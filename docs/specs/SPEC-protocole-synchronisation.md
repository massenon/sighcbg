# Spécification du protocole de synchronisation (extrait)

> Ce fichier ne contient que le §13 bis ; la spécification complète (§1 à §13) n'est pas dans cette branche alors que les README la citent (voir ECARTS-MAQUETTE E2550 point 5). À fusionner dans la spécification d'origine.

### 13 bis. L'état de synchronisation publié par la mère (lot RLS-SYNC, porté de la clinique sœur)

Le panneau en ligne a un écran « Synchronisation » (mère, fileuls, mobiles). Les **fileuls ne parlent pas au relais** : c'est la **mère** qui publie leur état, dans ses indicateurs de battement (`POST /mere/indicateurs`, tableau `fileuls`), en **compteurs et horodatages seulement**, au plus toutes les 2 secondes de calcul :

| Clé | Type | Sens |
|---|---|---|
| `poste` | texte, 40 caractères au plus : lettres, chiffres, espace, `.`, `:`, `-`, `_` | l'étiquette de l'appairage ; jamais un identifiant de dossier ni une phrase |
| `dernierContact` | entier (ms) ou `null` | dernière fois que la mère a entendu le poste ; `null` : jamais vu |
| `retardJournal` | entier positif ou nul, ou `null` | opérations de la mère que le poste n'a pas encore reprises ; `null` : non calculable (jamais zéro) |
| `conflitsOuverts` | entier positif ou nul | conflits ouverts concernant ce poste |
| `demandesImportEnAttente` | entier positif ou nul | demandes d'import déposées par ce poste et pas encore tranchées par la mère |

La clé `protocole` (entier de 1 à 9999) est acceptée quand la mère publie une version du protocole ; aucune n'est publiée aujourd'hui. **Une seule liste blanche, trois contrôles** : la mère OMET ce qui en sort (`synchroAssainirFileuls`), le relais REFUSE en nommant (422 `indicateur_cle_inconnue`, `indicateur_valeur_invalide` ou `indicateur_forme_invalide`, avec le motif, le geste et le chemin, jamais la valeur recopiée) et n'enregistre rien d'un envoi refusé, l'autorisation de la mère précédant la validation. Vecteurs communs à Dart, Node et PHP : `packages/domaine/test/vecteurs/synchro_fileuls.json`. Le relais tient un historique à part (durée et seuils réglés en base), note la relève des mobiles (heure et plus haut rang remis) et lève trois alertes (fileul silencieux, mobile silencieux, boîte qui grossit) sans jamais juger un contenu. Un téléphone n'en lit rien. Scénarios du banc : `RELSYNC1` (protocole, refus, opacité, téléphone) et `RELSYNC2` (relais Laravel : historique, purge à la durée réglée, relève). Écarts et hypothèses : `docs/architecture/ECARTS-MAQUETTE.md` E2549 à E2553.
