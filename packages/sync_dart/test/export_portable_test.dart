// L'export complet portable (décision 12, 17/11/2026) : sceller, vérifier sans écrire, ouvrir ; les refus nommés ; l'import d'une MÈRE dans une base neuve, les fileuls qui se
// rattachent à la mère importée ; l'export d'un FILEUL (sa file) repris sur un poste neuf par un code de reprise ; le refus d'un schéma plus récent.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';
import 'package:sigh_sync/src/depot.dart';
import 'package:test/test.dart';

final cle = List<int>.generate(32, (i) => (i * 11 + 5) % 256);
final autreCle = List<int>.generate(32, (i) => (i * 13 + 1) % 256);
const clinique = IdentiteExport(sigle: 'CBG', nom: 'Clinique de test', ifu: '123456');

ContenuExport contenu() => ContenuExport(collections: {
      'patients': [for (var i = 0; i < 40; i++) {'id': 'P$i', 'nom': 'DUPONTEXPORT$i', 'code': 'CBG/$i/26'}],
      'factures': [{'id': 'F1', 'montant': 5000}],
      'identifiants': [{'id': 'U1', 'hache': 'SECRETHACHE'}],
      'jetonsEnquete': [{'id': 'J1', 'jeton': 'JETONPUBLIC'}],
    }, meta: {'schema': 1, 'jeu': 'abc', 'cle_clinique': 'NEDOITPASVOYAGER', 'migrations': []});

Future<Uint8List> fichier({int bloc = 2048}) => ExportPortable.sceller(
    cle: cle, contenu: contenu(), role: epRoleMere, clinique: clinique, logicielVersion: '0.1.0', etiquette: 'Poste 1', maintenant: DateTime.utc(2026, 11, 17, 8), tailleBloc: bloc);

Matcher refus(String code) => throwsA(isA<ErreurExport>().having((e) => e.code, 'code', code));

void main() {
  group('le fichier', () {
    test('aller-retour sur plusieurs blocs : le contenu relu égale le contenu scellé, sans les exclusions', () async {
      final o = await fichier(bloc: 1024);
      final r = await ExportPortable.ouvrir(o, cle);
      expect(r.contenu.collections['patients']!.length, 40);
      expect(r.contenu.collections['patients']!.last['nom'], 'DUPONTEXPORT39');
      expect(r.contenu.collections['factures']!.single['montant'], 5000);
      expect(r.manifeste.compteurs['patients'], 40);
      expect(r.manifeste.roleSource, epRoleMere);
      expect(r.manifeste.schema, schemaDonneesCourant);
      expect(r.manifeste.clinique.nom, 'Clinique de test');
      expect(r.manifeste.empreinte, hasLength(64));
    });

    test('AUCUN secret ni clé : comptes hachés, jetons publics et clés de méta ne voyagent pas ; le manifeste le dit', () async {
      final o = await fichier();
      final r = await ExportPortable.ouvrir(o, cle);
      expect(r.contenu.collections.containsKey('identifiants'), isFalse);
      expect(r.contenu.collections.containsKey('jetonsEnquete'), isFalse);
      expect(r.contenu.meta.containsKey('cle_clinique'), isFalse);
      expect(r.manifeste.exclusions, containsAll(['identifiants', 'jetonsEnquete']));
      final brut = latin1.decode(o);
      for (final interdit in ['SECRETHACHE', 'JETONPUBLIC', 'NEDOITPASVOYAGER', 'DUPONTEXPORT', base64.encode(cle)]) {
        expect(brut.contains(interdit), isFalse, reason: '« $interdit » ne doit pas figurer en clair dans le fichier');
      }
      final hexCle = cle.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(brut.contains(hexCle), isFalse);
      expect(String.fromCharCodes(o.sublist(0, 9 + (ByteData.sublistView(o).getUint32(5)))).contains(hexCle), isFalse, reason: 'le manifeste en clair ne porte pas la clé, seulement son empreinte courte');
    });

    test('le manifeste se lit SANS clé, et ne porte que des comptes', () async {
      final (m, _) = ExportPortable.lireManifeste(await fichier());
      expect(m.cleEmpreinte, cleEmpreinteManifeste(cle));
      expect(m.cree, '2026-11-17T08:00:00.000Z');
      expect(jsonEncode(m.toJson()).contains('DUPONT'), isFalse);
    });

    test('vérifier ne fait que lire : aucun fichier créé, le rapport redonne le manifeste', () async {
      final o = await fichier();
      final avant = Directory.systemTemp.listSync().length;
      final r = await ExportPortable.verifier(o, cle);
      expect(r.contenuOk, isTrue);
      expect(Directory.systemTemp.listSync().length, avant);
    });
  });

  group('refus nommés', () {
    test('clé absente, clé incorrecte', () async {
      final o = await fichier();
      await expectLater(ExportPortable.ouvrir(o, null), refus('CLE_ABSENTE'));
      await expectLater(ExportPortable.ouvrir(o, autreCle), refus('CLE_INCORRECTE'));
    });
    test('fichier altéré : un octet changé dans un bloc, ou tronqué', () async {
      final o = await fichier();
      final altere = Uint8List.fromList(o)..[o.length - 20] ^= 0x55;
      await expectLater(ExportPortable.ouvrir(altere, cle), refus('FICHIER_ALTERE'));
      await expectLater(ExportPortable.ouvrir(o.sublist(0, o.length - 40), cle), refus('FICHIER_ALTERE'));
    });
    test('manifeste modifié en clair : refusé, même si le contenu est intact', () async {
      final o = await fichier();
      final texte = latin1.decode(o);
      final i = texte.indexOf('Poste 1');
      final modifie = Uint8List.fromList(o)..[i + 6] = '2'.codeUnitAt(0);
      await expectLater(ExportPortable.ouvrir(modifie, cle), refus('MANIFESTE_ALTERE'));
    });
    test('pas un export, ou format plus récent', () async {
      expect(() => ExportPortable.lireManifeste(utf8.encode('bonjour, ceci n est pas un export')), refus('FICHIER_INCONNU'));
      final o = await fichier();
      final futur = Uint8List.fromList(o)..[4] = epFormat + 1;
      expect(() => ExportPortable.lireManifeste(futur), refus('FORMAT_PLUS_RECENT'));
    });
  });

  group('mère et fileuls', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sigh-export-'));
    tearDown(() => tmp.deleteSync(recursive: true));
    String chemin(String n) => '${tmp.path}/$n';
    ConfigMere cfgMere(String db) => ConfigMere(port: 0, dbChemin: chemin(db), admin: 'adm', cleBase64: base64.encode(cle), dossierSauvegardes: chemin('sauv-$db'));

    Future<Map<String, Object?>> http(String base, String m, String p, [Object? corps]) async {
      final c = HttpClient();
      final r = await c.openUrl(m, Uri.parse('$base$p'));
      r.headers.contentType = ContentType.json;
      r.headers.set('x-admin', 'adm');
      if (corps != null) r.add(utf8.encode(jsonEncode(corps)));
      final rep = await r.close();
      final txt = await utf8.decoder.bind(rep).join();
      c.close();
      final j = txt.isEmpty ? <String, Object?>{} : jsonDecode(txt);
      return {'statut': rep.statusCode, if (j is Map) ...j.cast<String, Object?>() else 'liste': j};
    }

    Future<Fileul> poste(String base, {Map<String, Object?> code = const {}}) async {
      final c = (await http(base, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'P', ...code}))['code'];
      final f = Fileul(ConfigFileul(port: 0, mere: base, dbChemin: ':memory:'));
      expect((await f.commande('POST /appairer', {'code': c}, const {})).$1, 200);
      return f;
    }

    Map<String, Object?> patient(String nom, String n) => {'type': 'creer', 'collection': 'patients', 'fiche': 'fiche-$n', 'champs': {'nom': nom, 'prenom': 'P', 'naissance': '1980-01-0$n', 'dateCreation': '2026-11-17'}};

    test('MÈRE : exportée, importée dans une base NEUVE ; la mère importée garde la clé, le journal et le schéma ; les fileuls se rattachent sans se réappairer', () async {
      final a = await Mere.creer(cfgMere('a.db'));
      await a.demarrer();
      final baseA = 'http://127.0.0.1:${a.portEcoute}';
      final f = await poste(baseA);
      await f.commande('POST /plage', {'taille': 20}, const {});
      f.ecrire(patient('ALPHA', '1'));
      f.ecrire(patient('BETA', '2'));
      await f.cycle();
      expect((await a.base.select('SELECT COUNT(*) AS n FROM fiches WHERE collection=?', ['patients'])).first['n'], 2);

      // L'export de la mère : ses lignes, scellées par la clé de la clinique.
      final sync = await extraireMere(a.base);
      final octets = await ExportPortable.sceller(
          cle: cle, contenu: ContenuExport(collections: {'patients': []}, sync: sync), role: epRoleMere, clinique: clinique, logicielVersion: '0.1.0', etiquette: 'Mère');
      final ouvert = await ExportPortable.ouvrir(octets, cle);
      final tables = (ouvert.contenu.sync!['tables'] as Map).cast<String, Object?>();
      expect(tables.containsKey('codes'), isFalse, reason: 'les codes d’appairage ne voyagent pas');
      expect([for (final r in (tables['meta'] as List)) (r as Map)['k']], isNot(contains('cle')), reason: 'la clé de la clinique ne voyage pas');
      expect(ouvert.manifeste.compteurs['sync.operations'], 2);
      expect(latin1.decode(octets).contains('ALPHA'), isFalse);
      await a.arreter();

      // IMPORT dans une base neuve ; refus si elle existe.
      final cfgB = cfgMere('b.db');
      final rapport = await importerMereDansCibleNeuve(cfg: cfgB, sync: ouvert.contenu.sync!, cle: cle, schemaFichier: ouvert.manifeste.schema);
      expect(rapport.lignes, greaterThan(5));
      await expectLater(importerMereDansCibleNeuve(cfg: cfgB, sync: ouvert.contenu.sync!, cle: cle), refus('CIBLE_EXISTE'));
      expect(File(chemin('a.db')).existsSync(), isTrue, reason: 'la base en service n’est jamais touchée');

      final b = await Mere.creer(cfgB);
      expect((await b.base.select('SELECT COUNT(*) AS n FROM operations')).first['n'], 2);
      expect(await b.base.meta('cle'), base64.encode(cle), reason: 'la mère importée garde la clé de la clinique : fileuls et relais continuent de lui parler');
      expect(await b.base.metaInt(schemaCleMeta), schemaDonneesCourant);
      expect(await b.base.meta('importee_le'), isNotNull);
      await b.demarrer();
      final baseB = 'http://127.0.0.1:${b.portEcoute}';
      // Le fileul se REDIRIGE vers la mère importée et continue : même jeton, même plage, rien à réappairer.
      f.rediriger(baseB);
      f.ecrire(patient('GAMMA', '3'));
      await f.cycle();
      expect(f.etat.derniereErreur, isNull);
      expect((await b.base.select('SELECT COUNT(*) AS n FROM fiches WHERE collection=?', ['patients'])).first['n'], 3);
      expect((await b.base.select("SELECT COUNT(DISTINCT ${b.base.champJson('data', 'code')}) AS n FROM fiches WHERE collection='patients'")).first['n'], 3, reason: 'aucun doublon de code');
      expect((await f.commande('GET /etat', const {}, const {})).$2, isA<Map>());
      await b.arreter();
    });

    test('FILEUL : exporté (sa file), repris sur un poste neuf par un code de reprise : une seule fois chez la mère', () async {
      final a = await Mere.creer(cfgMere('a.db'));
      await a.demarrer();
      final baseA = 'http://127.0.0.1:${a.portEcoute}';
      final f1 = await poste(baseA);
      await f1.commande('POST /plage', {'taille': 20}, const {});
      f1.ecrire(patient('ECHO', '4'));
      f1.ecrire(patient('FOXTROT', '5'));
      final octets = await ExportPortable.sceller(
          cle: cle,
          contenu: ContenuExport(collections: {'patients': []}, sync: f1.etatPortable()),
          role: epRoleFileul,
          clinique: clinique,
          logicielVersion: '0.1.0',
          etiquette: 'Poste caisse',
          uuidSource: f1.uuid);
      final ouvert = await ExportPortable.ouvrir(octets, cle);
      expect(ouvert.manifeste.fileEnAttente, 2);
      expect(ouvert.manifeste.compteurs['sync.file'], 2);
      expect(jsonEncode(ouvert.contenu.sync).contains('jeton'), isFalse);

      final f2 = Fileul(ConfigFileul(port: 0, mere: baseA, dbChemin: ':memory:'));
      expect(f2.reprendreEtat(ouvert.contenu.sync!)['repris'], 2);
      expect(f2.reprendreEtat(ouvert.contenu.sync!)['refus'], 'POSTE_NON_NEUF');
      final emis = await http(baseA, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'Poste caisse', 'reprise': f1.uuid});
      final code = emis['code'];
      expect(emis['validite_s'], cfgMere('a.db').codeTtl ~/ 1000, reason: 'la durée de validité est celle de la mère, rendue avec le code (la console ne l\'écrit jamais)');
      expect(emis['expire'], isA<int>());
      final secondCode = (await http(baseA, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'Second poste', 'reprise': f1.uuid}))['code'];
      final (statutAp, repAp) = await f2.commande('POST /appairer', {'code': code}, const {});
      expect(statutAp, 200);
      final faite = (repAp as Map)['reprise'] as Map;
      expect(faite['de'], f1.uuid, reason: 'le poste neuf apprend QUEL poste il remplace, par la mère');
      expect(faite['plages'], greaterThanOrEqualTo(1));
      await f2.cycle();
      expect(f2.etat.derniereErreur, isNull);
      expect((await a.base.select("SELECT COUNT(*) AS n FROM fiches WHERE collection='patients'")).first['n'], 2);
      expect((await a.base.select("SELECT etat FROM appareils WHERE uuid=?", [f1.uuid])).first['etat'], 'revoque');
      final inconnu = await http(baseA, 'POST', '/admin/code', {'role': 'fileul', 'reprise': 'inconnu'});
      expect(inconnu['statut'], 404);
      expect(inconnu['code'], 'appareil_inconnu');
      // Un poste ne se reprend qu'UNE fois : ni un nouveau code, ni le second code déjà émis, ne passent (refus nommé avant tout effet).
      final redemande = await http(baseA, 'POST', '/admin/code', {'role': 'fileul', 'reprise': f1.uuid});
      expect(redemande['statut'], 409);
      expect(redemande['code'], 'deja_repris');
      final f3 = Fileul(ConfigFileul(port: 0, mere: baseA, dbChemin: ':memory:'));
      final (statutDouble, repDouble) = await f3.commande('POST /appairer', {'code': secondCode}, const {});
      expect(statutDouble, 409);
      expect((repDouble as Map)['code'], 'deja_repris');
      expect((await a.base.select("SELECT utilise FROM codes WHERE code=?", [secondCode])).first['utilise'], 0, reason: 'le code refusé ne se consume pas');
      // Un appairage ordinaire ne rapporte aucune reprise.
      final ordinaire = (await http(baseA, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'Ordinaire'}))['code'];
      final f4 = Fileul(ConfigFileul(port: 0, mere: baseA, dbChemin: ':memory:'));
      final (_, repOrdinaire) = await f4.commande('POST /appairer', {'code': ordinaire}, const {});
      expect((repOrdinaire as Map).containsKey('reprise'), isFalse);
      await a.arreter();
    });

    test('SCHÉMA : une base de mère écrite par une version PLUS RÉCENTE est refusée en le nommant, et rien n’est modifié', () async {
      final m = await Mere.creer(cfgMere('a.db'));
      expect(await m.base.metaInt(schemaCleMeta), schemaDonneesCourant, reason: 'une base neuve reçoit son numéro');
      await m.base.poserMeta(schemaCleMeta, schemaDonneesCourant + 5);
      await m.arreter();
      final taille = File(chemin('a.db')).lengthSync();
      await expectLater(Mere.creer(cfgMere('a.db')), throwsA(isA<ErreurSchemaDonnees>().having((e) => e.code, 'code', 'SCHEMA_PLUS_RECENT')));
      final d = DepotSqlite(chemin('a.db'));
      expect(await d.metaInt(schemaCleMeta), schemaDonneesCourant + 5, reason: 'le numéro n’a pas été écrasé');
      await d.fermer();
      expect(File(chemin('a.db')).lengthSync(), taille);
    });

    test('SCHÉMA : une base d’avant la chaîne (sans numéro) reçoit le schéma 1', () async {
      final m = await Mere.creer(cfgMere('a.db'));
      await m.base.exec('DELETE FROM meta WHERE k=?', [schemaCleMeta]);
      await m.arreter();
      final m2 = await Mere.creer(cfgMere('a.db'));
      expect(await m2.base.metaInt(schemaCleMeta), schemaDonneesCourant);
      await m2.arreter();
    });

    test('SAUVEGARDE : la dernière sauvegarde chiffrée est relue (déchiffrée, intégrité contrôlée) ; absente ou altérée, elle est refusée en nommant', () async {
      final m = await Mere.creer(cfgMere('a.db'));
      expect((await m.verifierDerniereSauvegarde())['code'], 'SAUVEGARDE_ABSENTE');
      final fichierEnc = await m.sauvegarderChiffre(prefixe: 'manuelle');
      final r = await m.verifierDerniereSauvegarde();
      expect(r['ok'], isTrue);
      expect(r['date'], isNotNull);
      final f = File(fichierEnc);
      final b = f.readAsBytesSync();
      b[b.length ~/ 2] ^= 0xff;
      f.writeAsBytesSync(b);
      final r2 = await m.verifierDerniereSauvegarde();
      expect(r2['ok'], isFalse);
      expect(r2['code'], 'SAUVEGARDE_ILLISIBLE');
      await m.arreter();
    });
  });

  test('un export d’une AUTRE clinique est refusé par les règles, même avec la bonne clé', () async {
    final o = await ExportPortable.sceller(
        cle: cle, contenu: contenu(), role: epRoleMere, clinique: const IdentiteExport(sigle: 'ZZ', nom: 'Autre clinique', ifu: '999'), logicielVersion: '0.1.0');
    final r = await ExportPortable.ouvrir(o, cle);
    expect(epControlerImport(manifeste: r.manifeste, roleCible: epRoleMere, identiteLocale: clinique)?.code, 'AUTRE_CLINIQUE');
  });
}
