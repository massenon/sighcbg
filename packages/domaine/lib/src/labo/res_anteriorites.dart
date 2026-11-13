/// LES ANTÉRIORITÉS D'UN EXAMEN — lot A1. Port du COMPORTEMENT du moteur de la clinique sœur (`SIGH.laboAnteriorites`), non de son code : fonctions pures,
/// les collections arrivent en argument ([JeuLabo]).
///
/// Une antériorité est une mesure RENDUE du même examen, pour le même patient, antérieure à la mesure lue. Quatre règles, tenues ici et nulle part
/// ailleurs (le comparatif, la courbe, la fiche imprimée et l'écran de validation biologique les appellent) :
///  1. RENDUE seulement ([resultatRendu] : validée biologiquement ou rectifiée). Une saisie, même validée techniquement, n'entre JAMAIS dans une
///     antériorité : le prescripteur ne la voit pas encore, la comparer reviendrait à lire par-dessus l'épaule du laboratoire.
///  2. Dans le périmètre du RBAC métier ([peutVoirResultat]) : on ne compare que ce qu'on a le droit de voir. Ce qui est masqué est COMPTÉ et son
///     motif est rendu, pour que l'écran le dise.
///  3. Ordre chronologique (date de la demande, puis référence).
///  4. Au plus N à l'écran (N = réglage `nbAnterioritesLabo` de la collection `reglages`, défaut 3) ; la fiche imprimée n'en lit qu'une, la plus
///     récente, par variable. Chaque mesure se juge aux bornes de SON époque ([variableALaDate]).
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import 'res_comparatif.dart';
import 'res_etats.dart';
import 'res_habilitations.dart';
import 'res_plages.dart';
import 'res_saisie.dart';
import 'res_seuils.dart';

/// Le nombre d'antériorités affichées, quand rien n'est réglé.
const int nbAnterioritesDefaut = 3;

/// Bornes du réglage : une comparaison de plus de douze colonnes ne se lit plus (hypothèse, à valider).
const int nbAnterioritesMax = 12;

/// La fiche de la collection `reglages` qui porte le nombre (champ `valeur`).
const String cleReglageAnteriorites = 'nbAnterioritesLabo';

/// Le nombre d'antériorités réglé en base ; un réglage absent, illisible ou hors bornes (1 à 12) retombe sur 3.
int nbAnterioritesReglees(Iterable<FicheLabo> reglagesActifs) {
  for (final f in reglagesActifs) {
    if (f['id'] != cleReglageAnteriorites) continue;
    final v = f['valeur'];
    final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());
    if (n != null && n >= 1 && n <= nbAnterioritesMax) return n;
  }
  return nbAnterioritesDefaut;
}

/// Tout ce que lisent les antériorités : les collections ACTIVES, la session qui regarde, le jour.
class JeuLabo {
  const JeuLabo({
    required this.demandes,
    required this.examens,
    required this.variables,
    required this.plages,
    required this.unites,
    this.seuils = const [],
    this.session,
    required this.aujourdhui,
    this.nombre = nbAnterioritesDefaut,
  });
  final Iterable<FicheLabo> demandes;
  final Iterable<FicheLabo> examens;
  final Iterable<FicheLabo> variables;
  final Iterable<FicheLabo> plages;
  final Iterable<FicheLabo> unites;
  final Iterable<FicheLabo> seuils;
  final SessionLabo? session;
  final DateTime aujourdhui;

  /// Le nombre d'antériorités affichées ([nbAnterioritesReglees]).
  final int nombre;
}

const List<String> typesQualitatifs = ['binaire', 'ternaire', 'liste', 'titre'];

bool _vide(Object? x) => x == null || x == '';
bool _vrai(Object? x) => x != null && x != false && x != '' && x != 0;

/// `cleChrono(d)` : date de la demande, puis référence.
String cleChrono(FicheLabo d) =>
    '${_vrai(d['dateHeure']) ? d['dateHeure'] : (_vrai(d['date']) ? d['date'] : '')}#${_vrai(d['reference']) ? d['reference'] : (d['id'] ?? '')}';

bool estQualitative(FicheLabo variable) => typesQualitatifs.contains(variable['type']);

/// Les mesures rendues d'un examen pour un patient : [visibles] (chronologiques), [cachees] (hors du périmètre du profil) et le [motif] de la restriction.
class MesuresRendues {
  const MesuresRendues(this.visibles, this.cachees, this.motif);
  final List<FicheLabo> visibles;
  final List<FicheLabo> cachees;
  final String? motif;
}

MesuresRendues mesuresRendues(Object? patientId, String? codeExamen, JeuLabo j) {
  final idx = [
    for (final r in j.demandes)
      if (r['patientId'] == patientId &&
          resultatRendu(r['etatAnalyse']) &&
          r['valeurs'] is Map &&
          (r['valeurs'] as Map).isNotEmpty &&
          codeExamenDe(r, j.examens) == codeExamen)
        r
  ];
  final tri = [for (var i = 0; i < idx.length; i++) (i, idx[i])]..sort((a, b) {
      final c = cleChrono(a.$2).compareTo(cleChrono(b.$2));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  final toutes = [for (final x in tri) x.$2];
  final visibles = filtrerResultats(toutes, j.session);
  final cachees = [for (final r in toutes) if (!visibles.contains(r)) r];
  return MesuresRendues(visibles, cachees, cachees.isEmpty ? null : peutVoirResultat(cachees.first, j.session).motif);
}

/// Les antériorités d'une mesure : [toutes] (chronologiques), [mesures] (les n plus récentes), [masquees] (comptées, jamais montrées) et le [motif].
class Anterieures {
  const Anterieures(this.toutes, this.mesures, this.masquees, this.motif);
  final List<FicheLabo> toutes;
  final List<FicheLabo> mesures;
  final int masquees;
  final String? motif;
}

/// [n] : `null` = toutes (la valeur précédente d'une variable se cherche dans toutes les antériorités, pas dans les seules colonnes affichées).
Anterieures anterieuresDe(FicheLabo demande, JeuLabo j, {int? n, bool toutes = false}) {
  final m = mesuresRendues(demande['patientId'], codeExamenDe(demande, j.examens), j);
  final cle = cleChrono(demande);
  bool avant(FicheLabo x) => x['id'] != demande['id'] && cleChrono(x).compareTo(cle) < 0;
  final tout = [for (final x in m.visibles) if (avant(x)) x];
  final cachees = [for (final x in m.cachees) if (avant(x)) x];
  final nb = toutes ? tout.length : (n ?? j.nombre);
  final mesures = tout.length <= nb ? tout : tout.sublist(tout.length - nb);
  return Anterieures(tout, mesures, cachees.length, cachees.isEmpty ? null : peutVoirResultat(cachees.first, j.session).motif);
}

/// La mesure précédente d'UNE variable : la plus récente des antériorités qui porte une valeur pour elle.
({Object? valeur, FicheLabo demande})? derniereValeurAnterieure(FicheLabo demande, String codeVariable, JeuLabo j) {
  final a = anterieuresDe(demande, j, toutes: true).toutes;
  for (var i = a.length - 1; i >= 0; i--) {
    final v = ((a[i]['valeurs'] as Map?) ?? const {})[codeVariable];
    if (!_vide(v)) return (valeur: v, demande: a[i]);
  }
  return null;
}

/// La variation d'une variable entre deux mesures. Trois natures : numérique (sens, écart signé, pourcentage ; une valeur précédente NULLE ne se divise
/// pas, elle le dit : [divisionParZero], [pourcent] vaut `null`) ; qualitative (comparaison en TEXTE, jamais de pourcentage) ; aucune (variable de
/// traçabilité, texte libre : rien à comparer, `null`).
class VariationLabo {
  const VariationLabo.numerique(
      {required this.avant, required this.apres, required this.ecart, required this.sens, required this.divisionParZero, required this.pourcent})
      : mode = 'numerique';
  const VariationLabo.texte({required this.avant, required this.apres, required this.sens})
      : mode = 'texte',
        ecart = null,
        divisionParZero = false,
        pourcent = null;
  final String mode;
  final Object avant;
  final Object apres;
  final double? ecart;

  /// `hausse` | `baisse` | `egal` (numérique) ; `egal` | `change` (texte).
  final String sens;
  final bool divisionParZero;
  final double? pourcent;
  double? get ecartAbsolu => ecart?.abs();
}

/// En deçà de cette valeur absolue, la valeur précédente est tenue pour NULLE : un pourcentage calculé sur une quasi-zéro est trompeur (décision de la
/// Direction du 13/11/2026). Aucun document ne fixe de seuil de proximité propre à une variable : la borne n'écarte que le bruit de virgule flottante,
/// toute valeur réellement mesurée (même 0,01) se divise.
const double epsilonValeurPrecedente = 1e-9;

double? _nombreJs(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

VariationLabo? variationEntre(FicheLabo? variable, Object? avant, Object? apres) {
  if (variable == null || _vide(avant) || _vide(apres)) return null;
  if (_vrai(variable['accompagnement'])) return null;
  final qualitative = estQualitative(variable);
  final a = _nombreJs(avant), b = _nombreJs(apres);
  if (!qualitative && variable['type'] == 'numerique' && a != null && b != null && a.isFinite && b.isFinite) {
    final ecart = arrondiJs((b - a) * 1e6) / 1e6;
    return VariationLabo.numerique(
        avant: a,
        apres: b,
        ecart: ecart,
        sens: ecart > 0 ? 'hausse' : (ecart < 0 ? 'baisse' : 'egal'),
        divisionParZero: a.abs() < epsilonValeurPrecedente,
        pourcent: a.abs() < epsilonValeurPrecedente ? null : arrondiJs(ecart / a.abs() * 10000) / 100);
  }
  if (qualitative || variable['type'] == 'numerique') {
    final ta = '$avant'.trim(), tb = '$apres'.trim();
    return VariationLabo.texte(avant: ta, apres: tb, sens: ta.toLowerCase() == tb.toLowerCase() ? 'egal' : 'change');
  }
  return null;
}

/// La phrase d'une variation, pour l'écran comme pour la pièce imprimée ([suffixe] : unité précédée d'une espace, ou vide).
String texteVariation(VariationLabo? v, [String suffixe = '']) {
  if (v == null) return 'Aucune antériorité';
  if (v.mode == 'texte') {
    return v.sens == 'egal' ? 'Inchangé (${v.apres})' : '${v.avant} puis ${v.apres}';
  }
  final ecart = v.ecart!;
  final signe = v.sens == 'hausse' ? '↑ +' : (v.sens == 'baisse' ? '↓ ' : '= ');
  final t = '$signe${chaineJs(arrondiJs(ecart * 100) / 100)}$suffixe';
  if (v.divisionParZero) return '$t (écart relatif non calculable : valeur précédente ${v.avant == 0 ? 'nulle' : 'proche de zéro'})';
  final p = v.pourcent!;
  return '$t (${p > 0 ? '+' : ''}${nombre(p, 1)} %)';
}

/// L'alerte d'une variation (lot A2) : `null` quand aucun seuil Validé n'est en vigueur à [date] (pas d'alerte configurée), ou que la variation n'est pas
/// numérique ; sinon l'alerte, qui SIGNALE et ne bloque jamais.
AlerteVariation? alerteVariation(FicheLabo? variable, VariationLabo? variation, Object? date, Iterable<FicheLabo> seuilsActifs, {required DateTime aujourdhui}) {
  if (variable == null || variation == null || variation.mode != 'numerique') return null;
  final s = seuilEnVigueur('${variable['id']}', date, seuilsActifs, aujourdhui: aujourdhui);
  if (s == null || s['retrait'] == true) return null;
  final raisons = <RaisonAlerte>[];
  final abs = _nombreJs(s['ecartAbsolu']), rel = _nombreJs(s['ecartRelatif']);
  if (abs != null && variation.ecartAbsolu! >= abs) raisons.add(RaisonAlerte('absolu', abs, variation.ecartAbsolu!));
  if (rel != null && variation.pourcent != null && variation.pourcent!.abs() >= rel) raisons.add(RaisonAlerte('relatif', rel, variation.pourcent!.abs()));
  return AlerteVariation(raisons.isNotEmpty, s, raisons, rel != null && variation.pourcent == null);
}

/// La date à laquelle une mesure se juge : celle de sa validation biologique si elle est rendue, aujourd'hui sinon.
String dateJugementMesure(FicheLabo d, DateTime aujourdhui) =>
    resultatRendu(d['etatAnalyse']) ? jourSeuil(_vrai(d['valideLe']) ? d['valideLe'] : d['dateHeure'], aujourdhui) : jourSeuil(null, aujourdhui);

String _suffixe(Object? uniteId, JeuLabo j) {
  final u = symboleUnite(uniteId, j.unites);
  return u == '—' ? '' : ' $u';
}

/// Une cellule du comparatif : la mesure, sa valeur, l'écart à SES bornes (`bas` | `haut` | `anormal` | `null`) et ses références d'époque.
class CelluleComparatif {
  const CelluleComparatif(this.demande, this.valeur, this.ecart, this.reference);
  final FicheLabo demande;
  final Object? valeur;
  final String? ecart;
  final String reference;
}

/// Une ligne du comparatif : une variable, ses cellules (une par colonne), la mesure précédente DE LA VARIABLE (pas forcément la colonne voisine), la
/// variation et l'alerte éventuelle.
class LigneModele {
  const LigneModele(this.variable, this.suffixe, this.cellules, this.precedente, this.variation, this.alerte);
  final FicheLabo variable;
  final String suffixe;
  final List<CelluleComparatif> cellules;
  final FicheLabo? precedente;
  final VariationLabo? variation;
  final AlerteVariation? alerte;
}

class ModeleComparatif {
  const ModeleComparatif(this.colonnes, this.lignes, this.anterieures, this.comparee);

  /// Les antériorités affichées (de la plus ancienne à la plus récente), puis la mesure comparée en dernière colonne.
  final List<FicheLabo> colonnes;
  final List<LigneModele> lignes;
  final Anterieures anterieures;
  final FicheLabo comparee;
}

/// Le modèle du comparatif d'une mesure [b] : construit une fois, il sert l'écran, la pièce imprimée et l'alerte.
ModeleComparatif modeleComparatif(String code, FicheLabo b, JeuLabo j) {
  final ant = anterieuresDe(b, j);
  final colonnes = [...ant.mesures, b];
  final lignes = <LigneModele>[];
  for (final v in variablesExamen(code, j.variables)) {
    if (v['actif'] == false || _vrai(v['accompagnement'])) continue;
    final valeurs = [for (final m in colonnes) ((m['valeurs'] as Map?) ?? const {})[v['code']]];
    if (valeurs.every(_vide)) continue;
    final cellules = [
      for (var i = 0; i < colonnes.length; i++)
        CelluleComparatif(
            colonnes[i],
            valeurs[i],
            _vide(valeurs[i]) ? null : ecart(variableALaDate(v, j.plages, colonnes[i]['dateHeure'], aujourdhui: j.aujourdhui), valeurs[i]),
            referenceALaDate(v, j.plages, colonnes[i]['dateHeure'], aujourdhui: j.aujourdhui))
    ];
    final vb = valeurs.last;
    final prec = _vide(vb) ? null : derniereValeurAnterieure(b, '${v['code']}', j);
    final variation = prec == null ? null : variationEntre(v, prec.valeur, vb);
    lignes.add(LigneModele(v, _suffixe(v['unite'], j), cellules, prec?.demande, variation,
        alerteVariation(v, variation, dateJugementMesure(b, j.aujourdhui), j.seuils, aujourdhui: j.aujourdhui)));
  }
  return ModeleComparatif(colonnes, lignes, ant, b);
}

/// Le texte d'une cellule de valeur (valeur et unité, ou un tiret quand la variable n'a pas été mesurée ce jour là).
String texteCellule(LigneModele l, CelluleComparatif c) => _vide(c.valeur) ? '—' : '${chaineJs(c.valeur)}${l.suffixe}';

/// LA COLONNE « ANTÉRIORITÉS » DE LA FICHE IMPRIMÉE : la mesure et la date de l'antériorité la plus récente, par variable. Jamais un blanc : une variable
/// sans antériorité imprime « Aucune antériorité », une variable de traçabilité (réactif, lot) « Sans objet ».
String texteAnterioriteImprimee(FicheLabo variable, FicheLabo demande, JeuLabo j) {
  if (_vrai(variable['accompagnement'])) return 'Sans objet';
  final ant = derniereValeurAnterieure(demande, '${variable['code']}', j);
  if (ant == null) return 'Aucune antériorité';
  return '${chaineJs(ant.valeur)}${_suffixe(variable['unite'], j)} (${dateFrJs(ant.demande['dateHeure'])})';
}

/// Les variations brutales d'UNE mesure (variables numériques seulement) : seules celles qui franchissent un seuil VALIDÉ.
class AlerteDeMesure {
  const AlerteDeMesure(this.variable, this.variation, this.alerte, this.precedente, this.suffixe);
  final FicheLabo variable;
  final VariationLabo variation;
  final AlerteVariation alerte;
  final FicheLabo precedente;
  final String suffixe;
}

List<AlerteDeMesure> alertesDe(FicheLabo demande, JeuLabo j) {
  final code = codeExamenDe(demande, j.examens);
  if (code == null || j.seuils.isEmpty) return const [];
  final out = <AlerteDeMesure>[];
  for (final v in variablesExamen(code, j.variables)) {
    if (v['actif'] == false || _vrai(v['accompagnement']) || v['type'] != 'numerique') continue;
    final val = ((demande['valeurs'] as Map?) ?? const {})[v['code']];
    if (_vide(val)) continue;
    final prec = derniereValeurAnterieure(demande, '${v['code']}', j);
    if (prec == null) continue;
    final variation = variationEntre(v, prec.valeur, val);
    final a = alerteVariation(v, variation, dateJugementMesure(demande, j.aujourdhui), j.seuils, aujourdhui: j.aujourdhui);
    if (a != null && a.alerte) out.add(AlerteDeMesure(v, variation!, a, prec.demande, _suffixe(v['unite'], j)));
  }
  return out;
}

/// « Variation brutale : seuil de 1 G/l ou 20 % atteint (seuil validé, version 2 du 15/11/2026) ».
String texteAlerte(AlerteVariation a, [String suffixe = '']) =>
    'Variation brutale : seuil de ${texteSeuil(a.seuil, suffixe)} atteint (seuil validé, version ${a.seuil['version']} du ${dateFrJs(a.seuil['dateEffet'])})';
