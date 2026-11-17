// SATISFACTION EN LIGNE (décision de la Direction du 16/11/2026, section 8), côté MÈRE :
//  1. vecteurs croisés : les enveloppes produites par le SCRIPT DU NAVIGATEUR (apps/web/public/js/satisfaction.js, voies Web Crypto et repli) se
//     déchiffrent ici à l'identique ; une enveloppe chiffrée ici (même algorithme que le navigateur) se déchiffre par l'implémentation de référence Node ;
//  2. bout en bout avec le relais de référence (packages/sync/banc/relais.js) : la mère publie le lien d'une enquête, le navigateur chiffre et dépose,
//     la mère relève, déchiffre, enregistre la réponse (canal « Lien public ») AU JOURNAL (elle redescend aux fileuls), puis acquitte ; une question
//     ajoutée au modèle paraît sur le lien ; une enveloppe illisible est écartée et nommée ; une révocation ferme la porte.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart' show iso, qualCanalPublic, qualNouveauJetonEnLigne, qualSaisiPar, qualSatisfaction;
import 'package:sigh_sync/src/commun.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:sigh_sync/src/satisfaction_en_ligne.dart';
import 'package:test/test.dart';

final String banc = '${Directory.current.path}/../sync/banc';
final String web = '${Directory.current.path}/../../apps/web';

Future<Map<String, Object?>> navigateur(Map<String, Object?> entree) async {
  final r = await Process.run('node', ['--no-warnings', '$web/tests/js/satisfaction.mjs', jsonEncode(entree)]);
  return (jsonDecode((r.stdout as String).trim()) as Map).cast<String, Object?>();
}

void main() {
  group('vecteurs croisés navigateur ↔ mère', () {
    final v = jsonDecode(File('test/vecteurs/satisfaction_navigateur.json').readAsStringSync()) as Map;
    final paire = (v['paire'] as Map).cast<String, Object?>();

    test('la paire de la clinique se reconstruit depuis sa clé privée (même clé publique, même identifiant)', () async {
      final k = await satCleDepuisGraine(satDeB64u('${paire['privee']}'));
      expect(satB64u(k.publique), paire['publique']);
      expect(k.kid, paire['kid']);
    });

    test('chaque enveloppe du navigateur (Web Crypto et repli) se déchiffre à l’identique ; un autre lien ou une altération est refusé', () async {
      final k = await satCleDepuisGraine(satDeB64u('${paire['privee']}'));
      for (final c in (v['cas'] as List).cast<Map>()) {
        final env = (c['enveloppe'] as Map).cast<String, Object?>();
        expect(await satDechiffrer(env, k, '${v['jeton']}'), c['reponses'], reason: '${c['voie']}');
        await expectLater(satDechiffrer(env, k, 'autrejetonautrejetonautr'), throwsA(isA<FormatException>()));
        final ct = satDeB64u('${env['ct']}')..[5] ^= 1;
        await expectLater(satDechiffrer({...env, 'ct': satB64u(ct)}, k, '${v['jeton']}'), throwsA(isA<FormatException>()));
      }
      final autre = await satNouvelleCle();
      await expectLater(satDechiffrer((v['cas'] as List).first['enveloppe'] as Map, autre, '${v['jeton']}'), throwsA(isA<FormatException>()));
    });

    test('une enveloppe chiffrée ici, comme le navigateur, se déchiffre par la référence Node ; le bourrage cache la longueur', () async {
      final k = await satNouvelleCle();
      final reps = {'Q_ACCUEIL': '4', 'Q_COM': 'Un mot.'};
      final env = await satChiffrer(reps, jeton: 'abcdefghijkmnpqrstuvwxyz', kid: k.kid, clePublique: satB64u(k.publique));
      expect((satDeB64u('${env['ct']}').length - 16) % 256, 0);
      expect(await satDechiffrer(env, k, 'abcdefghijkmnpqrstuvwxyz'), reps);
      final r = await Process.run('node', [
        '-e',
        "const M=require(process.argv[1]);const a=JSON.parse(process.argv[2]);process.stdout.write(JSON.stringify(M.dechiffrer(a.env,a.paire,a.jeton).reponses))",
        '$banc/satisfaction-cle.js',
        jsonEncode({
          'env': env,
          'paire': {'privee': satB64u(k.privee), 'publique': satB64u(k.publique), 'kid': k.kid},
          'jeton': 'abcdefghijkmnpqrstuvwxyz'
        }),
      ]);
      expect(jsonDecode(r.stdout as String), reps, reason: '${r.stderr}');
    });
  });

  group('bout en bout avec le relais de référence', () {
    late Directory dir;
    late Process relais;
    late int port;
    late Mere m;
    final client = HttpClient();

    Future<({int statut, String corps})> http(String methode, String chemin, [Object? json]) async {
      final req = await client.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
      if (json != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(json));
      }
      final rep = await req.close();
      return (statut: rep.statusCode, corps: await utf8.decoder.bind(rep).join());
    }

    Future<void> fiche(String col, String id, Map<String, Object?> data) => m.base
        .exec('INSERT INTO fiches(collection,id,data,fieldseq,archive) VALUES(?,?,?,?,0) ON CONFLICT(collection,id) DO UPDATE SET data=excluded.data', [col, id, jsonEncode(data), '{}']);
    Future<Map<String, Object?>> lire(String col, String id) async => (await m.lire(col, id))!.data;

    final enquete = <String, Object?>{
      'reference': 'ENQ-SAT',
      'statut': 'actif',
      'titre': 'Votre avis compte',
      'description': 'Quelques questions sur votre passage.',
      'questions': [
        {'code': 'Q_ACCUEIL', 'libelle': 'Qualité de l’accueil', 'type': 'note'},
        {'code': 'Q_RECO', 'libelle': 'Recommanderiez-vous la clinique ?', 'type': 'choix', 'options': ['Oui', 'Plutôt oui', 'Non']},
        {'code': 'Q_COM', 'libelle': 'Un commentaire ?', 'type': 'texte'},
      ],
    };
    const code = 'pqrstuvwxyzabcdefghijkmn';

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('sigh-sat-dart-');
      final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = sock.port;
      await sock.close();
      relais = await Process.start('node', ['--no-warnings', '$banc/relais.js', '--port=$port', '--db=${dir.path}/relais.sqlite', '--banc=1', '--sauvegardes=${dir.path}/blocs']);
      relais.stdout.drain<void>();
      relais.stderr.drain<void>();
      for (var i = 0; i < 100; i++) {
        try {
          await http('GET', '/satisfaction/inconnu');
          break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:', relais: 'http://127.0.0.1:$port', secretRelais: 'secret-mere'));
      await fiche('enquetes', 'ENQ00001', enquete);
      final j = qualNouveauJetonEnLigne(
          enquete: {...enquete, 'id': 'ENQ00001'},
          jeton: code,
          expireLe: iso(DateTime.now().add(const Duration(days: 30))),
          aujourdhui: DateTime.now(),
          ouvertPar: 'Compte d’essai');
      await fiche('jetonsEnquete', 'JET00001', j);
    });
    tearDown(() async {
      relais.kill(ProcessSignal.sigkill);
      await relais.exitCode;
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('publier, chiffrer dans le navigateur, relever, déchiffrer, enregistrer au journal, acquitter', () async {
      final p = await m.pont.satisfaction.publier();
      expect(p['publies'], 1, reason: '$p');
      final lien = await lire('jetonsEnquete', 'JET00001');
      expect(lien['lienPublic'], 'http://127.0.0.1:$port/satisfaction/$code');
      expect(lien['erreurRelais'], '');
      final page = await http('GET', '/satisfaction/$code');
      expect(page.statut, 200);
      expect(page.corps, contains('Qualité de l’accueil (1 à 5)'), reason: 'le modèle publié vient du générateur du domaine');
      expect(page.corps.contains('ENQ00001'), isFalse, reason: 'l’identifiant de l’enquête ne part pas au relais');
      // Republier sans changement ne renvoie rien.
      expect((await m.pont.satisfaction.publier())['publies'], 0);

      // Le navigateur chiffre avec la clé PUBLIQUE publiée, et dépose.
      final modele = (jsonDecode((await http('GET', '/satisfaction/$code/modele')).corps) as Map).cast<String, Object?>();
      final reps = {'Q_ACCUEIL': '4', 'Q_RECO': 'Plutôt oui', 'Q_COM': 'Sentinelle-Dart-Commentaire'};
      final env = ((await navigateur({'action': 'chiffrer', 'reponses': reps, 'publication': modele}))['enveloppe'] as Map).cast<String, Object?>()..remove('voie');
      expect((await http('POST', '/satisfaction/$code/reponse', {'enveloppe': env})).statut, 202);
      final tout = (await http('GET', '/banc/satisfaction/tout')).corps;
      expect(tout.contains('Sentinelle-Dart'), isFalse, reason: 'le relais ne détient rien de lisible');
      expect(tout.contains(code), isFalse, reason: 'ni le jeton en clair');

      // La mère relève, déchiffre, enregistre, acquitte.
      final r = await m.pont.satisfaction.relever();
      expect(r, {'recues': 1, 'illisibles': 0});
      final rows = await m.base.select("SELECT id, data FROM fiches WHERE collection='reponsesEnquetes'");
      expect(rows, hasLength(1));
      final rep = (jsonDecode(rows.first['data'] as String) as Map).cast<String, Object?>();
      expect('${rows.first['id']}', startsWith('SAT-'));
      expect(rep['canal'], qualCanalPublic);
      expect(rep['saisiPar'], qualSaisiPar(anonyme: true));
      expect(rep['jetonId'], 'JET00001');
      expect(rep['enqueteId'], 'ENQ00001');
      expect(rep['reponses'], {'Q_ACCUEIL': 4, 'Q_RECO': 'Plutôt oui', 'Q_COM': 'Sentinelle-Dart-Commentaire'});
      final ops = await m.base.select("SELECT appareil, type FROM operations WHERE collection='reponsesEnquetes'");
      expect(ops.single['type'], 'creer', reason: 'la réponse entre au journal : elle redescend aux fileuls');
      expect(ops.single['appareil'], 'mere');
      expect(qualSatisfaction({...enquete, 'id': 'ENQ00001'}, [rep]).reponses, 1, reason: 'les statistiques la comptent');
      expect(jsonDecode((await http('GET', '/banc/satisfaction/tout')).corps)['enveloppes'], isEmpty, reason: 'acquittée, donc effacée du relais');
      // Une relève rejouée ne double rien.
      expect((await m.pont.satisfaction.relever())['recues'], 0);
      final etat = await m.pont.satisfaction.etat();
      expect(etat['recues'], 1);
      expect(etat.toString().contains('privee'), isFalse, reason: 'l’état ne montre jamais la clé privée');
    });

    test('une question ajoutée au modèle paraît sur le lien ; une enveloppe illisible est écartée et nommée ; la révocation ferme la porte', () async {
      await m.pont.satisfaction.publier();
      await fiche('enquetes', 'ENQ00001', {
        ...enquete,
        'questions': [
          ...(enquete['questions'] as List),
          {'code': 'Q_PROPRE', 'libelle': 'Propreté des locaux', 'type': 'note'}
        ]
      });
      expect((await m.pont.satisfaction.publier())['publies'], 1);
      expect((await http('GET', '/satisfaction/$code')).corps, contains('Propreté des locaux (1 à 5)'));

      // Une enveloppe de bonne forme mais qui n'a pas été chiffrée pour la clinique.
      final k = await m.pont.satisfaction.cle();
      final faux = await satChiffrer({'Q_ACCUEIL': '5'}, jeton: 'autrejetonautrejetonautr', kid: k.kid, clePublique: satB64u(k.publique));
      expect((await http('POST', '/satisfaction/$code/reponse', {'enveloppe': faux})).statut, 202);
      expect(await m.pont.satisfaction.relever(), {'recues': 0, 'illisibles': 1});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final ev = await m.base.select("SELECT message FROM evenements WHERE source='satisfaction' AND niveau='alerte'");
      expect(ev.single['message'], contains('JET00001'));
      expect(jsonDecode((await http('GET', '/banc/satisfaction/tout')).corps)['enveloppes'], isEmpty);

      // Le poste révoque le lien : la mère le retire du relais et l'écrit sur la fiche.
      await fiche('jetonsEnquete', 'JET00001', {...await lire('jetonsEnquete', 'JET00001'), 'revoqueLe': iso(DateTime.now())});
      expect((await m.pont.satisfaction.publier())['revoques'], 1);
      expect((await http('GET', '/satisfaction/$code')).statut, 404);
      expect('${(await lire('jetonsEnquete', 'JET00001'))['relaisRevoqueLe']}', isNotEmpty);
    });

    test('un lien nominatif n’est jamais publié en ligne : refus nommé sur la fiche', () async {
      await fiche('jetonsEnquete', 'JET00001', {...await lire('jetonsEnquete', 'JET00001'), 'anonyme': false});
      final p = await m.pont.satisfaction.publier();
      expect(p['publies'], 0);
      expect('${(await lire('jetonsEnquete', 'JET00001'))['erreurRelais']}', contains('anonyme'));
      expect((await http('GET', '/satisfaction/$code')).statut, 404);
    });
  });

  test('sans lien en ligne, le tour ne fait rien : ni clé tirée, ni relais sollicité', () async {
    final m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:', relais: 'http://127.0.0.1:9', secretRelais: 'secret-mere'));
    await m.pont.satisfaction.tour();
    expect(await m.base.meta(SatisfactionEnLigne.cleMeta), isNull);
    expect(await m.base.meta(SatisfactionEnLigne.cleDerniereReleve), isNull);
  });
}
