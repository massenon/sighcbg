// PLANNING INDIVIDUEL (Direction, 16/11/2026, §8) : la résolution du régime EFFECTIF d'un agent à une date (dérogation partielle, remplacement, versions datées,
// valeurs d'attente champ par champ), la pose d'une version (refus nommés), le contrôle des jours, le calendrier de l'agent et l'honoraire de régime recalculé
// sur le régime effectif — à l'écran des primes comme au bulletin de paie (RG-11). Données de test fictives.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

void main() {
  // Deux régimes de la catégorie, tels que le magasin les porte (le second a un honoraire par occurrence et une valeur d'attente écrite sur la fiche).
  final regimes = <F>[
    {'libelle': 'Infirmiers', 'fonctions': ['infirmier'], 'vacations': ['garde_soins', 'garde_hospi'], 'repos': 'repos48', 'cycle': 3, 'source': 'Planning de travail des infirmiers'},
    {
      'libelle': 'Agents de sécurité', 'fonctions': ['securite'], 'vacations': ['garde', 'soiree'], 'repos': 'repos24', 'cycle': 3, 'honoraire': 1000,
      'honorairePeriodicite': 'occurrence', 'source': 'Planning des agents de sécurité', 'aValider': ['honoraire'],
    },
  ];
  F agent(String fonction) => {'id': 'AG-TEST', 'nomComplet': 'AGENT Fictif', 'fonction': fonction};
  RegimeRhResolu resoudre(String fonction, List<F> versions, String date) =>
      regimeRhALaDate(regimesActifs: regimes, versions: versions, fonction: fonction, date: date);

  group('la résolution du régime effectif', () {
    test('sans version : le régime de la catégorie, chaque champ de provenance « catégorie », les valeurs d’attente de la fiche reprises', () {
      final r = resoudre('securite', const [], '2026-11-20');
      expect(r.mode, 'categorie');
      expect(r.individuel, isFalse);
      expect(r.vacations, ['garde', 'soiree']);
      expect(r.honoraire, 1000);
      expect(r.provenances['honoraire'], provenanceCategorieRh);
      expect(r.provenances.containsKey('heureDebut'), isFalse, reason: 'la catégorie n’écrit pas d’horaire');
      expect(r.aValider, ['honoraire']);
      expect(r.jours, isNull);
    });

    test('dérogation PARTIELLE : seuls les horaires et les jours changent, le reste suit la catégorie', () {
      final v = {'id': 'RGI-1', 'employeId': 'AG-TEST', 'dateEffet': '2026-11-18', 'champs': {'heureDebut': '07:00', 'heureFin': '15:00', 'jours': ['lun', 'mar', 'mer', 'jeu', 'ven']}};
      final r = resoudre('infirmier', [v], '2026-11-20');
      expect(r.mode, 'derogation');
      expect(r.individuel, isTrue);
      expect(r.derogations, ['heureDebut', 'heureFin', 'jours']);
      expect([r.heureDebut, r.heureFin], ['07:00', '15:00']);
      expect(r.vacations, ['garde_soins', 'garde_hospi'], reason: 'les vacations suivent la catégorie');
      expect(r.repos, 'repos48');
      expect(r.provenances['heureDebut'], provenanceIndividuelleRh);
      expect(r.provenances['repos'], provenanceCategorieRh);
      expect(r.libelle, 'Infirmiers', reason: 'une dérogation garde le libellé de la catégorie');
      // Les vecteurs de la maquette lisent `toJson` : il n'est pas étendu.
      expect(r.toJson().containsKey('heureDebut'), isFalse);
      expect(r.toJsonComplet()['jours'], ['lun', 'mar', 'mer', 'jeu', 'ven']);
    });

    test('REMPLACEMENT par un autre régime : rien n’est hérité de la catégorie, les champs de la version complètent le régime adopté', () {
      final v = {
        'id': 'RGI-2', 'employeId': 'AG-TEST', 'dateEffet': '2026-11-18', 'mode': 'remplacement', 'baseRemplacement': 'Agents de sécurité',
        'champs': {'honoraire': 1500}, 'aValider': ['honoraire'],
      };
      final r = resoudre('infirmier', [v], '2026-11-20');
      expect(r.mode, 'remplacement');
      expect(r.individuel, isTrue);
      expect(r.categorie, 'Infirmiers', reason: 'la catégorie de l’agent reste connue');
      expect(r.libelle, 'Agents de sécurité');
      expect(r.vacations, ['garde', 'soiree']);
      expect(r.repos, 'repos24');
      expect(r.honoraire, 1500);
      expect(r.provenances['vacations'], provenanceRemplacementRh);
      expect(r.provenances['honoraire'], provenanceIndividuelleRh);
      expect(r.aValider, ['honoraire']);
    });

    test('REMPLACEMENT composé champ par champ : sans régime adopté, un champ non posé ne vaut RIEN (pas la catégorie)', () {
      final v = {
        'id': 'RGI-3', 'employeId': 'AG-TEST', 'dateEffet': '2026-11-18', 'mode': 'remplacement',
        'champs': {'libelle': 'Horaire de jour adapté', 'vacations': ['permanence'], 'heureDebut': '09:00', 'heureFin': '16:00', 'dureeHeures': 7},
      };
      final r = resoudre('infirmier', [v], '2026-11-20');
      expect(r.libelle, 'Horaire de jour adapté');
      expect(r.vacations, ['permanence']);
      expect(r.repos, isNull, reason: 'le repos de 48 h de la catégorie n’est pas hérité');
      expect(r.cycle, isNull);
      expect(r.dureeHeures, 7);
      expect(r.source, isNull);
    });

    test('VERSION DATÉE : avant la date d’effet, la catégorie ; après, la version ; le retour à la catégorie clôt la dérogation sans rien effacer', () {
      final versions = [
        {'id': 'RGI-4', 'employeId': 'AG-TEST', 'dateEffet': '2026-11-10', 'champs': {'repos': 'repos24'}},
        {'id': 'RGI-5', 'employeId': 'AG-TEST', 'dateEffet': '2026-12-01', 'retourCategorie': true, 'champs': <String, Object?>{}},
      ];
      expect(resoudre('infirmier', versions, '2026-11-09').repos, 'repos48');
      final nov = resoudre('infirmier', versions, '2026-11-15');
      expect([nov.repos, nov.versionId, nov.individuel], ['repos24', 'RGI-4', true]);
      final dec = resoudre('infirmier', versions, '2026-12-02');
      expect([dec.repos, dec.versionId, dec.individuel, dec.mode], ['repos48', 'RGI-5', false, 'categorie']);
    });
  });

  group('la pose d’une version (refus nommés)', () {
    ({RefusRh? refus, Map<String, Object?>? fiche}) poser(String mode, Map<String, Object?> champs,
            {String role = 'admin', List<F> versions = const [], String? base, String? doc, List<String>? aValider, String date = '2026-11-20'}) =>
        validerRegimeIndividuelRh(
            role: role, agentExiste: true, dateEffet: date, motif: 'Aménagement de poste', mode: mode, champs: champs, versions: versions, regimesActifs: regimes,
            aujourdhui: '2026-11-16', baseRemplacement: base, sourceDocument: doc, aValider: aValider);

    test('horaires seuls : acceptés (la maquette refusait « aucune dérogation » faute de champ classique)', () {
      final r = poser('derogation', {'heureDebut': '07:00', 'heureFin': '15:00'});
      expect(r.refus, isNull);
      expect(r.fiche!['champs'], {'heureDebut': '07:00', 'heureFin': '15:00'});
    });

    test('valeurs d’attente : sans document, tous les champs posés sont « à valider » ; avec un document, seuls ceux que l’on coche', () {
      expect(poser('derogation', {'repos': 'repos24', 'cycle': 4}).fiche!['aValider'], ['repos', 'cycle']);
      expect(poser('derogation', {'repos': 'repos24', 'cycle': 4}, doc: 'Avenant n° 3 au contrat').fiche!['aValider'], isEmpty);
      expect(poser('derogation', {'repos': 'repos24', 'cycle': 4}, doc: 'Avenant n° 3', aValider: ['cycle']).fiche!['aValider'], ['cycle']);
      final hors = poser('derogation', {'repos': 'repos24'}, aValider: ['honoraire']);
      expect(hors.refus!.code, 'A_VALIDER_HORS_VERSION');
    });

    test('refus nommés : heure illisible, durée hors bornes, jour inconnu, remplacement sans vacations, régime adopté introuvable, rôle sans le geste', () {
      expect(poser('derogation', {'heureDebut': '7h'}).refus!.code, 'CHAMP_INVALIDE');
      expect(poser('derogation', {'dureeHeures': 30}).refus!.extra['champ'], 'dureeHeures');
      expect(poser('derogation', {'jours': ['lundi']}).refus!.extra['champ'], 'jours');
      expect(poser('remplacement', {'heureDebut': '08:00'}).refus!.code, 'REMPLACEMENT_INCOMPLET');
      expect(poser('remplacement', const {}, base: 'Régime inexistant').refus!.code, 'REGIME_INTROUVABLE');
      expect(poser('remplacement', const {}, base: 'Agents de sécurité').refus, isNull);
      expect(poser('derogation', {'repos': 'repos24'}, role: 'caissier').refus!.code, 'DEROGATION_RESERVEE');
      expect(poser('derogation', const {}).refus!.code, 'AUCUNE_DEROGATION');
    });

    test('les contrôles de date de la maquette valent aussi pour un remplacement : jamais rétroactif, jamais avant la dernière version', () {
      expect(poser('remplacement', const {}, base: 'Agents de sécurité', date: '2026-11-01').refus!.code, 'DATE_PASSEE');
      final v = [{'id': 'RGI-9', 'employeId': 'AG-TEST', 'dateEffet': '2026-12-01', 'champs': {'repos': 'repos24'}}];
      expect(poser('remplacement', const {}, base: 'Agents de sécurité', versions: v).refus!.code, 'VERSION_ANTERIEURE');
    });
  });

  group('les incompatibilités appliquées au régime EFFECTIF', () {
    final a = agent('infirmier');
    test('le repos de 48 h de la catégorie devient 24 h par dérogation : la garde du surlendemain passe', () {
      final planning = <F>[{'id': 'PLN-1', 'employeId': 'AG-TEST', 'date': '2026-11-20', 'type': 'garde_hospi'}];
      final cat = resoudre('infirmier', const [], '2026-11-22');
      expect(controlerVacationRh(agent: a, planningActif: planning, regime: cat, date: '2026-11-22', type: 'garde_hospi')!.code, 'INCOMPATIBILITE_REPOS');
      final derog = resoudre('infirmier', [
        {'id': 'RGI-1', 'employeId': 'AG-TEST', 'dateEffet': '2026-11-01', 'champs': {'repos': 'repos24'}}
      ], '2026-11-22');
      expect(controlerVacationRh(agent: a, planningActif: planning, regime: derog, date: '2026-11-22', type: 'garde_hospi'), isNull);
      expect(controlerVacationRh(agent: a, planningActif: planning, regime: derog, date: '2026-11-21', type: 'garde_hospi')!.code, 'INCOMPATIBILITE_REPOS',
          reason: 'la garde de 24 h et son repos de 24 h restent');
    });

    test('des jours écrits refusent une vacation travaillée un autre jour ; un repos ou un congé ce jour-là passent', () {
      final r = resoudre('infirmier', [
        {'id': 'RGI-1', 'employeId': 'AG-TEST', 'dateEffet': '2026-11-01', 'champs': {'jours': ['lun', 'mar', 'mer', 'jeu', 'ven']}}
      ], '2026-11-21');
      // Le 21/11/2026 est un samedi.
      final refus = controlerVacationRh(agent: a, planningActif: const [], regime: r, date: '2026-11-21', type: 'garde_soins');
      expect(refus!.code, 'JOUR_HORS_REGIME');
      expect(refus.motif, contains('samedi'));
      expect(controlerVacationRh(agent: a, planningActif: const [], regime: r, date: '2026-11-21', type: 'repos24'), isNull);
      expect(controlerVacationRh(agent: a, planningActif: const [], regime: r, date: '2026-11-20', type: 'garde_soins'), isNull);
    });
  });

  group('horaires et calendrier', () {
    test('les horaires d’une vacation : ceux du régime s’il en écrit, sinon ceux du type (référentiel)', () {
      final cat = resoudre('infirmier', const [], '2026-11-20');
      final h1 = horairesVacationRh(cat, 'garde_soins');
      expect([h1.debut, h1.fin, h1.duree, h1.provenance], ['08:00', '18:30', 10.5, 'referentiel']);
      final ind = resoudre('infirmier', [
        {'id': 'RGI-1', 'employeId': 'AG-TEST', 'dateEffet': '2026-11-01', 'champs': {'heureDebut': '07:30', 'dureeHeures': 9}}
      ], '2026-11-20');
      final h2 = horairesVacationRh(ind, 'garde_soins');
      expect([h2.debut, h2.fin, h2.duree, h2.provenance], ['07:30', '18:30', 9, 'regime']);
      expect(horairesVacationRh(ind, 'repos48').duree, 0);
    });

    test('la vue de la semaine va du lundi au dimanche, celle du mois du premier au dernier jour', () {
      expect(bornesVuePlanningRh('semaine', DateTime(2026, 11, 19)), (du: '2026-11-16', au: '2026-11-22'));
      expect(bornesVuePlanningRh('mois', DateTime(2026, 2, 10)), (du: '2026-02-01', au: '2026-02-28'));
    });

    test('le calendrier porte vacations, congé VALIDÉ et régime du jour ; un congé à valider ne couvre rien', () {
      final cal = calendrierAgentRh(
        vacations: [{'id': 'PLN-1', 'employeId': 'AG-TEST', 'date': '2026-11-16', 'type': 'garde_soins'}],
        conges: [
          {'id': 'CG-1', 'employeId': 'AG-TEST', 'dateDebut': '2026-11-18', 'dateFin': '2026-11-19', 'statutConge': 'valide'},
          {'id': 'CG-2', 'employeId': 'AG-TEST', 'dateDebut': '2026-11-21', 'dateFin': '2026-11-21', 'statutConge': 'en_attente'},
        ],
        regimeDe: (d) => resoudre('infirmier', const [], d),
        du: '2026-11-16',
        au: '2026-11-22',
      );
      expect(cal, hasLength(7));
      expect(cal[0].vacation!['id'], 'PLN-1');
      expect(cal[0].horaires!.debut, '08:00');
      expect([for (final j in cal) j.conge?['id']], [null, null, 'CG-1', 'CG-1', null, null, null]);
    });
  });

  group('l’honoraire de régime, recalculé sur le régime EFFECTIF (RG-11)', () {
    final planning = <F>[
      {'id': 'PLN-1', 'employeId': 'AG-TEST', 'date': '2026-11-03', 'type': 'garde'},
      {'id': 'PLN-2', 'employeId': 'AG-TEST', 'date': '2026-11-10', 'type': 'soiree'},
      {'id': 'PLN-3', 'employeId': 'AG-TEST', 'date': '2026-11-17', 'type': 'garde', 'validationEtat': 'a_valider'},
      {'id': 'PLN-4', 'employeId': 'AG-TEST', 'date': '2026-11-24', 'type': 'garde'},
      {'id': 'PLN-5', 'employeId': 'AG-TEST', 'date': '2026-11-25', 'type': 'repos24'},
      {'id': 'PLN-6', 'employeId': 'AUTRE', 'date': '2026-11-03', 'type': 'garde'},
    ];

    test('par occurrence : chaque vacation VALIDÉE du régime, au montant du régime en vigueur à SA date (un relèvement en cours de mois ne remonte pas)', () {
      final versions = [
        {'id': 'RGI-1', 'employeId': 'AG-TEST', 'dateEffet': '2026-11-15', 'champs': {'honoraire': 1500}}
      ];
      final h = honoraireRegimeMoisRh(vacations: planning, employeId: 'AG-TEST', annee: 2026, mois: 11, regimeDe: (d) => resoudre('securite', versions, d));
      // 03/11 et 10/11 à 1 000 (catégorie), 24/11 à 1 500 (dérogation) ; le 17/11 n'est pas validé, le repos n'ouvre rien.
      expect([h.occurrences, h.parOccurrence, h.mensuel, h.montant], [3, 3500, 0, 3500]);
      expect(h.aValider, isTrue, reason: 'l’honoraire de la catégorie est une valeur d’attente');
    });

    test('mensuel : une seule fois, au montant du régime de la DERNIÈRE vacation qui l’ouvre ; sans régime à honoraire, rien', () {
      final versions = [
        {'id': 'RGI-1', 'employeId': 'AG-TEST', 'dateEffet': '2026-11-01', 'champs': {'honoraire': 4000, 'honorairePeriodicite': 'mensuelle'}, 'aValider': <String>[]},
      ];
      final h = honoraireRegimeMoisRh(vacations: planning, employeId: 'AG-TEST', annee: 2026, mois: 11, regimeDe: (d) => resoudre('securite', versions, d));
      expect([h.montant, h.mensuel, h.occurrences, h.aValider], [4000, 4000, 0, false]);
      final sans = honoraireRegimeMoisRh(vacations: planning, employeId: 'AG-TEST', annee: 2026, mois: 11, regimeDe: (d) => resoudre('infirmier', const [], d));
      expect(sans.montant, 0);
    });

    test('un REMPLACEMENT change l’honoraire : l’infirmier passé au régime des agents de sécurité le perçoit sur ses gardes', () {
      final versions = [
        {'id': 'RGI-1', 'employeId': 'AG-TEST', 'dateEffet': '2026-11-01', 'mode': 'remplacement', 'baseRemplacement': 'Agents de sécurité', 'champs': <String, Object?>{}}
      ];
      final h = honoraireRegimeMoisRh(vacations: planning, employeId: 'AG-TEST', annee: 2026, mois: 11, regimeDe: (d) => resoudre('infirmier', versions, d));
      expect(h.montant, 3000);
    });

    test('l’écran des primes et le bulletin de paie portent le même honoraire (une seule résolution)', () {
      final personnel = <F>[
        {'id': 'AG-TEST', 'matricule': '901', 'nomComplet': 'AGENT Fictif', 'fonction': 'securite', 'service': 'Direction', 'salaireBase': 100000, 'dateEmbauche': '2026-01-01'}
      ];
      final versions = <F>[
        {'id': 'RGI-1', 'employeId': 'AG-TEST', 'dateEffet': '2026-11-15', 'champs': {'honoraire': 1500}}
      ];
      final primes = rhbPrimesAcquises(
          personnelActif: personnel,
          planningActif: planning,
          grille: const [],
          historique: const [],
          annee: 2026,
          mois: 11,
          honoraireRegimeDe: (e) => honoraireRegimeMoisRh(
              vacations: planning, employeId: e['id'], annee: 2026, mois: 11, regimeDe: (d) => regimeRhALaDate(regimesActifs: regimes, versions: versions, fonction: '${e['fonction']}', date: d)).montant);
      final ligne = primes.singleWhere((x) => x.id == 'AG-TEST');
      expect(ligne.honoraireRegime, 3500);
      final calc = paiCalculer(personnel.single, 2026, 10,
          PaiEntrees(planning: planning, regimesTravail: regimes, regimesIndividuels: versions), DateTime(2026, 11, 30));
      final hon = calc.lignesPrimes.where((l) => l.id.startsWith('honoraire_regime')).toList();
      expect(hon.fold<num>(0, (a, l) => a + l.total), 3500);
      expect([for (final l in hon) '${l.unitaire}×${l.nombre}'], ['1000×2', '1500×1'], reason: 'une ligne par montant, sans moyenne');
      // Sans régimes individuels passés au moteur : la forme de la maquette, aucun honoraire.
      final maquette = paiCalculer(personnel.single, 2026, 10, PaiEntrees(planning: planning), DateTime(2026, 11, 30));
      expect(maquette.lignesPrimes.where((l) => l.id.startsWith('honoraire_regime')), isEmpty);
      // Primes NS 132 fermées : l'honoraire de régime (prime d'incinération de la note) suit la bascule.
      final ferme = paiCalculer(personnel.single, 2026, 10,
          PaiEntrees(planning: planning, regimesTravail: regimes, regimesIndividuels: versions, primesNs132: false), DateTime(2026, 11, 30));
      expect(ferme.lignesPrimes, isEmpty);
    });
  });
}
