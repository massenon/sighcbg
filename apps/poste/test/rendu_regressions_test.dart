import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show EntreeTicket, mdtNature;
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm8_facturation_test.dart' as f;

/// Défauts relevés à l'ŒIL sur le rendu réel (rapport `docs/rendu/RAPPORT.md`) et leur non-régression.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  test('l\'article suit le genre de l\'entité : « une situation », « un patient »', () {
    expect(rechercherEntite('situation de l’acheteur'), 'Rechercher une situation de l’acheteur…');
    expect(rechercherEntite('patient'), 'Rechercher un patient…');
    expect(aucuneEntiteEnregistree('consultation'), 'Aucune consultation enregistrée.');
    expect(aucuneEntiteEnregistree('convention de visites'), 'Aucune convention de visites enregistrée.');
    expect(aucuneEntiteEnregistree('rendez-vous'), 'Aucun rendez-vous enregistré.');
  });

  test('le jeu livré porte le CODE de la nature de visite, pas son libellé accentué', () {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
    final visites = m.collection('consultations').actives.where((c) => c['specialite'] == 'medecine-travail');
    expect(visites, isNotEmpty);
    for (final v in visites) {
      expect(mdtNature(v['natureVisite'])?.code, v['natureVisite'], reason: '${v['reference']}');
    }
  });

  f.cas('le montant réglé proposé est un entier sans « .0 »', (t) async {
    await f.ouvrir(t, f.magasin());
    await f.ajouterLibre(t, 'Carnet de santé', '500', quantite: '2');
    final champ = find.descendant(of: find.byKey(const Key('kit:champ:regle')), matching: find.byType(TextField));
    expect((t.widget<TextField>(champ).controller!.text), '1000');
  });

  f.cas('la liste « Situation de l\'acheteur » ne propose pas « — Aucun — » à côté de « Automatique » (même valeur vide)', (t) async {
    await f.ouvrir(t, f.magasin());
    await f.toucher(t, find.text('Automatique — d’après l’IFU saisi').first);
    expect(find.text('— Aucun —'), findsNothing);
    expect(find.text('Acheteur sans IFU actif — 5 % arrêté'), findsOneWidget);
  });

  testWidgets('l\'aperçu du ticket est CENTRÉ dans la modale et la modale est blanche sous son ombre', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold();
    })));
    afficherApercuTicket(ctx, EntreeTicket(operateur: 'CAISSE', numero: 'FN-1', date: DateTime(2026, 8, 16, 9), partPatient: 1000, total: 1000), 'T-1');
    await t.pump(const Duration(milliseconds: 600));
    final corps = t.getCenter(find.byKey(const Key('kit:modale-corps')));
    final ticket = t.getCenter(find.byKey(const Key('impression:ticket')));
    expect((corps.dx - ticket.dx).abs(), lessThan(2));
    final deco = t.widgetList<DecoratedBox>(find.descendant(of: find.byKey(const Key('kit:modale-panneau')), matching: find.byType(DecoratedBox))).first.decoration as BoxDecoration;
    expect(deco.color, Colors.white, reason: 'sans fond, l\'ombre se peint sous l\'en-tête et le grise');
  });
}
