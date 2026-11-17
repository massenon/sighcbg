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
- **Côté poste** : l'interrupteur « publier les indicateurs au relais » est **ouvert par défaut** (décision de la Direction du 10/11/2026, fermable aux Paramètres) ; il se règle, avec l'intervalle de publication, aux Paramètres du poste mère (écran « Indicateurs publiés »), qui affiche le contenu exact du dernier instantané envoyé. Tant qu'il est fermé, le tableau affiche « Jamais publié ».
- **Droits** : réservé aux comptes du panneau (tous superadmin, ADR-0005). **Lecture seule** : la page n'a aucune route d'écriture et aucune action ; un test le prouve.
- **Tests** : `php artisan test` (SQLite en mémoire) ; une copie de `.env.example` en `.env` avec `php artisan key:generate` est nécessaire à un poste neuf.

## Satisfaction en ligne (décision de la Direction du 16/11/2026, section 8)

Un patient répond au questionnaire de satisfaction **depuis chez lui**, par un lien ou un QR servi par le relais. C'est la **seule page publique** du relais ; elle ne porte aucun lien vers le panneau ni vers le logiciel, aucune ressource externe, aucun cookie (`Content-Security-Policy` fermée, `Referrer-Policy: no-referrer`, `Cache-Control: no-store`, `noindex`).

- **Chiffrée dans le navigateur** (`public/js/satisfaction.js`) avec la clé **publique** de la clinique : X25519 éphémère, HKDF-SHA256, AES-256-GCM, données authentifiées liées au lien (`sat1|kid|jeton`), clair bourré à 256 octets. La clé **privée** ne quitte jamais le poste mère : le relais stocke une enveloppe qu'il ne peut pas lire. Web Crypto X25519 si le navigateur le connaît, sinon une échelle de Montgomery en BigInt incluse dans le script (aucune dépendance réseau).
- **Aucun nom, aucun numéro de dossier, aucune question médicale** : un lien en ligne est toujours anonyme ; aucune adresse réseau n'est enregistrée avec une réponse, seul le **jour** de réception l'est.
- **Le lien porte un JETON** (24 caractères tirés au poste), daté et révocable, jamais l'identifiant de l'enquête ; le relais ne le garde que **haché**. Jeton inconnu, mal formé, expiré ou révoqué : **la même réponse neutre** (page, modèle, dépôt).
- **Le questionnaire naît du modèle** : la mère publie les champs engendrés par le générateur du domaine (le même que la saisie au guichet) ; une question ajoutée au modèle est republiée et paraît sur le lien. Le relais ne fait que **rendre** ces champs.
- **Routes publiques** (`routes/satisfaction.php`, chargées par `routes/relais.php`) : `GET /satisfaction/{jeton}` (page), `GET /satisfaction/{jeton}/modele` (JSON), `POST /satisfaction/{jeton}/reponse` (dépôt d'une enveloppe ; débit par adresse `RELAIS_SATISFACTION_DEBIT_DEPOT`, plafond par lien et par jour `RELAIS_SATISFACTION_PLAFOND_JOUR`, taille `RELAIS_SATISFACTION_ENVELOPPE_OCTETS_MAX`).
- **Routes de la mère, signées** (`x-mere` puis `x-signature: sha256=<HMAC-SHA256 du corps exact>`) : `POST /mere/satisfaction/publier` (lien, modèle, clé publique ; schéma FERMÉ `App\Relais\Satisfaction\Publication`), `revoquer` (la porte se ferme, les enveloppes déjà déposées restent à relever ; un lien révoqué ne se republie pas), `relever`, `acquitter` (les enveloppes acquittées sont **effacées** du relais). Un lien expiré ou révoqué depuis `RELAIS_SATISFACTION_CONSERVATION_JOURS` (30), sans enveloppe en attente, quitte le relais à la relève suivante.
- **Tables** : `satisfaction_liens`, `satisfaction_enveloppes` (migration `2026_11_16_120000`). Réglages : `config/satisfaction.php`.
- **Contrat de référence** : `packages/sync/banc/relais-satisfaction.js`, scénario `SAT1` du banc. **Tests** : `tests/Feature/SatisfactionEnLigneTest.php` (le chiffrement réel est produit par Node exécutant le script du navigateur) et `node --test tests/js/satisfaction.test.mjs`.
## SMS par le relais (ADR-0009, décision de la Direction du 16/11/2026)

Le relais transporte des SMS **déjà composés par la mère** : il ne voit qu'un numéro au format international et un texte (320 caractères au plus), le temps de l'envoi.

- **Ce que le relais ne voit jamais** : le dossier, le nom du patient (la mère ne remplace jamais `{{nom}}` dans un SMS), son code, le motif, le diagnostic, l'occasion du message. Le contrôle « aucun contenu médical » (liste de mots interdits, à valider par un médecin) est fait **par la mère**, deux fois ; le relais ne contrôle que la forme.
- **Routes** (`routes/relais-sms.php`, `App\Http\Controllers\SmsController`) : `POST /mere/sms` (dépôt `{"sms":{"id","numero","texte"}}`), `POST /mere/sms/statuts` (`{"ids":[…]}`), `GET /mere/sms/etat` (plafond, envoyés du jour, en attente, nom du pilote). Mêmes barrières que `/mere/indicateurs-clinique` : `x-mere`, puis `x-signature: sha256=<HMAC-SHA256 du corps exact, clé = RELAIS_SECRET_MERE>` (routes POST), puis un schéma fermé (422 `sms_invalide`), corps borné (413). Un dépôt rejoué (même `id`) rend la même ligne.
- **File** : table `sms_sortants` (migration `2026_11_16_000000`). Statuts `en_attente`, `envoye`, `echec`. **Le numéro et le texte sont effacés (NULL)** dès que le fournisseur accepte, ou au cinquième échec. Les lignes terminées sont purgées au-delà de `RELAIS_SMS_CONSERVATION_JOURS` (30). La table n'est **pas** incluse dans l'export de sauvegarde du relais (`App\Relais\Exporteur::TABLES`) : une file transitoire n'a rien à restaurer.
- **Envoi** : commande `php artisan relais:sms-envoyer`, inscrite au planificateur **chaque minute** (`routes/console.php`, `withoutOverlapping`) ; sur cPanel, le cron `schedule:run` la déclenche. **Aucun démon.**
- **Plafond quotidien** : `RELAIS_SMS_PLAFOND_JOUR` (100), jour civil d'`Africa/Porto-Novo`. Un dépôt qui le dépasserait (envoyés du jour + en attente) est refusé `429 plafond_atteint` ; l'envoi s'arrête aussi au plafond.
- **Tentatives** : cinq au plus (`RELAIS_SMS_TENTATIVES_MAX`, ramené à 5 s'il est plus grand), délais croissants (1 min, 5 min, 15 min, 1 h).
- **Pilote du fournisseur** (`App\Relais\Sms\Pilote`) : le choix est un RÉGLAGE du `.env`, `RELAIS_SMS_PILOTE` = `journal` (défaut : n'envoie **rien**, essai, banc) | `http` | `twilio` | `vonage`. Un autre nom est un **échec nommé** (`pilote_inconnu`), jamais un envoi simulé. Les identifiants vivent **uniquement** dans le `.env` (jamais en base, jamais dans le dépôt) ; la mère ne les voit pas.
  - `http` : pilote **générique**, JSON ; adresse, clé, en-tête, préfixe, expéditeur et noms des champs viennent de `RELAIS_SMS_HTTP_URL`, `_CLE`, `_ENTETE_CLE`, `_PREFIXE_CLE`, `RELAIS_SMS_EXPEDITEUR`, `RELAIS_SMS_HTTP_CHAMP_*`.
  - `twilio` : API Messages 2010-04-01 (`POST …/Accounts/{SID}/Messages.json`, auth Basic SID:jeton, corps `application/x-www-form-urlencoded` `To`/`From`/`Body`). Variables : `RELAIS_SMS_TWILIO_SID`, `RELAIS_SMS_TWILIO_TOKEN`, et l'expéditeur `RELAIS_SMS_EXPEDITEUR` (numéro Twilio) **ou** `RELAIS_SMS_TWILIO_SERVICE` (service de messagerie, prioritaire s'il est réglé).
  - `vonage` : **API SMS** (`POST /sms/json`, form-urlencoded `api_key`, `api_secret`, `from`, `to`, `text`), choisie plutôt que la Messages API : une clé et un secret suffisent, sans application ni clé privée JWT (adapté à un cPanel mutualisé). Vonage répond 200 même en refus : le succès se lit dans `messages[0].status` (« 0 »). Variables : `RELAIS_SMS_VONAGE_CLE`, `RELAIS_SMS_VONAGE_SECRET`, `RELAIS_SMS_EXPEDITEUR` (numéro ou nom alphanumérique admis au Bénin).
  - Les adresses des API (`RELAIS_SMS_TWILIO_URL_BASE`, `RELAIS_SMS_VONAGE_URL`) ont pour valeur par défaut l'API documentée du fournisseur ; on ne les change que pour un essai local.
  - **Paramètre manquant = échec nommé, file intacte** : si une variable requise est vide, le tour d'envoi ne touche à AUCUN SMS (ni tentative consommée, ni texte effacé), écrit `sms_pilote_non_configure` au journal (noms de variables, jamais de valeurs), et `relais:sms-envoyer` sort en erreur en listant ce qui manque. `GET /mere/sms/etat` rend `pilote` et `parametres_manquants` : l'écran « Passerelle SMS » de la mère les affiche.
  - Un refus rend un **code** (`twilio_http_401`, `vonage_statut_9`, `exception`), jamais le corps de la réponse du fournisseur. Plafond du jour, cinq tentatives, délais et conservation sont ceux de la file, communs à tous les pilotes.
- **Journal technique** : `relais_audit`, acteur `sms`, actions `sms_depose`, `sms_envoye`, `sms_echec`, `sms_refuse` ; le détail porte l'identifiant, un code et une longueur, **jamais un numéro ni un texte**.
- **Crochets du banc** (`RELAIS_BANC=true` seulement, 404 sinon) : `POST /banc/sms/tourner` (simule le cron, pilote `journal` ou `echec`, `avance_ms`), `GET /banc/sms/tout`.
- **Tests** : `tests/Feature/SmsRelaisTest.php` (`php artisan test --filter=SmsRelaisTest`), pilotes Twilio et Vonage éprouvés par `Http::fake` (aucun appel réseau réel).

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
