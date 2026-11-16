// LE PLAN DE TRAVAIL ANNUEL (PTA) — écran `m13-plan-annuel` (Direction de Baguidi, 17/11/2026 : « Oui au lot PTA. RIEN NE DOIT ÊTRE EN DUR. »).
//
// L'ancien « plan annuel de travail » de la maquette portait douze actions semées en dur sur l'année 2026, trois états écrits dans le code et un
// découpage en quatre trimestres figé. Le PTA en garde l'écran (même identifiant, mêmes droits de la matrice) et le refait sur SIX principes :
//
//  * PAR EXERCICE : l'exercice est celui du sélecteur de la barre supérieure (défaut : celui qui contient la date du jour) ; ses bornes viennent de la fiche
//    d'exercice (`debut`, `fin`), à défaut de l'année civile. Aucune année n'est écrite ici : la numérotation est une série annuelle `PTA-<exercice>-NNN`.
//  * RÉFÉRENTIELS ADMINISTRABLES : axes (`ptaAxes`) et états d'avancement (`ptaEtats`, libellé, ton et sens : réalisé, terminé, exclu du taux) sont des
//    collections réglées sous un geste réservé ; le DÉCOUPAGE (trimestre, mois, semestre) et le SEUIL d'alerte de retard sont des paramètres de clinique
//    versionnés par date. Tous sont semés de valeurs d'attente marquées « à valider ».
//  * UNE ACTION COMPLÈTE : intitulé, axe, objectif, indicateur et cible, valeur réalisée, avancement saisi OU calculé (et l'écran dit lequel), période,
//    responsable du personnel (ou une fonction, un service), service porteur, budget prévu et lien vers une ligne du module Budgets dont le RÉALISÉ est lu
//    au module (jamais ressaisi).
//  * UN CYCLE DE VIE : brouillon → soumis → ADOPTÉ (geste réservé, motif, jamais adopté par celui qui a soumis, jamais d'adoption automatique) → en exécution →
//    clôturé (bilan). Un plan adopté ne se réécrit pas : une RÉVISION ouvre une nouvelle version datée ; l'ancienne reste, « remplacée » (RG-14).
//  * DES ALERTES : une action non terminée dont la période est échue depuis plus que le seuil est EN RETARD ; une ligne par action, routée par geste réservé.
//  * DES IDENTITÉS QUI VOYAGENT : un plan se désigne par (exercice, version), un axe et un état par leur CODE, une ligne de budget par sa RÉFÉRENCE — jamais
//    par un identifiant local, que la synchronisation préfixe du poste qui l'a créé.
//
// Fonctions PURES : le poste y branche ses collections, sa matrice et son journal ; la mère y rejoue les dépôts des fileuls. Écarts : E3790 à E3829.
library;

import 'dart:convert' show jsonEncode;

import '../comptabilite/cpa_ecritures.dart' show cpaEcrituresExercice;
import '../comptabilite/cpb_gestion.dart' show cpbRealise;
import '../droits/gestes_reserves.dart';
import '../format/format_fr.dart';
import '../format/js.dart' show arrondiJs;
import '../parametres/definitions.dart' show definitionDeParametre;
import '../validation/validation.dart' show RefusValidation, valInstant;
import '../validation/validation_deposee.dart';
import 'adm_regles.dart' show AdmKpi, admReferenceSuivante;

typedef PtaFiche = Map<String, Object?>;

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Collections et paramètres
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les actions du plan (le nom historique de la collection est conservé : les postes installés la portent déjà).
const String ptaCollectionActions = 'planAnnuel';

/// Les en-têtes de plan : une fiche par (exercice, version).
const String ptaCollectionPlans = 'plansTravail';

/// Les axes du plan (référentiel administrable).
const String ptaCollectionAxes = 'ptaAxes';

/// Les états d'avancement d'une action (référentiel administrable).
const String ptaCollectionEtats = 'ptaEtats';

/// Les sources de financement d'une action (référentiel administrable).
const String ptaCollectionFinancements = 'ptaFinancements';

/// Les cinq collections du PTA (synchronisées entre postes, jamais vers un téléphone : une action porte un budget).
const Set<String> ptaCollections = {ptaCollectionActions, ptaCollectionPlans, ptaCollectionAxes, ptaCollectionEtats, ptaCollectionFinancements};

/// Les trois référentiels administrables du PTA, réglés sous le geste `pta_regler`.
const List<String> ptaReferentiels = [ptaCollectionAxes, ptaCollectionEtats, ptaCollectionFinancements];

/// La clé du paramètre de clinique « découpage du plan » (trimestre, mois, semestre), versionné par date.
const String ptaCleDecoupage = 'pta.decoupage';

/// La clé du paramètre de clinique « seuil d'alerte de retard » (en jours), versionné par date.
const String ptaCleSeuilRetard = 'pta.seuilRetardJours';

/// La clé du paramètre de clinique « préfixe de la numérotation » des actions (`<préfixe>-<exercice>-NNN`), versionné par date.
const String ptaClePrefixe = 'pta.prefixeNumero';

/// Le nombre de mois d'une période, par découpage : la SEULE table de sens du réglage (ses choix et leurs libellés vivent au registre des paramètres).
const Map<String, int> ptaMoisParPeriode = {'trimestre': 3, 'mois': 1, 'semestre': 6};

/// D'où viennent les valeurs semées : la clinique n'a AUCUN modèle officiel de PTA (précision de la Direction de Baguidi) ; le modèle semé est une PROPOSITION.
const String ptaSourceModele = 'Modèle proposé le 16/11/2026, à valider';

/// La mention portée par chaque élément semé, à l'écran et sur la pièce.
const String ptaMentionProposition = 'Proposition à valider par la Direction';

/// Le découpage en vigueur (valeur du paramètre), son défaut au registre si la valeur est illisible.
String ptaDecoupageDe(Object? valeur) {
  final v = '${valeur ?? ''}';
  if (ptaMoisParPeriode.containsKey(v)) return v;
  return '${definitionDeParametre(ptaCleDecoupage)?.defaut}';
}

/// Le préfixe de numérotation en vigueur (majuscules, chiffres ; son défaut au registre s'il est vide ou illisible).
String ptaPrefixeDe(Object? valeur) {
  final v = '${valeur ?? ''}'.trim().toUpperCase();
  if (RegExp(r'^[A-Z0-9]{1,12}$').hasMatch(v)) return v;
  return '${definitionDeParametre(ptaClePrefixe)?.defaut}';
}

/// Le seuil de retard en vigueur (jours), son défaut au registre si la valeur est illisible ou négative.
int ptaSeuilDe(Object? valeur) {
  final n = valeur is num ? valeur.toInt() : int.tryParse('${valeur ?? ''}'.trim());
  if (n != null && n >= 0) return n;
  final d = definitionDeParametre(ptaCleSeuilRetard)?.defaut;
  return d is num ? d.toInt() : 0;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Référentiels : axes et états
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les tons proposés pour un état (jetons du design system, pas une donnée métier).
const List<String> ptaTons = ['navy', 'info', 'success', 'warning', 'danger', 'neutre'];

const List<(String, String)> _axesSemes = [
  ('qualite_securite_soins', 'Qualité et sécurité des soins'),
  ('sante_mere_enfant', 'Santé de la mère et de l’enfant (CPN, accouchements, PF, vaccination)'),
  ('medicaments_consommables', 'Disponibilité des médicaments et consommables'),
  ('ressources_humaines_formation', 'Ressources humaines et formation'),
  ('infrastructures_equipements', 'Infrastructures, équipements et maintenance'),
  ('finances_recouvrement', 'Gestion financière et recouvrement (assurances, créances)'),
  ('systeme_information', 'Système d’information et numérique (SIGH, statistiques, rapports)'),
  ('gouvernance_partenariats', 'Gouvernance, partenariats et communication'),
];

/// Les axes SEMÉS (valeurs d'attente, à valider) : identifiants déterministes, les mêmes sur tous les postes.
List<PtaFiche> ptaSemenceAxes() => [
      for (final (i, a) in _axesSemes.indexed)
        {'id': 'PTAX-${a.$1}', 'statut': 'actif', 'code': a.$1, 'libelle': a.$2, 'ordre': i + 1, 'aValider': true, 'mention': ptaMentionProposition, 'source': ptaSourceModele}
    ];

/// Les états SEMÉS (valeurs d'attente, à valider). `realise` : compte comme réalisée ; `termine` : n'est plus suivie (ni retard ni alerte) ;
/// `exclutTaux` : sort du dénominateur du taux d'exécution ; `parDefaut` : l'état d'une action nouvelle.
List<PtaFiche> ptaSemenceEtats() => [
      for (final (i, e) in const [
        ('planifiee', 'Planifiée', 'warning', false, false, false, true),
        ('en_cours', 'En cours', 'info', false, false, false, false),
        ('realisee', 'Réalisée', 'success', true, true, false, false),
        ('reportee', 'Reportée', 'neutre', false, false, false, false),
        ('abandonnee', 'Abandonnée', 'danger', false, true, true, false),
      ].indexed)
        {
          'id': 'PTAE-${e.$1}',
          'statut': 'actif',
          'code': e.$1,
          'libelle': e.$2,
          'ton': e.$3,
          'ordre': i + 1,
          'realise': e.$4,
          'termine': e.$5,
          'exclutTaux': e.$6,
          'parDefaut': e.$7,
          'aValider': true,
          'mention': ptaMentionProposition,
          'source': ptaSourceModele,
        }
    ];

/// Les sources de financement SEMÉES (proposition à valider).
List<PtaFiche> ptaSemenceFinancements() => [
      for (final (i, f) in const [
        ('fonds_propres', 'Fonds propres'),
        ('assurances', 'Assurances'),
        ('partenaire', 'Partenaire'),
        ('etat', 'État'),
        ('autre', 'Autre'),
      ].indexed)
        {'id': 'PTAF-${f.$1}', 'statut': 'actif', 'code': f.$1, 'libelle': f.$2, 'ordre': i + 1, 'aValider': true, 'mention': ptaMentionProposition, 'source': ptaSourceModele}
    ];

/// La semence d'un référentiel du PTA, par collection.
List<PtaFiche> ptaSemenceDe(String collection) => switch (collection) {
      ptaCollectionAxes => ptaSemenceAxes(),
      ptaCollectionEtats => ptaSemenceEtats(),
      ptaCollectionFinancements => ptaSemenceFinancements(),
      _ => const [],
    };

int _ordre(PtaFiche f) => f['ordre'] is num ? (f['ordre'] as num).toInt() : 1 << 20;

/// Les fiches ACTIVES d'un référentiel, dans l'ordre réglé. Une collection VIDE (jamais semée : le jeu n'a pas été chargé) retombe sur la semence, en lecture.
List<PtaFiche> ptaReferentiel(Iterable<PtaFiche> fiches, List<PtaFiche> Function() semence) {
  final toutes = fiches.toList();
  if (toutes.isEmpty) return semence();
  return [for (final f in toutes) if (f['statut'] != 'archive') f]
    ..sort((a, b) {
      final o = _ordre(a).compareTo(_ordre(b));
      return o != 0 ? o : '${a['libelle']}'.compareTo('${b['libelle']}');
    });
}

List<PtaFiche> ptaAxesEnForce(Iterable<PtaFiche> fiches) => ptaReferentiel(fiches, ptaSemenceAxes);
List<PtaFiche> ptaEtatsEnForce(Iterable<PtaFiche> fiches) => ptaReferentiel(fiches, ptaSemenceEtats);
List<PtaFiche> ptaFinancementsEnForce(Iterable<PtaFiche> fiches) => ptaReferentiel(fiches, ptaSemenceFinancements);

/// La fiche d'un code, ARCHIVÉES comprises (une action garde le libellé de son axe archivé), puis la semence.
PtaFiche? ptaParCode(Object? code, Iterable<PtaFiche> fiches, List<PtaFiche> Function() semence) {
  if (code == null || '$code'.isEmpty) return null;
  for (final f in fiches) {
    if ('${f['code']}' == '$code' && f['statut'] != 'archive') return f;
  }
  for (final f in fiches) {
    if ('${f['code']}' == '$code') return f;
  }
  if (fiches.isEmpty) {
    for (final f in semence()) {
      if (f['code'] == '$code') return f;
    }
  }
  return null;
}

PtaFiche? ptaEtat(Object? code, Iterable<PtaFiche> etats) => ptaParCode(code, etats, ptaSemenceEtats);
PtaFiche? ptaAxe(Object? code, Iterable<PtaFiche> axes) => ptaParCode(code, axes, ptaSemenceAxes);
PtaFiche? ptaFinancement(Object? code, Iterable<PtaFiche> f) => ptaParCode(code, f, ptaSemenceFinancements);

/// Le libellé affiché d'un code (le code lui-même s'il n'est connu d'aucun référentiel : il se dit, il ne disparaît pas).
String ptaLibelleEtat(Object? code, Iterable<PtaFiche> etats) => code == null || '$code'.isEmpty ? '—' : '${ptaEtat(code, etats)?['libelle'] ?? code}';
String ptaLibelleAxe(Object? code, Iterable<PtaFiche> axes) => code == null || '$code'.isEmpty ? '—' : '${ptaAxe(code, axes)?['libelle'] ?? code}';
String ptaLibelleFinancement(Object? code, Iterable<PtaFiche> f) => code == null || '$code'.isEmpty ? '—' : '${ptaFinancement(code, f)?['libelle'] ?? code}';
String ptaTonEtat(Object? code, Iterable<PtaFiche> etats) => '${ptaEtat(code, etats)?['ton'] ?? 'neutre'}';

/// L'état d'une action nouvelle : celui que le référentiel marque `parDefaut`, à défaut le premier.
String? ptaEtatParDefaut(Iterable<PtaFiche> etats) {
  final l = ptaEtatsEnForce(etats);
  for (final e in l) {
    if (e['parDefaut'] == true) return '${e['code']}';
  }
  return l.isEmpty ? null : '${l.first['code']}';
}

bool _vrai(Object? v) => v == true;
bool ptaEtatRealise(Object? code, Iterable<PtaFiche> etats) => _vrai(ptaEtat(code, etats)?['realise']);
bool ptaEtatTermine(Object? code, Iterable<PtaFiche> etats) => _vrai(ptaEtat(code, etats)?['termine']);
bool ptaEtatExclutTaux(Object? code, Iterable<PtaFiche> etats) => _vrai(ptaEtat(code, etats)?['exclutTaux']);

final RegExp _code = RegExp(r'^[a-z0-9_]{2,40}$');

/// Le contrôle UNIQUE d'une fiche de référentiel (création ou modification) : geste réservé, code (minuscules, chiffres, souligné) unique et IMMUABLE, libellé,
/// ton connu pour un état. `null` : recevable.
RefusValidation? ptaControlerReferentiel(String collection, PtaFiche valeurs, Iterable<PtaFiche> existants,
    {PtaFiche? avant, required String role, required DroitsGestes gestes}) {
  if (!ptaReferentiels.contains(collection)) {
    return RefusValidation('REFERENTIEL_INCONNU', 'Référentiel inconnu : $collection.', null);
  }
  if (!gestes.peut(role, gestePtaRegler)) {
    return RefusValidation('REGLAGE_RESERVE',
        'Régler les référentiels du plan de travail annuel est le geste réservé « ${gesteReserve(gestePtaRegler)!.libelle} » : le rôle « $role » ne le détient pas.',
        'Demander à un rôle qui détient le geste, ou à la Direction de l’accorder dans Rôles et permissions › Gestes réservés');
  }
  final code = '${valeurs['code'] ?? ''}'.trim();
  if (avant != null && '${avant['code']}' != code) {
    return RefusValidation('CODE_IMMUABLE', 'Le code « ${avant['code']} » ne change pas : les actions du plan le citent, sur tous les postes.',
        'Archiver cette fiche et en créer une nouvelle');
  }
  if (!_code.hasMatch(code)) {
    return const RefusValidation('CODE_INVALIDE', 'Le code s’écrit en minuscules, chiffres et soulignés (2 à 40 caractères), sans espace ni accent.', 'Corriger le code');
  }
  for (final f in existants) {
    if ('${f['code']}' == code && (avant == null || f['id'] != avant['id'])) {
      return RefusValidation('CODE_EXISTANT', 'Le code « $code » existe déjà (${f['libelle']}${f['statut'] == 'archive' ? ', archivé' : ''}).', 'Choisir un autre code, ou restaurer la fiche archivée');
    }
  }
  if ('${valeurs['libelle'] ?? ''}'.trim().isEmpty) return const RefusValidation('LIBELLE_OBLIGATOIRE', 'Le libellé est obligatoire.', 'Saisir le libellé');
  if (collection == ptaCollectionEtats && !ptaTons.contains('${valeurs['ton'] ?? ''}')) {
    return RefusValidation('TON_INCONNU', 'Ton inconnu : ${valeurs['ton']}.', 'Choisir un ton parmi ${ptaTons.join(', ')}');
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Exercice et périodes
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// L'exercice d'un plan : son année, ses bornes, et s'il a une fiche (`amorce`).
class PtaExercice {
  const PtaExercice(this.annee, this.debut, this.fin, {this.amorce = true});
  final int annee;
  final DateTime debut;
  final DateTime fin;
  final bool amorce;
}

DateTime? _jour(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// L'exercice [annee] lu aux fiches d'exercice (bornes `debut` / `fin`) ; sans fiche, l'année civile — et l'écran dit « non amorcé ».
PtaExercice ptaExercice(Iterable<PtaFiche> exercices, int annee) {
  for (final x in exercices) {
    if (x['statut'] == 'archive' || '${x['annee']}' != '$annee') continue;
    final d = _jour(x['debut']), f = _jour(x['fin']);
    if (d != null && f != null && !f.isBefore(d)) return PtaExercice(annee, d, f);
  }
  return PtaExercice(annee, DateTime(annee, 1, 1), DateTime(annee, 12, 31), amorce: false);
}

/// La date à laquelle se lisent les réglages d'un exercice : le jour, ramené dans les bornes de l'exercice (un exercice passé lit son dernier jour, un
/// exercice à venir son premier). Un réglage changé en cours d'année vaut donc pour l'exercice en cours, pas pour un exercice clos.
DateTime ptaDateReglage(PtaExercice e, DateTime auj) {
  final j = DateTime(auj.year, auj.month, auj.day);
  if (j.isBefore(e.debut)) return e.debut;
  if (j.isAfter(e.fin)) return e.fin;
  return j;
}

const List<String> _moisCourts = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

/// Une période du plan (un trimestre, un mois, un semestre) : rang, code court (T1, M1, S1), libellés, bornes.
class PtaPeriode {
  const PtaPeriode(this.rang, this.code, this.libelle, this.libelleLong, this.debut, this.fin);
  final int rang;
  final String code;
  final String libelle;
  final String libelleLong;
  final DateTime debut;
  final DateTime fin;
  String get debutIso => iso(debut);
  String get finIso => iso(fin);
}

/// Les périodes de l'exercice selon le découpage réglé, de son premier jour à son dernier (un exercice qui ne commence pas en janvier est découpé depuis son début).
List<PtaPeriode> ptaPeriodes(PtaExercice e, String decoupage) {
  final pas = ptaMoisParPeriode[decoupage] ?? ptaMoisParPeriode[ptaDecoupageDe(null)] ?? 3;
  final prefixe = switch (decoupage) { 'mois' => 'M', 'semestre' => 'S', _ => 'T' };
  final out = <PtaPeriode>[];
  var d = e.debut;
  var rang = 1;
  while (!d.isAfter(e.fin) && rang <= 60) {
    final suivant = DateTime(d.year, d.month + pas, d.day);
    var fin = DateTime(suivant.year, suivant.month, suivant.day - 1);
    if (fin.isAfter(e.fin)) fin = e.fin;
    final m1 = _moisCourts[d.month - 1], m2 = _moisCourts[fin.month - 1];
    final court = decoupage == 'mois' ? '${m1[0].toUpperCase()}${m1.substring(1)}' : '$prefixe$rang';
    final long = decoupage == 'mois' ? '$m1 ${d.year}' : '$prefixe$rang ($m1 – $m2)';
    out.add(PtaPeriode(rang, '$prefixe$rang', court, long, d, fin));
    d = suivant;
    rang++;
  }
  return out;
}

/// Le CALENDRIER d'une action : les périodes COCHÉES, écrites par leurs bornes (`AAAA-MM-JJ/AAAA-MM-JJ`) et non par leur code : changer le découpage ne réécrit
/// aucune action, et une période cochée sous l'ancien découpage se lit encore sous le nouveau.
List<(DateTime, DateTime)> ptaCalendrier(PtaFiche action) {
  final out = <(DateTime, DateTime)>[];
  final c = action['calendrier'];
  if (c is List) {
    for (final x in c) {
      final p = '$x'.split('/');
      if (p.length != 2) continue;
      final d = _jour(p[0]), f = _jour(p[1]);
      if (d != null && f != null && !f.isBefore(d)) out.add((d, f));
    }
  }
  if (out.isEmpty) {
    final f = _jour(action['fin']);
    final d = _jour(action['debut']) ?? f;
    if (d != null && f != null && !f.isBefore(d)) out.add((d, f));
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}

/// La valeur du calendrier pour les périodes cochées.
List<String> ptaCalendrierDe(Iterable<PtaPeriode> cochees) => [for (final p in cochees) '${p.debutIso}/${p.finIso}'];

/// Le premier et le dernier jour d'un calendrier (`null` s'il est vide) : ce que l'action porte en `debut` / `fin`, et d'où se compte le retard.
(String, String)? ptaBornesCalendrier(List<String> calendrier) {
  final l = ptaCalendrier({'calendrier': calendrier});
  if (l.isEmpty) return null;
  var fin = l.first.$2;
  for (final x in l) {
    if (x.$2.isAfter(fin)) fin = x.$2;
  }
  return (iso(l.first.$1), iso(fin));
}

/// L'action couvre-t-elle la période ? (une période cochée, ou à défaut ses bornes, chevauche la période)
bool ptaCouvre(PtaFiche action, PtaPeriode p) {
  for (final (d, f) in ptaCalendrier(action)) {
    if (!d.isAfter(p.fin) && !f.isBefore(p.debut)) return true;
  }
  return false;
}

/// « T1 – T3 » (ou « T2 » quand une seule période est couverte) ; « — » sans période.
String ptaLibellePeriode(PtaFiche action, List<PtaPeriode> periodes) {
  final c = [for (final p in periodes) if (ptaCouvre(action, p)) p];
  if (c.isEmpty) return '—';
  return c.length == 1 ? c.first.libelle : '${c.first.libelle} – ${c.last.libelle}';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Actions : numérotation, avancement, retard, budget
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les champs du PROGRAMME d'une action : figés dès l'adoption du plan (on révise le plan pour les changer).
const List<String> ptaChampsProgramme = [
  'action', 'axe', 'objectif', 'resultatAttendu', 'indicateur', 'valeurDepart', 'cibleValeur', 'cibleUnite', 'calendrier', 'debut', 'fin', //
  'responsableType', 'responsableId', 'responsable', 'service', 'partenaires', 'budgetPrevu', 'sourceFinancement', 'budgetReference', 'avancementMode', //
  'exercice', 'planVersion', 'reference',
];

/// Les champs du SUIVI d'une action : ils restent ouverts pendant l'exécution (les faits ne s'arrêtent pas à l'adoption), fermés après la clôture.
const List<String> ptaChampsSuivi = ['etat', 'realiseValeur', 'tauxAvancement', 'observations'];

bool _memeExercice(PtaFiche f, int annee) => '${f['exercice']}' == '$annee';

/// La référence suivante de l'exercice (`<préfixe>-<exercice>-NNN`, préfixe RÉGLÉ aux paramètres), lue sur les actions EXISTANTES de l'exercice (archivées et
/// versions antérieures comprises) — jamais un compteur de page. Le rang suit la série de l'EXERCICE quel que soit le préfixe : changer le préfixe en cours d'année
/// ne redonne pas un numéro déjà attribué. Une action révisée garde sa référence d'une version à l'autre.
String ptaReferenceSuivante(int annee, Iterable<PtaFiche> actions, {String? prefixe}) {
  final p = prefixe ?? ptaPrefixeDe(null);
  final motif = RegExp('-$annee-(\\d+)\$');
  var max = 0;
  for (final a in actions) {
    if (!_memeExercice(a, annee)) continue;
    final m = motif.firstMatch('${a['reference'] ?? ''}');
    final n = m == null ? 0 : int.parse(m.group(1)!);
    if (n > max) max = n;
  }
  return admReferenceSuivante('$p-$annee-', 3, [if (max > 0) {'reference': '$p-$annee-${max.toString().padLeft(3, '0')}'}]);
}

num? _num(Object? v) {
  if (v is num) return v;
  return num.tryParse('${v ?? ''}'.trim().replaceAll(',', '.').replaceAll(' ', '').replaceAll(' ', ''));
}

/// Le pourcentage d'avancement d'une action et D'OÙ il vient. `valeur` nulle : non calculable (ce n'est pas zéro), et `explication` dit pourquoi.
class PtaTaux {
  const PtaTaux(this.valeur, this.mode, this.explication);
  final int? valeur;

  /// `calcule` (réalisé ÷ cible) ou `saisi` (par l'agent).
  final String mode;
  final String explication;
  String get texte => valeur == null ? 'Non calculable' : '$valeur %';
}

/// Le mode d'avancement d'une action : celui qu'elle déclare ; à défaut, `saisi` si un pourcentage a été saisi, sinon `calcule`.
String ptaModeAvancement(PtaFiche a) {
  final m = '${a['avancementMode'] ?? ''}';
  if (m == 'saisi' || m == 'calcule') return m;
  return _num(a['tauxAvancement']) != null ? 'saisi' : 'calcule';
}

PtaTaux ptaTaux(PtaFiche a) {
  final mode = ptaModeAvancement(a);
  if (mode == 'saisi') {
    final t = _num(a['tauxAvancement']);
    return t == null
        ? const PtaTaux(null, 'saisi', 'Saisi par l’agent : aucun pourcentage renseigné.')
        : PtaTaux(t.round(), 'saisi', 'Saisi par l’agent.');
  }
  final cible = _num(a['cibleValeur']), realise = _num(a['realiseValeur']);
  final unite = '${a['cibleUnite'] ?? ''}'.trim();
  if (cible == null || cible <= 0) return const PtaTaux(null, 'calcule', 'Calculé (réalisé ÷ cible) : non calculable, la cible n’est pas fixée.');
  if (realise == null) return const PtaTaux(null, 'calcule', 'Calculé (réalisé ÷ cible) : non calculable, aucune valeur réalisée n’est saisie.');
  final v = arrondiJs(realise / cible * 100).toInt();
  return PtaTaux(v, 'calcule', 'Calculé : réalisé ÷ cible = ${nombre(realise)} ÷ ${nombre(cible)}${unite.isEmpty ? '' : ' $unite'}.');
}

/// L'ÉCART d'une action : réalisé − cible (même unité) ; `null` si l'une des deux manque (non calculable).
num? ptaEcart(PtaFiche a) {
  final c = _num(a['cibleValeur']), r = _num(a['realiseValeur']);
  return c == null || r == null ? null : r - c;
}

/// Les jours de retard d'une action : `null` si elle n'est pas en retard. En retard = état non terminé ET dernier jour de sa période dépassé de PLUS que le
/// seuil réglé (le seuil est une tolérance, pas une échéance).
int? ptaJoursRetard(PtaFiche a, Iterable<PtaFiche> etats, DateTime auj, int seuilJours) {
  if (a['statut'] == 'archive' || ptaEtatTermine(a['etat'], etats)) return null;
  final cal = ptaCalendrier(a);
  if (cal.isEmpty) return null;
  var fin = cal.first.$2;
  for (final x in cal) {
    if (x.$2.isAfter(fin)) fin = x.$2;
  }
  final j = DateTime.utc(auj.year, auj.month, auj.day).difference(DateTime.utc(fin.year, fin.month, fin.day)).inDays;
  return j > seuilJours ? j : null;
}

/// La ligne du module Budgets liée à l'action (par sa RÉFÉRENCE, stable d'un poste à l'autre ; archivée : non liée).
PtaFiche? ptaBudgetLie(PtaFiche a, Iterable<PtaFiche> budgets) {
  final r = '${a['budgetReference'] ?? ''}'.trim();
  if (r.isEmpty) return null;
  for (final b in budgets) {
    if (b['statut'] != 'archive' && '${b['reference']}' == r) return b;
  }
  return null;
}

/// Le RÉALISÉ d'une ligne de budget, LU au module Budgets : les débits de classe 6 de son centre de coûts, sur les écritures de l'exercice DE LA LIGNE
/// (`cpbRealise`, la règle du module, jamais recopiée). `null` : ligne absente ou sans exercice lisible (non calculable).
double? ptaRealiseBudget(PtaFiche? budget, Iterable<PtaFiche> ecrituresActives) {
  if (budget == null) return null;
  final annee = int.tryParse('${budget['exercice'] ?? ''}'.trim());
  if (annee == null) return null;
  return cpbRealise(cpaEcrituresExercice(ecrituresActives, annee), budget['centreCout']);
}

/// La synthèse d'un plan : comptes, taux d'exécution, budget prévu et réalisé.
class PtaSynthese {
  const PtaSynthese({
    required this.programmees,
    required this.realisees,
    required this.abandonnees,
    required this.enRetard,
    required this.taux,
    required this.budgetPrevu,
    required this.budgetRealise,
    required this.lignesBudgetLiees,
    required this.liensIntrouvables,
  });
  final int programmees;
  final int realisees;

  /// Actions dont l'état sort du taux (`exclutTaux`).
  final int abandonnees;
  final int enRetard;

  /// Réalisées ÷ (programmées − exclues du taux) ; `null` : non calculable (aucune action comptée).
  final int? taux;
  final num budgetPrevu;

  /// Somme des réalisés des lignes de budget liées (chaque ligne une seule fois) ; `null` : aucune ligne liée.
  final double? budgetRealise;
  final int lignesBudgetLiees;

  /// Actions qui citent une référence de budget absente (ou archivée) du module : dites, jamais comptées.
  final int liensIntrouvables;

  Map<String, Object?> versJson() => {
        'programmees': programmees,
        'realisees': realisees,
        'abandonnees': abandonnees,
        'enRetard': enRetard,
        if (taux != null) 'taux': taux,
        'budgetPrevu': budgetPrevu,
        if (budgetRealise != null) 'budgetRealise': budgetRealise,
        'lignesBudgetLiees': lignesBudgetLiees,
        'liensIntrouvables': liensIntrouvables,
      };
}

PtaSynthese ptaSynthese(List<PtaFiche> actions, Iterable<PtaFiche> etats,
    {required DateTime auj, required int seuilJours, Iterable<PtaFiche> budgets = const [], Iterable<PtaFiche> ecritures = const []}) {
  final actives = [for (final a in actions) if (a['statut'] != 'archive') a];
  var realisees = 0, exclues = 0, retard = 0, introuvables = 0;
  num prevu = 0;
  final lignes = <String, PtaFiche>{};
  for (final a in actives) {
    if (ptaEtatRealise(a['etat'], etats)) realisees++;
    if (ptaEtatExclutTaux(a['etat'], etats)) exclues++;
    if (ptaJoursRetard(a, etats, auj, seuilJours) != null) retard++;
    prevu += _num(a['budgetPrevu']) ?? 0;
    if ('${a['budgetReference'] ?? ''}'.trim().isNotEmpty) {
      final b = ptaBudgetLie(a, budgets);
      if (b == null) {
        introuvables++;
      } else {
        lignes['${b['reference']}'] = b;
      }
    }
  }
  final denom = actives.length - exclues;
  double? realiseBudget;
  for (final b in lignes.values) {
    final r = ptaRealiseBudget(b, ecritures);
    if (r != null) realiseBudget = (realiseBudget ?? 0) + r;
  }
  return PtaSynthese(
    programmees: actives.length,
    realisees: realisees,
    abandonnees: exclues,
    enRetard: retard,
    taux: denom <= 0 ? null : arrondiJs(realisees / denom * 100).toInt(),
    budgetPrevu: prevu,
    budgetRealise: realiseBudget,
    lignesBudgetLiees: lignes.length,
    liensIntrouvables: introuvables,
  );
}

/// Les indicateurs de l'écran.
List<AdmKpi> ptaKpis(PtaSynthese s) => [
      AdmKpi('Actions programmées', nombre(s.programmees), 'list-checks', 'navy'),
      AdmKpi('Réalisées', nombre(s.realisees), 'check-circle-2', 'success'),
      AdmKpi('En retard', nombre(s.enRetard), 'clock-alert', s.enRetard > 0 ? 'danger' : 'success', 'au-delà du seuil réglé'),
      AdmKpi('Taux d’exécution', s.taux == null ? 'Non calculable' : '${s.taux} %', 'loader', 'info',
          s.abandonnees > 0 ? 'réalisées ÷ programmées, ${nombre(s.abandonnees)} exclue(s)' : 'réalisées ÷ programmées'),
      AdmKpi('Budget prévu', money(s.budgetPrevu), 'wallet', 'navy'),
      AdmKpi('Budget réalisé', s.budgetRealise == null ? 'Aucune ligne liée' : money(s.budgetRealise), 'wallet', 'info',
          s.liensIntrouvables > 0 ? 'lu au module Budgets — ${nombre(s.liensIntrouvables)} lien(s) introuvable(s)' : 'lu au module Budgets'),
    ];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Plans : versions et cycle de vie
// ---------------------------------------------------------------------------------------------------------------------------------------------

const String ptaPlanBrouillon = 'brouillon';
const String ptaPlanSoumis = 'soumis';
const String ptaPlanAdopte = 'adopte';
const String ptaPlanExecution = 'execution';
const String ptaPlanCloture = 'cloture';
const String ptaPlanRemplace = 'remplace';

/// Les états du plan, dans l'ordre du cycle (des codes de circuit, comme les étapes d'un bon de besoins : leur libellé est ici, leur sens aussi).
const List<String> ptaEtatsPlan = [ptaPlanBrouillon, ptaPlanSoumis, ptaPlanAdopte, ptaPlanExecution, ptaPlanCloture, ptaPlanRemplace];
const Map<String, String> ptaLibellesEtatPlan = {
  ptaPlanBrouillon: 'Brouillon',
  ptaPlanSoumis: 'Soumis à l’adoption',
  ptaPlanAdopte: 'Adopté',
  ptaPlanExecution: 'En exécution',
  ptaPlanCloture: 'Clôturé',
  ptaPlanRemplace: 'Remplacé par une révision',
};
const Map<String, String> ptaTonsEtatPlan = {
  ptaPlanBrouillon: 'neutre',
  ptaPlanSoumis: 'warning',
  ptaPlanAdopte: 'success',
  ptaPlanExecution: 'info',
  ptaPlanCloture: 'navy',
  ptaPlanRemplace: 'neutre',
};
const Map<String, int> _rangPlan = {ptaPlanBrouillon: 0, ptaPlanSoumis: 1, ptaPlanAdopte: 2, ptaPlanExecution: 3, ptaPlanCloture: 4, ptaPlanRemplace: 5};
int? ptaRangPlan(Object? etat) => _rangPlan['$etat'];

/// Les états que SEULE l'application d'une décision réservée écrit (sur la mère, ou au poste mère sous le geste) : un fileul les DÉPOSE.
const Set<String> ptaEtatsPlanReserves = {ptaPlanAdopte, ptaPlanCloture, ptaPlanRemplace};

/// Les états où le PROGRAMME est figé (un plan adopté ne se réécrit pas).
const Set<String> ptaEtatsPlanFiges = {ptaPlanAdopte, ptaPlanExecution, ptaPlanCloture, ptaPlanRemplace};

/// Les états où le plan est EN VIGUEUR (ses actions se suivent, ses retards alertent).
const Set<String> ptaEtatsPlanEnVigueur = {ptaPlanAdopte, ptaPlanExecution};

/// Les champs d'un en-tête que seule une décision réservée écrit.
const List<String> ptaChampsPlanReserves = [
  'adopteLe', 'adoptePar', 'adopteRole', 'motifAdoption', 'renvoyeLe', 'renvoyePar', 'motifRenvoi', //
  'clotureLe', 'cloturePar', 'bilan', 'remplaceLe', 'remplaceParVersion',
];

String ptaLibelleEtatPlan(Object? e) => ptaLibellesEtatPlan['$e'] ?? '$e';

/// La référence lisible d'un plan.
/// La référence d'un plan : le PRÉFIXE vient du réglage `pta.prefixeNumero` (semence lue par [ptaPrefixeDe]), jamais d'un littéral.
String ptaReferencePlan(int annee, int version, {String? prefixe}) => '${prefixe ?? ptaPrefixeDe(null)}-$annee-V$version';

/// L'identité d'un plan d'un poste à l'autre : `<exercice>/V<version>`.
String ptaClePlan(int annee, int version) => '$annee/V$version';

int ptaVersionDe(PtaFiche f) => f['version'] is num ? (f['version'] as num).toInt() : (int.tryParse('${f['version'] ?? f['planVersion'] ?? ''}') ?? 0);

/// Les versions du plan de l'exercice, une par numéro, de la plus ancienne à la plus récente. Deux postes hors ligne qui ont créé la même version : la plus
/// avancée dans le cycle l'emporte, puis la plus ancienne (le même résultat partout).
List<PtaFiche> ptaPlansExercice(Iterable<PtaFiche> plans, int annee) {
  final parVersion = <int, PtaFiche>{};
  for (final p in plans) {
    if (p['statut'] == 'archive' || !_memeExercice(p, annee)) continue;
    final v = ptaVersionDe(p);
    final x = parVersion[v];
    if (x == null) {
      parVersion[v] = p;
      continue;
    }
    final rp = ptaRangPlan(p['etat']) ?? -1, rx = ptaRangPlan(x['etat']) ?? -1;
    if (rp > rx || (rp == rx && '${p['creeLe'] ?? ''}${p['id']}'.compareTo('${x['creeLe'] ?? ''}${x['id']}') < 0)) parVersion[v] = p;
  }
  final cles = parVersion.keys.toList()..sort();
  return [for (final k in cles) parVersion[k]!];
}

PtaFiche? ptaPlanVersion(Iterable<PtaFiche> plans, int annee, int version) {
  for (final p in ptaPlansExercice(plans, annee)) {
    if (ptaVersionDe(p) == version) return p;
  }
  return null;
}

/// La dernière version du plan de l'exercice (`null` : aucun plan).
PtaFiche? ptaPlanCourant(Iterable<PtaFiche> plans, int annee) {
  final l = ptaPlansExercice(plans, annee);
  return l.isEmpty ? null : l.last;
}

/// La version EN VIGUEUR ou clôturée (la plus récente adoptée), `null` si aucune n'a été adoptée.
PtaFiche? ptaPlanAdopteDe(Iterable<PtaFiche> plans, int annee) {
  PtaFiche? r;
  for (final p in ptaPlansExercice(plans, annee)) {
    if (const {ptaPlanAdopte, ptaPlanExecution, ptaPlanCloture}.contains(p['etat'])) r = p;
  }
  return r;
}

/// Les actions ACTIVES d'une version du plan.
List<PtaFiche> ptaActionsDuPlan(Iterable<PtaFiche> actions, int annee, int version) => [
      for (final a in actions)
        if (a['statut'] != 'archive' && _memeExercice(a, annee) && ptaVersionDe(a) == version) a
    ];

/// Les actions saisies AVANT le PTA (sans exercice ni version) : rattachées à aucun plan, dites à l'écran, jamais comptées.
List<PtaFiche> ptaActionsHorsPlan(Iterable<PtaFiche> actions) => [
      for (final a in actions)
        if (a['statut'] != 'archive' && ('${a['exercice'] ?? ''}'.isEmpty || ptaVersionDe(a) == 0)) a
    ];

/// Ce qu'une décision écrit : une collection, l'identifiant LOCAL de la fiche, le patch.
class PtaEcriture {
  const PtaEcriture(this.collection, this.id, this.patch);
  final String collection;
  final Object? id;
  final Map<String, Object?> patch;
}

/// Le verdict d'un geste sur un plan : refus nommé, sans effet (déjà fait), ou les écritures à appliquer.
class PtaVerdict {
  const PtaVerdict.refus(RefusValidation this.refus)
      : sansEffet = false,
        ecritures = const [],
        creation = null;
  const PtaVerdict.sansEffet(RefusValidation this.refus)
      : sansEffet = true,
        ecritures = const [],
        creation = null;
  const PtaVerdict.ok({this.ecritures = const [], this.creation})
      : refus = null,
        sansEffet = false;
  final RefusValidation? refus;
  final bool sansEffet;
  final List<PtaEcriture> ecritures;

  /// Une fiche à CRÉER (nouvel en-tête de plan), le cas échéant.
  final PtaFiche? creation;
  bool get ok => refus == null;
}

RefusValidation _introuvable(int annee, int version) =>
    RefusValidation('INTROUVABLE', 'Le plan ${ptaReferencePlan(annee, version)} est introuvable ou archivé.', 'Rafraîchir le poste');

/// Crée la version 1 du plan de l'exercice, en BROUILLON. Refusé si l'exercice a déjà un plan, ou s'il est clos.
PtaVerdict ptaCreerPlan({required int annee, required Iterable<PtaFiche> plans, required String acteur, required DateTime maintenant, String? etatExercice}) {
  final existant = ptaPlanCourant(plans, annee);
  if (existant != null) {
    return PtaVerdict.refus(RefusValidation('PLAN_EXISTE', 'L’exercice $annee a déjà son plan (${ptaReferencePlan(annee, ptaVersionDe(existant))}, ${ptaLibelleEtatPlan(existant['etat']).toLowerCase()}).',
        'Ouvrir le plan existant ; pour le changer après adoption, le réviser'));
  }
  if (etatExercice == 'clos') {
    return PtaVerdict.refus(RefusValidation('EXERCICE_CLOS', 'L’exercice $annee est clos : on n’y ouvre pas de plan de travail.', 'Choisir un exercice ouvert au sélecteur'));
  }
  return PtaVerdict.ok(creation: {
    'id': ptaReferencePlan(annee, 1),
    'statut': 'actif',
    'reference': ptaReferencePlan(annee, 1),
    'exercice': annee,
    'version': 1,
    'etat': ptaPlanBrouillon,
    'creeLe': valInstant(maintenant),
    'creePar': acteur,
  });
}

/// Soumet le plan à l'adoption (droit d'écrire l'écran) : il faut un brouillon et au moins une action.
PtaVerdict ptaSoumettre(PtaFiche plan, Iterable<PtaFiche> actions, {required String acteur, required DateTime maintenant}) {
  final annee = int.tryParse('${plan['exercice']}') ?? 0, v = ptaVersionDe(plan);
  if (plan['etat'] == ptaPlanSoumis) return const PtaVerdict.sansEffet(RefusValidation('DEJA_SOUMIS', 'Le plan est déjà soumis à l’adoption.', 'Aucun'));
  if (plan['etat'] != ptaPlanBrouillon) {
    return PtaVerdict.refus(RefusValidation('PAS_BROUILLON', 'Seul un brouillon se soumet (état : ${ptaLibelleEtatPlan(plan['etat']).toLowerCase()}).', null));
  }
  if (ptaActionsDuPlan(actions, annee, v).isEmpty) {
    return const PtaVerdict.refus(RefusValidation('PLAN_VIDE', 'Un plan sans action ne se soumet pas.', 'Ajouter au moins une action'));
  }
  return PtaVerdict.ok(ecritures: [
    PtaEcriture(ptaCollectionPlans, plan['id'], {'etat': ptaPlanSoumis, 'soumisLe': valInstant(maintenant), 'soumisPar': acteur})
  ]);
}

/// Retire la soumission (retour en brouillon, droit d'écrire l'écran), tant que le plan n'est pas adopté.
PtaVerdict ptaRetirerSoumission(PtaFiche plan, {required String acteur, required DateTime maintenant}) {
  if (plan['etat'] != ptaPlanSoumis) {
    return PtaVerdict.refus(RefusValidation('PAS_SOUMIS', 'Le plan n’est pas soumis (état : ${ptaLibelleEtatPlan(plan['etat']).toLowerCase()}).', null));
  }
  return PtaVerdict.ok(ecritures: [
    PtaEcriture(ptaCollectionPlans, plan['id'], {'etat': ptaPlanBrouillon, 'retireLe': valInstant(maintenant), 'retirePar': acteur})
  ]);
}

/// Met en exécution un plan adopté (droit d'écrire l'écran) : rien n'est réservé ici, l'adoption l'a été.
PtaVerdict ptaMettreEnExecution(PtaFiche plan, {required String acteur, required DateTime maintenant}) {
  if (plan['etat'] == ptaPlanExecution) return const PtaVerdict.sansEffet(RefusValidation('DEJA_EN_EXECUTION', 'Le plan est déjà en exécution.', 'Aucun'));
  if (plan['etat'] != ptaPlanAdopte) {
    return PtaVerdict.refus(RefusValidation('PAS_ADOPTE', 'Seul un plan adopté se met en exécution (état : ${ptaLibelleEtatPlan(plan['etat']).toLowerCase()}).', 'Faire adopter le plan'));
  }
  return PtaVerdict.ok(ecritures: [
    PtaEcriture(ptaCollectionPlans, plan['id'], {'etat': ptaPlanExecution, 'executionLe': valInstant(maintenant), 'executionPar': acteur})
  ]);
}

/// Les trois décisions RÉSERVÉES au geste « adopter » : adopter, renvoyer en brouillon, clôturer.
const String ptaDecisionAdopter = 'adopter';
const String ptaDecisionRenvoyer = 'renvoyer';
const String ptaDecisionCloturer = 'cloturer';
const List<String> ptaDecisions = [ptaDecisionAdopter, ptaDecisionRenvoyer, ptaDecisionCloturer];

/// Le contrôle UNIQUE d'une décision réservée (poste à blanc, poste mère au geste, mère à l'application d'un dépôt) et ses écritures.
///
///  * le geste réservé « adopter » de la matrice EN FORCE (rôle archivé, écran fermé : refusé) ; motif OBLIGATOIRE (il dit pourquoi, et sur quelle instance) ;
///  * ADOPTER : le plan est soumis ; celui qui l'a soumis ne l'adopte pas (signer n'est pas saisir) ; la version précédente en vigueur devient « remplacée » ;
///    les actions de la nouvelle version reprennent le SUIVI de la version remplacée (même référence) : une révision change le programme, pas les faits ;
///  * RENVOYER : le plan soumis revient en brouillon, motif à l'appui ;
///  * CLÔTURER : un plan en vigueur se clôt avec son BILAN ([synthese], calculé par l'appelant à l'instant du geste) ; plus rien ne s'y écrit ensuite.
/// La date écrite est celle du GESTE ([maintenant]) : la mère qui rejoue un dépôt passe la date du dépôt, jamais celle de l'application.
PtaVerdict ptaDecider({
  required String decision,
  required int annee,
  required int version,
  required String role,
  required String acteur,
  required String motif,
  required DroitsGestes gestes,
  required Iterable<PtaFiche> plans,
  required Iterable<PtaFiche> actions,
  required DateTime maintenant,
  PtaSynthese? synthese,
}) {
  if (!ptaDecisions.contains(decision)) return PtaVerdict.refus(RefusValidation('DECISION_INCONNUE', 'Décision inconnue : $decision.', null));
  if (!gestes.peut(role, gestePtaAdopter)) {
    return PtaVerdict.refus(RefusValidation('ADOPTION_RESERVEE',
        'Adopter, renvoyer ou clôturer le plan de travail annuel est le geste réservé « ${gesteReserve(gestePtaAdopter)!.libelle} » : le rôle « $role » ne le détient pas.',
        'Demander à un rôle qui détient le geste, ou à la Direction de l’accorder dans Rôles et permissions › Gestes réservés'));
  }
  final plan = ptaPlanVersion(plans, annee, version);
  if (plan == null) return PtaVerdict.refus(_introuvable(annee, version));
  if (motif.trim().isEmpty) {
    return PtaVerdict.refus(RefusValidation('MOTIF_OBLIGATOIRE', 'Le motif est obligatoire.',
        decision == ptaDecisionCloturer ? 'Saisir le bilan du plan' : 'Dire pourquoi, et sur quelle instance (comité de direction du …)'));
  }
  final etat = '${plan['etat']}';
  final quand = valInstant(maintenant);
  final ref = ptaReferencePlan(annee, version);
  switch (decision) {
    case ptaDecisionAdopter:
      if (const {ptaPlanAdopte, ptaPlanExecution, ptaPlanCloture}.contains(etat)) {
        return PtaVerdict.sansEffet(RefusValidation('DEJA_ADOPTE', 'Le plan $ref est déjà adopté${plan['adoptePar'] == null ? '' : ' par ${plan['adoptePar']}'} : la première adoption fait foi.', 'Aucun'));
      }
      if (etat != ptaPlanSoumis) {
        return PtaVerdict.refus(RefusValidation('PAS_SOUMIS', 'Le plan $ref n’est pas soumis à l’adoption (état : ${ptaLibelleEtatPlan(etat).toLowerCase()}).', 'Le soumettre d’abord'));
      }
      if ('${plan['soumisPar'] ?? ''}'.isNotEmpty && plan['soumisPar'] == acteur) {
        return PtaVerdict.refus(RefusValidation('AUTO_ADOPTION', 'Celui qui a soumis le plan ($acteur) ne l’adopte pas : signer n’est pas saisir.',
            'Faire adopter le plan par un autre détenteur du geste'));
      }
      final mes = ptaActionsDuPlan(actions, annee, version);
      if (mes.isEmpty) return const PtaVerdict.refus(RefusValidation('PLAN_VIDE', 'Un plan sans action ne s’adopte pas.', 'Renvoyer le plan en brouillon'));
      final ecritures = <PtaEcriture>[
        PtaEcriture(ptaCollectionPlans, plan['id'], {'etat': ptaPlanAdopte, 'adopteLe': quand, 'adoptePar': acteur, 'adopteRole': role, 'motifAdoption': motif.trim()}),
      ];
      // La version remplacée : la dernière version en vigueur avant celle-ci.
      PtaFiche? remplacee;
      for (final p in ptaPlansExercice(plans, annee)) {
        if (ptaVersionDe(p) < version && ptaEtatsPlanEnVigueur.contains(p['etat'])) remplacee = p;
      }
      if (remplacee != null) {
        final vr = ptaVersionDe(remplacee);
        ecritures.add(PtaEcriture(ptaCollectionPlans, remplacee['id'], {'etat': ptaPlanRemplace, 'remplaceLe': quand, 'remplaceParVersion': version}));
        final anciennes = {for (final a in ptaActionsDuPlan(actions, annee, vr)) '${a['reference']}': a};
        for (final a in mes) {
          final x = anciennes['${a['reference']}'];
          if (x == null) continue;
          final patch = <String, Object?>{
            for (final k in ptaChampsSuivi)
              if (jsonEncode(x[k]) != jsonEncode(a[k]) && x[k] != null) k: x[k]
          };
          if (patch.isNotEmpty) ecritures.add(PtaEcriture(ptaCollectionActions, a['id'], patch));
        }
      }
      return PtaVerdict.ok(ecritures: ecritures);
    case ptaDecisionRenvoyer:
      if (etat != ptaPlanSoumis) {
        return PtaVerdict.refus(RefusValidation('PAS_SOUMIS', 'Le plan $ref n’est pas soumis (état : ${ptaLibelleEtatPlan(etat).toLowerCase()}) : rien à renvoyer.', null));
      }
      return PtaVerdict.ok(ecritures: [
        PtaEcriture(ptaCollectionPlans, plan['id'], {'etat': ptaPlanBrouillon, 'renvoyeLe': quand, 'renvoyePar': acteur, 'motifRenvoi': motif.trim()})
      ]);
    default:
      if (etat == ptaPlanCloture) return PtaVerdict.sansEffet(RefusValidation('DEJA_CLOTURE', 'Le plan $ref est déjà clôturé.', 'Aucun'));
      if (!ptaEtatsPlanEnVigueur.contains(etat)) {
        return PtaVerdict.refus(RefusValidation('PAS_EN_VIGUEUR', 'Seul un plan adopté ou en exécution se clôture (état : ${ptaLibelleEtatPlan(etat).toLowerCase()}).', null));
      }
      return PtaVerdict.ok(ecritures: [
        PtaEcriture(ptaCollectionPlans, plan['id'], {
          'etat': ptaPlanCloture,
          'clotureLe': quand,
          'cloturePar': acteur,
          'bilan': {'texte': motif.trim(), 'arreteLe': quand, 'arretePar': acteur, ...?synthese?.versJson()},
        })
      ]);
  }
}

/// RÉVISE un plan en vigueur : une nouvelle version, en BROUILLON, qui recopie ses actions (même référence). La version en vigueur le reste jusqu'à
/// l'adoption de la révision (RG-14 : rien n'est réécrit, l'historique des versions reste). Droit d'écrire l'écran ; motif obligatoire.
({RefusValidation? refus, PtaFiche? plan, List<PtaFiche> actions}) ptaReviser({
  required int annee,
  required Iterable<PtaFiche> plans,
  required Iterable<PtaFiche> actions,
  required String acteur,
  required String motif,
  required DateTime maintenant,
}) {
  final l = ptaPlansExercice(plans, annee);
  final enVigueur = [for (final p in l) if (ptaEtatsPlanEnVigueur.contains(p['etat'])) p];
  if (enVigueur.isEmpty) {
    return (refus: RefusValidation('PAS_EN_VIGUEUR', 'Seul un plan adopté ou en exécution se révise ; un brouillon se corrige directement.', null), plan: null, actions: const []);
  }
  final derniere = l.last;
  if (derniere['etat'] == ptaPlanBrouillon || derniere['etat'] == ptaPlanSoumis) {
    return (
      refus: RefusValidation('REVISION_OUVERTE', 'La révision ${ptaReferencePlan(annee, ptaVersionDe(derniere))} est déjà ouverte (${ptaLibelleEtatPlan(derniere['etat']).toLowerCase()}).',
          'La compléter et la faire adopter'),
      plan: null,
      actions: const []
    );
  }
  if (motif.trim().isEmpty) return (refus: const RefusValidation('MOTIF_OBLIGATOIRE', 'Le motif de la révision est obligatoire.', 'Dire ce qui change et pourquoi'), plan: null, actions: const []);
  final base = enVigueur.last;
  final vb = ptaVersionDe(base);
  final v = ptaVersionDe(derniere) + 1;
  final plan = <String, Object?>{
    'id': ptaReferencePlan(annee, v),
    'statut': 'actif',
    'reference': ptaReferencePlan(annee, v),
    'exercice': annee,
    'version': v,
    'etat': ptaPlanBrouillon,
    'reviseDe': vb,
    'motifRevision': motif.trim(),
    'creeLe': valInstant(maintenant),
    'creePar': acteur,
  };
  final copies = [
    for (final a in ptaActionsDuPlan(actions, annee, vb))
      {
        for (final e in a.entries)
          if (!const {'id', 'idSync', 'statut', '_creePar', '_creeLe', '_modifiePar', '_modifieLe'}.contains(e.key)) e.key: e.value,
        'statut': 'actif',
        'planVersion': v,
      }
  ];
  return (refus: null, plan: plan, actions: copies);
}

/// Les champs du SUIVI et du CALENDRIER qu'une action RECONDUITE ne reporte PAS : l'exercice suivant repart de zéro sur les faits (état par défaut, réalisé, avancement,
/// observations) et sur les dates (celles de l'exercice écoulé ne diraient rien du suivant, et l'action paraîtrait en retard d'un an), ni la ligne de budget de l'exercice
/// écoulé (le réalisé budgétaire d'un autre exercice ne se compte pas deux fois).
const List<String> ptaChampsNonReportes = [
  'id', 'idSync', 'statut', '_creePar', '_creeLe', '_modifiePar', '_modifieLe', //
  'reference', 'exercice', 'planVersion', //
  'etat', 'realiseValeur', 'tauxAvancement', 'observations', //
  'calendrier', 'debut', 'fin', 'budgetReference',
];

/// Le résultat d'une RECONDUCTION : le refus nommé, ou le plan suivant à créer (s'il n'existe pas), les actions à copier et celles déjà reconduites.
class PtaReconduction {
  const PtaReconduction({this.refus, this.sansEffet = false, this.planACreer, this.version = 0, this.actions = const [], this.dejaReconduites = const [], this.anneeCible = 0});
  final RefusValidation? refus;

  /// Rien à copier (tout est terminé, ou déjà reconduit) : dit, jamais silencieux.
  final bool sansEffet;
  final PtaFiche? planACreer;

  /// La version du plan suivant qui reçoit les actions (1 quand il est créé par la reconduction).
  final int version;
  final List<PtaFiche> actions;

  /// Les références d'origine déjà reconduites (relancer ne double rien).
  final List<String> dejaReconduites;
  final int anneeCible;
  bool get ok => refus == null;
}

/// RECONDUIT vers l'exercice SUIVANT les actions du plan de [annee] qui ne sont NI réalisées NI abandonnées — « terminé » se lit au RÉFÉRENTIEL des états
/// ([ptaEtatTermine]), jamais à des codes écrits ici. Le sens est UNIQUE : de l'exercice écoulé vers le suivant, jamais l'inverse. Les copies vont dans le plan de l'exercice
/// suivant, en BROUILLON, créé s'il n'existe pas (version 1) ; un plan suivant déjà soumis ou adopté refuse la reconduction en le nommant (un programme figé ne reçoit pas
/// d'action). Chaque copie garde son LIEN D'ORIGINE (`reconduiteDe` : la référence de l'action, stable d'une version à l'autre ; `reconduiteDeExercice`, `reconduiteLe`,
/// `reconduitePar`) : c'est aussi ce qui évite le DOUBLON quand on relance — une action déjà reconduite, même archivée depuis, n'est pas recopiée. L'action d'origine n'est
/// JAMAIS modifiée. Les champs de [ptaChampsNonReportes] repartent de zéro (état par défaut, réalisé, dates, ligne de budget) : les dates se replanifient.
PtaReconduction ptaReconduire({
  required int annee,
  required Iterable<PtaFiche> plans,
  required Iterable<PtaFiche> actions,
  required Iterable<PtaFiche> etats,
  required String acteur,
  required DateTime maintenant,
  String? prefixe,
  String? etatExerciceSuivant,
}) {
  final cible = annee + 1;
  final source = ptaPlanCourant(plans, annee);
  if (source == null) {
    return PtaReconduction(refus: RefusValidation('PAS_DE_PLAN_SOURCE', 'L’exercice $annee n’a pas de plan : il n’y a rien à reconduire.', 'Ouvrir le plan de l’exercice $annee'));
  }
  final aReconduire = [
    for (final a in ptaActionsDuPlan(actions, annee, ptaVersionDe(source)))
      if (!ptaEtatTermine(a['etat'], etats)) a
  ];
  if (aReconduire.isEmpty) {
    return PtaReconduction(
        sansEffet: true,
        refus: RefusValidation('RIEN_A_RECONDUIRE', 'Toutes les actions du plan $annee sont réalisées ou abandonnées : rien à reconduire vers $cible.', 'Aucun'),
        anneeCible: cible);
  }
  PtaFiche? planACreer;
  var version = 1;
  final existants = ptaPlansExercice(plans, cible);
  if (existants.isEmpty) {
    if (etatExerciceSuivant == 'clos') {
      return PtaReconduction(refus: RefusValidation('EXERCICE_CLOS', 'L’exercice $cible est clos : on n’y ouvre pas de plan de travail.', 'Choisir un exercice ouvert'));
    }
    final v = ptaCreerPlan(annee: cible, plans: plans, acteur: acteur, maintenant: maintenant, etatExercice: etatExerciceSuivant);
    if (!v.ok) return PtaReconduction(refus: v.refus);
    planACreer = v.creation;
  } else {
    final dernier = existants.last;
    version = ptaVersionDe(dernier);
    if (dernier['etat'] != ptaPlanBrouillon) {
      return PtaReconduction(
          refus: RefusValidation('PLAN_SUIVANT_FIGE',
              'Le plan ${ptaReferencePlan(cible, version)} de l’exercice $cible est ${ptaLibelleEtatPlan(dernier['etat']).toLowerCase()} : une action ne s’y ajoute pas.',
              dernier['etat'] == ptaPlanSoumis ? 'Retirer la soumission, puis reconduire' : 'Réviser le plan $cible (nouvelle version en brouillon), puis reconduire'));
    }
  }
  // Les actions DÉJÀ reconduites : par leur lien d'origine, dans tout l'exercice suivant (toutes versions, archivées comprises).
  final dejaFaites = <String>{
    for (final a in actions)
      if ('${a['exercice']}' == '$cible' && '${a['reconduiteDe'] ?? ''}'.isNotEmpty) '${a['reconduiteDe']}'
  };
  final etatDefaut = ptaEtatParDefaut(etats);
  final pool = [...actions];
  final copies = <PtaFiche>[];
  final deja = <String>[];
  for (final a in aReconduire) {
    final ref = '${a['reference'] ?? ''}';
    if (ref.isNotEmpty && dejaFaites.contains(ref)) {
      deja.add(ref);
      continue;
    }
    final copie = <String, Object?>{
      for (final e in a.entries)
        if (!ptaChampsNonReportes.contains(e.key)) e.key: e.value,
      'statut': 'actif',
      'exercice': cible,
      'planVersion': version,
      'reference': ptaReferenceSuivante(cible, pool, prefixe: prefixe),
      if (etatDefaut != null) 'etat': etatDefaut,
      'reconduiteDe': ref,
      'reconduiteDeExercice': annee,
      'reconduiteLe': valInstant(maintenant),
      'reconduitePar': acteur,
    };
    pool.add(copie);
    copies.add(copie);
  }
  if (copies.isEmpty) {
    return PtaReconduction(
        sansEffet: true,
        refus: RefusValidation('DEJA_RECONDUIT', 'Les ${deja.length} action(s) non terminée(s) du plan $annee sont déjà reconduites vers $cible : rien n’est recopié deux fois.', 'Aucun'),
        dejaReconduites: deja,
        anneeCible: cible);
  }
  return PtaReconduction(planACreer: planACreer, version: version, actions: copies, dejaReconduites: deja, anneeCible: cible);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Signataires des pièces du plan : lus à l'ORGANIGRAMME
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// La clé du réglage de clinique « signataires du plan » : la liste des POSTES (intitulé ou code de l'organigramme, séparés par un point-virgule) qui signent le plan et son
/// bilan. Vide : le poste qui coiffe l'organigramme signe. Versionné par date, réglé sous le geste `pta_regler`.
const String ptaCleSignataires = 'pta.signataires';

/// Un signataire d'une pièce du plan : l'INTITULÉ du poste à l'organigramme, et son titulaire quand l'organigramme le désigne (`null` : la ligne reste sans nom, à signer à la main).
class PtaSignataire {
  const PtaSignataire(this.intitule, this.titulaire);
  final String intitule;
  final String? titulaire;
}

String _norm(Object? v) => '$v'.trim().toLowerCase();

/// Les signataires du plan et du bilan, lus à l'ORGANIGRAMME ([postes], collection `postes`) : les postes que le réglage [reglage] liste (par intitulé ou code), dans l'ordre
/// du réglage ; sans réglage, le poste qui COIFFE l'organigramme (sans rattachement). Le titulaire est celui que le poste désigne (jamais un nom écrit dans le code, jamais
/// deviné) ; un poste du réglage absent de l'organigramme garde son intitulé tel qu'écrit, sans nom. Aucun poste lisible : une ligne qui dit qu'il reste à désigner.
List<PtaSignataire> ptaSignataires({required Iterable<PtaFiche> postes, Object? reglage}) {
  final actifs = [for (final p in postes) if (p['statut'] != 'archive') p];
  PtaSignataire deposte(PtaFiche p) {
    final t = '${p['titulaire'] ?? ''}'.trim();
    return PtaSignataire('${p['poste'] ?? ''}'.trim(), t.isEmpty ? null : t);
  }

  final voulus = [for (final s in '${reglage ?? ''}'.split(';')) if (s.trim().isNotEmpty) s.trim()];
  if (voulus.isNotEmpty) {
    return [
      for (final v in voulus)
        () {
          final p = actifs.where((p) => _norm(p['poste']) == _norm(v) || _norm(p['code']) == _norm(v) || _norm(p['codeLegende']) == _norm(v)).firstOrNull;
          return p == null ? PtaSignataire(v, null) : deposte(p);
        }()
    ];
  }
  final racines = [for (final p in actifs) if ('${p['parentId'] ?? ''}'.isEmpty) p];
  if (racines.isNotEmpty) return [deposte(racines.first)];
  return const [PtaSignataire('Signataire à désigner (réglage « signataires du plan »)', null)];
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Gardes au moteur (le poste) et contrôle à la mère
// ---------------------------------------------------------------------------------------------------------------------------------------------

String _j(Object? v) => jsonEncode(v);

/// La GARDE de la collection des actions : un plan adopté ne se réécrit pas (programme figé, ni ajout ni archivage), un plan clôturé ou remplacé ne bouge plus.
/// [plans] : TOUS les en-têtes. Une action sans plan (saisie avant le PTA) n'est pas gardée.
String? ptaGardeAction(String op, PtaFiche apres, PtaFiche? avant, Iterable<PtaFiche> plans) {
  final annee = int.tryParse('${(avant ?? apres)['exercice'] ?? ''}');
  final v = ptaVersionDe(avant ?? apres);
  if (annee == null || v == 0) return null;
  final plan = ptaPlanVersion(plans, annee, v);
  if (plan == null) return null;
  final etat = '${plan['etat']}';
  final ref = ptaReferencePlan(annee, v);
  if (!ptaEtatsPlanFiges.contains(etat)) return null;
  if (etat == ptaPlanCloture || etat == ptaPlanRemplace) {
    return 'Le plan $ref est ${ptaLibelleEtatPlan(etat).toLowerCase()} : ses actions ne se modifient plus (RG-14, l’historique reste tel qu’il a été arrêté).';
  }
  if (op == 'inserer') return 'Le plan $ref est adopté : une action ne s’y ajoute pas. Réviser le plan (nouvelle version) pour changer le programme.';
  if (op == 'archiver') return 'Le plan $ref est adopté : une action ne s’en retire pas. Réviser le plan, ou passer l’action à un état « abandonnée ».';
  if (avant != null) {
    for (final k in ptaChampsProgramme) {
      if (_j(avant[k]) != _j(apres[k])) {
        return 'Le plan $ref est adopté : le programme (« $k ») ne se réécrit pas. Seul le suivi (état, réalisé, avancement, observations) reste ouvert ; réviser le plan pour changer le reste.';
      }
    }
  }
  return null;
}

/// La GARDE de la collection des en-têtes : l'état n'avance que dans le cycle (seul « soumis → brouillon » recule), un plan adopté ne s'archive pas, un plan
/// clôturé ou remplacé ne bouge plus.
String? ptaGardePlan(String op, PtaFiche apres, PtaFiche? avant) {
  if (avant == null) return null;
  final ea = '${avant['etat']}', en = '${apres['etat']}';
  if (op == 'archiver' && ptaEtatsPlanFiges.contains(ea)) {
    return 'Un plan adopté ne s’archive pas : il est l’historique de l’exercice (RG-14).';
  }
  if (op != 'modifier') return null;
  if ((ea == ptaPlanCloture || ea == ptaPlanRemplace) && en == ea) {
    for (final k in apres.keys) {
      if (k != 'statut' && k != 'idSync' && _j(avant[k]) != _j(apres[k])) return 'Le plan est ${ptaLibelleEtatPlan(ea).toLowerCase()} : il ne se modifie plus.';
    }
    return null;
  }
  if (en == ea) return null;
  final ra = ptaRangPlan(ea), rn = ptaRangPlan(en);
  if (rn == null) return 'État de plan inconnu : $en.';
  if (ra != null && rn < ra && !(ea == ptaPlanSoumis && en == ptaPlanBrouillon)) {
    return 'Le plan ne revient pas en arrière : il est « ${ptaLibelleEtatPlan(ea)} », il ne repasse pas « ${ptaLibelleEtatPlan(en)} ».';
  }
  return null;
}

/// Le contrôle que la MÈRE refait sur chaque écriture d'un poste (hors mère) dans `plansTravail` : un poste ne crée qu'un brouillon ou un plan soumis, n'écrit
/// jamais un état réservé (adopté, clôturé, remplacé) ni un champ réservé (il les DÉPOSE), ne fait pas reculer un plan (sauf retirer sa soumission), et ne met
/// en exécution qu'un plan que la mère détient adopté. `null` : recevable. Miroir à l'identique dans `packages/sync/banc/mere.js`.
({String code, String motif, String geste})? refusPlanTravail(String type, Map<String, Object?> champs, {Object? etatActuel}) {
  for (final k in ptaChampsPlanReserves) {
    if (champs.containsKey(k)) {
      return (code: 'champ_reserve', motif: 'Le champ « $k » d’un plan de travail n’est écrit que par la décision réservée, appliquée par la mère.', geste: 'Déposer la décision depuis l’écran du plan');
    }
  }
  final nouveau = champs['etat'];
  if (type == 'creer') {
    if (nouveau == null || nouveau == ptaPlanBrouillon || nouveau == ptaPlanSoumis) return null;
    return (code: 'adoption_requise', motif: 'Un poste ne crée pas un plan déjà « ${ptaLibelleEtatPlan(nouveau)} » : l’adoption ne s’écrit que par le dépôt du détenteur du geste, appliqué par la mère.', geste: 'Créer le plan en brouillon, puis le soumettre');
  }
  if (nouveau == null || '$nouveau' == '$etatActuel') return null;
  final rn = ptaRangPlan(nouveau), ra = ptaRangPlan(etatActuel);
  if (rn == null) return (code: 'etat_inconnu', motif: 'État de plan inconnu : $nouveau.', geste: 'Choisir un état du cycle');
  if (ptaEtatsPlanReserves.contains('$nouveau')) {
    return (code: 'adoption_reservee', motif: 'L’état « ${ptaLibelleEtatPlan(nouveau)} » est le fait du détenteur du geste : il se DÉPOSE depuis son poste et la mère l’applique sous son rôle.', geste: 'Déposer la décision depuis l’écran du plan');
  }
  if (ra != null && rn < ra && !('$etatActuel' == ptaPlanSoumis && nouveau == ptaPlanBrouillon)) {
    return (code: 'etat_regressif', motif: 'Le plan ne revient jamais en arrière : il est « ${ptaLibelleEtatPlan(etatActuel)} », il ne repasse pas « ${ptaLibelleEtatPlan(nouveau)} ».', geste: 'Réviser le plan (nouvelle version)');
  }
  if (nouveau == ptaPlanExecution && '$etatActuel' != ptaPlanAdopte) {
    return (code: 'adoption_requise', motif: 'Mettre en exécution suppose l’adoption, que la mère ne détient pas (état actuel : « ${ptaLibelleEtatPlan(etatActuel)} »).', geste: 'Attendre la confirmation de la mère, puis reprendre');
  }
  return null;
}

/// Le contrôle que la MÈRE refait sur une écriture d'un poste dans `planAnnuel` : le programme d'une action d'un plan figé ne se réécrit pas (le suivi, si), et
/// rien ne s'écrit dans un plan clôturé ou remplacé. [plan] : l'en-tête que la mère détient pour (exercice, version) de l'action. `null` : recevable.
({String code, String motif, String geste})? refusActionPta(String type, Map<String, Object?> champs, {Map<String, Object?>? actuelle, Map<String, Object?>? plan}) {
  if (plan == null) return null;
  final etat = '${plan['etat']}';
  if (!ptaEtatsPlanFiges.contains(etat)) return null;
  if (etat == ptaPlanCloture || etat == ptaPlanRemplace) {
    return (code: 'plan_arrete', motif: 'Le plan est ${ptaLibelleEtatPlan(etat).toLowerCase()} : ses actions ne se modifient plus.', geste: 'Aucun : l’historique reste tel qu’il a été arrêté');
  }
  if (type == 'creer') return (code: 'plan_adopte', motif: 'Le plan est adopté : une action ne s’y ajoute pas.', geste: 'Réviser le plan (nouvelle version)');
  for (final k in ptaChampsProgramme) {
    if (champs.containsKey(k) && (actuelle == null || _j(actuelle[k]) != _j(champs[k]))) {
      return (code: 'plan_adopte', motif: 'Le plan est adopté : le programme (« $k ») ne se réécrit pas, seul le suivi reste ouvert.', geste: 'Réviser le plan (nouvelle version)');
    }
  }
  return null;
}

/// FUSION d'un en-tête que deux postes ont modifié : une décision réservée que le journal porte (adoption, clôture, remplacement) n'est jamais défaite par une
/// fusion tardive, et un état réservé que le journal NE porte PAS n'a pas pu naître légitimement sur un fileul (il ne naît que du dépôt appliqué par la mère) :
/// la version du journal l'emporte. [refusLocal] : la mère a refusé l'écriture locale. Le retrait d'une soumission (soumis → brouillon), lui, se garde.
Map<String, Object?> fusionnerPlanTravail(Map<String, Object?> fusion, Map<String, Object?> local, Map<String, Object?> recu, {bool refusLocal = false, bool posteFileul = false}) {
  final el = local['etat'], er = recu['etat'];
  if (er == null || '$el' == '$er') return fusion;
  final rl = ptaRangPlan(el), rr = ptaRangPlan(er);
  if (rr == null) return fusion;
  final inventeIci = posteFileul && ptaEtatsPlanReserves.contains('$el');
  final gagneRecu = refusLocal || inventeIci || (rr >= (ptaRangPlan(ptaPlanAdopte) ?? 2) && (rl == null || rr > rl));
  if (!gagneRecu) return fusion;
  fusion['etat'] = er;
  for (final k in ptaChampsPlanReserves) {
    if (recu.containsKey(k)) {
      fusion[k] = recu[k];
    } else if (inventeIci || refusLocal) {
      fusion.remove(k);
    }
  }
  return fusion;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Dépôt d'une décision depuis un fileul, application par la mère
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le genre de dépôt des décisions du PTA (à côté de `referentiel`, `circuit_achat`, `reglage_clinique`).
const String valGenrePta = 'pta_plan';

/// La famille d'un dépôt du PTA : `pta_<décision>`.
String ptaFamilleDepot(String decision) => 'pta_$decision';

/// DÉPOSE une décision réservée depuis un poste rattaché (qui n'écrit pas l'adoption). Les contrôles sont ceux de l'application, à blanc : un refus se NOMME dès le
/// poste. Un dépôt identique (même plan, même décision) qui attend déjà la mère n'est pas doublé.
VerdictDepot ptaDeposer({
  required String decision,
  required int annee,
  required int version,
  required String role,
  required String acteur,
  required String poste,
  required String motif,
  required DateTime maintenant,
  required DroitsGestes gestes,
  required Iterable<PtaFiche> plans,
  required Iterable<PtaFiche> actions,
  required List<PtaFiche> depots,
  required String Function() nouvelId,
}) {
  final essai = ptaDecider(
      decision: decision, annee: annee, version: version, role: role, acteur: acteur, motif: motif, gestes: gestes, plans: plans, actions: actions, maintenant: maintenant);
  if (essai.refus != null) {
    return VerdictDepot.refus(essai.sansEffet ? RefusValidation('DEJA_FAIT', essai.refus!.motif, 'Aucun') : essai.refus!);
  }
  final cible = ptaClePlan(annee, version);
  for (final d in depots) {
    if (d['statut'] != 'archive' && d['etat'] == valDepotDeposee && d['genre'] == valGenrePta && d['cible'] == cible && d['decision'] == decision) {
      return VerdictDepot.ok(d, dejaDepose: true);
    }
  }
  final quoi = switch (decision) { ptaDecisionAdopter => 'adoption', ptaDecisionRenvoyer => 'renvoi en brouillon', _ => 'clôture' };
  return VerdictDepot.ok({
    'id': nouvelId(),
    'statut': 'actif',
    'genre': valGenrePta,
    'famille': ptaFamilleDepot(decision),
    'cible': cible,
    'decision': decision,
    'exercice': annee,
    'version': version,
    'libelle': 'Plan de travail annuel ${ptaReferencePlan(annee, version)} — $quoi',
    'etat': valDepotDeposee,
    'demandeRole': role,
    'demandePar': acteur,
    'demandePoste': poste,
    'demandeLe': valInstant(maintenant),
    'motif': motif.trim(),
  });
}

/// Ce que la mère décide d'un dépôt du PTA : l'état du dépôt, le refus éventuel, les écritures du plan.
class ApplicationPta {
  const ApplicationPta({required this.etat, this.code, this.motif, this.geste, this.ecritures = const []});
  final String etat;
  final String? code;
  final String? motif;
  final String? geste;
  final List<PtaEcriture> ecritures;
}

/// APPLIQUE un dépôt sur la mère, sous le RÔLE et le NOM de son auteur, tous les contrôles refaits avec SA matrice et SES fiches, à la date du GESTE. `null` :
/// rien à faire (autre genre, déjà traité). [synthese] : le bilan d'une clôture, calculé par la mère sur ses données.
ApplicationPta? ptaAppliquerDepot(
  PtaFiche depot, {
  required DroitsGestes gestes,
  required Iterable<PtaFiche> plans,
  required Iterable<PtaFiche> actions,
  required DateTime maintenant,
  PtaSynthese Function(int annee, int version)? synthese,
}) {
  if (depot['genre'] != valGenrePta || depot['etat'] != valDepotDeposee || depot['statut'] == 'archive') return null;
  final annee = int.tryParse('${depot['exercice']}'), version = int.tryParse('${depot['version']}');
  if (annee == null || version == null) {
    return const ApplicationPta(etat: valDepotRefusee, code: 'CIBLE_ILLISIBLE', motif: 'Le dépôt ne désigne pas de plan lisible.', geste: 'Refaire le geste depuis l’écran du plan');
  }
  final quand = DateTime.tryParse('${depot['demandeLe'] ?? ''}') ?? maintenant;
  final decision = '${depot['decision']}';
  final v = ptaDecider(
      decision: decision,
      annee: annee,
      version: version,
      role: '${depot['demandeRole'] ?? ''}',
      acteur: '${depot['demandePar'] ?? ''}',
      motif: '${depot['motif'] ?? ''}',
      gestes: gestes,
      plans: plans,
      actions: actions,
      maintenant: quand,
      synthese: decision == ptaDecisionCloturer ? synthese?.call(annee, version) : null);
  if (v.ok) return ApplicationPta(etat: valDepotAppliquee, ecritures: v.ecritures);
  final r = v.refus!;
  return ApplicationPta(etat: v.sansEffet ? valDepotSansEffet : valDepotRefusee, code: r.code, motif: r.motif, geste: r.geste);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Alertes de retard
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Une action en retard d'un plan en vigueur.
class PtaRetard {
  const PtaRetard(this.action, this.jours, this.annee);
  final PtaFiche action;
  final int jours;
  final int annee;
}

/// Les actions EN RETARD de tous les plans EN VIGUEUR (adoptés ou en exécution), une par action (jamais de doublon : l'action est la clé). [seuil] : le seuil en
/// vigueur pour l'exercice (lu par l'appelant aux paramètres de clinique, à la date de réglage de l'exercice).
List<PtaRetard> ptaActionsEnRetard({
  required Iterable<PtaFiche> plans,
  required Iterable<PtaFiche> actions,
  required Iterable<PtaFiche> etats,
  required DateTime auj,
  required int Function(int annee) seuil,
}) {
  final out = <PtaRetard>[];
  final annees = {for (final p in plans) if (p['statut'] != 'archive') int.tryParse('${p['exercice']}')}.whereType<int>().toList()..sort();
  for (final annee in annees) {
    final vigueur = [for (final p in ptaPlansExercice(plans, annee)) if (ptaEtatsPlanEnVigueur.contains(p['etat'])) p];
    if (vigueur.isEmpty) continue;
    final v = ptaVersionDe(vigueur.last);
    final s = seuil(annee);
    for (final a in ptaActionsDuPlan(actions, annee, v)) {
      final j = ptaJoursRetard(a, etats, auj, s);
      if (j != null) out.add(PtaRetard(a, j, annee));
    }
  }
  return out;
}
