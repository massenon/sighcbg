// LES DÉCISIONS EN ATTENTE DE LA MÈRE (section AI, Direction du 16/11/2026).
//
// Trois files portent une décision prise sur un fileul et que seule la mère applique : les VALIDATIONS déposées (`validationsDeposees` : référentiels et circuits d'achat), les
// DEMANDES DE PRIX (`propositionsTarif`) et les DEMANDES D'IMPORT (`demandesImport`). Ce fichier les lit ENSEMBLE :
//  * la pastille « N décisions en attente de la mère » compte les TROIS, avec leur âge (la plus ancienne dit depuis quand la mère n'a pas répondu) ;
//  * au-delà du DÉLAI réglé par la clinique (réglage en base `validations.delaiAlerteMereHeures`, 4 heures semées), une ALERTE part vers le validateur concerné et l'administrateur.
//    Elle ne bloque rien, ne valide rien à la place de la mère : elle dit qu'une décision attend.
//
// Fonctions PURES : les fiches sont passées en argument ; l'âge est mesuré sur l'instant du GESTE (`demandeInstant`, à défaut `demandeLe`).

import '../achats/circuit_synchro.dart' show valGenreCircuitAchat;
import '../administration/pta.dart' show valGenrePta;
import '../droits/gestes_reserves.dart' show gestePtaAdopter, gesteRhEtapeSurveillant, gesteRhEtapeDaf, gesteFichesAideValider, gesteDocumentsFiscauxImporter;
import '../administration/fiches_aide_synchro.dart' show valGenreFicheAideValider;
import '../comptabilite/documents_fiscaux_synchro.dart' show valGenreLiasseImporter;
import '../mecef/facture_tiers_synchro.dart' show valGenreFactureTiers, gesteDestinataireFactureTiers;
import '../rh/planning_synchro.dart' show valGenrePlanningRh;
import 'reglage_depose.dart' show gesteDuReglage, valGenreReglage;
import '../droits/gestes_reserves.dart' show gesteNumerotationModifier;
import '../numerotation/numerotation_versions.dart' show valGenreNumerotation;
import 'validation.dart' show valFamille;
import 'validation_deposee.dart';

/// La clé du réglage de clinique (famille `validations`, versionné par date) : le délai, en HEURES, au-delà duquel une décision en attente de la mère s'alerte.
const String cleDelaiAlerteMere = 'validations.delaiAlerteMereHeures';

/// Le type de la notification de poste écrite au-delà du délai.
const String typeNotifDecisionMereEnRetard = 'decision_mere_en_retard';

/// Le destinataire que la décision du 16/11/2026 nomme EN PLUS du validateur : l'administrateur (identifiant du rôle de l'administrateur système). Ce n'est pas un droit :
/// c'est l'adresse d'une information.
const String posteAdministrateur = 'admin';

/// Les trois files.
const String genreDecisionValidation = 'validation';
const String genreDecisionPrix = 'prix';
const String genreDecisionImport = 'import';

/// Les collections des trois files.
const String collectionDemandesPrix = 'propositionsTarif';
const String collectionDemandesImport = 'demandesImport';

/// Une décision qui attend la mère.
class DecisionEnAttente {
  const DecisionEnAttente({
    required this.genre,
    required this.id,
    required this.libelle,
    required this.par,
    required this.role,
    required this.depuis,
    this.poste,
    this.famille,
    this.sousGenre,
  });

  /// `validation`, `prix` ou `import`.
  final String genre;
  final String id;
  final String libelle;
  final String par;
  final String role;

  /// L'instant du geste (`null` : illisible, l'âge ne se dit pas).
  final DateTime? depuis;
  final String? poste;

  /// La famille d'une validation de référentiel ou d'un circuit d'achat.
  final String? famille;

  /// Le genre propre à la file (`referentiel`, `circuit_achat`, `proposition`, `decision`…).
  final String? sousGenre;

  /// La référence d'une alerte (une seule par décision et par destinataire).
  String get reference => '$genre:$id';

  Duration? age(DateTime maintenant) => depuis == null ? null : maintenant.difference(depuis!);
}

DateTime? _instant(Map<String, Object?> f) => DateTime.tryParse('${f['demandeInstant'] ?? f['demandeLe'] ?? ''}');

bool _actif(Map<String, Object?> f) => f['statut'] != 'archive';

/// Les décisions en attente de la mère, des trois files, de la plus ancienne à la plus récente.
List<DecisionEnAttente> decisionsEnAttenteMere({
  required Iterable<Map<String, Object?>> validations,
  required Iterable<Map<String, Object?>> demandesPrix,
  required Iterable<Map<String, Object?>> demandesImport,
}) {
  final out = <DecisionEnAttente>[
    for (final d in validations)
      if (_actif(d) && d['etat'] == valDepotDeposee)
        DecisionEnAttente(
            genre: genreDecisionValidation,
            id: '${d['id']}',
            libelle: '${d['libelle'] ?? d['famille'] ?? 'Validation'} (${d['cible'] ?? ''})',
            par: '${d['demandePar'] ?? ''}',
            role: '${d['demandeRole'] ?? ''}',
            depuis: _instant(d),
            poste: d['demandePoste'] as String?,
            famille: d['famille'] as String?,
            sousGenre: d['genre'] as String?),
    for (final d in demandesPrix)
      if (_actif(d) && d['etat'] == 'deposee')
        DecisionEnAttente(
            genre: genreDecisionPrix,
            id: '${d['id']}',
            libelle: 'Prix : ${d['genre'] ?? 'demande'} ${d['code'] ?? d['versionId'] ?? ''}'.trim(),
            par: '${d['demandePar'] ?? ''}',
            role: '${d['demandeRole'] ?? ''}',
            depuis: _instant(d),
            poste: d['demandePoste'] as String?,
            sousGenre: d['genre'] as String?),
    for (final d in demandesImport)
      if (_actif(d) && d['etat'] == 'en_attente' && '${d['traiteLe'] ?? ''}'.isEmpty)
        DecisionEnAttente(
            genre: genreDecisionImport,
            id: '${d['id']}',
            libelle: 'Import : ${d['jeuLibelle'] ?? d['jeu'] ?? ''}',
            par: '${d['demandePar'] ?? ''}',
            role: '${d['demandeRole'] ?? ''}',
            depuis: _instant(d),
            poste: d['demandePoste'] as String?,
            sousGenre: '${d['jeu'] ?? ''}'),
  ];
  out.sort((a, b) => (a.depuis ?? DateTime(9999)).compareTo(b.depuis ?? DateTime(9999)));
  return out;
}

/// Ce que dit la pastille : le compte par file et l'âge de la plus ancienne.
class ResumeDecisionsMere {
  const ResumeDecisionsMere({required this.validations, required this.prix, required this.imports, this.plusAncienne, this.enRetard = 0});
  final int validations;
  final int prix;
  final int imports;

  /// L'âge de la plus ancienne décision en attente (`null` : aucune, ou âge illisible).
  final Duration? plusAncienne;

  /// Combien ont dépassé le délai d'alerte.
  final int enRetard;
  int get total => validations + prix + imports;

  /// « 3 décisions en attente de la mère » ; vide à zéro (la pastille ne s'affiche pas).
  String get libelle => total == 0 ? '' : '$total décision${total > 1 ? 's' : ''} en attente de la mère';

  /// Le détail : par file, puis l'âge de la plus ancienne.
  String get detail => [
        '$validations validation${validations > 1 ? 's' : ''}',
        '$prix demande${prix > 1 ? 's' : ''} de prix',
        '$imports demande${imports > 1 ? 's' : ''} d’import',
        if (plusAncienne != null) 'la plus ancienne depuis ${libelleAgeDecision(plusAncienne!)}',
        if (enRetard > 0) '$enRetard au-delà du délai d’alerte',
      ].join(' · ');
}

/// Un âge lisible : minutes, heures, jours.
String libelleAgeDecision(Duration d) {
  if (d.isNegative) return 'à l’instant';
  if (d.inDays >= 1) return '${d.inDays} j ${d.inHours % 24} h';
  if (d.inHours >= 1) return '${d.inHours} h ${d.inMinutes % 60} min';
  if (d.inMinutes >= 1) return '${d.inMinutes} min';
  return 'à l’instant';
}

/// Le résumé de la pastille.
ResumeDecisionsMere resumerDecisionsMere(List<DecisionEnAttente> decisions, DateTime maintenant, {int? delaiHeures}) {
  Duration? max;
  var retard = 0;
  for (final d in decisions) {
    final a = d.age(maintenant);
    if (a == null) continue;
    if (max == null || a > max) max = a;
    if (delaiHeures != null && a >= Duration(hours: delaiHeures)) retard++;
  }
  return ResumeDecisionsMere(
      validations: decisions.where((d) => d.genre == genreDecisionValidation).length,
      prix: decisions.where((d) => d.genre == genreDecisionPrix).length,
      imports: decisions.where((d) => d.genre == genreDecisionImport).length,
      plusAncienne: max,
      enRetard: retard);
}

/// Le délai en vigueur (heures) lu d'une valeur du registre : un entier d'au moins 1 ; sinon [defaut] (le défaut de la définition, que l'appelant lit du registre).
int delaiAlerteMereDepuis(Object? valeur, {required int defaut}) {
  if (valeur is num && valeur.isFinite && valeur >= 1) return valeur.toInt();
  if (valeur is String) {
    final n = int.tryParse(valeur.trim());
    if (n != null && n >= 1) return n;
  }
  return defaut;
}

/// Les décisions qui ont dépassé le délai : celles dont l'âge atteint [delaiHeures].
List<DecisionEnAttente> decisionsEnRetard(List<DecisionEnAttente> decisions, DateTime maintenant, int delaiHeures) => [
      for (final d in decisions)
        if ((d.age(maintenant) ?? Duration.zero) >= Duration(hours: delaiHeures)) d
    ];

/// À QUI s'adresse l'alerte d'une décision : le validateur concerné, puis l'administrateur. Le validateur est lu de ce qui DÉCIDE déjà de la décision, jamais d'une liste écrite ici :
///  * une validation de référentiel : les rôles de sa famille au registre des validations (ceux que la mère accepte comme validateurs) ;
///  * un circuit d'achat : le geste réservé qui le valide ([gesteCircuit], routé `geste:<id>` vers les rôles qui le détiennent dans la matrice) ;
///  * une demande de prix : le geste réservé de décider un prix ([gestePrix]) ;
///  * une demande d'import : les rôles qui ARBITRENT les lots dans la matrice en force ([rolesArbitreImport], passés par l'appelant).
/// Rend des postes de notification (`geste:<id>` ou identifiant de rôle), sans doublon.
List<String> destinatairesAlerteDecision(DecisionEnAttente d, {required String gesteCircuit, required String gestePrix, List<String> rolesArbitreImport = const []}) {
  final out = <String>[];
  void ajouter(String p) {
    if (p.isNotEmpty && !out.contains(p)) out.add(p);
  }

  switch (d.genre) {
    case genreDecisionValidation:
      if (d.sousGenre == valGenreCircuitAchat) {
        ajouter('geste:$gesteCircuit');
      } else if (d.sousGenre == valGenrePta) {
        // Une décision du plan de travail annuel (lot PTA, 17/11/2026) : ceux qui détiennent le geste « adopter », lus dans la matrice.
        ajouter('geste:$gestePtaAdopter');
      } else if (d.sousGenre == valGenrePlanningRh) {
        // Une décision du planning (17/11/2026, décision 12) : ceux qui détiennent une étape du circuit (surveillant, directrice administrative), lus dans la matrice.
        ajouter('geste:$gesteRhEtapeSurveillant');
        ajouter('geste:$gesteRhEtapeDaf');
      } else if (d.sousGenre == valGenreNumerotation) {
        // Une série de numérotation (lot 2) : ceux qui détiennent le geste `numerotation_modifier`, lus dans la matrice.
        ajouter('geste:$gesteNumerotationModifier');
      } else if (d.sousGenre == valGenreFactureTiers) {
        // Une demande sur une facture à une entreprise (17/11/2026) : ceux qui détiennent le geste qui l'émet, lus dans la matrice.
        ajouter('geste:$gesteDestinataireFactureTiers');
      } else if (d.sousGenre == valGenreFicheAideValider) {
        // La validation d'une fiche d'aide (18/11/2026) : ceux qui détiennent le geste `fiches_aide_valider`, lus dans la matrice.
        ajouter('geste:$gesteFichesAideValider');
      } else if (d.sousGenre == valGenreLiasseImporter) {
        // L'import d'une liasse fiscale (18/11/2026) : ceux qui détiennent le geste `documents_fiscaux_importer`, lus dans la matrice.
        ajouter('geste:$gesteDocumentsFiscauxImporter');
      } else if (d.sousGenre == valGenreReglage) {
        // Un réglage posé sous un geste réservé (16/11/2026, §7) : ceux qui détiennent CE geste, lus dans la matrice.
        final g = gesteDuReglage('${d.famille}');
        if (g != null) ajouter('geste:$g');
      } else {
        for (final r in valFamille('${d.famille}')?.roles ?? const <String>[]) {
          ajouter(r);
        }
      }
    case genreDecisionPrix:
      ajouter('geste:$gestePrix');
    case genreDecisionImport:
      for (final r in rolesArbitreImport) {
        ajouter(r);
      }
  }
  ajouter(posteAdministrateur);
  return out;
}
