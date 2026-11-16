'use strict';
/* Le dossier des scans de la mère et le client des fichiers : implémentation de RÉFÉRENCE (Node) des règles de `packages/sync_dart/lib/src/fichiers.dart` et
 * de `packages/domaine/lib/src/documents/doc_regles.dart`. Même contrat, mêmes codes de refus, mêmes noms normalisés ; le banc pilote l'une ou l'autre. */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const TAILLE_BLOC = 192 * 1024;
const TAILLE_DEFAUT = 10 * 1024 * 1024;
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const NOM_COURRIER = /^\d{4}-\d{2}-\d{2}_(ARR|DEP)_\d{4,}(_v\d{1,3})?\.(pdf|jpg|png)$/;
const NOM_PATIENT = /^\d{4}-\d{2}-\d{2}_[A-Za-z0-9]+(-[A-Za-z0-9]+)*_[a-z0-9]+(-[a-z0-9]+)*_\d{3,}(_v\d{1,3})?\.(pdf|jpg|png|webp)$/;
const nomValide = (n) => n.length <= 120 && (NOM_COURRIER.test(n) || NOM_PATIENT.test(n));
class Refus extends Error { constructor(code, motif, geste) { super(motif); this.code = code; this.motif = motif; this.geste = geste || ''; } }

/* Le format se lit sur les OCTETS, jamais sur le nom. */
function formatDes(o) {
  const debut = (m, d = 0) => o.length >= d + m.length && m.every((x, i) => o[d + i] === x);
  if (debut([0x25, 0x50, 0x44, 0x46, 0x2d])) return 'pdf';
  if (debut([0xff, 0xd8, 0xff])) return 'jpeg';
  if (debut([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'png';
  if (debut([0x52, 0x49, 0x46, 0x46]) && debut([0x57, 0x45, 0x42, 0x50], 8)) return 'webp';
  return null;
}
function controlerDepot(o, famille, tailleMax) {
  if (!o.length) return new Refus('FICHIER_VIDE', 'Le fichier est vide.', 'Numériser de nouveau.');
  const f = formatDes(o);
  if (!f || (f === 'webp' && famille !== 'patient')) return new Refus('FORMAT_REFUSE', 'Format non admis : seuls PDF, JPEG, PNG sont acceptés.', 'Enregistrer le scan en PDF, JPEG ou PNG.');
  if (o.length > tailleMax) return new Refus('TAILLE_DEPASSEE', `Le fichier pèse ${o.length} octets ; la taille maximale réglée est ${tailleMax}.`, 'Numériser en résolution plus basse, ou relever la taille maximale.');
  return null;
}

class Stock {
  constructor(dossier) { this.dossier = dossier; fs.mkdirSync(dossier, { recursive: true }); this.index = {}; this.lireIndex(); }
  get fichierIndex() { return path.join(this.dossier, 'empreintes.json'); }
  get reception() { return path.join(this.dossier, '.reception'); }
  lireIndex() { this.index = {}; try { this.index = JSON.parse(fs.readFileSync(this.fichierIndex, 'utf8')); } catch (e) { if (fs.existsSync(this.fichierIndex)) this.reconstruire(); } }
  ecrireIndex() { const t = this.fichierIndex + '.tmp'; fs.writeFileSync(t, JSON.stringify(this.index, null, 1)); fs.renameSync(t, this.fichierIndex); }
  reconstruire() {
    this.index = {};
    for (const n of fs.readdirSync(this.dossier)) {
      if (!nomValide(n)) continue; const o = fs.readFileSync(path.join(this.dossier, n)); const h = sha(o);
      (this.index[h] = this.index[h] || { noms: [], taille: o.length }).noms.push(n);
    }
    this.ecrireIndex();
  }
  nombre() { return Object.values(this.index).reduce((n, e) => n + e.noms.length, 0); }
  octets() { return Object.values(this.index).reduce((n, e) => n + e.taille * e.noms.length, 0); }
  existe(h) { return !!this.index[h]; }
  deposer(o, h, nom) {
    if (!nomValide(nom)) throw new Refus('NOM_NON_NORMALISE', `Le nom « ${nom} » n’est pas un nom normalisé : la mère ne range que sous un nom du schéma.`, 'Rejouer le dépôt depuis la fiche.');
    if (sha(o) !== h) throw new Refus('EMPREINTE_DIVERGENTE', 'L’empreinte annoncée ne correspond pas aux octets reçus : le fichier a été altéré en route.', 'Rejouer le dépôt.');
    const cible = path.join(this.dossier, nom);
    if (fs.existsSync(cible)) {
      if (sha(fs.readFileSync(cible)) === h) { this.indexer(h, nom, o.length); return; }
      throw new Refus('NOM_PRIS', `Le nom « ${nom} » est déjà pris par un AUTRE fichier : rien ne s’écrase.`, 'Déposer comme remplacement (nouvelle version) depuis la fiche.');
    }
    fs.writeFileSync(cible + '.part', o); fs.renameSync(cible + '.part', cible); this.indexer(h, nom, o.length);
  }
  indexer(h, nom, taille) { const e = (this.index[h] = this.index[h] || { noms: [], taille }); if (!e.noms.includes(nom)) e.noms.push(nom); this.ecrireIndex(); }
  lire(h) {
    const noms = (this.index[h] && this.index[h].noms) || []; if (!noms.length) return null;
    let present = false;
    for (const n of noms) { const f = path.join(this.dossier, n); if (!fs.existsSync(f)) continue; present = true; const o = fs.readFileSync(f); if (sha(o) === h) return o; }
    if (present) throw new Refus('FICHIER_ALTERE', `Le fichier rangé pour l’empreinte ${h.slice(0, 8)} ne se relit plus à l’identique : il n’est pas servi.`, 'Restaurer le dossier des scans depuis la sauvegarde, ou redéposer le scan.');
    return null;
  }
  blocsRecus(h) { try { return JSON.parse(fs.readFileSync(path.join(this.reception, h + '.json'), 'utf8')).recus; } catch (e) { return 0; } }
  recevoirBloc(c, tailleMax) {
    const { sha: h, nom, nomOrigine, famille, taille, index, total } = c; const o = Buffer.from(c.b64, 'base64');
    if (!nomValide(nom)) throw new Refus('NOM_NON_NORMALISE', `Le nom « ${nom} » n’est pas un nom normalisé.`, 'Rejouer le dépôt depuis la fiche.');
    if (taille > tailleMax) throw new Refus('TAILLE_DEPASSEE', `Le fichier pèse ${taille} octets ; la taille maximale réglée est ${tailleMax}.`, 'Numériser plus bas, ou relever la taille maximale.');
    if (!/^[0-9a-f]{64}$/.test(h)) throw new Refus('EMPREINTE_ILLISIBLE', 'L’empreinte n’est pas un SHA-256.', 'Rejouer le dépôt.');
    if (index < 0 || total < 1 || index >= total) throw new Refus('BLOC_INVALIDE', 'Numéro de bloc hors des bornes.', 'Rejouer le dépôt.');
    fs.mkdirSync(this.reception, { recursive: true });
    const part = path.join(this.reception, h + '.part'), etat = path.join(this.reception, h + '.json');
    let recus = fs.existsSync(etat) && fs.existsSync(part) ? this.blocsRecus(h) : 0;
    if (index < recus) return { recu: recus, attendu: recus, complet: false, rejeu: true };
    if (index > recus) throw new Refus('BLOC_HORS_ORDRE', `Le bloc ${index} arrive avant le bloc ${recus}.`, `Reprendre à partir du bloc ${recus}.`);
    if (index === 0 && fs.existsSync(part)) fs.rmSync(part);
    fs.appendFileSync(part, o); recus++;
    fs.writeFileSync(etat, JSON.stringify({ recus, total, taille, nom }));
    if (recus < total) return { recu: recus, attendu: recus, complet: false };
    const tout = fs.readFileSync(part); fs.rmSync(part); fs.rmSync(etat);
    if (tout.length !== taille) throw new Refus('TAILLE_DIVERGENTE', `Le fichier reçu pèse ${tout.length} octets, la fiche en annonce ${taille}.`, 'Rejouer le dépôt.');
    const r = controlerDepot(tout, famille, tailleMax); if (r) throw r;
    this.deposer(tout, h, nom); return { recu: recus, attendu: recus, complet: true };
  }
  bloc(h, i) {
    const o = this.lire(h); if (!o) return null;
    const total = Math.max(1, Math.ceil(o.length / TAILLE_BLOC));
    if (i < 0 || i >= total) throw new Refus('BLOC_INVALIDE', 'Numéro de bloc hors des bornes.', 'Relire depuis le bloc 0.');
    return { octets: o.subarray(i * TAILLE_BLOC, Math.min(o.length, (i + 1) * TAILLE_BLOC)), total, taille: o.length, nom: this.index[h].noms[0] };
  }
  controler() {
    const alteres = [], manquants = []; let ok = 0;
    for (const [h, e] of Object.entries(this.index)) for (const n of e.noms) {
      const f = path.join(this.dossier, n);
      if (!fs.existsSync(f)) manquants.push(n); else if (sha(fs.readFileSync(f)) !== h) alteres.push(n); else ok++;
    }
    return { verifies: ok, alteres, manquants, complet: !alteres.length && !manquants.length };
  }
  sauvegarder(dest) {
    fs.mkdirSync(dest, { recursive: true }); const manifeste = []; const copies = [], inchanges = [], alteres = [], manquants = [];
    for (const [h, e] of Object.entries(this.index)) for (const n of e.noms) {
      const src = path.join(this.dossier, n); if (!fs.existsSync(src)) { manquants.push(n); continue; }
      const o = fs.readFileSync(src); if (sha(o) !== h) { alteres.push(n); continue; }
      const dst = path.join(dest, n);
      if (fs.existsSync(dst) && sha(fs.readFileSync(dst)) === h) inchanges.push(n);
      else { fs.writeFileSync(dst + '.part', o); if (sha(fs.readFileSync(dst + '.part')) !== h) { fs.rmSync(dst + '.part'); alteres.push(n); continue; } fs.renameSync(dst + '.part', dst); copies.push(n); }
      manifeste.push({ nom: n, sha256: h, taille: o.length });
    }
    fs.writeFileSync(path.join(dest, 'MANIFESTE.json'), JSON.stringify({ ecritLe: new Date().toISOString(), fichiers: manifeste }, null, 1));
    return { destination: dest, copies: copies.length, inchanges: inchanges.length, alteres, manquants, total: manifeste.length };
  }
  restaurer(source) {
    const mf = path.join(source, 'MANIFESTE.json');
    if (!fs.existsSync(mf)) throw new Refus('SAUVEGARDE_SANS_MANIFESTE', `Le dossier « ${source} » ne contient pas de MANIFESTE.json : ce n’est pas une sauvegarde des scans.`, 'Choisir le dossier de sauvegarde des scans.');
    const liste = JSON.parse(fs.readFileSync(mf, 'utf8')).fichiers; fs.mkdirSync(this.dossier, { recursive: true });
    const restaures = [], presents = [], refuses = [], conflits = [], absents = [];
    for (const e of liste) {
      if (!nomValide(e.nom)) { refuses.push(e.nom); continue; }
      const src = path.join(source, e.nom); if (!fs.existsSync(src)) { absents.push(e.nom); continue; }
      const o = fs.readFileSync(src); if (sha(o) !== e.sha256) { refuses.push(e.nom); continue; }
      const dst = path.join(this.dossier, e.nom);
      if (fs.existsSync(dst)) { (sha(fs.readFileSync(dst)) === e.sha256 ? presents : conflits).push(e.nom); continue; }
      fs.writeFileSync(dst + '.part', o); if (sha(fs.readFileSync(dst + '.part')) !== e.sha256) { fs.rmSync(dst + '.part'); refuses.push(e.nom); continue; }
      fs.renameSync(dst + '.part', dst); restaures.push(e.nom);
    }
    this.reconstruire();
    return { restaures: restaures.length, presents: presents.length, refuses, conflits, absents, total: liste.length, complet: !refuses.length && !conflits.length && !absents.length };
  }
}

module.exports = { Stock, Refus, sha, nomValide, controlerDepot, formatDes, TAILLE_BLOC, TAILLE_DEFAUT };
