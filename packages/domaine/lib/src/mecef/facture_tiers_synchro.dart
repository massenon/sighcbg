/// LA FACTURE À UNE ENTREPRISE À TRAVERS LES POSTES (Direction de Baguidi, 17/11/2026, point 2) : où elle s'écrit, comment elle voyage, comment un fileul la DEMANDE.
///
/// L'ÉMISSION RESTE À LA MÈRE : c'est elle qui tient la numérotation (série `caisse.factures-tiers`, `caisse.avoirs`) et la normalisation (l'appareil MECeF est branché à son poste). Un fileul
/// ne peut donc ni créer ni modifier une facture à une entreprise ni son avoir : la mère REFUSE son écriture en nommant le geste (`emission_reservee_mere`), comme elle refuse la validation
/// d'une pièce du planning. Ce que le fileul écrit, c'est une DEMANDE (collection `validationsDeposees`, genre [valGenreFactureTiers] : le mécanisme de la continuité, pas un second) :
/// émission d'une facture née d'une ligne du relevé, avoir sur une pièce émise, retransmission au dispositif fiscal. La mère l'APPLIQUE sous le rôle et le nom de l'auteur, avec SA matrice,
/// SES numéros et SON relevé — tous les contrôles refaits — et écrit le verdict sur la même fiche, qui revient au fileul par le journal. Rejouable : une demande identique en attente n'est pas
/// doublée, une demande traitée n'est jamais rejouée.
///
/// Les deux collections voyagent entre postes en famille A (une fiche, une identité commune, champ à champ) : la pièce émise par la mère est LUE partout (comptable d'un fileul, DAF, caisse).
/// Elles ne partent JAMAIS vers un téléphone : l'IFU et le nom d'une entreprise, le souscripteur qu'elle prend en charge, sont des données nominatives (RG-13).
///
/// Fonctions PURES : le poste y branche ses collections et son transport ; la mère Dart et le banc Node en reprennent le refus d'écriture, à l'identique.
library;

import '../droits/gestes_reserves.dart';
import '../validation/validation.dart' show RefusValidation, valInstant;
import '../validation/validation_deposee.dart';
import 'facture_tiers_payeur.dart';
import 'facture_tiers_suite.dart';
import 'montants.dart' show validerAcheteurMecef;

/// Le genre de dépôt d'une demande sur une facture à une entreprise.
const String valGenreFactureTiers = 'facture_tiers';

/// Les deux collections qui voyagent (famille A de la mère, jamais vers un téléphone).
const List<String> facturesTiersCollectionsSync = [colFacturesTiers, colAvoirsTiers];

/// Les trois demandes qu'un fileul peut déposer.
const String factureTiersActionEmettre = 'emettre';
const String factureTiersActionAvoir = 'avoir';
const String factureTiersActionTransmettre = 'transmettre';
const List<String> factureTiersActions = [factureTiersActionEmettre, factureTiersActionAvoir, factureTiersActionTransmettre];

/// Le libellé d'une demande, pour la fiche et pour la file « validations en attente ».
const Map<String, String> factureTiersLibellesActions = {
  factureTiersActionEmettre: 'Émission d’une facture à une entreprise',
  factureTiersActionAvoir: 'Avoir sur une facture à une entreprise',
  factureTiersActionTransmettre: 'Transmission d’une facture à une entreprise au dispositif fiscal',
};

/// Le contrôle UNIQUE que la mère refait à l'écriture d'un poste sur ces deux collections : un refus nommé, ou `null` (la mère applique ; un poste qui n'est pas la mère est refusé).
/// [mere] : l'écriture vient de la mère elle-même. Miroir exact au banc Node (`mere.js`, `refusFactureTiersEcriture`).
({String code, String motif, String geste})? refusEcritureFactureTiers(String collection, {required bool mere}) {
  if (mere || !facturesTiersCollectionsSync.contains(collection)) return null;
  return (
    code: 'emission_reservee_mere',
    motif: 'Une facture à une entreprise et son avoir ne s’écrivent que sur le poste mère : elle seule tient la numérotation et la normalisation fiscale.',
    geste: 'Déposer une demande (« Émettre une facture à une entreprise ») : la mère l’applique sous votre rôle.'
  );
}

/// La clé qui identifie la CIBLE d'une demande : pour une émission, la ligne du relevé (compagnie, périodicité, souscripteur) ; pour un avoir ou une transmission, la pièce.
String cibleFactureTiers(String action, Map<String, Object?> charge) => action == factureTiersActionEmettre
    ? '${charge['compagnieCode']}|${charge['periode']}|${charge['souscripteur']}'
    : '${charge['factureId'] ?? ''}';

RefusValidation _non(String code, String motif, [String? geste]) => RefusValidation(code, motif, geste);

/// DÉPOSE une demande depuis un fileul. Les contrôles sont ceux du geste lui-même, à l'identique, et se NOMMENT dès le poste, avant tout dépôt : l'action est connue, le rôle détient le geste,
/// la charge est complète (IFU de 13 chiffres, nom, situation d'AIB CHOISIE ; motif de l'avoir ; pièce désignée), la pièce existe. [facture] : la pièce visée par un avoir ou une transmission, telle que
/// ce poste la voit. Un dépôt identique qui attend déjà la mère n'est pas doublé.
VerdictDepot factureTiersDeposer({
  required String action,
  required Map<String, Object?> charge,
  required String role,
  required String acteur,
  required String poste,
  required DateTime maintenant,
  required DroitsGestes gestes,
  required List<Map<String, Object?>> depots,
  required String Function() nouvelId,
  Map<String, Object?>? facture,
}) {
  VerdictDepot refus(String code, String motif, [String? geste]) => VerdictDepot.refus(_non(code, motif, geste));
  if (!factureTiersActions.contains(action)) {
    return refus('ACTION_INCONNUE', 'La demande « $action » n’existe pas pour une facture à une entreprise.', 'Choisir émission, avoir ou transmission.');
  }
  if (action != factureTiersActionTransmettre) {
    if (role.isEmpty || !gestes.peut(role, gesteFactureTiersEmettre)) {
      return refus('TIERS_PAYEUR_RESERVE', 'Demander une facture à une entreprise ou son avoir est le geste réservé « Émettre une facture à une entreprise » : votre rôle ne le détient pas.',
          'Demander au comptable ou à la DAF, ou faire accorder le geste au rôle dans « Rôles et permissions › Gestes réservés ».');
    }
  }
  if (action == factureTiersActionEmettre) {
    for (final (champ, libelle) in [('compagnieCode', 'la compagnie'), ('periode', 'la périodicité'), ('souscripteur', 'le souscripteur')]) {
      if ('${charge[champ] ?? ''}'.trim().isEmpty) {
        return refus('RELEVE_VIDE', 'La demande ne désigne pas $libelle : la pièce naît d’une ligne du relevé de M9.', 'Choisir la ligne du relevé (compagnie, périodicité, souscripteur).');
      }
    }
    final ifu = '${charge['ifu'] ?? ''}'.replaceAll(RegExp('[\\s  ]'), '');
    if (ifu.isEmpty) return refus('IFU_ACHETEUR_REQUIS', 'L’IFU de l’entreprise est obligatoire : une facture à un tiers payeur identifie son acheteur.', 'Saisir l’IFU de l’entreprise (13 chiffres).');
    final v = validerAcheteurMecef(ifu: ifu, nom: charge['nom']);
    if (v.refus != null) return refus(v.refus!.code, v.refus!.motif, v.refus!.geste);
    if ('${charge['nom'] ?? ''}'.trim().isEmpty) {
      return refus('NOM_ACHETEUR_ABSENT', 'Le nom de l’entreprise est obligatoire : il accompagne son IFU sur la pièce normalisée.', 'Saisir le nom de l’entreprise qui porte cet IFU.');
    }
    if ('${charge['situation'] ?? ''}'.trim().isEmpty) {
      return refus('AIB_SITUATION_A_CHOISIR', 'La situation de l’acheteur au barème de l’AIB n’est jamais présumée : le comptable la choisit.',
          'Choisir la situation de l’entreprise dans la liste du barème (Paramètres, « Acompte sur impôt (AIB) »).');
    }
  } else {
    if ('${charge['factureId'] ?? ''}'.trim().isEmpty || facture == null || facture['type'] != typeFactureTiersPayeur) {
      return refus('FACTURE_TIERS_INTROUVABLE', 'La demande ne désigne aucune facture à une entreprise de ce poste.', 'Choisir la pièce dans l’onglet « Factures à une entreprise ».');
    }
    if (action == factureTiersActionAvoir) {
      if ('${charge['motif'] ?? ''}'.trim().isEmpty) return refus('MOTIF_AVOIR_REQUIS', 'Un avoir se motive : la compagnie et l’entreprise liront pourquoi la pièce est contre-passée.', 'Saisir le motif de l’avoir.');
      final m = charge['montant'];
      if (m != null && !(m is num && m > 0)) return refus('AVOIR_REFUSE', 'Le montant de l’avoir doit être strictement supérieur à 0 FCFA.', 'Corriger le montant, ou le laisser vide pour contre-passer le reste.');
    } else {
      final r = refusRetransmissionFactureTiers(facture, role, gestes: gestes);
      if (r != null) return refus(r.code, r.motif, r.geste);
    }
  }
  final cible = cibleFactureTiers(action, charge);
  for (final d in depots) {
    if (d['statut'] != 'archive' && d['etat'] == valDepotDeposee && d['genre'] == valGenreFactureTiers && d['action'] == action && d['cible'] == cible && d['demandeRole'] == role) {
      return VerdictDepot.ok(d, dejaDepose: true);
    }
  }
  return VerdictDepot.ok({
    'id': nouvelId(),
    'statut': 'actif',
    'genre': valGenreFactureTiers,
    'famille': valGenreFactureTiers,
    'action': action,
    'cible': cible,
    'libelle': factureTiersLibellesActions[action],
    'charge': {...charge},
    'etat': valDepotDeposee,
    'demandeRole': role,
    'demandePar': acteur,
    'demandePoste': poste,
    'demandeLe': valInstant(maintenant),
  });
}

/// Le dernier dépôt d'une demande sur une cible, tant qu'il n'est pas résolu par une pièce visible : `deposee` (en attente de la mère) ou `refusee` (le motif nommé revient à l'auteur).
Map<String, Object?>? depotFactureTiersOuvert(Iterable<Map<String, Object?>> depots, String action, String cible) {
  Map<String, Object?>? dernier;
  for (final d in depots) {
    if (d['statut'] == 'archive' || d['genre'] != valGenreFactureTiers || d['action'] != action || d['cible'] != cible) continue;
    if (dernier == null || '${d['demandeLe']}'.compareTo('${dernier['demandeLe']}') >= 0) dernier = d;
  }
  if (dernier == null) return null;
  final e = '${dernier['etat']}';
  return e == valDepotDeposee || e == valDepotRefusee ? dernier : null;
}

/// À qui s'adresse la file des demandes en attente : ceux qui détiennent le geste d'émission (lus dans la matrice, jamais une liste de rôles).
const String gesteDestinataireFactureTiers = gesteFactureTiersEmettre;
