import 'dart:async';

import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_parametres.dart';
import '../donnees/magasin.dart';

/// LES DÉCISIONS EN ATTENTE DE LA MÈRE, AU POSTE (section AI, Direction du 16/11/2026). Les règles sont au domaine (`decisions_en_attente.dart`) ; ce service y branche le magasin,
/// le réglage de clinique et la notification de poste.
///
///  * [resume] : ce que dit la pastille « N décisions en attente de la mère » — les TROIS files (validations, demandes de prix, demandes d'import) et l'âge de la plus ancienne ;
///  * [verifier] : au-delà du délai réglé en base (`validations.delaiAlerteMereHeures`, 4 heures semées, versionné par date), UNE notification de poste par décision et par
///    destinataire (le validateur concerné, lu de ce qui décide déjà de la décision — registre des validations, geste réservé de la matrice, droit d'arbitrer les lots — puis
///    l'administrateur). Rien n'est bloqué, rien n'est appliqué à la place de la mère, rien n'est écrit sur la décision elle-même.
class AlerteDecisionsMere {
  AlerteDecisionsMere._(this.magasin);
  static final Expando<AlerteDecisionsMere> _instances = Expando('AlerteDecisionsMere');
  static AlerteDecisionsMere de(Magasin m) => _instances[m] ??= AlerteDecisionsMere._(m);

  final Magasin magasin;

  /// La matrice EN FORCE (rôles qui arbitrent les lots d'import) ; non branchée : l'alerte d'un import va à l'administrateur seul.
  MatriceDroits Function()? matrice;

  DateTime Function()? horloge;
  DateTime get _maintenant => (horloge ?? magasin.horloge)();

  Timer? _minuterie;

  /// Les décisions en attente que ce poste connaît.
  List<DecisionEnAttente> decisions() => decisionsEnAttenteMere(
      validations: magasin.collection(valCollectionDepots).toutes,
      demandesPrix: magasin.collection(collectionDemandesPrix).toutes,
      demandesImport: magasin.collection(collectionDemandesImport).toutes);

  /// Le délai d'alerte EN VIGUEUR aujourd'hui (heures), lu de la base ; le défaut de la définition tant que la fiche n'est pas arrivée.
  int delaiHeures() {
    final d = (definitionDeParametre(cleDelaiAlerteMere)!.defaut as num).toInt();
    final v = serviceParametres(magasin, auteur: () => 'lecture', horloge: () => _maintenant).valeur(cleDelaiAlerteMere, parametreDateIso(_maintenant));
    return delaiAlerteMereDepuis(v, defaut: d);
  }

  /// La pastille : les trois files, l'âge de la plus ancienne, et combien ont dépassé le délai.
  ResumeDecisionsMere resume() => resumerDecisionsMere(decisions(), _maintenant, delaiHeures: delaiHeures());

  List<String> _rolesArbitreImport() {
    final mat = matrice?.call();
    if (mat == null) return const [];
    return [
      for (final r in mat.rolesBruts)
        if (!mat.estArchive('${r['id']}') && mat.peutAnnuler('${r['id']}', ecranLotsImport)) '${r['id']}'
    ];
  }

  /// Écrit l'alerte de chaque décision qui a dépassé le délai : une notification par décision et par destinataire, jamais deux (rejouable). Rend le nombre de notifications écrites.
  int verifier() {
    final heures = delaiHeures();
    final retard = decisionsEnRetard(decisions(), _maintenant, heures);
    if (retard.isEmpty) return 0;
    final notifs = magasin.collection('notifications');
    final deja = {
      for (final n in notifs.toutes)
        if (n['type'] == typeNotifDecisionMereEnRetard) '${n['reference']}|${n['poste']}'
    };
    final arbitres = _rolesArbitreImport();
    var n = 0;
    for (final d in retard) {
      final age = d.age(_maintenant);
      for (final poste in destinatairesAlerteDecision(d, gesteCircuit: gesteValiderAchats, gestePrix: gesteDeciderPrix, rolesArbitreImport: arbitres)) {
        if (deja.contains('${d.reference}|$poste')) continue;
        notifs.inserer({
          'type': typeNotifDecisionMereEnRetard,
          'poste': poste,
          'destinataire': null,
          'libelle': 'Décision en attente de la mère depuis ${age == null ? 'plus de $heures h' : libelleAgeDecision(age)}',
          'detail': '${d.libelle}, déposée par ${d.par.isEmpty ? 'un agent' : d.par}${d.poste == null ? '' : ' (poste ${d.poste})'} : la mère ne l’a pas encore appliquée '
              '(délai d’alerte de la clinique : $heures h). Rien n’est bloqué et rien n’est validé à sa place ; vérifier que la mère est allumée et joignable.',
          'priorite': 'haute',
          'reference': d.reference,
          'lue': false,
          'creeLe': _maintenant.toUtc().toIso8601String(),
          'statut': 'actif',
        }, prefixe: 'NOT');
        n++;
      }
    }
    return n;
  }

  /// Démarre la vérification périodique (une minute par défaut : le délai se compte en heures).
  void demarrer({Duration intervalle = const Duration(minutes: 1)}) {
    _minuterie?.cancel();
    _minuterie = Timer.periodic(intervalle, (_) => verifier());
    verifier();
  }

  void arreter() {
    _minuterie?.cancel();
    _minuterie = null;
  }
}
