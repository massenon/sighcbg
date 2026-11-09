<div align="center">

<img src="apps/poste/assets/img/logo.png" alt="Clinique Baguidi « L'As du Cœur »" width="130">

# SIGH-CBG

**Système Intégré de Gestion Hospitalière**<br>
Clinique Baguidi « L'As du Cœur » · Centre de médecine du travail et de médecine générale · Parakou, Bénin

*Votre bien-être est notre raison d'être.*

![Flutter](https://img.shields.io/badge/Poste%20et%20mobile-Flutter-1565C0?style=flat-square)
![Laravel](https://img.shields.io/badge/Relais%20web-Laravel%2012-D32F2F?style=flat-square)
![Hors ligne](https://img.shields.io/badge/Conception-hors%20ligne%20d'abord-212121?style=flat-square)
![Statut](https://img.shields.io/badge/Statut-en%20construction-F59E0B?style=flat-square)
![Dépôt](https://img.shields.io/badge/Dépôt-privé-212121?style=flat-square)

</div>

---

## Aperçu

SIGH-CBG remplace un parc d'outils cloisonnés (stocks, caisse, dossiers, comptabilité, paie, papier) par **un seul logiciel** qui suit un acte de bout en bout : le patient est reçu, consulté, prescrit, facturé, encaissé, puis l'écriture comptable, la sortie de stock et la paie qui en découlent se font d'elles-mêmes.

Il est conçu pour **continuer à travailler sans connexion** : chaque poste est autonome, les données se rejoignent ensuite par synchronisation.

Le logiciel est une **réplique adaptée** du logiciel SIGH-CNT du même éditeur (identité, charte, périmètre et jeu de démonstration propres à Baguidi). L'architecture et les règles de gestion sont conservées, l'identité et les données ne le sont pas.

## Ce que couvre le logiciel

| Domaine | Modules |
|---|---|
| **Accueil et soins** | M1 Patients et dossier médical · M2 Rendez-vous, visites, consultations, imagerie · M3 Hospitalisation, bloc, observation · M4 Maternité, naissances, décès · M5 Laboratoire et banque de sang |
| **Logistique** | M6 Pharmacie et stocks (gros, détail, urgence, lots FEFO, inventaires) · M7 Achats, besoins, commandes, livraisons, factures fournisseurs |
| **Financier** | M8 Facturation, caisse, avoirs · MECeF (facture normalisée, activable) · M9 Assurances et créances · M12 Comptabilité SYSCOHADA, états financiers, échéances fiscales, barème AIB |
| **Ressources humaines** | M10 Personnel, planning, évaluations (NS 131, activable) · M11 Paie, cotisations, primes (NS 132, activable) |
| **Administration et système** | M13 Courriers, ambulance, qualité · M14 Rôles et permissions, audit, sauvegardes · Configuration, GED, rapports et états officiels · Tableaux de bord et pilotage |

Un module qui n'est pas exercé se ferme depuis *Paramètres système* : il disparaît du menu, de la recherche et de ses adresses, sans rien supprimer.

**Quatorze spécialités** sont présentées par la clinique : médecine du travail, santé publique, gynécologie, chirurgie, urologie, rhumatologie, ophtalmologie, orthophonie, endocrinologie, pédiatrie, neurologie, cardiologie, kinésithérapie, imagerie. Gynécologie, chirurgie et imagerie reposent déjà sur des modules existants ; les autres sont en cours de spécification.

## Architecture

```text
   ┌────────────┐  ┌────────────┐          ┌─────────────────┐
   │ Poste      │  │ Poste      │          │ Mobile          │
   │ « fileul » │  │ « mère »   │◄────────►│ soignant /      │
   │ (Flutter)  │  │ (Flutter)  │          │ réception       │
   └─────┬──────┘  └─────┬──────┘          └────────┬────────┘
         │  journal d'opérations, chiffré           │
         └──────────────►  Relais web (Laravel)  ◄──┘
                           opaque, ne lit pas les données
```

| Dossier | Rôle |
|---|---|
| `apps/poste` | Application de bureau Flutter : modes **fileul** (poste autonome) et **mère** (poste de référence de la clinique) |
| `apps/mobile` | Application Flutter minimale, uniquement par le relais |
| `apps/web` | Relais en ligne (Laravel 12) et panneau d'administration |
| `packages/domaine` | Règles de gestion en Dart pur : formats, facturation, paie, comptabilité, droits |
| `packages/sync`, `packages/sync_dart` | Protocole de synchronisation et son banc d'essai |
| `packages/rbac`, `packages/referentiels`, `packages/schema` | Matrice des droits, référentiels, schéma des données |
| `apps/poste/tool` | Générateur déterministe du jeu de démonstration |
| `tools/baguidi` | Contrôles scriptés (identité, pseudonymisation, sigle) |

## Règles de gestion, en bref

Chaque module les applique : identifiant patient `CBG/n/AA` unique et immuable (RG-01) · médicaments au prix d'achat, sans marge (RG-02) · aucune sortie de stock sans justificatif, jamais de stock négatif (RG-03) · commande validée par la Direction (RG-04) · FEFO (RG-05) · prise en charge assurance seulement si la carte est valide à la date (RG-09) · **toute écriture comptable équilibrée** (RG-10) · journal de toute action, aucune action anonyme (RG-12) · cloisonnement des droits (RG-13) · **archivage, jamais de suppression** (RG-14).

## Identité visuelle

| | |
|---|---|
| Rouge cœur (actions) | `#D32F2F` |
| Bleu santé (marque) | `#1565C0` |
| Anthracite (barre et ruban) | `#212121` |
| Polices | Montserrat (titres) · Inter (texte) · Dancing Script (devise) |

L'en-tête de chaque pièce imprimée suit un gabarit en trois zones (logo et devise, dénomination, coordonnées) sous un double filet rouge et bleu.

## Démarrer

Prérequis : Flutter 3.47 (Dart 3.13), Node 22.

```bash
cd packages/domaine && dart pub get && dart test       # règles de gestion
cd apps/poste && flutter pub get && flutter test       # poste (long : environ 25 minutes)
node packages/sync/banc/run.js                         # banc de synchronisation
```

Contrôles d'identité, qui doivent tous répondre 0 :

```bash
node tools/baguidi/controle-identite.mjs
node tools/baguidi/pseudonymiser.mjs --verifier
node tools/baguidi/cnt-vers-cbg.mjs --verifier
node tools/baguidi/demo-liasse.mjs --verifier
node tools/baguidi/substitution-identite.mjs --verifier
```

## Jeu de démonstration

Le jeu livré (`apps/poste/assets/donnees/jeu`) est **entièrement fictif** et marqué comme tel : patients, entreprises, fournisseurs, praticiens vacataires, numéros d'ambulance (non composables), liasse fiscale de démonstration. Seuls les neuf comptes de la clinique sont réels, sans mot de passe dans le dépôt. Il se régénère de façon reproductible :

```bash
cd apps/poste && flutter test tool/generer_jeu_baguidi.dart
```

**En production, il se vide et les vraies données le remplacent** : voir `docs/baguidi/PRODUCTION-VIDER-LE-JEU.md`.

## Documentation

| Document | Contenu |
|---|---|
| `docs/prd/PRD-replique-baguidi.md` | Spécification de la réplique, décisions de la Direction, questions ouvertes |
| `docs/prd/JEU-DEMONSTRATION-BAGUIDI.md` | Jeu de démonstration (version 2, validée) |
| `docs/baguidi/REPRISE.md` | État du chantier, reste à faire, pièges, règles d'envoi |
| `docs/audit/INVENTAIRE-AUDITS-PAYES.md` | Constats déjà établis sur le code d'origine |
| `docs/architecture/` | Architecture cible, décisions (ADR), fiches de parité |

> Les documents `docs/prd`, `docs/baguidi/REPRISE.md` et `docs/audit` se trouvent sur la branche `claude/eager-archimedes-e8whyx` ; le code, sur `provisoire/baguidi-lot1`.

## Confidentialité

Dépôt privé, logiciel propriétaire, tous droits réservés. Aucune donnée réelle de patient ne doit y figurer.

<div align="center"><sub>Clinique Baguidi « L'As du Cœur » · 02 BP : 105 Parakou (Rép. du Bénin)</sub></div>
