import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
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
}
