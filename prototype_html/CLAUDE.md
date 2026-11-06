# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

**SIGH-CBG** — Système Intégré de Gestion Hospitalière de la **CLINIQUE BAGUIDI « L'AS DE CŒUR »**
(Quartier Zongo II, 02 BP 105, Parakou, République du Bénin — IFU 3201001996110 du 26/11/2010 —
cliniquebaguidi@yahoo.fr — 95 74 69 56 / 95 95 99 14 / 97 09 34 99). Sous-titre officiel :
« CENTRE DE MÉDECINE DU TRAVAIL – MÉDECINE GÉNÉRALE ». Devise : « Votre bien-être est notre raison
d'être. » Sigle **validé par la Direction le 02/09/2026 : SIGH-CBG**.

Le prototype est la **dérivation** du prototype SIGH-CNT (CLINIQUE NASSIERA TOO, Natitingou), réalisée
le 02/09/2026 sur décision écrite de la Direction (`../Instructions.txt`, LA source prioritaire ;
`../PROMPT-DERIVATION.md`, la feuille de route). Rien n'a été redéveloppé : nettoyage des seeders,
désactivation des modules non exploités, charte graphique BAGUIDI. **Forme juridique, n° d'autorisation
d'ouverture, grille salariale, IFU des agents et seuils d'alerte N'ONT PAS ÉTÉ FOURNIS** : les champs
restent vides et les écrans le disent — aucune donnée officielle ne s'invente. Le **RCCM RB/PKO/17 A
4240 du 19/03/2009** a été fourni le 07/09/2026 et figure sur les pièces.

## Périmètre (décision de la Direction du 02/09/2026)

**ACTIFS** : M6 stocks et inventaire pharmacie · M7 achats et expressions de besoins — **y compris les
demandes de besoins du laboratoire et des services** (ce sont des besoins M7, pas du labo clinique) ·
M10 RH (fiches) · M11 paie & primes · M12 comptabilité SYSCOHADA · M13 administration · M14 sécurité ·
PIL pilotage · DASH tableaux de bord (dont le croisé dynamique) · CFG · GED · RAP.

**DÉSACTIVÉS via `modulesActifs`** (fiches `MOD-CBG-*` semées dans `store.seed()`, JAMAIS un retrait du
manifeste `nav.js`) : M1, M2, M3, M4, M5 (laboratoire clinique), M8 (caisse), M9 (assurances), MECEF.
Écrans fermés au canal des écrans : évaluations/sanctions NS 131 (`MOD-CBG-NS131`, barème seedé VIDÉ,
bascule `baremeModifiable` fermée, la paie calcule SANS rubrique de sanction), statistiques cliniques
de PIL (`MOD-CBG-STATS`) et **la dispensation au patient** — `m6-pharmacie-interne`,
`m6-pharmacie-externe` et le registre `m6-dispensation` (`MOD-CBG-OFFICINE`, 03-04/09/2026 : toute
délivrance naît d'une ordonnance réglée en caisse, deux circuits fermés — sans amont, le registre
n'enregistre rien ; **le stock reste entier**, module M6 ouvert). Cette liste ne se rediscute que sur
une nouvelle décision écrite.

Doctrine de la fermeture (héritée, vérifiée par la suite de tests) : une désactivation retire du
méga-menu, de la recherche et des adresses, POUR TOUS les rôles admin compris, sans rien supprimer ;
la réactivation (cfg-modules) rend tout en l'état ; CFG + DASH sont le noyau non désactivable ;
fermer un module ne casse JAMAIS un module actif — un KPI qui lirait une collection clinique affiche
un zéro honnête ou se masque ; un tableau de bord dont le poste n'existe pas chez BAGUIDI **l'annonce**
(bandeau générique posé UNE fois dans `K.dash`, pour tout rôle archivé porteur du tableau).

**Toute surface qui présente des écrans doit passer par `can()` / `N.tree()`, jamais par `N.NAV` brut.**
Quatre l'avaient oublié — cartes de hub, accès rapides, audit RBAC, puis (03/09/2026) l'**écran
d'aide**, qui annonçait 23 modules et 259 écrans, modules fermés compris, avec des cartes menant au
403. L'aide reste une DOCUMENTATION — elle liste tout — mais chaque module fermé y porte la mention
« Fermé », son motif, et n'est pas cliquable ; tout est dérivé de l'état courant, si bien qu'un module
rouvert y **reparaît ouvert sans qu'une ligne change** (sondé : fermé → rouvert → refermé). Même
règle pour les RÔLES : le sélecteur « Profil de connexion » du modal de la barre supérieure ne
propose que les rôles non archivés — offrir un rôle archivé, c'est offrir une porte que le contrôle
d'accès referme aussitôt en journalisant la tentative.

## Les chaînes transactionnelles de référence (critère de réussite)

Chez CNT c'était patient→consultation→facture ; chez BAGUIDI ce sont :

1. **expression de besoin (service ou laboratoire) → validation Direction (RG-04, quantité accordée ≠
   demandée) → bon de commande → réception (mouvement justifié RG-03, CUMP recalculé, FEFO) → facture
   fournisseur rapprochée → écriture comptable équilibrée en brouillon (RG-10)** ;
2. **fiche RH → planning (régimes) → bulletin de paie SANS sanction ni prime → validation par la
   Direction (signer n'est pas saisir)**.

`build/test-fonctionnel.js` les sonde de bout en bout (16 scénarios, 129 vérifications) avec les sondes
« module fermé proprement + modules actifs intacts ». L'ancienne suite CNT (54 scénarios cliniques)
vit dans l'historique git — rouvrir un module clinique permettra d'y reprendre les parcours.

## Comptes de test (seed exact — Instructions.txt, ne pas en inventer d'autres)

| Nom | Identifiant | Rôle |
|---|---|---|
| GBAGUIDI Rafiou | m-001@baguidi-clinique.bj | Direction (Directeur Général) |
| SANOUSSI Adamon | m-002@baguidi-clinique.bj | Comptable |
| MABOUDOU Nawal | m-003@baguidi-clinique.bj | RH |
| IDOHOU Abraham | m-004@baguidi-clinique.bj | Médecin |
| AKONDE Octave | m-005@baguidi-clinique.bj | Infirmier |
| SOKOU Peace | m-006@baguidi-clinique.bj | Direction |
| ZIME Nadège | m-007@baguidi-clinique.bj | Comptable |
| TOUNGOUH A. Zoulkifouli | m-008@baguidi-clinique.bj | RH |

Plus `admin@baguidi-clinique.bj` (administrateur système — son poste EST l'accès complet, seul rôle
sans fiche `rbac`). Le personnel seedé (`genPersonnel`) est EXACTEMENT ces huit agents, matricule N =
m-00N ; les **salaires sont des valeurs d'attente** marquées `salaireProvisoire`/`aValider`.

## RBAC

- **Rôles actifs** : admin, direction, comptable, **rh (DÉSARCHIVÉ le 02/09 — deux titulaires ; chez
  CNT il était archivé au profit de la DAF)**, medecin, infirmier. Chacun a sa fiche `rbac` — un rôle
  sans fiche a TOUS les droits, le trou corrigé chez CNT en vague 53.
- **Rôles archivés** (RG-14, `motifArchivage`, jamais supprimés, réactivables sur décision écrite) :
  dm, da, pharmacien, laborantin, caissier, reception, stock, agentadmin, ambulancier, aide_soignant,
  echographiste, surveillant, assistant_comptable, chirurgien, anesthesiste, aide_comptable,
  biomedical. Leurs tableaux de bord annoncent le poste sans titulaire ; leurs sessions sont refusées.
- **La Direction porte les validations** : paie (`m11-validation`) et RG-04 (`m7-besoins`,
  `m7-commandes`) par surcharges d'écran — signer n'est pas saisir ni tenir le stock.
- **Le comptable tient le stock et les achats** (M6/M7 en écriture, annulation non) : aucun
  gestionnaire de stock n'est nommé chez BAGUIDI et un rôle de plus ne s'ajoute que sur décision
  écrite — la séparation des tâches passe par la signature de la Direction. Documenté sur la fiche
  RBAC22, à confirmer.
- **Médecin et infirmier existent** (comptes actifs) mais leurs modules cliniques sont fermés : ils
  gardent leur tableau de bord (qui annonce le périmètre) et l'expression de besoins (`m7-besoins`
  accordé nommément — une surcharge ACCORDE autant qu'elle restreint).
- Rappels hérités : un écran l'emporte sur son module ; DASH et PIL ne se déclarent JAMAIS au niveau
  du module dans une fiche ; une fiche ne mentionne que les modules que le manifeste ouvre au rôle.
- Attendu : `npm run audit-rbac` → **0 promesse, 0 lecture non dite** ; `npm run inventaire-rbac`
  régénéré (`../newdocs/INVENTAIRE-RBAC.md`) et relu à chaque lot — un écran ajouté à un module
  hérite de ses droits et rouvre en silence ce que les surcharges fermaient.

## Seeders — ce qui est BAGUIDI, ce qui est hérité, ce qui est vide

- **BAGUIDI (semé)** : les 8 agents et leurs comptes, plannings/présences/prêts/événements régénérés
  sur eux, fermetures `MOD-CBG-*`, gestes de poste des modules actifs (écritures validées par SANOUSSI
  Adamon, bons accordés par SOKOU Peace…).
- **HÉRITÉ DE CNT, GARDÉ en jeu de démonstration (décision écrite « ON GARDE »), à remplacer par les
  données BAGUIDI dès réception** : inventaire SAGE (184 articles), catalogue des médicaments, plan
  comptable SYSCOHADA (93 comptes), compte de résultat 2025 (baseline des dashboards), calendrier
  fiscal béninois, fournisseurs, périodicités, familles de pièces, grille des primes NS 132 (moteur
  gardé, **grille marquée `aValider`** — la référence NS 132/07/DM/DA/CNT/2026 TRACE la provenance,
  c'est le faux positif documenté du grep « CNT »). L'écran `adm-validations` liste tout cela sous
  « À compléter par la Direction ».
- **VIDE (purgé)** : patients, consultations, admissions, soins, relevés, factures de soins, analyses,
  maternité, imagerie, pièces certifiantes, évaluations NS 131, barème NS 131, fiches de poste CNT.
  Les GÉNÉRATEURS restent dans `store.js` et `data-seed.js` (appels débranchés dans `peupler()`) :
  rouvrir un module clinique = les rebrancher, rien n'a été supprimé.
- Règle de placement héritée : un référentiel lu par PLUSIEURS modules s'amorce dans `store.seed()` ;
  un référentiel lu par UN seul écran s'amorce par cet écran (les collections `besoins`/`commandes`
  M7 s'amorcent à l'ouverture de l'écran — `adm-validations` annonce « file non amorcée » plutôt
  qu'un 0 faux). Le piège s'est repayé le 03/09/2026 : `utilisateurs` était amorcée par le seul écran
  M14 alors que le modal de profil de la barre supérieure la lit sur TOUTES les pages — elle est
  passée au socle (`genUtilisateurs`), et M14 ne fait plus que la lire.

## Commandes (depuis `prototype_html/`)

```bash
npm install        # Tailwind CLI + Puppeteer
npm run build      # gen-pages → gen-safelist → Tailwind (safelist AVANT la CSS — piège n°1)
npm run lint       # node --check sur toutes les sources JS
npm run check      # ouvre les 283 pages dans Chrome : erreurs JS, liens, ressources
npm run test       # 16 scénarios BAGUIDI (129 vérifications) — chaînes 1 et 2, fermetures, RBAC, charte
npm run audit-rbac # chaque écran sous chaque profil actif : commandes offertes vs droits réels
npm run inventaire-rbac # ce que chaque rôle voit RÉELLEMENT → ../newdocs/INVENTAIRE-RBAC.md
npm run verify     # lint + build + check + test
node build/check.js --pages=m6-,m7-   # contrôler un sous-ensemble
node build/shot.js <page>.html 1600 sortie.png   # capture d'écran
node build/_pdf2png.js "../fichier.pdf" build/pdf-pages 2   # rendre un PDF scanné en images
```

### Les trois pièges du build (hérités, toujours vrais)

1. **Régénérer la safelist avant de compiler la CSS.** L'interface est construite en JavaScript ;
   Tailwind ne voit pas ces classes. `build/gen-safelist.js` relit les sources et écrit
   `build/safelist.html`. Oublier l'étape produit une CSS incomplète et une mise en page cassée.
2. **`gen-safelist` retire les commentaires avant d'analyser** — une apostrophe française isolée dans
   un commentaire désynchronise le balayage et fait disparaître silencieusement les classes suivantes.
3. **Ajouter un écran = modifier `assets/js/nav.js` puis `npm run pages`.** Le manifeste est la source
   unique des liens ; `index.html` (écrit à la main) doit porter chaque script de la liste `SCRIPTS`
   de `gen-pages.js` — une garde de build refuse tout désalignement.

## Règles à ne jamais contourner

- **Aucune donnée officielle ne s'invente** : RCCM, autorisation, forme juridique, tarifs, salaires,
  primes, seuils, numéros d'urgence. Toute valeur manquante reste vide et l'écran le dit
  (« à compléter par la Direction »).
- **Les marquages `aValider` se posent librement et ne se retirent que sur décision écrite.**
- **Fermer un écran = `modulesActifs`** (écrans ET modules) — jamais un retrait du manifeste : le
  manifeste est la source unique des pages ET des liens, retirer l'entrée supprime la page et casse
  les liens.
- Toute modification de forme des données **incrémente `_version`** dans `store.js` (sinon les postes
  gardent l'ancien jeu en localStorage) et met à jour `LIBELLES` (corbeille RG-14).
- Édition de fichiers : **jamais de scripts Python (CRLF) ni de `node -e`** (backticks et échappements
  mangés) — scripts Node écrits via l'outil d'édition. `String.replace` sans regex frappe la PREMIÈRE
  occurrence du fichier : tout remplacement scripté part d'une ancre UNIQUE.
- Un rôle/référentiel s'**archive** (RG-14), ne se supprime jamais ; un archivage va toujours avec son
  transfert.
- Le code dossier et les numérotations de pièces lisent **`C.BRAND.sigle`** (`CBG/...`,
  `<SIGLE> n°/n°/CBG/<direction>/<année>`) — la règle vit à UN endroit. Clés localStorage :
  préfixe `sigh-cbg:`.
- RG-01→RG-14 du CDCT restent en vigueur sur les modules actifs (stock jamais négatif et justificatif
  RG-03, validation Direction RG-04, FEFO RG-05, RG-09/RG-10, journalisation RG-12, RG-13, RG-14).
- Typographie française des montants : `C.money` compose avec espace fine insécable (U+202F) et espace
  insécable avant FCFA — une sonde compare les CHIFFRES seuls, espaces neutralisées.

## Charte graphique (design system — safelist !)

- **Rouge Cœur `coeur-500` #D32F2F** — actions principales (`.btn-primary` plein), accents, slogan.
- **Bleu Santé `sante-600`/`navy-*` #1565C0** — titres, badges, onglets, liens : la palette `navy` du
  design system est REMAPPÉE sur le Bleu Santé (50–900) et le **Noir Anthracite #212121 (950 — topbar,
  ruban, barres sombres)** ; les classes n'ont pas changé, la palette si (`tailwind.config.js`).
- **Nuance documentée action/erreur** : le rouge d'ACTION est le Rouge Cœur profond en bouton plein ;
  le rouge d'ERREUR reste le rouge vif `danger-*` (badges, alertes) et `.btn-danger` est un CONTOUR
  rouge sur fond blanc. La sémantique vert/orange/rouge d'état ne change pas.
- **Typographie vendorée** (fonts/, aucune requête réseau) : Inter (courant), **Montserrat** (titres —
  h1-h3, `.card-title`, `.kpi-value`, `font-heading`), **Dancing Script EXCLUSIVEMENT pour le slogan**
  (`.font-slogan`, jamais ailleurs).
- **En-tête imprimé à 3 zones** (`print.js`, structure en tableau) : gauche = logo circulaire ~2,4 cm
  + slogan cursive rouge dessous ; centre = dénomination rouge + sous-titre anthracite ; droite =
  adresse, téléphones, IFU daté, e-mail, RCCM (« à compléter » si absent). Sous l'en-tête, **double
  ligne fine rouge puis bleue** — reprise sous la topbar de l'application et sur les écrans d'accès.
- Logo officiel vendoré : `assets/img/logo.png` (topbar, connexion, verrou, états, favicon).
- Écrans d'accès (gabarit `shell()` d'auth.js, maquettes `../design/` du 03/09/2026) : page CLAIRE à
  grandes formes bleues adoucies et PANNEAU FLOTTANT arrondi — moitié gauche en dégradé Bleu Santé
  portant tout l'en-tête BAGUIDI (dénomination, sous-titre, Parakou, périmètre, spécialités, slogan
  cursive, IFU), moitié droite en carte blanche du formulaire, double ligne rouge/bleue au sommet.
  Le VERROU de session garde SON décor distinct : plein écran anthracite, carte centrée au logo.

## Architecture (héritée — l'essentiel)

Chaque page HTML est un gabarit de dix lignes appelant `SIGH.mount('<id>')`. Coquille, méga-menu en
ruban filtré par rôle, fil d'Ariane et liens viennent de `assets/js/nav.js` (manifeste unique). Ordre
de chargement : `core` (BRAND, formats) → `data*` (semences) → `store` (magasin, `_version`, RG-14) →
`parcours` → `ui` → `charts`/`print` → `nav` → `app` → `modules/_kit.js` → module de l'écran — **chaque
page ne charge que le module de son écran**, d'où la règle de placement des référentiels. `kit.crud()`
fabrique les écrans de gestion ; `K.commande`/`K.commandeIcone` déclarent les écritures (l'audit RBAC
mesure promesses et lectures non dites) ; les totaux imprimés sont des `somme` de colonne, calculés
depuis les lignes réellement imprimées (« un total faux est pire qu'un total absent » — on ne totalise
que ce qui a un sens). `U.confirm` garde sa promesse ; un `U.combo()` n'est pas un `<select>` ;
deux clés `actions` dans un même `U.dataTable` : la seconde écrase la première en silence.

**Schéma des données** : `_version` courante **64**. Journal : 53 identité BAGUIDI (BRAND, sigh-cbg:,
sigle CBG) · 54 périmètre (MOD-CBG-*, NS 131 vidé) · 55 seeders (8 agents, purge clinique, NS 132
aValider) · 56 RBAC (rh désarchivé, 15 rôles archivés, RG-04 Direction, stats PIL fermées) · 57
officines fermées (MOD-CBG-OFFICINE) et `utilisateurs` amorcée AU SOCLE · 58 registre des
délivrances fermé avec les officines · **59 plan comptable SYSCOHADA RÉVISÉ** (1 332 comptes,
codes à quatre chiffres) · **60 les six secteurs** (groupes et centres alignés) et **l'AIB**
(`retenuesAIB`, `ifuStatut` par fournisseur) · **61 l'historique des prix** (`historiquePrix`, prix
du lot, coefficient de vente) · **62 pas de primes** (grille vide, écran fermé) · **63 le barème
d'AIB administrable** · **64 l'IFU et le régime de rémunération sur chaque fiche** (personnel et
prestataires), et l'AIB portée au bulletin. Les versions ≤ 52 sont l'historique CNT (voir
l'historique git du fichier).

**PIÈGE — la version se déclare à UN SEUL endroit.** `load()` comparait la version enregistrée à un
littéral distinct de celui de la semence. Incrémenter l'un sans l'autre faisait rejeter le magasin
**à chaque chargement de page** : rien ne plantait, le prototype ré-amorçait en silence et tout ce
qu'on venait de saisir disparaissait à la navigation suivante (deux chaînes de tests sont tombées
dessus le 07/09/2026). La constante `VERSION` en tête de `store.js` sert maintenant aux deux.

## Comptabilité et fiscalité (06-07/09/2026)

- **Plan comptable** : le SYSCOHADA **révisé** au complet (`data-plan-comptable.js`, engendré du CSV
  officiel par `build/gen-plan-comptable.js`). Codes à **quatre chiffres**, ceux que le service
  comptable de BAGUIDI emploie déjà (4011, 5711, 2458). Un compte est **imputable** s'il n'a pas
  d'enfant ; les niveaux supérieurs totalisent. **`D.COMPTES_SIGH` nomme les comptes des schémas
  d'écriture** — une écriture désigne son compte par son nom, le rattachement se corrige à un seul
  endroit. Le plan de la clinique d'origine est retiré ; `data-compta.js` ne garde que la baseline.
- **Les six secteurs** (`D.GROUPES_PRESTATION`, `D.CENTRES_COUT`, `D.secteurPrestation`) :
  Laboratoire · Pharmacie · Consultation · Échographie · Maternité · Hospitalisation et soins, plus
  **Direction** côté centres de coûts (charges transverses, non ventilées). Les mêmes partout —
  recettes, bénéfice brut, rapprochement, axes du croisé. Aucun ne manque, et un centre sans charge
  reste au tableau à zéro.
- **AIB** (`D.PARAM_AIB`, `D.tauxAIB`, `D.baremeAIB`, écran `m12-aib`) : ce que la clinique
  **retient** est une dette (4478), ce qu'elle **subit** une créance (4492), imputée sur l'impôt
  (891). **Le BARÈME est une DONNÉE administrable** (collection `baremeAIB`) : une règle *arrêtée*
  s'applique aussitôt, une règle en attente ne s'applique pas. Seule celle des **5 % est arrêtée**
  (IFU désactivé ou absent, effet 07/09/2026) ; les taux de **1 % et 3 %** relevés dans les pièces
  portent leur condition **proposée** et attendent que la Direction les arrête à l'écran. Quand
  deux règles visent le même tiers, le moteur **nomme les règles** au lieu de choisir. Le **statut
  de l'IFU se vérifie, se date et se signe** ; il n'est semé pour personne.
- **L'IFU vit sur la FICHE, pas sur la collection** : `personnel` et `prestataires` portent `ifu`,
  `ifuStatut`, `ifuVerifieLe`/`ifuVerifiePar` et `regimeRemuneration`. **C'est le régime qui décide
  de l'AIB** — un salaire supporte l'ITS, des honoraires facturés supportent l'acompte
  (`D.aibTiers`, lu par la paie, les prestataires et la comptabilité). Le bulletin porte la ligne
  **dans les deux cas**, à zéro et motivée pour un salarié : une pièce doit dire de quoi l'agent est
  redevable, pas seulement ce qu'il paie. Aucun IFU n'est semé pour les huit agents.
- **Pas de primes** (07/09/2026) : `grillePrimes` VIDE, écran `m10-primes` fermé
  (`MOD-CBG-PRIMES`), bulletins calculés sans prime. **Une grille vide vaut ZÉRO** —
  `D.NS132.montant()` ne retombe plus sur la note de la clinique d'origine, qui ferait verser des
  primes que personne n'a décidées. Le moteur (grille datée, versionnement) reste entier : rouvrir
  demande une décision écrite et la saisie d'une grille, jamais du code.
- **Historique des prix** (`historiquePrix`, `S.historiquePrix`) : la trace s'écrit dans le SEUL
  entonnoir `update()` du magasin, est en lecture seule, fige le libellé, et n'est jamais une
  source de valorisation — **un mouvement porte ses valeurs, copiées à l'enregistrement**. Trois
  méthodes de sortie (prix de vente, CUMP, **prix du lot**), un lot sans prix propre retombe sur le
  CUMP et le dit. `S.prixManquant()` refuse la sortie d'un article sans prix en nommant la fiche.
  Le **coefficient de vente** existe et vaut 1,00 (RG-02).

## Cible finale

CDCT §8.5 : application desktop .NET (WPF/WinUI 3) + PostgreSQL en client-serveur LAN — Web/API et
cloud écartés. Le prototype est la spécification exécutable ; la réalisation reste à faire.

## À compléter par la Direction (récapitulatif vivant — `adm-validations` fait foi à l'écran)

RCCM · forme juridique · n° d'autorisation d'ouverture · grille des primes BAGUIDI (NS 132 héritée
`aValider`) · grille salariale (salaires d'attente marqués) · inventaire et catalogue réels BAGUIDI
(SAGE hérité gardé en démonstration) · fournisseurs réels · baseline comptable BAGUIDI (2025 hérité) ·
seuils d'alerte de stock référence par référence · confirmation écrite de la tenue du stock par le
comptable (ou nomination d'un gestionnaire de stock) · fiches de poste (toutes « à rédiger »).
