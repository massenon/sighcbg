# Documents numérisés : courriers (M13) et dossier patient (M1)

Portage du lot DOCS-1 de la clinique « Nassiera Too » (D0 à D4, sauvegarde SAUV-F) vers l'architecture de Baguidi, sur les décisions de la Direction de Baguidi du 12/11/2026. On a porté le COMPORTEMENT et les règles, pas le code PHP/JS.

## Ce que fait le lot
- **Le fichier ne vit jamais dans le magasin ni sur le relais.** Il est rangé dans un DOSSIER du poste mère (`<dossier des données>/scans` par défaut, réglable dans Paramètres système › Scans numérisés, « où sont mes scans » y est affiché) sous un NOM NORMALISÉ strict : courrier `2026-11-11_ARR_0042.pdf`, dossier patient `2026-11-05_CBG-12-26_compte-rendu-medical_007.pdf` (date du document, code patient sans barre, type sans accent, rang de la référence `GED-00007`). Un remplacement ajoute `_v2`, `_v3` : l'ancienne version reste sur disque.
- La fiche porte le champ `scan` (empreinte SHA-256, nom d'origine, nom normalisé, type MIME, taille, pages, texte indexé ou non, version, déposant, date) et `scansAnterieurs` (versions remplacées ou retirées, avec motif). Le registre `fichiers` (clé = empreinte) garde taille, pages et texte extrait.
- **« Numérisé » est DÉRIVÉ** de la présence d'un fichier (`docNumerise`), jamais saisi.
- **Fileul** : il dépose et lit chez la mère par `/sync/fichier/*`, blocs de 192 Ko scellés AES-256-GCM avec la clé de clinique (même enveloppe que le reste de la synchronisation), reprise au bloc attendu, empreinte recalculée à l'arrivée et à chaque lecture. Le relais n'est pas sur ce chemin ; il voit seulement les fiches (métadonnées chiffrées).
- **Droits** : aucune comparaison de nom de rôle. Les commandes d'écriture suivent le droit de l'écran (`editer` pour déposer et remplacer, `annuler` pour retirer) et sont ABSENTES sans droit. La lecture d'un document patient suit les CATÉGORIES SENSIBLES (`donnees_sensibles.dart`, `docCategoriesDesTypes`) : Pièce d'identité → `identite_detaillee`, Carte d'assurance → `couverture_assurance`, les autres types exigent `notes_consultation` (plus `resultats_analyses`, `diagnostic_pathologie` ou `hospitalisation_soins` selon le type). Les lignes illisibles sont retirées du tableau et ANNONCÉES, le moteur refuse aussi.
- **Journal RG-12** : dépôt, remplacement, consultation, téléchargement, retrait, réglage de taille, déplacement du dossier, migration.
- **Retrait** : motif obligatoire, annulable, jamais de suppression physique.
- **Recherche** : métadonnées, plage de dates, filtre « Texte non indexé », texte des PDF qui portent une couche texte (extracteur local `doc_pdf_texte.dart`). Un scan image est dit « texte non indexé » tant qu'aucune lecture n'existe. **OCR préparé, aucun moteur branché** (lot OCR-C, E2549 à E2560) : file locale, versions de texte lu (`lecturesOcr`, ajout seul, chiffrées vers le relais, jamais vers un téléphone), **correction signée** du texte lu par un agent habilité (nouvelle version, le texte machine est conservé), réglage décidé à la mère (`reglagesOcr`). Pas de recherche par le sens.
- **Migration du base64** de `documentsPatient` : dépôt, RELECTURE du fichier rangé, comparaison d'empreinte, ET SEULEMENT ALORS retrait du base64 (`docMigrerBase64`). Bouton sur `m1-documents` et lancement automatique à l'ouverture d'une mère ; idempotente.
- **Sauvegarde** : `sauvegarderChiffre` de la mère copie aussi le dossier des scans (incrémental, chaque fichier relu et comparé, `MANIFESTE.json`) vers `<sauvegardes>/scans`. **Restauration** : `POST /admin/fichiers/restaurer` vérifie chaque empreinte AVANT copie, refuse et nomme un fichier corrompu, n'écrase rien. Contrôle d'intégrité : `GET /admin/fichiers/controle`.

## Ce qui a changé par rapport à Nassiera, et pourquoi
| Nassiera | Baguidi | Motif |
|---|---|---|
| `api/fichiers.php` sur le serveur web, dossier `api/fichiers/` | dossier de la poste MÈRE (`StockFichiers`), canal de synchronisation scellé | décision de la Direction : le relais ne lit rien |
| Fichier servi derrière la session PHP | blocs AES-GCM par la clé de clinique, jeton d'appareil, refus des mobiles | pas de serveur web au poste ; RG-13 |
| Zones par liste de rôles (`ROLES_ZONE_2`) | catégories sensibles de la matrice | aucun nom de rôle en dur, droits administrables à chaud |
| Champ `fichier` (objet) | champ `scan` | `fichier` existe déjà au poste Baguidi (nom d'origine du document, texte) |
| Nom de téléchargement recalculé | nom de RANGEMENT physique = nom normalisé | décision de la Direction : le fichier est renommé |
| Glisser-déposer + lecteur PDF du navigateur | sélecteur de fichier du système + visionneuse d'image écrite pour le projet ; PDF : caractéristiques, extrait du texte, « Ouvrir avec l'application du poste » | aucun moteur de rendu PDF ni paquet de glisser-déposer disponible dans le projet |
| Règle serveur `regles-fichiers.json` engendrée | règle unique du domaine (`doc_regles.dart`), appliquée au poste ET à la mère | une seule règle, jamais deux copies |
| Taille maximale en base serveur | réglage `documentsBornes` dans `reglages` du poste mère, lu par la mère à chaque dépôt | la mère n'a pas de table des réglages |
| Sauvegarde nocturne PHP planifiée, trois tâches | la sauvegarde chiffrée existante de la mère emporte les scans ; contrôle et restauration en routes d'administration | l'architecture de sauvegarde de Baguidi est celle de la mère |

## Limites dites (à ne pas masquer)
- **Pas de glisser-déposer depuis l'explorateur** (aucun paquet), **pas d'aperçu de PDF page par page** (aucun moteur de rendu dans le projet) : repli « Ouvrir avec l'application du poste ».
- **Copie de sauvegarde des scans en clair** (comme le dossier lui-même, lisible par l'utilisateur de la mère) : à ranger sur un support protégé. La base reste sauvegardée chiffrée.
- **Un fileul a besoin de la clé de clinique** pour sceller ses blocs : il la lit dans la configuration d'échanges entre pairs (`pair.json`). Sans elle, le dépôt et la lecture sont refusés (`CLE_ABSENTE`). Un fileul hors réseau de la mère ne peut ni déposer ni lire (refus nommé, rien de gardé à moitié) ; la lecture n'est pas mise en cache sur le fileul.
- La mère authentifie l'appareil, pas son rôle : l'accès par rôle et par catégorie est tenu au POSTE (comme le reste de l'application). Un fichier n'est désigné que par son empreinte SHA-256.
- **Mode pair** (relais seul, sans mère) : les fiches `courriers`, `documentsPatient`, `fichiers` ne sont pas dans `famillesPair` ; elles voyagent par le pont de la mère.
- Le texte extrait d'un PDF fusionne les tables ToUnicode de toutes ses polices ; un PDF chiffré ou en LZW n'est pas lu (« texte non indexé » avec sa raison). Vérifié sur des PDF construits pour les tests, jamais sur un vrai scan de la clinique.
- Le jeu `courriers` de l'importation (`jeux_import_stock.dart`) écrit encore `numerise: false` : champ inerte désormais.
- Aucune version de schéma n'existe au poste : la nouvelle collection `fichiers` est livrée vide dans le jeu (161 collections).

## À valider par la Direction
Taille maximale par défaut (10 Mo, « à valider » affiché) · schéma du nom normalisé du dossier patient · rattachement des types de document aux catégories sensibles (Facture rangée au clinique par prudence ; WEBP gardé au dossier patient seulement, le poste le recevait déjà) · conservation illimitée de la copie de sauvegarde.

## Preuves
`packages/domaine/test/doc_regles_test.dart` (règles, SHA-256 sur les vecteurs du standard, noms, migration, extracteur) · `packages/sync_dart/test/fichiers_test.dart` (stock, canal scellé, sauvegarde-restauration) · `apps/poste/test/documents_scans_test.dart` (service et écrans) · banc `SCANS-D1` (`packages/sync/banc/scenarios-fichiers.js`, références Node et Dart).
