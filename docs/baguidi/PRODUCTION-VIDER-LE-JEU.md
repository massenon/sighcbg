# Passer en production : vider le jeu de démonstration

Décision de la Direction du 08/11/2026 : aucune donnée de Nassiera Too dans SIGH-CBG. Les données livrées sont des **données de démonstration**, marquées comme telles, à vider puis à remplacer par les vraies.

## 1. Ce qui est donnée de démonstration (liste exacte)

**A. Les fichiers `apps/poste/assets/donnees/jeu/*.json` (153 fichiers, chargés au premier lancement).**

- Activité, **vidée par la réinitialisation** (83 collections, environ 9 520 fiches) : patients, consultations, dossiers de consultation et obstétricaux, factures, mère de factures, ordonnances, prescriptions, demandes d'analyses et d'imagerie, mouvements et lots de stock, écritures comptables, dépenses, factures fournisseurs, immobilisations, exercices, échéances fiscales (remises à « non payée »), planning, présences, bulletins, évaluations, courriers, réunions, etc.
- **Conservées par la réinitialisation, donc À REMPLACER À LA MAIN** (37 collections « essentielles » hors journal d'audit, vidé à part) : `personnel` (44 agents, salaire, catégorie et CNSS sont retirés par le vidage, pas les noms), `postes`, `soignants`, `produits` (184 articles de l'inventaire d'origine), `valorisationsSage`, `fournisseurs`, `souscripteurs`, `assureurs`, `actes`, `analyses`, `catalogueTarifs`, `grillePrimes`, `baremeNS131`, `comptes` (plan comptable), `banques`, `centresCouts`, `secteurs`, `materiel`, `emplacements`, `enquetes`, `modelesBadge`, `modelesMessage`, `obligationsFiscales`, `objectifsPilotage` (8 cibles proposées), `examensLabo`, `unitesLabo`, `variablesLabo`, `examensImagerie`, `variablesImagerie`, `pathologies`, `typesPiece`, `regimesTravail`, `naturesFacture`, `identiteLegale` (l'identité Baguidi, à vérifier, pas à vider), `rbac`, `utilisateurs` (les comptes de démonstration sans mot de passe sont retirés, pas les autres), `ambulances`.
- Techniques, jamais vidées : `rolesBase`, `modulesManifeste`, `reglages`.

**B. Les fixtures de test** (`apps/poste/test/fixtures/**`, `packages/domaine/test/vecteurs/*.json`) : ne sont jamais chargées au poste, elles ne servent qu'aux tests. Rien à vider en production.

**C. Les constantes Dart (compilées dans l'application, hors portée de toute réinitialisation).**

- `packages/domaine/lib/src/comptabilite/cpb_liasse.dart` et `cpc_liasse.dart` : la liasse fiscale de démonstration (code de dépôt `DEMO`, montants d'origine multipliés par 3).
- `packages/domaine/lib/src/comptabilite/cpc_donnees.dart` : le classeur 2025 de démonstration (montants multipliés par 3) ; ses objectifs de pilotage sont des propositions.
- Semences de premier affichage, appliquées seulement quand la collection est vide : `admAmorcerRepertoire` (répertoire des ambulances : 9 fiches, numéros fictifs `00 00 00 00 01` à `09`, mention « Numéro fictif de démonstration »), `admAmorcerEvenements`, `admAmorcerPlan`, `admAmorcerMateriel` (`adm_regles.dart`).

## 2. Comment fonctionne la réinitialisation, honnêtement

Deux chemins existent, tous deux **fermés par défaut** et journalisés (RG-12).

1. **Poste : écran « Paramètres système », onglet « Jeux de test »** (`cfb_systeme.dart`, `cfbViderActivite`).
   - Garde-fous : la bascule « autoriser la réinitialisation » est fermée par défaut (fermée, le vidage est refusé en le disant) ; son ouverture demande une confirmation et se journalise ; le vidage demande un **motif** et une confirmation « dangereuse ».
   - Ce qu'il vide : toutes les collections d'activité (A, première liste), la corbeille (fiches archivées, sauf rôles et comptes), le journal d'audit (la première entrée du journal neuf dit le vidage), les comptes de démonstration sans mot de passe (un compte avec mot de passe ou créé par l'assistant d'installation reste).
   - Ce qu'il retire dans les collections conservées : salaire, catégorie et CNSS du personnel.
   - Ce qu'il **ne vide pas** : les 37 collections essentielles (A, deuxième liste), donc entre autres les noms du personnel, l'inventaire `produits`, les fournisseurs, les souscripteurs, les tarifs, **les 9 fiches fictives du répertoire des ambulances**, ni les constantes Dart (C), ni les fixtures (B).
   - Le bouton voisin « Régénérer le jeu de démonstration » fait l'inverse (retour au jeu initial) : ne jamais l'utiliser en production.
2. **Mère : écran « Réinitialisation de production »** (`mere-reinit`, `POST /admin/reinitialiser`). Fenêtre d'ouverture de 30 minutes, saisie du nom de la clinique à l'identique, second profil (DAF ou Direction) différent de l'auteur, sauvegarde chiffrée préalable non désactivable. Elle vide l'activité et garde les essentiels, avec les mêmes limites que ci-dessus.

## 3. Marche à suivre

1. **Sauvegarder** : copier le dossier de données du poste et exporter la clé de chiffrement (écran « Paramètres système », « Sauvegarder la clé »).
2. **Vider l'activité** : autoriser la réinitialisation, vider avec un motif (« mise en production »), puis refermer la bascule. Relire le bilan affiché (tables vidées, enregistrements retirés).
3. **Remplacer les essentielles de démonstration**, écran par écran (jamais en vidant la collection à la main : une collection vide se ré-amorce à l'ouverture de son écran pour les semences de C) :
   - répertoire des ambulances : modifier chaque fiche fictive (le champ `fictif` tombe à la saisie du vrai numéro), archiver celles qui ne servent pas ;
   - personnel, postes, soignants, fournisseurs, souscripteurs, assureurs, comptes de trésorerie : saisie ou import des vraies données ;
   - produits et valorisation de stock, tarifs (actes, analyses, grille), barèmes et grille des primes : import validé par la Direction ;
   - comptes utilisateurs et matrice des droits : créer les vrais comptes avec leur mot de passe.
4. **Remplacer les constantes Dart (C)** par la liasse réellement déposée et le vrai classeur : elles se compilent, donc il faut une livraison (voir la procédure de livraison). `node tools/baguidi/demo-liasse.mjs --verifier` dit 0 tant que la liasse reste celle de démonstration, 1 si le fichier n'a pas été transformé ; une fois remplacée par la vraie liasse, retirer le script et le marqueur `DÉMONSTRATION BAGUIDI` des trois fichiers, et ôter la mention `cpbMentionDemonstration` des écrans.
5. **Contrôler** : `node tools/baguidi/controle-identite.mjs`, `node tools/baguidi/cnt-vers-cbg.mjs --verifier` et `node tools/baguidi/substitution-identite.mjs --verifier` doivent dire 0 ; lancer `dart test` (domaine) et `flutter test` (poste).

## 4. Limites connues

- Aucun mécanisme unique ne vide « tout ce qui est démonstration » : le vidage s'arrête aux essentielles, et les constantes Dart ne se vident que par une nouvelle livraison.
- Les données d'inventaire, de personnel et de tarifs portent encore l'origine de la clinique d'avant : leur remplacement est le lot suivant, il n'est pas fait ici.
