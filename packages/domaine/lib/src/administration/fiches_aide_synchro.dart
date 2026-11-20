// LA VALIDATION D'UNE FICHE D'AIDE DEPUIS UN POSTE RATTACHÉ (Direction de Baguidi, 18/11/2026, point 3 : « un fileul rédige mais ne valide pas » ne tient plus).
//
// Même circuit que les autres validations (`validationsDeposees`, famille A, une fiche par geste), nouveau genre [valGenreFicheAideValider] : le fileul DÉPOSE la demande de validation — le
// validateur est l'AGENT CONNECTÉ, avec son compte — et la MÈRE l'applique en REFAISANT tous les contrôles de [validerFicheAide], sous le rôle et le nom du déposant, avec SES données :
//  * le compte signataire est vérifié par la mère avant tout rejeu (existe, porte ce rôle, n'est pas archivé : contrôle commun à tous les genres, `verifierCompteSignataire`) ;
//  * le geste réservé `fiches_aide_valider` est relu dans la MATRICE de la mère ; la check-liste du bloc exige en plus le geste du professionnel (`valider_ref_bloc`), son nom et la date ;
//  * l'auteur de la fiche (celle que la mère connaît) n'est pas le validateur ;
//  * la fiche n'est ni archivée ni déjà validée (`sans_effet`, nommé, jamais une seconde trace).
// Le verdict nommé (`appliquee`, `sans_effet`, `refusee` avec code, motif et geste) est écrit par la mère sur la MÊME fiche de dépôt et revient au fileul par le pont ; la fiche d'aide porte alors
// la validation. Mère injoignable : le dépôt attend (état `deposee`), rien ne se perd, rien n'est « validé » avant la confirmation.
//
// Aucun nouveau geste réservé : c'est `fiches_aide_valider` (et `valider_ref_bloc`) qui décide, lu dans la matrice — jamais un nom de rôle écrit ici.
//
// Fonctions PURES : le poste y branche ses collections, son journal et son transport.

import 'dart:convert';

import '../droits/gestes_reserves.dart';
import '../validation/validation.dart' show RefusValidation, valInstant;
import '../validation/validation_deposee.dart';
import 'fiches_aide.dart';

/// Le genre de dépôt : la validation d'UNE fiche d'aide par un poste rattaché.
const String valGenreFicheAideValider = 'fiche_aide_valider';

/// Le libellé affiché d'un dépôt de validation de fiche d'aide.
String ficheAideLibelleDepot(Map<String, Object?>? fiche, Object? cible) {
  final t = '${fiche?['titre'] ?? ''}'.trim();
  return 'Validation de la fiche d’aide « ${t.isEmpty ? cible : t} »';
}

/// L'EMPREINTE du contenu qu'un validateur a relu : le contenu normalisé de la fiche, sérialisé. La demande la porte ; la mère refuse de valider une fiche dont le contenu a changé depuis (`FICHE_MODIFIEE`) :
/// on valide ce qu'on a lu, pas ce que l'auteur a réécrit entre-temps.
String ficheAideEmpreinteContenu(Map<String, Object?> fiche) => jsonEncode(contenuFicheAide(fiche));

/// DÉPOSE la demande de validation d'une fiche d'aide depuis un poste rattaché. Le contrôle est celui du geste direct, REFAIT À BLANC ici ([validerFicheAide] avec les données de ce poste) : un refus
/// se nomme dès le poste, rien n'est déposé. [ficheId] : la clé de synchronisation de la fiche (celle que la mère connaît). Un dépôt identique qui attend déjà la mère n'est pas doublé.
VerdictDepot ficheAideValiderDeposer({
  required String ficheId,
  required Map<String, Object?>? fiche,
  required String role,
  required String validateurId,
  required String validateurNom,
  required String poste,
  required DateTime maintenant,
  required DroitsGestes gestes,
  required Iterable<String> rolesConnus,
  required List<Map<String, Object?>> depots,
  required String Function() nouvelId,
  String? professionnel,
  String? professionnelLe,
}) {
  final essai = validerFicheAide(
      fiche: fiche,
      role: role,
      validateurId: validateurId,
      validateurNom: validateurNom,
      maintenant: maintenant,
      gestes: gestes,
      rolesConnus: rolesConnus,
      professionnel: professionnel,
      professionnelLe: professionnelLe);
  if (!essai.accepte) return VerdictDepot.refus(RefusValidation(essai.refus!.code, essai.refus!.motif, essai.refus!.geste));
  for (final d in depots) {
    if (d['statut'] != 'archive' && d['etat'] == valDepotDeposee && d['genre'] == valGenreFicheAideValider && d['cible'] == ficheId && d['validateurId'] == validateurId) {
      return VerdictDepot.ok(d, dejaDepose: true);
    }
  }
  return VerdictDepot.ok({
    'id': nouvelId(),
    'statut': 'actif',
    'genre': valGenreFicheAideValider,
    'famille': colFichesAide,
    'cible': ficheId,
    'libelle': ficheAideLibelleDepot(fiche, ficheId),
    'contenuVu': ficheAideEmpreinteContenu(fiche!),
    'etat': valDepotDeposee,
    'validateurId': validateurId,
    'demandeRole': role,
    'demandePar': validateurNom.trim(),
    'demandePoste': poste,
    'demandeLe': valInstant(maintenant),
    if ((professionnel ?? '').trim().isNotEmpty) 'professionnel': professionnel!.trim(),
    if ((professionnelLe ?? '').trim().isNotEmpty) 'professionnelLe': professionnelLe!.trim(),
  });
}

/// Ce que la mère décide d'un dépôt de validation : le verdict à écrire sur le dépôt et, quand la validation s'applique, le patch de la fiche et la fiche REMPLACÉE à archiver.
class ApplicationFicheAideValider {
  const ApplicationFicheAideValider({required this.etat, this.code, this.motif, this.geste, this.patch, this.archiver, this.archivage});
  final String etat;
  final String? code;
  final String? motif;
  final String? geste;

  /// Non nul seulement quand [etat] vaut `appliquee` : ce qu'il faut écrire sur la fiche d'aide.
  final Map<String, Object?>? patch;

  /// L'identifiant de la fiche que celle-ci remplace (à archiver à son tour, RG-14), s'il y en a une.
  final String? archiver;

  /// Le patch d'archivage de la fiche remplacée (`null` : rien à archiver, ou la remplacée est déjà archivée).
  final Map<String, Object?>? archivage;
}

/// APPLIQUE un dépôt sur la mère : refait TOUS les contrôles de [validerFicheAide] sous le RÔLE et le NOM du déposant, avec la fiche et la matrice de la mère, à la date du GESTE (`demandeLe`,
/// jamais celle de l'application : la validation ne s'antidate ni ne se postdate). [fiche] : la fiche d'aide telle que la mère la connaît (`null` : elle n'est pas (encore) arrivée) ;
/// [remplacee] : la fiche que celle-ci remplace, si la mère la connaît. `null` : rien à faire (dépôt déjà traité). Un `null` de [fiche] rend `FICHE_INCONNUE`, refusé : l'appelant décide d'attendre
/// avant d'appeler quand le dépôt peut devancer la fiche.
ApplicationFicheAideValider? ficheAideValiderAppliquer(
  Map<String, Object?> depot, {
  required Map<String, Object?>? fiche,
  required Map<String, Object?>? remplacee,
  required DroitsGestes gestes,
  required Iterable<String> rolesConnus,
  required DateTime maintenant,
}) {
  if (depot['genre'] != valGenreFicheAideValider || depot['etat'] != valDepotDeposee || depot['statut'] == 'archive') return null;
  final quand = DateTime.tryParse('${depot['demandeLe'] ?? ''}')?.toLocal() ?? maintenant;
  if (fiche != null && depot['contenuVu'] != null && fiche['statut'] == ficheAideProposee && depot['contenuVu'] != ficheAideEmpreinteContenu(fiche)) {
    return const ApplicationFicheAideValider(
        etat: valDepotRefusee,
        code: 'FICHE_MODIFIEE',
        motif: 'La fiche a été modifiée depuis la relecture du validateur : on valide ce qu’on a lu, pas ce qui a été réécrit entre-temps.',
        geste: 'Relire la fiche telle qu’elle est maintenant, puis redemander la validation.');
  }
  final v = validerFicheAide(
      fiche: fiche,
      role: '${depot['demandeRole'] ?? ''}',
      validateurId: '${depot['validateurId'] ?? ''}',
      validateurNom: '${depot['demandePar'] ?? ''}',
      maintenant: quand,
      gestes: gestes,
      rolesConnus: rolesConnus,
      professionnel: depot['professionnel'] as String?,
      professionnelLe: depot['professionnelLe'] as String?);
  if (!v.accepte) {
    final r = v.refus!;
    // « Déjà validée » n'est pas une faute : la fiche porte déjà sa validation, la mère n'en écrit pas une seconde.
    if (r.code == 'DEJA_VALIDEE') return ApplicationFicheAideValider(etat: valDepotSansEffet, code: r.code, motif: r.motif, geste: r.geste);
    return ApplicationFicheAideValider(etat: valDepotRefusee, code: r.code, motif: r.motif, geste: r.geste);
  }
  Map<String, Object?>? archivage;
  if (v.archiver != null && remplacee != null && remplacee['statut'] != ficheAideArchivee) {
    final ar = archiverFicheAide(
        fiche: remplacee,
        motif: 'Remplacée par la fiche ${depot['cible']}, validée le ${v.fiche!['valideLe']}',
        auteurNom: '${depot['demandePar'] ?? ''}',
        maintenant: quand);
    if (ar.accepte) archivage = ar.fiche;
  }
  return ApplicationFicheAideValider(etat: valDepotAppliquee, patch: v.fiche, archiver: v.archiver, archivage: archivage);
}

/// Le dépôt d'une fiche qui attend encore la mère (`null` : aucun) : l'écran dit « validation transmise à la mère, en attente » et n'offre pas de second geste.
Map<String, Object?>? ficheAideDepotEnAttente(Iterable<Map<String, Object?>> depots, Object? ficheId) {
  for (final d in depots) {
    if (d['statut'] != 'archive' && d['genre'] == valGenreFicheAideValider && d['cible'] == ficheId && d['etat'] == valDepotDeposee) return d;
  }
  return null;
}

/// Le dernier dépôt REFUSÉ par la mère pour cette fiche (son motif nommé revient au validateur) ; `null` si aucun, ou si un dépôt plus récent l'a suivi.
Map<String, Object?>? ficheAideDepotRefuse(Iterable<Map<String, Object?>> depots, Object? ficheId) {
  Map<String, Object?>? dernier;
  for (final d in depots) {
    if (d['statut'] == 'archive' || d['genre'] != valGenreFicheAideValider || d['cible'] != ficheId) continue;
    if (dernier == null || '${d['demandeLe']}'.compareTo('${dernier['demandeLe']}') >= 0) dernier = d;
  }
  return dernier != null && dernier['etat'] == valDepotRefusee ? dernier : null;
}
