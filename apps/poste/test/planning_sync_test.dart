import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/planning_rh_poste.dart';
import 'package:sigh_poste/modules/m11/pai_commun.dart' show entreesPaie;
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_validations_deposees.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;
import 'package:sigh_sync/sigh_sync.dart';
// ignore: implementation_imports
import 'package:sigh_sync/src/mere.dart' show Appareil, familles, collectionsPlanningJamaisMobile;

/// LE PLANNING À TRAVERS LES POSTES (Direction de Baguidi, 17/11/2026, décision 12) : planning (vacations), propositions, congés, ordres de mission et présences voyagent entre postes
/// (famille A), jamais vers un téléphone ; la VALIDATION se dépose et la mère l'applique sous le rôle de l'auteur ; la mère REFAIT le contrôle d'un poste.
/// Contre la VRAIE mère Dart : le transport des ponts est son `traiter`, donc chaque refus est réel. Données fictives.
typedef M = Map<String, Object?>;

class _Liaison {
  _Liaison(this.mere);
  final Mere mere;
  bool coupee = false;
  int n = 0;
}

class _Transport implements TransportPont {
  _Transport(this.l, this.app);
  final _Liaison l;
  final Appareil app;
  @override
  Future<List<PieceSync>> liste(String c) async {
    if (l.coupee) throw StateError('mère injoignable');
    final rows = await l.mere.base.select('SELECT id,data,archive FROM fiches WHERE collection=?', [c]);
    return [for (final r in rows) PieceSync('${r['id']}', (jsonDecode(r['data'] as String) as Map).cast<String, Object?>(), archive: (r['archive'] as int) != 0)];
  }

  @override
  Future<void> ecrire(String c, String fiche, {required bool existe, required Map<String, Object?> champs}) async {
    if (l.coupee) throw StateError('mère injoignable');
    final f = await l.mere.lire(c, fiche);
    final vu = <String, Object?>{for (final k in champs.keys) if (f != null && f.fieldseq[k] != null) k: f.fieldseq[k]};
    final r = await l.mere.traiter({'id': 'op${l.n++}', 'type': existe ? 'modifier' : 'creer', 'collection': c, 'fiche': fiche, 'champs': jsonDecode(jsonEncode(champs)), 'hlc': 1000 + l.n, 'vu': vu}, app);
    if (r['statut'] == 'refusee') throw StateError('${r['code']} : ${r['motif']}');
  }

  @override
  Future<void> restaurer(String collection, String fiche) async => throw StateError('non porté');
}

void main() {
  final auj = DateTime(2031, 3, 10, 9);
  Magasin poste() {
    final m = Magasin({
      'personnel': <M>[
        {'id': 'EA', 'statut': 'actif', 'nomComplet': 'Agent Alpha', 'matricule': 'M1', 'fonction': 'infirmier', 'service': 'Soins'},
        {'id': 'ES', 'statut': 'actif', 'nomComplet': 'Surveillant Sigma', 'matricule': 'M2', 'fonction': 'infirmier', 'service': 'Soins'},
        {'id': 'EB', 'statut': 'actif', 'nomComplet': 'Agent Beta', 'matricule': 'M3', 'fonction': 'infirmier', 'service': 'Soins'},
      ],
      for (final n in [...planningCollectionsSync, 'regimesTravail', 'regimesIndividuels', valCollectionDepots, 'notifications', 'rbac', 'utilisateurs', 'audit']) n: <M>[],
    }, 'POSTE')
      ..horloge = () => auj;
    serviceParametres(m, auteur: () => 'Poste mère').semerDefauts();
    return m;
  }

  test('les cinq collections : famille A à la mère Dart et au banc Node, pont du poste, jamais vers un téléphone, `presences` enfin connue', () {
    expect(planningCollectionsSync, ['planning', 'propositionsPlanning', 'conges', 'missions', 'presences']);
    expect(collectionsActivite, containsAll(planningCollectionsSync));
    for (final c in planningCollectionsSync) {
      expect(familles[c], 'A', reason: '$c : fiche modifiable champ par champ');
    }
    expect(collectionsPlanningJamaisMobile, containsAll(planningCollectionsSync));
    final dart = File('../../packages/sync_dart/lib/src/mere.dart').readAsStringSync();
    expect(dart, contains('...collectionsPlanningJamaisMobile'), reason: 'exclues au chemin de lecture du mobile');
    expect(dart, contains('refusPlanningRh('), reason: 'la mère refait le contrôle');
    final js = File('../../packages/sync/banc/mere.js').readAsStringSync();
    expect(js, contains("planning: 'A', propositionsPlanning: 'A', conges: 'A', missions: 'A', presences: 'A'"));
    final jamais = RegExp(r'const MOBILE_JAMAIS = \[([^\]]*)\]').firstMatch(js)!.group(1)!;
    for (final c in planningCollectionsSync) {
      expect(jamais, contains("'$c'"));
    }
  });

  test('la VRAIE mère Dart refait le contrôle : pièce jamais créée validée, validation non écrite par un poste ni défaite, vacation validée non réécrite, présences acceptées', () async {
    final d = Directory.systemTemp.createTempSync('planning-mere');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere = await Mere.creer(ConfigMere(port: 19594, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes'));
    final fileul = Appareil('F1', 'fileul'), laMere = Appareil('mere', 'mere');
    var n = 0;
    Future<Map<String, Object?>> op(Appareil a, String type, String c, String fiche, Map<String, Object?> champs) async {
      final f = await mere.lire(c, fiche);
      final vu = <String, Object?>{for (final k in champs.keys) if (f != null && f.fieldseq[k] != null) k: f.fieldseq[k]};
      return mere.traiter({'id': 'op${n++}', 'type': type, 'collection': c, 'fiche': fiche, 'champs': champs, 'hlc': 1000 + n, 'vu': vu}, a);
    }

    String? code(Map<String, Object?> r) => r['statut'] == 'refusee' ? '${r['code']}' : null;
    // Présences : refusée `collection_inconnue` avant ce lot.
    expect(code(await op(fileul, 'creer', 'presences', 'F1-PRS1', {'employeId': 'EA', 'date': '2031-03-10', 'etat': 'present', 'validationEtat': 'a_valider', 'etapesFaites': <Object?>[]})), isNull);
    expect(code(await op(fileul, 'creer', 'presences', 'F1-PRS2', {'employeId': 'EA', 'date': '2031-03-11', 'etat': 'present', 'validationEtat': 'valide'})), 'validation_reservee');
    expect(code(await op(fileul, 'modifier', 'presences', 'F1-PRS1', {'validationEtat': 'valide'})), 'validation_reservee');
    expect(code(await op(fileul, 'modifier', 'presences', 'F1-PRS1', {'validePar': 'Moi-même'})), 'champ_reserve');
    expect(code(await op(laMere, 'modifier', 'presences', 'F1-PRS1', {'validationEtat': 'valide', 'validePar': 'Surveillant Sigma', 'valideLe': '2031-03-10'})), isNull, reason: 'la mère applique le dépôt');
    expect(code(await op(fileul, 'modifier', 'presences', 'F1-PRS1', {'validationEtat': 'a_valider'})), 'validation_defaite');
    expect(code(await op(fileul, 'modifier', 'presences', 'F1-PRS1', {'etat': 'absent'})), 'presence_validee');
    expect(code(await op(fileul, 'modifier', 'presences', 'F1-PRS1', {'regularisations': <Object?>[{'par': 'X', 'motif': 'Oubli'}], 'etat': 'retard'})), isNull, reason: 'une régularisation tracée passe');
    // Congés et ordres de mission.
    expect(code(await op(fileul, 'creer', 'conges', 'F1-CG1', {'employeId': 'EA', 'statutConge': 'valide'})), 'validation_reservee');
    expect(code(await op(fileul, 'creer', 'conges', 'F1-CG1', {'employeId': 'EA', 'statutConge': 'en_attente', 'validationEtat': 'a_valider'})), isNull);
    expect(code(await op(fileul, 'modifier', 'conges', 'F1-CG1', {'statutConge': 'valide'})), 'validation_reservee');
    expect(code(await op(fileul, 'creer', 'missions', 'F1-OM1', {'agentId': 'EA', 'statutMission': 'validee'})), 'validation_reservee');
    // Vacations.
    expect(code(await op(fileul, 'creer', 'planning', 'F1-PLN1', {'employeId': 'EA', 'date': '2031-03-12', 'type': 'garde'})), 'validation_reservee', reason: 'sans état, une vacation compterait comme validée');
    expect(code(await op(fileul, 'creer', 'planning', 'F1-PLN1', {'employeId': 'EA', 'date': '2031-03-12', 'type': 'garde', 'validationEtat': 'validee'})), 'validation_reservee');
    expect(code(await op(fileul, 'creer', 'planning', 'F1-PLN1', {'employeId': 'EA', 'date': '2031-03-12', 'type': 'garde', 'validationEtat': 'a_valider'})), isNull);
    expect(code(await op(fileul, 'modifier', 'planning', 'F1-PLN1', {'type': 'permanence'})), isNull, reason: 'tant que la vacation attend, son auteur la corrige');
    expect(code(await op(fileul, 'modifier', 'planning', 'F1-PLN1', {'validationEtat': 'validee', 'validePar': 'Moi'})), isNotNull);
    expect(code(await op(laMere, 'modifier', 'planning', 'F1-PLN1', {'validationEtat': 'validee', 'statut': 'validee', 'validePar': 'Surveillant Sigma', 'valideLe': '2031-03-10'})), isNull);
    expect(code(await op(fileul, 'modifier', 'planning', 'F1-PLN1', {'date': '2031-03-13'})), 'vacation_validee');
    expect(code(await op(fileul, 'modifier', 'planning', 'F1-PLN1', {'validationEtat': 'a_valider'})), 'validation_defaite');
    expect(code(await op(fileul, 'modifier', 'planning', 'F1-PLN1', {'statut': 'archive'})), 'vacation_validee', reason: 'le retrait d’une vacation validée se dépose');
    expect(code(await op(fileul, 'modifier', 'planning', 'F1-PLN1', {'observation': 'Note libre'})), isNull, reason: 'une observation n’est pas le programme');
    // Propositions.
    expect(code(await op(fileul, 'creer', 'propositionsPlanning', 'F1-PPL0', {'etat': 'validee', 'employeId': 'EA'})), 'validation_reservee');
    expect(code(await op(fileul, 'creer', 'propositionsPlanning', 'F1-PPL1', {'etat': 'proposee', 'employeId': 'EA', 'type': 'ajout'})), isNull);
    expect(code(await op(fileul, 'modifier', 'propositionsPlanning', 'F1-PPL1', {'etat': 'validee'})), 'validation_reservee');
    expect(code(await op(fileul, 'modifier', 'propositionsPlanning', 'F1-PPL1', {'tranchePar': 'Moi'})), 'champ_reserve');
    expect(code(await op(laMere, 'modifier', 'propositionsPlanning', 'F1-PPL1', {'etat': 'validee', 'tranchePar': 'Surveillant Sigma'})), isNull);
    expect(code(await op(fileul, 'modifier', 'propositionsPlanning', 'F1-PPL1', {'etat': 'annulee'})), 'etat_regressif');
  });

  test('deux fileuls et la mère : la vacation posée sur l’un, la proposition validée sur l’autre, mère coupée puis rétablie ; aucun doublon, identifiants par poste, double affectation refusée', () async {
    final d = Directory.systemTemp.createTempSync('planning-pont');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere = await Mere.creer(ConfigMere(port: 19595, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes'));
    final liaison = _Liaison(mere);
    final f1 = poste(), f2 = poste(), mm = poste();
    final p1 = PontActivite(f1, _Transport(liaison, Appareil('F1', 'fileul')), etiquette: 'F1', reservesAuMere: true);
    final p2 = PontActivite(f2, _Transport(liaison, Appareil('F2', 'fileul')), etiquette: 'F2', reservesAuMere: true);
    final pm = PontActivite(mm, _Transport(liaison, Appareil('mere', 'mere')), etiquette: 'M');
    Future<void> tour() async {
      for (var i = 0; i < 3; i++) {
        for (final p in [p1, p2, pm]) {
          await p.cycle();
        }
      }
    }

    final s1 = ServiceValidationsDeposees.de(f1)..etiquette = 'F1';
    final s2 = ServiceValidationsDeposees.de(f2)..etiquette = 'F2';
    final sm = ServiceValidationsDeposees.de(mm)
      ..etiquette = 'M'
      ..exigerCompteInscrit = false;
    PlanningRhPoste surveillant(Magasin m, ServiceValidationsDeposees s) => PlanningRhPoste(m,
        auteur: () => 'Surveillant Sigma', role: 'surveillant', horloge: () => auj, deposer: s.deposeurPlanning(role: 'surveillant', acteur: 'Surveillant Sigma'));
    PlanningRhPoste agentA(Magasin m, ServiceValidationsDeposees s) =>
        PlanningRhPoste(m, auteur: () => 'Agent Alpha', role: 'infirmier', horloge: () => auj, deposer: s.deposeurPlanning(role: 'infirmier', acteur: 'Agent Alpha'));
    List<Fiche> valides(Magasin m) => [for (final v in m.collection('planning').actives) if (planningVacationValidee(v)) v];

    // 1. F1 : le surveillant POSE une vacation. Sur un fileul, c'est une validation : elle se dépose ; la vacation naît « à valider » et ne compte pas (RG-11).
    final pose = surveillant(f1, s1).poserVacation(employeId: 'EA', date: '2031-03-14', type: 'garde');
    expect(pose['ok'], isTrue, reason: '$pose');
    expect(pose['enAttenteMere'], isTrue);
    final v1 = f1.collection('planning').toutes.single;
    expect(v1['id'], startsWith('F1-PLN'), reason: 'identifiant préfixé par poste : jamais de collision hors ligne');
    expect(v1['validationEtat'], 'a_valider');
    expect(planningVacationValidee(v1), isFalse);
    expect(s1.depotPlanningEnAttente('planning', v1['id']), isNotNull, reason: '« transmise à la mère, en attente » : jamais « validée » sur un dépôt seul');
    await tour();
    for (final m in [mm, f2]) {
      final v = m.collection('planning').toutes.single;
      expect(v['id'], v1['id'], reason: 'même identifiant partout (aucun préfixe en plus)');
      expect(v['validationEtat'], 'a_valider');
    }
    expect(mm.collection(valCollectionDepots).toutes.single['genre'], valGenrePlanningRh);
    // RG-11 / E4027 : tant que la mère n'a pas appliqué, la vacation « à valider » n'est PAYÉE sur aucun poste (ni prime de garde) — et le bulletin le dit.
    final agentEA = <String, Object?>{'id': 'EA', 'matricule': 'EA', 'nomComplet': 'Agent Alpha', 'fonction': 'infirmier', 'salaireBase': 100000, 'dateEmbauche': '2020-01-01'};
    PaiCalcul paie(Magasin m) => paiCalculer(agentEA, 2031, 2, entreesPaie(m), DateTime(2031, 3, 31));
    for (final m in [f1, f2, mm]) {
      expect(paie(m).gardes, 0, reason: 'à valider : aucune garde comptée');
      expect(paie(m).avertissementVacations, '1 vacation(s) en attente de validation ne sont pas payées');
    }
    // La mère applique sous le rôle du surveillant, contrôles refaits.
    expect(sm.traiter(), 1);
    expect(planningVacationValidee(mm.collection('planning').parId(v1['id'])!), isTrue);
    expect(mm.collection('planning').parId(v1['id'])!['validePar'], 'Surveillant Sigma');
    await tour();
    for (final m in [f1, f2, mm]) {
      expect(valides(m).map((v) => v['id']), [v1['id']], reason: 'la validation de la mère revient aux deux fileuls');
    }
    for (final m in [f1, f2, mm]) {
      expect(paie(m).gardes, 1, reason: 'validée par la mère : payable au calcul suivant, sur chaque poste');
      expect(paie(m).avertissementVacations, isNull);
    }
    expect(s1.depotPlanningEnAttente('planning', v1['id']), isNull);
    expect(f1.collection(valCollectionDepots).toutes.single['etat'], valDepotAppliquee);
    expect(sm.traiter(), 0, reason: 'un dépôt traité n’est jamais rejoué');

    // 2. F1 : l'agent PROPOSE (un ajout) ; F2 : le surveillant valide. Il ne valide pas lui-même : il dépose, la mère applique.
    final prop = agentA(f1, s1).proposer(type: 'ajout', date: '2031-03-17', typeVacation: 'permanence', motif: 'Remplacement convenu');
    expect(prop['ok'], isTrue, reason: '$prop');
    expect(prop['direct'], isFalse);
    await tour();
    final pid = f2.collection('propositionsPlanning').toutes.single['id'];
    expect(pid, startsWith('F1-PPL'));
    final tr = surveillant(f2, s2).trancherProposition(pid, 'valider');
    expect(tr['ok'], isTrue, reason: '$tr');
    expect(tr['enAttenteMere'], isTrue);
    expect(f2.collection('propositionsPlanning').parId(pid)!['etat'], 'proposee', reason: 'rien n’est écrit tant que la mère n’a pas appliqué');
    expect(f2.collection('planning').actives, hasLength(1), reason: 'la vacation de la proposition n’existe pas encore');
    await tour();
    expect(sm.traiter(), 1);
    await tour();
    for (final m in [f1, f2, mm]) {
      expect(m.collection('propositionsPlanning').parId(pid)!['etat'], 'validee');
      expect(valides(m).map((v) => v['date']).toList()..sort(), ['2031-03-14', '2031-03-17'], reason: 'une seule vacation de plus, partout');
    }
    expect({for (final m in [f1, f2, mm]) (valides(m).map((v) => '${v['id']}').toList()..sort()).join(',')}, hasLength(1), reason: 'les trois postes lisent les mêmes identifiants');

    // 3. La mère est COUPÉE. F2 et F1 posent chacun, hors ligne, une vacation pour le même agent le même jour.
    liaison.coupee = true;
    expect(surveillant(f2, s2).poserVacation(employeId: 'EB', date: '2031-03-20', type: 'garde')['ok'], isTrue);
    expect(surveillant(f1, s1).poserVacation(employeId: 'EB', date: '2031-03-20', type: 'garde')['ok'], isTrue);
    await tour();
    expect(p1.erreur.value, isNotNull, reason: 'mère coupée : le poste le dit, il continue de travailler');
    expect(f1.collection('planning').actives.where((v) => v['employeId'] == 'EB').single['validationEtat'], 'a_valider');
    // Mère rétablie : aucun doublon ; la première appliquée gagne, la seconde est REFUSÉE en nommant la double affectation et archivée.
    liaison.coupee = false;
    await tour();
    await tour();
    expect(mm.collection(valCollectionDepots).actives.where((x) => x['etat'] == valDepotDeposee), hasLength(2));
    expect(sm.traiter(), 2);
    await tour();
    for (final m in [f1, f2, mm]) {
      final eb = valides(m).where((v) => v['employeId'] == 'EB').toList();
      expect(eb, hasLength(1), reason: 'une seule vacation validée pour cet agent ce jour-là, sur chaque poste');
      expect(m.collection('planning').archivees.where((v) => v['employeId'] == 'EB'), hasLength(1), reason: 'la perdante est archivée (RG-14), jamais effacée');
    }
    final verdicts = [for (final x in mm.collection(valCollectionDepots).toutes) if (x['collection'] == 'planning' && x['cible'].toString().isNotEmpty && x['etat'] != valDepotAppliquee) x];
    expect(verdicts.single['etat'], valDepotRefusee);
    expect(verdicts.single['resultatCode'], 'DOUBLE_AFFECTATION');
    // Le verdict revient au fileul qui a perdu, avec son motif.
    final perdant = [for (final m in [f1, f2]) for (final x in m.collection(valCollectionDepots).toutes) if (x['resultatCode'] == 'DOUBLE_AFFECTATION') x];
    expect(perdant, hasLength(2), reason: 'le même dépôt, lu par les deux fileuls');
    // Plus aucun dépôt ne reste à traiter, aucune fiche refusée par la mère.
    expect(sm.traiter(), 0);
    for (final p in [p1, p2, pm]) {
      expect(p.motifsRefus, isEmpty, reason: 'la mère n’a refusé aucune écriture légitime : ${p.motifsRefus}');
    }

    // 4. Les présences (pointage) arrivent à la mère : refusées `collection_inconnue` avant ce lot.
    f2.collection('presences').inserer({'statut': 'actif', 'employeId': 'EA', 'date': '2031-03-21', 'etat': 'present', 'validationEtat': 'a_valider', 'etapesFaites': <Object?>[]}, prefixe: 'PRS');
    await tour();
    expect(mm.collection('presences').toutes.single['id'], startsWith('F2-PRS'));
    expect(f1.collection('presences').toutes.single['id'], startsWith('F2-PRS'));
    expect(p2.motifsRefus, isEmpty);
    // Le surveillant de F1 valide ce pointage : dépôt, application par la mère, retour.
    final tp = surveillant(f1, s1).trancher('presences', f1.collection('presences').toutes.single['id'], 'valider');
    expect(tp['ok'], isTrue, reason: '$tp');
    expect(tp['enAttenteMere'], isTrue);
    expect(f1.collection('presences').toutes.single['validationEtat'], 'a_valider');
    await tour();
    expect(sm.traiter(), 1);
    await tour();
    for (final m in [f1, f2, mm]) {
      final pr = m.collection('presences').toutes.single;
      expect([pr['validationEtat'], pr['validePar']], ['valide', 'Surveillant Sigma']);
    }
    // Rejeu : tourner encore ne change rien (aucun doublon de fiche, aucun nouveau dépôt).
    final avant = [f1, f2, mm].map((m) => [m.collection('planning').toutes.length, m.collection('presences').toutes.length, m.collection(valCollectionDepots).toutes.length]).toList();
    await tour();
    await tour();
    expect([f1, f2, mm].map((m) => [m.collection('planning').toutes.length, m.collection('presences').toutes.length, m.collection(valCollectionDepots).toutes.length]).toList(), avant);

    // 5. Un téléphone n'en reçoit rien (la mère exclut ces cinq collections de son pull `mobile`) : sondé par le banc Node et ici par la constante lue au chemin de lecture.
    expect(collectionsPlanningJamaisMobile, containsAll(['planning', 'propositionsPlanning', 'conges', 'missions', 'presences']));
  });

  test('un refus de compte revient au fileul et ne laisse pas de vacation en attente orpheline ; un rôle sans le geste est refusé, nommé, à blanc', () async {
    final m = poste();
    final sm = ServiceValidationsDeposees.de(m)..etiquette = 'M';
    // Un agent sans le geste de l'encadrement : refus nommé dès le poste, rien de déposé.
    final pf = PlanningRhPoste(m, auteur: () => 'Agent Alpha', role: 'infirmier', horloge: () => auj, deposer: sm.deposeurPlanning(role: 'infirmier', acteur: 'Agent Alpha'));
    final r = pf.poserVacation(employeId: 'EA', date: '2031-03-14', type: 'garde');
    expect(r['code'], 'PLANNING_RESERVE');
    expect(m.collection(valCollectionDepots).toutes, isEmpty);
    expect(m.collection('planning').toutes, isEmpty);
    // Le surveillant dépose ; la mère exige un compte inscrit (aucun compte ici) : refus nommé, la vacation en attente est archivée.
    final ps = PlanningRhPoste(m, auteur: () => 'Surveillant Sigma', role: 'surveillant', horloge: () => auj, deposer: sm.deposeurPlanning(role: 'surveillant', acteur: 'Surveillant Sigma'));
    final p = ps.poserVacation(employeId: 'EA', date: '2031-03-14', type: 'garde');
    expect(p['ok'], isTrue);
    expect(sm.traiter(), 1);
    final dep = m.collection(valCollectionDepots).toutes.single;
    expect(dep['etat'], valDepotRefusee);
    expect(m.collection('planning').toutes.single['statut'], 'archive');
    // Un dépôt identique n'est pas doublé tant qu'il attend.
    final ps2 = PlanningRhPoste(m, auteur: () => 'Surveillant Sigma', role: 'surveillant', horloge: () => auj, deposer: sm.deposeurPlanning(role: 'surveillant', acteur: 'Surveillant Sigma'));
    final q = ps2.poserVacation(employeId: 'EB', date: '2031-03-15', type: 'garde');
    final id = q['id'];
    final again = ps2.poserVacation(employeId: 'EB', date: '2031-03-15', type: 'garde', existantId: id);
    expect(again['ok'], isTrue);
    expect(m.collection(valCollectionDepots).toutes.where((x) => x['etat'] == valDepotDeposee), hasLength(1));
  });
  test('le Surveillant écrit le planning individuel d\u2019un agent depuis un poste rattaché : la version du régime s\u2019écrit, mais la vacation reste dans le circuit « à valider » (déposée, jamais validée par le fileul) ; l\u2019agent sans le geste est refusé', () {
    final m = poste();
    final sm = ServiceValidationsDeposees.de(m)..etiquette = 'F1';
    PlanningRhPoste en(String role, String nom) => PlanningRhPoste(m, auteur: () => nom, role: role, horloge: () => auj, deposer: sm.deposeurPlanning(role: role, acteur: nom));
    final refus = en('infirmier', 'Agent Alpha').poserRegime(employeId: 'EA', dateEffet: '2031-03-20', mode: 'derogation', champs: {'repos': 'repos24'}, motif: 'Sonde');
    expect(refus['code'], 'DEROGATION_RESERVEE', reason: 'sans le geste dédié, un agent n\u2019écrit pas le planning individuel');
    expect(m.collection('regimesIndividuels').toutes, isEmpty);
    final s = en('surveillant', 'Surveillant Sigma');
    final r = s.poserRegime(employeId: 'EA', dateEffet: '2031-03-20', mode: 'derogation', champs: {'repos': 'repos24'}, motif: 'Sonde');
    expect(r['ok'], isTrue, reason: '$r');
    expect(m.collection('regimesIndividuels').toutes.single['creePar'], 'Surveillant Sigma');
    final v = s.poserVacation(employeId: 'EA', date: '2031-03-21', type: 'garde');
    expect(v['ok'], isTrue, reason: '$v');
    final att = m.collection('planning').toutes.single;
    expect(planningVacationValidee(att), isFalse, reason: 'posée depuis un poste rattaché : la vacation attend la mère');
    expect(att['validationEtat'], 'a_valider');
    expect(m.collection(valCollectionDepots).toutes.where((x) => x['etat'] == valDepotDeposee), hasLength(1));
  });
}
