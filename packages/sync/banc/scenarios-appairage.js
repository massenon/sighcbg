'use strict';
/* Scénario APP1 (Direction de Baguidi, 18/11/2026 : « plus de valeur en dur — toutes les valeurs seront des réglages ou paramétrables ») : la DURÉE DE VALIDITÉ d'un code d'appairage est un RÉGLAGE de la
   mère (`mere.validiteCodeAppairageMinutes`), daté et borné, relu à chaque émission, et RENDU AVEC LE CODE (`validite_s`, `expire`) pour un poste ordinaire COMME pour un mobile. Les écrans la lisent
   dans cette réponse : aucun n'écrit « 15 minutes ». Miroir de `sync_dart/lib/src/mere.dart` (`Mere.validiteCodeMs`) et de `domaine/lib/src/mere/reprise_poste_regles.dart` (`cleValiditeCodeAppairage`).
   Ici, SANS surcharge de lancement (`--code-ttl`) : c'est le réglage qui décide. Ce que les écrans disent de cette durée (ou de son absence) est éprouvé par les tests du poste. */
const P = require('./parametres');

const CLE = 'mere.validiteCodeAppairageMinutes';
const DEF = { cle: CLE, famille: 'mere', type: 'entier', defaut: 15, source: 'fixture du banc (miroir de la définition du domaine)' };
const local = (d) => `${String(d.getFullYear()).padStart(4, '0')}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

module.exports = ({ monde, verifier, attendre, dormir, titre }) => ({
  async APP1() {
    titre('APP-APP1 · validité d\'un code d\'appairage : réglage de la mère (daté, borné), annoncé avec le code (poste ordinaire et mobile), jamais écrit par un écran');
    const m = await monde({ relais: true });
    const poste = async (etiquette) => (await m.mere.admin('POST', '/admin/code', { role: 'fileul', etiquette })).json;
    const mobile = async (etiquette) => (await m.mere.admin('POST', '/admin/code-mobile', { etiquette, profil: 'reception' })).json;
    const regler = (valeur, dateEffet, version) => {
      const v = P.proposer({ definition: DEF, versions: [], usages: [], valeur, dateEffet, auteur: 'admin', creeLe: '2026-11-18T08:00:00Z', motif: 'banc' });
      v.fiche.version = version;
      return m.mere.admin('POST', '/admin/referentiel', { collection: 'parametres', fiche: `${CLE}@${dateEffet}@${version}`, champs: v.fiche }).then((r) => r.json);
    };
    const aujourdhui = local(new Date());
    const hier = local(new Date(Date.now() - 86400000));
    const demain = local(new Date(Date.now() + 86400000));

    /* 1. Aucun réglage posé : la valeur d'attente de la définition, annoncée avec le code. */
    const a0 = await poste('A0');
    const b0 = await mobile('T0');
    verifier('sans réglage posé, la mère annonce la valeur d\'attente (15 minutes) avec le code d\'un POSTE', a0.validite_s === 900 && typeof a0.expire === 'number', a0);
    verifier('… et avec le code d\'un MOBILE (même réponse, jamais « 15 minutes » écrit par l\'écran)', b0.validite_s === 900 && typeof b0.expire === 'number' && typeof b0.cle === 'string', b0);
    verifier('l\'échéance annoncée tient la durée annoncée', Math.abs((a0.expire - Date.now()) - a0.validite_s * 1000) < 5000, a0);

    /* 2. Un réglage daté d'hier s'applique aux codes émis ensuite ; celui d'avant garde l'échéance qu'il a reçue. */
    const r1 = await regler(30, hier, 1);
    verifier('la mère accepte la version datée du réglage', r1.statut === 'acceptee', r1);
    const a1 = await poste('A1');
    const b1 = await mobile('T1');
    verifier('le réglage (30 minutes) est annoncé pour un poste ET pour un mobile, dès l\'émission suivante', a1.validite_s === 1800 && b1.validite_s === 1800, [a1, b1]);
    verifier('le code émis AVANT le réglage garde son échéance (900 s)', a0.validite_s === 900);

    /* 3. Une version à venir ne s'applique pas encore. */
    const r2 = await regler(5, demain, 2);
    verifier('une version datée de demain est acceptée', r2.statut === 'acceptee', r2);
    verifier('… mais ne s\'applique pas encore : la durée annoncée reste celle d\'aujourd\'hui (30 minutes)', (await poste('A2')).validite_s === 1800);

    /* 4. Borné : une valeur hors bornes retombe sur la valeur d'attente, jamais sur zéro ni sur une durée absurde. */
    const r3 = await regler(100000, aujourdhui, 3);
    verifier('une version hors bornes est stockée telle quelle par la mère (le contrôle de bornes est à la lecture)', r3.statut === 'acceptee', r3);
    const a3 = await poste('A3');
    verifier('hors bornes (100000 minutes) : la valeur d\'attente (15 minutes), jamais la valeur absurde', a3.validite_s === 900, a3);
    const r4 = await regler(20, aujourdhui, 4);
    verifier('une version plus récente et valide reprend la main (20 minutes)', r4.statut === 'acceptee' && (await poste('A4')).validite_s === 1200 && (await mobile('T4')).validite_s === 1200, r4);

    /* 5. Le code émis sous le réglage sert vraiment (le réglage n'est pas qu'affiché). */
    const f = await m.fileul('F1', { sansAppairage: true });
    const c = await poste('F1');
    const ap = await f.post('/appairer', { code: c.code });
    verifier('un code émis sous le réglage appaire un poste', ap.status === 200, ap.json);
    await m.fermer();
  },
});
