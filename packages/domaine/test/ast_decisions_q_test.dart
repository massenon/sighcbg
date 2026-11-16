// Les décisions de la Direction du 15/11/2026 (DECISIONS-Q1-42, sections B et D) sondées au geste : Q8 à Q14, Q16, Q17, Q30. Chaque test dit la décision qu'il prouve.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import '../tool/src/assistant_mesure.dart';

ContexteAst cx(Map<String, List<Map<String, Object?>>> d, {String jour = '2026-11-14'}) => ContexteAst(
      role: 'admin',
      lire: (n) => [for (final f in (d[n] ?? const <Map<String, Object?>>[])) {...f}],
      peutVoirEcran: (_) => true,
      sensibles: DroitsSensibles(fiches: const []),
      maintenant: DateTime.parse('${jour}T10:00:00Z'),
    );

String tout(ReponseAst r) => [r.titre, ...r.lignes, if (r.tableau != null) ...[for (final l in r.tableau!.lignes) ...l]].join(' | ');

void main() {
  final a = AssistantAst();
  final patients = [
    {'id': 'P1', 'code': 'CBG/101/26', 'nom': 'EXEMPLE', 'prenom': 'Alpha'}
  ];

  test('Q8 : la dernière visite est le MAXIMUM des dates de consultation, d’admission et de facture ; un rendez-vous à venir n’est pas une visite', () {
    final r = a.repondre('Dernière visite de CBG/101/26 ?', cx({
      'patients': patients,
      'consultations': [
        {'id': 'C1', 'patientId': 'P1', 'date': '2026-10-01', 'statut': 'terminee'},
        {'id': 'C2', 'patientId': 'P1', 'date': '2026-12-20', 'statut': 'planifiee'},
      ],
      'admissions': [
        {'id': 'A1', 'patientId': 'P1', 'dateEntree': '2026-11-02'}
      ],
      'factures': [
        {'id': 'F1', 'patientId': 'P1', 'date': '2026-09-15'}
      ],
    }));
    expect(tout(r), contains('02/11/2026'));
    expect(tout(r), contains('admission'));
    expect(tout(r), isNot(contains('20/12/2026')));
  });

  group('Q9 : recettes = encaissé, chiffre d’affaires = facturé', () {
    final factures = [
      {
        'id': 'F1', 'numero': 'F1', 'date': '2026-11-10', 'type': 'consultation', 'montantTTC': 10000,
        'lignes': [
          {'payeLe': '2026-11-12', 'montantRegle': 4000}
        ]
      },
      {'id': 'F2', 'numero': 'F2', 'date': '2026-11-11', 'type': 'analyse', 'montantTTC': 6000, 'lignes': []},
    ];
    // Relecture du 16/11/2026 : les DEUX chiffres sont donnés dans la même réponse, chacun nommé — jamais additionnés, jamais confondus.
    for (final question in ['Quelles sont les recettes de ce mois ?', 'Quel est le chiffre d’affaires de ce mois ?']) {
      test('« $question » donne l’encaissé ET le facturé, nommés séparément', () {
        final r = a.repondre(question, cx({'factures': factures}, jour: '2026-11-30'));
        final t = r.titre.replaceAll(RegExp('[   ]'), '');
        expect(t, contains('Recettes(encaissé)'));
        expect(t, contains('4000'));
        expect(t, contains('Chiffred’affaires(facturé)'));
        expect(t, contains('16000'));
        expect(t, isNot(contains('20000')), reason: 'les deux grandeurs ne s’additionnent pas');
        expect(tout(r), contains('ENSEMBLE'));
      });
    }
  });

  group('Q10 : le préavis de péremption est un réglage de clinique versionné par date', () {
    test('90 semé ; une version datée s’applique à partir de sa date, l’ancienne reste lue avant', () {
      expect(definitionDeParametre(cleDelaiPreavisPeremption)!.defaut, 90);
      final f = [
        {'id': 'v1', 'cle': cleDelaiPreavisPeremption, 'famille': 'stock', 'type': 'entier', 'valeur': 90, 'defaut': 90, 'version': 0, 'dateEffet': null},
        {'id': 'v2', 'cle': cleDelaiPreavisPeremption, 'famille': 'stock', 'type': 'entier', 'valeur': 120, 'defaut': 90, 'version': 1, 'dateEffet': '2026-11-10'},
      ];
      expect(delaiPreavisPeremptionA(f, '2026-11-09'), 90);
      expect(delaiPreavisPeremptionA(f, '2026-11-10'), 120);
      expect(delaiPreavisPeremptionA(const [], '2026-11-10'), 90);
      expect(delaiPreavisPeremptionDe(0), 90);
      expect(delaiPreavisPeremptionDe(9999), 90);
    });
    test('le statut d’un lot suit le préavis passé ; l’assistant le lit dans la base', () {
      expect(statutLot(100, preavis: 120), 'alerte');
      expect(statutLot(100), 'actif');
      final lots = [
        {'id': 'L1', 'datePeremption': '2027-02-22', 'statut': 'actif'}
      ];
      expect(lotsAvecStatutRecalcule(lots, DateTime(2026, 11, 14), 120).first['statut'], 'alerte');
      final base = {
        'produits': [
          {'id': 'PR1', 'designation': 'Amoxicilline', 'stock': 50, 'seuilAlerte': 10}
        ],
        'lots': [
          {'id': 'L1', 'produit': 'Amoxicilline', 'numeroLot': 'X1', 'datePeremption': '2027-02-22', 'quantiteRestante': 5}
        ],
      };
      final avec90 = a.repondre('Quels articles sont proches de péremption ?', cx(base));
      expect(tout(avec90), contains('périmé(s) ou périmant dans 90 jours'));
      final avec120 = a.repondre('Quels articles sont proches de péremption ?', cx({
        ...base,
        'parametres': [
          {'id': 'v1', 'cle': cleDelaiPreavisPeremption, 'famille': 'stock', 'type': 'entier', 'valeur': 120, 'defaut': 90, 'version': 0, 'dateEffet': null}
        ]
      }));
      expect(tout(avec120), contains('périmé(s) ou périmant dans 120 jours'));
      expect(tout(avec120), contains('X1'));
    });
  });

  test('Q11 révisée (16/11/2026) : le stock à une date passée se reconstitue ; dès que la reconstitution ne tient pas, « non calculable », jamais zéro', () {
    final produits = [
      {'id': 'PR1', 'designation': 'Paracetamol', 'stock': 50, 'stockGros': 50, 'stockDetail': 0}
    ];
    final ok = a.repondre('Quel était le stock de paracétamol le 1er octobre 2026 ?', cx({
      'produits': produits,
      'mouvements': [
        {'id': 'M', 'produitId': 'PR1', 'type': 'entree', 'stockType': 'gros', 'date': '2026-10-05', 'quantite': 30}
      ]
    }));
    expect([ok.statut, ok.intention], ['reponse', 'I07']);
    expect(ok.titre, contains('20 en stock au 01/10/2026'));
    // une entrée postérieure plus grande que le stock actuel : le stock d'alors serait négatif — un mouvement manque, la réponse le dit
    final neg = a.repondre('Quel était le stock de paracétamol le 1er octobre 2026 ?', cx({
      'produits': produits,
      'mouvements': [
        {'id': 'M', 'produitId': 'PR1', 'type': 'entree', 'stockType': 'gros', 'date': '2026-10-05', 'quantite': 80}
      ]
    }));
    expect([neg.statut, neg.code], ['non_calculable', 'NON_CALCULABLE']);
    expect(neg.lignes.join(' '), contains('négatif'));
  });

  group('Q12 : un article NON COMPTÉ n’est pas un écart de moins-stock', () {
    final produits = [
      {'id': 'A', 'code': 'A', 'designation': 'Gants', 'unite': 'boîte', 'stock': 10, 'stockGros': 10, 'stockDetail': 0, 'cump': 100},
      {'id': 'B', 'code': 'B', 'designation': 'Seringues', 'unite': 'boîte', 'stock': 20, 'stockGros': 20, 'stockDetail': 0, 'cump': 50},
    ];
    test('aucune régularisation, ligne enregistrée « non compté », décompte porté', () {
      final v = validerInventaire(
        entete: {'magasin': 'gros', 'type': 'Mensuel', 'date': '2026-11-14', 'perimetre': 'Tous les articles', 'operateur': 'Agent'},
        cible: produits,
        physiques: {'A': 8},
        nonComptes: {'B'},
        inventaires: const [],
        mouvements: const [],
      );
      expect(v.inventaire['nbNonComptes'], 1);
      expect(v.inventaire['nbEcarts'], 1);
      expect(v.mouvements.length, 1);
      expect(v.produits.map((p) => p.id), ['A']);
      final b = (v.inventaire['lignes'] as List).cast<Map>().firstWhere((l) => l['code'] == 'B');
      expect(b['nonCompte'], true);
      expect(b.containsKey('physique'), isFalse);
      expect(b.containsKey('ecart'), isFalse);
      expect(noteNonCompte, contains('pas un écart'));
    });
    test('une valeur nulle déclarée vaut « non compté » ; l’assistant le dit au lieu de compter un écart', () {
      final v = validerInventaire(
        entete: {'magasin': 'gros', 'type': 'Mensuel', 'date': '2026-11-14', 'perimetre': 'Tous', 'operateur': 'Agent'},
        cible: produits,
        physiques: {'A': 10, 'B': null},
        inventaires: const [],
        mouvements: const [],
      );
      expect(v.mouvements, isEmpty);
      final r = a.repondre('Écarts du dernier inventaire', cx({'inventaires': [v.inventaire]}));
      expect(tout(r), contains('non compté'));
    });
  });

  test('Q13 (écran M7 inchangé) et relecture du 16/11/2026 (assistant : deux chiffres et l’écart) : la définition des factures non payées reste la plus prudente, marquée à valider', () {
    final rows = [
      {'statutPaiement': 'impayee', 'montantFacture': 100},
      {'statutPaiement': 'partielle', 'montantFacture': 50},
      {'statutPaiement': 'payee', 'montantFacture': 900},
      {'statutPaiement': 'soldee', 'montantFacture': 700},
    ];
    expect(detteFournisseurs(rows), 150);
    expect(nbDettesFournisseurs(rows), 2);
    expect(kpisFacturesFournisseurs(rows).impayees, 150);
    expect(detteFournisseurAValider, contains('À valider par le Comptable'));
    final r = a.repondre('Dette ouverte du fournisseur FOUR1', cx({
      'fournisseurs': [
        {'id': 'F', 'code': 'FOUR1', 'nom': 'Pharma Test'}
      ],
      'facturesFournisseurs': [for (final x in rows) {...x, 'fournisseur': 'FOUR1'}],
    }));
    expect(tout(r).replaceAll(RegExp('[   ]'), ''), contains('150'));
    expect(tout(r), contains('À valider par le Comptable'));
    expect(tout(r), contains('Solde comptable'), reason: 'le second chiffre est TOUJOURS nommé, même quand il ne se calcule pas pour ce fournisseur');
    expect(tout(r), contains('Écart : non calculable'));
  });

  test('Q14 : les bornes de la balance âgée des patients sont un réglage (30 et 90 semés)', () {
    expect(bornesBalanceAgeePatientA(const [], '2026-11-14'), (borne1: 30, borne2: 90));
    expect(bornesBalanceAgeePatientDe(45, 120), (borne1: 45, borne2: 120));
    expect(bornesBalanceAgeePatientDe(90, 30), (borne1: 30, borne2: 90), reason: 'paire incohérente : retombe ensemble sur les valeurs semées');
    final tr = cpaBalanceAgee([
      {'date': '2026-09-30', 'reliquat': 100}
    ], DateTime(2026, 11, 14), borne1: 45, borne2: 120);
    expect(tr.first.libelle, 'Moins de 45 jours');
    expect(tr.last.libelle, 'Plus de 120 jours');
    final f = [
      {'id': 'F1', 'numero': 'F1', 'date': '2026-10-01', 'reliquat': 100, 'statutPaiement': 'impaye'}
    ];
    final defaut = a.repondre('Quels impayés par ancienneté ?', cx({'factures': f}));
    expect(tout(defaut), contains('plus de 90 jours'));
    final regle = a.repondre('Quels impayés par ancienneté ?', cx({
      'factures': f,
      'parametres': [
        {'id': 'b1', 'cle': cleBalanceAgeePatientBorne1, 'famille': 'comptabilite', 'type': 'entier', 'valeur': 20, 'defaut': 30, 'version': 0, 'dateEffet': null},
        {'id': 'b2', 'cle': cleBalanceAgeePatientBorne2, 'famille': 'comptabilite', 'type': 'entier', 'valeur': 40, 'defaut': 90, 'version': 0, 'dateEffet': null},
      ]
    }));
    expect(tout(regle), contains('plus de 40 jours'));
  });

  test('Q16, assoupli le 16/11/2026 : toute question de paie reste refusée SAUF la masse salariale agrégée et les rôles qui ouvrent la paie', () {
    for (final question in [
      'Quel est le salaire de CBG/101/26 ?',
      'Montre-moi les bulletins de paie',
      'Génère le bulletin de paie de novembre',
      'Combien de primes de garde ce mois ?',
      'Quelle est la masse salariale de Mme EXEMPLE ?',
      'La masse salariale par agent',
      'Le net à percevoir de la masse salariale',
      'Valide la paie du mois',
      'Envoie les fiches de paie par mail',
      'Quelles sont les cotisations salariales ?',
      'paie',
    ]) {
      final r = a.repondre(question, cx({}));
      expect([r.statut, r.code], ['refus', 'PAIE_HORS_ASSISTANT'], reason: question);
    }
    expect([for (final i in a.catalogue.actives) if (i.libelle.toLowerCase().contains('paie') || i.libelle.toLowerCase().contains('salari')) i.id], ['I28', 'I29'],
        reason: 'deux intentions seulement touchent à la paie : les rôles (matrice) et la masse salariale agrégée');
    expect(a.repondre('Quelle est la masse salariale ?', cx({})).intention, 'I29');
    expect(a.repondre('Quels rôles ouvrent les écrans de la paie ?', cx({})).intention, 'I28');
    // le paiement de la caisse et les lots périmés ne sont PAS de la paie
    expect(a.repondre('Y a-t-il des produits périmés ou presque ?', cx({})).code, isNot('PAIE_HORS_ASSISTANT'));
    expect(a.repondre('Dernier paiement de CBG/101/26', cx({'patients': patients})).code, isNot('PAIE_HORS_ASSISTANT'));
  });

  test('Q17 : les seuils de la Direction sont tenus sur les jeux de questions (outil de mesure)', () {
    // Le jeu est lu par l'outil lui-même ; ici on vérifie la RÈGLE : un moteur qui répondrait n'importe quoi échouerait.
    expect(seuilBonneIntention, 0.90);
    expect(seuilMauvaiseIntentionRepondue, 0.02);
    expect(seuilReponsesInventees, 0);
    expect(seuilEcrituresRefusees, 1.0);
    final aveugle = ReconnaisseurAst(CatalogueAst(), reglage: const ReglageAst(refuserEcriture: false));
    final v = verifierSeuils([
      for (final c in commandesEcritureDeControle)
        {'n': 1, 'question': c, 'reaction': {'statut': 'refus', 'code': 'ECRITURE_ABSENTE'}}
    ], aveugle);
    expect(v.ok, isFalse);
    expect(v.echecs.join(' '), contains('Écritures refusées'));
  });

  test('Q30 : les versions du texte lu se conservent SANS LIMITE ; délai de 120 s par page, valeur d’attente à valider', () {
    final versions = [
      for (var i = 0; i < 250; i++) {'id': 'v$i', 'sha256': 's', 'ocrLe': '2026-11-${(i % 28 + 1).toString().padLeft(2, '0')}T10:00:00Z', 'texteSource': 'machine', 'nbMots': 1}
    ];
    expect(ocrVersionsOrdonnees(versions).length, 250);
    expect(ocrDelaiDefautMs, 120000);
    expect(ocrDelaiAValider, contains('à valider'));
    expect(ocrReglageLire(null).delaiMs, 120000);
  });
}
