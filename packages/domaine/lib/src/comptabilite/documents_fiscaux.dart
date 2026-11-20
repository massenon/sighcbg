/// LA LIASSE FISCALE DÉPOSÉE ET LE CLASSEUR 2025 SONT DES DONNÉES, PAS DU CODE (décision de la Direction de Baguidi du 16/11/2026, DECISIONS-16-11 § 9 : « ce sont des DONNÉES DÉPOSÉES,
/// pas des réglages ; elles quittent le code pour la base, sous forme d'IMPORT DATÉ — source, date de dépôt, auteur »).
///
/// Une liasse (le formulaire déposé à la DGI : bilan, compte de résultat, flux, notes) et un classeur de baseline (le compte de résultat de l'exercice de référence) sont des FICHES de la
/// collection [colDocumentsFiscaux] : `genre`, `exercice`, `dateEffet` (la date de dépôt du document), `source` (d'où il vient), `importeLe` et `importePar` (qui l'a posé, quand), `contenu`
/// (le document tel que déposé, jamais recalculé). Un document ne se réécrit pas : un dépôt rectifié est une NOUVELLE fiche d'une date d'effet plus récente, la plus récente fait foi
/// (même doctrine que les versions de paramètres). Les écrans la lisent comme toute donnée ; aucune constante ne la porte plus.
///
/// REGISTRE DE PROCESSUS, comme `Numerotation` et `ListesReference` : le poste le branche sur la collection au démarrage. Sans fiche, rien n'est inventé : [DocumentsFiscaux.liasse] est une structure VIDE
/// (exercices 0, aucune ligne) et [DocumentsFiscaux.importee] le dit, pour que l'écran écrive « aucune liasse importée » plutôt que de montrer des zéros qui se liraient comme des soldes.
library;

/// Mention portée par la règle d'écran de chaque écran qui lit la liasse ou le classeur 2025 tant que le document en base est celui de DÉMONSTRATION (décision du 08/11/2026).
const String cpbMentionDemonstration = 'Données de démonstration, à remplacer par la liasse réellement déposée par la clinique.';

/// La collection des documents fiscaux déposés (famille R : la mère l'écrit, les fileuls la reçoivent).
const String colDocumentsFiscaux = 'documentsFiscaux';

/// Les genres de document.
const String docFiscalLiasse = 'liasse';
const String docFiscalClasseur = 'classeur';

/// La fiche d'un import daté. [dateDepot] est AAAA-MM-JJ ; [importeLe] est la date du geste d'import ; [source] dit d'où vient le document (obligatoire : un chiffre sans origine ne se cite pas).
Map<String, Object?> docFiscalFiche({
  required String genre,
  required int exercice,
  required String dateDepot,
  required String source,
  required String auteur,
  required String importeLe,
  required Map<String, Object?> contenu,
}) {
  if (genre != docFiscalLiasse && genre != docFiscalClasseur) throw ArgumentError('genre de document fiscal inconnu : $genre');
  if (source.trim().isEmpty) throw ArgumentError('un document fiscal importé porte sa source');
  if (auteur.trim().isEmpty) throw ArgumentError('aucune action anonyme (RG-12) : l\'import porte son auteur');
  return {
    'id': 'doc-fiscal-$genre-$exercice-$dateDepot',
    'genre': genre,
    'exercice': exercice,
    'dateEffet': dateDepot,
    'source': source,
    'importeLe': importeLe,
    'importePar': auteur,
    'contenu': contenu,
    'statut': 'actif',
  };
}

class DocumentsFiscaux {
  DocumentsFiscaux._();

  static Iterable<Map<String, Object?>> Function()? _fiches;

  /// Branche le registre sur la collection (le poste : `collection('documentsFiscaux').toutes`). Le dernier branchement l'emporte.
  static void brancher(Iterable<Map<String, Object?>> Function() fiches) => _fiches = fiches;

  /// Débranche (test).
  static void debrancher() => _fiches = null;

  /// La fiche EN FORCE d'un genre : parmi les fiches non archivées, la plus récente par date d'effet, puis par date d'import, puis par identifiant ; `null` si aucune.
  static Map<String, Object?>? fiche(String genre) {
    Map<String, Object?>? meilleure;
    for (final f in _fiches?.call() ?? const <Map<String, Object?>>[]) {
      if (f['statut'] == 'archive' || f['genre'] != genre || f['contenu'] is! Map) continue;
      if (meilleure == null || _cle(f).compareTo(_cle(meilleure)) > 0) meilleure = f;
    }
    return meilleure;
  }

  static String _cle(Map<String, Object?> f) => '${f['dateEffet'] ?? ''}|${f['importeLe'] ?? ''}|${f['id'] ?? ''}';

  /// Un document de ce genre est-il importé ?
  static bool importee(String genre) => fiche(genre) != null;

  /// Le contenu de la liasse déposée en force, ou la structure VIDE (jamais d'exception : l'écran dit qu'il n'y en a pas).
  static Map<String, Object?> get liasse {
    final f = fiche(docFiscalLiasse);
    return f == null ? _liasseVide : (f['contenu'] as Map).cast<String, Object?>();
  }

  /// Le contenu du classeur de baseline en force, ou `null`.
  static Map<String, Object?>? get classeur {
    final f = fiche(docFiscalClasseur);
    return f == null ? null : (f['contenu'] as Map).cast<String, Object?>();
  }

  /// D'où vient la liasse en force (source, dates, auteur), pour que l'écran le dise ; `null` si aucune.
  static Map<String, Object?>? get provenanceLiasse => _provenance(fiche(docFiscalLiasse));
  static Map<String, Object?>? get provenanceClasseur => _provenance(fiche(docFiscalClasseur));

  static Map<String, Object?>? _provenance(Map<String, Object?>? f) =>
      f == null ? null : {'source': f['source'], 'dateDepot': f['dateEffet'], 'importeLe': f['importeLe'], 'importePar': f['importePar'], 'exercice': f['exercice']};
}

const Map<String, Object?> _liasseVide = {
  'DEPOT': {
    'denomination': '',
    'ifu': '',
    'dateDepot': '',
    'code': '',
    'exerciceN': 0,
    'exerciceN1': 0,
    'administration': '',
    'source': 'Aucune liasse déposée n’est importée en base.',
    'demonstration': '',
  },
  'BILAN_ACTIF': [],
  'BILAN_PASSIF': [],
  'RESULTAT': [],
  'FLUX': [],
  'DISPONIBILITES': {'note': '', 'lignes': [], 'commentaires': [], 'nb': ''},
  'SYNTHESE': [],
  'NOTES_SYNTHESE': [],
  'ECARTS': [],
};
