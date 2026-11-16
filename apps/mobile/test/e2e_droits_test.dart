// BOUT EN BOUT (Direction, 10/11/2026) : la mère change un droit, le téléphone le VOIT à sa prochaine synchronisation, sans redémarrer. Le vrai moteur de
// l'application (`MoteurMobileSync`, qui tient sa base chiffrée et sa boucle) parle à un relais et à une mère qui sont de vrais processus (packages/sync/banc).
//
// La mère est celle du banc en Node par défaut ; SIGH_E2E_MERE=dart prend l'exécutable Dart de packages/sync_dart/build (construire.sh mere).
// SIGH_E2E=0 ou l'absence de Node saute le test, en le disant.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';
import 'package:sigh_sync/sigh_sync.dart';

import 'aide_mobile.dart';

final _racine = () {
  var d = Directory.current;
  while (!File('${d.path}/packages/sync/banc/run.js').existsSync()) {
    if (d.parent.path == d.path) return null;
    d = d.parent;
  }
  return d.path;
}();

Future<int> _portLibre() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

Future<Map<String, Object?>> _appel(String methode, String url, [Map<String, Object?>? corps, Map<String, String> entetes = const {}]) async {
  final c = HttpClient();
  try {
    final req = await c.openUrl(methode, Uri.parse(url));
    req.headers.contentType = ContentType.json;
    entetes.forEach(req.headers.set);
    if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
    final rep = await req.close();
    final t = await utf8.decoder.bind(rep).join();
    final j = t.isEmpty ? <String, Object?>{} : jsonDecode(t);
    return j is Map ? j.cast<String, Object?>() : {'liste': j};
  } finally {
    c.close(force: true);
  }
}

Future<void> _attendre(Future<bool> Function() cond, String quoi, {int secondes = 30}) async {
  final fin = DateTime.now().add(Duration(seconds: secondes));
  while (DateTime.now().isBefore(fin)) {
    try {
      if (await cond()) return;
    } catch (_) {/* on réessaie */}
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
  fail('délai dépassé : $quoi');
}

void main() {
  final saute = _racine == null
      ? 'dépôt introuvable'
      : (Platform.environment['SIGH_E2E'] == '0' ? 'SIGH_E2E=0' : (Process.runSync('node', ['--version']).exitCode != 0 ? 'Node absent' : null));
  final mereDart = Platform.environment['SIGH_E2E_MERE'] == 'dart';

  test('la mère change un droit : le téléphone le voit sans redémarrer ; il ne peut pas écrire rbac ; sa fonction vient du code de la mère', () async {
    final tmp = Directory.systemTemp.createTempSync('sigh-e2e-droits-');
    final procs = <Process>[];
    final moteurs = <MoteurMobileSync>[];
    final bruts = <Mobile>[];
    addTearDown(() {
      for (final m in moteurs) {
        m.arreter();
      }
      for (final p in procs) {
        p.kill(ProcessSignal.sigkill);
      }
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final banc = '$_racine/packages/sync/banc';
    final portRelais = await _portLibre(), portMere = await _portLibre();
    procs.add(await Process.start('node', ['--no-warnings', '$banc/relais.js', '--port=$portRelais', '--db=${tmp.path}/relais.sqlite', '--banc=1']));
    final argsMere = ['--port=$portMere', '--db=${tmp.path}/mere.sqlite', '--admin=admin-banc', '--relais=http://127.0.0.1:$portRelais', '--secret-relais=secret-mere'];
    if (mereDart) {
      final exe = '$_racine/packages/sync_dart/build/mere_bundle/bundle/bin/mere';
      expect(File(exe).existsSync(), isTrue, reason: 'exécutable Dart de la mère absent : lancer packages/sync_dart/construire.sh mere');
      procs.add(await Process.start(exe, argsMere));
    } else {
      procs.add(await Process.start('node', ['--no-warnings', '$banc/mere.js', ...argsMere]));
    }
    for (final p in procs) {
      p.stdout.drain<void>();
      p.stderr.drain<void>();
    }
    final mere = 'http://127.0.0.1:$portMere';
    final admin = {'x-admin': 'admin-banc'};
    await _attendre(() async => (await _appel('GET', '$mere/admin/etat', null, admin))['epoch'] != null, 'la mère répond');
    Future<Map<String, Object?>> adminPost(String chemin, Map<String, Object?> corps) => _appel('POST', '$mere$chemin', corps, admin);
    Future<Map<String, Object?>> poser(String fiche, Map<String, Object?> champs) => adminPost('/admin/referentiel', {'collection': 'rbac', 'fiche': fiche, 'champs': champs});
    Future<int> compte(String c) async => ((await _appel('GET', '$mere/admin/compte?collection=$c', null, admin))['n'] as num).toInt();

    // La mère a DÉJÀ ses droits avant que le téléphone existe (les fiches du jeu livré, une par rôle) : l'instantané les lui livre à la bienvenue (famille R, hors lot).
    final graine = graineDeTest();
    for (final f in graine.rbacLivre) {
      final r = await poser('${f['id']}', {...f});
      expect(r['statut'], 'acceptee', reason: '$r');
    }
    final r0 = await poser('RBAC26', {'droitsEcrans': {'m4-cpon': {'voir': false, 'editer': false, 'annuler': false}}});
    expect(r0['statut'], 'acceptee', reason: '$r0');

    // --- le téléphone : le moteur de l'application, appairé par un code de la mère (fonction : sage-femme) -------------------------------------
    final moteur = MoteurMobileSync.creer(dbChemin: '${tmp.path}/sf.sqlite', relais: 'http://127.0.0.1:$portRelais', graine: graineDeTest());
    moteurs.add(moteur);
    expect(moteur.droits.value.synchronises, isFalse, reason: 'avant la première synchronisation : droits d\'origine');
    expect(moteur.droits.value.matrice.recue, isFalse);
    final c = await adminPost('/admin/code-mobile', {'etiquette': 'SF', 'profil': 'soignant', 'fonction': 'sage_femme'});
    await moteur.appairer(code: '${c['code']}', cleClinique: '${c['cle']}', agent: 'Sage-femme de garde');
    expect(moteur.soignant, isNotNull);
    expect(moteur.soignant!.session.fonction, 'sage_femme', reason: 'la fonction vient de la mère');
    expect(moteur.droits.role, 'sage_femme');

    await _attendre(() async {
      await moteur.actualiser();
      return moteur.droits.value.synchronises;
    }, 'les droits de la mère arrivent');
    expect(moteur.droits.value.matrice.recue, isTrue, reason: 'les fiches de la mère font foi');
    expect(moteur.droits.peutVoir('cpon'), isFalse, reason: 'la CPoN était fermée AVANT l\'appairage : l\'instantané la porte');
    expect(moteur.droits.peutEditer('cpn'), isTrue);
    final premiereDate = moteur.droits.value.majLe!;

    // --- la mère change un droit : le téléphone le voit à sa prochaine synchronisation, SANS redémarrer ------------------------------------------
    final ecoute = <bool>[];
    moteur.droits.addListener(() => ecoute.add(moteur.droits.peutEditer('cpn')));
    await poser('RBAC26', {'droitsEcrans': {'m4-cpn': {'voir': true, 'editer': false, 'annuler': false}, 'm4-cpon': {'voir': true, 'editer': true, 'annuler': false}}});
    await _attendre(() async {
      await moteur.actualiser();
      return !moteur.droits.peutEditer('cpn');
    }, 'la CPN passe en lecture seule sur le téléphone');
    expect(moteur.droits.peutVoir('cpn'), isTrue, reason: 'lecture seule : l\'écran reste, la commande disparaît');
    expect(moteur.droits.peutVoir('cpon'), isTrue, reason: 'la CPoN a été rouverte par la même décision');
    expect(ecoute, isNotEmpty, reason: 'l\'interface est prévenue : elle se redessine d\'elle-même');
    expect(moteur.droits.value.majLe!.isAfter(premiereDate) || moteur.droits.value.majLe == premiereDate, isTrue);
    expect(moteur.soignant!.session.fonction, 'sage_femme');
    // Le service refuse le geste suivant, nommé.
    await expectLater(ServiceSuite.depuisSoignant(moteur.soignant!).enregistrerCpn('p', {}), throwsA(isA<RefusMobile>().having((r) => r.code, 'code', 'DROIT_RETIRE')));

    // --- la fonction ne vient JAMAIS du téléphone ni d'une fiche de droits -----------------------------------------------------------------------
    await poser('RBAC26', {'fonction': 'medecin', 'profil': 'reception'});
    await Future<void>.delayed(const Duration(seconds: 2));
    await moteur.actualiser();
    expect(moteur.soignant!.session.fonction, 'sage_femme');
    expect(moteur.droits.role, 'sage_femme');
    expect(moteur.profil, ProfilMobile.soignant);

    // --- le téléphone ne peut PAS écrire rbac (famille R) -----------------------------------------------------------------------------------------
    await expectLater(
        moteur.source.creer('rbac', {'role': 'sage_femme', 'droitsEcrans': {'m4-cpn': {'voir': true, 'editer': true, 'annuler': true}}}),
        throwsA(isA<RefusMobile>().having((r) => r.code, 'code', 'regle_sur_la_mere')));
    // Et si l'on contourne la garde du téléphone (opération brute dans la file), la MÈRE refuse : le droit n'est pas seulement à l'écran.
    final c2 = await adminPost('/admin/code-mobile', {'etiquette': 'SF2', 'profil': 'soignant', 'fonction': 'sage_femme'});
    final brut = Mobile(ConfigMobile(port: 0, relais: 'http://127.0.0.1:$portRelais', dbChemin: '${tmp.path}/brut.sqlite', nom: 'brut'));
    bruts.add(brut);
    final (st, _) = await brut.commande('POST /appairer', {'code': c2['code'], 'cle': c2['cle']}, const {});
    expect(st, 200);
    final avant = await compte('rbac');
    final op = brut.ecrire({'type': 'modifier', 'collection': 'rbac', 'fiche': 'RBAC26', 'champs': {'droitsEcrans': {'m4-cpn': {'voir': true, 'editer': true, 'annuler': true}}}});
    for (var i = 0; i < 200; i++) {
      await brut.cycle();
      final (_, e) = await brut.commande('GET /etat', const {}, const {});
      final refus = ((e! as Map)['a_traiter'] as List).cast<Map>();
      if (refus.any((x) => x['code'] == 'droit_refuse')) break;
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    final (_, etat) = await brut.commande('GET /etat', const {}, const {});
    expect(((etat! as Map)['a_traiter'] as List).any((x) => (x as Map)['id'] == op['id'] && x['code'] == 'droit_refuse'), isTrue, reason: 'la mère refuse en nommant');
    expect(await compte('rbac'), avant);
    // La mère n'a pas rendu la CPN : ce que la fiche disait reste vrai chez elle ET sur le téléphone.
    final f = await _appel('GET', '$mere/admin/fiche?collection=rbac&id=RBAC26', null, admin);
    expect((((f['data'] as Map)['droitsEcrans'] as Map)['m4-cpn'] as Map)['editer'], isFalse);
    await moteur.actualiser();
    expect(moteur.droits.peutEditer('cpn'), isFalse);
  }, skip: saute, timeout: const Timeout(Duration(seconds: 120)));
}
