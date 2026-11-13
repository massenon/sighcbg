import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/selecteurs_import.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// Le bouton « Importer » sur les écrans des référentiels analyses, compagnies et souscripteurs (décision du 11/11/2026) : même fabrique que partout,
/// absent sans le droit de l'écran du JEU, vérification sans écriture, import écrit et journalisé.
final donnees = DonneesNavigation.depuisDossier();

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, String role) async {
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => DateTime(2026, 11, 1)));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

Uint8List csv(List<List<String>> lignes) => Uint8List.fromList(utf8.encode('﻿${[for (final l in lignes) l.map((x) => '"$x"').join(';')].join('\r\n')}\r\n'));

Magasin magasin() => Magasin({
      'examensLabo': const [],
      'assureurs': [
        {'id': 'A0', 'code': 'AFR', 'nom': 'AFRICAINE', 'statut': 'actif'}
      ],
      'souscripteurs': const [],
      'patients': const [],
      'factures': const [],
      collectionLots: const [],
      'audit': const [],
    });

class Cas {
  const Cas(this.jeu, this.ecran, this.collection, this.fichier, this.lignes, this.cle);
  final String jeu, ecran, collection, fichier, cle;
  final List<List<String>> lignes;
}

final cas3 = [
  Cas('analyses', 'm5-catalogue', 'examensLabo', 'a.csv', [jeuAnalyses.colonnes.map((c) => c.label).toList(), ['TST1', 'Examen de test', 'Biochimie', 'Sérum', '2 h']], 'code'),
  Cas('assureurs', 'm9-compagnies', 'assureurs', 'c.csv', [jeuAssureurs.colonnes.map((c) => c.label).toList(), ['NSIA', 'NSIA ASSURANCE', '0153212091', 'contact@exemple.bj', 'Signée']], 'code'),
  Cas('souscripteurs', 'm9-conventions', 'souscripteurs', 's.csv', [jeuSouscripteurs.colonnes.map((c) => c.label).toList(), ['Entreprise Test', 'TST/2026/0001', 'AFR', 'entreprise', '10', '2026-01-01', '']], 'police'),
];

void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    SelecteursImport.reinitialiser();
    ToastsSigh.viderPourTests();
  });

  for (final k in cas3) {
    testWidgets('${k.ecran} : bouton présent avec le droit du jeu, absent sans (jamais grisé)', (t) async {
      final m = donnees.matrice;
      final jeu = jeuImportParId(k.jeu)!;
      final avec = [for (final r in m.rolesBruts) '${r['id']}'].firstWhere((r) => m.peutEditer(r, jeu.ecran) && m.peutVoir(r, k.ecran), orElse: () => '');
      final sans = [for (final r in m.rolesBruts) '${r['id']}'].firstWhere((r) => !m.peutEditer(r, jeu.ecran) && m.peutVoir(r, k.ecran), orElse: () => '');
      expect(avec, isNotEmpty);
      expect(sans, isNotEmpty);
      await ouvrir(t, magasin(), k.ecran, avec);
      expect(find.byKey(Key('importer-${k.jeu}')), findsOneWidget, reason: avec);
      await ouvrir(t, magasin(), k.ecran, sans);
      expect(find.byKey(Key('importer-${k.jeu}')), findsNothing, reason: sans);
      expect(find.widgetWithText(BoutonSigh, 'Importer'), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('${k.ecran} : la vérification n\'écrit rien, l\'import écrit et journalise', (t) async {
      final m0 = donnees.matrice;
      final jeu = jeuImportParId(k.jeu)!;
      final role = [for (final r in m0.rolesBruts) '${r['id']}'].firstWhere((r) => m0.peutEditer(r, jeu.ecran) && m0.peutVoir(r, k.ecran));
      final m = magasin();
      final avant = m.collection(k.collection).toutes.length;
      await ouvrir(t, m, k.ecran, role);
      await toucher(t, find.byKey(Key('importer-${k.jeu}')));
      await toucher(t, find.byKey(const Key('import-vers-verification')));
      SelecteursImport.choisir = () async => FichierChoisi(k.fichier, csv(k.lignes));
      await toucher(t, find.byKey(const Key('import-choisir-fichier')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Vérification conforme'), findsOneWidget);
      expect(m.collection(k.collection).toutes.length, avant, reason: 'rien n\'est écrit à la vérification');
      expect(find.byKey(const Key('imp-ignorer-existants')), findsNothing, reason: 'hors des quatre jeux autorisés');
      await toucher(t, find.byKey(const Key('import-vers-import')));
      await toucher(t, find.byKey(const Key('import-ecrire')));
      expect(find.byKey(const Key('import-resultat')), findsOneWidget);
      expect(m.collection(k.collection).toutes.length, avant + 1);
      expect(m.collection('audit').toutes.where((a) => a['action'] == 'Import').length, 1, reason: 'RG-12');
      expect(m.collection(collectionLots).actives.single['etat'], 'applique');
      await t.pump(const Duration(seconds: 10));
    });
  }

  test('la borne de taille s\'applique à ces trois jeux et aucune règle d\'« ignorer » nouvelle n\'est ouverte', () {
    for (final id in ['analyses', 'assureurs', 'souscripteurs']) {
      final j = jeuImportParId(id)!;
      expect(j.octetsMaxDefaut, greaterThan(0));
      expect(j.ignorable, isFalse, reason: id);
    }
  });
}
