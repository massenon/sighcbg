# Prototype HTML — SIGH-CBG

Prototype d'interface du **Système Intégré de Gestion Hospitalière** de la
**CLINIQUE BAGUIDI « L'AS DE CŒUR »** (Centre de médecine du travail – médecine
générale, Quartier Zongo II, 02 BP 105, Parakou, République du Bénin).

Il est la **dérivation** du prototype SIGH-CNT (CLINIQUE NASSIERA TOO),
réalisée sur décision écrite de la Direction du 02/09/2026 : identité et charte
graphique BAGUIDI, seeders nettoyés, modules non exploités désactivés — rien
n'a été redéveloppé, rien n'a été supprimé.

## Ouvrir le prototype

Double-cliquer sur **`index.html`**. Aucune installation, aucun serveur et
aucune connexion Internet ne sont nécessaires : feuille de style, polices
(Inter, Montserrat, Dancing Script), icônes, logo et bibliothèque de graphiques
sont hébergés dans le dossier du projet.

> Ouvert par double-clic (protocole `file://`), Chrome refuse selon sa
> configuration l'accès au stockage local. Le prototype bascule alors sur un
> stockage en mémoire : tout reste fonctionnel, mais les saisies ne survivent
> pas au rechargement. Pour les conserver, servir le dossier :
>
> ```
> npx serve .        (ou)      python -m http.server 8080
> ```

Le prototype s'ouvre sur l'écran de connexion. Le sélecteur **« Profil de
connexion »** propose les huit comptes de test arrêtés par la Direction
(m-001 à m-008@baguidi-clinique.bj) et le compte d'administration système.

## Périmètre actuel (Direction, 02/09/2026)

**Modules actifs** : gestion des stocks et inventaire de la pharmacie (M6),
achats et expressions de besoins — y compris les besoins du laboratoire et des
services (M7), ressources humaines (M10), paie & primes (M11), comptabilité
SYSCOHADA (M12), administration (M13), sécurité (M14), pilotage, tableaux de
bord (dont le croisé dynamique), configuration, GED et rapports.

**Modules désactivés** (patients, consultations, hospitalisation, maternité,
laboratoire clinique, caisse, assurances, MECeF, barème d'évaluation NS 131) :
ils sont fermés par « Activité des modules » (`cfg-modules`), pour tous les
rôles — rien n'est supprimé, la Direction peut les rouvrir sur décision écrite.

Les deux chaînes transactionnelles de référence traversent le prototype de
bout en bout :

1. expression de besoin → validation Direction (RG-04) → bon de commande →
   réception → mouvement de stock / CUMP → facture fournisseur → écriture
   comptable ;
2. fiche RH → planning → primes → bulletin de paie → validation Direction.

## Données

- Les **8 agents** et leurs comptes viennent d'Instructions.txt — exactement.
- L'inventaire (184 articles), le catalogue des médicaments, le plan comptable
  SYSCOHADA (93 comptes), la baseline 2025, le calendrier fiscal, les
  fournisseurs et la grille des primes sont un **jeu de démonstration hérité**
  du prototype d'origine, gardé sur décision écrite et **marqué à remplacer**
  par les données réelles BAGUIDI.
- **RCCM, forme juridique, autorisation d'ouverture, grille salariale, note de
  service des primes et seuils d'alerte n'ont pas été fournis** : les champs
  restent vides et les écrans le disent — aucune donnée officielle ne
  s'invente. L'écran « Validations en attente » (`adm-validations`) tient la
  liste de ce qui attend la Direction.

## Se déplacer dans l'application

La navigation est un **méga-menu horizontal en ruban** : une rangée d'onglets
par domaine fonctionnel, et sous elle un panneau déployant les modules du
domaine, une rangée par module, chaque écran en pastille avec son icône. Le
panneau se replie de lui-même au défilement. Quatre raccourcis permanents —
Stocks, Achats, RH, Comptabilité — restent visibles menu replié. La barre
supérieure réunit la recherche globale (`Ctrl K`), les actions rapides, le
plein écran, les notifications et le profil.

## Vérifier

```bash
npm install
npm run verify      # lint + build + contrôle des 282 pages + 13 scénarios fonctionnels
npm run audit-rbac  # 0 promesse, 0 lecture non dite attendus
```

Le détail des mécanismes, des pièges du build et de la doctrine héritée est
dans `CLAUDE.md`.
