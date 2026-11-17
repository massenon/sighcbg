/// M1 — RÉPERTOIRE DES PATIENTS ET ANTÉCÉDENTS : règles portées de `m1-patients.js`, rejouées sur les vecteurs tirés des écrans RÉELS
/// (`test/vecteurs/pat_patients.json`, `pat_antecedents.json`, `pat_profil.json`).
///
/// RG-01 : le code patient `CBG/n/AA` est généré par la fabrique UNIQUE [codePatient] ; il ne se modifie plus. RG-09 : la validité de la carte
/// se lit à la date (moteur `carteValide` de la caisse), jamais sur une copie locale. RG-14 : on archive, on ne supprime pas.
library;

import '../parametres/listes_reference.dart' show ListesReference;
import '../caisse/prise_en_charge.dart' show carteValide;
import '../format/format_fr.dart';
import '../referentiels/regles.dart' show codePatient, lireCodePatient;
import '../labo/res_saisie.dart' show agePatient;
import '../numerotation/numerotation.dart';

typedef FichePat = Map<String, Object?>;

bool patVrai(Object? v) => v != null && v != '' && v != 0 && v != false;

/// Les huit groupes sanguins (`D.GROUPES_SANGUINS`).
const patGroupesSanguins = ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'];

/// `D.ANTECEDENTS` : la dernière entrée est l'absence d'antécédent — elle ne se coche pas, elle se déduit d'une liste vide.
List<String> get patAntecedents => ListesReference.valeurs('listes.m1.antecedents');
List<String> get patAntecedentsRisque => ListesReference.valeurs('listes.m1.antecedentsARisque');
List<String> get patAllergies => ListesReference.valeurs('listes.m1.allergies');


/// `liste(v)` : antécédents et allergies acceptent une liste OU l'ancienne chaîne unique ; « Aucun… » n'est pas une valeur.
List<String> patListe(Object? v) {
  if (v == null || v == '') return const [];
  final t = v is List ? v : [v];
  return [
    for (final x in t)
      if (patVrai(x) &&
          x != 'Aucun antécédent notable' &&
          x != 'Aucune allergie connue')
        '$x'
  ];
}

String patTexteListe(Object? v, [String vide = '—']) {
  final t = patListe(v);
  return t.isEmpty ? vide : t.join(', ');
}

/// `age(p)` : par `C.ageDe` — la fabrique unique, qui connaît l'âge DÉCLARÉ (écart E301).
int? patAge(FichePat p, DateTime maintenant) => agePatient(p, maintenant);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// RG-01 — le prochain code
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// `prochainCode()` : le plus grand rang de l'année lu sur les DEUX formes (`CBG/n/AA` et l’ancien `CNTn/AA`, quel que soit le sigle), archivés compris — un code attribué
/// ne se réutilise pas (RG-01) — puis la fabrique unique. Écart E300 : l'ancienne expression ne reconnaissait que l'ancien format.
String patProchainCode(Iterable<FichePat> patients, DateTime maintenant) {
  final suffixe = '${maintenant.year}'.substring('${maintenant.year}'.length - 2);
  var max = 0;
  for (final p in patients) {
    final c = lireCodePatient(p['code']);
    if (c != null && c.annee == suffixe && c.rang > max) max = c.rang;
  }
  return codePatient(max + 1, maintenant.year);
}

/// `beforeSave` : le code réservé à l'ouverture de l'écran a pu être pris entre-temps (deux guichets).
String? patRefusCode(Iterable<FichePat> patients, String code) =>
    patients.any((p) => p['code'] == code)
        ? 'Ce code dossier est déjà attribué. Recharger la page pour obtenir le suivant.'
        : null;

/// `transformerPatient(v, record)` : ce que l'enregistrement DÉDUIT de la saisie — le nom de la compagnie et l'âge. L'âge est une DÉCLARATION datée
/// quand la date de naissance est inconnue ; l'âge déjà déclaré ne se re-date pas (le re-dater le rajeunirait à chaque ouverture).
FichePat patTransformerPatient(FichePat saisie, FichePat? record, DateTime maintenant, {Iterable<FichePat> assureurs = const []}) {
  final v = {...saisie};
  // Le NOM de la compagnie se lit sur le référentiel des assureurs (`assureurs`, administrable) passé en argument : plus de copie des treize compagnies dans le code.
  final a = assureurs.where((x) => x['statut'] != 'archive' && x['code'] == v['assureur']).firstOrNull;
  v['assureurNom'] = a?['nom'];
  if ('${v['naissanceConnue'] ?? 'date'}' == 'age') {
    v['dateNaissance'] = '';
    final age = v['age'];
    final inchange = record != null &&
        patVrai(record['ageReferenceLe']) &&
        '${record['age']}' == '$age';
    v['ageReferenceLe'] = inchange ? record['ageReferenceLe'] : iso(maintenant);
  } else {
    v['age'] = '';
    v['ageReferenceLe'] = '';
  }
  v.remove('naissanceConnue');
  return v;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Répertoire : indicateurs et filtres
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// RG-09 à la MÊME date que la caisse.
bool patCarteValide(FichePat p, Iterable<FichePat> couvertures, DateTime maintenant) =>
    carteValide(p, [for (final c in couvertures) c], iso(maintenant));

class PatKpisRepertoire {
  const PatKpisRepertoire(this.actifs, this.creesAnnee, this.assures, this.expirees, this.partAssures, this.annee);
  final int actifs;

  /// Les dossiers créés pendant l'année [annee] (l'année de l'horloge du poste : « Créés en 2027 » le 1er janvier 2027 — lot 0, E3834).
  final int creesAnnee;
  final int annee;
  final int assures;
  final int expirees;

  /// « 57.1 % du répertoire ».
  final String partAssures;
}

PatKpisRepertoire patKpisRepertoire(List<FichePat> rows, Iterable<FichePat> couvertures, DateTime maintenant) {
  final assures = rows.where((p) => patVrai(p['assureur'])).toList();
  final expirees = assures.where((p) => !patCarteValide(p, couvertures, maintenant)).length;
  // « Créés en <année> » : l'ANNÉE EN COURS (la maquette écrivait 2026, l'année de son jeu ; corrigé au lot 0, E3834).
  final annee = rows.where((p) {
    final d = DateTime.tryParse('${p['dateCreation'] ?? ''}');
    return d != null && d.year == maintenant.year;
  }).length;
  return PatKpisRepertoire(rows.length, annee, assures.length, expirees,
      pourcent(rows.isNotEmpty ? assures.length / rows.length * 100 : 0), maintenant.year);
}

/// Filtre « Couverture » : assurés · non assurés · carte expirée.
bool patFiltreCouverture(FichePat p, String v, Iterable<FichePat> couvertures, DateTime maintenant) {
  if (v == 'assure') return patVrai(p['assureur']);
  if (v == 'non') return !patVrai(p['assureur']);
  if (v == 'expiree') {
    return patVrai(p['assureur']) && !patCarteValide(p, couvertures, maintenant);
  }
  return true;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Antécédents & allergies
// ---------------------------------------------------------------------------------------------------------------------------------------------

bool patRisque(FichePat p) =>
    patListe(p['antecedents']).any(patAntecedentsRisque.contains);
bool patAllergique(FichePat p) => patListe(p['allergies']).isNotEmpty;

class PatKpisAntecedents {
  const PatKpisAntecedents(this.renseignes, this.allergies, this.risque, this.sansAntecedent);
  final int renseignes;
  final int allergies;
  final int risque;
  final int sansAntecedent;
}

PatKpisAntecedents patKpisAntecedents(List<FichePat> rows) => PatKpisAntecedents(
    rows.where((p) => patListe(p['antecedents']).isNotEmpty).length,
    rows.where(patAllergique).length,
    rows.where(patRisque).length,
    rows.where((p) => patListe(p['antecedents']).isEmpty).length);

/// Filtres « Allergie » / « Antécédent » : la valeur se cherche DANS la liste (écart E305) ; « Aucun… » = liste vide.
bool patFiltreAllergie(FichePat p, String v) => v == 'Aucune allergie connue'
    ? patListe(p['allergies']).isEmpty
    : patListe(p['allergies']).contains(v);
bool patFiltreAntecedent(FichePat p, String v) => v == 'Aucun antécédent notable'
    ? patListe(p['antecedents']).isEmpty
    : patListe(p['antecedents']).contains(v);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Documents numérisés
// ---------------------------------------------------------------------------------------------------------------------------------------------

const patTypesDocument = [
  'Ordonnance',
  'Résultat de laboratoire',
  'Compte rendu médical',
  'Consentement éclairé',
  'Imagerie / Échographie',
  'Bulletin d’hospitalisation',
  'Facture',
  'Pièce d’identité',
  'Carte d’assurance',
  'Certificat médical',
];

/// `poidsDoc(o)` : « — », « 2 Ko », « 3.0 Mo » (JS : `toFixed(1)` et `Math.round`).
String patPoidsDoc(Object? o) {
  final n = o is num ? o : num.tryParse('${o ?? ''}');
  if (n == null || n == 0) return '—';
  if (n > 1024 * 1024) return '${(n / 1024 / 1024).toStringAsFixed(1)} Mo';
  return '${(n / 1024).round()} Ko';
}

class PatKpisDocuments {
  const PatKpisDocuments(this.total, this.valides, this.enAttente, this.dossiers);
  final int total;
  final int valides;
  final int enAttente;
  final int dossiers;
}

PatKpisDocuments patKpisDocuments(List<FichePat> rows) => PatKpisDocuments(
    rows.length,
    rows.where((r) => r['etat'] == 'valide').length,
    rows.where((r) => r['etat'] == 'en_attente').length,
    {for (final r in rows) '${r['code']}'}.length);

/// « GED-00005 » : le rang suit le NOMBRE de fiches du registre (archivées comprises), comme la maquette.
String patReferenceDocument(Iterable<Object?> fiches, {Object? date}) => numeroSuivant('patients.documents', date: date, existants: fiches);

/// Fichier d'un document : « PDF · 2 Ko » et la mention déposé / référencé.
String patFormatDocument(String? nomFichier) {
  final f = (nomFichier ?? '').toLowerCase();
  if (f.endsWith('pdf')) return 'PDF';
  if (f.endsWith('png')) return 'PNG';
  if (f.endsWith('webp')) return 'WEBP';
  return 'JPEG';
}
