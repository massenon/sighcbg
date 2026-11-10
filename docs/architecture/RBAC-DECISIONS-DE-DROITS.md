# Les droits ne sont jamais figés (Direction de Baguidi, 10/11/2026)

## Ce qui est vrai, et comment on le prouve

| Exigence | État trouvé | Ce qui a été fait | Preuve |
|---|---|---|---|
| (a) `rbac` et `modulesActifs` diffusés de la mère aux fileuls | **Déjà vrai** : les deux sont dans `cfbEssentielles`, donc famille R (la mère seule écrit), publiés par `PublicateurConfiguration`, repris par `ApplicateurConfiguration` (garde « réglé sur la mère » sur le fileul). `rolesBase` (la graine des rôles) n'est pas diffusé : il voyage avec le logiciel. | Un fileul **habilité** décidait déjà de rien : `m14-roles` était en lecture seule. Il dépose maintenant une **décision** (`decisionsDroits`, famille A, pont d'activité) ; la mère la juge, l'applique à `rbac`, la diffuse. | banc `RB1` (mère + 2 fileuls en processus) ; `droits_decisions_test` (mère réelle + 2 moteurs de fileul réels) |
| (b) application à chaud | **Déjà vrai pour le ruban et les commandes** (la coque écoute `rbac`). **Faux** pour l'écran ouvert dont le droit de *voir* est retiré (il restait affiché) et pour le **mode pair** (matrice engendrée lue une fois). | La coque ferme l'écran dont le droit est retiré (accès journalisé, retour à l'accueil du rôle, session gardée). Le mode pair du poste et de la mère lit `MatriceVive` / `ConfigMere.droitsPair` à chaque évaluation. | `droits_a_chaud_fileul_test`, `droits_diffusion_test` (sync_dart) |
| (c) modifications concurrentes | **Aucune règle** : l'écran réécrivait la fiche entière. | `decisions_droits.dart` : une décision ne porte que les clés qu'elle change ; la plus récente par horodatage de décision l'emporte **clé par clé** (identifiant à égalité, même fiche quel que soit l'ordre d'arrivée) ; l'ancienne est **écartée et nommée** ; l'écrasement d'une valeur non vue est marqué **concurrent** avec la décision remplacée ; journal (RG-12) : ancien et nouveau droit, auteur, motif. | `decisions_droits_test` (permutations), `droits_decisions_test` |
| (d) aucune matrice figée | La graine `rbac.json` est lue par `superposerDroits` à chaque calcul ; seul `cfaNavigation()` mémorise la graine (manifeste), les droits passent par `aChaud`. | `MatriceVive` : calcul mémoïsé, mémoïsation invalidée à toute écriture de `rbac` / `modulesActifs` / `specialites`. | `droits_decisions_test` (« MatriceVive ») |
| (e) l'écran le dit | — | Note en tête de « Rôles et permissions » : s'applique à tous les postes appairés, avec leur nombre quand le poste le sait (`postesClinique`), sinon « ce poste ne connaît pas leur nombre ». Motif obligatoire. « Revenir au défaut d'origine » par rôle. Onglet « Décisions de droits ». | `roles_responsables_test` |

## Limites assumées (rien n'est prétendu au-delà)

- **Mobiles** : la mère diffuse `rbac` à un mobile appairé comme à un fileul (le filtre de `GET /sync/pull` n'exclut que les hachés et les paramètres), mais l'application mobile n'évalue pas la matrice : elle applique la fonction fixée à l'appairage. Non modifié, non prouvé.
- **Relais** : opaque, il ne voit que des enveloppes ; aucun changement. Le relais Laravel n'a pas été retesté (aucun `composer install` dans ce dépôt).
- **Horloges** : « la plus récente » se lit à l'horodatage de décision du poste qui décide ; un poste dont l'horloge est très en retard voit sa décision écartée (nommée, jamais perdue).
- **`modulesActifs`** (activités fermées) reste décidé à la mère (écrans CFG) : seul `rbac` est posable par un fileul habilité.
- La mère juge sur **sa** matrice en force : l'auteur doit pouvoir *éditer* `m14-roles`. Le rôle d'auteur est celui de la session du poste appairé, que la mère croit.
