import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/impression/feuilles.dart';
import 'package:sigh_poste/impression/pdf.dart';
import 'package:sigh_poste/impression/piece.dart';

import 'aide_polices.dart';

/// Contrôle VISUEL des tableaux imprimés : écrit l'aperçu (PNG) et le PDF dans le dossier SIGH_CAPTURES. Sur demande seulement :
/// `SIGH_CAPTURES=/chemin flutter test test/capture_tableaux_test.dart`.
final String? _sortie = Platform.environment['SIGH_CAPTURES'];

PieceA4 _naissances() => PieceA4(
      titre: 'Sélection — naissances',
      reference: 'CBG-20261110-0001',
      utilisateur: 'Test',
      edite: DateTime(2026, 11, 10),
      tableaux: [
        TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Date et heure', valeur: (r) => r['d']),
          ColonneEtat(libelle: 'Mère', valeur: (r) => r['m']),
          ColonneEtat(libelle: 'Sexe', valeur: (r) => r['s']),
          ColonneEtat(libelle: 'Poids (g)', valeur: (r) => r['p'], droite: true, somme: (r) => r['p'] as num),
        ], lignes: const [
          {'d': '14/10/2026 à 08h50 (accouchement par voie basse)', 'm': 'A. D.', 's': 'Féminin', 'p': 3100},
          {'d': '15/10/2026', 'm': 'Deuxième mère de la liste, nom composé très long', 's': 'Masculin', 'p': 2900},
        ]),
        TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Code', valeur: (r) => r['c']),
          ColonneEtat(libelle: 'Analyse', valeur: (r) => r['a']),
          ColonneEtat(libelle: 'Échantillon', valeur: (r) => r['e']),
        ], lignes: const [
          {'c': 'HEM-01', 'a': 'Numération formule sanguine avec\nformule leucocytaire', 'e': 'Sang'},
        ]),
      ],
    );

void main() {
  testWidgets('capture : aperçu et PDF des tableaux', skip: _sortie == null, (t) async {
    await chargerPolices();
    t.view.physicalSize = const Size(1000, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: RepaintBoundary(key: const Key('cap'), child: FeuilleA4(piece: _naissances()))))));
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    await t.runAsync(() async {
      final RenderRepaintBoundary b = t.renderObject(find.byKey(const Key('cap')));
      final ui.Image img = await b.toImage(pixelRatio: 1.5);
      File('$_sortie/apercu-tableaux.png').writeAsBytesSync((await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
      final p = await PolicesPdf.charger();
      File('$_sortie/tableaux.pdf').writeAsBytesSync(await pdfA4(_naissances(), p));
    });
  });
}
