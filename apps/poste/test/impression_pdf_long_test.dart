import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/impression/feuilles.dart';
import 'package:sigh_poste/impression/pdf.dart';
import 'package:sigh_poste/impression/piece.dart';

import 'aide_polices.dart';

PieceA4 piece(int n) => PieceA4(
      titre: 'État long', reference: 'CBG-20261114-0001', utilisateur: 'Test', edite: DateTime(2026, 11, 14), tableaux: [
        TableauEtat(colonnes: [
          ColonneEtat(libelle: 'Code', valeur: (r) => r['c']),
          ColonneEtat(libelle: 'Libellé', valeur: (r) => r['l']),
          ColonneEtat(libelle: 'Prix', valeur: (r) => r['p'], droite: true, somme: (r) => r['p'] as num),
        ], lignes: [for (var i = 0; i < n; i++) {'c': 'C$i', 'l': 'Prestation numéro $i', 'p': 1000 + i}]),
      ],
    );

void main() {
  setUpAll(chargerPolices);
  for (final n in [10, 60, 201]) {
    testWidgets('PDF A4 de $n lignes s\'écrit', (t) async {
      final octets = await t.runAsync(() async => pdfA4(piece(n), await PolicesPdf.charger()));
      expect(octets!.length, greaterThan(1000));
    });
  }
}
