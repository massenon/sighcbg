// SECTION 7 des décisions du 16/11/2026 (export et impression depuis un tableau) : deux droits séparés, la limite réglée par un geste réservé, le journal par
// IDENTIFIANTS (au plus 50) et nombre, les VALEURS (vrai nombre, vraie date, texte masqué qui reste masqué), les tableaux exclus, la GED sans validation en masse,
// les PIÈCES COMPLÈTES une par page sur les registres de pièces, et l'export qui suit les filtres.
import 'dart:convert';
import 'dart:io' show File, ZLibCodec;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/jetons_shell.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/impression/piece.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/cfg/cfg_parametres.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';
import 'aide_qualite.dart';

Magasin magasinNu({List<Fiche> rbac = const []}) =>
    Magasin({'audit': const <Fiche>[], 'rbac': rbac, 'parametres': const <Fiche>[], 'usagesParametres': const <Fiche>[]}, 'POSTE', const {});

Fiche ficheRbac(String role, Map<String, Object?> gestes) => {'id': 'F$role', 'role': role, 'statut': 'actif', 'droitsGestes': gestes};

List<Ligne> lignes(int n) => [
      for (var i = 1; i <= n; i++) {'id': 'r$i', 'nom': 'Patient $i', 'montant': i * 1000 + 0.75, 'date': '2026-11-${(i % 28 + 1).toString().padLeft(2, '0')}', 'groupe': i.isEven ? 'pair' : 'impair'}
    ];

final colonnes = [
  const ColonneTableau(cle: 'nom', libelle: 'Nom'),
  ColonneTableau(
      cle: 'montant', libelle: 'Montant', droite: true, texte: (r) => '${(r['montant'] as num).round()} F', valeurExport: (r) => valeurExportNombre(r['montant'])),
  ColonneTableau(cle: 'date', libelle: 'Date', texte: (r) => '${r['date']}'.split('-').reversed.join('/'), valeurExport: (r) => valeurExportDate(r['date'])),
  const ColonneTableau(cle: 'groupe', libelle: 'Groupe'),
];

Widget tableau({int n = 30, bool exportable = true, PieceA4 Function(BuildContext, Ligne)? doc, List<ColonneTableau>? cols, List<Ligne>? l}) => TableauSigh(
    titre: 'Registre',
    nomExport: 'registre',
    colonnes: cols ?? colonnes,
    lignes: l ?? lignes(n),
    exportable: exportable,
    documentLigne: doc,
    filtres: [FiltreTableau(nom: 'groupe', libelle: 'Groupe', options: const [OptionChamp('pair', 'Pair'), OptionChamp('impair', 'Impair')])]);

Future<void> monter(WidgetTester t, Widget w, {Magasin? m, String role = 'medecin'}) async {
  t.view.physicalSize = const Size(2200, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
      home: ContexteEcran(
          ecranId: 'm8-factures',
          role: role,
          droit: const Droit(voir: true, editer: true, annuler: true),
          magasin: m ?? magasinNu(),
          aller: (_) {},
          utilisateur: 'Agent de test',
          horloge: () => DateTime(2026, 11, 16, 10),
          child: Scaffold(backgroundColor: JetonsShell.navy50, body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: w))))));
}

Future<void> pomper(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Map<String, Uint8List> lireZip(List<int> o) {
  final d = ByteData.sublistView(Uint8List.fromList(o));
  var fin = o.length - 22;
  while (d.getUint32(fin, Endian.little) != 0x06054b50) {
    fin--;
  }
  final n = d.getUint16(fin + 10, Endian.little);
  var p = d.getUint32(fin + 16, Endian.little);
  final r = <String, Uint8List>{};
  for (var i = 0; i < n; i++) {
    final meth = d.getUint16(p + 10, Endian.little), taille = d.getUint32(p + 20, Endian.little);
    final ln = d.getUint16(p + 28, Endian.little), le = d.getUint16(p + 30, Endian.little), lc = d.getUint16(p + 32, Endian.little);
    final deb = d.getUint32(p + 42, Endian.little);
    final lnL = d.getUint16(deb + 26, Endian.little), leL = d.getUint16(deb + 28, Endian.little);
    final don = o.sublist(deb + 30 + lnL + leL, deb + 30 + lnL + leL + taille);
    r[utf8.decode(o.sublist(p + 46, p + 46 + ln))] = Uint8List.fromList(meth == 8 ? ZLibCodec(raw: true).decode(don) : don);
    p += 46 + ln + le + lc;
  }
  return r;
}

Fiche dernier(Magasin m, String action) => m.collection('audit').toutes.firstWhere((j) => j['action'] == action);

void main() {
  final ecrits = <String, List<int>>{};
  late Future<String> Function(List<int>, String) avant;
  setUp(() {
    ecrits.clear();
    avant = ExportPoste.enregistrer;
    ExportPoste.enregistrer = (o, n) async {
      ecrits[n] = o;
      return '/tmp/$n';
    };
    ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf';
  });
  tearDown(() {
    ExportPoste.enregistrer = avant;
    ToastsSigh.viderPourTests();
  });

  group('point 1 : exporter et imprimer, deux droits séparés', () {
    testWidgets('export retiré, impression gardée : pas d’« Exporter », mais les cases et « Imprimer la sélection »', (t) async {
      await monter(t, tableau(), m: magasinNu(rbac: [ficheRbac('medecin', {gesteExporter: false})]));
      expect(find.text('Exporter'), findsNothing);
      expect(find.bySemanticsLabel('Sélectionner la ligne'), findsWidgets, reason: 'un des deux droits suffit aux cases');
      await t.tap(find.bySemanticsLabel('Sélectionner la ligne').first);
      await t.pump();
      expect(find.byKey(const Key('kit:tableau-exporter-selection')), findsNothing);
      expect(find.byKey(const Key('kit:tableau-imprimer-selection')), findsOneWidget);
    });

    testWidgets('impression retirée, export gardé : « Exporter » reste, « Imprimer la sélection » disparaît', (t) async {
      await monter(t, tableau(), m: magasinNu(rbac: [ficheRbac('medecin', {gesteImprimerTableau: false})]));
      expect(find.text('Exporter'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Sélectionner la ligne').first);
      await t.pump();
      expect(find.byKey(const Key('kit:tableau-exporter-selection')), findsOneWidget);
      expect(find.byKey(const Key('kit:tableau-imprimer-selection')), findsNothing);
    });

    testWidgets('les deux retirés : ni cases, ni commande', (t) async {
      await monter(t, tableau(), m: magasinNu(rbac: [ficheRbac('medecin', {gesteExporter: false, gesteImprimerTableau: false})]));
      expect(find.text('Exporter'), findsNothing);
      expect(find.bySemanticsLabel('Sélectionner la ligne'), findsNothing);
    });
  });

  group('points 3, 4 et 8 : journal par identifiants, valeurs, filtres', () {
    testWidgets('l’export suit le FILTRE ; le journal porte les identifiants des seules lignes exportées et leur nombre', (t) async {
      final m = magasinNu();
      await monter(t, tableau(), m: m);
      await t.tap(find.byType(PopupMenuButton<String>));
      await pomper(t);
      await t.tap(find.text('Pair').last);
      await pomper(t);
      await t.tap(find.text('Exporter'));
      await pomper(t);
      await t.tap(find.byKey(const Key('export:format:csv')));
      await pomper(t);
      final csv = utf8.decode(ecrits.values.single);
      expect(csv.split('\r\n').length, 16, reason: 'en-tête + les 15 lignes paires');
      final d = (dernier(m, actionJournalExport)['apres'] as Map).cast<String, Object?>();
      expect(d['filtre'], 'avec');
      expect(d['nbFiches'], 15);
      expect(d['fiches'], [for (var i = 2; i <= 30; i += 2) 'r$i']);
      expect(jsonEncode(d), isNot(contains('Patient')), reason: 'jamais le contenu des cellules');
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('au-delà de 50 fiches : 50 identifiants au journal, le total à côté', (t) async {
      final m = magasinNu();
      await monter(t, tableau(n: 75), m: m);
      await t.tap(find.text('Exporter'));
      await pomper(t);
      await t.tap(find.byKey(const Key('export:format:xlsx')));
      await pomper(t);
      final d = (dernier(m, actionJournalExport)['apres'] as Map).cast<String, Object?>();
      expect((d['fiches'] as List).length, 50);
      expect(d['nbFiches'], 75);
      expect(d['fichesTronquees'], isTrue);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('un refus (limite) est journalisé avec les identifiants visés', (t) async {
      final m = magasinNu();
      final s = serviceParametres(m, auteur: () => 'T', horloge: () => DateTime(2026, 11, 16))..semerDefauts();
      expect(s.regler(cleExportLimiteLignes, 5, '2026-11-01').ok, isTrue);
      await monter(t, tableau(n: 8), m: m);
      final etat = t.state<TableauSighState>(find.byType(TableauSigh));
      await executerExport(t.element(find.byType(TableauSigh)), SourceExport(
          nom: 'registre',
          titre: 'Registre',
          colonnes: () => colonnes,
          lignes: (_) => etat.lignesFiltrees,
          nbSelection: 0,
          nbFiltre: 8,
          nbTout: 8,
          filtreActif: false), PorteeExport.toutAvecFiltre, FormatExport.csv);
      await pomper(t);
      final j = dernier(m, actionJournalExport);
      expect(j['succes'], isFalse);
      final d = (j['apres'] as Map).cast<String, Object?>();
      expect(d['refus'], 'EXPORT_TROP_VOLUMINEUX');
      expect(d['nbFiches'], 8);
      expect(ecrits, isEmpty);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('la cellule part de la VALEUR : montant à décimales en vrai nombre, date en vraie date (xlsx et CSV)', (t) async {
      await monter(t, tableau(n: 1));
      await t.tap(find.text('Exporter'));
      await pomper(t);
      await t.tap(find.byKey(const Key('export:format:xlsx')));
      await pomper(t);
      final feuille = utf8.decode(lireZip(ecrits.values.single)['xl/worksheets/sheet1.xml']!);
      expect(feuille, contains('<v>1000.75</v>'), reason: 'l’écran affiche « 1001 F », le fichier garde 1000,75');
      expect(feuille, isNot(contains('1001')));
      // 2026-11-02 en numéro de série Excel (jours depuis le 30/12/1899).
      final serie = DateTime.utc(2026, 11, 2).difference(DateTime.utc(1899, 12, 30)).inDays;
      expect(feuille, contains('s="4"><v>$serie'), reason: 'la date est une vraie date (numéro de série au format date)');
      ecrits.clear();
      await t.tap(find.text('Exporter'));
      await pomper(t);
      await t.tap(find.byKey(const Key('export:format:csv')));
      await pomper(t);
      final csv = utf8.decode(ecrits.values.single);
      expect(csv, contains('"1000,75"'));
      expect(csv, contains('"02/11/2026"'));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('le texte MASQUÉ sort masqué, même si la colonne déclare une valeur d’export', (t) async {
      final cat = categoriesSensibles.firstWhere((c) => c.code == 'coordonnees');
      final m = Magasin({
        'audit': const <Fiche>[],
        'rbac': [
          {'id': 'F1', 'role': 'medecin', 'statut': 'actif', 'donneesSensibles': {cat.code: false}}
        ],
        'parametres': const <Fiche>[],
        'usagesParametres': const <Fiche>[],
      }, 'POSTE', const {});
      await monter(
          t,
          tableau(cols: [
            const ColonneTableau(cle: 'nom', libelle: 'Nom'),
            // Faute volontaire de l'auteur : une valeur d'export sur une colonne sensible. Elle est IGNORÉE (refus du profil), et une chaîne ne passe jamais.
            ColonneTableau(cle: 'telephone', libelle: 'Téléphone', valeurExport: (r) => r['telephone']),
            ColonneTableau(cle: 'masque', libelle: 'N° masqué', texte: (r) => '97 •• •• ${'${r['masque']}'.substring(6)}', valeurExport: (r) => r['masque']),
          ], l: [
            {'id': 'a', 'nom': 'Un', 'telephone': 97000000, 'masque': '97456712'}
          ]),
          m: m);
      await t.tap(find.text('Exporter'));
      await pomper(t);
      await t.tap(find.byKey(const Key('export:format:csv')));
      await pomper(t);
      final csv = utf8.decode(ecrits.values.single);
      expect(csv, isNot(contains('97000000')));
      expect(csv, contains(mentionReservee(cat.code)));
      expect(csv, isNot(contains('97456712')), reason: 'une valeur chaîne est ignorée : le texte masqué fait foi');
      expect(csv, contains('97 •• •• 12'));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('l’impression de la sélection est journalisée avec les identifiants, et refusée (journalisée) sans le droit', (t) async {
      await chargerPolices();
      final m = magasinNu();
      await monter(t, tableau(), m: m);
      await t.tap(find.bySemanticsLabel('Sélectionner la ligne').at(0));
      await t.tap(find.bySemanticsLabel('Sélectionner la ligne').at(2));
      await t.pump();
      await t.tap(find.byKey(const Key('kit:tableau-imprimer-selection')));
      await pomper(t);
      final d = (dernier(m, actionJournalImpression)['apres'] as Map).cast<String, Object?>();
      expect(d['fiches'], ['r1', 'r3']);
      expect(d['nbFiches'], 2);
      await t.tap(find.text('Fermer').last);
      await pomper(t);
      // sans le droit : refus nommé, journalisé avec les fiches visées
      final m2 = magasinNu(rbac: [ficheRbac('medecin', {gesteImprimerTableau: false})]);
      await monter(t, tableau(), m: m2);
      await ouvrirImpressionSelection(
          t.element(find.byType(TableauSigh)), SourceImpression(titre: 'Registre', colonnes: () => colonnes, lignes: lignes(3), filtres: const []));
      await pomper(t);
      final r = (dernier(m2, actionJournalImpression)['apres'] as Map).cast<String, Object?>();
      expect(r['refus'], 'IMPRESSION_RESERVEE');
      expect(r['fiches'], ['r1', 'r2', 'r3']);
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('point 5 : un tableau exclu n’a ni cases ni « Exporter »', () {
    testWidgets('exportable: false', (t) async {
      await monter(t, tableau(exportable: false));
      expect(find.text('Exporter'), findsNothing);
      expect(find.bySemanticsLabel('Sélectionner la ligne'), findsNothing);
    });

    test('CLIQUET : aucune grille de saisie en cours n’est un TableauSigh (elles restent hors export, liste dans EXPORT-exclusions.md)', () {
      // Les fichiers qui portent les grilles de saisie en cours recensées : la composition d'une facture, l'éditeur de lignes des bons d'achat, la feuille
      // d'inventaire, la saisie d'une écriture, la saisie des lignes d'une dépense. Un TableauSigh qui y entrerait offrirait cases et export sur une pièce
      // qui n'existe pas encore.
      const fichiers = [
        'lib/modules/m8/facturation.dart',
        'lib/modules/m7/besoins_commun.dart',
        'lib/modules/m6/mvt_inventaire_feuille.dart',
      ];
      for (final f in fichiers) {
        expect(File(f).readAsStringSync().contains(RegExp(r'(?<!Mini)TableauSigh\(')), isFalse, reason: f);
      }
      expect(File('../../docs/architecture/EXPORT-exclusions.md').existsSync(), isTrue);
    });
  });

  group('point 2 : la limite de lignes se règle par un geste réservé', () {
    Future<void> panneau(WidgetTester t, String role, {List<Fiche> rbac = const []}) async {
      t.view.physicalSize = const Size(1600, 6000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final m = magasinNu(rbac: rbac);
      await t.pumpWidget(MaterialApp(
          theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
          home: Builder(builder: (ctx) {
            return ContexteEcran(
                ecranId: 'cfg-systeme',
                role: role,
                droit: const Droit(voir: true, editer: true, annuler: true),
                magasin: m,
                aller: (_) {},
                utilisateur: 'Agent',
                horloge: () => DateTime(2026, 11, 16),
                child: Scaffold(body: SingleChildScrollView(child: Builder(builder: (c2) => PanneauParametres(c: ContexteEcran.of(c2), estMere: true)))));
          })));
      await t.pump();
    }

    testWidgets('qui édite l’écran sans le geste : la commande est absente de la carte de la limite, et le refus est NOMMÉ', (t) async {
      await panneau(t, 'comptable');
      expect(find.byKey(const Key('parametre:reserve:export.limiteLignes')), findsOneWidget);
      expect(find.textContaining('Régler la limite de lignes par export'), findsWidgets);
      expect(find.byKey(const Key('parametre:reserve:export.seuilProgression')), findsNothing, reason: 'le seuil du compteur reste au droit d’éditer l’écran');
    });

    testWidgets('l’origine (DAF) règle ; une fiche de rôle l’accorde au comptable', (t) async {
      await panneau(t, 'da');
      expect(find.byKey(const Key('parametre:reserve:export.limiteLignes')), findsNothing);
      await panneau(t, 'comptable', rbac: [ficheRbac('comptable', {gesteReglerLimiteExport: true})]);
      expect(find.byKey(const Key('parametre:reserve:export.limiteLignes')), findsNothing);
    });
  });

  group('point 6 : la GED — les cases servent à exporter et imprimer, jamais à valider en masse', () {
    cas('cases présentes, sélection sans aucune action de groupe qui valide', (t) async {
      final m = magasinDe({'documents': jeuJson('documents')});
      await ouvrir(t, m, 'ged-workflow');
      final tab = t.widget<TableauSigh>(find.byType(TableauSigh));
      expect(tab.actionsGroupe, isNull, reason: 'aucune action de groupe : ni valider ni rejeter en masse');
      expect(find.bySemanticsLabel('Sélectionner la ligne'), findsWidgets);
      final avant = m.collection('documents').toutes.map((d) => '${d['id']}:${d['etatValidation']}:${d['signe']}').toList();
      await toucher(t, find.bySemanticsLabel('Tout sélectionner'));
      final barre = find.byKey(const Key('kit:tableau-selection'));
      expect(barre, findsOneWidget);
      final libelles = [for (final b in t.widgetList<BoutonSigh>(find.descendant(of: barre, matching: find.byType(BoutonSigh)))) b.libelle];
      for (final l in libelles) {
        expect(l, isIn(['Exporter la sélection', 'Imprimer la sélection', 'Tout désélectionner']..addAll(libelles.where((x) => x.startsWith('Tout cocher')))), reason: l);
      }
      expect(libelles.any((l) => l.contains('Valider') || l.contains('Rejeter')), isFalse);
      expect(m.collection('documents').toutes.map((d) => '${d['id']}:${d['etatValidation']}:${d['signe']}').toList(), avant, reason: 'cocher ne change rien');
    });
  });

  group('point 7 : les pièces complètes cochées, une par page', () {
    Future<void> lot(WidgetTester t, Magasin m, String ecran) async {
      await ouvrir(t, m, ecran);
      await toucher(t, find.bySemanticsLabel('Sélectionner la ligne').at(0));
      await toucher(t, find.bySemanticsLabel('Sélectionner la ligne').at(1));
      await toucher(t, find.byKey(const Key('kit:tableau-imprimer-selection')));
      expect(find.byKey(const Key('impression:etats')), findsOneWidget, reason: '$ecran : la pièce complète est offerte');
      await toucher(t, find.byKey(const Key('impression:etats')));
      expect(find.textContaining('État 1 sur 2'), findsOneWidget, reason: ecran);
      final d = (dernier(m, actionJournalImpression)['apres'] as Map).cast<String, Object?>();
      expect(d['mode'], 'etat_par_ligne');
      expect(d['nbFiches'], 2);
    }

    cas('les factures (M8)', (t) async {
      await chargerPolices();
      await lot(t, magasinDe({'factures': jeuJson('factures')}), 'm8-factures');
    });
    cas('les bons de commande (M7)', (t) async {
      await chargerPolices();
      await lot(t, magasinDe({'commandes': jeuJson('commandes')}), 'm7-commandes');
    });
    cas('les ordonnances (M2)', (t) async {
      await chargerPolices();
      await lot(t, magasinDe({'ordonnances': jeuJson('ordonnances')}), 'm2-ordonnances');
    });
    cas('les certificats et attestations (M1)', (t) async {
      await chargerPolices();
      await lot(t, magasinDe({'pieces': jeuJson('pieces')}), 'm1-pieces');
    });
  });
}
