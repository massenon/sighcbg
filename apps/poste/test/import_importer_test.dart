import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/droits_import.dart';
import 'package:sigh_poste/import/selecteurs_import.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// `K.importer` : le bouton « Importer » des écrans métier et sa fenêtre en trois étapes (modèle, vérification, import). Décisions de la Direction du 11/11/2026 :
/// le droit d'importer est un droit de la matrice DISTINCT du droit d'écrire (la commande est ABSENTE sans lui) ; « ignorer les existants » n'est offert que sur
/// quatre jeux ; l'historique des lots ne montre que les lots de l'agent, sauf à qui arbitre (DAF, administrateur) ; la borne de taille se règle par jeu.
final donnees = DonneesNavigation.depuisDossier();

Magasin magasin({List<Map<String, Object?>> lots = const []}) => Magasin({
      'emplacements': [
        {'id': 'E1', 'code': 'A1', 'libelle': 'Rayon A1', 'zone': 'Rayonnage sec', 'statut': 'actif'}
      ],
      'produits': const [],
      'lots': const [],
      collectionLots: lots,
      'audit': const [],
    });

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {required String role}) async {
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => DateTime(2026, 11, 1)));
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

final entete = ['Code du casier', 'Intitulé', 'Zone', 'Température de conservation', 'Capacité (références)'];

Future<void> choisir(WidgetTester t, String nom, Uint8List octets) async {
  SelecteursImport.choisir = () async => FichierChoisi(nom, octets);
  await toucher(t, find.byKey(const Key('import-choisir-fichier')));
  await t.pump(const Duration(milliseconds: 300));
}

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

  cas('le bouton « Importer » est ABSENT sans le droit d\'importer le jeu (matrice), présent avec', (t) async {
    // Le médecin voit l'écran des emplacements mais n'a pas le droit d'importer ; le gestionnaire de stock l'a.
    await ouvrir(t, magasin(), 'm6-etiquetage', role: 'medecin');
    expect(find.byKey(const Key('importer-emplacements')), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Importer'), findsNothing, reason: 'absent, jamais grisé');
    await ouvrir(t, magasin(), 'm6-etiquetage', role: 'stock');
    expect(find.byKey(const Key('importer-emplacements')), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Importer'), findsOneWidget);
  });

  cas('un droit d\'importer n\'est pas un droit d\'écrire : le droit se lit sur l\'écran du JEU, aucun nom de rôle n\'est en dur', (t) async {
    // La direction écrit au référentiel produits en lecture seule, l'agent administratif importe les courriers sans écrire ailleurs : la matrice décide.
    await ouvrir(t, magasin(), 'm13-courriers', role: 'reception');
    expect(find.byKey(const Key('importer-courriers')), findsNothing);
    await ouvrir(t, magasin(), 'm13-courriers', role: 'agentadmin');
    expect(find.byKey(const Key('importer-courriers')), findsOneWidget);
  });

  cas('la fenêtre : trois étapes, rien n\'est écrit à la vérification ; sans « ignorer », l\'existant est un refus nommé qui consigne le fichier', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm6-etiquetage', role: 'stock');
    await toucher(t, find.byKey(const Key('importer-emplacements')));
    for (final k in ['import-etape-1', 'import-etape-2', 'import-etape-3']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(find.byKey(const Key('import-modele-xlsx')), findsOneWidget);
    await toucher(t, find.byKey(const Key('import-vers-verification')));
    await choisir(t, 'e.csv', csv([entete, ['A1', 'Autre', 'Réserve', '', ''], ['B1', 'Rayon B1', 'Réserve', 'Ambiante', '12']]));
    expect(find.textContaining('Fichier refusé. Rien n’a été écrit.'), findsOneWidget);
    expect(find.textContaining('existe déjà'), findsWidgets);
    expect(find.byKey(const Key('import-vers-import')), findsNothing, reason: 'aucun passage à l\'import sur un fichier refusé');
    expect(m.collection('emplacements').toutes.length, 1, reason: 'rien n\'est écrit à la vérification');
    expect(m.collection(collectionLots).actives.single['etat'], 'refuse');
  });

  cas('« ignorer les existants » : la ligne existante est listée et ignorée, l\'autre est importée, le lot garde les rangs ignorés', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm6-etiquetage', role: 'stock');
    await toucher(t, find.byKey(const Key('importer-emplacements')));
    await toucher(t, find.byKey(const Key('import-vers-verification')));
    await toucher(t, find.byKey(const Key('imp-ignorer-existants')));
    await choisir(t, 'e.csv', csv([entete, ['A1', 'Autre', 'Réserve', '', ''], ['B1', 'Rayon B1', 'Réserve', 'Ambiante', '12']]));
    expect(find.textContaining('Vérification conforme. 1 ligne(s) peuvent être écrites.'), findsOneWidget);
    expect(find.byKey(const Key('import-lignes-ignorees')), findsOneWidget);
    expect(find.textContaining('Lignes ignorées, la fiche existe déjà : 2.'), findsOneWidget);
    expect(m.collection('emplacements').toutes.length, 1);
    await toucher(t, find.byKey(const Key('import-vers-import')));
    await toucher(t, find.byKey(const Key('import-ecrire')));
    expect(find.byKey(const Key('import-resultat')), findsOneWidget);
    expect(find.textContaining('1 fiche(s) écrite(s), 1 ligne(s) ignorée(s)'), findsWidgets);
    final emp = m.collection('emplacements').actives;
    expect(emp.map((e) => e['code']), containsAll(['A1', 'B1']));
    expect(emp.firstWhere((e) => e['code'] == 'A1')['libelle'], 'Rayon A1', reason: 'l\'existant n\'est pas modifié');
    final lot = m.collection(collectionLots).actives.single;
    expect(lot['etat'], 'applique');
    expect(lot['ignores'], [2]);
    expect(m.collection('audit').toutes.where((a) => a['action'] == 'Import').length, 1, reason: 'RG-12 : le lot est journalisé');
  });

  cas('sur les patients, la fenêtre n\'offre PAS « ignorer les existants »', (t) async {
    await ouvrir(t, Magasin({'patients': const [], collectionLots: const [], 'audit': const []}), 'm1-patients', role: 'reception');
    await toucher(t, find.byKey(const Key('importer-patients')));
    await toucher(t, find.byKey(const Key('import-vers-verification')));
    expect(find.byKey(const Key('imp-ignorer-existants')), findsNothing);
    expect(find.text('Code dossier'), findsNothing, reason: 'RG-01 : le code n\'est jamais fourni par le fichier');
    expect(find.text('Groupe sanguin'), findsNothing);
  });

  cas('la borne de taille se règle PAR JEU dans les réglages : au-delà, le fichier est refusé en disant la borne', (t) async {
    final m = magasin();
    m.collection('reglages').inserer({'id': cleReglageOctetsMax('emplacements'), 'statut': 'actif', 'valeur': 40});
    await ouvrir(t, m, 'm6-etiquetage', role: 'stock');
    await toucher(t, find.byKey(const Key('importer-emplacements')));
    await toucher(t, find.byKey(const Key('import-vers-verification')));
    await choisir(t, 'e.csv', csv([entete, ['B1', 'Rayon B1', 'Réserve', 'Ambiante', '12']]));
    expect(find.textContaining('au-delà de la borne'), findsOneWidget);
    expect(m.collection('emplacements').toutes.length, 1);
    expect(octetsMaxDe(m, jeuProduits), octetsMaxImportDefaut, reason: 'un jeu sans réglage garde sa borne par défaut');
    expect(octetsMaxDe(m, jeuPatients), octetsMaxImportPatients);
  });

  cas('l\'historique des lots : l\'auteur lit les siens ; qui arbitre (DAF) les lit tous ; jamais une valeur de cellule', (t) async {
    final moi = agentDemonstration('stock', nom: donnees.matrice.libelle('stock') ?? 'stock').nom;
    List<Map<String, Object?>> lots() => [
          {'id': 'L1', 'reference': 'IMP-2026-001', 'jeu': 'emplacements', 'jeuLibelle': 'Importation des emplacements', 'fichier': 'a.csv', 'date': '2026-10-30', 'par': moi, 'etat': 'applique', 'nbLignes': 3, 'ecrits': const [], 'statut': 'actif'},
          {'id': 'L2', 'reference': 'IMP-2026-002', 'jeu': 'courriers', 'jeuLibelle': 'Importation du registre des courriers', 'fichier': 'b.csv', 'date': '2026-10-31', 'par': 'UNE AUTRE PERSONNE', 'etat': 'refuse', 'nbLignes': 5, 'ecrits': const [], 'erreurs': [{'n': 2, 'colonne': 'Date', 'code': 'TYPE_INVALIDE', 'niveau': 'refus', 'geste': 'Corrigez la date.'}], 'statut': 'actif'},
        ];
    await ouvrir(t, magasin(lots: lots()), 'imp-accueil', role: 'stock');
    await toucher(t, find.text('Historique des lots'));
    expect(find.text('IMP-2026-001'), findsOneWidget);
    expect(find.text('IMP-2026-002'), findsNothing, reason: 'le lot d\'un autre n\'est pas lisible par qui n\'arbitre pas');
    await ouvrir(t, magasin(lots: lots()), 'imp-accueil', role: 'da');
    await toucher(t, find.text('Historique des lots'));
    expect(find.text('IMP-2026-001'), findsOneWidget);
    expect(find.text('IMP-2026-002'), findsOneWidget);
  });

  cas('un comptage importé est REPRIS à la feuille d\'inventaire, jamais régularisé tout seul : la validation reste un geste humain', (t) async {
    final m = Magasin({
      'produits': [
        {'id': 'P1', 'code': 'PARA500', 'designation': 'PARACETAMOL 500 MG', 'unite': 'Boîte', 'categorie': 'medicament', 'cump': 100, 'stockGros': 50, 'stockDetail': 0, 'stock': 50, 'statut': 'actif'}
      ],
      'comptagesInventaire': [
        {'id': 'C1', 'lot': 'IMP-2026-001', 'magasin': 'gros', 'produitId': 'P1', 'code': 'PARA500', 'designation': 'PARACETAMOL 500 MG', 'physique': 47, 'regularise': false, 'statut': 'actif'},
        {'id': 'C2', 'lot': 'IMP-2026-002', 'magasin': 'detail', 'produitId': 'P1', 'code': 'PARA500', 'designation': 'PARACETAMOL 500 MG', 'physique': 9, 'regularise': false, 'statut': 'actif'},
      ],
      'inventaires': const [],
      'mouvements': const [],
      'audit': const [],
    });
    await ouvrir(t, m, 'm6-inventaire-feuille', role: 'stock');
    expect(find.textContaining('1 quantité(s) reprise(s) du comptage importé (lot IMP-2026-001)'), findsOneWidget, reason: 'le comptage du détail n\'est pas repris sur une feuille du gros');
    expect(find.widgetWithText(TextField, '47'), findsOneWidget);
    expect(m.collection('produits').parId('P1')!['stockGros'], 50, reason: 'rien n\'est régularisé à l\'ouverture');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Valider l’inventaire').last);
    expect(m.collection('produits').parId('P1')!['stockGros'], 47);
    expect(m.collection('comptagesInventaire').parId('C1')!['regularise'], isTrue);
    expect(m.collection('comptagesInventaire').parId('C2')!['regularise'], isFalse);
    await t.pump(const Duration(seconds: 15)); // le message de validation dure douze secondes
  });

  cas('l\'onglet « Taille des fichiers » (réglage de la borne par jeu) appartient à qui arbitre les lots', (t) async {
    await ouvrir(t, magasin(), 'imp-accueil', role: 'stock');
    expect(find.text('Taille des fichiers'), findsNothing);
    await ouvrir(t, magasin(), 'imp-accueil', role: 'da');
    await toucher(t, find.text('Taille des fichiers'));
    expect(find.text('Taille maximale d’un fichier d’import, par jeu'), findsOneWidget);
    expect(find.textContaining('048 Ko'), findsOneWidget, reason: 'le répertoire patients : 2 Mo par défaut');
  });

  group('la matrice des droits d\'importer (aucun nom de rôle en dur dans le code)', () {
    final m = donnees.matrice;
    final roles = [for (final r in m.rolesBruts) '${r['id']}'];
    bool importe(String role, JeuImport j) => m.peutEditer(role, j.ecran);

    test('la rangée « Importation » (IMP) n\'est visible qu\'aux détenteurs d\'un droit d\'importer', () {
      final ecransImp = [for (final e in donnees.manifeste.tousLesEcrans) if (!e.hub && e.module == 'IMP') e.id];
      expect(ecransImp, containsAll([for (final j in jeuxImport.where((j) => j.module == 'IMP')) j.ecran]));
      for (final role in roles) {
        final voit = ecransImp.any((id) => m.peutVoir(role, id));
        final detient = jeuxImport.any((j) => importe(role, j));
        expect(voit, detient, reason: '$role : voir la rangée IMP = détenir un droit d\'importer');
      }
    });

    test('l\'administrateur et la DAF importent tout ; l\'assistant comptable n\'importe rien', () {
      for (final role in ['admin', 'da']) {
        for (final j in jeuxImport) {
          expect(importe(role, j), isTrue, reason: '$role / ${j.id}');
        }
      }
      for (final j in jeuxImport) {
        expect(importe('aide_comptable', j), isFalse, reason: 'aide_comptable / ${j.id}');
      }
    });

    test('le gestionnaire de stock importe produits, stock initial, transferts, comptage, emplacements, fournisseurs ET le référentiel tarifaire (I4)', () {
      for (final id in ['produits', 'stock-detail', 'transferts', 'inventaire', 'emplacements', 'fournisseurs', 'grand-stock', 'actes']) {
        expect(importe('stock', jeuImportParId(id)!), isTrue, reason: id);
      }
      for (final id in ['patients', 'personnel', 'plan-comptable', 'soldes-ouverture', 'courriers']) {
        expect(importe('stock', jeuImportParId(id)!), isFalse, reason: id);
      }
    });

    test('le droit d\'importer est DISTINCT du droit d\'écrire : la réception écrit au registre des patients sans importer les courriers, et inversement', () {
      expect(m.peutEditer('agentadmin', 'm13-courriers') && importe('agentadmin', jeuCourriers), isTrue);
      expect(importe('reception', jeuCourriers), isFalse);
      expect(importe('comptable', jeuProduits), isFalse, reason: 'le comptable lit le référentiel produits sans l\'importer');
    });

    test('le salaire de base : seul le profil qui a le droit paie l\'obtient, par l\'écran de calcul de la paie', () {
      for (final role in roles) {
        final paie = m.peutEditer(role, DroitsImport.ecranDroitPaie);
        if (importe(role, jeuPersonnel)) expect(paie, isTrue, reason: '$role importe le personnel : droit paie attendu dans la matrice d\'origine');
      }
      expect(m.peutEditer('stock', DroitsImport.ecranDroitPaie), isFalse);
    });
  });
}
