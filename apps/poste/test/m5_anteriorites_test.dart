import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m5/res_comparatif.dart';
import 'package:sigh_poste/modules/m5/res_resultats.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';

/// Lots A1 et A2 du laboratoire, ÉCRAN PAR ÉCRAN : le comparatif (trois antériorités rendues, variation, courbe, impression), le compte rendu du patient (colonne
/// « Antériorités », périmètre RBAC), les seuils de variation brutale (Valider présent ou absent selon la matrice, refus du moteur, alerte qui ne bloque pas).
/// Les règles pures sont rejouées par `packages/domaine/test/res_anteriorites_test.dart`.
List<Fiche> liste(Object? v) => [for (final x in (v as List? ?? const [])) (x as Map).cast<String, Object?>()];

final auj = DateTime(2026, 11, 13, 12);

Magasin magasin(Map<String, List<Fiche>> surcharges) {
  const dossier = 'test/fixtures/jeu_sobre';
  final jeux = <String, Iterable<Fiche>>{
    for (final nom in Magasin.collectionsDuJeu) nom: liste(jsonDecode(File('$dossier/$nom.json').readAsStringSync())),
    ...surcharges,
  };
  return Magasin(jeux, 'POSTE', {...(jsonDecode(File('$dossier/referentiels.json').readAsStringSync()) as Map).cast<String, Object?>()});
}

/// La matrice du jeu livré : les droits du profil sur l'écran sont ceux que la matrice en force lui donne, jamais un rôle écrit dans le test.
Droit droitMatrice(String role, String ecran) {
  final d = (jsonDecode(File('assets/donnees/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
  final p = ((d['parRole'] as Map)[role] as Map?)?[ecran] as List?;
  if (p == null) return const Droit(voir: false, editer: false, annuler: false);
  return Droit(voir: p[0] == 1, editer: p[1] == 1, annuler: p[2] == 1);
}

Future<void> monter(WidgetTester t, Magasin m, Widget ecran,
    {String role = 'laborantin', String utilisateur = 'Dr BIO', String ecranId = 'm5-test', Droit? droit}) async {
  t.view.physicalSize = const Size(2600, 2200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  m.utilisateur = utilisateur;
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ContexteEcran(
              ecranId: ecranId,
              role: role,
              droit: droit ?? const Droit(voir: true, editer: true, annuler: true),
              magasin: m,
              aller: (_) {},
              utilisateur: utilisateur,
              horloge: () => auj,
              child: SingleChildScrollView(child: ecran)))));
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> onglet(WidgetTester t, String id) => toucher(t, find.byKey(Key('kit:onglet:$id')));

Future<void> choisir(WidgetTester t, String nom, String cible) async {
  await toucher(t, find.descendant(of: find.byKey(Key('kit:champ:$nom')), matching: find.byType(InkWell)).first);
  if (find.text(cible).evaluate().isEmpty) {
    await t.enterText(find.byType(TextField).last, cible);
    await t.pump(const Duration(milliseconds: 200));
  }
  await toucher(t, find.text(cible).last);
  await t.pump(const Duration(milliseconds: 400));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

Fiche demande(String id, String date,
        {String etat = 'valide', Map<String, Object?>? valeurs, String patient = 'PXA', String secteur = 'MÉDECINE GÉNÉRALE', String? valideLe}) =>
    {
      'id': id,
      'statut': 'actif',
      'reference': 'LAB-${id.padLeft(5, '0')}',
      'codeAnalyse': '${id.padLeft(5, '0')}-2026',
      'patientId': patient,
      'patient': 'TEST $patient',
      'patientCode': 'CBG/9/26',
      'analyseCode': 'L24',
      'analyse': 'NFS COMPLETE (HEMOGRAMME)',
      'examenCode': 'NFS',
      'categorie': 'Hématologie',
      'echantillon': 'Sang',
      'dateHeure': '${date}T09:00:00.000Z',
      'prescripteur': 'Dr TEST Prescripteur',
      'laborantin': 'KELE Gedur',
      'etatAnalyse': etat,
      'origine': 'ordonnance',
      'secteurDemandeur': secteur,
      if (etat == 'valide' || etat == 'rectifie') ...{'valideLe': valideLe ?? '${date}T15:00:00.000Z', 'valideBiologiquePar': 'Dr BIO'},
      if (etat == 'valide_technique') 'valideTechniqueLe': '${date}T12:00:00.000Z',
      'valeurs': valeurs ?? {'GB': 5, 'HB': 12},
    };

String texteDe(WidgetTester t, Finder f) => t.widget<Text>(f).data ?? '';

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  group('E2511 : le compte rendu complet ne reprend que ce que le profil a le droit de lire', () {
    // Une sage-femme lit les résultats de SON secteur ; le résultat demandé par la médecine générale lui est interdit.
    final demandes = [
      demande('1', '2026-03-01', patient: 'PXS', secteur: 'MATERNITÉ', valeurs: {'GB': 5}),
      demande('2', '2026-04-01', patient: 'PXS', secteur: 'MÉDECINE GÉNÉRALE', valeurs: {'GB': 6.5}),
    ];
    cas('le compte rendu imprimé par une sage-femme ne porte pas le résultat d’un autre secteur', (t) async {
      final m = magasin({'demandesAnalyses': demandes, 'plagesReactif': const []});
      await monter(t, m, const EcranResultats(fonction: 'sage_femme', secteur: 'MAT'), role: 'infirmier', utilisateur: 'SF Test');
      await onglet(t, 'valides');
      expect(find.byKey(const Key('res:compte-rendu:LAB-00001')), findsOneWidget);
      expect(find.byKey(const Key('res:compte-rendu:LAB-00002')), findsNothing, reason: 'la ligne interdite n’est même pas listée');
      await toucher(t, find.byKey(const Key('res:compte-rendu:LAB-00001')));
      expect(find.textContaining('5 G/l'), findsWidgets, reason: 'le résultat de son secteur figure sur la fiche');
      expect(find.textContaining('6.5 G/l'), findsNothing, reason: 'le résultat de la médecine générale n’est pas pour elle');
    });
    cas('le biologiste, lui, voit tout : le compte rendu porte les deux', (t) async {
      final m = magasin({'demandesAnalyses': demandes, 'plagesReactif': const []});
      await monter(t, m, const EcranResultats(fonction: 'biologiste'), role: 'laborantin');
      await onglet(t, 'valides');
      await toucher(t, find.byKey(const Key('res:compte-rendu:LAB-00001')));
      expect(find.textContaining('6.5 G/l'), findsWidgets);
    });
  });
}
