# Export et impression depuis un tableau — tableaux EXCLUS

Décision de la Direction du 16/11/2026 (`docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md`, section 7, premier point) :
« les grilles de SAISIE en cours (panier, lignes en composition…) et les DOCUMENTS imprimés n'ont ni cases ni « Exporter » (liste écrite avec motif) ».

Le composant commun `TableauSigh` (`apps/poste/lib/kit/tableau.dart`) porte les cases à cocher, « Exporter » et « Imprimer la sélection ».
Pour qu'un tableau n'offre RIEN de cela, il faut `exportable: false` (cases, « Exporter » et impression de la sélection tombent ensemble) ;
`selectionnable: false` seul retire les cases mais laisse « Exporter ».

## Mesure (16/11/2026)

On a cherché toutes les grilles de saisie en cours et tous les tableaux de documents du poste (`apps/poste/lib`) :
recherche de `TableauSigh(` (373 appels) avec leur contexte (modale, état local, liste en cours de composition), puis lecture des écrans de saisie connus.

**Résultat : aucune grille de saisie en cours et aucun document imprimé n'est construit sur `TableauSigh`.** Ils utilisent des composants
qui n'ont ni cases ni export : `MiniTableauSigh` (`kit/tableau_de_bord.dart`), `EditeurLignes` (M7), une `Table` Flutter écrite pour l'écran,
ou `TableauEtat` (le tableau d'une pièce A4, rendu par `FeuilleA4`, sans aucune interaction). Il n'y avait donc rien à couper. Le drapeau
`exportable: false` existe désormais pour le premier tableau de saisie qui serait construit sur le composant commun, et un test (« cliquet »)
vérifie que les fichiers des grilles de saisie ci-dessous ne contiennent pas de `TableauSigh(` (`apps/poste/test/export_section7_test.dart`).

## Liste des tableaux sans cases ni « Exporter »

### Grilles de saisie en cours

Motif commun : la pièce n'existe pas encore. L'exporter ou l'imprimer sortirait un brouillon que personne n'a validé, et cocher des lignes
qu'on est en train de taper n'a pas d'objet. La pièce s'imprime une fois enregistrée, depuis son registre.

| Écran | Grille | Fichier | Composant |
|---|---|---|---|
| `m8-facturation` | Lignes d'une facture en composition (prestations, remises, répartition assureur) | `modules/m8/facturation.dart` | `Table` propre à l'écran |
| `m7-besoins` | Lignes d'un bon d'expression de besoins en préparation | `modules/m7/besoins_commun.dart` (`EditeurLignes`), appelé par `besoins_expression.dart` | `EditeurLignes` |
| `m7-commandes` | Lignes d'un bon de commande en préparation | `modules/m7/besoins_commun.dart` (`EditeurLignes`), appelé par `besoins_commandes.dart` | `EditeurLignes` |
| `m6-transferts` | Lignes d'un bon de transfert en préparation (modale « Nouveau bon ») | `modules/m6/mvt_transferts.dart` (`_tableLignes`) | `Table` propre à l'écran |
| `m6-inventaire-feuille` | Feuille d'inventaire en cours de comptage | `modules/m6/mvt_inventaire_feuille.dart` | `ListView` de saisie |
| `m6-dispensation` | Lignes à servir d'une ordonnance (le « panier » de la délivrance) | `modules/m6/flux_dispensation.dart` | `MiniTableauSigh` |
| `m12-ecritures` | Lignes d'une écriture en saisie | `modules/m12/cpa_ecritures.dart` | `MiniTableauSigh` |
| `m12-depenses` | Lignes d'une dépense en saisie (modale `editeurLignes`, arbitrage n° 4) | `modules/m12/cpa_depenses.dart` | `MiniTableauSigh` |
| `m8-facture-avoir` | Lignes annulées d'un avoir (modale d'émission et tiroir) | `modules/m8/avoirs.dart` | `MiniTableauSigh` |
| `m7-pv-reception-*` | Lignes contrôlées d'un PV de réception | `modules/m7/pv_reception.dart` | `MiniTableauSigh` |

### Documents imprimés

Motif : une pièce imprimée est un DOCUMENT, pas un écran de travail. Ses tableaux (`TableauEtat`, dans `impression/piece.dart`) sont rendus
par `FeuilleA4` et par le PDF, sans aucune commande : rien à cocher, rien à exporter. La pièce elle-même s'enregistre en PDF depuis l'aperçu.
Cela vaut pour TOUTES les pièces (factures, reçus, bons, ordonnances, certificats, états, bulletins, comptes rendus, pièce de la sélection).

### Tableaux de détail dans un tiroir ou une modale

Motif : ils détaillent UNE fiche déjà ouverte (lignes d'une facture, d'un bon, d'une ordonnance, d'une écriture) ; la fiche s'exporte ou
s'imprime depuis son registre. Ils sont construits sur `MiniTableauSigh` (154 appels mesurés le 16/11/2026), qui n'a ni cases ni export.

## Ce qui n'est PAS exclu

- Les registres et les listes de travail (factures, encaissements, mouvements, écritures, bons, file de validation de la GED…) : cases et
  commandes selon les deux gestes réservés (`export_tableau`, `imprimer_tableau`).
- Le « Détail du calcul » de la paie (`m11-calcul`) : c'est le résultat d'un calcul, pas une saisie ; il s'exporte.
- La valorisation SAGE ligne à ligne (écran des imports, jeu « Grand Stock », onglet « Points à traiter » de la reprise) : chaque ligne s'enregistre aussitôt par sa propre modale ; la liste est un registre de travail.
