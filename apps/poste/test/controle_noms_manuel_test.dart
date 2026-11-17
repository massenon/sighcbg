import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// AUCUNE PERSONNE RÉELLE DANS LES MANUELS : le jeu livré (assets/donnees/jeu/personnel.json) porte les vrais agents de la clinique. Ce contrôle lit leurs
/// noms et prénoms et échoue si l'un d'eux paraît dans le texte d'un manuel (manuel.html, catalogue.html) ou dans les repères JSON des captures
/// (libellés de boutons, infobulles, onglets, clés). Le nom de famille qui est aussi la dénomination de la clinique n'est cherché qu'accolé à un prénom.
/// Les captures elles-mêmes sont gardées au moment du rendu (capture_manuel_test.dart refuse d'écrire une image où un texte porte un de ces noms).
List<String> nomsReels() {
  final personnel = (jsonDecode(File('assets/donnees/jeu/personnel.json').readAsStringSync()) as List).cast<Map>();
  final noms = <String>{};
  for (final p in personnel) {
    final nom = '${p['nom'] ?? ''}'.trim(), prenom = '${p['prenom'] ?? ''}'.trim();
    if (nom.length >= 3 && nom.toUpperCase() != 'BAGUIDI') noms.add(nom);
    if (prenom.length >= 3) noms.add(prenom);
    if (nom.isNotEmpty && prenom.isNotEmpty) noms.add('$nom $prenom');
  }
  return noms.toList();
}

/// Un nom trouvé comme MOT entier (« Peace » ne doit pas lever sur « Peacekeeping »), sans tenir compte de la casse.
List<String> trouves(String texte, List<String> noms) => [
      for (final n in noms)
        if (RegExp('(?<![\\p{L}])${RegExp.escape(n)}(?![\\p{L}])', caseSensitive: false, unicode: true).hasMatch(texte)) n
    ];

void main() {
  final noms = nomsReels();
  final manuels = Directory('../../docs/manuels/src');

  test('le jeu livré porte bien des noms à chercher (sinon le contrôle ne contrôlerait rien)', () {
    expect(noms, isNotEmpty);
  });

  test('aucun nom réel du personnel dans le texte des manuels', () {
    final fautes = <String>[];
    for (final f in manuels.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.html'))) {
      final t = trouves(f.readAsStringSync(), noms);
      if (t.isNotEmpty) fautes.add('${f.path} : ${t.join(', ')}');
    }
    expect(fautes, isEmpty, reason: fautes.join('\n'));
  });

  test('aucun nom réel du personnel dans les repères des captures', () {
    final fautes = <String>[];
    for (final f in manuels.listSync(recursive: true).whereType<File>().where((f) => f.path.contains('captures') && f.path.endsWith('.json'))) {
      final t = trouves(f.readAsStringSync(), noms);
      if (t.isNotEmpty) fautes.add('${f.path} : ${t.join(', ')}');
    }
    expect(fautes, isEmpty, reason: fautes.join('\n'));
  });
}
