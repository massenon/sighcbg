#!/usr/bin/env node
// CATALOGUE DE TOUS LES ÉCRANS DU POSTE — annexe du manuel d'utilisation (« le manuel couvre TOUS les écrans, aucun écran n'est omis »).
//
//   node docs/manuels/generer-catalogue.mjs
//
// Lit : le manifeste du poste (apps/poste/assets/donnees/manifeste.json — domaines, rangées du ruban, écrans), la matrice des droits engendrée
// (rbac.json : parRole[rôle][écran] = [voir, éditer, annuler]), les descriptions des écrans (docs/architecture/ecrans/<id>.json, à défaut
// ecrans-descriptions.json), la référence des activités (modulesActifs.reference.json) et les captures du test
// apps/poste/test/capture_catalogue_test.dart (docs/manuels/src/utilisateur/captures/catalogue/<id>.png + <id>.json).
// Écrit : docs/manuels/src/utilisateur/catalogue.html — une fiche par écran, rangée par domaine puis par rangée du ruban (ordre du ruban). Un écran
// du manifeste sans capture n'est JAMAIS omis : sa fiche porte le motif. Le manuel l'inclut (inclusion posée par generer.mjs / manuel.html).
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ici = dirname(fileURLToPath(import.meta.url));
const racine = resolve(ici, '../..');
const donnees = join(racine, 'apps/poste/assets/donnees');
const src = join(ici, 'src/utilisateur');
const dossierCaptures = join(src, 'captures/catalogue');
const lire = (f) => JSON.parse(readFileSync(f, 'utf8'));

const manifeste = lire(join(donnees, 'manifeste.json'));
const rbac = lire(join(donnees, 'rbac.json'));
const descriptionsPoste = lire(join(donnees, 'ecrans-descriptions.json')).ecrans;
const activites = lire(join(donnees, 'modulesActifs.reference.json'));

const fermesParDefaut = new Map();
for (const a of activites) if (a.actif === false) for (const id of a.ecrans || []) fermesParDefaut.set(id, a);

// Rôles en service (les rôles archivés n'ouvrent plus de session : ils ne figurent pas dans « qui y a accès »).
const roles = rbac.roles.filter((r) => !r.archive);
const libelleRole = Object.fromEntries(rbac.roles.map((r) => [r.id, r.label]));

// Descriptions des pages d'accès et système, que la maquette ne déclare pas (ses fiches n'en relèvent que le texte affiché).
const DESCRIPTIONS_SYSTEME = {
  index: 'L’écran de connexion : identifiant et mot de passe personnels, aucun compte partagé. Il s’affiche à l’ouverture du poste et après une déconnexion.',
  'auth-forgot': 'La demande de nouveau mot de passe : l’agent saisit son identifiant, la demande est transmise à l’administrateur et journalisée.',
  'auth-reset': 'La définition d’un nouveau mot de passe, selon la politique de mot de passe de la clinique.',
  'auth-2fa': 'La vérification en deux étapes, exigée pour les profils à privilèges élevés (administrateur, Direction).',
  'auth-lock': 'L’écran verrouillé : après quinze minutes d’inactivité, la session est suspendue sans être fermée ; le mot de passe la rouvre à l’écran quitté.',
  'error-404': 'La page affichée quand l’écran demandé n’existe pas ou a été déplacé ; elle renvoie au plan du site.',
  'error-403': 'La page affichée quand le profil ne dispose pas du droit d’ouvrir l’écran demandé ; la tentative est journalisée.',
  'plan-du-site': 'L’inventaire de tous les écrans, rangés par domaine et par module.',
  'enquete-publique': 'La fiche d’enquête ouverte par un lien partagé : une page sans menu ni session, tendue à un tiers ; aucune question ne porte sur la santé.',
};

function description(e) {
  const f = join(racine, 'docs/architecture/ecrans', `${e.id}.json`);
  if (existsSync(f)) {
    const d = lire(f).description;
    if (typeof d === 'string' && d.trim()) return d.trim();
  }
  const p = descriptionsPoste[e.id]?.description;
  if (typeof p === 'string' && p.trim()) return p.trim();
  return DESCRIPTIONS_SYSTEME[e.id] || null;
}

function titre(e) {
  const t = descriptionsPoste[e.id]?.titre;
  return typeof t === 'string' && t.trim() ? t.trim() : e.label;
}

/** Qui voit l'écran, en écriture et en lecture seule, d'après la matrice engendrée. */
function acces(e) {
  const ecriture = [], lecture = [];
  if (e.hub) {
    // Une page d'accueil de module se montre à tout rôle qui voit au moins un écran du module.
    const ids = manifeste.ecrans.filter((x) => !x.hub && x.module === e.module).map((x) => x.id);
    for (const r of roles) if (ids.some((id) => rbac.parRole[r.id]?.[id]?.[0])) lecture.push(r.id);
    return { ecriture, lecture, hub: true };
  }
  for (const r of roles) {
    const d = rbac.parRole[r.id]?.[e.id];
    if (!d || !d[0]) continue;
    (d[1] ? ecriture : lecture).push(r.id);
  }
  return { ecriture, lecture };
}

const capture = (id) => {
  const f = join(dossierCaptures, `${id}.json`);
  return existsSync(f) ? lire(f) : null;
};

const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const ancre = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// Rangement : domaine (ordre du ruban) → rangée canonique du ruban (alias exclus : l'écran est rangé à son domaine de rattachement) → écrans.
// Les pages d'accueil de module (hubs) ouvrent la première rangée de leur module ; les écrans hors ruban ferment le domaine.
const parId = new Map(manifeste.ecrans.map((e) => [e.id, e]));
const places = new Set();
const domaines = [];
for (const d of manifeste.domaines) {
  const groupes = [];
  for (const g of manifeste.modules.filter((m) => m.domaine === d.nom && !m.alias)) {
    const ecrans = [];
    if (!groupes.some((x) => x.code === g.code)) {
      const hub = manifeste.ecrans.find((e) => e.hub && e.module === g.code && e.domaine === d.nom && !places.has(e.id));
      if (hub) ecrans.push(hub);
    }
    for (const id of g.ecrans) {
      const e = parId.get(id);
      if (e && e.domaine === d.nom && !places.has(id) && !ecrans.includes(e)) ecrans.push(e);
    }
    ecrans.forEach((e) => places.add(e.id));
    if (ecrans.length) groupes.push({ code: g.code, label: g.label, secondaire: g.secondaire, ecrans });
  }
  const restants = manifeste.ecrans.filter((e) => e.domaine === d.nom && !places.has(e.id));
  restants.forEach((e) => places.add(e.id));
  if (restants.length) groupes.push({ code: null, label: 'Écrans hors ruban', horsRuban: true, ecrans: restants });
  if (groupes.length) domaines.push({ nom: d.nom, groupes });
}
const orphelins = manifeste.ecrans.filter((e) => !places.has(e.id));
if (orphelins.length) domaines.push({ nom: 'Autres écrans', groupes: [{ code: null, label: 'Écrans sans domaine', horsRuban: true, ecrans: orphelins }] });

// ---------------------------------------------------------------------------------------------------------------------------------------------------
const tous = domaines.flatMap((d) => d.groupes.flatMap((g) => g.ecrans));
if (tous.length !== manifeste.ecrans.length) throw new Error(`Rangement incomplet : ${tous.length} / ${manifeste.ecrans.length}`);
// Une capture qui montre un AVIS de la coque (écran pas encore porté, activité fermée, accès refusé, page 404) ne montre pas l'écran : elle compte parmi
// les écrans non capturés, et sa fiche donne l'avis pour motif.
const capturee = (id) => capture(id)?.capture === true && !capture(id)?.avis && existsSync(join(dossierCaptures, `${id}.png`));
const motifDe = (id) => capture(id)?.avis || capture(id)?.motif || 'Aucune capture n’a été produite pour cet écran (test de capture non exécuté).';
const nonCaptures = tous.filter((e) => !capturee(e.id));

function listeRoles(ids) {
  return ids.map((id) => `<span class="cat-role">${esc(libelleRole[id] || id)}</span>`).join(' ');
}

function fiche(d, g, e) {
  const c = capture(e.id);
  const desc = description(e);
  const a = acces(e);
  const chemin = e.hub
    ? `${esc(d.nom)} ➔ ${esc(e.moduleLabel || g.label)} ➔ page d’accueil du module`
    : g.horsRuban
      ? `${esc(d.nom)} ➔ ${esc(e.moduleLabel || e.module)} ➔ ${esc(e.label)} <span class="cat-hors">(hors ruban)</span>`
      : `${esc(d.nom)} ➔ ${esc(g.label)} ➔ ${esc(e.label)}`;
  const encadres = [];
  if (e.hub) encadres.push(['info', 'Page d’accueil de module', 'Cette page présente en cartes les écrans du module que votre rôle peut ouvrir. On l’atteint par l’intitulé de la rangée dans le menu, par le fil d’Ariane ou par les raccourcis de la barre.']);
  if (e.standalone) encadres.push(['info', 'Écran hors ruban', /renvoi|Fusionné/i.test(desc || '')
    ? 'Page de renvoi : l’écran a été fusionné dans un autre. Il ne figure plus au menu ; une ancienne adresse ou un ancien lien y mène encore et la page indique où se trouve désormais la fonction.'
    : 'Cet écran ne figure pas au menu en ruban : on y arrive par un bouton d’un autre écran, par la recherche globale ou, pour les pages d’accès, à l’ouverture de session.']);
  if (fermesParDefaut.has(e.id)) {
    const f = fermesParDefaut.get(e.id);
    encadres.push(['info', 'Activité fermée par défaut', `${esc(f.motif || 'Activité fermée.')} L’écran reste au logiciel : l’administrateur peut rouvrir l’activité depuis <strong>Système ➔ Configuration Clinique ➔ Activité des modules</strong>. La capture a été faite activité rouverte ; tant qu’elle est fermée, aucun rôle ne voit l’écran.`]);
  }
  if (e.id === 'plan-du-site') encadres.push(['info', 'Désactivé par défaut', 'Le plan du site est désactivé par un réglage du système ; l’administrateur l’active dans <strong>Système ➔ Configuration Clinique ➔ Paramètres système</strong>. La capture a été faite réglage activé.']);
  if (e.id === 'cfg-poste') encadres.push(['info', 'Réglages de ce poste', 'Cet écran règle le poste sur lequel on travaille (mode fileul ou mère). La capture montre un poste fileul de démonstration.']);
  if (c?.mode === 'mère') encadres.push(['info', 'Poste mère seulement', 'Cet écran n’existe que sur le poste mère (le serveur local de la clinique). La capture a été faite avec une source de démonstration : les appareils et volumes affichés sont fictifs.']);
  if (e.universel) encadres.push(['info', 'Écran ouvert à tous', 'Cet écran est ouvert à tout agent, quel que soit son rôle.']);

  let accesHtml;
  if (fermesParDefaut.has(e.id)) {
    const r = (e.roles || []).filter((x) => libelleRole[x]);
    accesHtml = `<p class="cat-acces"><strong>Qui y a accès :</strong> aucun rôle tant que l’activité est fermée. Activité rouverte : ${listeRoles(r)}.</p>`;
  } else if (e.standalone && (e.module === 'AUTH' || e.id === 'enquete-publique')) {
    accesHtml = `<p class="cat-acces"><strong>Qui y a accès :</strong> tout utilisateur${e.id === 'enquete-publique' ? ', et le tiers à qui le lien a été remis (sans session)' : ', avant ou pendant la session'}.</p>`;
  } else if (a.hub) {
    accesHtml = `<p class="cat-acces"><strong>Qui y a accès :</strong> ${a.lecture.length ? listeRoles(a.lecture) : 'aucun rôle'}. <span class="cat-note">Chacun n’y voit que les écrans que son rôle peut ouvrir.</span></p>`;
  } else {
    const lignes = [];
    if (a.ecriture.length) lignes.push(`<p class="cat-acces"><strong>Lecture et écriture :</strong> ${listeRoles(a.ecriture)}</p>`);
    if (a.lecture.length) lignes.push(`<p class="cat-acces"><strong>Lecture seule :</strong> ${listeRoles(a.lecture)}</p>`);
    if (!lignes.length) lignes.push('<p class="cat-acces"><strong>Qui y a accès :</strong> aucun rôle dans la matrice livrée ; l’administrateur peut l’ouvrir depuis <strong>Rôles &amp; permissions</strong>.</p>');
    accesHtml = lignes.join('\n');
  }

  let image;
  if (capturee(e.id)) {
    image = `<figure class="cat-capture"><img src="captures/catalogue/${esc(e.id)}.png" alt="Capture de l’écran ${esc(titre(e))}" width="${c.largeur || 1080}" height="${c.hauteur || 675}"><figcaption>Capture sous le rôle <strong>${esc(libelleRole[c.role] || c.role)}</strong>, jeu de démonstration (noms du personnel remplacés).</figcaption></figure>`;
  } else {
    const motif = motifDe(e.id);
    image = `<div class="encadre attention"><span class="titre">Écran non capturé</span><p>${esc(motif)}</p></div>`;
  }

  return `<section class="cat-fiche" id="ecran-${esc(e.id)}">
<div class="cat-tete">
<h4>${esc(titre(e))}</h4>
<p class="cat-chemin"><strong>Chemin :</strong> ${chemin}</p>
${desc ? `<p class="cat-desc"><strong>Rôle de l’écran :</strong> ${esc(desc)}</p>` : '<p class="cat-desc"><strong>Rôle de l’écran :</strong> <em>aucune description déclarée.</em></p>'}
${accesHtml}
</div>
${encadres.map(([k, t, p]) => `<div class="encadre ${k}"><span class="titre">${t}</span><p>${p}</p></div>`).join('\n')}
${image}
<p class="cat-id">Identifiant technique : <code>${esc(e.id)}</code> — module ${esc(e.module)}</p>
</section>`;
}

const corps = [];
corps.push(`<h1 id="annexe-catalogue">Annexe — Catalogue de tous les écrans</h1>
<p>Cette annexe présente <strong>tous les écrans du poste de travail</strong>, sans exception : les écrans du menu en ruban, les pages d’accueil de module, les pages de saisie et de renvoi hors ruban, les pages d’accès (connexion, verrouillage, erreurs), les écrans du poste mère et ceux des activités fermées par défaut.</p>
<p>Les écrans sont rangés comme dans le menu : par <strong>domaine</strong> (onglets du ruban, de gauche à droite), puis par <strong>rangée</strong> du panneau. Chaque fiche donne le titre exact de l’écran, son chemin de navigation, son rôle, les rôles qui y ont accès (d’après la matrice des droits livrée) et une capture.</p>
<table class="simple cat-compte">
<tr><th>Écrans au manifeste</th><th>Écrans capturés</th><th>Écrans non capturés</th></tr>
<tr><td><strong>${tous.length}</strong></td><td><strong>${tous.length - nonCaptures.length}</strong></td><td><strong>${nonCaptures.length}</strong></td></tr>
</table>
${nonCaptures.length
    ? `<div class="encadre attention"><span class="titre">Écrans non capturés</span><p>Ces écrans figurent au catalogue avec le motif de l’absence de capture :</p><ul>${nonCaptures.map((e) => `<li><a href="#ecran-${esc(e.id)}"><strong>${esc(titre(e))}</strong></a> (<code>${esc(e.id)}</code>) — ${esc(motifDe(e.id))}</li>`).join('')}</ul></div>`
    : '<div class="encadre info"><span class="titre">Information</span><p>Tous les écrans du manifeste ont été capturés.</p></div>'}
<div class="encadre info"><span class="titre">Information</span><p>Les captures montrent le <strong>haut de l’écran</strong> (1440 × 900 points), ouvert sous le rôle <strong>Administrateur système</strong>, qui voit tous les écrans, sur le jeu de démonstration livré. Votre écran peut montrer moins de boutons : chaque rôle ne voit que les commandes que ses droits autorisent. Les noms du personnel sont remplacés par « AGENTnn Démo ».</p></div>`);

for (const d of domaines) {
  const nb = d.groupes.reduce((s, g) => s + g.ecrans.length, 0);
  corps.push(`<h2 id="catalogue-${ancre(d.nom)}">Domaine ${esc(d.nom)} <span class="cat-nb">(${nb} écrans)</span></h2>`);
  for (const g of d.groupes) {
    corps.push(`<h3 id="catalogue-${ancre(d.nom)}-${ancre(g.label)}">${esc(g.label)}${g.code ? ` <span class="cat-nb">— ${esc(g.code)}, ${g.ecrans.length} écran(s)</span>` : ` <span class="cat-nb">— ${g.ecrans.length} écran(s)</span>`}</h3>`);
    for (const e of g.ecrans) corps.push(fiche(d, g, e));
  }
}

const html = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="pied" content="SIGH-CBG — Manuel d’utilisation du poste — Catalogue des écrans">
<title>Catalogue des écrans — SIGH-CBG</title>
<link rel="stylesheet" href="../commun/manuel.css">
<style>
/* Styles propres au catalogue (la feuille commune reste intacte). */
.cat-fiche { margin: 0 0 1.4em; padding-top: 0.2em; border-top: 1px solid var(--gris-200); }
.cat-tete { break-inside: avoid; break-after: avoid; }
.cat-capture { break-inside: avoid; }
.cat-fiche h4 { font-size: 12pt; margin: 0.6em 0 0.25em; color: var(--sante-900); }
.cat-chemin, .cat-desc, .cat-acces { font-size: 10pt; margin: 0 0 0.3em; }
.cat-role { display: inline-block; font-size: 8.8pt; border: 1px solid var(--sante-100); background: var(--sante-50); color: var(--sante-900); border-radius: 3px; padding: 0 0.35em; margin: 0.08em 0; white-space: nowrap; }
.cat-note, .cat-hors { color: var(--gris-600); font-style: italic; }
.cat-nb { font-weight: 400; color: var(--gris-600); font-size: 0.75em; }
.cat-capture { margin: 0.4em 0 0.3em; }
.cat-capture img { width: 78%; margin: 0 auto; height: auto; display: block; border: 1px solid var(--gris-200); border-radius: 5px; }
.cat-capture figcaption { text-align: center; font-size: 8.5pt; color: var(--gris-600); font-style: italic; margin-top: 0.25em; }
.cat-id { font-size: 8.5pt; color: var(--gris-400); margin: 0; }
.cat-fiche .encadre { font-size: 9.8pt; margin: 0.4em 0 0.5em; padding-top: 0.5em; padding-bottom: 0.5em; }
.cat-compte td { font-size: 13pt; text-align: center; }
</style>
</head>
<body>
<main>
${corps.join('\n')}
</main>
</body>
</html>
`;
writeFileSync(join(src, 'catalogue.html'), html);
console.log(`catalogue.html : ${tous.length} écrans, ${tous.length - nonCaptures.length} capturés, ${nonCaptures.length} non capturés.`);
for (const e of nonCaptures) console.log(`  non capturé : ${e.id} — ${motifDe(e.id)}`);
