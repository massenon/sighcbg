/// LA MÉCANIQUE DES SPÉCIALITÉS — règles pures, rejouées par `test/spec_moteur_test.dart`.
///
/// Trois choses vivent ici et nulle part ailleurs : le FORMULAIRE qui naît du modèle d'une fiche (un seul générateur, comme `qualChampsDepuisModele`
/// pour les enquêtes), la PIÈCE qu'enregistre une consultation spécialisée, et les STATISTIQUES, toujours recomptées depuis les registres — jamais
/// fournies. L'identité des écrans dynamiques (`spec-<code>`, `spec-<code>-consultation`, …) s'y décide aussi : le manifeste en dérive ses entrées.
library;

import '../consultation/cs_referentiels.dart' show csAppareils, csTempsExamen;
import '../format/format_fr.dart';
import '../format/js.dart' show nombreOuZero;

typedef FicheSp = Map<String, Object?>;

bool _vrai(Object? v) => v != null && v != '' && v != false;

String _txt(Object? v) => v == null ? '' : '$v'.trim();

List<FicheSp> _liste(Object? v) => [for (final x in (v as List? ?? const [])) (x as Map).cast<String, Object?>()];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// L'IDENTITÉ DES ÉCRANS
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les quatre vues génériques d'une spécialité : le hub (l'entrée du ruban), la consultation, l'agenda et la file, les statistiques.
enum SpecVue {
  hub('', 'Accueil'),
  consultation('-consultation', 'Consultations'),
  agenda('-agenda', 'Agenda et file'),
  stats('-stats', 'Statistiques');

  const SpecVue(this.suffixe, this.libelle);
  final String suffixe;
  final String libelle;
}

const specPrefixe = 'spec-';

/// Le module et la rangée du ruban qui portent les spécialités : une rangée SECONDAIRE de M2, dans le domaine Soins (le module ne change pas : les
/// droits ne bougent pas d'un pouce).
const specModule = 'M2';
const specDomaine = 'Soins';
const specRangeeLibelle = 'Spécialités';

/// L'écran du répertoire administrable des spécialités (statique, au manifeste).
const specEcranRepertoire = 'm2-specialites';

/// L'identifiant d'écran d'une vue d'une spécialité : `spec-cardiologie`, `spec-cardiologie-agenda`…
String specIdEcran(String code, [SpecVue vue = SpecVue.hub]) => '$specPrefixe$code${vue.suffixe}';

/// L'inverse : à quelle spécialité et à quelle vue répond cet identifiant d'écran ? `null` si ce n'en est pas un (ou si la spécialité est inconnue).
/// L'analyse part des codes CONNUS : un code peut contenir des tirets (`medecine-travail`), un suffixe ne se devine donc pas.
({String code, SpecVue vue})? specAnalyserId(String id, Iterable<String> codes) {
  if (!id.startsWith(specPrefixe)) return null;
  final reste = id.substring(specPrefixe.length);
  final connus = codes.toSet();
  for (final v in SpecVue.values.reversed) {
    if (v == SpecVue.hub) continue;
    if (reste.endsWith(v.suffixe) && connus.contains(reste.substring(0, reste.length - v.suffixe.length))) {
      return (code: reste.substring(0, reste.length - v.suffixe.length), vue: v);
    }
  }
  return connus.contains(reste) ? (code: reste, vue: SpecVue.hub) : null;
}

/// Les droits d'une vue se LISENT sur un écran statique du manifeste (la matrice engendrée reste l'unique source) : le hub et l'agenda suivent la file
/// d'attente (l'accueil y écrit), la consultation suit le dossier de consultation (clinique : l'accueil n'y entre pas, RG-13), les statistiques suivent
/// celles des consultations.
const specModelesDroits = {
  SpecVue.hub: 'm2-file-attente',
  SpecVue.agenda: 'm2-file-attente',
  SpecVue.consultation: 'm2-dossiers-consultation',
  SpecVue.stats: 'm2-stats-consultations',
};

final _formeCode = RegExp(r'^[a-z][a-z0-9]*(-[a-z0-9]+)*$');

/// Le refus nommé d'un code de spécialité, `null` s'il convient. Le code entre dans les adresses d'écran : minuscules, chiffres et tirets, et jamais
/// un suffixe réservé (`-consultation`, `-agenda`, `-stats`), qui rendrait l'adresse ambiguë.
String? specRefusCode(String code, Iterable<String> existants) {
  if (code.isEmpty) return 'Le code de la spécialité est obligatoire.';
  if (!_formeCode.hasMatch(code)) return 'Le code ne peut porter que des minuscules sans accent, des chiffres et des tirets (exemple : dermatologie).';
  for (final v in SpecVue.values) {
    if (v.suffixe.isNotEmpty && code.endsWith(v.suffixe)) return 'Le code ne peut pas finir par « ${v.suffixe} » : ce suffixe désigne une vue de la spécialité.';
  }
  if (existants.contains(code)) return 'Une spécialité porte déjà le code « $code ».';
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// LE FORMULAIRE QUI NAÎT DU MODÈLE
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Un champ du formulaire engendré. `type` : `section` · `texte` · `textarea` · `nombre` · `select` · `date`.
class SpecChamp {
  const SpecChamp(this.nom, this.libelle, this.type,
      {this.requis = false, this.plein = false, this.options = const [], this.aide, this.min, this.max, this.lignes = 3});
  final String nom;
  final String libelle;
  final String type;
  final bool requis;
  final bool plein;
  final List<String> options;
  final String? aide;
  final num? min;
  final num? max;
  final int lignes;
}

const specPrefixeQuestion = 'q_';
const specPrefixeExamen = 'ex.';
const specChampsAntecedents = [
  ('ant_medicaux', 'Antécédents médicaux'),
  ('ant_chirurgicaux', 'Antécédents chirurgicaux'),
  ('ant_gyneco_obstetricaux', 'Antécédents gynéco-obstétricaux'),
];

String _libelleAvecUnite(FicheSp q) => _vrai(q['unite']) ? '${q['libelle']} (${q['unite']})' : '${q['libelle']}';

/// LE générateur : un modèle → les champs du formulaire de consultation. Les questions du modèle (préfixe `q_`), puis l'examen clinique par appareil
/// repris du dossier de consultation générique (quatre temps : inspection, palpation, percussion, auscultation — préfixe `ex.`), puis les antécédents
/// (mêmes noms de champ que le dossier de consultation), puis la conclusion, qui est de toutes les spécialités.
List<SpecChamp> specChampsDepuisModele(Object? modele) {
  final m = (modele as Map?)?.cast<String, Object?>() ?? const {};
  final champs = <SpecChamp>[];
  for (final s in _liste(m['sections'])) {
    champs.add(SpecChamp('', '${s['titre']}', 'section', plein: true));
    for (final q in _liste(s['champs'])) {
      final type = '${q['type']}';
      final options = [for (final o in (q['options'] as List? ?? const [])) '$o'];
      final nom = '$specPrefixeQuestion${q['code']}';
      final requis = q['requis'] == true;
      final plein = q['plein'] == true;
      final min = q['min'] as num?, max = q['max'] as num?;
      champs.add(switch (type) {
        'nombre' => SpecChamp(nom, _libelleAvecUnite(q), 'nombre',
            requis: requis, plein: plein, min: min, max: max, aide: _vrai(q['aide']) ? '${q['aide']}' : null),
        'choix' || 'oui_non' => SpecChamp(nom, '${q['libelle']}', 'select',
            requis: requis, plein: plein, options: type == 'oui_non' && options.isEmpty ? const ['Oui', 'Non'] : options, aide: _vrai(q['aide']) ? '${q['aide']}' : null),
        'longtexte' => SpecChamp(nom, '${q['libelle']}', 'textarea', requis: requis, plein: true, lignes: 3, aide: _vrai(q['aide']) ? '${q['aide']}' : null),
        'date' => SpecChamp(nom, '${q['libelle']}', 'date', requis: requis, plein: plein),
        _ => SpecChamp(nom, '${q['libelle']}', 'texte', requis: requis, plein: plein, aide: _vrai(q['aide']) ? '${q['aide']}' : null),
      });
    }
  }
  final appareils = [for (final a in (m['appareils'] as List? ?? const [])) '$a'];
  if (appareils.isNotEmpty) {
    champs.add(const SpecChamp('', 'Examen clinique', 'section', plein: true));
    for (final code in appareils) {
      final a = csAppareils.where((x) => x['code'] == code).firstOrNull;
      final aides = (a?['aides'] as Map?)?.cast<String, Object?>() ?? const {};
      for (final t in csTempsExamen) {
        final tc = '${t['code']}';
        champs.add(SpecChamp('$specPrefixeExamen$code.$tc', '${a?['label'] ?? code} — ${t['label']}', 'texte',
            aide: _vrai(aides[tc]) && aides[tc] != '—' ? '${aides[tc]}' : null));
      }
    }
  }
  if (m['antecedents'] == true) {
    champs.add(const SpecChamp('', 'Antécédents', 'section', plein: true));
    for (final (nom, libelle) in specChampsAntecedents) {
      champs.add(SpecChamp(nom, libelle, 'textarea', plein: true, lignes: 2));
    }
  }
  champs.add(const SpecChamp('', 'Conclusion', 'section', plein: true));
  champs.add(const SpecChamp('diagnostic', 'Diagnostic retenu', 'texte', requis: true, plein: true));
  champs.add(const SpecChamp('conduite', 'Conduite à tenir', 'textarea', plein: true, lignes: 3));
  return champs;
}

/// Le refus nommé d'un modèle qu'on enregistre, `null` s'il convient : un questionnaire sans aucune question ne recueille rien, et deux questions de
/// même code se répondraient l'une l'autre.
String? specRefusModele(Object? modele) {
  final m = (modele as Map?)?.cast<String, Object?>() ?? const {};
  final codes = <String>{};
  var n = 0;
  for (final s in _liste(m['sections'])) {
    for (final q in _liste(s['champs'])) {
      final code = '${q['code']}';
      if (code.isEmpty || code == 'null') return 'Chaque question porte un code.';
      if (!codes.add(code)) return 'Deux questions portent le code « $code ».';
      if (q['type'] == 'choix' && (q['options'] as List? ?? const []).isEmpty) return 'La question « ${q['libelle']} » est un choix sans aucune option.';
      n++;
    }
  }
  final appareils = (m['appareils'] as List? ?? const []);
  if (n == 0 && appareils.isEmpty) return 'Un modèle sans question ni examen clinique ne recueille rien.';
  return null;
}

/// Les questions d'un modèle À PLAT (l'éditeur les liste dans l'ordre) : chacune porte le titre de sa section. Le contraire de [specModeleDepuisQuestions].
List<FicheSp> specQuestionsPlates(Object? modele) => [
      for (final s in _liste((modele as Map?)?['sections']))
        for (final q in _liste(s['champs'])) {...q, 'section': '${s['titre']}'}
    ];

/// Un modèle depuis des questions à plat : les questions CONSÉCUTIVES de même section se regroupent (l'ordre saisi est l'ordre du formulaire) ; une
/// question sans section tombe dans « Questions ». Les champs que l'éditeur laisse vides (options, unité, bornes) ne sont pas écrits.
Map<String, Object?> specModeleDepuisQuestions(List<FicheSp> questions, {List<String> appareils = const [], bool antecedents = false, int version = 1}) {
  final sections = <Map<String, Object?>>[];
  for (final q in questions) {
    final titre = _txt(q['section']).isEmpty ? 'Questions' : _txt(q['section']);
    if (sections.isEmpty || sections.last['titre'] != titre) sections.add({'titre': titre, 'champs': <Map<String, Object?>>[]});
    (sections.last['champs'] as List<Map<String, Object?>>).add({
      for (final e in q.entries)
        if (e.key != 'section' && e.value != null && e.value != '' && !(e.value is List && (e.value as List).isEmpty) && e.value != false) e.key: e.value
    });
  }
  return {'version': version, 'sections': sections, 'appareils': appareils, 'antecedents': antecedents};
}

/// Ce que le formulaire a recueilli, rangé comme la consultation le garde.
class SpecSaisie {
  const SpecSaisie({required this.reponses, required this.examensPhysiques, required this.antecedents, required this.diagnostic, required this.conduite});

  /// `code de question → valeur` (un nombre reste un nombre) ; une réponse vide n'est pas écrite.
  final Map<String, Object?> reponses;

  /// `appareil → {temps → texte}` : la forme du dossier de consultation générique.
  final Map<String, Object?> examensPhysiques;
  final Map<String, Object?> antecedents;
  final String diagnostic;
  final String conduite;
}

SpecSaisie specSeparer(Object? modele, Map<String, Object?> valeurs) {
  final reponses = <String, Object?>{};
  final examens = <String, Object?>{};
  final antecedents = <String, Object?>{};
  final types = {
    for (final s in _liste((modele as Map?)?['sections']))
      for (final q in _liste(s['champs'])) '${q['code']}': '${q['type']}'
  };
  for (final e in valeurs.entries) {
    final v = e.value;
    if (v == null || v == '' || (v is List && v.isEmpty)) continue;
    if (e.key.startsWith(specPrefixeQuestion)) {
      final code = e.key.substring(specPrefixeQuestion.length);
      reponses[code] = types[code] == 'nombre' ? nombreOuZero(v) : v;
    } else if (e.key.startsWith(specPrefixeExamen)) {
      final parts = e.key.substring(specPrefixeExamen.length).split('.');
      if (parts.length == 2) {
        final a = (examens.putIfAbsent(parts[0], () => <String, Object?>{}) as Map<String, Object?>);
        a[parts[1]] = _txt(v);
      }
    } else if (specChampsAntecedents.any((x) => x.$1 == e.key)) {
      antecedents[e.key] = _txt(v);
    }
  }
  return SpecSaisie(
      reponses: reponses,
      examensPhysiques: examens,
      antecedents: antecedents,
      diagnostic: _txt(valeurs['diagnostic']),
      conduite: _txt(valeurs['conduite']));
}

/// Le refus nommé d'une saisie, `null` si elle convient : le diagnostic est obligatoire (sans lui, la consultation n'a rien conclu) et chaque nombre
/// reste dans les bornes que le modèle déclare (un poids de 900 kg est une faute de frappe, pas une donnée).
String? specRefusSaisie(Object? modele, Map<String, Object?> valeurs) {
  if (_txt(valeurs['diagnostic']).isEmpty) return 'Rédiger le diagnostic retenu.';
  for (final s in _liste((modele as Map?)?['sections'])) {
    for (final q in _liste(s['champs'])) {
      if (q['type'] != 'nombre') continue;
      final v = valeurs['$specPrefixeQuestion${q['code']}'];
      if (v == null || v == '') continue;
      final n = nombreOuZero(v);
      final min = q['min'] as num?, max = q['max'] as num?;
      if (min != null && n < min) return '« ${q['libelle']} » : la valeur ${nombre(n)} est inférieure au minimum ${nombre(min)}.';
      if (max != null && n > max) return '« ${q['libelle']} » : la valeur ${nombre(n)} dépasse le maximum ${nombre(max)}.';
    }
  }
  return null;
}

/// Les réponses d'une consultation, LISIBLES : libellé de la question (relu au modèle de la fiche) et valeur avec son unité. Une question retirée du
/// modèle depuis l'enregistrement reste lisible sous son code : modifier un modèle ne doit pas rendre illisible une consultation déjà signée.
List<({String libelle, String valeur})> specReponsesLisibles(Object? modele, Map<String, Object?> reponses) {
  final index = {
    for (final s in _liste((modele as Map?)?['sections']))
      for (final q in _liste(s['champs'])) '${q['code']}': q
  };
  return [
    for (final e in reponses.entries)
      (
        libelle: '${index[e.key]?['libelle'] ?? e.key}',
        valeur: '${e.value is num ? nombre(e.value as num) : e.value}${_vrai(index[e.key]?['unite']) ? ' ${index[e.key]!['unite']}' : ''}'
      )
  ];
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// LA PIÈCE QU'ENREGISTRE UNE CONSULTATION SPÉCIALISÉE
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le type que porte une consultation spécialisée au registre des consultations (la médecine du travail garde le sien).
const specTypeConsultation = 'Consultation spécialisée';
const specTypeMedecineTravail = 'Médecine du travail';
const specCodeMedecineTravail = 'medecine-travail';

/// À quelle spécialité appartient une consultation ? Le champ `specialite` l'écrit ; les visites de médecine du travail d'avant la mécanique (jeu livré
/// avant elle) ne le portent pas et se reconnaissent à leur type. `null` : consultation générale.
String? specDeLaConsultation(FicheSp c) {
  if (_vrai(c['specialite'])) return '${c['specialite']}';
  if (c['type'] == specTypeMedecineTravail) return specCodeMedecineTravail;
  return null;
}

/// La consultation spécialisée telle qu'on l'insère dans `consultations` : au dossier du patient comme toute consultation (mêmes champs de lecture :
/// `motif`, `diagnostic`, `medecin`, `date`), avec en plus la spécialité, les réponses et l'examen. [referenceExistantes] : les fiches dont on lit
/// la série `C00001`.
FicheSp specNouvelleConsultation({
  required FicheSp fiche,
  required FicheSp patient,
  required SpecSaisie saisie,
  required String praticien,
  String? praticienId,
  required DateTime date,
  required String reference,
  String? motif,
  num? tarif,
}) {
  final libelle = '${fiche['libelle']}';
  return {
    'statut': 'terminee',
    'reference': reference,
    'patientId': patient['id'],
    'patient': '${patient['nom']} ${patient['prenom']}',
    'patientCode': patient['code'],
    if (_vrai(praticienId)) 'medecinId': praticienId,
    'medecin': praticien,
    'date': date.toUtc().toIso8601String(),
    'motif': _vrai(motif) ? motif : '$libelle — consultation',
    'diagnostic': saisie.diagnostic,
    if (saisie.conduite.isNotEmpty) 'conduite': saisie.conduite,
    'type': specTypeConsultation,
    'specialite': '${fiche['code']}',
    'specialiteLibelle': libelle,
    'reponses': saisie.reponses,
    if (saisie.examensPhysiques.isNotEmpty) 'examensPhysiques': saisie.examensPhysiques,
    if (saisie.antecedents.isNotEmpty) 'antecedentsSaisis': saisie.antecedents,
    'tarif': tarif ?? 0,
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// LES STATISTIQUES : RECOMPTÉES, JAMAIS FOURNIES
// ---------------------------------------------------------------------------------------------------------------------------------------------

String _jour(Object? v) {
  final t = _txt(v);
  return t.length >= 10 ? t.substring(0, 10) : t;
}

class SpecStats {
  const SpecStats(
      {required this.consultations,
      required this.patients,
      required this.ceMois,
      required this.rendezVousAVenir,
      required this.fileEnAttente,
      required this.recettes,
      required this.parPraticien,
      required this.parMois,
      required this.parSexe,
      required this.diagnostics,
      required this.aptitudes});

  /// Consultations enregistrées sur la période.
  final int consultations;

  /// Patients DISTINCTS vus sur la période.
  final int patients;
  final int ceMois;
  final int rendezVousAVenir;
  final int fileEnAttente;

  /// Somme des montants facturés pour ces consultations (la caisse seule dit ce qui est encaissé).
  final num recettes;
  final List<({String libelle, int valeur})> parPraticien;

  /// `aaaa-mm → nombre`, du plus ancien au plus récent.
  final List<({String libelle, int valeur})> parMois;
  final List<({String libelle, int valeur})> parSexe;

  /// Les diagnostics les plus fréquents (cinq au plus).
  final List<({String libelle, int valeur})> diagnostics;

  /// Médecine du travail : répartition des avis d'aptitude (vide pour toute autre spécialité).
  final List<({String libelle, int valeur})> aptitudes;
}

List<({String libelle, int valeur})> _compter(Iterable<String> cles, {int? limite}) {
  final n = <String, int>{};
  for (final c in cles) {
    if (c.isEmpty) continue;
    n[c] = (n[c] ?? 0) + 1;
  }
  final l = n.entries.toList();
  // Tri stable : à égalité, l'ordre d'apparition.
  final ordre = [for (var i = 0; i < l.length; i++) (i, l[i])];
  ordre.sort((a, b) {
    final c = b.$2.value.compareTo(a.$2.value);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  final out = [for (final e in ordre) (libelle: e.$2.key, valeur: e.$2.value)];
  return limite == null ? out : out.take(limite).toList();
}

/// Les statistiques d'une spécialité, lues sur les registres : consultations (enregistrées ou planifiées), patients (le sexe), file d'attente.
/// [du] / [au] : bornes `aaaa-mm-jj` incluses, vides = sans borne.
SpecStats specStatistiques(
  String code, {
  required Iterable<FicheSp> consultations,
  Iterable<FicheSp> patients = const [],
  Iterable<FicheSp> fileAttente = const [],
  String du = '',
  String au = '',
  required DateTime aujourdhui,
}) {
  final tous = [
    for (final c in consultations)
      if (c['statut'] != 'archive' && specDeLaConsultation(c) == code) c
  ];
  bool dansPlage(FicheSp c) {
    final j = _jour(c['date']);
    return (du.isEmpty || j.compareTo(du) >= 0) && (au.isEmpty || j.compareTo(au) <= 0);
  }

  final faites = [for (final c in tous) if (c['statut'] == 'terminee' && dansPlage(c)) c];
  final aujourd = iso(aujourdhui);
  final mois = aujourd.substring(0, 7);
  final parPatient = {for (final p in patients) '${p['id']}': p};
  final distincts = <String>{for (final c in faites) '${c['patientId'] ?? c['patientCode']}'};
  num recettes = 0;
  for (final c in faites) {
    recettes += nombreOuZero(c['tarif']);
  }
  final parMois = _compter([for (final c in faites) _jour(c['date']).length >= 7 ? _jour(c['date']).substring(0, 7) : ''])
    ..sort((a, b) => a.libelle.compareTo(b.libelle));
  return SpecStats(
    consultations: faites.length,
    patients: distincts.length,
    ceMois: [for (final c in tous) if (c['statut'] == 'terminee' && _jour(c['date']).startsWith(mois)) c].length,
    rendezVousAVenir: [for (final c in tous) if (c['statut'] == 'planifiee' && _jour(c['date']).compareTo(aujourd) >= 0) c].length,
    fileEnAttente: [for (final t in fileAttente) if (t['specialite'] == code && t['statut'] != 'archive' && t['etat'] == 'attente') t].length,
    recettes: recettes,
    parPraticien: _compter([for (final c in faites) _txt(c['medecin'])]),
    parMois: parMois,
    parSexe: _compter([
      for (final c in faites)
        switch (parPatient['${c['patientId']}']?['sexe']) { 'F' => 'Femmes', 'M' => 'Hommes', _ => '' }
    ]),
    diagnostics: _compter([for (final c in faites) _txt(c['diagnostic'])], limite: 5),
    aptitudes: code == specCodeMedecineTravail ? _compter([for (final c in faites) _txt(c['aptitude'])]) : const [],
  );
}
