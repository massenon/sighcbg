/* Captures et MESURES du rendu statique du panneau (voir rendre.php), aux formats Desktop 1440×900, Laptop 1280×720 et 1024×768, Tablette 768×1024, Mobile 390×844.
   Usage : node tests/rendu/capturer.cjs /dossier/des/pages-rendues /dossier/de/sortie [page ...]
   Mesures : débordement horizontal de la PAGE, taille minimale du texte (14 px), cibles tactiles (44 px) sous 1024 px, tiroir (ouverture, Échap, focus rendu).
   Code de sortie 1 si une mesure échoue. Playwright vient de l'environnement (require('playwright')). */
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const [entree, sortie, ...choisies] = process.argv.slice(2);
const FORMATS = [['desktop', 1440, 900], ['laptop', 1280, 720], ['laptop-1024', 1024, 768], ['tablette', 768, 1024], ['mobile', 390, 844]];
fs.mkdirSync(sortie, { recursive: true });
const pages = (choisies.length ? choisies : fs.readdirSync(entree).filter((f) => f.endsWith('.html')).map((f) => f.replace(/\.html$/, ''))).sort();

function mesurer() {
  const r = { debordement: document.documentElement.scrollWidth - window.innerWidth, texteMin: 99, petits: [], cibles: [] };
  const visible = (e) => { const s = getComputedStyle(e), b = e.getBoundingClientRect(); return s.visibility !== 'hidden' && s.display !== 'none' && b.width > 0 && b.height > 0 && b.bottom > 0 && b.right > 0 && b.left < window.innerWidth + 1 && getComputedStyle(e).opacity !== '0'; };
  const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n; (n = w.nextNode());) {
    if (!n.nodeValue.trim()) continue;
    const e = n.parentElement; if (!e || ['SCRIPT', 'STYLE', 'OPTION'].includes(e.tagName) || !visible(e)) continue;
    if (e.closest('svg')) continue;
    const fs = parseFloat(getComputedStyle(e).fontSize);
    if (fs < r.texteMin) r.texteMin = fs;
    if (fs < 14) r.petits.push((e.className || e.tagName) + ':' + fs + ':' + n.nodeValue.trim().slice(0, 30));
  }
  const etroit = window.innerWidth < 1024;
  if (etroit) {
    document.querySelectorAll('a[href], button, input, select, textarea, summary').forEach((e) => {
      if (e.classList.contains('lien-evitement') || !visible(e)) return;
      if (e.matches('p a, li > a:not(.nav-lien), td a, small a') && !e.closest('.ariane')) return; // lien dans une phrase : exempté (WCAG 2.5.8)
      let cible = e; if (e.matches('input[type=checkbox], input[type=radio]')) cible = e.closest('label') || e;
      const b = cible.getBoundingClientRect();
      if (b.height < 43.5) r.cibles.push((e.id || e.className || e.tagName) + ':' + Math.round(b.width) + 'x' + Math.round(b.height));
    });
  }
  return r;
}

(async () => {
  const nav = await chromium.launch();
  const bilan = []; let echecs = 0;
  for (const [nom, l, h] of FORMATS) {
    const ctx = await nav.newContext({ viewport: { width: l, height: h }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    for (const p of pages) {
      await page.goto('file://' + path.resolve(entree, p + '.html'));
      await page.evaluate(() => document.fonts.ready);
      const m = await page.evaluate(mesurer);
      const ko = m.debordement > 0 || m.petits.length > 0 || m.cibles.length > 0;
      if (ko) echecs++;
      bilan.push({ page: p, format: nom, largeur: l, ...m, ok: !ko });
      await page.screenshot({ path: path.join(sortie, `${p}-${nom}.png`), fullPage: false });
      if (['tableau', 'parametres', 'synchronisation', 'connexion', 'satisfaction'].includes(p)) await page.screenshot({ path: path.join(sortie, `${p}-${nom}-complet.png`), fullPage: true });
    }
    // Tiroir (sous 1024 px) : ouverture par le bouton, voile, focus dans la barre, Échap ferme et rend le focus.
    if (l < 1024) {
      await page.goto('file://' + path.resolve(entree, 'tableau.html'));
      const avant = await page.evaluate(() => getComputedStyle(document.getElementById('barre')).visibility);
      await page.click('#menu-ouvrir');
      await page.waitForTimeout(350);
      const ouvert = await page.evaluate(() => ({ visible: getComputedStyle(document.getElementById('barre')).visibility, expanded: document.getElementById('menu-ouvrir').getAttribute('aria-expanded'), focusDansBarre: document.getElementById('barre').contains(document.activeElement), debord: document.documentElement.scrollWidth - innerWidth }));
      await page.screenshot({ path: path.join(sortie, `tiroir-${nom}.png`) });
      await page.keyboard.press('Escape'); await page.waitForTimeout(350);
      const ferme = await page.evaluate(() => ({ visible: getComputedStyle(document.getElementById('barre')).visibility, expanded: document.getElementById('menu-ouvrir').getAttribute('aria-expanded'), focusSurBouton: document.activeElement && document.activeElement.id === 'menu-ouvrir' }));
      await page.click('#menu-ouvrir'); await page.waitForTimeout(350);
      await page.mouse.click(l - 4, 300); await page.waitForTimeout(350);
      const voile = await page.evaluate(() => getComputedStyle(document.getElementById('barre')).visibility);
      const tiroir = { avant, ouvert, ferme, fermeAuVoile: voile };
      const ok = avant === 'hidden' && ouvert.visible === 'visible' && ouvert.expanded === 'true' && ouvert.focusDansBarre && ouvert.debord <= 0 && ferme.visible === 'hidden' && ferme.expanded === 'false' && ferme.focusSurBouton && voile === 'hidden';
      if (!ok) echecs++;
      bilan.push({ page: 'tiroir', format: nom, largeur: l, tiroir, ok });
    }
    await ctx.close();
  }
  await nav.close();
  fs.writeFileSync(path.join(sortie, 'mesures.json'), JSON.stringify(bilan, null, 1));
  for (const b of bilan) if (!b.ok) console.log('ÉCHEC', b.format, b.page, JSON.stringify({ debord: b.debordement, petits: (b.petits || []).slice(0, 4), cibles: (b.cibles || []).slice(0, 6), tiroir: b.tiroir }));
  console.log(`${bilan.length} mesures, ${echecs} échec(s)`);
  process.exit(echecs ? 1 : 0);
})();
