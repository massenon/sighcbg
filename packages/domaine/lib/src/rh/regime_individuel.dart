/// M10, PLANNING INDIVIDUEL (Direction, 16/11/2026, `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md` §8) : « pour chaque agent, un régime individuel qui déroge champ par
/// champ au régime de sa catégorie ou le remplace ; la fiche du personnel porte un planning hebdomadaire ou mensuel ; les valeurs d'attente sont marquées champ par
/// champ ».
///
/// Ce fichier COMPLÈTE `planning_rh.dart` (lot L4, port de la maquette) sans en changer les vecteurs : la résolution du régime effectif reste UNE fonction
/// (`regimeRhALaDate`), étendue aux horaires, à la durée, aux jours et au remplacement. Ici : la pose d'une version (refus nommés), les horaires d'une vacation sous le
/// régime effectif, le calendrier de l'agent (semaine ou mois) et l'HONORAIRE DE RÉGIME du mois, lu par l'écran des primes et par le moteur de paie (RG-11).
///
/// Fonctions PURES : elles reçoivent les fiches lues au magasin et rendent une lecture ou un refus nommé ; elles n'écrivent rien. Aucune valeur n'est inventée : un
/// champ absent ne vaut rien (horaires et durée du type de vacation, tous les jours), et une valeur saisie sans document d'origine est marquée « à valider ».
library;

import 'double_paiement_prime.dart';
import 'planning_rh.dart';
import 'rhb_regles.dart';
import '../droits/gestes_reserves.dart';

/// Les modes d'une version de régime individuel (identifiants STOCKÉS sur la version : `mode`).
const String modeDerogationRh = 'derogation', modeRemplacementRh = 'remplacement', modeRetourRh = 'retour';

const Map<String, String> libellesModesRegimeRh = {
  modeDerogationRh: 'Dérogation champ par champ',
  modeRemplacementRh: 'Remplacement du régime de la catégorie',
  modeRetourRh: 'Retour au régime de la catégorie',
};

bool _renseigne(Object? x) => x != null && x != '' && !(x is List && x.isEmpty);
final RegExp _heure = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

/// Les horaires d'une vacation de type [type] sous le régime [r] : ceux du régime s'il en écrit (provenance `regime`), sinon ceux du type de vacation
/// (provenance `referentiel`, transcrits des plannings réels). Un type sans horaire (repos, congé…) rend une durée nulle.
({String? debut, String? fin, num duree, String provenance}) horairesVacationRh(RegimeRhResolu? r, Object? type) {
  final t = rhbTypePlanning(type);
  if (t == null || t.duree <= 0) return (debut: null, fin: null, duree: 0, provenance: 'referentiel');
  final propre = r != null && (r.heureDebut != null || r.heureFin != null || r.dureeHeures != null);
  return (
    debut: r?.heureDebut ?? t.debut,
    fin: r?.heureFin ?? t.fin,
    duree: r?.dureeHeures ?? t.duree,
    provenance: propre ? 'regime' : 'referentiel',
  );
}

/// Le jour [dateIso] est-il travaillé sous le régime [r] ? Sans jours écrits : oui (aucune restriction).
bool jourTravailleRh(RegimeRhResolu r, String dateIso) {
  final j = r.jours;
  if (j == null || j.isEmpty) return true;
  final d = DateTime.tryParse(dateIso.length >= 10 ? dateIso.substring(0, 10) : dateIso);
  if (d == null) return true;
  return j.contains(joursSemaineRh[d.weekday - 1].id);
}

/// La POSE d'une version de régime individuel : le refus nommé, ou la fiche normalisée à écrire (`champs`, `mode`, `retourCategorie`, `baseRemplacement`, `aValider`,
/// `sourceDocument`). Les contrôles de la maquette (droit, agent, date d'effet, motif, versions antérieures, champs classiques) sont ceux de [validerDerogationRh],
/// jamais recopiés ; ce qui s'y ajoute : horaires, durée, jours, remplacement et valeurs d'attente.
///
/// VALEURS D'ATTENTE : [aValider] nomme les champs dont la valeur ne vient d'aucun document. Absent (`null`) et SANS [sourceDocument], tous les champs posés le sont :
/// une valeur sans document d'origine est, par définition, une valeur d'attente. Un champ « à valider » qui n'est pas posé par la version est refusé.
({RefusRh? refus, Map<String, Object?>? fiche}) validerRegimeIndividuelRh({
  required String role,
  required bool agentExiste,
  required String? dateEffet,
  required String? motif,
  required String mode,
  required Map<String, Object?> champs,
  required List<FichePlanning> versions,
  required List<FichePlanning> regimesActifs,
  required String aujourdhui,
  String? baseRemplacement,
  String? sourceDocument,
  List<String>? aValider,
  DroitsGestes? gestes,
}) {
  ({RefusRh? refus, Map<String, Object?>? fiche}) non(RefusRh r) => (refus: r, fiche: null);
  if (![modeDerogationRh, modeRemplacementRh, modeRetourRh].contains(mode)) {
    return non(RefusRh('MODE_INCONNU', 'Le mode « $mode » n’existe pas.', 'Choisir une dérogation champ par champ, un remplacement ou le retour à la catégorie.'));
  }
  final retour = mode == modeRetourRh;
  final classiques = {for (final c in champsDerogeablesRh) c: champs[c]};
  final extras = {for (final c in champsHorairesRh) if (_renseigne(champs[c])) c: champs[c]};
  final libelle = '${champs['libelle'] ?? ''}'.trim();
  final base = baseRemplacement == null || baseRemplacement.trim().isEmpty ? null : baseRemplacement.trim();
  // Les contrôles communs (et les champs classiques) : ceux de la maquette.
  var r = validerDerogationRh(
      role: role, agentExiste: agentExiste, dateEffet: dateEffet, motif: motif, retourCategorie: retour, champs: classiques, versions: versions, aujourdhui: aujourdhui, gestes: gestes);
  if (r.refus?.code == 'AUCUNE_DEROGATION' && (extras.isNotEmpty || mode == modeRemplacementRh)) {
    // Rien de classique n'est dérogé, mais des horaires, des jours ou un remplacement le sont : les contrôles de date restent ceux de la maquette.
    r = validerDerogationRh(
        role: role, agentExiste: agentExiste, dateEffet: dateEffet, motif: motif, retourCategorie: true, champs: const {}, versions: versions, aujourdhui: aujourdhui, gestes: gestes);
    if (r.refus == null) r = (refus: null, champs: <String, Object?>{});
  }
  if (r.refus != null) {
    if (r.refus!.code == 'AUCUNE_DEROGATION') {
      return non(const RefusRh('AUCUNE_DEROGATION', 'Aucun champ n’est dérogé : le régime de l’agent suit déjà celui de sa catégorie.',
          'Renseigner au moins un champ (vacations, repos, cycle, honoraire, horaires, durée, jours), ou choisir « revenir au régime de la catégorie ».'));
    }
    return non(r.refus!);
  }
  final retenus = <String, Object?>{...?r.champs};
  if (!retour) {
    for (final c in ['heureDebut', 'heureFin']) {
      final h = extras[c];
      if (h == null) continue;
      if (!_heure.hasMatch('$h')) {
        return non(RefusRh('CHAMP_INVALIDE', 'L’${c == 'heureDebut' ? 'heure de début' : 'heure de fin'} « $h » n’est pas une heure (HH:MM).', 'Écrire l’heure sous la forme 08:00.',
            {'champ': c}));
      }
      retenus[c] = '$h';
    }
    final du = extras['dureeHeures'];
    if (du != null) {
      final d = du is num ? du : num.tryParse('$du'.replaceAll(',', '.'));
      if (d == null || d <= 0 || d > 24) {
        return non(const RefusRh('CHAMP_INVALIDE', 'La durée d’une vacation est un nombre d’heures, plus de 0 et au plus 24.', 'Corriger la durée.', {'champ': 'dureeHeures'}));
      }
      retenus['dureeHeures'] = d;
    }
    final jr = extras['jours'];
    if (jr != null) {
      final ids = [for (final j in joursSemaineRh) j.id];
      if (jr is! List || jr.any((x) => !ids.contains('$x'))) {
        return non(const RefusRh('CHAMP_INVALIDE', 'Les jours travaillés ne sont pas tous des jours de la semaine.', 'Choisir parmi lundi … dimanche.', {'champ': 'jours'}));
      }
      retenus['jours'] = [for (final j in ids) if (jr.map((x) => '$x').contains(j)) j];
    }
    if (mode == modeRemplacementRh) {
      if (base != null && regimeParLibelleRh(regimesActifs, base) == null) {
        return non(RefusRh('REGIME_INTROUVABLE', 'Le régime « $base » n’existe pas (ou est archivé).', 'Choisir un régime de la liste, ou composer le remplacement champ par champ.'));
      }
      final adopte = base == null ? null : regimeParLibelleRh(regimesActifs, base);
      final vac = retenus['vacations'] ?? adopte?['vacations'];
      if (!_renseigne(vac)) {
        return non(const RefusRh('REMPLACEMENT_INCOMPLET',
            'Un régime de remplacement remplace TOUT le régime de la catégorie : il porte au moins ses vacations (rien n’est hérité de la catégorie).',
            'Choisir le régime adopté, ou renseigner les vacations du régime individuel.'));
      }
      if (libelle.isNotEmpty) retenus['libelle'] = libelle;
    }
  }
  final doc = (sourceDocument ?? '').trim();
  final poses = [for (final c in champsRegimeIndividuelRh) if (retenus.containsKey(c)) c];
  List<String> attente;
  if (retour) {
    attente = const [];
  } else if (aValider == null) {
    attente = doc.isEmpty ? poses : const [];
  } else {
    final hors = [for (final c in aValider) if (!poses.contains(c)) c];
    if (hors.isNotEmpty) {
      return non(RefusRh('A_VALIDER_HORS_VERSION', 'Seul un champ posé par la version peut être marqué « à valider » : ${hors.map((c) => libellesChampsRegimeRh[c] ?? c).join(', ')}.',
          'Décocher ces champs, ou les renseigner.'));
    }
    attente = [for (final c in poses) if (aValider.contains(c)) c];
  }
  return (
    refus: null,
    fiche: {
      'champs': retenus,
      'mode': retour ? modeRetourRh : mode,
      'retourCategorie': retour,
      'baseRemplacement': mode == modeRemplacementRh ? base : null,
      'aValider': attente,
      'sourceDocument': doc.isEmpty ? null : doc,
    }
  );
}

/// Une ligne du calendrier de l'agent : le jour, sa vacation (s'il y en a une), le congé qui le couvre, le régime en vigueur.
class JourPlanningRh {
  const JourPlanningRh({
    required this.date,
    required this.regime,
    this.vacation,
    this.conge,
    this.horaires,
  });
  final String date;
  final RegimeRhResolu regime;
  final FichePlanning? vacation, conge;
  final ({String? debut, String? fin, num duree, String provenance})? horaires;

  /// Le jour est-il travaillé sous le régime en vigueur (jours écrits) ?
  bool get travailleParRegime => jourTravailleRh(regime, date);

  /// La vacation est-elle validée (une vacation d'avant le circuit, sans état, l'est) ?
  bool get validee => vacation != null && (vacation!['validationEtat'] == null || vacation!['validationEtat'] == '' || vacation!['validationEtat'] == 'validee');
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Les bornes d'une vue du planning de l'agent autour de [date] : `semaine` (du lundi au dimanche) ou `mois` (du premier au dernier jour).
({String du, String au}) bornesVuePlanningRh(String vue, DateTime date) {
  final j = DateTime.utc(date.year, date.month, date.day);
  if (vue == 'semaine') {
    final lundi = j.subtract(Duration(days: j.weekday - 1));
    return (du: _iso(lundi), au: _iso(lundi.add(const Duration(days: 6))));
  }
  return (du: _iso(DateTime.utc(j.year, j.month, 1)), au: _iso(DateTime.utc(j.year, j.month + 1, 0)));
}

/// Le CALENDRIER d'un agent du [du] au [au] (inclus) : chaque jour, sa vacation, le congé VALIDÉ qui le couvre et le régime en vigueur À CE JOUR. [vacations] et
/// [conges] sont les fiches actives de l'agent ; [regimeDe] est la résolution du régime effectif (une seule fonction, `regimeRhALaDate`).
List<JourPlanningRh> calendrierAgentRh({
  required List<FichePlanning> vacations,
  required List<FichePlanning> conges,
  required RegimeRhResolu Function(String date) regimeDe,
  required String du,
  required String au,
}) {
  final out = <JourPlanningRh>[];
  var d = DateTime.parse(du);
  final fin = DateTime.parse(au);
  while (!d.isAfter(fin)) {
    final iso = _iso(d);
    final r = regimeDe(iso);
    FichePlanning? v;
    for (final x in vacations) {
      if ('${x['date']}'.startsWith(iso)) v = x;
    }
    FichePlanning? cg;
    for (final x in conges) {
      if (!compteRh('conges', x)) continue;
      final a = '${x['dateDebut'] ?? ''}', b = '${x['dateFin'] ?? x['dateDebut'] ?? ''}';
      if (a.length >= 10 && b.length >= 10 && a.substring(0, 10).compareTo(iso) <= 0 && b.substring(0, 10).compareTo(iso) >= 0) cg = x;
    }
    out.add(JourPlanningRh(date: iso, regime: r, vacation: v, conge: cg, horaires: v == null ? null : horairesVacationRh(r, v['type'])));
    d = DateTime.utc(d.year, d.month, d.day + 1);
  }
  return out;
}

/// L'HONORAIRE DE RÉGIME d'un agent pour un mois (RG-11 : depuis le planning VALIDÉ et le régime EN VIGUEUR À LA DATE de chaque vacation, dérogation ou remplacement
/// compris). Une vacation n'ouvre l'honoraire que si son type est une vacation du régime qui le porte. Périodicité « par occurrence » : l'honoraire de chaque
/// vacation ; « mensuelle » (défaut) : une fois dans le mois, au montant du régime en vigueur à la DERNIÈRE vacation qui l'ouvre.
class HonoraireRegimeRh {
  const HonoraireRegimeRh(
      {this.montant = 0, this.occurrences = 0, this.mensuel = 0, this.parOccurrence = 0, this.aValider = false, this.lignes = const [], this.exclus = const []});
  final num montant, mensuel, parOccurrence;
  final int occurrences;

  /// Un montant lu sur un champ « à valider » (valeur d'attente) : l'écran le dit.
  final bool aValider;

  /// Le détail : date, type, montant retenu, périodicité, version de régime.
  final List<Map<String, Object?>> lignes;

  /// Les lignes ÉCARTÉES parce qu'elles répétaient une prime de la note NS 132 déjà versée (`DOUBLE_PAIEMENT_PRIME`, 17/11/2026) : la ligne et la répétition qui la nomme.
  final List<Map<String, Object?>> exclus;
}

HonoraireRegimeRh honoraireRegimeMoisRh({
  required List<FichePlanning> vacations,
  required Object? employeId,
  required int annee,
  required int mois,
  required RegimeRhResolu Function(String date) regimeDe,
  DoublePaiementPrime? Function(Map<String, Object?> ligne)? doublon,
}) {
  final prefixe = '${annee.toString().padLeft(4, '0')}-${mois.toString().padLeft(2, '0')}';
  final miennes = [
    for (final v in vacations)
      if (v['employeId'] == employeId &&
          '${v['date']}'.startsWith(prefixe) &&
          v['statut'] != 'archive' &&
          (v['validationEtat'] == null || v['validationEtat'] == '' || v['validationEtat'] == 'validee') &&
          (rhbTypePlanning(v['type'])?.duree ?? 0) > 0)
        v
  ]..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
  num occ = 0;
  var n = 0;
  var attente = false;
  Map<String, Object?>? dernierMensuel;
  final lignes = <Map<String, Object?>>[];
  final exclus = <Map<String, Object?>>[];
  for (final v in miennes) {
    final d = '${v['date']}'.substring(0, 10);
    final r = regimeDe(d);
    final h = r.honoraire;
    if (h == null || h <= 0 || !r.vacations.contains(v['type'])) continue;
    final per = r.honorairePeriodicite == 'occurrence' ? 'occurrence' : 'mensuelle';
    final l = <String, Object?>{'date': d, 'type': v['type'], 'vacationId': v['id'], 'montant': h, 'periodicite': per, 'versionId': r.versionId, 'regime': r.libelle, 'provenance': r.provenances['honoraire'], 'aValider': r.aValider.contains('honoraire')};
    // [doublon] : un honoraire INDIVIDUEL qui répète une prime NS 132 déjà versée ne se compte pas ; la ligne est gardée à part, avec la répétition qui la nomme.
    final dbl = doublon?.call(l);
    if (dbl != null) {
      exclus.add({...l, 'doublePaiement': dbl.toJson(), 'phrase': dbl.phrase()});
      continue;
    }
    if (per == 'occurrence') {
      occ += h;
      n++;
      lignes.add(l);
      if (r.aValider.contains('honoraire')) attente = true;
    } else {
      dernierMensuel = l;
    }
  }
  num men = 0;
  if (dernierMensuel != null) {
    men = dernierMensuel['montant'] as num;
    lignes.add(dernierMensuel);
    if (dernierMensuel['aValider'] == true) attente = true;
  }
  return HonoraireRegimeRh(montant: occ + men, occurrences: n, mensuel: men, parOccurrence: occ, aValider: attente, lignes: lignes, exclus: exclus);
}
