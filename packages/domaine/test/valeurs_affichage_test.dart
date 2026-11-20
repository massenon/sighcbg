// LOT « VALEURS EN DUR » DU 18/11/2026, familles G, B et H : plus aucun libellé comparé pour décider, plus aucun chiffre de démonstration, plus de tranche d'âge écrite en double.
// On prouve, pour chaque site converti : (1) la valeur d'attente est le comportement d'AVANT ; (2) un changement de RÉGLAGE ou de DONNÉE change le comportement, sans toucher au code.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> version(String cle, Object? valeur, String effet, {int v = 1}) {
  final d = definitionDeParametre(cle)!;
  return Parametre(cle: cle, famille: d.famille, type: d.type, valeur: valeur, defaut: d.defaut, dateEffet: effet, version: v, auteur: 'Test', motif: 'essai', creeLe: '2026-11-18T08:00:00.000').toJson();
}

void brancher(List<Map<String, Object?>> fiches) => ListesReference.brancher(() => fiches, horloge: () => DateTime(2026, 11, 18));

void main() {
  tearDown(ListesReference.debrancher);

  group('les entrées codées « code=Libellé|ton »', () {
    test('lecture : code, libellé, ton ; une entrée sans « = » est son propre libellé', () {
      final e = EntreeReference.lire('consultation=Consultation|info');
      expect([e.code, e.libelle, e.ton], ['consultation', 'Consultation', 'info']);
      final n = EntreeReference.lire('seul');
      expect([n.code, n.libelle, n.ton], ['seul', 'seul', '']);
      expect(EntreeReference.lire('x=Un libellé').ton, '');
    });
    test('un code inconnu reste lisible (jamais un blanc) et sans ton', () {
      expect(ListesReference.libelleDe('listes.m10.naturesPrestationPersonnel', 'inconnu'), 'inconnu');
      expect(ListesReference.tonDe('listes.m10.naturesPrestationPersonnel', 'inconnu'), '');
    });
  });

  group('G — la nature d\'une prestation au personnel est un CODE, son libellé et son ton un réglage', () {
    List<Map<String, Object?>> lignes() => rhcPrestations(
          patients: [
            {'id': 'P1', 'personnelId': 'A1', 'nom': 'X', 'prenom': 'Y', 'code': 'CBG/1/26', 'fonctionAgent': 'f'}
          ],
          consultations: [
            {'id': 'C1', 'patientId': 'P1', 'date': '2026-11-01', 'type': 'Consultation', 'tarif': 3000}
          ],
          analyses: [
            {'id': 'L1', 'patientId': 'P1', 'date': '2026-11-02', 'analyse': 'NFS', 'montant': 2000}
          ],
          admissions: [
            {'id': 'H1', 'patientId': 'P1', 'dateEntree': '2026-11-03', 'service': 'Médecine', 'lit': 'L1', 'montant': 10000}
          ],
        );

    test('valeur d\'attente : les trois libellés et les trois tons d\'avant', () {
      final l = lignes();
      expect({for (final x in l) x['natureCode']: x['nature']}, {'consultation': 'Consultation', 'analyse': 'Analyse', 'hospitalisation': 'Hospitalisation'});
      expect([for (final c in ['consultation', 'analyse', 'hospitalisation']) ListesReference.tonDe(rhcCleNaturesPrestation, c)], ['info', 'navy', 'attention']);
    });
    test('renommer un libellé et recolorer une nature ne change AUCUN code ni aucun décompte', () {
      brancher([version(rhcCleNaturesPrestation, 'consultation=Consultation externe|succes; analyse=Examen|danger; hospitalisation=Séjour|navy', '2026-11-01')]);
      final l = lignes();
      expect({for (final x in l) x['natureCode']: x['nature']}, {'consultation': 'Consultation externe', 'analyse': 'Examen', 'hospitalisation': 'Séjour'});
      expect(l.where((x) => x['natureCode'] == natureAssuranceConsultation), hasLength(1));
      expect(ListesReference.tonDe(rhcCleNaturesPrestation, 'analyse'), 'danger');
    });
    test('la ligne de l\'espace agent porte le code, plus un libellé', () {
      final r = assuranceDeLAgent(
          agentId: 'A1',
          patients: [
            {'id': 'P1', 'personnelId': 'A1'}
          ],
          consultations: [
            {'id': 'C1', 'patientId': 'P1', 'date': '2026-11-01', 'tarif': 3000}
          ],
          demandesAnalyses: const [],
          admissions: const []);
      expect(r.lignes.single.nature, natureAssuranceConsultation);
    });
  });

  group('G — l\'urgence d\'un rendez-vous ou d\'une sortie d\'ambulance est un marquage RÉGLÉ ou la donnée', () {
    test('rendez-vous : valeur d\'attente = « Urgence » seul', () {
      expect(agEstUrgent({'type': 'Urgence'}), isTrue);
      expect(agEstUrgent({'type': 'Consultation'}), isFalse);
      expect(agEstUrgent({'type': 'Urgence prioritaire'}), isFalse, reason: 'comme avant : l\'égalité exacte');
    });
    test('un autre type marqué urgent par réglage devient rouge sans toucher au code', () {
      brancher([version('listes.m2.typesRendezvousUrgents', 'Urgence; Contrôle', '2026-11-01')]);
      expect(agEstUrgent({'type': 'Contrôle'}), isTrue);
    });
    test('la fiche qui DIT son urgence l\'emporte sur le libellé', () {
      expect(agEstUrgent({'type': 'Urgence', 'urgent': false}), isFalse);
      expect(agEstUrgent({'type': 'Consultation', 'urgent': true}), isTrue);
    });
    test('ambulance : les deux motifs « Urgence … » d\'avant, et rien d\'autre', () {
      expect(admEstUrgente({'motif': 'Urgence médicale'}), isTrue);
      expect(admEstUrgente({'motif': 'Urgence obstétricale'}), isTrue);
      expect(admEstUrgente({'motif': 'Évacuation sanitaire'}), isFalse);
      brancher([version('listes.m13.motifsInterventionUrgents', 'Évacuation sanitaire', '2026-11-01')]);
      expect(admEstUrgente({'motif': 'Évacuation sanitaire'}), isTrue);
      expect(admEstUrgente({'motif': 'Urgence médicale'}), isFalse);
    });
  });

  group('G — la source d\'un relevé de surveillance est un code', () {
    List<Map<String, Object?>> releves() => hosRelevesDe('P1',
        constantes: [
          {'patientId': 'P1', 'dateHeure': '2026-11-01T08:00:00', 'temperature': 37}
        ],
        admissions: [
          {'id': 'A1', 'patientId': 'P1'}
        ],
        releves: [
          {'admissionId': 'A1', 'date': '2026-11-02', 'heure': '09:00', 'temperature': 38}
        ]);
    test('valeur d\'attente : Accueil / Hospitalisation, tons info / neutre', () {
      final r = releves();
      expect([for (final x in r) x['origineCode']], [hosOrigineAccueil, hosOrigineHospitalisation]);
      expect([for (final x in r) x['origine']], ['Accueil', 'Hospitalisation']);
      expect(ListesReference.tonDe(hosCleOriginesReleve, hosOrigineAccueil), 'info');
    });
    test('renommer la source change le libellé, jamais le code', () {
      brancher([version(hosCleOriginesReleve, 'accueil=Triage|attention; hospitalisation=Au lit|neutre', '2026-11-01')]);
      final r = releves();
      expect([for (final x in r) x['origine']], ['Triage', 'Au lit']);
      expect([for (final x in r) x['origineCode']], [hosOrigineAccueil, hosOrigineHospitalisation]);
    });
  });

  group('G — la portée de l\'imagerie vient de la MATRICE des fonctions, pas d\'un test sur un nom', () {
    String portee(String fonction) => patPorteeImagerie(SessionLabo(fonction: fonction));
    test('valeurs d\'attente : celles que le code disait', () {
      expect(portee('medecin'), 'tous');
      expect(portee('chirurgien'), 'tous');
      expect(portee('direction'), 'tous');
      expect(portee('sage_femme'), 'secteur');
      for (final f in ['infirmier', 'aide_soignant', 'tsl', 'biologiste', 'accueil', 'caissiere', 'stock', 'comptable']) {
        expect(portee(f), 'aucun', reason: f);
      }
    });
    test('chaque fonction de la matrice déclare sa portée ; l\'imagerie n\'ouvre jamais plus que « tous »', () {
      for (final c in capacitesLabo.values) {
        expect(['tous', 'secteur', 'aucun'], contains(c.voirImagerie), reason: c.fonction);
        expect(patPorteeImagerie(SessionLabo(fonction: c.fonction)), c.voirImagerie, reason: c.fonction);
      }
    });
    test('une fonction inconnue retombe sur celle déduite du rôle (jamais un accès élargi)', () {
      expect(patPorteeImagerie(const SessionLabo(role: 'reception', fonction: 'inventee')), 'aucun');
    });
  });

  group('B — le plan de numérisation est CALCULÉ', () {
    const lots = [
      EntreeReference('hospitalises', 'Hospitalisés', ''),
      EntreeReference('chroniques', 'Chroniques', ''),
      EntreeReference('maternite', 'Maternité', ''),
      EntreeReference('assures', 'Assurés', ''),
      EntreeReference('recents', 'Récents', ''),
      EntreeReference('inactifs', 'Inactifs', ''),
    ];
    final auj = DateTime(2026, 11, 18);
    Map<String, Object?> doc(String patient, {bool scan = true, String le = '2026-11-10T09:00:00'}) =>
        {'id': 'D$patient$le', 'patientId': patient, if (scan) 'scan': {'sha256': 'a' * 64, 'deposeLe': le}};
    PlanNumerisation plan({int fonds = 100, int fenetre = 24, List<EntreeReference> l = lots, List<Map<String, Object?>>? documents}) => docPlanNumerisation(
          patients: [
            {'id': 'P1'},
            {'id': 'P2', 'assureur': 'NSIA'},
            {'id': 'P3'},
            {'id': 'P4'},
            {'id': 'P5'},
          ],
          documents: documents ?? [doc('P1'), doc('P2'), doc('P2', le: '2026-10-05T09:00:00'), doc('P5', scan: false)],
          consultations: [
            {'patientId': 'P3', 'date': '2026-09-01'},
            {'patientId': 'P4', 'date': '2020-01-01'}
          ],
          admissions: [
            {'patientId': 'P1', 'statut': 'en_cours', 'dateEntree': '2026-11-01'}
          ],
          analyses: const [],
          grossesses: [
            {'patientId': 'P4'}
          ],
          aujourdhui: auj,
          fondsDeclare: fonds,
          fenetreMois: fenetre,
          lots: l,
        );
    LotNumerisation lot(PlanNumerisation p, String c) => p.lots.firstWhere((x) => x.critere == c);

    test('numérisés = patients portant un fichier DÉPOSÉ (un document sans fichier ne compte pas, deux fichiers comptent un patient)', () {
      final p = plan();
      expect(p.numerises, 2);
      expect(p.repertoire, 5);
    });
    test('actifs = activité dans la fenêtre réglée ; la fenêtre se règle', () {
      expect(plan().prioritaires, 2, reason: 'P1 (admission) et P3 (consultation de septembre) ; P4 a été vu en 2020');
      expect(plan(fenetre: 120).prioritaires, 3, reason: 'dix ans : la consultation de 2020 de P4 entre dans la fenêtre');
      expect(plan(fenetre: 1).prioritaires, 1, reason: 'une fenêtre d\'un mois ne garde que l\'admission de novembre');
      expect(plan().prioritairesNumerises, 1);
      expect(plan().prioritairesRestants, 1);
    });
    test('un patient appartient au PREMIER lot dont il remplit le critère ; le total est ce que la donnée porte', () {
      final p = plan();
      expect([lot(p, 'hospitalises').total, lot(p, 'hospitalises').fait], [1, 1]);
      expect([lot(p, 'maternite').total, lot(p, 'maternite').fait], [1, 0]);
      expect([lot(p, 'assures').total, lot(p, 'assures').fait], [1, 1]);
      expect(lot(p, 'recents').total, 1, reason: 'P3 ; P1 est déjà au lot des hospitalisés');
    });
    test('l\'ORDRE des lots est un réglage : inverser change l\'affectation', () {
      final p = plan(l: [lots[4], lots[0], lots[5]]);
      expect([lot(p, 'recents').total, lot(p, 'hospitalises').total], [2, 0]);
    });
    test('un lot sans donnée pour le calculer SE DIT : non calculable, avec la raison, jamais un zéro', () {
      final p = plan();
      final c = lot(p, 'chroniques');
      expect([c.total, c.fait, c.calculable], [null, null, false]);
      expect(c.raison, contains('chronique'));
      final inconnu = plan(l: [const EntreeReference('mystere', 'Lot ?', '')]).lots.single;
      expect(inconnu.calculable, isFalse);
      expect(inconnu.raison, contains('mystere'));
    });
    test('le fonds papier est DÉCLARÉ : il porte le lot inactif ; plus petit que le répertoire, le répertoire est retenu et on le dit', () {
      final p = plan(fonds: 1000);
      expect(p.fonds, 1000);
      expect(lot(p, 'inactifs').total, 1000 - (1 + 1 + 1 + 1), reason: 'le fonds moins les quatre lots calculés');
      expect(p.fondsInferieurAuRepertoire, isFalse);
      final petit = plan(fonds: 2);
      expect(petit.fonds, 5);
      expect(petit.fondsInferieurAuRepertoire, isTrue);
    });
    test('la cadence compte les fichiers déposés par mois, sur douze mois', () {
      final p = plan();
      expect(p.cadence, hasLength(12));
      expect(p.cadence.last, 2, reason: 'novembre : P1 et P2');
      expect(p.cadence[10], 1, reason: 'octobre : le second fichier de P2');
      expect(p.cadence.fold<num>(0, (a, b) => a + b), 3);
    });
    test('aucun dossier : tout vaut zéro, rien n\'est inventé', () {
      final p = docPlanNumerisation(
          patients: const [], documents: const [], consultations: const [], admissions: const [], analyses: const [], grossesses: const [], aujourdhui: auj, fondsDeclare: 0, fenetreMois: 24, lots: lots);
      expect([p.numerises, p.prioritaires, p.fonds, p.fondsInactif], [0, 0, 0, 0]);
    });
    test('les trois réglages du plan existent, bornés, et leurs valeurs d\'attente sont celles de l\'écran d\'avant', () {
      expect(seuilSeme(cleFondsPapier), 18000);
      expect(seuilSeme(cleFenetreDossiersActifs), 24);
      expect(ListesReference.entrees('listes.m1.lotsNumerisation').map((e) => e.code), ['hospitalises', 'chroniques', 'maternite', 'assures', 'recents', 'inactifs']);
      expect(seuilEntierDe(cleFondsPapier, -5), 18000, reason: 'hors bornes : la valeur d\'attente');
      expect(seuilEntierDe(cleFenetreDossiersActifs, 0), 24);
      expect(seuilEntierDe(cleFondsPapier, 25000), 25000);
    });
  });

  group('H — les tranches d\'âge sont UNE définition paramétrable, lue par deux écrans', () {
    test('valeurs d\'attente : exactement les deux découpages d\'avant (vecteurs de la maquette conservés)', () {
      expect([for (final t in tranchesAge) '${t.id}|${t.label}|${t.min}|${t.max}'],
          ['0-5|0 – 5 ans|0|5', '6-15|6 – 15 ans|6|15', '16-25|16 – 25 ans|16|25', '26-45|26 – 45 ans|26|45', '46-65|46 – 65 ans|46|65', '66+|66 ans et plus|66|200']);
      expect(pilTranchesAgeExamens,
          [('0-4', '0–4 ans', 0, 4), ('5-14', '5–14 ans', 5, 14), ('15-24', '15–24 ans', 15, 24), ('25-44', '25–44 ans', 25, 44), ('45-64', '45–64 ans', 45, 64), ('65+', '65 ans et plus', 65, 200)]);
    });
    test('les deux écrans divergent par RÉGLAGE, pas par du code : même fonction, deux clés', () {
      expect(ListesReference.semence(cleTranchesAgeLabo), isNot(ListesReference.semence(clePilTranchesAgeExamens)));
      brancher([version(cleTranchesAgeLabo, '4; 14; 24; 44; 64', '2026-11-01'), version(clePilTranchesAgeExamens, '4; 14; 24; 44; 64', '2026-11-01')]);
      expect([for (final t in tranchesAge) '${t.min}-${t.max}'], [for (final t in pilTranchesAgeExamens) '${t.$3}-${t.$4}'], reason: 'les aligner (DHIS2) = recopier les mêmes bornes');
    });
    test('changer les bornes change la tranche d\'un patient, à partir de la date d\'effet seulement', () {
      final patient = {'dateNaissance': '2016-01-01'}; // 10 ans au 18/11/2026
      final auj = DateTime(2026, 11, 18);
      expect(trancheAgeLabel(patient, auj), '6 – 15 ans');
      final fiches = [version(cleTranchesAgeLabo, '9; 19; 59', '2026-12-01')];
      ListesReference.brancher(() => fiches, horloge: () => DateTime(2026, 11, 30));
      expect(trancheAgeLabel(patient, auj), '6 – 15 ans');
      ListesReference.brancher(() => fiches, horloge: () => DateTime(2026, 12, 2));
      expect(trancheAgeLabel(patient, auj), '10 – 19 ans');
      expect(tranchesAge.last.label, '60 ans et plus');
    });
    test('des bornes incohérentes retombent sur la valeur d\'attente, jamais sur « aucune tranche »', () {
      for (final mauvais in ['', '15; 5', 'a; b', '5; 05', '-1; 5', '200']) {
        brancher([version(cleTranchesAgeLabo, mauvais, '2026-11-01')]);
        expect(tranchesAge, hasLength(6), reason: '« $mauvais »');
        expect(tranchesAge.first.label, '0 – 5 ans', reason: '« $mauvais »');
      }
    });
    test('une seule borne donne deux tranches, la seconde ouverte', () {
      final t = tranchesAgeDepuisBornes([17], separateur: '-');
      expect([for (final x in t) x.label], ['0-17 ans', '18 ans et plus']);
      expect(t.last.contient(90), isTrue);
    });
    test('les statistiques du pilotage suivent le réglage', () {
      brancher([version(clePilTranchesAgeExamens, '9; 59', '2026-11-01')]);
      expect([for (final t in pilTranchesAgeExamens) t.$2], ['0–9 ans', '10–59 ans', '60 ans et plus']);
    });
  });
}
