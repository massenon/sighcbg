// LOT 0 (16/11/2026, E3830-E3839) : les règles qui portaient une année figée lisent désormais l'horloge, la date de la pièce ou les fiches d'exercice.
// Chaque test place l'horloge de part et d'autre du 1er janvier 2027 : ce qui était juste en 2026 doit le rester en 2027.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  test('E3832 — le mois de référence des courbes comptables suit l’exercice et l’horloge (plus d’août 2026 figé)', () {
    expect(cpaMoisReference(2027, DateTime(2027, 1, 5)), DateTime(2027, 1, 1));
    expect(cpaMoisReference(2026, DateTime(2027, 1, 5)), DateTime(2026, 12, 1), reason: 'un exercice achevé se lit jusqu’en décembre');
    expect(cpaMoisReference(2028, DateTime(2027, 11, 20)), DateTime(2028, 12, 1), reason: 'exercice ouvert d’avance');
  });

  test('E3833 — les douze mois glissants de la masse salariale finissent au mois de l’horloge', () {
    final l = paiMoisGlissants(DateTime(2027, 1, 10));
    expect(l.length, 12);
    expect(l.last, endsWith('. 27'));
    expect(l.first, endsWith('. 26'));
  });

  test('E3837 — un bulletin sans année ne reçoit pas l’année 2026 : le mois seul, l’année dite non renseignée', () {
    final r = pilCoutAgent({'id': 'A1', 'salaireBase': 100000}, [
      {'personnelId': 'A1', 'agentId': 'A1', 'mois': 0, 'brut': 1, 'net': 1},
      {'personnelId': 'A1', 'agentId': 'A1', 'mois': 0, 'annee': 2027, 'brut': 1, 'net': 1},
    ], '', '');
    final periodes = [for (final b in r.bulletins) b.$1];
    expect(periodes, ['janvier (année non renseignée)', 'janvier 2027']);
  });

  test('E3838 — le calendrier fiscal n’a plus d’horloge par défaut : la date du jour décide de ce qui est réputé réglé', () {
    final avant = cfbGenEcheances(2026, obligationsFixes: cfbSemenceObligations(), aujourdhui: DateTime(2026, 8, 16));
    final apres = cfbGenEcheances(2026, obligationsFixes: cfbSemenceObligations(), aujourdhui: DateTime(2027, 1, 2));
    int payees(List<Map<String, Object?>> l) => l.where((e) => e['paye'] == true).length;
    expect(payees(apres), greaterThan(payees(avant)));
  });
}
