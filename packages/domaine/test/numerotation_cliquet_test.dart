// LE CLIQUET DE LA FAMILLE E (préfixes et formats de numérotation), lot 2 du 16/11/2026 : le balayage de l'inventaire des valeurs en dur
// (`tools/baguidi/inventaire-en-dur.mjs --cliquet --famille=E`) doit trouver ZÉRO préfixe de pièce écrit dans le code de production des quatre racines Dart
// et du relais. Toute référence passe par la fabrique du référentiel (`numeroSuivant`, `numeroFormate`, `numeroDerive`). Le test fait aussi mordre le
// cliquet : un préfixe millésimé injecté dans le balayage le fait échouer en nommant le fichier — un cliquet qui ne peut pas échouer ne protège rien.
import 'dart:io';

import 'package:test/test.dart';

/// La racine du dépôt (le test s'exécute dans `packages/domaine`).
final String racine = Directory.current.parent.parent.path;

ProcessResult cliquet([List<String> plus = const []]) =>
    Process.runSync('node', ['tools/baguidi/inventaire-en-dur.mjs', '--cliquet', '--famille=E', ...plus], workingDirectory: racine);

void main() {
  test('aucun préfixe de pièce en dur : le cliquet de la famille E passe', () {
    final r = cliquet();
    expect(r.exitCode, 0, reason: 'sortie : ${r.stdout}\n${r.stderr}');
    expect('${r.stdout}', contains('conformes'));
  });

  test('le cliquet MORD : un préfixe millésimé réintroduit le fait échouer, fichier et ligne nommés', () {
    final dossier = Directory.systemTemp.createTempSync('cliquet-e-');
    try {
      final sonde = File('${dossier.path}/sonde.dart')..writeAsStringSync("String sonde(int n) => 'BEB-2026-\${n.toString().padLeft(4, '0')}';\n");
      final r = cliquet(['--injecter=packages/domaine/lib/src/achats/sonde_cliquet.dart:${sonde.path}']);
      expect(r.exitCode, 1, reason: 'sortie : ${r.stdout}\n${r.stderr}');
      expect('${r.stderr}', contains('packages/domaine/lib/src/achats/sonde_cliquet.dart:1'));
      expect('${r.stderr}', contains('numeroSuivant'), reason: 'le refus dit où la référence doit se construire');
    } finally {
      dossier.deleteSync(recursive: true);
    }
  });
}
