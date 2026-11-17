// LE REGISTRE DES PARAMÈTRES DÉCLARÉS (lot L0) : ce que les paramètres du poste proposent, avec leur défaut SEMÉ.
//
// C'est une DONNÉE, pas du code de gestion : le poste en sème la version 0 dans la collection `parametres` au premier démarrage (même fiche sur tous les postes,
// voir [Parametres.semer]) ; la valeur en vigueur se LIT ensuite dans la base, par [Parametres.resoudre], jamais ici. Chaque lot déclare ses paramètres dans cette
// liste, avec la source de son défaut. Aucun taux, aucune date, aucun numéro n'est inventé. BAGUIDI : les six défauts ci-dessous viennent de la réplique d'origine
// (décisions de SA Direction) ; la Direction de Baguidi n'en a arrêté aucun, ils s'affichent donc comme valeurs d'attente à confirmer, et se règlent aux Paramètres
// par une version datée. Celui de l'AIB ne dit rien de la décision D4 de Baguidi (« les deux, selon la situation de l'émetteur », DECISIONS-2026-11-09) : il n'est
// pas branché et la décision se porte par le barème des situations, pas par ce réglage.
//
// `branche: false` : le réglage s'enregistre et se synchronise, mais l'écran qu'il commande ne le lit pas encore (lot à venir) ; l'écran des paramètres le dit.
// Le lot L3 a branché `mecef.mode` (lu par la normalisation, voir `src/mecef/mode.dart`). Les lots L5 et L6 ont branché `planning.circuitPresences` et
// `planning.agentModifieDirectement` (lus par le moteur du planning RH, `src/rh/planning_rh.dart`, et par la maquette). Les lots L7 et L8 ont branché
// `paie.copieFichePaieTelephone` (`src/rh/espace_mes.dart`), `planning.badgeSertDePointage` et `planning.delaiEntrePointagesBadge` (`src/rh/pointage_badge.dart`).
// AIB (lot L2 de la réplique d'origine) : les quatre réglages de l'AIB sont DÉCLARÉS (graine du registre, vecteurs `aib.json`, domaine `src/comptabilite/aib.dart`) mais NON
// BRANCHÉS à Baguidi. Baguidi écrit déjà la retenue d'AIB à la facture fournisseur (`cpd_retenue_aib`, pièce plate 401000/4478 en brouillon, barème des situations et
// `parametresAib`) : brancher « l'AIB sur les écritures d'achat » ajouterait un second écrivain de la même retenue, et la décision D4 (« les deux, selon la situation de
// l'émetteur », aucune écriture d'AIB subi) interdit de faire dépendre une écriture du réglage « qui supporte le prélèvement ».
// Le lot ORG2 a branché `securite.delaiVerrouPosteSecours` (`src/securite/verrou_secours.dart`, lu par le verrou de session d'un poste désigné de secours).
// Aucune de ces définitions n'est envoyée au téléphone (`mobile: false`) : la liste blanche est vide tant qu'un lot ne démontre pas le besoin (RG-13).

import '../mecef/imprimante_caisse.dart' show cleImprimanteModele, cleImprimanteLargeurPapier, cleImprimanteInterface, imprimanteLargeurDefautMm;
import '../sauvegarde/sauvegarde_horssite.dart';
import '../droits/gestes_reserves.dart' show gesteReglerLimiteExport, gestePtaRegler, gesteFiscalConfirmer, gesteFactureTiersEmettre;
import '../mecef/facture_tiers_payeur.dart' show factureTiersCleSignataires;
import '../administration/pta.dart' show ptaCleDecoupage, ptaClePrefixe, ptaCleSeuilRetard, ptaCleSignataires;
import '../paie/pai_baremes.dart';
import '../configuration/cfb_donnees.dart' show cfbCcibTotal;
import '../rh/rhc_regles.dart' show rhcCleMontantStandard, rhcMontantStandardSemence;
import '../administration/adm_regles.dart' show admCleForfaitAmbulance, admClePrixKmAmbulance, admForfaitAmbulanceSemence, admPrixKmAmbulanceSemence;
import 'parametres.dart';
import 'reglages_roles.dart';
import '../validation/decisions_en_attente.dart' show cleDelaiAlerteMere;

const String _reprise = 'Valeur de la graine du code (calendrier du comptable, réunion du 19/08/2026) : à confirmer par la Direction de Baguidi';
const String _decisions = 'Valeur d\'attente reprise de la réplique d\'origine : à confirmer par la Direction de Baguidi';

const List<DefinitionParametre> definitionsParametres = [
  DefinitionParametre(
    cle: 'mecef.mode',
    famille: 'mecef',
    type: TypeParametre.choix,
    choix: ['boitier', 'emecef'],
    libellesChoix: {'boitier': 'Boîtier physique', 'emecef': 'e-MECeF'},
    defaut: 'boitier',
    libelle: 'Mode de certification des factures',
    aide: 'Boîtier physique ou e-MECeF. Aucun numéro n\'est simulé au poste : sans adaptateur configuré, la vente reste en attente de certification. Le mode e-MECeF reste « non configuré : dossier d\'interface DGI requis ».',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L3 (MECeF)',
  ),
  // Le MODÈLE du boîtier MECeF (décision de la Direction de Baguidi du 16/11/2026) : un réglage de CLINIQUE (famille R par la collection `parametres`, la mère seule
  // écrit, jamais vers un téléphone), réglé sous le geste `reglage_mecef`. Il NOMME l'appareil sur l'écran de configuration, sur la pièce et au journal MECeF ; il ne
  // branche AUCUN protocole : l'intégration (interface, commandes, certificat) n'est documentée nulle part dans le dépôt (docs/guides/MECEF-BOITIER-ELTRADE-CC300.md).
  DefinitionParametre(
    cle: 'mecef.modeleBoitier',
    famille: 'mecef',
    type: TypeParametre.texte,
    defaut: 'ELTRADE CC300',
    libelle: 'Modèle du boîtier MECeF',
    aide: 'Le modèle de l\'appareil de certification (mode « Boîtier physique »). Il nomme l\'appareil à l\'écran, sur la pièce et au journal MECeF ; il ne branche aucun protocole : l\'adaptateur reste non configuré tant que l\'éditeur du boîtier n\'a pas fourni son intégration.',
    source: 'Décision de la Direction de Baguidi du 16/11/2026 (docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md) : le boîtier MECeF de Baguidi est un ELTRADE CC300',
    branche: true,
    appliquePar: 'Configuration MECeF, pièce et journal MECeF',
  ),
  // L'IMPRIMANTE DE CAISSE (décision de la Direction de Baguidi du 16/11/2026, E3761) : trois réglages de CLINIQUE de la famille `mecef` (réglés sous le geste
  // `reglage_mecef`, à l'écran « Configuration fiscale »). AUCUN modèle n'est fourni pour Baguidi : modèle et interface sont semés VIDES (« à renseigner », à
  // valider) ; la largeur est semée à 80 mm, le gabarit du ticket de la maquette, à valider. Ils DÉCRIVENT l'appareil, ils ne branchent aucun pilote d'impression :
  // seule la largeur est lue, par l'aperçu et le PDF du ticket de caisse (`src/mecef/imprimante_caisse.dart`).
  DefinitionParametre(
    cle: cleImprimanteModele,
    famille: 'mecef',
    type: TypeParametre.texte,
    defaut: '',
    libelle: 'Imprimante de caisse — modèle',
    aide: 'Le modèle de l\'imprimante du ticket de caisse. Aucun modèle n\'est fourni pour Baguidi : à renseigner par la clinique. Il décrit l\'appareil, il ne branche aucun pilote d\'impression.',
    source: 'Décision de la Direction de Baguidi du 16/11/2026 (docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md, §8) : aucun modèle fourni, valeur à renseigner, à valider',
    branche: true,
    appliquePar: 'Configuration fiscale (affiché)',
  ),
  DefinitionParametre(
    cle: cleImprimanteLargeurPapier,
    famille: 'mecef',
    type: TypeParametre.entier,
    defaut: imprimanteLargeurDefautMm,
    libelle: 'Imprimante de caisse — largeur du papier (mm)',
    aide: 'La largeur du rouleau, de 40 à 120 mm : l\'aperçu et le PDF du ticket de caisse la prennent. Hors de ces bornes, le ticket garde 80 mm et l\'écran le dit.',
    source: 'Gabarit du ticket de caisse de la maquette (rouleau 80 mm, P.ticket) ; décision de la Direction de Baguidi du 16/11/2026 : valeur d\'attente, à valider par la clinique',
    branche: true,
    appliquePar: 'Ticket de caisse 80 mm (aperçu et PDF)',
  ),
  DefinitionParametre(
    cle: cleImprimanteInterface,
    famille: 'mecef',
    type: TypeParametre.texte,
    defaut: '',
    libelle: 'Imprimante de caisse — interface',
    aide: 'Comment l\'imprimante est reliée au poste (par exemple USB, série, réseau), telle que la clinique la décrit. Aucune n\'est fournie pour Baguidi : à renseigner. Aucun pilote n\'est branché.',
    source: 'Décision de la Direction de Baguidi du 16/11/2026 (docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md, §8) : aucune interface fournie, valeur à renseigner, à valider',
    branche: true,
    appliquePar: 'Configuration fiscale (affiché)',
  ),
  DefinitionParametre(
    cle: 'bareme_aib.chargePrelevement',
    famille: 'bareme_aib',
    type: TypeParametre.choix,
    choix: ['clinique', 'acheteur'],
    libellesChoix: {'clinique': 'La clinique', 'acheteur': 'L\'acheteur'},
    defaut: 'clinique',
    libelle: 'Qui supporte le prélèvement de l\'AIB',
    aide: 'Décision D4 de Baguidi : les deux, selon la situation de l\'émetteur ; communiqué de la DGI et comptes confirmés par l\'expert-comptable à obtenir. Réglage non branché : aucune écriture d\'AIB subi n\'en dépend.',
    source: _decisions,
    branche: false,
  ),
  DefinitionParametre(
    cle: 'bareme_aib.branchementAchats',
    famille: 'bareme_aib',
    type: TypeParametre.choix,
    choix: ['desactive', 'actif'],
    libellesChoix: {'desactive': 'Désactivé (le moteur liste, n\'écrit rien)', 'actif': 'Activé (écrit ce qui est listé)'},
    defaut: 'desactive',
    libelle: 'Brancher l\'AIB sur les écritures d\'achat',
    aide: 'Différé par décision de la Direction : désactivé par défaut. L\'activation exige le compte d\'acompte, le compte de contrepartie et la charge arrêtés (refus nommé sinon).',
    source: _decisions,
    branche: false,
  ),
  DefinitionParametre(
    cle: 'bareme_aib.compteAcompte',
    famille: 'bareme_aib',
    type: TypeParametre.texte,
    defaut: '',
    libelle: 'Compte d\'acompte (débit)',
    aide: 'Choisi par le comptable dans le plan comptable : aucun numéro n\'est proposé d\'office (vide tant qu\'il n\'est pas choisi).',
    source: _decisions,
    branche: false,
  ),
  DefinitionParametre(
    cle: 'bareme_aib.compteContrepartie',
    famille: 'bareme_aib',
    type: TypeParametre.texte,
    defaut: '',
    libelle: 'Compte de contrepartie (crédit)',
    aide: 'Choisi par le comptable dans le plan comptable : une écriture s\'équilibre sur deux comptes que la clinique désigne (vide tant qu\'il n\'est pas choisi).',
    source: _decisions,
    branche: false,
  ),
  DefinitionParametre(
    cle: 'planning.circuitPresences',
    famille: 'planning',
    type: TypeParametre.choix,
    choix: ['surveillant', 'daf', 'surveillant_puis_daf'],
    libellesChoix: {'surveillant': 'Surveillant seul', 'daf': 'Directrice administrative seule', 'surveillant_puis_daf': 'Surveillant puis directrice administrative'},
    defaut: 'surveillant',
    libelle: 'Circuit de validation des présences et absences',
    aide: 'Surveillant seul, directrice administrative seule, ou surveillant puis directrice administrative. Congés et ordres de mission suivent le même circuit.',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L5 (circuit des présences)',
  ),
  DefinitionParametre(
    cle: 'planning.agentModifieDirectement',
    famille: 'planning',
    type: TypeParametre.booleen,
    defaut: false,
    libelle: 'L\'agent modifie directement son planning',
    aide: 'Non : l\'agent propose, le surveillant valide.',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L6 (propositions de planning)',
  ),
  DefinitionParametre(
    cle: 'paie.copieFichePaieTelephone',
    famille: 'paie',
    type: TypeParametre.booleen,
    defaut: true,
    libelle: 'Copie chiffrée de la fiche de paie sur le téléphone',
    aide: 'Oui : l\'agent garde sur son téléphone une copie chiffrée de sa propre fiche de paie ÉMISE (diffusée), jamais celle d\'un autre, jamais l\'ensemble de la paie, jamais recalculée à l\'appareil. Le réglage lui-même ne va PAS au téléphone (famille « paie » réservée) : la mère décide de publier ou de retirer la copie.',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L7 (espace « Mes »)',
  ),

  // LES TAUX ET LE BARÈME DE LA PAIE (lot 1 de l'inventaire des valeurs en dur, 16/11/2026) : la CNSS, le VPS et le barème de l'ITS quittent les constantes du moteur de
  // paie. Défaut SEMÉ = la valeur d'avant (aucun bulletin ne change) ; le moteur les lit À LA DATE DU BULLETIN (`pai_baremes.dart`). Famille RÉSERVÉE (jamais vers un
  // téléphone) et à réglage DÉDIÉ : une version nouvelle se pose par la confirmation fiscale, sous le geste `fiscal_confirmer`, avec un motif — jamais par le panneau générique.
  DefinitionParametre(
    cle: paiCleCnssOuvriere,
    famille: paiFamilleBaremes,
    type: TypeParametre.nombre,
    defaut: paiCnssOuvriereSemence,
    libelle: 'CNSS — part ouvrière (% du brut)',
    aide: 'Retenue sur le salaire brut après sanction, à chaque bulletin. Une version nouvelle prend effet à une date : un bulletin se calcule au taux en vigueur le premier jour de sa période ; un bulletin déjà généré garde le sien.',
    source: 'CDCT §10.10 (D.PARAM_PAIE de la maquette) : 3,6 %, sans plafond',
    branche: true,
    appliquePar: 'Moteur de paie (bulletin, cotisations, pilotage)',
    geste: gesteFiscalConfirmer,
  ),
  DefinitionParametre(
    cle: paiCleCnssPatronale,
    famille: paiFamilleBaremes,
    type: TypeParametre.nombre,
    defaut: paiCnssPatronaleSemence,
    libelle: 'CNSS — part patronale (% du brut)',
    aide: 'Charge de l\'employeur, non déduite du net. Versionnée par date comme la part ouvrière.',
    source: 'CDCT §10.10 (D.PARAM_PAIE de la maquette) : 16,4 %, sans plafond',
    branche: true,
    appliquePar: 'Moteur de paie (bulletin, cotisations, pilotage)',
    geste: gesteFiscalConfirmer,
  ),
  DefinitionParametre(
    cle: paiCleVps,
    famille: paiFamilleBaremes,
    type: TypeParametre.nombre,
    defaut: paiVpsTauxSemence,
    libelle: 'VPS — versement patronal de solidarité (% du brut)',
    aide: 'Charge de l\'employeur, non déduite du net. Versionnée par date.',
    source: 'CDCT §10.10 (D.PARAM_PAIE de la maquette) : 4 % du salaire brut',
    branche: true,
    appliquePar: 'Moteur de paie (bulletin, cotisations, pilotage)',
    geste: gesteFiscalConfirmer,
  ),
  DefinitionParametre(
    cle: paiCleBaremeIts,
    famille: paiFamilleBaremes,
    type: TypeParametre.texte,
    defaut: paiBaremeItsSemence,
    libelle: 'Barème progressif de l\'ITS',
    aide: 'Tranches [plancher, plafond, taux %], la dernière sans plafond. Le barème semé est celui de la maquette, « à confirmer par le service comptable » : il reste marqué à confirmer tant qu\'aucune confirmation ne cite le texte qui le fonde.',
    source: 'Maquette (D.PARAM_PAIE.its) : à confirmer par le service comptable, aucun texte cité',
    branche: true,
    appliquePar: 'Moteur de paie (ITS de chaque bulletin)',
    geste: gesteFiscalConfirmer,
  ),
  // LA PRIME D'ANCIENNETÉ (complément du lot 1) : deux copies en dur (moteur de paie, fiche d'évaluation NS 131) remplacées par deux paramètres datés, lus par une règle.
  DefinitionParametre(
    cle: paiCleAncienneteTaux,
    famille: paiFamilleBaremes,
    type: TypeParametre.nombre,
    defaut: paiAncienneteTauxSemence,
    libelle: 'Prime d\'ancienneté — taux par année (% du salaire de base)',
    aide: 'Le taux appliqué par année d\'ancienneté, au salaire de base. Lu à la date du bulletin ; un bulletin déjà généré garde le sien.',
    source: 'Maquette (m11-paie.js, prime d\'ancienneté) : 2 % par année, à confirmer par la Direction de Baguidi',
    branche: true,
    appliquePar: 'Moteur de paie et fiche d\'évaluation NS 131',
    geste: gesteFiscalConfirmer,
  ),
  DefinitionParametre(
    cle: paiCleAncienneteSeuil,
    famille: paiFamilleBaremes,
    type: TypeParametre.entier,
    defaut: paiAncienneteSeuilAnsSemence,
    libelle: 'Prime d\'ancienneté — à partir de (années)',
    aide: 'Le nombre d\'années d\'ancienneté à partir duquel la prime est due. Entier de 0 à 40.',
    source: 'Maquette (m11-paie.js, prime d\'ancienneté) : à partir de 2 ans, à confirmer par la Direction de Baguidi',
    branche: true,
    appliquePar: 'Moteur de paie et fiche d\'évaluation NS 131',
    geste: gesteFiscalConfirmer,
  ),
  // LA TVA DU RÉGIME NORMAL (complément du lot 1) : 18 % écrits dans le référentiel fiscal. Le RÉGIME se choisit à la configuration fiscale (exonéré à Baguidi) ; son taux
  // normal est daté, lu à la date de la pièce.
  DefinitionParametre(
    cle: paiCleTvaNormal,
    famille: paiFamilleBaremes,
    type: TypeParametre.nombre,
    defaut: paiTvaNormalSemence,
    libelle: 'TVA — taux du régime normal (%)',
    aide: 'Appliqué quand la configuration fiscale retient le régime normal (Baguidi : régime exonéré, produits et actes de santé). Versionné par date.',
    source: 'Référentiel fiscal de la maquette (D.PARAM_FISCAL.regimesTva) : 18 %',
    branche: true,
    appliquePar: 'Facturation normalisée (MECeF) au régime normal',
    geste: gesteFiscalConfirmer,
  ),
  // LA PARTICIPATION STANDARD AUX ÉVÉNEMENTS DU PERSONNEL (lot 1) : le montant proposé par agent quand l'événement n'en porte pas. Elle transite (ni recette ni charge).
  DefinitionParametre(
    cle: rhcCleMontantStandard,
    famille: 'rh',
    type: TypeParametre.entier,
    defaut: rhcMontantStandardSemence,
    libelle: 'Participation standard par agent aux événements du personnel (FCFA)',
    aide: 'Proposée à la création d\'un événement (mariage, naissance, décès…) et reprise quand le montant saisi est vide ou nul. Un événement déjà créé garde le montant qu\'il porte.',
    source: 'Usage de la clinique repris de la maquette (vague 21) : 1 000 F, à confirmer par la Direction de Baguidi',
    branche: true,
    appliquePar: 'Événements du personnel (m10-evenements)',
  ),
  DefinitionParametre(
    cle: 'planning.badgeSertDePointage',
    famille: 'planning',
    type: TypeParametre.booleen,
    defaut: true,
    libelle: 'Le badge sert de pointage',
    aide: 'Oui : un badge vérifié valide crée une présence « à valider » au registre (arrivée, puis départ au passage suivant), qui suit le circuit de validation des présences.',
    source: _decisions,
    branche: true,
    appliquePar: 'Lot L8 (badge et pointage)',
  ),

  // --- Calendrier fiscal (Baguidi, 10/11/2026) : les seuils et le montant qui vivaient en dur dans les moteurs. Ils sont BRANCHÉS : le suivi des échéances et
  // la configuration fiscale lisent la valeur en vigueur AUJOURD'HUI (versionnée par date, jamais réécrite). Le défaut est celui de la graine du code.
  DefinitionParametre(
    cle: 'fiscal.delaiAPayerJours',
    famille: 'fiscal',
    type: TypeParametre.entier,
    defaut: 10,
    libelle: 'Échéance « à payer » : délai d\'alerte (jours)',
    aide: 'Une échéance non réglée devient « à payer » quand elle tombe dans ce délai ; l\'alerte sonore de l\'ouverture suit le même délai.',
    source: _reprise,
  ),
  DefinitionParametre(
    cle: 'fiscal.delaiDeclarationJours',
    famille: 'fiscal',
    type: TypeParametre.entier,
    defaut: 30,
    libelle: 'Échéance « déclaration attendue » : délai (jours)',
    aide: 'Quand une déclaration précède le paiement, l\'échéance passe « déclaration attendue » dans ce délai. Doit rester supérieur au délai « à payer ».',
    source: _reprise,
  ),
  DefinitionParametre(
    cle: 'fiscal.ccibMontant',
    famille: 'fiscal',
    type: TypeParametre.entier,
    defaut: cfbCcibTotal,
    libelle: 'CCIB : contribution annuelle (FCFA)',
    aide: 'Réglée en deux tranches égales (mars et juin). Montant à confirmer par le cabinet comptable ; il s\'affiche aux indicateurs de la fiscalité et à la configuration fiscale.',
    source: _reprise,
  ),
  DefinitionParametre(
    cle: 'planning.delaiEntrePointagesBadge',
    famille: 'planning',
    type: TypeParametre.entier,
    defaut: 5,
    libelle: 'Délai minimal entre deux pointages par badge (minutes)',
    aide: 'Deux passages du même badge plus rapprochés sont refusés. Entier de 0 à 720 ; 0 ne refuse jamais. Valeur d\'attente de 5 minutes : aucun document ne la fixe, proposition à valider par la Direction.',
    source: 'Proposition à valider (lot L8) : aucun document ne fixe ce délai',
    branche: true,
    appliquePar: 'Lot L8 (badge et pointage)',
  ),
  DefinitionParametre(
    cle: 'securite.delaiVerrouPosteSecours',
    famille: 'securite',
    type: TypeParametre.entier,
    defaut: 5,
    libelle: 'Délai de verrou d\'un poste de secours (minutes)',
    aide: 'Un poste partagé de secours, où un agent sans téléphone ouvre sa propre session, se verrouille plus vite qu\'un poste ordinaire. Entier de 1 à 120. Valeur d\'attente de 5 minutes proposée par l\'équipe : aucun document ne la fixe, à valider par la Direction. Le délai ordinaire de 15 minutes (CDCT 12.2, politique de sécurité) ne change pas. Quel poste est « de secours » se désigne à ce poste même (donnée locale, jamais synchronisée).',
    source: 'Proposition à valider (décision P3 du 11/11/2026) : aucun document ne fixe ce délai',
    branche: true,
    appliquePar: 'Lot ORG2 (verrou d\'un poste de secours)',
  ),
  // Lot BAK (ADR-0008) : la sauvegarde hors site (relais web ou dossier distant) est un réglage de CLINIQUE posé à la poste mère, versionné par date, reçu des fileuls, JAMAIS envoyé à un téléphone
  // (`mobile: false`, famille réservée). Désactivée par défaut ; elle se règle à l'écran « Sauvegarde hors site » (droit, motif, refus nommés), pas au panneau générique.
  DefinitionParametre(
    cle: shCleActif,
    famille: 'horssite',
    type: TypeParametre.booleen,
    defaut: false,
    libelle: 'Copie hors site active',
    aide: 'Désactivée par défaut : l\'administrateur ou la Directrice Administrative l\'active à la main, une fois une destination choisie. Réglage de la clinique, posé à la poste mère.',
    source: 'Décision de la Direction du 15/11/2026 (« il faut l’implémenter ») : lot BAK, ADR-0008',
    branche: true,
    appliquePar: 'Lot BAK (sauvegarde hors site)',
  ),
  DefinitionParametre(
    cle: shCleDestinationMagasin,
    famille: 'horssite',
    type: TypeParametre.choix,
    choix: ['aucune', 'relais', 'dossier'],
    libellesChoix: {'aucune': 'Aucune', 'relais': 'Relais web', 'dossier': 'Dossier distant monté'},
    defaut: 'relais',
    libelle: 'Destination de la copie du magasin',
    aide: 'Relais web par défaut (proposition) : la copie de la base de la mère est petite (quelques Mo). Aucune : ce type de copie n\'est pas fait.',
    source: 'Proposition à valider (lot BAK, ADR-0008) : aucun document ne fixe cette valeur',
    branche: true,
    appliquePar: 'Lot BAK (sauvegarde hors site)',
  ),
  DefinitionParametre(
    cle: shCleDestinationFichiers,
    famille: 'horssite',
    type: TypeParametre.choix,
    choix: ['aucune', 'relais', 'dossier'],
    libellesChoix: {'aucune': 'Aucune', 'relais': 'Relais web', 'dossier': 'Dossier distant monté'},
    defaut: 'aucune',
    libelle: 'Destination de la copie des fichiers numérisés',
    aide: 'Aucune par défaut (proposition) : le volume des scans n\'est pas mesuré et l\'espace d\'un hébergement mutualisé est borné. À choisir par la Direction : relais web ou dossier distant monté.',
    source: 'Décision de la Direction du 15/11/2026 (Q33, DECISIONS-Q1-42) : « Aucune » tant que le volume des fichiers n\'est pas mesuré (voir docs/guides/mesurer-le-quota-du-relais.md)',
    branche: true,
    appliquePar: 'Lot BAK (sauvegarde hors site)',
  ),
  DefinitionParametre(
    cle: shCleDossierMagasin,
    famille: 'horssite',
    type: TypeParametre.texte,
    defaut: '',
    libelle: 'Dossier distant du magasin',
    aide: 'Chemin complet d\'un dossier monté (partage réseau, disque d\'un autre site) ; vide : aucun. Sert si la destination est « dossier distant ». SFTP n\'est pas fait.',
    source: 'Proposition à valider (lot BAK, ADR-0008) : aucun document ne fixe cette valeur',
    branche: true,
    appliquePar: 'Lot BAK (sauvegarde hors site)',
  ),
  DefinitionParametre(
    cle: shCleDossierFichiers,
    famille: 'horssite',
    type: TypeParametre.texte,
    defaut: '',
    libelle: 'Dossier distant des fichiers',
    aide: 'Chemin complet d\'un dossier monté ; vide : aucun. Sert si la destination est « dossier distant ». SFTP n\'est pas fait.',
    source: 'Proposition à valider (lot BAK, ADR-0008) : aucun document ne fixe cette valeur',
    branche: true,
    appliquePar: 'Lot BAK (sauvegarde hors site)',
  ),
  DefinitionParametre(
    cle: shCleFrequence,
    famille: 'horssite',
    type: TypeParametre.entier,
    defaut: shFrequenceDefaut,
    libelle: 'Fréquence de la copie des fichiers (minutes)',
    aide: 'Entier de 15 à 1440. Une heure par défaut : incrémentale, peu coûteuse tant que rien ne change.',
    source: 'Proposition à valider (lot BAK, ADR-0008) : copie des fichiers toutes les heures, valeur de la clinique sœur',
    branche: true,
    appliquePar: 'Lot BAK (sauvegarde hors site)',
  ),
  DefinitionParametre(
    cle: shCleHeureControle,
    famille: 'horssite',
    type: TypeParametre.entier,
    defaut: shHeureControleDefaut,
    libelle: 'Heure du contrôle nocturne',
    aide: 'Entier de 0 à 23 (heure locale de la mère). Le contrôle nocturne copie le magasin et vérifie les copies hors site. 2 h par défaut.',
    source: 'Proposition à valider (lot BAK, ADR-0008) : contrôle chaque nuit, l\'heure est une proposition',
    branche: true,
    appliquePar: 'Lot BAK (sauvegarde hors site)',
  ),
  DefinitionParametre(
    cle: shCleCopiesMagasin,
    famille: 'horssite',
    type: TypeParametre.entier,
    defaut: shCopiesMagasinDefaut,
    libelle: 'Copies du magasin gardées',
    aide: 'Entier de 2 à 60. Les plus anciennes sont archivées (restaurables), jamais supprimées tant que l\'espace le permet. 7 par défaut, comme la copie locale.',
    source: 'Décision de la Direction du 15/11/2026 (Q31, DECISIONS-Q1-42) : lot BAK, ADR-0008',
    branche: true,
    appliquePar: 'Lot BAK (sauvegarde hors site)',
  ),
  DefinitionParametre(
    cle: shCleCopiesFichiers,
    famille: 'horssite',
    type: TypeParametre.entier,
    defaut: shCopiesFichiersDefaut,
    libelle: 'Copies des fichiers gardées',
    aide: 'Entier de 2 à 60. Une copie des fichiers est un état complet (les blocs sont partagés entre copies). 14 par défaut.',
    source: 'Décision de la Direction du 15/11/2026 (Q31, DECISIONS-Q1-42) : lot BAK, ADR-0008',
    branche: true,
    appliquePar: 'Lot BAK (sauvegarde hors site)',
  ),
  DefinitionParametre(
    cle: shCleTailleBloc,
    famille: 'horssite',
    type: TypeParametre.entier,
    defaut: shTailleBlocDefaut,
    libelle: 'Taille d\'un bloc (octets)',
    aide: 'Entier de 65 536 à 4 194 304. 1 048 576 par défaut : sous la plus petite limite de requête PHP courante des hébergements mutualisés (non mesurée sur le vrai hébergement).',
    source: 'Décision de la Direction du 15/11/2026 (Q31, DECISIONS-Q1-42) : lot BAK, ADR-0008',
    branche: true,
    appliquePar: 'Lot BAK (sauvegarde hors site)',
  ),
  DefinitionParametre(
    cle: shCleBlocsControles,
    famille: 'horssite',
    type: TypeParametre.entier,
    defaut: shBlocsControlesDefaut,
    libelle: 'Blocs téléchargés et vérifiés chaque nuit',
    aide: 'Entier de 0 à 200. Chaque nuit, des blocs de la dernière copie sont téléchargés, déchiffrés et vérifiés de bout en bout (0 : seule la présence est contrôlée).',
    source: 'Proposition à valider (lot BAK, ADR-0008) : aucun document ne fixe cette valeur',
    branche: true,
    appliquePar: 'Lot BAK (sauvegarde hors site)',
  ),
  // Q10 (décision du 15/11/2026) : le préavis de péremption vivait en CONSTANTE (90 jours) dans le stock, les alertes, les indicateurs et l'assistant. C'est un réglage de clinique,
  // versionné par date : une alerte émise sous l'ancien délai ne se réécrit jamais.
  DefinitionParametre(
    cle: 'stock.delaiPreavisPeremptionJours',
    famille: 'stock',
    type: TypeParametre.entier,
    defaut: 90,
    libelle: 'Préavis de péremption (jours)',
    aide: 'Un lot est « à péremption proche » quand sa date tombe dans ce nombre de jours (RG-05). Entier de 1 à 730 ; une valeur hors bornes retombe sur 90. Se règle par une NOUVELLE VERSION datée (jamais écrasée) ; lu par les lots, les alertes, les tableaux de bord et l\'assistant.',
    source: 'Décision de la Direction du 15/11/2026 (Q10, DECISIONS-Q1-42) : 90 jours semés, versionné par date',
    branche: true,
    appliquePar: 'Lot AST-2 (péremption, assistant)',
  ),
  // Relecture des 100 questions d'agents (Direction, 16/11/2026) : la durée sans sortie qui fait d'un article un « article immobile » était un littéral de l'assistant (30 jours).
  DefinitionParametre(
    cle: 'stock.joursArticlesImmobiles',
    famille: 'stock',
    type: TypeParametre.entier,
    defaut: 30,
    libelle: 'Articles immobiles : durée sans sortie (jours)',
    aide: 'Un article en stock est « immobile » (ne tourne plus) quand il n\'a eu aucune sortie depuis ce nombre de jours. Entier de 1 à 730 ; une valeur hors bornes retombe sur 30. Lu par l\'assistant quand la question ne dit pas la durée ; versionné par date. Valeur d\'attente, à valider.',
    source: 'Décision de la Direction du 16/11/2026 (relecture des questions d\'agents, DECISIONS-16-11) : 30 jours d\'attente, à valider',
    branche: true,
    appliquePar: 'Lot assistant (articles immobiles)',
  ),
  // Q14 : les bornes de la balance âgée des patients (30 et 90 jours) sont un réglage de clinique, plus un littéral d'écran ni d'assistant.
  DefinitionParametre(
    cle: 'comptabilite.balanceAgeePatientBorne1Jours',
    famille: 'comptabilite',
    type: TypeParametre.entier,
    defaut: 30,
    libelle: 'Balance âgée des patients : première borne (jours)',
    aide: 'Les impayés patients sont rangés en quatre tranches : jusqu\'à la première borne, jusqu\'à la seconde, au-delà de la seconde. Entier de 1 à 365, strictement inférieur à la seconde borne ; sinon les valeurs semées (30 et 90) s\'appliquent. À valider par la Direction.',
    source: 'Décision de la Direction du 15/11/2026 (Q14, DECISIONS-Q1-42) : 30 et 90 jours semés — valeur d\'attente, à valider',
    branche: true,
    appliquePar: 'Lot AST-2 (balance âgée patients, assistant)',
  ),
  DefinitionParametre(
    cle: 'comptabilite.balanceAgeePatientBorne2Jours',
    famille: 'comptabilite',
    type: TypeParametre.entier,
    defaut: 90,
    libelle: 'Balance âgée des patients : seconde borne (jours)',
    aide: 'Voir la première borne. Entier de 2 à 730, strictement supérieur à la première borne. À valider par la Direction.',
    source: 'Décision de la Direction du 15/11/2026 (Q14, DECISIONS-Q1-42) : 30 et 90 jours semés — valeur d\'attente, à valider',
    branche: true,
    appliquePar: 'Lot AST-2 (balance âgée patients, assistant)',
  ),
  DefinitionParametre(
    cle: 'assistant.retentionJours',
    famille: 'assistant',
    type: TypeParametre.entier,
    defaut: 30,
    libelle: 'Conservation des conversations de l\'assistant (jours)',
    aide: 'Les conversations avec l\'assistant sont propres au poste et à l\'agent, chiffrées, jamais synchronisées ; elles sont purgées après ce nombre de jours. Entier de 1 à 90 : une valeur hors bornes retombe sur 30. Décision de la Direction du 15/11/2026 (30 jours).',
    source: 'Décision de la Direction du 15/11/2026 (conversations conservées 30 jours, réglable, borné)',
    branche: true,
    appliquePar: 'Lot AST-1 (assistant)',
  ),
  // --- Export des tableaux (Q40, Direction du 15/11/2026) : AUCUNE valeur codée en dur dans l'export ; les trois réglages vivent en base. AK (16/11/2026) : la limite de
  // lignes par export n'existe plus par défaut (0 = aucune limite) ; les deux autres valeurs d'attente restent « à fixer sur la plus grande table réelle ».
  DefinitionParametre(
    cle: 'export.limiteLignes',
    famille: 'export',
    type: TypeParametre.entier,
    defaut: 0,
    libelle: 'Nombre maximal de lignes par export (0 = aucune limite)',
    aide: 'Par défaut AUCUNE limite : seul le droit d\'exporter compte (décision AK du 16/11/2026). Si la clinique fixe une limite (entier d\'au moins 1), un export au-delà est REFUSÉ en le disant, jamais tronqué en silence. 0 ou vide : aucune limite.',
    source: 'Décision de la Direction du 16/11/2026 (AK) : pas de limite de lignes par défaut, seul le droit d\'export compte (remplace la valeur d\'attente de Q40, « à fixer sur la plus grande table réelle »)',
    branche: true,
    appliquePar: 'Chantier TABLEAUX (export)',
    // Section 7 (16/11/2026) : la limite se règle par un GESTE RÉSERVÉ, pas par le seul droit d'éditer l'écran des paramètres.
    geste: gesteReglerLimiteExport,
  ),
  DefinitionParametre(
    cle: 'export.seuilProgression',
    famille: 'export',
    type: TypeParametre.entier,
    defaut: 2000,
    libelle: 'Seuil d\'affichage du compteur de progression (lignes)',
    aide: 'À partir de ce nombre de lignes, l\'export se déroule par lots avec un compteur et un bouton Annuler. Entier d\'au moins 1. Valeur d\'attente : à fixer sur la plus grande table réelle.',
    source: 'Valeur d\'attente (décision Q40 du 15/11/2026) : à fixer sur la plus grande table réelle',
    branche: true,
    appliquePar: 'Chantier TABLEAUX (export)',
  ),
  DefinitionParametre(
    cle: 'export.limiteEtatsParLigne',
    famille: 'export',
    type: TypeParametre.entier,
    defaut: 100,
    libelle: 'Nombre maximal d\'états imprimés d\'un coup (un état par ligne)',
    aide: 'Quand « Imprimer la sélection » produit un état par ligne cochée, au-delà de ce nombre l\'impression est REFUSÉE en le disant ; le tableau unique n\'est pas concerné. Entier d\'au moins 1. Valeur d\'attente : à fixer à l\'usage.',
    source: 'Valeur d\'attente (décision Q42 du 15/11/2026) : à fixer à l\'usage',
    branche: true,
    appliquePar: 'Chantier TABLEAUX (impression de la sélection)',
  ),

  // Section AI (Direction, 16/11/2026) : une décision prise sur un fileul et non appliquée par la mère au-delà de ce délai s'ALERTE (notification de poste au validateur concerné et à
  // l'administrateur). Aucun blocage, aucune validation automatique. BRANCHÉ : lu à chaque vérification par `AlerteDecisionsMere` et par la pastille.
  DefinitionParametre(
    cle: cleDelaiAlerteMere,
    famille: 'validations',
    type: TypeParametre.entier,
    defaut: 4,
    libelle: 'Décision en attente de la mère : délai d’alerte (heures)',
    aide: 'Une validation, une demande de prix ou une demande d’import déposée sur un fileul et que la mère n’a pas appliquée au-delà de ce délai déclenche une alerte vers le validateur concerné (rôles qui détiennent le geste, lus dans la matrice) et l’administrateur. Rien n’est bloqué, rien n’est validé à la place de la mère. Entier d’au moins 1.',
    source: 'Décision de la Direction du 16/11/2026 (section AI) : 4 heures',
    branche: true,
    appliquePar: 'Continuité des validations (pastille et alerte des décisions en attente de la mère)',
  ),

  // Q4 de la Direction de Baguidi (17/11/2026) : le POSTE porté sur la pièce ; QUI valide n'est plus un réglage mais le geste réservé `achats_valider` de la fiche RBAC (Direction du 16/11/2026) —
  // l'ancienne clé `achats.rolesValidateurs` est retirée du registre (voir `reglages_roles.dart`). Q3 (écritures d'inventaire en clôture) n'est plus un réglage non plus : le geste réservé
  // `cloture_inventaire` (point 7 du 17/11/2026) ; la clé `cloture.rolesInventaire` est retirée de la même façon.
  DefinitionParametre(
    cle: cleLibelleValidateurAchats,
    famille: 'achats',
    type: TypeParametre.texte,
    defaut: 'Directrice administrative',
    libelle: 'Poste validateur porté sur les pièces d\'achat',
    aide: 'Le POSTE (jamais le nom d\'une personne) écrit sur un bon arbitré ou une commande validée. L\'agent réel qui a validé est porté à part.',
    source: 'Décision de la Direction du 17/11/2026 (Q4) : le poste de la Directrice Administrative',
    branche: true,
    appliquePar: 'Circuit d\'achats (m7-besoins, m7-commandes)',
  ),
  // LIGNE SANS PRIX SUR UNE FACTURE (Direction de Baguidi, 16/11/2026, complément §7) : par défaut RIEN d'une facture ne s'encaisse tant qu'une ligne attend son prix (« prix à
  // valoriser », « prix assuré à définir »). Oui : on revient à l'encaissement ligne par ligne de la v21 (les autres lignes s'encaissent). Réglage de CLINIQUE (famille R : la mère seule
  // écrit, les fileuls le reçoivent), posé sous le geste réservé `reglage_encaissement_sans_prix` depuis n'importe quel poste (un fileul dépose, la mère applique).
  DefinitionParametre(
    cle: cleEncaisserResteSansPrix,
    famille: 'caisse',
    type: TypeParametre.booleen,
    defaut: false,
    libelle: 'Encaisser le reste d\'une facture qui a une ligne sans prix',
    aide: 'Non (par défaut) : tant qu\'une ligne de la facture attend son prix (prix à valoriser, prix assuré à définir), RIEN de la facture ne s\'encaisse et la pharmacie ne délivre rien. Oui : les autres lignes s\'encaissent, la ligne sans prix reste en attente, nommée, et la pharmacie délivre les lignes réglées.',
    source: 'Décision de la Direction de Baguidi du 16/11/2026 (docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md, §7) : rien ne s\'encaisse par défaut',
    branche: true,
    appliquePar: 'Caisse (m8-caisse) et délivrance',
  ),
  // LE PLAN DE TRAVAIL ANNUEL (lot PTA, Direction de Baguidi, 17/11/2026 : « RIEN NE DOIT ÊTRE EN DUR »). Deux réglages de CLINIQUE (famille R par la collection
  // `parametres` : la mère seule écrit, chaque version datée), posés sous le geste réservé `pta_regler` depuis n'importe quel poste (un fileul dépose, la mère applique).
  // La clinique n'a AUCUN modèle officiel de PTA : les trois réglages sont ceux du MODÈLE PROPOSÉ par la Direction (16/11/2026), à valider.
  DefinitionParametre(
    cle: ptaCleDecoupage,
    famille: 'pta',
    type: TypeParametre.choix,
    choix: ['trimestre', 'mois', 'semestre'],
    libellesChoix: {'trimestre': 'Par trimestre', 'mois': 'Par mois', 'semestre': 'Par semestre'},
    defaut: 'trimestre',
    libelle: 'Découpage du plan de travail annuel',
    aide: 'Les périodes de la frise du plan et du choix des périodes d\'une action. Un exercice se lit avec le découpage en vigueur à son jour courant (un exercice clos, à son dernier jour) : changer le découpage ne réécrit aucune action, qui garde ses dates.',
    source: 'Modèle proposé le 16/11/2026, à valider : périodicité trimestrielle (proposition à valider par la Direction)',
    branche: true,
    appliquePar: 'Plan de travail annuel (m13-plan-annuel)',
    geste: gestePtaRegler,
  ),
  DefinitionParametre(
    cle: ptaCleSeuilRetard,
    famille: 'pta',
    type: TypeParametre.entier,
    defaut: 15,
    libelle: 'Seuil d\'alerte de retard d\'une action du plan (jours)',
    aide: 'Une action non terminée dont la période est échue depuis PLUS que ce nombre de jours est en retard : elle est comptée à l\'écran et lève une alerte vers les détenteurs du geste « alerte de retard du plan ». Entier positif ou nul.',
    source: 'Modèle proposé le 16/11/2026, à valider : 15 jours après la fin de la période (proposition à valider par la Direction)',
    branche: true,
    appliquePar: 'Plan de travail annuel (m13-plan-annuel) et centre de notifications',
    geste: gestePtaRegler,
  ),
  DefinitionParametre(
    cle: ptaClePrefixe,
    famille: 'pta',
    type: TypeParametre.texte,
    defaut: 'PTA',
    libelle: 'Préfixe de la numérotation des actions du plan',
    aide: 'Les actions se numérotent « <préfixe>-<exercice>-NNN », série annuelle. Majuscules et chiffres, 1 à 12 caractères ; une valeur illisible retombe sur le défaut. Changer le préfixe ne renumérote aucune action et ne redonne jamais un rang déjà attribué dans l\'exercice.',
    source: 'Modèle proposé le 16/11/2026, à valider : numérotation PTA-<exercice>-NNN (proposition à valider par la Direction)',
    branche: true,
    appliquePar: 'Plan de travail annuel (m13-plan-annuel)',
    geste: gestePtaRegler,
  ),
  // LES SIGNATAIRES DU PLAN (Direction de Baguidi, 16/11/2026 : « RIEN en dur ») : le plan et son bilan s'impriment avec les signataires que l'ORGANIGRAMME désigne (le titulaire du
  // poste) ; ce réglage nomme les POSTES qui signent. Vide, le poste qui coiffe l'organigramme signe : aucun intitulé ni nom n'est écrit dans le code.
  DefinitionParametre(
    cle: ptaCleSignataires,
    famille: 'pta',
    type: TypeParametre.texte,
    defaut: '',
    libelle: 'Postes signataires du plan de travail annuel et de son bilan',
    aide: 'Les POSTES de l\'organigramme (intitulé ou code, séparés par un point-virgule) dont la signature figure sur le plan et sur son bilan imprimés ; leur titulaire est lu à l\'organigramme, jamais saisi ici. Vide : le poste qui coiffe l\'organigramme signe. Un poste absent de l\'organigramme s\'imprime tel qu\'écrit, sans nom.',
    source: 'Décision de la Direction de Baguidi du 16/11/2026 (docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md, §9) : rien en dur, signataires lus à l\'organigramme',
    branche: true,
    appliquePar: 'Plan de travail annuel (m13-plan-annuel) : impression du plan et du bilan',
    geste: gestePtaRegler,
  ),

  // LES SIGNATAIRES DE LA FACTURE À UNE ENTREPRISE (Direction de Baguidi, 17/11/2026, « RIEN en dur ») : la pièce imprimée porte les postes que la clinique désigne ; leur titulaire est lu à
  // l'organigramme. Vide, le poste qui coiffe l'organigramme signe. Aucun intitulé de poste ni nom n'est écrit dans le code.
  DefinitionParametre(
    cle: factureTiersCleSignataires,
    famille: 'caisse',
    type: TypeParametre.texte,
    defaut: '',
    libelle: 'Postes signataires de la facture à une entreprise',
    aide: 'Les POSTES de l\'organigramme (intitulé ou code, séparés par un point-virgule) dont la signature figure sur la facture à une entreprise imprimée ; leur titulaire est lu à l\'organigramme, jamais saisi ici. Vide : le poste qui coiffe l\'organigramme signe. Un poste absent de l\'organigramme s\'imprime tel qu\'écrit, sans nom. L\'acheteur signe toujours une ligne « Reçu le / Signature » : ce n\'est pas un poste de la clinique.',
    source: 'Décision de la Direction de Baguidi du 16/11/2026 (docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md, §9) : rien en dur, signataires lus à l\'organigramme ; pièce du point 2 du 17/11/2026',
    branche: true,
    appliquePar: 'Facture à une entreprise (m9-facture-mere) : impression de la pièce',
    geste: gesteFactureTiersEmettre,
  ),

  // LE TARIF D'UNE COURSE D'AMBULANCE SANS MONTANT SAISI (lot 1 de l'inventaire des valeurs en dur) : 5 000 F + 500 F par kilomètre vivaient en dur dans le moteur. Aucun
  // document ne fixe ce tarif (il n'est pas au catalogue) : ce sont des PROPOSITIONS À VALIDER, réglables par une version datée. Une course saisie avec son montant le garde.
  DefinitionParametre(
    cle: admCleForfaitAmbulance,
    famille: 'ambulance',
    type: TypeParametre.entier,
    defaut: admForfaitAmbulanceSemence,
    libelle: 'Course d\'ambulance sans montant saisi : forfait (FCFA)',
    aide: 'Proposé quand la course est enregistrée sans montant : forfait + kilomètres × prix au kilomètre. Valeur d\'attente, à valider par la Direction.',
    source: 'Proposition à valider : valeur de la maquette, aucun document ne fixe le tarif d\'une course',
    branche: true,
    appliquePar: 'Interventions de l\'ambulance (m13)',
  ),
  DefinitionParametre(
    cle: admClePrixKmAmbulance,
    famille: 'ambulance',
    type: TypeParametre.entier,
    defaut: admPrixKmAmbulanceSemence,
    libelle: 'Course d\'ambulance sans montant saisi : prix au kilomètre (FCFA)',
    aide: 'Ajouté au forfait pour chaque kilomètre parcouru. Valeur d\'attente, à valider par la Direction.',
    source: 'Proposition à valider : valeur de la maquette, aucun document ne fixe le tarif d\'une course',
    branche: true,
    appliquePar: 'Interventions de l\'ambulance (m13)',
  ),
];

/// La clé du réglage « encaisser le reste d'une facture qui a une ligne sans prix » (Non par défaut).
const String cleEncaisserResteSansPrix = 'caisse.encaisserResteLigneSansPrix';

/// La valeur lue du réglage : seul un `true` explicite rouvre l'encaissement ligne par ligne ; toute autre valeur (absente, illisible) garde le défaut, rien ne s'encaisse.
bool encaisserResteSansPrixDe(Object? valeur) => valeur == true;

/// Le libellé d'une famille de paramètres, pour les onglets de l'écran des paramètres. Une famille absente de la table s'affiche sous son identifiant.
const Map<String, String> libellesFamillesParametres = {
  'mecef': 'MECeF',
  'bareme_aib': 'AIB',
  'planning': 'Planning et présences',
  'paie': 'Paie',
  'fiscal': 'Calendrier fiscal',
  'securite': 'Sécurité',
  'horssite': 'Sauvegarde hors site',
  'assistant': 'Assistant',
  'stock': 'Stock et péremption',
  'comptabilite': 'Comptabilité et recouvrement',
  'export': 'Export des tableaux',
  'cloture': 'Clôture comptable',
  'achats': 'Achats',
  'validations': 'Validations et continuité',
  'caisse': 'Caisse et encaissement',
  'pta': 'Plan de travail annuel',
  paiFamilleBaremes: 'Taux et barèmes de la paie',
  'rh': 'Ressources humaines',
  'ambulance': 'Ambulance',
};

/// La définition d'une clé, ou `null`.
DefinitionParametre? definitionDeParametre(String cle) {
  for (final d in definitionsParametres) {
    if (d.cle == cle) return d;
  }
  return null;
}
