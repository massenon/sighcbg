'use strict';
/* =============================================================================
 * SIGH-CBG : le CÔTÉ MÈRE de la satisfaction en ligne, implémentation de RÉFÉRENCE (Node), pour le banc et les vecteurs croisés.
 * La mère tient une paire X25519 ; elle publie la clé PUBLIQUE au relais avec chaque lien, garde la clé PRIVÉE et déchiffre seule les enveloppes « sat1 »
 * déposées par le navigateur (apps/web/public/js/satisfaction.js). Même schéma que packages/sync_dart/lib/src/satisfaction_en_ligne.dart.
 * Ce fichier n'est JAMAIS chargé par le relais (relais.js, relais-satisfaction.js) : le relais ne détient aucune clé.
 * ========================================================================== */
const crypto = require('node:crypto');

const b64u = (b) => Buffer.from(b).toString('base64url');
const deB64u = (t) => Buffer.from(String(t || ''), 'base64url');
const INFO = 'sigh-satisfaction-v1';

/* kid = 16 premiers caractères hexadécimaux du SHA-256 de la clé publique brute. */
const kidDe = (pub) => crypto.createHash('sha256').update(pub).digest('hex').slice(0, 16);

function nouvellePaire() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('x25519');
  const jwk = privateKey.export({ format: 'jwk' });
  const pub = deB64u(jwk.x);
  return { privee: b64u(deB64u(jwk.d)), publique: b64u(pub), kid: kidDe(pub) };
}

function dechiffrer(env, paire, jeton) {
  if (!env || env.v !== 'sat1') throw new Error('version_inconnue');
  if (env.kid !== paire.kid) throw new Error('cle_inconnue');
  const pub = deB64u(paire.publique);
  const epk = deB64u(env.epk);
  const prive = crypto.createPrivateKey({ key: { kty: 'OKP', crv: 'X25519', d: paire.privee, x: paire.publique }, format: 'jwk' });
  const autre = crypto.createPublicKey({ key: { kty: 'OKP', crv: 'X25519', x: b64u(epk) }, format: 'jwk' });
  const secret = crypto.diffieHellman({ privateKey: prive, publicKey: autre });
  if (secret.every((x) => x === 0)) throw new Error('secret_nul');
  const cle = Buffer.from(crypto.hkdfSync('sha256', secret, Buffer.concat([epk, pub]), Buffer.from(INFO), 32));
  const brut = deB64u(env.ct);
  const iv = deB64u(env.iv);
  if (iv.length !== 12 || brut.length < 17) throw new Error('enveloppe_invalide');
  const d = crypto.createDecipheriv('aes-256-gcm', cle, iv);
  d.setAAD(Buffer.from(`sat1|${env.kid}|${jeton}`));
  d.setAuthTag(brut.subarray(brut.length - 16));
  const clair = Buffer.concat([d.update(brut.subarray(0, brut.length - 16)), d.final()]);
  const j = JSON.parse(clair.toString('utf8'));
  if (j.v !== 1 || typeof j.reponses !== 'object' || j.reponses === null) throw new Error('clair_invalide');
  return { reponses: j.reponses, taille: clair.length };
}

module.exports = { nouvellePaire, dechiffrer, kidDe, b64u, deB64u, INFO };
