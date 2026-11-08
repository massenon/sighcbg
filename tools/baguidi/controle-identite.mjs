#!/usr/bin/env node
// CONTRÔLE DE L'IDENTITÉ : échoue (code 1) si une trace de la clinique d'origine (Nassiera Too) subsiste dans le code et les petits jeux.
// Périmètre : apps/*/lib, packages/*/lib, apps/web (sans vendor), apps/poste/assets/donnees. Les tests et les vecteurs sont hors périmètre (ils
// portent des données d'essai), de même que les jeux de données que le lot suivant remplacera : LISTE BLANCHE EXPLICITE ci-dessous.
// Deux familles de motifs : l'IDENTITÉ de la clinique (partout) et les NOMS de signataires d'origine (code seulement : les jeux de personnel
// et de patients les portent comme données, remplacées avec elles). Usage depuis la racine :  node tools/baguidi/controle-identite.mjs
import { readFileSync, statSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const IDENTITE = /NASSIERA|Nassiera|Natitingou|NATITINGOU|Tchirimina|TOO SARL|3201642748214|RB\/NAT|raison de vivre|QUE DIEU VOUS GU|cliniquenassiera|01 95 44 51 51|01 66 43 28 20|60 33 92 92|NS 145\/08\/DA\/C[N]T|Clinique NASSIERA/;
const SIGNATAIRES = /BASSONGUI|KASSA/;
const RACINES = ['apps/poste/lib', 'apps/poste/assets/donnees', 'apps/mobile/lib', 'apps/web', 'apps/sync/lib', 'packages/domaine/lib', 'packages/sync_dart/lib'];
const SAUF = /(^|\/)(node_modules|\.git|build|vendor|\.dart_tool|\.claude|storage|bootstrap\/cache)(\/|$)|composer\.lock|package-lock\.json/;
const EXT = /\.(dart|json|js|mjs|php|yaml|yml|txt|xml|sql|html|css|blade\.php|md)$/;

// Liste blanche EXPLICITE : ce que le lot suivant (générateur de données Baguidi) remplacera.
const JEUX = ['patients', 'dossiersObstetricaux', 'dossiersConsultation', 'consultations', 'demandesAnalyses', 'rapportsMedicaux', 'fichesReference',
  'factures', 'facturesMere', 'souscripteurs', 'fournisseurs', 'catalogueTarifs', 'actes', 'postes', 'fichesPoste', 'personnel', 'planAnnuel'];
const BLANCHE = new Set([
  ...JEUX.map((j) => `apps/poste/assets/donnees/jeu/${j}.json`),
  // personnel, paie, primes : sources documentaires de la clinique d'origine (notes de service NS 131/132 et barèmes)
  'packages/domaine/lib/src/administration/adm_notes_donnees.dart',
  'packages/domaine/lib/src/rh/rhb_regles.dart',
  'packages/domaine/lib/src/administration/adm_regles.dart',   // responsables du plan annuel (personnel)
  'packages/domaine/lib/src/configuration/cfb_fiscal_date.dart', // validation des échéances par un comptable du personnel d'origine
  // documents fiscaux de l'autre clinique : jamais réécrits (inventer une liasse serait une faute)
  'packages/domaine/lib/src/comptabilite/cpb_liasse.dart',
  'packages/domaine/lib/src/comptabilite/cpc_liasse.dart',
  'packages/domaine/lib/src/comptabilite/cpc_donnees.dart',
  // hors périmètre de ce lot (autres agents) : identité imprimée, règles de configuration
  'packages/domaine/lib/src/impression/identite.dart',
  'packages/domaine/lib/src/configuration/cfa_regles.dart',
]);
// Mentions de commentaires d'une règle de configuration appartenant à d'autres agents
const BLANCHE_PREFIXES = ['apps/poste/lib/modules/cfg/cfa_organisation.dart'];

const AVEC_NOMS = (p) => p.startsWith('apps/poste/lib') || p.startsWith('packages/domaine/lib') || p.startsWith('apps/mobile') || p.startsWith('apps/web');
let trouvailles = 0, ignores = 0;
function passe(p) {
  if (SAUF.test(p) || !existsSync(p)) return;
  const st = statSync(p);
  if (st.isDirectory()) { for (const f of readdirSync(p)) passe(join(p, f)); return; }
  if (!EXT.test(p) || st.size > 8e6) return;
  if (BLANCHE.has(p) || BLANCHE_PREFIXES.some((x) => p.startsWith(x))) { ignores++; return; }
  const lignes = readFileSync(p, 'utf8').split('\n');
  lignes.forEach((l, i) => {
    const m = l.match(IDENTITE) || (AVEC_NOMS(p) && l.match(SIGNATAIRES));
    if (m) { trouvailles++; console.log(`${p}:${i + 1}: « ${m[0]} »`); }
  });
}
RACINES.forEach(passe);
console.log(`${trouvailles} trace(s) hors liste blanche (${ignores} fichier(s) en liste blanche).`);
process.exit(trouvailles ? 1 : 0);
