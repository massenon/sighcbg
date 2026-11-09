# Note de reprise SIGH-CBG (09/11/2026)

Pour reprendre le chantier dans une session neuve sans relire l'historique. Lire dans cet ordre : ce fichier, `docs/prd/PRD-replique-baguidi.md` (spécification, questions tranchées barrées), `docs/prd/JEU-DEMONSTRATION-BAGUIDI.md` (version 2 validée), `docs/audit/INVENTAIRE-AUDITS-PAYES.md`.

## 1. Où est le code (ATTENTION : local seulement)

| Quoi | Où |
|---|---|
| Code de travail | dépôt local `/home/user/sighcbg`, branche **`baguidi-lot1`**, dernier commit `e4ea9e4`, **non poussé** |
| Spécification et notes | branche `claude/eager-archimedes-e8whyx` de `massenon/sighcbg` (poussée) |
| Sources Baguidi (logo, charte, maquette) | branche `baguidi-sources` de `massenon/sighcbg` (poussée, sans historique) |
| Base d'origine | `massenon/sighcnt`, branche `claude/sighcnt-monorepo-offline-first-i0v3v9` ; importée à `26efb3f`, mise à jour jusqu'à `c052c905` (le commit `27df5d68`, provisoire, est écarté) |

**Risque : le conteneur de la session est éphémère. `baguidi-lot1` n'existe que dans ce conteneur.** Tant qu'il n'est pas poussé, il se perd à la fin de la session. Il ne se pousse PAS en l'état : son historique contient, dans le commit d'import, des données de Nassiera Too, et `sighcbg` est public. Voir la section 5.

## 2. Ce qui est fait (état vert au 09/11 : domaine 2 833 tests, poste 2 339 + 10 ignorés avec motif, banc de synchronisation 218/218)

Identité Baguidi surchargeable (`IdentiteClinique`, `IdentiteImprimee`) ; sigle CBG partout (`tools/baguidi/cnt-vers-cbg.mjs`) ; charte (jetons coeur, sante, anthracite ; Montserrat et Dancing Script) ; écran de connexion ; papier à en-tête en trois zones (rendu vérifié sur images) ; bascules NS 131 et NS 132 et MECeF réellement coupables ; M1 à M10 ouverts, banque de sang et donneurs comprises ; mises à jour de Nassiera Too fusionnées ; mentions d'entreprise retirées ; ambulances et liasse de DÉMONSTRATION (numéros fictifs non composables, montants multipliés par 3) ; pseudonymisation des tests ; **fondation du générateur du jeu** (`apps/poste/tool/`).

## 3. Ce qui reste, dans l'ordre (les points 1 à 4 sont FAITS : voir la section 6)

1. **Sous-lot clinique** du jeu (patients, consultations, analyses, imagerie, hospitalisation, bloc, maternité, banque de sang) : fichier `apps/poste/tool/jeu_baguidi/module_clinique.dart`.
2. **Sous-lot RH et paie** : `module_rh_paie.dart` (contrats, congés, présences, 24 bulletins, août et septembre validés, octobre en brouillon, aucune évaluation NS 131).
3. **Sous-lot stock, achats, caisse, comptabilité** : `module_stock_finance.dart` (120 produits, lots FEFO, ~900 mouvements, besoins, commandes, livraisons, factures fournisseurs, ventes de pharmacie, dépenses, créances, arrêtés de caisse, échéance dépassée, écritures équilibrées).
4. **Barème AIB** (5 % arrêté le 07/09/2026, 1 % et 3 % non arrêtés ; comptes 4478, 4492, 891) : aucun écran ni collection au poste, à construire.
5. **Les quatorze spécialités** (PRD P0-12) : une mécanique pilotée par des données, médecine du travail d'abord ; audit déjà fait dans le PRD.
6. **Banque de sang à compléter** : lien poche vers patient transfusé, restauration des poches archivées, bordereaux imprimés.
7. **Corrections de caisse restantes** : client libre pour le comptoir (vérifier ce que la mise à jour amont a déjà réglé : écriture 411 faite).
8. **Relais web et application mobile** aux couleurs Baguidi (P1-3) ; l'application mobile ne suit pas les fermetures de modules.
9. **Recette** : pièces imprimées validées, installation à blanc, contrôle d'identité à 0.

Questions ouvertes de la Direction : Q21 (TVA 18 % sur tout ? confirmation écrite), Q28 (logo « DE » contre RCCM « DU »), Q33 (titulaire du rôle stock), Q38 (avenant au CDC V2), forme et autorisation (autorisation d'ouverture vide), grille salariale, tarifs. J14 : passer `sighcbg` en privé.

## 4. Outils et pièges appris

- Flutter 3.47.9 dans `/opt/sdk/flutter` (se réinstalle depuis `storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz`). `export PATH=/opt/sdk/flutter/bin:$PATH`. `dart pub get` dans `packages/domaine`, `flutter pub get` dans `apps/poste`.
- Suite poste : environ 25 minutes sur 4 cœurs. La lancer UNE fois par fusion, en arrière-plan vers un fichier, sans toucher au dépôt pendant ce temps. Ne jamais fusionner avant son verdict.
- Contrôles scriptés (tous doivent dire 0) : `tools/baguidi/{controle-identite,pseudonymiser --verifier,cnt-vers-cbg --verifier,demo-liasse --verifier,substitution-identite --verifier}.mjs`.
- Les agents travaillent dans des worktrees créés À LA MAIN (`git worktree add .claude/worktrees/<nom> -b <nom> baguidi-lot1`) : l'option d'isolation automatique échoue quand le répertoire courant n'est pas le dépôt. Imposer `model: sonnet` à chaque agent (le défaut hérite du modèle le plus cher).
- Les tests de parité lisent `apps/poste/test/fixtures/jeu_reference` (ancien jeu pseudonymisé) ; le jeu LIVRÉ est `apps/poste/assets/donnees/jeu`, régénéré par `flutter test tool/generer_jeu_baguidi.dart` (déterminisme octet pour octet).
- Les noms réels des neuf agents de Baguidi ne passent JAMAIS par le script de pseudonymisation.
- La maquette de Nassiera Too n'est pas dans le dépôt : les vecteurs ne se régénèrent pas, ils se transforment par scripts rejouables.

## 5. Avant tout envoi sur GitHub

1. La Direction passe `sighcbg` en privé (réglage du dépôt, J14).
2. Le contrôle d'identité dit 0 sur le jeu livré et sur tout le dépôt.
3. Envoi en **un seul commit sans historique** (`git checkout --orphan`, tout l'état final, un commit) : aucun commit ne contient alors de donnée de Nassiera Too.
4. Si une sauvegarde intermédiaire est indispensable avant cela, uniquement sur un dépôt privé et sur une branche nommée provisoire, en sachant que l'historique contient des données de Nassiera Too.

## 6. Mise à jour du 09/11/2026 (soir) : le jeu de démonstration est complet

État vert vérifié sur `baguidi-lot1` (`e4ea9e4`) : domaine 2 853 tests, poste 2 408 passés + 10 ignorés avec motif (un seul échec trouvé à la suite complète, corrigé et rejoué seul), banc de synchronisation 218/218 (216/218 avant correction : la pseudonymisation avait désolidarisé deux homonymes du scénario R15). **Leçon : lancer aussi le banc de synchronisation (`node packages/sync/banc/run.js`) après toute pseudonymisation ou tout remplacement global.**

Fait depuis la section 3 : sous-lot clinique (120 patients, 200 consultations, 351 factures, analyses, imagerie, hospitalisation, bloc, maternité, banque de sang), RH et paie (24 bulletins), stock, achats, caisse et comptabilité (150 produits, 830 mouvements, 208 pièces validées), barème AIB (écran `m12-aib`, taux daté : 5 % arrêté au 07/09/2026, 1 % et 3 % non arrêtés), vue calendrier des échéances, signataires lus par qualité, marquage des valeurs d'attente.

Ce que le modèle du poste ne sait pas représenter (constaté, rien d'inventé) : pas de collection d'arrêtés de caisse (l'état de caisse s'imprime à la demande) ; une créance est une facture mère (9 au jeu, pas 18) ; le stock d'urgence est un drapeau sur le magasin de détail ; le moteur de facture exige une fiche patient (le comptoir utilise une identité générique fictive : la fonction « client libre » reste à construire).

Reste, dans l'ordre : (a) brancher la retenue d'AIB sur les factures fournisseurs réglées (crédit 4478, brouillon, RG-10), le registre des retenues et l'AIB subi ; (b) client libre ; (c) arrêtés de caisse persistants si la Direction les veut ; (d) les quatorze spécialités (PRD P0-12) ; (e) compléter la banque de sang (lien poche vers patient transfusé, restauration, bordereaux) ; (f) relais web et mobile aux couleurs Baguidi ; (g) marquer la grille NS 132 « héritée, à confirmer » (prime « bloc fixe » de l'infirmier à confirmer) ; (h) corriger à la source quelques moteurs qui écrivent un nom de l'autre clinique (`directriceAdministrative`, `dafSignataire`, `magasinierParDefaut`) ; (i) recette : installer à blanc, ouvrir un PDF d'essai, contrôle d'identité à 0.

Arbitrages en attente de la Direction : rémunération sur la fiche de poste ou seulement sur les fiches d'agent et de prestataire ; accès de la DAF et de l'assistant comptable à `m12-aib` ; CNSS au 10 dans une constante de repli du domaine ; Q21, Q28, Q33, Q38 ; passage de `sighcbg` en privé (J14), préalable à toute sauvegarde de `baguidi-lot1` : la visibilité était encore « public » au dernier contrôle.
