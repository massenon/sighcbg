// La DURÉE DE VALIDITÉ d'un code d'appairage est un RÉGLAGE de la mère (Direction de Baguidi, 18/11/2026 : « plus de valeur en dur ») : daté, borné, relu à chaque émission, rendu avec
// le code (`validite_s`, `expire`) pour un poste ordinaire COMME pour un mobile. Aucun écran n'écrit « 15 minutes ».
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sigh-validite-'));
  tearDown(() => tmp.deleteSync(recursive: true));

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
    return {'statut': rep.statusCode, if (j is Map) ...j.cast<String, Object?>()};
  }

  /// Une version du réglage, écrite comme la mère la reçoit (fiche de la collection `parametres`).
  Future<void> regler(Mere m, Object? valeur, String effet, int version, {String statut = 'actif'}) async {
    final d = definitionDeParametre(cleValiditeCodeAppairage)!;
    final v = Parametre(cle: cleValiditeCodeAppairage, famille: d.famille, type: d.type, valeur: valeur, defaut: d.defaut, dateEffet: effet, version: version, auteur: 'Test', motif: 'essai', creeLe: '2026-11-17T08:00:00.000')
        .toJson();
    await m.base.exec('INSERT INTO fiches(collection,id,data,fieldseq,archive) VALUES(?,?,?,?,?)',
        [parCollectionParametres, '$cleValiditeCodeAppairage@$effet@$version', jsonEncode({...v, 'statut': statut}), '{}', statut == 'archive' ? 1 : 0]);
  }

  // Un relais minimal : il accepte tout et garde ce que la mère lui déclare (l'empreinte d'un code de mobile et SON ÉCHÉANCE).
  final declares = <Map<String, Object?>>[];
  late HttpServer relais;
  setUp(() async {
    declares.clear();
    relais = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    relais.listen((req) async {
      final texte = await utf8.decoder.bind(req).join();
      if (req.uri.path == '/mere/code') declares.add((jsonDecode(texte) as Map).cast<String, Object?>());
      req.response.headers.contentType = ContentType.json;
      req.response.write('{}');
      await req.response.close();
    });
  });
  tearDown(() => relais.close(force: true));

  Future<(Mere, String)> mere({int? codeTtl}) async {
    final m = await Mere.creer(ConfigMere(
        port: 0, dbChemin: ':memory:', admin: 'adm', dossierSauvegardes: '${tmp.path}/sauv${codeTtl ?? ''}', codeTtl: codeTtl, relais: 'http://127.0.0.1:${relais.port}'));
    await m.demarrer();
    return (m, 'http://127.0.0.1:${m.portEcoute}');
  }

  test('sans réglage posé : la valeur d’attente de la définition, annoncée avec le code (poste ordinaire, mobile, reprise)', () async {
    final (m, base) = await mere();
    final attendu = seuilSeme(cleValiditeCodeAppairage) * 60;
    final poste = await http(base, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'P'});
    expect(poste['validite_s'], attendu);
    expect(poste['expire'], isA<int>());
    final mobile = await http(base, 'POST', '/admin/code-mobile', {'etiquette': 'T', 'profil': 'reception'});
    expect(mobile['validite_s'], attendu, reason: 'le code mobile annonce lui aussi sa durée');
    expect(mobile['expire'], isA<int>());
    expect(mobile['cle'], isA<String>());
    expect(declares.single['expire_le'], mobile['expire'], reason: 'le relais reçoit la MÊME échéance que celle annoncée à la console');
    await m.arreter();
  });

  test('le réglage est LU à chaque émission : une version datée d’aujourd’hui change la durée, le code déjà émis garde son échéance', () async {
    final (m, base) = await mere();
    final avant = await http(base, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'A'});
    await regler(m, 30, '2000-01-01', 1);
    final apres = await http(base, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'B'});
    expect(apres['validite_s'], 30 * 60);
    expect((apres['expire'] as int) - DateTime.now().millisecondsSinceEpoch, inInclusiveRange(30 * 60 * 1000 - 5000, 30 * 60 * 1000));
    expect(avant['validite_s'], seuilSeme(cleValiditeCodeAppairage) * 60);
    expect((await http(base, 'POST', '/admin/code-mobile', {'etiquette': 'T', 'profil': 'reception'}))['validite_s'], 30 * 60);
    final reprise = await http(base, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'C'});
    expect(reprise['validite_s'], 30 * 60);
    await m.arreter();
  });

  test('daté : une version à venir ne s’applique pas encore ; une version archivée ne compte pas (RG-14)', () async {
    final (m, base) = await mere();
    await regler(m, 45, '2999-01-01', 1);
    await regler(m, 90, '2000-01-01', 2, statut: 'archive');
    final r = await http(base, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'P'});
    expect(r['validite_s'], seuilSeme(cleValiditeCodeAppairage) * 60);
    await m.arreter();
  });

  test('borné : hors des bornes de la définition, la valeur d’attente — jamais zéro, jamais une durée absurde', () async {
    final (m, base) = await mere();
    final d = definitionDeParametre(cleValiditeCodeAppairage)!;
    await regler(m, d.max! + 1, '2000-01-01', 1);
    expect((await http(base, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'P'}))['validite_s'], seuilSeme(cleValiditeCodeAppairage) * 60);
    await regler(m, 0, '2000-01-02', 2);
    expect((await http(base, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'Q'}))['validite_s'], seuilSeme(cleValiditeCodeAppairage) * 60);
    await m.arreter();
  });

  test('la surcharge de lancement (`--code-ttl`, bancs) l’emporte sur le réglage et reste annoncée', () async {
    final (m, base) = await mere(codeTtl: 300);
    await regler(m, 60, '2000-01-01', 1);
    final r = await http(base, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'P'});
    expect(r['validite_s'], 0, reason: '300 ms annoncés en secondes entières');
    await m.arreter();
  });

  test('un code expiré à l’échéance annoncée est refusé (le réglage décide vraiment, il n’est pas seulement affiché)', () async {
    final (m, base) = await mere(codeTtl: 200);
    final code = (await http(base, 'POST', '/admin/code', {'role': 'fileul', 'etiquette': 'P'}))['code'];
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final r = await http(base, 'POST', '/appairage', {'code': code, 'uuid': 'x'});
    expect(r['code'], 'code_expire');
    await m.arreter();
  });
}
