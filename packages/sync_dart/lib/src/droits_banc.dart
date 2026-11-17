/// LES DROITS DU BANC D'ESSAI, LUS D'UN FICHIER DE DONNÉES (`packages/sync/banc/droits-banc.json`) : aucun nom de rôle n'est écrit dans le code Dart. Le même fichier est
/// lu par la référence Node (`banc/pair.js`) et recopié dans les vecteurs du domaine (`pair.json`, clé `droits`) : une seule source pour les trois.
/// Ce ne sont PAS les droits réels : la production passe par la matrice `rbac.json` (`droitsDepuisMatrice`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

/// Cherche `packages/sync/banc/droits-banc.json` du dossier courant vers la racine. [chemin] non vide : ce fichier-là.
File? trouverFichierDroitsBanc(String chemin) {
  if (chemin.isNotEmpty) return File(chemin);
  var d = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    final c = File('${d.path}/packages/sync/banc/droits-banc.json');
    if (c.existsSync()) return c;
    d = d.parent;
  }
  return null;
}

/// La table du banc, lue du fichier. Refus nommé (`StateError`) si le fichier est introuvable ou illisible : une mère qui démarrerait sans droits les accorderait à tous,
/// ou à personne, sans le dire.
DroitsOperation chargerDroitsBanc([String chemin = '']) {
  final f = trouverFichierDroitsBanc(chemin);
  if (f == null || !f.existsSync()) throw StateError('droits du banc introuvables (droits-banc.json) : indiquer --droits-banc=chemin ou lancer depuis le dépôt');
  try {
    final t = ((jsonDecode(f.readAsStringSync()) as Map)['droits'] as Map)
        .map((c, ts) => MapEntry('$c', (ts as Map).map((ty, r) => MapEntry('$ty', [for (final x in r as List) '$x']))));
    return droitsDepuisTable(t);
  } catch (e) {
    throw StateError('droits du banc illisibles (${f.path}) : $e');
  }
}
