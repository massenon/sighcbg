-- =============================================================================
-- SIGH-CBG — organigramme imprimé (fiche documentaire paysage FCH_GRH_006), 10/11/2026
-- 1. « postes » porte désormais de quoi redessiner le graphe : code abrégé, niveau, centre, taille, type de lien, barre, coude, rang de légende. Le moteur de
--    dessin ne connaît aucune coordonnée : il les lit ici. Migration à part : 0001 est engendrée, on n'y écrit pas à la main.
-- 2. « fichesDocumentaires » : les paramètres d'une fiche (référence, date, version, titres, mention de propriété, grille). Une fiche par document ; écrite par la
--    mère, reprise par les fileuls (collection de configuration synchronisée). RG-14 : `statut = 'archive'`, jamais de DELETE.
-- =============================================================================
ALTER TABLE "cfg"."postes" ADD COLUMN IF NOT EXISTS "code" text;
ALTER TABLE "cfg"."postes" ADD COLUMN IF NOT EXISTS "code_legende" text;
ALTER TABLE "cfg"."postes" ADD COLUMN IF NOT EXISTS "ordre_legende" integer;
ALTER TABLE "cfg"."postes" ADD COLUMN IF NOT EXISTS "niveau" integer;
ALTER TABLE "cfg"."postes" ADD COLUMN IF NOT EXISTS "x" numeric;
ALTER TABLE "cfg"."postes" ADD COLUMN IF NOT EXISTS "y" numeric;
ALTER TABLE "cfg"."postes" ADD COLUMN IF NOT EXISTS "largeur" numeric;
ALTER TABLE "cfg"."postes" ADD COLUMN IF NOT EXISTS "hauteur" numeric;
ALTER TABLE "cfg"."postes" ADD COLUMN IF NOT EXISTS "lien" text;
ALTER TABLE "cfg"."postes" ADD COLUMN IF NOT EXISTS "barre" numeric;
ALTER TABLE "cfg"."postes" ADD COLUMN IF NOT EXISTS "coude_x" numeric;
ALTER TABLE "cfg"."postes" ADD COLUMN IF NOT EXISTS "coude_y" numeric;

CREATE TABLE IF NOT EXISTS "cfg"."fiches_documentaires" (
  "id" text PRIMARY KEY,
  "statut" text,
  "reference" text,
  "date" date,
  "version" text,
  "titre_haut" text,
  "titre" text,
  "mention" text,
  "grille" jsonb,
  "extra" jsonb
);
COMMENT ON TABLE "cfg"."fiches_documentaires" IS 'Collection « fichesDocumentaires » — Configuration (cartouche, mention de propriété et grille de l’organigramme imprimé)';
CREATE INDEX IF NOT EXISTS "ix_fiches_documentaires_statut" ON "cfg"."fiches_documentaires" ("statut");
