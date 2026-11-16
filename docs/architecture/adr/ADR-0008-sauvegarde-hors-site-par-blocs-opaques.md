# ADR-0008 : Sauvegarde hors site par blocs opaques chiffrés (relais web ou dossier distant) — renversement borné de « rien sur le relais »

| | |
|---|---|
| **Statut** | **accepté le 15/11/2026** par la Direction (« il faut l’implémenter »). Il **renverse, pour les seules sauvegardes**, la règle « aucun octet de fichier ne passe par le relais » posée en v10 (`docs/architecture/DOCUMENTS-NUMERISES.md` : « le fichier ne vit jamais dans le magasin ni sur le relais ») ; il **ne modifie** ni ADR-0005, ni ADR-0006, ni ADR-0007 (la synchronisation courante, les échanges entre pairs et les indicateurs agrégés restent inchangés). |
| **Date** | 15/11/2026 |
| **Décideurs** | Direction, ingénierie |
| **Lié à** | ADR-0005 (relais opaque), ADR-0006, ADR-0007 (numérotation : le précédent ADR-0007 de ce dépôt traite des indicateurs agrégés ; celui-ci est le 0008), `docs/architecture/DOCUMENTS-NUMERISES.md`, `docs/architecture/ECARTS-MAQUETTE.md` (E2750 à E2762) |

## Contexte

La sauvegarde du magasin (copie chiffrée quotidienne de la base de la mère, `sauvegarderChiffre`) et celle du dossier des scans (copie incrémentale avec empreintes vérifiées) sont faites sur un **disque local**. Une panne de disque, un vol ou un incendie emportent les données **et** leur copie : une copie sur le même disque n’est pas une copie hors site. Le relais en ligne (`apps/web`, cPanel mutualisé) ne détient que le **journal chiffré** : c’est une copie hors site des données *synchronisées*, pas de la base de la mère, et pas un seul octet de scan.

La Direction a décidé de livrer, dans cette clinique aussi, la sauvegarde chiffrée hors site par le relais (« il faut l’implémenter »). La clinique sœur l’a livrée et vérifiée avant nous : le contrat (protocole, refus nommés, rotation à plancher, opacité) est repris tel quel, et adapté à ce dépôt (dossier des scans plat, un fichier par nom normalisé ; pas de module de stockage chiffré des scans).

## Options examinées

1. **Ne rien changer** (disque externe emporté à la main). Aucune dépendance en ligne ; mais cela dépend d’un geste humain quotidien que personne ne vérifie. C’est l’état actuel et la raison de la demande.
2. **Copier le dossier de sauvegarde tel quel vers un service tiers.** Écartée : le texte médical quitterait la clinique en clair ou sous une clé qu’elle ne maîtrise pas, et un service externe s’ajouterait.
3. **Relais web, blocs opaques chiffrés par la clé de la clinique** (retenue). Réutilise l’hébergement et le secret de la mère déjà en place ; le relais ne voit que des blocs chiffrés, leurs identifiants, tailles et dates. Inconvénient : l’espace disque d’un cPanel est borné (quota dit) et la taille d’une requête PHP aussi.
4. **Dossier distant monté** (partage réseau, disque d’un autre site). Même format, même chiffrement, aucune limite de requête ; la clinique le maîtrise. Inconvénient : la cible concrète n’est pas fournie ; SFTP n’est pas décrit ici, il n’est pas inventé.

Les options 3 et 4 sont livrées derrière **une même interface de destination** ; la clinique règle **une destination par type de copie** (magasin, fichiers), donc **jusqu’à deux destinations**.

## Décision

1. **Deux types de copie, réglages indépendants** : `magasin` (instantané de la base de la mère) et `fichiers` (le dossier des scans). Chacun a sa destination (`aucune`, `relais`, `dossier`) et sa rotation. **Désactivée par défaut** ; l’activation et le réglage sont réservés à l’**administrateur** et à la **Directrice Administrative** (`da`), avec un motif, journalisés (RG-12). Les réglages sont des **paramètres en base** (famille `horssite`, versionnés par date, défauts semés, jamais envoyés à un téléphone : RG-13) ; le panneau générique des paramètres ne les montre pas (écran dédié, règles de réglage propres).
2. **Chiffrement au poste mère, clé de la clinique, jamais envoyée.** Le clair est découpé en blocs de taille bornée (défaut 1 Mio) ; chaque bloc est chiffré AES-256-GCM par la clé de la clinique, au format `nonce (12) ‖ chiffré ‖ tag (16)`, les **métadonnées (genre, type, version) authentifiées** (AAD). Le nonce est dérivé (HMAC-SHA-256 de la clé sur l’empreinte du clair) : un même clair donne le même bloc, d’où le **dédoublonnage** et l’**idempotence du rejeu** sans état local. L’**identifiant d’un bloc est l’empreinte SHA-256 du bloc chiffré**. Le **manifeste** (liste ordonnée des éléments et de leurs blocs, tailles, empreintes du clair) est **chiffré lui aussi** et déposé comme blocs : la destination ne connaît ni noms de fichiers, ni formats, ni nombre de fichiers, seulement des identifiants de blocs.
3. **Une famille de routes dédiée `/sauvegarde/*`** sur le relais — jamais le journal (`/depot`), jamais une charge libre : état, blocs manquants, dépôt d’un bloc (octets bruts, empreinte revérifiée), ouverture d’une copie, rattachement, validation, liste, lecture. **Réservée à la mère** (en-tête de la mère) : un fileul ou un téléphone appairé reçoit **403 `sauvegarde_reservee_mere`**.
4. **Un garde-fou « bloc non chiffré » au dépôt.** Le relais ne détient aucune clé et ne peut pas *prouver* qu’un bloc est chiffré ; il refuse (**422 `BLOC_NON_CHIFFRE`**) ce qui ne l’est manifestement pas : un bloc d’au moins 4 Kio dont l’entropie est inférieure à 7,5 bits par octet, ou qui commence par une signature de fichier d’au moins quatre octets. C’est un détecteur d’oubli grossier, pas une preuve (un clair compressé au milieu d’un fichier passerait) : la clé protège, pas le relais.
5. **Bornes dites, refus nommés** (code, motif, geste) : limite par copie (`SAUVEGARDE_TROP_GROSSE`), plafond d’espace (`ESPACE_RELAIS_INSUFFISANT`, avec le geste : relever le quota, réduire le nombre de copies, passer à un dossier distant), bloc trop gros, bloc altéré en route, bloc manquant, rotation hors bornes. Tous les plafonds sont **en base du relais**, défauts semés, réglables au panneau.
6. **Rotation sans suppression sèche, purge à plancher.** Au-delà de N copies, la plus ancienne est **archivée** (restaurable, blocs gardés). Elle n’est **purgée** que si l’espace manque, la plus ancienne d’abord, **jamais une copie courante, jamais l’une des `plancher` plus récentes copies restaurables d’un type, jamais une copie en cours**. Une copie purgée garde sa ligne (date, taille, motif : RG-14) et le relais dit qu’elle n’est plus restaurable (410). Si l’espace manque encore : refus, **rien d’actuel n’est détruit**.
7. **Reprise après coupure.** Le client demande au relais les blocs manquants et ne dépose que ceux-là ; une copie n’est validée qu’une fois tous ses blocs rattachés ; une copie interrompue n’est jamais comptée.
8. **Restauration vérifiée avant d’écrire.** Elle télécharge, déchiffre et vérifie chaque bloc (empreinte du chiffré, authentification, empreinte du clair, longueur) et le manifeste. Un bloc altéré ou manquant est **refusé et nommé**, et **rien n’est restauré à moitié** : la base et les fichiers sont écrits dans une cible NEUVE, après la dernière vérification ; la base et le dossier en service ne sont **jamais** touchés par la restauration.
9. **Contrôle chaque nuit** (relecture de la dernière copie, quelques blocs téléchargés et vérifiés de bout en bout) ; **alerte si la dernière copie est trop ancienne** (au-delà de deux fréquences, signalée une fois) ; le journal technique de la mère ne porte **jamais** un nom de fichier, un nom de patient ni un contenu.
10. **Ce que le relais voit après cette décision** : pour la synchronisation, rien de plus qu’avant. Pour la sauvegarde : des blocs chiffrés, leurs identifiants, tailles et dates, des compteurs. L’écran « Opacité » du panneau le prouve sur les blocs (entropie, aucune signature, aucun mot du texte).

**Ce qu’on ne fait PAS** : aucun octet de sauvegarde en clair ; aucune clé au relais ; aucune sauvegarde par un téléphone ; pas de SFTP ; pas de suppression sèche tant que l’espace le permet ; pas de restauration qui remplace la base en service ; **les scans eux-mêmes restent servis fileul ↔ mère sans le relais** (v10) — seule leur *sauvegarde* chiffrée peut y être déposée.

## Conséquences

- **Positives** : une copie hors site, chiffrée, vérifiable, reprenable, par le relais déjà payé ou par un dossier de la clinique ; rotation bornée et dite ; aucune nouvelle dépendance en ligne.
- **Négatives, et ce qui les compense** : (a) l’espace d’un cPanel mutualisé est faible : quota dit, refus nommé, dossier distant en alternative, **mesure à faire avant la mise en service** ; (b) **la clé de la clinique devient la seule porte de la reprise après sinistre** : sans elle les blocs sont irrécupérables (exporter la clé, copie papier sous scellé, à décider par la Direction) ; (c) le relais détient désormais des octets de santé chiffrés : la sécurité repose sur la clé, pas sur le relais ; (d) le nonce dérivé révèle au relais que deux blocs sont identiques (pas leur contenu) : accepté et dit.
- **Schéma** : une migration du relais (blocs sur disque sous `storage/app/sauvegardes`, jamais en base ; trois tables de lignes), onze paramètres (famille `horssite`), aucune nouvelle collection du magasin.
- **RBAC** : réglage et restauration réservés à `admin` et `da` ; un fileul lit le réglage et ne le pose pas ; aucune modification de la matrice des droits.
- **Bancs** : le banc de protocole (`packages/sync/banc`) porte le protocole d’abord (relais de référence, client de référence, destinations relais et dossier) ; le relais Laravel rejoue les mêmes scénarios (`banc:laravel`) ; le domaine Dart porte les règles pures avec les vecteurs du banc ; le scénario `BAK1` pilote la mère (référence Node ou Dart) de bout en bout.

## Comment on vérifiera que c’était la bonne décision

Scénarios `SAUVHS1` à `SAUVHS4` (protocole) et `BAK1` (mère de bout en bout, deux destinations) ; `dart test` du domaine, du moteur et du poste ; l’écran « Opacité » du panneau ; une **restauration à blanc mensuelle** par l’administrateur sur une machine propre (à planifier) ; revue de cette ADR après la première mesure sur l’hébergement cPanel réel (espace, `post_max_size`, temps d’exécution).


## Note du 16/11/2026 (décisions Q31 à Q34)

- **Q31 confirmé** : blocs de 1 Mio, copies 7 (magasin) et 14 (fichiers), plancher 2, plafond 60 — des réglages de clinique, plus des « propositions ».
- **Q32** : le quota du relais (5 Gio évoqué) n'est **pas codé** ; il se mesure sur l'hébergement réel avec `tools/baguidi/mesurer-quota-relais.mjs` (guide `docs/guides/MESURER-LE-QUOTA-DU-RELAIS.md`).
- **Q33** : destination des fichiers par défaut « Aucune » tant que le volume n'est pas mesuré.
- **Q34** : SFTP **reporté** ; rien à faire, rien d'inventé.
