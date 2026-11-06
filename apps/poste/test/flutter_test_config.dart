import 'dart:async';

import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/shell/coque.dart';

/// Les bancs écrits avant le 03/11/2026 supposent la mise en page « panneau du méga-menu ouvert » (hauteurs de liste, éléments construits). Ils la gardent ;
/// le défaut LIVRÉ (panneau replié) est mesuré par `coque_test.dart`, qui le rétablit.
///
/// De même, les bancs des écrans de M1 à M5 (et des statistiques et tableaux de bord cliniques) éprouvent ces écrans comme si la clinique les rouvrait :
/// le périmètre livré de la Clinique Baguidi (fiches MOD03 à MOD09 du jeu) ne s'y applique pas ; `fermetures_baguidi_test.dart` le rétablit et le mesure.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  CoquePoste.panneauOuvertAuDemarrage = true;
  DonneesNavigation.appliquerPerimetreLivre = false;
  await testMain();
}
