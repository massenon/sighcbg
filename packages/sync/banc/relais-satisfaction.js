'use strict';
/* =============================================================================
 * SIGH-CBG : le RELAIS DE RÉFÉRENCE, famille de routes de la SATISFACTION EN LIGNE (décision de la Direction du 16/11/2026, section 8).
 * Contrat de apps/web (SatisfactionController) : mêmes chemins, mêmes codes, mêmes réponses neutres.
 *
 * OPAQUE par construction : n'importe ni `crypto.js` ni `satisfaction-cle.js`, ne détient aucune clé privée. Il voit un modèle de questions publié par la
 * mère (non secret), la clé PUBLIQUE de la clinique, des enveloppes chiffrées dans le navigateur, des jours de réception et des compteurs.
 *   PUBLIC  GET  /satisfaction/:jeton          page du questionnaire (HTML) ; jeton inconnu, expiré, révoqué, mal formé : LA MÊME page neutre (404)
 *           GET  /satisfaction/:jeton/modele   le modèle publié (JSON) ou la réponse neutre (404)
 *           POST /satisfaction/:jeton/reponse  dépôt d'une enveloppe { enveloppe: {v,kid,epk,iv,ct} } → 202 ; débit par adresse, plafond par lien et par jour
 *   MÈRE    POST /mere/satisfaction/{publier,revoquer,relever,acquitter}   secret `x-mere` PUIS signature `x-signature: sha256=<HMAC du corps exact>`
 * ========================================================================== */
const nodeCrypto = require('node:crypto');

const NEUTRE = { code: 'lien_invalide', motif: 'Ce lien n’est plus valable.' };
const PAGE_NEUTRE = '<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><title>Lien non valable</title></head><body><main><h1>Ce lien n’est plus valable.</h1><p>Le questionnaire est clos ou l’adresse est incomplète.</p></main></body></html>';
const CLES = ['jeton_hash', 'ref', 'expire_le', 'clinique', 'titre', 'description', 'champs', 'cle_publique', 'kid'];
const CLES_CHAMP = ['nom', 'libelle', 'type', 'requis', 'options', 'lignes'];
const CLES_ENV = ['v', 'kid', 'epk', 'iv', 'ct'];
const sha = (s) => nodeCrypto.createHash('sha256').update(s).digest('hex');
const echapper = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[c]));
const texte = (v, min, max) => typeof v === 'string' && [...v].length >= min && [...v].length <= max && !/[\x00-\x08\x0B-\x1F\x7F]/.test(v);
const estDate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s + 'T00:00:00Z')) && new Date(s + 'T00:00:00Z').toISOString().slice(0, 10) === s;
const objet = (o) => o !== null && typeof o === 'object' && !Array.isArray(o);

/* Le jour au fuseau de la clinique (Africa/Porto-Novo = UTC+1, sans heure d'été). `decalageJours` sert aux essais. */
const jourDe = (ms) => new Date(ms + 3600 * 1000).toISOString().slice(0, 10);

function defautsChamp(c) {
  if (!objet(c)) return ['objet attendu'];
  const k = Object.keys(c);
  if (k.length !== CLES_CHAMP.length || k.some((x) => !CLES_CHAMP.includes(x))) return [`clés attendues : ${CLES_CHAMP.join(', ')}`];
  const d = [];
  if (typeof c.nom !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_]{0,39}$/.test(c.nom)) d.push('nom : identifiant de 40 caractères au plus attendu');
  if (!texte(c.libelle, 1, 200)) d.push('libelle : texte de 1 à 200 caractères attendu');
  if (!['select', 'textarea'].includes(c.type)) d.push('type : select ou textarea attendu');
  if (typeof c.requis !== 'boolean') d.push('requis : vrai ou faux attendu');
  if (!Number.isInteger(c.lignes) || c.lignes < 1 || c.lignes > 10) d.push('lignes : entier de 1 à 10 attendu');
  if (!Array.isArray(c.options) || c.options.length > 20) d.push('options : liste de 20 choix au plus attendue');
  else {
    if (c.options.some((o) => !texte(o, 1, 120))) d.push('options : choix de 1 à 120 caractères attendus');
    if (c.type === 'select' && c.options.length === 0) d.push('options : une liste a besoin de ses choix');
  }
  return d;
}

function defautsPublication(p) {
  if (!objet(p)) return ['la publication doit être un objet'];
  const d = [];
  const inattendus = Object.keys(p).filter((k) => !CLES.includes(k));
  if (inattendus.length) d.push(`champ(s) inattendu(s) : ${inattendus.slice(0, 5).join(', ')}`);
  for (const k of CLES) if (!(k in p)) d.push(`champ manquant : ${k}`);
  if (d.length) return d;
  if (typeof p.jeton_hash !== 'string' || !/^[0-9a-f]{64}$/.test(p.jeton_hash)) d.push('jeton_hash : 64 caractères hexadécimaux attendus');
  if (typeof p.ref !== 'string' || !/^[A-Za-z0-9._:-]{1,64}$/.test(p.ref)) d.push('ref : identifiant technique attendu');
  if (!estDate(p.expire_le)) d.push('expire_le : date AAAA-MM-JJ attendue');
  if (!texte(p.clinique, 1, 80)) d.push('clinique : texte de 1 à 80 caractères attendu');
  if (!texte(p.titre, 1, 120)) d.push('titre : texte de 1 à 120 caractères attendu');
  if (!texte(p.description, 0, 500)) d.push('description : texte de 500 caractères au plus attendu');
  if (typeof p.cle_publique !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(p.cle_publique)) d.push('cle_publique : 32 octets en base64url attendus');
  if (typeof p.kid !== 'string' || !/^[0-9a-f]{16}$/.test(p.kid)) d.push('kid : 16 caractères hexadécimaux attendus');
  if (!Array.isArray(p.champs) || p.champs.length < 1 || p.champs.length > 40) { d.push('champs : liste de 1 à 40 champs attendue'); return d; }
  const noms = new Set();
  p.champs.forEach((c, i) => {
    for (const x of defautsChamp(c)) d.push(`champs[${i}] : ${x}`);
    if (objet(c) && typeof c.nom === 'string') { if (noms.has(c.nom)) d.push(`champs[${i}] : nom en double`); noms.add(c.nom); }
  });
  return d;
}

function defautsEnveloppe(e) {
  if (!objet(e) || Object.keys(e).length !== CLES_ENV.length || Object.keys(e).some((k) => !CLES_ENV.includes(k))) return ['clés attendues'];
  const d = [];
  if (e.v !== 'sat1') d.push('version inconnue');
  if (typeof e.kid !== 'string' || !/^[0-9a-f]{16}$/.test(e.kid)) d.push('kid invalide');
  if (typeof e.epk !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(e.epk)) d.push('epk invalide');
  if (typeof e.iv !== 'string' || !/^[A-Za-z0-9_-]{16}$/.test(e.iv)) d.push('iv invalide');
  if (typeof e.ct !== 'string' || !/^[A-Za-z0-9_-]+$/.test(e.ct)) d.push('ct invalide');
  else { const n = Math.floor((e.ct.length * 3) / 4); if (n < 272 || (n - 16) % 256 !== 0) d.push('ct : longueur inattendue'); }
  return d;
}

/* La page du questionnaire, rendue depuis les champs PUBLIÉS (même balisage que la vue Blade, sans feuille de style : le banc ne mesure que le contenu). */
function page(d) {
  const champs = d.champs.map((c) => `<div class="champ"><label for="sat-${echapper(c.nom)}">${echapper(c.libelle)}</label>${c.type === 'select'
    ? `<select id="sat-${echapper(c.nom)}" name="${echapper(c.nom)}"${c.requis ? ' required' : ''}><option value="">Choisir…</option>${c.options.map((o) => `<option value="${echapper(o)}">${echapper(o)}</option>`).join('')}</select>`
    : `<textarea id="sat-${echapper(c.nom)}" name="${echapper(c.nom)}" rows="${c.lignes}"${c.requis ? ' required' : ''}></textarea>`}</div>`).join('');
  const json = JSON.stringify(d).replace(/</g, '\\u003C').replace(/>/g, '\\u003E').replace(/&/g, '\\u0026');
  return `<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><title>${echapper(d.titre)}</title></head><body><main><p>${echapper(d.clinique)}</p><h1>${echapper(d.titre)}</h1>`
    + `<p>${echapper(d.description)}</p><p>Questionnaire ANONYME : on ne vous demande ni votre nom, ni votre numéro de dossier.</p><form id="sat-formulaire">${champs}<button type="submit">Envoyer ma réponse</button></form></main>`
    + `<script type="application/json" id="sat-donnees">${json}</script><script src="/js/satisfaction.js" defer></script></body></html>`;
}

module.exports = function installer({ db, Err, secretMere, maintenant = () => Date.now(), reglages = {} }) {
  const R = { plafondJour: 500, debitDepot: 10, debitPage: 60, enveloppeMax: 16384, publicationMax: 65536, conservationJours: 30, ...reglages };
  db.exec(`CREATE TABLE IF NOT EXISTS sat_liens (id INTEGER PRIMARY KEY AUTOINCREMENT, jeton_hash TEXT UNIQUE, ref TEXT, clinique TEXT, titre TEXT, description TEXT, champs TEXT,
      cle_publique TEXT, kid TEXT, expire_le TEXT, revoque_le INTEGER, publie_le INTEGER, jour_compte TEXT DEFAULT '', n_jour INTEGER DEFAULT 0);
    CREATE TABLE IF NOT EXISTS sat_enveloppes (rid INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE, lien_id INTEGER, enveloppe TEXT, taille INTEGER, recue_le TEXT);
    CREATE TABLE IF NOT EXISTS sat_audit (id INTEGER PRIMARY KEY AUTOINCREMENT, quand INTEGER, action TEXT, detail TEXT);`);
  const aujourdhui = () => jourDe(maintenant());
  const journal = (action, detail) => db.prepare('INSERT INTO sat_audit(quand,action,detail) VALUES(?,?,?)').run(maintenant(), action, String(detail).slice(0, 120));
  const debits = new Map(); // limite de débit par adresse ET famille de route, en mémoire (comme la table cache de Laravel) : jamais rattachée à une réponse
  function limiter(req, famille, max) {
    const cle = famille + '|' + (req.socket.remoteAddress || '');
    const minute = Math.floor(maintenant() / 60000);
    const x = debits.get(cle);
    const n = x && x.minute === minute ? x.n + 1 : 1;
    debits.set(cle, { minute, n });
    if (n > max) throw new Err(429, 'trop_de_requetes', 'Trop de requêtes : réessayez dans une minute.');
  }
  function lienOuvert(jeton) {
    if (!/^[a-z0-9]{16,64}$/.test(jeton)) return null;
    const l = db.prepare('SELECT * FROM sat_liens WHERE jeton_hash=?').get(sha(jeton));
    if (!l || l.revoque_le !== null || l.expire_le < aujourdhui()) return null;
    return l;
  }
  const donnees = (l, jeton) => ({ clinique: l.clinique, titre: l.titre, description: l.description, champs: JSON.parse(l.champs), jeton, kid: l.kid, cle_publique: l.cle_publique, depot: `/satisfaction/${jeton}/reponse` });
  function corpsMere(req, brut) {
    if (!secretMere || req.headers['x-mere'] !== secretMere) throw new Err(403, 'mere_requise');
    if (brut.length > R.publicationMax) throw new Err(413, 'corps_trop_gros', 'Ce corps dépasse la taille permise.');
    const attendue = 'sha256=' + nodeCrypto.createHmac('sha256', secretMere).update(brut).digest('hex');
    const recue = String(req.headers['x-signature'] || '');
    if (recue.length !== attendue.length || !nodeCrypto.timingSafeEqual(Buffer.from(recue), Buffer.from(attendue))) {
      journal('satisfaction_refusee', 'signature_invalide');
      throw new Err(401, 'signature_invalide', 'La signature du corps ne correspond pas : demande refusée.');
    }
    try { const j = JSON.parse(brut.toString('utf8') || '{}'); return objet(j) ? j : {}; } catch (e) { return {}; }
  }
  function purger() {
    const seuilJour = jourDe(maintenant() - R.conservationJours * 86400000);
    const seuilMs = maintenant() - R.conservationJours * 86400000;
    db.prepare('DELETE FROM sat_liens WHERE (expire_le < ? OR (revoque_le IS NOT NULL AND revoque_le < ?)) AND id NOT IN (SELECT lien_id FROM sat_enveloppes)').run(seuilJour, seuilMs);
  }

  /* Rend `undefined` si la route n'est pas de cette famille. */
  function traiter(req, u, q, brut) {
    const m = /^\/satisfaction\/([^/]*)(\/modele|\/reponse)?$/.exec(u.pathname);
    if (m) {
      const jeton = decodeURIComponent(m[1]);
      if (req.method === 'GET' && !m[2]) {
        limiter(req, 'page', R.debitPage);
        const l = lienOuvert(jeton);
        return l ? { __html: page(donnees(l, jeton)), statut: 200 } : { __html: PAGE_NEUTRE, statut: 404 };
      }
      if (req.method === 'GET' && m[2] === '/modele') {
        limiter(req, 'page', R.debitPage);
        const l = lienOuvert(jeton);
        if (!l) { const e = new Err(404, NEUTRE.code, NEUTRE.motif); throw e; }
        return donnees(l, jeton);
      }
      if (req.method === 'POST' && m[2] === '/reponse') {
        limiter(req, 'depot', R.debitDepot);
        const l = lienOuvert(jeton); /* le lien d'abord : la réponse neutre quelle que soit la forme du corps */
        if (!l) throw new Err(404, NEUTRE.code, NEUTRE.motif);
        if (brut.length > R.enveloppeMax) throw new Err(413, 'enveloppe_trop_grosse', 'Votre réponse est trop longue : raccourcissez le commentaire.');
        let j; try { j = JSON.parse(brut.toString('utf8')); } catch (e) { j = null; }
        if (!objet(j) || Object.keys(j).join() !== 'enveloppe' || defautsEnveloppe(j.enveloppe).length) throw new Err(422, 'enveloppe_invalide', 'Réponse illisible : rechargez la page et recommencez.');
        if (j.enveloppe.kid !== l.kid) throw new Err(409, 'cle_perimee', 'Le questionnaire a été mis à jour : rechargez la page et recommencez.');
        const jour = aujourdhui();
        const n = l.jour_compte === jour ? l.n_jour : 0;
        if (n >= R.plafondJour) throw new Err(429, 'plafond_atteint', 'Ce questionnaire a reçu beaucoup de réponses aujourd’hui : réessayez demain.');
        db.prepare('UPDATE sat_liens SET jour_compte=?, n_jour=? WHERE id=?').run(jour, n + 1, l.id);
        const t = JSON.stringify(j.enveloppe);
        db.prepare('INSERT INTO sat_enveloppes(id,lien_id,enveloppe,taille,recue_le) VALUES(?,?,?,?,?)').run(nodeCrypto.randomUUID(), l.id, t, t.length, jour);
        return { ok: true, __statut: 202 };
      }
      return undefined;
    }
    if (req.method !== 'POST' || !u.pathname.startsWith('/mere/satisfaction/')) return undefined;
    const quoi = u.pathname.slice('/mere/satisfaction/'.length);
    if (!['publier', 'revoquer', 'relever', 'acquitter'].includes(quoi)) return undefined;
    const p = corpsMere(req, brut);
    if (quoi === 'publier') {
      const d = defautsPublication(p);
      if (d.length) { journal('satisfaction_refusee', 'publication_invalide'); throw new Err(422, 'publication_invalide', 'Publication non conforme : ' + d.slice(0, 5).join(' ; ')); }
      const ex = db.prepare('SELECT * FROM sat_liens WHERE jeton_hash=?').get(p.jeton_hash);
      if (ex && ex.revoque_le !== null) throw new Err(409, 'lien_revoque', 'Ce lien est révoqué : il ne se republie pas. Ouvrir un nouveau lien.');
      const v = [p.ref, p.clinique, p.titre, p.description, JSON.stringify(p.champs), p.cle_publique, p.kid, p.expire_le, maintenant()];
      if (ex) db.prepare('UPDATE sat_liens SET ref=?, clinique=?, titre=?, description=?, champs=?, cle_publique=?, kid=?, expire_le=?, publie_le=? WHERE id=?').run(...v, ex.id);
      else db.prepare('INSERT INTO sat_liens(ref,clinique,titre,description,champs,cle_publique,kid,expire_le,publie_le,jeton_hash) VALUES(?,?,?,?,?,?,?,?,?,?)').run(...v, p.jeton_hash);
      journal('satisfaction_publiee', p.ref);
      return { ok: true, cree: !ex };
    }
    if (quoi === 'revoquer') {
      if (typeof p.jeton_hash !== 'string' || !/^[0-9a-f]{64}$/.test(p.jeton_hash)) throw new Err(422, 'jeton_hash_invalide', 'jeton_hash : 64 caractères hexadécimaux attendus.');
      const l = db.prepare('SELECT * FROM sat_liens WHERE jeton_hash=?').get(p.jeton_hash);
      if (!l) throw new Err(404, 'lien_inconnu', 'Aucun lien publié ne porte ce jeton.');
      if (l.revoque_le === null) { db.prepare('UPDATE sat_liens SET revoque_le=? WHERE id=?').run(maintenant(), l.id); journal('satisfaction_revoquee', l.ref); }
      return { ok: true };
    }
    if (quoi === 'relever') {
      const lim = Math.max(1, Math.min(200, Number(p.limite) || 100));
      purger();
      const rows = db.prepare('SELECT e.id, l.ref, e.recue_le, e.enveloppe FROM sat_enveloppes e JOIN sat_liens l ON l.id=e.lien_id ORDER BY e.rid LIMIT ?').all(lim);
      if (rows.length) journal('satisfaction_relevee', `${rows.length} enveloppe(s)`);
      return { enveloppes: rows.map((r) => ({ id: r.id, ref: r.ref, recue_le: r.recue_le, enveloppe: JSON.parse(r.enveloppe) })), fin: rows.length < lim };
    }
    const ids = (Array.isArray(p.ids) ? p.ids : []).filter((i) => typeof i === 'string' && /^[0-9a-f-]{36}$/.test(i)).slice(0, 500);
    let n = 0;
    for (const i of ids) n += Number(db.prepare('DELETE FROM sat_enveloppes WHERE id=?').run(i).changes);
    if (n) journal('satisfaction_acquittee', `${n} enveloppe(s) effacée(s)`);
    return { acquittees: n };
  }

  /* Crochets du banc (jamais en production) : tout lire, reculer l'expiration d'un lien. */
  const banc = {
    'GET /banc/satisfaction/tout': () => ({ liens: db.prepare('SELECT * FROM sat_liens').all(), enveloppes: db.prepare('SELECT * FROM sat_enveloppes').all(), audit: db.prepare('SELECT * FROM sat_audit').all() }),
    'POST /banc/satisfaction/vieillir': (req, b) => { db.prepare('UPDATE sat_liens SET expire_le=? WHERE ref=?').run(String(b.expire_le), String(b.ref)); return { ok: true }; },
  };
  return { traiter, banc, defautsPublication, defautsEnveloppe };
};
