import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/service_droits.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/m10/rha_commun.dart' show remunerationReservee;
import 'package:sigh_poste/modules/m10/rhb_planning.dart' show honoraireReserve;
import 'package:sigh_poste/shell/page_standard.dart';

import 'aide_polices.dart';

/// OUVERTURES EN LECTURE du 16/11/2026, AU POSTE : chaque écran ouvert s'affiche sous son rôle (et non la page 403), sans commande d'écriture ; le plan
/// des lits se lit SANS le séjour pour les profils qui n'ouvrent pas les admissions ; le planning se lit SANS le montant des honoraires pour les profils qui
/// ne lisent pas les primes. Les rôles nommés ici sont ceux du TEST : le code testé n'en connaît aucun, il lit la matrice (`packages/domaine/test/
/// ouvertures_lecture_16_11_test.dart` sonde la matrice elle-même).
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 11, 16, 10);

const ouvertures = <String, List<String>>{
  'dm': ['m10-planning'],
  'infirmier': ['m10-planning'],
  'reception': ['m10-planning'],
  'ambulancier': ['m10-planning'],
  'chirurgien': ['m10-planning'],
  'laborantin': ['cfg-tarifs', 'cfg-catalogue'],
  'echographiste': ['cfg-tarifs', 'cfg-catalogue'],
  'responsable_radiologie': ['cfg-tarifs', 'cfg-catalogue'],
  'comptable': ['cfg-tarifs', 'cfg-catalogue'],
  'anesthesiste': ['m6-stock-detail', 'm6-lots'],
  'agentadmin': ['m3-plan-lits'],
  'surveillant': ['m3-plan-lits', 'm10-personnel', 'm10-employe-profil'],
  'aide_soignant': ['m3-plan-lits'],
  'assistant_comptable': ['m2-stats-consultations', 'm3-stats-hospitalisations', 'm6-point-ventes'],
};

Magasin jeu() {
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu);
  m.utilisateur = 'Direction';
  ServiceDroits.de(m).fileulRattache = () => false;
  return m;
}

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, String role) async {
  t.view.physicalSize = const Size(1600, 2600);
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

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

/// Les textes affichés, toute espace retirée (le poste compose les montants avec des espaces fines insécables).
Set<String> textesSansEspaces(WidgetTester t) => {
      for (final w in t.widgetList<Text>(find.byType(Text))) (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll(RegExp(r'[\s\u00a0\u202f]'), '')
    };

/// Le premier lit OCCUPÉ du plan (une admission en cours) : son libellé.
String litOccupe(Magasin m) {
  for (final a in m.collection('admissions').actives) {
    if ((a['dateSortie'] == null || a['dateSortie'] == '') && a['statut'] == 'en_cours' && a['lit'] != null) return '${a['lit']}';
  }
  throw StateError('aucune admission en cours dans le jeu');
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  testWidgets('chaque écran ouvert s’affiche sous son rôle (jamais la page 403), en lecture seule', (t) async {
    final m = jeu();
    for (final o in ouvertures.entries) {
      for (final e in o.value) {
        await ouvrir(t, m, e, o.key);
        expect(find.text('Accès refusé'), findsNothing, reason: '${o.key} → $e');
        expect(find.byType(PageStandard), findsOneWidget, reason: '${o.key} → $e');
        final d = donnees.aChaud(m).matrice.droit(o.key, e);
        expect(d, const Droit(voir: true, editer: false, annuler: false), reason: '${o.key} → $e');
      }
    }
  });

  group('plan des lits : le PLAN sans le séjour', () {
    for (final role in ['agentadmin', 'surveillant', 'aide_soignant']) {
      testWidgets('$role : qui occupe quel lit, sans diagnostic, sans prise en charge, sans geste', (t) async {
        final m = jeu();
        for (final a in m.collection('admissions').actives) {
          m.collection('admissions').mettreAJour(a['id'], {'diagnosticEntree': 'DIAG-XYZ'});
        }
        await ouvrir(t, m, 'm3-plan-lits', role);
        expect(find.byKey(const Key('garde-sensible:hospitalisation_soins')), findsNothing, reason: 'l’écran s’ouvre');
        expect(find.byKey(const Key('plan:vue-restreinte')), findsOneWidget, reason: 'la vue restreinte se dit');
        final lit = litOccupe(m);
        // Les accès rapides de l'en-tête peuvent porter un raccourci vers un écran que le rôle a (la feuille de température de l'aide-soignante) : on
        // compte avant d'ouvrir le tiroir, le tiroir ne doit rien y ajouter.
        final feuillesAvant = find.widgetWithText(BoutonSigh, 'Feuille de température').evaluate().length;
        await toucher(t, find.byKey(Key('plan:lit:$lit')));
        expect(find.text('Date d’entrée'), findsOneWidget, reason: 'le plan : depuis quand');
        expect(find.byKey(const Key('sensible:hospitalisation_soins')), findsOneWidget, reason: 'le tiroir dit ce qu’il ne montre pas');
        expect(find.text('DIAG-XYZ'), findsNothing, reason: 'aucun diagnostic');
        expect(find.text('Diagnostic d’entrée'), findsNothing);
        expect(find.text('Prise en charge'), findsNothing);
        expect(find.text('Infirmier référent'), findsNothing);
        expect(find.widgetWithText(BoutonSigh, 'Préparer la sortie'), findsNothing, reason: 'aucun geste');
        expect(find.widgetWithText(BoutonSigh, 'Feuille de température').evaluate().length, feuillesAvant, reason: 'le tiroir n’offre aucun geste');
      });
    }

    testWidgets('un profil qui ouvre les admissions garde le plan entier (rien ne change pour lui)', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm3-plan-lits', 'reception');
      expect(find.byKey(const Key('plan:vue-restreinte')), findsNothing);
      await toucher(t, find.byKey(Key('plan:lit:${litOccupe(m)}')));
      expect(find.text('Diagnostic d’entrée'), findsOneWidget);
      expect(find.widgetWithText(BoutonSigh, 'Préparer la sortie'), findsOneWidget);
    });

    testWidgets('une catégorie fermée par DÉCISION de la clinique ferme l’écran entier, comme avant', (t) async {
      final m = jeu();
      ServiceDroits.de(m).decider(
          role: 'agentadmin',
          valeurs: {'donneesSensibles': {'hospitalisation_soins': false}},
          journal: 'Droit sur les données sensibles',
          motif: 'Décision de la Direction',
          auteurRole: 'admin');
      await ouvrir(t, m, 'm3-plan-lits', 'agentadmin');
      expect(find.byKey(const Key('garde-sensible:hospitalisation_soins')), findsOneWidget);
      expect(find.byKey(const Key('plan:vue-restreinte')), findsNothing);
    });
  });

  group('planning : qui est de garde, sans le montant des honoraires', () {
    for (final role in ['dm', 'infirmier', 'reception', 'ambulancier', 'chirurgien']) {
      testWidgets('$role : lecture, aucune case modifiable, honoraires réservés', (t) async {
        final m = jeu();
        await ouvrir(t, m, 'm10-planning', role);
        expect(find.byKey(const Key('rhb:honoraire-reserve')), findsWidgets, reason: 'le montant est remplacé par la mention');
        expect(textesSansEspaces(t).contains('5000'), isFalse, reason: 'aucun montant d’honoraire (5 000 FCFA du régime d’incinération)');
        expect(find.widgetWithText(BoutonSigh, 'Nouveau régime'), findsNothing);
        expect(find.text('+'), findsNothing, reason: 'aucune case à affecter');
      });
    }

    testWidgets('les profils qui lisaient déjà le planning gardent les montants (DAF : primes ; surveillant : écriture du planning)', (t) async {
      for (final role in ['da', 'surveillant']) {
        final m = jeu();
        await ouvrir(t, m, 'm10-planning', role);
        expect(find.byKey(const Key('rhb:honoraire-reserve')), findsNothing, reason: role);
        expect(find.text(honoraireReserve), findsNothing, reason: role);
        expect(textesSansEspaces(t).contains('5000'), isTrue, reason: '$role lit le montant');
      }
    });
  });

  group('fiche du personnel : lecture seule, rémunération masquée (17/11/2026, point 1)', () {
    // L'onglet de la FICHE (le ruban porte lui aussi des libellés de même nom).
    Finder onglet(String nom) => find.descendant(of: find.byType(OngletsSigh), matching: find.text(nom));

    Future<void> ouvrirFiche(WidgetTester t, Magasin m, String role) async {
      await ouvrir(t, m, 'm10-employe-profil', role);
      expect(find.text('Accès refusé'), findsNothing, reason: role);
    }

    testWidgets('le Surveillant lit l’identité et le planning, sans salaire, sans CNSS, sans primes, sans évaluations, sans assurances', (t) async {
      final m = jeu();
      final agent = m.collection('personnel').actives.reduce((a, b) => '${a['matricule']}'.compareTo('${b['matricule']}') <= 0 ? a : b);
      // Le premier agent affiché a adopté le régime d'incinération (honoraire de 5 000 F) : le montant est celui qu'on ne doit pas lire.
      m.collection('regimesIndividuels').inserer({
        'id': 'RGI-T1',
        'employeId': agent['id'],
        'dateEffet': '2026-01-01',
        'mode': 'remplacement',
        'baseRemplacement': 'Incinération des déchets de l’hôpital',
        'champs': <String, Object?>{},
      });
      await ouvrirFiche(t, m, 'surveillant');
      expect(find.text('Matricule'), findsWidgets);
      expect(find.text(remunerationReservee), findsNWidgets(2), reason: 'salaire et N° CNSS : la mention, jamais un champ vide');
      final cnss = '${agent['cnss'] ?? ''}';
      if (cnss.isNotEmpty) expect(textesSansEspaces(t).any((x) => x.contains(cnss.replaceAll(' ', ''))), isFalse, reason: 'aucun numéro CNSS');
      expect(textesSansEspaces(t).contains(textesSansEspaces(t).firstWhere((x) => x == '${agent['salaireBase']}', orElse: () => '#')), isFalse);
      for (final nom in ['Primes (NS 132)', 'Évaluations & sanctions', 'Assurances']) {
        await toucher(t, onglet(nom));
        expect(find.byKey(const Key('rha:remuneration-reservee')), findsOneWidget, reason: nom);
      }
      // Aucune commande d'écriture du dossier : ni « Modifier », ni « Nouveau ».
      expect(find.widgetWithText(BoutonSigh, 'Nouveau'), findsNothing);
      // Le planning individuel se lit, sans le montant de l'honoraire (la règle de la fiche s'ajoute à celle du planning), et ne s'écrit pas sans le geste réservé.
      await toucher(t, onglet('Planning individuel'));
      expect(find.byKey(const Key('pli:regime')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('pli:valeur:honoraire'))).data, honoraireReserve, reason: 'l’honoraire du régime est DIT réservé, jamais vidé ni montré');
      expect(textesSansEspaces(t).any((x) => x.contains('5000')), isFalse, reason: 'aucun montant d’honoraire à qui ne lit pas la rémunération');
      expect(find.widgetWithText(BoutonSigh, 'Nouvelle version'), findsNothing, reason: 'écriture réservée au geste « Régler le personnel »');
    });

    testWidgets('le registre du personnel ouvert au Surveillant : colonnes salaire et CNSS réservées, masse salariale absente', (t) async {
      final m = jeu();
      await ouvrir(t, m, 'm10-personnel', 'surveillant');
      expect(find.text('Accès refusé'), findsNothing);
      expect(find.text('réservé'), findsWidgets);
      expect(find.text('Masse salariale'), findsNothing);
      expect(find.text('Salaire moyen'), findsNothing);
      expect(find.text('Effectif'), findsWidgets);
      expect(find.widgetWithText(BoutonSigh, 'Nouvel agent'), findsNothing);
    });

    testWidgets('la DAF lit tout comme avant (rien ne change pour elle)', (t) async {
      final m = jeu();
      final agent = m.collection('personnel').actives.reduce((a, b) => '${a['matricule']}'.compareTo('${b['matricule']}') <= 0 ? a : b);
      m.collection('regimesIndividuels').inserer({
        'id': 'RGI-T1',
        'employeId': agent['id'],
        'dateEffet': '2026-01-01',
        'mode': 'remplacement',
        'baseRemplacement': 'Incinération des déchets de l’hôpital',
        'champs': <String, Object?>{},
      });
      await ouvrirFiche(t, m, 'da');
      expect(find.text(remunerationReservee), findsNothing);
      await toucher(t, onglet('Primes (NS 132)'));
      expect(find.byKey(const Key('rha:remuneration-reservee')), findsNothing);
      await toucher(t, onglet('Planning individuel'));
      expect(find.text(honoraireReserve), findsNothing);
      expect(textesSansEspaces(t).any((x) => x.contains('5000')), isTrue, reason: 'la DAF lit le montant');
      await ouvrir(t, m, 'm10-personnel', 'da');
      expect(find.text('réservé'), findsNothing);
      expect(find.text('Masse salariale'), findsOneWidget);
    });
  });
}
