// La retenue d'AIB sur facture fournisseur : taux du barème daté, refus nommés, pièce plate équilibrée (RG-10), reversement au 10 reporté.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

CpdFiche v(String id, String situation, num taux, {String? effet, bool arrete = true}) => {
      'id': id, 'situation': situation, 'taux': taux, 'dateEffet': effet,
      'statutArret': arrete ? cpdStatutArrete : cpdStatutNonArrete, 'statut': 'actif',
    };

void main() {
  // La catégorie d'une retenue EST une situation de l'acheteur : « sans » = sans IFU actif (5 %), « actif » = IFU actif (1 %, non arrêté).
  const sans = 'ifu_inactif_ou_absent';
  const actif = 'ifu_actif';
  final bareme = [
    v('B1', sans, 5, effet: '2026-09-07'),
    v('B2', actif, 1, arrete: false),
    v('B3', sans, 6, effet: '2027-01-01'),
  ];

  test('le taux vient du barème À LA DATE : 5 % en 2026, 6 % après la version datée', () {
    expect(cpdCalculerRetenueAib(bareme, sans, 246450, DateTime(2026, 10, 1)).montant, 12323); // 12 322,5 arrondi au franc
    expect(cpdCalculerRetenueAib(bareme, sans, 100000, DateTime(2027, 2, 1)).montant, 6000);
  });

  test('refus nommés : taux non arrêté, avant la première version, base nulle', () {
    expect(() => cpdCalculerRetenueAib(bareme, actif, 1000, DateTime(2026, 10, 1)), throwsA(isA<RefusRetenueAib>().having((e) => e.motif, 'motif', contains(actif))));
    expect(() => cpdCalculerRetenueAib(bareme, sans, 1000, DateTime(2026, 9, 1)), throwsA(isA<RefusRetenueAib>().having((e) => e.motif, 'motif', contains('07/09/2026'))));
    expect(() => cpdCalculerRetenueAib(bareme, sans, 0, DateTime(2026, 10, 1)), throwsA(isA<RefusRetenueAib>()));
  });

  test('la retenue porte sa situation et la VERSION du barème : une correction ultérieure ne la réécrit pas ; une situation inconnue est refusée en la nommant', () {
    final r = cpdCalculerRetenueAib(bareme, sans, 200000, DateTime(2026, 10, 1));
    expect(r.situation, sans);
    expect(r.versFiche()['situation'], sans);
    expect(r.versFiche()['versionId'], 'B1');
    expect(r.versFiche().containsKey('code'), isFalse);
    expect(r.dateEffet, '2026-09-07');
    final situations = [
      {'id': 'S1', 'code': sans, 'libelle': 'Sans IFU actif', 'declencheur': 'ifu_absent', 'ordre': 1, 'statut': 'actif'}
    ];
    expect(() => cpdCalculerRetenueAib(bareme, actif, 1000, DateTime(2026, 10, 1), situations: situations),
        throwsA(isA<RefusRetenueAib>().having((e) => e.motif, 'motif', contains('n\'est pas active'))));
  });

  test('la pièce est plate, en brouillon, équilibrée : débit 401000, crédit 4478', () {
    final r = cpdCalculerRetenueAib(bareme, sans, 200000, DateTime(2026, 10, 1));
    final l = cpdEcrituresRetenueAib(retenue: r, numero: 'ACH-2026-00001', date: '2026-10-01', reference: 'FF-1', fournisseur: 'GPB', pieceId: 'FF0001');
    expect(l.length, 2);
    expect(l.every((x) => x['statut'] == 'brouillon'), isTrue);
    expect(l[0]['compte'], '401000');
    expect(l[0]['debit'], 10000);
    expect(l[1]['compte'], cpdCompteAibRetenu);
    expect(l[1]['credit'], 10000);
  });

  test('reversement : le 10 du mois suivant, reporté au lundi si week-end, jamais avancé', () {
    expect(cpdEcheanceReversementAib(DateTime(2026, 10, 15)), DateTime(2026, 11, 10)); // mardi
    expect(cpdEcheanceReversementAib(DateTime(2026, 11, 20)), DateTime(2026, 12, 10)); // jeudi
    expect(cpdEcheanceReversementAib(DateTime(2026, 5, 3)), DateTime(2026, 6, 10)); // mercredi
    expect(cpdEcheanceReversementAib(DateTime(2026, 7, 2)), DateTime(2026, 8, 10)); // lundi
    expect(cpdEcheanceReversementAib(DateTime(2026, 12, 5)), DateTime(2027, 1, 11)); // 10/01/2027 dimanche → lundi 11
  });

  test('une facture ne porte qu\'une retenue ; archivée, aucune', () {
    expect(cpdControlerRetenueFacture({'statut': 'actif'}), isNull);
    expect(cpdControlerRetenueFacture({'statut': 'actif', 'retenueAib': {'montant': 1}}), contains('déjà'));
    expect(cpdControlerRetenueFacture({'statut': 'archive'}), contains('archivée'));
  });

  test('le registre totalise par mois et date le reversement ; ignore les factures sans retenue ou archivées', () {
    final reg = cpdRegistreRetenuesAib([
      {'reference': 'A', 'fournisseurNom': 'X', 'date': '2026-10-02', 'retenueAib': {'situation': sans, 'taux': 5, 'base': 1000, 'montant': 50, 'date': '2026-10-02'}},
      {'reference': 'B', 'fournisseurNom': 'Y', 'date': '2026-10-20', 'retenueAib': {'situation': sans, 'taux': 5, 'base': 2000, 'montant': 100, 'date': '2026-10-20'}},
      {'reference': 'C', 'date': '2026-10-21'},
      {'reference': 'D', 'statut': 'archive', 'retenueAib': {'montant': 999, 'date': '2026-10-22'}},
    ]);
    expect(reg.total, 150);
    expect(reg.parMois['2026-10'], 150);
    expect(reg.lignes.length, 2);
    expect(reg.lignes.first['reference'], 'B');
    expect(reg.lignes.first['reversement'], '2026-11-10');
  });
}
