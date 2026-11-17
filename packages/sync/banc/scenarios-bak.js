'use strict';
/* Scénario BAK1 (décision de la Direction de Baguidi du 15/11/2026, ADR-0008) : la SAUVEGARDE CHIFFRÉE HORS SITE, pilotée de bout en bout PAR LA MÈRE — celle de référence (Node) ou, avec
   SIGH_MERE=dart, l'exécutable Dart ; le relais est celui de référence ou, avec SIGH_RELAIS=laravel, le relais Laravel.

   Ce que le scénario éprouve, par les routes d'administration de la mère (`/admin/horssite/*`) et les réglages posés comme un administrateur les pose (fiches `parametres` datées) :
     1. DÉSACTIVÉE par défaut : rien ne part, le refus est nommé ;
     2. DEUX DESTINATIONS : le magasin vers le relais, les scans vers un dossier distant monté ; la clé de la clinique ne part pas ;
     3. OPACITÉ : ce que le relais ET le dossier distant détiennent, décodé, ne porte ni nom de fichier, ni mot du contenu, ni signature de fichier, avec l'entropie d'un chiffrement ;
        le journal technique de la mère ne porte aucun nom ; un bloc NON chiffré est REFUSÉ au dépôt (BLOC_NON_CHIFFRE), rien n'est stocké ;
     4. COUPURE puis REPRISE : la mère est TUÉE au milieu d'une copie des scans, puis relancée : seuls les blocs manquants partent, aucune copie en double ;
     5. BLOC ALTÉRÉ : le contrôle et la restauration le refusent en le NOMMANT, rien n'est restauré à moitié ;
     6. RESTAURATION COMPLÈTE : la base et les scans sont restaurés dans une cible NEUVE, empreintes identiques, la base et le dossier en service intacts ; une copie faite par la mère est
        restaurée par le client de référence (interopérabilité Node/Dart) ;
     7. PURGE AU PLANCHER : l'espace du relais manque, les plus anciennes copies archivées sont purgées la plus ancienne d'abord, JAMAIS une copie courante ; une copie purgée le DIT (410). */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { DatabaseSync } = require('node:sqlite');
const { DestRelais, Chiffreur } = require('./sauvegarde-hs');
const { DestDossier } = require('./sauvegarde-dossier');
const R = require('./sauvegarde-regles');

const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const MOT = 'Hyperglycemie-Secrete-BAK1';
const SENTINELLE_SCAN = 'SENTINELLE-SCAN-BAK1-Zebulon';
const NOMS_SCANS = ['2026-11-03_ARR_0001.pdf', '2026-11-04_ARR_0002.jpg', '2026-11-05_DEP_0003.png'];
const entropie = (b) => { const c = new Array(256).fill(0); for (const x of b) c[x]++; return -c.reduce((a, n) => (n ? a + (n / b.length) * Math.log2(n / b.length) : a), 0); };
const bruit = (graine, n) => { const out = Buffer.alloc(n); for (let i = 0; i < n; i += 32) crypto.createHash('sha256').update(graine + ':' + i).digest().copy(out, i, 0, Math.min(32, n - i)); return out; };
const scan = (nom, taille) => Buffer.concat([
  /pdf$/.test(nom) ? Buffer.from(`%PDF-1.4\n${SENTINELLE_SCAN}\n`) : /jpg$/.test(nom) ? Buffer.from([0xff, 0xd8, 0xff, 0xe0]) : Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), bruit(nom, taille)]);

/* tous les fichiers d'un dossier, récursivement */
const fichiersDe = (d) => (fs.existsSync(d) ? fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? fichiersDe(path.join(d, e.name)) : [path.join(d, e.name)])) : []);

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async BAK1() {
    titre('SAUVEGARDE-BAK1 · copie chiffrée hors site par la mère : désactivée par défaut, deux destinations, opacité, coupure puis reprise, bloc altéré refusé, restauration complète, purge au plancher');
    const m = await monde({ relais: true });
    await m.mere.tuer();
    m.mere.opts.cle = Buffer.from(m.clePair, 'hex').toString('base64');
    m.mere.opts.fichiers = path.join(m.dir, 'scans-mere');
    await m.mere.demarrer();
    const cleClinique = Buffer.from(m.clePair, 'hex');
    const distant = path.join(m.dir, 'dossier-distant'); fs.mkdirSync(distant);
    const admin = (methode, chemin, corps) => m.mere.admin(methode, chemin, corps);
    const etat = async () => (await admin('GET', '/admin/horssite/etat')).json;
    const lancer = (type) => admin('POST', '/admin/horssite/lancer', { type });
    const relaisEtat = () => m.relais.direct('GET', '/sauvegarde/etat').then((r) => r.json);
    const destRelais = new DestRelais(`http://127.0.0.1:${m.relais.port}`, 'secret-mere');
    const destDossier = new DestDossier(distant);
    let version = 0;
    const regler = async (valeurs) => {
      const TYPES = { 'horssite.actif': 'booleen', 'horssite.destinationMagasin': 'choix', 'horssite.destinationFichiers': 'choix', 'horssite.dossierMagasin': 'texte', 'horssite.dossierFichiers': 'texte',
        'horssite.copiesMagasin': 'entier', 'horssite.copiesFichiers': 'entier', 'horssite.tailleBloc': 'entier', 'horssite.blocsControles': 'entier' };
      version++;
      for (const [cle, valeur] of Object.entries(valeurs)) {
        const r = await admin('POST', '/admin/referentiel', { collection: 'parametres', fiche: `${cle}@2020-01-01@${version}`, champs: { cle, famille: 'horssite', type: TYPES[cle], valeur, defaut: valeur, ...(TYPES[cle] === 'choix' ? { choix: ['aucune', 'relais', 'dossier'] } : {}), dateEffet: '2020-01-01', version, auteur: 'admin', creeLe: '2026-11-15T08:00:00Z', mobile: false } });
        if (r.json.statut !== 'acceptee') verifier('le réglage posé est accepté par la mère', false, [cle, r.json]);
      }
    };
    let tirage = 0;
    /* une fiche dont le contenu CHANGE à chaque appel : sur la même identité, les pages de la base qui la portent changent, donc les blocs de chaque copie lui sont propres (le dédoublonnage ne les partage pas) */
    const ecrireFiche = (id, taille) => admin('POST', '/admin/referentiel', { collection: 'produits', fiche: id, champs: { designation: MOT + ' ' + id, note: bruit(id + ':' + (++tirage), taille).toString('base64') } }).then((r) => r.json);
    const deposerScan = async (nom, octets) => {
      const h = sha(octets); const BLOC = 192 * 1024; const total = Math.max(1, Math.ceil(octets.length / BLOC));
      for (let i = 0; i < total; i++) {
        const r = await admin('POST', '/admin/fichiers/bloc', { charge: { sha: h, nom, nomOrigine: nom, famille: 'courrier', taille: octets.length, index: i, total, b64: octets.subarray(i * BLOC, (i + 1) * BLOC).toString('base64') } });
        if (r.status !== 200) verifier('le scan est déposé chez la mère', false, [nom, r.status, r.json]);
      }
      return h;
    };
    const manifesteDe = async (dest, type, copieId) => {
      const ch = new Chiffreur(cleClinique); const c = await dest.copie(copieId);
      const clair = Buffer.concat(await Promise.all(c.racine.map(async (id) => ch.ouvrir('manifeste', type, await dest.bloc(id)))));
      return JSON.parse(clair.toString());
    };

    /* 1. DÉSACTIVÉE par défaut */
    const e0 = await etat();
    const l0 = await lancer('magasin');
    verifier('désactivée par défaut : l\'état dit « inactive », lancer est refusé en nommant HORSSITE_DESACTIVEE (409) avec le geste, rien ne part',
      e0.actif === false && l0.status === 409 && l0.json.code === 'HORSSITE_DESACTIVEE' && /Sauvegarde hors site/.test(l0.json.geste || '') && (await relaisEtat()).nb_blocs === 0, [e0.actif, l0.status, l0.json]);

    /* 2. deux destinations : le magasin vers le relais, les scans vers un dossier distant */
    const scans = {}; for (const [i, nom] of NOMS_SCANS.entries()) { const o = scan(nom, [400000, 150000, 90000][i]); scans[nom] = { octets: o, sha: await deposerScan(nom, o) }; }
    await ecrireFiche('bak-0', 50000);
    await regler({ 'horssite.actif': true, 'horssite.destinationMagasin': 'relais', 'horssite.destinationFichiers': 'dossier', 'horssite.dossierFichiers': distant, 'horssite.copiesMagasin': 2, 'horssite.copiesFichiers': 2, 'horssite.tailleBloc': 65536, 'horssite.blocsControles': 200 });
    const copieM = await lancer('magasin'); const copieF = await lancer('fichiers');
    verifier('activée par un réglage daté : la copie du magasin part vers le RELAIS, celle des scans vers le DOSSIER DISTANT (deux destinations)',
      copieM.status === 200 && copieM.json.ok === true && copieF.status === 200 && copieF.json.ok === true && copieF.json.elements === 3, [copieM.status, copieM.json, copieF.status, copieF.json]);
    const re = await relaisEtat();
    verifier('le relais tient UNE copie du magasin et AUCUNE copie des scans ; le dossier distant tient UNE copie des scans',
      re.copies.magasin.completes === 1 && re.copies.fichiers.completes === 0 && (await destDossier.copies('fichiers')).filter((c) => c.etat === 'complete').length === 1, [re.copies, await destDossier.copies('fichiers')]);
    const e1 = await etat();
    verifier('l\'état de la dernière copie est lisible : date, taille et résultat, pour chaque type', ['magasin', 'fichiers'].every((t) => e1.types[t].dernier && e1.types[t].dernier.ok === true && e1.types[t].dernier.quand > 0 && e1.types[t].dernier.octets > 0), e1.types);
    const rejeu = await lancer('fichiers');
    verifier('le rejeu du même état ne dépose rien de plus (idempotent)', rejeu.status === 200 && rejeu.json.deposes === 0 && rejeu.json.rejeu === true, rejeu.json);

    /* 3. OPACITÉ : le relais et le dossier distant, décodés */
    const blocsRelais = fichiersDe(path.join(m.dir, 'sauvegardes-relais', 'blocs')).filter((f) => !f.endsWith('.tmp')).map((f) => fs.readFileSync(f));
    const blocsDossier = fichiersDe(path.join(distant, 'blocs')).filter((f) => !f.endsWith('.tmp')).map((f) => fs.readFileSync(f));
    const signatures = [Buffer.from('SQLite format 3'), Buffer.from('%PDF-'), Buffer.from([0xff, 0xd8, 0xff]), Buffer.from([0x89, 0x50, 0x4e, 0x47]), Buffer.from('RIFF'), Buffer.from('PK\x03\x04')];
    const motsInterdits = [MOT, 'Hyperglycemie', SENTINELLE_SCAN, 'SENTINELLE', 'ARR_0001', 'DEP_0003', '.pdf', '.jpg', 'patient', 'fiches'];
    const propre = (liste) => liste.length > 0 && liste.every((b) => signatures.every((s) => !b.subarray(0, s.length).equals(s)) && motsInterdits.every((x) => !b.includes(Buffer.from(x))));
    verifier(`le relais (${blocsRelais.length} blocs) et le dossier distant (${blocsDossier.length} blocs), octets décodés : aucune signature de fichier au début, aucun mot du contenu, aucun nom de fichier`, propre(blocsRelais) && propre(blocsDossier));
    const gros = [...blocsRelais, ...blocsDossier].filter((b) => b.length >= 4096);
    verifier('chaque bloc de plus de 4 Kio a l\'entropie d\'un chiffrement (> 7,5 bits par octet)', gros.length >= 5 && gros.every((b) => entropie(b) > 7.5), gros.map((b) => +entropie(b).toFixed(2)).slice(0, 8));
    const copiesDossier = fichiersDe(path.join(distant, 'copies')).map((f) => fs.readFileSync(f, 'utf8')).join('\n');
    const toutRelais = JSON.stringify((await m.relais.direct('GET', '/banc/sauvegarde/tout')).json);
    verifier('les fiches de copie du dossier distant et les tables du relais ne portent que des identifiants, des tailles et des dates : ni nom, ni empreinte en clair, ni clé',
      motsInterdits.every((x) => !copiesDossier.includes(x) && !toutRelais.includes(x)) && !Object.values(scans).some((s) => copiesDossier.includes(s.sha) || toutRelais.includes(s.sha)) && !toutRelais.includes(m.clePair) && !copiesDossier.includes(m.clePair));
    const journal = (await admin('GET', '/admin/horssite/journal')).json.lignes.map((l) => l.message).join('\n');
    verifier('le journal technique de la mère dit les copies (compteurs) sans AUCUN nom de fichier, de patient ni empreinte',
      /Copie hors site magasin/.test(journal) && motsInterdits.every((x) => !journal.includes(x)) && !Object.values(scans).some((s) => journal.includes(s.sha.slice(0, 12))), journal.slice(0, 300));
    const clair = Buffer.from('patient ' + MOT + ' ordonnance '.repeat(600)); const idClair = sha(clair);
    const refusClair = await m.relais.direct('PUT', '/sauvegarde/bloc/' + idClair, clair, undefined).catch(() => null);
    const direct = await fetch(`http://127.0.0.1:${m.relais.port}/sauvegarde/bloc/${idClair}`, { method: 'PUT', headers: { 'x-mere': 'secret-mere', 'Content-Type': 'application/octet-stream' }, body: clair });
    const jd = await direct.json().catch(() => ({}));
    void refusClair;
    verifier('un bloc NON CHIFFRÉ (du texte) est REFUSÉ au dépôt : 422 BLOC_NON_CHIFFRE avec le geste, rien n\'est stocké',
      direct.status === 422 && jd.code === 'BLOC_NON_CHIFFRE' && /Chiffrer/.test(jd.geste || '') && (await destRelais.manquants([idClair])).includes(idClair), [direct.status, jd]);
    const refusDossier = await destDossier.deposerBloc(idClair, clair).then(() => null, (x) => x.refus);
    verifier('le dossier distant refuse lui aussi le bloc non chiffré (même garde-fou)', refusDossier && refusDossier.code === 'BLOC_NON_CHIFFRE', refusDossier);

    /* 4. COUPURE puis REPRISE : la mère est TUÉE au milieu de la copie des scans */
    const gros2 = scan('2026-11-06_ARR_0004.pdf', 9 * 1024 * 1024); scans['2026-11-06_ARR_0004.pdf'] = { octets: gros2, sha: await deposerScan('2026-11-06_ARR_0004.pdf', gros2) };
    const blocsAvant = fichiersDe(path.join(distant, 'blocs')).filter((f) => !f.endsWith('.tmp')).length;
    const copiesAvant = (await destDossier.copies('fichiers')).length;
    void lancer('fichiers').catch(() => {});
    let demarre = false; for (let i = 0; i < 20000 && !demarre; i++) { demarre = fichiersDe(path.join(distant, 'blocs')).filter((f) => !f.endsWith('.tmp')).length >= blocsAvant + 10; if (!demarre) await dormir(2); } /* sonde serrée : la copie doit être coupée AU MILIEU */
    await m.mere.tuer();
    const blocsMilieu = fichiersDe(path.join(distant, 'blocs')).filter((f) => !f.endsWith('.tmp')).length;
    verifier('la mère est TUÉE au milieu de la copie : des blocs sont déjà là, la copie n\'est PAS complète (la précédente reste la dernière complète)',
      demarre && blocsMilieu > blocsAvant && (await destDossier.copies('fichiers')).filter((c) => c.etat === 'complete').length === 1, [demarre, blocsAvant, blocsMilieu]);
    await m.mere.demarrer();
    const repris = await lancer('fichiers');
    const blocsFin = fichiersDe(path.join(distant, 'blocs')).filter((f) => !f.endsWith('.tmp')).length;
    verifier('mère relancée : la reprise termine la copie, les blocs d\'avant la coupure ne sont pas redéposés (déjà là), la copie est complète',
      repris.status === 200 && repris.json.ok === true && repris.json.dejaLa >= blocsMilieu - blocsAvant && repris.json.deposes + repris.json.dejaLa >= blocsFin - blocsAvant && (await destDossier.copies('fichiers')).filter((c) => c.etat === 'complete').length === 2, repris.json);
    const copiesApres = await destDossier.copies('fichiers');
    verifier('aucune copie en double : une seule copie de plus pour l\'état nouveau, aucun bloc en double (identifiants distincts)',
      copiesApres.length === copiesAvant + 1 && new Set(fichiersDe(path.join(distant, 'blocs')).map((f) => path.basename(f))).size === blocsFin, [copiesAvant, copiesApres.length]);

    /* 5. BLOC ALTÉRÉ : nommé, rien n'est restauré à moitié */
    const derniereF = copiesApres.find((c) => c.etat === 'complete');
    const mf = await manifesteDe(destDossier, 'fichiers', derniereF.id);
    const idAltere = mf.elements.find((e) => e.ref === '2026-11-06_ARR_0004.pdf').blocs[1].id;
    const fAltere = path.join(distant, 'blocs', idAltere.slice(0, 2), idAltere);
    const original = fs.readFileSync(fAltere); const abime = Buffer.from(original); abime[abime.length - 1] ^= 1; fs.writeFileSync(fAltere, abime);
    const ctl = await admin('POST', '/admin/horssite/controler');
    const cibleKo = path.join(m.dir, 'restauration-ko');
    const rKo = await admin('POST', '/admin/horssite/restaurer', { type: 'fichiers', copie: derniereF.id, cible: cibleKo });
    verifier('un bloc altéré au dossier distant : le CONTRÔLE le dit (ok faux, BLOC_ALTERE nommé) et la RESTAURATION le refuse en le nommant',
      ctl.json.fichiers && ctl.json.fichiers.ok === false && ctl.json.fichiers.code === 'BLOC_ALTERE' && rKo.status !== 200 && rKo.json.code === 'BLOC_ALTERE' && rKo.json.motif.includes(idAltere), [ctl.json, rKo.status, rKo.json]);
    verifier('rien n\'est restauré à moitié : ni cible, ni dossier de travail', !fs.existsSync(cibleKo) && fs.readdirSync(m.dir).every((n) => !/restauration-ko/.test(n)));
    const e2 = await etat();
    verifier('l\'échec du contrôle est enregistré à l\'état de la copie (visible à l\'écran)', e2.types.fichiers.controle && e2.types.fichiers.controle.ok === false, e2.types.fichiers.controle);
    fs.writeFileSync(fAltere, original);

    /* 6. RESTAURATION COMPLÈTE : empreintes identiques, rien du service touché */
    const avantService = fichiersDe(path.join(m.dir, 'scans-mere')).filter((f) => !/\.(tmp|part)$/.test(f)).map((f) => [path.basename(f), sha(fs.readFileSync(f))]).sort().join('|');
    const cibleF = path.join(m.dir, 'restauration-fichiers');
    const rF = await admin('POST', '/admin/horssite/restaurer', { type: 'fichiers', copie: derniereF.id, cible: cibleF });
    const dirR = path.join(cibleF, 'fichiers');
    const identiques = Object.entries(scans).every(([nom, s]) => fs.existsSync(path.join(dirR, nom)) && sha(fs.readFileSync(path.join(dirR, nom))) === s.sha);
    verifier('restauration des scans dans une cible NEUVE : les quatre fichiers ont les mêmes empreintes que les originaux, aucun de plus',
      rF.status === 200 && rF.json.elements === 4 && identiques && fichiersDe(dirR).filter((f) => !f.endsWith('MANIFESTE.json') && !f.endsWith('empreintes.json')).length === 4, [rF.status, rF.json]);
    const apresService = fichiersDe(path.join(m.dir, 'scans-mere')).filter((f) => !/\.(tmp|part)$/.test(f)).map((f) => [path.basename(f), sha(fs.readFileSync(f))]).sort().join('|');
    verifier('le dossier des scans EN SERVICE n\'est pas touché par la restauration', avantService === apresService);
    const rExiste = await admin('POST', '/admin/horssite/restaurer', { type: 'fichiers', copie: derniereF.id, cible: cibleF });
    verifier('une cible qui existe déjà est REFUSÉE (409 CIBLE_EXISTE) : la restauration ne remplace jamais', rExiste.status === 409 && rExiste.json.code === 'CIBLE_EXISTE', [rExiste.status, rExiste.json]);
    const copiesM = (await admin('GET', '/admin/horssite/copies?type=magasin')).json.copies;
    const cibleM = path.join(m.dir, 'restauration-magasin');
    const rM = await admin('POST', '/admin/horssite/restaurer', { type: 'magasin', copie: copiesM[0].id, cible: cibleM });
    let nbFiches = -1; try { const bd = new DatabaseSync(path.join(cibleM, 'magasin'), { readOnly: true }); nbFiches = bd.prepare("SELECT COUNT(*) AS n FROM fiches WHERE id='bak-0'").get().n; bd.close(); } catch (x) { nbFiches = String(x.message); }
    verifier('restauration du magasin : une base SQLite lisible qui contient la fiche posée avant la copie', rM.status === 200 && rM.json.elements === 1 && nbFiches === 1, [rM.status, rM.json, nbFiches]);
    const cibleCli = path.join(m.dir, 'restauration-cli');
    const cli = spawnSync('node', ['--no-warnings', path.join(__dirname, 'sauvegarde-restaure.js'), JSON.stringify({ relais: destRelais.base, secret: 'secret-mere', cle: m.clePair, copie: copiesM[0].id, cible: cibleCli })], { encoding: 'utf8' });
    const sortie = (() => { try { return JSON.parse(cli.stdout.trim().split('\n').pop()); } catch (x) { return { ok: false, brut: cli.stdout + cli.stderr }; } })();
    verifier('INTEROPÉRABILITÉ : la copie faite par la mère est restaurée par le client de référence, octet pour octet la même base',
      sortie.ok === true && fs.existsSync(path.join(cibleCli, 'magasin')) && sha(fs.readFileSync(path.join(cibleCli, 'magasin'))) === sha(fs.readFileSync(path.join(cibleM, 'magasin'))), sortie);

    /* 7. PURGE AU PLANCHER : cinq copies du magasin de plus (garder 2), puis le relais manque d'espace */
    const ids = [copiesM[0].id];
    const parEtat = async () => { const cs = (await admin('GET', '/admin/horssite/copies?type=magasin')).json.copies; return Object.fromEntries(cs.map((c) => [c.id, c.etat])); };
    for (let i = 1; i <= 5; i++) {
      await dormir(15); await ecrireFiche('bak-gros', 220000);
      const r = await lancer('magasin'); if (r.status !== 200) verifier('une copie du magasin est faite', false, [i, r.status, r.json]);
      ids.push((await admin('GET', '/admin/horssite/copies?type=magasin')).json.copies.find((c) => c.etat === 'complete' && !ids.includes(c.id)).id);
    }
    const e7 = await parEtat();
    verifier('six copies du magasin, garder 2 : les deux plus récentes sont courantes, les quatre plus anciennes ARCHIVÉES (jamais supprimées)',
      e7[ids[5]] === 'complete' && e7[ids[4]] === 'complete' && ids.slice(0, 4).every((i) => e7[i] === 'archivee'), e7);
    /* Le plan d'une copie compte la copie ENTIÈRE (le client ignore ce que le relais tient déjà) : le quota est réglé pour que le plan PASSE (la copie entière tient dans l'espace libre plus les
       anciennes copies archivées libérables) alors que les blocs réellement NOUVEAUX (la fiche réécrite et sa trace au journal) ne tiennent pas sans purge. La base grossit de la fiche à chaque écriture
       (le journal la garde) : la marge en tient compte. */
    const r7 = await relaisEtat();
    const taillesCopies = (await admin('GET', '/admin/horssite/copies?type=magasin')).json.copies.sort((a, b) => b.date - a.date).map((c) => c.taille);
    const croissance = taillesCopies[0] - taillesCopies[1]; /* ce que chaque écriture ajoute à la base, mesuré sur les deux dernières copies */
    await dormir(15); await ecrireFiche('bak-gros', 220000);
    await m.relais.direct('POST', '/banc/sauvegarde/reglage', { cle: 'quotaOctets', valeur: Math.max(1, r7.utilise + taillesCopies[0] + croissance + 20000 - r7.liberable) });
    const r8 = await lancer('magasin');
    const e8 = await parEtat();
    const nouvelle = Object.keys(e8).find((i) => !ids.includes(i));
    verifier('l\'espace manque : la copie est faite en PURGEANT les plus anciennes copies archivées, la plus ancienne d\'abord (la plus ancienne est purgée avant la suivante)',
      r8.status === 200 && r8.json.ok === true && e8[ids[0]] === 'purgee' && (e8[ids[1]] !== 'purgee' || e8[ids[0]] === 'purgee'), [r8.status, r8.json.code, e8]);
    const courantes = Object.entries(e8).filter(([, s]) => s === 'complete').map(([i]) => i);
    verifier('JAMAIS une copie courante : la copie nouvelle et la plus récente d\'avant sont intactes, leurs blocs sont lisibles ; rien de courant n\'est purgé',
      courantes.length === 2 && courantes.includes(nouvelle) && courantes.includes(ids[5]) && e8[ids[4]] !== 'purgee', e8);
    const rPurgee = await admin('POST', '/admin/horssite/restaurer', { type: 'magasin', copie: ids[0], cible: path.join(m.dir, 'restauration-purgee') });
    verifier('une copie purgée le DIT : refus nommé COPIE_PURGEE (410), rien restauré ; sa ligne reste au registre (RG-14)', rPurgee.status === 410 && rPurgee.json.code === 'COPIE_PURGEE' && !fs.existsSync(path.join(m.dir, 'restauration-purgee')) && ids[0] in e8, [rPurgee.status, rPurgee.json]);
    const rCourante = await admin('POST', '/admin/horssite/restaurer', { type: 'magasin', copie: nouvelle, cible: path.join(m.dir, 'restauration-courante') });
    const rAvant = await admin('POST', '/admin/horssite/restaurer', { type: 'magasin', copie: ids[5], cible: path.join(m.dir, 'restauration-avant') });
    verifier('les deux copies courantes se restaurent toujours après la purge', rCourante.status === 200 && rCourante.json.ok === true && rAvant.status === 200 && rAvant.json.ok === true, [rCourante.status, rAvant.status]);
    await m.relais.direct('POST', '/banc/sauvegarde/reglage', { cle: 'quotaOctets', valeur: 1000 });
    await dormir(15); await ecrireFiche('bak-gros', 220000);
    const r9 = await lancer('magasin');
    const e9 = await parEtat();
    verifier('quota insuffisant même après avoir tout libéré : refus nommé ESPACE_RELAIS_INSUFFISANT (507) avec le geste, les copies courantes SONT INTACTES, rien d\'actuel détruit',
      r9.status === 507 && r9.json.code === 'ESPACE_RELAIS_INSUFFISANT' && !!r9.json.geste && Object.entries(e9).filter(([, s]) => s === 'complete').map(([i]) => i).sort().join() === courantes.sort().join(), [r9.status, r9.json, e9]);
    const e10 = await etat();
    verifier('l\'erreur est enregistrée à l\'état avec son geste ; la dernière copie réussie reste affichée (jamais un faux « à jour »)', e10.types.magasin.erreur && e10.types.magasin.erreur.code === 'ESPACE_RELAIS_INSUFFISANT' && !!e10.types.magasin.erreur.geste && e10.types.magasin.dernier && e10.types.magasin.dernier.ok === true, e10.types.magasin);
    /* 8. LES RÈGLES DE RÉFÉRENCE ET LES VECTEURS PARTAGÉS NE DIVERGENT PAS : ce que Dart et PHP rejouent est ce que ce banc applique (un vecteur périmé ferait tester Dart contre une règle qui n'est plus la nôtre) */
    const vecteurs = JSON.parse(fs.readFileSync(path.join(__dirname, '..', '..', 'domaine', 'test', 'vecteurs', 'sauvegarde_horssite.json'), 'utf8')).cas;
    const rejoue = (c) => {
      const e = c.entree;
      switch (c.op) {
        case 'ordrePurge': return R.ordrePurge(e.copies, e.plancher);
        case 'rotation': return R.rotation(e.copies, e.garder, e.plancher, e.plafond);
        case 'verifierReglage': return R.verifierReglage(e);
        case 'verifierPlan': return R.verifierPlan(e);
        case 'blocSuspect': return R.blocSuspect(Buffer.from(e.base64, 'base64'));
        default: return undefined;
      }
    };
    const ecarts = vecteurs.filter((c) => rejoue(c) !== undefined && JSON.stringify(rejoue(c)) !== JSON.stringify(c.attendu)).map((c) => c.nom);
    verifier(`les ${vecteurs.length} vecteurs partagés (purge à plancher, rotation, réglage, plan, bloc non chiffré) donnent à la règle de référence du banc exactement l'attendu`, ecarts.length === 0, ecarts);
    await m.fermer();
  },
});
