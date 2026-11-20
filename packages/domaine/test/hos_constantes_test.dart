// LOT B : les constantes à une source. Tension en DEUX nombres (cmHg), diurèse en millilitres ; migration des anciennes données ; aucune alerte de variation.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

void main() {
  group('la tension : deux nombres, « 12/8 » n’est qu’une mise en forme', () {
    test('mise en forme, jamais une moitié de tension', () {
      expect(hosTensionTexte(12, 8), '12/8');
      expect(hosTensionTexte('13', '9'), '13/9');
      expect(hosTensionTexte(12, null), isNull);
      expect(hosTensionTexte(null, null), isNull);
      expect(hosUniteTension, 'cmHg');
    });
    test('l’ancien texte : deux entiers séparés par une barre, rien d’autre n’est deviné', () {
      expect(hosAnalyserTension('12/8'), (sys: 12, dia: 8));
      expect(hosAnalyserTension(' 11 / 7 '), (sys: 11, dia: 7));
      for (final x in ['12 sur 8', '12', '12/8/4', 'abc', '', null, '120/80', '12,5/8']) {
        expect(hosAnalyserTension(x), isNull, reason: '$x');
      }
    });
    test('les nombres l’emportent TOUJOURS sur le texte ; le texte ne complète que ce qui manque', () {
      expect(hosTensionDe({'tensionSys': 14, 'tensionDia': 9, 'tension': '10/6'}), (sys: 14, dia: 9));
      expect(hosTensionDe({'tension': '12/8'}), (sys: 12, dia: 8));
      expect(hosTensionDe({'tensionSys': 14, 'tension': '14/8'}), (sys: 14, dia: 8));
      expect(hosTensionDe({'temperature': 37}), (sys: null, dia: null));
      expect(hosTensionAffichee({'tensionSys': 12, 'tensionDia': 8}), '12/8');
      expect(hosTensionAffichee({'tension': 'non mesurée'}), 'non mesurée', reason: 'un texte non analysable se montre tel quel, il n’est ni perdu ni inventé en nombres');
      expect(hosTensionAffichee({}), isNull);
    });
    test('les bornes sont celles de l’accueil, reprises : systolique 4 à 30, diastolique 2 à 20', () {
      expect([hosTensionSysMin, hosTensionSysMax, hosTensionDiaMin, hosTensionDiaMax], [4, 30, 2, 20]);
    });
  });

  group('la diurèse : millilitres partout', () {
    test('texte en mL, sans décimale', () {
      expect(hosDiureseTexte(1200), '1200 mL');
      expect(hosDiureseTexte(1200.4), '1200 mL');
      expect(hosDiureseTexte(null), '—');
      expect(hosUniteDiurese, 'mL');
      expect(hosDiureseMax, 5000);
    });
    test('l’échelle de la courbe est graduée en mL, sans conversion : 1 200 mL se place au même endroit que 1,2 L sur l’ancienne échelle', () {
      final e = hosEchelles.firstWhere((x) => x.code == 'diurese');
      expect(e.unite, 'mL');
      expect(e.graduations, [0, 500, 1000, 1500, 2000, 2500]);
      expect(hosPositionSurEchelle(e, 1250), closeTo(0.5, 1e-9));
    });
    test('hosRelevesDe : la diurèse du lit et celle de l’accueil (millilitres) passent telles quelles, la tension se lit des deux nombres', () {
      final rel = hosRelevesDe('P1',
          constantes: [
            {'patientId': 'P1', 'dateHeure': '2026-11-10T09:00', 'tensionSys': 13, 'tensionDia': 8, 'diurese': 800}
          ],
          admissions: [
            {'id': 'A1', 'patientId': 'P1'}
          ],
          releves: [
            {'admissionId': 'A1', 'date': '2026-11-10', 'heure': '18:00', 'tensionSys': 12, 'tensionDia': 7, 'diurese': 1200},
            {'admissionId': 'A1', 'date': '2026-11-11', 'heure': '08:00', 'tension': '11/6', 'diurese': 900}
          ]);
      expect([for (final r in rel) r['diurese']], [800, 1200, 900]);
      expect([for (final r in rel) r['ta']], [13, 12, 11], reason: 'une fiche d’avant le lot (texte seul) se lit encore');
      expect([for (final r in rel) hosTensionAffichee(r)], ['13/8', '12/7', '11/6']);
    });
  });

  group('la migration des constantes d’avant le lot B', () {
    final releves = <F>[
      {'id': 'REL1', 'statut': 'actif', 'admissionId': 'A1', 'tension': '12/8', 'diurese': 1200},
      {'id': 'REL2', 'statut': 'archive', 'admissionId': 'A1', 'tension': '11/7', 'diurese': 900},
      {'id': 'REL3', 'statut': 'actif', 'admissionId': 'A1', 'tension': 'à reprendre', 'diurese': 700},
      {'id': 'REL4', 'statut': 'actif', 'admissionId': 'A1', 'tensionSys': 13, 'tensionDia': 9},
      {'id': 'REL5', 'statut': 'actif', 'admissionId': 'A1', 'temperature': 37},
    ];
    final observations = <F>[
      {
        'id': 'OBS1',
        'constantes': [
          {'heure': '2026-11-10T09:00:00Z', 'tension': '10/6', 'pouls': 70},
          {'heure': '2026-11-10T13:00:00Z', 'tensionSys': 12, 'tensionDia': 7}
        ]
      },
      {'id': 'OBS2', 'constantes': <Object?>[]},
      {'id': 'OBS3'},
    ];
    final constantes = <F>[
      {'id': 'C1', 'tensionSys': 13, 'tensionDia': 9, 'tension': '13/9', 'diurese': 1.5},
      {'id': 'C2', 'tensionSys': 12, 'tensionDia': 8, 'tension': '12/8', 'diurese': 0.25},
      {'id': 'C3', 'tensionSys': 12, 'tensionDia': 8, 'tension': '12/8'},
    ];

    test('« a/b » devient deux nombres (archivées comprises), le texte disparaît ; un texte illisible reste TEL QUEL, compté, jamais inventé', () {
      final r = hosMigrerConstantes(releves: releves, diureseAccueilEnLitres: false);
      final m = {for (final f in r.modifiees['releves']!) f['id']: f};
      expect(m['REL1'], {'id': 'REL1', 'statut': 'actif', 'admissionId': 'A1', 'diurese': 1200, 'tensionSys': 12, 'tensionDia': 8});
      expect(m['REL2']!['tensionSys'], 11, reason: 'RG-14 : une fiche archivée est migrée aussi, elle ne disparaît pas');
      expect(m['REL3']!['tension'], 'à reprendre');
      expect(m['REL3']!.containsKey('tensionSys'), isFalse);
      expect(m['REL4'], releves[3], reason: 'déjà à la bonne forme : intacte');
      expect(m['REL5'], releves[4]);
      expect(r.tensionsScindees, 2);
      expect(r.tensionsIllisibles, 1);
      expect(r.modifiees.length, 1, reason: 'seule la collection qui change est à réécrire');
      expect(m['REL1']!['diurese'], 1200, reason: 'la diurèse du lit est DÉJÀ en millilitres : on n’y touche pas');
    });

    test('les constantes d’une feuille d’observation sont scindées une à une, l’ordre et les autres champs conservés', () {
      final r = hosMigrerConstantes(observations: observations, diureseAccueilEnLitres: false);
      final o = r.modifiees['observations']!;
      final cs = (o.first['constantes'] as List).cast<Map>();
      expect(cs[0], {'heure': '2026-11-10T09:00:00Z', 'pouls': 70, 'tensionSys': 10, 'tensionDia': 6});
      expect(cs[1]['tensionSys'], 12);
      expect(o[1]['constantes'], isEmpty);
      expect(o[2].containsKey('constantes'), isFalse);
      expect(r.tensionsScindees, 1);
    });

    test('la diurèse d’accueil passe des litres aux millilitres, UNE fois, sur demande de la marque de version ; le texte calculé de l’accueil reste', () {
      final r = hosMigrerConstantes(constantes: constantes, diureseAccueilEnLitres: true);
      final m = {for (final f in r.modifiees['constantes']!) f['id']: f};
      expect(m['C1']!['diurese'], 1500);
      expect(m['C2']!['diurese'], 250);
      expect(m['C3']!.containsKey('diurese'), isFalse, reason: 'pas de diurèse : rien à convertir, rien d’inventé');
      expect(m['C1']!['tension'], '13/9', reason: 'champ calculé de l’accueil : exception tracée à « une source », conservé');
      expect(r.diuresesConverties, 2);
      // Sans la demande (poste déjà à la bonne forme), 2 mL ne deviennent JAMAIS 2 000 mL.
      final non = hosMigrerConstantes(constantes: [{'id': 'C9', 'diurese': 2}], diureseAccueilEnLitres: false);
      expect(non.aFait, isFalse);
      expect(non.diuresesConverties, 0);
    });

    test('idempotente : rejouer la migration sur une collection migrée ne change rien (tension) et rend « rien à faire »', () {
      final une = hosMigrerConstantes(releves: releves, observations: observations, diureseAccueilEnLitres: false);
      final deux = hosMigrerConstantes(releves: une.modifiees['releves']!, observations: une.modifiees['observations']!, diureseAccueilEnLitres: false);
      expect(deux.tensionsScindees, 0);
      expect(deux.modifiees, isEmpty);
      expect(deux.tensionsIllisibles, 1, reason: 'le texte illisible reste dit à chaque passage : il attend une correction humaine');
    });
  });
}
