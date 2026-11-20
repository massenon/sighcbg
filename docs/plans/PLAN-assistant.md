# PLAN (Baguidi) : l'assistant, version 1

Source : `docs/prd/PRD-ASSISTANT-baguidi.md`, la mesure AST-0 de la clinique sœur et les décisions de la Direction du 15/11/2026. Écarts : `docs/architecture/ECARTS-MAQUETTE.md` E2780 à E2797.

## Étapes (chacune verte avant la suivante, un commit par étape)

### AST-0 : mesurer
1. `packages/domaine/lib/src/assistant/` : texte (normalisation, distance bornée), catalogue (27 lignes), reconnaissance, contexte et réponse. **Vérification** : `dart analyze lib`, `dart test test/assistant_mesure_test.dart`.
2. `tool/mesure_assistant.dart` : taux (réglage impair, contrôle pair, jeu aveugle), par intention, échecs, paramètres, temps, robustesse, droits, tableau et matrice engendrés. **Vérification** : `dart run tool/mesure_assistant.dart`.
3. `test/vecteurs/assistant_questions.json` (100), `assistant_questions_aveugle.json` (30), `assistant_profils.json`, `assistant_droits.json` (engendré). **Vérification** : la matrice engendrée est comparée à `rbac.json` à chaque test.
4. Document de couverture et recommandation chiffrée. **Vérification** : relecture, blocs engendrés à jour.

### AST-1 : livrer
5. Exécuteurs en lecture seule (fiches gelées), moteur (droit, alertes de période, sources visibles), conversation (purge, bornes). **Vérification** : `dart test test/assistant_moteur_test.dart test/assistant_conversation_test.dart`.
6. Paramètre `assistant.retentionJours` dans `definitionsParametres` (famille « Assistant »). **Vérification** : `dart test test/parametres_test.dart test/parametres_service_test.dart`.
7. Service de poste (`apps/poste/lib/core/service_assistant.dart`) : fichier chiffré par agent, purge, effacement, erreur. Écran `apps/poste/lib/modules/auth/ast_ecran.dart`, entrée de registre, lien du menu profil. **Vérification** : `flutter test test/assistant_ecran_test.dart`.
8. Manifeste et matrice : `sup-assistant` (module SUP, universel) dans les trois copies du manifeste, les trois de `rbac.json`, les trois `rolesBase.json`, `parite.json`, descriptions d'écran, fiche de parité, vecteur du plan du site. **Vérification** : `dart test test/assistant_ecran_droits_test.dart test/mob_droits_test.dart test/droits_a_chaud_test.dart test/acces_test.dart` ; `node --test packages/rbac/test/rbac.test.js` ; poste : `acces_test`, `roles_responsables_test`, `parite_ecrans_test` ; mobile : `droits_mobile_test`, `parite_mobile_test`.
9. Mutations (dix, réelles) ; écarts et documents. **Vérification** : chaque mutation rouge, fichier restauré.

## Non fait (suite possible)
- Collection `assistantIntentions` et écran d'administration du catalogue (incrément de schéma, famille de synchronisation) : E2787.
- Compteur local sans texte des questions non comprises, pour décider d'un modèle sur des chiffres réels.
- Trace d'audit des questions nommant un patient, si la Direction la veut (lève la règle « aucune écriture ») : E2788.
- Base de connaissances (procédures, glossaire) validée par la Direction : I26 et I27.
- Banc complet et `flutter test` complet : non lancés (autres agents sur les ports partagés).
