import 'package:sigh_domaine/sigh_domaine.dart';

import 'contexte_ecran.dart';

/// Les GESTES RÉSERVÉS en force pour l'écran : fiches `rbac` et matrice en force (rôle archivé, écran ou module fermé), lues À CHAQUE appel, jamais mises en cache : une décision de la clinique
/// vaut à la lecture suivante. Aucun nom de rôle n'est écrit ici : l'origine est celle du référentiel `gestesReserves`.
DroitsGestes droitsGestesEcran(ContexteEcran c) {
  final mat = c.donnees?.matrice;
  return DroitsGestes(fiches: c.magasin.collection('rbac').actives, estArchive: mat?.estArchive, ecranActif: mat?.ecranActif);
}

/// Le rôle de la SESSION détient-il ce GESTE RÉSERVÉ ? (voir [droitsGestesEcran]).
bool gestePeutEcran(ContexteEcran c, String geste) => droitsGestesEcran(c).peut(c.role, geste);
