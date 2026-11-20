/// LA SUITE DE LA FACTURE À UNE ENTREPRISE (Direction de Baguidi, 17/11/2026, point 2 des décisions du 16/11) : l'AVOIR qui la corrige, la TRANSMISSION au dispositif fiscal, et le contrôle de
/// ce qui s'imprime. Le moteur d'avoir est celui de la caisse (`emettreAvoir`) : plafond cumulé, lignes nommées, montant > 0, contre-passation en brouillon dont l'équilibre est CONSTRUIT
/// (RG-10) — ici on l'appelle, on ne le recopie pas. La transmission suit le circuit MECeF des autres ventes normalisées : mode et adaptateur du réglage, état « en attente » tant qu'aucun
/// appareil ne répond, refus nommés, jamais un numéro fabriqué.
///
/// Ce que la facture à une entreprise change par rapport à celle d'un patient, et que rien ne présume : elle PORTE un acheteur (IFU et nom) et l'AIB choisi par le comptable ; l'AIB entre dans
/// la base MECeF selon la règle existante (`mecefMontants` : base = part du payeur, net à payer = hors taxes + AIB).
///
/// Fonctions PURES : elles rendent ce qu'il faut écrire ou un refus nommé ; elles n'écrivent rien.
library;

import '../caisse/avoir.dart';
import '../administration/pta.dart' show PtaSignataire, ptaSignataires;
import '../droits/gestes_reserves.dart';
import 'etats.dart';
import 'facture_tiers_payeur.dart';
import 'mode.dart';
import 'montants.dart';
import 'normalisation.dart' show refusRetransmission;

num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// La collection des avoirs des factures à une entreprise. À part de `avoirs` (caisse) : elle porte un acheteur et ne part jamais vers un téléphone ; la SÉRIE de numéros
/// (`caisse.avoirs`) reste unique, calculée sur les deux collections.
const String colAvoirsTiers = 'avoirsTiers';

/// Le type porté par l'avoir d'une facture à une entreprise.
const String typeAvoirFactureTiers = 'avoir_tiers_payeur';

/// L'unique ligne d'une facture à une entreprise, telle que la normalisation et l'avoir la lisent (identifiant stable `L001`, jamais saisie : le montant est la part du relevé).
List<Map<String, Object?>> lignesFactureTiers(Map<String, Object?> f) {
  final montant = _n(f['montantTTC']);
  return [
    {
      'id': 'L001',
      'designation': '${f['designation'] ?? 'Prise en charge des soins'}',
      'quantite': 1,
      'prixUnitaire': montant,
      'montantBrut': montant,
      'montant': montant,
      'remise': 0,
      'partAssureur': 0,
      'partPersonnel': 0,
    }
  ];
}

/// Ce qui reste à contre-passer sur la pièce : son montant moins les avoirs déjà portés (jamais négatif).
num resteAvoirableFactureTiers(Map<String, Object?> f) {
  final reste = _n(f['montantTTC']) - _n(f['montantAvoirs']);
  return reste > 0 ? reste : 0;
}

/// Le verdict d'un avoir sur une facture à une entreprise.
class VerdictAvoirTiers {
  const VerdictAvoirTiers.ok(AvoirEmis this.emission) : refus = null;
  const VerdictAvoirTiers.refus(RefusTiersPayeur this.refus) : emission = null;
  final AvoirEmis? emission;
  final RefusTiersPayeur? refus;
  bool get ok => emission != null;
}

/// ÉMETTRE l'AVOIR d'une facture à une entreprise : le refus nommé, ou ce que le moteur unique d'avoir écrit, enrichi de l'acheteur et de l'AIB de la pièce. Ordre des contrôles : le poste (un
/// fileul dépose, il n'écrit pas) ; le geste réservé de l'émission (corriger la pièce est le geste qui l'a émise : aucun geste nouveau) ; la pièce ; le motif ; puis le moteur (lignes nommées,
/// montant > 0, plafond CUMULÉ à la facture).
///
/// [avoirsTiers] : les avoirs déjà émis sur les factures à une entreprise (le plafond cumulé ne porte que sur la pièce). [avoirsCaisse] : ceux de la caisse, pour que la série de numéros reste
/// unique. [montant] : absent, l'avoir contre-passe tout ce qui reste ; sinon une partie. La pièce émise n'est jamais réécrite : l'appelant écrit l'avoir et le cumul qu'elle PORTE.
VerdictAvoirTiers emettreAvoirFactureTiers({
  required String role,
  DroitsGestes? gestes,
  bool fileul = false,
  required Map<String, Object?>? facture,
  required String idAvoir,
  required String motif,
  required String jour,
  required String utilisateur,
  num? montant,
  String? remboursement,
  String? observations,
  String? date,
  String? horodatage,
  bool mecefActif = true,
  List<Map<String, Object?>> avoirsTiers = const [],
  List<Map<String, Object?>> avoirsCaisse = const [],
  List<Map<String, Object?>> facturesMere = const [],
}) {
  VerdictAvoirTiers non(String code, String motif, String geste) => VerdictAvoirTiers.refus(RefusTiersPayeur(code, motif, geste));
  if (fileul) {
    return non('FILEUL_LECTURE_SEULE', 'Ce poste est un fileul : l’avoir d’une facture à une entreprise s’émet depuis le poste mère, qui tient la numérotation et la normalisation.',
        'Déposer la demande d’avoir : la mère l’applique sous votre rôle, la pièce reviendra ici par la synchronisation.');
  }
  if (role.isEmpty || !(gestes ?? gestesOrigine()).peut(role, gesteFactureTiersEmettre)) {
    return non('TIERS_PAYEUR_RESERVE', 'Corriger une facture à une entreprise est le geste réservé qui l’émet (« Émettre une facture à une entreprise ») : votre rôle ne le détient pas.',
        'Demander au comptable ou à la DAF, ou faire accorder le geste au rôle dans « Rôles et permissions › Gestes réservés ».');
  }
  if (facture == null || facture['type'] != typeFactureTiersPayeur) {
    return non('FACTURE_TIERS_INTROUVABLE', 'Cette pièce n’est pas une facture à une entreprise du registre.', 'Choisir la facture dans l’onglet « Factures à une entreprise ».');
  }
  if (facture['statut'] == 'archive') {
    return non('FACTURE_TIERS_ARCHIVEE', 'La facture ${facture['numero']} est archivée : on ne la contre-passe plus.', 'Restaurer la pièce depuis la corbeille, ou choisir une autre facture.');
  }
  if (motif.trim().isEmpty) {
    return non('MOTIF_AVOIR_REQUIS', 'Un avoir se motive : la compagnie et l’entreprise liront pourquoi la pièce est contre-passée.', 'Saisir le motif de l’avoir.');
  }
  final reste = resteAvoirableFactureTiers(facture);
  final voulu = montant ?? reste;
  final ligne = lignesFactureTiers(facture).first;
  final nommee = {...ligne, 'montant': voulu, 'prixUnitaire': voulu, 'montantBrut': voulu};
  final AvoirEmis e;
  try {
    e = emettreAvoir(
        facture: facture,
        idAvoir: idAvoir,
        lignes: [nommee],
        motif: motif.trim(),
        jour: jour,
        utilisateur: utilisateur,
        remboursement: remboursement,
        observations: observations,
        date: date,
        origine: 'facture_tiers',
        horodatage: horodatage,
        mecefActif: mecefActif,
        facturesMere: facturesMere,
        avoirs: avoirsTiers,
        avoirsNumerotation: [...avoirsCaisse, ...avoirsTiers]);
  } on RefusAvoir catch (x) {
    return non('AVOIR_REFUSE', x.motif, 'Corriger les lignes ou le montant de l’avoir (le cumul des avoirs ne dépasse jamais la facture).');
  }
  // L'AIB de l'avoir suit le taux de la pièce corrigée, sur le même calcul de montants (base = le montant corrigé, AIB sur le hors taxes).
  final taux = facture['aibTaux'];
  final m = mecefMontants(lignes: [nommee], totalAttendu: voulu, aibTaux: taux is num ? taux : null);
  final aib = m.ok ? m.montants!.aib : null;
  final fiche = {
    ...e.avoir,
    'type': typeAvoirFactureTiers,
    'factureType': typeFactureTiersPayeur,
    'acheteurIfu': facture['acheteurIfu'],
    'acheteurNom': facture['acheteurNom'],
    'patient': facture['acheteurNom'],
    'compagnieCode': facture['compagnieCode'],
    'aibTaux': facture['aibTaux'],
    if (aib != null) 'aibMontant': aib,
    if (m.ok) 'baseMecef': m.montants!.base,
  };
  return VerdictAvoirTiers.ok(AvoirEmis(avoir: fiche, ecritures: e.ecritures, montantAvoirs: e.montantAvoirs));
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La transmission au dispositif fiscal
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce que la préparation de la certification d'une facture à une entreprise rend : la demande à l'appareil, ou le refus nommé.
class PreparationCertificationTiers {
  const PreparationCertificationTiers.ok(DemandeCertification this.demande, MontantsMecef this.montants, AcheteurMecef this.acheteur) : refus = null;
  const PreparationCertificationTiers.refus(RefusMecef this.refus)
      : demande = null,
        montants = null,
        acheteur = null;
  final DemandeCertification? demande;
  final MontantsMecef? montants;
  final AcheteurMecef? acheteur;
  final RefusMecef? refus;
  bool get ok => demande != null;
}

/// Les contrôles qui PRÉCÈDENT l'envoi d'une facture à une entreprise : pièce du registre, active, non contre-passée en totalité, pas déjà normalisée (elle ne se renormalise jamais), acheteur
/// identifié (IFU et nom), montants entiers cohérents avec le total. Contrairement à la vente d'un patient, aucun encaissement n'est exigé : on facture l'entreprise avant qu'elle ne règle. L'AIB
/// est celui que la pièce porte (choisi à l'émission, taux du barème arrêté à sa date).
PreparationCertificationTiers preparerCertificationFactureTiers(Map<String, Object?> f, {num tauxTvaCourant = 0}) {
  final num_ = '${f['numero'] ?? f['id']}';
  PreparationCertificationTiers non(String code, String motif, String geste) => PreparationCertificationTiers.refus(RefusMecef(code, motif, geste));
  if (f['type'] != typeFactureTiersPayeur) {
    return non('PAS_UNE_FACTURE_TIERS', 'La pièce $num_ n’est pas une facture à une entreprise.', 'Normaliser les ventes des patients depuis la caisse.');
  }
  if (f['statut'] == 'archive') {
    return non('PIECE_ARCHIVEE', 'La facture $num_ est archivée : elle ne se transmet pas.', 'Restaurer la pièce, ou en émettre une autre.');
  }
  if (_n(f['montantAvoirs']) > 0 && _n(f['montantAvoirs']) >= _n(f['montantTTC'])) {
    return non('PIECE_CONTRE_PASSEE', 'La facture $num_ est contre-passée en totalité par avoir : il n’y a plus rien à transmettre.', 'Émettre une nouvelle facture à l’entreprise.');
  }
  if (porteBlocFiscal(f)) {
    return non('DEJA_NORMALISEE', 'La facture $num_ est déjà normalisée (${f['numeroMecef']}) : elle ne se renormalise jamais.', 'La corriger par un avoir.');
  }
  final ach = validerAcheteurMecef(ifu: f['acheteurIfu'], nom: f['acheteurNom'], aibTaux: f['aibTaux'], aibSituation: f['aibSituation']);
  if (ach.refus != null) return PreparationCertificationTiers.refus(ach.refus!);
  if ('${f['acheteurIfu'] ?? ''}'.trim().isEmpty) {
    return non('IFU_ACHETEUR_REQUIS', 'La facture $num_ n’a pas d’IFU d’acheteur : une facture à un tiers payeur identifie son acheteur.', 'Archiver la pièce et la réémettre avec l’IFU de l’entreprise.');
  }
  final m = mecefMontants(lignes: lignesFactureTiers(f), totalAttendu: _n(f['montantTTC']), aibTaux: ach.acheteur!.aibTaux, tauxTvaCourant: tauxTvaCourant);
  if (!m.ok) return PreparationCertificationTiers.refus(m.refus!);
  final mt = m.montants!;
  return PreparationCertificationTiers.ok(
      DemandeCertification(
        cle: '${f['id'] ?? f['numero']}',
        total: mt.total,
        base: mt.base,
        aib: mt.aib,
        ifuAcheteur: '${f['acheteurIfu']}'.replaceAll(RegExp('[\\s  ]'), ''),
        nomAcheteur: '${f['acheteurNom']}'.trim(),
        aibTaux: ach.acheteur!.aibTaux,
      ),
      mt,
      ach.acheteur!);
}

/// Les états de la transmission d'une facture à une entreprise, en mots de l'écran : en attente → certifiée / rejetée.
const String transmissionTiersEnAttente = 'en_attente';
const String transmissionTiersCertifiee = 'certifiee';
const String transmissionTiersRejetee = 'rejetee';

/// Ce que la transmission a décidé : l'état, le patch à écrire sur la pièce, le refus nommé quand elle ne s'est pas faite.
class ResultatTransmissionTiers {
  const ResultatTransmissionTiers(this.etat, this.patch, {this.refus});
  final String etat;
  final Map<String, Object?> patch;
  final RefusMecef? refus;
  bool get certifiee => etat == transmissionTiersCertifiee;
}

/// Qui peut TRANSMETTRE (ou retransmettre) une facture à une entreprise, sans geste nouveau : celui qui détient le geste qui l'ÉMET ([gesteFactureTiersEmettre] : le comptable et la DAF d'origine)
/// transmet sa propre pièce tant qu'elle n'est pas normalisée (en attente, rejetée, expirée) — la retransmission des ventes de la caisse (« une fois », puis « sans limite ») lui est fermée
/// d'origine, et lui retirer la transmission de ce qu'il vient d'émettre l'obligerait à passer par un autre poste. Sinon, la règle des autres ventes ([refusRetransmission]) s'applique telle
/// quelle : geste réservé de la retransmission, une fois puis sans limite. Jamais une pièce déjà normalisée. `null` : permis.
RefusMecef? refusRetransmissionFactureTiers(Map<String, Object?> f, String role, {DroitsGestes? gestes}) {
  final g = gestes ?? gestesOrigine();
  final etat = etatMecefDe(f)?.id;
  if (role.isNotEmpty && g.peut(role, gesteFactureTiersEmettre) && etat != 'normalisee' && const ['refusee', 'expiree', 'en_attente'].contains(etat)) return null;
  return refusRetransmission(f, role, gestes: gestes);
}

/// Ce que la transmission décide SANS interroger l'appareil : un refus de la préparation (pièce non transmissible, montants ou acheteur à corriger) ou l'attente d'un appareil non configuré.
/// `null` : l'appareil est branché, il faut le questionner ([transmettreFactureTiersPayeur]). SYNCHRONE : la mère qui applique la demande d'un fileul n'a pas à attendre un appareil absent.
ResultatTransmissionTiers? transmissionImmediateFactureTiers(Map<String, Object?> f, AdaptateurMecef adaptateur, {String? modeleBoitier, num tauxTvaCourant = 0}) {
  final prep = preparerCertificationFactureTiers(f, tauxTvaCourant: tauxTvaCourant);
  if (!prep.ok) {
    final r = prep.refus!;
    // Un refus des MONTANTS ou de l'acheteur écrit la pièce « rejetée » (à corriger) ; les autres refus n'écrivent rien.
    const aCorriger = {'AUCUNE_LIGNE', 'QUANTITE_INVALIDE', 'PRIX_DECIMAL', 'MONTANT_DECIMAL', 'REMISE_INVALIDE', 'TOTAL_INCOHERENT', 'AIB_TAUX_INVALIDE', 'IFU_INVALIDE', 'NOM_ACHETEUR_ABSENT', 'IFU_ACHETEUR_REQUIS'};
    final ecrit = aCorriger.contains(r.code);
    return ResultatTransmissionTiers(ecrit ? transmissionTiersRejetee : '', ecrit ? {'statutMecef': 'rejete', 'codeRetour': r.code, 'motifRefusMecef': r.motif} : const {}, refus: r);
  }
  if (!adaptateur.configure) {
    final refus = adaptateur.refus!;
    return ResultatTransmissionTiers(
        transmissionTiersEnAttente, {...champsEnAttenteCertification(refus, adaptateur.mode), ...champsAppareilMecef(adaptateur.mode, modeleBoitier), 'aibMontant': prep.montants!.aib}, refus: refus);
  }
  return null;
}

/// TRANSMET une facture à une entreprise à l'adaptateur du mode en vigueur. Aucun appareil configuré : la pièce reste EN ATTENTE, avec le code, le motif et le geste du refus nommé
/// (jamais un numéro fabriqué). Un appareil qui répond par un numéro : la pièce est CERTIFIÉE (identifiant, instant de l'appareil, AIB). Un refus de l'appareil : la pièce est REJETÉE, le code
/// et le motif sont portés pour la correction. [maintenant] : l'instant écrit quand l'appareil n'en donne pas.
Future<ResultatTransmissionTiers> transmettreFactureTiersPayeur(
  Map<String, Object?> f,
  AdaptateurMecef adaptateur, {
  required DateTime maintenant,
  required String auteur,
  String? modeleBoitier,
  num tauxTvaCourant = 0,
}) async {
  final immediat = transmissionImmediateFactureTiers(f, adaptateur, modeleBoitier: modeleBoitier, tauxTvaCourant: tauxTvaCourant);
  if (immediat != null) return immediat;
  final prep = preparerCertificationFactureTiers(f, tauxTvaCourant: tauxTvaCourant);
  final rep = await adaptateur.emettre(prep.demande!);
  if (!rep.ok) {
    final r = rep.refus!;
    return ResultatTransmissionTiers(transmissionTiersRejetee, {'statutMecef': 'rejete', 'codeRetour': r.code, 'motifRefusMecef': r.motif, 'modeMecef': adaptateur.mode}, refus: r);
  }
  return ResultatTransmissionTiers(transmissionTiersCertifiee, {
    'statutMecef': 'valide',
    'numeroMecef': rep.numero,
    'codeRetour': 'OK-200',
    'motifRefusMecef': null,
    'dateTransmission': rep.horodatage ?? maintenant.toIso8601String(),
    'aibMontant': prep.montants!.aib,
    'normalisePar': auteur,
    'modeMecef': adaptateur.mode,
    ...champsAppareilMecef(adaptateur.mode, modeleBoitier),
  });
}

/// Le libellé de l'état de transmission d'une facture à une entreprise (écran et pièce) : en attente / certifiée / rejetée / à vérifier.
String libelleTransmissionTiers(Map<String, Object?> f) {
  final e = etatMecefDe(f);
  if (e == null) return 'Sans objet (module MECeF fermé à l’émission)';
  return switch (e.id) {
    'normalisee' => 'Certifiée',
    'en_attente' => 'En attente de certification',
    'refusee' => 'Rejetée',
    _ => e.libelle,
  };
}

/// Les signataires de la pièce imprimée, lus à l'ORGANIGRAMME ([postes], collection `postes`) : les postes que le réglage [reglage] (`factureTiers.signataires`) liste, sinon le poste qui coiffe
/// l'organigramme. Aucun intitulé ni nom n'est écrit dans le code ; sans poste lisible, une ligne qui dit qu'il reste à désigner (et nomme CE réglage).
List<PtaSignataire> signatairesFactureTiers({required Iterable<Map<String, Object?>> postes, Object? reglage}) {
  final actifs = [for (final p in postes) if (p['statut'] != 'archive') p];
  final voulus = '${reglage ?? ''}'.split(';').any((x) => x.trim().isNotEmpty);
  final racines = actifs.any((p) => '${p['parentId'] ?? ''}'.isEmpty);
  if (!voulus && !racines) return const [PtaSignataire('Signataire à désigner (réglage « postes signataires de la facture à une entreprise »)', null)];
  return ptaSignataires(postes: postes, reglage: reglage);
}
