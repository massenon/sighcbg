import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/impression/fiche_organigramme.dart';
import 'package:sigh_poste/impression/identite_poste.dart';
import 'package:sigh_poste/impression/piece.dart';
import 'package:sigh_poste/impression/pdf.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/cfg/cfa_commun.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// L'organigramme IMPRIMÉ de cfg-organisation sur le jeu LIVRÉ (les dix-neuf postes réels) : le bouton produit la fiche paysage de deux pages, la légende
/// porte les dix-huit abréviations, un poste ajouté ou archivé se retrouve au graphe et à la légende, « Page n sur N » est exact, les paramètres de la fiche
/// font le cartouche, et le PDF écrit est PAYSAGE.
Magasin livre() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

FichePaysage fiche(Magasin m) => fichePaysageOrganigramme(m, utilisateur: 'BAGUIDI Rafiou', edite: DateTime(2026, 11, 10, 9, 30), reference: 'CBG-20261110-0001');

int pagesPdf(List<int> octets) => RegExp(r'/Type\s*/Page(?![s\w])').allMatches(latin1.decode(octets)).length;

List<List<double>> boitesPdf(List<int> octets) => [
      for (final m in RegExp(r'/MediaBox\s*\[\s*([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s+([\d.\-]+)\s*\]').allMatches(latin1.decode(octets)))
        [for (var i = 1; i <= 4; i++) double.parse(m.group(i)!)]
    ];

void main() {
  setUpAll(() async {
    await chargerPolices();
    cfaPoserNavigation(donneesNav);
  });
  tearDown(() {
    ToastsSigh.viderPourTests();
    IdentiteClinique.reinitialiser();
  });

  test('le jeu livré : dix-neuf postes, une fiche documentaire, deux pages, dix-huit abréviations', () {
    final m = livre();
    expect(m.collection('postes').actives.length, 19);
    final f = fiche(m);
    expect(f.pages.length, 2);
    expect(f.pages[0], isA<PageGraphe>());
    expect((f.pages[0] as PageGraphe).scene.cases.length, 19);
    expect((f.pages[1] as PageLegende).lignes.map((l) => l.code).toList(), [
      'DG/MC', 'SM', 'MG', 'MP', 'CARH', 'RE', 'RM', 'RR', 'RL', 'RSI', 'RA', 'AR', 'FC', 'ADS', 'AES', 'CVA/ AIM', 'AS', 'RI'
    ]);
    expect(f.cartouche(0), ['Référence : FCH_GRH_006', 'Date : 03/05/2023', 'Version 01', 'Page 1 sur 2']);
    expect(f.cartouche(1).last, 'Page 2 sur 2');
    expect(f.fiche.mention, 'Ce document demeure strictement la propriété de la Clinique BAGUIDI l’AS de Cœur');
    // Seul le Directeur Général a un titulaire connu : aucun autre nom n'est inventé.
    final titulaires = [for (final p in m.collection('postes').actives) if ('${p['titulaire'] ?? ''}'.isNotEmpty) '${p['titulaire']}'];
    expect(titulaires, ['BAGUIDI Rafiou']);
  });

  test('le pied vient de l’IDENTITÉ de la clinique, jamais d’un texte recopié', () {
    final m = livre();
    final i = identiteImprimeeDe(m, DateTime(2026, 11, 10));
    final pied = fiche(m).pied;
    expect(pied[0], contains(i.nom));
    expect(pied[0], contains(i.bp));
    for (final t in i.telephones) {
      expect(pied[0], contains(t));
    }
    expect(pied[1], contains(i.ifu));
    expect(pied[1], contains(i.email));
  });

  test('un poste ajouté apparaît au graphe et à la légende, sans code ; un poste archivé disparaît de l’un et de l’autre', () {
    final m = livre();
    final id = m.collection('postes').inserer({'poste': 'Responsable Qualité', 'code': 'RQ', 'parentId': 'PST001', 'role': 'agentadmin', 'effectif': 1, 'niveau': 3}).fiche['id'];
    var f = fiche(m);
    final scene = (f.pages[0] as PageGraphe).scene;
    expect(scene.cases.length, 20);
    expect(scene.cases.firstWhere((c) => c.id == id).texte, 'RQ');
    expect(scene.traits.any((t) => t.x2 == scene.cases.firstWhere((c) => c.id == id).cx), isTrue, reason: 'relié à son rattachement');
    expect((f.pages[1] as PageLegende).lignes.map((l) => l.code), contains('RQ'));
    expect((f.pages[1] as PageLegende).lignes.length, 19);
    expect(f.pages.length, 2, reason: 'la dix-neuvième ligne tient encore sur la page');

    m.collection('postes').archiver('PST003');
    m.collection('postes').archiver(id);
    f = fiche(m);
    final s2 = (f.pages[0] as PageGraphe).scene;
    expect(s2.cases.any((c) => c.id == 'PST003' || c.id == id), isFalse);
    expect(s2.cases.length, 18);
    final codes = (f.pages[1] as PageLegende).lignes.map((l) => l.code).toList();
    expect(codes.contains('MG'), isFalse);
    expect(codes.contains('RQ'), isFalse);
    expect(codes.length, 17);
  });

  test('« Page n sur N » suit le nombre RÉEL de pages : la légende qui déborde passe à la page suivante', () {
    final m = livre();
    for (var i = 0; i < 3; i++) {
      m.collection('postes').inserer({'poste': 'Poste $i', 'code': 'Z$i', 'parentId': 'PST001', 'role': 'agentadmin', 'effectif': 1});
    }
    final f = fiche(m);
    expect(f.pages.length, 3);
    expect((f.pages[1] as PageLegende).lignes.length, 19);
    expect((f.pages[2] as PageLegende).lignes.length, 2);
    for (var i = 0; i < 3; i++) {
      expect(f.cartouche(i).last, 'Page ${i + 1} sur 3');
    }
  });

  test('les paramètres de la fiche modifiés en base font le cartouche modifié', () {
    final m = livre();
    m.collection(ficheDocCollection).mettreAJour('organigramme', {'reference': 'FCH_GRH_007', 'date': '2026-11-10', 'version': '02', 'titreHaut': 'DOCUMENT', 'titre': 'ORGANISATION', 'mention': 'Mention de test'});
    final f = fiche(m);
    expect(f.cartouche(0), ['Référence : FCH_GRH_007', 'Date : 10/11/2026', 'Version 02', 'Page 1 sur 2']);
    expect((f.fiche.titreHaut, f.fiche.titre, f.fiche.mention), ('DOCUMENT', 'ORGANISATION', 'Mention de test'));
    // La modification est journalisée (RG-12) et ne touche pas la grille.
    expect(m.collection('audit').actives.any((a) => '${a['entite'] ?? a['entity'] ?? a}'.contains('fichesDocumentaires') || '$a'.contains('FCH_GRH_007')), isTrue);
    expect(f.fiche.grille.niveauxY.length, 6);
  });

  test('le PDF est PAYSAGE : deux pages A4, largeur supérieure à la hauteur', () async {
    final m = livre();
    final p = await PolicesPdf.charger();
    final octets = await pdfFichePaysage(fiche(m), p);
    expect(pagesPdf(octets), 2);
    final boites = boitesPdf(octets);
    expect(boites.length, 2);
    for (final b in boites) {
      final l = b[2] - b[0], h = b[3] - b[1];
      expect(l, greaterThan(h));
      expect(l, closeTo(841.89, 0.5));
      expect(h, closeTo(595.28, 0.5));
    }
  });

  casM14('le bouton « Imprimer l’organigramme » ouvre la fiche paysage (deux pages) et son PDF est écrit ; la liste des postes reste sous son propre bouton', (t) async {
    String? nom;
    List<int>? pdf;
    ImpressionPoste.enregistrer = (octets, n) async {
      pdf = octets;
      nom = n;
      return '/faux/$n.pdf';
    };
    final m = livre();
    await ouvrirM14(t, m, 'cfg-organisation');
    await toucherM14(t, find.text('Organigramme').first);
    expect(find.widgetWithText(BoutonSigh, 'Imprimer l’organigramme'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Imprimer la liste des postes'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer l’organigramme'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('impression:fiche:0')), findsOneWidget);
    expect(find.byKey(const Key('impression:fiche:1')), findsOneWidget);
    expect(find.byKey(const Key('impression:fiche:2')), findsNothing);
    expect(find.text('Page 1 sur 2'), findsOneWidget);
    expect(find.text('Page 2 sur 2'), findsOneWidget);
    expect(find.text('ORGANIGRAMME'), findsWidgets);
    final legende = find.byKey(const Key('impression:fiche:legende'));
    expect(find.descendant(of: legende, matching: find.byType(RichText)), findsNWidgets(18));
    for (final id in ['PST001', 'PST006', 'PST019']) {
      expect(find.byKey(Key('case:$id')), findsOneWidget);
    }
    for (final i in [0, 1]) {
      expect(find.descendant(of: find.byKey(Key('impression:fiche:$i')), matching: find.text('Ce document demeure strictement la propriété de la Clinique BAGUIDI l’AS de Cœur')), findsOneWidget);
    }
    await t.runAsync(() async {
      await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer en PDF'));
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await t.pump(const Duration(milliseconds: 300));
    expect(nom, startsWith('CBG-'));
    expect(pagesPdf(pdf!), 2);
    expect(boitesPdf(pdf!).every((b) => b[2] - b[0] > b[3] - b[1]), isTrue);
    // La liste des postes (état A4 portrait) s'imprime toujours, sous son bouton.
    await t.pump(const Duration(seconds: 6));
  });

  casM14('au geste : un poste créé à l’écran avec son code entre au graphe et à la légende de l’impression', (t) async {
    final m = livre();
    await ouvrirM14(t, m, 'cfg-organisation');
    await toucherM14(t, find.text('Organigramme').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'poste', 'Responsable Qualité');
    await saisir(t, 'code', 'RQ');
    await saisir(t, 'niveau', '3');
    await choisirM14(t, 'role', 'Infirmier / Sage-femme');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final f = m.collection('postes').toutes.first;
    expect(f['code'], 'RQ');
    expect(f['niveau'], 3);
    await t.pump(const Duration(seconds: 6));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer l’organigramme'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(Key('case:${f['id']}')), findsOneWidget);
    final legende = find.byKey(const Key('impression:fiche:legende'));
    expect(find.descendant(of: legende, matching: find.byType(RichText)), findsNWidgets(19));
    await t.pump(const Duration(seconds: 6));
  });

  casM14('l’édition des paramètres de la fiche se fait à l’écran et change le cartouche imprimé', (t) async {
    final m = livre();
    await ouvrirM14(t, m, 'cfg-organisation');
    await toucherM14(t, find.text('Organigramme').first);
    expect(find.text('Fiche imprimée de l’organigramme — cartouche et mention de propriété'), findsOneWidget);
    expect(find.text('FCH_GRH_006'), findsWidgets);
    await toucherM14(t, find.byTooltip('Modifier').first);
    await saisir(t, 'reference', 'FCH_GRH_010');
    await saisir(t, 'version', '03');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final f = m.collection(ficheDocCollection).actives.single;
    expect(f['reference'], 'FCH_GRH_010');
    expect(f['version'], '03');
    expect(f['mention'], isNotEmpty);
    await t.pump(const Duration(seconds: 6));
    expect(fiche(m).cartouche(0)[0], 'Référence : FCH_GRH_010');
    expect(File('assets/donnees/jeu/fichesDocumentaires.json').existsSync(), isTrue);
  });
}
