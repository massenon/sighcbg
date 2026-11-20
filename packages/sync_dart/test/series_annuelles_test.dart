import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart' show anneeCreationDossier, codePatient;
import 'package:sigh_sync/src/depot.dart';
import 'package:sigh_sync/src/fileul.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:sigh_sync/src/mobile.dart';
import 'package:test/test.dart';

/// RG-01, lot 0 (E3830) : l'année d'un code de dossier attribué par la synchronisation est celle de la CRÉATION du dossier, jamais celle du jour de la
/// synchronisation, et la série repart au changement d'année. Un dossier créé le 31/12/2026 et un le 01/01/2027, sur la mère, un fileul et un téléphone.
void main() {
  var n = 0;
  Map<String, Object?> creation(Map<String, Object?> champs, {int? hlc}) =>
      {'id': 'op-${n++}', 'collection': 'patients', 'fiche': 'PAT-${n++}', 'type': 'creer', 'hlc': hlc ?? DateTime.now().millisecondsSinceEpoch, 'champs': champs};
  String annee(Object? code) => '$code'.split('/')[2];
  int rang(Object? code) => int.parse('$code'.split('/')[1]);
  final fileul = Appareil('F1', 'fileul');

  group('domaine : l’année de création', () {
    test('la date de création écrite fait foi ; à défaut, l’horloge LOCALE du geste', () {
      final minuitPasse = DateTime(2027, 1, 1, 0, 30).millisecondsSinceEpoch;
      expect(anneeCreationDossier('2026-12-31', minuitPasse), 2026);
      expect(anneeCreationDossier('2026-12-31T23:59:00', minuitPasse), 2026);
      expect(anneeCreationDossier(null, minuitPasse), 2027, reason: 'le 1er janvier à 00 h 30 (heure locale) est en 2027');
      expect(anneeCreationDossier('', DateTime(2026, 12, 31, 23, 59).millisecondsSinceEpoch), 2026);
      expect(anneeCreationDossier('illisible', DateTime(2026, 12, 31, 23, 59).millisecondsSinceEpoch), 2026);
    });
  });

  group('mère', () {
    late Mere m;
    setUp(() async => m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:')));

    test('une base neuve ouvre la série de l’année en cours à 1000, comme avant ; les autres années repartent à 1', () async {
      expect(await m.base.meta('next_patient'), isNull, reason: 'plus de compteur unique');
      expect(await m.base.meta(Mere.cleSeriePatients(DateTime.now().year)), '1000');
      final a = DateTime.now().year + 1;
      final p = await m.allouerPlage('F1', 'patients', 5, 0, annee: a);
      expect(p, {'debut': 1, 'fin': 5, 'annee': a});
    });

    test('dossiers PROVISOIRES du 31/12/2026 et du 01/01/2027 synchronisés plus tard : chacun dans la série de SON année', () async {
      final r1 = await m.traiter(creation({'nom': 'VEILLE', 'dateCreation': '2026-12-31', 'code': 'PROV-1'}), fileul);
      final r2 = await m.traiter(creation({'nom': 'LENDEMAIN', 'dateCreation': '2027-01-01', 'code': 'PROV-2'}), fileul);
      final r3 = await m.traiter(creation({'nom': 'LENDEMAIN-BIS', 'dateCreation': '2027-01-01'}), fileul);
      // Sans date de création écrite : l'horloge du geste (31/12/2026 23 h 59, heure locale).
      final r4 = await m.traiter(creation({'nom': 'HORLOGE'}, hlc: DateTime(2026, 12, 31, 23, 59).millisecondsSinceEpoch), fileul);
      for (final r in [r1, r2, r3, r4]) {
        expect(r['statut'], 'acceptee', reason: '$r');
      }
      expect(annee(r1['numero']), '26');
      expect(annee(r2['numero']), '27');
      expect(annee(r3['numero']), '27');
      expect(annee(r4['numero']), '26');
      expect(rang(r3['numero']), rang(r2['numero']) + 1, reason: 'la série 2027 se suit');
      expect(rang(r4['numero']), rang(r1['numero']) + 1, reason: 'la série 2026 se suit, sans être touchée par 2027');
      if (DateTime.now().year != 2027) expect(rang(r2['numero']), 1, reason: 'la série 2027 repart à 1');
    });

    test('une plage appartient à UNE année : son rang ne code pas un dossier d’une autre année ; la mère elle-même n’est pas contrainte', () async {
      final p = await m.allouerPlage('F1', 'patients', 3, 0, annee: 2026);
      expect(p['annee'], 2026);
      final ok = await m.traiter(creation({'nom': 'A', 'dateCreation': '2026-12-31', 'code': codePatient(p['debut']!, 2026)}), fileul);
      expect(ok['statut'], 'acceptee');
      final ko = await m.traiter(creation({'nom': 'B', 'dateCreation': '2027-01-01', 'code': codePatient(p['fin']!, 2027)}), fileul);
      expect(ko['code'], 'numero_hors_plage');
      // Un rang déjà pris par la mère n'entraîne jamais le refus d'un provisoire : il est sauté.
      final suivant = int.parse((await m.base.meta(Mere.cleSeriePatients(2026)))!);
      final mere = await m.traiter(creation({'nom': 'C', 'code': codePatient(suivant, 2026)}), Appareil('mere', 'mere'));
      expect(mere['statut'], 'acceptee');
      final prov = await m.traiter(creation({'nom': 'D', 'dateCreation': '2026-12-31', 'code': 'PROV-3'}), fileul);
      expect(prov['statut'], 'acceptee');
      expect(prov['numero'], codePatient(suivant + 1, 2026));
    });

    test('la série d’une année neuve commence au-dessus des codes de cette année que la mère détient déjà', () async {
      await m.traiter(creation({'nom': 'ANCIEN', 'code': codePatient(41, 2028)}), Appareil('mere', 'mere'));
      final p = await m.allouerPlage('F1', 'patients', 2, 0, annee: 2028);
      expect(p['debut'], 42);
      final q = await m.allouerPlage('F2', 'patients', 2, 50, annee: 2028);
      expect(q['debut'], 50, reason: 'le minimum du poste demandeur est respecté');
    });
  });

  test('MIGRATION : l’ancien compteur unique devient celui de l’année en cours, les plages sans année lui sont rattachées', () async {
    final dir = await Directory.systemTemp.createTemp('sigh-series-');
    final chemin = '${dir.path}/mere.sqlite';
    try {
      final d = await Depot.ouvrir(chemin, '');
      await d.initialiser('CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT); CREATE TABLE IF NOT EXISTS plages (appareil TEXT, nom TEXT, debut BIGINT, fin BIGINT)');
      await d.poserMeta('next_patient', 1250);
      await d.exec('INSERT INTO plages(appareil,nom,debut,fin) VALUES(?,?,?,?)', ['F1', 'patients', 1200, 1249]);
      await d.exec('INSERT INTO plages(appareil,nom,debut,fin) VALUES(?,?,?,?)', ['F1', 'besoins', 1, 50]);
      await d.fermer();
      final m = await Mere.creer(ConfigMere(port: 0, dbChemin: chemin));
      final an = DateTime.now().year;
      expect(await m.base.meta('next_patient'), isNull);
      expect(await m.base.meta(Mere.cleSeriePatients(an)), '1250', reason: 'la série en cours continue : aucun code réattribué');
      final r = await m.traiter(creation({'nom': 'X', 'code': codePatient(1210, an)}), fileul);
      expect(r['statut'], 'acceptee', reason: 'une plage d’avant le lot 0 reste valable pour l’année en cours : $r');
      expect((await m.base.select("SELECT annee FROM plages WHERE nom='besoins'")).single['annee'], isNull, reason: 'les autres séries ne sont pas touchées');
      await m.base.fermer();
      // Une seconde ouverture ne refait pas la migration.
      final m2 = await Mere.creer(ConfigMere(port: 0, dbChemin: chemin));
      expect(await m2.base.meta(Mere.cleSeriePatients(an)), '1250');
      await m2.base.fermer();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  group('fileul', () {
    Fileul poste() => Fileul(ConfigFileul(port: 0, mere: 'http://127.0.0.1:1', dbChemin: ':memory:'));

    test('la plage 2026 code le dossier du 31/12/2026 ; le dossier du 01/01/2027 reçoit un provisoire', () {
      final f = poste();
      f.base.exec("INSERT INTO plage(nom,prochain,fin,annee) VALUES('patients',10,12,2026)");
      final a = f.ecrire({'type': 'creer', 'collection': 'patients', 'champs': {'nom': 'VEILLE', 'dateCreation': '2026-12-31'}});
      final b = f.ecrire({'type': 'creer', 'collection': 'patients', 'champs': {'nom': 'LENDEMAIN', 'dateCreation': '2027-01-01'}});
      expect((a['champs']! as Map)['code'], codePatient(10, 2026));
      expect('${(b['champs']! as Map)['code']}', startsWith('PROV-'));
    });

    test('une plage d’avant le lot 0 (sans année) ne code plus rien : provisoire, jamais une année devinée', () {
      final f = poste();
      f.base.exec("INSERT INTO plage(nom,prochain,fin) VALUES('patients',10,12)");
      final a = f.ecrire({'type': 'creer', 'collection': 'patients', 'champs': {'nom': 'X'}});
      expect('${(a['champs']! as Map)['code']}', startsWith('PROV-'));
    });
  });

  group('téléphone', () {
    Mobile tel() => Mobile(ConfigMobile(port: 0, relais: 'http://127.0.0.1:1', dbChemin: ':memory:'));

    test('la plage de l’appairage (2026) code le dossier du 31/12/2026 ; celui du 01/01/2027 reçoit un provisoire', () {
      final t = tel();
      t.recevoir({'type': 'bienvenue', 'epoch': 1, 'plage': {'debut': 1003, 'fin': 1022, 'annee': 2026}, 'profil': 'reception'});
      final a = t.ecrire({'type': 'creer', 'collection': 'patients', 'champs': {'nom': 'VEILLE', 'dateCreation': '2026-12-31'}});
      final b = t.ecrire({'type': 'creer', 'collection': 'patients', 'champs': {'nom': 'LENDEMAIN', 'dateCreation': '2027-01-01'}});
      expect((a['champs']! as Map)['code'], codePatient(1003, 2026));
      expect('${(b['champs']! as Map)['code']}', startsWith('PROV-'));
    });

    test('une plage reçue avant le lot 0 (sans année) ne code plus rien', () {
      final t = tel();
      t.recevoir({'type': 'bienvenue', 'epoch': 1, 'plage': {'debut': 1003, 'fin': 1022}, 'profil': 'reception'});
      final a = t.ecrire({'type': 'creer', 'collection': 'patients', 'champs': {'nom': 'X'}});
      expect('${(a['champs']! as Map)['code']}', startsWith('PROV-'));
    });
  });
}
