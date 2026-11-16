import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/jetons_shell.dart';
import 'package:sigh_poste/core/theme.dart';
import 'package:sigh_poste/impression/entete_papier.dart';
import 'package:sigh_poste/impression/feuilles.dart';
import 'package:sigh_poste/impression/pdf.dart';
import 'package:sigh_poste/impression/piece.dart';

import 'aide_polices.dart';

/// Outil de contrôle VISUEL du papier à en-tête (E2) : écrit des PNG dans le dossier donné par SIGH_CAPTURES.
/// Ne tourne que sur demande : `SIGH_CAPTURES=/chemin flutter test test/capture_entete_test.dart`.
final String? _sortie = Platform.environment['SIGH_CAPTURES'];

Future<void> _png(WidgetTester t, Key cle, String nom) async {
  await t.runAsync(() async {
    final RenderRepaintBoundary b = t.renderObject(find.byKey(cle));
    final ui.Image img = await b.toImage(pixelRatio: 1.5);
    final d = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_sortie/$nom').writeAsBytesSync(d!.buffer.asUint8List());
  });
}

void main() {
  tearDown(IdentiteClinique.reinitialiser);
  final i = IdentiteImprimee.depuisFiche(const {});

  testWidgets('capture : aperçu de cfg-branding', skip: _sortie == null, (t) async {
    await chargerPolices();
    t.view.physicalSize = const Size(1000, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        theme: ThemeSigh.clair(),
        home: Scaffold(
            body: Center(
                child: RepaintBoundary(
                    key: const Key('cap'),
                    child: SizedBox(
                        width: 900,
                        child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate300)),
                            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              EnteteLegal(identite: i, echelle: 0.9),
                              const SizedBox(height: 16),
                              const Text('(corps du document)', textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              Text('${EnteteTroisZones.depuis(i).piedLegal} · Document généré par A le 01/11/2026 · Réf. CBG-XXXXXXXX-0001 · ${EnteteTroisZones.depuis(i).editeDepuis}',
                                  style: const TextStyle(fontSize: 8, color: JetonsShell.slate500)),
                            ]))))))));
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    await _png(t, const Key('cap'), 'en-tete-apercu.png');
  });

  testWidgets('capture : feuille A4', skip: _sortie == null, (t) async {
    await chargerPolices();
    t.view.physicalSize = const Size(1000, 1300);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        theme: ThemeSigh.clair(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: RepaintBoundary(
                    key: const Key('cap'),
                    child: FeuilleA4(piece: PieceA4(titre: 'État de démonstration', reference: 'CBG-20261108-0001', utilisateur: 'BICHIASI Cezoune Sichovian', edite: DateTime(2026, 11, 8), identite: i)))))));
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    await _png(t, const Key('cap'), 'en-tete-a4.png');
  });

  testWidgets('capture : PDF A4 (octets écrits)', skip: _sortie == null, (t) async {
    final p = (await t.runAsync(PolicesPdf.charger))!;
    final piece = PieceA4(titre: 'État de démonstration', reference: 'CBG-20261108-0001', utilisateur: 'BICHIASI Cezoune Sichovian', edite: DateTime(2026, 11, 8), identite: i);
    final octets = (await t.runAsync(() => pdfA4(piece, p)))!;
    File('$_sortie/en-tete.pdf').writeAsBytesSync(octets);
  });
}
