import 'package:sigh_domaine/sigh_domaine.dart';

import 'contexte_ecran.dart';

/// Les droits sur les GESTES RÉSERVÉS, EN FORCE pour l'écran : fiches `rbac` et matrice (rôle archivé, écran ou module fermé), relus à CHAQUE appel, jamais mis en cache.
DroitsGestes gestesEcran(ContexteEcran c) {
  final mat = c.donnees?.matrice;
  return DroitsGestes(fiches: c.magasin.collection('rbac').actives, estArchive: mat?.estArchive, ecranActif: mat?.ecranActif);
}

/// Le rôle de la SESSION détient-il ce GESTE RÉSERVÉ ? Lu À CHAQUE appel des fiches `rbac` et de la matrice en force (rôle archivé, écran ou module fermé), jamais mis en cache : une décision de
/// la clinique vaut à la lecture suivante. Aucun nom de rôle n'est écrit ici : l'origine est celle du référentiel `gestesReserves`.
bool gestePeutEcran(ContexteEcran c, String geste) => gestesEcran(c).peut(c.role, geste);
