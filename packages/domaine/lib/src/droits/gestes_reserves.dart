/// LES GESTES RÉSERVÉS : un droit PAR GESTE, porté par la fiche de rôle (lot B, Direction du 13/11/2026).
///
/// Un geste qui engage un professionnel nommé n'est pas une liste de rôles écrite dans un écran : c'est un droit de la fiche `rbac` du rôle
/// (`droitsGestes.<geste>`, vrai ou faux), accordé PAR RÔLE (jamais par agent), que le référentiel ci-dessous ne donne d'origine qu'à la liste `rolesDefaut`.
/// Même mécanisme que les catégories de données sensibles ([DroitsSensibles]) : évalué À CHAQUE appel depuis les fiches, rien n'est mis en cache, une décision
/// prise à l'instant vaut à la lecture suivante, sans redémarrage.
///
///  * UNE SURCHARGE ACCORDE AUTANT QU'ELLE RETIRE : `true` accorde (même à un rôle absent de `rolesDefaut`, l'administrateur système compris), `false` retire
///    (même au rôle d'origine), absent suit l'origine ;
///  * « un rôle sans fiche a tous les droits » vaut pour les ÉCRANS, jamais pour un geste réservé : l'administrateur système, qui n'a pas de fiche, n'a donc PAS
///    ce droit d'origine, et aucune exception de nom de rôle n'est écrite nulle part ;
///  * un rôle archivé n'a aucun geste, un écran ou un module fermé retire le geste à TOUS les rôles ;
///  * le droit n'ouvre PAS l'écran du geste : l'écran se règle à part (« Régler écran par écran »).
library;

import 'a_chaud.dart' show surchargesParRole;

/// Un geste réservé : son identifiant (clé du droit), ce qu'il autorise, l'écran qui le porte et les rôles qui le détiennent d'origine.
class GesteReserve {
  const GesteReserve({required this.id, required this.libelle, required this.module, required this.ecran, required this.rolesDefaut, this.aide = ''});
  final String id;
  final String libelle;
  final String module;
  final String ecran;

  /// Les rôles qui détiennent le geste sans aucune décision. Un rôle créé en exploitation n'y figure pas : il part de zéro.
  final List<String> rolesDefaut;
  final String aide;
}

/// Valider un seuil de variation brutale du laboratoire : au Biologiste médical d'origine (réponse de la Direction du 13/11/2026).
const String gesteValiderSeuil = 'valider_seuil_labo';

/// Valider un seuil de variation PAR INTÉRIM, avec la fonction de technicien de laboratoire : la fonction est portée par le rôle du Biologiste médical, et non
/// par un rôle propre. Personne ne le détient d'origine (le technicien est exclu par défaut) ; l'accorder au rôle sous lequel le technicien se connecte l'ouvre
/// à ses techniciens. Il s'ajoute à [gesteValiderSeuil] : il ne le remplace pas.
const String gesteValiderSeuilInterim = 'valider_seuil_labo_interim';

/// Le référentiel des gestes réservés. Une donnée du domaine : le code l'interroge, il ne recopie jamais ses identifiants ni ses rôles d'origine.
const List<GesteReserve> gestesReserves = [
  GesteReserve(
      id: gesteValiderSeuil,
      libelle: 'Valider un seuil de variation brutale du laboratoire',
      module: 'M5',
      ecran: 'm5-valeurs-reference',
      rolesDefaut: ['laborantin'],
      aide: 'Rend un seuil opposable : sans lui, un seuil enregistré reste sans effet. Origine : le Biologiste médical.'),
  GesteReserve(
      id: gesteValiderSeuilInterim,
      libelle: 'Valider un seuil de variation brutale avec la fonction de technicien de laboratoire',
      module: 'M5',
      ecran: 'm5-valeurs-reference',
      rolesDefaut: [],
      aide: 'Le technicien de laboratoire est exclu par défaut. Accordé à un rôle, ses agents de fonction technicien peuvent valider un seuil (en plus du droit précédent).'),
];

GesteReserve? gesteReserve(String id) {
  for (final g in gestesReserves) {
    if (g.id == id) return g;
  }
  return null;
}

/// La clé du droit dans une décision (`geste.<id>`) ; dans la fiche : `droitsGestes.<id>`.
String drCleGeste(String id) => 'geste.$id';

/// Les droits sur les gestes réservés, évalués À CHAQUE appel depuis les fiches `rbac` et la matrice EN FORCE.
class DroitsGestes {
  /// [fiches] : la collection `rbac`. [estArchive] : le rôle est-il archivé (matrice en force) ? [ecranActif] : `(écran, module) → bool`, l'activité est-elle
  /// ouverte ? `null` = non branché (réputé ouvert : un test nu).
  DroitsGestes({required Iterable<Map<String, Object?>> fiches, bool Function(String role)? estArchive, bool Function(String ecran, String module)? ecranActif})
      : _sur = surchargesParRole(fiches),
        _archive = estArchive,
        _actif = ecranActif;

  final Map<String, Map<String, Object?>> _sur;
  final bool Function(String role)? _archive;
  final bool Function(String ecran, String module)? _actif;

  /// La décision EXPLICITE de la clinique pour ce rôle et ce geste (`null` : aucune, l'origine s'applique).
  bool? decision(String role, String geste) {
    final m = _sur[role]?['droitsGestes'];
    if (m is! Map) return null;
    final v = m[geste];
    return v is bool ? v : null;
  }

  /// L'origine : le rôle est-il dans la liste d'origine du geste ? Geste inconnu : refusé.
  bool defaut(String role, String geste) => gesteReserve(geste)?.rolesDefaut.contains(role) ?? false;

  /// Le rôle détient-il ce geste ? Rôle vide, geste inconnu, rôle archivé, écran ou module fermé : non.
  bool peut(String role, String geste) {
    final g = gesteReserve(geste);
    if (g == null || role.isEmpty) return false;
    if (_archive?.call(role) ?? false) return false;
    if (!(_actif?.call(g.ecran, g.module) ?? true)) return false;
    return decision(role, geste) ?? defaut(role, geste);
  }

  /// `origine` ou `decide` : d'où vient le droit (écran d'administration).
  String origine(String role, String geste) => decision(role, geste) == null ? 'origine' : 'decide';

  /// Les rôles de [roles] qui détiennent le geste (liste DÉRIVÉE du droit, jamais recopiée).
  List<String> rolesAvec(String geste, Iterable<String> roles) => [
        for (final r in roles)
          if (peut(r, geste)) r
      ];
}
