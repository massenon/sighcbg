# Procédure : restaurer la poste mère tombée, depuis la sauvegarde hors site

Décision de la Direction (Q37, 17/11/2026) : **pas de promotion d'un fileul en mère de secours, pas maintenant.** Le chemin est la **restauration de la mère depuis la copie hors site** (ADR-0008). Ce document dit ce que le code permet réellement ; ce qui n'est pas vérifié est marqué comme tel.

## Avant la panne (à avoir en main, sinon la procédure est impossible)

1. **La clé de la clinique.** Les blocs sont chiffrés (AES-256-GCM) par elle ; sans elle ils sont irrécupérables (ADR-0008, conséquence négative b). Une copie sous scellé, hors de la mère, est à la charge de la Direction.
2. **Les réglages de la copie** : activée, destination du magasin (relais web ou dossier distant monté), destination des fichiers. Réglables par l'administrateur et la Directrice Administrative (liste de rôles du réglage `horssite`, pas encore un geste réservé de la fiche de rôle : voir E3077). La copie du magasin est de NUIT (une par jour) ; celle des fichiers suit sa fréquence (une heure par défaut).
3. **Une restauration à blanc mensuelle** sur une machine propre (prévue par l'ADR) : elle prouve que la clé, la destination et la procédure fonctionnent AVANT le jour où l'on en a besoin.

## Ce que la restauration fait, et ne fait pas

* Elle écrit dans un **dossier NEUF** (`CIBLE_EXISTE` si la cible existe) ; elle ne touche **jamais** la base ni le dossier des scans en service.
* Elle télécharge, déchiffre et vérifie chaque bloc (empreinte du chiffré, authentification, empreinte du clair, longueur) et le manifeste **avant** d'écrire ; un bloc altéré ou manquant est refusé et nommé (`BLOC_ALTERE`, `BLOC_MANQUANT`, `MANIFESTE_ALTERE`), **rien n'est restauré à moitié**. On choisit alors une autre copie.
* Magasin : `<cible>/magasin` (la copie de la base de la mère). Fichiers : `<cible>/fichiers/<nom normalisé>` avec un `MANIFESTE.json`, l'index reconstruit.
* **Elle ne remet pas la mère en service d'elle-même.** Le basculement est un geste humain, décrit ci-dessous.

## Procédure

**0. Constater.** Les fileuls affichent « mère injoignable » : ils continuent de saisir, leurs opérations restent en file (rien n'est perdu, rien ne les bloque). Ne pas réinitialiser un fileul.

**1. Préparer une machine** (la même, réparée, ou une autre) avec le poste installé en mode mère et les mêmes versions que la mère tombée. Y disposer de : la clé de la clinique, l'adresse et le secret d'accès de la destination (relais web) ou le dossier distant monté, le secret d'administration de la mère.

**2. Choisir la copie.** Poste mère, « Sauvegardes et restauration » (hors site) : lister les copies du type `magasin`, prendre la plus récente **restaurable** (état « valide »). Une copie « purgée » (410) ou « en cours » n'est pas restaurable.

**3. Restaurer le magasin** vers un dossier neuf, par la commande « Restaurer vers une cible neuve » (route `POST /admin/horssite/restaurer`, type `magasin`). Lire le résultat : nombre d'éléments et d'octets vérifiés. En cas de refus, relire le code, changer de copie.

**4. Restaurer les fichiers numérisés** de la même façon (type `fichiers`) vers un second dossier neuf. Ils sont sauvegardés plus souvent que le magasin : un scan déposé après la dernière copie n'y est pas.

**5. Mettre en service** (geste manuel, la mère arrêtée) : placer la copie du magasin à l'emplacement de la base de la mère (paramètre `--db` du service) et le dossier restauré à celui des scans, puis redémarrer la mère. *Le fichier restauré est la copie de la base telle que la mère la sauvegarde ; la réouverture sous la clé de stockage de la clinique n'a pas été rejouée dans ce lot.*

**6. Contrôler avant de rouvrir aux postes** : la console de la mère (état, base, intégrité des fichiers) ; le compteur de pièces ; la date de la dernière écriture, qui **dit ce qui manque** (voir « Ce qui peut manquer »).

**7. Laisser les fileuls se rattacher.** Ils renvoient leurs opérations en file ; la mère les applique avec ses contrôles habituels et le verdict revient. Une pièce d'un exercice clos ou en clôture est **mise de côté** (`exercice_clos`, `exercice_en_cloture`) et listée, jamais écrite ni perdue. *L'époque de la mère est conservée dans la base restaurée ; le comportement exact d'un fileul dont le journal est plus avancé que la copie restaurée n'a pas été rejoué ici : à vérifier à la restauration à blanc.*

## Ce qui peut manquer (à dire à la Direction, sans l'inventer)

* **Tout ce qui a été écrit sur la mère depuis la dernière copie du magasin** (jusqu'à 30 heures : copie de nuit). Les opérations des fileuls, elles, reviennent de leurs files tant qu'elles n'ont pas été confirmées par la mère ; **celles que la mère avait déjà confirmées puis perdues ne sont pas toutes rejouables par les fileuls** : c'est la mesure à faire à blanc.
* Les scans déposés après la dernière copie des fichiers.
* **Les références numérotées par la mère** (plages, codes patients, numéros de pièces) : la mère restaurée reprend ses compteurs d'avant la panne ; les plages déjà remises aux fileuls leur appartiennent et sont respectées (RG-01).

## Ce qui n'existe pas (et qu'on ne simule pas)

* Pas de promotion d'un fileul en mère (décision du 17/11/2026) : aucun fileul ne porte les droits ni la clé de la mère.
* Pas de basculement automatique : la restauration est vérifiée, la mise en service est humaine.
* Pas de SFTP (reporté, Q34). Quota du relais à mesurer sur l'hébergement réel avant mise en service (Q32).

## Qui peut le faire

La restauration et la lecture des copies sont réservées à l'administrateur et à la Directrice Administrative ; un fileul ne les voit pas (`REGLAGE_RESERVE`).
