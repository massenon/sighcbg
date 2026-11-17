#!/usr/bin/env node
// NEUTRALISATION DE L'IDENTITÉ DE LA CLINIQUE SŒUR dans les données de test, les tests, le banc, les outils et les documents (décision de la Direction de
// Baguidi du 16/11/2026 : « aucune trace de la clinique sœur, NULLE PART », DECISIONS-16-11 §8).
//
// Les vecteurs du domaine, les fixtures du poste (jeu de référence, jeu sobre, classeurs d'import), les fiches de parité des écrans et les tests ont été
// engendrés par la maquette de la clinique sœur : ils portaient sa dénomination, son IFU, son RCCM, son autorisation, son adresse, ses téléphones, son
// courriel, sa devise et sa ville. Ce script remplace chacun de ces éléments par l'élément CORRESPONDANT de la Clinique Baguidi, tel que le jeu livré le
// porte (apps/poste/assets/donnees/jeu/identiteLegale.json, packages/domaine/lib/src/impression/identite.dart), avec UNE SEULE TABLE appliquée partout à la
// fois : la parité entre une fixture et un vecteur tient, puisque les deux côtés reçoivent le même remplacement. C'est la méthode de pseudonymiser.mjs
// (noms de personnes), appliquée à l'identité de l'établissement.
//
// PROPRIÉTÉS (vérifiées à chaque exécution) :
//  - DÉTERMINISTE et FIGÉE : la table est écrite en clair ci-dessous, jamais recalculée.
//  - REJOUABLE et IDEMPOTENTE : aucune valeur de remplacement ne contient un motif d'origine ; une seconde passe ne trouve rien.
//  - Le texte est remplacé TEL QUEL (aucune ré-sérialisation JSON) : la mise en forme des fichiers ne bouge pas. Les classeurs .xlsx sont rouverts, leurs
//    parties XML remplacées, et réécrits (fabrique ZIP de pseudonymiser.mjs).
//
// CE FICHIER EST LE SEUL DU DÉPÔT À PORTER LES MOTIFS D'ORIGINE EN CLAIR : c'est la seule liste blanche du contrôle d'identité (controle-identite.mjs), qui
// IMPORTE la liste `MOTIFS` d'ici au lieu de la recopier. Les gardes des tests Dart (aide_identite_origine.dart du domaine et du poste) et le contrôle des
// spécimens (apps/poste/tool/specimens/controler.py) relisent la même ligne `MOTIFS` : une seule liste, lue par tous.
// Pourquoi pas des EMPREINTES (comme noms-origine.json) : un motif d'identité est souvent une suite de mots ou de chiffres (« raison de vivre », un numéro de
// téléphone en cinq groupes, un RCCM) et il paraît COLLÉ à ce qui l'entoure dans le texte extrait d'un PDF ou d'une page (« …TOOBP : 507… ») ; une
// empreinte se compare à un jeton entier, elle laisserait passer ces formes collées sans le dire. Une recherche de sous-chaîne, elle, les trouve.
//
// Usage, depuis la racine du dépôt :
//   node tools/baguidi/neutraliser-identite.mjs              applique sur le périmètre par défaut
//   node tools/baguidi/neutraliser-identite.mjs --verifier   compte sans écrire (code de sortie 1 s'il reste quelque chose à remplacer)
//   node tools/baguidi/neutraliser-identite.mjs fichier…     applique sur les fichiers ou dossiers nommés
import { readFileSync, writeFileSync, statSync, readdirSync, existsSync } from 'node:fs';
import { inflateRawSync, deflateRawSync, crc32 } from 'node:zlib';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { lireZip, ecrireZip } from './pseudonymiser.mjs';

const RACINE = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const CE_FICHIER = 'tools/baguidi/neutraliser-identite.mjs';

// --- Les motifs d'origine (sous-chaînes, sensibles à la casse) que le contrôle d'identité refuse PARTOUT hors de ce fichier ----------------------------
// FORMAT LU PAR LES TESTS DART ET PAR controler.py : la déclaration tient sur UNE ligne, chaque motif entre apostrophes droites, sans échappement.
export const MOTIFS = ['NASSIERA', 'Nassiera', 'nassiera', 'NASSIÈRA', 'Nassièra', 'nassièra', 'Natitingou', 'NATITINGOU', 'natitingou', 'Tchirimina', 'TCHIRIMINA', 'tchirimina', 'Atacora', 'ATACORA', 'TOO SARL', '3201642748214', '32016427', '3201 6427', 'RB/NAT', 'raison de vivre', 'QUE DIEU VOUS GU', '01 95 44 51 51', '01 66 43 28 20', '60 33 92 92', 'BP : 507', 'BP 507', '066/MS/DC', 'NS 145/08/DA/CNT'];
// Deux valeurs d'origine que demo-liasse.mjs cherche encore dans les données qu'il transforme (il les importe d'ici au lieu de les recopier).
export const ORIGINE = { ifu: '3201642748214', denominationLiasse: 'CLINIQUE NASSIERA SARL' };
const echapper = (s) => s.replace(/[.*+?^${}()|[\]\\\/]/g, '\\$&');
/** L'expression du contrôle : une alternative des motifs, dans l'ordre de la liste. */
export const IDENTITE_ORIGINE = new RegExp(MOTIFS.map(echapper).join('|'));

// --- Les éléments d'identité de la Clinique Baguidi (fiche identiteLegale du jeu livré) ------------------------------------------------------------------
const NBSP = '\u00a0';   // espace insécable, comme identite.dart et le jeu livré
const NOM = `CLINIQUE BAGUIDI «${NBSP}L’AS DU CŒUR${NBSP}»`;
const NOM_COURT_TITRE = 'Clinique BAGUIDI';   // forme du jeu livré (modèle de badge) et du code (cfb_donnees : « Organigramme de la Clinique BAGUIDI »)
const SLOGAN = 'Votre bien-être est notre raison d’être.';
const BP = '02 BP : 105 PARAKOU (Rép. du Bénin)';
const TELS = ['95 74 69 56', '95 95 99 14', '97 09 34 99'];
const IFU = '3201001996110';
const RCCM = 'RB/PKO/17 A 4240';
const ENREGISTREMENT = 'N° D’ENREGISTREMENT 0416/ONMB/ATL/2002';
const EMAIL = 'cliniquebaguidi@yahoo.fr';
const QUARTIER_CLINIQUE = 'Zongo II';
// Le quartier de la clinique sœur, quand il est l'ADRESSE D'UN PATIENT (fixtures, vecteurs) : un quartier FICTIF de Parakou, inventé ici. L'initiale et le
// rang alphabétique parmi les quartiers des jeux d'essai sont gardés (Santa < Tikpanou < Toucountouna), pour qu'un tri rejoue le même ordre des deux côtés.
const QUARTIER_FICTIF = 'Tikpanou';

// --- LA TABLE, dans l'ordre d'application : la forme la plus longue d'abord -------------------------------------------------------------------------------
export const TABLE = [
  // Dénomination : la raison sociale complète devient la dénomination de Baguidi ; le nom court sans « CLINIQUE » devient « BAGUIDI ».
  ['CLINIQUE NASSIERA TOO SARL', NOM],
  ['Clinique NASSIERA TOO SARL', NOM],
  ['CLINIQUE NASSIERA SARL', NOM],
  ['CLINIQUE NASSIERA TOO', NOM],
  ['Clinique NASSIERA TOO', NOM_COURT_TITRE],
  ['Clinique Nassièra Too', NOM_COURT_TITRE],
  ['Clinique Nassiera Too', NOM_COURT_TITRE],
  ['NASSIERA TOO', 'BAGUIDI'],
  // Écran de connexion (fiches de parité) : la présentation et la localisation composées par l'écran de Baguidi.
  ['Natitingou — République du Bénin', 'Parakou, République du Bénin'],
  // Devise imprimée.
  ['Votre santé, notre raison de vivre.', SLOGAN],
  ['Votre santé, notre raison de vivre', SLOGAN],
  // Adresse postale, téléphones, courriel.
  ['BP : 507 NATITINGOU (Rép. du Bénin)', BP],
  ['01 95 44 51 51  /  01 66 43 28 20', TELS.join('  /  ')],
  ['01 95 44 51 51 / 01 66 43 28 20', TELS.join(' / ')],
  ['"telephones":["01 95 44 51 51","01 66 43 28 20"]', `"telephones":${JSON.stringify(TELS)}`],
  ['"01 95 44 51 51",\n    "01 66 43 28 20"\n', `"${TELS[0]}",\n    "${TELS[1]}",\n    "${TELS[2]}"\n`],
  ['"01 95 44 51 51",\n   "01 66 43 28 20"\n', `"${TELS[0]}",\n   "${TELS[1]}",\n   "${TELS[2]}"\n`],
  ['"01 95 44 51 51",\n        "01 66 43 28 20"\n', `"${TELS[0]}",\n        "${TELS[1]}",\n        "${TELS[2]}"\n`],
  ['01 95 44 51 51', TELS[0]],
  ['01 66 43 28 20', TELS[1]],
  // La ligne des rendez-vous : Baguidi n'en a pas de dédiée, c'est le premier téléphone de l'en-tête.
  ['60 33 92 92', TELS[0]],
  ['cliniquenassiera@gmail.com', EMAIL],
  // Identifiants fiscaux et légaux. Un RCCM d'essai (« RB/NAT/2026-B-999 », nouvelle version d'identité) garde son numéro et prend le greffe de Parakou.
  ['3201642748214', IFU],
  // Les formes dérivées de l'IFU dans les vecteurs de saisie : groupé par 4-4-5, tronqué à 12 chiffres suivis d'une lettre, tronqué à 10 chiffres.
  ['3201 6427 48214', '3201 0019 96110'],
  ['320164274821x', '320100199611x'],
  ['3201642748', '3201001996'],
  ['RB/NAT/2016-B-268', RCCM],
  ['RB/NAT/', 'RB/PKO/'],
  // L'autorisation d'ouverture : Baguidi n'en a pas (champ vide) ; à sa place, l'en-tête imprime le n° d'enregistrement à l'Ordre (lignesEnTete).
  ['AUTORISATION D’OUVERTURE N° 066/MS/DC/SGM/CJ/DNSP/SRS/SA/058SGG20/N°20 du 02/07/2020', ENREGISTREMENT],
  ['N° 066/MS/DC/SGM/CJ/DNSP/SRS/SA/058SGG20/N°20 du 02/07/2020', ''],
  // Forme juridique : non renseignée chez Baguidi.
  ['Société à Responsabilité Limitée', ''],
  // Adresse géographique de la clinique et « Fait à … ».
  ['Quartier Tchirimina, Natitingou', `Quartier ${QUARTIER_CLINIQUE}, Parakou`],
  ['Fait à Natitingou', 'Fait à Parakou'],
  // Le relais de la clinique sœur (indicatif d'adresse dans un test de normalisation) : une adresse d'exemple neutre, Baguidi fournira la sienne.
  ['sighcnt.nassieratoo.com', 'relais.exemple.bj'],
  // Quartier, ville et département : le quartier devient un quartier fictif de Parakou, la ville Parakou, le département le Borgou.
  ['Tchirimina', QUARTIER_FICTIF],
  ['TCHIRIMINA', QUARTIER_FICTIF.toUpperCase()],
  ['Natitingou', 'Parakou'],
  ['NATITINGOU', 'PARAKOU'],
  ['natitingou', 'parakou'],
  ['Atacora-Donga', 'Borgou-Alibori'],
  ['Atacora', 'Borgou'],
  ['ATACORA', 'BORGOU'],
];

// Remplacements PROPRES à un fichier, appliqués AVANT la table. Un vecteur qui est une SORTIE du code se recale sur ce que le code produit, jamais l'inverse.
const PROPRES = {
  // L'exemple du modèle d'import des patients est ÉCRIT PAR LE CODE (jeux_import.dart : « Zongo II, Parakou ») : le vecteur et les classeurs-modèles qui le
  // recopient portent donc la sortie du code, et non le quartier fictif des adresses de patients.
  'packages/domaine/test/vecteurs/import.json': [['Tchirimina, Natitingou', `${QUARTIER_CLINIQUE}, Parakou`]],
  'apps/poste/test/fixtures/import/modele-patients.xlsx': [['Tchirimina, Natitingou', `${QUARTIER_CLINIQUE}, Parakou`]],
  'apps/poste/test/fixtures/import/compresse-niveau1-modele-patients.xlsx': [['Tchirimina, Natitingou', `${QUARTIER_CLINIQUE}, Parakou`]],
};

/** Contrôle de la table : idempotence (aucun remplacement ne réintroduit un motif) et motifs tous couverts. */
export function controlerTable() {
  const erreurs = [];
  for (const [a, b] of [...TABLE, ...Object.values(PROPRES).flat()]) {
    if (IDENTITE_ORIGINE.test(b)) erreurs.push(`le remplacement de « ${a} » réintroduit un motif d'origine`);
    if (a === b) erreurs.push(`règle sans effet : ${a}`);
  }
  for (const m of MOTIFS) if (m.includes("'")) erreurs.push(`le motif ${m} porte une apostrophe droite (format de la ligne MOTIFS)`);
  return erreurs;
}

/** Applique la table (et les règles propres au fichier) à un texte. Rend { texte, n, compte }. */
export function neutraliser(texte, fichier = '') {
  let t = texte;
  let n = 0;
  const compte = {};
  for (const [a, b] of [...(PROPRES[fichier] || []), ...TABLE]) {
    const k = t.split(a).length - 1;
    if (!k) continue;
    t = t.split(a).join(b);
    n += k;
    compte[a] = (compte[a] || 0) + k;
  }
  return { texte: t, n, compte };
}

/** Neutralise les parties XML d'un classeur ; seules les parties modifiées sont recompressées, au niveau d'origine quand le nom le dit (« niveau1 »). */
export function neutraliserClasseur(buf, fichier) {
  const entrees = lireZip(buf);
  let n = 0;
  const compte = {};
  for (const x of entrees) {
    if (!/\.xml$/.test(x.nom)) continue;
    const brut = x.methode === 8 ? inflateRawSync(x.donnees) : x.donnees;
    const r = neutraliser(brut.toString('utf8'), fichier);
    if (!r.n) continue;
    n += r.n;
    for (const [k, v] of Object.entries(r.compte)) compte[k] = (compte[k] || 0) + v;
    const neuf = Buffer.from(r.texte, 'utf8');
    x.donnees = deflateRawSync(neuf, /niveau1/.test(fichier) ? { level: 1 } : {}); x.methode = 8; x.crc = crc32(neuf); x.taille = neuf.length;
  }
  return { buffer: n ? ecrireZip(entrees) : buf, n, compte };
}

// --- Périmètre : tout le dépôt utile ---------------------------------------------------------------------------------------------------------------
export const PERIMETRE = ['apps', 'packages', 'docs', 'tools', 'presentation', 'infra', '.claude/skills', 'package.json', 'README.md'];
export const SAUF = /(^|\/)(node_modules|\.git|build|vendor|\.dart_tool|storage|bootstrap\/cache|\.gradle|Pods)(\/|$)|composer\.lock|package-lock\.json|pubspec\.lock/;
export const EXT = /\.(dart|json|js|cjs|mjs|ts|vue|php|yaml|yml|txt|xml|sql|html|css|md|csv|py|sh|bat|iss|rc|example|exemple|ini|conf|svg|xlsx)$|(^|\/)\.env[^/]*$/;
export function lister(chemin, sortie = []) {
  if (SAUF.test(chemin) || !existsSync(chemin)) return sortie;
  const st = statSync(chemin);
  if (st.isDirectory()) { for (const f of readdirSync(chemin).sort()) lister(join(chemin, f), sortie); return sortie; }
  if (EXT.test(chemin) && st.size < 16e6) sortie.push(chemin);
  return sortie;
}

function principal() {
  const args = process.argv.slice(2);
  const verifier = args.includes('--verifier');
  const erreurs = controlerTable();
  if (erreurs.length) { console.error(erreurs.join('\n')); process.exit(2); }
  process.chdir(RACINE);
  const cibles = args.filter((a) => !a.startsWith('--'));
  const fichiers = (cibles.length ? cibles : PERIMETRE).flatMap((c) => lister(c)).map((f) => relative(RACINE, join(RACINE, f)));
  let total = 0, touches = 0;
  const parRegle = {}, parDossier = {};
  for (const f of fichiers) {
    if (f === CE_FICHIER) continue;
    let r, ecrire;
    if (f.endsWith('.xlsx')) {
      r = neutraliserClasseur(readFileSync(f), f);
      ecrire = () => writeFileSync(f, r.buffer);
    } else {
      r = neutraliser(readFileSync(f, 'utf8'), f);
      ecrire = () => writeFileSync(f, r.texte);
    }
    if (!r.n) continue;
    total += r.n; touches++;
    for (const [k, v] of Object.entries(r.compte)) parRegle[k] = (parRegle[k] || 0) + v;
    const d = f.split('/').slice(0, 3).join('/');
    parDossier[d] = (parDossier[d] || 0) + r.n;
    if (!verifier) ecrire();
  }
  for (const [d, c] of Object.entries(parDossier).sort()) console.log(`${String(c).padStart(7)}  ${d}`);
  console.log('Par règle :');
  for (const [a, b] of TABLE) if (parRegle[a]) console.log(`${String(parRegle[a]).padStart(7)}  « ${a.replace(/\n/g, '⏎')} »`);
  for (const [f, l] of Object.entries(PROPRES)) for (const [a] of l) if (parRegle[a] && fichiers.includes(f)) console.log(`        (règle propre à ${f})`);
  console.log(`${total} remplacement(s) ${verifier ? 'à faire' : 'faits'} dans ${touches} fichier(s) sur ${fichiers.length}.`);
  process.exit(verifier && total ? 1 : 0);
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) principal();
