// LE PLANNING À TRAVERS LES POSTES (Direction de Baguidi, 17/11/2026, décision 12 : « planning, vacations, congés et présences voyagent entre postes, jamais vers le téléphone, avec les
// contrôles de la mère »).
//
// Cinq collections : `planning` (les vacations), `propositionsPlanning`, `conges`, `missions`, `presences`. Ce sont des FICHES modifiables champ par champ (famille A de la mère). Elles
// portent un circuit de validation ; or un fileul ne valide pas à la place du validateur : la validation SE DÉPOSE (collection `validationsDeposees`, genre [valGenrePlanningRh], le mécanisme
// de la continuité des validations, pas un second) et la MÈRE l'applique sous le rôle et le nom de l'auteur, avec SA matrice en force et SES fiches (le planning que tous les postes
// ont déjà versé) : c'est elle qui voit la double affectation entre deux postes hors ligne.
//
// Ce fichier porte ce qui est PUR et partagé par la mère (Dart et banc Node) et par le poste :
//  * [refusPlanningRh] : le contrôle que la mère REFAIT sur ce qu'un poste écrit (une pièce ne naît ni ne devient « validée » par un poste ; une validation ne se défait pas ; une vacation
//    validée ne se réécrit pas) ;
//  * [planningRhDeposer] : la fiche de dépôt (dédoublonnée) ;
//  * [fusionnerPlanningRh] : la fusion de réception qui ne défait jamais une validation.
//
// Aucun rôle n'est écrit ici : la matrice décide, à l'application, par les gestes réservés du circuit (`rh_etape_surveillant`, `rh_etape_daf`, `rh_encadrer`).
library;

import '../validation/validation.dart' show RefusValidation, valInstant;
import '../validation/validation_deposee.dart';
import 'planning_rh.dart' show RefusRh, gardePresenceValideeRh;
import 'rhb_regles.dart' show vacationCompteRh, vacationEtatAValider, vacationEtatValidee;

/// Les cinq collections du planning qui voyagent (famille A de la mère ; jamais vers un téléphone : elles portent des honoraires, des motifs d'absence et des données de santé).
const List<String> planningCollectionsSync = ['planning', 'propositionsPlanning', 'conges', 'missions', 'presences'];

/// Le genre de dépôt des gestes de validation du planning (à côté de `referentiel`, `circuit_achat`, `reglage_clinique`, `pta_plan`).
const String valGenrePlanningRh = 'planning_rh';

/// Les actions déposables : poser une vacation (pose chez un fileul, validée par la mère), remplacer une vacation validée, retirer une vacation, trancher une pièce (pointage, congé, ordre
/// de mission), trancher une proposition.
const String planningActionPoser = 'poser';
const String planningActionRemplacer = 'remplacer';
const String planningActionRetirer = 'retirer';
const String planningActionTrancher = 'trancher';
const String planningActionProposition = 'proposition';
const List<String> planningActions = [planningActionPoser, planningActionRemplacer, planningActionRetirer, planningActionTrancher, planningActionProposition];

/// Les collections à circuit de validation (pointage, congé, ordre de mission).
const List<String> planningPiecesACircuit = ['presences', 'conges', 'missions'];

/// Le rang d'un état de validation d'une pièce : une validation n'est jamais défaite par une fusion ni par une écriture (le refus et la validation complète sont tous deux « décidés »).
const Map<String, int> planningRangPiece = {'a_valider': 0, 'valide_surveillant': 1, 'valide': 2, 'refuse': 2};

/// Les états qu'un poste n'écrit pas lui-même (ils se déposent).
const List<String> planningEtatsPieceReserves = ['valide_surveillant', 'valide', 'refuse'];

/// Les champs d'une pièce validée ou refusée que SEULE la mère écrit (la trace de la décision).
const List<String> planningChampsDecisionPiece = ['validePar', 'valideLe', 'motifRefus', 'refuseePar', 'refuseeLe', 'valideePar', 'valideeLe'];

/// Les champs d'une proposition tranchée que SEULE la mère écrit.
const List<String> planningChampsDecisionProposition = ['tranchePar', 'trancheLe', 'appliquees', 'motifRefus', 'motifValidation'];

/// Le programme d'une vacation : ce qu'une vacation validée ne se réécrit pas.
const List<String> planningChampsProgrammeVacation = ['date', 'employeId', 'type', 'employe', 'fonction', 'service'];

const Map<String, int> planningRangProposition = {'proposee': 0, 'annulee': 1, 'validee': 2, 'refusee': 2};

String _s(Object? v) => v == null ? '' : '$v';
bool _vide(Object? v) => v == null || v == '' || (v is List && v.isEmpty);
bool _meme(Object? a, Object? b) => '${_norm(a)}' == '${_norm(b)}';
Object? _norm(Object? v) => v is Map ? (v.keys.map((k) => '$k').toList()..sort()).map((k) => '$k:${_norm(v[k])}').join(',') : (v is List ? v.map(_norm).join('|') : v);

/// Une vacation est VALIDÉE quand elle ne dit pas le contraire : sans état (jeu d'origine, pose directe d'autrefois) ou `validee` (même lecture que le calcul des honoraires de régime, RG-11).
bool planningVacationValidee(Map<String, Object?> v) => vacationCompteRh(v);

/// L'état de validation d'une pièce à circuit (même lecture que `etatValidationRh`, sans en dépendre : la mère Node la recopie).
String planningEtatPiece(String collection, Map<String, Object?> rec) {
  final e = _s(rec['validationEtat']);
  if (e.isNotEmpty) return e;
  if (collection == 'conges') {
    final s = _s(rec['statutConge']);
    return s == 'en_attente' ? 'a_valider' : (s == 'refuse' ? 'refuse' : 'valide');
  }
  if (collection == 'missions') {
    final s = _s(rec['statutMission']);
    return (s == 'a_valider' || s == 'projet') ? 'a_valider' : (s == 'refusee' ? 'refuse' : 'valide');
  }
  return 'valide';
}

/// LE CONTRÔLE QUE LA MÈRE REFAIT sur une écriture d'un poste (jamais sur ses propres écritures : elle applique les dépôts). [type] : `creer` ou `modifier` ; [champs] : ce qui est écrit ;
/// [actuelle] : la fiche telle que la mère la détient (`null` à la création). `null` : l'écriture passe.
///
///  * une pièce (pointage, congé, ordre de mission) ou une proposition NAÎT « à valider » : un poste ne la crée pas déjà validée, refusée ou tranchée ;
///  * l'état de validation ne s'écrit pas par un poste (il se DÉPOSE : la mère l'applique sous le rôle de l'auteur), ni la trace de la décision ;
///  * une validation ne se DÉFAIT pas : une fusion tardive ne ramène pas une pièce validée à « à valider » ;
///  * une vacation NAÎT « à valider » (la pose se dépose) ; une vacation VALIDÉE ne se réécrit pas (programme) ni ne s'archive par un poste : le remplacement et le retrait se déposent ;
///  * un pointage validé ne se modifie que par une régularisation tracée (même garde qu'au poste).
RefusRh? refusPlanningRh(String collection, String type, Map<String, Object?> champs, {Map<String, Object?>? actuelle}) {
  if (!planningCollectionsSync.contains(collection)) return null;
  final creation = type == 'creer';
  RefusRh reserve(String quoi) => RefusRh('validation_reservee',
      '$quoi : la décision ne s’écrit pas par un poste, elle se DÉPOSE depuis le poste du validateur et la mère l’applique sous son rôle, ses contrôles refaits.', 'Déposer la décision depuis l’écran du circuit');
  RefusRh champReserve(String k) => RefusRh('champ_reserve',
      'Le champ « $k » est la trace d’une décision : il n’est écrit que par la mère, à l’application du dépôt du validateur.', 'Déposer la décision depuis l’écran du circuit');

  if (planningPiecesACircuit.contains(collection)) {
    final nouveau = champs['validationEtat'];
    final courant = actuelle == null ? 'a_valider' : planningEtatPiece(collection, actuelle);
    if (creation) {
      if (nouveau != null && '$nouveau' != 'a_valider' && '$nouveau' != '') return reserve('Une pièce ne naît pas déjà « $nouveau »');
      final sc = champs['statutConge'], sm = champs['statutMission'];
      if (collection == 'conges' && sc != null && '$sc' != 'en_attente') return reserve('Une demande de congé ne naît pas déjà « $sc »');
      if (collection == 'missions' && sm != null && '$sm' != 'a_valider' && '$sm' != 'projet') return reserve('Un ordre de mission ne naît pas déjà « $sm »');
    } else if (nouveau != null && '$nouveau' != courant) {
      final rn = planningRangPiece['$nouveau'], rc = planningRangPiece[courant];
      if (rn == null) return RefusRh('etat_inconnu', 'État de validation inconnu : $nouveau.', 'Choisir a_valider, valide_surveillant, valide ou refuse');
      if (rc != null && rn < rc) {
        return RefusRh('validation_defaite', 'Une validation ne se défait pas : la pièce est « $courant », elle ne repasse pas à « $nouveau ».', 'Faire une nouvelle demande plutôt que de défaire la décision');
      }
      if (planningEtatsPieceReserves.contains('$nouveau')) return reserve('L’état « $nouveau »');
    }
    if (collection == 'conges' && !creation) {
      final s = champs['statutConge'];
      if (s != null && (s == 'valide' || s == 'refuse') && '${actuelle?['statutConge'] ?? ''}' != '$s') return reserve('Le statut « $s » du congé');
    }
    if (collection == 'missions' && !creation) {
      final s = champs['statutMission'];
      if (s != null && (s == 'validee' || s == 'refusee') && '${actuelle?['statutMission'] ?? ''}' != '$s') return reserve('Le statut « $s » de l’ordre de mission');
    }
    for (final k in planningChampsDecisionPiece) {
      if (champs.containsKey(k) && !_vide(champs[k]) && (creation || !_meme(champs[k], actuelle?[k]))) return champReserve(k);
    }
    if (collection == 'presences' && !creation && actuelle != null) {
      final motif = gardePresenceValideeRh('modifier', actuelle, {...actuelle, ...champs});
      if (motif != null) {
        return RefusRh('presence_validee', 'Un pointage validé ne se modifie pas directement : il se régularise (motif, date et auteur consignés).', 'Régulariser le pointage depuis l’écran des présences');
      }
    }
    return null;
  }

  if (collection == 'propositionsPlanning') {
    final nouveau = champs['etat'];
    final courant = actuelle == null ? 'proposee' : _s(actuelle['etat']);
    if (creation) {
      if (nouveau != null && '$nouveau' != 'proposee') return reserve('Une proposition ne naît pas déjà « $nouveau »');
    } else if (nouveau != null && '$nouveau' != courant) {
      final rn = planningRangProposition['$nouveau'], rc = planningRangProposition[courant];
      if (rn == null) return RefusRh('etat_inconnu', 'État de proposition inconnu : $nouveau.', 'Choisir proposee, validee, refusee ou annulee');
      if (rc != null && rn < rc) {
        return RefusRh('etat_regressif', 'Une proposition tranchée ne recule pas : elle est « $courant », elle ne repasse pas à « $nouveau ».', 'Faire une nouvelle proposition');
      }
      if (nouveau == 'validee' || nouveau == 'refusee') return reserve('L’état « $nouveau » d’une proposition');
    }
    for (final k in planningChampsDecisionProposition) {
      if (champs.containsKey(k) && !_vide(champs[k]) && (creation || !_meme(champs[k], actuelle?[k]))) return champReserve(k);
    }
    return null;
  }

  // planning : les vacations.
  final etat = champs['validationEtat'];
  if (creation) {
    if (etat == null || '$etat' != vacationEtatAValider) {
      return reserve('Une vacation ne naît pas validée (état « ${_vide(etat) ? 'absent' : etat} »)');
    }
    for (final k in const ['validePar', 'valideLe']) {
      if (!_vide(champs[k])) return champReserve(k);
    }
    return null;
  }
  final validee = actuelle != null && planningVacationValidee(actuelle);
  if (etat != null && '$etat' != _s(actuelle?['validationEtat'])) {
    if ('$etat' == vacationEtatAValider && validee) {
      return RefusRh('validation_defaite', 'Une validation ne se défait pas : la vacation est validée, elle ne repasse pas « à valider ».', 'Retirer la vacation (dépôt) plutôt que de défaire la décision');
    }
    if ('$etat' == vacationEtatValidee || '$etat' == '') return reserve('L’état « validée » d’une vacation');
  }
  for (final k in const ['validePar', 'valideLe']) {
    if (champs.containsKey(k) && !_vide(champs[k]) && !_meme(champs[k], actuelle?[k])) return champReserve(k);
  }
  if (validee) {
    for (final k in planningChampsProgrammeVacation) {
      if (champs.containsKey(k) && !_meme(champs[k], actuelle[k])) {
        return RefusRh('vacation_validee', 'Une vacation validée ne se réécrit pas (« $k ») : le remplacement se DÉPOSE depuis le poste du validateur, la mère le contrôle et l’applique.', 'Déposer le remplacement, ou proposer la modification');
      }
    }
    if (_s(champs['statut']) == 'archive' && _s(actuelle['statut']) != 'archive') {
      return RefusRh('vacation_validee', 'Une vacation validée ne se retire pas par un poste : le retrait se DÉPOSE depuis le poste du validateur, la mère l’applique.', 'Déposer le retrait');
    }
  }
  return null;
}

/// DÉPOSE un geste de validation du planning depuis un poste rattaché. Les contrôles du geste (droit, circuit, refus nommé) sont faits par l'appelant sur SES fiches, à blanc, avant d'appeler :
/// ici, la forme de la fiche et sa non-duplication. Un dépôt identique (même action, même pièce, même décision, même rôle) qui attend déjà la mère n'est pas doublé.
VerdictDepot planningRhDeposer({
  required String action,
  required String collection,
  required String cible,
  required String libelle,
  required String role,
  required String acteur,
  required String poste,
  required DateTime maintenant,
  required List<Map<String, Object?>> depots,
  required String Function() nouvelId,
  String? decision,
  String? motif,
  Map<String, Object?>? valeurs,
}) {
  if (!planningActions.contains(action)) {
    return const VerdictDepot.refus(RefusValidation('ACTION_INCONNUE', 'Cette action du planning ne se dépose pas.', 'Choisir poser, remplacer, retirer, trancher ou proposition'));
  }
  if (!planningCollectionsSync.contains(collection)) {
    return VerdictDepot.refus(RefusValidation('COLLECTION_INCONNUE', 'La collection « $collection » ne passe pas par le circuit du planning.', 'Choisir une pièce du planning'));
  }
  for (final d in depots) {
    if (d['statut'] != 'archive' &&
        d['etat'] == valDepotDeposee &&
        d['genre'] == valGenrePlanningRh &&
        d['action'] == action &&
        d['collection'] == collection &&
        d['cible'] == cible &&
        d['decision'] == decision &&
        d['demandeRole'] == role) {
      return VerdictDepot.ok(d, dejaDepose: true);
    }
  }
  return VerdictDepot.ok({
    'id': nouvelId(),
    'statut': 'actif',
    'genre': valGenrePlanningRh,
    'famille': 'planning_$action',
    'action': action,
    'collection': collection,
    'cible': cible,
    'libelle': libelle,
    'etat': valDepotDeposee,
    'demandeRole': role,
    'demandePar': acteur,
    'demandePoste': poste,
    'demandeLe': valInstant(maintenant),
    if (decision != null) 'decision': decision,
    if (motif != null && motif.trim().isNotEmpty) 'motif': motif.trim(),
    if (valeurs != null && valeurs.isNotEmpty) 'valeurs': valeurs,
  });
}

/// FUSION DE RÉCEPTION : [fusion] est la fusion champ à champ déjà faite, [local] et [recu] les deux versions face à face. Une validation que le journal porte n'est jamais défaite : si l'état reçu
/// est plus avancé, il l'emporte avec la trace de la décision ; un état plus avancé inventé ICI (poste rattaché, écriture refusée par la mère) cède au journal.
/// [posteFileul] : ce poste ne détient pas la mère ; [refusLocal] : la mère a refusé la dernière écriture de ce poste sur cette fiche.
void fusionnerPlanningRh(String collection, Map<String, Object?> fusion, Map<String, Object?> local, Map<String, Object?> recu, {bool refusLocal = false, bool posteFileul = false}) {
  if (!planningCollectionsSync.contains(collection)) return;
  if (planningPiecesACircuit.contains(collection)) {
    final rl = planningRangPiece[planningEtatPiece(collection, local)] ?? 0, rr = planningRangPiece[planningEtatPiece(collection, recu)] ?? 0;
    if (!(rr > rl || (posteFileul && refusLocal && rl > rr))) return;
    final cles = ['validationEtat', 'etapesFaites', 'circuitUtilise', 'statutConge', 'statutMission', ...planningChampsDecisionPiece];
    for (final k in cles) {
      if (recu.containsKey(k)) {
        fusion[k] = recu[k];
      } else {
        fusion.remove(k);
      }
    }
    return;
  }
  if (collection == 'propositionsPlanning') {
    final rl = planningRangProposition[_s(local['etat'])] ?? 0, rr = planningRangProposition[_s(recu['etat'])] ?? 0;
    if (!(rr > rl || (posteFileul && refusLocal && rl > rr))) return;
    for (final k in ['etat', ...planningChampsDecisionProposition, 'annuleeLe']) {
      if (recu.containsKey(k)) {
        fusion[k] = recu[k];
      } else {
        fusion.remove(k);
      }
    }
    return;
  }
  // planning : une vacation validée (journal) ne redevient pas « à valider » ; une validation inventée ici cède.
  final vl = planningVacationValidee(local), vr = planningVacationValidee(recu);
  if ((vr && !vl) || (posteFileul && refusLocal && vl && !vr)) {
    for (final k in ['validationEtat', 'statut', 'validePar', 'valideLe', 'origine']) {
      if (recu.containsKey(k)) {
        fusion[k] = recu[k];
      } else {
        fusion.remove(k);
      }
    }
  }
}

/// Les doublons d'AFFECTATION entre postes : des vacations actives du même agent le même jour (ce que `controlerVacationRh` refuse à la saisie, et qu'aucun poste hors ligne ne pouvait voir).
/// Marqueur LOCAL, déduit : jamais corrigé en silence. Seules comptent les vacations validées et les en attente non archivées.
List<List<Map<String, Object?>>> planningAffectationsEnDoublon(Iterable<Map<String, Object?>> vacations) {
  final par = <String, List<Map<String, Object?>>>{};
  for (final v in vacations) {
    if (v['statut'] == 'archive') continue;
    final e = _s(v['employeId']), d = _s(v['date']);
    if (e.isEmpty || d.length < 10) continue;
    (par['$e|${d.substring(0, 10)}'] ??= []).add(v);
  }
  return [for (final g in par.values) if (g.length > 1) g];
}
