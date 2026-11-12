import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';

/// LE SERVICE DES SCANS DU POSTE : ce que les écrans (courriers M13, documents du dossier patient M1) appellent pour déposer, lire, remplacer, retirer, migrer.
///
/// Il ne range rien lui-même : le fichier va chez la MÈRE ([DocStockage] : le client des fichiers, qui parle à la mère par le canal de synchronisation scellé, ou
/// le stock local quand ce poste est la mère). Le magasin ne garde que les métadonnées (champ `scan`, versions `scansAnterieurs`) et le REGISTRE par empreinte
/// (collection `fichiers` : taille, pages, texte indexé). Chaque geste se journalise (RG-12) : dépôt, consultation, téléchargement, retrait, réglage.
///
/// Les règles (formats, taille, nom normalisé, versions, doublons, migration, droits par catégorie sensible) sont celles du domaine ; ce service les enchaîne.
class DocAvertissement implements Exception {
  const DocAvertissement(this.ailleurs, this.motif);
  final Map<String, Object?> ailleurs;
  final String motif;
  @override
  String toString() => motif;
}

typedef FamilleDoc = ({String collection, String module, String entite});

const Map<String, FamilleDoc> famillesDocuments = {
  docFamilleCourrier: (collection: 'courriers', module: 'M13', entite: 'Courrier'),
  docFamillePatient: (collection: 'documentsPatient', module: 'M1', entite: 'Document patient'),
};

/// Écrit un fichier téléchargé et rend son chemin. Posé en variable : les tests n'écrivent pas sur le disque de la machine.
/// Par défaut : `$SIGH_EXPORTS`, sinon « Téléchargements » de l'utilisateur, sinon le dossier temporaire.
Future<String> Function(String nom, List<int> octets) enregistrerTelechargement = (nom, octets) async {
  Directory dossier = Directory.systemTemp;
  final env = Platform.environment;
  final cible = env['SIGH_EXPORTS'];
  if (cible != null && cible.isNotEmpty) {
    dossier = Directory(cible);
  } else {
    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home != null) {
      for (final n in ['Downloads', 'Téléchargements']) {
        final d = Directory('$home${Platform.pathSeparator}$n');
        if (d.existsSync()) {
          dossier = d;
          break;
        }
      }
    }
  }
  await dossier.create(recursive: true);
  final f = File('${dossier.path}${Platform.pathSeparator}$nom');
  await f.writeAsBytes(octets, flush: true);
  return f.path;
};

/// Ouvre un fichier avec l'application du système (le repli quand le PDF n'a pas de moteur de rendu dans le poste). Posé en variable pour les tests.
Future<bool> Function(String chemin) ouvrirAvecApplication = (chemin) async {
  try {
    final r = Platform.isWindows
        ? await Process.run('cmd', ['/c', 'start', '', chemin])
        : await Process.run(Platform.isMacOS ? 'open' : 'xdg-open', [chemin]);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
};

class ResultatDepot {
  const ResultatDepot({required this.fiche, required this.scan, required this.annuler, required this.remplacement, required this.avertissementIndexation});
  final Map<String, Object?> fiche;
  final Map<String, Object?> scan;
  final VoidCallback annuler;
  final bool remplacement;

  /// « Texte non indexé » : un scan image se dit, il ne se tait pas.
  final String? avertissementIndexation;
}

class ServiceFichiers {
  ServiceFichiers._(this.magasin);
  final Magasin magasin;
  static final Expando<ServiceFichiers> _par = Expando('ServiceFichiers');
  static ServiceFichiers de(Magasin m) => _par[m] ??= ServiceFichiers._(m);

  /// Le stockage pour une famille de documents ; `null` : le poste n'est pas branché à un dossier de scans (les dépôts sont refusés en le disant).
  DocStockage Function(String famille)? stockagePour;

  /// « Où sont mes scans ? » : le chemin sur la mère et ce qu'elle tient (`dossier`, `fichiers`, `octets`).
  Future<Map<String, Object?>> Function()? lireInfo;

  /// Ce poste est la mère : il peut déplacer le dossier. Un fileul n'a pas cette commande.
  Future<Map<String, Object?>> Function(String dossier)? changerDossierMere;

  bool get branche => stockagePour != null;
  bool get estMere => changerDossierMere != null;

  DocStockage _stockage(String famille) {
    final f = stockagePour;
    if (f == null) {
      throw const DocErreur('FICHIERS_NON_BRANCHES', 'Ce poste n’est relié à aucun dossier de scans : la mère n’est pas joignable ou le poste n’est pas rattaché.', 'Vérifier que la mère répond (Ce poste, Synchronisation), puis réessayer.');
    }
    return f(famille);
  }

  // --- réglages ---------------------------------------------------------------------------------------------------
  Fiche? _reglage(String id) => magasin.collection('reglages').parId(id);

  /// La taille maximale en force (octets) : le réglage de la clinique, sinon 10 Mo « à valider ».
  int tailleMax() => docTailleMax(_reglage('documentsBornes')?['valeur']);

  bool get tailleMaxValidee => _reglage('documentsBornes') != null;

  /// Règle la taille maximale : bornée, motif obligatoire, journalisée. Rend le refus nommé, ou `null`.
  DocErreur? reglerTailleMax(int octets, String motif) {
    final refus = docControlerReglageTaille(octets, motif);
    if (refus != null) return refus;
    final col = magasin.collection('reglages');
    final avant = tailleMax();
    final fiche = {'id': 'documentsBornes', 'valeur': octets, 'motif': motif.trim(), 'modifiePar': magasin.utilisateur, 'modifieLe': magasin.horloge().toIso8601String()};
    if (col.parId('documentsBornes') == null) {
      col.inserer(fiche, prefixe: 'REG');
    } else {
      col.mettreAJour('documentsBornes', fiche);
    }
    magasin.journaliser('Taille maximale des scans', 'M14', 'Réglage', 'documentsBornes', {'octets': avant}, {'octets': octets, 'motif': motif.trim()});
    return null;
  }

  /// Le chemin des scans à AFFICHER : celui de la mère quand elle répond, sinon le dernier connu. `null` : inconnu.
  Future<String?> cheminDesScans() async {
    try {
      final i = await lireInfo?.call();
      final d = i?['dossier'];
      if (d is String && d.isNotEmpty) {
        _memoriserChemin(d);
        return d;
      }
    } catch (_) {/* la mère ne répond pas : on dit le dernier chemin connu */}
    final k = _reglage('dossierScans')?['chemin'];
    return k is String && k.isNotEmpty ? k : null;
  }

  void _memoriserChemin(String d) {
    final col = magasin.collection('reglages');
    final f = col.parId('dossierScans');
    if (f != null && f['chemin'] == d) return;
    final fiche = {'id': 'dossierScans', 'chemin': d};
    if (f == null) {
      col.ajouterSansJournal(fiche, notifier: false);
    } else {
      f['chemin'] = d;
    }
  }

  /// MÈRE : déplace le dossier des scans (copie vérifiée, ancien dossier conservé). Refus nommé pour un fileul.
  Future<Map<String, Object?>> reglerDossier(String chemin, String motif) async {
    final f = changerDossierMere;
    if (f == null) {
      throw const DocErreur('REGLAGE_RESERVE_A_LA_MERE', 'Le dossier des scans se règle sur le poste mère : les fichiers y vivent.', 'Faire le réglage depuis le poste mère.');
    }
    if (motif.trim().isEmpty) throw const DocErreur('MOTIF_REQUIS', 'Le motif du changement est obligatoire (journal RG-12).', 'Renseigner le motif.');
    final avant = await cheminDesScans();
    final r = await f(chemin);
    _memoriserChemin('${r['nouveau']}');
    magasin.journaliser('Dossier des scans déplacé', 'M14', 'Réglage', 'dossierScans', {'chemin': avant}, {'chemin': r['nouveau'], 'copies': r['copies'], 'motif': motif.trim()});
    return r;
  }

  // --- registre par empreinte ------------------------------------------------------------------------------------
  CollectionMagasin get _registre => magasin.collection('fichiers');

  /// Le texte extrait d'une pièce PDF à couche texte (mots normalisés), ou `''`.
  String texteDe(Map<String, Object?> fiche) {
    final sha = docScan(fiche)?['sha256'];
    return sha == null ? '' : '${_registre.parId(sha)?['texte'] ?? ''}';
  }

  void _enregistrerEmpreinte(String sha, {required int taille, required String mime, int? pages, required String texte, required String famille}) {
    final f = _registre.parId(sha);
    if (f == null) {
      _registre.inserer({'id': sha, 'taille': taille, 'mime': mime, 'pages': pages, 'texte': texte, 'premiereDate': magasin.horloge().toIso8601String(), 'familles': [famille]}, prefixe: 'FIC');
    } else {
      final fams = {...((f['familles'] as List?) ?? const []).map((e) => '$e'), famille}.toList();
      _registre.mettreAJour(sha, {'familles': fams}, journaliser: false);
    }
  }

  // --- gestes ---------------------------------------------------------------------------------------------------
  /// DÉPOSE un scan sur une fiche (première pièce ou remplacement). Contrôles dans l'ordre : droit de la zone, format et taille, doublon (même fiche : refus ;
  /// autre fiche : [DocAvertissement] sauf [confirmerAilleurs]). Le fichier part chez la mère SOUS SON NOM NORMALISÉ ; la fiche reçoit ses métadonnées ;
  /// le registre par empreinte reçoit le texte d'un PDF à couche texte. Rend le résultat et la fonction qui l'ANNULE (RG-14 : l'annulation retire la pièce de la
  /// fiche et la range aux versions antérieures ; le fichier reste).
  Future<ResultatDepot> deposer({
    required String famille,
    required Object? ficheId,
    required String nomOrigine,
    required List<int> octets,
    bool Function(String categorie)? peutCategorie,
    bool confirmerAilleurs = false,
  }) async {
    final fam = famillesDocuments[famille]!;
    final col = magasin.collection(fam.collection);
    final fiche = col.parId(ficheId);
    if (fiche == null) throw const DocErreur('FICHE_INTROUVABLE', 'La fiche n’existe plus.', 'Rouvrir le registre.');
    if (famille == docFamillePatient && peutCategorie != null && !docPeutLire(peutCategorie, fiche['type'])) {
      throw DocErreur('ZONE_REFUSEE', 'Ce profil ne peut pas déposer un document de type « ${fiche['type']} » : ${mentionReservee(docCategoriesManquantes(peutCategorie, fiche['type']).first)}.', 'Demander à un profil habilité.');
    }
    final refus = docControlerDepot(octets: octets, nomOrigine: nomOrigine, famille: famille, tailleMaxReglee: _reglage('documentsBornes')?['valeur']);
    if (refus != null) throw refus;
    final sha = docSha256(octets);
    final d = docControlerDoublon(
        sha256: sha,
        fiche: fiche,
        fiches: col.actives,
        memePortee: famille == docFamillePatient ? (f) => f['patientId'] != null && f['patientId'] == fiche['patientId'] : null);
    if (d.refus) throw docRefusDoublon(d.memeFiche!);
    if (d.avertissement && !confirmerAilleurs) {
      final a = d.ailleurs!;
      throw DocAvertissement(a, 'Ce fichier (empreinte ${docEmpreinteAbregee(sha)}) est déjà rattaché à ${a['reference'] ?? 'une autre fiche'}.');
    }
    final fmt = docFormatDesOctets(octets)!;
    final version = docProchaineVersion(fiche);
    final nom = docNomNormalise(famille: famille, fiche: fiche, ext: fmt.extension, version: version);
    // Le texte d'un PDF à couche texte, extrait AVANT l'envoi (un PDF illisible n'empêche pas le dépôt : il est « texte non indexé »).
    final texte = fmt.id == 'pdf' ? docExtraireTextePdf(octets) : null;
    await _stockage(famille).deposer(octets: octets, sha256: sha, nomNormalise: nom);
    final maintenant = magasin.horloge().toIso8601String();
    final meta = docMetaScan(
        sha256: sha, nomOrigine: nomOrigine, nomNormalise: nom, mime: fmt.mime, taille: octets.length, version: version, deposePar: magasin.utilisateur, deposeLe: maintenant,
        pages: texte?.pages == 0 ? null : texte?.pages, texteIndexe: texte?.indexe ?? false);
    _enregistrerEmpreinte(sha, taille: octets.length, mime: fmt.mime, pages: texte?.pages, texte: texte?.indexe == true ? texte!.texte : '', famille: famille);
    final patch = docPatchDepot(fiche, meta, par: magasin.utilisateur, le: maintenant);
    final remplacement = docScan(fiche) != null;
    final annuler = col.mettreAJour(ficheId, patch, journaliser: false);
    magasin.journaliser(remplacement ? 'Remplacement d’un scan' : 'Dépôt d’un scan', fam.module, fam.entite, '${fiche['reference'] ?? fiche['id']}',
        remplacement ? {'sha256': docScan({'scan': patch['scansAnterieurs'] is List ? (patch['scansAnterieurs'] as List).last : null})?['sha256']} : null,
        {'sha256': sha, 'nom': nom, 'taille': octets.length, 'version': version});
    return ResultatDepot(
        fiche: col.parId(ficheId)!,
        scan: meta,
        annuler: annuler,
        remplacement: remplacement,
        avertissementIndexation: fmt.id == 'pdf' && texte != null && !texte.indexe ? texte.raison : (fmt.id != 'pdf' ? 'Image : texte non indexé (l’OCR est une phase ultérieure).' : null));
  }

  /// RETIRE la pièce d'une fiche : motif obligatoire, la pièce passe aux versions antérieures, le fichier RESTE chez la mère (RG-14). Rend la fonction qui annule.
  VoidCallback retirer({required String famille, required Object? ficheId, required String motif}) {
    final fam = famillesDocuments[famille]!;
    final col = magasin.collection(fam.collection);
    final fiche = col.parId(ficheId)!;
    final patch = docPatchRetrait(fiche, par: magasin.utilisateur, le: magasin.horloge().toIso8601String(), motif: motif);
    final sha = docScan(fiche)!['sha256'];
    final annuler = col.mettreAJour(ficheId, patch, journaliser: false);
    magasin.journaliser('Retrait d’un scan', fam.module, fam.entite, '${fiche['reference'] ?? fiche['id']}', {'sha256': sha}, {'motif': motif.trim()});
    return () {
      annuler();
      magasin.journaliser('Retrait d’un scan annulé', fam.module, fam.entite, '${fiche['reference'] ?? fiche['id']}', null, {'sha256': sha});
    };
  }

  /// LIT les octets de la pièce (vérifiés : l'empreinte est recalculée). Journalisé (RG-12). [version] : une version antérieure, sinon la pièce courante.
  Future<Uint8List> lire({
    required String famille,
    required Map<String, Object?> fiche,
    Map<String, Object?>? version,
    bool Function(String categorie)? peutCategorie,
    String action = 'Consultation d’un scan',
  }) async {
    final fam = famillesDocuments[famille]!;
    if (famille == docFamillePatient && peutCategorie != null && !docPeutLire(peutCategorie, fiche['type'])) {
      throw DocErreur('ZONE_REFUSEE', 'Ce profil ne peut pas lire un document de type « ${fiche['type']} ».', 'Demander à un profil habilité.');
    }
    final s = version ?? docScan(fiche);
    if (s == null) throw const DocErreur('SANS_PIECE', 'Cette fiche ne porte aucun fichier.', 'Déposer un scan d’abord.');
    final o = await _stockage(famille).lire('${s['sha256']}');
    if (o == null) {
      throw DocErreur('FICHIER_ABSENT', 'La mère ne détient pas le fichier ${s['nomNormalise']}.', 'Vérifier le dossier des scans de la mère (contrôle, puis restauration depuis la sauvegarde).');
    }
    magasin.journaliser(action, fam.module, fam.entite, '${fiche['reference'] ?? fiche['id']}', null, {'sha256': s['sha256'], 'nom': s['nomNormalise']});
    return Uint8List.fromList(o);
  }

  /// TÉLÉCHARGE sous le NOM NORMALISÉ : rend le chemin écrit.
  Future<String> telecharger({required String famille, required Map<String, Object?> fiche, Map<String, Object?>? version, bool Function(String categorie)? peutCategorie}) async {
    final s = version ?? docScan(fiche)!;
    final o = await lire(famille: famille, fiche: fiche, version: version, peutCategorie: peutCategorie, action: 'Téléchargement d’un scan');
    return enregistrerTelechargement('${s['nomNormalise']}', o);
  }

  /// Ouvre la pièce avec l'application du système (le repli du PDF). Une copie temporaire sous le nom normalisé.
  Future<bool> ouvrir({required String famille, required Map<String, Object?> fiche, Map<String, Object?>? version, bool Function(String categorie)? peutCategorie}) async {
    final s = version ?? docScan(fiche)!;
    final o = await lire(famille: famille, fiche: fiche, version: version, peutCategorie: peutCategorie);
    final tmp = await Directory.systemTemp.createTemp('sigh-scan-');
    final f = File('${tmp.path}${Platform.pathSeparator}${s['nomNormalise']}');
    await f.writeAsBytes(o, flush: true);
    return ouvrirAvecApplication(f.path);
  }

  /// MIGRE les documents du dossier patient encore en base64 vers le dossier des scans : empreinte relue AVANT retrait du base64 (règle du domaine).
  Future<DocRapportMigration> migrerBase64() async {
    final col = magasin.collection('documentsPatient');
    final st = _stockage(docFamillePatient);
    final rapport = await docMigrerBase64(
        fiches: col.toutes,
        stockage: st,
        par: magasin.utilisateur,
        le: magasin.horloge().toIso8601String(),
        tailleMaxReglee: _reglage('documentsBornes')?['valeur'],
        pages: (o, m) => m == 'application/pdf' ? docExtraireTextePdf(o).pages : null,
        texteIndexe: (o, m) => m == 'application/pdf' && docExtraireTextePdf(o).indexe,
        appliquer: (id, patch) async {
          final scan = (patch['scan'] as Map).cast<String, Object?>();
          final f = col.parId(id)!;
          final donnees = docDecoderDataUri(f['donnees']);
          final pdf = scan['mime'] == 'application/pdf' && donnees != null ? docExtraireTextePdf(donnees.octets) : null;
          _enregistrerEmpreinte('${scan['sha256']}', taille: (scan['taille'] as num).toInt(), mime: '${scan['mime']}', pages: pdf?.pages, texte: pdf?.indexe == true ? pdf!.texte : '', famille: docFamillePatient);
          col.mettreAJour(id, patch, journaliser: false);
        });
    magasin.journaliser('Migration des documents patient hors du magasin', 'M1', 'Document patient', 'migration-base64', null,
        {'migrees': rapport.migrees.length, 'refusees': [for (final r in rapport.refusees) '${r.fiche}: ${r.code}'], 'ignorees': rapport.ignorees});
    return rapport;
  }

  /// Combien de fiches portent encore un base64 (la migration a-t-elle à faire ?).
  int enBase64() => magasin.collection('documentsPatient').toutes.where((f) => '${f['donnees'] ?? ''}'.isNotEmpty).length;
}
