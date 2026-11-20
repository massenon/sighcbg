'use strict';
/* Scénario PLN1 (Direction de Baguidi, 17/11/2026, décision 12 : « planning, vacations, congés et présences voyagent entre postes, jamais vers le téléphone, avec les contrôles de la mère ») :
   le PLANNING traverse les postes. Les vacations (`planning`), leurs propositions, les congés, les ordres de mission et les présences sont des fiches de famille A (miroir de
   `sync_dart/lib/src/mere.dart`). `presences` était poussée par le pont mais ABSENTE de la table de la mère : refusée `collection_inconnue`.
   Ce que le banc éprouve ICI, avec de vrais processus, c'est le PROTOCOLE :
   · une vacation, une présence, un congé, une proposition écrits « à valider » par un fileul arrivent à la mère ET à l'autre fileul, sous des identifiants préfixés par poste (aucune collision) ;
   · la mère REFAIT le contrôle : une pièce ou une vacation ne naît pas validée, la validation ne s'écrit pas par un poste (elle se dépose, la mère l'applique), une validation ne se défait pas,
     une vacation VALIDÉE ne se réécrit ni ne s'archive par un poste, un pointage validé ne se modifie que par une régularisation tracée ;
   · la mère coupée puis relancée : rien n'est perdu, aucun doublon ; jamais une fiche du planning vers un téléphone (honoraires, motifs d'absence).
   Ce que le poste fait (dépôt, application sous le rôle de l'auteur avec sa matrice et son planning, double affectation entre deux postes) est éprouvé par `apps/poste/test/planning_sync_test.dart`. */
module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async PLN1() {
    titre('PLN-PLN1 · planning à travers les postes : pose « à valider », validation réservée à la mère, vacation validée figée, présences acceptées, mère coupée, rien vers un téléphone');
    const m = await monde({ relais: true });
    const f1 = await m.fileul('F1');
    const f2 = await m.fileul('F2');
    const compte = async (c) => (await m.mere.admin('GET', '/admin/compte?collection=' + c)).json.n;
    const refus = async (f, code) => (await f.etat()).a_traiter.some((x) => x.code === code);
    const admin = async (collection, fiche, champs) => (await m.mere.admin('POST', '/admin/referentiel', { collection, fiche, champs })).json;
    const chez = async (f, c, id) => { const l = (await f.liste(c)).find((x) => x.id === id); return l && l.data; };
    const chezMere = async (c, id) => { const r = (await m.mere.admin('GET', '/admin/fiche?collection=' + c + '&id=' + encodeURIComponent(id))).json; return r && !r.absente ? r.data : undefined; };

    /* 1. Une vacation n'est jamais créée validée par un poste ; « à valider », elle arrive partout, sous un identifiant propre au poste. */
    await f1.ecrire({ type: 'creer', collection: 'planning', fiche: 'F1-PLN00001', champs: { employeId: 'EA', date: '2031-03-14', type: 'garde', validationEtat: 'validee', statut: 'validee' } });
    verifier('une vacation créée « validée » par un poste est refusée en le nommant (validation_reservee)', await attendre(() => refus(f1, 'validation_reservee'), 15000) && (await compte('planning')) === 0);
    await f1.ecrire({ type: 'creer', collection: 'planning', fiche: 'F1-PLN00002', champs: { employeId: 'EA', date: '2031-03-14', type: 'garde', validationEtat: 'a_valider', statut: 'a_valider' } });
    verifier('la vacation « à valider » de F1 arrive à la mère ET chez F2 (identifiant préfixé par poste)',
      await attendre(async () => (await compte('planning')) === 1 && !!(await chez(f2, 'planning', 'F1-PLN00002')), 20000), await compte('planning'));

    /* 2. La validation ne s'écrit pas par un poste : elle se dépose, la mère l'applique. */
    await dormir(1200);
    await f2.ecrire({ type: 'modifier', collection: 'planning', fiche: 'F1-PLN00002', champs: { validationEtat: 'validee', validePar: 'Moi-même' }, vu: {} });
    verifier('un fileul n\'écrit pas lui-même la validation : refus nommé, la vacation reste « à valider » à la mère', await attendre(() => refus(f2, 'validation_reservee') || refus(f2, 'champ_reserve'), 15000) && ((await chezMere('planning', 'F1-PLN00002')) || {}).validationEtat === 'a_valider');
    /* La mère applique le dépôt (ici : à sa console, comme le fait le poste mère sous le rôle de l'auteur). */
    await admin('planning', 'F1-PLN00002', { validationEtat: 'validee', statut: 'validee', validePar: 'Surveillant Sigma', valideLe: '2031-03-10' });
    verifier('la validation de la mère voyage : F1 et F2 lisent la vacation « validée »', await attendre(async () => ((await chez(f1, 'planning', 'F1-PLN00002')) || {}).validationEtat === 'validee' && ((await chez(f2, 'planning', 'F1-PLN00002')) || {}).validationEtat === 'validee', 20000));

    /* 3. Une vacation validée est figée pour un poste ; une validation ne se défait pas. */
    await dormir(1200);
    await f1.ecrire({ type: 'modifier', collection: 'planning', fiche: 'F1-PLN00002', champs: { date: '2031-03-15' }, vu: {} });
    verifier('une vacation VALIDÉE ne se réécrit pas par un poste : refus nommé (vacation_validee), date intacte à la mère', await attendre(() => refus(f1, 'vacation_validee'), 15000) && (await chezMere('planning', 'F1-PLN00002')).date === '2031-03-14');
    await f2.ecrire({ type: 'modifier', collection: 'planning', fiche: 'F1-PLN00002', champs: { validationEtat: 'a_valider' }, vu: {} });
    verifier('UNE VALIDATION NE SE DÉFAIT PAS : retour « à valider » refusé en le nommant', await attendre(() => refus(f2, 'validation_defaite'), 15000) && (await chezMere('planning', 'F1-PLN00002')).validationEtat === 'validee');
    await f2.ecrire({ type: 'modifier', collection: 'planning', fiche: 'F1-PLN00002', champs: { statut: 'archive' }, vu: {} });
    verifier('le retrait d\'une vacation validée se dépose : l\'archivage par un poste est refusé', await attendre(async () => (await refus(f2, 'vacation_validee')) && ((await chezMere('planning', 'F1-PLN00002')) || {}).statut !== 'archive', 15000));

    /* 4. Les présences : acceptées par la mère (refusées `collection_inconnue` avant ce lot), jamais créées validées ; le pointage validé se régularise. */
    await f1.ecrire({ type: 'creer', collection: 'presences', fiche: 'F1-PRS00001', champs: { employeId: 'EA', date: '2031-03-14', etat: 'present', validationEtat: 'a_valider', etapesFaites: [] } });
    verifier('un pointage de F1 arrive à la mère ET chez F2 (la collection est connue de la mère)', await attendre(async () => (await compte('presences')) === 1 && !!(await chez(f2, 'presences', 'F1-PRS00001')), 20000), await compte('presences'));
    verifier('aucun refus `collection_inconnue` côté fileul', !(await refus(f1, 'collection_inconnue')));
    await f2.ecrire({ type: 'creer', collection: 'presences', fiche: 'F2-PRS00001', champs: { employeId: 'EB', date: '2031-03-14', etat: 'present', validationEtat: 'valide', validePar: 'Moi' } });
    verifier('un pointage créé « validé » par un poste est refusé en le nommant', await attendre(() => refus(f2, 'validation_reservee'), 15000) && (await compte('presences')) === 1);
    await admin('presences', 'F1-PRS00001', { validationEtat: 'valide', validePar: 'Surveillant Sigma', valideLe: '2031-03-14' });
    await attendre(async () => ((await chez(f1, 'presences', 'F1-PRS00001')) || {}).validationEtat === 'valide', 20000);
    await dormir(1200);
    await f1.ecrire({ type: 'modifier', collection: 'presences', fiche: 'F1-PRS00001', champs: { etat: 'absent' }, vu: {} });
    verifier('un pointage validé ne se modifie pas directement : refus nommé (presence_validee)', await attendre(() => refus(f1, 'presence_validee'), 15000) && (await chezMere('presences', 'F1-PRS00001')).etat === 'present');

    /* 5. Congés, ordres de mission, propositions : jamais créés tranchés par un poste ; « à valider », ils voyagent. */
    await f1.ecrire({ type: 'creer', collection: 'conges', fiche: 'F1-CG00001', champs: { employeId: 'EA', statutConge: 'valide' } });
    await f1.ecrire({ type: 'creer', collection: 'missions', fiche: 'F1-OM00001', champs: { agentId: 'EA', statutMission: 'validee' } });
    await f1.ecrire({ type: 'creer', collection: 'propositionsPlanning', fiche: 'F1-PPL00001', champs: { employeId: 'EA', type: 'ajout', etat: 'validee' } });
    verifier('un congé, un ordre de mission, une proposition créés « tranchés » par un poste sont refusés', await attendre(async () => (await compte('conges')) === 0 && (await compte('missions')) === 0 && (await compte('propositionsPlanning')) === 0 && (await refus(f1, 'validation_reservee')), 15000));
    await f1.ecrire({ type: 'creer', collection: 'conges', fiche: 'F1-CG00002', champs: { employeId: 'EA', statutConge: 'en_attente', validationEtat: 'a_valider' } });
    await f1.ecrire({ type: 'creer', collection: 'missions', fiche: 'F1-OM00002', champs: { agentId: 'EA', statutMission: 'a_valider', validationEtat: 'a_valider' } });
    await f1.ecrire({ type: 'creer', collection: 'propositionsPlanning', fiche: 'F1-PPL00002', champs: { employeId: 'EA', type: 'ajout', etat: 'proposee' } });
    verifier('« à valider », le congé, l\'ordre de mission et la proposition arrivent à la mère ET chez F2',
      await attendre(async () => !!(await chez(f2, 'conges', 'F1-CG00002')) && !!(await chez(f2, 'missions', 'F1-OM00002')) && !!(await chez(f2, 'propositionsPlanning', 'F1-PPL00002')), 20000));
    await dormir(1200);
    await f2.ecrire({ type: 'modifier', collection: 'propositionsPlanning', fiche: 'F1-PPL00002', champs: { etat: 'validee', tranchePar: 'Moi' }, vu: {} });
    verifier('la décision d\'une proposition ne s\'écrit pas par un poste', await attendre(async () => (await refus(f2, 'validation_reservee')) || (await refus(f2, 'champ_reserve')), 15000) && ((await chezMere('propositionsPlanning', 'F1-PPL00002')) || {}).etat === 'proposee');

    /* 6. Mère coupée puis relancée : la vacation posée pendant la coupure arrive, sans doublon. */
    await m.mere.tuer();
    await f2.ecrire({ type: 'creer', collection: 'planning', fiche: 'F2-PLN00001', champs: { employeId: 'EB', date: '2031-03-20', type: 'permanence', validationEtat: 'a_valider', statut: 'a_valider' } });
    await m.mere.demarrer();
    verifier('mère relancée : la vacation posée pendant la coupure arrive à la mère et chez F1, une seule fois', await attendre(async () => (await compte('planning')) === 2 && !!(await chez(f1, 'planning', 'F2-PLN00001')), 25000), await compte('planning'));
    await dormir(2500);
    verifier('aucun doublon après rejeu', (await compte('planning')) === 2 && (await compte('presences')) === 1, { planning: await compte('planning'), presences: await compte('presences') });

    /* 7. Rien vers un téléphone. */
    const mob = await m.mobile('T1', { profil: 'soignant', fonction: 'infirmier' });
    await dormir(1500);
    const vus = {};
    for (const c of ['planning', 'propositionsPlanning', 'conges', 'missions', 'presences']) vus[c] = (await mob.liste(c)).length;
    verifier('un téléphone ne reçoit aucune fiche du planning, des congés, des missions ni des présences', Object.values(vus).every((n) => n === 0), vus);
    await m.fermer();
  },
});
