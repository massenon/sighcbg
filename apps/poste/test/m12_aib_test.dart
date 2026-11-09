import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// M12 `m12-aib` : le barème de l'AIB, versionné par date d'effet. Ce que l'écran dit (arrêté / non arrêté), ce qu'il écrit (création, version datée,
/// archivage avec motif), ce qu'il REFUSE (réécrire une version arrêtée) et ce qu'il n'offre jamais sans le droit.
Magasin magasinAib() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

/// Choisit [jour] (« mm/jj/aaaa », la saisie du sélecteur) dans le champ date [champ] : le sélecteur s'ouvre en calendrier, on passe en saisie au clavier.
Future<void> choisirDate(WidgetTester t, String champ, String jour) async {
  await toucherM14(t, find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  await t.pump(const Duration(milliseconds: 400));
  await t.tap(find.byIcon(Icons.edit_outlined));
  await t.pump(const Duration(milliseconds: 300));
  await t.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).first, jour);
  await t.pump();
  await t.tap(find.text('OK'));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('l\'écran DIT ce qui est arrêté (5 %) et ce qui ne l\'est pas (1 % et 3 %, à valider) ; le 5 % s\'applique aujourd\'hui', (t) async {
    final m = magasinAib();
    await ouvrirM14(t, m, 'm12-aib');
    expect(find.textContaining('ARRÊTÉ : 5 %'), findsOneWidget);
    expect(find.textContaining('arrêté par Direction le 07/09/2026'), findsOneWidget);
    expect(find.textContaining('NON ARRÊTÉ, À VALIDER : 1 % (Taux de 1 % : champ d’application à préciser) ; 3 %'), findsOneWidget);
    expect(find.text('Taux appliqué aujourd’hui'), findsOneWidget);
    expect(find.text('5 %'), findsWidgets);
    expect(find.text('Non arrêté, à valider'), findsNWidgets(2));
    expect(find.text('Arrêté'), findsWidgets);
    expect(m.collection('baremeAIB').actives.length, 3);
  });

  casM14('créer une VERSION DATÉE : AIB-5 à 6 % arrêté, à compter du 01/01/2027 — le 5 % reste en vigueur avant (journalisé, RG-12)', (t) async {
    final m = magasinAib();
    await ouvrirM14(t, m, 'm12-aib');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'code', 'AIB-5');
    await saisir(t, 'categorie', 'Taux généralisé : IFU désactivé ou absent du fichier actif');
    await saisir(t, 'taux', '6');
    await choisirDate(t, 'dateEffet', '01/01/2027');
    await choisirM14(t, 'statutArret', 'Arrêté');
    await choisirDate(t, 'dateArret', '10/30/2026');
    await saisir(t, 'decideurArret', 'Direction');
    await saisir(t, 'motif', 'Correction du taux à compter de 2027');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final v = m.collection('baremeAIB').actives.firstWhere((f) => f['taux'] == 6);
    expect([v['code'], v['dateEffet'], v['arrete'], v['decideurArret'], v['statut']], ['AIB-5', '2027-01-01', true, 'Direction', 'actif']);
    expect(m.collection('baremeAIB').actives.length, 4, reason: 'une correction AJOUTE une version, elle n\'en écrase aucune');
    expect(find.text('Nouveau taux d’AIB créé.'), findsOneWidget);
    final fiches = m.collection('baremeAIB').actives;
    expect(cpdTauxAibALaDate(fiches, 'AIB-5', DateTime(2026, 12, 31)).taux, 5);
    expect(cpdTauxAibALaDate(fiches, 'AIB-5', DateTime(2027, 1, 1)).taux, 6);
    expect(m.collection('audit').toutes.first['action'], 'Création');
  });

  casM14('une version ARRÊTÉE ne se corrige pas sur place : refus nommé, rien n\'est écrit', (t) async {
    final m = magasinAib();
    await ouvrirM14(t, m, 'm12-aib');
    // triées par code : AIB-1, AIB-3, puis AIB-5 (la seule arrêtée)
    await toucherM14(t, find.byTooltip('Modifier').last);
    await saisir(t, 'taux', '6');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.textContaining('ne se corrige pas sur place'), findsOneWidget);
    expect(m.collection('baremeAIB').actives.firstWhere((f) => f['id'] == 'BAIB01')['taux'], 5);
  });

  casM14('un taux hors de 0 à 100 % est refusé', (t) async {
    final m = magasinAib();
    await ouvrirM14(t, m, 'm12-aib');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau'));
    await saisir(t, 'code', 'AIB-X');
    await saisir(t, 'categorie', 'Essai');
    await saisir(t, 'taux', '150');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.text('Le taux doit être compris entre 0 et 100 %.'), findsWidgets);
    expect(m.collection('baremeAIB').actives.length, 3);
  });

  casM14('archiver : motif obligatoire, annulable, jamais supprimé (RG-14) ; la version archivée ne s\'applique plus', (t) async {
    final m = magasinAib();
    await ouvrirM14(t, m, 'm12-aib');
    await toucherM14(t, find.byTooltip('Archiver').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
    expect(find.text('Le motif est obligatoire.'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'Version remplacée');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Archiver').last);
    expect(m.collection('baremeAIB').actives.length, 2);
    expect(m.collection('baremeAIB').toutes.length, 3, reason: 'rien n\'est supprimé');
    expect(find.text('Enregistrement archivé.'), findsOneWidget);
  });

  casM14('l\'onglet « Taux à une date » rend le taux EN VIGUEUR à la date choisie, et le motif quand rien ne s\'applique', (t) async {
    final m = magasinAib();
    await ouvrirM14(t, m, 'm12-aib');
    await toucherM14(t, find.text('Taux à une date'));
    expect(find.text('Taux en vigueur au 30/10/2026'), findsOneWidget);
    expect(find.text('Aucun taux'), findsNWidgets(2), reason: 'le 1 % et le 3 % ne sont pas arrêtés');
    expect(find.textContaining('Taux de 5 % arrêté, en vigueur depuis le 07/09/2026.'), findsOneWidget);
    expect(find.textContaining('n\'est pas arrêté'), findsWidgets);
  });

  casM14('l\'onglet « Taux à une date » : AVANT la première version arrêtée, aucun taux ne s\'applique et le motif nomme la date de prise d\'effet', (t) async {
    final m = magasinAib();
    await ouvrirM14(t, m, 'm12-aib');
    await toucherM14(t, find.text('Taux à une date'));
    await choisirDate(t, 'date', '09/06/2026');
    expect(find.text('Taux en vigueur au 06/09/2026'), findsOneWidget);
    expect(find.text('Aucun taux'), findsNWidgets(3));
    expect(find.textContaining('la première version prend effet à cette date'), findsOneWidget);
    await choisirDate(t, 'date', '09/07/2026');
    expect(find.text('Taux en vigueur au 07/09/2026'), findsOneWidget);
    expect(find.text('Aucun taux'), findsNWidgets(2));
  });

  casM14('lecture seule : « Nouveau », « Modifier » et « Archiver » sont ABSENTS', (t) async {
    final m = magasinAib();
    await ouvrirM14(t, m, 'm12-aib', role: 'comptable', donnees: donneesLectureSeule('comptable', 'm12-aib'));
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
  });

  casM14('la Direction LIT le barème sans y écrire ; un rôle clinique n\'y accède pas', (t) async {
    final m = magasinAib();
    await ouvrirM14(t, m, 'm12-aib', role: 'direction');
    expect(find.textContaining('ARRÊTÉ : 5 %'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    await ouvrirM14(t, m, 'm12-aib', role: 'caissier');
    expect(find.textContaining('ARRÊTÉ : 5 %'), findsNothing);
  });
}
