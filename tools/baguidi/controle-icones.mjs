#!/usr/bin/env node
// CONTRÔLE DES ICÔNES (réplique Baguidi) : aucune icône de l'application ne doit être celle de l'ancienne clinique ni l'icône par défaut de Flutter.
// Le contrôle d'identité ne voit pas les binaires : celui-ci compare les EMPREINTES (sha256).
//   1. chaque fichier d'icône existe, n'est pas vide, n'a pas l'empreinte d'une icône d'origine (tools/baguidi/icones-origine.json) ;
//   2. chaque fichier a l'empreinte engendrée par tools/baguidi/generer-icones.py depuis le logo de Baguidi (icones-attendues.json) ;
//   3. l'icône Windows porte bien les sept tailles 16/24/32/48/64/128/256, le favicon 16/32/48.
// Code de sortie : 0 si tout est conforme, 1 sinon. Usage : node tools/baguidi/controle-icones.mjs
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ici = dirname(fileURLToPath(import.meta.url));
const racine = join(ici, '..', '..');
const origine = JSON.parse(readFileSync(join(ici, 'icones-origine.json'), 'utf8')).empreintes;
const attendues = JSON.parse(readFileSync(join(ici, 'icones-attendues.json'), 'utf8'));
const interdites = new Set(Object.values(origine));
const sha = (b) => createHash('sha256').update(b).digest('hex');
const problemes = [];

for (const [chemin, attendue] of Object.entries(attendues)) {
  const f = join(racine, chemin);
  if (!existsSync(f)) { problemes.push(`${chemin} : absent`); continue; }
  const b = readFileSync(f);
  if (b.length === 0) { problemes.push(`${chemin} : vide`); continue; }
  const h = sha(b);
  if (interdites.has(h)) problemes.push(`${chemin} : icône d'origine (ancienne clinique ou Flutter)`);
  else if (h !== attendue) problemes.push(`${chemin} : ne vient pas du logo Baguidi (relancer tools/baguidi/generer-icones.py)`);
}
for (const chemin of Object.keys(origine)) {
  if (!(chemin in attendues)) problemes.push(`${chemin} : icône d'origine non remplacée dans icones-attendues.json`);
}

function tailles(chemin) {
  const b = readFileSync(join(racine, chemin));
  const n = b.readUInt16LE(4);
  const t = [];
  for (let i = 0; i < n; i++) t.push(b[6 + i * 16] || 256);
  return t.sort((a, c) => a - c).join(',');
}
const exige = [['apps/poste/windows/runner/resources/app_icon.ico', '16,24,32,48,64,128,256'], ['apps/web/public/favicon.ico', '16,32,48']];
for (const [c, t] of exige) if (existsSync(join(racine, c)) && tailles(c) !== t) problemes.push(`${c} : tailles ${tailles(c)} au lieu de ${t}`);

if (problemes.length) { console.log(problemes.join('\n')); console.log(`\n${problemes.length} icône(s) non conforme(s).`); process.exit(1); }
console.log(`0 icône d'origine : ${Object.keys(attendues).length} icônes conformes.`);
