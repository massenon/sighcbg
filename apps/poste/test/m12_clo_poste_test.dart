import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m12/cpc_commun.dart' show amorcerExercices, definirMoisOuvertureSuivant;

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LOT CLO (clinique sœur), vérifié puis appliqué à Baguidi — décision du 16/11/2026, docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md § 6. L'ÉCRAN et le MAGASIN :
/// (a) colonnes N-1 du compte de résultat, (b) ouverture / clôture au grand livre (« Inconnu », jamais zéro, écran ET état imprimé), (c) journaux CL et AN
/// réservés au moteur (saisie et garde de la collection), (d) l'ouverture automatique n'écrit aucune pièce, (e) le bandeau de l'exercice et ses voisins.
Magasin magasinComplet() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Future<void> ouvrir(WidgetTester t, Magasin m, String ecran, {String role = 'admin', DateTime? horloge}) =>
    ouvrirM14(t, m, ecran, role: role, horloge: horloge);

/// Des à-nouveaux VALIDÉS au 1er janvier 2026, posés comme le fait l'importation des soldes d'ouverture (geste d'ouverture admis par la garde).
void poserANouveaux2026(Magasin m) {
  final col = m.collection('ecritures');
  for (final l in [
    {'compte': '571000', 'debit': 250000, 'credit': 0},
    {'compte': '101100', 'debit': 0, 'credit': 250000},
  ]) {
    col.inserer({
      'numero': 'AN-2026-00001',
      'date': '2026-01-01',
      'journal': 'AN',
      'journalLibelle': 'Journal des à-nouveaux',
      'libelle': 'Solde d’ouverture',
      ...l,
      'origine': cpcOrigineImportOuverture,
      'statut': 'validee',
    }, prefixe: 'ECR');
  }
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('(b) grand livre : solde d’ouverture et solde de clôture', () {
    casM14('sans à-nouveau, après la liasse déposée : l’écran dit « Inconnu » (jamais zéro), l’état imprimé aussi', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-grand-livre');
      expect(find.byKey(const Key('gl-ouverture-cloture')), findsOneWidget);
      expect(find.text('Inconnu'), findsWidgets, reason: 'ouverture et clôture inconnues');
      expect(find.textContaining('liasse déposée'), findsWidgets);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer le grand livre'));
      expect(find.textContaining('Solde d’ouverture'), findsWidgets);
      expect(find.text('Inconnu'), findsWidgets, reason: 'l’état imprimé dit « Inconnu »');
    });

    casM14('à-nouveaux validés : l’ouverture est ÉCRITE, la clôture = ouverture + mouvements validés (les à-nouveaux ne comptent pas deux fois)', (t) async {
      final m = magasinComplet();
      poserANouveaux2026(m);
      await ouvrir(t, m, 'm12-grand-livre');
      await choisirM14(t, 'compte', '571000 — Caisse');
      final actives = m.collection('ecritures').actives;
      final o = cpcOuvertureCompte(m.collection('exercices').toutes, actives, 2026, '571000');
      expect(o.statut, CpcStatutOuverture.ecrite);
      expect(o.solde, 250000);
      final clo = cpcClotureCompte(o, actives, 2026, '571000');
      expect(find.text(money(250000)), findsWidgets);
      expect(find.text('Écrit (à-nouveaux validés)'), findsOneWidget);
      expect(find.text(money(clo.solde!)), findsWidgets);
      expect(find.textContaining('AN-2026-00001'), findsWidgets);
    });
  });

  group('(c) journaux CL et AN réservés au moteur', () {
    test('la garde de la collection refuse une écriture manuelle au journal AN ou CL, en nommant ; le geste d’ouverture passe', () {
      final m = magasinComplet();
      final col = m.collection('ecritures');
      for (final j in ['AN', 'CL']) {
        expect(
            () => col.inserer({'numero': '$j-2026-00099', 'date': '2026-05-01', 'journal': j, 'compte': '571000', 'debit': 10, 'credit': 0, 'statut': 'brouillon', 'origine': 'Saisie manuelle'}),
            throwsA(isA<EcritureRefusee>().having((e) => e.motif, 'motif', contains('réservé au moteur'))),
            reason: j);
      }
      expect(m.collection('audit').toutes.any((x) => x['action'] == 'Écriture refusée'), isTrue, reason: 'RG-12 : le refus est journalisé');
      poserANouveaux2026(m);
      expect(col.actives.where((e) => e['journal'] == 'AN').length, 2);
    });

    casM14('la saisie d’une écriture ne propose ni AN ni CL', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-ecritures');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvelle écriture'));
      await toucherM14(t, find.descendant(of: find.byKey(const Key('kit:champ:journal')), matching: find.byType(InkWell)).first);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('OD — Journal des opérations diverses'), findsWidgets);
      expect(find.text('AN — Journal des à-nouveaux'), findsNothing);
      expect(find.text('CL — Journal de clôture'), findsNothing);
    });

    casM14('la vue des journaux annonce les journaux réservés au moteur', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-journaux');
      expect(find.textContaining('réservés au moteur'), findsWidgets);
    });
  });

  group('(d) l’ouverture automatique de l’exercice suivant n’écrit aucune pièce', () {
    test('en décembre, 2027 s’ouvre : une fiche d’exercice, ZÉRO écriture, aucun à-nouveau', () {
      final m = magasinComplet();
      final avant = m.collection('ecritures').toutes.length;
      int auditEcritures() => m.collection('audit').toutes.where((x) => x['entite'] == 'ecritures').length;
      final auditAvant = auditEcritures();
      expect(definirMoisOuvertureSuivant(m, 12, auteur: 'DAF'), isNull);
      amorcerExercices(m, DateTime(2026, 12, 1));
      expect(cpcEtatExercice(m.collection('exercices').toutes, 2027), 'ouvert');
      expect(m.collection('ecritures').toutes.length, avant, reason: 'aucune pièce écrite');
      expect(m.collection('ecritures').toutes.where((e) => e['journal'] == 'AN' || e['journal'] == 'CL'), isEmpty);
      expect(auditEcritures(), auditAvant, reason: 'le journal d’audit ne porte aucune nouvelle écriture comptable');
    });
  });

  group('(e) bandeau de l’exercice et boutons N-1 / N+1', () {
    casM14('grand livre : état de l’exercice du jour ; « Exercice 2025 » mène à l’exercice clos ; le défaut reste l’exercice du jour même si 2027 est ouvert d’avance', (t) async {
      final m = magasinComplet();
      amorcerExercices(m, DateTime(2026, 12, 2));
      await ouvrir(t, m, 'm12-grand-livre', horloge: DateTime(2026, 12, 2, 10));
      expect(find.byKey(const Key('bandeau-exercice')), findsOneWidget);
      expect(find.text('Exercice 2026 · ouvert'), findsOneWidget, reason: 'le sélecteur : le défaut est l’exercice qui contient la date du jour (v21)');
      expect(find.descendant(of: find.byKey(const Key('bandeau-exercice-etat')), matching: find.text('Ouvert')), findsOneWidget);
      expect(find.textContaining('Exercice 2026 ouvert : les écritures y entrent encore'), findsOneWidget);
      expect(find.byKey(const Key('bandeau-exercice-suivant')), findsOneWidget, reason: '2027 ouvert d’avance en décembre');
      expect(find.byKey(const Key('bandeau-exercice-precedent')), findsOneWidget);
      await toucherM14(t, find.byKey(const Key('bandeau-exercice-precedent')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Exercice 2025 · clos'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('bandeau-exercice-etat')), matching: find.text('Clos')), findsOneWidget);
      expect(find.textContaining('Exercice 2025 clos d’office'), findsOneWidget);
    });

    casM14('aux bornes, le bouton est ABSENT (jamais grisé)', (t) async {
      final m = magasinComplet();
      amorcerExercices(m, DateTime(2026, 10, 30));
      await ouvrir(t, m, 'm12-balance');
      expect(find.descendant(of: find.byKey(const Key('bandeau-exercice-etat')), matching: find.text('Ouvert')), findsOneWidget);
      expect(find.byKey(const Key('bandeau-exercice-suivant')), findsNothing, reason: 'pas d’exercice 2027 en octobre');
    });
  });

  group('(a) compte de résultat : N-1 calculé au même filtre, à côté de N-1 cité', () {
    casM14('exercice 2026 : trois colonnes — N calculé, N-1 calculé, N-1 cité du dépôt — et le bandeau le dit', (t) async {
      final m = magasinComplet();
      await ouvrir(t, m, 'm12-compte-resultat');
      expect(find.text('EXERCICE 2026 (N)'), findsOneWidget);
      expect(find.text('EXERCICE 2025 (N-1)'), findsOneWidget, reason: 'la colonne N-1 CALCULÉE au même filtre');
      expect(find.text('EXERCICE AU 31/12/2025 (N-1)'), findsOneWidget, reason: 'la colonne N-1 CITÉE du dépôt, à côté');
      expect(find.text('NET (1) — calculé — arrêté au 31/12/2025'), findsOneWidget);
      expect(find.textContaining('MÊME filtre que la colonne N'), findsOneWidget);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer le compte de résultat'));
      expect(find.textContaining('Colonne N-1 (calculée, même filtre que N)'), findsWidgets);
      expect(find.textContaining('Colonne N-1 (déposée)'), findsWidgets);
    });
  });
}
