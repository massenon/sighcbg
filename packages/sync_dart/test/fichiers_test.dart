// Le dossier des scans de la mère et le canal fileul → mère : dépôt par blocs scellés, lecture, empreintes, refus nommés, sauvegarde et restauration.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';
import 'package:test/test.dart';

List<int> pdfDe(int taille, [int graine = 1]) {
  final r = Random(graine);
  return [...latin1.encode('%PDF-1.4\n% scan de test\n'), for (var i = 0; i < taille; i++) r.nextInt(256)];
}

String hexDe(String b64) => base64.decode(b64).map((o) => o.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sigh-scans-'));
  tearDown(() => tmp.deleteSync(recursive: true));
  String chemin(String n) => '${tmp.path}/$n';

  group('StockFichiers', () {
    test('un dépôt range sous le nom normalisé ; rejoué, il est idempotent ; un autre contenu sous le même nom est refusé', () async {
      final s = StockFichiers(chemin('scans'));
      final o = pdfDe(500);
      final sha = docSha256(o);
      await s.deposer(octets: o, sha256: sha, nomNormalise: '2026-11-11_ARR_0042.pdf');
      await s.deposer(octets: o, sha256: sha, nomNormalise: '2026-11-11_ARR_0042.pdf');
      expect(File(chemin('scans/2026-11-11_ARR_0042.pdf')).readAsBytesSync(), o);
      expect(s.nombre, 1);
      final autre = pdfDe(500, 2);
      await expectLater(s.deposer(octets: autre, sha256: docSha256(autre), nomNormalise: '2026-11-11_ARR_0042.pdf'), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'NOM_PRIS')));
      // la version 2 d'un courrier a SON nom : l'ancienne reste
      await s.deposer(octets: autre, sha256: docSha256(autre), nomNormalise: '2026-11-11_ARR_0042_v2.pdf');
      expect(s.nombre, 2);
      expect(await s.lire(sha), o);
    });
    test('refus nommés : nom libre, empreinte annoncée fausse', () async {
      final s = StockFichiers(chemin('scans'));
      final o = pdfDe(50);
      await expectLater(s.deposer(octets: o, sha256: docSha256(o), nomNormalise: '../evil.pdf'), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'NOM_NON_NORMALISE')));
      await expectLater(s.deposer(octets: o, sha256: 'a' * 64, nomNormalise: '2026-11-11_ARR_0001.pdf'), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'EMPREINTE_DIVERGENTE')));
      expect(s.nombre, 0);
    });
    test('un fichier altéré sur disque n’est JAMAIS servi', () async {
      final s = StockFichiers(chemin('scans'));
      final o = pdfDe(80);
      final sha = docSha256(o);
      await s.deposer(octets: o, sha256: sha, nomNormalise: '2026-11-11_DEP_0001.pdf');
      File(chemin('scans/2026-11-11_DEP_0001.pdf')).writeAsBytesSync([...o, 1]);
      await expectLater(s.lire(sha), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'FICHIER_ALTERE')));
      expect(s.controler()['alteres'], ['2026-11-11_DEP_0001.pdf']);
      File(chemin('scans/2026-11-11_DEP_0001.pdf')).deleteSync();
      expect(s.controler()['manquants'], ['2026-11-11_DEP_0001.pdf']);
      expect(await s.lire(sha), isNull);
    });
    test('l’index se reconstruit depuis les fichiers', () async {
      final s = StockFichiers(chemin('scans'));
      final o = pdfDe(80);
      await s.deposer(octets: o, sha256: docSha256(o), nomNormalise: '2026-11-11_DEP_0001.pdf');
      File(chemin('scans/empreintes.json')).writeAsStringSync('{illisible');
      final s2 = StockFichiers(chemin('scans'));
      expect(s2.existe(docSha256(o)), isTrue);
    });
    test('réception par blocs : ordre exigé, rejeu ignoré, reprise, taille et format contrôlés', () async {
      final s = StockFichiers(chemin('scans'));
      final o = pdfDe(tailleBloc * 2 + 10);
      final sha = docSha256(o);
      List<int> bloc(int i) => o.sublist(i * tailleBloc, min(o.length, (i + 1) * tailleBloc));
      Future<Map<String, Object?>> envoie(int i, {int? taille, String famille = 'courrier', int? tailleMax}) => s.recevoirBloc(
          sha256: sha, nomNormalise: '2026-11-11_ARR_0001.pdf', nomOrigine: 'a.pdf', famille: famille, taille: taille ?? o.length, index: i, total: 3, octets: bloc(i), tailleMax: tailleMax ?? docTailleDefaut);
      await envoie(0);
      await expectLater(envoie(2), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'BLOC_HORS_ORDRE')));
      expect((await envoie(0))['rejeu'], true);
      expect(s.blocsRecus(sha), 1);
      await envoie(1);
      final fin = await envoie(2);
      expect(fin['complet'], true);
      expect(await s.lire(sha), o);
      await expectLater(envoie(0, tailleMax: 1000), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'TAILLE_DEPASSEE')));
    });
    test('SAUVEGARDE → RESTAURATION : aller-retour, empreintes vérifiées, source corrompue refusée, rien d’écrasé', () async {
      final s = StockFichiers(chemin('scans'));
      final a = pdfDe(1000, 1), b = pdfDe(2000, 2);
      await s.deposer(octets: a, sha256: docSha256(a), nomNormalise: '2026-11-11_ARR_0001.pdf');
      await s.deposer(octets: b, sha256: docSha256(b), nomNormalise: '2026-11-05_CBG-12-26_ordonnance_007.pdf');
      final r = s.sauvegarder(chemin('sauv'));
      expect(r['copies'], 2);
      expect(s.sauvegarder(chemin('sauv'))['inchanges'], 2, reason: 'incrémentale');
      expect(File(chemin('sauv/MANIFESTE.json')).existsSync(), isTrue);
      // un disque neuf : la restauration rend les fichiers ET vérifie les empreintes
      final neuf = StockFichiers(chemin('neuf'));
      final rest = neuf.restaurer(chemin('sauv'));
      expect(rest['restaures'], 2);
      expect(rest['complet'], true);
      expect(await neuf.lire(docSha256(a)), a);
      expect(await neuf.lire(docSha256(b)), b);
      expect(File(chemin('neuf/2026-11-11_ARR_0001.pdf')).readAsBytesSync(), a);
      // restaurer deux fois : tout est « présent », rien n'est réécrit
      expect(neuf.restaurer(chemin('sauv'))['presents'], 2);
      // une sauvegarde dont un fichier est corrompu : refusé, nommé, jamais copié
      File(chemin('sauv/2026-11-11_ARR_0001.pdf')).writeAsBytesSync([...a, 9]);
      final vide = StockFichiers(chemin('vide'));
      final r2 = vide.restaurer(chemin('sauv'));
      expect(r2['refuses'], ['2026-11-11_ARR_0001.pdf']);
      expect(r2['complet'], false);
      expect(File(chemin('vide/2026-11-11_ARR_0001.pdf')).existsSync(), isFalse);
      expect(r2['restaures'], 1);
      // une sauvegarde de la source altérée ne propage pas la corruption
      File(chemin('scans/2026-11-11_ARR_0001.pdf')).writeAsBytesSync([...a, 7]);
      final r3 = s.sauvegarder(chemin('sauv2'));
      expect(r3['alteres'], ['2026-11-11_ARR_0001.pdf']);
      expect(File(chemin('sauv2/2026-11-11_ARR_0001.pdf')).existsSync(), isFalse);
      // pas de manifeste : refus nommé
      expect(() => vide.restaurer(chemin('rien')), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'SAUVEGARDE_SANS_MANIFESTE')));
    });
    test('changer le dossier copie et vérifie ; l’ancien est conservé', () async {
      final s = StockFichiers(chemin('scans'));
      final a = pdfDe(100);
      await s.deposer(octets: a, sha256: docSha256(a), nomNormalise: '2026-11-11_ARR_0001.pdf');
      final r = s.changerDossier(chemin('ailleurs'));
      expect(r['copies'], 1);
      expect(s.dossier, chemin('ailleurs'));
      expect(await s.lire(docSha256(a)), a);
      expect(File(chemin('scans/2026-11-11_ARR_0001.pdf')).existsSync(), isTrue, reason: 'RG-14 : l’ancien dossier n’est pas vidé');
      expect(() => s.changerDossier('  '), throwsA(isA<DocErreur>()));
    });
  });

  group('mère et fileul, canal scellé', () {
    late Mere mere;
    late String base;
    setUp(() async {
      mere = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:', admin: 'adm', dossierFichiers: chemin('mere-scans'), dossierSauvegardes: chemin('sauvegardes')));
      await mere.demarrer();
      base = 'http://127.0.0.1:${mere.portEcoute}';
    });
    tearDown(() => mere.arreter());

    Future<Map<String, Object?>> http(String m, String p, [Object? corps, Map<String, String>? ent]) async {
      final c = HttpClient();
      final r = await c.openUrl(m, Uri.parse('$base$p'));
      r.headers.contentType = ContentType.json;
      ent?.forEach(r.headers.set);
      if (corps != null) r.add(utf8.encode(jsonEncode(corps)));
      final rep = await r.close();
      final j = jsonDecode(await utf8.decoder.bind(rep).join()) as Map;
      c.close();
      return {'statut': rep.statusCode, ...j.cast<String, Object?>()};
    }

    Future<Fileul> poste({String cle = '', String role = 'fileul'}) async {
      final code = (await http('POST', '/admin/code', {'role': role}, {'x-admin': 'adm'}))['code'];
      final f = Fileul(ConfigFileul(port: 0, mere: base, dbChemin: ':memory:', cleClinique: cle));
      final (st, _) = await f.commande('POST /appairer', {'code': code}, const {});
      expect(st, 200);
      return f;
    }

    test('dépôt par un fileul, lecture par un AUTRE fileul : empreinte vérifiée, rien de lisible sur le fil, le mobile est refusé', () async {
      final cleHex = hexDe(mere.pont.cleBase64);
      final a = await poste(cle: cleHex), b = await poste(cle: cleHex);
      final o = pdfDe(tailleBloc * 2 + 777, 5);
      final sha = docSha256(o);
      await a.clientFichiers(famille: 'courrier').deposer(octets: o, sha256: sha, nomNormalise: '2026-11-11_ARR_0042.pdf', nomOrigine: 'scan.pdf');
      // chez la mère : sous son nom normalisé
      expect(File(chemin('mere-scans/2026-11-11_ARR_0042.pdf')).readAsBytesSync(), o);
      // un autre fileul lit, et le client RECALCULE l'empreinte
      expect(await b.clientFichiers().lire(sha), o);
      expect((await b.clientFichiers().info())['dossier'], chemin('mere-scans'));
      // un fichier inconnu : null, pas une erreur
      expect(await b.clientFichiers().lire('0' * 64), isNull);
      // sans la clé de clinique : refus nommé côté poste
      final sansCle = await poste();
      expect(() => sansCle.clientFichiers(), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'CLE_ABSENTE')));
      // mauvaise clé : la mère refuse un bloc qu'elle ne sait pas authentifier
      final fausse = await poste(cle: 'ab' * 32);
      await expectLater(fausse.clientFichiers().deposer(octets: o, sha256: sha, nomNormalise: '2026-11-11_ARR_0043.pdf'), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'enveloppe_alteree')));
      // un téléphone ne reçoit aucun scan
      final cm = (await http('POST', '/admin/code', {'role': 'mobile', 'etiquette': 'tel', 'profil': 'soignant', 'fonction': 'medecin'}, {'x-admin': 'adm'}))['code'];
      final tel = Fileul(ConfigFileul(port: 0, mere: base, dbChemin: ':memory:', cleClinique: cleHex));
      expect((await tel.commande('POST /appairer', {'code': cm}, const {})).$1, 200);
      await expectLater(tel.http1('GET', '/sync/fichier/info'), throwsA(predicate((e) => '$e'.contains('mobile_sans_scans'))));
    });

    test('la mère refuse un format non admis et une taille hors réglage, en le nommant ; la reprise repart du bloc attendu', () async {
      final cleHex = hexDe(mere.pont.cleBase64);
      final a = await poste(cle: cleHex);
      final faux = [...latin1.encode('MZ pas un pdf'), ...List.filled(300, 1)];
      await expectLater(a.clientFichiers(famille: 'courrier').deposer(octets: faux, sha256: docSha256(faux), nomNormalise: '2026-11-11_ARR_0044.pdf'), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'FORMAT_REFUSE')));
      mere.cfg.tailleMaxFichier = () => 100 * 1024;
      final gros = pdfDe(200 * 1024, 9);
      await expectLater(a.clientFichiers().deposer(octets: gros, sha256: docSha256(gros), nomNormalise: '2026-11-11_ARR_0045.pdf'), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'TAILLE_DEPASSEE')));
      mere.cfg.tailleMaxFichier = null;
      // coupure au milieu : un premier bloc est déjà chez la mère, le client reprend au bloc 1
      final o = pdfDe(tailleBloc * 2 + 5, 11);
      final sha = docSha256(o);
      await mere.stockFichiers!.recevoirBloc(sha256: sha, nomNormalise: '2026-11-11_ARR_0046.pdf', nomOrigine: 'a.pdf', famille: 'patient', taille: o.length, index: 0, total: 3, octets: o.sublist(0, tailleBloc));
      await a.clientFichiers().deposer(octets: o, sha256: sha, nomNormalise: '2026-11-11_ARR_0046.pdf');
      expect(await mere.stockFichiers!.lire(sha), o);
    });

    test('la sauvegarde de la base emporte les scans, et une restauration rend les fichiers', () async {
      final o = pdfDe(900, 3);
      await mere.stockFichiers!.deposer(octets: o, sha256: docSha256(o), nomNormalise: '2026-11-11_ARR_0001.pdf');
      final r = await http('POST', '/admin/sauvegarder', {}, {'x-admin': 'adm'});
      expect((r['scans'] as Map)['copies'], 1);
      final copie = chemin('sauvegardes/scans');
      expect(File('$copie/2026-11-11_ARR_0001.pdf').readAsBytesSync(), o);
      // le disque de la mère meurt : on restaure
      File(chemin('mere-scans/2026-11-11_ARR_0001.pdf')).deleteSync();
      expect((await http('GET', '/admin/fichiers/controle', null, {'x-admin': 'adm'}))['manquants'], ['2026-11-11_ARR_0001.pdf']);
      final rest = await http('POST', '/admin/fichiers/restaurer', {'source': copie}, {'x-admin': 'adm'});
      expect(rest['restaures'], 1);
      expect(rest['complet'], true);
      expect(await mere.stockFichiers!.lire(docSha256(o)), o);
    });

    test('sans dossier configuré, le service des fichiers est fermé et le dit', () async {
      final m2 = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:', admin: 'adm'));
      await m2.demarrer();
      final c = HttpClient();
      final r = await c.getUrl(Uri.parse('http://127.0.0.1:${m2.portEcoute}/admin/fichiers/info'));
      r.headers.set('x-admin', 'adm');
      final rep = await r.close();
      expect(rep.statusCode, 503);
      expect(jsonDecode(await utf8.decoder.bind(rep).join())['code'], 'fichiers_non_configures');
      c.close();
      await m2.arreter();
    });
  });
}
