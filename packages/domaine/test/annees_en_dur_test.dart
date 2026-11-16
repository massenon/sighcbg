// CLIQUET « AUCUNE ANNÉE EN DUR QUI DÉCIDE » (lot 0 de l'inventaire des valeurs en dur, 16/11/2026 — E3840 ; à livrer avant le 1er janvier 2027).
//
// Une année littérale 2024-2030 qui DÉCIDE (un compteur « de l'année 2026 », un code patient « …/26 », un exercice réputé clos, une date de jeu par défaut)
// devient fausse le 1er janvier suivant. Le détecteur est celui de l'inventaire (`tools/baguidi/inventaire-en-dur.mjs`, famille A : il sait distinguer
// une citation datée, une semence documentée, un exemple d'aide ou un libellé long d'une valeur qui décide) ; la liste des sites tolérés est FERMÉE et
// motivée (`tools/baguidi/annees-tolerees.json`). Ce test le fait tourner à chaque `dart test` du domaine : il échoue si une année réapparaît, si une
// valeur tolérée se répand, ou si un site toléré corrigé reste dans la liste (le cliquet ne remonte jamais). La même garde existe en `node --test`
// (`tools/baguidi/inventaire-en-dur.test.mjs`), qui prouve aussi que le cliquet sait échouer.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('aucune année en dur qui décide dans le code de production, hors la liste fermée et motivée', () async {
    final script = File('../../tools/baguidi/inventaire-en-dur.mjs');
    expect(script.existsSync(), isTrue, reason: 'le détecteur de l’inventaire est introuvable depuis packages/domaine');
    final ProcessResult r;
    try {
      r = await Process.run('node', [script.path, '--cliquet', '--famille=A']);
    } on ProcessException catch (e) {
      fail('Node.js est requis par cette garde (le dépôt l’exige déjà, engines >= 22) : $e');
    }
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}', contains('0 nouvelle valeur en dur'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
