-- =============================================================================
-- SIGH-CBG — les fiches du barème de l'AIB ne portent plus de comptes (décision de la Direction, 09/11/2026 : « on va le corriger dans les Paramètres »)
-- Les champs documentaires `compteRetenu`, `compteSubi` et `compteImputation` doublaient la rubrique « comptes » de `cfg.parametres_aib`, SEULE source lue par les
-- moteurs de pièces (à la date de la pièce). Ils n'avaient pas de colonne propre : ils vivent dans `extra` (jsonb), d'où le retrait ci-dessous. Idempotent.
-- Les pièces déjà passées gardent les comptes d'origine : ils sont portés par la pièce (écriture, retenue, AIB subi), jamais lus au barème.
-- Migration à part : 0001 est engendrée, 0003 et 0004 sont déjà passées.
-- =============================================================================
UPDATE "cfg"."bareme_aib"
   SET "extra" = "extra" - 'compteRetenu' - 'compteSubi' - 'compteImputation'
 WHERE "extra" ?| ARRAY['compteRetenu', 'compteSubi', 'compteImputation'];
COMMENT ON TABLE "cfg"."bareme_aib" IS 'Collection « baremeAib » — Configuration (taux par situation, versionnés ; les comptes de l''AIB vivent aux paramètres, rubrique « comptes »)';
