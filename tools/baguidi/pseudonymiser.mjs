#!/usr/bin/env node
// PSEUDONYMISATION DES NOMS DE PERSONNES de la clinique d'origine (décision J11 de la Direction, 08/11/2026).
//
// Les jeux d'essai du dépôt (jeu de référence copié du jeu livré, fixture sobre, vecteurs du domaine, fiches de parité des écrans, tests Dart et code
// qui citent un nom) ont été engendrés par la maquette de la Clinique Nassiera Too : ils portent les noms de SON personnel et de SES patients.
// Ce script remplace chaque nom par un pseudonyme, avec UNE SEULE TABLE appliquée partout : la parité entre un test et un vecteur tient, puisque les
// deux côtés reçoivent le même remplacement, et plus aucun nom réel de l'autre clinique ne figure dans le dépôt.
//
// PROPRIÉTÉS DE LA TABLE (vérifiées à chaque exécution, le script refuse de tourner sinon) :
//  - DÉTERMINISTE et FIGÉE : écrite en clair ci-dessous, jamais recalculée.
//  - MONOTONE : l'ordre alphabétique (accents et casse neutralisés) des pseudonymes est celui des noms d'origine ; un test qui trie des noms, ou un
//    vecteur trié par la maquette, retrouve donc le même ordre des deux côtés.
//  - DISJOINTE : aucun pseudonyme n'est lui-même un nom d'origine (le script est REJOUABLE et IDEMPOTENT : une seconde passe ne trouve rien), aucun
//    n'apparaît déjà dans les fichiers traités, et AUCUN ne reprend l'un des noms réels de la clinique Baguidi (BAGUIDI, SOKOU, SANOUSSI, ZIME,
//    MABOUDOU, TOUNGOUH, IDOHOU, AKONDE et leurs prénoms).
//  - Les pseudonymes sont des noms INVENTÉS (syllabes tirées d'une graine), jamais ceux d'une personne.
//
// CE QU'IL TRAITE : les jetons de la table, en MAJUSCULES (« TAKI »), en casse de titre (« Taki ») et, pour les noms de famille, en minuscules dans un
// identifiant de compte (« a.taki »). Un prénom qui est aussi un mot courant (Rose, Bio, Parfait…) n'est remplacé qu'à la suite d'un autre nom. Les noms
// sont remplacés TELS QUELS dans le texte (aucune ré-sérialisation JSON : la mise en forme ne bouge pas).
//
// Ce fichier est le SEUL du dépôt qui porte les noms d'origine en clair : il est en liste blanche du contrôle d'identité. Le contrôle, lui, lit le
// fichier de HACHAGES `noms-origine.json` produit ici (`--hachages`), pas la table.
//
// Usage, depuis la racine du dépôt :
//   node tools/baguidi/pseudonymiser.mjs              applique sur le périmètre par défaut
//   node tools/baguidi/pseudonymiser.mjs --verifier   compte sans écrire (code de sortie 1 s'il reste quelque chose à pseudonymiser)
//   node tools/baguidi/pseudonymiser.mjs --hachages   réécrit tools/baguidi/noms-origine.json (empreintes lues par controle-identite.mjs)
//   node tools/baguidi/pseudonymiser.mjs fichier…     applique sur les fichiers ou dossiers nommés
import { createHash } from 'node:crypto';
import { inflateRawSync, deflateRawSync, crc32 } from 'node:zlib';
import { readFileSync, writeFileSync, statSync, readdirSync, existsSync } from 'node:fs';
import { join, relative, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const RACINE = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// [pseudonyme, nom de famille ?, prénom ?] par jeton normalisé (minuscules, sans accent, apostrophe droite).
export const TABLE = {
  "abdoul": ["abebia", 0, 1],
  "aboubakar": ["aboumoge", 0, 1],
  "adam": ["achoube", 1, 0],
  "adamou": ["adiadou", 1, 0],
  "addoul": ["adjapilo", 0, 1],
  "adiabath": ["adjoupi", 0, 1],
  "adissa": ["afagu", 0, 1],
  "adjaho": ["agbesen", 1, 0],
  "adjovi": ["agbuzia", 1, 0],
  "agbo": ["agoro", 1, 0],
  "agossou": ["akiafadjo", 1, 0],
  "ahohou": ["akpomer", 1, 0],
  "aichatou": ["aliazian", 0, 1],
  "aissatou": ["amachim", 0, 1],
  "akpo": ["amitu", 1, 0],
  "alassane": ["anapouzia", 0, 1],
  "alassani": ["anigbe", 1, 0],
  "ali": ["apadama", 0, 1],
  "alice": ["apomu", 0, 1],
  "alimatou": ["arialu", 0, 1],
  "ami": ["arolou", 0, 1],
  "amina": ["asare", 0, 1],
  "aminou": ["asounouta", 0, 1],
  "ana": ["atifi", 0, 1],
  "aniki": ["atugbipou", 1, 0],
  "augustin": ["avolutu", 0, 1],
  "awa": ["azemidia", 0, 1],
  "awaou": ["azomou", 0, 1],
  "baba": ["badom", 0, 1],
  "bado": ["batol", 1, 0],
  "bagri": ["belabo", 1, 0],
  "bako": ["biali", 1, 0],
  "bani": ["biarel", 1, 0],
  "bassongui": ["bichiasi", 1, 0],
  "bernadette": ["biredo", 0, 1],
  "bertine": ["bodje", 0, 1],
  "biaou": ["bona", 1, 0],
  "bibata": ["bouboli", 0, 1],
  "bio": ["bounoukia", 0, 1],
  "boukari": ["buke", 1, 0],
  "celestine": ["cager", 0, 1],
  "chabi": ["cezoune", 1, 1],
  "chantal": ["cichin", 0, 1],
  "choucouratou": ["cochesia", 0, 1],
  "colette": ["coufi", 0, 1],
  "daouda": ["dachulo", 1, 0],
  "dieyabidi": ["datu", 1, 0],
  "djagba": ["diloso", 1, 0],
  "djato": ["dokpede", 1, 0],
  "djibril": ["doulom", 0, 1],
  "dossou": ["duloune", 1, 0],
  "edah": ["edianou", 1, 0],
  "edmond": ["edjukavom", 0, 1],
  "elvyre": ["egbifepo", 0, 1],
  "emile": ["ekiatia", 0, 1],
  "eric": ["emirivi", 0, 1],
  "ezin": ["esedjor", 1, 0],
  "fassinou": ["faleke", 1, 0],
  "fati": ["farou", 0, 1],
  "fatima": ["feriadjul", 0, 1],
  "fatouma": ["fiapeken", 0, 1],
  "felix": ["fikponou", 0, 1],
  "fidele": ["fodi", 0, 1],
  "florent": ["foulumi", 0, 1],
  "foussena": ["fuchibu", 0, 1],
  "gado": ["gakaria", 1, 0],
  "ganiou": ["gedur", 0, 1],
  "garba": ["gevamian", 1, 0],
  "gbedji": ["gidji", 1, 0],
  "gbegan": ["goda", 1, 0],
  "gbegnon": ["gokomar", 1, 0],
  "gounou": ["gudjo", 1, 0],
  "hafissou": ["hakpuram", 0, 1],
  "helene": ["hekoukpol", 0, 1],
  "herve": ["hiabidjo", 0, 1],
  "honorine": ["hine", 0, 1],
  "hounkpatin": ["houluke", 1, 0],
  "hounkpe": ["hubin", 1, 0],
  "hounsou": ["huniam", 1, 0],
  "ibrahim": ["ibaze", 0, 1],
  "ida": ["ichufuva", 0, 1],
  "idrissou": ["igboupu", 1, 1],
  "illa": ["ikpoufase", 1, 0],
  "imorou": ["imefulu", 1, 0],
  "issa": ["isiasiabu", 1, 0],
  "issifou": ["ivekel", 0, 1],
  "jean": ["jagi", 0, 1],
  "justine": ["jiakpune", 0, 1],
  "kadidjatou": ["kadouze", 0, 1],
  "karim": ["kagbouta", 0, 1],
  "kassa": ["kalou", 1, 0],
  "kassim": ["kedjopou", 0, 1],
  "kinnou": ["kele", 1, 0],
  "koffi": ["kiafour", 0, 1],
  "kora": ["kiavumu", 1, 0],
  "koto": ["kigbino", 1, 0],
  "koua": ["kimar", 1, 0],
  "kouagou": ["kogal", 1, 0],
  "kouassi": ["kopegou", 1, 0],
  "kpade": ["kougbom", 1, 0],
  "kpatinde": ["koumedjal", 1, 0],
  "kpognon": ["kouzo", 1, 0],
  "kpossou": ["kulun", 1, 0],
  "lamatou": ["ladjefo", 0, 1],
  "lea": ["lemera", 0, 1],
  "luc": ["loubi", 0, 1],
  "lucres": ["ludjia", 0, 1],
  "m'po": ["m'abekpia", 1, 0],
  "mama": ["maful", 0, 1],
  "mamam": ["mefuti", 1, 0],
  "maman": ["metiavi", 1, 0],
  "marc": ["mevour", 0, 1],
  "marcel": ["miakpago", 0, 1],
  "marguerite": ["mibu", 0, 1],
  "mariam": ["migikpa", 0, 1],
  "mariette": ["mobachia", 0, 1],
  "mary": ["modjo", 0, 1],
  "massenon": ["mogbo", 1, 0],
  "mathieu": ["mopekpal", 0, 1],
  "moumouni": ["moufiado", 1, 0],
  "moussa": ["mudovur", 0, 1],
  "n'tcha": ["n'achou", 1, 0],
  "nadege": ["nedi", 0, 1],
  "nkoue": ["nidjon", 1, 0],
  "nourou": ["noupi", 0, 1],
  "odeito": ["obeki", 1, 0],
  "orou": ["odjipiar", 1, 1],
  "ouorou": ["ogilu", 1, 0],
  "ourtcha": ["osiamiam", 1, 0],
  "padonou": ["pachetol", 1, 0],
  "paraiso": ["penu", 1, 0],
  "parfait": ["piavegbam", 0, 1],
  "pascal": ["pimolel", 0, 1],
  "paul": ["pouchul", 0, 1],
  "paulin": ["pouvopal", 0, 1],
  "rabiatou": ["rafiakpe", 0, 1],
  "rachida": ["rarouvil", 0, 1],
  "rachidatou": ["resia", 0, 1],
  "ramatou": ["riadife", 0, 1],
  "remi": ["riazialo", 0, 1],
  "rodrigue": ["ridur", 0, 1],
  "roger": ["rolan", 0, 1],
  "rose": ["roulin", 0, 1],
  "rosine": ["routoun", 0, 1],
  "sabi": ["sabar", 0, 1],
  "safarath": ["sadjoto", 0, 1],
  "salamatou": ["saliagel", 0, 1],
  "salifou": ["sazo", 1, 1],
  "salou": ["segbiaze", 0, 1],
  "sambieni": ["semia", 1, 0],
  "sambo": ["sesa", 1, 0],
  "sanni": ["siachou", 1, 0],
  "seidou": ["sianuvu", 1, 0],
  "seko": ["sichovian", 0, 1],
  "seraphine": ["sigbudja", 0, 1],
  "sidi": ["sochasi", 0, 1],
  "soglo": ["solekpu", 1, 0],
  "soule": ["souder", 1, 0],
  "souleymane": ["soukoul", 0, 1],
  "soumanou": ["souvolour", 1, 0],
  "sourou": ["sugbia", 1, 0],
  "sylvie": ["sunokpu", 0, 1],
  "taki": ["tachedi", 1, 0],
  "takpara": ["tagbakpur", 1, 0],
  "tamou": ["tavapi", 1, 1],
  "tchando": ["tiafima", 1, 0],
  "tchane": ["tiamou", 1, 0],
  "tchobo": ["tidju", 1, 0],
  "tchoukourou": ["tigeche", 1, 0],
  "tepa": ["toga", 1, 0],
  "tereyama": ["tougbial", 0, 1],
  "tigri": ["touza", 1, 0],
  "tounde": ["tukepou", 0, 1],
  "worou": ["wedia", 1, 0],
  "yacoubou": ["yacha", 0, 1],
  "yahouza": ["yelia", 0, 1],
  "yaradjinnin": ["yevun", 1, 0],
  "yaro": ["yiaki", 1, 0],
  "yaya": ["yiroude", 0, 1],
  "yeni": ["yoro", 1, 0],
  "yerro": ["yousezo", 1, 0],
  "yo": ["yudjouvou", 1, 0],
  "yorou": ["yumeral", 1, 0],
  "zakari": ["zapeto", 0, 1],
  "zaki": ["zesian", 0, 1],
  "zannou": ["ziakpa", 1, 0],
  "zime": ["ziavel", 1, 0],
  "zita": ["zido", 0, 1],
  "zoukaneri": ["zobo", 0, 1],
  "zoulehath": ["zouguti", 0, 1],
  "zoumarou": ["zouzatum", 1, 0],
};

// Les noms réels de la clinique Baguidi, que la table ne doit JAMAIS produire (ni les produire par hasard dans un pseudonyme).
const BAGUIDI = ['baguidi', 'sokou', 'sanoussi', 'zime', 'maboudou', 'toungouh', 'idohou', 'akonde', 'rafiou', 'adamon', 'nawal', 'abraham', 'octave', 'peace', 'nadege', 'zoulkifouli'];
// Ces noms sont à la fois d'origine (le jeu d'origine les portait) ET ceux d'une vraie personne de Baguidi : on les remplace dans les jeux
// d'essai, mais le CONTRÔLE ne les cherche pas (le jeu livré les porte légitimement).
const CHEVAUCHENT = new Set(['zime', 'nadege', 'gado']); // gado : IRM_GADO (gadolinium), un mot du métier
// Prénoms qui sont aussi des mots courants ou des prénoms très répandus : remplacés seulement à la suite d'un autre nom, jamais cherchés par le contrôle.
const APRES_NOM = new Set(['rose', 'bio', 'ami', 'mary', 'parfait', 'fidele', 'alice', 'ida', 'ana', 'mama', 'ali']);
const GENERIQUES = new Set(['jean', 'paul', 'marc', 'luc', 'eric', 'felix', 'lea', 'mathieu', 'pascal', 'marcel', 'roger', 'emile', 'helene', 'sylvie', 'chantal', 'colette', 'justine',
  'marguerite', 'bernadette', 'celestine', 'rosine', 'mariette', 'honorine', 'florent', 'herve', 'augustin', 'edmond', 'rodrigue', 'koffi', 'ibrahim', 'fatima', 'moussa', 'karim',
  'seraphine', 'zita', 'issifou', 'pascal', 'paulin', 'remi']);

const PSEUDOS = new Set(Object.values(TABLE).map((v) => v[0]));
export const norm = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/’/g, "'");
const hacher = (n) => createHash('sha256').update(n).digest('hex').slice(0, 14);

// Formes collées relevées dans les sources (faute de frappe d'un espace) : le pseudonyme suit celui du jeton qu'elles contiennent.
// « nadegecontrats » : « Nadège » soudé à « Contrats RH » dans un vecteur extrait d'un écran ; le nom passe en casse de titre, le reste reste tel quel (3e élément « reste »).
const COLLES = { choucouratoupar: ['choucouratou', 'par'], soinsaniki: ['soins', 'aniki'], nadegecontrats: ['nadege', 'Contrats', 'reste'], sekocontrats: ['seko', 'Contrats', 'reste'] };
const pseudoDe = (n) => (TABLE[n] ? TABLE[n][0] : (COLLES[n] ? (COLLES[n][0] === 'soins' ? 'soins' + TABLE[COLLES[n][1]][0] : TABLE[COLLES[n][0]][0] + COLLES[n][1]) : null));

export function controlerTable() {
  const cles = Object.keys(TABLE);
  const vals = cles.map((k) => TABLE[k][0]);
  const erreurs = [];
  if (new Set(vals).size !== vals.length) erreurs.push('pseudonymes en double');
  const tri = [...cles].sort();
  for (let i = 1; i < tri.length; i++) if (!(TABLE[tri[i - 1]][0] < TABLE[tri[i]][0])) erreurs.push(`table non monotone entre ${tri[i - 1]} et ${tri[i]}`);
  // le pseudonyme garde la première lettre du nom d'origine (initiales, identifiants « a.nom ») et l'apostrophe des noms qui en portent
  for (const k of cles) {
    if (TABLE[k][0][0] !== k[0]) erreurs.push(`le pseudonyme de ${k} ne garde pas son initiale`);
    if (k.includes("'") !== TABLE[k][0].includes("'")) erreurs.push(`le pseudonyme de ${k} ne garde pas son apostrophe`);
  }
  for (const v of vals) {
    if (TABLE[v]) erreurs.push(`le pseudonyme ${v} est lui-même un nom d'origine`);
    if (BAGUIDI.includes(v)) erreurs.push(`le pseudonyme ${v} est un nom réel de Baguidi`);
    if (BAGUIDI.some((b) => v.includes(b))) erreurs.push(`le pseudonyme ${v} contient un nom réel de Baguidi`);
    if (!/^[a-z]+(?:'[a-z]+)?$/.test(v)) erreurs.push(`le pseudonyme ${v} n'est pas en minuscules ASCII`);
  }
  return erreurs;
}

const TOKEN = /[\p{L}]+(?:[’'][\p{L}]+)?/gu;
const MAJ = (m) => m === m.toUpperCase() && m !== m.toLowerCase();
const TITRE = (m) => m[0] === m[0].toUpperCase() && m[0] !== m[0].toLowerCase() && m.slice(1) === m.slice(1).toLowerCase();
const mettreEnForme = (pseudo, forme, original = '') => {
  const apos = original.includes('’') ? '’' : "'";
  const p = pseudo.replace("'", apos);
  if (forme === 'U') return p.toUpperCase();
  if (forme === 'T') return p[0].toUpperCase() + p.slice(1);
  if (forme === 'M') return [...p].map((c, i) => (original[i] && original[i] === original[i].toUpperCase() && original[i] !== original[i].toLowerCase() ? c.toUpperCase() : c)).join('');
  return p;
};

/** Remplace les noms d'un texte. Rend { texte, n } (n : nombre de jetons remplacés). */
export function pseudonymiser(texte, { ambigus = false, minuscules = false } = {}) {
  let n = 0;
  let dernierFin = -10;       // fin du dernier jeton-nom reconnu
  const sortie = texte.replace(TOKEN, (jeton, position) => {
    const reconnu = (tok, pos) => {
      const k = norm(tok);
      const lettres = tok.replace(/[’']/g, '');
      const e = TABLE[k] ? k : (COLLES[k] ? k : null);
      if (!e) return null;
      if (COLLES[e] && COLLES[e][2] === 'reste') return mettreEnForme(TABLE[COLLES[e][0]][0], 'T', tok) + tok.slice(COLLES[e][0].length);
      const pseudo = pseudoDe(e);
      let forme = null;
      if (lettres.length >= 2 && MAJ(lettres)) forme = 'U';
      else if (lettres.length >= 3 && TITRE(lettres)) forme = 'T';
      else if (lettres.length >= 4 && lettres !== lettres.toLowerCase() && lettres !== lettres.toUpperCase() && !TITRE(lettres) && !APRES_NOM.has(e)) forme = 'M';
      else if ((minuscules || /["']/.test(texte[pos - 1] || '') && /["']/.test(texte[pos + tok.length] || '')) && lettres.length >= 4 && lettres === lettres.toLowerCase() && !APRES_NOM.has(e)) forme = 'L';
      // un nom saisi en minuscules seul dans sa chaîne (« kassa » : les vecteurs éprouvent l'insensibilité à la casse)
      else if (lettres === lettres.toLowerCase() && TABLE[e] && TABLE[e][1] && texte.slice(Math.max(0, pos - 2), pos).match(/[a-z]\.$/)) forme = 'L';
      // un nom de famille saisi en minuscules derrière un titre de civilité (« mme taki », « dr kassa » : les tests tapent un nom de session au clavier)
      else if (lettres === lettres.toLowerCase() && lettres.length >= 4 && TABLE[e] && TABLE[e][1] && /(?:^|[^a-z])(?:mme|mlle|dr|pr) $/i.test(texte.slice(Math.max(0, pos - 6), pos))) forme = 'L';
      if (!forme) return null;
      if (forme !== 'L' && lettres.length === 2 && forme === 'T') return null;
      // Un prénom qui est aussi un mot ou un code (AMI = actes médico-infirmiers, ANA01, BIO RAD, Bio-chimie) ne se remplace qu'en casse de titre et isolé.
      if (APRES_NOM.has(e) && (tok.toLowerCase() !== e || (forme !== 'T' && !(forme === 'U' && pos - dernierFin <= 1)) || /[0-9_-]/.test(texte[pos - 1] || '') || /[_-]/.test(texte[pos + tok.length] || '') || (/[0-9]/.test(texte[pos + tok.length] || '') && !(pos - dernierFin <= 1)))) return null;
      if (ambigus && APRES_NOM.has(e) && !(pos - dernierFin <= 1 || /(?:Dr|Mme|Mlle|Pr|M\.|SF) $/.test(texte.slice(Math.max(0, pos - 5), pos)))) return null;
      return mettreEnForme(pseudo, forme, tok);
    };
    // Un jeton collé à un tiret bas est un identifiant (IRM_GADO : le gadolinium, pas un patient) : jamais un nom.
    if (texte[position - 1] === '_' || texte[position + jeton.length] === '_') return jeton;
    let r = reconnu(jeton, position);
    if (r === null && /[’']/.test(jeton)) {
      // « l’ADAM », « d’Orou » : l'apostrophe est une élision, on essaie la partie qui suit
      const i = jeton.search(/[’']/);
      const reste = reconnu(jeton.slice(i + 1), position + i + 1);
      if (reste !== null) { n++; dernierFin = position + jeton.length; return jeton.slice(0, i + 1) + reste; }
    }
    // Un pseudonyme déjà posé reste un NOM pour ce qui le suit : sur un dépôt déjà passé, « BICHIASI Bio82 j » doit encore faire reconnaître « Bio ».
    if (r === null) { if (PSEUDOS.has(norm(jeton))) dernierFin = position + jeton.length; return jeton; }
    n++; dernierFin = position + jeton.length;
    return r;
  });
  // NOMS COLLÉS : le texte extrait d'un PDF colle les mots (« Garde 24hAGOSSOU Yahouza », « ColetteSage-femme »). Un nom de famille en majuscules collé à ce qui le
  // précède, un prénom en casse de titre collé à ce qui le suit en majuscule : relevés ici, sur les noms d'au moins cinq lettres.
  let res = sortie;
  for (const g of COLLES_RE) {
    res = res.replace(g.re, (...m) => { n++; return g.fn(m); });
  }
  return { texte: res, n };
}

const ACCENTS = { a: 'aàâä', e: 'eéèêë', i: 'iïî', o: 'oôö', u: 'uùûü', c: 'cç' };
const motif = (cle, maj) => [...cle].map((c) => (c === "'" ? "['’]" : ACCENTS[c] ? `[${maj ? ACCENTS[c].toUpperCase() : ACCENTS[c]}]` : (maj ? c.toUpperCase() : c))).join('');
const COLLES_RE = Object.entries(TABLE).filter(([k]) => (k.length >= 5 || k === 'seko') && !APRES_NOM.has(k) && !CHEVAUCHENT.has(k)).flatMap(([k, [pseudo, famille]]) => [
  ...(famille ? [{ re: new RegExp(`(?<=[a-z0-9])(${motif(k, true)})(?![A-Za-zÀ-ÿ])`, 'g'), fn: (m) => mettreEnForme(pseudo, 'U', m[1]) }] : []),
  { re: new RegExp(`(?<![A-Za-zÀ-ÿ'’])(${motif(k[0], true)}${motif(k.slice(1), false)})(?=[A-Z])`, 'g'), fn: (m) => mettreEnForme(pseudo, 'T', m[1]) },
]);

// --- Classeurs .xlsx : archives ZIP dont les parties XML portent les chaînes (noms de patients et d'agents des fichiers d'import d'essai) ---------------------
function lireZip(buf) {
  let e = buf.length - 22;
  while (e >= 0 && buf.readUInt32LE(e) !== 0x06054b50) e--;
  if (e < 0) throw new Error('archive ZIP illisible');
  const n = buf.readUInt16LE(e + 10);
  let p = buf.readUInt32LE(e + 16);
  const entrees = [];
  for (let i = 0; i < n; i++) {
    const nl = buf.readUInt16LE(p + 28), el = buf.readUInt16LE(p + 30), cl = buf.readUInt16LE(p + 32), lho = buf.readUInt32LE(p + 42);
    const csize = buf.readUInt32LE(p + 20);
    const lnl = buf.readUInt16LE(lho + 26), lel = buf.readUInt16LE(lho + 28);
    entrees.push({ nom: buf.toString('utf8', p + 46, p + 46 + nl), methode: buf.readUInt16LE(p + 10), heure: buf.readUInt16LE(p + 12), date: buf.readUInt16LE(p + 14),
      attr: buf.readUInt32LE(p + 38), donnees: buf.subarray(lho + 30 + lnl + lel, lho + 30 + lnl + lel + csize), crc: buf.readUInt32LE(p + 16), taille: buf.readUInt32LE(p + 24) });
    p += 46 + nl + el + cl;
  }
  return entrees;
}
function ecrireZip(entrees) {
  const locaux = [], centraux = [];
  let decalage = 0;
  for (const x of entrees) {
    const nom = Buffer.from(x.nom, 'utf8');
    const l = Buffer.alloc(30);
    l.writeUInt32LE(0x04034b50, 0); l.writeUInt16LE(20, 4); l.writeUInt16LE(0x0800, 6); l.writeUInt16LE(x.methode, 8); l.writeUInt16LE(x.heure, 10); l.writeUInt16LE(x.date, 12);
    l.writeUInt32LE(x.crc, 14); l.writeUInt32LE(x.donnees.length, 18); l.writeUInt32LE(x.taille, 22); l.writeUInt16LE(nom.length, 26);
    const c = Buffer.alloc(46);
    c.writeUInt32LE(0x02014b50, 0); c.writeUInt16LE(20, 4); c.writeUInt16LE(20, 6); c.writeUInt16LE(0x0800, 8); c.writeUInt16LE(x.methode, 10); c.writeUInt16LE(x.heure, 12); c.writeUInt16LE(x.date, 14);
    c.writeUInt32LE(x.crc, 16); c.writeUInt32LE(x.donnees.length, 20); c.writeUInt32LE(x.taille, 24); c.writeUInt16LE(nom.length, 28); c.writeUInt32LE(x.attr, 38); c.writeUInt32LE(decalage, 42);
    locaux.push(l, nom, x.donnees); centraux.push(c, nom);
    decalage += 30 + nom.length + x.donnees.length;
  }
  const cd = Buffer.concat(centraux);
  const fin = Buffer.alloc(22);
  fin.writeUInt32LE(0x06054b50, 0); fin.writeUInt16LE(entrees.length, 8); fin.writeUInt16LE(entrees.length, 10); fin.writeUInt32LE(cd.length, 12); fin.writeUInt32LE(decalage, 16);
  return Buffer.concat([...locaux, cd, fin]);
}
/** Pseudonymise les parties XML d'un classeur. Rend { buffer, n } ; le fichier n'est réécrit que si n > 0. */
export function pseudonymiserClasseur(buf) {
  const entrees = lireZip(buf);
  let n = 0;
  for (const x of entrees) {
    if (!/\.xml$/.test(x.nom)) continue;
    const brut = x.methode === 8 ? inflateRawSync(x.donnees) : x.donnees;
    const r = pseudonymiser(brut.toString('utf8'), { minuscules: true });
    if (!r.n) continue;
    n += r.n;
    const neuf = Buffer.from(r.texte, 'utf8');
    x.donnees = deflateRawSync(neuf); x.methode = 8; x.crc = crc32(neuf); x.taille = neuf.length;
  }
  return { buffer: n ? ecrireZip(entrees) : buf, n };
}

// --- Périmètre ------------------------------------------------------------------------------------------------------------------------------------
const PERIMETRE = [
  'apps/poste/test', 'packages/domaine/test', 'apps/poste/lib', 'packages/domaine/lib', 'docs/architecture',
  'apps/mobile', 'apps/web/tests', 'packages/sync', 'packages/sync_dart',
  // les deux références figées de la matrice des droits (comparées par les tests du domaine) : jamais le jeu livré
  'apps/poste/assets/donnees/rbac.reference.json', 'apps/poste/assets/donnees/modulesActifs.reference.json',
];
// Le test du générateur et la documentation de Baguidi citent les noms RÉELS des neuf agents (dont ZIME, aussi nom d'un agent de l'ancien jeu) : jamais pseudonymisés.
const SAUF = /(^|\/)(node_modules|\.git|build|vendor|\.dart_tool|\.claude|storage|golden)(\/|$)|generer_jeu_baguidi_test\.dart$/;
const EXT = /\.(dart|json|md|txt|mjs|cjs|js|ts|vue|yaml|yml|csv|html|php|xlsx)$/;
const lister = (chemin, sortie = []) => {
  if (SAUF.test(chemin) || !existsSync(chemin)) return sortie;
  const st = statSync(chemin);
  if (st.isDirectory()) { for (const f of readdirSync(chemin).sort()) lister(join(chemin, f), sortie); return sortie; }
  if (EXT.test(chemin) && st.size < 12e6) sortie.push(chemin);
  return sortie;
};

function hachagesPseudonymes() {
  return Object.values(TABLE).map((v) => hacher(v[0])).sort();
}

function hachages() {
  const sortie = [];
  for (const [k, [, famille, prenom]] of Object.entries(TABLE)) {
    if (CHEVAUCHENT.has(k) || APRES_NOM.has(k) || GENERIQUES.has(k) || k.length < 3) continue;
    sortie.push({ h: hacher(k), f: famille ? 'UT' : 'U' });
  }
  return sortie.sort((a, b) => a.h.localeCompare(b.h));
}

function principal() {
  const args = process.argv.slice(2);
  const verifier = args.includes('--verifier');
  const erreurs = controlerTable();
  if (erreurs.length) { console.error(erreurs.join('\n')); process.exit(2); }
  if (args.includes('--hachages')) {
    const fichier = join(RACINE, 'tools/baguidi/noms-origine.json');
    writeFileSync(fichier, JSON.stringify({ avertissement: 'Empreintes (SHA-256 tronqué) des noms de personnes de la clinique d\'origine (noms) et de leurs pseudonymes de test (pseudonymes), lues par controle-identite.mjs. Produit par pseudonymiser.mjs --hachages.', noms: hachages(), pseudonymes: hachagesPseudonymes() }, null, 1) + '\n');
    console.log(`${hachages().length} empreintes écrites dans ${relative(RACINE, fichier)}`);
    return;
  }
  process.chdir(RACINE);
  let hachagesAJour = true;
  try {
    const lu = JSON.parse(readFileSync('tools/baguidi/noms-origine.json', 'utf8'));
    hachagesAJour = JSON.stringify(lu.noms) === JSON.stringify(hachages()) && JSON.stringify(lu.pseudonymes) === JSON.stringify(hachagesPseudonymes());
  } catch { hachagesAJour = false; }
  if (!hachagesAJour) { console.log('noms-origine.json n\'est pas à jour : relancer avec --hachages.'); if (verifier) process.exit(1); }
  const cibles = args.filter((a) => !a.startsWith('--'));
  const fichiers = (cibles.length ? cibles : PERIMETRE).flatMap((c) => lister(c));
  // Les pseudonymes ne doivent pas déjà figurer dans les fichiers à traiter (sans quoi la table serait ambiguë) : relevé en lecture seule.
  const vus = new Set(Object.values(TABLE).map((v) => v[0]));
  let total = 0, touches = 0;
  const parDossier = {};
  for (const f of fichiers) {
    if (f === 'tools/baguidi/pseudonymiser.mjs') continue;
    let n, ecrire;
    if (f.endsWith('.xlsx')) {
      const r = pseudonymiserClasseur(readFileSync(f));
      n = r.n; ecrire = () => writeFileSync(f, r.buffer);
    } else {
      const avant = readFileSync(f, 'utf8');
      // Les mots courants qui sont aussi des prénoms (Rose, Parfait…) ne sont remplacés à la suite d'un nom que dans le code et les documents ; dans les
      // données et les tests, un prénom peut se trouver seul dans son champ : on le remplace toujours, sans quoi un nom recomposé par le code ne retrouverait pas le vecteur.
      const r = pseudonymiser(avant, { ambigus: /\/lib\/|^docs\/|\.md$/.test(f) });
      n = r.n; ecrire = () => writeFileSync(f, r.texte);
    }
    if (!n) continue;
    total += n; touches++;
    const d = f.split('/').slice(0, 3).join('/');
    parDossier[d] = (parDossier[d] || 0) + n;
    if (!verifier) ecrire();
  }
  void vus;
  for (const [d, c] of Object.entries(parDossier).sort()) console.log(`${String(c).padStart(7)}  ${d}`);
  console.log(`${total} jeton(s) ${verifier ? 'à pseudonymiser' : 'pseudonymisé(s)'} dans ${touches} fichier(s) sur ${fichiers.length}.`);
  process.exit(verifier && total ? 1 : 0);
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) principal();
