// LE PLAN DE TRAVAIL ANNUEL (lot PTA, Direction de Baguidi, 17/11/2026 : « RIEN NE DOIT ÊTRE EN DUR ») : exercice sans année écrite, numérotation en série
// annuelle, périodes selon le découpage réglé, avancement saisi ou calculé, retard au seuil, réalisé budgétaire LU au module Budgets, cycle de vie avec adoption
// réservée, révision en nouvelle version, refus nommés, contrôle de la mère, fusion et dépôt depuis un fileul.
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;

M fiche(String role, Map<String, bool> gestes) => {'id': 'RBAC-$role', 'role': role, 'statut': 'actif', 'droitsGestes': gestes};

void main() {
  final etats = ptaSemenceEtats();
  final auj = DateTime(2031, 6, 20, 10);

  group('exercice et périodes : aucune année écrite', () {
    test('les bornes viennent de la fiche d’exercice ; sans fiche, l’année civile, dite non amorcée', () {
      final e = ptaExercice([
        {'annee': 2031, 'debut': '2031-01-01', 'fin': '2031-12-31', 'statut': 'actif'}
      ], 2031);
      expect([e.annee, iso(e.debut), iso(e.fin), e.amorce], [2031, '2031-01-01', '2031-12-31', true]);
      final n = ptaExercice(const [], 2044);
      expect([iso(n.debut), iso(n.fin), n.amorce], ['2044-01-01', '2044-12-31', false]);
    });

    test('découpage trimestre, mois, semestre ; un exercice qui ne commence pas en janvier est découpé depuis son début', () {
      final e = ptaExercice(const [], 2031);
      expect(ptaPeriodes(e, 'trimestre').map((p) => p.libelle), ['T1', 'T2', 'T3', 'T4']);
      expect(ptaPeriodes(e, 'trimestre')[1].libelleLong, 'T2 (avr. – juin)');
      expect(ptaPeriodes(e, 'semestre').map((p) => '${p.debutIso}/${p.finIso}'), ['2031-01-01/2031-06-30', '2031-07-01/2031-12-31']);
      expect(ptaPeriodes(e, 'mois').length, 12);
      expect(ptaPeriodes(e, 'mois').first.libelle, 'Janv.');
      final decale = ptaExercice([
        {'annee': 2032, 'debut': '2031-07-01', 'fin': '2032-06-30'}
      ], 2032);
      final t = ptaPeriodes(decale, 'trimestre');
      expect(t.map((p) => p.debutIso), ['2031-07-01', '2031-10-01', '2032-01-01', '2032-04-01']);
      expect(t.last.finIso, '2032-06-30');
    });

    test('le découpage et le seuil illisibles retombent sur le défaut du REGISTRE des paramètres (jamais une valeur écrite ici)', () {
      expect(ptaDecoupageDe('decennie'), definitionDeParametre(ptaCleDecoupage)!.defaut);
      expect(ptaSeuilDe(-3), definitionDeParametre(ptaCleSeuilRetard)!.defaut);
      expect(ptaSeuilDe('12'), 12);
      expect(definitionDeParametre(ptaCleDecoupage)!.source, contains('à valider'));
      expect(definitionDeParametre(ptaCleSeuilRetard)!.source, contains('à valider'));
      expect(gesteDuReglage(ptaCleDecoupage), gestePtaRegler, reason: 'réglable depuis n’importe quel poste, sous le geste');
      expect(gesteDuReglage(ptaCleSeuilRetard), gestePtaRegler);
    });

    test('la date de réglage d’un exercice : le jour ramené dans ses bornes', () {
      final e = ptaExercice(const [], 2031);
      expect(iso(ptaDateReglage(e, DateTime(2031, 6, 20))), '2031-06-20');
      expect(iso(ptaDateReglage(e, DateTime(2033, 2, 1))), '2031-12-31');
      expect(iso(ptaDateReglage(e, DateTime(2029, 2, 1))), '2031-01-01');
    });

    test('ni le moteur ni l’écran du PTA n’écrivent une année', () {
      for (final f in ['lib/src/administration/pta.dart', '../../apps/poste/lib/modules/m13/pta_vues.dart']) {
        final lignes = File(f).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//'));
        final annees = [for (final l in lignes) ...RegExp(r'(?<![\d/.-])20\d\d(?!\d)').allMatches(l).map((m) => m.group(0))];
        expect(annees, isEmpty, reason: '$f : une année en dur');
      }
    });
  });

  group('référentiels semés « à valider »', () {
    test('le MODÈLE PROPOSÉ par la Direction : huit axes, cinq états, cinq sources de financement, tous « proposition à valider »', () {
      expect(ptaSemenceAxes().map((a) => a['libelle']), [
        'Qualité et sécurité des soins',
        'Santé de la mère et de l’enfant (CPN, accouchements, PF, vaccination)',
        'Disponibilité des médicaments et consommables',
        'Ressources humaines et formation',
        'Infrastructures, équipements et maintenance',
        'Gestion financière et recouvrement (assurances, créances)',
        'Système d’information et numérique (SIGH, statistiques, rapports)',
        'Gouvernance, partenariats et communication',
      ]);
      expect(ptaSemenceFinancements().map((a) => a['libelle']), ['Fonds propres', 'Assurances', 'Partenaire', 'État', 'Autre']);
      for (final f in [...ptaSemenceAxes(), ...ptaSemenceEtats(), ...ptaSemenceFinancements()]) {
        expect([f['aValider'], f['source'], f['mention']], [true, 'Modèle proposé le 16/11/2026, à valider', 'Proposition à valider par la Direction'], reason: '${f['code']}');
      }
      expect(definitionDeParametre(ptaCleDecoupage)!.defaut, 'trimestre');
      expect(definitionDeParametre(ptaCleSeuilRetard)!.defaut, 15);
      expect(gesteReserve(gestePtaAdopter)!.rolesDefaut, ['direction', 'da']);
    });

    test('axes et états semés, marqués, ordonnés ; la collection vide retombe sur la semence', () {
      expect(ptaSemenceAxes().every((a) => a['aValider'] == true && '${a['source']}'.contains('à valider')), isTrue);
      expect(etats.map((e) => e['libelle']), ['Planifiée', 'En cours', 'Réalisée', 'Reportée', 'Abandonnée']);
      expect(ptaEtatsEnForce(const []).length, 5);
      expect(ptaEtatParDefaut(const []), 'planifiee');
      final regles = [
        {'id': 'E1', 'code': 'fait', 'libelle': 'Fait', 'ordre': 2, 'realise': true, 'termine': true},
        {'id': 'E2', 'code': 'afaire', 'libelle': 'À faire', 'ordre': 1, 'parDefaut': true},
        {'id': 'E3', 'code': 'vieux', 'libelle': 'Vieux', 'ordre': 0, 'statut': 'archive'},
      ];
      expect(ptaEtatsEnForce(regles).map((e) => e['code']), ['afaire', 'fait'], reason: 'la clinique a réglé ses états : la semence ne s’y mêle pas');
      expect(ptaLibelleEtat('vieux', regles), 'Vieux', reason: 'un état archivé garde son libellé pour les actions qui le portent');
      expect(ptaLibelleEtat('inconnu', regles), 'inconnu', reason: 'un code inconnu se dit, il ne disparaît pas');
    });

    test('contrôle d’une fiche : geste réservé, code immuable et unique, ton connu', () {
      final g = DroitsGestes(fiches: const []);
      expect(ptaControlerReferentiel(ptaCollectionAxes, {'code': 'achats', 'libelle': 'Achats'}, ptaSemenceAxes(), role: 'medecin', gestes: g)!.code, 'REGLAGE_RESERVE');
      final ok = DroitsGestes(fiches: [fiche('medecin', {gestePtaRegler: true})]);
      expect(ptaControlerReferentiel(ptaCollectionAxes, {'code': 'achats', 'libelle': 'Achats'}, ptaSemenceAxes(), role: 'medecin', gestes: ok), isNull,
          reason: 'une fiche de rôle accorde le geste');
      expect(ptaControlerReferentiel(ptaCollectionAxes, {'code': 'systeme_information', 'libelle': 'X'}, ptaSemenceAxes(), role: 'medecin', gestes: ok)!.code, 'CODE_EXISTANT');
      expect(ptaControlerReferentiel(ptaCollectionAxes, {'code': 'Finance 2', 'libelle': 'X'}, ptaSemenceAxes(), role: 'medecin', gestes: ok)!.code, 'CODE_INVALIDE');
      final f = ptaSemenceAxes().first;
      expect(ptaControlerReferentiel(ptaCollectionAxes, {...f, 'code': 'autre'}, ptaSemenceAxes(), avant: f, role: 'medecin', gestes: ok)!.code, 'CODE_IMMUABLE');
      expect(ptaControlerReferentiel(ptaCollectionAxes, {...f, 'libelle': 'Numérique'}, ptaSemenceAxes(), avant: f, role: 'medecin', gestes: ok), isNull);
      expect(ptaControlerReferentiel(ptaCollectionEtats, {'code': 'gele', 'libelle': 'Gelé', 'ton': 'fuchsia'}, etats, role: 'medecin', gestes: ok)!.code, 'TON_INCONNU');
    });
  });

  group('action : numérotation, avancement, retard, budget', () {
    test('référence en série ANNUELLE construite depuis l’exercice, lue sur les fiches existantes (archivées comprises)', () {
      expect(ptaReferenceSuivante(2031, const []), 'PTA-2031-001');
      final l = [
        {'exercice': 2031, 'reference': 'PTA-2031-004', 'statut': 'archive'},
        {'exercice': 2030, 'reference': 'PTA-2030-009'},
      ];
      expect(ptaReferenceSuivante(2031, l), 'PTA-2031-005');
      expect(ptaReferenceSuivante(2032, l), 'PTA-2032-001');
    });

    test('le PRÉFIXE de la numérotation est un réglage ; le changer ne redonne jamais un rang déjà attribué dans l’exercice', () {
      expect(definitionDeParametre(ptaClePrefixe)!.defaut, 'PTA');
      expect(gesteDuReglage(ptaClePrefixe), gestePtaRegler);
      final l = [
        {'exercice': 2031, 'reference': 'PTA-2031-007'}
      ];
      expect(ptaReferenceSuivante(2031, l, prefixe: ptaPrefixeDe('plan')), 'PLAN-2031-008');
      expect(ptaPrefixeDe('  '), 'PTA', reason: 'illisible : le défaut du registre');
      expect(ptaPrefixeDe('pt a'), 'PTA');
    });

    test('CALENDRIER : périodes cochées écrites par leurs bornes ; le retard se compte depuis la fin de la DERNIÈRE période cochée', () {
      final e = ptaExercice(const [], 2031);
      final t = ptaPeriodes(e, 'trimestre');
      final cal = ptaCalendrierDe([t[0], t[2]]);
      expect(cal, ['2031-01-01/2031-03-31', '2031-07-01/2031-09-30']);
      expect(ptaBornesCalendrier(cal), ('2031-01-01', '2031-09-30'));
      final a = {'etat': 'en_cours', 'calendrier': cal};
      expect([for (final p in t) ptaCouvre(a, p)], [true, false, true, false], reason: 'T2 n’est pas coché : la frise le montre vide');
      expect(ptaLibellePeriode(a, t), 'T1 – T3');
      expect(ptaJoursRetard(a, etats, DateTime(2031, 10, 15), 15), isNull);
      expect(ptaJoursRetard(a, etats, DateTime(2031, 10, 16), 15), 16);
      final mois = ptaPeriodes(e, 'mois');
      expect([for (final p in mois) ptaCouvre(a, p)].where((x) => x).length, 6, reason: 'un découpage changé relit le calendrier sans le réécrire');
    });

    test('écart réalisé − cible (le bilan), non calculable sans l’un des deux', () {
      expect(ptaEcart({'cibleValeur': 40, 'realiseValeur': 30}), -10);
      expect(ptaEcart({'cibleValeur': 40}), isNull);
    });

    test('avancement CALCULÉ (réalisé ÷ cible) ou SAISI, et l’écran dit lequel ; non calculable n’est pas zéro', () {
      final t = ptaTaux({'avancementMode': 'calcule', 'cibleValeur': 40, 'realiseValeur': 30, 'cibleUnite': 'agents formés'});
      expect([t.valeur, t.mode], [75, 'calcule']);
      expect(t.explication, contains('réalisé ÷ cible'));
      expect(ptaTaux({'avancementMode': 'calcule', 'realiseValeur': 3}).valeur, isNull);
      expect(ptaTaux({'avancementMode': 'calcule', 'realiseValeur': 3}).texte, 'Non calculable');
      expect(ptaTaux({'avancementMode': 'calcule', 'cibleValeur': 10}).explication, contains('aucune valeur réalisée'));
      final s = ptaTaux({'avancementMode': 'saisi', 'tauxAvancement': 60, 'cibleValeur': 10, 'realiseValeur': 1});
      expect([s.valeur, s.mode], [60, 'saisi'], reason: 'saisi : la cible ne recalcule rien');
      expect(ptaModeAvancement({'tauxAvancement': 20}), 'saisi', reason: 'fiche d’avant le mode : un pourcentage saisi reste saisi');
    });

    test('retard : état non terminé ET période échue depuis PLUS que le seuil réglé', () {
      final a = {'etat': 'en_cours', 'debut': '2031-01-01', 'fin': '2031-03-31'};
      expect(ptaJoursRetard(a, etats, DateTime(2031, 4, 30), 30), isNull, reason: '30 jours pile : dans la tolérance');
      expect(ptaJoursRetard(a, etats, DateTime(2031, 5, 1), 30), 31);
      expect(ptaJoursRetard({...a, 'etat': 'realisee'}, etats, auj, 30), isNull);
      expect(ptaJoursRetard({...a, 'etat': 'abandonnee'}, etats, auj, 30), isNull, reason: 'abandonnée = terminée, plus suivie');
      expect(ptaJoursRetard({...a, 'etat': 'reportee'}, etats, auj, 0), isNotNull);
      expect(ptaJoursRetard(a, etats, DateTime(2031, 4, 2), 0), 2);
    });

    test('le RÉALISÉ budgétaire est LU au module Budgets (débits de classe 6 du centre, exercice de la ligne), jamais ressaisi', () {
      final budgets = [
        {'id': 'BUD1', 'reference': 'BG-2031-001', 'exercice': '2031', 'centreCout': 'laboratoire', 'prevu': 500000},
        {'id': 'BUD2', 'reference': 'BG-2031-002', 'exercice': '2031', 'centreCout': 'pharmacie', 'statut': 'archive'},
      ];
      final ecritures = [
        {'date': '2031-02-10', 'compte': '604100', 'centreCout': 'laboratoire', 'debit': 120000, 'credit': 0, 'statut': 'valide'},
        {'date': '2031-03-10', 'compte': '604100', 'centreCout': 'laboratoire', 'debit': 30000, 'credit': 0, 'statut': 'valide'},
        {'date': '2030-03-10', 'compte': '604100', 'centreCout': 'laboratoire', 'debit': 99999, 'credit': 0, 'statut': 'valide'},
        {'date': '2031-03-10', 'compte': '706000', 'centreCout': 'laboratoire', 'debit': 5000, 'credit': 0, 'statut': 'valide'},
      ];
      final attendu = cpbRealise(cpaEcrituresExercice(ecritures, 2031), 'laboratoire');
      expect(ptaRealiseBudget(ptaBudgetLie({'budgetReference': 'BG-2031-001'}, budgets), ecritures), attendu);
      expect(attendu, 150000);
      expect(ptaBudgetLie({'budgetReference': 'BG-2031-002'}, budgets), isNull, reason: 'une ligne archivée n’est plus liée');
      final s = ptaSynthese([
        {'etat': 'realisee', 'budgetPrevu': 400000, 'budgetReference': 'BG-2031-001', 'fin': '2031-03-31'},
        {'etat': 'en_cours', 'budgetPrevu': 100000, 'budgetReference': 'BG-2031-001', 'fin': '2031-03-31'},
        {'etat': 'abandonnee', 'budgetReference': 'BG-2031-002', 'fin': '2031-03-31'},
        {'etat': 'planifiee', 'fin': '2031-12-31'},
      ], etats, auj: auj, seuilJours: 30, budgets: budgets, ecritures: ecritures);
      expect([s.programmees, s.realisees, s.abandonnees, s.enRetard, s.taux], [4, 1, 1, 1, 33]);
      expect([s.budgetPrevu, s.budgetRealise, s.lignesBudgetLiees, s.liensIntrouvables], [500000, 150000, 1, 1], reason: 'une ligne liée deux fois compte une fois');
      final k = ptaKpis(s);
      expect(k.map((x) => x.libelle), ['Actions programmées', 'Réalisées', 'En retard', 'Taux d’exécution', 'Budget prévu', 'Budget réalisé']);
      expect(ptaKpis(ptaSynthese(const [], etats, auj: auj, seuilJours: 30))[3].valeur, 'Non calculable');
      expect(ptaKpis(ptaSynthese(const [], etats, auj: auj, seuilJours: 30))[5].valeur, 'Aucune ligne liée');
    });
  });

  group('cycle de vie : brouillon → soumis → adopté → en exécution → clôturé', () {
    final da = DroitsGestes(fiches: const []);
    List<M> actions(int v, {String etat = 'en_cours'}) => [
          {'id': 'A$v-1', 'exercice': 2031, 'planVersion': v, 'reference': 'PTA-2031-001', 'action': 'Former', 'etat': etat, 'realiseValeur': 3, 'fin': '2031-03-31'},
        ];

    test('création : version 1 en brouillon, refus nommé si l’exercice a déjà son plan ou s’il est clos', () {
      final c = ptaCreerPlan(annee: 2031, plans: const [], acteur: 'A', maintenant: auj);
      expect([c.creation!['reference'], c.creation!['etat'], c.creation!['version']], ['PTA-2031-V1', 'brouillon', 1]);
      expect(ptaCreerPlan(annee: 2031, plans: [c.creation!], acteur: 'A', maintenant: auj).refus!.code, 'PLAN_EXISTE');
      expect(ptaCreerPlan(annee: 2031, plans: const [], acteur: 'A', maintenant: auj, etatExercice: 'clos').refus!.code, 'EXERCICE_CLOS');
    });

    test('soumettre exige une action ; adopter est RÉSERVÉ, exige un motif, jamais par celui qui a soumis', () {
      final plan = {'id': 'P1', 'exercice': 2031, 'version': 1, 'etat': 'brouillon'};
      expect(ptaSoumettre(plan, const [], acteur: 'Rédacteur', maintenant: auj).refus!.code, 'PLAN_VIDE');
      final s = ptaSoumettre(plan, actions(1), acteur: 'Rédacteur', maintenant: auj);
      final soumis = {...plan, ...s.ecritures.single.patch};
      expect(soumis['etat'], 'soumis');
      PtaVerdict decider(String role, String acteur, {String motif = 'Comité de direction', String decision = ptaDecisionAdopter, M? p}) => ptaDecider(
          decision: decision, annee: 2031, version: 1, role: role, acteur: acteur, motif: motif, gestes: da, plans: [p ?? soumis], actions: actions(1), maintenant: auj);
      expect(decider('comptable', 'X').refus!.code, 'ADOPTION_RESERVEE', reason: 'le comptable n’a pas le geste d’origine');
      expect(decider('admin', 'X').refus!.code, 'ADOPTION_RESERVEE', reason: 'l’administrateur système non plus : origine Direction et DAF, à valider');
      expect(decider('direction', 'Directeur', motif: ' ').refus!.code, 'MOTIF_OBLIGATOIRE');
      expect(decider('direction', 'Rédacteur').refus!.code, 'AUTO_ADOPTION');
      expect(decider('direction', 'Directeur', p: plan).refus!.code, 'PAS_SOUMIS', reason: 'jamais d’adoption d’un brouillon');
      final a = decider('direction', 'Directeur');
      expect(a.ok, isTrue);
      final p = a.ecritures.single.patch;
      expect([p['etat'], p['adoptePar'], p['adopteRole'], p['motifAdoption'], p['adopteLe']], ['adopte', 'Directeur', 'direction', 'Comité de direction', valInstant(auj)]);
      final adopte = {...soumis, ...p};
      expect(decider('da', 'DAF', p: adopte).sansEffet, isTrue, reason: 'rejouable : la première adoption fait foi');
      final renvoi = decider('da', 'DAF', decision: ptaDecisionRenvoyer, motif: 'Cibles à chiffrer');
      expect([renvoi.ecritures.single.patch['etat'], renvoi.ecritures.single.patch['motifRenvoi']], ['brouillon', 'Cibles à chiffrer']);
      expect(DroitsGestes(fiches: [fiche('comptable', {gestePtaAdopter: true})]).peut('comptable', gestePtaAdopter), isTrue, reason: 'une fiche accorde');
      expect(DroitsGestes(fiches: [fiche('da', {gestePtaAdopter: false})]).peut('da', gestePtaAdopter), isFalse, reason: 'une fiche retire');
    });

    test('exécution puis clôture avec bilan ; plus rien ne s’écrit ensuite', () {
      final adopte = {'id': 'P1', 'exercice': 2031, 'version': 1, 'etat': 'adopte', 'adoptePar': 'Directeur'};
      expect(ptaMettreEnExecution({...adopte, 'etat': 'soumis'}, acteur: 'A', maintenant: auj).refus!.code, 'PAS_ADOPTE');
      final ex = {...adopte, ...ptaMettreEnExecution(adopte, acteur: 'A', maintenant: auj).ecritures.single.patch};
      expect(ex['etat'], 'execution');
      final syn = ptaSynthese(actions(1), etats, auj: auj, seuilJours: 30);
      final c = ptaDecider(
          decision: ptaDecisionCloturer, annee: 2031, version: 1, role: 'da', acteur: 'DAF', motif: 'Bilan : objectifs atteints aux deux tiers', gestes: da, plans: [ex], actions: actions(1), maintenant: auj, synthese: syn);
      final p = c.ecritures.single.patch;
      expect(p['etat'], 'cloture');
      expect((p['bilan'] as Map)['texte'], 'Bilan : objectifs atteints aux deux tiers');
      expect((p['bilan'] as Map)['programmees'], 1);
      final clos = {...ex, ...p};
      expect(ptaGardeAction('modifier', {...actions(1).single, 'realiseValeur': 9}, actions(1).single, [clos]), contains('clôturé'));
      expect(ptaGardePlan('modifier', {...clos, 'bilan': 'autre'}, clos), contains('ne se modifie plus'));
    });

    test('un plan adopté ne se réécrit pas : programme figé, suivi ouvert, ni ajout ni retrait', () {
      final adopte = [{'id': 'P1', 'exercice': 2031, 'version': 1, 'etat': 'execution'}];
      final a = actions(1).single;
      expect(ptaGardeAction('modifier', {...a, 'realiseValeur': 8, 'etat': 'realisee', 'observations': 'ok'}, a, adopte), isNull);
      expect(ptaGardeAction('modifier', {...a, 'action': 'Former tout le monde'}, a, adopte), contains('« action »'));
      expect(ptaGardeAction('modifier', {...a, 'fin': '2031-06-30'}, a, adopte), contains('« fin »'));
      expect(ptaGardeAction('inserer', {...a, 'id': 'nouv'}, null, adopte), contains('ne s’y ajoute pas'));
      expect(ptaGardeAction('archiver', a, a, adopte), contains('abandonnée'));
      expect(ptaGardeAction('modifier', {...a, 'action': 'X'}, a, [{...adopte.single, 'etat': 'brouillon'}]), isNull, reason: 'un brouillon se corrige');
      expect(ptaGardePlan('archiver', adopte.single, adopte.single), contains('ne s’archive pas'));
      expect(ptaGardePlan('modifier', {...adopte.single, 'etat': 'brouillon'}, adopte.single), contains('ne revient pas en arrière'));
      expect(ptaGardePlan('modifier', {'etat': 'brouillon'}, {'etat': 'soumis'}), isNull, reason: 'retirer sa soumission est permis');
    });

    test('RÉVISION : nouvelle version datée en brouillon, l’ancienne reste en vigueur puis devient « remplacée » à l’adoption, le suivi est repris', () {
      final v1 = {'id': 'P1', 'exercice': 2031, 'version': 1, 'etat': 'execution'};
      final a1 = actions(1);
      expect(ptaReviser(annee: 2031, plans: [{...v1, 'etat': 'brouillon'}], actions: a1, acteur: 'A', motif: 'm', maintenant: auj).refus!.code, 'PAS_EN_VIGUEUR');
      expect(ptaReviser(annee: 2031, plans: [v1], actions: a1, acteur: 'A', motif: '', maintenant: auj).refus!.code, 'MOTIF_OBLIGATOIRE');
      final r = ptaReviser(annee: 2031, plans: [v1], actions: a1, acteur: 'Rédacteur', motif: 'Budget révisé en juin', maintenant: auj);
      expect([r.plan!['version'], r.plan!['etat'], r.plan!['reviseDe'], r.plan!['reference']], [2, 'brouillon', 1, 'PTA-2031-V2']);
      expect(r.actions.single['planVersion'], 2);
      expect(r.actions.single['reference'], 'PTA-2031-001', reason: 'une action révisée garde sa référence');
      expect(r.actions.single.containsKey('id'), isFalse);
      final v2 = {...r.plan!, 'id': 'P2', 'etat': 'soumis', 'soumisPar': 'Rédacteur'};
      expect(ptaReviser(annee: 2031, plans: [v1, v2], actions: a1, acteur: 'A', motif: 'm', maintenant: auj).refus!.code, 'REVISION_OUVERTE');
      // La v1 a avancé pendant la révision : l'adoption de la v2 reprend ce suivi.
      final a2 = [
        {...r.actions.single, 'id': 'A2-1', 'realiseValeur': 3}
      ];
      final a1Avance = [
        {...a1.single, 'realiseValeur': 7, 'etat': 'realisee'}
      ];
      final ad = ptaDecider(
          decision: ptaDecisionAdopter, annee: 2031, version: 2, role: 'direction', acteur: 'Directeur', motif: 'Révision adoptée', gestes: da, plans: [v1, v2], actions: [...a1Avance, ...a2], maintenant: auj);
      final par = {for (final e in ad.ecritures) '${e.id}': e.patch};
      expect(par['P2']!['etat'], 'adopte');
      expect([par['P1']!['etat'], par['P1']!['remplaceParVersion']], ['remplace', 2]);
      expect(par['A2-1'], {'etat': 'realisee', 'realiseValeur': 7});
      final apres = [
        {...v1, ...par['P1']!},
        {...v2, ...par['P2']!}
      ];
      expect(ptaPlanAdopteDe(apres, 2031)!['version'], 2);
      expect(ptaPlansExercice(apres, 2031).length, 2, reason: 'RG-14 : l’ancienne version reste, consultable');
    });

    test('RECONDUCTION : les actions ni réalisées ni abandonnées passent à l’exercice suivant (brouillon créé), avec leur lien d’origine, sans doublon ni retour en arrière', () {
      final v1 = {'id': 'P1', 'exercice': 2031, 'version': 1, 'etat': 'cloture'};
      M a(String ref, String etat, {String? id}) =>
          {'id': id ?? 'A$ref', 'statut': 'actif', 'exercice': 2031, 'planVersion': 1, 'reference': 'PTA-2031-$ref', 'action': 'Action $ref', 'etat': etat, 'realiseValeur': 4, 'debut': '2031-02-01', 'fin': '2031-03-31', 'calendrier': ['2031-01-01/2031-03-31'], 'budgetReference': 'BUD-1'};
      final src = [a('001', 'realisee'), a('002', 'abandonnee'), a('003', 'en_cours'), a('004', 'reportee')];
      final r = ptaReconduire(annee: 2031, plans: [v1], actions: src, etats: etats, acteur: 'Rédacteur', maintenant: auj);
      expect(r.ok, isTrue);
      expect(r.planACreer!['etat'], 'brouillon', reason: 'le plan suivant naît en brouillon s’il n’existe pas');
      expect([r.planACreer!['exercice'], r.planACreer!['version']], [2032, 1]);
      expect(r.actions.map((x) => x['reconduiteDe']), ['PTA-2031-003', 'PTA-2031-004'], reason: 'ni les réalisées ni les abandonnées : lues au référentiel des états');
      final c0 = r.actions.first;
      expect([c0['exercice'], c0['planVersion'], c0['reference'], c0['etat'], c0['reconduiteDeExercice'], c0['reconduitePar']], [2032, 1, 'PTA-2032-001', 'planifiee', 2031, 'Rédacteur']);
      for (final k in ['realiseValeur', 'debut', 'fin', 'calendrier', 'budgetReference']) {
        expect(c0.containsKey(k), isFalse, reason: '$k repart de zéro');
      }
      expect(c0['action'], 'Action 003', reason: 'le programme est reporté');
      expect(r.actions[1]['reference'], 'PTA-2032-002', reason: 'série annuelle de l’exercice suivant');
      // Relancer : rien n’est recopié deux fois (même si une copie a été archivée depuis).
      final appliquees = [for (final (i, x) in r.actions.indexed) {...x, 'id': 'N$i', if (i == 1) 'statut': 'archive'}];
      final p2 = {...r.planACreer!, 'id': 'P2032'};
      final encore = ptaReconduire(annee: 2031, plans: [v1, p2], actions: [...src, ...appliquees], etats: etats, acteur: 'A', maintenant: auj);
      expect(encore.sansEffet, isTrue);
      expect(encore.refus!.code, 'DEJA_RECONDUIT');
      // Une nouvelle action non terminée est reconduite seule ; les autres ne sont pas doublées.
      final plus = ptaReconduire(annee: 2031, plans: [v1, p2], actions: [...src, ...appliquees, a('005', 'planifiee')], etats: etats, acteur: 'A', maintenant: auj);
      expect(plus.actions.map((x) => x['reconduiteDe']), ['PTA-2031-005']);
      expect(plus.planACreer, isNull);
      expect(plus.actions.single['reference'], 'PTA-2032-003', reason: 'ne redonne jamais un rang déjà attribué');
      // L'origine n'est jamais touchée ; le sens est unique (l'exercice 2032 ne se reconduit pas vers 2031).
      expect(src.first['etat'], 'realisee');
      expect(ptaReconduire(annee: 2032, plans: [v1, p2], actions: [...appliquees], etats: etats, acteur: 'A', maintenant: auj).actions.every((x) => x['exercice'] == 2033), isTrue);
    });

    test('RECONDUCTION : refus nommés (aucun plan source, plan suivant soumis ou adopté, exercice suivant clos, rien à reconduire)', () {
      final v1 = {'id': 'P1', 'exercice': 2031, 'version': 1, 'etat': 'execution'};
      M a(String etat) => {'id': 'A1', 'statut': 'actif', 'exercice': 2031, 'planVersion': 1, 'reference': 'PTA-2031-001', 'etat': etat};
      expect(ptaReconduire(annee: 2031, plans: const [], actions: [a('en_cours')], etats: etats, acteur: 'A', maintenant: auj).refus!.code, 'PAS_DE_PLAN_SOURCE');
      expect(ptaReconduire(annee: 2031, plans: [v1], actions: [a('realisee')], etats: etats, acteur: 'A', maintenant: auj).refus!.code, 'RIEN_A_RECONDUIRE');
      expect(ptaReconduire(annee: 2031, plans: [v1], actions: [a('en_cours')], etats: etats, acteur: 'A', maintenant: auj, etatExerciceSuivant: 'clos').refus!.code, 'EXERCICE_CLOS');
      for (final e in ['soumis', 'adopte', 'execution']) {
        final r = ptaReconduire(annee: 2031, plans: [v1, {'id': 'P2', 'exercice': 2032, 'version': 1, 'etat': e}], actions: [a('en_cours')], etats: etats, acteur: 'A', maintenant: auj);
        expect(r.refus!.code, 'PLAN_SUIVANT_FIGE', reason: e);
      }
      final ok = ptaReconduire(annee: 2031, plans: [v1, {'id': 'P2', 'exercice': 2032, 'version': 1, 'etat': 'brouillon'}], actions: [a('en_cours')], etats: etats, acteur: 'A', maintenant: auj);
      expect(ok.ok && ok.planACreer == null && ok.version == 1 && ok.actions.length == 1, isTrue, reason: 'un brouillon existant reçoit les copies');
    });

    test('SIGNATAIRES : lus à l’organigramme (réglage de postes, sinon le poste qui coiffe) ; jamais un nom écrit dans le code', () {
      final postes = [
        {'id': 'P1', 'statut': 'actif', 'poste': 'Directeur Général', 'code': 'DG', 'titulaire': 'DUPONT Marie'},
        {'id': 'P2', 'statut': 'actif', 'parentId': 'P1', 'poste': 'Responsable Comptable', 'code': 'RC', 'titulaire': ''},
        {'id': 'P3', 'statut': 'archive', 'poste': 'Ancien poste', 'code': 'AP', 'titulaire': 'X'},
      ];
      var s = ptaSignataires(postes: postes);
      expect([s.single.intitule, s.single.titulaire], ['Directeur Général', 'DUPONT Marie'], reason: 'sans réglage : le poste qui coiffe l’organigramme');
      s = ptaSignataires(postes: postes, reglage: 'rc ; Directeur Général');
      expect([for (final x in s) (x.intitule, x.titulaire)], [('Responsable Comptable', null), ('Directeur Général', 'DUPONT Marie')], reason: 'ordre du réglage, code ou intitulé ; sans titulaire : ligne sans nom');
      s = ptaSignataires(postes: postes, reglage: 'Poste inconnu');
      expect([s.single.intitule, s.single.titulaire], ['Poste inconnu', null], reason: 'un poste absent de l’organigramme garde son intitulé, sans nom');
      expect(ptaSignataires(postes: postes, reglage: 'AP').single.titulaire, isNull, reason: 'un poste archivé ne signe pas');
      expect(ptaSignataires(postes: const []).single.titulaire, isNull);
      expect(ptaSignataires(postes: const []).single.intitule, contains('à désigner'));
      expect(gesteDuReglage(ptaCleSignataires), gestePtaRegler);
      expect(definitionDeParametre(ptaCleSignataires)!.defaut, '');
    });

    test('deux postes hors ligne qui créent la même version : le même en-tête l’emporte partout', () {
      final a = {'id': 'F1-P', 'exercice': 2031, 'version': 1, 'etat': 'brouillon', 'creeLe': '2031-01-02T08:00:00Z'};
      final b = {'id': 'F2-P', 'exercice': 2031, 'version': 1, 'etat': 'brouillon', 'creeLe': '2031-01-02T07:00:00Z'};
      expect(ptaPlanCourant([a, b], 2031)!['id'], 'F2-P');
      expect(ptaPlanCourant([b, a], 2031)!['id'], 'F2-P');
      expect(ptaPlanCourant([b, {...a, 'etat': 'soumis'}], 2031)!['id'], 'F1-P', reason: 'le plus avancé dans le cycle');
    });
  });

  group('mère, fusion, dépôt', () {
    test('la MÈRE refait le contrôle d’un poste : états et champs réservés, pas de recul, exécution sur adoption détenue', () {
      expect(refusPlanTravail('creer', {'etat': 'brouillon'}), isNull);
      expect(refusPlanTravail('creer', {'etat': 'adopte'})!.code, 'adoption_requise');
      expect(refusPlanTravail('modifier', {'etat': 'adopte'}, etatActuel: 'soumis')!.code, 'adoption_reservee');
      expect(refusPlanTravail('modifier', {'etat': 'cloture'}, etatActuel: 'execution')!.code, 'adoption_reservee');
      expect(refusPlanTravail('modifier', {'adoptePar': 'Moi'}, etatActuel: 'soumis')!.code, 'champ_reserve');
      expect(refusPlanTravail('modifier', {'etat': 'brouillon'}, etatActuel: 'adopte')!.code, 'etat_regressif');
      expect(refusPlanTravail('modifier', {'etat': 'brouillon'}, etatActuel: 'soumis'), isNull);
      expect(refusPlanTravail('modifier', {'etat': 'execution'}, etatActuel: 'soumis')!.code, 'adoption_requise');
      expect(refusPlanTravail('modifier', {'etat': 'execution'}, etatActuel: 'adopte'), isNull);
      final plan = {'etat': 'execution'};
      expect(refusActionPta('modifier', {'realiseValeur': 4}, actuelle: {'realiseValeur': 3}, plan: plan), isNull);
      expect(refusActionPta('modifier', {'cibleValeur': 4}, actuelle: {'cibleValeur': 3}, plan: plan)!.code, 'plan_adopte');
      expect(refusActionPta('creer', {'action': 'x'}, plan: plan)!.code, 'plan_adopte');
      expect(refusActionPta('modifier', {'realiseValeur': 4}, plan: {'etat': 'cloture'})!.code, 'plan_arrete');
    });

    test('fusion : une adoption du journal n’est pas défaite ; un état réservé inventé sur un fileul cède ; un retrait de soumission se garde', () {
      expect(fusionnerPlanTravail({'etat': 'soumis'}, {'etat': 'soumis'}, {'etat': 'adopte', 'adoptePar': 'D'})['etat'], 'adopte');
      final f = fusionnerPlanTravail({'etat': 'adopte', 'adoptePar': 'Moi'}, {'etat': 'adopte', 'adoptePar': 'Moi'}, {'etat': 'soumis'}, posteFileul: true);
      expect([f['etat'], f.containsKey('adoptePar')], ['soumis', false]);
      expect(fusionnerPlanTravail({'etat': 'brouillon'}, {'etat': 'brouillon'}, {'etat': 'soumis'})['etat'], 'brouillon');
    });

    test('un fileul DÉPOSE l’adoption ; la mère l’applique sous le rôle de l’auteur, à la date du geste ; rejouable sans effet double', () {
      final plans = [
        {'id': 'F1-PTA-2031-V1', 'exercice': 2031, 'version': 1, 'etat': 'soumis', 'soumisPar': 'Rédacteur'}
      ];
      final actions = [
        {'id': 'A', 'exercice': 2031, 'planVersion': 1, 'reference': 'PTA-2031-001', 'action': 'Former'}
      ];
      final g = DroitsGestes(fiches: const []);
      final refuse = ptaDeposer(
          decision: ptaDecisionAdopter, annee: 2031, version: 1, role: 'caissier', acteur: 'C', poste: 'F1', motif: 'm', maintenant: auj, gestes: g, plans: plans, actions: actions, depots: const [], nouvelId: () => 'D0');
      expect(refuse.refus!.code, 'ADOPTION_RESERVEE', reason: 'refus nommé dès le poste, rien de déposé');
      final d = ptaDeposer(
          decision: ptaDecisionAdopter, annee: 2031, version: 1, role: 'direction', acteur: 'Directeur', poste: 'F1', motif: 'Comité', maintenant: auj, gestes: g, plans: plans, actions: actions, depots: const [], nouvelId: () => 'D1');
      expect([d.fiche!['genre'], d.fiche!['cible'], d.fiche!['etat']], [valGenrePta, '2031/V1', valDepotDeposee]);
      final double = ptaDeposer(
          decision: ptaDecisionAdopter, annee: 2031, version: 1, role: 'direction', acteur: 'Directeur', poste: 'F1', motif: 'Comité', maintenant: auj, gestes: g, plans: plans, actions: actions, depots: [d.fiche!], nouvelId: () => 'D2');
      expect(double.dejaDepose, isTrue);
      // La mère (une heure plus tard) : la matrice de la mère retire le geste à la Direction → refus nommé, rien n'est écrit.
      final plusTard = auj.add(const Duration(hours: 1));
      final retire = ptaAppliquerDepot(d.fiche!, gestes: DroitsGestes(fiches: [fiche('direction', {gestePtaAdopter: false})]), plans: plans, actions: actions, maintenant: plusTard);
      expect([retire!.etat, retire.code], [valDepotRefusee, 'ADOPTION_RESERVEE']);
      final a = ptaAppliquerDepot(d.fiche!, gestes: g, plans: plans, actions: actions, maintenant: plusTard)!;
      expect(a.etat, valDepotAppliquee);
      expect(a.ecritures.single.patch['adopteLe'], valInstant(auj), reason: 'la date du GESTE, pas celle de l’application');
      final apres = [
        {...plans.single, ...a.ecritures.single.patch}
      ];
      expect(ptaAppliquerDepot(d.fiche!, gestes: g, plans: apres, actions: actions, maintenant: plusTard)!.etat, valDepotSansEffet);
      expect(ptaAppliquerDepot({...d.fiche!, 'etat': valDepotAppliquee}, gestes: g, plans: plans, actions: actions, maintenant: plusTard), isNull);
      final dec = DecisionEnAttente(genre: genreDecisionValidation, id: 'D1', libelle: 'x', par: 'Directeur', role: 'direction', depuis: auj, sousGenre: valGenrePta, famille: ptaFamilleDepot(ptaDecisionAdopter));
      expect(destinatairesAlerteDecision(dec, gesteCircuit: gesteValiderAchats, gestePrix: gesteDeciderPrix), contains('geste:$gestePtaAdopter'));
    });

    test('alertes : une ligne par action en retard des seuls plans EN VIGUEUR', () {
      final plans = [
        {'id': 'P1', 'exercice': 2031, 'version': 1, 'etat': 'remplace'},
        {'id': 'P2', 'exercice': 2031, 'version': 2, 'etat': 'execution'},
        {'id': 'P3', 'exercice': 2030, 'version': 1, 'etat': 'cloture'},
      ];
      final actions = [
        {'id': 'A1', 'exercice': 2031, 'planVersion': 1, 'etat': 'en_cours', 'fin': '2031-01-31'},
        {'id': 'A2', 'exercice': 2031, 'planVersion': 2, 'etat': 'en_cours', 'fin': '2031-01-31'},
        {'id': 'A3', 'exercice': 2031, 'planVersion': 2, 'etat': 'realisee', 'fin': '2031-01-31'},
        {'id': 'A4', 'exercice': 2030, 'planVersion': 1, 'etat': 'en_cours', 'fin': '2030-01-31'},
      ];
      final r = ptaActionsEnRetard(plans: plans, actions: actions, etats: etats, auj: auj, seuil: (_) => 30);
      expect(r.map((x) => x.action['id']), ['A2']);
      expect(ptaActionsEnRetard(plans: plans, actions: actions, etats: etats, auj: DateTime(2031, 3, 1), seuil: (_) => 30), isEmpty);
    });
  });
}
