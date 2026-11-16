'use strict';
/* Scénario FIN1 (Direction de Baguidi, Q26, 16/11/2026) : budgets et immobilisations rejoignent la synchronisation (famille A, miroir de `sync_dart/lib/src/mere.dart`). Un import fait chez un fileul
   ne reste plus local au poste : la fiche arrive à la mère ET à l'autre fileul, champ à champ (deux postes qui modifient deux champs différents gardent les deux changements) ; la mère coupée puis
   relancée ne perd rien ; JAMAIS vers un téléphone (donnée financière, RG-13). Les couvertures d'assurance (même décision) étaient déjà en famille A.
   Ce que le poste fait de ces fiches (écriture directe d'un jeu restreint, numérotation) est éprouvé par `apps/poste/test/budgets_immobilisations_sync_test.dart`. */
module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async FIN1() {
    titre('FINANCE-FIN1 · budgets et immobilisations à travers les postes (famille A), champ à champ, mère coupée, rien vers un téléphone');
    const m = await monde({ relais: true });
    const f1 = await m.fileul('F1');
    const f2 = await m.fileul('F2');
    const compte = async (c) => (await m.mere.admin('GET', '/admin/compte?collection=' + c)).json.n;
    const chez = async (f, c, id) => { const l = (await f.liste(c)).find((x) => x.id === id); return l && l.data; };
    const chezMere = async (c, id) => { const r = (await m.mere.admin('GET', '/admin/fiche?collection=' + c + '&id=' + encodeURIComponent(id))).json; return r && !r.absente ? r.data : undefined; };

    const b = await f1.ecrire({ type: 'creer', collection: 'budgets', champs: { reference: 'BG-2026-001', exercice: 2026, centreCout: 'CONSULTATION', montant: 1500000 } });
    const i = await f1.ecrire({ type: 'creer', collection: 'immobilisations', champs: { designation: 'Échographe', dateAcquisition: '2026-02-01', valeur: 4200000 } });
    verifier('le budget et l\'immobilisation écrits chez F1 arrivent à la mère ET chez F2, sans doublon',
      await attendre(async () => (await compte('budgets')) === 1 && (await compte('immobilisations')) === 1 && !!(await chez(f2, 'budgets', b.fiche)) && !!(await chez(f2, 'immobilisations', i.fiche)), 20000),
      { budgets: await compte('budgets'), immobilisations: await compte('immobilisations') });

    /* Deux postes modifient deux champs différents : les deux changements survivent (fusion champ à champ). */
    await dormir(1200);
    await f1.ecrire({ type: 'modifier', collection: 'budgets', fiche: b.fiche, champs: { montant: 1600000 } });
    await f2.ecrire({ type: 'modifier', collection: 'budgets', fiche: b.fiche, champs: { observation: 'Révisé par la DAF' } });
    verifier('deux champs modifiés par deux postes : les deux changements arrivent partout',
      await attendre(async () => { const x = await chezMere('budgets', b.fiche); const y = await chez(f1, 'budgets', b.fiche); return x && y && x.montant === 1600000 && x.observation === 'Révisé par la DAF' && y.observation === 'Révisé par la DAF' && y.montant === 1600000; }, 20000),
      { mere: await chezMere('budgets', b.fiche), f1: await chez(f1, 'budgets', b.fiche) });

    /* Mère coupée puis relancée : l'immobilisation écrite pendant la coupure n'est pas perdue. */
    await m.mere.tuer();
    const i2 = await f1.ecrire({ type: 'creer', collection: 'immobilisations', champs: { designation: 'Autoclave', dateAcquisition: '2026-03-01', valeur: 900000 } });
    await m.mere.demarrer();
    verifier('mère relancée : l\'immobilisation écrite pendant la coupure arrive à la mère et chez F2',
      await attendre(async () => (await compte('immobilisations')) === 2 && !!(await chez(f2, 'immobilisations', i2.fiche)), 20000), await compte('immobilisations'));

    /* Jamais vers un téléphone (RG-13). */
    const mob = await m.mobile('T1', { profil: 'soignant', fonction: 'infirmier' });
    await dormir(1500);
    verifier('un téléphone ne reçoit ni les budgets ni les immobilisations', (await mob.liste('budgets')).length === 0 && (await mob.liste('immobilisations')).length === 0,
      { b: (await mob.liste('budgets')).length, i: (await mob.liste('immobilisations')).length });
    await m.fermer();
  },
});
