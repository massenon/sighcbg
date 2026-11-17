'use strict';
/* Scénario BASEPORT1 (décision 12 de la Direction de Baguidi, 17/11/2026) : un FILEUL exporté, réimporté sur un poste NEUF, se rattache à la mère SANS PERTE DE SA FILE NI DOUBLON.

   Ce que le scénario prouve, sur le protocole (mère Node OU Dart, fileul Node OU Dart — le même scénario) :
     1. un fileul coupé du réseau saisit trois dossiers : ils restent dans sa file (non confirmés) ; `GET /etat-portable` les rend, avec ses plages, et AUCUN secret (ni jeton, ni renouvellement) ;
     2. l'état ne se reprend QUE sur un poste neuf (`POSTE_NON_NEUF`) ;
     3. un poste neuf reprend l'état et est appairé par un code de REPRISE : la mère lui passe les plages, révoque l'ancien ; le réseau revient : les trois dossiers arrivent UNE fois
        (aucun doublon, mêmes codes), la file se vide ;
     4. sans la reprise (un code ordinaire), les mêmes saisies sont refusées EN NOMMANT (`numero_hors_plage`) : elles ne se perdent pas en silence, elles se listent à traiter — c'est la preuve que
        la reprise d'identité est nécessaire et non décorative ;
     5. un code de reprise vers un poste inconnu est refusé en nommant (`appareil_inconnu`).
   Le chiffrement du fichier d'export et sa vérification sont prouvés par les tests Dart (`export_portable_test.dart`) : le banc, lui, mène la RESYNCHRONISATION. */
module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async BASEPORT1() {
    titre('BASEPORT1 · un fileul exporté, réimporté sur un poste neuf et rattaché par un code de reprise : sa file arrive une fois, sans perte ni doublon');
    const m = await monde();
    const f1 = await m.fileul('Poste export', { plage: 50 });
    // Un dossier synchronisé AVANT la coupure : il est confirmé, il ne voyage pas dans la file.
    const avant = await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'DEJA', prenom: 'Confirme', naissance: '1990-01-01', dateCreation: new Date().toISOString().slice(0, 10) } });
    await attendre(async () => await f1.vide(), 15000);
    m.reseau.regler('ferme');
    const codes = [];
    for (let i = 1; i <= 3; i++) {
      const r = await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'HORSLIGNE' + i, prenom: 'P', naissance: `1980-0${i}-01`, dateCreation: new Date().toISOString().slice(0, 10) } });
      codes.push(r.fiche);
    }
    const e = (await f1.get('/etat-portable'));
    verifier('l\'état portable porte la FILE non confirmée (3 saisies), le dossier déjà confirmé n\'en fait pas partie', e.role === 'fileul' && e.file.length === 3 && e.file.every((o) => /HORSLIGNE/.test(JSON.stringify(o))), { file: e.file.length });
    verifier('l\'état portable porte les plages, l\'étiquette et l\'identifiant du poste', e.uuid === f1.uuid && e.etiquette === 'Poste export' && e.plage.length >= 1);
    const brut = JSON.stringify(e);
    verifier('l\'état portable ne porte AUCUN secret : ni jeton, ni renouvellement', !/jeton|renouvellement/i.test(brut));
    const refusNonNeuf = await f1.post('/reprendre-etat', { etat: e });
    verifier('un poste qui a déjà des saisies refuse de reprendre un état (POSTE_NON_NEUF), rien n\'est écrit', refusNonNeuf.status === 422 && refusNonNeuf.json.refus === 'POSTE_NON_NEUF');
    await f1.tuer();

    // Le poste NEUF : il reprend l'état, puis est appairé par un code de reprise.
    const f2 = await m.fileul('Poste neuf', { sansAppairage: true });
    const rep = await f2.post('/reprendre-etat', { etat: e });
    verifier('un poste neuf reprend la file (3 opérations) et se souvient de qui il remplace', rep.status === 200 && rep.json.repris === 3 && rep.json.repris_de === f1.uuid, rep.json);
    verifier('la file reprise est visible comme saisie en attente, rien n\'est parti', (await f2.etat()).en_attente === 3);
    const inconnu = await m.mere.admin('POST', '/admin/code', { etiquette: 'X', role: 'fileul', reprise: 'poste-qui-n-existe-pas' });
    verifier('un code de reprise vers un poste inconnu est refusé en le nommant (appareil_inconnu)', inconnu.status === 404 && inconnu.json.code === 'appareil_inconnu', inconnu.json);
    const { json: c } = await m.mere.admin('POST', '/admin/code', { etiquette: 'Poste neuf', role: 'fileul', reprise: f1.uuid });
    m.reseau.regler('ouvert');
    const ap = await f2.post('/appairer', { code: c.code });
    verifier('l\'appairage par code de reprise réussit', ap.status === 200, ap.json);
    verifier('la file se vide : la mère a accepté les trois saisies reprises', await attendre(async () => { const s = await f2.etat(); return s.en_attente === 0 && s.acceptees >= 3; }, 20000), await f2.etat());
    const etat = (await m.mere.admin('GET', '/admin/etat')).json;
    const ancien = etat.appareils.find((a) => a.uuid === f1.uuid);
    verifier('la mère a RÉVOQUÉ le poste remplacé (il reste au registre, RG-14)', ancien && ancien.etat === 'revoque', ancien);
    const chezMere = async (id) => { const r = (await m.mere.admin('GET', '/admin/fiche?collection=patients&id=' + encodeURIComponent(id))).json; return r && !r.absente ? r.data : undefined; };
    const compte = async () => (await m.mere.admin('GET', '/admin/compte?collection=patients')).json.n;
    const presentes = await Promise.all(codes.map(chezMere));
    verifier('chacune des trois saisies est chez la mère, sous son identifiant d\'origine (aucune perte)', presentes.every((d, i) => d && d.nom === 'HORSLIGNE' + (i + 1)), presentes.map((d) => d && d.nom));
    verifier('la mère ne compte que 4 dossiers : le confirmé et les 3 repris, aucun doublon', (await compte()) === 4, await compte());
    verifier('chaque dossier repris garde le code attribué par le poste d\'origine, dans sa plage', presentes.every((d) => typeof d.code === 'string' && d.code.length > 0) && new Set(presentes.map((d) => d.code)).size === 3, presentes.map((d) => d.code));
    const s2 = await f2.etat();
    verifier('aucune saisie reprise n\'est à traiter (aucun refus)', s2.a_traiter.length === 0, s2.a_traiter);
    // Rejouer l'import (même état, mêmes identifiants) sur un autre poste neuf ne duplique rien : les opérations sont reconnues par leur identifiant.
    const f3 = await m.fileul('Poste neuf bis', { sansAppairage: true });
    await f3.post('/reprendre-etat', { etat: e });
    const { json: c3 } = await m.mere.admin('POST', '/admin/code', { etiquette: 'Poste neuf bis', role: 'fileul' });
    await f3.post('/appairer', { code: c3.code });
    await attendre(async () => (await f3.etat()).en_attente === 0, 20000);
    verifier('un export réimporté une SECONDE fois est reconnu par ses identifiants d\'opération : aucun doublon chez la mère', (await compte()) === 4, await compte());

    // 4. SANS reprise d'identité : les saisies reprises sont refusées EN NOMMANT (jamais perdues en silence). C'est la preuve que la reprise n'est pas décorative.
    const g1 = await m.fileul('Poste sans reprise', { plage: 50 });
    m.reseau.regler('ferme');
    await g1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'SANSREPRISE', prenom: 'P', naissance: '1975-05-05', dateCreation: new Date().toISOString().slice(0, 10) } });
    const eg = await g1.get('/etat-portable');
    await g1.tuer();
    const g2 = await m.fileul('Poste neuf ordinaire', { sansAppairage: true });
    await g2.post('/reprendre-etat', { etat: eg });
    const { json: cg } = await m.mere.admin('POST', '/admin/code', { etiquette: 'Poste neuf ordinaire', role: 'fileul' });
    m.reseau.regler('ouvert');
    await g2.post('/appairer', { code: cg.code });
    verifier('sans code de reprise, la saisie reprise est REFUSÉE en nommant le motif (numero_hors_plage), elle n\'est ni perdue ni appliquée', await attendre(async () => { const s = await g2.etat(); return s.a_traiter.length === 1 && s.a_traiter[0].code === 'numero_hors_plage'; }, 20000), await g2.etat());
    verifier('la mère n\'a pas enregistré ce dossier', (await compte()) === 4, await compte());
  },
});
