import 'package:sigh_domaine/sigh_domaine.dart' show DroitsOperation, OperationPair;
import 'package:sigh_sync/src/mere.dart';
import 'package:test/test.dart';

/// Les droits (Direction, 10/11/2026) : la fiche de droits est de la configuration que la mère seule écrit et que tous les postes reçoivent ; les décisions de droits sont
/// une fiche descriptive qu'un poste habilité dépose à la mère ; l'échange entre pairs lit les droits À CHAQUE évaluation, jamais une matrice capturée au démarrage.
void main() {
  test('rbac et modulesActifs sont de la configuration diffusée (famille R, la mère seule écrit) ; les décisions de droits sont de la famille A, écrites par tous les postes', () {
    expect(familles['rbac'], 'R');
    expect(familles['modulesActifs'], 'R');
    expect(familles['decisionsDroits'], 'A');
    expect(collectionsConfigurationPoste, containsAll(['rbac', 'modulesActifs']));
    expect(collectionsConfigurationPoste.contains('decisionsDroits'), isFalse, reason: 'ce n\'est pas de la configuration : un fileul l\'écrit');
    expect(collectionsConfigurationPoste.contains('rolesBase'), isFalse, reason: 'la graine des rôles voyage avec le logiciel, pas avec la mère');
  });

  test('les droits de l\'échange entre pairs sont lus à CHAQUE évaluation : une décision de droits vaut aussitôt, sans redémarrer la mère', () async {
    final cfg = ConfigMere(port: 0, dbChemin: ':memory:');
    final m = await Mere.creer(cfg);
    OperationPair op() => const OperationPair(id: 'o1', appareil: 'A', hlc: 1, collection: 'patients', fiche: 'p1', type: 'creer', role: 'reception');
    var ouvert = false;
    cfg.droitsPair = (OperationPair o) => ouvert;
    final DroitsOperation lus = m.pair.droits;
    expect(lus(op()), isFalse, reason: 'les droits injectés refusent');
    ouvert = true;
    expect(m.pair.droits(op()), isTrue, reason: 'la même mère, sans redémarrage : la décision est lue à l\'opération suivante');
    cfg.droitsPair = null;
    expect(m.pair.droits(op()), isNotNull, reason: 'sans injection, la matrice engendrée (graine) reste lue comme avant');
  });
}
