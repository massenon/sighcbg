import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/impression/feuilles.dart';
import 'package:sigh_poste/impression/piece.dart';

import 'aide_polices.dart';

/// Tableaux imprimés (aperçu) : TOUTES les cellules d'une même rangée ont la hauteur de la plus haute, et le texte démarre au même niveau
/// (règle unique : texte aligné EN HAUT de la cellule). Défaut d'origine (10-11/11/2026) : chaque cellule était un conteneur de hauteur propre,
/// les bordures se décalaient d'une colonne à l'autre dès qu'une cellule passait sur deux lignes.
PieceA4 _piece() => PieceA4(
      titre: 'Sélection — naissances',
      reference: 'CBG-20261110-0001',
      utilisateur: 'Test',
      edite: DateTime(2026, 11, 10),
      tableaux: [
        TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Date et heure', valeur: (r) => r['d']),
          ColonneEtat(libelle: 'Mère', valeur: (r) => r['m']),
          ColonneEtat(libelle: 'Sexe', valeur: (r) => r['s']),
          ColonneEtat(libelle: 'Poids', valeur: (r) => r['p'], droite: true, somme: (r) => r['p'] as num),
        ], lignes: const [
          {'d': '14/10/2026\nà 08h50', 'm': 'A', 's': 'Féminin', 'p': 3100},
          {'d': '15/10/2026', 'm': 'B\nC\nD', 's': 'Masculin', 'p': 2900},
        ]),
      ],
    );

void main() {
  setUpAll(chargerPolices);

  testWidgets('aperçu : cellules d’une rangée de même hauteur, texte au même niveau', (t) async {
    t.view.physicalSize = const Size(1400, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Inter'),
        home: Scaffold(body: SingleChildScrollView(child: Align(alignment: Alignment.topLeft, child: FeuilleA4(piece: _piece()))))));
    await t.pump();
    final table = t.renderObject<RenderTable>(find.byKey(const Key('impression:tableau')));
    expect(table.rows, 4, reason: 'en-tête + 2 lignes + total');
    for (var y = 0; y < table.rows; y++) {
      final cellules = table.row(y).toList();
      expect(cellules.length, 4);
      final hauteurs = cellules.map((c) => c.size.height).toSet();
      expect(hauteurs.length, 1, reason: 'rangée $y : hauteurs ${cellules.map((c) => c.size.height).toList()}');
      // le texte démarre au même niveau dans toutes les cellules de la rangée
      final hauts = <double>{};
      for (final c in cellules) {
        late RenderParagraph p;
        void cherche(RenderObject o) {
          if (o is RenderParagraph) { p = o; return; }
          o.visitChildren(cherche);
        }
        cherche(c);
        hauts.add(double.parse(p.localToGlobal(Offset.zero).dy.toStringAsFixed(1)));
      }
      expect(hauts.length, 1, reason: 'rangée $y : le texte ne démarre pas au même niveau : $hauts');
    }
  });
}
