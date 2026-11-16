import 'package:sigh_domaine/sigh_domaine.dart';

/// Des pièces EXISTANTES dont le plus grand rang vaut [rang] dans la série [serie] (aucune si [rang] vaut 0) : les tests de numérotation qui disaient « n fiches
/// déjà écrites » disent désormais « le plus grand rang porté est n » — la règle du 17/11/2026 (le PLUS GRAND rang + 1, jamais le nombre de fiches).
List<Map<String, Object?>> piecesAuRang(String serie, int rang, {Object? date}) =>
    rang == 0 ? const [] : [{Numerotation.semence(serie).champ: numeroFormate(serie, date: date ?? '2026-06-01', rang: rang)}];
