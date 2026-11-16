/// LA FACTURE D'UN PATIENT NE PORTE NI ACHETEUR NI AIB (Direction de Baguidi, 16/11/2026, `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md` §8, écarts E3770 à E3779).
///
/// Le patient paie le TOTAL de sa part : la facture reste normalisée MECeF, mais sans IFU ni nom d'acheteur et sans acompte sur impôt (AIB). Le bloc « FACTURE
/// NORMALISÉE » (IFU de l'acheteur, Nom de l'acheteur, Taux d'AIB) disparaît des trois portes d'encaissement de la caisse (émission, registre des paiements, file
/// de caisse) ; le moteur de normalisation du poste n'exige ni n'applique d'AIB sur une facture de la caisse, qui est toujours celle d'un patient (ou d'un client
/// libre au comptoir, un particulier lui aussi).
///
/// Ce qui RESTE, là où l'acheteur et l'AIB ont un sens (mesure du 16/11/2026) :
///
/// * la RETENUE d'AIB sur la facture d'un fournisseur (M7, `cpd_retenue_aib`, barème « retenue sur la facture d'un tiers ») et l'AIB subi (`cpd_aib_subi`) ;
/// * le moteur de l'acheteur au barème (`acheteurNormaliseAuBareme`, `aibPourAcheteur`, `validerAcheteurMecef`) et les montants (`mecefMontants` avec un taux) :
///   ils servent la vente normalisée à un TIERS PAYEUR identifié par son IFU (un assureur, une entreprise cliente). Aucune porte du poste n'émet aujourd'hui une
///   telle vente : la part de l'assureur ou de l'entreprise est portée par la facture du patient puis réclamée par le relevé et la facture mère de M9, qui ne
///   sont pas des pièces MECeF. Le moteur est gardé pour cette porte, sans écran.
library;

import 'montants.dart';

/// Le taux d'AIB d'une facture patient : aucun (le patient paie le total).
const int mecefAibFacturePatient = 0;

/// L'acheteur d'une facture patient : ni IFU, ni nom, AIB nul. C'est une vente à un particulier, normalisée sans acheteur.
const AcheteurMecef acheteurFacturePatient = AcheteurMecef(aibTaux: mecefAibFacturePatient);

/// Les champs qu'une facture patient porte après sa normalisation : ni acheteur, ni situation au barème, ni repli, ni motif, AIB nul. Une pièce semée ou
/// encaissée AVANT la décision du 16/11/2026 qui portait encore un acheteur ou un taux en attente de certification est normalisée sous cette règle (le journal
/// garde l'ancienne valeur, RG-12) : une pièce non certifiée n'a encore rien émis.
const Map<String, Object?> champsFacturePatientSansAib = {
  'ifuClient': null,
  'acheteurNom': null,
  'aibTaux': mecefAibFacturePatient,
  'aibSituation': null,
  'aibRepli': null,
  'aibMotif': null,
};

/// La mention dite à l'écran et sur la pièce : la facture d'un patient est normalisée sans acheteur ni AIB.
const String mecefMentionFacturePatient =
    'Facture d’un patient : normalisée MECeF sans acheteur ni AIB (le patient paie le total, décision de la Direction du 16/11/2026).';

/// Où la saisie de l'acheteur et de l'AIB garde un sens, et pourquoi (affiché par la configuration fiscale, et repris par les écarts E3770 à E3779).
const List<(String, String)> mecefSaisieAcheteurAibConservee = [
  ('Facture d’un fournisseur (M7)', 'Retenue d’AIB sur la facture d’un tiers, au barème « retenue sur la facture d’un tiers » ; AIB subi, sans écriture.'),
  ('Vente à un tiers payeur (assureur, entreprise cliente)', 'Moteur de l’acheteur au barème gardé au domaine ; aucune porte du poste n’émet cette vente aujourd’hui (relevé et facture mère de M9 hors MECeF).'),
];
