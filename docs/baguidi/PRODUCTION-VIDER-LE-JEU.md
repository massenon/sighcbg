# Passer en production : archiver le jeu de démonstration

Décision de la Direction du 08/11/2026 : aucune donnée de Nassiera Too dans SIGH-CBG. Les données livrées sont des **données de démonstration**, marquées comme telles, à mettre hors service puis à remplacer par les vraies.

**Décision D6 de la Direction du 09/11/2026 : « remise du jeu de démonstration : les ARCHIVER, les brouillons, etc. »** (RG-14, archivage logique, jamais de suppression physique). Le geste par défaut de mise en production est donc **l'archivage** (section 2) ; le vidage destructif d'origine subsiste, mais derrière une seconde porte nommée « suppression physique » (section 2, décision de maintien). Ce fichier garde son nom : les liens existants (`docs/baguidi/PRODUCTION-VIDER-LE-JEU.md`) continuent de mener ici.

## 1. Ce qui est donnée de démonstration (liste exacte)

**A. Les fichiers `apps/poste/assets/donnees/jeu/*.json` (153 fichiers, chargés au premier lancement).**

- Activité, **archivée par la mise en production** (106 collections d'activité au total, dont 60 portent des fiches actives dans le jeu livré : **4 620 fiches actives, dont 649 brouillons**, mesuré le 09/11/2026 ; la suppression physique, elle, vide aussi les fiches déjà archivées) : patients, consultations, dossiers de consultation et obstétricaux, factures, mère de factures, ordonnances, prescriptions, demandes d'analyses et d'imagerie, mouvements et lots de stock, écritures comptables, dépenses, factures fournisseurs, immobilisations, exercices, échéances fiscales (remises à « non payée »), planning, présences, bulletins, évaluations, courriers, réunions, etc.
- **Conservées par la mise en production, donc À REMPLACER À LA MAIN** (37 collections « essentielles » hors journal d'audit) : `personnel` (44 agents ; salaire, catégorie et CNSS restent en place par l'archivage — seule la suppression physique les retire — et sont à remplacer par les vraies valeurs), `postes`, `soignants`, `produits` (184 articles de l'inventaire d'origine), `valorisationsSage`, `fournisseurs`, `souscripteurs`, `assureurs`, `actes`, `analyses`, `catalogueTarifs`, `grillePrimes`, `baremeNS131`, `comptes` (plan comptable), `banques`, `centresCouts`, `secteurs`, `materiel`, `emplacements`, `enquetes`, `modelesBadge`, `modelesMessage`, `obligationsFiscales`, `objectifsPilotage` (8 cibles proposées), `examensLabo`, `unitesLabo`, `variablesLabo`, `examensImagerie`, `variablesImagerie`, `pathologies`, `typesPiece`, `regimesTravail`, `naturesFacture`, `identiteLegale` (l'identité Baguidi, à vérifier, pas à vider), `rbac`, `utilisateurs` (les comptes de démonstration restent en place par l'archivage ; la suppression physique retire ceux qui n'ont pas de mot de passe), `ambulances`.
- Techniques, jamais vidées : `rolesBase`, `modulesManifeste`, `reglages`.

**B. Les fixtures de test** (`apps/poste/test/fixtures/**`, `packages/domaine/test/vecteurs/*.json`) : ne sont jamais chargées au poste, elles ne servent qu'aux tests. Rien à vider en production.

**C. Les constantes Dart (compilées dans l'application, hors portée de toute réinitialisation).**

- `packages/domaine/lib/src/comptabilite/cpb_liasse.dart` et `cpc_liasse.dart` : la liasse fiscale de démonstration (code de dépôt `DEMO`, montants d'origine multipliés par 3).
- `packages/domaine/lib/src/comptabilite/cpc_donnees.dart` : le classeur 2025 de démonstration (montants multipliés par 3) ; ses objectifs de pilotage sont des propositions.
- Semences de premier affichage, appliquées seulement quand la collection est vide : `admAmorcerRepertoire` (répertoire des ambulances : 9 fiches, numéros fictifs `00 00 00 00 01` à `09`, mention « Numéro fictif de démonstration »), `admAmorcerEvenements`, `admAmorcerPlan`, `admAmorcerMateriel` (`adm_regles.dart`).

## 2. Comment fonctionne la mise en production, honnêtement

Deux chemins existent, tous deux **fermés par défaut** et journalisés (RG-12). **Le geste par défaut est l'archivage.**

### 2.1 Poste : écran « Paramètres système », onglet « Jeux de test » (`cfb_systeme.dart`, `cfbArchiverJeuDemo`)

- **Garde-fous** (tenus par la fonction, pas seulement par le bouton) : la bascule « autoriser la réinitialisation » est **fermée par défaut** (fermée, le bouton est absent et l'archivage est refusé en le disant) ; son ouverture demande une confirmation et se journalise ; l'archivage exige un **motif** (celui de l'agent, journalisé) et une confirmation « dangereuse » qui **dit que rien n'est supprimé**. Le bouton « Réinitialiser le jeu de données » de l'onglet « Installation et données » mène au même geste.
- **Ce que fait « Archiver le jeu de démonstration »** : pour chaque collection d'activité (la liste « A » de la section 1 : ni essentielle, ni technique), **toutes les fiches actives** passent à `statut: archive` (ancien statut gardé dans `statutAvantArchivage`) avec les marques `_motifArchivage` = « Jeu de démonstration, mise en production », `_archivePar` (l'acteur de la session) et `_archiveLe` (la date). Y compris :
  - les **brouillons** (écritures comptables, inventaires, comptes rendus d'imagerie) : archivés comme les autres, **jamais validés** au passage (leur ancien statut `brouillon` est conservé) ;
  - les **files d'attente, tâches bloquées et notifications** (collections `taches`, `notifications`, `tachesPlanifiees`, etc.) ;
  - les **échéances fiscales** : remises à « non payée » (le calendrier, dérivé d'un document, reste en service, l'échéance n'est pas archivée). **Décision de la Direction du 09/11/2026 : le paiement de démonstration est une donnée fictive, pas une pièce comptable : il est SUPPRIMÉ**, jamais rangé nulle part (plus de `paiementsArchives`, champs de règlement retirés ; une ancienne trace laissée par un archivage antérieur est retirée aussi). Une ligne du journal (« Paiements fictifs d'échéances fiscales retirés ») dit combien ont été retirés, le bilan affiché et la synthèse du journal le reprennent. C'est la seule suppression du geste ; la restauration depuis la Corbeille vaut pour toutes les autres fiches. La mère (poste mère) ne détient pas la collection des échéances (elle n'est pas synchronisée) : son mode `archiver` n'a rien à y retirer.
- **Ce qui ne bouge pas** : les collections essentielles et techniques (personnel et salaires compris, tarifs, plan comptable, comptes, droits, identité, paramètres AIB et fiscaux…), la Corbeille, et **le journal d'audit, qui n'est pas vidé** : il reçoit **une entrée par collection touchée** (« Archivage du jeu de démonstration », nombre archivé et nombre de brouillons) et **une entrée de synthèse** (RG-12).
- **Le bilan affiché** dit combien de fiches ont été archivées **par collection** et **combien de brouillons** ; il reste à l'écran dans la carte « Bilan de l'archivage ».
- **Restauration** : les fiches archivées se retrouvent et se restaurent **une à une** depuis l'onglet **Corbeille** de `cfg-systeme` (elles y portent le motif, l'acteur et la date). Une fiche restaurée revient exactement avec son ancien statut, sans marque « archivée le… ». Il n'y a pas de « tout restaurer » en un geste.
- **Les compteurs de numérotation ne reculent pas** (RG-01) : les générateurs (code patient `CBG/n/AA`, séries annuelles des factures et des pièces comptables) lisent les fiches **archivées comprises** ; un code archivé n'est donc jamais réattribué. Vérifié par test sur le jeu livré (code patient, rang de facture, numéro de pièce). Correction au passage : le « prochain numéro » affiché à la configuration MECeF se calculait sur les factures actives et serait reparti de 1 ; il lit désormais la série entière.
- **Idempotent** : rejouer l'archivage n'a plus rien à archiver et conserve la date et le motif d'origine.

### 2.2 La suppression physique : seconde porte, conservée mais distincte

Le vidage destructif d'origine (`cfbViderActivite`) **n'est plus le geste de mise en production**. Il reste sous le nom **« Suppression physique des jeux de test »**, dans une carte à part « Suppression physique (hors RG-14) », avec **deux confirmations** : le motif, puis une confirmation nommée « Suppression physique : dernière confirmation » dont le bouton dit « Supprimer physiquement ». L'écran dit qu'elle **contredit RG-14** (fiches d'activité, Corbeille et journal vidés, sans retour possible, numérotation remise à zéro).

*Choix et justification.* J'ai gardé la fonction dans l'interface plutôt que de la retirer de la production : un poste d'essai ou de recette (jeu de démonstration modifié par des essais) doit pouvoir être remis à neuf sans réinstaller, et le banc de synchronisation s'appuie sur elle. Ce qui la rend sûre n'est plus son absence mais sa double porte : bascule fermée par défaut, absente quand elle est fermée, motif, confirmation nommée. Si la Direction préfère la retirer de la production, c'est un seul bouton à masquer par un réglage ; l'archivage n'en dépend pas.

Le bouton voisin « Régénérer le jeu de démonstration » fait l'inverse (retour au jeu initial) : ne jamais l'utiliser en production.

### 2.3 Mère : écran « Réinitialisation de production » (`mere-reinit`, `POST /admin/reinitialiser`)

Mêmes garde-fous qu'avant : fenêtre d'ouverture de 30 minutes, saisie du nom de la clinique à l'identique, second profil (DAF ou Direction) différent de l'auteur, sauvegarde chiffrée préalable non désactivable. S'y ajoute le **mode** :

- **`archiver` (défaut, motif obligatoire, refus nommé `motif_requis`)** : chaque fiche active des collections d'activité de la mère passe à l'état archivé **par des opérations du journal** (`modifier` portant les marques, puis `archiver`), donc **propagées aux postes fileuls et aux mobiles comme n'importe quel archivage**. **Aucune purge, aucun changement d'époque, `next_patient` et les plages de numéros intacts** (RG-01). Les référentiels (famille R, donc la configuration diffusée), les essentiels du moteur, les hachés de mots de passe, le battement des postes et les variations de compteur ne sont pas archivés. La réponse porte le bilan par collection et les brouillons ; la mère l'écrit à son journal technique.
- **`supprimer` (exige `suppression_physique: true`, refus nommé `suppression_physique_non_confirmee`)** : le vidage destructif d'origine (époque + 1, journal d'opérations purgé).
- Un `mode` absent vaut `archiver` : **un appel sans mode ne détruit jamais**.
- Côté poste, la console propose « Archiver le jeu de démonstration » (champ motif) et, à part, « Suppression physique » avec sa confirmation nommée. La console historique (`console.dart`) n'offre que l'archivage.

### 2.4 Propagation aux postes fileuls : ce qui est prouvé et ce qui ne l'est pas

- **Règle de fusion** (`fusionnerArchivage`, pont d'activité) : **l'archivage l'emporte** sur une modification concurrente ou sur une fiche distante non archivée plus ancienne ; si la fiche était **déjà** archivée à la dernière synchronisation, ce n'est plus une nouveauté et la **restauration** (d'un poste ou de la mère) se propage. Un poste qui n'a pas vu l'archivage n'écrase plus `archive` du journal par un changement de statut (la modification des autres champs part).
- **Restauration d'une fiche archivée par la mère** : opération `restaurer` du journal (nouvelle méthode `TransportPont.restaurer`, `POST /admin/referentiel` avec `type: restaurer`) ; les marques d'archivage sont effacées avec elle.
- **Prouvé** : test du pont à trois postes (deux postes et la mère, journal partagé) ; test contre le **vrai service de la mère (Dart, HTTP)** : sans motif refusé, archivage sans changement d'époque, fiches conservées avec marques, restauration, puis suppression physique à confirmation explicite ; banc de synchronisation (processus réels, mère et fileuls Node) : scénario `R8a`, deux fileuls reçoivent l'archivage, essentiels intacts, aucun export ni purge, numérotation sans réattribution, restauration depuis un fileul.
- **Non prouvé** : le banc contre l'exécutable Dart de la mère et de ses fileuls (`SIGH_MERE=dart`, bundle non construit ici), la mère sur PostgreSQL, la restauration d'une mère depuis le relais après un archivage (les opérations `modifier` et `archiver` sont des types standard que `restaurer()` sait rejouer, mais ce parcours n'est pas rejoué), l'archivage rejoué sur un vrai fileul Flutter en cours d'utilisation.

## 3. Marche à suivre

1. **Sauvegarder** : copier le dossier de données du poste et exporter la clé de chiffrement (écran « Paramètres système », « Sauvegarder la clé »).
2. **Archiver le jeu de démonstration** : onglet « Jeux de test », autoriser la réinitialisation, « Archiver le jeu de démonstration » avec un motif (« mise en production »), puis refermer la bascule. Relire le bilan affiché (fiches archivées par table, brouillons). **Ne pas** utiliser « Suppression physique » pour une mise en production.
3. **Sur une clinique à plusieurs postes** : lancer l'archivage **à la mère** (écran « Réinitialisation de production ») pour que les postes fileuls reçoivent l'archivage de ce que le pont porte ; les collections que le pont ne porte pas (voir 4) s'archivent **poste par poste**, par le même geste à l'onglet « Jeux de test ».
4. **Remplacer les essentielles de démonstration**, écran par écran (jamais en vidant la collection à la main : une collection vide se ré-amorce à l'ouverture de son écran pour les semences de C) :
   - répertoire des ambulances : modifier chaque fiche fictive (le champ `fictif` tombe à la saisie du vrai numéro), archiver celles qui ne servent pas ;
   - personnel (dont salaires, catégories, CNSS, que l'archivage laisse en place), postes, soignants, fournisseurs, souscripteurs, assureurs, comptes de trésorerie : saisie ou import des vraies données ;
   - comptes utilisateurs de démonstration : les archiver (un rôle ou un compte s'archive, RG-14) et créer les vrais comptes avec leur mot de passe ;
   - produits et valorisation de stock, tarifs (actes, analyses, grille), barèmes et grille des primes : import validé par la Direction ;
   - matrice des droits : la relire.
5. **Remplacer les constantes Dart (C)** par la liasse réellement déposée et le vrai classeur : elles se compilent, donc il faut une livraison (voir la procédure de livraison). `node tools/baguidi/demo-liasse.mjs --verifier` dit 0 tant que la liasse reste celle de démonstration, 1 si le fichier n'a pas été transformé ; une fois remplacée par la vraie liasse, retirer le script et le marqueur `DÉMONSTRATION BAGUIDI` des trois fichiers, et ôter la mention `cpbMentionDemonstration` des écrans.
6. **Contrôler** : `node tools/baguidi/controle-identite.mjs`, `node tools/baguidi/cnt-vers-cbg.mjs --verifier` et `node tools/baguidi/substitution-identite.mjs --verifier` doivent dire 0 ; lancer `dart test` (domaine) et `flutter test` (poste).

## 4. Limites connues

- **Aucun mécanisme unique ne met « tout ce qui est démonstration » hors service** : l'archivage s'arrête aux essentielles, et les constantes Dart ne se remplacent que par une nouvelle livraison.
- **Les essentielles restent à la main** : personnel (noms et salaires de démonstration), inventaire `produits`, fournisseurs, souscripteurs, tarifs, **comptes de démonstration**, 9 fiches fictives du répertoire des ambulances. L'archivage ne les touche pas (contrairement à la suppression physique, qui retire les salaires et les comptes sans mot de passe).
- **La synchronisation ne porte que certaines collections** : le pont du poste ne synchronise que `collectionsActivite` (patients, rendez-vous, constantes, relevés, observations, visites, appels, consultations, dossiers de consultation, antécédents, factures, avoirs, écritures, mouvements, lots, produits, admissions). L'archivage d'ordonnances, prescriptions, bulletins, dépenses, inventaires, etc. reste **local au poste qui lance le geste** ; la mère n'archive que ce qu'elle détient.
- **Les gardes de collection ne jouent pas** pour ce geste, comme pour le vidage : c'est une remise du jeu, non l'écriture d'une fiche. Les registres des clôtures et les archives d'exercice, qui se disent immuables pour l'agent, sont archivés avec le reste du jeu de démonstration.
- **Le journal d'audit reste plafonné à 400 entrées** (plafond du magasin) : l'archivage y ajoute une entrée par collection touchée et une synthèse (une soixantaine sur le jeu livré) ; sur un poste dont le journal est déjà plein, les plus anciennes sortent du tampon comme pour tout geste. Exporter le journal avant si on veut tout garder.
- **Pas de « tout restaurer »** : la Corbeille restaure fiche par fiche.
- **Les brouillons archivés restent des brouillons** : restaurés, ils redeviennent des brouillons à valider ; rien ne les valide à la restauration.
- Les données d'inventaire, de personnel et de tarifs portent encore l'origine de la clinique d'avant : leur remplacement est le lot suivant, il n'est pas fait ici.
