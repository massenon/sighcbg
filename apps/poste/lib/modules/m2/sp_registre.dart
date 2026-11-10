import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/config_poste.dart';
import '../../shell/contexte_ecran.dart';
import 'sp_commun.dart';
import 'sp_ecrans.dart';

/// LA RÉSOLUTION DES ÉCRANS DE SPÉCIALITÉ. Le registre statique des écrans (`ecransM2`) ne peut pas les nommer : ils naissent de fiches. Un identifiant
/// `spec-<code>[-vue]` dont le code est celui d'une spécialité CONNUE rend le widget générique de sa vue ; tout autre identifiant n'est pas de ce registre.
Widget Function(BuildContext, ConfigPoste)? ecranSpecialitePour(String id, Iterable<String> codes) {
  final r = specAnalyserId(id, codes);
  if (r == null) return null;
  return (contexte, cfg) => switch (r.vue) {
        SpecVue.hub => EcranSpecialiteHub(r.code,
            descriptionFiche: () {
              final m = ContexteEcran.maybeOf(contexte)?.magasin;
              final f = m == null ? null : specialiteDeCode(m, r.code);
              return f == null || '${f['description'] ?? ''}'.isEmpty ? null : '${f['description']}';
            }()),
        SpecVue.consultation => EcranSpecialiteConsultation(r.code),
        SpecVue.agenda => EcranSpecialiteAgenda(r.code),
        SpecVue.stats => EcranSpecialiteStats(r.code),
      };
}
