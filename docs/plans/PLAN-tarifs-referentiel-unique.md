# PLAN (Baguidi) : référentiel de prix unique, écran « Tarifs et prix », changement de prix validé et jamais rétroactif

Source : le chantier livré et vérifié par la clinique sœur (lots T0 à T6) et les réponses de la Direction T1 à T15, valables pour Baguidi. Écarts : `docs/architecture/ECARTS-MAQUETTE.md` E2575 à E2586. Baguidi n'a pas de maquette JavaScript : le comportement est porté en Dart pur (domaine) puis en écrans Flutter, adapté à l'architecture de Baguidi (famille de synchronisation, mère et fileuls, droits par la matrice, gestes réservés, sélecteur du kit, `K.importer`).

## Résultat attendu
- UNE liste de prix lue par la caisse, la prescription, les soins, l'imagerie, les certificats, la consultation spécialisée et la caisse manuelle, au prix EN VIGUEUR à la DATE de la pièce ; UN écran « Tarifs et prix » pour proposer, décider (Oui ou Non) et lire l'historique.
- Une pièce émise garde son prix : le prix se versionne par date d'effet, une version est immuable (RG-14).
- Aucun prix facturé aujourd'hui ne change à la migration. Baguidi n'a remis AUCUNE grille imprimée : aucune proposition n'est inventée.

## Étapes
### TAR-0 : caractérisation [FAIT 14/11/2026]
- Le relevé exhaustif d'AVANT (`apps/poste/test/fixtures/tarifs/prix-avant-tar.json`) est tiré de l'arbre d'avant le lot (commit 7fff32b1) par le harnais décrit à `test/tarifs_capture_poste_test.dart` : 277 codes (151 de grille, 78 actes, 48 analyses), cinq voies par code et par colonne (accesseur de grille, prescription d'acte, prescription d'analyse, soins, imagerie), plus les listes de la caisse manuelle (actes, analyses, journée d'hospitalisation) et les 15 types de certificat.
- Constats : (1) la caisse, la prescription et la consultation spécialisée lisaient `actes`, `catalogueTarifs` et `analyses` : trois listes, trois règles ; (2) le code de grille `CERT-APT` est porté par DEUX lignes (« Certificat médical d'aptitude » 7 000, « Certificat d'aptitude » 5 000) : l'ancien lecteur prenait la première (E2578) ; (3) prescrire un code d'acte absent de `actes` rend une ligne à 0 (199 codes sur 277) : mesuré, non corrigé (E2584).
### TAR-1 : socle et adaptateur de lecture [FAIT]
- `packages/domaine/lib/src/tarifs/tarifs.dart` (moteur pur : version, résolution à la date, migration, gardes), accesseur `TarifsPoste` (`apps/poste/lib/donnees/tarifs_poste.dart`), collections `tarifs` et `versionsTarif` (famille R), projection de lecture de `actes`, `analyses`, `catalogueTarifs` (reconstruite par la mère), gardes d'immutabilité au magasin, reprise d'un poste déjà peuplé, jeu livré engendré (206 prestations, 206 versions 1).
- Critère : relevé après = relevé avant. Mesuré : 0 écart inattendu sur 277 codes ; 117 écarts ATTENDUS et nommés (39 lignes LABO de la grille fusionnées avec leur analyse, sur trois voies que personne n'emprunte : E2577).
### TAR-2 : l'écran unique [FAIT]
- `apps/poste/lib/modules/cfg/cft_tarifs.dart`, étiquette « Tarifs et prix » (T15), deux droits distincts : PROPOSER = éditer l'écran ; DÉCIDER et DATER DANS LE PASSÉ = deux gestes réservés de la matrice (`tarif_decider`, `tarif_dater_passe`), aucun nom de rôle dans le moteur (E2579).
### TAR-3 : circuit Oui ou Non complet [FAIT]
- Contrôle d'usage (date passée refusée dès qu'une pièce a utilisé la prestation depuis cette date ; sinon DAF et Direction par la matrice, avec la case et le motif), bouton « Valider » de la modale (Enregistrée devient Validée), « Oui à tout » encadré, ligne impayée figée à la prescription (T4), pro-forma gardée 30 jours réglables en base (T5), info-bulle de la date passée dérivée de la matrice (T6).
### TAR-4 : importation par proposition [FAIT]
- Jeu `tarifs` (`packages/domaine/lib/src/import/jeux_import_tarifs.dart`) qui remplace l'ancien « catalogue des actes » (qui écrivait des prix dans une liste devenue projection) ; même chemin que l'écran (`tarProposer`), colonne « Valider (Oui/Non) » : vide = à valider, Non = consigné avec son motif sans version (T7). Réservé à la mère (E2582).
### TAR-6 : synchronisation [FAIT]
- Famille R pour `tarifs` et `versionsTarif`, famille A pour `propositionsTarif` (un fileul DÉPOSE, la mère applique sous le rôle de l'auteur) ; aucun prix vers un mobile ; l'application des demandes côté mère est BRANCHÉE en production (`ApplicateurDemandesTarif`, démarré par `main.dart`), prouvée contre la vraie mère Dart (`tarifs_sync_test.dart`) : E2580.
### T12 : la journée d'hospitalisation [FAIT]
- `TarifsPoste.tarifsJournee` : les écrans des chambres, le plan des lits, le tableau des hospitalisations (pilotage) et la caisse lisent la journée au référentiel (prestations HO01 à HO03).
### À FAIRE, hors lot
- T13 : les garanties des assureurs seront aussi datées (chantier séparé, NON fait ici).
- Les produits (prix d'achat versionné), l'impression de la grille comparée, la comparaison avec une grille imprimée : hors lot par décision.
- Retrait des anciennes listes comme source (T7 de la sœur) : `actes`, `analyses`, `catalogueTarifs` restent des projections de lecture.
- Régénération du dictionnaire de données (`DICTIONNAIRE-DONNEES.md`, `packages/schema`) pour `tarifs`, `versionsTarif`, `propositionsTarif`.
- Essai en application réelle (Windows, deux machines, relais) : non fait.

## Commandes
- `cd packages/domaine && dart test test/tarifs_test.dart test/tarifs_import_test.dart test/gestes_reserves_test.dart test/import_test.dart`
- `cd apps/poste && flutter test test/tarifs_capture_poste_test.dart test/tarifs_poste_test.dart test/tarifs_ecran_test.dart test/tarifs_sync_test.dart`
- Régénérer le jeu : `cd apps/poste && flutter test tool/generer_jeu_baguidi.dart`.
