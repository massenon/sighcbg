// LA FACTURE À UNE ENTREPRISE (Direction de Baguidi, 17/11/2026, point 2) : une vente normalisée distincte de la facture du patient, avec l'IFU et le nom de l'acheteur, la situation d'AIB
// CHOISIE par le comptable (jamais d'office), numérotée par la série `caisse.factures-tiers`, rattachée à une ligne du relevé de M9, sous un geste réservé, avec des refus nommés.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

CpdFiche v(String id, String situation, num taux, {String? effet, bool arrete = true}) => {
      'id': id, 'situation': situation, 'taux': taux, 'dateEffet': effet, 'statutArret': arrete ? cpdStatutArrete : cpdStatutNonArrete, 'arrete': arrete, 'aValider': !arrete, 'statut': 'actif',
    };
CpdFiche s(String code, String libelle, String declencheur, int ordre) => {'id': 'S-$code', 'code': code, 'libelle': libelle, 'declencheur': declencheur, 'ordre': ordre, 'statut': 'actif'};

F facture(String numero, {String assureur = 'NSIA', String souscripteur = 'GIZ Bénin', num ttc = 20000, num part = 16000, String date = '2026-11-10', String statut = 'actif'}) => {
      'id': 'ID-$numero', 'numero': numero, 'assureur': assureur, 'souscripteur': souscripteur, 'montantTTC': ttc, 'partAssurance': part, 'partPatient': ttc - part, 'date': date, 'statut': statut,
      'lignes': [{'id': 'L1'}],
    };

void main() {
  setUp(Numerotation.reinitialiser);
  tearDown(Numerotation.reinitialiser);
  final situations = [
    s('ifu_actif', 'Acheteur avec IFU actif', cpdDeclencheurIfuRenseigne, 1),
    s('ifu_inactif_ou_absent', 'Acheteur sans IFU actif', cpdDeclencheurIfuAbsent, 2),
    s('prestation_service', 'Prestation de service', cpdDeclencheurChoix, 3),
  ];
  // 5 % arrêté (acheteur sans IFU actif) ; 1 % non arrêté (IFU actif) : seul un taux ARRÊTÉ s'applique.
  final bareme = [v('B1', 'ifu_inactif_ou_absent', 5, effet: '2026-09-07'), v('B2', 'ifu_actif', 1, arrete: false)];
  final auj = DateTime(2026, 11, 16, 10);
  final factures = [facture('FP-2026-00001'), facture('FP-2026-00002', part: 8000), facture('FP-2026-00003', souscripteur: 'Mairie de Parakou')];
  final lignes = assFillesMere(factures, 'NSIA', 'NSIA ASSURANCE', '2026-10-17');
  AssFilleMere? giz() => lignes.where((l) => l.souscripteur == 'GIZ Bénin').firstOrNull;
  const ifu = '3201642748214';

  VerdictFactureTiers emettre({
    String role = 'comptable',
    DroitsGestes? gestes,
    bool fileul = false,
    Object? acheteurIfu = ifu,
    Object? acheteurNom = 'GIZ Bénin SARL',
    Object? situation = 'ifu_inactif_ou_absent',
    AssFilleMere? ligne,
    bool sansLigne = false,
    List<F> tiers = const [],
    List<F> meres = const [],
  }) =>
      emettreFactureTiersPayeur(
          role: role,
          gestes: gestes,
          fileul: fileul,
          acheteurIfu: acheteurIfu,
          acheteurNom: acheteurNom,
          situationChoisie: situation,
          compagnieCode: 'NSIA',
          compagnieNom: 'NSIA ASSURANCE',
          periode: 'mois',
          periodeLibelle: 'Mensuelle',
          depuis: '2026-10-17',
          ligne: sansLigne ? null : (ligne ?? giz()),
          facturesTiers: tiers,
          facturesMere: meres,
          date: auj,
          situations: situations,
          versions: bareme,
          auteur: 'TACHEDI Arialu');

  test('la ligne du relevé de M9 : 24 000 F pris en charge par le souscripteur sur deux factures patients', () {
    expect([giz()!.assureur, giz()!.factures.length], [24000, 2]);
  });

  group('l\'émission réussie : numérotée par la fabrique, rattachée au relevé, normalisée avec son acheteur', () {
    test('numéro de la série `caisse.factures-tiers`, IFU et nom, AIB du barème arrêté sur le hors taxes, rattachement', () {
      final v0 = emettre();
      expect(v0.ok, isTrue, reason: '${v0.refus?.code} ${v0.refus?.motif}');
      final f = v0.fiche!;
      expect(f['numero'], 'FT-2026-00001');
      expect(f['type'], typeFactureTiersPayeur);
      expect([f['acheteurIfu'], f['acheteurNom']], [ifu, 'GIZ Bénin SARL']);
      expect([f['aibSituation'], f['aibTaux']], ['ifu_inactif_ou_absent', 5], reason: 'la situation est celle que le comptable a choisie, le taux celui du barème arrêté');
      expect(f['montantTTC'], 24000);
      expect(f['aibMontant'], 1200, reason: '5 % du hors taxes (produits de santé exonérés : HT = 24 000)');
      expect(f['netAPayer'], 25200, reason: 'HT + AIB, comme la facture certifiée de référence');
      expect(f['statutMecef'], 'en_attente', reason: 'aucun numéro n\'est fabriqué sans appareil');
      expect(f['piecesFilles'], ['FP-2026-00001', 'FP-2026-00002']);
      expect([f['compagnieCode'], f['souscripteur'], f['montantReleve'], f['nbFilles']], ['NSIA', 'GIZ Bénin', 24000, 2]);
      expect(rattachementFactureTiers(f), allOf(contains('GIZ Bénin'), contains('FP-2026-00001'), contains('24 000')));
    });

    test('le numéro suit le plus grand rang porté, archives comprises (une fiche archivée au milieu ne redonne jamais un numéro)', () {
      final tiers = [
        {'numero': 'FT-2026-00001', 'statut': 'actif', 'piecesFilles': ['AUTRE-1']},
        {'numero': 'FT-2026-00006', 'statut': 'archive', 'piecesFilles': ['AUTRE-2']},
      ];
      expect(emettre(tiers: tiers).fiche!['numero'], 'FT-2026-00007');
      // L'année suivante, la série repart à 1.
      final v1 = emettreFactureTiersPayeur(
          role: 'comptable', acheteurIfu: ifu, acheteurNom: 'GIZ', situationChoisie: 'ifu_inactif_ou_absent', compagnieCode: 'NSIA', compagnieNom: 'NSIA ASSURANCE', periode: 'mois',
          periodeLibelle: 'Mensuelle', depuis: '2026-10-17', ligne: giz(), facturesTiers: tiers, date: DateTime(2027, 1, 5), situations: situations, versions: bareme, auteur: 'T');
      expect(v1.fiche!['numero'], 'FT-2027-00001');
    });

    test('la facture du PATIENT reste sans acheteur ni AIB : le moteur de la caisse n\'est pas touché par cette pièce', () {
      expect(acheteurFacturePatient.ifu, isNull);
      expect(acheteurFacturePatient.aibTaux, 0);
      expect(Numerotation.semence('caisse.factures').prefixe, 'FN');
      expect(Numerotation.semence(serieFactureTiers).prefixe, isNot('FN'), reason: 'une série à part');
      expect(Numerotation.semence(serieFactureTiers).aValider, isTrue, reason: 'le préfixe est une proposition à valider');
    });
  });

  group('les refus NOMMÉS, dans l\'ordre, et rien d\'écrit', () {
    test('sans le geste réservé : TIERS_PAYEUR_RESERVE (le caissier, le médecin) ; le comptable et la DAF d\'origine, une fiche de rôle règle', () {
      for (final r in ['caissier', 'medecin', 'admin', '']) {
        expect(emettre(role: r).refus!.code, 'TIERS_PAYEUR_RESERVE', reason: r);
      }
      expect(emettre(role: 'da').ok, isTrue);
      final retire = DroitsGestes(fiches: [
        {'role': 'comptable', 'droitsGestes': {gesteFactureTiersEmettre: false}},
        {'role': 'caissier', 'droitsGestes': {gesteFactureTiersEmettre: true}},
      ]);
      expect(emettre(role: 'comptable', gestes: retire).refus!.code, 'TIERS_PAYEUR_RESERVE');
      expect(emettre(role: 'caissier', gestes: retire).ok, isTrue);
    });

    test('un fileul n\'émet pas (la mère tient la numérotation) : FILEUL_LECTURE_SEULE', () {
      expect(emettre(fileul: true).refus!.code, 'FILEUL_LECTURE_SEULE');
    });

    test('ligne du relevé absente : RELEVE_VIDE ; part prise en charge nulle : MONTANT_NUL', () {
      expect(emettre(sansLigne: true).refus!.code, 'RELEVE_VIDE');
      final nulle = AssFilleMere('Sans part')..factures.add(facture('FP-9', part: 0));
      expect(emettre(ligne: nulle).refus!.code, 'MONTANT_NUL');
    });

    test('une facture patient déjà réclamée par une autre facture à une entreprise, ou par une facture mère émise : FILLE_DEJA_FACTUREE, la pièce est nommée', () {
      final r1 = emettre(tiers: [
        {'numero': 'FT-2026-00002', 'statut': 'actif', 'piecesFilles': ['FP-2026-00002']}
      ]).refus!;
      expect(r1.code, 'FILLE_DEJA_FACTUREE');
      expect(r1.motif, allOf(contains('FP-2026-00002'), contains('FT-2026-00002')));
      final r2 = emettre(meres: [
        {'numero': 'FM-2026-0004', 'statut': 'actif', 'piecesFilles': ['FP-2026-00001']}
      ]).refus!;
      expect(r2.code, 'FILLE_DEJA_FACTUREE');
      expect(r2.motif, contains('FM-2026-0004'));
      // Une pièce ARCHIVÉE ne réclame plus rien (RG-14 : elle a été retirée).
      expect(emettre(tiers: [
        {'numero': 'FT-2026-00002', 'statut': 'archive', 'piecesFilles': ['FP-2026-00002']}
      ]).ok, isTrue);
    });

    test('l\'acheteur : IFU obligatoire, 13 chiffres, nom obligatoire', () {
      expect(emettre(acheteurIfu: '').refus!.code, 'IFU_ACHETEUR_REQUIS');
      expect(emettre(acheteurIfu: null).refus!.code, 'IFU_ACHETEUR_REQUIS');
      expect(emettre(acheteurIfu: '12345').refus!.code, 'IFU_INVALIDE');
      expect(emettre(acheteurNom: '  ').refus!.code, 'NOM_ACHETEUR_ABSENT');
    });

    test('la situation d\'AIB n\'est JAMAIS présumée, même quand l\'IFU suffirait à la déduire : AIB_SITUATION_A_CHOISIR', () {
      expect(emettre(situation: '').refus!.code, 'AIB_SITUATION_A_CHOISIR');
      expect(emettre(situation: null).refus!.code, 'AIB_SITUATION_A_CHOISIR');
    });

    test('un taux NON ARRÊTÉ ne s\'applique jamais : AIB_SANS_BAREME (le 1 % de l\'IFU actif) ; une situation inconnue est refusée', () {
      final r = emettre(situation: 'ifu_actif').refus!;
      expect(r.code, 'AIB_SANS_BAREME');
      expect(r.motif, contains('1 %'));
      expect(emettre(situation: 'inconnue').refus!.code, 'AIB_SANS_BAREME');
    });
  });

  test('le geste est réservé au comptable et à la DAF d\'origine, rattaché à l\'écran de la facture mère', () {
    final g = gesteReserve(gesteFactureTiersEmettre)!;
    expect(g.rolesDefaut, ['comptable', 'da']);
    expect(g.ecran, 'm9-facture-mere');
    expect(DroitsGestes(fiches: const []).rolesAvec(gesteFactureTiersEmettre, const ['admin', 'da', 'direction', 'comptable', 'caissier', 'stock']), ['da', 'comptable']);
  });
}
