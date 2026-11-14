import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/mere/activation.dart' show ServiceMereLocal;
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/mere/mrb_source.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// Les écrans du lot (b) contre le VRAI service de la mère (`packages/sync_dart`, SQLite en mémoire) et un relais factice qui ENREGISTRE ce qu'on lui
/// dépose. Deux preuves qu'aucun faux ne peut donner :
///  1. ce que l'adaptateur lit est ce que le moteur répond réellement (champs, formes, refus) ;
///  2. le relais est OPAQUE : ce qui part est du chiffré (aucun nom de patient, aucun nom de collection, jamais la clé), et les indicateurs publiés
///     sont exactement la liste fermée `mrbChampsPublies`.
final cleBase64 = base64.encode(List<int>.generate(32, (i) => 7 * i + 3)); // 32 octets, comme la vraie clé AES-256
const adminSecret = 'admin-test';

class RelaisEspion {
  late HttpServer serveur;
  final depots = <Map<String, Object?>>[];
  final indicateurs = <Map<String, Object?>>[];
  final chemins = <String>[];

  Future<void> demarrer() async {
    serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serveur.listen((req) async {
      final corps = await utf8.decoder.bind(req).join();
      chemins.add('${req.method} ${req.uri.path}');
      Object reponse = <String, Object?>{};
      if (req.uri.path == '/depot') depots.add((jsonDecode(corps) as Map).cast<String, Object?>());
      if (req.uri.path == '/mere/indicateurs') indicateurs.add((jsonDecode(corps) as Map).cast<String, Object?>());
      if (req.uri.path == '/mere/appareils') reponse = {'appareils': []};
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(reponse));
      await req.response.close();
    });
  }

  String get url => 'http://127.0.0.1:${serveur.port}';
  Future<void> arreter() => serveur.close(force: true);
}

Future<void> attendre(bool Function() condition, {Duration delai = const Duration(seconds: 8), String Function()? raison}) async {
  final fin = DateTime.now().add(delai);
  while (!condition()) {
    if (DateTime.now().isAfter(fin)) fail('condition jamais atteinte${raison == null ? '' : ' : ${raison()}'}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  test('adaptateur contre le vrai service : état, supervision, journal, compte, réinitialisation, et relais opaque', () async {
    final relais = RelaisEspion();
    await relais.demarrer();
    const port = 19461;
    final dossier = Directory.systemTemp.createTempSync('sigh-mrb-');
    final mere = ServiceMereLocal(ConfigMere(
        port: port,
        dbChemin: ':memory:',
        admin: adminSecret,
        relais: relais.url,
        cleBase64: cleBase64,
        dossierSauvegardes: dossier.path));
    await mere.demarrer();
    addTearDown(() async {
      await mere.arreter();
      await relais.arreter();
      dossier.deleteSync(recursive: true);
    });

    final client = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: adminSecret);
    final s = MrbSourceClient(client);

    // 1. Une fiche patient écrite par la mère : son nom ne doit JAMAIS apparaître chez le relais.
    final r = await http.post(Uri.parse('http://127.0.0.1:$port/admin/referentiel'),
        headers: {'x-admin': adminSecret, 'content-type': 'application/json'},
        body: jsonEncode({'collection': 'patients', 'fiche': 'p1', 'champs': {'nom': 'KOPEGOU Azemidia', 'telephone': '97000000'}}));
    expect(r.statusCode, 200, reason: r.body);

    // 2. Ce que le moteur expose, tel que l'adaptateur le lit.
    var etat = await s.etat();
    expect(etat.epoch, 1);
    expect(etat.seqMax, greaterThan(0));
    expect(etat.depot, 'sqlite');
    expect(etat.repN, isNotNull, reason: 'rep_n est annoncé par le moteur');
    expect(etat.reinitOuverte, isFalse);
    expect(await s.patientsActifs(), 1);
    final sante = await s.supervision();
    expect(sante.controle('Base de données')!.etat, 'ok');
    expect(sante.controle('Sauvegarde')!.etat, 'alerte', reason: 'aucune sauvegarde faite : le moteur le dit, la console ne l’adoucit pas');
    expect(sante.controle('Relais en ligne'), isNotNull);

    // 3. Le relais reçoit le journal, CHIFFRÉ. Preuve d'opacité sur les corps réellement expédiés.
    await attendre(() => relais.depots.isNotEmpty && relais.indicateurs.isNotEmpty, raison: () => 'chemins reçus par le relais : ${relais.chemins.toSet()}');
    for (final corps in relais.depots) {
      expect(mrbDefautsOpacite(corps, interdits: ['KOPEGOU', 'Azemidia', '97000000', 'patients', 'telephone', cleBase64]), isEmpty,
          reason: 'ce qui part au relais doit être du chiffré : ${jsonEncode(corps)}');
    }
    final enveloppe = (relais.depots.first['enveloppe']! as Map);
    expect(base64.decode(enveloppe['ct']! as String).length, greaterThan(16), reason: 'charge chiffrée + marque d’authentification');
    expect(enveloppe['dir'], 'journal');

    // 4. Les indicateurs publiés : liste fermée, valeurs numériques, aucun nom.
    final publie = ((relais.indicateurs.last['indicateurs']) as Map).cast<String, Object?>();
    expect(publie.keys.toList(), [...mrbChampsPublies, ...mrbChampsStructures], reason: 'lot RLS-SYNC : les compteurs, puis le tableau des fileuls (compteurs et horodatages)');
    expect(publie['fileuls'], isA<List>());
    expect(mrbVerifierIndicateurs(publie).sansDonneeDeSante, isTrue);
    expect(jsonEncode(relais.indicateurs), isNot(contains('KOPEGOU')));
    expect(publie['patients_actifs'], 1, reason: 'l’aperçu de l’écran calcule la même valeur par /admin/compte');

    // 5. La réplication rattrape son retard : le compteur d'enveloppes avance.
    await attendre(() => relais.depots.length >= 1);
    etat = await s.etat();
    expect(etat.repN, greaterThan(0));

    // 6. Sauvegarde chiffrée à la demande.
    final fichier = await s.sauvegarderMaintenant();
    expect(fichier, endsWith('.enc'));
    expect(File(fichier).existsSync(), isTrue);
    final claire = File(fichier).readAsBytesSync();
    expect(utf8.decode(claire, allowMalformed: true), isNot(contains('KOPEGOU')), reason: 'la sauvegarde est chiffrée avec la clé de clinique');
    final sante2 = await s.supervision();
    expect(sante2.controle('Sauvegarde')!.etat, 'ok');
    expect(sante2.controle('Sauvegarde')!.valeur, isA<num>(), reason: 'la date de la dernière sauvegarde vient de la supervision');

    // 7. QR mobile : le code et la clé sortent par la seule route prévue.
    final mobile = await s.codeMobile('Dr Yoro', profil: 'soignant', fonction: 'medecin');
    expect(mobile.code, hasLength(8));
    expect(mobile.payloadQr, contains(cleBase64));
    expect(relais.chemins, contains('POST /mere/code'), reason: 'seul le HACHÉ du code est déclaré au relais');

    // 8. Réinitialisation : fermée par défaut, gardes nommées par le moteur, trace au journal.
    await expectLater(s.reinitialiser(confirmation: 'NASSIERA TOO', second: 'Mme TACHEDI'),
        throwsA(isA<ErreurMere>().having((e) => e.code, 'code', 'reinit_fermee')));
    await s.ouvrirFenetreReinit(true);
    expect((await s.etat()).reinitOuverte, isTrue);
    await expectLater(s.reinitialiser(confirmation: 'autre nom', second: 'Mme TACHEDI'),
        throwsA(isA<ErreurMere>().having((e) => e.code, 'code', 'confirmation_invalide')));
    await expectLater(s.reinitialiser(confirmation: s.nomClinique, second: ''),
        throwsA(isA<ErreurMere>().having((e) => e.code, 'code', 'second_profil_requis')));
    // D6 (09/11/2026) : le défaut ARCHIVE. Sans motif : refusé, nommé. Avec motif : la fiche passe à l'état archivé, rien n'est supprimé, l'époque ne bouge pas.
    await expectLater(s.reinitialiser(confirmation: s.nomClinique, second: 'Mme TACHEDI'),
        throwsA(isA<ErreurMere>().having((e) => e.code, 'code', 'motif_requis')));
    final archive = await s.reinitialiser(confirmation: s.nomClinique, second: 'Mme TACHEDI', motif: 'Mise en production');
    expect(archive.sauvegarde, isNotEmpty);
    expect(archive.mode, 'archiver');
    expect(archive.epoch, 1, reason: 'archiver n’est pas purger : l’époque ne change pas, les postes n’ont rien à resynchroniser');
    expect(archive.archivees['patients'], 1);
    expect(archive.totalArchivees, 1);
    expect(await s.patientsActifs(), 0, reason: 'la fiche est archivée, donc plus active');
    final liste = await http.get(Uri.parse('http://127.0.0.1:$port/admin/liste?collection=patients'), headers: {'x-admin': adminSecret});
    final fiches = jsonDecode(liste.body) as List;
    expect(fiches, hasLength(1), reason: 'RG-14 : la fiche existe toujours');
    expect((fiches.single as Map)['archive'], isTrue);
    expect(((fiches.single as Map)['data'] as Map)['_motifArchivage'], 'Jeu de démonstration, mise en production');
    expect(((fiches.single as Map)['data'] as Map)['nom'], 'KOPEGOU Azemidia', reason: 'le contenu est intact');
    expect((await s.etat()).reinitOuverte, isFalse, reason: 'la fenêtre se referme avec le geste');
    final journal = await s.journal(limite: 50);
    expect(journal.any((l) => l.message.startsWith('Archivage du jeu de démonstration') && l.niveau == 'alerte'), isTrue);
    // Une fiche archivée par la mère se RESTAURE par l'opération `restaurer` du journal (le pont du poste l'émet depuis la Corbeille).
    final restauree = await http.post(Uri.parse('http://127.0.0.1:$port/admin/referentiel'),
        headers: {'x-admin': adminSecret, 'content-type': 'application/json'}, body: jsonEncode({'collection': 'patients', 'fiche': 'p1', 'type': 'restaurer', 'champs': {}}));
    expect(restauree.statusCode, 200, reason: restauree.body);
    expect(await s.patientsActifs(), 1, reason: 'restaurée : de nouveau active');
    // La suppression physique a sa porte : fenêtre rouverte, confirmation explicite, époque + 1.
    await s.ouvrirFenetreReinit(true);
    final ouvertes = await http.post(Uri.parse('http://127.0.0.1:$port/admin/reinitialiser'),
        headers: {'x-admin': adminSecret, 'content-type': 'application/json'}, body: jsonEncode({'confirmation': s.nomClinique, 'second': 'X', 'mode': 'supprimer'}));
    expect(ouvertes.statusCode, 422, reason: 'sans suppression_physique: true, jamais de vidage');
    expect((jsonDecode(ouvertes.body) as Map)['code'], 'suppression_physique_non_confirmee');
    final fait = await s.reinitialiser(confirmation: s.nomClinique, second: 'Mme TACHEDI', supprimer: true);
    expect(fait.sauvegarde, isNotEmpty);
    expect(fait.mode, 'supprimer');
    expect(fait.epoch, 2, reason: 'la suppression physique incrémente l’époque');
    expect((jsonDecode((await http.get(Uri.parse('http://127.0.0.1:$port/admin/liste?collection=patients'), headers: {'x-admin': adminSecret})).body) as List), isEmpty);
    expect((await s.etat()).reinitOuverte, isFalse);
    final journal2 = await s.journal(limite: 50);
    expect(journal2.any((l) => l.message.startsWith('Réinitialisation') && l.niveau == 'alerte'), isTrue);

    // 9. Même après tout cela, rien d'identifiant n'est parti chez le relais.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    for (final corps in relais.depots) {
      expect(mrbDefautsOpacite(corps, interdits: ['KOPEGOU', 'patients', cleBase64]), isEmpty);
    }
    expect(jsonEncode(relais.depots) + jsonEncode(relais.indicateurs), isNot(contains(cleBase64)), reason: 'la clé n’est jamais envoyée au relais');
  });
}
