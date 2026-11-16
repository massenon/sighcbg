import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// LE PLANNING À TRAVERS LES POSTES (17/11/2026, décision 12) : le moteur PUR que la mère (Dart et Node) et le poste partagent. Données fictives.
typedef M = Map<String, Object?>;

void main() {
  String? code(RefusRh? r) => r?.code;

  test('une pièce à circuit naît « à valider » ; la validation ne s’écrit pas par un poste, ne se défait pas', () {
    for (final c in ['presences', 'conges', 'missions']) {
      expect(code(refusPlanningRh(c, 'creer', {'validationEtat': 'a_valider'})), isNull, reason: c);
      expect(code(refusPlanningRh(c, 'creer', {'validationEtat': 'valide'})), 'validation_reservee', reason: c);
      expect(code(refusPlanningRh(c, 'creer', {'validationEtat': 'refuse'})), 'validation_reservee', reason: c);
      expect(code(refusPlanningRh(c, 'modifier', {'validationEtat': 'valide'}, actuelle: {'validationEtat': 'a_valider'})), 'validation_reservee', reason: c);
      expect(code(refusPlanningRh(c, 'modifier', {'validationEtat': 'valide_surveillant'}, actuelle: {'validationEtat': 'a_valider'})), 'validation_reservee', reason: c);
      expect(code(refusPlanningRh(c, 'modifier', {'validationEtat': 'a_valider'}, actuelle: {'validationEtat': 'valide'})), 'validation_defaite', reason: c);
      expect(code(refusPlanningRh(c, 'modifier', {'validationEtat': 'valide'}, actuelle: {'validationEtat': 'valide'})), isNull, reason: 'même état renvoyé : rien à refuser');
      expect(code(refusPlanningRh(c, 'modifier', {'validePar': 'X'}, actuelle: {'validationEtat': 'a_valider'})), 'champ_reserve', reason: c);
    }
    expect(code(refusPlanningRh('conges', 'creer', {'statutConge': 'valide'})), 'validation_reservee');
    expect(code(refusPlanningRh('conges', 'creer', {'statutConge': 'en_attente'})), isNull);
    expect(code(refusPlanningRh('missions', 'creer', {'statutMission': 'validee'})), 'validation_reservee');
    expect(code(refusPlanningRh('missions', 'creer', {'statutMission': 'projet'})), isNull);
    // Une pièce d'avant le circuit (sans état) se lit « validée » : elle ne repasse pas « à valider ».
    expect(code(refusPlanningRh('conges', 'modifier', {'validationEtat': 'a_valider'}, actuelle: {'statutConge': 'valide'})), 'validation_defaite');
  });

  test('un pointage validé ne se modifie que par une régularisation tracée', () {
    final v = <String, Object?>{'validationEtat': 'valide', 'etat': 'present', 'regularisations': <Object?>[]};
    expect(code(refusPlanningRh('presences', 'modifier', {'etat': 'absent'}, actuelle: v)), 'presence_validee');
    expect(code(refusPlanningRh('presences', 'modifier', {'etat': 'absent', 'regularisations': <Object?>[{'par': 'X'}]}, actuelle: v)), isNull);
    expect(code(refusPlanningRh('presences', 'modifier', {'observation': 'note'}, actuelle: v)), isNull);
  });

  test('une vacation naît « à valider » (sans état elle compterait comme validée) ; validée, elle ne se réécrit ni ne s’archive par un poste', () {
    expect(code(refusPlanningRh('planning', 'creer', {'date': '2031-03-14'})), 'validation_reservee');
    expect(code(refusPlanningRh('planning', 'creer', {'validationEtat': 'validee'})), 'validation_reservee');
    expect(code(refusPlanningRh('planning', 'creer', {'validationEtat': 'a_valider', 'validePar': 'X'})), 'champ_reserve');
    expect(code(refusPlanningRh('planning', 'creer', {'validationEtat': 'a_valider', 'date': '2031-03-14'})), isNull);
    final attente = <String, Object?>{'validationEtat': 'a_valider', 'date': '2031-03-14', 'type': 'garde'};
    expect(code(refusPlanningRh('planning', 'modifier', {'date': '2031-03-15'}, actuelle: attente)), isNull, reason: 'l’auteur corrige sa vacation en attente');
    expect(code(refusPlanningRh('planning', 'modifier', {'validationEtat': 'validee'}, actuelle: attente)), 'validation_reservee');
    final validee = <String, Object?>{'validationEtat': 'validee', 'date': '2031-03-14', 'type': 'garde', 'employeId': 'EA'};
    expect(code(refusPlanningRh('planning', 'modifier', {'date': '2031-03-15'}, actuelle: validee)), 'vacation_validee');
    expect(code(refusPlanningRh('planning', 'modifier', {'employeId': 'EB'}, actuelle: validee)), 'vacation_validee');
    expect(code(refusPlanningRh('planning', 'modifier', {'date': '2031-03-14'}, actuelle: validee)), isNull, reason: 'même valeur renvoyée');
    expect(code(refusPlanningRh('planning', 'modifier', {'validationEtat': 'a_valider'}, actuelle: validee)), 'validation_defaite');
    expect(code(refusPlanningRh('planning', 'modifier', {'statut': 'archive'}, actuelle: validee)), 'vacation_validee');
    expect(code(refusPlanningRh('planning', 'modifier', {'statut': 'archive'}, actuelle: attente)), isNull);
    // Une vacation d'avant le circuit (sans état) est validée.
    expect(planningVacationValidee({'date': 'x'}), isTrue);
    expect(planningVacationValidee({'validationEtat': 'a_valider'}), isFalse);
  });

  test('une proposition naît « proposee » ; sa décision est réservée, elle ne recule pas', () {
    expect(code(refusPlanningRh('propositionsPlanning', 'creer', {'etat': 'proposee'})), isNull);
    expect(code(refusPlanningRh('propositionsPlanning', 'creer', {'etat': 'validee'})), 'validation_reservee');
    expect(code(refusPlanningRh('propositionsPlanning', 'modifier', {'etat': 'refusee'}, actuelle: {'etat': 'proposee'})), 'validation_reservee');
    expect(code(refusPlanningRh('propositionsPlanning', 'modifier', {'etat': 'annulee'}, actuelle: {'etat': 'proposee'})), isNull, reason: 'l’agent retire sa proposition');
    expect(code(refusPlanningRh('propositionsPlanning', 'modifier', {'etat': 'annulee'}, actuelle: {'etat': 'validee'})), 'etat_regressif');
    expect(code(refusPlanningRh('propositionsPlanning', 'modifier', {'tranchePar': 'X'}, actuelle: {'etat': 'proposee'})), 'champ_reserve');
    expect(code(refusPlanningRh('patients', 'creer', {'validationEtat': 'valide'})), isNull, reason: 'une autre collection n’est pas concernée');
  });

  test('le dépôt : forme, non-duplication, actions et collections connues', () {
    final depots = <M>[];
    var n = 0;
    VerdictDepot depose({String action = planningActionTrancher, String role = 'surveillant', String cible = 'F1-PRS1'}) => planningRhDeposer(
        action: action, collection: 'presences', cible: cible, libelle: 'pointage', role: role, acteur: 'S', poste: 'F2', maintenant: DateTime(2031, 3, 10), depots: depots, nouvelId: () => 'D${n++}', decision: 'valider');
    final a = depose();
    expect(a.ok && !a.dejaDepose, isTrue);
    expect([a.fiche!['genre'], a.fiche!['famille'], a.fiche!['etat'], a.fiche!['collection']], [valGenrePlanningRh, 'planning_trancher', valDepotDeposee, 'presences']);
    depots.add(a.fiche!);
    expect(depose().dejaDepose, isTrue, reason: 'un dépôt identique qui attend la mère n’est pas doublé');
    expect(depose(role: 'da').dejaDepose, isFalse);
    expect(depose(cible: 'F1-PRS2').dejaDepose, isFalse);
    expect(depose(action: 'inconnue').refus!.code, 'ACTION_INCONNUE');
    expect(planningRhDeposer(action: planningActionPoser, collection: 'patients', cible: 'x', libelle: 'x', role: 'r', acteur: 'a', poste: 'p', maintenant: DateTime(2031), depots: const [], nouvelId: () => 'x').refus!.code, 'COLLECTION_INCONNUE');
  });

  test('la fusion ne défait jamais une validation ; une validation inventée ici cède au journal', () {
    final local = <String, Object?>{'validationEtat': 'a_valider', 'x': 1};
    final recu = <String, Object?>{'validationEtat': 'valide', 'validePar': 'S', 'valideLe': '2031-03-10', 'etapesFaites': <Object?>[{'etape': 'surveillant'}], 'x': 1};
    final fusion = {...local};
    fusionnerPlanningRh('presences', fusion, local, recu);
    expect([fusion['validationEtat'], fusion['validePar']], ['valide', 'S']);
    // Un état plus avancé local (poste rattaché, écriture refusée) cède.
    final f2 = {'validationEtat': 'valide', 'validePar': 'Moi'};
    fusionnerPlanningRh('presences', f2, {'validationEtat': 'valide', 'validePar': 'Moi'}, {'validationEtat': 'a_valider'}, refusLocal: true, posteFileul: true);
    expect(f2['validationEtat'], 'a_valider');
    expect(f2.containsKey('validePar'), isFalse);
    // Sans refus, un état local plus avancé reste (jamais défait).
    final f3 = {'validationEtat': 'valide'};
    fusionnerPlanningRh('presences', f3, {'validationEtat': 'valide'}, {'validationEtat': 'a_valider'});
    expect(f3['validationEtat'], 'valide');
    // Vacation : le journal validé l'emporte sur une copie « à valider ».
    final v = <String, Object?>{'validationEtat': 'a_valider', 'statut': 'a_valider'};
    fusionnerPlanningRh('planning', v, {'validationEtat': 'a_valider', 'statut': 'a_valider'}, {'validationEtat': 'validee', 'statut': 'validee', 'validePar': 'S'});
    expect([v['validationEtat'], v['statut'], v['validePar']], ['validee', 'validee', 'S']);
    // Proposition tranchée.
    final p = <String, Object?>{'etat': 'proposee'};
    fusionnerPlanningRh('propositionsPlanning', p, {'etat': 'proposee'}, {'etat': 'validee', 'tranchePar': 'S', 'appliquees': <Object?>['M-PLN1']});
    expect([p['etat'], p['tranchePar']], ['validee', 'S']);
  });

  test('les doublons d’affectation entre postes : même agent, même jour, hors vacations archivées', () {
    final g = planningAffectationsEnDoublon([
      {'id': 'a', 'employeId': 'EA', 'date': '2031-03-14'},
      {'id': 'b', 'employeId': 'EA', 'date': '2031-03-14', 'validationEtat': 'a_valider'},
      {'id': 'c', 'employeId': 'EA', 'date': '2031-03-15'},
      {'id': 'd', 'employeId': 'EB', 'date': '2031-03-14'},
      {'id': 'e', 'employeId': 'EB', 'date': '2031-03-14', 'statut': 'archive'},
    ]);
    expect(g, hasLength(1));
    expect([for (final v in g.single) v['id']], ['a', 'b']);
  });
}
