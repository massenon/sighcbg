import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/service_droits.dart';
import 'package:sigh_poste/impression/piece.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/m1/externe.dart';
import 'package:sigh_poste/modules/m1/fiche_impression.dart';
import 'package:sigh_poste/modules/m1/pieces.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';
import 'package:sigh_poste/shell/recherche_globale.dart';

import 'aide_polices.dart';

/// LES DONNÉES SENSIBLES DU PATIENT (Direction, 11/11/2026) : un droit par catégorie, porté par la matrice, jamais un nom de rôle. Ici : l'ÉCRAN (fiche patient),
/// le PAPIER (dossier imprimé), la RECHERCHE globale, et le droit accordé À CHAUD sans rien rouvrir. Les rôles nommés ici sont ceux du TEST ; le code testé n'en
/// connaît aucun — il lit la matrice.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 11, 11, 10);

const tel = '97123456';
const quartier = 'ZONGO-XYZ';
const groupe = 'AB-';

Magasin jeu() {
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
  final p = trierPar([...m.collection('patients').actives], (x) => x['code']).first;
  m.collection('patients').mettreAJour(p['id'], {
    'telephone': tel,
    'quartier': quartier,
    'groupeSanguin': groupe,
    'antecedents': ['Hypertension artérielle'],
    'allergies': [],
  });
  m.utilisateur = 'Direction';
  ServiceDroits.de(m).fileulRattache = () => false;
  return m;
}

Fiche patientDe(Magasin m) => trierPar([...m.collection('patients').actives], (x) => x['code']).first;

void decider(Magasin m, String role, Map<String, bool?> cats) => ServiceDroits.de(m).decider(
    role: role, valeurs: {'donneesSensibles': cats}, journal: 'Droit sur les données sensibles', motif: 'Décision de la Direction', auteurRole: 'admin');

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, String role) async {
  t.view.physicalSize = const Size(1600, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: ecran,
      magasin: m,
      horloge: () => aujourdhui));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

String reserve(String code) => mentionReservee(code);

/// Le texte de toutes les pièces d'un état imprimé.
String texteDesBlocs(List<BlocPiece> blocs) {
  final b = StringBuffer();
  for (final x in blocs) {
    if (x is BlocTableau) {
      for (final l in x.tableau.lignes) {
        for (final c in x.tableau.colonnes) {
          b.writeln('${c.valeur(l)}');
        }
      }
    }
  }
  return b.toString();
}

void main() {
  setUpAll(chargerPolices);

  // Le défaut de la livraison : la Zone 1 (répertoire) se lit avec l'écran du répertoire, la Zone 2 avec celui du dossier de consultation.
  test('LIVRAISON : ce que chaque profil perd par défaut est exactement l’écart entre le répertoire et la consultation (relevé)', () {
    final m = jeu();
    final nav = donnees.aChaud(m);
    final d = DroitsSensibles(fiches: m.collection('rbac').actives, peutVoirEcran: nav.matrice.peutVoir);
    final roles = [for (final r in nav.matrice.rolesBruts) '${r['id']}'];
    var voitRepertoire = 0, perdentLaClinique = 0;
    for (final r in roles) {
      if (!nav.matrice.peutVoir(r, 'm1-patients')) continue;
      voitRepertoire++;
      // Cohérence : qui n'a pas le dossier de consultation perd les catégories de la Zone 2, qui l'a les garde.
      expect(d.peut(r, 'antecedents'), nav.matrice.peutVoir(r, 'm2-dossiers-consultation'), reason: r);
      expect(d.peut(r, 'coordonnees'), isTrue, reason: '$r garde la Zone 1');
      if (!d.peut(r, 'diagnostic_pathologie')) perdentLaClinique++;
    }
    expect(voitRepertoire, greaterThan(10));
    expect(perdentLaClinique, greaterThan(0), reason: 'des profils qui lisaient la clinique sans en avoir le droit : à dire à la Direction');
    // Ce relevé est imprimé pour le rapport : `flutter test --plain-name RELEVÉ` n'écrit rien, l'assertion suffit.
    stdout.writeln('RELEVÉ — $voitRepertoire profils ouvrent le répertoire ; $perdentLaClinique n’ont pas le dossier de consultation et perdent la Zone 2.');
  });

  testWidgets('FICHE : sans droit sur la catégorie le champ DIT « Information réservée » ; avec le droit il est lu', (t) async {
    final m = jeu();
    // Un profil qui lit le répertoire sans le dossier de consultation (Zone 1 seulement) et un qui a les deux.
    final nav = donnees.aChaud(m);
    final roles = [for (final r in nav.matrice.rolesBruts) '${r['id']}'];
    final zone1 = roles.firstWhere((r) => nav.matrice.peutVoir(r, 'm1-patient-profil') && !nav.matrice.peutVoir(r, 'm2-dossiers-consultation'));
    final zone2 = roles.firstWhere((r) => nav.matrice.peutVoir(r, 'm1-patient-profil') && nav.matrice.peutVoir(r, 'm2-dossiers-consultation'));

    await ouvrir(t, m, 'm1-patient-profil', zone1);
    expect(find.text(tel), findsOneWidget, reason: 'la Zone 1 se lit');
    expect(find.text(groupe), findsNothing);
    expect(find.textContaining(groupe), findsNothing, reason: 'le groupe sanguin n’est pas non plus dans le bandeau d’identité');
    expect(find.text(reserve('groupe_serologies')), findsOneWidget, reason: 'le champ le dit, il n’apparaît pas vide');
    // Les rubriques de la Zone 2 le disent aussi, sans compte.
    await t.tap(find.byKey(const Key('m1:rubrique:antecedents')));
    await t.pump();
    expect(find.byKey(const Key('sensible:antecedents')), findsOneWidget);
    expect(find.textContaining('Hypertension'), findsNothing);
    await t.tap(find.byKey(const Key('m1:rubrique:medical')));
    await t.pump();
    expect(find.byKey(const Key('sensible:notes_consultation')), findsWidgets);

    await ouvrir(t, m, 'm1-patient-profil', zone2);
    expect(find.text(groupe), findsWidgets);
    expect(find.byKey(const Key('sensible:groupe_serologies')), findsNothing);
    await t.tap(find.byKey(const Key('m1:rubrique:antecedents')));
    await t.pump();
    expect(find.textContaining('Hypertension'), findsOneWidget);
  });

  testWidgets('À CHAUD : un droit accordé ou retiré s’applique sans rien rouvrir, sur la fiche déjà affichée', (t) async {
    final m = jeu();
    final nav = donnees.aChaud(m);
    final role = [for (final r in nav.matrice.rolesBruts) '${r['id']}'].firstWhere((r) => nav.matrice.peutVoir(r, 'm1-patient-profil') && !nav.matrice.peutVoir(r, 'm2-dossiers-consultation'));
    await ouvrir(t, m, 'm1-patient-profil', role);
    expect(find.text(groupe), findsNothing);
    expect(find.text(tel), findsOneWidget);

    decider(m, role, {'groupe_serologies': true});
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text(groupe), findsWidgets, reason: 'accordé à chaud');

    decider(m, role, {'coordonnees': false});
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text(tel), findsNothing, reason: 'retiré à chaud — même ce que le défaut donnait');
    expect(find.text(reserve('coordonnees')), findsWidgets);

    decider(m, role, {'coordonnees': null, 'groupe_serologies': null});
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text(tel), findsOneWidget, reason: 'retour au défaut de la matrice');
    expect(find.text(groupe), findsNothing);
  });

  testWidgets('RÉPERTOIRE : la colonne masquée porte la mention, ne se lit pas, et la recherche du tableau ne retrouve pas la valeur', (t) async {
    final m = jeu();
    final nav = donnees.aChaud(m);
    final role = [for (final r in nav.matrice.rolesBruts) '${r['id']}'].firstWhere((r) => nav.matrice.peutVoir(r, 'm1-patients'));
    decider(m, role, {'coordonnees': false});
    await ouvrir(t, m, 'm1-patients', role);
    expect(find.text(tel), findsNothing);
    expect(find.text(quartier), findsNothing);
    expect(find.byKey(const Key('sensible:coordonnees')), findsWidgets);
    final nomComplet = '${patientDe(m)['nom']} ${patientDe(m)['prenom']}';
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, '${patientDe(m)['nom']}');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(nomComplet), findsWidgets, reason: 'sentinelle : le patient se retrouve par son nom, donc l’absence plus bas est une mesure');
    // La recherche du tableau lit le texte des colonnes : le numéro masqué ne retrouve aucune ligne.
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, tel);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('${patientDe(m)['nom']} ${patientDe(m)['prenom']}'), findsNothing, reason: 'on ne retrouve pas un patient par une valeur qu’on n’a pas le droit de lire');
  });

  test('IMPRESSION : le dossier imprimé masque les mêmes catégories que l’écran, et reprend la valeur quand le droit est accordé', () {
    final m = jeu();
    final nav = donnees.aChaud(m);
    final roles = [for (final r in nav.matrice.rolesBruts) '${r['id']}'];
    final zone1 = roles.firstWhere((r) => nav.matrice.peutVoir(r, 'm1-patients') && !nav.matrice.peutVoir(r, 'm2-dossiers-consultation'));
    String papier(String role) {
      late String s;
      final ctx = ContexteEcran(
          ecranId: 'm1-patients',
          role: role,
          droit: const Droit(voir: true, editer: false, annuler: false),
          magasin: m,
          donnees: donnees.aChaud(m),
          aller: (_) {},
          child: const SizedBox());
      s = texteDesBlocs(blocsDossierComplet(ctx, patientDe(m)));
      return s;
    }

    var s = papier(zone1);
    expect(s, contains(tel), reason: 'la Zone 1 s’imprime');
    expect(s, isNot(contains(groupe)));
    expect(s, isNot(contains('Hypertension')));
    expect(s, contains(reserve('groupe_serologies')));
    expect(s, contains(reserve('antecedents')));
    decider(m, zone1, {'antecedents': true, 'coordonnees': false});
    s = papier(zone1);
    expect(s, contains('Hypertension'), reason: 'droit accordé : le papier le reprend');
    expect(s, isNot(contains(tel)));
    expect(s, isNot(contains(quartier)));
  });

  test('RECHERCHE GLOBALE : le détail d’un patient ne donne pas le quartier sans le droit, et aucune valeur masquée n’est indexée', () {
    final m = jeu();
    final nav = donnees.aChaud(m);
    final role = [for (final r in nav.matrice.rolesBruts) '${r['id']}'].firstWhere((r) => nav.matrice.peutVoir(r, 'm1-patients'));
    final nom = patientDe(m)['nom'] as String;
    String detail() => [
          for (final g in rechercheGlobale(requete: nom, role: role, nav: donnees.aChaud(m), magasin: m))
            for (final r in g.resultats) '${r.label} ${r.detail}'
        ].join('\n');
    expect(detail(), contains(quartier));
    decider(m, role, {'coordonnees': false});
    expect(detail(), isNot(contains(quartier)));
    expect(detail(), contains(nom), reason: 'le patient reste trouvable par son identification minimale');
    // On ne retrouve jamais un patient par une valeur sensible (téléphone, antécédent, groupe) : ces champs ne sont pas indexés.
    for (final valeur in [tel, 'Hypertension', groupe]) {
      final g = rechercheGlobale(requete: valeur, role: role, nav: donnees.aChaud(m), magasin: m);
      expect([for (final x in g) if (x.groupe == 'Patients') x], isEmpty, reason: valeur);
    }
  });

  testWidgets('ADMINISTRATION : l’onglet « Données sensibles » de m14-roles décide, motive, journalise, et la décision est effective aussitôt', (t) async {
    final m = jeu();
    final nav = donnees.aChaud(m);
    final cible = [for (final r in nav.matrice.rolesBruts) '${r['id']}'].firstWhere((r) => nav.matrice.peutVoir(r, 'm1-patients') && !nav.matrice.peutVoir(r, 'm2-dossiers-consultation'));
    await ouvrir(t, m, 'm14-roles', 'admin');
    await t.tap(find.text('Données sensibles'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('m14:sensibles:note')), findsOneWidget);
    for (final c in categoriesSensibles) {
      expect(find.byKey(Key('m14:sensibles:${c.code}')), findsOneWidget, reason: c.code);
    }
    // Le rôle affiché est le premier actif : on décide AU GESTE, par l'écran (modale de motif), comme l'administrateur.
    final premier = [for (final r in nav.matrice.rolesBruts) '${r['id']}'].first;
    final avant = DroitsSensibles(fiches: m.collection('rbac').actives, peutVoirEcran: nav.matrice.peutVoir);
    final actuel = avant.peut(premier, 'antecedents');
    expect(avant.origine(premier, 'antecedents'), 'defaut');
    await t.ensureVisible(find.byKey(const Key('m14:sensibles:basculer:antecedents')));
    await t.pump();
    await t.tap(find.byKey(const Key('m14:sensibles:basculer:antecedents')));
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(find.byType(TextField).last, 'Décision de la Direction du 11/11/2026');
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, actuel ? 'Masquer' : 'Autoriser').last);
    await t.pump(const Duration(milliseconds: 400));
    final f = m.collection('rbac').actives.firstWhere((x) => x['role'] == premier);
    expect((f['donneesSensibles'] as Map)['antecedents'], !actuel, reason: 'la décision est écrite dans la fiche rbac du rôle');
    expect(find.byKey(const Key('m14:sensibles:defaut:antecedents')), findsOneWidget, reason: 'une décision se défait : « Revenir au défaut »');
    final audit = m.collection('audit').toutes.where((a) => a['action'] == 'Droit sur les données sensibles du patient');
    expect(audit, isNotEmpty, reason: 'RG-12 : la décision est journalisée');
    expect('${audit.last['apres']}', contains(actuel ? 'masqué' : 'visible'));
    expect('${audit.last['apres']}', contains('Décision de la Direction'), reason: 'avec son motif');
    final decision = m.collection(drCollectionDecisions).toutes.last;
    expect([decision['role'], decision['auteurRole']], [premier, 'admin'], reason: 'la décision voyage comme toute décision de droits (diffusée aux postes)');
    // Retour au défaut, au geste.
    await t.ensureVisible(find.byKey(const Key('m14:sensibles:defaut:antecedents')));
    await t.pump();
    await t.tap(find.byKey(const Key('m14:sensibles:defaut:antecedents')));
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(find.byType(TextField).last, 'Retour au défaut');
    await t.pump();
    await t.tap(find.widgetWithText(BoutonSigh, 'Revenir au défaut').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('m14:sensibles:defaut:antecedents')), findsNothing);
    expect(cible, isNotEmpty);
    await t.pump(const Duration(seconds: 10));
  });

  // ------------------------------------------------------------------------------------------------------------------------------------------
  // LOT 2 : patient externe, pièces certifiantes, hospitalisation, KPI du répertoire.

  const ecransHospitalisation = [
    'm3-admissions', 'm3-plan-lits', 'm3-feuille-temperature', 'm3-observation', 'm3-soins', 'm3-surveillance', 'm3-administrations', 'm3-glasgow',
    'm3-transfusion', 'm3-rapport', 'm3-visites-patients', 'm3-sorties', 'm3-sortie-avis-medical',
  ];

  ContexteEcran contexte(Magasin m, String role, String ecran) => ContexteEcran(
      ecranId: ecran,
      role: role,
      droit: const Droit(voir: true, editer: true, annuler: false),
      magasin: m,
      donnees: donnees.aChaud(m),
      aller: (_) {},
      child: const SizedBox());

  test('LIVRAISON 2 : les profils dont la vue change à la livraison (relevé non nominatif), et ceux qui ouvrent les écrans de référence ne perdent rien', () {
    final m = jeu();
    final nav = donnees.aChaud(m);
    final d = DroitsSensibles(fiches: m.collection('rbac').actives, peutVoirEcran: nav.matrice.peutVoir);
    final roles = [for (final r in nav.matrice.rolesBruts) '${r['id']}'];
    final touches = <String>{};
    for (final r in roles) {
      for (final e in ecransHospitalisation) {
        if (nav.matrice.peutVoir(r, e) && !d.peut(r, 'hospitalisation_soins')) touches.add(r);
      }
      if (nav.matrice.peutVoir(r, 'm1-pieces') && !d.peut(r, 'notes_consultation')) touches.add(r);
      if (nav.matrice.peutVoir(r, 'm1-pieces') && !d.peut(r, 'couverture_assurance')) touches.add(r);
      if (nav.matrice.peutVoir(r, 'm1-externe') && !d.peut(r, 'resultats_analyses')) touches.add(r);
      if (nav.matrice.peutVoir(r, 'm1-externe') && !d.peut(r, 'coordonnees')) touches.add(r);
      if (nav.matrice.peutVoir(r, 'm1-patients') && !d.peut(r, 'couverture_assurance')) touches.add(r);
      // Référence : qui ouvre l'écran dont la catégorie dépend la garde.
      if (nav.matrice.peutVoir(r, 'm3-admissions')) expect(d.peut(r, 'hospitalisation_soins'), isTrue, reason: r);
    }
    final lisent = roles.where((r) => ecransHospitalisation.any((e) => nav.matrice.peutVoir(r, e))).length;
    stdout.writeln('RELEVÉ 2 — ${touches.length} profil(s) sur ${roles.length} voient une vue changer à la livraison ; $lisent ouvrent au moins un écran d’hospitalisation.');
    // Hospitalisation : ne perdent que ceux qui ouvrent un écran M3 sans ouvrir les admissions.
    for (final r in roles) {
      final ouvreM3 = ecransHospitalisation.any((e) => nav.matrice.peutVoir(r, e));
      if (ouvreM3 && !nav.matrice.peutVoir(r, 'm3-admissions')) continue;
      if (ouvreM3) expect(d.peut(r, 'hospitalisation_soins'), isTrue, reason: '$r garde l’hospitalisation');
    }
  });

  testWidgets('KPI DU RÉPERTOIRE : assurés et cartes expirées disparaissent sans « couverture d’assurance », reviennent à chaud', (t) async {
    final m = jeu();
    final nav = donnees.aChaud(m);
    final role = [for (final r in nav.matrice.rolesBruts) '${r['id']}'].firstWhere((r) => nav.matrice.peutVoir(r, 'm1-patients'));
    await ouvrir(t, m, 'm1-patients', role);
    expect(find.text('Patients assurés'), findsOneWidget, reason: 'sentinelle : le KPI existe par défaut');
    expect(find.text('Cartes expirées'), findsOneWidget);
    decider(m, role, {'couverture_assurance': false});
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Patients assurés'), findsNothing);
    expect(find.text('Cartes expirées'), findsNothing);
    expect(find.text('Dossiers actifs'), findsOneWidget, reason: 'les indicateurs sans donnée sensible restent');
    decider(m, role, {'couverture_assurance': null});
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Patients assurés'), findsOneWidget, reason: 'droit rendu à chaud (retour au défaut de la matrice)');
  });

  testWidgets('HOSPITALISATION : chaque écran dit « Information réservée » sans le droit, et s’ouvre à chaud quand il est accordé', (t) async {
    final m = jeu();
    final nav = donnees.aChaud(m);
    final roles = [for (final r in nav.matrice.rolesBruts) '${r['id']}'];
    var ouverts = 0;
    for (final e in ecransHospitalisation) {
      final role = roles.where((r) => r != 'admin' && nav.matrice.peutVoir(r, e) && nav.matrice.peutVoir(r, 'm3-admissions')).firstOrNull;
      if (role == null) continue;
      ouverts++;
      await ouvrir(t, m, e, role);
      decider(m, role, {'hospitalisation_soins': false});
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('garde-sensible:hospitalisation_soins')), findsOneWidget, reason: '$e refuse sans le droit');
      decider(m, role, {'hospitalisation_soins': null});
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('garde-sensible:hospitalisation_soins')), findsNothing, reason: '$e s’ouvre à chaud');
    }
    expect(ouverts, greaterThan(8));
  });

  testWidgets('ADMISSIONS : le diagnostic d’entrée suit « diagnostic et pathologie », colonne masquée, non triable, non retrouvée par la recherche', (t) async {
    final m = jeu();
    for (final a in m.collection('admissions').actives) {
      m.collection('admissions').mettreAJour(a['id'], {'diagnosticEntree': 'DIAG-XYZ'});
    }
    final nav = donnees.aChaud(m);
    final role = [for (final r in nav.matrice.rolesBruts) '${r['id']}'].firstWhere((r) => r != 'admin' && nav.matrice.peutVoir(r, 'm3-admissions'));
    await ouvrir(t, m, 'm3-admissions', role);
    expect(find.text('DIAG-XYZ'), findsWidgets, reason: 'sentinelle : lu par défaut');
    decider(m, role, {'diagnostic_pathologie': false});
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('DIAG-XYZ'), findsNothing);
    expect(find.byKey(const Key('garde-sensible:hospitalisation_soins')), findsNothing, reason: 'l’écran reste ouvert : seule la colonne se masque');
    expect(find.text(reserve('diagnostic_pathologie')), findsWidgets);
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, 'DIAG-XYZ');
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(reserve('diagnostic_pathologie')), findsNothing, reason: 'la recherche du tableau ne retrouve aucune ligne par une valeur masquée');
  });

  test('IMPRESSION 2 : le bulletin du patient externe et la pièce certifiante masquent l’âge, les coordonnées, les mentions et la couverture sans le droit', () {
    final m = jeu();
    final nav = donnees.aChaud(m);
    final role = [for (final r in nav.matrice.rolesBruts) '${r['id']}'].firstWhere((r) => nav.matrice.peutVoir(r, 'm1-externe'));
    final p = {...patientDe(m), 'age': 41, 'dateNaissance': null, 'telephone': tel, 'adresse': 'RUE-SECRETE', 'prescripteurExterieur': 'Dr X'};
    String bulletin() {
      final c = contexte(m, role, 'm1-externe');
      return EcranExterne.cartoucheBulletin(p, {'numero': 'F1', 'partPatient': 1000}, c, AccesSensible.de(c)).map((e) => '${e.$1}:${e.$2}').join('\n');
    }

    var s = bulletin();
    expect(s, contains(tel), reason: 'sentinelle : lu par défaut');
    expect(s, contains('RUE-SECRETE'));
    decider(m, role, {'coordonnees': false, 'identite_detaillee': false});
    s = bulletin();
    expect(s, isNot(contains(tel)));
    expect(s, isNot(contains('RUE-SECRETE')));
    expect(s, isNot(contains('41')));
    expect(s, contains(reserve('coordonnees')));
    expect(s, contains(reserve('identite_detaillee')));
    expect(s, contains('Dr X'), reason: 'ce qui n’est pas une donnée du patient reste');
    decider(m, role, {'coordonnees': true, 'identite_detaillee': true});
    expect(bulletin(), contains(tel), reason: 'droit accordé : le papier reprend la valeur');

    final piece = {'contenu': 'MENTION-SECRETE', 'couverture': 'COUV-XYZ'};
    String papier() {
      final c = contexte(m, role, 'm1-pieces');
      return EcranPieces.blocsPiece(piece, AccesSensible.de(c)).map((b) => b is BlocTexte ? b.texte : '').join('\n');
    }

    expect(papier(), contains('MENTION-SECRETE'));
    decider(m, role, {'notes_consultation': false, 'couverture_assurance': false});
    s = papier();
    expect(s, isNot(contains('MENTION-SECRETE')));
    expect(s, isNot(contains('COUV-XYZ')));
    expect(s, contains(reserve('notes_consultation')));
    // Le formulaire de délivrance ne propose pas non plus de saisir ce qu'on ne peut pas lire.
    final c = contexte(m, role, 'm1-pieces');
    expect(EcranPieces.champs(c, null).any((d) => d.nom == 'contenu'), isFalse);
    decider(m, role, {'notes_consultation': true});
    expect(EcranPieces.champs(contexte(m, role, 'm1-pieces'), null).any((d) => d.nom == 'contenu'), isTrue, reason: 'relu à chaque appel');
  });

  test('GARDE : aucune comparaison de nom de rôle dans le masquage ajouté', () {
    final roles = [for (final r in donnees.matrice.rolesBruts) '${r['id']}'];
    final fichiers = [
      'lib/kit/champ_sensible.dart',
      'lib/modules/m1/fiche.dart',
      'lib/modules/m1/fiche_impression.dart',
      'lib/modules/m1/patients.dart',
      'lib/shell/recherche_globale.dart',
      'lib/modules/m1/externe.dart',
      'lib/modules/m1/pieces.dart',
      'lib/modules/m3/hos_admissions.dart',
      'lib/modules/m3/hos_plan_lits.dart',
      'lib/modules/m3/hos_temperature.dart',
      'lib/modules/m3/hos_observation.dart',
      'lib/modules/m3/hos_soins.dart',
      'lib/modules/m3/surv_surveillance.dart',
      'lib/modules/m3/surv_administrations.dart',
      'lib/modules/m3/surv_glasgow.dart',
      'lib/modules/m3/surv_transfusion.dart',
      'lib/modules/m3/surv_rapport.dart',
      'lib/modules/m3/surv_visites.dart',
      'lib/modules/m3/bloc_sorties.dart',
      'lib/modules/m3/bloc_avis_medical.dart',
      'lib/modules/m2/cs_consultations.dart',
      'lib/modules/m2/cs_ordonnances.dart',
      'lib/modules/m2/cs_fiche.dart',
      'lib/modules/m2/cs_dossiers.dart',
    ];
    for (final f in fichiers) {
      for (final l in File(f).readAsLinesSync()) {
        final u = l.trimLeft();
        if (u.startsWith('//')) continue;
        // Les lignes du masquage : tout appel au point unique, ou à la catégorie.
        if (!RegExp(r'AccesSensible|\.peut\(|texteSi|masquerSi|MentionReservee|GardeSensible|peutLireChamp|\.colonne\(').hasMatch(l)) continue;
        for (final r in roles) {
          expect(RegExp('[\'"]${RegExp.escape(r)}[\'"]').hasMatch(l), isFalse, reason: '$f nomme le rôle « $r » : $l');
        }
      }
    }
  });
}
