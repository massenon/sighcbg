# Décisions de la Direction du 09/11/2026 (formulaire de validation, enregistré à 16:05 UTC)

Source : formulaire publié (artefact privé), réponses lues dans sa base le 09/11/2026. **Elles font foi.**

| # | Décision | Réponse | Remarque de la Direction |
|---|---|---|---|
| D1 | Relier au barème les trois endroits au taux d'AIB de 1 % par défaut | **Oui**, les trois : retransmission d'une facture, vente sans acheteur, affichage de la configuration MECeF. **Sans taux arrêté en vigueur : appliquer 0 %** (et non refuser) | — |
| D2 | Versement CNSS du 15 pour les postes déjà installés | **Oui, migration au démarrage** | — |
| D3 | Modèles des spécialités ; check-listes du bloc | **Attendre les praticiens** (les deux) | — |
| D4 | Qui supporte le prélèvement de 5 % de l'AIB | **Les deux, selon la situation de l'émetteur**. Pièces à obtenir : communiqué de la DGI, comptes confirmés par écrit par l'expert-comptable. **Aucune écriture d'AIB subi** (affichage seul) | « créer un formulaire de validation pour le barème AIB dans Paramètres (poste, web) » |
| D5 | « ContexteEcran absent » à l'impression depuis le tiroir patient | **Oui**, reproduire puis corriger | — |
| D6 | Livraison (remise à zéro du jeu, commit unique) | **En dernier, après accord explicite**. Préalables : D1 à D5 réglées, dépôt privé, jeu vidé, contrôle d'identité à 0 | — |
| D7 | Base de l'AIB : champ hors taxes sur les factures fournisseurs | **Oui** | « créer un formulaire de validation pour la base AIB des factures fournisseurs dans Paramètres, base de données (poste, web) » |
| D8 | Vente à un acheteur avec IFU actif tant que le 1 % n'est pas arrêté | **Garder le refus** jusqu'au texte de la DGI | « créer un formulaire de validation pour le branchement IFU dans Paramètres (poste, web), qui prend le taux fourni » |

## Lectures retenues (à corriger si elles ne conviennent pas)
- D1 « 0 % sans taux arrêté » et D8 « refus pour IFU actif » se recoupent : la lecture retenue est que le **0 %** vaut pour les trois endroits à défaut (retransmission, vente sans acheteur, affichage), et que la **fenêtre acheteur** garde son refus nommé quand l'acheteur a un IFU actif et que le 1 % n'est pas arrêté.
- « web » désigne le relais en ligne (Laravel) : il est opaque et ne porte pas les règles métier ; le formulaire de validation se livre d'abord au **poste** (Paramètres), le côté web est à confirmer.

## Règle générale (Direction, 09/11/2026)
**Tout ce qui est paramétrable l'est dans les Paramètres du poste et du web, ENREGISTRÉ EN BASE, avec un défaut.** Aucune constante métier lue directement dans le code : le code ne porte qu'une graine qui amorce la collection de paramètres ; les moteurs lisent la valeur en vigueur à la date (versionnée, jamais écrasée). Le côté web (relais Laravel, opaque) est à définir : quels paramètres y remontent et comment.
