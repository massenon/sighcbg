import 'package:sigh_domaine/sigh_domaine.dart';

import 'magasin.dart';

/// MIGRATION AU DÉMARRAGE (Direction, 09/11/2026, D2) : le versement des cotisations CNSS au 15 (`CNSS-VERS`, date NON ARRÊTÉE) est arrivé au calendrier
/// après que des postes ont été installés. Un poste déjà installé le REÇOIT au démarrage, sans attendre qu'un agent ouvre un écran.
///
/// Les règles, une par garde-fou :
/// - **idempotente** : l'obligation est cherchée PAR SON CODE (obligations actives, archivées et historique compris) ; deux démarrages = une seule fiche, et
///   les échéances portent un identifiant déterminé (`ECH<exercice>-CNSS-VERS-<mm>`) : deux postes qui migrent chacun de leur côté produisent les mêmes
///   fiches, la synchronisation les confond au lieu de les doubler ;
/// - **n'écrase JAMAIS** : une fiche existante (jour modifié, date arrêtée par la Direction, archivée ou retirée) n'est ni réécrite ni ressuscitée ;
/// - **ne touche pas aux échéances existantes**, payées ou non (un MOIS déjà couvert n'est pas recréé, quel qu'en soit le jour : la Direction a pu le déplacer) : seules les échéances MANQUANTES de l'exercice courant sont créées, toutes non payées,
///   sans quittance inventée ;
/// - **rien n'est créé sur un poste neuf** (collection vide) : `ConfigurationFiscalePoste.amorcer` sème alors tout le calendrier, CNSS-VERS compris, et
///   `amorcerEcheances` engendre l'exercice entier — créer ici seulement les échéances de CNSS-VERS le priverait de ses voisines ;
/// - **journalisée** (RG-12), acteur « migration » ; **jamais une suppression** (RG-14).
const codeCnssVers = 'CNSS-VERS';
const acteurMigration = 'migration';

/// Ce que la migration a fait : l'obligation ajoutée (ou non), et le nombre d'échéances créées sur l'exercice.
class ResultatMigrationCnssVers {
  const ResultatMigrationCnssVers({required this.obligationAjoutee, required this.echeancesCreees, required this.exercice});
  final bool obligationAjoutee;
  final int echeancesCreees;
  final int exercice;
  bool get aFaitQuelqueChose => obligationAjoutee || echeancesCreees > 0;
}

ResultatMigrationCnssVers migrerCnssVers(Magasin m, {DateTime? aujourdhui}) {
  final auj = aujourdhui ?? DateTime.now();
  final exercice = auj.year;
  const rien = ResultatMigrationCnssVers(obligationAjoutee: false, echeancesCreees: 0, exercice: 0);
  final obl = m.collection('obligationsFiscales');
  // Poste neuf : le semis de l'écran couvre tout le calendrier.
  if (obl.toutes.isEmpty) return rien;
  final hist = m.collection('historiqueObligations');
  final ech = m.collection('echeancesFiscales');
  final ancienUtilisateur = m.utilisateur;
  m.utilisateur = acteurMigration;
  try {
    var ajoutee = false;
    final connues = [...obl.toutes, ...hist.toutes].where((f) => f['code'] == codeCnssVers).toList();
    Fiche? fiche = obl.actives.where((f) => f['code'] == codeCnssVers && f['type'] != 'parametres').firstOrNull;
    if (connues.isEmpty) {
      final source = cfbCalendrierFiscal.firstWhere((o) => o.code == codeCnssVers);
      var f = cfbFicheDepuisObligation(source);
      if (obl.parId(f['id']) != null) f = {...f, 'id': 'FIS-$codeCnssVers'};
      f = {...f, '_creePar': acteurMigration, '_creeLe': m.horloge().toUtc().toIso8601String()};
      obl.ajouterSansJournal(f);
      m.journaliser('Migration : obligation $codeCnssVers ajoutée', 'M12', 'obligationsFiscales', codeCnssVers, null,
          {'id': f['id'], 'jour': f['jour'], 'statutArret': f['statutArret'], 'source': f['source']});
      fiche = f;
      ajoutee = true;
    }
    // Obligation archivée ou retirée par la Direction : elle ne revient pas.
    if (fiche == null) return ResultatMigrationCnssVers(obligationAjoutee: ajoutee, echeancesCreees: 0, exercice: exercice);
    // L'exercice n'a encore aucune échéance : `amorcerEcheances` l'engendrera en entier à l'ouverture de l'écran.
    final exerciceAmorce = ech.toutes.any((e) => nombreOuZero(e['exercice']).toInt() == exercice);
    var creees = 0;
    if (exerciceAmorce) {
      final deja = {
        for (final e in ech.toutes)
          if (e['code'] == codeCnssVers && nombreOuZero(e['exercice']).toInt() == exercice) '${e['echeanceTheorique'] ?? e['echeance']}'.substring(0, 7)
      };
      final ids = {for (final e in ech.toutes) e['id']};
      final nouvelles = <Fiche>[];
      for (final e in cfbGenEcheances(exercice, obligationsFixes: [fiche], aujourdhui: auj, sansReglement: true)) {
        if (e['code'] != codeCnssVers || deja.contains('${e['echeanceTheorique']}'.substring(0, 7))) continue;
        final mois = '${e['echeanceTheorique']}'.substring(5, 7);
        final id = 'ECH$exercice-$codeCnssVers-$mois';
        if (ids.contains(id)) continue;
        nouvelles.add({...e, 'id': id, 'paye': false, 'datePaiement': null, 'reference': null, 'valideePar': null, '_creePar': acteurMigration});
      }
      for (final e in nouvelles) {
        ech.ajouterSansJournal(e);
      }
      creees = nouvelles.length;
      if (creees > 0) {
        m.journaliser('Migration : échéances $codeCnssVers créées', 'M12', 'echeancesFiscales', codeCnssVers, null,
            {'exercice': exercice, 'creees': creees, 'echeances': [for (final e in nouvelles) e['echeance']]});
      }
    }
    return ResultatMigrationCnssVers(obligationAjoutee: ajoutee, echeancesCreees: creees, exercice: exercice);
  } finally {
    m.utilisateur = ancienUtilisateur;
  }
}
