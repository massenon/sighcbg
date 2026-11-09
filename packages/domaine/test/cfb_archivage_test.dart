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

    test('le calendrier reste en service, le paiement de démonstration est rangé avec son motif, son acteur et sa date', () {
      final r = cfbRemettreEcheance(payee, motif: cfbMotifArchivageJeuDemo, par: 'Admin', le: le)!;
      expect([r['paye'], r['datePaiement'], r['montant'], r['reference'], r['valideePar'], r['statut']], [false, null, null, null, null, 'actif']);
      expect(r['echeance'], '2026-01-12', reason: 'la date due ne bouge pas');
      final trace = (r['paiementsArchives'] as List).single as Map;
      expect([trace['paye'], trace['reference'], trace['montant'], trace['statut'], trace['_archivePar'], trace['_motifArchivage']],
          [true, 'VIR-1', 120000, 'archive', 'Admin', 'Jeu de démonstration, mise en production']);
    });

    test('une échéance sans paiement n\'est pas touchée ; rejouer ne perd pas la première trace', () {
      expect(cfbRemettreEcheance({'id': 'E', 'paye': false}, motif: 'm', par: 'A', le: le), isNull);
      final une = cfbRemettreEcheance(payee, motif: 'm', par: 'A', le: le)!;
      final deux = cfbRemettreEcheance({...une, 'paye': true, 'reference': 'VIR-2'}, motif: 'm', par: 'A', le: le)!;
      expect((deux['paiementsArchives'] as List).length, 2);
    });
  });

  test('le bilan compte par collection, à part les brouillons, et ne compte que les collections touchées', () {
    const b = CfbBilanArchivage(parCollection: {'patients': 120, 'ecritures': 1211, 'vide': 0}, brouillons: {'ecritures': 642, 'resultatsImagerie': 6}, echeancesRemises: 63);
    expect(b.tables, 2);
    expect(b.total, 1331);
    expect(b.totalBrouillons, 648);
    expect(cfbToastArchivage(b), startsWith('2 table(s) archivée(s) — '));
    expect(cfbToastArchivage(b), contains('dont'));
    expect(cfbToastArchivage(b), contains('brouillon(s)'));
    expect(cfbToastArchivage(b), contains('Rien n’est supprimé'));
    final lignes = cfbLignesBilanArchivage(b);
    expect(lignes.first, startsWith('ecritures : '));
    expect(lignes.first, contains('dont'));
    expect(lignes.length, 2);
  });
}
