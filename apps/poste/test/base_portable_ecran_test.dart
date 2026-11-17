// Les écrans de la décision 12 (17/11/2026) : « Export, import et mise à jour » (cfg-base-portable), la carte « Préparer la mise à jour » et « Restaurer la clé de la clinique »
// (mere-cle-restauration). Droits par geste réservé (commande ABSENTE sans droit), refus nommés à l'écran, la clé jamais affichée.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/base_portable_poste.dart';
import 'package:sigh_poste/donnees/cle_clinique_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/maj_poste.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/cfg/cfg_base_portable.dart';
import 'package:sigh_poste/modules/mere/mrd_cle_restauration.dart';
import 'package:sigh_poste/modules/mere/registre_mere.dart';
import 'package:sigh_poste/modules/cfg/registre_cfg.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';

final cle = List<int>.generate(32, (i) => (i * 17 + 3) % 256);
final hexCle = cle.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  setUpAll(chargerPolices);
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sigh-ecran-base-'));
  tearDown(() {
    SelecteursBase.reinitialiser();
    tmp.deleteSync(recursive: true);
  });

  Future<Magasin> magasinAvecServices() async {
    final m = Magasin({'patients': [{'id': 'P1', 'statut': 'actif', 'nom': 'NOMSECRET'}]}, 'POSTE');
    await m.brancherPersistance(PersistanceMemoire(), delai: Duration.zero);
    return m;
  }

  void installer(Magasin m, String role) {
    // le droit se lit de la fiche de rôle À CHAQUE appel : les services interrogent les mêmes gestes que l'écran
    bool peut(String g) => DroitsGestes(fiches: m.collection('rbac').actives).peut(role, g);
    final base = ServiceBasePortable(magasin: m, dossierDonnees: tmp.path, role: () => 'fileul', cleClinique: () async => cle, peut: peut)..installer();
    ServiceMiseAJour(magasin: m, dossierDonnees: tmp.path, base: base, role: () => 'fileul', peut: peut, versionCourante: '0.1.0').installer();
    ServiceCleClinique(magasin: m, dossierDonnees: tmp.path, peut: peut).installer();
  }

  Future<void> monter(WidgetTester t, Magasin m, Widget ecran, String id, String role) async {
    t.view.physicalSize = const Size(1500, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ContexteEcran(
                    ecranId: id, role: role, droit: const Droit(voir: true, editer: true, annuler: true), magasin: m, utilisateur: 'U-ESSAI', aller: (_) {}, horloge: () => DateTime(2026, 11, 17, 12), child: ecran)))));
    await t.pump(const Duration(milliseconds: 100));
  }

  // Les opérations de fichier et de chiffrement s'enchaînent : chacune rend la main à la vraie boucle d'événements avant la suivante, d'où l'alternance (temps réel, puis pompe).
  Future<void> attendre(WidgetTester t, [Finder? jusqua]) async {
    for (var i = 0; i < 160; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await t.pump(const Duration(milliseconds: 20));
      if (jusqua != null && jusqua.evaluate().isNotEmpty) return;
    }
  }

  test('les écrans sont branchés aux registres', () {
    expect(ecransMERE.keys, contains('mere-cle-restauration'));
    expect(ecransCFG.keys, contains('cfg-base-portable'));
  });

  testWidgets('cfg-base-portable, administrateur : exporte, le fichier est RELU et vérifié, la liste de ce qui ne voyage pas est dite', (t) async {
    final m = await magasinAvecServices();
    installer(m, 'admin');
    await monter(t, m, const EcranBasePortable(), 'cfg-base-portable', 'admin');
    expect(find.byKey(const Key('base:exporter')), findsOneWidget);
    expect(find.byKey(const Key('base:importer')), findsOneWidget);
    expect(find.byKey(const Key('maj:preparer')), findsOneWidget);
    expect(find.byKey(const Key('maj:lever')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('base:exclusions'))).data, allOf(contains('identifiants'), contains('jetonsEnquete')));
    await t.tap(find.byKey(const Key('base:exporter')));
    await attendre(t, find.byKey(const Key('base:export-ok')));
    expect(find.byKey(const Key('base:export-ok')), findsOneWidget);
    expect(find.textContaining('Relu et vérifié'), findsOneWidget);
    expect(Directory('${tmp.path}/exports').listSync().whereType<File>().single.path, endsWith('.sghx'));
  });

  testWidgets('sans les gestes réservés : l’écran se lit, les commandes sont ABSENTES (jamais grisées)', (t) async {
    final m = await magasinAvecServices();
    installer(m, 'caissier');
    await monter(t, m, const EcranBasePortable(), 'cfg-base-portable', 'caissier');
    for (final k in ['base:exporter', 'base:importer', 'base:verifier', 'maj:preparer', 'maj:lever']) {
      expect(find.byKey(Key(k)), findsNothing, reason: k);
    }
    expect(find.text('Export, import et mise à jour'), findsNothing, reason: 'le titre vient du manifeste, pas du corps');
    expect(find.textContaining('Préparer la mise à jour'), findsWidgets);
  });

  testWidgets('import : un fichier introuvable et une clé incorrecte sont refusés à l’écran en NOMMANT ; rien n’est écrit', (t) async {
    final m = await magasinAvecServices();
    installer(m, 'admin');
    await monter(t, m, const EcranBasePortable(), 'cfg-base-portable', 'admin');
    await t.enterText(find.byKey(const Key('base:fichier')), '${tmp.path}/absent.sghx');
    await t.tap(find.byKey(const Key('base:importer')));
    await attendre(t, find.byKey(const Key('base:erreur')));
    expect(find.textContaining('FICHIER_ILLISIBLE'), findsOneWidget);
    // un vrai export, mais ouvert avec une AUTRE clé (le service est remplacé, l'écran remonté)
    final export = await t.runAsync(() => ServiceBasePortable.de(m)!.exporter(dossierDestination: '${tmp.path}/ex'));
    ServiceBasePortable(magasin: m, dossierDonnees: tmp.path, role: () => 'fileul', cleClinique: () async => List.filled(32, 7), peut: (_) => true).installer();
    await monter(t, m, const EcranBasePortable(), 'cfg-base-portable', 'admin');
    await t.enterText(find.byKey(const Key('base:fichier')), export!.chemin);
    await t.tap(find.byKey(const Key('base:verifier')));
    await attendre(t, find.byKey(const Key('base:erreur')));
    expect(find.byKey(const Key('base:erreur')), findsOneWidget);
    expect(find.textContaining('CLE_INCORRECTE'), findsOneWidget);
    expect(Directory(tmp.path).listSync().whereType<Directory>().where((d) => d.path.contains('import-')), isEmpty);
  });

  testWidgets('import réussi : rapport (schéma, base en service intacte), puis mise en service : motif refusé s’il est court, programmée sinon', (t) async {
    final m = await magasinAvecServices();
    installer(m, 'admin');
    await monter(t, m, const EcranBasePortable(), 'cfg-base-portable', 'admin');
    final export = await t.runAsync(() => ServiceBasePortable.de(m)!.exporter(dossierDestination: '${tmp.path}/ex'));
    await t.enterText(find.byKey(const Key('base:fichier')), export!.chemin);
    await t.tap(find.byKey(const Key('base:verifier')));
    await attendre(t, find.byKey(const Key('base:verifie')));
    expect(find.byKey(const Key('base:verifie')), findsOneWidget);
    await t.tap(find.byKey(const Key('base:importer')));
    await attendre(t, find.byKey(const Key('base:import-ok')));
    expect(find.byKey(const Key('base:import-ok')), findsOneWidget);
    expect(find.textContaining('La base en service n’a pas été touchée'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('base:mise-en-service')), 200, scrollable: find.byType(Scrollable).first);
    await t.enterText(find.byKey(const Key('base:motif')), 'court');
    await t.tap(find.byKey(const Key('base:mise-en-service')));
    await attendre(t, find.textContaining('MOTIF_OBLIGATOIRE'));
    expect(find.textContaining('MOTIF_OBLIGATOIRE'), findsOneWidget);
    await t.enterText(find.byKey(const Key('base:motif')), 'remplacement du poste après panne du disque');
    await t.tap(find.byKey(const Key('base:mise-en-service')));
    await attendre(t, find.byKey(const Key('base:mise-en-service-ok')));
    expect(find.byKey(const Key('base:mise-en-service-ok')), findsOneWidget);
    expect(File('${tmp.path}/${ServiceBasePortable.fichierMiseEnService}').existsSync(), isTrue);
  });

  testWidgets('préparer la mise à jour : bloquée en nommant, préparée → autorisée ; lever le blocage exige un motif', (t) async {
    final m = await magasinAvecServices();
    installer(m, 'admin');
    await monter(t, m, const EcranBasePortable(), 'cfg-base-portable', 'admin');
    expect(find.byKey(const Key('maj:bloquee')), findsOneWidget);
    expect(find.textContaining('SAUVEGARDE_ABSENTE'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('maj:lever')), 200, scrollable: find.byType(Scrollable).first);
    await t.enterText(find.byKey(const Key('maj:motif')), 'court');
    await t.tap(find.byKey(const Key('maj:lever')));
    await attendre(t, find.byKey(const Key('maj:erreur')));
    expect(find.byKey(const Key('maj:erreur')), findsOneWidget);
    expect(find.textContaining('MOTIF_OBLIGATOIRE'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('maj:preparer')));
    await t.tap(find.byKey(const Key('maj:preparer')));
    await attendre(t, find.byKey(const Key('maj:autorisee')));
    expect(find.byKey(const Key('maj:autorisee')), findsOneWidget);
    expect(File('${tmp.path}/$majFichierAutorisation').existsSync(), isTrue);
  });

  testWidgets('mere-cle-restauration : l’empreinte erronée est refusée sans rien écrire ; la bonne est acceptée ; la clé n’apparaît nulle part', (t) async {
    final m = await magasinAvecServices();
    installer(m, 'admin');
    await monter(t, m, const EcranCleRestauration(), 'mere-cle-restauration', 'admin');
    expect(find.byKey(const Key('cle:etat')), findsOneWidget);
    expect(find.textContaining('Aucune clé de clinique'), findsOneWidget);
    await t.enterText(find.byKey(const Key('cle:texte')), hexCle);
    await t.enterText(find.byKey(const Key('cle:empreinte')), 'deadbeef');
    await t.tap(find.byKey(const Key('cle:restaurer')));
    await attendre(t, find.byKey(const Key('cle:erreur')));
    expect(find.textContaining('EMPREINTE_DIFFERENTE'), findsOneWidget);
    expect(File('${tmp.path}/pair.json').existsSync(), isFalse);
    expect(t.widget<TextField>(find.byKey(const Key('cle:texte'))).obscureText, isTrue, reason: 'la clé saisie est masquée');
    await t.enterText(find.byKey(const Key('cle:empreinte')), cleEmpreinte(cle).substring(0, 8));
    await t.tap(find.byKey(const Key('cle:restaurer')));
    await attendre(t, find.byKey(const Key('cle:acceptee')));
    expect(find.byKey(const Key('cle:acceptee')), findsOneWidget);
    expect(File('${tmp.path}/pair.json').existsSync(), isTrue);
    expect(t.widget<TextField>(find.byKey(const Key('cle:texte'))).controller!.text, isEmpty, reason: 'le champ qui a porté la clé est vidé');
    expect(find.textContaining(hexCle), findsNothing);
    expect(find.textContaining(base64.encode(cle)), findsNothing);
    expect(jsonEncode(m.collection('audit').toutes).contains(hexCle), isFalse);
  });

  testWidgets('mere-cle-restauration : sans le droit d’administrer le système, l’accès est refusé', (t) async {
    final m = await magasinAvecServices();
    installer(m, 'caissier');
    await monter(t, m, const EcranCleRestauration(), 'mere-cle-restauration', 'caissier');
    expect(find.byKey(const Key('cle:restaurer')), findsNothing);
  });
}
