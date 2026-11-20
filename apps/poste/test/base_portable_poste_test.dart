// L'export complet portable, son réimport et la mise en service, AU POSTE (décision 12, 17/11/2026) : droits par geste réservé, refus nommés, magasin NEUF jamais la base en service,
// fileul (file reprise, copie préalable vérifiée, avertissement d'ancienneté) et mère (journal rejoué dans une base neuve), échange de dossiers au démarrage sans rien supprimer.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/base_portable_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_sync/sigh_sync.dart';

typedef F = Map<String, Object?>;

final cle = List<int>.generate(32, (i) => (i * 5 + 9) % 256);
final autreCle = List<int>.generate(32, (i) => (i * 3 + 2) % 256);

Matcher refus(String code) => throwsA(isA<ErreurExport>().having((e) => e.code, 'code', code));

Future<Magasin> magasinPeuple() async {
  final m = Magasin({
    'patients': [for (var i = 0; i < 5; i++) {'id': 'P$i', 'statut': 'actif', 'nom': 'NOMSECRET$i'}],
    'factures': [{'id': 'F1', 'statut': 'actif', 'montant': 1000}],
    'identifiants': [{'id': 'U1', 'statut': 'actif', 'hache': 'HACHESECRET'}],
    'jetonsEnquete': [{'id': 'J1', 'statut': 'actif', 'jeton': 'JETONSECRET'}],
    'releves': const <F>[],
    'constantes': const <F>[],
    'observations': const <F>[],
  }, 'POSTE');
  await m.brancherPersistance(PersistanceMemoire(), delai: Duration.zero);
  return m;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sigh-base-portable-'));
  tearDown(() => tmp.deleteSync(recursive: true));
  String chemin(String n) => '${tmp.path}/$n';

  Future<ServiceBasePortable> service(Magasin m,
      {String role = 'fileul',
      MoteurFileul? moteur,
      bool rattache = true,
      bool Function(String)? peut,
      List<int>? Function()? laCle,
      Mere? Function()? mere,
      String? dossier,
      DateTime Function()? horloge}) async {
    return ServiceBasePortable(
      magasin: m,
      dossierDonnees: dossier ?? tmp.path,
      role: () => role,
      cleClinique: () async => laCle == null ? cle : laCle(),
      peut: peut ?? (_) => true,
      rattache: () => rattache,
      moteur: moteur,
      mere: mere,
      configMere: (db, b64) => ConfigMere(port: 0, dbChemin: db, admin: 'adm', cleBase64: b64, dossierSauvegardes: chemin('sauv')),
      horloge: horloge,
    );
  }

  MoteurFileul moteur(String nom) => MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: nom);

  group('exporter', () {
    test('un fichier relu et VÉRIFIÉ ; ni comptes hachés, ni jetons, ni clé ; journal d’audit en COMPTES seulement ; preuve posée', () async {
      final m = await magasinPeuple();
      final s = await service(m);
      final r = await s.exporter(dossierDestination: chemin('exports'));
      expect(r.verifie, isTrue);
      expect(File(r.chemin).existsSync(), isTrue);
      expect(r.manifeste.compteurs['patients'], 5);
      expect(r.manifeste.exclusions, containsAll(['identifiants', 'jetonsEnquete']));
      final brut = latin1.decode(File(r.chemin).readAsBytesSync());
      for (final x in ['NOMSECRET', 'HACHESECRET', 'JETONSECRET']) {
        expect(brut.contains(x), isFalse);
      }
      final log = m.collection('audit').toutes.last;
      expect(log['action'], 'Export de la base complète');
      expect(jsonEncode(log).contains('NOMSECRET'), isFalse, reason: 'le journal ne porte aucun contenu médical');
      expect(s.preuves.preuve('export')!.verifiee, isTrue);
    });

    test('geste réservé : sans le droit, refus nommé, rien d’écrit ; sans clé, CLE_ABSENTE', () async {
      final m = await magasinPeuple();
      await expectLater((await service(m, peut: (g) => g != gesteBaseExporter)).exporter(dossierDestination: chemin('exports')), refus('GESTE_RESERVE'));
      expect(Directory(chemin('exports')).existsSync(), isFalse);
      await expectLater((await service(m, laCle: () => null)).exporter(dossierDestination: chemin('exports')), refus('CLE_ABSENTE'));
    });

    test('un export de mère sans service en marche est refusé (il serait incomplet)', () async {
      await expectLater((await service(await magasinPeuple(), role: 'mere')).exporter(dossierDestination: chemin('e')), refus('CONTENU_INCOMPLET'));
    });
  });

  group('fileul : exporté, réimporté sur un poste NEUF, la file reprise', () {
    test('de bout en bout : copie préalable vérifiée, magasin neuf relisible, file reprise à la mise en service, échange de dossiers au démarrage sans rien supprimer', () async {
      // Le poste d'origine : deux saisies en file.
      final mA = await magasinPeuple();
      final moteurA = moteur('Poste A');
      moteurA.ecrire('patients', 'fa1', existe: false, champs: {'nom': 'ATTENTE1', 'prenom': 'p', 'naissance': '1990-01-01', 'dateCreation': '2026-11-17'});
      moteurA.ecrire('patients', 'fa2', existe: false, champs: {'nom': 'ATTENTE2', 'prenom': 'p', 'naissance': '1990-01-02', 'dateCreation': '2026-11-17'});
      final export = await (await service(mA, moteur: moteurA)).exporter(dossierDestination: chemin('exports'));
      expect(export.manifeste.fileEnAttente, 2);

      // Le poste d'arrivée : NEUF.
      final dossierB = chemin('posteB');
      Directory('$dossierB/magasin').createSync(recursive: true);
      File('$dossierB/magasin/vieux.txt').writeAsStringSync('ancien magasin');
      final mB = await magasinPeuple();
      final moteurB = moteur('Poste B');
      expect(moteurB.estNeuf, isTrue);
      final sB = await service(mB, moteur: moteurB, dossier: dossierB);
      final ri = await sB.importer(chemin: export.chemin);
      expect(ri.mode, ModeImport.complet);
      expect(ri.fileReprise, 2);
      expect(ri.copiePrealable, isNotNull, reason: 'un fileul rattaché copie d’abord son magasin actuel');
      expect(File(ri.copiePrealable!).existsSync(), isTrue);
      expect(Directory(ri.dossierNeuf).existsSync(), isTrue);
      expect(Directory('$dossierB/magasin').listSync().whereType<File>().map((f) => f.uri.pathSegments.last), contains('vieux.txt'), reason: 'la base en service n’a pas bougé');
      final relu = await PersistanceFichiers('${ri.dossierNeuf}/magasin').lireTout();
      expect(relu['patients']!.length, 5);
      expect(relu.containsKey('identifiants'), isFalse);
      expect((await PersistanceFichiers('${ri.dossierNeuf}/magasin').lireMeta())[schemaCleMeta], schemaDonneesCourant);

      // Refus de la mise en service : motif court, droit absent.
      await expectLater(sB.programmerMiseEnService(dossierNeuf: ri.dossierNeuf, motif: 'court'), refus('MOTIF_OBLIGATOIRE'));
      final sansDroit = await service(mB, moteur: moteurB, dossier: dossierB, peut: (g) => g != gesteBaseImporter);
      await expectLater(sansDroit.programmerMiseEnService(dossierNeuf: ri.dossierNeuf, motif: 'remplacement du poste caisse'), refus('GESTE_RESERVE'));
      expect(moteurB.estNeuf, isTrue, reason: 'rien n’est repris avant le geste');

      await sB.programmerMiseEnService(dossierNeuf: ri.dossierNeuf, motif: 'remplacement du poste caisse en panne');
      expect(moteurB.fileEnAttente().length, 2, reason: 'la file du poste exporté est reprise : aucune saisie ne se perd');
      expect(File('$dossierB/${ServiceBasePortable.fichierMiseEnService}').existsSync(), isTrue);
      expect(Directory('$dossierB/magasin').listSync().whereType<File>().map((f) => f.uri.pathSegments.last), contains('vieux.txt'), reason: 'rien ne bouge avant le redémarrage');

      // Au démarrage : l'échange, l'ancien magasin RENOMMÉ.
      final trace = ServiceBasePortable.appliquerMiseEnServiceEnAttente(dossierB, maintenant: DateTime(2026, 11, 17, 9));
      expect(trace!['echec'], isNull);
      final anciens = Directory(dossierB).listSync().whereType<Directory>().where((d) => d.path.contains('magasin.avant-import-')).toList();
      expect(anciens, hasLength(1));
      expect(File('${anciens.single.path}/vieux.txt').readAsStringSync(), 'ancien magasin', reason: 'jamais supprimé (RG-14)');
      expect(File('$dossierB/magasin/vieux.txt').existsSync(), isFalse);
      expect((await PersistanceFichiers('$dossierB/magasin').lireTout())['patients']!.length, 5);
      expect(File('$dossierB/${ServiceBasePortable.fichierMiseEnService}').existsSync(), isFalse);
      expect(ServiceBasePortable.appliquerMiseEnServiceEnAttente(dossierB), isNull, reason: 'une seule fois');
      // La trace d'audit.
      ServiceBasePortable.journaliserMiseEnServiceEffectuee(mB, dossierB);
      expect(mB.collection('audit').toutes.map((l) => l['action']), contains('Mise en service d\'une base importée'));
    });

    test('les refus se disent AVANT toute écriture : autre clinique, schéma plus récent, mauvaise clé, fichier altéré, cible existante, droit', () async {
      final m = await magasinPeuple();
      final s = await service(m);
      final bon = await s.exporter(dossierDestination: chemin('exports'));
      final octets = File(bon.chemin).readAsBytesSync();
      // autre clinique
      final autre = await ExportPortable.sceller(
          cle: cle, contenu: ContenuExport(collections: {'patients': []}), role: epRoleFileul, clinique: const IdentiteExport(sigle: 'ZZ', nom: 'Autre clinique', ifu: '999'), logicielVersion: '1');
      File(chemin('autre.sghx')).writeAsBytesSync(autre);
      await expectLater(s.importer(chemin: chemin('autre.sghx')), refus('AUTRE_CLINIQUE'));
      // schéma plus récent
      final futur = await ExportPortable.sceller(
          cle: cle, contenu: ContenuExport(collections: {'patients': []}), role: epRoleFileul, clinique: s.identite, logicielVersion: '9', schema: schemaDonneesCourant + 1);
      File(chemin('futur.sghx')).writeAsBytesSync(futur);
      await expectLater(s.importer(chemin: chemin('futur.sghx')), refus('SCHEMA_PLUS_RECENT'));
      // mauvaise clé
      await expectLater((await service(m, laCle: () => autreCle)).importer(chemin: bon.chemin), refus('CLE_INCORRECTE'));
      // altéré
      final alt = List<int>.from(octets)..[octets.length - 30] ^= 0x42;
      File(chemin('altere.sghx')).writeAsBytesSync(alt);
      await expectLater(s.importer(chemin: chemin('altere.sghx')), refus('FICHIER_ALTERE'));
      // cible existante
      Directory(chemin('cible')).createSync();
      await expectLater(s.importer(chemin: bon.chemin, dossierNeuf: chemin('cible')), refus('CIBLE_EXISTE'));
      // droit
      await expectLater((await service(m, peut: (g) => g != gesteBaseImporter)).importer(chemin: bon.chemin), refus('GESTE_RESERVE'));
      expect(Directory(tmp.path).listSync().whereType<Directory>().where((d) => d.path.contains('import-')), isEmpty, reason: 'aucun magasin neuf n’a été écrit pour un refus');
    });

    test('un fileul NON RATTACHÉ importe comme une mère de lui-même : l’export d’un fileul est refusé, celui d’une mère accepté, sans copie préalable', () async {
      final m = await magasinPeuple();
      final fich = await (await service(m)).exporter(dossierDestination: chemin('exports'));
      await expectLater((await service(m, rattache: false)).importer(chemin: fich.chemin), refus('FILEUL_VERS_MERE'));
      final enMere = await ExportPortable.sceller(
          cle: cle, contenu: ContenuExport(collections: {'patients': [{'id': 'P1', 'statut': 'actif'}]}), role: epRoleMere, clinique: (await service(m)).identite, logicielVersion: '1');
      File(chemin('mere.sghx')).writeAsBytesSync(enMere);
      final r = await (await service(m, rattache: false)).importer(chemin: chemin('mere.sghx'));
      expect(r.mode, ModeImport.complet);
      expect(r.copiePrealable, isNull);
    });

    test('un export de MÈRE sur un fileul rattaché : resynchronisation (la mère reste l’autorité) ; plus ancien que la dernière synchro : avertissement, saisies LISTÉES et gardées', () async {
      final m = await magasinPeuple();
      final moteurB = moteur('B');
      moteurB.ecrire('patients', 'fb1', existe: false, champs: {'nom': 'LOCALE', 'prenom': 'p', 'naissance': '1990-01-01', 'dateCreation': '2026-11-17'});
      final ancienne = DateTime.now().toUtc().subtract(const Duration(days: 3));
      final enMere = await ExportPortable.sceller(
          cle: cle, contenu: ContenuExport(collections: {'patients': [{'id': 'P1', 'statut': 'actif'}]}), role: epRoleMere, clinique: (await service(m)).identite, logicielVersion: '1', maintenant: ancienne);
      File(chemin('mere.sghx')).writeAsBytesSync(enMere);
      final s = await service(m, moteur: moteurB, rattache: true);
      final r = await s.importer(chemin: chemin('mere.sghx'));
      expect(r.mode, ModeImport.resynchronisation);
      expect(r.avertissement, isNotNull, reason: 'une saisie locale est postérieure au fichier et non synchronisée');
      expect(r.avertissement!.saisies.single.fiche, 'fb1');
      expect(r.avertissement!.message, contains('non bloquant'));
      expect(moteurB.fileEnAttente().length, 1, reason: 'la saisie locale reste dans la file : jamais écrasée');
      final liste = File('${File(r.copiePrealable!).parent.path}/saisies-non-synchronisees.json');
      expect(liste.existsSync(), isTrue, reason: 'la liste est gardée avec la copie du magasin remplacé');
      expect(jsonDecode(liste.readAsStringSync()), hasLength(1));
      // La file d'un fileul exporté repris sur un poste qui n'est PAS neuf n'est pas mêlée à sa file : elle est listée.
      final moteurA = moteur('A');
      moteurA.ecrire('patients', 'fa1', existe: false, champs: {'nom': 'AUTRE', 'prenom': 'p', 'naissance': '1990-01-01', 'dateCreation': '2026-11-17'});
      final fA = await (await service(m, moteur: moteurA)).exporter(dossierDestination: chemin('exA'));
      final r2 = await (await service(m, moteur: moteurB)).importer(chemin: fA.chemin);
      expect(r2.fileReprise, 0);
      expect(r2.fileNonReprise.single.fiche, 'fa1');
    });
  });

  test('MÈRE : exportée avec son journal, importée dans une base NEUVE (mere.db) ; l’échange au démarrage renomme l’ancienne sans la supprimer', () async {
    final cfg = ConfigMere(port: 0, dbChemin: chemin('mere.db'), admin: 'adm', cleBase64: base64.encode(cle), dossierSauvegardes: chemin('sauv'));
    final mere = await Mere.creer(cfg);
    await mere.base.exec('INSERT INTO evenements(quand,niveau,source,message) VALUES(?,?,?,?)', [1, 'info', 'test', 'un evenement']);
    final m = await magasinPeuple();
    final s = await service(m, role: 'mere', mere: () => mere);
    final e = await s.exporter(dossierDestination: chemin('exports'));
    expect(e.manifeste.compteurs.keys.any((k) => k.startsWith('sync.')), isTrue);
    await mere.arreter();
    final ri = await s.importer(chemin: e.chemin);
    expect(ri.lignesMere, greaterThan(0));
    expect(File('${ri.dossierNeuf}/mere.db').existsSync(), isTrue);
    expect(File(chemin('mere.db')).existsSync(), isTrue, reason: 'la base de la mère en service n’est pas touchée');
    await s.programmerMiseEnService(dossierNeuf: ri.dossierNeuf, motif: 'reprise de la mère sur une machine neuve');
    final t = ServiceBasePortable.appliquerMiseEnServiceEnAttente(tmp.path, maintenant: DateTime(2026, 11, 17, 10));
    expect(t!['renomme'], contains('mere.db'));
    expect(File(chemin('mere.db.avant-import-20261117-100000')).existsSync(), isTrue);
    final m2 = await Mere.creer(cfg);
    expect(await m2.base.meta('cle'), base64.encode(cle));
    expect((await m2.base.select("SELECT message FROM evenements WHERE source='test'")).single['message'], 'un evenement');
    await m2.arreter();
  });

  test('mise en service SANS copie vérifiée récente : refusée, nommée', () async {
    final m = await magasinPeuple();
    final s = await service(m);
    Directory('${tmp.path}/neuf/magasin').createSync(recursive: true);
    File('${tmp.path}/neuf/IMPORT.json').writeAsStringSync('{}');
    await expectLater(s.programmerMiseEnService(dossierNeuf: '${tmp.path}/neuf', motif: 'reprise du poste après sinistre'), refus('MISE_EN_SERVICE_SANS_COPIE'));
    await s.exporter(dossierDestination: chemin('e'));
    await s.programmerMiseEnService(dossierNeuf: '${tmp.path}/neuf', motif: 'reprise du poste après sinistre');
    // un échec de l'échange ne laisse pas le poste à moitié échangé
    Directory('${tmp.path}/neuf/magasin').deleteSync(recursive: true);
    final t = ServiceBasePortable.appliquerMiseEnServiceEnAttente(tmp.path);
    expect(t!['echec'], isNotNull);
    expect(File('${tmp.path}/${ServiceBasePortable.fichierMiseEnService}.echec').existsSync(), isTrue);
  });
}
