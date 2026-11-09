// PRD P0-5 : les deux activités de la paie pilotées depuis Paramètres système. Primes NS 132 fermées : le brut ne porte aucune prime de la note ;
// évaluations NS 131 fermées : la sanction vaut zéro ; bascules ouvertes (le défaut) : le calcul est inchangé, ce que les vecteurs de
// `paie_test.dart` continuent de vérifier. L'état se LIT dans `modulesActifs`, jamais dans un drapeau à part.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;

void main() {
  final auj = DateTime(2026, 10, 30, 10);
  // Une caissière embauchée l'an dernier (pas de prime d'ancienneté) : 3 gardes et 2 permanences en octobre, une évaluation à 10 %.
  final caissiere = <String, Object?>{
    'id': 'E1',
    'matricule': '001',
    'nomComplet': 'AGENT Test',
    'fonction': 'caissiere',
    'salaireBase': 100000,
    'dateEmbauche': '2025-09-01',
    'statut': 'actif'
  };
  final planning = [
    for (final j in ['05', '12', '19']) <String, Object?>{'employeId': 'E1', 'type': 'garde', 'date': '2026-10-$j', 'statut': 'actif'},
    for (final j in ['07', '14']) <String, Object?>{'employeId': 'E1', 'type': 'permanence', 'date': '2026-10-$j', 'statut': 'actif'},
  ];
  final evaluations = [
    <String, Object?>{'employeId': 'E1', 'periode': paiPeriodeLibelle(2026, 9), 'prelevementPct': 10, 'statut': 'actif'}
  ];
  PaiCalcul calc({bool primes = true, bool sanctions = true}) => paiCalculer(
      caissiere, 2026, 9, PaiEntrees(planning: planning, evaluations: evaluations, primesNs132: primes, sanctionsNs131: sanctions), auj);

  group('le moteur de paie suit les deux bascules', () {
    test('bascules ouvertes (défaut) : garde 3 × 900, permanence 2 × 600, forfait caisse 10 000 ; sanction 10 % du brut', () {
      final c = calc();
      expect(c.totalPrimes, 2700 + 1200 + 10000);
      expect(c.brut, 113900);
      expect(c.pctSanction, 10);
      expect(c.sanction, 11390);
      expect(c.brutApresSanction, 102510);
      expect([for (final l in c.lignesPrimes) l.id], ['permanence', 'garde', 'caisse']);
      // Le défaut du constructeur EST l'ouverture : un appelant qui ne dit rien garde le comportement d'avant.
      const e = PaiEntrees();
      expect([e.primesNs132, e.sanctionsNs131], [true, true]);
    });

    test('primes NS 132 fermées : brut = salaire de base, aucune ligne de prime (garde et permanence comprises), compteurs conservés', () {
      final c = calc(primes: false);
      expect(c.totalPrimes, 0);
      expect(c.lignesPrimes, isEmpty);
      expect(c.brut, 100000);
      expect([c.gardes, c.permanences], [3, 2], reason: 'le planning existe toujours ; seules les primes tombent');
      expect(c.sanction, 10000, reason: 'la sanction NS 131, ouverte, porte sur le brut sans primes');
      expect(c.cnssOuvriere, arrondiJs(90000 * paiCnssOuvriere / 100));
    });

    test('évaluations NS 131 fermées : sanction nulle, le brut après sanction est le brut', () {
      final c = calc(sanctions: false);
      expect(c.pctSanction, 0);
      expect(c.sanction, 0);
      expect(c.brutApresSanction, c.brut);
      expect(c.brut, 113900, reason: 'les primes, ouvertes, restent');
      expect(c.net, c.brut - c.totalRetenues);
    });

    test('les deux fermées : brut = base, net = base − cotisations', () {
      final c = calc(primes: false, sanctions: false);
      expect(c.brut, 100000);
      expect(c.sanction, 0);
      expect(c.coutEmployeur, 100000 + arrondiJs(100000 * paiCnssPatronale / 100) + arrondiJs(100000 * paiVpsTaux / 100));
    });

    test('la prime d’ancienneté et les heures supplémentaires ne relèvent pas de la NS 132 : elles restent', () {
      final ancien = {...caissiere, 'dateEmbauche': '2020-01-01'};
      final hs = [
        <String, Object?>{'employeId': 'E1', 'valide': true, 'periode': paiPeriodeLibelle(2026, 9), 'montant': 5000, 'heures': 4, 'statut': 'actif'}
      ];
      final c = paiCalculer(ancien, 2026, 9, PaiEntrees(planning: planning, heuresSup: hs, primesNs132: false), auj);
      expect(c.primeAnciennete, greaterThan(0));
      expect(c.heuresSupMontant, 5000);
      expect(c.brut, 100000 + c.primeAnciennete + 5000);
    });
  });

  group('l’état des bascules se lit dans modulesActifs', () {
    M fiche(String code, List<String> ecrans, {bool actif = false, String statut = 'actif', String module = 'M10'}) =>
        {'id': code, 'code': code, 'module': module, 'ecrans': ecrans, 'actif': actif, 'statut': statut};

    test('aucune fiche : les deux activités sont ouvertes', () {
      expect(paiActivites(const []), (primesNs132: true, sanctionsNs131: true));
    });
    test('la fiche de la bascule NS 132 ferme les primes seules ; celle de la NS 131 les sanctions seules', () {
      expect(paiActivites([fiche(paiBasculeNs132.code, paiBasculeNs132.ecrans)]), (primesNs132: false, sanctionsNs131: true));
      expect(paiActivites([fiche(paiBasculeNs131.code, paiBasculeNs131.ecrans)]), (primesNs132: true, sanctionsNs131: false));
    });
    test('une fiche rouverte ou ARCHIVÉE ne ferme rien (RG-14)', () {
      expect(paiActivites([fiche(paiBasculeNs132.code, paiBasculeNs132.ecrans, actif: true)]).primesNs132, true);
      expect(paiActivites([fiche(paiBasculeNs132.code, paiBasculeNs132.ecrans, statut: 'archive')]).primesNs132, true);
    });
    test('une seule source de vérité : une activité déclarée ailleurs sur le même écran, ou le module M10 fermé en entier, ferme aussi', () {
      expect(paiActivites([fiche('M10-AUTRE', ['m10-primes'])]).primesNs132, false);
      expect(paiActivites([fiche('MODULE-M10', const [])]), (primesNs132: false, sanctionsNs131: false));
      expect(paiActivites([fiche('M10-SANCT', ['m10-sanctions'])]).sanctionsNs131, true, reason: 'l’écran pilote de la NS 131 est celui des évaluations');
    });
    test('les écrans fermés et l’origine du barème sont nommés', () {
      expect(paiBasculeNs132.ecrans, ['m10-primes']);
      expect(paiBasculeNs131.ecrans, ['m10-evaluations', 'm10-sanctions']);
      expect(paiBasculeNs132.source, rhbNs132Reference);
      expect(paiBasculeNs131.source, rhbNs131Reference);
      expect(paiFicheBascule([fiche(paiBasculeNs131.code, paiBasculeNs131.ecrans)], paiBasculeNs131)?['code'], 'PAIE-NS131');
      expect(paiFicheBascule([fiche(paiBasculeNs131.code, paiBasculeNs131.ecrans, statut: 'archive')], paiBasculeNs131), isNull);
    });
  });

  group('les autres recompositions des primes suivent la même bascule', () {
    test('rhaPrimesAgent (onglet « Primes » de la fiche employé) : vide quand la NS 132 est fermée', () {
      expect(rhaPrimesAgent(const [], 'caissiere', 3, 2), isNotEmpty);
      expect(rhaPrimesAgent(const [], 'caissiere', 3, 2, primesNs132: false), isEmpty);
    });
    test('rhbSolde (fiche d’évaluation et de solde) : primes et prélèvement à zéro selon les bascules', () {
      RhbSolde s({bool p = true, bool n = true}) => rhbSolde(
          salaireBrut: 200000,
          prelevementPct: 10,
          gardes: 3,
          permanences: 2,
          montantGarde: 1500,
          montantPermanence: 800,
          montantAccueil: 7000,
          ans: 0,
          primesNs132: p,
          sanctionsNs131: n);
      expect([s().brut, s().prelevement], [200000 + 4500 + 1600 + 7000, 21310]);
      expect([s(p: false).brut, s(p: false).primeGarde, s(p: false).primeAccueil, s(p: false).prelevement], [200000, 0, 0, 20000]);
      expect([s(n: false).brut, s(n: false).prelevement], [213100, 0]);
    });
  });

  group('signataires et exercice, lus au magasin (jamais écrits en dur)', () {
    final personnel = <M>[
      {'nomComplet': 'MEDECIN Chef', 'fonction': 'medecin', 'poste': 'Directeur Médical', 'statut': 'actif'},
      {'nomComplet': 'DAF Une', 'fonction': 'direction', 'poste': 'Directrice de l’Administration et des Finances', 'statut': 'actif'},
      {'nomComplet': 'ASSISTANT Un', 'fonction': 'comptable', 'poste': 'Assistant de Direction', 'statut': 'actif'},
      {'nomComplet': 'COMPTABLE Un', 'fonction': 'comptable', 'poste': 'Comptable', 'statut': 'actif'},
      {'nomComplet': 'ANCIEN Comptable', 'fonction': 'comptable', 'poste': 'Comptable', 'statut': 'archive'},
    ];
    test('chaque qualité trouve son titulaire par le poste ; l’assistant ne signe pas pour le comptable', () {
      expect(paiSignataire(personnel, PaiQualite.comptable), 'COMPTABLE Un');
      expect(paiSignataire(personnel, PaiQualite.daf), 'DAF Une');
      expect(paiSignataire(personnel, PaiQualite.direction), 'MEDECIN Chef');
      expect(paiSignataire(personnel, PaiQualite.surveillant), isNull, reason: 'personne : la pièce imprime une ligne sans nom');
    });
    test('un directeur général passe avant le directeur médical ; un personnel vide ne nomme personne', () {
      expect(paiSignataire([...personnel, {'nomComplet': 'DG Un', 'poste': 'Directeur Général', 'statut': 'actif'}], PaiQualite.direction), 'DG Un');
      expect(paiSignataire(const [], PaiQualite.comptable), isNull);
    });
    test('l’exercice de la paie est l’exercice ouvert qui contient la date, sinon l’année de l’horloge', () {
      final exos = <M>[
        {'annee': 2026, 'debut': '2026-01-01', 'fin': '2026-12-31', 'etat': 'ouvert', 'statut': 'actif'},
        {'annee': 2025, 'debut': '2025-01-01', 'fin': '2025-12-31', 'etat': 'clos', 'statut': 'actif'},
      ];
      expect(paiExercice(exos, DateTime(2026, 10, 30)), 2026);
      expect(paiExercice(const [], DateTime(2027, 2, 1)), 2027);
      expect(paiExercice(exos, DateTime(2025, 6, 1)), 2025, reason: 'exercice clos : l’horloge répond');
    });
  });
}
