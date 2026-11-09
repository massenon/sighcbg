// Le bareme de l'AIB : le taux en vigueur À UNE DATE, versionné par date d'effet (comme la grille des primes), jamais écrasé.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

CpdFiche v(String id, String code, num taux, {String? effet, bool arrete = true, String statut = 'actif', String? dateArret, String? decideur}) => {
      'id': id,
      'code': code,
      'categorie': 'Catégorie $code',
      'taux': taux,
      'dateEffet': effet,
      'statutArret': arrete ? cpdStatutArrete : cpdStatutNonArrete,
      'dateArret': dateArret,
      'decideurArret': decideur,
      'statut': statut,
    };

void main() {
  // 5 % arrêté depuis le 07/09/2026 ; le 1 % et le 3 % figurent au bareme mais ne sont pas arrêtés ; une CORRECTION ajoute une version à 6 % au 01/01/2027.
  final bareme = [
    v('B1', 'AIB-GEN', 5, effet: '2026-09-07', dateArret: '2026-09-07', decideur: 'Direction'),
    v('B2', 'AIB-1', 1, arrete: false),
    v('B3', 'AIB-3', 3, arrete: false),
    v('B4', 'AIB-GEN', 6, effet: '2027-01-01', dateArret: '2026-12-15', decideur: 'Direction'),
  ];

  group('le taux en vigueur à une date', () {
    test('avant la première version arrêtée : AUCUN taux, et le motif nomme la date de prise d\'effet', () {
      final r = cpdTauxAibALaDate(bareme, 'AIB-GEN', DateTime(2026, 9, 6));
      expect(r.taux, isNull);
      expect(r.motif, contains('07/09/2026'));
    });

    test('le jour de la prise d\'effet et après : 5 %, pas 6 % tant que la version corrigée n\'a pas pris effet', () {
      expect(cpdTauxAibALaDate(bareme, 'AIB-GEN', DateTime(2026, 9, 7)).taux, 5);
      expect(cpdTauxAibALaDate(bareme, 'AIB-GEN', DateTime(2026, 12, 31)).taux, 5);
      expect(cpdTauxAibALaDate(bareme, 'AIB-GEN', DateTime(2026, 12, 31)).version!['id'], 'B1');
    });

    test('une correction AJOUTE une version : à partir de sa date d\'effet 6 %, et une date passée garde 5 % (l\'acompte déjà retenu ne se réécrit pas)', () {
      expect(cpdTauxAibALaDate(bareme, 'AIB-GEN', DateTime(2027, 1, 1)).taux, 6);
      expect(cpdTauxAibALaDate(bareme, 'AIB-GEN', DateTime(2027, 6, 30)).version!['id'], 'B4');
      expect(cpdTauxAibALaDate(bareme, 'AIB-GEN', DateTime(2026, 10, 1)).taux, 5);
    });

    test('un taux NON ARRÊTÉ ne s\'applique jamais : taux nul, motif qui nomme ce qui attend la Direction', () {
      final r = cpdTauxAibALaDate(bareme, 'AIB-1', DateTime(2026, 10, 1));
      expect(r.taux, isNull);
      expect(r.enAttente, hasLength(1));
      expect(r.motif, contains('1 %'));
      expect(r.motif, contains('n\'est pas arrêté'));
    });

    test('une version ARCHIVÉE est ignorée : le taux précédent reprend (RG-14, la version n\'est pas supprimée)', () {
      final archive = [for (final f in bareme) f['id'] == 'B4' ? {...f, 'statut': 'archive'} : f];
      expect(cpdTauxAibALaDate(archive, 'AIB-GEN', DateTime(2027, 3, 1)).taux, 5);
    });

    test('une catégorie inconnue : aucun taux et un motif', () {
      final r = cpdTauxAibALaDate(bareme, 'AIB-9', DateTime(2026, 10, 1));
      expect(r.taux, isNull);
      expect(r.motif, contains('Aucune version'));
    });

    test('le bareme du jour : une ligne par catégorie, le taux appliqué se lit en chiffres', () {
      final b = cpdBaremeEnVigueur(bareme, DateTime(2026, 11, 9));
      expect([for (final x in b) x.code], ['AIB-GEN', 'AIB-1', 'AIB-3']);
      expect([for (final x in b) x.reponse.taux], [5, null, null]);
    });

    test('le montant retenu : 1 250 000 F à 5 % = 62 500 F ; 333 F à 5 % = 17 F (arrondi au franc)', () {
      expect(cpdMontantAib(1250000, 5), 62500);
      expect(cpdMontantAib(333, 5), 17);
    });
  });

  group('le contrôle d\'une saisie', () {
    final auj = DateTime(2026, 11, 9);
    Map<String, Object?> saisie({String code = 'AIB-GEN', String taux = '5', String effet = '2027-06-01', String statutArret = cpdStatutArrete, String dateArret = '2026-11-09', String decideur = 'Direction'}) =>
        {'code': code, 'categorie': 'Catégorie $code', 'taux': taux, 'dateEffet': effet, 'statutArret': statutArret, 'dateArret': dateArret, 'decideurArret': decideur};

    test('une saisie complète est acceptée', () => expect(cpdControlerVersionAib(saisie(), null, bareme, auj), isNull));

    test('un taux hors de 0 à 100 % est refusé', () {
      expect(cpdControlerVersionAib(saisie(taux: '120'), null, bareme, auj), contains('entre 0 et 100'));
      expect(cpdControlerVersionAib(saisie(taux: 'x'), null, bareme, auj), contains('entre 0 et 100'));
    });

    test('une version arrêtée exige date d\'effet, date d\'arrêt et décideur ; une non arrêtée n\'exige rien de tout cela', () {
      expect(cpdControlerVersionAib(saisie(effet: ''), null, bareme, auj), contains('date d\'effet'));
      expect(cpdControlerVersionAib(saisie(dateArret: ''), null, bareme, auj), contains('date de l\'arrêt'));
      expect(cpdControlerVersionAib(saisie(decideur: ' '), null, bareme, auj), contains('décideur'));
      expect(cpdControlerVersionAib(saisie(statutArret: cpdStatutNonArrete, effet: '', dateArret: '', decideur: ''), null, bareme, auj), isNull);
    });

    test('deux versions d\'une même catégorie ne partagent pas la même date d\'effet', () {
      expect(cpdControlerVersionAib(saisie(effet: '2026-09-07'), null, bareme, auj), contains('07/09/2026'));
    });

    test('une version ARRÊTÉE ne se corrige pas sur place : on ajoute une version ; son motif seul s\'édite', () {
      final b1 = bareme.first;
      final corrige = {...saisie(taux: '6', effet: '2026-09-07', dateArret: '2026-09-07')};
      expect(cpdControlerVersionAib(corrige, b1, bareme, auj), contains('ajouter une nouvelle version'));
      final memeChose = {...saisie(taux: '5', effet: '2026-09-07', dateArret: '2026-09-07'), 'motif': 'précision de rédaction'};
      expect(cpdControlerVersionAib(memeChose, b1, bareme, auj), isNull);
    });

    test('une version NON arrêtée se corrige librement, et l\'arrêt la fait entrer en vigueur', () {
      final b2 = bareme[1];
      final arretee = saisie(code: 'AIB-1', taux: '1', effet: '2026-11-10', dateArret: '2026-11-09');
      expect(cpdControlerVersionAib(arretee, b2, bareme, auj), isNull);
    });
  });
}
