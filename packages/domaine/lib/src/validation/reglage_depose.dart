// UN RÉGLAGE DE CLINIQUE POSÉ SOUS UN GESTE RÉSERVÉ, DEPUIS N'IMPORTE QUEL POSTE (Direction de Baguidi, 16/11/2026, complément §7 : « réglé par le rôle qui a le droit, sur
// N'IMPORTE QUEL poste, propagé par la synchronisation »).
//
// Un paramètre de clinique vit dans la collection `parametres` (famille R : la mère seule écrit, chaque version datée). Certains réglages ne relèvent pas du droit d'éditer l'écran des
// paramètres mais d'un GESTE RÉSERVÉ de la fiche de rôle ([reglagesSousGeste]). Sur la mère, le geste écrit la version ; sur un poste rattaché, il ne s'écrit pas : il se DÉPOSE dans
// `validationsDeposees` (genre [valGenreReglage]) — le mécanisme de la continuité des validations, pas un second —, et la mère l'APPLIQUE sous le rôle et le nom de son auteur, en
// refaisant TOUS les contrôles avec SA matrice (geste en force, rôle archivé, activité fermée) et SES versions (valeur, date, usage par une pièce). La version écrite revient au
// fileul par le journal. Rejouable : un réglage déjà à la valeur voulue à cette date rend `sans_effet`, nommé, sans seconde version.
//
// Fonctions PURES : le poste y branche ses collections, sa matrice et son journal.
library;

import '../administration/pta.dart' show ptaCleDecoupage, ptaClePrefixe, ptaCleSeuilRetard, ptaCleSignataires;
import '../droits/gestes_reserves.dart';
import '../parametres/definitions.dart';
import '../parametres/parametres.dart';
import 'validation.dart' show RefusValidation, valInstant;
import 'validation_deposee.dart';

/// Le genre de dépôt d'un réglage de clinique (à côté de `referentiel` et `circuit_achat`).
const String valGenreReglage = 'reglage_clinique';

/// Les réglages qui se posent sous un GESTE RÉSERVÉ (clé du paramètre → geste). Une donnée : ajouter un réglage ici suffit à le rendre déposable depuis un fileul.
const Map<String, String> reglagesSousGeste = {
  cleEncaisserResteSansPrix: gesteReglageEncaissementSansPrix,
  // Le plan de travail annuel (lot PTA, 17/11/2026) : découpage, seuil de retard et préfixe de numérotation.
  ptaCleDecoupage: gestePtaRegler,
  ptaCleSeuilRetard: gestePtaRegler,
  ptaClePrefixe: gestePtaRegler,
  ptaCleSignataires: gestePtaRegler,
};

/// Le geste réservé qui pose ce réglage (`null` : le réglage suit le droit d'éditer l'écran des paramètres, sur la mère).
String? gesteDuReglage(String cle) => reglagesSousGeste[cle];

/// Le contrôle UNIQUE (poste à blanc, mère à l'application) : `refus`, ou la version à écrire ; `sansEffet` quand la valeur voulue est DÉJÀ en vigueur à cette date.
({RefusValidation? refus, bool sansEffet, Parametre? version}) reglageControler({
  required String cle,
  required Object? valeur,
  required String dateEffet,
  required String role,
  required String acteur,
  required DroitsGestes gestes,
  required List<Parametre> versions,
  required List<Map<String, Object?>> usages,
  required DateTime maintenant,
  String? motif,
}) {
  final geste = gesteDuReglage(cle);
  final def = definitionDeParametre(cle);
  if (geste == null || def == null) {
    return (refus: RefusValidation('REGLAGE_INCONNU', 'Le réglage « $cle » ne se pose pas sous un geste réservé.', 'Le régler depuis les Paramètres de la mère'), sansEffet: false, version: null);
  }
  if (!gestes.peut(role, geste)) {
    final g = gesteReserve(geste);
    return (
      refus: RefusValidation('REGLAGE_RESERVE', '« ${def.libelle} » se règle sous le geste réservé « ${g?.libelle ?? geste} » : le rôle « $role » ne le détient pas.',
          'Demander à un rôle qui détient le geste, ou à la Direction de l’accorder dans Rôles et permissions › Gestes réservés'),
      sansEffet: false,
      version: null
    );
  }
  final enVigueur = Parametres.resoudre(cle, versions.where((v) => v.cle == cle).toList(), dateEffet, definition: def);
  if (enVigueur.ok && enVigueur.valeur!.valeur == valeur && Parametres.valeurValide(def.type, valeur, def.choix)) {
    // Déjà la valeur voulue à cette date, et aucune version ultérieure ne la contredit : rien à écrire.
    final apres = versions.where((v) => v.cle == cle && v.dateEffet != null && v.dateEffet!.compareTo(dateEffet) > 0 && v.valeur != valeur);
    if (apres.isEmpty) return (refus: null, sansEffet: true, version: null);
  }
  final r = Parametres.proposer(
    definition: def,
    versions: versions.where((v) => v.cle == cle).toList(),
    usages: usages.where((u) => u['cle'] == cle).toList(),
    valeur: valeur,
    dateEffet: dateEffet,
    auteur: acteur,
    creeLe: maintenant.toUtc().toIso8601String(),
    motif: (motif == null || motif.trim().isEmpty) ? null : motif.trim(),
  );
  if (!r.ok) return (refus: RefusValidation(r.refus!.code, r.refus!.motif, r.refus!.geste), sansEffet: false, version: null);
  return (refus: null, sansEffet: false, version: r.valeur);
}

/// DÉPOSE un réglage depuis un poste rattaché (qui n'écrit pas `parametres`). Les contrôles sont ceux de l'application, à blanc : un refus se NOMME dès le poste. Un dépôt identique
/// (même clé, même valeur, même date) qui attend déjà la mère n'est pas doublé.
VerdictDepot reglageDeposer({
  required String cle,
  required Object? valeur,
  required String dateEffet,
  required String role,
  required String acteur,
  required String poste,
  required DateTime maintenant,
  required DroitsGestes gestes,
  required List<Parametre> versions,
  required List<Map<String, Object?>> usages,
  required List<Map<String, Object?>> depots,
  required String Function() nouvelId,
  String? motif,
}) {
  final c = reglageControler(
      cle: cle, valeur: valeur, dateEffet: dateEffet, role: role, acteur: acteur, gestes: gestes, versions: versions, usages: usages, maintenant: maintenant, motif: motif);
  if (c.refus != null) return VerdictDepot.refus(c.refus!);
  if (c.sansEffet) {
    return VerdictDepot.refus(const RefusValidation('DEJA_REGLE', 'Le réglage a déjà cette valeur à cette date : rien n’est transmis.', 'Aucun'));
  }
  for (final d in depots) {
    if (d['statut'] != 'archive' && d['etat'] == valDepotDeposee && d['genre'] == valGenreReglage && d['cible'] == cle && d['valeur'] == valeur && d['dateEffet'] == dateEffet) {
      return VerdictDepot.ok(d, dejaDepose: true);
    }
  }
  final def = definitionDeParametre(cle)!;
  return VerdictDepot.ok({
    'id': nouvelId(),
    'statut': 'actif',
    'genre': valGenreReglage,
    // La « famille » d'un dépôt de réglage est sa CLÉ : c'est elle qui dit quel geste le valide (alerte de décision en retard, `destinatairesAlerteDecision`).
    'famille': cle,
    'familleParametre': def.famille,
    'cible': cle,
    'valeur': valeur,
    'dateEffet': dateEffet,
    'libelle': 'Réglage « ${def.libelle} »',
    'etat': valDepotDeposee,
    'demandeRole': role,
    'demandePar': acteur,
    'demandePoste': poste,
    'demandeLe': valInstant(maintenant),
    if (motif != null && motif.trim().isNotEmpty) 'motif': motif.trim(),
  });
}

/// Le verdict d'un dépôt de réglage appliqué par la mère : l'état à écrire sur le dépôt, le refus éventuel, la version à écrire dans `parametres`.
class ApplicationReglage {
  const ApplicationReglage({required this.etat, this.code, this.motif, this.geste, this.version});
  final String etat;
  final String? code;
  final String? motif;
  final String? geste;
  final Parametre? version;
}

/// APPLIQUE un dépôt de réglage sur la mère, sous le RÔLE et le NOM de son auteur, tous les contrôles refaits avec les données de la mère. `null` : rien à faire (déjà traité, autre
/// genre). [gestes] : la MATRICE en force de la mère, jamais une liste de rôles.
ApplicationReglage? reglageAppliquer(
  Map<String, Object?> depot, {
  required DroitsGestes gestes,
  required List<Parametre> versions,
  required List<Map<String, Object?>> usages,
  required DateTime maintenant,
}) {
  if (depot['genre'] != valGenreReglage || depot['etat'] != valDepotDeposee || depot['statut'] == 'archive') return null;
  final c = reglageControler(
      cle: '${depot['cible']}',
      valeur: depot['valeur'],
      dateEffet: '${depot['dateEffet']}',
      role: '${depot['demandeRole'] ?? ''}',
      acteur: '${depot['demandePar'] ?? ''}',
      gestes: gestes,
      versions: versions,
      usages: usages,
      maintenant: maintenant,
      motif: [if ('${depot['motif'] ?? ''}'.trim().isNotEmpty) '${depot['motif']}'.trim(), 'déposé depuis le poste ${depot['demandePoste'] ?? '—'}'].join(' — '));
  if (c.refus != null) return ApplicationReglage(etat: valDepotRefusee, code: c.refus!.code, motif: c.refus!.motif, geste: c.refus!.geste);
  if (c.sansEffet) {
    return const ApplicationReglage(etat: valDepotSansEffet, code: 'DEJA_REGLE', motif: 'Le réglage avait déjà cette valeur à cette date : aucune version n’est écrite une seconde fois.');
  }
  return ApplicationReglage(etat: valDepotAppliquee, version: c.version);
}
