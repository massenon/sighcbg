'use strict';
/* Scénario PTA1 (lot PTA, Direction de Baguidi, 17/11/2026 : « Oui au lot PTA. RIEN NE DOIT ÊTRE EN DUR ») : le PLAN DE TRAVAIL ANNUEL traverse les postes. Les actions (`planAnnuel`),
   les en-têtes de plan (`plansTravail`) et les référentiels administrables (`ptaAxes`, `ptaEtats`, `ptaFinancements`) sont des fiches de famille A (miroir de `sync_dart/lib/src/mere.dart`).
   Ce que le banc éprouve ICI, avec de vrais processus, c'est le PROTOCOLE :
   · l'action et le plan écrits par un fileul arrivent à la mère ET à l'autre fileul ; un axe ajouté sur un poste se lit partout ;
   · la mère REFAIT le contrôle : un plan n'est jamais créé ni passé « adopté » par un poste (il se dépose, la mère l'applique), un champ d'adoption ne s'écrit pas par un poste, un plan adopté ne
     recule pas, le PROGRAMME d'une action d'un plan adopté ne se réécrit pas (le SUIVI, si) ;
   · la mère coupée puis relancée : rien n'est perdu ; jamais une fiche du plan (budgets prévus) vers un téléphone.
   Ce que le poste fait (dépôt de l'adoption, application sous le rôle de l'auteur, fusion qui ne régresse pas) est éprouvé par `apps/poste/test/pta_sync_test.dart` et
   `packages/domaine/test/pta_test.dart`. */
module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async PTA1() {
    titre('PTA-PTA1 · plan de travail annuel à travers les postes : adoption réservée à la mère, programme figé, suivi ouvert, mère coupée, rien vers un téléphone');
    const m = await monde({ relais: true });
    const f1 = await m.fileul('F1');
    const f2 = await m.fileul('F2');
    const compte = async (c) => (await m.mere.admin('GET', '/admin/compte?collection=' + c)).json.n;
    const refus = async (f, code) => (await f.etat()).a_traiter.some((x) => x.code === code);
    const admin = async (collection, fiche, champs) => (await m.mere.admin('POST', '/admin/referentiel', { collection, fiche, champs })).json;
    const chez = async (f, c, id) => { const l = (await f.liste(c)).find((x) => x.id === id); return l && l.data; };
    const chezMere = async (c, id) => { const r = (await m.mere.admin('GET', '/admin/fiche?collection=' + c + '&id=' + encodeURIComponent(id))).json; return r && !r.absente ? r.data : undefined; };

    /* 1. Le plan, une action et un axe écrits chez F1 arrivent partout. */
    const p = await f1.ecrire({ type: 'creer', collection: 'plansTravail', champs: { reference: 'PTA-2031-V1', exercice: 2031, version: 1, etat: 'brouillon', creePar: 'Rédacteur' } });
    const a = await f1.ecrire({ type: 'creer', collection: 'planAnnuel', champs: { reference: 'PTA-2031-001', exercice: 2031, planVersion: 1, action: 'Former le personnel', axe: 'ressources_humaines_formation', cibleValeur: 40, cibleUnite: 'agents', etat: 'planifiee', calendrier: ['2031-01-01/2031-03-31'] } });
    const x = await f1.ecrire({ type: 'creer', collection: 'ptaAxes', champs: { code: 'hygiene', libelle: 'Hygiène hospitalière', ordre: 9 } });
    verifier('le plan, l\'action et l\'axe de F1 arrivent à la mère ET chez F2',
      await attendre(async () => (await compte('plansTravail')) === 1 && (await compte('planAnnuel')) === 1 && (await compte('ptaAxes')) === 1 && !!(await chez(f2, 'planAnnuel', a.fiche)) && !!(await chez(f2, 'ptaAxes', x.fiche)), 20000),
      { plans: await compte('plansTravail'), actions: await compte('planAnnuel'), axes: await compte('ptaAxes') });

    /* 2. La mère REFAIT le contrôle de l'adoption. */
    await f2.ecrire({ type: 'creer', collection: 'plansTravail', champs: { reference: 'PTA-2032-V1', exercice: 2032, version: 1, etat: 'adopte' } });
    verifier('un plan n\'est jamais CRÉÉ « adopté » par un poste : refus nommé', await attendre(() => refus(f2, 'adoption_requise'), 15000));
    await f1.ecrire({ type: 'modifier', collection: 'plansTravail', fiche: p.fiche, champs: { etat: 'soumis', soumisPar: 'Rédacteur' } });
    verifier('la soumission (droit d\'écran) passe et voyage', await attendre(async () => ((await chezMere('plansTravail', p.fiche)) || {}).etat === 'soumis' && ((await chez(f2, 'plansTravail', p.fiche)) || {}).etat === 'soumis', 15000));
    await dormir(1200);
    await f2.ecrire({ type: 'modifier', collection: 'plansTravail', fiche: p.fiche, champs: { etat: 'adopte' }, vu: {} });
    verifier('un fileul n\'écrit pas lui-même l\'ADOPTION (il la dépose) : refus nommé, le plan reste soumis à la mère', await attendre(() => refus(f2, 'adoption_reservee'), 15000) && (await chezMere('plansTravail', p.fiche)).etat === 'soumis');
    await f2.ecrire({ type: 'modifier', collection: 'plansTravail', fiche: p.fiche, champs: { adoptePar: 'Moi-même' }, vu: {} });
    verifier('un champ d\'adoption ne s\'écrit pas par un poste : refus nommé', await attendre(() => refus(f2, 'champ_reserve'), 15000) && !(await chezMere('plansTravail', p.fiche)).adoptePar);
    /* La mère applique le dépôt (ici : à sa console, comme le fait le poste mère sous le rôle de l'auteur). */
    await admin('plansTravail', p.fiche, { etat: 'adopte', adoptePar: 'Le Directeur', adopteRole: 'direction', adopteLe: '2031-01-15T09:00:00Z', motifAdoption: 'Comité de direction' });
    verifier('l\'adoption de la mère voyage : F1 et F2 lisent le plan « adopté »', await attendre(async () => ((await chez(f1, 'plansTravail', p.fiche)) || {}).etat === 'adopte' && ((await chez(f2, 'plansTravail', p.fiche)) || {}).etat === 'adopte', 15000));
    await dormir(1200);
    await f1.ecrire({ type: 'modifier', collection: 'plansTravail', fiche: p.fiche, champs: { etat: 'brouillon' }, vu: {} });
    verifier('UN PLAN ADOPTÉ NE RECULE PAS : retour en brouillon refusé en le nommant', await attendre(() => refus(f1, 'etat_regressif'), 15000) && (await chezMere('plansTravail', p.fiche)).etat === 'adopte');

    /* 3. Programme figé, suivi ouvert. */
    await f1.ecrire({ type: 'modifier', collection: 'planAnnuel', fiche: a.fiche, champs: { cibleValeur: 10 }, vu: {} });
    verifier('le PROGRAMME d\'une action d\'un plan adopté ne se réécrit pas : refus nommé, cible intacte à la mère', await attendre(() => refus(f1, 'plan_adopte'), 15000) && (await chezMere('planAnnuel', a.fiche)).cibleValeur === 40);
    await f1.ecrire({ type: 'creer', collection: 'planAnnuel', champs: { reference: 'PTA-2031-002', exercice: 2031, planVersion: 1, action: 'Ajout tardif', etat: 'planifiee' } });
    verifier('une action ne s\'ajoute pas à un plan adopté : la mère n\'en garde rien', await attendre(async () => (await compte('planAnnuel')) === 1, 15000));
    await f2.ecrire({ type: 'modifier', collection: 'planAnnuel', fiche: a.fiche, champs: { realiseValeur: 12, etat: 'en_cours' } });
    verifier('le SUIVI reste ouvert : le réalisé saisi chez F2 arrive à la mère et chez F1', await attendre(async () => ((await chezMere('planAnnuel', a.fiche)) || {}).realiseValeur === 12 && ((await chez(f1, 'planAnnuel', a.fiche)) || {}).realiseValeur === 12, 15000));
    await f1.ecrire({ type: 'modifier', collection: 'plansTravail', fiche: p.fiche, champs: { etat: 'execution' } });
    verifier('la mise en exécution d\'un plan adopté passe (droit d\'écran)', await attendre(async () => ((await chezMere('plansTravail', p.fiche)) || {}).etat === 'execution', 15000));

    /* 4. Mère coupée puis relancée ; rien vers un téléphone. */
    await m.mere.tuer();
    const e = await f2.ecrire({ type: 'creer', collection: 'ptaEtats', champs: { code: 'suspendue', libelle: 'Suspendue', ton: 'warning', ordre: 6 } });
    await m.mere.demarrer();
    verifier('mère relancée : l\'état ajouté pendant la coupure arrive à la mère et chez F1', await attendre(async () => (await compte('ptaEtats')) === 1 && !!(await chez(f1, 'ptaEtats', e.fiche)), 20000), await compte('ptaEtats'));
    const mob = await m.mobile('T1', { profil: 'soignant', fonction: 'infirmier' });
    await dormir(1500);
    const vus = {};
    for (const c of ['planAnnuel', 'plansTravail', 'ptaAxes', 'ptaEtats', 'ptaFinancements']) vus[c] = (await mob.liste(c)).length;
    verifier('un téléphone ne reçoit aucune fiche du plan de travail annuel', Object.values(vus).every((n) => n === 0), vus);
    await m.fermer();
  },
});
