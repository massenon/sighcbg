import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_validations_deposees.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;
import 'package:sigh_sync/sigh_sync.dart';
// ignore: implementation_imports
import 'package:sigh_sync/src/mere.dart' show Appareil;

/// LE PLAN DE TRAVAIL ANNUEL À TRAVERS LES POSTES (lot PTA, 17/11/2026) : les cinq collections du PTA voyagent (famille A à la mère Dart, au banc Node, au pont du poste) et jamais vers
/// un téléphone ; une action et un plan écrits chez un fileul arrivent à la mère et à l'autre fileul ; l'ADOPTION déposée par un fileul est appliquée par la mère sous le rôle de son
/// auteur et revient à tous les postes ; un dépôt d'un rôle sans le geste est refusé, nommé, et rien n'est adopté.
class _Journal {
  final Map<String, Map<String, Map<String, Object?>>> fiches = {};
}

class _Transport implements TransportPont {
  _Transport(this.j);
  final _Journal j;
  @override
  Future<void> restaurer(String collection, String fiche) async => throw StateError('non porté');
  @override
  Future<List<PieceSync>> liste(String c) async => [for (final e in (j.fiches[c] ?? {}).entries) PieceSync(e.key, jsonDecode(jsonEncode(e.value)) as Map<String, Object?>)];
  @override
  Future<void> ecrire(String c, String fiche, {required bool existe, required Map<String, Object?> champs}) async {
    final col = j.fiches.putIfAbsent(c, () => {});
    col[fiche] = {...?col[fiche], ...jsonDecode(jsonEncode(champs)) as Map<String, Object?>};
  }
}

void main() {
  final auj = DateTime(2031, 2, 10, 9);
  Magasin poste() => Magasin({for (final n in [...ptaCollections, valCollectionDepots, 'budgets', 'ecritures', 'notifications', 'rbac', 'utilisateurs']) n: <Map<String, Object?>>[]}, 'POSTE')
    ..horloge = () => auj;

  test('les cinq collections du PTA : famille A à la mère Dart et au banc Node, pont du poste ; jamais vers un téléphone', () {
    expect(collectionsActivite, containsAll(ptaCollections));
    final dart = File('../../packages/sync_dart/lib/src/mere.dart').readAsStringSync();
    expect(dart, contains("'planAnnuel': 'A', 'plansTravail': 'A', 'ptaAxes': 'A', 'ptaEtats': 'A', 'ptaFinancements': 'A'"));
    expect(dart, contains('...collectionsPlanTravailJamaisMobile'), reason: 'exclues au chemin de lecture du mobile');
    expect(dart, contains('refusPlanTravail('), reason: 'la mère refait le contrôle de l’adoption');
    expect(dart, contains('refusActionPta('), reason: 'la mère refait le contrôle du programme figé');
    final js = File('../../packages/sync/banc/mere.js').readAsStringSync();
    expect(js, contains("planAnnuel: 'A', plansTravail: 'A', ptaAxes: 'A', ptaEtats: 'A', ptaFinancements: 'A'"));
    final jamais = RegExp(r'const MOBILE_JAMAIS = \[([^\]]*)\]').firstMatch(js)!.group(1)!;
    for (final c in ptaCollections) {
      expect(jamais, contains("'$c'"));
    }
  });

  test('deux postes : le plan et l’action d’un fileul arrivent partout ; l’adoption DÉPOSÉE est appliquée par la mère sous le rôle de son auteur et revient au fileul', () async {
    final j = _Journal();
    final f1 = poste(), f2 = poste(), mm = poste();
    final p1 = PontActivite(f1, _Transport(j), etiquette: 'F1', reservesAuMere: true);
    final p2 = PontActivite(f2, _Transport(j), etiquette: 'F2', reservesAuMere: true);
    final pm = PontActivite(mm, _Transport(j), etiquette: 'M');
    Future<void> tour() async {
      for (var i = 0; i < 3; i++) {
        for (final p in [p1, p2, pm]) {
          await p.cycle();
        }
      }
    }

    // F1 rédige et soumet.
    final creation = ptaCreerPlan(annee: 2031, plans: const [], acteur: 'Rédacteur', maintenant: auj);
    f1.collection(ptaCollectionActions).inserer({
      'statut': 'actif', 'exercice': 2031, 'planVersion': 1, 'reference': 'PTA-2031-001', 'action': 'Former', 'axe': 'ressources_humaines_formation', 'etat': 'planifiee', //
      'cibleValeur': 10, 'calendrier': ['2031-01-01/2031-01-20'],
    }, prefixe: 'PTA');
    f1.collection(ptaCollectionPlans).inserer(creation.creation!);
    final plan1 = f1.collection(ptaCollectionPlans).toutes.single;
    final s = ptaSoumettre(plan1, f1.collection(ptaCollectionActions).toutes, acteur: 'Rédacteur', maintenant: auj);
    f1.collection(ptaCollectionPlans).mettreAJour(plan1['id'], s.ecritures.single.patch);
    await tour();
    for (final m in [mm, f2]) {
      expect(ptaPlanCourant(m.collection(ptaCollectionPlans).toutes, 2031)!['etat'], 'soumis');
      expect(ptaActionsDuPlan(m.collection(ptaCollectionActions).toutes, 2031, 1).single['reference'], 'PTA-2031-001');
    }

    // F2 : un caissier tente d'adopter → refus NOMMÉ dès le poste, rien de déposé.
    final sf2 = ServiceValidationsDeposees.de(f2)..etiquette = 'F2';
    final refus = sf2.deposerPta(ptaDecisionAdopter, 2031, 1, role: 'caissier', acteur: 'Caissier', motif: 'x');
    expect(refus.refus!.code, 'ADOPTION_RESERVEE');
    expect(f2.collection(valCollectionDepots).toutes, isEmpty);
    // F2 : la Direction dépose l'adoption.
    final d = sf2.deposerPta(ptaDecisionAdopter, 2031, 1, role: 'direction', acteur: 'Le Directeur', motif: 'Comité de direction');
    expect(d.ok, isTrue);
    expect(sf2.depotPtaEnAttente(2031, 1), isNotNull, reason: '« transmise à la mère, en attente » : jamais « adopté » sur un dépôt seul');
    expect(ptaPlanCourant(f2.collection(ptaCollectionPlans).toutes, 2031)!['etat'], 'soumis');
    await tour();
    final sm = ServiceValidationsDeposees.de(mm)
      ..etiquette = 'M'
      ..exigerCompteInscrit = false;
    expect(sm.traiter(), 1);
    final pm2031 = ptaPlanCourant(mm.collection(ptaCollectionPlans).toutes, 2031)!;
    expect([pm2031['etat'], pm2031['adoptePar'], pm2031['adopteRole']], ['adopte', 'Le Directeur', 'direction']);
    expect(mm.collection(valCollectionDepots).toutes.single['etat'], valDepotAppliquee);
    await tour();
    for (final m in [f1, f2]) {
      expect(ptaPlanCourant(m.collection(ptaCollectionPlans).toutes, 2031)!['etat'], 'adopte', reason: 'l’adoption de la mère revient aux deux fileuls');
    }
    expect(sf2.depotPtaEnAttente(2031, 1), isNull);
    // Le suivi saisi chez F1 après l'adoption voyage ; le programme, lui, est gardé au moteur.
    final a1 = ptaActionsDuPlan(f1.collection(ptaCollectionActions).toutes, 2031, 1).single;
    f1.collection(ptaCollectionActions).mettreAJour(a1['id'], {'realiseValeur': 4, 'etat': 'en_cours'});
    expect(() => f1.collection(ptaCollectionActions).mettreAJour(a1['id'], {'cibleValeur': 2}), throwsA(isA<EcritureRefusee>()));
    await tour();
    expect(ptaActionsDuPlan(mm.collection(ptaCollectionActions).toutes, 2031, 1).single['realiseValeur'], 4);
    // La clôture déposée par F2 : la mère calcule le BILAN sur SES données (une action, aucune réalisée, en retard au seuil d'attente de 15 jours).
    final pf1 = ptaPlanCourant(f1.collection(ptaCollectionPlans).toutes, 2031)!;
    f1.collection(ptaCollectionPlans).mettreAJour(pf1['id'], ptaMettreEnExecution(pf1, acteur: 'Rédacteur', maintenant: auj).ecritures.single.patch);
    await tour();
    expect(sf2.deposerPta(ptaDecisionCloturer, 2031, 1, role: 'da', acteur: 'La DAF', motif: 'Bilan de fin d’exercice').ok, isTrue);
    await tour();
    expect(sm.traiter(), 1);
    await tour();
    final clos = ptaPlanCourant(f2.collection(ptaCollectionPlans).toutes, 2031)!;
    expect(clos['etat'], 'cloture');
    final bilan = (clos['bilan'] as Map).cast<String, Object?>();
    expect([bilan['texte'], bilan['programmees'], bilan['realisees'], bilan['enRetard']], ['Bilan de fin d’exercice', 1, 0, 1]);
  });

  test('la VRAIE mère Dart refait le contrôle : adoption et champ réservés, recul refusé, programme figé, suivi ouvert', () async {
    final d = Directory.systemTemp.createTempSync('pta-mere');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere = await Mere.creer(ConfigMere(port: 19593, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes'));
    final fileul = Appareil('F1', 'fileul'), laMere = Appareil('mere', 'mere');
    var n = 0;
    // Chaque écriture porte la VERSION VUE de ses champs (ce que le poste a lu de la mère) : sans elle, elle serait concurrente de la précédente.
    Future<Map<String, Object?>> op(Appareil a, String type, String c, String fiche, Map<String, Object?> champs) async {
      final f = await mere.lire(c, fiche);
      final vu = <String, Object?>{for (final k in champs.keys) if (f != null && f.fieldseq[k] != null) k: f.fieldseq[k]};
      return mere.traiter({'id': 'op${n++}', 'type': type, 'collection': c, 'fiche': fiche, 'champs': champs, 'hlc': 1000 + n, 'vu': vu}, a);
    }
    String? code(Map<String, Object?> r) => r['statut'] == 'refusee' ? '${r['code']}' : null;
    expect(code(await op(fileul, 'creer', ptaCollectionPlans, 'P1', {'exercice': 2031, 'version': 1, 'etat': 'adopte'})), 'adoption_requise');
    expect(code(await op(fileul, 'creer', ptaCollectionPlans, 'P1', {'exercice': 2031, 'version': 1, 'etat': 'soumis'})), isNull);
    expect(code(await op(fileul, 'creer', ptaCollectionActions, 'A1', {'exercice': 2031, 'planVersion': 1, 'reference': 'PTA-2031-001', 'cibleValeur': 10})), isNull);
    expect(code(await op(fileul, 'modifier', ptaCollectionPlans, 'P1', {'etat': 'adopte'})), 'adoption_reservee');
    expect(code(await op(fileul, 'modifier', ptaCollectionPlans, 'P1', {'adoptePar': 'Moi'})), 'champ_reserve');
    expect(code(await op(laMere, 'modifier', ptaCollectionPlans, 'P1', {'etat': 'adopte', 'adoptePar': 'Le Directeur'})), isNull, reason: 'la mère applique le dépôt');
    expect(code(await op(fileul, 'modifier', ptaCollectionPlans, 'P1', {'etat': 'brouillon'})), 'etat_regressif');
    expect(code(await op(fileul, 'modifier', ptaCollectionActions, 'A1', {'cibleValeur': 3})), 'plan_adopte');
    expect(code(await op(fileul, 'creer', ptaCollectionActions, 'A2', {'exercice': 2031, 'planVersion': 1, 'reference': 'PTA-2031-002'})), 'plan_adopte');
    expect(code(await op(fileul, 'modifier', ptaCollectionActions, 'A1', {'realiseValeur': 4})), isNull, reason: 'le suivi reste ouvert');
    expect(code(await op(fileul, 'modifier', ptaCollectionPlans, 'P1', {'etat': 'execution'})), isNull);
  });
}
