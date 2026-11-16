'use strict';
/* =============================================================================
 * SIGH-CBG : la destination « DOSSIER DISTANT MONTÉ » de la sauvegarde hors site (lot BAK, ADR-0008), version de RÉFÉRENCE (Node).
 * Même format et mêmes refus que `DestinationDossier` du moteur Dart (`packages/sync_dart/lib/src/sauvegarde_horssite.dart`) : une copie faite par l'un se lit par l'autre.
 * Blocs : `blocs/<2>/<id>`, copies : `copies/<id>.json`, écritures atomiques. Le dossier n'est JAMAIS créé : un disque absent se créerait sur le disque des données.
 * Aucun quota ni limite de requête : l'espace est celui du dossier, inconnu de ce poste (absent de l'état, jamais compté comme zéro).
 * ========================================================================== */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const R = require('./sauvegarde-regles');
const { ErreurSauvegarde } = require('./sauvegarde-hs');

const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const ID = /^[0-9a-f]{64}$/;
const e = (code, motif, geste, plus) => new ErreurSauvegarde(R.refus(code, motif, geste, plus));

class DestDossier {
  constructor(racine, { plancher = 2, plafond = 60 } = {}) { this.racine = racine; this.plancher = plancher; this.plafond = plafond; this.libelle = 'dossier distant'; }
  _bloc(id) { return path.join(this.racine, 'blocs', id.slice(0, 2), id); }
  _copie(id) { return path.join(this.racine, 'copies', id + '.json'); }
  _exiger() { if (!fs.existsSync(this.racine)) throw e('DOSSIER_INTROUVABLE', `« ${this.racine} » n'existe pas ou n'est pas monté`, 'Brancher ou monter le dossier distant : le poste ne le crée jamais.'); }
  _lire(id) { if (!fs.existsSync(this._copie(id))) throw e('COPIE_INCONNUE', 'cette copie n\'existe pas dans le dossier distant', 'Relire la liste des copies.'); return JSON.parse(fs.readFileSync(this._copie(id), 'utf8')); }
  _ecrire(c) { fs.mkdirSync(path.join(this.racine, 'copies'), { recursive: true }); const t = this._copie(c.id) + '.tmp'; fs.writeFileSync(t, JSON.stringify(c)); fs.renameSync(t, this._copie(c.id)); }
  _toutes() { const d = path.join(this.racine, 'copies'); return fs.existsSync(d) ? fs.readdirSync(d).filter((n) => n.endsWith('.json')).map((n) => JSON.parse(fs.readFileSync(path.join(d, n), 'utf8'))) : []; }
  async etat() {
    this._exiger(); const cs = this._toutes(); const copies = {};
    for (const t of R.TYPES) {
      const c = cs.filter((x) => x.type === t && x.etat === 'complete').sort((a, b) => b.date - a.date);
      const n = (s) => cs.filter((x) => x.type === t && x.etat === s).length;
      copies[t] = { completes: n('complete'), archivees: n('archivee'), purgees: 0, ouvertes: n('ouverte'), derniere: c[0] || null };
    }
    return { format: R.FORMAT, limites: { rotationPlancher: this.plancher, rotationPlafond: this.plafond }, copies };
  }
  async manquants(ids) { this._exiger(); return ids.filter((i) => ID.test(i) && !fs.existsSync(this._bloc(i))); }
  async deposerBloc(id, octets) {
    this._exiger();
    if (!ID.test(id)) throw e('BLOC_ID_INVALIDE', 'l\'identifiant d\'un bloc est une empreinte SHA-256 en hexadécimal', 'Utiliser l\'empreinte du bloc chiffré.');
    if (!octets.length) throw e('BLOC_TROP_GROS', 'un bloc vide n\'est pas déposé', 'Réduire la taille de bloc du réglage.');
    if (sha(octets) !== id) throw e('BLOC_ALTERE_EN_ROUTE', 'les octets reçus n\'ont pas l\'empreinte annoncée : le bloc a été altéré en route', 'Renvoyer le bloc.');
    const suspect = R.blocSuspect(octets); if (suspect) throw new ErreurSauvegarde(suspect);
    const f = this._bloc(id);
    if (fs.existsSync(f)) return { id, taille: octets.length, rejeu: true };
    fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f + '.tmp', octets); fs.renameSync(f + '.tmp', f);
    return { id, taille: octets.length };
  }
  async ouvrir(id, type, date, garder) {
    this._exiger();
    if (!ID.test(id) || !R.TYPES.includes(type)) throw e('COPIE_INVALIDE', 'identifiant ou type de copie invalide', 'Utiliser l\'identifiant calculé par le poste mère et un type connu.');
    const r = R.rotation([], garder, this.plancher, this.plafond); if (!r.ok) throw new ErreurSauvegarde(r);
    if (fs.existsSync(this._copie(id))) return { etat: this._lire(id).etat, rejeu: true };
    this._ecrire({ id, type, etat: 'ouverte', date, recu: Date.now(), garder, nb_blocs: 0, taille: 0, liens: [], racine: [], motif: null });
    return { etat: 'ouverte' };
  }
  async attacher(id, ids) {
    this._exiger(); const c = this._lire(id);
    if (c.etat === 'complete') return;
    if (c.etat !== 'ouverte') throw e('COPIE_NON_OUVERTE', `cette copie est ${c.etat}`, 'Rouvrir la copie par le poste mère.');
    const manque = await this.manquants(ids);
    if (manque.length) throw e('BLOC_MANQUANT', `${manque.length} bloc(s) ne sont pas dans le dossier distant`, 'Déposer d\'abord les blocs manquants.', { manquants: manque.slice(0, 50) });
    const liens = [...new Set([...c.liens, ...ids])]; c.liens = liens; c.nb_blocs = liens.length; c.taille = liens.reduce((s, i) => s + fs.statSync(this._bloc(i)).size, 0);
    this._ecrire(c);
  }
  async valider(id, racine) {
    this._exiger(); const c = this._lire(id);
    if (c.etat === 'complete') return { etat: 'complete', rejeu: true, archivees: [] };
    if (c.etat !== 'ouverte') throw e('COPIE_NON_OUVERTE', `cette copie est ${c.etat}`, 'Rouvrir la copie par le poste mère.');
    if (!racine.length) throw e('RACINE_ABSENTE', 'une copie complète désigne les blocs de son manifeste', 'Déposer et désigner les blocs du manifeste.');
    const liens = new Set(c.liens); const manque = racine.filter((i) => !liens.has(i));
    if (manque.length) throw e('BLOC_MANQUANT', `${manque.length} bloc(s) du manifeste ne sont pas rattachés à cette copie`, 'Rattacher les blocs du manifeste.', { manquants: manque.slice(0, 50) });
    c.etat = 'complete'; c.racine = racine; this._ecrire(c);
    const r = R.rotation(this._toutes().filter((x) => x.type === c.type), c.garder, this.plancher, this.plafond);
    for (const a of r.archiver) { const x = this._lire(a); x.etat = 'archivee'; this._ecrire(x); }
    return { etat: 'complete', archivees: r.archiver };
  }
  async copies(type) { this._exiger(); return this._toutes().filter((c) => !type || c.type === type).sort((a, b) => b.date - a.date).map((c) => { const x = { ...c }; delete x.liens; return x; }); }
  async copie(id) {
    this._exiger(); const c = this._lire(id);
    if (c.etat !== 'complete' && c.etat !== 'archivee') throw e('COPIE_INCOMPLETE', 'cette copie n\'a jamais été validée', 'Choisir une copie complète.');
    const x = { ...c }; delete x.liens; return x;
  }
  async bloc(id) { this._exiger(); const f = this._bloc(id); if (!fs.existsSync(f)) throw e('BLOC_ABSENT', 'ce bloc n\'est pas (ou plus) dans le dossier distant', 'Choisir une autre copie.'); return fs.readFileSync(f); }
}
module.exports = { DestDossier };
