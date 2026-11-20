import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// HONORAIRE DE RÉGIME CONTRE PRIME NS 132 (Direction de Baguidi, 17/11/2026, point 3 de `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md` § 10) : un honoraire de régime INDIVIDUEL qui
/// correspond à une prime de la grille déjà versée pour la même vacation est REFUSÉ à la pose (`DOUBLE_PAIEMENT_PRIME`) et exclu du bulletin, avec un message nommé au validateur.
/// Le cas d'école : le régime « Incinération » (5 000 F mensuels) adopté par un aide-soignant, à qui la note NS 132 verse déjà 5 000 F d'incinération.

typedef F = Map<String, Object?>;

List<F> fiches(String f) => [for (final x in jsonDecode(File(f).readAsStringSync()) as List) (x as Map).cast<String, Object?>()];

void main() {
  // Les régimes de la catégorie tels que le jeu livré les porte (dont « Incinération des déchets de l'hôpital », 5 000 F mensuels, vacation `incineration`).
  final regimes = fiches('../../apps/poste/assets/donnees/jeu/regimesTravail.json');
  const incineration = 'Incinération des déchets de l’hôpital';
  final primes = rhbPrimesALaDate(const [], const []);
  num grille(String id, String fonction, String jour) => rhbMontantPrime(const [], const [], id, fonction, jour);

  RegimeRhResolu resoudre(String fonction, List<F> versions, String date) =>
      regimeRhALaDate(regimesActifs: regimes, versions: versions, fonction: fonction, date: date);

  F remplacement({String base = incineration, Map<String, Object?> champs = const {}, String date = '2026-12-01'}) =>
      {'id': 'RGI-1', 'employeId': 'AG-TEST', 'dateEffet': date, 'mode': 'remplacement', 'baseRemplacement': base, 'champs': champs, 'aValider': <String>[]};

  RefusRh? poser(String fonction, F version, {String jour = '2026-12-01'}) => controlerDoublePaiementPrimeRh(
      regime: resoudre(fonction, [version], jour), jour: jour, primes: primes, montantPrime: (id) => grille(id, fonction, jour));

  group('à la pose : la version qui répète la prime est REFUSÉE, nommée', () {
    test('le régime d\'incinération (5 000 F) adopté par un aide-soignant : DOUBLE_PAIEMENT_PRIME, avec la prime, la vacation, le montant et le jour', () {
      final r = poser('aide_soignant', remplacement());
      expect(r, isNotNull);
      expect(r!.code, 'DOUBLE_PAIEMENT_PRIME');
      expect(r.motif, allOf(contains('Incinération'), contains('NS 132'), contains('5 000'), contains('01/12/2026'), contains('ne se paie pas deux fois')));
      expect(r.geste, contains('Retirer l’honoraire'));
      expect(r.extra, containsPair('prime', 'incineration'));
      expect(r.extra, containsPair('vacation', 'incineration'));
      expect(r.extra, containsPair('montant', 5000));
      expect(r.toJson()['ok'], isFalse);
    });

    test('même chose par une DÉROGATION qui pose l\'honoraire et les vacations d\'incinération sur le régime de la catégorie', () {
      final v = {
        'id': 'RGI-2', 'employeId': 'AG-TEST', 'dateEffet': '2026-12-01',
        'champs': {'vacations': ['incineration'], 'honoraire': 5000, 'honorairePeriodicite': 'mensuelle'}, 'aValider': <String>[]
      };
      expect(poser('aide_soignant', v)!.code, 'DOUBLE_PAIEMENT_PRIME');
    });

    test('un honoraire d\'un AUTRE montant est un complément voulu : accepté', () {
      final v = {
        'id': 'RGI-3', 'employeId': 'AG-TEST', 'dateEffet': '2026-12-01',
        'champs': {'vacations': ['incineration'], 'honoraire': 6000, 'honorairePeriodicite': 'mensuelle'}, 'aValider': <String>[]
      };
      expect(poser('aide_soignant', v), isNull);
    });

    test('une fonction à qui la grille ne verse PAS cette prime (le médecin) : rien à répéter, accepté', () {
      expect(poser('medecin', remplacement()), isNull);
    });

    test('la grille se lit À LA DATE : une prime d\'incinération relevée à 5 500 le 01/12 ne fait plus doublon avec un honoraire de 5 000', () {
      final g = [
        {'primeId': 'incineration', 'dateEffet': '2026-12-01', 'montants': {'aide_soignant': 5500}}
      ];
      final h = [
        {'primeId': 'incineration', 'dateEffet': '2026-01-01', 'dateFin': '2026-11-30', 'montants': {'aide_soignant': 5000}}
      ];
      RefusRh? a(String jour) => controlerDoublePaiementPrimeRh(
          regime: resoudre('aide_soignant', [remplacement(date: '2026-01-01')], jour),
          jour: jour,
          primes: rhbPrimesALaDate(g, h),
          montantPrime: (id) => rhbMontantPrime(g, h, id, 'aide_soignant', jour));
      expect(a('2026-11-15')!.code, 'DOUBLE_PAIEMENT_PRIME');
      expect(a('2026-12-15'), isNull);
    });

    test('un honoraire de la CATÉGORIE (sans version) n\'est jamais en cause : c\'est la grille de la clinique', () {
      // La catégorie « Incinération » appliquée à une fonction qui la porte, sans version individuelle.
      final r = resoudre('entretien', const [], '2026-12-01');
      expect(r.individuel, isFalse);
      expect(controlerDoublePaiementPrimeRh(regime: r, jour: '2026-12-01', primes: primes, montantPrime: (id) => grille(id, 'entretien', '2026-12-01')), isNull);
    });

    test('rythmes différents : un honoraire PAR OCCURRENCE de 5 000 ne répète pas un forfait mensuel de 5 000', () {
      final v = remplacement(champs: {'honorairePeriodicite': 'occurrence'});
      expect(poser('aide_soignant', v), isNull);
    });

    test('la garde par occurrence : un honoraire de 900 F par garde répète la prime de garde de l\'aide-soignant (900 F)', () {
      final v = {
        'id': 'RGI-4', 'employeId': 'AG-TEST', 'dateEffet': '2026-12-01',
        'champs': {'honoraire': 900, 'honorairePeriodicite': 'occurrence'}, 'aValider': <String>[]
      };
      final r = poser('aide_soignant', v);
      expect(r!.code, 'DOUBLE_PAIEMENT_PRIME');
      expect(r.extra['prime'], 'garde');
      // 1 000 F par garde n'est pas la prime : accepté.
      expect(poser('aide_soignant', {...v, 'champs': {'honoraire': 1000, 'honorairePeriodicite': 'occurrence'}}), isNull);
    });
  });

  group('au bulletin : l\'honoraire répété est EXCLU, la prime reste, le message est nommé', () {
    final personnel = <F>[
      {'id': 'AG-TEST', 'matricule': '901', 'nomComplet': 'AGENT Fictif', 'fonction': 'aide_soignant', 'service': 'Soins', 'salaireBase': 100000, 'dateEmbauche': '2026-01-01'}
    ];
    // Le planning VALIDÉ du mois : une vacation d'incinération (qui ouvre l'honoraire du régime) et une garde (qui ouvre la prime de garde).
    final planning = <F>[
      {'id': 'PLN-1', 'employeId': 'AG-TEST', 'date': '2026-11-10', 'type': 'incineration'},
      {'id': 'PLN-2', 'employeId': 'AG-TEST', 'date': '2026-11-12', 'type': 'garde'},
    ];

    PaiCalcul calculer(List<F> versions) =>
        paiCalculer(personnel.single, 2026, 10, PaiEntrees(planning: planning, regimesTravail: regimes, regimesIndividuels: versions), DateTime(2026, 11, 30));

    test('le cas Incinération 5 000 F adopté par un aide-soignant : la prime NS 132 est versée UNE fois, l\'honoraire est écarté et dit', () {
      final c = calculer([remplacement(date: '2026-11-01')]);
      final incin = c.lignesPrimes.where((l) => l.id == 'incineration').toList();
      expect([incin.length, incin.single.total], [1, 5000], reason: 'la prime de la grille reste due');
      expect(c.lignesPrimes.where((l) => l.id.startsWith('honoraire_regime')), isEmpty, reason: 'l\'honoraire répété n\'entre pas au bulletin');
      expect(c.honorairesExclus, hasLength(1));
      final x = c.honorairesExclus.single;
      expect(x['code'], 'DOUBLE_PAIEMENT_PRIME');
      expect(x['message'], allOf(contains('AGENT Fictif'), contains('Incinération'), contains('5 000'), contains('10/11/2026'), contains('Seule la prime de la grille est versée')));
      expect(paiBulletinDe(c, 'BUL-00001')['honorairesExclus'], hasLength(1), reason: 'le validateur le lit sur la pièce');
    });

    test('le même agent sans double emploi : l\'honoraire est compté (6 000 F), la prime aussi', () {
      final c = calculer([remplacement(date: '2026-11-01', champs: {'honoraire': 6000, 'honorairePeriodicite': 'mensuelle'})]);
      expect(c.honorairesExclus, isEmpty);
      expect(c.lignesPrimes.where((l) => l.id == 'honoraire_regime_mensuel').single.total, 6000);
      expect(c.lignesPrimes.where((l) => l.id == 'incineration').single.total, 5000);
      expect(paiBulletinDe(c, 'BUL-00001').containsKey('honorairesExclus'), isFalse, reason: 'rien à dire : le champ n\'est pas écrit');
    });

    test('CHEVAUCHEMENT : l\'honoraire de 6 000 F s\'ajoute à la prime de 5 000 F pour la même vacation — versé, mais SIGNALÉ au validateur (pas un refus)', () {
      final c = calculer([remplacement(date: '2026-11-01', champs: {'honoraire': 6000, 'honorairePeriodicite': 'mensuelle'})]);
      expect(c.chevauchementsPrimes, hasLength(1));
      final x = c.chevauchementsPrimes.single;
      expect(x['code'], codeChevauchementPrime);
      expect(x['message'], allOf(contains('AGENT Fictif'), contains('Incinération'), contains('6 000'), contains('5 000'), contains('les deux sont versés')));
      expect(c.lignesPrimes.where((l) => l.id == 'honoraire_regime_mensuel').single.total, 6000, reason: 'rien n\'est exclu');
      expect(paiBulletinDe(c, 'BUL-00001')['chevauchementsPrimes'], hasLength(1));
    });

    test('pas de chevauchement à signaler : doublon exact (déjà exclu), sans version, ou régime de la catégorie', () {
      expect(calculer([remplacement(date: '2026-11-01')]).chevauchementsPrimes, isEmpty, reason: 'le doublon exact est EXCLU, pas signalé deux fois');
      final sans = calculer(const []);
      expect(sans.chevauchementsPrimes, isEmpty);
      expect(paiBulletinDe(sans, 'BUL-00001').containsKey('chevauchementsPrimes'), isFalse);
    });

    test('sans version individuelle : le bulletin est celui d\'avant, aucune exclusion', () {
      final c = calculer(const []);
      expect(c.honorairesExclus, isEmpty);
      expect(c.lignesPrimes.where((l) => l.id.startsWith('honoraire_regime')), isEmpty);
    });

    test('primes NS 132 fermées : ni la prime ni l\'honoraire ne se versent, donc rien n\'est écarté', () {
      final c = paiCalculer(personnel.single, 2026, 10,
          PaiEntrees(planning: planning, regimesTravail: regimes, regimesIndividuels: [remplacement(date: '2026-11-01')], primesNs132: false), DateTime(2026, 11, 30));
      expect(c.honorairesExclus, isEmpty);
      expect(c.lignesPrimes, isEmpty);
    });

    test('l\'honoraire du mois lu par l\'écran des primes porte la même exclusion (une seule résolution)', () {
      final versions = [remplacement(date: '2026-11-01')];
      final h = honoraireRegimeMoisRh(
          vacations: planning,
          employeId: 'AG-TEST',
          annee: 2026,
          mois: 11,
          regimeDe: (d) => resoudre('aide_soignant', versions, d),
          doublon: (l) => doublePaiementLigneRh(l, primes: primes, montantPrime: (id, jour) => grille(id, 'aide_soignant', jour)));
      expect(h.montant, 0);
      expect(h.exclus.single['phrase'], contains('répète la prime'));
      final sans = honoraireRegimeMoisRh(vacations: planning, employeId: 'AG-TEST', annee: 2026, mois: 11, regimeDe: (d) => resoudre('aide_soignant', versions, d));
      expect(sans.montant, 5000, reason: 'sans le contrôle, l\'honoraire se compterait : c\'est ce que la règle écarte');
    });
  });
}
