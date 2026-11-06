/* =============================================================================
 * GÉNÉRATEUR DU PLAN COMPTABLE SYSCOHADA RÉVISÉ
 * -----------------------------------------------------------------------------
 * Source : « plan-comptable-syscohada-revise.csv » (racine du dépôt), remis par
 * la Direction le 06/09/2026 — le plan de comptes du SYSCOHADA RÉVISÉ, qui
 * REMPLACE le plan hérité de la clinique d'origine.
 *
 * Le fichier produit — assets/js/data-plan-comptable.js — est GÉNÉRÉ : ne pas
 * le modifier à la main, la prochaine exécution l'écraserait. Pour corriger un
 * libellé, corriger le CSV puis relancer :
 *     node build/gen-plan-comptable.js
 *
 * Ce que le générateur ajoute au CSV, et qu'il ne faut pas confondre avec la
 * source : le NIVEAU (longueur du code), la CLASSE (premier chiffre), le
 * PARENT (code tronqué d'un cran) et le caractère IMPUTABLE — un compte est
 * imputable s'il n'a pas d'enfant dans le plan, c'est-à-dire s'il est une
 * feuille. Une écriture se passe sur une feuille ; les niveaux supérieurs
 * totalisent.
 * ========================================================================== */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SOURCE = path.resolve(ROOT, '..', 'plan-comptable-syscohada-revise.csv');
const CIBLE = path.join(ROOT, 'assets/js/data-plan-comptable.js');

const brut = fs.readFileSync(SOURCE, 'utf8').replace(/^﻿/, '');
const lignes = brut.split(/\r?\n/).filter((l) => l.trim().length);

const comptes = [];
const vus = new Set();
lignes.forEach((ligne, i) => {
  const sep = ligne.indexOf(';');
  if (sep < 0) return;
  const code = ligne.slice(0, sep).trim();
  const libelle = ligne.slice(sep + 1).trim();
  if (i === 0 && /^code$/i.test(code)) return;           // en-tête
  if (!/^[1-9][0-9]*$/.test(code)) return;               // ligne parasite
  if (vus.has(code)) {
    console.warn('  ! code en double, ignoré : ' + code + ' — ' + libelle);
    return;
  }
  vus.add(code);
  comptes.push({ code: code, libelle: libelle });
});

/* Le parent est le code tronqué d'un caractère, s'il existe au plan. */
const index = new Set(comptes.map((c) => c.code));
const aDesEnfants = new Set();
comptes.forEach((c) => {
  if (c.code.length > 1 && index.has(c.code.slice(0, -1))) aDesEnfants.add(c.code.slice(0, -1));
});

const sortie = comptes.map((c) => ({
  code: c.code,
  libelle: c.libelle,
  classe: Number(c.code[0]),
  niveau: c.code.length,
  parent: c.code.length > 1 && index.has(c.code.slice(0, -1)) ? c.code.slice(0, -1) : null,
  imputable: !aDesEnfants.has(c.code),
}));

const parNiveau = {};
sortie.forEach((c) => { parNiveau[c.niveau] = (parNiveau[c.niveau] || 0) + 1; });
const imputables = sortie.filter((c) => c.imputable).length;

const entete = `/* =============================================================================
 * SIGH-CBG — PLAN COMPTABLE SYSCOHADA RÉVISÉ
 * -----------------------------------------------------------------------------
 * FICHIER GÉNÉRÉ par build/gen-plan-comptable.js — ne pas modifier à la main.
 * Source : plan-comptable-syscohada-revise.csv (Direction, 06/09/2026).
 *
 * ${sortie.length} comptes : ${[1, 2, 3, 4].map((n) => (parNiveau[n] || 0) + ' de niveau ' + n).join(', ')}.
 * ${imputables} comptes IMPUTABLES (feuilles du plan) — les autres totalisent.
 *
 * Ce plan REMPLACE celui de la clinique d'origine (93 comptes), retiré le
 * 06/09/2026 sur décision de la Direction. Les écritures du logiciel passent
 * sur les codes SYSCOHADA à quatre chiffres, ceux que le service comptable de
 * BAGUIDI emploie déjà dans son journal (4011, 5711, 2458…).
 * ========================================================================== */
(function (global) {
  'use strict';

  var COMPTES = `;

const pied = `;

  global.SIGH = global.SIGH || {};
  global.SIGH.planComptable = {
    COMPTES: COMPTES,
    SOURCE: 'Plan comptable SYSCOHADA révisé — Direction, 06/09/2026',
  };
})(window);
`;

/* Une ligne par compte : le fichier se relit et se compare d'une version à
   l'autre, ce qu'un JSON d'un seul tenant interdirait. */
const corps = '[\n' + sortie.map((c) => '    ' + JSON.stringify(c)).join(',\n') + '\n  ]';

fs.writeFileSync(CIBLE, entete + corps + pied);

console.log('Plan comptable SYSCOHADA révisé engendré :');
console.log('  ' + sortie.length + ' comptes  (' + imputables + ' imputables)');
[1, 2, 3, 4].forEach((n) => console.log('  niveau ' + n + ' : ' + (parNiveau[n] || 0)));
console.log('  → ' + path.relative(ROOT, CIBLE));
