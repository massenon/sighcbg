// L'AIB SUBI sur facture fournisseur (position de la Direction, 09/11/2026) : l'AIB facturé se contrôle en montants entiers, la pièce est plate et équilibrée en
// brouillon (débit compte d'AIB subi, crédit compte fournisseur), les comptes se lisent aux Paramètres à la date de la pièce, une facture ne porte qu'un AIB
// subi, un taux hors barème est SIGNALÉ sans bloquer, et l'imputation sur l'impôt sur les bénéfices est indiquée en lecture.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

CpdFiche v(String id, String situation, num taux, {String? effet, bool arrete = true}) => {
      'id': id, 'situation': situation, 'taux': taux, 'dateEffet': effet,
      'statutArret': arrete ? cpdStatutArrete : cpdStatutNonArrete, 'arrete': arrete, 'statut': 'actif',
    };

CpdFiche s(String code, String declencheur, int ordre) => {'id': 'S-$code', 'code': code, 'libelle': code, 'declencheur': declencheur, 'ordre': ordre, 'statut': 'actif'};

Map<String, Object?> facture({Object? aib = const {'montant': 10000, 'taux': 5, 'baseHt': 200000}, Map<String, Object?> plus = const {}}) => {
      'id': 'FFR1',
      'reference': 'FF-0001',
      'fournisseurNom': 'Grossiste Pharma Borgou',
      'date': '2026-10-12',
      'montantFacture': 210000,
      'statut': 'actif',
      if (aib != null) 'aibFacture': aib,
      ...plus,
    };

void main() {
  final situations = [s('ifu_actif', cpdDeclencheurIfuRenseigne, 1), s('ifu_inactif_ou_absent', cpdDeclencheurIfuAbsent, 2)];
  final bareme = [v('B1', 'ifu_inactif_ou_absent', 5, effet: '2026-09-07'), v('B2', 'ifu_actif', 1, arrete: false)];

  group('l\'AIB facturé : facultatif, entier, cohérent', () {
    test('vide : rien à contrôler, et l\'AIB facturé se retire', () {
      expect(cpdControlerAibFacture(), isNull);
      expect(cpdAibFactureDepuisSaisie(), isNull);
    });

    test('complet et cohérent : 5 % de 200 000 = 10 000', () {
      expect(cpdControlerAibFacture(montant: '10000', taux: '5', base: '200000', montantFacture: 210000), isNull);
      expect(cpdAibFactureDepuisSaisie(montant: '10000', taux: '5', base: '200000'), {'montant': 10000, 'taux': 5, 'baseHt': 200000});
      expect(cpdControlerAibFacture(montant: '10 000', taux: '5', base: '200 000'), isNull, reason: 'espaces de milliers tolérés');
    });

    test('refus nommés : incomplet, non entier, taux hors 1-100, nul, INCOHÉRENT avec la base et le taux, base au-dessus du facturé', () {
      expect(cpdControlerAibFacture(montant: '10000', taux: '5'), contains('AIB_FACTURE_INCOMPLET'));
      expect(cpdControlerAibFacture(montant: '10000,5', taux: '5', base: '200000'), contains('AIB_FACTURE_NON_ENTIER'));
      expect(cpdControlerAibFacture(montant: '10000', taux: '5', base: '200000,5'), contains('AIB_FACTURE_NON_ENTIER'));
      expect(cpdControlerAibFacture(montant: '10000', taux: '5,5', base: '200000'), contains('AIB_FACTURE_TAUX_INVALIDE'));
      expect(cpdControlerAibFacture(montant: '10000', taux: '0', base: '200000'), contains('AIB_FACTURE_TAUX_INVALIDE'));
      expect(cpdControlerAibFacture(montant: '10000', taux: '101', base: '200000'), contains('AIB_FACTURE_TAUX_INVALIDE'));
      expect(cpdControlerAibFacture(montant: '0', taux: '5', base: '200000'), contains('AIB_FACTURE_MONTANT_NUL'));
      expect(cpdControlerAibFacture(montant: 'abc', taux: '5', base: '200000'), contains('AIB_FACTURE_NON_NUMERIQUE'));
      final incoherent = cpdControlerAibFacture(montant: '9000', taux: '5', base: '200000')!;
      expect(incoherent, contains('AIB_FACTURE_INCOHERENT'));
      expect(incoherent, contains('10 000'), reason: 'le refus dit le montant attendu');
      expect(cpdControlerAibFacture(montant: '10000', taux: '5', base: '200000', montantFacture: 150000), contains('AIB_FACTURE_BASE_SUPERIEURE'));
    });

    test('l\'arrondi est celui du franc : 5 % de 169 492 = 8 475 (8 474,6)', () {
      expect(cpdControlerAibFacture(montant: '8475', taux: '5', base: '169492'), isNull);
      expect(cpdControlerAibFacture(montant: '8474', taux: '5', base: '169492'), contains('AIB_FACTURE_INCOHERENT'));
    });
  });

  group('le taux se compare au barème arrêté : signalé, jamais bloquant', () {
    test('5 % est arrêté au 12/10/2026 : pas de signal', () {
      expect(cpdSignalTauxAibFacture(situations, bareme, 5, DateTime(2026, 10, 12)), isNull);
    });

    test('1 % n\'est pas arrêté : « Taux non arrêté au barème », avec ce qui l\'est', () {
      final signal = cpdSignalTauxAibFacture(situations, bareme, 1, DateTime(2026, 10, 12))!;
      expect(signal, contains('Taux non arrêté au barème'));
      expect(signal, contains('5 %'));
    });

    test('avant la première version arrêtée : aucun taux arrêté, le signal le dit ; le 1 % arrêté un jour cesse d\'être signalé', () {
      expect(cpdSignalTauxAibFacture(situations, bareme, 5, DateTime(2026, 8, 1)), contains('aucun taux n\'est arrêté'));
      final arrete = [...bareme, v('B4', 'ifu_actif', 1, effet: '2026-12-01')];
      expect(cpdSignalTauxAibFacture(situations, arrete, 1, DateTime(2026, 12, 15)), isNull);
      expect(cpdSignalTauxAibFacture(situations, arrete, 1, DateTime(2026, 11, 15)), isNotNull);
    });
  });

  group('constater l\'AIB subi : une pièce plate, en brouillon, équilibrée', () {
    final comptes = cpaComptesALaDate(cpaFichesGraine(), DateTime(2026, 10, 12));

    test('débit 4492, crédit 401000 du même montant, journal des achats, origine nommée', () {
      final r = cpdConstaterAibSubi(facture: facture(), date: DateTime(2026, 10, 12), comptes: comptes, numero: 'AIBS-FF-0001');
      final l = r.ecritures;
      expect(l.length, 2);
      expect(l.every((x) => x['statut'] == 'brouillon' && x['journal'] == 'ACH' && x['numero'] == 'AIBS-FF-0001' && x['pieceId'] == 'FFR1'), isTrue);
      expect([l[0]['compte'], l[0]['debit'], l[0]['credit']], ['4492', 10000, 0]);
      expect([l[1]['compte'], l[1]['debit'], l[1]['credit']], ['401000', 0, 10000]);
      expect(l[0]['origine'], 'Automatique — AIB subi');
      expect(l.fold<num>(0, (a, x) => a + (x['debit'] as num)), l.fold<num>(0, (a, x) => a + (x['credit'] as num)), reason: 'RG-10');
      expect(r.fiche, containsPair('montant', 10000));
      expect([r.fiche['taux'], r.fiche['base'], r.fiche['date'], r.fiche['compteSubi'], r.fiche['comptesVersion']], [5, 200000, '2026-10-12', '4492', 1]);
    });

    test('les comptes sont ceux de la version EN VIGUEUR à la date de la pièce, les anciennes pièces gardent les leurs', () {
      final fiches = [
        ...cpaFichesGraine(),
        {
          'id': 'P2', 'statut': 'actif', 'rubrique': cpaRubriqueComptes, 'version': 2, 'dateEffet': '2026-11-01', 'compteAibSubi': '4491', 'compteAibRetenu': '4478',
          'compteImputation': '891', 'compteFournisseur': '401000', 'decideur': 'Expert-comptable', 'dateDecision': '2026-10-30', 'motif': 'confirmation',
        },
      ];
      CpdAibSubiConstate a(String date) => cpdConstaterAibSubi(
          facture: facture(plus: {'date': date}), date: DateTime.parse(date), comptes: cpaComptesALaDate(fiches, DateTime.parse(date)), numero: 'N');
      expect(a('2026-10-12').ecritures[0]['compte'], '4492');
      expect(a('2026-11-12').ecritures[0]['compte'], '4491');
      expect(a('2026-11-12').fiche['comptesVersion'], 2);
    });

    test('le signal du taux est porté par la fiche (le taux a été constaté tel que facturé)', () {
      final r = cpdConstaterAibSubi(
          facture: facture(aib: {'montant': 2000, 'taux': 1, 'baseHt': 200000}), date: DateTime(2026, 10, 12), comptes: comptes, numero: 'N',
          signalTaux: cpdSignalTauxAibFacture(situations, bareme, 1, DateTime(2026, 10, 12)));
      expect(r.fiche['signalTaux'], contains('Taux non arrêté au barème'));
      expect(r.ecritures[0]['debit'], 2000);
    });

    test('refus nommés : archivée, sans AIB facturé, déjà constaté, incohérent', () {
      CpdAibSubiConstate essai(Map<String, Object?> f) => cpdConstaterAibSubi(facture: f, date: DateTime(2026, 10, 12), comptes: comptes, numero: 'N');
      expect(() => essai(facture(plus: {'statut': 'archive'})), throwsA(isA<RefusAibSubi>().having((e) => e.motif, 'motif', contains('archivée'))));
      expect(() => essai(facture(aib: null)), throwsA(isA<RefusAibSubi>().having((e) => e.motif, 'motif', contains('AIB_SUBI_SANS_AIB_FACTURE'))));
      expect(() => essai(facture(plus: {'aibSubi': {'montant': 10000}})), throwsA(isA<RefusAibSubi>().having((e) => e.motif, 'motif', contains('déjà son AIB subi'))));
      expect(() => essai(facture(aib: {'montant': 9000, 'taux': 5, 'baseHt': 200000})),
          throwsA(isA<RefusAibSubi>().having((e) => e.motif, 'motif', contains('AIB_FACTURE_INCOHERENT'))));
    });
  });

  group('le registre et l\'imputation en lecture', () {
    final comptes = cpaComptesALaDate(cpaFichesGraine(), DateTime(2026, 10, 12));
    final factures = [
      facture(plus: {'reference': 'A', 'aibSubi': {'montant': 10000, 'taux': 5, 'base': 200000, 'date': '2026-10-12', 'compteSubi': '4492'}}),
      facture(plus: {'reference': 'B', 'aibSubi': {'montant': 2000, 'taux': 1, 'base': 200000, 'date': '2026-11-03', 'signalTaux': 'Taux non arrêté au barème'}, 'retenueAib': {'montant': 3000, 'date': '2026-11-04'}}),
      facture(plus: {'reference': 'C', 'statut': 'archive', 'aibSubi': {'montant': 999, 'date': '2026-10-01'}}),
      facture(plus: {'reference': 'D', 'retenueAib': {'montant': 500, 'date': '2025-12-30'}}),
      facture(aib: null, plus: {'reference': 'E'}),
    ];

    test('une ligne par facture qui porte son AIB subi, total et mois ; les archivées et les autres sont ignorées', () {
      final reg = cpdRegistreAibSubi(factures);
      expect(reg.total, 12000);
      expect(reg.parMois, {'2026-10': 10000, '2026-11': 2000});
      expect(reg.lignes.map((l) => l['reference']), ['B', 'A']);
      expect(reg.lignes.first['signalTaux'], isNotNull);
    });

    test('imputation indiquée : subi + retenu de l\'EXERCICE, compte d\'imputation des Paramètres, rien d\'écrit', () {
      final i = cpdImputationAibExercice(factures, 2026, comptes);
      expect([i.subi, i.retenu, i.total, i.compteImputation], [12000, 3000, 15000, '891']);
      expect(cpdImputationAibExercice(factures, 2025, comptes).total, 500);
      expect(cpdImputationAibExercice(factures, 2027, comptes).total, 0);
    });
  });
}
