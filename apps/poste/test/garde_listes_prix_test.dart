import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// GARDE : AUCUNE LECTURE DIRECTE D'UNE ANCIENNE LISTE DE PRIX (lot TFIN, T7 ; même règle que `garde-listes-prix.js` de la maquette de la clinique sœur).
///
/// Les collections `actes` et `catalogueTarifs`, la colonne `prix` du catalogue `analyses` et le `tarif` des `typesChambre` ne sont plus que des PROJECTIONS ou des SEMENCES du référentiel de
/// prix unique (`tarifs` / `versionsTarif`) : leur prix est celui d'ORIGINE, figé. Le lire hors des accesseurs datés, c'est afficher ou facturer un prix périmé en silence. Un prix se lit
/// par `TarifsPoste.prixActe`, `prixAnalyse`, `prixGrille`, `actes()`, `analyses()`, `typesChambre()`, `entreeGrille()` / `grille()` (le prix EN VIGUEUR à la date de la pièce).
///
/// Règle : pour chaque mention d'une de ces listes (`collection('actes')`, `referentiel('analyses')`, la constante de domaine `hosTypesChambre`…) dans `apps/poste/lib` et `packages/domaine/lib`, l'EXPRESSION qui la porte — et, quand
/// elle est affectée à une variable, les [fenetre] lignes suivantes — ne doit pas lire de propriété de prix (`prix`, `tarif`, `prixNonAssure`, `prixAssure`). Une mention sans lecture de prix
/// (désignation, code, effectif) est admise. Un fichier de la LISTE BLANCHE ci-dessous lit légitimement (accesseur, semis, migration, import, catalogue qui ÉDITE sa propre colonne) ; une ligne
/// marquée `garde-prix:` (avec sa raison) l'est aussi. Toute nouvelle lecture échoue ici, nommée « fichier:ligne ».
const fenetre = 14;

/// Les lecteurs légitimes, chacun avec sa raison. Ajouter une ligne ici est une décision, pas un contournement.
const listeBlanche = <String, String>{
  'apps/poste/lib/donnees/tarifs_poste.dart': 'LES accesseurs datés eux-mêmes (projections `actes()`, `analyses()`, `typesChambre()`) et la migration des anciennes listes',
  'packages/domaine/lib/src/tarifs/tarifs.dart': 'le moteur du référentiel : construit le semis depuis les anciennes listes',
  'packages/domaine/lib/src/import/jeux_import.dart': 'import : les jeux d\'import des anciennes collections sont reversés dans le référentiel',
  'packages/domaine/lib/src/configuration/cfb_donnees.dart': 'nomenclature des collections (noms, pas de prix lus)',
};

final _liste = RegExp(r'''\b(?:collection|referentiel)\(\s*'(actes|analyses|catalogueTarifs|typesChambre)'\s*\)|\b(hosTypesChambre)\b''');
final _prix = RegExp(r'''(?:\.|\[\s*')(prix|tarif|prixNonAssure|prixAssure)\b''');

List<File> _sources(String dir) => [
      for (final f in Directory(dir).listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f
    ];

/// Retire les commentaires (leur texte est blanchi, les sauts de ligne restent) : une phrase de doc qui cite `a['prix']` n'est pas du code.
String _sansCommentaires(String s) {
  s = s.replaceAllMapped(RegExp(r'/\*[\s\S]*?\*/'), (m) => m[0]!.replaceAll(RegExp(r'[^\n]'), ' '));
  return s.replaceAllMapped(RegExp(r'''(^|[^:\\'"`])//[^\n]*'''), (m) => '${m[1]}${' ' * (m[0]!.length - m[1]!.length)}');
}

/// L'expression qui commence en [debut] : jusqu'à `;` ou `,` de profondeur zéro, en suivant les chaînes `.x` / `[i]` qui prolongent une parenthèse fermée.
String _phrase(String src, int debut) {
  var prof = 0, i = debut;
  for (; i < src.length; i++) {
    final c = src[i];
    if ('([{'.contains(c)) {
      prof++;
    } else if (')]}'.contains(c)) {
      prof--;
      if (prof < 0) break;
    } else if (prof == 0 && (c == ';' || c == ',')) {
      break;
    }
  }
  return src.substring(debut, i);
}

List<String> analyser(String racine, List<String> dirs) {
  final fautes = <String>[];
  for (final dir in dirs) {
    for (final f in _sources('$racine/$dir')) {
      final rel = f.path.substring(racine.length + 1);
      if (listeBlanche.containsKey(rel)) continue;
      final brut = f.readAsStringSync();
      final lignesBrutes = brut.split('\n');
      final src = _sansCommentaires(brut);
      final lignes = src.split('\n');
      for (final m in _liste.allMatches(src)) {
        final ligne = '\n'.allMatches(src.substring(0, m.start)).length;
        if (lignesBrutes[ligne].contains('garde-prix:')) continue;
        final phrase = _phrase(src, m.start);
        var lu = _prix.firstMatch(phrase);
        // Affectée à une variable : ce que les lignes suivantes font de cette variable compte aussi.
        final avant = src.substring(src.lastIndexOf('\n', m.start) + 1, m.start).replaceFirst(RegExp(r'[\w.?!]*$'), '');
        final aff = RegExp(r'(?:final|var)\s+(?:[\w<>?,\s]+\s)?(\w+)\s*=\s*$').firstMatch(avant) ?? RegExp(r'\b(\w+)\s*=\s*$').firstMatch(avant);
        // Les variables qui portent la liste : celle qui l'affecte, et les variables de boucle qui la parcourent ensuite.
        final vars = <String>{if (aff != null) aff[1]!};
        final boucle = RegExp(r'for\s*\(\s*final\s+(\w+)\s+in\s+\(?\s*$').firstMatch(avant);
        if (boucle != null) vars.add(boucle[1]!);
        if (lu == null && vars.isNotEmpty) {
          final ind = RegExp(r'^\s*').firstMatch(lignes[ligne])![0]!.length;
          for (var k = ligne; k < lignes.length && k < ligne + 1 + fenetre && lu == null; k++) {
            final l = lignes[k];
            if (k > ligne && l.trim().isNotEmpty && RegExp(r'^\s*').firstMatch(l)![0]!.length < ind) break;
            for (final v in {...vars}) {
              final derive = RegExp('for\\s*\\(\\s*final\\s+(\\w+)\\s+in\\s+$v\\b').firstMatch(l);
              if (derive != null) vars.add(derive[1]!);
            }
            for (final v in vars) {
              lu ??= RegExp('\\b$v\\b\\s*(?:\\[\\s*\'|\\.)(prix|tarif|prixNonAssure|prixAssure)\\b').firstMatch(l);
            }
          }
        }
        if (lu != null) fautes.add('$rel:${ligne + 1}  ${m[1] ?? m[2]}  lit  ${lu[0]}');
      }
    }
  }
  return fautes;
}

void main() {
  test('aucune lecture directe d\'une ancienne liste de prix hors des accesseurs datés (liste blanche explicite)', () {
    final racine = Directory.current.path.replaceAll(RegExp(r'/apps/poste$'), '');
    final fautes = analyser(racine, ['apps/poste/lib', 'packages/domaine/lib']);
    expect(fautes, isEmpty, reason: 'le prix se lit par TarifsPoste.prixActe / prixAnalyse / actes() / analyses() / typesChambre() / grille() :\n${fautes.join('\n')}');
  });

  test('la garde SAIT mordre : une lecture directe fabriquée est relevée', () {
    final tmp = Directory.systemTemp.createTempSync('garde');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory('${tmp.path}/d').createSync();
    File('${tmp.path}/d/a.dart').writeAsStringSync("""
void f(m) {
  final x = m.collection('actes').actives.firstWhere((a) => a['code'] == 'MG01')['prix'];
  final t = m.referentiel('typesChambre');
  for (final c in t) { print(c['tarif']); }
  for (final a in m.referentiel('analyses')) print(a['prix']);
  final ok = m.collection('actes').actives.map((a) => a['libelle']);
  final raison = m.collection('analyses').actives.length; // garde-prix: effectif
  final j = hosTypesChambre.firstWhere((t) => t.id == 'vip').tarif;
  // m.collection('actes') a['prix'] dans un commentaire
}
""");
    final fautes = analyser(tmp.path, ['d']);
    expect(fautes.length, 4, reason: fautes.join('\n'));
  });
}
