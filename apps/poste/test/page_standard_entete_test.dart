import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/shell/page_standard.dart';

import 'aide_polices.dart';

/// L'EN-TÊTE DE PAGE STANDARD, cinq commandes sur 1 280 px (lot TFIN) : les commandes passent à la LIGNE au lieu d'écraser le titre. Relevé chez la clinique sœur : un écran qui portait cinq
/// commandes (dont « Importer les données ») réduisait le titre à quinze pixels de large, un mot par ligne.
void main() {
  setUpAll(chargerPolices);

  testWidgets('cinq commandes sur 1 280 px : le titre tient sur UNE ligne, à sa largeur naturelle', (t) async {
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PageStandard(
      titre: 'Courriers et orientation',
      fil: const ['Accueil', 'Administration', 'Courriers et orientation'],
      module: 'M13',
      description: 'Le registre des courriers.',
      actions: [
        for (final l in const ['Importer les données', 'Nouveau courrier', 'Exporter le registre', 'Imprimer l’état', 'Filtres avancés'])
          BoutonSigh(libelle: l, onPressed: () {}),
      ],
      child: const SizedBox(),
    ))));
    await t.pump();
    final titre = t.getSize(find.byKey(const Key('titre-page')));
    expect(titre.width, greaterThan(200), reason: 'le titre est écrasé par les commandes : ${titre.width} px');
    expect(titre.height, lessThan(20 * 1.4 * 1.5), reason: 'le titre passe sur plusieurs lignes : il est écrasé (${titre.height} px de haut)');
    expect(find.byType(BoutonSigh), findsNWidgets(5));
    expect(t.takeException(), isNull);
  });
}
