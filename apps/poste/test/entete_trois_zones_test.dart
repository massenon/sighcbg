import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/jetons_shell.dart';
import 'package:sigh_poste/impression/entete_papier.dart';
import 'package:sigh_poste/impression/feuilles.dart';
import 'package:sigh_poste/impression/pdf.dart';
import 'package:sigh_poste/impression/piece.dart';

import 'aide_polices.dart';

/// P0-13 : le papier à en-tête en TROIS ZONES, le même modèle à l'écran (A4, aperçu de cfg-branding) et sur le PDF.
IdentiteImprimee identite({Map<String, Object?> fiche = const {}}) => IdentiteImprimee.depuisFiche(fiche);

Future<void> monter(WidgetTester t, Widget w) async {
  await chargerPolices();
  t.view.physicalSize = const Size(1200, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));
  await t.pump();
}

void main() {
  tearDown(IdentiteClinique.reinitialiser);

  test('modèle : zone droite dans l’ordre, date d’IFU, ONMB ; autorisation vide non imprimée ; aucune ligne vide', () {
    final e = EnteteTroisZones.depuis(identite());
    expect(e.denomination, IdentiteClinique.nom);
    expect(e.sousTitre, 'CENTRE DE MÉDECINE DU TRAVAIL, MÉDECINE GÉNÉRALE');
    expect(e.devise, 'Votre bien-être est notre raison d’être.');
    expect(e.lignesDroite, [
      '02 BP : 105 PARAKOU (Rép. du Bénin)',
      'Téléphones : 95 74 69 56 / 95 95 99 14 / 97 09 34 99',
      'IFU : 3201001996110 du 26 novembre 2010',
      'E-mail : cliniquebaguidi@yahoo.fr',
      'Quartier Zongo II, Parakou — République du Bénin',
      'RCCM : RB/PKO/17 A 4240',
      'N° d’enregistrement ONMB : 0416/ONMB/ATL/2002',
    ]);
    expect(e.piedLegal, '${IdentiteClinique.nom} — IFU 3201001996110 — RCCM RB/PKO/17 A 4240');
    expect(e.editeDepuis, 'Édité depuis le SIGH-CBG');
    expect(e.lignesDroite.any((l) => l.contains('utorisation')), isFalse);
  });

  test('modèle : champs vides = rien d’imprimé ; une date d’IFU vide laisse le numéro seul ; une version datée sans ifuDate retombe sur la semence', () {
    final vide = EnteteTroisZones.depuis(identite(fiche: {'bp': '', 'email': '', 'telephones': <String>[], 'rccm': '', 'enregistrement': '', 'ifuDate': '', 'slogan': ''}));
    expect(vide.lignesDroite, ['IFU : 3201001996110', 'Quartier Zongo II, Parakou — République du Bénin']);
    expect(vide.lignesDroite.every((l) => l.trim().isNotEmpty), isTrue);
    expect(vide.devise, '');
    final avec = EnteteTroisZones.depuis(identite(fiche: {'autorisation': 'N° 012/MS'}));
    expect(avec.lignesDroite, contains('Autorisation d’ouverture : N° 012/MS'));
    // Une ancienne version datée (sans ifuDate) hérite de la semence : elle n'est pas cassée.
    expect(identite(fiche: {'version': 1, 'debut': null}).ifuDate, '26 novembre 2010');
  });

  testWidgets('feuille A4 : trois zones (logo + devise, dénomination + activité, coordonnées à droite) et double filet rouge puis bleu, 2 px', (t) async {
    await monter(t, FeuilleA4(piece: PieceA4(titre: 'État', reference: 'CBG-20261030-0001', utilisateur: 'A', edite: DateTime(2026, 10, 30), identite: identite())));
    final e = t.getRect(find.byKey(const Key('impression:entete')));
    final g = t.getRect(find.byKey(const Key('entete:gauche'))), c = t.getRect(find.byKey(const Key('entete:centre'))), d = t.getRect(find.byKey(const Key('entete:droite')));
    expect(g.right, lessThanOrEqualTo(c.left));
    expect(c.right, lessThanOrEqualTo(d.left));
    expect(g.width, lessThan(e.width * 0.26));
    // Logo : zone gauche, 2,4 cm, jamais étiré ; devise dessous, en Dancing Script rouge cœur.
    final logo = t.getRect(find.byKey(const Key('logo-clinique')));
    expect(logo.width, closeTo(mm(24), 0.5));
    expect(logo.height, closeTo(mm(24), 0.5));
    expect(g.contains(logo.center), isTrue);
    final devise = t.widget<Text>(find.byKey(const Key('entete:devise')));
    expect(devise.style!.fontFamily, 'Dancing Script');
    expect(devise.style!.color, JetonsShell.coeur500);
    expect(t.getTopLeft(find.byKey(const Key('entete:devise'))).dy, greaterThan(logo.bottom - 1));
    final nom = t.widget<Text>(find.byKey(const Key('impression:entete:nom')));
    expect(nom.style!.fontFamily, 'Montserrat');
    expect(nom.style!.fontWeight, FontWeight.w700);
    expect(nom.style!.color, JetonsShell.coeur500);
    expect(find.text('CENTRE DE MÉDECINE DU TRAVAIL, MÉDECINE GÉNÉRALE'), findsOneWidget);
    expect(find.text('IFU : 3201001996110 du 26 novembre 2010'), findsOneWidget);
    expect(find.text('Quartier Zongo II, Parakou — République du Bénin'), findsOneWidget);
    // Double filet : 2 px rouge, 2 px d'écart, 2 px bleu, pleine largeur.
    final r = t.getRect(find.byKey(const Key('entete:filet-coeur'))), b = t.getRect(find.byKey(const Key('entete:filet-sante')));
    expect(r.height, 2);
    expect(b.height, 2);
    expect(b.top - r.bottom, 2);
    expect(r.width, closeTo(e.width, 0.5));
    expect(b.width, closeTo(e.width, 0.5));
    expect(t.widget<Container>(find.byKey(const Key('entete:filet-coeur'))).color, JetonsShell.coeur500);
    expect(t.widget<Container>(find.byKey(const Key('entete:filet-sante'))).color, JetonsShell.sante600);
    // Pied : dénomination, IFU, RCCM ; référence ; « Édité depuis le SIGH-CBG ».
    expect(find.text('${IdentiteClinique.nom} — IFU 3201001996110 — RCCM RB/PKO/17 A 4240'), findsOneWidget);
    expect(find.text('Réf. document : CBG-20261030-0001'), findsOneWidget);
    expect(find.text('Édité depuis le SIGH-CBG'), findsOneWidget);
  });

  testWidgets('champs vides : aucune ligne vide, aucun libellé orphelin, aucune autorisation', (t) async {
    await monter(t, EnteteLegal(identite: identite(fiche: {'bp': '', 'email': '', 'rccm': '', 'enregistrement': '', 'ifuDate': '', 'slogan': '', 'autorisation': ''})));
    final lignes = [for (final x in t.widgetList<Text>(find.descendant(of: find.byKey(const Key('entete:droite')), matching: find.byType(Text)))) x.data!];
    expect(lignes, ['Téléphones : 95 74 69 56 / 95 95 99 14 / 97 09 34 99', 'IFU : 3201001996110', 'Quartier Zongo II, Parakou — République du Bénin']);
    expect(lignes.any((l) => l.trim().isEmpty), isFalse);
    expect(find.byKey(const Key('entete:devise')), findsNothing);
    expect(find.textContaining('RCCM'), findsNothing);
    expect(find.textContaining('utorisation'), findsNothing);
    expect(find.textContaining('E-mail'), findsNothing);
  });

  testWidgets('PDF A4 : mêmes polices (Montserrat, Dancing Script) et texte de l’en-tête identique', (t) async {
    final p = (await t.runAsync(PolicesPdf.charger))!;
    final pieceA4 = PieceA4(titre: 'État', reference: 'CBG-20261030-0001', utilisateur: 'A', edite: DateTime(2026, 10, 30), identite: identite());
    final octets = (await t.runAsync(() => pdfA4(pieceA4, p, compresser: false)))!;
    final brut = latin1.decode(octets);
    expect(brut, contains('Montserrat'));
    expect(brut, contains('DancingScript'));
    expect(RegExp(r'/Type\s*/Page\b').hasMatch(brut), isTrue);
  });
}
