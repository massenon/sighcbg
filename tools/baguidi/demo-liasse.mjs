#!/usr/bin/env node
// DONNÉES DE DÉMONSTRATION BAGUIDI pour la liasse fiscale et le classeur 2025 (décision de la Direction du 08/11/2026 : aucune donnée de Nassiera Too).
//
// Les trois constantes Dart `cpb_liasse.dart`, `cpc_liasse.dart` (liasse déposée) et `cpc_donnees.dart` (classeur 2025) portaient les chiffres d'une AUTRE clinique.
// Ce script les remplace par un jeu de DÉMONSTRATION : dénomination et IFU lus de l'identité Baguidi, code de dépôt « DEMO », date de dépôt au 30/04/2026
// (l'échéance de dépôt des états financiers), et TOUS les montants multipliés par un même entier (3). Une multiplication par un entier conserve toutes
// les identités comptables (sous-totaux, totaux, contrôles, marge commerciale nulle, les six écarts internes du document) : les tests qui comparent restent possibles.
// Ne sont PAS multipliés : les années, les comptes, les pourcentages de variation (ils ne changent pas), le nombre de postes sans compte, les objectifs de pilotage.
//
// IDEMPOTENT : chaque fichier traité porte la ligne-marqueur MARQUEUR ; un fichier marqué n'est jamais multiplié une seconde fois.
// REJOUABLE à vide : `node tools/baguidi/demo-liasse.mjs --verifier` ne modifie rien et dit 0 si tout est déjà transformé (exit 1 sinon).
// Les fichiers de test (vecteurs et attentes) qui citent ces valeurs sont réécrits par la MÊME transformation (voir CIBLES_TEXTE).
import { readFileSync, writeFileSync } from 'node:fs';

const FACTEUR = 3;
const MARQUEUR = `// DÉMONSTRATION BAGUIDI (tools/baguidi/demo-liasse.mjs) : montants d’origine multipliés par ${FACTEUR}, code de dépôt DEMO. Ne pas rejouer à la main : le script est idempotent.`;
const verifier = process.argv.includes('--verifier');

const lire = (p) => readFileSync(p, 'utf8');
const identite = lire('packages/domaine/lib/src/impression/identite.dart');
const nom = identite.match(/'nom': '([^']+)'/)[1];
const ifu = identite.match(/'ifu': '([^']+)'/)[1];
const DEPOT = { denomination: nom, ifu, dateDepot: '2026-04-30', code: 'DEMO' };
const SOURCE = 'Liasse de démonstration (code DEMO) : données fictives, à remplacer par la liasse réellement déposée par la clinique';
const MENTION = 'Données de démonstration, à remplacer par la liasse réellement déposée par la clinique';

const CLES = new Set(['brut', 'amort', 'net', 'netN1', 'n', 'n1']);
const x3 = (v) => Math.round(v * FACTEUR * 100) / 100;

// Nombres écrits en toutes lettres de chiffres dans un texte (« 43 450 392 », « −2 632 175 », « 450 F ») : groupés par espace fine ou insécable.
const SEP = '[\\u00a0\\u202f ]';
const NOMBRE = new RegExp(`(\\d{1,3}(?:${SEP}\\d{3})+)|(\\d{1,3})(?=${SEP}F\\b)`, 'g');
function multTexte(t) {
  return t.replace(NOMBRE, (m, groupe) => {
    const sep = (m.match(/[   ]/) || [' '])[0];
    const n = Number(m.replace(/[   ]/g, ''));
    const r = String(x3(n));
    return r.replace(/\B(?=(\d{3})+(?!\d))/g, sep);
  });
}

function multObjet(o, dansDepot) {
  if (Array.isArray(o)) return o.map((v) => multObjet(v, dansDepot));
  if (o && typeof o === 'object') {
    const r = {};
    for (const [k, v] of Object.entries(o)) {
      if (typeof v === 'number' && CLES.has(k)) r[k] = x3(v);
      else if (k === 'constat' && typeof v === 'string') r[k] = multTexte(v);
      else r[k] = multObjet(v, dansDepot);
    }
    return r;
  }
  return o;
}

function transformerLiasseJson(j) {
  const sortie = multObjet(j);
  sortie.DEPOT = { ...j.DEPOT, ...DEPOT, source: SOURCE, demonstration: MENTION };
  return sortie;
}

let modifies = 0;
function ecrire(p, t) { modifies++; if (!verifier) writeFileSync(p, t); console.log(`${verifier ? 'à transformer' : 'transformé'} : ${p}`); }

// 1. cpc_liasse.dart : la liasse en JSON
{
  const p = 'packages/domaine/lib/src/comptabilite/cpc_liasse.dart';
  const s = lire(p);
  if (!s.includes(MARQUEUR)) {
    const m = s.match(/(const String cpcLiasseJson = r''')([\s\S]*?)(''';)/);
    const j = transformerLiasseJson(JSON.parse(m[2]));
    const tete = s.slice(0, s.indexOf('const String cpcLiasseJson')).replace(/^\/\/ FICHIER ENGENDRÉ[^\n]*\n/, '').replace(/^\/\/ La liasse fiscale DÉPOSÉE[^\n]*\n/, '');
    ecrire(p, `${MARQUEUR}\n// Liasse fiscale de DÉMONSTRATION : structure du formulaire (références, libellés, ordre) et valeurs fictives. Des faits de démonstration : ils se citent, ne se recalculent pas.\n${tete}${m[1]}${JSON.stringify(j)}${m[3]}${s.slice(s.indexOf(m[0]) + m[0].length)}`);
  }
}

// 2. cpc_donnees.dart : classeur 2025 (les objectifs de pilotage ne sont pas des montants : intacts)
{
  const p = 'packages/domaine/lib/src/comptabilite/cpc_donnees.dart';
  const s = lire(p);
  if (!s.includes(MARQUEUR)) {
    const m = s.match(/(const String cpcExercice2025Json = r''')([\s\S]*?)(''';)/);
    const j = JSON.parse(m[2]);
    const montants = (o) => {
      if (Array.isArray(o)) return o.map(montants);
      if (typeof o === 'number') return x3(o);
      if (o && typeof o === 'object') return Object.fromEntries(Object.entries(o).map(([k, v]) => [k, k === 'postesSansCompte' ? v : montants(v)]));
      return o;
    };
    const t = { ...j };
    for (const k of ['chiffreAffaires', 'totalChiffreAffaires', 'depenses', 'totalDepenses', 'totalHorsExploitation', 'totalCharges', 'resultat', 'controle']) t[k] = montants(j[k]);
    t.depenses = j.depenses.map((d) => ({ ...d, mois: d.mois.map(x3), total: x3(d.total) }));
    ecrire(p, s.replace(/^\/\/ FICHIER ENGENDRÉ[^\n]*\n/, `${MARQUEUR}\n// Classeur 2025 de DÉMONSTRATION (montants fictifs). Les objectifs de pilotage ci-dessous ne sont pas des montants : inchangés.\n`).replace(m[0], m[1] + JSON.stringify(t) + m[3]));
  }
}

// 3. cpb_liasse.dart : la même liasse, en littéral Dart (une valeur par ligne)
{
  const p = 'packages/domaine/lib/src/comptabilite/cpb_liasse.dart';
  const s = lire(p);
  if (!s.includes(MARQUEUR)) {
    const lignes = s.split('\n');
    let dansDepot = false;
    const sortie = lignes.map((l) => {
      if (/^ {2}'DEPOT': \{/.test(l)) dansDepot = true;
      else if (dansDepot && /^ {2}\},/.test(l)) dansDepot = false;
      if (dansDepot) {
        if (/^ {4}'denomination':/.test(l)) return `    'denomination': '${DEPOT.denomination}',`;
        if (/^ {4}'ifu':/.test(l)) return `    'ifu': '${DEPOT.ifu}',`;
        if (/^ {4}'dateDepot':/.test(l)) return `    'dateDepot': '${DEPOT.dateDepot}',`;
        if (/^ {4}'code':/.test(l)) return `    'code': '${DEPOT.code}',`;
        if (/^ {4}'source':/.test(l)) return `    'source': '${SOURCE}',\n    'demonstration': '${MENTION}',`;
        return l;
      }
      const v = l.match(/^(\s*)'(brut|amort|net|netN1|n|n1)': (-?\d+(?:\.\d+)?),$/);
      if (v) return `${v[1]}'${v[2]}': ${x3(Number(v[3]))},`;
      const c = l.match(/^(\s*'constat': ')(.*)(',)$/);
      if (c) return c[1] + multTexte(c[2]) + c[3];
      return l;
    });
    const tete = [MARQUEUR, '// La liasse fiscale de DÉMONSTRATION (code DEMO) : structure du formulaire ET valeurs fictives (exercice N = 2025, N-1 = 2024). Des faits de démonstration : ils se citent.', '// Les écarts internes du document (`ECARTS`) sont CONSERVÉS, non arbitrés.'];
    ecrire(p, [...tete, ...sortie.slice(3)].join('\n'));
  }
}


// 4. Vecteurs de test qui CITENT les valeurs de la liasse et du classeur (écrans de la maquette rejoués). Les anciens montants se déduisent des constantes
// déjà transformées (ancien = nouveau / 3, exact : le nouveau est arrondi au centime). Seuls les montants d'au moins 1 000 sont réécrits, et seulement dans les ZONES des
// vecteurs qui portent des valeurs déposées (voir VECTEURS). Les pourcentages DÉRIVÉS d'une comparaison entre une valeur
// déposée (multipliée) et une valeur calculée du journal (non multipliée) ne se retrouvent pas par multiplication : ils sont corrigés à part dans les tests.
const MARQUEUR_VECTEUR = '"_demoLiasse"';
const CLES_MONTANTS = new Set([...CLES, 'chiffreAffaires', 'mois', 'total', 'totalChiffreAffaires', 'totalDepenses', 'totalHorsExploitation', 'totalCharges', 'resultat', 'totalDetail', 'totalClasseur', 'ecart', 'montantSansCompte']);
const nouveaux = new Set();
{
  const collecte = (o, cle) => {
    if (Array.isArray(o)) o.forEach((v) => collecte(v, cle));
    else if (o && typeof o === 'object') { for (const [k, v] of Object.entries(o)) if (k !== 'annee' && k !== 'postesSansCompte' && k !== 'variation') collecte(v, k); }
    else if (typeof o === 'number' && CLES_MONTANTS.has(cle)) nouveaux.add(o);
  };
  const liasse = JSON.parse(lire('packages/domaine/lib/src/comptabilite/cpc_liasse.dart').match(/cpcLiasseJson = r'''([\s\S]*?)'''/)[1]);
  const classeur = JSON.parse(lire('packages/domaine/lib/src/comptabilite/cpc_donnees.dart').match(/cpcExercice2025Json = r'''([\s\S]*?)'''/)[1]);
  for (const k of Object.keys(liasse)) if (k !== 'DEPOT') collecte(liasse[k], '');
  collecte(classeur, '');
}
// ancien arrondi → nouveau exact
const CORRESPONDANCE = new Map();
for (const nv of nouveaux) {
  const ancien = Math.round(nv * 100 / FACTEUR) / 100;
  if (Math.abs(ancien) >= 1000) CORRESPONDANCE.set(Math.abs(Math.round(ancien)), Math.abs(nv));
}
// Les nombres des textes d'écart (sommes recalculées, ZH…) ne sont portés par aucune clé : on les lit dans les textes déjà transformés.
{
  const liasse = JSON.parse(lire('packages/domaine/lib/src/comptabilite/cpc_liasse.dart').match(/cpcLiasseJson = r'''([\s\S]*?)'''/)[1]);
  for (const e of liasse.ECARTS || []) {
    for (const m of e.constat.matchAll(/(\d{1,3}(?: \d{3})+)/g)) {
      const nv = Number(m[1].replace(/ /g, ''));
      const ancien = Math.round(nv / FACTEUR);
      if (ancien >= 1000 && !CORRESPONDANCE.has(ancien)) CORRESPONDANCE.set(ancien, nv);
    }
  }
}
const JETON = /(?<![\d.,])(\d{1,3}(?:[   ]\d{3})+|\d{4,})(?:([.,])(\d{1,2}))?(?![\d])/g;
function multJetons(texte) {
  return texte.replace(JETON, (m, ent, sepDec, dec) => {
    const n = Number(ent.replace(/[   ]/g, ''));
    const cible = CORRESPONDANCE.get(n);
    if (cible === undefined) return m;
    const sep = (ent.match(/[   ]/) || [''])[0];
    const entier = dec !== undefined ? Math.floor(cible) : Math.round(cible);
    let sortie = sep ? String(entier).replace(/\B(?=(\d{3})+(?!\d))/g, sep) : String(entier);
    if (dec !== undefined) sortie += sepDec + cible.toFixed(2).split('.')[1].slice(0, dec.length);
    return sortie;
  });
}
// Zones des vecteurs qui portent les valeurs DÉPOSÉES ou du classeur : jamais le fichier entier, car un montant du journal ou du registre des
// immobilisations (valeurs propres au jeu de démonstration) peut coïncider avec un montant de la liasse et serait multiplié à tort.
const VECTEURS = [
  // [fichier, chemins (premier niveau, ou [clé, sous-clé]) des zones transformées]
  ['packages/domaine/test/vecteurs/comptabilite_b.json', [['ecrans', 'm12-compte-resultat'], ['ecrans', 'm12-flux-tresorerie']]],
  ['packages/domaine/test/vecteurs/etats.json', [['jeu'], ['pieces'], ['avecN1'], ['ecarts']]],
  ['packages/domaine/test/vecteurs/echeances.json', [['baseline']]],
];
// « N-1 : X FCFA (-94.0 %) » : l'écart relatif compare une valeur CALCULÉE du journal (inchangée) à la valeur déposée (multipliée) : p' = (p + 100) / 3 - 100.
const POURCENT = /(\(|\s)([+\-−]?\d+(?:\.\d+)?) %/g;
function recalculePourcent(t) {
  return t.replace(POURCENT, (m, av, p) => {
    const v = Number(p.replace('−', '-'));
    const nv = (v + 100) / FACTEUR - 100;
    return `${av}${nv.toFixed(1)} %`;
  });
}
// Colonnes qui ne se multiplient pas : celles que le JOURNAL calcule (exercice en cours, exercice « calculé », colonne journal) et les variations en %.
const COLONNE_CALCULEE = /calcul[ée]|EN COURS|JOURNAL|VARIATION|EXERCICE 2026/i;
function colonnesCalculees(entetes) {
  const rangees = (Array.isArray(entetes) && Array.isArray(entetes[0])) ? entetes : [entetes];
  const n = Math.max(...rangees.map((r) => r.length));
  const sauf = new Set();
  rangees.forEach((r) => r.forEach((h, k) => { if (COLONNE_CALCULEE.test(h)) sauf.add(n - r.length + k + (rangees.length > 1 && r === rangees[0] ? 0 : 0)); }));
  // une sous-rangée plus courte s'aligne à DROITE sur la rangée principale
  return { sauf, n };
}
const transformeLigne = (cellules, sauf, ctx) => cellules.map((c, k) => (sauf.has(k) ? c : transformeFeuille(c, ctx)));
function transformeTable(t, ctx) {
  const { sauf } = colonnesCalculees(t.entetes);
  const r = { ...t };
  r.lignes = t.lignes.map((l) => (Array.isArray(l) ? transformeLigne(l, sauf, ctx) : { ...l, cellules: transformeLigne(l.cellules, sauf, ctx) }));
  if (t.pied !== undefined) r.pied = Array.isArray(t.pied) ? transformeLigne(t.pied, sauf, ctx) : transformeFeuille(t.pied, ctx);
  return r;
}
// Le champ « contenu » d'une pièce imprimée juxtapose les cellules sans séparateur : on le reconstruit cellule par cellule, dans l'ordre.
function reconstruitContenu(contenu, anciennes, nouvelles) {
  let curseur = 0, sortie = '';
  for (let k = 0; k < anciennes.length; k++) {
    const a = String(anciennes[k]), nv = String(nouvelles[k]);
    const idx = contenu.indexOf(a, curseur);
    if (idx < 0) continue;
    sortie += contenu.slice(curseur, idx) + nv;
    curseur = idx + a.length;
  }
  return sortie + contenu.slice(curseur);
}
const cellulesDe = (t) => [...(Array.isArray(t.entetes?.[0]) ? t.entetes.flat() : (t.entetes || [])), ...t.lignes.flatMap((l) => (Array.isArray(l) ? l : l.cellules)), ...(Array.isArray(t.pied) ? t.pied : [])];
function transformeFeuille(o, ctx = {}) {
  if (typeof o === 'string') {
    const t = multJetons(o);
    return t !== o && ctx.pct && /N-1 :/.test(o) ? recalculePourcent(t) : t;
  }
  if (typeof o === 'number') {
    const c = Math.abs(o) >= 1000 ? CORRESPONDANCE.get(Math.round(Math.abs(o))) : undefined;
    return c === undefined ? o : Math.sign(o) * c;
  }
  if (Array.isArray(o)) return o.map((v) => transformeFeuille(v, ctx));
  if (o && typeof o === 'object') {
    if (o.entetes && o.lignes) return transformeTable(o, ctx);
    // `entetes` et `tables` en parallèle (colonnes d'une table par rangée de titres)
    if (Array.isArray(o.entetes) && Array.isArray(o.tables) && Array.isArray(o.entetes[0]) && Array.isArray(o.tables[0]) && Array.isArray(o.tables[0][0])) {
      const r = { ...o };
      r.tables = o.tables.map((rows, k) => { const { sauf } = colonnesCalculees(o.entetes[k]); return rows.map((l) => transformeLigne(l, sauf, ctx)); });
      for (const k of Object.keys(o)) if (k !== 'tables') r[k] = transformeFeuille(o[k], ctx);
      return r;
    }
    const r = Object.fromEntries(Object.entries(o).map(([k, v]) => [k, transformeFeuille(v, { ...ctx, pct: ctx.pct && !(k === 'depose') && ctx.pct })]));
    if (typeof o.contenu === 'string' && Array.isArray(o.tables)) {
      r.contenu = reconstruitContenu(o.contenu, o.tables.flatMap(cellulesDe), r.tables.flatMap(cellulesDe));
    }
    return r;
  }
  return o;
}
// La baseline du classeur 2025 (écran m12-baseline) : TOUT y est dérivé du classeur (moyennes, mois, parts) donc multiplié, sauf les pourcentages, qui ne bougent
// pas, et la COMPARAISON avec les factures 2026 du jeu (non multipliées) dont l'écart et l'évolution sont recalculés.
function transformeBaseline(b) {
  const pool = new Map();
  const ajoute = (exact) => { if (Math.abs(exact) >= 100) pool.set(Math.round(Math.abs(exact)), Math.abs(exact)); };
  for (const [ancien, nv] of CORRESPONDANCE) pool.set(ancien, nv);
  const donnees = b.donnees || {};
  for (const k of ['chargesMois', 'resultatMois']) (donnees[k] || []).forEach(ajoute);
  const classeur = JSON.parse(lire('packages/domaine/lib/src/comptabilite/cpc_donnees.dart').match(/cpcExercice2025Json = r'''([\s\S]*?)'''/)[1]);
  const ancien = (v) => Math.round(v * 100 / FACTEUR) / 100;
  const nouveau = new Map();
  for (const d of classeur.depenses) ajoute(ancien(d.total) / 12);
  ajoute(ancien(classeur.totalChiffreAffaires) / 12);
  ajoute(ancien(classeur.totalDepenses) / 12);
  // table arrondi-ancien → exact ancien ; le nouveau exact est FACTEUR fois l'ancien exact
  const exactAncien = new Map();
  for (const [r, v] of pool) exactAncien.set(r, CORRESPONDANCE.has(r) ? ancien(CORRESPONDANCE.get(r)) : v);
  const jeton = (texte) => texte.replace(JETON, (m, ent, sepDec, dec) => {
    const n = Number(ent.replace(/[   ]/g, ''));
    const v = exactAncien.get(n);
    if (v === undefined || dec !== undefined) return multJetons(m);
    const sep = (ent.match(/[   ]/) || [''])[0];
    const r = Math.round(v * FACTEUR);
    return sep ? String(r).replace(/\B(?=(\d{3})+(?!\d))/g, sep) : String(r);
  });
  const walk = (o) => {
    if (typeof o === 'string') return jeton(o);
    if (typeof o === 'number') {
      if (Math.abs(o) < 100) return o;
      const e = exactAncien.get(Math.round(Math.abs(o)));
      if (e === undefined) return o;
      return Math.sign(o) * (Number.isInteger(o) ? Math.round(e * FACTEUR) : x3(Math.abs(o)));
    }
    if (Array.isArray(o)) return o.map(walk);
    if (o && typeof o === 'object') return Object.fromEntries(Object.entries(o).map(([k, v]) => [k, walk(v)]));
    return o;
  };
  const sortie = {};
  for (const [k, v] of Object.entries(b)) {
    if (k === 'comparaison' || k === 'graphiquesComparaison' || k === 'sourceTexte') continue;
    sortie[k] = walk(v);
  }
  if (b.piece) sortie.piece.contenu = reconstruitContenu(b.piece.contenu, b.piece.tables.flatMap(cellulesDe), sortie.piece.tables.flatMap(cellulesDe));
  // Comparaison : l'écart et l'évolution se recalculent avec le NOUVEAU chiffre d'affaires 2025 contre les factures 2026 inchangées.
  const fmt = (n, sep) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, sep);
  const lit = (t) => Number(t.replace(/[^\d-−]/g, '').replace('−', '-'));
  const sepDe = (t) => (t.match(/[   ]/) || [' '])[0];
  const comp = { ...b.comparaison };
  comp.lignes = b.comparaison.lignes.map((l) => {
    const [mois, ca25, ca26, ecart] = l;
    const ancien25 = lit(ca25), v26 = lit(ca26);
    const nouveau25 = Math.round(exactAncien.has(ancien25) ? exactAncien.get(ancien25) * FACTEUR : ancien25 * FACTEUR);
    const ec = v26 - nouveau25;
    const evo = nouveau25 === 0 ? 0 : Math.round((ec / nouveau25) * 100);
    return [mois, fmt(nouveau25, sepDe(ca25)), ca26, (ec < 0 ? '-' : '') + fmt(Math.abs(ec), sepDe(ecart)), `${evo} %`];
  });
  comp.notes = walk(b.comparaison.notes);
  for (const k of Object.keys(b.comparaison)) if (!['lignes', 'notes'].includes(k)) comp[k] = walk(b.comparaison[k]);
  sortie.comparaison = comp;
  sortie.graphiquesComparaison = b.graphiquesComparaison.map((g) => ({ ...g, series: g.series.map((s) => (/2025/.test(s.label) ? { ...s, data: s.data.map((x) => Math.round((exactAncien.get(Math.round(x)) ?? x) * FACTEUR)) } : s)) }));
  let src = b.sourceTexte;
  const dec25 = classeur.chiffreAffaires[11], d25 = String(Math.round(ancien(dec25)));
  src = src.replace(/15 744 645/g, (m) => fmt(Math.round(ancien(dec25) * FACTEUR), ' ')).replace(/(-)47 233 935/g, '$1' + fmt(Math.round(ancien(dec25) * FACTEUR), ' '));
  sortie.sourceTexte = src;
  return sortie;
}

for (const [p, zones] of VECTEURS) {
  const s = lire(p);
  if (s.includes(MARQUEUR_VECTEUR)) continue;
  const j = JSON.parse(s);
  for (const z of zones) {
    const parent = z.length === 1 ? j : j[z[0]];
    const cle = z[z.length - 1];
    parent[cle] = cle === 'baseline' ? transformeBaseline(parent[cle]) : transformeFeuille(parent[cle], { pct: p.endsWith('comptabilite_b.json') });
  }
  const marque = { _demoLiasse: `Montants de la liasse et du classeur 2025 multipliés par ${FACTEUR} dans ${zones.map((z) => z.join('.')).join(', ')} (tools/baguidi/demo-liasse.mjs) : données de démonstration Baguidi`, ...j };
  ecrire(p, JSON.stringify(marque, null, 1).replace(/BK505416/g, 'DEMO').replace(/15\/05\/2026/g, '30/04/2026').replace(/2026-05-15/g, '2026-04-30').replace(/CLINIQUE NASSIERA SARL/g, DEPOT.denomination).replace(/3201642748214/g, DEPOT.ifu).replace(/— 450 F d’écart/g, '— 1 350 F d’écart') + '\n');
}


// Vecteurs qui ne citent de la liasse que la DATE de dépôt (toutes les occurrences y sont celles du dépôt : valideLe des exercices clos, motifs de lecture seule).
for (const p of ['packages/domaine/test/vecteurs/exercice.json']) {
  const s = lire(p);
  if (s.includes(MARQUEUR_VECTEUR)) continue;
  const t = s.replace(/2026-05-15/g, DEPOT.dateDepot).replace(/15\/05\/2026/g, '30/04/2026').replace(/BK505416/g, DEPOT.code);
  ecrire(p, t.replace(/^\{\n/, `{\n "_demoLiasse": "Date de dépôt de la liasse de démonstration (30/04/2026) : seules les dates de dépôt sont réécrites (tools/baguidi/demo-liasse.mjs)",\n`));
}

// 5. Tests Dart qui CITENT des valeurs de la liasse ou du classeur : remplacements littéraux, donc naturellement idempotents (l'ancien texte n'existe plus).
const REMPLACEMENTS = [
  ['BK505416', 'DEMO'], ['15/05/2026', '30/04/2026'], ['2026-05-15', '2026-04-30'],
  ['CLINIQUE NASSIERA SARL', DEPOT.denomination], ['3201642748214', DEPOT.ifu],
  ['190830994', String(x3(190830994))], ['190 830 994', '572 492 982'], ['160 264 063', '480 792 188'],
  ['450 F d’écart', '1 350 F d’écart'], ['-18108317', '-54324951'], ['−18 108 317', '−54 324 951'], ['18108317', '54324951'],
  ['141667', '425001'], ['141 667', '425 001'],
  ['31359405', '94078215'], ['2632175', '7896525'], ['6300639', '18901917'], ['6 300 639', '18 901 917'],
  ['4561200', '13683600'], ['4472283', '13416849'], ['112937495', '338812485'], ['180151372', '540454116'], ['100066531', '300199593'],
  ['31 359 405', '94 078 215'], ['-2 632 175', '-7 896 525'], ['12 546 383', '37 639 149'],
];
const TESTS_DART = [
  'packages/domaine/test/cpb_feuillets_test.dart', 'packages/domaine/test/cpc_etats_test.dart', 'packages/domaine/test/cpc_echeances_test.dart',
  'packages/domaine/test/cpc_exercice_test.dart', 'apps/poste/test/m12_comptabilite_b_test.dart', 'apps/poste/test/m12_synthese_test.dart',
  'apps/poste/test/m12_etats_test.dart', 'apps/poste/test/m12_exercice_test.dart', 'apps/poste/test/m12_comptabilite_test.dart',
];
for (const p of TESTS_DART) {
  const s = lire(p);
  let t = s;
  for (const [a, b] of REMPLACEMENTS) t = t.split(a).join(b);
  if (t !== s) ecrire(p, t);
}

// Autres sites qui portent la DATE de dépôt (jeu des exercices clos d'office, constante du moteur d'écritures) : remplacement littéral, idempotent.
for (const [p, a, b] of [
  ['apps/poste/assets/donnees/jeu/exercices.json', '2026-05-15', DEPOT.dateDepot],
  ['packages/domaine/test/vecteurs/comptabilite.json', '"valideLe": "2026-05-15"', `"valideLe": "${DEPOT.dateDepot}"`],
  ['packages/domaine/test/vecteurs/comptabilite.json', '"dateDepot": "2026-05-15"', `"dateDepot": "${DEPOT.dateDepot}"`],
  ['packages/domaine/test/vecteurs/comptabilite.json', 'clos le 15/05/2026 — lecture seule', 'clos le 30/04/2026 — lecture seule'],
  ['packages/domaine/lib/src/comptabilite/cpa_ecritures.dart', "cpaLiasseDateDepot = '2026-05-15'", `cpaLiasseDateDepot = '${DEPOT.dateDepot}'`],
]) {
  const s = lire(p);
  if (s.includes(a)) ecrire(p, s.split(a).join(b));
}

for (const f of ['m12-etats-financiers', 'm12-compte-resultat', 'm12-flux-tresorerie']) {
  // fiches d'écran de la documentation : la note de source cite le dépôt
  const p = `docs/architecture/ecrans/${f}.json`;
  const s = lire(p);
  const t = s.replace(/BK505416/g, DEPOT.code).replace(/CLINIQUE NASSIERA SARL/g, DEPOT.denomination).replace(/3201642748214/g, DEPOT.ifu).replace(/déposée le 15\/05\/2026/g, `déposée le 30/04/2026`);
  if (t !== s) ecrire(p, t);
}
console.log(modifies === 0 ? '0 : déjà transformé (marqueur présent).' : `${modifies} fichier(s) ${verifier ? 'à transformer' : 'transformé(s)'}.`);
process.exit(verifier && modifies ? 1 : 0);
