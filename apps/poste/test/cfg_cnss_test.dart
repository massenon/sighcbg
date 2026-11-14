import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LA CNSS EN DEUX OBLIGATIONS, AU GESTE (décision de la Direction du 09/11/2026) : la « Déclaration unique (ITS, VPS, déclaration CNSS) » au 10 et le
/// « versement des cotisations » au 15, ce dernier MARQUÉ NON ARRÊTÉ (le 15 vient de guides ; à confirmer auprès de la CNSS). Les règles du domaine sont
/// sondées dans `packages/domaine/test/cfb_cnss_test.dart` ; ici, les ÉCRANS du jeu LIVRÉ de Baguidi : référence (`cfg-comptabilite`), suivi
/// (`m12-echeances`), la modification datée qui régénère les échéances non payées, et l'arrêt qui retire le marquage.
Magasin magasinLivre() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  Finder badge(String code) => find.byKey(Key('cfb:nonarretee:$code'));
  Fiche vers(Magasin m) => m.collection('obligationsFiscales').actives.firstWhere((f) => f['code'] == 'CNSS-VERS');
  List<Fiche> echeancesVers(Magasin m, {bool archivees = false}) =>
      [for (final e in m.collection('echeancesFiscales').toutes) if (e['code'] == 'CNSS-VERS' && (e['statut'] == 'archive') == archivees) e]
        ..sort((a, b) => '${a['echeanceTheorique']}'.compareTo('${b['echeanceTheorique']}'));

  casM14('cfg-comptabilite : les DEUX lignes CNSS sont là, seule la nouvelle est marquée NON ARRÊTÉE, avec son motif et sa commande « Arrêter »', (t) async {
    final m = magasinLivre();
    await ouvrirM14(t, m, 'cfg-comptabilite');
    expect(find.text('Déclaration unique (ITS, VPS, déclaration CNSS)'), findsOneWidget);
    expect(find.text('CNSS, versement des cotisations'), findsOneWidget);
    expect(find.byKey(const Key('cfb:modifier:CNSS')), findsOneWidget);
    expect(find.byKey(const Key('cfb:modifier:CNSS-VERS')), findsOneWidget);
    expect(badge('CNSS-VERS'), findsOneWidget, reason: 'le versement est marqué non arrêté, à l\'écran');
    expect(badge('CNSS'), findsNothing, reason: 'la déclaration unique est arrêtée : aucun marquage');
    expect(badge('ITS'), findsNothing);
    final bandeau = t.widget<NoteSigh>(find.byKey(const Key('cfb:nonarretees')));
    expect(bandeau.texte, contains('CNSS-VERS'));
    expect(bandeau.texte, contains('le 15 du mois suivant'));
    expect(bandeau.texte, contains('CNSS'), reason: 'le motif nomme ce qu\'il faut confirmer');
    expect(find.byKey(const Key('cfb:arreter:CNSS-VERS')), findsOneWidget, reason: 'l\'administrateur arrête les dates');
    expect(find.byKey(const Key('cfb:arreter:CNSS')), findsNothing, reason: 'rien à arrêter sur une date déjà arrêtée');
    // les deux parts de cotisation sont dites dans la règle appliquée, jamais codées ailleurs
    expect(vers(m)['note'], allOf(contains('16,4 %'), contains('3,6 %')));
  });

  casM14('en lecture seule, le marquage reste visible mais la commande « Arrêter » est ABSENTE', (t) async {
    final m = magasinLivre();
    await ouvrirM14(t, m, 'cfg-comptabilite', donnees: donneesLectureSeule('admin', 'cfg-comptabilite'));
    expect(badge('CNSS-VERS'), findsOneWidget);
    expect(find.byKey(const Key('cfb:arreter:CNSS-VERS')), findsNothing);
    expect(find.byKey(const Key('cfb:modifier:CNSS-VERS')), findsNothing);
  });

  casM14('modifier le jour avec date d\'effet : les échéances non payées sont régénérées, les payées et les antérieures ne bougent pas, la date reste NON ARRÊTÉE', (t) async {
    final m = magasinLivre();
    final avant = echeancesVers(m);
    expect(avant.length, 12);
    final payeesAvant = [for (final e in avant) if (e['paye'] == true) '${e['reference']}'];
    expect(payeesAvant, isNotEmpty);
    await ouvrirM14(t, m, 'cfg-comptabilite');
    await toucherM14(t, find.byKey(const Key('cfb:modifier:CNSS-VERS')));
    await saisir(t, 'jour', '16');
    await toucherM14(t, find.byKey(const Key('cfb:obligation:continuer')));
    expect(find.text('Portée de la modification'), findsOneWidget);
    expect(find.byKey(const Key('cfb:portee:impact')), findsOneWidget, reason: 'la modale annonce ce que la régénération fait des échéances');
    await saisir(t, 'motif', 'La CNSS précise le 16');
    await toucherM14(t, find.byKey(const Key('cfb:portee:appliquer')));
    final f = vers(m);
    expect([f['jour'], f['dateEffet']], [16, '2026-10-30']);
    expect(f['statutArret'], 'non_arrete', reason: 'modifier le jour n\'arrête rien');
    expect(badge('CNSS-VERS'), findsOneWidget);
    final apres = echeancesVers(m);
    expect(apres.length, 12, reason: 'toujours douze versements actifs');
    expect([for (final e in apres) if (e['paye'] == true) '${e['reference']}'], payeesAvant, reason: 'une quittance ne bouge jamais');
    // les mois antérieurs à la date d'effet gardent le 15 ; novembre et décembre passent au 16 (le 16/11 est un lundi, le 16/12 un mercredi)
    for (final e in apres) {
      final theorique = '${e['echeanceTheorique']}';
      expect(theorique.endsWith(theorique.compareTo('2026-10-30') >= 0 ? '-16' : '-15'), isTrue, reason: theorique);
    }
    final archivees = echeancesVers(m, archivees: true);
    expect(archivees.map((e) => e['echeanceTheorique']), ['2026-11-15', '2026-12-15'], reason: 'seules les non payées à partir de la date d\'effet sont archivées (RG-14)');
    expect(m.collection('historiqueObligations').actives.where((h) => h['code'] == 'CNSS-VERS').single['jour'], 15, reason: 'la version sortante est à l\'historique');
    // la déclaration unique n'a pas bougé
    expect(m.collection('echeancesFiscales').toutes.where((e) => e['code'] == 'CNSS' && e['statut'] == 'archive'), isEmpty);
  });

  casM14('« Arrêter la date » : décideur et date écrits sur la fiche, le marquage et la commande disparaissent, aucune échéance n\'est touchée, UNE ligne de journal', (t) async {
    final m = magasinLivre();
    final echeancesAvant = m.collection('echeancesFiscales').toutes.length;
    await ouvrirM14(t, m, 'cfg-comptabilite');
    final journal = m.collection('audit').toutes.length;
    await toucherM14(t, find.byKey(const Key('cfb:arreter:CNSS-VERS')));
    expect(find.text('Arrêter la date de CNSS-VERS'), findsOneWidget);
    // sans décideur : refusé, rien n'est écrit
    await saisir(t, 'decideur', '');
    await toucherM14(t, find.byKey(const Key('cfb:arreter:confirmer')));
    expect(find.text('Décideur et date de l’arrêt sont obligatoires.'), findsOneWidget);
    expect(vers(m)['statutArret'], 'non_arrete');
    await t.pump(const Duration(seconds: 10));
    await saisir(t, 'decideur', 'Direction (décision du 09/11/2026)');
    await toucherM14(t, find.byKey(const Key('cfb:arreter:confirmer')));
    final f = vers(m);
    expect([f['statutArret'], f['decideurArret'], f['dateArret']], ['arrete', 'Direction (décision du 09/11/2026)', '2026-10-30']);
    expect(f['jour'], 15, reason: 'arrêter ne change pas le jour');
    expect(badge('CNSS-VERS'), findsNothing, reason: 'le marquage disparaît quand la Direction arrête la date');
    expect(find.byKey(const Key('cfb:nonarretees')), findsNothing, reason: 'plus aucune date non arrêtée : le bandeau tombe aussi');
    expect(find.byKey(const Key('cfb:arreter:CNSS-VERS')), findsNothing);
    expect(find.byKey(const Key('cfb:arretee:CNSS-VERS')), findsOneWidget, reason: 'l\'écran dit qui a arrêté et quand');
    expect(m.collection('echeancesFiscales').toutes.length, echeancesAvant, reason: 'arrêter ne régénère rien');
    expect(m.collection('audit').toutes.length, journal + 1, reason: 'RG-12 : une ligne de journal pour l\'arrêt');
    expect(m.collection('historiqueObligations').actives.where((h) => h['code'] == 'CNSS-VERS'), isEmpty, reason: 'arrêter n\'est pas une version datée');
  });

  casM14('m12-echeances : les échéances du versement CNSS portent le marquage, qui tombe dès que la date est arrêtée ; celles de la déclaration unique n\'en portent pas', (t) async {
    final m = magasinLivre();
    await ouvrirM14(t, m, 'm12-echeances');
    final cle = find.byKey(const Key('cpc:nonarretee:CNSS-VERS:2026-01-15'));
    expect(cle, findsOneWidget);
    expect(find.byKey(const Key('cpc:nonarretee:CNSS:2026-01-10')), findsNothing);
    final r = cfbArreterObligation(m.collection('obligationsFiscales').toutes,
        code: 'CNSS-VERS', role: 'direction', decideur: 'Direction', acteur: 'test', maintenant: aujourdhui, aujourdhui: aujourdhui);
    expect(r.ok, isTrue, reason: '${r.refus}');
    m.collection('obligationsFiscales').mettreAJour(r.id, r.fiche!);
    await t.pump(const Duration(milliseconds: 300));
    expect(cle, findsNothing, reason: 'le marquage se lit sur l\'obligation vivante : l\'arrêt le retire sans régénérer');
  });
}
