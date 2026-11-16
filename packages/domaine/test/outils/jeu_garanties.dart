// JEU DE FACTURES DU RELEVÉ « AVANT / APRÈS » des garanties datées (T13, 14/11/2026).
//
// Le jeu est DÉTERMINISTE (aucun hasard, aucune horloge) et ne porte que des données inventées pour l'épreuve : trois souscripteurs avec leur grille propre, un souscripteur dont la
// compagnie porte la grille, un souscripteur sans convention, et des assurés qui changent de souscripteur en cours d'année. Il sert deux fois : `releve_garanties_avant.dart` l'a rejoué
// sur le moteur d'AVANT (garanties sans date) et a écrit `vecteurs/garanties_avant.json` ; `garanties_datees_test.dart` le rejoue sur le moteur d'APRÈS et exige le même résultat,
// tant qu'aucune version datée n'est ajoutée. Un montant facturé ne change pas à la migration.
import 'package:sigh_domaine/sigh_domaine.dart';

typedef F = Map<String, Object?>;

Map<String, Object?> _g(String sous, String code, String libelle, String cat, num taux, num? plafond, String? unite, {String? assureur}) => {
      'id': 'GAR-$sous-$code',
      'souscripteurId': sous.isEmpty ? null : sous,
      'assureur': assureur ?? 'ASS1',
      'code': code,
      'libelle': libelle,
      'categorie': cat,
      'taux': taux,
      'plafond': plafond,
      'unitePlafond': unite,
      'zone': 'Bénin',
    };

/// Les souscripteurs : S1 et S2 portent leur grille, S3 la reçoit de sa compagnie, S4 n'a aucune convention.
List<F> souscripteursJeu() => [
      {'id': 'S1', 'nom': 'Employeur un', 'assureur': 'ASS1', 'police': 'P/1', 'categorie': 'entreprise', 'actesExclus': ['Check-up et bilan de santé'], 'produitsExclus': ['Gants'], 'accordPrealable': ['Scanner']},
      {'id': 'S2', 'nom': 'Employeur deux', 'assureur': 'ASS1', 'police': 'P/2', 'categorie': 'entreprise', 'actesExclus': [], 'produitsExclus': [], 'accordPrealable': []},
      {'id': 'S3', 'nom': 'Employeur trois', 'assureur': 'ASS2', 'police': 'P/3', 'categorie': 'particulier', 'actesExclus': [], 'produitsExclus': [], 'accordPrealable': []},
      {'id': 'S4', 'nom': 'Employeur quatre', 'assureur': 'ASS3', 'police': 'P/4', 'categorie': 'particulier', 'actesExclus': [], 'produitsExclus': [], 'accordPrealable': []},
    ];

/// Les garanties d'AVANT : aucune ne porte de date d'effet ni de rang de version.
List<F> garantiesJeu() => [
      for (final b in AssBareme.garanties) _g('S1', '${b['code']}', '${b['libelle']}', '${b['categorie']}', b['taux'] as num, b['plafond'] as num?, b['unitePlafond'] as String?),
      _g('S2', 'A', 'Consultation généraliste', 'consultation', 70, 4000, 'acte'),
      _g('S2', 'B', 'Consultation spécialiste ou professeur', 'consultation', 70, 9000, 'acte'),
      _g('S2', 'C', 'Analyses et travaux de laboratoire', 'analyse', 60, null, null),
      _g('S2', 'D', 'Frais pharmaceutiques', 'medicament', 50, 20000, 'acte'),
      _g('', 'X1', 'Consultation généraliste', 'consultation', 100, null, null, assureur: 'ASS2'),
      _g('', 'X2', 'Analyses et travaux de laboratoire', 'analyse', 90, 15000, 'acte', assureur: 'ASS2'),
    ];

List<F> patientsJeu() => [
      for (final (id, ass, sous, exp) in const [
        ('PA1', 'ASS1', 'S1', '2027-12-31'),
        ('PA2', 'ASS1', 'S2', '2027-06-30'),
        ('PA3', 'ASS2', 'S3', '2027-03-31'),
        ('PA4', 'ASS3', 'S4', '2027-12-31'),
        ('PA5', 'ASS1', 'S1', '2026-05-31'), // carte expirée en cours d'année
        ('PA6', 'ASS1', 'S2', '2027-12-31'), // change de souscripteur le 01/06/2026
        ('PA7', '', '', ''), // non assuré
      ])
        {
          'id': id,
          'assureur': ass.isEmpty ? null : ass,
          'souscripteurId': sous.isEmpty ? null : sous,
          'carteExpiration': exp.isEmpty ? null : exp,
          'categorieAssurance': 'entreprise',
          'tauxPriseEnCharge': 80,
        }
    ];

List<F> couverturesJeu() => [
      {'id': 'CV-6a', 'patientId': 'PA6', 'assureur': 'ASS1', 'souscripteurId': 'S1', 'carteExpiration': '2027-12-31', 'debut': null, 'fin': '2026-05-31'},
      {'id': 'CV-6b', 'patientId': 'PA6', 'assureur': 'ASS1', 'souscripteurId': 'S2', 'carteExpiration': '2027-12-31', 'debut': '2026-06-01', 'fin': null},
    ];

const _lignesTypes = <(String, String, num)>[
  ('Consultation généraliste', 'consultation', 5000),
  ('Consultation spécialiste', 'consultation', 12000),
  ('Bilan sanguin', 'analyse', 18000),
  ('Amoxicilline', 'medicament', 9000),
  ('Pansement', 'soin', 2500),
  ('Échographie pelvienne', 'imagerie', 15000),
  ('Scanner', 'imagerie', 60000),
  ('Accouchement normal', 'maternite', 200000),
  ('Check-up et bilan de santé', 'consultation', 30000),
  ('Gants', 'medicament', 1500),
  ('Journée d’hospitalisation', 'hospitalisation', 20000),
];

/// Les pièces : chaque (assuré, jour) du calendrier de l'année porte trois à quatre lignes tirées de façon déterministe.
List<({String patientId, String date, List<F> lignes})> piecesJeu() {
  final out = <({String patientId, String date, List<F> lignes})>[];
  var k = 0;
  const jours = ['2026-01-15', '2026-03-02', '2026-05-31', '2026-06-01', '2026-06-20', '2026-08-10', '2026-11-14', '2026-12-31'];
  for (final p in patientsJeu()) {
    for (final j in jours) {
      final n = 3 + (k % 2);
      out.add((
        patientId: '${p['id']}',
        date: j,
        lignes: [
          for (var i = 0; i < n; i++)
            () {
              final t = _lignesTypes[(k * 3 + i * 5) % _lignesTypes.length];
              return <String, Object?>{'libelle': t.$1, 'categorie': t.$2, 'montant': t.$3, 'accordObtenu': (k + i) % 4 == 0};
            }()
        ]
      ));
      k++;
    }
  }
  return out;
}

/// Ce que le moteur répond pour toutes les pièces, dans une forme comparable (JSON).
List<Map<String, Object?>> releve({List<F>? garanties}) {
  final g = garanties ?? garantiesJeu();
  final pats = {for (final p in patientsJeu()) p['id']: p};
  return [
    for (final pc in piecesJeu())
      () {
        final r = repartir(patient: pats[pc.patientId], lignes: pc.lignes, date: pc.date, couvertures: couverturesJeu(), souscripteurs: souscripteursJeu(), garanties: g);
        return <String, Object?>{
          'patientId': pc.patientId,
          'date': pc.date,
          'souscripteurId': r.souscripteurId,
          'carteValide': r.carteValide,
          'grilleSaisie': r.grilleSaisie,
          'total': r.total,
          'partAssureur': r.partAssureur,
          'partPatient': r.partPatient,
          'lignes': [
            for (final l in r.lignes) {'libelle': l['libelle'], 'partAssureur': l['partAssureur'], 'partPatient': l['partPatient'], 'taux': l['taux'], 'plafond': l['plafond'], 'garantie': l['garantie'], 'motif': l['motif']}
          ],
        };
      }()
  ];
}
