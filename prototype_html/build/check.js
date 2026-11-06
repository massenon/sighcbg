/* =============================================================================
 * Contrôle de conformité du prototype SIGH-CBG
 * -----------------------------------------------------------------------------
 * Ouvre chaque page dans Chrome (sans interface) et vérifie :
 *   1. aucune erreur JavaScript ni avertissement console d'erreur ;
 *   2. aucune ressource introuvable (404) ;
 *   3. aucun lien cassé — chaque href pointe vers un fichier existant ;
 *   4. la coquille est bien montée (méga-menu, barre supérieure, contenu) ;
 *   5. l'écran est bien déclaré au registre (pas de repli « en construction »).
 *
 * Usage :  node build/check.js  [--pages=m1-patients,m6-stock]  [--headful]
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const puppeteer = require('puppeteer');

const ROOT = path.resolve(__dirname, '..');
const PORT = 8099;

/* --- Localisation d'un navigateur installé -------------------------------- */
function findBrowser() {
  const candidates = [
    process.env.CHROME_PATH,
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  ].filter(Boolean);
  for (const c of candidates) if (fs.existsSync(c)) return c;
  return null;
}

/* --- Serveur statique minimal --------------------------------------------- */
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json',
  '.woff2': 'font/woff2', '.jpeg': 'image/jpeg', '.jpg': 'image/jpeg',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};
function serve() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html';
      const file = path.join(ROOT, rel);
      if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('404'); return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(PORT, () => resolve(server));
  });
}

/* --- Inventaire des pages -------------------------------------------------- */
function listPages() {
  const pages = ['index.html'];
  for (const f of fs.readdirSync(path.join(ROOT, 'pages'))) {
    if (f.endsWith('.html')) pages.push('pages/' + f);
  }
  return pages;
}

/* --- Programme principal ---------------------------------------------------*/
(async () => {
  const args = process.argv.slice(2);
  const only = (args.find((a) => a.startsWith('--pages=')) || '').replace('--pages=', '');
  const headful = args.includes('--headful');

  const exe = findBrowser();
  if (!exe) {
    console.error('Aucun navigateur Chrome/Edge trouvé. Définir CHROME_PATH.');
    process.exit(2);
  }

  let pages = listPages();
  if (only) {
    const wanted = only.split(',').map((s) => s.trim());
    pages = pages.filter((p) => wanted.some((w) => p.includes(w)));
  }

  const server = await serve();
  const browser = await puppeteer.launch({
    executablePath: exe,
    headless: !headful,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
  });

  const report = { pages: 0, jsErrors: [], missing: [], brokenLinks: [], notMounted: [], stubs: [], slow: [] };
  const linkCache = new Map();

  function fileExists(rel) {
    if (linkCache.has(rel)) return linkCache.get(rel);
    const f = path.join(ROOT, rel.split('#')[0].split('?')[0]);
    const ok = fs.existsSync(f);
    linkCache.set(rel, ok);
    return ok;
  }

  for (const rel of pages) {
    /* Sur un contrôle de 282 pages, le petit serveur statique local lâche
       parfois une poignée de requêtes (core.js ou la page elle-même non
       servis) : la page « échoue » alors sur un incident de transport, pas
       sur un défaut du prototype. UNE reprise par page distingue le défaut
       réel — qui échoue deux fois — de l'aléa, qui ne se reproduit pas. */
    let errors, missing, elapsed;
    let page;
    for (let essai = 0; essai < 2; essai++) {
      page = await browser.newPage();
      errors = [];
      missing = [];

      page.on('pageerror', (e) => errors.push(String(e.message || e)));
      page.on('console', (msg) => {
        if (msg.type() === 'error') errors.push('console.error: ' + msg.text());
      });
      page.on('requestfailed', (req) => missing.push(req.url()));
      page.on('response', (res) => {
        if (res.status() === 404) missing.push(res.url());
      });

      const t0 = Date.now();
      try {
        await page.goto(`http://127.0.0.1:${PORT}/${rel}`, { waitUntil: 'networkidle2', timeout: 25000 });
        await new Promise((r) => setTimeout(r, 350)); // laisse le rendu différé (graphiques) s'exécuter
      } catch (e) {
        errors.push('Navigation: ' + e.message);
      }
      elapsed = Date.now() - t0;

      const transport = missing.length > 0 || errors.some((x) => /^Navigation:/.test(x));
      if (!transport || essai === 1) break;
      await page.close();
      await new Promise((r) => setTimeout(r, 400));
    }
    if (elapsed > 6000) report.slow.push({ page: rel, ms: elapsed });

    /* Structure montée + liens */
    let info = { links: [], mounted: false, stub: false, title: '' };
    try {
      info = await page.evaluate(() => {
        const links = [...document.querySelectorAll('a[href]')]
          .map((a) => a.getAttribute('href'))
          /* Un tel:, un mailto: ou un data: ne désigne pas une page du prototype :
             les compter comme liens ferait échouer le contrôle sur un numéro de
             téléphone parfaitement valide. */
          .filter((h) => h && !/^(https?:|#|mailto:|tel:|sms:|data:|blob:|javascript:)/i.test(h));
        const standalone = !!(window.SIGH && window.SIGH.screens
          && Object.values(window.SIGH.screens).some((s) => s.standalone && location.pathname.includes(s.id)));
        const mounted = !!document.querySelector('#app-menubar') || !!document.querySelector('#page > *')
          || document.body.children.length > 3;
        const stub = document.body.textContent.includes('Écran en cours de construction');
        return { links: [...new Set(links)], mounted, stub, title: document.title, standalone,
          chemin: location.pathname };
      });
    } catch (e) {
      errors.push('Évaluation: ' + e.message);
    }

    /* Résolution des liens relatifs — contre le chemin FINAL de la page, pas
       celui qu'on a ouvert : un écran d'accès sans session (auth-lock)
       REDIRIGE vers la connexion à la racine, et ses liens `pages/…` se
       résolvaient contre `pages/`, fabriquant des `pages/pages/…` fantômes. */
    const chemin = (info.chemin || '/' + rel).replace(/^\/+/, '') || rel;
    const dir = path.posix.dirname(chemin);
    for (const href of info.links) {
      const target = path.posix.normalize(path.posix.join(dir === '.' ? '' : dir, href));
      if (!fileExists(target)) {
        report.brokenLinks.push({ page: rel, href, resolved: target });
      }
    }

    if (errors.length) report.jsErrors.push({ page: rel, errors: [...new Set(errors)] });
    if (missing.length) report.missing.push({ page: rel, urls: [...new Set(missing)] });
    if (!info.mounted) report.notMounted.push(rel);
    if (info.stub) report.stubs.push(rel);

    report.pages++;
    await page.close();
    process.stdout.write(`\r  ${report.pages}/${pages.length} pages contrôlées…   `);
  }

  await browser.close();
  server.close();

  /* --- Restitution --------------------------------------------------------- */
  const line = '─'.repeat(72);
  console.log('\n' + line);
  console.log('CONTRÔLE DU PROTOTYPE SIGH-CBG');
  console.log(line);
  console.log(`Pages contrôlées          : ${report.pages}`);
  console.log(`Erreurs JavaScript        : ${report.jsErrors.length} page(s)`);
  console.log(`Ressources introuvables   : ${report.missing.length} page(s)`);
  console.log(`Liens cassés              : ${report.brokenLinks.length}`);
  console.log(`Pages non montées         : ${report.notMounted.length}`);
  console.log(`Écrans non implémentés    : ${report.stubs.length}`);
  if (report.slow.length) console.log(`Pages lentes (> 6 s)      : ${report.slow.length}`);

  if (report.jsErrors.length) {
    console.log('\n── ERREURS JAVASCRIPT ' + '─'.repeat(50));
    for (const e of report.jsErrors.slice(0, 25)) {
      console.log(`\n  ${e.page}`);
      e.errors.slice(0, 4).forEach((x) => console.log(`    • ${x.slice(0, 240)}`));
    }
    if (report.jsErrors.length > 25) console.log(`\n  … et ${report.jsErrors.length - 25} autre(s) page(s).`);
  }
  if (report.missing.length) {
    console.log('\n── RESSOURCES INTROUVABLES ' + '─'.repeat(45));
    for (const m of report.missing.slice(0, 10)) {
      console.log(`  ${m.page}`);
      m.urls.slice(0, 3).forEach((u) => console.log(`    • ${u}`));
    }
  }
  if (report.brokenLinks.length) {
    console.log('\n── LIENS CASSÉS ' + '─'.repeat(56));
    const grouped = {};
    for (const b of report.brokenLinks) (grouped[b.resolved] = grouped[b.resolved] || []).push(b.page);
    Object.entries(grouped).slice(0, 25).forEach(([target, pages]) => {
      console.log(`  ${target}  ←  ${pages.length} page(s), ex. ${pages[0]}`);
    });
  }
  if (report.notMounted.length) {
    console.log('\n── PAGES NON MONTÉES ' + '─'.repeat(51));
    report.notMounted.slice(0, 20).forEach((p) => console.log(`  ${p}`));
  }
  if (report.stubs.length) {
    console.log('\n── ÉCRANS NON ENCORE IMPLÉMENTÉS ' + '─'.repeat(39));
    console.log('  ' + report.stubs.map((p) => path.basename(p, '.html')).join(', '));
  }

  const bloquant = report.jsErrors.length + report.missing.length + report.brokenLinks.length + report.notMounted.length;
  console.log('\n' + line);
  console.log(bloquant === 0
    ? 'RÉSULTAT : CONFORME — 0 erreur JS, 0 lien cassé, 0 ressource manquante.'
    : `RÉSULTAT : ${bloquant} anomalie(s) bloquante(s) à corriger.`);
  console.log(line);

  fs.writeFileSync(path.join(ROOT, 'build/rapport-controle.json'), JSON.stringify(report, null, 2));
  process.exit(bloquant === 0 ? 0 : 1);
})();
