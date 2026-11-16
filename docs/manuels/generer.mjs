#!/usr/bin/env node
// GÉNÉRATEUR COMMUN DES MANUELS SIGH-CBG : HTML/CSS → PDF A4 par Playwright (Chromium), reproductible.
//
//   node docs/manuels/generer.mjs <dossier-source> <pdf-de-sortie>
//   ex. node docs/manuels/generer.mjs docs/manuels/src/utilisateur docs/manuels/Manuel-utilisateur-SIGH-CBG.pdf
//
// Le dossier source contient `manuel.html` (le document) et, au besoin, `captures/<nom>.png` + `captures/<nom>.json` (repères écrits par un test de
// capture Flutter : rectangles des boutons, des clés, des infobulles). Ce que fait le script :
//   1. CAPTURES ANNOTÉES — chaque `<figure class="capture" data-capture="captures/NOM" data-cibles='[…]'>` devient un SVG : la capture, un cadre et une
//      FLÈCHE rouge vers chaque cible, et une pastille numérotée. Une cible se désigne par `{"bouton":"Libellé"}`, `{"cle":"cle-flutter"}`,
//      `{"info":"Infobulle"}`, `{"onglet":"Libellé"}` ou `{"rect":[x,y,l,h]}` (coordonnées logiques de l'écran), avec `"de":"haut|bas|gauche|droite"`
//      (côté d'où vient la flèche) et `"n"` (rang parmi les homonymes). `data-recadrage="x,y,l,h"` ne montre qu'une partie de l'écran. Une cible
//      introuvable ARRÊTE la génération en la nommant : une flèche qui pointe le vide est pire que pas de flèche.
//   2. PAGINATION — premier rendu, lecture du numéro de page de chaque titre (marqueurs invisibles `§P<id>§` relus par `pdftotext`), puis second rendu
//      avec les numéros dans la table des matières (liens internes dans les deux cas). Sans `pdftotext`, la table garde ses liens sans numéros.
//   3. SIGNETS — le plan du PDF suit les titres h1/h2 (option `outline` de Chromium) ; pied de page « page X / Y ».
//   4. INCLUSIONS — une ligne `<!-- INCLURE fichier.html -->` est remplacée par le contenu du fichier (chemin relatif au dossier source ; s'il est un
//      document complet, seul le contenu de son <body>, ou de son <main>, est repris). Fichier ABSENT : la directive disparaît sans erreur (l'annexe
//      « Catalogue de tous les écrans » n'existe pas toujours). Les captures des fichiers inclus suivent les mêmes règles que celles du manuel.
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, existsSync, readdirSync, mkdtempSync, rmSync } from 'node:fs';
import { resolve, join, dirname, basename } from 'node:path';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const [, , srcArg, sortieArg] = process.argv;
if (!srcArg || !sortieArg) {
  console.error('Usage : node docs/manuels/generer.mjs <dossier-source> <pdf-de-sortie>');
  process.exit(2);
}
const src = resolve(srcArg);
const sortie = resolve(sortieArg);
const page_html = join(src, 'manuel.html');
if (!existsSync(page_html)) {
  console.error(`Introuvable : ${page_html}`);
  process.exit(2);
}

// Les repères des captures, lus côté Node (le navigateur ne lit pas file:// par fetch).
const reperes = {};
const dossierCaptures = join(src, 'captures');
if (existsSync(dossierCaptures)) {
  for (const f of readdirSync(dossierCaptures)) {
    if (f.endsWith('.json')) reperes[`captures/${f.replace(/\.json$/, '')}`] = JSON.parse(readFileSync(join(dossierCaptures, f), 'utf8'));
  }
}

// Les inclusions : le document assemblé est écrit à côté du manuel (même dossier, donc mêmes chemins relatifs pour les images et la feuille de style),
// sous un nom temporaire supprimé à la fin.
function inclure(texte) {
  return texte.replace(/<!--\s*INCLURE\s+([^\s>]+)\s*-->/g, (_, nom) => {
    const f = join(src, nom);
    if (!existsSync(f)) {
      console.warn(`Inclusion absente (ignorée) : ${nom}`);
      return '';
    }
    let contenu = readFileSync(f, 'utf8');
    const corps = contenu.match(/<main[^>]*>([\s\S]*)<\/main>/i) || contenu.match(/<body[^>]*>([\s\S]*)<\/body>/i);
    if (corps) contenu = corps[1];
    console.log(`Inclusion : ${nom} (${(contenu.length / 1024).toFixed(0)} Ko)`);
    return contenu;
  });
}
const html = inclure(readFileSync(page_html, 'utf8'));
const page_assemblee = join(src, `.manuel-assemble-${process.pid}.html`);
writeFileSync(page_assemblee, html);
process.on('exit', () => rmSync(page_assemblee, { force: true }));
const pied = (html.match(/<meta name="pied" content="([^"]*)"/) || [])[1] || 'SIGH-CBG';

const piedTemplate = `<div style="width:100%;font-family:'Liberation Sans',Arial,sans-serif;font-size:8.5px;color:#64748b;padding:0 18mm;display:flex;justify-content:space-between;">
  <span>${pied}</span><span>Page <span class="pageNumber"></span> / <span class="totalPages"></span></span></div>`;

/** Dans la page : annote les captures, pose les marqueurs de pagination. Rend la liste des erreurs. */
function preparer({ reperes }) {
  const NS = 'http://www.w3.org/2000/svg';
  const erreurs = [];
  const el = (n, a = {}) => {
    const e = document.createElementNS(NS, n);
    for (const [k, v] of Object.entries(a)) e.setAttribute(k, v);
    return e;
  };
  for (const fig of document.querySelectorAll('figure.capture')) {
    const nom = fig.dataset.capture;
    const r = reperes[nom];
    if (!r) {
      erreurs.push(`capture sans repères : ${nom}`);
      continue;
    }
    const [W, H] = r.taille;
    let [cx, cy, cw, ch] = (fig.dataset.recadrage || `0,0,${W},${H}`).split(',').map(Number);
    const cibles = JSON.parse(fig.dataset.cibles || '[]');
    const svg = el('svg', { viewBox: `${cx} ${cy} ${cw} ${ch}`, class: 'capture-svg', role: 'img' });
    const defs = el('defs');
    const clip = el('clipPath', { id: `clip-${Math.random().toString(36).slice(2)}` });
    clip.append(el('rect', { x: cx, y: cy, width: cw, height: ch, rx: 0 }));
    defs.append(clip);
    svg.append(defs);
    const img = el('image', { href: `${nom}.png`, x: 0, y: 0, width: W, height: H, preserveAspectRatio: 'none' });
    svg.append(img);
    // Échelle de dessin : épaisseurs et pastilles constantes à l'impression, quelle que soit la largeur recadrée.
    const k = (cw / (r.largeurReference || 1440)) * 1.35;
    cibles.forEach((c, i) => {
      let rect = null;
      const n = c.n || 0;
      if (c.rect) rect = c.rect;
      else if (c.bouton) rect = (r.boutons.filter((b) => b.libelle === c.bouton)[n] || {}).rect;
      else if (c.cle) rect = r.cles[c.cle];
      else if (c.info) rect = (r.infobulles.filter((b) => b.message === c.info)[n] || {}).rect;
      else if (c.onglet) rect = (r.onglets.filter((b) => b.libelle === c.onglet)[n] || {}).rect;
      if (!rect) {
        erreurs.push(`${nom} : cible introuvable ${JSON.stringify(c)}`);
        return;
      }
      const [x, y, w, h] = rect;
      const m = 4 * k;
      svg.append(el('rect', { x: x - m, y: y - m, width: w + 2 * m, height: h + 2 * m, rx: 6 * k, fill: 'none', stroke: '#D32F2F', 'stroke-width': 3 * k }));
      // La flèche vient du côté demandé, sinon du côté où il y a le plus de place dans le cadre visible.
      const mx = x + w / 2, my = y + h / 2;
      let de = c.de;
      if (!de) {
        const place = { bas: cy + ch - (y + h), haut: y - cy, gauche: x - cx, droite: cx + cw - (x + w) };
        de = Object.entries(place).sort((a, b) => b[1] - a[1])[0][0];
      }
      const L = (c.long || 90) * k;
      const d = 0.55; // inclinaison légère : la flèche se lit mieux en biais
      const R = 15 * k;
      const trace = (cote) => {
        if (cote === 'bas') return [mx + L * d, y + h + m + 2 * k + L, mx, y + h + m + 2 * k];
        if (cote === 'haut') return [mx - L * d, y - m - 2 * k - L, mx, y - m - 2 * k];
        if (cote === 'gauche') return [x - m - 2 * k - L, my + L * d, x - m - 2 * k, my];
        return [x + w + m + 2 * k + L, my + L * d, x + w + m + 2 * k, my];
      };
      // La pastille doit rester DANS le cadre visible : sinon la flèche change de côté.
      const dedans = ([px, py]) => px - 1.6 * R >= cx && px + 1.6 * R <= cx + cw && py - 1.6 * R >= cy && py + 1.6 * R <= cy + ch;
      if (!dedans(trace(de))) de = ['bas', 'gauche', 'droite', 'haut'].find((cote) => dedans(trace(cote))) || de;
      let [x1, y1, x2, y2] = trace(de);
      const ang = Math.atan2(y2 - y1, x2 - x1);
      const tete = 16 * k, ouv = 0.45;
      const bx = x2 - Math.cos(ang) * tete * 0.8, by = y2 - Math.sin(ang) * tete * 0.8;
      svg.append(el('line', { x1, y1, x2: bx, y2: by, stroke: '#D32F2F', 'stroke-width': 5 * k, 'stroke-linecap': 'round' }));
      svg.append(el('polygon', {
        points: `${x2},${y2} ${x2 - tete * Math.cos(ang - ouv)},${y2 - tete * Math.sin(ang - ouv)} ${x2 - tete * Math.cos(ang + ouv)},${y2 - tete * Math.sin(ang + ouv)}`,
        fill: '#D32F2F',
      }));
      const px = x1 + Math.cos(ang) * -R * 0.6, py = y1 + Math.sin(ang) * -R * 0.6;
      svg.append(el('circle', { cx: px, cy: py, r: R, fill: '#D32F2F', stroke: '#fff', 'stroke-width': 3 * k }));
      const t = el('text', { x: px, y: py + 6 * k, 'text-anchor': 'middle', 'font-size': 17 * k, 'font-weight': 700, fill: '#fff', 'font-family': 'Liberation Sans, Arial, sans-serif' });
      t.textContent = String(c.num || i + 1);
      svg.append(t);
    });
    fig.prepend(svg);
  }
  // Table des matières ENGENDRÉE des titres (h1 et h2 du contenu) : elle ne peut pas diverger du document. Un titre sans id en reçoit un.
  const liste = document.getElementById('tdm-liste');
  if (liste) {
    const slug = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    const vus = new Set();
    let courant = null;
    for (const h of document.querySelectorAll('main h1, main h2')) {
      if (h.closest('.hors-tdm')) continue;
      if (!h.id) {
        let id = slug(h.textContent).slice(0, 60) || 'titre';
        while (vus.has(id)) id += '-';
        h.id = id;
      }
      vus.add(h.id);
      const li = document.createElement('li');
      const a = document.createElement('a');
      a.href = `#${h.id}`;
      a.innerHTML = `<span class="t"></span><span class="points"></span><span class="tdm-page" data-cible="${h.id}">00</span>`;
      a.querySelector('.t').textContent = h.textContent.replace(/\s+/g, ' ').trim();
      li.append(a);
      if (h.tagName === 'H1') {
        liste.append(li);
        courant = document.createElement('ol');
        li.append(courant);
      } else if (courant) courant.append(li);
    }
    for (const ol of liste.querySelectorAll('ol')) if (!ol.children.length) ol.remove();
  }
  // Un titre ne reste jamais seul en bas de page : il est groupé avec les deux blocs qui le suivent dans un conteneur insécable (Chromium ignore
  // `break-after: avoid` entre un titre et un bloc conteneur). Un bloc `.tache` est d'abord déplié pour que son premier paragraphe rejoigne le titre.
  for (const h of document.querySelectorAll('main h2, main h3')) {
    const suivant = h.nextElementSibling;
    if (suivant && suivant.classList.contains('tache')) suivant.replaceWith(...suivant.childNodes);
    const groupe = document.createElement('div');
    groupe.className = 'groupe-titre';
    h.before(groupe);
    groupe.append(h);
    let pris = 0;
    while (pris < 2 && groupe.nextElementSibling && !/^H[123]$/.test(groupe.nextElementSibling.tagName)) {
      const e = groupe.nextElementSibling;
      if (pris >= 1 && e.matches('figure, table, ol.etapes')) break;
      groupe.append(e);
      pris++;
    }
  }
  // Marqueurs de pagination : un texte minuscule et blanc juste après chaque titre numéroté (jamais dans le titre : il polluerait les signets).
  for (const h of document.querySelectorAll('main h1[id], main h2[id]')) {
    const s = document.createElement('div');
    s.className = 'marqueur-page';
    s.textContent = `§P${h.id}§`;
    h.after(s);
  }
  return erreurs;
}

async function rendre(navigateur, numeros, masquer = false) {
  const page = await navigateur.newPage();
  await page.goto(pathToFileURL(page_assemblee).href, { waitUntil: 'load' });
  const erreurs = await page.evaluate(preparer, { reperes });
  if (erreurs.length) {
    console.error(erreurs.join('\n'));
    process.exit(1);
  }
  if (numeros) {
    await page.evaluate((num) => {
      for (const s of document.querySelectorAll('.tdm-page')) s.textContent = num[s.dataset.cible] ?? '';
    }, numeros);
  }
  // Rendu final : marqueurs masqués (même place, donc même pagination, mais plus aucun texte parasite dans le PDF).
  if (masquer) await page.addStyleTag({ content: '.marqueur-page{visibility:hidden}' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(300);
  const pdf = await page.pdf({
    format: 'A4',
    printBackground: true,
    preferCSSPageSize: true,
    displayHeaderFooter: true,
    headerTemplate: '<div></div>',
    footerTemplate: piedTemplate,
    outline: true,
    tagged: true,
  });
  await page.close();
  return pdf;
}

function paginer(pdf) {
  try {
    execFileSync('pdftotext', ['-v'], { stdio: 'ignore' });
  } catch {
    console.warn('pdftotext absent : la table des matières garde ses liens, sans numéros de page.');
    return null;
  }
  const tmp = mkdtempSync(join(tmpdir(), 'manuel-'));
  try {
    const f = join(tmp, 'm.pdf');
    writeFileSync(f, pdf);
    const texte = execFileSync('pdftotext', ['-enc', 'UTF-8', f, '-'], { maxBuffer: 64 * 1024 * 1024 }).toString('utf8');
    const pages = texte.split('\f');
    const num = {};
    pages.forEach((p, i) => {
      for (const m of p.replace(/\s+/g, '').matchAll(/§P([^§]+)§/g)) num[m[1]] ??= String(i + 1);
    });
    return { num, total: pages.filter((p) => p.trim()).length };
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

const navigateur = await chromium.launch();
try {
  let pdf = await rendre(navigateur, null);
  const p1 = paginer(pdf);
  if (p1) {
    pdf = await rendre(navigateur, p1.num);
    const p2 = paginer(pdf);
    const derives = Object.keys(p1.num).filter((k) => p2.num[k] !== p1.num[k]);
    // Les numéros ont pu décaler la mise en page (rare) : on retient alors ceux relus au second rendu.
    if (derives.length) console.warn(`Numéros relus au second rendu pour : ${derives.join(', ')}`);
    pdf = await rendre(navigateur, derives.length ? p2.num : p1.num, true);
    console.log(`${Object.keys(p1.num).length} titres paginés.`);
  }
  writeFileSync(sortie, pdf);
  console.log(`PDF écrit : ${sortie} (${(pdf.length / 1024 / 1024).toFixed(1)} Mo)`);
} finally {
  await navigateur.close();
}
