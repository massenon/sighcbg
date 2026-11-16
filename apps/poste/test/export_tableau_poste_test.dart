// Le chantier TABLEAUX au poste : cases à cocher, sélection conservée d'une page à l'autre, compteur, export de la sélection et de tout (avec ou sans filtre),
// limite et refus nommé, droit réservé, champs sensibles masqués, journal sans contenu, impression de la sélection.
import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/jetons_shell.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/piece.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';

Magasin magasin() => Magasin({'audit': const <Fiche>[], 'rbac': const <Fiche>[], 'parametres': const <Fiche>[], 'usagesParametres': const <Fiche>[]}, 'POSTE', const {});

List<Ligne> lignes(int n) => [
      for (var i = 1; i <= n; i++) {'id': 'r$i', 'nom': 'Patient $i', 'montant': '${i}000', 'groupe': i.isEven ? 'pair' : 'impair'}
    ];

const colonnes = [ColonneTableau(cle: 'nom', libelle: 'Nom'), ColonneTableau(cle: 'montant', libelle: 'Montant', droite: true), ColonneTableau(cle: 'groupe', libelle: 'Groupe')];

Future<void> monter(WidgetTester t, Widget tableau, {Magasin? m, String role = 'medecin', bool coque = true}) async {
  t.view.physicalSize = const Size(2200, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final corps = Scaffold(backgroundColor: JetonsShell.navy50, body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: tableau)));
  await t.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
      home: coque
          ? ContexteEcran(
              ecranId: 'm6-transferts',
              role: role,
              droit: const Droit(voir: true, editer: true, annuler: true),
              magasin: m ?? magasin(),
              aller: (_) {},
              utilisateur: 'Agent de test',
              horloge: () => DateTime(2026, 11, 15, 10),
              child: corps)
          : corps));
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
  });
  tearDown(() => ExportPoste.enregistrer = avant);

  Widget tableau({bool? selectionnable, PieceA4 Function(BuildContext, Ligne)? doc, int n = 30}) => TableauSigh(
      titre: 'Transferts',
      nomExport: 'transferts',
      colonnes: colonnes,
      lignes: lignes(n),
      selectionnable: selectionnable,
      documentLigne: doc,
      filtres: [FiltreTableau(nom: 'groupe', libelle: 'Groupe', options: const [OptionChamp('pair', 'Pair'), OptionChamp('impair', 'Impair')])]);

  testWidgets('sous une coque : cases à cocher ; sans coque ou sur demande contraire : aucune', (t) async {
    await monter(t, tableau());
    expect(find.bySemanticsLabel('Sélectionner la ligne'), findsWidgets);
    await monter(t, tableau(), coque: false);
    expect(find.bySemanticsLabel('Sélectionner la ligne'), findsNothing);
    await monter(t, tableau(selectionnable: false));
    expect(find.bySemanticsLabel('Sélectionner la ligne'), findsNothing);
  });

  testWidgets('la sélection survit au changement de page, le compteur la dit, « tout cocher » prend tout le filtre, l\'agent la vide', (t) async {
    await monter(t, tableau());
    await t.tap(find.bySemanticsLabel('Tout sélectionner'));
    await t.pump();
    expect(find.byKey(const Key('kit:tableau-compteur')), findsOneWidget);
    expect(find.text('12 lignes sélectionnées'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Page suivante'));
    await t.pump();
    expect(find.text('12 lignes sélectionnées'), findsOneWidget, reason: 'changer de page ne perd rien');
    await t.tap(find.bySemanticsLabel('Sélectionner la ligne').first);
    await t.pump();
    expect(find.text('13 lignes sélectionnées'), findsOneWidget);
    await t.tap(find.byKey(const Key('kit:tableau-tout-cocher')));
    await t.pump();
    expect(find.text('30 lignes sélectionnées'), findsOneWidget);
    await t.tap(find.text('Tout désélectionner'));
    await t.pump();
    expect(find.byKey(const Key('kit:tableau-compteur')), findsNothing);
  });

  testWidgets('Exporter la sélection : un vrai classeur de ces lignes seules, journalisé sans contenu', (t) async {
    final m = magasin();
    await monter(t, tableau(), m: m);
    await t.tap(find.bySemanticsLabel('Sélectionner la ligne').at(1));
    await t.tap(find.bySemanticsLabel('Sélectionner la ligne').at(4));
    await t.pump();
    await t.tap(find.byKey(const Key('kit:tableau-exporter-selection')));
    await pomper(t);
    expect(find.byKey(const Key('export:portee:selection')), findsOneWidget);
    await t.tap(find.byKey(const Key('export:format:xlsx')));
    await pomper(t);
    expect(ecrits.keys.single, 'transferts-2026-11-15-selection.xlsx');
    final feuille = utf8.decode(lireZip(ecrits.values.single)['xl/worksheets/sheet1.xml']!);
    expect(RegExp('<row ').allMatches(feuille).length, 3, reason: 'en-tête + 2 lignes cochées');
    expect(feuille, allOf(contains('Patient 2'), contains('Patient 5')));
    expect(feuille, isNot(contains('Patient 3')));
    expect(feuille, contains('<c r="B2"><v>2000</v></c>'), reason: 'le montant est numérique');
    final j = m.collection('audit').toutes.first;
    expect(j['action'], 'Export de tableau');
    expect(j['entite'], 'm6-transferts');
    expect(j['utilisateur'], isNotNull);
    final detail = (j['apres'] as Map).cast<String, Object?>();
    // Section 7 (16/11/2026) : les IDENTIFIANTS des fiches (au plus 50) et leur nombre, jamais le contenu.
    expect(detail, {'portee': 'selection', 'lignes': 2, 'filtre': 'sans', 'colonnes': 3, 'format': 'xlsx', 'fiches': ['r2', 'r5'], 'nbFiches': 2});
    expect(jsonEncode(j), isNot(contains('Patient')), reason: 'jamais le contenu');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('Tout exporter : avec le filtre actif, puis sans le filtre ; le CSV garde la même chaîne', (t) async {
    await monter(t, tableau());
    await t.tap(find.byType(PopupMenuButton<String>));
    await pomper(t);
    await t.tap(find.text('Pair').last);
    await pomper(t);
    await t.tap(find.text('Exporter'));
    await pomper(t);
    expect(find.byKey(const Key('export:portee:tout_avec_filtre')), findsOneWidget);
    expect(find.byKey(const Key('export:portee:tout_sans_filtre')), findsOneWidget);
    await t.tap(find.byKey(const Key('export:format:csv')));
    await pomper(t);
    var csv = utf8.decode(ecrits.values.single);
    expect(csv.split('\r\n').length, 16, reason: 'en-tête + 15 pairs sur toutes les pages (page de 12)');
    ecrits.clear();
    await t.tap(find.text('Exporter'));
    await pomper(t);
    await t.tap(find.byKey(const Key('export:portee:tout_sans_filtre')));
    await t.pump();
    await t.tap(find.byKey(const Key('export:format:csv')));
    await pomper(t);
    csv = utf8.decode(ecrits.values.single);
    expect(csv.split('\r\n').length, 31);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('au-delà de la limite de la clinique : refus NOMMÉ, aucun fichier', (t) async {
    final m = magasin();
    final s = serviceParametres(m, auteur: () => 'Test', horloge: () => DateTime(2026, 11, 15));
    s.semerDefauts();
    expect(s.regler(cleExportLimiteLignes, 10, '2026-11-01', motif: 'essai').ok, isTrue);
    await monter(t, tableau(), m: m);
    await t.tap(find.text('Exporter'));
    await pomper(t);
    expect(find.byKey(const Key('export:refus')), findsOneWidget);
    expect(find.textContaining('la limite réglée par la clinique est de 10'), findsOneWidget);
    expect(t.widget<BoutonSigh>(find.byKey(const Key('export:format:xlsx'))).onPressed, isNull);
    expect(ecrits, isEmpty);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('AK (16/11/2026) : sans limite fixée par la clinique, tout s\'exporte ; l\'ancien semis (version 0) ne limite rien', (t) async {
    final m = magasin();
    // Une base semée AVANT la décision : la version 0 porte une petite limite d'attente (simulée à 3) ; elle n'est pas une décision de la clinique.
    final semis = Parametres.semer(definitionDeParametre(cleExportLimiteLignes)!).toJson();
    m.collection(parCollectionParametres).ajouterSansJournal({...semis, 'id': '$cleExportLimiteLignes@defaut@0', 'valeur': 3, 'defaut': 3});
    await monter(t, tableau(), m: m);
    await t.tap(find.text('Exporter'));
    await pomper(t);
    expect(find.byKey(const Key('export:refus')), findsNothing, reason: 'aucune limite tant que la clinique n’en a pas fixé une');
    await t.tap(find.byKey(const Key('export:format:csv')));
    await pomper(t);
    expect(utf8.decode(ecrits.values.single).split('\r\n').length, 31, reason: 'en-tête + les 30 lignes, jamais tronqué');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('AK : l\'impression de la sélection suit le FILTRE appliqué et le porte sur la pièce', (t) async {
    await chargerPolices();
    final m = magasin();
    await monter(t, tableau(), m: m);
    await t.tap(find.byType(PopupMenuButton<String>));
    await pomper(t);
    await t.tap(find.text('Pair').last);
    await pomper(t);
    await t.tap(find.bySemanticsLabel('Tout sélectionner'));
    await t.pump();
    await t.tap(find.byKey(const Key('kit:tableau-tout-cocher')));
    await t.pump();
    expect(find.text('15 lignes sélectionnées'), findsOneWidget, reason: '« tout cocher » prend le filtre, pas tout le tableau');
    await t.tap(find.byKey(const Key('kit:tableau-imprimer-selection')));
    await pomper(t);
    final apres = m.collection('audit').toutes.first['apres'] as Map;
    expect(apres['lignes'], 15);
    expect(find.textContaining('Pair'), findsWidgets, reason: 'le filtre en force est écrit sur la pièce');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('droit retiré par une décision de la clinique : la commande est ABSENTE, rien ne s\'exporte', (t) async {
    final m = Magasin({
      'audit': const <Fiche>[],
      'rbac': [
        // Section 7 (16/11/2026) : exporter et imprimer sont deux droits ; les cases tombent quand AUCUN des deux ne reste.
        {'id': 'F1', 'role': 'medecin', 'statut': 'actif', 'droitsGestes': {gesteExporter: false, gesteImprimerTableau: false}}
      ],
      'parametres': const <Fiche>[],
      'usagesParametres': const <Fiche>[],
    }, 'POSTE', const {});
    await monter(t, tableau(), m: m);
    expect(find.text('Exporter'), findsNothing);
    expect(find.bySemanticsLabel('Sélectionner la ligne'), findsNothing, reason: 'rien à cocher pour qui ne peut ni exporter ni imprimer');
  });

  testWidgets('un champ sensible refusé au profil n\'est jamais exporté en clair', (t) async {
    final cat = categoriesSensibles.firstWhere((c) => c.code == 'coordonnees');
    const champ = 'telephone';
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
        TableauSigh(
            nomExport: 'x',
            colonnes: [ColonneTableau(cle: 'nom', libelle: 'Nom'), ColonneTableau(cle: champ, libelle: 'Sensible')],
            lignes: [
              {'id': 'a', 'nom': 'Un', champ: 'SECRET-123'}
            ]),
        m: m);
    await t.tap(find.text('Exporter'));
    await pomper(t);
    await t.tap(find.byKey(const Key('export:format:csv')));
    await pomper(t);
    final csv = utf8.decode(ecrits.values.single);
    expect(csv, isNot(contains('SECRET-123')));
    expect(csv, contains(mentionReservee(cat.code)));
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('Imprimer la sélection : un seul tableau par défaut au gabarit, un état par ligne quand le document existe', (t) async {
    await chargerPolices();
    PieceA4 doc(BuildContext c, Ligne l) =>
        PieceA4(titre: 'Bon ${l['nom']}', reference: 'REF-${l['id']}', utilisateur: 'Agent', edite: DateTime(2026, 11, 15), blocs: const [BlocTexte('x')]);
    final m = magasin();
    await monter(t, tableau(doc: doc), m: m);
    await t.tap(find.bySemanticsLabel('Sélectionner la ligne').at(0));
    await t.tap(find.bySemanticsLabel('Sélectionner la ligne').at(1));
    await t.pump();
    await t.tap(find.byKey(const Key('kit:tableau-imprimer-selection')));
    await pomper(t);
    await t.tap(find.byKey(const Key('impression:etats')));
    await pomper(t);
    expect(find.byKey(const Key('impression:lot:position')), findsOneWidget);
    expect(find.textContaining('État 1 sur 2'), findsOneWidget);
    await t.tap(find.byKey(const Key('impression:lot:suivant')));
    await t.pump();
    expect(find.textContaining('État 2 sur 2'), findsOneWidget);
    expect((m.collection('audit').toutes.first['apres'] as Map)['mode'], 'etat_par_ligne');
    await t.tap(find.text('Fermer').last);
    await pomper(t);
    // sans document unitaire : directement le tableau unique à l'aperçu du gabarit
    await monter(t, tableau(), m: m);
    await t.tap(find.bySemanticsLabel('Sélectionner la ligne').at(0));
    await t.pump();
    await t.tap(find.byKey(const Key('kit:tableau-imprimer-selection')));
    await pomper(t);
    expect(find.text('Transferts'), findsWidgets);
    expect((m.collection('audit').toutes.first['apres'] as Map)['mode'], 'tableau');
  });

  testWidgets('un état par ligne au-delà de la limite réglée : refus nommé', (t) async {
    PieceA4 doc(BuildContext c, Ligne l) => PieceA4(titre: 'B', reference: 'R${l['id']}', utilisateur: 'A', edite: DateTime(2026, 11, 15));
    final m = magasin();
    final s = serviceParametres(m, auteur: () => 'T', horloge: () => DateTime(2026, 11, 15))..semerDefauts();
    s.regler(cleExportLimiteEtats, 1, '2026-11-01', motif: 'essai');
    await monter(t, tableau(doc: doc), m: m);
    await t.tap(find.bySemanticsLabel('Tout sélectionner'));
    await t.pump();
    await t.tap(find.byKey(const Key('kit:tableau-imprimer-selection')));
    await pomper(t);
    await t.tap(find.byKey(const Key('impression:etats')));
    await pomper(t);
    expect(find.textContaining('limite réglée par la clinique est de 1 états'), findsOneWidget);
    expect(find.byKey(const Key('impression:lot:position')), findsNothing);
    expect((m.collection('audit').toutes.first['apres'] as Map)['refus'], 'IMPRESSION_TROP_D_ETATS');
    await t.pump(const Duration(seconds: 10));
  });
}
