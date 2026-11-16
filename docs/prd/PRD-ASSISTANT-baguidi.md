# PRD : l'assistant de la Clinique Baguidi (conversation locale, lecture seule, sans modèle de langage)

| | |
|---|---|
| **Statut** | Version 1 livrée (lots AST-0 et AST-1) ; suites en attente de la Direction |
| **Date** | 15/11/2026 |
| **Décision** | « Il faut l'implémenter » (Direction, 15/11/2026) |
| **Base** | Le PRD et la mesure AST-0 de la clinique sœur, adaptés ; pour chaque écart, la raison est aux écarts E2780 à E2797 de `docs/architecture/ECARTS-MAQUETTE.md` |
| **Mesure** | `docs/architecture/ASSISTANT-couverture-des-intentions.md` |

## 1. Problème
Un agent cherche aujourd'hui une réponse en ouvrant les écrans un à un : le stock d'un article, le reste à payer d'un patient, l'état d'une demande d'analyse, la validité d'une carte. L'assistant lui permet de poser la question en français. Il ne remplace aucun écran : il LIT ce que l'agent a déjà le droit de lire et dit d'où vient la réponse.

## 2. Décisions de la Direction (applicables telles quelles)
1. **Version 1 sans modèle de langage** : reconnaissance déterministe d'intentions. Un modèle local ne se décide que si la mesure le justifie ; rien n'est branché.
2. **25 intentions extensibles** : une intention est une question à source et droit déclarés (catalogue du code ; le branchement d'une collection de surcharges est un lot à part, E2787).
3. **Tous les utilisateurs authentifiés y ont accès, mais chaque réponse est filtrée par les droits de l'utilisateur** : matrice des droits, masquage par catégorie sensible, habilitations métier du résultat. Aucun nom de rôle dans le code.
4. **Lecture seule** : aucune écriture. La commande d'écriture est ABSENTE ; une demande d'écriture renvoie vers l'écran concerné.
5. **Jamais d'invention** : toute réponse cite sa source (écran et collection) et sait dire « non calculable », « pas de données », « vous n'avez pas le droit ». Aucun diagnostic, aucun conseil thérapeutique (refus nommé).
6. **Aucun accès réseau, aucun envoi hors de la clinique.**
7. **Conversations propres au poste et à l'agent**, non synchronisées, chiffrées au repos, conservées 30 jours (réglable en base, borné de 1 à 90) puis purgées. L'historique non conservé se dit « non calculable ».

## 3. Périmètre de la version 1
- 25 intentions livrées (20 calculables, 5 « petit lot » avec leur définition proposée dite dans la réponse) ; 2 candidates tracées NON DISPONIBLES (procédures, glossaire : aucune base de connaissances au dépôt).
- Un écran « Assistant » (`sup-assistant`, module SUP, universel, hors ruban, lien dans le menu profil) : question, réponse (titre, lignes, tableau), source cliquable vers un écran que l'agent voit, propositions quand la question est ambiguë, états chargement, vide et erreur, effacement de la conversation.
- Hors périmètre : impression de la conversation, voix, modèle de langage, catalogue administrable à l'écran, journal d'audit des questions (E2788), recherche dans les documents numérisés.

## 4. Règles
- **Droit** : une intention exige qu'au moins un de ses écrans de lecture soit visible ; chaque sous-source n'est lue que si son écran l'est ; les catégories sensibles masquent avec la mention réservée standard ; le résultat d'analyse suit `peutVoirResultat` et n'est jamais recopié.
- **Refus nommés** : `LECTURE_NON_AUTORISEE`, `INTENTION_INCONNUE`, `ECRITURE_ABSENTE`, `AVIS_MEDICAL_REFUSE`, `ENVOI_EXTERNE_REFUSE`, `INJONCTION_REFUSEE`, `PRECISION_REQUISE`, `QUESTION_AMBIGUE`, `NON_CALCULABLE_HISTORIQUE`, `PERIODE_FUTURE`, `AUCUN_RESULTAT`, `HOMONYMES`, `NON_CALCULABLE`, `ERREUR_INTERNE`. Les refus passent avant toute lecture.
- **Conversation** : un fichier chiffré par agent sous `assistant/` du dossier des données du poste ; purge à l'ouverture, à chaque question et au démarrage ; un fichier illisible n'est jamais écrasé.

## 5. Critères de réussite (vérifiés)
Zéro valeur inventée sur 130 questions ; magasin identique avant et après une conversation ; dix mutations rouges ; droits éprouvés sur la matrice réelle de plusieurs profils ; écran fermé à un rôle archivé ; conversation chiffrée, purgée, effaçable.

## 6. À décider par la Direction
Trace des questions qui nomment un patient (E2788) ; définitions proposées (E2790) ; branchement et administration du catalogue en base (E2787) ; compteur local sans texte pour décider d'un modèle (recommandation : non, E2792 et document de couverture, section 6) ; procédures et glossaire : qui rédige les fiches validées.
