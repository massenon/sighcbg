/// LES DÉCISIONS DE DROITS : la matrice n'est jamais figée, et une décision n'écrase jamais rien en silence (Direction, 10/11/2026).
///
/// Une fiche de la collection `rbac` (une par rôle) est un REGISTRE de droits : chaque droit — celui d'un module (`droits.M4`), celui d'un écran
/// (`droitsEcrans.m4-cpn`), un champ du rôle (`champ.statut`, `champ.libelle`…) — est une CLÉ, et chaque clé porte l'horodatage de la décision qui l'a posée
/// en dernier (`cles`). Une DÉCISION (`decisionsDroits`, une fiche immuable par geste) ne porte que les clés qu'elle change, avec la valeur que son auteur
/// avait sous les yeux (`avant`) :
///
///  * la décision la plus RÉCENTE par horodatage de décision l'emporte, clé par clé ; à égalité l'identifiant de décision départage, de sorte que deux
///    postes qui rejouent les mêmes décisions dans un ordre différent aboutissent à la même fiche ;
///  * une décision plus ancienne que celle en vigueur sur une clé n'est PAS appliquée à cette clé : elle est écartée, et le dit (ligne `ecarte`) ;
///  * une clé écrasée alors que sa valeur n'est plus celle que l'auteur avait vue est marquée `concurrent` : deux postes ont décidé sur le même droit, la
///    ligne nomme la décision remplacée (auteur, motif, date) ;
///  * deux décisions sur des droits DIFFÉRENTS d'un même rôle se cumulent : aucune n'efface l'autre ;
///  * tout se journalise (RG-12) : ancien droit, nouveau droit, auteur, motif. Rien ne se supprime (RG-14) : « revenir au défaut d'origine » est une
///    décision de plus, qui réapplique la graine en nouvelle version et laisse l'historique entier.
///
/// Pur et sans magasin : le poste y branche ses collections (`decisionsDroits`, `rbac`), le journal et le transport.
library;

import 'dart:convert';

import 'donnees_sensibles.dart' show categorieSensible;

typedef FicheDr = Map<String, Object?>;

/// La collection des décisions (journal des demandes de modification de droits), diffusée entre les postes comme l'activité.
const String drCollectionDecisions = 'decisionsDroits';

/// L'écran des décisions de droits : l'agent qui décide doit y avoir le droit d'ÉDITER (la mère REFAIT ce contrôle, un bouton absent ne protège rien).
const String drEcranDecision = 'm14-roles';

/// Les champs d'un rôle qui se décident comme des droits.
const List<String> drChampsDuRole = [
  'statut',
  'libelle',
  'libelleCourt',
  'libelleOrigine',
  'couleur',
  'accueil',
  'nouveau',
  'motif',
  'archiveLe',
  'archivePar',
  'motifArchivage',
  'restaureLe',
  'restaurePar',
  'definiLe',
  'definiPar',
];

String drCleModule(String code) => 'droits.$code';
String drCleEcran(String id) => 'droitsEcrans.$id';
String drCleChamp(String nom) => 'champ.$nom';

String _dateIso(DateTime d) => d.toUtc().toIso8601String();

bool _egal(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

Map<String, Object?> _map(Object? v) => v is Map ? v.cast<String, Object?>() : <String, Object?>{};

/// La fiche aplatie en clés de droit : `{clé: valeur}`. Une clé absente n'a pas de décision (le manifeste et la matrice engendrée font foi).
Map<String, Object?> drAplatir(FicheDr? f) {
  if (f == null) return {};
  final out = <String, Object?>{};
  for (final e in _map(f['droits']).entries) {
    out[drCleModule(e.key)] = e.value;
  }
  for (final e in _map(f['droitsEcrans']).entries) {
    out[drCleEcran(e.key)] = e.value;
  }
  for (final e in _map(f['donneesSensibles']).entries) {
    if (e.value is bool) out['sensible.${e.key}'] = e.value;
  }
  for (final n in drChampsDuRole) {
    if (f.containsKey(n) && f[n] != null) out[drCleChamp(n)] = f[n];
  }
  return out;
}

/// Ce que `valeurs` (la forme que l'écran écrit : `droits`, `droitsEcrans` entiers, champs du rôle) change par rapport à [avant] : clé → nouvelle valeur,
/// `null` quand la clé disparaît (un réglage d'écran retiré). Rien d'autre n'est une décision : les clés inchangées ne se touchent pas.
Map<String, Object?> drDiff(FicheDr? avant, Map<String, Object?> valeurs) {
  final a = drAplatir(avant);
  final out = <String, Object?>{};
  if (valeurs['droits'] is Map) {
    for (final e in _map(valeurs['droits']).entries) {
      final k = drCleModule(e.key);
      if (!_egal(a[k], e.value)) out[k] = e.value;
    }
  }
  if (valeurs['droitsEcrans'] is Map) {
    final neufs = _map(valeurs['droitsEcrans']);
    for (final e in neufs.entries) {
      final k = drCleEcran(e.key);
      if (!_egal(a[k], e.value)) out[k] = e.value;
    }
    for (final k in a.keys) {
      if (k.startsWith('droitsEcrans.') && !neufs.containsKey(k.substring('droitsEcrans.'.length))) out[k] = null;
    }
  }
  // Les droits sur les catégories de données sensibles : `{catégorie: true|false|null}` — `null` revient au défaut (la matrice), c'est une clé qui disparaît.
  if (valeurs['donneesSensibles'] is Map) {
    for (final e in _map(valeurs['donneesSensibles']).entries) {
      final k = 'sensible.${e.key}';
      if (!_egal(a[k], e.value) && !(a[k] == null && e.value == null)) out[k] = e.value;
    }
  }
  for (final n in drChampsDuRole) {
    if (!valeurs.containsKey(n)) continue;
    final k = drCleChamp(n);
    final v = valeurs[n];
    if (!_egal(a[k], v) && !(a[k] == null && v == null)) out[k] = v;
  }
  return out;
}

/// Les clés qui ramènent [actuelle] à la graine [graine] : une décision « revenir au défaut d'origine ». Une clé que la graine ne connaît pas disparaît
/// (`null`) ; une clé que la graine porte est remise à sa valeur. La graine est la fiche du jeu livré avec le poste, jamais modifiée.
Map<String, Object?> drChangementsVersGraine(FicheDr? actuelle, FicheDr graine) {
  final a = drAplatir(actuelle), g = drAplatir(graine);
  final out = <String, Object?>{};
  for (final k in {...a.keys, ...g.keys}) {
    if (!_egal(a[k], g[k])) out[k] = g[k];
  }
  return out;
}

/// L'étiquette lisible d'une clé : « module M4 », « écran m4-cpn », « champ statut ».
String drLibelleCle(String cle) {
  if (cle.startsWith('droits.')) return 'module ${cle.substring(7)}';
  if (cle.startsWith('droitsEcrans.')) return 'écran ${cle.substring(13)}';
  if (cle.startsWith('champ.')) return 'champ ${cle.substring(6)}';
  if (cle.startsWith('sensible.')) return 'données sensibles : ${categorieSensible(cle.substring(9))?.libelle ?? cle.substring(9)}';
  return cle;
}

/// Un droit en toutes lettres : « voir, éditer », « fermé », « suit son module » (clé absente).
String drLibelleValeur(String cle, Object? v) {
  if (cle.startsWith('sensible.')) return v == null ? 'suit la matrice (défaut)' : (v == true ? 'visible' : 'masqué');
  if (v == null) return cle.startsWith('droits') ? 'suit la matrice d’origine' : '—';
  if (v is Map) {
    if (v['voir'] != true) return 'fermé';
    final l = <String>['voir', if (v['editer'] == true) 'éditer', if (v['annuler'] == true) 'annuler'];
    return l.join(', ');
  }
  return '$v';
}

/// La décision : une fiche IMMUABLE de `decisionsDroits`, qui voyage du poste qui décide vers la mère. [genre] : `modification` ou `defaut_origine`.
FicheDr drDecision({
  required String id,
  required String role,
  required Map<String, Object?> changements,
  required Map<String, Object?> avant,
  required String motif,
  required String auteur,
  required String poste,
  required DateTime decideLe,
  String? auteurRole,
  String? auteurId,
  int baseVersion = 0,
  String genre = 'modification',
  String? journal,
}) =>
    {
      'id': id,
      // L'identité de la décision voyage dans un champ propre : l'identifiant de la fiche change d'un poste à l'autre en route (le pont le remplace), pas ceci.
      'ident': id,
      'role': role,
      'genre': genre,
      'changements': {...changements},
      'avant': {for (final k in changements.keys) k: avant[k]},
      'motif': motif,
      'auteur': auteur,
      'auteurRole': auteurRole,
      'auteurId': auteurId,
      'poste': poste,
      'decideLe': _dateIso(decideLe),
      'baseVersion': baseVersion,
      'journal': journal,
      'statutDemande': 'en_attente',
    };

/// Une clé de la décision, telle que le moteur l'a jugée.
class LigneDecisionDroits {
  const LigneDecisionDroits({
    required this.cle,
    required this.ancien,
    required this.nouveau,
    required this.appliquee,
    this.concurrent = false,
    this.remplaceeParDecision,
    this.remplaceeParAuteur,
    this.remplaceeParMotif,
    this.remplaceeLe,
  });
  final String cle;
  final Object? ancien, nouveau;

  /// Appliquée à la fiche, ou écartée (une décision plus récente tient déjà cette clé).
  final bool appliquee;

  /// Appliquée alors que la valeur n'était plus celle que l'auteur avait vue : deux décisions sur le même droit.
  final bool concurrent;

  /// Écartée : la décision plus récente qui garde la clé. Concurrente : la décision que celle-ci a remplacée.
  final String? remplaceeParDecision, remplaceeParAuteur, remplaceeParMotif, remplaceeLe;

  Map<String, Object?> toJson() => {
        'cle': cle,
        'ancien': ancien,
        'nouveau': nouveau,
        'statut': appliquee ? 'appliquee' : 'ecartee',
        if (concurrent) 'concurrent': true,
        if (remplaceeParDecision != null) 'autreDecision': remplaceeParDecision,
        if (remplaceeParAuteur != null) 'autreAuteur': remplaceeParAuteur,
        if (remplaceeParMotif != null) 'autreMotif': remplaceeParMotif,
        if (remplaceeLe != null) 'autreLe': remplaceeLe,
      };
}

class ResultatDecisionDroits {
  const ResultatDecisionDroits({required this.fiche, required this.lignes, required this.issue, this.motifRefus});

  /// La fiche du rôle après la décision (`null` quand rien n'a changé et qu'il n'y avait pas de fiche).
  final FicheDr? fiche;
  final List<LigneDecisionDroits> lignes;

  /// `appliquee` · `partielle` (une partie des clés écartée) · `ecartee` (rien d'appliqué : toutes plus anciennes) · `sans_effet` (déjà ainsi) · `refusee`.
  final String issue;
  final String? motifRefus;

  List<LigneDecisionDroits> get appliquees => [for (final l in lignes) if (l.appliquee) l];
  List<LigneDecisionDroits> get ecartees => [for (final l in lignes) if (!l.appliquee) l];
  List<LigneDecisionDroits> get concurrentes => [for (final l in lignes) if (l.concurrent) l];

  /// Ancien et nouveau droit des clés appliquées, pour la ligne du journal d'audit (RG-12).
  Map<String, Object?> get avantJournal => {for (final l in appliquees) drLibelleCle(l.cle): drLibelleValeur(l.cle, l.ancien)};
  Map<String, Object?> get apresJournal => {for (final l in appliquees) drLibelleCle(l.cle): drLibelleValeur(l.cle, l.nouveau)};
}

/// Plus récent que `(le, id)` : l'horodatage d'abord, l'identifiant de décision à égalité.
bool _plusRecent(String le, String id, String leRef, String idRef) {
  final c = le.compareTo(leRef);
  return c != 0 ? c > 0 : id.compareTo(idRef) > 0;
}

/// Applique [decision] à la fiche du rôle ([actuelle], `null` : le rôle n'a pas encore de fiche). Ne modifie rien : rend la fiche NOUVELLE et le détail clé par clé.
/// La fiche rendue porte `version` (+1 si quelque chose a changé), `decideLe` / `decidePar` / `decisionId` et le registre `cles`.
ResultatDecisionDroits drAppliquer(FicheDr? actuelle, FicheDr decision) {
  final id = '${decision['ident'] ?? decision['id']}';
  final le = '${decision['decideLe']}';
  final changements = _map(decision['changements']);
  final vu = _map(decision['avant']);
  final role = '${decision['role']}';
  if (le.isEmpty || DateTime.tryParse(le) == null) {
    return const ResultatDecisionDroits(fiche: null, lignes: [], issue: 'refusee', motifRefus: 'Horodatage de décision absent ou illisible.');
  }
  if ('${decision['motif'] ?? ''}'.trim().isEmpty) {
    return const ResultatDecisionDroits(fiche: null, lignes: [], issue: 'refusee', motifRefus: 'Une décision de droits sans motif ne s’applique pas.');
  }
  final base = actuelle == null ? <String, Object?>{'role': role, 'statut': 'actif'} : {for (final e in actuelle.entries) e.key: e.value};
  final droits = {..._map(base['droits'])};
  final ecrans = {..._map(base['droitsEcrans'])};
  final sensibles = {..._map(base['donneesSensibles'])};
  final cles = {for (final e in _map(base['cles']).entries) e.key: _map(e.value)};
  final courant = drAplatir(actuelle);
  final lignes = <LigneDecisionDroits>[];
  var applique = false;
  var tamponChange = false;
  for (final e in changements.entries) {
    final k = e.key;
    final tampon = cles[k];
    // La même décision rejouée (le transport rend deux fois la même fiche) : rien à dire, rien à écrire.
    if (tampon != null && '${tampon['id']}' == id) continue;
    if (tampon != null && !_plusRecent(le, id, '${tampon['le']}', '${tampon['id']}')) {
      lignes.add(LigneDecisionDroits(
          cle: k,
          ancien: courant[k],
          nouveau: e.value,
          appliquee: false,
          remplaceeParDecision: '${tampon['id']}',
          remplaceeParAuteur: '${tampon['par'] ?? ''}',
          remplaceeParMotif: '${tampon['motif'] ?? ''}',
          remplaceeLe: '${tampon['le']}'));
      continue;
    }
    if (_egal(courant[k], e.value)) {
      // Déjà ainsi : rien à écrire, mais la décision est la plus récente à tenir cette clé.
      cles[k] = {'le': le, 'id': id, 'par': decision['auteur'], 'motif': decision['motif']};
      tamponChange = true;
      continue;
    }
    final concurrent = vu.containsKey(k) && !_egal(vu[k], courant[k]);
    lignes.add(LigneDecisionDroits(
        cle: k,
        ancien: courant[k],
        nouveau: e.value,
        appliquee: true,
        concurrent: concurrent,
        remplaceeParDecision: concurrent && tampon != null ? '${tampon['id']}' : null,
        remplaceeParAuteur: concurrent && tampon != null ? '${tampon['par'] ?? ''}' : null,
        remplaceeParMotif: concurrent && tampon != null ? '${tampon['motif'] ?? ''}' : null,
        remplaceeLe: concurrent && tampon != null ? '${tampon['le']}' : null));
    applique = true;
    if (k.startsWith('droits.')) {
      final code = k.substring(7);
      if (e.value == null) {
        droits.remove(code);
      } else {
        droits[code] = e.value;
      }
    } else if (k.startsWith('droitsEcrans.')) {
      final ec = k.substring(13);
      if (e.value == null) {
        ecrans.remove(ec);
      } else {
        ecrans[ec] = e.value;
      }
    } else if (k.startsWith('sensible.')) {
      final cat = k.substring(9);
      if (e.value == null) {
        sensibles.remove(cat);
      } else {
        sensibles[cat] = e.value;
      }
    } else if (k.startsWith('champ.')) {
      final n = k.substring(6);
      if (e.value == null) {
        base.remove(n);
      } else {
        base[n] = e.value;
      }
    }
    cles[k] = {'le': le, 'id': id, 'par': decision['auteur'], 'motif': decision['motif']};
  }
  final ecartees = lignes.where((l) => !l.appliquee).length;
  if (!applique) {
    // Rien à écrire, mais la décision tient désormais ses clés : une décision plus ancienne qui arriverait après ne pourrait pas les reprendre.
    if (tamponChange) base['cles'] = cles;
    return ResultatDecisionDroits(fiche: tamponChange ? base : null, lignes: lignes, issue: ecartees > 0 ? 'ecartee' : 'sans_effet');
  }
  base['droits'] = droits;
  base['droitsEcrans'] = ecrans;
  if (sensibles.isNotEmpty || base.containsKey('donneesSensibles')) base['donneesSensibles'] = sensibles;
  base['cles'] = cles;
  base['version'] = ((base['version'] as num?)?.toInt() ?? 0) + 1;
  final dernier = '${base['decideLe'] ?? ''}';
  if (dernier.isEmpty || _plusRecent(le, id, dernier, '${base['decisionId'] ?? ''}')) {
    base['decideLe'] = le;
    base['decisionId'] = id;
    base['decidePar'] = decision['auteur'];
  }
  return ResultatDecisionDroits(fiche: base, lignes: lignes, issue: ecartees > 0 ? 'partielle' : 'appliquee');
}

/// Une décision d'un agent est-elle recevable ? `auteurRole` doit pouvoir ÉDITER l'écran des droits ; le motif est obligatoire. Rend le refus nommé, ou `null`.
/// [peutEditer] : `(role, ecran) -> bool`, c'est-à-dire `MatriceDroits.peutEditer` de la matrice EN FORCE chez celui qui juge.
String? drRefusDecision(FicheDr decision, {required bool Function(String role, String ecran) peutEditer}) {
  if ('${decision['motif'] ?? ''}'.trim().isEmpty) return 'Une décision de droits sans motif ne s’applique pas.';
  final r = '${decision['auteurRole'] ?? ''}';
  if (r.isEmpty) return 'Auteur sans rôle connu : la décision ne se rattache à aucun profil habilité.';
  if (!peutEditer(r, drEcranDecision)) {
    return 'Le profil « $r » n’a pas le droit de modifier les droits des rôles (écran « Rôles et permissions »).';
  }
  return null;
}
