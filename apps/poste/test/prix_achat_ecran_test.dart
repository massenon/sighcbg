import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// L'ÉCRAN « Référentiel produits » ET LE PRIX D'ACHAT VERSIONNÉ : « Changer le prix d'achat » AJOUTE une version datée au lieu d'écrire sur la fiche, la commande est ABSENTE sans le droit de
/// modifier l'écran, « Valider » n'existe que pour qui détient le geste de décider, la fiche ne reçoit plus le prix de son formulaire de modification, la création pose la version 1 et refuse un prix
/// absent, l'onglet « Produits » de « Tarifs et prix » lit la version en vigueur, et la décision (Oui) arrive de l'onglet Alertes.
const _code = 'ACC';

Magasin monde() {
  final m = magasinM14();
  TarifsPoste.assurerProduits(m);
  return m;
}

Map<String, Object?> fiche(Magasin m, [String code = _code]) => m.collection('produits').actives.firstWhere((p) => p['code'] == code);
num achat(Magasin m, [String code = _code]) => TarifsPoste.prixProduit(m, fiche(m, code), aujourdhui: aujourdhui).achat!;

Future<void> chercher(WidgetTester t, String texte) async {
  await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, texte);
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('la ligne porte « Changer le prix d\'achat » : la modale AJOUTE une version proposée, la fiche et le prix en vigueur ne bougent pas', (t) async {
    final m = monde();
    final avant = fiche(m)['prixAchat'] as num;
    await ouvrirM14(t, m, 'm6-produits', role: 'stock');
    await chercher(t, _code);
    await toucherM14(t, find.byTooltip('Changer le prix d’achat').first);
    expect(find.text('Changer le prix d’achat'), findsWidgets);
    expect(find.byKey(const Key('kit:champ:prixVente')), findsNothing, reason: 'médicament : le prix de vente se DÉRIVE, il ne se saisit pas (RG-02)');
    await saisir(t, 'prixAchat', '${avant + 7}');
    await saisir(t, 'motif', 'Nouveau tarif du fournisseur');
    expect(find.widgetWithText(BoutonSigh, 'Valider'), findsNothing, reason: 'le gestionnaire de stock propose ; valider est le geste de décider');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final vs = TarifsPoste.lire(m).versionsDe(_code);
    expect(vs.length, 2, reason: 'la version 1 est conservée, une version est AJOUTÉE');
    expect([vs.last['statut'], vs.last['prixNonAssure'], vs.last['proposeRole'], vs.last['origine'], vs.last['version']], ['propose', avant + 7, 'stock', 'ecran', 2]);
    expect(fiche(m)['prixAchat'], avant);
    expect(achat(m), avant);
    expect(find.text('Proposition enregistrée : elle attend la décision (Oui ou Non).'), findsOneWidget);
  });

  casM14('un profil qui décide (DAF) valide en un geste : la version prend effet, la fiche suit, le prix de vente d\'un médicament suit sans marge', (t) async {
    final m = monde();
    final avant = fiche(m)['prixAchat'] as num;
    await ouvrirM14(t, m, 'm6-produits', role: 'da');
    await chercher(t, _code);
    await toucherM14(t, find.byTooltip('Changer le prix d’achat').first);
    await saisir(t, 'prixAchat', '${avant + 11}');
    await saisir(t, 'motif', 'Avenant fournisseur');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider'));
    expect([achat(m), fiche(m)['prixAchat'], fiche(m)['prixVente']], [avant + 11, avant + 11, avant + 11]);
    final v = TarifsPoste.lire(m).versionsDe(_code).last;
    expect([v['statut'], v['roleDecision']], ['valide', 'da']);
    expect(find.textContaining('Prix d’achat validé : il prend effet le'), findsOneWidget);
  });

  casM14('un prix refusé se NOMME à la modale (zéro) et n\'écrit rien', (t) async {
    final m = monde();
    await ouvrirM14(t, m, 'm6-produits', role: 'stock');
    await chercher(t, _code);
    await toucherM14(t, find.byTooltip('Changer le prix d’achat').first);
    await saisir(t, 'prixAchat', '0');
    await saisir(t, 'motif', 'Essai');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.textContaining('Un zéro n’est pas un tarif'), findsOneWidget);
    expect(TarifsPoste.lire(m).versionsDe(_code).length, 1);
  });

  casM14('sans le droit de modifier l\'écran, la commande est ABSENTE (jamais grisée) ; l\'historique reste offert', (t) async {
    final m = monde();
    await ouvrirM14(t, m, 'm6-produits', role: 'direction');
    await chercher(t, _code);
    expect(find.byTooltip('Changer le prix d’achat'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    await toucherM14(t, find.byTooltip('Historique de prix').first);
    expect(find.byKey(const Key('prix-achat:historique')), findsOneWidget);
    expect(find.textContaining('Version 1'), findsOneWidget);
    expect(find.textContaining('depuis l’origine'), findsOneWidget, reason: 'la version 1 de reprise n\'a pas de date d\'effet inventée');
  });

  casM14('DÉCISION DU 16/11/2026 : le caissier modifie toujours les produits (stock détail) mais ne voit plus « Changer le prix d\'achat » : proposer un prix d\'achat est un geste réservé', (t) async {
    final m = monde();
    await ouvrirM14(t, m, 'm6-produits', role: 'caissier');
    await chercher(t, _code);
    expect(find.byTooltip('Modifier'), findsWidgets, reason: 'le droit d\'éditer l\'écran est conservé');
    expect(find.byTooltip('Changer le prix d’achat'), findsNothing);
    expect(find.byTooltip('Historique de prix'), findsWidgets, reason: 'la lecture de l\'historique reste offerte');
  });

  casM14('la MODIFICATION de la fiche ne porte plus le prix : le formulaire n\'a ni prix d\'achat ni prix de vente, et enregistrer ne le touche pas', (t) async {
    final m = monde();
    final avant = fiche(m)['prixAchat'] as num;
    await ouvrirM14(t, m, 'm6-produits', role: 'stock');
    await chercher(t, _code);
    await toucherM14(t, find.byTooltip('Modifier').first);
    expect(find.byKey(const Key('kit:champ:prixAchat')), findsNothing);
    expect(find.byKey(const Key('kit:champ:prixVente')), findsNothing);
    await saisir(t, 'emplacement', 'Rayon essai');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(fiche(m)['emplacement'], 'Rayon essai');
    expect([fiche(m)['prixAchat'], fiche(m)['prixVente']], [avant, avant]);
    expect(TarifsPoste.lire(m).versionsDe(_code).length, 1);
  });

  casM14('la CRÉATION pose la version 1 (sans date d\'effet) ; un prix absent est refusé en le nommant ; RG-02 nommé', (t) async {
    final m = monde();
    await ouvrirM14(t, m, 'm6-produits', role: 'stock');
    await toucherM14(t, find.text('Nouveau'));
    await saisir(t, 'code', 'TST-NOUV');
    await saisir(t, 'designation', 'Article d\'essai');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(m.collection('produits').actives.where((p) => p['code'] == 'TST-NOUV'), isEmpty, reason: 'sans prix d\'achat, l\'article ne se crée pas');
    await saisir(t, 'prixAchat', '480');
    await saisir(t, 'prixVente', '900');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(find.textContaining('RG-02 : un médicament se facture au prix d’achat'), findsOneWidget);
    expect(m.collection('produits').actives.where((p) => p['code'] == 'TST-NOUV'), isEmpty);
    await saisir(t, 'prixVente', '');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(fiche(m, 'TST-NOUV')['prixAchat'], 480);
    final vs = TarifsPoste.lire(m).versionsDe('TST-NOUV');
    expect([vs.length, vs.single['version'], vs.single['prixNonAssure'], vs.single['statut'], vs.single['origine'], vs.single.containsKey('dateEffet')], [1, 1, 480, 'valide', 'creation', false]);
  });

  casM14('un article sans prix en vigueur est « à valoriser » : badge, filtre dédié, jamais un zéro', (t) async {
    final m = magasinM14();
    final p = fiche(m);
    m.collection('produits').appliquerDistante({...p}..remove('prixAchat'));
    TarifsPoste.assurerProduits(m);
    await ouvrirM14(t, m, 'm6-produits', role: 'stock');
    await chercher(t, _code);
    expect(find.text('à valoriser'), findsWidgets);
    expect(TarifsPoste.produitsAValoriser(m, aujourdhui: aujourdhui).map((x) => x.produit['code']), [_code]);
  });

  casM14('la proposition du gestionnaire de stock arrive à l\'onglet Alertes de « Tarifs et prix » : le Oui de la DAF met la version en vigueur et la fiche la suit', (t) async {
    final m = monde();
    final avant = fiche(m)['prixAchat'] as num;
    final stock = TarifsPoste(m, role: 'stock', auteur: () => 'Gestionnaire', peutProposerPrixAchat: true, horloge: () => aujourdhui);
    expect(stock.proposerPrixAchat(DemandeProduit(code: _code, prixAchat: avant + 9, dateEffet: tarIso(aujourdhui), motif: 'Hausse')).ok, isTrue);
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    final f = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('kit:onglet:alertes'));
    await toucherM14(t, f.first);
    await chercher(t, _code);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Oui').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Oui, valider'));
    expect([achat(m), fiche(m)['prixAchat'], fiche(m)['prixVente']], [avant + 9, avant + 9, avant + 9]);
    final n = m.collection('notifications').toutes.where((x) => x['type'] == 'prix_decide');
    expect(n.length, 1, reason: 'le retour part au poste de l\'auteur');
  });

  casM14('l\'onglet « Produits » de « Tarifs et prix » lit la VERSION en vigueur (jamais la fiche) : une version décidée mais à venir ne change pas la ligne', (t) async {
    final m = monde();
    final avant = fiche(m)['prixAchat'] as num;
    final da = TarifsPoste(m, role: 'da', auteur: () => 'DAF', peutProposerPrixAchat: true, horloge: () => aujourdhui);
    expect(da.proposerPrixAchat(DemandeProduit(code: _code, prixAchat: avant + 50, dateEffet: '2027-06-01', motif: 'Avenant à venir', valider: true)).ok, isTrue);
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    final f = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('kit:onglet:produits'));
    await toucherM14(t, f.first);
    await chercher(t, _code);
    expect(achat(m), avant, reason: 'à venir : le prix d\'aujourd\'hui ne bouge pas');
    // Les montants sont composés en typographie française (espaces fines) : on compare les CHIFFRES seuls, comme le fait la sonde de la maquette.
    final chiffres = [for (final w in t.widgetList<Text>(find.byType(Text))) (w.data ?? '').replaceAll(RegExp(r'[^0-9]'), '')];
    expect(chiffres.contains('$avant'), isTrue, reason: 'la ligne montre le prix en vigueur aujourd\'hui');
    expect(chiffres.contains('${avant + 50}'), isFalse, reason: 'la version à venir ne se lit pas encore');
  });
}
