/// Le CONTEXTE d'une question (qui la pose, ce qu'il peut lire) et la RÉPONSE de l'assistant. L'assistant est en LECTURE SEULE : le contexte ne porte AUCUNE fonction
/// d'écriture — un exécuteur n'a, par construction, que de quoi lire. Les fiches rendues sont GELÉES (cartes et listes non modifiables) : écrire dedans lève une erreur
/// et le test d'étanchéité aux écritures en fait un échec.
library;

import '../droits/donnees_sensibles.dart';
import '../labo/res_habilitations.dart' show SessionLabo;
import 'ast_texte.dart';

typedef FicheAst = Map<String, Object?>;

/// Lit une collection du magasin (fiches actives ou non : l'archivage logique est filtré ici, RG-14). Le seul accès aux données.
typedef LireAst = List<Map<String, Object?>> Function(String collection);

/// Gèle récursivement une valeur lue : cartes et listes non modifiables.
Object? astGeler(Object? v) {
  if (v is Map) return Map<String, Object?>.unmodifiable({for (final e in v.entries) '${e.key}': astGeler(e.value)});
  if (v is List) return List<Object?>.unmodifiable([for (final x in v) astGeler(x)]);
  return v;
}

/// Ce que l'assistant lit de la MATRICE au-delà du rôle de la session — en LECTURE SEULE, jamais un nom de rôle comparé : les rôles en force (archivés écartés), leur
/// libellé, qui voit un écran, qui détient un geste réservé (`DroitsGestes`), les écrans d'un module (manifeste). Sert à dire « en attente de la validation de <poste> »
/// sans nommer un poste en dur, et à répondre « quels rôles ouvrent les écrans de la paie ». `null` (test nu, poste sans matrice) : les réponses qui en dépendent le DISENT.
class MatriceAst {
  const MatriceAst({required this.roles, required this.libelleRole, required this.roleVoit, required this.roleDetient, required this.ecransDuModule});
  final List<String> Function() roles;
  final String Function(String role) libelleRole;
  final bool Function(String role, String ecran) roleVoit;
  final bool Function(String role, String geste) roleDetient;
  final List<String> Function(String module) ecransDuModule;

  /// Les libellés des rôles qui détiennent [geste] (matrice en force, décisions de la clinique comprises).
  List<String> titulaires(String geste) => [for (final r in roles()) if (roleDetient(r, geste)) libelleRole(r)];
}

class ContexteAst {
  ContexteAst({
    required this.role,
    required this.lire,
    required this.peutVoirEcran,
    required this.sensibles,
    required this.maintenant,
    this.session,
    this.patientContexte,
    this.libelleEcran,
    this.etatSynchro,
    this.matrice,
  });

  /// Le rôle de la session : transmis aux moteurs de droits, JAMAIS comparé à un nom.
  final String role;
  final LireAst lire;

  /// La matrice EN FORCE (ruban, écran universel, fermeture de module comprises) : `(écran) → bool` pour ce rôle.
  final bool Function(String ecran) peutVoirEcran;
  final DroitsSensibles sensibles;
  final DateTime maintenant;

  /// Fonction et secteur de l'agent : les habilitations métier du résultat (`peutVoirResultat`).
  final SessionLabo? session;

  /// Le dernier patient de la conversation (« ce patient »), fourni par la conversation, jamais deviné.
  final String? patientContexte;
  final String Function(String ecran)? libelleEcran;

  /// L'état de la synchronisation du poste, s'il le sait. `null` : l'assistant ne le lit pas.
  final String? Function()? etatSynchro;

  /// La matrice au-delà de la session (gestes réservés, autres rôles) : lue, jamais écrite. `null` : non branchée, dit dans la réponse.
  final MatriceAst? matrice;

  /// Le rôle de la session détient-il le geste réservé [geste] ? Sans matrice : `null` (on ne sait pas, et la réponse le dit — jamais « oui » par défaut).
  bool? detient(String geste) => matrice?.roleDetient(role, geste);

  String get jour => astIso(maintenant);

  /// Une fiche d'aide RÉSERVÉE à des rôles (la liste `roles` est une DONNÉE de la fiche, jamais un nom écrit ici) ne se montre qu'à eux ; sans liste, elle est pour tous.
  bool roleAutorise(Iterable<Object?> roles) {
    final liste = {for (final r in roles) '$r'};
    return liste.isEmpty || liste.intersection({role}).isNotEmpty;
  }

  /// Les fiches ACTIVES d'une collection, gelées.
  List<FicheAst> col(String nom) => [
        for (final f in lire(nom))
          if (f['statut'] != 'archive') astGeler(f) as FicheAst
      ];

  bool voit(Iterable<String> ecrans) => ecrans.any(peutVoirEcran);
  bool sensible(String categorie) => sensibles.peut(role, categorie);
  String ecran(String id) => libelleEcran?.call(id) ?? id;
}

/// Une source citée : l'écran (lien profond, seulement si l'agent le voit) et la collection lue.
class SourceAst {
  const SourceAst(this.ecran, this.collection);
  final String ecran;
  final String collection;
  Map<String, Object?> toJson() => {'ecran': ecran, 'collection': collection};
  @override
  bool operator ==(Object o) => o is SourceAst && o.ecran == ecran && o.collection == collection;
  @override
  int get hashCode => Object.hash(ecran, collection);
}

class TableauAst {
  const TableauAst(this.colonnes, this.lignes);
  final List<String> colonnes;
  final List<List<String>> lignes;
  Map<String, Object?> toJson() => {'colonnes': colonnes, 'lignes': lignes};
}

/// La réponse. Toujours l'un de : `reponse` (calculée sur des enregistrements lus), `refus` (code nommé), `non_calculable` (la donnée manque, la raison est dite),
/// `pas_de_donnees` (la lecture est vide), `precision` (un paramètre manque), `ambigue`, `non_comprise`.
class ReponseAst {
  const ReponseAst({
    required this.statut,
    required this.titre,
    this.code,
    this.intention,
    this.lignes = const [],
    this.tableau,
    this.sources = const [],
    this.geste,
    this.ecranRenvoi,
    this.propositions = const [],
    this.patientCode,
  });

  final String statut;
  final String titre;
  final String? code;
  final String? intention;
  final List<String> lignes;
  final TableauAst? tableau;
  final List<SourceAst> sources;
  final String? geste;

  /// L'écran vers lequel la réponse renvoie (écriture refusée, rapport à ouvrir) : retiré si l'agent ne le voit pas.
  final String? ecranRenvoi;
  final List<String> propositions;

  /// Le patient dont la réponse parle (un seul, jamais deviné) : la conversation s'en sert pour « ce patient ».
  final String? patientCode;

  bool get estRefus => statut == 'refus';

  ReponseAst avec({List<SourceAst>? sources, String? ecranRenvoi, bool retirerRenvoi = false, String? patientCode, String? intention}) => ReponseAst(
      statut: statut, titre: titre, code: code, intention: intention ?? this.intention, lignes: lignes, tableau: tableau, sources: sources ?? this.sources, geste: geste,
      ecranRenvoi: retirerRenvoi ? null : (ecranRenvoi ?? this.ecranRenvoi), propositions: propositions, patientCode: patientCode ?? this.patientCode);

  Map<String, Object?> toJson() => {
        'statut': statut,
        'titre': titre,
        if (code != null) 'code': code,
        if (intention != null) 'intention': intention,
        if (lignes.isNotEmpty) 'lignes': lignes,
        if (tableau != null) 'tableau': tableau!.toJson(),
        'sources': [for (final s in sources) s.toJson()],
        if (geste != null) 'geste': geste,
        if (ecranRenvoi != null) 'ecranRenvoi': ecranRenvoi,
        if (propositions.isNotEmpty) 'propositions': propositions,
        if (patientCode != null) 'patientCode': patientCode,
      };

  static ReponseAst depuisJson(Map<String, Object?> j) => ReponseAst(
        statut: '${j['statut']}',
        titre: '${j['titre']}',
        code: j['code'] as String?,
        intention: j['intention'] as String?,
        lignes: [for (final x in (j['lignes'] as List? ?? const [])) '$x'],
        tableau: j['tableau'] is Map
            ? TableauAst([for (final c in ((j['tableau'] as Map)['colonnes'] as List)) '$c'], [for (final l in ((j['tableau'] as Map)['lignes'] as List)) [for (final c in (l as List)) '$c']])
            : null,
        sources: [for (final s in (j['sources'] as List? ?? const [])) SourceAst('${(s as Map)['ecran']}', '${s['collection']}')],
        geste: j['geste'] as String?,
        ecranRenvoi: j['ecranRenvoi'] as String?,
        propositions: [for (final x in (j['propositions'] as List? ?? const [])) '$x'],
        patientCode: j['patientCode'] as String?,
      );
}
