import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/accord.dart';

/// L'accord en genre des libellés : « Nouvelle admission », « Toutes les consultations ». Un gabarit générique ne devine pas le genre
/// d'une entité (c'est `accord.dart` qui le sait) ; un littéral ne doit jamais coller « Nouveau » à un nom féminin connu.
void main() {
  test('les fonctions d’accord', () {
    expect(nouvelleEntite('admission'), 'Nouvelle admission');
    expect(entiteCreee('admission'), 'Nouvelle admission créée.');
    expect(nouvelleEntite('patient'), 'Nouveau patient');
    expect(entiteCreee('patient'), 'Nouveau patient créé.');
    expect(nouvelleEntite('accouchement'), 'Nouvel accouchement');
    expect(entiteCreee('agent'), 'Nouvel agent créé.');
    expect(nouvelleEntite('demande d’analyse'), 'Nouvelle demande d’analyse');
    expect(nouvelleEntite('Check-liste'), 'Nouvelle Check-liste');
    expect(nouvelleEntite('Contre-référence'), 'Nouvelle Contre-référence');
    expect(nouvelleEntite('Couverture'), 'Nouvelle Couverture');
    expect(nouvelleEntite('rendez-vous'), 'Nouveau rendez-vous');
    expect(tousLesEntites('consultation', 'consultations'), 'Toutes les consultations');
    expect(tousLesEntites('lot', 'lots'), 'Tous les lots');
    expect(modifierEntite('facture'), 'Modifier la facture');
    expect(modifierEntite('lot'), 'Modifier le lot');
    expect(modifierEntite('admission'), 'Modifier l’admission');
  });

  test('aucun littéral de l’application n’accole « Nouveau » ou « Tous les » à un nom féminin connu', () {
    final fem = motsFeminins.map(RegExp.escape).toList()..sort((a, b) => b.length.compareTo(a.length));
    final alt = fem.join('|');
    final nouveau = RegExp('Nouveau ((?:$alt))(?![a-zéèêàâîïôû])', caseSensitive: false);
    final tous = RegExp('Tous les ((?:$alt))s(?![a-zéèêàâîïôû])', caseSensitive: false);
    final fautes = <String>[];
    for (final racine in ['lib', '../mobile/lib']) {
      final dossier = Directory(racine);
      if (!dossier.existsSync()) continue;
      for (final f in dossier.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final lignes = f.readAsLinesSync();
        for (var i = 0; i < lignes.length; i++) {
          final l = lignes[i].trim();
          if (l.startsWith('//')) continue;
          if (nouveau.hasMatch(l) || tous.hasMatch(l)) fautes.add('${f.path}:${i + 1}  $l');
        }
      }
    }
    expect(fautes, isEmpty, reason: 'accorder avec nouvelleEntite() / tousLesEntites() ou écrire « Nouvelle » / « Toutes les » :\n${fautes.join('\n')}');
  });

  test('aucun gabarit n’assemble « Nouveau » et une entité à la main', () {
    final motif = RegExp(r'Nouveau \$\{?(widget\.)?entite');
    final fautes = <String>[];
    for (final racine in ['lib', '../mobile/lib']) {
      final dossier = Directory(racine);
      if (!dossier.existsSync()) continue;
      for (final f in dossier.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final lignes = f.readAsLinesSync();
        for (var i = 0; i < lignes.length; i++) {
          if (!lignes[i].trim().startsWith('//') && motif.hasMatch(lignes[i])) fautes.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(fautes, isEmpty);
  });
}
