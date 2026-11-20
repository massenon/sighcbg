'use strict';
/* Scénario SMS1 (ADR-0009, décision de la Direction de Baguidi du 16/11/2026) : LES SMS PAR LE RELAIS, éprouvés sur le contrat du relais (celui de référence,
   ou, avec SIGH_RELAIS=laravel, le relais Laravel). La mère y est simulée par ses en-têtes : x-mere et la signature du corps exact.

   Ce que le scénario éprouve :
     1. les BARRIÈRES : sans secret 403, signature fausse 401, schéma fermé (champ en trop, numéro local, texte trop long) 422, sans jamais répéter la valeur reçue ;
     2. le DÉPÔT : en attente, idempotent par identifiant ;
     3. l'ENVOI par la tâche planifiée (simulée par le crochet du banc) puis l'EFFACEMENT du numéro et du texte, statut suivi par la mère ;
     4. CINQ TENTATIVES au plus, délais respectés, puis échec et effacement ;
     5. le PLAFOND du jour : le dépôt de trop est refusé 429 plafond_atteint ;
     6. le JOURNAL technique ne porte ni numéro ni texte ;
     7. la DURÉE DE VALIDITÉ (E5204) : un SMS retenu par le plafond ne part pas le lendemain s'il est périmé — statut « expire », numéro et texte effacés. */
const crypto = require('node:crypto');

const SECRET = 'secret-mere';
const TEXTE = 'Rappel : rendez-vous a la clinique le 18/11/2026 a 09h00. Pour modifier, appelez l accueil.';
const signer = (corps) => 'sha256=' + crypto.createHmac('sha256', SECRET).update(JSON.stringify(corps)).digest('hex');
const numero = (i) => '+229000' + String(i).padStart(5, '0');
const idSms = (i) => 'sms-banc-' + String(i).padStart(6, '0');

module.exports = ({ monde, verifier, titre }) => ({
  async SMS1() {
    titre('SMS-SMS1 · SMS par le relais : barrières (secret, signature, schéma fermé), dépôt idempotent, envoi puis effacement, cinq tentatives, plafond du jour, journal sans contenu');
    const m = await monde({ relais: true });
    const r = m.relais;
    const deposer = (corps, ent) => r.brut('POST', '/mere/sms', corps, Object.assign({ 'x-mere': SECRET, 'x-signature': signer(corps) }, ent || {}));
    const sms = (i, plus) => ({ sms: Object.assign({ id: idSms(i), numero: numero(i), texte: TEXTE }, plus || {}) });
    const statuts = async (ids) => { const c = { ids }; return (await r.brut('POST', '/mere/sms/statuts', c, { 'x-mere': SECRET, 'x-signature': signer(c) })).json.statuts || []; };
    const tout = async () => (await r.brut('GET', '/banc/sms/tout')).json;

    // 1. barrières
    const sansMere = await r.brut('POST', '/mere/sms', sms(1));
    verifier('sans le secret de la mère, le dépôt est refusé (403 mere_requise)', sansMere.status === 403 && sansMere.json.code === 'mere_requise', sansMere);
    const fausse = await deposer(sms(1), { 'x-signature': 'sha256=' + '0'.repeat(64) });
    verifier('une signature fausse est refusée (401 signature_invalide)', fausse.status === 401 && fausse.json.code === 'signature_invalide', fausse);
    const enTrop = await deposer(sms(1, { patient: 'NOM-SENTINELLE-SMS1' }));
    verifier('un champ en trop est refusé (422 sms_invalide) sans répéter la valeur reçue', enTrop.status === 422 && enTrop.json.code === 'sms_invalide' && !JSON.stringify(enTrop.json).includes('SENTINELLE'), enTrop);
    const local = await deposer(sms(1, { numero: '0100000001' }));
    verifier('un numéro qui n\'est pas au format international est refusé, sans être répété', local.status === 422 && !JSON.stringify(local.json).includes('0100000001'), local);
    const long = await deposer(sms(1, { texte: 'a'.repeat(321) }));
    verifier('un texte de plus de 320 caractères est refusé', long.status === 422 && long.json.code === 'sms_invalide', long);
    verifier('rien d\'un dépôt refusé n\'est enregistré', (await tout()).lignes.length === 0);

    // 2. dépôt idempotent
    const ok = await deposer(sms(1));
    verifier('un SMS signé et conforme est déposé en attente', ok.status === 200 && ok.json.sms && ok.json.sms.statut === 'en_attente' && ok.json.rejeu === false, ok);
    verifier('la réponse du dépôt ne répète ni le numéro ni le texte', !JSON.stringify(ok.json).includes(numero(1)) && !JSON.stringify(ok.json).includes('rendez-vous'), ok.json);
    const rejeu = await deposer(sms(1));
    verifier('un dépôt rejoué rend la même ligne, sans doublon', rejeu.status === 200 && rejeu.json.rejeu === true && (await tout()).lignes.length === 1, rejeu);
    const etat0 = await r.brut('GET', '/mere/sms/etat', null, { 'x-mere': SECRET });
    verifier('l\'état (réservé à la mère) affiche le plafond du jour et l\'attente, sans contenu', etat0.status === 200 && etat0.json.plafond_jour > 0 && etat0.json.en_attente === 1 && etat0.json.tentatives_max === 5, etat0.json);
    const etatAnonyme = await r.brut('GET', '/mere/sms/etat');
    verifier('sans le secret, l\'état est refusé', etatAnonyme.status === 403, etatAnonyme);
    const s0 = await statuts([idSms(1), 'sms-banc-inconnu']);
    verifier('la mère suit le statut : en attente, et « inconnu » pour un identifiant jamais déposé', s0.length === 2 && s0[0].statut === 'en_attente' && s0[1].statut === 'inconnu', s0);

    // 3. envoi puis effacement
    const t1 = await r.brut('POST', '/banc/sms/tourner', { pilote: 'journal' });
    verifier('le passage du cron envoie le SMS (pilote journal)', t1.status === 200 && t1.json.envoyes === 1, t1.json);
    const l1 = (await tout()).lignes.find((l) => l.uid === idSms(1));
    verifier('après envoi, le NUMÉRO et le TEXTE sont effacés ; restent statut, tentatives et horodatages', l1 && l1.statut === 'envoye' && l1.numero === null && l1.texte === null && l1.envoye_le > 0 && Number(l1.tentatives) === 1, l1);
    const s1 = await statuts([idSms(1)]);
    verifier('la mère lit le statut « envoyé »', s1[0] && s1[0].statut === 'envoye', s1);

    // 4. cinq tentatives au plus
    await deposer(sms(2));
    let avance = 0; let suite = true;
    for (let i = 1; i <= 4; i++) {
      const t = await r.brut('POST', '/banc/sms/tourner', { pilote: 'echec', avance_ms: avance });
      const l = (await tout()).lignes.find((x) => x.uid === idSms(2));
      suite = suite && t.json.echecs === 1 && l.statut === 'en_attente' && Number(l.tentatives) === i && l.numero !== null;
      const immediat = await r.brut('POST', '/banc/sms/tourner', { pilote: 'echec', avance_ms: avance });
      suite = suite && immediat.json.echecs === 0;
      avance = Number(l.prochain_essai_le) - Date.now() + 1000;
    }
    verifier('quatre échecs : le SMS reste en attente, le délai entre deux tentatives est respecté', suite);
    const t5 = await r.brut('POST', '/banc/sms/tourner', { pilote: 'echec', avance_ms: avance });
    const l2 = (await tout()).lignes.find((x) => x.uid === idSms(2));
    verifier('au cinquième échec : statut « echec », numéro et texte effacés, plus aucune tentative', t5.json.abandons === 1 && l2.statut === 'echec' && Number(l2.tentatives) === 5 && l2.numero === null && l2.texte === null, l2);
    const t6 = await r.brut('POST', '/banc/sms/tourner', { pilote: 'echec', avance_ms: avance + 86400000 });
    verifier('après le cinquième échec, rien n\'est plus tenté', t6.json.echecs === 0 && t6.json.abandons === 0, t6.json);

    // 5. plafond du jour
    const e = (await r.brut('GET', '/mere/sms/etat', null, { 'x-mere': SECRET })).json;
    const place = e.plafond_jour - e.envoyes_aujourdhui - e.en_attente;
    let tous = true;
    for (let i = 0; i < place; i++) tous = (await deposer(sms(100 + i))).status === 200 && tous;
    const deTrop = await deposer(sms(100 + place));
    verifier(`le plafond du jour (${e.plafond_jour}) est tenu : les ${place} dépôts permis passent, le suivant est refusé (429 plafond_atteint)`, tous && deTrop.status === 429 && deTrop.json.code === 'plafond_atteint', deTrop);

    // 7. durée de validité : les SMS que le plafond retient sont périmés 25 heures plus tard (validité par défaut : 24 heures)
    const enAttente = (await tout()).lignes.filter((l) => l.statut === 'en_attente').length;
    const lendemain = await r.brut('POST', '/banc/sms/tourner', { pilote: 'journal', avance_ms: 25 * 3600000 });
    const apres = (await tout()).lignes;
    const perimes = apres.filter((l) => l.statut === 'expire');
    verifier(`un SMS en attente dont la validité est dépassée est ABANDONNÉ (${enAttente} en attente → ${perimes.length} expirés), jamais envoyé le lendemain`, enAttente > 0 && lendemain.json.expires === enAttente && perimes.length === enAttente && lendemain.json.envoyes === 0, lendemain.json);
    verifier('un SMS expiré a son numéro et son texte EFFACÉS, un statut nommé et aucune tentative', perimes.every((l) => l.numero === null && l.texte === null && l.derniere_erreur === 'expire' && Number(l.tentatives) === 0 && l.envoye_le === null), perimes[0]);
    const sExp = await statuts([idSms(100)]);
    verifier('la mère lit le statut « expire », sans numéro ni texte', sExp[0] && sExp[0].statut === 'expire' && !JSON.stringify(sExp).includes(numero(100)), sExp);
    const eVal = (await r.brut('GET', '/mere/sms/etat', null, { 'x-mere': SECRET })).json;
    verifier('l\'état annonce la durée de validité réglée', eVal.validite_heures >= 1, eVal);

    // 6. journal technique
    const audit = JSON.stringify((await tout()).audit);
    verifier('le journal technique trace dépôts, envois, échecs, refus et expirations', ['sms_depose', 'sms_envoye', 'sms_echec', 'sms_refuse', 'sms_expire'].every((a) => audit.includes(a)), audit.slice(0, 300));
    verifier('le journal technique ne porte ni numéro ni texte', !/\+?229000\d{5}/.test(audit) && !audit.includes('rendez-vous') && !audit.includes('SENTINELLE'), audit.slice(0, 300));
    await m.fermer();
  },
});
