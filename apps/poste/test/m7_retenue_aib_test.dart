import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// La retenue d'AIB sur facture fournisseur, AU GESTE : le taux vient du barème daté par situation (`situationsAib`, `baremeAib`), la pièce naît plate et équilibrée en brouillon, la facture la porte,
/// le registre la relit ; une seconde retenue et une date antérieure au barème sont refusées en le disant.
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

Magasin _avecFacture(String date, {num? ht, num? tva, List<Map<String, Object?>> parametres = const []}) {
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
    'montantLivraison': 200000,
    'montantFacture': 200000,
    if (ht != null) 'montantHT': ht,
    if (tva != null) 'montantTVA': tva,
    'ecart': 0,
    'statutRappro': 'rapproche',
    'statutPaiement': 'impayee',
    'statut': 'actif',
  });
  return m;
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  testWidgets('retenir l\'AIB : 5 % de 200 000 = 10 000, pièce plate en brouillon 401000/4478, facture porteuse, registre', (t) async {
    final m = _avecFacture('2026-10-12');
    await _ouvrir(t, m, 'm7-factures-fournisseurs');
    await _toucher(t, find.byTooltip('Retenir l’AIB').first);
    await _toucher(t, find.widgetWithText(BoutonSigh, 'Constater la retenue'));
    final f = m.collection('facturesFournisseurs').parId('FFR1')!;
    final r = (f['retenueAib'] as Map).cast<String, Object?>();
    expect(r['montant'], 10000);
    expect(r['taux'], 5);
    expect(r['situation'], 'ifu_inactif_ou_absent', reason: 'la catégorie de la retenue EST une situation de l\'acheteur');
    expect(r['versionId'], 'BAI01', reason: 'la retenue porte la version du barème sous laquelle elle a été calculée');
    expect(r['reversement'], '2026-11-10');
    final nouvelles = [for (final e in m.collection('ecritures').actives) if (e['pieceId'] == 'FFR1') e];
    expect(nouvelles.length, 2);
    expect(nouvelles.every((e) => e['statut'] == 'brouillon'), isTrue);
    expect(nouvelles.firstWhere((e) => e['compte'] == '401000')['debit'], 10000);
    expect(nouvelles.firstWhere((e) => e['compte'] == '4478')['credit'], 10000);
    expect(find.byTooltip('Retenir l’AIB'), findsNothing, reason: 'une facture ne porte qu\'une retenue');
    // Le registre (écran du barème) relit la retenue.
    await _ouvrir(t, m, 'm12-aib');
    expect(find.text('Registre des retenues d’AIB'), findsOneWidget);
    expect(find.text('FF-TEST-0001'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
  });

  // D7 (Direction, 09/11/2026) : la base de la retenue est le montant HORS TAXES quand il est renseigné ; sinon le montant facturé, et la fenêtre le DIT.
  testWidgets('D7 base HT : 5 % de 169 492 (hors taxes) et non de 200 000 (facturé) ; la fenêtre dit quelle base sert, la facture la porte', (t) async {
    final m = _avecFacture('2026-10-12', ht: 169492, tva: 30508);
    await _ouvrir(t, m, 'm7-factures-fournisseurs');
    await _toucher(t, find.byTooltip('Retenir l’AIB').first);
    expect(find.byKey(const Key('retenue:base')), findsOneWidget);
    expect(find.textContaining('Base : montant hors taxes de la facture'), findsOneWidget);
    await _toucher(t, find.widgetWithText(BoutonSigh, 'Constater la retenue'));
    final r = (m.collection('facturesFournisseurs').parId('FFR1')!['retenueAib'] as Map).cast<String, Object?>();
    expect([r['base'], r['montant'], r['baseSource']], [169492, 8475, 'ht']);
    expect(r['baseMotif'], contains('hors taxes'));
    final plat = [for (final e in m.collection('ecritures').actives) if (e['pieceId'] == 'FFR1') e];
    expect(plat.firstWhere((e) => e['compte'] == '4478')['credit'], 8475);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('D7 sans hors taxes : REPLI sur le montant facturé, annoncé dans la fenêtre et porté par la retenue', (t) async {
    final m = _avecFacture('2026-10-12');
    await _ouvrir(t, m, 'm7-factures-fournisseurs');
    await _toucher(t, find.byTooltip('Retenir l’AIB').first);
    expect(find.textContaining('Hors taxes non renseigné sur cette facture'), findsOneWidget);
    expect(find.textContaining('MONTANT FACTURÉ'), findsWidgets);
    await _toucher(t, find.widgetWithText(BoutonSigh, 'Constater la retenue'));
    final r = (m.collection('facturesFournisseurs').parId('FFR1')!['retenueAib'] as Map).cast<String, Object?>();
    expect([r['base'], r['montant'], r['baseSource']], [200000, 10000, 'facture']);
    expect(r['baseMotif'], contains('MONTANT FACTURÉ'));
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('D7 la base validée aux Paramètres « montant facturé » à compter du 20/10/2026 s\'applique aux factures de cette date, pas aux plus anciennes', (t) async {
    const v2 = {
      'id': 'PAA-BASE-2', 'statut': 'actif', 'rubrique': 'base_retenue', 'version': 2, 'base': 'facture', 'dateEffet': '2026-10-20',
      'decideur': 'Direction', 'dateDecision': '2026-10-15', 'motif': 'Avis de l\'expert-comptable',
    };
    // facture du 25/10 : la version 2 est en vigueur → montant facturé même avec un HT renseigné
    final m = _avecFacture('2026-10-25', ht: 169492, tva: 30508, parametres: const [v2]);
    await _ouvrir(t, m, 'm7-factures-fournisseurs');
    await _toucher(t, find.byTooltip('Retenir l’AIB').first);
    expect(find.textContaining('Base : montant facturé (choix des Paramètres, v2)'), findsOneWidget);
    await _toucher(t, find.widgetWithText(BoutonSigh, 'Constater la retenue'));
    var r = (m.collection('facturesFournisseurs').parId('FFR1')!['retenueAib'] as Map).cast<String, Object?>();
    expect([r['base'], r['montant'], r['baseSource']], [200000, 10000, 'facture']);
    // facture du 12/10 : la version 1 (hors taxes) est celle de sa date
    final m2 = _avecFacture('2026-10-12', ht: 169492, tva: 30508, parametres: const [v2]);
    await _ouvrir(t, m2, 'm7-factures-fournisseurs');
    await _toucher(t, find.byTooltip('Retenir l’AIB').first);
    expect(find.textContaining('Base : montant hors taxes de la facture'), findsOneWidget);
    await _toucher(t, find.widgetWithText(BoutonSigh, 'Constater la retenue'));
    r = (m2.collection('facturesFournisseurs').parId('FFR1')!['retenueAib'] as Map).cast<String, Object?>();
    expect([r['base'], r['baseSource']], [169492, 'ht']);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('D7 la saisie de la facture : hors taxes et TVA facultatifs, cohérents avec le montant facturé, refusés sinon', (t) async {
    final m = _avecFacture('2026-10-12');
    await _ouvrir(t, m, 'm7-factures-fournisseurs');
    await _toucher(t, find.byTooltip('Modifier').first);
    expect(find.text('Montant hors taxes (FCFA)'), findsWidgets);
    expect(find.text('TVA (FCFA, ligne séparée)'), findsWidgets);
    await t.enterText(find.descendant(of: find.byKey(const Key('kit:champ:montantHT')), matching: find.byType(TextField)), '250000');
    await t.pump();
    await _toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.textContaining('FACTURE_HT_SUPERIEUR'), findsWidgets, reason: 'le hors-taxes dépasse le facturé (200 000) : refus nommé');
    expect(m.collection('facturesFournisseurs').parId('FFR1')!['montantHT'], isNull);
    await t.enterText(find.descendant(of: find.byKey(const Key('kit:champ:numero')), matching: find.byType(TextField)), 'F-1');
    await t.enterText(find.descendant(of: find.byKey(const Key('kit:champ:montantHT')), matching: find.byType(TextField)), '169492');
    await t.enterText(find.descendant(of: find.byKey(const Key('kit:champ:montantTVA')), matching: find.byType(TextField)), '30508');
    await t.pump();
    await _toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final f = m.collection('facturesFournisseurs').parId('FFR1')!;
    expect([f['montantHT'], f['montantTVA']], [169492, 30508]);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('une facture antérieure au barème arrêté (07/09/2026) est REFUSÉE en le disant, rien n\'est écrit', (t) async {
    final m = _avecFacture('2026-08-12');
    final avant = m.collection('ecritures').actives.length;
    await _ouvrir(t, m, 'm7-factures-fournisseurs');
    await _toucher(t, find.byTooltip('Retenir l’AIB').first);
    expect(find.textContaining('Aucun taux d’AIB arrêté'), findsWidgets);
    expect(m.collection('ecritures').actives.length, avant);
    expect(m.collection('facturesFournisseurs').parId('FFR1')!['retenueAib'], isNull);
    await t.pump(const Duration(seconds: 10));
  });
}
