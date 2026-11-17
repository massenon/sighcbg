import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/planning_rh_poste.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m10/rhb_planning.dart' show honoraireReserve;
import 'package:sigh_poste/modules/m11/pai_commun.dart' show entreesPaie;

import 'aide_polices.dart';
import 'm14_aide.dart';
import 'rhb_aide.dart';

/// PLANNING INDIVIDUEL (Direction, 16/11/2026, §8) : l'onglet « Planning individuel » de la fiche du personnel — le régime EFFECTIF champ par champ (provenance, valeurs
/// d'attente « à valider »), le calendrier de la semaine ou du mois, l'édition du régime individuel (dérogation, remplacement) sous les droits de la MATRICE ; l'honoraire
/// de régime recalculé à l'écran des primes et au bulletin ; « Mon espace » qui lit la même résolution. Agent et documents FICTIFS.
final _lundi = DateTime(2026, 12, 7, 10);

ControleurFormulaire _ctl(WidgetTester t) => t.widget<FormulaireSigh>(find.byType(FormulaireSigh).last).controleur;

/// Un infirmier fictif, ses vacations de décembre 2026 (validées) et un congé validé.
Magasin _magasin({String nom = 'AGENT Planning Fictif'}) {
  final m = magasinRhb();
  m.collection('personnel').inserer(
      {'id': 'EMPPLI', 'statut': 'actif', 'nomComplet': nom, 'matricule': '0', 'fonction': 'infirmier', 'service': 'Soins infirmiers', 'poste': 'Infirmier', 'categorie': 'B'},
      prefixe: 'EMP');
  final p = m.collection('planning');
  for (final (id, date, type) in [('PLI1', '2026-12-03', 'garde'), ('PLI2', '2026-12-07', 'garde_soins'), ('PLI3', '2026-12-09', 'garde_hospi'), ('PLI4', '2026-12-10', 'repos48')]) {
    p.inserer({
      'id': id, 'statut': 'validee', 'date': date, 'type': type, 'employeId': 'EMPPLI', 'employe': nom, 'fonction': 'infirmier', 'service': 'Soins infirmiers',
      'regimeLibelle': 'Infirmiers', 'validationEtat': 'validee',
    }, prefixe: 'PLN');
  }
  m.collection('conges').inserer(
      {'id': 'CGPLI', 'statut': 'actif', 'employeId': 'EMPPLI', 'nature': 'Congé annuel', 'dateDebut': '2026-12-11', 'dateFin': '2026-12-12', 'statutConge': 'valide'},
      prefixe: 'CG');
  return m;
}

PlanningRhPoste _service(Magasin m, DateTime jour) => PlanningRhPoste(m, auteur: () => 'Administrateur', role: 'admin', horloge: () => jour);

Future<void> _ouvrirFiche(WidgetTester t, Magasin m, {String role = 'admin'}) async {
  await ouvrirM14(t, m, 'm10-employe-profil', horloge: _lundi, role: role);
  t.widget<FormulaireSigh>(find.byType(FormulaireSigh).first).controleur.poser('agent', 'EMPPLI');
  await t.pump(const Duration(milliseconds: 300));
  await toucherM14(t, find.text('Planning individuel').last);
}

/// Pose une surcharge d'écrans sur la fiche RBAC du rôle (fusionnée à celle qui existe : une fiche par rôle).
void _surcharge(Magasin m, String role, Map<String, Object?> ecrans) {
  final col = m.collection('rbac');
  final f = col.toutes.where((x) => x['role'] == role && x['statut'] != 'archive').firstOrNull;
  if (f == null) {
    col.inserer({'role': role, 'statut': 'actif', 'droitsEcrans': ecrans}, prefixe: 'RBAC');
  } else {
    col.mettreAJour(f['id'], {'droitsEcrans': {...((f['droitsEcrans'] as Map?) ?? const {}).cast<String, Object?>(), ...ecrans}});
  }
}

String _valeur(WidgetTester t, String champ) => t.widget<Text>(find.byKey(Key('pli:valeur:$champ'))).data ?? '';
String _badge(WidgetTester t, String jour) => t.widget<BadgeSigh>(find.byKey(Key('pli:jour:$jour'))).libelle;

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('fiche du personnel : l’onglet « Planning individuel »', () {
    casM14('le régime de la catégorie, la semaine de l’agent (vacations, congé validé) ; une dérogation PARTIELLE posée à l’écran, ses valeurs d’attente marquées', (t) async {
      final m = _magasin();
      await _ouvrirFiche(t, m);
      expect(find.text('Régime de la catégorie'), findsOneWidget);
      expect(_valeur(t, 'repos'), 'Repos 48h');
      expect(_valeur(t, 'heureDebut'), 'Selon la vacation (référentiel)');
      expect(find.text('Semaine du 07/12/2026 au 13/12/2026'), findsOneWidget);
      expect(_badge(t, '2026-12-07'), 'Garde soins');
      expect(_badge(t, '2026-12-11'), 'Congé', reason: 'le congé validé couvre le jour');
      expect(find.textContaining('08:00 → 18:30'), findsWidgets, reason: 'les horaires du référentiel');

      // Sans aucun champ : refus nommé, rien n'est écrit.
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Déroger'));
      expect(find.text('Dérogation champ par champ'), findsOneWidget);
      await saisir(t, 'motif', 'Aménagement de poste (fictif)');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer la version'));
      expect(find.textContaining('Aucun champ n’est dérogé'), findsOneWidget);
      expect(m.collection('regimesIndividuels').toutes, isEmpty);
      // Horaires et jours seulement, sans document d'origine : la version est écrite, ses deux valeurs sont « à valider ».
      _ctl(t).poser('heureDebut', '07:00');
      _ctl(t).poser('jours', ['lun', 'mar', 'mer', 'jeu', 'ven']);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer la version'));
      final v = m.collection('regimesIndividuels').toutes.single;
      expect([v['employeId'], v['mode'], v['dateEffet'], v['aValider']], ['EMPPLI', 'derogation', '2026-12-07', ['heureDebut', 'jours']]);
      expect((v['champs'] as Map).keys.toSet(), {'heureDebut', 'jours'});
      expect(find.text('Régime individuel enregistré.'), findsOneWidget);
      ToastsSigh.viderPourTests();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Dérogation individuelle'), findsOneWidget);
      expect(_valeur(t, 'heureDebut'), '07:00');
      expect(_valeur(t, 'repos'), 'Repos 48h', reason: 'le repos suit toujours la catégorie');
      expect(find.byKey(const Key('pli:a-valider:heureDebut')), findsOneWidget);
      expect(find.byKey(const Key('pli:a-valider:jours')), findsOneWidget);
      expect(find.byKey(const Key('pli:a-valider:repos')), findsNothing);
      expect(find.textContaining('07:00 → 18:30'), findsWidgets, reason: 'la vacation se lit sous le régime effectif');
      // La vue du mois.
      await toucherM14(t, find.byKey(const Key('pli:vue:mois')));
      expect(find.text('Planning de décembre 2026'), findsOneWidget);
      expect(_badge(t, '2026-12-03'), 'G');
      // Le contrôle de repos et des jours, au poste : le samedi n'est plus un jour travaillé de l'agent.
      final refus = _service(m, _lundi).poserVacation(employeId: 'EMPPLI', date: '2026-12-19', type: 'garde_soins');
      expect(refus['code'], 'JOUR_HORS_REGIME');
    });

    casM14('REMPLACEMENT : l’agent adopte en bloc un autre régime, rien n’est hérité de sa catégorie ; un remplacement sans vacations est refusé en le nommant', (t) async {
      final m = _magasin();
      await _ouvrirFiche(t, m);
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Remplacer le régime'));
      expect(find.text('Remplacement du régime de la catégorie'), findsWidgets);
      await saisir(t, 'motif', 'Affectation à la sécurité (fictif)');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer la version'));
      expect(find.textContaining('Un régime de remplacement remplace TOUT le régime de la catégorie'), findsOneWidget);
      _ctl(t).poser('baseRemplacement', 'Agents de sécurité');
      await saisir(t, 'sourceDocument', 'Note de service fictive n° 1');
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer la version'));
      final v = m.collection('regimesIndividuels').toutes.single;
      expect([v['mode'], v['baseRemplacement'], v['sourceDocument'], v['aValider']], ['remplacement', 'Agents de sécurité', 'Note de service fictive n° 1', isEmpty]);
      ToastsSigh.viderPourTests();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Agents de sécurité'), findsWidgets);
      expect(_valeur(t, 'repos'), 'Repos 24h', reason: 'le repos de 48 h de la catégorie n’est plus hérité');
      expect(_valeur(t, 'vacations'), contains('Garde 24h'));
      expect(find.textContaining('Note de service fictive n° 1'), findsWidgets);
      // L'historique de la fiche : la version, son mode, son document.
      await toucherM14(t, find.widgetWithText(BoutonSigh, 'Historique (1)'));
      expect(find.text('Historique du régime de AGENT Planning Fictif'), findsOneWidget);
      expect(find.text('Remplacement du régime de la catégorie'), findsWidgets);
    });

    casM14('droits de la MATRICE : la Direction lit (montants compris) sans commande d’écriture ; sans les primes, le montant est dit réservé ; sans le planning, l’onglet le dit', (t) async {
      final m = _magasin();
      final r = _service(m, DateTime(2026, 12, 1)).poserRegime(
          employeId: 'EMPPLI',
          dateEffet: '2026-12-01',
          mode: modeDerogationRh,
          champs: {'honoraire': 1500, 'honorairePeriodicite': 'occurrence'},
          motif: 'Honoraire de garde (fictif)',
          sourceDocument: 'Avenant fictif');
      expect(r['ok'], isTrue);
      await _ouvrirFiche(t, m, role: 'direction');
      expect(find.widgetWithText(BoutonSigh, 'Déroger'), findsNothing, reason: 'une commande interdite est ABSENTE');
      expect(find.widgetWithText(BoutonSigh, 'Remplacer le régime'), findsNothing);
      expect(sansEspaces(_valeur(t, 'honoraire')), contains('1500'));
      // L'honoraire du mois recalculé sur le régime effectif : garde soins du 07/12 et garde hospitalisation du 09/12 (vacations du régime), pas la garde du 03/12.
      expect(sansEspaces(kpis(t)['Honoraire de régime (décembre 2026)']), contains('3000'));

      _surcharge(m, 'da', {
        'm10-primes': {'voir': false, 'editer': false, 'annuler': false},
        'm10-planning': {'voir': true, 'editer': false, 'annuler': false},
      });
      await _ouvrirFiche(t, m, role: 'da');
      expect(_valeur(t, 'honoraire'), honoraireReserve);
      expect(kpis(t)['Honoraire de régime (décembre 2026)'], honoraireReserve);
      expect(find.widgetWithText(BoutonSigh, 'Déroger'), findsNothing);

      _surcharge(m, 'da', {'m10-planning': {'voir': false, 'editer': false, 'annuler': false}});
      await _ouvrirFiche(t, m, role: 'da');
      expect(find.text('Le planning de l’agent se lit avec le droit de lire le planning du personnel.'), findsOneWidget);
      expect(find.byKey(const Key('pli:regime')), findsNothing);
    });

    casM14('le SURVEILLANT écrit le planning individuel (geste dédié `rh_planning_individuel`), sans lire aucune rémunération ; retiré à sa fiche de rôle, la commande disparaît', (t) async {
      final m = _magasin();
      await _ouvrirFiche(t, m, role: 'surveillant');
      expect(find.widgetWithText(BoutonSigh, 'Déroger'), findsOneWidget, reason: 'le geste dédié est accordé d’origine au Surveillant');
      expect(find.widgetWithText(BoutonSigh, 'Remplacer le régime'), findsOneWidget);
      // Le geste ne donne aucun autre droit RH : ni le circuit, ni la lecture du salaire.
      final g = DroitsGestes(fiches: m.collection('rbac').actives);
      expect(g.peut('surveillant', gesteRhRegler), isFalse);
      expect(g.peut('surveillant', gesteRhPlanningIndividuel), isTrue);
      // La Direction retire le geste dans la fiche de rôle : la commande est absente.
      final col = m.collection('rbac');
      final f = col.toutes.where((x) => x['role'] == 'surveillant' && x['statut'] != 'archive').firstOrNull;
      if (f == null) {
        col.inserer({'role': 'surveillant', 'statut': 'actif', 'droitsGestes': {gesteRhPlanningIndividuel: false}}, prefixe: 'RBAC');
      } else {
        col.mettreAJour(f['id'], {'droitsGestes': {...((f['droitsGestes'] as Map?) ?? const {}).cast<String, Object?>(), gesteRhPlanningIndividuel: false}});
      }
      await _ouvrirFiche(t, m, role: 'surveillant');
      expect(find.widgetWithText(BoutonSigh, 'Déroger'), findsNothing, reason: 'une commande interdite est ABSENTE');
    });
  });

  group('l’honoraire de régime recalculé sur le régime EFFECTIF (RG-11)', () {
    casM14('l’écran des primes porte la colonne « Honoraire de régime » et le bulletin calculé le même montant', (t) async {
      final m = _magasin();
      _service(m, DateTime(2026, 12, 1)).poserRegime(
          employeId: 'EMPPLI', dateEffet: '2026-12-01', mode: modeDerogationRh, champs: {'honoraire': 1500, 'honorairePeriodicite': 'occurrence'}, motif: 'Sonde (fictif)');
      final paie = paiCalculer(m.collection('personnel').actives.firstWhere((e) => e['id'] == 'EMPPLI'), 2026, 11, entreesPaie(m), DateTime(2026, 12, 15));
      expect(paie.lignesPrimes.where((l) => l.id.startsWith('honoraire_regime')).fold<num>(0, (a, l) => a + l.total), 3000);
      await ouvrirM14(t, m, 'm10-primes', horloge: DateTime(2026, 12, 15, 10));
      expect(find.text('HONORAIRE DE RÉGIME'), findsWidgets, reason: 'la colonne paraît dès qu’un agent perçoit un honoraire de régime');
      expect(texteAffiche(t).contains('agentplanningfictif'), isTrue);
    });
  });

  group('« Mon espace » lit la même résolution', () {
    casM14('la rubrique du planning porte le régime de l’agent aujourd’hui ; le montant de l’honoraire reste réservé à qui lit les primes', (t) async {
      final nom = agentDemonstration('infirmier', nom: donneesNav.matrice.libelle('infirmier')).nom;
      final m = _magasin(nom: nom);
      _service(m, DateTime(2026, 12, 1)).poserRegime(
          employeId: 'EMPPLI', dateEffet: '2026-12-01', mode: modeDerogationRh, champs: {'repos': 'repos24', 'honoraire': 2000}, motif: 'Sonde (fictif)');
      await ouvrirM14(t, m, 'm10-mes', horloge: _lundi, role: 'infirmier');
      await toucherM14(t, find.byKey(const Key('mes:rubrique:planning')));
      expect(find.text('Mon régime de travail aujourd’hui'), findsOneWidget);
      expect(find.text('Dérogation individuelle'), findsOneWidget);
      expect(_valeur(t, 'repos'), 'Repos 24h');
      expect(_valeur(t, 'honoraire'), honoraireReserve, reason: 'l’infirmier ne voit pas l’écran des primes');
      expect(find.byKey(const Key('pli:a-valider:honoraire')), findsOneWidget, reason: 'posé sans document : valeur d’attente');
    });
  });
}
