// Extrait du CODE la liste exacte des gestes réservés et des paramètres de clinique, pour les annexes du manuel administrateur.
// Aucune liste n'est recopiée à la main : le manuel lit ce que le domaine déclare.
//
// Depuis la racine du dépôt (après `flutter pub get` dans apps/poste) :
//   dart --packages=apps/poste/.dart_tool/package_config.json docs/manuels/src/admin/outils/extraire_references.dart > docs/manuels/src/admin/references.json
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

void main() {
  final roles = <String, String>{};
  final rbac = jsonDecode(File('apps/poste/assets/donnees/rbac.json').readAsStringSync()) as Map;
  for (final r in (rbac['roles'] as List).cast<Map>()) {
    roles['${r['id']}'] = '${r['label']}';
  }
  final sortie = {
    'gestes': [
      for (final g in gestesReserves)
        {
          'id': g.id,
          'libelle': g.libelle,
          'module': g.module,
          'ecran': g.ecran,
          'rolesDefaut': [for (final r in g.rolesDefaut) roles[r] ?? r],
          'suitEcran': g.suitEcran,
          'aide': g.aide,
        }
    ],
    'familles': libellesFamillesParametres,
    'parametres': [
      for (final d in definitionsParametres)
        {
          'cle': d.cle,
          'famille': d.famille,
          'type': d.type.name,
          // Un réglage de CONTACT (coordonnées de personnes) ne livre JAMAIS sa valeur d'attente à l'annexe : « à renseigner par la clinique » (E4704).
          'defaut': d.cle.startsWith('support.editeur') ? '' : (d.defaut is Duration ? '${d.defaut}' : d.defaut),
          if (d.cle.startsWith('support.editeur')) 'contact': true,
          'libelle': d.libelle,
          'choix': d.choix,
          'libellesChoix': d.libellesChoix,
          'branche': d.branche,
          'sensible': d.sensible,
          'aide': d.aide,
          'source': d.source,
        }
    ],
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(sortie));
}
