// Engendre packages/sync_dart/test/vecteurs/satisfaction_navigateur.json : des enveloppes produites par le SCRIPT DU NAVIGATEUR (public/js/satisfaction.js,
// voie Web Crypto X25519 ET voie de repli BigInt) pour une paire de clinique fixe, que le test Dart de la mère doit déchiffrer à l'identique.
// Usage (depuis apps/web) : node tests/js/vecteurs-satisfaction.mjs
import { writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { charger } from './satisfaction.mjs';

const M = createRequire(import.meta.url)('../../../../packages/sync/banc/satisfaction-cle.js');
const paire = M.nouvellePaire();
const jeton = 'mnpqrstuvwxyzabcdefghijk';
const pub = { jeton, kid: paire.kid, cle_publique: paire.publique };
const cas = [];
for (const [voie, opts, reponses] of [
  ['webcrypto', {}, { Q_ACCUEIL: '5', Q_RECO: 'Oui', Q_COM: 'Accueil chaleureux, merci à l’équipe.' }],
  ['repli', { forcerRepli: true }, { Q_ACCUEIL: '2', Q_RECO: 'Plutôt non' }],
  ['repli', { forcerRepli: true }, { Q_COM: 'é'.repeat(300) }],
]) {
  const S = charger();
  const enveloppe = await S.chiffrer(reponses, pub, opts);
  if (enveloppe.voie !== voie) throw new Error(`voie attendue ${voie}, obtenue ${enveloppe.voie}`);
  delete enveloppe.voie;
  if (JSON.stringify(M.dechiffrer(enveloppe, paire, jeton).reponses) !== JSON.stringify(reponses)) throw new Error('aller-retour Node en échec');
  cas.push({ voie, reponses, enveloppe });
}
const sortie = new URL('../../../../packages/sync_dart/test/vecteurs/satisfaction_navigateur.json', import.meta.url);
writeFileSync(sortie, JSON.stringify({ source: 'apps/web/public/js/satisfaction.js (exécuté par Node, Web Crypto)', schema: 'sat1', paire, jeton, cas }, null, 1) + '\n');
console.log(`${cas.length} enveloppes écrites dans ${sortie.pathname}`);
