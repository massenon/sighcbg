#!/usr/bin/env node
// SUBSTITUTION DE L'IDENTITÉ LÉGALE dans les vecteurs de test et les fixtures (réplique Baguidi, PRD §4, mission « identité »).
//
// Les vecteurs (packages/domaine/test/vecteurs/*.json) et la fixture du poste (apps/poste/test/fixtures/jeu_sobre) ont été engendrés par la maquette
// de la Clinique Nassiera Too : ils portent son identité légale. Là où un test compare l'identité IMPRIMÉE à un vecteur, ce script applique dans ce
// vecteur la MÊME substitution que le code : l'identité de Nassiera Too devient celle de la Clinique Baguidi.
//
// CE QU'IL TOUCHE, et rien d'autre : les chaînes d'identité légale (dénomination, nom court, devise, adresse postale, téléphones, courriel, IFU,
// RCCM, nom du logiciel, adresse géographique de l'en-tête, « Fait à … ») et la formule de politesse des factures, qui devient le slogan
// (décision de la Direction du 06/11/2026 au soir). Les fiches de parité des écrans autonomes (docs/architecture/ecrans) reçoivent en plus
// la présentation, la localisation et la dénomination composées par l'écran de connexion Baguidi.
//
// CE QU'IL NE TOUCHE JAMAIS : les noms d'agents, de patients, les montants, les codes patient (`CBG/n/AA` : les tests les rejouent sous le sigle de
// la maquette, voir `sousLeSigleDeLaMaquette`), les références de notes de service, les noms de documents (« Tarifs des consultations NASSIERA
// TOO »), les adresses des patients. Un autre lot remplacera les données.
//
// Le texte est remplacé TEL QUEL (aucune ré-sérialisation JSON) : la mise en forme des fichiers ne bouge pas, et le script est REJOUABLE (une seconde
// passe ne trouve plus rien). Usage, depuis la racine du dépôt :
//   node tools/baguidi/substitution-identite.mjs              applique sur la liste par défaut
//   node tools/baguidi/substitution-identite.mjs --verifier   compte sans écrire (code de sortie 1 s'il reste quelque chose à substituer)
//   node tools/baguidi/substitution-identite.mjs fichier…     applique sur les fichiers ou dossiers nommés
import { readFileSync, writeFileSync, statSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';

const NBSP = ' ';
const NOM = `CLINIQUE BAGUIDI «${NBSP}L’AS DU CŒUR${NBSP}»`;
const SLOGAN = 'Votre bien-être est notre raison d’être.';
const TELS = ['95 74 69 56', '95 95 99 14', '97 09 34 99'];

// L'ordre compte : la forme la plus longue d'abord (la dénomination avec « SARL » avant le nom court, la devise suivie d'un point avant la devise nue).
export const SUBSTITUTIONS = [
  ['CLINIQUE NASSIERA TOO SARL', NOM],
  ['CLINIQUE NASSIERA TOO', NOM],
  ['Natitingou — République du Bénin', 'Parakou, République du Bénin'],
  ['Dossier patient, hospitalisation, laboratoire, pharmacie et stocks, facturation normalisée, ressources humaines, paie et comptabilité SYSCOHADA.',
   'Gestion des stocks et inventaire de la pharmacie, achats et expressions de besoins, ressources humaines, paie et primes, comptabilité SYSCOHADA, pilotage et tableaux de bord.'],
  ['Votre santé, notre raison de vivre.', SLOGAN],
  ['Votre santé, notre raison de vivre', SLOGAN],
  ['BP : 507 NATITINGOU (Rép. du Bénin)', '02 BP : 105 PARAKOU (Rép. du Bénin)'],
  ['01 95 44 51 51  /  01 66 43 28 20', TELS.join('  /  ')],
  ['01 95 44 51 51 / 01 66 43 28 20', TELS.join(' / ')],
  ['cliniquenassiera@gmail.com', 'cliniquebaguidi@yahoo.fr'],
  ['3201642748214', '3201001996110'],
  ['RB/NAT/2016-B-268', 'RB/PKO/17 A 4240'],
  ['Quartier Tchirimina, Natitingou', 'Quartier Zongo II, Parakou'],
  ['Fait à Natitingou', 'Fait à Parakou'],
  // La ligne des rendez-vous citée par les messages de rappel : Baguidi n'en a pas de dédiée, c'est le premier téléphone de l'en-tête.
  ['60 33 92 92', TELS[0]],
];

// Substitutions PROPRES à un fichier : la fiche de la semence de l'identité légale (vecteur fiscal-date) porte des champs que le reste des vecteurs
// ne cite pas comme identité (sigle, forme juridique, autorisation, régime de TVA) ; Baguidi n'a ni forme, ni autorisation, ni régime renseignés.
const PROPRES = {
  'fiscal-date.json': [
    ['"sigle": "CBG"', '"sigle": "CBG"'],
    ['"telephones": [\n    "01 95 44 51 51",\n    "01 66 43 28 20"\n   ],', '"telephones": [\n    "95 74 69 56",\n    "95 95 99 14",\n    "97 09 34 99"\n   ],'],
    ['"forme": "Société à Responsabilité Limitée"', '"forme": ""'],
    ['"autorisation": "N° 066/MS/DC/SGM/CJ/DNSP/SRS/SA/058SGG20/N°20 du 02/07/2020"', '"autorisation": ""'],
    ['"regimeTva": "Taux normal 18 %"', '"regimeTva": ""'],
    ['"formulePolitesse": "QUE DIEU VOUS GUÉRISSE ! AMINE !"', '"formulePolitesse": "Votre bien-être est notre raison d’être."'],
  ],
  // La version 1 de l'identité légale du jeu livré (collection `identiteLegale`, JSON compact) : la graine devient celle de Baguidi, avec les champs
  // que la maquette ne porte pas (nom court, activité, date du RCCM, n° d'enregistrement ONMB) ; forme, autorisation et régime de TVA restent VIDES.
  'identiteLegale.json': [
    ['"sigle":"CBG"', '"sigle":"CBG","nomCourt":"CLINIQUE BAGUIDI","activite":"CENTRE DE MÉDECINE DU TRAVAIL, MÉDECINE GÉNÉRALE"'],
    ['"forme":"Société à Responsabilité Limitée"', '"forme":""'],
    ['"telephones":["01 95 44 51 51","01 66 43 28 20"]', '"telephones":["95 74 69 56","95 95 99 14","97 09 34 99"]'],
    ['"autorisation":"N° 066/MS/DC/SGM/CJ/DNSP/SRS/SA/058SGG20/N°20 du 02/07/2020"', '"autorisation":"","rccmDate":"19/03/2009","enregistrement":"0416/ONMB/ATL/2002"'],
    ['"regimeTva":"Taux normal 18 %"', '"regimeTva":""'],
    ['"formulePolitesse":"QUE DIEU VOUS GUÉRISSE ! AMINE !"', '"formulePolitesse":"Votre bien-être est notre raison d’être."'],
  ],
};

const FORMULE = 'QUE DIEU VOUS GUÉRISSE ! AMINE !';
// Dans un tableau de lignes (rouleau de caisse) : la formule ET le séparateur qui la précède.
const FORMULE_EN_LIGNE = /,(\s*)"-{32}",\s*"QUE DIEU VOUS GUÉRISSE ! AMINE !"/g;

// Les vecteurs dont un test compare l'identité imprimée (ticket, en-têtes et rappels de cfg, plan annuel), et la fixture du poste qui les rejoue.
const PAR_DEFAUT = [
  'packages/domaine/test/vecteurs/ticket.json',
  'packages/domaine/test/vecteurs/cfg.json',
  'packages/domaine/test/vecteurs/administration.json',
  'packages/domaine/test/vecteurs/fiscal-date.json',
  'apps/poste/assets/donnees/jeu/identiteLegale.json',
  'apps/poste/test/fixtures/jeu_sobre/identiteLegale.json',
  'apps/poste/test/fixtures/jeu_sobre/planAnnuel.json',
  'apps/poste/test/fixtures/jeu_sobre/modelesMessage.json',
  // Les fiches de parité des neuf écrans autonomes (parite_autonomes_test) : extraites de la maquette Nassiera Too, elles portent son identité.
  'docs/architecture/ecrans/index.json',
  'docs/architecture/ecrans/auth-forgot.json',
  'docs/architecture/ecrans/auth-reset.json',
  'docs/architecture/ecrans/auth-2fa.json',
  'docs/architecture/ecrans/auth-lock.json',
  'docs/architecture/ecrans/error-403.json',
  'docs/architecture/ecrans/error-404.json',
  'docs/architecture/ecrans/plan-du-site.json',
  'docs/architecture/ecrans/enquete-publique.json',
];

function fichiers(chemins) {
  const out = [];
  for (const c of chemins) {
    const s = statSync(c);
    if (s.isDirectory()) out.push(...fichiers(readdirSync(c).map((n) => join(c, n))));
    else if (/\.json$/.test(c)) out.push(c);
  }
  return out;
}

export function substituer(texte, fichier = '') {
  let t = texte;
  const compte = {};
  for (const [nom, liste] of Object.entries(PROPRES)) {
    if (!fichier.endsWith(nom)) continue;
    for (const [a, b] of liste) {
      const n = t.split(a).length - 1;
      if (n) { t = t.split(a).join(b); compte[a.slice(0, 40)] = (compte[a.slice(0, 40)] || 0) + n; }
    }
  }
  const noter = (cle, n) => { if (n) compte[cle] = (compte[cle] || 0) + n; };
  for (const [a, b] of SUBSTITUTIONS) {
    const n = t.split(a).length - 1;
    noter(a, n);
    if (n) t = t.split(a).join(b);
  }
  const enLigne = (t.match(FORMULE_EN_LIGNE) || []).length;
  noter(`${FORMULE} (ligne de rouleau)`, enLigne);
  t = t.replace(FORMULE_EN_LIGNE, '');
  const reste = t.split(FORMULE).length - 1;
  noter(FORMULE, reste);
  if (reste) t = t.split(FORMULE).join('');
  return { texte: t, compte };
}

const args = process.argv.slice(2);
const verifier = args.includes('--verifier');
const cibles = args.filter((a) => a !== '--verifier');
let total = 0;
for (const f of fichiers(cibles.length ? cibles : PAR_DEFAUT)) {
  const avant = readFileSync(f, 'utf8');
  const { texte, compte } = substituer(avant, f);
  const n = Object.values(compte).reduce((a, b) => a + b, 0);
  if (!n) continue;
  total += n;
  console.log(`${relative(process.cwd(), f)} : ${n} substitution(s)`);
  for (const [k, v] of Object.entries(compte)) console.log(`  ${v} × ${k}`);
  if (!verifier) writeFileSync(f, texte);
}
console.log(verifier ? `${total} substitution(s) à faire.` : `${total} substitution(s) appliquée(s).`);
if (verifier && total) process.exitCode = 1;
