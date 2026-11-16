// MÉDICAMENT SANS PRIX D'ACHAT : PRESCRIRE, BLOQUER LA CAISSE (Direction de Baguidi, 16/11/2026). La ligne porte « prix à valoriser », jamais 0 ; seul SON encaissement est
// refusé (code nommé PRIX_A_VALORISER), les autres lignes s'encaissent ; la ligne se valorise EN PLACE, au prix en vigueur à la date de la pièce (sinon le premier prix qui l'a
// valorisée), sans réécrire une pièce normalisée.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

F facture({num taux = 0, bool agent = false, String? numeroMecef}) {
  final lignes = csConstruireLignes(medicaments: [
    {'produit': 'Paracétamol 500', 'quantite': 2, 'prix': 100, 'total': 200, 'produitId': 'P1'},
    {'produit': 'Amoxicilline 1 g', 'quantite': 3, 'prix': null, 'total': null, 'produitId': 'P2', 'prixAValoriser': true},
  ], analyses: [
    {'designation': 'NFS', 'prix': 3000}
  ], demandes: [
    {'id': 'D1'}
  ], taux: taux, personnelId: agent ? 'AG1' : null);
  final connues = lignes.where((l) => l['montant'] != null);
  num som(String k) => connues.fold<num>(0, (a, l) => a + (l[k] as num));
  return {
    'id': 'FAC1',
    'numero': 'FP-2026-00001',
    'date': '2026-11-16T09:00:00.000Z',
    'patient': 'Patient Essai',
    'lignes': lignes,
    'montantHT': som('montant'),
    'montantTTC': som('montant'),
    'montantBrut': som('montantBrut'),
    'partAssurance': som('partAssureur'),
    'partPersonnel': som('partPersonnel'),
    'partPatient': som('partPatient'),
    'reliquat': som('partPatient'),
    'montantPaye': 0,
    'tauxPriseEnCharge': taux,
    'priseEnChargePersonnel': agent,
    'assureur': taux > 0 ? 'NSIA' : null,
    'lignesAValoriser': 1,
    'statutPaiement': 'impayee',
    'statutMecef': 'en_attente',
    if (numeroMecef != null) 'numeroMecef': numeroMecef,
  };
}

List<F> lignesDe(F f) => [for (final l in f['lignes'] as List) (l as Map).cast<String, Object?>()];

void main() {
  group('la ligne « prix à valoriser » : jamais un zéro', () {
    test('la ligne payable existe, sans AUCUN montant ; les totaux ne la comptent pas (ni pour 0) et le compte la nomme', () {
      final f = facture();
      final l = lignesDe(f)[1];
      expect(ligneAValoriser(l), isTrue);
      for (final k in ['prixUnitaire', 'montant', 'montantBrut', 'partAssureur', 'partPersonnel', 'partPatient', 'prixUnitaireNet']) {
        expect(l[k], isNull, reason: '$k : un tiret n’est pas un zéro');
      }
      expect(l['produitId'], 'P2', reason: 'la ligne sait ce qu’elle couvre');
      expect(lignesAValoriserDe(f), hasLength(1));
      expect(f['montantTTC'], 3200);
    });
  });

  group('l’encaissement : seule la ligne sans prix est refusée, nommée', () {
    test('toutes les lignes cochées : les deux lignes connues passent, la ligne sans prix est refusée PRIX_A_VALORISER ; la pièce reste ouverte', () {
      final f = facture();
      final r = encaisser(f, lignes: ['L001', 'L002', 'L003'], aujourdhui: '2026-11-16', maintenant: '2026-11-16T10:00:00Z');
      expect(r.refus, isNull);
      expect(r.lignesReglees, ['L001', 'L003']);
      expect(r.montantRegle, 3200);
      expect(r.lignesRefusees.single['id'], 'L002');
      expect(r.lignesRefusees.single['code'], codePrixAValoriser);
      expect('${r.lignesRefusees.single['motif']}', contains('Amoxicilline'));
      expect(r.facture['statutPaiement'], 'partielle', reason: 'jamais « soldée » avec une ligne sans montant');
      expect(r.facture['lignesAValoriser'], 1);
      expect(r.restantDu, 0, reason: 'le reste CONNU est nul ; la ligne sans prix reste à part, nommée');
      expect(lignesDe(r.facture)[1]['statutPaiement'], 'du');
    });

    test('seule la ligne sans prix cochée : refus nommé, RIEN n’est écrit', () {
      final f = facture();
      final r = encaisser(f, lignes: ['L002'], aujourdhui: '2026-11-16', maintenant: '2026-11-16T10:00:00Z');
      expect(r.refusCode, codePrixAValoriser);
      expect(r.ecritures, isEmpty);
      expect(identical(r.facture, f), isTrue);
    });

    test('un versement global : les lignes connues sont allouées, la ligne sans prix sautée et nommée', () {
      final r = encaisser(facture(), aujourdhui: '2026-11-16', maintenant: '2026-11-16T10:00:00Z');
      expect(r.lignesReglees, ['L001', 'L003']);
      expect(r.lignesRefusees.single['code'], codePrixAValoriser);
      expect(r.facture['statutPaiement'], 'partielle');
      final r2 = encaisser(r.facture, aujourdhui: '2026-11-16', maintenant: '2026-11-16T10:05:00Z');
      expect(r2.refusCode, codePrixAValoriser, reason: 'il ne reste que la ligne sans prix');
    });
  });

  group('le prix retenu : à la date de la pièce, sinon le premier prix qui a valorisé l’article', () {
    final produit = {'id': 'P2', 'code': 'AMOX1G', 'designation': 'Amoxicilline 1 g', 'categorie': 'medicament'};
    final tarifs = [
      {'id': 'AMOX1G', 'code': 'AMOX1G', 'famille': tarFamilleProduit, 'statut': 'actif'}
    ];
    F v(int n, String? de, num? prix, {String statut = 'valide'}) => {
          'id': 'AMOX1G@$de@$n',
          'code': 'AMOX1G',
          'version': n,
          if (de != null) 'dateEffet': de,
          if (prix != null) 'prixNonAssure': prix else 'etatNonAssure': 'manquant',
          'etatAssure': 'unique',
          'statut': statut,
        };

    test('article encore à valoriser : aucun prix, rien n’est inventé', () {
      final h = ReferentielTarifs(tarifs, [v(1, null, null)]);
      expect(tarPrixValorisation(h, produit, '2026-11-16', aujourdhui: '2026-11-17'), isNull);
    });

    test('le premier prix validé APRÈS la pièce la valorise ; un prix plus récent ne la suit pas ; une date future ne vaut pas encore ; une proposition non plus', () {
      final h = ReferentielTarifs(tarifs, [v(1, null, null), v(2, '2026-11-18', 450), v(3, '2026-11-25', 600), v(4, '2026-11-17', 999, statut: 'propose')]);
      final p = tarPrixValorisation(h, produit, '2026-11-16', aujourdhui: '2026-11-30')!;
      expect(p.prixUnitaire, 450);
      expect(p.version, 2);
      expect(p.regle, 'premiere_valorisation');
      expect(tarPrixValorisation(h, produit, '2026-11-16', aujourdhui: '2026-11-17'), isNull, reason: 'le prix du 18 n’est pas encore en vigueur');
    });

    test('un prix daté à la date de la pièce (ou avant) : le prix EN VIGUEUR à cette date', () {
      final h = ReferentielTarifs(tarifs, [v(1, null, null), v(2, '2026-11-16', 400), v(3, '2026-11-20', 600)]);
      final p = tarPrixValorisation(h, produit, '2026-11-16', aujourdhui: '2026-11-30')!;
      expect(p.prixUnitaire, 400);
      expect(p.regle, 'a_la_date');
    });
  });

  group('valoriser EN PLACE : compléter un montant absent, jamais réécrire une pièce validée', () {
    const prix = PrixValorisation(prixUnitaire: 450, version: 2, dateEffet: '2026-11-18', regle: 'premiere_valorisation');

    test('les parts suivent la règle de la pièce (taux arrêté à sa date), aucune remise (RG-02), la trace est portée ; les autres lignes ne bougent pas', () {
      final f = facture(taux: 80);
      final r = valoriserLigne(f, 'L002', prix, utilisateur: 'CAISSE', maintenant: '2026-11-20T08:00:00Z');
      expect(r.ok, isTrue);
      final l = lignesDe(r.facture!)[1];
      expect(l['montant'], 1350);
      expect(l['partAssureur'], 1080);
      expect(l['partPatient'], 270);
      expect(l['remise'], 0);
      expect(ligneAValoriser(l), isFalse);
      expect((l['valorisation'] as Map)['version'], 2);
      expect((l['valorisation'] as Map)['valorisePar'], 'CAISSE');
      expect(r.facture!['montantTTC'], (f['montantTTC'] as num) + 1350);
      expect(r.facture!['partPatient'], (f['partPatient'] as num) + 270);
      expect(r.facture!['lignesAValoriser'], 0);
      expect(lignesDe(r.facture!)[0], lignesDe(f)[0], reason: 'une ligne déjà valorisée ne bouge pas');
      expect(r.facture!['numero'], f['numero']);
      expect(r.ecritures, isEmpty, reason: 'la créance n’est pas encore constatée : le premier versement la constatera en entier');
      // Puis la ligne s'encaisse normalement, et la pièce se solde.
      final e = encaisser(r.facture!, lignes: ['L001', 'L002', 'L003'], aujourdhui: '2026-11-20', maintenant: '2026-11-20T08:01:00Z');
      expect(e.lignesRefusees, isEmpty);
      expect(e.facture['statutPaiement'], 'soldee');
    });

    test('un agent de la clinique : prise en charge du personnel, jamais une créance', () {
      final r = valoriserLigne(facture(agent: true), 'L002', prix, utilisateur: 'C', maintenant: '2026-11-20T08:00:00Z');
      final l = lignesDe(r.facture!)[1];
      expect(l['partPersonnel'], 1350);
      expect(l['partAssureur'], 0);
      expect(l['partPatient'], 0);
    });

    test('créance de l’assureur DÉJÀ constatée : la part assurée de la ligne entre au journal par une écriture équilibrée (411 / 706, brouillon)', () {
      final f = facture(taux: 80);
      final premier = encaisser(f, lignes: ['L001'], aujourdhui: '2026-11-16', maintenant: '2026-11-16T10:00:00Z');
      final r = valoriserLigne(premier.facture, 'L002', prix,
          utilisateur: 'C', maintenant: '2026-11-20T08:00:00Z', aujourdhui: '2026-11-20', ecritures: [for (final (i, e) in premier.ecritures.indexed) {...e, 'id': 'E$i'}]);
      expect(r.ecritures, hasLength(2));
      final debit = r.ecritures.fold<double>(0, (a, e) => a + (e['debit'] as double));
      final credit = r.ecritures.fold<double>(0, (a, e) => a + (e['credit'] as double));
      expect(debit, 1080);
      expect(credit, debit, reason: 'RG-10');
      expect(r.ecritures.every((e) => e['statut'] == 'brouillon'), isTrue);
      expect(r.ecritures.first['numero'], premier.ecritures.first['numero'], reason: 'même pièce de caisse');
    });

    test('refus nommés : pièce normalisée, ligne déjà valorisée, ligne introuvable, pièce archivée', () {
      expect(valoriserLigne(facture(numeroMecef: 'MECEF-1'), 'L002', prix, utilisateur: 'C', maintenant: 'x').refusCode, 'PIECE_NORMALISEE');
      expect(valoriserLigne(facture(), 'L001', prix, utilisateur: 'C', maintenant: 'x').refusCode, 'DEJA_VALORISEE');
      expect(valoriserLigne(facture(), 'L099', prix, utilisateur: 'C', maintenant: 'x').refusCode, 'LIGNE_INTROUVABLE');
      expect(valoriserLigne({...facture(), 'statut': 'archive'}, 'L002', prix, utilisateur: 'C', maintenant: 'x').refusCode, 'PIECE_ARCHIVEE');
    });
  });

  test('une pièce qui attend un prix ne se normalise pas (refus nommé, rien d’écrit)', () {
    final p = preparerNormalisation({...facture(), 'montantPaye': 200});
    expect(p.refus?.code, 'PRIX_A_VALORISER');
  });

  test('une ligne « prix à valoriser » n’est pas un USAGE du prix : le premier prix d’achat peut être daté à la date de la pièce', () {
    final pres = {'id': 'AMOX1G', 'code': 'AMOX1G', 'famille': tarFamilleProduit, 'statut': 'actif'};
    final f = facture();
    expect(tarUsages(pres, '2026-11-01', PiecesTarif(factures: [f]), aujourdhui: '2026-11-20', produitsIds: {'P2'}), isEmpty);
    expect(tarUsages(pres, '2026-11-01', PiecesTarif(factures: [f]), aujourdhui: '2026-11-20', produitsIds: {'P1'}), hasLength(1), reason: 'une ligne valorisée reste un usage');
  });
}
