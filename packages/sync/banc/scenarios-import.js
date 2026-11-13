'use strict';
/* Scénario IMP1 (lot IMP-C, décision de la Direction du 12/11/2026, « option c », repris du lot IMP-D de la clinique sœur) : la DEMANDE D'IMPORT d'un fileul à la mère.

   Un fileul qui importe un référentiel dont la mère seule est l'autorité l'écrit DIRECTEMENT chez lui (il le voit tout de suite, sous l'IDENTITÉ de la demande, « en attente de la mère ») ET
   dépose une demande vérifiée (`demandesImport`, famille A) ; la mère rejoue l'analyse sous le rôle de l'auteur, exige le MÊME résultat et reste la seule autorité : elle applique SOUS LES MÊMES
   IDENTIFIANTS (une fiche par code, jamais « provisoire + archivée ») ou refuse en nommant ; le verdict revient au fileul sur la même fiche ; sur refus le fileul RESTITUE (archivage RG-14).

   Scénario IMP2 (décision de la Direction du 13/11/2026, lot IMP-E de la clinique sœur repris) : le GRAND STOCK s'écrit chez le gestionnaire de stock (fileul). Même nature de preuve : le banc tient la
   place de la mère de référence (qui range `lots`, `mouvements` et `deltasCompteurs` comme la mère Dart) ; ce que le poste fait de ses fiches en attente (propres à lui, jamais publiées, valeur de
   départ, restitution par mouvements inverses) est éprouvé par `apps/poste/test/grand_stock_*_test.dart` (VRAIE mère Dart) et par `packages/domaine/test/demande_import_test.dart`. Ici : l'IDENTITÉ COMMUNE
   des fiches (une seule fiche par identifiant, jamais deux), les VARIATIONS ajoutées une fois, la demande qui voyage, le refus et la restitution partielle fusionnés champ à champ, la mère injoignable
   puis tuée, deux fileuls, le relais opaque, et RIEN vers un téléphone.

   Ce que le banc éprouve ICI, avec de vrais processus de synchronisation (la mère et les fileuls : de référence en Node, ou Dart avec SIGH_MERE / SIGH_FILEUL / SIGH_MOBILE=dart) : le PROTOCOLE
   — la fiche voyage dans les deux sens, le relais ne voit que du chiffré, un téléphone ne la dépose ni ne la reçoit, et un fileul falsifié ne peut ni se délivrer un verdict, ni remettre une demande
   en attente, ni écrire le référentiel directement. Les processus de synchronisation ne tiennent pas de magasin métier : le poste (fileul ou mère) est joué par l'OUTIL du domaine
   (`packages/domaine/tool/import_banc.dart`) sur des magasins en mémoire, avec LA règle du domaine et la matrice de production — rien n'est réécrit ici. La preuve que le poste mère réel traite
   une demande SANS appel manuel est dans `apps/poste/test/demandes_import_sync_test.dart` (vraie mère, vrai moteur de fileul, vrais ponts). */
const path = require('node:path');
const { spawn } = require('node:child_process');
const { dechiffrer } = require('./crypto');

const DOMAINE = path.join(__dirname, '..', '..', 'domaine');
const SECRET = 'DESIGNATION-SECRETE-IMP1-Zébulon';
const entropie = (b) => { const c = new Array(256).fill(0); for (const x of b) c[x]++; return -c.reduce((a, n) => (n ? a + (n / b.length) * Math.log2(n / b.length) : a), 0); };

/* Le poste du banc : la règle du domaine, rejouée dans un processus à part. */
function poste(commande, entree) {
  /* Asynchrone : un processus qui BLOQUE la boucle d'événements du banc pendant plusieurs secondes casse les connexions ouvertes vers la mère et les fileuls (« fetch failed »). */
  return new Promise((ok, ko) => {
    const p = spawn(process.env.DART || 'dart', ['run', 'tool/import_banc.dart', commande], { cwd: DOMAINE, stdio: ['pipe', 'pipe', 'pipe'] });
    let sortie = '', erreur = '';
    p.stdout.on('data', (d) => { sortie += d; }); p.stderr.on('data', (d) => { erreur += d; });
    p.once('error', ko);
    p.once('close', (code) => {
      if (code !== 0) return ko(new Error(`outil du domaine (${commande}) : ${erreur || sortie}`));
      const ligne = sortie.split('\n').reverse().find((l) => l.startsWith('{'));
      try { ok(JSON.parse(ligne)); } catch (e) { ko(new Error(`outil du domaine (${commande}) : sortie illisible : ${sortie}`)); }
    });
    p.stdin.end(JSON.stringify(entree) + '\n');
  });
}

const ENTETE = ['Code article', 'Désignation', 'Catégorie', 'Unité', 'Prix d’achat unitaire', 'Prix de vente unitaire', 'Seuil d’alerte', 'Emplacement', 'Code fournisseur'];
const ligne = (code, designation) => [code, designation, 'Médicaments', 'Boîte', 350, 350, '', '', ''];
const actives = (magasin, col) => (magasin[col] || []).filter((f) => f.statut !== 'archive');

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async IMP1() {
    titre('IMPORT-IMP1 · le fileul écrit chez lui ET dépose une demande ; la mère seule autorité (applique, refuse nommé) ; jeu restreint jamais demandé ; fileul falsifié sans effet');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1');
    const lecteur = await m.fileul('F2'); /* SECOND fileul : il reçoit la configuration, JAMAIS la demande d'un autre poste (décision du 13/11/2026) */
    const compte = async () => (await m.mere.admin('GET', '/admin/compte?collection=demandesImport')).json.n;
    const verdict = async (id, champs) => (await m.mere.admin('POST', '/admin/referentiel', { collection: 'demandesImport', fiche: id, champs })).json;
    /* Ce que la mère détient : lu à SA console (le journal des demandes n'est plus lu par un autre fileul, décision du 13/11/2026). */
    const chezLaMere = async (id) => { const r = (await m.mere.admin('GET', '/admin/fiche?collection=demandesImport&id=' + encodeURIComponent(id))).json; return r && !r.absente ? r.data : undefined; };
    const chezLeFileul = async (id) => { const l = (await f1.liste('demandesImport')).find((x) => x.id === id); return l && l.data; };
    const refus = async (code) => (await f1.etat()).a_traiter.some((x) => x.code === code);

    let magF = { produits: [], lotsImportation: [], fournisseurs: [] }; /* le magasin du fileul */
    let magM = { produits: [], lotsImportation: [], patients: [] }; /* le magasin de la mère */

    /* 1. L'ÉCRITURE DIRECTE : le fileul voit son import tout de suite, sous l'identité de la demande, « en attente de la mère » ; la demande part vérifiée avec ce que la mère doit reproduire. */
    const o1 = await poste('fileul', { role: 'stock', par: 'GESTIONNAIRE', poste: 'F1', jeu: 'produits', lignes: [ENTETE, ligne('IMPA', SECRET), ligne('IMPB', 'AMOXICILLINE BANC')], magasin: magF, idDemande: 'DIM-F1-1' });
    magF = o1.magasin;
    const locales = actives(magF, 'produits');
    verifier('chez le fileul : l\'import est visible TOUT DE SUITE (2 fiches), « en attente de la mère », sous l\'identité de la demande (jamais l\'étiquette du poste)', o1.ok && locales.length === 2 && locales.every((f) => f.enAttenteMere === 'DIM-F1-1' && f.serieDemande === 'DIM-F1-1' && /^PRO-DIM-F1-1-\d$/.test(f.id)), o1);
    verifier('la demande part vérifiée : en attente, rôle et auteur de l\'écrivant, lot local nommé, lignes jointes pour que la mère rejoue, lignes écrites que la mère doit reproduire', o1.demande.etat === 'en_attente' && o1.demande.demandeRole === 'stock' && o1.demande.demandePar === 'GESTIONNAIRE' && !!o1.demande.lotLocal && !!o1.demande.lotLocalId && o1.demande.ecritureDirecte === true && o1.demande.serieIdentifiants === 'DIM-F1-1' && o1.demande.rangsEcrits.length === 2 && o1.demande.lignes.length === 3, o1.demande);

    /* 2. LE DÉPÔT : famille A, la mère l'accepte avec ses lignes, et un second poste la reçoit (le journal de la mère). */
    const r = await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1-1', champs: o1.demande });
    verifier('la mère accepte la demande d\'un fileul (famille A)', r.fiche === 'DIM-F1-1' && await attendre(async () => (await compte()) === 1, 15000), r);
    verifier('la mère la détient avec ses lignes (elle doit pouvoir rejouer) ET sa série d\'identifiants', await attendre(async () => { const d = await chezLaMere('DIM-F1-1'); return !!d && d.lignes.length === 3 && d.etat === 'en_attente' && d.serieIdentifiants === 'DIM-F1-1'; }, 15000));

    /* 2 bis. DÉCISION DU 13/11/2026 : LE JOURNAL DES DEMANDES EST RÉSERVÉ à la mère et au poste auteur. Les lignes voyagent en clair jusqu'au verdict : un SECOND fileul ne reçoit rien, ne modifie rien. */
    await dormir(900);
    verifier('un SECOND fileul ne reçoit JAMAIS la demande du premier (ni ses lignes, ni son état), alors que la mère la détient', (await lecteur.liste('demandesImport')).length === 0 && (await compte()) >= 1, (await lecteur.liste('demandesImport')).length);
    verifier('le fileul auteur, lui, relit sa propre demande', !!(await chezLeFileul('DIM-F1-1')));
    await lecteur.ecrire({ type: 'modifier', collection: 'demandesImport', fiche: 'DIM-F1-1', champs: { etat: 'retiree', lignes: [] } });
    verifier('le second fileul ne peut pas modifier la demande d\'un autre poste : refus nommé (demande_d_un_autre_poste), la demande reste intacte à la mère', await attendre(async () => (await lecteur.etat()).a_traiter.some((x) => x.code === 'demande_d_un_autre_poste'), 15000) && (await chezLaMere('DIM-F1-1')).etat === 'en_attente' && (await chezLaMere('DIM-F1-1')).lignes.length === 3, (await lecteur.etat()).a_traiter);

    /* 3. LA MÈRE, SEULE AUTORITÉ : elle rejoue sous le rôle de l'auteur, exige le même résultat et applique SOUS LES MÊMES IDENTIFIANTS ; son verdict revient, les lignes sont effacées. */
    const demande1 = await chezLaMere('DIM-F1-1');
    const o2 = await poste('mere', { demande: { id: 'DIM-F1-1', ...demande1 }, magasin: magM });
    magM = o2.magasin;
    const idsFileul = locales.map((f) => f.id).sort();
    verifier('la mère applique : deux fiches à elle, lot à elle, au nom de l\'auteur, SANS marquage « en attente »', o2.appliquee && actives(magM, 'produits').length === 2 && actives(magM, 'produits').every((f) => f.lotImport === o2.lot && f.validePar === 'GESTIONNAIRE' && f.enAttenteMere === undefined), o2);
    verifier('les fiches de la mère portent EXACTEMENT les identifiants de celles du fileul : une identité de ligne, jamais deux versions d\'un même code', JSON.stringify(actives(magM, 'produits').map((f) => f.id).sort()) === JSON.stringify(idsFileul), [actives(magM, 'produits').map((f) => f.id), idsFileul]);
    verifier('la mère écrit son verdict sur la fiche', (await verdict('DIM-F1-1', o2.champs)).statut === 'acceptee');
    for (const f of actives(magM, 'produits')) await m.mere.admin('POST', '/admin/referentiel', { collection: 'produits', fiche: f.id, champs: f });
    verifier('le fileul reçoit le verdict nommé sur SA demande, lignes effacées, auteur et jeu conservés', await attendre(async () => { const d = await chezLeFileul('DIM-F1-1'); return !!d && d.etat === 'appliquee' && d.lignes.length === 0 && d.traitePar === 'Mère' && d.demandePar === 'GESTIONNAIRE' && d.jeu === 'produits' && d.ecritureDirecte === true; }, 15000));

    /* 4. LE FILEUL REÇOIT LA COPIE DE LA MÈRE SOUS LES MÊMES IDENTIFIANTS : elle REMPLACE la sienne, aucun doublon ; le marquage tombe ; rien n'est archivé. */
    verifier('la copie de la mère descend au fileul par la configuration diffusée, sous les MÊMES identifiants : aucun doublon', await attendre(async () => { const ids = (await f1.liste('produits')).filter((x) => x.data.lotImport === o2.lot).map((x) => x.id).sort(); return JSON.stringify(ids) === JSON.stringify(idsFileul); }, 15000), (await f1.liste('produits')).map((x) => x.id));
    const demandeRendue = { id: 'DIM-F1-1', ...(await chezLeFileul('DIM-F1-1')) };
    const apres = await poste('suite', { demande: demandeRendue, magasin: magF });
    magF = apres.magasin;
    verifier('confirmée : le fileul LÈVE le marquage « en attente de la mère » (2 fiches), rien n\'est archivé, une fiche par code', apres.suite === 'leverLeMarquage' && apres.marques === 2 && actives(magF, 'produits').length === 2 && magF.produits.length === 2 && actives(magF, 'produits').every((f) => f.enAttenteMere === undefined), apres);
    const dejaLeve = await poste('suite', { demande: { ...demandeRendue, marquageLeve: true }, magasin: magF });
    verifier('rejouée une fois le marquage levé, la suite ne fait rien (idempotente)', dejaLeve.suite === 'aucune');

    /* 5. REFUS NOMMÉ : un autre poste a créé la même fiche à la mère entre-temps. Le fileul a écrit chez lui ; la mère rejoue, refuse en nommant, n'écrit rien ; le fileul RESTITUE son écriture. */
    magM.produits.unshift({ id: 'PRD-AILLEURS', code: 'IMPC', designation: 'créé par un autre poste', statut: 'actif' });
    const o3 = await poste('fileul', { role: 'stock', par: 'GESTIONNAIRE', poste: 'F1', jeu: 'produits', lignes: [ENTETE, ligne('IMPC', 'ARTICLE EN DOUBLE')], magasin: magF, idDemande: 'DIM-F1-2' });
    magF = o3.magasin;
    await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1-2', champs: o3.demande });
    await attendre(async () => (await compte()) === 2 && !!(await chezLaMere('DIM-F1-2')), 15000);
    const avantM = JSON.stringify(magM.produits);
    const o4 = await poste('mere', { demande: { id: 'DIM-F1-2', ...(await chezLaMere('DIM-F1-2')) }, magasin: magM });
    magM = o4.magasin;
    await verdict('DIM-F1-2', o4.champs);
    verifier('la mère REFUSE en nommant (DOUBLON_MAGASIN, rejoué à la mère), n\'écrit rien, consigne le fichier à son historique', !o4.appliquee && o4.code === 'DOUBLON_MAGASIN' && /rejoué à la mère/.test(o4.motif) && !!o4.geste && JSON.stringify(magM.produits) === avantM && !!o4.lot, o4);
    verifier('le refus nommé revient au fileul (code, motif, geste)', await attendre(async () => { const d = await chezLeFileul('DIM-F1-2'); return !!d && d.etat === 'refusee' && d.resultatCode === 'DOUBLON_MAGASIN' && !!d.resultatGeste; }, 15000));
    const o5 = await poste('suite', { demande: { id: 'DIM-F1-2', ...(await chezLeFileul('DIM-F1-2')) }, magasin: magF });
    magF = o5.magasin;
    const restituee = magF.produits.find((f) => f.code === 'IMPC');
    verifier('RESTITUTION : l\'écriture du fileul est ARCHIVÉE avec son motif (jamais supprimée, RG-14), le lot passe « restitué »', o5.suite === 'restituer' && o5.ok && o5.restitution === 'faite' && o5.archives === 1 && restituee.statut === 'archive' && /refusé par la mère/.test(restituee._motifArchivage) && magF.lotsImportation.some((l) => l.id === o3.demande.lotLocalId && l.etat === 'restitue'), o5);
    await f1.ecrire({ type: 'modifier', collection: 'demandesImport', fiche: 'DIM-F1-2', champs: { restitution: o5.restitution, restitutionLe: '2026-11-12', restitutionArchives: o5.archives, restitutionGardees: [] } });
    verifier('la restitution du fileul s\'ajoute au refus de la mère sur la MÊME fiche : la mère garde le verdict ET la restitution (champ à champ)', await attendre(async () => { const d = await chezLaMere('DIM-F1-2'); return !!d && d.etat === 'refusee' && d.resultatCode === 'DOUBLON_MAGASIN' && d.restitution === 'faite' && d.restitutionArchives === 1; }, 15000));

    /* 5 bis. UNE PIÈCE ÉMISE NE SE RÉÉCRIT JAMAIS : une commande s'appuie sur l'une des fiches refusées, elle RESTE, marquée « refusée par la mère » ; le verdict dit « restitution partielle ». */
    magF.commandes = [{ id: 'CMD-1', fournisseurCode: 'SOBAPS', statut: 'actif' }];
    const o3b = await poste('fileul', { role: 'comptable', par: 'COMPTABLE', poste: 'F1', jeu: 'fournisseurs', lignes: [['Code fournisseur', 'Raison sociale'], ['SOBAPS', 'EXISTE DEJA'], ['NSIA', 'AUTRE']], magasin: magF, idDemande: 'DIM-F1-4' });
    if (o3b.ok) {
      magF = o3b.magasin;
      const refusP = { ...o3b.demande, id: 'DIM-F1-4', etat: 'refusee', resultatCode: 'DOUBLON_MAGASIN', resultatMotif: 'une fiche équivalente est déjà tenue' };
      const o5b = await poste('suite', { demande: refusP, magasin: magF });
      magF = o5b.magasin;
      verifier('une pièce émise s\'appuie sur une fiche refusée : elle est GARDÉE (marquée), l\'autre restituée, restitution PARTIELLE', o5b.restitution === 'partielle' && o5b.gardees === 1 && o5b.archives === 1 && actives(magF, 'fournisseurs').some((f) => /DOUBLON_MAGASIN/.test(f.refuseeParMere || '')), o5b);
    }

    /* 5 ter. LE FILEUL RETIRE SA DEMANDE avant la réponse de la mère : elle passe à « retirée », lignes effacées ; elle ne se retire plus après un verdict. */
    const o3c = await poste('fileul', { role: 'stock', par: 'GESTIONNAIRE', poste: 'F1', jeu: 'produits', lignes: [ENTETE, ligne('IMPR', 'ARTICLE RETIRE')], magasin: magF, idDemande: 'DIM-F1-5' });
    magF = o3c.magasin;
    await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1-5', champs: o3c.demande });
    await attendre(async () => !!(await chezLaMere('DIM-F1-5')), 45000);
    await f1.ecrire({ type: 'modifier', collection: 'demandesImport', fiche: 'DIM-F1-5', champs: { etat: 'retiree', retireePar: 'GESTIONNAIRE', retireeLe: '2026-11-12', lignes: [] } });
    verifier('la mère voit la demande retirée (elle ne l\'applique plus), sans ses lignes', await attendre(async () => { const d = await chezLaMere('DIM-F1-5'); return !!d && d.etat === 'retiree' && d.lignes.length === 0; }, 45000));
    const n1 = (await f1.etat()).a_traiter.length;
    await f1.ecrire({ type: 'modifier', collection: 'demandesImport', fiche: 'DIM-F1-1', champs: { etat: 'retiree' } });
    verifier('retirer une demande DÉJÀ jugée est refusé, nommé : un verdict ne se retire pas', await attendre(async () => (await f1.etat()).a_traiter.length > n1, 15000) && (await chezLaMere('DIM-F1-1')).etat === 'appliquee');

    /* 6. UN JEU RESTREINT NE PASSE JAMAIS PAR UNE DEMANDE : le fileul ne dépose rien ; et une demande FORGÉE pour ce jeu est refusée par la mère en le nommant, même sous un rôle qui détient tout. */
    for (const jeu of ['patients', 'personnel']) {
      const o = await poste('fileul', { role: 'admin', par: 'ADMIN', poste: 'F1', jeu, lignes: [['x']], magasin: magF, idDemande: 'DIM-R-' + jeu });
      verifier(`fileul, jeu restreint « ${jeu} » : aucune demande n'est composée (JEU_NON_DEMANDABLE)`, !o.ok && o.refus.code === 'JEU_NON_DEMANDABLE' && !o.demande, o);
    }
    const forgee = { etat: 'en_attente', jeu: 'patients', jeuLibelle: 'patients', fichier: 'p.xlsx', demandePar: 'FAUX', demandeRole: 'admin', demandePoste: 'F1', demandeLe: '2026-11-12', lignes: [['Nom'], ['SECRET']], nbLignes: 1, aEcrire: 1 };
    await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1-FORGEE', champs: forgee });
    await attendre(async () => !!(await chezLaMere('DIM-F1-FORGEE')), 15000);
    const o6 = await poste('mere', { demande: { id: 'DIM-F1-FORGEE', ...(await chezLaMere('DIM-F1-FORGEE')) }, magasin: magM });
    verifier('demande forgée pour un jeu restreint : la mère refuse (JEU_RESTREINT), rien n\'est écrit, même sous le rôle admin', !o6.appliquee && o6.code === 'JEU_RESTREINT' && (o6.magasin.patients || []).length === 0, o6);

    /* 7. AUCUN CONTOURNEMENT PAR UN FILEUL FALSIFIÉ. */
    const n0 = (await f1.etat()).a_traiter.length;
    await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1-VERDICT', champs: { ...forgee, jeu: 'produits', etat: 'appliquee', resultatCode: '', traitePar: 'Mère' } });
    verifier('un fileul qui dépose une demande DÉJÀ « appliquée » avec un verdict est refusé, nommé', await attendre(() => refus('verdict_reserve_a_la_mere'), 15000));
    await f1.ecrire({ type: 'modifier', collection: 'demandesImport', fiche: 'DIM-F1-1', champs: { etat: 'en_attente' } });
    await attendre(async () => (await f1.etat()).a_traiter.filter((x) => x.code === 'verdict_reserve_a_la_mere').length >= 2, 15000);
    verifier('remettre en attente une demande traitée (pour la faire rejouer) est refusé', (await f1.etat()).a_traiter.filter((x) => x.code === 'verdict_reserve_a_la_mere').length >= 2, (await f1.etat()).a_traiter);
    await f1.ecrire({ type: 'creer', collection: 'produits', fiche: 'PRD-FAUX', champs: { code: 'FAUX', designation: 'écrit sans passer par la mère' } });
    verifier('écrire directement le référentiel (famille R) est refusé : droit_refuse', await attendre(() => refus('droit_refuse'), 15000));
    verifier('à la mère : la demande traitée garde son verdict, aucune fiche forgée n\'existe, la demande « déjà appliquée » n\'a pas été créée',
      (await chezLaMere('DIM-F1-1')).etat === 'appliquee' && !(await lecteur.liste('produits')).some((x) => x.id === 'PRD-FAUX') && !(await chezLaMere('DIM-F1-VERDICT')) && (await f1.etat()).a_traiter.length > n0);
    const forgeeRole = { ...forgee, jeu: 'produits', jeuLibelle: 'produits', demandePar: 'FAUX COMPTABLE', demandeRole: 'medecin', lignes: [ENTETE, ligne('IMPD', 'ECRIT SOUS UN AUTRE ROLE')] };
    const o7 = await poste('mere', { demande: { id: 'DIM-F1-ROLE', ...forgeeRole }, magasin: magM });
    verifier('un rôle déclaré sans le droit d\'importer (médecin) : la mère REJOUE avec SA matrice et refuse (DROIT_IMPORT_REFUSE), rien n\'est écrit', !o7.appliquee && o7.code === 'DROIT_IMPORT_REFUSE' && !actives(o7.magasin, 'produits').some((f) => f.code === 'IMPD'), o7);
    const o8 = await poste('mere', { demande: { id: 'DIM-F1-GROS', ...forgeeRole, demandeRole: 'stock', lignes: [ENTETE, ligne('IMPE', 'X'.repeat(300000))] }, magasin: magM, octetsMax: 10 * 1024 });
    verifier('des lignes démesurées (au-delà de la borne du jeu) sont refusées avant tout rejeu (FICHIER_TROP_GROS)', !o8.appliquee && o8.code === 'FICHIER_TROP_GROS', o8.code);
    const o9 = await poste('mere', { demande: { id: 'DIM-F1-1', ...(await chezLeFileul('DIM-F1-1')) }, magasin: magM });
    verifier('un verdict n\'est jamais écrit deux fois : une demande déjà traitée ne se rejoue pas (DEMANDE_DEJA_TRAITEE)', !o9.appliquee && o9.code === 'DEMANDE_DEJA_TRAITEE', o9);

    /* 8. LE RELAIS NE VOIT QUE DU CHIFFRÉ : on décode chaque enveloppe, on cherche la désignation du fichier dans les octets, on mesure l'entropie. */
    await attendre(async () => { const e = (await m.mere.admin('GET', '/admin/etat')).json; return e.rep_seq === e.seq_max; }, 15000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const journal = brut.lignes.filter((l) => l.dir === 'journal');
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = journal.map((l) => Buffer.from(l.ct, 'base64'));
    verifier('le relais détient le journal de la mère en enveloppes', journal.length >= 1, journal.length);
    verifier('ni la désignation du fichier, ni le nom de la collection, ni le code du verdict ne sont lisibles au relais, même après décodage des octets',
      !/Zébulon|DESIGNATION-SECRETE|demandesImport|DOUBLON_MAGASIN/.test(tout) && octets.every((b) => !/Z\xc3\xa9bulon|DESIGNATION-SECRETE|demandesImport|DOUBLON_MAGASIN/.test(b.toString('latin1'))), tout.length);
    const gros = octets.filter((b) => b.length >= 250);
    verifier('chaque enveloppe porteuse a l\'entropie d\'un chiffrement (> 7 bits/octet)', gros.length >= 1 && gros.every((b) => entropie(b) > 7.0), octets.map((b) => [b.length, +entropie(b).toFixed(2)]));
    const claires = journal.map((l) => dechiffrer(cleClinique, l)).flatMap((c) => c.ops || []);
    verifier('avec la clé de clinique (que le relais n\'a pas), l\'enveloppe contient bien la demande et ses lignes : l\'opacité ne vient pas d\'un contenu vide',
      claires.some((o) => o.collection === 'demandesImport' && JSON.stringify(o.champs || {}).includes(SECRET)), claires.length);

    /* 9. UN TÉLÉPHONE NE LA DÉPOSE PAS (liste blanche du profil) ET NE LA REÇOIT PAS. */
    const mob = await m.mobile('M1', { profil: 'soignant' });
    await mob.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-M1-1', champs: { ...forgee, jeu: 'produits' } });
    verifier('le téléphone qui tente de déposer une demande d\'import est refusé, nommé (droit_refuse)', await attendre(async () => (await mob.etat()).a_traiter.some((x) => x.code === 'droit_refuse'), 15000));
    await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1-3', champs: { ...forgee, jeu: 'produits', lignes: [ENTETE, ligne('IMPF', 'APRES APPAIRAGE')] } });
    await attendre(async () => !!(await chezLaMere('DIM-F1-3')), 15000);
    await dormir(900);
    verifier('le téléphone ne reçoit AUCUNE demande d\'import (ni lignes, ni verdict)', (await mob.liste('demandesImport')).length === 0, (await mob.liste('demandesImport')).length);
    await m.fermer();
  },
  async IMP2() {
    titre('IMPORT-IMP2 · le Grand Stock chez le fileul : identité commune (une fiche par identifiant), variations ajoutées une fois, demande, refus partiel, mère coupée puis tuée, deux fileuls, relais opaque, rien vers un téléphone');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const f1 = await m.fileul('F1');
    const f2 = await m.fileul('F2');
    const etatMere = () => m.mere.admin('GET', '/admin/etat').then((r) => r.json);
    const compte = (col) => m.mere.admin('GET', '/admin/compte?collection=' + col).then((r) => r.json.n);
    const refus = async (f, code) => (await f.etat()).a_traiter.some((x) => x.code === code);
    const STOCK_SECRET = 'ARTICLE-SECRET-IMP2-Quinquina';
    const ligneGS = [['Code article', 'Désignation', 'Catégorie', 'Unité', 'Quantité', 'N° de lot', 'Date de péremption'], ['MED1', STOCK_SECRET, 'Médicaments', 'Boîte', 100, 'L1', '2028-06-30'], ['MED1', STOCK_SECRET, 'Médicaments', 'Boîte', 50, 'L2', '2029-01-31']];
    const demande = (serie, extra) => ({
      etat: 'en_attente', jeu: 'grand-stock', jeuLibelle: 'Importation Grand Stock', fichier: 'inventaire.xlsx', demandePar: 'GESTIONNAIRE', demandeRole: 'stock', demandeLe: '2026-11-13',
      lignes: ligneGS, nbLignes: 2, aEcrire: 2,
      ecritureDirecte: true, serieIdentifiants: serie, lotLocal: 'IMP-2026-001', lotLocalId: 'LOT-' + serie + '-1', rangsEcrits: [2, 3], ...extra,
    });
    /* Les fiches d'une demande portent une identité déterministe `<COL>-<demande>-<rang>`, sa série et, pour un compteur, sa valeur de DÉPART (jamais le compteur lui-même : il voyage par ses variations). */
    const lot = (serie, rang, q) => ({ produitId: 'PRO-' + serie + '-1', numeroLot: 'L' + rang, serieDemande: serie, departCompteurs: { quantiteRestante: q }, statut: 'actif', lotImport: 'IMP-MERE-' + serie });
    const mouvement = (serie, rang, q) => ({ produitId: 'PRO-' + serie + '-1', type: 'entree', quantite: q, serieDemande: serie, reference: 'M00000' + rang, statut: 'actif' });

    /* 1. LE CATALOGUE NE S'ÉCRIT QUE PAR LA MÈRE : même une fiche née d'une demande est refusée au fileul (famille R) ; ses lots et mouvements, fiches descriptives, sont acceptés. */
    await f1.ecrire({ type: 'creer', collection: 'produits', fiche: 'PRO-DIMG1-1', champs: { code: 'MED1', serieDemande: 'DIMG1', departCompteurs: { stockGros: 150 } } });
    verifier('le catalogue des produits n\'est JAMAIS accepté d\'un fileul, même une fiche née d\'une demande : refus nommé (droit_refuse), la mère reste l\'autorité', await attendre(() => refus(f1, 'droit_refuse'), 15000), (await f1.etat()).a_traiter);
    verifier('la mère ne détient aucun produit du fileul', (await compte('produits')) === 0);

    /* 2. LA DEMANDE voyage avec ce que la mère doit reproduire ; la mère applique : MÊMES identifiants, UNE fiche par identifiant (pas de lot doublé) */
    const rd = await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1G-1', champs: demande('DIMG1') });
    verifier('la mère accepte la demande du Grand Stock (famille A) avec sa série et les lignes écrites', rd.fiche === 'DIM-F1G-1' && await attendre(async () => (await compte('demandesImport')) === 1, 15000), rd);
    for (const [i, q] of [100, 50].entries()) {
      const rl = await m.mere.admin('POST', '/admin/referentiel', { collection: 'lots', fiche: 'LOT-DIMG1-' + (i + 1), champs: lot('DIMG1', i + 1, q) }).then((x) => x.json);
      const rm = await m.mere.admin('POST', '/admin/referentiel', { collection: 'mouvements', fiche: 'MOU-DIMG1-' + (i + 1), champs: mouvement('DIMG1', i + 1, q) }).then((x) => x.json);
      verifier('la mère écrit le lot et le mouvement ' + (i + 1) + ' de la demande sous leurs identifiants communs', rl.statut === 'acceptee' && rm.statut === 'acceptee', [rl, rm]);
    }
    /* Le fileul PUBLIE à son tour (la mère a confirmé : sa fiche cesse d'être propre au poste) la fiche qu'il tient sous le MÊME identifiant : un seul lot, jamais deux. */
    await f1.ecrire({ type: 'creer', collection: 'lots', fiche: 'LOT-DIMG1-1', champs: lot('DIMG1', 1, 100) });
    verifier('la même identité écrite une seconde fois est refusée (fiche_existe) : un lot n\'existe jamais en double', await attendre(() => refus(f1, 'fiche_existe'), 15000), (await f1.etat()).a_traiter);
    verifier('la mère tient exactement DEUX lots et DEUX mouvements pour la demande (pas quatre)', (await compte('lots')) === 2 && (await compte('mouvements')) === 2, [await compte('lots'), await compte('mouvements')]);
    /* ... et corrige un champ d'une fiche tenue : champ à champ, jamais une seconde fiche. */
    await f1.ecrire({ type: 'modifier', collection: 'lots', fiche: 'LOT-DIMG1-1', champs: { emplacement: 'Rayon A' } });
    verifier('un champ ajouté par le fileul à une fiche que la mère détient se fusionne (champ à champ), toujours deux lots', await attendre(async () => {
      const l = (await f2.liste('lots')).find((x) => x.id === 'LOT-DIMG1-1');
      return !!l && l.data.emplacement === 'Rayon A' && l.data.lotImport === 'IMP-MERE-DIMG1' && (await f2.liste('lots')).length === 2;
    }, 15000), (await f2.liste('lots')).map((x) => x.id));
    const verdict = { etat: 'appliquee', resultatCode: '', resultatLot: 'IMP-MERE-DIMG1', resultatEcrits: 7, traitePar: 'Mère', traiteLe: '2026-11-13', lignes: [] };
    verifier('la mère confirme sur la MÊME fiche', (await m.mere.admin('POST', '/admin/referentiel', { collection: 'demandesImport', fiche: 'DIM-F1G-1', champs: verdict }).then((x) => x.json)).statut === 'acceptee');

    /* 3. LES VARIATIONS s'ajoutent UNE fois : une fiche par variation, jamais modifiée ; la même variation rejouée est refusée, elle ne compte pas deux fois */
    await f1.ecrire({ type: 'creer', collection: 'deltasCompteurs', fiche: 'F1~1~0', champs: { cle: 'lots/LOT-DIMG1-1/quantiteRestante', delta: -10, poste: 'F1' } });
    verifier('la variation de sortie du fileul est acceptée par la mère (une fiche ajoutée)', await attendre(async () => (await compte('deltasCompteurs')) === 1, 15000));
    await f1.ecrire({ type: 'creer', collection: 'deltasCompteurs', fiche: 'F1~1~0', champs: { cle: 'lots/LOT-DIMG1-1/quantiteRestante', delta: -10, poste: 'F1' } });
    verifier('la même variation rejouée est refusée (fiche_existe) : une sortie ne se compte jamais deux fois', await attendre(async () => (await f1.etat()).a_traiter.filter((x) => x.code === 'fiche_existe').length >= 2, 15000), (await f1.etat()).a_traiter);
    verifier('la mère ne détient qu\'UNE variation', (await compte('deltasCompteurs')) === 1);

    /* 4. DEUX FILEULS IMPORTENT LE MÊME INVENTAIRE : la mère refuse la seconde demande en nommant ; le second fileul ajoute SA restitution PARTIELLE (un article déjà sorti reste) sur la même fiche */
    await f2.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F2G-1', champs: demande('DIMG2', { demandePar: 'GESTIONNAIRE DEUX', lotLocalId: 'LOT-DIMG2-1' }) });
    verifier('la seconde demande (même inventaire) arrive à la mère', await attendre(async () => (await compte('demandesImport')) === 2, 15000));
    const verdict2 = { etat: 'refusee', resultatCode: 'DOUBLON_MAGASIN', resultatMotif: 'rejoué à la mère, le fichier est refusé (ligne 2, Code article) : l’article « MED1 » existe déjà dans le référentiel', resultatGeste: 'Retirez la ligne du fichier.', traitePar: 'Mère', traiteLe: '2026-11-13', lignes: [] };
    verifier('la mère refuse la seconde demande en nommant le code', (await m.mere.admin('POST', '/admin/referentiel', { collection: 'demandesImport', fiche: 'DIM-F2G-1', champs: verdict2 }).then((x) => x.json)).statut === 'acceptee');
    verifier('le second fileul reçoit le refus nommé (code, motif, geste)', await attendre(async () => {
      const l = (await f2.liste('demandesImport')).find((x) => x.id === 'DIM-F2G-1');
      return !!l && l.data.etat === 'refusee' && l.data.resultatCode === 'DOUBLON_MAGASIN' && /rejoué à la mère/.test(l.data.resultatMotif) && !!l.data.resultatGeste;
    }, 15000));
    await f2.ecrire({ type: 'modifier', collection: 'demandesImport', fiche: 'DIM-F2G-1', champs: { restitution: 'partielle', restitutionLe: '2026-11-13', restitutionArchives: 1, restitutionGardees: [{ collection: 'produits', id: 'PRO-DIMG2-1', code: 'STOCK_DEJA_SORTI', motif: 'une pièce émise ne se réécrit jamais' }] } });
    verifier('la restitution PARTIELLE du fileul s\'ajoute au refus de la mère sur la MÊME fiche : la mère garde le verdict ET la liste des fiches gardées',
      await attendre(async () => {
        const r = (await m.mere.admin('GET', '/admin/fiche?collection=demandesImport&id=DIM-F2G-1')).json; const d = r && !r.absente ? r.data : null;
        return !!d && d.etat === 'refusee' && d.resultatCode === 'DOUBLON_MAGASIN' && d.restitution === 'partielle' && d.restitutionGardees.length === 1 && d.restitutionGardees[0].code === 'STOCK_DEJA_SORTI';
      }, 15000), (await m.mere.admin('GET', '/admin/fiche?collection=demandesImport&id=DIM-F2G-1')).json);
    verifier('DÉCISION DU 13/11/2026 : chaque fileul ne détient que SA demande — F1 ne reçoit jamais celle de F2 (lignes de l\'inventaire valorisé), F2 ne reçoit jamais celle de F1', await (async () => {
      await dormir(900);
      const ids1 = (await f1.liste('demandesImport')).map((x) => x.id), ids2 = (await f2.liste('demandesImport')).map((x) => x.id);
      return ids1.every((i) => i.startsWith('DIM-F1')) && ids2.length === 1 && ids2[0] === 'DIM-F2G-1' && !ids1.includes('DIM-F2G-1');
    })(), [(await f1.liste('demandesImport')).map((x) => x.id), (await f2.liste('demandesImport')).map((x) => x.id)]);
    verifier('aucune ligne de l\'inventaire de F2 n\'est arrivée chez F1, même dans ses fiches restantes', !JSON.stringify(await f1.liste('demandesImport')).includes(STOCK_SECRET));
    verifier('la mère n\'a écrit AUCUN lot pour le refusé : le stock reste celui de la première demande (150, deux lots), la mère l\'emporte', (await compte('lots')) === 2 && (await compte('mouvements')) === 2);

    /* 5. LA MÈRE EST INJOIGNABLE : la demande ET la variation du fileul attendent dans sa file (hors ligne d'abord), puis arrivent UNE fois ; la mère est ensuite TUÉE, relancée sur sa base */
    m.reseau.regler('ferme');
    await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1G-3', champs: demande('DIMG3', { fichier: 'hors-ligne.xlsx', lotLocalId: 'LOT-DIMG3-1' }) });
    await f1.ecrire({ type: 'creer', collection: 'deltasCompteurs', fiche: 'F1~2~0', champs: { cle: 'lots/LOT-DIMG1-2/quantiteRestante', delta: -5, poste: 'F1' } });
    await dormir(700);
    verifier('mère injoignable : la demande et la sortie restent dans la file du fileul, la mère ne les a pas', (await f1.etat()).en_attente >= 2 && (await compte('demandesImport')) === 2 && (await compte('deltasCompteurs')) === 1, await f1.etat());
    m.reseau.regler('ouvert');
    verifier('le réseau revient : la demande et la sortie arrivent à la mère, UNE fois chacune', await attendre(async () => (await compte('demandesImport')) === 3 && (await compte('deltasCompteurs')) === 2 && await f1.vide(), 20000), [await compte('demandesImport'), await compte('deltasCompteurs')]);
    await m.mere.tuer();
    await f2.ecrire({ type: 'creer', collection: 'deltasCompteurs', fiche: 'F2~1~0', champs: { cle: 'lots/LOT-DIMG1-1/quantiteRestante', delta: -3, poste: 'F2' } });
    await dormir(700);
    await m.mere.demarrer();
    verifier('mère tuée puis relancée : la sortie de la file arrive, sans doublon', await attendre(async () => (await compte('deltasCompteurs')) === 3 && await f2.vide(), 25000), await compte('deltasCompteurs'));
    verifier('les lots et mouvements de la mère n\'ont pas bougé : deux lots, deux mouvements', (await compte('lots')) === 2 && (await compte('mouvements')) === 2);

    /* 6. LE RELAIS ne voit que du chiffré : ni la désignation de l'article, ni les noms de collections de stock, ni la série, ni les identifiants */
    await attendre(async () => { const e = await etatMere(); return e.rep_seq === e.seq_max; }, 20000);
    const brut = (await m.relais.direct('GET', '/banc/tout')).json;
    const journal = brut.lignes.filter((l) => l.dir === 'journal');
    const tout = JSON.stringify({ lignes: brut.lignes, codes: brut.codes, appareils: brut.appareils, meta: brut.meta.filter((x) => x.k !== 'indicateurs') });
    const octets = journal.map((l) => Buffer.from(l.ct, 'base64'));
    const mots = /Quinquina|ARTICLE-SECRET|demandesImport|deltasCompteurs|departCompteurs|serieDemande|LOT-DIMG1|DOUBLON_MAGASIN|STOCK_DEJA_SORTI/;
    const motsOctets = /Quinquina|ARTICLE-SECRET|demandesImport|deltasCompteurs|departCompteurs|serieDemande|LOT-DIMG1|DOUBLON_MAGASIN|STOCK_DEJA_SORTI/;
    verifier('le relais détient le journal de la mère en enveloppes', journal.length >= 1, journal.length);
    verifier('ni la désignation de l\'article, ni les collections du stock, ni les identifiants, ni le code du verdict ne sont lisibles au relais, même après décodage des octets', !mots.test(tout) && octets.every((b) => !motsOctets.test(b.toString('latin1'))), tout.length);
    const gros = octets.filter((b) => b.length >= 250);
    verifier('chaque enveloppe porteuse a l\'entropie d\'un chiffrement (> 7 bits/octet)', gros.length >= 1 && gros.every((b) => entropie(b) > 7.0), octets.map((b) => [b.length, +entropie(b).toFixed(2)]));
    const claires = journal.map((l) => dechiffrer(cleClinique, l)).flatMap((c) => c.ops || []);
    verifier('avec la clé de clinique (que le relais n\'a pas), l\'enveloppe contient bien la demande du Grand Stock et ses lignes : l\'opacité ne vient pas d\'un contenu vide',
      claires.some((o) => o.collection === 'demandesImport' && JSON.stringify(o.champs || {}).includes(STOCK_SECRET)), claires.length);

    /* 7. UN TÉLÉPHONE ne dépose pas la demande et ne reçoit NI la demande, NI ses lignes, NI les variations, NI les lots et mouvements écrits par une demande (hors de sa portée : le stock voyage aux
       mobiles selon leurs règles actuelles, non changées par ce lot) */
    const mob = await m.mobile('M1', { profil: 'soignant' });
    await mob.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-M1G-1', champs: demande('DIMGM', { demandeRole: 'medecin' }) });
    verifier('le téléphone qui tente de déposer une demande de Grand Stock est refusé, nommé (droit_refuse)', await attendre(async () => (await mob.etat()).a_traiter.some((x) => x.code === 'droit_refuse'), 15000));
    await f1.ecrire({ type: 'creer', collection: 'demandesImport', fiche: 'DIM-F1G-5', champs: demande('DIMG5', { fichier: 'apres-appairage.xlsx', lotLocalId: 'LOT-DIMG5-1' }) });
    await attendre(async () => (await compte('demandesImport')) === 4, 15000);
    await m.mere.admin('POST', '/admin/referentiel', { collection: 'lots', fiche: 'LOT-DIMG5-1', champs: lot('DIMG5', 1, 100) });
    await m.mere.admin('POST', '/admin/referentiel', { collection: 'mouvements', fiche: 'MOU-DIMG5-1', champs: mouvement('DIMG5', 1, 100) });
    await m.mere.admin('POST', '/admin/referentiel', { collection: 'demandesImport', fiche: 'DIM-F1G-5', champs: { etat: 'refusee', resultatCode: 'RESULTAT_DIFFERENT', lignes: [] } });
    await f1.ecrire({ type: 'creer', collection: 'deltasCompteurs', fiche: 'F1~3~0', champs: { cle: 'lots/LOT-DIMG5-1/quantiteRestante', delta: -1, poste: 'F1' } });
    await dormir(1200);
    const recu = async (col) => (await mob.liste(col)).length;
    verifier('le téléphone ne reçoit AUCUNE demande d\'import, AUCUNE variation, AUCUN lot ni mouvement écrit par une demande', (await recu('demandesImport')) === 0 && (await recu('deltasCompteurs')) === 0 && (await recu('lots')) === 0 && (await recu('mouvements')) === 0,
      [await recu('demandesImport'), await recu('deltasCompteurs'), await recu('lots'), await recu('mouvements')]);
    verifier('la mère n\'a pas écrit la demande du téléphone', (await compte('demandesImport')) === 4);
    await m.fermer();
  },
});
