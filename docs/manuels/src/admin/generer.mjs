#!/usr/bin/env node
// GÉNÉRATEUR DU MANUEL ADMINISTRATEUR : HTML/CSS → PDF A4 par Playwright (Chromium), reproductible.
//
//   node docs/manuels/src/admin/generer.mjs [dossier-source] [pdf-de-sortie]
//   (par défaut : docs/manuels/src/admin → docs/manuels/Manuel-administrateur-SIGH-CBG.pdf)
//
// Le dossier source contient :
//   * `manuel.html` : le document (styles dans `manuel.css`) ;
//   * `references.json` : la liste des gestes réservés et des paramètres, EXTRAITE DU CODE par `outils/extraire_references.dart` ;
//   * `images/brut/<nom>.png` et `images/brut/cibles.json` : les captures réelles écrites par `apps/poste/test/capture_admin_test.dart`, avec les
//     rectangles des commandes à désigner.
// Ce que fait le script :
//   1. ANNEXES — les tableaux `<tbody data-ref="gestes">` et `<div data-ref="parametres">` sont remplis depuis `references.json`.
//   2. CAPTURES ANNOTÉES — chaque `<figure class="capture" data-capture="NOM" data-cibles='[{"c":"Libellé","de":"bas"}]'>` devient un SVG : la
//      capture, un cadre rouge et une FLÈCHE rouge numérotée vers chaque cible relevée par le test. `data-recadrage="x,y,l,h"` ne montre qu'une
//      partie. Une cible introuvable ARRÊTE la génération en la nommant : une flèche qui pointe le vide est pire que pas de flèche.
//   3. PAGINATION — premier rendu, lecture du numéro de page de chaque titre (marqueurs invisibles relus par `pdftotext`), second rendu avec les
//      numéros dans la table des matières. Signets du PDF (option `outline` de Chromium) et pied « page X / Y » hors couverture.
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, existsSync, mkdtempSync, rmSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { pathToFileURL, fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  ({ chromium } = require('/opt/node-tools/node_modules/playwright'));
}

const ici = dirname(fileURLToPath(import.meta.url));
const src = resolve(process.argv[2] || ici);
const sortie = resolve(process.argv[3] || join(ici, '..', '..', 'Manuel-administrateur-SIGH-CBG.pdf'));
const pageHtml = join(src, 'manuel.html');
const cibles = JSON.parse(readFileSync(join(src, 'images', 'brut', 'cibles.json'), 'utf8'));
const references = JSON.parse(readFileSync(join(src, 'references.json'), 'utf8'));

const pied = `<div style="width:100%;font-family:Inter,'Liberation Sans',Arial,sans-serif;font-size:8px;color:#64748b;padding:0 20mm;display:flex;justify-content:space-between;">
  <span>SIGH-CBG · Manuel administrateur</span><span>Page <span class="pageNumber"></span> / <span class="totalPages"></span></span></div>`;

/** Dans la page : remplit les annexes, annote les captures, pose les marqueurs de pagination. Rend la liste des erreurs. */
function preparer({ cibles, references, marqueurs }) {
  const NS = 'http://www.w3.org/2000/svg';
  const erreurs = [];
  const esc = (s) => String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);
  const el = (n, a = {}) => {
    const e = document.createElementNS(NS, n);
    for (const [k, v] of Object.entries(a)) e.setAttribute(k, v);
    return e;
  };

  // 1. Annexes générées depuis le code.
  const tg = document.querySelector('[data-ref="gestes"]');
  if (tg) {
    tg.innerHTML = references.gestes
      .map((g) => `<tr><td><code>${esc(g.id)}</code></td><td><strong>${esc(g.libelle)}</strong><br><span class="petit">${esc(g.aide)}</span></td>`
        + `<td>${esc(g.module === '*' ? 'Tous' : g.module)}${g.ecran ? `<br><code>${esc(g.ecran)}</code>` : ''}</td>`
        + `<td>${g.rolesDefaut.length ? g.rolesDefaut.map(esc).join(', ') : (g.suitEcran ? 'Suit la lecture de l’écran' : 'Aucun')}</td></tr>`)
      .join('');
  }
  const dp = document.querySelector('[data-ref="parametres"]');
  if (dp) {
    const parFamille = {};
    for (const p of references.parametres) (parFamille[p.famille] ||= []).push(p);
    const val = (p) => {
      // Un réglage de contact n'affiche jamais de valeur d'attente (E4704) : la clinique la renseigne.
      if (p.contact || String(p.cle).startsWith('support.editeur')) return '<em>à renseigner par la clinique</em>';
      if (p.defaut === '' || p.defaut === null) return '<em>vide</em>';
      if (p.defaut === true) return 'oui';
      if (p.defaut === false) return 'non';
      return esc(p.libellesChoix?.[p.defaut] ?? p.defaut);
    };
    dp.innerHTML = Object.entries(parFamille)
      .map(([f, ps]) => `<h3 class="famille">${esc(references.familles[f] || f)}</h3><table class="tableau ref"><thead><tr><th style="width:34%">Clé</th><th>Paramètre</th><th style="width:15%">Défaut semé</th><th style="width:11%">Bornes</th></tr></thead><tbody>`
        + ps.map((p) => `<tr><td><code>${esc(p.cle)}</code></td><td>${esc(p.libelle)}${p.branche ? '' : ' <span class="pastille">non branché</span>'}${p.geste ? ` <span class="petit">(geste <code>${esc(p.geste)}</code>)</span>` : ''}</td><td>${val(p)}</td><td>${p.min != null && p.max != null ? `${p.min} à ${p.max}` : ''}</td></tr>`).join('')
        + '</tbody></table>')
      .join('');
  }
  // Icônes des encadrés, dessinées en SVG (aucune police d'émoticônes requise).
  const ICONES = {
    info: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="11" fill="#1565C0"/><rect x="10.8" y="10" width="2.4" height="8" rx="1.2" fill="#fff"/><circle cx="12" cy="6.8" r="1.5" fill="#fff"/></svg>',
    attention: '<svg viewBox="0 0 24 24"><path d="M12 1.8 23 21.5H1z" fill="#D32F2F" stroke="#D32F2F" stroke-width="1.5" stroke-linejoin="round"/><rect x="10.8" y="8" width="2.4" height="7.5" rx="1.2" fill="#fff"/><circle cx="12" cy="18.3" r="1.5" fill="#fff"/></svg>',
    bonne: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="11" fill="#15803D"/><path d="M6.5 12.5l3.6 3.6 7.4-7.6" fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    observer: '<svg viewBox="0 0 24 24"><circle cx="10" cy="10" r="7" fill="#F3EEFF" stroke="#6D28D9" stroke-width="2.6"/><path d="M15.2 15.2 21.5 21.5" stroke="#6D28D9" stroke-width="3.2" stroke-linecap="round"/></svg>',
    param: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="7.2" fill="none" stroke="#B45309" stroke-width="4.4" stroke-dasharray="3.1 2.55"/><circle cx="12" cy="12" r="5.6" fill="#B45309"/><circle cx="12" cy="12" r="2.4" fill="#FFF7E6"/></svg>',
  };
  const TITRES = { info: 'Information', attention: 'Attention', bonne: 'Bonne pratique', observer: 'Où observer', param: 'Paramétrage' };
  for (const e of document.querySelectorAll('.encadre')) {
    const type = Object.keys(ICONES).find((k) => e.classList.contains(k));
    if (!type) continue;
    const corps = document.createElement('div');
    corps.className = 'corps';
    while (e.firstChild) corps.append(e.firstChild);
    if (!corps.querySelector('.titre')) {
      const t = document.createElement('span');
      t.className = 'titre';
      t.textContent = e.dataset.titre || TITRES[type];
      corps.prepend(t);
    }
    const ico = document.createElement('div');
    ico.className = 'ico';
    ico.innerHTML = ICONES[type];
    e.append(ico, corps);
  }
  for (const n of document.querySelectorAll('[data-compte]')) {
    n.textContent = String(references[n.dataset.compte]?.length ?? '?');
  }

  // 2. Captures annotées.
  for (const fig of document.querySelectorAll('figure.capture')) {
    const nom = fig.dataset.capture;
    const r = cibles[nom];
    if (!r) {
      erreurs.push(`capture inconnue : ${nom}`);
      continue;
    }
    const W = r.largeur, H = r.hauteur;
    const [cx, cy, cw, ch] = (fig.dataset.recadrage || `0,0,${W},${H}`).split(',').map(Number);
    const liste = JSON.parse(fig.dataset.cibles || '[]');
    const svg = el('svg', { viewBox: `${cx} ${cy} ${cw} ${ch}`, class: 'capture-svg', role: 'img' });
    svg.append(el('image', { href: `images/brut/${nom}.png`, x: 0, y: 0, width: W, height: H, preserveAspectRatio: 'none' }));
    const k = cw / 1500;
    liste.forEach((c, i) => {
      const rect = c.rect || r.cibles[c.c];
      if (!rect) {
        erreurs.push(`${nom} : cible introuvable « ${c.c} »`);
        return;
      }
      const [x, y, w, h] = rect;
      const m = 5 * k;
      svg.append(el('rect', { x: x - m, y: y - m, width: w + 2 * m, height: h + 2 * m, rx: 7 * k, fill: 'none', stroke: '#D32F2F', 'stroke-width': 3.5 * k }));
      const mx = x + w / 2, my = y + h / 2;
      let de = c.de;
      if (!de) {
        const place = { bas: cy + ch - (y + h), haut: y - cy, gauche: x - cx, droite: cx + cw - (x + w) };
        de = Object.entries(place).sort((a, b) => b[1] - a[1])[0][0];
      }
      const L = (c.long || 110) * k, d = 0.5;
      let x1, y1, x2, y2;
      if (de === 'bas') { x2 = mx; y2 = y + h + m + 2 * k; x1 = mx + L * d; y1 = y2 + L; }
      else if (de === 'haut') { x2 = mx; y2 = y - m - 2 * k; x1 = mx - L * d; y1 = y2 - L; }
      else if (de === 'gauche') { x2 = x - m - 2 * k; y2 = my; x1 = x2 - L; y1 = my + L * d; }
      else { x2 = x + w + m + 2 * k; y2 = my; x1 = x2 + L; y1 = my + L * d; }
      const ang = Math.atan2(y2 - y1, x2 - x1);
      const tete = 22 * k, ouv = 0.42;
      const bx = x2 - Math.cos(ang) * tete * 0.8, by = y2 - Math.sin(ang) * tete * 0.8;
      svg.append(el('line', { x1, y1, x2: bx, y2: by, stroke: '#D32F2F', 'stroke-width': 6 * k, 'stroke-linecap': 'round' }));
      svg.append(el('polygon', {
        points: `${x2},${y2} ${x2 - tete * Math.cos(ang - ouv)},${y2 - tete * Math.sin(ang - ouv)} ${x2 - tete * Math.cos(ang + ouv)},${y2 - tete * Math.sin(ang + ouv)}`,
        fill: '#D32F2F',
      }));
      const R = 19 * k;
      const px = x1 - Math.cos(ang) * R * 0.6, py = y1 - Math.sin(ang) * R * 0.6;
      svg.append(el('circle', { cx: px, cy: py, r: R, fill: '#D32F2F', stroke: '#fff', 'stroke-width': 3.5 * k }));
      const t = el('text', { x: px, y: py + 7.5 * k, 'text-anchor': 'middle', 'font-size': 21 * k, 'font-weight': 700, fill: '#fff', 'font-family': 'Inter, Arial, sans-serif' });
      t.textContent = String(c.n || i + 1);
      svg.append(t);
    });
    fig.prepend(svg);
  }

  // Chemins de menu (éléments en gras) et flux d'action, séparés par ➔.
  for (const n of document.querySelectorAll('.ch, .flux')) {
    const parts = n.textContent.split('➔').map((s) => s.trim());
    const gras = n.classList.contains('ch');
    n.innerHTML = parts.map((p) => (gras ? `<strong>${esc(p)}</strong>` : esc(p))).join('<span class="fleche">➔</span>');
  }

  // Table des matières : h1 et h2 numérotés, liens internes.
  const toc = document.querySelector('nav.toc[data-auto] > ol');
  if (toc) {
    let li = null, sous = null;
    for (const h of document.querySelectorAll('h1[id], h2[id]')) {
      if (h.closest('nav.toc') || h.closest('.couverture')) continue;
      const texte = h.textContent.replace(/\s+/g, ' ').trim();
      const a = `<a href="#${h.id}"><span class="t">${esc(texte)}</span><span class="pts"></span><span class="num"></span></a>`;
      if (h.tagName === 'H1') {
        li = document.createElement('li');
        li.innerHTML = a;
        toc.append(li);
        sous = null;
      } else if (li) {
        if (!sous) { sous = document.createElement('ol'); li.append(sous); }
        const s = document.createElement('li');
        s.innerHTML = a;
        sous.append(s);
      }
    }
  }

  // 3. Marqueurs de pagination (texte minuscule et blanc juste après chaque titre numéroté).
  if (marqueurs) {
    for (const h of document.querySelectorAll('h1[id], h2[id]')) {
      const s = document.createElement('div');
      s.className = 'marqueur-page';
      s.textContent = `QQP${h.id.replace(/[^a-z0-9]/gi, '')}QQ`;
      h.after(s);
    }
  }
  const titres = [...document.querySelectorAll('h1[id], h2[id]')]
    .filter((h) => !h.closest('.couverture'))
    .map((h) => [h.tagName === 'H1' ? 1 : 2, h.textContent.replace(/\s+/g, ' ').trim(), h.id.replace(/[^a-z0-9]/gi, '')]);
  return { erreurs, titres };
}

let titres = [];
async function rendre(navigateur, numeros) {
  const page = await navigateur.newPage();
  await page.goto(pathToFileURL(pageHtml).href, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  const prep = await page.evaluate(preparer, { cibles, references, marqueurs: true });
  const erreurs = prep.erreurs;
  titres = prep.titres;
  if (erreurs.length) {
    console.error(erreurs.join('\n'));
    process.exit(1);
  }
  if (numeros) {
    await page.evaluate((num) => {
      for (const a of document.querySelectorAll('nav.toc a[href^="#"]')) {
        const n = num[a.getAttribute('href').slice(1).replace(/[^a-z0-9]/gi, '')];
        const s = a.querySelector('.num');
        if (s && n) s.textContent = String(n);
      }
    }, numeros);
  }
  const pdf = await page.pdf({
    format: 'A4',
    printBackground: true,
    preferCSSPageSize: true,
    displayHeaderFooter: true,
    headerTemplate: '<span></span>',
    footerTemplate: pied,
    margin: { top: '18mm', bottom: '18mm', left: '20mm', right: '20mm' },
    outline: false,
    tagged: true,
  });
  await page.close();
  return pdf;
}

/** La seule couverture, sans pied ni en-tête. */
async function rendreCouverture(navigateur) {
  const page = await navigateur.newPage();
  await page.goto(pathToFileURL(pageHtml).href, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(() => {
    const c = document.querySelector('.couverture');
    document.body.replaceChildren(c);
  });
  const pdf = await page.pdf({ format: 'A4', printBackground: true, preferCSSPageSize: true, margin: { top: 0, bottom: 0, left: 0, right: 0 } });
  await page.close();
  return pdf;
}

const navigateur = await chromium.launch();
const tmp = mkdtempSync(join(tmpdir(), 'manuel-admin-'));
try {
  const brouillon = await rendre(navigateur, null);
  const f = join(tmp, 'brouillon.pdf');
  writeFileSync(f, brouillon);
  const texte = execFileSync('pdftotext', ['-layout', f, '-'], { maxBuffer: 64 * 1024 * 1024 }).toString();
  const numeros = {};
  texte.split('\f').forEach((p, i) => {
    for (const m of p.matchAll(/QQP([A-Za-z0-9]+)QQ/g)) numeros[m[1]] ??= i + 1;
  });
  const final = await rendre(navigateur, numeros);
  writeFileSync(sortie, final);
  // La COUVERTURE sans pied de page : une page rendue à part remplace la première ; signets et liens internes sont conservés.
  const couverture = await rendreCouverture(navigateur);
  const fc = join(tmp, 'couverture.pdf');
  writeFileSync(fc, couverture);
  execFileSync('python3', ['-I', '-c', `
import sys, pymupdf
doc = pymupdf.open(sys.argv[1]); cov = pymupdf.open(sys.argv[2])
import json
toc = [[1, 'Couverture', 1]] + [[n, t, p] for n, t, p in json.loads(sys.argv[4])]
doc.delete_page(0); doc.insert_pdf(cov, from_page=0, to_page=0, start_at=0)
doc.set_toc(toc)
doc.set_metadata({'title': 'Manuel administrateur SIGH-CBG', 'author': 'SIGH-CBG', 'subject': 'Installation, mise en service et administration', 'creator': 'docs/manuels/src/admin/generer.mjs'})
doc.save(sys.argv[3], garbage=3, deflate=True)
`, sortie, fc, join(tmp, 'final.pdf'), JSON.stringify(titres.filter((t) => numeros[t[2]]).map(([n, t, id]) => [n, t, numeros[id]]))]);
  writeFileSync(sortie, readFileSync(join(tmp, 'final.pdf')));
  const pages = (execFileSync('pdfinfo', [sortie]).toString().match(/Pages:\s+(\d+)/) || [])[1];
  console.log(`${sortie} : ${pages} pages, ${Object.keys(numeros).length} titres paginés.`);
} finally {
  await navigateur.close();
  rmSync(tmp, { recursive: true, force: true });
}
