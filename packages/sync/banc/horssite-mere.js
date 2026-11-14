'use strict';
/* =============================================================================
 * SIGH-CBG : la COPIE HORS SITE de la mère de RÉFÉRENCE (lot BAK, ADR-0008). Les routes `/admin/horssite/*` du banc, mêmes refus nommés, mêmes statuts, même forme de réponse
 * que le moteur Dart (`packages/sync_dart/lib/src/horssite_mere.dart`, `Mere.routeHorsSite`). Le réglage est lu des fiches `parametres` de la mère (famille `horssite`, versionné par
 * date, DÉSACTIVÉE par défaut) ; la clé de clinique est celle du journal et ne part jamais. Pas de planificateur ici : les gestes se déclenchent par les routes (le banc les pilote).
 * Le journal technique ne porte JAMAIS un nom de fichier, un nom de patient ni un contenu : des codes, des compteurs, des tailles.
 * ========================================================================== */
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const R = require('./sauvegarde-regles');
const { DestRelais, ErreurSauvegarde, sauvegarder, restaurer, controler } = require('./sauvegarde-hs');
const { DestDossier } = require('./sauvegarde-dossier');

const CLES = {
  actif: 'horssite.actif', destM: 'horssite.destinationMagasin', destF: 'horssite.destinationFichiers', dosM: 'horssite.dossierMagasin', dosF: 'horssite.dossierFichiers',
  copiesM: 'horssite.copiesMagasin', copiesF: 'horssite.copiesFichiers', bloc: 'horssite.tailleBloc', blocsCtl: 'horssite.blocsControles',
};
/* Les défauts : ceux du registre des paramètres du domaine (`definitionsParametres`), désactivée par défaut. */
const DEFAUTS = { [CLES.actif]: false, [CLES.destM]: 'relais', [CLES.destF]: 'aucune', [CLES.dosM]: '', [CLES.dosF]: '', [CLES.copiesM]: R.DEFAUTS.copiesMagasin, [CLES.copiesF]: R.DEFAUTS.copiesFichiers, [CLES.bloc]: R.DEFAUTS.tailleBloc, [CLES.blocsCtl]: R.DEFAUTS.blocsControles };

module.exports = ({ db, stock, cle, relais, secretRelais, evenement, Err }) => {
  const enCours = new Set();
  const meta = (k) => { const r = db.prepare('SELECT v FROM meta WHERE k=?').get(k); return r ? JSON.parse(r.v) : null; };
  const poser = (k, v) => db.prepare('INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v').run(k, JSON.stringify(v));
  const refus = (r, statut) => new Err(statut || ({ HORSSITE_DESACTIVEE: 409, COPIE_EN_COURS: 409, CIBLE_EXISTE: 409, SAUVEGARDE_TROP_GROSSE: 413, ESPACE_RELAIS_INSUFFISANT: 507, DOSSIER_INTROUVABLE: 503 })[r.code] || r.statut || 422, r.code, r.motif, { geste: r.geste });
  const dur = (code, motif, geste) => new ErreurSauvegarde(R.refus(code, motif, geste));

  /* la valeur en vigueur AUJOURD'HUI : la version datée la plus récente dont la date d'effet est atteinte, à défaut le défaut */
  function reglage() {
    const jour = new Date().toISOString().slice(0, 10);
    const versions = db.prepare("SELECT data FROM fiches WHERE collection='parametres' AND archive=0").all().map((r) => JSON.parse(r.data)).filter((p) => String(p.cle || '').startsWith('horssite.'));
    const v = (k) => {
      const c = versions.filter((p) => p.cle === k && String(p.dateEffet) <= jour).sort((a, b) => String(b.dateEffet).localeCompare(String(a.dateEffet)) || (b.version - a.version))[0];
      return c ? c.valeur : DEFAUTS[k];
    };
    const type = (dest, dos, copies) => ({ destination: v(dest), dossier: String(v(dos) || ''), copies: Number(v(copies)) });
    return { actif: v(CLES.actif) === true, tailleBloc: Number(v(CLES.bloc)), blocsControles: Number(v(CLES.blocsCtl)), magasin: type(CLES.destM, CLES.dosM, CLES.copiesM), fichiers: type(CLES.destF, CLES.dosF, CLES.copiesF) };
  }
  const destination = (type, r) => {
    const t = r[type];
    if (t.destination === 'aucune') throw dur('DESTINATION_ABSENTE', `aucune destination n'est réglée pour la copie ${type}`, 'Choisir le relais ou un dossier distant à l\'écran « Sauvegarde hors site ».');
    if (t.destination === 'relais') {
      if (!relais) throw dur('RELAIS_NON_CONFIGURE', 'cette mère n\'est pas reliée au relais', 'Renseigner l\'adresse du relais dans la configuration de la mère, ou choisir un dossier distant.');
      return new DestRelais(relais, secretRelais);
    }
    return new DestDossier(t.dossier);
  };
  const verifier = (r, type) => R.verifierReglage({ actif: r.actif, destination: r[type].destination, dossier: r[type].dossier, tailleBloc: r.tailleBloc, copies: r[type].copies, blocsControles: r.blocsControles });

  function elementsMagasin(db0, dossierTmp) {
    const f = path.join(dossierTmp, 'magasin.copie');
    db0.exec(`VACUUM INTO '${f.replace(/'/g, '')}'`);
    const octets = fs.readFileSync(f); fs.rmSync(f, { force: true });
    return { liste: [{ ref: 'magasin', taille: octets.length, lire: () => octets }], illisibles: 0 };
  }
  function elementsFichiers() {
    const s = stock(); if (!s) return { liste: [], illisibles: 0 };
    const liste = []; let illisibles = 0;
    for (const [h, e] of Object.entries(s.index)) for (const n of e.noms) {
      const f = path.join(s.dossier, n);
      if (!fs.existsSync(f) || crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex') !== h) { illisibles++; continue; }
      liste.push({ ref: n, taille: e.taille, lire: () => fs.readFileSync(f) });
    }
    return { liste, illisibles };
  }

  async function lancer(type, manuel) {
    if (!R.TYPES.includes(type)) throw dur('TYPE_INCONNU', `le type de copie « ${type} » n'existe pas`, 'Choisir magasin ou fichiers.');
    const r = reglage();
    if (!r.actif) throw dur('HORSSITE_DESACTIVEE', 'la copie hors site est désactivée', 'L\'administrateur ou la Directrice Administrative l\'active à l\'écran « Sauvegarde hors site ».');
    if (enCours.has(type)) throw dur('COPIE_EN_COURS', `une copie ${type} est déjà en cours`, 'Attendre la fin de la copie en cours.');
    enCours.add(type);
    const t0 = Date.now(); const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sigh-hs-'));
    try {
      poser('horssite.etat.' + type, { ...(meta('horssite.etat.' + type) || {}), tentative: t0 });
      const ctrl = verifier(r, type); if (ctrl) throw new ErreurSauvegarde(ctrl);
      const dest = destination(type, r);
      const el = type === 'magasin' ? elementsMagasin(db, tmp) : elementsFichiers();
      const res = await sauvegarder({ dest, cle: cle(), type, elements: el.liste, tailleBloc: r.tailleBloc, garder: r[type].copies, date: t0 });
      const rapport = { ok: true, quand: Date.now(), duree: Date.now() - t0, copie: res.copie.slice(0, 12), rejeu: res.rejeu, deposes: res.deposes, dejaLa: res.dejaLa, octetsDeposes: res.octetsDeposes,
        octets: el.liste.reduce((n, e) => n + e.taille, 0), blocs: res.deposes + res.dejaLa, elements: el.liste.length, illisibles: el.illisibles, destination: dest.libelle || 'relais', manuel: !!manuel };
      poser('horssite.etat.' + type, { ...(meta('horssite.etat.' + type) || {}), dernier: rapport, erreur: null });
      evenement('info', 'sauvegarde', `Copie hors site ${type} (${rapport.destination}) : ${res.deposes} bloc(s) déposé(s), ${res.dejaLa} déjà présent(s), ${rapport.elements} élément(s)${res.rejeu ? ', état déjà sauvegardé' : ''}`);
      if (el.illisibles) evenement('alerte', 'sauvegarde', `Copie hors site ${type} : ${el.illisibles} élément(s) illisible(s) à la source, non copiés`);
      return rapport;
    } catch (e) {
      if (e instanceof ErreurSauvegarde) {
        poser('horssite.etat.' + type, { ...(meta('horssite.etat.' + type) || {}), erreur: { quand: Date.now(), code: e.code, motif: e.refus.motif, geste: e.refus.geste } });
        evenement('erreur', 'sauvegarde', `Copie hors site ${type} : ${e.code}`);
      } else { poser('horssite.etat.' + type, { ...(meta('horssite.etat.' + type) || {}), erreur: { quand: Date.now(), code: 'DESTINATION_INJOIGNABLE', motif: 'la destination ne répond pas', geste: 'Vérifier le relais ou le dossier distant ; la copie reprendra.' } }); }
      throw e;
    } finally { enCours.delete(type); fs.rmSync(tmp, { recursive: true, force: true }); }
  }

  async function controle() {
    const r = reglage(); const sortie = {};
    for (const t of R.TYPES) {
      if (!r.actif || r[t].destination === 'aucune') continue;
      const refusT = await controler({ dest: destination(t, r), cle: cle(), type: t, nbBlocs: r.blocsControles });
      const ctrl = refusT ? { ok: false, quand: Date.now(), code: refusT.code, motif: refusT.motif, geste: refusT.geste } : { ok: true, quand: Date.now() };
      poser('horssite.etat.' + t, { ...(meta('horssite.etat.' + t) || {}), controle: ctrl }); sortie[t] = ctrl;
      if (refusT) evenement('erreur', 'sauvegarde', `Contrôle de la copie hors site ${t} : ${refusT.code}`); else evenement('info', 'sauvegarde', `Contrôle de la copie hors site ${t} : sain`);
    }
    poser('horssite.controle', { quand: Date.now(), types: sortie });
    return { ok: Object.values(sortie).every((c) => c.ok), types: sortie };
  }

  async function restaurerCopie({ type, copie, cible }) {
    const r = reglage(); const dest = destination(type, r);
    if (fs.existsSync(cible)) throw dur('CIBLE_EXISTE', `« ${cible} » existe déjà`, 'Restaurer vers un dossier NEUF : la restauration ne remplace jamais ce qui existe.');
    const travail = cible + '.hs-travail';
    const res = await restaurer({ dest, cle: cle(), copieId: copie, cible: travail });
    try {
      fs.mkdirSync(cible, { recursive: true });
      if (type === 'magasin') fs.renameSync(path.join(travail, 'magasin'), path.join(cible, 'magasin'));
      else {
        const d = path.join(cible, 'fichiers'); fs.mkdirSync(d); const mf = [];
        for (const n of fs.readdirSync(travail)) { const o = fs.readFileSync(path.join(travail, n)); fs.writeFileSync(path.join(d, n), o); mf.push({ nom: n, sha256: crypto.createHash('sha256').update(o).digest('hex'), taille: o.length }); }
        fs.writeFileSync(path.join(d, 'MANIFESTE.json'), JSON.stringify({ ecritLe: new Date().toISOString(), fichiers: mf }, null, 1));
      }
    } finally { fs.rmSync(travail, { recursive: true, force: true }); }
    evenement('alerte', 'sauvegarde', `Restauration de la copie hors site ${type} vers une cible neuve : ${res.elements} élément(s), ${res.octets} octet(s) vérifiés`);
    return { ok: true, type, elements: res.elements, octets: res.octets, cible };
  }

  function etat() {
    const r = reglage(); const types = {};
    for (const t of R.TYPES) { const e = meta('horssite.etat.' + t) || {}; types[t] = { dernier: e.dernier || null, erreur: e.erreur || null, controle: e.controle || null, destination: r[t].destination }; }
    return { actif: r.actif, types, controle: meta('horssite.controle') };
  }
  async function copies(type) { const r = reglage(); return destination(type, r).copies(type); }

  /* l'enveloppe des routes : les refus nommés deviennent des erreurs HTTP avec leur statut et leur geste */
  const garde = (f) => async (...a) => { try { return await f(...a); } catch (e) { if (e instanceof ErreurSauvegarde) throw refus(e.refus); throw e; } };
  return {
    etat: garde(async () => etat()),
    copies: garde(async (type) => ({ copies: await copies(type || 'magasin') })),
    lancer: garde(async (b) => lancer(String(b.type), true)),
    controler: garde(async () => controle()),
    restaurer: garde(async (b) => restaurerCopie({ type: String(b.type), copie: String(b.copie), cible: String(b.cible) })),
  };
};
