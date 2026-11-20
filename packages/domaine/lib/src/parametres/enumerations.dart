/// LES ÉNUMÉRATIONS STRUCTURELLES (lot « valeurs en dur », famille D, 18/11/2026) : des codes que la LOGIQUE lit pour décider (mode de paiement, famille de tarif, catégorie de produit,
/// nature de perte…). Un code est un INVARIANT d'algorithme : il vit ICI, dans UNE seule définition nommée, et n'est jamais recopié (la maquette en gardait deux ou trois copies de
/// plusieurs d'entre eux). Ce que la clinique peut vouloir changer, c'est le LIBELLÉ affiché : il vient du réglage `libelles.*` (voir [ListesReference.correspondance]), daté, jamais
/// écrasé. Changer un libellé ne change donc jamais une décision ; un code ajouté au réglage mais inconnu d'ici est ignoré (la logique ne saurait qu'en faire).
///
/// Les CODES d'une énumération sont ceux de la définition de son réglage (`definitions.dart`, valeur d'attente « code=Libellé ; … ») : UNE seule liste de codes, jamais une seconde
/// ici ni dans un écran. `enumerationsStructurelles` les liste toutes (le test de concordance les parcourt).
library;

import 'listes_reference.dart' show EnumCodes;

/// Modes de paiement.
const enumModesPaiement = EnumCodes('libelles.m8.modesPaiement');

/// Catégories de produit.
const enumCategoriesProduit = EnumCodes('libelles.m6.categoriesProduit');

/// Types de stock.
const enumTypesStock = EnumCodes('libelles.m6.typesStock');

/// Natures de perte.
const enumNaturesPerte = EnumCodes('libelles.m6.naturesPerte');

/// Familles de tarif.
const enumFamillesTarif = EnumCodes('libelles.cfg.famillesTarif');

/// Catégories de dépenses (lecture de gestion).
const enumCategoriesDepense = EnumCodes('libelles.m12.categoriesDepense');

/// Postes de la file d'attente.
const enumPostesFile = EnumCodes('libelles.m2.postesFile');

/// Services demandeurs d'un examen.
const enumServicesDemandeurs = EnumCodes('libelles.m5.servicesDemandeurs');

/// Fonctions du personnel (colonnes de la grille des primes).
const enumFonctionsPaie = EnumCodes('libelles.m11.fonctionsPaie');

/// Temps de l'examen physique.
const enumTempsExamen = EnumCodes('libelles.m1.tempsExamen');

/// Catégories d'antécédents.
const enumCategoriesAntecedent = EnumCodes('libelles.m1.categoriesAntecedent');

/// Types de question d'une enquête.
const enumTypesQuestion = EnumCodes('libelles.m13.typesQuestion');

/// Catégories de la GED.
const enumCategoriesDocument = EnumCodes('libelles.m13.categoriesDocument');

/// Types de planning.
const enumTypesPlanning = EnumCodes('libelles.m10.typesPlanning');

/// Catégories de garantie d'assurance.
const enumCategoriesGarantie = EnumCodes('libelles.m9.categoriesGarantie');

/// Catégories d'assurance d'un souscripteur.
const enumCategoriesAssurance = EnumCodes('libelles.m9.categoriesAssurance');

/// Natures de prêt ou d'avance.
const enumNaturesPret = EnumCodes('libelles.m11.naturesPret');

/// Motifs de rejet d'une transmission.
const enumCodesRejet = EnumCodes('libelles.mecef.codesRejet');

/// Toutes les énumérations structurelles (le test de concordance les parcourt).
const enumerationsStructurelles = <EnumCodes>[
  enumModesPaiement,
  enumCategoriesProduit,
  enumTypesStock,
  enumNaturesPerte,
  enumFamillesTarif,
  enumCategoriesDepense,
  enumPostesFile,
  enumServicesDemandeurs,
  enumFonctionsPaie,
  enumTempsExamen,
  enumCategoriesAntecedent,
  enumTypesQuestion,
  enumCategoriesDocument,
  enumTypesPlanning,
  enumCategoriesGarantie,
  enumCategoriesAssurance,
  enumNaturesPret,
  enumCodesRejet,
];
