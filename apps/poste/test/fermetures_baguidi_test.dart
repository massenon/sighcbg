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

/// FERMETURE DES MODULES HORS PÉRIMÈTRE (PRD Baguidi, P0-4). La Clinique Baguidi est un centre de médecine du travail : le jeu livré
/// (`jeu/modulesActifs.json`) ferme M1 à M5 en entier, les statistiques cliniques du pilotage et les tableaux de bord des postes cliniques. La matrice
/// engendrée `rbac.json` n'en sait rien (elle a été extraite banque de sang et transfusion seules fermées) : c'est la superposition à chaud, comparée à
/// la configuration de l'extraction (`modulesActifs.reference.json`), qui rend ces fermetures effectives. Vérifié ici pour CHAQUE rôle : ruban, recherche
/// globale, pages d'accueil de module, accès rapides, adresses directes, page d'accueil fermée, écran cfg-modules et réouverture.
final donnees = DonneesNavigation.depuisDossier();

const motifBaguidi = 'Hors périmètre Clinique Baguidi (médecine du travail)';
const modulesFermes = {'M1', 'M2', 'M3', 'M4', 'M5'};
const statsCliniques = {
  'm4-stats-maternite',
  'm2-stats-echographie',
  'm5-stats-examens',
  'm2-stats-consultations',
  'm3-stats-bloc',
  'm3-stats-hospitalisations',
};
const tableauxCliniques = {
  'dash-medecin',
  'dash-infirmier',
  'dash-laborantin',
  'dash-aide-soignant',
  'dash-echographiste',
  'dash-chirurgien',
  'dash-anesthesiste',
  'dash-maternite',
  'dash-patient',
};

Magasin jeu() => Magasin.depuisDossier(['rbac', 'modulesActifs', 'modulesManifeste', 'audit', 'patients', 'produits', 'personnel', 'actes', 'assureurs', 'comptes']);

bool estFerme(EcranNav e) => modulesFermes.contains(e.module) || statsCliniques.contains(e.id) || tableauxCliniques.contains(e.id);

/// Un identifiant qui mène à un écran fermé (un hub d'un module fermé l'est aussi).
bool cibleFermee(Manifeste m, String id) {
  final e = m.ecran(id);
  if (e == null) return false;
  return estFerme(e) || (e.hub && modulesFermes.contains(e.module));
}

List<String> get roles => [for (final r in donnees.matrice.rolesBruts) '${r['id']}'];

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
      horloge: () => DateTime(2026, 11, 6, 10)));
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
  final fermes = [for (final e in manifeste.tousLesEcrans) if (!e.hub && estFerme(e)) e];

  group('le jeu livré', () {
    test('garde les deux fiches de l\'extraction et y ajoute sept fermetures datées, signées et motivées', () {
      final fiches = Magasin.depuisDossier(['modulesActifs']).collection('modulesActifs').actives.toList();
      expect(fiches.map((f) => f['id']), ['MOD01', 'MOD02', 'MOD03', 'MOD04', 'MOD05', 'MOD06', 'MOD07', 'MOD08', 'MOD09']);
      expect(donnees.referenceModules!.map((f) => f['id']), ['MOD01', 'MOD02'], reason: 'la référence est la configuration de l\'extraction de rbac.json');
      expect(donnees.perimetreLivre, {'MOD03', 'MOD04', 'MOD05', 'MOD06', 'MOD07', 'MOD08', 'MOD09'});
      expect(DonneesNavigation.appliquerPerimetreLivre, isTrue, reason: 'au poste, le périmètre livré s\'applique toujours');
      for (final f in fiches.skip(2)) {
        expect(f['actif'], false, reason: '${f['id']}');
        expect(f['motif'], motifBaguidi);
        expect(f['fermeLe'], '2026-11-06');
        expect(f['fermePar'], 'Direction');
      }
      expect({for (final f in fiches.skip(2)) if (f['ecrans'] == null) f['module']}, modulesFermes);
      final nommes = {for (final f in fiches.skip(2)) ...((f['ecrans'] as List?) ?? const []).map((e) => '$e')};
      expect(nommes, {...statsCliniques, ...tableauxCliniques});
      for (final id in nommes) {
        expect(manifeste.ecran(id), isNotNull, reason: 'identifiant inconnu du manifeste : $id');
      }
    });

    test('les statistiques fermées sont TOUTES celles du pilotage qui ne lisent que la clinique ; M8, MECeF et le reste restent ouverts', () {
      final nav = donnees.aChaud(jeu());
      for (final e in manifeste.tousLesEcrans.where((e) => !e.hub && const {'M8', 'MECEF', 'M6', 'M7', 'M9', 'M10', 'M11', 'M12', 'M13', 'M14', 'GED', 'RAP'}.contains(e.module))) {
        expect(nav.matrice.peutVoir('admin', e.id), donnees.matrice.peutVoir('admin', e.id), reason: '${e.id} ne doit pas changer');
      }
      for (final id in ['dash-direction', 'dash-da', 'dash-admin', 'dash-croise', 'm10-cout-agent', 'm12-rentabilite-groupes', 'm12-tableau-decisionnel', 'dash-caissier', 'dash-comptable']) {
        expect(nav.matrice.peutVoir('admin', id) || !donnees.matrice.peutVoir('admin', id), isTrue, reason: '$id reste ouvert');
      }
    });
  });

  group('pour CHAQUE rôle de rbac.json', () {
    late Magasin m;
    late DonneesNavigation nav;
    setUp(() {
      m = jeu();
      nav = donnees.aChaud(m);
    });

    test('aucun écran fermé n\'est visible (matrice), au ruban ni dans les raccourcis permanents', () {
      expect(roles.length, greaterThanOrEqualTo(16));
      for (final role in roles) {
        for (final e in fermes) {
          expect(nav.matrice.peutVoir(role, e.id), isFalse, reason: '$role voit ${e.id}');
        }
        final ruban = manifeste.ruban(nav.matrice, role, estMere: true);
        for (final d in ruban) {
          expect(d.nom, isNot('Soins'), reason: '$role : le domaine Soins disparaît, toutes ses rangées sont fermées');
          for (final r in d.rangees) {
            for (final e in r.ecrans) {
              expect(estFerme(e), isFalse, reason: '$role : pastille ${e.id} au ruban');
            }
          }
        }
        for (final r in manifeste.raccourcis(ruban)) {
          expect(cibleFermee(manifeste, r.hub), isFalse, reason: '$role : raccourci ${r.hub}');
        }
      }
    });

    test('la recherche globale ne propose aucun écran, aucune rubrique, aucun patient d\'un module fermé', () {
      final requetes = <String>{
        for (final e in fermes) e.label,
        for (final r in nav.barre.rubriques)
          if (cibleFermee(manifeste, r.ecran)) r.label,
        for (final p in m.collection('patients').actives.take(5)) '${p['nom']}',
        'patient', 'consultation', 'hospitalisation', 'maternité', 'laboratoire', 'statistiques', 'tableau de bord',
      }..removeWhere((q) => q.trim().length < 2);
      for (final role in roles) {
        for (final q in requetes) {
          for (final g in rechercheGlobale(requete: q, role: role, nav: nav, magasin: m)) {
            for (final r in g.resultats) {
              expect(cibleFermee(manifeste, r.ecran), isFalse, reason: '$role, « $q » : ${g.groupe} → ${r.ecran}');
            }
          }
        }
      }
    });

    test('les pages d\'accueil de module des modules fermés sont fermées, et aucun hub ne montre de carte fermée', () {
      for (final role in roles) {
        for (final code in modulesFermes) {
          expect(ecranOuvertAuRole(nav, role, 'hub-${code.toLowerCase()}'), isFalse, reason: '$role : hub-$code');
        }
        for (final hub in hubsDuManifeste) {
          final entree = manifeste.ecran(hub);
          if (entree == null) continue;
          final mod = ModuleHub.depuis(manifeste, entree.module);
          if (mod == null) continue;
          for (final c in cartesDuHub(mod, nav, (id) => nav.matrice.peutVoir(role, id))) {
            expect(cibleFermee(manifeste, c.id), isFalse, reason: '$role : carte ${c.id} du hub $hub');
          }
        }
      }
    });

    test('ni les actions rapides de la barre, ni les accès rapides en tête de page ne mènent à un écran fermé', () {
      for (final role in roles) {
        for (final a in actionsRapidesDuRole(nav, role)) {
          expect(cibleFermee(manifeste, a.ecran), isFalse, reason: '$role : action rapide ${a.ecran}');
        }
        final ruban = manifeste.ruban(nav.matrice, role, estMere: true);
        for (final d in ruban) {
          for (final r in d.rangees) {
            for (final e in r.ecrans) {
              final cibles = <String>[];
              for (final b in accesRapides(ecran: e, ruban: ruban, declarees: const [], aller: cibles.add).whereType<BoutonSigh>()) {
                b.onPressed?.call();
              }
              for (final c in cibles) {
                expect(cibleFermee(manifeste, c), isFalse, reason: '$role, sur ${e.id} : accès rapide $c');
              }
            }
          }
        }
      }
    });

    test('les écrans ouverts gardent EXACTEMENT les droits de la matrice engendrée', () {
      for (final role in roles) {
        for (final e in manifeste.tousLesEcrans.where((e) => !e.hub && !estFerme(e))) {
          expect(nav.matrice.droit(role, e.id), donnees.matrice.droit(role, e.id), reason: '$role / ${e.id}');
        }
      }
    });
  });

  testWidgets('ADRESSE DIRECTE : un écran fermé (module entier, statistique, tableau de bord, hub) mène à « Activité fermée » avec le motif, administrateur compris', (t) async {
    for (final id in ['m1-patients', 'm3-admissions', 'm5-demandes', 'hub-m2', 'm4-stats-maternite', 'dash-medecin']) {
      await monter(t, jeu(), ecran: id);
      expect(find.byKey(const Key('activite-fermee')), findsOneWidget, reason: id);
      expect(find.textContaining(motifBaguidi), findsWidgets, reason: id);
      expect(t.takeException(), isNull, reason: id);
    }
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('RUBAN : l\'administrateur n\'a plus de domaine Soins ; Financier (caisse), Logistique et Pilotage demeurent', (t) async {
    await monter(t, jeu());
    expect(find.byKey(const Key('domaine-Soins')), findsNothing);
    for (final d in ['Accueil', 'Logistique', 'Financier', 'RH', 'Administration', 'Système', 'Pilotage']) {
      expect(find.byKey(Key('domaine-$d')), findsOneWidget, reason: d);
    }
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('PAGE D\'ACCUEIL FERMÉE : chaque rôle dont l\'accueil est fermé retombe sur le premier écran de son ruban, sans écran vide ni exception', (t) async {
    final nav = donnees.aChaud(jeu());
    final concernes = [
      for (final role in roles)
        if (!nav.matrice.estArchive(role) && nav.matrice.accueil(role) != null && !nav.matrice.peutVoir(role, nav.matrice.accueil(role)!)) role
    ];
    expect(concernes, containsAll(['medecin', 'infirmier', 'laborantin']));
    for (final role in concernes) {
      await monter(t, jeu(), role: role);
      expect(t.takeException(), isNull, reason: role);
      expect(find.byKey(const Key('activite-fermee')), findsNothing, reason: '$role : l\'accueil de repli n\'est pas une activité fermée');
      final ruban = manifeste.ruban(nav.matrice, role, estMere: false);
      if (ruban.isEmpty) {
        expect(find.text('Aucun module n’est ouvert à votre profil.'), findsOneWidget, reason: role);
      } else {
        expect(find.byKey(const Key('titre-page')), findsOneWidget, reason: '$role : une page est servie');
      }
    }
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('cfg-modules AFFICHE les fermetures Baguidi ; rouvrir M1 d\'une bascule rend ses écrans au ruban, à chaud', (t) async {
    final m = jeu();
    await monter(t, m, ecran: 'cfg-modules', hauteur: 4000);
    expect(find.text(motifBaguidi), findsWidgets);
    expect(find.text('Patients & Dossier médical'), findsWidgets);
    expect(find.text('Statistiques cliniques'), findsWidgets);
    expect(find.text('Tableaux de bord des postes cliniques'), findsWidgets);
    expect(find.text('06/11/2026'), findsWidgets);
    expect(find.byTooltip('Rouvrir le module M1'), findsOneWidget);
    expect(find.byTooltip('Fermer le module M8'), findsOneWidget, reason: 'la caisse reste ouverte');
    expect(donnees.aChaud(m).matrice.peutVoir('admin', 'm1-patients'), isFalse);

    final bascule = find.byTooltip('Rouvrir le module M1');
    await t.ensureVisible(bascule);
    await t.pump();
    await t.tap(bascule);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.widgetWithText(BoutonSigh, 'Rouvrir l’activité').last);
    await t.pump(const Duration(milliseconds: 400));

    final f = m.collection('modulesActifs').toutes.firstWhere((x) => x['id'] == 'MOD03');
    expect(f['actif'], true, reason: 'rouverte, la fiche reste (RG-14)');
    expect(m.collection('audit').toutes.any((a) => '${a['action']}'.contains('Réouverture')), isTrue, reason: 'RG-12');
    final nav = donnees.aChaud(m);
    expect(nav.matrice.peutVoir('admin', 'm1-patients'), isTrue);
    expect(nav.matrice.droit('admin', 'm1-patients'), donnees.matrice.droit('admin', 'm1-patients'));
    expect(nav.matrice.peutVoir('admin', 'm2-agenda'), isFalse, reason: 'M2 reste fermé');
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('domaine-Soins')), findsOneWidget, reason: 'la coque écoute modulesActifs : le domaine revient sans redémarrage');
    await t.pump(const Duration(seconds: 10));
  });
}
