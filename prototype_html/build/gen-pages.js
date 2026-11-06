/* =============================================================================
 * Générateur des pages HTML du prototype SIGH-CBG
 * -----------------------------------------------------------------------------
 * Chaque page est engendrée à partir du manifeste assets/js/nav.js : la coquille
 * HTML est donc rigoureusement identique partout et tous les liens restent
 * cohérents. Relancer après toute modification du manifeste :
 *     node build/gen-pages.js
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

/* --- Chargement du manifeste dans un contexte minimal --------------------- */
const sandbox = { SIGH: {} };
new Function('window', fs.readFileSync(path.join(ROOT, 'assets/js/nav.js'), 'utf8'))(sandbox);
const NAV = sandbox.SIGH.nav;

/* --- Association module → fichier de rendu ------------------------------- */
const MODULE_FILES = {
  DASH: 'dashboards', PIL: 'dashboards', M1: 'm1-patients', M2: 'm2-consultations', M3: 'm3-hospitalisation',
  M4: 'm4-maternite', M5: 'm5-laboratoire', M6: 'm6-stock', M7: 'm7-achats',
  M8: 'm8-facturation', M9: 'm9-assurances', MECEF: 'mecef', M12: 'm12-comptabilite',
  M10: 'm10-rh', M11: 'm11-paie', M13: 'm13-administration', GED: 'ged',
  RAP: 'rapports', M14: 'm14-securite', CFG: 'configuration', AUTH: 'auth', SUP: 'support',
};

const SCRIPTS = [
  'vendor/lucide.min.js', 'vendor/chart.umd.min.js', 'vendor/lz-string.min.js',
  'core.js', 'data-plan-comptable.js', 'data-compta.js', 'data-sage.js', 'data-labo.js', 'data.js', 'data-tarifs.js', 'data-clinique.js', 'data-imagerie.js', 'data-dossier.js', 'data-maternite.js', 'store.js', 'parcours.js', 'ui.js', 'charts.js', 'print.js', 'nav.js', 'notifications.js', 'app.js', 'data-seed.js',
  'modules/_kit.js',
];

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function template(entry, opts) {
  const o = opts || {};
  const depth = o.root ? '' : '../';
  const mod = MODULE_FILES[entry.module];
  const scripts = SCRIPTS.map((s) => `  <script src="${depth}assets/js/${s}"></script>`);
  if (mod) scripts.push(`  <script src="${depth}assets/js/modules/${mod}.js"></script>`);

  return `<!doctype html>
<html lang="fr" data-root="${depth}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="${esc(entry.moduleLabel)} — Système Intégré de Gestion Hospitalière de la CLINIQUE BAGUIDI « L'AS DE CŒUR ».">
  <title>${esc(entry.label)} — SIGH Clinique BAGUIDI</title>
  <link rel="icon" href="${depth}assets/img/logo.png">
  <link rel="stylesheet" href="${depth}assets/css/tailwind.css">
</head>
<body class="min-h-screen bg-slate-100">
${scripts.join('\n')}
  <script>SIGH.mount(${JSON.stringify(entry.id)});</script>
</body>
</html>
`;
}

/* --- Génération ---------------------------------------------------------- */
const pagesDir = path.join(ROOT, 'pages');
fs.mkdirSync(pagesDir, { recursive: true });

let created = 0, kept = 0;
const written = new Set();

Object.keys(NAV.INDEX).forEach((id) => {
  const entry = NAV.INDEX[id];
  if (id === 'index') return; /* la page de connexion est écrite à la main */
  const file = path.join(pagesDir, id + '.html');
  const html = template(entry, {});
  written.add(id + '.html');
  const existing = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
  if (existing === html) { kept++; return; }
  fs.writeFileSync(file, html);
  created++;
});

/* --- Détection des pages orphelines -------------------------------------- */
const orphans = fs.readdirSync(pagesDir).filter((f) => f.endsWith('.html') && !written.has(f));

console.log(`Pages générées/mises à jour : ${created}`);
console.log(`Pages inchangées            : ${kept}`);
console.log(`Total au manifeste          : ${written.size}`);
if (orphans.length) console.log(`Pages orphelines (hors manifeste) : ${orphans.join(', ')}`);


/* --- Garde : index.html doit porter les mêmes scripts que les pages -------
   La page de connexion est écrite à la main ; elle a déjà divergé une fois
   (13 scripts sur 24 — un premier survol à froid semait le magasin et
   cassait sur L.EXAMENS). Le build échoue si elle diverge encore. */
const indexHtml = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const manquants = SCRIPTS.filter((s) => indexHtml.indexOf('assets/js/' + s) === -1);
if (manquants.length) {
  console.error('ERREUR — index.html ne charge pas : ' + manquants.join(', '));
  console.error('La page de connexion doit porter la même liste SCRIPTS que les pages générées.');
  process.exit(1);
}
console.log('index.html : scripts alignés sur SCRIPTS (' + SCRIPTS.length + ').');