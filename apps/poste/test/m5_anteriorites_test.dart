import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/donnees/seuils_poste.dart';
import 'package:sigh_poste/modules/cfg/cfb_systeme.dart';
import 'package:sigh_poste/modules/m5/cat_valeurs.dart';
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
        {String etat = 'valide',
        Map<String, Object?>? valeurs,
        String patient = 'PXA',
        String secteur = 'MÉDECINE GÉNÉRALE',
        String? valideLe,
        String examen = 'NFS',
        String analyse = 'NFS COMPLETE (HEMOGRAMME)'}) =>
    {
      'id': id,
      'statut': 'actif',
      'reference': 'LAB-${id.padLeft(5, '0')}',
      'codeAnalyse': '${id.padLeft(5, '0')}-2026',
      'patientId': patient,
      'patient': 'TEST $patient',
      'patientCode': 'CBG/9/26',
      'analyseCode': 'L24',
      'analyse': analyse,
      'examenCode': examen,
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

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // A1 : le comparatif
  // ---------------------------------------------------------------------------------------------------------------------------------------------
  group('A1 : le comparatif lit jusqu’à trois antériorités rendues', () {
    final d = [
      demande('11', '2026-01-10', valeurs: {'GB': 4.5, 'HB': 13}),
      demande('12', '2026-02-10', valeurs: {'GB': 5}),
      demande('13', '2026-03-10', valeurs: {'GB': 6}),
      demande('14', '2026-04-10', valeurs: {'GB': 7}),
      demande('15', '2026-05-10', valeurs: {'GB': 10, 'HB': 12}),
      demande('16', '2026-06-10', etat: 'saisi', valeurs: {'GB': 50}),
      demande('17', '2026-07-10', etat: 'valide_technique', valeurs: {'GB': 60}),
    ];
    Magasin jeu([List<Fiche> reglages = const []]) => magasin({'demandesAnalyses': d, 'plagesReactif': const [], 'reglages': reglages});
    Future<void> ouvrir(WidgetTester t, Magasin m, {String role = 'laborantin'}) async {
      await monter(t, m, const EcranComparatifResultats(fonction: 'biologiste'), role: role);
      await choisir(t, 'patient', 'TEST PXA (CBG/9/26) — 5 résultat(s)');
      await choisir(t, 'examen', 'NFS complète (hémogramme) (5 mesures)');
    }

    cas('trois antériorités par défaut, de la plus ancienne à la mesure comparée ; une saisie non validée n’y entre pas', (t) async {
      await ouvrir(t, jeu());
      for (final col in ['a0', 'a1', 'a2', 'b']) {
        expect(find.byKey(Key('res:cmp:cell:GB:$col')), findsOneWidget, reason: col);
      }
      expect(find.byKey(const Key('res:cmp:cell:GB:a3')), findsNothing);
      expect(texteDe(t, find.byKey(const Key('res:cmp:cell:GB:a0'))), '5 G/l');
      expect(texteDe(t, find.byKey(const Key('res:cmp:cell:GB:a1'))), '6 G/l');
      expect(texteDe(t, find.byKey(const Key('res:cmp:cell:GB:a2'))), '7 G/l');
      expect(texteDe(t, find.byKey(const Key('res:cmp:cell:GB:b'))), '10 G/l');
      expect(find.text('Mesure comparée'), findsWidgets);
      expect(find.text('Antériorité 1'), findsOneWidget);
      expect(find.text('Antériorité 3'), findsOneWidget);
      // La saisie du 10/06 et la validation technique du 10/07 ne sont ni proposées ni comparées.
      expect(find.textContaining('50 G/l'), findsNothing);
      expect(find.textContaining('60 G/l'), findsNothing);
    });

    cas('la variation se lit à la mesure précédente DE LA VARIABLE, en disant laquelle quand ce n’est pas la colonne voisine', (t) async {
      await ouvrir(t, jeu());
      expect(texteDe(t, find.byKey(const Key('res:cmp:variation:GB'))), '↑ +3 G/l (+42.9 %)');
      // HB : mesurée le 10/01 et le 10/05 seulement : la précédente est hors des trois colonnes.
      expect(texteDe(t, find.byKey(const Key('res:cmp:variation:HB'))), '↓ -1 g/dl (-7.7 %)');
      expect(find.text('à la mesure du 10/01/2026'), findsOneWidget);
    });

    cas('le réglage en base change le nombre d’antériorités (reglages.nbAnterioritesLabo)', (t) async {
      await ouvrir(t, jeu([
        {'id': 'nbAnterioritesLabo', 'statut': 'actif', 'valeur': 2}
      ]));
      expect(find.byKey(const Key('res:cmp:cell:GB:a0')), findsOneWidget);
      expect(find.byKey(const Key('res:cmp:cell:GB:a1')), findsOneWidget);
      expect(find.byKey(const Key('res:cmp:cell:GB:a2')), findsNothing);
      expect(texteDe(t, find.byKey(const Key('res:cmp:cell:GB:a0'))), '6 G/l');
    });

    cas('la mesure comparée se choisit : ses antériorités s’en déduisent', (t) async {
      await ouvrir(t, jeu());
      await choisir(t, 'b', '10/03/2026 — 00013-2026');
      expect(find.byKey(const Key('res:cmp:cell:GB:a0')), findsOneWidget);
      expect(find.byKey(const Key('res:cmp:cell:GB:a1')), findsOneWidget);
      expect(find.byKey(const Key('res:cmp:cell:GB:a2')), findsNothing);
      expect(texteDe(t, find.byKey(const Key('res:cmp:cell:GB:b'))), '6 G/l');
      expect(texteDe(t, find.byKey(const Key('res:cmp:variation:GB'))), '↑ +1 G/l (+20.0 %)');
      await choisir(t, 'b', '10/01/2026 — 00011-2026');
      expect(find.text('Cette mesure est la plus ancienne rendue : aucune antériorité. Choisir une mesure plus récente.'), findsOneWidget);
    });

    cas('la courbe de tendance s’ouvre au clic sur un paramètre numérique et porte TOUTES les mesures rendues', (t) async {
      await ouvrir(t, jeu());
      await toucher(t, find.byKey(const Key('res:tendance:GB')));
      expect(find.textContaining('Tendance : '), findsOneWidget);
      expect(find.byKey(const Key('res:tendance:courbe:GB')), findsOneWidget);
      final tableau = find.byKey(const Key('res:tendance:valeurs:GB'));
      for (final x in ['4.5 G/l', '5 G/l', '6 G/l', '7 G/l', '10 G/l']) {
        expect(find.descendant(of: tableau, matching: find.text(x)), findsOneWidget, reason: x);
      }
      expect(find.descendant(of: tableau, matching: find.textContaining('50 G/l')), findsNothing);
      expect(find.text('5 mesure(s) rendue(s)'), findsOneWidget);
    });

    cas('une variable qualitative se compare en texte, sans pourcentage ni courbe', (t) async {
      final crp = [
        demande('21', '2026-01-10', patient: 'PXC', examen: 'CRP', analyse: 'PROTEINE C-REACTIVE (CRP)', valeurs: {'CRPQ': 'Négatif', 'CRPT': 3}),
        demande('22', '2026-02-10', patient: 'PXC', examen: 'CRP', analyse: 'PROTEINE C-REACTIVE (CRP)', valeurs: {'CRPQ': 'Positif', 'CRPT': 0}),
        demande('23', '2026-03-10', patient: 'PXC', examen: 'CRP', analyse: 'PROTEINE C-REACTIVE (CRP)', valeurs: {'CRPQ': 'Positif', 'CRPT': 12}),
      ];
      await monter(t, magasin({'demandesAnalyses': crp, 'plagesReactif': const []}), const EcranComparatifResultats(fonction: 'biologiste'));
      await choisir(t, 'patient', 'TEST PXC (CBG/9/26) — 3 résultat(s)');
      await choisir(t, 'examen', 'Protéine C-réactive (CRP) (3 mesures)');
      expect(texteDe(t, find.byKey(const Key('res:cmp:variation:CRPQ'))), 'Inchangé (Positif)');
      expect(find.byKey(const Key('res:tendance:CRPQ')), findsNothing, reason: 'pas de courbe pour une valeur qualitative');
      // Valeur précédente nulle : le pourcentage ne se calcule pas, et l'écran le dit.
      expect(texteDe(t, find.byKey(const Key('res:cmp:variation:CRPT'))), '↑ +12 mg/l (écart relatif non calculable : valeur précédente nulle)');
    });

    cas('le périmètre RBAC métier s’applique aux antériorités : jamais une antériorité qu’on n’a pas le droit de voir', (t) async {
      final sf = [
        demande('31', '2026-01-10', patient: 'PXS', secteur: 'MATERNITÉ', valeurs: {'GB': 5}),
        demande('32', '2026-02-10', patient: 'PXS', secteur: 'MÉDECINE GÉNÉRALE', valeurs: {'GB': 99}),
        demande('33', '2026-03-10', patient: 'PXS', secteur: 'MATERNITÉ', valeurs: {'GB': 6}),
      ];
      await monter(t, magasin({'demandesAnalyses': sf, 'plagesReactif': const []}), const EcranComparatifResultats(fonction: 'sage_femme', secteur: 'MAT'),
          role: 'infirmier', utilisateur: 'SF Test');
      await choisir(t, 'patient', 'TEST PXS (CBG/9/26) — 2 résultat(s)');
      await choisir(t, 'examen', 'NFS complète (hémogramme) (2 mesures)');
      expect(find.textContaining('1 mesure(s) rendue(s) de cet examen sont hors de votre périmètre'), findsOneWidget);
      expect(find.textContaining('99 G/l'), findsNothing);
      expect(texteDe(t, find.byKey(const Key('res:cmp:cell:GB:a0'))), '5 G/l');
      expect(find.byKey(const Key('res:cmp:cell:GB:a1')), findsNothing);
    });

    cas('imprimer le comparatif : la pièce porte les colonnes et dit ce qu’elle ne reprend pas', (t) async {
      await ouvrir(t, jeu());
      await toucher(t, find.byKey(const Key('res:cmp:imprimer')));
      expect(find.textContaining('Seules les mesures rendues (validées biologiquement) et lisibles par le profil qui édite'), findsOneWidget);
      expect(find.text('Variation à la mesure précédente'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // A1 : la colonne « Antériorités » de la fiche imprimée
  // ---------------------------------------------------------------------------------------------------------------------------------------------
  group('A1 : la fiche de résultats imprimée remplit sa colonne Antériorités', () {
    final d = [
      demande('41', '2026-01-10', patient: 'PXI', valeurs: {'GB': 5, 'HB': 12}),
      demande('42', '2026-04-10', patient: 'PXI', valeurs: {'GB': 7}),
    ];
    cas('mesure et date de l’antériorité la plus récente ; « Aucune antériorité » plutôt qu’un blanc', (t) async {
      await monter(t, magasin({'demandesAnalyses': d, 'plagesReactif': const []}), const EcranResultats(fonction: 'biologiste'));
      await onglet(t, 'valides');
      await toucher(t, find.byKey(const Key('res:compte-rendu:LAB-00042')));
      expect(find.text('Antériorités'), findsWidgets);
      expect(find.text('5 G/l (10/01/2026)'), findsOneWidget, reason: 'GB de la mesure du 10/04 : la précédente est celle du 10/01');
      expect(find.text('Aucune antériorité'), findsWidgets);
      expect(find.textContaining('La colonne Antériorités reprend la mesure rendue la plus récente du même examen.'), findsOneWidget);
    });
    cas('une antériorité hors du périmètre du profil n’est pas imprimée, et la pièce le dit', (t) async {
      final sf = [
        demande('51', '2026-01-10', patient: 'PXS', secteur: 'MATERNITÉ', valeurs: {'GB': 5}),
        demande('52', '2026-02-10', patient: 'PXS', secteur: 'MÉDECINE GÉNÉRALE', valeurs: {'GB': 99}),
        demande('53', '2026-03-10', patient: 'PXS', secteur: 'MATERNITÉ', valeurs: {'GB': 6}),
      ];
      await monter(t, magasin({'demandesAnalyses': sf, 'plagesReactif': const []}), const EcranResultats(fonction: 'sage_femme', secteur: 'MAT'),
          role: 'infirmier', utilisateur: 'SF Test');
      await onglet(t, 'valides');
      await toucher(t, find.byKey(const Key('res:compte-rendu:LAB-00053')));
      expect(find.text('5 G/l (10/01/2026)'), findsOneWidget);
      expect(find.textContaining('99 G/l'), findsNothing);
      expect(find.textContaining('antériorité(s) hors du périmètre du profil qui édite ne sont pas reprises'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // A2 : les seuils de variation brutale
  // ---------------------------------------------------------------------------------------------------------------------------------------------
  group('A2 : seuils de variation brutale', () {
    const ecran = 'm5-valeurs-reference';
    Future<void> ouvrir(WidgetTester t, Magasin m, String role, {String? fonction}) async {
      await monter(t, m, const EcranValeursReference(), role: role, ecranId: ecran, droit: droitMatrice(role, ecran));
      await choisir(t, 'examen', 'NFS complète (hémogramme)');
    }

    ContexteEcran contexte(Magasin m, String role, {String? fonction}) => ContexteEcran(
        ecranId: ecran,
        role: role,
        droit: droitMatrice(role, ecran),
        magasin: m,
        aller: (_) {},
        utilisateur: 'Test',
        agentConnecte: fonction == null ? null : Agent(utilisateurId: 'u-$role', nom: 'Agent Test', role: role, fonction: fonction),
        horloge: () => auj,
        child: const SizedBox());

    Magasin vide() => magasin({'demandesAnalyses': const [], 'plagesReactif': const []});

    test('AUCUN seuil par défaut : aucune fiche livrée, aucune semée, aucune alerte', () {
      expect(File('assets/donnees/jeu/seuilsDelta.json').existsSync(), isFalse);
      expect(File('test/fixtures/jeu_sobre/seuilsDelta.json').existsSync(), isFalse);
      expect(Magasin.collectionsDuJeu, isNot(contains('seuilsDelta')));
      final m = vide();
      expect(m.collection('seuilsDelta').actives, isEmpty);
      // Variables candidates : seules les variables numériques du catalogue de Baguidi (hors accompagnement), 72 sur 50 examens.
      final num = [for (final v in m.collection('variablesLabo').actives) if (v['type'] == 'numerique' && v['accompagnement'] != true && v['actif'] != false) v];
      expect(num.length, 72);
      expect({for (final v in num) v['examen']}.length, 50);
    });

    cas('Valider est PRÉSENT quand la matrice le donne, ABSENT sinon, alors que régler reste ouvert à qui édite l’écran', (t) async {
      // Un seuil Enregistré en attente sur GB.
      final m = vide();
      final bio = SeuilsPoste(contexte(m, 'laborantin'));
      expect(bio.enregistrer('VAR-NFS-GB', ecartAbsolu: 1, dateEffet: '2026-11-13').ok, isTrue);
      await ouvrir(t, m, 'laborantin');
      expect(find.byKey(const Key('seuils:valider:GB')), findsOneWidget, reason: 'le profil à qui la matrice donne le droit annuler de l’écran voit Valider');
      expect(find.byKey(const Key('seuils:regler:GB')), findsOneWidget);
      expect(find.byKey(const Key('seuils:abandonner:GB')), findsOneWidget);
    });

    cas('un profil qui édite l’écran sans le droit de valider règle et abandonne, mais NE VOIT PAS Valider', (t) async {
      final droitDm = droitMatrice('dm', ecran);
      expect(droitDm.editer, isTrue, reason: 'prémisse : la matrice livrée laisse éditer l’écran à ce profil');
      expect(droitDm.annuler, isFalse, reason: 'prémisse : mais pas arbitrer');
      final m = vide();
      expect(SeuilsPoste(contexte(m, 'laborantin')).enregistrer('VAR-NFS-GB', ecartAbsolu: 1, dateEffet: '2026-11-13').ok, isTrue);
      await ouvrir(t, m, 'dm');
      expect(find.byKey(const Key('seuils:regler:GB')), findsOneWidget);
      expect(find.byKey(const Key('seuils:abandonner:GB')), findsOneWidget);
      expect(find.byKey(const Key('seuils:valider:GB')), findsNothing, reason: 'commande ABSENTE, non grisée');
    });

    cas('de bout en bout au geste : régler (Enregistré, sans effet), puis Valider avec motif (Validé, en vigueur)', (t) async {
      final m = vide();
      await ouvrir(t, m, 'laborantin');
      expect(find.text('Aucun seuil'), findsWidgets);
      await toucher(t, find.byKey(const Key('seuils:regler:GB')));
      await t.enterText(find.descendant(of: find.byKey(const Key('kit:champ:ecartAbsolu')), matching: find.byType(TextField)), '2');
      await t.pump();
      await toucher(t, find.byKey(const Key('seuils:enregistrer')));
      // Enregistré : sans effet, la commande Valider paraît.
      expect(find.byKey(const Key('seuils:etat:GB')), findsOneWidget);
      expect(find.text('Enregistré (sans effet)'), findsWidgets);
      expect(SeuilsPoste(contexte(m, 'laborantin')).etat('VAR-NFS-GB').enVigueur, isNull);
      await toucher(t, find.byKey(const Key('seuils:valider:GB')));
      // Un motif vide : refus nommé du moteur, rien n'est validé.
      await toucher(t, find.text('Valider le seuil'));
      expect(find.textContaining('Le motif de la validation est obligatoire'), findsWidgets);
      expect(SeuilsPoste(contexte(m, 'laborantin')).etat('VAR-NFS-GB').etat, 'enregistre');
      await toucher(t, find.byKey(const Key('seuils:valider:GB')));
      await t.enterText(find.byType(TextField).last, 'Notice du réactif');
      await t.pump();
      await toucher(t, find.text('Valider le seuil'));
      final e = SeuilsPoste(contexte(m, 'laborantin')).etat('VAR-NFS-GB');
      expect(e.etat, 'valide');
      expect(e.enVigueur!['motifValidation'], 'Notice du réactif');
      expect(e.enVigueur!['ecartAbsolu'], 2);
      expect(find.byKey(const Key('seuils:valider:GB')), findsNothing, reason: 'plus rien à valider');
      expect(find.byKey(const Key('seuils:historique:GB')), findsOneWidget);
    });

    test('LE MOTEUR REVÉRIFIE : un geste forcé sans le droit est refusé en le nommant, rien n’est écrit', () {
      final m = vide();
      expect(SeuilsPoste(contexte(m, 'laborantin')).enregistrer('VAR-NFS-GB', ecartAbsolu: 1, dateEffet: '2026-11-13').ok, isTrue);
      for (final role in ['dm', 'medecin', 'direction', 'infirmier']) {
        final r = SeuilsPoste(contexte(m, role)).valider('VAR-NFS-GB', motif: 'Je force');
        expect(r.ok, isFalse, reason: role);
        expect(r.refus!.code, 'VALIDATION_RESERVEE', reason: role);
      }
      expect(SeuilsPoste(contexte(m, 'laborantin')).etat('VAR-NFS-GB').etat, 'enregistre');
      // Qui n'édite pas l'écran ne règle pas non plus.
      final r = SeuilsPoste(contexte(m, 'medecin')).enregistrer('VAR-NFS-GB', ecartAbsolu: 9, dateEffet: '2026-11-13');
      expect(r.refus!.code, 'DROIT_REFUSE');
    });

    test('le technicien de laboratoire qui valide par intérim ne valide pas un seuil, même sous le profil du laboratoire', () {
      final m = vide();
      expect(SeuilsPoste(contexte(m, 'laborantin')).enregistrer('VAR-NFS-GB', ecartAbsolu: 1, dateEffet: '2026-11-13').ok, isTrue);
      final tsl = SeuilsPoste(contexte(m, 'laborantin', fonction: 'tsl'));
      expect(tsl.peutValider, isFalse);
      expect(tsl.valider('VAR-NFS-GB', motif: 'Intérim').refus!.code, 'FONCTION_NON_HABILITEE');
      final bio = SeuilsPoste(contexte(m, 'laborantin', fonction: 'biologiste'));
      expect(bio.peutValider, isTrue);
      expect(bio.valider('VAR-NFS-GB', motif: 'Notice').ok, isTrue);
    });

    test('versions datées IMMUABLES au magasin : réécrire ou archiver une version validée est refusé d’où qu’arrive l’écriture', () {
      final m = vide();
      final bio = SeuilsPoste(contexte(m, 'laborantin', fonction: 'biologiste'));
      bio.enregistrer('VAR-NFS-GB', ecartAbsolu: 1, dateEffet: '2026-11-13');
      bio.valider('VAR-NFS-GB', motif: 'Notice');
      final col = m.collection('seuilsDelta');
      final validee = col.actives.single;
      expect(() => col.mettreAJour(validee['id'], {'ecartAbsolu': 99}), throwsA(isA<EcritureRefusee>()));
      expect(() => col.archiver(validee['id']), throwsA(isA<EcritureRefusee>()));
      expect(col.parId(validee['id'])!['ecartAbsolu'], 1);
      // Modifier = AJOUTER une version Enregistrée ; la validée reste en force.
      final r = bio.enregistrer('VAR-NFS-GB', ecartAbsolu: 3, dateEffet: '2026-11-20');
      expect(r.creation, isTrue);
      expect(col.actives.length, 2);
      final e = bio.etat('VAR-NFS-GB');
      expect(e.etat, 'enregistre_sur_valide');
      expect(e.enVigueur!['ecartAbsolu'], 1);
    });

    test('une validation écrit UNE ligne de journal (RG-12) ; le seuil validé survit au vidage de l’activité', () {
      final m = vide();
      final bio = SeuilsPoste(contexte(m, 'laborantin', fonction: 'biologiste'));
      bio.enregistrer('VAR-NFS-GB', ecartAbsolu: 1, dateEffet: '2026-11-13');
      final avant = m.collection('audit').toutes.length;
      bio.valider('VAR-NFS-GB', motif: 'Notice');
      final journal = m.collection('audit').toutes.take(m.collection('audit').toutes.length - avant);
      expect(journal.where((l) => l['action'] == 'Seuil de variation validé').length, 1);
      expect(journal.length, 1);
      cfbViderActivite(m, 'Mise en production');
      expect(m.collection('seuilsDelta').actives.length, 1);
    });

    // L'alerte : seuil validé directement posé au magasin (la forme que le moteur écrit).
    Fiche seuilValide(Map<String, Object?> champs) => {
          'id': 'SEU00001',
          'variableId': 'VAR-NFS-GB',
          'variableCode': 'GB',
          'version': 1,
          'etat': 'valide',
          'dateEffet': '2026-01-01',
          'retrait': false,
          'statut': 'actif',
          'valideLe': '2026-01-01T08:00:00.000Z',
          'validePar': 'Dr BIO',
          'valideRole': 'Biologiste médical',
          'motifValidation': 'Notice',
          ...champs,
        };
    final prec = demande('61', '2026-05-10', patient: 'PXV', valeurs: {'GB': 5});
    final cible = demande('62', '2026-11-12', patient: 'PXV', etat: 'valide_technique', valeurs: {'GB': 9});

    cas('l’alerte SIGNALE à la validation biologique (colonne, tiroir) et ne bloque JAMAIS : la validation passe', (t) async {
      final m = magasin({'demandesAnalyses': [prec, cible], 'plagesReactif': const [], 'seuilsDelta': [seuilValide({'ecartAbsolu': 1})]});
      await monter(t, m, const EcranResultats(fonction: 'biologiste'), role: 'laborantin');
      await onglet(t, 'relecture');
      expect(find.byKey(const Key('res:alerte-validation:LAB-00062')), findsOneWidget);
      expect(find.textContaining('1 variable(s) signalée(s)'), findsOneWidget);
      await toucher(t, find.byKey(const Key('res:valider-bio:LAB-00062')));
      expect(find.textContaining('Variation brutale signalée (seuils validés)'), findsOneWidget);
      expect(find.textContaining('Ce signalement n’empêche pas la validation'), findsOneWidget);
      await toucher(t, find.text('Valider biologiquement'));
      expect(m.collection('demandesAnalyses').parId('62')!['etatAnalyse'], 'valide', reason: 'le signalement n’a rien retenu');
      // Aucune notification d'alerte : la seule notification est celle du résultat disponible.
      final notifs = m.collection('notifications').actives;
      expect(notifs.map((n) => n['type']), ['resultat_disponible']);
      expect('${notifs.single}', isNot(contains('ariation')));
    });

    final enregistre = seuilValide({'etat': 'enregistre', 'valideLe': null, 'validePar': null, 'valideRole': null, 'motifValidation': null, 'ecartAbsolu': 1});
    for (final (nom, seuils) in [('sans aucun seuil', <Fiche>[]), ('avec un seuil seulement Enregistré (sans effet)', [enregistre])]) {
      cas('$nom, aucune alerte ne s’affiche à la validation biologique', (t) async {
        final m = magasin({'demandesAnalyses': [prec, cible], 'plagesReactif': const [], 'seuilsDelta': seuils});
        await monter(t, m, const EcranResultats(fonction: 'biologiste'), role: 'laborantin');
        await onglet(t, 'relecture');
        expect(find.byKey(const Key('res:valider-bio:LAB-00062')), findsOneWidget, reason: 'la mesure est bien à valider');
        expect(find.byKey(const Key('res:alerte-validation:LAB-00062')), findsNothing);
      });
    }

    cas('l’alerte est signalée au comparatif, avec la version et la date d’effet du seuil ; elle n’est pas sur le résultat du prescripteur', (t) async {
      final rendu = demande('62', '2026-11-12', patient: 'PXV', valeurs: {'GB': 9}, valideLe: '2026-11-12T15:00:00.000Z');
      final m = magasin({'demandesAnalyses': [prec, rendu], 'plagesReactif': const [], 'seuilsDelta': [seuilValide({'ecartAbsolu': 1})]});
      await monter(t, m, const EcranComparatifResultats(fonction: 'biologiste'), role: 'laborantin');
      await choisir(t, 'patient', 'TEST PXV (CBG/9/26) — 2 résultat(s)');
      await choisir(t, 'examen', 'NFS complète (hémogramme) (2 mesures)');
      expect(find.byKey(const Key('res:cmp:alerte:GB')), findsOneWidget);
      expect(find.textContaining('Variation brutale : seuil de 1 G/l atteint (seuil validé, version 1 du 01/01/2026)'), findsOneWidget);
      // L'écran du prescripteur (onglet « Rendus au prescripteur ») ne porte aucune alerte.
    });
  });
}
