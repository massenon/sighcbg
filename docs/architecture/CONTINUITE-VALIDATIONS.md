# Continuité de service des validations (Direction de Baguidi, 15/11/2026)

> « Une validation à faire ne doit JAMAIS empêcher le fileul de travailler. Une validation créée par un fileul et qui devrait être validée par la mère : le poste de la mère n'est pas fait pour valider (c'est un poste qui porte la clinique, pas un poste de validation) ; il faut une CONTINUITÉ DES SERVICES. »

Quatre exigences : (a) aucun état « en attente de validation » ne bloque le poste qui l'a créé ; (b) le validateur (celui que la matrice autorise) valide DEPUIS N'IMPORTE QUEL POSTE, la mère appliquant mécaniquement sous le rôle de l'auteur, tous les contrôles refaits ; (c) mère injoignable : l'état dit « en attente de la mère », jamais « validé » avant confirmation ; (d) la validation déposée est rejouable sans effet double, le verdict revient au fileul.

## Ce que l'audit a trouvé (par lecture du code, par calcul sur les constantes de la production, par tests contre la vraie mère Dart)

**Aucun état « en attente de validation » ne bloque son auteur** : les gardes trouvées sont des dépendances de nature (une commande ne part pas chez le fournisseur sans la DAF, RG-04 ; la clôture définitive refuse les brouillons ; un résultat non validé n'est pas rendu au prescripteur ; un taux d'AIB non arrêté refuse la vente à l'acheteur concerné). L'auteur saisit, facture, encaisse, délivre pendant ce temps (sondé pour les écritures).

**Le vrai défaut était ailleurs : trois classes de collections, et seule la première permettait la validation à distance.**
La classe se calcule sur les constantes de la production (`collectionsConfiguration()`, `collectionsActivite`) ; `continuite_validations_audit_test.dart` fige ce tableau, il ne peut donc pas se périmer en silence.

| Classe | Définition | Le validateur peut valider depuis un autre poste ? |
|---|---|---|
| **R** configuration | la mère seule écrit, le fileul reçoit | AVANT : non, geste refusé « réglé sur la mère » (`CONFIGURATION_DE_LA_MERE`). APRÈS : oui, par dépôt appliqué par la mère |
| **A** activité synchronisée | le pont fusionne champ à champ dans les deux sens | oui : le geste s'écrit à n'importe quel poste et voyage |
| **L** locale | l'enregistrement n'existe que sur le poste qui l'a créé | NON : le circuit ne traverse pas les postes |

## Tableau : circuit × les quatre questions

Légende des preuves : **T** test contre la vraie mère Dart · **C** code lu · **K** constantes de production calculées (test d'audit).

| Circuit (collection écrite par le geste) | Classe | (a) l'auteur est-il bloqué ? | (b) valider depuis un fileul ? | qui applique ? | (c) mère coupée ? | Preuve |
|---|---|---|---|---|---|---|
| **Référentiels à valider, 15 familles** (actes, analyses, valorisations, objectifs, barème AIB, modèles de message, badge, enquêtes, bornes labo, pathologies, imagerie, check-lists, répartition des charges, jeux d'import, barème ITS) | R | non | **oui, CORRIGÉ** (avant : refusé) | la mère, sous le rôle et le nom de l'auteur | badge « Transmise à la mère, en attente », élément toujours « à valider », poste libre ; reprise au retour | T `validations_fileul_depot_test`, `validations_fileul_ecran_test`, K |
| Tarifs : proposition, Oui/Non, retrait (`propositionsTarif`) | R + A | non | oui (déjà) | la mère (`ApplicateurDemandesTarif`) | dépôt en file, retour du verdict | T `tarifs_sync_test`, `tarifs_fileul_depot_test` |
| Décisions de droits (`decisionsDroits`) | R + A | non | oui (déjà) | la mère (`ServiceDroits`) | idem | T `droits_decisions_test` |
| Lots d'import (`demandesImport`, arbitrage à `imp-accueil`) | A | non (le lot est écrit chez le fileul, marqué « en attente de la mère ») | oui (déjà) | la mère (`ServiceDemandesImport`) | « jamais appliqué avant la confirmation » | T `demandes_import_sync_test` |
| Écritures comptables, brouillon → validée (`ecritures`) | A | non : le caissier encaisse la pièce suivante | **oui, vérifié** : le comptable d'un AUTRE fileul valide, la mère et l'auteur reçoivent | personne (le geste est écrit à son poste, fusion champ à champ) | le poste valide en local, la mère reçoit au retour | T `continuite_validations_audit_test` |
| Présences : validation du surveillant (`presences`) | A | non (« visible mais ne compte pas ») | oui par construction (même classe) | personne | idem | K, C |
| Avoirs, factures (`avoirs`, `factures`) | A | non | oui par construction | personne | idem | K |
| Corrections de la lecture OCR (`lecturesOcr`) | A | non | oui (ajout seul, signé) | personne | idem | T `ocr_direct_sync_test` |
| Configuration fiscale : identité légale, obligations (`identiteLegale`, `obligationsFiscales`) | R | non | **NON, reste à faire** : bouton absent sur un fileul (et le droit d'édition de CFG y est forcé à lecture seule) | — | — | K, C (`cfb_configuration_fiscale.dart`) |
| Décisions de l'AIB : arrêt du barème, base, branchement IFU, comptes (`parametresAib`) | R | **oui, pour la vente** à un acheteur dont le taux n'est pas arrêté (dépendance de nature, refus nommé) | **NON, reste à faire** (écran en lecture seule sur un fileul) | — | — | K, C |
| Réglage « encaisser le reste d'une facture qui a une ligne sans prix » (`parametres`, clé `caisse.encaisserResteLigneSansPrix`, 16/11/2026 §7) | R | non | **OUI (E3542)** : le détenteur du geste réservé `reglage_encaissement_sans_prix` le pose depuis n'importe quel poste, par DÉPÔT (`validationsDeposees`, genre `reglage_clinique`) | la mère, sous le rôle et le nom de l'auteur, avec SA matrice (geste en force, valeur, date, usage) ; rejeu sans effet | dépôt en file, « transmis à la mère, en attente » ; la version revient par la synchronisation | `reglage_depose_test`, `reglage_ligne_sans_prix_poste_test` (services du poste, PAS la vraie mère ni le banc : E3546 d) |
| Bons de besoins (`besoins`) : expression, arbitrage DAF (valider, rejeter ou compléter avec motif), tâches du comptable et du stock | ~~L~~ **A** (16/11/2026) | non ; le bon reste « soumis » chez son auteur jusqu'à la confirmation | **OUI, POSSIBLE (E2850-E2853)** : la DAF arbitre depuis N'IMPORTE QUEL poste, par DÉPÔT (`validationsDeposees`, genre `circuit_achat`) | la mère, sous le rôle et le nom de l'auteur, contrôles refaits (premier dépôt = décision, rejeu sans effet) | dépôt en file, « transmis à la mère, en attente », jamais « accordé » avant ; reprise au retour | T `circuit_achats_sync_test`, T banc `CIR1` (référence et Dart), T `circuit_synchro_test` |
| Commandes, validation DAF RG-04 (`commandes`) | ~~L~~ **A** (16/11/2026) | non ; la TRANSMISSION au fournisseur attend la validation que la mère détient (refusée sinon) | **OUI, POSSIBLE (E2853, E2854)** : même dépôt, famille `commande_validation` | la mère | idem | T idem |
| Factures fournisseurs, livraisons, PV de réception | L | non | non (même cause) | — | — | K |
| Paie : validation de la Direction, « autre que le générateur » (`bulletins`) | L | non (le bulletin se génère ; la DIFFUSION attend) | NON ; **par nature** exige une AUTRE personne | — | — | K, C |
| Dépenses (`depenses`), clôture (`clotures`) | L | non ; la clôture définitive refuse les brouillons (dépendance de nature) | non | — | — | K, C |
| Planning, propositions, congés, missions, présences (`planning`, `propositionsPlanning`, `conges`, `missions`, `presences`) | ~~L~~ **A** (17/11/2026, décision 12) | non ; la vacation posée naît « à valider » et ne compte pas (RG-11) | **OUI** : le validateur dépose depuis N'IMPORTE QUEL poste (genre `planning_rh`) | la mère, sous le rôle et le nom de l'auteur, avec SA matrice et SON planning (double affectation entre postes) | dépôt en file, « transmise à la mère, en attente » ; reprise au retour | T `planning_sync_test`, banc `PLN1` |
| Facture à une entreprise et son avoir (`facturesTiers`, `avoirsTiers`) | ~~L~~ **A** (17/11/2026, point 2) | non ; la pièce est émise par la mère seule, une demande déposée reste « transmise à la mère, en attente » | **OUI** : émission, avoir et transmission MECeF se DÉPOSENT (genre `facture_tiers`) ; un fileul n'écrit ni la pièce ni son avoir (`emission_reservee_mere`) | la mère, sous le rôle et le nom de l'auteur, avec SA matrice, SES numéros, SON relevé et SON boîtier | dépôt en file ; reprise au retour | T `facture_tiers_sync_test`, banc `FTR1` |
| Validation technique puis biologique (`demandesAnalyses`) | L | non ; le prescripteur ne voit rien avant (dépendance de nature) | non ; **par nature** engage le biologiste (intérim TSL déjà prévu) | — | — | K, C |
| Seuils de variation brutale du laboratoire (`seuilsDelta`) | L | non (« enregistré » sans effet) | non | — | — | K, C |
| Comptes rendus d'imagerie (`demandesImagerie`, `resultatsImagerie`), CPA, CR d'anesthésie | L | non | non | — | — | K |
| Documents de la GED, signature (`documents`), badges (`badges`), pièces certifiantes (`pieces`) | L | non | non ; la signature est **nominative par nature** | — | — | K, C |

Lecture de la classe L : ce n'est pas une règle de validation qui manque, ce sont les COLLECTIONS qui ne rejoignent pas le pont d'activité (le pont ne porte aujourd'hui que patients, rendez-vous, constantes, consultations, dossiers, couvertures, courriers, documents patient, présences, factures, avoirs, écritures, mouvements, lots, produits, admissions et les files de dépôt). Un besoin exprimé sur un fileul reste sur ce fileul : la DAF qui porte la mère ne le voit pas. C'est le plus gros écart à la continuité, et sa correction n'est pas une validation de plus : c'est la synchronisation de chaque collection, avec sa règle de fusion, sa numérotation et son RBAC. **À décider** (voir plus bas).

## Ce qui a été corrigé : UNE fabrique, pas un mécanisme par circuit

`packages/domaine/lib/src/validation/validation_deposee.dart` (pur) + `apps/poste/lib/sync/service_validations_deposees.dart` (magasin, journal, pont) + branchement dans `ValidationPoste` et `main.dart`.

* **Le validateur d'un fileul rattaché ne se voit plus refuser son geste : il le DÉPOSE** (collection `validationsDeposees`, famille A, une fiche par geste : famille, élément, rôle, auteur, poste, instant). Mêmes contrôles qu'un geste direct, rejoués à blanc au poste (rôle hors famille, élément inconnu, déjà validé : refus nommé avant tout dépôt).
* **La mère applique** (écoute de la collection + minuterie de sûreté, comme `ApplicateurDemandesTarif`) : `valValiderReferentiel` rejoué sous le rôle et le nom de l'AUTEUR, avec les données de la mère, SANS réécrire un contrôle. Les traces sont celles du geste direct, datées du GESTE (pas de l'application : la mère peut avoir été éteinte entre-temps). Journal (RG-12) : « déposée par X, appliquée par la mère ». Aucun humain devant la mère.
* **(c)** Tant que la mère n'a pas confirmé : badge « Transmise à la mère, en attente » (jamais « Validé »), commande « Valider » absente (pas de second dépôt), élément toujours « à valider », écran et poste libres. Sondé mère coupée puis revenue.
* **(d)** Dépôt identique pas doublé ; application rejouée = `sans_effet` nommé (aucune seconde trace) ; dépôt traité jamais rejoué. Le verdict (`appliquee`, `sans_effet`, `refusee` + code, motif, geste) revient sur la MÊME fiche par le pont ; une notification (une seule fois, `notifieLe`) le dit à l'auteur, refus compris avec son motif nommé.
* `validationsDeposees` ne part jamais vers un téléphone (RG-13), famille A à la mère Dart et au banc Node.
* Test rouge avant / vert après : sans le dépôt, le même test échoue sur `CONFIGURATION_DE_LA_MERE`.

## Ce qui n'a PAS été fait, faute de décision ou par nature

1. **Collections de classe L** (paie, labo, imagerie, GED, livraisons, factures fournisseurs…) : les faire rejoindre le pont est un chantier par collection (fusion, numérotation, RBAC, quota). **`besoins` et `commandes` ont rejoint le pont le 16/11/2026** (décision de la Direction ; voir la section suivante) ; reste, dans l'ordre proposé, `bulletins` (hors lot, consigne de la Direction).
2. **Configuration fiscale et décisions de l'AIB** (classe R) : même fabrique, un genre de dépôt de plus chacun ; l'écran fiscal doit en plus cesser d'être en lecture seule pour le seul geste de validation. Non fait pour ne pas élargir sans décision ; à noter que le barème AIB (famille `bareme_aib`) est, lui, couvert.
3. **Présence humaine par nature** : la signature de la GED (signature électronique nominative), la validation de la paie par une AUTRE personne que le générateur, la validation biologique (engage le biologiste). La continuité proposée, sans l'implémenter : suppléance déclarée (le TSL pour le biologiste est déjà prévu), délégation datée et motivée de la Direction à l'Assistant de Direction pour la paie ; à décider.
4. **Les écritures (classe A) ne sont pas « appliquées par la mère »** : le geste s'écrit à son poste et voyage ; aucun recontrôle RG-10 par la mère à l'arrivée. Décision : faut-il que la mère refuse une pièce validée déséquilibrée ?
5. **Un fileul déconnecté valide « en local »** pour la classe A (la ligne passe « validée » chez lui avant que la mère l'ait reçue). Pour la classe R le principe (c) est tenu ; pour A, l'état local n'est pas encore marqué « non confirmé par la mère ».

## Les circuits d'achat traversent les postes (Direction, 16/11/2026)

Décision de la Direction : faire traverser, dans l'ordre, `besoins` puis `commandes`. Fait, par les mêmes mécanismes que ci-dessus (aucun second mécanisme) :

* **Famille A** + règle de fusion de l'ÉTAT : rang par état, jamais de régression, deux décisions concurrentes → la plus ancienne, la perdante nommée (E2851).
* **La mère refait le contrôle de l'état** de tout bon écrit par un poste : pas de création « accordé », pas d'arbitrage écrit par un fileul (il se DÉPOSE), pas de régression, pas d'aval sans arbitrage détenu (E2852).
* **L'arbitrage et la validation DA sont des dépôts** `validationsDeposees` (genre `circuit_achat`), appliqués par la mère sous le rôle de l'auteur, contrôles refaits ; le verdict revient à l'auteur avec notification ; le poste n'est jamais bloqué (E2853).
* **Numérotation par plages** de la mère, un carnet par série : plus de `BEB` en double entre deux fileuls hors ligne (E2855).
* **Tâches du comptable et du stock** nées de l'état du bon sur chaque poste (E2856). **Jamais vers un téléphone** (E2857).

Preuve : `apps/poste/test/circuit_achats_sync_test.dart` (vraie mère Dart, deux fileuls, mère arrêtée puis relancée), `packages/domaine/test/circuit_synchro_test.dart`, banc `CIR1` (référence et Dart), treize mutations rouges (E2861). **Limite ouverte** : un fileul reçoit tous les bons (le filtre de la mère est par appareil, pas par agent) — E2857.

## Les cinq principes de continuité (Q36, Direction de Baguidi, 17/11/2026)

Relus contre ce document et contre le code (E3079). Statut : **tenu**, ou **non tenu** avec l'écart nommé.

| Principe | Statut | Preuve ou écart |
|---|---|---|
| **P1. Jamais bloquant** : une validation à faire n'arrête jamais le poste qui l'a créée | **Tenu** | Aucun état « en attente » ne bloque son auteur (audit ci-dessus). Clôture : l'avertissement avant « Démarrer la clôture » informe sans bloquer ; la mère met de côté la pièce d'un fileul datée d'un exercice clos (`exercice_clos`) ou en clôture (`exercice_en_cloture`) au lieu de la refuser au fileul, qui garde sa pièce (E3072). Écart nommé : la mère ne le dit pas encore au fileul (aucun verdict ne revient par le pont) ni ne propose de « reprendre » la pièce après réouverture. |
| **P2. Décision humaine hors de la mère** : le validateur valide depuis n'importe quel poste | **Non tenu en partie** | Tenu : référentiels (15 familles), prix, droits, lots d'import, écritures, besoins et commandes (dépôt appliqué par la mère sous le rôle de l'auteur). **Non tenu** : configuration fiscale et décisions de l'AIB (bouton absent sur un fileul) ; circuit de clôture (les quatre transitions se font sur le poste qui porte les exercices : `exercices` n'est pas synchronisée) ; collections de classe L restantes (paie, labo, imagerie, GED, livraisons, factures fournisseurs). Les présences humaines par nature (signature GED, validation de paie par une autre personne, validation biologique) restent hors principe. |
| **P3. File qui se rejoue** : un dépôt est rejouable sans effet double, le verdict revient | **Tenu pour les dépôts** | `validationsDeposees` : dépôt identique non doublé, application rejouée = `sans_effet`, verdict sur la même fiche, notification unique. **Non tenu** : (a) la mère ne recontrôle pas l'équilibre d'une écriture validée par un fileul (point 4 plus haut) ; (b) une pièce mise de côté n'a pas de commande de reprise (E3072 c). |
| **P4. Jamais d'auto-validation** | **Tenu là où il est sondé** | Clôture : l'identifiant de l'agent est comparé (« Signer n'est pas saisir »), sondé avec droit accordé (`drc_decisions_test`, `identite_test`, `m12_exercice_test`) ; paie : par nature une autre personne. **Non vérifié par ce lot** : l'arbitrage d'un bon de besoins par son propre auteur (le circuit ne compare pas l'auteur du bon et l'arbitre). |
| **P5. Alerte réglable** | **Non tenu en partie** | Réglable : échéances fiscales (`fiscal.delaiAPayerJours`, `fiscal.delaiDeclarationJours`), copie hors site (retard), validateur et rôles d'inventaire (Q3, Q4). **Non tenu** : aucun délai réglable pour signaler une validation restée trop longtemps en attente de la mère (le badge « transmise à la mère, en attente » ne s'alerte pas) ; l'alerte des opérations à envoyer avant clôture ne reçoit pas le compte réel de la file (reste à 0). Ces deux points touchent la synchronisation et sa file : laissés à l'agent qui la porte. |

**Corrigé dans ce lot sans toucher au service de synchronisation** : circuit de clôture en geste réservé (E3070), avertissement non bloquant (E3071), mise de côté à la réception de la mère poste (E3072), inventaire et validateur des achats en réglages (E3073, E3074), contrôle de rôle manquant sur la validation directe d'une commande (E3074).

## Hypothèses

* ~~Le rôle d'un dépôt est celui de la session du poste, que la mère croit~~ **Remplacé le 16/11/2026 (section AI, E3411)** : la mère VÉRIFIE le compte inscrit sur la décision (`demandeCompte`) dans SES `utilisateurs` — il existe, porte ce rôle, n'est pas archivé — pour les validations déposées, les demandes de prix et les demandes d'import ; sinon refus nommé (`COMPTE_NON_INSCRIT`, `COMPTE_INCONNU`, `COMPTE_ROLE_DIFFERENT`, `COMPTE_ARCHIVE`) rendu au fileul. Les décisions de droits (`ServiceDroits`) ne sont pas concernées par ce lot.
* « Mère injoignable » est simulé par l'arrêt des cycles du pont du fileul (le dépôt reste dans sa file) ; l'arrêt réel du service n'a pas été rejoué.
* Les boutons « Valider » des écrans de CFG autres que « Tarifs et prix » sont offerts au validateur par leur composant commun (indépendant du droit d'édition) : vérifié à l'écran sur « Tarifs et prix » seulement.

## Preuves

`packages/domaine/test/validation_deposee_test.dart` (8, moteur pur) · `apps/poste/test/validations_fileul_depot_test.dart` (vraie mère Dart + vrai moteur de fileul : dépôt, application sous le rôle, idempotence, mode « fiche », mère coupée, refus nommé qui revient, notifications) · `validations_fileul_ecran_test.dart` (écran) · `continuite_validations_audit_test.dart` (classes calculées, circuit d'activité à deux fileuls).

## Mise à jour du 16/11/2026 (Q18 à Q29)

* **Prestation distincte (Q18)** : la troisième issue de l'arbitrage de doublon de prix suit le circuit des demandes de prix : sur un fileul, le geste se DÉPOSE (`propositionsTarif`, genre `distincts`) et la mère l'applique sous le rôle de l'auteur ; le nouveau code reste « proposition à valider » (Oui ou Non par le circuit ordinaire).
* **Budgets et immobilisations (Q26)** passent de la classe L à la classe A (pont d'activité, mère Dart, banc Node), jamais vers un téléphone ; les couvertures d'assurance étaient déjà en A. Les lignes du tableau ci-dessus qui les rangeaient en L sont périmées.
* **Stock détail initial et bon de transfert (Q25)** : imports réservés à la mère (un seul stock, RG-03).

## Section AI (Direction, 16/11/2026) : alerte, compte signataire, date de signature, pastille

* **Alerte réglable (P5, la partie « validation en attente de la mère » est désormais tenue)** : réglage de clinique `validations.delaiAlerteMereHeures` (famille R `parametres`, 4 h semées). Au-delà, `AlerteDecisionsMere` écrit une notification de poste au validateur concerné (rôles de la famille au registre ; `geste:achats_valider` ; `geste:tarif_decider` ; arbitres des lots lus dans la matrice) et à l'administrateur. Aucun blocage, aucune auto-validation (E3410).
* **Compte signataire vérifié par la mère** (E3411), voir l'hypothèse corrigée plus haut.
* **Date de signature** : la validation appliquée depuis un dépôt porte `signeLe` (le geste) et `appliqueLe` (la mère) ; les verdicts des trois files aussi (E3412).
* **Pastille** « N décisions en attente de la mère » : validations, demandes de prix et demandes d'import, âge de la plus ancienne (E3413).

Preuves : `packages/domaine/test/decisions_mere_test.dart`, `apps/poste/test/decisions_mere_poste_test.dart`, et les tests de synchronisation contre la vraie mère, mis à jour pour signer par un compte nominatif (`aide_comptes.dart`).

## Le planning traverse les postes (Direction de Baguidi, 17/11/2026, décision 12)

`planning`, `propositionsPlanning`, `conges`, `missions` et `presences` passent de la classe L à la classe **A** (mère Dart, banc Node, pont du poste), jamais vers un téléphone. Même mécanisme que ci-dessus, aucun second : la validation d'une pièce du planning depuis un fileul est un **dépôt** (`validationsDeposees`, genre `planning_rh`, actions `poser`, `remplacer`, `retirer`, `trancher`, `proposition`) ; la mère l'applique sous le rôle de l'auteur en REFAISANT les contrôles du geste direct (`PlanningRhPoste`) sur SON planning, qui est celui de tous les postes. Elle refait aussi, à chaque écriture d'un poste, `refusPlanningRh` : une pièce ne naît pas validée, la validation ne s'écrit pas par un poste, une validation ne se défait pas, une vacation validée ne se réécrit pas. Identifiants préfixés par poste (`<étiquette>-PLN00005`). Écarts E4020 à E4028 de `ECARTS-MAQUETTE.md`.

Preuves : `apps/poste/test/planning_sync_test.dart` (vraie mère Dart, deux fileuls et le poste mère : pose sur l'un, proposition validée sur l'autre, mère coupée puis rétablie, double affectation refusée et archivée, aucun doublon), `packages/domaine/test/planning_synchro_test.dart` (moteur pur), banc `PLN1` (Node et Dart).

## La facture à une entreprise traverse les postes (Direction de Baguidi, 17/11/2026, point 2)

`facturesTiers` et `avoirsTiers` passent de la classe L à la classe **A** (mère Dart, banc Node, pont du poste), jamais vers un téléphone. Même mécanisme que ci-dessus, aucun second : l'ÉMISSION reste à la mère (numérotation et boîtier fiscal) ; un fileul DÉPOSE une demande (`validationsDeposees`, genre `facture_tiers`, actions `emettre`, `avoir`, `transmettre`) et la mère l'applique sous le rôle et le nom de son auteur, mêmes fonctions que le geste direct. Le verdict (`appliquee`, `sans_effet`, `refusee` avec code, motif et geste) revient au fileul sur la même fiche. Voir E4200 à E4212 de `ECARTS-MAQUETTE.md`.

Preuves : `apps/poste/test/facture_tiers_sync_test.dart` (vraie mère Dart, deux fileuls et le poste mère : émission demandée, même ligne refusée, rôle sans le geste refusé, avoir plafonné, transmission en attente nommée, mère coupée, rejeu), `packages/domaine/test/facture_tiers_suite_test.dart`, banc `FTR1` (Node et Dart).

## La validation d'une fiche d'aide et l'import de la liasse depuis un fileul (Direction de Baguidi, 18/11/2026, points 3 et 4)

Deux gestes qui n'existaient que sur la mère passent par le même circuit (`validationsDeposees`, famille A), deux genres de plus, aucun mécanisme nouveau :

* **`fiche_aide_valider`** — le fileul DÉPOSE la demande de validation d'une fiche d'aide ; le validateur est l'agent connecté, avec son compte (`demandeCompte`, vérifié par la mère avant tout rejeu). La mère l'applique sous le rôle et le nom du déposant en refaisant les contrôles de `validerFicheAide` : geste réservé `fiches_aide_valider` relu dans SA matrice, auteur de la fiche (celle que la mère connaît) différent du validateur, check-liste du bloc = geste du professionnel `valider_ref_bloc` + nom + date. Un contrôle de plus propre au dépôt : la demande porte l'empreinte du contenu que le validateur a relu (`contenuVu`) ; une fiche réécrite entre-temps est refusée `FICHE_MODIFIEE` (on valide ce qu'on a lu). Une fiche déjà validée rend `sans_effet` ; la fiche reste « proposée » tant que la mère n'a pas confirmé.
* **`liasse_importer`** — le fileul DÉPOSE la demande d'import ; le contenu est le document que SON poste a validé avec le validateur strict. La mère rejoue la validation stricte sur le contenu reçu, applique `preparerImportFiscal` sous le geste `documents_fiscaux_importer` du compte signataire, à la date du geste du déposant. La taille est bornée par le réglage `comptabilite.tailleMaxDepotFiscalKo` (dépôt ET application). La collection `documentsFiscaux` reste de **famille R** (la mère seule l'écrit : un fileul qui l'écrirait est refusé `droit_refuse`), ne va jamais vers un téléphone ; la version écrite par la mère revient aux postes par la configuration. Après verdict, la mère VIDE le contenu de la demande (le document n'est pas dupliqué dans le registre des demandes).

Dans les deux cas : verdict nommé (`appliquee`, `sans_effet`, `refusee` avec code, motif et geste) écrit sur la même fiche de dépôt et notification de l'auteur ; mère injoignable = demande en attente, rien ne se perd ; au-delà du délai réglé (`validations.delaiAlerteMereHeures`, 4 heures semées) une alerte part vers ceux qui détiennent le geste (lus dans la matrice) et l'administrateur. Aucun geste réservé nouveau. Voir E5050 à E5059 de `ECARTS-MAQUETTE.md`.

Preuves : `apps/poste/test/fiche_aide_liasse_sync_test.dart` (vraie mère Dart, deux fileuls et le poste mère : refus à blanc, mère coupée, rejeu sous le rôle du compte, retrait du geste, contenu falsifié, compte inconnu, collection en R), `packages/domaine/test/fiches_aide_synchro_test.dart`, `packages/domaine/test/documents_fiscaux_synchro_test.dart`, banc `FLI1` (Node et Dart).

