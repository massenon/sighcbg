// PLANNING INDIVIDUEL (Direction de Baguidi, 17/11/2026) : le geste DÉDIÉ `rh_planning_individuel`. Le Surveillant écrit le régime individuel d'un agent ; ce droit ne lui donne
// AUCUN autre droit RH (circuit de validation, délai du badge, copie de la fiche de paie : `rh_regler`) ; une fiche de rôle l'accorde et le retire.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

F fiche(String role, Map<String, bool> gestes) => {'id': 'R-$role', 'role': role, 'statut': 'actif', 'droitsGestes': gestes};

({RefusRh? refus, F? champs}) poser(String role, {DroitsGestes? gestes}) => validerDerogationRh(
    role: role, agentExiste: true, dateEffet: '2026-11-20', motif: 'Sonde', retourCategorie: false, champs: const {'repos': 'repos24'}, versions: const [], aujourdhui: '2026-11-17', gestes: gestes);

void main() {
  const g = gesteRhPlanningIndividuel;

  test('le geste est au référentiel : le surveillant, la DAF et l’administrateur d’origine, aucun autre', () {
    expect(gesteReserve(g), isNotNull);
    final d = DroitsGestes(fiches: const []);
    expect(d.rolesAvec(g, const ['admin', 'da', 'surveillant', 'direction', 'rh', 'dm', 'medecin', 'infirmier', 'comptable', 'reception', 'caissier', 'un_role_cree_en_exploitation']),
        ['admin', 'da', 'surveillant']);
  });

  test('ceux qui écrivaient le planning par `rh_regler` (DAF, administrateur) ne perdent rien', () {
    final d = DroitsGestes(fiches: const []);
    for (final r in ['admin', 'da']) {
      expect(d.peut(r, gesteRhRegler), isTrue, reason: r);
      expect(d.peut(r, g), isTrue, reason: r);
    }
  });

  test('le Surveillant pose un régime individuel, mais ne règle RIEN d’autre : ni circuit, ni copie de paie, ni badge', () {
    final d = DroitsGestes(fiches: const []);
    expect(poser('surveillant', gestes: d).refus, isNull);
    expect(d.peut('surveillant', gesteRhRegler), isFalse);
    expect(controlerReglageRh(role: 'surveillant', genre: 'circuit', valeur: 'surveillant', gestes: d)?.code, 'REGLAGE_RESERVE');
    expect(controlerReglageCopiePaie('surveillant', gestes: d)?.code, 'REGLAGE_RESERVE');
    expect(d.peut('surveillant', gesteRhConfirmerValeur), isFalse, reason: 'aucune valeur d’attente de rémunération à confirmer');
  });

  test('l’inverse : `rh_regler` ne donne pas le planning individuel (geste dédié, pas un sous-ensemble)', () {
    final d = DroitsGestes(fiches: [fiche('direction', {gesteRhRegler: true})]);
    expect(d.peut('direction', gesteRhRegler), isTrue);
    expect(poser('direction', gestes: d).refus?.code, 'DEROGATION_RESERVEE');
  });

  test('la fiche de rôle accorde (hors origine) et retire (à l’origine) : réglable', () {
    expect(poser('reception', gestes: DroitsGestes(fiches: const [])).refus?.code, 'DEROGATION_RESERVEE');
    expect(poser('reception', gestes: DroitsGestes(fiches: [fiche('reception', {g: true})])).refus, isNull);
    expect(poser('surveillant', gestes: DroitsGestes(fiches: [fiche('surveillant', {g: false})])).refus?.code, 'DEROGATION_RESERVEE');
  });
}
