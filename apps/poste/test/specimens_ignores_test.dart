import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// L'outil de spécimens (`tool/specimens/`) ne doit JAMAIS tourner dans la suite normale : il ouvre quelque trois cents écrans et écrit un dossier. Il est lancé sur
/// demande (`SIGH_SPECIMENS=1 flutter test tool/specimens/generer_specimens_test.dart`). Ce banc vérifie, sans rien lancer, que chaque cas de l'outil est
/// conditionné par la variable d'environnement, et qu'aucun autre fichier de test n'y traîne.
void main() {
  final source = File('tool/specimens/generer_specimens_test.dart').readAsStringSync();

  test('l’outil de spécimens ne s’active que par SIGH_SPECIMENS=1', () {
    expect(source, contains("Platform.environment['SIGH_SPECIMENS'] == '1'"));
  });

  test('chaque cas de l’outil est ignoré sans la variable', () {
    final cas = RegExp(r'testWidgets\(').allMatches(source).length;
    final ignores = RegExp(r'skip: !actif').allMatches(source).length;
    expect(cas, greaterThan(0));
    expect(ignores, cas, reason: 'un cas sans `skip: !actif` s’exécuterait dans la suite normale');
  });

  test('aucun autre test ne se cache dans tool/specimens', () {
    final tests = Directory('tool/specimens').listSync().whereType<File>().map((f) => f.path.split('/').last).where((n) => n.endsWith('_test.dart')).toList();
    expect(tests, ['generer_specimens_test.dart']);
  });
}
