/// LES TAUX ET LE BARÈME DE LA PAIE, VERSIONNÉS PAR DATE D'EFFET (lot 1 de l'inventaire des valeurs en dur, `docs/architecture/INVENTAIRE-VALEURS-EN-DUR.md`,
/// défauts graves n° 4 et 5).
///
/// La CNSS (part ouvrière 3,6 %, part patronale 16,4 %), le VPS (4 %) et le barème progressif de l'ITS vivaient en constantes du moteur de paie : un changement
/// de taux exigeait une nouvelle version du logiciel, et la « confirmation fiscale » ne faisait que recopier la constante. Ils deviennent des PARAMÈTRES DE
/// CLINIQUE de la collection `parametres` (famille R : la mère seule écrit ; famille [paiFamilleBaremes], réservée : jamais vers un téléphone, RG-13), déclarés
/// dans `definitions.dart` avec pour DÉFAUT SEMÉ la valeur d'avant (aucun bulletin ne change). Trois règles :
///
///  * le moteur les lit À LA DATE DU BULLETIN (le premier jour de la période de paie, comme les paramètres ORTB) : une version datée du 1er janvier ne touche
///    pas le bulletin de décembre ;
///  * un bulletin GÉNÉRÉ porte les taux qui l'ont calculé (`tauxPaie`) : il ne se recalcule jamais, et sa pièce imprime SES taux, pas ceux du jour ;
///  * une version nouvelle se pose par la confirmation fiscale (geste réservé `fiscal_confirmer`, motif obligatoire, `confirmations_fiscales.dart`), jamais par
///    le panneau générique des paramètres (la famille a son réglage dédié).
///
/// Symboles préfixés `pai` / `Pai`. Fonctions PURES : l'appelant écrit, journalise (RG-12) et notifie.
library;

import 'dart:convert';

import '../format/js.dart' show arrondiJs;
import '../parametres/definitions.dart' show definitionDeParametre;
import '../parametres/parametres.dart';
import '../referentiels/versions_datees.dart' show isoJour;

/// La famille des taux et barèmes fiscaux et sociaux dans le registre des paramètres (CNSS, VPS, ITS, prime d'ancienneté, TVA du régime normal) : RÉSERVÉE (jamais vers
/// un téléphone : rémunération et fiscal, RG-13) et à réglage DÉDIÉ (la confirmation fiscale, sous le geste `fiscal_confirmer`).
const String paiFamilleBaremes = 'taux_fiscaux';

/// Les clés des paramètres (une version = une fiche de la collection `parametres`).
const String paiCleCnssOuvriere = 'taux_fiscaux.cnssTauxOuvrier';
const String paiCleCnssPatronale = 'taux_fiscaux.cnssTauxPatronal';
const String paiCleVps = 'taux_fiscaux.vpsTaux';
const String paiCleBaremeIts = 'taux_fiscaux.baremeIts';
const String paiCleAncienneteTaux = 'taux_fiscaux.primeAncienneteTaux';
const String paiCleAncienneteSeuil = 'taux_fiscaux.primeAncienneteSeuilAns';
const String paiCleTvaNormal = 'taux_fiscaux.tvaTauxNormal';
const List<String> paiClesBaremes = [paiCleCnssOuvriere, paiCleCnssPatronale, paiCleVps, paiCleBaremeIts, paiCleAncienneteTaux, paiCleAncienneteSeuil, paiCleTvaNormal];

// --- LES SEMENCES (lues par `definitions.dart` et par [PaiTauxPaie.semence], jamais ailleurs) ------------------------------------------------------------
/// CNSS : part ouvrière 3,6 %, part patronale 16,4 % (sans plafond), CDCT §10.10 (`D.PARAM_PAIE.cnss` de la maquette).
const double paiCnssOuvriereSemence = 3.6;
const double paiCnssPatronaleSemence = 16.4;

/// VPS : 4 % du salaire brut (versement patronal de solidarité), `D.PARAM_PAIE.vps`.
const double paiVpsTauxSemence = 4;

/// La prime d'ancienneté (`m11-paie.js`) : 2 % du salaire de base PAR ANNÉE d'ancienneté, à partir de 2 ans. Le moteur de paie et la fiche d'évaluation NS 131
/// la lisaient chacun en dur (deux copies) ; ils lisent désormais ces paramètres, par [paiPrimeAnciennete].
const double paiAncienneteTauxSemence = 2;
const int paiAncienneteSeuilAnsSemence = 2;

/// La TVA du régime NORMAL (`D.PARAM_FISCAL.regimesTva`, 18 %) : la configuration fiscale choisit le régime (exonéré pour les actes de santé, le régime de Baguidi) ;
/// le taux du régime normal est un paramètre daté.
const double paiTvaNormalSemence = 18;

/// Le barème ITS de la maquette (`D.PARAM_PAIE.its`), « à confirmer par le service comptable » : tranches `[de, à (null = sans plafond), taux %]`, en JSON
/// parce que c'est ainsi que la version voyage (paramètre de type texte).
const String paiBaremeItsSemence = '[[0,60000,0],[60001,150000,10],[150001,250000,15],[250001,500000,19],[500001,null,30]]';

/// Une tranche du barème ITS : de [de] à [a] (`null` = sans plafond), au taux [taux] (%).
class PaiTranche {
  const PaiTranche(this.de, this.a, this.taux);
  final num de;
  final num? a;
  final num taux;

  @override
  bool operator ==(Object other) => other is PaiTranche && other.de == de && other.a == a && other.taux == taux;
  @override
  int get hashCode => Object.hash(de, a, taux);
  @override
  String toString() => '[$de, $a, $taux]';
}

num _canonNum(num v) => v == v.truncateToDouble() ? v.toInt() : v;

/// Le barème relu d'une valeur de paramètre (texte JSON) ou d'une liste ; `null` s'il est illisible.
List<PaiTranche>? paiBaremeItsDepuisJson(Object? v) {
  Object? l = v;
  if (v is String) {
    try {
      l = jsonDecode(v);
    } catch (_) {
      return null;
    }
  }
  if (l is! List || l.isEmpty) return null;
  final out = <PaiTranche>[];
  for (final t in l) {
    if (t is! List || t.length != 3) return null;
    final de = t[0], a = t[1], taux = t[2];
    if (de is! num || taux is! num || (a != null && a is! num)) return null;
    out.add(PaiTranche(_canonNum(de), a == null ? null : _canonNum(a as num), _canonNum(taux)));
  }
  return out;
}

/// Le barème sous la forme qui voyage (texte JSON, nombres entiers écrits sans décimale).
String paiBaremeItsVersJson(List<PaiTranche> b) => jsonEncode([
      for (final t in b) [_canonNum(t.de), t.a == null ? null : _canonNum(t.a!), _canonNum(t.taux)]
    ]);

/// Le contrôle d'un barème progressif : au moins une tranche, la première part de 0, chaque tranche commence au franc qui suit la précédente, la dernière (et
/// elle seule) est sans plafond, chaque taux entre 0 et 100 %. Rend le motif du refus, ou `null`.
String? paiControlerBaremeIts(List<PaiTranche> b) {
  if (b.isEmpty) return 'Le barème doit compter au moins une tranche.';
  if (b.first.de != 0) return 'La première tranche commence à 0 F.';
  for (var i = 0; i < b.length; i++) {
    final t = b[i];
    final rang = i + 1;
    if (t.taux < 0 || t.taux > 100 || !t.taux.isFinite) return 'Tranche $rang : le taux est un pourcentage entre 0 et 100.';
    final derniere = i == b.length - 1;
    if (derniere && t.a != null) return 'La dernière tranche est sans plafond (« et plus »).';
    if (!derniere && t.a == null) return 'Tranche $rang : seule la dernière tranche est sans plafond.';
    if (t.a != null && t.a! <= t.de) return 'Tranche $rang : le plafond doit dépasser le plancher.';
    if (i > 0 && t.de != b[i - 1].a! + 1) return 'Tranche $rang : elle commence au franc qui suit le plafond de la tranche ${rang - 1} (${b[i - 1].a! + 1}).';
  }
  return null;
}

/// Le barème écrit pour la saisie : une tranche par ligne, « plancher plafond taux », le plafond de la dernière s'écrivant « et plus ».
String paiBaremeItsVersSaisie(List<PaiTranche> b) => [for (final t in b) '${_canonNum(t.de)} ${t.a == null ? 'et plus' : _canonNum(t.a!)} ${_canonNum(t.taux)}'].join('\n');

/// Le barème relu d'une saisie (une tranche par ligne : plancher, plafond ou « et plus » / « - », taux ; les espaces de milliers et « % » sont tolérés) et
/// contrôlé ([paiControlerBaremeIts]). Rend le barème, ou le motif du refus.
({List<PaiTranche>? bareme, String? refus}) paiBaremeItsDepuisSaisie(String texte) {
  final out = <PaiTranche>[];
  final lignes = [for (final l in texte.split('\n')) if (l.trim().isNotEmpty) l.trim()];
  for (var i = 0; i < lignes.length; i++) {
    final l = lignes[i]
        .replaceAll(RegExp(r'et\s+plus', caseSensitive: false), ' - ')
        .replaceAll('%', ' ')
        .replaceAll(RegExp(r'(?<=\d)[\s  ]+(?=\d{3}\b)'), '')
        .replaceAll(',', '.');
    final mots = l.split(RegExp(r'[\s;]+')).where((m) => m.isNotEmpty).toList();
    if (mots.length != 3) return (bareme: null, refus: 'Ligne ${i + 1} : attendu « plancher plafond taux » (le plafond de la dernière tranche s’écrit « et plus »).');
    final de = num.tryParse(mots[0]);
    final a = mots[1] == '-' ? null : num.tryParse(mots[1]);
    final taux = num.tryParse(mots[2]);
    if (de == null || taux == null || (mots[1] != '-' && a == null)) return (bareme: null, refus: 'Ligne ${i + 1} : nombre illisible.');
    out.add(PaiTranche(_canonNum(de), a == null ? null : _canonNum(a), _canonNum(taux)));
  }
  final r = paiControlerBaremeIts(out);
  return r == null ? (bareme: out, refus: null) : (bareme: null, refus: r);
}

/// Le contrôle d'un taux de cotisation (pourcentage) : nombre fini, strictement positif, inférieur à 100. Rend le motif du refus, ou `null`.
String? paiControlerTaux(Object? v, String libelle) {
  if (v is! num || !v.isFinite) return '$libelle : un nombre est attendu.';
  if (v <= 0 || v >= 100) return '$libelle : un pourcentage strictement compris entre 0 et 100 est attendu.';
  return null;
}

/// Le contrôle d'un seuil en années (prime d'ancienneté) : entier de 0 à 40. Rend le motif du refus, ou `null`.
String? paiControlerSeuilAns(Object? v) {
  if (v is! num || !v.isFinite || v != v.truncateToDouble()) return 'Le seuil d’ancienneté est un nombre entier d’années.';
  if (v < 0 || v > 40) return 'Le seuil d’ancienneté est compris entre 0 et 40 ans.';
  return null;
}

/// LA PRIME D'ANCIENNETÉ, une seule règle (paie et fiche d'évaluation) : [t] taux % du salaire de base par année, dès le seuil ; arrondie au franc. [t] : les taux en
/// vigueur à la date de la pièce (absent : les semences, 2 % dès 2 ans).
double paiPrimeAnciennete(num salaireBase, int ans, [PaiTauxPaie? t]) {
  final x = t ?? PaiTauxPaie.semence;
  return ans >= x.ancienneteSeuilAns ? arrondiJs(salaireBase * (x.ancienneteTaux / 100) * ans) : 0.0;
}

/// La version d'une valeur datée : son numéro et sa date d'effet (`null` : la valeur semée, « depuis toujours »).
class PaiVersionTaux {
  const PaiVersionTaux(this.version, this.dateEffet);
  final int version;
  final String? dateEffet;
  bool get semee => dateEffet == null;
  /// Ce qui s'écrit sur le bulletin : aucun champ nul (une valeur semée n'a pas de date d'effet, elle n'en écrit pas).
  Map<String, Object?> get fiche => {'version': version, if (dateEffet != null) 'dateEffet': dateEffet};
  factory PaiVersionTaux.depuis(Object? f) => f is Map
      ? PaiVersionTaux((f['version'] as num?)?.toInt() ?? 0, f['dateEffet'] == null || '${f['dateEffet']}'.isEmpty ? null : '${f['dateEffet']}')
      : const PaiVersionTaux(0, null);

  /// « valeur semée » ou « version 2, en vigueur depuis le 01/01/2027 ».
  String get libelle => dateEffet == null
      ? 'valeur semée'
      : 'version $version, en vigueur depuis le ${dateEffet!.substring(8, 10)}/${dateEffet!.substring(5, 7)}/${dateEffet!.substring(0, 4)}';
}

/// LES TAUX DE LA PAIE en vigueur à une date : ce que le moteur applique au bulletin, et ce que les écrans affichent (jamais une constante).
class PaiTauxPaie {
  const PaiTauxPaie(
      {required this.cnssOuvriere,
      required this.cnssPatronale,
      required this.vps,
      required this.baremeIts,
      required this.ancienneteTaux,
      required this.ancienneteSeuilAns,
      required this.tvaNormal,
      this.versions = const {}});

  final num cnssOuvriere, cnssPatronale, vps;

  /// La prime d'ancienneté : [ancienneteTaux] % du salaire de base par année, dès [ancienneteSeuilAns] ans.
  final num ancienneteTaux;
  final int ancienneteSeuilAns;

  /// Le taux de TVA du régime NORMAL (le régime appliqué se choisit à la configuration fiscale).
  final num tvaNormal;
  final List<PaiTranche> baremeIts;

  /// La version de chaque valeur, par clé ([paiClesBaremes]) ; absente : la valeur semée.
  final Map<String, PaiVersionTaux> versions;

  /// Les valeurs semées (la graine des définitions) : ce que valait le moteur avant le lot, et ce qu'il applique sur un poste neuf.
  static final PaiTauxPaie semence = PaiTauxPaie(
      cnssOuvriere: paiCnssOuvriereSemence,
      cnssPatronale: paiCnssPatronaleSemence,
      vps: paiVpsTauxSemence,
      baremeIts: paiBaremeItsDepuisJson(paiBaremeItsSemence)!,
      ancienneteTaux: paiAncienneteTauxSemence,
      ancienneteSeuilAns: paiAncienneteSeuilAnsSemence,
      tvaNormal: paiTvaNormalSemence);

  /// Les valeurs EN VIGUEUR à [date] (la date de la pièce : le premier jour de la période d'un bulletin) dans les versions de la collection `parametres`
  /// ([parametres], fiches brutes ; les archivées sont ignorées). Sans version applicable, le défaut semé de la définition ; une valeur illisible (jamais écrite
  /// par le poste, qui contrôle avant d'écrire) retombe aussi sur le défaut semé.
  factory PaiTauxPaie.aLaDate(Iterable<Map<String, Object?>> parametres, Object? date) {
    final iso = isoJour(date is DateTime ? date : '${date ?? ''}');
    final versions = <Parametre>[
      for (final f in parametres)
        if (f['statut'] != 'archive' && paiClesBaremes.contains(f['cle'])) Parametre.fromJson(f)
    ];
    final vus = <String, PaiVersionTaux>{};
    Object? lire(String cle) {
      final r = Parametres.resoudre(cle, versions, iso, definition: definitionDeParametre(cle));
      if (!r.ok) return null;
      vus[cle] = PaiVersionTaux(r.valeur!.version, r.valeur!.dateEffet);
      return r.valeur!.valeur;
    }

    num taux(String cle, num repli) {
      final v = lire(cle);
      return v is num && paiControlerTaux(v, cle) == null ? v : repli;
    }

    final s = PaiTauxPaie.semence;
    final its = paiBaremeItsDepuisJson(lire(paiCleBaremeIts));
    final seuil = lire(paiCleAncienneteSeuil);
    final tva = lire(paiCleTvaNormal);
    return PaiTauxPaie(
        cnssOuvriere: taux(paiCleCnssOuvriere, s.cnssOuvriere),
        cnssPatronale: taux(paiCleCnssPatronale, s.cnssPatronale),
        vps: taux(paiCleVps, s.vps),
        baremeIts: its != null && paiControlerBaremeIts(its) == null ? its : s.baremeIts,
        ancienneteTaux: taux(paiCleAncienneteTaux, s.ancienneteTaux),
        ancienneteSeuilAns: seuil is num && paiControlerSeuilAns(seuil) == null ? seuil.toInt() : s.ancienneteSeuilAns,
        tvaNormal: tva is num && tva.isFinite && tva >= 0 && tva < 100 ? tva : s.tvaNormal,
        versions: vus);
  }

  /// Les taux PORTÉS par un bulletin généré (`tauxPaie`) ; `null` si le bulletin n'en porte pas (bulletin antérieur au lot).
  static PaiTauxPaie? depuisFiche(Object? f) {
    if (f is! Map) return null;
    final s = PaiTauxPaie.semence;
    num n(Object? v, num repli) => v is num ? v : repli;
    final vs = f['versions'];
    return PaiTauxPaie(
        cnssOuvriere: n(f['cnssOuvriere'], s.cnssOuvriere),
        cnssPatronale: n(f['cnssPatronale'], s.cnssPatronale),
        vps: n(f['vps'], s.vps),
        baremeIts: paiBaremeItsDepuisJson(f['baremeIts']) ?? s.baremeIts,
        ancienneteTaux: n(f['ancienneteTaux'], s.ancienneteTaux),
        ancienneteSeuilAns: n(f['ancienneteSeuilAns'], s.ancienneteSeuilAns).toInt(),
        tvaNormal: s.tvaNormal,
        versions: vs is Map ? {for (final e in vs.entries) '${e.key}': PaiVersionTaux.depuis(e.value)} : const {});
  }

  /// La version d'une clé (semée si elle n'a jamais été réglée).
  PaiVersionTaux version(String cle) => versions[cle] ?? const PaiVersionTaux(0, null);

  /// Ce qu'un bulletin généré PORTE (`tauxPaie`) : les taux qui l'ont calculé et leur version.
  Map<String, Object?> get fiche => {
        'cnssOuvriere': cnssOuvriere,
        'cnssPatronale': cnssPatronale,
        'vps': vps,
        'baremeIts': jsonDecode(paiBaremeItsVersJson(baremeIts)),
        'ancienneteTaux': ancienneteTaux,
        'ancienneteSeuilAns': ancienneteSeuilAns,
        'versions': {for (final c in paiClesBaremes) if (c != paiCleTvaNormal) c: version(c).fiche},
      };
}

/// La date à laquelle se lisent les taux d'un bulletin : le premier jour de sa période de paie ([mois] de 0 à 11), comme les paramètres ORTB.
String paiDateTauxBulletin(int annee, int mois) => isoJour(DateTime(annee, mois + 1, 1));

/// Les taux d'un bulletin STOCKÉ : ceux qu'il porte (`tauxPaie`) ; à défaut (bulletin antérieur au lot), ceux en vigueur au premier jour de sa période.
PaiTauxPaie paiTauxDuBulletin(Map<String, Object?> b, Iterable<Map<String, Object?>> parametres) {
  final portes = PaiTauxPaie.depuisFiche(b['tauxPaie']);
  if (portes != null) return portes;
  final annee = b['annee'] is num ? (b['annee'] as num).toInt() : int.tryParse('${b['annee']}');
  final mois = b['mois'] is num ? (b['mois'] as num).toInt() : int.tryParse('${b['mois']}');
  if (annee == null || mois == null) return PaiTauxPaie.semence;
  return PaiTauxPaie.aLaDate(parametres, paiDateTauxBulletin(annee, mois));
}

/// `calculITS(base)` sur un barème [bareme] (par défaut : le barème semé) : barème progressif par tranches, arrondi au franc ; `+ 1` sauf pour la première
/// tranche (qui commence à 0).
int paiCalculItsSur(num base, List<PaiTranche> bareme) {
  var impot = 0.0;
  for (final t in bareme) {
    final plafond = t.a ?? double.infinity;
    final b = base.toDouble();
    final tranche = (b < plafond ? b : plafond.toDouble()) - t.de + (t.de == 0 ? 0 : 1);
    final positive = tranche > 0 ? tranche : 0;
    if (positive > 0) impot += positive * t.taux / 100;
  }
  return arrondiJs(impot).toInt();
}

/// Le dernier mois de paie déjà GÉNÉRÉ (bulletins actifs) : `(annee, mois)`, `null` sans bulletin. Une version nouvelle d'un taux ne peut prendre effet qu'après
/// le premier jour de ce mois : sinon elle contredirait des bulletins déjà calculés.
({int annee, int mois})? paiDernierePeriodeGeneree(Iterable<Map<String, Object?>> bulletins) {
  ({int annee, int mois})? der;
  for (final b in bulletins) {
    if ('${b['statut'] ?? 'actif'}' == 'archive') continue;
    final a = b['annee'] is num ? (b['annee'] as num).toInt() : int.tryParse('${b['annee']}');
    final m = b['mois'] is num ? (b['mois'] as num).toInt() : int.tryParse('${b['mois']}');
    if (a == null || m == null) continue;
    if (der == null || a * 12 + m > der.annee * 12 + der.mois) der = (annee: a, mois: m);
  }
  return der;
}
