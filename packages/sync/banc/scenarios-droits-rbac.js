'use strict';
/* Scénario RB1 (Direction de Baguidi, 10/11/2026) : LES DROITS NE SONT JAMAIS FIGÉS. Une mère et deux fileuls en vrais processus :
   - la fiche de droits d'un rôle (collection `rbac`) voyage de la mère à TOUS les fileuls, sans que l'un d'eux redémarre ; un fileul coupé la reçoit à son retour ;
   - un fileul ne peut pas l'écrire (famille R : refus nommé) ; il dépose une DÉCISION (`decisionsDroits`, famille A) que la mère reçoit et que l'autre fileul voit ;
   - deux décisions concurrentes sur le même rôle arrivent TOUTES LES DEUX, avec leur horodatage de décision : aucune ne se perd en route (ce que la mère en fait —
     la plus récente l'emporte, l'ancienne est écartée et nommée — est la règle du domaine, rejouée en Dart : packages/domaine/test/decisions_droits_test.dart et
     apps/poste/test/droits_decisions_test.dart) ;
   - l'issue marquée par la mère sur la décision revient au fileul qui l'avait déposée.
   Ce banc prouve le TRANSPORT ; il ne prouve ni le jugement des décisions (poste), ni l'application à chaud dans l'interface (tests de widget du poste). */
module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async RB1() {
    titre('RBAC-RB1 · une fiche de droits voyage de la mère à deux fileuls sans redémarrage ; un fileul ne l\'écrit pas, il dépose une décision ; les décisions concurrentes arrivent toutes');
    const m = await monde({});
    const f1 = await m.fileul('F1');
    const f2 = await m.fileul('F2');
    const poser = (fiche, champs) => m.mere.admin('POST', '/admin/referentiel', { collection: 'rbac', fiche, champs }).then((r) => r.json);
    const fiche = (version, droitM9) => ({ role: 'sage_femme', statut: 'actif', version, droits: { M4: { voir: true, editer: true, annuler: true }, M9: droitM9 }, decideLe: `2026-11-10T0${version}:00:00.000Z` });
    const droitsDe = async (poste) => (await poste.liste('rbac')).filter((x) => x.id === 'RBAC26').map((x) => x.data)[0];
    const v = async (poste) => ((await droitsDe(poste)) || {}).version;
    const pid1 = f1.proc.pid, pid2 = f2.proc.pid;

    /* 1. la mère pose la fiche : les DEUX fileuls la reçoivent, sans redémarrer */
    const r1 = await poser('RBAC26', fiche(1, { voir: false, editer: false, annuler: false }));
    verifier('la mère accepte la fiche de droits (famille R) avec un seq', r1.statut === 'acceptee' && r1.seq > 0, r1);
    verifier('les deux fileuls reçoivent la fiche', await attendre(async () => (await v(f1)) === 1 && (await v(f2)) === 1, 15000), [await v(f1), await v(f2)]);

    /* 2. un droit modifié par la mère se propage à tous, À TOUT MOMENT : aucun processus n'est relancé */
    const cyclesAvant = (await f1.etat()).cycles;
    await poser('RBAC26', fiche(2, { voir: true, editer: false, annuler: false }));
    verifier('la version 2 (M9 ouvert en lecture) arrive aux deux fileuls', await attendre(async () => (await v(f1)) === 2 && (await v(f2)) === 2, 15000), [await v(f1), await v(f2)]);
    verifier('le contenu arrivé est le droit décidé, champ pour champ', ((await droitsDe(f2)).droits.M9.voir === true) && ((await droitsDe(f2)).droits.M9.editer === false));
    verifier('aucun fileul n\'a redémarré : même processus, ses cycles ont continué', f1.proc.pid === pid1 && f2.proc.pid === pid2 && (await f1.etat()).cycles > cyclesAvant);

    /* 3. un fileul n'écrit pas la fiche de droits : refus nommé, la fiche ne bouge pas */
    await f1.ecrire({ type: 'modifier', collection: 'rbac', fiche: 'RBAC26', champs: { droits: { M9: { voir: true, editer: true, annuler: true } } } });
    verifier('la mère REFUSE l\'écriture d\'un fileul sur la fiche de droits (droit_refuse, nommé)', await attendre(async () => (await f1.etat()).a_traiter.some((x) => x.code === 'droit_refuse'), 15000));
    verifier('la fiche n\'a pas bougé ni à la mère ni sur l\'autre fileul', (await v(f2)) === 2 && ((await droitsDe(f2)).droits.M9.editer === false));

    /* 4. il dépose une DÉCISION : la mère la reçoit, l'autre fileul la voit */
    const dec = (ident, decideLe, motif, valeur) => ({ ident, role: 'sage_femme', genre: 'modification', changements: { 'droits.M9': valeur }, motif, auteur: ident, auteurRole: 'admin', decideLe, statutDemande: 'en_attente' });
    await f1.ecrire({ type: 'creer', collection: 'decisionsDroits', fiche: 'F1-D1', champs: dec('F1-D1', '2026-11-10T10:00:00.000Z', 'Besoin de la maternité', { voir: true, editer: true, annuler: false }) });
    verifier('la décision d\'un fileul arrive à la mère (famille A : acceptée)', await attendre(async () => (await m.mere.admin('GET', '/admin/compte?collection=decisionsDroits')).json.n === 1, 15000));
    verifier('l\'autre fileul la voit aussi (le journal des décisions est partagé)', await attendre(async () => (await f2.liste('decisionsDroits')).length === 1, 15000));

    /* 5. DEUX DÉCISIONS CONCURRENTES sur le même rôle : F2 à 12 h, F1 à 10 h — arrivées dans cet ordre. Aucune ne se perd, chacune porte son horodatage de décision. */
    await f2.ecrire({ type: 'creer', collection: 'decisionsDroits', fiche: 'F2-D2', champs: dec('F2-D2', '2026-11-10T12:00:00.000Z', 'Lecture seule', { voir: true, editer: false, annuler: false }) });
    await dormir(150);
    await f1.ecrire({ type: 'creer', collection: 'decisionsDroits', fiche: 'F1-D3', champs: dec('F1-D3', '2026-11-10T09:30:00.000Z', 'Fermeture', { voir: false, editer: false, annuler: false }) });
    verifier('la mère détient les trois décisions : aucune ne s\'est perdue', await attendre(async () => (await m.mere.admin('GET', '/admin/compte?collection=decisionsDroits')).json.n === 3, 15000));
    const surF2 = await attendre(async () => (await f2.liste('decisionsDroits')).length === 3, 15000);
    verifier('l\'autre fileul les voit toutes les trois, avec l\'horodatage de décision de chacune', surF2
      && (await f2.liste('decisionsDroits')).map((x) => x.data.decideLe).sort().join() === ['2026-11-10T09:30:00.000Z', '2026-11-10T10:00:00.000Z', '2026-11-10T12:00:00.000Z'].join());

    /* 6. la mère juge (poste) puis applique la plus récente ; l'issue est marquée sur la décision et revient au fileul qui l'avait déposée */
    await poser('RBAC26', { ...fiche(3, { voir: true, editer: false, annuler: false }), decideLe: '2026-11-10T12:00:00.000Z', decisionId: 'F2-D2' });
    await m.mere.admin('POST', '/admin/referentiel', { collection: 'decisionsDroits', fiche: 'F1-D3', champs: { statutDemande: 'ecartee', traiteLe: '2026-11-10T12:00:01.000Z' } });
    verifier('l\'issue marquée par la mère revient au fileul qui avait déposé la décision', await attendre(async () => {
      const d = (await f1.liste('decisionsDroits')).find((x) => x.id === 'F1-D3');
      return d && d.data.statutDemande === 'ecartee';
    }, 15000));
    verifier('la décision écartée garde son contenu (rien n\'est écrasé) : motif et valeur proposée sont intacts', await (async () => {
      const d = (await f1.liste('decisionsDroits')).find((x) => x.id === 'F1-D3');
      return d.data.motif === 'Fermeture' && d.data.changements['droits.M9'].voir === false;
    })());

    /* 7. un fileul COUPÉ reçoit les droits à son retour : pas de réinstallation, pas de procédure */
    await f2.tuer();
    await poser('RBAC26', fiche(4, { voir: true, editer: true, annuler: false }));
    verifier('pendant la coupure, l\'autre fileul reçoit la version 4', await attendre(async () => (await v(f1)) === 4, 15000));
    await f2.demarrer();
    verifier('le fileul coupé la reçoit à son retour, sur sa base d\'avant', await attendre(async () => (await v(f2)) === 4, 20000), await v(f2));
    await m.fermer();
  },

  /* Scénario RB2 (Direction de Baguidi, 10/11/2026) : « L'APPLICATION MOBILE ÉVALUE LA MATRICE DES DROITS ». Ce que la mère décide arrive au téléphone par le relais chiffré :
     - un téléphone appairé AVANT toute fiche de droits reçoit l'instantané (vide), puis chaque modification, SANS redémarrer ;
     - un téléphone appairé APRÈS la fiche la reçoit à sa bienvenue ;
     - un téléphone coupé la reçoit à son retour, sur sa base d'avant ;
     - le téléphone ne peut PAS l'écrire (famille R : refus nommé, rien n'est mis en file) ;
     - la FONCTION reste celle du code d'appairage : une fiche de droits qui prétend en porter une ne la change pas.
     Ce banc prouve le TRANSPORT et la garde d'écriture du téléphone ; l'évaluation (le moteur du poste rejoué) et l'effet à l'écran sont prouvés par les tests du domaine et de
     l'application mobile (packages/domaine/test/mob_droits_test.dart, apps/mobile/test/droits_mobile_test.dart). */
  async RB2() {
    titre('RBAC-RB2 · la fiche de droits voyage de la mère à un mobile par le relais, sans redémarrage ; le mobile ne l\'écrit pas ; sa fonction reste celle du code d\'appairage');
    const m = await monde({ relais: true });
    const poser = (fiche, champs) => m.mere.admin('POST', '/admin/referentiel', { collection: 'rbac', fiche, champs }).then((r) => r.json);
    const fiche = (version, voir) => ({ role: 'sage_femme', statut: 'actif', version, droitsEcrans: { 'm4-cpn': { voir, editer: voir, annuler: false } }, decideLe: `2026-11-10T0${version}:00:00.000Z` });
    const droitsDe = async (tel) => ((await tel.liste('rbac')).find((x) => x.id === 'RBAC26') || {}).data;
    const v = async (tel) => ((await droitsDe(tel)) || {}).version;

    /* 1. un téléphone appairé AVANT toute fiche : la mère lui livre l'instantané (vide), il est « synchronisé » sans rien avoir à appliquer */
    const sf = await m.mobile('SF', { profil: 'soignant', fonction: 'sage_femme' });
    verifier('un mobile appairé sans fiche de droits reçoit tout de même l\'instantané : sa date de mise à jour est posée', await attendre(async () => (await sf.etat()).droits_maj_le > 0, 15000), (await sf.etat()).droits_maj_le);
    verifier('mais il n\'a reçu aucune fiche (la graine d\'origine reste en force)', (await sf.liste('rbac')).length === 0);
    const miseAJour0 = (await sf.etat()).droits_maj_le;
    const pid = sf.proc.pid;

    /* 2. la mère pose la fiche : le mobile la reçoit, sans redémarrer */
    const r1 = await poser('RBAC26', fiche(1, true));
    verifier('la mère accepte la fiche de droits', r1.statut === 'acceptee', r1);
    verifier('le mobile reçoit la version 1', await attendre(async () => (await v(sf)) === 1, 15000), await v(sf));
    verifier('sa date de mise à jour avance', (await sf.etat()).droits_maj_le >= miseAJour0);
    await poser('RBAC26', fiche(2, false));
    verifier('la version 2 (CPN fermée à la sage-femme) arrive à chaud : même processus', await attendre(async () => (await v(sf)) === 2, 15000) && sf.proc.pid === pid);
    verifier('le contenu arrivé est le droit décidé, champ pour champ', (await droitsDe(sf)).droitsEcrans['m4-cpn'].voir === false);
    verifier('la fiche de droits est du CONFIG, hors lot : elle n\'entre pas dans la portée de la tournée', (await sf.etat()).lot_expire === 0);

    /* 3. le mobile n'écrit pas la configuration : refus nommé en local, rien n'est mis en file, la mère ne reçoit rien */
    const enAttenteAvant = (await sf.etat()).en_attente;
    const ecr = await sf.post('/ecrire', { type: 'modifier', collection: 'rbac', fiche: 'RBAC26', champs: { droitsEcrans: { 'm4-cpn': { voir: true, editer: true, annuler: true } } } });
    verifier('le mobile REFUSE d\'écrire `rbac` : 403, code nommé, geste indiqué', ecr.status === 403 && ecr.json.code === 'regle_sur_la_mere' && /administrateur/.test(ecr.json.geste), ecr.json);
    const ecrM = await sf.post('/ecrire', { type: 'creer', collection: 'modulesActifs', fiche: 'MODX', champs: { module: 'M4', actif: false } });
    verifier('de même pour les activités fermées', ecr.status === 403 && ecrM.status === 403 && ecrM.json.code === 'regle_sur_la_mere', ecrM.json);
    await dormir(600);
    verifier('rien n\'a été mis en file, et la fiche de la mère n\'a pas bougé', (await sf.etat()).en_attente === enAttenteAvant && (await droitsDe(sf)).droitsEcrans['m4-cpn'].voir === false);

    /* 4. la FONCTION ne vient pas du téléphone, ni d'une fiche de droits : elle reste celle du code (R27 reste vrai) */
    await poser('RBAC26', { ...fiche(3, true), fonction: 'medecin', profil: 'reception' });
    verifier('une fiche qui prétend porter une fonction ne change pas celle du téléphone', await attendre(async () => (await v(sf)) === 3, 15000) && (await sf.etat()).fonction === 'sage_femme' && (await sf.etat()).profil === 'soignant', await sf.etat());

    /* 5. un téléphone coupé reçoit la décision à son retour, sur sa base d'avant */
    await sf.tuer();
    await poser('RBAC26', fiche(4, false));
    await sf.demarrer();
    verifier('le mobile redémarré reçoit la version 4', await attendre(async () => (await v(sf)) === 4, 20000), await v(sf));

    /* 6. un second téléphone, appairé APRÈS la fiche, la reçoit avec sa bienvenue */
    const inf = await m.mobile('INF', { profil: 'soignant', fonction: 'infirmier' });
    verifier('un mobile appairé après la fiche la reçoit (instantané)', await attendre(async () => (await v(inf)) === 4, 15000), await v(inf));
    verifier('et sa fonction est celle de SON code', (await inf.etat()).fonction === 'infirmier');
    await m.fermer();
  },
});
