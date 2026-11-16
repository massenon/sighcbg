// Les écrans de la lecture OCR et de la correction signée (lots OCR-prep et OCR-C) : l'état d'une pièce, la commande « Corriger le texte lu » (ABSENTE sans le droit d'éditer ou sans le droit de
// lire le type), le texte machine conservé à l'historique, le réglage décidé à la mère (un fileul le lit, ne le modifie pas, et dit quand le moteur choisi lui manque).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/documents/ocr_poste.dart';
import 'package:sigh_poste/documents/panneau_scan.dart';
import 'package:sigh_poste/documents/service_fichiers.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_sync/sigh_sync.dart';

import 'aide_polices.dart';
import 'documents_scans_test.dart' show courrier, docu, magasin, png, tester;

final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 11, 14, 10);
const texteLu = 'Ordonnance amoxicilline 500 mg deux fois par jour';

void main() {
  late Directory tmp;
  late StockFichiers stock;
  setUpAll(chargerPolices);
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sigh-ocr-ecrans-');
    stock = StockFichiers('${tmp.path}/scans');
    SelecteursScan.reinitialiser();
  });
  tearDown(() {
    SelecteursScan.reinitialiser();
    ToastsSigh.viderPourTests();
    tmp.deleteSync(recursive: true);
  });

  ({Magasin m, ServiceFichiers s, OcrPoste o}) poste(Map<String, List<Fiche>> jeux, {bool mere = true, bool moteur = true, bool actif = true}) {
    final m = magasin(jeux);
    m.horloge = () => auj;
    m.utilisateur = 'Awa EXEMPLE';
    final s = ServiceFichiers.de(m);
    s.stockagePour = (_) => stock;
    s.lireInfo = () async => {'dossier': stock.dossier, 'fichiers': stock.nombre};
    final o = OcrPoste(m, estMere: () => mere)
      ..automatique = false
      ..accesCourant = (() => (c) => true)
      ..installer();
    if (moteur) o.enregistrer(MoteurOcrFactice(texteParDefaut: texteLu));
    if (actif && moteur) o.definirReglage(peutRegler: true, actif: true, moteur: 'factice', langue: 'fra', motif: 'essai');
    if (!mere) s.changerDossierMere = null;
    return (m: m, s: s, o: o);
  }

  Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, String role) async {
    t.view.physicalSize = const Size(1600, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(SighPoste(key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.fileul, role: role), ecranInitial: ecran, magasin: m, horloge: () => auj));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> toucher(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('sans moteur : le panneau du scan dit « aucun moteur d’OCR installé sur ce poste », pas de relance, pas de correction', (t) async {
    final p = poste({'courriers': [courrier('C1', 'ARR-2026-0042')]}, moteur: false);
    await p.s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.png', octets: png);
    await ouvrir(t, p.m, 'm13-courriers', 'direction');
    await toucher(t, find.byTooltip('Voir le scan'));
    expect(find.byKey(const Key('ocr:etat-non_indexe')), findsOneWidget);
    expect(find.textContaining('aucun moteur d’OCR installé sur ce poste'), findsWidgets);
    expect(find.byKey(const Key('ocr:relancer')), findsNothing);
    expect(find.byKey(const Key('ocr:corriger')), findsNothing);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('lu par machine : marqué « à vérifier » ; avec le droit, « Corriger le texte lu » ouvre une modale, la correction est signée, le texte machine reste à l’historique', (t) async {
    final p = poste({'courriers': [courrier('C1', 'ARR-2026-0042')]});
    await p.s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.png', octets: png);
    p.m.horloge = () => DateTime(2026, 11, 14, 8); // la machine a lu le matin ; la correction viendra à l'heure de la session (10 h)
    await p.o.vider();
    await ouvrir(t, p.m, 'm13-courriers', 'direction');
    await toucher(t, find.byTooltip('Voir le scan'));
    expect(find.byKey(const Key('ocr:etat-ocr_indexe')), findsOneWidget);
    expect(find.byKey(const Key('ocr:marque')), findsOneWidget);
    expect(find.byKey(const Key('ocr:corriger')), findsOneWidget);
    await toucher(t, find.byKey(const Key('ocr:corriger')));
    expect(find.byKey(const Key('ocr:correction-note')), findsOneWidget);
    // un texte inchangé n'est pas une correction : refus nommé dans la modale
    await toucher(t, find.byKey(const Key('ocr:correction-enregistrer')));
    expect(find.byKey(const Key('ocr:correction-refus')), findsOneWidget);
    expect(find.textContaining('AUCUN_CHANGEMENT'), findsOneWidget);
    await t.enterText(find.byKey(const Key('ocr:correction-texte')), 'Ordonnance amoxicilline 250 mg trois fois par jour');
    await t.enterText(find.byKey(const Key('ocr:correction-motif')), 'dosage lu de travers');
    await toucher(t, find.byKey(const Key('ocr:correction-enregistrer')));
    final sha = docSha256(png);
    expect(p.o.versionsDe(sha), hasLength(2));
    expect(find.byKey(const Key('ocr:etat-ocr_corrige')), findsOneWidget);
    final auteur = '${p.o.versionCourante(sha)!['corrigePar']}';
    expect(auteur, isNotEmpty, reason: 'la correction est signée de l’agent de la session');
    expect(p.o.versionCourante(sha)!['corrigePar'], p.m.utilisateur);
    expect(find.textContaining('Texte corrigé par $auteur'), findsWidgets);
    expect(find.byKey(const Key('ocr:marque')), findsNothing, reason: 'plus « à vérifier » : une personne l’a relu');
    expect(find.byKey(const Key('ocr:corrige')), findsOneWidget);
    // l'historique lisible : la version humaine est la courante, le texte machine reste lisible
    await toucher(t, find.byKey(const Key('ocr:historique-2')));
    expect(find.textContaining('Version 2 (courante) : corrigée par $auteur'), findsOneWidget);
    expect(find.textContaining('lue par machine (factice)'), findsOneWidget);
    expect(find.textContaining('dosage lu de travers'), findsWidgets);
    expect(tester(t, 'ocr:texte-1'), texteLu, reason: 'le texte machine est conservé');
    expect(tester(t, 'ocr:texte-2'), 'Ordonnance amoxicilline 250 mg trois fois par jour');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('droits : sans le droit d’éditer l’écran, la commande « Corriger le texte lu » est ABSENTE (non grisée) ; l’état et l’historique restent lisibles', (t) async {
    final p = poste({'documentsPatient': [docu('D1', 'GED-00001', 'Pièce d’identité')]});
    await p.s.deposer(famille: docFamillePatient, ficheId: 'D1', nomOrigine: 'o.png', octets: png);
    await p.o.vider();
    // lecture seule sur l'écran des documents patient
    await ouvrir(t, p.m, 'm1-documents', 'anesthesiste');
    await toucher(t, find.byTooltip('Prévisualiser'));
    expect(find.byKey(const Key('ocr:etat-ocr_indexe')), findsOneWidget);
    expect(find.byKey(const Key('ocr:corriger')), findsNothing);
    expect(find.byKey(const Key('ocr:relancer')), findsNothing);
    expect(find.byKey(const Key('ocr:historique-1')), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('zone 2 : un profil qui ne lit pas le type du document ne voit RIEN du texte lu (ni état, ni historique, ni correction)', (t) async {
    final p = poste({'documentsPatient': [docu('D1', 'GED-00001', 'Pièce d’identité')]});
    await p.s.deposer(famille: docFamillePatient, ficheId: 'D1', nomOrigine: 'o.png', octets: png);
    await p.o.vider();
    // le même document, requalifié compte rendu médical : l'accueil n'en lit plus le type
    p.m.collection('documentsPatient').mettreAJour('D1', {'type': 'Compte rendu médical'}, journaliser: false);
    await ouvrir(t, p.m, 'm1-documents', 'medecin');
    await toucher(t, find.byTooltip('Prévisualiser'));
    expect(find.byKey(const Key('ocr:etat-ocr_indexe')), findsOneWidget, reason: 'le médecin lit la zone clinique');
    await ouvrir(t, p.m, 'm1-documents', 'reception');
    expect(find.text('GED-00001'), findsNothing, reason: 'l’accueil ne voit même pas la ligne : la pièce est réservée');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('Paramètres système › Scans numérisés : la mère règle la lecture (moteur, délai, motif) ; un fileul LIT le réglage, ne le modifie pas, et dit quand son moteur manque', (t) async {
    final p = poste({}, actif: false);
    p.s.changerDossierMere = (d) async => {'nouveau': d, 'ancien': stock.dossier, 'copies': 0};
    await ouvrir(t, p.m, 'cfg-systeme', 'admin');
    await toucher(t, find.text('Scans numérisés'));
    expect(find.byKey(const Key('ocr:carte-reglage')), findsOneWidget);
    expect(tester(t, 'ocr:reglage-etat'), startsWith('Lecture désactivée'));
    await toucher(t, find.byKey(const Key('ocr:bouton-reglage')));
    await toucher(t, find.byKey(const Key('ocr:actif')));
    await toucher(t, find.byKey(const Key('ocr:enregistrer')));
    expect(find.byKey(const Key('ocr:reglage-refus')), findsOneWidget, reason: 'sans motif : refus nommé');
    await t.enterText(find.byKey(const Key('ocr:delai')), '45');
    await t.enterText(find.byKey(const Key('ocr:motif')), 'mise en service');
    await toucher(t, find.byKey(const Key('ocr:moteur')));
    await toucher(t, find.textContaining('Moteur factice de test').last);
    await toucher(t, find.byKey(const Key('ocr:enregistrer')));
    final r = p.o.reglage;
    expect(r.actif, isTrue, reason: '${p.m.collection('reglagesOcr').toutes}');
    expect(r.delaiMs, 45000);
    expect(r.moteur, 'factice');
    await t.pump(const Duration(seconds: 10));

    // un FILEUL : le réglage reçu de la mère se lit, la commande est absente, et le moteur choisi qui manque est dit
    final f = poste({}, mere: false, moteur: false, actif: false);
    f.m.collection('reglagesOcr').appliquerDistante({'id': 'ocr', 'actif': true, 'moteur': 'tesseract-local', 'langue': 'fra', 'delaiMs': 60000, 'reglePar': 'Administrateur', 'regleLe': '2026-11-14T08:00:00.000Z', 'motif': 'essai'});
    await ouvrir(t, f.m, 'cfg-systeme', 'admin');
    await toucher(t, find.text('Scans numérisés'));
    expect(tester(t, 'ocr:reglage-etat'), 'Lecture activée');
    expect(find.textContaining('tesseract-local'), findsWidgets);
    expect(find.byKey(const Key('ocr:bouton-reglage')), findsNothing);
    expect(find.byKey(const Key('ocr:reglage-lecture-seule')), findsOneWidget);
    expect(find.byKey(const Key('ocr:moteur-indisponible')), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });
}
