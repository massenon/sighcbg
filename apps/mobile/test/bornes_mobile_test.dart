// LES BORNES DE SAISIE DU TÉLÉPHONE SONT DES RÉGLAGES (consigne du 18/11/2026 : « plus de valeur en dur »). La mère livre les versions de la LISTE BLANCHE ; le téléphone les relit à
// sa base à CHAQUE geste. Sans réglage reçu, la valeur d'attente (le comportement d'avant) ; un réglage reçu change le comportement ; archivé ou futur, il ne s'applique pas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_mobile/moteur/bornes_mobile.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';
import 'package:sigh_mobile/main.dart';

import 'aide_mobile.dart';
import 'aide_suite.dart';

LigneLot version(String cle, Object? valeur, {String effet = '2026-01-01', int v = 1, bool archive = false}) {
  final d = definitionDeParametre(cle)!;
  return LigneLot(
      '$cle@$effet@$v',
      Parametre(cle: cle, famille: d.famille, type: d.type, valeur: valeur, defaut: d.defaut, dateEffet: effet, version: v, auteur: 'Test', creeLe: '2026-11-18T08:00:00.000', mobile: true).toJson(),
      archive: archive);
}

void main() {
  group('relecture à la base du téléphone', () {
    test('aucun réglage reçu (collection vide) : les valeurs d\'attente', () async {
      final b = await bornesDe(SourceMemoire(), horloge);
      expect(b.estAttente, isTrue);
      expect(b.ageMaxAns, 120);
      expect(b.intervalle('constantes', 'temperature'), (min: 30, max: 45));
    });

    test('une source qui échoue ne désarme jamais le contrôle : valeurs d\'attente', () async {
      final b = await bornesDe(_Cassee(), horloge);
      expect(b.intervalle('constantes', 'temperature'), (min: 30, max: 45));
    });

    test('un réglage reçu change la borne ; archivé (RG-14) ou daté du futur, il ne s\'applique pas', () async {
      final recu = SourceMemoire({'parametres': [version('mobile.saisie.constantes.temperatureMax', 47)]});
      expect((await bornesDe(recu, horloge)).intervalle('constantes', 'temperature').max, 47);
      final archive = SourceMemoire({'parametres': [version('mobile.saisie.constantes.temperatureMax', 47, archive: true)]});
      expect((await bornesDe(archive, horloge)).intervalle('constantes', 'temperature').max, 45);
      final futur = SourceMemoire({'parametres': [version('mobile.saisie.constantes.temperatureMax', 47, effet: '2999-01-01')]});
      expect((await bornesDe(futur, horloge)).intervalle('constantes', 'temperature').max, 45);
    });
  });

  group('les gestes du téléphone suivent les bornes reçues', () {
    ServiceSoignant soignant(SourceMemoire s) => ServiceSoignant(s, session: const SessionSoignant(agent: 'Dr YORO M’ABEKPIA Foulumi', fonction: 'medecin'), maintenant: () => horloge);

    test('constantes : 46 °C est refusé sans réglage, accepté une fois la borne haute réglée à 47', () async {
      final sans = lotDeDemonstration();
      await expectLater(soignant(sans).enregistrerConstantes('p2', {'temperature': '46'}), throwsA(isA<RefusMobile>()));
      final avec = lotDeDemonstration()..donnees['parametres'] = [version('mobile.saisie.constantes.temperatureMax', 47)];
      await soignant(avec).enregistrerConstantes('p2', {'temperature': '46'});
      expect(avec.de('constantes').single['temperature'], 46);
      // le message du refus dit la borne EN VIGUEUR
      try {
        await soignant(avec).enregistrerConstantes('p2', {'temperature': '48'});
        fail('48 doit être refusé');
      } on RefusMobile catch (r) {
        expect(r.champs['temperature'], 'La température : valeur improbable (30 à 47).');
      }
    });

    test('CPN (suite du mobile) : le terme maximal réglé à 50 SA accepte 48', () async {
      ServiceSuite suite(SourceMemoire s) => ServiceSuite.depuisSoignant(ServiceSoignant(s, session: const SessionSoignant(agent: 'Sage-femme X', fonction: 'sage_femme'), maintenant: () => horloge));
      final saisie = {'sa': '48', 'poids': '60', 'sys': '120', 'dia': '80', 'hu': '30', 'bcf': '140'};
      final sans = lotSageFemme();
      await expectLater(suite(sans).enregistrerCpn('p4', saisie), throwsA(isA<RefusMobile>().having((r) => r.champs['sa'], 'terme', 'Le terme : valeur improbable (4 à 45).')));
      final avec = lotSageFemme()..donnees['parametres'] = [version('mobile.saisie.cpn.saMax', 50)];
      await suite(avec).enregistrerCpn('p4', saisie);
      expect(avec.de('cpn'), hasLength(1));
    });
  });

  testWidgets('réception de secours : l\'âge maximal déclaré est le RÉGLAGE reçu (110), le message le dit ; 115 refusé, 110 accepté', (t) async {
    final m = FauxMoteurSuite(source: accueilDeSecours()..donnees['parametres'] = [version(mobCleAgeMax, 110)])..profil = ProfilMobile.receptionSecours;
    await t.pumpWidget(SighMobile(moteur: m));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('nom')), 'AMITU');
    await t.enterText(find.byKey(const Key('prenom')), 'Mevour');
    await t.enterText(find.byKey(const Key('age')), '115');
    await t.tap(find.byKey(const Key('creer')));
    await t.pumpAndSettle();
    expect(find.text('L’âge déclaré est obligatoire (0 à 110 ans).'), findsOneWidget);
    expect(m.crees, isEmpty);
    await t.enterText(find.byKey(const Key('age')), '110');
    await t.tap(find.byKey(const Key('creer')));
    await t.pumpAndSettle();
    expect(m.crees, hasLength(1));
  });
}

class _Cassee extends SourceMemoire {
  @override
  Future<List<LigneLot>> liste(String collection) async => throw StateError('base illisible');
}
