'use strict';
/* =============================================================================
 * SIGH-CBG : le RELAIS DE RÉFÉRENCE, famille de routes `/mere/sms*` (ADR-0009, SMS par le relais).
 * Même contrat que apps/web (SmsController, App\Relais\Sms\*) : la mère dépose un SMS DÉJÀ COMPOSÉ (un numéro au format international, un texte de 320
 * caractères au plus), signé (x-mere + x-signature = HMAC-SHA256 du corps exact, clé = secret de la mère), schéma fermé. Le relais ne juge pas le sens du
 * texte : il borne le nombre d'envois par jour, envoie par un PILOTE (ici « journal », qui n'envoie rien, ou « echec » pour l'essai), puis EFFACE le numéro et
 * le texte, après acceptation ou au cinquième échec. Le journal technique porte un identifiant et un code, jamais un numéro ni un texte.
 * ========================================================================== */
const nodeCrypto = require('node:crypto');

const NUMERO = /^\+[1-9][0-9]{7,14}$/;
const IDENTIFIANT = /^[A-Za-z0-9_-]{8,64}$/;
const DELAIS_MS = { 1: 60000, 2: 300000, 3: 900000, 4: 3600000 };
const LONGUEUR_MAX = 320;
const OCTETS_MAX = 4096;
const TENTATIVES_MAX = 5;

/* Début du jour civil d'Africa/Porto-Novo (UTC+1, sans heure d'été). */
const debutDuJour = (m) => { const decale = m + 3600000; return decale - (decale % 86400000) - 3600000; };

module.exports = function installer({ db, Err, mereOk, secretMere, plafondJour = 100, maintenant = () => Date.now() }) {
  db.exec(`CREATE TABLE IF NOT EXISTS sms_sortants (rid INTEGER PRIMARY KEY AUTOINCREMENT, uid TEXT UNIQUE, numero TEXT, texte TEXT, longueur INTEGER, statut TEXT, tentatives INTEGER DEFAULT 0,
      depose_le INTEGER, prochain_essai_le INTEGER, envoye_le INTEGER, echec_le INTEGER, efface_le INTEGER, derniere_erreur TEXT);
    CREATE TABLE IF NOT EXISTS sms_audit (rid INTEGER PRIMARY KEY AUTOINCREMENT, quand INTEGER, action TEXT, detail TEXT);`);
  const journal = (action, detail) => db.prepare('INSERT INTO sms_audit(quand,action,detail) VALUES(?,?,?)').run(maintenant(), action, detail);
  const refus = (s, code, motif) => { journal('sms_refuse', code); return new Err(s, code, motif); };
  const envoyesAujourdhui = (m) => db.prepare('SELECT COUNT(*) AS n FROM sms_sortants WHERE envoye_le >= ?').get(debutDuJour(m)).n;
  const enAttente = () => db.prepare("SELECT COUNT(*) AS n FROM sms_sortants WHERE statut='en_attente'").get().n;
  const longueur = (t) => [...t].length;
  const statut = (l) => ({ id: l.uid, statut: l.statut, tentatives: l.tentatives, longueur: l.longueur, depose_le: l.depose_le, envoye_le: l.envoye_le ?? null, echec_le: l.echec_le ?? null, erreur: l.derniere_erreur ?? null });

  /* L'autorisation précède la validation : secret, taille, signature, PUIS le JSON. */
  function corpsSigne(req, brut) {
    if (!mereOk(req)) throw new Err(403, 'mere_requise');
    if (brut.length > OCTETS_MAX) throw refus(413, 'corps_trop_gros', 'Un SMS est court : ce corps dépasse la taille permise.');
    const attendue = 'sha256=' + nodeCrypto.createHmac('sha256', secretMere).update(brut).digest('hex');
    const recue = String(req.headers['x-signature'] || '');
    if (recue.length !== attendue.length || !nodeCrypto.timingSafeEqual(Buffer.from(recue), Buffer.from(attendue))) throw refus(401, 'signature_invalide', 'La signature du corps ne correspond pas : dépôt refusé.');
    try { return JSON.parse(brut.toString('utf8')); } catch (e) { return null; }
  }

  function valider(c) {
    if (!c || typeof c !== 'object' || Array.isArray(c) || Object.keys(c).join() !== 'sms' || !c.sms || typeof c.sms !== 'object' || Array.isArray(c.sms)) return ['corps : un seul objet « sms » attendu'];
    const s = c.sms; const d = [];
    for (const k of Object.keys(s)) if (!['id', 'numero', 'texte'].includes(k)) d.push('sms.' + k.replace(/[^A-Za-z0-9_]/g, '?').slice(0, 32) + ' : champ inattendu');
    if (typeof s.id !== 'string' || !IDENTIFIANT.test(s.id)) d.push('sms.id : 8 à 64 caractères parmi lettres, chiffres, « - » et « _ »');
    if (typeof s.numero !== 'string' || !NUMERO.test(s.numero)) d.push('sms.numero : format international attendu (« + » puis 8 à 15 chiffres)');
    if (typeof s.texte !== 'string' || s.texte === '') d.push('sms.texte : texte non vide attendu');
    else if (longueur(s.texte) > LONGUEUR_MAX) d.push('sms.texte : ' + LONGUEUR_MAX + ' caractères au plus');
    else if (/[\x00-\x09\x0B-\x1F\x7F]/.test(s.texte)) d.push('sms.texte : caractère de contrôle refusé');
    return d;
  }

  /* Un tour d'envoi (le cron) : pilote « journal » (accepte) ou « echec » (refuse tout, code essai_echec). */
  function tourner(pilote, m) {
    const bilan = { envoyes: 0, echecs: 0, abandons: 0, purges: 0, plafond_atteint: false };
    bilan.purges = Number(db.prepare("DELETE FROM sms_sortants WHERE statut IN ('envoye','echec') AND efface_le < ?").run(m - 30 * 86400000).changes);
    const restant = plafondJour - envoyesAujourdhui(m);
    if (restant <= 0) { bilan.plafond_atteint = enAttente() > 0; return bilan; }
    const lignes = db.prepare("SELECT * FROM sms_sortants WHERE statut='en_attente' AND prochain_essai_le <= ? ORDER BY depose_le, rid LIMIT ?").all(m, Math.min(20, restant));
    for (const l of lignes) {
      const t = l.tentatives + 1;
      if (pilote !== 'echec') {
        db.prepare("UPDATE sms_sortants SET statut='envoye', tentatives=?, envoye_le=?, efface_le=?, numero=NULL, texte=NULL, derniere_erreur=NULL WHERE rid=?").run(t, m, m, l.rid);
        journal('sms_envoye', l.uid + ' pilote=journal longueur=' + l.longueur); bilan.envoyes++;
      } else if (t >= TENTATIVES_MAX) {
        db.prepare("UPDATE sms_sortants SET statut='echec', tentatives=?, echec_le=?, efface_le=?, numero=NULL, texte=NULL, derniere_erreur='essai_echec' WHERE rid=?").run(t, m, m, l.rid);
        journal('sms_echec', l.uid + ' essai_echec abandon apres ' + t + ' tentatives'); bilan.abandons++;
      } else {
        db.prepare("UPDATE sms_sortants SET tentatives=?, prochain_essai_le=?, derniere_erreur='essai_echec' WHERE rid=?").run(t, m + (DELAIS_MS[t] || 3600000), l.rid);
        journal('sms_echec', l.uid + ' essai_echec tentative ' + t); bilan.echecs++;
      }
    }
    bilan.plafond_atteint = envoyesAujourdhui(m) >= plafondJour && enAttente() > 0;
    return bilan;
  }

  const routes = {
    'POST /mere/sms': (req, b, q, brut) => {
      const c = corpsSigne(req, brut); const d = valider(c);
      if (d.length) throw refus(422, 'sms_invalide', 'SMS non conforme au schéma : ' + d.slice(0, 5).join(' ; '));
      const s = c.sms; const m = maintenant();
      const deja = db.prepare('SELECT * FROM sms_sortants WHERE uid=?').get(s.id);
      if (deja) return { ok: true, rejeu: true, sms: statut(deja) };
      if (envoyesAujourdhui(m) + enAttente() >= plafondJour) throw refus(429, 'plafond_atteint', 'Le plafond quotidien de SMS (' + plafondJour + ') est atteint : réessayer demain ou relever le plafond dans le .env du relais.');
      db.prepare("INSERT INTO sms_sortants(uid,numero,texte,longueur,statut,tentatives,depose_le,prochain_essai_le) VALUES(?,?,?,?,'en_attente',0,?,?)").run(s.id, s.numero, s.texte, longueur(s.texte), m, m);
      journal('sms_depose', s.id + ' longueur=' + longueur(s.texte));
      return { ok: true, rejeu: false, sms: statut(db.prepare('SELECT * FROM sms_sortants WHERE uid=?').get(s.id)) };
    },
    'POST /mere/sms/statuts': (req, b, q, brut) => {
      const c = corpsSigne(req, brut);
      const ids = c && typeof c === 'object' && !Array.isArray(c) && Object.keys(c).join() === 'ids' && Array.isArray(c.ids) ? c.ids : null;
      if (!ids || ids.length > 200 || ids.some((i) => typeof i !== 'string' || !IDENTIFIANT.test(i))) throw refus(422, 'ids_invalides', 'Le corps doit porter « ids » : une liste de 200 identifiants au plus.');
      return { statuts: [...new Set(ids)].map((id) => { const l = db.prepare('SELECT * FROM sms_sortants WHERE uid=?').get(id); return l ? statut(l) : { id, statut: 'inconnu' }; }) };
    },
    'GET /mere/sms/etat': (req) => {
      if (!mereOk(req)) throw new Err(403, 'mere_requise');
      return { plafond_jour: plafondJour, envoyes_aujourdhui: envoyesAujourdhui(maintenant()), en_attente: enAttente(), tentatives_max: TENTATIVES_MAX, longueur_max: LONGUEUR_MAX, pilote: 'journal' };
    },
  };
  const banc = {
    'POST /banc/sms/tourner': (req, b) => tourner(b.pilote === 'echec' ? 'echec' : 'journal', maintenant() + Math.max(0, +b.avance_ms || 0)),
    'GET /banc/sms/tout': () => ({ lignes: db.prepare('SELECT * FROM sms_sortants ORDER BY rid').all(), audit: db.prepare('SELECT * FROM sms_audit ORDER BY rid').all() }),
  };
  return { routes, banc };
};
