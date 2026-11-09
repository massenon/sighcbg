// LES 120 PATIENTS FICTIFS DU JEU (M1) : 80 salariés des six entreprises clientes, 15 assurés de NSIA, SUNU et SANLAM (dont DEUX cartes expirées, pour
// montrer RG-09), 25 clients de passage. Codes `CBG/1/26` à `CBG/120/26` (RG-01 : attribués dans l'ordre de création, jamais modifiés). Les conventions des
// six entreprises (la grille de garanties par souscripteur) sont posées ici : sans elles, le moteur de prise en charge ne répartirait rien.
import 'package:sigh_domaine/sigh_domaine.dart' as d;
import 'package:sigh_poste/donnees/magasin.dart';

import 'clinique_base.dart';
import 'clinique_noms.dart';
import 'contexte.dart';

/// Un patient du jeu avec ce que les événements ont besoin de savoir de lui.
class PatientJeu {
  PatientJeu(this.id, this.code, this.groupe, this.entrepriseId, this.creation, this.sexe, this.naissance);
  final String id;
  final String code;

  /// `salarie`, `assure` ou `passage`.
  final String groupe;
  final String? entrepriseId;
  final DateTime creation;
  final String sexe;
  final DateTime naissance;
  bool get assure => groupe != 'passage';
  Fiche fiche(Jeu j) => j.parId('patients', id)!;
}

const String mentionFictif = 'Patient fictif de démonstration';

/// Les trois taux de la convention : 70 % pour les soins courants, 80 % pour l'hospitalisation, 100 % pour les prestations de médecine du travail et la
/// fiche d'aptitude (l'employeur les règle). Une catégorie sans garantie (certificat, médicament) reste à la charge du patient.
const List<(String, String, num)> garantiesTypes = [
  ('medecine_travail', 'Visites de médecine du travail', 100),
  ('fiche_aptitude', 'Fiche d’aptitude (médecine du travail)', 100),
  ('consultation', 'Consultations', 70),
  ('analyse', 'Analyses de laboratoire', 70),
  ('imagerie', 'Imagerie médicale', 70),
  ('soin', 'Soins et actes infirmiers', 70),
  ('maternite', 'Maternité', 70),
  ('chirurgie', 'Chirurgie et actes du bloc', 70),
  ('hospitalisation', 'Hospitalisation', 80),
];

void poserGaranties(Jeu j) {
  var n = 0;
  final souscripteurs = j.lire('souscripteurs');
  for (final s in souscripteurs) {
    for (final (cat, libelle, taux) in garantiesTypes) {
      n++;
      j.ajouter(
          'garanties',
          {
            'id': 'GAR${pad(n, 4)}',
            'statut': 'actif',
            'souscripteurId': s['id'],
            'assureur': s['assureur'],
            'categorie': cat,
            'libelle': libelle,
            'taux': taux,
            'plafond': null,
            'source': 'Convention fictive de démonstration : à remplacer par la convention réellement signée',
          },
          'GAR');
    }
    j.maj('souscripteurs', s['id'], {'grilleSaisie': true});
  }
}

/// Les trois profils de patients : les listes des nombres par entreprise suivent l'effectif déclaré des six entreprises (60, 45, 38, 30, 25, 20).
const List<int> _salariesParEntreprise = [22, 17, 14, 11, 9, 7];

List<PatientJeu> creerPatients(Jeu j) {
  final t = j.t;
  final ctx = j.ctx;
  final assureurs = {for (final a in ctx.fiches('assureurs')) '${a['code']}': '${a['nom']}'};
  final souscripteurs = ctx.fiches('souscripteurs');

  // 1. Les étiquettes des 120 patients, puis le mélange : les codes suivent l'ordre de création, pas celui des groupes.
  final etiquettes = <(String, int)>[
    for (var e = 0; e < 6; e++)
      for (var i = 0; i < _salariesParEntreprise[e]; i++) ('salarie', e),
    for (var i = 0; i < 15; i++) ('assure', i),
    for (var i = 0; i < 25; i++) ('passage', i),
  ];
  final ordre = t.melanger(etiquettes);

  // 2. Les dates de création : croissantes avec le code, réparties sur les jours ouvrés du 01/08 au 30/10.
  final jours = ctx.joursOuvres(du: DateTime(2026, 8, 1), au: DateTime(2026, 10, 30));

  // 3. Les noms : combinaisons uniques.
  final pris = <String>{};
  (String, String) nom(String sexe) {
    for (;;) {
      final n = t.choisir(patronymes);
      final p = t.choisir(sexe == 'F' ? prenomsFeminins : prenomsMasculins);
      if (pris.add('$n $p')) return (n, p);
    }
  }

  // 4. Les deux cartes expirées parmi les quinze assurés (rangs 3 et 11).
  final fiches = <PatientJeu>[];
  var compteurAssure = 0;
  var tel = 0;
  for (var k = 0; k < ordre.length; k++) {
    final (groupe, e) = ordre[k];
    final rang = k + 1;
    final creation = jours[(k * jours.length ~/ ordre.length)];
    final sexe = switch (groupe) {
      'salarie' => t.chance(0.28) ? 'F' : 'M',
      'assure' => t.chance(0.55) ? 'F' : 'M',
      _ => t.chance(0.6) ? 'F' : 'M',
    };
    final (n, p) = nom(sexe);
    // Âges : adultes pour les salariés, plus étalés pour les autres.
    final age = switch (groupe) {
      'salarie' => t.entre(21, 58),
      'assure' => t.entre(8, 64),
      _ => t.choisir([2, 4, 7, 11, 16, 22, 27, 31, 36, 41, 47, 55, 62, 70]) + t.entre(0, 2),
    };
    final naissance = DateTime(2026 - age, t.entre(1, 12), t.entre(1, 28));
    final id = 'PAT${pad(rang, 4)}';
    final quartier = t.choisir(quartiers);
    final avecTel = t.chance(0.6);
    tel++;
    final fiche = <String, Object?>{
      'id': id,
      'statut': 'actif',
      'code': d.codePatient(rang, 2026),
      'nom': n,
      'prenom': p,
      'sexe': sexe,
      'dateNaissance': Contexte.date(naissance),
      'telephone': avecTel ? '00 00 00 00 ${pad(tel % 99 + 1, 2)}' : '',
      'adresse': '$quartier, Parakou',
      'quartier': quartier,
      'dateCreation': Contexte.date(creation),
      'groupeSanguin': t.pondere({'O+': 44, 'A+': 24, 'B+': 22, 'AB+': 4, 'O-': 3, 'A-': 1, 'B-': 1, 'AB-': 1}),
      'antecedents': t.chance(0.7) ? 'Aucun antécédent notable' : t.choisir(patAntecedentsCourants),
      'allergies': t.chance(0.85) ? '' : t.choisir(patAllergiesCourantes),
      'assure': groupe != 'passage',
      'tauxPriseEnCharge': 0,
      'fictif': true,
      'source': mentionFictif,
    };
    String? entrepriseId;
    if (groupe == 'salarie' || groupe == 'assure') {
      // Un salarié dépend de SON entreprise ; un assuré individuel est rattaché à l'une des deux entreprises de sa compagnie (ayant droit).
      final Fiche s;
      if (groupe == 'salarie') {
        s = souscripteurs[e];
      } else {
        final compagnie = const ['NSIA', 'SUNU', 'SANLAM'][e % 3];
        final de = souscripteurs.where((x) => x['assureur'] == compagnie).toList();
        s = de[(e ~/ 3) % de.length];
        compteurAssure++;
      }
      entrepriseId = '${s['id']}';
      final expiree = groupe == 'assure' && (e == 3 || e == 11);
      fiche.addAll({
        'assureur': s['assureur'],
        'assureurNom': assureurs['${s['assureur']}'],
        'numeroPolice': s['police'],
        'souscripteurId': s['id'],
        'souscripteur': s['nom'],
        'categorieAssurance': 'entreprise',
        'tauxPriseEnCharge': 70,
        'carteExpiration': expiree ? (e == 3 ? '2026-06-30' : '2026-09-30') : '2027-07-31',
        if (groupe == 'salarie') 'profession': t.choisir(professions),
        if (groupe == 'salarie') 'employeur': s['nom'],
        if (groupe == 'assure') 'typeAssure': 'ayant droit',
      });
    }
    ctx.ajouter('patients', normalisee(fiche));
    fiches.add(PatientJeu(id, '${fiche['code']}', groupe, entrepriseId, creation, sexe, naissance));
  }
  if (compteurAssure != 15) throw StateError('15 assurés attendus, $compteurAssure créés.');
  ctx.note('clinique : 120 patients fictifs (${fiches.where((p) => p.groupe == 'salarie').length} salariés, 15 assurés dont 2 cartes expirées, 25 de passage)');
  return fiches;
}

const List<String> patAntecedentsCourants = [
  'Hypertension artérielle', 'Diabète de type 2', 'Asthme', 'Ulcère gastrique', 'Drépanocytose', 'Césarienne antérieure',
];
const List<String> patAllergiesCourantes = ['Pénicilline', 'Sulfamides', 'Aspirine', 'Iode'];
