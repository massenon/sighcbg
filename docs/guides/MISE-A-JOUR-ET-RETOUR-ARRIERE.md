# Mettre à jour le logiciel, et revenir en arrière

Décision 12 de la Direction de Baguidi (17/11/2026, `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md` § 12). Ce guide dit ce que le code fait réellement ; ce qui n'est pas vérifié est marqué comme tel.

## Les principes

1. **Une mise à jour peut changer la forme des données.** Le logiciel porte un numéro de **schéma des données** (constante unique `schemaDonneesCourant`, domaine, `schema_donnees.dart`), écrit dans la méta du magasin du poste et dans celle de la mère, lu à chaque ouverture.
2. **Jamais d'écrasement, jamais de perte.** Un magasin ou une base de mère écrits par une version **plus récente** que le logiciel sont **refusés en les nommant** (`SCHEMA_PLUS_RECENT`, ou `SCHEMA_ILLISIBLE` si le numéro est illisible) : rien n'est lu, rien n'est modifié (vérifié octet par octet par les tests). Le poste affiche le refus au démarrage au lieu de s'ouvrir.
3. **Une migration n'est jamais seulement destructive.** La chaîne (`migrationsDonnees`) est ordonnée, contiguë à partir de 1, idempotente (chaque migration ne joue que si le schéma est inférieur à son numéro), journalisée dans la méta (`migrations` : numéro, nom, date, comptes — jamais une fiche). **Avant** d'écrire la forme convertie, la **forme d'origine** de chaque collection modifiée est rangée à côté : `<dossier du magasin>/migrations/avant-<n>/<collection>.sigh` (chiffrée comme le reste). La migration n° 1 est celle des constantes du lot B (tension en deux nombres, diurèse en millilitres) : l'ancienne marque `formeConstantes` du poste en est devenue le numéro 1.
4. **Une mise à jour ne s'installe qu'avec une sauvegarde vérifiée.** L'installeur Windows bloque sinon (voir « Préparer »).

## Procédure pas à pas

### 1. Préparer (sur le poste à mettre à jour, avant d'installer)

Écran **« Export, import et mise à jour »** (Paramètres, Système) ou, sur la mère, **« Mises à jour et compatibilité »** : carte **« Préparer la mise à jour »**.

* Elle lit le réglage **« Ancienneté maximale de la sauvegarde avant une mise à jour »** (famille « Mise à jour du logiciel », paramètre daté `maj.sauvegardeMaxHeures`, 24 h par défaut — **valeur d'attente à valider par la Direction**, bornée de 1 à 168).
* **Mère** : elle fait la sauvegarde chiffrée de la base, **la relit** (déchiffrement, ouverture de la copie, contrôle d'intégrité) puis fait l'export portable et **le relit**. **Fileul** : l'export portable, qui porte la file des saisies non confirmées, tient lieu de sauvegarde (un fileul n'a pas de sauvegarde de la mère à contrôler).
* Si **les deux preuves ont moins de N heures et sont vérifiées**, elle écrit `autorisation-mise-a-jour.txt` dans le dossier des données (valable 4 heures, pour une seule mise à jour). Sinon elle **retire** toute autorisation et l'écran dit, en les nommant, ce qui manque : `SAUVEGARDE_ABSENTE`, `SAUVEGARDE_TROP_ANCIENNE`, `SAUVEGARDE_NON_VERIFIEE`, `EXPORT_ABSENT`, `EXPORT_TROP_ANCIEN`, `EXPORT_NON_VERIFIE`.
* Droit : le geste réservé `base_exporter` (administrateur et DAF d'origine, réglable en fiche de rôle).

### 2. Sauvegarder et exporter (c'est fait par « Préparer », mais on peut le faire à la main)

* **Exporter la base complète** : un seul fichier `.sghx`, chiffré par la clé de la clinique, avec son manifeste lisible sans clé. À **ranger hors de la machine** (clé USB, autre poste) : un export qui reste sur le disque qu'on va réinstaller ne protège de rien.
* **La clé de la clinique doit être sous scellé, hors de la machine.** Sans elle, ni l'export ni la sauvegarde ne se rouvrent.

### 3. Installer

Lancer l'installeur `SIGH_Poste_Setup_<version>.exe`. Sur une machine qui porte déjà des données (dossier `magasin` ou `mere.db`), **il refuse** sans autorisation valide, avec le message `Mise à jour BLOQUÉE : AUTORISATION_ABSENTE | AUTORISATION_EXPIREE | AUTORISATION_ILLISIBLE`. Sur une première installation (aucune donnée), il passe. À la fin, il retire l'autorisation : une autorisation vaut pour une mise à jour.

**Cas de force majeure** : l'écran porte « Lever le blocage (force majeure) », geste réservé `maj_lever_blocage` (administrateur et DAF d'origine), **motif obligatoire** (10 caractères au moins) ; l'auteur, la date et le motif sont écrits au journal d'audit, et l'autorisation porte `levee=oui`.

> **Limite assumée.** Le fichier d'autorisation protège contre l'**oubli**, pas contre un administrateur de la machine qui voudrait le contourner (il peut l'écrire lui-même). Le script Pascal de l'installeur (`apps/poste/installer/sigh_poste.iss`) **n'a pas été compilé ni exécuté** dans cet environnement (pas d'Inno Setup) : la logique d'autorisation est prouvée côté Dart (`majLireAutorisation`, mêmes codes, même format) et un test garde que le script cite les mêmes constantes ; l'exécution réelle de l'installeur reste à recetter sur une machine Windows.

### 4. Contrôler

Au premier démarrage de la nouvelle version : le poste ouvre le magasin, joue la chaîne de migrations si elle est nécessaire (le journal d'audit et la méta `migrations` en font foi), et refuse en les nommant un magasin plus récent. Contrôler :

* le nombre de fiches par ensemble (l'export de contrôle donne les mêmes **compteurs** que le manifeste de l'export d'avant) ;
* sur la mère, « Mises à jour et compatibilité » : version, appareils ;
* qu'un fileul se resynchronise (journal de la mère, « À traiter »).

### 5. Revenir en arrière

Deux cas.

**A. La migration a eu lieu et l'on veut revenir à l'ancienne version du logiciel.**

1. Fermer le poste. **Ne pas** lancer l'ancienne version sur le magasin migré : s'il est au schéma plus récent, elle le **refusera en le nommant** (c'est voulu : jamais d'écrasement).
2. Réinstaller l'**ancienne version** du logiciel (l'installeur d'avant ; il exige lui aussi une autorisation : « Préparer » sur la version courante, ou la levée de blocage).
3. Rétablir les données **d'avant** : *soit* l'**export** fait avant la mise à jour (écran « Export, import et mise à jour » de l'ancienne version, **Importer** dans un magasin neuf, puis **mise en service**), *soit* la **forme d'origine** rangée par la migration (`migrations/avant-<n>/`, à recopier à la place des collections concernées, poste arrêté). L'export est la voie normale ; les formes d'origine servent au cas où l'export manquerait.
4. Sur un fileul rattaché : la mère reste l'autorité ; il se resynchronise ensuite. Ses saisies non confirmées sont dans la file (elles voyagent avec l'export d'un fileul).

**B. L'installation elle-même a échoué.** Les données ne sont jamais dans le dossier du programme (`%LOCALAPPDATA%\SIGHCBG\donnees`) : réinstaller l'ancienne version les retrouve telles quelles.

> L'ancien magasin n'est **jamais supprimé** : la mise en service d'un import le **renomme** (`magasin.avant-import-<date>`, `mere.db.avant-import-<date>`).

## Export et import : ce qui est vrai

* **Export** (`base_exporter`) : un fichier, manifeste en clair (version du logiciel, schéma, date, identité de la clinique, compteurs par collection, empreinte du contenu, empreinte **courte** de la clé), contenu compressé et chiffré par la clé de la clinique (AES-256-GCM, le chiffrement des sauvegardes). **Vérifié sans rien écrire** par « Vérifier le fichier ».
* **Ce qui voyage** : toutes les collections du magasin (archivées comprises), sa méta ; pour une **mère**, les tables de son journal de synchronisation ; pour un **fileul**, sa **file d'opérations non confirmées**, ses plages de numéros, ses baux, son étiquette.
* **Ce qui ne voyage jamais** : la clé de la clinique ; les hachés des mots de passe (`identifiants`) — **les mots de passe se redéfinissent sur le poste d'arrivée** (réinitialisation de compte) ; les jetons des liens publics d'enquête ; les codes d'appairage non utilisés ; toute clé de méta qui nomme une clé, un secret, un jeton ou un mot de passe. Le mot de passe de la messagerie et les fichiers numérisés ne sont **pas** dans le magasin et ne sont pas dans l'export (les scans ont leur propre copie).
* **Import** (`base_importer`) : contrôles dans l'ordre, **avant** d'écrire — format, schéma (`SCHEMA_PLUS_RECENT`), clinique (`AUTRE_CLINIQUE`), rôle de la source (`FILEUL_VERS_MERE`), cible neuve (`CIBLE_EXISTE`), puis clé (`CLE_ABSENTE`, `CLE_INCORRECTE`), authentification (`FICHIER_ALTERE`, `MANIFESTE_ALTERE`), empreinte (`EMPREINTE_DIFFERENTE`). Il écrit dans un **dossier neuf** ; la **mise en service** est un second geste (motif, journal), appliqué au **démarrage suivant** (l'ancien magasin est renommé, jamais supprimé). Une mise en service exige un **export vérifié de moins de N heures** (la copie du magasin remplacé).
* **Fileul** : l'export d'un fileul importé sur un fileul **neuf** reprend sa file (aucune saisie perdue, aucun doublon : les opérations gardent leur identifiant, la mère les reconnaît) ; le nouveau poste s'appaire par un **code de reprise** que l'administrateur émet à la mère (`POST /admin/code` avec `reprise`), qui lui passe les plages et **révoque l'ancien poste** (sans quoi la mère refuserait les codes de dossier hors plage : prouvé par le banc, `numero_hors_plage`). Un fileul **rattaché** qui importe fait d'abord une **copie préalable vérifiée** de son magasin ; un import **plus ancien que sa dernière synchronisation** avertit (non bloquant) et **liste** les saisies postérieures non synchronisées (gardées dans la file et dans `saisies-non-synchronisees.json`, jamais écrasées). Un export de **mère** importé sur un fileul rattaché n'est qu'un **point de départ de resynchronisation** : la mère reste l'autorité et renvoie ce qu'elle a validé. Un fileul **non rattaché** importe comme une mère de lui-même. Un fichier d'une **autre clinique** est refusé.
* **Mère** : l'import rejoue le journal dans une **base neuve** (`mere.db`) et y remet la clé de la clinique ; les fileuls continuent avec leur jeton et leur plage, sans se réappairer (prouvé en Dart).

## Ce qui n'a pas été vérifié (à dire à la Direction)

* L'**installeur Windows** n'a pas été exécuté (voir plus haut).
* La **réouverture d'une mère importée sous la clé de stockage SQLCipher du poste** n'a pas été rejouée (les tests ouvrent la base sans chiffrement de stockage ; l'import passe par `Mere.creer`, donc par le même chemin que la mère en service).
* Une **mère sur PostgreSQL** : l'import écrit dans une base **SQLite** neuve ; la cible PostgreSQL n'est pas couverte.
* Un **export de mère volumineux** se tient **en mémoire** (le journal entier en JSON puis compressé) : à mesurer sur la base réelle avant de compter dessus.
* Le **banc de synchronisation** (Node) mène la resynchronisation d'un fileul exporté (scénario `BASEPORT1`) ; le **fichier chiffré** lui-même est prouvé par les tests Dart. Le banc ne rejoue pas un export de mère (les deux mères, Node et Dart, n'ont pas la même base : l'import de mère n'existe qu'en Dart).
