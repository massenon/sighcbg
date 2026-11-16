# Dossier de présentation — spécimens des pièces imprimées

Ce dossier réunit **un spécimen de chaque document imprimable** du poste SIGH-CBG de la **CLINIQUE BAGUIDI « L’AS DU CŒUR »** : factures, ticket de caisse, reçus, ordonnance, bulletins
d’analyses, comptes rendus, certificats, bons de commande / livraison / sortie / transfert, bulletins de paie, états comptables et liasse, états de stock, badge, états d’imagerie, fiche
d’aptitude de médecine du travail, comptes rendus de spécialités, rapports de la Direction… Il sert à **montrer le papier** (à une réunion, à un auditeur, à l’imprimeur) sans ouvrir
le logiciel.

> **Ce sont des spécimens de démonstration.** Toutes les données viennent du **jeu de démonstration livré** avec le poste (patients et opérations fictifs ; les agents de la clinique
> n’y paraissent que comme utilisateurs ou signataires). Aucun de ces documents n’a de valeur : une mention diagonale **« SPÉCIMEN · DONNÉES FICTIVES »** est apposée sur chaque page
> **après coup** (`tool/specimens/tamponner.py`) — le gabarit d’impression du logiciel n’est pas modifié pour cela, et les vraies pièces n’ont pas cette mention.

{{CHIFFRES}}

## Ce que montrent tous les spécimens

Chaque pièce A4 reprend le **papier à en-tête** de la clinique, produit par le même gabarit que celui du poste :

- **en-tête en trois zones** : à gauche le logo et la devise manuscrite « Votre bien-être est notre raison d’être » ; au centre la dénomination « CLINIQUE BAGUIDI « L’AS DU CŒUR » » et
  l’intitulé de l’établissement ; à droite les coordonnées (BP, téléphones, e-mail, adresse), l’**IFU**, le **RCCM** et le numéro d’enregistrement ;
- **double filet** (rouge et bleu) sous l’en-tête, puis le **titre** de la pièce et son sous-titre ;
- le **cartouche** d’identification, le **tableau** dont le **total est recalculé** depuis les lignes réellement imprimées, le lieu et la date (« Fait à Parakou, le … ») ;
- les **signatures** : le nom du signataire se lit au dossier du personnel selon sa qualité, jamais dans le code (sans titulaire, la ligne reste à signer à la main) ;
- le **pied normalisé** : dénomination, IFU, RCCM, utilisateur ayant édité, date et heure, référence `CBG-AAAAMMJJ-NNNN`, pagination « Page n / N » (l’en-tête n’est porté que par la première page), « Édité depuis le SIGH-CBG ».

Deux gabarits sortent de ce modèle : le **ticket de caisse 80 mm** (rouleau, bloc MECeF, montant arrêté en lettres) et le **badge CR80** (carte 85,6 × 54 mm, recto puis verso, QR du matricule et du numéro
de série ; ni IFU ni RCCM, mentions fiscales qui n’ont rien à faire sur une carte).

## Index par module

Le tableau de **couverture** complet (écran source, rôle, pages, particularités, documents non produits et pourquoi) est dans **[INDEX.md](INDEX.md)**.

{{INDEX_PAR_MODULE}}

## Ce qui est bâti pour le spécimen (le jeu livré n'en porte pas)

Le jeu de démonstration laisse plusieurs registres vides. Pour ne pas se priver de leurs pièces, l'outil les montre à partir d'une **fiche d'exemple fictive**, bâtie sur un patient ou un agent du jeu dans
un magasin éphémère (rien n'est écrit au jeu livré) :

- **fiche d'exemple inscrite au registre, puis pièce éditée depuis l'écran** : déclaration de décès, fiche de planification familiale, fiche d'urgence SONUB/SONUC, fiche d'intervention d'ambulance, compte rendu
  de réunion, fiche de référence, rapport médical, fiche de courrier, fiche documentaire (GED), ordre de mission, reçu de participation, badge et planche de badges ;
- **pièce produite par sa fabrique d'impression sur une fiche d'exemple** : attestation de remboursement et avis d'annulation, bon de sortie de stock (dispensation), décharge de sortie contre avis médical,
  bon de pansement ;
- **enregistrement par le moteur de l'écran, comme le bouton « Enregistrer la visite »** : la visite de médecine du travail et sa **fiche d'aptitude** (pièce certifiante) ;
- **pièce produite par sa fabrique sur une fiche du jeu** (rien de bâti) : facture, facture pro-forma, reçu détaillé, engagement de paiement, facture d'avoir, ticket de caisse 80 mm, facture normalisée MECeF,
  ordonnance, dossier de consultation, dossier complet du patient, procès-verbal de réception des réactifs.

## Documents non produits

{{NB_NON_PRODUITS}} documents (ou familles de documents) n’ont pas de spécimen propre ; chacun est listé avec sa raison dans [INDEX.md](INDEX.md#documents-non-produits-et-pourquoi) (registre vide au jeu livré, pièce née d’une saisie de formulaire,
même gabarit qu’un spécimen présent…). Rien n’est passé sous silence : le fichier `couverture.json` garde en outre les avertissements de l’outil.

## Comment le régénérer

Depuis `apps/poste` (Flutter installé, `export PATH=/opt/sdk/flutter/bin:$PATH`) :

```bash
rm -rf ../../presentation
SIGH_SPECIMENS=1 SIGH_SPECIMENS_SORTIE=../../presentation \
  flutter test tool/specimens/generer_specimens_test.dart          # 10 à 25 minutes : ouvre ~370 écrans
python3 tool/specimens/finaliser.py ../../presentation              # mention SPÉCIMEN, INDEX.md, README.md (PyMuPDF requis)
python3 tool/specimens/controler.py ../../presentation              # aucune trace de l'autre clinique, PDF lisibles
node ../../tools/baguidi/controle-identite.mjs                      # contrôle d'identité du dépôt
```

Sans la variable `SIGH_SPECIMENS=1`, l’outil est **ignoré** (il ne tourne jamais dans la suite normale). `SIGH_SPECIMENS_ECRANS` et `SIGH_SPECIMENS_RECETTES` limitent le rejeu à des préfixes d’écrans ou de
pièces. Le principe et les pièges sont décrits dans `apps/poste/tool/specimens/README.md`.
