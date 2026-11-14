// Calcule, pour des rôles NOUVEAUX, ce que la matrice engendrée (`rbac.json`) doit porter : les droits par écran et par module, déduits du manifeste et des
// fiches RBAC par le MÊME moteur que le poste (`superposerDroits`), dans l'état de l'extraction (activités fermées de `modulesActifs.reference.json`).
// La maquette qui engendrait `rbac.json` n'est plus dans ce dépôt : un rôle ajouté s'y ajoute par ce calcul, rejouable.
//
// Usage (depuis packages/domaine) : dart run tool/calculer_roles_matrice.dart <sortie.json> <role> [<role>…]
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

Map<String, Object?> json(String f) => (jsonDecode(File(f).readAsStringSync()) as Map).cast<String, Object?>();
List<Map<String, Object?>> fiches(String f) => [for (final x in jsonDecode(File(f).readAsStringSync()) as List) (x as Map).cast<String, Object?>()];

void main(List<String> args) {
  final sortie = args.first;
  final roles = args.skip(1).toList();
  final manifeste = Manifeste.depuisJson(json('../referentiels/data/manifeste.json'));
  final base = MatriceDroits.depuisJson(json('../rbac/data/rbac.json'));
  final mat = superposerDroits(base, manifeste,
      rbac: fiches('../../apps/poste/assets/donnees/rbac.reference.json'),
      modulesActifs: fiches('../../apps/poste/assets/donnees/modulesActifs.reference.json'));
  final out = <String, Object?>{};
  for (final r in roles) {
    final ecrans = {
      for (final e in manifeste.tousLesEcrans)
        if (!e.hub && mat.peutVoir(r, e.id)) e.id: [1, mat.droit(r, e.id).editer ? 1 : 0, mat.droit(r, e.id).annuler ? 1 : 0],
    };
    final modules = <String, Set<String>>{};
    for (final e in manifeste.tousLesEcrans) {
      if (!e.hub && mat.peutVoir(r, e.id)) (modules[e.module] ??= {}).add(e.id);
    }
    out[r] = {'ecrans': ecrans, 'modulesAvecEcranVisible': {for (final e in modules.entries) e.key: e.value.length}};
  }
  File(sortie).writeAsStringSync(jsonEncode(out));
  stdout.writeln('${roles.length} rôle(s) calculé(s) → $sortie');
}
