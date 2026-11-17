import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/modules/m12/cpc_commun.dart' show amorcerExercices;
import 'package:sigh_poste/shell/choix_exercice.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// Le sélecteur d'exercice de la barre supérieure (arbitrage du 05/11/2026) : seulement sur les écrans « à année », choix tenu en session, flèches absentes aux bornes.
void main() {
  setUpAll(chargerPolices);

  casM14('présent sur un écran à année, avec l\'exercice du jour ; flèche suivante ABSENTE à la borne', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm12-balance');
    expect(find.byKey(const Key('selecteur-exercice')), findsOneWidget);
    expect(find.text('Exercice 2026 · ouvert'), findsOneWidget);
    expect(find.byKey(const Key('exercice-precedent')), findsOneWidget);
    expect(find.byKey(const Key('exercice-suivant')), findsNothing, reason: 'pas d\'exercice après le dernier : la flèche est absente, non grisée');
  });

  casM14('choisir l\'exercice précédent change l\'affichage, tient pour la session, et se lit dans la lecture de l\'écran', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm12-balance');
    await toucherM14(t, find.byKey(const Key('exercice-precedent')));
    expect(find.text('Exercice 2025 · clos'), findsOneWidget);
    expect(ChoixExercice.valeur.value, 2025);
    expect(find.byKey(const Key('exercice-suivant')), findsOneWidget);
    await toucherM14(t, find.byKey(const Key('exercice-precedent')));
    expect(find.text('Exercice 2024 · clos'), findsOneWidget, reason: 'les deux exercices de la liasse déposée existent');
    expect(find.byKey(const Key('exercice-precedent')), findsNothing, reason: 'premier exercice connu : flèche absente');
    await t.pump(const Duration(seconds: 10));
  });

  // Direction de Baguidi, 16/11/2026 (E3260) : le défaut est l'exercice qui CONTIENT LA DATE DU JOUR. En décembre, l'exercice suivant est ouvert d'avance (Q29) mais n'est pas le défaut.
  casM14('en décembre : l\'exercice N+1 ouvert d\'avance reste CHOISISSABLE, le défaut est l\'exercice du jour', (t) async {
    final m = magasinM14();
    amorcerExercices(m, DateTime(2026, 12, 5)); // l'amorçage que font la clôture et les états financiers à leur ouverture
    await ouvrirM14(t, m, 'm12-balance', horloge: DateTime(2026, 12, 5, 10));
    expect(m.collection('exercices').actives.any((x) => x['annee'] == 2027), isTrue, reason: 'Q29 : 2027 ouvert d\'avance en décembre');
    expect(find.text('Exercice 2026 · ouvert'), findsOneWidget, reason: 'les pièces de décembre sont de 2026 : la v20 affichait 2027 (ouvert le plus récent)');
    await toucherM14(t, find.byKey(const Key('exercice-suivant')));
    expect(find.text('Exercice 2027 · ouvert'), findsOneWidget);
    expect(ChoixExercice.valeur.value, 2027);
    await t.pump(const Duration(seconds: 10));
  });

  casM14('l\'exercice du jour NON AMORCÉ : le sélecteur le dit, aucun autre exercice n\'est affiché à sa place (E3261)', (t) async {
    final m = magasinM14();
    // Une fiche 2026 archivée : l'amorçage ne la recrée pas (RG-14), l'exercice du jour n'a donc aucune fiche active.
    final exos = m.collection('exercices');
    if (!exos.toutes.any((x) => x['annee'] == 2026)) exos.inserer({'id': 'EXO-2026', 'annee': 2026, 'etat': 'ouvert', 'statut': 'actif'});
    final f = exos.toutes.firstWhere((x) => x['annee'] == 2026);
    exos.mettreAJour(f['id'], {'statut': 'archive'});
    await ouvrirM14(t, m, 'm12-balance');
    expect(find.text('Exercice 2026 · non amorcé'), findsOneWidget, reason: 'la maquette aurait basculé en silence sur 2025, le plus récent');
    expect(find.byKey(const Key('exercice-suivant')), findsNothing);
    await toucherM14(t, find.byKey(const Key('exercice-precedent')));
    expect(find.text('Exercice 2025 · clos'), findsOneWidget, reason: 'la flèche mène à l\'exercice existant le plus proche');
    await t.pump(const Duration(seconds: 10));
  });

  casM14('ABSENT des écrans du jour et des tableaux de bord de poste', (t) async {
    final m = magasinM14();
    for (final id in ['m8-caisse', 'dash-da', 'm12-ouverture']) {
      await ouvrirM14(t, m, id);
      expect(find.byKey(const Key('selecteur-exercice')), findsNothing, reason: id);
    }
  });
}
