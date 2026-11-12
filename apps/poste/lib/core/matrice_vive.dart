import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import 'donnees_navigation.dart';

/// LA MATRICE EN FORCE, LUE À CHAQUE ÉVALUATION (10/11/2026) : la graine engendrée (`rbac.json`) superposée aux décisions de droits du magasin (`rbac`,
/// `modulesActifs`, spécialités). Ce qui sert de droits hors de la coque — l'échange entre pairs, le jugement des décisions par la mère — la lit ici plutôt que de
/// capturer une matrice au démarrage : une capture serait figée au jour du lancement, et une décision prise ensuite ne vaudrait que pour les écrans.
///
/// Le calcul est mémoïsé, mais la mémoïsation tombe à la moindre écriture des collections de droits : l'évaluation suivante repart de la fiche en base.
class MatriceVive {
  MatriceVive(this.base, this.magasin) {
    for (final n in const ['rbac', 'modulesActifs', 'specialites']) {
      magasin.collection(n).addListener(_invalider);
    }
  }
  final DonneesNavigation base;
  final Magasin magasin;
  DonneesNavigation? _cache;

  /// Combien de fois la matrice a été recalculée (les tests s'en servent : une écriture de droits DOIT la faire repartir).
  int calculs = 0;

  void _invalider() => _cache = null;

  DonneesNavigation get donnees {
    final c = _cache;
    if (c != null) return c;
    calculs++;
    return _cache = base.aChaud(magasin);
  }

  MatriceDroits get matrice => donnees.matrice;
  bool peutEditer(String role, String ecran) => matrice.peutEditer(role, ecran);
  bool peutAnnuler(String role, String ecran) => matrice.peutAnnuler(role, ecran);
  bool peutVoir(String role, String ecran) => matrice.peutVoir(role, ecran);

  @visibleForTesting
  void oublier() => _invalider();
}
