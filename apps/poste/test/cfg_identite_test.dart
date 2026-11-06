import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/identite_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

typedef M = Map<String, Object?>;
M obj(Object? o) => (o as Map).cast<String, Object?>();
final v = obj(jsonDecode(File('../../packages/domaine/test/vecteurs/cfg.json').readAsStringSync()));
String s(Object? x) => '$x'.replaceAll(RegExp(r'[\s  ]'), '');

/// cfg-branding et cfg-entetes : l'identité légale est UNIQUE. Les règles (valeurs, grille, pied) sont rejouées sur les vecteurs de la maquette
/// (packages/domaine/test/cfa_regles_test.dart) ; ici, l'ÉCRAN — les champs, l'enregistrement journalisé (RG-12), le refus nommé, le dépôt d'une
/// ressource (conservée dans le poste), son retrait (archivage annulable) et les droits.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);
  tearDown(IdentiteClinique.reinitialiser);
  final b = obj(v['branding']);

  casM14('cfg-entetes : un IFU, un RCCM, une autorisation ; la grille de l’identité et la note des pièces anciennes', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-entetes');
    for (final k in (obj(v['entetes'])['kpis'] as List).cast<List>()) {
      expect(find.text('${k[0]}'), findsWidgets, reason: '${k[0]}');
      if (k[2] != null) expect(find.text('${k[2]}'), findsWidgets, reason: '${k[2]}');
    }
    expect(find.text('Identité légale imprimée sur chaque état'), findsOneWidget);
    expect(find.text(IdentiteClinique.ifu), findsWidgets);
    expect(find.text(IdentiteClinique.rccm), findsWidgets);
    // Les mentions que la Direction n'a pas encore saisies le DISENT à l'écran (la pièce, elle, ne les imprime pas).
    expect(find.text(cfaMentionARenseigner), findsWidgets);
    expect(find.textContaining('Non imprimée — Non applicable'), findsOneWidget);
    expect(find.textContaining('Un document ancien qui diverge du présent en-tête n’est donc pas un faux.'), findsOneWidget);
    // Lecture pure : aucune commande d'écriture.
    expect(find.widgetWithText(BoutonSigh, 'Enregistrer'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  casM14('cfg-branding : les 14 champs de la maquette, plus le nom court et la formule de politesse, préremplis de l’identité en vigueur ; trois cartes', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-branding');
    for (final c in [...(b['champs'] as Map).keys, 'nomCourt', 'formulePolitesse']) {
      expect(find.byKey(Key('kit:champ:$c')), findsOneWidget, reason: '$c');
    }
    for (final c in ['Paramètres de l’identité', 'Aperçu du papier à en-tête', 'Ressources graphiques']) {
      expect(find.text(c), findsOneWidget, reason: c);
    }
    expect(find.widgetWithText(BoutonSigh, 'Enregistrer'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Prévisualiser un état'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Déposer une ressource'), findsOneWidget);
    expect(find.text('À fournir'), findsNWidgets(5));
    expect(find.textContaining('Réf. CBG-XXXXXXXX-0001'), findsOneWidget);
    // Les valeurs affichées sont celles du vecteur.
    final champs = obj(b['champs']);
    final nom = t.widget<TextField>(find.descendant(of: find.byKey(const Key('kit:champ:nom')), matching: find.byType(TextField)));
    expect(nom.controller!.text, champs['nom']);
    final ifu = t.widget<TextField>(find.descendant(of: find.byKey(const Key('kit:champ:ifu')), matching: find.byType(TextField)));
    expect(ifu.controller!.text, champs['ifu']);
  });

  casM14('« Enregistrer » journalise la modification (RG-12) et le dit ; un nom ou un IFU vide est REFUSÉ, rien n’est journalisé', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-branding');
    final avant = m.collection('audit').toutes.length;
    await saisir(t, 'ifu', '');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
    expect(m.collection('audit').toutes.length, avant);
    await t.pump(const Duration(seconds: 10));
    await saisir(t, 'ifu', '3201001996110');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.text('Identité enregistrée.'), findsOneWidget);
    // L'identité est écrite dans le magasin (fiche IDENTITE de `ressources`) : la collection journalise la création.
    expect(m.collection('audit').toutes.length, avant + 1);
    final j = m.collection('audit').toutes.first;
    expect([j['action'], j['module'], j['entite'], j['reference']], ['Création', 'CFG', 'ressources', idFicheIdentite]);
    expect(j['utilisateur'], isNotEmpty);
    // Un second enregistrement MODIFIE la fiche, avec les valeurs avant et après (RG-12).
    await t.pump(const Duration(seconds: 10));
    await saisir(t, 'forme', 'SARL');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final j2 = m.collection('audit').toutes.first;
    expect([j2['action'], j2['entite'], j2['reference']], ['Modification', 'ressources', idFicheIdentite]);
    expect('${j2['apres']}', contains('SARL'));
    expect(m.collection('ressources').actives.where((f) => f['id'] == idFicheIdentite).length, 1, reason: 'une seule fiche d’identité');
  });

  casM14('enregistrer met à jour la BASE et TOUTES les pièces : la valeur saisie est imprimée, une mention vide ne l’est pas', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-branding');
    // État initial : autorisation et forme VIDES ; la formule de politesse vaut le slogan (décision du 06/11/2026) ;
    // l'aperçu n'a aucune ligne « AUTORISATION D'OUVERTURE ».
    String champ(String c) =>
        t.widget<TextField>(find.descendant(of: find.byKey(Key('kit:champ:$c')), matching: find.byType(TextField))).controller!.text;
    expect([champ('forme'), champ('autorisation')], ['', '']);
    expect(champ('formulePolitesse'), 'Votre bien-être est notre raison d’être.');
    expect(find.textContaining('AUTORISATION D’OUVERTURE'), findsNothing);
    await saisir(t, 'autorisation', 'N° 012/MS/DNSP/2009');
    await saisir(t, 'formulePolitesse', 'MERCI DE VOTRE CONFIANCE');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    // La base : la fiche porte les valeurs saisies.
    final f = m.collection('ressources').parId(idFicheIdentite)!;
    expect((f['identite'] as Map)['autorisation'], 'N° 012/MS/DNSP/2009');
    expect((f['identite'] as Map)['formulePolitesse'], 'MERCI DE VOTRE CONFIANCE');
    // L'identité imprimée : toutes les pièces lisent IdentiteClinique.
    expect(IdentiteClinique.autorisation, 'N° 012/MS/DNSP/2009');
    expect(IdentiteClinique.lignesEnTete, contains('AUTORISATION D’OUVERTURE N° 012/MS/DNSP/2009'));
    await t.pump();
    expect(find.text('AUTORISATION D’OUVERTURE N° 012/MS/DNSP/2009'), findsOneWidget, reason: 'l’aperçu suit l’enregistrement');
    // Vider la mention : elle cesse d'être imprimée.
    await t.pump(const Duration(seconds: 10));
    await saisir(t, 'autorisation', '');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    await t.pump();
    expect(IdentiteClinique.autorisation, '');
    expect(find.textContaining('AUTORISATION D’OUVERTURE'), findsNothing);
    // Archiver la fiche (corbeille, RG-14) rend l'identité initiale.
    m.collection('ressources').archiver(idFicheIdentite);
    appliquerIdentite(m);
    expect(IdentiteClinique.formulePolitesse, '');
  });

  casM14('« Prévisualiser un état » ouvre le papier à en-tête avec les sept mentions', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-branding');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Prévisualiser un état'));
    expect(find.text('Aperçu du papier à en-tête'), findsWidgets);
    expect(find.textContaining('Modèle appliqué à tous les documents édités'), findsWidgets);
    expect(find.textContaining('TAKI Alimatou'), findsWidgets);
  });

  casM14('dépôt d’une ressource : le fichier est CONSERVÉ dans le poste, la ligne passe à « Déposé » ; remplacer archive l’ancien ; retirer archive (RG-14)', (t) async {
    final m = magasinM14();
    final dossier = Directory.systemTemp.createTempSync('cfa_res');
    addTearDown(() => dossier.deleteSync(recursive: true));
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final f1 = File('${dossier.path}/logo.png')..writeAsBytesSync(png);
    await ouvrirM14(t, m, 'cfg-branding');
    await toucherM14(t, find.byTooltip('Déposer').first);
    await saisir(t, 'chemin', f1.path);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Déposer').last);
    final col = m.collection('ressources');
    expect(col.actives.length, 1);
    final r = col.actives.first;
    expect([r['type'], r['libelle'], r['fichier'], r['taille']], ['logo', 'Logo principal', 'logo.png', png.length]);
    expect('${r['donnees']}', startsWith('data:image/png;base64,'));
    expect(find.text('Déposé'), findsOneWidget);
    expect(find.text('À fournir'), findsNWidgets(4));
    expect(find.textContaining('Ressource « Logo principal » enregistrée.'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    // Remplacer : l'ancienne est archivée, la nouvelle devient la ressource.
    final f2 = File('${dossier.path}/logo2.jpg')..writeAsBytesSync(png);
    await toucherM14(t, find.byTooltip('Remplacer').first);
    await saisir(t, 'chemin', f2.path);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Remplacer').last);
    expect(col.actives.length, 1);
    expect(col.archivees.length, 1);
    expect(col.actives.first['fichier'], 'logo2.jpg');
    await t.pump(const Duration(seconds: 10));
    // Retirer : confirmation, archivage annulable, jamais de suppression.
    await toucherM14(t, find.byTooltip('Retirer').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Retirer').last);
    expect(col.actives, isEmpty);
    expect(col.toutes.length, 2);
    expect(find.text('Ressource retirée.'), findsOneWidget);
  });

  casM14('dépôt refusé EN LE NOMMANT : fichier introuvable, fichier qui n’est pas une image — rien n’est conservé', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-branding');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Déposer une ressource'));
    await saisir(t, 'libelle', 'Cachet');
    await saisir(t, 'chemin', '/n/existe/pas.png');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Déposer').last);
    expect(find.textContaining('Fichier introuvable'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    await saisir(t, 'chemin', '/tmp/notes.txt');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Déposer').last);
    expect(find.textContaining('Choisir un fichier image'), findsOneWidget);
    expect(m.collection('ressources').toutes, isEmpty);
  });

  casM14('droits : en lecture seule, Enregistrer et Déposer sont ABSENTS (jamais grisés) ; la prévisualisation reste', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-branding', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-branding'));
    expect(find.widgetWithText(BoutonSigh, 'Enregistrer'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Déposer une ressource'), findsNothing);
    expect(find.byTooltip('Déposer'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Prévisualiser un état'), findsOneWidget);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
  });
}
