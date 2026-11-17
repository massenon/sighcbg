// LA FAMILLE C DE L'INVENTAIRE DES VALEURS EN DUR (bornes cliniques et seuils numériques ; consigne de la Direction du 18/11/2026 : « plus de valeur en dur »).
// On prouve, pour chaque site converti : (1) la valeur d'ATTENTE est le comportement d'avant, mot pour mot ; (2) un changement de RÉGLAGE change le comportement ; (3) une valeur hors
// bornes ou une paire incohérente retombe sur l'attente, jamais sur zéro ; (4) le téléphone ne reçoit que la liste blanche.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> version(String cle, Object? valeur, {String effet = '2026-01-01', int v = 1}) {
  final d = definitionDeParametre(cle)!;
  return Parametre(cle: cle, famille: d.famille, type: d.type, valeur: valeur, defaut: d.defaut, dateEffet: effet, version: v, auteur: 'Test', motif: 'essai', creeLe: '2026-11-18T08:00:00.000', mobile: d.mobile)
      .toJson();
}

void main() {
  final maintenant = DateTime(2026, 11, 18, 10);
  Map<String, String> s(Map<String, String> m) => m;

  group('téléphone : les bornes de plausibilité sont des réglages de la liste blanche', () {
    test('la liste blanche : 37 réglages numériques bornés, famille « mobile », chacun avec une source à valider', () {
      expect(mobBornesDefs.length, 18);
      final cles = {for (final d in mobBornesDefs) ...{d.cleMin, d.cleMax}, mobCleAgeMax};
      expect(cles.length, 37, reason: '18 champs × (min, max) + l\'âge maximal, sans doublon');
      for (final k in cles) {
        final d = definitionDeParametre(k);
        expect(d, isNotNull, reason: k);
        expect(d!.mobile, isTrue, reason: k);
        expect(d.famille, mobFamilleBornes, reason: k);
        expect(d.source, isNotNull, reason: k);
        expect(libellesFamillesParametres.containsKey(d.famille), isTrue);
      }
    });

    test('SANS réglage reçu : les bornes d\'avant, au chiffre près, et les messages d\'avant', () {
      const avant = {
        'constantes': {'temperature': (30, 45), 'sys': (50, 260), 'dia': (30, 160), 'pouls': (20, 250), 'fr': (5, 80), 'spo2': (50, 100), 'poids': (0.5, 300)},
        'prescription': {'duree': (1, 90)},
        'cpn': {'sa': (4, 45), 'poids': (30, 200), 'sys': (60, 260), 'dia': (30, 160), 'bcf': (60, 220)},
        'cpon': {'t': (34, 43), 'pb': (1000, 6000)},
        'surveillance': {'mpouls': (30, 220), 'bfr': (10, 100), 'bt': (34, 41)},
      };
      for (final e in avant.entries) {
        for (final c in e.value.entries) {
          final i = MobBornes.attente.intervalle(e.key, c.key);
          expect((i.min, i.max), (c.value.$1, c.value.$2), reason: '${e.key}.${c.key}');
        }
      }
      expect(MobBornes.attente.ageMaxAns, 120);
      final e = mobErreursConstantes(s({'temperature': '57'}));
      expect(e['temperature'], 'La température : valeur improbable (30 à 45).');
      expect(mobErreursCpn(s({'sa': '50', 'poids': '60', 'sys': '120', 'dia': '80'}))['sa'], 'Le terme : valeur improbable (4 à 45).');
      expect(mobErreursCpon(s({'ta': '12/8', 't': '37', 'pb': '9000'}))['pb'], 'Le poids du bébé : valeur improbable (1000 à 6000).');
      expect(mobErreursSurveillance(s({'bt': '45'}))['bt'], 'La T° du bébé : valeur improbable (34 à 41).');
    });

    test('un RÉGLAGE change le comportement : 46 °C devient acceptable, et le message dit la nouvelle borne', () {
      final b = MobBornes.depuisFiches([version('mobile.saisie.constantes.temperatureMax', 47)], '2026-06-01');
      expect(mobErreursConstantes(s({'temperature': '46'}), bornes: b), isEmpty);
      expect(mobErreursConstantes(s({'temperature': '46'})), isNotEmpty, reason: 'sans réglage, 46 °C reste improbable');
      expect(mobErreursConstantes(s({'temperature': '48'}), bornes: b)['temperature'], 'La température : valeur improbable (30 à 47).');
      // la même fiche, mais datée du lendemain : pas encore en vigueur
      final futur = MobBornes.depuisFiches([version('mobile.saisie.constantes.temperatureMax', 47, effet: '2026-12-01')], '2026-06-01');
      expect(mobErreursConstantes(s({'temperature': '46'}), bornes: futur), isNotEmpty);
    });

    test('la pièce émise suit le réglage : le moteur refuse ou accepte selon les bornes en vigueur', () {
      final patient = {'code': 'CBG/12/26', 'nom': 'DULOUNE', 'prenom': 'Aline'};
      final b = MobBornes.depuisFiches([version('mobile.saisie.constantes.poidsMax', 150)], '2026-06-01');
      expect(() => mobChampsConstantes(patient: patient, patientId: 'p', saisie: s({'temperature': '37', 'poids': '200'}), acteur: 'X', maintenant: maintenant, bornes: b), throwsA(isA<RefusMobile>()));
      expect(mobChampsConstantes(patient: patient, patientId: 'p', saisie: s({'temperature': '37', 'poids': '200'}), acteur: 'X', maintenant: maintenant)['poids'], 200);
    });

    test('hors enveloppe, illisible, ou paire inversée : les DEUX bornes reviennent à l\'attente ; l\'enveloppe protège le contrôle', () {
      MobBornes avec(Map<String, Object?> m) => MobBornes.depuisFiches([for (final e in m.entries) version(e.key, e.value)], '2026-06-01');
      // plafond de l'enveloppe de la température : 50 ; 99 est refusé à la lecture
      expect(avec({'mobile.saisie.constantes.temperatureMax': 99}).intervalle('constantes', 'temperature'), (min: 30, max: 45));
      // texte illisible
      expect(avec({'mobile.saisie.constantes.temperatureMax': 'beaucoup'}).intervalle('constantes', 'temperature'), (min: 30, max: 45));
      // paire inversée (min 40 >= max 45 d'attente → min 46 > max 45) : retombe ensemble
      expect(avec({'mobile.saisie.constantes.temperatureMin': 46}).intervalle('constantes', 'temperature'), (min: 30, max: 45));
      // paire cohérente
      expect(avec({'mobile.saisie.constantes.temperatureMin': 34, 'mobile.saisie.constantes.temperatureMax': 42}).intervalle('constantes', 'temperature'), (min: 34, max: 42));
      // l'âge maximal : borné de 100 à 150
      expect(avec({mobCleAgeMax: 110}).ageMaxAns, 110);
      expect(avec({mobCleAgeMax: 999}).ageMaxAns, 120);
      expect(avec({mobCleAgeMax: 5}).ageMaxAns, 120);
    });

    test('une version archivée ne s\'applique pas (RG-14) ; une version datée plus récente remplace la précédente', () {
      final archive = {...version('mobile.saisie.reception.ageDeclareMaxAns', 140), 'statut': 'archive'};
      expect(MobBornes.depuisFiches([archive], '2026-06-01').ageMaxAns, 120);
      final v1 = version(mobCleAgeMax, 130, effet: '2026-01-01');
      final v2 = version(mobCleAgeMax, 110, effet: '2026-05-01', v: 2);
      expect(MobBornes.depuisFiches([v1, v2], '2026-06-01').ageMaxAns, 110);
      expect(MobBornes.depuisFiches([v1, v2], '2026-03-01').ageMaxAns, 130);
    });

    test('la prescription : la durée suit le réglage', () {
      final b = MobBornes.depuisFiches([version('mobile.saisie.prescription.dureeMax', 120)], '2026-06-01');
      final saisie = s({'med': 'x', 'poso': '1/j', 'duree': '100'});
      expect(mobValider(mobReglesPrescriptionA(), saisie)['duree'], 'La durée : valeur improbable (1 à 90).');
      expect(mobValider(mobReglesPrescriptionA(b), saisie), isEmpty);
    });
  });

  group('certificat de grossesse : le terme maximal est un réglage', () {
    test('attente 45 ; réglé à 50, un terme de 48 devient recevable ; hors bornes (80), l\'attente', () {
      expect(cfaErreurTerme('46', seuilSeme(cfaCleTermeMaxCertificat)), isNotNull);
      expect(seuilSeme(cfaCleTermeMaxCertificat), 45);
      final reglee = seuilEntierA([version(cfaCleTermeMaxCertificat, 50)], cfaCleTermeMaxCertificat, '2026-06-01');
      expect(cfaErreurTerme('48', reglee), isNull);
      expect(cfaErreurTerme('51', reglee), 'Le terme doit être compris entre 1 et 50 semaines d’aménorrhée.');
      expect(seuilEntierA([version(cfaCleTermeMaxCertificat, 80)], cfaCleTermeMaxCertificat, '2026-06-01'), 45);
      expect(cfaErreurTerme('0', 45), isNotNull, reason: 'la borne basse (1) est structurelle');
      expect(cfaErreurTerme('abc', 45), isNull, reason: 'la nature du champ est contrôlée ailleurs');
    });
  });

  group('imagerie : le délai d\'aberration est un réglage', () {
    PilFiche d(String id, String dh) => {'id': id, 'dateHeure': dh};
    PilFiche r(String id, String rendu) => {'statut': 'rendu', 'demandeImagerieId': id, 'renduLe': rendu, 'examenCode': 'X'};
    final demandes = [d('a', '2026-01-01T08:00'), d('b', '2026-01-01T08:00')];
    // a : 10 jours ; b : 40 jours
    final crs = [r('a', '2026-01-11T08:00'), r('b', '2026-02-10T08:00')];
    String delai(PilVue v) => v.kpis.firstWhere((k) => k.libelle.startsWith('Délai moyen')).valeur;
    test('attente 30 jours : le délai de 40 jours est écarté ; réglé à 60 jours, il compte', () {
      expect(delai(pilStatsImagerie(demandes, crs)), '240 h');
      expect(delai(pilStatsImagerie(demandes, crs, delaiAberrationJours: 60)), '600 h');
      expect(seuilEntierA([version(pilCleDelaiAberrationImagerie, 60)], pilCleDelaiAberrationImagerie, '2026-06-01'), 60);
    });
  });

  group('mise à jour : la validité de l\'autorisation est un réglage', () {
    test('attente 4 heures ; bornes 1 à 72 ; le refus nomme la durée EN VIGUEUR', () {
      expect(majValiditeAutorisationHeures, 4);
      expect(majHeuresDefaut, 24);
      expect((majHeuresMin, majHeuresMax), (1, 168));
      final now = DateTime(2026, 11, 18, 12);
      final texte = majTexteAutorisation(maintenant: now, validiteHeures: 12, versionCourante: '0.1.0', schema: schemaDonneesCourant, levee: false, sauvegarde: now, export: now);
      expect(majLireAutorisation(texte, now.add(const Duration(hours: 13)), validiteHeures: 12)?.code, 'AUTORISATION_EXPIREE');
      expect(majLireAutorisation(texte, now.add(const Duration(hours: 13)), validiteHeures: 12)?.geste, contains('12 heures'));
      expect(seuilEntierA([version(cleMajValiditeAutorisationHeures, 12)], cleMajValiditeAutorisationHeures, '2026-06-01'), 12);
      expect(seuilEntierA([version(cleMajValiditeAutorisationHeures, 100)], cleMajValiditeAutorisationHeures, '2026-06-01'), 4);
    });
  });

  group('mère : fenêtre de réinitialisation et seuils de supervision', () {
    test('attente : 30 minutes, puis les seuils d\'avant ; réglée, la fenêtre suit (miroir de la règle appliquée par la mère)', () {
      expect(mrbDureeFenetreReinit, const Duration(minutes: 30));
      final t0 = DateTime(2026, 11, 18, 9);
      expect(mrbFenetreRestante(ouverteLe: t0, maintenant: t0.add(const Duration(minutes: 45))), Duration.zero);
      expect(mrbFenetreRestante(ouverteLe: t0, maintenant: t0.add(const Duration(minutes: 45)), duree: const Duration(minutes: 60)), const Duration(minutes: 15));
      final a = mereSeuilsSupervisionA(const [], '2026-06-01');
      expect((a.disqueAttentionOctets, a.disqueAlerteOctets), (10 << 30, 2 << 30));
      expect((a.sauvegardeAttentionHeures, a.sauvegardeAlerteHeures), (26, 50));
      expect((a.posteSilenceAttentionMin, a.posteSilenceAlerteMin, a.posteRetardOperations), (30, 240, 500));
      expect((a.relaisRetardAttention, a.relaisRetardAlerte, a.deriveHorlogeMin), (50, 2000, 2));
    });
    test('une paire dont l\'ordre est inversé retombe ENSEMBLE sur l\'attente ; une paire cohérente est appliquée', () {
      final ok = mereSeuilsSupervisionA([version(mereCleSauvegardeAttentionHeures, 40), version(mereCleSauvegardeAlerteHeures, 80)], '2026-06-01');
      expect((ok.sauvegardeAttentionHeures, ok.sauvegardeAlerteHeures), (40, 80));
      final inverse = mereSeuilsSupervisionA([version(mereCleSauvegardeAttentionHeures, 90)], '2026-06-01');
      expect((inverse.sauvegardeAttentionHeures, inverse.sauvegardeAlerteHeures), (26, 50));
      // le disque : l'attention se déclenche à un espace libre PLUS GRAND que l'alerte
      final disque = mereSeuilsSupervisionA([version(mereCleDisqueAttenteGo, 100), version(mereCleDisqueAlerteGo, 20)], '2026-06-01');
      expect((disque.disqueAttentionOctets, disque.disqueAlerteOctets), (100 << 30, 20 << 30));
      final disqueInverse = mereSeuilsSupervisionA([version(mereCleDisqueAlerteGo, 50)], '2026-06-01');
      expect((disqueInverse.disqueAttentionOctets, disqueInverse.disqueAlerteOctets), (10 << 30, 2 << 30));
    });
    test('chaque réglage de la mère est déclaré, borné, dans la famille « mere », vers aucun téléphone', () {
      for (final k in [
        mrbCleFenetreReinit, mereCleDelaiSauvegardeQuotidienne, mereCleAgeLimiteCopieMagasin, mereCleDisqueAttenteGo, mereCleDisqueAlerteGo, mereCleSauvegardeAttentionHeures,
        mereCleSauvegardeAlerteHeures, mereClePosteSilenceAttentionMin, mereClePosteSilenceAlerteMin, mereClePosteRetardOperations, mereCleRelaisRetardAttention, mereCleRelaisRetardAlerte,
        mereCleDeriveHorlogeMin, mereCleCyclesCopieFichiers, mereCleToleranceCopieFichiersMin,
      ]) {
        final d = definitionDeParametre(k);
        expect(d, isNotNull, reason: k);
        expect(d!.famille, 'mere', reason: k);
        expect(d.mobile, isFalse, reason: k);
        final v = d.defaut as int;
        expect(v >= d.min! && v <= d.max!, isTrue, reason: k);
      }
    });
  });

  group('balance âgée des assureurs : deux bornes réglables, les libellés suivent', () {
    test('déclarées 30 et 90, bornées ; indépendantes de celles des patients', () {
      for (final k in [cleBalanceAgeeAssureurBorne1, cleBalanceAgeeAssureurBorne2]) {
        final d = definitionDeParametre(k)!;
        expect(d.famille, 'assurances');
        expect(d.mobile, isFalse);
      }
      final a = bornesBalanceAgeeAssureurA([version(cleBalanceAgeeAssureurBorne1, 15), version(cleBalanceAgeeAssureurBorne2, 60)], '2026-06-01');
      expect((a.borne1, a.borne2), (15, 60));
      final p = bornesBalanceAgeePatientA([version(cleBalanceAgeeAssureurBorne1, 15), version(cleBalanceAgeeAssureurBorne2, 60)], '2026-06-01');
      expect((p.borne1, p.borne2), (30, 90), reason: 'régler les assureurs ne déplace pas les patients');
    });
  });
}
