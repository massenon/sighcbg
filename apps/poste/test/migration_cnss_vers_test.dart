import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/migration_cnss_vers.dart';

/// D2 (Direction, 09/11/2026) : un poste déjà installé reçoit le versement CNSS du 15 (`CNSS-VERS`, non arrêté) au démarrage.
/// Le jeu livré sert de poste « à jour » ; on lui retire CNSS-VERS pour figurer un poste installé avant son arrivée.
Magasin livre() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

final auj = DateTime(2026, 11, 9);

/// Un poste installé AVANT CNSS-VERS : ni la fiche, ni ses échéances.
Magasin ancienPoste() {
  final m = livre();
  m.collection('obligationsFiscales').remplacerContenu([for (final f in m.collection('obligationsFiscales').toutes) if (f['code'] != codeCnssVers) f]);
  m.collection('echeancesFiscales').remplacerContenu([for (final f in m.collection('echeancesFiscales').toutes) if (f['code'] != codeCnssVers) f]);
  return m;
}

List<Map<String, Object?>> vers(Magasin m, String c) => [for (final f in m.collection(c).toutes) if (f['code'] == codeCnssVers) f];

void main() {
  test('un poste sans CNSS-VERS la reçoit : non arrêtée, échéances non payées, journalisée par « migration »', () {
    final m = ancienPoste();
    expect(vers(m, 'obligationsFiscales'), isEmpty);
    final audit0 = m.collection('audit').toutes.length;
    final r = migrerCnssVers(m, aujourdhui: auj);
    expect(r.obligationAjoutee, isTrue);
    expect(r.echeancesCreees, 12);
    final f = vers(m, 'obligationsFiscales').single;
    expect(f['jour'], 15);
    expect(f['statutArret'], 'non_arrete');
    final e = vers(m, 'echeancesFiscales');
    expect(e.length, 12);
    expect(e.every((x) => x['paye'] == false && x['reference'] == null && x['exercice'] == 2026), isTrue);
    expect(e.every((x) => '${x['echeanceTheorique']}'.endsWith('-15')), isTrue);
    expect({for (final x in e) x['id']}.length, 12);
    final journal = m.collection('audit').toutes.take(m.collection('audit').toutes.length - audit0).toList();
    expect(journal.length, 2);
    expect(journal.every((l) => l['utilisateur'] == 'migration'), isTrue);
    expect(m.utilisateur, isNot('migration'), reason: 'l\'acteur de la session est restitué');
  });

  test('deux démarrages = une seule fiche, et rien de plus au second', () {
    final m = ancienPoste();
    migrerCnssVers(m, aujourdhui: auj);
    final audit = m.collection('audit').toutes.length;
    final r2 = migrerCnssVers(m, aujourdhui: auj);
    expect(r2.aFaitQuelqueChose, isFalse);
    expect(vers(m, 'obligationsFiscales').length, 1);
    expect(vers(m, 'echeancesFiscales').length, 12);
    expect(m.collection('audit').toutes.length, audit, reason: 'aucune ligne de journal sur un démarrage sans effet');
  });

  test('une fiche modifiée et arrêtée par la Direction reste intacte, ses échéances payées aussi', () {
    final m = livre();
    final o = m.collection('obligationsFiscales');
    final id = vers(m, 'obligationsFiscales').single['id'];
    o.mettreAJour(id, {'jour': 16, 'statutArret': 'arrete', 'dateArret': '2026-11-09', 'decideurArret': 'La Direction'});
    final e = m.collection('echeancesFiscales');
    final une = vers(m, 'echeancesFiscales').first;
    e.mettreAJour(une['id'], {'paye': true, 'reference': 'QUIT-1'});
    final avantO = [for (final f in o.toutes) {...f}], avantE = [for (final f in e.toutes) {...f}];
    final r = migrerCnssVers(m, aujourdhui: auj);
    expect(r.aFaitQuelqueChose, isFalse);
    expect(o.toutes, avantO);
    expect(e.toutes, avantE);
  });

  test('une fiche archivée par la Direction ne ressuscite pas', () {
    final m = livre();
    final o = m.collection('obligationsFiscales');
    o.archiver(vers(m, 'obligationsFiscales').single['id']);
    final avant = o.toutes.length;
    final r = migrerCnssVers(m, aujourdhui: auj);
    expect(r.aFaitQuelqueChose, isFalse);
    expect(o.toutes.length, avant);
    expect(o.actives.where((f) => f['code'] == codeCnssVers), isEmpty);
  });

  test('fiche présente mais échéances manquantes : seules les manquantes sont créées, les existantes (payées) ne bougent pas', () {
    final m = livre();
    final e = m.collection('echeancesFiscales');
    final ex = vers(m, 'echeancesFiscales');
    e.mettreAJour(ex[0]['id'], {'paye': true, 'reference': 'QUIT-X'});
    final retirees = ex.skip(3).map((x) => x['id']).toSet();
    e.remplacerContenu([for (final f in e.toutes) if (!retirees.contains(f['id'])) f]);
    final avant = [for (final f in e.toutes) {...f}];
    final r = migrerCnssVers(m, aujourdhui: auj);
    expect(r.obligationAjoutee, isFalse);
    expect(r.echeancesCreees, retirees.length);
    expect(vers(m, 'echeancesFiscales').length, 12);
    for (final f in avant) {
      expect(e.parId(f['id']), f, reason: 'une échéance existante n\'est jamais réécrite');
    }
  });

  test('exercice sans aucune échéance : rien n\'est créé ici, l\'écran engendre tout le calendrier à l\'ouverture', () {
    final m = ancienPoste();
    m.collection('echeancesFiscales').remplacerContenu(const []);
    final r = migrerCnssVers(m, aujourdhui: auj);
    expect(r.obligationAjoutee, isTrue);
    expect(r.echeancesCreees, 0);
    expect(m.collection('echeancesFiscales').toutes, isEmpty);
  });

  test('poste neuf (aucune obligation) : rien, le semis de l\'écran s\'en charge', () {
    final m = livre();
    m.collection('obligationsFiscales').remplacerContenu(const []);
    expect(migrerCnssVers(m, aujourdhui: auj).aFaitQuelqueChose, isFalse);
    expect(m.collection('obligationsFiscales').toutes, isEmpty);
  });
}
