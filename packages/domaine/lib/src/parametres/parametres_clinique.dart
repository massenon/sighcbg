// LES RÉGLAGES DE CLINIQUE QUE LES RÈGLES LISENT (décisions Q10 et Q14 de la Direction, 15/11/2026) : le préavis de péremption et les bornes de la balance âgée des patients vivaient
// en littéraux (90 jours ; 30 et 90 jours). Ce sont des PARAMÈTRES de la collection `parametres` (famille R, versionnés par date, jamais écrasés) : ce fichier ne fait que les LIRE, depuis
// n'importe quelle liste de fiches de versions (le magasin du poste, l'assistant), en bornant ce qui est lu — une valeur illisible retombe sur la valeur SEMÉE, jamais sur zéro.
//
// Dart pur, aucune horloge : la date est toujours fournie.
library;

import 'definitions.dart';
import 'parametres.dart';

const String cleDelaiPreavisPeremption = 'stock.delaiPreavisPeremptionJours';
const String cleBalanceAgeePatientBorne1 = 'comptabilite.balanceAgeePatientBorne1Jours';
const String cleBalanceAgeePatientBorne2 = 'comptabilite.balanceAgeePatientBorne2Jours';

/// Les valeurs SEMÉES (repli d'un poste jamais semé ou d'une valeur hors bornes) : elles sont aussi les défauts des définitions, un seul endroit les dit.
const int preavisPeremptionSeme = 90;
const int balanceAgeeBorne1Semee = 30;
const int balanceAgeeBorne2Semee = 90;

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

int? _entier(Object? v) => v is num && v.isFinite && v == v.truncateToDouble() ? v.toInt() : null;

/// Le préavis de péremption (jours) EN VIGUEUR à [date] (AAAA-MM-JJ) : la version datée qui s'applique, sinon 90. Hors bornes (1 à 730) : 90.
int delaiPreavisPeremptionA(Iterable<Map<String, Object?>> fichesParametres, String date) => delaiPreavisPeremptionDe(_valeurA(fichesParametres, cleDelaiPreavisPeremption, date));

/// Le préavis tiré d'une valeur brute (un réglage lu autrement, par exemple par le service des paramètres du poste).
int delaiPreavisPeremptionDe(Object? valeur) {
  final n = _entier(valeur);
  return n != null && n >= preavisPeremptionMin && n <= preavisPeremptionMax ? n : preavisPeremptionSeme;
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
