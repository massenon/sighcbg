// LA SAUVEGARDE OBLIGATOIRE AVANT UNE MISE À JOUR (Direction de Baguidi, 17/11/2026, décision 12) : les RÈGLES PURES.
//
// Une mise à jour peut changer la forme des données. Avant de l'installer, la clinique doit détenir (1) une SAUVEGARDE de la mère VÉRIFIÉE (restaurable : relue et contrôlée) et
// (2) un EXPORT PORTABLE vérifié, TOUS DEUX de moins de N heures. N est un RÉGLAGE DATÉ (`maj.sauvegardeMaxHeures`), jamais une valeur écrite ici. Faute de quoi la mise à jour est
// BLOQUÉE avec un message nommé ; le blocage ne se lève que par un GESTE RÉSERVÉ tracé (cas de force majeure, motif obligatoire).
//
// L'installeur Windows ne lit pas la base : il lit un petit fichier d'AUTORISATION que le poste écrit quand la préparation est faite (`autorisation-mise-a-jour.txt`, sous le dossier
// des données). Format en `clé=valeur`, une par ligne, lisible par le script Pascal de l'installeur. LIMITE assumée : ce fichier protège contre l'OUBLI, pas contre un administrateur
// qui voudrait le contourner (il le peut, en connaissance de cause : c'est un poste dont il est l'administrateur).
library;

import '../droits/gestes_reserves.dart';
import 'sauvegarde_horssite.dart' show RefusSauvegarde;

const String cleMajSauvegardeMaxHeures = 'maj.sauvegardeMaxHeures';

/// Défaut SEMÉ (valeur d'attente à valider par la Direction) et bornes : un réglage hors bornes est refusé, jamais rogné.
const int majHeuresDefaut = 24;
const int majHeuresMin = 1;
const int majHeuresMax = 168;

/// Le nom du fichier d'autorisation, sous le dossier des données du poste.
const String majFichierAutorisation = 'autorisation-mise-a-jour.txt';

/// La durée de validité d'une AUTORISATION posée par la préparation (heures) : assez pour installer, pas pour oublier. Aussi un réglage de fait, borné ici.
const int majValiditeAutorisationHeures = 4;

/// Une preuve : la date de l'objet (sauvegarde ou export) et s'il a été VÉRIFIÉ (relu, déchiffré, empreinte contrôlée).
class PreuveMaj {
  const PreuveMaj({required this.date, required this.verifiee, this.detail = ''});
  final DateTime date;
  final bool verifiee;
  final String detail;
}

/// Le verdict de la préparation.
class VerdictMaj {
  const VerdictMaj({required this.refus, required this.maxHeures});
  final List<RefusSauvegarde> refus;
  final int maxHeures;
  bool get autorisee => refus.isEmpty;
}

RefusSauvegarde _r(String code, String motif, String geste, [Map<String, Object?> plus = const {}]) => RefusSauvegarde(code, motif, geste, plus);

/// Vérifie le réglage N : un entier de [majHeuresMin] à [majHeuresMax].
RefusSauvegarde? majVerifierReglage(Object? v) => v is int && v >= majHeuresMin && v <= majHeuresMax
    ? null
    : _r('MAJ_DELAI_HORS_BORNES', 'le délai de validité de la sauvegarde avant mise à jour doit être un entier de $majHeuresMin à $majHeuresMax heures',
        'Choisir un délai dans ces bornes (Paramètres › Mise à jour).');

RefusSauvegarde? _controler(String nom, String codeBase, PreuveMaj? p, DateTime maintenant, int maxHeures) {
  if (p == null) {
    return _r('${codeBase}_ABSENT${codeBase == 'SAUVEGARDE' ? 'E' : ''}', 'aucun${codeBase == 'SAUVEGARDE' ? 'e' : ''} $nom n’est connu de ce poste',
        'Lancer ${codeBase == 'SAUVEGARDE' ? 'la sauvegarde' : 'l’export'} depuis « Préparer la mise à jour ».');
  }
  final age = maintenant.difference(p.date);
  if (age > Duration(hours: maxHeures)) {
    return _r('${codeBase}_TROP_${codeBase == 'SAUVEGARDE' ? 'ANCIENNE' : 'ANCIEN'}', 'la dernière $nom date de ${age.inHours} heure(s) ; le maximum accepté avant une mise à jour est de $maxHeures heure(s)',
        'Refaire ${codeBase == 'SAUVEGARDE' ? 'la sauvegarde' : 'l’export'} maintenant.', {'ageHeures': age.inHours, 'maxHeures': maxHeures});
  }
  if (!p.verifiee) {
    return _r('${codeBase}_NON_VERIFIE${codeBase == 'SAUVEGARDE' ? 'E' : ''}', 'la dernière $nom n’a pas été vérifiée (relue et contrôlée) : une copie jamais vérifiée n’est pas une garantie',
        'Lancer la vérification depuis « Préparer la mise à jour ».');
  }
  return null;
}

/// LA PRÉPARATION : la sauvegarde ET l'export doivent être récents (moins de [maxHeures]) et vérifiés. Chaque manque est NOMMÉ. [maintenant] : l'horloge du poste.
VerdictMaj majPreparation({required DateTime maintenant, required int maxHeures, PreuveMaj? sauvegarde, PreuveMaj? export}) {
  final r = <RefusSauvegarde>[];
  final a = _controler('sauvegarde', 'SAUVEGARDE', sauvegarde, maintenant, maxHeures);
  final b = _controler('export portable', 'EXPORT', export, maintenant, maxHeures);
  if (a != null) r.add(a);
  if (b != null) r.add(b);
  return VerdictMaj(refus: r, maxHeures: maxHeures);
}

/// Le MESSAGE de blocage, nommé (codes puis motifs) : celui que l'installeur et l'écran affichent.
String majMessageBlocage(VerdictMaj v) =>
    'Mise à jour BLOQUÉE : ${v.refus.map((x) => '${x.code} (${x.motif})').join(' ; ')}. Préparer la mise à jour (sauvegarde vérifiée et export portable de moins de ${v.maxHeures} heure(s)), ou lever le blocage par le geste réservé en cas de force majeure.';

/// La longueur minimale du motif d'une levée de blocage.
const int majMotifLongueurMin = 10;

/// LA LEVÉE DU BLOCAGE : un geste réservé, un motif écrit. Refus nommé sinon. [aLeDroit] est le résultat de `DroitsGestes.peut(role, gesteMajLeverBlocage)`, jamais un nom de rôle.
RefusSauvegarde? majControlerLevee({required bool aLeDroit, required String motif}) {
  if (!aLeDroit) {
    return _r('GESTE_RESERVE', 'lever le blocage d’une mise à jour est un geste réservé de la fiche de rôle (« ${gesteReserve(gesteMajLeverBlocage)?.libelle ?? gesteMajLeverBlocage} »)', 'Demander à un rôle qui détient ce droit.');
  }
  if (motif.trim().length < majMotifLongueurMin) {
    return _r('MOTIF_OBLIGATOIRE', 'le motif de la levée (cas de force majeure) doit comporter au moins $majMotifLongueurMin caractères', 'Écrire le motif ; il est journalisé avec l’auteur et la date.');
  }
  return null;
}

String _horodate(DateTime d) {
  String p(int n, [int l = 2]) => n.toString().padLeft(l, '0');
  return '${p(d.year, 4)}${p(d.month)}${p(d.day)}${p(d.hour)}${p(d.minute)}${p(d.second)}';
}

/// LE FICHIER D'AUTORISATION (texte `clé=valeur`). Les dates sont à l'HEURE LOCALE du poste, au format `AAAAMMJJHHMMSS`, comparables comme des chaînes : c'est ce que lit
/// l'installeur, qui tourne sur la même machine. `levee=oui` : le blocage a été levé par geste réservé (motif et auteur au journal du poste).
String majTexteAutorisation(
        {required DateTime maintenant, required int validiteHeures, required String versionCourante, required int schema, required bool levee, DateTime? sauvegarde, DateTime? export}) =>
    [
      'SIGH-AUTORISATION-MAJ 1',
      'cree_local=${_horodate(maintenant)}',
      'valable_jusqu_local=${_horodate(maintenant.add(Duration(hours: validiteHeures)))}',
      'version_courante=$versionCourante',
      'schema=$schema',
      'levee=${levee ? 'oui' : 'non'}',
      if (sauvegarde != null) 'sauvegarde_local=${_horodate(sauvegarde)}',
      if (export != null) 'export_local=${_horodate(export)}',
      '',
    ].join('\n');

/// Relit une autorisation (même logique que le script de l'installeur) : valide à [maintenant] ? Rend `null` si oui, le refus nommé sinon.
RefusSauvegarde? majLireAutorisation(String? texte, DateTime maintenant) {
  if (texte == null || texte.trim().isEmpty) {
    return _r('AUTORISATION_ABSENTE', 'aucune préparation de mise à jour n’a été faite sur ce poste', 'Ouvrir le poste mère, « Préparer la mise à jour », puis relancer l’installation.');
  }
  final lignes = texte.split(RegExp(r'\r?\n'));
  if (lignes.isEmpty || !lignes.first.startsWith('SIGH-AUTORISATION-MAJ')) {
    return _r('AUTORISATION_ILLISIBLE', 'le fichier d’autorisation n’a pas la forme attendue', 'Refaire « Préparer la mise à jour ».');
  }
  String? v(String k) {
    for (final l in lignes) {
      if (l.startsWith('$k=')) return l.substring(k.length + 1).trim();
    }
    return null;
  }

  final jusqu = v('valable_jusqu_local');
  if (jusqu == null || !RegExp(r'^\d{14}$').hasMatch(jusqu)) {
    return _r('AUTORISATION_ILLISIBLE', 'la date de validité de l’autorisation est illisible', 'Refaire « Préparer la mise à jour ».');
  }
  if (jusqu.compareTo(_horodate(maintenant)) < 0) {
    return _r('AUTORISATION_EXPIREE', 'l’autorisation de mise à jour a expiré', 'Refaire « Préparer la mise à jour » (elle ne vaut que $majValiditeAutorisationHeures heures).');
  }
  return null;
}

/// Les gestes de ce lot (pour les tests de cohérence).
const List<String> majGestes = [gesteMajLeverBlocage];
