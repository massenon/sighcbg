// LA VALIDATION DÉPOSÉE PAR UN FILEUL, APPLIQUÉE PAR LA MÈRE (Direction de Baguidi, 15/11/2026 : « une validation à faire ne doit JAMAIS empêcher le fileul de travailler »).
//
// Le poste mère « porte la clinique » : personne n'a à s'asseoir devant lui pour valider. Un VALIDATEUR (celui que la matrice autorise : la famille du référentiel)
// valide donc DEPUIS N'IMPORTE QUEL POSTE. Sur un fileul, la configuration est tenue par la mère (famille R) : le geste ne s'écrit pas, il se DÉPOSE comme une
// décision (collection `validationsDeposees`, famille A, une fiche par geste), et la mère l'APPLIQUE MÉCANIQUEMENT sous le rôle et le nom de l'auteur en refaisant
// TOUS les contrôles — ceux de [valValiderReferentiel], sans en réécrire un seul. C'est le modèle des demandes de prix (`ApplicateurDemandesTarif`) et des décisions de
// droits (`ServiceDroits`) ; ce fichier en est la FABRIQUE COMMUNE pour la validation d'un référentiel : un seul mécanisme, pas un par circuit.
//
// Quatre garanties :
//  * le poste qui a créé l'élément n'est jamais bloqué : il continue de travailler, l'élément reste « à valider » ;
//  * tant que la mère n'a pas confirmé, l'état dit « transmise à la mère, en attente » — JAMAIS « validé » ;
//  * le dépôt est REJOUABLE sans effet double : un geste déjà déposé n'est pas déposé deux fois, et un geste appliqué deux fois n'écrit qu'une validation
//    (l'élément déjà validé rend `sans_effet`, nommé, jamais une seconde trace) ;
//  * le verdict (`appliquee`, `sans_effet`, `refusee` avec code, motif, geste) est écrit par la mère sur la MÊME fiche, qui revient au fileul par le pont d'activité.
//
// Fonctions PURES : le poste y branche ses collections, son journal et son transport.

import 'validation.dart';

/// La collection des validations déposées (famille A : le fileul dépose, la mère complète du verdict ; jamais vers un téléphone).
const String valCollectionDepots = 'validationsDeposees';

/// Le seul genre de dépôt aujourd'hui : la validation d'un élément d'un référentiel (les quinze familles de [valFamilles]).
const String valGenreReferentiel = 'referentiel';

/// Les états d'un dépôt. `deposee` : en attente de la mère. Les trois autres sont des verdicts, écrits par la mère seule.
const String valDepotDeposee = 'deposee';
const String valDepotAppliquee = 'appliquee';
const String valDepotSansEffet = 'sans_effet';
const String valDepotRefusee = 'refusee';

/// Les champs que SEULE la mère écrit sur un dépôt (le verdict).
const List<String> valChampsVerdictDepot = ['etat', 'resultatCode', 'resultatMotif', 'resultatGeste', 'traiteLe', 'traitePar'];

/// Ce que le dépôt rend : un refus nommé (rien n'est déposé), ou la fiche à écrire. [dejaDepose] : un dépôt identique attend déjà la mère, il n'y en a pas de second.
class VerdictDepot {
  const VerdictDepot.refus(RefusValidation r)
      : refus = r,
        fiche = null,
        dejaDepose = false;
  const VerdictDepot.ok(Map<String, Object?> this.fiche, {this.dejaDepose = false}) : refus = null;
  final RefusValidation? refus;
  final Map<String, Object?>? fiche;
  final bool dejaDepose;
  bool get ok => refus == null;
}

/// DÉPOSE la validation d'un élément depuis un poste qui ne peut pas l'écrire (un fileul rattaché). Les contrôles sont ceux du geste lui-même, à l'identique :
/// famille connue, rôle de la session dans la famille, élément connu, élément en attente. [depots] : les dépôts déjà présents (le poste les lit au magasin).
VerdictDepot valDeposer(
  String familleId,
  String id, {
  required String role,
  required String acteur,
  required String poste,
  required DateTime maintenant,
  required LectureValidation lire,
  required Map<String, String> libelles,
  required List<Map<String, Object?>> depots,
  required String Function() nouvelId,
  String? motif,
}) {
  // Le contrôle à blanc : le geste réel, rejoué comme s'il s'écrivait ici. Un refus se NOMME dès le poste, avant tout dépôt.
  final essai = valValiderReferentiel(familleId, id, role: role, acteur: acteur, maintenant: maintenant, lire: lire, libelles: libelles, motif: motif);
  if (!essai.ok) return VerdictDepot.refus(essai.refus!);
  // Rejouable : un dépôt de la même famille, du même élément, par le même rôle, qui attend encore la mère, n'est pas doublé.
  for (final d in depots) {
    if (d['statut'] != 'archive' && d['etat'] == valDepotDeposee && d['genre'] == valGenreReferentiel && d['famille'] == familleId && d['cible'] == id && d['demandeRole'] == role) {
      return VerdictDepot.ok(d, dejaDepose: true);
    }
  }
  final f = valFamille(familleId)!;
  return VerdictDepot.ok({
    'id': nouvelId(),
    'statut': 'actif',
    'genre': valGenreReferentiel,
    'famille': familleId,
    'cible': id,
    'libelle': f.libelle,
    'etat': valDepotDeposee,
    'demandeRole': role,
    'demandePar': acteur,
    'demandePoste': poste,
    'demandeLe': valInstant(maintenant),
    if (motif != null && motif.trim().isNotEmpty) 'motif': motif.trim(),
  });
}

/// Ce que la mère décide d'un dépôt : le verdict à écrire sur la fiche, et, quand la validation s'applique, ce qu'il faut ÉCRIRE (le même verdict que le geste direct).
class ApplicationDepot {
  const ApplicationDepot({required this.etat, this.code, this.motif, this.geste, this.validation});
  final String etat;
  final String? code;
  final String? motif;
  final String? geste;

  /// Non nul seulement quand [etat] vaut `appliquee` : la collection, le patch ou la fiche à créer, la ligne de journal.
  final VerdictValidation? validation;
}

/// APPLIQUE un dépôt sur la mère : refait TOUS les contrôles sous le RÔLE et le NOM de l'auteur du dépôt, avec les données de la mère. La date de la validation est celle du
/// GESTE de l'auteur (`demandeLe`), pas celle de l'application : la mère peut avoir été éteinte entre-temps, la validation ne doit pas être antidatée ni postdatée.
/// Un dépôt déjà traité n'est pas rejoué (`null` : rien à faire) ; un élément déjà validé rend `sans_effet`, nommé.
ApplicationDepot? valAppliquerDepot(
  Map<String, Object?> depot, {
  required LectureValidation lire,
  required Map<String, String> libelles,
  required DateTime maintenant,
}) {
  if (depot['etat'] != valDepotDeposee || depot['statut'] == 'archive') return null;
  if (depot['genre'] != valGenreReferentiel) {
    return const ApplicationDepot(
        etat: valDepotRefusee,
        code: 'GENRE_INCONNU',
        motif: 'Dépôt de validation d’un genre inconnu de la mère.',
        geste: 'Refaire le geste depuis l’écran du référentiel.');
  }
  final quand = DateTime.tryParse('${depot['demandeLe'] ?? ''}') ?? maintenant;
  final motif = depot['motif'] as String?;
  final v = valValiderReferentiel('${depot['famille']}', '${depot['cible']}',
      role: '${depot['demandeRole']}', acteur: '${depot['demandePar']}', maintenant: quand, lire: lire, libelles: libelles, fileul: false, motif: motif);
  if (v.ok) return ApplicationDepot(etat: valDepotAppliquee, validation: v);
  final r = v.refus!;
  if (r.code == 'DEJA_VALIDE') return ApplicationDepot(etat: valDepotSansEffet, code: r.code, motif: r.motif, geste: r.geste);
  return ApplicationDepot(etat: valDepotRefusee, code: r.code, motif: r.motif, geste: r.geste);
}

/// L'état d'attente d'un élément au poste qui l'a validé : le dernier dépôt, s'il n'est pas résolu par une validation visible. `null` : aucun dépôt à dire.
class EtatDepot {
  const EtatDepot({required this.etat, required this.depotId, required this.par, required this.le, this.code, this.motif, this.geste});
  final String etat;
  final String depotId;
  final String par;
  final String le;
  final String? code;
  final String? motif;
  final String? geste;
  bool get enAttente => etat == valDepotDeposee;
  bool get refuse => etat == valDepotRefusee;
}

/// Le dernier dépôt pour un élément. Un dépôt `appliquee` ou `sans_effet` ne dit plus rien : l'élément porte alors SA validation (l'état lu, jamais stocké).
EtatDepot? valEtatDepot(String familleId, String id, List<Map<String, Object?>> depots) {
  Map<String, Object?>? dernier;
  for (final d in depots) {
    if (d['statut'] == 'archive' || d['genre'] != valGenreReferentiel || d['famille'] != familleId || d['cible'] != id) continue;
    if (dernier == null || '${d['demandeLe']}'.compareTo('${dernier['demandeLe']}') >= 0) dernier = d;
  }
  if (dernier == null) return null;
  final etat = '${dernier['etat']}';
  if (etat != valDepotDeposee && etat != valDepotRefusee) return null;
  return EtatDepot(
      etat: etat,
      depotId: '${dernier['id']}',
      par: '${dernier['demandePar']}',
      le: '${dernier['demandeLe']}',
      code: dernier['resultatCode'] as String?,
      motif: dernier['resultatMotif'] as String?,
      geste: dernier['resultatGeste'] as String?);
}
