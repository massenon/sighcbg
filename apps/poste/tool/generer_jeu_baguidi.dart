// LE GÉNÉRATEUR DU JEU DE DÉMONSTRATION BAGUIDI (J12, Direction, 08/11/2026).
//
// Point d'entrée. Il tourne SOUS FLUTTER, pas sous `dart run` : le magasin du poste importe `package:flutter`, donc `dart:ui`, que la machine virtuelle
// Dart seule n'a pas. Depuis `apps/poste` :
//
//   flutter test tool/generer_jeu_baguidi.dart
//
// écrit un fichier JSON par collection dans `assets/donnees/jeu/` (variable d'environnement JEU_SORTIE pour un autre dossier). Voir `tool/README.md`.
//
// L'ORDRE DES ÉTAPES est celui des dépendances : le socle (référentiels), les personnes, la clinique (qui produit les patients), les RH et la paie, puis le
// stock, la caisse et la comptabilité (qui lisent tout ce qui précède). Chaque sous-lot ne touche QUE son fichier `module_*.dart`, déjà branché ici.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'jeu_baguidi/contexte.dart';
import 'jeu_baguidi/module_clinique.dart' as clinique;
import 'jeu_baguidi/module_rh_paie.dart' as rh_paie;
import 'jeu_baguidi/module_stock_finance.dart' as stock_finance;
import 'jeu_baguidi/personnes.dart' as personnes;
import 'jeu_baguidi/socle.dart' as socle;

/// Les étapes, dans l'ordre. Une étape est une fonction `generer(Contexte)` ; elle lit ce que les précédentes ont écrit.
final List<(String, void Function(Contexte))> etapes = [
  ('socle', socle.generer),
  ('personnes', personnes.generer),
  ('clinique', clinique.generer),
  ('rh_paie', rh_paie.generer),
  ('stock_finance', stock_finance.generer),
];

/// Construit le jeu en mémoire : nom de fichier → contenu. Pure : ne touche pas au disque (hors lecture de la référence et du plan comptable).
Map<String, String> construireJeu({Contexte? contexte}) {
  final ctx = contexte ?? Contexte.demarrer();
  for (final (nom, etape) in etapes) {
    etape(ctx);
  }
  return ctx.sortie();
}

/// Écrit le jeu dans [dossier] (créé au besoin). Ne réécrit pas un fichier dont le contenu n'a pas changé. Rend le nombre de fichiers écrits.
int ecrireJeu(Map<String, String> fichiers, String dossier) {
  Directory(dossier).createSync(recursive: true);
  var ecrits = 0;
  for (final e in fichiers.entries) {
    final f = File('$dossier/${e.key}');
    if (f.existsSync() && f.readAsStringSync() == e.value) continue;
    f.writeAsStringSync(e.value);
    ecrits++;
  }
  return ecrits;
}

void main() {
  test('génère le jeu de démonstration Baguidi', () {
    final sortie = Platform.environment['JEU_SORTIE'] ?? 'assets/donnees/jeu';
    final ctx = Contexte.demarrer();
    final fichiers = construireJeu(contexte: ctx);
    final ecrits = ecrireJeu(fichiers, sortie);
    final vides = fichiers.entries.where((e) => e.value == '[]\n').length;
    // ignore: avoid_print
    print([...ctx.notes, '${fichiers.length} fichiers dans $sortie ($ecrits réécrits, $vides collections vides)'].join('\n'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
