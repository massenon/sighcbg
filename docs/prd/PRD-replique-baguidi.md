# PRD : SIGH-CB, réplique du logiciel SIGH-CNT pour la Clinique Baguidi « L'As de Cœur »

| | |
|---|---|
| **Statut** | Brouillon v2, à valider par la Direction de la Clinique Baguidi |
| **Date** | 06/11/2026 (v2 : réponses aux questions Q1, Q2 et Q5 intégrées le même jour) |
| **Dépôt cible** | `massenon/sighcbg` (vide à ce jour) |
| **Base** | `massenon/sighcnt`, branche `claude/sighcnt-monorepo-offline-first-i0v3v9`, commit `2bb35df` (06/11/2026) |
| **Nature du chantier** | Restructuration et changement d'identité. **Pas de réécriture** : l'architecture et le code restent ceux de SIGH-CNT |

---

## 1. Problème

La Clinique Baguidi « L'As de Cœur » (Parakou) est un centre de médecine du travail et de médecine générale. Elle a besoin d'un système de gestion pour sa pharmacie et ses stocks, ses achats et expressions de besoins, ses RH, sa paie, sa comptabilité SYSCOHADA et son pilotage. Le logiciel SIGH-CNT, construit pour la Clinique Nassiera Too (Natitingou), couvre déjà ces fonctions, avec son architecture hors ligne d'abord (poste Flutter fileul/mère, relais web Laravel, mobile).

Repartir de zéro coûterait des mois et ferait perdre les règles de gestion déjà éprouvées (RG-01 à RG-14, 74 parcours, audit RBAC). Livrer SIGH-CNT tel quel serait une faute : chaque pièce porterait l'identité légale d'une autre clinique (IFU, RCCM, logo), et la moitié des modules (soins, laboratoire, caisse) relèvent d'activités que Baguidi n'exerce pas, ou pas dans ce logiciel.

## 2. Objectifs

1. **Une identité, une seule.** Toute pièce imprimée, tout écran, toute page du relais et l'application mobile portent l'identité de la Clinique Baguidi. **Aucune occurrence** de l'identité Nassiera Too dans ce qui est livré, vérifiée par un contrôle automatique.
2. **Le périmètre Baguidi, et lui seul.** Les modules hors périmètre sont fermés pour tous les rôles : absents du ruban, de la recherche, des hubs et des adresses. Facturation & Caisse est réduit à une **caisse minimale** (opérations sans dossier patient, ventes de pharmacie, état journalier). Trois modules (MECeF, Primes NS 132, Évaluations NS 131) arrivent **ouverts** et se ferment depuis *Paramètres système*.
3. **Toute l'activité de la clinique est suivie en comptabilité, sans double saisie patient.** La clinique garde son logiciel de caisse rattaché aux patients. Le comptable **reporte** chaque jour dans SIGH-CB les ventes de ce logiciel par nature d'activité (actes, consultations, certificats, hospitalisations, analyses, imagerie, pharmacie…), ainsi que les dépenses et les sorties. Chaque report produit son écriture équilibrée (RG-10) et alimente les statistiques. Cible : 100 % des journées de caisse reportées, écart nul entre le total reporté et le total du logiciel de caisse.
4. **Les modules conservés restent complets.** Stock, achats, RH, paie, comptabilité, administration, sécurité, configuration, GED, rapports et pilotage gardent leur CRUD entier (créer, consulter, modifier, archiver, restaurer, imprimer). Leurs bancs d'essai restent verts.
5. **La charte graphique Baguidi.** Couleurs, logo et écran de connexion suivent le design system de Baguidi, sans toucher à la géométrie des écrans.
6. **Le code reste synchronisable avec SIGH-CNT.** Les différences entre les deux dépôts tiennent dans des fichiers d'identité, de thème, de données et de configuration identifiés. Un correctif de SIGH-CNT se reporte sans conflit sur le reste du code.

## 3. Hors objectifs

| Hors objectif | Raison |
|---|---|
| Réécrire ou réarchitecturer le code | Demande explicite. L'architecture hors ligne (ADR-0002, ADR-0005) et le protocole de synchronisation restent tels quels |
| Supprimer le code des modules fermés | Une fermeture est **réversible** (doctrine `modulesActifs` : rien n'est supprimé, la réouverture rend tout en l'état). Supprimer le code romprait aussi la synchronisation avec SIGH-CNT |
| Renommer les identifiants techniques (`sigh_poste`, codes M1 à M14, identifiants de rôles, noms de collections) | Doctrine « laborantin » : on ne renomme pas un identifiant technique. Seul ce qui est visible ou légal change |
| Remplacer le logiciel de caisse patient de Baguidi, ou s'y connecter automatiquement | Il reste l'outil du guichet. La redondance (report manuel des totaux du jour) est **assumée** par la Direction. L'interfaçage automatique est hors périmètre (CDCT §4.3) |
| Reprendre dans SIGH-CB le détail patient par patient des ventes | Le report se fait par **nature d'activité et par jour**, pas par patient : ressaisir chaque patient doublerait le travail du guichet et ouvrirait des données médicales au comptable (RG-13) |
| Créer des modules propres à la médecine du travail (visites d'embauche, aptitude, suivi par entreprise) | Initiative séparée, à spécifier après la mise en service. Voir P2 |
| Le site vitrine (`apps/vitrine`, `frontend_html/`) | Non demandé (périmètre : web, poste, mobile). À traiter dans un second temps si Baguidi le souhaite |
| Reprendre les données de Nassiera Too | Elles sont confidentielles et propres à une autre clinique (personnel, paie, comptes, inventaire). Elles ne sont **jamais** livrées à Baguidi |

## 4. Identité de référence (fournie le 06/11/2026)

```
CLINIQUE BAGUIDI « L'AS DE CŒUR »
CENTRE DE MÉDECINE DU TRAVAIL, MÉDECINE GÉNÉRALE
Parakou, République du Bénin

Système Intégré de Gestion Hospitalière
Gestion des stocks et inventaire de la pharmacie, achats et expressions de besoins,
ressources humaines, paie et primes, comptabilité SYSCOHADA, pilotage et tableaux de bord.

Spécialités : Médecine du travail · Santé publique · Gynécologie · Chirurgie · Urologie ·
Rhumatologie · Ophtalmologie · + 7 spécialités

Devise : « Votre bien-être est notre raison d'être. »

Mention légale : CLINIQUE BAGUIDI « L'AS DE CŒUR » — IFU 3201001996110 — RCCM RB/PKO/17 A 4240 du 19/03/2009
```

**Fiche d'identité fournie par la Direction le 06/11/2026**, correspondance avec `IdentiteClinique` :

| Champ de `IdentiteClinique` | Valeur Baguidi |
|---|---|
| `nom` (dénomination sociale) | CLINIQUE BAGUIDI « L'AS DE CŒUR » |
| `sigle` (remplace « CNT ») | **CBG** |
| `nomCourt` | à confirmer (proposition : CLINIQUE BAGUIDI) |
| `slogan` | Votre bien-être est notre raison d'être. |
| adresse géographique (champ nouveau, absent de `IdentiteClinique`) | Quartier Zongo II, Parakou |
| `bp` | 02 BP : 105 PARAKOU (Rép. du Bénin) |
| `telephones` | 95 74 69 56 · 95 95 99 14 · 97 09 34 99 |
| `email` | cliniquebaguidi@yahoo.fr |
| `ifu` | 3201001996110 |
| `rccm` | RB/PKO/17 A 4240 du 19/03/2009 |
| `mentionLegale` | dérivée : `CLINIQUE BAGUIDI « L'AS DE CŒUR » — IFU 3201001996110 — RCCM RB/PKO/17 A 4240 du 19/03/2009.` |
| forme juridique | **non renseignée** (SARL, SA, EI… ? Elle figure habituellement sur l'en-tête légal) |
| `autorisation` (n° d'autorisation d'ouverture) | **non renseigné** |
| `formuleArrete` | générique, reprise telle quelle : « Arrêtée la présente facture à la somme de » |
| `formulePolitesse` (pied de facture) | **non renseignée** (celle de Nassiera Too, « QUE DIEU VOUS GUÉRISSE ! AMINE ! », ne se reprend pas) |

Le **sigle CBG** remplace « CNT » partout où il est visible : numérotation des pièces certifiantes (`<SIGLE> n°/n°/CBG/<direction>/<année>`), préfixe des codes, titre « SIGH-CBG ». Les identifiants techniques (`sigh_poste`, noms de collections) ne changent pas.

**Le logo (reçu le 06/11/2026)** : un badge circulaire. Une double bague **rouge et noire** porte « CLINIQUE BAGUIDI » en haut et « L'AS DE CŒUR » en bas, en capitales blanches sur bandeaux rouges cernés de noir. Au centre, un **cœur** dessiné par deux traits dégradés, **bleu** à gauche et **rouge** à droite, entoure une **roue dentée noire** frappée du **caducée** : la médecine du travail, littéralement. Le fond est blanc.

Palette déduite du logo, **à confirmer** par les valeurs hexadécimales mesurées sur le fichier source :

| Rôle dans le design system | Couleur du logo | Valeur estimée à l'œil |
|---|---|---|
| Primaire (en-têtes, actions principales, ruban) | rouge des bandeaux | ≈ `#E01F26` |
| Secondaire (accents, liens, graphiques) | bleu du cœur | ≈ `#2F6FD6` |
| Texte et contours | noir de la roue | ≈ `#111111` |
| Fonds | blanc / gris clair | `#FFFFFF` |

**Conséquence pour P1-1** : chez Nassiera Too, le bleu marine est la couleur institutionnelle et le rouge est réservé au sens « rupture, péremption, erreur ». Si le **rouge** devient la primaire de Baguidi, un bouton principal et une alerte de rupture auront la même couleur. Trois solutions : (a) primaire **bleue**, rouge réservé à la marque (logo, bandeau de connexion) et aux erreurs ; (b) primaire rouge, et les erreurs passent sur un rouge plus sombre avec une icône obligatoire ; (c) primaire noire ou anthracite, rouge et bleu en accents. **Recommandation : (a)**, qui ne change pas la sémantique des 300 écrans. À trancher par la Direction (Q18).

Le logo et la charte sont dans la branche `baguidi-sources` (en cours d'envoi) : `draft/logo.png`, `draft/Cliniqur BAGUIDI LAS DU COEUR.png`, `draft/design/login_exemple*.png|jpg`.

## 4 bis. Identification fiscale, numérotation et obligations (fournies le 06/11/2026)

**Identification fiscale.** Dénomination, IFU, RCCM : voir §4. Adresse fiscale : 02 BP : 105 PARAKOU (Rép. du Bénin). Devise : **FCFA (XOF)**. Forme juridique et autorisation d'ouverture : « à compléter par la Direction ».

**Régime de TVA : taux normal 18 %.** C'est une **différence de fond avec Nassiera Too**, qui est en régime **exonéré** (produits et actes de santé, TVA à 0 et net à payer = HT + AIB 1 %, facture certifiée MECeF à l'appui). Le moteur sait déjà faire les deux : `packages/domaine/lib/src/caisse/mecef.dart` porte les régimes `exonere` et `normal` (18 %), et le régime est un **paramètre** de `mecef-config`. Le passer à `normal` est donc une **configuration**, pas un développement. Mais une erreur de régime fausse chaque facture normalisée et chaque déclaration : **Q21** demande confirmation écrite, et si certaines natures restent exonérées (médicaments, actes de soins) alors que d'autres sont taxables (prestations de médecine du travail facturées aux entreprises), le régime doit être porté **par nature d'article**, pas par établissement.

**Numérotation des documents.**

| Document | Format Baguidi | Séquence | Remarque |
|---|---|---|---|
| Facture normalisée | `FN-AAAA-NNNNN` | strictement séquentielle | |
| Facture pro-forma | `PRO-AAAA-NNNNN` | indépendante | l'écran `m8-proforma` est fermé par P0-4 : à rouvrir si Baguidi émet des pro-forma (Q22) |
| Avoir | `AV-AAAA-NNNN` | strictement séquentielle | 4 chiffres, pas 5 |
| Dossier patient | `CBG/[n°]/[AA]` | par année civile (RG-01) | M1 est fermé : le format est **paramétré pour la réouverture**, il ne sert pas en version 1 |
| Bon de commande | `BC-AAAA-NNNN` | par exercice | |
| Bon d'expression de besoins | `BEB-AAAA-NNNN` | par exercice | |
| Bulletin de paie | `BP-NNNNN` | par période de paie | ⚠ « par période » avec un numéro sans année : la numérotation repart-elle à 1 chaque mois ? Deux bulletins `BP-00001` coexisteraient alors (Q23) |
| Écriture comptable | `JJJ-AAAA-NNNNN` | par journal | `JJJ` = code du journal (VTE, ACH, BQE, CAI, SAL, OD, AN…) |

**Exigence P0-10 (numérotation)** : chaque format ci-dessus est appliqué par la fabrique de numéros existante du document concerné, à la place du format de Nassiera Too. Ce qui est « strictement séquentiel » ne présente **aucun trou** : un numéro attribué ne se réattribue jamais, une pièce annulée garde le sien (avoir, RG-14). La reprise des séquences sur plusieurs postes suit le mécanisme existant des plages allouées par la mère.
- *Critères* : 100 factures normalisées émises sur deux postes fileuls et la mère donnent `FN-2026-00001` à `FN-2026-00100` sans trou ni doublon ; changement d'année = reprise à 1 ; un bulletin et une écriture portent le format attendu.
- À vérifier dans le code : la base construit-elle ces préfixes en dur dans chaque fabrique, ou depuis un paramètre ? S'ils sont en dur, la bonne correction est de les **paramétrer** (une table de formats), pas de les réécrire un par un : c'est ce qui permettra la troisième clinique.

**Obligations déclaratives.**

| Déclaration | Périodicité | Échéance Baguidi | Base Nassiera Too | Écran producteur dans le logiciel |
|---|---|---|---|---|
| Cotisations CNSS | mensuelle | **15** du mois suivant | **10** du mois suivant (`D.CALENDRIER_FISCAL`) | `m11` état des cotisations CNSS ; suivi `m12-echeances` |
| ITS | mensuelle | 10 du mois suivant | 10 | `m11` état ITS ; `m12-echeances` |
| VPS | mensuelle | 10 du mois suivant | 10 | `m11` état VPS ; `m12-echeances` |
| Transmission des factures normalisées | continue | à l'émission | à l'émission | `MECEF` (centre de supervision) |
| États financiers de synthèse | annuelle | clôture de l'exercice | 30 avril (liquidation du solde puis dépôt) | `m12-etats-financiers`, `m12-cloture` |

Le calendrier fiscal est un **référentiel** (`D.CALENDRIER_FISCAL`, semé au socle, source unique de `cfg-comptabilite` et `m12-echeances`) : y porter l'échéance CNSS au 15 alimente les deux écrans. La base porte aussi des obligations que la liste de Baguidi ne cite pas : **AIB**, quatre acomptes d'**impôt sur les sociétés**, **patente**, **CCIB**, **TVM**, redevances **ORTB** Radio/Télé (qui se cumulent), **TVA** (déclaration mensuelle, désormais due puisque le régime est au taux normal). **Q24** : sont-elles à retirer, ou la liste reçue ne cite-t-elle que les principales ? Une obligation retirée à tort ferait disparaître une échéance de l'alarme de `m12-echeances`.

## 5. Ce que l'analyse de la base a établi

- **L'identité vit en un seul endroit dans le code** : `packages/domaine/lib/src/impression/identite.dart` (`IdentiteClinique`, environ 140 usages). La reprendre change toutes les pièces imprimées. Quelques fichiers la recopient en dur et doivent être alignés : `cfa_identite.dart`, `page_standard.dart` (pied de page), `cpb_liasse.dart`, `cpc_liasse.dart`, `cfa_regles.dart`.
- **Mais l'identité Nassiera Too est aussi dans les données et les tests** : 94 fichiers citent « NASSIERA », 58 « Natitingou », 194 le format `CNT/`. La plupart sont des vecteurs de test (`packages/domaine/test/vecteurs`), des fixtures (`apps/poste/test/fixtures`) et le jeu livré (`apps/poste/assets/donnees/jeu/*.json`).
- **Le thème est piloté par des jetons** (`apps/poste/lib/core/theme.dart` lit `JetonsSigh` et `JetonsShell`). Changer la palette ne demande pas de toucher aux écrans.
- **La fermeture de modules existe déjà** : collection `modulesActifs`, écran `cfg-modules` (`apps/poste/lib/modules/cfg/cfb_modules.dart`), jeu livré `assets/donnees/jeu/modulesActifs.json`. La banque de sang et les donneurs y sont déjà fermés. Seul le NOYAU (CFG, DASH) ne se ferme pas. Une fiche peut fermer un module entier ou une liste d'écrans.
- **Le poste dépend de paquets du monorepo** : `apps/poste/pubspec.yaml` référence `packages/domaine` et `packages/sync_dart` par chemin relatif. Copier seulement `apps/web`, `apps/poste` et `apps/mobile` ne compilerait pas.
- **Le dépôt `sighcbg` est vide** : aucun commit, aucune branche distante.

## 6. Récits utilisateurs

**Direction de la Clinique Baguidi**
- En tant que Directrice, je veux que chaque facture fournisseur, bulletin de paie, état comptable et bon porte l'en-tête et l'IFU/RCCM de Baguidi, pour que nos pièces soient opposables aux impôts et à la CNSS.
- En tant que Directrice, je veux pouvoir activer MECeF le jour où nous serons assujettis à la facture normalisée, sans attendre une nouvelle version.
- En tant que Directrice, je veux activer ou désactiver les primes NS 132 et les évaluations NS 131, parce que ces barèmes sont des notes de service de Nassiera Too et que nous pourrions adopter les nôtres.
- En tant que Directrice, je veux voir les recettes de la clinique par nature d'activité, par jour, par mois et par année, pour piloter sans ouvrir le logiciel de caisse.

**Comptable**
- En tant que comptable, je veux reporter chaque soir les ventes du jour du logiciel de caisse, ligne par nature (actes, certificats, hospitalisations…), pour que la comptabilité suive toute l'activité.
- En tant que comptable, je veux que le logiciel refuse un second report de la même journée pour la même caisse, pour ne jamais compter deux fois une recette.
- En tant que comptable, je veux saisir le total affiché par le logiciel de caisse et voir l'écart avec ma ventilation, pour détecter une erreur de report avant de valider.
- En tant que comptable, je veux enregistrer les dépenses et les sorties de caisse de la journée, pour que l'état de caisse se tienne.
- En tant que comptable, je veux reporter la part due par un assureur ou une entreprise cliente, pour que la créance apparaisse dans le suivi des créances (M9).

**Pharmacie**
- En tant que dispensateur, je veux sortir des produits sur un bon de sortie interne émis par un service, pour justifier la consommation sans dossier patient.
- En tant que dispensateur, je veux enregistrer une vente de pharmacie au comptant sans dossier patient, pour que le stock et la caisse bougent ensemble.

**Agents (gestionnaire de stock, comptable, DAF, RH)**
- En tant que gestionnaire de stock, je veux retrouver tout le CRUD de la pharmacie et des stocks (articles, lots FEFO, transferts, inventaires, pertes), pour remplacer nos fiches papier.
- En tant qu'agent, je veux un écran de connexion aux couleurs et au logo de ma clinique, pour savoir que je suis dans le bon logiciel.
- En tant qu'agent, je ne veux voir dans le ruban que les activités que la clinique exerce, pour ne pas chercher ce qui n'existe pas.

**Administrateur du poste**
- En tant qu'administrateur, je veux installer le poste mère sur un ordinateur vierge et ne trouver aucune donnée d'une autre clinique, pour démarrer sur un magasin propre.
- En tant qu'administrateur, si un agent tape l'adresse d'un écran fermé, je veux qu'il tombe sur la page « accès refusé », pour qu'aucun module fermé ne reste atteignable.

**Cas limites**
- Un poste où SIGH-CNT est déjà installé (machine de démonstration) : l'installation de SIGH-CB ne doit ni l'écraser ni lire ses données.
- La réouverture d'un module fermé (MECeF) doit rendre l'écran vide et fonctionnel, pas un écran cassé faute de données amorcées.

## 7. Exigences

### P0 : indispensables à la livraison

**P0-1. Import de la base dans `sighcbg`**
- Importer depuis le commit `2bb35df` : `apps/web`, `apps/poste`, `apps/mobile`, **et leurs dépendances** `packages/domaine`, `packages/sync_dart`, `packages/rbac`, `packages/referentiels`, `packages/schema`, `packages/impression`, `packages/sync` (banc du protocole), ainsi que `infra/poste`, la configuration racine (`package.json`, `.gitignore`, `.nvmrc`, `.editorconfig`, `.gitattributes`) et les ADR de `docs/architecture/`.
- Le commit d'import cite le dépôt, la branche et le commit d'origine.
- *Critères* : `flutter analyze` et `flutter test` passent sur `apps/poste` et `apps/mobile` **avant tout changement d'identité** ; les tests Laravel de `apps/web` passent ; `npm run banc:sync` passe. Ce point de départ vert est la référence de toutes les étapes suivantes.

**P0-2. Identité légale**
- Remplacer les constantes de `IdentiteClinique` par celles de Baguidi (§4) et aligner les cinq fichiers qui les recopient.
- Remplacer `apps/poste/assets/img/logo.png`, `logo.jpeg` et `icone-poste.png` par le logo Baguidi.
- Changer les libellés visibles du relais web (nom de l'application, gabarits) et de l'application mobile (nom Android).
- *Critères* :
  - [ ] Un contrôle automatique (script `controle-identite`) cherche « NASSIERA », « Natitingou », « 3201642748214 », « RB/NAT », « raison de vivre », « cliniquenassiera » dans tout le dépôt hors historique et dossier d'archive. **Résultat attendu : 0.** Il tourne en CI.
  - [ ] Facture fournisseur, bulletin de paie, état comptable et bon de commande imprimés en PDF portent l'en-tête Baguidi, IFU 3201001996110 et RCCM RB/PKO/17 A 4240 du 19/03/2009.
  - [ ] Le pied de page légal de chaque écran du poste affiche la mention légale Baguidi.

**P0-3. Données livrées propres**
- Purger `apps/poste/assets/donnees/jeu/` de toute donnée de Nassiera Too : personnel, paie, inventaire SAGE, écritures, liasse fiscale, assureurs, comptes, patients et pièces de soins.
- Conserver les **référentiels génériques** (plan comptable SYSCOHADA, calendrier fiscal béninois, familles d'articles, régimes de travail types) et les marquer « à valider par Baguidi ».
- Régénérer les vecteurs de test et les fixtures qui portent l'identité Nassiera Too, sans changer ce qu'ils vérifient.
- *Critères* : un poste mère installé à neuf affiche des registres vides (ou de démonstration explicitement fictifs, selon la décision Q4) ; aucun nom d'agent de Nassiera Too n'apparaît ; tous les tests passent.

**P0-4. Fermeture des modules hors périmètre**
- Ajouter au jeu livré `modulesActifs.json` des fiches `actif: false` (motif « Hors périmètre Clinique Baguidi », date, auteur Direction) pour :

| Module | Code | Fermeture |
|---|---|---|
| Banque de sang | M5 (écran `m5-banque-sang`) | déjà fermée dans la base |
| Donneurs & transfusions | M5 (écran `m5-donneurs`) | déjà fermée dans la base |
| Patients & Dossier médical | M1 | module entier |
| RDV, Visites & Consultations | M2 | module entier (rangées secondaires et imagerie comprises) |
| Hospitalisation | M3 | module entier |
| Maternité, Naissances & Décès | M4 | module entier |
| Laboratoire clinique | M5 | module entier |
| Facturation & Caisse | M8 | **partielle** : écrans de facturation patient fermés (`m8-facturation`, `m8-factures`, `m8-proforma`, `m8-paiements`, `m8-reliquats`, `m8-remboursements`). Restent ouverts : `m8-operations`, `m8-caisse`, `m8-recettes`, `m8-dashboard` (voir P0-9). `m8-facture-avoir` selon Q12 |

- Les tableaux de bord des postes purement cliniques (médecin, sage-femme, laboratoire, maternité, échographiste, chirurgien, anesthésiste, caisse) sont fermés par écran : un tableau sans module derrière n'a rien à montrer.
- *Critères* :
  - [ ] Pour chacun des 16 rôles, `inventaire-rbac` ne liste aucun écran des modules fermés.
  - [ ] L'adresse directe d'un écran fermé mène à la page 403, administrateur compris.
  - [ ] La recherche globale ne propose aucun résultat d'un module fermé (patients compris).
  - [ ] Les modules conservés montent et fonctionnent avec ces modules fermés (le banc d'indépendance existe déjà : scénario 54 de la maquette et son équivalent poste).

**P0-5. Trois modules activables depuis Paramètres système**
- MECeF (module `MECEF`), Primes NS 132 (écrans de primes de M11), Évaluations & sanctions NS 131 (`m10-evaluations` et l'onglet *Barème NS 131* de `cfg-systeme`) portent chacun une bascule dans `cfg-modules`.
- **Les trois arrivent ouverts à l'installation** (décision du 06/11/2026). La Direction les ferme depuis *Paramètres système*.
- Quand Primes NS 132 est fermé, le calcul de paie n'ajoute **aucune** prime NS 132 et le bulletin ne porte pas la rubrique. Quand NS 131 est fermé, aucune sanction ne remonte à la paie.
- *Critères* :
  - [ ] Fermer puis rouvrir chaque bascule rend l'écran en l'état, sans erreur.
  - [ ] Bulletin calculé avec NS 132 fermé = brut sans primes NS 132 (test chiffré).
  - [ ] La bascule est journalisée (RG-12) avec son auteur.

**P0-6. CRUD des modules conservés**
- M6 Pharmacie & Stocks, M7 Achats & Fournisseurs, **M9 Assurances & Créances** (décision du 06/11/2026), M10 RH, M11 Paie, M12 Comptabilité, M13 Administration, M14 Sécurité, CFG, GED, RAP, PIL, DASH.
- **M9 sans facturation patient** : les écrans de référentiel et de suivi (compagnies, conventions, créances, relances, historique) restent pleinement utilisables ; les créances y naissent des reports de recettes à crédit (P0-8). Les écrans qui exigent le détail patient par patient (`m9-assures`, `m9-prises-en-charge`, `m9-factures-assureur`, `m9-facture-mere`) restent ouverts mais **disent** qu'ils ne se remplissent pas sans facturation patient, plutôt que d'afficher un zéro trompeur (Q13).
- *Critères* : tous les tests existants de ces modules passent sans modification de leur logique ; l'audit RBAC des écrans conservés donne 0 promesse et 0 commande cachée.

**P0-8. Report des recettes journalières (nouvel écran M12, `m12-report-recettes`)**

Le seul vrai développement du chantier. Il réutilise des mécanismes existants : l'éditeur de lignes en modale des dépenses multi-lignes (`m12-depenses`), l'écriture plate par ligne, le contrôle RG-10 avant écriture, la naissance en brouillon, la plage de dates du kit.

- Un **report** = une journée × une caisse source (le logiciel de caisse, ou chaque caisse s'il y en a plusieurs : Q14). Il porte des **lignes par nature d'activité** : consultations, actes, certificats, hospitalisations, analyses, imagerie, pharmacie, visites de médecine du travail, autres (liste administrable, rattachée aux six secteurs et aux groupes de prestation existants).
- Chaque ligne distingue **encaissé** (espèces, mobile money, banque) et **à crédit** (tiers désigné : compagnie d'assurance ou entreprise cliente).
- Le comptable saisit aussi le **total affiché par le logiciel de caisse**. L'écran montre l'écart avec la somme des lignes ; un écart non nul se dit et exige un motif pour valider.
- Écriture produite, une ligne plate par compte : débit trésorerie (57x / 52x) pour l'encaissé, débit 411 du tiers pour le crédit, crédit du compte de produit 70x de chaque nature. Équilibre contrôlé avant écriture (RG-10), pièce en brouillon, validée par un geste humain.
- **Unicité** : un second report pour la même date et la même caisse est refusé en nommant le premier. Une correction passe par une modification du brouillon, ou par contre-passation si la pièce est validée (une pièce validée ne se réécrit jamais).
- **Suivi et statistiques** : recettes par nature, par secteur, par mode d'encaissement, par tiers, par jour / mois / trimestre / année (les six périodicités de `C.PERIODES`), journées non reportées signalées. Les écrans existants `m8-recettes`, `m12-rentabilite-groupes`, `m12-tableau-decisionnel`, `m12-bfr` et le compte de résultat lisent ces reports.
- *Critères* :
  - [ ] Given une journée reportée, When le comptable tente un second report pour la même date et la même caisse, Then il est refusé et le premier est nommé.
  - [ ] La somme débit = la somme crédit pour chaque report (test sur 100 reports aléatoires).
  - [ ] La part à crédit d'un assureur apparaît dans `m9-creances` sous ce tiers, et disparaît de la créance quand son règlement est saisi.
  - [ ] Les statistiques par nature sur un mois égalent la somme des lignes reportées sur ce mois (recompte du magasin).
  - [ ] Un jour ouvré sans report apparaît dans la liste « journées non reportées » du tableau de bord comptable.
  - [ ] Aucun nom de patient ni donnée médicale n'est saisi ni affiché (RG-13).

**P0-9. Caisse minimale et sorties de pharmacie**
- **Vente de pharmacie au comptant sans dossier patient**, depuis `m8-operations` : l'opération porte ses lignes d'articles, sort le stock du rayon de détail (RG-03 : justificatif = n° de l'opération ; refus nommé si une ligne n'est pas couverte) et produit l'écriture d'encaissement. RG-02 s'applique (prix d'achat, sans marge). À vérifier dans le code : `m8-operations` enregistre aujourd'hui une opération sans dossier, mais il faut confirmer qu'elle sait sortir du stock.
- **Bon de sortie interne** : la consommation d'un service (bloc, salle de soins, visites d'entreprise) sort du stock sur un **bon de besoins servi** (`m7-besoins`, déjà ouvert à tout agent, avec quantité demandée ≠ quantité accordée). Le n° du bon est le justificatif RG-03. Aucune caisse, aucun patient.
- **Ce qui se recoupe** : les ventes de pharmacie enregistrées dans SIGH-CB **ne se reportent pas une seconde fois** dans le report journalier (P0-8). La nature « pharmacie » du report ne sert qu'aux ventes de pharmacie faites dans le logiciel de caisse patient, si la clinique en fait (Q15).
- `m8-caisse` (état de caisse journalier) agrège les opérations de caisse, les ventes de pharmacie et les dépenses (`m12-depenses`) de la journée.
- *Critères* :
  - [ ] Vente de 3 articles : stock du détail diminué de chaque quantité, mouvement rattaché au n° d'opération, écriture équilibrée en brouillon.
  - [ ] Vente d'une quantité supérieure au stock : refusée en nommant l'article.
  - [ ] Sortie sur bon de besoins servi : mouvement rattaché au n° du bon ; sortie sans bon refusée.
  - [ ] L'état de caisse du jour = opérations + ventes − dépenses, recalculé depuis les registres.

**P0-7. Cohabitation avec SIGH-CNT**
- Identifiants d'installation distincts : `applicationId` Android, nom et GUID de l'installateur Windows (`apps/poste/installer`), dossier de données du poste, nom des bases SQLite, préfixes de stockage.
- *Critère* : SIGH-CNT et SIGH-CB installés sur la même machine démarrent chacun sur leurs propres données.

### P1 : à livrer rapidement ensuite

**P1-1. Design system Baguidi**
- Remplacer les valeurs de `JetonsSigh` / `JetonsShell` par la palette Baguidi (primaire, secondaire, fonds). Garder la sémantique vert / orange / rouge, que les écrans utilisent pour l'état des stocks.
- *Critères* : contraste WCAG AA sur texte principal et boutons ; aucune couleur écrite en dur hors jetons (contrôle par recherche).

**P1-2. Écran de connexion Baguidi (maquette de référence reçue le 06/11/2026)**

Refaire `acc_gabarit.dart` / `acc_ecrans.dart` sur la maquette fournie. Une carte centrée aux coins arrondis, posée sur un fond bleu très pâle et flou, coupée en deux :

| Zone | Contenu de la maquette |
|---|---|
| **Liseré supérieur** | fin filet de toute la largeur de la carte, **rouge puis bleu** (les deux traits du cœur du logo) |
| **Panneau gauche (≈ 55 %)** | fond en **dégradé bleu** (≈ `#1E63C0` en haut à gauche vers ≈ `#123E7C` en bas), deux grands disques translucides en décor, et un **cœur avec tracé d'électrocardiogramme** en filigrane en bas à droite |
| ‣ en-tête | logo dans une pastille blanche ronde ; « CLINIQUE BAGUIDI « L'AS DE CŒUR » » en capitales grasses blanches ; « CENTRE DE MÉDECINE DU TRAVAIL – MÉDECINE GÉNÉRALE » en petites capitales bleu clair ; « Parakou — République du Bénin » en blanc atténué |
| ‣ titre | « Système Intégré de Gestion Hospitalière », grand, blanc, police géométrique grasse |
| ‣ présentation | « Gestion des stocks et inventaire de la pharmacie, achats et expressions de besoins, ressources humaines, paie et primes, comptabilité SYSCOHADA, pilotage et tableaux de bord. » |
| ‣ spécialités | sept pastilles à contour blanc translucide (Médecine du travail, Santé publique, Gynécologie, Chirurgie, Urologie, Rhumatologie, Ophtalmologie) puis une pastille **pleine blanche** « + 7 spécialités » |
| ‣ pied | la devise « Votre bien-être est notre raison d'être. » en **police manuscrite**, puis la mention légale en petit texte atténué |
| **Panneau droit (≈ 45 %)** | fond blanc |
| ‣ titre | « Connexion » en bleu foncé, sous-titre « Authentification individuelle obligatoire » en gris |
| ‣ champs | « Identifiant » (exemple saisi : `m-001@baguidi-clinique.bj`) ; « Mot de passe » avec lien **« Mot de passe oublié ? »** aligné à droite et œil d'affichage dans le champ |
| ‣ option | case « Se souvenir de ce poste » |
| ‣ action | bouton pleine largeur **rouge** (≈ `#D32F2F`) « Se connecter » avec icône d'entrée |

Ce que la maquette tranche, et ce qu'elle laisse ouvert :
- **Q18 en partie tranchée** : la marque est **bleue** (panneau, titres) et le **bouton d'action principal de la connexion est rouge**. Reste à décider si les boutons principaux des 300 écrans suivent ce rouge (et les erreurs passent alors sur un rouge plus sombre avec icône obligatoire), ou si le rouge reste propre à la connexion et à la marque. Recommandation inchangée : boutons de l'application en bleu, rouge réservé à la connexion, au logo et aux alertes.
- **Polices** : trois familles (titres géométriques, corps de texte, devise manuscrite). Elles doivent être **embarquées dans le poste** (`apps/poste/assets/polices/`), aucune requête réseau : le poste fonctionne hors ligne. Noms exacts des polices à obtenir du concepteur de la maquette (Q19) ; à défaut, équivalents libres de licence.
- **L'identifiant a la forme d'une adresse** (`m-001@baguidi-clinique.bj`) : le poste actuel connecte par identifiant de compte. Q20 : est-ce un exemple décoratif ou une règle de nommage des comptes ? Le domaine `baguidi-clinique.bj` diffère de l'e-mail officiel (`cliniquebaguidi@yahoo.fr`).
- **« Mot de passe oublié ? »** se branche sur le mécanisme existant (code de secours et coffre de récupération du poste) ; il ne doit pas promettre un envoi par courriel si le relais SMTP n'est pas configuré.
- **« Se souvenir de ce poste »** existe-t-il dans le poste de base ? À vérifier ; sinon, il ne retient que l'identifiant, jamais le mot de passe.
- **Responsive** : sous la largeur d'une tablette, le panneau bleu passe au-dessus et se réduit à l'en-tête et au titre.
- *Critères* : rendu comparé côte à côte avec la maquette à 1920 px et 1366 px ; contraste AA du texte blanc sur le dégradé et du libellé du bouton rouge ; aucun texte de Nassiera Too ; fonctionne hors ligne (polices et logo locaux) ; capture validée par la Direction de Baguidi.

**P1-3. Relais web et mobile aux couleurs Baguidi**
- Panneau superadmin du relais et application mobile alignés sur les jetons.

**P1-4. Masquer les rôles sans objet**
- Médecin, sage-femme, biologiste, échographiste, chirurgien, anesthésiste, caissier : rôles archivés (RG-14, jamais supprimés) si la Direction le confirme (Q3).

### P2 : à anticiper, hors version 1

- **Modules propres à la médecine du travail** (entreprises clientes, visites d'embauche et périodiques, fiches d'aptitude). Ne rien fermer de façon irréversible qui empêcherait de rouvrir M1/M2 plus tard.
- **Facturation aux entreprises** si M8 reste fermé : la réouverture de M8 doit rester possible sans migration.
- **Report des correctifs de SIGH-CNT** : garder la liste des fichiers « propres à Baguidi » (`docs/DIFFERENCES-CNT.md`) à jour pour que le report reste mécanique.
- **Dérivation vers une troisième clinique** : si l'opération se répète, extraire l'identité, le thème et le périmètre dans un seul fichier de configuration d'établissement.

## 8. Indicateurs de réussite

| Indicateur | Cible | Mesure |
|---|---|---|
| Occurrences de l'identité Nassiera Too | **0** | script `controle-identite` en CI, à chaque commit |
| Tests poste, mobile, domaine, web | 100 % verts, même nombre de tests qu'à l'import (moins ceux des modules fermés, listés un par un) | CI |
| Écrans de modules fermés atteignables | **0** sur 16 rôles | `inventaire-rbac` + test des adresses directes |
| Promesses à l'audit RBAC | **0** | `audit-rbac` |
| Fichiers modifiés hors liste « propres à Baguidi » | **0** | diff par rapport au commit d'import |
| Pièces imprimées validées par la Direction Baguidi | facture fournisseur, bulletin, état comptable, bon de commande | revue visuelle, à la livraison |
| Journées de caisse reportées | 100 % des jours ouvrés, écart reporté / logiciel de caisse = 0 F | tableau de bord comptable, chaque mois |
| Délai de report | report du jour J saisi au plus tard à J+1 | date de saisie / date du report |
| Mise en service (indicateur tardif) | stock et paie tenus dans SIGH-CB pendant un mois complet sans retour au papier | Direction Baguidi, 1 mois après installation |

## 9. Questions ouvertes

| # | Question | Pour | Bloquant ? |
|---|---|---|---|
| ~~Q1~~ | ~~M9 à garder ou à fermer ?~~ **Tranché le 06/11/2026 : gardé** (P0-6) | | |
| ~~Q2~~ | ~~État par défaut de MECeF, NS 132, NS 131 ?~~ **Tranché le 06/11/2026 : ouverts** (P0-5) | | |
| Q3 | Les rôles cliniques (médecin, sage-femme, biologiste, caissier…) : à archiver ou à garder ? | Direction Baguidi | Non |
| Q4 | Registres vides à l'installation, ou jeu de démonstration **fictif** aux couleurs de Baguidi pour la formation ? | Direction Baguidi | **Oui** (P0-3) |
| ~~Q5~~ | ~~Justificatif des sorties de pharmacie ?~~ **Tranché le 06/11/2026 : les deux** — bon de sortie interne ET caisse minimale pour les ventes de pharmacie ; le comptable reporte les ventes du logiciel de caisse patient (P0-8, P0-9) | | |
| Q6 | ~~Sigle, BP, téléphones, e-mail, adresse fiscale, devise~~ **fournis le 06/11/2026** (§4, §4 bis). Restent : **forme juridique** et **n° d’autorisation d’ouverture** (« à compléter par la Direction »), **formule de politesse** des factures, nom court | Direction Baguidi | Non (des valeurs vides n'empêchent pas le développement ; elles bloquent la recette des pièces imprimées) |
| Q7 | Fichier source du logo (vectoriel de préférence) et charte graphique (couleurs en hexadécimal, police) | Direction Baguidi | Oui pour P1-1/P1-2, non pour P0 |
| Q8 | Historique git : importer avec l'historique de SIGH-CNT (report de correctifs facilité, mais l'historique contient des données de Nassiera Too et un mot de passe commis le 17/10/2026) ou en **instantané** (recommandé) ? | Ingénierie + Direction CNT | **Oui** (P0-1) |
| Q9 | La Direction de Nassiera Too a-t-elle autorisé la réutilisation du code pour une autre clinique ? | Direction CNT, juridique | **Oui** (avant tout import) |
| Q10 | Les 7 spécialités non nommées (« + 7 spécialités ») : liste complète pour l'écran de connexion ? | Direction Baguidi | Non |
| Q11 | Le relais web (cPanel) : nouvel hébergement et nouveau domaine pour Baguidi, ou relais partagé ? Un relais partagé mêlerait les journaux de deux cliniques | Ingénierie + Direction Baguidi | Oui avant mise en service, non pour le développement |
| Q12 | Une vente de pharmacie erronée se corrige-t-elle par **facture d'avoir** (`m8-facture-avoir`, à garder ouvert) ou par une opération de remboursement ? | Direction Baguidi + comptable | Non |
| Q13 | Les écrans M9 qui exigent le détail patient (assurés, prises en charge, factures mensuelles assureur, facture mère) : les garder ouverts avec leur avertissement, ou les fermer par écran ? Baguidi facture-t-elle les assureurs depuis son logiciel de caisse ? | Direction Baguidi | Non |
| Q14 | Combien de caisses alimentent le logiciel de caisse patient (une seule, ou une par point de vente) ? Le report se fait par journée **et par caisse** | Comptable Baguidi | **Oui** (P0-8) |
| Q15 | La pharmacie vend-elle **aussi** dans le logiciel de caisse patient ? Si oui, quelle vente fait foi pour le stock, pour ne pas sortir deux fois le même produit ? | Direction Baguidi + gestionnaire de stock | **Oui** (P0-9) |
| Q16 | Liste des natures d'activité du report et comptes de produit 70x de chacune (le plan de Baguidi peut différer de celui de Nassiera Too). Un export du logiciel de caisse (même une capture de son état journalier) permettrait d'aligner les natures sur ce qu'il imprime | Comptable Baguidi | **Oui** (P0-8) |
| Q18 | La maquette de connexion fixe la marque en **bleu** et le bouton de connexion en **rouge**. Les boutons principaux de l'application suivent-ils ce rouge, ou restent-ils bleus (recommandé) ? Voir P1-2 | Direction Baguidi + design | Non pour P0, oui pour P1-1 |
| Q19 | Noms des trois polices de la maquette de connexion (titres, corps, devise manuscrite) et licence d'embarquement | concepteur de la maquette | Non |
| Q20 | L'identifiant en forme d'adresse (`m-001@baguidi-clinique.bj`) est-il une règle de nommage des comptes ou un exemple ? Le domaine `baguidi-clinique.bj` existe-t-il ? | Direction Baguidi | Non |
| Q21 | **TVA au taux normal 18 % sur TOUT ?** Nassiera Too est exonérée (produits et actes de santé). Confirmation écrite du régime de Baguidi, et liste des natures éventuellement exonérées (médicaments, soins) si le régime est mixte | Direction Baguidi + conseil fiscal | **Oui** (P0-10 et MECeF) |
| Q22 | Baguidi émet-elle des factures pro-forma ? Si oui, `m8-proforma` reste ouvert | Direction Baguidi | Non |
| Q23 | Bulletin `BP-NNNNN` « par période de paie » : la séquence repart-elle à 1 chaque mois (et comment distinguer deux `BP-00001`), ou est-elle continue ? | DAF Baguidi | Non |
| Q24 | Les obligations de la base absentes de la liste reçue (AIB, acomptes IS, patente, CCIB, TVM, ORTB, déclaration de TVA) : à retirer ou à garder ? | Comptable Baguidi | Non |
| Q17 | Qui fait le report : le comptable seul, ou l'assistant comptable avec validation par le comptable (séparation des tâches) ? | Direction Baguidi | Non |

## 10. Calendrier et phasage

Aucune échéance n'a été communiquée. Phasage proposé, chaque phase se termine sur une CI verte :

| Phase | Contenu | Dépend de |
|---|---|---|
| **0. Décisions** | Q4, Q6, Q8, Q9 (Q1, Q2, Q5 tranchées) | Direction Baguidi, Direction CNT |
| **1. Import** | P0-1 : base importée, CI verte **sans aucun changement** | Q8, Q9 |
| **2. Identité et données** | P0-2, P0-3, P0-7, script `controle-identite` | Q4, Q6 |
| **3. Périmètre** | P0-4, P0-5, P0-6 | aucune |
| **3 bis. Caisse et report** | P0-9 (caisse minimale, bons de sortie), puis P0-8 (report des recettes, statistiques) | Q14, Q15, Q16 |
| **4. Charte graphique** | P1-1, P1-2, P1-3 | Q7 |
| **5. Recette** | pièces imprimées validées, installation à blanc sur un poste Baguidi, P1-4 | phases 1 à 4 |

Règle de conduite : **une phase par lot de commits**, jamais l'identité et le périmètre dans le même commit. Un défaut se rattache ainsi à sa cause, et le report d'un correctif de SIGH-CNT reste lisible.
