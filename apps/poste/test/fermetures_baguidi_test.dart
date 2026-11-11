import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/shell/acces_rapides.dart';
import 'package:sigh_poste/shell/ecran_hub.dart';
import 'package:sigh_poste/shell/menus_barre.dart';
import 'package:sigh_poste/shell/recherche_globale.dart';

import 'aide_polices.dart';

/// NON-RÉGRESSION DE L'OUVERTURE (Direction, 06/11/2026, nuit). Le jeu livré (`jeu/modulesActifs.json`) ne ferme plus rien : M1 à M10 sont ouverts avec tout, banque de
/// sang et donneurs comprises, et les rôles pharmacien et RH sont rouverts. La matrice engendrée `rbac.json` a été extraite banque de sang et donneurs FERMÉS et
/// pharmacien et RH ARCHIVÉS ; la superposition à chaud compare le jeu à deux RÉFÉRENCES figées (`modulesActifs.reference.json`, `rbac.reference.json`), si bien
/// que ce qui diffère (l'ouverture) devient effectif. Ce banc mesure, pour CHAQUE rôle : aucun « Activité fermée » sur M1 à M10, l'inventaire des écrans est
/// celui de la matrice d'origine ; puis la mécanique (fermer, rouvrir) par la fiche et par cfg-modules.
final donnees = DonneesNavigation.depuisDossier();

/// Les deux écrans que `rbac.json` a extraits fermés et que le jeu rouvre.
const ecransRouverts = ['m5-banque-sang', 'm5-donneurs'];

/// Les deux rôles que `rbac.json` a extraits archivés et que le jeu rouvre.
const rolesRouverts = {'pharmacien', 'rh'};

Magasin jeu() => Magasin.depuisDossier(['rbac', 'modulesActifs', 'modulesManifeste', 'audit', 'patients', 'produits', 'personnel', 'actes', 'assureurs', 'comptes', 'poches', 'donneurs']);

List<String> get roles => [for (final r in donnees.matrice.rolesBruts) '${r['id']}'];

/// La matrice D'ORIGINE : celle que `N.can()` de la maquette calcule du manifeste et des fiches du jeu, sans aucune fermeture (recalcul complet, sans référence).
MatriceDroits origine(Magasin m) => superposerDroits(donnees.matrice, donnees.manifeste, rbac: m.collection('rbac').toutes);

Future<void> monter(WidgetTester t, Magasin m, {String role = 'admin', String? ecran, double hauteur = 1000}) async {
  t.view.physicalSize = Size(1600, hauteur);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role, nomPoste: 'Test'),
      magasin: m,
      ecranInitial: ecran,
      horloge: () => DateTime(2026, 11, 8, 10)));
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(chargerPolices);
  // Les autres bancs lèvent le périmètre livré (`flutter_test_config.dart`) ; celui-ci mesure le poste tel qu'il est livré.
  setUp(() => DonneesNavigation.appliquerPerimetreLivre = true);
  tearDown(() => DonneesNavigation.appliquerPerimetreLivre = false);
  tearDown(ToastsSigh.viderPourTests);

  final manifeste = donnees.manifeste;
  final modulesOuverts = {'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'M8', 'M9', 'M10'};

  group('le jeu livré', () {
    test('ne porte AUCUNE fiche de fermeture ; la référence de l\'extraction garde banque de sang et donneurs ; aucun périmètre livré', () {
      final fiches = Magasin.depuisDossier(['modulesActifs']).collection('modulesActifs').toutes;
      expect(fiches, isEmpty, reason: 'M1 à M10 ouverts avec tout (Direction, 06/11/2026)');
      expect(donnees.referenceModules!.map((f) => f['id']), ['MOD01', 'MOD02'], reason: 'la référence est la configuration de l\'extraction de rbac.json');
      expect(donnees.perimetreLivre, isEmpty);
    });

    test('les fiches RBAC du jeu rouvrent pharmacien et RH ; la référence les garde archivés', () {
      final jeuRbac = jeu().collection('rbac').toutes;
      for (final r in rolesRouverts) {
        expect(jeuRbac.firstWhere((f) => f['role'] == r)['statut'], 'actif', reason: r);
        expect(donnees.referenceRbac!.firstWhere((f) => f['role'] == r)['statut'], 'archive', reason: 'référence : $r');
        expect(donnees.matrice.estArchive(r), isTrue, reason: 'rbac.json (engendré) les a extraits archivés');
      }
      expect({for (final f in jeuRbac) if (f['statut'] == 'archive') f['role']}, isEmpty, reason: 'plus aucun rôle archivé au jeu livré');
    });
  });

  group('pour CHAQUE rôle de rbac.json', () {
    late Magasin m;
    late DonneesNavigation nav;
    setUp(() {
      m = jeu();
      nav = donnees.aChaud(m);
    });

    test('l\'inventaire des écrans visibles est celui de la matrice d\'origine : aucune fermeture sur M1 à M10, aucun rôle archivé', () {
      final o = origine(m);
      expect(roles.length, greaterThanOrEqualTo(16));
      for (final role in roles) {
        expect(nav.matrice.estArchive(role), isFalse, reason: '$role n\'est plus archivé');
        for (final e in manifeste.tousLesEcrans.where((e) => !e.hub)) {
          expect(nav.matrice.droit(role, e.id), o.droit(role, e.id), reason: '$role / ${e.id} : inventaire différent de la matrice d\'origine');
          if (rolesRouverts.contains(role) || ecransRouverts.contains(e.id)) continue;
          expect(nav.matrice.droit(role, e.id), donnees.matrice.droit(role, e.id), reason: '$role / ${e.id} : l\'ouverture ne change aucune autre case');
        }
        for (final e in manifeste.tousLesEcrans.where((e) => modulesOuverts.contains(e.module))) {
          expect(nav.matrice.fermetures?.ecranActif(e.id, e.module) ?? true, isTrue, reason: '$role : ${e.id} porte une fermeture');
        }
      }
      expect(roles.where((r) => nav.matrice.peutVoir(r, 'm10-personnel')), contains('rh'));
      expect(nav.matrice.peutVoir('pharmacien', 'm6-stock-detail') || nav.matrice.peutVoir('pharmacien', 'm6-dashboard'), isTrue);
    });

    test('la banque de sang et les donneurs : un rôle autorisé par la matrice d\'origine les voit au ruban, dans la recherche, et ouvre leur adresse', () {
      final o = origine(m);
      for (final id in ecransRouverts) {
        final e = manifeste.ecran(id)!;
        final autorises = [for (final r in roles) if (o.peutVoir(r, id)) r];
        expect(autorises, containsAll(['laborantin', 'medecin', 'dm', 'admin', 'direction']), reason: id);
        for (final role in roles) {
          final attendu = o.peutVoir(role, id);
          expect(donnees.matrice.peutVoir(role, id), isFalse, reason: 'rbac.json les a extraits fermés : $role / $id');
          expect(nav.matrice.peutVoir(role, id), attendu, reason: '$role / $id');
          expect(ecranOuvertAuRole(nav, role, id), attendu, reason: 'adresse directe : $role / $id');
          final ruban = manifeste.ruban(nav.matrice, role, estMere: true);
          final auRuban = [for (final d in ruban) for (final r in d.rangees) for (final x in r.ecrans) x.id].contains(id);
          expect(auRuban, attendu, reason: 'ruban : $role / $id');
          final trouve = [
            for (final g in rechercheGlobale(requete: e.label, role: role, nav: nav, magasin: m)) for (final r in g.resultats) r.ecran
          ].contains(id);
          expect(trouve, attendu, reason: 'recherche « ${e.label} » : $role / $id');
        }
      }
    });

    test('les pages d\'accueil M1 à M10 et les actions rapides ne mènent à aucune activité fermée', () {
      final o = origine(m);
      expect(ecranOuvertAuRole(nav, 'pharmacien', 'hub-m6'), isTrue, reason: 'pharmacien rouvert : sa page d\'accueil M6');
      expect(ecranOuvertAuRole(nav, 'rh', 'hub-m10'), isTrue, reason: 'RH rouvert : sa page d\'accueil M10');
      for (final role in roles) {
        for (final code in modulesOuverts) {
          final hub = manifeste.ecran('hub-${code.toLowerCase()}');
          if (hub == null) continue;
          final attendu = manifeste.tousLesEcrans.any((e) => !e.hub && e.module == code && o.peutVoir(role, e.id));
          // Une page d'accueil de module ne s'ouvre jamais hors de la matrice d'origine (celle d'un module décidé à chaud n'est pas relue : choix existant).
          if (ecranOuvertAuRole(nav, role, hub.id)) expect(attendu, isTrue, reason: '$role : hub-$code ouvert sans écran visible');
        }
        for (final a in actionsRapidesDuRole(nav, role)) {
          expect(ecranOuvertAuRole(nav, role, a.ecran), isTrue, reason: '$role : action rapide ${a.ecran}');
        }
      }
    });
  });

  testWidgets('ADRESSE DIRECTE : les écrans de M1 à M5 et la banque de sang s\'ouvrent, sans « Activité fermée »', (t) async {
    for (final id in ['m1-patients', 'm3-admissions', 'm5-demandes', 'hub-m2', 'm4-stats-maternite', 'dash-medecin', 'm5-banque-sang', 'm5-donneurs']) {
      await monter(t, jeu(), ecran: id);
      expect(find.byKey(const Key('activite-fermee')), findsNothing, reason: id);
      expect(t.takeException(), isNull, reason: id);
    }
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('RUBAN : l\'administrateur retrouve le domaine Soins avec la banque de sang et les donneurs', (t) async {
    await monter(t, jeu());
    for (final d in ['Accueil', 'Soins', 'Logistique', 'Financier', 'RH', 'Administration', 'Système', 'Pilotage']) {
      expect(find.byKey(Key('domaine-$d')), findsOneWidget, reason: d);
    }
    await t.tap(find.byKey(const Key('domaine-Soins')));
    await t.pump();
    if (find.byKey(const Key('panneau-ruban')).evaluate().isEmpty) {
      await t.tap(find.byKey(const Key('domaine-Soins')));
      await t.pump();
    }
    expect(find.byKey(const Key('pastille-m5-banque-sang')), findsOneWidget);
    expect(find.byKey(const Key('pastille-m5-donneurs')), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('LE MÉCANISME DEMEURE : cfg-modules ferme M1 (motif exigé) puis le rouvre ; fermé, le ruban et l\'adresse le disent, rouvert tout revient, à chaud', (t) async {
    final m = jeu();
    await monter(t, m, ecran: 'cfg-modules', hauteur: 4000);
    expect(find.byTooltip('Fermer le module M1'), findsOneWidget);
    expect(find.byTooltip('Fermer le module M8'), findsOneWidget);
    expect(donnees.aChaud(m).matrice.peutVoir('admin', 'm1-patients'), isTrue);

    final fermer = find.byTooltip('Fermer le module M1');
    await t.ensureVisible(fermer);
    await t.pump();
    await t.tap(fermer);
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(find.byType(TextField).last, 'Essai de la mécanique de fermeture');
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, 'Fermer l’activité').last);
    await t.pump(const Duration(milliseconds: 400));
    final f = m.collection('modulesActifs').toutes.firstWhere((x) => x['module'] == 'M1');
    expect(f['actif'], false);
    expect(donnees.aChaud(m).matrice.peutVoir('admin', 'm1-patients'), isFalse, reason: 'fermé : l\'écran quitte la matrice à chaud');
    expect(donnees.aChaud(m).matrice.peutVoir('admin', 'm2-agenda'), isTrue, reason: 'fermer M1 ne ferme que M1');

    final rouvrir = find.byTooltip('Rouvrir le module M1');
    await t.ensureVisible(rouvrir);
    await t.pump();
    await t.tap(rouvrir);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.widgetWithText(BoutonSigh, 'Rouvrir l’activité').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(m.collection('modulesActifs').toutes.firstWhere((x) => x['module'] == 'M1')['actif'], true, reason: 'rouverte, la fiche reste (RG-14)');
    expect(m.collection('audit').toutes.any((a) => '${a['action']}'.contains('Réouverture')), isTrue, reason: 'RG-12');
    final nav = donnees.aChaud(m);
    expect(nav.matrice.peutVoir('admin', 'm1-patients'), isTrue);
    expect(nav.matrice.droit('admin', 'm1-patients'), donnees.matrice.droit('admin', 'm1-patients'));
    await t.pump(const Duration(seconds: 10));
  });

  test('LE MÉCANISME, au moteur : une fiche fermant la banque de sang la ferme pour tous, la fiche archivée ne ferme plus rien (RG-14)', () {
    final m = jeu();
    final col = m.collection('modulesActifs');
    col.inserer({'id': 'MODT', 'module': 'M5', 'ecrans': ['m5-banque-sang'], 'libelle': 'Banque de sang', 'actif': false});
    var nav = donnees.aChaud(m);
    for (final r in roles) {
      expect(nav.matrice.peutVoir(r, 'm5-banque-sang'), isFalse, reason: r);
    }
    expect(nav.matrice.peutVoir('admin', 'm5-donneurs'), isTrue);
    col.archiver('MODT');
    nav = donnees.aChaud(m);
    expect(nav.matrice.peutVoir('admin', 'm5-banque-sang'), isTrue);
  });
}
