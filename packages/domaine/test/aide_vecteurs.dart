// Aides communes des tests qui rejouent des vecteurs engendrés par la maquette.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart' show IdentiteClinique;
import 'package:test/test.dart';

/// LA MAQUETTE NUMÉROTE SOUS LE SIGLE « CNT » (codes patient `CNT/n/AA`, pièces `… /CNT/…`, références `CNT-…`, fichiers `sigh-cnt-…`) : ses
/// vecteurs portent ce sigle. Le logiciel, lui, préfixe avec le sigle EN VIGUEUR (`IdentiteClinique.sigle`, CBG par défaut). Pour rejouer un vecteur de
/// numérotation, le fichier applique le sigle de la maquette le temps de chaque test, puis rend l'identité initiale. Le sigle par défaut et la
/// surcharge sont sondés à part (identite_clinique_test.dart).
void sousLeSigleDeLaMaquette() {
  setUp(() => IdentiteClinique.appliquer({'sigle': 'CNT'}));
  tearDown(IdentiteClinique.reinitialiser);
}

/// Le JEU DE DONNÉES livré (`apps/poste/assets/donnees/jeu`) est encore celui de la Clinique Nassiera Too : un autre lot le remplacera. Quand un test
/// compare au jeu une chaîne qui porte l'IDENTITÉ légale (devise d'un modèle de message, nom du logiciel), il passe la valeur du jeu par la même
/// substitution que `tools/baguidi/substitution-identite.mjs` (copie fidèle de sa liste, dans le même ordre). Une fois le jeu remplacé, la
/// substitution ne trouve plus rien et ne change rien.
String identiteBaguidi(String texte) {
  const nbsp = ' ';
  const substitutions = [
    ('CLINIQUE NASSIERA TOO SARL', 'CLINIQUE BAGUIDI «$nbsp' 'L’AS DE CŒUR$nbsp»'),
    ('CLINIQUE NASSIERA TOO', 'CLINIQUE BAGUIDI'),
    ('Votre santé, notre raison de vivre.', 'Votre bien-être est notre raison d’être.'),
    ('Votre santé, notre raison de vivre', 'Votre bien-être est notre raison d’être.'),
    ('BP : 507 NATITINGOU (Rép. du Bénin)', '02 BP : 105 PARAKOU (Rép. du Bénin)'),
    ('01 95 44 51 51  /  01 66 43 28 20', '95 74 69 56  /  95 95 99 14  /  97 09 34 99'),
    ('01 95 44 51 51 / 01 66 43 28 20', '95 74 69 56 / 95 95 99 14 / 97 09 34 99'),
    ('cliniquenassiera@gmail.com', 'cliniquebaguidi@yahoo.fr'),
    ('3201642748214', '3201001996110'),
    ('RB/NAT/2016-B-268', 'RB/PKO/17 A 4240 du 19/03/2009'),
    ('SIGH-CNT', 'SIGH-CBG'),
    ('Quartier Tchirimina, Natitingou', 'Quartier Zongo II, Parakou'),
    ('Fait à Natitingou', 'Fait à Parakou'),
    ('60 33 92 92', '95 74 69 56'),
  ];
  var t = texte;
  for (final (a, b) in substitutions) {
    t = t.replaceAll(a, b);
  }
  return t;
}

List<Map<String, Object?>> liste(Object? v) =>
    ((v ?? const []) as List).map((x) => (x as Map).cast<String, Object?>()).toList();

Map<String, Object?> lireVecteurs(String nom) {
  final f = File('test/vecteurs/$nom.json');
  if (!f.existsSync()) fail('vecteurs absents : lancer le script de prototype_html/build qui engendre $nom.json');
  return (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
}

/// Compare [obtenu] à [attendu] champ par champ (les champs `_…` et ceux de [ignorer] sont laissés de côté) ; les nombres se comparent en valeur.
void memes(Object? obtenu, Object? attendu, String chemin,
    {Set<String> ignorer = const {}, bool sousEnsemble = false}) {
  if (attendu is Map) {
    final o = (obtenu as Map?) ?? const {};
    for (final k in sousEnsemble ? attendu.keys : {...attendu.keys, ...o.keys}) {
      if (ignorer.contains(k) || '$k'.startsWith('_')) continue;
      memes(o[k], attendu[k], '$chemin.$k', ignorer: ignorer, sousEnsemble: sousEnsemble);
    }
  } else if (attendu is List) {
    final o = obtenu as List;
    expect(o.length, attendu.length, reason: '$chemin : longueur');
    for (var i = 0; i < attendu.length; i++) {
      memes(o[i], attendu[i], '$chemin[$i]', ignorer: ignorer, sousEnsemble: sousEnsemble);
    }
  } else if (attendu is num) {
    expect(obtenu is num ? obtenu.toDouble() : obtenu, attendu.toDouble(), reason: chemin);
  } else {
    expect(obtenu, attendu, reason: chemin);
  }
}
