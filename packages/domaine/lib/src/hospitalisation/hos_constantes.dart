/// LES CONSTANTES, À UNE SOURCE (lot B, 13/11/2026) : la tension et la diurèse se saisissent, se rangent et se lisent de la MÊME façon à l'accueil et à l'hospitalisation.
///
///  * TENSION : DEUX nombres entiers, `tensionSys` et `tensionDia`, en cmHg — l'unité que la saisie d'accueil portait déjà (libellés, échelle de la feuille de température
///    5 à 30). « 12/8 » n'est plus qu'une MISE EN FORME ([hosTensionTexte]), jamais une donnée saisie. Les bornes sont celles de l'accueil, reprises pour l'hospitalisation :
///    PROPOSITION à valider par un soignant, aucune n'est inventée.
///  * DIURÈSE : en MILLILITRES partout, sans décimale. L'accueil la saisissait en litres (borne de 5 L) et l'hospitalisation en millilitres : deux unités pour une même grandeur.
///  * AUCUNE ALERTE de variation sur les constantes : aucune règle clinique n'est documentée. Les constantes se lisent en courbe, elles ne déclenchent rien.
///
/// Les anciennes données (tension en texte « 12/8 », diurèse d'accueil en litres) se RELISENT et se MIGRENT par [hosMigrerConstantes] : pure, sans magasin.
library;

typedef FicheHos = Map<String, Object?>;

/// L'unité de la tension, unique.
const String hosUniteTension = 'cmHg';
const String hosUniteDiurese = 'mL';

/// Les bornes de saisie : tension systolique 4 à 30, diastolique 2 à 20 (cmHg), diurèse 0 à 5 000 mL. Proposition à valider par un soignant : reprises de l'accueil.
const int hosTensionSysMin = 4, hosTensionSysMax = 30, hosTensionDiaMin = 2, hosTensionDiaMax = 20, hosDiureseMin = 0, hosDiureseMax = 5000;

num? _nombre(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  final s = '$v'.trim().replaceAll(',', '.');
  return s.isEmpty ? null : num.tryParse(s);
}

String _texte(num n) => n == n.truncate() ? '${n.toInt()}' : '$n';

/// « 12/8 » : la mise en forme de deux nombres, ou `null` quand l'un manque (on n'écrit pas une moitié de tension).
String? hosTensionTexte(Object? sys, Object? dia) {
  final s = _nombre(sys), d = _nombre(dia);
  return s == null || d == null ? null : '${_texte(s)}/${_texte(d)}';
}

/// Le texte « a/b » de l'ancienne saisie, analysé : deux ENTIERS séparés par une barre. Tout autre texte rend `null` (jamais deviné : « 12 sur 8 » reste un texte).
({int sys, int dia})? hosAnalyserTension(Object? texte) {
  final m = RegExp(r'^\s*(\d{1,2})\s*/\s*(\d{1,2})\s*$').firstMatch('${texte ?? ''}');
  return m == null ? null : (sys: int.parse(m[1]!), dia: int.parse(m[2]!));
}

/// La tension d'une fiche (relevé d'hospitalisation, relevé d'accueil, constante d'observation) : les DEUX NOMBRES d'abord, le texte « a/b » d'une ancienne fiche
/// seulement à défaut (une fiche arrivée d'un poste qui n'a pas encore migré). Rend `(null, null)` quand rien n'est lisible.
({num? sys, num? dia}) hosTensionDe(FicheHos f) {
  final s = _nombre(f['tensionSys']), d = _nombre(f['tensionDia']);
  if (s != null && d != null) return (sys: s, dia: d);
  // Un nombre manque : le texte « a/b » d'une ancienne fiche le complète (jamais l'inverse : un nombre saisi l'emporte toujours sur le texte).
  final a = hosAnalyserTension(f['tension']);
  return (sys: s ?? a?.sys, dia: d ?? a?.dia);
}

/// Le texte d'affichage de la tension d'une fiche (« 12/8 »), ou le texte ancien non analysable tel quel, ou `null`.
String? hosTensionAffichee(FicheHos f) {
  final t = hosTensionDe(f);
  final mise = hosTensionTexte(t.sys, t.dia);
  if (mise != null) return mise;
  final brut = '${f['tension'] ?? ''}'.trim();
  return brut.isEmpty ? null : brut;
}

/// La diurèse en millilitres, entière.
String hosDiureseTexte(Object? ml) {
  final n = _nombre(ml);
  return n == null ? '—' : '${n.round()} mL';
}

/// Ce que la migration a fait, collection par collection, pour que le poste le DISE.
class RapportMigrationConstantes {
  RapportMigrationConstantes();

  /// Collections modifiées (nom → fiches complètes, archivées comprises) : à réécrire.
  final Map<String, List<FicheHos>> modifiees = {};
  int tensionsScindees = 0;

  /// Textes de tension non analysables : gardés TELS QUELS, hors des nombres (jamais inventés).
  int tensionsIllisibles = 0;
  int diuresesConverties = 0;
  bool get aFait => modifiees.isNotEmpty;
}

FicheHos _scinder(FicheHos f, RapportMigrationConstantes r) {
  if (f['tensionSys'] != null || f['tensionDia'] != null) return f;
  final brut = f['tension'];
  if (brut == null || '$brut'.trim().isEmpty) return f;
  final a = hosAnalyserTension(brut);
  if (a == null) {
    r.tensionsIllisibles++;
    return f;
  }
  r.tensionsScindees++;
  return {...f, 'tensionSys': a.sys, 'tensionDia': a.dia}..remove('tension');
}

/// MIGRATION DES CONSTANTES D'AVANT LE LOT B. [releves] : relevés d'hospitalisation (tension texte → deux nombres ; diurèse déjà en millilitres). [observations] :
/// chaque constante de la feuille d'observation (même scission). [constantes] : relevés d'accueil, dont la diurèse était en LITRES : multipliée par 1 000, UNE FOIS —
/// [diureseAccueilEnLitres] est posé par l'appelant d'après la marque de version du poste (sans marque, 2 mL et 2 L se confondent). La tension d'accueil porte déjà
/// ses deux nombres et son texte calculé : rien à scinder. Idempotente pour la tension ; la diurèse ne se convertit que sur demande.
RapportMigrationConstantes hosMigrerConstantes(
    {Iterable<FicheHos> releves = const [],
    Iterable<FicheHos> observations = const [],
    Iterable<FicheHos> constantes = const [],
    required bool diureseAccueilEnLitres}) {
  final r = RapportMigrationConstantes();
  final avantR = r.tensionsScindees;
  final rel = [for (final f in releves) _scinder(f, r)];
  if (r.tensionsScindees != avantR) r.modifiees['releves'] = rel;
  var obsChangees = false;
  final obs = <FicheHos>[];
  for (final o in observations) {
    final cs = o['constantes'];
    if (cs is! List || cs.isEmpty) {
      obs.add(o);
      continue;
    }
    final avant = r.tensionsScindees;
    final neuves = [for (final x in cs) x is Map ? _scinder(x.cast<String, Object?>(), r) : x];
    if (r.tensionsScindees != avant) {
      obsChangees = true;
      obs.add({...o, 'constantes': neuves});
    } else {
      obs.add(o);
    }
  }
  if (obsChangees) r.modifiees['observations'] = obs;
  if (diureseAccueilEnLitres) {
    var change = false;
    final cst = <FicheHos>[];
    for (final f in constantes) {
      final d = _nombre(f['diurese']);
      if (d == null) {
        cst.add(f);
        continue;
      }
      change = true;
      r.diuresesConverties++;
      cst.add({...f, 'diurese': (d * 1000).round()});
    }
    if (change) r.modifiees['constantes'] = cst;
  }
  return r;
}
