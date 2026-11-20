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

   Une seule ligne cron suffit : `schedule:run` déclenche **toutes** les tâches planifiées du relais (`routes/console.php`). Aucun démon n'est lancé.

   | Tâche planifiée | Fréquence | Rôle |
   |---|---|---|
   | `relais:surveiller` | chaque minute | marque le passage du cron (écran Hébergement), lève ou résout les alertes, purge l'historique des indicateurs |
   | `relais:sms-envoyer` | chaque minute (sans chevauchement) | envoie les SMS déposés par la mère (plafond du jour, cinq tentatives au plus), abandonne les périmés, puis **efface** leur numéro et leur texte ; purge les lignes terminées (ADR-0009) |
   | `relais:exporter` | chaque jour à 03:00 | export de la base du relais |
   | `relais:purger --oui` | chaque jour à 03:10 | purge du journal d'audit au-delà de la conservation (jamais des enveloppes) |

5. **SMS (facultatif, ADR-0009)** : tant que `RELAIS_SMS_PILOTE=journal` (défaut), **aucun SMS ne part réellement** : le pilote d'essai marque le SMS envoyé et n'appelle aucun fournisseur. Cela ne concerne que les SMS : le reste du relais (synchronisation, indicateurs, alertes par courriel, satisfaction) fonctionne normalement. Pour envoyer pour de bon, renseigner dans le `.env` **du serveur seulement** le fournisseur choisi par la clinique : `RELAIS_SMS_PILOTE=vonage` (`RELAIS_SMS_VONAGE_CLE`, `RELAIS_SMS_VONAGE_SECRET`), `twilio` (`RELAIS_SMS_TWILIO_SID`, `RELAIS_SMS_TWILIO_TOKEN`, puis `RELAIS_SMS_EXPEDITEUR` ou `RELAIS_SMS_TWILIO_SERVICE`) ou `http` (pilote générique : `RELAIS_SMS_HTTP_URL`, `RELAIS_SMS_HTTP_CLE` et, selon le fournisseur, `RELAIS_SMS_HTTP_ENTETE_CLE`, `RELAIS_SMS_HTTP_PREFIXE_CLE`, `RELAIS_SMS_EXPEDITEUR`, `RELAIS_SMS_HTTP_CHAMP_*`), puis le plafond `RELAIS_SMS_PLAFOND_JOUR` et la durée de validité `RELAIS_SMS_VALIDITE_HEURES` (24 par défaut : un SMS en attente depuis plus longtemps, retenu par le plafond du jour ou par une panne, est abandonné au lieu de partir périmé le lendemain). Ces identifiants ne vont jamais dans le dépôt. Un paramètre manquant est nommé (sans sa valeur) au panneau superadmin, section « SMS du relais », et à l'écran « Passerelle SMS » de la mère. Côté poste, la passerelle s'ouvre à l'écran « Passerelle SMS » de la mère (fermée par défaut) ; un SMS ne part que pour un patient qui a accepté les SMS à son dossier. Les envois automatiques (rappel la veille d'un rendez-vous, vœux d'anniversaire) sont des réglages datés de la mère, fermés par défaut.

## Côté poste mère

Écran « Activer la mère » : adresse du relais, secret de la mère (même texte que `RELAIS_SECRET_MERE`) et clé de clinique.

## Mise en production des données

Voir `docs/baguidi/PRODUCTION-VIDER-LE-JEU.md` : le jeu de démonstration s'archive (RG-14) depuis Paramètres système, onglet « Jeux de test », avec la bascule de réinitialisation ouverte puis refermée. Une sauvegarde chiffrée précède toujours le geste.
