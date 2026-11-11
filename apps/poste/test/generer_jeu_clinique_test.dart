// Les SONDES D'INVARIANTS du sous-lot clinique du jeu de démonstration Baguidi (M1 à M5) : codes patient uniques (RG-01), carte expirée à 100 % à la charge du
// patient (RG-09), chaque facture égale à la somme de ses lignes, chaque encaissement soldant exactement ses lignes, créance de l'assureur au journal, chaque
// pièce comptable équilibrée (RG-10), volumes validés par la Direction, aucun médicament dans les factures de ce sous-lot.
// Le générateur est lancé EN MÉMOIRE (aucune écriture sur le disque).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../tool/generer_jeu_baguidi.dart';

typedef F = Map<String, Object?>;

List<F> lire(Map<String, String> j, String nom) => [for (final f in jsonDecode(j['$nom.json']!) as List) (f as Map).cast<String, Object?>()];
num n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);

void main() {
  final jeu = construireJeu();
  List<F> c(String nom) => lire(jeu, nom);

  final patients = c('patients');
  // Les factures du sous-lot clinique : les ventes de pharmacie au comptoir (sous-lot stock, sans dossier patient) sont écartées.
  final factures = [for (final f in c('factures')) if (f['venteComptoir'] != true) f];
  final ecritures = c('ecritures');
  final consultations = c('consultations');

  test('patients : 120 codes CBG/n/26 uniques, noms uniques, aucun nom réel, téléphones non composables (RG-01)', () {
    expect(patients.length, 120);
    expect([for (final p in patients) p['code']], [for (var i = 1; i <= 120; i++) 'CBG/$i/26']);
    expect(patients.map((p) => '${p['nom']} ${p['prenom']}').toSet().length, 120);
    const reserves = ['BAGUIDI', 'SOKOU', 'SANOUSSI', 'ZI${'ME'}', 'MABOUDOU', 'TOUNGOUH', 'IDOHOU', 'AKONDE'];
    for (final p in patients) {
      expect(reserves.contains(p['nom']), isFalse, reason: '${p['nom']}');
      expect(RegExp(r'^(|00 00 00 00 \d\d)$').hasMatch('${p['telephone']}'), isTrue, reason: '${p['telephone']}');
      expect(p['fictif'], true);
    }
    // Les dates de création croissent avec le code : un code n'est attribué qu'à l'ouverture du dossier.
    final dates = [for (final p in patients) '${p['dateCreation']}'];
    expect(dates, [...dates]..sort());
  });

  test('patients : 80 salariés des six entreprises, 15 assurés NSIA/SUNU/SANLAM dont 2 cartes expirées, 25 de passage', () {
    final souscripteurs = c('souscripteurs').map((s) => s['id']).toSet();
    final salaries = patients.where((p) => p['profession'] != null).toList();
    expect(salaries.length, 80);
    expect(salaries.every((p) => souscripteurs.contains(p['souscripteurId']) && p['employeur'] == p['souscripteur']), isTrue);
    final assures = patients.where((p) => p['typeAssure'] == 'ayant droit').toList();
    expect(assures.length, 15);
    expect(assures.map((p) => p['assureur']).toList()..sort(), [...List.filled(5, 'NSIA'), ...List.filled(5, 'SANLAM'), ...List.filled(5, 'SUNU')]);
    expect(patients.where((p) => p['assureur'] == null).length, 25);
    final expirees = patients.where((p) => p['carteExpiration'] != null && '${p['carteExpiration']}'.compareTo('2026-11-07') < 0).toList();
    expect(expirees.length, 2);
  });

  test('consultations : 200 (110 médecine du travail 45/55/10, 60 générale, 30 de spécialité), tous les praticiens existent au socle', () {
    expect(consultations.length, 200);
    final mt = consultations.where((x) => x['type'] == 'Médecine du travail').toList();
    expect(mt.length, 110);
    expect([for (final k in ['embauche', 'periodique', 'reprise']) mt.where((x) => x['natureVisite'] == k).length], [45, 55, 10]);
    expect(mt.every((x) => x['medecin'] == 'IDOHOU Abraham'), isTrue);
    final prestataires = c('prestataires').map((p) => '${p['nom']}').toSet();
    final personnel = c('personnel').map((p) => '${p['nomComplet']}').toSet();
    final autres = consultations.where((x) => x['type'] != 'Médecine du travail').toList();
    expect(autres.where((x) => x['medecin'] == 'IDOHOU Abraham').length, 60);
    expect(autres.where((x) => prestataires.contains(x['medecin'])).length, 30);
    for (final x in consultations) {
      expect(personnel.contains(x['medecin']) || prestataires.contains(x['medecin']), isTrue, reason: '${x['medecin']}');
    }
    // 200 consultations tenues entre le 01/08 et le 07/11/2026, jamais un dimanche.
    for (final x in consultations) {
      final d = DateTime.parse('${x['date']}');
      expect(d.isBefore(DateTime.utc(2026, 8, 1)) || d.isAfter(DateTime.utc(2026, 11, 7, 12)), isFalse, reason: '${x['date']}');
      expect(d.weekday, isNot(DateTime.sunday), reason: '${x['reference']}');
    }
  });

  test('quarante dossiers de consultation complets, par le moteur : anamnèse, antécédents, examen par appareil, constantes datées', () {
    final d = c('dossiersConsultation');
    expect(d.length, 40);
    for (final x in d) {
      expect('${x['histoire']}', isNotEmpty);
      expect(x['ant_medicaux'], isNotNull);
      expect((x['examensPhysiques'] as Map), isNotEmpty);
      expect(x['constantesAccueil'], isNotNull, reason: 'constantes de l\'accueil copiées, datées');
      expect(['cloture', 'attente_labo'].contains(x['etat']), isTrue);
    }
    // Un seul dossier ouvert (en attente du laboratoire) par patient.
    final ouverts = d.where((x) => x['etat'] == 'attente_labo').map((x) => x['patientCode']).toList();
    expect(ouverts.toSet().length, ouverts.length);
  });

  test('factures : chaque facture égale la somme de ses lignes, répartition assureur / patient cohérente, numéros uniques', () {
    expect(factures.length, inInclusiveRange(330, 370));
    expect(factures.map((f) => f['numero']).toSet().length, factures.length);
    for (final f in factures) {
      final lignes = (f['lignes'] as List).cast<Map>();
      expect(lignes.fold<num>(0, (s, l) => s + n(l['montant'])), n(f['montantTTC']), reason: '${f['numero']}');
      expect(lignes.fold<num>(0, (s, l) => s + n(l['partPatient'])), n(f['partPatient']), reason: '${f['numero']}');
      expect(lignes.fold<num>(0, (s, l) => s + n(l['partAssureur'])), n(f['partAssurance']), reason: '${f['numero']}');
      expect(n(f['partPatient']) + n(f['partAssurance']), n(f['montantTTC']), reason: '${f['numero']}');
      for (final l in lignes) {
        expect(n(l['partPatient']) + n(l['partAssureur']) + n(l['partPersonnel']), n(l['montant']), reason: '${f['numero']} ${l['id']}');
      }
    }
    // Chaque série annuelle suit l'ordre des dates.
    for (final prefixe in ['FN-', 'FP-', 'FC-']) {
      final serie = factures.where((f) => '${f['numero']}'.startsWith(prefixe)).toList()..sort((a, b) => '${a['numero']}'.compareTo('${b['numero']}'));
      expect([for (final f in serie) '${f['date']}'], [for (final f in serie) '${f['date']}']..sort(), reason: prefixe);
    }
  });

  test('encaissements : chaque règlement solde exactement ses lignes ; ~5 % à encaisser, 3 reliquats', () {
    var impayees = 0, partielles = 0;
    for (final f in factures) {
      final lignes = (f['lignes'] as List).cast<Map>();
      final reglees = lignes.where((l) => l['statutPaiement'] == 'paye').toList();
      final dues = reglees.fold<num>(0, (s, l) => s + n(l['partPatient']));
      switch (f['statutPaiement']) {
        case 'soldee':
          expect(reglees.length, lignes.length, reason: '${f['numero']}');
          expect(n(f['montantPaye']), n(f['partPatient']), reason: '${f['numero']}');
          expect(n(f['reliquat']), 0, reason: '${f['numero']}');
        case 'partielle':
          partielles++;
          expect(reglees, isNotEmpty);
          expect(reglees.length, lessThan(lignes.length));
          expect(n(f['montantPaye']), dues, reason: '${f['numero']}');
          expect(n(f['reliquat']), n(f['partPatient']) - dues, reason: '${f['numero']}');
        case 'impayee':
          impayees++;
          expect(reglees, isEmpty, reason: '${f['numero']}');
          expect(n(f['montantPaye']), 0);
          expect(n(f['reliquat']), n(f['partPatient']));
        default:
          fail('statut de règlement inattendu : ${f['statutPaiement']}');
      }
    }
    expect(partielles, 3);
    final aEncaisser = impayees + partielles;
    expect(aEncaisser / factures.length, inInclusiveRange(0.03, 0.07));
  });

  test('RG-09 : une carte expirée donne une pièce à 100 % à la charge du patient ; la même carte, valide à la date, est couverte', () {
    final parId = {for (final p in patients) p['id']: p};
    for (final f in factures) {
      final p = parId[f['patientId']]!;
      final exp = p['carteExpiration'];
      if (exp == null) {
        expect(n(f['partAssurance']), 0, reason: '${f['numero']} : patient non assuré');
        continue;
      }
      final valide = '$exp'.compareTo('${f['date']}') >= 0;
      if (!valide) {
        expect(n(f['partAssurance']), 0, reason: '${f['numero']} : carte expirée le $exp');
        expect(n(f['partPatient']), n(f['montantTTC']), reason: '${f['numero']}');
      }
    }
    for (final p in patients.where((p) => p['carteExpiration'] != null && '${p['carteExpiration']}'.compareTo('2026-11-07') < 0)) {
      final siennes = factures.where((f) => f['patientId'] == p['id']).toList();
      final apres = siennes.where((f) => '${p['carteExpiration']}'.compareTo('${f['date']}') < 0).toList();
      expect(apres, isNotEmpty, reason: '${p['code']} doit montrer RG-09');
      expect(apres.every((f) => n(f['partAssurance']) == 0 && n(f['partPatient']) == n(f['montantTTC'])), isTrue);
    }
    // Celle qui expire le 30/09 est aussi venue AVANT : la pièce d'alors est couverte à 70 %.
    final avant = factures.where((f) => f['patientCode'] == 'CBG/34/26' && '${f['date']}'.compareTo('2026-09-30') <= 0 && n(f['partAssurance']) > 0);
    expect(avant, isNotEmpty);
  });

  test('journal : chaque pièce équilibrée (RG-10), une ligne a un sens, la créance 411 de chaque pièce assurée est passée', () {
    final plan = c('comptes').map((x) => '${x['num']}').toSet();
    final parPiece = <String, List<F>>{};
    for (final e in ecritures) {
      parPiece.putIfAbsent('${e['pieceId']}', () => []).add(e);
      expect(plan.contains('${e['compte']}'), isTrue, reason: 'compte ${e['compte']} absent du plan');
      expect(n(e['debit']) == 0 || n(e['credit']) == 0, isTrue);
      expect(n(e['debit']) + n(e['credit']), greaterThan(0));
      // Brouillon, ou validée : le sous-lot stock et comptabilité valide les pièces d'août et de septembre.
      expect(e['statut'], isIn(['brouillon', 'validee']));
    }
    for (final e in parPiece.entries) {
      final deb = e.value.fold<num>(0, (s, x) => s + n(x['debit']));
      final cre = e.value.fold<num>(0, (s, x) => s + n(x['credit']));
      expect(deb, cre, reason: 'pièce ${e.key}');
    }
    for (final f in factures.where((f) => n(f['partAssurance']) > 0)) {
      final d411 = ecritures.where((e) => e['pieceId'] == f['id'] && e['compte'] == '411110').fold<num>(0, (s, e) => s + n(e['debit']));
      expect(d411, n(f['partAssurance']), reason: '${f['numero']}');
    }
    // Les encaissements : le débit de la caisse (571000) d'une pièce est ce que le patient a payé.
    for (final f in factures) {
      final d571 = ecritures.where((e) => e['pieceId'] == f['id'] && e['compte'] == '571000').fold<num>(0, (s, e) => s + n(e['debit']));
      expect(d571, n(f['montantPaye']), reason: '${f['numero']}');
    }
  });

  test('aucun médicament dans les factures de ce sous-lot (les ventes de pharmacie relèvent du sous-lot stock)', () {
    for (final f in factures) {
      for (final l in (f['lignes'] as List).cast<Map>()) {
        expect(l['categorie'], isNot('medicament'));
        expect(l['produitId'], isNull);
      }
    }
    expect(c('ordonnances').every((o) => (o['medicaments'] as List).isEmpty), isTrue);
    // Les produits relèvent du sous-lot stock : le stock est peuplé, aucune facture de ce sous-lot n'en porte.
  });

  test('avoirs : trois, émis par le moteur, plafonnés à la facture, contre-passation équilibrée ; factures mères du mois rapprochées', () {
    final avoirs = c('avoirs');
    expect(avoirs.length, 3);
    for (final a in avoirs) {
      final f = factures.firstWhere((x) => x['id'] == a['factureId']);
      expect(n(a['montant']), lessThanOrEqualTo(n(f['montantTTC'])));
      expect(n(f['montantAvoirs']), n(a['montant']));
      expect((f['avoirIds'] as List).contains(a['id']), isTrue);
      final lignes = ecritures.where((e) => (a['ecritureIds'] as List).contains(e['id'])).toList();
      expect(lignes.length, 2);
      expect(lignes.fold<num>(0, (s, e) => s + n(e['debit'])), lignes.fold<num>(0, (s, e) => s + n(e['credit'])));
    }
    final meres = c('facturesMere');
    expect(meres.length, 9);
    for (final m in meres) {
      expect((m['controle'] as Map)['totalFilles'], (m['controle'] as Map)['totalFactures']);
      expect((m['controle'] as Map)['totalFactures'], (m['controle'] as Map)['totalLignes']);
      expect(n(m['montantReclame']), greaterThan(0));
    }
  });

  test('analyses : 80 demandes dont 60 rendues, codes NNNNN-AAAA uniques, valeurs aux bornes du socle, circuit prélèvement', () {
    final dem = c('demandesAnalyses');
    expect(dem.length, 80);
    expect(dem.map((x) => x['codeAnalyse']).toSet().length, 80);
    expect(dem.every((x) => RegExp(r'^\d{5}-2026$').hasMatch('${x['codeAnalyse']}')), isTrue);
    final rendues = dem.where((x) => x['etatAnalyse'] == 'valide').toList();
    expect(rendues.length, 60);
    // Une demande non payée reste bloquée et en attente ; une payée ne l'est plus.
    for (final x in dem) {
      if (x['bloqueParPaiement'] == true) {
        expect(x['etatAnalyse'], 'en_attente');
        expect(x['regleLe'], isNull);
      } else {
        expect(x['regleLe'], isNotNull);
      }
    }
    // Chaque demande est portée par une ligne de facture payable qui la désigne.
    for (final x in dem) {
      final f = factures.firstWhere((f) => (f['lignes'] as List).any((l) => (l as Map)['demandeId'] == x['id']));
      expect(f, isNotNull);
    }
    // Les valeurs d'un résultat rendu : chaque variable numérique bornée est dans [min, max] sauf la valeur anormale annoncée.
    final variables = c('variablesLabo');
    final examens = c('examensLabo');
    var verifiees = 0;
    for (final x in rendues.where((x) => x['valeurs'] != null)) {
      final code = examens.firstWhere((e) => x['analyse'].toString().toLowerCase().startsWith(e['designation'].toString().toLowerCase().split(' ').first) || e['code'] == x['analyseCode'], orElse: () => {})['code'];
      if (code == null) continue;
      var hors = 0;
      for (final e in (x['valeurs'] as Map).entries) {
        final v = variables.where((v) => v['examen'] == code && v['code'] == e.key && v['type'] == 'numerique' && v['min'] != null && v['max'] != null).firstOrNull;
        if (v == null || e.value is! num) continue;
        verifiees++;
        if (n(e.value) < n(v['min']) || n(e.value) > n(v['max'])) hors++;
      }
      expect(hors, lessThanOrEqualTo(1), reason: '${x['reference']}');
    }
    expect(verifiees, greaterThan(100));
    // Le circuit : prélevé avant reçu avant saisi avant validé.
    for (final x in rendues) {
      final etapes = [x['regleLe'], x['preleveLe'], x['recuLaboLe'], x['saisiLe'], x['valideTechniqueLe'], x['valideLe']].map((t) => DateTime.parse('$t')).toList();
      for (var i = 1; i < etapes.length; i++) {
        expect(etapes[i].isBefore(etapes[i - 1]), isFalse, reason: '${x['reference']} étape $i');
      }
    }
  });

  test('imagerie : 25 demandes, cinq modalités, quatre états, comptes rendus liés', () {
    final dem = c('demandesImagerie');
    expect(dem.length, 25);
    expect(dem.map((x) => x['modalite']).toSet(), {'echographie', 'radiographie', 'mammographie', 'scanner', 'irm'});
    expect(dem.map((x) => x['statut']).toSet(), {'demandee', 'payee', 'executee', 'validee'});
    final cr = c('resultatsImagerie');
    for (final x in dem) {
      final liee = cr.where((r) => r['demandeImagerieId'] == x['id']).toList();
      switch (x['statut']) {
        case 'validee':
          expect(liee.length, 1);
          expect(liee.first['statut'], 'rendu');
          expect('${liee.first['conclusion']}', isNotEmpty);
        case 'executee':
          expect(liee.length, 1);
          expect(liee.first['statut'], 'brouillon');
        default:
          expect(liee, isEmpty);
      }
      if (x['statut'] == 'demandee') expect(x['bloqueParPaiement'], true);
    }
  });

  test('hospitalisation et bloc : 6 observations de 24 h au plus, 2 admissions, 5 interventions (3 avec CPA et compte rendu d\'anesthésie, 2 sans)', () {
    final obs = c('observations');
    expect(obs.length, 6);
    for (final o in obs.where((o) => o['dateSortie'] != null)) {
      final h = DateTime.parse('${o['dateSortie']}').difference(DateTime.parse('${o['dateEntree']}')).inHours;
      expect(h, lessThanOrEqualTo(24), reason: '${o['reference']}');
    }
    expect(obs.where((o) => o['statutObservation'] == 'en_cours').length, 1);
    final adm = c('admissions');
    expect(adm.length, 2);
    expect(adm.map((a) => a['statut']).toSet(), {'sortie', 'en_cours'});
    expect(adm.where((a) => a['origineObservation'] != null).length, 1, reason: 'l\'hospitalisation naît d\'une observation');
    final cro = c('crOperatoires');
    final cpa = c('cpa');
    final cra = c('crAnesthesie');
    expect([cro.length, cpa.length, cra.length], [5, 3, 3]);
    final patientsCpa = cpa.map((x) => x['patientId']).toSet();
    expect(cro.where((x) => !patientsCpa.contains(x['patientId'])).length, 2, reason: 'deux interventions signalées sans CPA, jamais bloquées');
    expect(c('checklistsBloc').length, 10);
    expect(cpa.every((x) => x['conclusion'] == 'Apte à l’anesthésie' || '${x['observations']}'.isNotEmpty), isTrue, reason: 'une CPA avec réserves nomme ses réserves');
    expect(cra.every((x) => '${x['incidents']}'.isNotEmpty), isTrue);
  });

  test('maternité : 6 CPN, 3 accouchements, 3 naissances aux bornes du rapport officiel, dossiers obstétricaux liés', () {
    final gro = c('grossesses');
    expect(gro.length, 6);
    expect(c('dossiersObstetricaux').length, 6);
    expect(gro.every((g) => g['dossierObstetricalId'] != null && (g['visites'] as List).isNotEmpty), isTrue);
    final acc = c('accouchements');
    expect(acc.length, 3);
    expect(acc.where((a) => a['type'] == 'Césarienne').length, 1);
    final nai = c('naissances');
    expect(nai.length, 3);
    for (final x in nai) {
      expect(n(x['pc']), inInclusiveRange(32, 38));
      expect(n(x['pt']), inInclusiveRange(30, 36));
      expect(n(x['apgar5']), greaterThanOrEqualTo(7));
      expect(acc.any((a) => a['id'] == x['accouchementId']), isTrue);
    }
    // La césarienne du bloc est celle de la maternité : même patiente, même jour.
    final cesar = acc.firstWhere((a) => a['type'] == 'Césarienne');
    expect(c('crOperatoires').any((o) => o['patientId'] == cesar['patientId'] && '${cesar['dateHeure']}'.startsWith('${o['dateOperation']}')), isTrue);
    expect(c('partogrammes').length, 3);
  });

  test('banque de sang : 15 donneurs, 20 poches (2 périmées), 4 transfusions avec fiche de surveillance, 90 jours entre deux dons', () {
    final don = c('donneurs');
    final poches = c('poches');
    expect(don.length, 15);
    expect(poches.length, 20);
    expect(poches.where((p) => p['etat'] == 'perime').length, 2);
    expect(poches.where((p) => p['etat'] == 'alerte').length, 3);
    expect(poches.map((p) => p['reference']).toSet().length, 20);
    final transf = c('surveillancesTransfusion');
    expect(transf.length, 4);
    for (final t in transf) {
      expect(poches.any((p) => p['reference'] == t['pochePSL'] && p['reserve'] == true), isTrue);
      expect(t['releves'], t['attendus']);
    }
    // Un donneur ne donne pas deux fois en moins de 90 jours.
    final parDonneur = <String, List<DateTime>>{};
    for (final p in poches) {
      parDonneur.putIfAbsent('${p['donneur']}', () => []).add(DateTime.parse('${p['datePrelevement']}'));
    }
    for (final e in parDonneur.entries) {
      final l = e.value..sort();
      for (var i = 1; i < l.length; i++) {
        expect(l[i].difference(l[i - 1]).inDays, greaterThanOrEqualTo(90), reason: e.key);
      }
    }
    for (final p in poches) {
      expect(don.any((d) => d['nom'] == p['donneur'] && d['groupe'] == p['groupe']), isTrue);
    }
  });

  test('aucune collection de M1 à M5 vide sans motif', () {
    const vides = {
      // les rendez-vous vivent dans `consultations` (statut planifiee), les antécédents sur le patient, le plan des lits est une constante du domaine
      'rendezvous', 'visites', 'antecedents', 'lits', 'chambres',
      // aucun assuré n'a changé de compagnie : la fiche du dossier fait foi
      'couverturesAssurance',
      // aucun fichier n'est livré avec le jeu
      'documentsPatient', 'clichesImagerie',
      // relèvent du sous-lot stock
      'produits', 'dispensations',
      // autres modules ou générateurs de rapports non peuplés par ce sous-lot
      'certificats', 'fichesReference', 'contreReferences', 'references', 'scoresGlasgow', 'rapportsMedicaux', 'registreSONU', 'planificationFamiliale',
      'ptme', 'soinsCuratifsMaternite', 'crMaternite', 'appels', 'deces', 'ambulance',
    };
    const peuplees = [
      'patients', 'constantes', 'consultations', 'dossiersConsultation', 'ordonnances', 'prescriptions', 'administrations', 'demandesAnalyses',
      'demandesImagerie', 'resultatsImagerie', 'pieces', 'avoirs', 'facturesMere', 'garanties', 'taches', 'notifications', 'observations', 'admissions',
      'releves', 'soins', 'visitesHospi', 'crOperatoires', 'cpa', 'crAnesthesie', 'checklistsBloc', 'grossesses', 'suiviMaternite',
      'dossiersObstetricaux', 'accouchements', 'naissances', 'partogrammes', 'cpon', 'donneurs', 'poches', 'surveillancesTransfusion',
    ];
    for (final k in peuplees) {
      expect(c(k), isNotEmpty, reason: k);
      expect(vides.contains(k), isFalse, reason: k);
    }
  });
}
