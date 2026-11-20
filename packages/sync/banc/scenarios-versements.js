'use strict';
/* Scénario VERS1 (Direction de Baguidi, 20/11/2026, §13) : le règlement d'une facture en plusieurs versements, à travers les postes. Un versement est une ligne de JOURNAL (famille B, ajout
   seul ; miroir de `sync_dart/lib/src/mere.dart`) : deux postes qui encaissent chacun un versement sur la même facture le même jour ajoutent deux lignes, jamais un doublon (même rejeu : une
   seule fois), la mère en tient la somme et le reste dû est JUSTE ; un versement ne se réécrit pas (la correction est une contre-passation, une AUTRE ligne) ; jamais vers un téléphone
   (montants et références de transaction, RG-13). Ce que le poste en fait (allocation aux lignes, écritures par type, états, reçu) est éprouvé par `apps/poste/test/versements_poste_test.dart`. */
module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async VERS1() {
    titre('VERSEMENTS-VERS1 · deux postes encaissent chacun un versement sur la même facture le même jour (famille B), reste dû juste, contre-passation = une autre ligne, rien vers un téléphone');
    const m = await monde({ relais: true });
    const f1 = await m.fileul('F1');
    const f2 = await m.fileul('F2');
    /* Le téléphone est appairé AVANT les écritures : un test de portée sur des données antérieures à l'appairage ne prouve rien. */
    const mob = await m.mobile('T1', { profil: 'soignant', fonction: 'infirmier' });
    const total = 8000;
    const compte = async () => (await m.mere.admin('GET', '/admin/compte?collection=versements')).json.n;
    const chezMere = async (id) => { const r = (await m.mere.admin('GET', '/admin/fiche?collection=versements&id=' + encodeURIComponent(id))).json; return r && !r.absente ? r.data : undefined; };
    const chez = async (f, id) => { const l = (await f.liste('versements')).find((x) => x.id === id); return l && l.data; };
    const base = { factureId: 'F-2026-001', factureNumero: 'FN-2026-00001', sens: 'versement', date: '2026-11-20', lot: 'LOT-1', statut: 'actif' };

    /* Chaque poste écrit SON versement (identifiant préfixé par le poste), le même jour, sur la même facture. */
    const v1 = await f1.ecrire({ type: 'creer', collection: 'versements', fiche: 'F1-VRS00001', champs: { ...base, numero: 'VRS-2026-00001', montant: 5000, type: 'mobile_money', typeLibelle: 'Mobile Money', modaliteLibelle: 'MTN', reference: 'MP2611.0042', compteTresorerie: '521000', caissier: 'caissier-1' } });
    const v2 = await f2.ecrire({ type: 'creer', collection: 'versements', fiche: 'F2-VRS00001', champs: { ...base, numero: 'VRS-2026-00001', montant: 3000, type: 'especes', typeLibelle: 'Espèces', compteTresorerie: '571000', caissier: 'caissier-2' } });
    verifier('les deux versements arrivent à la mère ET chez l\'autre poste, sans doublon',
      await attendre(async () => (await compte()) === 2 && !!(await chez(f1, v2.fiche)) && !!(await chez(f2, v1.fiche)), 20000), { mere: await compte() });

    /* La somme des versements de la mère est le total réglé ; le reste dû est juste (8 000 − 5 000 − 3 000 = 0). */
    const lus = [await chezMere(v1.fiche), await chezMere(v2.fiche)];
    const verse = lus.reduce((a, x) => a + (x ? x.montant : 0), 0);
    verifier('la mère tient les deux lignes : total versé 8 000, reste dû 0, une ligne par type', verse === total && total - verse === 0 && lus.map((x) => x && x.type).sort().join() === 'especes,mobile_money', lus);

    /* Un rejeu du même versement (mauvais réseau) ne se compte jamais deux fois. */
    await f1.ecrire({ type: 'creer', collection: 'versements', fiche: 'F1-VRS00001', champs: { ...base, numero: 'VRS-2026-00001', montant: 5000, type: 'mobile_money' } });
    await dormir(1200);
    verifier('le même versement rejoué ne s\'ajoute pas (rejeu sans effet)', (await compte()) === 2, await compte());

    /* Un versement ne se réécrit pas (journal : ajout seul) : la mère refuse la modification, la ligne reste intacte. */
    let refus = null;
    try { await f1.ecrire({ type: 'modifier', collection: 'versements', fiche: v1.fiche, champs: { montant: 1 } }); } catch (e) { refus = e; }
    await dormir(1500);
    const apres = await chezMere(v1.fiche);
    verifier('le montant d\'un versement écrit ne se modifie pas (la ligne de la mère reste à 5 000)', apres && apres.montant === 5000, apres);

    /* L'annulation est une CONTRE-PASSATION : une AUTRE ligne, qui désigne la première ; la somme nette retombe. */
    const c1 = await f2.ecrire({ type: 'creer', collection: 'versements', fiche: 'F2-VRS00002', champs: { ...base, numero: 'VRS-2026-00002', sens: 'contrepassation', annule: v1.fiche, montant: 5000, type: 'mobile_money', motif: 'Montant saisi par erreur', caissier: 'comptable-1' } });
    verifier('la contre-passation est une troisième ligne, la première n\'est pas touchée',
      await attendre(async () => (await compte()) === 3 && !!(await chezMere(c1.fiche)), 15000), await compte());
    const tout = [await chezMere(v1.fiche), await chezMere(v2.fiche), await chezMere(c1.fiche)];
    const net = tout.reduce((a, x) => a + (x.sens === 'contrepassation' ? -x.montant : x.montant), 0);
    verifier('somme nette après contre-passation : 3 000 versés, 5 000 de reste dû ; la ligne d\'origine est intacte', net === 3000 && tout[0].montant === 5000 && tout[0].sens === 'versement', { net });

    /* Mère coupée puis relancée : le versement écrit pendant la coupure n'est pas perdu. */
    await m.mere.tuer();
    const v3 = await f1.ecrire({ type: 'creer', collection: 'versements', fiche: 'F1-VRS00002', champs: { ...base, factureId: 'F-2026-002', numero: 'VRS-2026-00003', lot: 'LOT-2', montant: 2000, type: 'tpe', typeLibelle: 'TPE (carte bancaire)', caissier: 'caissier-1' } });
    await m.mere.demarrer();
    verifier('mère relancée : le versement de la coupure arrive à la mère et chez F2, une fois',
      await attendre(async () => (await compte()) === 4 && !!(await chez(f2, v3.fiche)), 25000), await compte());

    /* Jamais vers un téléphone (RG-13). */
    /* Un téléphone n'ÉCRIT pas un versement non plus (montants et références de transaction, RG-13) : la mère refuse l'opération du téléphone, la ligne n'existe pas chez elle. */
    const avant = await compte();
    await mob.ecrire({ type: 'creer', collection: 'versements', fiche: 'T1-VRS00001', champs: { ...base, numero: 'VRS-2026-00099', montant: 100, type: 'especes', caissier: 'tel' } }).catch(() => null);
    await dormir(2500);
    verifier('un téléphone ne peut écrire aucun versement (la mère en compte toujours autant)', (await compte()) === avant && !(await chezMere('T1-VRS00001')), { avant, apres: await compte() });
    verifier('un téléphone ne reçoit aucun versement', (await mob.liste('versements')).length === 0, (await mob.liste('versements')).length);
    await m.fermer();
  },
});
