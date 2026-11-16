/// L'EXPORT ET L'IMPRESSION DES LIGNES D'UN TABLEAU (Q38 à Q42, Direction du 15/11/2026) : les règles, en Dart pur, que le composant de tableau du poste appelle.
///
///  * le FORMAT : un classeur .xlsx (cellules typées, en-tête figé, largeurs) ET le CSV, les deux ;
///  * la PORTÉE : la sélection cochée, ou tout le tableau (toutes les pages), avec ou sans le filtre actif ;
///  * la LIMITE : un réglage de clinique ([ReglagesExport], lu de la base, jamais d'ici) ; au-delà, un REFUS NOMMÉ, jamais une troncature silencieuse ;
///  * le DROIT : DEUX gestes réservés, réglables par rôle ([gesteExporter] pour le fichier, [gesteImprimerTableau] pour l'impression) ; sans décision, les rôles qui
///    LISENT l'écran ; la LIMITE elle-même se règle par le geste [gesteReglerLimiteExport] ;
///  * le JOURNAL (RG-12) : qui, quel écran, combien de lignes, avec ou sans filtre, les IDENTIFIANTS des fiches (au plus 50) et leur nombre. JAMAIS le contenu.
///
/// Ce que le fichier contient est ce que l'écran montre : les colonnes visibles ; une colonne qui DÉCLARE sa valeur d'export part en vrai nombre ou vraie date, les
/// autres partent du texte affiché (donc masqué comme à l'écran).
library;

import 'dart:convert';

import '../droits/gestes_reserves.dart' show gesteExporter, gesteImprimerTableau, gesteReglerLimiteExport;
import '../parametres/definitions.dart';
import 'xlsx.dart';

export 'xlsx.dart' show RefusExport;

/// Le format d'un export.
enum FormatExport {
  xlsx('xlsx', 'Excel (.xlsx)'),
  csv('csv', 'CSV');

  const FormatExport(this.extension, this.libelle);
  final String extension;
  final String libelle;
}

/// La portée d'un export.
enum PorteeExport {
  /// Les seules lignes cochées.
  selection('selection', 'La sélection'),

  /// Tout le tableau, toutes les pages, AVEC le filtre et la recherche en force.
  toutAvecFiltre('tout_avec_filtre', 'Tout le tableau, filtre actif'),

  /// Tout le tableau, toutes les pages, SANS le filtre ni la recherche.
  toutSansFiltre('tout_sans_filtre', 'Tout le tableau, sans le filtre');

  const PorteeExport(this.code, this.libelle);
  final String code;
  final String libelle;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les réglages de la clinique.
// ---------------------------------------------------------------------------------------------------------------------------------------------

const String cleExportLimiteLignes = 'export.limiteLignes';
const String cleExportSeuilProgression = 'export.seuilProgression';
const String cleExportLimiteEtats = 'export.limiteEtatsParLigne';

/// Les réglages d'export EN VIGUEUR. Ils viennent de la base ([depuisParametres] reçoit la lecture) ; à défaut de fiche (poste jamais semé), le défaut de la
/// DÉFINITION du registre : aucune valeur n'est écrite ici.
///
/// AK (Direction, 16/11/2026) : PAS DE LIMITE de lignes par défaut, seul le droit d'export compte. [limiteLignes] vaut `null` (« aucune limite ») tant que la clinique
/// n'en a pas FIXÉ une : valeur vide ou 0 = illimité ; le refus `EXPORT_TROP_VOLUMINEUX` ne s'applique qu'à une limite d'au moins une ligne réglée par une version
/// datée. La version 0 d'un réglage est le DÉFAUT SEMÉ, pas une décision de la clinique : une base semée avant le 16/11/2026 porte encore l'ancienne valeur d'attente
/// (200 000) en version 0 ; elle suit le défaut de la définition en vigueur (aucune limite), jamais l'ancien semis.
class ReglagesExport {
  const ReglagesExport({required this.limiteLignes, required this.seuilProgression, required this.limiteEtatsParLigne});

  /// Le nombre de lignes au-delà duquel un export est REFUSÉ ; `null` : aucune limite (le défaut).
  final int? limiteLignes;

  /// Le nombre de lignes à partir duquel l'export se déroule par lots, avec un compteur de progression.
  final int seuilProgression;

  /// Le nombre d'états au-delà duquel « un état par ligne » est refusé (chaque état est une pièce complète).
  final int limiteEtatsParLigne;

  /// [valeur] : la valeur EN VIGUEUR d'une clé ; [version] (facultatif) : le numéro de la version qui la porte (0 = défaut semé).
  factory ReglagesExport.depuisParametres(Object? Function(String cle) valeur, {int? Function(String cle)? version}) {
    int lire(String cle) {
      final v = valeur(cle);
      if (v is num && v.isFinite && v >= 1) return v.toInt();
      final d = definitionDeParametre(cle)!.defaut;
      return (d as num).toInt();
    }

    return ReglagesExport(
        limiteLignes: limiteExportDepuis(valeur(cleExportLimiteLignes), version: version?.call(cleExportLimiteLignes)),
        seuilProgression: lire(cleExportSeuilProgression),
        limiteEtatsParLigne: lire(cleExportLimiteEtats));
  }

  /// La taille d'un lot : le quart du seuil, au moins une ligne. DÉRIVÉE du réglage, jamais une constante.
  int get tailleLot => (seuilProgression ~/ 4).clamp(1, 1 << 30);

  /// Le refus nommé si [n] lignes dépassent la limite, sinon `null`.
  RefusExport? verifier(int n) => limiteLignes == null || n <= limiteLignes!
      ? null
      : RefusExport(
          'EXPORT_TROP_VOLUMINEUX',
          '$n lignes à exporter : la limite réglée par la clinique est de $limiteLignes lignes par export',
          'Cocher ou filtrer pour exporter moins de lignes, ou demander à l\'administrateur de relever la limite (Paramètres › Export des tableaux).');

  /// Le refus nommé si [n] états dépassent la limite des états par ligne, sinon `null`.
  RefusExport? verifierEtats(int n) => n <= limiteEtatsParLigne
      ? null
      : RefusExport(
          'IMPRESSION_TROP_D_ETATS',
          '$n états à imprimer : la limite réglée par la clinique est de $limiteEtatsParLigne états par impression',
          'Cocher moins de lignes, ou imprimer la sélection en un seul tableau (Paramètres › Export des tableaux pour la limite).');
}

/// La limite de lignes EN VIGUEUR lue d'une valeur du registre : `null` (aucune limite) pour une valeur vide, nulle, négative ou illisible, et pour la version 0
/// (le défaut semé, qui n'est pas une décision de la clinique : voir [ReglagesExport]) ; sinon l'entier fixé par la clinique.
int? limiteExportDepuis(Object? valeur, {int? version}) {
  if (version == 0) {
    final d = definitionDeParametre(cleExportLimiteLignes)?.defaut;
    return d is num && d >= 1 ? d.toInt() : null;
  }
  if (valeur is num && valeur.isFinite && valeur >= 1) return valeur.toInt();
  if (valeur is String) {
    final n = int.tryParse(valeur.trim());
    if (n != null && n >= 1) return n;
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La sélection : conservée d'une page à l'autre jusqu'à ce que l'agent la vide.
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les lignes cochées d'un tableau, par IDENTITÉ de ligne (jamais par position : la page, le tri et le filtre ne la changent pas).
class SelectionLignes {
  final Set<String> _ids = <String>{};

  int get taille => _ids.length;
  bool get vide => _ids.isEmpty;
  bool contient(String id) => _ids.contains(id);
  Set<String> get ids => Set.unmodifiable(_ids);

  void cocher(String id) => _ids.add(id);
  void decocher(String id) => _ids.remove(id);
  void basculer(String id) => _ids.contains(id) ? _ids.remove(id) : _ids.add(id);

  /// Coche ou décoche TOUTES les lignes de [ids] (une page, ou tout le filtre).
  void definir(Iterable<String> ids, bool coche) {
    for (final i in ids) {
      coche ? _ids.add(i) : _ids.remove(i);
    }
  }

  bool toutesCochees(Iterable<String> ids) => ids.isNotEmpty && ids.every(_ids.contains);

  /// L'agent vide la sélection : le SEUL moyen de la perdre avec le changement d'écran.
  void vider() => _ids.clear();

  /// Écarte les identités qui ne sont plus au tableau (fiche archivée entre-temps) : le compteur ne compte que ce qui existe.
  void retenir(Set<String> presents) => _ids.removeWhere((i) => !presents.contains(i));
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Les cellules.
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Une colonne exportée : son libellé, le texte que l'écran affiche, la VALEUR d'export déclarée par la colonne (prioritaire : un montant, une date) et la valeur brute de
/// repli (prise seulement quand la colonne n'a pas de texte).
class ColonneExport {
  const ColonneExport({required this.libelle, required this.texte, this.brut, this.valeur});
  final String libelle;
  final String Function(Map<String, Object?>) texte;
  final Object? Function(Map<String, Object?>)? brut;

  /// La valeur d'EXPORT déclarée par la colonne (Direction, 16/11/2026, section 7) : un nombre part en VRAI nombre (décimales comprises, pas le texte arrondi), une date
  /// en VRAIE date. Toute autre valeur (une chaîne) est IGNORÉE et la cellule part du TEXTE affiché : un texte masqué sort donc masqué, jamais la valeur en clair.
  final Object? Function(Map<String, Object?>)? valeur;
}

/// La date qu'une VALEUR d'export désigne : un `DateTime`, ou une chaîne ISO stricte (`AAAA-MM-JJ`, avec ou sans heure). Toute autre chaîne : `null`.
DateTime? dateDeValeurExport(Object? v) {
  if (v is DateTime) return v;
  if (v is! String) return null;
  final m = _dateIso.firstMatch(v.trim());
  if (m == null) return null;
  return _dateValide(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.tryParse(m[4] ?? '') ?? 0, int.tryParse(m[5] ?? '') ?? 0, int.tryParse(m[6] ?? '') ?? 0);
}

bool _avecHeure(Object? v, DateTime d) => v is String ? RegExp(r'[ T]\d{2}:\d{2}').hasMatch(v) : (d.hour != 0 || d.minute != 0 || d.second != 0);

/// La cellule .xlsx d'une colonne : depuis sa VALEUR d'export quand elle est un nombre ou une date (vrai nombre, décimales comprises ; vraie date), sinon depuis le
/// TEXTE affiché ([celluleDepuis]). Une chaîne non-date passée en valeur est ignorée : le texte (éventuellement masqué) fait foi.
CelluleXlsx celluleDepuisValeur(String texte, Object? valeur, [Object? brut]) {
  if (valeur is num && valeur.isFinite) {
    final entier = valeur == valeur.truncate();
    return CelluleNombre(valeur, entier ? FormatNombre.entierMilliers : FormatNombre.decimalMilliers);
  }
  final d = dateDeValeurExport(valeur);
  if (d != null) return CelluleDate(d, avecHeure: _avecHeure(valeur, d));
  return celluleDepuis(texte, brut);
}

String _deux(int n) => n.toString().padLeft(2, '0');

/// Le texte CSV d'une colonne : un nombre en VRAI nombre (toutes ses décimales, virgule décimale, sans séparateur de milliers ni unité : Excel en français le relit en
/// nombre), une date en `jj/mm/aaaa` (avec l'heure si la valeur en porte une) ; sinon le TEXTE affiché, neutralisé ([garderTexteCsv]).
String texteCsvDepuisValeur(String texte, Object? valeur) {
  if (valeur is num && valeur.isFinite) {
    final s = valeur == valeur.truncate() ? valeur.toInt().toString() : valeur.toString();
    return s.replaceAll('.', ',');
  }
  final d = dateDeValeurExport(valeur);
  if (d != null) {
    final j = '${_deux(d.day)}/${_deux(d.month)}/${d.year.toString().padLeft(4, '0')}';
    return _avecHeure(valeur, d) ? '$j ${_deux(d.hour)}:${_deux(d.minute)}' : j;
  }
  return garderTexteCsv(texte);
}

final RegExp _nombreGroupe = RegExp(r'^-?\d{1,3}(?:[   ]\d{3})+(?:,\d+)?$');
final RegExp _nombreSimple = RegExp(r'^-?\d+(?:,\d+)?$');
final RegExp _dateFr = RegExp(r'^(\d{2})/(\d{2})/(\d{4})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?$');
final RegExp _dateIso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?)?$');
final RegExp _devise = RegExp(r'[   ]*(?:F\s?CFA|FCFA|F)$');

DateTime? _dateValide(int a, int m, int j, [int h = 0, int mi = 0, int s = 0]) {
  if (m < 1 || m > 12 || j < 1 || j > 31 || h > 23 || mi > 59 || s > 59 || a < 1900) return null;
  final d = DateTime(a, m, j, h, mi, s);
  return d.year == a && d.month == m && d.day == j ? d : null;
}

/// La cellule qu'un texte AFFICHÉ désigne : une date (`jj/mm/aaaa` avec ou sans heure, ou ISO), un nombre à la française (milliers séparés par une espace,
/// virgule décimale, unité FCFA retirée), sinon le texte tel quel.
///
/// Prudence : un identifiant ou un téléphone ne devient JAMAIS un nombre (zéro initial, plus de 15 chiffres, signe plus) ; une date impossible reste du
/// texte ; une unité autre que le franc (kg, %, mg/dl) laisse la cellule en texte, l'unité faisant partie de ce qu'on lit. [brut] n'est pris que si le
/// texte est vide (la colonne n'a pas de texte propre) : un brut numérique est alors un nombre, une date une date.
CelluleXlsx celluleDepuis(String texte, [Object? brut]) {
  final t = texte.trim();
  if (t.isEmpty) {
    if (brut is DateTime) return CelluleDate(brut, avecHeure: brut.hour != 0 || brut.minute != 0);
    if (brut is num && brut.isFinite) return CelluleNombre(brut);
    return const CelluleVide();
  }
  var m = _dateFr.firstMatch(t);
  if (m != null) {
    final d = _dateValide(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!), int.tryParse(m[4] ?? '') ?? 0, int.tryParse(m[5] ?? '') ?? 0, int.tryParse(m[6] ?? '') ?? 0);
    if (d != null) return CelluleDate(d, avecHeure: m[4] != null);
    return CelluleTexte(t);
  }
  m = _dateIso.firstMatch(t);
  if (m != null) {
    final d = _dateValide(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.tryParse(m[4] ?? '') ?? 0, int.tryParse(m[5] ?? '') ?? 0, int.tryParse(m[6] ?? '') ?? 0);
    if (d != null) return CelluleDate(d, avecHeure: m[4] != null);
    return CelluleTexte(t);
  }
  final sansDevise = t.replaceFirst(_devise, '');
  final groupe = _nombreGroupe.hasMatch(sansDevise);
  if (groupe || _nombreSimple.hasMatch(sansDevise)) {
    final chiffres = sansDevise.replaceAll(RegExp(r'[^\d]'), '');
    final entierPart = sansDevise.split(',').first.replaceAll(RegExp(r'[^\d]'), '');
    final zeroInitial = !groupe && entierPart.length > 1 && entierPart.startsWith('0');
    final avecDeviseRetiree = sansDevise != t;
    // Un entier simple (sans milliers, sans devise) peut être un code : au-delà de 15 chiffres ou à zéro initial, il reste du texte.
    if (!zeroInitial && chiffres.length <= 15) {
      final n = num.tryParse(sansDevise.replaceAll(RegExp(r'[   ]'), '').replaceAll(',', '.'));
      if (n != null && n.isFinite) {
        final decimal = sansDevise.contains(',');
        return CelluleNombre(n, groupe || avecDeviseRetiree ? (decimal ? FormatNombre.decimalMilliers : FormatNombre.entierMilliers) : FormatNombre.general);
      }
    }
  }
  return CelluleTexte(t);
}

/// Neutralise un texte que Excel évaluerait comme une FORMULE à l'ouverture d'un CSV : un `=`, un `@` ou un signe suivi d'autre chose qu'un chiffre est précédé d'une
/// apostrophe. Un nombre négatif (`-12`) et une date ne sont pas touchés.
String garderTexteCsv(String t) {
  if (t.isEmpty) return t;
  final c = t[0];
  if (c == '=' || c == '@' || c == '\t' || c == '\r') return '\'$t';
  if ((c == '+' || c == '-') && t.length > 1 && !RegExp(r'^[+-]\s?[\d.,]').hasMatch(t)) return '\'$t';
  return t;
}

/// Le nom de fichier d'un export : `<base>-AAAA-MM-JJ[-selection].<ext>`, la base réduite à des caractères sûrs.
String nomFichierExport(String base, DateTime jour, FormatExport format, {bool selection = false}) {
  var b = base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '-').replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  if (b.isEmpty) b = 'export';
  final j = '${jour.year.toString().padLeft(4, '0')}-${jour.month.toString().padLeft(2, '0')}-${jour.day.toString().padLeft(2, '0')}';
  return '$b-$j${selection ? '-selection' : ''}.${format.extension}';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La production.
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce que rend [produireExport] : les octets du fichier, ou un refus nommé, ou l'annulation de l'agent. Jamais un fichier tronqué.
class ResultatExport {
  const ResultatExport.ok(this.octets, this.lignes, this.format, {this.texte})
      : refus = null,
        annule = false;
  const ResultatExport.refus(this.refus, this.format)
      : octets = null,
        lignes = 0,
        texte = null,
        annule = false;
  const ResultatExport.annule(this.format)
      : octets = null,
        texte = null,
        refus = null,
        lignes = 0,
        annule = true;

  final List<int>? octets;

  /// Le CSV en texte (BOM compris), pour l'écran qui le reçoit lui-même ; `null` pour un classeur.
  final String? texte;
  final int lignes;
  final RefusExport? refus;
  final bool annule;
  final FormatExport format;
  bool get ok => octets != null;
}

/// Produit le fichier. La limite est vérifiée AVANT tout travail (refus nommé). Au-delà du seuil de progression, la conversion se fait par LOTS : entre deux
/// lots, la main est rendue à l'interface et [progression] reçoit `(fait, total)` ; [annule] arrête proprement (aucun fichier). Le rendu se fait sur le fil
/// principal (les colonnes portent des fonctions de l'écran, qui ne passent pas à un autre fil) : le compteur garde l'interface vivante, il ne la décharge pas.
Future<ResultatExport> produireExport({
  required List<ColonneExport> colonnes,
  required List<Map<String, Object?>> lignes,
  required FormatExport format,
  required String feuille,
  required DateTime maintenant,
  required ReglagesExport reglages,
  void Function(int fait, int total)? progression,
  bool Function()? annule,
}) async {
  final refus = reglages.verifier(lignes.length);
  if (refus != null) return ResultatExport.refus(refus, format);
  if (colonnes.isEmpty) {
    return ResultatExport.refus(const RefusExport('EXPORT_SANS_COLONNE', 'aucune colonne à exporter', 'Afficher au moins une colonne du tableau (menu « Colonnes »).'), format);
  }
  final total = lignes.length;
  final parLots = total > reglages.seuilProgression;
  final lot = reglages.tailleLot;
  final cellules = <List<CelluleXlsx>>[];
  final textes = <List<String>>[];
  for (var i = 0; i < total; i++) {
    final r = lignes[i];
    if (format == FormatExport.xlsx) {
      cellules.add([
        for (final c in colonnes) celluleDepuisValeur(c.texte(r), c.valeur?.call(r), c.brut?.call(r)),
      ]);
    } else {
      textes.add([for (final c in colonnes) texteCsvDepuisValeur(c.texte(r), c.valeur?.call(r))]);
    }
    if (parLots && (i + 1) % lot == 0) {
      progression?.call(i + 1, total);
      await Future<void>.delayed(Duration.zero);
      if (annule?.call() ?? false) return ResultatExport.annule(format);
    }
  }
  progression?.call(total, total);
  try {
    if (format == FormatExport.xlsx) {
      final octets = ecrireXlsx(feuille: feuille, entetes: [for (final c in colonnes) c.libelle], lignes: cellules, maintenant: maintenant);
      return ResultatExport.ok(octets, total, format);
    }
    final csv = '\uFEFF${[
      colonnes.map((c) => _guillemets(c.libelle)).join(';'),
      ...textes.map((l) => l.map(_guillemets).join(';')),
    ].join('\r\n')}';
    return ResultatExport.ok(_utf8(csv), total, format, texte: csv);
  } on RefusExport catch (e) {
    return ResultatExport.refus(e, format);
  }
}

String _guillemets(String v) => '"${v.replaceAll('"', '""')}"';

List<int> _utf8(String s) => utf8.encode(s);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le journal (RG-12).
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le nombre maximal d'IDENTIFIANTS de fiches écrits dans UNE entrée du journal (Direction, 16/11/2026, section 7 : « au plus 50 par entrée »). Le nombre TOTAL est
/// toujours écrit à côté : un export de 10 000 lignes ne gonfle pas le journal, mais il dit combien de fiches sont sorties.
const int maxIdentifiantsJournalExport = 50;

/// Les identifiants des lignes (champ `id`, la clé technique de la fiche ; jamais une valeur de cellule) : les lignes sans identifiant sont comptées dans `lignes`, pas ici.
List<String> identifiantsDesLignes(Iterable<Map<String, Object?>> lignes) => [
      for (final l in lignes)
        if (l['id'] != null && '${l['id']}'.isNotEmpty) '${l['id']}'
    ];

/// Ce que le journal d'audit retient d'un export ou d'une impression de lignes : le GESTE, l'écran, le nombre de lignes, la portée, le filtre en force ou non,
/// le format, le nombre de colonnes, et les IDENTIFIANTS des fiches (au plus [maxIdentifiantsJournalExport], `fiches`) avec leur nombre total (`nbFiches`). JAMAIS une
/// valeur de cellule, ni un nom de patient, ni le texte d'une recherche (qui peut être un nom).
Map<String, Object?> detailJournalExport({
  required PorteeExport portee,
  required int lignes,
  required bool filtreActif,
  required int colonnes,
  FormatExport? format,
  String? mode,
  RefusExport? refus,
  List<String>? identifiants,
}) =>
    {
      'portee': portee.code,
      'lignes': lignes,
      'filtre': filtreActif ? 'avec' : 'sans',
      'colonnes': colonnes,
      if (format != null) 'format': format.extension,
      if (mode != null) 'mode': mode,
      if (refus != null) 'refus': refus.code,
      if (identifiants != null) ...{
        'fiches': identifiants.take(maxIdentifiantsJournalExport).toList(),
        'nbFiches': identifiants.length,
        if (identifiants.length > maxIdentifiantsJournalExport) 'fichesTronquees': true,
      },
    };

/// L'action écrite au journal.
const String actionJournalExport = 'Export de tableau';
const String actionJournalImpression = 'Impression de lignes';
