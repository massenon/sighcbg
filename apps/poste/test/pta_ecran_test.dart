import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/shell/choix_exercice.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LE PLAN DE TRAVAIL ANNUEL (lot PTA, Direction de Baguidi, 17/11/2026) à l'écran `m13-plan-annuel` : l'exercice vient du SÉLECTEUR de la barre supérieure (aucune année écrite),
/// le jeu livré ne porte AUCUN plan, le cycle brouillon → soumis → adopté passe par la matrice (adopter = geste réservé, ABSENT sans lui), une action en retard au seuil se dit,
/// et les deux pièces (plan, bilan) sortent au gabarit A4 paysage.
typedef M = Map<String, Object?>;

void poserFormulaire(WidgetTester t, Map<String, Object?> v) {
  final ctl = t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;
  for (final e in v.entries) {
    ctl.poser(e.key, e.value);
  }
}

Future<void> motif(WidgetTester t, String texte, String bouton) async {
  await t.enterText(find.byType(TextField).last, texte);
  await t.pump();
  await t.tap(find.widgetWithText(BoutonSigh, bouton).last);
  await t.pump(const Duration(milliseconds: 400));
}

/// Un plan EN EXÉCUTION de l'exercice [annee], avec une action dont la dernière période cochée finit le 30/09 (en retard au 30/10 au-delà de 15 jours).
void semerPlanEnExecution(dynamic m, int annee) {
  // L'action d'abord : la garde du moteur refuse d'AJOUTER une action à un plan déjà adopté.
  m.collection(ptaCollectionActions).inserer({
    'statut': 'actif',
    'exercice': annee,
    'planVersion': 1,
    'reference': 'PTA-$annee-001',
    'action': 'Former les sages-femmes à la partographie',
    'axe': 'sante_mere_enfant',
    'indicateur': 'Sages-femmes formées',
    'cibleValeur': 6,
    'cibleUnite': 'sages-femmes',
    'realiseValeur': 3,
    'avancementMode': 'calcule',
    'etat': 'en_cours',
    'calendrier': ['$annee-07-01/$annee-09-30'],
    'debut': '$annee-07-01',
    'fin': '$annee-09-30',
    'responsable': 'Surveillance des soins',
    'budgetPrevu': 250000,
  }, prefixe: 'PTA');
  m.collection(ptaCollectionPlans).inserer({
    'id': 'PTA-$annee-V1',
    'statut': 'actif',
    'reference': 'PTA-$annee-V1',
    'exercice': annee,
    'version': 1,
    'etat': 'execution',
    'adoptePar': 'Le Directeur',
    'adopteLe': '$annee-01-15T09:00:00Z',
    'motifAdoption': 'Comité de direction',
  });
}

void main() {
  setUpAll(chargerPolices);
  setUp(() {
    ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf';
    ChoixExercice.reinitialiser();
  });
  tearDown(() {
    ToastsSigh.viderPourTests();
    ChoixExercice.reinitialiser();
  });

  testWidgets('le jeu livré n’a AUCUN plan ; l’exercice vient du sélecteur (défaut : celui du jour), N-1 se choisit et tout se relit', (t) async {
    final m = magasinM14();
    expect(m.collection(ptaCollectionPlans).toutes, isEmpty);
    await ouvrirM14(t, m, 'm13-plan-annuel');
    expect(find.byKey(const Key('selecteur-exercice')), findsOneWidget, reason: 'le PTA est un écran « à année »');
    expect(find.text('Exercice 2026 · ouvert'), findsOneWidget);
    expect(find.text('Plan de travail annuel — exercice 2026'), findsOneWidget);
    expect(find.textContaining('Aucun plan pour l’exercice 2026'), findsOneWidget);
    expect(find.widgetWithText(BoutonSigh, 'Ouvrir le plan de l’exercice 2026'), findsOneWidget);
    // Les référentiels SEMÉS du modèle proposé, marqués « à valider ».
    expect(find.text('Qualité et sécurité des soins · à valider'), findsOneWidget);
    expect(find.text('Fonds propres · à valider'), findsOneWidget);
    await toucherM14(t, find.byKey(const Key('exercice-precedent')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Plan de travail annuel — exercice 2025'), findsOneWidget, reason: 'titres lus de l’exercice CHOISI');
    expect(find.widgetWithText(BoutonSigh, 'Ouvrir le plan de l’exercice 2025'), findsNothing, reason: '2025 est clos : on n’y ouvre pas de plan (commande absente)');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('cycle complet : ouvrir, saisir une action (numéro en série annuelle), soumettre ; « Adopter » ABSENT sans le geste, présent sous la Direction qui adopte', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm13-plan-annuel', role: 'agentadmin');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Ouvrir le plan de l’exercice 2026'));
    expect(m.collection(ptaCollectionPlans).toutes.single['etat'], 'brouillon');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Nouvelle action'));
    poserFormulaire(t, {
      'axe': 'qualite_securite_soins',
      'objectif': 'Réduire les infections associées aux soins',
      'action': 'Audit trimestriel de l’hygiène des mains',
      'indicateur': 'Audits réalisés',
      'cibleValeur': '4',
      'cibleUnite': 'audits',
      'calendrier': ['2026-01-01/2026-03-31', '2026-10-01/2026-12-31'],
      'budgetPrevu': '150000',
      'sourceFinancement': 'fonds_propres',
    });
    await t.tap(find.widgetWithText(BoutonSigh, 'Créer'));
    await t.pump(const Duration(milliseconds: 400));
    final a = m.collection(ptaCollectionActions).toutes.singleWhere((x) => x['exercice'] == 2026);
    expect([a['reference'], a['exercice'], a['planVersion'], a['etat'], a['debut'], a['fin']], ['PTA-2026-001', 2026, 1, 'planifiee', '2026-01-01', '2026-12-31']);
    expect(find.byKey(const Key('pta:barre:PTA-2026-001:T1')), findsOneWidget);
    expect((t.widget<Container>(find.byKey(const Key('pta:barre:PTA-2026-001:T2'))).decoration as BoxDecoration).color, isNot(equals(null)));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Soumettre à l’adoption'));
    expect(m.collection(ptaCollectionPlans).toutes.single['etat'], 'soumis');
    expect(find.widgetWithText(BoutonSigh, 'Adopter le plan'), findsNothing, reason: 'l’agent administratif n’a pas le geste « adopter » : la commande est absente, pas grisée');
    await t.pump(const Duration(seconds: 10));

    await ouvrirM14(t, m, 'm13-plan-annuel', role: 'direction');
    expect(find.widgetWithText(BoutonSigh, 'Adopter le plan'), findsOneWidget);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Adopter le plan'));
    await motif(t, 'Comité de direction du 30/10', 'Adopter');
    final p = m.collection(ptaCollectionPlans).toutes.single;
    expect([p['etat'], p['motifAdoption'], p['adopteRole']], ['adopte', 'Comité de direction du 30/10', 'direction']);
    expect(t.widget<BadgeSigh>(find.byKey(const Key('pta:etat-plan'))).libelle, 'Adopté');
    expect(m.collection('audit').toutes.any((j) => '${j['action']}'.contains('Décision du plan de travail annuel')), isTrue, reason: 'RG-12');
    // Un plan adopté ne se réécrit pas : la garde du moteur refuse une écriture du programme, quelle que soit la voie.
    expect(() => m.collection(ptaCollectionActions).mettreAJour(a['id'], {'cibleValeur': 9}), throwsA(isA<Exception>()));
    m.collection(ptaCollectionActions).mettreAJour(a['id'], {'realiseValeur': 1, 'etat': 'en_cours'});
    expect(m.collection(ptaCollectionActions).parId(a['id'])!['realiseValeur'], 1, reason: 'le suivi reste ouvert');
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('une action en retard au-delà du SEUIL réglé (15 jours d’attente) : pastille, compte, filtre « en retard »', (t) async {
    final m = magasinM14();
    semerPlanEnExecution(m, 2026);
    await ouvrirM14(t, m, 'm13-plan-annuel', role: 'da');
    expect(find.byKey(const Key('pta:retard')), findsOneWidget);
    expect(t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == 'En retard')).valeur, '1');
    expect(t.widget<KpiSigh>(find.byWidgetPredicate((w) => w is KpiSigh && w.libelle == 'Taux d’exécution')).valeur, '0 %');
    final tab = t.widget<TableauSigh>(find.byType(TableauSigh).first);
    final f = tab.filtres.firstWhere((x) => x.nom == 'retard');
    expect(tab.lignes.where((l) => f.correspond!(l, 'oui')).length, 1);
    expect(find.text('30 j'), findsOneWidget, reason: '30/09 → 30/10 : 30 jours de retard');
    // Le seuil relevé à 60 jours (une version datée, paramètre de clinique) : plus de retard.
    m.collection(parCollectionParametres).inserer({
      'id': Parametres.idVersion(ptaCleSeuilRetard, '2026-01-01', 1),
      'statut': 'actif',
      'cle': ptaCleSeuilRetard,
      'famille': 'pta',
      'type': 'entier',
      'valeur': 60,
      'defaut': 15,
      'dateEffet': '2026-01-01',
      'version': 1,
      'auteur': 'test',
    });
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('pta:retard')), findsNothing);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('« Imprimer le plan » et « Imprimer le bilan » : A4 paysage, exercice et version lus du plan, bilan avec réalisé, cible, écart', (t) async {
    final m = magasinM14();
    semerPlanEnExecution(m, 2026);
    await ouvrirM14(t, m, 'm13-plan-annuel', role: 'da');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer le plan'));
    expect(find.text('Exercice 2026 — PTA-2026-V1'), findsWidgets);
    expect(find.text('Objectif spécifique'), findsWidgets);
    expect(find.text('Financement'), findsWidgets);
    expect(t.getSize(find.byKey(const Key('impression:a4')).first).width, greaterThan(t.getSize(find.byKey(const Key('impression:a4')).first).height * 0.9),
        reason: 'feuille en paysage');
    await t.tapAt(const Offset(5, 5));
    await t.pump(const Duration(milliseconds: 400));
    Navigator.of(t.element(find.byType(Scaffold).first)).popUntil((r) => r.isFirst);
    await t.pump(const Duration(milliseconds: 400));
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer le bilan'));
    expect(find.textContaining('bilan provisoire'), findsWidgets, reason: 'plan non clôturé : le bilan le dit');
    expect(find.text('Écart'), findsWidgets);
    expect(find.text('-3 sages-femmes'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('« Reconduire les actions non réalisées » : copie vers l’exercice suivant (plan en brouillon créé), lien d’origine, journalisé, rien en double si on relance', (t) async {
    final m = magasinM14();
    semerPlanEnExecution(m, 2026);
    await ouvrirM14(t, m, 'm13-plan-annuel', role: 'da');
    final bouton = find.byKey(const Key('pta:reconduire'));
    expect(bouton, findsOneWidget);
    await toucherM14(t, bouton);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Reconduire').last);
    final plans = m.collection(ptaCollectionPlans).actives.where((p) => p['exercice'] == 2027).toList();
    expect(plans.single['etat'], 'brouillon', reason: 'plan de 2027 créé en brouillon');
    final copies = m.collection(ptaCollectionActions).actives.where((a) => a['exercice'] == 2027).toList();
    expect(copies.single['reconduiteDe'], 'PTA-2026-001');
    expect(copies.single['reference'], 'PTA-2027-001');
    expect(copies.single['calendrier'], isNull, reason: 'les dates repartent de zéro');
    expect(m.collection(ptaCollectionActions).actives.firstWhere((a) => a['exercice'] == 2026)['etat'], 'en_cours', reason: 'l’origine n’est pas touchée');
    expect(m.collection('audit').toutes.any((j) => '${j['action']}'.contains('Reconduction du plan de travail annuel')), isTrue, reason: 'journalisé (RG-12)');
    await t.pump(const Duration(seconds: 10));
    // Relancer : rien n'est recopié deux fois.
    await toucherM14(t, bouton);
    expect(find.textContaining('déjà reconduites'), findsWidgets);
    expect(m.collection(ptaCollectionActions).actives.where((a) => a['exercice'] == 2027).length, 1);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('les signataires du plan et du bilan se lisent à l’ORGANIGRAMME (poste et titulaire), ou au réglage « signataires du plan » ; aucun intitulé écrit dans le code', (t) async {
    final m = magasinM14();
    semerPlanEnExecution(m, 2026);
    final racine = m.collection('postes').actives.firstWhere((p) => '${p['parentId'] ?? ''}'.isEmpty);
    await ouvrirM14(t, m, 'm13-plan-annuel', role: 'da');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Imprimer le plan'));
    expect(find.text('${racine['poste']}'), findsWidgets, reason: 'le poste qui coiffe l’organigramme signe');
    if ('${racine['titulaire'] ?? ''}'.isNotEmpty) expect(find.text('${racine['titulaire']}'), findsWidgets);
    expect(find.text('La Directrice Administrative'), findsNothing);
    expect(find.text('La Direction'), findsNothing);
    await t.pump(const Duration(seconds: 10));
  });

  testWidgets('régler les référentiels : réservé au geste (« Ajouter » absent sans lui), une fiche ajoutée s’ARRÊTE (plus « à valider »)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'm13-plan-annuel', role: 'agentadmin');
    expect(find.widgetWithText(BoutonSigh, 'Ajouter'), findsNothing);
    await t.pump(const Duration(seconds: 10));
    await ouvrirM14(t, m, 'm13-plan-annuel', role: 'da');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Ajouter').first);
    poserFormulaire(t, {'code': 'hygiene', 'libelle': 'Hygiène hospitalière', 'ordre': '9'});
    await t.tap(find.widgetWithText(BoutonSigh, 'Enregistrer').last);
    await t.pump(const Duration(milliseconds: 400));
    final f = m.collection(ptaCollectionAxes).toutes.firstWhere((x) => x['code'] == 'hygiene');
    expect([f['libelle'], f['aValider'], f['arretePar'] != null], ['Hygiène hospitalière', false, true]);
    expect(find.text('Hygiène hospitalière'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
  });
}
