#!/usr/bin/env node
// MESURE (jamais un réglage) du volume que la sauvegarde hors site demanderait au relais (Q32, décision du 15/11/2026 : « mesurer d'abord sur l'hébergement réel, ne rien coder en dur »).
// Aucune limite de 5 Gio n'est écrite dans le code : le quota réel de l'hébergement se passe en argument (--quota-gio), relevé à l'hébergeur ; sans lui l'outil donne le BESOIN et dit « quota à relever ».
//
//   node tools/baguidi/mesurer-quota-relais.mjs --magasin <fichier ou dossier> --fichiers <dossier des scans> [--copies-magasin 7] [--copies-fichiers 14] [--bloc 1048576] [--quota-gio <n>] [--json]
import { statSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const args = process.argv.slice(2);
const val = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 && i + 1 < args.length ? args[i + 1] : d; };
const SURCOUT_BLOC = 28; // octets ajoutés par bloc chiffré (même valeur que `shSurcoutBloc`, packages/domaine/lib/src/sauvegarde/sauvegarde_horssite.dart)

function taille(chemin) {
  if (!chemin) return { octets: 0, fichiers: 0, absent: true };
  let st;
  try { st = statSync(chemin); } catch { return { octets: 0, fichiers: 0, absent: true }; }
  if (!st.isDirectory()) return { octets: st.size, fichiers: 1 };
  let octets = 0, fichiers = 0;
  for (const e of readdirSync(chemin, { withFileTypes: true })) {
    const t = taille(join(chemin, e.name));
    octets += t.octets; fichiers += t.fichiers;
  }
  return { octets, fichiers };
}

const bloc = parseInt(val('bloc', '1048576'), 10);
const cm = parseInt(val('copies-magasin', '7'), 10);
const cf = parseInt(val('copies-fichiers', '14'), 10);
const m = taille(val('magasin')), f = taille(val('fichiers'));
const chiffre = (o) => o + Math.ceil(o / bloc) * SURCOUT_BLOC;
// Borne HAUTE : chaque copie comptée comme complète. Les blocs sont partagés entre copies : la réalité est plus basse, d'un facteur qui ne se mesure qu'avec le rythme de changement.
const haut = chiffre(m.octets) * cm + chiffre(f.octets) * cf;
// Borne BASSE : une seule copie de chaque (aucun changement entre deux copies).
const bas = chiffre(m.octets) + chiffre(f.octets);
const gio = (o) => (o / 1024 / 1024 / 1024).toFixed(3);
const quota = val('quota-gio');
const sortie = {
  magasin: { octets: m.octets, fichiers: m.fichiers, absent: !!m.absent },
  fichiers: { octets: f.octets, fichiers: f.fichiers, absent: !!f.absent },
  blocOctets: bloc, copiesMagasin: cm, copiesFichiers: cf,
  besoinBasGio: Number(gio(bas)), besoinHautGio: Number(gio(haut)),
  quotaGio: quota == null ? null : Number(quota),
  verdict: quota == null ? 'quota à relever auprès de l’hébergeur (cPanel : « Utilisation du disque », ou `quota -s`) puis relancer avec --quota-gio'
    : (haut / 1024 ** 3 <= Number(quota) ? 'tient, même dans la borne haute' : (bas / 1024 ** 3 <= Number(quota) ? 'tient seulement si les copies partagent leurs blocs : surveiller, ou réduire les copies / choisir un dossier distant' : 'NE TIENT PAS : réduire les copies, choisir un dossier distant ou relever le quota')),
};
if (args.includes('--json')) console.log(JSON.stringify(sortie, null, 2));
else {
  console.log(`Magasin : ${gio(m.octets)} Gio (${m.fichiers} fichier(s))${m.absent ? ' — CHEMIN ABSENT' : ''}`);
  console.log(`Fichiers numérisés : ${gio(f.octets)} Gio (${f.fichiers} fichier(s))${f.absent ? ' — CHEMIN ABSENT' : ''}`);
  console.log(`Besoin au relais : de ${sortie.besoinBasGio} Gio (une copie) à ${sortie.besoinHautGio} Gio (${cm} copies du magasin, ${cf} des fichiers, aucun bloc partagé)`);
  console.log(`Quota de l'hébergement : ${quota ?? 'non relevé'}${quota ? ' Gio' : ''}`);
  console.log(`Verdict : ${sortie.verdict}`);
}
