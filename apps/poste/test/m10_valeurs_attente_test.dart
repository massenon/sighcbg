import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show gesteRhConfirmerValeur;
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// Les VALEURS D'ATTENTE de M10 (jeu LIVRÉ de Baguidi) : le salaire, la date d'embauche et le tarif d'un vacataire que la Direction n'a pas encore remis sont
/// marqués « provisoire » / « à fournir » (icône ET libellé) ; les modifier les ARRÊTE, dans la même écriture, donc au même journal (RG-12).
Magasin magasinLivre() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('personnel : le salaire d\'attente est MARQUÉ « provisoire » (icône et libellé), et l\'écran dit combien de valeurs attendent', (t) async {
    final m = magasinLivre();
    final attente = m.collection('personnel').actives.where((a) => a['salaireProvisoire'] == true).length;
    expect(attente, greaterThan(0));
    await ouvrirM14(t, m, 'm10-personnel');
    expect(find.text('provisoire'), findsWidgets);
    expect(find.byIcon(LucideIcons.hourglass), findsWidgets);
    expect(find.textContaining('Valeurs d’attente : $attente salaire(s)'), findsOneWidget);
  });

  casM14('personnel : MODIFIER le salaire retire son marquage « provisoire » et le journalise ; la date d\'embauche, laissée telle quelle, garde le sien', (t) async {
    final m = magasinLivre();
    await ouvrirM14(t, m, 'm10-personnel');
    final avant = m.collection('personnel').actives.firstWhere((a) => a['matricule'] == 'm-001');
    expect([avant['salaireProvisoire'], avant['dateEmbaucheProvisoire']], [true, true]);
    final nbAvant = m.collection('personnel').actives.where((a) => a['salaireProvisoire'] == true).length;
    await toucherM14(t, find.byTooltip('Modifier').first);
    await saisir(t, 'salaireBase', '310000');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final apres = m.collection('personnel').actives.firstWhere((a) => a['matricule'] == 'm-001');
    expect(apres['salaireBase'], 310000);
    expect(apres['salaireProvisoire'], false, reason: 'la valeur remise arrête l\'attente');
    expect(apres['dateEmbaucheProvisoire'], true, reason: 'la date n\'a pas bougé : son marquage reste');
    expect(m.collection('personnel').actives.where((a) => a['salaireProvisoire'] == true).length, nbAvant - 1);
    final j = m.collection('audit').toutes.first;
    expect(j['action'], 'Modification');
    expect('${j['avant']}', allOf(contains('250000'), contains('true')));
    expect('${j['apres']}', allOf(contains('310000'), contains('false')));
  });

  casM14('personnel : modifier le téléphone seul n\'arrête AUCUNE valeur d\'attente', (t) async {
    final m = magasinLivre();
    await ouvrirM14(t, m, 'm10-personnel');
    await toucherM14(t, find.byTooltip('Modifier').first);
    await saisir(t, 'telephone', '0197000000');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final a = m.collection('personnel').actives.firstWhere((a) => a['matricule'] == 'm-001');
    expect([a['salaireProvisoire'], a['dateEmbaucheProvisoire']], [true, true]);
  });

  casM14('la fiche d\'édition expose salaire, date d\'embauche, catégorie et CNSS', (t) async {
    final m = magasinLivre();
    await ouvrirM14(t, m, 'm10-personnel');
    await toucherM14(t, find.byTooltip('Modifier').first);
    for (final champ in ['salaireBase', 'dateEmbauche', 'categorie', 'cnss']) {
      expect(find.byKey(Key('kit:champ:$champ')), findsOneWidget, reason: champ);
    }
  });

  casM14('prestataires : le tarif « à fournir » est marqué ; saisir le tarif remis l\'arrête et le journalise', (t) async {
    final m = magasinLivre();
    await ouvrirM14(t, m, 'm10-prestataires');
    expect(find.text('à fournir'), findsWidgets);
    // triés par nom : la première ligne est le premier vacataire alphabétique
    final nomPremier = (m.collection('prestataires').actives.map((p) => '${p['nom']}').toList()..sort()).first;
    expect(find.byKey(Key('kit:champ:tarifActe')), findsNothing);
    await toucherM14(t, find.byTooltip('Modifier').first);
    expect(find.byKey(Key('kit:champ:tarifActe')), findsOneWidget);
    await saisir(t, 'tarifActe', '15000');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final p = m.collection('prestataires').actives.firstWhere((p) => p['nom'] == nomPremier);
    expect(p['tarifActe'], 15000);
    expect(p['tarifAFournir'], false);
    expect('${m.collection('audit').toutes.first['apres']}', contains('15000'));
  });

  // --- Création sans valeur inventée, marquage champ par champ, confirmation motivée (Direction, 16/11/2026) ---------------------------------------------------
  Future<void> ouvrirFiche(WidgetTester t, String nom) async {
    await toucherM14(t, find.text(nom).first);
    await t.pump(const Duration(milliseconds: 400));
  }

  casM14('création d\'un agent : salaire, date d\'embauche, catégorie, CNSS et sexe VIDES ; catégorie et CNSS laissés vides sont marqués « à renseigner »', (t) async {
    final m = magasinLivre();
    await ouvrirM14(t, m, 'm10-personnel');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouveau').first);
    final ctl = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
    for (final k in ['salaireBase', 'dateEmbauche', 'categorie', 'cnss', 'sexe']) {
      expect('${ctl[k] ?? ''}', '', reason: 'aucune valeur inventée pour $k');
    }
    // Salaire et date d'embauche sont EXIGÉS : sans eux, rien n'est écrit.
    final n0 = m.collection('personnel').toutes.length;
    await saisir(t, 'matricule', 'T-1');
    await saisir(t, 'nom', 'TESTEUR');
    await saisir(t, 'prenom', 'Anne');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    expect(m.collection('personnel').toutes.length, n0, reason: 'refus : salaire et date manquent');
    ctl.poser('fonction', 'infirmier');
    ctl.poser('service', ctl['service']);
    await saisir(t, 'salaireBase', '95000');
    ctl.poser('dateEmbauche', '2026-11-02');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Créer'));
    final a = m.collection('personnel').toutes.firstWhere((x) => x['matricule'] == 'T-1');
    expect(a['salaireBase'], 95000);
    expect(a['dateEmbauche'], '2026-11-02');
    expect(a['categorieProvisoire'], true, reason: 'catégorie laissée vide : marquée à renseigner');
    expect(a['cnssProvisoire'], true);
    expect(a['salaireProvisoire'], isNot(true), reason: 'salaire saisi : aucune attente');
    expect(a['dateEmbaucheProvisoire'], isNot(true));
  });

  casM14('confirmer une valeur d\'attente : motif obligatoire (refus nommé sans), puis marquage levé et motif journalisé', (t) async {
    final m = magasinLivre();
    await ouvrirM14(t, m, 'm10-personnel');
    await ouvrirFiche(t, 'BAGUIDI Rafiou');
    expect(find.widgetWithText(BoutonSigh, 'Confirmer'), findsWidgets);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Confirmer').first);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Confirmer').last);
    var a = m.collection('personnel').actives.firstWhere((x) => x['matricule'] == 'm-001');
    expect(a['salaireProvisoire'], true, reason: 'sans motif : refusé');
    expect(find.text('Confirmation refusée.'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Confirmer').first);
    await motifM14(t, 'Confirmer', 'Salaire arrêté par la Direction le 16/11');
    a = m.collection('personnel').actives.firstWhere((x) => x['matricule'] == 'm-001');
    expect(a['salaireProvisoire'], false);
    expect(a['salaireBase'], 250000, reason: 'la valeur est retenue telle quelle');
    expect('${a['confirmationsValeurs']}', allOf(contains('salaireBase'), contains('Salaire arrêté par la Direction le 16/11')));
    final j = m.collection('audit').toutes.first;
    expect('${j['avant']}', contains('true'));
    expect('${j['apres']}', allOf(contains('false'), contains('Salaire arrêté par la Direction le 16/11')));
  });

  casM14('sans le geste « rh_confirmer_valeur », aucun bouton « Confirmer » n\'est offert', (t) async {
    final m = magasinLivre();
    // La clinique retire le geste à la DAF : l'écran reste lisible, la commande disparaît (absente, jamais grisée).
    m.collection('rbac').inserer({'role': 'da', 'statut': 'actif', 'droitsGestes': {gesteRhConfirmerValeur: false}});
    await ouvrirM14(t, m, 'm10-personnel', role: 'da');
    await ouvrirFiche(t, 'BAGUIDI Rafiou');
    expect(find.textContaining('Valeurs d’attente de cet agent'), findsOneWidget, reason: 'l\'attente reste VISIBLE');
    expect(find.widgetWithText(BoutonSigh, 'Confirmer'), findsNothing);
  });
}
