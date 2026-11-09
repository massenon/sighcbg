// Les PARAMÈTRES DE L'AIB en base, versionnés (Direction, 09/11/2026) : base de la retenue, branchement IFU, taux de repli, longueur de l'IFU.
// D1 : sans taux arrêté en vigueur, les trois endroits sans fenêtre appliquent 0 % (jamais un taux inventé) avec le motif du moteur ;
// D8 : la fenêtre de l'acheteur GARDE son refus nommé AIB_SANS_BAREME tant que le 1 % n'est pas arrêté — la différence est VOULUE et verrouillée ici.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

CpdFiche v(String id, String situation, num taux, {String? effet, bool arrete = true}) => {
      'id': id,
      'situation': situation,
      'taux': taux,
      'dateEffet': effet,
      'statutArret': arrete ? cpdStatutArrete : cpdStatutNonArrete,
      'arrete': arrete,
      'statut': 'actif',
    };

CpdFiche s(String code, String libelle, String declencheur, int ordre) =>
    {'id': 'S-$code', 'code': code, 'libelle': libelle, 'declencheur': declencheur, 'ordre': ordre, 'statut': 'actif'};

CpdFiche p(String rubrique, int version, Map<String, Object?> champs, {String? effet, String statut = 'actif'}) => {
      'id': 'P-$rubrique-$version',
      'statut': statut,
      'rubrique': rubrique,
      'version': version,
      if (effet != null) 'dateEffet': effet,
      ...champs,
    };

void main() {
  final situations = [
    s('ifu_actif', 'Acheteur avec IFU actif', cpdDeclencheurIfuRenseigne, 1),
    s('ifu_inactif_ou_absent', 'Acheteur sans IFU actif', cpdDeclencheurIfuAbsent, 2),
    s('prestation_service', 'Prestation de service', cpdDeclencheurChoix, 3),
  ];
  final bareme = [
    v('B1', 'ifu_inactif_ou_absent', 5, effet: '2026-09-07'),
    v('B2', 'ifu_actif', 1, arrete: false),
    v('B3', 'prestation_service', 3, arrete: false),
  ];
  final avant = DateTime(2026, 8, 1);
  final apres = DateTime(2026, 11, 9);
  const ifu = '3201642748214';

  group('la graine et les versions datées', () {
    test('la graine : hors taxes, IFU de 13 chiffres présumé actif, repli à 0 %', () {
      const g = CpdParametresAib.graine;
      expect([g.base, g.longueurIfu, g.situationIfuRenseigne, g.situationIfuAbsent, g.tauxRepli, g.deLaGraine], ['ht', 13, 'ifu_actif', 'ifu_inactif_ou_absent', 0, true]);
      final fiches = cpaFichesGraine();
      expect(fiches.map((f) => f['rubrique']), [cpaRubriqueBase, cpaRubriqueBranchement, cpaRubriqueComptes]);
      expect(fiches.every((f) => f['aValider'] == true && f['graine'] == true && !f.containsKey('decideur')), isTrue, reason: 'une graine n\'est pas une décision');
      expect(fiches.any((f) => f.containsKey('dateEffet')), isFalse, reason: 'sans date d\'effet : depuis l\'ouverture, et aucun champ nul');
    });

    test('collection vide : la graine, et elle le dit ; la graine semée donne les mêmes valeurs', () {
      expect(cpaParametresALaDate(const [], apres).deLaGraine, isTrue);
      final semee = cpaParametresALaDate(cpaFichesGraine(), apres);
      expect(semee.deLaGraine, isFalse);
      expect([semee.base, semee.longueurIfu, semee.tauxRepli], ['ht', 13, 0]);
      expect(semee.provenance, contains('base v1'));
    });

    test('la version en vigueur est celle de la date : une validation future ne change pas le passé', () {
      final fiches = [
        ...cpaFichesGraine(),
        p(cpaRubriqueBase, 2, {'base': 'facture'}, effet: '2026-10-01'),
        p(cpaRubriqueBase, 3, {'base': 'ht'}, effet: '2027-01-01'),
      ];
      expect(cpaParametresALaDate(fiches, DateTime(2026, 9, 30)).base, 'ht');
      expect(cpaParametresALaDate(fiches, DateTime(2026, 10, 1)).base, 'facture');
      expect(cpaParametresALaDate(fiches, DateTime(2026, 12, 31)).base, 'facture');
      expect(cpaParametresALaDate(fiches, DateTime(2027, 1, 1)).base, 'ht');
      expect(cpaParametresALaDate(fiches, DateTime(2026, 10, 1)).versionBase, 2);
      expect(cpaVersionSuivante(fiches, cpaRubriqueBase), 4);
      expect(cpaVersionSuivante(fiches, cpaRubriqueBareme), 1);
    });

    test('une version archivée ne s\'applique plus (RG-14), mais son numéro ne se reprend pas', () {
      final fiches = [
        ...cpaFichesGraine(),
        p(cpaRubriqueBase, 2, {'base': 'facture'}, effet: '2026-10-01', statut: 'archive'),
      ];
      expect(cpaParametresALaDate(fiches, apres).base, 'ht');
      expect(cpaVersionSuivante(fiches, cpaRubriqueBase), 3);
    });
  });

  group('le contrôle d\'une validation, avant écriture', () {
    final base = [...cpaFichesGraine(), p(cpaRubriqueBase, 2, {'base': 'facture'}, effet: '2026-10-01')];
    Map<String, Object?> saisie([Map<String, Object?> o = const {}]) =>
        {'decideur': 'Direction', 'dateDecision': '2026-11-09', 'dateEffet': '2026-11-10', 'motif': 'Avis de l\'expert-comptable', 'base': 'ht', ...o};

    test('décideur, date de la décision, motif et date d\'effet sont OBLIGATOIRES', () {
      expect(cpaControlerVersion(cpaRubriqueBase, saisie(), base, apres), isNull);
      expect(cpaControlerVersion(cpaRubriqueBase, saisie({'decideur': ' '}), base, apres), startsWith('PARAM_DECIDEUR_ABSENT'));
      expect(cpaControlerVersion(cpaRubriqueBase, saisie({'dateDecision': ''}), base, apres), startsWith('PARAM_DATE_ABSENTE'));
      expect(cpaControlerVersion(cpaRubriqueBase, saisie({'motif': ''}), base, apres), startsWith('PARAM_MOTIF_ABSENT'));
      expect(cpaControlerVersion(cpaRubriqueBase, saisie({'dateEffet': ''}), base, apres), startsWith('PARAM_DATE_EFFET_ABSENTE'));
      expect(cpaControlerVersion(cpaRubriqueBase, saisie({'dateDecision': '2026-11-10'}), base, apres), startsWith('PARAM_DATE_FUTURE'));
    });

    test('la date d\'effet est POSTÉRIEURE à celle de la version la plus récente : une version ne se réécrit pas', () {
      expect(cpaControlerVersion(cpaRubriqueBase, saisie({'dateEffet': '2026-10-01'}), base, apres), startsWith('PARAM_DATE_ANTERIEURE'));
      expect(cpaControlerVersion(cpaRubriqueBase, saisie({'dateEffet': '2026-09-01'}), base, apres), startsWith('PARAM_DATE_ANTERIEURE'));
    });

    test('la base se choisit entre « ht » et « facture »', () {
      expect(cpaControlerVersion(cpaRubriqueBase, saisie({'base': 'ttc'}), base, apres), startsWith('PARAM_BASE_INVALIDE'));
    });

    test('branchement : longueur 1 à 20, taux de repli 0 à 100, situations ACTIVES du barème', () {
      Map<String, Object?> b([Map<String, Object?> o = const {}]) =>
          saisie({'longueurIfu': 13, 'situationIfuRenseigne': 'ifu_actif', 'situationIfuAbsent': 'ifu_inactif_ou_absent', 'tauxRepli': 0, ...o});
      final vide = <CpdFiche>[];
      String? c(Map<String, Object?> m) => cpaControlerVersion(cpaRubriqueBranchement, m, vide, apres, situations: situations);
      expect(c(b()), isNull);
      expect(c(b({'longueurIfu': 0})), startsWith('PARAM_IFU_LONGUEUR'));
      expect(c(b({'longueurIfu': 21})), startsWith('PARAM_IFU_LONGUEUR'));
      expect(c(b({'tauxRepli': 101})), startsWith('PARAM_TAUX_REPLI'));
      expect(c(b({'tauxRepli': -1})), startsWith('PARAM_TAUX_REPLI'));
      expect(c(b({'situationIfuRenseigne': 'inconnue'})), startsWith('PARAM_SITUATION_INCONNUE'));
    });

    test('la revue du barème n\'exige que la décision (décideur, date, motif)', () {
      expect(cpaControlerVersion(cpaRubriqueBareme, saisie({'dateEffet': null}), const [], apres), isNull);
      expect(cpaControlerVersion(cpaRubriqueBareme, saisie({'decideur': ''}), const [], apres), startsWith('PARAM_DECIDEUR_ABSENT'));
    });
  });

  group('la base de la retenue d\'AIB (D7)', () {
    final facture = {'montantFacture': 118000, 'montantHT': 100000, 'montantTVA': 18000};
    CpdParametresAib avec(String base) => CpdParametresAib(
        base: base, longueurIfu: 13, situationIfuRenseigne: 'ifu_actif', situationIfuAbsent: 'ifu_inactif_ou_absent', tauxRepli: 0, versionBase: 2);

    test('« hors taxes » : le HT quand il est renseigné', () {
      final r = cpaBaseRetenue(facture, avec(cpaBaseHt));
      expect([r.base, r.source, r.repli], [100000, 'ht', false]);
      expect(r.motif, contains('hors taxes'));
    });

    test('« hors taxes » sans HT : repli SUR LE MONTANT FACTURÉ, annoncé', () {
      final r = cpaBaseRetenue({'montantFacture': 118000}, avec(cpaBaseHt));
      expect([r.base, r.source, r.repli], [118000, 'facture', true]);
      expect(r.motif, contains('MONTANT FACTURÉ'));
      expect(r.motif, contains('non renseigné'));
    });

    test('« montant facturé » : toujours le facturé, même quand le HT est renseigné', () {
      final r = cpaBaseRetenue(facture, avec(cpaBaseFacture));
      expect([r.base, r.source, r.repli], [118000, 'facture', false]);
    });

    test('la retenue calculée sur HT : 5 % de 100 000 = 5 000, base et source portées par la pièce', () {
      final b = cpaBaseRetenue(facture, avec(cpaBaseHt));
      final ret = cpdCalculerRetenueAib(bareme, 'ifu_inactif_ou_absent', b.base, apres, situations: situations, baseSource: b.source, baseMotif: b.motif);
      expect([ret.base, ret.montant, ret.taux], [100000, 5000, 5]);
      expect(ret.versFiche()['baseSource'], 'ht');
      final repli = cpaBaseRetenue({'montantFacture': 118000}, avec(cpaBaseHt));
      final ret2 = cpdCalculerRetenueAib(bareme, 'ifu_inactif_ou_absent', repli.base, apres, situations: situations, baseSource: repli.source, baseMotif: repli.motif);
      expect(ret2.montant, 5900);
      expect(ret2.versFiche()['baseMotif'], contains('MONTANT FACTURÉ'));
    });

    test('les montants d\'une facture : HT ≤ facturé, HT + TVA = facturé, la TVA ne va pas sans HT', () {
      expect(cpaControlerMontantsFacture(ht: 100000, tva: 18000, facture: 118000), isNull);
      expect(cpaControlerMontantsFacture(ht: 100000, facture: 118000), isNull);
      expect(cpaControlerMontantsFacture(facture: 118000), isNull);
      expect(cpaControlerMontantsFacture(ht: 120000, facture: 118000), startsWith('FACTURE_HT_SUPERIEUR'));
      expect(cpaControlerMontantsFacture(ht: 100000, tva: 20000, facture: 118000), startsWith('FACTURE_TVA_INCOHERENTE'));
      expect(cpaControlerMontantsFacture(tva: 18000, facture: 118000), startsWith('FACTURE_TVA_SANS_HT'));
      expect(cpaControlerMontantsFacture(ht: -1, facture: 118000), startsWith('FACTURE_HT_NEGATIF'));
    });
  });

  group('D1 contre D8 : 0 % aux trois endroits sans fenêtre, refus gardé à la fenêtre de l\'acheteur', () {
    const graine = CpdParametresAib.graine;

    test('sans IFU, AVANT l\'arrêt du 5 % : aucun taux arrêté → 0 %, avec le motif du moteur', () {
      final r = aibParDefautALaDate(date: avant, situations: situations, versions: bareme, parametres: graine);
      expect([r.taux, r.arrete, r.repli, r.situation], [0, false, true, null]);
      expect(r.motif, contains('Aucun taux arrêté en vigueur au 01/08/2026'));
      expect(r.motif, contains('0 %'));
      expect(r.motif, contains('Aucun taux arrêté avant le 07/09/2026'));
    });

    test('sans IFU, APRÈS le 07/09/2026 : le taux arrêté du barème (5 %), pas un repli', () {
      final r = aibParDefautALaDate(date: apres, situations: situations, versions: bareme, parametres: graine);
      expect([r.taux, r.arrete, r.repli, r.situation], [5, true, false, 'ifu_inactif_ou_absent']);
      expect(r.motif, 'Taux de 5 % arrêté, en vigueur depuis le 07/09/2026.');
    });

    test('avec un IFU actif : le 1 % n\'est pas arrêté → 0 % au défaut (D1), les taux non arrêtés sont offerts, jamais appliqués', () {
      final r = aibParDefautALaDate(ifu: ifu, date: apres, situations: situations, versions: bareme, parametres: graine);
      expect([r.taux, r.arrete], [0, false]);
      expect(r.nonArretes, ['1 % — non arrêté, à valider']);
      expect(r.motif, contains('0 %'));
    });

    test('le taux de repli est celui des PARAMÈTRES : 2 % validé → 2 % sans taux arrêté', () {
      final param = cpaParametresALaDate([
        ...cpaFichesGraine(),
        p(cpaRubriqueBranchement, 2, {'longueurIfu': 13, 'situationIfuRenseigne': 'ifu_actif', 'situationIfuAbsent': 'ifu_inactif_ou_absent', 'tauxRepli': 2}, effet: '2026-10-01'),
      ], apres);
      expect(param.tauxRepli, 2);
      expect(aibParDefautALaDate(ifu: ifu, date: apres, situations: situations, versions: bareme, parametres: param).taux, 2);
      // avant la version 2, la version 1 (0 %) s'applique
      final ancien = cpaParametresALaDate([
        ...cpaFichesGraine(),
        p(cpaRubriqueBranchement, 2, {'tauxRepli': 2}, effet: '2026-10-01'),
      ], DateTime(2026, 9, 1));
      expect(ancien.tauxRepli, 0);
    });

    test('D8 : la FENÊTRE de l\'acheteur garde son refus nommé AIB_SANS_BAREME pour un IFU actif tant que le 1 % n\'est pas arrêté', () {
      final r = aibPourAcheteur(ifu: ifu, date: apres, situations: situations, versions: bareme, parametres: graine);
      expect(r.ok, isFalse);
      expect(r.refus!.code, cpdCodeAibSansBareme);
      expect(r.nonArretes, ['1 % — non arrêté, à valider']);
      // …alors que le défaut des trois autres endroits, lui, applique 0 % : la différence est voulue.
      expect(aibParDefautALaDate(ifu: ifu, date: apres, situations: situations, versions: bareme, parametres: graine).taux, 0);
      final fenetre = acheteurNormaliseAuBareme(ifu: ifu, nom: 'Clinique X', date: apres, situations: situations, versions: bareme, parametres: graine);
      expect(fenetre.acheteur, isNull);
      expect(fenetre.refus!.code, cpdCodeAibSansBareme);
    });

    test('le 1 % arrêté un jour : la fenêtre cesse de refuser, le défaut applique 1 % — lu au barème, jamais écrit dans le code', () {
      final arrete = [...bareme, v('B4', 'ifu_actif', 1, effet: '2026-12-01')];
      final dec = DateTime(2026, 12, 15);
      expect(aibPourAcheteur(ifu: ifu, date: dec, situations: situations, versions: arrete).taux, 1);
      expect(aibParDefautALaDate(ifu: ifu, date: dec, situations: situations, versions: arrete).taux, 1);
      expect(aibParDefautALaDate(ifu: ifu, date: DateTime(2026, 11, 30), situations: situations, versions: arrete).taux, 0);
    });
  });

  group('le branchement IFU : situations présumées et longueur de l\'IFU, lues aux Paramètres', () {
    test('la situation présumée quand l\'IFU est renseigné est celle du branchement, plus celle du déclencheur', () {
      const param = CpdParametresAib(
          base: 'ht', longueurIfu: 13, situationIfuRenseigne: 'prestation_service', situationIfuAbsent: 'ifu_inactif_ou_absent', tauxRepli: 0);
      final r = aibPourAcheteur(ifu: ifu, date: apres, situations: situations, versions: bareme, parametres: param);
      expect(r.situation, 'prestation_service');
      expect(r.presomption, isTrue);
    });

    test('une situation du branchement absente du barème : on retombe sur le déclencheur (jamais un acheteur sans situation)', () {
      const param = CpdParametresAib(
          base: 'ht', longueurIfu: 13, situationIfuRenseigne: 'disparue', situationIfuAbsent: 'ifu_inactif_ou_absent', tauxRepli: 0);
      final r = aibPourAcheteur(ifu: ifu, date: apres, situations: situations, versions: bareme, parametres: param);
      expect(r.situation, 'ifu_actif');
    });

    test('la longueur de l\'IFU vient des Paramètres : 10 chiffres acceptés, 13 refusés avec le bon nombre dans le message', () {
      const dix = CpdParametresAib(
          base: 'ht', longueurIfu: 10, situationIfuRenseigne: 'ifu_actif', situationIfuAbsent: 'ifu_inactif_ou_absent', tauxRepli: 0);
      expect(aibPourAcheteur(ifu: '3201642748', date: apres, situations: situations, versions: bareme, parametres: dix).situation, 'ifu_actif');
      final refus = aibPourAcheteur(ifu: ifu, date: apres, situations: situations, versions: bareme, parametres: dix).refus!;
      expect(refus.code, 'IFU_INVALIDE');
      expect(refus.motif, contains('10 chiffres'));
      expect(validerAcheteurMecef(ifu: ifu, nom: 'X', longueurIfu: 10).refus!.motif, contains('10 chiffres'));
      expect(validerAcheteurMecef(ifu: '3201642748', nom: 'X', longueurIfu: 10).acheteur!.ifu, '3201642748');
    });

    test('un taux de repli de la vente sans acheteur est accepté de 0 à 100 et marqué `aibRepli`', () {
      final a = validerAcheteurMecef(aibTaux: 7, aibRepli: true).acheteur!;
      expect([a.aibTaux, a.aibRepli, a.toJson()['aibRepli']], [7, true, true]);
      expect(validerAcheteurMecef(aibTaux: 7).refus!.code, 'AIB_TAUX_INVALIDE', reason: 'hors repli, la voie héritée reste bornée à 0, 1 ou 5');
      expect(validerAcheteurMecef(aibTaux: 101, aibRepli: true).refus!.code, 'AIB_TAUX_INVALIDE');
    });
  });

  group('les COMPTES de l\'AIB, en base et versionnés (rubrique `comptes`)', () {
    Map<String, Object?> comptes({String subi = '4492', String retenu = '4478', String imputation = '891', String fournisseur = '401000'}) =>
        {'compteAibSubi': subi, 'compteAibRetenu': retenu, 'compteImputation': imputation, 'compteFournisseur': fournisseur};

    test('la graine : 4492, 4478, 891, 401000 ; marquée à confirmer par l\'expert-comptable, sans décideur', () {
      const g = CpdComptesAib.graine;
      expect([g.subi, g.retenu, g.imputation, g.fournisseur, g.deLaGraine, g.aConfirmer], ['4492', '4478', '891', '401000', true, true]);
      final fiche = cpaFichesGraine().firstWhere((f) => f['rubrique'] == cpaRubriqueComptes);
      expect([fiche['compteAibSubi'], fiche['compteAibRetenu'], fiche['compteImputation'], fiche['compteFournisseur']], ['4492', '4478', '891', '401000']);
      expect(fiche['aConfirmerExpertComptable'], isTrue);
      expect(fiche.containsKey('decideur'), isFalse, reason: 'une graine n\'est pas une décision');
      expect(fiche.containsKey('dateEffet'), isFalse);
    });

    test('collection vide : la graine, et elle le dit ; semée : mêmes comptes, version 1, toujours à confirmer', () {
      final vide = cpaComptesALaDate(const [], apres);
      expect([vide.deLaGraine, vide.provenance], [true, contains('graine')]);
      final semee = cpaComptesALaDate(cpaFichesGraine(), apres);
      expect([semee.deLaGraine, semee.version, semee.aConfirmer, semee.subi], [false, 1, true, '4492']);
      expect(semee.marquage, contains('expert-comptable'));
      expect(semee.provenance, contains('à confirmer'));
    });

    test('une version validée (décideur + date) lève le marquage, prend effet à sa date, et la précédente reste lue avant', () {
      final fiches = [
        ...cpaFichesGraine(),
        p(cpaRubriqueComptes, 2, {...comptes(subi: '4491'), 'decideur': 'Expert-comptable', 'dateDecision': '2026-11-10'}, effet: '2026-12-01'),
      ];
      final apresV2 = cpaComptesALaDate(fiches, DateTime(2026, 12, 15));
      expect([apresV2.subi, apresV2.version, apresV2.aConfirmer, apresV2.marquage], ['4491', 2, false, '']);
      final avantV2 = cpaComptesALaDate(fiches, DateTime(2026, 11, 30));
      expect([avantV2.subi, avantV2.version], ['4492', 1], reason: 'les anciennes pièces gardent leurs comptes d\'origine');
    });

    test('une version archivée est ignorée ; un compte absent de la fiche retombe, lui seul, sur la graine', () {
      final fiches = [
        ...cpaFichesGraine(),
        p(cpaRubriqueComptes, 2, comptes(subi: '4491'), effet: '2026-10-01', statut: 'archive'),
        p(cpaRubriqueComptes, 3, {'compteAibSubi': '4493'}, effet: '2026-11-01'),
      ];
      final c = cpaComptesALaDate(fiches, apres);
      expect([c.subi, c.retenu, c.imputation, c.fournisseur, c.version], ['4493', '4478', '891', '401000', 3]);
    });

    test('le contrôle : décideur, date, motif, date d\'effet postérieure, comptes de 3 à 8 chiffres et DISTINCTS', () {
      final base = {'decideur': 'D', 'dateDecision': '2026-11-09', 'motif': 'm', 'dateEffet': '2026-11-10', ...comptes()};
      final existantes = cpaFichesGraine();
      expect(cpaControlerVersion(cpaRubriqueComptes, base, existantes, apres), isNull);
      expect(cpaControlerVersion(cpaRubriqueComptes, {...base, 'decideur': ''}, existantes, apres), contains('PARAM_DECIDEUR_ABSENT'));
      expect(cpaControlerVersion(cpaRubriqueComptes, {...base, 'dateEffet': null}, existantes, apres), contains('PARAM_DATE_EFFET_ABSENTE'));
      expect(cpaControlerVersion(cpaRubriqueComptes, {...base, 'compteAibSubi': '44X2'}, existantes, apres), contains('PARAM_COMPTE_INVALIDE'));
      expect(cpaControlerVersion(cpaRubriqueComptes, {...base, 'compteAibSubi': '12'}, existantes, apres), contains('3 à 8 chiffres'));
      expect(cpaControlerVersion(cpaRubriqueComptes, {...base, 'compteAibSubi': '4478'}, existantes, apres), contains('PARAM_COMPTES_CONFONDUS'));
      final v2 = [...existantes, p(cpaRubriqueComptes, 2, comptes(), effet: '2026-11-20')];
      expect(cpaControlerVersion(cpaRubriqueComptes, base, v2, apres), contains('PARAM_DATE_ANTERIEURE'),
          reason: 'le passé ne se réécrit pas : une version de plus prend une date d\'effet postérieure');
    });
  });
}
