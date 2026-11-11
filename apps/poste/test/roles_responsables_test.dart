import 'dart:convert';
import 'dart:io';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/service_droits.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// TROIS RÔLES NOUVEAUX (Direction de Baguidi, 10/11/2026) : Responsable Radiologie, Responsable Maternité (sage-femme), Responsable Assurance. L'organisation réelle
/// (collection `postes`) les rattachait à l'échographiste, à l'infirmier et au comptable. Chacun ouvre ce qu'il doit — et seulement cela — et se règle comme tout rôle.
final donnees = DonneesNavigation.depuisDossier();

const roles = ['responsable_radiologie', 'sage_femme', 'responsable_assurance'];

Magasin poste() => Magasin.depuisDossier(['rbac', 'modulesActifs', 'audit', 'rolesBase', 'specialites', 'postes', 'naissances', 'patients', 'factures', 'assureurs', 'couverturesAssurance', 'relances', 'demandesImagerie', 'resultatsImagerie']);

Set<String> visibles(Magasin m, String role) => donnees.aChaud(m).matrice.ecransVisibles(role);

Set<String> modules(Magasin m, Set<String> ecrans) => {for (final e in ecrans) donnees.manifeste.ecran(e)?.module ?? '?'};

Set<String> editables(Magasin m, String role) {
  final mat = donnees.aChaud(m).matrice;
  return {for (final e in mat.ecransVisibles(role)) if (mat.peutEditer(role, e)) e};
}

Fiche ficheRole(Magasin m, String role) => m.collection('rbac').toutes.firstWhere((x) => x['role'] == role);

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('ils existent à froid, dans le jeu livré comme dans la matrice engendrée', () {
    test('le jeu LIVRÉ porte les trois fiches RBAC, les trois rôles de base et les trois postes de l’organisation rattachés à leur rôle', () {
      final livre = Magasin.depuisDossier(['rbac', 'rolesBase', 'postes'], 'assets/donnees/jeu');
      for (final r in roles) {
        expect(livre.collection('rbac').toutes.where((f) => f['role'] == r), hasLength(1), reason: 'une fiche RBAC explicite : un rôle sans fiche aurait tous les droits');
        expect(livre.collection('rbac').toutes.firstWhere((f) => f['role'] == r)['nouveau'], true);
        expect(livre.collection('rolesBase').toutes.where((f) => f['id'] == r), hasLength(1));
        expect(donnees.matrice.roleConnu(r), isTrue, reason: 'la matrice engendrée connaît le rôle');
        expect(donnees.matrice.accueil(r), isNotNull);
        expect(donnees.matrice.peutVoir(r, donnees.matrice.accueil(r)!), isTrue, reason: 'l’accueil d’un rôle est un écran qu’il voit');
      }
      String roleDuPoste(String code) => livre.collection('postes').toutes.firstWhere((p) => p['code'] == code)['role'] as String;
      expect([roleDuPoste('RR'), roleDuPoste('RM'), roleDuPoste('RA')], ['responsable_radiologie', 'sage_femme', 'responsable_assurance']);
      expect(roleDuPoste('RE'), 'echographiste', reason: 'le Responsable Échographie garde l’échographiste');
      expect(roleDuPoste('AR'), 'aide_comptable');
    });

    test('libellés long et court, couleur, accueil : ceux de la décision de la Direction', () {
      final m = poste();
      expect(donnees.matrice.libelle('responsable_radiologie'), 'Responsable Radiologie');
      expect(donnees.matrice.libelle('sage_femme'), 'Responsable Maternité (sage-femme)');
      expect(donnees.matrice.libelle('responsable_assurance'), 'Responsable Assurance');
      expect([for (final r in roles) ficheRole(m, r)['libelleCourt']], ['Resp. Radiologie', 'Resp. Maternité', 'Resp. Assurance']);
      expect([for (final r in roles) donnees.matrice.accueil(r)], ['dash-responsable-radiologie', 'dash-sage-femme', 'dash-responsable-assurance']);
    });

    test('la matrice engendrée et la fiche disent la MÊME chose : la superposition à chaud ne change rien à froid', () {
      final m = poste();
      final vive = donnees.aChaud(m).matrice;
      for (final r in roles) {
        // La graine a été engendrée banque de sang et donneurs FERMÉS ; la Direction les a rouverts (06/11/2026) : c'est le seul écart que la superposition apporte.
        const rouverts = {'m5-banque-sang', 'm5-donneurs'};
        expect(vive.ecransVisibles(r).difference(donnees.matrice.ecransVisibles(r)).difference(rouverts), isEmpty, reason: r);
        expect(donnees.matrice.ecransVisibles(r).difference(vive.ecransVisibles(r)), isEmpty, reason: r);
        for (final e in donnees.matrice.ecransVisibles(r)) {
          expect(vive.droit(r, e), donnees.matrice.droit(r, e), reason: '$r → $e');
        }
      }
    });
  });

  group('inventaire : chaque rôle ouvre ce qu’il doit, et seulement cela', () {
    test('Responsable Radiologie : l’imagerie en écriture, le dossier en lecture, aucun accès financier ni prescription', () {
      final m = poste();
      const r = 'responsable_radiologie';
      final v = visibles(m, r);
      expect(modules(m, v).difference({'AUTH', 'SUP'}), {'M1', 'M2', 'M5', 'M7', 'M13', 'RAP', 'CFG', 'PIL', 'DASH'});
      expect(v, containsAll([
        'dash-responsable-radiologie', 'm2-dashboard-imagerie', 'm2-imagerie-demandes', 'm2-imagerie', 'm2-imagerie-radiographie', 'm2-imagerie-mammographie',
        'm2-imagerie-scanner', 'm2-imagerie-irm', 'm2-echographie-galerie', 'm2-stats-echographie', 'cfg-imagerie-catalogue', 'm1-patients', 'm1-patient-profil'
      ]));
      expect(editables(m, r).where((e) => !e.startsWith('m7-besoins') && e != 'dash-responsable-radiologie' && !e.startsWith('auth') && e != 'index' && !e.startsWith('error') && e != 'plan-du-site' && !{'aide-apropos', 'parametres-hub', 'contact-editeur'}.contains(e)).toSet(),
          {'m2-dashboard-imagerie', 'm2-imagerie-demandes', 'm2-imagerie', 'm2-imagerie-radiographie', 'm2-imagerie-mammographie', 'm2-imagerie-scanner', 'm2-imagerie-irm', 'm2-echographie-galerie', 'm2-imagerie-cr'},
          reason: 'il écrit l’imagerie, et rien d’autre');
      final mat = donnees.aChaud(m).matrice;
      for (final e in ['m2-ordonnances', 'm2-salle-soins', 'm2-pathologies', 'm2-dossiers-consultation', 'm2-consultation-fiche']) {
        expect(mat.peutEditer(r, e), isFalse, reason: 'il exécute, il ne prescrit pas : $e');
      }
      expect(mat.peutVoir(r, 'cfg-imagerie-catalogue') && !mat.peutEditer(r, 'cfg-imagerie-catalogue'), isTrue, reason: 'le catalogue se lit');
      for (final e in v) {
        final mod = donnees.manifeste.ecran(e)!.module;
        expect(['M3', 'M4', 'M6', 'M8', 'M9', 'MECEF', 'M10', 'M11', 'M12', 'GED', 'M14'].contains(mod), isFalse, reason: 'aucun accès financier, RH ni logistique : $e');
      }
    });

    test('Responsable Radiologie = le technicien d’échographie à ses tableaux près : mêmes écrans, mêmes droits (il exécute sans prescrire)', () {
      final m = poste();
      final mat = donnees.aChaud(m).matrice;
      final rr = mat.ecransVisibles('responsable_radiologie').difference({'dash-responsable-radiologie'});
      final ec = mat.ecransVisibles('echographiste').difference({'dash-echographiste'});
      expect(rr, ec);
      for (final e in rr) {
        expect(mat.droit('responsable_radiologie', e), mat.droit('echographiste', e), reason: e);
      }
    });

    test('Responsable Maternité : M4 en écriture, dossiers et consultations en lecture, constantes saisies, résultats de son secteur, ni finance ni imagerie', () {
      final m = poste();
      const r = 'sage_femme';
      final v = visibles(m, r);
      expect(modules(m, v).difference({'AUTH', 'SUP'}), {'M1', 'M2', 'M4', 'M5', 'M7', 'RAP', 'PIL', 'DASH'});
      final mat = donnees.aChaud(m).matrice;
      for (final e in v.where((e) => donnees.manifeste.ecran(e)!.module == 'M4')) {
        expect(mat.peutEditer(r, e), isTrue, reason: 'M4 est son module : $e');
      }
      expect(v.where((e) => donnees.manifeste.ecran(e)!.module == 'M4'), hasLength(15), reason: 'les quinze écrans de la maternité, pages de saisie comprises');
      for (final e in ['m1-patients', 'm1-patient-profil', 'm1-antecedents', 'm2-consultations', 'm2-agenda']) {
        expect(mat.peutVoir(r, e) && !mat.peutEditer(r, e), isTrue, reason: 'lecture seule : $e');
      }
      expect(mat.peutEditer(r, 'm1-constantes'), isTrue, reason: 'elle saisit les constantes');
      expect(v, containsAll(['m5-resultats', 'm5-demandes-maternite', 'm5-resultats-comparatif', 'm4-stats-maternite', 'dash-sage-femme']));
      for (final e in ['m5-demandes', 'm5-catalogue', 'm5-reactifs', 'm5-banque-sang', 'm5-donneurs', 'm2-imagerie', 'm2-imagerie-demandes', 'm1-pieces', 'm1-dossier-etendu']) {
        expect(v.contains(e), isFalse, reason: 'fermé : $e');
      }
      for (final e in v) {
        final mod = donnees.manifeste.ecran(e)!.module;
        expect(['M3', 'M6', 'M8', 'M9', 'MECEF', 'M10', 'M11', 'M12', 'M13', 'GED', 'M14', 'CFG'].contains(mod), isFalse, reason: 'pas de finance, ni administration : $e');
      }
    });

    test('Responsable Assurance : M9 en écriture, la facturation M8 en lecture, le répertoire sans dossier médical, rien en comptabilité ni clinique', () {
      final m = poste();
      const r = 'responsable_assurance';
      final v = visibles(m, r);
      expect(modules(m, v).difference({'AUTH', 'SUP'}), {'M1', 'M7', 'M8', 'M9', 'RAP', 'DASH'});
      final mat = donnees.aChaud(m).matrice;
      for (final e in v.where((e) => donnees.manifeste.ecran(e)!.module == 'M9')) {
        expect(mat.peutEditer(r, e), isTrue, reason: 'M9 est son module : $e');
      }
      expect(v.where((e) => donnees.manifeste.ecran(e)!.module == 'M9'), hasLength(10));
      for (final e in v.where((e) => donnees.manifeste.ecran(e)!.module == 'M8')) {
        expect(mat.peutEditer(r, e), isFalse, reason: 'la facturation se lit seulement : $e');
      }
      expect(v, containsAll(['m8-facturation', 'm8-factures', 'm8-facture-avoir', 'm9-assures', 'm9-conventions', 'm9-relances', 'm9-factures-assureur', 'm1-patients', 'dash-responsable-assurance']));
      for (final e in ['m8-caisse', 'm8-operations', 'm8-recettes', 'm1-dossier-medical', 'm1-antecedents', 'm1-constantes', 'm1-pieces', 'm12-ecritures', 'm12-dashboard', 'm5-resultats', 'm2-consultations']) {
        expect(v.contains(e), isFalse, reason: 'fermé : $e');
      }
      expect(mat.peutEditer(r, 'm1-patients'), isFalse, reason: 'le répertoire se lit, sans dossier médical');
    });

    test('droit d’archiver : chaque rôle suit le rôle existant le plus proche, sans l’élargir (revu par la Direction le 11/11/2026)', () {
      final mat = donnees.aChaud(poste()).matrice;
      final ids = donnees.manifeste.tousLesEcrans.where((e) => !e.hub).toList();
      // Responsable Radiologie = Technicien d'échographie sur tout écran que les deux ouvrent (hors tableau de bord propre à chacun).
      for (final e in ids.where((e) => !e.id.startsWith('dash-'))) {
        expect(mat.peutAnnuler('responsable_radiologie', e.id), mat.peutAnnuler('echographiste', e.id), reason: 'radiologie comme échographiste : ${e.id}');
      }
      // Responsable Maternité : archive en M4 comme l'infirmier (qui y a le droit), nulle part ailleurs que ce que l'infirmier peut.
      for (final e in ids.where((e) => e.module == 'M4')) {
        expect(mat.peutAnnuler('sage_femme', e.id), mat.peutAnnuler('infirmier', e.id), reason: 'sage-femme comme infirmier : ${e.id}');
      }
      expect(ids.any((e) => e.module == 'M4' && mat.peutAnnuler('infirmier', e.id)), isTrue, reason: 'l\'infirmier archive en M4 : l\'alignement n\'est pas une fermeture');
      for (final e in ids.where((e) => mat.peutAnnuler('sage_femme', e.id) && !e.id.startsWith('dash-'))) {
        expect(mat.peutAnnuler('infirmier', e.id), isTrue, reason: 'la sage-femme n\'archive pas où l\'infirmier ne le peut pas : ${e.id}');
      }
      // Responsable Assurance : M9 comme le comptable (modifie, n'archive pas) ; M8 en lecture seule.
      for (final e in ids.where((e) => e.module == 'M9')) {
        expect(mat.peutAnnuler('responsable_assurance', e.id), isFalse, reason: 'M9 : pas d\'archivage, comme le comptable : ${e.id}');
        expect(mat.peutAnnuler('responsable_assurance', e.id), mat.peutAnnuler('comptable', e.id), reason: e.id);
        expect(mat.peutEditer('responsable_assurance', e.id), mat.peutEditer('comptable', e.id), reason: e.id);
      }
      for (final e in ids.where((e) => e.module == 'M8')) {
        expect(mat.peutEditer('responsable_assurance', e.id), isFalse, reason: e.id);
        expect(mat.peutAnnuler('responsable_assurance', e.id), isFalse, reason: e.id);
      }
    });

    test('un tableau de bord par rôle, dans le manifeste, ouvert aux rôles qui lisent tout et fermé à tous les autres', () {
      final m = poste();
      const dash = {'responsable_radiologie': 'dash-responsable-radiologie', 'sage_femme': 'dash-sage-femme', 'responsable_assurance': 'dash-responsable-assurance'};
      final mat = donnees.aChaud(m).matrice;
      for (final e in dash.entries) {
        for (final autre in donnees.matrice.rolesBruts.map((x) => '${x['id']}')) {
          final attendu = autre == e.key || {'admin', 'da', 'direction'}.contains(autre);
          expect(mat.peutVoir(autre, e.value), attendu, reason: '${e.value} sous $autre');
        }
      }
    });
  });

  Future<void> monter(WidgetTester t, Magasin m, {required String role, String? ecran}) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(SighPoste(
        donnees: donnees,
        config: ConfigPoste(mode: ModePoste.fileul, role: role, nomPoste: 'Poste'),
        magasin: m,
        ecranInitial: ecran,
        horloge: () => DateTime(2026, 11, 10, 10)));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  group('ouverture sous le rôle', () {
    testWidgets('chacun ouvre sur SON tableau de bord, qui annonce ce que son profil ne voit pas', (t) async {
      for (final (r, titre) in [
        ('responsable_radiologie', 'Tableau de bord — Responsable Radiologie'),
        ('sage_femme', 'Tableau de bord — Responsable Maternité'),
        ('responsable_assurance', 'Tableau de bord — Responsable Assurance'),
      ]) {
        await monter(t, poste(), role: r);
        expect(find.text(titre), findsWidgets, reason: r);
        expect(find.text('Ce que votre profil ne voit pas'), findsOneWidget, reason: r);
        expect(find.byKey(const Key('tbb:premier-regard')), findsOneWidget, reason: r);
        expect(find.byKey(const Key('ecran-a-porter')), findsNothing);
        await t.pump(const Duration(seconds: 10));
      }
    });

    testWidgets('Responsable Radiologie : « Nouvelle demande » lui est fermée (il exécute, il ne prescrit pas), l’échographiste de même', (t) async {
      await monter(t, poste(), role: 'responsable_radiologie', ecran: 'm2-imagerie-demandes');
      expect(find.text('Demandes d’imagerie médicale'), findsWidgets);
      expect(find.text('Nouvelle demande'), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('Responsable Maternité : elle ÉCRIT au registre des naissances', (t) async {
      await monter(t, poste(), role: 'sage_femme', ecran: 'm4-naissances');
      expect(find.text('Registre des naissances'), findsWidgets);
      expect(find.widgetWithIcon(BoutonSigh, LucideIcons.plus).evaluate().length, greaterThan(0));
      expect(find.textContaining('Lecture seule : le profil'), findsNothing);
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('Responsable Assurance : elle ÉCRIT aux assurés (M9) et LIT la facturation, en le disant par la note de lecture seule qui nomme son profil', (t) async {
      final m = poste();
      await monter(t, m, role: 'responsable_assurance', ecran: 'm9-assures');
      expect(find.textContaining('Lecture seule : le profil'), findsNothing);
      await monter(t, m, role: 'responsable_assurance', ecran: 'm8-factures');
      expect(find.textContaining('Lecture seule : le profil'), findsOneWidget);
      expect(find.textContaining('Responsable Assurance'), findsWidgets, reason: 'la note nomme le profil');
      expect(find.widgetWithIcon(BoutonSigh, LucideIcons.plus).evaluate().length, 0);
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('refus nommé ailleurs : un écran fermé au rôle n’est pas servi, l’accueil du rôle s’ouvre à la place', () {
    for (final (r, accueil, ferme) in [
      ('responsable_radiologie', 'Tableau de bord — Responsable Radiologie', 'm12-ecritures'),
      ('responsable_radiologie', 'Tableau de bord — Responsable Radiologie', 'm2-ordonnances'),
      ('sage_femme', 'Tableau de bord — Responsable Maternité', 'm8-caisse'),
      ('sage_femme', 'Tableau de bord — Responsable Maternité', 'm2-imagerie-demandes'),
      ('responsable_assurance', 'Tableau de bord — Responsable Assurance', 'm12-ecritures'),
      ('responsable_assurance', 'Tableau de bord — Responsable Assurance', 'm1-dossier-medical'),
    ]) {
      testWidgets('$r → $ferme', (t) async {
        final m = poste();
        expect(donnees.aChaud(m).matrice.peutVoir(r, ferme), isFalse);
        await monter(t, m, role: r, ecran: ferme);
        expect(find.text(accueil), findsWidgets);
        await t.pump(const Duration(seconds: 10));
      });
    }
  });

  group('aucune promesse d’écriture sans droit : un écran en lecture seule n’offre aucune commande de création', () {
    for (final (r, ecran) in [
      ('responsable_radiologie', 'm1-patients'),
      ('responsable_radiologie', 'm2-prescriptions'),
      ('responsable_radiologie', 'm5-resultats'),
      ('sage_femme', 'm1-patients'),
      ('sage_femme', 'm2-rendezvous'),
      ('sage_femme', 'm5-resultats'),
      ('responsable_assurance', 'm1-patients'),
      ('responsable_assurance', 'm8-facturation'),
      ('responsable_assurance', 'm8-paiements'),
    ]) {
      testWidgets('$r sur $ecran', (t) async {
        final m = poste();
        final mat = donnees.aChaud(m).matrice;
        expect(mat.peutVoir(r, ecran) && !mat.peutEditer(r, ecran), isTrue, reason: 'le test suppose une lecture seule');
        await monter(t, m, role: r, ecran: ecran);
        expect(find.byKey(const Key('ecran-a-porter')), findsNothing);
        expect(find.widgetWithIcon(BoutonSigh, LucideIcons.plus).evaluate().length, 0, reason: 'aucune commande de création : elle serait une promesse');
        await t.pump(const Duration(seconds: 10));
      });
    }
  });

  group('modifiables à l’écran « Rôles et permissions »', () {
    // L'ordre des lignes de la matrice est celui de l'ÉCRAN : les rôles de base puis ceux des fiches, sans les archivés par la fiche (pas par la graine).
    int rang(Magasin m, String role) => [
          for (final r in secRoles(m.collection('rolesBase').toutes, secSurcharges(m.collection('rbac').toutes)))
            if (!r.archive) r.id
        ].indexOf(role);
    int rangModule(Magasin m, String code) => [for (final r in m.collection('modulesManifeste').toutes) r].indexWhere((r) => r['code'] == code);
    // Le bouton « Revenir au défaut d'origine » n'existe que pour les rôles qui ONT une graine (une fiche du jeu livré) : l'administrateur système, sans fiche, n'en a pas.
    int rangDefaut(Magasin m, String role) => [
          for (final r in secRoles(m.collection('rolesBase').toutes, secSurcharges(m.collection('rbac').toutes)))
            if (!r.archive && ServiceDroits.de(m).graineDuRole(r.id) != null) r.id
        ].indexOf(role);
    Future<void> poser(WidgetTester t, String cle) async {
      final coche = t.getSemantics(find.byKey(Key(cle))).flagsCollection.isChecked == CheckedState.isTrue;
      if (coche) return;
      await t.ensureVisible(find.byKey(Key(cle)));
      await t.pump();
      await t.tap(find.byKey(Key(cle)));
      await t.pump(const Duration(milliseconds: 200));
    }

    for (final (r, module, ecran) in [
      ('responsable_radiologie', 'M8', 'm8-factures'),
      ('sage_femme', 'M9', 'm9-assures'),
      ('responsable_assurance', 'M12', 'm12-ecritures'),
    ]) {
      casM14('$r : un droit se décide avec son motif, s’applique aussitôt ; « revenir au défaut d’origine » le ramène à la graine, historique conservé', (t) async {
        final m = magasinM14();
        final service = ServiceDroits.de(m)..fileulRattache = (() => false);
        await ouvrirM14(t, m, 'm14-roles');
        expect(find.byKey(const Key('m14:diffusion')), findsOneWidget);
        expect(find.textContaining('tous les postes appairés'), findsWidgets, reason: 'la note le dit en toutes lettres');
        expect(find.text(donneesNav.matrice.libelle(r)!), findsWidgets, reason: 'le rôle est à la matrice');
        expect(donneesNav.aChaud(m).matrice.peutVoir(r, ecran), isFalse);
        await toucherM14(t, find.byTooltip('Modifier les droits de ce rôle').at(rang(m, r)));
        await t.pump(const Duration(milliseconds: 400));
        await poser(t, 'case:${rangModule(m, module)}:voir');
        await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer les droits'));
        // Sans motif : refusé, rien n'est écrit.
        await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer les droits').last);
        expect(find.text('Le motif est obligatoire.'), findsOneWidget);
        expect(service.decisions.toutes, isEmpty);
        await motifM14(t, 'Enregistrer les droits', 'Décision de la Direction du 10/11/2026');
        expect(donneesNav.aChaud(m).matrice.peutVoir(r, ecran), isTrue, reason: 'effective aussitôt');
        final d = service.decisions.toutes.single;
        expect([d['role'], d['motif'], d['statutDemande']], [r, 'Décision de la Direction du 10/11/2026', 'appliquee']);
        expect(d['auteur'], isNotEmpty);
        // Le retour au défaut d'origine.
        await t.pump(const Duration(seconds: 6));
        await toucherM14(t, find.byTooltip('Revenir au défaut d’origine').at(rangDefaut(m, r)));
        await motifM14(t, 'Revenir au défaut', 'Retour au réglage d’origine');
        expect(donneesNav.aChaud(m).matrice.peutVoir(r, ecran), isFalse, reason: 'la graine est réappliquée');
        expect(service.decisions.toutes, hasLength(2), reason: 'rien n’est supprimé');
        expect(m.collection('rbac').toutes.firstWhere((x) => x['role'] == r)['version'], 2);
      });
    }

    casM14('un FILEUL rattaché habilité : la décision part à la mère, la fiche de droits locale ne bouge pas, et l’écran le dit', (t) async {
      final m = magasinM14();
      final service = ServiceDroits.de(m)..fileulRattache = (() => true);
      await ouvrirM14(t, m, 'm14-roles');
      expect(find.textContaining('Ce poste est rattaché à la mère'), findsOneWidget);
      await toucherM14(t, find.byTooltip('Modifier les droits de ce rôle').at([for (final r in secRoles(m.collection('rolesBase').toutes, secSurcharges(m.collection('rbac').toutes))) if (!r.archive) r.id].indexOf('sage_femme')));
      await t.pump(const Duration(milliseconds: 400));
      final rm9 = [for (final r in m.collection('modulesManifeste').toutes) r].indexWhere((r) => r['code'] == 'M9');
      await t.ensureVisible(find.byKey(Key('case:$rm9:voir')));
      await t.tap(find.byKey(Key('case:$rm9:voir')));
      await t.pump(const Duration(milliseconds: 200));
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer les droits'));
      await motifM14(t, 'Enregistrer les droits');
      expect(find.text('Décision transmise à la mère.'), findsOneWidget);
      expect(service.decisions.toutes.single['statutDemande'], 'en_attente');
      expect(((m.collection('rbac').toutes.firstWhere((x) => x['role'] == 'sage_femme')['droits'] as Map)['M9'] as Map)['voir'], isFalse);
      expect(donneesNav.aChaud(m).matrice.peutVoir('sage_femme', 'm9-assures'), isFalse, reason: 'rien n’est appliqué ici : la mère décide');
    });
  });
}
