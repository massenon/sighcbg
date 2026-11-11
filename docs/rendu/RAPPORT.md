# Rendu réel des écrans et pièces récents (09/11/2026)

Décision de la Direction : « faut lancer le rendu ». Jusqu'ici ces écrans n'avaient été vérifiés que par des tests de widgets. Ils sont ici **dessinés pour de vrai** (vraies polices Inter, Montserrat, Dancing Script, jeu LIVRÉ `assets/donnees/jeu`, 1440 px de large, certaines pages en pleine hauteur) puis **regardés image par image**.

Méthode : un test Flutter jetable (`apps/poste/test/rendu_jetable_test.dart`, ignoré sans `SIGH_RENDU=<dossier>`, NON commité) monte `SighPoste` sous un rôle ayant le droit, pilote l'écran (onglets, modales, tiroirs) et écrit un PNG par `RenderRepaintBoundary.toImage`. Les PDF des spécimens (`presentation/`) sont rendus par `pdftoppm`. 53 images déposées ici (≤ 285 Ko chacune) ; images « avant » préfixées `avant-`.

Particularité du banc : la pastille du code de module (« M7 », « CFG ») s'écrit en police Consolas, absente de cette machine ; sans alias elle sortait en carrés. Ce n'est pas un défaut du poste (Windows la possède) : le test charge LiberationMono sous ce nom.

## Défauts corrigés à la racine (9)

| # | Défaut vu à l'image | Cause | Correction | Image avant → après |
|---|---|---|---|---|
| 1 | **Toutes les modales** (« Nouveau taux d'AIB », « Retenir l'AIB », ticket…) : en-tête et corps teintés de gris, bande blanche de 20 px au-dessus du titre | `BoxDecoration(boxShadow)` sans fond : l'ombre se peint aussi sous un cadre transparent ; le blanc du `Material` était recouvert | fond blanc porté par la décoration (modale, tiroir, panneau des listes déroulantes) — `kit/modale.dart`, `kit/formulaire.dart` | avant-18, avant-28, avant-12 → 18, 28, 12 |
| 2 | Aperçu du **ticket 80 mm** collé à gauche de la modale | `Center` dans un défilement horizontal (largeur non bornée) ne centre rien | largeur disponible imposée comme minimum (ticket et A4) — `impression/apercu.dart` | avant-12 → 12 |
| 3 | Facturation : « Montant réglé » affiche **1000.0** | `'${partPatient}'` d'un `double` | entier sans décimale — `m8/facturation.dart` | avant-11 → 11 |
| 4 | Statistiques de spécialité : axe vertical **4 · 4 · 3 · 3 · 2 · 2 · 1 · 1 · 0** | graduations fractionnaires arrondies à l'entier | graduations 0,5 · 1,5… gardent leur décimale — `kit/graphiques.dart` | avant-04 → 04 |
| 5 | Médecine du travail : « périodiques **0** » alors que 55 visites périodiques ; filtre « Nature » aveugle sur elles | le jeu écrivait le libellé accentué `périodique` au lieu du code `periodique` (`tool/jeu_baguidi/clinique_soins.dart`) | générateur corrigé, jeu régénéré (seul `consultations.json` change), lecture tolérante pour les fiches anciennes — `m2/sp_travail.dart` | avant-06 → 06 |
| 6 | « Rechercher **un** situation… », « Aucun consultation enregistré », « un convention » | gabarit `un ${entité}` sans accord | `kit/accord.dart` (`rechercherEntite`, `aucuneEntiteEnregistree`) branché dans les 8 tableaux CRUD | 16, 08 |
| 7 | Factures fournisseurs : colonne **Actions rognée** (« ACTIO », icônes Retenir l'AIB / Constater l'AIB coupées) à 1440 px | douze colonnes non coupables dépassent la largeur | nouveau paramètre `colonnesMasquees` du tableau ; « Montant livré » masqué à l'ouverture, remis par « Colonnes » ; références sans `sansCoupure` | avant-27 → 27 |
| 8 | Fenêtre « Facture normalisée », liste « Situation de l'acheteur » : **deux lignes cochées** (« — Aucun — » et « Automatique ») | l'option « Automatique » a la valeur vide, la même que « Aucun » | pas de ligne « Aucun » quand une option porte la valeur vide — `kit/formulaire.dart` | avant-26 → 26 |
| 9 | (même racine que 1) panneau des listes déroulantes grisé | idem | idem | — |

Tests de non-régression : `apps/poste/test/rendu_regressions_test.dart` (accord des articles, codes de nature de visite du jeu livré, montant réglé sans « .0 », ticket centré et modale blanche, liste sans doublon « Aucun »). Le défaut 4 (axe) n'a pas de test : la fonction est privée, il se vérifie à l'image 04.

## Tableau écran → image → verdict

| Écran / pièce | Image | Verdict |
|---|---|---|
| Répertoire des 14 spécialités `m2-specialites` | 01 | conforme (table à défilement horizontal interne : colonne « CONSU… » au bord) |
| Hub de spécialité (cardiologie) | 02 | conforme |
| Consultation spécialisée | 03, 39 (formulaire) | conforme ; « Aucune … enregistrée » corrigé (6) |
| Statistique de spécialité | 04 | défaut corrigé (4) |
| Agenda de spécialité | 05 | conforme |
| Médecine du travail : visites | 06, 37 (tiroir + « Imprimer la fiche d'aptitude »), 38 (nouvelle visite) | défaut corrigé (5) ; modale grisée corrigée (1) |
| Entreprises clientes et salariés | 07 | conforme |
| Conventions de visites | 08 | conforme (« Rechercher un convention » corrigé, 6) |
| Facturation : formulaire, liste des patients | 09, 09b | conforme |
| Facturation « Client libre » (formulaire, ligne) | 10, 11, 13 | défaut corrigé (3) |
| Ticket 80 mm (aperçu) | 12 | défaut corrigé (1, 2) |
| `m12-aib` : barème + retenues, Taux à une date, Situations, AIB subi, modale « Nouveau » | 14 à 18 | conforme après (1, 6) ; voir restants R3 |
| `cfg-validations-aib` : Barème, Base, Branchement IFU, Comptes de l'AIB | 19 à 22 | conforme |
| Configuration MECeF | 24 | conforme |
| Fenêtre « Facture normalisée » + note du taux d'AIB | 25, 26 | défaut corrigé (8) |
| Factures fournisseurs ; modales « Retenir l'AIB » et « Constater l'AIB subi » | 27, 28, 29 | défauts corrigés (7, 1) |
| Calendrier fiscal (`cfg-comptabilite`) : CNSS au 10, CNSS-VERS « Non arrêtée (à valider) » | 30 | conforme |
| `m12-echeances` : CNSS-VERS en retard, « Date non arrêtée (à valider) » | 31 | conforme |
| Archivage du jeu : onglet Jeux de test verrouillé, autorisé, confirmation, bilan | 32, 33, 34, 35 | conforme ; voir R1 |
| `mere-reinit` | 36 | conforme (bandeau « service de la mère » normal sans service) |
| Fiche d'aptitude (PDF) | pdf-fiche-d-aptitude-… | conforme : en-tête Baguidi, tampon SPÉCIMEN, aucune trace de l'ancienne clinique |
| Comptes rendus de spécialité (PDF cardiologie, médecine du travail), certificat d'aptitude | pdf-compte-rendu-…, pdf-certificat-… | conforme |
| Barème AIB (PDF) | pdf-bareme-de-l-aib-… | conforme |
| Ticket de caisse 80 mm (PDF) | pdf-ticket-de-caisse-80-mm-1 | conforme (voir R4) |

## Défauts restants

| # | Défaut | Gravité | Pourquoi non corrigé |
|---|---|---|---|
| R1 | Onglet « Jeux de test » : les pastilles « Ce qui serait archivé / conservé » et le bilan nomment les collections par leur **clé technique** (`facturesFournisseurs (6)`, `demandesAnalyses`, `ecritures`, `poches`…) | moyenne (lisible par un administrateur, illisible pour la Direction) | `cfb_systeme.dart` partie archivage : fichier de l'autre agent. Le magasin a déjà `LIBELLES` pour la corbeille : à réutiliser |
| R2 | Bilan d'archivage : `echeancesFiscales (75)` reste listé « archivé » dans « Ce qui serait archivé » après l'archivage (les échéances sont volontairement conservées) | faible | même fichier |
| R3 | `m12-aib` : à 900 px de haut, le tableau des taux est sous trois bandeaux, deux KPI et deux rangées d'onglets (registres puis barème) ; la hiérarchie des deux groupes d'onglets prête à confusion | faible (ergonomie) | choix de composition, pas une panne |
| R4 | Ticket avant normalisation : « CODE DGI : CODE-DGI-EN-ATTENTE / DEMONSTRATION », « NIM : NIM0… » en valeurs d'attente | faible | placeholders assumés avant le retour du dispositif ; à relire à la mise en service |
| R5 | Aucune pièce imprimée de **retenue d'AIB** ni de **bilan d'archivage** dans `presentation/` : ces pièces ne s'impriment pas (le bilan est un écran) | information | rien à rendre |
| R6 | Tableaux larges ailleurs que `m7-factures-fournisseurs` : même mécanisme (colonnes non coupables > largeur) possible ; seuls les écrans de la liste de mission ont été balayés à 1440 px. Sous 1100 px non rendu | moyenne (à balayer) | un balayage des 300 écrans à 1100 px reste à faire avec ce banc |
| R7 | Première capture d'une série : logo de l'en-tête parfois vide (décodage d'image asynchrone du banc, corrigé par une attente) | nulle | artefact du banc |
