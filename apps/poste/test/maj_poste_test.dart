// « Préparer la mise à jour » (décision 12, 17/11/2026) : sauvegarde vérifiée ET export vérifié de moins de N heures, N lu du réglage ; blocage nommé ; levée par geste réservé tracé ;
// fichier d'autorisation lu par l'installeur.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/base_portable_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/maj_poste.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_sync/sigh_sync.dart';

final cle = List<int>.generate(32, (i) => (i * 7 + 1) % 256);
Matcher refus(String code) => throwsA(isA<ErreurExport>().having((e) => e.code, 'code', code));

void main() {
  late Directory tmp;
  late DateTime maintenant;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sigh-maj-');
    maintenant = DateTime(2026, 11, 17, 8);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(Magasin, ServiceBasePortable, ServiceMiseAJour)> monter({String role = 'fileul', int heures = 24, bool Function(String)? peut, Mere? mere}) async {
    final m = Magasin({'patients': [{'id': 'P1', 'statut': 'actif', 'nom': 'X'}]}, 'POSTE');
    await m.brancherPersistance(PersistanceMemoire(), delai: Duration.zero);
    bool p(String g) => peut == null ? true : peut(g);
    final b = ServiceBasePortable(
        magasin: m, dossierDonnees: tmp.path, role: () => role, cleClinique: () async => cle, peut: p, mere: mere == null ? null : () => mere, horloge: () => maintenant);
    final s = ServiceMiseAJour(
        magasin: m, dossierDonnees: tmp.path, base: b, role: () => role, peut: p, versionCourante: '0.1.0', mere: mere == null ? null : () => mere, maxHeures: () => heures, horloge: () => maintenant);
    return (m, b, s);
  }

  test('sans aucune preuve : bloquée, avec les codes nommés ; l’installeur n’a rien à lire', () async {
    final (_, _, s) = await monter();
    expect(s.verdict().autorisee, isFalse);
    expect(s.verdict().refus.map((r) => r.code), containsAll(['SAUVEGARDE_ABSENTE', 'EXPORT_ABSENT']));
    expect(s.autorisation()?.code, 'AUTORISATION_ABSENTE');
  });

  test('FILEUL : préparer exporte, relit, autorise ; l’autorisation vaut quelques heures puis expire ; passé N heures, tout est à refaire', () async {
    final (m, _, s) = await monter();
    final v = await s.preparer();
    expect(v.autorisee, isTrue);
    expect(s.autorisation(), isNull);
    expect(Directory('${tmp.path}/exports').listSync().whereType<File>(), hasLength(1));
    expect(File('${tmp.path}/$majFichierAutorisation').readAsStringSync(), contains('levee=non'));
    expect(m.collection('audit').toutes.map((l) => l['action']), contains('Mise à jour préparée'));
    // l'autorisation expire (4 h)
    maintenant = maintenant.add(const Duration(hours: 5));
    expect(s.autorisation()?.code, 'AUTORISATION_EXPIREE');
    // et la sauvegarde elle-même est trop ancienne passé N heures : le verdict le dit, nommément
    maintenant = maintenant.add(const Duration(hours: 24));
    final v2 = s.verdict();
    expect(v2.refus.map((r) => r.code), containsAll(['SAUVEGARDE_TROP_ANCIENNE', 'EXPORT_TROP_ANCIEN']));
    // préparer refait ce qui est périmé
    expect((await s.preparer()).autorisee, isTrue);
    expect(Directory('${tmp.path}/exports').listSync().whereType<File>().length, greaterThanOrEqualTo(1));
  });

  test('N est le RÉGLAGE : 1 h périme une preuve de 2 h que 24 h acceptait (mêmes preuves, même dossier)', () async {
    final (m, b, s24) = await monter(heures: 24);
    await s24.preparer();
    maintenant = maintenant.add(const Duration(hours: 2));
    expect(s24.verdict().autorisee, isTrue);
    final s1 = ServiceMiseAJour(magasin: m, dossierDonnees: tmp.path, base: b, role: () => 'fileul', peut: (_) => true, versionCourante: '0.1.0', maxHeures: () => 1, horloge: () => maintenant);
    expect(s1.verdict().autorisee, isFalse);
    expect(s1.verdict().refus.map((r) => r.code), contains('EXPORT_TROP_ANCIEN'));
  });

  test('une préparation qui échoue RETIRE l’autorisation d’avant et nomme la cause', () async {
    final (m, _, s) = await monter();
    await s.preparer();
    expect(s.fichierAutorisation.existsSync(), isTrue);
    maintenant = maintenant.add(const Duration(hours: 30));
    final sansCle = ServiceBasePortable(magasin: m, dossierDonnees: tmp.path, role: () => 'fileul', cleClinique: () async => null, peut: (_) => true, horloge: () => maintenant);
    final s2 = ServiceMiseAJour(magasin: m, dossierDonnees: tmp.path, base: sansCle, role: () => 'fileul', peut: (_) => true, versionCourante: '0.1.0', horloge: () => maintenant);
    await expectLater(s2.preparer(), refus('CLE_ABSENTE'));
    expect(s2.fichierAutorisation.existsSync(), isFalse);
  });

  test('geste réservé : sans le droit d’exporter, on ne prépare pas', () async {
    final (_, _, s) = await monter(peut: (g) => g != gesteBaseExporter);
    await expectLater(s.preparer(), refus('GESTE_RESERVE'));
  });

  group('levée du blocage', () {
    test('sans le droit : refus nommé ; sans motif : refus nommé ; accordée : autorisation « levée », auteur et motif au journal', () async {
      final (m, _, sans) = await monter(peut: (g) => g != gesteMajLeverBlocage);
      expect(() => sans.lever(motif: 'panne totale du disque de sauvegarde'), refus('GESTE_RESERVE'));
      final (m2, _, s) = await monter();
      expect(() => s.lever(motif: 'court'), refus('MOTIF_OBLIGATOIRE'));
      expect(s.fichierAutorisation.existsSync(), isFalse);
      s.lever(motif: 'panne totale du disque de sauvegarde, correctif de sécurité urgent');
      expect(s.fichierAutorisation.readAsStringSync(), contains('levee=oui'));
      expect(s.autorisation(), isNull);
      final l = m2.collection('audit').toutes.firstWhere((l) => l['action'].toString().startsWith('Blocage de mise à jour levé'));
      expect(jsonEncode(l), contains('panne totale du disque'));
      expect(m.collection('audit').toutes.where((l) => l['action'].toString().startsWith('Blocage')), isEmpty);
    });
  });

  test('MÈRE : la sauvegarde chiffrée est faite ET relue, l’export contient le journal ; les deux preuves autorisent', () async {
    final cfg = ConfigMere(port: 0, dbChemin: '${tmp.path}/mere.db', admin: 'adm', cleBase64: base64.encode(cle), dossierSauvegardes: '${tmp.path}/sauv');
    final mere = await Mere.creer(cfg);
    addTearDown(mere.arreter);
    final (_, _, s) = await monter(role: 'mere', mere: mere);
    final v = await s.preparer();
    expect(v.autorisee, isTrue);
    expect(s.preuves.preuve('sauvegarde')!.verifiee, isTrue);
    expect(s.preuves.preuve('export')!.verifiee, isTrue);
    expect(Directory('${tmp.path}/sauv').listSync().whereType<File>().any((f) => f.path.endsWith('.enc')), isTrue);
    // sauvegarde altérée : la relecture la refuse, la préparation reste bloquée
    final enc = Directory('${tmp.path}/sauv').listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.enc'));
    final b = enc.readAsBytesSync();
    b[b.length ~/ 2] ^= 0xff;
    enc.writeAsBytesSync(b);
    expect((await mere.verifierDerniereSauvegarde())['ok'], isFalse);
  });
}
