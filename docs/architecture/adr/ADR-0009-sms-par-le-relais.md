# ADR-0009 : Les SMS partent par le relais, composés par la mère, effacés après envoi

| | |
|---|---|
| **Statut** | **proposé le 16/11/2026** (décision de principe de la Direction de Baguidi, `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md` § 8). Il **précise** ADR-0005 (relais opaque) et ADR-0007 (ce que le relais voit en clair). Le fournisseur de SMS, le plafond réel et la liste des mots interdits restent à arrêter. |
| **Date** | 16/11/2026 |
| **Décideurs** | Direction, ingénierie |
| **Lié à** | ADR-0005 (relais opaque, cPanel sans démon), ADR-0007 (flux en clair signé, schéma fermé), `apps/web/README.md`, `docs/guides/DEPLOIEMENT-CPANEL.md` |

## Contexte

La clinique veut prévenir ses patients par SMS (rappel de rendez-vous, vœux). Le poste mère est sur le réseau local, souvent sans accès direct à un fournisseur de SMS, et il ne doit jamais détenir les identifiants d'un fournisseur dans le dépôt ni dans la base des postes. Le relais en ligne est le seul composant joignable en permanence ; il est hébergé sur un cPanel mutualisé : **pas de démon, pas de file Redis, un `cron` chaque minute**.

Jusqu'ici le relais ne voyait en clair que des agrégats non nominatifs (ADR-0007). Un SMS, par nature, porte un **numéro de téléphone**, donnée personnelle. La question est donc : que voit le relais, combien de temps, et qu'est-ce qui garantit qu'aucun contenu médical ne sort par ce canal.

## Décision

1. **La mère compose, le relais transporte.** Le texte est composé sur le poste mère à partir d'un **modèle de message** (`modelesMessage`) ; le relais reçoit un SMS **déjà composé** : un numéro au format international (`+` et 8 à 15 chiffres) et un texte (320 caractères au plus). Il ne reçoit **jamais** le dossier, le nom du patient, son code, le motif, le diagnostic, ni l'occasion (le relais ne sait pas s'il transporte un rappel ou des vœux).
2. **Aucun contenu médical, contrôlé par la mère, deux fois.** Un rappel dit le jour, l'heure et la clinique. La composition **retire le nom** du patient (la variable `{{nom}}` n'est jamais remplacée dans un SMS : le relais ne doit pas voir un nom à côté d'un numéro) et **refuse** un texte qui contient un mot d'une liste de mots interdits (diagnostic, analyse, résultat, grossesse, VIH…) — refus nommé `SMS_CONTENU_MEDICAL`, avec le mot trouvé. La liste vit dans le domaine (`packages/domaine/lib/src/sms/sms.dart`), elle est **marquée « à valider par un médecin »** et s'affiche telle quelle à l'écran « Passerelle SMS ». Le poste contrôle avant de déposer ; le service de la mère recontrôle avant d'envoyer au relais. **Le relais ne contrôle pas le sens** (aucune règle métier au relais, ADR-0005) : il contrôle la **forme** (schéma fermé, longueurs, format du numéro).
3. **Dépôt signé, mêmes barrières que les indicateurs.** `POST /mere/sms` : secret de la mère (`x-mere`), **signature du corps** (`x-signature: sha256=<HMAC-SHA256 du corps exact, clé = RELAIS_SECRET_MERE>`), schéma fermé (`{"sms":{"id","numero","texte"}}`, tout champ en trop refusé, 422), corps borné (413). L'identifiant est tiré par la mère : un dépôt rejoué rend la même ligne (idempotent).
4. **Envoi par tâche planifiée, jamais par démon.** La commande `relais:sms-envoyer` est inscrite au planificateur Laravel (`routes/console.php`, chaque minute) ; sur cPanel, c'est le cron d'une minute `php artisan schedule:run`, déjà en place pour la surveillance, qui la déclenche. Aucune requête de la mère n'attend l'envoi.
5. **Effacement après envoi.** Dès qu'un SMS est accepté par le fournisseur, **le numéro et le texte sont effacés** de la ligne (`NULL`) ; il ne reste que l'identifiant, le statut, le nombre de tentatives, la longueur du texte et des horodatages. Même effacement après le **cinquième échec** (statut `echec`). Les lignes terminées sont purgées au-delà de `RELAIS_SMS_CONSERVATION_JOURS` (30 par défaut).
6. **Plafond quotidien.** `RELAIS_SMS_PLAFOND_JOUR` (100 par défaut) borne le nombre de SMS envoyés par jour (jour civil d'`Africa/Porto-Novo`). Un dépôt qui dépasserait le plafond du jour (envoyés + en attente) est refusé `429 plafond_atteint` : la mère le sait tout de suite, et un poste compromis ne peut pas transformer le relais en canon à SMS. La commande s'arrête aussi au plafond. Le plafond est **affiché** au poste (lu par `GET /mere/sms/etat`), il ne se règle pas depuis le poste.
7. **Cinq tentatives au plus.** Un échec du fournisseur remet le SMS en attente avec un délai croissant ; au cinquième, il passe `echec` et s'efface.
8. **Le fournisseur est un pilote, ses identifiants vivent dans le `.env` du relais seulement.** `RELAIS_SMS_PILOTE=journal` (défaut) n'envoie rien : il marque le SMS envoyé et journalise sa longueur — c'est le pilote de l'essai et du banc. `RELAIS_SMS_PILOTE=http` est un pilote HTTP **générique** dont l'adresse, la clé, l'en-tête et l'expéditeur viennent du `.env` (`RELAIS_SMS_HTTP_URL`, `RELAIS_SMS_HTTP_CLE`, `RELAIS_SMS_HTTP_ENTETE_CLE`, `RELAIS_SMS_EXPEDITEUR`) : **aucune API de fournisseur réel n'est écrite dans le dépôt**, aucun identifiant n'y figure. Un pilote propre à un fournisseur s'ajoutera derrière la même interface (`App\Relais\Sms\Pilote`) quand la clinique l'aura choisi.
9. **Journal technique sans contenu.** Le journal d'audit du relais (`relais_audit`) porte l'action (`sms_depose`, `sms_envoye`, `sms_echec`, `sms_refuse`), l'identifiant du SMS et un code ; **jamais le numéro, jamais le texte**. Les erreurs du fournisseur sont journalisées par leur code HTTP, pas par leur corps.
10. **La mère suit le statut.** `POST /mere/sms/statuts` (signé) rend, pour une liste d'identifiants, le statut, les tentatives et les horodatages. La mère tient son propre journal des envois (numéro masqué, longueur, auteur, statut) pour l'écran « Journal des envois SMS ».
11. **Désactivé par défaut côté poste.** L'interrupteur « Passerelle SMS » vit en base de la mère, **fermé par défaut** : un flux de numéros personnels hors du poste est un acte que la clinique ouvre en connaissance de cause. Régler et « Tester l'envoi » sont un **geste réservé** de la matrice (`reglage_sms`, origine proposée : l'administrateur et la DAF, à valider) ; aucun rôle n'est écrit dans le code.

## Ce que le relais voit, et ce qu'il ne voit jamais

| Voit (le temps de l'envoi) | Ne voit jamais |
|---|---|
| un numéro au format international | le nom du patient, son code, son dossier |
| un texte déjà composé (320 caractères au plus) | le motif, le diagnostic, un résultat, une ordonnance |
| un identifiant tiré par la mère | l'occasion (rappel, vœux…), le modèle, l'auteur |
| après envoi : statut, tentatives, longueur, horodatages | après envoi : ni le numéro ni le texte |

## Options écartées

- **Envoyer depuis le poste mère directement** : la mère n'a pas toujours d'accès sortant, et ses identifiants de fournisseur vivraient dans la base des postes, synchronisée.
- **Chiffrer le SMS de bout en bout jusqu'au relais** : sans effet, le relais doit remettre au fournisseur un numéro et un texte en clair. L'effacement après envoi borne l'exposition.
- **Un démon qui vide la file en continu** : impossible sur cPanel mutualisé ; le cron d'une minute suffit à un rappel.
- **Contrôler les mots interdits au relais** : ce serait une règle métier au relais (ADR-0005), et la liste doit vivre là où un médecin la valide.
- **Garder le texte pour preuve au relais** : la preuve de l'envoi est le statut ; le texte reste au journal de la mère, dans la clinique.

## Conséquences

- **Un deuxième flux en clair** quitte la mère, avec une donnée personnelle (le numéro) : il est borné par un interrupteur fermé par défaut, un geste réservé, un schéma fermé, une signature, un plafond quotidien et l'effacement après envoi.
- **Deux exemplaires du contrat** : le relais Laravel (`App\Http\Controllers\SmsController`, `App\Relais\Sms\*`) et le relais de référence du banc (`packages/sync/banc/relais-sms.js`) ; le scénario `SMS1` du banc éprouve le contrat (dépôt signé, refus, plafond, effacement, cinq tentatives).
- **À valider** : la liste des mots interdits (par un médecin), le plafond réel, le fournisseur et son pilote, l'origine du geste `reglage_sms`, le consentement du patient au SMS (case au dossier, non faite à ce jour).
- **Non vérifié ici** : envoi réel par un fournisseur, comportement sur l'hébergement cPanel réel, PostgreSQL de production (les tests PHP tournent sur SQLite en mémoire et ne sont pas exécutés dans cet environnement faute de `vendor/`).
