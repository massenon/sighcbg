// LES VERSEMENTS (Direction de Baguidi, 20/11/2026, §13) : allocation, plafond, écriture par type, compatibilité d'une ancienne facture, refus nommés, contre-passation.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

const auj = '2026-11-20';
const maint = '2026-11-20T10:00:00.000';

/// Une facture de deux lignes (5 000 et 3 000) pour un patient non assuré.
Map<String, Object?> facture({num partAssurance = 0}) => {
      'id': 'F1',
      'numero': 'FN-2026-00001',
      'patient': 'PATIENT-TEST',
      'date': auj,
      'montantTTC': 8000 + partAssurance,
      'partPatient': 8000,
      'partAssurance': partAssurance,
      'montantPaye': 0,
      'reliquat': 8000,
      'statutPaiement': 'impayee',
      'lignes': [
        {'id': 'L1', 'designation': 'Analyse', 'categorie': 'analyse', 'quantite': 1, 'prixUnitaire': 5000, 'partPatient': 5000, 'partAssureur': 0, 'statutPaiement': 'du'},
        {'id': 'L2', 'designation': 'Consultation', 'categorie': 'consultation', 'quantite': 1, 'prixUnitaire': 3000, 'partPatient': 3000, 'partAssureur': 0, 'statutPaiement': 'du'},
      ],
    };

ResultatVersements regler(Map<String, Object?> f, List<VersementSaisi> v, {List<String>? lignes, List<Map<String, Object?>> existants = const [], List<Map<String, Object?>> ecritures = const []}) =>
    reglerParVersements(f, v, lignes: lignes, aujourdhui: auj, maintenant: maint, utilisateur: 'caissier1', versementsExistants: existants, ecritures: ecritures);

double som(Iterable<Map<String, Object?>> e, String compte, String sens) => e.where((x) => '${x['compte']}' == compte).fold(0.0, (a, x) => a + (x[sens]! as num));

void main() {
  const momo = VersementSaisi(montant: 5000, type: 'mobile_money', modalite: 'MV01', reference: 'MP2611.1234');
  const cash = VersementSaisi(montant: 3000, type: 'especes');

  test('deux versements de types différents règlent la facture : une ligne par versement, deux écritures plates sur deux comptes de trésorerie', () {
    final r = regler(facture(), [momo, cash], lignes: ['L1', 'L2']);
    expect(r.refus, isNull);
    expect(r.versements.length, 2);
    expect(r.encaissement!.facture['statutPaiement'], 'soldee');
    expect(r.encaissement!.facture['montantPaye'], 8000);
    expect(r.encaissement!.facture['reliquat'], 0);
    expect(r.encaissement!.facture['modePaiement'], modeMixte);
    expect(r.encaissement!.lignesReglees, ['L1', 'L2']);
    expect(r.versements.map((v) => v['compteTresorerie']), [compteTresorerieAttente, compteCaisse]);
    expect(r.versements.first['modaliteLibelle'], 'MTN');
    expect(r.versements.map((v) => v['numero']).toSet().length, 2, reason: 'deux numéros distincts');
    // Une écriture par versement : débit du compte du type, crédit 706 du même montant, équilibrée, brouillon.
    expect(som(r.ecritures, compteTresorerieAttente, 'debit'), 5000);
    expect(som(r.ecritures, compteCaisse, 'debit'), 3000);
    expect(som(r.ecritures, comptePrestations, 'credit'), 8000);
    expect(r.ecritures.fold(0.0, (a, x) => a + (x['debit']! as num)), r.ecritures.fold(0.0, (a, x) => a + (x['credit']! as num)));
    expect(r.ecritures.every((x) => x['statut'] == 'brouillon'), isTrue);
    expect({for (final x in r.ecritures) x['numero']}.length, 1, reason: 'une seule pièce de caisse pour la facture');
  });

  test('la part de l\'assureur (411) n\'est constatée qu\'au PREMIER versement, une seule fois', () {
    final r = regler(facture(partAssurance: 2000), [momo, cash], lignes: ['L1', 'L2']);
    expect(r.refus, isNull);
    expect(som(r.ecritures, '411110', 'debit'), 2000);
    expect(r.ecritures.where((x) => x['compte'] == '411110').length, 1);
    expect(som(r.ecritures, comptePrestations, 'credit'), 10000);
    expect(r.ecritures.fold(0.0, (a, x) => a + (x['debit']! as num)), r.ecritures.fold(0.0, (a, x) => a + (x['credit']! as num)));
  });

  test('un seul type : la facture garde ce mode (et non « mixte »)', () {
    final r = regler(facture(), [const VersementSaisi(montant: 8000, type: 'tpe')], lignes: ['L1', 'L2']);
    expect(r.encaissement!.facture['modePaiement'], 'tpe');
  });

  test('prestation bloquée : une ligne n\'est réglée que si elle l\'est entièrement ; le total des versements doit égaler les lignes cochées (refus nommé)', () {
    final r = regler(facture(), [momo, const VersementSaisi(montant: 1000, type: 'especes')], lignes: ['L1', 'L2']);
    expect(r.refusCode, codeVersementsEcartLignes);
    expect(r.refus, contains(money(2000)));
    expect(r.versements, isEmpty);
    expect(r.ecritures, isEmpty);
    // Seule la ligne cochée est réglée : L2 reste due.
    final partiel = regler(facture(), [momo], lignes: ['L1']);
    expect(partiel.encaissement!.lignesReglees, ['L1']);
    expect(partiel.encaissement!.restantDu, 3000);
    expect(partiel.encaissement!.facture['statutPaiement'], 'partielle');
  });

  test('plafond : la somme des versements ne dépasse jamais le dû (refus nommé), avec ou sans prestations cochées', () {
    final trop = regler(facture(), [momo, const VersementSaisi(montant: 4000, type: 'especes')], lignes: ['L1', 'L2']);
    expect(trop.refusCode, codeVersementsEcartLignes);
    expect(trop.refus, contains('ne dépasse jamais le dû'));
    // Sans lignes cochées : l'allocation suit l'ordre de la pièce, et 5 000 + 3 000 la solde.
    final ordre = regler(facture(), [momo, cash]);
    expect(ordre.refus, isNull);
    expect(ordre.encaissement!.lignesReglees, ['L1', 'L2']);
    // Un montant qui ne couvre aucune ligne entière est refusé : jamais d'argent sans ligne pour le porter.
    final aucune = regler(facture(), [const VersementSaisi(montant: 2000, type: 'especes')]);
    expect(aucune.refusCode, codeVersementsMontantNonAlloue);
  });

  test('refus nommés : liste vide, montant, type inconnu, modalité d\'un autre type, référence exigée, référence déjà utilisée', () {
    expect(regler(facture(), const []).refusCode, codeVersementsVides);
    expect(regler(facture(), [const VersementSaisi(montant: 0, type: 'especes')]).refusCode, codeVersementMontant);
    expect(regler(facture(), [const VersementSaisi(montant: 8000, type: 'cheque_maison')]).refusCode, codeVersementTypeInconnu);
    expect(regler(facture(), [const VersementSaisi(montant: 8000, type: 'especes', modalite: 'MV01')]).refusCode, codeVersementModaliteInconnue);
    final sansRef = regler(facture(), [const VersementSaisi(montant: 8000, type: 'mobile_money', modalite: 'MV01')]);
    expect(sansRef.refusCode, codeVersementReferenceExigee);
    final ok = regler(facture(), [momo, cash], lignes: ['L1', 'L2']);
    // La même référence sur une autre facture : refusée en nommant.
    final autre = {...facture(), 'id': 'F2', 'numero': 'FN-2026-00002'};
    final dup = regler(autre, [momo, cash], existants: [for (final (i, v) in ok.versements.indexed) {...v, 'id': 'V$i'}]);
    expect(dup.refusCode, codeVersementReferenceUtilisee);
    // Deux fois la même référence dans le même règlement.
    expect(regler(facture(), [momo, const VersementSaisi(montant: 3000, type: 'mobile_money', reference: 'mp2611.1234')], lignes: ['L1', 'L2']).refusCode, codeVersementReferenceUtilisee);
  });

  test('le type est un PARAMÈTRE : un type créé par la clinique est accepté, un type archivé ou inactif est refusé, le compte suit la fiche', () {
    final types = [
      ...typesVersementSemence(),
      {'id': 'TV09', 'code': 'cheque', 'libelle': 'Chèque', 'compteTresorerie': '521100', 'referenceExigee': true, 'actif': true},
      {'id': 'TV10', 'code': 'virement', 'libelle': 'Virement', 'compteTresorerie': '521200', 'actif': false},
    ];
    ResultatVersements avec(String code, {String ref = ''}) =>
        reglerParVersements(facture(), [VersementSaisi(montant: 8000, type: code, reference: ref)], lignes: ['L1', 'L2'], aujourdhui: auj, maintenant: maint, typesFiches: types);
    final c = avec('cheque', ref: 'CH-778');
    expect(c.refus, isNull);
    expect(som(c.ecritures, '521100', 'debit'), 8000);
    expect(avec('cheque').refusCode, codeVersementReferenceExigee);
    expect(avec('virement').refusCode, codeVersementTypeInconnu);
    // Les valeurs d'attente sont marquées à confirmer.
    expect(typesVersementEnService(const []).every((t) => t.aConfirmer), isTrue);
    expect(modalitesVersementEnService(const [], type: 'mobile_money').map((m) => m.libelle), ['MTN', 'Moov', 'Celtiis']);
  });

  test('compatibilité : une facture ANCIENNE sans versements se lit comme un versement implicite de son mode unique (rien n\'est réécrit)', () {
    final ancienne = {...facture(), 'id': 'F0', 'montantPaye': 8000, 'reliquat': 0, 'statutPaiement': 'soldee', 'modePaiement': 'mtn', 'dernierReglement': {'date': '2026-09-01T09:00:00', 'montant': 8000}};
    final l = versementsDeFacture(ancienne, const []);
    expect(l.length, 1);
    expect(l.first.implicite, isTrue);
    expect(l.first.type, 'mtn');
    expect(l.first.montant, 8000);
    expect(l.first.date, '2026-09-01');
    expect(versementsDeFacture(facture(), const []), isEmpty, reason: 'rien réglé, aucun versement implicite');
    // Les états par type : 5 000 Mobile Money + 3 000 espèces ; l'ancienne facture compte pour son mode.
    final r = regler(facture(), [momo, cash], lignes: ['L1', 'L2']);
    final vers = [for (final (i, v) in r.versements.indexed) {...v, 'id': 'V$i', 'factureId': 'F1'}];
    final par = repartitionParType([r.encaissement!.facture, ancienne], vers);
    expect(par['mobile_money'], 5000);
    expect(par['especes'], 3000);
    expect(par['mtn'], 8000);
    expect(par.values.fold<num>(0, (a, b) => a + b), 16000);
  });

  group('contre-passation', () {
    final r = regler(facture(), [momo, cash], lignes: ['L1', 'L2']);
    final vers = [for (final (i, v) in r.versements.indexed) {...v, 'id': 'V$i'}];
    final f = r.encaissement!.facture;
    test('annuler un règlement : une contre-passation PAR versement, écriture inverse équilibrée, prestations redevenues dues', () {
      final c = contrepasserReglement(f, 'V0', vers, motif: 'Erreur de saisie du montant', aujourdhui: auj, maintenant: maint, utilisateur: 'comptable1', ecritures: r.ecritures);
      expect(c.refus, isNull);
      expect(c.contrepassations.length, 2);
      expect(c.contrepassations.every((x) => x['sens'] == sensContrepassation && x['motif'] == 'Erreur de saisie du montant'), isTrue);
      expect(c.contrepassations.map((x) => x['annule']), ['V0', 'V1']);
      expect(c.facture['montantPaye'], 0);
      expect(c.facture['reliquat'], 8000);
      expect(c.facture['statutPaiement'], 'impayee');
      expect(c.lignesRouvertes, ['L1', 'L2']);
      expect(som(c.ecritures, compteTresorerieAttente, 'credit'), 5000);
      expect(som(c.ecritures, compteCaisse, 'credit'), 3000);
      expect(som(c.ecritures, comptePrestations, 'debit'), 8000);
      // Après contre-passation, la facture se lit sans versement en vigueur (la contre-passation compte, jamais une suppression).
      final apres = [...vers, for (final (i, x) in c.contrepassations.indexed) {...x, 'id': 'C$i'}];
      expect(versementsDeFacture({...f, ...c.facture}, apres), isEmpty);
    });
    test('refus nommés : sans motif, déjà annulé, introuvable, facture normalisée', () {
      expect(contrepasserReglement(f, 'V0', vers, motif: ' ', aujourdhui: auj, maintenant: maint).refusCode, codeVersementMotifObligatoire);
      expect(contrepasserReglement(f, 'V9', vers, motif: 'x', aujourdhui: auj, maintenant: maint).refusCode, codeVersementIntrouvable);
      final annule = [...vers, {'id': 'C0', 'factureId': 'F1', 'sens': sensContrepassation, 'annule': 'V0', 'montant': 5000, 'statut': 'actif'}];
      expect(contrepasserReglement(f, 'V0', annule, motif: 'x', aujourdhui: auj, maintenant: maint).refusCode, codeVersementDejaAnnule);
      expect(contrepasserReglement({...f, 'statutMecef': 'valide', 'numeroMecef': 'M1'}, 'V0', vers, motif: 'x', aujourdhui: auj, maintenant: maint).refusCode, codeVersementFactureNormalisee);
    });
  });
}
