import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/impression/fiche_organigramme.dart';
import 'package:sigh_poste/impression/identite_poste.dart';
import 'package:sigh_poste/impression/pdf.dart';
import 'package:sigh_poste/impression/piece.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/cfg/cfa_commun.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// L'organigramme est MODIFIABLE (Direction, 11/11/2026) : réaffecter un poste, changer son titulaire (choisi au personnel), porter un titre, archiver — et
/// l'impression suit. Les droits de modification sont ceux de la matrice : sans eux, les commandes sont absentes.
Magasin livre() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

FichePaysage fiche(Magasin m) => fichePaysageOrganigramme(m, utilisateur: 'BAGUIDI Rafiou', edite: DateTime(2026, 11, 11, 9, 30), reference: 'CBG-20261111-0001');

SceneOrganigramme scene(Magasin m) => (fiche(m).pages[0] as PageGraphe).scene;

void main() {
  setUpAll(() async {
    await chargerPolices();
    cfaPoserNavigation(donneesNav);
  });
  tearDown(() {
    ToastsSigh.viderPourTests();
    IdentiteClinique.reinitialiser();
  });

  test('le titre porté par l’agent titulaire entre dans la boîte du poste (écran et PDF lisent la même scène) ; il suit le dossier du personnel', () async {
    final m = livre();
    final agent = m.collection('personnel').actives.firstWhere((a) => '${a['nomComplet']}' != 'BAGUIDI Rafiou');
    m.collection('postes').mettreAJour('PST014', {'titulaire': '${agent['nomComplet']}', 'personnelId': agent['id']});
    expect(scene(m).cases.firstWhere((c) => c.id == 'PST014').titre, '', reason: 'sans titre porté, la boîte est inchangée');
    m.collection('personnel').mettreAJour(agent['id'], {'titreOrganigramme': 'SG'});
    var k = scene(m).cases.firstWhere((c) => c.id == 'PST014');
    expect((k.texte, k.titre), ('RSI', '(SG)'));
    expect(cfaTitulaireDuPoste(m, m.collection('postes').actives.firstWhere((p) => p['id'] == 'PST014')), '${agent['nomComplet']} (SG)');
    // Le titre se change au dossier de l'agent : la boîte suit, sans toucher au poste.
    m.collection('personnel').mettreAJour(agent['id'], {'titreOrganigramme': 'SG adj.'});
    expect(scene(m).cases.firstWhere((c) => c.id == 'PST014').titre, '(SG adj.)');
    // Le PDF paysage se produit avec le titre porté.
    final p = await PolicesPdf.charger();
    final octets = await pdfFichePaysage(fiche(m), p);
    expect(octets.length, greaterThan(1000));
  });

  test('un poste réaffecté : le graphe et la légende suivent ; archivé, il disparaît sans que la fiche soit supprimée (RG-14)', () {
    final m = livre();
    final avant = scene(m);
    m.collection('postes').mettreAJour('PST003', {'parentId': 'PST010', 'lien': 'direct', 'niveau': 3});
    final apres = scene(m);
    final mg = apres.cases.firstWhere((c) => c.id == 'PST003');
    final rl = apres.cases.firstWhere((c) => c.id == 'PST010');
    expect(apres.traits.any((t) => t.x1 == t.x2 && t.y1 == rl.bas && t.y2 == mg.y), isTrue, reason: 'une descente droite relie RL à MG');
    expect(apres.traits, isNot(equals(avant.traits)));
    m.collection('postes').archiver('PST003');
    expect(scene(m).cases.any((c) => c.id == 'PST003'), isFalse);
    expect((fiche(m).pages[1] as PageLegende).lignes.map((l) => l.code), isNot(contains('MG')));
    expect(m.collection('postes').toutes.any((p) => p['id'] == 'PST003'), isTrue, reason: 'archivé, jamais supprimé');
    expect(m.collection('postes').actives.any((p) => p['id'] == 'PST003'), isFalse);
  });

  test('un titulaire remplacé : le nom suit, le titre porté est celui du NOUVEL agent ; un poste sans titulaire est vacant', () {
    final m = livre();
    final agents = m.collection('personnel').actives.where((a) => '${a['nomComplet']}' != 'BAGUIDI Rafiou').toList();
    m.collection('personnel').mettreAJour(agents[0]['id'], {'titreOrganigramme': 'SG'});
    m.collection('postes').mettreAJour('PST014', {'titulaire': '${agents[0]['nomComplet']}', 'personnelId': agents[0]['id']});
    expect(scene(m).cases.firstWhere((c) => c.id == 'PST014').titre, '(SG)');
    m.collection('postes').mettreAJour('PST014', {'titulaire': '${agents[1]['nomComplet']}', 'personnelId': agents[1]['id']});
    expect(scene(m).cases.firstWhere((c) => c.id == 'PST014').titre, '', reason: 'le titre appartient à l’agent, pas au poste');
    final p = m.collection('postes').actives.firstWhere((x) => x['id'] == 'PST014');
    expect(agentDuPoste(m, p)!['id'], agents[1]['id']);
    m.collection('postes').mettreAJour('PST014', {'titulaire': '', 'personnelId': ''});
    expect(agentDuPoste(m, m.collection('postes').actives.firstWhere((x) => x['id'] == 'PST014')), isNull);
  });

  casM14('à l’écran : les postes sans titulaire disent « Poste vacant » ; le titulaire se choisit parmi le personnel et le poste enregistre son nom ET son lien', (t) async {
    final m = livre();
    final agent = m.collection('personnel').actives.firstWhere((a) => '${a['nomComplet']}' != 'BAGUIDI Rafiou');
    m.collection('personnel').mettreAJour(agent['id'], {'titreOrganigramme': 'SG'});
    await ouvrirM14(t, m, 'cfg-organisation');
    await toucherM14(t, find.text('Organigramme').first);
    expect(find.text('Poste vacant'), findsWidgets);
    expect(find.byKey(const Key('organigramme:vacant:PST002')), findsOneWidget);
    expect(find.byKey(const Key('organigramme:titulaire:PST001')), findsOneWidget);
    // Modifier un poste : la liste des titulaires est le personnel (on y cherche l'agent par son nom).
    await toucherM14(t, find.byTooltip('Modifier').at(1));
    await choisirM14(t, 'personnelId', '${agent['nomComplet']}${'${agent['poste'] ?? ''}'.isNotEmpty ? ' — ${agent['poste']}' : ''}');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer'));
    final modifies = m.collection('postes').actives.where((p) => '${p['personnelId'] ?? ''}' == '${agent['id']}').toList();
    expect(modifies.length, 1);
    expect(modifies.single['titulaire'], '${agent['nomComplet']}');
    expect(find.text('${agent['nomComplet']} (SG)'), findsWidgets, reason: 'le titre porté s’écrit à côté du nom');
    await t.pump(const Duration(seconds: 6));
  });

  casM14('droits : sans le droit de modifier, créer, réaffecter, changer le titulaire et archiver sont ABSENTS ; l’impression reste', (t) async {
    final m = livre();
    await ouvrirM14(t, m, 'cfg-organisation', role: 'admin', donnees: donneesLectureSeule('admin', 'cfg-organisation'));
    await toucherM14(t, find.text('Organigramme').first);
    expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
    expect(find.byTooltip('Modifier'), findsNothing);
    expect(find.byTooltip('Archiver'), findsNothing);
    expect(find.widgetWithText(BoutonSigh, 'Imprimer l’organigramme'), findsOneWidget);
    expect(find.text('Poste vacant'), findsWidgets);
    await t.pump(const Duration(seconds: 6));
  });
}
