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

import 'parametres.dart';

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
    defaut: 300000,
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
];

/// Le libellé d'une famille de paramètres, pour les onglets de l'écran des paramètres. Une famille absente de la table s'affiche sous son identifiant.
const Map<String, String> libellesFamillesParametres = {
  'mecef': 'MECeF',
  'bareme_aib': 'AIB',
  'planning': 'Planning et présences',
  'paie': 'Paie',
  'fiscal': 'Calendrier fiscal',
  'securite': 'Sécurité',
};

/// La définition d'une clé, ou `null`.
DefinitionParametre? definitionDeParametre(String cle) {
  for (final d in definitionsParametres) {
    if (d.cle == cle) return d;
  }
  return null;
}
