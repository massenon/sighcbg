/// M10, lots L4 à L6 (10/11/2026) : le régime INDIVIDUEL qui déroge champ par champ, le contrôle de repos unique, le circuit de validation des présences,
/// absences, congés et ordres de mission, et les propositions de planning de l'agent.
///
/// Port de `SIGH.planningRh` (`prototype_html/assets/js/parcours.js`, fin du fichier) ; vecteurs `test/vecteurs/planning_rh.json`, engendrés par
/// `prototype_html/build/vecteurs-planning-rh.js` (le moteur de la maquette, piloté dans Chrome). Les fonctions sont PURES : elles reçoivent les fiches
/// lues au magasin, la date du jour et le rôle, et rendent un résultat ou un refus nommé (code, motif, geste) ; elles n'écrivent rien.
///
/// Décisions de la Direction du 09/11/2026 : le régime de la catégorie est la règle, la dérogation individuelle ne change que les champs renseignés
/// (versions datées immuables) ; le circuit de validation est un réglage (`planning.circuitPresences` du registre des paramètres, défaut `surveillant`) ;
/// l'agent propose, le surveillant valide (`planning.agentModifieDirectement`, défaut non). Aucune durée, aucun honoraire ni aucune règle de repos n'est
/// inventé : le repos et les honoraires viennent des régimes de la maquette (`rhbReglesPlanning`, NS 132).
library;

import 'rhb_regles.dart';
import '../droits/gestes_reserves.dart';

/// Le rôle détient-il le geste réservé [geste] dans la matrice en force ([g]) ? Absente, l'origine du référentiel (ce que valaient les listes d'avant).
bool _peutRh(DroitsGestes? g, String role, String geste) => (g ?? gestesOrigine()).peut(role, geste);

typedef FichePlanning = Map<String, Object?>;

/// Les champs d'un régime qu'une dérogation individuelle peut changer.
const List<String> champsDerogeablesRh = ['vacations', 'repos', 'cycle', 'honoraire', 'honorairePeriodicite'];

/// PLANNING INDIVIDUEL (Direction, 16/11/2026, §8) : les champs que le régime individuel ajoute à ceux de la maquette — les HORAIRES (début, fin), la DURÉE d'une
/// vacation et les JOURS de la semaine travaillés. Absents du régime de la catégorie, ils ne valent rien : les horaires et la durée sont alors ceux du type de
/// vacation (`rhbTypesPlanning`, transcrits des plannings réels), et l'absence de jours veut dire « tous les jours » (aucune restriction écrite).
const List<String> champsHorairesRh = ['heureDebut', 'heureFin', 'dureeHeures', 'jours'];

/// Tous les champs qu'un régime individuel (dérogation ou remplacement) peut porter, dans l'ordre d'affichage.
const List<String> champsRegimeIndividuelRh = [...champsDerogeablesRh, ...champsHorairesRh];

/// Les libellés des champs d'un régime (écran, historique, refus).
const Map<String, String> libellesChampsRegimeRh = {
  'vacations': 'Vacations',
  'repos': 'Repos',
  'cycle': 'Cycle',
  'honoraire': 'Honoraire',
  'honorairePeriodicite': 'Périodicité de l’honoraire',
  'heureDebut': 'Heure de début',
  'heureFin': 'Heure de fin',
  'dureeHeures': 'Durée (heures)',
  'jours': 'Jours travaillés',
};

/// Les jours de la semaine (identifiants STOCKÉS), du lundi au dimanche : l'indice + 1 est le `weekday` de Dart.
const List<({String id, String libelle})> joursSemaineRh = [
  (id: 'lun', libelle: 'Lundi'),
  (id: 'mar', libelle: 'Mardi'),
  (id: 'mer', libelle: 'Mercredi'),
  (id: 'jeu', libelle: 'Jeudi'),
  (id: 'ven', libelle: 'Vendredi'),
  (id: 'sam', libelle: 'Samedi'),
  (id: 'dim', libelle: 'Dimanche'),
];

/// Les trois provenances d'un champ du régime en vigueur : la CATÉGORIE (régime administré, avec son document source), le REMPLACEMENT (un autre régime adopté
/// en bloc) et l'INDIVIDUEL (la valeur portée par la version de l'agent). Un champ sans provenance n'a pas de valeur.
const String provenanceCategorieRh = 'categorie', provenanceRemplacementRh = 'remplacement', provenanceIndividuelleRh = 'individuel';

const List<String> vacationsGardeRh = ['garde', 'garde_hospi'];

/// Un refus nommé : code, motif, geste (et le détail utile à l'écran).
class RefusRh {
  const RefusRh(this.code, this.motif, this.geste, [this.extra = const {}]);
  final String code, motif, geste;
  final Map<String, Object?> extra;
  Map<String, Object?> toJson() => {'ok': false, 'code': code, 'motif': motif, 'geste': geste, ...extra};
}

String _dateFr(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

String _ajouteJours(String iso, int n) {
  final p = iso.split('-').map(int.parse).toList();
  final d = DateTime.utc(p[0], p[1], p[2]).add(Duration(days: n));
  String z(int x) => x.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${z(d.month)}-${z(d.day)}';
}

bool _renseigne(Object? x) => x != null && x != '' && !(x is List && x.isEmpty);

List<String> _liste(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];

/// Le régime en vigueur pour un agent à une date : la catégorie, puis les champs dérogés de la dernière version à date d'effet atteinte — ou, pour une version
/// de REMPLACEMENT, le régime qu'elle adopte en bloc, complété de ses propres champs.
///
/// `toJson` est la forme de la MAQUETTE (vecteurs `planning_rh.json`) : elle n'est pas étendue. Ce que le planning individuel ajoute (horaires, durée, jours,
/// mode, provenance et valeurs d'attente champ par champ) se lit dans les propriétés et dans [toJsonComplet].
class RegimeRhResolu {
  RegimeRhResolu({
    required this.date,
    this.categorie,
    this.libelle,
    this.fonctions = const [],
    this.vacations = const [],
    this.repos,
    this.cycle,
    this.honoraire,
    this.honorairePeriodicite,
    this.source,
    this.mention,
    this.individuel = false,
    this.derogations = const [],
    this.versionId,
    this.dateEffet,
    this.heureDebut,
    this.heureFin,
    this.dureeHeures,
    this.jours,
    this.mode = 'categorie',
    this.baseRemplacement,
    this.motif,
    this.sourceDocument,
    List<String>? aValider,
    Map<String, String>? provenances,
  })  : aValider = aValider ?? [],
        provenances = provenances ?? {};
  final String date;
  String? categorie, libelle, repos, honorairePeriodicite, source, mention, versionId, dateEffet;
  List<String> fonctions, vacations, derogations;
  num? cycle, honoraire;
  bool individuel;

  /// Les horaires (« HH:MM ») et la durée PROPRES au régime ; `null` : ceux du type de vacation (voir [horairesVacationRh]).
  String? heureDebut, heureFin;
  num? dureeHeures;

  /// Les jours de la semaine travaillés (identifiants de [joursSemaineRh]) ; `null` : tous les jours, aucune restriction écrite.
  List<String>? jours;

  /// `categorie` (aucune version, ou retour à la catégorie), `derogation` (champ par champ) ou `remplacement` (le régime est remplacé entièrement).
  String mode;

  /// Le libellé du régime ADOPTÉ par un remplacement (`null` : un remplacement composé champ par champ, sans régime de base).
  String? baseRemplacement;

  /// Le motif et le document d'origine de la version en vigueur (l'arrêté, l'avenant, la note…) ; `null` sans version.
  String? motif, sourceDocument;

  /// Les champs dont la valeur est une VALEUR D'ATTENTE (« à valider ») : elle ne vient d'aucun document.
  List<String> aValider;

  /// D'où vient chaque champ renseigné : [provenanceCategorieRh], [provenanceRemplacementRh] ou [provenanceIndividuelleRh].
  Map<String, String> provenances;

  /// La valeur d'un champ du régime, par son nom (`champsRegimeIndividuelRh`).
  Object? valeur(String champ) => switch (champ) {
        'vacations' => vacations,
        'repos' => repos,
        'cycle' => cycle,
        'honoraire' => honoraire,
        'honorairePeriodicite' => honorairePeriodicite,
        'heureDebut' => heureDebut,
        'heureFin' => heureFin,
        'dureeHeures' => dureeHeures,
        'jours' => jours,
        _ => null,
      };

  Map<String, Object?> toJson() => {
        'date': date, 'categorie': categorie, 'libelle': libelle, 'fonctions': fonctions, 'vacations': vacations, 'repos': repos, 'cycle': cycle,
        'honoraire': honoraire, 'honorairePeriodicite': honorairePeriodicite, 'source': source, 'mention': mention, 'individuel': individuel,
        'derogations': derogations, 'versionId': versionId, 'dateEffet': dateEffet,
      };

  Map<String, Object?> toJsonComplet() => {
        ...toJson(),
        'heureDebut': heureDebut, 'heureFin': heureFin, 'dureeHeures': dureeHeures, 'jours': jours, 'mode': mode, 'baseRemplacement': baseRemplacement,
        'motif': motif, 'sourceDocument': sourceDocument, 'aValider': aValider, 'provenances': provenances,
      };
}

/// Le régime de la CATÉGORIE : le premier régime ACTIF du magasin qui couvre la fonction, à défaut la règle relevée sur les plannings.
Map<String, Object?>? regimeCategorieRh(List<FichePlanning> regimesActifs, String? fonction) {
  for (final r in regimesActifs) {
    if (_liste(r['fonctions']).contains(fonction)) return r;
  }
  final d = rhbRegleDe(fonction);
  if (d == null) return null;
  return {
    'libelle': d.libelle, 'fonctions': d.fonctions, 'vacations': d.vacations, 'repos': d.repos, 'cycle': d.cycle, 'honoraire': d.honoraire,
    'honorairePeriodicite': d.honorairePeriodicite, 'source': d.source, 'mention': d.mention,
  };
}

/// Le régime nommé [libelle] (base d'un REMPLACEMENT) : un régime ACTIF du magasin, à défaut une règle relevée sur les plannings. `null` s'il n'existe pas.
Map<String, Object?>? regimeParLibelleRh(List<FichePlanning> regimesActifs, String? libelle) {
  if (libelle == null || libelle.isEmpty) return null;
  for (final r in regimesActifs) {
    if (r['libelle'] == libelle) return r;
  }
  for (final d in rhbReglesPlanning) {
    if (d.libelle == libelle) {
      return {
        'libelle': d.libelle, 'fonctions': d.fonctions, 'vacations': d.vacations, 'repos': d.repos, 'cycle': d.cycle, 'honoraire': d.honoraire,
        'honorairePeriodicite': d.honorairePeriodicite, 'source': d.source, 'mention': d.mention,
      };
    }
  }
  return null;
}

/// Les libellés des régimes qu'un remplacement peut adopter : ceux du magasin (actifs), puis les règles relevées qui n'y figurent pas.
List<String> libellesRegimesRh(List<FichePlanning> regimesActifs) {
  final out = <String>[for (final r in regimesActifs) if ('${r['libelle'] ?? ''}'.isNotEmpty) '${r['libelle']}'];
  for (final d in rhbReglesPlanning) {
    if (!out.contains(d.libelle)) out.add(d.libelle);
  }
  return out;
}

/// Pose sur [out] les champs d'un régime [r] (catégorie ou base d'un remplacement), avec leur provenance et ses valeurs d'attente (`aValider` de la fiche).
void _appliquerRegime(RegimeRhResolu out, Map<String, Object?> r, String provenance) {
  out.vacations = _liste(r['vacations']);
  out.repos = r['repos'] == null || r['repos'] == '' ? null : '${r['repos']}';
  out.cycle = r['cycle'] is num ? r['cycle'] as num : null;
  out.honoraire = r['honoraire'] == null || r['honoraire'] == 0 || r['honoraire'] is! num ? null : r['honoraire'] as num;
  out.honorairePeriodicite = r['honorairePeriodicite'] == null || r['honorairePeriodicite'] == '' ? null : '${r['honorairePeriodicite']}';
  out.heureDebut = _renseigne(r['heureDebut']) ? '${r['heureDebut']}' : null;
  out.heureFin = _renseigne(r['heureFin']) ? '${r['heureFin']}' : null;
  out.dureeHeures = r['dureeHeures'] is num ? r['dureeHeures'] as num : null;
  out.jours = _renseigne(r['jours']) ? _liste(r['jours']) : null;
  out.source = r['source'] as String?;
  out.mention = r['mention'] as String?;
  out.provenances = {for (final c in champsRegimeIndividuelRh) if (_renseigne(out.valeur(c))) c: provenance};
  final av = _liste(r['aValider']);
  out.aValider = [for (final c in champsRegimeIndividuelRh) if (av.contains(c) && out.provenances.containsKey(c)) c];
}

/// `regimeALaDate` : [versions] sont les fiches ACTIVES de l'agent (collection `regimesIndividuels`). C'est LA résolution du régime effectif d'un agent à une date :
/// le planning (types autorisés, contrôle de repos), les primes (honoraire du régime, RG-11), la paie et « Mon espace » la lisent, aucun ne la refait.
///
/// Une version porte `mode` : absent ou `derogation`, seuls les champs renseignés changent (le reste suit la catégorie) ; `remplacement`, le régime de la catégorie
/// est REMPLACÉ entièrement — par le régime `baseRemplacement` s'il est nommé, complété des champs de la version ; aucun champ de la catégorie n'est hérité.
/// `retourCategorie` ramène à la catégorie. Les valeurs d'attente de la version (`aValider`) sont portées champ par champ.
RegimeRhResolu regimeRhALaDate({
  required List<FichePlanning> regimesActifs,
  required List<FichePlanning> versions,
  required String? fonction,
  required String date,
}) {
  final base = regimeCategorieRh(regimesActifs, fonction);
  final out = RegimeRhResolu(
    date: date,
    categorie: base == null ? null : '${base['libelle']}',
    libelle: base == null ? null : '${base['libelle']}',
    fonctions: base == null ? [] : _liste(base['fonctions']),
  );
  if (base != null) _appliquerRegime(out, base, provenanceCategorieRh);
  final triees = [...versions]..sort((a, b) => '${a['dateEffet']}'.compareTo('${b['dateEffet']}'));
  FichePlanning? v;
  for (final x in triees) {
    if ('${x['dateEffet']}'.compareTo(date) <= 0) v = x;
  }
  if (v == null) return out;
  out.versionId = v['id'] as String?;
  out.dateEffet = '${v['dateEffet']}';
  out.motif = _renseigne(v['motif']) ? '${v['motif']}' : null;
  out.sourceDocument = _renseigne(v['sourceDocument']) ? '${v['sourceDocument']}' : null;
  if (v['retourCategorie'] == true) return out;
  final champs = (v['champs'] as Map?)?.cast<String, Object?>() ?? const {};
  final remplacement = v['mode'] == 'remplacement';
  if (remplacement) {
    final adopte = regimeParLibelleRh(regimesActifs, v['baseRemplacement'] as String?);
    _appliquerRegime(out, adopte ?? const {}, provenanceRemplacementRh);
    if (adopte == null) {
      out.source = null;
      out.mention = null;
    }
    out.baseRemplacement = adopte == null ? null : '${adopte['libelle']}';
    out.libelle = _renseigne(champs['libelle']) ? '${champs['libelle']}' : (adopte == null ? 'Régime individuel' : '${adopte['libelle']}');
    out.mode = 'remplacement';
  }
  final derog = <String>[];
  for (final c in champsRegimeIndividuelRh) {
    final x = champs[c];
    if (!_renseigne(x)) continue;
    switch (c) {
      case 'vacations':
        out.vacations = _liste(x);
      case 'repos':
        out.repos = x == 'aucun' ? null : '$x';
      case 'cycle':
        out.cycle = x as num;
      case 'honoraire':
        out.honoraire = x as num;
      case 'honorairePeriodicite':
        out.honorairePeriodicite = '$x';
      case 'heureDebut':
        out.heureDebut = '$x';
      case 'heureFin':
        out.heureFin = '$x';
      case 'dureeHeures':
        out.dureeHeures = x as num;
      case 'jours':
        out.jours = _liste(x);
    }
    derog.add(c);
    if (_renseigne(out.valeur(c)) || c == 'repos') {
      out.provenances[c] = provenanceIndividuelleRh;
    }
    out.aValider.remove(c);
  }
  if (out.repos == null) out.provenances.remove('repos');
  final av = _liste(v['aValider']);
  for (final c in derog) {
    if (av.contains(c) && !out.aValider.contains(c)) out.aValider.add(c);
  }
  out.aValider = [for (final c in champsRegimeIndividuelRh) if (out.aValider.contains(c)) c];
  out.derogations = derog;
  out.individuel = remplacement || derog.isNotEmpty;
  if (out.individuel && !remplacement) out.mode = 'derogation';
  return out;
}

/// Les types de vacation qu'un agent peut recevoir : ceux de son régime, le repos, et congé, absence, remplacement.
List<String> typesAutorisesRh(RegimeRhResolu r) {
  if (r.categorie == null && !r.individuel) return [for (final t in rhbTypesPlanning) t.id];
  return [...r.vacations, ...[r.repos, 'conge', 'absence', 'remplacement'].whereType<String>()];
}

/// La pose d'une dérogation : le refus nommé, ou la fiche normalisée à écrire (champs retenus). [versions] : les versions actives de l'agent.
({RefusRh? refus, Map<String, Object?>? champs}) validerDerogationRh({
  required String role,
  required bool agentExiste,
  required String? dateEffet,
  required String? motif,
  required bool retourCategorie,
  required Map<String, Object?> champs,
  required List<FichePlanning> versions,
  required String aujourdhui,
  DroitsGestes? gestes,
}) {
  if (!_peutRh(gestes, role, gesteRhRegler)) {
    return (refus: const RefusRh('DEROGATION_RESERVEE', 'Le régime individuel se règle par la Directrice Administrative ou l’administrateur.', 'Demander à la Directrice Administrative de poser la dérogation.'), champs: null);
  }
  if (!agentExiste) {
    return (refus: const RefusRh('AGENT_INTROUVABLE', 'L’agent désigné n’existe pas au personnel.', 'Choisir un agent du personnel.'), champs: null);
  }
  final d = dateEffet ?? '';
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) {
    return (refus: const RefusRh('DATE_INVALIDE', 'La date d’effet est absente ou illisible.', 'Choisir la date à partir de laquelle la dérogation s’applique.'), champs: null);
  }
  if ((motif ?? '').trim().isEmpty) {
    return (refus: const RefusRh('MOTIF_OBLIGATOIRE', 'Le motif de la dérogation est obligatoire.', 'Dire pourquoi le régime de cet agent diffère de celui de sa catégorie.'), champs: null);
  }
  if (d.compareTo(aujourdhui) < 0) {
    return (
      refus: RefusRh('DATE_PASSEE', 'La date d’effet (${_dateFr(d)}) est antérieure à aujourd’hui : une dérogation ne s’applique jamais rétroactivement.',
          'Choisir aujourd’hui ou une date à venir. Les vacations passées gardent le régime sous lequel elles ont été posées.'),
      champs: null
    );
  }
  final retenus = <String, Object?>{};
  if (!retourCategorie) {
    final admises = [for (final t in rhbTypesPlanning) if (t.duree > 0) t.id];
    final vac = champs['vacations'];
    if (_renseigne(vac)) {
      if (vac is! List || vac.any((x) => !admises.contains(x))) {
        return (refus: const RefusRh('CHAMP_INVALIDE', 'Les vacations proposées ne sont pas toutes des vacations travaillées du référentiel.', 'Choisir parmi les types de vacation du référentiel.', {'champ': 'vacations'}), champs: null);
      }
      retenus['vacations'] = [for (final x in vac) '$x'];
    }
    final repos = champs['repos'];
    if (_renseigne(repos)) {
      if (!['repos24', 'repos48', 'aucun'].contains(repos)) {
        return (refus: RefusRh('CHAMP_INVALIDE', 'Le repos « $repos » n’existe pas.', 'Choisir repos de 24 h, repos de 48 h ou aucun repos codifié.', const {'champ': 'repos'}), champs: null);
      }
      retenus['repos'] = repos;
    }
    final cycle = champs['cycle'];
    if (_renseigne(cycle)) {
      final cy = cycle is num ? cycle : num.tryParse('$cycle');
      if (cy == null || !(cy >= 1) || cy.floor() != cy) {
        return (refus: const RefusRh('CHAMP_INVALIDE', 'Le cycle doit être un nombre entier de jours, au moins 1.', 'Corriger le cycle.', {'champ': 'cycle'}), champs: null);
      }
      retenus['cycle'] = cy;
    }
    final hon = champs['honoraire'];
    if (_renseigne(hon)) {
      final h = hon is num ? hon : num.tryParse('$hon');
      if (h == null || !(h >= 0)) {
        return (refus: const RefusRh('CHAMP_INVALIDE', 'L’honoraire doit être un montant positif ou nul.', 'Corriger l’honoraire.', {'champ': 'honoraire'}), champs: null);
      }
      retenus['honoraire'] = h;
    }
    final per = champs['honorairePeriodicite'];
    if (_renseigne(per)) {
      if (!['mensuelle', 'occurrence'].contains(per)) {
        return (refus: const RefusRh('CHAMP_INVALIDE', 'La périodicité de l’honoraire est mensuelle ou par occurrence.', 'Corriger la périodicité.', {'champ': 'honorairePeriodicite'}), champs: null);
      }
      retenus['honorairePeriodicite'] = per;
    }
    if (retenus.isEmpty) {
      return (refus: const RefusRh('AUCUNE_DEROGATION', 'Aucun champ n’est dérogé : le régime de l’agent suit déjà celui de sa catégorie.', 'Renseigner au moins un champ, ou choisir « revenir au régime de la catégorie ».'), champs: null);
    }
  }
  final triees = [...versions]..sort((a, b) => '${a['dateEffet']}'.compareTo('${b['dateEffet']}'));
  if (triees.any((v) => '${v['dateEffet']}' == d)) {
    return (refus: RefusRh('DATE_EXISTANTE', 'Une version commence déjà le ${_dateFr(d)} pour cet agent : une version ne se réécrit pas.', 'Choisir une date d’effet postérieure.'), champs: null);
  }
  if (triees.isNotEmpty && '${triees.last['dateEffet']}'.compareTo(d) > 0) {
    return (
      refus: RefusRh('VERSION_ANTERIEURE',
          'La version la plus récente de cet agent commence le ${_dateFr('${triees.last['dateEffet']}')} : une version insérée avant elle masquerait l’historique.', 'Choisir une date d’effet postérieure à la dernière version.'),
      champs: null
    );
  }
  return (refus: null, champs: retenus);
}

/// Le contrôle d'incompatibilité : repos qui suit une garde (durée du régime EN VIGUEUR À LA DATE), avant comme après, et double affectation.
/// [planningActif] : les vacations actives de l'agent ; [ignoreId] : celle qu'on remplace. Rend `null` si la saisie est acceptable.
RefusRh? controlerVacationRh({
  required Map<String, Object?>? agent,
  required List<FichePlanning> planningActif,
  required RegimeRhResolu? regime,
  required String? date,
  required String? type,
  String? ignoreId,
}) {
  if (agent == null) return const RefusRh('AGENT_INTROUVABLE', 'L’agent désigné n’existe pas au personnel.', 'Choisir un agent du personnel.');
  final d = (date ?? '').length >= 10 ? date!.substring(0, 10) : '';
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) return const RefusRh('DATE_INVALIDE', 'La date de la vacation est absente ou illisible.', 'Choisir une date.');
  if (rhbTypePlanning(type) == null) return RefusRh('TYPE_INCONNU', 'Le type de vacation « $type » n’existe pas.', 'Choisir un type du référentiel.');
  final nom = '${agent['nomComplet']}';
  final autres = [for (final p in planningActif) if (p['employeId'] == agent['id'] && p['id'] != ignoreId) p];
  for (final p in autres) {
    if (p['date'] == d) {
      return RefusRh('DOUBLE_AFFECTATION', '$nom a déjà une vacation le ${_dateFr(d)} (${rhbTypePlanningLabel(p['type'])}).',
          'Modifier la vacation existante, ou choisir un autre jour.', {'date': d, 'existante': p['id']});
    }
  }
  if (vacationsGardeRh.contains(type)) {
    final jours = regime?.repos == 'repos48' ? 2 : 1;
    for (var k = 1; k <= jours; k++) {
      for (final p in autres) {
        if (p['date'] == _ajouteJours(d, -k) && vacationsGardeRh.contains(p['type'])) {
          return RefusRh('INCOMPATIBILITE_REPOS',
              'Incompatibilité : le repos de ${jours * 24} h qui suit une garde n’est pas respecté (garde déjà programmée le ${_dateFr('${p['date']}')} pour $nom).',
              'Choisir un jour après le repos de ${jours * 24} h, ou retirer l’autre garde.',
              {'date': d, 'autre': p['id'], 'reposHeures': jours * 24, 'individuel': regime?.individuel ?? false});
        }
      }
      for (final p in autres) {
        if (p['date'] == _ajouteJours(d, k) && vacationsGardeRh.contains(p['type'])) {
          return RefusRh('INCOMPATIBILITE_REPOS',
              'Incompatibilité : le repos de ${jours * 24} h qui suivrait cette garde serait entamé par la garde déjà programmée le ${_dateFr('${p['date']}')} pour $nom.',
              'Choisir un autre jour, ou retirer l’autre garde.', {'date': d, 'autre': p['id'], 'reposHeures': jours * 24, 'individuel': regime?.individuel ?? false});
        }
      }
    }
  }
  // PLANNING INDIVIDUEL : un régime qui ÉCRIT ses jours travaillés refuse une vacation travaillée un autre jour (repos, congé, absence et remplacement restent
  // possibles). Sans jours écrits, aucune restriction : rien n'est déduit d'une mention en texte libre.
  final jr = regime?.jours;
  if (jr != null && jr.isNotEmpty && (rhbTypePlanning(type)?.duree ?? 0) > 0) {
    final p = d.split('-').map(int.parse).toList();
    final j = joursSemaineRh[DateTime.utc(p[0], p[1], p[2]).weekday - 1];
    if (!jr.contains(j.id)) {
      return RefusRh('JOUR_HORS_REGIME', 'Le ${_dateFr(d)} est un ${j.libelle.toLowerCase()} : le régime en vigueur de $nom ne compte pas ce jour parmi ses jours travaillés.',
          'Choisir un jour travaillé du régime (${[for (final x in joursSemaineRh) if (jr.contains(x.id)) x.libelle.toLowerCase()].join(', ')}), ou poser un repos, un congé ou une absence.',
          {'date': d, 'jour': j.id, 'individuel': regime?.individuel ?? false});
    }
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------
// L5 : le circuit de validation
// ---------------------------------------------------------------------------------------------------------------------

/// Les circuits (identifiants STOCKÉS) et leurs étapes ; le défaut est `surveillant`.
const Map<String, List<String>> circuitsRh = {
  'surveillant': ['surveillant'],
  'daf': ['daf'],
  'surveillant_puis_daf': ['surveillant', 'daf'],
};
const String circuitRhDefaut = 'surveillant';
const Map<String, String> libellesCircuitsRh = {
  'surveillant': 'Surveillant seul',
  'daf': 'Directrice administrative seule',
  'surveillant_puis_daf': 'Surveillant puis directrice administrative',
};
/// Le geste réservé qui tranche chaque ÉTAPE du circuit (origine : surveillant et administrateur ; DAF et administrateur). Jamais une liste de rôles.
const Map<String, String> gesteEtapeRh = {'surveillant': gesteRhEtapeSurveillant, 'daf': gesteRhEtapeDaf};

/// Les rôles d'ORIGINE de chaque étape (affichage) : DÉRIVÉS du référentiel des gestes, jamais recopiés.
Map<String, List<String>> get rolesEtapeRh => {for (final e in gesteEtapeRh.entries) e.key: gesteReserve(e.value)?.rolesDefaut ?? const []};
const Map<String, String> nomEtapeRh = {'surveillant': 'le surveillant', 'daf': 'la directrice administrative'};

/// Les motifs d'absence codés (PRD, addendum du 07/11/2026).
const List<({String id, String libelle})> motifsAbsenceRh = [
  (id: 'maladie', libelle: 'Maladie'),
  (id: 'mission', libelle: 'Mission'),
  (id: 'conge', libelle: 'Congé'),
];

/// Le circuit en vigueur d'une valeur lue en base : une valeur inconnue ramène au défaut.
String circuitRhEnVigueur(Object? valeur) => valeur is String && circuitsRh.containsKey(valeur) ? valeur : circuitRhDefaut;

/// Les collections qui passent par le circuit, et le champ qui désigne l'agent concerné.
const Map<String, ({String nom, String agent, String entite})> piecesRh = {
  'presences': (nom: 'pointage', agent: 'employeId', entite: 'Presence'),
  'conges': (nom: 'demande de congé', agent: 'employeId', entite: 'Conge'),
  'missions': (nom: 'ordre de mission', agent: 'agentId', entite: 'Ordre de mission'),
};

/// a_valider, valide_surveillant, valide, refuse. Les pièces d'AVANT le circuit sont lues d'après leur état d'origine.
String etatValidationRh(String nom, FichePlanning rec) {
  final e = rec['validationEtat'];
  if (e is String && e.isNotEmpty) return e;
  if (nom == 'conges') {
    final s = rec['statutConge'];
    return s == 'en_attente' ? 'a_valider' : (s == 'refuse' ? 'refuse' : 'valide');
  }
  if (nom == 'missions') {
    final s = rec['statutMission'];
    return (s == 'a_valider' || s == 'projet') ? 'a_valider' : (s == 'refusee' ? 'refuse' : 'valide');
  }
  return 'valide';
}

/// Une pièce COMPTE (primes, évaluation, taux de présence, soldes) seulement validée.
bool compteRh(String nom, FichePlanning rec) => etatValidationRh(nom, rec) == 'valide';

List<FichePlanning> _etapesFaites(FichePlanning rec) => [for (final x in (rec['etapesFaites'] as List? ?? const [])) (x as Map).cast<String, Object?>()];

String? prochaineEtapeRh(FichePlanning rec, String circuit) {
  final faites = [for (final x in _etapesFaites(rec)) if (x['decision'] != 'refuse') '${x['etape']}'];
  for (final e in circuitsRh[circuit]!) {
    if (!faites.contains(e)) return e;
  }
  return null;
}

/// Le rôle peut-il trancher cette pièce ? Rend l'étape, ou le refus nommé.
({RefusRh? refus, String? etape}) peutTrancherRh({
  required String nom,
  required FichePlanning? rec,
  required String role,
  required String circuit,
  required String acteur,
  String? moiId,
  String? moiNom,
  DroitsGestes? gestes,
}) {
  final def = piecesRh[nom];
  if (def == null) {
    return (refus: RefusRh('COLLECTION_INCONNUE', 'La collection « $nom » ne passe pas par le circuit de validation.', 'Choisir pointage, congé ou ordre de mission.'), etape: null);
  }
  if (rec == null || rec['statut'] == 'archive') {
    return (refus: const RefusRh('PIECE_INTROUVABLE', 'La pièce n’existe pas ou est archivée.', 'Choisir une ligne du registre.'), etape: null);
  }
  final etat = etatValidationRh(nom, rec);
  if (etat == 'valide' || etat == 'refuse') {
    return (
      refus: RefusRh('DEJA_TRANCHEE', 'Cette pièce est déjà ${etat == 'valide' ? 'validée' : 'refusée'} : une décision ne se réécrit pas.',
          nom == 'presences' ? 'Pour corriger un pointage validé, le régulariser (motif, date et auteur consignés).' : 'Saisir une nouvelle demande.'),
      etape: null
    );
  }
  final etapes = circuitsRh[circuit]!;
  final etape = prochaineEtapeRh(rec, circuit) ?? etapes.last;
  if (!_peutRh(gestes, role, gesteEtapeRh[etape]!)) {
    return (
      refus: RefusRh('VALIDATION_RESERVEE', 'L’étape en attente est celle de ${nomEtapeRh[etape]} (circuit : ${libellesCircuitsRh[circuit]}).',
          'Demander à ${nomEtapeRh[etape]} de trancher.', {'etape': etape}),
      etape: null
    );
  }
  if (moiId != null && '${rec[def.agent]}' == moiId) {
    return (refus: RefusRh('AUTO_VALIDATION', 'Personne ne valide sa propre pièce : ${def.nom} de $moiNom.', 'Demander à un autre habilité de trancher.'), etape: null);
  }
  if (_etapesFaites(rec).any((x) => x['par'] == acteur && x['decision'] != 'refuse')) {
    return (
      refus: RefusRh('ETAPE_DEJA_SIGNEE', 'Vous avez déjà signé une étape de cette pièce : deux étapes ne se signent pas par la même personne.', 'Demander à ${nomEtapeRh[etape]} de trancher.'),
      etape: null
    );
  }
  return (refus: null, etape: etape);
}

/// TRANCHER une pièce : valider (étape par étape selon le circuit) ou refuser (motif obligatoire). Rend le refus nommé, ou le patch à écrire.
({RefusRh? refus, Map<String, Object?>? patch, String? etat, String? etape, bool complet}) trancherRh({
  required String collection,
  required FichePlanning? rec,
  required String decision,
  required String? motif,
  required String role,
  required String circuit,
  required String acteur,
  required String aujourdhui,
  String? moiId,
  String? moiNom,
  DroitsGestes? gestes,
}) {
  final def = piecesRh[collection];
  ({RefusRh? refus, Map<String, Object?>? patch, String? etat, String? etape, bool complet}) non(RefusRh r) => (refus: r, patch: null, etat: null, etape: null, complet: false);
  if (def == null) return non(RefusRh('COLLECTION_INCONNUE', 'La collection « $collection » ne passe pas par le circuit de validation.', 'Choisir pointage, congé ou ordre de mission.'));
  if (decision != 'valider' && decision != 'refuser') return non(const RefusRh('DECISION_INCONNUE', 'La décision est « valider » ou « refuser ».', 'Choisir une décision.'));
  final p = peutTrancherRh(nom: collection, rec: rec, role: role, circuit: circuit, acteur: acteur, moiId: moiId, moiNom: moiNom, gestes: gestes);
  if (p.refus != null) return non(p.refus!);
  final m = (motif ?? '').trim();
  if (decision == 'refuser' && m.isEmpty) return non(const RefusRh('MOTIF_OBLIGATOIRE', 'Un refus exige son motif : l’agent doit pouvoir le lire.', 'Écrire le motif du refus.'));
  if (collection == 'missions') {
    if (rec!['statutMission'] == 'projet') {
      return non(const RefusRh('PAS_SOUMISE', 'L’ordre est encore en projet : il n’a pas été soumis à validation.', 'Le soumettre d’abord (état « en attente de validation »).'));
    }
    if (decision == 'valider') {
      final avis = rec['avisChefService'] as Map?;
      if (avis == null) return non(const RefusRh('AVIS_REQUIS', 'L’avis du chef de service est requis avant la validation d’un ordre de mission.', 'Consigner l’avis du chef de service, puis valider.'));
      if (avis['avis'] == 'defavorable' && m.isEmpty) {
        return non(const RefusRh('MOTIF_OBLIGATOIRE', 'Valider contre un avis défavorable exige un motif.', 'Écrire pourquoi la mission est validée malgré l’avis.'));
      }
    }
  }
  final trace = <String, Object?>{
    'etape': p.etape, 'par': acteur, 'role': role, 'le': aujourdhui, 'decision': decision == 'valider' ? 'valide' : 'refuse', 'motif': m.isEmpty ? null : m,
  };
  final etapes = [..._etapesFaites(rec!), trace];
  final patch = <String, Object?>{'etapesFaites': etapes};
  String etat;
  if (decision == 'refuser') {
    etat = 'refuse';
    patch['validationEtat'] = 'refuse';
    patch['motifRefus'] = m;
    patch['refuseePar'] = acteur;
    patch['refuseeLe'] = aujourdhui;
    patch['circuitUtilise'] = circuit;
    if (collection == 'conges') patch['statutConge'] = 'refuse';
    if (collection == 'missions') patch['statutMission'] = 'refusee';
  } else {
    final faites = [for (final x in etapes) if (x['decision'] == 'valide') '${x['etape']}'];
    final restantes = [for (final e in circuitsRh[circuit]!) if (!faites.contains(e)) e];
    if (restantes.isNotEmpty) {
      etat = 'valide_surveillant';
      patch['validationEtat'] = 'valide_surveillant';
    } else {
      etat = 'valide';
      patch['validationEtat'] = 'valide';
      patch['validePar'] = acteur;
      patch['valideLe'] = aujourdhui;
      patch['circuitUtilise'] = circuit;
      if (collection == 'conges') patch['statutConge'] = 'valide';
      if (collection == 'missions') {
        patch['statutMission'] = 'validee';
        patch['valideePar'] = acteur;
        patch['valideeLe'] = aujourdhui;
      }
    }
  }
  return (refus: null, patch: patch, etat: etat, etape: p.etape, complet: etat == 'valide');
}

// ---------------------------------------------------------------------------------------------------------------------
// L6 : les propositions de planning
// ---------------------------------------------------------------------------------------------------------------------

/// Les types de proposition (identifiants STOCKÉS).
const List<({String id, String libelle})> typesPropositionRh = [
  (id: 'ajout', libelle: 'Ajouter une vacation'),
  (id: 'modification', libelle: 'Modifier une vacation'),
  (id: 'retrait', libelle: 'Retirer une vacation'),
  (id: 'echange', libelle: 'Échanger une vacation avec un collègue'),
];

/// Le contrôle commun à la proposition et à la validation : le refus nommé, ou `null` si la proposition est applicable.
/// [regimeDe] rend le régime en vigueur d'un agent à une date ; [planningActif] : tout le planning actif ; [personnel] : les agents par identifiant.
RefusRh? controlerPropositionRh({
  required FichePlanning proposition,
  required List<FichePlanning> planningActif,
  required Map<String, FichePlanning> personnel,
  required RegimeRhResolu Function(FichePlanning agent, String date) regimeDe,
}) {
  FichePlanning? vac(Object? id) {
    for (final p in planningActif) {
      if (p['id'] == id) return p;
    }
    return null;
  }

  RefusRh? controle(FichePlanning agent, String date, String? type, String? ignoreId) => controlerVacationRh(
        agent: agent,
        planningActif: planningActif,
        regime: regimeDe(agent, date),
        date: date,
        type: type,
        ignoreId: ignoreId,
      );

  final t = proposition['type'];
  final agent = personnel['${proposition['employeId']}'];
  final cv = proposition['vacationId'] == null ? null : vac(proposition['vacationId']);
  if (t == 'ajout') {
    return agent == null
        ? const RefusRh('AGENT_INTROUVABLE', 'L’agent désigné n’existe pas au personnel.', 'Choisir un agent du personnel.')
        : controle(agent, '${proposition['date']}', proposition['typeVacation'] as String?, null);
  }
  if (cv == null) return const RefusRh('VACATION_INTROUVABLE', 'La vacation visée n’existe plus au planning.', 'Choisir une vacation du planning.');
  if (cv['employeId'] != proposition['employeId']) {
    return const RefusRh('VACATION_D_AUTRUI', 'La vacation visée n’est pas celle de l’agent qui propose.', 'Choisir une de ses propres vacations.');
  }
  if (t == 'retrait') return null;
  if (t == 'modification') {
    return agent == null
        ? const RefusRh('AGENT_INTROUVABLE', 'L’agent désigné n’existe pas au personnel.', 'Choisir un agent du personnel.')
        : controle(agent, '${proposition['date'] ?? cv['date']}', proposition['typeVacation'] as String?, '${cv['id']}');
  }
  if (t == 'echange') {
    final cb = proposition['contrepartieId'] == null ? null : vac(proposition['contrepartieId']);
    if (cb == null) return const RefusRh('ECHANGE_SANS_CONTREPARTIE', 'L’échange désigne une vacation de collègue qui n’existe plus.', 'Choisir la vacation du collègue.');
    if (cb['employeId'] == cv['employeId']) return const RefusRh('ECHANGE_MEME_AGENT', 'Un échange se fait avec un autre agent.', 'Choisir la vacation d’un collègue.');
    final eA = personnel['${cv['employeId']}']!, eB = personnel['${cb['employeId']}']!;
    if (!typesAutorisesRh(regimeDe(eB, '${cv['date']}')).contains(cv['type'])) {
      return RefusRh('ECHANGE_HORS_REGIME', '${rhbTypePlanningLabel(cv['type'])} n’est pas une vacation du régime de ${eB['nomComplet']}.', 'Choisir un collègue de même régime.');
    }
    if (!typesAutorisesRh(regimeDe(eA, '${cb['date']}')).contains(cb['type'])) {
      return RefusRh('ECHANGE_HORS_REGIME', '${rhbTypePlanningLabel(cb['type'])} n’est pas une vacation du régime de ${eA['nomComplet']}.', 'Choisir un collègue de même régime.');
    }
    final r1 = controle(eB, '${cv['date']}', cv['type'] as String?, '${cb['id']}');
    if (r1 != null) return r1;
    return controle(eA, '${cb['date']}', cb['type'] as String?, '${cv['id']}');
  }
  return RefusRh('TYPE_PROPOSITION_INCONNU', 'Le type de proposition « $t » n’existe pas.', 'Choisir ajout, modification, retrait ou échange.');
}

/// Les propositions visibles d'un rôle : l'agent ne voit que les siennes (RG-13), le surveillant, la DAF et l'administrateur voient tout.
List<FichePlanning> propositionsVisiblesRh(List<FichePlanning> actives, String role, String? moiId, {DroitsGestes? gestes}) {
  if (_peutRh(gestes, role, gesteRhEncadrer)) return actives;
  if (moiId == null) return const [];
  return [for (final p in actives) if (p['employeId'] == moiId) p];
}

/// La décision du surveillant sur une proposition : le refus nommé, ou `null` (le contrôle d'application se fait par [controlerPropositionRh]).
RefusRh? peutTrancherPropositionRh({
  required FichePlanning? proposition,
  required String role,
  required String decision,
  required String? motif,
  String? moiId,
  DroitsGestes? gestes,
}) {
  if (!_peutRh(gestes, role, gesteRhEncadrer)) {
    return const RefusRh('VALIDATION_RESERVEE', 'Le planning se valide par le surveillant (ou la Directrice Administrative).', 'Demander au surveillant.');
  }
  if (proposition == null || proposition['statut'] == 'archive') {
    return const RefusRh('PROPOSITION_INTROUVABLE', 'La proposition n’existe pas.', 'Choisir une proposition de la liste.');
  }
  if (decision != 'valider' && decision != 'refuser') return const RefusRh('DECISION_INCONNUE', 'La décision est « valider » ou « refuser ».', 'Choisir une décision.');
  final etat = proposition['etat'];
  if (etat != 'proposee') {
    return RefusRh('DEJA_TRANCHEE', 'La proposition est déjà ${etat == 'validee' ? 'validée' : (etat == 'refusee' ? 'refusée' : 'retirée')} : une décision ne se réécrit pas.', 'Attendre une nouvelle proposition.');
  }
  if (moiId != null && proposition['employeId'] == moiId) return const RefusRh('AUTO_VALIDATION', 'Personne ne valide sa propre proposition.', 'Demander à un autre habilité.');
  if (decision == 'refuser' && (motif ?? '').trim().isEmpty) {
    return const RefusRh('MOTIF_OBLIGATOIRE', 'Un refus exige son motif : l’agent doit pouvoir le lire.', 'Écrire le motif du refus.');
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------
// Les gestes de l'écran (lots L5 et L6) : réglages, pose et retrait du planning, régularisation, avis du chef de service, retrait d'une proposition
// ---------------------------------------------------------------------------------------------------------------------

/// Qui règle le circuit de validation et « l'agent modifie directement » : l'administrateur et la Directrice Administrative. [genre] : `circuit` ou `direct`.
/// Une valeur de circuit hors référentiel est refusée ; pour `direct`, toute valeur autre que vrai vaut non (comme la maquette).
RefusRh? controlerReglageRh({required String role, required String genre, Object? valeur, DroitsGestes? gestes}) {
  if (!_peutRh(gestes, role, gesteRhRegler)) {
    return genre == 'circuit'
        ? const RefusRh('REGLAGE_RESERVE', 'Le circuit de validation se règle par l’administrateur ou la Directrice Administrative.', 'Demander à la Directrice Administrative.')
        : const RefusRh('REGLAGE_RESERVE', 'Ce réglage se fait par l’administrateur ou la Directrice Administrative.', 'Demander à la Directrice Administrative.');
  }
  if (genre == 'circuit' && !circuitsRh.containsKey(valeur)) {
    return RefusRh('CIRCUIT_INCONNU', 'Le circuit « $valeur » n’existe pas.', 'Choisir surveillant seul, directrice administrative seule, ou surveillant puis directrice administrative.');
  }
  return null;
}

/// Le planning du personnel se pose et se retire par le surveillant, la Directrice Administrative ou l'administrateur ; un agent PROPOSE.
RefusRh? peutPoserPlanningRh(String role, {bool retrait = false, DroitsGestes? gestes}) {
  if (_peutRh(gestes, role, gesteRhEncadrer)) return null;
  return retrait
      ? const RefusRh('PLANNING_RESERVE', 'Le planning du personnel se retire par le surveillant ou la Directrice Administrative.', 'Demander au surveillant.')
      : const RefusRh('PLANNING_RESERVE', 'Le planning du personnel se pose par le surveillant ou la Directrice Administrative.',
          'Un agent propose ses vacations (propositions de planning) ; le surveillant valide.');
}

/// Le retrait d'une vacation : le droit, puis l'existence (une vacation archivée n'existe plus).
RefusRh? controlerRetraitVacationRh({required String role, required FichePlanning? vacation, required Object? id, DroitsGestes? gestes}) {
  final r = peutPoserPlanningRh(role, retrait: true, gestes: gestes);
  if (r != null) return r;
  if (vacation == null || vacation['statut'] == 'archive') {
    return RefusRh('VACATION_INTROUVABLE', 'La vacation $id n’existe pas ou est déjà retirée.', 'Choisir une vacation du registre.');
  }
  return null;
}

String? _texteOuNull(Object? x) => x is String && x.isNotEmpty ? x : null;

/// RÉGULARISER un pointage : correction DATÉE, avec auteur et motif obligatoire, réservée aux habilités du circuit. Rend le refus nommé, ou le patch à écrire
/// (l'état, la trace ajoutée à `regularisations`, et `motifCode` / `justificatif` seulement s'ils sont fournis).
({RefusRh? refus, Map<String, Object?>? patch}) regulariserPresenceRh({
  required FichePlanning? rec,
  required String role,
  required String acteur,
  required String aujourdhui,
  required Map<String, Object?> o,
  String? moiId,
  DroitsGestes? gestes,
}) {
  ({RefusRh? refus, Map<String, Object?>? patch}) non(RefusRh r) => (refus: r, patch: null);
  if (rec == null || rec['statut'] == 'archive') return non(const RefusRh('PIECE_INTROUVABLE', 'Le pointage n’existe pas ou est archivé.', 'Choisir une ligne du registre.'));
  if (!_peutRh(gestes, role, gesteRhEncadrer)) {
    return non(const RefusRh('REGULARISATION_RESERVEE', 'La régularisation d’un pointage se fait par le surveillant ou la Directrice Administrative.', 'Demander au surveillant.'));
  }
  final motif = '${o['motif'] ?? ''}'.trim();
  if (motif.isEmpty) return non(const RefusRh('MOTIF_OBLIGATOIRE', 'Le motif de la régularisation est obligatoire.', 'Dire ce qui justifie la correction.'));
  const etats = ['present', 'retard', 'absent', 'conge'];
  if (!etats.contains(o['etat'])) {
    return non(RefusRh('ETAT_INCONNU', 'L’état « ${o['etat']} » n’existe pas.', 'Choisir présent, retard, absent ou congé.'));
  }
  final code = _texteOuNull(o['motifCode']);
  if (code != null && !motifsAbsenceRh.any((x) => x.id == code)) {
    return non(RefusRh('MOTIF_CODE_INCONNU', 'Le motif codé « $code » n’existe pas.', 'Choisir maladie, mission ou congé.'));
  }
  if (moiId != null && '${rec['employeId']}' == moiId) {
    return non(const RefusRh('AUTO_VALIDATION', 'Personne ne régularise son propre pointage.', 'Demander à un autre habilité.'));
  }
  final trace = <String, Object?>{
    'le': aujourdhui,
    'par': acteur,
    'motif': motif,
    'etatAvant': rec['etat'],
    'etatApres': o['etat'],
    'motifCodeAvant': _texteOuNull(rec['motifCode']),
    'motifCodeApres': code ?? _texteOuNull(rec['motifCode']),
  };
  final patch = <String, Object?>{
    'etat': o['etat'],
    'regularisations': [for (final x in (rec['regularisations'] as List? ?? const [])) x, trace],
  };
  if (o.containsKey('motifCode')) patch['motifCode'] = code;
  if (o.containsKey('justificatif')) patch['justificatif'] = _texteOuNull(o['justificatif']);
  return (refus: null, patch: patch);
}

/// L'AVIS DU CHEF DE SERVICE sur un ordre de mission : consigné par un habilité du circuit, lu à la validation. Rend le refus nommé, ou le patch à écrire.
({RefusRh? refus, Map<String, Object?>? patch}) avisMissionRh({
  required FichePlanning? rec,
  required String role,
  required String acteur,
  required String aujourdhui,
  required Map<String, Object?> o,
  DroitsGestes? gestes,
}) {
  ({RefusRh? refus, Map<String, Object?>? patch}) non(RefusRh r) => (refus: r, patch: null);
  if (rec == null || rec['statut'] == 'archive') return non(const RefusRh('PIECE_INTROUVABLE', 'L’ordre de mission n’existe pas ou est archivé.', 'Choisir une ligne du registre.'));
  if (!_peutRh(gestes, role, gesteRhEncadrer)) {
    return non(const RefusRh('AVIS_RESERVE', 'L’avis du chef de service se consigne par le surveillant, la Directrice Administrative ou l’administrateur.', 'Demander au surveillant.'));
  }
  final avis = o['avis'];
  if (avis != 'favorable' && avis != 'defavorable') return non(const RefusRh('AVIS_INCONNU', 'L’avis est « favorable » ou « défavorable ».', 'Choisir l’avis.'));
  final chef = '${o['chef'] ?? ''}'.trim();
  if (chef.isEmpty) return non(const RefusRh('CHEF_ABSENT', 'Le nom du chef de service qui donne l’avis est obligatoire.', 'Choisir le chef de service de l’agent.'));
  final motif = '${o['motif'] ?? ''}'.trim();
  if (avis == 'defavorable' && motif.isEmpty) return non(const RefusRh('MOTIF_OBLIGATOIRE', 'Un avis défavorable exige son motif.', 'Dire pourquoi l’avis est défavorable.'));
  final etat = etatValidationRh('missions', rec);
  if (etat == 'valide' || etat == 'refuse') {
    return non(const RefusRh('DEJA_TRANCHEE', 'L’ordre de mission est déjà tranché : l’avis se donne avant la décision.', 'Saisir un nouvel ordre.'));
  }
  return (
    refus: null,
    patch: {
      'avisChefService': {'avis': avis, 'chef': chef, 'motif': motif.isEmpty ? null : motif, 'le': aujourdhui, 'consignePar': acteur}
    }
  );
}

/// L'agent RETIRE sa propre proposition tant qu'elle n'est pas tranchée. Rend le refus nommé, ou le patch à écrire.
({RefusRh? refus, Map<String, Object?>? patch}) annulerPropositionRh({required FichePlanning? proposition, required String aujourdhui, String? moiId}) {
  ({RefusRh? refus, Map<String, Object?>? patch}) non(RefusRh r) => (refus: r, patch: null);
  if (proposition == null || proposition['statut'] == 'archive') return non(const RefusRh('PROPOSITION_INTROUVABLE', 'La proposition n’existe pas.', 'Choisir une proposition de la liste.'));
  if (moiId == null || proposition['employeId'] != moiId) {
    return non(const RefusRh('PROPOSITION_D_AUTRUI', 'Seul l’agent qui a proposé peut retirer sa proposition.', 'Se connecter avec son compte.'));
  }
  final etat = proposition['etat'];
  if (etat != 'proposee') {
    return non(RefusRh('DEJA_TRANCHEE', 'La proposition est déjà ${etat == 'validee' ? 'validée' : (etat == 'refusee' ? 'refusée' : 'retirée')}.', 'Faire une nouvelle proposition.'));
  }
  return (refus: null, patch: {'etat': 'annulee', 'annuleeLe': aujourdhui});
}

// ---------------------------------------------------------------------------------------------------------------------
// Les gardes de collection : ce que le MOTEUR refuse, quoi que montre l'écran (masquer un bouton ne protège rien)
// ---------------------------------------------------------------------------------------------------------------------

/// Une version de régime individuel ne se réécrit ni ne s'archive : elle explique des vacations déjà posées. `null` : l'opération passe (l'insertion seule).
String? gardeRegimeIndividuelRh(String operation) => operation == 'modifier' || operation == 'archiver'
    ? 'REGIME_INDIVIDUEL_FIGE : une version de régime individuel ne se réécrit ni ne s’archive (elle explique des vacations déjà posées). Ajouter une nouvelle version à une date d’effet postérieure, ou « revenir au régime de la catégorie ».'
    : null;

/// Un pointage validé ne se modifie pas directement : il se régularise (motif, date et auteur consignés). [avant] : la fiche telle qu'elle est ; [apres] : telle
/// qu'elle serait après la mise à jour. Une pièce d'avant le circuit (sans état validé) reste éditable ; une régularisation (la trace s'allonge) passe.
String? gardePresenceValideeRh(String operation, FichePlanning? avant, FichePlanning apres) {
  if (operation != 'modifier' || avant == null || avant['validationEtat'] != 'valide') return null;
  String v(FichePlanning f, String k) => f[k] == null ? '' : '${f[k]}';
  final change = ['etat', 'date', 'employeId', 'heureArrivee', 'heureDepart', 'motifCode'].any((k) => v(avant, k) != v(apres, k));
  final regularise = ((apres['regularisations'] as List?)?.length ?? 0) > ((avant['regularisations'] as List?)?.length ?? 0);
  return change && !regularise ? 'PRESENCE_VALIDEE : un pointage validé ne se modifie pas directement ; le régulariser (motif, date et auteur consignés).' : null;
}
