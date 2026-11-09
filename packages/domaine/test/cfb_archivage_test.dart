import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// D6 (09/11/2026) : les règles PURES de l'archivage du jeu de démonstration. Le geste sur le magasin livré est sondé côté poste (`archivage_jeu_test.dart`).
void main() {
  test('le motif des fiches archivées est celui de la Direction', () => expect(cfbMotifArchivageJeuDemo, 'Jeu de démonstration, mise en production'));

  test('un brouillon se reconnaît à son statut, à l\'état d\'un inventaire ou à son état — jamais à autre chose', () {
    expect(cfbEstBrouillon({'statut': 'brouillon'}), isTrue);
    expect(cfbEstBrouillon({'statutInv': 'brouillon'}), isTrue);
    expect(cfbEstBrouillon({'etat': 'brouillon'}), isTrue);
    expect(cfbEstBrouillon({'statut': 'validee'}), isFalse);
    expect(cfbEstBrouillon({'statut': 'archive', 'statutAvantArchivage': 'brouillon'}), isFalse, reason: 'déjà archivé : ce n\'est plus un brouillon à compter');
    expect(cfbEstBrouillon(const {}), isFalse);
  });

  test('refus nommés : bascule fermée, puis motif manquant ; sinon rien à dire', () {
    expect(cfbRefusArchivage(autorisee: false, motif: 'x'), contains('verrouillée'));
    expect(cfbRefusArchivage(autorisee: true, motif: '  '), contains('Motif obligatoire'));
    expect(cfbRefusArchivage(autorisee: true, motif: 'Mise en production'), isNull);
  });

  test('les marques d\'archivage portent date, auteur et motif', () {
    final m = cfbMarquesArchivage(motif: cfbMotifArchivageJeuDemo, par: 'Admin', le: DateTime(2026, 11, 9, 10));
    expect(m, {'_archiveLe': '2026-11-09T10:00:00.000', '_archivePar': 'Admin', '_motifArchivage': 'Jeu de démonstration, mise en production'});
  });

  group('la remise d\'une échéance à non payée', () {
    final le = DateTime(2026, 11, 9);
    final payee = {
      'id': 'ECH0001', 'statut': 'actif', 'code': 'ITS', 'paye': true, 'datePaiement': '2026-01-12', 'montant': 120000, 'moyen': 'Virement bancaire',
      'reference': 'VIR-1', 'valideePar': 'Mme X', 'echeance': '2026-01-12',
    };

    test('le calendrier reste en service, le paiement de démonstration est SUPPRIMÉ : aucune trace, rien n\'est rangé', () {
      final r = cfbRetirerPaiementDemo({...payee, 'observation': 'virement du 12', 'paiementsArchives': const []})!;
      final f = r.fiche;
      expect(r.retires, 1);
      expect([f['paye'], f['statut'], f['echeance'], f['code']], [false, 'actif', '2026-01-12', 'ITS'], reason: 'le calendrier ne bouge pas, la date due non plus');
      for (final c in [...cfbChampsPaiementEcheance.where((c) => c != 'paye'), 'paiementsArchives']) {
        expect(f.containsKey(c), isFalse, reason: 'plus de trace de $c');
      }
      expect(f.keys.where((k) => k.contains('rchiv')), isEmpty);
    });

    test('une échéance sans paiement n\'est pas touchée ; une ancienne trace d\'archivage est retirée et comptée', () {
      expect(cfbRetirerPaiementDemo({'id': 'E', 'paye': false}), isNull);
      final ancienne = {'id': 'E', 'paye': false, 'paiementsArchives': [{'paye': true, 'reference': 'VIR-0'}]};
      final r = cfbRetirerPaiementDemo(ancienne)!;
      expect(r.retires, 1);
      expect(r.fiche.containsKey('paiementsArchives'), isFalse);
      final deux = cfbRetirerPaiementDemo({...payee, 'paiementsArchives': [{'paye': true}]})!;
      expect(deux.retires, 2, reason: 'le paiement de la fiche et celui de l\'ancienne trace');
    });
  });

  test('le bilan compte par collection, à part les brouillons, et ne compte que les collections touchées', () {
    const b = CfbBilanArchivage(parCollection: {'patients': 120, 'ecritures': 1211, 'vide': 0}, brouillons: {'ecritures': 642, 'resultatsImagerie': 6}, paiementsRetires: 63);
    expect(b.tables, 2);
    expect(b.total, 1331);
    expect(b.totalBrouillons, 648);
    expect(cfbToastArchivage(b), startsWith('2 table(s) archivée(s) — '));
    expect(cfbToastArchivage(b), contains('dont'));
    expect(cfbToastArchivage(b), contains('brouillon(s)'));
    expect(cfbToastArchivage(b), contains('Aucune fiche n’est supprimée'));
    expect(cfbToastArchivage(b), contains('63 paiement(s) fictif(s)'));
    final lignes = cfbLignesBilanArchivage(b);
    expect(lignes.first, startsWith('ecritures : '));
    expect(lignes.first, contains('dont'));
    expect(lignes.length, 2);
  });
}
