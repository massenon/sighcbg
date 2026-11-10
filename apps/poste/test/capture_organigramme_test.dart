import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/theme.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/feuilles.dart';
import 'package:sigh_poste/impression/fiche_organigramme.dart';
import 'package:sigh_poste/impression/pdf.dart';

import 'aide_polices.dart';

/// Outil de contrôle VISUEL de l'organigramme imprimé : écrit le PDF et les captures de l'aperçu dans le dossier donné par SIGH_CAPTURES.
/// Ne tourne que sur demande : `SIGH_CAPTURES=/chemin flutter test test/capture_organigramme_test.dart`.
final String? _sortie = Platform.environment['SIGH_CAPTURES'];

void main() {
  tearDown(IdentiteClinique.reinitialiser);

  testWidgets('capture : PDF et aperçu de l’organigramme du jeu livré', skip: _sortie == null, (t) async {
    await chargerPolices();
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
    final fiche = fichePaysageOrganigramme(m, utilisateur: 'BAGUIDI Rafiou', edite: DateTime(2026, 11, 10, 9, 30), reference: 'CBG-20261110-0001');
    final p = (await t.runAsync(PolicesPdf.charger))!;
    final octets = (await t.runAsync(() => pdfFichePaysage(fiche, p)))!;
    File('$_sortie/organigramme.pdf').writeAsBytesSync(octets);

    t.view.physicalSize = const Size(1200, 1700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        theme: ThemeSigh.clair(),
        home: Scaffold(body: SingleChildScrollView(child: RepaintBoundary(key: const Key('cap'), child: FeuilleFichePaysage(fiche: fiche))))));
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 400)));
    await t.pump();
    await t.runAsync(() async {
      final RenderRepaintBoundary b = t.renderObject(find.byKey(const Key('cap')));
      final ui.Image img = await b.toImage(pixelRatio: 1.5);
      final d = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$_sortie/organigramme-apercu.png').writeAsBytesSync(d!.buffer.asUint8List());
    });
  });
}
