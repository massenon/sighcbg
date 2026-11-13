import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// D5 : « ContexteEcran absent » à l'impression depuis le TIROIR du répertoire des patients.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('ouvrir le tiroir d\'un patient puis « Imprimer l\'état » ne lève aucune exception', (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
    await ouvrirM14(t, m, 'm1-patients');
    await toucherM14(t, find.byTooltip('Consulter').first);
    expect(find.byKey(const Key('kit:tiroir-panneau')), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'le tiroir s\'ouvre');
    // On referme le tiroir (Échap), puis on imprime l'état de la même ligne : l'aperçu s'ouvre.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('kit:tiroir-panneau')), findsNothing);
    await toucherM14(t, find.byTooltip('Imprimer l’état').first);
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull, reason: 'l\'impression de l\'état depuis la liste');
    expect(find.text('Enregistrer en PDF'), findsWidgets, reason: 'l\'aperçu est ouvert');
  });

  casM14('la racine : une modale et un tiroir relaient le contexte de l\'écran qui les ouvre (tout futur tiroir en profite)', (t) async {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
    await ouvrirM14(t, m, 'm1-patients');
    final ctx = t.element(find.byType(TableauSigh).first);
    String? vuTiroir, vuModale;
    afficherTiroir<void>(ctx,
        titre: 'T', corps: Builder(builder: (c) => Text(vuTiroir = ContexteEcran.of(c).ecranId)));
    await t.pump(const Duration(milliseconds: 400));
    Navigator.of(t.element(find.byKey(const Key('kit:tiroir-panneau')))).pop();
    await t.pump(const Duration(milliseconds: 400));
    afficherModale<void>(ctx,
        titre: 'M', corps: Builder(builder: (c) => Text(vuModale = ContexteEcran.of(c).ecranId)));
    await t.pump(const Duration(milliseconds: 400));
    expect(vuTiroir, 'm1-patients');
    expect(vuModale, 'm1-patients');
    expect(t.takeException(), isNull);
  });
}
