/* SATISFACTION EN LIGNE (décision de la Direction du 16/11/2026, section 8) : la réponse d'un patient est CHIFFRÉE ICI, dans son navigateur, avec la clé
   PUBLIQUE de la clinique. Le relais ne reçoit qu'une enveloppe qu'il ne peut pas lire : la clé privée ne quitte jamais le poste mère, seul à déchiffrer.

   Schéma « sat1 » (le même que packages/sync_dart/lib/src/satisfaction_en_ligne.dart, éprouvé par des vecteurs croisés) :
     1. une paire X25519 ÉPHÉMÈRE est tirée pour CETTE réponse (Web Crypto si le navigateur connaît X25519, sinon l'échelle de Montgomery ci-dessous, en BigInt) ;
     2. secret partagé = X25519(clé éphémère, clé publique de la clinique) ; un secret nul (point de petit ordre) est refusé ;
     3. clé = HKDF-SHA256(secret, sel = clé éphémère publique || clé publique de la clinique, info = « sigh-satisfaction-v1 »), 32 octets ;
     4. AES-256-GCM, nonce de 12 octets tiré au hasard, données authentifiées = « sat1|<kid>|<jeton> » : une enveloppe déplacée vers un autre lien échoue ;
     5. le clair est un JSON { v: 1, reponses: {...}, bourrage } complété d'espaces jusqu'à un multiple de 256 octets : la taille de l'enveloppe ne trahit pas la
        longueur d'un commentaire.
   Aucun nom, aucun numéro de dossier, aucune adresse réseau n'entre dans le clair. Aucune ressource externe : ce fichier est servi par le relais lui-même. */
(function (racine) {
  'use strict';
  var enc = new TextEncoder();
  var VERSION = 'sat1';
  var INFO = 'sigh-satisfaction-v1';
  var BLOC = 256;

  function versB64u(o) { var s = ''; for (var i = 0; i < o.length; i++) s += String.fromCharCode(o[i]); return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
  function deB64u(t) {
    var s = String(t || '').replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '=';
    var b = atob(s), o = new Uint8Array(b.length); for (var i = 0; i < b.length; i++) o[i] = b.charCodeAt(i); return o;
  }
  function concat(a, b) { var o = new Uint8Array(a.length + b.length); o.set(a, 0); o.set(b, a.length); return o; }

  /* --- X25519 (RFC 7748) en BigInt : repli pour les navigateurs dont Web Crypto ne connaît pas X25519. Non constant en temps : la clé secrète est
     ÉPHÉMÈRE, tirée pour une seule réponse, sur le téléphone du répondant ; aucun tiers n'y mesure quoi que ce soit. ---------------------------------- */
  var P = (BigInt(1) << BigInt(255)) - BigInt(19);
  var A24 = BigInt(121665);
  function mod(a) { var r = a % P; return r < BigInt(0) ? r + P : r; }
  function puissance(b, e) { var r = BigInt(1); b = mod(b); while (e > BigInt(0)) { if (e & BigInt(1)) r = mod(r * b); b = mod(b * b); e >>= BigInt(1); } return r; }
  function lireLE(o) { var r = BigInt(0); for (var i = o.length - 1; i >= 0; i--) r = (r << BigInt(8)) + BigInt(o[i]); return r; }
  function ecrireLE(n) { var o = new Uint8Array(32); for (var i = 0; i < 32; i++) { o[i] = Number(n & BigInt(255)); n >>= BigInt(8); } return o; }
  function scalarMult(k, u) {
    var e = new Uint8Array(k); e[0] &= 248; e[31] &= 127; e[31] |= 64;
    var uu = new Uint8Array(u); uu[31] &= 127;
    var x1 = mod(lireLE(uu)), x2 = BigInt(1), z2 = BigInt(0), x3 = x1, z3 = BigInt(1), swap = 0;
    var n = lireLE(e);
    for (var t = 254; t >= 0; t--) {
      var kt = Number((n >> BigInt(t)) & BigInt(1));
      swap ^= kt;
      if (swap) { var a = x2; x2 = x3; x3 = a; a = z2; z2 = z3; z3 = a; }
      swap = kt;
      var A = mod(x2 + z2), AA = mod(A * A), B = mod(x2 - z2), BB = mod(B * B), E = mod(AA - BB);
      var C = mod(x3 + z3), D = mod(x3 - z3), DA = mod(D * A), CB = mod(C * B);
      x3 = mod((DA + CB) * (DA + CB)); z3 = mod(x1 * mod((DA - CB) * (DA - CB)));
      x2 = mod(AA * BB); z2 = mod(E * mod(AA + A24 * E));
    }
    if (swap) { x2 = x3; z2 = z3; }
    return ecrireLE(mod(x2 * puissance(z2, P - BigInt(2))));
  }
  var BASE = (function () { var o = new Uint8Array(32); o[0] = 9; return o; })();

  /* Une paire éphémère et le secret partagé avec la clé publique de la clinique. `forcerRepli` sert aux essais (les deux voies doivent s'accorder). */
  async function echange(clePubliqueClinique, forcerRepli) {
    var subtle = racine.crypto.subtle;
    if (!forcerRepli) {
      try {
        var paire = await subtle.generateKey({ name: 'X25519' }, true, ['deriveBits']);
        var pub = new Uint8Array(await subtle.exportKey('raw', paire.publicKey));
        var autre = await subtle.importKey('raw', clePubliqueClinique, { name: 'X25519' }, false, []);
        var s = new Uint8Array(await subtle.deriveBits({ name: 'X25519', public: autre }, paire.privateKey, 256));
        return { epk: pub, secret: s, voie: 'webcrypto' };
      } catch (e) { /* navigateur sans X25519 : repli */ }
    }
    var priv = racine.crypto.getRandomValues(new Uint8Array(32));
    return { epk: scalarMult(priv, BASE), secret: scalarMult(priv, clePubliqueClinique), voie: 'repli' };
  }

  function clairBourre(reponses) {
    var corps = JSON.stringify({ v: 1, reponses: reponses, bourrage: '' });
    var manque = (BLOC - (enc.encode(corps).length % BLOC)) % BLOC;
    return enc.encode(JSON.stringify({ v: 1, reponses: reponses, bourrage: new Array(manque + 1).join(' ') }));
  }

  /* Chiffre les réponses pour la clinique. `publication` = { jeton, kid, cle_publique } tels que la page les porte. Rend l'enveloppe à déposer. */
  async function chiffrer(reponses, publication, options) {
    var pk = deB64u(publication.cle_publique);
    if (pk.length !== 32) throw new Error('Clé publique de la clinique invalide.');
    var ex = await echange(pk, options && options.forcerRepli);
    var nul = true; for (var i = 0; i < 32; i++) if (ex.secret[i] !== 0) nul = false;
    if (nul) throw new Error('Clé publique de la clinique invalide.');
    var subtle = racine.crypto.subtle;
    var ikm = await subtle.importKey('raw', ex.secret, 'HKDF', false, ['deriveBits']);
    var octets = new Uint8Array(await subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt: concat(ex.epk, pk), info: enc.encode(INFO) }, ikm, 256));
    var cle = await subtle.importKey('raw', octets, { name: 'AES-GCM' }, false, ['encrypt']);
    var iv = racine.crypto.getRandomValues(new Uint8Array(12));
    var aad = enc.encode(VERSION + '|' + publication.kid + '|' + publication.jeton);
    var ct = new Uint8Array(await subtle.encrypt({ name: 'AES-GCM', iv: iv, additionalData: aad, tagLength: 128 }, cle, clairBourre(reponses)));
    return { v: VERSION, kid: publication.kid, epk: versB64u(ex.epk), iv: versB64u(iv), ct: versB64u(ct), voie: ex.voie };
  }

  /* --- La page : le formulaire est rendu par le relais depuis les champs PUBLIÉS par la mère (engendrés par LE générateur du domaine) ; ce script ne fait
     que lire les valeurs, chiffrer et déposer. ---------------------------------------------------------------------------------------------------------- */
  function brancher(doc) {
    var donnees = doc.getElementById('sat-donnees');
    var form = doc.getElementById('sat-formulaire');
    if (!donnees || !form) return;
    var pub = JSON.parse(donnees.textContent);
    var etat = doc.getElementById('sat-etat');
    var bouton = form.querySelector('button[type="submit"]');
    function dire(t, classe) { etat.textContent = t; etat.className = 'etat ' + (classe || ''); }
    form.hidden = false;
    var sansJs = doc.getElementById('sat-sans-js'); if (sansJs) sansJs.hidden = true;
    form.addEventListener('submit', async function (ev) {
      ev.preventDefault();
      if (!form.reportValidity()) return;
      var reponses = {};
      pub.champs.forEach(function (c) {
        var el = form.elements[c.nom];
        var v = el ? String(el.value || '').trim() : '';
        if (v !== '') reponses[c.nom] = v;
      });
      bouton.disabled = true; dire('Chiffrement et envoi de votre réponse…');
      try {
        var env = await chiffrer(reponses, pub);
        delete env.voie;
        var r = await fetch(pub.depot, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' }, body: JSON.stringify({ enveloppe: env }), credentials: 'omit', referrerPolicy: 'no-referrer' });
        if (r.ok) { form.hidden = true; doc.getElementById('sat-merci').hidden = false; return; }
        var corps = {}; try { corps = await r.json(); } catch (e) { /* corps vide */ }
        dire(corps.motif || 'Votre réponse n’a pas pu être envoyée. Réessayez plus tard.', 'erreur');
      } catch (e) {
        dire('Votre réponse n’a pas pu être envoyée : vérifiez votre connexion puis réessayez.', 'erreur');
      }
      bouton.disabled = false;
    });
  }

  racine.SighSatisfaction = { chiffrer: chiffrer, scalarMult: scalarMult, versB64u: versB64u, deB64u: deB64u, VERSION: VERSION, INFO: INFO };
  if (racine.document) {
    if (racine.document.readyState === 'loading') racine.document.addEventListener('DOMContentLoaded', function () { brancher(racine.document); });
    else brancher(racine.document);
  }
})(typeof globalThis !== 'undefined' ? globalThis : this);
