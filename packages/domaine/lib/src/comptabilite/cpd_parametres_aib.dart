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
/// Quatre rubriques :
///
/// * `base_retenue` — la base de la retenue d'AIB sur une facture fournisseur : `ht` (le montant hors taxes quand il est renseigné, sinon repli SUR LE MONTANT
///   FACTURÉ, en le disant) ou `facture` (toujours le montant facturé) ;
/// * `branchement_ifu` — la table « situation de l'acheteur → taux du barème arrêté qu'elle utilise » : quelle situation du barème est PRÉSUMÉE quand un IFU de
///   [longueurIfu] chiffres est renseigné (aujourd'hui : actif) et quand il est absent, le taux de repli quand le barème n'a aucun taux arrêté à la date.
///   Le branchement LIT le taux au barème, jamais une valeur propre ;
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

const List<(String, String)> cpaRubriques = [
  (cpaRubriqueBareme, 'Validation du barème AIB'),
  (cpaRubriqueBase, 'Validation de la base de l’AIB des factures fournisseurs'),
  (cpaRubriqueBranchement, 'Validation du branchement IFU'),
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

/// Les fiches qui AMORCENT la collection : une version 1 par rubrique à valeur, « depuis l'ouverture » (sans date d'effet : un champ nul ne s'écrit pas), marquée `aValider` — c'est une
/// valeur d'attente, pas une décision : aucun décideur n'y est écrit.
List<Map<String, Object?>> cpaFichesGraine() {
  const g = CpdParametresAib.graine;
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
  ];
}

/// Le contrôle d'une validation AVANT écriture : un message de refus nommé, ou `null`. Commun aux trois formulaires.
///
/// * décideur, date de la décision et motif obligatoires (la décision ne peut pas être postérieure à aujourd'hui) ;
/// * la date d'effet est obligatoire pour une version de `base_retenue` et de `branchement_ifu`, et STRICTEMENT postérieure à celle de la version la plus
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
