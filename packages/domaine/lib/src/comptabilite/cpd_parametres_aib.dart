/// LES PARAMÈTRES DE L'AIB, ENREGISTRÉS EN BASE ET VERSIONNÉS (Direction, 09/11/2026) : la base de la retenue sur facture fournisseur, le branchement de
/// l'IFU de l'acheteur sur le barème, le taux de repli « sans taux arrêté », la longueur de l'IFU.
///
/// RÈGLE DE LA DIRECTION : tout ce qui est paramétrable l'est aux Paramètres, enregistré en base (collection `parametresAib`, une fiche par VERSION et par
/// RUBRIQUE), avec un DÉFAUT SEMÉ. Le moteur LIT la version en vigueur à la date de la pièce ; une valeur de code ne sert que de GRAINE de la collection
/// ([CpdParametresAib.graine], [cpaFichesGraine]) et d'ultime repli quand la collection est vide (poste jamais semé) — l'appelant le DIT alors
/// (`deLaGraine`).
///
/// Une version n'écrase jamais la précédente : valider AJOUTE une fiche à une date d'effet postérieure (comme le barème, la grille des primes et les plages
/// par lot de réactif). La fiche porte le DÉCIDEUR et la DATE DE LA DÉCISION (obligatoires), le motif, le numéro de version. Une version s'archive, elle ne se
/// supprime pas (RG-14).
///
/// Cinq rubriques :
///
/// * `base_retenue` — la base de la retenue d'AIB sur une facture fournisseur : `ht` (le montant hors taxes quand il est renseigné, sinon repli SUR LE MONTANT
///   FACTURÉ, en le disant) ou `facture` (toujours le montant facturé) ;
/// * `branchement_ifu` — la table « situation de l'acheteur → taux du barème arrêté qu'elle utilise » : quelle situation du barème est PRÉSUMÉE quand un IFU de
///   [longueurIfu] chiffres est renseigné (aujourd'hui : actif) et quand il est absent, le taux de repli quand le barème n'a aucun taux arrêté à la date.
///   Le branchement LIT le taux au barème, jamais une valeur propre ;
/// * `comptes` — les COMPTES de l'AIB (Direction, 09/11/2026) : AIB subi (créance sur l'État, 4492), AIB retenu / collecté (dette, 4478), imputation sur l'impôt
///   sur les bénéfices (891), compte fournisseur (401000). Aucun compte n'est écrit dans un moteur : la retenue et l'AIB subi lisent la version EN VIGUEUR à la date
///   de la pièce ; les pièces déjà passées gardent leurs comptes d'origine (une version de plus ne les réécrit pas). Tant que la validation (décideur + date) n'a
///   pas eu lieu, les comptes sont marqués « à confirmer par l'expert-comptable » : aucune source consultée ne confirme 4492 ;
/// * `bareme` — la revue du barème par situation (arrêt / maintien non arrêté) : le registre des décisions ; l'arrêt lui-même s'écrit dans `baremeAib`
///   par la mécanique de `m12-aib` ([cpdControlerVersionAib]), jamais dupliquée ici.
library;

import '../referentiels/versions_datees.dart';
import 'cpd_bareme_aib.dart';

/// La collection des paramètres de l'AIB (une fiche par version et par rubrique).
const String cpaCollection = 'parametresAib';

const String cpaRubriqueBase = 'base_retenue';
const String cpaRubriqueBranchement = 'branchement_ifu';
const String cpaRubriqueBareme = 'bareme';
const String cpaRubriqueComptes = 'comptes';

const List<(String, String)> cpaRubriques = [
  (cpaRubriqueBareme, 'Validation du barème AIB'),
  (cpaRubriqueBase, 'Validation de la base de l’AIB des factures fournisseurs'),
  (cpaRubriqueBranchement, 'Validation du branchement IFU'),
  (cpaRubriqueComptes, 'Validation des comptes de l’AIB'),
];

/// Les deux bases possibles de la retenue.
const String cpaBaseHt = 'ht';
const String cpaBaseFacture = 'facture';

const List<(String, String)> cpaBases = [
  (cpaBaseHt, 'Hors taxes (montant facturé si le hors taxes n’est pas renseigné)'),
  (cpaBaseFacture, 'Montant facturé (toujours)'),
];

/// Les deux décisions de la revue du barème.
const String cpaChoixArreter = 'arreter';
const String cpaChoixMaintenir = 'maintenir';

const List<(String, String)> cpaChoixBareme = [
  (cpaChoixArreter, 'Arrêter cette version'),
  (cpaChoixMaintenir, 'Maintenir non arrêtée'),
];

String _jour(Object? d) => d == null || '$d'.isEmpty ? '' : isoJour(d);

bool _actif(CpdFiche f) => '${f['statut'] ?? 'actif'}' == 'actif';

String _dateFr(String iso) => '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';

/// Les paramètres en vigueur à une date : ce que le moteur lit.
class CpdParametresAib {
  const CpdParametresAib({
    required this.base,
    required this.longueurIfu,
    required this.situationIfuRenseigne,
    required this.situationIfuAbsent,
    required this.tauxRepli,
    this.versionBase,
    this.versionBranchement,
    this.baseDepuis,
    this.branchementDepuis,
    this.deLaGraine = false,
  });

  /// `ht` ou `facture`.
  final String base;

  /// Le nombre de chiffres d'un IFU (13 à l'origine).
  final int longueurIfu;

  /// La situation du barème PRÉSUMÉE quand un IFU de [longueurIfu] chiffres est renseigné (l'activité n'est pas vérifiée auprès de la DGI).
  final String situationIfuRenseigne;

  /// La situation du barème quand aucun IFU n'est renseigné.
  final String situationIfuAbsent;

  /// Le taux (entier, en %) appliqué quand le barème n'a AUCUN taux arrêté en vigueur à la date (la Direction : 0, jamais un taux inventé).
  final int tauxRepli;

  final int? versionBase;
  final int? versionBranchement;
  final String? baseDepuis;
  final String? branchementDepuis;

  /// Vrai quand aucune version n'est enregistrée : les valeurs sont celles de la graine du code (poste jamais semé).
  final bool deLaGraine;

  /// La GRAINE : la valeur qui amorce la collection (et l'ultime repli d'une collection vide). Aucun appelant du poste ne la lit directement.
  static const CpdParametresAib graine = CpdParametresAib(
    base: cpaBaseHt,
    longueurIfu: 13,
    situationIfuRenseigne: 'ifu_actif',
    situationIfuAbsent: 'ifu_inactif_ou_absent',
    tauxRepli: 0,
    deLaGraine: true,
  );

  /// Une phrase qui dit d'où viennent les paramètres (affichée près du résultat).
  String get provenance => deLaGraine
      ? 'paramètres de la graine (aucune version enregistrée aux Paramètres)'
      : 'paramètres aux Paramètres : base v${versionBase ?? '—'}, branchement IFU v${versionBranchement ?? '—'}';
}

/// Le compte fournisseur de la graine (le sous-compte à six chiffres du plan, que la retenue débite).
const String cpaCompteFournisseurGraine = '401000';

/// Les quatre COMPTES de l'AIB (rubrique `comptes`), tels qu'ils s'appliquent à une date.
class CpdComptesAib {
  const CpdComptesAib({
    required this.subi,
    required this.retenu,
    required this.imputation,
    required this.fournisseur,
    this.version,
    this.depuis,
    this.decideur,
    this.deLaGraine = false,
  });

  /// Le compte de l'AIB SUBI (créance sur l'État) : débité par l'écriture d'AIB subi sur facture fournisseur.
  final String subi;

  /// Le compte de l'AIB RETENU / COLLECTÉ (dette envers l'État) : crédité par la retenue.
  final String retenu;

  /// Le compte d'IMPUTATION sur l'impôt sur les bénéfices (indiqué en lecture au registre, jamais écrit).
  final String imputation;

  /// Le compte FOURNISSEUR : débité par la retenue, crédité par l'AIB subi.
  final String fournisseur;

  final int? version;
  final String? depuis;

  /// Le décideur de la version : vide tant que les comptes n'ont pas été validés.
  final String? decideur;

  /// Vrai quand aucune version n'est enregistrée (collection vide) : les comptes sont ceux de la graine du code.
  final bool deLaGraine;

  /// Vrai tant que ces comptes n'ont pas été CONFIRMÉS (aucun décideur) : la graine, ou une version semée à l'installation.
  bool get aConfirmer => deLaGraine || (decideur ?? '').isEmpty;

  /// La GRAINE : les valeurs qui amorcent la collection (et l'ultime repli d'une collection vide). Aucun moteur du poste ne la lit directement.
  static const CpdComptesAib graine = CpdComptesAib(
    subi: cpdCompteAibSubi,
    retenu: cpdCompteAibRetenu,
    imputation: cpdCompteAibImputation,
    fournisseur: cpaCompteFournisseurGraine,
    deLaGraine: true,
  );

  String get provenance => deLaGraine
      ? 'comptes de la graine (aucune version enregistrée aux Paramètres)'
      : 'comptes aux Paramètres, version v${version ?? '—'}${aConfirmer ? ', à confirmer par l’expert-comptable' : ''}';

  /// Le marquage affiché près des comptes tant qu'ils ne sont pas validés ; vide une fois validés.
  String get marquage => aConfirmer ? 'À confirmer par l’expert-comptable (aucune décision enregistrée)' : '';
}

/// La fiche de [rubrique] EN VIGUEUR à [date] : la plus récente par date d'effet (puis par numéro de version) qui ne dépasse pas [date] ; une fiche sans
/// date d'effet vaut « depuis l'ouverture ». `null` quand aucune ne couvre la date.
CpdFiche? cpaFicheALaDate(Iterable<CpdFiche> fiches, String rubrique, DateTime date) {
  final jour = isoJour(date);
  final candidates = [
    for (final f in fiches)
      if (_actif(f) && '${f['rubrique']}' == rubrique && (_jour(f['dateEffet']).isEmpty || _jour(f['dateEffet']).compareTo(jour) <= 0)) f
  ];
  if (candidates.isEmpty) return null;
  int version(CpdFiche f) => (f['version'] as num?)?.toInt() ?? 0;
  candidates.sort((a, b) {
    final c = _jour(a['dateEffet']).compareTo(_jour(b['dateEffet']));
    return c != 0 ? c : version(a).compareTo(version(b));
  });
  return candidates.last;
}

/// Les versions ACTIVES d'une rubrique, de la plus ancienne à la plus récente.
List<CpdFiche> cpaVersionsDe(Iterable<CpdFiche> fiches, String rubrique) {
  final out = [for (final f in fiches) if (_actif(f) && '${f['rubrique']}' == rubrique) f];
  int version(CpdFiche f) => (f['version'] as num?)?.toInt() ?? 0;
  out.sort((a, b) {
    final c = _jour(a['dateEffet']).compareTo(_jour(b['dateEffet']));
    return c != 0 ? c : version(a).compareTo(version(b));
  });
  return out;
}

/// Le numéro de la PROCHAINE version d'une rubrique (1 + le plus grand existant, archivées comprises : un numéro ne se reprend jamais).
int cpaVersionSuivante(Iterable<CpdFiche> fiches, String rubrique) {
  var max = 0;
  for (final f in fiches) {
    if ('${f['rubrique']}' != rubrique) continue;
    final v = (f['version'] as num?)?.toInt() ?? 0;
    if (v > max) max = v;
  }
  return max + 1;
}

int? _entier(Object? v) => v is num ? (v == v.roundToDouble() ? v.toInt() : null) : int.tryParse('$v'.trim());

/// Les paramètres EN VIGUEUR à [date], lus aux fiches. Une rubrique sans fiche retombe sur la graine ([CpdParametresAib.deLaGraine] dit alors que rien
/// n'est enregistré).
CpdParametresAib cpaParametresALaDate(Iterable<CpdFiche> fiches, DateTime date) {
  const g = CpdParametresAib.graine;
  final base = cpaFicheALaDate(fiches, cpaRubriqueBase, date);
  final branch = cpaFicheALaDate(fiches, cpaRubriqueBranchement, date);
  if (base == null && branch == null) return g;
  final choixBase = '${base?['base'] ?? ''}';
  return CpdParametresAib(
    base: choixBase == cpaBaseFacture || choixBase == cpaBaseHt ? choixBase : g.base,
    longueurIfu: _entier(branch?['longueurIfu']) ?? g.longueurIfu,
    situationIfuRenseigne: '${branch?['situationIfuRenseigne'] ?? ''}'.isEmpty ? g.situationIfuRenseigne : '${branch!['situationIfuRenseigne']}',
    situationIfuAbsent: '${branch?['situationIfuAbsent'] ?? ''}'.isEmpty ? g.situationIfuAbsent : '${branch!['situationIfuAbsent']}',
    tauxRepli: _entier(branch?['tauxRepli']) ?? g.tauxRepli,
    versionBase: (base?['version'] as num?)?.toInt(),
    versionBranchement: (branch?['version'] as num?)?.toInt(),
    baseDepuis: base == null || _jour(base['dateEffet']).isEmpty ? null : _jour(base['dateEffet']),
    branchementDepuis: branch == null || _jour(branch['dateEffet']).isEmpty ? null : _jour(branch['dateEffet']),
  );
}

/// Les COMPTES de l'AIB EN VIGUEUR à [date], lus à la rubrique `comptes`. Sans fiche (collection vide), la graine, qui le dit ([CpdComptesAib.deLaGraine]) ;
/// une fiche qui ne porte pas un compte retombe, pour ce compte seul, sur la graine.
CpdComptesAib cpaComptesALaDate(Iterable<CpdFiche> fiches, DateTime date) {
  const g = CpdComptesAib.graine;
  final fiche = cpaFicheALaDate(fiches, cpaRubriqueComptes, date);
  if (fiche == null) return g;
  String compte(String cle, String repli) => '${fiche[cle] ?? ''}'.trim().isEmpty ? repli : '${fiche[cle]}'.trim();
  return CpdComptesAib(
    subi: compte('compteAibSubi', g.subi),
    retenu: compte('compteAibRetenu', g.retenu),
    imputation: compte('compteImputation', g.imputation),
    fournisseur: compte('compteFournisseur', g.fournisseur),
    version: (fiche['version'] as num?)?.toInt(),
    depuis: _jour(fiche['dateEffet']).isEmpty ? null : _jour(fiche['dateEffet']),
    decideur: fiche['decideur'] == null ? null : '${fiche['decideur']}',
  );
}

/// Les fiches qui AMORCENT la collection : une version 1 par rubrique à valeur, « depuis l'ouverture » (sans date d'effet : un champ nul ne s'écrit pas), marquée `aValider` — c'est une
/// valeur d'attente, pas une décision : aucun décideur n'y est écrit.
List<Map<String, Object?>> cpaFichesGraine() {
  const g = CpdParametresAib.graine;
  const c = CpdComptesAib.graine;
  const motif = 'Graine semée à l’installation : valeur d’attente, à valider par la Direction, la DAF, le comptable ou l’administrateur aux Paramètres.';
  return [
    {
      'id': 'PAA-BASE-1',
      'statut': 'actif',
      'rubrique': cpaRubriqueBase,
      'version': 1,
      'base': g.base,
      'graine': true,
      'aValider': true,
      'motif': motif,
    },
    {
      'id': 'PAA-IFU-1',
      'statut': 'actif',
      'rubrique': cpaRubriqueBranchement,
      'version': 1,
      'longueurIfu': g.longueurIfu,
      'situationIfuRenseigne': g.situationIfuRenseigne,
      'situationIfuAbsent': g.situationIfuAbsent,
      'tauxRepli': g.tauxRepli,
      'graine': true,
      'aValider': true,
      'motif': motif,
    },
    {
      'id': 'PAA-COMPTES-1',
      'statut': 'actif',
      'rubrique': cpaRubriqueComptes,
      'version': 1,
      'compteAibSubi': c.subi,
      'compteAibRetenu': c.retenu,
      'compteImputation': c.imputation,
      'compteFournisseur': c.fournisseur,
      'graine': true,
      'aValider': true,
      'aConfirmerExpertComptable': true,
      'motif': 'Comptes semés à l’installation : valeurs d’attente, À CONFIRMER PAR L’EXPERT-COMPTABLE (aucune source consultée ne confirme 4492 pour l’AIB subi), puis à valider aux Paramètres.',
    },
  ];
}

/// Le contrôle d'une validation AVANT écriture : un message de refus nommé, ou `null`. Commun aux quatre formulaires.
///
/// * décideur, date de la décision et motif obligatoires (la décision ne peut pas être postérieure à aujourd'hui) ;
/// * la date d'effet est obligatoire pour une version de `base_retenue`, de `branchement_ifu` et de `comptes`, et STRICTEMENT postérieure à celle de la version la plus
///   récente (une version ne se réécrit pas, une version insérée avant elle masquerait l'historique) ;
/// * `base_retenue` : la base est `ht` ou `facture` ; `branchement_ifu` : longueur entière de 1 à 20, situations ACTIVES du barème, taux de repli entier de
///   0 à 100.
String? cpaControlerVersion(String rubrique, Map<String, Object?> saisie, Iterable<CpdFiche> existantes, DateTime aujourdhui,
    {Iterable<CpdFiche>? situations}) {
  if ('${saisie['decideur'] ?? ''}'.trim().isEmpty) return 'PARAM_DECIDEUR_ABSENT : le décideur est obligatoire.';
  final decision = _jour(saisie['dateDecision']);
  if (decision.isEmpty) return 'PARAM_DATE_ABSENTE : la date de la décision est obligatoire.';
  if (decision.compareTo(isoJour(aujourdhui)) > 0) return 'PARAM_DATE_FUTURE : la date de la décision ne peut pas être postérieure à aujourd\'hui.';
  if ('${saisie['motif'] ?? ''}'.trim().isEmpty) return 'PARAM_MOTIF_ABSENT : le motif de la décision est obligatoire.';
  if (rubrique == cpaRubriqueBareme) return null;
  final effet = _jour(saisie['dateEffet']);
  if (effet.isEmpty) return 'PARAM_DATE_EFFET_ABSENTE : la date d\'effet de la nouvelle version est obligatoire.';
  final versions = cpaVersionsDe(existantes, rubrique);
  final datees = [for (final v in versions) if (_jour(v['dateEffet']).isNotEmpty) _jour(v['dateEffet'])]..sort();
  if (datees.isNotEmpty && datees.last.compareTo(effet) >= 0) {
    return 'PARAM_DATE_ANTERIEURE : la version la plus récente prend effet le ${_dateFr(datees.last)} — une nouvelle version prend une date d\'effet POSTÉRIEURE (le passé ne se réécrit pas).';
  }
  if (rubrique == cpaRubriqueBase) {
    final b = '${saisie['base'] ?? ''}';
    if (b != cpaBaseHt && b != cpaBaseFacture) return 'PARAM_BASE_INVALIDE : la base se choisit entre « hors taxes » et « montant facturé ».';
    return null;
  }
  if (rubrique == cpaRubriqueComptes) {
    const libelles = {
      'compteAibSubi': 'AIB subi (créance sur l’État)',
      'compteAibRetenu': 'AIB retenu ou collecté (dette envers l’État)',
      'compteImputation': 'imputation sur l’impôt sur les bénéfices',
      'compteFournisseur': 'fournisseur',
    };
    final vus = <String>{};
    for (final e in libelles.entries) {
      final compte = '${saisie[e.key] ?? ''}'.trim();
      if (!RegExp(r'^\d{3,8}$').hasMatch(compte)) {
        return 'PARAM_COMPTE_INVALIDE : le compte « $compte » (${e.value}) doit comporter de 3 à 8 chiffres.';
      }
      vus.add(compte);
    }
    if (vus.length != libelles.length) {
      return 'PARAM_COMPTES_CONFONDUS : les quatre comptes doivent être distincts — une créance et une dette sur l\'État ne se portent pas au même compte.';
    }
    return null;
  }
  if (rubrique == cpaRubriqueBranchement) {
    final l = _entier(saisie['longueurIfu']);
    if (l == null || l < 1 || l > 20) return 'PARAM_IFU_LONGUEUR : la longueur de l\'IFU doit être un nombre entier de chiffres, de 1 à 20.';
    final t = _entier(saisie['tauxRepli']);
    if (t == null || t < 0 || t > 100) return 'PARAM_TAUX_REPLI : le taux de repli doit être un pourcentage entier de 0 à 100.';
    if (situations != null) {
      final codes = {for (final s in cpdSituationsActives(situations)) '${s['code']}'};
      for (final k in ['situationIfuRenseigne', 'situationIfuAbsent']) {
        if (!codes.contains('${saisie[k] ?? ''}')) return 'PARAM_SITUATION_INCONNUE : la situation « ${saisie[k] ?? ''} » n\'est pas une situation active du barème de l\'AIB.';
      }
    }
    return null;
  }
  return 'PARAM_RUBRIQUE_INCONNUE : la rubrique « $rubrique » n\'existe pas.';
}

/// La BASE d'une retenue d'AIB sur une facture fournisseur, selon [parametres] : le montant, d'où il vient et la phrase qui le dit.
class CpdBaseRetenue {
  const CpdBaseRetenue({required this.base, required this.source, required this.motif, this.repli = false});
  final num base;

  /// `ht` ou `facture` : la base effectivement utilisée.
  final String source;
  final String motif;

  /// Vrai quand le choix était « hors taxes » mais que le hors-taxes n'est pas renseigné : la base est le montant facturé, et le motif le dit.
  final bool repli;
}

/// La base de la retenue de [facture] : le HT (`montantHT`) quand le paramètre dit « hors taxes » ET qu'il est renseigné ; sinon le montant facturé
/// (`montantFacture`), avec la raison.
CpdBaseRetenue cpaBaseRetenue(Map<String, Object?> facture, CpdParametresAib parametres) {
  final facturee = facture['montantFacture'] is num ? facture['montantFacture'] as num : num.tryParse('${facture['montantFacture'] ?? ''}') ?? 0;
  final ht = facture['montantHT'] is num ? facture['montantHT'] as num : num.tryParse('${facture['montantHT'] ?? ''}');
  final version = parametres.deLaGraine ? 'graine' : 'v${parametres.versionBase ?? '—'}';
  if (parametres.base == cpaBaseFacture) {
    return CpdBaseRetenue(base: facturee, source: cpaBaseFacture, motif: 'Base : montant facturé (choix des Paramètres, $version).');
  }
  if (ht != null && ht > 0) {
    return CpdBaseRetenue(base: ht, source: cpaBaseHt, motif: 'Base : montant hors taxes de la facture (choix des Paramètres, $version).');
  }
  return CpdBaseRetenue(
      base: facturee,
      source: cpaBaseFacture,
      repli: true,
      motif: 'Hors taxes non renseigné sur cette facture : la base de la retenue est le MONTANT FACTURÉ (repli du choix « hors taxes », $version) — renseigner le montant hors taxes de la facture pour une retenue juste.');
}

/// Le contrôle des MONTANTS d'une facture fournisseur à la saisie : le hors-taxes (facultatif) ne dépasse pas le montant facturé, et quand la TVA est portée
/// sur une ligne séparée (facultative aussi), HT + TVA = montant facturé. Un message de refus nommé, ou `null`.
String? cpaControlerMontantsFacture({Object? ht, Object? tva, Object? facture}) {
  num? n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}'.trim().replaceAll(',', '.'));
  final h = n(ht);
  final t = n(tva);
  final f = n(facture);
  if (h == null && t == null) return null;
  if (h != null && h < 0) return 'FACTURE_HT_NEGATIF : le montant hors taxes ne peut pas être négatif.';
  if (t != null && t < 0) return 'FACTURE_TVA_NEGATIVE : la TVA ne peut pas être négative.';
  if (h == null && t != null) return 'FACTURE_TVA_SANS_HT : la TVA s\'accompagne du montant hors taxes qu\'elle complète.';
  if (f != null && f > 0) {
    if (h! > f) return 'FACTURE_HT_SUPERIEUR : le montant hors taxes (${h.round()}) dépasse le montant facturé (${f.round()}).';
    if (t != null && (h + t - f).abs() > 0.5) {
      return 'FACTURE_TVA_INCOHERENTE : hors taxes (${h.round()}) + TVA (${t.round()}) ≠ montant facturé (${f.round()}).';
    }
  }
  return null;
}
