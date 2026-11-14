import 'package:flutter_test/flutter_test.dart';

import 'aide_grand_stock.dart';

/// NON-RÉGRESSION : le jeu d'origine existe à l'identique sur tous les postes (mêmes identifiants, mère comprise). Deux fileuls qui le créent chacun AVANT de s'être parlé
/// (miroir vide) ne doivent laisser aucun refus `fiche_existe` : la seconde création, identique à ce que la mère détient, est un rejeu accepté sans effet.
void main() {
  test('deux fileuls qui poussent le même jeu d’origine avant tout tirage : une fiche à la mère, aucun refus', () async {
    final c = Clinique(9781, ':memory:');
    await c.demarrer();
    final postes = <Poste>[];
    try {
      await c.pub.pousser();
      await c.pontM.cycle(); // la mère détient déjà le jeu d'origine
      for (final n in ['F1', 'F2']) {
        final p = Poste(n, c.port, 'stock', 'AGENT $n');
        await p.moteur.rattacher('http://127.0.0.1:${c.port}', await c.console.codeAppareil(n));
        postes.add(p);
      }
      for (final p in postes) {
        expect(await p.pont.pousser(), greaterThan(0), reason: '${p.nom} : miroir vide, il crée le jeu d’origine');
      }
      for (final p in postes) {
        p.moteur.demarrer();
      }
      for (var i = 0; i < 8; i++) {
        for (final p in postes) {
          await p.tour();
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      for (final p in postes) {
        expect(await p.moteur.refusees(), isEmpty, reason: p.nom);
      }
      final n = (await c.mere.base.select("SELECT COUNT(*) AS n FROM fiches WHERE collection='patients' AND id='PAT0001'")).first['n'];
      expect(n, 1);
    } finally {
      for (final p in postes) {
        p.appl.arreter();
      }
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
