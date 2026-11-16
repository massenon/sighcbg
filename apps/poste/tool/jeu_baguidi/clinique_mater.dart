// LA MATERNITÉ (M4) : six femmes suivies en consultation prénatale (la grille de la CPN, visite par visite), leurs dossiers obstétricaux, trois accouchements
// (deux eutociques, une césarienne), trois naissances avec leurs mesures aux bornes du rapport officiel du 27/08/2026, les partogrammes et les consultations
// postnatales. Les honoraires (CPN, accouchement) passent par la caisse ; une échographie obstétricale et quatre analyses prénatales passent par la
// prescription du moteur de consultation.
//
// La clinique n'a pas de sage-femme au personnel : le prestataire de la CPN et l'accoucheur sont le médecin. Rien n'est inventé pour combler ce vide.
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import 'clinique_base.dart';
import 'clinique_hospi.dart';
import 'clinique_patients.dart';
import 'clinique_soins.dart';

class _Grossesse {
  _Grossesse(this.pat, this.visites, this.sa0, {this.accouchement, this.cesarienne = false});
  final PatientJeu pat;
  final List<DateTime> visites;

  /// Terme (semaines d'aménorrhée) à la première visite.
  final int sa0;
  final DateTime? accouchement;
  final bool cesarienne;
  String id = '';
  String dossierId = '';
  String ddr = '';
}

DateTime _prochainJourOuvre(List<DateTime> jours, DateTime depuis) => jours.firstWhere((x) => !x.isBefore(DateTime(depuis.year, depuis.month, depuis.day)), orElse: () => jours.last);

/// Planifie la maternité. Rend la césarienne (patiente, date) pour le bloc.
CesarienneJeu planifierMaternite(Jeu j, List<PatientJeu> pats, Set<String> exclus) {
  final t = j.t;
  final jours = j.ctx.joursOuvres(du: DateTime(2026, 8, 1), au: DateTime(2026, 11, 6));
  final femmes = [for (final p in pats) if (p.sexe == 'F' && ageA(p, DateTime.utc(2026, 10, 1)) >= 19 && ageA(p, DateTime.utc(2026, 10, 1)) <= 38 && !exclus.contains(p.id) && !p.creation.isAfter(DateTime(2026, 9, 30))) p]
    ..sort((a, b) => a.creation.compareTo(b.creation));
  if (femmes.length < 6) throw StateError('Moins de six femmes de 19 à 38 ans pour la maternité (${femmes.length}).');
  // Les trois premières patientes accouchent dans la fenêtre ; les trois suivantes sont encore enceintes au 07/11.
  final accouchees = femmes.take(3).toList();
  final enceintes = femmes.skip(3).toList();
  final gr = <_Grossesse>[];
  final limite = DateTime.utc(2026, 10, 30);
  for (final p in accouchees) {
    final f0 = _prochainJourOuvre(jours, DateTime(p.creation.year, p.creation.month, p.creation.day + t.entre(0, 2)));
    var sa0 = t.entre(29, 33);
    var acc = DateTime.utc(f0.year, f0.month, f0.day).add(Duration(days: (39 - sa0) * 7 + t.entre(0, 5)));
    while (acc.isAfter(limite)) {
      sa0++;
      acc = DateTime.utc(f0.year, f0.month, f0.day).add(Duration(days: (39 - sa0) * 7 + t.entre(0, 5)));
    }
    final visites = <DateTime>[DateTime(f0.year, f0.month, f0.day)];
    while (true) {
      final cible = visites.last.add(Duration(days: 21 + t.entre(0, 3)));
      if (!cible.isBefore(DateTime(acc.year, acc.month, acc.day - 3))) break;
      visites.add(_prochainJourOuvre(jours, cible));
    }
    gr.add(_Grossesse(p, visites, sa0, accouchement: DateTime.utc(acc.year, acc.month, acc.day, t.entre(1, 20), t.entre(0, 5) * 10)));
  }
  // La césarienne est celle qui accouche en dernier.
  gr.sort((a, b) => a.accouchement!.compareTo(b.accouchement!));
  final cesarienneIdx = 2;
  final cesar = _Grossesse(gr[cesarienneIdx].pat, gr[cesarienneIdx].visites, gr[cesarienneIdx].sa0, accouchement: gr[cesarienneIdx].accouchement, cesarienne: true);
  gr[cesarienneIdx] = cesar;
  for (final p in enceintes.take(3)) {
    final f0 = _prochainJourOuvre(jours, DateTime(p.creation.year, p.creation.month, p.creation.day + t.entre(0, 2)));
    final sa0 = t.entre(14, 24);
    final visites = <DateTime>[DateTime(f0.year, f0.month, f0.day)];
    while (true) {
      final cible = visites.last.add(Duration(days: 28 + t.entre(0, 3)));
      if (cible.isAfter(DateTime(2026, 11, 6))) break;
      visites.add(_prochainJourOuvre(jours, cible));
    }
    gr.add(_Grossesse(p, visites, sa0));
  }
  for (final g in gr) {
    exclus.add(g.pat.id);
  }

  // Les deux prescriptions prénatales : écho obstétricale + quatre analyses (deux femmes enceintes).
  final presc = <int, (List<String>, List<String>)>{};
  var cible = 0;
  for (var i = 3; i < gr.length; i++) {
    final visiteIdx = gr[i].visites.length > 1 ? 1 : 0;
    presc[i * 10 + visiteIdx] = cible == 0 ? (['L17', 'L21'], ['IMG-ECHO-OBS']) : (['L24', 'L14'], ['IMG-ECHO-OBS']);
    cible++;
    if (cible == 2) break;
  }

  for (final (gi, g) in gr.indexed) {

    // La première visite ouvre le dossier obstétrical et la grossesse ; les suivantes s'y ajoutent.
    final premiere = instant(g.visites.first, t.entre(8, 11), t.entre(0, 5) * 10);
    // Mêmes visites pour toute la durée : on construit les fiches d'un bloc à la première visite.
    j.planifier(premiere, () => _ouvrirDossierEtGrossesse(j, g, gi));
    for (final (vi, v) in g.visites.indexed) {
      final qv = vi == 0 ? premiere : instant(v, t.entre(8, 14), t.entre(0, 5) * 10);
      final bilan = presc[gi * 10 + vi];
      j.planifier(qv.add(const Duration(minutes: 1)), () => _visiteCpn(j, g, vi, qv, bilan));
    }
    if (g.accouchement != null) {
      j.planifier(g.accouchement!, () => _accouchement(j, g, gi));
    }
  }
  return CesarienneJeu(cesar.pat, cesar.accouchement!);
}

String _terme(int sa) => '$sa SA';

// --------------------------------------------------------------------------------------------------------------------------------------------

void _ouvrirDossierEtGrossesse(Jeu j, _Grossesse g, int gi) {
  final t = j.t;
  final pat = g.pat.fiche(j);
  final f0 = g.visites.first;
  final age = ageA(g.pat, f0);
  // DDR déduite du terme à la première visite : la DPA se déduit de la DDR (280 jours), jamais saisie à part.
  final ddr = DateTime.utc(f0.year, f0.month, f0.day).subtract(Duration(days: g.sa0 * 7 + t.entre(0, 5)));
  g.ddr = jourDe(ddr);
  final dpa = d.matDpaDepuisDdr(g.ddr)!;
  final parite = t.entre(0, 3);
  final nDos = j.ctx.collection('dossiersObstetricaux').toutes.length + 1;
  final dossier = j.ajouter(
      'dossiersObstetricaux',
      {
        'statut': 'actif',
        'numeroDossier': d.matNumeroDossier(j.ctx.collection('dossiersObstetricaux').toutes, f0),
        'dateEntree': jourDe(f0),
        'patientId': pat['id'],
        'patient': '${pat['nom']} ${pat['prenom']}',
        'patientCode': pat['code'],
        'age': age,
        'taille': (1.5 + t.entre(0, 25) / 100),
        'profession': '${pat['profession'] ?? 'Ménagère'}',
        'nationalite': 'Béninoise',
        'quartier': pat['quartier'],
        'telephone': pat['telephone'],
        'personneContact': '',
        'telephoneContact': '',
        'referee': false,
        'refereePar': '',
        'procreateurNom': '',
        'procreateurProfession': '',
        'procreateurGs': '',
        'procreateurSerologie': 'Négative',
        'maladies': 'Néant',
        'traitements': 'Néant',
        'allergies': '${pat['allergies']}'.isEmpty ? 'Non connues' : '${pat['allergies']}',
        'gestite': parite + 1,
        'parite': parite,
        'avortements': 0,
        'enfantsVivants': parite,
        'enfantsDecedes': 0,
        'transfusions': 0,
        'ddr': g.ddr,
        'dpa': dpa,
        'facteurs': g.cesarienne ? {'taille': false, 'cesarienne': false, 'age_max': age > 35} : <String, Object?>{},
        'examens': {
          'gs': '${pat['groupeSanguin']}'.replaceAll(RegExp(r'[+-]'), ''),
          'rh': '${pat['groupeSanguin']}'.endsWith('-') ? 'Négatif' : 'Positif',
          'coombs': 'Négatif',
          'electrophorese': 'AA',
          'hb': '${(10.5 + t.entre(0, 25) / 10).toStringAsFixed(1)} g/dl',
          'hematocrite': '${t.entre(31, 38)} %',
          'plaquettes': '${t.entre(190, 330)} G/l',
          'tpha': 'Négatif',
          'vdrl': 'Négatif',
          'hiv1': 'Négatif',
          'hiv2': 'Négatif',
          'toxo_igg': 'Négatif',
          'toxo_igm': 'Négatif',
          'rubeole_igg': 'Négatif',
          'rubeole_igm': 'Négatif',
          'hepatiteB': 'Négatif',
          'ecbu': 'Stérile',
          'glycemie': '0.${t.entre(78, 95)} g/l',
          'gp75': 'Normale',
        },
        'vat': {'VAT1': jourDe(ddr.add(const Duration(days: 120))), 'VAT2': jourDe(ddr.add(const Duration(days: 150)))},
        'droits': {for (var k = 0; k < 10; k++) '$k': true},
        'plan': {for (var k = 0; k < 9; k++) '$k': k != 1 && k != 3},
        'classesMeres': ['${g.sa0 < 27 ? '2ème' : '3ème'} trimestre'],
        'infoPF': 'Counseling prévu à la CPoN',
        'referenceCPN': '',
        'referenceAccouchement': '',
        'sageFemme': medecinNom,
        'statutDossier': 'suivi',
        'fictif': true,
      },
      'DOB',
      largeur: 4);
  g.dossierId = '${dossier['id']}';
  final nGro = j.ctx.collection('grossesses').toutes.length + 1;
  final gro = j.ajouter(
      'grossesses',
      {
        'statut': 'actif',
        'reference': 'CPN-${pad(nGro, 4)}',
        'patientId': pat['id'],
        'patient': '${pat['nom']} ${pat['prenom']}',
        'patientCode': pat['code'],
        'ddr': g.ddr,
        'dpa': dpa,
        'termeSA': g.sa0,
        'groupeSanguin': pat['groupeSanguin'],
        'sageFemme': medecinNom,
        'gar': g.cesarienne,
        'milda': true,
        'mebendazole': true,
        'vat': 'VAT2',
        'fer': true,
        'folates': true,
        'sp': <Object?>[],
        'visites': <Object?>[],
        'dossierObstetricalId': dossier['id'],
        'dossierObstetricalNumero': dossier['numeroDossier'],
        'fictif': true,
      },
      'GRO',
      largeur: 4);
  g.id = '${gro['id']}';
  j.maj('dossiersObstetricaux', dossier['id'], {'referenceCPN': gro['reference']});
  if (gi == 3) {
    // Une attestation de grossesse, pièce certifiante passée par la caisse (non couverte, hors SOS).
    delivrerPiece(j, g.pat, 'TPC01', j.horloge.add(const Duration(minutes: 40)), medecin: medecinNom, contenu: 'Je soussigné certifie que l’intéressée est enceinte de ${g.sa0} semaines d’aménorrhée.', remisA: 'L’intéressée');
  }
  nDos.toString();
}

void _visiteCpn(Jeu j, _Grossesse g, int vi, DateTime quand, (List<String>, List<String>)? bilan) {
  final t = j.t;
  final pat = g.pat.fiche(j);
  final dpaSem = quand.difference(DateTime.parse(g.ddr)).inDays ~/ 7;
  final sa = dpaSem;
  final poids = (g.pat.sexe == 'F' ? 56 + t.entre(0, 18) + vi * 2 : 60).toDouble();
  final taille = 1.5 + t.entre(0, 22) / 100;
  final imc = (poids / (taille * taille) * 10).round() / 10;
  final visite = {
    'n': vi + 1,
    'date': jourDe(quand),
    'arrivee': '${pad(quand.hour, 2)}h${pad(quand.minute > 0 ? quand.minute - 1 : 0, 2)}',
    'heureCpnr': '${pad(quand.hour, 2)}h${pad(quand.minute + 12 > 59 ? 59 : quand.minute + 12, 2)}',
    'prestataire': '$medecinNom — médecin',
    'terme': _terme(sa),
    'echographie': bilan != null ? 'Prescrite ce jour' : (vi == 0 ? 'Non faite' : 'Non refaite'),
    'plaintes': t.choisir(['Aucune', 'Brûlures gastriques', 'Lombalgies', 'Nausées matinales', 'Pesanteur pelvienne']),
    'ta': '${t.entre(10, 13)}/${t.entre(6, 8)}',
    'pouls': t.entre(68, 92),
    'temperature': (36.5 + t.entre(0, 7) / 10).toStringAsFixed(1),
    'muqueuses': t.choisir(['Colorées', 'Colorées', 'Légèrement pâles']),
    'omi': 'Absents',
    'pb': '${t.entre(24, 29)} cm',
    'conscience': 'Bonne',
    'poids': poids,
    'imc': imc,
    'urines': 'A− / N− / S− / L−',
    'albumine': '—',
    'sucre': '—',
    'seins': 'Sans particularité',
    'inspection': g.cesarienne ? 'Cicatrice de césarienne' : 'RAS',
    'hu': (sa * 0.95 + t.entre(0, 2)).round(),
    'presentation': sa < 30 ? 'Non fixée' : (g.cesarienne ? 'Siège' : 'Céphalique'),
    'pointsUreteraux': 'Libres',
    'bdcf': t.entre(126, 158),
    'vulve': 'Saine',
    'speculum': vi == 0 ? 'Col sain, glaire limpide' : 'Non fait',
    'toucherVaginal': vi == 0 ? 'Col long postérieur fermé' : 'Non fait',
    'bassin': g.cesarienne && sa > 33 ? 'Bassin limite à l’appréciation clinique' : (vi == 0 ? 'Cliniquement normal' : 'Non refait'),
    'sp': vi == 0 ? 'Non due' : 'SP${vi < 4 ? vi : 3} — 3 cp supervisés',
    'deparasitage': vi == 1,
    'fer': true,
    'foldine': true,
    'milda': true,
    'conseilsNutrition': true,
    'signesDanger': true,
    'counselingPF': vi >= 2,
    'methodePF': '',
    'diagnostic': 'Grossesse de $sa SA évolutive',
    'conduite': 'Poursuite du suivi',
    'rdvCpn': g.visites.length > vi + 1 ? jourDe(g.visites[vi + 1]) : '',
    'rdvClasse': '',
    'rechercheActive': '',
  };
  final gro = j.parId('grossesses', g.id)!;
  final liste = [...(gro['visites'] as List).cast<Map<String, Object?>>(), visite];
  j.maj('grossesses', g.id, {'visites': liste, 'termeSA': sa});
  // Le suivi : une ligne à jour par grossesse (dernière visite).
  final suivi = j.ctx.collection('suiviMaternite').toutes.where((x) => x['grossesseId'] == g.id).firstOrNull;
  final fiche = {
    'statut': 'actif',
    'patientId': pat['id'],
    'patient': '${pat['nom']} ${pat['prenom']}',
    'patientCode': pat['code'],
    'date': jourDe(quand),
    'dpa': d.matDpaDepuisDdr(g.ddr),
    'termeSA': sa,
    'poids': poids,
    'cpn': vi + 1,
    'groupeSanguin': pat['groupeSanguin'],
    'risque': g.cesarienne ? 'À risque' : 'Standard',
    'sageFemme': medecinNom,
    'observations': 'Grossesse évolutive, bruits du cœur fœtal perçus',
    'grossesseId': g.id,
  };
  if (suivi == null) {
    j.ajouter('suiviMaternite', fiche, 'SUI');
  } else {
    j.maj('suiviMaternite', suivi['id'], fiche);
  }

  // Les honoraires : consultation prénatale, tarif du catalogue (RG-09) ; encaissés au guichet.
  final assure = d.carteValide(pat, j.lire('couverturesAssurance'), jourDe(quand));
  final pr = d.csTarifPrix(j.stock, 'CONS-PRE', assure);
  final l = d.ligneSaisie(nature: 'acte', designation: 'Consultation prénatale', quantite: 1, prixUnitaire: pr.montant!, secteur: 'Maternité');
  final pieces = j.caisse.emettre(patient: pat, lignes: [l], quand: quand.add(const Duration(minutes: 20)), type: 'Maternité', complement: {'grossesseId': g.id});
  for (final f in pieces) {
    j.caisse.encaisser('${f['id']}', mode: t.choisir(modesReglement), quand: quand.add(const Duration(minutes: 28)));
  }
  // La prescription prénatale éventuelle : échographie obstétricale + analyses, une facture globale encaissée.
  if (bilan != null) {
    j.horloge = quand.add(const Duration(minutes: 15));
    final r = d.csPrescrire(
        j.stock,
        {
          'patientCode': pat['code'],
          'medecin': medecinNom,
          'diagnostic': 'Grossesse évolutive — bilan prénatal',
          'date': iso8601(quand.add(const Duration(minutes: 15))),
          'indication': 'Surveillance de la grossesse',
          'origine': 'maternite',
          'medicaments': const <Object?>[],
          'analyses': bilan.$1,
          'imagerie': bilan.$2,
        },
        const d.SessionCs(role: 'medecin', fonction: 'medecin', secteur: 'MATERNITÉ'));
    final fac = j.parId('factures', r.facture['id'])!;
    j.caisse.constaterCreance(fac, quand.add(const Duration(minutes: 16)));
    j.caisse.encaisser('${fac['id']}', mode: t.choisir(modesReglement), quand: quand.add(const Duration(minutes: 30)));
  }
}

// --------------------------------------------------------------------------------------------------------------------------------------------

void _accouchement(Jeu j, _Grossesse g, int gi) {
  final t = j.t;
  final quand = g.accouchement!;
  final pat = g.pat.fiche(j);
  final cesarienne = g.cesarienne;
  final nAcc = j.ctx.collection('accouchements').toutes.length + 1;
  final hemorragie = false;
  final acc = j.ajouter(
      'accouchements',
      {
        'statut': 'actif',
        'reference': 'ACC-${pad(nAcc, 4)}',
        'patientId': pat['id'],
        'patient': '${pat['nom']} ${pat['prenom']}',
        'patientCode': pat['code'],
        'dateHeure': iso8601(quand),
        'type': cesarienne ? 'Césarienne' : 'Eutocique',
        'voie': cesarienne ? 'Haute' : 'Voie basse',
        'actes': cesarienne ? <Object?>[] : (t.chance(0.4) ? ['Épisiotomie'] : <Object?>[]),
        'sageFemme': medecinNom,
        'duree': cesarienne ? '1 h' : '${t.entre(5, 11)} h',
        'complications': 'Aucune',
        'issue': 'Favorable',
        'modeDelivrance': cesarienne ? 'Dirigée au bloc' : 'Assistée (GATPA)',
        'gestesDelivrance': cesarienne ? ['Ocytocine 10 UI après extraction'] : ['Ocytocine 10 UI à la 1ʳᵉ minute', 'Traction contrôlée du cordon'],
        'hemorragie': hemorragie,
        'quantiteSang': cesarienne ? 500 : t.entre(150, 320),
        'placenta': {
          'cotyledons': true,
          'cupule': true,
          'insertionCordon': 'Centrale',
          'grandCote': t.entre(18, 23),
          'petitCote': t.entre(15, 18),
          'longueurCordon': t.entre(48, 58),
          'poidsPlacenta': t.entre(480, 620),
          'faceMaternelle': 'Cotylédons complets, pas de rétention',
          'faceFoetale': 'Membranes complètes, insertion appréciée',
        },
        'femmeReferee': false,
        'femmeDecedee': false,
        'nnReference': false,
        'nnDecede': false,
        'grossesseId': g.id,
        'dossierObstetricalId': g.dossierId,
        'fictif': true,
      },
      'ACC',
      largeur: 4);
  // La naissance, aux bornes écrites du rapport officiel (PC 32-38, PT 30-36, Apgar à 5 minutes au moins 7).
  final nNai = j.ctx.collection('naissances').toutes.length + 1;
  final a1 = t.entre(7, 9), a5 = t.entre(8, 10), a10 = 10;
  final garcon = t.chance(0.5);
  final elements = {'coeur': '> 100', 'respiration': 'Normal', 'tonus': 'Normal', 'couleur': 'Rosé', 'reflexe': 'Normal'};
  final nai = j.ajouter(
      'naissances',
      {
        'statut': 'actif',
        'reference': 'NAI-${pad(nNai, 4)}',
        'accouchementId': acc['id'],
        'dateHeure': iso8601(quand),
        'mere': '${pat['nom']} ${pat['prenom']}',
        'mereCode': pat['code'],
        'mereId': pat['id'],
        'sexe': garcon ? 'M' : 'F',
        'poids': (2.9 + t.entre(0, 7) / 10).toStringAsFixed(2),
        'taille': t.entre(48, 52),
        'pc': 33.0 + t.entre(0, 30) / 10,
        'pt': 31.0 + t.entre(0, 30) / 10,
        'apgar1': a1,
        'apgar5': a5,
        'apgar10': a10,
        'reanimation': false,
        'vitK1': true,
        'collyre': true,
        'vpo0': true,
        'bcg': true,
        'hepB0': true,
        'vivant': true,
        'declare': true,
        'apgarDetail': {'1ʳᵉ minute': elements, '5ᵉ minute': elements, '10ᵉ minute': elements},
        'soinsFiche': {'seinPrecoce': true, 'collyre': true, 'vitK1': true, 'examenSystematique': true, 'arv': false, 'carteInfantile': true},
        'elements24h': <Object?>[],
        'grossesseId': g.id,
        'fictif': true,
      },
      'NAI',
      largeur: 4);
  // Le partogramme : surveillance horaire coté, clos à l'accouchement.
  final nPar = j.ctx.collection('partogrammes').toutes.length + 1;
  final debut = quand.subtract(Duration(hours: cesarienne ? 5 : t.entre(5, 8)));
  final nbMesures = cesarienne ? 5 : t.entre(5, 8);
  final mesures = <Map<String, Object?>>[];
  var dil = 4;
  for (var h = 0; h < nbMesures; h++) {
    mesures.add({
      'heure': h,
      'dilatation': dil,
      'descente': (5 - h * 5 ~/ nbMesures).clamp(0, 5),
      'bdf': t.entre(122, 150),
      'contractions': (2 + h ~/ 2).clamp(2, 5),
      'ta': '${t.entre(10, 13)}/${t.entre(6, 8)}',
      'pouls': t.entre(70, 96),
      'liquide': 'C',
      'chevauchement': t.entre(0, 1),
      'descenteCotee': '${(5 - h * 5 ~/ nbMesures).clamp(0, 5)}/5',
      'dureeContractions': h < 2 ? 'courte' : (h < 4 ? 'moyenne' : 'longue'),
      'ocytocine': '',
      'temperature': '36.${t.entre(5, 9)}',
      'urines': '',
    });
    if (dil < 10) dil += t.entre(1, 2);
    if (dil > 10) dil = 10;
  }
  final nPar0 = nPar;
  j.ajouter(
      'partogrammes',
      {
        'statut': 'actif',
        'reference': 'PARTO-${pad(nPar0, 4)}',
        'patientId': pat['id'],
        'patient': '${pat['nom']} ${pat['prenom']}',
        'patientCode': pat['code'],
        'gestite': 2,
        'parite': 1,
        'debut': iso8601(debut),
        'accoucheur': medecinNom,
        'mesures': mesures,
        'rupture': iso8601(debut.add(const Duration(hours: 2))),
        'dilatationFinale': 10,
        'issue': cesarienne ? 'Césarienne pour disproportion foeto-pelvienne' : 'Accouchement eutocique',
        'clos': true,
        'accouchementId': acc['id'],
      },
      'PAR',
      largeur: 4);
  j.maj('dossiersObstetricaux', g.dossierId, {'referenceAccouchement': acc['reference'], 'statutDossier': 'accouche'});
  // Le certificat médical d'accouchement (pièce sans tarif à la grille : aucune facture).
  delivrerPiece(j, g.pat, 'TPC03', quand.add(const Duration(hours: 3)), medecin: medecinNom, contenu: 'Je soussigné certifie que l’intéressée a accouché le ${jourDe(quand)}.', remisA: 'L’intéressée');
  // Les honoraires de l'accouchement : tarif du catalogue (RG-09), encaissés avant la sortie.
  final assure = d.carteValide(pat, j.lire('couverturesAssurance'), jourDe(quand));
  final code = cesarienne ? 'ACCDC' : 'ACCE';
  final pr = d.csTarifPrix(j.stock, code, assure);
  final libelle = j.lire('catalogueTarifs').firstWhere((x) => x['code'] == code)['libelle'];
  final l = d.ligneSaisie(nature: 'acte', designation: '$libelle', quantite: 1, prixUnitaire: pr.montant!, secteur: 'Maternité');
  final pieces = j.caisse.emettre(patient: pat, lignes: [l], quand: quand.add(const Duration(hours: 6)), type: 'Maternité', complement: {'accouchementId': acc['id'], 'grossesseId': g.id});
  for (final f in pieces) {
    j.caisse.encaisser('${f['id']}', mode: t.choisir(modesReglement), quand: quand.add(Duration(hours: cesarienne ? 70 : 22)));
  }
  // Les consultations postnatales : CPoN 1 (J0-J1) puis CPoN 2 (J6-J14) tant que la date est passée.
  for (final (k, type, delai) in [(1, 'cpon1', 1), (2, 'cpon2', 8)]) {
    final dc = instant(DateTime.utc(quand.year, quand.month, quand.day + delai), 10);
    if (dc.isAfter(DateTime.utc(2026, 11, 7, 10))) continue;
    j.planifier(dc, () {
      final n = j.ctx.collection('cpon').toutes.length + 1;
      j.ajouter(
          'cpon',
          {
            'statut': 'actif',
            'reference': 'CPO-${pad(n, 4)}',
            'patientId': pat['id'],
            'patient': '${pat['nom']} ${pat['prenom']}',
            'patientCode': pat['code'],
            'accouchementRef': acc['reference'],
            'date': jourDe(dc),
            'type': type,
            'hemorragieAntePartum': false,
            'hpp': false,
            'examen': 'TA, T°, utérus, lochies, seins — involution normale',
            'supplementation': 'Vit A + Fer/Folates',
            'conseilPF': k == 2,
            'etatNouveauNe': 'Bon état, allaitement établi',
            'sageFemme': medecinNom,
            'fictif': true,
          },
          'CPO',
          largeur: 4);
    });
  }
  nai.toString();
}
