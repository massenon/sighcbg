// RG-11 — la paie et les primes ne comptent QUE les vacations validées : une vacation « à valider » ne rapporte rien, une fois validée elle rapporte.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> vac(String id, String date, String type, {String? etat}) =>
      {'id': id, 'employeId': 'm-9', 'date': date, 'type': type, 'statut': 'actif', if (etat != null) 'validationEtat': etat};
  final agent = <String, Object?>{'id': 'm-9', 'matricule': 'm-9', 'nomComplet': 'TEST Agent', 'fonction': 'infirmier', 'salaireBase': 100000, 'dateEmbauche': '2020-01-01'};
  final aujourdhui = DateTime(2026, 9, 30, 10);

  PaiLignePrime? ligne(PaiCalcul c, String id) => c.lignesPrimes.where((l) => l.id == id).firstOrNull;

  test('la fonction unique : sans état = lue validée (avant le circuit), validee compte, a_valider et refuse ne comptent pas', () {
    expect(vacationCompteRh(vac('a', '2026-09-01', 'garde')), isTrue);
    expect(vacationCompteRh(vac('a', '2026-09-01', 'garde', etat: 'validee')), isTrue);
    expect(vacationCompteRh(vac('a', '2026-09-01', 'garde', etat: 'a_valider')), isFalse);
    expect(vacationCompteRh(vac('a', '2026-09-01', 'garde', etat: 'refuse')), isFalse);
  });

  test('bulletin : une garde et une permanence « à valider » ne rapportent rien ; validées, elles rapportent', () {
    final aValider = [vac('p1', '2026-09-03', 'garde', etat: 'a_valider'), vac('p2', '2026-09-05', 'permanence', etat: 'a_valider')];
    final avant = paiCalculer(agent, 2026, 8, PaiEntrees(planning: aValider), aujourdhui);
    expect(ligne(avant, 'garde'), isNull, reason: 'garde à valider : aucune prime');
    expect(ligne(avant, 'permanence'), isNull);
    final validees = [for (final v in aValider) {...v, 'validationEtat': 'validee'}];
    final apres = paiCalculer(agent, 2026, 8, PaiEntrees(planning: validees), aujourdhui);
    expect(ligne(apres, 'garde')?.nombre, 1, reason: 'validée : la garde rapporte');
    expect(ligne(apres, 'permanence')?.nombre, 1);
    expect(apres.brut, greaterThan(avant.brut));
  });

  test('primes du mois (m10-primes), fiche et statistiques de garde : la vacation à valider est écartée', () {
    final pl = [vac('p1', '2026-09-03', 'garde', etat: 'a_valider'), vac('p2', '2026-09-04', 'garde'), vac('p3', '2026-09-05', 'permanence', etat: 'a_valider')];
    expect(rhbCompter(pl, 'm-9', 2026, 9, 'garde'), 1);
    expect(rhbCompter(pl, 'm-9', 2026, 9, 'permanence'), 0);
    expect(rhaCompter(pl, 'garde'), 1);
    expect(rhbLignesGardes(pl).map((v) => v['id']), ['p2']);
    final apres = [for (final v in pl) {...v, 'validationEtat': 'validee'}];
    expect(rhbCompter(apres, 'm-9', 2026, 9, 'garde'), 2);
    expect(rhbCompter(apres, 'm-9', 2026, 9, 'permanence'), 1);
    expect(rhbLignesGardes(apres).length, 3);
  });
}
