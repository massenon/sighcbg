# Déployer le relais en production (cPanel mutualisé)

Le relais est opaque : il stocke des enveloppes chiffrées et des indicateurs sans nom de patient. Contraintes de l'hébergeur : PHP 8.2+, PostgreSQL, `cron` chaque minute, pas de SSH ni de Redis.

## Sur le poste de développement

```bash
cd apps/web
composer install --no-dev --optimize-autoloader
```

Téléverser le dossier `apps/web` sur l'hébergeur. La racine web du domaine doit pointer sur `public/`.

## Sur le serveur

1. Créer la base PostgreSQL et son utilisateur dans cPanel.
2. Copier `apps/web/production.env.exemple` en `.env` à la racine du dossier téléversé (jamais dans le dépôt). Renseigner `APP_URL`, `APP_KEY`, `DB_*` et `RELAIS_SECRET_MERE` (texte long et aléatoire).
3. Migrer la base et créer le compte du panneau (terminal cPanel ou tâche ponctuelle) :
   ```bash
   php artisan migrate --force
   php artisan relais:superadmin direction@clinique.bj --mot-de-passe='douze-caracteres-minimum'
   ```
4. Ajouter la tâche cron chaque minute : `php /chemin/vers/apps/web/artisan schedule:run`. Les files de tâches (pilote `database`) se vident par `php /chemin/vers/apps/web/artisan queue:work --stop-when-empty`, lancé aussi par cron.

## Côté poste mère

Écran « Activer la mère » : adresse du relais, secret de la mère (même texte que `RELAIS_SECRET_MERE`) et clé de clinique.

## Mise en production des données

Voir `docs/baguidi/PRODUCTION-VIDER-LE-JEU.md` : le jeu de démonstration s'archive (RG-14) depuis Paramètres système, onglet « Jeux de test », avec la bascule de réinitialisation ouverte puis refermée. Une sauvegarde chiffrée précède toujours le geste.
