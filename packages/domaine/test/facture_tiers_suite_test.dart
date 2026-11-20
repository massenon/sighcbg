// LA SUITE DE LA FACTURE À UNE ENTREPRISE (Direction de Baguidi, 17/11/2026, point 2) : l'avoir par le moteur UNIQUE, la transmission au dispositif fiscal par le circuit MECeF existant,
// la demande d'un fileul et le refus d'écriture de la mère. Données fictives.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

class _Appareil implements AdaptateurMecef {
  _Appareil({this.numero, this.refusRendu});
  final String? numero;
  final RefusMecef? refusRendu;
  int appels = 0;
  DemandeCertification? vue;
  @override
  String get mode => 'boitier';
  @override
  bool get configure => true;
  @override
  RefusMecef? get refus => null;
  @override
  Future<ReponseCertification> emettre(DemandeCertification d) async {
    appels++;
    vue = d;
    return numero != null ? ReponseCertification.ok(numero!, '2026-11-17T10:00:00Z') : ReponseCertification.refus(refusRendu!);
  }
}

F piece({String id = 'FTP00001', num ttc = 24000, num aibTaux = 5, String statutMecef = 'en_attente', num avoirs = 0, String statut = 'actif', List<String> filles = const ['FP-1', 'FP-2']}) => {
      'id': id,
      'numero': 'FT-2026-00001',
      'type': typeFactureTiersPayeur,
      'statut': statut,
      'date': '2026-11-16',
      'acheteurIfu': '1201555000123',
      'acheteurNom': 'GIZ Bénin SARL',
      'aibSituation': 'ifu_inactif_ou_absent',
      'aibTaux': aibTaux,
      'montantTTC': ttc,
      'designation': 'Prise en charge des soins — GIZ Bénin (NSIA, Mensuelle)',
      'compagnieCode': 'NSIA',
      'souscripteur': 'GIZ Bénin',
      'piecesFilles': filles,
      'statutMecef': statutMecef,
      if (avoirs > 0) 'montantAvoirs': avoirs,
    };

void main() {
  setUp(Numerotation.reinitialiser);
  tearDown(Numerotation.reinitialiser);
  final auj = DateTime(2026, 11, 17, 9);

  VerdictAvoirTiers avoir({String role = 'comptable', bool fileul = false, F? facture, String motif = 'Erreur de période', num? montant, List<F> tiers = const [], List<F> caisse = const []}) => emettreAvoirFactureTiers(
      role: role, fileul: fileul, facture: facture ?? piece(), idAvoir: 'AVT00001', motif: motif, jour: '2026-11-17', utilisateur: 'TACHEDI Arialu', montant: montant, avoirsTiers: tiers, avoirsCaisse: caisse);

  group('l\'avoir : le moteur UNIQUE, la pièce émise jamais réécrite', () {
    test('avoir total : ligne nommée, numéro de la série partagée, contre-passation ÉQUILIBRÉE en brouillon, AIB de la pièce', () {
      final v = avoir();
      expect(v.ok, isTrue, reason: '${v.refus?.code} ${v.refus?.motif}');
      final e = v.emission!;
      expect(e.avoir['reference'], matches(RegExp(r'^AV-2026-\d{4}$')));
      expect(e.avoir['montant'], 24000);
      expect(e.avoir['type'], typeAvoirFactureTiers);
      expect(e.avoir['factureType'], typeFactureTiersPayeur);
      expect([e.avoir['acheteurNom'], e.avoir['acheteurIfu']], ['GIZ Bénin SARL', '1201555000123']);
      expect(e.avoir['aibMontant'], 1200, reason: '5 % de 24 000 (hors taxes) : l\'AIB de la pièce corrigée');
      expect((e.avoir['lignesAnnulees'] as List).single, containsPair('designation', 'Prise en charge des soins — GIZ Bénin (NSIA, Mensuelle)'));
      expect(e.ecritures, hasLength(2));
      final debit = e.ecritures.fold<num>(0, (a, x) => a + (x['debit'] as num)), credit = e.ecritures.fold<num>(0, (a, x) => a + (x['credit'] as num));
      expect([debit, credit], [24000, 24000], reason: 'RG-10 : débit = crédit, CONSTRUIT');
      expect(e.ecritures.every((x) => x['statut'] == 'brouillon'), isTrue);
      expect(e.avoir.containsKey('statutMecef'), isTrue);
      expect(e.avoir['statutMecef'], 'sans_objet', reason: 'pièce non normalisée : rien à régulariser au dispositif fiscal');
      expect(e.montantAvoirs, 24000);
    });
    test('pièce normalisée : l\'avoir est EN ATTENTE de régularisation MECeF', () {
      final v = avoir(facture: piece(statutMecef: 'valide'));
      expect(v.emission!.avoir['statutMecef'], 'en_attente');
    });
    test('plafond CUMULÉ : un second avoir qui dépasserait est refusé en nommant les montants', () {
      final premier = avoir(montant: 20000).emission!.avoir;
      final v = avoir(facture: piece(avoirs: 20000), montant: 5000, tiers: [{...premier, 'id': 'AVT00001', 'statut': 'actif', 'factureId': 'FTP00001'}]);
      expect(v.ok, isFalse);
      expect(v.refus!.code, 'AVOIR_REFUSE');
      expect(v.refus!.motif, contains('Le cumul des avoirs'));
    });
    test('la série `caisse.avoirs` est UNE : un avoir de la caisse déjà émis décale le numéro, jamais de doublon', () {
      final caisse = [
        {'reference': 'AV-2026-0001', 'statut': 'actif', 'date': '2026-11-10', 'factureId': 'FAC1', 'montant': 1}
      ];
      final v = avoir(caisse: caisse);
      expect(v.emission!.avoir['reference'], 'AV-2026-0002');
    });
    test('un avoir de la caisse qui porterait le même identifiant de pièce ne pèse pas sur le plafond de la facture à une entreprise', () {
      final caisse = [
        {'reference': 'AV-2026-0001', 'statut': 'actif', 'date': '2026-11-10', 'factureId': 'FTP00001', 'montant': 23000}
      ];
      expect(avoir(caisse: caisse).ok, isTrue);
    });
    test('refus nommés : fileul, geste, pièce, archivée, motif, avoir d\'un avoir', () {
      expect(avoir(fileul: true).refus!.code, 'FILEUL_LECTURE_SEULE');
      expect(avoir(role: 'caissier').refus!.code, 'TIERS_PAYEUR_RESERVE');
      expect(avoir(facture: {...piece(), 'type': 'Facture'}).refus!.code, 'FACTURE_TIERS_INTROUVABLE');
      expect(avoir(facture: piece(statut: 'archive')).refus!.code, 'FACTURE_TIERS_ARCHIVEE');
      expect(avoir(motif: '  ').refus!.code, 'MOTIF_AVOIR_REQUIS');
      expect(avoir(montant: 0).refus!.code, 'AVOIR_REFUSE');
    });
    test('un avoir TOTAL libère les factures patients (elles se réclament de nouveau) ; un avoir partiel ne libère rien', () {
      final total = piece(avoirs: 24000);
      final partiel = piece(avoirs: 10000);
      expect(fillesDejaReclamees(facturesTiers: [total]), isEmpty);
      expect(fillesDejaReclamees(facturesTiers: [partiel]).keys, containsAll(['FP-1', 'FP-2']));
    });
    test('le reste avoirable : montant moins les avoirs portés, jamais négatif', () {
      expect(resteAvoirableFactureTiers(piece(avoirs: 9000)), 15000);
      expect(resteAvoirableFactureTiers(piece(avoirs: 30000)), 0);
    });
  });

  group('la transmission : le circuit MECeF des autres ventes, sans numéro fabriqué', () {
    test('préparation : pas d\'encaissement exigé, base = total, AIB sur le hors taxes, net = HT + AIB', () {
      final p = preparerCertificationFactureTiers(piece());
      expect(p.ok, isTrue, reason: '${p.refus?.code}');
      expect([p.demande!.total, p.demande!.base, p.demande!.aib], [24000, 24000, 1200]);
      expect(p.montants!.net, 25200);
      expect([p.demande!.ifuAcheteur, p.demande!.nomAcheteur, p.demande!.aibTaux], ['1201555000123', 'GIZ Bénin SARL', 5]);
    });
    test('refus nommés : déjà normalisée, contre-passée, archivée, pas une facture à une entreprise, IFU absent', () {
      expect(preparerCertificationFactureTiers({...piece(statutMecef: 'valide'), 'numeroMecef': 'MECEF1'}).refus!.code, 'DEJA_NORMALISEE');
      expect(preparerCertificationFactureTiers(piece(avoirs: 24000)).refus!.code, 'PIECE_CONTRE_PASSEE');
      expect(preparerCertificationFactureTiers(piece(statut: 'archive')).refus!.code, 'PIECE_ARCHIVEE');
      expect(preparerCertificationFactureTiers({...piece(), 'type': 'Facture'}).refus!.code, 'PAS_UNE_FACTURE_TIERS');
      expect(preparerCertificationFactureTiers({...piece(), 'acheteurIfu': ''}).refus!.code, 'IFU_ACHETEUR_REQUIS');
      expect(preparerCertificationFactureTiers({...piece(), 'acheteurIfu': '123'}).refus!.code, 'IFU_INVALIDE');
    });
    test('aucun appareil configuré : la pièce reste EN ATTENTE avec le refus nommé du mode, aucun numéro', () async {
      final r = await transmettreFactureTiersPayeur(piece(), const AdaptateurNonConfigure('boitier', modeleBoitier: 'ELTRADE CC300'), maintenant: auj, auteur: 'X', modeleBoitier: 'ELTRADE CC300');
      expect(r.etat, transmissionTiersEnAttente);
      expect(r.patch['statutMecef'], 'en_attente');
      expect(r.patch['codeRetour'], mecefCodeNonConfigure);
      expect(r.patch.containsKey('numeroMecef'), isFalse);
      expect(r.patch['modeleBoitierMecef'], 'ELTRADE CC300');
      expect(r.refus!.code, mecefCodeNonConfigure);
    });
    test('l\'appareil répond : CERTIFIÉE, identifiant et instant de l\'appareil, AIB porté ; la demande lui a envoyé total, base et AIB', () async {
      final a = _Appareil(numero: 'CC300-000042');
      final r = await transmettreFactureTiersPayeur(piece(), a, maintenant: auj, auteur: 'TACHEDI Arialu');
      expect(r.certifiee, isTrue);
      expect(r.patch['statutMecef'], 'valide');
      expect(r.patch['numeroMecef'], 'CC300-000042');
      expect(r.patch['dateTransmission'], '2026-11-17T10:00:00Z');
      expect(r.patch['aibMontant'], 1200);
      expect(r.patch['normalisePar'], 'TACHEDI Arialu');
      expect([a.vue!.total, a.vue!.base, a.vue!.aib], [24000, 24000, 1200]);
    });
    test('l\'appareil refuse : REJETÉE avec code et motif pour la correction', () async {
      final a = _Appareil(refusRendu: const RefusMecef('E-12', 'IFU acheteur inconnu du dispositif.', 'Corriger l’IFU'));
      final r = await transmettreFactureTiersPayeur(piece(), a, maintenant: auj, auteur: 'X');
      expect(r.etat, transmissionTiersRejetee);
      expect([r.patch['statutMecef'], r.patch['codeRetour']], ['rejete', 'E-12']);
    });
    test('une pièce déjà normalisée ne rappelle JAMAIS l\'appareil', () async {
      final a = _Appareil(numero: 'N2');
      final r = await transmettreFactureTiersPayeur({...piece(statutMecef: 'valide'), 'numeroMecef': 'N1'}, a, maintenant: auj, auteur: 'X');
      expect(a.appels, 0);
      expect(r.refus!.code, 'DEJA_NORMALISEE');
      expect(r.patch, isEmpty);
    });
    test('qui transmet : le détenteur du geste d\'émission transmet sa pièce ; sinon la règle des ventes (une fois puis sans limite) ; jamais une pièce normalisée', () {
      expect(refusRetransmissionFactureTiers(piece(), 'comptable'), isNull, reason: 'celui qui émet transmet sa pièce');
      expect(refusRetransmissionFactureTiers({...piece(), 'retransmissions': 3}, 'da'), isNull);
      expect(refusRetransmissionFactureTiers(piece(), 'caissier'), isNull, reason: 'origine : la caisse retransmet une fois');
      expect(refusRetransmissionFactureTiers({...piece(), 'retransmissions': 1}, 'caissier')!.code, 'RETRANSMISSION_RESERVEE');
      expect(refusRetransmissionFactureTiers(piece(), 'infirmier')!.code, 'RETRANSMISSION_INTERDITE');
      expect((refusRetransmissionFactureTiers(piece(statutMecef: 'valide')..['numeroMecef'] = 'N', 'comptable'))!.code, 'DEJA_NORMALISEE');
    });
    test('libellés d\'état : en attente, certifiée, rejetée', () {
      expect(libelleTransmissionTiers(piece()), 'En attente de certification');
      expect(libelleTransmissionTiers(piece(statutMecef: 'valide')), 'Certifiée');
      expect(libelleTransmissionTiers(piece(statutMecef: 'rejete')), 'Rejetée');
    });
  });

  group('un fileul DÉPOSE ; la mère seule écrit', () {
    VerdictDepot deposer(String action, F charge, {String role = 'comptable', F? facture, List<F> depots = const []}) => factureTiersDeposer(
        action: action, charge: charge, role: role, acteur: 'Agent Fileul', poste: 'P2', maintenant: auj, gestes: gestesOrigine(), depots: depots, nouvelId: () => 'VDP-1', facture: facture);
    final emission = {'compagnieCode': 'NSIA', 'periode': 'mois', 'souscripteur': 'GIZ Bénin', 'ifu': '1201555000123', 'nom': 'GIZ Bénin SARL', 'situation': 'ifu_inactif_ou_absent'};

    test('l\'émission déposée : fiche `deposee`, rôle et auteur du geste, charge complète', () {
      final v = deposer(factureTiersActionEmettre, emission);
      expect(v.ok, isTrue, reason: '${v.refus?.code}');
      final f = v.fiche!;
      expect([f['genre'], f['action'], f['etat'], f['demandeRole'], f['demandePar']], [valGenreFactureTiers, 'emettre', valDepotDeposee, 'comptable', 'Agent Fileul']);
      expect(f['cible'], 'NSIA|mois|GIZ Bénin');
      expect((f['charge'] as Map)['ifu'], '1201555000123');
    });
    test('refus nommés dès le poste : geste, relevé, IFU, nom, situation d\'AIB jamais présumée', () {
      expect(deposer(factureTiersActionEmettre, emission, role: 'caissier').refus!.code, 'TIERS_PAYEUR_RESERVE');
      expect(deposer(factureTiersActionEmettre, {...emission, 'souscripteur': ''}).refus!.code, 'RELEVE_VIDE');
      expect(deposer(factureTiersActionEmettre, {...emission, 'ifu': ''}).refus!.code, 'IFU_ACHETEUR_REQUIS');
      expect(deposer(factureTiersActionEmettre, {...emission, 'ifu': '12'}).refus!.code, 'IFU_INVALIDE');
      expect(deposer(factureTiersActionEmettre, {...emission, 'nom': ' '}).refus!.code, 'NOM_ACHETEUR_ABSENT');
      expect(deposer(factureTiersActionEmettre, {...emission, 'situation': ''}).refus!.code, 'AIB_SITUATION_A_CHOISIR');
      expect(deposer('inconnue', emission).refus!.code, 'ACTION_INCONNUE');
    });
    test('rejouable : une demande identique en attente n\'est pas doublée ; une demande refusée peut être redéposée', () {
      final premier = deposer(factureTiersActionEmettre, emission).fiche!;
      final encore = deposer(factureTiersActionEmettre, emission, depots: [premier]);
      expect(encore.dejaDepose, isTrue);
      final refusee = {...premier, 'etat': valDepotRefusee};
      expect(deposer(factureTiersActionEmettre, emission, depots: [refusee]).dejaDepose, isFalse);
    });
    test('l\'avoir et la transmission visent une pièce du poste ; motif obligatoire ; retransmission sous la règle existante', () {
      final p = piece();
      expect(deposer(factureTiersActionAvoir, {'factureId': 'FTP00001', 'motif': 'Erreur'}, facture: p).ok, isTrue);
      expect(deposer(factureTiersActionAvoir, {'factureId': 'FTP00001', 'motif': ''}, facture: p).refus!.code, 'MOTIF_AVOIR_REQUIS');
      expect(deposer(factureTiersActionAvoir, {'factureId': 'FTP00001', 'motif': 'x', 'montant': -3}, facture: p).refus!.code, 'AVOIR_REFUSE');
      expect(deposer(factureTiersActionAvoir, {'factureId': 'ZZ', 'motif': 'x'}).refus!.code, 'FACTURE_TIERS_INTROUVABLE');
      expect(deposer(factureTiersActionTransmettre, {'factureId': 'FTP00001'}, facture: p, role: 'caissier').ok, isTrue);
      expect(deposer(factureTiersActionTransmettre, {'factureId': 'FTP00001'}, facture: {...p, 'retransmissions': 1}, role: 'caissier').refus!.code, 'RETRANSMISSION_RESERVEE');
      expect(deposer(factureTiersActionTransmettre, {'factureId': 'FTP00001'}, facture: {...p, 'retransmissions': 4}).ok, isTrue, reason: 'le comptable transmet sa pièce');
    });
    test('le dernier dépôt ouvert d\'une cible : en attente ou refusé, jamais un dépôt appliqué', () {
      final d = deposer(factureTiersActionAvoir, {'factureId': 'FTP00001', 'motif': 'Erreur'}, facture: piece()).fiche!;
      expect(depotFactureTiersOuvert([d], 'avoir', 'FTP00001')!['etat'], valDepotDeposee);
      expect(depotFactureTiersOuvert([{...d, 'etat': valDepotAppliquee}], 'avoir', 'FTP00001'), isNull);
      expect(depotFactureTiersOuvert([{...d, 'etat': valDepotRefusee}], 'avoir', 'FTP00001')!['etat'], valDepotRefusee);
    });
    test('la mère refuse l\'écriture d\'un poste sur les deux collections ; elle seule applique ; les autres collections ne sont pas concernées', () {
      for (final c in facturesTiersCollectionsSync) {
        expect(refusEcritureFactureTiers(c, mere: false)!.code, 'emission_reservee_mere');
        expect(refusEcritureFactureTiers(c, mere: true), isNull);
      }
      expect(refusEcritureFactureTiers('factures', mere: false), isNull);
      expect(facturesTiersCollectionsSync, ['facturesTiers', 'avoirsTiers']);
    });
  });

  test('les signataires : sans organigramme ni réglage, la ligne dit qu\'il reste à désigner et nomme CE réglage ; sinon le poste qui coiffe l\'organigramme ; un poste du réglage absent garde son intitulé', () {
    expect(signatairesFactureTiers(postes: const [], reglage: '').single.intitule, contains('facture à une entreprise'));
    final postes = [
      {'poste': 'Poste A', 'code': 'PA', 'titulaire': 'Titulaire A', 'parentId': ''},
      {'poste': 'Poste B', 'code': 'PB', 'titulaire': 'Titulaire B', 'parentId': 'x'},
    ];
    expect(signatairesFactureTiers(postes: postes, reglage: null).single.titulaire, 'Titulaire A');
    final deux = signatairesFactureTiers(postes: postes, reglage: 'PB;Poste inconnu');
    expect([deux[0].titulaire, deux[1].intitule, deux[1].titulaire], ['Titulaire B', 'Poste inconnu', null]);
  });

  test('les signataires de la pièce sont un RÉGLAGE de clinique (vide par défaut), posé sous le geste d\'émission, déposable depuis un fileul', () {
    final def = definitionDeParametre(factureTiersCleSignataires)!;
    expect(def.defaut, '');
    expect(gesteDuReglage(factureTiersCleSignataires), gesteFactureTiersEmettre);
  });
}
