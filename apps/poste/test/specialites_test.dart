import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'aide_qualite.dart' show ouvrir, toucher, saisir, choisir, cas, kpi, donnees, aujourdhui;

/// LES QUATORZE SPÉCIALITÉS (PRD P0-12), au geste : une seule mécanique pilotée par des données. On crée une consultation depuis le formulaire ENGENDRÉ
/// du modèle, on la retrouve au dossier du patient, on ajoute une quinzième spécialité par une fiche — sans code — et on la voit au ruban ; un rôle sans le
/// module n'ouvre rien ; les statistiques se recomptent. Les règles pures sont rejouées dans `packages/domaine/test/spec_*_test.dart`.
List<Map<String, Object?>> livre(String nom) =>
    [for (final x in (jsonDecode(File('assets/donnees/jeu/$nom.json').readAsStringSync()) as List)) (x as Map).cast<String, Object?>()];

Magasin magasin({int? patients, bool consultations = true, String? seulement}) {
  final tous = [for (final p in livre('patients')) if (seulement == null || p['code'] == seulement) p];
  return Magasin({
    'audit': const <Fiche>[],
    'specialites': specFichesDeBase(),
    'patients': [for (final p in (patients == null ? tous : tous.take(patients))) {...p}],
    'personnel': livre('personnel'),
    'actes': livre('actes'),
    'catalogueTarifs': livre('catalogueTarifs'),
    'couverturesAssurance': livre('couverturesAssurance'),
    'souscripteurs': livre('souscripteurs'),
    'garanties': livre('garanties'),
    'typesPiece': livre('typesPiece'),
    'conventionsVisites': livre('conventionsVisites'),
    'consultations': consultations ? livre('consultations') : const <Fiche>[],
    'pieces': const <Fiche>[],
    'factures': const <Fiche>[],
    'ecritures': const <Fiche>[],
    'taches': const <Fiche>[],
    'fileAttente': const <Fiche>[],
  }, 'POSTE', {...(jsonDecode(File('test/fixtures/jeu_reference/referentiels.json').readAsStringSync()) as Map).cast<String, Object?>()});
}

Future<void> saisirDernier(WidgetTester t, String champ, String valeur) async {
  await t.enterText(find.descendant(of: find.byKey(Key('kit:champ:$champ')).last, matching: find.byType(TextField)), valeur);
  await t.pump();
}

bool aBouton(String libelle) => find.byWidgetPredicate((w) => w is BoutonSigh && w.libelle == libelle).evaluate().isNotEmpty;

/// Une consultation spécialisée de la clinique, par un praticien : `statut`, `date` et `diagnostic` à l'appel.
int compte(Magasin m, String code, {String statut = 'terminee'}) =>
    m.collection('consultations').actives.where((x) => specDeLaConsultation(x) == code && x['statut'] == statut).length;

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('le jeu livré', () {
    test('les quatorze fiches sont semées, sans marquage « à valider », avec leur source', () {
      final f = livre('specialites');
      expect(f.length, 14);
      expect(f.map((x) => x['libelle']).toList(), specFichesDeBase().map((x) => x['libelle']).toList());
      for (final x in f) {
        expect(x.containsKey('aValider'), isFalse);
        expect(x['source'], specSource);
        expect(specRefusModele(x['modele']), isNull, reason: '${x['code']}');
      }
    });

    test('les consultations de démonstration sont fictives et rattachées à leur spécialité : 110 visites du travail, 30 consultations de spécialistes', () {
      final c = livre('consultations');
      final rattachees = c.where((x) => specDeLaConsultation(x) != null).toList();
      expect(rattachees.length, 140);
      expect(c.where((x) => x['specialite'] == 'medecine-travail').length, 110);
      final codes = {for (final x in livre('specialites')) '${x['code']}'};
      for (final x in rattachees) {
        expect(codes, contains(specDeLaConsultation(x)));
      }
      // Chaque vacataire spécialiste ne consulte que dans SA spécialité.
      final presta = {for (final p in livre('prestataires')) '${p['nom']}': '${p['specialite']}'};
      for (final x in c.where((x) => x['specialite'] != null && x['specialite'] != 'medecine-travail')) {
        expect(x['specialiteLibelle'], presta['${x['medecin']}']);
      }
    });

    test('six conventions de visites, une par entreprise cliente fictive ; la fiche d\'aptitude est une pièce du registre (TPC15, grille MT-FAP)', () {
      final conv = livre('conventionsVisites');
      final entreprises = livre('souscripteurs').where((s) => s['categorie'] == 'entreprise').map((s) => s['id']).toList();
      expect(conv.map((c) => c['entrepriseId']).toList(), entreprises);
      expect(conv.length, 6);
      expect(conv.every((c) => c['fictif'] == true && '${c['source']}'.isNotEmpty), isTrue);
      final tp = livre('typesPiece').firstWhere((t) => t['id'] == 'TPC15');
      expect(tp['tarifCode'], 'MT-FAP');
      expect(livre('catalogueTarifs').any((t) => t['code'] == 'MT-FAP'), isTrue);
    });
  });

  group('le ruban et les droits', () {
    cas('les quatorze spécialités sont au ruban du médecin, dans la rangée « Spécialités » de SOINS', (t) async {
      await ouvrir(t, magasin(patients: 3), 'm2-specialites', role: 'medecin');
      expect(find.byKey(const Key('panneau-ruban')), findsOneWidget);
      for (final f in specFichesDeBase()) {
        expect(find.byKey(Key('pastille-spec-${f['code']}')), findsOneWidget, reason: '${f['libelle']}');
      }
      expect(find.text('SPÉCIALITÉS'), findsWidgets);
    });

    test('les droits d\'une spécialité sont ceux de l\'écran modèle, pour CHAQUE rôle : aucun écran ouvert à un rôle qui n\'a pas le module', () {
      final nav = donnees.aChaud(magasin(patients: 3));
      expect(nav.manifeste.ecran('spec-cardiologie'), isNotNull);
      for (final r in nav.matrice.rolesBruts) {
        final role = '${r['id']}';
        for (final v in SpecVue.values) {
          final modele = nav.matrice.droit(role, specModelesDroits[v]!);
          expect(nav.matrice.droit(role, specIdEcran('cardiologie', v)), modele, reason: '$role / ${v.name}');
        }
      }
      // Les rôles sans le module M2 : rien.
      for (final role in ['caissier', 'comptable', 'stock', 'laborantin', 'rh', 'pharmacien']) {
        expect(nav.matrice.ecransVisibles(role).where((e) => e.startsWith(specPrefixe)), isEmpty, reason: role);
      }
      // L'accueil entre à l'agenda, jamais à la consultation (RG-13) ; le médecin à tout.
      expect(nav.matrice.peutVoir('reception', 'spec-cardiologie-agenda'), isTrue);
      expect(nav.matrice.peutVoir('reception', 'spec-cardiologie-consultation'), isFalse);
      for (final v in SpecVue.values) {
        expect(nav.matrice.peutVoir('medecin', specIdEcran('cardiologie', v)), isTrue);
      }
      expect(nav.matrice.peutEditer('direction', 'spec-cardiologie-consultation'), isFalse);
    });

    cas('un rôle sans le module n\'ouvre pas la consultation : le formulaire ne se dessine pas', (t) async {
      await ouvrir(t, magasin(patients: 3), 'spec-cardiologie-consultation', role: 'caissier');
      expect(aBouton('Nouvelle consultation'), isFalse);
      expect(find.byType(TableauSigh), findsNothing);
    });

    cas('l\'accueil ne voit pas la consultation ; la direction la lit sans pouvoir y écrire', (t) async {
      final m = magasin(patients: 3);
      await ouvrir(t, m, 'spec-cardiologie-consultation', role: 'reception');
      expect(find.byType(TableauSigh), findsNothing);
      await ouvrir(t, m, 'spec-cardiologie-consultation', role: 'direction');
      expect(find.byType(TableauSigh), findsOneWidget);
      expect(aBouton('Nouvelle consultation'), isFalse, reason: 'une commande interdite est absente, jamais grisée');
    });

    cas('le hub de la chirurgie renvoie vers le bloc : les cartes d\'un écran fermé au profil sont absentes', (t) async {
      final m = magasin(patients: 3);
      await ouvrir(t, m, 'spec-chirurgie', role: 'medecin');
      expect(find.byKey(const Key('spec-renvoi:m3-bloc-cro')), findsOneWidget);
      expect(find.byKey(const Key('spec-carte:spec-chirurgie-consultation')), findsOneWidget);
      // Un rôle qui voit la spécialité sans voir le bloc : sa carte de renvoi est absente (jamais une carte vers un écran fermé).
      final nav = donnees.aChaud(m);
      final role = [for (final r in nav.matrice.rolesBruts) '${r['id']}'].firstWhere(
          (r) => nav.matrice.peutVoir(r, 'spec-chirurgie') && !nav.matrice.peutVoir(r, 'm3-bloc-cro'),
          orElse: () => '');
      expect(role, isNotEmpty, reason: 'au moins un rôle voit la chirurgie sans voir le bloc');
      await ouvrir(t, m, 'spec-chirurgie', role: role);
      expect(find.byKey(const Key('spec-renvoi:m3-bloc-cro')), findsNothing);
      expect(find.byKey(const Key('spec-carte:spec-chirurgie-agenda')), findsOneWidget);
      // L'accueil, lui, n'a pas la consultation : sa carte est absente.
      await ouvrir(t, m, 'spec-chirurgie', role: 'reception');
      expect(find.byKey(const Key('spec-carte:spec-chirurgie-consultation')), findsNothing);
      expect(find.byKey(const Key('spec-carte:spec-chirurgie-agenda')), findsOneWidget);
    });
  });

  group('la consultation spécialisée : le formulaire naît du modèle', () {
    cas('on crée une consultation de cardiologie, elle passe par la caisse et se retrouve au dossier du patient', (t) async {
      final m = magasin(consultations: false, seulement: 'CBG/2/26');
      await ouvrir(t, m, 'spec-cardiologie-consultation', role: 'medecin');
      await toucher(t, find.text('Nouvelle consultation').first);
      // Le formulaire est celui du MODÈLE de la fiche : ses questions, l'examen de l'appareil cardio-vasculaire, la conclusion.
      expect(find.text('Fréquence cardiaque (bpm)'), findsOneWidget);
      expect(find.text('Appareil cardio-vasculaire — Auscultation'), findsOneWidget);
      expect(find.textContaining('Diagnostic retenu'), findsWidgets);
      await choisir(t, 'patientCode', 'CBG/2/26 — BIO-GUERA Hadjara');
      await saisir(t, 'q_fc', '88');
      await saisir(t, 'q_tension', '15/9');
      await saisir(t, 'ex.cardio_vasculaire.auscultation', 'B1 B2 réguliers, pas de souffle');
      await saisir(t, 'diagnostic', 'Hypertension artérielle');
      await toucher(t, find.text('Enregistrer la consultation').last);

      final c = m.collection('consultations').toutes.single;
      expect(c['specialite'], 'cardiologie');
      expect(c['patientCode'], 'CBG/2/26');
      expect(c['statut'], 'terminee');
      expect(c['diagnostic'], 'Hypertension artérielle');
      expect(c['reponses'], {'fc': 88, 'tension': '15/9'});
      expect((c['examensPhysiques'] as Map)['cardio_vasculaire'], {'auscultation': 'B1 B2 réguliers, pas de souffle'});
      expect(c['reference'], 'C00001');
      // La caisse : l'acte de consultation spécialiste, au tarif de la grille, facture non réglée ; le comptable informé en brouillon (RG-10).
      final f = m.collection('factures').toutes.single;
      expect(f['type'], specTypeConsultation);
      expect(((f['lignes'] as List).single as Map)['acteCode'], 'CH01');
      expect(f['montantTTC'], 10000);
      expect(f['montantPaye'], 0);
      expect(c['factureNumero'], f['numero']);
      expect(c['tarif'], 10000);
      expect(m.collection('ecritures').toutes, isNotEmpty);
      expect(m.collection('audit').toutes, isNotEmpty, reason: 'RG-12 : le geste est journalisé');
      expect(find.text('Consultation enregistrée au dossier de BIO-GUERA Hadjara.'), findsOneWidget);

      // Au DOSSIER du patient : la rubrique « Consultations spécialisées » la porte.
      await ouvrir(t, m, 'm1-patient-profil', role: 'medecin');
      await toucher(t, find.byKey(const Key('m1:rubrique:specialites')));
      expect(find.text('Hypertension artérielle'), findsWidgets);
      expect(find.text('Cardiologie'), findsWidgets);
    });

    cas('un diagnostic absent ou un nombre hors des bornes du modèle : rien n\'est écrit, le refus est nommé', (t) async {
      final m = magasin(patients: 3, consultations: false);
      await ouvrir(t, m, 'spec-cardiologie-consultation', role: 'medecin');
      await toucher(t, find.text('Nouvelle consultation').first);
      await choisir(t, 'patientCode', 'CBG/2/26 — BIO-GUERA Hadjara');
      await toucher(t, find.text('Enregistrer la consultation').last);
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget, reason: 'le diagnostic est obligatoire');
      await saisir(t, 'diagnostic', 'RAS');
      await saisir(t, 'q_fc', '900');
      await toucher(t, find.text('Enregistrer la consultation').last);
      expect(find.textContaining('dépasse le maximum'), findsOneWidget);
      expect(m.collection('consultations').toutes, isEmpty);
      expect(m.collection('factures').toutes, isEmpty);
    });

    cas('une spécialité sans acte de consultation tarifé : la consultation s\'enregistre, rien n\'est facturé et l\'écran le dit', (t) async {
      final m = magasin(patients: 3, consultations: false);
      await ouvrir(t, m, 'spec-sante-publique-consultation', role: 'medecin');
      await toucher(t, find.text('Nouvelle consultation').first);
      await choisir(t, 'patientCode', 'CBG/2/26 — BIO-GUERA Hadjara');
      await saisir(t, 'diagnostic', 'Vaccination à jour');
      await toucher(t, find.text('Enregistrer la consultation').last);
      expect(m.collection('consultations').toutes.single['tarif'], 0);
      expect(m.collection('factures').toutes, isEmpty);
      expect(find.textContaining('Aucun acte tarifé n’est rattaché'), findsOneWidget);
    });
  });

  group('une quinzième spécialité : une fiche, aucun code', () {
    cas('Dermatologie créée par sa fiche paraît au ruban, avec son hub et le formulaire de son modèle', (t) async {
      final m = magasin(patients: 3, consultations: false);
      expect(m.collection('specialites').actives.length, 14);
      await ouvrir(t, m, 'm2-specialites', role: 'admin');
      await toucher(t, find.text('Nouvelle spécialité').first);
      await saisirDernier(t, 'libelle', 'Dermatologie');
      await saisirDernier(t, 'code', 'dermatologie');
      await toucher(t, find.text('Ajouter une question').last);
      await saisirDernier(t, 'libelle', 'Type de lésion');
      await toucher(t, find.text('Ajouter').last);
      await toucher(t, find.text('Créer la spécialité').last);

      final f = m.collection('specialites').actives;
      expect(f.length, 15);
      final neuve = f.firstWhere((x) => x['code'] == 'dermatologie');
      expect(neuve['libelle'], 'Dermatologie');
      expect(neuve['statut'], 'actif');
      expect(specQuestionsPlates(neuve['modele']).single['libelle'], 'Type de lésion');
      expect(m.collection('audit').toutes, isNotEmpty);

      // Au ruban de tout rôle qui a le module, sans une ligne de code ajoutée.
      final nav = donnees.aChaud(m);
      for (final role in ['medecin', 'admin']) {
        final ruban = nav.manifeste.ruban(nav.matrice, role, estMere: false);
        expect([for (final d in ruban) for (final r in d.rangees) for (final e in r.ecrans) e.id], contains('spec-dermatologie'), reason: role);
      }
      expect(nav.manifeste.ruban(nav.matrice, 'caissier', estMere: false).expand((d) => d.rangees).expand((r) => r.ecrans).map((e) => e.id), isNot(contains('spec-dermatologie')));
      await ouvrir(t, m, 'm2-specialites', role: 'medecin');
      expect(find.byKey(const Key('pastille-spec-dermatologie')), findsOneWidget);

      // Son hub, puis le formulaire de son modèle : la question ajoutée à la fiche paraît à la saisie.
      await ouvrir(t, m, 'spec-dermatologie', role: 'medecin');
      expect(find.byKey(const Key('spec-carte:spec-dermatologie-consultation')), findsOneWidget);
      await ouvrir(t, m, 'spec-dermatologie-consultation', role: 'medecin');
      await toucher(t, find.text('Nouvelle consultation').first);
      expect(find.text('Type de lésion'), findsOneWidget);
    });

    cas('un code déjà pris, ou qui finit par un suffixe réservé, est refusé : aucune fiche n\'est créée', (t) async {
      final m = magasin(patients: 3, consultations: false);
      await ouvrir(t, m, 'm2-specialites', role: 'admin');
      await toucher(t, find.text('Nouvelle spécialité').first);
      await saisirDernier(t, 'libelle', 'Doublon');
      await saisirDernier(t, 'code', 'cardiologie');
      await toucher(t, find.text('Ajouter une question').last);
      await saisirDernier(t, 'libelle', 'Q');
      await toucher(t, find.text('Ajouter').last);
      await toucher(t, find.text('Créer la spécialité').last);
      expect(m.collection('specialites').actives.length, 14);
      expect(find.textContaining('déjà le code'), findsOneWidget);
    });

    test('une fiche archivée quitte le ruban sans rien perdre (RG-14)', () {
      final m = magasin(patients: 3);
      final spec = m.collection('specialites').actives.firstWhere((x) => x['code'] == 'urologie');
      final avant = compte(m, 'urologie');
      m.collection('specialites').archiver(spec['id']);
      final nav = donnees.aChaud(m);
      expect(nav.manifeste.ecran('spec-urologie'), isNull);
      expect(nav.manifeste.ecran('spec-cardiologie'), isNotNull);
      expect(compte(m, 'urologie'), avant, reason: 'les consultations restent lisibles');
      expect(m.collection('specialites').toutes.length, 14);
    });
  });

  group('les statistiques sont recomptées depuis les registres', () {
    cas('les chiffres affichés sont ceux d\'un recomptage indépendant, et suivent une nouvelle consultation', (t) async {
      final m = magasin();
      final brut = livre('consultations').where((x) => x['specialite'] == 'cardiologie' && x['statut'] == 'terminee').toList();
      expect(brut, isNotEmpty);
      final patients = {for (final x in brut) x['patientId']}.length;
      await ouvrir(t, m, 'spec-cardiologie-stats', role: 'medecin');
      expect(kpi(t, 'Consultations').replaceAll(RegExp(r'\s'), ''), '${brut.length}');
      expect(kpi(t, 'Patients distincts').replaceAll(RegExp(r'\s'), ''), '$patients');
      final facture = brut.fold<num>(0, (a, x) => a + (x['tarif'] as num? ?? 0));
      expect(kpi(t, 'Facturé').replaceAll(RegExp(r'[^\d]'), ''), '${facture.toInt()}');
      // Une consultation de plus : le compte suit, rien n'est « fourni ».
      m.collection('consultations').inserer({
        'statut': 'terminee',
        'specialite': 'cardiologie',
        'specialiteLibelle': 'Cardiologie',
        'patientId': 'PAT0099',
        'patientCode': 'CBG/99/26',
        'patient': 'TEST Stat',
        'medecin': 'Cardiologue vacataire (fictif de démonstration)',
        'date': '2026-08-16T08:00:00.000Z',
        'diagnostic': 'Angor',
        'tarif': 10000,
      }, prefixe: 'CON');
      await t.pump(const Duration(milliseconds: 100));
      expect(kpi(t, 'Consultations').replaceAll(RegExp(r'\s'), ''), '${brut.length + 1}');
      expect(kpi(t, 'Patients distincts').replaceAll(RegExp(r'\s'), ''), '${patients + 1}');
      expect(find.text('Par praticien'), findsOneWidget);
      expect(find.text('Diagnostics les plus fréquents'), findsOneWidget);
    });

    cas('médecine du travail : la répartition des avis d\'aptitude est celle des visites', (t) async {
      final m = magasin();
      final visites = livre('consultations').where((x) => x['specialite'] == 'medecine-travail').toList();
      final apte = visites.where((x) => x['aptitude'] == 'Apte').length;
      await ouvrir(t, m, 'spec-medecine-travail-stats', role: 'medecin');
      expect(find.text('Avis d’aptitude'), findsOneWidget);
      expect(kpi(t, 'Consultations').replaceAll(RegExp(r'\s'), ''), '${visites.length}');
      expect(apte, greaterThan(0));
      final s = specStatistiques('medecine-travail', consultations: m.collection('consultations').actives, aujourdhui: aujourdhui);
      expect(s.aptitudes.firstWhere((e) => e.libelle == 'Apte').valeur, apte);
    });
  });

  group('l\'agenda et la file', () {
    cas('un rendez-vous pris dans la spécialité, honoré, DEVIENT la consultation (il n\'en naît pas une seconde)', (t) async {
      final m = magasin(patients: 3, consultations: false);
      await ouvrir(t, m, 'spec-cardiologie-agenda', role: 'medecin');
      await toucher(t, find.text('Nouveau rendez-vous').first);
      await choisir(t, 'patientCode', 'CBG/2/26 — BIO-GUERA Hadjara');
      await saisir(t, 'motif', 'Contrôle tensionnel');
      await toucher(t, find.text('Enregistrer le rendez-vous').last);
      final rdv = m.collection('consultations').toutes.single;
      expect(rdv['statut'], 'planifiee');
      expect(rdv['specialite'], 'cardiologie');
      expect(compte(m, 'cardiologie'), 0, reason: 'un rendez-vous planifié n\'est pas une consultation');

      await toucher(t, find.byTooltip('Consulter (honorer le rendez-vous)').first);
      await saisir(t, 'diagnostic', 'Hypertension équilibrée');
      await toucher(t, find.text('Enregistrer la consultation').last);
      final apres = m.collection('consultations').toutes;
      expect(apres.length, 1, reason: 'le rendez-vous est devenu la consultation');
      expect(apres.single['id'], rdv['id']);
      expect(apres.single['statut'], 'terminee');
      expect(apres.single['diagnostic'], 'Hypertension équilibrée');
      expect(apres.single['reference'], rdv['reference']);
      expect(compte(m, 'cardiologie'), 1);
    });

    cas('la file : on inscrit un patient, on l\'appelle ; la file porte le poste « Consultation » et la spécialité', (t) async {
      final m = magasin(patients: 3, consultations: false);
      await ouvrir(t, m, 'spec-cardiologie-agenda', role: 'medecin');
      await toucher(t, find.text('File d’attente (0)'));
      await toucher(t, find.text('Inscrire un patient').first);
      await choisir(t, 'patientCode', 'CBG/2/26 — BIO-GUERA Hadjara');
      await saisir(t, 'motif', 'Palpitations');
      await toucher(t, find.text('Inscrire').last);
      final tk = m.collection('fileAttente').toutes.single;
      expect(tk['poste'], 'consultation');
      expect(tk['specialite'], 'cardiologie');
      expect(tk['etat'], 'attente');
      await toucher(t, find.byTooltip('Appeler').first);
      expect(m.collection('fileAttente').toutes.single['etat'], 'servi');
      // La file d'une autre spécialité ne le voit pas.
      expect(specStatistiques('urologie', consultations: const [], fileAttente: m.collection('fileAttente').actives, aujourdhui: aujourdhui).fileEnAttente, 0);
    });

    cas('l\'accueil prend le rendez-vous mais ne peut pas consulter : la commande « Consulter » est absente', (t) async {
      final m = magasin(patients: 3, consultations: false);
      m.collection('consultations').inserer({
        'statut': 'planifiee', 'specialite': 'cardiologie', 'patientId': 'PAT0002', 'patientCode': 'CBG/2/26', 'patient': 'BIO-GUERA Hadjara',
        'medecin': 'IDOHOU Abraham', 'date': '2026-08-20T09:00:00.000Z', 'motif': 'Contrôle'
      }, prefixe: 'CON');
      await ouvrir(t, m, 'spec-cardiologie-agenda', role: 'reception');
      expect(aBouton('Nouveau rendez-vous'), isTrue);
      expect(find.byTooltip('Reporter'), findsWidgets);
      expect(find.byTooltip('Consulter (honorer le rendez-vous)'), findsNothing, reason: 'consulter, c\'est ouvrir le formulaire clinique : l\'accueil n\'y entre pas (RG-13)');
    });
  });

  group('la médecine du travail', () {
    cas('une visite d\'embauche : au dossier, avis d\'aptitude, pièce de caisse de la visite et fiche d\'aptitude tarifée comme pièce certifiante', (t) async {
      final m = magasin(patients: 3, consultations: false);
      await ouvrir(t, m, 'm2-mdt-visites', role: 'medecin');
      await toucher(t, find.text('Nouvelle visite').first);
      await choisir(t, 'nature', 'Visite médicale d’embauche');
      await choisir(t, 'entrepriseId', 'Société Cotonnière du Borgou');
      await choisir(t, 'patientCode', 'CBG/2/26 — BIO-GUERA Hadjara');
      await saisir(t, 'q_poste', 'Imprimeur');
      await choisir(t, 'q_aptitude', 'Apte');
      await saisir(t, 'diagnostic', 'Apte au poste de travail');
      await toucher(t, find.text('Enregistrer la visite').last);

      final c = m.collection('consultations').toutes.single;
      expect(c['type'], 'Médecine du travail');
      expect(c['natureVisite'], 'embauche');
      expect(c['entreprise'], 'Société Cotonnière du Borgou');
      expect(c['aptitude'], 'Apte');
      expect(c['poste'], 'Imprimeur');
      expect(specDeLaConsultation(c), 'medecine-travail');
      // La fiche d'aptitude : pièce certifiante (registre des pièces), tarifée sur MT-FAP par `patFacturerPiece`, numérotée FAP.
      final fa = c['ficheAptitude'] as Map;
      expect('${fa['reference']}', startsWith('FA-0001/'));
      expect('${fa['pieceReference']}', startsWith('FAP 001/001/'));
      expect(fa['valableJusqua'], isNotNull);
      final piece = m.collection('pieces').toutes.single;
      expect(piece['typeId'], 'TPC15');
      expect(piece['sigle'], 'FAP');
      expect(piece['montant'], 5000);
      expect(piece['factureId'], isNotNull);
      // Deux pièces de caisse : la visite (acte MT01, au tarif assuré de la carte valide à la date, RG-09) et la fiche d'aptitude.
      final factures = m.collection('factures').toutes;
      expect(factures.length, 2);
      final visite = factures.firstWhere((f) => f['type'] == 'Médecine du travail');
      expect(((visite['lignes'] as List).first as Map)['acteCode'], 'MT01');
      expect(visite['montantTTC'], 6000);
      expect(visite['consultationId'], c['id']);
      expect(c['factureNumero'], visite['numero']);
      expect(factures.firstWhere((f) => f['type'] == 'Certificat & attestation')['pieceRef'], piece['reference']);
      expect(m.collection('taches').toutes.where((x) => x['type'] == 'encaissement'), isNotEmpty);
      // Une visite n'est pas une consultation générale : elle compte à sa spécialité.
      expect(compte(m, 'medecine-travail'), 1);
    });

    cas('sans l\'entreprise ou sans avis d\'aptitude : rien n\'est écrit', (t) async {
      final m = magasin(patients: 3, consultations: false);
      await ouvrir(t, m, 'm2-mdt-visites', role: 'medecin');
      await toucher(t, find.text('Nouvelle visite').first);
      await choisir(t, 'nature', 'Visite médicale périodique');
      await choisir(t, 'patientCode', 'CBG/2/26 — BIO-GUERA Hadjara');
      await saisir(t, 'diagnostic', 'RAS');
      await toucher(t, find.text('Enregistrer la visite').last);
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget, reason: 'l\'entreprise et l\'avis sont obligatoires');
      expect(m.collection('consultations').toutes, isEmpty);
      expect(m.collection('pieces').toutes, isEmpty);
      expect(m.collection('factures').toutes, isEmpty);
    });

    cas('la fiche d\'aptitude d\'une visite qui n\'en a pas se délivre depuis la ligne, une seule fois', (t) async {
      final m = magasin(patients: 3, consultations: false);
      m.collection('consultations').inserer({
        'statut': 'terminee', 'type': 'Médecine du travail', 'specialite': 'medecine-travail', 'natureVisite': 'periodique', 'entrepriseId': 'SOU001',
        'entreprise': 'Société Cotonnière du Borgou', 'patientId': 'PAT0002', 'patientCode': 'CBG/2/26', 'patient': 'BIO-GUERA Hadjara',
        'medecin': 'IDOHOU Abraham', 'date': '2026-08-10T09:00:00.000Z', 'motif': 'Visite périodique', 'diagnostic': 'Apte', 'aptitude': 'Apte', 'poste': 'Imprimeur',
        'reference': 'C00001',
      }, prefixe: 'CON');
      await ouvrir(t, m, 'm2-mdt-visites', role: 'medecin');
      expect(kpi(t, 'Sans fiche d’aptitude'), '1');
      await toucher(t, find.byTooltip('Délivrer la fiche d’aptitude').first);
      final c = m.collection('consultations').toutes.single;
      expect((c['ficheAptitude'] as Map)['reference'], 'FA-0001/26');
      expect(m.collection('pieces').toutes.length, 1);
      expect(kpi(t, 'Sans fiche d’aptitude'), '0');
      expect(find.byTooltip('Délivrer la fiche d’aptitude'), findsNothing, reason: 'une fiche délivrée ne se délivre pas deux fois');
    });

    cas('annuler la délivrance défait TOUT : la fiche, la pièce du registre, la facture et la tâche de caisse', (t) async {
      final m = magasin(patients: 3, consultations: false);
      m.collection('consultations').inserer({
        'statut': 'terminee', 'type': 'Médecine du travail', 'specialite': 'medecine-travail', 'natureVisite': 'periodique', 'entrepriseId': 'SOU001',
        'entreprise': 'Société Cotonnière du Borgou', 'patientId': 'PAT0002', 'patientCode': 'CBG/2/26', 'patient': 'BIO-GUERA Hadjara',
        'medecin': 'IDOHOU Abraham', 'date': '2026-08-10T09:00:00.000Z', 'motif': 'Visite périodique', 'diagnostic': 'Apte', 'aptitude': 'Apte', 'poste': 'Imprimeur',
        'reference': 'C00001',
      }, prefixe: 'CON');
      await ouvrir(t, m, 'm2-mdt-visites', role: 'medecin');
      await toucher(t, find.byTooltip('Délivrer la fiche d’aptitude').first);
      expect(m.collection('pieces').actives.length, 1);
      expect(m.collection('factures').actives.length, 1);
      expect(m.collection('taches').actives.length, 1);
      await toucher(t, find.text('Annuler').first);
      expect(m.collection('pieces').actives, isEmpty);
      expect(m.collection('factures').actives, isEmpty, reason: 'la pièce de caisse de la fiche annulée ne reste pas due');
      expect(m.collection('taches').actives, isEmpty);
      expect(m.collection('consultations').toutes.single['ficheAptitude'], isNull);
    });

    cas('entreprises et salariés : les six entreprises fictives, leurs salariés (patients rattachés) et l\'échéance de chacun', (t) async {
      final m = magasin();
      final ent = livre('souscripteurs').where((s) => s['categorie'] == 'entreprise').map((s) => s['id']).toSet();
      final salaries = livre('patients').where((p) => ent.contains(p['souscripteurId'])).length;
      await ouvrir(t, m, 'm2-mdt-entreprises', role: 'medecin');
      expect(kpi(t, 'Entreprises clientes'), '${ent.length}');
      expect(kpi(t, 'Salariés connus').replaceAll(RegExp(r'\s'), ''), '$salaries');
      await toucher(t, find.textContaining('Salariés (').first);
      expect(find.text('DERNIÈRE VISITE'), findsOneWidget);
      expect(find.text('PROCHAINE VISITE'), findsOneWidget);
      // Aucun avis d'aptitude (donnée de santé) sur cette vue.
      expect(find.text('AVIS'), findsNothing);
    });

    cas('conventions : six en vigueur, le décompte oppose les visites prévues aux visites réalisées', (t) async {
      final m = magasin();
      await ouvrir(t, m, 'm2-mdt-conventions', role: 'medecin');
      expect(kpi(t, 'Conventions en vigueur'), '6');
      expect(kpi(t, 'Entreprises sans convention'), '0');
      final prevues = livre('conventionsVisites').fold<int>(0, (a, c) => a + (c['visitesAnnuellesPrevues'] as num).toInt());
      expect(kpi(t, 'Visites prévues par an').replaceAll(RegExp(r'\s'), ''), '$prevues');
      final realisees = livre('conventionsVisites')
          .fold<int>(0, (a, c) => a + mdtDecompteConvention(c, m.collection('consultations').actives, aujourdhui.year).realisees);
      expect(kpi(t, 'Réalisées cette année').replaceAll(RegExp(r'\s'), ''), '$realisees');
      expect(realisees, greaterThan(0));
    });
  });
}
