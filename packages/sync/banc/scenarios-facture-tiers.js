'use strict';
/* Scénario FTR1 (Direction de Baguidi, 17/11/2026, point 2 : « facture à une entreprise : impression, avoir, transmission MECeF, synchronisation ») :
   la FACTURE À UNE ENTREPRISE (`facturesTiers`) et son AVOIR (`avoirsTiers`) traversent les postes. Miroir de `sync_dart/lib/src/mere.dart` : famille A, mais l'ÉMISSION reste à la MÈRE, qui tient la
   numérotation (séries `caisse.factures-tiers`, `caisse.avoirs`) et le boîtier MECeF. Ce que le banc éprouve ICI, avec de vrais processus, c'est le PROTOCOLE :
   · un fileul n'écrit NI la pièce NI son avoir NI sa certification NI son cumul d'avoirs : refus nommé `emission_reservee_mere`, rien n'arrive à la mère ;
   · la pièce émise par la mère arrive aux DEUX fileuls ; sa certification (NIM, statut) et le cumul de ses avoirs, écrits par la mère, les rejoignent champ à champ ;
   · le fileul DÉPOSE une demande (`validationsDeposees`, genre `facture_tiers` : émission, avoir, transmission) : elle arrive à la mère ; le verdict que la mère écrit sur la même fiche revient au
     fileul auteur ET à l'autre poste ;
   · la mère coupée puis relancée : la demande déposée pendant la coupure arrive, sans doublon ;
   · jamais vers un téléphone : ni la pièce, ni l'avoir, ni la demande.
   Ce que le poste fait (contrôles du dépôt, application sous le rôle de l'auteur avec la matrice de la mère, son relevé et ses numéros, avoir par le moteur unique, transmission au circuit MECeF) est éprouvé
   par `apps/poste/test/facture_tiers_sync_test.dart` contre la vraie mère Dart. */
module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async FTR1() {
    titre('FTR-FTR1 · facture à une entreprise : émission réservée à la mère, pièce lue partout, certification et avoirs de la mère, demande d\'un fileul et verdict, mère coupée, rien vers un téléphone');
    const m = await monde({ relais: true });
    const f1 = await m.fileul('F1');
    const f2 = await m.fileul('F2');
    const compte = async (c) => (await m.mere.admin('GET', '/admin/compte?collection=' + c)).json.n;
    const refus = async (f, code) => (await f.etat()).a_traiter.some((x) => x.code === code);
    const admin = async (collection, fiche, champs) => (await m.mere.admin('POST', '/admin/referentiel', { collection, fiche, champs })).json;
    const chez = async (f, c, id) => { const l = (await f.liste(c)).find((x) => x.id === id); return l && l.data; };
    const chezMere = async (c, id) => { const r = (await m.mere.admin('GET', '/admin/fiche?collection=' + c + '&id=' + encodeURIComponent(id))).json; return r && !r.absente ? r.data : undefined; };
    const piece = { numero: 'FT-2031-00001', type: 'tiers_payeur', statut: 'actif', acheteurIfu: '1201555000123', acheteurNom: 'Entreprise Fictive SARL', montantTTC: 24000, aibTaux: 5, aibMontant: 1200, statutMecef: 'en_attente', piecesFilles: ['FP-1', 'FP-2'] };

    /* 1. L'émission reste à la mère : un fileul n'écrit ni la facture ni l'avoir. */
    await f1.ecrire({ type: 'creer', collection: 'facturesTiers', fiche: 'FTP00001', champs: piece });
    verifier('un fileul ne crée pas une facture à une entreprise : refus nommé (emission_reservee_mere), rien n\'arrive à la mère', await attendre(() => refus(f1, 'emission_reservee_mere'), 15000) && (await compte('facturesTiers')) === 0, await compte('facturesTiers'));
    await f2.ecrire({ type: 'creer', collection: 'avoirsTiers', fiche: 'AVT00001', champs: { reference: 'AV-2031-0001', factureId: 'FTP00001', montant: 24000 } });
    verifier('un fileul ne crée pas non plus l\'avoir d\'une facture à une entreprise', await attendre(() => refus(f2, 'emission_reservee_mere'), 15000) && (await compte('avoirsTiers')) === 0, await compte('avoirsTiers'));

    /* 2. La pièce émise par la mère est LUE partout. */
    await admin('facturesTiers', 'FTP00001', piece);
    verifier('la facture émise par la mère arrive aux DEUX fileuls, montant et acheteur intacts',
      await attendre(async () => { const a = await chez(f1, 'facturesTiers', 'FTP00001'), b = await chez(f2, 'facturesTiers', 'FTP00001'); return !!a && !!b && a.montantTTC === 24000 && b.acheteurNom === 'Entreprise Fictive SARL'; }, 20000));

    /* 3. Un poste ne réécrit pas la pièce : ni sa certification, ni son cumul d'avoirs, ni son montant. */
    await dormir(1200);
    await f1.ecrire({ type: 'modifier', collection: 'facturesTiers', fiche: 'FTP00001', champs: { statutMecef: 'valide', numeroMecef: 'FAUX-NIM-0001' }, vu: {} });
    verifier('un fileul ne certifie pas la pièce : refus nommé, la mère garde « en attente » sans numéro', await attendre(() => refus(f1, 'emission_reservee_mere'), 15000) && ((await chezMere('facturesTiers', 'FTP00001')) || {}).statutMecef === 'en_attente' && !((await chezMere('facturesTiers', 'FTP00001')) || {}).numeroMecef);
    await f2.ecrire({ type: 'modifier', collection: 'facturesTiers', fiche: 'FTP00001', champs: { montantAvoirs: 24000, montantTTC: 1 }, vu: {} });
    verifier('un fileul ne touche ni le montant ni le cumul des avoirs de la pièce', await attendre(async () => ((await chezMere('facturesTiers', 'FTP00001')) || {}).montantTTC === 24000 && !((await chezMere('facturesTiers', 'FTP00001')) || {}).montantAvoirs, 8000));

    /* 4. La certification et les avoirs écrits par la mère voyagent champ à champ. */
    await admin('facturesTiers', 'FTP00001', { statutMecef: 'valide', numeroMecef: 'CC300-000042', codeRetour: 'OK-200', dateTransmission: '2031-03-10T10:00:00Z' });
    verifier('la certification de la mère (NIM, statut) rejoint les deux fileuls ; le montant ne bouge pas',
      await attendre(async () => { const a = await chez(f1, 'facturesTiers', 'FTP00001'), b = await chez(f2, 'facturesTiers', 'FTP00001'); return !!a && !!b && a.statutMecef === 'valide' && b.numeroMecef === 'CC300-000042' && a.montantTTC === 24000; }, 20000));
    await admin('avoirsTiers', 'AVT00001', { reference: 'AV-2031-0001', factureId: 'FTP00001', factureNumero: 'FT-2031-00001', montant: 10000, type: 'avoir_tiers_payeur', statut: 'actif' });
    await admin('facturesTiers', 'FTP00001', { montantAvoirs: 10000, avoirIds: ['AVT00001'] });
    verifier('l\'avoir émis par la mère et le cumul que la pièce porte arrivent aux deux fileuls',
      await attendre(async () => !!(await chez(f1, 'avoirsTiers', 'AVT00001')) && ((await chez(f2, 'facturesTiers', 'FTP00001')) || {}).montantAvoirs === 10000, 20000));

    /* 5. Le fileul DÉPOSE une demande ; la mère écrit le verdict sur la même fiche, qui revient partout. */
    const depot = { genre: 'facture_tiers', famille: 'facture_tiers', action: 'emettre', cible: 'NSIA|mois|Souscripteur Fictif', libelle: 'Émission d’une facture à une entreprise', etat: 'deposee', demandeRole: 'comptable', demandePar: 'Agent Fileul', demandePoste: 'F1', demandeLe: '2031-03-10T09:00:00Z', charge: { compagnieCode: 'NSIA', periode: 'mois', souscripteur: 'Souscripteur Fictif', ifu: '1201555000123', nom: 'Entreprise Fictive SARL', situation: 'ifu_inactif_ou_absent' }, statut: 'actif' };
    await f1.ecrire({ type: 'creer', collection: 'validationsDeposees', fiche: 'VDP-F1-1', champs: depot });
    verifier('la demande d\'émission d\'un fileul arrive à la mère ET chez l\'autre fileul (le centre des validations la voit partout)',
      await attendre(async () => ((await chezMere('validationsDeposees', 'VDP-F1-1')) || {}).action === 'emettre' && !!(await chez(f2, 'validationsDeposees', 'VDP-F1-1')), 20000));
    await dormir(1200);
    await admin('validationsDeposees', 'VDP-F1-1', { etat: 'refusee', traitePar: 'Poste mère', traiteLe: '2031-03-10T09:05:00Z', resultatCode: 'FILLE_DEJA_FACTUREE', resultatMotif: 'Des factures patients de cette ligne sont déjà réclamées.', resultatGeste: 'Choisir une autre période.' });
    verifier('le verdict NOMMÉ de la mère revient au fileul auteur ET à l\'autre poste',
      await attendre(async () => { const a = await chez(f1, 'validationsDeposees', 'VDP-F1-1'), b = await chez(f2, 'validationsDeposees', 'VDP-F1-1'); return !!a && !!b && a.etat === 'refusee' && a.resultatCode === 'FILLE_DEJA_FACTUREE' && b.etat === 'refusee'; }, 20000));
    await f2.ecrire({ type: 'creer', collection: 'validationsDeposees', fiche: 'VDP-F2-1', champs: { ...depot, action: 'avoir', cible: 'FTP00001', demandePoste: 'F2', demandePar: 'Autre Agent', charge: { factureId: 'FTP00001', motif: 'Erreur de période' } } });
    await attendre(async () => !!(await chezMere('validationsDeposees', 'VDP-F2-1')), 20000);
    await admin('validationsDeposees', 'VDP-F2-1', { etat: 'appliquee', traitePar: 'Poste mère', resultatReference: 'AV-2031-0002' });
    verifier('une demande d\'avoir appliquée : la référence de l\'avoir écrite par la mère revient au fileul', await attendre(async () => ((await chez(f2, 'validationsDeposees', 'VDP-F2-1')) || {}).resultatReference === 'AV-2031-0002', 20000));

    /* 6. Mère coupée puis relancée : la demande déposée pendant la coupure arrive, sans doublon. */
    await m.mere.tuer();
    await f2.ecrire({ type: 'creer', collection: 'validationsDeposees', fiche: 'VDP-F2-2', champs: { ...depot, action: 'transmettre', cible: 'FTP00001', demandePoste: 'F2', demandePar: 'Autre Agent', charge: { factureId: 'FTP00001' } } });
    await m.mere.demarrer();
    verifier('mère relancée : la demande déposée pendant la coupure arrive à la mère et chez F1, une seule fois', await attendre(async () => (await compte('validationsDeposees')) === 3 && !!(await chez(f1, 'validationsDeposees', 'VDP-F2-2')), 25000), await compte('validationsDeposees'));
    await dormir(2500);
    verifier('aucun doublon après rejeu', (await compte('validationsDeposees')) === 3 && (await compte('facturesTiers')) === 1 && (await compte('avoirsTiers')) === 1, { depots: await compte('validationsDeposees'), factures: await compte('facturesTiers'), avoirs: await compte('avoirsTiers') });

    /* 7. Rien vers un téléphone. */
    const mob = await m.mobile('T1', { profil: 'soignant', fonction: 'infirmier' });
    await dormir(1500);
    const vus = {};
    for (const c of ['facturesTiers', 'avoirsTiers', 'validationsDeposees']) vus[c] = (await mob.liste(c)).length;
    verifier('un téléphone ne reçoit ni la facture à une entreprise, ni son avoir, ni la demande d\'un fileul (IFU et nom d\'entreprise, souscripteur : RG-13)', Object.values(vus).every((n) => n === 0), vus);
    await m.fermer();
  },
});
