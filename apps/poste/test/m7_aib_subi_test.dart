import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// L'AIB SUBI sur facture fournisseur, AU GESTE (position de la Direction du 09/11/2026) : l'AIB facturé se saisit dans la modale d'édition (entier, cohérent,
/// refus nommés), « Constater l'AIB subi » pose UNE pièce plate en brouillon (débit compte d'AIB subi, crédit compte fournisseur, RG-10), la facture PORTE son
/// AIB subi, une seule fois ; les comptes se lisent aux Paramètres à la date de la pièce ; un taux hors barème est SIGNALÉ sans bloquer ; le registre de
/// `m12-aib` relit le tout et indique l'imputation sur l'impôt sur les bénéfices, sans écriture.
final _donnees = DonneesNavigation.depuisDossier();

Magasin _magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Future<void> _ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: _donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => DateTime(2026, 10, 30)));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _saisir(WidgetTester t, String champ, String texte) async {
  final f = find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField));
  await t.ensureVisible(f);
  await t.enterText(f, texte);
  await t.pump();
}

/// Une facture fournisseur, seule au registre ; [aib] est l'AIB facturé (ou rien).
Magasin _avecFacture({
  String date = '2026-10-12',
  Map<String, Object?>? aib = const {'montant': 10000, 'taux': 5, 'baseHt': 200000},
  List<Map<String, Object?>> parametres = const [],
  Map<String, Object?> plus = const {},
}) {
  final m = _magasin();
  for (final x in parametres) {
    m.collection('parametresAib').ajouterSansJournal(x);
  }
  final col = m.collection('facturesFournisseurs');
  for (final x in col.actives) {
    col.archiver(x['id']);
  }
  col.inserer({
    'id': 'FFR1',
    'reference': 'FF-TEST-0001',
    'numeroFournisseur': 'F-1',
    'date': date,
    'fournisseur': 'GPB',
    'fournisseurNom': 'Grossiste Pharma Borgou',
    'montantLivraison': 210000,
    'montantFacture': 210000,
    'montantHT': 200000,
    if (aib != null) 'aibFacture': aib,
    'ecart': 0,
    'statutRappro': 'rapproche',
    'statutPaiement': 'impayee',
    'statut': 'actif',
    ...plus,
  });
  return m;
}

Fiche _facture(Magasin m) => m.collection('facturesFournisseurs').parId('FFR1')!;

List<Fiche> _pieceDe(Magasin m) => [for (final e in m.collection('ecritures').actives) if (e['pieceId'] == 'FFR1') e];

/// Le texte de la note d'imputation, SANS aucune espace (les montants sont composés avec des espaces fines et insécables).
String _texteImputation(WidgetTester t) =>
    t.widget<Text>(find.descendant(of: find.byKey(const Key('aib:imputation')), matching: find.byType(Text)).first).data!.replaceAll(RegExp(r'\s'), '');

const _comptesV2 = {
  'id': 'PAA-COMPTES-2', 'statut': 'actif', 'rubrique': 'comptes', 'version': 2, 'dateEffet': '2026-11-01', 'compteAibSubi': '4491', 'compteAibRetenu': '4479',
  'compteImputation': '891', 'compteFournisseur': '401100', 'decideur': 'Expert-comptable', 'dateDecision': '2026-10-28', 'motif': 'Confirmation écrite',
};

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('l\'AIB facturé se saisit dans la modale d\'édition de la facture', () {
    testWidgets('montant, taux et base cohérents : la facture porte `aibFacture` en entiers, l\'AIB subi reste à constater', (t) async {
      final m = _avecFacture(aib: null);
      await _ouvrir(t, m, 'm7-factures-fournisseurs');
      expect(find.byTooltip('Constater l’AIB subi'), findsNothing, reason: 'sans AIB facturé, rien à constater');
      await _toucher(t, find.byTooltip('Modifier').first);
      await _saisir(t, 'numero', 'FA-GPB-1');
      await _saisir(t, 'aibFactureMontant', '10000');
      await _saisir(t, 'aibFactureTaux', '5');
      await _saisir(t, 'aibFactureBase', '200000');
      await _toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      final a = (_facture(m)['aibFacture'] as Map).cast<String, Object?>();
      expect([a['montant'], a['taux'], a['baseHt']], [10000, 5, 200000]);
      expect(_facture(m)['aibSubi'], isNull, reason: 'saisir l\'AIB facturé ne constate rien');
      expect(_pieceDe(m), isEmpty);
      expect(find.byTooltip('Constater l’AIB subi'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('incohérent avec la base et le taux : refus nommé sur le champ, rien n\'est écrit', (t) async {
      final m = _avecFacture(aib: null);
      await _ouvrir(t, m, 'm7-factures-fournisseurs');
      await _toucher(t, find.byTooltip('Modifier').first);
      await _saisir(t, 'numero', 'FA-GPB-1');
      await _saisir(t, 'aibFactureMontant', '9000');
      await _saisir(t, 'aibFactureTaux', '5');
      await _saisir(t, 'aibFactureBase', '200000');
      await _toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.textContaining('AIB_FACTURE_INCOHERENT'), findsWidgets);
      expect(find.textContaining('10 000'), findsWidgets, reason: 'le refus dit le montant attendu');
      expect(_facture(m)['aibFacture'], isNull);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('incomplet, non entier : refus nommés', (t) async {
      final m = _avecFacture(aib: null);
      await _ouvrir(t, m, 'm7-factures-fournisseurs');
      await _toucher(t, find.byTooltip('Modifier').first);
      await _saisir(t, 'numero', 'FA-GPB-1');
      await _saisir(t, 'aibFactureMontant', '10000');
      await _toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.textContaining('AIB_FACTURE_INCOMPLET'), findsWidgets);
      await _saisir(t, 'aibFactureTaux', '5');
      await _saisir(t, 'aibFactureBase', '200000,5');
      await _toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.textContaining('AIB_FACTURE_NON_ENTIER'), findsWidgets);
      expect(_facture(m)['aibFacture'], isNull);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('l\'AIB subi déjà constaté FIGE l\'AIB facturé : la modifier est refusé en le disant', (t) async {
      final m = _avecFacture(plus: {'aibSubi': {'montant': 10000, 'taux': 5, 'base': 200000, 'date': '2026-10-12', 'ecritureIds': []}});
      await _ouvrir(t, m, 'm7-factures-fournisseurs');
      await _toucher(t, find.byTooltip('Modifier').first);
      await _saisir(t, 'numero', 'FA-GPB-1');
      await _saisir(t, 'aibFactureMontant', '5000');
      await _saisir(t, 'aibFactureBase', '100000');
      await _toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
      expect(find.textContaining('AIB_FACTURE_FIGEE'), findsWidgets);
      expect((_facture(m)['aibFacture'] as Map)['montant'], 10000);
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('Constater l\'AIB subi : une pièce plate en brouillon, la facture la porte', () {
    testWidgets('5 % de 200 000 = 10 000 : débit 4492, crédit 401000, journal des achats, brouillon, RG-10 ; l\'action disparaît, le registre relit', (t) async {
      final m = _avecFacture();
      await _ouvrir(t, m, 'm7-factures-fournisseurs');
      await _toucher(t, find.byTooltip('Constater l’AIB subi').first);
      expect(find.byKey(const Key('aibsubi:signal')), findsNothing, reason: '5 % est arrêté au barème au 12/10/2026');
      expect(find.byKey(const Key('aibsubi:comptes-a-confirmer')), findsOneWidget, reason: 'la graine est marquée à confirmer par l\'expert-comptable');
      await _toucher(t, find.byKey(const Key('aibsubi:constater')));
      final f = _facture(m);
      final s = (f['aibSubi'] as Map).cast<String, Object?>();
      expect([s['montant'], s['taux'], s['base'], s['date'], s['compteSubi'], s['compteFournisseur']], [10000, 5, 200000, '2026-10-12', '4492', '401000']);
      expect((s['ecritureIds'] as List).length, 2);
      expect(s['signalTaux'], isNull);
      final p = _pieceDe(m);
      expect(p.length, 2);
      expect(p.every((e) => e['statut'] == 'brouillon' && e['journal'] == 'ACH' && e['numero'] == 'AIBS-FF-TEST-0001'), isTrue);
      expect(p.firstWhere((e) => e['compte'] == '4492')['debit'], 10000);
      expect(p.firstWhere((e) => e['compte'] == '401000')['credit'], 10000);
      expect(p.fold<num>(0, (a, e) => a + (e['debit'] as num)), p.fold<num>(0, (a, e) => a + (e['credit'] as num)), reason: 'RG-10');
      expect((f['aibFacture'] as Map)['montant'], 10000, reason: 'la facture n\'est pas réécrite : son AIB facturé reste');
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'AIB subi sur facture fournisseur' && a['reference'] == 'FF-TEST-0001'), isTrue);
      expect(find.byTooltip('Constater l’AIB subi'), findsNothing, reason: 'une facture ne porte qu\'un AIB subi');
      // le registre de m12-aib relit la pièce et indique l'imputation
      await _ouvrir(t, m, 'm12-aib');
      expect(find.textContaining('Imputation sur l’impôt sur les bénéfices de 2026'), findsOneWidget);
      expect(_texteImputation(t), contains('AIBsubi10000'));
      await _toucher(t, find.text('AIB subi (créance)'));
      expect(find.text('Registre de l’AIB subi'), findsOneWidget);
      expect(find.text('FF-TEST-0001'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('un taux de 1 %, non arrêté au barème, est SIGNALÉ — jamais refusé : la pièce naît, la fiche porte le signal, le registre aussi', (t) async {
      final m = _avecFacture(aib: const {'montant': 2000, 'taux': 1, 'baseHt': 200000});
      await _ouvrir(t, m, 'm7-factures-fournisseurs');
      await _toucher(t, find.byTooltip('Constater l’AIB subi').first);
      expect(find.byKey(const Key('aibsubi:signal')), findsOneWidget);
      expect(find.textContaining('Taux non arrêté au barème'), findsWidgets);
      await _toucher(t, find.byKey(const Key('aibsubi:constater')));
      final s = (_facture(m)['aibSubi'] as Map).cast<String, Object?>();
      expect(s['montant'], 2000);
      expect('${s['signalTaux']}', contains('Taux non arrêté au barème'));
      expect(_pieceDe(m).length, 2);
      await _ouvrir(t, m, 'm12-aib');
      await _toucher(t, find.text('AIB subi (créance)'));
      expect(find.text('Taux non arrêté au barème'), findsWidgets);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('le tiroir de la facture dit l\'AIB facturé et, pour un taux hors barème, le signal', (t) async {
      final m = _avecFacture(aib: const {'montant': 2000, 'taux': 1, 'baseHt': 200000});
      await _ouvrir(t, m, 'm7-factures-fournisseurs');
      await _toucher(t, find.text('FF-TEST-0001').first);
      expect(find.textContaining('1 % de'), findsWidgets);
      expect(find.byKey(const Key('aibsubi:signal-detail')), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('les comptes se lisent aux Paramètres À LA DATE de la pièce : 4492 avant la version 2, 4491 / 401100 après ; la retenue lit aussi son compte', (t) async {
      final avant = _avecFacture(date: '2026-10-12', parametres: const [_comptesV2]);
      await _ouvrir(t, avant, 'm7-factures-fournisseurs');
      await _toucher(t, find.byTooltip('Constater l’AIB subi').first);
      await _toucher(t, find.byKey(const Key('aibsubi:constater')));
      expect([for (final e in _pieceDe(avant)) e['compte']].toSet(), {'4492', '401000'}, reason: 'les pièces antérieures gardent leurs comptes d\'origine');

      final apres = _avecFacture(date: '2026-11-12', parametres: const [_comptesV2]);
      await _ouvrir(t, apres, 'm7-factures-fournisseurs');
      await _toucher(t, find.byTooltip('Constater l’AIB subi').first);
      expect(find.byKey(const Key('aibsubi:comptes-a-confirmer')), findsNothing, reason: 'la version 2 est validée : le marquage est levé');
      await _toucher(t, find.byKey(const Key('aibsubi:constater')));
      final p = _pieceDe(apres);
      expect(p.firstWhere((e) => (e['debit'] as num) > 0)['compte'], '4491');
      expect(p.firstWhere((e) => (e['credit'] as num) > 0)['compte'], '401100');
      expect((_facture(apres)['aibSubi'] as Map)['comptesVersion'], 2);

      // la retenue d'AIB (autre facture, même date) lit, elle aussi, la version en vigueur : débit 401100, crédit 4479
      final ret = _avecFacture(date: '2026-11-12', aib: null, parametres: const [_comptesV2]);
      await _ouvrir(t, ret, 'm7-factures-fournisseurs');
      await _toucher(t, find.byTooltip('Retenir l’AIB').first);
      await _toucher(t, find.widgetWithText(BoutonSigh, 'Constater la retenue'));
      final r = _pieceDe(ret);
      expect(r.firstWhere((e) => (e['debit'] as num) > 0)['compte'], '401100');
      expect(r.firstWhere((e) => (e['credit'] as num) > 0)['compte'], '4479');
      expect((_facture(ret)['retenueAib'] as Map)['compteRetenu'], '4479');
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('refus nommés : rien n\'est écrit', () {
    testWidgets('exercice clôturé (2025, déposé) : écriture refusée en le nommant, la facture ne porte rien', (t) async {
      final m = _avecFacture(date: '2025-06-10');
      await _ouvrir(t, m, 'm7-factures-fournisseurs');
      await _toucher(t, find.byTooltip('Constater l’AIB subi').first);
      await _toucher(t, find.byKey(const Key('aibsubi:constater')));
      expect(find.text('Écriture refusée.'), findsOneWidget);
      expect(find.textContaining('Exercice 2025 clôturé'), findsOneWidget);
      expect(_facture(m)['aibSubi'], isNull);
      expect(_pieceDe(m), isEmpty);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('un AIB facturé incohérent posé hors modale : refus nommé AIB_FACTURE_INCOHERENT', (t) async {
      final m = _avecFacture(aib: const {'montant': 9000, 'taux': 5, 'baseHt': 200000});
      await _ouvrir(t, m, 'm7-factures-fournisseurs');
      await _toucher(t, find.byTooltip('Constater l’AIB subi').first);
      expect(find.byKey(const Key('aibsubi:constater')), findsNothing, reason: 'le refus tombe avant la fenêtre');
      expect(find.text('AIB subi refusé.'), findsOneWidget);
      expect(find.textContaining('AIB_FACTURE_INCOHERENT'), findsOneWidget);
      expect(_facture(m)['aibSubi'], isNull);
      expect(_pieceDe(m), isEmpty);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('facture archivée entre l\'ouverture de la fenêtre et la validation : refus nommé', (t) async {
      final m = _avecFacture();
      await _ouvrir(t, m, 'm7-factures-fournisseurs');
      await _toucher(t, find.byTooltip('Constater l’AIB subi').first);
      m.collection('facturesFournisseurs').archiver('FFR1');
      await _toucher(t, find.byKey(const Key('aibsubi:constater')));
      expect(find.textContaining('archivée'), findsWidgets);
      expect(_pieceDe(m), isEmpty);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('AIB subi déjà constaté entre l\'ouverture et la validation : refus nommé, une seule pièce', (t) async {
      final m = _avecFacture();
      await _ouvrir(t, m, 'm7-factures-fournisseurs');
      await _toucher(t, find.byTooltip('Constater l’AIB subi').first);
      m.collection('facturesFournisseurs').mettreAJour('FFR1', {'aibSubi': {'montant': 10000, 'taux': 5, 'base': 200000, 'date': '2026-10-12', 'ecritureIds': []}});
      await _toucher(t, find.byKey(const Key('aibsubi:constater')));
      expect(find.textContaining('déjà son AIB subi'), findsOneWidget);
      expect(_pieceDe(m), isEmpty);
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('droits : la commande est offerte à qui écrit, absente de qui ne fait que lire', () {
    testWidgets('le comptable constate ; la Direction (lecture de M7) ne voit pas la commande', (t) async {
      await _ouvrir(t, _avecFacture(), 'm7-factures-fournisseurs', role: 'comptable');
      expect(find.byTooltip('Constater l’AIB subi'), findsOneWidget);
      await _ouvrir(t, _avecFacture(), 'm7-factures-fournisseurs', role: 'direction');
      expect(find.byTooltip('Constater l’AIB subi'), findsNothing);
      expect(find.byTooltip('Modifier'), findsNothing);
    });
  });

  group('m12-aib : le registre « AIB subi » à côté des retenues, l\'imputation en lecture', () {
    testWidgets('sans AIB subi : l\'onglet le dit ; l\'imputation indique 0 + 0 et ne passe aucune écriture', (t) async {
      final m = _avecFacture(aib: null);
      final avant = m.collection('ecritures').actives.length;
      await _ouvrir(t, m, 'm12-aib');
      expect(find.text('Retenues (dette)'), findsOneWidget);
      expect(find.text('AIB subi (créance)'), findsOneWidget);
      await _toucher(t, find.text('AIB subi (créance)'));
      expect(find.textContaining('Aucun AIB subi constaté'), findsOneWidget);
      expect(_texteImputation(t), contains('AIBsubi0FCFA+AIBretenu0FCFA=0FCFA'));
      expect(m.collection('ecritures').actives.length, avant);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('l\'imputation additionne l\'AIB subi ET l\'AIB retenu de l\'exercice, au compte d\'imputation des Paramètres', (t) async {
      final m = _avecFacture(parametres: const [_comptesV2], plus: {
        'aibSubi': {'montant': 10000, 'taux': 5, 'base': 200000, 'date': '2026-10-12', 'compteSubi': '4492'},
        'retenueAib': {'montant': 3000, 'taux': 5, 'base': 60000, 'date': '2026-10-12', 'situation': 'ifu_inactif_ou_absent'},
      });
      await _ouvrir(t, m, 'm12-aib');
      final note = _texteImputation(t);
      expect(note, contains('AIBsubi10000FCFA+AIBretenu3000FCFA=13000FCFA'));
      expect(note, contains('compted’imputation891'));
      await _toucher(t, find.text('AIB subi (créance)'));
      expect(find.text('Registre de l’AIB subi'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });
  });
}
