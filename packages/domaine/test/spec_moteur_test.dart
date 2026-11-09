import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  final fiches = specFichesDeBase();

  group('les quatorze fiches de base', () {
    test('quatorze spécialités, codes uniques, dans l\'ordre de la clinique', () {
      expect(fiches.length, 14);
      expect({for (final f in fiches) f['code']}.length, 14);
      expect(fiches.map((f) => f['libelle']).toList(), [
        'Médecine du travail', 'Santé publique', 'Gynécologie', 'Chirurgie', 'Urologie', 'Rhumatologie', 'Ophtalmologie',
        'Orthophonie', 'Endocrinologie', 'Pédiatrie', 'Neurologie', 'Cardiologie', 'Kinésithérapie', 'Imagerie'
      ]);
    });

    test('aucune fiche n\'est marquée « à valider » (contenu arrêté par la Direction) et toutes citent leur source', () {
      for (final f in fiches) {
        expect(f.containsKey('aValider'), isFalse, reason: '${f['code']}');
        expect(f['source'], specSource);
        expect(f['statut'], 'actif');
        expect(specRefusModele(f['modele']), isNull, reason: '${f['code']}');
      }
    });

    test('gynécologie, chirurgie et imagerie RENVOIENT vers leurs écrans existants ; la médecine du travail vers les siens', () {
      Map<String, Object?> de(String code) => fiches.firstWhere((f) => f['code'] == code);
      List<String> renvoi(String code) => [for (final r in (de(code)['renvoi'] as List)) (r as Map)['ecran'] as String];
      expect(renvoi('gynecologie'), contains('m4-dossier-obstetrical'));
      expect(renvoi('chirurgie'), contains('m3-bloc-cro'));
      expect(renvoi('imagerie'), contains('m2-imagerie-demandes'));
      expect(renvoi('medecine-travail'), ['m2-mdt-visites', 'm2-mdt-entreprises', 'm2-mdt-conventions']);
      expect(fiches.where((f) => f.containsKey('renvoi')).length, 4);
    });

    test('la référence est neuve à chaque appel : modifier une fiche ne touche pas la suivante', () {
      final a = specFichesDeBase();
      a.first['libelle'] = 'Autre';
      expect(specFichesDeBase().first['libelle'], 'Médecine du travail');
    });
  });

  group('le formulaire naît du modèle', () {
    final cardio = fiches.firstWhere((f) => f['code'] == 'cardiologie');

    test('questions, examen par appareil, antécédents et conclusion, dans cet ordre', () {
      final c = specChampsDepuisModele(cardio['modele']);
      final noms = [for (final x in c) x.nom];
      expect(noms.first, '');
      expect(noms, containsAllInOrder(['q_tension', 'q_fc', 'ex.cardio_vasculaire.inspection', 'ex.cardio_vasculaire.auscultation', 'ex.pleuro_pulmonaire.palpation', 'ant_medicaux', 'diagnostic', 'conduite']));
      expect(c.firstWhere((x) => x.nom == 'diagnostic').requis, isTrue);
      final fc = c.firstWhere((x) => x.nom == 'q_fc');
      expect(fc.type, 'nombre');
      expect(fc.libelle, 'Fréquence cardiaque (bpm)');
      expect(c.firstWhere((x) => x.nom == 'q_dyspnee').options, ['Aucune', 'À l’effort', 'Au repos']);
      expect(c.firstWhere((x) => x.nom == 'q_ecg').options, ['Oui', 'Non']);
    });

    test('ajouter une question au modèle suffit à la faire paraître au formulaire suivant', () {
      final modele = {
        'sections': [
          {'titre': 'Peau', 'champs': [{'code': 'lesion', 'libelle': 'Lésion', 'type': 'texte'}]}
        ],
        'appareils': <String>[],
        'antecedents': false,
      };
      expect([for (final x in specChampsDepuisModele(modele)) x.nom], ['', 'q_lesion', '', 'diagnostic', 'conduite']);
      ((modele['sections'] as List).first as Map)['champs'].add({'code': 'prurit', 'libelle': 'Prurit', 'type': 'oui_non'});
      expect([for (final x in specChampsDepuisModele(modele)) x.nom], ['', 'q_lesion', 'q_prurit', '', 'diagnostic', 'conduite']);
    });

    test('un modèle sans question ni examen est refusé ; deux questions de même code aussi', () {
      expect(specRefusModele({'sections': <Object>[], 'appareils': <String>[]}), contains('ne recueille rien'));
      expect(
          specRefusModele({
            'sections': [
              {'titre': 'A', 'champs': [{'code': 'x', 'libelle': 'X', 'type': 'texte'}, {'code': 'x', 'libelle': 'Y', 'type': 'texte'}]}
            ]
          }),
          contains('« x »'));
      expect(
          specRefusModele({
            'sections': [
              {'titre': 'A', 'champs': [{'code': 'x', 'libelle': 'X', 'type': 'choix'}]}
            ]
          }),
          contains('sans aucune option'));
    });

    test('la saisie est rangée comme la consultation la garde : nombres, examen par appareil, antécédents', () {
      final s = specSeparer(cardio['modele'], {
        'q_tension': '14/9',
        'q_fc': '88',
        'q_ecg': 'Oui',
        'q_ecg_resultat': '',
        'ex.cardio_vasculaire.auscultation': 'B1 B2 réguliers',
        'ant_medicaux': 'HTA',
        'diagnostic': 'Hypertension artérielle',
        'conduite': 'Contrôle dans un mois',
      });
      expect(s.reponses, {'tension': '14/9', 'fc': 88, 'ecg': 'Oui'});
      expect(s.reponses['fc'], isA<num>());
      expect(s.examensPhysiques, {'cardio_vasculaire': {'auscultation': 'B1 B2 réguliers'}});
      expect(s.antecedents, {'ant_medicaux': 'HTA'});
      expect(s.diagnostic, 'Hypertension artérielle');
    });

    test('refus nommés : diagnostic absent, nombre hors des bornes du modèle', () {
      expect(specRefusSaisie(cardio['modele'], {'diagnostic': ''}), 'Rédiger le diagnostic retenu.');
      expect(specRefusSaisie(cardio['modele'], {'diagnostic': 'HTA', 'q_fc': '500'}), contains('dépasse le maximum'));
      expect(specRefusSaisie(cardio['modele'], {'diagnostic': 'HTA', 'q_fc': '80'}), isNull);
    });

    test('les réponses restent lisibles quand une question quitte le modèle', () {
      final l = specReponsesLisibles(cardio['modele'], {'fc': 88, 'ancienne': 'x'});
      expect(l[0].libelle, 'Fréquence cardiaque');
      expect(l[0].valeur, '88 bpm');
      expect(l[1].libelle, 'ancienne');
    });
  });

  group('l\'identité des écrans dynamiques', () {
    final codes = ['medecine-travail', 'cardiologie', 'a'];
    test('aller-retour, y compris pour un code à tirets', () {
      for (final c in codes) {
        for (final v in SpecVue.values) {
          final r = specAnalyserId(specIdEcran(c, v), codes);
          expect(r, (code: c, vue: v), reason: specIdEcran(c, v));
        }
      }
      expect(specIdEcran('cardiologie'), 'spec-cardiologie');
      expect(specIdEcran('medecine-travail', SpecVue.agenda), 'spec-medecine-travail-agenda');
    });
    test('un identifiant étranger ou une spécialité inconnue ne répondent pas', () {
      expect(specAnalyserId('m2-agenda', codes), isNull);
      expect(specAnalyserId('spec-inconnue', codes), isNull);
      expect(specAnalyserId('spec-cardiologie-stats', ['cardiologie']), (code: 'cardiologie', vue: SpecVue.stats));
      expect(specAnalyserId('spec-cardiologie-stats', const []), isNull);
    });
    test('un code refusé : vide, majuscules, accent, suffixe réservé, doublon', () {
      expect(specRefusCode('dermatologie', ['cardiologie']), isNull);
      expect(specRefusCode('', const []), isNotNull);
      expect(specRefusCode('Derma', const []), contains('minuscules'));
      expect(specRefusCode('gériatrie', const []), contains('minuscules'));
      expect(specRefusCode('derma-stats', const []), contains('suffixe'));
      expect(specRefusCode('cardiologie', ['cardiologie']), contains('déjà'));
    });
  });

  group('la consultation enregistrée et les statistiques recomptées', () {
    final fiche = fiches.firstWhere((f) => f['code'] == 'cardiologie');
    final patient = {'id': 'P1', 'code': 'CBG/1/26', 'nom': 'AKO', 'prenom': 'Bio', 'sexe': 'M'};
    test('la pièce porte la spécialité, les réponses et les champs de lecture du dossier', () {
      final s = specSeparer(fiche['modele'], {'q_fc': '70', 'diagnostic': 'RAS'});
      final c = specNouvelleConsultation(
          fiche: fiche, patient: patient, saisie: s, praticien: 'Dr X', date: DateTime.utc(2026, 11, 9, 8), reference: 'C00001', tarif: 10000);
      expect(c['specialite'], 'cardiologie');
      expect(c['type'], specTypeConsultation);
      expect(c['patientCode'], 'CBG/1/26');
      expect(c['diagnostic'], 'RAS');
      expect(c['statut'], 'terminee');
      expect(specDeLaConsultation(c), 'cardiologie');
      expect(c.values.contains(null), isFalse);
    });
    test('une visite de médecine du travail d\'avant la mécanique se reconnaît à son type', () {
      expect(specDeLaConsultation({'type': 'Médecine du travail'}), 'medecine-travail');
      expect(specDeLaConsultation({'type': 'Consultation'}), isNull);
    });
    test('les statistiques se recomptent depuis les registres : période, praticien, sexe, mois, diagnostics, file', () {
      final base = {'type': specTypeConsultation, 'specialite': 'cardiologie', 'statut': 'terminee', 'tarif': 10000};
      final consults = [
        {...base, 'patientId': 'P1', 'date': '2026-11-02T08:00:00.000Z', 'medecin': 'Dr X', 'diagnostic': 'HTA'},
        {...base, 'patientId': 'P1', 'date': '2026-11-05T08:00:00.000Z', 'medecin': 'Dr X', 'diagnostic': 'HTA'},
        {...base, 'patientId': 'P2', 'date': '2026-10-20T08:00:00.000Z', 'medecin': 'Dr Y', 'diagnostic': 'Angor'},
        {...base, 'patientId': 'P3', 'date': '2026-08-01T08:00:00.000Z', 'medecin': 'Dr Y', 'diagnostic': 'HTA'},
        {...base, 'specialite': 'urologie', 'patientId': 'P1', 'date': '2026-11-02T08:00:00.000Z', 'medecin': 'Dr Z', 'diagnostic': 'Autre'},
        {...base, 'statut': 'planifiee', 'patientId': 'P2', 'date': '2026-11-20T08:00:00.000Z', 'medecin': 'Dr X'},
        {...base, 'statut': 'archive', 'patientId': 'P9', 'date': '2026-11-03T08:00:00.000Z', 'medecin': 'Dr X', 'diagnostic': 'HTA'},
      ];
      final patients = [
        {'id': 'P1', 'sexe': 'M'},
        {'id': 'P2', 'sexe': 'F'},
        {'id': 'P3', 'sexe': 'F'},
      ];
      final file = [
        {'specialite': 'cardiologie', 'etat': 'attente'},
        {'specialite': 'cardiologie', 'etat': 'servi'},
        {'specialite': 'urologie', 'etat': 'attente'},
      ];
      final s = specStatistiques('cardiologie',
          consultations: consults, patients: patients, fileAttente: file, aujourdhui: DateTime(2026, 11, 9));
      expect(s.consultations, 4);
      expect(s.patients, 3);
      expect(s.ceMois, 2);
      expect(s.rendezVousAVenir, 1);
      expect(s.fileEnAttente, 1);
      expect(s.recettes, 40000);
      expect(s.parPraticien.map((e) => (e.libelle, e.valeur)).toList(), [('Dr X', 2), ('Dr Y', 2)]);
      expect(s.parMois.map((e) => (e.libelle, e.valeur)).toList(), [('2026-08', 1), ('2026-10', 1), ('2026-11', 2)]);
      expect(s.parSexe.map((e) => (e.libelle, e.valeur)).toList(), [('Hommes', 2), ('Femmes', 2)]);
      expect(s.diagnostics.first, (libelle: 'HTA', valeur: 3));
      // La période restreint le décompte.
      final p = specStatistiques('cardiologie',
          consultations: consults, patients: patients, du: '2026-11-01', au: '2026-11-30', aujourdhui: DateTime(2026, 11, 9));
      expect(p.consultations, 2);
      expect(p.patients, 1);
      expect(p.aptitudes, isEmpty);
    });
  });
}
