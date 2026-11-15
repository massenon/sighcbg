// LES 200 CONSULTATIONS DU JEU : 110 visites de médecine du travail (45 embauche, 55 périodiques, 10 reprise) par le seul médecin, 60 consultations de
// médecine générale, 30 de spécialité tenues par les vacataires fictifs du socle. Quarante dossiers de consultation complets (anamnèse, antécédents, examen
// par appareil, constantes datées) passent par le MOTEUR DE CONSULTATION du domaine : dossier, puis fiche, puis prescription, puis caisse, dans cet ordre.
//
// Rien ne s'écrit à la main là où un moteur existe : le dossier (`csEnregistrerDossier`), la fiche (`csEnregistrerFiche`), la prescription
// (`csPrescrire`, une facture globale aux lignes payables), la prescription de soins (`csPrescrireSoins`, `csAdministrer`), l'émission (`emettreFacture`)
// et l'encaissement (`encaisser`). Aucun médicament n'est prescrit : les ventes de pharmacie relèvent du sous-lot stock.
import 'package:sigh_domaine/sigh_domaine.dart' as d;
import 'package:sigh_poste/donnees/magasin.dart';

import 'clinique_base.dart';
import 'clinique_patients.dart';
import 'clinique_scenarios.dart';

/// Un passage d'un patient à la clinique : le jour, le tableau clinique, ce qui sera prescrit, ce que la caisse en fera.
class Passage {
  Passage(this.quand, this.pat, this.nature, this.scenario);
  DateTime quand;
  final PatientJeu pat;

  /// `mt_embauche`, `mt_periodique`, `mt_reprise`, `mg` ou `spe`.
  final String nature;
  String scenario;
  Fiche? prestataire;
  bool dossier = false;
  bool releve = false;
  List<String> analyses = [];
  List<String> imagerie = [];
  bool impaye = false;
  bool reliquat = false;
  bool certificat = false;
  String? avoir;
  bool get mt => nature.startsWith('mt_');
}

int ageA(PatientJeu p, DateTime t) {
  var a = t.year - p.naissance.year;
  if (t.month < p.naissance.month || (t.month == p.naissance.month && t.day < p.naissance.day)) a--;
  return a;
}

const List<String> modesReglement = ['especes', 'especes', 'especes', 'mtn', 'mtn', 'moov', 'tpe'];

// --------------------------------------------------------------------------------------------------------------------------------------------
// Le plan : QUI vient QUAND, pour QUOI
// --------------------------------------------------------------------------------------------------------------------------------------------

/// Le plan des 200 consultations. Les jours sont ceux de la fenêtre (01/08 au 06/11/2026, la clinique ouvre six jours sur sept).
List<Passage> planifierPassages(Jeu j, List<PatientJeu> pats) {
  final t = j.t;
  final jours = j.ctx.joursOuvres(du: DateTime(2026, 8, 1), au: DateTime(2026, 11, 6));
  DateTime jourApres(DateTime depuis, {int marge = 0}) {
    final ok = [for (final x in jours) if (!x.isBefore(depuis)) x];
    if (ok.isEmpty) return jours.last;
    // La marge est un nombre de jours ouvrés minimal avant la première date possible.
    final base = marge < ok.length ? marge : ok.length - 1;
    return ok[t.entre(base, ok.length - 1)];
  }

  DateTime horaire(DateTime jour) => instant(jour, t.entre(8, 15), t.entre(0, 5) * 10);

  final passages = <Passage>[];

  // --- Médecine du travail : 80 premières visites (45 embauche, 35 périodiques), 20 périodiques et 10 reprises de suite ---
  final salaries = [for (final p in pats) if (p.groupe == 'salarie') p];
  final ordreSalaries = t.melanger(salaries);
  final premieres = <Passage>[];
  for (var i = 0; i < ordreSalaries.length; i++) {
    final p = ordreSalaries[i];
    final jour = jours.firstWhere((x) => !x.isBefore(p.creation));
    // La première visite a lieu au plus tard trois jours ouvrés après l'ouverture du dossier.
    final apres = [for (final x in jours) if (!x.isBefore(jour)) x];
    final jv = apres[t.entre(0, apres.length < 4 ? apres.length - 1 : 3)];
    premieres.add(Passage(horaire(jv), p, i < 45 ? 'mt_embauche' : 'mt_periodique', 'MT'));
  }
  passages.addAll(premieres);
  final suivis = [for (final x in premieres) if (x.quand.isBefore(DateTime.utc(2026, 9, 25))) x];
  final choisis = t.melanger(suivis).take(30).toList();
  if (choisis.length < 30) throw StateError('Pas assez de salariés visités avant le 25/09 pour 30 visites de suite (${choisis.length}).');
  for (var i = 0; i < 30; i++) {
    final base = choisis[i];
    final decalage = t.entre(25, 55);
    var jv = jours.firstWhere((x) => !x.isBefore(DateTime(base.quand.year, base.quand.month, base.quand.day + decalage)), orElse: () => jours.last);
    if (jv.isAfter(DateTime(2026, 11, 6))) jv = DateTime(2026, 11, 6);
    passages.add(Passage(horaire(jv), base.pat, i < 20 ? 'mt_periodique' : 'mt_reprise', 'MT'));
  }
  // Un certificat d'aptitude demandé par le salarié (pièce certifiante, hors convention) pour 40 % des visites.
  for (final p in passages.where((x) => x.mt)) {
    p.certificat = t.chance(0.4);
  }

  // --- Médecine générale : 60 passages ---
  const mg = <(String, int)>[
    ('S1', 9), ('S2', 6), ('S3', 7), ('S4', 5), ('S5', 5), ('S6', 5), ('S7', 3), ('S8', 4), ('S9', 5), ('S10', 3), ('S14', 4), ('S17', 2), ('S18', 1), ('S20', 1),
  ];
  // L'imagerie de médecine générale : 11 examens, attachés aux tableaux qui l'appellent.
  final imagerieMg = <String, List<List<String>>>{
    'S5': [['IMG-ECHO-ABD'], ['IMG-ECHO-ABD'], ['IMG-ECHO-ABD']],
    'S3': [['IMG-RX-THO'], ['IMG-RX-THO'], ['IMG-RX-THO']],
    'S8': [['IMG-RX-RAC']],
    'S17': [['IMG-ECHO-ABP'], ['IMG-TDM-ABP']],
    'S18': [['IMG-TDM-THO']],
    'S20': [['IMG-RX-MEM']],
  };
  final mgPassages = <Passage>[];
  for (final (code, n) in mg) {
    final sc = scenarios[code]!;
    final imgs = [...(imagerieMg[code] ?? const <List<String>>[])];
    for (var i = 0; i < n; i++) {
      final p = _patientPour(j, pats, sc, jourApres: jourApres, horaire: horaire);
      final pa = Passage(p.$2, p.$1, 'mg', code);
      if (i < imgs.length) pa.imagerie = imgs[i];
      mgPassages.add(pa);
    }
  }
  // RG-09 montré : les deux patients à carte d'assurance EXPIRÉE viennent à la clinique après l'expiration (la pièce reste intégralement à leur charge) ;
  // celui dont la carte expire en septembre est aussi venu AVANT (la même pièce y était couverte à la date).
  final remplaces = <int>{};
  void remplacer(PatientJeu pat, DateTime debut, DateTime fin) {
    final i = [
      for (var k = 0; k < mgPassages.length; k++)
        if (!remplaces.contains(k) && const ['S1', 'S4', 'S6', 'S14', 'S9'].contains(mgPassages[k].scenario) && mgPassages[k].imagerie.isEmpty) k
    ].first;
    remplaces.add(i);
    final ok = [for (final x in jours) if (!x.isBefore(debut) && !x.isAfter(fin)) x];
    mgPassages[i] = Passage(horaire(t.choisir(ok)), pat, 'mg', mgPassages[i].scenario);
  }

  for (final pp in pats) {
    final exp = '${pp.fiche(j)['carteExpiration'] ?? ''}';
    if (!pp.assure || exp.compareTo('2026-11-07') >= 0) continue;
    final dExp = DateTime.parse(exp);
    final creation = pp.creation;
    final apres = DateTime(dExp.year, dExp.month, dExp.day + 1);
    if (creation.isBefore(DateTime(dExp.year, dExp.month, dExp.day - 1))) {
      remplacer(pp, creation, DateTime(dExp.year, dExp.month, dExp.day - 1));
    }
    remplacer(pp, apres.isBefore(creation) ? creation : apres, DateTime(2026, 11, 6));
    remplacer(pp, apres.isBefore(creation) ? creation : apres, DateTime(2026, 11, 6));
  }
  passages.addAll(mgPassages);

  // --- Spécialités : 30 passages chez les vacataires du socle ---
  final prestataires = j.lire('prestataires');
  Fiche prest(String specialite) => prestataires.firstWhere((x) => x['specialite'] == specialite);
  const spe = <(String, String, int, List<List<String>>)>[
    ('Cardiologie', 'S22', 5, [['IMG-ECG'], ['IMG-ECG']]),
    ('Endocrinologie', 'S7', 3, []),
    ('Neurologie', 'S16', 1, [['IMG-TDM-CER']]),
    ('Neurologie', 'S26', 2, []),
    ('Pédiatrie', 'S23', 4, []),
    ('Ophtalmologie', 'S24', 2, []),
    ('Urologie', 'S11', 3, [['IMG-ECHO-PRO'], ['IMG-ECHO-PRO']]),
    ('Rhumatologie', 'S13', 1, [['IMG-IRM-GEN']]),
    ('Rhumatologie', 'S19', 1, [['IMG-IRM-RAC']]),
    ('Rhumatologie', 'S8', 1, [['IMG-RX-RAC']]),
    ('Kinésithérapie', 'S25', 1, []),
    ('Gynécologie', 'S12', 2, [['IMG-ECHO-PEL'], ['IMG-ECHO-PEL']]),
    ('Gynécologie', 'S15', 2, [['IMG-MAM-DEP'], ['IMG-MAM-DIA']]),
    ('Chirurgie', 'S9', 2, []),
  ];
  final spePassages = <Passage>[];
  for (final (specialite, code, n, imgs) in spe) {
    final sc = scenarios[code]!;
    for (var i = 0; i < n; i++) {
      final p = _patientPour(j, pats, sc, jourApres: jourApres, horaire: horaire);
      final pa = Passage(p.$2, p.$1, 'spe', code)..prestataire = prest(specialite);
      if (i < imgs.length) pa.imagerie = imgs[i];
      spePassages.add(pa);
    }
  }
  passages.addAll(spePassages);

  // --- Qui a un dossier : les 23 passages d'imagerie, puis 17 autres tirés au sort (40 en tout) ---
  final nonMt = [...mgPassages, ...spePassages];
  final imageries = [for (final p in nonMt) if (p.imagerie.isNotEmpty) p];
  if (imageries.length != 23) throw StateError('23 examens d\'imagerie attendus hors maternité, ${imageries.length} planifiés.');
  for (final p in imageries) {
    p.dossier = true;
  }
  final autres = t.melanger([for (final p in nonMt) if (!p.dossier) p]);
  for (final p in autres.take(17)) {
    p.dossier = true;
  }
  // Un relevé de constantes à l'accueil pour tous les dossiers et pour 40 % des autres passages.
  for (final p in nonMt) {
    p.releve = p.dossier || t.chance(0.4);
  }

  // --- Les analyses : 80 demandes en tout (78 ici, 2 en maternité sont comptées avec les autres : le total est vérifié par le test) ---
  final prescripteurs = [for (final p in nonMt) if (scenarios[p.scenario]!.analyses.isNotEmpty) p];
  final aMaternite = 4;
  final cible = 80 - aMaternite;
  final base = cible ~/ prescripteurs.length;
  var reste = cible % prescripteurs.length;
  const complement = ['L24', 'L14', 'L10', 'L09', 'L16', 'L05', 'L47', 'L03', 'L07'];
  for (final p in t.melanger(prescripteurs)) {
    final n = base + (reste > 0 ? 1 : 0);
    if (reste > 0) reste--;
    final liste = [...scenarios[p.scenario]!.analyses];
    for (final c in complement) {
      if (liste.length >= n) break;
      if (!liste.contains(c)) liste.add(c);
    }
    p.analyses = liste.take(n).toList();
  }

  // --- La caisse : ~5 % de pièces laissées à encaisser, 3 reliquats, 3 avoirs ---
  final recentes = [for (final p in nonMt) if (p.quand.isAfter(DateTime.utc(2026, 9, 30))) p];
  final recImg = t.melanger([for (final p in recentes) if (p.imagerie.isNotEmpty) p]);
  final recAutres = t.melanger([for (final p in recentes) if (p.imagerie.isEmpty) p]);
  for (final p in [...recImg.take(2), ...recAutres.take(4)]) {
    p.impaye = true;
  }
  // Les reliquats : trois prescriptions d'au moins deux prestations dues par le patient (patient non assuré, pour que la part due soit celle des lignes).
  final avecBilan = [
    for (final p in nonMt)
      if (!p.impaye && p.analyses.length + p.imagerie.length >= 2 && p.quand.isAfter(DateTime.utc(2026, 9, 15))) p
  ];
  for (final p in t.melanger(avecBilan).take(3)) {
    p.reliquat = true;
  }
  // Trois impayés de plus parmi les certificats et les visites (les pièces de médecine du travail sont couvertes à 100 % : rien à encaisser).
  final cert = [for (final p in passages.where((x) => x.mt && x.certificat && x.quand.isAfter(DateTime.utc(2026, 10, 10)))) p];
  for (final p in t.melanger(cert).take(3)) {
    p.impaye = true;
  }
  // Les avoirs : sur trois consultations payées, quelques jours après (avant le 21 du mois : la facture mère du mois n'est émise que le 5 suivant et
  // une fille consolidée ne se corrige plus). Les patients non assurés d'abord : l'avoir leur est remboursé en espèces.
  final eligibles = [
    for (final p in nonMt)
      if (!p.impaye && !p.reliquat && p.quand.isBefore(DateTime.utc(2026, 10, 21)) && p.quand.day <= 20 && p.analyses.isEmpty && p.imagerie.isEmpty) p
  ];
  final nonAssures = t.melanger([for (final p in eligibles) if (!p.pat.assure) p]);
  final assures = t.melanger([for (final p in eligibles) if (p.pat.assure) p]);
  final motifs = ['Erreur de facturation — consultation facturée deux fois', 'Prestation non réalisée', 'Geste commercial décidé par la Direction'];
  for (final (i, p) in [...nonAssures, ...assures].take(3).indexed) {
    p.avoir = motifs[i];
  }
  // Les résultats récents : douze passages avec analyses et huit avec imagerie ont lieu dans les derniers jours (04 au 06/11), pour que le circuit
  // du laboratoire et celui de l'imagerie montrent des examens encore en cours.
  final derniers = [DateTime(2026, 11, 4), DateTime(2026, 11, 5), DateTime(2026, 11, 6)];
  final libres = [for (final p in nonMt) if (!p.impaye && !p.reliquat && p.avoir == null) p];
  final avecAnalyses = t.melanger([for (final p in libres) if (p.analyses.isNotEmpty && p.imagerie.isEmpty) p]).take(12);
  final avecImagerie = t.melanger([for (final p in libres) if (p.imagerie.isNotEmpty)p]).take(8);
  for (final p in [...avecAnalyses, ...avecImagerie]) {
    p.quand = horaire(t.choisir(derniers));
  }
  return passages..sort((a, b) => a.quand.compareTo(b.quand));
}

/// Choisit un patient compatible avec le tableau (sexe, âge) et une date postérieure à l'ouverture de son dossier.
(PatientJeu, DateTime) _patientPour(Jeu j, List<PatientJeu> pats, Scenario sc,
    {required DateTime Function(DateTime, {int marge}) jourApres, required DateTime Function(DateTime) horaire}) {
  final t = j.t;
  final ref = DateTime.utc(2026, 10, 1);
  var candidats = [
    for (final p in pats)
      if ((sc.sexe == null || p.sexe == sc.sexe) && ageA(p, ref) >= sc.ageMin && ageA(p, ref) <= sc.ageMax) p
  ];
  if (candidats.isEmpty) candidats = [...pats];
  final p = t.choisir(candidats);
  final jour = jourApres(p.creation);
  return (p, horaire(jour));
}

// --------------------------------------------------------------------------------------------------------------------------------------------
// L'exécution d'un passage
// --------------------------------------------------------------------------------------------------------------------------------------------

/// `m2-consultations` : la session qui agit pour le moteur (le médecin, au secteur de la médecine générale).
const _session = d.SessionCs(role: 'medecin', fonction: 'medecin', secteur: 'MÉDECINE GÉNÉRALE');

Map<String, Object?> releveValeurs(Jeu j, PatientJeu pp, DateTime quand, Scenario? sc) {
  final t = j.t;
  final age = ageA(pp, quand);
  final fievre = sc?.fievre ?? false;
  final hta = sc?.hta ?? false;
  final temp = fievre ? 38.0 + t.entre(2, 16) / 10 : 36.3 + t.entre(0, 11) / 10;
  final sys = hta ? t.entre(15, 19) : t.entre(10, 14);
  final dia = hta ? t.entre(9, 11) : t.entre(6, 9);
  final double poids;
  final int taille;
  if (age < 15) {
    poids = (age * 2.4 + 8 + t.entre(0, 30) / 10).roundToDouble();
    taille = (age * 6 + 78 + t.entre(0, 8)).clamp(60, 175);
  } else {
    poids = (pp.sexe == 'F' ? t.entre(50, 88) : t.entre(58, 98)).toDouble();
    taille = pp.sexe == 'F' ? t.entre(155, 175) : t.entre(163, 188);
  }
  final imc = (poids / ((taille / 100) * (taille / 100)) * 10).round() / 10;
  return {
    'temperature': (temp * 10).round() / 10,
    'tensionSys': sys,
    'tensionDia': dia,
    'tension': '$sys/$dia',
    'pouls': fievre ? t.entre(86, 112) : t.entre(62, 94),
    'fr': age < 15 ? t.entre(20, 28) : t.entre(14, 20),
    'spo2': t.entre(95, 99),
    'poids': poids,
    'taille': taille,
    'imc': imc,
  };
}

Fiche poserReleve(Jeu j, PatientJeu pp, Fiche pat, DateTime quand, Scenario? sc) {
  final v = releveValeurs(j, pp, quand, sc);
  final n = j.ctx.collection('constantes').toutes.length + 1;
  final h = quand.hour;
  return j.ajouter(
      'constantes',
      {
        'id': 'CST${pad(n, 5)}',
        'statut': 'actif',
        'reference': 'CST-${pad(n, 5)}',
        'patientCode': pat['code'],
        'patientId': pat['id'],
        'patient': '${pat['nom']} ${pat['prenom']}',
        'dateHeure': '${jourDe(quand)}T${pad(h, 2)}:${pad(quand.minute, 2)}',
        'moment': h < 11 ? 'matin' : (h < 15 ? 'midi' : 'soir'),
        ...v,
        'releveePar': infirmierNom,
        'origine': 'accueil',
      },
      'CST');
}

/// L'examen par appareil, au format du moteur : un objet par appareil, quatre temps chacun.
Map<String, Object?> examensPhysiques(Scenario sc) => {
      for (final e in sc.appareils.entries)
        e.key: {
          'inspection': e.value[0],
          'palpation': e.value[1],
          'percussion': e.value[2],
          'auscultation': e.value[3],
        }
    };

String _heureH(DateTime t) => '${pad(t.hour, 2)}h${pad(t.minute, 2)}';

/// Le dossier de consultation qu'enregistre le médecin : tout ce que la fiche récapitulera.
Map<String, Object?> dossierValeurs(Jeu j, Passage p, Fiche pat, Scenario sc, Fiche? releve, DateTime quand) {
  final t = j.t;
  final age = ageA(p.pat, quand);
  final femme = p.pat.sexe == 'F';
  final v = <String, Object?>{
    'patientCode': pat['code'],
    'typeVenue': t.pondere({'premiere': 5, 'controle': 3, 'suivi': 2, 'urgence': 1}),
    'motifVenue': sc.motif,
    'dateArrivee': jourDe(quand),
    'heureArrivee': _heureH(quand),
    'soignant': p.prestataire != null ? '${p.prestataire!['nom']}' : medecinNom,
    'recuPar': infirmierNom,
    'histoire': sc.histoire,
    'traitementEnCours': '${pat['antecedents']}' == 'Hypertension artérielle' ? 'Inhibiteur calcique' : '',
    'ant_medicaux': '${pat['antecedents'] ?? 'Aucun antécédent notable'}',
    'ant_chirurgicaux': 'Aucun',
    'ant_gyneco_obstetricaux': femme && age >= 15 ? 'Ménarche à 13 ans, cycles réguliers' : 'Sans objet',
    'allergies': '${pat['allergies'] ?? ''}',
    'allergiesMedicamenteuses': '${pat['allergies'] ?? ''}',
    'statutVaccinal': t.choisir(['À jour', 'À jour', 'Incomplet', 'Inconnu']),
    'groupeSanguin': '${pat['groupeSanguin'] ?? ''}',
    'electrophoreseHb': t.pondere({'AA': 70, 'AS': 25, 'AC': 5}),
    'etatGeneral': sc.fievre ? 'moyen' : 'bon',
    'etatGeneralPrecision': '',
    'examensPhysiques': examensPhysiques(sc),
  };
  if (femme && age >= 15 && age <= 50) {
    final parite = t.entre(0, 4);
    v['antecedentsObstetricaux'] = {
      'gestite': parite + t.entre(0, 1),
      'parite': parite,
      'enfantsVivants': parite,
      'faussesCouches': 0,
      'enfantsDecedes': 0,
      'pathologies': <Object?>[],
    };
  }
  if (releve != null) {
    // Les valeurs mesurées par le médecin lui-même, voisines de celles de l'accueil (le dossier garde la copie de l'accueil en plus).
    v['temperature'] = releve['temperature'];
    v['tension'] = releve['tension'];
    v['pouls'] = releve['pouls'];
    v['spo2'] = releve['spo2'];
    v['poids'] = releve['poids'];
    v['taille'] = releve['taille'];
    v['imc'] = releve['imc'];
  }
  return v;
}

String _prescripteurNom(Passage p) => p.prestataire != null ? '${p.prestataire!['nom']}' : medecinNom;

/// L'exécution complète d'un passage.
void executerPassage(Jeu j, Passage p) {
  if (p.mt) {
    _visiteTravail(j, p);
  } else {
    _consultation(j, p);
  }
}

/// Encaisse (ou laisse à encaisser) les pièces d'un passage. [maxLignes] : un règlement partiel ne règle que les premières lignes dues.
void _regler(Jeu j, Passage p, Fiche facture, DateTime quand, {bool partiel = false}) {
  final f = j.parId('factures', facture['id'])!;
  if (d.nombreOuZero(f['partPatient']) <= 0 || f['statutPaiement'] == 'soldee') return;
  if (p.impaye) return;
  final mode = j.t.choisir(modesReglement);
  if (partiel) {
    final dues = [for (final l in (f['lignes'] as List).cast<Map>()) if (l['statutPaiement'] != 'paye' && d.nombreOuZero(l['partPatient']) > 0) '${l['id']}'];
    if (dues.length >= 2) {
      j.caisse.encaisser('${f['id']}', lignes: dues.take(dues.length - 1).toList(), mode: mode, quand: quand);
      return;
    }
  }
  j.caisse.encaisser('${f['id']}', mode: mode, quand: quand);
}

/// La ligne d'honoraires d'une consultation, au tarif du catalogue (RG-09 : tarif assuré si la carte est valide à la date).
Map<String, Object?> ligneHonoraires(Jeu j, Fiche pat, String codeTarif, String designation, DateTime quand,
    {String categorie = 'consultation', String? acteCode}) {
  final assure = d.carteValide(pat, j.lire('couverturesAssurance'), jourDe(quand));
  final pr = d.csTarifPrix(j.stock, codeTarif, assure);
  if (pr.montant == null) throw StateError('Tarif absent pour $codeTarif : $designation.');
  final l = d.ligneSaisie(nature: 'acte', designation: designation, quantite: 1, prixUnitaire: pr.montant!, secteur: 'Médecine générale');
  return {...l, 'categorie': categorie, if (acteCode != null) 'acteCode': acteCode};
}

// --- La médecine du travail -----------------------------------------------------------------------------------------------------------------

const _natures = {
  'mt_embauche': ('MT-EMB', 'MT01', 'Visite médicale d’embauche', 'embauche'),
  'mt_periodique': ('MT-PER', 'MT02', 'Visite médicale périodique', 'periodique'),
  'mt_reprise': ('MT-REP', 'MT03', 'Visite médicale de reprise', 'reprise'),
};

void _visiteTravail(Jeu j, Passage p) {
  final t = j.t;
  final quand = p.quand;
  j.horloge = quand;
  final pat = p.pat.fiche(j);
  final (codeTarif, acte, libelle, nature) = _natures[p.nature]!;
  final entreprise = j.parId('souscripteurs', p.pat.entrepriseId)!;
  final aptitude = t.pondere({'Apte': 82, 'Apte avec aménagement de poste': 12, 'Inapte temporaire': 6});
  final consultations = j.ctx.collection('consultations');
  final ref = d.referenceSerie('C', 5, consultations.toutes);
  final consult = j.ajouter(
      'consultations',
      {
        'statut': 'terminee',
        'reference': ref,
        'patientId': pat['id'],
        'patient': '${pat['nom']} ${pat['prenom']}',
        'patientCode': pat['code'],
        'medecinId': medecinSoignantId,
        'medecin': medecinNom,
        'date': iso8601(quand),
        'motif': '$libelle — ${entreprise['nom']}',
        'diagnostic': aptitude == 'Apte' ? 'Apte au poste de travail' : aptitude,
        'type': 'Médecine du travail',
        'natureVisite': nature,
        'entrepriseId': entreprise['id'],
        'entreprise': '${entreprise['nom']}',
        'poste': '${pat['profession'] ?? ''}',
        'aptitude': aptitude,
        'tarif': 0,
        'fictif': true,
        'source': 'Visite fictive de démonstration',
      },
      'CON');
  // Les constantes de la visite : relevées par l'infirmier avant le médecin.
  if (t.chance(0.5)) {
    poserReleve(j, p.pat, pat, DateTime.utc(quand.year, quand.month, quand.day, quand.hour, 0).subtract(const Duration(minutes: 25)), null);
  }
  // La visite et la fiche d'aptitude passent par la caisse : couvertes à 100 % par la convention de l'entreprise (carte valide à la date, RG-09).
  final lignes = [
    ligneHonoraires(j, pat, codeTarif, libelle, quand, categorie: 'medecine_travail', acteCode: acte),
    ligneHonoraires(j, pat, 'MT-FAP', 'Fiche d’aptitude', quand, categorie: 'fiche_aptitude', acteCode: 'MT04'),
  ];
  final pieces = j.caisse.emettre(
      patient: pat, lignes: lignes, quand: quand, type: 'Médecine du travail', complement: {'consultationId': consult['id'], 'entrepriseId': entreprise['id']});
  j.maj('consultations', consult['id'], {
    'factureId': pieces.first['id'],
    'factureNumero': pieces.first['numero'],
    'ficheAptitude': {
      'reference': 'FA-${pad(j.ctx.collection('consultations').toutes.where((c) => c['ficheAptitude'] != null).length + 1, 4)}/26',
      'conclusion': aptitude,
      'entreprise': '${entreprise['nom']}',
      'valableJusqua': jourDe(DateTime.utc(quand.year + 1, quand.month, quand.day)),
    },
    'tarif': d.nombreOuZero(pieces.first['montantTTC']),
  });
  for (final f in pieces) {
    _regler(j, p, f, quand.add(const Duration(minutes: 12)));
  }
  if (p.certificat) delivrerPiece(j, p.pat, 'TPC04', quand.add(const Duration(minutes: 20)), impaye: p.impaye, medecin: medecinNom);
}

// --- Les pièces certifiantes, par la caisse ------------------------------------------------------------------------------------------------

/// Délivre une pièce certifiante (`pieces`) : numérotée par le registre annuel du sigle, facturée par `patFacturerPiece` (seul SOS couvre un certificat),
/// encaissée au guichet sauf si [impaye].
Fiche? delivrerPiece(Jeu j, PatientJeu pp, String typeId, DateTime quand,
    {bool impaye = false, required String medecin, String? contenu, String? remisA}) {
  j.horloge = quand;
  final pat = pp.fiche(j);
  final type = d.patTypesPiece.firstWhere((x) => x.id == typeId);
  final pieces = j.ctx.collection('pieces');
  final num = d.patNumeroter(type, pieces.toutes, quand.year);
  final pr = type.tarifCode == null ? null : d.csTarifPrix(j.stock, type.tarifCode, false);
  final entreeTarif = j.lire('catalogueTarifs').where((x) => x['code'] == type.tarifCode).firstOrNull;
  final r = d.patFacturerPiece(
    patient: pat,
    montant: pr?.montant,
    libelle: type.libelle,
    reference: num.reference,
    acteCode: type.tarifCode,
    assurable: entreeTarif?['assurable'],
    couvertures: j.lire('couverturesAssurance'),
    nbFactures: j.ctx.collection('factures').toutes.length,
    nouvelId: (prefixe) => prefixe == 'FAC' ? j.nouvelId('factures', 'FAC') : j.nouvelId('taches', 'TCH'),
    date: quand,
  );
  String? factureId, factureNumero;
  if (r != null) {
    final fac = {...r.facture};
    if (j.caisse.mecefActif) {
      fac['statutMecef'] = 'en_attente';
    } else {
      fac.remove('statutMecef');
    }
    final ins = j.ajouter('factures', fac, 'FAC');
    j.ajouter('taches', r.tache, 'TCH');
    factureId = '${ins['id']}';
    factureNumero = '${ins['numero']}';
    j.caisse.constaterCreance(ins, quand);
    if (!impaye) j.caisse.encaisser(factureId, mode: j.t.choisir(modesReglement), quand: quand.add(const Duration(minutes: 6)));
    j.maj('factures', factureId, {'pieceRef': num.reference});
  }
  return j.ajouter(
      'pieces',
      {
        'statut': 'actif',
        'numero': num.numero,
        'annee': num.annee,
        'reference': num.reference,
        'sigle': type.sigle,
        'libelle': type.libelle,
        'direction': type.direction,
        'typeId': type.id,
        'patientId': pat['id'],
        'patient': '${pat['nom']} ${pat['prenom']}',
        'patientCode': pat['code'],
        'medecin': medecin,
        'dateDelivrance': jourDe(quand),
        'contenu': contenu ?? 'Je soussigné certifie avoir examiné l’intéressé(e) à la date indiquée.',
        'remisA': remisA ?? 'L’intéressé(e)',
        'montant': pr?.montant ?? 0,
        'couverture': d.patCouverturePiece(entreeTarif?['assurable']),
        if (factureId != null) 'factureId': factureId,
        if (factureNumero != null) 'factureNumero': factureNumero,
        'fictif': true,
      },
      'PCE');
}

// --- La consultation de médecine générale et de spécialité --------------------------------------------------------------------------------

void _consultation(Jeu j, Passage p) {
  final t = j.t;
  final quand = p.quand;
  final sc = scenarios[p.scenario]!;
  final pat = p.pat.fiche(j);
  final nom = _prescripteurNom(p);
  final spe = p.nature == 'spe';
  final jour = jourDe(quand);
  j.horloge = quand;

  // 1. Les constantes de l'accueil, relevées avant le médecin.
  Fiche? releve;
  if (p.releve) releve = poserReleve(j, p.pat, pat, quand.subtract(const Duration(minutes: 30)), sc);

  // 2. Le dossier (moteur), puis la fiche (moteur) qui en est le récapitulatif et la SEULE porte de prescription.
  Fiche? consult;
  d.ResultatPrescription? presc;
  final pathologies = [sc.pathologie];
  final fiche = {
    'patientCode': pat['code'],
    'medecin': nom,
    'date': iso8601(quand.add(const Duration(minutes: 25))),
    'diagnostic': sc.diagnostic,
    'pathologies': pathologies,
    'resumeSyndromique': sc.resume,
    'hypotheses': '',
    'traitementEmblee': sc.traitement,
    'conduite': sc.traitement,
    'orientation': 'domicile',
    'tarif': 0,
    'medicaments': const <Object?>[],
    'analyses': p.analyses,
    'imagerie': p.imagerie,
    'urgent': false,
  };
  if (p.dossier) {
    // Un dossier encore « en attente du laboratoire » d'une venue précédente se clôt à la nouvelle venue : un seul dossier ouvert par patient.
    for (final o in j.ctx.collection('dossiersConsultation').actives.where((x) => x['patientCode'] == pat['code'] && x['etat'] == 'attente_labo')) {
      j.maj('dossiersConsultation', o['id'], {'etat': 'cloture', 'cloturLe': iso8601(quand)});
    }
    j.horloge = quand.add(const Duration(minutes: 8));
    final dossier = d.csEnregistrerDossier(j.stock, dossierValeurs(j, p, pat, sc, releve, quand), null, _session).dossier;
    j.horloge = quand.add(const Duration(minutes: 25));
    final r = d.csEnregistrerFiche(j.stock, {...fiche, 'dossierConsultationId': dossier['id']}, _session);
    consult = r.consultation;
    presc = r.prescription;
  } else {
    final ref = d.referenceSerie('C', 5, j.ctx.collection('consultations').toutes);
    final cv = releve ?? const <String, Object?>{};
    consult = j.ajouter(
        'consultations',
        {
          'statut': 'terminee',
          'reference': ref,
          'patientId': pat['id'],
          'patient': '${pat['nom']} ${pat['prenom']}',
          'patientCode': pat['code'],
          'medecinId': spe ? null : medecinSoignantId,
          'medecin': nom,
          'date': iso8601(quand),
          'type': 'Consultation',
          'motif': sc.motif,
          'diagnostic': sc.diagnostic,
          'resumeSyndromique': sc.resume,
          'traitementEmblee': sc.traitement,
          'conduite': sc.traitement,
          'pathologies': pathologies,
          'pathologiePrincipale': sc.pathologie,
          'pathologiesLibelles': [sc.diagnostic],
          'notifiable': sc.pathologie == 'PAL-S',
          'temperature': cv['temperature'],
          'tension': cv['tension'],
          'poids': cv['poids'],
          'fc': cv['pouls'],
          'orientation': 'domicile',
          'orientationLabel': d.csLibelleOrientation('domicile'),
          'tarif': 0,
        },
        'CON');
    if (p.analyses.isNotEmpty || p.imagerie.isNotEmpty) {
      j.horloge = quand.add(const Duration(minutes: 20));
      presc = d.csPrescrire(
          j.stock,
          {
            'patientCode': pat['code'],
            'medecin': nom,
            'diagnostic': sc.diagnostic,
            'date': iso8601(quand.add(const Duration(minutes: 20))),
            'consultationId': consult['id'],
            'indication': sc.diagnostic,
            'origine': 'consultation',
            'medicaments': const <Object?>[],
            'analyses': p.analyses,
            'imagerie': p.imagerie,
          },
          _session);
      j.maj('consultations', consult['id'], {
        'ordonnanceId': presc.ordonnance['id'],
        'ordonnanceNumero': presc.ordonnance['numero'],
        'factureId': presc.facture['id'],
        'factureNumero': presc.facture['numero'],
      });
    }
  }
  final consultId = '${consult['id']}';

  // 3. La pièce de prescription (analyses, imagerie) : la créance de l'assureur est constatée à l'émission.
  Fiche? facturePrescription;
  if (presc != null) {
    facturePrescription = j.parId('factures', presc.facture['id']);
    j.caisse.constaterCreance(facturePrescription!, quand.add(const Duration(minutes: 30)));
  }

  // 4. La prescription de soins (moteur) : adressée à la salle de soins, réglée avec les honoraires.
  Fiche? soins;
  if (sc.soins.isNotEmpty && t.chance(spe ? 0.2 : 0.75)) {
    j.horloge = quand.add(const Duration(minutes: 28));
    final nb = t.entre(1, sc.pathologie == 'GEA' || sc.pathologie == 'PAL-S' ? 3 : 2);
    soins = d.csPrescrireSoins(j.stock, {
      'patientCode': pat['code'],
      'prescripteurId': medecinSoignantId,
      'prescripteur': nom,
      'origine': 'consultation',
      'secteurDestinataire': 'salle_soins',
      'modalite': 'ambulatoire',
      'indication': sc.diagnostic,
      'actes': [for (final c in sc.soins) {'code': c, 'nbAdministrations': nb}],
      'date': iso8601(quand.add(const Duration(minutes: 28))),
    });
  }

  // 5. Les honoraires (et les soins) : une pièce émise par le moteur d'émission.
  j.horloge = quand.add(const Duration(minutes: 35));
  final code = spe ? 'CONS-SPE' : 'CONS-GEN';
  final libelle = spe ? 'Consultation de spécialiste — ${p.prestataire!['specialite']}' : 'Consultation généraliste';
  final lignes = [ligneHonoraires(j, pat, code, libelle, quand)];
  if (soins != null) {
    final assure = d.carteValide(pat, j.lire('couverturesAssurance'), jour);
    for (final l in (soins['lignes'] as List).cast<Map>()) {
      final pr = d.csTarifPrix(j.stock, l['acteCode'], assure);
      final prix = pr.montant ?? 0;
      final lg = d.ligneSaisie(nature: 'acte', designation: '${l['libelle']}', quantite: l['nbAdministrations'] ?? 1, prixUnitaire: prix, secteur: 'Soins et observation');
      lignes.add({...lg, 'acteCode': l['acteCode']});
    }
  }
  final pieces = j.caisse.emettre(
      patient: pat,
      lignes: lignes,
      quand: quand.add(const Duration(minutes: 35)),
      type: soins != null ? 'Consultation et soins' : 'Consultation',
      complement: {'consultationId': consultId, if (soins != null) 'prescriptionSoinsId': soins['id']});
  j.maj('consultations', consultId, {
    'factureHonorairesId': pieces.first['id'],
    'factureHonorairesNumero': pieces.first['numero'],
    'tarif': d.nombreOuZero(lignes.first['prixUnitaire']),
  });
  if (soins != null) j.maj('prescriptions', soins['id'], {'factureId': pieces.first['id'], 'factureNumero': pieces.first['numero']});

  // 6. Le guichet : les honoraires d'abord, puis la prescription (ou un règlement partiel).
  final guichet = quand.add(const Duration(minutes: 42));
  for (final f in pieces) {
    _regler(j, p, f, guichet);
  }
  if (facturePrescription != null) {
    _regler(j, p, facturePrescription, guichet.add(const Duration(minutes: 4)), partiel: p.reliquat);
  }

  // 7. Les administrations de soins, une fois la prescription réglée (salle de soins, infirmier).
  if (soins != null && j.parId('prescriptions', soins['id'])!['statutPaiement'] == 'payee') {
    final pres = j.parId('prescriptions', soins['id'])!;
    final lignesSoins = (pres['lignes'] as List).cast<Map>();
    for (var i = 0; i < lignesSoins.length; i++) {
      final n = d.nombreOuZero(lignesSoins[i]['nbAdministrations']).toInt();
      for (var k = 0; k < n; k++) {
        final quandAdm = quand.add(Duration(days: k, hours: 1, minutes: i * 10));
        if (quandAdm.isAfter(DateTime.utc(2026, 11, 7, 11))) break;
        final ligne = i;
        j.planifier(quandAdm, () {
          final r = d.csAdministrer(j.stock, pres['id'],
              ligneIndex: ligne,
              executantId: infirmierSoignantId,
              dateHeure: iso8601(quandAdm),
              observation: k == 0 ? 'Sans incident' : '');
          if (!r.ok) throw StateError('Administration refusée : ${r.motif}');
        });
      }
    }
  }

  // 8. L'avoir éventuel : la Direction rectifie quelques jours plus tard.
  if (p.avoir != null) {
    final cle = pieces.first['id'];
    final motif = p.avoir!;
    j.planifier(quand.add(Duration(days: t.entre(2, 5), hours: 1)), () {
      final assure = d.nombreOuZero(j.parId('factures', cle)!['partAssurance']) > 0;
      j.caisse.avoir(
          factureId: '$cle', motif: motif, quand: j.horloge, remboursement: assure ? 'creance' : 'especes', lignesIndex: [0]);
    });
  }
}
