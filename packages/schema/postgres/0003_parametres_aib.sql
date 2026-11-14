-- =============================================================================
-- SIGH-CBG — paramètres de l'AIB, versionnés (décisions D1, D4, D7 et D8 de la Direction, 09/11/2026)
-- Collection « parametresAib » du poste : une fiche par VERSION et par RUBRIQUE (base de la retenue d'AIB sur facture fournisseur, branchement de
-- l'IFU de l'acheteur sur le barème, revue du barème). Une version n'écrase jamais la précédente : valider AJOUTE une ligne à une date d'effet
-- postérieure. Écrite par la mère seule, reprise par les fileuls (famille R de la synchronisation). RG-14 : `statut = 'archive'`, jamais de DELETE.
-- Migration à part : 0001 est engendrée, on n'y écrit pas à la main.
-- =============================================================================
CREATE TABLE IF NOT EXISTS "cfg"."parametres_aib" (
  "id" text PRIMARY KEY,
  "statut" text,
  "rubrique" text,
  "version" integer,
  "date_effet" date,
  "decideur" text,
  "date_decision" date,
  "motif" text,
  "base" text,
  "longueur_ifu" integer,
  "situation_ifu_renseigne" text,
  "situation_ifu_absent" text,
  "taux_repli" integer,
  "choix" text,
  "version_bareme_id" text,
  "situation" text,
  "taux" integer,
  "graine" boolean,
  "a_valider" boolean,
  "saisi_par" text,
  "saisi_le" date,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."parametres_aib" IS 'Collection « parametresAib » — Configuration (versions datées : base de la retenue, branchement IFU, revue du barème)';
CREATE INDEX IF NOT EXISTS "ix_parametres_aib_rubrique" ON "cfg"."parametres_aib" ("rubrique", "date_effet");
CREATE INDEX IF NOT EXISTS "ix_parametres_aib_statut" ON "cfg"."parametres_aib" ("statut");

-- D7 : le montant HORS TAXES et la TVA (ligne séparée) des factures fournisseurs, facultatifs ; la base de la retenue d'AIB y lit le hors-taxes.
ALTER TABLE "m7"."factures_fournisseurs" ADD COLUMN IF NOT EXISTS "montant_ht" integer;
ALTER TABLE "m7"."factures_fournisseurs" ADD COLUMN IF NOT EXISTS "montant_tva" integer;
