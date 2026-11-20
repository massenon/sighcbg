#!/usr/bin/env node
// Puits SMTP de test pour SIGH-CBG (Node pur, module `net`/`tls`, aucune dépendance).
//
// Il joue le serveur de messagerie face au client Dart (`packages/sync_dart/lib/src/smtp.dart`) pour `smtp_test.dart` : un vrai message part par le
// protocole, chaque refus est reproductible, et le test relit ce que le serveur a reçu.
//
// Arguments : --user=… --pass=… (identifiants acceptés ; vides = aucune authentification exigée)
//             --mode=aucun|starttls|ssl (chiffrement offert ; `aucun` n'annonce pas STARTTLS)
//             --refuser=a@b.cc[,c@d.ee] (destinataires refusés : réponse 550)
//             --echo=1 (serveur « maladroit » : son refus d'authentification recopie ce qu'il a reçu)
// Sortie standard, une ligne par évènement :
//             PRET <port>      le serveur écoute (port libre choisi par le système, sur 127.0.0.1)
//             MSG <json>       un message accepté : {entetes (clés en minuscules, mots encodés décodés), corps (décodé, sans dot-stuffing),
//                              de, a (destinataires), commandes (suite des commandes de la connexion, « AUTH PLAIN ok » / « AUTH PLAIN refus »)}
// Le certificat TLS est AUTO-SIGNÉ et propre à ce fichier (clé de test, sans valeur) : un client qui contrôle les certificats doit donc refuser.
'use strict';
const net = require('net');
const tls = require('tls');

const args = Object.fromEntries(process.argv.slice(2).filter((a) => a.startsWith('--')).map((a) => {
  const i = a.indexOf('=');
  return i < 0 ? [a.slice(2), '1'] : [a.slice(2, i), a.slice(i + 1)];
}));
const user = args.user || '';
const pass = args.pass || '';
const mode = args.mode || 'aucun';
const refuses = (args.refuser || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
const echo = args.echo === '1';

const KEY = `-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCE3SFsvUxiO7/F
Kcl9qsD04b1TFI2JRVjTQ/mVGyHkeH025t+UAkixPc+BxwKuEkMmUjs6IpkCoJ+P
RcdKNBvCZ/19XNKDHFnCP7/EaM/LWTIU5ZkRZ/WxsSWLkj6ijIA1YwbvInfiZ5XJ
Ju8APppwfnl8kp5XzvloafBYSkwoj2BW9dndXA2lMi+EGTQ2GIMS8O3KiLAQP7yH
F8SZOzyTgWwptolCBcgGgFEeOUyn9+wLEUljdo8AcXq6riN6PtgA0c5vw0gO1i9F
bnGX1g7HoZH6+tq2++hpP9CFUxIzQ0pXQqEcQBIrG3RnURUKsYePhxrvzaX6nUcM
GPnIIo1nAgMBAAECggEAAimBEj5wYEbdo40/CKr/Mdz8kj4K4Zl9zQ5VoO4MmqW1
T+/o4oU4/p1lY5TD/+YvLo/3A8atW8QWZKP7jsMTUpITp3cbu+N5uHYGHmGgRAxj
CsEDwStCbc5WsJNELqv/qB7A7aJPdiE+aEQYbpYWOE9ula7jIcWt/FuA/EbVP3Gz
3HBqwkffW22vTl4glZmE2IbR7HtsSC1RHT8oHXkGbdaXTw0sPef7E+GUUSwzg3v+
hTRZ/bjsTQN8zyg5K3lUU6bBcLJI4tuQmtTg34LSq+B4mus12sez9XoLurx1WONA
wlhf3+Gwbk/rdhBA1hjHl9Csm0J1+8+Y+13qcViu1QKBgQC6HN917wIgS78ggT6a
ljkfgbQU0r29f4jl+hvbC+TpanxpLKVDbHp17xTOc4vYEoBKkV7cC9bzApZR7IPJ
gATgE3xPd5F0O0lELidVSLUuPUxuqt/SfFKQYUmRK3KogzAyS6S+Y2ynRY/lDSzz
h1lCg/sj5wcdgO9Jh0WBm5uUawKBgQC2wWbgGl3ay1ZRXnG3GDoEJDiJ7E7I5RBN
WqGSRHPAxSi98YzSW26FIfGkz8JLQLtwszd7IG956+dxnzr0ol92T7rFEmy8oOoP
126MMW/OP+MBIk1+kea8cZPIWEVy2J3rnWhN9Q9aF/0m8JfaYMBmgfDraIjI+uuc
EnkFX4FJ9QKBgGqR0+c89/O0S/n55/Yu5QDEjXCLB/j1iVde8wpn8ikyP5Ed7ngA
KtNTFo/tG/ubBHkuaqoH4Yp/RcIdc40zUBdbMQh0CAcNV7PB1eYA3zZeBWEtWUK2
y7Q+8Rg+T8ZscHGsXOZkGjhiHbZj6AR+0T7EQk9Zn/pl9R8eZU+E4f6HAoGAMMZv
QXJoCCPqtq7BJL+nhEFygYT7Bez0q+B7bMEuL42vMPqNvfq/BXMovfbhARqWrB54
uTjP57dJPu7jWjUXy0i+LSicsr8zmOTDUVFEaMRuPng8PIKOFU8uxPKiHmOnyiFp
nBzCayYp30GpFZRq5TDa7skocJNfXHklqYRyyh0CgYAiSPi1KHN/pKZAXK6HphFL
Eqxg3GdzcEzS29j4wstZBZJtJHKXtimnaREP33bYVzl+WGP8v/5EXJQ3S96p8/16
9rMIzzWV/fxzEaYEc5YlpH5SARy3722pcDmKFWiC/zJouaTOQBqpTAuQRdjB2CHm
0qbFgDxYjvl62ABFfgAfng==
-----END PRIVATE KEY-----`;
const CERT = `-----BEGIN CERTIFICATE-----
MIIDFzCCAf+gAwIBAgIUHdVlBW42zMil1PZaww9vrgqc2dowDQYJKoZIhvcNAQEL
BQAwGjEYMBYGA1UEAwwPcHVpdHMtc210cC10ZXN0MCAXDTI2MTEwOTIxMjMzOVoY
DzIxMjYxMDE2MjEyMzM5WjAaMRgwFgYDVQQDDA9wdWl0cy1zbXRwLXRlc3QwggEi
MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCE3SFsvUxiO7/FKcl9qsD04b1T
FI2JRVjTQ/mVGyHkeH025t+UAkixPc+BxwKuEkMmUjs6IpkCoJ+PRcdKNBvCZ/19
XNKDHFnCP7/EaM/LWTIU5ZkRZ/WxsSWLkj6ijIA1YwbvInfiZ5XJJu8APppwfnl8
kp5XzvloafBYSkwoj2BW9dndXA2lMi+EGTQ2GIMS8O3KiLAQP7yHF8SZOzyTgWwp
tolCBcgGgFEeOUyn9+wLEUljdo8AcXq6riN6PtgA0c5vw0gO1i9FbnGX1g7HoZH6
+tq2++hpP9CFUxIzQ0pXQqEcQBIrG3RnURUKsYePhxrvzaX6nUcMGPnIIo1nAgMB
AAGjUzBRMB0GA1UdDgQWBBTVg164sXeG0gBeD1wxt/70dzTbdTAfBgNVHSMEGDAW
gBTVg164sXeG0gBeD1wxt/70dzTbdTAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3
DQEBCwUAA4IBAQCBA1BQCQLvcVPwOvxNRgKdLPb+2xQgHtRvmTBHK3qqd4azLc+O
IS7cT/ipP+64ztBc2PlQ8PWv9EYkiPxyyKyGffEv3XfVWiCxXtU7iRvkA1fPRfds
PrBcyJ11xRPtxCJlCnjEbDmkaYX28DGFFOtdPWY48BlzfE5JnrfzsW5mw82h9FZh
Vsw/4UxRFByRIu066n0Uo3BPExSmyjqwoT1UNHx6koL02VNllcOr6BS7lrGa6sYD
/yURxo+1DkORBv2nFlp22gTnOe29YkIwVLkPk4ykWuCRD1jszHvBIhEcVvnZQN68
ovmKiKTi9g9vDQfyEF2a2tVsrmwEhNYQBFj6
-----END CERTIFICATE-----`;

const b64 = (s) => Buffer.from(String(s).trim(), 'base64').toString('utf8');
const decoderMots = (v) => v.replace(/=\?UTF-8\?B\?([A-Za-z0-9+/=]*)\?=/gi, (_, x) => Buffer.from(x, 'base64').toString('utf8'));

function analyser(brut, de, a, commandes) {
  const sep = brut.indexOf('\r\n\r\n');
  const tete = sep < 0 ? brut : brut.slice(0, sep);
  const corps = sep < 0 ? '' : brut.slice(sep + 4);
  const entetes = {};
  for (const l of tete.replace(/\r\n[ \t]+/g, ' ').split('\r\n')) {
    const i = l.indexOf(':');
    if (i > 0) entetes[l.slice(0, i).toLowerCase()] = decoderMots(l.slice(i + 1).trim());
  }
  let texte = corps.replace(/\r\n/g, '');
  const enc = (entetes['content-transfer-encoding'] || '').toLowerCase();
  texte = enc === 'base64' ? Buffer.from(texte, 'base64').toString('utf8') : corps.replace(/\r\n$/, '');
  return { entetes, corps: texte, de, a, commandes };
}

function session(socket, dejaTls) {
  let enTls = dejaTls;
  let flux = socket;
  let tampon = '';
  let etat = 'commande'; // commande | login-user | login-pass | data
  let de = '';
  let a = [];
  let commandes = [];
  let donnees = '';
  let loginUser = '';
  const ecrire = (t) => { try { flux.write(t + '\r\n'); } catch (_) { /* connexion perdue */ } };

  const authentifier = (u, p, nom) => {
    const ok = (user === '' && pass === '') || (u === user && p === pass);
    commandes.push(ok ? `${nom} ok` : `${nom} refus`);
    if (ok) ecrire('235 2.7.0 Authentification réussie');
    else ecrire(`535 5.7.8 Authentification refusée${echo ? `, reçu : ${p}` : ''}`);
  };

  const traiter = (ligne) => {
    if (etat === 'data') {
      if (ligne === '.') {
        etat = 'commande';
        const brut = donnees;
        donnees = '';
        const msg = analyser(brut, de, a, commandes.slice());
        process.stdout.write('MSG ' + JSON.stringify(msg) + '\n');
        ecrire('250 2.0.0 Message accepté pour livraison');
        de = ''; a = [];
      } else {
        donnees += (ligne.startsWith('..') ? ligne.slice(1) : ligne) + '\r\n';
      }
      return;
    }
    if (etat === 'login-user') {
      loginUser = b64(ligne);
      etat = 'login-pass';
      ecrire('334 ' + Buffer.from('Password:').toString('base64'));
      return;
    }
    if (etat === 'login-pass') {
      etat = 'commande';
      authentifier(loginUser, b64(ligne), 'AUTH LOGIN');
      return;
    }
    const maj = ligne.toUpperCase();
    const verbe = maj.split(' ')[0];
    if (verbe === 'EHLO' || verbe === 'HELO') {
      commandes.push(verbe);
      if (verbe === 'HELO') return ecrire('250 puits-smtp');
      const l = ['250-puits-smtp'];
      if (mode === 'starttls' && !enTls) l.push('250-STARTTLS');
      l.push('250-8BITMIME', '250 AUTH PLAIN LOGIN');
      return ecrire(l.join('\r\n'));
    }
    if (verbe === 'STARTTLS') {
      commandes.push('STARTTLS');
      if (mode !== 'starttls' || enTls) return ecrire('502 5.5.1 STARTTLS non disponible');
      ecrire('220 2.0.0 Prêt à démarrer TLS');
      const brut = flux;
      brut.removeAllListeners('data');
      const s = new tls.TLSSocket(brut, { isServer: true, key: KEY, cert: CERT });
      s.on('error', () => {});
      flux = s;
      enTls = true;
      tampon = '';
      brancher(s);
      return;
    }
    if (verbe === 'AUTH') {
      const p = ligne.split(/\s+/);
      const meca = (p[1] || '').toUpperCase();
      if (meca === 'PLAIN' && p[2]) {
        const [, u = '', pw = ''] = b64(p[2]).split('\u0000');
        return authentifier(u, pw, 'AUTH PLAIN');
      }
      if (meca === 'LOGIN') {
        commandes.push('AUTH LOGIN');
        etat = 'login-user';
        return ecrire('334 ' + Buffer.from('Username:').toString('base64'));
      }
      return ecrire('504 5.5.4 Mécanisme non pris en charge');
    }
    if (verbe === 'MAIL') {
      commandes.push('MAIL');
      const m = /<([^>]*)>/.exec(ligne);
      de = m ? m[1] : '';
      return ecrire('250 2.1.0 Expéditeur accepté');
    }
    if (verbe === 'RCPT') {
      commandes.push('RCPT');
      const m = /<([^>]*)>/.exec(ligne);
      const dest = m ? m[1] : '';
      if (refuses.includes(dest.toLowerCase())) return ecrire(`550 5.1.1 Destinataire refusé : ${dest}`);
      a.push(dest);
      return ecrire('250 2.1.5 Destinataire accepté');
    }
    if (verbe === 'DATA') {
      commandes.push('DATA');
      if (!a.length) return ecrire('503 5.5.1 Aucun destinataire');
      etat = 'data';
      donnees = '';
      return ecrire('354 Terminer par <CRLF>.<CRLF>');
    }
    if (verbe === 'RSET') { de = ''; a = []; return ecrire('250 2.0.0 OK'); }
    if (verbe === 'NOOP') return ecrire('250 2.0.0 OK');
    if (verbe === 'QUIT') { ecrire('221 2.0.0 Au revoir'); return flux.end(); }
    return ecrire('500 5.5.2 Commande inconnue');
  };

  function brancher(s) {
    s.on('data', (d) => {
      tampon += d.toString('utf8');
      let i;
      while ((i = tampon.indexOf('\r\n')) >= 0) {
        const ligne = tampon.slice(0, i);
        tampon = tampon.slice(i + 2);
        traiter(ligne);
      }
    });
    s.on('error', () => {});
  }

  brancher(flux);
  ecrire('220 puits-smtp prêt');
}

const serveur = mode === 'ssl'
  ? tls.createServer({ key: KEY, cert: CERT }, (s) => session(s, true))
  : net.createServer((s) => session(s, false));
serveur.on('tlsClientError', () => {});
serveur.listen(0, '127.0.0.1', () => process.stdout.write(`PRET ${serveur.address().port}\n`));
