// La version du format des données du magasin du poste (décision 12, 17/11/2026) : écrite en méta, lue à l'ouverture ; la chaîne de migrations amène un magasin d'ancienne forme
// à la forme courante SANS rien détruire ; un magasin plus récent que le logiciel est refusé en le nommant, sans qu'un octet soit modifié.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/persistance.dart';

typedef F = Map<String, Object?>;

Map<String, List<F>> ancien() => {
      'releves': [
        {'id': 'REL1', 'statut': 'actif', 'tension': '12/8', 'diurese': 1200},
        {'id': 'REL2', 'statut': 'archive', 'tension': '11/7', 'diurese': 800},
      ],
      'constantes': [
        {'id': 'C1', 'statut': 'actif', 'patientId': 'P1', 'diurese': 1.5, 'tensionSys': 13, 'tensionDia': 9, 'tension': '13/9'},
      ],
      'patients': [
        {'id': 'P1', 'statut': 'actif', 'nom': 'ALPHA'},
      ],
    };

Magasin poste() => Magasin({'releves': const <F>[], 'constantes': const <F>[], 'observations': const <F>[], 'patients': const <F>[]}, 'POSTE');

void main() {
  group('magasin d’ancienne forme (schéma 0, sans numéro)', () {
    test('relu après migration : forme courante, numéro et journal écrits, forme d’origine rangée à part', () async {
      final p = PersistanceMemoire(ancien());
      final m = poste();
      await m.brancherPersistance(p, delai: Duration.zero);
      expect(m.schemaDesDonnees, schemaDonneesCourant);
      expect(p.meta[schemaCleMeta], schemaDonneesCourant);
      final rel = m.collection('releves').toutes;
      expect(rel[0]['tensionSys'], 12);
      expect(rel[1]['statut'], 'archive', reason: 'RG-14 : l’archivée reste archivée');
      expect(m.collection('constantes').toutes.single['diurese'], 1500);
      final journal = (p.meta[schemaCleJournal] as List).cast<Map>();
      expect(journal.single['numero'], 1);
      expect(journal.single['nom'], 'constantes-lot-b');
      expect(journal.single.toString().contains('ALPHA'), isFalse, reason: 'le journal ne porte que des comptes');
      // NON DESTRUCTIVE : l'ancienne forme est conservée, intacte.
      final avant = p.avantMigration[1]!;
      expect(avant['releves']![0]['tension'], '12/8');
      expect(avant['constantes']![0]['diurese'], 1.5);
      expect(avant.containsKey('patients'), isFalse, reason: 'seules les collections converties sont copiées');
      // La relecture après migration : un second poste lit la forme migrée telle quelle.
      final m2 = poste();
      await m2.brancherPersistance(p, delai: Duration.zero);
      expect(m2.collection('releves').toutes[0]['tensionSys'], 12);
      expect(m2.collection('constantes').toutes.single['diurese'], 1500, reason: 'IDEMPOTENTE : jamais reconvertie');
      expect(m2.migrationsJouees, isEmpty);
      expect((p.meta[schemaCleJournal] as List).length, 1);
    });

    test('sur disque : la forme d’origine est rangée sous migrations/avant-1/ (relisible), la forme migrée remplace dans le magasin', () async {
      final tmp = Directory.systemTemp.createTempSync('sigh-schema-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final seed = PersistanceFichiers('${tmp.path}/magasin');
      for (final e in ancien().entries) {
        await seed.ecrire(e.key, e.value);
      }
      await seed.ecrireMeta({'jeu': 'x'});
      final m = poste();
      await m.brancherPersistance(PersistanceFichiers('${tmp.path}/magasin'), delai: Duration.zero);
      expect(File('${tmp.path}/magasin/migrations/avant-1/releves.json').existsSync(), isTrue);
      final sauvegarde = PersistanceFichiers('${tmp.path}/magasin/migrations/avant-1');
      final forme = (await sauvegarde.lireTout())['releves']!;
      expect(forme[0]['tension'], '12/8', reason: 'l’ancienne forme se relit telle qu’elle était');
      final relu = (await PersistanceFichiers('${tmp.path}/magasin').lireTout())['releves']!;
      expect(relu[0]['tensionSys'], 12);
      expect(Directory('${tmp.path}/magasin/migrations').existsSync(), isTrue);
    });

    test('chiffré : la forme d’origine conservée est chiffrée comme le reste', () async {
      final tmp = Directory.systemTemp.createTempSync('sigh-schema-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final cle = List<int>.generate(32, (i) => i + 1);
      final seed = PersistanceFichiers('${tmp.path}/magasin', cle: cle);
      for (final e in ancien().entries) {
        await seed.ecrire(e.key, e.value);
      }
      await poste().brancherPersistance(PersistanceFichiers('${tmp.path}/magasin', cle: cle), delai: Duration.zero);
      final f = File('${tmp.path}/magasin/migrations/avant-1/releves.sigh');
      expect(f.existsSync(), isTrue);
      expect(String.fromCharCodes(f.readAsBytesSync()).contains('12/8'), isFalse);
    });
  });

  group('magasin PLUS RÉCENT que le logiciel : refusé en le nommant, rien n’est modifié', () {
    test('en mémoire : aucune écriture, méta et collections intactes', () async {
      final p = PersistanceMemoire(ancien())..meta = {'schema': schemaDonneesCourant + 4, 'jeu': 'abc'};
      final avant = {for (final e in p.contenu.entries) e.key: e.value.toString()};
      await expectLater(poste().brancherPersistance(p, delai: Duration.zero), throwsA(isA<ErreurSchemaDonnees>().having((e) => e.code, 'code', 'SCHEMA_PLUS_RECENT')));
      expect(p.ecritures, isEmpty);
      expect(p.meta, {'schema': schemaDonneesCourant + 4, 'jeu': 'abc'});
      expect({for (final e in p.contenu.entries) e.key: e.value.toString()}, avant);
    });

    test('sur disque : les octets du dossier sont identiques avant et après le refus', () async {
      final tmp = Directory.systemTemp.createTempSync('sigh-schema-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final seed = PersistanceFichiers('${tmp.path}/magasin');
      for (final e in ancien().entries) {
        await seed.ecrire(e.key, e.value);
      }
      await seed.ecrireMeta({'schema': schemaDonneesCourant + 1});
      String empreinte() => [for (final f in Directory('${tmp.path}/magasin').listSync(recursive: true).whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path))) '${f.path}:${f.readAsStringSync()}'].join('|');
      final avant = empreinte();
      try {
        await poste().brancherPersistance(PersistanceFichiers('${tmp.path}/magasin'), delai: Duration.zero);
        fail('doit refuser');
      } on ErreurSchemaDonnees catch (e) {
        expect(e.refus.motif, contains('schéma ${schemaDonneesCourant + 1}'));
        expect(e.refus.plus['schemaLu'], schemaDonneesCourant + 1);
      }
      expect(empreinte(), avant);
    });

    test('un numéro de schéma illisible est refusé de même', () async {
      final p = PersistanceMemoire(ancien())..meta = {'schema': 'v2'};
      await expectLater(poste().brancherPersistance(p, delai: Duration.zero), throwsA(isA<ErreurSchemaDonnees>().having((e) => e.code, 'code', 'SCHEMA_ILLISIBLE')));
      expect(p.ecritures, isEmpty);
    });
  });

  test('un poste NEUF naît au schéma courant sans rien migrer ni journaliser', () async {
    final p = PersistanceMemoire();
    final m = Magasin({'constantes': [{'id': 'C1', 'statut': 'actif', 'diurese': 2}]}, 'POSTE');
    await m.brancherPersistance(p, delai: Duration.zero);
    expect(p.meta[schemaCleMeta], schemaDonneesCourant);
    expect(p.meta[schemaCleJournal], isNull);
    expect(m.collection('constantes').toutes.single['diurese'], 2);
  });

  test('l’ancienne marque formeConstantes=2 (poste d’avant la chaîne, déjà converti) vaut le schéma 1 : rien n’est reconverti', () async {
    final p = PersistanceMemoire({'constantes': [{'id': 'C1', 'statut': 'actif', 'diurese': 1500}]})..meta = {'formeConstantes': 2};
    final m = poste();
    await m.brancherPersistance(p, delai: Duration.zero);
    expect(m.collection('constantes').toutes.single['diurese'], 1500);
    expect(p.meta[schemaCleMeta], schemaDonneesCourant);
  });
}
