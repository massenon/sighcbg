// HOSPITALISATION ET BLOC (M3) : huit admissions (six mises en observation de vingt-quatre heures au plus, deux hospitalisations dont l'une naît d'une
// observation), leurs sorties, la surveillance (relevés, soins, visites), puis cinq interventions avec compte rendu opératoire, check-listes, consultation
// pré-anesthésique et compte rendu d'anesthésie pour trois d'entre elles. Les deux autres sont SIGNALÉES sans CPA, jamais bloquées (l'urgence n'attend pas).
//
// La clinique n'a pas de chirurgien au personnel : les opérateurs sont les vacataires fictifs du socle (chirurgien, gynécologue) ; l'anesthésiste est le
// médecin, l'aide opérateur l'infirmier. Chaque intervention tarifée au catalogue passe par la caisse ; une mise en observation n'est pas tarifée.
import 'package:sigh_domaine/sigh_domaine.dart' as d;
import 'package:sigh_poste/donnees/magasin.dart';

import 'clinique_base.dart';
import 'clinique_patients.dart';
import 'clinique_soins.dart';
import 'contexte.dart';

/// Ce que la maternité communique au bloc : la patiente de la césarienne et la date.
class CesarienneJeu {
  CesarienneJeu(this.patient, this.quand);
  final PatientJeu patient;
  final DateTime quand;
}

PatientJeu? chercherPatient(List<PatientJeu> pats, Tirage t,
    {String? sexe, int ageMin = 0, int ageMax = 120, DateTime? creeAvant, Set<String> exclus = const {}, bool? assure}) {
  final ref = DateTime.utc(2026, 10, 1);
  final c = [
    for (final p in pats)
      if ((sexe == null || p.sexe == sexe) &&
          ageA(p, ref) >= ageMin &&
          ageA(p, ref) <= ageMax &&
          (creeAvant == null || !p.creation.isAfter(creeAvant)) &&
          !exclus.contains(p.id) &&
          (assure == null || p.assure == assure))
        p
  ];
  return c.isEmpty ? null : t.choisir(c);
}

const _signes = ['Surveillance rapprochée', 'Sous perfusion', 'Douleur en diminution', 'Patient conscient, orienté', 'État stable', 'Apyrexie'];

// --------------------------------------------------------------------------------------------------------------------------------------------
// Les mises en observation
// --------------------------------------------------------------------------------------------------------------------------------------------

Fiche _observation(Jeu j, PatientJeu pp, DateTime entree, {required int heures, required String unite, required String motif, String? orientation, String conclusion = '', String? destination}) {
  final t = j.t;
  final pat = pp.fiche(j);
  final u = d.hosUnitesObservation.firstWhere((x) => x.id == unite);
  final n = j.ctx.collection('observations').toutes.length + 1;
  final releves = <Map<String, Object?>>[];
  for (var h = 0; h <= heures; h += 4) {
    final tt = entree.add(Duration(hours: h));
    if (tt.isAfter(DateTime.utc(2026, 11, 7, 11, 45))) break;
    releves.add({
      'heure': iso8601(tt),
      'temperature': (36.4 + t.entre(0, 17) / 10).toStringAsFixed(1),
      // La tension en DEUX nombres (cmHg), dans l'ordre des tirages d'origine : systolique puis diastolique (lot B).
      'tensionSys': t.entre(10, 13),
      'tensionDia': t.entre(6, 8),
      'pouls': t.entre(66, 105),
      'spo2': t.entre(94, 99),
      'observation': t.choisir(_signes),
      'par': infirmierNom,
    });
  }
  final cloture = orientation != null;
  final sortie = entree.add(Duration(hours: heures));
  final fiche = {
    'statut': 'actif',
    'reference': 'OBS-2026-${pad(n, 4)}',
    'patientId': pat['id'],
    'patient': '${pat['nom']} ${pat['prenom']}',
    'patientCode': pat['code'],
    'unite': unite,
    'uniteLabel': u.label,
    'place': 'Place ${(n % u.places) + 1}',
    'motif': motif,
    'dateEntree': iso8601(entree),
    'medecin': medecinNom,
    'infirmier': infirmierNom,
    'constantes': releves,
    'statutObservation': cloture ? 'clos' : 'en_cours',
    if (cloture) ...{
      'orientation': orientation,
      'orientationLabel': d.hosOrientation(orientation)?.label ?? orientation,
      'conclusion': conclusion,
      'dateSortie': iso8601(sortie),
      'decidePar': medecinNom,
      if (destination != null) 'destination': destination,
    },
    'fictif': true,
  };
  return j.ajouter('observations', fiche, 'OBS', largeur: 4);
}

// --------------------------------------------------------------------------------------------------------------------------------------------
// Les hospitalisations
// --------------------------------------------------------------------------------------------------------------------------------------------

num _tarifChambre(Jeu j, String type) {
  final l = (j.ctx.referentiels['typesChambre'] as List).cast<Map>().firstWhere((x) => x['id'] == type);
  return l['tarif'] as num;
}

/// Ouvre l'admission : référence du registre, chambre et type tirés du lit (`hosConstruireAdmission`).
Fiche _admission(Jeu j, PatientJeu pp, DateTime entree, String lit, String diagnostic, String symptomes, {String? origineObservation}) {
  final pat = pp.fiche(j);
  final toutes = j.ctx.collection('admissions').toutes;
  final f = d.hosConstruireAdmission(
    {
      'patientCode': pat['code'],
      'lit': lit,
      'dateEntree': jourDe(entree),
      'diagnosticEntree': diagnostic,
      'symptomes': symptomes,
      'priseEnCharge': 'plus_8h',
      'infirmierId': infirmierSoignantId,
      'infirmier': infirmierNom,
      'statut': 'en_cours',
      if (origineObservation != null) 'origineObservation': origineObservation,
      'fictif': true,
    },
    null,
    j.lire('patients'),
    toutes,
    reference: (prefixe, largeur, fiches) => d.referenceSerie(prefixe, largeur, fiches),
  );
  return j.ajouter('admissions', f, 'ADM', largeur: 4);
}

void _surveillanceSejour(Jeu j, Fiche adm, DateTime debut, DateTime fin, {required String traitement}) {
  final t = j.t;
  // Deux relevés par jour (matin et soir) sur la feuille de température, un soin infirmier par jour, une visite sur deux.
  for (var jour = DateTime.utc(debut.year, debut.month, debut.day); !jour.isAfter(fin); jour = jour.add(const Duration(days: 1))) {
    if (jour.isAfter(DateTime.utc(2026, 11, 7))) break;
    for (final h in [8, 18]) {
      final tt = instant(jour, h);
      if (tt.isBefore(debut) || tt.isAfter(fin) || tt.isAfter(DateTime.utc(2026, 11, 7, 11, 45))) continue;
      j.ajouter(
          'releves',
          {
            'statut': 'actif',
            'admissionId': adm['id'],
            'date': jourDe(tt),
            'heure': '${pad(h, 2)}:00',
            'temperature': 36.5 + t.entre(0, 18) / 10,
            'tensionSys': t.entre(10, 13),
            'tensionDia': t.entre(6, 8),
            'fc': t.entre(64, 100),
            'spo2': t.entre(94, 99),
            'fr': t.entre(14, 22),
            'diurese': t.entre(900, 2200),
            'poids': t.entre(55, 85),
            'taille': t.entre(155, 185),
            'traitement': traitement,
            'saisiPar': infirmierNom,
          },
          'REL');
    }
    final tj = instant(jour, 10);
    if (!tj.isBefore(debut) && !tj.isAfter(fin) && !tj.isAfter(DateTime.utc(2026, 11, 7, 11, 45))) {
      j.ajouter(
          'soins',
          {
            'statut': 'actif',
            'date': jourDe(jour),
            'heure': '10:00',
            'admissionId': adm['id'],
            'patientId': adm['patientId'],
            'patient': adm['patient'],
            'patientCode': adm['patientCode'],
            'lit': adm['lit'],
            'acte': t.choisir(d.hosActesSoins),
            'produit': '',
            'quantite': 0,
            'soignant': infirmierNom,
            'observations': '',
            'etat': 'realise',
          },
          'SOI');
      if (t.chance(0.5)) {
        j.ajouter(
            'visitesHospi',
            {
              'statut': 'actif',
              'date': jourDe(jour),
              'heure': '${t.entre(15, 18)}:00',
              'admissionId': adm['id'],
              'patient': adm['patient'],
              'patientCode': adm['patientCode'],
              'lit': adm['lit'],
              'type': 'Famille',
              'visiteur': 'Accompagnant déclaré',
              'observation': 'Visite de courtoisie',
            },
            'VIS',
            largeur: 4);
      }
    }
  }
}

/// La facture du séjour : une ligne de journées au tarif de la chambre ; la répartition suit RG-09 (hospitalisation couverte à 80 % pour un assuré).
Fiche _factureSejour(Jeu j, Fiche adm, DateTime quand, int jours, {required bool regler}) {
  final pat = j.parId('patients', adm['patientId'])!;
  final type = '${adm['typeChambre']}';
  final tarif = _tarifChambre(j, type);
  final libelle = 'Journée d’hospitalisation — chambre ${d.hosLibelleTypeChambre(type)}';
  final l = d.ligneSaisie(nature: 'hospitalisation', designation: libelle, quantite: jours, prixUnitaire: tarif);
  final pieces = j.caisse.emettre(patient: pat, lignes: [l], quand: quand, type: 'Hospitalisation', complement: {'admissionId': adm['id']});
  if (regler) {
    for (final f in pieces) {
      j.caisse.encaisser('${f['id']}', mode: j.t.choisir(modesReglement), quand: quand.add(const Duration(minutes: 15)));
    }
  }
  j.maj('admissions', adm['id'], {'factureId': pieces.first['id'], 'factureNumero': pieces.first['numero']});
  return pieces.first;
}

// --------------------------------------------------------------------------------------------------------------------------------------------
// Le plan de la hospitalisation et du bloc
// --------------------------------------------------------------------------------------------------------------------------------------------

/// Planifie (et exécute dans la file) les huit admissions : six observations, deux hospitalisations. [exclus] : les patients déjà engagés ailleurs.
void planifierHospitalisation(Jeu j, List<PatientJeu> pats, Set<String> exclus) {
  final t = j.t;
  PatientJeu choisir({String? sexe, int ageMin = 18, int ageMax = 70, required DateTime avant}) {
    final p = chercherPatient(pats, t, sexe: sexe, ageMin: ageMin, ageMax: ageMax, creeAvant: avant, exclus: exclus) ??
        chercherPatient(pats, t, creeAvant: avant, exclus: exclus)!;
    exclus.add(p.id);
    return p;
  }

  // (jour, heure d'entrée, durée, unité, motif, orientation, conclusion, sexe, âge min, âge max)
  final obs = <(DateTime, int, int, String, String, String?, String, String?, int, int)>[
    (DateTime.utc(2026, 9, 5), 9, 10, 'urgences', 'Traumatisme crânien léger, surveillance neurologique', 'domicile', 'Surveillance sans particularité, retour à domicile.', null, 18, 60),
    (DateTime.utc(2026, 9, 22), 14, 8, 'medecine', 'Crise d’asthme, aérosols répétés', 'domicile', 'Amélioration complète, traitement de fond prescrit.', null, 12, 60),
    (DateTime.utc(2026, 10, 8), 11, 22, 'urgences', 'Paludisme avec vomissements incoercibles', 'hospitalisation', 'Paludisme sans amélioration à 22 heures : hospitalisation complète.', null, 18, 60),
    (DateTime.utc(2026, 10, 19), 8, 12, 'pediatrie', 'Fièvre élevée de l’enfant, surveillance', 'domicile', 'Apyrexie obtenue, retour à domicile avec ordonnance.', null, 1, 12),
    (DateTime.utc(2026, 11, 2), 16, 18, 'maternite', 'Contractions prématurées', 'transfert', 'Menace d’accouchement prématuré : transfert vers un établissement de niveau supérieur.', 'F', 20, 38),
  ];
  var idxHospi = -1;
  for (final (i, o) in obs.indexed) {
    final (jour, h, duree, unite, motif, orientation, conclusion, sexe, a0, a1) = o;
    final p = choisir(sexe: sexe, ageMin: a0, ageMax: a1, avant: DateTime(jour.year, jour.month, jour.day));
    final entree = instant(jour, h);
    j.planifier(entree, () {
      final fiche = _observation(j, p, entree,
          heures: duree, unite: unite, motif: motif, orientation: orientation, conclusion: conclusion, destination: orientation == 'transfert' ? 'Hôpital de référence (établissement de niveau supérieur)' : null);
      if (orientation == 'hospitalisation') {
        final sortieObs = entree.add(Duration(hours: duree));
        j.planifier(sortieObs, () {
          final adm = _admission(j, p, sortieObs, 'A2 LIT1', 'Paludisme grave', 'Vomissements incoercibles', origineObservation: '${fiche['reference']}');
          j.memo['admission1'] = adm['id'];
          final fin = DateTime.utc(sortieObs.year, sortieObs.month, sortieObs.day + 4, 10);
          _surveillanceSejour(j, adm, sortieObs, fin, traitement: 'Perfusion de sérum et antipaludéen injectable');
          j.planifier(fin, () {
            // RG-06 / RG-07 : solde apuré à la caisse, puis les trois signatures ; le lit est libéré.
            final f = _factureSejour(j, j.parId('admissions', adm['id'])!, fin, 4, regler: true);
            j.maj('admissions', adm['id'], {
              ...d.blocPatchSortie({'dateSortie': jourDe(fin), 'etatSortie': 'Guéri', 'consignes': 'Poursuite du traitement à domicile, contrôle à une semaine.', 'sigPatient': true}),
              'statut': 'sortie',
              'factureSortieNumero': f['numero'],
            });
          });
        });
      }
    });
    if (orientation == 'hospitalisation') idxHospi = i;
  }
  if (idxHospi < 0) throw StateError('Une observation doit mener à une hospitalisation.');
  // Une observation en cours (entrée ce matin, six heures de surveillance).
  final pEnCours = choisir(avant: DateTime(2026, 11, 6));
  j.planifier(DateTime.utc(2026, 11, 7, 6, 15), () {
    _observation(j, pEnCours, DateTime.utc(2026, 11, 7, 6, 15), heures: 6, unite: 'urgences', motif: 'Douleur abdominale aiguë, surveillance');
  });

  // La seconde hospitalisation : admise le 04/11, toujours en cours ; les nuits écoulées sont facturées et restent à encaisser.
  final p2 = choisir(avant: DateTime(2026, 11, 3));
  final entree2 = instant(DateTime.utc(2026, 11, 4), 15);
  j.planifier(entree2, () {
    final adm = _admission(j, p2, entree2, 'A1 LIT2', 'Pneumopathie aiguë', 'Fièvre, toux et douleur thoracique');
    _surveillanceSejour(j, adm, entree2, DateTime.utc(2026, 11, 7, 11), traitement: 'Antibiothérapie injectable, oxygénothérapie à la demande');
    j.planifier(DateTime.utc(2026, 11, 7, 9), () {
      _factureSejour(j, j.parId('admissions', adm['id'])!, DateTime.utc(2026, 11, 7, 9), 3, regler: false);
    });
  });
}

// --------------------------------------------------------------------------------------------------------------------------------------------
// Le bloc opératoire
// --------------------------------------------------------------------------------------------------------------------------------------------

class _Intervention {
  const _Intervention(this.jour, this.heure, this.intitule, this.diagnostic, this.anesthesie, this.codeActe, this.operateurSpecialite, this.cpa, this.compte);
  final DateTime jour;
  final int heure;
  final String intitule;
  final String diagnostic;
  final String anesthesie;
  final String codeActe;
  final String operateurSpecialite;
  final bool cpa;
  final String compte;
}

/// Cinq interventions : la césarienne vient de la maternité (même patiente, même jour), les quatre autres sont des gestes de petite chirurgie.
void planifierBloc(Jeu j, List<PatientJeu> pats, Set<String> exclus, CesarienneJeu cesar) {
  final t = j.t;
  final interventions = <(_Intervention, PatientJeu)>[
    (
      _Intervention(DateTime.utc(cesar.quand.year, cesar.quand.month, cesar.quand.day), cesar.quand.hour, 'Césarienne segmentaire transversale',
          'Présentation du siège, bassin limite à terme', 'Rachianesthésie', 'ACCDC', 'Gynécologie', true,
          'Installation en décubitus dorsal avec billot. Asepsie et champage. Laparotomie sous-ombilicale transversale, hystérotomie segmentaire, extraction d’un nouveau-né vivant, délivrance dirigée, hystérorraphie en un plan, fermeture plan par plan. Perte sanguine estimée à 500 ml. Pansement.'),
      cesar.patient
    ),
  ];
  PatientJeu choisir(DateTime avant) {
    final p = chercherPatient(pats, t, ageMin: 16, ageMax: 65, creeAvant: avant, exclus: exclus) ?? chercherPatient(pats, t, creeAvant: avant, exclus: exclus)!;
    exclus.add(p.id);
    return p;
  }

  final autres = [
    _Intervention(DateTime.utc(2026, 9, 3), 9, 'Incision et drainage d’un abcès fessier', 'Abcès fessier collecté', 'Anesthésie générale', 'ABCG', 'Chirurgie', true,
        'Installation en décubitus latéral. Asepsie et champage. Incision de 4 cm au point le plus déclive, évacuation de pus franc, lavage au sérum, exploration digitale, mise en place d’une mèche. Pas d’incident per-opératoire. Pansement.'),
    _Intervention(DateTime.utc(2026, 9, 29), 10, 'Drainage d’un abcès de l’aisselle', 'Abcès axillaire', 'Anesthésie générale', 'ABCM', 'Chirurgie', true,
        'Installation en décubitus dorsal, bras en abduction. Asepsie et champage. Incision et évacuation du pus, lavage, mèche. Pas d’incident per-opératoire. Pansement.'),
    _Intervention(DateTime.utc(2026, 10, 15), 11, 'Extraction d’un corps étranger du pied', 'Corps étranger sous-cutané du pied', 'Anesthésie locale', 'EXTO', 'Chirurgie', false,
        'Anesthésie locale à la lidocaïne. Asepsie. Incision de 1 cm, extraction d’une épine, lavage, fermeture. Pas d’incident. Pansement.'),
    _Intervention(DateTime.utc(2026, 11, 3), 14, 'Suture d’une plaie de la main', 'Plaie délabrante de la main', 'Anesthésie locale', 'SUT', 'Chirurgie', false,
        'Anesthésie locale. Parage de la plaie, lavage abondant, suture en points séparés. Pas d’incident. Pansement, sérovaccination antitétanique.'),
  ];
  for (final i in autres) {
    interventions.add((i, choisir(DateTime(i.jour.year, i.jour.month, i.jour.day))));
  }
  interventions.sort((a, b) => instant(a.$1.jour, a.$1.heure).compareTo(instant(b.$1.jour, b.$1.heure)));

  final prestataires = j.lire('prestataires');
  Fiche prest(String s) => prestataires.firstWhere((x) => x['specialite'] == s);
  final blocPatients = <String>{};
  for (final (iv, pp) in interventions) {
    final quand = instant(iv.jour, iv.heure);
    final operateur = prest(iv.operateurSpecialite);
    j.planifier(quand, () {
      final pat = pp.fiche(j);
      blocPatients.add(pp.id);
      // La consultation pré-anesthésique, la veille ou le jour même (jamais bloquante).
      String? refCpa;
      if (iv.cpa) {
        final n = j.ctx.collection('cpa').toutes.length + 1;
        final reserves = iv.codeActe == 'ABCM';
        final f = j.ajouter(
            'cpa',
            {
              'statut': 'actif',
              'reference': 'CPA-2026-${pad(n, 4)}',
              'date': jourDe(quand.subtract(const Duration(days: 1))),
              'patientId': pat['id'],
              'patient': '${pat['nom']} ${pat['prenom']}',
              'patientCode': pat['code'],
              'asa': t.choisir(['I', 'I', 'II']),
              'mallampati': t.choisir(['I', 'II']),
              'technique': iv.anesthesie,
              'antecedentsAnesthesiques': 'Aucun',
              'allergies': '${pat['allergies']}'.isEmpty ? 'Aucune connue' : '${pat['allergies']}',
              'jeuneConsigne': true,
              'conclusion': reserves ? d.blocConclusionsCpa[1] : d.blocConclusionsCpa[0],
              'observations': reserves ? 'Hypertension artérielle à équilibrer avant l’intervention : tension à contrôler le matin même.' : '',
              'anesthesiste': medecinNom,
              'fictif': true,
            },
            'CPA',
            largeur: 4);
        if (d.blocRefusCpa(f) != null) throw StateError('CPA refusée : ${d.blocRefusCpa(f)!.message}');
        refCpa = '${f['reference']}';
      }
      // Le compte rendu opératoire (moteur de construction du bloc).
      final cro = j.ajouter(
          'crOperatoires',
          d.blocConstruireCro(
            {
              'statut': 'actif',
              'dateOperation': jourDe(quand),
              'patientCode': pat['code'],
              'nip': pat['code'],
              'diagnosticPeroperatoire': iv.diagnostic,
              'intervention': iv.intitule,
              'anesthesie': iv.anesthesie,
              'cro': iv.compte,
              'operateurId': operateur['id'],
              'aideOperateurId': infirmierSoignantId,
              'anesthesisteId': medecinSoignantId,
              'fictif': true,
            },
            patient: pat,
            nomSoignant: (id) => id == operateur['id'] ? '${operateur['nom']}' : (id == infirmierSoignantId ? infirmierNom : medecinNom),
            toutes: j.ctx.collection('crOperatoires').toutes,
          ),
          'CRO');
      // Les deux check-listes, séparées : avant l'incision, avant la sortie de salle.
      for (final (moment, labels, h) in [('entree', d.blocChecklistEntree, quand.subtract(const Duration(minutes: 15))), ('sortie', d.blocChecklistSortie, quand.add(const Duration(minutes: 50)))]) {
        final lignes = d.blocLignesChecklist(labels, {for (var k = 0; k < labels.length; k++) 'it$k': true});
        final nk = j.ctx.collection('checklistsBloc').toutes.length + 1;
        j.ajouter(
            'checklistsBloc',
            {
              'statut': 'actif',
              'reference': 'CKL-${pad(nk, 4)}',
              'moment': moment,
              'dateHeure': iso8601(h),
              'patientId': pat['id'],
              'patient': '${pat['nom']} ${pat['prenom']}',
              'responsableId': infirmierSoignantId,
              'responsable': infirmierNom,
              'items': lignes.items,
              'coches': lignes.coches,
              'total': lignes.total,
            },
            'CKL',
            largeur: 4);
      }
      // Le compte rendu d'anesthésie : induction, entretien, réveil (« aucun incident » s'écrit).
      if (iv.cpa) {
        final nr = j.ctx.collection('crAnesthesie').toutes.length + 1;
        j.ajouter(
            'crAnesthesie',
            {
              'statut': 'actif',
              'reference': 'CRA-2026-${pad(nr, 4)}',
              'patientId': pat['id'],
              'patient': '${pat['nom']} ${pat['prenom']}',
              'patientCode': pat['code'],
              'dateOperation': jourDe(quand),
              'croReference': cro['reference'],
              'technique': iv.anesthesie,
              'agents': iv.anesthesie == 'Rachianesthésie' ? 'Bupivacaïne hyperbare 10 mg, sérum physiologique, ocytocine après extraction' : 'Kétamine, diazépam, sérum physiologique, antalgique',
              'heureInduction': '${pad(quand.hour, 2)}:${pad(quand.minute, 2)}',
              'heureFin': '${pad(quand.hour + 1, 2)}:${pad(quand.minute, 2)}',
              'incidents': 'Aucun incident',
              'surveillancePerop': 'Constantes relevées toutes les cinq minutes, stables. Remplissage par sérum physiologique.',
              'heureArriveeReveil': '${pad(quand.hour + 1, 2)}:${pad(quand.minute + 5 > 59 ? 59 : quand.minute + 5, 2)}',
              'etatReveil': 'Réveil calme, constantes stables, douleur contrôlée.',
              'decisionSortie': d.blocDecisionsReveil[0],
              'anesthesiste': medecinNom,
              'fictif': true,
              'cpaReference': refCpa,
            },
            'CRA',
            largeur: 4);
      }
      // La caisse : l'acte tarifé au catalogue (RG-09), encaissé au guichet. La césarienne est facturée avec l'accouchement par la maternité.
      if (iv.codeActe != 'ACCDC') {
        final assure = d.carteValide(pat, j.lire('couverturesAssurance'), jourDe(quand));
        final pr = d.csTarifPrix(j.stock, iv.codeActe, assure);
        final libelle = j.lire('catalogueTarifs').firstWhere((x) => x['code'] == iv.codeActe)['libelle'];
        final l = d.ligneSaisie(nature: 'acte', designation: '$libelle — ${iv.intitule}', quantite: 1, prixUnitaire: pr.montant ?? 0, secteur: 'Chirurgie');
        final pieces = j.caisse.emettre(
            patient: pat, lignes: [l], quand: quand.add(const Duration(minutes: 90)), type: 'Chirurgie', complement: {'crOperatoireId': cro['id']});
        for (final f in pieces) {
          j.caisse.encaisser('${f['id']}', mode: t.choisir(modesReglement), quand: quand.add(const Duration(minutes: 100)));
        }
      }
    });
  }
}
