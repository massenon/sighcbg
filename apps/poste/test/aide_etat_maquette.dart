import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';

/// L'ÉTAT DE LA MAQUETTE : les bancs de parité mesurent le poste contre des fiches extraites de la maquette, dont la configuration d'activités est celle de
/// l'extraction (banque de sang et donneurs FERMÉS, fiches MOD01 et MOD02). Le jeu livré ne ferme plus rien depuis le 06/11/2026 (nuit) : on repose ici les deux
/// fiches de référence (`modulesActifs.reference.json`) pour que ces bancs mesurent toujours le même état.
Magasin avecEtatMaquette(Magasin m) {
  final col = m.collection('modulesActifs');
  for (final f in DonneesNavigation.depuisDossier().referenceModules ?? const <Map<String, Object?>>[]) {
    if (col.toutes.every((x) => x['id'] != f['id'])) col.inserer({...f});
  }
  return m;
}
