import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// UN PRÉFIXE PAR REGISTRE (Direction de Baguidi, 17/11/2026, point 5 ; E3874). Cinq préfixes étaient partagés entre deux registres (`DEP-` courriers départ et dépenses, `LAB-` demandes
/// d'analyses et réactifs, `C` consultations et rendez-vous, `EVT-` événements du personnel et de l'établissement, `BP-` registre des bulletins et référence d'un bulletin d'agent) : deux
/// pièces de deux registres pouvaient porter le même numéro. Chaque registre a désormais le sien (proposition « à valider ») ; les numéros déjà émis ne changent pas et leurs rangs restent
/// LUS sous l'ancien préfixe, pour que le registre ne redonne jamais un rang déjà pris.

void main() {
  setUp(Numerotation.reinitialiser);
  tearDown(Numerotation.reinitialiser);

  // (série qui change, série qui garde le préfixe, ancien numéro émis, numéro suivant attendu, date de la pièce)
  const cas = <(String, String, String, String, String)>[
    ('adm.courriers-depart', 'compta.depenses', 'DEP-2026-0010', 'COU-2026-0011', '2026-06-01'),
    ('labo.reactifs', 'labo.demandes', 'LAB-0012', 'REA-0013', '2026-06-01'),
    ('agenda.rendezvous', 'consultation.consultations', 'C00012', 'RDV-00013', '2026-06-01'),
    ('adm.evenements', 'rh.evenements', 'EVT-0012', 'EVE-0013', '2026-06-01'),
    ('paie.bulletins', 'paie.bulletins-agent', 'BP-00012', 'BUL-00013', '2026-06-01'),
  ];

  group('chaque registre a son préfixe : plus aucun numéro commun à deux registres', () {
    for (final c in cas) {
      test('${c.$1} ne partage plus son préfixe avec ${c.$2}', () {
        final a = Numerotation.semence(c.$1), b = Numerotation.semence(c.$2);
        expect(a.prefixe, isNot(b.prefixe));
        expect(a.aValider, isTrue, reason: 'le préfixe retenu est une proposition à valider');
        expect(a.note, contains('PROPRE'));
        // Les numéros FORMÉS par les deux séries ne se confondent plus, quel que soit le rang.
        for (final rang in [1, 12, 400]) {
          expect(numeroFormate(c.$1, date: c.$5, rang: rang), isNot(numeroFormate(c.$2, date: c.$5, rang: rang)), reason: 'rang $rang');
        }
      });

      test('${c.$1} : « ${c.$3} » déjà émis garde son numéro, reste reconnu, et son rang n\'est pas redonné (suivant : ${c.$4})', () {
        expect(numeroDeLaSerie(c.$1, c.$3), isTrue, reason: 'un numéro d\'avant le changement reste reconnu par sa série');
        final existants = [
          {Numerotation.semence(c.$1).champ: c.$3, 'statut': 'archive'}
        ];
        expect(numeroSuivant(c.$1, date: c.$5, existants: existants), c.$4);
        // Les deux préfixes se lisent ensemble : le plus grand rang des deux gagne.
        final melange = [
          ...existants,
          {Numerotation.semence(c.$1).champ: numeroFormate(c.$1, date: c.$5, rang: 20)}
        ];
        expect(rangMaximal(c.$1, date: c.$5, existants: melange), 20);
      });
    }

    test('les cinq registres partagés sont bien ceux de la décision (aucune autre paire de séquences ne partage un préfixe sans le dire)', () {
      // Les paires restantes qui partagent un préfixe le font EXPRÈS : la contre-passation d'une pièce de clôture ou d'à-nouveau porte la lettre « C » devant le rang.
      final seq = Numerotation.semences.where((s) => s.genre == genreSequence).toList();
      final parTete = <String, List<String>>{};
      for (final s in seq) {
        (parTete['${s.prefixe}|${s.separateur}|${s.positionAnnee}|${s.annee}'] ??= []).add(s.code);
      }
      final partages = {for (final e in parTete.entries) if (e.value.length > 1) ...{e.key: e.value}};
      for (final e in partages.entries) {
        final series = [for (final c in e.value) Numerotation.semence(c)];
        final lettres = series.map((s) => s.prefixeRang).toSet();
        expect(lettres.length, series.length, reason: 'préfixe ${e.key} partagé sans lettre qui distingue : ${e.value}');
      }
    });
  });

  group('la lecture double des rangs', () {
    test('une série annuelle repart à 1 sous la nouvelle année, mais lit l\'ancien préfixe de l\'année en cours', () {
      final existants = [
        {'reference': 'DEP-2026-0010'}
      ];
      expect(numeroSuivant('adm.courriers-depart', date: '2026-12-31', existants: existants), 'COU-2026-0011');
      expect(numeroSuivant('adm.courriers-depart', date: '2027-01-02', existants: existants), 'COU-2027-0001');
    });

    test('une dépense et un courrier du même rang ne se confondent plus : la série des dépenses garde DEP- et ne lit pas COU-', () {
      final courriers = [
        {'reference': 'COU-2026-0030'}
      ];
      expect(numeroSuivant('compta.depenses', date: '2026-06-01', existants: courriers), 'DEP-2026-0001', reason: 'les dépenses ne lisent que leur registre');
      expect(numeroDeLaSerie('compta.depenses', 'COU-2026-0030'), isFalse);
    });

    test('une version datée du préfixe ne fait pas perdre la lecture de l\'ancien', () {
      final v = {
        'code': 'adm.courriers-depart',
        'prefixe': 'SORT',
        'dateEffet': '2027-01-01',
        'statut': 'actif',
        'aValider': false
      };
      Numerotation.appliquer([v]);
      final s = Numerotation.serie('adm.courriers-depart', date: '2027-03-01');
      expect(s.prefixe, 'SORT');
      expect(s.prefixesAnterieurs, ['DEP-']);
      expect(numeroSuivant('adm.courriers-depart', date: '2027-03-01', existants: [
        {'reference': 'DEP-2027-0004'}
      ]), 'SORT-2027-0005');
    });

    test('une référence provisoire de la série reste reconnue sous l\'ancien préfixe', () {
      expect(numeroDeLaSerie('adm.courriers-depart', 'DEP-2026-PROV-X1'), isTrue);
      expect(numeroDeLaSerie('adm.courriers-depart', 'COU-2026-PROV-X1'), isTrue);
    });
  });
}
