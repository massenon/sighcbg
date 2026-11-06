// DÉRIVÉ DE LA MAQUETTE BAGUIDI (prototype_html/tailwind.config.js), ÉDITÉ À LA MAIN le 06/11/2026 :
// la chaîne d'engendrement d'origine (build/extraire.js) reste chez l'éditeur (dépôt SIGH-CNT) et n'est pas dans ce dépôt.
// Jetons de design de la maquette. Aucune couleur en dur ailleurs.
// ignore_for_file: constant_identifier_names

/// Palettes (nuance -> ARGB). Utilisation : `Color(JetonsSigh.navy[900]!)`.
///
/// Charte BAGUIDI : Rouge Cœur (actions), Bleu Santé (titres, badges), Noir Anthracite (texte, barres sombres).
/// Le rouge d'ACTION (`coeur`, base 500) n'est PAS le rouge d'ERREUR (`danger`, inchangé) : une alerte ne doit
/// jamais se confondre avec un bouton. `navy` est RÉAFFECTÉ comme dans la maquette (50 à 900 = Bleu Santé,
/// 950 = Noir Anthracite) pour que la coquille change de couleur sans changer de classes.
class JetonsSigh {
  JetonsSigh._();

  /// Rouge Cœur : couleur principale / actions (base 500).
  static const Map<int, int> coeur = {
    50: 0xFFFDECEC,
    100: 0xFFFBD8D8,
    200: 0xFFF6B1B1,
    300: 0xFFEE8383,
    400: 0xFFE35555,
    500: 0xFFD32F2F,
    600: 0xFFB62222,
    700: 0xFF971C1C,
    800: 0xFF7D1A1A,
    900: 0xFF671717,
    950: 0xFF3F0D0D,
  };

  /// Bleu Santé : secondaire / titres, badges (base 600).
  static const Map<int, int> sante = {
    50: 0xFFEEF4FC,
    100: 0xFFD9E7F8,
    200: 0xFFB6D0F1,
    300: 0xFF8AB3E8,
    400: 0xFF5590DA,
    500: 0xFF2F74CC,
    600: 0xFF1565C0,
    700: 0xFF1253A0,
    800: 0xFF124684,
    900: 0xFF123A6B,
    950: 0xFF0C2647,
  };

  /// Noir Anthracite : textes et barres sombres (DEFAULT = 900).
  static const Map<int, int> anthracite = {
    800: 0xFF2B2B2B,
    900: 0xFF212121,
    950: 0xFF1A1A1A,
  };

  /// RÉAFFECTÉ (maquette Baguidi) : 50 à 900 = Bleu Santé à l'identique, 950 = Noir Anthracite.
  static const Map<int, int> navy = {
    50: 0xFFEEF4FC,
    100: 0xFFD9E7F8,
    200: 0xFFB6D0F1,
    300: 0xFF8AB3E8,
    400: 0xFF5590DA,
    500: 0xFF2F74CC,
    600: 0xFF1565C0,
    700: 0xFF1253A0,
    800: 0xFF124684,
    900: 0xFF123A6B,
    950: 0xFF212121,
  };
  static const Map<int, int> success = {
    50: 0xFFEEFBF4,
    100: 0xFFD6F5E3,
    200: 0xFFB0E9CC,
    300: 0xFF7BD7AE,
    400: 0xFF45BD8B,
    500: 0xFF22A170,
    600: 0xFF15825A,
    700: 0xFF12684A,
    800: 0xFF12523C,
    900: 0xFF104433,
  };
  static const Map<int, int> warning = {
    50: 0xFFFFF8EB,
    100: 0xFFFFEDC6,
    200: 0xFFFFD888,
    300: 0xFFFFBE4A,
    400: 0xFFFFA620,
    500: 0xFFF98307,
    600: 0xFFDD5F02,
    700: 0xFFB74106,
    800: 0xFF94320C,
    900: 0xFF7A2A0D,
  };
  static const Map<int, int> danger = {
    50: 0xFFFEF2F2,
    100: 0xFFFEE2E2,
    200: 0xFFFECACA,
    300: 0xFFFCA5A5,
    400: 0xFFF87171,
    500: 0xFFEF4444,
    600: 0xFFDC2626,
    700: 0xFFB91C1C,
    800: 0xFF991B1B,
    900: 0xFF7F1D1D,
  };
  static const Map<int, int> info = {
    50: 0xFFEFF8FF,
    100: 0xFFDBEEFE,
    200: 0xFFBFE2FE,
    300: 0xFF92D0FD,
    400: 0xFF61B6FA,
    500: 0xFF3B98F6,
    600: 0xFF257AEB,
    700: 0xFF1D63D8,
    800: 0xFF1E51AF,
    900: 0xFF1E468A,
  };
  static const List<String> policeSans = [
    'Inter',
    'Segoe UI',
    'system-ui',
    'sans-serif'
  ];

  /// `font-heading` de la maquette : titres, en-têtes d'écran, dénomination imprimée.
  static const List<String> policeTitres = [
    'Montserrat',
    'Inter',
    'Segoe UI',
    'system-ui',
    'sans-serif'
  ];

  /// `font-slogan` de la maquette : EXCLUSIVEMENT la devise.
  static const List<String> policeSlogan = [
    'Dancing Script',
    'Segoe Script',
    'cursive'
  ];
  static const List<String> policeMono = [
    'Consolas',
    'ui-monospace',
    'monospace'
  ];

  /// Taille de texte minimale (CDCT) : 11 pt équivalent.
  static const double tailleMinimalePt = 11;
}
