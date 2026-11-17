'use strict';
/* Scénario FAI1 (Direction de Baguidi, 17/11/2026 : fiches d'aide de l'assistant et import daté de la liasse fiscale) : deux collections traversent les postes.
   · `fichesAide` (famille A : fiches descriptives, champ à champ, dans les deux sens) — une fiche écrite sur un fileul arrive à la mère et à l'autre fileul ; mais la VALIDATION ne s'écrit que
     sur la mère (refus nommé `validation_reservee_mere` : un fileul ne crée pas une fiche déjà validée, ne pose ni validateur ni professionnel, ne valide pas) et une fiche validée ne se réécrit pas
     (`fiche_validee`) ; l'archiver reste permis ; la validation écrite par la mère rejoint les deux fileuls ;
   · `documentsFiscaux` (famille R : la mère seule écrit) — la liasse importée sur la mère arrive aux DEUX fileuls ; un fileul ne l'écrit pas (`droit_refuse`) ;
   · ni l'une ni l'autre ne part vers un téléphone (aucun écran du mobile ne les lit ; la liasse est une donnée financière, RG-13).
   Miroir de `sync_dart/lib/src/mere.dart` ; la règle d'écriture vient de `packages/domaine/lib/src/assistant/fiches_aide.dart` (`refusEcritureFicheAide`).
   Ce que le poste fait (contrôle de l'auteur, geste réservé, professionnel nommé, journal) est éprouvé par les tests du domaine et du poste. */
module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async FAI1() {
    titre('FAI-FAI1 · fiches d\'aide : écrites partout, validation écrite par la mère seule, fiche validée non réécrite, archivage permis ; liasse fiscale : la mère écrit, les fileuls reçoivent ; rien vers un téléphone');
    const m = await monde({ relais: true });
    const f1 = await m.fileul('F1');
    const f2 = await m.fileul('F2');
    /* Le téléphone est appairé AVANT les écritures : la portée d'un mobile ne remonte pas avant son appairage, un téléphone appairé après ne prouverait rien. */
    const mob = await m.mobile('T1', { profil: 'soignant', fonction: 'infirmier' });
    const compte = async (c) => (await m.mere.admin('GET', '/admin/compte?collection=' + c)).json.n;
    const refus = async (f, code) => (await f.etat()).a_traiter.some((x) => x.code === code);
    const admin = async (collection, fiche, champs) => (await m.mere.admin('POST', '/admin/referentiel', { collection, fiche, champs })).json;
    const chez = async (f, c, id) => { const l = (await f.liste(c)).find((x) => x.id === id); return l && l.data; };
    const chezMere = async (c, id) => { const r = (await m.mere.admin('GET', '/admin/fiche?collection=' + c + '&id=' + encodeURIComponent(id))).json; return r && !r.absente ? r.data : undefined; };
    const fiche = { type: 'aide', statut: 'proposee', titre: 'Enregistrer un courrier entrant', motsCles: ['courrier entrant'], roles: [], ecrans: [], etapes: ['Ouvrir l’écran', 'Choisir « arrivée »'], auteurId: 'U-F1', auteurNom: 'Auteur Fictif' };

    /* 1. Une fiche écrite sur un fileul arrive à la mère et à l'autre fileul. */
    await f1.ecrire({ type: 'creer', collection: 'fichesAide', fiche: 'FA-F1-1', champs: fiche });
    verifier('une fiche d\'aide écrite sur un fileul arrive à la mère ET à l\'autre fileul',
      await attendre(async () => ((await chezMere('fichesAide', 'FA-F1-1')) || {}).titre === fiche.titre && !!(await chez(f2, 'fichesAide', 'FA-F1-1')), 20000));
    await dormir(1200);
    await f2.ecrire({ type: 'modifier', collection: 'fichesAide', fiche: 'FA-F1-1', champs: { titre: 'Enregistrer un courrier arrivé' }, vu: {} });
    verifier('l\'autre fileul corrige le titre d\'une fiche non validée : la correction arrive à la mère et au premier fileul',
      await attendre(async () => ((await chezMere('fichesAide', 'FA-F1-1')) || {}).titre === 'Enregistrer un courrier arrivé' && ((await chez(f1, 'fichesAide', 'FA-F1-1')) || {}).titre === 'Enregistrer un courrier arrivé', 20000));

    /* 2. La validation ne s'écrit pas sur un fileul. */
    await f1.ecrire({ type: 'creer', collection: 'fichesAide', fiche: 'FA-F1-2', champs: { ...fiche, statut: 'validee', validePar: 'Moi-même', valideLe: '2026-11-17' } });
    verifier('un fileul ne crée pas une fiche déjà validée : refus nommé (validation_reservee_mere), rien n\'arrive à la mère',
      await attendre(() => refus(f1, 'validation_reservee_mere'), 15000) && !(await chezMere('fichesAide', 'FA-F1-2')), await chezMere('fichesAide', 'FA-F1-2'));
    await f2.ecrire({ type: 'modifier', collection: 'fichesAide', fiche: 'FA-F1-1', champs: { validePar: 'Moi-même', valideLe: '2026-11-17', statut: 'validee' }, vu: {} });
    verifier('un fileul ne valide pas : la fiche reste « proposée » à la mère, sans validateur',
      await attendre(() => refus(f2, 'validation_reservee_mere'), 15000) && ((await chezMere('fichesAide', 'FA-F1-1')) || {}).statut === 'proposee' && !((await chezMere('fichesAide', 'FA-F1-1')) || {}).validePar);

    /* 3. La validation écrite par la mère rejoint les deux fileuls. */
    await admin('fichesAide', 'FA-F1-1', { statut: 'validee', validateurId: 'U-MERE', validePar: 'Valideur Fictif', valideLe: '2026-11-17' });
    verifier('la validation écrite par la mère (validateur nommé, date) arrive aux DEUX fileuls',
      await attendre(async () => { const a = await chez(f1, 'fichesAide', 'FA-F1-1'), b = await chez(f2, 'fichesAide', 'FA-F1-1'); return !!a && !!b && a.statut === 'validee' && b.validePar === 'Valideur Fictif' && a.valideLe === '2026-11-17'; }, 20000));

    /* 4. Une fiche validée ne se réécrit pas ; l'archiver reste permis. */
    await dormir(1200);
    await f1.ecrire({ type: 'modifier', collection: 'fichesAide', fiche: 'FA-F1-1', champs: { etapes: ['Autre étape'] }, vu: {} });
    verifier('un fileul ne réécrit pas une fiche validée : refus nommé (fiche_validee), le texte relu reste celui de la mère',
      await attendre(() => refus(f1, 'fiche_validee'), 15000) && JSON.stringify(((await chezMere('fichesAide', 'FA-F1-1')) || {}).etapes) === JSON.stringify(fiche.etapes));
    await f2.ecrire({ type: 'modifier', collection: 'fichesAide', fiche: 'FA-F1-1', champs: { statut: 'archive', statutAvantArchivage: 'validee', archivePar: 'Archiviste', motifArchivage: 'Procédure changée', archiveLe: '2026-11-17T10:00:00Z' }, vu: {} });
    verifier('archiver une fiche validée depuis un fileul est permis (RG-14) : la mère et l\'autre fileul la voient archivée, jamais supprimée',
      await attendre(async () => ((await chezMere('fichesAide', 'FA-F1-1')) || {}).statut === 'archive' && ((await chez(f1, 'fichesAide', 'FA-F1-1')) || {}).motifArchivage === 'Procédure changée', 20000));

    /* 5. La liasse fiscale : la mère écrit, les fileuls reçoivent, un fileul n'écrit pas. */
    const liasse = { genre: 'liasse', exercice: 2025, dateEffet: '2026-04-30', source: 'Remise à la DGI', importeLe: '2026-11-17T09:00:00Z', importePar: 'Comptable Fictif', statut: 'actif', contenu: { DEPOT: { exerciceN: 2025 } } };
    await admin('documentsFiscaux', 'doc-fiscal-liasse-2025-2026-04-30', liasse);
    verifier('la liasse importée sur la mère arrive aux DEUX fileuls (source, date de dépôt et auteur intacts)',
      await attendre(async () => { const a = await chez(f1, 'documentsFiscaux', 'doc-fiscal-liasse-2025-2026-04-30'), b = await chez(f2, 'documentsFiscaux', 'doc-fiscal-liasse-2025-2026-04-30'); return !!a && !!b && a.source === 'Remise à la DGI' && b.dateEffet === '2026-04-30' && a.importePar === 'Comptable Fictif'; }, 20000));
    await f1.ecrire({ type: 'creer', collection: 'documentsFiscaux', fiche: 'doc-fiscal-liasse-2025-2026-09-01', champs: { ...liasse, dateEffet: '2026-09-01' } });
    verifier('un fileul n\'écrit pas la liasse : refus nommé (droit_refuse), la mère n\'en reçoit pas une seconde version',
      await attendre(() => refus(f1, 'droit_refuse'), 15000) && (await compte('documentsFiscaux')) === 1, await compte('documentsFiscaux'));

    /* 6. Rien vers un téléphone. */
    await dormir(1500);
    const vus = {};
    for (const c of ['fichesAide', 'documentsFiscaux']) vus[c] = (await mob.liste(c)).length;
    verifier('un téléphone ne reçoit ni les fiches d\'aide ni la liasse fiscale déposée (donnée financière, RG-13)', Object.values(vus).every((n) => n === 0), vus);
    await m.fermer();
  },
});
