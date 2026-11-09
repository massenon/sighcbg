/// L'AIB SUBI SUR UNE FACTURE FOURNISSEUR (M7 → M12) — position de la Direction du 09/11/2026 (`docs/prd/POSITION-AIB-2026-11-09.md`).
///
/// Quand un fournisseur FACTURE un AIB à la clinique (acompte sur l'impôt sur les bénéfices, au taux de 1 % ou de 5 % selon la situation de l'acheteur), c'est
/// l'ACHETEUR qui le supporte : il n'est pas une charge, c'est une CRÉANCE sur l'État, imputée en fin d'année sur l'impôt sur les bénéfices. La clinique le
/// constate par UNE pièce plate, en BROUILLON, contrôlée équilibrée avant écriture (RG-10) : débit du compte d'AIB subi, crédit du compte fournisseur du même
/// montant, journal des achats. La facture PORTE son AIB subi (`aibSubi` : montant, taux, date, `ecritureIds`) et n'est jamais réécrite ; elle n'en porte qu'un.
///
/// L'AIB facturé (`aibFacture` : montant, taux, base hors taxes) est un renseignement FACULTATIF de la facture, saisi en montants ENTIERS et refusé en le
/// disant quand il n'est pas cohérent (montant ≠ base × taux, arrondi au franc). Le taux n'est pas un taux « commode » : il se compare au barème arrêté en
/// vigueur à la date de la facture ; un taux qui ne correspond à aucune version arrêtée ne BLOQUE pas (le fournisseur a facturé ce qu'il a facturé) mais est
/// SIGNALÉ « taux non arrêté au barème ».
///
/// LES COMPTES ne sont pas écrits ici : ils se lisent aux Paramètres (`cpaComptesALaDate`, rubrique `comptes`) à la date de la pièce. Aucune écriture d'AIB
/// COLLECTÉ sur les ventes de la clinique : hors périmètre, position documentée (le montant payé par l'acheteur inclurait l'AIB : à valider avant de toucher
/// aux écritures d'encaissement). L'imputation sur l'impôt sur les bénéfices est INDIQUÉE en lecture ([cpdImputationAibExercice]), jamais écrite.
library;

import '../referentiels/versions_datees.dart';
import 'cpd_bareme_aib.dart';
import 'cpd_parametres_aib.dart';

/// Refus nommé d'une opération d'AIB subi : rien n'a été écrit.
class RefusAibSubi implements Exception {
  const RefusAibSubi(this.motif);
  final String motif;
  @override
  String toString() => motif;
}

num? _nombre(Object? v) {
  if (v is num) return v;
  final s = '${v ?? ''}'.trim().replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.');
  return s.isEmpty ? null : num.tryParse(s);
}

bool _vide(Object? v) => '${v ?? ''}'.trim().isEmpty;

String _f(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$b';
}

String _dateFr(String iso) => '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';

/// L'AIB FACTURÉ n'est-il pas renseigné du tout (les trois champs vides) ? Il est facultatif : vide, il n'y a rien à contrôler.
bool cpdAibFactureVide({Object? montant, Object? taux, Object? base}) => _vide(montant) && _vide(taux) && _vide(base);

/// Le contrôle de l'AIB facturé à la SAISIE : un message de refus nommé, ou `null`.
///
/// * les trois champs vont ensemble (montant, taux, base hors taxes) : tous vides (facultatif) ou tous renseignés ;
/// * montants ENTIERS (le poste calcule au franc), strictement positifs ; taux entier de 1 à 100 ;
/// * COHÉRENCE : montant = base × taux / 100, arrondi au franc ([cpdMontantAib]) ;
/// * la base ne dépasse pas le montant facturé de la pièce quand celui-ci est connu.
String? cpdControlerAibFacture({Object? montant, Object? taux, Object? base, Object? montantFacture}) {
  if (cpdAibFactureVide(montant: montant, taux: taux, base: base)) return null;
  if (_vide(montant) || _vide(taux) || _vide(base)) {
    return 'AIB_FACTURE_INCOMPLET : l\'AIB facturé se renseigne en entier — le montant, le taux et la base hors taxes — ou pas du tout.';
  }
  final m = _nombre(montant);
  final t = _nombre(taux);
  final b = _nombre(base);
  if (m == null || t == null || b == null) return 'AIB_FACTURE_NON_NUMERIQUE : le montant, le taux et la base de l\'AIB facturé sont des nombres.';
  if (m != m.roundToDouble() || b != b.roundToDouble()) {
    return 'AIB_FACTURE_NON_ENTIER : les montants de l\'AIB facturé (montant et base hors taxes) s\'écrivent en francs entiers.';
  }
  if (t != t.roundToDouble() || t < 1 || t > 100) return 'AIB_FACTURE_TAUX_INVALIDE : le taux de l\'AIB facturé (« ${'${taux ?? ''}'.trim()} ») est un pourcentage entier de 1 à 100.';
  if (m <= 0 || b <= 0) return 'AIB_FACTURE_MONTANT_NUL : le montant et la base hors taxes de l\'AIB facturé sont strictement positifs.';
  final attendu = cpdMontantAib(b, t);
  if (attendu != m.round()) {
    return 'AIB_FACTURE_INCOHERENT : ${t.round()} % de ${_f(b)} (base hors taxes) font ${_f(attendu)}, et non ${_f(m)} — corriger le montant, le taux ou la base.';
  }
  final f = _nombre(montantFacture);
  if (f != null && f > 0 && b > f) {
    return 'AIB_FACTURE_BASE_SUPERIEURE : la base hors taxes de l\'AIB (${_f(b)}) dépasse le montant facturé (${_f(f)}).';
  }
  return null;
}

/// La fiche `aibFacture` à écrire sur la facture, ou `null` (champs vides : l'AIB facturé se RETIRE). Suppose [cpdControlerAibFacture] passé.
Map<String, Object?>? cpdAibFactureDepuisSaisie({Object? montant, Object? taux, Object? base}) {
  if (cpdAibFactureVide(montant: montant, taux: taux, base: base)) return null;
  return {'montant': _nombre(montant)!.round(), 'taux': _nombre(taux)!.round(), 'baseHt': _nombre(base)!.round()};
}

/// Le SIGNAL « taux non arrêté au barème » : `null` quand [taux] est celui d'une version ARRÊTÉE du barème en vigueur à [date] (n'importe quelle situation :
/// l'AIB facturé l'a été à la situation du fournisseur, que le poste ne connaît pas) ; sinon la phrase qui le dit, avec ce qui est arrêté. Ne bloque rien.
String? cpdSignalTauxAibFacture(Iterable<CpdFiche> situations, Iterable<CpdFiche> versions, num taux, DateTime date) {
  final arretes = <num>{
    for (final b in cpdBaremeEnVigueur(situations, versions, date))
      if (b.reponse.taux != null) b.reponse.taux!,
  };
  if (arretes.contains(taux)) return null;
  final jour = _dateFr(isoJour(date));
  final dit = arretes.isEmpty ? 'aucun taux n\'est arrêté' : 'arrêté${arretes.length > 1 ? 's' : ''} : ${(arretes.toList()..sort()).map((t) => '${t == t.roundToDouble() ? t.toInt() : t} %').join(', ')}';
  return 'Taux non arrêté au barème : ${taux == taux.roundToDouble() ? taux.toInt() : taux} % ne correspond à aucune version arrêtée du barème en vigueur au $jour ($dit). L\'AIB facturé est constaté tel que le fournisseur l\'a facturé ; la Direction arrête le barème aux Paramètres.';
}

/// Le contrôle AVANT « Constater l'AIB subi » : un message de refus nommé, ou `null`. Une facture archivée n'en reçoit pas, il faut un AIB facturé
/// cohérent, et une facture ne porte QU'UN AIB subi (la corriger passe par une nouvelle pièce, jamais en la réécrivant).
String? cpdControlerAibSubi(Map<String, Object?> facture) {
  if ('${facture['statut'] ?? 'actif'}' != 'actif') return 'Une facture archivée ne reçoit pas d\'AIB subi.';
  final a = facture['aibFacture'];
  if (a is! Map) return 'AIB_SUBI_SANS_AIB_FACTURE : cette facture ne porte pas d\'AIB facturé — le renseigner (montant, taux, base hors taxes) en modifiant la facture.';
  if (facture['aibSubi'] is Map) return 'Cette facture porte déjà son AIB subi : le corriger se fait par une nouvelle pièce, jamais en le réécrivant.';
  return cpdControlerAibFacture(montant: a['montant'], taux: a['taux'], base: a['baseHt'], montantFacture: facture['montantFacture']);
}

/// Ce que « Constater l'AIB subi » produit : les deux lignes plates de la pièce (brouillon) et la fiche que la facture PORTERA (sans `ecritureIds`, que
/// l'appelant ajoute une fois les lignes écrites).
class CpdAibSubiConstate {
  const CpdAibSubiConstate({required this.ecritures, required this.fiche});
  final List<Map<String, Object?>> ecritures;
  final Map<String, Object?> fiche;
}

/// Construit la pièce d'AIB subi de [facture] à [date], aux [comptes] EN VIGUEUR à cette date. Refus nommé ([RefusAibSubi]) : facture archivée, pas d'AIB
/// facturé, déjà constaté, incohérent, ou pièce déséquilibrée (RG-10). [signalTaux] (voir [cpdSignalTauxAibFacture]) est porté par la fiche.
CpdAibSubiConstate cpdConstaterAibSubi({
  required Map<String, Object?> facture,
  required DateTime date,
  required CpdComptesAib comptes,
  required String numero,
  String? signalTaux,
}) {
  final refus = cpdControlerAibSubi(facture);
  if (refus != null) throw RefusAibSubi(refus);
  final a = (facture['aibFacture'] as Map).cast<String, Object?>();
  final montant = _nombre(a['montant'])!.round();
  final taux = _nombre(a['taux'])!.round();
  final reference = '${facture['reference'] ?? facture['id']}';
  final fournisseur = '${facture['fournisseurNom'] ?? facture['fournisseur'] ?? ''}';
  final jour = isoJour(date);
  final base = <String, Object?>{
    'numero': numero,
    'date': jour,
    'journal': 'ACH',
    'journalLibelle': 'Journal des achats',
    'libelle': 'AIB subi $taux % — facture $reference — $fournisseur',
    'pieceId': '${facture['id']}',
    'pieceNumero': reference,
    'origine': 'Automatique — AIB subi',
    'statut': 'brouillon',
  };
  final lignes = [
    {...base, 'compte': comptes.subi, 'compteLibelle': 'AIB subi (créance sur l\'État)', 'debit': montant, 'credit': 0},
    {...base, 'compte': comptes.fournisseur, 'compteLibelle': 'Fournisseurs', 'debit': 0, 'credit': montant},
  ];
  final d = lignes.fold<num>(0, (s, l) => s + (l['debit'] as num));
  final c = lignes.fold<num>(0, (s, l) => s + (l['credit'] as num));
  if (d != c) throw RefusAibSubi('Écriture déséquilibrée (débit $d ≠ crédit $c) : AIB subi refusé (RG-10).');
  return CpdAibSubiConstate(ecritures: lignes, fiche: {
    'montant': montant,
    'taux': taux,
    'base': _nombre(a['baseHt'])!.round(),
    'date': jour,
    'compteSubi': comptes.subi,
    'compteFournisseur': comptes.fournisseur,
    if (comptes.version != null) 'comptesVersion': comptes.version,
    if (signalTaux != null) 'signalTaux': signalTaux,
  });
}

/// Le registre de l'AIB SUBI : une ligne par facture qui le porte, avec le total et les totaux par mois.
class CpdRegistreAibSubi {
  const CpdRegistreAibSubi({required this.lignes, required this.parMois, required this.total});
  final List<Map<String, Object?>> lignes;
  final Map<String, int> parMois;
  final int total;
}

CpdRegistreAibSubi cpdRegistreAibSubi(Iterable<Map<String, Object?>> factures) {
  final lignes = <Map<String, Object?>>[];
  final parMois = <String, int>{};
  var total = 0;
  for (final f in factures) {
    if ('${f['statut'] ?? 'actif'}' != 'actif') continue;
    final s = f['aibSubi'];
    if (s is! Map) continue;
    final date = DateTime.tryParse('${s['date'] ?? f['date'] ?? ''}');
    final m = (s['montant'] as num?)?.round() ?? 0;
    final mois = date == null ? '—' : isoJour(date).substring(0, 7);
    parMois[mois] = (parMois[mois] ?? 0) + m;
    total += m;
    lignes.add({
      'reference': f['reference'],
      'fournisseur': f['fournisseurNom'],
      'date': date == null ? null : isoJour(date),
      'taux': s['taux'],
      'base': s['base'],
      'montant': m,
      'compte': s['compteSubi'],
      'signalTaux': s['signalTaux'],
    });
  }
  lignes.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  return CpdRegistreAibSubi(lignes: lignes, parMois: parMois, total: total);
}

/// L'IMPUTATION sur l'impôt sur les bénéfices, INDIQUÉE en lecture (jamais écrite) : l'AIB subi et l'AIB retenu de l'exercice [annee], leur total, et le
/// compte d'imputation des Paramètres.
class CpdImputationAib {
  const CpdImputationAib({required this.annee, required this.subi, required this.retenu, required this.compteImputation});
  final int annee;
  final int subi;
  final int retenu;
  final String compteImputation;
  int get total => subi + retenu;
}

CpdImputationAib cpdImputationAibExercice(Iterable<Map<String, Object?>> factures, int annee, CpdComptesAib comptes) {
  int deLAnnee(Object? cle, Object? repli) {
    final d = DateTime.tryParse('${cle ?? repli ?? ''}');
    return d?.year ?? -1;
  }

  var subi = 0;
  var retenu = 0;
  for (final f in factures) {
    if ('${f['statut'] ?? 'actif'}' != 'actif') continue;
    final s = f['aibSubi'];
    if (s is Map && deLAnnee(s['date'], f['date']) == annee) subi += (s['montant'] as num?)?.round() ?? 0;
    final r = f['retenueAib'];
    if (r is Map && deLAnnee(r['date'], f['date']) == annee) retenu += (r['montant'] as num?)?.round() ?? 0;
  }
  return CpdImputationAib(annee: annee, subi: subi, retenu: retenu, compteImputation: comptes.imputation);
}
