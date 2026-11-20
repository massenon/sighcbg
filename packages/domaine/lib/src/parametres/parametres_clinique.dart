// LES RÉGLAGES DE CLINIQUE QUE LES RÈGLES LISENT (décisions Q10 et Q14 de la Direction, 15/11/2026) : le préavis de péremption et les bornes de la balance âgée des patients vivaient
// en littéraux (90 jours ; 30 et 90 jours). Ce sont des PARAMÈTRES de la collection `parametres` (famille R, versionnés par date, jamais écrasés) : ce fichier ne fait que les LIRE, depuis
// n'importe quelle liste de fiches de versions (le magasin du poste, l'assistant), en bornant ce qui est lu — une valeur illisible retombe sur la valeur SEMÉE, jamais sur zéro.
//
// Dart pur, aucune horloge : la date est toujours fournie.
library;

import 'definitions.dart';
import 'parametres.dart';
import '../rh/rhc_regles.dart' show rhcCleMontantStandard, rhcMontantStandardSemence;
import '../administration/adm_regles.dart' show admCleForfaitAmbulance, admClePrixKmAmbulance, admForfaitAmbulanceSemence, admPrixKmAmbulanceSemence;

const String cleDelaiPreavisPeremption = 'stock.delaiPreavisPeremptionJours';
const String cleBalanceAgeePatientBorne1 = 'comptabilite.balanceAgeePatientBorne1Jours';
const String cleBalanceAgeePatientBorne2 = 'comptabilite.balanceAgeePatientBorne2Jours';
const String cleJoursArticlesImmobiles = 'stock.joursArticlesImmobiles';
const String cleBalanceAgeeAssureurBorne1 = 'assurances.balanceAgeeAssureurBorne1Jours';
const String cleBalanceAgeeAssureurBorne2 = 'assurances.balanceAgeeAssureurBorne2Jours';

// Le plan de numérisation (lot « valeurs en dur », famille B) : le fonds papier déclaré et la fenêtre qui fait d'un dossier un dossier actif.
const String cleFondsPapier = 'numerisation.fondsPapierDossiers';
const String cleFenetreDossiersActifs = 'numerisation.fenetreDossiersActifsMois';

// Les clés des seuils qui vivaient en littéraux (lot « seuils » ; leurs défauts et leurs bornes sont dans `definitions.dart`, un seul endroit).
const String cleDelaiVerrouOrdinaire = 'securite.delaiVerrouOrdinaireMinutes';
const String cleRenouvellementMotDePasse = 'securite.renouvellementMotDePasseJours';
const String cleDureeVerrouCompte = 'securite.dureeVerrouCompteMinutes';
const String cleDureeBlocageSecours = 'securite.dureeBlocageSecoursMinutes';
const String cleValiditeMotDePasseTemporaire = 'securite.validiteMotDePasseTemporaireHeures';

/// La durée sans sortie d'un « article immobile » (jours) : le défaut du paramètre `stock.joursArticlesImmobiles` (30 semés), borné de 1 à 730 (décision du 16/11/2026).
int get joursArticlesImmobilesSeme => seuilSeme(cleJoursArticlesImmobiles);

/// Les valeurs SEMÉES (repli d'un poste jamais semé ou d'une valeur hors bornes) : elles sont aussi les défauts des définitions, un seul endroit les dit.
int get preavisPeremptionSeme => seuilSeme(cleDelaiPreavisPeremption);
int get balanceAgeeBorne1Semee => seuilSeme(cleBalanceAgeePatientBorne1);
int get balanceAgeeBorne2Semee => seuilSeme(cleBalanceAgeePatientBorne2);
int get balanceAgeeAssureurBorne1Semee => seuilSeme(cleBalanceAgeeAssureurBorne1);
int get balanceAgeeAssureurBorne2Semee => seuilSeme(cleBalanceAgeeAssureurBorne2);

/// Les bornes acceptées pour le préavis de péremption (jours).
const int preavisPeremptionMin = 1;
const int preavisPeremptionMax = 730;

Object? _valeurA(Iterable<Map<String, Object?>> fiches, String cle, String date) {
  final versions = [
    for (final f in fiches)
      if (f['statut'] != 'archive' && f['cle'] == cle) Parametre.fromJson(f)
  ];
  final r = Parametres.resoudre(cle, versions, date, definition: definitionDeParametre(cle));
  return r.ok ? r.valeur!.valeur : definitionDeParametre(cle)?.defaut;
}

/// Un réglage OUI/NON en vigueur à [date] : la version datée qui s'applique, sinon le défaut de la définition. Seul un `true` explicite ouvre ; toute autre valeur ferme.
bool reglageBooleenA(Iterable<Map<String, Object?>> fichesParametres, String cle, String date) => _valeurA(fichesParametres, cle, date) == true;

int? _entier(Object? v) => v is num && v.isFinite && v == v.truncateToDouble() ? v.toInt() : null;

/// Le préavis de péremption (jours) EN VIGUEUR à [date] (AAAA-MM-JJ) : la version datée qui s'applique, sinon 90. Hors bornes (1 à 730) : 90.
int delaiPreavisPeremptionA(Iterable<Map<String, Object?>> fichesParametres, String date) => delaiPreavisPeremptionDe(_valeurA(fichesParametres, cleDelaiPreavisPeremption, date));

/// Le préavis tiré d'une valeur brute (un réglage lu autrement, par exemple par le service des paramètres du poste).
int delaiPreavisPeremptionDe(Object? valeur) {
  final n = _entier(valeur);
  return n != null && n >= preavisPeremptionMin && n <= preavisPeremptionMax ? n : preavisPeremptionSeme;
}

/// La durée sans sortie qui fait d'un article un « article immobile », EN VIGUEUR à [date] : la version datée qui s'applique, sinon 30. Hors bornes (1 à 730) : 30.
int joursArticlesImmobilesA(Iterable<Map<String, Object?>> fichesParametres, String date) {
  final n = _entier(_valeurA(fichesParametres, cleJoursArticlesImmobiles, date));
  return n != null && n >= 1 && n <= 730 ? n : joursArticlesImmobilesSeme;
}

/// Les deux bornes de la balance âgée des patients EN VIGUEUR à [date] : (30, 90) semées. Une paire incohérente (première borne >= seconde, hors 1 à 730) retombe sur les valeurs semées
/// ENSEMBLE : corriger une borne seule ferait des tranches qui se chevauchent.
({int borne1, int borne2}) bornesBalanceAgeePatientA(Iterable<Map<String, Object?>> fichesParametres, String date) =>
    bornesBalanceAgeePatientDe(_valeurA(fichesParametres, cleBalanceAgeePatientBorne1, date), _valeurA(fichesParametres, cleBalanceAgeePatientBorne2, date));

({int borne1, int borne2}) bornesBalanceAgeePatientDe(Object? b1, Object? b2) {
  final a = _entier(b1), b = _entier(b2);
  if (a != null && b != null && a >= 1 && b <= 730 && a < b) return (borne1: a, borne2: b);
  return (borne1: balanceAgeeBorne1Semee, borne2: balanceAgeeBorne2Semee);
}

/// Les deux bornes de la balance âgée des ASSUREURS EN VIGUEUR à [date] : (30, 90) semées, réglables à part de celles des patients (les créances des compagnies et le reliquat des
/// patients ne se recouvrent pas au même rythme). Une paire incohérente (première borne >= seconde, hors 1 à 730) retombe sur les valeurs semées ENSEMBLE.
({int borne1, int borne2}) bornesBalanceAgeeAssureurA(Iterable<Map<String, Object?>> fichesParametres, String date) =>
    bornesBalanceAgeeAssureurDe(_valeurA(fichesParametres, cleBalanceAgeeAssureurBorne1, date), _valeurA(fichesParametres, cleBalanceAgeeAssureurBorne2, date));

({int borne1, int borne2}) bornesBalanceAgeeAssureurDe(Object? b1, Object? b2) {
  final a = _entier(b1), b = _entier(b2);
  if (a != null && b != null && a >= 1 && b <= 730 && a < b) return (borne1: a, borne2: b);
  return (borne1: balanceAgeeAssureurBorne1Semee, borne2: balanceAgeeAssureurBorne2Semee);
}

/// Les quatre tranches de la balance âgée des patients pour ces bornes, dans l'ordre, sous la forme (libellé, ancienneté minimale exclue, ancienneté maximale incluse) ; la dernière est ouverte.
/// Le milieu est celui de l'assistant historique : « 0 à 30 », « 31 à 60 », « 61 à 90 », « plus de 90 » avec les bornes semées (60 = la médiane des deux bornes, jamais lue d'un réglage).
List<({String libelle, int min, int? max})> tranchesBalanceAgeePatient(int borne1, int borne2) {
  final milieu = ((borne1 + borne2) / 2).round();
  return [
    (libelle: '0 à $borne1 jours', min: -1, max: borne1),
    (libelle: '${borne1 + 1} à $milieu jours', min: borne1, max: milieu),
    (libelle: '${milieu + 1} à $borne2 jours', min: milieu, max: borne2),
    (libelle: 'plus de $borne2 jours', min: borne2, max: null),
  ];
}

/// La participation standard par agent aux événements du personnel EN VIGUEUR à [date] (paramètre `rh.participationStandardParAgent`, lot 1 de l'inventaire des valeurs
/// en dur) : la version datée qui s'applique, sinon la graine (1 000 F). Une valeur illisible ou négative retombe sur la graine.
int participationStandardA(Iterable<Map<String, Object?>> fichesParametres, String date) {
  final n = _entier(_valeurA(fichesParametres, rhcCleMontantStandard, date));
  return n != null && n >= 0 ? n : rhcMontantStandardSemence;
}

/// Le tarif d'une course d'ambulance sans montant saisi EN VIGUEUR à [date] (paramètres `ambulance.forfaitCourse` et `ambulance.prixKilometre`, propositions à valider, lot 1) :
/// les versions datées qui s'appliquent, sinon les graines (5 000 F + 500 F par kilomètre). Une valeur illisible ou négative retombe sur sa graine.
({int forfait, int parKm}) tarifAmbulanceA(Iterable<Map<String, Object?>> fichesParametres, String date) {
  final f = _entier(_valeurA(fichesParametres, admCleForfaitAmbulance, date));
  final k = _entier(_valeurA(fichesParametres, admClePrixKmAmbulance, date));
  return (forfait: f != null && f >= 0 ? f : admForfaitAmbulanceSemence, parKm: k != null && k >= 0 ? k : admPrixKmAmbulanceSemence);
}

/// Un SEUIL ENTIER en vigueur à [date] : la version datée qui s'applique, sinon le défaut SEMÉ de la définition ; une valeur illisible ou hors des bornes déclarées
/// (`min`, `max` de la définition) retombe sur ce défaut, jamais sur zéro. Les seuils et délais qui vivaient en littéraux se lisent tous par ici (lot « seuils »).
int seuilEntierA(Iterable<Map<String, Object?>> fichesParametres, String cle, String date) => seuilEntierDe(cle, _valeurA(fichesParametres, cle, date));

/// Le seuil tiré d'une valeur brute (réglage lu autrement, par exemple par le service des paramètres du poste) : borné par la définition de [cle].
int seuilEntierDe(String cle, Object? valeur) {
  final n = _entier(valeur);
  final d = definitionDeParametre(cle);
  if (n != null && d != null && (d.min == null || n >= d.min!) && (d.max == null || n <= d.max!)) return n;
  return seuilSeme(cle);
}

/// Le défaut SEMÉ d'un seuil : la seule valeur d'attente, celle de la définition. Une clé inconnue est une faute de programmation (jamais un zéro silencieux).
int seuilSeme(String cle) {
  final d = definitionDeParametre(cle);
  final v = d?.defaut;
  if (v is! num) throw ArgumentError('seuil inconnu : $cle');
  return v.toInt();
}

/// Un SEUIL NUMÉRIQUE (décimal permis : un poids de 0,5 kg) en vigueur à [date] : la version datée qui s'applique, sinon le défaut SEMÉ ; hors des bornes déclarées par la
/// définition (`min`, `max`) ou illisible, le défaut semé, jamais zéro.
num seuilNombreA(Iterable<Map<String, Object?>> fichesParametres, String cle, String date) => seuilNombreDe(cle, _valeurA(fichesParametres, cle, date));

/// Le seuil numérique tiré d'une valeur brute : borné par la définition de [cle].
num seuilNombreDe(String cle, Object? valeur) {
  final d = definitionDeParametre(cle);
  if (valeur is num && valeur.isFinite && d != null && (d.min == null || valeur >= d.min!) && (d.max == null || valeur <= d.max!)) return valeur;
  return seuilNombreSeme(cle);
}

/// Le défaut SEMÉ d'un seuil numérique (décimal conservé). Une clé inconnue est une faute de programmation.
num seuilNombreSeme(String cle) {
  final v = definitionDeParametre(cle)?.defaut;
  if (v is! num) throw ArgumentError('seuil inconnu : $cle');
  return v;
}
