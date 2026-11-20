// Garde du design du relais : (1) aucune couleur en dur ni ressource externe dans les vues et feuilles du panneau, (2) jetons.css à jour avec la charte,
// (3) contraste AA des couples de couleurs des jetons. Usage : node --test tests/js/panneau-jetons.test.mjs (depuis apps/web)
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { engendrer } from '../../../../tools/baguidi/engendrer-jetons-relais.mjs';

const web = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const parcourir = (d) => readdirSync(d).flatMap((f) => (statSync(join(d, f)).isDirectory() ? parcourir(join(d, f)) : [join(d, f)]));
const vues = ['resources/views/layouts', 'resources/views/livewire/panneau', 'resources/views/panneau', 'resources/views/satisfaction'].flatMap((d) => parcourir(join(web, d)));
const feuilles = ['public/css/panneau.css', 'public/css/satisfaction.css'].map((f) => join(web, f));
const surface = [...vues, ...feuilles];
const lire = (f) => readFileSync(f, 'utf8');
const sansCommentaires = (t) => t.replace(/\{\{--[\s\S]*?--\}\}/g, '').replace(/\/\*[\s\S]*?\*\//g, '');

test('aucune couleur en dur dans les vues ni dans les feuilles du panneau', () => {
  const motif = /#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![0-9a-zA-Z_-])|\b(?:rgba?|hsla?|oklch|hwb)\(/g;
  const fautes = surface.flatMap((f) => [...sansCommentaires(lire(f)).matchAll(motif)].map((m) => `${f.replace(web + '/', '')} : ${m[0]}`));
  assert.deepEqual(fautes, []);
});

test('aucune URL externe, aucun CDN, aucune police distante', () => {
  const motif = /(?:https?:)?\/\/[a-z0-9.-]+\.[a-z]{2,}|@import\s+url\(\s*["']?https?:|fonts\.googleapis|cdn\./gi;
  const fautes = surface.flatMap((f) => [...sansCommentaires(lire(f)).matchAll(motif)].map((m) => `${f.replace(web + '/', '')} : ${m[0]}`));
  assert.deepEqual(fautes, []);
  const jetons = lire(join(web, 'public/css/jetons.css'));
  assert.ok(!/https?:\/\//.test(jetons), 'jetons.css ne charge rien d\'externe');
  for (const m of jetons.matchAll(/url\("\.\.\/(fonts\/[^"]+)"\)/g)) assert.ok(existsSync(join(web, 'public', m[1])), `police absente : ${m[1]}`);
});

test('jetons.css est à jour avec docs/design/design-tokens.json et jetons_shell.dart', () => {
  assert.equal(lire(join(web, 'public/css/jetons.css')), engendrer());
});

test('les feuilles n\'emploient que des variables définies dans jetons.css', () => {
  const definies = new Set([...lire(join(web, 'public/css/jetons.css')).matchAll(/(--[a-z0-9-]+):/g)].map((m) => m[1]));
  const fautes = feuilles.flatMap((f) => [...lire(f).matchAll(/var\((--[a-z0-9-]+)/g)].map((m) => m[1]).filter((v) => !definies.has(v)).map((v) => `${f.replace(web + '/', '')} : ${v}`));
  assert.deepEqual(fautes, []);
});

// ---- Contraste WCAG ----
const vars = {};
for (const m of lire(join(web, 'public/css/jetons.css')).matchAll(/(--[a-z0-9-]+):\s*([^;]+);/g)) vars[m[1]] = m[2].trim();
const resoudre = (n, g = 0) => { let v = vars[n]; const r = v && v.match(/^var\((--[a-z0-9-]+)\)$/); if (r && g < 8) return resoudre(r[1], g + 1); return v; };
const lum = (h) => { const [r, g, b] = [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255).map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
export const contraste = (a, b) => { const [x, y] = [lum(resoudre(a)), lum(resoudre(b))].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
const COUPLES = [
  ['texte / fond', '--c-texte', '--c-fond', 4.5], ['texte / surface', '--c-texte', '--c-surface', 4.5], ['texte doux / surface', '--c-texte-doux', '--c-surface', 4.5], ['texte doux / fond', '--c-texte-doux', '--c-fond', 4.5],
  ['lien / surface', '--c-lien', '--c-surface', 4.5], ['lien / fond', '--c-lien', '--c-fond', 4.5], ['titre / fond', '--c-titre', '--c-fond', 4.5], ['titre / en-tête de tableau', '--c-titre', '--c-neutre-fond', 4.5],
  ['bouton principal', '--c-sur-action', '--c-action', 4.5], ['bouton principal survol', '--c-sur-action', '--c-action-survol', 4.5], ['bouton secondaire', '--c-titre', '--c-surface', 4.5],
  ['bouton danger', '--c-alerte-bouton', '--c-surface', 4.5], ['entrée courante (rouge)', '--c-sur-action', '--c-action', 4.5],
  ['barre : texte', '--c-barre-texte', '--c-barre', 4.5], ['barre : texte discret', '--c-barre-doux', '--c-barre', 4.5], ['barre : titre', '--c-barre-titre', '--c-barre', 4.5], ['barre : devise', '--c-barre-devise', '--c-barre', 4.5],
  ['pastille OK', '--c-ok-texte', '--c-ok-fond', 4.5], ['pastille attention', '--c-attention-texte', '--c-attention-fond', 4.5], ['pastille alerte', '--c-alerte-texte', '--c-alerte-fond', 4.5], ['pastille neutre', '--c-neutre-texte', '--c-neutre-fond', 4.5],
  ['note', '--c-note-texte', '--c-note-fond', 4.5], ['info', '--c-info-texte', '--c-info-fond', 4.5],
  ['devise rouge sur surface', '--c-action', '--c-surface', 4.5],
  ['bordure de champ / surface (composant : 3:1)', '--c-bord-champ', '--c-surface', 3], ['focus / surface (3:1)', '--c-focus', '--c-surface', 3], ['focus / barre (3:1)', '--c-focus-barre', '--c-barre', 3],
];
for (const [nom, a, b, seuil] of COUPLES) test(`contraste ${nom} ≥ ${seuil}:1`, () => { const c = contraste(a, b); assert.ok(c >= seuil, `${nom} : ${c.toFixed(2)}:1`); });
