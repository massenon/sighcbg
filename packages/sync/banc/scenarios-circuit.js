'use strict';
/* Scénario CIR1 (Direction de Baguidi, 16/11/2026) : les circuits d'achat TRAVERSENT les postes. Le bon d'expression de besoins et la commande sont des fiches de famille A que plusieurs
   postes complètent ; ce que le banc éprouve ICI, avec de vrais processus (mère et fileuls : de référence en Node, ou Dart avec SIGH_MERE / SIGH_FILEUL / SIGH_MOBILE=dart), c'est le PROTOCOLE :

   · le bon écrit par un fileul est reçu par la mère ET par l'autre fileul (la DAF qui arbitre depuis son poste le voit) ;
   · les PLAGES de numéros, un carnet par série : deux fileuls hors ligne ne tirent jamais le même BEB, et une plage de bons ne brûle aucun numéro de dossier ;
   · la mère REFAIT le contrôle de l'état : un bon n'est jamais créé « accordé », un fileul n'écrit pas lui-même un arbitrage (il se dépose, la mère l'applique), l'état ne régresse jamais,
     l'aval (préparation, transmission) suppose l'arbitrage que la mère détient ;
   · la mère coupée puis relancée : rien n'est perdu ; jamais un bon ni une commande (prix d'achat des lignes) vers un téléphone.
   Ce que le poste fait de ses fiches (dépôt de l'arbitrage, application sous le rôle de l'auteur, tâches du comptable et du stock, fusion qui ne régresse pas) est éprouvé par
   `apps/poste/test/circuit_achats_sync_test.dart` (VRAIE mère Dart, deux vrais moteurs de fileul) et `packages/domaine/test/circuit_synchro_test.dart`. */
module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async CIR1() {
    titre('CIRCUITS-CIR1 · besoins et commandes à travers les postes : plages par série, état réservé et jamais régressif, mère coupée, rien vers un téléphone');
    const m = await monde({ relais: true });
    const f1 = await m.fileul('F1');
    const f2 = await m.fileul('F2');
    const compte = async (c) => (await m.mere.admin('GET', '/admin/compte?collection=' + c)).json.n;
    const refus = async (f, code) => (await f.etat()).a_traiter.some((x) => x.code === code);
    const admin = async (collection, fiche, champs) => (await m.mere.admin('POST', '/admin/referentiel', { collection, fiche, champs })).json;
    const chez = async (f, c, id) => { const l = (await f.liste(c)).find((x) => x.id === id); return l && l.data; };
    const chezMere = async (c, id) => { const r = (await m.mere.admin('GET', '/admin/fiche?collection=' + c + '&id=' + encodeURIComponent(id))).json; return r && !r.absente ? r.data : undefined; };

    /* 1. Les PLAGES, un carnet par série : disjointes entre postes, la série des commandes part de 1, celle des dossiers n'est pas brûlée. */
    const p1 = (await f1.post('/plage', { nom: 'besoins', taille: 20, minimum: 5 })).json;
    const p2 = (await f2.post('/plage', { nom: 'besoins', taille: 20, minimum: 5 })).json;
    const pc = (await f1.post('/plage', { nom: 'commandes', taille: 20 })).json;
    verifier('deux plages de bons : disjointes, au-delà du plus grand rang déjà écrit', p1.debut >= 5 && p2.debut > p1.fin && p2.fin - p2.debut === 19, { p1, p2 });
    verifier('la série des commandes a SON carnet (elle part de 1) : une plage de bons ne brûle aucun numéro', pc.debut === 1 && pc.fin === 20, pc);
    const dossier = await f1.ecrire({ type: 'creer', collection: 'patients', champs: { nom: 'Premier dossier' } });
    verifier('le carnet des DOSSIERS n\'a pas bougé : le premier code est tiré dans sa plage habituelle', /^CBG\/\d+\/26$/.test((await f1.vue('patients', dossier.fiche)).data.code), (await f1.vue('patients', dossier.fiche)).data);

    /* 2. Le besoin écrit chez F1 est reçu par la mère ET par F2 (la DAF qui arbitre depuis son poste). */
    const b = await f1.ecrire({ type: 'creer', collection: 'besoins', champs: { reference: 'BEB-2026-' + String(p1.debut).padStart(4, '0'), etape: 'soumis', service: 'Laboratoire', demandeur: 'Agent F1', lignes: [{ produit: 'Gants', quantiteDemandee: 2, prixAchat: 500 }] } });
    verifier('le besoin de F1 arrive à la mère ET chez F2', await attendre(async () => (await compte('besoins')) === 1 && !!(await chez(f2, 'besoins', b.fiche)), 15000));

    /* 3. La mère REFAIT le contrôle de l'état. */
    await f1.ecrire({ type: 'creer', collection: 'besoins', champs: { reference: 'BEB-TRICHE', etape: 'accorde', service: 'Labo', demandeur: 'Agent F1', lignes: [] } });
    verifier('un bon n\'est jamais CRÉÉ « accordé » par un poste : refus nommé', await attendre(() => refus(f1, 'arbitrage_requis'), 15000));
    verifier('…et la mère n\'en a rien gardé', (await compte('besoins')) === 1);
    await f2.ecrire({ type: 'modifier', collection: 'besoins', fiche: b.fiche, champs: { etape: 'accorde', arbitrePar: 'Moi-même' }, vu: {} });
    verifier('un fileul n\'écrit pas lui-même un arbitrage (il se dépose) : refus nommé, état intact à la mère', await attendre(() => refus(f2, 'arbitrage_reserve'), 15000) && (await chezMere('besoins', b.fiche)).etape === 'soumis');
    /* La mère applique le dépôt (ici : à sa console, comme le fait le poste mère). */
    await admin('besoins', b.fiche, { etape: 'accorde', arbitrePar: 'La DAF', arbitreLe: '2026-11-16T09:00:00Z' });
    verifier('l\'arbitrage de la mère voyage : F1 (l\'auteur) et F2 le lisent « accordé »', await attendre(async () => (await chez(f1, 'besoins', b.fiche) || {}).etape === 'accorde' && (await chez(f2, 'besoins', b.fiche) || {}).etape === 'accorde', 15000));
    await f1.ecrire({ type: 'modifier', collection: 'besoins', fiche: b.fiche, champs: { etape: 'soumis' }, vu: {} });
    verifier('L\'ÉTAT NE RÉGRESSE JAMAIS : le retour à « soumis » est refusé en le nommant, le bon reste accordé à la mère', await attendre(() => refus(f1, 'etat_regressif'), 15000) && (await chezMere('besoins', b.fiche)).etape === 'accorde');
    await f1.ecrire({ type: 'modifier', collection: 'besoins', fiche: b.fiche, champs: { etape: 'prepare' } });
    verifier('l\'aval suit : la préparation est acceptée dès que la mère détient l\'arbitrage', await attendre(async () => ((await chezMere('besoins', b.fiche)) || {}).etape === 'prepare', 15000));

    /* 4. La commande : même garde (RG-04). */
    const c = await f1.ecrire({ type: 'creer', collection: 'commandes', champs: { reference: 'BC-2026-0001', statutCommande: 'attente_validation', fournisseur: 'F001', montant: 5000, lignes: [] } });
    verifier('la commande de F1 arrive à la mère et chez F2', await attendre(async () => (await compte('commandes')) === 1 && !!(await chez(f2, 'commandes', c.fiche)), 15000));
    await f2.ecrire({ type: 'modifier', collection: 'commandes', fiche: c.fiche, champs: { statutCommande: 'validee', valideePar: 'Moi' }, vu: {} });
    verifier('RG-04 : un fileul ne valide pas une commande lui-même (refus nommé), elle reste en attente à la mère', await attendre(() => refus(f2, 'arbitrage_reserve'), 15000) && (await chezMere('commandes', c.fiche)).statutCommande === 'attente_validation');
    await f1.ecrire({ type: 'modifier', collection: 'commandes', fiche: c.fiche, champs: { statutCommande: 'transmise' }, vu: {} });
    verifier('la transmission suppose la validation DA : refusée tant que la mère ne la détient pas', await attendre(() => refus(f1, 'arbitrage_requis'), 15000));
    await admin('commandes', c.fiche, { statutCommande: 'validee', valideePar: 'La DAF', dateValidation: '2026-11-16' });
    await attendre(async () => ((await chez(f1, 'commandes', c.fiche)) || {}).statutCommande === 'validee', 15000);
    await dormir(1200); /* le fileul écrit sa modification sur la VERSION VUE confirmée : lui laisser le temps de confirmer l'arbitrage qu'il vient de lire, sinon sa modification est lue comme concurrente */
    const tr = await f1.ecrire({ type: 'modifier', collection: 'commandes', fiche: c.fiche, champs: { statutCommande: 'transmise' } });
    verifier('validée par la mère, la commande part chez le fournisseur : la transmission voyage', tr.refus === undefined && await attendre(async () => ((await chezMere('commandes', c.fiche)) || {}).statutCommande === 'transmise', 15000), { tr, mere: await chezMere('commandes', c.fiche), f1: await chez(f1, 'commandes', c.fiche), etat: await f1.etat() });

    /* 5. Mère coupée puis relancée : le bon écrit pendant la coupure n'est pas perdu. */
    await m.mere.tuer();
    const b2 = await f1.ecrire({ type: 'creer', collection: 'besoins', champs: { reference: 'BEB-2026-' + String(p1.debut + 1).padStart(4, '0'), etape: 'soumis', service: 'Maternité', demandeur: 'Agent F1', lignes: [] } });
    await m.mere.demarrer();
    verifier('mère relancée : le bon écrit pendant la coupure arrive à la mère et chez F2, sans doublon', await attendre(async () => (await compte('besoins')) === 2 && !!(await chez(f2, 'besoins', b2.fiche)), 20000), await compte('besoins'));

    /* 6. Jamais vers un téléphone : le prix d'achat des lignes reste dans la clinique (RG-13). */
    const mob = await m.mobile('T1', { profil: 'soignant', fonction: 'infirmier' });
    await dormir(1500);
    verifier('un téléphone ne reçoit ni les bons de besoins ni les commandes', (await mob.liste('besoins')).length === 0 && (await mob.liste('commandes')).length === 0, { b: (await mob.liste('besoins')).length, c: (await mob.liste('commandes')).length });
    await m.fermer();
  },
});
