/// LE RÉFÉRENTIEL DE NUMÉROTATION UNIQUE (lot 2 de l'inventaire des valeurs en dur, famille E, 16/11/2026).
///
/// Toute référence de pièce (bons, commandes, livraisons, factures, avoirs, reçus, ordonnances, CPA, CRA, observations, certificats, missions,
/// transferts, inventaires, écritures…) est construite ICI, par UNE fabrique, qui lit la collection administrable `seriesNumerotation` : une SÉRIE
/// (code stable, jamais affiché) porte son préfixe, l'inclusion de l'année et son format (`AAAA`, `AA`), la place de l'année (avant ou après le rang),
/// le séparateur, la longueur du rang et la remise à 1 annuelle. AUCUN préfixe ni millésime n'est écrit dans un écran ou une règle : l'année vient de la
/// DATE DE LA PIÈCE, jamais de l'horloge du poste ni d'un « 2026 » oublié dans le code — au 1ᵉʳ janvier 2027, chaque série annuelle repart d'elle-même.
///
/// Trois règles, et la troisième commande les deux autres :
///  * les SEMENCES ([seriesNumerotationSemence]) reprennent EXACTEMENT les formats du code au 16/11/2026 : aucune pièce existante ne change de numéro
///    (RG-01, une pièce émise ne se renumérote jamais). Elles sont marquées « à valider » : la Direction arrête ou corrige ;
///  * une modification est une VERSION DATÉE (une fiche immuable par version, `dateEffet` au plus tôt aujourd'hui) : elle ne s'applique qu'aux pièces
///    à venir, les pièces déjà émises gardent leur numéro ; elle se pose sous le geste réservé `numerotation_modifier` (origine proposée :
///    l'administrateur et la Directrice Administrative, à valider) ;
///  * la collection est de la famille R : la MÈRE seule l'écrit ; un poste rattaché DÉPOSE sa modification (`validationsDeposees`), la mère la rejoue
///    sous le rôle de son auteur ([serieAppliquerDepot]).
///
/// La fabrique est un registre de PROCESSUS ([Numerotation.appliquer]) que le poste alimente depuis son magasin, au démarrage et à chaque écriture de
/// la collection — le mécanisme de l'identité de la clinique (`IdentiteClinique.appliquer`). Sans application (tests, outils), les semences font foi.
/// Le code patient (RG-01, `codePatient`) et le Plan de travail annuel ont leurs propres chantiers : ils peuvent s'y brancher par [Numerotation.serie].
library;

import 'semences_numerotation.dart';

export 'semences_numerotation.dart';

/// La collection des versions de séries (famille R).
const String colSeriesNumerotation = 'seriesNumerotation';

/// Les valeurs admises pour l'année d'un numéro.
const String anneeAucune = 'aucune';
const String anneeLongue = 'AAAA';
const String anneeCourte = 'AA';
const List<String> formatsAnnee = [anneeAucune, anneeLongue, anneeCourte];

/// La place de l'année : avant le rang (`BEB-2026-0001`) ou après (`BDG-00001-2026`, `FA-0001/26`).
const String anneeAvant = 'avant';
const String anneeApres = 'apres';

/// Une série SÉQUENTIELLE (préfixe, année, rang) ou DÉRIVÉE (préfixe + une référence qui existe déjà : `AIB-<facture>`, `QUIT-<code>-<exercice>`).
const String genreSequence = 'sequence';
const String genreDerive = 'derive';

/// Les séparateurs admis (un numéro se lit au téléphone et s'écrit sur le papier : pas d'espace, pas de caractère ambigu). Le séparateur VIDE colle le rang
/// au préfixe (`C00012`, `M000123`, `H00004` : les séries courtes de la maquette).
const List<String> separateursAdmis = ['-', '/', '_', '.', ''];

/// Une série de numérotation, dans la version en vigueur à une date.
class SerieNumerotation {
  const SerieNumerotation({
    required this.code,
    required this.libelle,
    required this.module,
    required this.prefixe,
    this.annee = anneeAucune,
    this.positionAnnee = anneeAvant,
    this.separateur = '-',
    this.separateurAnnee,
    this.largeur = 4,
    this.prefixeRang = '',
    this.remiseAnnuelle = false,
    this.genre = genreSequence,
    this.champ = 'reference',
    this.dateEffet,
    this.aValider = true,
    this.note = '',
  });

  /// L'identifiant STABLE de la série (jamais affiché sur une pièce) : c'est lui que le code nomme, jamais le préfixe.
  final String code;
  final String libelle;
  final String module;
  final String prefixe;

  /// `aucune`, `AAAA` ou `AA`.
  final String annee;

  /// `avant` ou `apres` le rang.
  final String positionAnnee;

  /// Entre le préfixe et la suite.
  final String separateur;

  /// Entre l'année et le rang (ou le rang et l'année) ; à défaut, [separateur].
  final String? separateurAnnee;

  /// La longueur du rang (complété de zéros à gauche).
  final int largeur;

  /// Une lettre fixe devant le rang (`C` des contre-passations de clôture : `CL-2026-C00001`).
  final String prefixeRang;

  /// Le rang repart à 1 chaque année (il ne se compare alors qu'aux pièces de la même année).
  final bool remiseAnnuelle;
  final String genre;

  /// Le champ des fiches qui porte le numéro (`reference`, `numero`, `code`…).
  final String champ;

  /// `null` : la semence (depuis l'origine) ; sinon le premier jour où la version s'applique.
  final String? dateEffet;

  /// Semence non encore arrêtée par la Direction.
  final bool aValider;
  final String note;

  String get sepAnnee => separateurAnnee ?? separateur;
  bool get avecAnnee => annee != anneeAucune;

  /// Le millésime tel qu'il s'écrit dans le numéro.
  String anneeTexte(int an) => annee == anneeCourte ? (an % 100).toString().padLeft(2, '0') : annee == anneeLongue ? '$an' : '';

  String get _tete => prefixe.isEmpty ? '' : '$prefixe$separateur';

  /// Le numéro de rang [rang] (un entier, ou un texte déjà composé comme `PROV-…`) pour l'année [an].
  String formater({required int an, required Object rang}) {
    final r = rang is int ? '$rang'.padLeft(largeur, '0') : '$rang';
    if (genre == genreDerive) return '$_tete$r';
    if (!avecAnnee) return '$_tete$prefixeRang$r';
    final a = anneeTexte(an);
    if (positionAnnee == anneeApres) return '$_tete$prefixeRang$r$sepAnnee$a';
    return '$_tete$a$sepAnnee$prefixeRang$r';
  }

  /// Tout ce qui précède le rang (`BEB-2026-`), pour les formats où le rang termine le numéro ; `null` quand l'année suit le rang.
  String? racine(int an) => (avecAnnee && positionAnnee == anneeApres) ? null : formater(an: an, rang: '');

  /// Le rang porté par [numero] s'il appartient à la série ; `null` sinon. [an] : seules les pièces de cette année comptent (série à remise annuelle).
  /// Le rang est lu sur les chiffres de tête (`FN-2026-00237-A` → 237) ; une référence provisoire (`…-PROV-…`) n'a pas de rang.
  int? rangDe(String numero, {int? an}) {
    final m = _motif(an).firstMatch(numero);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  RegExp _motif(int? an) {
    final yp = !avecAnnee ? '' : (an != null && remiseAnnuelle) ? RegExp.escape(anneeTexte(an)) : (annee == anneeCourte ? r'\d{2}' : r'\d{4}');
    final tete = RegExp.escape(_tete);
    final pr = RegExp.escape(prefixeRang);
    if (!avecAnnee) return RegExp('^$tete$pr(\\d+)');
    if (positionAnnee == anneeApres) return RegExp('^$tete$pr(\\d+)${RegExp.escape(sepAnnee)}$yp\$');
    return RegExp('^$tete$yp${RegExp.escape(sepAnnee)}$pr(\\d+)');
  }

  /// Le numéro appartient-il à la série (quel qu'en soit le rang ou l'année) ? Une référence provisoire de la série y appartient aussi.
  bool reconnait(Object? numero) {
    final s = '${numero ?? ''}';
    if (s.isEmpty) return false;
    if (genre == genreDerive) return prefixe.isEmpty ? false : s.startsWith(_tete);
    if (_motif(null).hasMatch(s)) return true;
    return prefixe.isNotEmpty && s.startsWith(_tete) && s.contains('PROV-');
  }

  /// Le format lisible (`BEB-AAAA-NNNN`), pour l'écran d'administration.
  String get formatLisible {
    final n = genre == genreDerive ? '<référence>' : ''.padLeft(largeur, 'N');
    if (genre == genreDerive) return '$_tete$n';
    if (!avecAnnee) return '$_tete$prefixeRang$n';
    if (positionAnnee == anneeApres) return '$_tete$prefixeRang$n$sepAnnee$annee';
    return '$_tete$annee$sepAnnee$prefixeRang$n';
  }

  Map<String, Object?> toJson() => {
        'code': code,
        'libelle': libelle,
        'module': module,
        'prefixe': prefixe,
        'annee': annee,
        'positionAnnee': positionAnnee,
        'separateur': separateur,
        if (separateurAnnee != null) 'separateurAnnee': separateurAnnee,
        'largeur': largeur,
        'prefixeRang': prefixeRang,
        'remiseAnnuelle': remiseAnnuelle,
        'genre': genre,
        'champ': champ,
        if (dateEffet != null) 'dateEffet': dateEffet,
        'aValider': aValider,
        if (note.isNotEmpty) 'note': note,
      };

  /// Une fiche de la collection, complétée par la [base] (la semence) pour ce qu'elle ne dit pas. `null` si la fiche est illisible.
  static SerieNumerotation? depuisFiche(Map<String, Object?> f, SerieNumerotation base) {
    String t(String k, String d) => f[k] is String ? f[k] as String : d;
    final larg = f['largeur'];
    final l = larg is num ? larg.toInt() : int.tryParse('${larg ?? ''}') ?? base.largeur;
    final s = SerieNumerotation(
      code: base.code,
      libelle: t('libelle', base.libelle),
      module: t('module', base.module),
      prefixe: t('prefixe', base.prefixe),
      annee: t('annee', base.annee),
      positionAnnee: t('positionAnnee', base.positionAnnee),
      separateur: t('separateur', base.separateur),
      separateurAnnee: f.containsKey('separateurAnnee') ? (f['separateurAnnee'] as String?) : base.separateurAnnee,
      largeur: l,
      prefixeRang: t('prefixeRang', base.prefixeRang),
      remiseAnnuelle: f['remiseAnnuelle'] is bool ? f['remiseAnnuelle'] as bool : base.remiseAnnuelle,
      genre: base.genre,
      champ: base.champ,
      dateEffet: f['dateEffet'] is String ? _jour(f['dateEffet']) : null,
      aValider: f['aValider'] == true,
      note: t('note', base.note),
    );
    return serieInvalide(s) == null ? s : null;
  }
}

/// Le contrôle d'une série (à la saisie, à l'application d'un dépôt, à la lecture d'une fiche) : le motif du refus, ou `null`.
String? serieInvalide(SerieNumerotation s) {
  if (!RegExp(r'^[A-Z0-9][A-Z0-9-]{0,15}$').hasMatch(s.prefixe)) {
    return 'Le préfixe doit tenir en 1 à 16 caractères : lettres majuscules, chiffres ou tiret, sans espace ni accent.';
  }
  if (!separateursAdmis.contains(s.separateur)) return 'Séparateur inconnu : ${s.separateur} (admis : ${separateursAdmis.map((x) => x.isEmpty ? '(aucun)' : x).join(' ')}).';
  if (s.genre == genreDerive) return null;
  if (!formatsAnnee.contains(s.annee)) return 'Format d’année inconnu : ${s.annee} (aucune, AAAA ou AA).';
  if (s.positionAnnee != anneeAvant && s.positionAnnee != anneeApres) return 'Place de l’année inconnue : ${s.positionAnnee} (avant ou après le rang).';
  if (s.separateurAnnee != null && !separateursAdmis.contains(s.separateurAnnee)) return 'Séparateur de l’année inconnu : ${s.separateurAnnee}.';
  if (s.largeur < 1 || s.largeur > 9) return 'La longueur du rang va de 1 à 9 chiffres.';
  if (!RegExp(r'^[A-Z]{0,3}$').hasMatch(s.prefixeRang)) return 'La lettre devant le rang : 0 à 3 lettres majuscules.';
  if (s.remiseAnnuelle && !s.avecAnnee) return 'Une remise à 1 annuelle suppose que le numéro porte l’année : sans elle, deux pièces de deux années porteraient le même numéro.';
  return null;
}

/// Le jour ISO (`AAAA-MM-JJ`) d'une date : [DateTime], chaîne ISO, ou année seule (le 1ᵉʳ janvier). `null` si illisible.
String? _jour(Object? d) {
  if (d is DateTime) return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  if (d is int) return '${d.toString().padLeft(4, '0')}-01-01';
  final s = '${d ?? ''}';
  final m = RegExp(r'^(\d{4})(-\d{2}-\d{2})?').firstMatch(s);
  if (m == null) return null;
  return m.group(2) == null ? '${m.group(1)}-01-01' : '${m.group(1)}${m.group(2)}';
}

/// L'année d'une date de pièce ([DateTime], ISO, année).
int? anneeDePiece(Object? d) {
  final j = _jour(d);
  return j == null ? null : int.parse(j.substring(0, 4));
}

/// Une série inconnue du référentiel : une erreur de PROGRAMMATION (le code nomme une série qui n'existe pas), jamais un refus d'agent.
class SerieInconnue implements Exception {
  const SerieInconnue(this.code);
  final String code;
  @override
  String toString() => 'Série de numérotation inconnue : « $code » (déclarer sa semence dans semences_numerotation.dart).';
}

/// LE REGISTRE : semences + versions de la collection, appliquées par le poste.
class Numerotation {
  const Numerotation._();

  static final Map<String, SerieNumerotation> _semences = {for (final s in seriesNumerotationSemence) s.code: s};
  static Map<String, List<SerieNumerotation>> _versions = const {};

  /// Toutes les semences, dans l'ordre du référentiel.
  static List<SerieNumerotation> get semences => seriesNumerotationSemence;

  /// La semence d'une série (lève [SerieInconnue]).
  static SerieNumerotation semence(String code) => _semences[code] ?? (throw SerieInconnue(code));

  static bool connue(String code) => _semences.containsKey(code);

  /// Applique les fiches ACTIVES de la collection (une par version). Une fiche archivée ne compte plus (RG-14) ; une fiche illisible ou d'une série
  /// inconnue est ignorée (la semence fait foi). `null` ou vide : retour aux semences.
  static void appliquer(Iterable<Map<String, Object?>>? fiches) {
    final v = <String, List<SerieNumerotation>>{};
    for (final f in fiches ?? const <Map<String, Object?>>[]) {
      if (f['statut'] == 'archive') continue;
      final base = _semences['${f['code']}'];
      if (base == null || f['dateEffet'] == null) continue;
      final s = SerieNumerotation.depuisFiche(f, base);
      if (s == null) continue;
      (v[base.code] ??= []).add(s);
    }
    for (final l in v.values) {
      l.sort((a, b) => a.dateEffet!.compareTo(b.dateEffet!));
    }
    _versions = v;
  }

  /// Revient aux semences (tests, réinitialisation).
  static void reinitialiser() => _versions = const {};

  /// Les versions datées d'une série (sans la semence), la plus ancienne d'abord.
  static List<SerieNumerotation> versions(String code) => List.unmodifiable(_versions[code] ?? const []);

  /// La version d'une série en vigueur à [date] (la semence si aucune version n'est encore entrée en vigueur).
  static SerieNumerotation serie(String code, {Object? date}) {
    final base = semence(code);
    final vs = _versions[code];
    if (vs == null || vs.isEmpty) return base;
    final j = _jour(date) ?? _jour(DateTime.now())!;
    SerieNumerotation retenue = base;
    for (final v in vs) {
      if (v.dateEffet!.compareTo(j) <= 0) retenue = v;
    }
    return retenue;
  }

  /// Toutes les versions connues d'une série (semence comprise) : un numéro de N'IMPORTE quelle version reste reconnu après un changement de préfixe.
  static List<SerieNumerotation> _toutes(String code) => [semence(code), ...?_versions[code]];

  /// Le numéro appartient-il à la série, sous l'une quelconque de ses versions ?
  static bool reconnait(String code, Object? numero) => _toutes(code).any((s) => s.reconnait(numero));
}

String _valeur(Object? e, String champ) => e is Map ? '${e[champ] ?? ''}' : '${e ?? ''}';

int _anneeOuMaintenant(Object? date, int? annee) => annee ?? anneeDePiece(date) ?? DateTime.now().year;

/// Le plus grand rang déjà porté par les pièces [existants] (fiches ou numéros, archivées comprises : un numéro ne se réutilise jamais) dans la série
/// [code] en vigueur à [date]. [annee] remplace l'année de la date (un budget d'exercice, une clôture). [champ] : le champ du numéro (défaut : celui de
/// la série).
int rangMaximal(String code, {Object? date, int? annee, required Iterable<Object?> existants, String? champ}) {
  final s = Numerotation.serie(code, date: date);
  final an = _anneeOuMaintenant(date, annee);
  final c = champ ?? s.champ;
  var max = 0;
  for (final e in existants) {
    final r = s.rangDe(_valeur(e, c), an: an);
    if (r != null && r > max) max = r;
  }
  return max;
}

/// LE NUMÉRO SUIVANT d'une série : le plus grand rang déjà écrit (année de la pièce pour une série annuelle) plus un, formaté selon la version en
/// vigueur à [date]. L'année vient de [date] (la date de la pièce), sauf [annee] explicite.
String numeroSuivant(String code, {Object? date, int? annee, required Iterable<Object?> existants, String? champ}) {
  final s = Numerotation.serie(code, date: date);
  final an = _anneeOuMaintenant(date, annee);
  return s.formater(an: an, rang: rangMaximal(code, date: date, annee: annee, existants: existants, champ: champ) + 1);
}

/// Le numéro de rang [rang] (déjà calculé par l'appelant : une plage reçue de la mère, une version de clôture, un rang de série partagée).
String numeroFormate(String code, {Object? date, int? annee, required int rang}) =>
    Numerotation.serie(code, date: date).formater(an: _anneeOuMaintenant(date, annee), rang: rang);

/// Une référence PROVISOIRE de la série (plage épuisée hors ligne) : la place du rang porte `PROV-<suffixe>`, si bien qu'elle ne ressemble à aucun numéro.
String numeroProvisoire(String code, {Object? date, int? annee, required String suffixe}) =>
    Numerotation.serie(code, date: date).formater(an: _anneeOuMaintenant(date, annee), rang: 'PROV-$suffixe');

/// Un numéro DÉRIVÉ d'une référence existante (`AIB-<facture>`, `QUIT-<obligation>-<exercice>`) : le préfixe de la série, son séparateur, la base.
String numeroDerive(String code, String base, {Object? date}) => Numerotation.serie(code, date: date).formater(an: 0, rang: base);

/// Ce qui précède le rang (`BEB-2026-`) dans la version en vigueur à [date] : affichage d'une configuration, recherche d'une série par préfixe.
/// Lève [StateError] pour une série dont l'année suit le rang (elle n'a pas de racine).
String racineNumero(String code, {Object? date, int? annee}) =>
    Numerotation.serie(code, date: date).racine(_anneeOuMaintenant(date, annee)) ?? (throw StateError('La série $code place l’année après le rang : elle n’a pas de racine.'));

/// Le numéro [numero] appartient-il à la série [code] (n'importe quelle version) ?
bool numeroDeLaSerie(String code, Object? numero) => Numerotation.reconnait(code, numero);
