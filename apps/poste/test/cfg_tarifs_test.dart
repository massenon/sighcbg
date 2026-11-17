import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// cfg-tarifs, réécrit sur l'écran UNIQUE « Tarifs et prix » (lot TAR). Ce fichier garde l'INTENTION des neuf tests de l'ancien « Référentiel tarifaire » : indicateurs et
/// onglets qui disent vrai, un prix absent se dit « à valider » (jamais zéro), RG-02 (le prix de vente d'un médicament suit le prix d'achat), les pièces sans tarif nommées,
/// la grille imprimée, et les commandes d'écriture ABSENTES (jamais grisées) sans le droit. Les règles du moteur sont rejouées par `tarifs_poste_test.dart` et le domaine ;
/// le circuit Oui/Non par `tarifs_ecran_test.dart`.
Future<void> onglet(WidgetTester t, String id) async {
  final f = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('kit:onglet:$id'));
  await toucherM14(t, f.first);
}

Future<void> chercher(WidgetTester t, String texte) async {
  await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, texte);
  await t.pump(const Duration(milliseconds: 500));
}

/// Les prestations NON archivées et celles qui n'ont aucun prix en vigueur aujourd'hui, lues du magasin (jamais recopiées).
({int total, int sansPrix, Map<String, int> parFamille}) lecture(Magasin m) {
  final h = TarifsPoste.lire(m);
  final jour = tarIso(aujourdhui);
  final actives = [for (final p in h.tarifs) if (p['statut'] != 'archive') p];
  final fam = <String, int>{};
  for (final p in actives) {
    fam['${p['famille']}'] = (fam['${p['famille']}'] ?? 0) + 1;
  }
  return (total: actives.length, sansPrix: actives.where((p) => h.instantane(p, jour) == null).length, parFamille: fam);
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  Future<void> nouvellePrestation(WidgetTester t, {required String code, required String libelle, required String famille, String? prix, String libelleFamille = ''}) async {
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvelle prestation'));
    await saisir(t, 'code', code);
    await saisir(t, 'libelle', libelle);
    await choisirM14(t, 'famille', famille);
    if (prix != null) await saisir(t, 'prixNonAssure', prix);
    await choisirM14(t, 'etatAssure', 'Prix unique (aucune colonne assurée)');
    await saisir(t, 'motif', 'Test : nouvelle prestation');
  }

  casM14('ouverture : les indicateurs et les comptes des onglets disent ce que le magasin porte (rien de recopié)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    final l = lecture(m);
    expect(find.text('Prestations tarifées'), findsOneWidget);
    expect(find.text('${l.total}'), findsWidgets);
    expect(find.text('${l.total - l.sansPrix}'), findsWidgets, reason: 'Prix en vigueur = prestations moins celles sans prix');
    final nbPrestations = ['CONSULTATION', 'ACTE', 'HOSPITALISATION', 'AMI', 'GYNECO', 'CERTIFICAT'].fold<int>(0, (a, f) => a + (l.parFamille[f] ?? 0));
    expect(find.text('$nbPrestations'), findsWidgets, reason: 'compte de l\'onglet Prestations');
    expect(find.text('${l.parFamille['LABO'] ?? 0}'), findsWidgets, reason: 'compte de l\'onglet Analyses');
    expect(find.text('${m.collection('produits').actives.length}'), findsWidgets, reason: 'compte de l\'onglet Produits');
    expect(find.text('Imprimer la grille'), findsOneWidget);
  });

  casM14('produits : RG-02 en note, LECTURE SEULE (ni Nouveau, ni Modifier, ni Archiver) ; la saisie vit au référentiel des produits, qui applique RG-02', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    await onglet(t, 'produits');
    expect(find.textContaining('RG-02 : un médicament se facture au prix d’achat, sans marge'), findsOneWidget);
    expect(find.text('Sans marge'), findsWidgets);
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing, reason: 'les produits se retirent par le stock, pas ici');
    // Une marge ne peut pas exister sur un médicament du jeu : la colonne le dit pour chacun.
    for (final p in m.collection('produits').actives.where((p) => p['categorie'] == 'medicament')) {
      expect(p['prixVente'], p['prixAchat'], reason: 'RG-02 : ${p['designation']}');
    }
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Ouvrir le référentiel des produits'));
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsOneWidget, reason: 'la création d\'un produit se fait là (RG-02 contrôlé par m6_stock_test)');
  });

  casM14('création d\'un acte : SANS prix en vigueur tant que le Oui n\'est pas donné (« à valider », jamais zéro) ; sans prix ou à zéro, la saisie est refusée', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    final avant = lecture(m);
    await nouvellePrestation(t, code: 'ACT-TEST', libelle: 'Acte Test', famille: 'Actes', prix: '2500');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final h = TarifsPoste.lire(m);
    expect(h.parCode['ACT-TEST']!['famille'], 'ACTE');
    final v = h.versionsDe('ACT-TEST').single;
    expect([v['version'], v['statut'], v['prixNonAssure']], [1, 'propose', 2500], reason: 'une création = une prestation + une version 1, proposée');
    final apres = lecture(m);
    expect(apres.total, avant.total + 1);
    expect(apres.sansPrix, avant.sansPrix + 1, reason: 'absent tant que non décidé : jamais zéro');
    expect(TarifsPoste.prix(m, 'ACT-TEST', tarIso(aujourdhui), false, aujourdhui: aujourdhui).montant, isNull);
    // Le prix absent est refusé à la saisie.
    await t.pump(const Duration(seconds: 10));
    await onglet(t, 'prestations');
    await nouvellePrestation(t, code: 'ACT-SANS', libelle: 'Acte sans prix', famille: 'Actes');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.text('Le formulaire comporte des erreurs.'), findsWidgets);
    expect(TarifsPoste.lire(m).parCode['ACT-SANS'], isNull);
    // Le zéro n'est pas un tarif : refus du moteur, nommé.
    await saisir(t, 'prixNonAssure', '0');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    expect(find.textContaining('Un zéro n’est pas un tarif'), findsWidgets);
    expect(TarifsPoste.lire(m).parCode['ACT-SANS'], isNull);
  });

  casM14('création d\'une analyse : prix proposé puis « Valider » (DAF) ; l\'analyse naît au catalogue lu par la caisse, au prix en vigueur', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    final analysesAvant = m.collection('analyses').actives.length;
    await nouvellePrestation(t, code: 'L49', libelle: 'Analyse Test', famille: 'Analyses de laboratoire', prix: '2500');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider'));
    final p = TarifsPoste.lire(m).parCode['L49']!;
    expect([p['famille'], p['codeAnalyse']], ['LABO', 'L49']);
    expect(TarifsPoste.prix(m, 'L49', tarIso(aujourdhui), false, aujourdhui: aujourdhui).montant, 2500);
    expect(m.collection('analyses').actives.length, analysesAvant + 1, reason: 'la projection de lecture crée la fiche d\'analyse que la caisse et le laboratoire lisent');
    expect(m.collection('analyses').actives.any((a) => a['code'] == 'L49' && a['prix'] == 2500), isTrue);
  });

  casM14('onglet Analyses : la note dit « provisoire » et renvoie le modèle au catalogue du laboratoire ; les valeurs d\'attente portent l\'état « Provisoire »', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    await onglet(t, 'analyses');
    expect(find.textContaining('marqués « provisoire »'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Ouvrir le catalogue des analyses'), findsOneWidget);
    final h = TarifsPoste.lire(m);
    final jour = tarIso(aujourdhui);
    final prov = h.tarifs.where((p) => p['famille'] == 'LABO' && h.instantane(p, jour)?.provisoire == true).length;
    expect(prov, greaterThan(0), reason: 'Baguidi n\'a remis aucune grille : les analyses portent des valeurs d\'attente');
    expect(find.text('Provisoire'), findsWidgets);
  });

  casM14('certificats : famille de « Prestations » (SOS seule lue de la grille) ; les types de pièce sans tarif sont NOMMÉS', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    final sans = [for (final r in m.collection('typesPiece').actives) if (r['tarifCode'] == null || r['tarifCode'] == '') r];
    expect(sans, isNotEmpty, reason: 'le jeu porte des types de pièce sans tarif');
    expect(find.textContaining('type(s) de pièce sans tarif au catalogue'), findsOneWidget);
    expect(find.textContaining('${sans.first['libelle']}'), findsWidgets, reason: 'la pièce est nommée');
    await chercher(t, 'CERT');
    final h = TarifsPoste.lire(m);
    expect(h.tarifs.any((p) => p['famille'] == 'CERTIFICAT' && p['assurable'] == 'sos'), isTrue);
    expect(find.text('SOS seule'), findsWidgets);
    expect(find.widgetWithText(BoutonSigh, 'Ouvrir le catalogue des analyses'), findsNothing);
  });

  casM14('« Imprimer la grille » : l\'état porte les prix en vigueur ; une prestation sans prix n\'est jamais imprimée à zéro, le cartouche la COMPTE', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'da');
    await nouvellePrestation(t, code: 'ACT-GRILLE', libelle: 'Acte Grille', famille: 'Actes', prix: '2500');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    await t.pump(const Duration(seconds: 10));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer la grille'));
    expect(find.text('Grille tarifaire'), findsWidgets);
    expect(find.textContaining('Prix en vigueur au'), findsWidgets);
    expect(find.textContaining('Prestations imprimées'), findsWidgets);
    expect(find.textContaining('Sans prix en vigueur (non imprimées)'), findsWidgets, reason: 'la prestation créée sans Oui manque à la grille, et la grille le dit');
  });

  casM14('droits : en lecture seule, aucune commande d\'écriture (absentes, jamais grisées), le bandeau le dit, l\'impression reste offerte', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-tarifs'));
    expect(find.widgetWithText(BoutonSigh, 'Nouvelle prestation'), findsNothing);
    expect(find.byTooltip('Proposer un changement'), findsNothing);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Imprimer la grille'), findsOneWidget);
    await onglet(t, 'alertes');
    expect(find.widgetWithText(BoutonSigh, 'Oui'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Non'), findsNothing);
  });

  casM14('AJ (16/11/2026) : « sans prix » est VU DE TOUS ; « Tarifer » n’est offert qu’au geste de décider un prix', (t) async {
    Magasin avecSansPrix() {
      final m = magasinM14();
      m.collection(tarCollectionTarifs).ajouterSansJournal({'id': 'ACT-SANS', 'code': 'ACT-SANS', 'codeActe': 'ACT-SANS', 'libelle': 'Acte sans prix', 'famille': 'ACTE', 'statut': 'actif'});
      return m;
    }

    await ouvrirM14(t, avecSansPrix(), 'cfg-tarifs', role: 'da');
    await onglet(t, 'sansprix');
    await chercher(t, 'ACT-SANS');
    expect(find.text('Acte sans prix'), findsWidgets);
    expect(find.byKey(const Key('cft:tarifer:ACT-SANS')), findsOneWidget, reason: 'la DAF détient le geste de décider un prix');

    await ouvrirM14(t, avecSansPrix(), 'cfg-tarifs', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-tarifs'));
    await onglet(t, 'sansprix');
    await chercher(t, 'ACT-SANS');
    expect(find.text('Acte sans prix'), findsWidgets, reason: 'l’indication « sans prix » ne dépend d’aucun droit');
    expect(find.text('Sans prix en vigueur'), findsWidgets);
  });

  test('AJ : « Tarifer » suit le geste réservé de la matrice, jamais un rôle écrit en dur', () {
    final m = magasinM14();
    final sans = TarifsPoste(m, role: 'caissier', auteur: () => 'x', fileul: false, peutEditerEcran: true, horloge: () => aujourdhui);
    final avec = TarifsPoste(m, role: 'da', auteur: () => 'x', fileul: false, peutEditerEcran: true, horloge: () => aujourdhui);
    expect(sans.peutDecider, isFalse);
    expect(avec.peutDecider, isTrue);
  });
}
