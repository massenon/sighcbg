// GARDE DU LOT 0 (E3840) : aucune année littérale 2024-2030 qui DÉCIDE ne réapparaît dans le code de production (`lib` du poste, du domaine, de la
// synchronisation et du mobile ; relais Laravel), hors la liste fermée et motivée `annees-tolerees.json`.
//   node --test tools/baguidi/inventaire-en-dur.test.mjs
// Le premier test fait tourner le cliquet sur le dépôt réel ; les suivants prouvent qu'il PEUT échouer (un cliquet qui ne rougit jamais ne protège rien).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { analyser, cliquet, lireToleres } from './inventaire-en-dur.mjs';

const res = analyser();
const toleres = lireToleres('A');

test('le dépôt : aucune année en dur qui décide hors de la liste fermée, et aucune tolérance périmée', () => {
  const r = cliquet(res.candidats, toleres, 'A');
  assert.deepEqual(r.nouveaux.map((c) => `${c.fichier}:${c.ligne} « ${c.valeur} »`), [], 'une année en dur est apparue : la lire dans l’horloge, la date de la pièce ou un paramètre daté');
  assert.deepEqual(r.depassements, []);
  assert.deepEqual(r.perimes.map((t) => `${t.fichier} « ${t.valeur} »`), [], 'un site toléré a été corrigé : le retirer de annees-tolerees.json');
});

test('chaque tolérance porte un motif et un nombre de sites', () => {
  for (const t of toleres) {
    assert.ok(t.motif.length > 20, `motif trop court : ${JSON.stringify(t)}`);
    assert.ok(Number.isInteger(t.sites) && t.sites >= 1);
  }
});

test('le cliquet ROUGIT sur une année qui réapparaît (ex. `codePatient(n, 2026)`)', () => {
  const faux = { famille: 'A', statut: 'defaut', fichier: 'packages/sync_dart/lib/src/mere.dart', ligne: 481, valeur: '2026', contexte: "champs['code'] = codePatient(n, 2026);" };
  const r = cliquet([...res.candidats, faux], toleres, 'A');
  assert.equal(r.nouveaux.length, 1);
  assert.equal(r.nouveaux[0].fichier, faux.fichier);
});

test('le cliquet ROUGIT quand une valeur tolérée se répand, et quand un site toléré corrigé n’est pas retiré de la liste', () => {
  const t = toleres[0];
  const copie = { ...res.candidats.find((c) => c.famille === 'A' && c.statut === 'defaut' && c.fichier === t.fichier && String(c.valeur) === t.valeur), ligne: 9999 };
  assert.equal(cliquet([...res.candidats, copie], toleres, 'A').depassements.length, 1);
  const sansLui = res.candidats.filter((c) => !(c.famille === 'A' && c.fichier === t.fichier && String(c.valeur) === t.valeur));
  assert.equal(cliquet(sansLui, toleres, 'A').perimes.length, 1);
});

test('un candidat écarté (citation, semence, libellé long) ne compte pas : seul le statut « defaut » décide', () => {
  const cite = { famille: 'A', statut: 'citation', fichier: 'x.dart', ligne: 1, valeur: 'décision du 16/11/2026', contexte: '' };
  assert.equal(cliquet([...res.candidats, cite], toleres, 'A').nouveaux.length, 0);
});
