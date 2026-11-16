/// LE CATALOGUE D'INTENTIONS de l'assistant : une intention = UNE question, à source et droit DÉCLARÉS. C'est la source UNIQUE de la reconnaissance, des exécuteurs,
/// du tableau de couverture (AST-0) et des droits : ajouter une intention est ajouter une ligne ici (et son exécuteur), jamais toucher au moteur.
///
/// Statuts (mesurés dans le code, jamais supposés) :
///  * `calculable` : la donnée ET la règle existent, la réponse est une lecture ou un filtre de champs existants ;
///  * `petit_lot` : la donnée existe mais une définition ou une agrégation manque (dite dans la réponse) ;
///  * `non_disponible` : la donnée ou le contenu n'existe pas — l'intention n'est PAS livrée (`actif: false`), elle figure au tableau pour qu'on sache pourquoi.
///
/// Les clés de refus sont celles de [refusAst]. Aucun nom de rôle ici : le droit d'une intention est la liste d'ÉCRANS dont l'agent doit en voir un, lue dans la
/// matrice en force (`MatriceDroits`), jamais comparée à un rôle.
library;

import 'ast_texte.dart';

/// Un indice de reconnaissance : une ou plusieurs formes consécutives (`*` final = préfixe), et son poids (1 indice, 2 net, 3 fort, 4 et plus décisif).
typedef IndiceAst = (String, int);

class IntentionAst {
  const IntentionAst({
    required this.id,
    required this.groupe,
    required this.libelle,
    required this.ecransLecture,
    required this.sources,
    required this.statut,
    required this.raison,
    required this.indices,
    this.requis = const [],
    this.futurOk = false,
    this.historique = false,
    this.refus = const ['LECTURE_NON_AUTORISEE', 'AUCUN_RESULTAT'],
    this.actif = true,
    this.exemple = '',
  });

  final String id;
  final String groupe;
  final String libelle;

  /// Les écrans de LECTURE : l'agent doit en voir au moins un (matrice en force). Vide : intention ouverte à tout agent authentifié (aucune donnée métier lue).
  final List<String> ecransLecture;

  /// Chaque source est « chemin : fonctions ou collections » LUE dans le code — le test de couverture vérifie que le fichier existe et nomme chaque fonction.
  final List<String> sources;
  final String statut;
  final String raison;
  final List<IndiceAst> indices;

  /// Les paramètres obligatoires (`patient`, `acte`, `article`, `fournisseur`) : sans eux, la réponse demande une précision au lieu de deviner.
  final List<String> requis;

  /// Une période future a un sens (échéances, garde de demain, péremptions à venir).
  final bool futurOk;

  /// L'historique à une date passée est LISIBLE (prix, couverture, factures datées). Faux : l'état n'est conservé qu'à aujourd'hui (stock), la date passée est « non calculable ».
  final bool historique;
  final List<String> refus;
  final bool actif;
  final String exemple;
}

/// Les refus et réactions NOMMÉS : un code, ce qui est dit, et le geste proposé. Aucun refus n'est muet.
class RefusAst {
  const RefusAst(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
}

const Map<String, RefusAst> refusAst = {
  'LECTURE_NON_AUTORISEE': RefusAst('LECTURE_NON_AUTORISEE', 'votre fonction ne lit pas cet écran', 'demander l’accès à l’administrateur'),
  'INTENTION_INCONNUE': RefusAst('INTENTION_INCONNUE', 'la question ne rentre dans aucune intention du catalogue', 'reformuler ou choisir parmi les intentions proches'),
  'ECRITURE_ABSENTE': RefusAst('ECRITURE_ABSENTE', 'l’assistant n’écrit rien : la commande n’existe pas ici', 'ouvrir l’écran concerné et valider soi-même'),
  'AVIS_MEDICAL_REFUSE': RefusAst('AVIS_MEDICAL_REFUSE', 'aucune aide au diagnostic ni avis thérapeutique', 'consulter le dossier si le droit existe, ou le médecin'),
  'ENVOI_EXTERNE_REFUSE': RefusAst('ENVOI_EXTERNE_REFUSE', 'rien ne quitte la clinique', 'imprimer l’état depuis l’écran concerné'),
  'INJONCTION_REFUSEE': RefusAst('INJONCTION_REFUSEE', 'les règles et les droits ne se contournent pas par la conversation', 'poser une question du catalogue'),
  'PRECISION_REQUISE': RefusAst('PRECISION_REQUISE', 'un paramètre obligatoire manque', 'préciser le patient, l’article, l’acte ou le fournisseur'),
  'QUESTION_AMBIGUE': RefusAst('QUESTION_AMBIGUE', 'plusieurs intentions possibles', 'choisir parmi les intentions proposées'),
  'NON_CALCULABLE_HISTORIQUE': RefusAst('NON_CALCULABLE_HISTORIQUE', 'l’historique à cette date n’est pas conservé', 'lire l’état d’aujourd’hui'),
  'PERIODE_FUTURE': RefusAst('PERIODE_FUTURE', 'la période demandée n’a pas commencé', 'choisir une période échue'),
  'AUCUN_RESULTAT': RefusAst('AUCUN_RESULTAT', 'aucun enregistrement ne correspond', 'vérifier l’orthographe ou ouvrir la liste'),
  'HOMONYMES': RefusAst('HOMONYMES', 'plusieurs correspondances', 'choisir dans la liste, jamais la première'),
  'NON_CALCULABLE': RefusAst('NON_CALCULABLE', 'la donnée nécessaire n’est pas renseignée', 'la saisir à l’écran indiqué'),
  'ERREUR_INTERNE': RefusAst('ERREUR_INTERNE', 'le calcul a échoué', 'réessayer, ou ouvrir l’écran concerné'),
  // Q16 (décision du 15/11/2026) : AUCUNE intention de paie en v1, sans exception — salaires, bulletins, primes, retenues et cotisations salariales ne se lisent PAS par l'assistant. Le refus se nomme.
  'PAIE_HORS_ASSISTANT': RefusAst('PAIE_HORS_ASSISTANT', 'la paie n’est pas du ressort de l’assistant : aucune question de paie n’est traitée, sans exception', 'ouvrir l’écran de la paie si votre profil y a droit, ou demander à la personne habilitée'),
  'ASSISTANT_INDISPONIBLE': RefusAst('ASSISTANT_INDISPONIBLE', 'l’assistant est désactivé ou le profil n’a pas de poste', 'demander à l’administrateur'),
};

/// Les secteurs nommables par un mot seul : une question réduite à ce mot est AMBIGUË, elle propose les trois intentions les plus proches.
const Map<String, List<String>> domainesAst = {
  'pharmacie': ['I07', 'I08', 'I10'],
  'stock': ['I07', 'I08', 'I10'],
  'laboratoire': ['I19', 'I05', 'I08'],
  'caisse': ['I14', 'I15', 'I16'],
  'comptabilite': ['I14', 'I16', 'I25'],
  'maternite': ['I04', 'I20', 'I05'],
  'fournisseur': ['I12', 'I13', 'I16'],
  'patient': ['I01', 'I02', 'I03'],
  'imagerie': ['I19', 'I05', 'I21'],
};

/// Les écrans d'ÉCRITURE vers lesquels une commande refusée renvoie (mots de la demande → écran).
const List<({List<String> mots, String ecran})> ecransEcritureAst = [
  (mots: ['facture', 'avoir'], ecran: 'm8-facture-avoir'),
  (mots: ['sortie', 'stock', 'boites', 'boite'], ecran: 'm6-mouvements'),
  (mots: ['encaisse', 'paiement', 'francs', 'caisse'], ecran: 'm8-caisse'),
  (mots: ['prix', 'tarif'], ecran: 'cfg-tarifs'),
  (mots: ['patient', 'dossier'], ecran: 'm1-patients'),
  (mots: ['commande'], ecran: 'm7-commandes'),
  (mots: ['ordonnance'], ecran: 'm2-ordonnances'),
];


/// Les 27 lignes du tableau de couverture : 25 intentions LIVRÉES (`actif`) et 2 candidates non disponibles, tracées pour mémoire.
const List<IntentionAst> catalogueAstDefaut = [
  IntentionAst(
    id: 'I01',
    groupe: 'Patients (M1)',
    libelle: 'Retrouver un patient (nom ou code)',
    ecransLecture: ['m1-patients'],
    sources: ['packages/domaine/lib/src/referentiels/regles.dart : lireCodePatient, reCodePatient', 'packages/domaine/lib/src/patients/pat_patients.dart : patAge ; collection `patients`'],
    statut: 'petit_lot',
    raison: 'L’identité se lit sur `patients`. Aucune fonction du domaine ne cherche par nom (la recherche est un filtre d’écran) : la recherche tolérante et la liste d’homonymes sont écrites ici. '
        '« Dernière venue » n’a aucune définition au cahier : elle est PROPOSÉE (la plus récente date parmi les consultations, admissions et factures que l’agent peut lire) et la réponse la nomme.',
    indices: [('retrouve', 2), ('cherche', 2), ('trouve', 2), ('patient', 2), ('patiente', 2), ('dossier', 1), ('identite', 2), ('derniere visite', 4), ('derniere venue', 4), ('naissance', 1), ('qui est', 1)],
    requis: ['patient'],
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'HOMONYMES', 'AUCUN_RESULTAT', 'PRECISION_REQUISE'],
    exemple: 'Retrouve le patient EXEMPLE/Patient',
  ),
  IntentionAst(
    id: 'I02',
    groupe: 'Patients (M1)',
    libelle: 'Validité de l’assurance à la date du jour ou à une date',
    ecransLecture: ['m1-patients', 'm9-assures', 'm8-facturation'],
    sources: ['packages/domaine/lib/src/caisse/prise_en_charge.dart : carteValide, couvertureALaDate (RG-09, couverture datée)'],
    statut: 'calculable',
    raison: 'RG-09 se lit à la date par le moteur de la caisse ; une carte absente se dit « aucune carte », jamais « invalide » ni zéro.',
    indices: [('assurance', 4), ('assure', 2), ('assureur', 2), ('mutuelle', 3), ('carte', 1), ('valide', 1), ('valable', 1), ('validite', 2), ('jusqu a quand', 2), ('compagnie', 2), ('couverture', 2), ('prise en charge', 3)],
    requis: ['patient'],
    futurOk: true,
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'PRECISION_REQUISE', 'AUCUN_RESULTAT', 'HOMONYMES'],
    exemple: 'La carte d’assurance de EXEMPLE/Patient est-elle valide ?',
  ),
  IntentionAst(
    id: 'I03',
    groupe: 'Facturation (M8)',
    libelle: 'Reste à payer et dernière facture d’un patient',
    ecransLecture: ['m8-factures', 'm8-reliquats', 'm8-caisse'],
    sources: ['collection `factures` : reliquat, statutPaiement, montantTTC, date (écrit par packages/domaine/lib/src/caisse/emission.dart : emettreFacture)'],
    statut: 'calculable',
    raison: 'La facture porte `reliquat` (part patient restant due) et `statutPaiement` ; le total dû est leur somme.',
    indices: [('doit encore', 4), ('reste a payer', 5), ('reste du', 3), ('solde', 4), ('reliquat', 3), ('derniere facture', 5), ('dernier paiement', 3), ('doit', 2)],
    requis: ['patient'],
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'PRECISION_REQUISE', 'AUCUN_RESULTAT', 'HOMONYMES'],
    exemple: 'Combien doit encore EXEMPLE/Patient ?',
  ),
  IntentionAst(
    id: 'I04',
    groupe: 'Hospitalisation (M3)',
    libelle: 'Admissions en cours, lit occupé, lits libres',
    ecransLecture: ['m3-admissions', 'm3-plan-lits'],
    sources: ['collection `admissions` : statut (en_cours), lit, chambre, dateEntree', 'collections `lits` et `chambres` (plan des lits)'],
    statut: 'calculable',
    raison: 'Les admissions en cours se lisent ; les lits libres exigent le plan des lits renseigné : sans lui, la réponse dit « non calculable » et ne devine pas.',
    indices: [('hospitalis*', 4), ('lits libres', 5), ('lit libre', 5), ('dans le lit', 4), ('lit', 3), ('lits', 3), ('occupe', 2), ('admission', 2), ('admissions', 2), ('chambre', 1), ('hospitalises', 4)],
    refus: ['LECTURE_NON_AUTORISEE', 'AUCUN_RESULTAT', 'NON_CALCULABLE'],
    exemple: 'Qui est hospitalisé en ce moment ?',
  ),
  IntentionAst(
    id: 'I05',
    groupe: 'Tarifs (CFG)',
    libelle: 'Prix d’un acte, d’une analyse ou d’un produit (deux prix, du jour ou à une date)',
    ecransLecture: ['cfg-tarifs', 'm8-facturation', 'm6-produits'],
    sources: ['packages/domaine/lib/src/tarifs/tarifs.dart : ReferentielTarifs.instantane, enVigueur, aLaDate (versions datées)', 'collection `produits` : prixVente (médicaments, RG-02)'],
    statut: 'calculable',
    raison: 'Le référentiel de prix est unique et daté : deux colonnes (non assuré, assuré), la version en vigueur à la date, la mention « valeur d’attente » quand la version est provisoire. '
        'Un tiret est une valeur manquante, jamais un zéro.',
    indices: [('prix', 4), ('tarif', 4), ('combien coute', 4), ('coute', 3), ('non assure', 3), ('combien pour', 1), ('facture a', 1)],
    requis: ['acte'],
    futurOk: true,
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'PRECISION_REQUISE', 'AUCUN_RESULTAT', 'HOMONYMES', 'NON_CALCULABLE'],
    exemple: 'Quel est le prix de la consultation généraliste ?',
  ),
  IntentionAst(
    id: 'I06',
    groupe: 'Tarifs (CFG)',
    libelle: 'Historique des changements de prix d’un acte',
    ecransLecture: ['cfg-tarifs'],
    sources: ['packages/domaine/lib/src/tarifs/tarifs.dart : ReferentielTarifs.versionsDe (collection `versionsTarif`)'],
    statut: 'calculable',
    raison: 'Chaque changement de prix est une version datée et motivée : l’historique est la liste de ces versions.',
    indices: [('prix', 3), ('ancien*', 5), ('historique', 4), ('chang*', 3), ('evolution', 2), ('versions', 2), ('avant', 1)],
    requis: ['acte'],
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'PRECISION_REQUISE', 'AUCUN_RESULTAT', 'HOMONYMES'],
    exemple: 'Historique du prix de la consultation généraliste',
  ),
  IntentionAst(
    id: 'I07',
    groupe: 'Pharmacie et stocks (M6)',
    libelle: 'Niveau d’un article (total, gros, détail), seuil, lots dans l’ordre FEFO',
    ecransLecture: ['m6-produits', 'm6-stock-gros', 'm6-stock-detail', 'm6-lots'],
    sources: ['packages/domaine/lib/src/stock/stock.dart : ordreFefo, etatStock, seuilFixe ; collections `produits` (stock, stockGros, stockDetail, seuilAlerte, emplacement) et `lots` (datePeremption, quantiteRestante, RG-05)'],
    statut: 'calculable',
    raison: 'Le stock se lit sur la fiche article ; l’ordre de sortie est le tri des lots par péremption (RG-05). Le stock n’est conservé qu’à aujourd’hui : une date passée est « non calculable ».',
    indices: [('stock', 3), ('combien reste', 4), ('il reste', 2), ('quantite', 2), ('par lot', 2), ('lot', 1), ('lots', 1), ('fefo', 3), ('sortir en premier', 4), ('disponible', 1), ('combien de', 2), ('en rayon', 2)],
    requis: ['article'],
    refus: ['LECTURE_NON_AUTORISEE', 'PRECISION_REQUISE', 'AUCUN_RESULTAT', 'HOMONYMES', 'NON_CALCULABLE_HISTORIQUE'],
    exemple: 'Combien reste-t-il de EXEMPLE/Article ?',
  ),
  IntentionAst(
    id: 'I08',
    groupe: 'Pharmacie et stocks (M6)',
    libelle: 'Articles en rupture, sous le seuil, proches de péremption',
    ecransLecture: ['m6-alertes', 'm6-produits', 'm6-lots'],
    sources: ['packages/domaine/lib/src/stock/stock.dart : sousSeuil, sousSeuilHorsRupture, sansSeuilFixe, joursAvantPeremption, delaiPreavisPeremption ; collections `produits` et `lots`'],
    statut: 'calculable',
    raison: 'Un article sans seuil fixé n’est pas « sous le seuil » : il est compté à part et signalé. L’horizon de péremption par défaut est de trois mois.',
    indices: [('rupture*', 5), ('sous le seuil', 5), ('seuil', 2), ('perim*', 4), ('perempt*', 4), ('reapprovisionnement', 2), ('a commander', 2), ('alerte', 1), ('manque', 2), ('manquent', 2), ('epuise*', 3)],
    futurOk: true,
    refus: ['LECTURE_NON_AUTORISEE', 'AUCUN_RESULTAT', 'NON_CALCULABLE_HISTORIQUE'],
    exemple: 'Quels articles sont en rupture ?',
  ),
  IntentionAst(
    id: 'I09',
    groupe: 'Pharmacie et stocks (M6)',
    libelle: 'Articles qui tournent et articles qui ne bougent plus',
    ecransLecture: ['m6-mouvements', 'm6-point-ventes'],
    sources: ['collection `mouvements` : type (sortie), quantite, date, produitId'],
    statut: 'petit_lot',
    raison: 'Les sorties sont datées et rattachées à un justificatif : le classement par quantité sortie se calcule. « Qui ne tourne plus » n’a aucune définition au cahier : elle est PROPOSÉE (aucune sortie sur la période) et dite dans la réponse.',
    indices: [('plus sortis', 5), ('plus sorti', 5), ('plus vendus', 5), ('top des sorties', 5), ('tourne*', 4), ('pas bouge', 5), ('bouge', 3), ('sans sortie', 4), ('rotation', 3), ('classement', 1), ('ne sortent plus', 5), ('dormants', 4)],
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'AUCUN_RESULTAT'],
    exemple: 'Quels sont les 5 articles les plus sortis ce mois-ci ?',
  ),
  IntentionAst(
    id: 'I10',
    groupe: 'Pharmacie et stocks (M6)',
    libelle: 'Valeur du stock au CUMP (par catégorie)',
    ecransLecture: ['m6-point-stock', 'm6-produits', 'm6-stock-gros'],
    sources: ['packages/domaine/lib/src/stock/stock.dart : valeurStock, libelleCategorie ; collection `produits` (stock, cump, categorie, valorisationProvisoire)'],
    statut: 'calculable',
    raison: 'Valeur = quantité × CUMP, par catégorie ; les références valorisées à titre provisoire sont comptées et signalées. Aucun axe de secteur n’existe au magasin : la ventilation est par catégorie d’article.',
    indices: [('valeur du stock', 6), ('valeur', 3), ('valorisation', 5), ('cump', 3), ('combien vaut', 5), ('vaut', 3), ('montant du stock', 5)],
    refus: ['LECTURE_NON_AUTORISEE', 'AUCUN_RESULTAT', 'NON_CALCULABLE_HISTORIQUE'],
    exemple: 'Quelle est la valeur du stock ?',
  ),
  IntentionAst(
    id: 'I11',
    groupe: 'Pharmacie et stocks (M6)',
    libelle: 'Inventaire : état du dernier, écarts',
    ecransLecture: ['m6-inventaire'],
    sources: ['collection `inventaires` : date, statutInv, nbArticles, nbEcarts, valeurEcart, lignes'],
    statut: 'calculable',
    raison: 'Le dernier inventaire porte son état, le nombre d’écarts, leur valeur et ses lignes.',
    indices: [('inventaire', 5), ('ecarts', 2), ('non comptes', 4), ('comptage', 3)],
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'AUCUN_RESULTAT'],
    exemple: 'Où en est le dernier inventaire ?',
  ),
  IntentionAst(
    id: 'I12',
    groupe: 'Achats (M7)',
    libelle: 'Fournisseur : coordonnées, commandes, dette ouverte',
    ecransLecture: ['m7-fournisseurs', 'm7-commandes', 'm7-factures-fournisseurs'],
    sources: ['collection `fournisseurs` : code, nom, ville, tel, delai', 'collection `commandes` : statutCommande', 'collection `facturesFournisseurs` : montantFacture, statutPaiement, echeance'],
    statut: 'calculable',
    raison: 'La dette ouverte est la somme des factures fournisseur non soldées. Un téléphone absent se dit « non renseigné » : aucun numéro n’est jamais déduit.',
    indices: [('fournisseur*', 5), ('livraisons', 2), ('livraison', 2), ('coordonnees', 2), ('contact', 1), ('devons', 3), ('doit on', 2)],
    requis: ['fournisseur'],
    refus: ['LECTURE_NON_AUTORISEE', 'PRECISION_REQUISE', 'AUCUN_RESULTAT', 'HOMONYMES'],
    exemple: 'Que devons-nous au fournisseur EXEMPLE/Fournisseur ?',
  ),
  IntentionAst(
    id: 'I13',
    groupe: 'Achats (M7)',
    libelle: 'Commandes en attente de validation (RG-04) et validateur',
    ecransLecture: ['m7-commandes'],
    sources: ['packages/domaine/lib/src/achats/commandes.dart : statuts (attente_validation, validee), valideePar, dateValidation'],
    statut: 'calculable',
    raison: 'RG-04 : une commande de stock gros est validée par la Directrice Administrative avant transmission ; l’état et le validateur sont portés par la commande.',
    indices: [('commande*', 4), ('attente', 2), ('validation', 2), ('valider', 2), ('valide', 1), ('bon de commande', 3)],
    refus: ['LECTURE_NON_AUTORISEE', 'AUCUN_RESULTAT'],
    exemple: 'Quelles commandes attendent une validation ?',
  ),
  IntentionAst(
    id: 'I14',
    groupe: 'Facturation (M8)',
    libelle: 'Recettes d’un jour, d’une semaine, d’un mois, ventilées',
    ecransLecture: ['m8-recettes', 'm8-operations', 'm8-caisse'],
    sources: ['collection `factures` : lignes (montantRegle, payeLe), montantTTC, date, type'],
    statut: 'calculable',
    raison: 'DEUX grandeurs, jamais confondues (décision du 15/11/2026) : les « recettes » sont l’ENCAISSÉ (somme des `montantRegle` dont la date de règlement tombe dans la période) ; le « chiffre d’affaires » est le FACTURÉ (montant TTC des factures datées de la période). Ventilation par type de facture.',
    indices: [('recette*', 5), ('chiffre d affaires', 5), ('encaisse', 3), ('encaisses', 3), ('ventes', 1), ('par secteur', 1), ('mode de paiement', 1), ('combien a t on fait', 3)],
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'PERIODE_FUTURE', 'AUCUN_RESULTAT'],
    exemple: 'Quelles sont les recettes de ce mois ?',
  ),
  IntentionAst(
    id: 'I15',
    groupe: 'Facturation (M8)',
    libelle: 'Factures et avoirs d’une période, factures non certifiées MECeF',
    ecransLecture: ['m8-factures', 'mecef-factures', 'm8-facture-avoir'],
    sources: ['collection `factures` : date, montantTTC, statutMecef', 'collection `avoirs` : reference, montant, statutMecef'],
    statut: 'calculable',
    raison: 'Une facture est « non certifiée » tant que son `statutMecef` n’est pas « valide » : le compte est un filtre, la certification elle-même est l’affaire de l’écran MECeF.',
    indices: [('factures', 3), ('facture', 2), ('avoir*', 4), ('mecef', 5), ('non certifie*', 3), ('emises', 2)],
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'PERIODE_FUTURE', 'AUCUN_RESULTAT'],
    exemple: 'Combien de factures non certifiées MECeF ?',
  ),
  IntentionAst(
    id: 'I16',
    groupe: 'Assurances et créances (M9)',
    libelle: 'Impayés des patients par ancienneté',
    ecransLecture: ['m9-creances', 'm8-reliquats'],
    sources: ['collection `factures` : reliquat, statutPaiement, date', 'packages/domaine/lib/src/caisse/prise_en_charge.dart : carteValide (la part assureur se lit à `m9-creances`)'],
    statut: 'petit_lot',
    raison: 'Les impayés PATIENT (reliquat des factures non soldées) se classent par ancienneté ; la part des assureurs est la créance de `m9-creances`, qu’une définition commune (même facture, même part) reste à poser : la réponse renvoie à cet écran au lieu de la recalculer.',
    indices: [('impaye*', 5), ('creance*', 5), ('anciennete', 3), ('nous doit', 5), ('debiteur*', 4), ('dettes des patients', 4), ('en retard de paiement', 4)],
    refus: ['LECTURE_NON_AUTORISEE', 'AUCUN_RESULTAT'],
    exemple: 'Quels impayés de plus de 30 jours ?',
  ),
  IntentionAst(
    id: 'I17',
    groupe: 'Patients (M1)',
    libelle: 'Retrouver les ordonnances et pièces délivrées à un patient',
    ecransLecture: ['m2-ordonnances', 'm1-pieces'],
    sources: ['collection `ordonnances` : numero, date, patientCode', 'collection `pieces` : reference, libelle, dateDelivrance, patientCode'],
    statut: 'petit_lot',
    raison: 'Les ordonnances et les pièces certifiantes se lisent par patient ; les documents numérisés (`documentsPatient`) suivent leur propre droit (zone 2) et ne sont pas lus ici.',
    indices: [('courrier*', 3), ('ordonnance*', 5), ('certificat*', 4), ('document*', 2), ('piece*', 3), ('attestation*', 3)],
    requis: ['patient'],
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'PRECISION_REQUISE', 'AUCUN_RESULTAT', 'HOMONYMES'],
    exemple: 'Les ordonnances de EXEMPLE/Patient',
  ),
  IntentionAst(
    id: 'I18',
    groupe: 'Tarifs (CFG)',
    libelle: 'Prix d’un certificat ou d’une attestation (consultation du prix seulement)',
    ecransLecture: ['cfg-types-piece', 'm1-pieces', 'cfg-tarifs'],
    sources: ['collection `typesPiece` : sigle, libelle, tarifCode', 'packages/domaine/lib/src/tarifs/tarifs.dart : ReferentielTarifs.aLaDate'],
    statut: 'calculable',
    raison: 'Chaque type de pièce désigne son code de tarif ; le prix est celui du référentiel unique. Les certificats ne sont couverts que par SOS : la réponse le dit.',
    indices: [('certificat*', 1), ('attestation*', 1)],
    futurOk: true,
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'AUCUN_RESULTAT', 'NON_CALCULABLE'],
    exemple: 'Combien coûte un certificat d’aptitude ?',
  ),
  IntentionAst(
    id: 'I19',
    groupe: 'Laboratoire (M5)',
    libelle: 'État d’une demande d’analyse, résultats RENDUS seulement',
    ecransLecture: ['m5-demandes', 'm5-resultats'],
    sources: ['packages/domaine/lib/src/labo/res_etats.dart : etatResultat', 'packages/domaine/lib/src/labo/res_habilitations.dart : peutVoirResultat (deux verrous, fonction, secteur)', 'collection `demandesAnalyses`'],
    statut: 'calculable',
    raison: 'L’état d’une demande est public aux postes habilités ; un RÉSULTAT ne se montre que s’il est validé biologiquement ET que l’agent y a droit (habilitation métier et catégorie sensible). Sinon la réponse dit pourquoi.',
    indices: [('analyse*', 4), ('demande d analyse', 4), ('resultat*', 4), ('echo', 3), ('imagerie', 2), ('radio', 2), ('hemogramme', 1), ('nfs', 1), ('valide', 1), ('etat de la demande', 3), ('bilan', 2)],
    requis: ['patient_ou_analyse'],
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'PRECISION_REQUISE', 'AUCUN_RESULTAT', 'HOMONYMES'],
    exemple: 'Où en sont les analyses de EXEMPLE/Patient ?',
  ),
  IntentionAst(
    id: 'I20',
    groupe: 'Ressources humaines (M10)',
    libelle: 'Qui est de garde ou de permanence à une date',
    ecransLecture: ['m10-planning', 'm10-stats-gardes'],
    sources: ['collection `planning` : date, type (garde, garde_soins, permanence), employe, service, statut (validee)'],
    statut: 'calculable',
    raison: 'Le planning VALIDÉ est la source ; un planning non validé n’est pas affiché comme acquis. Un jour sans ligne se dit « aucune garde posée », jamais « personne ».',
    indices: [('garde', 5), ('permanence', 5), ('planning', 4), ('de garde', 1), ('astreinte', 4)],
    futurOk: true,
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'AUCUN_RESULTAT'],
    exemple: 'Qui est de garde ce soir ?',
  ),
  IntentionAst(
    id: 'I21',
    groupe: 'Pilotage',
    libelle: 'Indicateurs du jour (consultations, admissions, analyses, factures)',
    ecransLecture: ['m2-consultations', 'm3-admissions', 'm5-demandes', 'm8-factures'],
    sources: ['collections `consultations`, `admissions`, `demandesAnalyses`, `factures` (comptes par jour)'],
    statut: 'calculable',
    raison: 'Chaque compte n’est donné que pour les écrans que l’agent voit ; les autres sont dits « hors de votre périmètre » et non comptés à zéro.',
    indices: [('tableau de bord', 6), ('indicateurs', 3), ('activite', 3), ('bilan du jour', 5), ('point du jour', 5)],
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'PERIODE_FUTURE'],
    exemple: 'Les indicateurs du jour',
  ),
  IntentionAst(
    id: 'I22',
    groupe: 'Système',
    libelle: 'Alertes ouvertes et état de la synchronisation',
    ecransLecture: [],
    sources: ['collection `notifications` : lue, priorite, libelle, poste', 'packages/domaine/lib/src/sync/pair.dart (état du poste : fourni par le poste, jamais deviné)'],
    statut: 'petit_lot',
    raison: 'Les notifications non lues se comptent ; l’état de la synchronisation appartient au poste (pas au magasin) : s’il n’est pas fourni, la réponse dit qu’elle ne le lit pas.',
    indices: [('synchro*', 5), ('mere', 3), ('fileul*', 4), ('retard', 2), ('a jour', 3), ('alerte*', 4), ('notification*', 4), ('poste', 1)],
    refus: ['AUCUN_RESULTAT', 'NON_CALCULABLE'],
    exemple: 'Quelles alertes sont ouvertes ?',
  ),
  IntentionAst(
    id: 'I23',
    groupe: 'Rapports (RAP)',
    libelle: 'Générer un rapport : ouvrir l’état existant',
    ecransLecture: ['rapports-bibliotheque'],
    sources: ['packages/domaine/lib/src/rapports/rap_regles.dart (bibliothèque des états)', 'écrans `rapports-bibliotheque`, `rapports-generateur`, `m8-recettes`, `m6-point-stock`'],
    statut: 'calculable',
    raison: 'L’assistant n’imprime rien : il nomme l’état et son écran (lien profond, si l’agent le voit). Le droit de l’état visé est celui de son écran.',
    indices: [('imprime*', 7), ('rapport*', 7), ('etat de', 2), ('etat des', 2), ('etat du', 2), ('rouleau', 3), ('80 mm', 2), ('genere*', 2), ('pdf', 3)],
    refus: ['LECTURE_NON_AUTORISEE', 'ENVOI_EXTERNE_REFUSE'],
    exemple: 'Je veux imprimer l’état des recettes du mois',
  ),
  IntentionAst(
    id: 'I24',
    groupe: 'Consultations (M2)',
    libelle: 'Rendez-vous du jour et file d’attente',
    ecransLecture: ['m2-agenda', 'm2-file-attente'],
    sources: ['collection `rendezvous` : date, patient, statut', 'collection `fileAttente`'],
    statut: 'calculable',
    raison: 'Les rendez-vous et la file d’attente se lisent par date. Les deux registres sont vides au jeu livré : la réponse dit « aucun enregistrement », ce qui n’est pas « personne n’attend ».',
    indices: [('rendez vous', 5), ('rdv', 5), ('agenda', 4), ('file d attente', 5), ('attente', 2), ('attendent', 3), ('consultation*', 1), ('programme', 2)],
    futurOk: true,
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'AUCUN_RESULTAT'],
    exemple: 'Les rendez-vous de demain',
  ),
  IntentionAst(
    id: 'I25',
    groupe: 'Comptabilité (M12)',
    libelle: 'Prochaines échéances fiscales et échéances en retard',
    ecransLecture: ['m12-echeances'],
    sources: ['collection `echeancesFiscales` : echeance, paye, libelle, periode (calendrier fiscal, `packages/domaine/lib/src/configuration/cfb_regles.dart`)'],
    statut: 'calculable',
    raison: 'Le calendrier fiscal est un référentiel de la configuration ; une échéance est « en retard » quand sa date est passée et qu’elle n’est pas payée.',
    indices: [('echeance*', 5), ('fiscal*', 4), ('impot*', 3), ('declaration*', 3), ('its', 2), ('cnss', 2), ('tva', 2), ('aib', 2), ('a payer', 2)],
    futurOk: true,
    historique: true,
    refus: ['LECTURE_NON_AUTORISEE', 'AUCUN_RESULTAT'],
    exemple: 'Quelles échéances fiscales sont en retard ?',
  ),
  IntentionAst(
    id: 'I26',
    groupe: 'Aide',
    libelle: 'Procédures : comment faire, où saisir, qui valide',
    ecransLecture: [],
    sources: ['aucune : aucune base de connaissances validée n’existe dans le dépôt (écran `aide-apropos` : texte fixe sur l’éditeur et le support)'],
    statut: 'non_disponible',
    raison: 'Le contenu des procédures n’existe pas : l’inventer serait précisément ce que l’assistant s’interdit. À écrire par la Direction (fiches de connaissance validées) avant tout lot.',
    indices: [('comment', 5), ('ou je saisis', 5), ('ou saisir', 5), ('procedure', 4)],
    actif: false,
    refus: ['INTENTION_INCONNUE'],
  ),
  IntentionAst(
    id: 'I27',
    groupe: 'Aide',
    libelle: 'Glossaire et règles de gestion (« c’est quoi… »)',
    ecransLecture: [],
    sources: ['aucune : les règles RG-01 à RG-14 vivent dans la documentation du dépôt, pas dans une collection du poste'],
    statut: 'non_disponible',
    raison: 'Aucune fiche de glossaire n’est portée au magasin du poste. Candidat à une base de connaissances validée par la Direction.',
    indices: [('c est quoi', 6), ('que veut dire', 6), ('qu est ce que', 6), ('definition', 5), ('signifie', 5)],
    actif: false,
    refus: ['INTENTION_INCONNUE'],
  ),
];

/// Le catalogue en force : celui du code, corrigé par les lignes de la collection `assistantIntentions` (ajouts de synonymes bornés, désactivation). Une ligne ne crée
/// JAMAIS une intention sans exécuteur : étendre le catalogue au-delà demande une ligne de code, et l'écran d'administration le dit.
class CatalogueAst {
  CatalogueAst._(this.intentions, this.surcharges);

  /// [lignes] : fiches de `assistantIntentions` : `{id, actif?, synonymes?: [{indice, poids}]}`.
  factory CatalogueAst([Iterable<Map<String, Object?>> lignes = const [], List<IntentionAst> base = catalogueAstDefaut]) {
    final par = <String, Map<String, Object?>>{};
    for (final l in lignes) {
      if (l['statut'] == 'archive') continue;
      final id = '${l['id']}';
      if (base.any((i) => i.id == id)) par[id] = l;
    }
    final out = <IntentionAst>[];
    for (final i in base) {
      final s = par[i.id];
      if (s == null) {
        out.add(i);
        continue;
      }
      final extra = <IndiceAst>[];
      for (final x in ((s['synonymes'] as List?) ?? const []).take(synonymesMax)) {
        if (x is! Map) continue;
        final indice = astNormaliser('${x['indice'] ?? ''}');
        final poids = x['poids'] is num ? (x['poids'] as num).toInt() : 2;
        if (indice.isEmpty || indice.length > 40) continue;
        extra.add((indice, poids.clamp(1, synonymePoidsMax)));
      }
      out.add(IntentionAst(
        id: i.id, groupe: i.groupe, libelle: i.libelle, ecransLecture: i.ecransLecture, sources: i.sources, statut: i.statut, raison: i.raison,
        indices: [...i.indices, ...extra], requis: i.requis, futurOk: i.futurOk, historique: i.historique, refus: i.refus, exemple: i.exemple,
        // une intention non disponible ne se réactive pas par une ligne : son exécuteur n'existe pas
        actif: i.statut == 'non_disponible' ? false : (s['actif'] != false) && i.actif,
      ));
    }
    return CatalogueAst._({for (final i in out) i.id: i}, par.keys.toSet());
  }

  /// Au plus ce nombre de synonymes lus par intention, et un poids plafonné : une ligne mal écrite ne peut pas faire basculer toute la reconnaissance.
  static const int synonymesMax = 20;
  static const int synonymePoidsMax = 3;

  final Map<String, IntentionAst> intentions;
  final Set<String> surcharges;

  IntentionAst? operator [](String id) => intentions[id];
  bool actif(String id) => intentions[id]?.actif == true;
  Iterable<IntentionAst> get actives => intentions.values.where((i) => i.actif);
}
