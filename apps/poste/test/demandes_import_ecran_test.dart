import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/selecteurs_import.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/sync/service_demandes_import.dart';

import 'aide_polices.dart';

/// LA FENÊTRE D'IMPORT SUR UN FILEUL (lot IMP-C, « option c » de la Direction du 12/11/2026) : un référentiel que la mère seule écrit s'enregistre AUSSITÔT chez le fileul, malgré la
/// garde « réglé sur la mère », ET une demande part à la mère ; la fenêtre le dit avant et après. Sur la MÈRE, l'import reste local et direct. Un jeu restreint ne propose aucune demande.
final donnees = DonneesNavigation.depuisDossier();

Magasin magasin() {
  final m = Magasin({'fournisseurs': const [], collectionLots: const [], 'audit': const [], 'patients': const []});
  // La garde « réglé sur la mère » que l'applicateur de configuration pose sur un fileul rattaché.
  m.collection('fournisseurs').garder((op, f) => 'Réglé sur la mère');
  return m;
}

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {required String role, bool fileul = true}) async {
  ServiceDemandesImport.de(m)
    ..fileulRattache = (() => fileul)
    ..etiquette = 'F1';
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: fileul ? ModePoste.fileul : ModePoste.mere, role: role), ecranInitial: ecran, magasin: m, horloge: () => DateTime(2026, 11, 12)));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

Uint8List csv(List<List<String>> lignes) => Uint8List.fromList(utf8.encode('﻿${[for (final l in lignes) l.map((x) => '"$x"').join(';')].join('\r\n')}\r\n'));

final entete = [for (final c in jeuFournisseurs.colonnes) c.label];
List<String> ligne(String code) => [for (final (i, _) in jeuFournisseurs.colonnes.indexed) i == 0 ? code : (i == 1 ? 'FOURNISSEUR $code' : '')];

void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
      await corps(t);
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    SelecteursImport.reinitialiser();
    ToastsSigh.viderPourTests();
  });

  cas('FILEUL : la fenêtre dit la double voie ; l\'import s\'écrit chez lui malgré la garde (fiches provisoires) ET une demande en attente est déposée', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm7-fournisseurs', role: 'comptable');
    await toucher(t, find.byKey(const Key('importer-fournisseurs')));
    expect(find.textContaining('qui reste seule autorité'), findsOneWidget, reason: 'la voie est dite AVANT l\'envoi');
    await toucher(t, find.byKey(const Key('import-vers-verification')));
    SelecteursImport.choisir = () async => FichierChoisi('f.csv', csv([entete, ligne('FIMP')]));
    await toucher(t, find.byKey(const Key('import-choisir-fichier')));
    await t.pump(const Duration(milliseconds: 300));
    await toucher(t, find.byKey(const Key('import-vers-import')));
    await toucher(t, find.byKey(const Key('import-ecrire')));
    expect(find.textContaining('Une demande est partie à la mère'), findsWidgets);
    final f = m.collection('fournisseurs').actives.single;
    expect(f['code'], 'FIMP');
    expect(f['provisoireMere'], true, reason: 'visible tout de suite, marqué provisoire');
    final d = m.collection(demandesImportCollection).toutes.single;
    expect(d['etat'], demandeImportEnAttente);
    expect(d['demandeRole'], 'comptable');
    expect(d['jeu'], 'fournisseurs');
  });

  cas('MÈRE : l\'import reste local et direct, aucune demande, aucune note de double voie, aucune fiche provisoire', (t) async {
    final m = Magasin({'fournisseurs': const [], collectionLots: const [], 'audit': const []});
    await ouvrir(t, m, 'm7-fournisseurs', role: 'comptable', fileul: false);
    await toucher(t, find.byKey(const Key('importer-fournisseurs')));
    expect(find.textContaining('qui reste seule autorité'), findsNothing);
    await toucher(t, find.byKey(const Key('import-vers-verification')));
    SelecteursImport.choisir = () async => FichierChoisi('f.csv', csv([entete, ligne('FLOC')]));
    await toucher(t, find.byKey(const Key('import-choisir-fichier')));
    await t.pump(const Duration(milliseconds: 300));
    await toucher(t, find.byKey(const Key('import-vers-import')));
    await toucher(t, find.byKey(const Key('import-ecrire')));
    expect(m.collection('fournisseurs').actives.single['provisoireMere'], isNull);
    expect(m.collection(demandesImportCollection).toutes, isEmpty);
  });

  cas('FILEUL, jeu RESTREINT : aucune demande n\'est proposée ni déposée (patients : activité restreinte, jamais par une demande)', (t) async {
    final m = magasin();
    final svc = ServiceDemandesImport.de(m)..fileulRattache = (() => true);
    expect(svc.passeParUneDemande(jeuPatients), isFalse);
    expect(svc.passeParUneDemande(jeuPersonnel), isFalse);
    expect(svc.reserveALaMere(jeuPersonnel), isTrue, reason: 'le personnel est restreint ET de la configuration de la mère : il se règle à la mère, le fileul le dit');
    await ouvrir(t, m, 'm1-patients', role: 'reception');
    await toucher(t, find.byKey(const Key('importer-patients')));
    expect(find.textContaining('qui reste seule autorité'), findsNothing);
  });
}
