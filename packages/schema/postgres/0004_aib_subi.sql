-- =============================================================================
-- SIGH-CBG — AIB subi sur facture fournisseur et comptes paramétrables de l'AIB (position de la Direction, 09/11/2026)
-- Rubrique « comptes » de la collection « parametresAib » : les quatre comptes de l'AIB (subi, retenu ou collecté, imputation, fournisseur), versionnés par date
-- d'effet comme les autres rubriques ; marqués « à confirmer par l'expert-comptable » tant que le décideur n'est pas écrit. Les moteurs de pièces lisent la
-- version en vigueur à la date de la pièce. Migration à part : 0001 est engendrée, 0003 est déjà passée.
-- Les factures fournisseurs portent, dans `extra` (jsonb, comme la retenue d'AIB déjà portée), l'AIB FACTURÉ (`aibFacture` : montant, taux, base hors taxes)
-- et l'AIB SUBI constaté (`aibSubi` : montant, taux, date, comptes, `ecritureIds`) : aucune colonne à ajouter, la facture n'est jamais réécrite.
-- =============================================================================
ALTER TABLE "cfg"."parametres_aib" ADD COLUMN IF NOT EXISTS "compte_aib_subi" text;
ALTER TABLE "cfg"."parametres_aib" ADD COLUMN IF NOT EXISTS "compte_aib_retenu" text;
ALTER TABLE "cfg"."parametres_aib" ADD COLUMN IF NOT EXISTS "compte_imputation" text;
ALTER TABLE "cfg"."parametres_aib" ADD COLUMN IF NOT EXISTS "compte_fournisseur" text;
ALTER TABLE "cfg"."parametres_aib" ADD COLUMN IF NOT EXISTS "a_confirmer_expert_comptable" boolean;
COMMENT ON TABLE "cfg"."parametres_aib" IS 'Collection « parametresAib » — Configuration (versions datées : base de la retenue, branchement IFU, revue du barème, comptes de l''AIB)';
