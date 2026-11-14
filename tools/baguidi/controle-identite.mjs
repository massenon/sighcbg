#!/usr/bin/env node
// CONTRÔLE DE L'IDENTITÉ : échoue (code 1) si une trace de la clinique d'origine (Nassiera Too) subsiste dans le code et les petits jeux.
// Périmètre : apps/*/lib, packages/*/lib, apps/web (sans vendor), apps/poste/assets/donnees. Les tests et les vecteurs sont hors périmètre (ils
// portent des données d'essai), de même que les jeux de données que le lot suivant remplacera : LISTE BLANCHE EXPLICITE ci-dessous.
// Deux familles de motifs : l'IDENTITÉ de la clinique (partout) et les NOMS de personnes d'origine (voir plus bas : par empreintes).
// TROISIÈME FAMILLE (décision J11, 08/11/2026) : les NOMS DE PERSONNES de la clinique d'origine, cherchés PARTOUT (code, tests, fixtures, vecteurs, documents,
// jeu livré). La liste n'est PAS écrite ici : elle est lue sous forme d'EMPREINTES (SHA-256 tronqué) dans `noms-origine.json`, produit par `pseudonymiser.mjs`,
// seul fichier du dépôt à porter les noms en clair (liste blanche). Les fixtures de test portent les PSEUDONYMES de la table, jamais les noms d'origine ; le
// jeu LIVRÉ avec le poste ne porte NI les uns NI les autres (un pseudonyme est une donnée de test, pas une donnée de Baguidi).
// Usage depuis la racine :  node tools/baguidi/controle-identite.mjs
import { readFileSync, statSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

const IDENTITE = /NASSIERA|Nassiera|Natitingou|NATITINGOU|Tchirimina|TOO SARL|3201642748214|RB\/NAT|raison de vivre|QUE DIEU VOUS GU|cliniquenassiera|01 95 44 51 51|01 66 43 28 20|60 33 92 92|NS 145\/08\/DA\/C[N]T|Clinique NASSIERA/;
const RACINES = ['apps/poste/lib', 'apps/poste/assets/donnees', 'apps/mobile/lib', 'apps/web', 'apps/sync/lib', 'packages/domaine/lib', 'packages/sync_dart/lib'];
const SAUF = /(^|\/)(node_modules|\.git|build|vendor|\.dart_tool|\.claude|storage|bootstrap\/cache)(\/|$)|composer\.lock|package-lock\.json/;
const EXT = /\.(dart|json|js|cjs|mjs|ts|vue|php|yaml|yml|txt|xml|sql|html|css|blade\.php|md)$/;

// Liste blanche EXPLICITE : ce que le lot suivant (générateur de données Baguidi) remplacera.
const JEUX = [];   // le jeu livré est celui de Baguidi (générateur) : plus de jeu en liste blanche
const BLANCHE = new Set([
  ...JEUX.map((j) => `apps/poste/assets/donnees/jeu/${j}.json`),
  // personnel, paie, primes : sources documentaires de la clinique d'origine (notes de service NS 131/132 et barèmes)
  'packages/domaine/lib/src/administration/adm_notes_donnees.dart',
  'packages/domaine/lib/src/rh/rhb_regles.dart',
  'packages/domaine/lib/src/administration/adm_regles.dart',   // responsables du plan annuel (personnel)
  'packages/domaine/lib/src/configuration/cfb_fiscal_date.dart', // validation des échéances par un comptable du personnel d'origine
  // la liasse et le classeur 2025 sont désormais des données de DÉMONSTRATION Baguidi (tools/baguidi/demo-liasse.mjs, 08/11/2026) : plus d'exception
  // hors périmètre de ce lot (autres agents) : identité imprimée, règles de configuration
  'packages/domaine/lib/src/impression/identite.dart',
  'packages/domaine/lib/src/configuration/cfa_regles.dart',
]);
// Mentions de commentaires d'une règle de configuration appartenant à d'autres agents
const BLANCHE_PREFIXES = ['apps/poste/lib/modules/cfg/cfa_organisation.dart'];

// Noms de personnes d'origine : empreintes. Un nom de famille est cherché en MAJUSCULES et en casse de titre, un prénom en MAJUSCULES.
const EMPREINTES = JSON.parse(readFileSync(new URL('./noms-origine.json', import.meta.url), 'utf8'));
const NOMS = new Map(EMPREINTES.noms.map((e) => [e.h, e.f]));
const PSEUDOS = new Set(EMPREINTES.pseudonymes);
const norm = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/’/g, "'");
const hacher = (n) => createHash('sha256').update(n).digest('hex').slice(0, 14);
const TOKEN = /[\p{L}]+(?:[’'][\p{L}]+)?/gu;
const estMaj = (t) => t === t.toUpperCase() && t !== t.toLowerCase();
const estTitre = (t) => t[0] === t[0].toUpperCase() && t[0] !== t[0].toLowerCase() && t.slice(1) === t.slice(1).toLowerCase();
function nomDOrigine(ligne) {
  for (const m of ligne.matchAll(TOKEN)) {
    const t = m[0].replace(/[’']/g, '');
    if (t.length < 3) continue;
    const f = NOMS.get(hacher(norm(m[0])));
    if (f && (estMaj(t) || (f === 'UT' && estTitre(t)))) return m[0];
  }
  return null;
}
function pseudonyme(ligne) {
  for (const m of ligne.matchAll(TOKEN)) {
    const t = m[0].replace(/[’']/g, '');
    if (t.length >= 4 && PSEUDOS.has(hacher(norm(m[0]))) && (estMaj(t) || estTitre(t))) return m[0];
  }
  return null;
}
// Périmètre de la famille « noms » : tout le dépôt utile, tests et documents compris.
const RACINES_NOMS = ['apps', 'packages', 'docs', 'tools'];
// Le seul fichier qui porte les noms d'origine en clair, et le fichier d'empreintes.
const BLANCHE_NOMS = new Set(['tools/baguidi/pseudonymiser.mjs', 'tools/baguidi/noms-origine.json']);
// Le jeu LIVRÉ ne porte aucun pseudonyme de test.
const JEU_LIVRE = 'apps/poste/assets/donnees/jeu';

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
    const m = l.match(IDENTITE);
    if (m) { trouvailles++; console.log(`${p}:${i + 1}: « ${m[0]} »`); }
  });
}
RACINES.forEach(passe);
// Famille « noms de personnes » : passe distincte, sur un périmètre plus large, sans liste blanche de jeux (les fixtures sont pseudonymisées).
let nomsTrouves = 0;
function passeNoms(p) {
  if (SAUF.test(p) || !existsSync(p)) return;
  const st = statSync(p);
  if (st.isDirectory()) { for (const f of readdirSync(p)) passeNoms(join(p, f)); return; }
  if (!EXT.test(p) || st.size > 12e6 || BLANCHE_NOMS.has(p)) return;
  const lignes = readFileSync(p, 'utf8').split('\n');
  lignes.forEach((l, i) => {
    const nom = nomDOrigine(l);
    if (nom) { nomsTrouves++; console.log(`${p}:${i + 1}: nom d'origine « ${nom} »`); return; }
    if (p.startsWith(JEU_LIVRE)) {
      const ps = pseudonyme(l);
      if (ps) { nomsTrouves++; console.log(`${p}:${i + 1}: pseudonyme de test « ${ps} » dans le jeu livré`); }
    }
  });
}
RACINES_NOMS.forEach(passeNoms);
trouvailles += nomsTrouves;
console.log(`${trouvailles} trace(s) hors liste blanche (${ignores} fichier(s) en liste blanche).`);
process.exit(trouvailles ? 1 : 0);
