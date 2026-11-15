# Continuité de service des validations (Direction de Baguidi, 15/11/2026)

> « Une validation à faire ne doit JAMAIS empêcher le fileul de travailler. Une validation créée par un fileul et qui devrait être validée par la mère : le poste de la mère n'est pas fait pour valider (c'est un poste qui porte la clinique, pas un poste de validation) ; il faut une CONTINUITÉ DES SERVICES. »

Quatre exigences : (a) aucun état « en attente de validation » ne bloque le poste qui l'a créé ; (b) le validateur (celui que la matrice autorise) valide DEPUIS N'IMPORTE QUEL POSTE, la mère appliquant mécaniquement sous le rôle de l'auteur, tous les contrôles refaits ; (c) mère injoignable : l'état dit « en attente de la mère », jamais « validé » avant confirmation ; (d) la validation déposée est rejouable sans effet double, le verdict revient au fileul.

## Ce que l'audit a trouvé (par lecture du code, par calcul sur les constantes de la production, par tests contre la vraie mère Dart)

**Aucun état « en attente de validation » ne bloque son auteur** : les gardes trouvées sont des dépendances de nature (une commande ne part pas chez le fournisseur sans la DAF, RG-04 ; la clôture refuse les brouillons ; un résultat non validé n'est pas rendu au prescripteur ; un taux d'AIB non arrêté refuse la vente à l'acheteur concerné). L'auteur saisit, facture, encaisse, délivre pendant ce temps (sondé pour les écritures).

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
| Bons de besoins (`besoins`) : expression, arbitrage DAF (valider, rejeter ou compléter avec motif), tâches du comptable et du stock | ~~L~~ **A** (16/11/2026) | non ; le bon reste « soumis » chez son auteur jusqu'à la confirmation | **OUI, POSSIBLE (E2850-E2853)** : la DAF arbitre depuis N'IMPORTE QUEL poste, par DÉPÔT (`validationsDeposees`, genre `circuit_achat`) | la mère, sous le rôle et le nom de l'auteur, contrôles refaits (premier dépôt = décision, rejeu sans effet) | dépôt en file, « transmis à la mère, en attente », jamais « accordé » avant ; reprise au retour | T `circuit_achats_sync_test`, T banc `CIR1` (référence et Dart), T `circuit_synchro_test` |
| Commandes, validation DAF RG-04 (`commandes`) | ~~L~~ **A** (16/11/2026) | non ; la TRANSMISSION au fournisseur attend la validation que la mère détient (refusée sinon) | **OUI, POSSIBLE (E2853, E2854)** : même dépôt, famille `commande_validation` | la mère | idem | T idem |
| Factures fournisseurs, livraisons, PV de réception | L | non | non (même cause) | — | — | K |
| Paie : validation de la Direction, « autre que le générateur » (`bulletins`) | L | non (le bulletin se génère ; la DIFFUSION attend) | NON ; **par nature** exige une AUTRE personne | — | — | K, C |
| Dépenses (`depenses`), clôture (`clotures`) | L | non ; la clôture refuse les brouillons (dépendance de nature) | non | — | — | K, C |
| Planning, propositions (`planning`) | L | non | non | — | — | K |
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

## Hypothèses

* Le rôle d'un dépôt est celui de la session du poste, que la mère croit (même confiance que les décisions de droits et les demandes de prix).
* « Mère injoignable » est simulé par l'arrêt des cycles du pont du fileul (le dépôt reste dans sa file) ; l'arrêt réel du service n'a pas été rejoué.
* Les boutons « Valider » des écrans de CFG autres que « Tarifs et prix » sont offerts au validateur par leur composant commun (indépendant du droit d'édition) : vérifié à l'écran sur « Tarifs et prix » seulement.

## Preuves

`packages/domaine/test/validation_deposee_test.dart` (8, moteur pur) · `apps/poste/test/validations_fileul_depot_test.dart` (vraie mère Dart + vrai moteur de fileul : dépôt, application sous le rôle, idempotence, mode « fiche », mère coupée, refus nommé qui revient, notifications) · `validations_fileul_ecran_test.dart` (écran) · `continuite_validations_audit_test.dart` (classes calculées, circuit d'activité à deux fileuls).
