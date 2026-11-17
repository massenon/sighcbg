import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> rel(String id, Object? tension) => {'id': id, 'tension': tension};
final t0 = DateTime.utc(2026, 11, 17, 8);

ContenuDonnees ancien({Map<String, Object?> meta = const {}}) => ContenuDonnees({
      'releves': [rel('R1', '12/8'), rel('R2', '14/9')],
      'constantes': [{'id': 'C1', 'diurese': 2}],
      'patients': [{'id': 'P1', 'nom': 'X'}],
    }, {...meta});

void main() {
  group('lecture du schéma', () {
    test('absent : neuf = courant, peuplé sans marque = 0, ancienne marque du lot B = 1', () {
      expect(schemaDeLaMeta({}, peuple: false), schemaDonneesCourant);
      expect(schemaDeLaMeta({}, peuple: true), 0);
      expect(schemaDeLaMeta({'formeConstantes': 2}, peuple: true), 1);
      expect(schemaDeLaMeta({'schema': 7}, peuple: true), 7);
      expect(schemaDeLaMeta({'schema': 'abc'}, peuple: true), isNull);
    });
  });

  group('méta illisible (E4603)', () {
    test('un magasin PEUPLÉ dont la méta est illisible est refusé, nommé, sans rien convertir', () {
      final c = ancien(meta: {schemaCleMetaIllisible: true});
      expect(() => migrerDonnees(c, horloge: () => t0), throwsA(isA<ErreurSchemaDonnees>().having((e) => e.code, 'code', 'META_ILLISIBLE')));
      expect(c.collections['constantes']!.single['diurese'], 2, reason: 'la diurèse n’est pas convertie (×1000)');
      expect(() => garderSchema(c), throwsA(isA<ErreurSchemaDonnees>()));
    });

    test('un magasin VIDE à la méta illisible n’a rien à perdre : il naît au schéma courant, le témoin n’est jamais écrit', () {
      final c = ContenuDonnees({'releves': []}, {schemaCleMetaIllisible: true});
      final r = migrerDonnees(c, horloge: () => t0);
      expect(r.schemaApres, schemaDonneesCourant);
      expect(metaMigree(c.meta, r).containsKey(schemaCleMetaIllisible), isFalse);
      expect(c.meta.containsKey(schemaCleMetaIllisible), isTrue, reason: 'l’entrée n’est pas mutée');
    });

    test('une méta ABSENTE (magasin d’avant la chaîne) et une méta saine ne sont pas touchées : schéma 0 migré, schéma courant inchangé', () {
      expect(migrerDonnees(ancien(), horloge: () => t0).schemaAvant, 0);
      expect(migrerDonnees(ancien(meta: {'schema': schemaDonneesCourant}), horloge: () => t0).aFait, isFalse);
    });
  });

  test('la chaîne livrée est ordonnée et contiguë, et son dernier numéro est le schéma courant', () {
    verifierChaine(migrationsDonnees);
    expect(migrationsDonnees.first.numero, 1);
    expect(migrationsDonnees.length, schemaDonneesCourant);
    expect(() => verifierChaine([MigrationDonnees(numero: 2, nom: 'x', libelle: '', appliquer: (c, x) => const SortieMigration({}))]), throwsStateError);
  });

  group('migration n°1 (constantes) : un magasin d’ancienne forme se relit après migration', () {
    test('tension scindée, diurèse d’accueil convertie UNE fois, journal et schéma posés', () {
      final c = ancien();
      final r = migrerDonnees(c, horloge: () => t0);
      expect(r.schemaAvant, 0);
      expect(r.schemaApres, 1);
      final rel1 = r.modifiees['releves']!.firstWhere((f) => f['id'] == 'R1');
      expect(rel1['tensionSys'], 12);
      expect(rel1['tensionDia'], 8);
      expect(rel1.containsKey('tension'), isFalse);
      expect(r.modifiees['constantes']!.single['diurese'], 2000);
      expect(r.journal.single['nom'], 'constantes-lot-b');
      expect(r.journal.single['tensionsScindees'], 2);
      final m = metaMigree(c.meta, r);
      expect(m[schemaCleMeta], 1);
      expect((m[schemaCleJournal] as List).length, 1);
      // Le journal ne porte que des comptes : aucune fiche.
      expect(m.toString().contains('X'), isFalse);
    });

    test('NON DESTRUCTIVE : la forme d’origine est rendue avant conversion et l’original n’est jamais modifié', () {
      final c = ancien();
      final r = migrerDonnees(c, horloge: () => t0);
      final avant = r.formesAvant[1]!;
      expect(avant['releves']!.first['tension'], '12/8');
      expect(avant['constantes']!.single['diurese'], 2);
      expect(c.collections['releves']!.first['tension'], '12/8', reason: 'l’original reste intact : l’appelant écrit, pas la chaîne');
      expect(c.collections['constantes']!.single['diurese'], 2);
    });

    test('IDEMPOTENTE : rejouée sur le magasin déjà migré, elle ne change plus rien (la diurèse n’est pas reconvertie)', () {
      final c = ancien();
      final r1 = migrerDonnees(c, horloge: () => t0);
      final c2 = ContenuDonnees({...c.collections, ...r1.modifiees}, metaMigree(c.meta, r1));
      final r2 = migrerDonnees(c2, horloge: () => t0);
      expect(r2.aFait, isFalse);
      expect(r2.modifiees, isEmpty);
      expect(r2.journal, isEmpty);
      expect(metaMigree(c2.meta, r2), c2.meta);
      expect(c2.collections['constantes']!.single['diurese'], 2000);
    });

    test('l’ancienne marque formeConstantes=2 équivaut au schéma 1 : la diurèse n’est pas reconvertie', () {
      final c = ancien(meta: {'formeConstantes': 2});
      final r = migrerDonnees(c, horloge: () => t0);
      expect(r.schemaAvant, 1);
      expect(r.aFait, isFalse);
      expect(r.modifiees, isEmpty);
    });

    test('un magasin NEUF (vide) naît au schéma courant, sans rien convertir', () {
      final r = migrerDonnees(ContenuDonnees({}, {}), horloge: () => t0);
      expect(r.aFait, isFalse);
      expect(metaMigree({}, r)[schemaCleMeta], schemaDonneesCourant);
    });
  });

  group('refus nommés', () {
    test('un schéma PLUS RÉCENT que le logiciel est refusé, rien n’est lu ni modifié', () {
      final c = ancien(meta: {'schema': schemaDonneesCourant + 3});
      try {
        migrerDonnees(c, horloge: () => t0);
        fail('doit refuser');
      } on ErreurSchemaDonnees catch (e) {
        expect(e.code, 'SCHEMA_PLUS_RECENT');
        expect(e.refus.plus['schemaLu'], schemaDonneesCourant + 3);
        expect(e.refus.motif, contains('schéma ${schemaDonneesCourant + 3}'));
      }
      expect(c.collections['releves']!.first['tension'], '12/8');
    });

    test('un schéma illisible est refusé en le nommant', () {
      expect(() => garderSchema(ancien(meta: {'schema': 'x'})), throwsA(isA<ErreurSchemaDonnees>().having((e) => e.code, 'code', 'SCHEMA_ILLISIBLE')));
    });
  });

  group('une chaîne de plusieurs migrations (chaîne de test injectée)', () {
    SortieMigration ajouter(ContenuDonnees c, String champ) => SortieMigration({
          'patients': [for (final f in c.collections['patients']!) {...f, champ: true}]
        }, {'ajoutes': c.collections['patients']!.length});
    final chaine = [
      migrationsDonnees.first,
      MigrationDonnees(numero: 2, nom: 'deux', libelle: 'a', appliquer: (c, x) => ajouter(c, 'm2')),
      MigrationDonnees(numero: 3, nom: 'trois', libelle: 'b', appliquer: (c, x) => ajouter(c, 'm3')),
    ];

    test('de 0 à 3 : dans l’ordre, chacune journalisée, formes d’origine rendues par migration', () {
      final r = migrerDonnees(ancien(), chaine: chaine, horloge: () => t0);
      expect([for (final j in r.journal) j['numero']], [1, 2, 3]);
      expect(r.schemaApres, 3);
      expect(r.modifiees['patients']!.single, containsPair('m3', true));
      expect(r.formesAvant[2]!['patients']!.single.containsKey('m2'), isFalse);
      expect(r.formesAvant[3]!['patients']!.single.containsKey('m3'), isFalse);
      expect(r.formesAvant[3]!['patients']!.single, containsPair('m2', true), reason: 'la forme avant la 3 est la sortie de la 2');
    });

    test('de 1 à 3 : seules 2 et 3 jouent', () {
      final r = migrerDonnees(ancien(meta: {'schema': 1}), chaine: chaine, horloge: () => t0);
      expect([for (final j in r.journal) j['numero']], [2, 3]);
    });

    test('un magasin au schéma 4 est refusé par une chaîne qui s’arrête à 3', () {
      expect(() => migrerDonnees(ancien(meta: {'schema': 4}), chaine: chaine, horloge: () => t0), throwsA(isA<ErreurSchemaDonnees>()));
    });

    test('une migration qui échoue ne laisse rien : l’original est intact', () {
      final mauvaise = [
        migrationsDonnees.first,
        MigrationDonnees(numero: 2, nom: 'casse', libelle: '', appliquer: (c, x) => throw StateError('boum')),
      ];
      final c = ancien();
      expect(() => migrerDonnees(c, chaine: mauvaise, horloge: () => t0), throwsStateError);
      expect(c.collections['releves']!.first['tension'], '12/8');
      expect(c.meta.containsKey(schemaCleMeta), isFalse);
    });
  });
}
