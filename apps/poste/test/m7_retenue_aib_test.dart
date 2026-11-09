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

Magasin _avecFacture(String date) {
  final m = _magasin();
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
