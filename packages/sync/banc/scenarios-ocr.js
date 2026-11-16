'use strict';
/* Scénario OCR1 (lots OCR-prep et OCR-C) : le TEXTE LU d'un scan est une MÉTADONNÉE du fichier (collection `lecturesOcr`, une fiche par version, identifiant déterministe) ; la CORRECTION
   SIGNÉE d'une personne est une version de plus, au même titre. Elles voyagent par le journal comme toute fiche de la famille B (ajout seul) : JAMAIS en clair par le relais, JAMAIS vers un téléphone.
   Le RÉGLAGE de la lecture (`reglagesOcr`, fiche `ocr`) se décide à la mère (famille R : elle seule écrit) et descend aux fileuls, qui ne le modifient pas. La FILE (`fileOcr`) est locale au poste.

   Ce que ce banc éprouve : le PROTOCOLE, avec la mère de référence (Node) ou la mère Dart, et des fileuls de référence ou Dart. La logique du poste (états, file, reprise, droit, correction visible
   ou absente) est éprouvée par `apps/poste/test/ocr_*_test.dart`, et le code de la mère Dart contre de vrais fileuls par `apps/poste/test/ocr_direct_sync_test.dart`. Ici :

     1. une lecture écrite par F1 arrive chez F2 par le journal, avec son texte et sa provenance ;
     2. la MÊME lecture (même identifiant) écrite par F2 : acceptée sans effet, UNE fiche à la mère, aucun refus à « traiter » ;
     3. une autre version du même fichier (autre moteur) s'AJOUTE : deux fiches, l'ancienne inchangée ;
     4. une CORRECTION signée écrite par F2 arrive chez F1 : version de plus, le texte machine reste intact à la mère et chez F1 ;
     5. une lecture ou une correction ne se MODIFIE jamais : refusée par la mère (journal_immuable) ;
     6. la file `fileOcr` ne voyage pas : collection inconnue de la mère ;
     7. le RÉGLAGE écrit à la mère arrive chez les deux fileuls ; un fileul qui tente de l'écrire (modifier ou créer) est refusé (droit_refuse), la valeur reste ;
     8. JAMAIS vers un téléphone : il ne dépose ni ne reçoit une lecture, une correction, ni le réglage ;
     9. le relais ne voit RIEN du texte lu ni corrigé : aucun mot en clair, enveloppes d'entropie de chiffrement. */
const crypto = require('node:crypto');
const { dechiffrer } = require('./crypto');

const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const entropie = (b) => { const c = new Array(256).fill(0); for (const x of b) c[x]++; return -c.reduce((a, n) => (n ? a + (n / b.length) * Math.log2(n / b.length) : a), 0); };
const SECRET = 'Paludisme-Grave-Secret-OCR1';
const CORRIGE = 'Diagnostic-Corrige-Par-Une-Personne-OCR1';

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async OCR1() {
    titre('OCR-OCR1 · lectures et corrections signées en ajout seul (famille B), réglage descendant de la mère (famille R), file locale, jamais vers un téléphone, le relais ne voit rien');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1'); const f2 = await m.fileul('F2');
    const compte = (col) => m.mere.admin('GET', '/admin/compte?collection=' + col).then((r) => r.json.n);
    const empreinte = sha(Buffer.from('un scan sans couche texte, pour le banc OCR1'));
    const norme = 'paludisme grave secret ocr1';
    const idLecture = (moteur, version, texte) => 'OCR-' + empreinte.slice(0, 16) + '-' + sha(Buffer.from(moteur + '|' + version + '|fra|' + texte)).slice(0, 12);
    const lecture = (moteur, version, texteBrut, ocrLe) => ({ sha256: empreinte, texteBrut, texte: texteBrut.toLowerCase().replace(/-/g, ' '), nbMots: texteBrut.split(/[ -]/).length, texteSource: 'ocr', moteur, moteurVersion: version, langue: 'fra', ocrLe, ocrPar: 'Agent F', declencheur: 'automatique', pages: 1 });
    const id1 = idLecture('factice', '0.1', norme);
    /* la signature d'intégrité d'une correction : même définition que `ocrSignature` du domaine (OCRCOR1 | empreinte | version corrigée | auteur | date | motif | sha256 du texte) */
    const signer = (corrigeDe, texte, auteur, corrigeLe, motif) => sha(Buffer.from(['OCRCOR1', empreinte, corrigeDe, auteur, corrigeLe, motif, sha(Buffer.from(texte))].join('|')));
    const correction = (corrigeDe, texte, auteur, corrigeLe, motif) => ({ sha256: empreinte, texteBrut: texte, texte: texte.toLowerCase().replace(/-/g, ' '), nbMots: texte.split(/[ -]/).length, texteSource: 'humain', corrigeDe, corrigePar: auteur, corrigeLe, motif, signature: signer(corrigeDe, texte, auteur, corrigeLe, motif), langue: 'fra', ocrLe: corrigeLe, ocrPar: auteur });
    const refus = async (poste, code) => (await poste.etat()).a_traiter.some((x) => x.code === code);

    /* 1. LA LECTURE ARRIVE par le journal, avec son texte. */
    await f1.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: id1, champs: lecture('factice', '0.1', SECRET, '2026-11-14T10:00:00.000Z') });
    verifier('la lecture écrite par F1 arrive chez F2 par le journal, avec son texte et sa provenance (moteur, version, date)', await attendre(async () => (await f2.liste('lecturesOcr')).length === 1, 15000)
      && (await f2.liste('lecturesOcr'))[0].data.texteBrut === SECRET && (await f2.liste('lecturesOcr'))[0].data.moteur === 'factice' && (await f2.liste('lecturesOcr'))[0].data.ocrLe === '2026-11-14T10:00:00.000Z');

    /* 2. LA MÊME LECTURE écrite par l'autre poste : acceptée sans effet. */
    await f2.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: id1, champs: lecture('factice', '0.1', SECRET, '2026-11-14T10:00:05.000Z') });
    verifier('la même lecture (même identifiant) écrite par F2 est acceptée SANS EFFET : une fiche à la mère, aucun refus à « traiter », la première date fait foi',
      await attendre(async () => (await compte('lecturesOcr')) === 1 && (await f1.etat()).en_attente === 0 && (await f2.etat()).en_attente === 0, 15000)
      && !(await refus(f1, 'fiche_existe')) && !(await refus(f2, 'fiche_existe')) && (await f1.liste('lecturesOcr'))[0].data.ocrLe === '2026-11-14T10:00:00.000Z', [(await f1.etat()).a_traiter, (await f2.etat()).a_traiter]);

    /* 3. UNE AUTRE VERSION s'ajoute. */
    const id2 = idLecture('factice', '0.2', 'seconde lecture meilleure');
    await f2.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: id2, champs: lecture('factice', '0.2', 'Seconde-lecture-meilleure', '2026-11-14T11:00:00.000Z') });
    verifier('une autre version du même fichier (autre version du moteur) S\'AJOUTE : deux fiches partout, l\'ancienne inchangée', await attendre(async () => (await compte('lecturesOcr')) === 2 && (await f1.liste('lecturesOcr')).length === 2, 15000)
      && (await f1.liste('lecturesOcr')).find((x) => x.id === id1).data.texteBrut === SECRET && id1 !== id2);

    /* 4. LA CORRECTION SIGNÉE est une version de plus. */
    const idCor = 'COR-' + empreinte.slice(0, 16) + '-' + sha(Buffer.from(id1 + 'banc')).slice(0, 12);
    const cor = correction(id1, CORRIGE, 'Awa Agoro', '2026-11-14T12:00:00.000Z', 'accent et mot rétablis');
    await f2.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: idCor, champs: cor });
    verifier('la correction signée écrite par F2 arrive chez F1 avec son auteur, sa date, son motif et sa signature : une version de plus (trois à la mère), le texte machine reste INTACT partout',
      await attendre(async () => (await compte('lecturesOcr')) === 3 && (await f1.liste('lecturesOcr')).length === 3, 15000)
      && (await f1.liste('lecturesOcr')).find((x) => x.id === idCor).data.corrigePar === 'Awa Agoro' && (await f1.liste('lecturesOcr')).find((x) => x.id === idCor).data.signature === cor.signature
      && (await f1.liste('lecturesOcr')).find((x) => x.id === id1).data.texteBrut === SECRET && (await f2.liste('lecturesOcr')).find((x) => x.id === id1).data.texteBrut === SECRET);

    /* 5. UNE LECTURE, UNE CORRECTION NE SE MODIFIENT JAMAIS. */
    await f1.ecrire({ type: 'modifier', collection: 'lecturesOcr', fiche: id1, correctif: { texteBrut: 'réécrit' } });
    await f1.ecrire({ type: 'modifier', collection: 'lecturesOcr', fiche: idCor, correctif: { texteBrut: 'falsifié', corrigePar: 'Quelqu\'un d\'autre' } });
    await attendre(async () => (await f1.etat()).en_attente === 0, 15000);
    verifier('modifier une lecture OU une correction est REFUSÉ par la mère (journal_immuable) et les textes restent ceux des versions',
      (await refus(f1, 'journal_immuable')) && (await f2.liste('lecturesOcr')).find((x) => x.id === id1).data.texteBrut === SECRET && (await f2.liste('lecturesOcr')).find((x) => x.id === idCor).data.texteBrut === CORRIGE
      && (await f2.liste('lecturesOcr')).find((x) => x.id === idCor).data.corrigePar === 'Awa Agoro', (await f1.etat()).a_traiter);

    /* 6. LA FILE EST LOCALE : elle ne voyage pas (collection inconnue de la mère). */
    await f1.ecrire({ type: 'creer', collection: 'fileOcr', fiche: 'OCQ-' + empreinte.slice(0, 16), champs: { sha256: empreinte, etat: 'en_attente', famille: 'courrier' } });
    await dormir(2500);
    verifier('la file de lecture (`fileOcr`) est locale au poste : la mère la refuse (collection_inconnue) et F2 n\'en reçoit aucune fiche', (await refus(f1, 'collection_inconnue')) && (await f2.liste('fileOcr')).length === 0, (await f1.etat()).a_traiter);

    /* 7. LE RÉGLAGE se décide à la mère et descend ; un fileul ne l'écrit pas. */
    const reglage = { actif: true, moteur: 'factice', langue: 'fra', delaiMs: 90000, regleLe: '2026-11-14T08:00:00.000Z', reglePar: 'Administrateur', motif: 'mise en service' };
    const r1 = await m.mere.admin('POST', '/admin/referentiel', { collection: 'reglagesOcr', fiche: 'ocr', champs: reglage });
    verifier('la mère écrit le réglage (acceptée, avec un seq)', r1.json.statut === 'acceptee' && r1.json.seq > 0, r1.json);
    verifier('les DEUX fileuls reçoivent le réglage (moteur actif, délai, activation) par la synchronisation', await attendre(async () => (await f1.liste('reglagesOcr')).length === 1 && (await f2.liste('reglagesOcr')).length === 1, 15000)
      && (await f2.liste('reglagesOcr'))[0].data.moteur === 'factice' && (await f2.liste('reglagesOcr'))[0].data.delaiMs === 90000 && (await f1.liste('reglagesOcr'))[0].data.actif === true);
    await f1.ecrire({ type: 'modifier', collection: 'reglagesOcr', fiche: 'ocr', correctif: { actif: false, moteur: 'pirate', delaiMs: 1 } });
    await f2.ecrire({ type: 'creer', collection: 'reglagesOcr', fiche: 'ocr-f2', champs: { ...reglage, moteur: 'autre' } });
    verifier('un fileul qui tente de MODIFIER le réglage, ou d\'en créer un autre, est refusé par la mère (droit_refuse) : le réglage reste celui de la mère, chez les deux fileuls et à la mère',
      await attendre(async () => (await refus(f1, 'droit_refuse')) && (await refus(f2, 'droit_refuse')), 15000)
      && (await compte('reglagesOcr')) === 1 && (await f1.liste('reglagesOcr'))[0].data.moteur === 'factice' && (await f2.liste('reglagesOcr')).length === 1, [(await f1.etat()).a_traiter, (await f2.etat()).a_traiter]);
    const r2 = await m.mere.admin('POST', '/admin/referentiel', { collection: 'reglagesOcr', fiche: 'ocr', champs: { actif: false, motif: 'arrêt de la lecture' } });
    verifier('un nouveau réglage de la mère descend à son tour (désactivation reçue par les fileuls)', r2.json.statut === 'acceptee' && await attendre(async () => (await f1.liste('reglagesOcr'))[0].data.actif === false && (await f2.liste('reglagesOcr'))[0].data.actif === false, 15000));

    /* 8. JAMAIS VERS UN TÉLÉPHONE. */
    const mob = await m.mobile('M1', { profil: 'soignant' });
    await mob.ecrire({ type: 'creer', collection: 'lecturesOcr', fiche: 'OCR-FORGEE', champs: lecture('pirate', '9', 'texte forgé', '2026-11-14T13:00:00.000Z') });
    verifier('le téléphone qui tente de déposer une lecture est refusé, nommé (droit_refuse)', await attendre(async () => (await mob.etat()).a_traiter.some((x) => x.code === 'droit_refuse'), 15000));
    await dormir(2500);
    const versMobile = (await m.relais.direct('GET', '/banc/tout')).json.lignes.filter((l) => l.dir === 'vers_mobile' && l.appareil === mob.uuid);
    const collectionsMobile = versMobile.flatMap((l) => (dechiffrer(cleClinique, l).ops || []).map((o) => o.collection));
    verifier('le téléphone ne reçoit AUCUNE lecture, AUCUNE correction, AUCUN réglage : sa base n\'en porte pas et rien de tel ne figure dans ce que le relais lui a distribué',
      (await mob.liste('lecturesOcr')).length === 0 && (await mob.liste('reglagesOcr')).length === 0 && !collectionsMobile.includes('lecturesOcr') && !collectionsMobile.includes('reglagesOcr'), collectionsMobile);
    verifier('la lecture forgée du téléphone n\'est pas à la mère', (await compte('lecturesOcr')) === 3);

    /* 9. LE RELAIS NE VOIT RIEN du texte lu ni corrigé. */
    await attendre(async () => { const e = (await m.mere.admin('GET', '/admin/etat')).json; return e.rep_seq === e.seq_max; }, 15000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = brut.lignes.map((l) => Buffer.from(l.ct, 'base64'));
    const motif = new RegExp(SECRET + '|' + CORRIGE + '|paludisme|Awa Agoro|lecturesOcr|reglagesOcr|Seconde-lecture');
    verifier('le relais détient le journal chiffré de la mère (lectures, correction et réglage y sont) mais AUCUN mot du texte lu ou corrigé, ni auteur, ni nom de collection, en clair', brut.lignes.length >= 2
      && !motif.test(tout) && octets.every((o) => !motif.test(o.toString('latin1'))), brut.lignes.length);
    const gros = octets.filter((o) => o.length >= 250);
    verifier('chaque enveloppe a l\'entropie d\'un chiffrement (> 7 bits/octet), pas un simple encodage', gros.length >= 1 && gros.every((o) => entropie(o) > 7.0), octets.map((o) => [o.length, +entropie(o).toFixed(2)]));
    await m.fermer();
  },
});
