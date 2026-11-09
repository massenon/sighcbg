# apps/web — relais en ligne et panneau superadmin (Laravel 12, cPanel mutualisé)

Rôle **opaque** (ADR-0005, spec §12–13) : le relais **ne lit jamais** un dossier. Il stocke des **enveloppes chiffrées de bout en bout**
(clé de clinique que seuls les appareils de la clinique détiennent), des **indicateurs sans nom de patient**, le battement de cœur de la mère,
et porte un **panneau superadmin minimal** (Blade + Livewire + Alpine) : appareils et jetons, journaux techniques, sauvegardes, restauration,
supervision. **Aucune règle de gestion, aucun écran métier.**

Contraintes d'hébergement (cPanel mutualisé) : PHP ≥ 8.2, PostgreSQL, `cron` chaque minute, **pas de SSH, pas de Redis, pas de WebSocket**.
`composer install --no-dev --optimize-autoloader` et la compilation des ressources se font **sur le poste de développement** ; on téléverse
le dossier (racine web = `public/`). Files de tâches en pilote `database`, `queue:work --stop-when-empty` par `cron`. `.env` hors dépôt.

Contrat du relais : `packages/sync/banc/relais.js` (implémentation de référence) et `docs/specs/SPEC-protocole-synchronisation.md` §12.
**État : squelette Laravel 12 sans code métier.**

## Tableau de bord de la clinique (ADR-0007, décision de la Direction du 09/11/2026)

Le relais reste opaque pour tout dossier. Il accepte en plus de la mère un **instantané d'indicateurs agrégés non nominatifs**, que le panneau superadmin montre en **lecture seule** (`/panneau/clinique`, menu « Tableau de bord de la clinique »).

- **Ce que le relais voit** : des nombres (patients actifs, consultations et visites du mois, factures émises, montants facturé / encaissé / reste dû en FCFA, articles sous seuil, lots proches de la péremption, échéances en retard, brouillons comptables, utilisateurs actifs, taux d'occupation des lits), la prochaine échéance fiscale (code d'obligation et date), l'identifiant technique et la dernière synchronisation de chaque poste, la version de l'application, l'état du jeu (démonstration ou production).
- **Ce que le relais ne voit toujours pas** : aucun dossier, aucun nom, code patient, téléphone, adresse, motif, diagnostic, fournisseur ni agent. Tout le contenu des dossiers reste dans des enveloppes chiffrées de bout en bout.
- **Route** `POST /mere/indicateurs-clinique` (distincte de `/mere/indicateurs`, qui garde ses trois compteurs de supervision). Trois barrières : le secret de la mère (`x-mere`), la **signature du corps** (`x-signature: sha256=<HMAC-SHA256 du corps exact, clé = RELAIS_SECRET_MERE>`), puis un **schéma fermé** (`App\Relais\IndicateursClinique`) : tout champ inattendu, toute chaîne libre, tout type inattendu est refusé (422), un corps de plus de 16 Ko aussi (413). Un instantané rejoué ou plus ancien que le dernier reçu est refusé (409). Les refus sont journalisés par leur code, jamais par leur contenu.
- **Conservation** : table `indicateurs_clinique` (migration `2026_11_09_000000`), les `RELAIS_INDICATEURS_CLINIQUE_MAX` derniers instantanés (500 par défaut), purge à chaque réception. Incluse dans l'export de sauvegarde du relais.
- **Réglages** (`.env`, voir `config/relais.php`) : `RELAIS_INDICATEURS_CLINIQUE_MAX`, `RELAIS_SEUIL_INDICATEURS_CLINIQUE_MS` (plancher de l'alerte « trop ancien », 1 h ; le seuil réel est le plus grand de ce plancher et de trois fois l'intervalle observé entre les deux derniers instantanés), `RELAIS_INDICATEURS_CLINIQUE_OCTETS_MAX`.
- **Côté poste** : l'interrupteur « publier les indicateurs au relais » est **fermé par défaut** ; il se règle, avec l'intervalle de publication, aux Paramètres du poste mère (écran « Indicateurs publiés »), qui affiche le contenu exact du dernier instantané envoyé. Tant qu'il est fermé, le tableau affiche « Jamais publié ».
- **Droits** : réservé aux comptes du panneau (tous superadmin, ADR-0005). **Lecture seule** : la page n'a aucune route d'écriture et aucune action ; un test le prouve.
- **Tests** : `php artisan test` (SQLite en mémoire) ; une copie de `.env.example` en `.env` avec `php artisan key:generate` est nécessaire à un poste neuf.

## Essai local sur un poste de développement (PostgreSQL)

Le relais tourne sur PostgreSQL, comme en production : un essai local sur SQLite ne prouverait rien sur ce que l'hébergeur servira.

1. Installer PostgreSQL 15 ou plus, puis créer la base et son utilisateur (`psql -U postgres`) :
   ```sql
   CREATE USER sigh_relais WITH PASSWORD 'choisir-un-mot-de-passe';
   CREATE DATABASE sigh_relais OWNER sigh_relais;
   ```
2. Dans `apps/web` : `composer install`, puis `Copy-Item .env.example .env` (PowerShell) ou `cp .env.example .env`. Renseigner `DB_PASSWORD` et `RELAIS_SECRET_MERE` (un texte long et aléatoire), puis `php artisan key:generate`.
3. `php artisan migrate`, puis `php artisan relais:superadmin votre@courriel.bj --mot-de-passe='…'` (12 caractères au moins) pour créer le compte du panneau, et `php artisan serve`.
4. Pour la PRODUCTION, partir de `production.env.exemple` (à copier en `.env` sur le serveur, jamais dans le dépôt).

Les tests (`php artisan test`) utilisent SQLite en mémoire : ils n'ont besoin d'aucune base installée.

Dans le poste, « Activer la mère » demande trois choses : l'adresse du relais (par exemple `sighcbg.exemple.bj`), le secret de la mère (le même texte que `RELAIS_SECRET_MERE` du `.env` du relais) et la clé de clinique (16 caractères au moins, à ranger sur papier : sans elle, rien de ce qui quitte le serveur ne peut être restauré).
