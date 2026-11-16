// Outil d'essai : exécute le MÊME script que le navigateur (public/js/satisfaction.js) dans un contexte isolé, avec le Web Crypto de Node.
// Entrée (argument JSON ou entrée standard) : { action: 'chiffrer', reponses, publication: {jeton, kid, cle_publique}, forcerRepli? }
//                                            { action: 'scalarmult', k, u }  (base64url, 32 octets chacun)
//                                            { action: 'paire' }  ou  { action: 'dechiffrer', enveloppe, paire, jeton } : le CÔTÉ MÈRE de référence
//                                            (packages/sync/banc/satisfaction-cle.js), pour les essais seulement : le relais n'en charge rien.
// Sortie : JSON sur la sortie standard ({ enveloppe } ou { resultat }, ou { erreur }).
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { createRequire } from 'node:module';

const mere = () => createRequire(import.meta.url)('../../../../packages/sync/banc/satisfaction-cle.js');

export function charger(sansX25519 = false) {
  const code = readFileSync(new URL('../../public/js/satisfaction.js', import.meta.url), 'utf8');
  let cryptoCtx = globalThis.crypto;
  if (sansX25519) {
    // Un navigateur dont Web Crypto ignore X25519 : generateKey refuse, le script prend son repli BigInt.
    const vrai = globalThis.crypto.subtle;
    const subtle = new Proxy(vrai, { get: (t, p) => (p === 'generateKey' ? async () => { throw new Error('NotSupportedError'); } : t[p].bind(t)) });
    cryptoCtx = { subtle, getRandomValues: (a) => globalThis.crypto.getRandomValues(a) };
  }
  const ctx = { globalThis: null, TextEncoder, TextDecoder, atob, btoa, BigInt, crypto: cryptoCtx };
  ctx.globalThis = ctx;
  vm.runInNewContext(code, ctx);
  return ctx.SighSatisfaction;
}

async function principal() {
  const brut = process.argv[2] ?? readFileSync(0, 'utf8');
  const e = JSON.parse(brut);
  try {
    if (e.action === 'paire') {
      process.stdout.write(JSON.stringify({ paire: mere().nouvellePaire() }));
    } else if (e.action === 'dechiffrer') {
      process.stdout.write(JSON.stringify({ reponses: mere().dechiffrer(e.enveloppe, e.paire, e.jeton).reponses }));
    } else if (e.action === 'scalarmult') {
      const S = charger();
      process.stdout.write(JSON.stringify({ resultat: S.versB64u(S.scalarMult(S.deB64u(e.k), S.deB64u(e.u))) }));
    } else {
      const S = charger(e.sansX25519 === true);
      const env = await S.chiffrer(e.reponses, e.publication, { forcerRepli: e.forcerRepli === true });
      process.stdout.write(JSON.stringify({ enveloppe: env }));
    }
  } catch (x) {
    process.stdout.write(JSON.stringify({ erreur: String((x && x.message) || x) }));
  }
}

if (import.meta.url === `file://${process.argv[1]}`) await principal();
