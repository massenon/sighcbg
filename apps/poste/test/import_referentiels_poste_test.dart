import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/droits_import.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/import/selecteurs_import.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// LES SEPT JEUX DE RÉFÉRENTIELS AU POSTE (lot « jeux supplémentaires ») : le bouton « Importer » est posé par la fabrique unique (`actionsImporter`) sur l'écran de chaque référentiel, ABSENT
/// sans le droit de la matrice ; la fenêtre écrit la fiche de l'écran avec son journal ; la borne de taille se règle par jeu en base ; la garde d'exercice clos des budgets est au MOTEUR
/// du magasin (l'écran la subit comme le fichier).
final donnees = DonneesNavigation.depuisDossier();

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu)..utilisateur = 'Agent test';

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {required String role}) async {
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.fileul, role: role), ecranInitial: ecran, magasin: m, horloge: () => DateTime(2026, 11, 14, 10)));
  for (var i = 0; i < 6; i++) {
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

  // (écran hôte, jeu, rôle qui importe, rôle qui voit l'écran sans pouvoir importer)
  final hotes = [
    ('cfg-natures-facture', 'natures-facture', 'direction', 'dm'),
    ('cfg-centres-couts', 'centres-couts', 'da', 'medecin'),
    ('m5-unites', 'unites-labo', 'laborantin', 'medecin'),
    ('cfg-imagerie-catalogue', 'catalogue-imagerie', 'da', 'dm'),
    ('m10-prestataires', 'prestataires', 'da', 'direction'),
    ('m12-immobilisations', 'immobilisations', 'comptable', 'aide_comptable'),
    ('m12-budgets', 'budgets', 'comptable', 'direction'),
  ];

  for (final (ecran, id, role, sans) in hotes) {
    cas('$ecran : le bouton « Importer » (fabrique unique) est présent pour « $role », ABSENT pour « $sans » (jamais grisé)', (t) async {
      final m = jeu();
      await ouvrir(t, m, ecran, role: role);
      expect(find.byKey(Key('importer-$id')), findsOneWidget, reason: '$role importe $id');
      await ouvrir(t, jeu(), ecran, role: sans);
      expect(find.byKey(Key('importer-$id')), findsNothing, reason: '$sans n\'a pas le droit d\'importer $id');
      expect(find.widgetWithText(BoutonSigh, 'Importer'), findsNothing, reason: 'absent, jamais grisé');
    });
  }

  test('la matrice engendrée porte les sept écrans, le droit se lit de la matrice et de rien d\'autre', () {
    for (final j in [jeuNaturesFacture, jeuCentresCouts, jeuUnitesLabo, jeuCatalogueImagerie, jeuPrestataires, jeuImmobilisations, jeuBudgets]) {
      expect(donnees.matrice.droit('admin', j.ecran).editer, isTrue, reason: j.id);
      expect(donnees.matrice.droit('medecin', j.ecran).voir, isFalse, reason: j.id);
    }
  });

  cas('la fenêtre sur les natures de facture : un doublon refuse et consigne, puis le fichier valide écrit la fiche de l\'écran et journalise (RG-12)', (t) async {
    final m = jeu();
    final avant = m.collection('naturesFacture').actives.length;
    final ordreMax = m.collection('naturesFacture').actives.map((x) => (x['ordre'] as num?) ?? 0).reduce((a, b) => a > b ? a : b);
    final entete = ['Code', 'Nature de la facture', 'Secteur émetteur', 'Origine'];
    await ouvrir(t, m, 'cfg-natures-facture', role: 'da');
    await toucher(t, find.byKey(const Key('importer-natures-facture')));
    expect(find.byKey(const Key('imp-ignorer-existants')), findsNothing, reason: 'jamais d\'« ignorer les existants » sur une nature : une facture la porte');
    await toucher(t, find.byKey(const Key('import-vers-verification')));
    SelecteursImport.choisir = () async => FichierChoisi('n.csv', csv([entete, ['CONS', 'Autre consultation', 'Médecine générale', '']]));
    await toucher(t, find.byKey(const Key('import-choisir-fichier')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Fichier refusé. Rien n’a été écrit.'), findsOneWidget);
    expect(m.collection('naturesFacture').actives.length, avant);
    SelecteursImport.choisir = () async => FichierChoisi('n.csv', csv([entete, ['orth', 'Orthopédie', 'Chirurgie', '']]));
    await toucher(t, find.byKey(const Key('import-choisir-fichier')));
    await t.pump(const Duration(milliseconds: 300));
    await toucher(t, find.byKey(const Key('import-vers-import')));
    await toucher(t, find.byKey(const Key('import-ecrire')));
    expect(find.byKey(const Key('import-resultat')), findsOneWidget);
    final neuve = m.collection('naturesFacture').actives.firstWhere((x) => x['code'] == 'ORTH');
    expect([neuve['libelle'], neuve['secteur'], neuve['ordre']], ['Orthopédie', 'Chirurgie', ordreMax + 1]);
    expect(m.collection('audit').toutes.where((a) => a['action'] == 'Import').length, 1, reason: 'RG-12');
    expect(m.collection(collectionLots).actives.where((l) => l['etat'] == 'refuse'), hasLength(1));
    expect(m.collection(collectionLots).actives.where((l) => l['etat'] == 'applique'), hasLength(1));
  });

  test('la borne de taille se règle PAR JEU dans les réglages : défaut 512 Ko, valeur de la clinique sinon', () {
    final m = jeu();
    for (final j in [jeuNaturesFacture, jeuCentresCouts, jeuUnitesLabo, jeuCatalogueImagerie, jeuPrestataires, jeuImmobilisations, jeuBudgets]) {
      expect(octetsMaxDe(m, j), octetsMaxImportCourt, reason: j.id);
    }
    m.collection('reglages').inserer({'id': cleReglageOctetsMax('budgets'), 'statut': 'actif', 'valeur': 4096});
    expect(octetsMaxDe(m, jeuBudgets), 4096);
    expect(octetsMaxDe(m, jeuImmobilisations), octetsMaxImportCourt, reason: 'un autre jeu garde son défaut');
  });

  test('LA GARDE DES BUDGETS EST AU MOTEUR : un exercice clos refuse l\'écriture (écran ou fichier), un exercice ouvert l\'accepte ; lecture et archivage du clos aussi refusés', () {
    final m = jeu();
    final budgets = m.collection('budgets');
    expect(() => budgets.inserer({'id': 'BUD-X', 'reference': 'BG-2025-001', 'exercice': 2025, 'centreCout': 'laboratoire', 'nature': 'Investissements', 'prevu': 10, 'statut': 'actif'}, prefixe: 'BUD'),
        throwsA(isA<EcritureRefusee>().having((e) => '$e', 'motif nommé', contains('clôturé'))));
    expect(budgets.toutes.where((b) => b['id'] == 'BUD-X'), isEmpty, reason: 'rien n\'est écrit');
    final ok = budgets.inserer({'id': 'BUD-Y', 'reference': 'BG-2027-001', 'exercice': 2027, 'centreCout': 'laboratoire', 'nature': 'Investissements', 'prevu': 10, 'statut': 'actif'}, prefixe: 'BUD');
    expect(ok.fiche['id'], 'BUD-Y');
    // Un exercice clôturé après coup ferme aussi la modification et l'archivage de ce budget (la garde relit les exercices à CHAQUE écriture).
    m.collection('exercices').inserer({'id': 'EXO27', 'annee': 2027, 'etat': 'clos', 'statut': 'actif'}, prefixe: 'EXO');
    expect(() => budgets.mettreAJour('BUD-Y', {'prevu': 20}), throwsA(isA<EcritureRefusee>()));
    expect(() => budgets.archiver('BUD-Y'), throwsA(isA<EcritureRefusee>()));
  });

  test('l\'import de budgets passe par le port du poste : exercice clos refusé à la VÉRIFICATION en le nommant, exercice ouvert écrit sous la référence BG-AAAA-NNN', () {
    final m = jeu();
    PortMagasin port() => PortMagasin(m, aujourdhui: () => DateTime(2026, 11, 14), nomAgent: 'Agent test', profil: const ProfilImport.accordeTout());
    final centre = m.collection('centresCouts').actives.first;
    List<List<Object?>> fichier(int exercice) => [
          [for (final c in jeuBudgets.colonnes) c.label],
          [exercice, '${centre['code']}', 'Investissements', 1234000],
        ];
    final clos = analyserLignes(jeuBudgets, fichier(2025), 'b.xlsx', port());
    expect(clos.accepte, isFalse);
    expect(clos.problemes.map((p) => p.code), contains('EXERCICE_CLOS'));
    final a = analyserLignes(jeuBudgets, fichier(2027), 'b.xlsx', port());
    expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) p.code]}');
    final r = appliquer(jeuBudgets, a, port());
    expect(r.ok, isTrue, reason: '${r.code} ${r.motif}');
    final b = m.collection('budgets').actives.firstWhere((x) => x['lotImport'] == r.lot!['reference']);
    expect([b['reference'], b['exercice'], b['centre'], b['prevu']], ['BG-2027-001', 2027, centre['libelle'], 1234000]);
    expect(b['id'], startsWith('BUD'), reason: 'préfixe d\'identifiant aligné sur l\'écran');
  });
}
