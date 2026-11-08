import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/impression/feuilles.dart';
import 'package:sigh_poste/impression/pdf.dart';
import 'package:sigh_poste/impression/piece.dart';

import 'aide_polices.dart';

/// Impression : géométrie des gabarits contre la maquette (`references/kit/impression.json`), contenu du ticket identique (vecteurs, test du
/// domaine), PDF structurellement valide aux dimensions physiques (80 mm / A4). Le texte du PDF n'est pas relu (glyphes encodés) : on contrôle
/// la structure ; la fidélité du contenu est portée par les listes de lignes communes à l'aperçu et au PDF.
late Map<String, dynamic> ref;
final date = DateTime(2026, 10, 30, 14, 5);

final entree = EntreeTicket(
  operateur: 'A',
  numero: 'F-1',
  date: date,
  dossier: 'CBG/12/26',
  lignes: const [
    LigneArticle(
        designation: 'Consultation',
        quantite: 1,
        prixUnitaire: 3000,
        montant: 3000)
  ],
  total: 3000,
  partPatient: 3000,
  regle: 3000,
);

final piece = PieceA4(
  titre: 'État de test',
  reference: 'CBG-20261030-0001',
  utilisateur: 'ADJAHO Rose',
  edite: date,
  tableaux: [
    TableauEtat(colonnes: [
      ColonneEtat(libelle: 'Désignation', valeur: (r) => r['d']),
      ColonneEtat(
          libelle: 'Montant',
          valeur: (r) => r['m'],
          droite: true,
          somme: (r) => r['m'] as num),
    ], lignes: const [
      {'d': 'A', 'm': 1000},
      {'d': 'B', 'm': 250}
    ])
  ],
  signatures: const [Signature('Le Caissier'), Signature('La DAF')],
);

Future<void> monter(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1400, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Inter'),
      home: Scaffold(
          body: SingleChildScrollView(
              child: Align(alignment: Alignment.topLeft, child: w)))));
  await t.pump();
}

void main() {
  setUpAll(() async {
    await chargerPolices();
    ref = jsonDecode(
            File('test/references/kit/impression.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  testWidgets(
      'ticket : 80 mm de large, hauteur proche de la maquette, lignes du domaine',
      (t) async {
    // La géométrie se compare à la maquette, qui imprime une formule de politesse : on en pose une le temps de la mesure.
    IdentiteClinique.appliquer({'formulePolitesse': 'MERCI DE VOTRE CONFIANCE'});
    addTearDown(IdentiteClinique.reinitialiser);
    await monter(t, FeuilleTicket(entree: entree, reference: 'CBG-1'));
    final r = t.getRect(find.byKey(const Key('impression:ticket')));
    expect(r.width, closeTo((ref['ticket']['l'] as num).toDouble(), 0.5));
    final h = (ref['ticket']['h'] as num).toDouble();
    expect(r.height, closeTo(h, h * 0.08),
        reason: 'ticket ${r.height} vs ${ref['ticket']['h']}');
    expect(find.text('MONTANT TOTAL'), findsOneWidget);
    expect(find.text('trois mille francs CFA'), findsOneWidget);
    expect(find.text('MERCI DE VOTRE CONFIANCE'), findsOneWidget);
    expect(find.text('CLINIQUE BAGUIDI'), findsOneWidget);
  });

  testWidgets('ticket sans formule de politesse (identité initiale) : aucune ligne de formule, aucune trace de Nassiera Too', (t) async {
    await monter(t, FeuilleTicket(entree: entree, reference: 'CBG-1'));
    expect(find.textContaining('DIEU'), findsNothing);
    expect(find.textContaining('NASSIERA'), findsNothing);
    expect(find.text('IFU ${IdentiteClinique.ifu}'), findsOneWidget);
  });

  testWidgets(
      'A4 : 210 × 297 mm, en-tête légal unique, titre, tableau avec total refait, pied normalisé',
      (t) async {
    // La géométrie se compare à la maquette, dont l'en-tête porte une autorisation d'ouverture : on en pose une le temps de la mesure.
    IdentiteClinique.appliquer({'autorisation': 'N° 012/MS/DNSP/2009'});
    addTearDown(IdentiteClinique.reinitialiser);
    await monter(t, FeuilleA4(piece: piece));
    final a4 = t.getRect(find.byKey(const Key('impression:a4')));
    expect(a4.width, closeTo((ref['a4']['l'] as num).toDouble(), 0.5));
    expect(a4.height, greaterThanOrEqualTo(mm(297) - 0.5));
    final e = t.getRect(find.byKey(const Key('impression:entete')));
    // L'en-tête n'a plus la hauteur de la maquette Nassiera Too (titre centré) : il suit le papier en trois zones de Baguidi (P0-13).
    expect(e.height, greaterThan(mm(24)), reason: 'au moins la hauteur du logo de 2,4 cm');
    expect(e.width, closeTo((ref['entete']['l'] as num).toDouble(), 1));
    final ti = t.getRect(find.byKey(const Key('impression:titre')));
    expect(ti.height, closeTo((ref['titre']['h'] as num).toDouble(), 6));
    final pied = t.getRect(find.byKey(const Key('impression:pied')));
    expect(pied.height, closeTo((ref['pied']['h'] as num).toDouble(), 6));
    // L'identité légale est imprimée une fois, depuis le domaine.
    expect(
        find.textContaining('IFU : ${IdentiteClinique.ifu} du ${IdentiteClinique.ifuDate}'), findsOneWidget);
    expect(
        find.textContaining('RCCM : ${IdentiteClinique.rccm}'), findsOneWidget);
    // Le total est calculé : 1000 + 250.
    expect(find.text('1 250'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(
        find.textContaining(
            'Document généré par ADJAHO Rose le 30/10/2026 à 14h05'),
        findsOneWidget);
    expect(find.text('Réf. document : CBG-20261030-0001'), findsOneWidget);
    expect(find.text('Autorisation d’ouverture : N° 012/MS/DNSP/2009'), findsOneWidget);
    expect(find.text('Édité depuis le SIGH-CBG'), findsOneWidget);
    expect(find.textContaining('Fait à Parakou, le '), findsOneWidget, reason: 'la ville de l’adresse de la clinique, jamais Natitingou');
  });

  testWidgets('A4, identité initiale : l’autorisation d’ouverture VIDE n’imprime ni sa ligne ni son libellé ; l’en-tête raccourcit d’autant', (t) async {
    await monter(t, FeuilleA4(piece: piece));
    expect(find.textContaining('AUTORISATION'), findsNothing);
    expect(find.text(IdentiteClinique.nom), findsOneWidget);
    expect(find.text(IdentiteClinique.bp), findsOneWidget);
    expect(find.text(IdentiteClinique.slogan), findsOneWidget);
    expect(find.textContaining('NASSIERA'), findsNothing);
    expect(find.textContaining('Natitingou'), findsNothing);
  });

  test('référence de pièce <SIGLE>-AAAAMMJJ-NNNN : le sigle de la clinique (CBG), jamais écrit en dur', () {
    expect(PieceA4.reference_(date, 7), 'CBG-20261030-0007');
    IdentiteClinique.appliquer({'sigle': 'XYZ'});
    addTearDown(IdentiteClinique.reinitialiser);
    expect(PieceA4.reference_(date, 7), 'XYZ-20261030-0007');
  });

  testWidgets('PDF : ticket 80 mm et A4 structurellement valides', (t) async {
    final p = await t.runAsync(PolicesPdf.charger);
    final tk = (await t
        .runAsync(() => pdfTicket(entree, 'CBG-1', p!, compresser: false)))!;
    final a4 = (await t.runAsync(() => pdfA4(piece, p!, compresser: false)))!;
    String txt(List<int> b) => latin1.decode(b);
    expect(txt(tk.sublist(0, 5)), '%PDF-');
    expect(txt(a4.sublist(0, 5)), '%PDF-');
    expect(txt(tk.sublist(tk.length - 6)).trim(), '%%EOF');
    // MediaBox : 80 mm = 226,77 pt ; A4 = 595,28 × 841,89 pt.
    final box = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]');
    final mt = box.firstMatch(txt(tk))!;
    expect(double.parse(mt.group(1)!), closeTo(226.77, 0.1));
    final ma = box.firstMatch(txt(a4))!;
    expect(double.parse(ma.group(1)!), closeTo(595.28, 0.1));
    expect(double.parse(ma.group(2)!), closeTo(841.89, 0.1));
    expect(RegExp(r'/Type\s*/Page\b').hasMatch(txt(a4)), isTrue);
  });
}
