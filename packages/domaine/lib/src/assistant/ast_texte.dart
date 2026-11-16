/// L'ASSISTANT (lots AST-0 et AST-1) : le texte. Normalisation sans casse ni accents, distance d'édition BORNÉE, tolérance selon la longueur du mot.
///
/// Dart pur, aucune importation hors `dart:core` : le module est étanche par construction (aucun réseau, aucun fichier, aucun processus) et un test
/// (`assistant_etancheite_test.dart`) échoue si une dépendance de ce genre s'y glisse.
library;

const Map<String, String> _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
  'ô': 'o', 'ö': 'o', 'ò': 'o', 'ó': 'o', 'õ': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ç': 'c', 'ñ': 'n', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae',
};

/// Sans casse ni accents ; tout ce qui n'est pas lettre ou chiffre devient une espace (apostrophe, tiret, ponctuation), espaces réduites.
String astNormaliser(String texte) {
  final b = StringBuffer();
  for (final r in texte.runes) {
    final c = String.fromCharCode(r).toLowerCase();
    b.write(_accents[c] ?? c);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Distance d'édition (la transposition de deux lettres voisines compte pour une faute), BORNÉE : rend [borne] + 1 dès que la distance la dépasse.
int astDistance(String a, String b, int borne) {
  if ((a.length - b.length).abs() > borne) return borne + 1;
  var avant2 = List<int>.filled(b.length + 1, 0);
  var avant = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cour = List<int>.filled(b.length + 1, 0)..[0] = i;
    var mini = cour[0];
    for (var j = 1; j <= b.length; j++) {
      final cout = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = _min3(avant[j] + 1, cour[j - 1] + 1, avant[j - 1] + cout);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        final t = avant2[j - 2] + 1;
        if (t < v) v = t;
      }
      cour[j] = v;
      if (v < mini) mini = v;
    }
    if (mini > borne) return borne + 1;
    avant2 = avant;
    avant = cour;
  }
  return avant[b.length] > borne ? borne + 1 : avant[b.length];
}

int _min3(int a, int b, int c) => a < b ? (a < c ? a : c) : (b < c ? b : c);

/// Les fautes tolérées selon la longueur du mot ATTENDU : aucune sous cinq lettres (« lit », « lot », « prix » ne se confondent pas), une jusqu'à sept, deux au-delà.
int astTolerance(int longueur) => longueur < 5 ? 0 : (longueur < 8 ? 1 : 2);

/// Les abréviations d'agent, généralistes : remplacées avant la reconnaissance.
const Map<String, String> astAbreviations = {
  'stk': 'stock', 'cb': 'combien', 'qte': 'quantite', 'fact': 'facture', 'factu': 'facture', 'ordo': 'ordonnance', 'compta': 'comptabilite', 'nb': 'nombre',
  'pat': 'patient', 'assu': 'assurance', 'inv': 'inventaire', 'fourn': 'fournisseur', 'lab': 'laboratoire', 'mvt': 'mouvement', 'peremp': 'peremption',
};

/// `AAAA-MM-JJ`.
String astIso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
