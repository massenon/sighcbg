#!/usr/bin/env node
// ENGENDRE apps/web/public/css/jetons.css : l'UNIQUE source de variables CSS du relais (panneau superadmin, page de connexion, questionnaire public).
// Les valeurs ne sont PAS recopiées à la main : les palettes viennent de docs/design/design-tokens.json (charte Baguidi), les neutres « slate » et le voile
// de jetons_shell.dart (le poste), les ombres du JSON. Aucune couleur n'est écrite ailleurs dans le CSS ou dans les vues du relais.
// Usage depuis la racine :  node tools/baguidi/engendrer-jetons-relais.mjs            (écrit le fichier)
//                           node tools/baguidi/engendrer-jetons-relais.mjs --verifier (échoue si le fichier engendré diffère de l'existant)
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const racine = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SORTIE = join(racine, 'apps/web/public/css/jetons.css');

export function engendrer() {
  const j = JSON.parse(readFileSync(join(racine, 'docs/design/design-tokens.json'), 'utf8'));
  const shell = readFileSync(join(racine, 'apps/poste/lib/core/jetons_shell.dart'), 'utf8');
  const hex = (v) => v.toLowerCase();
  const nuances = (nom, palette) => Object.entries(palette).filter(([k]) => /^\d+$/.test(k)).map(([k, v]) => `  --${nom}-${k}: ${hex(v)};`);

  const slate = [...shell.matchAll(/slate(\d+) = Color\(0xFF([0-9A-Fa-f]{6})\)/g)].map((m) => `  --slate-${m[1]}: #${m[2].toLowerCase()};`);
  if (slate.length !== 10) throw new Error('jetons_shell.dart : les dix nuances slate sont introuvables');
  const scrim = shell.match(/scrim = Color\(0x([0-9A-Fa-f]{2})([0-9A-Fa-f]{6})\)/);
  if (!scrim) throw new Error('jetons_shell.dart : le voile (scrim) est introuvable');
  const alpha = (parseInt(scrim[1], 16) / 255).toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
  const rvb = [0, 2, 4].map((i) => parseInt(scrim[2].slice(i, i + 2), 16)).join(' ');

  const pol = (liste) => liste.map((f) => (/\s/.test(f) ? `"${f}"` : f)).join(', ');
  const face = (famille, fichier, poids) => `@font-face { font-family: "${famille}"; font-style: normal; font-weight: ${poids}; font-display: swap; src: url("../fonts/${fichier}.woff2") format("woff2"); }`;

  const c = j.couleurs;
  return [
    '/* ENGENDRÉ par tools/baguidi/engendrer-jetons-relais.mjs : NE PAS ÉDITER À LA MAIN.',
    '   Sources : docs/design/design-tokens.json (palettes, ombres, polices), apps/poste/lib/core/jetons_shell.dart (neutres, voile).',
    '   UNIQUE endroit du relais où une couleur s\'écrit en dur ; panneau.css et satisfaction.css n\'emploient que var(--…). */',
    face('Inter', 'Inter-Regular', 400), face('Inter', 'Inter-Medium', 500), face('Inter', 'Inter-SemiBold', 600), face('Inter', 'Inter-Bold', 700),
    face('Montserrat', 'Montserrat-SemiBold', 600), face('Montserrat', 'Montserrat-Bold', 700), face('Dancing Script', 'DancingScript-Regular', 400),
    '',
    ':root {',
    '  /* Palettes de la charte : Rouge Cœur (actions), Bleu Santé (titres, badges), Noir Anthracite (barres sombres). */',
    ...nuances('coeur', c.coeur), ...nuances('sante', c.sante),
    ...Object.entries(c.anthracite).filter(([k]) => /^\d+$/.test(k)).map(([k, v]) => `  --anthracite-${k}: ${hex(v)};`),
    '  /* États : le rouge d\'ERREUR (danger) n\'est pas le rouge d\'ACTION (coeur) : une alerte ne se confond jamais avec un bouton. */',
    ...nuances('success', c.success), ...nuances('warning', c.warning), ...nuances('danger', c.danger), ...nuances('info', c.info),
    '  /* Neutres du poste. */',
    ...slate,
    '  --blanc: #ffffff;',
    `  --voile: rgb(${rvb} / ${alpha});`,
    '  --survol-sombre: rgb(255 255 255 / 0.1);',
    '  --defilement-ombre: rgb(' + rvb + ' / 0.18);',
    '',
    '  /* Rôles : ce sont ces noms que le CSS et les vues emploient. */',
    '  --c-action: var(--coeur-500); --c-action-survol: var(--coeur-600); --c-action-actif: var(--coeur-700); --c-sur-action: var(--blanc);',
    '  --c-lien: var(--sante-700); --c-titre: var(--sante-900); --c-accent: var(--sante-600);',
    '  --c-texte: var(--slate-900); --c-texte-doux: var(--slate-600);',
    '  --c-fond: var(--slate-100); --c-surface: var(--blanc); --c-surface-douce: var(--slate-50);',
    '  --c-bord: var(--slate-200); --c-bord-champ: var(--slate-500);',
    '  --c-barre: var(--anthracite-900); --c-barre-profonde: var(--anthracite-950); --c-barre-texte: var(--slate-300); --c-barre-doux: var(--slate-400); --c-barre-titre: var(--blanc); --c-barre-devise: var(--coeur-300);',
    '  --c-focus: var(--sante-600); --c-focus-barre: var(--sante-300);',
    '  --c-ok-fond: var(--success-100); --c-ok-texte: var(--success-800); --c-ok-bord: var(--success-600);',
    '  --c-attention-fond: var(--warning-100); --c-attention-texte: var(--warning-800); --c-attention-bord: var(--warning-600);',
    '  --c-alerte-fond: var(--danger-100); --c-alerte-texte: var(--danger-800); --c-alerte-bord: var(--danger-600); --c-alerte-bouton: var(--danger-700);',
    '  --c-info-fond: var(--info-50); --c-info-texte: var(--info-900); --c-info-bord: var(--info-600);',
    '  --c-neutre-fond: var(--sante-50); --c-neutre-texte: var(--sante-800);',
    '  --c-note-fond: var(--sante-50); --c-note-bord: var(--sante-600); --c-note-texte: var(--sante-900);',
    '',
    '  /* Échelle d\'espacement UNIQUE : 4 / 8 / 12 / 16 / 24 / 32 px. */',
    '  --e-1: 4px; --e-2: 8px; --e-3: 12px; --e-4: 16px; --e-6: 24px; --e-8: 32px;',
    '  /* Rayons (rounded-lg, rounded-xl de la maquette) et cible tactile minimale. */',
    '  --rayon: 8px; --rayon-lg: 12px; --rayon-pastille: 999px; --cible: 44px;',
    '  /* Ombres de la maquette. */',
    `  --ombre-carte: ${j.ombres.card};`, `  --ombre-leve: ${j.ombres.raise};`, `  --ombre-pop: ${j.ombres.pop};`,
    '  /* Typographie : Inter pour le texte, Montserrat pour les titres, Dancing Script EXCLUSIVEMENT pour la devise. */',
    `  --police-texte: ${pol(j.police.sans)};`, `  --police-titres: ${pol(j.police.heading)};`, `  --police-devise: ${pol(j.police.slogan)};`, `  --police-code: ${pol(j.police.mono)};`,
    '  --t-base: 15px; --t-petit: 14px; --t-grand: 18px; --t-titre: 24px; --t-valeur: 28px;',
    '  --largeur-barre: 272px; --largeur-contenu: 1200px;',
    '}',
    '',
  ].join('\n');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const texte = engendrer();
  if (process.argv.includes('--verifier')) {
    const actuel = existsSync(SORTIE) ? readFileSync(SORTIE, 'utf8') : '';
    if (actuel !== texte) { console.error('jetons.css n\'est pas à jour : relancer tools/baguidi/engendrer-jetons-relais.mjs'); process.exit(1); }
    console.log('jetons.css à jour');
  } else { writeFileSync(SORTIE, texte); console.log(`écrit : ${SORTIE}`); }
}
