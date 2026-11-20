// RG-11 / E4027 — la paie ne retient QUE les vacations validées par la mère ; une vacation « à valider » est SIGNALÉE au bulletin, jamais comptée ni perdue.
// Non-régression : le même jeu avec et sans champ d'état donne les mêmes montants (un état absent se lit validé).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

void main() {
  final regimes = [for (final x in jsonDecode(File('../../apps/poste/assets/donnees/jeu/regimesTravail.json').readAsStringSync()) as List) (x as Map).cast<String, Object?>()];
  final agent = <String, Object?>{'id': 'm-9', 'matricule': '909', 'nomComplet': 'TEST Agent', 'fonction': 'aide_soignant', 'service': 'Soins', 'salaireBase': 100000, 'dateEmbauche': '2020-01-01'};
  final aujourdhui = DateTime(2026, 11, 30, 10);
  F vac(String id, String date, String type, {String? etat}) => {'id': id, 'employeId': 'm-9', 'date': date, 'type': type, 'statut': 'actif', if (etat != null) 'validationEtat': etat};
  F incineration({String? etat, String id = 'p-inc', String date = '2026-11-10'}) => vac(id, date, 'incineration', etat: etat);
  final regimeIndividuel = <F>[
    {'id': 'RGI-1', 'employeId': 'm-9', 'dateEffet': '2026-11-01', 'mode': 'remplacement', 'baseRemplacement': 'Incinération des déchets de l’hôpital', 'champs': {'honoraire': 6000, 'honorairePeriodicite': 'mensuelle'}, 'aValider': <String>[]}
  ];
  PaiCalcul calculer(List<F> planning, {bool regime = true}) =>
      paiCalculer(agent, 2026, 10, PaiEntrees(planning: planning, regimesTravail: regimes, regimesIndividuels: regime ? regimeIndividuel : null), aujourdhui);

  test('constantes uniques : validee / a_valider / refuse, et la fonction unique les lit', () {
    expect([vacationEtatValidee, vacationEtatAValider, vacationEtatRefusee], ['validee', 'a_valider', 'refuse']);
    expect(vacationEnAttenteRh(vac('a', '2026-11-01', 'garde', etat: vacationEtatAValider)), isTrue);
    expect(vacationEnAttenteRh(vac('a', '2026-11-01', 'garde')), isFalse);
    expect(vacationEnAttenteRh(vac('a', '2026-11-01', 'garde', etat: vacationEtatRefusee)), isFalse, reason: 'refusée : ni payée ni « en attente »');
    expect([for (final e in [null, vacationEtatValidee, vacationEtatAValider, vacationEtatRefusee]) vacationEtatLibelleRh(vac('a', '2026-11-01', 'garde', etat: e))],
        ['Validée', 'Validée', 'À valider', 'Refusée']);
    expect(planningVacationValidee(vac('a', '2026-11-01', 'garde', etat: vacationEtatAValider)), isFalse);
    expect(vacationsEnAttentePhrase(0), isNull);
    expect(vacationsEnAttentePhrase(2), '2 vacation(s) en attente de validation ne sont pas payées');
  });

  test('NON-RÉGRESSION : le même jeu avec et sans champ d\'état (ancien jeu = validé) donne les mêmes montants, sans avertissement', () {
    final ancien = [vac('p1', '2026-11-03', 'garde'), vac('p2', '2026-11-05', 'permanence'), incineration()];
    final explicite = [for (final v in ancien) {...v, 'validationEtat': vacationEtatValidee}];
    for (final regime in [false, true]) {
      final a = calculer(ancien, regime: regime), b = calculer(explicite, regime: regime);
      expect([a.brut, a.totalPrimes, a.net, a.gardes, a.permanences], [b.brut, b.totalPrimes, b.net, b.gardes, b.permanences]);
      expect(a.vacationsEnAttente, isEmpty);
      expect(a.avertissementVacations, isNull);
      expect(a.totalPrimes, greaterThan(0));
    }
  });

  test('une vacation « à valider » : absente du montant (prime ET honoraire), présente dans l\'avertissement', () {
    final seulesValidees = [vac('p1', '2026-11-03', 'garde'), incineration()];
    final avecAttente = [...seulesValidees, vac('p2', '2026-11-05', 'garde', etat: vacationEtatAValider), vac('p3', '2026-11-06', 'permanence', etat: vacationEtatAValider), incineration(etat: vacationEtatAValider, id: 'p-inc2', date: '2026-11-17')];
    final ref = calculer(seulesValidees), c = calculer(avecAttente);
    expect([c.brut, c.totalPrimes, c.gardes, c.permanences], [ref.brut, ref.totalPrimes, ref.gardes, ref.permanences], reason: 'les vacations à valider ne rapportent rien');
    expect(c.lignesPrimes.where((l) => l.id.startsWith('honoraire_regime')).map((l) => l.nombre), ref.lignesPrimes.where((l) => l.id.startsWith('honoraire_regime')).map((l) => l.nombre));
    expect(c.vacationsEnAttente.map((v) => v['id']), ['p2', 'p3', 'p-inc2']);
    expect(c.avertissementVacations, '3 vacation(s) en attente de validation ne sont pas payées');
    expect(paiBulletinDe(c, 'BUL-00001')['vacationsEnAttente'], hasLength(3), reason: 'le bulletin l\'écrit à sa génération');
    expect(paiBulletinDe(ref, 'BUL-00001').containsKey('vacationsEnAttente'), isFalse);
  });

  test('une vacation d\'un autre mois, d\'un autre agent, archivée, refusée ou sans durée (repos) n\'est pas signalée', () {
    final c = calculer([
      vac('a', '2026-10-30', 'garde', etat: vacationEtatAValider),
      {...vac('b', '2026-11-04', 'garde', etat: vacationEtatAValider), 'employeId': 'autre'},
      {...vac('c', '2026-11-04', 'garde', etat: vacationEtatAValider), 'statut': 'archive'},
      vac('d', '2026-11-04', 'garde', etat: vacationEtatRefusee),
      vac('e', '2026-11-04', 'repos24', etat: vacationEtatAValider),
    ]);
    expect(c.vacationsEnAttente, isEmpty);
  });

  test('la validation par la mère rend la vacation payable au calcul SUIVANT ; le bulletin déjà généré n\'est pas réécrit', () {
    final avant = [vac('p1', '2026-11-03', 'garde', etat: vacationEtatAValider)];
    final c1 = calculer(avant);
    final bulletin1 = paiBulletinDe(c1, 'BUL-00001');
    final brut1 = bulletin1['brut'];
    expect(c1.gardes, 0);
    expect(bulletin1['vacationsEnAttente'], hasLength(1));
    // La mère applique : même vacation, état « validée ».
    final apres = [for (final v in avant) {...v, 'validationEtat': vacationEtatValidee}];
    final c2 = calculer(apres);
    expect(c2.gardes, 1);
    expect(c2.brut, greaterThan(c1.brut as num));
    expect(c2.vacationsEnAttente, isEmpty);
    // Le bulletin 1 est un instantané : le calcul suivant n'y touche pas.
    expect(bulletin1['brut'], brut1);
    expect(bulletin1['vacationsEnAttente'], hasLength(1));
  });

  test('la fusion de la mère : l\'état validé reçu l\'emporte, la vacation devient payable', () {
    // La fusion champ à champ ne défait jamais une validation (E4025) ; le calcul lit l'état fusionné.
    final posee = vac('p1', '2026-11-03', 'garde', etat: vacationEtatAValider);
    expect(calculer([posee]).gardes, 0);
    expect(calculer([{...posee, 'validationEtat': vacationEtatValidee, 'validePar': 'mère', 'valideLe': '2026-11-04'}]).gardes, 1);
  });
}
