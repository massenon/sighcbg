// ADR-0009 : la passerelle SMS de la mère. Fermée par défaut (rien ne part, pas même un essai) ; ouverte, la mère RECONTRÔLE le texte composé par le poste
// (mot interdit, numéro, variable restée : refus nommé, rien n'est déposé), dépose un SMS SIGNÉ au relais, garde au journal le numéro MASQUÉ sans le texte,
// nomme le refus du relais (plafond) et suit le statut jusqu'à « envoyé ».
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sigh_sync/src/commun.dart';
import 'package:sigh_sync/src/indicateurs_clinique.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:test/test.dart';

class Recu {
  Recu(this.chemin, this.entetes, this.corps);
  final String chemin;
  final Map<String, String> entetes;
  final List<int> corps;
}

void main() {
  late HttpServer relais;
  late List<Recu> recus;
  late int statutDepot;
  late String statutSuivi;
  late Mere m;
  const secret = 's3cr3t-de-la-mere';
  const texte = 'Bonjour, nous vous rappelons votre rendez-vous a la clinique le 18/11/2026 a 09h00.';

  setUp(() async {
    recus = [];
    statutDepot = 200;
    statutSuivi = 'en_attente';
    relais = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(relais.forEach((req) async {
      final corps = await req.fold<List<int>>([], (a, b) => [...a, ...b]);
      final h = <String, String>{};
      req.headers.forEach((k, v) => h[k] = v.join(','));
      recus.add(Recu(req.uri.path, h, corps));
      req.response.headers.contentType = ContentType.json;
      switch (req.uri.path) {
        case '/mere/sms':
          req.response.statusCode = statutDepot;
          final id = statutDepot == 200 ? ((jsonDecode(utf8.decode(corps)) as Map)['sms'] as Map)['id'] : null;
          req.response.write(statutDepot == 200
              ? jsonEncode({'ok': true, 'rejeu': false, 'sms': {'id': id, 'statut': 'en_attente', 'tentatives': 0}})
              : '{"code":"plafond_atteint","motif":"Le plafond quotidien de SMS (100) est atteint."}');
        case '/mere/sms/statuts':
          final ids = (jsonDecode(utf8.decode(corps)) as Map)['ids'] as List;
          req.response.write(jsonEncode({'statuts': [for (final i in ids) {'id': i, 'statut': statutSuivi, 'tentatives': 1, 'envoye_le': statutSuivi == 'envoye' ? 1 : null}]}));
        case '/mere/sms/etat':
          req.response.write('{"plafond_jour":100,"envoyes_aujourdhui":3,"en_attente":0,"tentatives_max":5,"longueur_max":320,"pilote":"journal"}');
        default:
          req.response.write('{"ok":true}');
      }
      await req.response.close();
    }));
    m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:', relais: 'http://127.0.0.1:${relais.port}', secretRelais: secret, versionApplication: '2.0.1'));
  });
  tearDown(() async => relais.close(force: true));

  List<Recu> depots() => recus.where((r) => r.chemin == '/mere/sms').toList();

  test('par défaut la passerelle est FERMÉE : rien ne part, pas même un essai, et le refus est nommé', () async {
    final e = await m.pont.sms.etat();
    expect((e['reglages'] as Map)['actif'], isFalse);
    expect(e['mots_interdits_statut'], contains('à valider par un médecin'));
    await expectLater(m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte}), throwsA(isA<Err>().having((x) => x.code, 'code', 'SMS_PASSERELLE_FERMEE')));
    expect(depots(), isEmpty);
  });

  test('l’état affiche le plafond lu au relais (il ne se règle pas depuis le poste)', () async {
    final e = await m.pont.sms.etat();
    expect((e['relais'] as Map)['plafond_jour'], 100);
    expect((e['relais'] as Map)['envoyes_aujourdhui'], 3);
    expect(e['relais_configure'], isTrue);
  });

  test('ouverte : la mère RECONTRÔLE ; un mot interdit, un numéro local ou une variable restée sont refusés et rien n’est déposé', () async {
    await m.pont.sms.regler({'actif': true});
    for (final (corps, code) in [
      ({'numero': '+2290100000001', 'texte': 'Votre résultat d’analyse est prêt.'}, 'SMS_CONTENU_MEDICAL'),
      ({'numero': '0100000001', 'texte': texte}, 'SMS_NUMERO_INVALIDE'),
      ({'numero': '+2290100000001', 'texte': 'Bonjour {{nom}}.'}, 'SMS_VARIABLE_INCONNUE'),
    ]) {
      await expectLater(m.pont.sms.envoyer(corps), throwsA(isA<Err>().having((x) => x.code, 'code', code)));
    }
    expect(depots(), isEmpty);
    expect(await m.pont.sms.journal(), isEmpty);
  });

  test('un SMS conforme part SIGNÉ, schéma fermé ; le journal de la mère garde le numéro MASQUÉ, jamais le texte ni le numéro', () async {
    await m.pont.sms.regler({'actif': true});
    final r = await m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte, 'modele': 'Rappel de rendez-vous', 'auteur': 'U-1'});
    expect(r['depose'], isTrue);
    final d = depots().single;
    expect(d.entetes['x-mere'], secret);
    expect(d.entetes['x-signature'], 'sha256=${PublicationIndicateurs.signer(secret, d.corps)}');
    final corps = jsonDecode(utf8.decode(d.corps)) as Map;
    expect(corps.keys, ['sms']);
    expect((corps['sms'] as Map).keys.toSet(), {'id', 'numero', 'texte'});
    final j = await m.pont.sms.journal();
    expect(j, hasLength(1));
    expect(j.single['statut'], 'en_attente');
    expect(j.single['numero_masque'], '+229 •••••••• 01');
    final brut = jsonEncode(j);
    expect(brut, isNot(contains('0100000001')));
    expect(brut, isNot(contains('rendez-vous a la clinique')));
  });

  test('un refus du relais (plafond) est NOMMÉ et inscrit au journal ; rien n’est réessayé en silence', () async {
    await m.pont.sms.regler({'actif': true});
    statutDepot = 429;
    await expectLater(m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte}), throwsA(isA<Err>().having((x) => x.code, 'code', 'plafond_atteint').having((x) => x.statut, 'statut', 429)));
    final j = await m.pont.sms.journal();
    expect(j.single['statut'], 'non_depose');
    expect(j.single['erreur'], 'plafond_atteint');
    expect(depots(), hasLength(1));
  });

  test('le suivi relève le statut au relais jusqu’à « envoyé »', () async {
    await m.pont.sms.regler({'actif': true});
    await m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte});
    expect(await m.pont.sms.suivre(), 0);
    statutSuivi = 'envoye';
    expect(await m.pont.sms.suivre(), 1);
    final e = (await m.pont.sms.journal()).single;
    expect(e['statut'], 'envoye');
    expect(e['envoye_le'], 1);
    final suivi = recus.where((r) => r.chemin == '/mere/sms/statuts').last;
    expect(suivi.entetes['x-signature'], 'sha256=${PublicationIndicateurs.signer(secret, suivi.corps)}');
    expect(await m.pont.sms.suivre(), 0, reason: 'plus rien en attente : aucune requête');
  });

  test('refermer la passerelle arrête tout dépôt', () async {
    await m.pont.sms.regler({'actif': true});
    await m.pont.sms.regler({'actif': false});
    await expectLater(m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte}), throwsA(isA<Err>()));
    await expectLater(m.pont.sms.regler({'actif': 'oui'}), throwsA(isA<Err>().having((x) => x.code, 'code', 'interrupteur_invalide')));
    expect(depots(), isEmpty);
  });
}
