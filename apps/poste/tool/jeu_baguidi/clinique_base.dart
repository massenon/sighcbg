// L'OUTILLAGE COMMUN DU SOUS-LOT CLINIQUE : le déroulé chronologique des événements, l'adaptateur du magasin vers le moteur de consultation
// (`StockCs`) et les gestes de caisse (émission, encaissement, avoir) qui appellent les MOTEURS de `packages/domaine` et rien d'autre.
//
// Pourquoi un déroulé chronologique : les numéros de pièce (FN-2026-00001, CAI-2026-00001, LAB-00001, C00001…) suivent le REGISTRE, plus grand rang plus un.
// Pour qu'une facture du 3 août porte un numéro plus petit qu'une facture du 3 octobre, tout ce qui s'écrit passe par une file triée par date et exécutée
// dans l'ordre. Un événement peut en planifier d'autres (le prélèvement du lendemain, l'avoir de la semaine suivante).
import 'package:sigh_domaine/sigh_domaine.dart' as d;
import 'package:sigh_poste/donnees/magasin.dart';

import 'contexte.dart';

/// Le caissier qui signe les encaissements du jeu : le seul poste comptable nommé au personnel qui tienne la caisse.
const String caissierDuJeu = 'ZIME Nadège';

/// Le médecin du travail et de médecine générale : le seul médecin de la clinique.
const String medecinNom = 'IDOHOU Abraham';
const String medecinSoignantId = 'SOI01';
const String infirmierNom = 'AKONDE Octave';
const String infirmierSoignantId = 'SOI02';

String pad(int n, int l) => n.toString().padLeft(l, '0');

/// Un instant UTC (le jeu ne dépend jamais du fuseau du poste qui le génère).
DateTime instant(DateTime jour, int h, [int mn = 0]) => DateTime.utc(jour.year, jour.month, jour.day, h, mn);

String iso8601(DateTime t) => t.toUtc().toIso8601String();

/// La NORMALISATION de démonstration d'une vente soldée (MECeF, lot M1 : toute vente est normalisée, et l'émission laisse la pièce `en_attente`). Les
/// contrôles et les montants entiers sont ceux du domaine (`preparerNormalisation`) ; le numéro est celui de l'appareil de démonstration, marqué
/// `mecefSimule` (jamais un numéro fiscal). Une vente que le domaine refuserait reste `en_attente`, comme au poste.
///
/// LE TAUX D'AIB SUIT LA RÈGLE DU POSTE (D1) : une pièce sans taux reçoit le taux ARRÊTÉ du barème en vigueur à sa date pour la situation de son acheteur, sinon
/// le taux de repli des Paramètres (0 %) — la même fonction que `normaliserVente` (`aibParDefautALaDate`), lue aux collections du jeu en construction.
Fiche champsNormalisation(Fiche fac, String numero, DateTime quand, Contexte ctx) {
  final date = DateTime.tryParse('${fac['date'] ?? ''}') ?? quand;
  final situations = ctx.collection('situationsAib').actives;
  final versions = ctx.collection('baremeAib').actives;
  final parametres = d.cpaParametresALaDate(ctx.collection(d.cpaCollection).actives, date);
  Map<String, Object?>? saisi;
  String? motif;
  if ('${fac['aibTaux'] ?? ''}'.isEmpty) {
    final defaut = d.aibParDefautALaDate(ifu: fac['ifuClient'], date: date, situations: situations, versions: versions, parametres: parametres);
    saisi = {'aibTaux': defaut.taux, 'aibSituation': defaut.situation, 'aibRepli': defaut.repli};
    motif = defaut.motif;
  }
  final prep = d.preparerNormalisation(fac, acheteurSaisi: saisi, longueurIfu: parametres.longueurIfu);
  if (!prep.ok) return const {};
  final a = prep.acheteur!;
  return {
    'statutMecef': 'valide',
    'numeroMecef': numero,
    'codeRetour': 'OK-200',
    'dateTransmission': iso8601(quand),
    'mecefSimule': true,
    'ifuClient': a.ifu,
    'acheteurNom': a.nom,
    'aibTaux': a.aibTaux,
    if (a.aibSituation != null) 'aibSituation': a.aibSituation,
    if (a.aibRepli) 'aibRepli': true,
    if (motif != null) 'aibMotif': motif,
    'aibMontant': prep.montants!.aib,
  };
}
String jourDe(DateTime t) => Contexte.date(t);

/// Le jour calendaire suivant [n] jours (instants UTC, heure conservée).
DateTime plusJours(DateTime t, int n) => t.add(Duration(days: n));

/// Les montants d'un jeu sont des entiers de francs : un `double` entier s'écrit sans décimale.
Object? entier(Object? v) {
  if (v is double && v == v.truncateToDouble()) return v.toInt();
  return v;
}

/// Convertit récursivement les doubles entiers en entiers (l'écriture JSON d'un `2000.0` donnerait `2000.0` là où le poste lit `2000`).
Object? normaliser(Object? v) {
  if (v is Map) return {for (final e in v.entries) '${e.key}': normaliser(e.value)};
  if (v is List) return [for (final x in v) normaliser(x)];
  return entier(v);
}

Fiche normalisee(Fiche f) => (normaliser(f) as Map).cast<String, Object?>();

/// Une entrée de la file : un instant, un rang d'arrivée (l'ordre de planification départage deux événements simultanés) et le geste.
class _Evt {
  _Evt(this.quand, this.rang, this.geste);
  final DateTime quand;
  final int rang;
  final void Function() geste;
}

/// Le contexte de génération du sous-lot : le tirage, l'horloge, la file et les gestes de caisse.
class Jeu {
  Jeu(this.ctx) : t = ctx.tirageDe('clinique') {
    stock = StockJeu(this);
    caisse = Caisse(this);
  }

  final Contexte ctx;
  final Tirage t;
  late final StockJeu stock;
  late final Caisse caisse;

  /// L'instant « courant » de la file : mis à jour avant chaque geste.
  DateTime horloge = DateTime.utc(2026, 8, 1, 8);

  /// Les compteurs d'identifiant par collection (un identifiant ne se réutilise jamais, archivées comprises).
  final Map<String, int> _compteurs = {};

  /// Des notes de passage d'un événement à l'autre (la facture d'une consultation, le dossier d'une prescription…).
  final Map<String, Object?> memo = {};

  final List<_Evt> _file = [];
  int _rang = 0;

  /// Planifie un geste à un instant : inséré à sa place dans la file (stable à égalité).
  void planifier(DateTime quand, void Function() geste) {
    final e = _Evt(quand, _rang++, geste);
    var i = _file.length;
    while (i > 0 && _file[i - 1].quand.isAfter(quand)) {
      i--;
    }
    _file.insert(i, e);
  }

  /// Déroule la file du plus ancien au plus récent. Un geste peut planifier à son tour (jamais dans le passé de l'instant courant).
  void derouler() {
    while (_file.isNotEmpty) {
      final e = _file.removeAt(0);
      horloge = e.quand;
      e.geste();
    }
  }

  /// Un identifiant `PREFIXE` + rang sur [largeur] chiffres.
  String nouvelId(String collection, String prefixe, {int largeur = 5}) {
    final n = (_compteurs[collection] ?? ctx.collection(collection).toutes.length) + 1;
    _compteurs[collection] = n;
    return '$prefixe${pad(n, largeur)}';
  }

  /// Ajoute une fiche À LA FIN d'une collection (ordre déterministe) et rend la fiche telle qu'écrite (sa copie vivante).
  Fiche ajouter(String collection, Fiche fiche, String prefixe, {int largeur = 5}) {
    final f = {...fiche};
    f['id'] ??= nouvelId(collection, prefixe, largeur: largeur);
    f['statut'] ??= 'actif';
    ctx.ajouter(collection, normalisee(f));
    return ctx.collection(collection).parId(f['id'])!;
  }

  Fiche? parId(String collection, Object? id) => ctx.collection(collection).parId(id);

  void maj(String collection, Object? id, Fiche patch) {
    ctx.collection(collection).mettreAJour(id, normalisee(patch), journaliser: false);
  }

  /// Les fiches d'une collection comme listes de `Map<String, Object?>` (copie de lecture).
  List<Fiche> lire(String collection) => ctx.fiches(collection);
}

/// Le magasin vu par le moteur de consultation du domaine. Mêmes préfixes d'identifiant que le poste ; l'insertion se fait À LA FIN (le poste insère
/// en tête, mais l'ordre d'un fichier livré doit rester celui de l'écriture), l'horloge est celle de la file.
class StockJeu implements d.StockCs {
  StockJeu(this.jeu);
  final Jeu jeu;

  static const _prefixes = {
    'consultations': 'CON',
    'dossiersConsultation': 'DOS',
    'ordonnances': 'ORD',
    'demandesAnalyses': 'DEM',
    'demandesImagerie': 'IME',
    'factures': 'FAC',
    'taches': 'TCH',
    'notifications': 'NOT',
    'prescriptions': 'PRS',
    'administrations': 'ADM',
  };

  @override
  List<Fiche> actives(String col) => jeu.ctx.collection(col).actives;
  @override
  List<Fiche> toutes(String col) => jeu.ctx.collection(col).toutes;
  @override
  Fiche? parId(String col, Object? id) => jeu.parId(col, id);
  @override
  Fiche inserer(String col, Fiche fiche) => jeu.ajouter(col, {'statut': 'actif', ...fiche}, _prefixes[col] ?? 'ID');
  @override
  void mettreAJour(String col, Object? id, Fiche patch) => jeu.maj(col, id, patch);
  @override
  void archiver(String col, Object? id) => jeu.ctx.collection(col).archiver(id);
  @override
  void defaire(String col, Object? id) => jeu.ctx.collection(col).archiver(id);
  @override
  List<Fiche> referentiel(String nom) => [
        for (final x in (jeu.ctx.referentiels[nom] as List? ?? const [])) (x as Map).cast<String, Object?>()
      ];
  @override
  DateTime get maintenant => jeu.horloge;
}

/// Les gestes de caisse du jeu : tous passent par les moteurs du domaine (`emettreFacture`, `encaisser`, `ecritureEncaissement`, `emettreAvoir`).
class Caisse {
  Caisse(this.jeu);
  final Jeu jeu;
  int _graineMecef = 5000;

  /// L'identifiant MECeF simulé d'une pièce (le boîtier physique n'est pas branché : tiré d'une graine fixe, jamais de l'horloge).
  String numeroMecef() => d.numeroMecefSimule(++_graineMecef);

  late final bool mecefActif =
      d.fermeturesEnVigueur(jeu.ctx.collection('modulesActifs').toutes).mecefEnService;

  Map<String, String> _libellesComptes() => {
        for (final c in jeu.ctx.fiches('comptes')) '${c['num']}': '${c['libelle']}',
      };
  late final Map<String, String> libelles = _libellesComptes();

  /// Écrit les lignes d'écriture rendues par un moteur : identifiant, libellé du compte. Elles naissent en BROUILLON (RG-10 contrôlé par le moteur).
  List<Fiche> poserEcritures(List<Map<String, Object?>> lignes) {
    final posees = <Fiche>[];
    for (final e in lignes) {
      final compte = '${e['compte']}';
      posees.add(jeu.ajouter(
          'ecritures',
          {
            ...e,
            if (e['compteLibelle'] == null && libelles[compte] != null) 'compteLibelle': libelles[compte],
            'statut': 'brouillon',
          },
          'ECR'));
    }
    return posees;
  }

  /// `m8-facturation › Enregistrer` : le moteur d'émission répartit chaque ligne (RG-09, carte valide à la date), sépare les pièces `-A` / `-B`, numérote
  /// la série de l'année. La pièce naît NON réglée ; la créance de l'assureur est constatée tout de suite (411 / 706, brouillon), comme à l'écran.
  /// Rend les pièces écrites (une ou deux).
  List<Fiche> emettre({
    required Fiche patient,
    required List<Map<String, Object?>> lignes,
    required DateTime quand,
    required String type,
    Fiche complement = const {},
  }) {
    final jour = jourDe(quand);
    final factures = jeu.ctx.collection('factures').toutes;
    final r = d.emettreFacture(
      patient: patient,
      lignes: lignes,
      dateRepartition: jour,
      dateFacture: jour,
      type: type,
      mode: 'especes',
      rangDebut: d.rangSerieFactures(d.prefixeSerieFacture(proforma: false, dateFacture: jour), factures) - 1,
      reglement: 0,
      mecefActif: mecefActif,
      couvertures: jeu.lire('couverturesAssurance'),
      souscripteurs: jeu.lire('souscripteurs'),
      garanties: jeu.lire('garanties'),
    );
    final ecrites = <Fiche>[];
    for (final p in r.pieces) {
      final fiche = {...p}..remove('mecef');
      final soldeeD = (p['statutPaiement'] == 'soldee');
      fiche['lignes'] = [
        for (final (i, l) in (p['lignes'] as List).cast<Map<String, Object?>>().indexed)
          {
            ...l,
            'id': 'L${pad(i + 1, 3)}',
            // Une ligne dont la part patient est nulle (tout est pris en charge) n'attend aucun règlement : elle naît réglée à 0, comme sur les pièces réelles.
            'statutPaiement': soldeeD ? 'paye' : 'du',
            'montantRegle': 0,
            if (soldeeD) 'payeLe': iso8601(quand),
            if (soldeeD) 'payePar': caissierDuJeu,
          }
      ];
      fiche['statut'] = 'actif';
      if (p['mecef'] == true) fiche.addAll(champsNormalisation(fiche, numeroMecef(), quand, jeu.ctx));
      fiche.addAll(complement);
      final ins = jeu.ajouter('factures', fiche, 'FAC');
      ecrites.add(ins);
      poserEcritures(d.ecritureEncaissement(ins, 0.0, jour, jeu.lire('ecritures')));
    }
    return ecrites;
  }

  /// La créance de l'assureur d'une pièce émise par le MOTEUR DE PRESCRIPTION (`csPrescrire`) : à l'écran, elle n'est constatée qu'au premier versement ;
  /// le jeu la pose à l'émission comme `m8-facturation`, faute de quoi une pièce restée à encaisser n'aurait aucune créance au journal.
  void constaterCreance(Fiche facture, DateTime quand) {
    poserEcritures(d.ecritureEncaissement(facture, 0.0, jourDe(quand), jeu.lire('ecritures')));
  }

  /// `PR.encaisser` : le cœur arithmétique est celui du domaine ; ici l'orchestration (déblocage du laboratoire, de l'imagerie et des tâches d'aval,
  /// écriture 571 / 706, prescription de soins réglée). [lignes] : les prestations nommées (sinon tout ce qui est dû).
  d.ResultatEncaissement? encaisser(String factureId, {List<String>? lignes, String mode = 'especes', required DateTime quand}) {
    final fac = jeu.parId('factures', factureId);
    if (fac == null) throw StateError('Facture introuvable : $factureId');
    final r = d.encaisser(
      fac,
      lignes: lignes,
      mode: mode,
      aujourdhui: jourDe(quand),
      maintenant: iso8601(quand),
      utilisateur: caissierDuJeu,
      mecefActif: mecefActif,
      ecritures: jeu.lire('ecritures'),
    );
    if (r.refus != null) throw StateError('Encaissement refusé : ${r.refus}');
    if (r.deja) return null;
    final f = r.facture;
    jeu.maj('factures', factureId, {
      for (final k in ['lignes', 'montantPaye', 'reliquat', 'modePaiement', 'statutPaiement', 'statutMecef', 'baseMecef', 'dernierReglement'])
        if (f.containsKey(k)) k: f[k],
    });
    if (mecefActif && f['statutPaiement'] == 'soldee' && fac['numeroMecef'] == null && d.nombreOuZero(f['partPatient']) > 0) {
      jeu.maj('factures', factureId, champsNormalisation({...fac, ...f}, numeroMecef(), quand, jeu.ctx));
    }
    final iso = iso8601(quand);
    final reglees = [
      for (final l in (f['lignes'] as List).cast<Map>())
        if (r.lignesReglees.contains('${l['id']}')) l.cast<String, Object?>()
    ];
    final analyses = jeu.ctx.collection('demandesAnalyses');
    for (final l in reglees) {
      if (l['categorie'] != 'analyse' || l['demandeId'] == null) continue;
      final dem = analyses.parId(l['demandeId']);
      if (dem == null) continue;
      jeu.maj('demandesAnalyses', dem['id'], {
        'bloqueParPaiement': false,
        'statutPaiement': 'soldee',
        'etatAnalyse': dem['etatAnalyse'] == 'valide' ? 'valide' : 'attente_prelevement',
        'regleLe': iso,
      });
    }
    final imagerie = jeu.ctx.collection('demandesImagerie');
    for (final l in reglees) {
      if (l['categorie'] != 'imagerie' || l['demandeImagerieId'] == null) continue;
      final di = imagerie.parId(l['demandeImagerieId']);
      if (di == null) continue;
      jeu.maj('demandesImagerie', di['id'], {
        'bloqueParPaiement': false,
        'statut': di['statut'] == 'demandee' ? 'payee' : di['statut'],
        'regleLe': iso,
      });
    }
    if (f['statutPaiement'] == 'soldee') {
      final taches = jeu.ctx.collection('taches');
      for (final t in taches.actives.where((t) => t['factureId'] == factureId)) {
        if (t['type'] == 'encaissement') {
          jeu.maj('taches', t['id'], {'statut': 'fait', 'faitLe': iso, 'faitPar': caissierDuJeu});
        } else if (t['statut'] == 'bloque') {
          jeu.maj('taches', t['id'], {'statut': 'en_attente'});
        }
      }
      if (f['ordonnanceId'] != null) jeu.maj('ordonnances', f['ordonnanceId'], {'statutPaiement': 'soldee'});
      if (f['prescriptionSoinsId'] != null) jeu.maj('prescriptions', f['prescriptionSoinsId'], {'statutPaiement': 'payee'});
    }
    poserEcritures(r.ecritures);
    return r;
  }

  /// `emettreAvoir` : le moteur UNIQUE de l'avoir. Contre-passation PLATE en brouillon, cumul porté par la facture (elle n'est jamais réécrite).
  Fiche avoir({
    required String factureId,
    required String motif,
    required DateTime quand,
    String remboursement = 'creance',
    List<int>? lignesIndex,
  }) {
    final fac = jeu.parId('factures', factureId)!;
    final detail = (fac['lignes'] as List).cast<Map>();
    final choisies = lignesIndex ?? [for (var i = 0; i < detail.length; i++) i];
    final lignes = [
      for (final i in choisies)
        {
          'id': detail[i]['id'],
          'designation': detail[i]['designation'],
          'montant': detail[i]['montant'],
        }
    ];
    final idAvoir = jeu.nouvelId('avoirs', 'AVR');
    final r = d.emettreAvoir(
      facture: fac,
      idAvoir: idAvoir,
      lignes: lignes,
      motif: motif,
      remboursement: remboursement,
      observations: 'Avoir de démonstration émis par le moteur.',
      jour: jourDe(quand),
      utilisateur: caissierDuJeu,
      mecefActif: mecefActif,
      facturesMere: jeu.lire('facturesMere'),
      avoirs: jeu.lire('avoirs'),
    );
    final ins = jeu.ajouter('avoirs', {...r.avoir, 'id': idAvoir, 'statut': 'actif', 'horodatage': iso8601(quand)}, 'AVR');
    final ecr = poserEcritures(r.ecritures);
    jeu.maj('avoirs', idAvoir, {'ecritureIds': [for (final e in ecr) e['id']]});
    jeu.maj('factures', factureId, {
      'avoirIds': [...((fac['avoirIds'] as List?) ?? const []), idAvoir],
      'montantAvoirs': r.montantAvoirs,
    });
    return ins;
  }
}
