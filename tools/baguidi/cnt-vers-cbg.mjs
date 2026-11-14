#!/usr/bin/env node
// Le sigle CNT (Clinique Nassiera Too) devient CBG (Clinique Baguidi) partout où il est un MOT : codes patient CNT/n/AA, références de pièces,
// références de notes de service, noms de fichiers d'export, nom du logiciel. Décision de la Direction du 08/11/2026 (« tout mot clé CNT en CBG »).
//
// CE QU'IL TOUCHE : le mot CNT en majuscules, isolé (ni lettre, ni chiffre, ni soulignement avant ; pas de lettre après), et les formes minuscules
// « sigh-cnt » et « sigh_cnt ». Sources, données, vecteurs et tests de apps/, packages/ et tools/, les fiches de docs/architecture/ecrans et les jetons.
// CE QU'IL NE TOUCHE PAS : l'historique rédigé (docs/**/*.md, PRD, ADR, journal des écarts), les identifiants techniques (une variable « cnt »,
// un nom de classe), les dossiers .claude, node_modules, build, les binaires.
// Rejouable : une seconde passe ne trouve plus rien. Usage depuis la racine :  node tools/baguidi/cnt-vers-cbg.mjs [--verifier]
import { readFileSync, writeFileSync, statSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const RACINES = ['apps', 'packages', 'tools', 'docs/architecture/ecrans', 'docs/design', 'package.json'];
const EXT = /\.(dart|json|js|mjs|php|yaml|yml|iss|rc|kts|kt|txt|xml|sql|html|css|example|exemple|gradle|cmake|cc|h|plist)$|\.env/i;
const SAUF = /(^|\/)(node_modules|\.git|build|vendor|\.dart_tool|\.claude)(\/|$)|pubspec\.lock|composer\.lock|package-lock\.json|cnt-vers-cbg\.mjs$/;
const MOT = /(?<![A-Za-z0-9_])CNT(?![A-Za-z])/g;
const MIN = /sigh([-_])cnt(?![A-Za-z])/g;
const verifier = process.argv.includes('--verifier');
let fichiers = 0, occ = 0;
function passe(p) {
  if (SAUF.test(p)) return;
  let st; try { st = statSync(p); } catch { return; }
  if (st.isDirectory()) { for (const f of readdirSync(p)) passe(join(p, f)); return; }
  if (!EXT.test(p) || st.size > 8e6) return;
  let s; try { s = readFileSync(p, 'utf8'); } catch { return; }
  let n = 0;
  const t = s.replace(MOT, () => (n++, 'CBG')).replace(MIN, (_, sep) => (n++, `sigh${sep}cbg`));
  if (n) { fichiers++; occ += n; if (!verifier) writeFileSync(p, t); }
}
RACINES.forEach(passe);
console.log(`${occ} occurrence(s) dans ${fichiers} fichier(s) ${verifier ? 'à remplacer' : 'remplacée(s)'}.`);
process.exit(verifier && occ ? 1 : 0);
