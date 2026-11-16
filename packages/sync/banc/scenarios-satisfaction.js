'use strict';
/* Scénario SAT1 (décision de la Direction de Baguidi du 16/11/2026, section 8) : la SATISFACTION EN LIGNE, au contrat du relais — celui de référence ou,
   avec SIGH_RELAIS=laravel, le relais Laravel (apps/web).

   Le CÔTÉ MÈRE est joué par l'implémentation de référence (`satisfaction-cle.js` : paire X25519, déchiffrement) et des requêtes SIGNÉES ; le NAVIGATEUR
   par le script même que sert le relais (`apps/web/public/js/satisfaction.js`), exécuté dans un contexte isolé. Ce que le scénario éprouve :
     1. la mère seule publie : sans secret 403, signature fausse 401 ; une publication hors schéma est refusée en la nommant ;
     2. la page publique rend LE modèle publié (une question ajoutée au modèle et republiée y paraît), sans lien vers le logiciel ;
     3. jeton inconnu, mal formé, expiré, révoqué : LA MÊME réponse, page, modèle et dépôt ;
     4. deux réponses chiffrées dans le navigateur (Web Crypto X25519 et repli BigInt) sont déposées ; ce que le relais détient, décodé, ne porte aucune
        réponse en clair et a l'entropie d'un chiffrement ; le journal du relais n'en porte rien non plus ;
     5. la mère relève, déchiffre avec SA clé privée, retrouve les réponses ; une enveloppe rattachée à un autre lien ne se déchiffre pas ; l'acquittement
        efface les enveloppes ;
     6. la révocation ferme la porte (page neutre), un lien révoqué ne se republie pas ;
     7. le débit des dépôts est limité par adresse. */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const M = require('./satisfaction-cle');

const SECRET = 'secret-mere';
const SENTINELLE = 'Sentinelle-SAT1-Commentaire-Zebulon';
const entropie = (b) => { const c = new Array(256).fill(0); for (const x of b) c[x]++; return -c.reduce((a, n) => (n ? a + (n / b.length) * Math.log2(n / b.length) : a), 0); };
const jeton = () => Array.from(crypto.randomBytes(24), (x) => 'abcdefghijkmnopqrstuvwxyz23456789'[x % 33]).join('');
const jour = (decalage) => new Date(Date.now() + 3600 * 1000 + decalage * 86400000).toISOString().slice(0, 10);

/* Le navigateur : le script servi par le relais, avec le Web Crypto de Node. */
function navigateur() {
  const code = fs.readFileSync(path.join(__dirname, '..', '..', '..', 'apps', 'web', 'public', 'js', 'satisfaction.js'), 'utf8');
  const ctx = { TextEncoder, TextDecoder, atob, btoa, BigInt, crypto: globalThis.crypto };
  ctx.globalThis = ctx;
  vm.runInNewContext(code, ctx);
  return ctx.SighSatisfaction;
}

const champs = (avecPropre) => [
  { nom: 'Q_ACCUEIL', libelle: 'Qualité de l’accueil (1 à 5)', type: 'select', requis: true, options: ['1', '2', '3', '4', '5'], lignes: 3 },
  { nom: 'Q_RECO', libelle: 'Recommanderiez-vous la clinique ?', type: 'select', requis: true, options: ['Oui', 'Plutôt oui', 'Plutôt non', 'Non'], lignes: 3 },
  ...(avecPropre ? [{ nom: 'Q_PROPRE', libelle: 'Propreté des locaux (1 à 5)', type: 'select', requis: true, options: ['1', '2', '3', '4', '5'], lignes: 3 }] : []),
  { nom: 'Q_COM', libelle: 'Un commentaire ?', type: 'textarea', requis: false, options: [], lignes: 2 },
];

module.exports = ({ monde, verifier, titre }) => ({
  async SAT1() {
    titre('SATISFACTION-SAT1 · questionnaire en ligne par jeton : publication signée, page neutre, chiffrement dans le navigateur, relève et déchiffrement par la mère seule, révocation, débit');
    const m = await monde({ relais: true });
    const base = `http://127.0.0.1:${m.relais.port}`;
    const signe = async (chemin, corps, { secret = SECRET, signature } = {}) => {
      const brut = JSON.stringify(corps);
      const r = await fetch(base + chemin, { method: 'POST', body: brut, headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'x-mere': secret,
        'x-signature': signature || 'sha256=' + crypto.createHmac('sha256', secret).update(brut).digest('hex') } });
      let j = {}; try { j = await r.json(); } catch (e) { /* vide */ }
      return { status: r.status, json: j };
    };
    const page = async (j) => { const r = await fetch(`${base}/satisfaction/${j}`); return { status: r.status, texte: await r.text() }; };
    const modele = async (j) => { const r = await fetch(`${base}/satisfaction/${j}/modele`, { headers: { Accept: 'application/json' } }); return { status: r.status, texte: await r.text() }; };
    const deposer = async (j, env) => { const r = await fetch(`${base}/satisfaction/${j}/reponse`, { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' }, body: JSON.stringify({ enveloppe: env }) }); return { status: r.status, texte: await r.text() }; };
    const paire = M.nouvellePaire();
    const publication = (j, plus = {}) => ({ jeton_hash: crypto.createHash('sha256').update(j).digest('hex'), ref: 'JET-SAT1', expire_le: jour(30), clinique: 'Clinique d’essai',
      titre: 'Votre avis compte', description: 'Quelques questions sur votre passage.', champs: champs(false), cle_publique: paire.publique, kid: paire.kid, ...plus });
    const factice = () => ({ v: 'sat1', kid: paire.kid, epk: crypto.randomBytes(32).toString('base64url'), iv: crypto.randomBytes(12).toString('base64url'), ct: crypto.randomBytes(272).toString('base64url') });

    // 1. La mère seule publie.
    const J = jeton();
    verifier('sans le secret de la mère, la publication est refusée (403)', (await signe('/mere/satisfaction/publier', publication(J), { secret: 'faux' })).status === 403);
    verifier('une signature fausse est refusée (401), rien n’est publié', (await signe('/mere/satisfaction/publier', publication(J), { signature: 'sha256=00' })).status === 401 && (await page(J)).status === 404);
    const horsSchema = await signe('/mere/satisfaction/publier', publication(J, { champs: [{ nom: '_repondant', libelle: 'Votre nom', type: 'textarea', requis: true, options: [], lignes: 1 }] }));
    verifier('un champ réservé au poste (nom du répondant) est refusé en le nommant (422)', horsSchema.status === 422 && horsSchema.json.code === 'publication_invalide', JSON.stringify(horsSchema.json));
    const pub = await signe('/mere/satisfaction/publier', publication(J));
    verifier('la mère publie un lien signé', pub.status === 200 && pub.json.cree === true, JSON.stringify(pub.json));

    // 2. La page rend LE modèle publié, sans lien vers le logiciel.
    const p1 = await page(J);
    verifier('la page publique rend les questions du modèle publié', p1.status === 200 && p1.texte.includes('Recommanderiez-vous la clinique ?') && p1.texte.includes('name="Q_COM"'));
    verifier('la page publique ne porte aucun lien vers le logiciel', !/<a\s/i.test(p1.texte) && !p1.texte.includes('panneau'));
    await signe('/mere/satisfaction/publier', publication(J, { champs: champs(true) }));
    verifier('une question ajoutée au modèle et republiée paraît sur le lien', (await page(J)).texte.includes('Propreté des locaux (1 à 5)'));

    // 3. Inconnu, mal formé, expiré, révoqué : la même réponse.
    const JE = jeton(); const JR = jeton();
    await signe('/mere/satisfaction/publier', publication(JE, { ref: 'JET-SAT1-E' }));
    await m.relais.direct('POST', '/banc/satisfaction/vieillir', { ref: 'JET-SAT1-E', expire_le: jour(-1) });
    await signe('/mere/satisfaction/publier', publication(JR, { ref: 'JET-SAT1-R' }));
    await signe('/mere/satisfaction/revoquer', { jeton_hash: crypto.createHash('sha256').update(JR).digest('hex') });
    const series = { page: [], modele: [], depot: [] };
    for (const j of [jeton(), 'mal%20forme', JE, JR]) {
      const a = await page(j); series.page.push(a.status + '|' + a.texte);
      const b = await modele(j); series.modele.push(b.status + '|' + b.texte);
      const c = await deposer(j, factice()); series.depot.push(c.status + '|' + c.texte);
    }
    for (const [nom, s] of Object.entries(series)) verifier(`jeton inconnu, mal formé, expiré, révoqué : UNE seule réponse (${nom}), 404`, new Set(s).size === 1 && s[0].startsWith('404|'), [...new Set(s)].join(' ≠ ').slice(0, 300));
    verifier('la réponse neutre ne nomme ni la clinique ni le questionnaire', !series.page[0].includes('Votre avis compte') && !series.page[0].includes('Clinique d'));

    // 4. Le navigateur chiffre ; le relais ne lit rien.
    const S = navigateur();
    const donnees = JSON.parse((await modele(J)).texte);
    const r1 = { Q_ACCUEIL: '5', Q_RECO: 'Oui', Q_PROPRE: '4', Q_COM: SENTINELLE };
    const r2 = { Q_ACCUEIL: '3', Q_RECO: 'Plutôt non', Q_PROPRE: '2' };
    const e1 = await S.chiffrer(r1, donnees); const e2 = await S.chiffrer(r2, donnees, { forcerRepli: true });
    verifier('le navigateur chiffre par les deux voies (Web Crypto X25519, repli BigInt)', e1.voie === 'webcrypto' && e2.voie === 'repli');
    delete e1.voie; delete e2.voie;
    const d1 = await deposer(J, e1); const d2 = await deposer(J, e2);
    verifier('les deux enveloppes sont déposées (202)', d1.status === 202 && d2.status === 202, d1.texte + ' ' + d2.texte);
    const malForme = await deposer(J, { reponses: r1 });
    verifier('une réponse EN CLAIR est refusée au dépôt (422), rien n’est stocké', malForme.status === 422);
    const kidFaux = await deposer(J, { ...factice(), kid: 'fedcba9876543210' });
    verifier('une enveloppe chiffrée pour une autre clé est refusée (409 cle_perimee)', kidFaux.status === 409 && kidFaux.texte.includes('cle_perimee'));
    const tout = (await m.relais.direct('GET', '/banc/satisfaction/tout')).json;
    const vu = JSON.stringify(tout);
    verifier('ce que le relais détient ne porte ni le commentaire en clair ni le jeton en clair', !vu.includes(SENTINELLE) && !vu.includes(J));
    const octets = Buffer.concat((tout.enveloppes || []).map((x) => Buffer.from(JSON.parse(x.enveloppe).ct, 'base64url')));
    verifier('les chiffrés stockés ont l’entropie d’un chiffrement (> 7 bits par octet)', octets.length >= 544 && entropie(octets) > 7, `entropie ${entropie(octets).toFixed(2)}, ${octets.length} octets`);

    // 5. La mère relève, déchiffre seule, acquitte.
    const rel = await signe('/mere/satisfaction/relever', {});
    const envs = rel.json.enveloppes || [];
    verifier('la mère relève les deux enveloppes, rattachées à la référence de SON lien et au jour de réception', envs.length === 2 && envs.every((x) => x.ref === 'JET-SAT1' && /^\d{4}-\d{2}-\d{2}$/.test(x.recue_le)), JSON.stringify(rel.json).slice(0, 300));
    let lues = [];
    try { lues = envs.map((x) => M.dechiffrer(x.enveloppe, paire, J).reponses); } catch (e) { lues = [String(e)]; }
    verifier('la mère déchiffre avec SA clé privée et retrouve les réponses exactes', JSON.stringify(lues) === JSON.stringify([r1, r2]), JSON.stringify(lues));
    let deplacee = false; try { M.dechiffrer(envs[0].enveloppe, paire, JE); } catch (e) { deplacee = true; }
    verifier('une enveloppe rattachée à un autre lien ne se déchiffre pas (données authentifiées)', deplacee);
    const acq = await signe('/mere/satisfaction/acquitter', { ids: envs.map((x) => x.id) });
    verifier('l’acquittement efface les enveloppes relevées', acq.json.acquittees === 2 && (await signe('/mere/satisfaction/relever', {})).json.enveloppes.length === 0);

    // 6. La révocation ferme la porte.
    await signe('/mere/satisfaction/revoquer', { jeton_hash: crypto.createHash('sha256').update(J).digest('hex') });
    verifier('un lien révoqué rend la page neutre', (await page(J)).status === 404);
    verifier('un lien révoqué ne se republie pas (409 lien_revoque)', (await signe('/mere/satisfaction/publier', publication(J))).json.code === 'lien_revoque');

    // 7. Le débit des dépôts est limité par adresse.
    const JD = jeton();
    await signe('/mere/satisfaction/publier', publication(JD, { ref: 'JET-SAT1-D' }));
    const statuts = [];
    for (let i = 0; i < 12; i++) statuts.push((await deposer(JD, factice())).status);
    verifier('au-delà du débit permis par minute, le dépôt est refusé (429)', statuts.includes(429), statuts.join(','));
    const audit = JSON.stringify(((await m.relais.direct('GET', '/banc/satisfaction/tout')).json || {}).audit || []);
    verifier('le journal du relais ne porte aucune réponse', !audit.includes(SENTINELLE));
  },
});
