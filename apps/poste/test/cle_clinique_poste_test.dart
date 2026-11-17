// La restauration de la clé de la clinique sur un poste neuf (décision 12, 17/11/2026) : l'empreinte est contrôlée AVANT acceptation, refus nommés, jamais la clé à l'écran ni au journal.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/cle_clinique_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_poste/sync/config_pair.dart';

final cle = List<int>.generate(32, (i) => (i * 9 + 4) % 256);
final hex = cle.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
Matcher refus(String code) => throwsA(isA<ErreurExport>().having((e) => e.code, 'code', code));

void main() {
  late Directory tmp;
  late Magasin m;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sigh-cle-');
    m = Magasin();
  });
  tearDown(() => tmp.deleteSync(recursive: true));
  ServiceCleClinique service({bool droit = true}) => ServiceCleClinique(magasin: m, dossierDonnees: tmp.path, peut: (g) => droit && g == gesteSystemeAdministrer);
  String empreinte() => cleEmpreinte(cle).substring(0, 8);

  test('depuis la copie sous scellé : acceptée si l’empreinte est reproduite ; rangée dans pair.json ; empreinte seule au journal', () async {
    final courte = await service().restaurer(texte: hex, empreinteAttendue: empreinte());
    expect(courte, empreinte().toUpperCase());
    expect(ConfigPairPoste.lireBrut(tmp.path)['cle'], hex);
    final trace = jsonEncode(m.collection('audit').toutes);
    expect(trace, contains(courte));
    expect(trace.contains(hex), isFalse, reason: 'la clé n’est JAMAIS journalisée');
    expect(trace.contains(base64.encode(cle)), isFalse);
    expect(await service().empreinteCourante(), courte);
  });

  test('depuis un fichier de sauvegarde de clé (format SGHK) : lu SANS écrire tant que l’empreinte n’est pas contrôlée', () async {
    final src = CleLocale('${tmp.path}/cle-poste.bin');
    await File('${tmp.path}/cle-poste.bin').writeAsString(base64.encode(cle));
    final fichier = await src.exporter('${tmp.path}/sauvegarde.cle', 'une phrase de passe assez longue');
    await expectLater(service().restaurer(fichier: fichier, phrase: 'une phrase de passe assez longue', empreinteAttendue: 'deadbeef'), refus('EMPREINTE_DIFFERENTE'));
    expect(File('${tmp.path}/pair.json').existsSync(), isFalse, reason: 'rien n’est écrit avant l’acceptation');
    await expectLater(service().restaurer(fichier: fichier, phrase: 'mauvaise phrase de passe longue', empreinteAttendue: empreinte()), refus('PHRASE_INCORRECTE'));
    await expectLater(service().restaurer(fichier: '${tmp.path}/absent.cle', phrase: 'x', empreinteAttendue: empreinte()), refus('FICHIER_CLE_INVALIDE'));
    await File('${tmp.path}/pasunecle.cle').writeAsString('n importe quoi, assez long pour passer la taille minimale du format');
    await expectLater(service().restaurer(fichier: '${tmp.path}/pasunecle.cle', phrase: 'x', empreinteAttendue: empreinte()), refus('FICHIER_CLE_INVALIDE'));
    expect(await service().restaurer(fichier: fichier, phrase: 'une phrase de passe assez longue', empreinteAttendue: empreinte()), empreinte().toUpperCase());
    expect(ConfigPairPoste.lireBrut(tmp.path)['cle'], hex);
  });

  test('refus nommés : droit, clé illisible, empreinte absente ou illisible ; aucun refus ne cite la clé', () async {
    await expectLater(service(droit: false).restaurer(texte: hex, empreinteAttendue: empreinte()), refus('GESTE_RESERVE'));
    await expectLater(service().restaurer(texte: 'pas une clé', empreinteAttendue: empreinte()), refus('CLE_ILLISIBLE'));
    await expectLater(service().restaurer(texte: hex, empreinteAttendue: ''), refus('EMPREINTE_ABSENTE'));
    await expectLater(service().restaurer(texte: hex, empreinteAttendue: 'zz'), refus('EMPREINTE_ILLISIBLE'));
    try {
      await service().restaurer(texte: hex, empreinteAttendue: 'deadbeef');
    } on ErreurExport catch (e) {
      expect('${e.refus.motif} ${e.refus.geste}'.contains(hex), isFalse);
    }
    expect(File('${tmp.path}/pair.json').existsSync(), isFalse);
  });

  test('une AUTRE clé déjà en service n’est pas écrasée sans confirmation ; confirmée, elle est remplacée', () async {
    final autre = List<int>.generate(32, (i) => (i * 3 + 7) % 256);
    final hexAutre = autre.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    ConfigPairPoste.ecrire(tmp.path, cleHex: hexAutre);
    await expectLater(service().restaurer(texte: hex, empreinteAttendue: empreinte()), refus('CLE_EN_SERVICE_DIFFERENTE'));
    expect(ConfigPairPoste.lireBrut(tmp.path)['cle'], hexAutre);
    await service().restaurer(texte: hex, empreinteAttendue: empreinte(), remplacer: true);
    expect(ConfigPairPoste.lireBrut(tmp.path)['cle'], hex);
    expect(jsonEncode(m.collection('audit').toutes).contains('"remplacee":true'), isTrue);
    // la même clé déjà en service : acceptée sans confirmation
    await service().restaurer(texte: hex, empreinteAttendue: empreinte());
  });
}
