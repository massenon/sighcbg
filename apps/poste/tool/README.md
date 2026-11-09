# Générateur du jeu de démonstration Baguidi

Décision J12 de la Direction (08/11/2026). Le jeu livré avec le poste (`assets/donnees/jeu/`, 153 fichiers JSON) n'est plus écrit à la main : il est
ENGENDRÉ, de façon déterministe, par ce générateur.

## Commande (depuis `apps/poste`)

```
flutter test tool/generer_jeu_baguidi.dart
```

Elle tourne sous Flutter et non sous `dart run` : le magasin du poste importe `package:flutter` (donc `dart:ui`). Variable `JEU_SORTIE` pour écrire
ailleurs que dans `assets/donnees/jeu`. Le test `test/generer_jeu_baguidi_test.dart` prouve le déterminisme (deux exécutions, mêmes octets), la
conservation des 153 noms de fichier, l'absence de champ nul et que le jeu livré est à jour : après toute modification d'une étape, relancer la commande.

## Architecture

- `generer_jeu_baguidi.dart` : point d'entrée et liste ORDONNÉE des étapes (socle, personnes, clinique, rh_paie, stock_finance).
- `jeu_baguidi/contexte.dart` : le `Contexte` (magasin en mémoire, tirage seedé Mulberry32 graine 20261108 avec un flux par étape `tirageDe('nom')`,
  horloge fixe 07/11/2026 12:00, fenêtre 01/08 au 07/11/2026, `remplacer` / `ajouter` / `reference`) et l'écriture des fichiers (une fiche par ligne,
  aucun champ nul, `[]` pour une collection vide, journal d'audit livré vide).
- `jeu_baguidi/socle.dart` : référentiels (plan comptable, actes et tarifs, assureurs, entreprises, secteurs, postes, calendrier fiscal).
- `jeu_baguidi/personnes.dart` : personnel, comptes, soignants, vacataires fictifs.
- `jeu_baguidi/module_clinique.dart`, `module_rh_paie.dart`, `module_stock_finance.dart` : un fichier par sous-lot, déjà branchés, vides.
  Chaque sous-lot ne modifie QUE son fichier (et peut en ajouter d'autres à côté). L'ordre d'exécution est celui des dépendances : la clinique produit
  les patients, le stock et la finance lisent tout ce qui précède.

## Règles pour les sous-lots

- Toute écriture métier passe par les moteurs de `packages/domaine` (facture, encaissement, avoir, écriture) : RG-03 et RG-10 tiennent par construction.
- Aucun `DateTime.now()`, aucun `dart:math` : `Contexte.maintenant` et `ctx.tirageDe('votre_etape')`.
- `ctx.reference(nom)` lit le jeu de référence de la clinique d'origine, PSEUDONYMISÉ : à n'employer que pour du générique (catalogues), jamais pour
  des personnes. `node tools/baguidi/controle-identite.mjs` refuse tout nom d'origine et tout pseudonyme de test dans le jeu livré.
- Aucun numéro de téléphone ou d'urgence inventé, aucun mot de passe, aucune empreinte.

## Mots de passe

Les neuf comptes (`admin@baguidi-clinique.bj`, `m-001@baguidi-clinique.bj` à `m-008@…`) sont ACTIFS et SANS secret. Le haché d'un mot de passe vit dans la
collection technique `identifiants`, jamais livrée. Un compte sans haché n'ouvre pas de session (état « mot de passe à définir »).
- Administrateur : à la première mise en service, le poste lui tire un mot de passe provisoire aléatoire, affiché une fois à l'écran de connexion, avec
  changement obligatoire (`ServiceIdentifiants.amorcerAdministrateur`).
- Les huit autres : l'administrateur ouvre « Utilisateurs » (m14), action « Définir le mot de passe » (« Générer un mot de passe provisoire », case
  « changement obligatoire à la première connexion » cochée par défaut).

## Fichiers de données

`donnees/plan-comptable-syscohada-revise.csv` : plan SYSCOHADA révisé (1 332 comptes, colonnes `Code;Libellé`), norme publique.
`test/fixtures/jeu_reference/` : copie pseudonymisée du jeu d'origine, jeu de TEST (`Magasin.dossierJeuDeTest`) et source des référentiels génériques.
