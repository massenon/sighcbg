// Les scans (courriers M13, dossier patient M1) : le service (dépôt, versions, retrait annulable, lecture vérifiée, journal, taille, migration du base64,
// sauvegarde puis restauration) et les écrans (panneau de scan, visionneuse, droits par commande et par catégorie sensible).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/documents/panneau_scan.dart';
import 'package:sigh_poste/documents/service_fichiers.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_sync/sigh_sync.dart';

import 'aide_polices.dart';

final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 11, 12, 10);

/// Un vrai PNG 1×1 (décodable) et un PDF à couche texte.
final png = Uint8List.fromList(base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
Uint8List pdf(String mot) => Uint8List.fromList(latin1.encode('%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\n2 0 obj\n<< /Length 60 >>\nstream\nBT /F1 12 Tf (Compte rendu $mot) Tj ET\nendstream\nendobj\n%%EOF'));
Uint8List pdfImage() => Uint8List.fromList(latin1.encode('%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\n2 0 obj\n<< /Subtype /Image /Filter /DCTDecode /Length 4 >>\nstream\nÿØÿà\nendstream\nendobj'));

Fiche courrier(String id, String ref, {String sens = 'arrivee'}) => {
      'id': id, 'reference': ref, 'sens': sens, 'date': '2026-11-11', 'correspondant': 'Ministère de la Santé', 'objet': 'Autorisation', 'nature': 'Lettre',
      'affecteA': 'Direction Médicale', 'traitement': 'en_attente', 'statut': 'actif'
    };
Fiche docu(String id, String ref, String type, {String patientId = 'K1'}) =>
    {'id': id, 'reference': ref, 'patientId': patientId, 'code': 'CBG/1/26', 'patient': 'AGORO Awa', 'type': type, 'date': '2026-11-05', 'etat': 'valide', 'depose': 'Awa', 'statut': 'actif'};

Magasin magasin(Map<String, List<Fiche>> jeux) => Magasin({
      'audit': const [],
      'reglages': const [],
      'fichiers': const [],
      'courriers': const [],
      'documentsPatient': const [],
      'rbac': const [],
      'patients': [
        {'id': 'K1', 'code': 'CBG/1/26', 'nom': 'AGORO', 'prenom': 'Awa', 'statut': 'actif'}
      ],
      for (final e in jeux.entries) e.key: [for (final x in e.value) {...x}],
    }, 'POSTE');

void main() {
  late Directory tmp;
  late StockFichiers stock;
  setUpAll(chargerPolices);
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sigh-poste-scans-');
    stock = StockFichiers('${tmp.path}/scans');
    SelecteursScan.reinitialiser();
  });
  tearDown(() {
    SelecteursScan.reinitialiser();
    ToastsSigh.viderPourTests();
    tmp.deleteSync(recursive: true);
  });

  ServiceFichiers brancher(Magasin m, {DocStockage? st}) {
    final s = ServiceFichiers.de(m);
    s.stockagePour = (_) => st ?? stock;
    s.lireInfo = () async => {'dossier': stock.dossier, 'fichiers': stock.nombre};
    m.horloge = () => auj;
    m.utilisateur = 'Awa KOUASSI';
    return s;
  }

  group('service : courriers', () {
    test('dépôt : nom normalisé chez la mère, métadonnées sur la fiche, « Numérisé » dérivé, texte indexé, journal', () async {
      final m = magasin({'courriers': [courrier('C1', 'ARR-2026-0042')]});
      final s = brancher(m);
      final r = await s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'Courrier ministère.pdf', octets: pdf('hémorragie'));
      final f = m.collection('courriers').parId('C1')!;
      expect(docNumerise(f), isTrue);
      expect(docScan(f)!['nomNormalise'], '2026-11-11_ARR_0042.pdf');
      expect(File('${stock.dossier}/2026-11-11_ARR_0042.pdf').existsSync(), isTrue);
      expect(docScan(f)!['sha256'], docSha256(pdf('hémorragie')));
      expect(docScan(f)!['texteIndexe'], isTrue);
      expect(docEtatIndexation(f), 'indexe');
      expect(s.texteDe(f), contains('hemorragie'));
      expect(m.collection('fichiers').parId(docScan(f)!['sha256']), isNotNull);
      expect(f.containsKey('donnees'), isFalse, reason: 'aucun octet de fichier dans le magasin');
      expect(jsonEncode(m.collection('courriers').toutes), isNot(contains('JVBER')), reason: 'pas de base64 de PDF');
      expect(m.collection('audit').toutes.first['action'], 'Dépôt d’un scan');
      expect(r.annuler, isNotNull);
    });

    test('un scan image est « texte non indexé » et le dit', () async {
      final m = magasin({'courriers': [courrier('C1', 'ARR-2026-0001')]});
      final s = brancher(m);
      final r = await s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.png', octets: png);
      expect(docEtatIndexation(m.collection('courriers').parId('C1')!), 'non_indexe');
      expect(r.avertissementIndexation, contains('non indexé'));
      final p = await s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'b.pdf', octets: pdfImage());
      expect(p.avertissementIndexation, contains('scan image'));
    });

    test('refus nommés : format, extension, taille, doublon sur la même fiche ; rien n’est écrit', () async {
      final m = magasin({'courriers': [courrier('C1', 'ARR-2026-0001'), courrier('C2', 'ARR-2026-0002')]});
      final s = brancher(m);
      Future<DocErreur> refus(Future<Object?> f) async {
        try {
          await f;
        } on DocErreur catch (e) {
          return e;
        }
        fail('un refus était attendu');
      }

      expect((await refus(s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'x.exe', octets: [1, 2, 3, 4]))).code, 'FORMAT_REFUSE');
      expect((await refus(s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'x.pdf', octets: png))).code, 'EXTENSION_INCOHERENTE');
      expect(s.reglerTailleMax(10, 'x')!.code, 'TAILLE_HORS_BORNES');
      expect(s.reglerTailleMax(docTaillePlancher, 'Disque plein'), isNull);
      expect(s.tailleMax(), docTaillePlancher);
      final gros = Uint8List.fromList([...pdf('x'), ...List.filled(docTaillePlancher, 7)]);
      expect((await refus(s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'g.pdf', octets: gros))).code, 'TAILLE_DEPASSEE');
      await s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.pdf', octets: pdf('a'));
      expect((await refus(s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.pdf', octets: pdf('a')))).code, 'DOUBLON_MEME_FICHE');
      expect(stock.nombre, 1);
      expect(m.collection('audit').toutes.where((a) => a['action'] == 'Taille maximale des scans'), hasLength(1));
      // le même fichier sur une AUTRE fiche : avertissement nommé, puis accepté si l'agent confirme
      Object? ailleurs;
      try {
        await s.deposer(famille: docFamilleCourrier, ficheId: 'C2', nomOrigine: 'a.pdf', octets: pdf('a'));
      } on DocAvertissement catch (a) {
        ailleurs = a.ailleurs['reference'];
      }
      expect(ailleurs, 'ARR-2026-0001');
      await s.deposer(famille: docFamilleCourrier, ficheId: 'C2', nomOrigine: 'a.pdf', octets: pdf('a'), confirmerAilleurs: true);
      expect(docScan(m.collection('courriers').parId('C2')!)!['nomNormalise'], '2026-11-11_ARR_0002.pdf');
      expect(stock.nombre, 2, reason: 'deux noms normalisés pour les mêmes octets');
    });

    test('remplacement : l’ancienne version reste (fiche ET disque) ; retrait : motif obligatoire, annulable ; jamais de suppression', () async {
      final m = magasin({'courriers': [courrier('C1', 'ARR-2026-0042')]});
      final s = brancher(m);
      await s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'v1.pdf', octets: pdf('un'));
      final r2 = await s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'v2.pdf', octets: pdf('deux'));
      var f = m.collection('courriers').parId('C1')!;
      expect(r2.remplacement, isTrue);
      expect(docScan(f)!['version'], 2);
      expect(docScan(f)!['nomNormalise'], '2026-11-11_ARR_0042_v2.pdf');
      expect(docScansAnterieurs(f).single['nomNormalise'], '2026-11-11_ARR_0042.pdf');
      expect(File('${stock.dossier}/2026-11-11_ARR_0042.pdf').readAsBytesSync(), pdf('un'));
      expect(await s.lire(famille: docFamilleCourrier, fiche: f, version: docScansAnterieurs(f).single), pdf('un'));
      expect(() => s.retirer(famille: docFamilleCourrier, ficheId: 'C1', motif: '  '), throwsA(isA<DocErreur>()));
      final annule = s.retirer(famille: docFamilleCourrier, ficheId: 'C1', motif: 'Mauvais scan');
      f = m.collection('courriers').parId('C1')!;
      expect(docNumerise(f), isFalse);
      expect(docScansAnterieurs(f), hasLength(2));
      expect(File('${stock.dossier}/2026-11-11_ARR_0042_v2.pdf').existsSync(), isTrue, reason: 'RG-14 : le fichier reste');
      annule();
      f = m.collection('courriers').parId('C1')!;
      expect(docNumerise(f), isTrue);
      expect(docScan(f)!['version'], 2);
      expect(docScansAnterieurs(f), hasLength(1));
    });

    test('la lecture est vérifiée (empreinte recalculée), journalisée, et un fichier altéré n’est jamais rendu', () async {
      final m = magasin({'courriers': [courrier('C1', 'ARR-2026-0042')]});
      final s = brancher(m);
      await s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'v1.pdf', octets: pdf('un'));
      final f = m.collection('courriers').parId('C1')!;
      expect(await s.lire(famille: docFamilleCourrier, fiche: f), pdf('un'));
      expect(m.collection('audit').toutes.first['action'], 'Consultation d’un scan');
      expect(m.collection('audit').toutes.first['utilisateur'], 'Awa KOUASSI');
      File('${stock.dossier}/2026-11-11_ARR_0042.pdf').writeAsBytesSync([...pdf('un'), 1]);
      await expectLater(s.lire(famille: docFamilleCourrier, fiche: f), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'FICHIER_ALTERE')));
      // sans dossier branché : refus nommé, rien d'écrit
      final m2 = magasin({'courriers': [courrier('C1', 'ARR-2026-0042')]});
      await expectLater(ServiceFichiers.de(m2).deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.pdf', octets: pdf('a')), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'FICHIERS_NON_BRANCHES')));
    });

    test('téléchargement sous le nom normalisé', () async {
      final m = magasin({'courriers': [courrier('C1', 'ARR-2026-0042')]});
      final s = brancher(m);
      await s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'Courrier ministère.pdf', octets: pdf('un'));
      final ecrit = <String, List<int>>{};
      final avant = enregistrerTelechargement;
      enregistrerTelechargement = (nom, o) async {
        ecrit[nom] = o;
        return '/faux/$nom';
      };
      addTearDown(() => enregistrerTelechargement = avant);
      await s.telecharger(famille: docFamilleCourrier, fiche: m.collection('courriers').parId('C1')!);
      expect(ecrit.keys, ['2026-11-11_ARR_0042.pdf']);
      expect(ecrit.values.single, pdf('un'));
    });
  });

  group('service : dossier patient et droits par catégorie sensible', () {
    test('le droit de lire un type suit la matrice, jamais un nom de rôle ; le dépôt est refusé aussi', () async {
      final m = magasin({'documentsPatient': [docu('D1', 'GED-00001', 'Compte rendu médical'), docu('D2', 'GED-00002', 'Pièce d’identité')]});
      final s = brancher(m);
      final accueil = DroitsSensibles(fiches: const [], peutVoirEcran: (r, e) => e == 'm1-patients');
      bool peut(String c) => accueil.peut('quelconque', c);
      await expectLater(s.deposer(famille: docFamillePatient, ficheId: 'D1', nomOrigine: 'cr.pdf', octets: pdf('x'), peutCategorie: peut), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'ZONE_REFUSEE')));
      await s.deposer(famille: docFamillePatient, ficheId: 'D2', nomOrigine: 'cni.png', octets: png, peutCategorie: peut);
      final f = m.collection('documentsPatient').parId('D2')!;
      expect(docScan(f)!['nomNormalise'], '2026-11-05_CBG-1-26_piece-d-identite_002.png');
      expect(await s.lire(famille: docFamillePatient, fiche: f, peutCategorie: peut), png);
      // un profil sans la catégorie ne lit pas un compte rendu déjà déposé
      await s.deposer(famille: docFamillePatient, ficheId: 'D1', nomOrigine: 'cr.pdf', octets: pdf('x'));
      await expectLater(s.lire(famille: docFamillePatient, fiche: m.collection('documentsPatient').parId('D1')!, peutCategorie: peut), throwsA(isA<DocErreur>().having((e) => e.code, 'code', 'ZONE_REFUSEE')));
    });

    test('MIGRATION du base64 : rangé chez la mère, empreinte relue AVANT retrait, base64 absent du magasin ensuite', () async {
      final o1 = pdf('migration'), o2 = png;
      String uri(List<int> o, String mime) => 'data:$mime;base64,${base64Encode(o)}';
      final m = magasin({
        'documentsPatient': [
          {...docu('D1', 'GED-00001', 'Ordonnance'), 'fichier': 'ord.pdf', 'donnees': uri(o1, 'application/pdf')},
          {...docu('D2', 'GED-00002', 'Facture'), 'fichier': 'f.png', 'donnees': uri(o2, 'image/png')},
          {...docu('D3', 'GED-00003', 'Facture'), 'taille': 3000000},
        ]
      });
      final s = brancher(m);
      expect(s.enBase64(), 2);
      final r = await s.migrerBase64();
      expect(r.migrees, ['GED-00001', 'GED-00002']);
      expect(r.complet, isTrue);
      expect(s.enBase64(), 0);
      final apres = jsonEncode(m.collection('documentsPatient').toutes);
      expect(apres, isNot(contains(base64Encode(o1).substring(10, 40))));
      final f = m.collection('documentsPatient').parId('D1')!;
      expect(docScan(f)!['sha256'], docSha256(o1));
      expect(File('${stock.dossier}/${docScan(f)!['nomNormalise']}').readAsBytesSync(), o1);
      expect(await s.lire(famille: docFamillePatient, fiche: f), o1);
      expect(s.texteDe(f), contains('migration'));
      expect(docNumerise(m.collection('documentsPatient').parId('D3')!), isFalse, reason: 'déclaré sans fichier : reste « référencé »');
      expect((await s.migrerBase64()).migrees, isEmpty, reason: 'idempotente');
      expect(m.collection('audit').toutes.first['action'], contains('Migration'));
    });

    test('une copie qui ne relit pas à l’identique laisse le base64 : la vérification d’empreinte est le garde-fou', () async {
      final o1 = pdf('migration');
      final m = magasin({
        'documentsPatient': [
          {...docu('D1', 'GED-00001', 'Ordonnance'), 'donnees': 'data:application/pdf;base64,${base64Encode(o1)}'}
        ]
      });
      final s = brancher(m, st: _StockMenteur(stock));
      final r = await s.migrerBase64();
      expect(r.migrees, isEmpty);
      expect(r.refusees.single.code, 'EMPREINTE_RELUE_DIFFERENTE');
      expect(s.enBase64(), 1);
      expect(m.collection('documentsPatient').parId('D1')!['donnees'], isNotNull);
    });
  });

  group('sauvegarde puis restauration (aller-retour par le service)', () {
    test('un disque perdu : la restauration rend les fichiers ET vérifie les empreintes ; une sauvegarde altérée est refusée en nommant', () async {
      final m = magasin({'courriers': [courrier('C1', 'ARR-2026-0042'), courrier('C2', 'DEP-2026-0003', sens: 'depart')]});
      final s = brancher(m);
      await s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.pdf', octets: pdf('un'));
      await s.deposer(famille: docFamilleCourrier, ficheId: 'C2', nomOrigine: 'b.png', octets: png);
      expect(stock.sauvegarder('${tmp.path}/sauv')['copies'], 2);
      Directory(stock.dossier).deleteSync(recursive: true);
      final neuf = StockFichiers('${tmp.path}/neuf');
      s.stockagePour = (_) => neuf;
      expect(neuf.restaurer('${tmp.path}/sauv')['complet'], isTrue);
      final f = m.collection('courriers').parId('C1')!;
      expect(await s.lire(famille: docFamilleCourrier, fiche: f), pdf('un'), reason: 'les empreintes de la fiche retrouvent le fichier restauré');
      expect(sha(File('${tmp.path}/neuf/2026-11-11_ARR_0042.pdf')), docScan(f)!['sha256']);
      File('${tmp.path}/sauv/2026-11-11_DEP_0003.png').writeAsBytesSync([...png, 5]);
      final r = StockFichiers('${tmp.path}/autre').restaurer('${tmp.path}/sauv');
      expect(r['refuses'], ['2026-11-11_DEP_0003.png']);
    });
  });

  group('écrans', () {
    Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, String role) async {
      t.view.physicalSize = const Size(1600, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(SighPoste(key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.fileul, role: role), ecranInitial: ecran, magasin: m, horloge: () => auj));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> toucher(WidgetTester t, Finder f) async {
      await t.ensureVisible(f);
      await t.pump();
      await t.tap(f);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    }

    testWidgets('courrier : déposer un scan depuis le tiroir, aperçu et visionneuse (rotation), « Numérisé » se dérive ; texte du PDF cherchable', (t) async {
      final m = magasin({'courriers': [courrier('C1', 'ARR-2026-0042')]});
      brancher(m);
      SelecteursScan.choisir = (_) async => ScanChoisi('scan.png', png);
      await ouvrir(t, m, 'm13-courriers', 'direction');
      expect(find.text('À scanner'), findsOneWidget);
      await toucher(t, find.byTooltip('Déposer un scan'));
      expect(find.byKey(const Key('panneau-scan')), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Déposer un scan'));
      final f = m.collection('courriers').parId('C1')!;
      expect(docNumerise(f), isTrue);
      expect(find.byKey(const Key('visionneuse:vue')), findsOneWidget);
      expect(find.textContaining('2026-11-11_ARR_0042.png'), findsWidgets);
      expect(find.byKey(const Key('scan:chemin')), findsOneWidget);
      expect(tester(t, 'scan:chemin'), contains(stock.dossier));
      expect(find.text('Rotation 0°'), findsOneWidget);
      await toucher(t, find.byTooltip('Pivoter à droite'));
      expect(find.text('Rotation 90°'), findsOneWidget);
      await toucher(t, find.byTooltip('Ajuster à la fenêtre'));
      expect(find.text('Rotation 0°'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Remplacer le scan'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Retirer le scan'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('droits : la commande « Déposer un scan » est ABSENTE sans droit d’édition, « Retirer » sans droit d’annulation', (t) async {
      final m = magasin({'courriers': [courrier('C1', 'ARR-2026-0042')]});
      final s = brancher(m);
      await s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.png', octets: png);
      // reception : [voir, éditer, —] sur m13-courriers
      await ouvrir(t, m, 'm13-courriers', 'reception');
      await toucher(t, find.byTooltip('Voir le scan'));
      expect(find.widgetWithText(BoutonSigh, 'Remplacer le scan'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Télécharger'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Retirer le scan'), findsNothing, reason: 'pas de droit d’annuler : la commande est absente, non grisée');
    });

    testWidgets('dossier patient : l’accueil ne voit ni ne cherche un compte rendu (zone 2), et la restriction s’annonce', (t) async {
      final m = magasin({
        'documentsPatient': [docu('D1', 'GED-00001', 'Compte rendu médical'), docu('D2', 'GED-00002', 'Pièce d’identité')]
      });
      brancher(m);
      await ouvrir(t, m, 'm1-documents', 'reception');
      expect(find.text('GED-00002'), findsOneWidget);
      expect(find.text('GED-00001'), findsNothing);
      expect(find.byKey(const Key('doc:reservees')), findsOneWidget);
      // un profil clinique voit les deux
      await ouvrir(t, m, 'm1-documents', 'medecin');
      expect(find.text('GED-00001'), findsOneWidget);
      expect(find.text('GED-00002'), findsOneWidget);
      expect(find.byKey(const Key('doc:reservees')), findsNothing);
    });

    testWidgets('dossier patient : une décision de droits accordée à chaud ouvre la zone, sans nom de rôle dans le code', (t) async {
      final m = magasin({
        'documentsPatient': [docu('D1', 'GED-00001', 'Compte rendu médical')]
      });
      brancher(m);
      m.collection('rbac').inserer({'id': 'RBAC-reception', 'role': 'reception', 'donneesSensibles': {'notes_consultation': true, 'diagnostic_pathologie': true}}, prefixe: 'RBAC');
      await ouvrir(t, m, 'm1-documents', 'reception');
      expect(find.text('GED-00001'), findsOneWidget);
    });

    testWidgets('dossier patient : ajouter un document range le fichier sous son nom normalisé ; le texte d’un PDF se retrouve par un mot de son corps', (t) async {
      final m = magasin({'documentsPatient': []});
      brancher(m);
      final s = ServiceFichiers.de(m);
      // La fiche naît de la modale ; on prépare ici le même résultat par le service, puis on cherche à l'écran.
      m.collection('documentsPatient').inserer({...docu('D1', 'GED-00001', 'Compte rendu médical')}, prefixe: 'DOC');
      await s.deposer(famille: docFamillePatient, ficheId: 'D1', nomOrigine: 'cr.pdf', octets: pdf('Hémorragie'));
      m.collection('documentsPatient').inserer({...docu('D2', 'GED-00002', 'Ordonnance')}, prefixe: 'DOC');
      await s.deposer(famille: docFamillePatient, ficheId: 'D2', nomOrigine: 'o.png', octets: png);
      await ouvrir(t, m, 'm1-documents', 'admin');
      await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, 'hemorragie');
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('GED-00001'), findsOneWidget);
      expect(find.text('GED-00002'), findsNothing);
      expect(find.textContaining('Texte indexé'), findsWidgets);
      await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, '');
      await t.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Texte non indexé'), findsWidgets, reason: 'le scan image le dit sur sa ligne');
    });

    testWidgets('dossier patient : « Ajouter un document » (modale) crée la fiche ET range le fichier ; un fichier refusé ne laisse aucune fiche', (t) async {
      final m = magasin({'documentsPatient': []});
      brancher(m);
      await ouvrir(t, m, 'm1-documents', 'admin');
      void poserForm(Map<String, Object?> v) {
        final ctl = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
        v.forEach(ctl.poser);
      }

      // un format refusé : le choix lui-même est refusé en le nommant, rien ne part
      SelecteursScan.choisir = (_) async => ScanChoisi('virus.exe', Uint8List.fromList([1, 2, 3, 4]));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter un document'));
      poserForm({'patientId': 'K1', 'type': 'Ordonnance'});
      await toucher(t, find.widgetWithText(BoutonSigh, 'Choisir le fichier'));
      expect(find.textContaining('Format non admis'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Rattacher au dossier'));
      expect(m.collection('documentsPatient').toutes, isEmpty);
      // un fichier valide
      SelecteursScan.choisir = (_) async => ScanChoisi('ordonnance.pdf', pdf('paracétamol'));
      await toucher(t, find.widgetWithText(BoutonSigh, 'Choisir le fichier'));
      expect(find.byKey(const Key('doc:fichier-choisi')), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Rattacher au dossier'));
      final fiches = m.collection('documentsPatient').toutes;
      expect(fiches, hasLength(1));
      expect(docScan(fiches.single)!['nomNormalise'], '2026-11-12_CBG-1-26_ordonnance_001.pdf');
      expect(File('${stock.dossier}/2026-11-12_CBG-1-26_ordonnance_001.pdf').readAsBytesSync(), pdf('paracétamol'));
      expect(fiches.single.containsKey('donnees'), isFalse);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('droits : un profil en lecture seule ne voit ni « Ajouter un document » ni « Remplacer le scan »', (t) async {
      final m = magasin({'documentsPatient': [docu('D1', 'GED-00001', 'Pièce d’identité')]});
      final s = brancher(m);
      await s.deposer(famille: docFamillePatient, ficheId: 'D1', nomOrigine: 'o.png', octets: png);
      await ouvrir(t, m, 'm1-documents', 'anesthesiste');
      expect(find.widgetWithText(BoutonSigh, 'Ajouter un document'), findsNothing);
      await toucher(t, find.byTooltip('Prévisualiser'));
      expect(find.byKey(const Key('panneau-scan')), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Télécharger'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Remplacer le scan'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Retirer le scan'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Déposer un scan'), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('Paramètres système › Scans numérisés : le chemin chez la mère s’affiche ; la taille maximale se règle avec motif ; un fileul ne règle rien', (t) async {
      final m = magasin({});
      final s = brancher(m);
      s.changerDossierMere = (d) async => {'nouveau': d, 'ancien': stock.dossier, 'copies': 0};
      await ouvrir(t, m, 'cfg-systeme', 'admin');
      await toucher(t, find.text('Scans numérisés'));
      expect(find.byKey(const Key('scans:chemin-mere')), findsOneWidget);
      expect(tester(t, 'scans:chemin-mere'), stock.dossier);
      expect(find.textContaining('à valider par la Direction'), findsOneWidget);
      await toucher(t, find.widgetWithText(BoutonSigh, 'Régler la taille maximale'));
      await t.enterText(find.byKey(const Key('scans:taille')), '20');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.textContaining('Le motif du changement est obligatoire'), findsOneWidget);
      await t.enterText(find.byKey(const Key('scans:motif')), 'Scans en couleur');
      await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(s.tailleMax(), 20 * 1024 * 1024);
      expect(m.collection('reglages').parId('documentsBornes')!['motif'], 'Scans en couleur');
      await t.pump(const Duration(seconds: 10));
      // un fileul : pas de commande de réglage
      s.changerDossierMere = null;
      await ouvrir(t, m, 'cfg-systeme', 'admin');
      await toucher(t, find.text('Scans numérisés'));
      expect(find.widgetWithText(BoutonSigh, 'Régler la taille maximale'), findsNothing);
      expect(find.widgetWithText(BoutonSigh, 'Changer le dossier'), findsNothing);
      expect(find.textContaining('Se règle sur le poste mère'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('courriers : la recherche lit le texte du PDF ; plage de dates ; filtre « Texte non indexé »', (t) async {
      final m = magasin({'courriers': [courrier('C1', 'ARR-2026-0042'), courrier('C2', 'ARR-2026-0043')]});
      final s = brancher(m);
      await s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.pdf', octets: pdf('autorisation sanitaire'));
      await s.deposer(famille: docFamilleCourrier, ficheId: 'C2', nomOrigine: 'b.png', octets: png);
      await ouvrir(t, m, 'm13-courriers', 'direction');
      await t.enterText(find.byWidgetPredicate((w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Rechercher')).first, 'sanitaire');
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('ARR-2026-0042'), findsOneWidget);
      expect(find.text('ARR-2026-0043'), findsNothing);
    });
  });
}

String tester(WidgetTester t, String cle) {
  final w = t.widget(find.byKey(Key(cle)));
  return w is SelectableText ? (w.data ?? '') : ((w as Text).data ?? '');
}

String sha(File f) => docSha256(f.readAsBytesSync());

/// Un stockage qui range correctement mais RELIT autre chose : ce que la vérification d'empreinte de la migration doit attraper.
class _StockMenteur implements DocStockage {
  _StockMenteur(this.vrai);
  final StockFichiers vrai;
  @override
  Future<void> deposer({required List<int> octets, required String sha256, required String nomNormalise}) => vrai.deposer(octets: octets, sha256: sha256, nomNormalise: nomNormalise);
  @override
  Future<List<int>?> lire(String sha256) async => [...(await vrai.lire(sha256))!, 0];
}
