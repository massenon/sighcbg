import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/service_droits.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// LE DROIT D'IMPORT, RÉGLÉ DANS « RÔLES ET PERMISSIONS » (lot IMP-C, Direction du 12/11/2026) : pas un second système. Chaque réglage est une DÉCISION de droits d'écran de la fiche `rbac`
/// (`ServiceDroits.decider`), motivée, journalisée, jugée par la mère, effective à chaud — et le moteur d'import la relit de la matrice en force.
final donnees = DonneesNavigation.depuisDossier();

Magasin jeu() {
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
  m.utilisateur = 'Direction';
  ServiceDroits.de(m).fileulRattache = () => false;
  return m;
}

ProfilImport profilDe(Magasin m, String role) {
  final mat = donnees.aChaud(m).matrice;
  return ProfilImport(role: role, libelleRole: mat.libelle(role) ?? role, droitEcran: (e) => mat.droit(role, e));
}

List<List<Object?>> fichier() => [
      [for (final c in jeuFournisseurs.colonnes) c.label],
      [...ligneExemple(jeuFournisseurs)]..[0] = 'DROITIMP'..[1] = 'FOURNISSEUR DROIT',
    ];

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, String role) async {
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.fileul, role: role), ecranInitial: ecran, magasin: m, horloge: () => DateTime(2026, 11, 12, 10)));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(chargerPolices);

  test('UNE DÉCISION DE DROITS D\'ÉCRAN accorde puis retire l\'import, à chaud, et le moteur la relit de la matrice en force', () {
    final m = jeu();
    // Un rôle qui n'importe pas les fournisseurs dans la matrice d'origine.
    final role = [for (final r in donnees.matrice.rolesBruts) '${r['id']}'].firstWhere((r) => !donnees.matrice.droit(r, jeuFournisseurs.ecran).editer && r != 'admin');
    Map<String, Object?> ecrans(Magasin m) =>
        {...((m.collection('rbac').toutes.where((f) => f['role'] == role).firstOrNull?['droitsEcrans'] as Map?)?.cast<String, Object?>() ?? const {})};
    PortImportMemoire port() => PortImportMemoire({}, profilFixe: profilDe(m, role));
    expect(analyserFichier(jeuFournisseurs, fichier(), 'f.xlsx', port()).refusDroit, isTrue, reason: 'sans le droit : le moteur refuse');
    ServiceDroits.de(m).decider(
        role: role,
        valeurs: {'droitsEcrans': {...ecrans(m), jeuFournisseurs.ecran: {'voir': true, 'editer': true, 'annuler': false}}},
        journal: 'Droit d’import des données',
        motif: 'Décision de la Direction du 12/11/2026',
        auteurRole: 'admin');
    expect(analyserFichier(jeuFournisseurs, fichier(), 'f.xlsx', port()).accepte, isTrue, reason: 'accordé à chaud, sans redémarrage, par la même mécanique que tout droit d\'écran');
    ServiceDroits.de(m).decider(
        role: role,
        valeurs: {'droitsEcrans': {...ecrans(m), jeuFournisseurs.ecran: {'voir': true, 'editer': false, 'annuler': false}}},
        journal: 'Droit d’import des données',
        motif: 'Retrait',
        auteurRole: 'admin');
    expect(analyserFichier(jeuFournisseurs, fichier(), 'f.xlsx', port()).refusDroit, isTrue, reason: 'retiré : de nouveau refusé');
    expect(m.collection(drCollectionDecisions).toutes.length, 2, reason: 'deux décisions au journal des décisions, rien ne se supprime');
  });

  testWidgets('L\'ONGLET « Droit d\'import » de m14-roles : retire puis rend l\'import au geste (motif, journal RG-12, décision de droits), effectif aussitôt', (t) async {
    final m = jeu();
    await ouvrir(t, m, 'm14-roles', 'admin');
    await t.tap(find.text('Droit d’import'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('m14:import:note')), findsOneWidget);
    for (final j in jeuxImport) {
      expect(find.byKey(Key('m14:import:${j.id}')), findsOneWidget, reason: j.id);
    }
    expect(find.byKey(const Key('m14:import:lots')), findsOneWidget);
    final premier = '${donnees.matrice.rolesBruts.first['id']}';
    expect(donnees.aChaud(m).matrice.droit(premier, jeuFournisseurs.ecran).editer, isTrue, reason: 'le premier rôle importe les fournisseurs');
    Future<void> basculer(String cle, String libelle, String motif) async {
      await t.ensureVisible(find.byKey(Key(cle)));
      await t.pump();
      await t.tap(find.byKey(Key(cle)));
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.byType(TextField).last, motif);
      await t.pump();
      await t.tap(find.widgetWithText(BoutonSigh, libelle).last);
      await t.pump(const Duration(milliseconds: 400));
    }

    await basculer('m14:import:basculer:fournisseurs', 'Retirer l’import', 'Plus d’import des fournisseurs');
    final f = m.collection('rbac').actives.firstWhere((x) => x['role'] == premier);
    expect(((f['droitsEcrans'] as Map)[jeuFournisseurs.ecran] as Map)['editer'], false, reason: 'la décision est écrite dans la fiche rbac du rôle');
    expect(donnees.aChaud(m).matrice.droit(premier, jeuFournisseurs.ecran).editer, isFalse, reason: 'effective à chaud');
    expect(find.text('Lecture seule'), findsWidgets);
    final audit = m.collection('audit').toutes.where((a) => a['action'] == 'Droit d’import des données');
    expect(audit, isNotEmpty, reason: 'RG-12 : journalisé');
    expect('${audit.last['apres']}', contains('Plus d’import des fournisseurs'), reason: 'avec son motif');
    final decision = m.collection(drCollectionDecisions).toutes.last;
    expect([decision['role'], decision['auteurRole']], [premier, 'admin'], reason: 'la décision voyage comme toute décision de droits : la mère la juge, les postes la reprennent');
    await basculer('m14:import:basculer:fournisseurs', 'Autoriser l’import', 'Retour de l’import');
    expect(donnees.aChaud(m).matrice.droit(premier, jeuFournisseurs.ecran).editer, isTrue);
    await t.pump(const Duration(seconds: 10));
  });
}
