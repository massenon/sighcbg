/// L'ÉCRIVAIN DE CLASSEUR .xlsx (Q38, Direction du 15/11/2026) : un VRAI classeur Office Open XML, écrit en Dart pur (zip + XML), sans dépendance.
///
/// Ce qu'il porte, et que le CSV ne porte pas : des cellules NUMÉRIQUES (un montant se totalise dans Excel), des cellules DATE (un tri chronologique
/// et non alphabétique), un en-tête FIGÉ (il reste visible au défilement), un filtre automatique sur l'en-tête et des LARGEURS de colonnes calculées
/// sur le contenu. Les textes sont écrits en chaînes en ligne : jamais évalués comme formules, quoi qu'ils commencent par `=` ou `@`.
///
/// Ce qu'il ne fait pas : une seule feuille, aucune formule, aucune image, aucun style de cellule individuel (quatre formats numériques et un en-tête).
/// Les limites du format sont REFUSÉES en les nommant ([RefusExport]) : au-delà de 1 048 575 lignes de données ou 16 384 colonnes, un classeur tronquerait.
library;

import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

/// Un refus NOMMÉ d'export : le code (stable, testable), le motif (lisible au guichet) et le geste de correction. Jamais de troncature silencieuse.
class RefusExport implements Exception {
  const RefusExport(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
  @override
  String toString() => '$code : $motif';
}

/// Le format numérique d'une cellule numérique.
enum FormatNombre { general, entierMilliers, decimalMilliers }

/// Une cellule du classeur : vide, texte, nombre ou date (avec ou sans heure).
sealed class CelluleXlsx {
  const CelluleXlsx();
}

class CelluleVide extends CelluleXlsx {
  const CelluleVide();
}

class CelluleTexte extends CelluleXlsx {
  const CelluleTexte(this.texte);
  final String texte;
}

class CelluleNombre extends CelluleXlsx {
  const CelluleNombre(this.valeur, [this.format = FormatNombre.general]);
  final num valeur;
  final FormatNombre format;
}

class CelluleDate extends CelluleXlsx {
  const CelluleDate(this.date, {this.avecHeure = false});

  /// Les composantes (année, mois, jour, heure, minute) sont lues telles quelles : aucun fuseau n'est appliqué (la date affichée à l'écran est celle du classeur).
  final DateTime date;
  final bool avecHeure;
}

/// Le plus grand nombre de lignes de données d'une feuille (une ligne est prise par l'en-tête sur 1 048 576).
const int xlsxLignesMax = 1048575;
const int xlsxColonnesMax = 16384;

/// L'index de colonne (0 = A) en lettres : 0 → A, 25 → Z, 26 → AA.
String lettreColonne(int i) {
  var n = i + 1;
  final s = StringBuffer();
  final lettres = <String>[];
  while (n > 0) {
    final r = (n - 1) % 26;
    lettres.add(String.fromCharCode(65 + r));
    n = (n - 1) ~/ 26;
  }
  for (final l in lettres.reversed) {
    s.write(l);
  }
  return s.toString();
}

/// Le numéro de série Excel d'une date (jours depuis le 30/12/1899, fraction = heure). Calculé en UTC sur les composantes : insensible au fuseau.
double numeroSerieExcel(DateTime d, {bool avecHeure = false}) {
  final jour = DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1899, 12, 30)).inDays;
  if (!avecHeure) return jour.toDouble();
  return jour + (d.hour * 3600 + d.minute * 60 + d.second) / 86400;
}

final RegExp _interdits = RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]');

String _xml(String s) => s
    .replaceAll(_interdits, '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Le nom de feuille accepté par Excel : 31 caractères au plus, sans `[ ] : * ? / \`, jamais vide.
String nomFeuilleValide(String nom) {
  var n = nom.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (n.length > 31) n = n.substring(0, 31).trim();
  return n.isEmpty ? 'Feuille1' : n;
}

/// Écrit le classeur : [entetes] en première ligne (gras, figée), puis [lignes]. Rend les octets du fichier .xlsx.
/// [maintenant] date les entrées du zip (déterministe : un test fixe l'instant).
Uint8List ecrireXlsx({required String feuille, required List<String> entetes, required Iterable<List<CelluleXlsx>> lignes, required DateTime maintenant}) {
  if (entetes.isEmpty) throw const RefusExport('EXPORT_SANS_COLONNE', 'aucune colonne à exporter', 'Afficher au moins une colonne du tableau (menu « Colonnes »).');
  if (entetes.length > xlsxColonnesMax) {
    throw RefusExport('XLSX_COLONNES_MAX', '${entetes.length} colonnes : un classeur Excel en porte au plus $xlsxColonnesMax', 'Masquer des colonnes (menu « Colonnes »), ou exporter en CSV.');
  }
  final largeurs = [for (final e in entetes) e.length.toDouble()];
  final feuilleXml = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')
    ..write('<sheetFormatPr defaultRowHeight="15"/>');
  final donnees = StringBuffer()..write('<sheetData>');
  donnees.write('<row r="1">');
  for (var c = 0; c < entetes.length; c++) {
    donnees.write('<c r="${lettreColonne(c)}1" s="1" t="inlineStr"><is><t xml:space="preserve">${_xml(entetes[c])}</t></is></c>');
  }
  donnees.write('</row>');
  var n = 0;
  for (final ligne in lignes) {
    n++;
    if (n > xlsxLignesMax) {
      throw const RefusExport('XLSX_LIGNES_MAX', 'plus de 1 048 575 lignes : un classeur Excel ne les porte pas', 'Filtrer ou cocher moins de lignes, ou exporter en CSV.');
    }
    final r = n + 1;
    donnees.write('<row r="$r">');
    for (var c = 0; c < entetes.length; c++) {
      final cel = c < ligne.length ? ligne[c] : const CelluleVide();
      final ref = '${lettreColonne(c)}$r';
      switch (cel) {
        case CelluleVide():
          break;
        case CelluleTexte(:final texte):
          if (texte.isEmpty) break;
          donnees.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_xml(texte)}</t></is></c>');
          final l = texte.length.toDouble();
          if (l > largeurs[c]) largeurs[c] = l;
        case CelluleNombre(:final valeur, :final format):
          if (!valeur.isFinite) break;
          final s = switch (format) { FormatNombre.general => 0, FormatNombre.entierMilliers => 2, FormatNombre.decimalMilliers => 3 };
          donnees.write('<c r="$ref"${s == 0 ? '' : ' s="$s"'}><v>$valeur</v></c>');
          final l = (format == FormatNombre.general ? '$valeur' : '$valeur#').length * 1.2;
          if (l > largeurs[c]) largeurs[c] = l;
        case CelluleDate(:final date, :final avecHeure):
          donnees.write('<c r="$ref" s="${avecHeure ? 5 : 4}"><v>${numeroSerieExcel(date, avecHeure: avecHeure)}</v></c>');
          final l = avecHeure ? 16.0 : 10.0;
          if (l > largeurs[c]) largeurs[c] = l;
      }
    }
    donnees.write('</row>');
  }
  donnees.write('</sheetData>');
  feuilleXml.write('<cols>');
  for (var c = 0; c < entetes.length; c++) {
    final w = (largeurs[c] + 2).clamp(8.0, 60.0);
    feuilleXml.write('<col min="${c + 1}" max="${c + 1}" width="${w.toStringAsFixed(1)}" customWidth="1"/>');
  }
  feuilleXml.write('</cols>');
  feuilleXml.write(donnees);
  feuilleXml.write('<autoFilter ref="A1:${lettreColonne(entetes.length - 1)}${n + 1}"/>');
  feuilleXml.write('</worksheet>');

  final nom = _xml(nomFeuilleValide(feuille));
  final zip = EcrivainZip(maintenant);
  zip.ajouter(
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '</Types>');
  zip.ajouter(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>');
  zip.ajouter(
      'xl/workbook.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="$nom" sheetId="1" r:id="rId1"/></sheets>'
          '</workbook>');
  zip.ajouter(
      'xl/_rels/workbook.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '</Relationships>');
  zip.ajouter(
      'xl/styles.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<numFmts count="2"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/><numFmt numFmtId="165" formatCode="dd/mm/yyyy\\ hh:mm"/></numFmts>'
          '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
          '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
          '<fill><patternFill patternType="solid"><fgColor rgb="FFE2E8F0"/><bgColor indexed="64"/></patternFill></fill></fills>'
          '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
          '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
          '<cellXfs count="6">'
          '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
          '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
          '<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
          '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
          '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
          '<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
          '</cellXfs>'
          '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
          '</styleSheet>');
  zip.ajouterOctets('xl/worksheets/sheet1.xml', utf8.encode(feuilleXml.toString()));
  return zip.octets();
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// ZIP : l'écrivain minimal (entrées compressées en DEFLATE brut, CRC-32, pas de ZIP64).
// ---------------------------------------------------------------------------------------------------------------------------------------------

final List<int> _tableCrc = () {
  final t = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    t[n] = c;
  }
  return t;
}();

/// Le CRC-32 (polynôme 0xEDB88320) de [octets].
int crc32(List<int> octets) {
  var c = 0xFFFFFFFF;
  for (final b in octets) {
    c = _tableCrc[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

class _Entree {
  _Entree(this.nom, this.donnees, this.crc, this.tailleOrigine, this.methode, this.decalage);
  final List<int> nom;
  final List<int> donnees;
  final int crc;
  final int tailleOrigine;
  final int methode;
  final int decalage;
}

/// Un zip en mémoire. [ajouter] pose un texte UTF-8, [ajouterOctets] des octets ; [octets] rend l'archive complète.
class EcrivainZip {
  EcrivainZip(DateTime maintenant)
      : _heure = ((maintenant.hour << 11) | (maintenant.minute << 5) | (maintenant.second ~/ 2)) & 0xFFFF,
        _jour = ((((maintenant.year < 1980 ? 1980 : maintenant.year) - 1980) << 9) | (maintenant.month << 5) | maintenant.day) & 0xFFFF;

  final int _heure;
  final int _jour;
  final List<_Entree> _entrees = [];
  final BytesBuilder _corps = BytesBuilder(copy: false);

  void ajouter(String nom, String texte) => ajouterOctets(nom, utf8.encode(texte));

  void ajouterOctets(String nom, List<int> brut) {
    final crc = crc32(brut);
    final compresse = ZLibCodec(raw: true, level: 6).encode(brut);
    final deflate = compresse.length < brut.length;
    final donnees = deflate ? compresse : brut;
    final nomOctets = utf8.encode(nom);
    final decalage = _corps.length;
    final e = _Entree(nomOctets, donnees, crc, brut.length, deflate ? 8 : 0, decalage);
    _entrees.add(e);
    final h = BytesBuilder(copy: false);
    _u32(h, 0x04034b50);
    _u16(h, 20);
    _u16(h, 0x0800);
    _u16(h, e.methode);
    _u16(h, _heure);
    _u16(h, _jour);
    _u32(h, crc);
    _u32(h, donnees.length);
    _u32(h, brut.length);
    _u16(h, nomOctets.length);
    _u16(h, 0);
    h.add(nomOctets);
    _corps.add(h.takeBytes());
    _corps.add(donnees);
  }

  Uint8List octets() {
    final sortie = BytesBuilder(copy: false)..add(_corps.toBytes());
    final debutRepertoire = sortie.length;
    for (final e in _entrees) {
      final h = BytesBuilder(copy: false);
      _u32(h, 0x02014b50);
      _u16(h, 20);
      _u16(h, 20);
      _u16(h, 0x0800);
      _u16(h, e.methode);
      _u16(h, _heure);
      _u16(h, _jour);
      _u32(h, e.crc);
      _u32(h, e.donnees.length);
      _u32(h, e.tailleOrigine);
      _u16(h, e.nom.length);
      _u16(h, 0);
      _u16(h, 0);
      _u16(h, 0);
      _u16(h, 0);
      _u32(h, 0);
      _u32(h, e.decalage);
      h.add(e.nom);
      sortie.add(h.takeBytes());
    }
    final tailleRepertoire = sortie.length - debutRepertoire;
    final fin = BytesBuilder(copy: false);
    _u32(fin, 0x06054b50);
    _u16(fin, 0);
    _u16(fin, 0);
    _u16(fin, _entrees.length);
    _u16(fin, _entrees.length);
    _u32(fin, tailleRepertoire);
    _u32(fin, debutRepertoire);
    _u16(fin, 0);
    sortie.add(fin.takeBytes());
    final r = sortie.takeBytes();
    if (r.length > 0xFFFFFFF0) throw const RefusExport('ZIP_TROP_GRAND', 'le classeur dépasse 4 Go', 'Exporter moins de lignes.');
    return r;
  }

  static void _u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  static void _u32(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
}
