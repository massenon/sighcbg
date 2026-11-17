#!/usr/bin/env node
// CONTRÔLE DE L'IDENTITÉ : échoue (code 1) si une trace de la clinique sœur (clinique d'origine) subsiste dans le dépôt.
// DEUX FAMILLES de motifs, cherchées sur TOUT LE DÉPÔT UTILE (code, jeu livré, tests, fixtures, vecteurs, banc, outils, documents, présentation, classeurs
// .xlsx compris) :
//  - l'IDENTITÉ de l'établissement (dénomination, IFU, RCCM, autorisation, adresse, téléphones, courriel, devise, ville, quartier, département). Décision de la
//    Direction de Baguidi du 16/11/2026 (DECISIONS-16-11 §8) : aucune trace NULLE PART, les données de test comprises. La liste des motifs n'est PAS écrite
//    ici : elle est IMPORTÉE de `neutraliser-identite.mjs`, le script qui a remplacé ces motifs par l'identité de Baguidi et SEUL fichier du dépôt à les
//    porter en clair — c'est l'UNIQUE liste blanche de cette famille ;
//  - les NOMS DE PERSONNES de la clinique d'origine (décision J11, 08/11/2026). La liste n'est PAS écrite ici : elle est lue sous forme d'EMPREINTES (SHA-256
//    tronqué) dans `noms-origine.json`, produit par `pseudonymiser.mjs`, seul fichier du dépôt à porter les noms en clair (liste blanche). Les fixtures de test
//    portent les PSEUDONYMES de la table, jamais les noms d'origine ; le jeu LIVRÉ avec le poste ne porte NI les uns NI les autres (un pseudonyme est une
//    donnée de test, pas une donnée de Baguidi).
// Les PDF du dossier `presentation/` sont contrôlés à part (apps/poste/tool/specimens/controler.py), sur la même liste de motifs.
// Usage depuis la racine :  node tools/baguidi/controle-identite.mjs
import { readFileSync, statSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { inflateRawSync } from 'node:zlib';
import { IDENTITE_ORIGINE, CE_FICHIER, PERIMETRE, SAUF, EXT } from './neutraliser-identite.mjs';
import { lireZip } from './pseudonymiser.mjs';

// Le texte d'un fichier : ses lignes, ou, pour un classeur .xlsx, les lignes de ses parties XML (chaînes partagées, feuilles).
function lignesDe(p) {
  if (!p.endsWith('.xlsx')) return readFileSync(p, 'utf8').split('\n');
  return lireZip(readFileSync(p)).filter((x) => /\.xml$/.test(x.nom)).flatMap((x) => (x.methode === 8 ? inflateRawSync(x.donnees) : x.donnees).toString('utf8').split('\n'));
}

// Noms de personnes d'origine : empreintes. Un nom de famille est cherché en MAJUSCULES et en casse de titre, un prénom en MAJUSCULES.
const EMPREINTES = JSON.parse(readFileSync(new URL('./noms-origine.json', import.meta.url), 'utf8'));
const NOMS = new Map(EMPREINTES.noms.map((e) => [e.h, e.f]));
const PSEUDOS = new Set(EMPREINTES.pseudonymes);
const norm = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/’/g, "'");
const hacher = (n) => createHash('sha256').update(n).digest('hex').slice(0, 14);
const TOKEN = /[\p{L}]+(?:[’'][\p{L}]+)?/gu;
const estMaj = (t) => t === t.toUpperCase() && t !== t.toLowerCase();
const estTitre = (t) => t[0] === t[0].toUpperCase() && t[0] !== t[0].toLowerCase() && t.slice(1) === t.slice(1).toLowerCase();
function nomDOrigine(ligne) {
  for (const m of ligne.matchAll(TOKEN)) {
    const t = m[0].replace(/[’']/g, '');
    if (t.length < 3) continue;
    const f = NOMS.get(hacher(norm(m[0])));
    if (f && (estMaj(t) || (f === 'UT' && estTitre(t)))) return m[0];
  }
  return null;
}
function pseudonyme(ligne) {
  for (const m of ligne.matchAll(TOKEN)) {
    const t = m[0].replace(/[’']/g, '');
    if (t.length >= 4 && PSEUDOS.has(hacher(norm(m[0]))) && (estMaj(t) || estTitre(t))) return m[0];
  }
  return null;
}
// Périmètre de la famille « noms » : tout le dépôt utile, tests et documents compris.
const RACINES_NOMS = ['apps', 'packages', 'docs', 'tools'];
// Le seul fichier qui porte les noms d'origine en clair, et le fichier d'empreintes.
const BLANCHE_NOMS = new Set(['tools/baguidi/pseudonymiser.mjs', 'tools/baguidi/noms-origine.json']);
// Le jeu LIVRÉ ne porte aucun pseudonyme de test.
const JEU_LIVRE = 'apps/poste/assets/donnees/jeu';
// CLIQUET « aucune personne en dur dans le code » (17/11/2026) : ces fichiers portent encore un NOM D'EXEMPLE (aide à la saisie, profils de démonstration du mobile,
// coordonnées de l'éditeur), pas une règle métier. La liste ne peut que DÉCROÎTRE ; tout autre fichier de lib qui porte un nom de personne fait échouer le contrôle.
const EXEMPLES_TOLERES = new Set([
  'apps/poste/lib/mere/console.dart',
  'apps/poste/lib/modules/m10/rhc_evenements.dart',
  'apps/poste/lib/modules/m2/cr_saisie.dart',
  'apps/poste/lib/modules/m2/img_demandes.dart',
  'apps/poste/lib/modules/m3/bloc_demande_examen.dart',
  'apps/poste/lib/modules/m5/dem_registre.dart',
  'apps/poste/lib/modules/mere/mra_affectation.dart',
  'apps/poste/lib/modules/mere/mra_supervision.dart',
  'packages/domaine/lib/src/configuration/cfa_regles.dart',
  'packages/domaine/lib/src/format/recherche.dart',
  'packages/domaine/lib/src/import/jeux_import.dart',
  'packages/domaine/lib/src/mobile/mob_suite_donnees.dart',
]);

let trouvailles = 0;
function passe(p) {
  if (SAUF.test(p) || !existsSync(p)) return;
  const st = statSync(p);
  if (st.isDirectory()) { for (const f of readdirSync(p).sort()) passe(join(p, f)); return; }
  if (!EXT.test(p) || st.size > 16e6 || p === CE_FICHIER) return;
  lignesDe(p).forEach((l, i) => {
    const m = l.match(IDENTITE_ORIGINE);
    if (m) { trouvailles++; console.log(`${p}:${i + 1}: identité de la clinique sœur « ${m[0]} »`); }
  });
}
PERIMETRE.forEach(passe);
// Famille « noms de personnes » : passe distincte, sur un périmètre plus large, sans liste blanche de jeux (les fixtures sont pseudonymisées).
let nomsTrouves = 0;
function passeNoms(p) {
  if (SAUF.test(p) || !existsSync(p)) return;
  const st = statSync(p);
  if (st.isDirectory()) { for (const f of readdirSync(p)) passeNoms(join(p, f)); return; }
  if (!EXT.test(p) || st.size > 16e6 || BLANCHE_NOMS.has(p)) return;
  lignesDe(p).forEach((l, i) => {
    const nom = nomDOrigine(l);
    if (nom) { nomsTrouves++; console.log(`${p}:${i + 1}: nom d'origine « ${nom} »`); return; }
    if (p.startsWith(JEU_LIVRE) || (/^(apps|packages)\/[^\/]+\/lib\//.test(p) && !EXEMPLES_TOLERES.has(p))) {   // aucune PERSONNE en dur dans le code (jeu livré ou lib) : l'agent vient de la session, du personnel ou du rôle
      const ps = pseudonyme(l);
      if (ps) { nomsTrouves++; console.log(`${p}:${i + 1}: pseudonyme de test « ${ps} » dans le code ou le jeu livré`); }
    }
  });
}
RACINES_NOMS.forEach(passeNoms);
trouvailles += nomsTrouves;
console.log(`${trouvailles} trace(s) hors liste blanche (liste blanche : ${CE_FICHIER} pour l'identité ; ${[...BLANCHE_NOMS].join(', ')} pour les noms).`);
process.exit(trouvailles ? 1 : 0);
