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
    aide: 'Boîtier physique ou e-MECeF. Aucun numéro n\'est simulé au poste ; le mode e-MECeF reste « non configuré : dossier d\'interface DGI requis ».',
    source: _decisions,
    branche: false,
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
    appliquePar: 'Lot L2 (AIB)',
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
    branche: false,
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
    branche: false,
    appliquePar: 'Lot L6 (propositions de planning)',
  ),
  DefinitionParametre(
    cle: 'paie.copieFichePaieTelephone',
    famille: 'paie',
    type: TypeParametre.booleen,
    defaut: true,
    libelle: 'Copie chiffrée de la fiche de paie sur le téléphone',
    aide: 'Oui : l\'agent garde une copie chiffrée de sa fiche de paie sur son téléphone.',
    source: _decisions,
    branche: false,
    appliquePar: 'Lot L7 (espace « Mes »)',
  ),
  DefinitionParametre(
    cle: 'planning.badgeSertDePointage',
    famille: 'planning',
    type: TypeParametre.booleen,
    defaut: true,
    libelle: 'Le badge sert de pointage',
    aide: 'Oui : le badge se relie au registre des présences.',
    source: _decisions,
    branche: false,
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
];

/// Le libellé d'une famille de paramètres, pour les onglets de l'écran des paramètres. Une famille absente de la table s'affiche sous son identifiant.
const Map<String, String> libellesFamillesParametres = {
  'mecef': 'MECeF',
  'bareme_aib': 'AIB',
  'planning': 'Planning et présences',
  'paie': 'Paie',
  'fiscal': 'Calendrier fiscal',
};

/// La définition d'une clé, ou `null`.
DefinitionParametre? definitionDeParametre(String cle) {
  for (final d in definitionsParametres) {
    if (d.cle == cle) return d;
  }
  return null;
}
