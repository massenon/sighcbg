// Essais du chiffrement de la satisfaction en ligne (node --test tests/js/satisfaction.test.mjs, depuis apps/web) : le script du NAVIGATEUR chiffre,
// le côté MÈRE de référence (packages/sync/banc/satisfaction-cle.js) déchiffre. Les deux voies du navigateur (Web Crypto X25519 et repli BigInt) s'accordent.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import crypto from 'node:crypto';
import { charger } from './satisfaction.mjs';

const require = createRequire(import.meta.url);
const M = require('../../../../packages/sync/banc/satisfaction-cle.js');
const hex = (h) => Uint8Array.from(Buffer.from(h, 'hex'));

test('X25519 en BigInt : vecteurs de la RFC 7748 (section 5.2)', () => {
  const S = charger();
  const r = S.scalarMult(hex('a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4'), hex('e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c'));
  assert.equal(Buffer.from(r).toString('hex'), 'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552');
  const r2 = S.scalarMult(hex('4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d'), hex('e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493'));
  assert.equal(Buffer.from(r2).toString('hex'), '95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957');
});

test('le repli BigInt donne le même secret que le X25519 de Node, sur vingt paires tirées au hasard', () => {
  const S = charger();
  for (let i = 0; i < 20; i++) {
    const a = M.nouvellePaire();
    const b = M.nouvellePaire();
    const prive = crypto.createPrivateKey({ key: { kty: 'OKP', crv: 'X25519', d: a.privee, x: a.publique }, format: 'jwk' });
    const pub = crypto.createPublicKey({ key: { kty: 'OKP', crv: 'X25519', x: b.publique }, format: 'jwk' });
    const attendu = crypto.diffieHellman({ privateKey: prive, publicKey: pub });
    assert.equal(Buffer.from(S.scalarMult(M.deB64u(a.privee), M.deB64u(b.publique))).toString('hex'), attendu.toString('hex'));
    assert.equal(Buffer.from(S.scalarMult(M.deB64u(a.privee), Uint8Array.from([9, ...new Array(31).fill(0)]))).toString('base64url'), a.publique);
  }
});

for (const [voie, opts] of [['webcrypto', {}], ['repli forcé', { forcerRepli: true }], ['navigateur sans X25519', { sansX25519: true }]]) {
  test(`le navigateur chiffre (${voie}), la mère seule déchiffre ; un autre lien ou une altération échoue`, async () => {
    const S = charger(opts.sansX25519 === true);
    const paire = M.nouvellePaire();
    const pub = { jeton: 'abcdefghijkmnopqrstuvwxy', kid: paire.kid, cle_publique: paire.publique };
    const reponses = { Q_ACCUEIL: '5', Q_RECO: 'Oui', Q_COM: 'Accueil chaleureux, attente un peu longue.' };
    const env = await S.chiffrer(reponses, pub, { forcerRepli: opts.forcerRepli === true });
    assert.equal(env.voie, voie === 'webcrypto' ? 'webcrypto' : 'repli');
    assert.equal(env.v, 'sat1');
    // Opacité : aucune réponse en clair dans l'enveloppe, et un chiffré de taille multiple de 256 (le bourrage cache la longueur du commentaire).
    assert.ok(!JSON.stringify(env).includes('chaleureux'));
    assert.equal((M.deB64u(env.ct).length - 16) % 256, 0);
    assert.deepEqual(M.dechiffrer(env, paire, pub.jeton).reponses, reponses);
    assert.throws(() => M.dechiffrer(env, paire, 'autrejetonautrejetonautr'));
    const altere = { ...env, ct: Buffer.from(M.deB64u(env.ct).map((x, i) => (i === 3 ? x ^ 1 : x))).toString('base64url') };
    assert.throws(() => M.dechiffrer(altere, paire, pub.jeton));
    const autreCle = M.nouvellePaire();
    assert.throws(() => M.dechiffrer(env, { ...autreCle, kid: paire.kid }, pub.jeton));
  });
}

test('une clé publique nulle (point de petit ordre) est refusée par le navigateur', async () => {
  const S = charger();
  await assert.rejects(S.chiffrer({ Q: '1' }, { jeton: 'x', kid: 'y', cle_publique: Buffer.alloc(32).toString('base64url') }, { forcerRepli: true }));
});
