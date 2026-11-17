// PARITÉ de la copie du réglage dans le miroir Node du banc (`packages/sync/banc/mere.js`, `REGLAGE_CODE`) avec la définition du domaine : clé, valeur d'attente, bornes. Les deux copies
// ne divergent pas en silence (consigne de la Direction du 18/11/2026 : « plus de valeur en dur »).
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  test('le miroir Node de la mère porte la même clé, la même valeur d’attente et les mêmes bornes que la définition', () {
    final src = File('../sync/banc/mere.js').readAsStringSync();
    final m = RegExp(r"const REGLAGE_CODE = \{ cle: '([^']+)', defaut: (\d+), min: (\d+), max: (\d+) \};").firstMatch(src);
    expect(m, isNotNull, reason: 'REGLAGE_CODE introuvable dans banc/mere.js');
    final d = definitionDeParametre(cleValiditeCodeAppairage)!;
    expect(m!.group(1), cleValiditeCodeAppairage);
    expect(int.parse(m.group(2)!), d.defaut);
    expect(int.parse(m.group(3)!), d.min);
    expect(int.parse(m.group(4)!), d.max);
  });

  test('aucun écran ni aucune mère n’écrit plus « 15 minutes » pour un code d’appairage', () {
    final fichiers = [
      '../../apps/poste/lib/modules/mere/mra_supervision.dart',
      '../../apps/poste/lib/modules/mere/mrb_cle.dart',
      '../../apps/poste/lib/mere/console.dart',
      '../../apps/poste/lib/modules/auth/ins_modale.dart',
    ];
    for (final f in fichiers) {
      final t = File(f).readAsStringSync();
      expect(RegExp(r'valable\s+15\s+min|\(15 minutes\)|8 caractères, 15 minutes').hasMatch(t), isFalse, reason: f);
    }
    for (final f in ['../sync_dart/lib/src/mere.dart', '../sync/banc/mere.js', '../sync_dart/bin/mere.dart']) {
      final t = File(f).readAsStringSync();
      expect(t.contains('15 * 60 * 1000'), isFalse, reason: '$f : la durée d’un code est le réglage, pas un littéral');
      expect(t.contains('900000'), isFalse, reason: '$f : la durée d’un code est le réglage, pas un littéral');
    }
  });
}
