// Calcule le ruban (et les cartes de Paramètres) de rôles NOUVEAUX dans la forme des vecteurs `ruban.json`. Rejouable ; voir `calculer_roles_matrice.dart`.
// Usage (depuis packages/domaine) : dart run tool/ruban_roles_vecteur.dart <sortie.json> <role> [<role>…]
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

Map<String, Object?> json(String f) => (jsonDecode(File(f).readAsStringSync()) as Map).cast<String, Object?>();

void main(List<String> args) {
  final manifeste = Manifeste.depuisJson(json('../referentiels/data/manifeste.json'));
  final matrice = MatriceDroits.depuisJson(json('../rbac/data/rbac.json'));
  final cas = <Map<String, Object?>>[];
  for (final role in args.skip(1)) {
    cas.add({
      'role': role,
      'archive': matrice.estArchive(role),
      'domaines': [
        for (final d in manifeste.ruban(matrice, role, estMere: true))
          {
            'domaine': d.nom,
            'rangees': [
              for (final r in d.rangees) {'code': r.code, 'label': r.label, 'hub': r.hub, 'ecrans': [for (final e in r.ecrans) e.id]}
            ]
          }
      ],
      'cartes': [
        for (final d in manifeste.cartesParametres(matrice, role, estMere: true, domaines: {'Système', 'Poste mère', 'Relais en ligne'}))
          {
            'domaine': d.nom,
            'rangees': [
              for (final r in d.rangees) {'code': r.code, 'label': r.label, 'hub': r.hub, 'ecrans': [for (final e in r.ecrans) e.id]}
            ]
          }
      ],
    });
  }
  File(args.first).writeAsStringSync(jsonEncode(cas));
}
