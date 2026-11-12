'use strict';
/* Scénario D1 (décision de la Direction de Baguidi, 12/11/2026) : les SCANS (courriers, dossier patient) vivent dans un DOSSIER du poste MÈRE, jamais sur le relais.
   Un fileul dépose le fichier chez la mère et un AUTRE fileul le lit chez elle, par blocs scellés AES-256-GCM (clé de clinique) : l'empreinte SHA-256 est recalculée à l'arrivée
   et à chaque lecture, le nom de rangement est un nom normalisé strict, un fichier altéré sur disque n'est jamais servi, et le relais — qui voit pourtant passer les FICHES
   (métadonnées chiffrées) — ne détient aucun octet de fichier, aucun nom, aucune empreinte en clair.
   La mère et les fileuls sont ceux du banc (référence Node ou, avec SIGH_MERE / SIGH_FILEUL=dart, l'exécutable Dart). */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { dechiffrer } = require('./crypto');

const SENTINELLE = 'SENTINELLE-SCAN-CLAIR-Zébulon-7731';
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');

/* Un PDF à couche texte, d'environ 600 Ko (trois blocs de 192 Ko au moins), qui porte la sentinelle. */
function pdfDe(graine) {
  const alea = crypto.createHash('sha256').update('graine-' + graine).digest();
  const corps = Buffer.alloc(600 * 1024); for (let i = 0; i < corps.length; i++) corps[i] = alea[i % 32] ^ (i & 0xff);
  return Buffer.concat([Buffer.from(`%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\n2 0 obj\n<< /Length 80 >>\nstream\nBT /F1 12 Tf (${SENTINELLE}) Tj ET\nendstream\nendobj\n`, 'latin1'), corps, Buffer.from('\n%%EOF', 'latin1')]);
}

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async D1() {
    titre('SCANS-D1 · le fichier vit chez la mère, un fileul le dépose, un autre le lit (blocs scellés, empreinte vérifiée) ; le relais ne voit aucun clair');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    m.mere.opts.fichiers = path.join(m.dir, 'scans-mere');
    await m.mere.demarrer();
    const a = await m.fileul('A', { cleClinique: m.clePair });
    const b = await m.fileul('B', { cleClinique: m.clePair });
    const faux = await m.fileul('FAUX', { cleClinique: 'ab'.repeat(32) });
    const sansCle = await m.fileul('SANSCLE');
    const dossier = m.mere.opts.fichiers;
    const o = pdfDe(1), s = sha(o), nom = '2026-11-11_ARR_0042.pdf';

    /* 1. dépôt par le fileul A, rangé chez la mère sous son nom normalisé */
    const d = await a.post('/fichier/deposer', { b64: o.toString('base64'), sha: s, nom, famille: 'courrier', nomOrigine: 'Courrier ministère.pdf' });
    verifier('le dépôt par un fileul est accepté', d.status === 200, d.json);
    verifier('la mère le range dans SON dossier sous le nom normalisé, octets identiques', fs.existsSync(path.join(dossier, nom)) && sha(fs.readFileSync(path.join(dossier, nom))) === s);

    /* 2. la fiche (métadonnées seulement) voyage par la synchronisation ordinaire */
    const meta = { sha256: s, nomNormalise: nom, nom: 'Courrier ministère.pdf', taille: o.length, mime: 'application/pdf' };
    const e = await a.ecrire({ type: 'creer', collection: 'courriers', fiche: 'C-0042', champs: { reference: 'ARR-2026-0042', objet: 'Autorisation', scan: meta } });
    verifier('la fiche du courrier est acceptée avec ses métadonnées de scan', e.statut !== 'refusee', e);
    verifier('le fileul B reçoit la FICHE (empreinte, nom normalisé), jamais le fichier', await attendre(async () => { const l = await b.liste('courriers'); return l.length === 1 && l[0].data.scan.sha256 === s && l[0].data.scan.nomNormalise === nom; }, 15000));

    /* 3. B va chercher le fichier chez la mère : empreinte recalculée à l'arrivée */
    const l = await b.get(`/fichier/lire?sha=${s}`);
    verifier('B lit le fichier chez la mère', !!l.b64, l);
    const lu = Buffer.from(l.b64 || '', 'base64');
    verifier('octets identiques, empreinte recalculée identique', lu.equals(o) && sha(lu) === s && l.sha === s);
    verifier('un fichier que la mère ne détient pas : absent, nommé', (await appelLire(b, '0'.repeat(64))).status === 404);

    /* 4. refus nommés */
    const traversee = await a.post('/fichier/deposer', { b64: o.toString('base64'), sha: s, nom: '../evil.pdf', famille: 'courrier' });
    verifier('un nom non normalisé est refusé (aucune traversée de dossier)', traversee.status === 422 && traversee.json.code === 'NOM_NON_NORMALISE', traversee.json);
    const faussee = await a.post('/fichier/deposer', { b64: o.toString('base64'), sha: 'f'.repeat(64), nom: '2026-11-11_ARR_0043.pdf', famille: 'courrier' });
    verifier('une empreinte annoncée fausse est refusée, rien n\'est rangé', faussee.status === 422 && !fs.existsSync(path.join(dossier, '2026-11-11_ARR_0043.pdf')), faussee.json);
    const exe = Buffer.concat([Buffer.from('MZ pas un scan'), Buffer.alloc(300, 1)]);
    const refusFormat = await a.post('/fichier/deposer', { b64: exe.toString('base64'), sha: sha(exe), nom: '2026-11-11_ARR_0044.pdf', famille: 'courrier' });
    verifier('un format non admis est refusé, nommé', refusFormat.status === 422 && refusFormat.json.code === 'FORMAT_REFUSE', refusFormat.json);
    const autre = pdfDe(2);
    const pris = await a.post('/fichier/deposer', { b64: autre.toString('base64'), sha: sha(autre), nom, famille: 'courrier' });
    verifier('un nom déjà pris par un AUTRE contenu est refusé : rien ne s\'écrase', pris.status === 422 && pris.json.code === 'NOM_PRIS' && sha(fs.readFileSync(path.join(dossier, nom))) === s, pris.json);
    const mauvaiseCle = await faux.post('/fichier/deposer', { b64: o.toString('base64'), sha: s, nom: '2026-11-11_ARR_0045.pdf', famille: 'courrier' });
    verifier('un poste qui scelle avec une autre clé est refusé par la mère', mauvaiseCle.status === 422 && /enveloppe_alteree/.test(JSON.stringify(mauvaiseCle.json)), mauvaiseCle.json);
    const sans = await sansCle.post('/fichier/deposer', { b64: o.toString('base64'), sha: s, nom: '2026-11-11_ARR_0046.pdf', famille: 'courrier' });
    verifier('un poste sans la clé de clinique ne dépose rien (CLE_ABSENTE)', sans.status === 422 && sans.json.code === 'CLE_ABSENTE', sans.json);

    /* 5. un fichier altéré sur le disque de la mère n'est JAMAIS servi */
    fs.appendFileSync(path.join(dossier, nom), Buffer.from([1]));
    const alt = await appelLire(b, s);
    verifier('un fichier altéré sur disque est refusé en le nommant, jamais servi', alt.status === 422 && alt.json.code === 'FICHIER_ALTERE', alt.json);
    const ctrl = await m.mere.admin('GET', '/admin/fichiers/controle');
    verifier('le contrôle de la mère nomme le fichier altéré', ctrl.json.alteres && ctrl.json.alteres.includes(nom), ctrl.json);

    /* 6. sauvegarde puis restauration : les fichiers reviennent, les empreintes sont vérifiées */
    const copie = fs.readFileSync(path.join(dossier, nom)).subarray(0, o.length);
    fs.writeFileSync(path.join(dossier, nom), copie); // on remet le fichier en état pour sauvegarder
    const sauv = await m.mere.admin('POST', '/admin/sauvegarder');
    verifier('la sauvegarde de la mère emporte les scans', sauv.status === 200 && sauv.json.scans && sauv.json.scans.copies >= 1, sauv.json);
    const destination = path.join(m.dir, 'sauvegardes', 'scans');
    verifier('la copie sauvegardée porte l\'empreinte du fichier', sha(fs.readFileSync(path.join(destination, nom))) === s);
    fs.rmSync(path.join(dossier, nom));
    verifier('disque perdu : la lecture dit « absent », pas une erreur muette', (await appelLire(b, s)).status === 404);
    const rest = await m.mere.admin('POST', '/admin/fichiers/restaurer', { source: destination });
    verifier('la restauration rend le fichier et le dit complet', rest.json.restaures >= 1 && rest.json.complet === true, rest.json);
    const relu = await b.get(`/fichier/lire?sha=${s}`);
    verifier('après restauration, B relit le fichier à l\'identique', relu.sha === s && Buffer.from(relu.b64, 'base64').equals(o));
    fs.appendFileSync(path.join(destination, nom), Buffer.from([9]));
    fs.rmSync(path.join(dossier, nom));
    const refusee = await m.mere.admin('POST', '/admin/fichiers/restaurer', { source: destination });
    verifier('une sauvegarde corrompue est REFUSÉE (empreinte), le fichier n\'est pas copié', refusee.json.refuses && refusee.json.refuses.includes(nom) && !fs.existsSync(path.join(dossier, nom)), refusee.json);

    /* 7. LE RELAIS : aucun clair, aucun octet de fichier */
    const rep = await attendre(async () => { const e = (await m.mere.admin('GET', '/admin/etat')).json; return e.seq_max > 0 && e.rep_seq === e.seq_max; }, 20000);
    verifier('la mère a répliqué au relais TOUT son journal (les fiches), chiffré', !!rep);
    await dormir(500);
    const tout = (await m.relais.direct('GET', '/banc/tout')).json;
    const vu = JSON.stringify({ lignes: tout.lignes.map((x) => Object.assign({}, x, { ct: undefined, nonce: undefined })), codes: tout.codes, appareils: tout.appareils, meta: tout.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = tout.lignes.map((x) => Buffer.from(x.ct, 'base64'));
    const brutOctets = octets.map((b64) => b64.toString('latin1')).join('\n');
    verifier('le relais détient une enveloppe de journal (les fiches voyagent chiffrées)', tout.lignes.length >= 1, tout.lignes.length);
    /* Avec la clé de clinique (que le relais n'a pas) on retrouve la fiche : elle y est bien, mais seulement chiffrée, et sans le fichier. */
    const claires = tout.lignes.map((x) => { try { return dechiffrer(Buffer.from(m.clePair, 'hex'), x); } catch (er) { return null; } }).filter(Boolean);
    const ops = claires.flatMap((c) => c.ops || []);
    verifier('déchiffrée avec la clé de clinique, l\'enveloppe porte la FICHE du courrier (empreinte, nom normalisé) et aucun octet de fichier', ops.some((op) => op.collection === 'courriers' && op.champs && op.champs.scan && op.champs.scan.sha256 === s) && !JSON.stringify(claires).includes(SENTINELLE), ops.length);
    verifier('aucun mot du scan, aucune empreinte, aucun nom de fichier en clair au relais', !vu.includes(s) && !vu.includes(nom) && !vu.includes('ministère') && !vu.includes(SENTINELLE) && !brutOctets.includes(SENTINELLE) && !brutOctets.includes(nom) && !brutOctets.includes(s));
    verifier('aucune enveloppe n\'a la taille d\'un fichier : le relais ne reçoit aucun octet du scan', octets.every((b) => b.length < 64 * 1024), octets.map((b) => b.length).sort((x, y) => y - x).slice(0, 3));
    verifier('la clé de clinique n\'est nulle part au relais', !vu.includes(m.clePair) && !vu.includes(Buffer.from(m.clePair, 'hex').toString('base64')));
    await m.fermer();
  },
});

/* La lecture renvoie le statut ET le corps (le client du banc `get` ne rend que le corps). */
async function appelLire(f, sha256) {
  const r = await fetch(`${f.base}/fichier/lire?sha=${sha256}`);
  let json = {}; try { json = await r.json(); } catch (e) { /* vide */ }
  return { status: r.status, json };
}
