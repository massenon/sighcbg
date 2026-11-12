import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';

/// Le PORT d'écriture du moteur d'importation (`PortImport`, packages/domaine) branché sur le magasin du poste. Une écriture refusée par une garde de
/// collection (exercice clos : `EcritureRefusee`) remonte au moteur, qui défait ce qu'il vient de poser.
class PortMagasin extends PortImport {
  PortMagasin(this.magasin, {required this.aujourdhui, required this.nomAgent, required this.profil, this.gardesLevees = false, this.etiquette = ''});
  final Magasin magasin;

  /// Les gardes des collections écrites sont levées pour CE port : l'écriture directe d'un import de configuration à un fileul (« option c », lot IMP-C), dont la mère reste
  /// l'autorité par la demande qui la double. Faux partout ailleurs : la mère, comme les écrans ordinaires, subit les gardes.
  final bool gardesLevees;

  /// L'étiquette du poste, mise dans les identifiants posés par ce port quand les gardes sont levées : une fiche provisoire d'un fileul ne peut ainsi entrer en collision avec aucune
  /// fiche de la mère (sinon la configuration diffusée l'écraserait en silence).
  final String etiquette;

  T _garde<T>(String collection, T Function() f) => gardesLevees ? magasin.collection(collection).sansGardes(f) : f();

  /// Le profil qui importe (droits lus de la matrice en force) : le moteur refuse selon lui. Jamais un nom de rôle ici.
  @override
  final ProfilImport profil;
  final DateTime Function() aujourdhui;
  final String nomAgent;

  static const _prefixes = {
    'produits': 'PRD',
    'lots': 'LOT',
    'mouvements': 'MVT',
    'patients': 'PAT',
    'personnel': 'EMP',
    'actes': 'ACT',
    'examensLabo': 'EXA',
    'fournisseurs': 'F',
    'assureurs': 'ASS',
    'souscripteurs': 'SOU',
    'comptes': 'CPT',
    'ecritures': 'ECR',
    collectionLots: 'LIM',
  };

  @override
  List<FicheImport> toutes(String collection) => magasin.collection(collection).toutes;

  @override
  String get jour {
    final d = aujourdhui();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  String get utilisateur => nomAgent;

  /// L'identifiant suivant : le plus grand rang numérique de la collection, plus un (jamais `longueur + 1` : une fiche retirée ou archivée ne doit pas
  /// faire réattribuer un identifiant).
  String _id(String collection) {
    final p = _prefixes[collection] ?? collection.substring(0, collection.length < 3 ? collection.length : 3).toUpperCase();
    var max = 0;
    for (final f in magasin.collection(collection).toutes) {
      final m = RegExp(r'(\d+)$').firstMatch('${f['id'] ?? ''}');
      final k = m == null ? 0 : int.parse(m[1]!);
      if (k > max) max = k;
    }
    return '$p${etiquette.isEmpty ? '' : '$etiquette-'}${(max + 1).toString().padLeft(4, '0')}';
  }

  @override
  FicheImport inserer(String collection, FicheImport fiche) {
    final col = magasin.collection(collection);
    final r = _garde(collection, () => col.inserer({...fiche, 'id': fiche['id'] ?? _id(collection)}, prefixe: _prefixes[collection] ?? 'ID'));
    // L'auteur et la date de création accompagnent toute fiche (RG-12) : ils s'ajoutent sans repasser par le journal.
    r.fiche['_creePar'] = nomAgent;
    r.fiche['_creeLe'] = magasin.horloge().toIso8601String();
    return r.fiche;
  }

  /// Retire une fiche posée dans CE geste (l'atomicité du lot) : la collection est réécrite sans elle. Jamais pour une fiche publiée.
  @override
  void retirer(String collection, Object? id) {
    final col = magasin.collection(collection);
    col.remplacerContenu([
      for (final f in col.toutes)
        if (f['id'] != id) f
    ]);
  }

  @override
  bool archiver(String collection, Object? id, String motif) {
    try {
      _garde(collection, () => magasin.collection(collection).archiver(id));
      return true;
    } on EcritureRefusee {
      return false;
    }
  }

  @override
  void restaurer(String collection, Object? id) => _garde(collection, () => magasin.collection(collection).restaurer(id));

  @override
  void mettreAJour(String collection, Object? id, FicheImport patch) => _garde(collection, () => magasin.collection(collection).mettreAJour(id, patch));

  @override
  void journaliser(String action, String module, String entite, String reference, Object? avant, Object? apres) =>
      magasin.journaliser(action, module, entite, reference, avant, apres);
}
