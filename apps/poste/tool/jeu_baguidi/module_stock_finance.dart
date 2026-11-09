// SOUS-LOT « STOCK, ACHATS, CAISSE ET COMPTABILITÉ » (JEU-4), le dernier du jeu de démonstration : 150 produits (120 de pharmacie et d'intendance, 30 réactifs
// et consommables de laboratoire), leurs lots FEFO, un déroulé de mouvements du 01/08 au 07/11/2026, cinq fournisseurs fictifs, douze besoins, huit commandes
// validées par la Direction (RG-04), six livraisons avec procès-verbal, six factures fournisseurs, quarante ventes de pharmacie au comptoir, trente dépenses
// multi-lignes, la validation des pièces d'août et de septembre, les échéances fiscales de l'exercice 2026 et le suivi des créances d'assureurs.
//
// RIEN N'EST CALCULÉ À LA MAIN : chaque geste appelle le moteur de `packages/domaine` qui le porte au poste (voir `stock_simulation.dart`, `finance_caisse.dart`,
// `finance_compta.dart`). Cette étape s'exécute APRÈS la clinique et la paie : elle lit leurs factures et leurs écritures (en brouillon) et valide celles d'août et de
// septembre.
//
// CE QUI RESTE VIDE, ET POURQUOI : voir l'en-tête de `finance_compta.dart` (immobilisations, rapprochements, exercices, arrêtés de caisse) ; `dispensations`
// reste vide aussi : toute délivrance naît d'une ordonnance, et aucune ordonnance de la clinique ne porte de médicament (les ventes de pharmacie sont des
// ventes au comptoir, facturées sans dossier patient).
import 'contexte.dart';
import 'finance_caisse.dart';
import 'finance_compta.dart';
import 'stock_base.dart';
import 'stock_simulation.dart';

void generer(Contexte ctx) {
  final a = Atelier(ctx);
  final caisse = CaisseComptoir(a);
  final compta = Comptabilite(a, caisse);
  final stock = Stock(a, caisse, compta);

  stock.referentiels();
  stock.produitsEtOuverture();
  stock.derouler();
  stock.fixerLesSeuils();

  compta.depenses();
  compta.echeances();
  compta.creances();
  final pieces = compta.validerAoutSeptembre();

  ctx.note('stock : ${ctx.fiches('produits').length} produits, ${ctx.fiches('lots').length} lots, ${ctx.fiches('mouvements').length} mouvements, '
      '${ctx.fiches('transferts').length} transferts, ${ctx.fiches('inventaires').length} inventaires, ${ctx.fiches('emplacements').length} emplacements');
  ctx.note('achats : ${ctx.fiches('fournisseurs').length} fournisseurs, ${ctx.fiches('besoins').length} besoins, ${ctx.fiches('commandes').length} commandes, '
      '${ctx.fiches('livraisons').length} livraisons, ${ctx.fiches('pvReceptions').length} procès-verbaux, ${ctx.fiches('facturesFournisseurs').length} factures fournisseurs');
  ctx.note('ventes au comptoir : ${ctx.fiches('factures').where((f) => f['venteComptoir'] == true).length} ventes, ${stock.refus} refus RG-03 rejoués sans écriture');
  ctx.note('comptabilité : ${ctx.fiches('depenses').length} dépenses, ${ctx.fiches('echeancesFiscales').length} échéances, ${ctx.fiches('relances').length} relances, '
      '${ctx.fiches('ecritures').length} lignes d\'écriture, $pieces pièces validées (août et septembre)');
}
