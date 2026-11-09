// SOUS-LOT « STOCK, ACHATS, FACTURATION, CAISSE, COMPTABILITÉ » : produits, lots, mouvements, besoins, commandes, livraisons, factures fournisseurs,
// factures, encaissements, avoirs, créances, écritures, dépenses.
//
// CE FICHIER EST LE VÔTRE ET LE SEUL À MODIFIER pour ce sous-lot : `generer_jeu_baguidi.dart` l'appelle déjà, il n'y a rien à enregistrer ailleurs.
// Cette étape s'exécute EN DERNIER : elle lit les patients, consultations, prescriptions et bulletins des étapes précédentes (`ctx.fiches(...)`). Le plan
// comptable (`comptes`, avec les sous-comptes à six chiffres des moteurs), les actes, les tarifs, les assureurs et les entreprises souscriptrices sont
// déjà écrits par `socle.dart`. Règles communes : voir `tool/README.md` (tirage `ctx.tirageDe('stock_finance')`, horloge `Contexte.maintenant`, moteurs de
// `packages/domaine` : facture, encaissement, avoir, écriture ; chaque pièce comptable équilibrée par construction, RG-10).
import 'contexte.dart';

void generer(Contexte ctx) {
  // Rien à générer pour l'instant : les collections de stock, d'achats, de caisse et de comptabilité restent vides (`[]`).
}
