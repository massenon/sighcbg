import 'package:sigh_domaine/sigh_domaine.dart';

import 'magasin.dart';

/// LE RÉFÉRENTIEL DE PRIX UNIQUE AU POSTE (PRD-TARIFS, lot T6) : la colle entre les fonctions pures de `packages/domaine/lib/src/tarifs/tarifs.dart` (rejouées sur les
/// vecteurs de la maquette) et le magasin du poste. Aucune règle ici : la résolution du prix, la proposition, la décision, le contrôle d'usage, la date passée et la
/// pro-forma sont celles du domaine. Ce fichier ne fait qu'assembler les fiches, écrire ce que le domaine rend, journaliser (RG-12) et tenir les collections de lecture.
///
/// COLLECTIONS. `tarifs` (l'identité d'une prestation) et `versionsTarif` (une ligne par version, immuable pour ce qui est du prix) sont de FAMILLE R : la mère seule les
/// écrit, un fileul les reçoit par le journal de configuration et ne peut pas les écrire (garde « réglé sur la mère », `CONFIGURATION_DE_LA_MERE`). Un fileul ne
/// décide ni ne propose directement : il DÉPOSE une demande (`propositionsTarif`, famille B, ajout seul) que la mère applique après avoir refait les mêmes contrôles
/// sous le rôle de l'auteur de la demande ; le verdict (appliquée ou refusée, code et motif) revient au fileul par la même collection.
///
/// `actes`, `analyses` et `catalogueTarifs` ne sont plus que des PROJECTIONS de lecture (prix en vigueur aujourd'hui), reconstruites par la MÈRE au démarrage, à chaque
/// décision et au changement de jour ; un fileul les reçoit avec la configuration. Aucun lecteur de prix ne les relit : tous passent par [lire] et l'accesseur daté.
class IssueTarif {
  const IssueTarif({this.refus, this.version, this.demande, this.valideeEnUnGeste = false, this.rapport, this.reutilise = false});

  /// La prestation de prix du produit existait déjà (fiche recréée, reprise) : aucune seconde version 1 n'est posée.
  final bool reutilise;
  final RefusTarif? refus;

  /// La version écrite (mère) ou, pour une proposition d'un fileul, la version telle que la mère l'écrira (aperçu).
  final Map<String, Object?>? version;

  /// La demande déposée à la mère (fileul) : jamais une version écrite localement.
  final Map<String, Object?>? demande;
  final bool valideeEnUnGeste;

  /// « Oui à tout » : acceptées, refusées nommées, exclues.
  final DecisionEnBloc? rapport;
  bool get ok => refus == null;
  bool get depose => demande != null;
}

class _Cache {
  ReferentielTarifs? h;
  bool sale = true;
}

class TarifsPoste {
  TarifsPoste(
    this.m, {
    required this.role,
    required this.auteur,
    this.fileul = false,
    this.libelles = const {},
    this.peutEditerEcran = false,
    this.peutEditerPour,
    this.peutProposerPrixAchat = false,
    this.peutProposerPrixAchatPour,
    this.peutProposerReception = false,
    this.peutProposerReceptionPour,
    DroitsGestes Function()? gestes,
    DateTime Function()? horloge,
    this.etiquette = 'P',
  })  : _horloge = horloge ?? DateTime.now,
        _gestes = gestes;
  final Magasin m;
  final String role;
  final String Function() auteur;

  /// Le poste est un fileul rattaché à une mère : il lit, il ne peut pas écrire une version.
  final bool fileul;
  final Map<String, String> libelles;

  /// Le droit d'ÉDITER l'écran « Tarifs et prix » (fiches RBAC) de l'agent connecté.
  final bool peutEditerEcran;

  /// Le droit d'éditer l'écran, pour un AUTRE rôle (la mère qui applique la demande d'un fileul sous le rôle de son auteur). `null` : seuls les rôles de décision.
  final bool Function(String role)? peutEditerPour;

  /// Le droit de PROPOSER le prix d'achat d'un produit (modifier « Référentiel produits », importer le jeu `tarifs-produits`, modifier les réceptions d'achats) : jamais celui d'éditer « Tarifs et prix ».
  final bool peutProposerPrixAchat;

  /// Le même droit pour un AUTRE rôle (la mère qui applique la demande d'un fileul sous le rôle de son auteur). `null` : seuls les rôles qui détiennent le geste de décider.
  final bool Function(String role)? peutProposerPrixAchatPour;

  /// Le droit de MODIFIER l'écran des réceptions d'achats (`m7-receptions`), qui est l'autorité de la proposition née d'une réception : jamais celui de modifier « Référentiel produits ».
  final bool peutProposerReception;

  /// Le même droit pour un AUTRE rôle (la mère qui applique la demande d'un fileul). `null` : seuls les rôles qui détiennent le geste de décider.
  final bool Function(String role)? peutProposerReceptionPour;
  final DateTime Function() _horloge;
  final DroitsGestes Function()? _gestes;

  /// Les gestes réservés EN FORCE (matrice des droits : fiches `rbac` ET origine), relus à chaque appel : rien n'est mis en cache, une décision prise à l'instant vaut à
  /// la lecture suivante. AUCUN nom de rôle n'est écrit ici : décider et dater dans le passé sont deux gestes de la matrice.
  DroitsGestes get gestes => (_gestes ?? () => DroitsGestes(fiches: m.collection('rbac').actives))();

  /// Les libellés des rôles qui détiennent le geste de date passée, DÉRIVÉS de la matrice (info-bulle et refus).
  List<String> get profilsDatePassee {
    final g = gestes;
    final roles = {...libelles.keys, ...?gesteReserve(gesteDaterPrixPasse)?.rolesDefaut};
    return [for (final r in g.rolesAvec(gesteDaterPrixPasse, roles)) (libelles[r] ?? r)];
  }

  /// Les libellés des rôles qui détiennent le geste de DÉCIDER, dérivés de la matrice.
  List<String> get profilsDecider {
    final roles = {...libelles.keys, ...?gesteReserve(gesteDeciderPrix)?.rolesDefaut};
    return [for (final r in gestes.rolesAvec(gesteDeciderPrix, roles)) (libelles[r] ?? r)];
  }

  /// L'étiquette du poste, qui rend unique l'identifiant d'une demande déposée.
  final String etiquette;

  static final Expando<_Cache> _caches = Expando('tarifs');

  /// Le référentiel du magasin, indexé une fois et relu dès qu'une des deux collections change.
  static ReferentielTarifs lire(Magasin m) {
    var c = _caches[m];
    if (c == null) {
      c = _caches[m] = _Cache();
      void sale() => c!.sale = true;
      m.collection(tarCollectionTarifs).addListener(sale);
      m.collection(tarCollectionVersions).addListener(sale);
    }
    if (c.sale || c.h == null) {
      c.h = ReferentielTarifs(m.collection(tarCollectionTarifs).toutes, m.collection(tarCollectionVersions).toutes);
      c.sale = false;
    }
    return c.h!;
  }

  /// Les pièces que le contrôle d'usage lit SUR LES LIGNES.
  static PiecesTarif pieces(Magasin m) => PiecesTarif(
      factures: m.collection('factures').toutes, demandesAnalyses: m.collection('demandesAnalyses').toutes, demandesImagerie: m.collection('demandesImagerie').toutes);

  /// Le JOUR (`AAAA-MM-JJ`) d'une date : aucune horloge lue ici, l'appelant fournit la sienne.
  static String jour(DateTime d) => tarIso(d);

  // --- Les lecteurs : UN accesseur, le prix de la version en vigueur à la date de la PIÈCE -------------------------------------------------------------------

  /// `PR.tarifALaDate(code, date, assure)` : les trois espaces de codes et les alias. [date] est celle de la pièce (jamais l'horloge au moment du calcul) ;
  /// [aujourdhui] ne sert que quand la date est vide.
  static ResolutionTarif prix(Magasin m, Object? code, Object? date, bool assure, {required DateTime aujourdhui}) =>
      lire(m).aLaDate(code, date, assure, aujourdhui: tarIso(aujourdhui));

  /// Les prestations du référentiel que `actes` rangeait : les fiches d'ACTE avec le prix EN VIGUEUR à [date] (`prix`, `prixAssure`, `nonCouvert`, `assurable`). Le
  /// libellé de facturation et le secteur viennent de la prestation. Un acte sans prix en vigueur porte `prix: null` (« à valider »), jamais un zéro.
  static List<Map<String, Object?>> actes(Magasin m, {required DateTime aujourdhui, Object? date}) {
    final h = lire(m);
    final j = tarJourDe(date, tarIso(aujourdhui));
    final out = <Map<String, Object?>>[];
    for (final p in h.tarifs) {
      if (p['statut'] == 'archive' || p['codeActe'] == null) continue;
      final s = h.instantane(p, j);
      out.add({
        'id': 'ACT-${p['code']}',
        'code': p['codeActe'],
        'libelle': p['libelle'],
        'secteur': p['secteur'] ?? '',
        'famille': p['famille'],
        'prix': s?.na,
        if (p['codeGrille'] != null) 'codeTarif': p['codeGrille'],
        if (s != null && s.etatAssure == 'montant') 'prixAssure': s.pa,
        'nonCouvert': s?.nc ?? false,
        if (p.containsKey('assurable')) 'assurable': p['assurable'],
        'tarifProvisoire': s?.provisoire ?? false,
        if (p['source'] != null) 'source': p['source'],
      });
    }
    return out;
  }

  /// Le prix en vigueur à [date] d'une ANALYSE (espace des codes d'analyse), selon la carte ; `null` : pas de prix (« à valider »).
  static num? prixAnalyse(Magasin m, Object? code, {required DateTime aujourdhui, Object? date, bool assure = false}) =>
      lire(m).prixAnalyse(code, date, assure, aujourdhui: tarIso(aujourdhui)).montant;

  /// Le prix en vigueur à [date] d'un ACTE (espace des codes d'acte), selon la carte et la règle historique de la prescription.
  static num? prixActe(Magasin m, Object? code, {required DateTime aujourdhui, Object? date, bool assure = false}) =>
      lire(m).prixActe(code, date, assure, aujourdhui: tarIso(aujourdhui)).montant;

  /// Le prix d'une ligne de GRILLE (imagerie, soins AMI, certificats) : la forme de l'ancien `D.tarifPrix`.
  static ResolutionTarif prixGrille(Magasin m, Object? code, {required DateTime aujourdhui, Object? date, bool assure = false}) =>
      lire(m).prixGrille(code, date, assure, aujourdhui: tarIso(aujourdhui));

  /// Les analyses du catalogue (le MODÈLE : désignation, catégorie, échantillon, délai) avec le prix EN VIGUEUR à [date] (la colonne que [assure] décide). `prix` vaut `null`
  /// quand aucun prix n'est en vigueur (« à valider »), jamais un zéro. Le catalogue est la collection `analyses` quand le jeu la porte, le référentiel livré sinon.
  static List<Map<String, Object?>> analyses(Magasin m, {required DateTime aujourdhui, Object? date, bool assure = false}) {
    final base = m.collection('analyses').actives;
    final modele = base.isNotEmpty ? base : m.referentiel('analyses');
    final h = lire(m);
    final j = tarJourDe(date, tarIso(aujourdhui));
    return [
      for (final a in modele)
        {
          ...a,
          'prix': h.prixAnalyse(a['code'], j, assure, aujourdhui: j).connu ? h.prixAnalyse(a['code'], j, assure, aujourdhui: j).montant : null,
        }
    ];
  }

  /// Les types de chambre (la nomenclature livrée) avec le prix de la JOURNÉE en vigueur à [date] : la journée facturée est une prestation du référentiel (`HO01` à `HO03`).
  static List<Map<String, Object?>> typesChambre(Magasin m, {required DateTime aujourdhui, Object? date}) {
    final h = lire(m);
    final j = tarJourDe(date, tarIso(aujourdhui));
    final out = <Map<String, Object?>>[];
    var i = 0;
    for (final t in m.referentiel('typesChambre')) {
      i++;
      final code = 'HO${i < 10 ? '0' : ''}$i';
      final r = h.prixActe(code, j, false, aujourdhui: j);
      out.add({...t, 'code': code, 'tarif': r.connu ? r.montant : t['tarif']});
    }
    return out;
  }

  /// La JOURNÉE d'hospitalisation par type de chambre (`standard`, `vip`, `vvip`) au prix EN VIGUEUR à [date] (T12 : la journée est une prestation du référentiel, `HO01` à
  /// `HO03`). Vide quand le magasin ne porte pas la nomenclature : le lecteur retombe alors sur la nomenclature livrée du domaine, jamais sur un zéro.
  static Map<String, num> tarifsJournee(Magasin m, {required DateTime aujourdhui, Object? date}) => {
        for (final t in typesChambre(m, aujourdhui: aujourdhui, date: date))
          if (t['tarif'] is num) '${t['id']}': t['tarif'] as num
      };

  /// L'entrée de GRILLE d'un code (imagerie, soins AMI, certificats) : libellé de la grille, famille, assurabilité et les deux colonnes EN VIGUEUR à [date], dans la forme que
  /// l'ancien catalogue tarifaire donnait à ses lecteurs. `null` : le code n'est pas une ligne de grille du référentiel.
  static Map<String, Object?>? entreeGrille(Magasin m, Object? code, {required DateTime aujourdhui, Object? date}) {
    final h = lire(m);
    final p = h.parGrille['$code'];
    return p == null ? null : _entreeGrille(h, p, tarJourDe(date, tarIso(aujourdhui)));
  }

  /// Toutes les lignes de grille du référentiel (filtrées par [famille] : `AMI`, `GYNECO`, `CERTIFICAT`, `IMAGERIE`, `LABO`, `CONSULTATION`), avec les prix en vigueur.
  static List<Map<String, Object?>> grille(Magasin m, {required DateTime aujourdhui, Object? date, String? famille}) {
    final h = lire(m);
    final j = tarJourDe(date, tarIso(aujourdhui));
    return [
      for (final p in h.tarifs)
        if (p['statut'] != 'archive' && p['codeGrille'] != null && (famille == null || p['famille'] == famille)) _entreeGrille(h, p, j)
    ];
  }

  static Map<String, Object?> _entreeGrille(ReferentielTarifs h, Map<String, Object?> p, String jour) {
    final s = h.instantane(p, jour);
    return {
      'id': 'TAR-${p['codeGrille']}',
      'statut': 'actif',
      'code': p['codeGrille'],
      'libelle': p['libelleGrille'] ?? p['libelle'],
      'famille': p['famille'],
      'prixNonAssure': s?.na,
      'prixAssure': (s == null || s.nc) ? null : s.pa,
      'nonCouvert': s?.nc ?? false,
      if (p.containsKey('assurable')) 'assurable': p['assurable'],
      'prixAValider': s == null || s.na == null || (s.pa == null && !s.nc && p['assurable'] != false) || s.provisoire,
      if (p['source'] != null) 'source': p['source'],
    };
  }

  /// La prestation (l'identité) d'un code d'ACTE : libellé de facturation, secteur, famille. `null` : inconnu.
  static Map<String, Object?>? prestationActe(Magasin m, Object? code) => lire(m).parActe['$code'];

  /// Les secteurs des actes (code d'acte vers secteur) : ce que les points de ventes, le coût d'activité et le pilotage lisent pour ranger une ligne par secteur.
  static List<Map<String, Object?>> actesPourSecteurs(Magasin m) => [
        for (final p in lire(m).tarifs)
          if (p['statut'] != 'archive' && p['codeActe'] != null) {'code': p['codeActe'], 'libelle': p['libelle'], 'secteur': p['secteur'] ?? ''}
      ];

  // --- Le contexte d'un geste ------------------------------------------------------------------------------------------------------------------------------

  String get aujourdhui => tarIso(_horloge());

  ReferentielTarifs get h => lire(m);

  ContexteTarif contexte({String? pourRole, String? pourAuteur, bool? pourFileul, bool reception = false}) {
    final r = pourRole ?? role;
    return ContexteTarif(
      referentiel: lire(m),
      aujourdhui: aujourdhui,
      role: r,
      auteur: pourAuteur ?? auteur(),
      peutEditerEcran: pourRole == null ? peutEditerEcran : (peutEditerPour?.call(r) ?? gestes.peut(r, gesteDeciderPrix)),
      peutProposerProduit: reception
          ? (pourRole == null ? peutProposerReception : (peutProposerReceptionPour?.call(r) ?? gestes.peut(r, gesteDeciderPrix)))
          : (pourRole == null ? peutProposerPrixAchat : (peutProposerPrixAchatPour?.call(r) ?? gestes.peut(r, gesteDeciderPrix))),
      produits: m.collection('produits').toutes,
      peutDecider: gestes.peut(r, gesteDeciderPrix),
      peutDatePassee: gestes.peut(r, gesteDaterPrixPasse),
      profilsDatePassee: profilsDatePassee,
      fileul: pourFileul ?? fileul,
      libelles: libelles,
      pieces: pieces(m),
    );
  }

  bool get peutDecider => gestes.peut(role, gesteDeciderPrix);
  bool get peutDaterPasse => gestes.peut(role, gesteDaterPrixPasse);
  bool get peutProposer => peutEditerEcran;

  // --- Proposer ---------------------------------------------------------------------------------------------------------------------------------------

  /// Propose une version. Sur la MÈRE : écrit la version (et l'identité d'une prestation créée). Sur un FILEUL : la même vérification, puis DÉPÔT d'une demande que la
  /// mère applique : rien n'est écrit dans `versionsTarif` (famille R).
  IssueTarif proposer(DemandeProposition d) {
    if (fileul) {
      final r = tarProposer(contexte(pourFileul: false), d);
      if (!r.ok) return IssueTarif(refus: r.refus);
      final dem = _deposer('proposition', {
        'code': d.code,
        'prixNonAssure': d.prixNonAssure,
        'prixAssure': d.prixAssure,
        'etatAssure': d.etatAssure ?? 'montant',
        'dateEffet': d.dateEffet,
        'motif': d.motif,
        if (d.datePassee) 'datePassee': true,
        if (d.valider) 'valider': true,
        if (d.creation != null) 'creation': d.creation,
        if (d.assurable != null) 'assurable': d.assurable,
      });
      return IssueTarif(demande: dem, version: r.valeur!.version, valideeEnUnGeste: d.valider);
    }
    final r = tarProposer(contexte(), d);
    if (!r.ok) return IssueTarif(refus: r.refus);
    return IssueTarif(version: _ecrireProposition(r.valeur!), valideeEnUnGeste: r.valeur!.valideeEnUnGeste);
  }

  Map<String, Object?> _ecrireProposition(PropositionTarif p) {
    final code = '${p.version['code']}';
    if (p.identite != null) m.collection(tarCollectionTarifs).inserer(p.identite!);
    m.journaliser('Changement de prix : ${p.journalAction}', 'CFG', 'prix', code, null, p.journalExtra);
    m.collection(tarCollectionVersions).inserer(p.version);
    if (p.valideeEnUnGeste) _apresDecision(code, '${p.version['decidePar']}', '${p.version['proposeRole']}');
    return p.version;
  }

  // --- Les PRODUITS : le prix d'achat versionné ---------------------------------------------------------------------------------------------------------

  /// Propose un changement du PRIX D'ACHAT d'un produit (jamais un écrasement de la fiche : une version AJOUTÉE, datée, soumise au Oui ou au Non). RG-02 : un médicament se facture au prix
  /// d'achat, sans marge, refusé en nommant. Sur la MÈRE : écrit la version. Sur un FILEUL : la même vérification, puis DÉPÔT d'une demande que la mère applique (famille R).
  IssueTarif proposerPrixAchat(DemandeProduit d) {
    final produits = m.collection('produits').toutes;
    if (fileul) {
      final r = tarProposerProduit(contexte(pourFileul: false), d, produits: produits);
      if (!r.ok) return IssueTarif(refus: r.refus);
      final dem = _deposer('propositionProduit', {
        'code': d.code,
        'prixAchat': d.prixAchat,
        if (d.prixVente != null) 'prixVente': d.prixVente,
        'dateEffet': d.dateEffet,
        'motif': d.motif,
        if (d.datePassee) 'datePassee': true,
        if (d.valider) 'valider': true,
        if ((d.source ?? '').isNotEmpty) 'source': d.source,
        if (d.importJeu != null) 'importJeu': d.importJeu,
        if (d.importLot != null) 'importLot': d.importLot,
        if (d.reception) 'reception': true,
      });
      return IssueTarif(demande: dem, version: r.valeur!.version, valideeEnUnGeste: d.valider);
    }
    final r = tarProposerProduit(contexte(), d, produits: produits);
    if (!r.ok) return IssueTarif(refus: r.refus);
    return IssueTarif(version: _ecrireProposition(r.valeur!), valideeEnUnGeste: r.valeur!.valideeEnUnGeste);
  }

  /// LA PROPOSITION NÉE D'UNE RÉCEPTION D'ACHAT : une réception à un autre prix que celui en vigueur à sa date OUVRE une proposition de changement du prix d'achat (date d'effet = date de réception,
  /// motif « prix constaté à la réception n° … »), une seule par produit, JAMAIS bloquante : la réception, le stock et le CUMP sont écrits par l'écran avant, un refus du moteur se DIT sans rien
  /// défaire, et jamais une écriture directe du prix. Aucun prix ne change avant le Oui. Sur la MÈRE : écrit la version. Sur un FILEUL : même vérification, puis DÉPÔT d'une demande
  /// (`reception: true`) que la mère applique sous l'autorité de MODIFIER les réceptions. Rend l'issue du moteur et, pour un fileul, la demande déposée.
  ({IssuePrixReception issue, Map<String, Object?>? version, Map<String, Object?>? demande}) proposerPrixReception(
      {required Map<String, Object?> produit, required Object? prixRecu, Object? date, required String reference}) {
    final i = tarProposerPrixReception(contexte(pourFileul: false, reception: true),
        produit: produit, prixRecu: prixRecu, date: date, reference: reference, produits: m.collection('produits').toutes);
    if (i.etat != 'ouverte') return (issue: i, version: null, demande: null);
    if (fileul) {
      final dem = _deposer('propositionProduit', {
        'code': i.code,
        'prixAchat': i.prix,
        'dateEffet': i.dateEffet,
        'motif': i.proposition!.version['motif'],
        if (i.proposition!.version['datePassee'] == true) 'datePassee': true,
        'source': i.proposition!.version['source'],
        'reception': true,
      });
      return (issue: i, version: i.proposition!.version, demande: dem);
    }
    return (issue: i, version: _ecrireProposition(i.proposition!), demande: null);
  }

  /// LA CRÉATION D'UNE FICHE PRODUIT pose la version 1 de son prix d'achat par la MÊME voie, jamais « à plat sur la fiche ». Un prix absent ou nul pose un `manquant` : l'article se crée « à
  /// valoriser » et ne se facture pas. Si la prestation de prix existe déjà, aucune seconde version 1 n'est posée. Un fileul ne l'écrit pas (famille R) : la fiche reçoit sa version 1 de
  /// reprise à la mère ([assurerProduits]).
  IssueTarif creerPrixProduit(Map<String, Object?> produit, {String? motif, String? source, String? importJeu, String? importLot}) {
    if (produit['code'] == null) return const IssueTarif(refus: RefusTarif('PRODUIT_INTROUVABLE', 'Aucune fiche produit à doter d’un prix d’achat.', 'Créer la fiche produit d’abord.'));
    if (h.parCode['${produit['code']}'] != null) return const IssueTarif(reutilise: true);
    if (fileul) return IssueTarif(refus: tarRefusFileul());
    final r = tarProposerProduit(contexte(), tarDemandeCreationProduit(produit, motif: motif, source: source, importJeu: importJeu, importLot: importLot), produits: m.collection('produits').toutes);
    if (!r.ok) return IssueTarif(refus: r.refus);
    return IssueTarif(version: _ecrireProposition(r.valeur!));
  }

  /// LA MÈRE seulement : chaque produit actif sans prestation de prix reçoit la sienne, ORIGINE « reprise » : le prix d'achat qu'il tient aujourd'hui, jamais un zéro (un prix absent est
  /// `manquant`), SANS date d'effet inventée (la version 1 vaut depuis l'origine). Réparation d'une donnée existante, pas un geste d'agent : aucune ligne de journal par produit, une seule pour le lot.
  static int assurerProduits(Magasin m) {
    final h = lire(m);
    final dotes = {for (final p in h.tarifs) '${p['code']}'};
    final r = tarMigrerProduits(m.collection('produits').actives, origine: 'reprise', dejaDotes: dotes);
    for (final t in r.tarifs) {
      m.collection(tarCollectionTarifs).ajouterSansJournal(t);
    }
    for (final v in r.versions) {
      m.collection(tarCollectionVersions).ajouterSansJournal(v);
    }
    if (r.tarifs.isNotEmpty) m.journaliser('Reprise des prix d’achat des produits', 'CFG', 'prix', 'produits', null, {'produits': r.tarifs.length});
    return r.tarifs.length;
  }

  /// DÉCISION DU 16/11/2026 : une analyse CRÉÉE au catalogue du laboratoire OUVRE aussitôt son identité de prix au référentiel unique (famille LABO, code d'analyse = code de la prestation), SANS AUCUNE
  /// version : état « sans prix en vigueur, à valider ». Elle n'est donc pas facturable (refus nommé `TARIF_A_VALIDER`, jamais un zéro) jusqu'au Oui de la DAF, qui la tarife par le circuit
  /// habituel (proposition, puis Oui ou Non). La DAF est PRÉVENUE (une notification de poste, une seule par analyse). La mère seule écrit (famille R) ; l'opération est rejouable : une analyse déjà
  /// dotée d'une prestation (code d'analyse ou alias) n'est pas touchée. Rend les codes ouverts.
  static List<String> assurerAnalyses(Magasin m, {DateTime Function()? horloge}) {
    final h = lire(m);
    // Référentiel absent (poste neuf, avant la reprise) : on n'invente rien, la reprise des prix s'en chargera avec ses propres règles.
    if (h.vide) return const [];
    final ouverts = <String>[];
    for (final a in m.collection('analyses').actives) {
      final code = '${a['code'] ?? ''}'.trim();
      if (code.isEmpty || h.parAnalyse[code] != null || h.parCode[code] != null) continue;
      final libelle = '${a['designation'] ?? a['libelle'] ?? code}';
      m.collection(tarCollectionTarifs).inserer({
        'id': code,
        'code': code,
        'codeAnalyse': code,
        'libelle': libelle,
        'famille': 'LABO',
        'statut': 'actif',
        'source': 'Ouverte à la création de l’analyse au catalogue du laboratoire, sans prix (décision du 16/11/2026)',
      });
      m.journaliser('Analyse créée sans prix : prestation ouverte', 'CFG', 'prix', code, null, {'libelle': libelle, 'état': 'sans prix en vigueur, à valider'});
      final dejaPrevenue = m.collection('notifications').toutes.any((n) => n['type'] == 'prix_a_tarifer' && n['reference'] == code && n['statut'] != 'archive');
      if (!dejaPrevenue) {
        m.collection('notifications').inserer({
          'type': 'prix_a_tarifer',
          'poste': 'da',
          'destinataire': null,
          'libelle': 'Analyse sans prix à tarifer : $libelle',
          'detail': 'L’analyse « $libelle » ($code) vient d’être créée au catalogue du laboratoire. Elle n’est pas facturable tant que son prix n’est pas arrêté : « Tarifs et prix », onglet Sans prix (proposition, puis Oui).',
          'priorite': 'normale',
          'reference': code,
          'lue': false,
          'creeLe': (horloge ?? DateTime.now)().toUtc().toIso8601String(),
          'statut': 'actif',
        }, prefixe: 'NOT');
      }
      ouverts.add(code);
    }
    return ouverts;
  }

  // --- Les prix EN DOUBLON : l'arbitrage de la Direction (16/11/2026) -------------------------------------------------------------------------------------

  /// Les codes de prestation portés deux fois, aux prix différents, par une liste de départ (`catalogueTarifs`, `actes`) : à arbitrer. La caisse lit, tant que rien n'est arbitré, la première ligne.
  static List<TarDoublonPrix> doublonsPrix(Magasin m) => [
        for (final c in tarListesDeDepart.keys) ...tarDoublonsPrix(c, m.collection(c).toutes),
      ];

  /// « Garder celui-ci » : ARCHIVE les autres lignes du code (RG-14, motif, auteur et date portés sur la fiche, une ligne de journal) ; si le prix gardé n'est pas celui que le référentiel lit, il est
  /// proposé par le circuit ordinaire (date d'effet aujourd'hui, validé en un geste par celui qui arbitre : il détient le geste de décider) AVANT toute archive — un refus du moteur (pièce émise,
  /// proposition en attente…) ne laisse rien d'écrit. La MÈRE seule écrit (famille R) ; un fileul reçoit le refus nommé.
  IssueTarif arbitrerDoublon(TarDoublonPrix d, Object? gardeId, String motif) {
    if (fileul) return IssueTarif(refus: tarRefusFileul());
    final p = d.collection == 'catalogueTarifs' ? h.parGrille[d.code] : h.parActe[d.code];
    final s = p == null ? null : h.instantane(p, aujourdhui);
    final r = tarArbitrerDoublon(d,
        gardeId: gardeId, motif: motif, peutDecider: peutDecider, prixEnVigueurNA: s?.na, prixEnVigueurA: s?.pa, assureEnVigueurMontant: s?.etatAssure == 'montant');
    if (!r.ok) return IssueTarif(refus: RefusTarif(r.code!, r.motif!, r.geste!));
    Map<String, Object?>? version;
    final prix = r.prixAProposer;
    if (prix != null && p != null) {
      final i = proposer(DemandeProposition(
          code: '${p['code']}',
          prixNonAssure: prix['prixNonAssure'],
          prixAssure: prix['prixAssure'],
          etatAssure: '${prix['etatAssure']}',
          dateEffet: aujourdhui,
          motif: 'Arbitrage de la Direction (prix en doublon) : ${motif.trim()}',
          valider: true));
      if (!i.ok) return i;
      version = i.version;
    }
    final col = m.collection(d.collection);
    for (final f in r.aArchiver) {
      col.mettreAJour(f['id'], {'motifArchivage': motif.trim(), 'archivePar': auteur(), 'archiveLe': aujourdhui, 'arbitrageDoublonGarde': r.garde!['id']}, journaliser: false);
      col.archiver(f['id']);
    }
    m.journaliser('Arbitrage d’un prix en doublon', 'CFG', 'prix', d.code, null, {
      'gardé': r.garde!['id'],
      'archivées': [for (final f in r.aArchiver) f['id']].join(', '),
      'par': auteur(),
      'motif': motif.trim().length > 60 ? motif.trim().substring(0, 60) : motif.trim(),
      if (version != null) 'version': version['id'],
    });
    projeter(m, (_horloge)());
    return IssueTarif(version: version);
  }

  /// Le prix d'achat (et le prix de vente DÉRIVÉ, RG-02) d'un produit à la date de la PIÈCE : jamais la fiche, jamais l'horloge au moment du calcul. Un prix absent n'est pas zéro.
  static PrixProduit prixProduit(Magasin m, Map<String, Object?> produit, {required DateTime aujourdhui, Object? date}) => tarPrixProduit(lire(m), produit, date, aujourdhui: tarIso(aujourdhui));

  /// Les articles « à valoriser » aujourd'hui : source UNIQUE de la liste, de l'indicateur et de l'alerte.
  static List<({Map<String, Object?> produit, bool enAttente})> produitsAValoriser(Magasin m, {required DateTime aujourdhui}) =>
      tarProduitsAValoriser(lire(m), m.collection('produits').toutes, tarIso(aujourdhui));

  // --- Décider ----------------------------------------------------------------------------------------------------------------------------------------

  /// Décide une proposition (Oui ou Non, motif obligatoire au Non). Sur un FILEUL : dépôt d'une demande de décision, appliquée par la mère sous le rôle de son auteur.
  IssueTarif decider(String versionId, String decision, {String? motif, String? dateEffet}) {
    if (fileul) {
      final r = tarDecider(contexte(pourFileul: false), versionId, decision, motif: motif, dateEffet: dateEffet);
      if (!r.ok) return IssueTarif(refus: r.refus);
      final dem = _deposer('decision', {'versionId': versionId, 'decision': decision, if (motif != null && motif.isNotEmpty) 'motifDecision': motif, if (dateEffet != null) 'dateEffet': dateEffet});
      return IssueTarif(demande: dem, version: r.valeur!.version);
    }
    final r = tarDecider(contexte(), versionId, decision, motif: motif, dateEffet: dateEffet);
    if (!r.ok) return IssueTarif(refus: r.refus);
    appliquerDecision(r.valeur!);
    return IssueTarif(version: r.valeur!.version);
  }

  /// Écrit une décision recevable (la mère seulement) : une ligne de journal par transition, le correctif de la version, le retour à l'auteur, le marquage levé.
  void appliquerDecision(DecisionTarif d) {
    final v = h.versions.firstWhere((x) => x['id'] == d.versionId);
    m.journaliser('Changement de prix : ${d.journalAction}', 'CFG', 'prix', '${v['code']}', null, d.journalExtra);
    m.collection(tarCollectionVersions).mettreAJour(d.versionId, d.patch, journaliser: false);
    final n = d.notification;
    if (n != null) _notifier(n);
    if (d.leverMarquage) _apresDecision('${v['code']}', '${d.patch['decidePar']}', '${d.patch['roleDecision']}');
  }

  /// Retire une proposition en attente (l'auteur, ou un profil qui décide) : elle reste lisible (RG-14). La décision d'un fileul n'est pas un retrait : un fileul
  /// retire par une demande.
  IssueTarif retirer(String versionId, String? motif) {
    if (fileul) {
      final r = tarRetirer(contexte(pourFileul: false), versionId, motif);
      if (!r.ok) return IssueTarif(refus: r.refus);
      return IssueTarif(demande: _deposer('retrait', {'versionId': versionId, if (motif != null && motif.isNotEmpty) 'motifDecision': motif}));
    }
    final r = tarRetirer(contexte(), versionId, motif);
    if (!r.ok) return IssueTarif(refus: r.refus);
    appliquerDecision(r.valeur!);
    return IssueTarif(version: r.valeur!.version);
  }

  /// « Oui à tout », ENCADRÉ : jamais sans la comparaison affichée, jamais sans le droit ; chaque ligne passe par la décision ordinaire. Un fileul dépose UNE demande
  /// par ligne que la mère décide (chacune refait ses contrôles). Une seule ligne de journal pour le geste.
  IssueTarif deciderTous({required bool comparaisonAffichee, List<String>? ids, String? dateEffet, double? seuil}) {
    if (fileul) {
      final r = tarDeciderTous(() => contexte(pourFileul: false), comparaisonAffichee: comparaisonAffichee, appliquer: (_) {}, ids: const []);
      if (!r.ok) return IssueTarif(refus: r.refus);
      final liste = ids ?? [for (final v in h.versions) if (v['statut'] == 'propose') '${v['id']}'];
      final deposees = <Map<String, Object?>>[];
      for (final id in liste) {
        deposees.add(_deposer('decision', {'versionId': id, 'decision': 'oui', 'lot': 'oui-a-tout', if (dateEffet != null) 'dateEffet': dateEffet}));
      }
      return IssueTarif(rapport: DecisionEnBloc(acceptees: [for (final d in deposees) {'id': d['versionId'], 'demande': d['id']}], refusees: const [], exclues: const []));
    }
    final r = tarDeciderTous(() => contexte(), comparaisonAffichee: comparaisonAffichee, appliquer: appliquerDecision, ids: ids, dateEffet: dateEffet, seuil: seuil ?? seuilVariation());
    if (!r.ok) return IssueTarif(refus: r.refus);
    final b = r.valeur!;
    m.journaliser('Changement de prix : Oui à tout', 'CFG', 'prix', 'lot', null, {'oui': b.acceptees.length, 'refus': b.refusees.length, 'exclus': b.exclues.length, 'role': role});
    return IssueTarif(rapport: b);
  }

  /// Le seuil de variation signalée, lu de la base (`reglages`) : AUCUNE valeur par défaut (aucun document ne la fixe).
  double? seuilVariation() => tarSeuilVariation(m.collection('reglages').parId(tarCleSeuilVariation)?['valeur']);

  // --- La demande d'un fileul (famille B) --------------------------------------------------------------------------------------------------------------

  Map<String, Object?> _deposer(String genre, Map<String, Object?> contenu) {
    final col = m.collection(tarCollectionDemandes);
    final id = 'DT$etiquette${_horloge().microsecondsSinceEpoch}${col.toutes.length}';
    final fiche = {
      'id': id,
      'statut': 'actif',
      'genre': genre,
      'etat': 'deposee',
      'demandePar': auteur(),
      'demandeRole': role,
      'demandeLe': aujourdhui,
      ...contenu,
    };
    m.journaliser('Changement de prix : demande déposée à la mère ($genre)', 'CFG', 'prix', '${contenu['code'] ?? contenu['versionId'] ?? ''}', null, {'role': role});
    col.inserer(fiche);
    return fiche;
  }

  /// MÈRE : applique les demandes déposées par les fileuls. Chacune refait les MÊMES contrôles sous le rôle et le nom de son auteur (un bouton absent sur le fileul
  /// ne protège rien) ; le verdict est écrit sur la demande et revient au fileul par le pont. Rend le nombre de demandes traitées.
  int appliquerDemandes() {
    if (fileul) return 0;
    var n = 0;
    final col = m.collection(tarCollectionDemandes);
    final enAttente = [for (final d in col.toutes) if (d['etat'] == 'deposee') d]
      ..sort((a, b) => '${a['demandeLe']}${a['id']}'.compareTo('${b['demandeLe']}${b['id']}'));
    for (final d in enAttente) {
      final role = '${d['demandeRole']}', par = '${d['demandePar']}';
      final cx = contexte(pourRole: role, pourAuteur: par, pourFileul: false, reception: d['reception'] == true);
      RefusTarif? refus;
      Object? versionId;
      switch ('${d['genre']}') {
        case 'proposition':
          final dem = DemandeProposition(
            code: '${d['code']}',
            prixNonAssure: d['prixNonAssure'],
            prixAssure: d['prixAssure'],
            etatAssure: d['etatAssure'] as String?,
            dateEffet: d['dateEffet'] as String?,
            motif: d['motif'] as String?,
            datePassee: d['datePassee'] == true,
            valider: d['valider'] == true,
            creation: (d['creation'] as Map?)?.cast<String, Object?>(),
            assurable: d['assurable'],
          );
          final r = tarProposer(cx, dem);
          if (r.ok) {
            versionId = _ecrireProposition(r.valeur!)['id'];
          } else {
            refus = r.refus;
          }
        case 'propositionProduit':
          final r = tarProposerProduit(
              cx,
              DemandeProduit(
                code: '${d['code']}',
                prixAchat: d['prixAchat'],
                prixVente: d['prixVente'],
                dateEffet: d['dateEffet'] as String?,
                motif: d['motif'] as String?,
                datePassee: d['datePassee'] == true,
                valider: d['valider'] == true,
                source: d['source'] as String?,
                importJeu: d['importJeu'] as String?,
                importLot: d['importLot'] as String?,
                reception: d['reception'] == true,
              ),
              produits: m.collection('produits').toutes);
          if (r.ok) {
            versionId = _ecrireProposition(r.valeur!)['id'];
          } else {
            refus = r.refus;
          }
        case 'decision':
          final r = tarDecider(cx, '${d['versionId']}', '${d['decision']}', motif: d['motifDecision'] as String?, dateEffet: d['dateEffet'] as String?);
          if (r.ok) {
            appliquerDecision(r.valeur!);
            versionId = d['versionId'];
          } else {
            refus = r.refus;
          }
        case 'retrait':
          final r = tarRetirer(cx, '${d['versionId']}', d['motifDecision'] as String?);
          if (r.ok) {
            appliquerDecision(r.valeur!);
            versionId = d['versionId'];
          } else {
            refus = r.refus;
          }
        default:
          refus = const RefusTarif('GENRE_INCONNU', 'Demande de prix d’un genre inconnu.', 'La refaire depuis « Tarifs et prix ».');
      }
      col.mettreAJour(d['id'], {
        'etat': refus == null ? 'appliquee' : 'refusee',
        'traiteLe': aujourdhui,
        'traitePar': auteur(),
        if (versionId != null) 'versionId': versionId,
        if (refus != null) ...{'resultatCode': refus.code, 'resultatMotif': refus.motif, 'resultatGeste': refus.geste},
      }, journaliser: false);
      n++;
    }
    return n;
  }

  // --- Après une décision : le marquage « tarif d'attente » levé, la projection refaite -----------------------------------------------------------------

  void _apresDecision(String code, String qui, String roleDecideur) {
    final p = h.parCode[code];
    if (p != null) {
      for (final x in [('actes', p['codeActe']), ('analyses', p['codeAnalyse'])]) {
        if (x.$2 == null) continue;
        final fiche = m.collection(x.$1).actives.where((f) => f['code'] == x.$2).firstOrNull;
        if (fiche == null) continue;
        List<Fiche> lire(String nom) => m.collection(nom).toutes;
        final e = valEtatValidation(x.$1, '${fiche['id']}', lire, libelles);
        if (e != null && e.enAttente) {
          final v = valValiderReferentiel(x.$1, '${fiche['id']}', role: roleDecideur, acteur: qui, maintenant: _horloge(), lire: lire, libelles: libelles);
          if (v.ok) {
            final col = m.collection(v.collection!);
            if (v.creation != null) {
              col.ajouterSansJournal(v.creation!);
            } else {
              col.mettreAJour(v.collection == valCollectionValidations ? 'VRF-${v.id}' : '${v.id}', v.patch, journaliser: false);
            }
            final j = v.journal!;
            m.journaliser(j.action, j.module, j.entite, j.reference, j.avant, j.apres);
          }
        }
      }
    }
    for (final (id, patch) in tarLeverProvisoire(h, code, qui: qui, jour: aujourdhui)) {
      m.collection(tarCollectionVersions).mettreAJour(id, patch, journaliser: false);
    }
    projeter(m, _horloge());
  }

  // --- La durée de validité d'une pro-forma (réglage en base, défaut 30 jours « à valider ») --------------------------------------------------------------

  int validiteProformaJours() => tarValiditeProformaJours(m.collection('reglages').parId(tarCleValiditeProforma)?['valeur']);

  ResultatTarif<({int jours, int avant})> definirValiditeProforma(Object? jours, {String? motif}) {
    final r = tarDefinirValiditeProforma(contexte(), jours, reglageActuel: m.collection('reglages').parId(tarCleValiditeProforma)?['valeur']);
    if (!r.ok) return r;
    final col = m.collection('reglages');
    m.journaliser('Validité d’une pro-forma', 'CFG', 'reglage', tarCleValiditeProforma, {'jours': r.valeur!.avant}, {'jours': r.valeur!.jours, 'motif': motif});
    if (col.parId(tarCleValiditeProforma) != null) {
      col.mettreAJour(tarCleValiditeProforma, {'valeur': r.valeur!.jours}, journaliser: false);
    } else {
      col.ajouterSansJournal({'id': tarCleValiditeProforma, 'statut': 'actif', 'valeur': r.valeur!.jours});
    }
    return r;
  }

  /// L'écart d'une pro-forma à la conversion (le prix tenu dans la durée de validité, le prix du jour au-delà) ; n'écrit aucune pièce.
  ResultatTarif<Map<String, Object?>> ecartProforma(Object? factureId, {String? dateConversion}) {
    final f = m.collection('factures').toutes.where((x) => x['id'] == factureId).firstOrNull;
    final patient = f == null ? null : m.collection('patients').toutes.where((p) => p['code'] == f['patientCode']).firstOrNull;
    return tarEcartProforma(f,
        referentiel: h,
        pieces: pieces(m),
        aujourdhui: aujourdhui,
        validiteJours: validiteProformaJours(),
        assureA: (jour) => patient != null && carteValide(patient, m.collection('couverturesAssurance').toutes, jour),
        dateConversion: dateConversion);
  }

  // --- La projection de lecture et sa garde de parité -----------------------------------------------------------------------------------------------------

  static final Expando<String> _dernierJour = Expando('tarifs:jour');

  /// Reconstruit `actes`, `analyses` et `catalogueTarifs` depuis le référentiel, au prix en vigueur AUJOURD'HUI : seuls les champs de prix, sans ligne de journal (rien
  /// n'est « modifié » au sens métier). Rend le nombre de fiches touchées. Idempotent.
  static int projeter(Magasin m, DateTime maintenant) {
    final h = lire(m);
    if (h.vide) return 0;
    final j = tarIso(maintenant);
    final c = tarProjection(h, j,
        actes: m.collection('actes').toutes, analyses: m.collection('analyses').toutes, catalogue: m.collection('catalogueTarifs').toutes, avecCreations: true);
    var n = 0;
    for (final x in c) {
      final col = m.collection(x.collection);
      if (x.creation != null) {
        col.ajouterSansJournal(x.creation!);
      } else {
        final f = col.parId(x.id);
        if (f == null) continue;
        col.appliquerDistante({...f, ...x.patch});
      }
      n++;
    }
    n += projeterProduits(m, maintenant);
    _dernierJour[m] = j;
    return n;
  }

  /// La fiche `produits` de chaque article doté d'un prix versionné dit le prix EN VIGUEUR AUJOURD'HUI (une version datée de demain prend effet à sa date, au prochain démarrage ou à la décision
  /// suivante) : seuls les champs de prix qui diffèrent, jamais un prix absent (la fiche garde son marquage « à valoriser »). Rend le nombre de fiches corrigées.
  static int projeterProduits(Magasin m, DateTime maintenant) {
    final h = lire(m);
    if (h.vide) return 0;
    final j = tarIso(maintenant);
    var n = 0;
    for (final fiche in m.collection('produits').actives) {
      final p = h.parCode['${fiche['code']}'];
      if (p == null || p['famille'] != tarFamilleProduit) continue;
      final s = h.instantane(p, j);
      if (s == null) continue;
      final c = tarCorrectifProduit(fiche, s);
      if (c == null) continue;
      m.collection('produits').appliquerDistante({...fiche, ...c});
      n++;
    }
    return n;
  }

  /// Le changement de jour sans tâche de minuit : à appeler à l'ouverture d'un écran ; ne fait rien si la projection de ce jour est déjà faite.
  static int projeterSiNouveauJour(Magasin m, DateTime maintenant) => _dernierJour[m] == tarIso(maintenant) ? 0 : projeter(m, maintenant);

  /// La GARDE DE PARITÉ : chaque fiche des trois collections de lecture doit dire ce que le référentiel dit aujourd'hui. Un écart est une ERREUR nommée, jamais un
  /// affichage différent. Rend la liste des écarts (vide quand tout concorde).
  static List<Map<String, Object?>> parites(Magasin m, DateTime maintenant) {
    final h = lire(m);
    if (h.vide) return const [];
    final c = tarProjection(h, tarIso(maintenant),
        actes: m.collection('actes').toutes, analyses: m.collection('analyses').toutes, catalogue: m.collection('catalogueTarifs').toutes);
    return [
      for (final x in c) {'collection': x.collection, 'id': x.id, 'ecart': x.patch}
    ];
  }

  // --- La reprise d'un magasin d'AVANT le référentiel ------------------------------------------------------------------------------------------------------

  /// Un poste qui avait enregistré ses actes avant l'arrivée du référentiel (collection `actes` relue du disque, aucune collection `tarifs`) : le prix FACTURÉ aujourd'hui
  /// est celui de la collection `actes` (la caisse la lisait), il devient la version 1 ; le prix des analyses et de la grille est celui du jeu livré. Les éditions faites
  /// à `catalogueTarifs` (que personne ne lisait) sont LISTÉES, jamais appliquées. Journalisée une fois ; ne fait rien sur un magasin qui porte déjà le référentiel.
  /// Rend la migration (ou `null`). La projection est ensuite refaite par la MÈRE seulement.
  static MigrationTarifs? reprendre(Magasin m, {DateTime Function()? horloge, bool fileul = false}) {
    MigrationTarifs? mg;
    final lues = m.collectionsLuesDuDisque;
    if (lues.contains('actes') && !lues.contains(tarCollectionTarifs)) {
      mg = tarMigrer(
          actes: m.collection('actes').toutes,
          grille: m.jeuDOrigine('catalogueTarifs'),
          analyses: m.referentiel('analyses'),
          catalogue: m.collection('catalogueTarifs').toutes);
      m.collection(tarCollectionTarifs).remplacerContenu(mg.tarifs);
      m.collection(tarCollectionVersions).remplacerContenu(mg.versions);
      final reels = [for (final e in mg.ecarts) if (const {'acte-grille', 'catalogue-grille', 'catalogue-inconnu'}.contains(e['type'])) e];
      m.journaliser('Reprise des prix (magasin d’avant le référentiel)', 'CFG', 'prix', 'migration', null,
          {'prestations': mg.tarifs.length, 'versions': mg.versions.length, 'ecartsListes': reels.length});
    }
    if (!fileul) projeter(m, (horloge ?? DateTime.now)());
    return mg;
  }

  /// Une notification s'adresse à un POSTE, non à une personne (la même fiche que `PR.notifier`).
  void _notifier(Map<String, Object?> o) {
    m.collection('notifications').inserer({
      'type': o['type'],
      'poste': o['poste'] ?? 'tous',
      'destinataire': o['destinataire'],
      'libelle': o['libelle'],
      'detail': o['detail'],
      'priorite': o['priorite'] ?? 'normale',
      'reference': o['reference'],
      'lue': false,
      'creeLe': _horloge().toUtc().toIso8601String(),
    }, prefixe: 'NOT');
  }
}
