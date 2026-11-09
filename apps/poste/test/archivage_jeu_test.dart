import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/modules/cfg/cfb_commun.dart' show cfbPoserReglage;
import 'package:sigh_poste/modules/cfg/cfb_systeme.dart';

/// D6 (Direction, 09/11/2026) : la mise en production ARCHIVE le jeu de démonstration (RG-14). Banc au GESTE, sur le magasin du jeu LIVRÉ
/// (`assets/donnees/jeu`) : aucune fiche d'activité active après, brouillons compris et jamais validés, essentielles intactes, journal conservé et enrichi, bilan
/// exact, restauration depuis la Corbeille, refus sans bascule ni motif, compteurs de numérotation qui ne reculent pas (RG-01).
Magasin livre() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

String instantane(Magasin m, Iterable<String> noms) => jsonEncode({for (final n in noms) n: m.collection(n).toutes});

List<String> activite(Magasin m) => [
      for (final n in cfbNomsCollections())
        if (!{...cfbEssentielles, ...cfbCollectionsTechniques}.contains(n)) n
    ];

void main() {
  test('refusé tant que la bascule est fermée, puis sans motif : rien n\'est écrit, le refus est nommé', () {
    final m = livre();
    final avant = instantane(m, cfbNomsCollections());
    expect(() => cfbArchiverJeuDemo(m, motifDuGeste: 'Mise en service'), throwsA(isA<CfbRefusArchivage>().having((e) => e.motif, 'motif', contains('verrouillée'))));
    cfbPoserReglage(m, 'reinitAutorisee', true);
    final avantMotif = instantane(m, cfbNomsCollections());
    expect(() => cfbArchiverJeuDemo(m, motifDuGeste: '   '), throwsA(isA<CfbRefusArchivage>().having((e) => e.motif, 'motif', contains('Motif obligatoire'))));
    expect(instantane(m, cfbNomsCollections()), avantMotif);
    expect(avantMotif, isNot(avant), reason: 'seule la bascule a changé');
    expect(m.collection('audit').toutes.where((a) => '${a['action']}'.startsWith('Archivage du jeu')), isEmpty);
  });

  group('archivage du jeu livré', () {
    late Magasin m;
    late CfbBilanArchivage bilan;
    late Map<String, int> activesAvant;
    late int brouillonsAvant, archiveesAvant, auditAvant;
    late String essentiellesAvant;
    late String codePatient, rangFacture, numeroEcriture;
    final conservees = {...cfbEssentielles, ...cfbCollectionsTechniques};
    final auj = DateTime(2026, 11, 9);

    setUpAll(() {
      m = livre();
      cfbPoserReglage(m, 'reinitAutorisee', true);
      m.journaliser('Geste antérieur à l’archivage', 'CFG', 'Essai', 'avant', null, null);
      auditAvant = m.collection('audit').toutes.length;
      activesAvant = {for (final n in activite(m)) n: m.collection(n).actives.length};
      brouillonsAvant = [for (final n in activite(m)) if (n != 'echeancesFiscales') ...m.collection(n).actives.where(cfbEstBrouillon)].length;
      archiveesAvant = [for (final n in cfbNomsCollections()) m.collection(n).archivees.length].fold(0, (a, b) => a + b);
      essentiellesAvant = instantane(m, [for (final n in cfbNomsCollections()) if (conservees.contains(n) && n != 'audit' && n != 'reglages') n]);
      codePatient = patProchainCode(m.collection('patients').toutes, auj);
      rangFacture = '${rangSerieFactures('FN-2026-', m.collection('factures').toutes)}';
      numeroEcriture = cpaNumeroPiece('CAI', 2026, m.collection('ecritures').toutes);
      bilan = cfbArchiverJeuDemo(m, motifDuGeste: 'Mise en production de la clinique');
    });

    test('aucune fiche d\'activité n\'est plus active — files, tâches bloquées, notifications comprises', () {
      for (final n in activite(m)) {
        if (n == 'echeancesFiscales') continue;
        expect(m.collection(n).actives, isEmpty, reason: n);
      }
      for (final n in ['taches', 'notifications', 'patients', 'consultations', 'factures', 'ecritures', 'depenses', 'ordonnances', 'prescriptions', 'mouvements', 'lots', 'bulletins']) {
        expect(activesAvant[n], greaterThan(0), reason: '$n devait avoir des fiches de démonstration');
        expect(m.collection(n).actives, isEmpty, reason: n);
      }
      expect(activesAvant['taches'], isNotNull);
      expect(m.collection('taches').toutes.any((t) => t['statutAvantArchivage'] == 'bloque'), isTrue, reason: 'une tâche bloquée est archivée avec son statut');
    });

    test('chaque fiche porte le motif, l\'acteur et la date ; aucune fiche n\'est supprimée', () {
      final f = m.collection('patients').toutes.first;
      expect(f['statut'], 'archive');
      expect(f['_motifArchivage'], 'Jeu de démonstration, mise en production');
      expect(f['_archivePar'], m.utilisateur);
      expect(DateTime.tryParse('${f['_archiveLe']}'), isNotNull);
      expect(f['statutAvantArchivage'], isNotNull);
      for (final n in activite(m)) {
        expect(m.collection(n).toutes.length, greaterThanOrEqualTo(activesAvant[n]!), reason: '$n : rien n\'est supprimé');
      }
    });

    test('les BROUILLONS sont archivés comme les autres, jamais validés au passage', () {
      final ecr = m.collection('ecritures').toutes;
      final brouillons = ecr.where((e) => e['statutAvantArchivage'] == 'brouillon');
      expect(brouillons.length, 642);
      expect(brouillons.every((e) => e['statut'] == 'archive' && e['validePar'] == null && e['valideLe'] == null), isTrue);
      expect(ecr.where((e) => e['statut'] == 'validee'), isEmpty, reason: 'rien n\'est (re)validé');
      expect(bilan.totalBrouillons, brouillonsAvant);
      expect(bilan.brouillons['ecritures'], 642);
      expect(bilan.brouillons['resultatsImagerie'], 6);
    });

    test('les collections ESSENTIELLES sont intactes — personnel et salaires compris', () {
      final noms = [for (final n in cfbNomsCollections()) if (conservees.contains(n) && n != 'audit' && n != 'reglages') n];
      expect(instantane(m, noms), essentiellesAvant);
      expect(m.collection('personnel').toutes.every((p) => p['salaireBase'] != null), isTrue);
    });

    test('les échéances fiscales sont remises à non payées, leur paiement de démonstration est archivé', () {
      final e = m.collection('echeancesFiscales');
      expect(e.toutes.length, 75, reason: 'le calendrier reste en service');
      expect(e.actives.length, 75);
      expect(e.toutes.any((f) => f['paye'] == true || f['reference'] != null), isFalse);
      final payees = e.toutes.where((f) => f['paiementsArchives'] != null).toList();
      expect(payees, isNotEmpty);
      expect(bilan.echeancesRemises, payees.length);
      final trace = (payees.first['paiementsArchives'] as List).first as Map;
      expect([trace['statut'], trace['_motifArchivage'], trace['_archivePar']], ['archive', 'Jeu de démonstration, mise en production', m.utilisateur]);
      expect(trace['paye'], true);
    });

    test('le journal n\'est PAS vidé : une entrée par collection (compte archivé) et une synthèse', () {
      final a = m.collection('audit').toutes;
      expect(a.length, auditAvant + bilan.tables + 2, reason: 'les entrées antérieures restent ; + une par collection ; + échéances ; + synthèse');
      expect(a.any((l) => l['action'] == 'Geste antérieur à l’archivage'), isTrue);
      final parTable = a.where((l) => l['action'] == 'Archivage du jeu de démonstration').toList();
      expect(parTable.length, bilan.tables);
      final pat = parTable.firstWhere((l) => l['reference'] == 'patients');
      expect((pat['apres'] as Map)['archivees'], activesAvant['patients']);
      expect((pat['apres'] as Map)['motif'], 'Jeu de démonstration, mise en production');
      final synth = a.firstWhere((l) => l['action'] == 'Archivage du jeu de démonstration (synthèse)');
      expect((synth['apres'] as Map)['fiches'], bilan.total);
      expect((synth['apres'] as Map)['brouillons'], brouillonsAvant);
      expect((synth['apres'] as Map)['motifDuGeste'], 'Mise en production de la clinique');
    });

    test('le bilan dit combien de fiches par collection et combien de brouillons', () {
      final attendu = {for (final e in activesAvant.entries) if (e.key != 'echeancesFiscales' && e.value > 0) e.key: e.value};
      expect(bilan.parCollection, attendu);
      expect(bilan.total, attendu.values.fold(0, (a, b) => a + b));
      expect(cfbToastArchivage(bilan), contains('${bilan.tables} table(s) archivée(s)'));
      expect(cfbToastArchivage(bilan), contains('brouillon(s)'));
      expect(cfbLignesBilanArchivage(bilan).length, bilan.tables);
    });

    test('la Corbeille les retrouve toutes ; une fiche restaurée revient exactement où elle était', () {
      expect(cfbCorbeille(m).length, archiveesAvant + bilan.total);
      final p = m.collection('patients').toutes.first;
      final avant = p['statutAvantArchivage'];
      final ligne = cfbCorbeille(m).firstWhere((l) => l.collection == 'patients' && l.refId == p['id']);
      expect(ligne.motif, 'Jeu de démonstration, mise en production');
      expect(ligne.archivePar, m.utilisateur);
      m.collection('patients').restaurer(p['id']);
      final r = m.collection('patients').parId(p['id'])!;
      expect(r['statut'], avant);
      expect(m.collection('patients').actives.length, 1);
      expect([r['_archiveLe'], r['_archivePar'], r['_motifArchivage'], r['statutAvantArchivage']], [null, null, null, null], reason: 'plus « archivée le … »');
      expect(cfbCorbeille(m).length, archiveesAvant + bilan.total - 1);
      m.collection('patients').archiver(p['id']);
    });

    test('les compteurs de numérotation ne reculent pas : un code archivé n\'est jamais réattribué (RG-01)', () {
      expect(patProchainCode(m.collection('patients').toutes, auj), codePatient);
      expect(codePatient, isNot('CBG/1/26'));
      final codes = m.collection('patients').toutes.map((p) => p['code']).toSet();
      expect(codes, isNot(contains(codePatient)));
      expect('${rangSerieFactures('FN-2026-', m.collection('factures').toutes)}', rangFacture);
      expect(int.parse(rangFacture), greaterThan(100), reason: 'la série ne repart pas de 1');
      expect(cpaNumeroPiece('CAI', 2026, m.collection('ecritures').toutes), numeroEcriture);
      expect(numeroEcriture, isNot('CAI-2026-00001'));
    });

    test('rejouer l\'archivage n\'a plus rien à archiver et garde la date et le motif d\'origine', () {
      final marque = m.collection('patients').toutes.first['_archiveLe'];
      final b2 = cfbArchiverJeuDemo(m, motifDuGeste: 'Second passage');
      expect(b2.total, 0);
      expect(b2.tables, 0);
      expect(m.collection('patients').toutes.first['_archiveLe'], marque);
    });
  });
}
