# PRD : SIGH-CB, réplique du logiciel SIGH-CNT pour la Clinique Baguidi « L'As de Cœur »

| | |
|---|---|
| **Statut** | Brouillon, à valider par la Direction de la Clinique Baguidi |
| **Date** | 06/11/2026 |
| **Dépôt cible** | `massenon/sighcbg` (vide à ce jour) |
| **Base** | `massenon/sighcnt`, branche `claude/sighcnt-monorepo-offline-first-i0v3v9`, commit `2bb35df` (06/11/2026) |
| **Nature du chantier** | Restructuration et changement d'identité. **Pas de réécriture** : l'architecture et le code restent ceux de SIGH-CNT |

---

## 1. Problème

La Clinique Baguidi « L'As de Cœur » (Parakou) est un centre de médecine du travail et de médecine générale. Elle a besoin d'un système de gestion pour sa pharmacie et ses stocks, ses achats et expressions de besoins, ses RH, sa paie, sa comptabilité SYSCOHADA et son pilotage. Le logiciel SIGH-CNT, construit pour la Clinique Nassiera Too (Natitingou), couvre déjà ces fonctions, avec son architecture hors ligne d'abord (poste Flutter fileul/mère, relais web Laravel, mobile).

Repartir de zéro coûterait des mois et ferait perdre les règles de gestion déjà éprouvées (RG-01 à RG-14, 74 parcours, audit RBAC). Livrer SIGH-CNT tel quel serait une faute : chaque pièce porterait l'identité légale d'une autre clinique (IFU, RCCM, logo), et la moitié des modules (soins, laboratoire, caisse) relèvent d'activités que Baguidi n'exerce pas, ou pas dans ce logiciel.

## 2. Objectifs

1. **Une identité, une seule.** Toute pièce imprimée, tout écran, toute page du relais et l'application mobile portent l'identité de la Clinique Baguidi. **Aucune occurrence** de l'identité Nassiera Too dans ce qui est livré, vérifiée par un contrôle automatique.
2. **Le périmètre Baguidi, et lui seul.** Les huit modules hors périmètre sont fermés pour tous les rôles : absents du ruban, de la recherche, des hubs et des adresses. Trois modules (MECeF, Primes NS 132, Évaluations NS 131) se ferment et se rouvrent depuis *Paramètres système*.
3. **Les modules conservés restent complets.** Stock, achats, RH, paie, comptabilité, administration, sécurité, configuration, GED, rapports et pilotage gardent leur CRUD entier (créer, consulter, modifier, archiver, restaurer, imprimer). Leurs bancs d'essai restent verts.
4. **La charte graphique Baguidi.** Couleurs, logo et écran de connexion suivent le design system de Baguidi, sans toucher à la géométrie des écrans.
5. **Le code reste synchronisable avec SIGH-CNT.** Les différences entre les deux dépôts tiennent dans des fichiers d'identité, de thème, de données et de configuration identifiés. Un correctif de SIGH-CNT se reporte sans conflit sur le reste du code.

## 3. Hors objectifs

| Hors objectif | Raison |
|---|---|
| Réécrire ou réarchitecturer le code | Demande explicite. L'architecture hors ligne (ADR-0002, ADR-0005) et le protocole de synchronisation restent tels quels |
| Supprimer le code des modules fermés | Une fermeture est **réversible** (doctrine `modulesActifs` : rien n'est supprimé, la réouverture rend tout en l'état). Supprimer le code romprait aussi la synchronisation avec SIGH-CNT |
| Renommer les identifiants techniques (`sigh_poste`, codes M1 à M14, identifiants de rôles, noms de collections) | Doctrine « laborantin » : on ne renomme pas un identifiant technique. Seul ce qui est visible ou légal change |
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

Champs de `IdentiteClinique` **encore inconnus** (voir §9) : sigle, nom court, BP, téléphones, e-mail, n° d'autorisation d'ouverture, formule de politesse des factures, logo, couleurs.

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
| Facturation & Caisse | M8 | module entier |

- Les tableaux de bord des postes purement cliniques (médecin, sage-femme, laboratoire, maternité, échographiste, chirurgien, anesthésiste, caisse) sont fermés par écran : un tableau sans module derrière n'a rien à montrer.
- *Critères* :
  - [ ] Pour chacun des 16 rôles, `inventaire-rbac` ne liste aucun écran des modules fermés.
  - [ ] L'adresse directe d'un écran fermé mène à la page 403, administrateur compris.
  - [ ] La recherche globale ne propose aucun résultat d'un module fermé (patients compris).
  - [ ] Les modules conservés montent et fonctionnent avec ces modules fermés (le banc d'indépendance existe déjà : scénario 54 de la maquette et son équivalent poste).

**P0-5. Trois modules activables depuis Paramètres système**
- MECeF (module `MECEF`), Primes NS 132 (écrans de primes de M11), Évaluations & sanctions NS 131 (`m10-evaluations` et l'onglet *Barème NS 131* de `cfg-systeme`) portent chacun une bascule dans `cfg-modules`.
- L'état par défaut à l'installation suit la décision Q2.
- Quand Primes NS 132 est fermé, le calcul de paie n'ajoute **aucune** prime NS 132 et le bulletin ne porte pas la rubrique. Quand NS 131 est fermé, aucune sanction ne remonte à la paie.
- *Critères* :
  - [ ] Fermer puis rouvrir chaque bascule rend l'écran en l'état, sans erreur.
  - [ ] Bulletin calculé avec NS 132 fermé = brut sans primes NS 132 (test chiffré).
  - [ ] La bascule est journalisée (RG-12) avec son auteur.

**P0-6. CRUD des modules conservés**
- M6 Pharmacie & Stocks, M7 Achats & Fournisseurs, M10 RH, M11 Paie, M12 Comptabilité, M13 Administration, M14 Sécurité, CFG, GED, RAP, PIL, DASH (M9 selon Q1).
- *Critères* : tous les tests existants de ces modules passent sans modification de leur logique ; l'audit RBAC des écrans conservés donne 0 promesse et 0 commande cachée.

**P0-7. Cohabitation avec SIGH-CNT**
- Identifiants d'installation distincts : `applicationId` Android, nom et GUID de l'installateur Windows (`apps/poste/installer`), dossier de données du poste, nom des bases SQLite, préfixes de stockage.
- *Critère* : SIGH-CNT et SIGH-CB installés sur la même machine démarrent chacun sur leurs propres données.

### P1 : à livrer rapidement ensuite

**P1-1. Design system Baguidi**
- Remplacer les valeurs de `JetonsSigh` / `JetonsShell` par la palette Baguidi (primaire, secondaire, fonds). Garder la sémantique vert / orange / rouge, que les écrans utilisent pour l'état des stocks.
- *Critères* : contraste WCAG AA sur texte principal et boutons ; aucune couleur écrite en dur hors jetons (contrôle par recherche).

**P1-2. Écran de connexion Baguidi**
- Refaire `acc_gabarit.dart` / `acc_ecrans.dart` : logo, nom, centre de médecine du travail, ville, texte de présentation, liste des spécialités, devise, mention légale en pied.
- *Critère* : capture validée par la Direction de Baguidi.

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
| Mise en service (indicateur tardif) | stock et paie tenus dans SIGH-CB pendant un mois complet sans retour au papier | Direction Baguidi, 1 mois après installation |

## 9. Questions ouvertes

| # | Question | Pour | Bloquant ? |
|---|---|---|---|
| Q1 | **M9 Assurances & créances** : à garder ou à fermer ? Il lit les factures de M8, qui sera fermé. La description de Baguidi ne le cite pas | Direction Baguidi | **Oui** (P0-4) |
| Q2 | État par défaut de MECeF, NS 132 et NS 131 à l'installation : ouvert ou fermé ? | Direction Baguidi | **Oui** (P0-5) |
| Q3 | Les rôles cliniques (médecin, sage-femme, biologiste, caissier…) : à archiver ou à garder ? | Direction Baguidi | Non |
| Q4 | Registres vides à l'installation, ou jeu de démonstration **fictif** aux couleurs de Baguidi pour la formation ? | Direction Baguidi | **Oui** (P0-3) |
| Q5 | **Sorties de pharmacie sans caisse ni dossier patient** : dans SIGH-CNT, une délivrance naît d'une ordonnance passée en caisse (RG-03, justificatif = n° d'ordonnance). M1 et M8 fermés, quel justificatif ? Bon de sortie interne par service ? Consommation de la visite d'entreprise ? | Direction Baguidi + ingénierie | **Oui** (P0-6, sinon la pharmacie ne peut rien sortir) |
| Q6 | Champs d'identité manquants : sigle (remplace « CNT »), nom court, BP, téléphones, e-mail, n° d'autorisation d'ouverture, formule de politesse des factures | Direction Baguidi | **Oui** (P0-2) |
| Q7 | Fichier source du logo (vectoriel de préférence) et charte graphique (couleurs en hexadécimal, police) | Direction Baguidi | Oui pour P1-1/P1-2, non pour P0 |
| Q8 | Historique git : importer avec l'historique de SIGH-CNT (report de correctifs facilité, mais l'historique contient des données de Nassiera Too et un mot de passe commis le 17/10/2026) ou en **instantané** (recommandé) ? | Ingénierie + Direction CNT | **Oui** (P0-1) |
| Q9 | La Direction de Nassiera Too a-t-elle autorisé la réutilisation du code pour une autre clinique ? | Direction CNT, juridique | **Oui** (avant tout import) |
| Q10 | Les 7 spécialités non nommées (« + 7 spécialités ») : liste complète pour l'écran de connexion ? | Direction Baguidi | Non |
| Q11 | Le relais web (cPanel) : nouvel hébergement et nouveau domaine pour Baguidi, ou relais partagé ? Un relais partagé mêlerait les journaux de deux cliniques | Ingénierie + Direction Baguidi | Oui avant mise en service, non pour le développement |

## 10. Calendrier et phasage

Aucune échéance n'a été communiquée. Phasage proposé, chaque phase se termine sur une CI verte :

| Phase | Contenu | Dépend de |
|---|---|---|
| **0. Décisions** | Q1, Q2, Q4, Q5, Q6, Q8, Q9 | Direction Baguidi, Direction CNT |
| **1. Import** | P0-1 : base importée, CI verte **sans aucun changement** | Q8, Q9 |
| **2. Identité et données** | P0-2, P0-3, P0-7, script `controle-identite` | Q4, Q6 |
| **3. Périmètre** | P0-4, P0-5, P0-6, solution de sortie de stock (Q5) | Q1, Q2, Q5 |
| **4. Charte graphique** | P1-1, P1-2, P1-3 | Q7 |
| **5. Recette** | pièces imprimées validées, installation à blanc sur un poste Baguidi, P1-4 | phases 1 à 4 |

Règle de conduite : **une phase par lot de commits**, jamais l'identité et le périmètre dans le même commit. Un défaut se rattache ainsi à sa cause, et le report d'un correctif de SIGH-CNT reste lisible.
