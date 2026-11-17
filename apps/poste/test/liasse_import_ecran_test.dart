// L'écran « Import de la liasse fiscale » (m12-liasse-import, E4800) : import daté (source, date de dépôt, auteur), refus nommés, versions, archivage, droit par geste réservé,
// poste rattaché en lecture, « aucune liasse importée » dit, journal sans contenu comptable. Documents d'import : ceux de démonstration (`tool/donnees/*_demo.json`).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m12/registre_m12.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

const _liasse = 'tool/donnees/liasse_2025_demo.json';
const _classeur = 'tool/donnees/classeur_2025_demo.json';

void main() {
  setUpAll(chargerPolices);
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sigh-liasse-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Un magasin SANS aucun document fiscal (l'écran doit le dire).
  Magasin vide() {
    final m = magasinM14();
    m.collection(colDocumentsFiscaux).remplacerContenu(const []);
    return m;
  }

  String ecrire(String nom, String contenu) {
    final f = File('${tmp.path}/$nom')..writeAsStringSync(contenu);
    return f.path;
  }

  Future<void> choisir(WidgetTester t, String chemin) async {
    await t.enterText(find.byKey(const Key('liasse:fichier')), chemin);
    await t.pump();
    await toucherM14(t, find.byKey(const Key('liasse:verifier')));
  }

  test('l’écran est branché au registre de M12', () => expect(ecransM12.keys, contains('m12-liasse-import')));

  casM14('aucune liasse importée : l’écran le DIT (jamais des zéros), et les deux commandes d’import sont là pour qui détient le geste', (t) async {
    final m = vide();
    await ouvrirM14(t, m, 'm12-liasse-import', role: 'comptable');
    expect(find.byKey(const Key('liasse:aucune-liasse')), findsOneWidget);
    expect(find.byKey(const Key('liasse:aucune-classeur')), findsOneWidget);
    expect(find.textContaining('aucun chiffre'), findsWidgets);
    expect(find.byKey(const Key('liasse:verifier')), findsOneWidget);
    expect(DocumentsFiscaux.importee(docFiscalLiasse), isFalse);
  });

  casM14('importer la liasse : vérifiée sans rien écrire, puis importée avec sa source, sa date de dépôt et son auteur ; elle FAIT FOI ; le journal ne porte aucun montant', (t) async {
    final m = vide();
    await ouvrirM14(t, m, 'm12-liasse-import', role: 'comptable');
    await choisir(t, _liasse);
    expect(find.byKey(const Key('liasse:resume')), findsOneWidget);
    expect(find.textContaining('liasse de l’exercice 2025'), findsOneWidget);
    expect(find.textContaining(cpbMentionDemonstration), findsWidgets, reason: 'le document de démonstration le dit');
    expect(m.collection(colDocumentsFiscaux).toutes, isEmpty, reason: 'vérifier n’écrit rien');
    // la date et la source du document sont proposées
    expect(tester(t, 'liasse:date').controller!.text, '2026-04-30');
    expect(tester(t, 'liasse:source').controller!.text, contains('code DEMO'));
    await t.enterText(find.byKey(const Key('liasse:source')), 'Liasse remise à la DGI le 30/04/2026');
    await toucherM14(t, find.byKey(const Key('liasse:importer')));
    expect(find.byKey(const Key('liasse:ok')), findsOneWidget);
    final fiche = m.collection(colDocumentsFiscaux).toutes.single;
    expect([fiche['genre'], fiche['exercice'], fiche['dateEffet'], fiche['source']], [docFiscalLiasse, 2025, '2026-04-30', 'Liasse remise à la DGI le 30/04/2026']);
    expect('${fiche['importePar']}', isNotEmpty);
    expect(fiche['importeLe'], startsWith('2026-10-30'));
    expect(DocumentsFiscaux.importee(docFiscalLiasse), isTrue);
    expect(DocumentsFiscaux.provenanceLiasse!['source'], 'Liasse remise à la DGI le 30/04/2026');
    expect(find.byKey(const Key('liasse:en-force-liasse')), findsOneWidget);
    expect(find.byKey(const Key('liasse:aucune-liasse')), findsNothing);
    expect(find.text('Fait foi'), findsOneWidget);
    // RG-12 : une ligne de journal nommée, SANS contenu comptable détaillé
    final ligne = m.collection('audit').toutes.firstWhere((x) => x['action'] == 'Import' && x['entite'] == 'Document fiscal');
    expect(ligne['utilisateur'], isNotEmpty);
    final json = jsonEncode(ligne);
    expect((ligne['apres'] as Map)['lignes'], isA<Map>());
    for (final interdit in ['"brut"', '"netN1"', 'IMMOBILISATIONS', '3201001996110']) {
      expect(json, isNot(contains(interdit)), reason: interdit);
    }
  });

  casM14('importer le classeur : la date de dépôt est obligatoire (le classeur n’en porte pas) ; un refus se nomme', (t) async {
    final m = vide();
    await ouvrirM14(t, m, 'm12-liasse-import', role: 'comptable');
    await choisir(t, _classeur);
    expect(find.textContaining('classeur de l’exercice 2025'), findsOneWidget);
    await t.enterText(find.byKey(const Key('liasse:source')), 'Classeur de l’expert-comptable');
    await toucherM14(t, find.byKey(const Key('liasse:importer')));
    expect(find.byKey(const Key('liasse:refus')), findsOneWidget);
    expect(find.textContaining('DATE_DEPOT_ABSENTE'), findsOneWidget);
    expect(m.collection(colDocumentsFiscaux).toutes, isEmpty);
    await t.enterText(find.byKey(const Key('liasse:date')), '2026-12-25');
    await toucherM14(t, find.byKey(const Key('liasse:importer')));
    expect(find.textContaining('DATE_DEPOT_FUTURE'), findsOneWidget, reason: 'aujourd’hui est le 30/10/2026');
    await t.enterText(find.byKey(const Key('liasse:date')), '2026-04-30');
    await toucherM14(t, find.byKey(const Key('liasse:importer')));
    expect(find.byKey(const Key('liasse:ok')), findsOneWidget);
    expect(DocumentsFiscaux.importee(docFiscalClasseur), isTrue);
    expect(cpcClasseurImporte, isTrue);
  });

  casM14('un document invalide est REFUSÉ en nommant le code et l’endroit fautif ; la source vide aussi ; rien n’est écrit', (t) async {
    final m = vide();
    await ouvrirM14(t, m, 'm12-liasse-import', role: 'comptable');
    final casse = (jsonDecode(File(_liasse).readAsStringSync()) as Map).cast<String, Object?>()..remove('FLUX');
    await choisir(t, ecrire('casse.json', jsonEncode(casse)));
    expect(find.byKey(const Key('liasse:refus')), findsOneWidget);
    expect(find.textContaining('CLE_MANQUANTE'), findsOneWidget);
    expect(find.textContaining('(FLUX)'), findsOneWidget);
    expect(find.byKey(const Key('liasse:importer')), findsNothing, reason: 'un document refusé ne s’importe pas');
    await choisir(t, ecrire('vide.json', ''));
    expect(find.textContaining('FICHIER_VIDE'), findsOneWidget);
    await choisir(t, '${tmp.path}/absent.json');
    expect(find.textContaining('FICHIER_ILLISIBLE'), findsOneWidget);
    // la source
    await choisir(t, _liasse);
    await t.enterText(find.byKey(const Key('liasse:source')), '  ');
    await toucherM14(t, find.byKey(const Key('liasse:importer')));
    expect(find.textContaining('SOURCE_ABSENTE'), findsOneWidget);
    expect(m.collection(colDocumentsFiscaux).toutes, isEmpty);
  });

  casM14('une version nouvelle s’AJOUTE, la plus récente fait foi, une version s’ARCHIVE avec motif (jamais supprimée) et la précédente reprend', (t) async {
    final m = magasinM14(); // la liasse de démonstration du 30/04/2026 est déjà là
    expect(m.collection(colDocumentsFiscaux).toutes.where((f) => f['genre'] == docFiscalLiasse), hasLength(1));
    await ouvrirM14(t, m, 'm12-liasse-import', role: 'comptable');
    // un dépôt rectifié, plus récent : même exercice, nouvelle date
    final rect = (jsonDecode(File(_liasse).readAsStringSync()) as Map).cast<String, Object?>();
    (rect['DEPOT'] as Map)['dateDepot'] = '2026-06-10';
    await choisir(t, ecrire('rect.json', jsonEncode(rect)));
    await t.enterText(find.byKey(const Key('liasse:source')), 'Liasse rectifiée');
    await toucherM14(t, find.byKey(const Key('liasse:importer')));
    expect(m.collection(colDocumentsFiscaux).toutes.where((f) => f['genre'] == docFiscalLiasse), hasLength(2), reason: 'rien n’est écrasé');
    expect(DocumentsFiscaux.provenanceLiasse!['source'], 'Liasse rectifiée');
    expect(find.text('Fait foi'), findsNWidgets(2), reason: 'la liasse rectifiée ET le classeur de démonstration du jeu');
    expect(find.text('Antérieure'), findsOneWidget);
    // archiver la plus récente : motif obligatoire
    final recente = m.collection(colDocumentsFiscaux).toutes.firstWhere((f) => f['source'] == 'Liasse rectifiée')['id'];
    await toucherM14(t, find.byKey(Key('liasse:archiver:$recente')));
    await toucherM14(t, find.byKey(const Key('liasse:archiver-ok')));
    expect(find.textContaining('MOTIF_ABSENT'), findsOneWidget);
    await t.enterText(find.byKey(const Key('liasse:motif')), 'Import fait par erreur');
    await toucherM14(t, find.byKey(const Key('liasse:archiver-ok')));
    final archivee = m.collection(colDocumentsFiscaux).parId(recente)!;
    expect([archivee['statut'], archivee['motifArchivage']], ['archive', 'Import fait par erreur']);
    expect(archivee['archivePar'], isNotEmpty);
    expect(m.collection(colDocumentsFiscaux).toutes.where((f) => f['genre'] == docFiscalLiasse), hasLength(2), reason: 'une version archivée n’est jamais supprimée');
    expect(DocumentsFiscaux.provenanceLiasse!['source'], isNot('Liasse rectifiée'), reason: 'la précédente reprend');
    expect(find.text('Archivée'), findsOneWidget);
    expect(find.textContaining('Import fait par erreur'), findsWidgets);
    expect(m.collection('audit').toutes.any((x) => x['action'] == 'Archivage' && x['entite'] == 'Document fiscal'), isTrue);
  });

  casM14('sans le geste réservé : l’écran se lit (versions, ce qui fait foi), toutes les commandes sont ABSENTES, jamais grisées', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm12-liasse-import', role: 'direction');
    expect(find.byKey(const Key('liasse:lecture')), findsOneWidget);
    for (final k in ['liasse:verifier', 'liasse:importer', 'liasse:fichier']) {
      expect(find.byKey(Key(k)), findsNothing, reason: k);
    }
    expect(find.byWidgetPredicate((w) => w is BoutonSigh && w.libelle == 'Archiver'), findsNothing);
    expect(find.byKey(const Key('liasse:en-force-liasse')), findsOneWidget);
    expect(find.text('Fait foi'), findsWidgets);
  });

  casM14('la clinique ACCORDE le geste à un autre rôle par la fiche de rôle, et le retire au comptable', (t) async {
    final m = magasinM14();
    m.collection('rbac').inserer({'id': 'RBAC-LIASSE', 'role': 'direction', 'statut': 'actif', 'droitsGestes': {gesteDocumentsFiscauxImporter: true}}, prefixe: 'RBAC');
    await ouvrirM14(t, m, 'm12-liasse-import', role: 'direction');
    expect(find.byKey(const Key('liasse:verifier')), findsOneWidget, reason: 'accordé à la Direction');
    final m2 = magasinM14();
    m2.collection('rbac').inserer({'id': 'RBAC-LIASSE2', 'role': 'comptable', 'statut': 'actif', 'droitsGestes': {gesteDocumentsFiscauxImporter: false}}, prefixe: 'RBAC');
    await ouvrirM14(t, m2, 'm12-liasse-import', role: 'comptable');
    expect(find.byKey(const Key('liasse:verifier')), findsNothing, reason: 'retiré au comptable');
  });

  casM14('un poste rattaché (fileul) lit la liasse que la mère a importée ; l’import se fait sur la mère, la commande est absente et le motif dit pourquoi', (t) async {
    final m = magasinM14();
    await t.runAsync(() => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true)));
    await ouvrirM14(t, m, 'm12-liasse-import', role: 'comptable');
    expect(find.byKey(const Key('liasse:fileul')), findsOneWidget);
    expect(find.textContaining('Réglé sur la mère'), findsOneWidget);
    expect(find.byKey(const Key('liasse:verifier')), findsNothing);
    expect(find.byKey(const Key('liasse:en-force-liasse')), findsOneWidget, reason: 'les versions de la mère sont lues ici');
  });
}

/// Le champ de texte nommé [cle] (pour lire ce que l'écran y a posé).
TextField tester(WidgetTester t, String cle) => t.widget<TextField>(find.byKey(Key(cle)));
