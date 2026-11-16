import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import 'service_fichiers.dart';

/// LA LECTURE OCR DES SCANS AU POSTE (lots OCR-prep et OCR-C, portés de la clinique sœur vers l'architecture Baguidi) : AUCUN moteur choisi, AUCUN moteur livré, AUCUNE qualité promise.
///
/// Ce service enchaîne les gestes du domaine (`doc_ocr.dart`, `doc_ocr_correction.dart`) : il ne décide rien. Par défaut AUCUN moteur n'est branché et l'état de chaque scan dit exactement
/// « aucun moteur d'OCR installé sur ce poste ». Le jour où un moteur est branché ([enregistrer]) et choisi au réglage DE LA MÈRE, les scans sans couche texte entrent dans la file : un
/// fichier à la fois, borné en temps, reprise après arrêt, jamais deux files pour la même empreinte.
///
/// Où vivent les données :
///  - la FILE est une collection LOCALE au poste (`fileOcr`, une ligne par empreinte, jamais synchronisée : un traitement en cours ici n'est pas l'affaire d'un autre poste) ;
///  - les LECTURES (`lecturesOcr`) sont des MÉTADONNÉES du fichier : une fiche par version — lecture machine OU correction signée d'une personne —, identifiant déterministe, IMMUABLE
///    (garde du magasin), synchronisée par le journal (famille B : ajout seul, chiffrée vers le relais), JAMAIS vers un téléphone ;
///  - le RÉGLAGE (`reglagesOcr`, fiche `ocr`) se décide À LA MÈRE (famille R : elle seule écrit) et descend aux fileuls par la synchronisation ; un fileul le lit, ne le modifie pas, et dit
///    quand le moteur choisi n'est pas installé chez lui.

/// La file de lecture, collection LOCALE au poste.
const String ocrFile = 'fileOcr';

/// Les lectures (versions de texte lu par machine et corrections signées), collection synchronisée (famille B).
const String ocrLectures = 'lecturesOcr';

/// Le réglage de la lecture, décidé à la mère (famille R), une fiche d'identifiant `ocr`.
const String ocrReglages = 'reglagesOcr';

class ResultatFileOcr {
  const ResultatFileOcr.ok({this.fait = false, this.sha, this.version, this.nouvelle = false, this.deja = false, this.ecarte})
      : refus = null,
        ok = true;
  const ResultatFileOcr.refus(RefusFichier this.refus)
      : ok = false,
        fait = false,
        sha = null,
        version = null,
        nouvelle = false,
        deja = false,
        ecarte = null;
  final bool ok;
  final RefusFichier? refus;

  /// Un traitement a été mené à son terme (réussi ou en échec nommé).
  final bool fait;
  final String? sha;
  final String? version;
  final bool nouvelle;

  /// Déjà en file, déjà lu : rien à faire.
  final bool deja;

  /// Le code du refus qui a fait écarter ce fichier pour ce profil (droit, zone) : un autre profil le traitera.
  final String? ecarte;
}

class OcrPoste extends ChangeNotifier {
  OcrPoste(this.magasin, {bool Function()? estMere, this.accesCourant, RendeurPages? rendeur})
      : _rendeur = rendeur,
        estMere = estMere ?? (() => ServiceFichiers.de(magasin).estMere) {
    ServiceFichiers.de(magasin).ocr = this;
    magasin.collection(ocrLectures).garder((op, f) {
      final existantes = magasin.collection(ocrLectures).toutes;
      if (op == 'modifier') return 'Une lecture OCR est IMMUABLE : une relance ou une correction AJOUTE une version datée, elle ne réécrit pas l’ancienne.';
      if (op == 'archiver') return 'Une lecture OCR ne s’archive pas : elle reste lisible (RG-14), une nouvelle version devient la version courante.';
      if (op == 'inserer' && existantes.any((x) => x['id'] == f['id'])) return 'La version « ${f['id']} » existe déjà : une version ne se réécrit pas.';
      return null;
    });
    // Le réglage décidé à la mère arrive : une activation rattrape les scans déjà déposés (le fileul lit chez lui, avec son moteur).
    magasin.collection(ocrReglages).addListener(_surReglage);
  }

  final Magasin magasin;

  /// Ce poste est-il la mère ? (le réglage ne s'y décide que là).
  final bool Function() estMere;

  /// Ce que le PROFIL COURANT peut lire (catégories sensibles de la matrice) : la file de lecture n'ouvre que ce que l'agent connecté a le droit de lire. `null` : non branché, les
  /// documents du dossier patient sont alors écartés (le plus prudent) ; les courriers n'ont pas de zone.
  bool Function(String categorie)? Function()? accesCourant;

  RendeurPages? _rendeur;
  final Map<String, MoteurOcr> _moteurs = {};
  final Set<String> _ecartes = {};
  bool _occupe = false;
  Timer? _minuterie;

  /// La file tourne d'elle-même (une minuterie, un fichier par passe) : vrai en exploitation. Un test la coupe pour mener la file à la main ([traiterSuivant], [vider]).
  bool automatique = true;

  static final Expando<OcrPoste> _installes = Expando<OcrPoste>('OcrPoste');

  /// Le service installé pour ce magasin (posé par `main`, ou par un test), ou `null` : les écrans ne plantent jamais sans lui.
  static OcrPoste? de(Magasin m) => _installes[m];
  void installer() => _installes[magasin] = this;
  void rafraichir() => notifyListeners();

  void _surReglage() {
    if (pret) {
      balayer();
      demarrer();
    }
    notifyListeners();
  }

  // --- moteurs : injectables, AUCUN par défaut ---------------------------------------------------------------------------------------------

  void enregistrer(MoteurOcr m) {
    _moteurs[m.id] = m;
    notifyListeners();
  }

  void retirer([String? id]) {
    if (id == null) {
      _moteurs.clear();
    } else {
      _moteurs.remove(id);
    }
    notifyListeners();
  }

  void poserRendeur(RendeurPages? r) => _rendeur = r;
  Map<String, MoteurOcr> get moteurs => Map.unmodifiable(_moteurs);
  bool get moteurInstalle => _moteurs.isNotEmpty;

  // --- réglage : décidé à la mère, lu partout ------------------------------------------------------------------------------------------

  ReglageOcr get reglage => ocrReglageLire(magasin.collection(ocrReglages).parId('ocr'));

  /// Le moteur choisi AU RÉGLAGE, s'il est installé sur CE poste ; `null` sinon (et l'état le dit : un poste dont le moteur n'est pas disponible le dit).
  MoteurOcr? get moteurActif {
    final id = reglage.moteur;
    return id != null ? _moteurs[id] : null;
  }

  bool get pret => ocrPret(actif: reglage.actif, moteurActif: moteurActif != null);

  /// Le réglage est-il possible ICI : la mère seulement. Le droit de l'agent (écran des paramètres système) est le second contrôle, fait par [definirReglage].
  bool get reglageEstIci => estMere();

  /// Pose le réglage : réservé au POSTE MÈRE et à qui peut modifier l'écran des paramètres ([peutRegler], le droit de la matrice), motivé ; activer sans moteur installé SUR LA MÈRE est
  /// REFUSÉ en le nommant. Écrit, journalisé (RG-12) ; la mère le publie aux fileuls. Une activation rattrape les scans déjà déposés.
  ResultatFileOcr definirReglage({required bool peutRegler, required bool actif, required String? moteur, required String langue, required String? motif, int? delaiMs}) {
    final avant = reglage;
    final r = ocrDefinirReglage(
        estMere: estMere(),
        peutRegler: peutRegler,
        actif: actif,
        moteur: moteur,
        langue: langue,
        motif: motif,
        moteurs: _moteurs,
        avant: avant,
        delaiMs: delaiMs,
        regleLe: magasin.horloge().toUtc().toIso8601String(),
        reglePar: magasin.utilisateur);
    if (!r.ok) return ResultatFileOcr.refus(r.refus!);
    final col = magasin.collection(ocrReglages);
    final valeur = {'id': 'ocr', ...r.reglage!.toJson()};
    if (col.parId('ocr') == null) {
      col.inserer(valeur, prefixe: 'ROC');
    } else {
      col.mettreAJour('ocr', valeur, journaliser: false);
    }
    final m = (motif ?? '').trim();
    magasin.journaliser('Réglage de la lecture OCR des scans', 'M14', 'Réglage', 'ocr', {'actif': avant.actif, 'moteur': avant.moteur, 'langue': avant.langue},
        {'actif': actif, 'moteur': moteur, 'langue': r.reglage!.langue, 'motif': m.length > 40 ? m.substring(0, 40) : m});
    notifyListeners();
    return const ResultatFileOcr.ok();
  }

  // --- données ----------------------------------------------------------------------------------------------------------------------------------

  CollectionMagasin get _registre => magasin.collection('fichiers');
  CollectionMagasin get _lectures => magasin.collection(ocrLectures);
  CollectionMagasin get _file => magasin.collection(ocrFile);

  String _idFile(String sha) => 'OCQ-${sha.substring(0, 16)}';
  Fiche? _entreeFile(String sha) => _file.parId(_idFile(sha));
  Fiche? _registreDe(String sha) => _registre.parId(sha);

  /// Le fichier porte-t-il une couche texte native ? Elle prime toujours sur l'OCR.
  bool natif(String sha, [Map<String, Object?>? scan]) => scan?['texteIndexe'] == true || '${_registreDe(sha)?['texte'] ?? ''}'.isNotEmpty;

  /// Les versions d'une empreinte (lectures machine et corrections), de la plus ancienne à la plus récente.
  List<FicheDoc> versionsDe(String sha) => ocrVersionsOrdonnees([
        for (final v in _lectures.actives)
          if (v['sha256'] == sha) v
      ]);
  FicheDoc? versionCourante(String sha) => ocrVersionCourante(versionsDe(sha));

  /// L'état d'indexation d'un fichier (l'objet `scan` d'une fiche) : couche texte, lu par machine (à vérifier), corrigé par une personne, en attente, en cours, en échec, non indexé.
  EtatIndexationOcr etatDe(Map<String, Object?> scan) {
    final sha = '${scan['sha256']}';
    final r = reglage;
    return ocrEtatIndexation(
        natif: natif(sha, scan),
        versions: versionsDe(sha),
        file: _entreeFile(sha),
        moteurInstalle: moteurInstalle,
        actif: r.actif,
        moteurActif: moteurActif != null,
        moteurChoisi: r.moteur);
  }

  /// Le texte (mots normalisés) que la recherche lit : la couche native PRIME ; sinon la version COURANTE (la correction humaine, si elle existe), seulement si le profil lit la zone du
  /// document ([peutCategorie] : la matrice, jamais un nom de rôle).
  String texteOcr(String sha, {required String famille, String? type, required bool Function(String categorie)? peutCategorie}) {
    final reg = _registreDe(sha);
    final texteNatif = '${reg?['texte'] ?? ''}';
    return ocrTexteRecherche(natifIndexe: texteNatif.isNotEmpty, natifTexte: texteNatif, versions: versionsDe(sha), famille: famille, type: type, peutCategorie: peutCategorie);
  }

  // --- la file ------------------------------------------------------------------------------------------------------------------------------------

  /// Un scan entre dans la file (idempotent : une seule ligne par empreinte). Rend le refus nommé, ou `deja` s'il n'y a rien à faire.
  ResultatFileOcr demander(String sha, {String? famille, String? type, bool relance = false}) {
    final reg = _registreDe(sha);
    final f = _entreeFile(sha);
    final r = reglage;
    final d = ocrDemander(
        registre: reg == null ? null : {'sha256': sha, 'texteIndexe': '${reg['texte'] ?? ''}'.isNotEmpty, if (f != null) 'ocr': {...f}},
        versions: versionsDe(sha),
        moteurInstalle: moteurInstalle,
        actif: r.actif,
        moteurActif: moteurActif != null,
        relance: relance,
        famille: famille,
        type: type,
        maintenant: magasin.horloge().toUtc().toIso8601String(),
        par: magasin.utilisateur);
    if (d.refus != null) return ResultatFileOcr.refus(d.refus!);
    if (d.deja) return const ResultatFileOcr.ok(deja: true);
    final ligne = {'id': _idFile(sha), 'sha256': sha, ...d.etat!};
    if (f == null) {
      _file.inserer(ligne, prefixe: 'OCQ');
    } else {
      _file.mettreAJour(_idFile(sha), ligne, journaliser: false);
    }
    magasin.journaliser(relance ? 'Relance de la lecture OCR' : 'Lecture OCR demandée', 'M13', 'Lecture OCR', docEmpreinteAbregee(sha), {'empreinte': docEmpreinteAbregee(sha)}, {'etat': 'en_attente'});
    _ecartes.remove(sha);
    notifyListeners();
    return const ResultatFileOcr.ok();
  }

  /// Après un dépôt : le scan sans couche texte entre dans la file SI une lecture est possible ; sinon rien ne se met en file et l'état dit pourquoi.
  void apresDepot(String sha, {required String famille, String? type}) {
    if (natif(sha)) return;
    final r = demander(sha, famille: famille, type: type);
    if (r.ok && !r.deja) demarrer();
  }

  /// Les scans sans texte, sans lecture et hors file qu'une activation du réglage doit rattraper. Rend le nombre mis en file.
  int balayer() {
    if (!pret) return 0;
    var n = 0;
    for (final entry in famillesDocuments.entries) {
      for (final f in magasin.collection(entry.value.collection).actives) {
        final x = docScan(f);
        if (x == null) continue;
        final sha = '${x['sha256']}';
        if (natif(sha, x) || _entreeFile(sha) != null || versionCourante(sha) != null) continue;
        final r = demander(sha, famille: entry.key, type: entry.key == docFamillePatient ? '${f['type']}' : null);
        if (r.ok && !r.deja) n++;
      }
    }
    return n;
  }

  /// Reprise après arrêt : un traitement « en cours » depuis plus de deux délais est remis en attente, ou en échec après trois essais. Rend le nombre repris.
  int reprendre() {
    var n = 0;
    final maintenant = magasin.horloge();
    for (final f in List<Fiche>.of(_file.toutes)) {
      final r = ocrReprendre(f, maintenant: maintenant, delaiMs: reglage.delaiMs);
      if (r == null) continue;
      _file.mettreAJour(f['id'], r, journaliser: false);
      magasin.journaliser('Lecture OCR reprise après arrêt', 'M13', 'Lecture OCR', docEmpreinteAbregee('${f['sha256']}'), {'etat': 'en_cours'}, {'etat': r['etat']});
      n++;
    }
    if (n > 0) notifyListeners();
    return n;
  }

  /// La commande « Relancer la lecture » est-elle OFFERTE ? Absente sinon, jamais grisée.
  bool relancePossible(Map<String, Object?> scan, {required bool peutDeposer}) => ocrRelancePossible(peutDeposer: peutDeposer, pret: pret, etat: etatDe(scan).etat);

  /// La relance : le moteur la refuse aussi sans le droit (masquer un bouton ne protège rien).
  ResultatFileOcr relancer(Map<String, Object?> scan, {required bool peutDeposer, required String famille, String? type}) {
    final refus = ocrRefusRelance(peutDeposer: peutDeposer, moteurInstalle: moteurInstalle, actif: reglage.actif, moteurActif: moteurActif != null, sansPiece: scan['sha256'] == null);
    if (refus != null) return ResultatFileOcr.refus(refus);
    final r = demander('${scan['sha256']}', famille: famille, type: type, relance: true);
    if (r.ok && !r.deja) demarrer();
    return r;
  }

  /// Traite UN fichier de la file, sous le profil de l'agent connecté. Jamais deux traitements à la fois. Un refus de zone n'est pas un échec du fichier : ce profil ne le lit pas, un autre le
  /// traitera.
  Future<ResultatFileOcr> traiterSuivant() async {
    if (_occupe) return const ResultatFileOcr.ok();
    if (!pret) {
      return ResultatFileOcr.refus(!moteurInstalle
          ? ocrRefus(CodeOcr.moteurAbsent, ocrRaisonSansMoteur)
          : (!reglage.actif ? ocrRefus(CodeOcr.desactive, 'la lecture OCR est désactivée au réglage') : ocrRefus(CodeOcr.moteurAbsent, 'le moteur choisi au réglage de la mère n’est pas installé sur ce poste')));
    }
    final choisi = ocrChoisirSuivant([for (final f in _file.toutes) {'sha256': f['sha256'], 'ocr': {...f}}], ecartes: _ecartes);
    if (choisi == null) return const ResultatFileOcr.ok();
    final suivant = (choisi['ocr']! as Map).cast<String, Object?>();
    final sha = '${suivant['sha256']}';
    final famille = '${suivant['famille'] ?? docFamilleCourrier}';
    final type = suivant['type'] as String?;
    if (famille == docFamillePatient) {
      final peut = accesCourant?.call();
      if (peut == null || !docPeutLire(peut, type)) {
        _ecartes.add(sha);
        return ResultatFileOcr.ok(ecarte: peut == null ? 'SESSION_REQUISE' : CodeOcr.zoneRefusee);
      }
    }
    _occupe = true;
    try {
      final List<int>? lus;
      try {
        lus = await ServiceFichiers.de(magasin).lireOctets(famille: famille, sha: sha);
      } catch (_) {
        _ecartes.add(sha); // injoignable ou altéré : rien à lire pour l'instant, la synchronisation le ramènera
        return const ResultatFileOcr.ok(ecarte: 'FICHIER_ABSENT');
      }
      if (lus == null) {
        _ecartes.add(sha);
        return const ResultatFileOcr.ok(ecarte: 'FICHIER_ABSENT');
      }
      final octets = Uint8List.fromList(lus);
      final essais = ((suivant['essais'] as num?) ?? 0).toInt() + 1;
      _file.mettreAJour(suivant['id'], {'etat': 'en_cours', 'debutLe': magasin.horloge().toUtc().toIso8601String(), 'essais': essais}, journaliser: false);
      magasin.journaliser('Lecture OCR commencée', 'M13', 'Lecture OCR', docEmpreinteAbregee(sha), {'empreinte': docEmpreinteAbregee(sha)}, {'etat': 'en_cours'});
      final r = reglage;
      final lu = await ocrLireFichier(moteur: moteurActif, octets: octets, formatId: docFormatDesOctets(octets)?.id ?? 'inconnu', mime: null, langue: r.langue, delaiMs: r.delaiMs, rendeur: _rendeur);
      if (!lu.ok) {
        _file.mettreAJour(suivant['id'], {'etat': 'echec', 'code': lu.refus!.code, 'raison': lu.refus!.motif, 'geste': lu.refus!.geste, 'finLe': magasin.horloge().toUtc().toIso8601String()}, journaliser: false);
        magasin.journaliser('Lecture OCR en échec', 'M13', 'Lecture OCR', docEmpreinteAbregee(sha), {'empreinte': docEmpreinteAbregee(sha)}, {'etat': 'echec', 'code': lu.refus!.code});
        notifyListeners();
        return ResultatFileOcr.ok(fait: true, sha: sha);
      }
      final m = moteurActif!;
      final fiche = ocrNouvelleLecture(
          sha: sha,
          texte: lu.texte,
          moteur: m.id,
          moteurVersion: m.version,
          langue: r.langue,
          ocrLe: magasin.horloge().toUtc().toIso8601String(),
          ocrPar: magasin.utilisateur,
          declencheur: '${suivant['declencheur'] ?? 'automatique'}',
          pages: lu.pages,
          dureeMs: lu.dureeMs,
          confiance: lu.confiance);
      final nouvelle = _lectures.parId(fiche['id']) == null;
      if (nouvelle) {
        _lectures.inserer(fiche, prefixe: 'OCR');
        magasin.journaliser('Lecture OCR d’un scan', 'M13', 'Lecture OCR', '${fiche['id']}', null, {'empreinte': docEmpreinteAbregee(sha), 'moteur': m.id, 'mots': fiche['nbMots'], 'pages': lu.pages});
      }
      // La ligne de file est terminée : elle ne se supprime pas (RG-14), elle est marquée faite, et ne compte plus comme file.
      _file.mettreAJour(suivant['id'], {'etat': 'termine', 'finLe': magasin.horloge().toUtc().toIso8601String()}, journaliser: false);
      magasin.journaliser('Lecture OCR terminée', 'M13', 'Lecture OCR', docEmpreinteAbregee(sha), {'etat': 'en_cours'}, {'etat': 'ocr_indexe', 'version': fiche['id']});
      notifyListeners();
      return ResultatFileOcr.ok(fait: true, sha: sha, version: '${fiche['id']}', nouvelle: nouvelle);
    } finally {
      _occupe = false;
    }
  }

  /// Vide la file jusqu'à ce qu'il n'y ait plus rien à lire (tests, reprise à l'ouverture d'un écran).
  Future<int> vider([int max = 50]) async {
    reprendre();
    var faits = 0;
    while (faits < max) {
      final r = await traiterSuivant();
      if (!r.fait) break;
      faits++;
    }
    return faits;
  }

  /// Fait tourner la file sans bloquer la saisie : un fichier par passe, la main rendue entre deux. S'arrête de lui-même quand la file est vide.
  void demarrer() {
    if (!automatique || _minuterie != null || !pret) return;
    _minuterie = Timer(const Duration(milliseconds: 50), () async {
      _minuterie = null;
      reprendre();
      final r = await traiterSuivant();
      if (r.fait) demarrer();
    });
  }

  void arreter() {
    _minuterie?.cancel();
    _minuterie = null;
  }

  // --- la correction signée (lot C) ------------------------------------------------------------------------------------------------------------

  /// La commande « Corriger le texte lu » est-elle OFFERTE ? Il faut un texte lu par machine à corriger (pas de couche native), le droit d'ÉDITER l'écran du document et — pour un document du
  /// dossier patient — le droit de LIRE son type. ABSENTE sinon, jamais grisée.
  bool correctionPossible(Map<String, Object?> scan, {required String famille, String? type, required bool peutEditer, bool Function(String categorie)? peutCategorie}) {
    final sha = '${scan['sha256']}';
    if (natif(sha, scan) || versionCourante(sha) == null) return false;
    return ocrRefusCorrection(peutEditerEcran: peutEditer, famille: famille, type: type, peutCategorie: peutCategorie) == null;
  }

  /// CORRIGE le texte lu : le moteur refuse sans le droit (masquer un bouton ne protège rien) ; la correction est une NOUVELLE VERSION signée (auteur de la session, date et heure, motif
  /// facultatif), le texte machine reste ; la version humaine devient la courante, donc celle qui est indexée. Rend la version écrite dans [ResultatFileOcr.version].
  ResultatFileOcr corriger(
      {required Map<String, Object?> scan,
      required String texte,
      required String famille,
      String? type,
      required bool peutEditer,
      bool Function(String categorie)? peutCategorie,
      String? motif,
      String? corrigeDe}) {
    final refusDroit = ocrRefusCorrection(peutEditerEcran: peutEditer, famille: famille, type: type, peutCategorie: peutCategorie);
    if (refusDroit != null) return ResultatFileOcr.refus(refusDroit);
    final sha = '${scan['sha256']}';
    final r = ocrNouvelleCorrection(
        sha: sha,
        texte: texte,
        versions: versionsDe(sha),
        natif: natif(sha, scan),
        auteur: magasin.utilisateur,
        auteurId: magasin.acteur?.utilisateurId,
        corrigeLe: magasin.horloge().toUtc().toIso8601String(),
        corrigeDe: corrigeDe,
        motif: motif);
    if (r.refus != null) return ResultatFileOcr.refus(r.refus!);
    final fiche = r.fiche!;
    if (_lectures.parId(fiche['id']) != null) return ResultatFileOcr.ok(sha: sha, version: '${fiche['id']}', deja: true);
    _lectures.inserer(fiche, prefixe: 'COR');
    final fam = famillesDocuments[famille]!;
    magasin.journaliser('Correction du texte lu d’un scan', fam.module, fam.entite, '${fiche['id']}', {'version': fiche['corrigeDe']},
        {'empreinte': docEmpreinteAbregee(sha), 'mots': fiche['nbMots'], 'motif': '${fiche['motif']}'.length > 40 ? '${fiche['motif']}'.substring(0, 40) : fiche['motif']});
    notifyListeners();
    return ResultatFileOcr.ok(sha: sha, version: '${fiche['id']}', nouvelle: true);
  }

  /// L'historique lisible d'un scan (de la plus récente à la plus ancienne), ou vide si le profil ne lit pas le document.
  List<Map<String, Object?>> historique(String sha, {required String famille, String? type, bool Function(String categorie)? peutCategorie}) {
    if (famille == docFamillePatient && (peutCategorie == null || !docPeutLire(peutCategorie, type))) return const [];
    return ocrHistorique(versionsDe(sha));
  }
}
