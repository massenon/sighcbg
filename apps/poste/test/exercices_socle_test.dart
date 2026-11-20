import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/exercices_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/shell/choix_exercice.dart';

/// DÉFAUT PTA (17/11/2026) : sur un poste réel avec le jeu LIVRÉ (`assets/donnees/jeu`), la table des exercices est vide et le sélecteur d'exercice de la barre supérieure ne se dessinait
/// qu'après l'amorçage par un ÉCRAN (clôture, états financiers, plan de travail) : le widget n'écoutait pas la collection. Deux corrections à la racine : l'amorçage est au SOCLE (appelé au démarrage du
/// poste, `main.dart`) ET le sélecteur écoute la collection. Aucune année en dur : l'horloge, le journal et la liasse déposée décident.
void main() {
  final auj = DateTime(2026, 11, 17, 10);
  Magasin jeuLivre() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

  test('le jeu livré porte une table des exercices VIDE : c\'est l\'amorçage du socle qui la remplit, sans ouvrir aucun écran', () {
    final m = jeuLivre();
    expect(m.collection('exercices').toutes, isEmpty, reason: 'le jeu livré ne contient aucun exercice');
    amorcerExercices(m, auj);
    final annees = {for (final x in m.collection('exercices').actives) x['annee']};
    expect(annees, contains(2026), reason: 'l\'exercice de la date du jour');
    expect(annees.length, greaterThanOrEqualTo(2), reason: 'les exercices de la liasse déposée aussi');
    final avant = m.collection('exercices').toutes.length;
    amorcerExercices(m, auj);
    expect(m.collection('exercices').toutes.length, avant, reason: 'idempotent : une année déjà présente n\'est jamais réinsérée');
  });

  test('le démarrage du poste appelle l\'amorçage du socle (avant le premier affichage)', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("import 'donnees/exercices_poste.dart';"));
    expect(main, contains('amorcerExercices(magasin, DateTime.now());'));
    expect(main.indexOf('amorcerExercices(magasin, DateTime.now());'), lessThan(main.indexOf('brancherIdentite(magasin);')), reason: 'avant le premier affichage');
  });

  testWidgets('le sélecteur ÉCOUTE la collection : vide il est absent, dès que l\'exercice naît (écran, réception du pont) il se dessine, sans autre geste', (t) async {
    final m = jeuLivre();
    ChoixExercice.reinitialiser();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SelecteurExercice(magasin: m, aujourdhui: auj))));
    expect(find.byKey(const Key('selecteur-exercice')), findsNothing, reason: 'aucun exercice : rien à choisir');
    amorcerExercices(m, auj);
    await t.pump();
    expect(find.byKey(const Key('selecteur-exercice')), findsOneWidget);
    expect(find.text('Exercice 2026 · ouvert'), findsOneWidget);
  });
  testWidgets('un écran qui amorce PENDANT sa construction ne fait pas planter le sélecteur : son repeint est reporté à la fin de l\u2019image', (t) async {
    final m = jeuLivre();
    ChoixExercice.reinitialiser();
    var fait = false;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      SelecteurExercice(magasin: m, aujourdhui: auj),
      Builder(builder: (_) {
        if (!fait) {
          fait = true;
          amorcerExercices(m, auj); // comme `didChangeDependencies` de la clôture, des états financiers ou du plan de travail
        }
        return const SizedBox();
      }),
    ]))));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byKey(const Key('selecteur-exercice')), findsOneWidget);
  });
}
