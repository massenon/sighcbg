import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

const id = IdentiteExport(sigle: 'CBG', nom: 'Clinique X', ifu: '123');
ManifesteExport man({String role = epRoleMere, int schema = schemaDonneesCourant, int format = epFormat, IdentiteExport? clinique, String cree = '2026-11-17T08:00:00.000Z'}) => ManifesteExport(
    format: format, logicielVersion: '0.1.0', schema: schema, cree: cree, clinique: clinique ?? id, roleSource: role, etiquette: 'Poste 1',
    compteurs: {'patients': 3, 'factures': 2}, empreinte: 'ab' * 32, tailleClair: 2048, cleEmpreinte: '0123456789abcdef');

void main() {
  test('le manifeste fait l’aller-retour et ne porte que des comptes', () {
    final m = man();
    final j = m.toJson();
    expect(j['total'], 5);
    final relu = ManifesteExport.depuisJson(j);
    expect(relu.toCanonique(), m.toCanonique());
    expect(j.toString(), isNot(contains('mot')));
  });

  test('un manifeste mal formé est refusé en le nommant', () {
    expect(() => ManifesteExport.depuisJson('x'), throwsA(isA<ErreurExport>().having((e) => e.code, 'code', 'MANIFESTE_ILLISIBLE')));
    final j = man().toJson()..['genre'] = 'autre';
    expect(() => ManifesteExport.depuisJson(j), throwsA(isA<ErreurExport>().having((e) => e.code, 'code', 'FICHIER_INCONNU')));
    final k = man().toJson()..remove('schema');
    expect(() => ManifesteExport.depuisJson(k), throwsA(isA<ErreurExport>()));
  });

  group('contrôles d’import', () {
    test('cas nominal : mère vers mère', () => expect(epControlerImport(manifeste: man(), roleCible: epRoleMere, identiteLocale: id), isNull));
    test('schéma plus récent', () => expect(epControlerImport(manifeste: man(schema: schemaDonneesCourant + 1), roleCible: epRoleMere)?.code, 'SCHEMA_PLUS_RECENT'));
    test('format plus récent', () => expect(epControlerImport(manifeste: man(format: epFormat + 1), roleCible: epRoleMere)?.code, 'FORMAT_PLUS_RECENT'));
    test('autre clinique, sur la mère comme sur le fileul', () {
      const autre = IdentiteExport(sigle: 'ZZ', nom: 'Autre', ifu: '999');
      expect(epControlerImport(manifeste: man(clinique: autre), roleCible: epRoleMere, identiteLocale: id)?.code, 'AUTRE_CLINIQUE');
      expect(epControlerImport(manifeste: man(clinique: autre, role: epRoleFileul), roleCible: epRoleFileul, identiteLocale: id)?.code, 'AUTRE_CLINIQUE');
    });
    test('un export de fileul ne devient pas une mère', () {
      expect(epControlerImport(manifeste: man(role: epRoleFileul), roleCible: epRoleMere)?.code, 'FILEUL_VERS_MERE');
    });
    test('un fileul NON rattaché importe comme une mère de lui-même : le fileul y est refusé comme sur une mère', () {
      expect(epControlerImport(manifeste: man(role: epRoleFileul), roleCible: epRoleFileul, rattache: false)?.code, 'FILEUL_VERS_MERE');
      expect(epControlerImport(manifeste: man(role: epRoleMere), roleCible: epRoleFileul, rattache: false), isNull);
      expect(epModeImport(manifeste: man(role: epRoleMere), roleCible: epRoleFileul, rattache: false), ModeImport.complet);
    });
    test('un fileul rattaché accepte l’export d’un fileul (sa file) et celui d’une mère (resynchronisation)', () {
      expect(epControlerImport(manifeste: man(role: epRoleFileul), roleCible: epRoleFileul), isNull);
      expect(epModeImport(manifeste: man(role: epRoleFileul), roleCible: epRoleFileul), ModeImport.complet);
      expect(epControlerImport(manifeste: man(role: epRoleMere), roleCible: epRoleFileul), isNull);
      expect(epModeImport(manifeste: man(role: epRoleMere), roleCible: epRoleFileul), ModeImport.resynchronisation);
    });
    test('cible existante : jamais d’écrasement', () => expect(epControlerImport(manifeste: man(), roleCible: epRoleMere, cibleExiste: true)?.code, 'CIBLE_EXISTE'));
  });

  group('avertissement d’ancienneté (non bloquant)', () {
    final exporte = DateTime.utc(2026, 11, 10, 8);
    test('import plus ancien que la dernière synchro : avertit et liste les saisies locales postérieures', () {
      final saisies = [
        SaisieLocale(collection: 'patients', fiche: 'P9', type: 'creer', quand: DateTime.utc(2026, 11, 12)),
        SaisieLocale(collection: 'patients', fiche: 'P1', type: 'modifier', quand: DateTime.utc(2026, 11, 9)),
      ];
      final a = epAvertirAnciennete(exportCree: exporte, derniereSynchro: DateTime.utc(2026, 11, 16, 8), fileEnAttente: saisies)!;
      expect(a.ecartHeures, 6 * 24);
      expect([for (final s in a.saisies) s.fiche], ['P9']);
      expect(a.message, contains('non bloquant'));
      expect(a.message, contains('autorité'));
    });
    test('import récent et rien en file : pas d’avertissement', () {
      expect(epAvertirAnciennete(exportCree: exporte, derniereSynchro: DateTime.utc(2026, 11, 9)), isNull);
    });
  });

  group('rien de secret ne voyage', () {
    test('exclusions : comptes hachés et jetons publics', () {
      expect(epCollectionsExclues.keys, containsAll(['identifiants', 'jetonsEnquete']));
      expect(epTablesMereExclues, contains('codes'));
      expect(epMetaMereExclues, contains('cle'));
    });
    test('les clés de méta qui nomment un secret sont écartées', () {
      final m = epMetaExportable({'schema': 1, 'cle': 'X', 'cle_clinique': 'X', 'jeton:abc': 'x', 'secretRelais': 'x', 'epoch': 3, 'motdepasse': 'x', 'jeu': 'h'});
      expect(m.keys.toSet(), {'schema', 'epoch', 'jeu'});
      expect(epMetaExportable({'cle': 'x', 'a': 1}, exclues: ['a']), isEmpty);
    });
  });

  test('les gestes d’export et d’import existent, sans nom de rôle écrit dans les règles', () {
    expect(gesteReserve(gesteBaseExporter), isNotNull);
    expect(gesteReserve(gesteBaseImporter), isNotNull);
    expect(epRolesExport, epRolesImport);
    expect(epRolesExport, isNotEmpty);
    expect(gestesOrigine().peut(epRolesExport.first, gesteBaseExporter), isTrue);
    expect(gestesOrigine().peut('inconnu', gesteBaseExporter), isFalse);
  });
}
