// Écrit `test/vecteurs/garanties_avant.json` : le résultat de la prise en charge sur le jeu de `jeu_garanties.dart`, tel que le moteur le rendait AVANT les garanties datées.
// Lancé UNE fois, sur le moteur d'avant (commit 2197feda) ; ne se relance pas : le fichier est la mesure de référence, il ne se regénère pas à partir du code d'après.
// Usage : `dart run test/outils/releve_garanties_avant.dart` depuis packages/domaine.
import 'dart:convert';
import 'dart:io';

import 'jeu_garanties.dart';

void main() {
  final r = releve();
  final totalA = r.fold<double>(0, (a, x) => a + (x['partAssureur'] as double));
  final totalP = r.fold<double>(0, (a, x) => a + (x['partPatient'] as double));
  File('test/vecteurs/garanties_avant.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
    'moteur': 'avant garanties datées (2197feda)',
    'pieces': r.length,
    'lignes': r.fold<int>(0, (a, x) => a + (x['lignes'] as List).length),
    'partAssureurTotale': totalA,
    'partPatientTotale': totalP,
    'releve': r,
  }));
  stdout.writeln('pièces ${r.length}, part assureur $totalA, part patient $totalP');
}
