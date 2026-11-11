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

  /// Archiver un poste PORTEUR par l'écran : motif, puis le toast. Rend le magasin pour que le test lise ce qui est écrit.
  Future<void> archiverParEcran(WidgetTester t, int rang, String motif) async {
    await toucherM14(t, find.text('Organigramme').first);
    await toucherM14(t, find.byTooltip('Archiver').at(rang));
    await t.enterText(find.byType(TextField).last, motif);
    await t.pump();
  }

  List<String> enfantsActifs(Magasin m, String id) => [for (final p in m.collection('postes').actives) if (p['parentId'] == id) '${p['id']}'];

  casM14('archiver un poste de 4 sous-postes : la confirmation les nomme, ils passent au parent (un geste, journalisé), la scène du PDF n’a aucune boîte orpheline ; annuler les restitue', (t) async {
    final m = livre();
    final col = m.collection('postes');
    final avant = enfantsActifs(m, 'PST005');
    expect(avant.length, 4);
    await ouvrirM14(t, m, 'cfg-organisation');
    await archiverParEcran(t, 4, 'Réorganisation');
    // (1) la confirmation DIT combien, lesquels et vers quel poste.
    expect(find.textContaining('4 sous-postes seront réaffectés'), findsOneWidget);
    expect(find.textContaining('« Agent De Sécurité »'), findsOneWidget);
    expect(find.textContaining('« Directeur Général/ Médecin chef »'), findsOneWidget);
    await t.tap(find.widgetWithText(BoutonSigh, 'Archiver').last);
    await t.pump(const Duration(milliseconds: 400));
    // (2) les sous-postes sont rattachés au parent du poste archivé ; le poste est archivé, jamais supprimé (RG-14).
    for (final id in avant) {
      expect(col.parId(id)!['parentId'], 'PST001', reason: id);
      expect(col.parId(id)!['statut'] ?? 'actif', isNot('archive'));
    }
    expect(col.actives.any((p) => p['id'] == 'PST005'), isFalse);
    expect(col.toutes.any((p) => p['id'] == 'PST005'), isTrue);
    // Le journal porte, pour CHAQUE sous-poste, l'ancien et le nouveau rattachement (RG-12).
    final reaff = m.collection('audit').toutes.where((e) => e['action'] == 'Modification' && e['avant'] is Map && (e['avant'] as Map)['parentId'] == 'PST005').toList();
    expect(reaff.length, 4, reason: 'une ligne de journal par sous-poste réaffecté');
    expect(reaff.every((e) => (e['apres'] as Map)['parentId'] == 'PST001'), isTrue);
    expect(m.collection('audit').toutes.where((e) => e['action'] == 'Archivage').length, 1, reason: 'un seul archivage');
    // (7) la scène du PDF paysage : aucune boîte orpheline — chaque case non sommet est reliée à un parent encore dessiné.
    final sc = scene(m);
    final ids = sc.cases.map((c) => c.id).toSet();
    expect(ids, isNot(contains('PST005')));
    for (final id in avant) {
      expect(ids, contains(id));
      final k = sc.cases.firstWhere((c) => c.id == id);
      expect(sc.traits.any((tr) => tr.x2 >= k.x && tr.x2 <= k.x + k.l && tr.y2 >= k.y && tr.y2 <= k.bas), isTrue, reason: 'un trait aboutit à la boîte de $id');
    }
    final octets = await pdfFichePaysage(fiche(m), await PolicesPdf.charger());
    expect(octets.length, greaterThan(1000));
    // (3) l'annulation restitue les rattachements d'origine.
    await t.tap(find.text('Annuler').last);
    await t.pump(const Duration(milliseconds: 400));
    for (final id in avant) {
      expect(col.parId(id)!['parentId'], 'PST005', reason: id);
    }
    expect(col.actives.any((p) => p['id'] == 'PST005'), isTrue);
    await t.pump(const Duration(seconds: 6));
  });

  casM14('annuler l’archivage : un sous-poste modifié entre-temps n’est PAS écrasé, et le toast le nomme', (t) async {
    final m = livre();
    final col = m.collection('postes');
    await ouvrirM14(t, m, 'cfg-organisation');
    await archiverParEcran(t, 4, 'Réorganisation');
    await t.tap(find.widgetWithText(BoutonSigh, 'Archiver').last);
    await t.pump(const Duration(milliseconds: 400));
    col.mettreAJour('PST016', {'parentId': 'PST007'}); // modifié entre-temps
    await t.tap(find.text('Annuler').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(col.parId('PST016')!['parentId'], 'PST007', reason: 'non écrasé');
    expect(col.parId('PST017')!['parentId'], 'PST005');
    expect(find.textContaining('modifié entre-temps'), findsOneWidget);
    expect(find.textContaining('« Agent De Sécurité »'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
  });

  test('un SOMMET archivé : ses sous-postes deviennent des sommets, la scène du PDF les place sans orphelin ; la restauration ne ré-attache pas d’office et le dit', () {
    final m = livre();
    final col = m.collection('postes');
    // Un sommet de test portant deux sous-postes.
    col.inserer({'id': 'PSTX', 'poste': 'Sommet X', 'parentId': null, 'effectif': 1, 'role': 'agentadmin', 'statut': 'actif'});
    col.mettreAJour('PST002', {'parentId': 'PSTX'});
    col.mettreAJour('PST003', {'parentId': 'PSTX'});
    final plan = cfaPlanArchivagePoste(col.actives, 'PSTX');
    expect(plan.nouveauParentId, isNull);
    for (final r in plan.reaffectations) {
      col.mettreAJour(r.id, {'parentId': r.nouveauParentId});
    }
    col.mettreAJour('PSTX', {'sousPostesReaffectes': [for (final r in plan.reaffectations) r.toJson()]});
    col.archiver('PSTX');
    expect(col.parId('PST002')!['parentId'], isNull);
    expect(col.parId('PST003')!['parentId'], isNull);
    expect(cfaArbre(col.actives).map((n) => n.fiche['id']), containsAll(['PST002', 'PST003']));
    final sc = scene(m);
    expect(sc.cases.map((c) => c.id), containsAll(['PST002', 'PST003']));
    // Restauration : rien n'est rattaché d'office, la note le dit.
    col.restaurer('PSTX');
    expect(col.parId('PST002')!['parentId'], isNull);
    expect(cfaNoteRestaurationPoste(col.parId('PSTX')!, col.actives), allOf(contains('PAS rattachés'), contains('Médecin Généraliste')));
  });
}
