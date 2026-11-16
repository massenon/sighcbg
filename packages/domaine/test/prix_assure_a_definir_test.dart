// PRIX ASSURÉ À DÉFINIR (section AJ, Direction du 16/11/2026) : un acte ASSURABLE dont la colonne « prix assuré » de la grille est vide. Pour un ASSURÉ, la ligne dit « prix assuré
// à définir » (le prix non assuré affiché pour information), n'est JAMAIS facturée au prix non assuré, et son encaissement est refusé en le nommant (PRIX_ASSURE_A_DEFINIR),
// par la même mécanique que « prix à valoriser » ; elle se valorise en place dès qu'un prix assuré validé est en vigueur.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

ReferentielTarifs referentiel({List<F> autres = const []}) => ReferentielTarifs([
      {'id': 'PANS', 'code': 'PANS', 'codeActe': 'PANS', 'libelle': 'Pansement simple', 'famille': 'ACTE', 'statut': 'actif', 'assurable': true},
      {'id': 'CONS', 'code': 'CONS', 'codeActe': 'CONS', 'libelle': 'Consultation', 'famille': 'CONSULTATION', 'statut': 'actif', 'assurable': true},
    ], [
      {'id': 'PANS@origine@1', 'code': 'PANS', 'version': 1, 'prixNonAssure': 9000, 'etatAssure': 'manquant', 'statut': 'valide'},
      {'id': 'CONS@origine@1', 'code': 'CONS', 'version': 1, 'prixNonAssure': 5000, 'prixAssure': 4000, 'etatAssure': 'montant', 'statut': 'valide'},
      ...autres,
    ]);

F facture() {
  final lignes = csConstruireLignes(medicaments: const [], analyses: const [], demandes: const [], actes: [
    {'code': 'CONS', 'libelle': 'Consultation', 'prix': 4000},
    {'code': 'PANS', 'libelle': 'Pansement simple', 'prix': null, 'prixAssureADefinir': true, 'prixNonAssureInfo': 9000},
  ], taux: 80);
  final connues = lignes.where((l) => l['montant'] != null);
  num som(String k) => connues.fold<num>(0, (a, l) => a + (l[k] as num));
  return {
    'id': 'FAC1',
    'numero': 'FP-2026-00001',
    'date': '2026-11-16T09:00:00.000Z',
    'lignes': lignes,
    'montantHT': som('montant'),
    'montantTTC': som('montant'),
    'montantBrut': som('montantBrut'),
    'partAssurance': som('partAssureur'),
    'partPersonnel': som('partPersonnel'),
    'partPatient': som('partPatient'),
    'reliquat': som('partPatient'),
    'montantPaye': 0,
    'tauxPriseEnCharge': 80,
    'assureur': 'NSIA',
    'lignesAValoriser': 1,
    'statutPaiement': 'impayee',
    'statutMecef': 'en_attente',
  };
}

List<F> lignesDe(F f) => [for (final l in f['lignes'] as List) (l as Map).cast<String, Object?>()];

void main() {
  test('le référentiel : pour un ASSURÉ, aucun montant (jamais le prix non assuré), le non assuré pour information ; le non-assuré paie son prix', () {
    final h = referentiel();
    final a = h.prixActe('PANS', '2026-11-16', true, aujourdhui: '2026-11-16');
    expect([a.connu, a.montant, a.assureADefinir, a.informatif], [true, null, true, 9000]);
    final na = h.prixActe('PANS', '2026-11-16', false, aujourdhui: '2026-11-16');
    expect([na.montant, na.assureADefinir], [9000, false]);
    expect(h.prixActe('CONS', '2026-11-16', true, aujourdhui: '2026-11-16').montant, 4000, reason: 'un prix assuré présent s’applique');
  });

  test('la ligne de l’assuré : « prix assuré à définir », AUCUN montant, hors totaux, l’acte qu’elle couvre nommé', () {
    final f = facture();
    final l = lignesDe(f)[1];
    expect(ligneAValoriser(l), isTrue, reason: 'même mécanique que « prix à valoriser »');
    expect(ligneAssureADefinir(l), isTrue);
    for (final k in ['prixUnitaire', 'montant', 'montantBrut', 'partAssureur', 'partPatient']) {
      expect(l[k], isNull, reason: '$k : jamais 0, jamais 9 000');
    }
    expect(l['acteCode'], 'PANS');
    expect(libelleLigneSansMontant(l), allOf(contains('Prix assuré à définir'), contains('9000'), contains('pour information')));
    expect(f['montantTTC'], 4000, reason: 'le total ne porte que la consultation');
    expect(codeLigneSansMontant(l), codePrixAssureADefinir);
    expect(libelleLigneSansMontant(lignesDe(facture())[0]), libellePrixAValoriser, reason: 'une autre ligne n’est pas concernée');
  });

  test('l’encaissement PAR DÉFAUT : rien de la facture ne s’encaisse (FACTURE_EN_ATTENTE_DE_PRIX), la ligne nommée avec sa cause PRIX_ASSURE_A_DEFINIR', () {
    final f = facture();
    final r = encaisser(f, lignes: ['L001', 'L002'], aujourdhui: '2026-11-16', maintenant: '2026-11-16T10:00:00Z');
    expect(r.refusCode, codeFactureEnAttenteDePrix);
    expect(r.lignesReglees, isEmpty);
    expect(r.lignesRefusees.single['code'], codePrixAssureADefinir);
    expect('${r.refus}', allOf(contains('Pansement simple'), contains('prix assuré à définir'), contains('Tarifs et prix')));
  });

  test('l’encaissement, réglage OUVERT : la ligne est refusée NOMMÉE (PRIX_ASSURE_A_DEFINIR), la consultation passe ; seule cochée, rien n’est écrit', () {
    final f = facture();
    final r = encaisser(f, lignes: ['L001', 'L002'], aujourdhui: '2026-11-16', maintenant: '2026-11-16T10:00:00Z', encaisserResteSansPrix: true);
    expect(r.refus, isNull);
    expect(r.lignesReglees, ['L001']);
    expect(r.lignesRefusees.single['code'], codePrixAssureADefinir);
    expect('${r.lignesRefusees.single['motif']}', allOf(contains('Pansement simple'), contains('jamais facturée au prix non assuré')));
    final seule = encaisser(f, lignes: ['L002'], aujourdhui: '2026-11-16', maintenant: '2026-11-16T10:00:00Z', encaisserResteSansPrix: true);
    expect(seule.refusCode, codePrixAssureADefinir);
    expect(seule.lignesReglees, isEmpty);
    final global = encaisser(f, aujourdhui: '2026-11-16', maintenant: '2026-11-16T10:00:00Z', encaisserResteSansPrix: true);
    expect(global.lignesReglees, ['L001'], reason: 'un montant global ne la règle pas non plus');
  });

  test('la valorisation : seul le prix assuré EN VIGUEUR À LA DATE DE LA PIÈCE la valorise (jamais un prix assuré daté après, jamais le non assuré), en place, parts au taux de la pièce', () {
    final f = facture();
    final l = lignesDe(f)[1];
    expect(tarPrixValorisationLigne(referentiel(), l, null, '2026-11-16', aujourdhui: '2026-11-18'), isNull, reason: 'jamais le prix non assuré');
    final apres = referentiel(autres: [
      {'id': 'PANS@2026-11-17@2', 'code': 'PANS', 'version': 2, 'prixNonAssure': 9000, 'prixAssure': 6000, 'etatAssure': 'montant', 'statut': 'valide', 'dateEffet': '2026-11-17'},
    ]);
    expect(tarPrixValorisationLigne(apres, l, null, '2026-11-16', aujourdhui: '2026-11-21'), isNull, reason: 'le repli « premier prix après la pièce » est retiré (16/11/2026, §7)');
    final h = referentiel(autres: [
      {'id': 'PANS@2026-11-16@2', 'code': 'PANS', 'version': 2, 'prixNonAssure': 9000, 'prixAssure': 6000, 'etatAssure': 'montant', 'statut': 'valide', 'dateEffet': '2026-11-16', 'datePassee': true},
      {'id': 'PANS@2026-11-20@3', 'code': 'PANS', 'version': 3, 'prixNonAssure': 9000, 'prixAssure': 6500, 'etatAssure': 'montant', 'statut': 'valide', 'dateEffet': '2026-11-20'},
    ]);
    final p = tarPrixValorisationLigne(h, l, null, '2026-11-16', aujourdhui: '2026-11-21')!;
    expect([p.prixUnitaire, p.regle, p.version], [6000, 'a_la_date', 2], reason: 'le prix daté du jour de la pièce, pas la hausse ultérieure');
    final v = valoriserLigne(f, 'L002', p, utilisateur: 'Caisse', maintenant: '2026-11-21T08:00:00Z');
    expect(v.ok, isTrue);
    final apresLigne = lignesDe(v.facture!)[1];
    expect([apresLigne['montant'], apresLigne['partAssureur'], apresLigne['partPatient'], apresLigne['prixAssureADefinir']], [6000, 4800, 1200, false]);
    expect(ligneAValoriser(apresLigne), isFalse);
    // Valorisée, la facture s'encaisse EN ENTIER, réglage fermé.
    final e = encaisser(v.facture!, aujourdhui: '2026-11-21', maintenant: '2026-11-21T08:01:00Z');
    expect(e.refus, isNull);
    expect(e.facture['statutPaiement'], 'soldee');
  });
}
