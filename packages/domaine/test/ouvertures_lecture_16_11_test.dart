import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef Fiche = Map<String, Object?>;

List<Fiche> _lire(String chemin) => [for (final f in jsonDecode(File(chemin).readAsStringSync()) as List) (f as Map).cast<String, Object?>()];
Map<String, Object?> _json(String chemin) => (jsonDecode(File(chemin).readAsStringSync()) as Map).cast<String, Object?>();

/// OUVERTURES DE DROITS EN LECTURE (décision de la Direction du 16/11/2026, `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md` § 2).
///
/// Chaque ouverture est une SURCHARGE D'ÉCRAN nommée dans la fiche `rbac` du rôle (`voir: true, editer: false, annuler: false`) — jamais un module
/// ouvert. Ce test le prouve rôle par rôle sur les TROIS lectures de la matrice : la matrice engendrée (`rbac.json`, ce que lisent la mère, le poste et
/// le mobile), la matrice RECALCULÉE depuis le manifeste et les fiches du jeu livré (aucune dérive entre la fiche et la case), et la superposition à
/// chaud du poste (jeu livré contre la référence de l'extraction).
const ouvertures = <String, List<String>>{
  // Planning et gardes : qui est de garde.
  'dm': ['m10-planning'],
  'infirmier': ['m10-planning'],
  'reception': ['m10-planning'],
  'ambulancier': ['m10-planning'],
  'chirurgien': ['m10-planning'],
  // Tarifs et prix (et sa page de renvoi « Catalogue tarifaire ») ; jamais la caisse ni la facturation. Le Responsable Radiologie suit le technicien
  // d'échographie (décision du 10/11/2026 : mêmes écrans, test d'alignement).
  'laborantin': ['cfg-tarifs', 'cfg-catalogue'],
  'echographiste': ['cfg-tarifs', 'cfg-catalogue'],
  'responsable_radiologie': ['cfg-tarifs', 'cfg-catalogue'],
  'comptable': ['cfg-tarifs', 'cfg-catalogue'],
  // Stock de la pharmacie : état du stock détail et lots ; ni mouvement, ni inventaire, ni transfert.
  'anesthesiste': ['m6-stock-detail', 'm6-lots'],
  // Plan des lits (qui est dans quel lit), sans les admissions ni le dossier.
  'agentadmin': ['m3-plan-lits'],
  // Fiche du personnel (17/11/2026, point 1) : en lecture, rémunération masquée au poste ; seul l'onglet « Planning individuel » s'écrit (geste « Régler le personnel »).
  'surveillant': ['m3-plan-lits', 'm10-personnel', 'm10-employe-profil'],
  'aide_soignant': ['m3-plan-lits'],
  // Activité (consultations, admissions) et état des ventes : l'Assistant de Direction (identifiant technique `assistant_comptable`).
  'assistant_comptable': ['m2-stats-consultations', 'm3-stats-hospitalisations', 'm6-point-ventes'],
};

/// Ce qui ne s'ouvre PAS avec : les écrans d'écriture voisins, que la décision n'ouvre pas.
const fermesAvec = <String, List<String>>{
  'dm': ['m10-presences', 'm10-primes', 'm10-personnel', 'm11-calcul'],
  'infirmier': ['m10-presences', 'm10-primes', 'm10-stats-gardes', 'm11-calcul'],
  'reception': ['m10-presences', 'm10-primes', 'm11-calcul'],
  'ambulancier': ['m10-presences', 'm10-primes', 'm11-calcul'],
  'chirurgien': ['m10-presences', 'm10-primes', 'm11-calcul'],
  'laborantin': ['m8-facturation', 'm8-caisse', 'm8-factures', 'cfg-modules'],
  'echographiste': ['m8-facturation', 'm8-caisse', 'm8-factures', 'cfg-modules'],
  'comptable': ['cfg-modules'],
  'anesthesiste': ['m6-mouvements', 'm6-inventaire', 'm6-transferts', 'm6-dispensation', 'm6-stock-gros', 'm6-pertes', 'm6-produits'],
  'agentadmin': ['m3-admissions', 'm3-surveillance', 'm1-dossier-medical', 'm2-dossiers-consultation'],
  'surveillant': ['m3-admissions', 'm3-surveillance', 'm1-dossier-medical', 'm2-dossiers-consultation', 'm10-primes', 'm10-evaluations', 'm10-sanctions', 'm10-contrats', 'm10-assurance-personnel', 'm11-calcul'],
  'aide_soignant': ['m3-admissions', 'm1-dossier-medical', 'm2-dossiers-consultation'],
  'assistant_comptable': ['m6-mouvements', 'm6-inventaire', 'm8-caisse', 'm5-resultats', 'dash-croise', 'dash-da'],
};

void main() {
  final brut = _json('../rbac/data/rbac.json');
  final base = MatriceDroits.depuisJson(brut);
  final manifeste = Manifeste.depuisJson(_json('../referentiels/data/manifeste.json'));
  final livre = _lire('../../apps/poste/assets/donnees/jeu/rbac.json');
  final reference = _lire('../../apps/poste/assets/donnees/rbac.reference.json');
  final modulesReference = _lire('../../apps/poste/assets/donnees/modulesActifs.reference.json');
  final recalculee = superposerDroits(base, manifeste, rbac: livre, modulesActifs: modulesReference);
  final aChaud = superposerDroits(base, manifeste,
      rbac: livre, modulesActifs: _lire('../../apps/poste/assets/donnees/jeu/modulesActifs.json'), referenceRbac: reference, referenceModules: modulesReference);
  const lecture = Droit(voir: true, editer: false, annuler: false);

  test('chaque écran ouvert existe au manifeste (aucun lien vers un écran absent)', () {
    for (final e in ouvertures.values.expand((x) => x)) {
      expect(manifeste.ecran(e), isNotNull, reason: e);
    }
  });

  group('chaque ouverture est une LECTURE SEULE, rôle par rôle', () {
    for (final o in ouvertures.entries) {
      for (final e in o.value) {
        test('${o.key} → $e : voir, ni éditer ni annuler', () {
          for (final (nom, m) in [('engendrée', base), ('recalculée', recalculee), ('à chaud', aChaud)]) {
            expect(m.droit(o.key, e), lecture, reason: '${o.key} / $e (matrice $nom)');
            expect(m.peutEditer(o.key, e), isFalse, reason: 'aucune écriture : ${o.key} / $e ($nom)');
            expect(m.peutAnnuler(o.key, e), isFalse, reason: 'aucune annulation : ${o.key} / $e ($nom)');
          }
        });
      }
    }
  });

  test('la fiche du rôle porte une SURCHARGE D\'ÉCRAN nommée, jamais l\'ouverture du module', () {
    for (final o in ouvertures.entries) {
      final f = livre.firstWhere((x) => x['role'] == o.key);
      final ecrans = (f['droitsEcrans'] as Map).cast<String, Object?>();
      for (final e in o.value) {
        expect(ecrans[e], {'voir': true, 'editer': false, 'annuler': false}, reason: '${o.key} / $e');
        final module = manifeste.ecran(e)!.module;
        final droitModule = (f['droits'] as Map?)?[module] as Map?;
        expect(droitModule?['voir'] == true, isFalse, reason: '${o.key} : le module $module n\'est pas ouvert pour autant');
      }
    }
  });

  test('les écrans voisins restent fermés : la lecture ouverte n\'emporte ni le module ni les écritures', () {
    for (final o in fermesAvec.entries) {
      for (final e in o.value) {
        expect(base.peutVoir(o.key, e), isFalse, reason: '${o.key} / $e');
        expect(recalculee.peutVoir(o.key, e), isFalse, reason: '${o.key} / $e (recalculée)');
      }
    }
  });

  test('la matrice engendrée est EXACTEMENT ce que donnent le manifeste et les fiches (aucune case recopiée à la main)', () {
    // Les rôles de la décision ; les autres (pharmacien et RH rouverts par le jeu livré le 06/11/2026) ont leur propre histoire, hors de ce test. La
    // superposition à chaud n'est pas comparée en entier ici : le jeu livré rouvre aussi la banque de sang (fermée à l'extraction), sans rapport avec la décision.
    for (final role in ouvertures.keys) {
      expect(recalculee.parRoleBrut(role), base.parRoleBrut(role), reason: role);
    }
  });

  test('le Biologiste lit déjà le stock de réactifs du laboratoire (module M5) : rien à ouvrir, rien de retiré', () {
    expect(base.peutVoir('laborantin', 'm5-reactifs'), isTrue);
    expect(base.peutVoir('laborantin', 'm5-reactifs-stats'), isTrue);
  });

  test('plan des lits : ni diagnostic, ni séjour pour les trois profils (catégories sensibles refusées par défaut, sans décision)', () {
    final sensibles = DroitsSensibles(fiches: livre, peutVoirEcran: base.peutVoir);
    for (final role in ['agentadmin', 'surveillant', 'aide_soignant']) {
      for (final cat in ['diagnostic_pathologie', 'notes_consultation', 'hospitalisation_soins', 'antecedents']) {
        expect(sensibles.peut(role, cat), isFalse, reason: '$role / $cat');
        expect(sensibles.origine(role, cat), 'defaut', reason: '$role / $cat : aucune décision écrite, le défaut suit la matrice');
      }
    }
  });

  test('rien de ces ouvertures ne va au téléphone : aucun écran du mobile ne porte le droit d\'un écran ouvert', () {
    final ouverts = ouvertures.values.expand((x) => x).toSet();
    for (final e in mobEcransManifeste.entries) {
      expect(ouverts.contains(e.value), isFalse, reason: '${e.key} → ${e.value}');
    }
  });
}
