// LOT CLO (clinique sœur), vérifié puis appliqué à Baguidi — décision du 16/11/2026, docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md § 6 :
//  (a) la colonne N-1 du compte de résultat est calculée AU MÊME FILTRE DE STATUT que la colonne N, à côté de la colonne N-1 citée du dépôt ;
//  (b) le grand livre porte un solde d'OUVERTURE (écrit / provisoire / inconnu — jamais un zéro par défaut) et un solde de CLÔTURE par compte ;
//  (c) les journaux CL et AN sont réservés au moteur (ni saisie manuelle, ni autre voie : refus nommé) ;
//  (d) l'ouverture automatique de l'exercice suivant n'écrit AUCUNE pièce.
// Jeu SYNTHÉTIQUE (aucune identité réelle) : chaque attendu se recompte à la main.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';
import 'aide_documents_fiscaux.dart';

typedef F = Map<String, Object?>;

F ligne(String numero, String date, String journal, String compte, num debit, num credit,
        {String statut = 'validee', String? origine, String? origineCloture, String? contrePasseDe}) =>
    {
      'id': '$numero-$compte-$debit-$credit',
      'numero': numero,
      'date': date,
      'journal': journal,
      'compte': compte,
      'debit': debit,
      'credit': credit,
      'statut': statut,
      if (origine != null) 'origine': origine,
      if (origineCloture != null) 'origineCloture': origineCloture,
      if (contrePasseDe != null) 'contrePasseDe': contrePasseDe,
    };

F exercice(int annee, String etat, {String source = 'journal'}) =>
    {'id': 'EXO-$annee', 'annee': annee, 'statut': 'actif', 'etat': etat, 'source': source};

void main() {
  brancherDocumentsFiscauxDeTest();
  // 2026 : une vente de 1 000 encaissée (validée), une vente de 500 en brouillon, et la pièce de CLÔTURE qui solde le 706 au 131.
  final e2026 = [
    ligne('VTE-2026-00001', '2026-03-10', 'VTE', '571000', 1000, 0),
    ligne('VTE-2026-00001', '2026-03-10', 'VTE', '706000', 0, 1000),
    ligne('VTE-2026-00002', '2026-04-10', 'VTE', '571000', 500, 0, statut: 'brouillon'),
    ligne('VTE-2026-00002', '2026-04-10', 'VTE', '706000', 0, 500, statut: 'brouillon'),
    ligne('CL-2026-00001', '2026-12-31', 'CL', '706000', 1000, 0, origineCloture: 'cl'),
    ligne('CL-2026-00001', '2026-12-31', 'CL', '131000', 0, 1000, origineCloture: 'cl'),
  ];
  // 2027 : une vente de 300.
  final e2027 = [
    ligne('VTE-2027-00001', '2027-02-01', 'VTE', '571000', 300, 0),
    ligne('VTE-2027-00001', '2027-02-01', 'VTE', '706000', 0, 300),
  ];

  group('(a) compte de résultat : N-1 au même filtre de statut que N', () {
    test('la colonne N-1 calculée retient les VALIDÉES, écarte les brouillons ET la pièce CL (sinon un exercice clos se lirait à zéro)', () {
      final cols = cpbColonnesFeuilletEcran('resultat', '2027', DateTime(2027, 12, 31), [...e2026, ...e2027]);
      expect(cols.length, 2, reason: '2026 n’est pas déposé : deux colonnes calculées');
      expect(cols[0].depose || cols[1].depose, isFalse);
      expect(cols[0].val('TC'), 300);
      expect(cols[1].val('TC'), 1000, reason: 'CL écartée, brouillon de 500 écarté');
      expect(cols[1].brouillons, 2, reason: 'les deux lignes en brouillon sont ANNONCÉES');
      expect(cols[1].val('XI'), 1000, reason: 'le résultat de l’exercice clos est son activité, pas zéro');
    });

    test('le tableau des flux calculé écarte aussi la pièce CL : la CAFG d’un exercice clos n’est pas nulle', () {
      final cols = cpbColonnesFeuillet('flux', '2026', DateTime(2026, 12, 31), e2026);
      expect(cols[0].val('FA'), 1000);
    });

    test('exercice précédent DÉPOSÉ : trois colonnes — N calculé, N-1 calculé (même filtre), N-1 cité du dépôt — jamais deux sources dans une colonne', () {
      final cols = cpbColonnesFeuilletEcran('resultat', '2026', DateTime(2026, 12, 31), e2026);
      expect(cols.length, 3);
      expect([for (final c in cols) c.depose], [false, false, true]);
      expect([for (final c in cols) c.annee], [2026, 2025, 2025]);
      expect(cols[1].nbLignes, 0, reason: 'le journal ne porte rien de 2025');
      expect(cols[2].val('XI'), cpbLignesResultat.firstWhere((l) => l.ref == 'XI').n, reason: 'la colonne déposée CITE la liasse');
      expect(identical(cpbColonneN1Reference(cols), cols[2]), isTrue, reason: 'colonne calculée vide : la référence de comparaison est le dépôt');
      final avec2025 = [...e2026, ligne('VTE-2025-00001', '2025-06-01', 'VTE', '571000', 70, 0), ligne('VTE-2025-00001', '2025-06-01', 'VTE', '706000', 0, 70)];
      final cols2 = cpbColonnesFeuilletEcran('resultat', '2026', DateTime(2026, 12, 31), avec2025);
      expect(cols2[1].val('TC'), 70);
      expect(identical(cpbColonneN1Reference(cols2), cols2[1]), isTrue, reason: 'le journal porte N-1 : la comparaison se fait au même filtre');
    });

    test('la vue « liasse déposée » et les deux colonnes de la maquette restent inchangées (vecteurs)', () {
      expect(cpbColonnesFeuilletEcran('resultat', 'depose', null, e2026).length, 2);
      expect(cpbColonnesFeuillet('resultat', '2026', DateTime(2026, 12, 31), e2026).length, 2);
    });
  });

  group('(b) grand livre : solde d’ouverture écrit / provisoire / inconnu, et solde de clôture', () {
    final liasse = exercice(2025, 'clos', source: 'liasse');
    final exos = [liasse, exercice(2026, 'ouvert'), exercice(2027, 'ouvert')];

    test('sans à-nouveau et après la liasse déposée : INCONNU (jamais zéro), clôture inconnue aussi ; un compte de gestion est « néant » par nature', () {
      final o = cpcOuvertureCompte(exos, e2026, 2026, '571000');
      expect(o.statut, CpcStatutOuverture.inconnue);
      expect(o.solde, isNull);
      expect(o.libelleStatut, 'Inconnu');
      expect(o.motif, contains('liasse'));
      expect(cpcClotureCompte(o, e2026, 2026, '571000').solde, isNull);
      expect(cpcClotureCompte(o, e2026, 2026, '571000').mouvements, 1000);
      final g = cpcOuvertureCompte(exos, e2026, 2026, '706000');
      expect(g.statut, CpcStatutOuverture.gestion);
      expect(g.solde, 0);
      expect(cpcClotureCompte(g, e2026, 2026, '706000').solde, 0, reason: 'vente 1 000 puis CL 1 000 : soldé à la clôture');
    });

    test('ouverture inconnue de N-1 non clos : N est inconnu aussi (rien ne se calcule sur une base inconnue)', () {
      final o = cpcOuvertureCompte(exos, [...e2026, ...e2027], 2027, '571000');
      expect(o.statut, CpcStatutOuverture.inconnue);
      expect(o.solde, isNull);
    });

    test('l’exercice de la liasse se reconnaît même sans fiche amorcée', () {
      final o = cpcOuvertureCompte(const [], e2026, 2026, '571000');
      expect(o.statut, CpcStatutOuverture.inconnue);
      expect(o.motif, contains('liasse'));
    });

    test('pas d’exercice précédent au journal : inconnu', () {
      final o = cpcOuvertureCompte([exercice(2030, 'ouvert')], const [], 2030, '571000');
      expect(o.statut, CpcStatutOuverture.inconnue);
      expect(o.motif, contains('ne figure pas au journal'));
    });

    final an2026 = [
      ligne('AN-2026-00001', '2026-01-01', 'AN', '571000', 5000, 0, origine: cpcOrigineImportOuverture),
      ligne('AN-2026-00001', '2026-01-01', 'AN', '101000', 0, 5000, origine: cpcOrigineImportOuverture),
    ];

    test('à-nouveaux VALIDÉS : ÉCRIT ; un compte absent des à-nouveaux est écrit à zéro ; la clôture ne compte pas deux fois l’ouverture ; brouillons annoncés', () {
      final ecr = [...an2026, ...e2026];
      final o = cpcOuvertureCompte(exos, ecr, 2026, '571000');
      expect(o.statut, CpcStatutOuverture.ecrite);
      expect(o.solde, 5000);
      expect(o.pieces, ['AN-2026-00001']);
      final c = cpcClotureCompte(o, ecr, 2026, '571000');
      expect(c.mouvements, 1000, reason: 'les lignes AN forment l’ouverture, elles ne sont pas des mouvements');
      expect(c.solde, 6000);
      expect(c.brouillons, 1);
      final absent = cpcOuvertureCompte(exos, ecr, 2026, '401000');
      expect(absent.statut, CpcStatutOuverture.ecrite);
      expect(absent.solde, 0);
    });

    test('à-nouveaux en BROUILLON ou CONTRE-PASSÉS : non écrits', () {
      final brouillon = [for (final l in an2026) {...l, 'statut': 'brouillon'}];
      final o = cpcOuvertureCompte(exos, [...brouillon, ...e2026], 2026, '571000');
      expect(o.statut, CpcStatutOuverture.inconnue);
      expect(o.brouillonsAN, 2);
      final contre = [
        ...an2026,
        ligne('AN-2026-C00001', '2026-01-01', 'AN', '571000', 0, 5000, origineCloture: 'an-contre', contrePasseDe: 'AN-2026-00001'),
        ligne('AN-2026-C00001', '2026-01-01', 'AN', '101000', 5000, 0, origineCloture: 'an-contre', contrePasseDe: 'AN-2026-00001'),
      ];
      expect(cpcOuvertureCompte(exos, [...contre, ...e2026], 2026, '571000').statut, CpcStatutOuverture.inconnue);
    });

    test('N-1 OUVERT avec ouverture écrite : N est PROVISOIRE, calculé (et le résultat de N-1 va au 131)', () {
      final ecr = [...an2026, ...e2026.where((x) => x['journal'] != 'CL'), ...e2027];
      final o = cpcOuvertureCompte(exos, ecr, 2027, '571000');
      expect(o.statut, CpcStatutOuverture.provisoire);
      expect(o.solde, 6000, reason: '5 000 reportés + 1 000 validés de 2026 (le brouillon ne compte pas)');
      final r = cpcOuvertureCompte(exos, ecr, 2027, '131000');
      expect(r.solde, -1000, reason: 'bénéfice de 2026 au crédit du 131');
      expect(cpcClotureCompte(o, ecr, 2027, '571000').solde, 6300);
    });

    test('N-1 CLOS avec ses à-nouveaux définitifs : ÉCRIT ; N-1 clos SANS à-nouveaux retrouvés : INCONNU', () {
      final clos = [liasse, exercice(2026, 'clos'), exercice(2027, 'ouvert')];
      final an2027 = [
        ligne('AN-2027-00001', '2027-01-01', 'AN', '571000', 6000, 0, origineCloture: 'an'),
        ligne('AN-2027-00001', '2027-01-01', 'AN', '101000', 0, 5000, origineCloture: 'an'),
        ligne('AN-2027-00001', '2027-01-01', 'AN', '131000', 0, 1000, origineCloture: 'an'),
      ];
      expect(cpcOuvertureCompte(clos, [...an2026, ...e2026, ...an2027, ...e2027], 2027, '571000').solde, 6000);
      final sans = cpcOuvertureCompte(clos, [...an2026, ...e2026, ...e2027], 2027, '571000');
      expect(sans.statut, CpcStatutOuverture.inconnue);
      expect(sans.motif, contains('clôturé'));
    });
  });

  group('(c) journaux CL et AN réservés au moteur', () {
    test('ils ne sont PAS proposés à la saisie manuelle', () {
      final codes = [for (final j in cpaJournauxSaisissables) j.$1];
      expect(codes.contains('AN'), isFalse);
      expect(codes.contains('CL'), isFalse);
      expect(codes, containsAll(['ACH', 'VTE', 'CAI', 'BQ', 'BQE', 'SAL', 'IMM', 'OD']));
      expect(cpaJournalLibelle('CL'), 'Journal de clôture');
    });

    test('la saisie d’une écriture dans CL ou AN est REFUSÉE en nommant le geste qui écrit ce journal', () {
      for (final j in ['AN', 'CL']) {
        expect(
            () => cpaEcrituresDeSaisie(
                date: '2026-05-02', journal: j, libelle: 'essai', centreCout: '', piece: '', lignes: [
                  {'compte': '571000', 'debit': 10, 'credit': 0},
                  {'compte': '101000', 'debit': 0, 'credit': 10},
                ], statut: 'brouillon', exercice: 2026, toutes: const []),
            throwsA(isA<CpaRefus>().having((r) => r.detail, 'détail', contains('réservé au moteur'))),
            reason: j);
      }
    });

    test('la garde de la collection : seuls les gestes de clôture (origineCloture) et d’ouverture (report, import des soldes) écrivent CL et AN', () {
      expect(cpcGardeJournalReserve('inserer', ligne('AN-2026-00009', '2026-01-01', 'AN', '571000', 1, 0, origine: 'Saisie manuelle')), contains('réservé au moteur'));
      expect(cpcGardeJournalReserve('inserer', ligne('CL-2026-00009', '2026-12-31', 'CL', '706000', 1, 0, origine: cpcOrigineImportOuverture)), contains('CL'));
      expect(cpcGardeJournalReserve('modifier', ligne('X', '2026-03-01', 'AN', '571000', 1, 0, origine: 'Saisie manuelle')), isNotNull,
          reason: 'basculer une écriture manuelle au journal AN est refusé aussi');
      expect(cpcGardeJournalReserve('inserer', ligne('AN-2026-00001', '2026-01-01', 'AN', '571000', 1, 0, origine: cpcOrigineImportOuverture)), isNull);
      expect(cpcGardeJournalReserve('inserer', ligne('AN-2026-00001', '2026-01-01', 'AN', '571000', 1, 0, origine: cpcOrigineReportOuverture)), isNull);
      expect(cpcGardeJournalReserve('inserer', ligne('CL-2026-00001', '2026-12-31', 'CL', '706000', 1, 0, origineCloture: 'cl')), isNull);
      expect(cpcGardeJournalReserve('archiver', ligne('AN-2026-00009', '2026-01-01', 'AN', '571000', 1, 0, origine: 'Saisie manuelle')), isNull,
          reason: 'la pré-clôture demande d’archiver des à-nouveaux antérieurs');
      expect(cpcGardeJournalReserve('inserer', ligne('OD-2026-00001', '2026-03-01', 'OD', '571000', 1, 0, origine: 'Saisie manuelle')), isNull);
      // Les pièces du report du bilan d'ouverture passent la garde.
      final rep = cpcReporterANouveaux(const CpcSoldesCloture([{'compte': '571000', 'libelle': 'Caisse', 'solde': 1000.0}], 1000), 2026, dejaEcrits: 0);
      expect(rep.ok, isTrue);
      for (final l in rep.lignes) {
        expect(cpcGardeJournalReserve('inserer', l), isNull);
      }
    });

    test('la vue des journaux montre CL dès que l’exercice en porte une pièce, et seulement alors', () {
      expect(cpaLignesJournaux(e2026).map((j) => j.code), contains('CL'));
      final cl = cpaLignesJournaux(e2026).firstWhere((j) => j.code == 'CL');
      expect([cl.debit, cl.credit, cl.nb], [1000, 1000, 2]);
      expect(cpaLignesJournaux(e2027).map((j) => j.code).contains('CL'), isFalse);
      expect(cpaLignesJournaux(e2027).length, cpaJournaux.length);
    });
  });

  group('(d) l’ouverture automatique de l’exercice suivant n’écrit AUCUNE pièce', () {
    test('elle ne rend que des fiches d’exercice (aucun journal, aucun compte, aucun montant)', () {
      final fiches = cpcExercicesAAmorcer([exercice(2026, 'ouvert')], e2026, DateTime(2026, 12, 1), moisOuvertureSuivant: 12);
      expect([for (final f in fiches) f['annee']], contains(2027));
      for (final f in fiches) {
        expect('${f['id']}', startsWith('EXO-'));
        for (final k in ['journal', 'compte', 'debit', 'credit', 'numero']) {
          expect(f.containsKey(k), isFalse, reason: '${f['id']} porte « $k »');
        }
      }
      final f2027 = fiches.firstWhere((f) => f['annee'] == 2027);
      expect(f2027['etat'], 'ouvert');
      expect(cpcANouveauxEcrits(e2026, 2027), isEmpty, reason: 'aucun à-nouveau n’est écrit par l’ouverture');
    });
  });
}
