// LES DROITS DU MOBILE (Direction, 10/11/2026) : l'application évalue la matrice que la mère diffuse, avec le moteur du poste (packages/domaine).
// Le moteur est faux (le lot est en mémoire) mais le SUIVI des droits et les SERVICES sont les vrais : ce que l'écran offre, retire ou ferme vient de la matrice.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_mobile/main.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';
import 'package:sigh_mobile/ui/reglages.dart';

import 'aide_mobile.dart';
import 'aide_suite.dart';

typedef Fiche = Map<String, Object?>;

/// Une décision de la mère sur un rôle : les fiches du jeu livré, plus UNE fiche de surcharge (la plus récente l'emporte, champ par champ).
Fiche surcharge(String role, Map<String, Object?> ecrans, {String id = 'RBACX'}) =>
    {'id': id, 'role': role, 'statut': 'actif', 'droitsEcrans': ecrans, 'definiLe': '2026-11-10'};

void decider(FauxMoteur m, List<Fiche> decisions, {List<Fiche> modules = const [], DateTime? le}) =>
    m.droits.appliquer(rbac: [...m.droits.graine.rbacLivre, ...decisions], modulesActifs: modules, majLe: le ?? DateTime(2026, 11, 10, 14, 5));

Map<String, Object?> sansVoir() => {'voir': false, 'editer': false, 'annuler': false};
Map<String, Object?> lectureSeule() => {'voir': true, 'editer': false, 'annuler': false};

Future<FauxMoteurSuite> ouvrirSoignant(WidgetTester t, {String fonction = 'medecin', SourceMemoire? source}) async {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final m = FauxMoteurSuite(fonction: fonction, agent: 'Agent de test', source: source ?? lotSageFemme())..profil = ProfilMobile.soignant;
  await t.pumpWidget(SighMobile(moteur: m));
  await t.pumpAndSettle();
  return m;
}

Future<void> ouvrirDossierP4(WidgetTester t) async {
  await t.tap(find.byKey(const Key('onglet-dossiers')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('patient-p4')));
  await t.pumpAndSettle();
}

void main() {
  group('le suivi des droits (le même moteur que le poste)', () {
    test('le rôle vient de la FONCTION fixée par la mère ; un téléphone non appairé, ou une fonction inconnue, ne porte aucun droit d\'écran clinique', () {
      final d = SuiviDroits(graineDeTest());
      expect(d.role, isNull);
      expect(d.peutVoir('dossier'), isFalse);
      expect(d.peutVoir('parametres'), isTrue, reason: 'l\'appareil se dit toujours');
      d.definirRole(mobRoleDroits(reception: false, fonction: 'sage_femme'));
      expect(d.role, 'sage_femme');
      expect(d.peutEditer('cpn'), isTrue);
      d.definirRole(mobRoleDroits(reception: false, fonction: 'chauffeur'));
      expect(d.peutVoir('dossier'), isFalse);
    });

    test('une décision qui ne change rien ne réveille pas l\'écran ; la date de réception, elle, avance', () {
      final d = SuiviDroits(graineDeTest(), role: 'medecin');
      var n = 0;
      d.addListener(() => n++);
      d.appliquer(rbac: d.graine.rbacLivre, modulesActifs: const [], majLe: DateTime(2026, 11, 10, 8));
      expect(n, 1, reason: 'première livraison : la matrice est celle de la mère');
      expect(d.value.majLe, DateTime(2026, 11, 10, 8));
      d.appliquer(rbac: d.graine.rbacLivre, modulesActifs: const [], majLe: DateTime(2026, 11, 10, 9));
      expect(d.value.majLe, DateTime(2026, 11, 10, 9));
      expect(n, 2, reason: 'seule la date a bougé');
      d.appliquer(rbac: [...d.graine.rbacLivre, surcharge('medecin', {'m2-ordonnances': lectureSeule()})], modulesActifs: const []);
      expect(d.peutEditer('prescription'), isFalse);
      expect(d.value.majLe, DateTime(2026, 11, 10, 9), reason: 'sans nouvelle date, la dernière est gardée');
    });

    test('le moteur réel du téléphone n\'a PAS d\'autre source que la graine tant que la mère n\'a rien livré : droits d\'origine, pas synchronisés', () async {
      final m = MoteurMobileSync.creer(dbChemin: ':memory:', relais: 'http://127.0.0.1:1', graine: graineDeTest());
      await m.actualiser();
      expect(m.droits.value.synchronises, isFalse);
      expect(m.droits.value.matrice.recue, isFalse);
      // Sans rôle (pas appairé), ouvrir un dossier est refusé NOMMÉ : le droit est refait au geste, pas seulement à l'affichage.
      await expectLater(m.creerPatient({'nom': 'X'}), throwsA(isA<RefusMobile>().having((r) => r.code, 'code', 'DROIT_RETIRE')));
      m.arreter();
    });
  });

  group('services : une commande dont le droit est retiré est refusée, nommée, à chaque geste', () {
    test('le médecin d\'origine prescrit médicaments et analyses ; la lecture seule de l\'ordonnance ne laisse que les analyses ; plus rien : aucune nature', () async {
      final m = FauxMoteur(fonction: 'medecin')..profil = ProfilMobile.soignant;
      final s = m.soignant!;
      expect(s.naturesPrescriptibles, ['medicament', 'analyse']);
      decider(m, [surcharge('medecin', {'m2-ordonnances': lectureSeule()})]);
      expect(s.naturesPrescriptibles, ['analyse']);
      decider(m, [surcharge('medecin', {'m2-ordonnances': lectureSeule(), 'm5-demandes': lectureSeule()})]);
      expect(s.naturesPrescriptibles, isEmpty);
      await expectLater(s.prescrireMedicament('p1', {}), throwsA(isA<RefusMobile>().having((r) => r.code, 'code', 'DROIT_RETIRE')));
      await expectLater(s.prescrireAnalyses('p1', ['NFS'], 'Non urgent'), throwsA(isA<RefusMobile>().having((r) => r.motif, 'motif', contains('Demande d’analyses'))));
    });

    test('constantes, note, dossier et agenda : chaque geste refait le contrôle avec les droits du MOMENT', () async {
      final m = FauxMoteur(fonction: 'medecin')..profil = ProfilMobile.soignant;
      final s = m.soignant!;
      expect(s.peutSaisirConstantes && s.peutSaisirNote && s.peutVoirDossiers && s.peutVoirAgenda, isTrue);
      await s.enregistrerConstantes('p1', {'temperature': '37.5'});
      decider(m, [surcharge('medecin', {'m1-constantes': lectureSeule(), 'm2-consultation-fiche': lectureSeule(), 'm1-patients': sansVoir(), 'm2-agenda': sansVoir()})]);
      expect(s.peutSaisirConstantes, isFalse);
      expect(s.peutSaisirNote, isFalse);
      expect(s.peutVoirDossiers, isFalse);
      expect(s.peutVoirAgenda, isFalse);
      final ecrit = m.source.ecritures.length;
      await expectLater(s.enregistrerConstantes('p1', {'temperature': '37.5'}), throwsA(isA<RefusMobile>().having((r) => r.code, 'code', 'DROIT_RETIRE')));
      await expectLater(s.enregistrerNote('p1', {'motif': 'x'}), throwsA(isA<RefusMobile>().having((r) => r.code, 'code', 'DROIT_RETIRE')));
      await expectLater(s.dossier('p1'), throwsA(isA<RefusMobile>().having((r) => r.motif, 'motif', contains('Dossier du patient'))));
      await expectLater(s.agenda(), throwsA(isA<RefusMobile>()));
      expect(m.source.ecritures.length, ecrit, reason: 'aucun refus n\'a écrit une opération');
    });

    test('la CPN de la sage-femme et l\'orientation de la réception suivent aussi la matrice', () async {
      final sf = FauxMoteurSuite(fonction: 'sage_femme', source: lotSageFemme())..profil = ProfilMobile.soignant;
      final suite = ServiceSuite.depuisSoignant(sf.soignant!);
      expect(suite.peut('cpn') && suite.peut('cpon') && suite.peut('surveillance'), isTrue);
      decider(sf, [surcharge('sage_femme', {'m4-cpn': lectureSeule()})]);
      expect(suite.peut('cpn'), isFalse);
      expect(suite.peut('cpon'), isTrue);
      await expectLater(suite.enregistrerCpn('p4', {'dateVisite': '2026-10-31'}), throwsA(isA<RefusMobile>().having((r) => r.code, 'code', 'DROIT_RETIRE')));

      final rec = FauxMoteurSuite(source: accueilDeSecours())..profil = ProfilMobile.receptionSecours;
      final accueil = ServiceSuite.reception(rec, droits: rec.droits);
      expect(rec.droits.role, 'reception');
      expect(accueil.peut('orientation'), isTrue);
      decider(rec, [surcharge('reception', {'m2-file-attente': lectureSeule()})]);
      expect(accueil.peut('orientation'), isFalse);
      await expectLater(accueil.orienter('d1', destination: mobOrientationDestinations.first, degre: mobOrientationDegres.first), throwsA(isA<RefusMobile>().having((r) => r.code, 'code', 'DROIT_RETIRE')));
    });
  });

  group('écrans : ce que la décision de la mère change à l\'écran, sans redémarrer', () {
    testWidgets('un écran dont le droit de voir est retiré DISPARAÎT de la navigation ; rendu, il revient', (t) async {
      final m = await ouvrirSoignant(t);
      expect(find.byKey(const Key('onglet-agenda')), findsOneWidget);
      expect(find.byKey(const Key('onglet-dossiers')), findsOneWidget);
      decider(m, [surcharge('medecin', {'m1-patients': sansVoir()})]);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('onglet-dossiers')), findsNothing, reason: 'les dossiers du lot ne sont plus ouverts à ce rôle');
      expect(find.byKey(const Key('onglet-agenda')), findsNothing, reason: 'un seul écran reste : plus d\'onglets, l\'agenda seul');
      expect(find.byKey(const Key('agenda-vide')).evaluate().isNotEmpty || find.text('09h30').evaluate().isNotEmpty || find.byKey(const Key('rdv-0')).evaluate().isNotEmpty, isTrue, reason: 'l\'agenda reste affiché');
      decider(m, [surcharge('medecin', {'m1-patients': lectureSeule()}, id: 'RBACY')]);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('onglet-dossiers')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('plus aucun écran ouvert : la page le DIT au lieu de rester muette (aide-soignante : le répertoire n\'est pas à elle dans la matrice)', (t) async {
      final m = await ouvrirSoignant(t, fonction: 'aide_soignant');
      expect(find.byKey(const Key('aucun-ecran')), findsOneWidget);
      expect(find.byKey(const Key('onglet-dossiers')), findsNothing);
      decider(m, [surcharge('aide_soignant', {'m1-patients': lectureSeule()})]);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('aucun-ecran')), findsNothing);
      expect(find.byKey(const Key('patient-p4')).evaluate().isNotEmpty || find.byKey(const Key('rdv-0')).evaluate().isNotEmpty || find.byKey(const Key('agenda-vide')).evaluate().isNotEmpty, isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('une commande d\'écriture dont le droit est retiré est ABSENTE (jamais grisée), l\'écran de lecture reste ouvert', (t) async {
      final m = await ouvrirSoignant(t);
      await ouvrirDossierP4(t);
      expect(find.byKey(const Key('saisir-constantes')), findsOneWidget);
      expect(find.byKey(const Key('nouvelle-note')), findsOneWidget);
      expect(find.byKey(const Key('prescrire')), findsOneWidget);
      decider(m, [surcharge('medecin', {'m1-constantes': lectureSeule(), 'm2-consultation-fiche': lectureSeule(), 'm2-ordonnances': lectureSeule(), 'm5-demandes': lectureSeule()})]);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('saisir-constantes')), findsNothing);
      expect(find.byKey(const Key('nouvelle-note')), findsNothing);
      expect(find.byKey(const Key('prescrire')), findsNothing);
      expect(find.text('SUGBIA Migikpa'), findsWidgets, reason: 'le dossier, lui, reste lisible');
      expect(find.byKey(const Key('droit-retire')), findsNothing, reason: 'rien ne s\'est fermé : seul le droit d\'écrire a changé');
      expect(t.takeException(), isNull);
    });

    testWidgets('un écran OUVERT dont le droit de voir est retiré à chaud se FERME : retour à l\'accueil, le message le dit, aucune exception', (t) async {
      final m = await ouvrirSoignant(t);
      await ouvrirDossierP4(t);
      expect(find.byKey(const Key('saisir-constantes')), findsOneWidget);
      decider(m, [surcharge('medecin', {'m1-patients': sansVoir()})]);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('saisir-constantes')), findsNothing);
      expect(find.text('Ma tournée'), findsOneWidget, reason: 'retour à l\'accueil');
      expect(find.byKey(const Key('droit-retire')), findsOneWidget);
      expect(find.textContaining('Retour à l’accueil'), findsOneWidget);
      expect(find.textContaining('Dossier du patient'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('une SAISIE ouverte dont le droit d\'écrire est retiré se ferme aussi (la note de consultation) ; la session et le lot sont gardés', (t) async {
      final m = await ouvrirSoignant(t);
      await ouvrirDossierP4(t);
      await t.tap(find.byKey(const Key('nouvelle-note')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('enregistrer-note')), findsOneWidget);
      decider(m, [surcharge('medecin', {'m2-consultation-fiche': lectureSeule()})]);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('enregistrer-note')), findsNothing);
      expect(find.text('Ma tournée'), findsOneWidget);
      expect(find.byKey(const Key('droit-retire')), findsOneWidget);
      expect(m.profil, ProfilMobile.soignant, reason: 'la session est gardée');
      expect(t.takeException(), isNull);
    });

    testWidgets('un module fermé par la direction retire ses commandes (la CPN de la sage-femme) ; sa réouverture les rend', (t) async {
      final m = await ouvrirSoignant(t, fonction: 'sage_femme');
      await ouvrirDossierP4(t);
      expect(find.byKey(const Key('ouvrir-cpn')), findsOneWidget);
      final fermeM4 = {'id': 'MOD10', 'code': 'M4', 'module': 'M4', 'actif': false, 'motif': 'Hors périmètre'};
      decider(m, const [], modules: [...m.droits.graine.referenceModules, fermeM4]);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ouvrir-cpn')), findsNothing);
      expect(find.byKey(const Key('ouvrir-cpon')), findsNothing);
      decider(m, const [], modules: [...m.droits.graine.referenceModules, {...fermeM4, 'statut': 'archive'}]);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ouvrir-cpn')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('réception de secours : sans le droit d\'ouvrir un dossier, le formulaire est ABSENT et la page dit pourquoi ; l\'orientation disparaît avec son droit', (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final m = FauxMoteurSuite(source: accueilDeSecours())..profil = ProfilMobile.receptionSecours;
      await t.pumpWidget(SighMobile(moteur: m));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('creer')), findsOneWidget);
      expect(find.byKey(const Key('orienter')), findsOneWidget);
      // La page d'ouverture d'un dossier porte les droits du registre qu'elle alimente (`servant`) : c'est le répertoire des patients qu'on met en lecture.
      decider(m, [surcharge('reception', {'m1-patients': lectureSeule(), 'm2-file-attente': lectureSeule()})]);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('creer')), findsNothing);
      expect(find.byKey(const Key('nom')), findsNothing);
      expect(find.byKey(const Key('creer-ferme')), findsOneWidget);
      expect(find.byKey(const Key('orienter')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('l\'écran des réglages dit l\'état des droits', () {
    testWidgets('avant toute synchronisation : « droits d\'origine, pas encore synchronisés » ; après : la date de mise à jour', (t) async {
      final m = await ouvrirSoignant(t);
      await t.tap(find.byKey(const Key('ouvrir-reglages')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('reglages-droits')), findsOneWidget);
      expect(find.text('Droits d’origine, pas encore synchronisés'), findsOneWidget);
      expect(find.byKey(const Key('reglages-droits-role')), findsOneWidget);
      decider(m, const [], le: DateTime(2026, 11, 10, 14, 5));
      await t.pumpAndSettle();
      expect(find.text('Droits d’origine, pas encore synchronisés'), findsNothing);
      expect(find.text(libelleMiseAJourDroits(m.droits.value)), findsOneWidget);
      expect(libelleMiseAJourDroits(m.droits.value), 'Droits mis à jour le ${dateFR(DateTime(2026, 11, 10, 14, 5))} à ${heure(DateTime(2026, 11, 10, 14, 5))}');
      expect(find.textContaining('mis à jour le'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
