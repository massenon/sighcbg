/// EXTRACTION LOCALE DU TEXTE D'UN PDF (couche texte seulement), écrite pour le projet : aucune bibliothèque, aucun appel externe, aucun OCR.
///
/// Ce qu'elle lit : les flux de contenu (`BT … ET`), décompressés quand ils sont en Flate, les chaînes des opérateurs Tj / TJ / ' / ", littérales ou
/// hexadécimales, et les tables ToUnicode (`beginbfchar`, `beginbfrange`) des polices à codes de deux octets. Elle rend les MOTS DISTINCTS (normalisés,
/// accents et casse ignorés, au plus [docMotsMax]) et le nombre de pages.
///
/// Ce qu'elle ne fait pas, et DIT : un scan est une image, sans couche texte (« Aucune couche texte : scan image ») ; un PDF chiffré n'est pas lu ; les
/// ToUnicode de toutes les polices sont FUSIONNÉES (approximation : deux polices qui affectent un même code à deux lettres différentes ne sont pas
/// distinguées) ; un filtre autre que Flate (LZW, ASCII85) n'est pas lu. Dans tous ces cas la pièce est « texte non indexé », jamais « aucun résultat ».
library;

import 'dart:convert';
import 'dart:io' show ZLibDecoder, ZLibCodec;

import '../format/recherche.dart' show normaliser;

const int docMotsMax = 4000;

class DocTextePdf {
  const DocTextePdf({required this.mots, required this.pages, required this.indexe, this.raison, this.tronque = false});
  final List<String> mots;
  final int pages;
  final bool indexe;
  final bool tronque;

  /// Pourquoi le texte n'est pas indexé (affiché sur la ligne et dans la fiche).
  final String? raison;

  /// Les mots collés en une chaîne, pour la colonne de recherche.
  String get texte => mots.join(' ');
}

String _l1(List<int> o) => latin1.decode(o, allowInvalid: true);

List<int>? _inflate(List<int> o) {
  try {
    return ZLibDecoder().convert(o);
  } catch (_) {
    try {
      return ZLibCodec(raw: true).decode(o);
    } catch (_) {
      return null;
    }
  }
}

class _Flux {
  _Flux(this.dico, this.octets);
  final String dico;
  final List<int> octets;
}

List<_Flux> _flux(List<int> pdf) {
  final s = _l1(pdf);
  final out = <_Flux>[];
  var i = 0;
  while (true) {
    final d = s.indexOf('stream', i);
    if (d < 0) break;
    if (d >= 3 && s.substring(d - 3, d) == 'end') {
      i = d + 6;
      continue;
    }
    var debut = d + 6;
    if (debut < s.length && s.codeUnitAt(debut) == 13) debut++;
    if (debut < s.length && s.codeUnitAt(debut) == 10) debut++;
    final fin = s.indexOf('endstream', debut);
    if (fin < 0) break;
    final dicoDebut = s.lastIndexOf('obj', d);
    final dico = dicoDebut < 0 ? '' : s.substring(dicoDebut, d);
    var brut = pdf.sublist(debut, fin);
    if (dico.contains('/FlateDecode')) {
      final x = _inflate(brut);
      if (x == null) {
        i = fin + 9;
        continue;
      }
      brut = x;
    } else if (dico.contains('/LZWDecode') || dico.contains('/ASCII85Decode') || dico.contains('/DCTDecode') || dico.contains('/CCITTFaxDecode') || dico.contains('/JPXDecode')) {
      i = fin + 9;
      continue;
    }
    out.add(_Flux(dico, brut));
    i = fin + 9;
  }
  return out;
}

/// Une table ToUnicode : code (entier) vers texte, et la largeur des codes en octets.
class _Cmap {
  final Map<int, String> table = {};
  int largeur = 0;
}

String _utf16Hex(String hex) {
  final u = <int>[];
  for (var i = 0; i + 3 < hex.length + 0 && i + 4 <= hex.length; i += 4) {
    u.add(int.parse(hex.substring(i, i + 4), radix: 16));
  }
  return String.fromCharCodes(u);
}

void _lireCmap(String s, _Cmap c) {
  for (final bloc in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true).allMatches(s)) {
    for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>').allMatches(bloc.group(1)!)) {
      c.largeur = c.largeur < m.group(1)!.length ~/ 2 ? m.group(1)!.length ~/ 2 : c.largeur;
      c.table.putIfAbsent(int.parse(m.group(1)!, radix: 16), () => _utf16Hex(m.group(2)!));
    }
  }
  for (final bloc in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true).allMatches(s)) {
    for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<([0-9A-Fa-f]+)>|\[(.*?)\])', dotAll: true).allMatches(bloc.group(1)!)) {
      final a = int.parse(m.group(1)!, radix: 16), b = int.parse(m.group(2)!, radix: 16);
      c.largeur = c.largeur < m.group(1)!.length ~/ 2 ? m.group(1)!.length ~/ 2 : c.largeur;
      if (b < a || b - a > 65535) continue;
      if (m.group(4) != null) {
        final dep = int.parse(m.group(4)!, radix: 16);
        for (var k = 0; k <= b - a; k++) {
          c.table.putIfAbsent(a + k, () => _utf16Hex((dep + k).toRadixString(16).padLeft(m.group(4)!.length, '0')));
        }
      } else if (m.group(5) != null) {
        final l = RegExp(r'<([0-9A-Fa-f]+)>').allMatches(m.group(5)!).toList();
        for (var k = 0; k < l.length && a + k <= b; k++) {
          c.table.putIfAbsent(a + k, () => _utf16Hex(l[k].group(1)!));
        }
      }
    }
  }
}

/// Les chaînes d'un bloc de texte : ce qui est entre parenthèses (avec échappements) ou entre chevrons.
List<({List<int> octets, bool hex})> _chaines(String bloc) {
  final out = <({List<int> octets, bool hex})>[];
  var i = 0;
  while (i < bloc.length) {
    final c = bloc[i];
    if (c == '(') {
      final o = <int>[];
      var prof = 1;
      i++;
      while (i < bloc.length && prof > 0) {
        final ch = bloc[i];
        if (ch == '\\' && i + 1 < bloc.length) {
          final n = bloc[i + 1];
          if (RegExp(r'[0-7]').hasMatch(n)) {
            var j = i + 1, v = 0, k = 0;
            while (j < bloc.length && k < 3 && RegExp(r'[0-7]').hasMatch(bloc[j])) {
              v = v * 8 + int.parse(bloc[j]);
              j++;
              k++;
            }
            o.add(v & 0xff);
            i = j;
            continue;
          }
          o.add(switch (n) { 'n' => 10, 'r' => 13, 't' => 9, 'b' => 8, 'f' => 12, _ => n.codeUnitAt(0) & 0xff });
          i += 2;
          continue;
        }
        if (ch == '(') prof++;
        if (ch == ')') {
          prof--;
          if (prof == 0) {
            i++;
            break;
          }
        }
        o.add(ch.codeUnitAt(0) & 0xff);
        i++;
      }
      out.add((octets: o, hex: false));
    } else if (c == '<' && !(i + 1 < bloc.length && bloc[i + 1] == '<')) {
      final fin = bloc.indexOf('>', i);
      if (fin < 0) break;
      var h = bloc.substring(i + 1, fin).replaceAll(RegExp(r'\s'), '');
      if (h.length.isOdd) h += '0';
      if (RegExp(r'^[0-9A-Fa-f]*$').hasMatch(h)) {
        out.add((octets: [for (var k = 0; k < h.length; k += 2) int.parse(h.substring(k, k + 2), radix: 16)], hex: true));
      }
      i = fin + 1;
    } else {
      i++;
    }
  }
  return out;
}

/// Extrait le texte d'un PDF. Ne lève jamais : un PDF illisible rend `indexe: false` et la raison.
DocTextePdf docExtraireTextePdf(List<int> pdf) {
  try {
    final tout = _l1(pdf);
    if (tout.contains('/Encrypt')) return const DocTextePdf(mots: [], pages: 0, indexe: false, raison: 'PDF chiffré : texte non lu.');
    final flux = _flux(pdf);
    final cmap = _Cmap();
    final contenus = <String>[];
    var pages = RegExp(r'/Type\s*/Page(?![a-zA-Z])').allMatches(tout).length;
    for (final f in flux) {
      final t = _l1(f.octets);
      if (t.contains('beginbfchar') || t.contains('beginbfrange')) {
        _lireCmap(t, cmap);
      } else if (f.dico.contains('/ObjStm')) {
        pages += RegExp(r'/Type\s*/Page(?![a-zA-Z])').allMatches(t).length;
      } else if (RegExp(r'\bBT\b').hasMatch(t)) {
        contenus.add(t);
      }
    }
    final bruts = <String>[];
    for (final c in contenus) {
      for (final bt in RegExp(r'\bBT\b(.*?)\bET\b', dotAll: true).allMatches(c)) {
        for (final ch in _chaines(bt.group(1)!)) {
          if (ch.hex && cmap.largeur >= 2 && ch.octets.length.isEven) {
            final b = StringBuffer();
            for (var k = 0; k < ch.octets.length; k += 2) {
              final code = (ch.octets[k] << 8) | ch.octets[k + 1];
              b.write(cmap.table[code] ?? '');
            }
            bruts.add(b.toString());
          } else if (ch.hex && cmap.table.isNotEmpty && cmap.largeur == 1) {
            bruts.add(ch.octets.map((o) => cmap.table[o] ?? '').join());
          } else {
            // Windows-1252 pour l'essentiel du français : latin1 couvre les accents usuels.
            bruts.add(latin1.decode(ch.octets, allowInvalid: true));
          }
        }
        bruts.add(' ');
      }
    }
    final vus = <String>{};
    var tronque = false;
    for (final m in RegExp(r'[a-z0-9]{2,}').allMatches(normaliser(bruts.join(' ')))) {
      if (vus.length >= docMotsMax) {
        tronque = true;
        break;
      }
      vus.add(m.group(0)!);
    }
    if (pages == 0) pages = contenus.isEmpty ? 0 : contenus.length;
    if (vus.isEmpty) return DocTextePdf(mots: const [], pages: pages, indexe: false, raison: 'Aucune couche texte : scan image (l’OCR est une phase ultérieure).');
    return DocTextePdf(mots: vus.toList(), pages: pages, indexe: true, tronque: tronque);
  } catch (e) {
    return DocTextePdf(mots: const [], pages: 0, indexe: false, raison: 'PDF illisible par l’extracteur local : texte non indexé.');
  }
}
