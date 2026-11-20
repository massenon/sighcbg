'use strict';
/* Scénario FLI1 (Direction de Baguidi, 18/11/2026, points 3 et 4 : « validation d'une fiche d'aide » et « import de la liasse » par un FILEUL) : les deux gestes qui n'étaient possibles que sur la mère passent par le
   circuit des validations déposées (`validationsDeposees`, famille A), genres `fiche_aide_valider` et `liasse_importer`. Miroir de `sync_dart/lib/src/mere.dart`. Ce que le banc éprouve ICI, avec de vrais processus,
   c'est le PROTOCOLE :
   · la demande de validation d'une fiche d'aide et la demande d'import d'une liasse (contenu de ~32 Ko, la vraie taille d'une liasse) arrivent à la mère ET chez l'autre fileul ; le verdict nommé que la
     mère écrit sur la MÊME fiche de dépôt revient à l'auteur et à l'autre poste (et le contenu du document, vidé après verdict, ne reste pas dupliqué) ;
   · la VALIDATION d'une fiche d'aide reste écrite par la mère seule : un fileul qui l'écrirait lui-même est refusé (`validation_reservee_mere`) — le dépôt est la seule voie ;
   · la liasse reste de FAMILLE R : un fileul n'écrit pas `documentsFiscaux` (`droit_refuse`), la version écrite par la mère arrive aux deux fileuls ;
   · mère coupée : la demande déposée pendant la coupure arrive à la relance, sans doublon ;
   · jamais vers un téléphone : ni les demandes, ni la liasse.
   Ce que le poste fait (contrôle à blanc, compte signataire, geste réservé relu à la matrice de la mère, auteur ≠ validateur, validation stricte REJOUÉE, taille bornée par un réglage, notification) est
   éprouvé par `apps/poste/test/fiche_aide_liasse_sync_test.dart` contre la vraie mère Dart, avec mutations. */
const fs = require('node:fs');
const path = require('node:path');

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async FLI1() {
    titre('FLI-FLI1 · validation d\'une fiche d\'aide et import de la liasse déposés par un fileul : demandes lues partout, verdict nommé de la mère, validation réservée à la mère, liasse en R, mère coupée, rien vers un téléphone');
    const liasse = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', '..', 'apps', 'poste', 'tool', 'donnees', 'liasse_2025_demo.json'), 'utf8'));
    const m = await monde({ relais: true });
    const f1 = await m.fileul('F1');
    const f2 = await m.fileul('F2');
    const mob = await m.mobile('T1', { profil: 'soignant', fonction: 'infirmier' });
    const compte = async (c) => (await m.mere.admin('GET', '/admin/compte?collection=' + c)).json.n;
    const refus = async (f, code) => (await f.etat()).a_traiter.some((x) => x.code === code);
    const admin = async (collection, fiche, champs) => (await m.mere.admin('POST', '/admin/referentiel', { collection, fiche, champs })).json;
    const chez = async (f, c, id) => { const l = (await f.liste(c)).find((x) => x.id === id); return l && l.data; };
    const chezMere = async (c, id) => { const r = (await m.mere.admin('GET', '/admin/fiche?collection=' + c + '&id=' + encodeURIComponent(id))).json; return r && !r.absente ? r.data : undefined; };
    const fiche = { type: 'aide', statut: 'proposee', titre: 'Enregistrer un courrier entrant', motsCles: ['courrier entrant'], roles: [], ecrans: [], etapes: ['Ouvrir l’écran', 'Choisir « arrivée »'], auteurId: 'U-F1', auteurNom: 'Auteur Fictif' };
    const base = { etat: 'deposee', demandeRole: 'direction', demandePar: 'Valideur Fictif', demandePoste: 'F2', demandeCompte: 'U-F2', demandeLe: '2026-11-18T09:00:00.000Z', statut: 'actif' };

    /* 1. Le fileul DÉPOSE la validation d'une fiche d'aide ; la fiche, elle, reste « proposée » à la mère. */
    await f1.ecrire({ type: 'creer', collection: 'fichesAide', fiche: 'F1-FAI-1', champs: fiche });
    await attendre(async () => !!(await chezMere('fichesAide', 'F1-FAI-1')) && !!(await chez(f2, 'fichesAide', 'F1-FAI-1')), 20000);
    await f2.ecrire({ type: 'creer', collection: 'validationsDeposees', fiche: 'VDP-F2-1', champs: { ...base, genre: 'fiche_aide_valider', famille: 'fichesAide', cible: 'F1-FAI-1', libelle: 'Validation de la fiche d’aide « Enregistrer un courrier entrant »', validateurId: 'U-F2', contenuVu: JSON.stringify(fiche) } });
    verifier('la demande de validation d\'une fiche d\'aide arrive à la mère ET chez l\'autre fileul ; la fiche reste « proposée »',
      await attendre(async () => ((await chezMere('validationsDeposees', 'VDP-F2-1')) || {}).genre === 'fiche_aide_valider' && !!(await chez(f1, 'validationsDeposees', 'VDP-F2-1')), 20000)
      && ((await chezMere('fichesAide', 'F1-FAI-1')) || {}).statut === 'proposee');

    /* 2. La VALIDATION reste écrite par la mère seule : un fileul qui l'écrirait lui-même est refusé, nommément. */
    await dormir(1200);
    await f2.ecrire({ type: 'modifier', collection: 'fichesAide', fiche: 'F1-FAI-1', champs: { statut: 'validee', validePar: 'Moi-même', valideLe: '2026-11-18', validateurId: 'U-F2' }, vu: {} });
    verifier('un fileul n\'écrit pas la validation d\'une fiche : refus nommé (validation_reservee_mere), la fiche reste proposée à la mère — le dépôt est la seule voie',
      await attendre(() => refus(f2, 'validation_reservee_mere'), 15000) && ((await chezMere('fichesAide', 'F1-FAI-1')) || {}).statut === 'proposee');

    /* 3. La mère applique : la validation qu'elle écrit et le verdict nommé reviennent partout. */
    await admin('fichesAide', 'F1-FAI-1', { statut: 'validee', validateurId: 'U-F2', validePar: 'Valideur Fictif', valideLe: '2026-11-18' });
    await admin('validationsDeposees', 'VDP-F2-1', { etat: 'appliquee', traitePar: 'Poste mère', traiteLe: '2026-11-18T09:05:00.000Z', appliqueLe: '2026-11-18T09:05:00.000Z', signeLe: '2026-11-18T09:00:00.000Z' });
    verifier('la validation appliquée par la mère ET le verdict arrivent aux DEUX fileuls (validateur nommé, date, verdict sur la même fiche de dépôt)',
      await attendre(async () => { const a = await chez(f1, 'fichesAide', 'F1-FAI-1'), b = await chez(f2, 'fichesAide', 'F1-FAI-1'), v = await chez(f2, 'validationsDeposees', 'VDP-F2-1'); return !!a && !!b && !!v && a.statut === 'validee' && b.validePar === 'Valideur Fictif' && v.etat === 'appliquee'; }, 20000));

    /* 4. L'import de la liasse : la demande porte un document de la taille d'une vraie liasse, elle arrive intacte ; la collection reste R. */
    const octets = Buffer.byteLength(JSON.stringify(liasse), 'utf8');
    await f1.ecrire({ type: 'creer', collection: 'validationsDeposees', fiche: 'VDP-F1-2', champs: { ...base, demandePoste: 'F1', demandeRole: 'comptable', demandePar: 'Comptable Fictif', demandeCompte: 'U-F1', genre: 'liasse_importer', famille: 'documentsFiscaux', cible: 'liasse|2025|2026-04-30', libelle: 'Import de la liasse 2025 (dépôt du 2026-04-30)', documentGenre: 'liasse', exercice: 2025, dateDepot: '2026-04-30', source: 'Remise à la DGI', contenu: liasse, octets, resume: { BILAN_ACTIF: 29 } } });
    verifier('la demande d\'import (document de ' + Math.round(octets / 1024) + ' Ko) arrive à la mère ET chez l\'autre fileul, contenu intact',
      await attendre(async () => { const a = await chezMere('validationsDeposees', 'VDP-F1-2'), b = await chez(f2, 'validationsDeposees', 'VDP-F1-2'); return !!a && !!b && JSON.stringify(a.contenu) === JSON.stringify(liasse) && JSON.stringify(b.contenu) === JSON.stringify(liasse); }, 30000));
    await f1.ecrire({ type: 'creer', collection: 'documentsFiscaux', fiche: 'doc-fiscal-liasse-2025-2026-04-30', champs: { genre: 'liasse', exercice: 2025, dateEffet: '2026-04-30', source: 'Remise à la DGI', importePar: 'Comptable Fictif', statut: 'actif', contenu: liasse } });
    verifier('un fileul n\'écrit PAS la collection de la liasse (famille R) : refus nommé (droit_refuse), la mère n\'en reçoit rien',
      await attendre(() => refus(f1, 'droit_refuse'), 15000) && (await compte('documentsFiscaux')) === 0, await compte('documentsFiscaux'));
    await dormir(1200);
    /* La mère rejoue, écrit la version, vide le contenu de la demande et écrit le verdict. */
    await admin('documentsFiscaux', 'doc-fiscal-liasse-2025-2026-04-30', { genre: 'liasse', exercice: 2025, dateEffet: '2026-04-30', source: 'Remise à la DGI', importeLe: '2026-11-18T09:00:00.000Z', importePar: 'Comptable Fictif', statut: 'actif', contenu: liasse });
    await admin('validationsDeposees', 'VDP-F1-2', { etat: 'appliquee', traitePar: 'Poste mère', resultatReference: 'doc-fiscal-liasse-2025-2026-04-30', contenu: {}, contenuVideLe: '2026-11-18T09:05:00.000Z' });
    verifier('la version écrite par la mère arrive aux DEUX fileuls ; le verdict revient avec sa référence ; le contenu de la demande, vidé, ne reste pas dupliqué',
      await attendre(async () => { const a = await chez(f1, 'documentsFiscaux', 'doc-fiscal-liasse-2025-2026-04-30'), b = await chez(f2, 'documentsFiscaux', 'doc-fiscal-liasse-2025-2026-04-30'), v = await chez(f1, 'validationsDeposees', 'VDP-F1-2'); return !!a && !!b && !!v && a.importePar === 'Comptable Fictif' && v.etat === 'appliquee' && v.resultatReference === 'doc-fiscal-liasse-2025-2026-04-30' && Object.keys(v.contenu || {}).length === 0; }, 30000));

    /* 5. Mère coupée puis relancée : la demande déposée pendant la coupure arrive, sans doublon. */
    await m.mere.tuer();
    await f2.ecrire({ type: 'creer', collection: 'validationsDeposees', fiche: 'VDP-F2-3', champs: { ...base, genre: 'liasse_importer', famille: 'documentsFiscaux', cible: 'classeur|2025|2026-04-30', libelle: 'Import du classeur 2025', documentGenre: 'classeur', exercice: 2025, dateDepot: '2026-04-30', source: 'Classeur de l’expert-comptable', contenu: { annee: 2025 } } });
    await m.mere.demarrer();
    verifier('mère relancée : la demande déposée pendant la coupure arrive à la mère et chez F1, une seule fois', await attendre(async () => (await compte('validationsDeposees')) === 3 && !!(await chez(f1, 'validationsDeposees', 'VDP-F2-3')), 25000), await compte('validationsDeposees'));
    await dormir(2500);
    verifier('aucun doublon après rejeu', (await compte('validationsDeposees')) === 3 && (await compte('documentsFiscaux')) === 1, { depots: await compte('validationsDeposees'), docs: await compte('documentsFiscaux') });

    /* 6. Rien vers un téléphone. */
    await dormir(1500);
    const vus = {};
    for (const c of ['validationsDeposees', 'documentsFiscaux', 'fichesAide']) vus[c] = (await mob.liste(c)).length;
    verifier('un téléphone ne reçoit ni les demandes, ni la liasse, ni les fiches d\'aide (donnée financière, RG-13)', Object.values(vus).every((n) => n === 0), vus);
    await m.fermer();
  },
});
