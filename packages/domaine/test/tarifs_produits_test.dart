import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// LE PRIX D'ACHAT DES PRODUITS VERSIONNÉ (famille PRODUIT du référentiel de prix) : version 1 posée à la création ou à la reprise SANS date inventée, une version AJOUTÉE à chaque
/// changement (jamais écrasée), RG-02 refusé hors marge et NOMMÉ, accesseur à la date de la pièce, une seule proposition ouverte, date passée réservée, usage contrôlé sur les lignes.
/// Les articles sont ceux de l'essai (codes `TST-…`) : aucune donnée d'une autre clinique.
typedef M = Map<String, Object?>;

const auj = '2026-11-14';
M med(String code, num achat, {String? id}) => {'id': id ?? 'P-$code', 'code': code, 'designation': 'Article $code', 'categorie': 'medicament', 'prixAchat': achat, 'prixVente': achat, 'statut': 'actif'};
M conso(String code, num achat, {num? vente}) => {'id': 'P-$code', 'code': code, 'designation': 'Article $code', 'categorie': 'conso_medical', 'prixAchat': achat, 'prixVente': vente ?? achat, 'statut': 'actif'};

ReferentielTarifs ref(List<M> produits, {List<M> versionsEnPlus = const []}) {
  final mg = tarMigrerProduits(produits);
  return ReferentielTarifs([
    {'id': 'SENTINELLE', 'code': 'SENTINELLE', 'famille': 'ACTE', 'statut': 'actif'},
    ...mg.tarifs
  ], [...mg.versions, ...versionsEnPlus]);
}

ContexteTarif cx(ReferentielTarifs h, {bool proposer = true, bool decider = false, bool passee = false, bool fileul = false, PiecesTarif pieces = const PiecesTarif(), String role = 'stock'}) => ContexteTarif(
    referentiel: h,
    aujourdhui: auj,
    role: role,
    auteur: 'Agent essai',
    peutProposerProduit: proposer,
    peutDecider: decider,
    peutDatePassee: passee,
    profilsDatePassee: const ['la DAF', 'la Direction'],
    fileul: fileul,
    pieces: pieces);

DemandeProduit dem(String code, Object? achat, {String? date = '2026-11-20', String? motif = 'Nouveau tarif fournisseur', Object? vente, bool valider = false, bool passee = false}) =>
    DemandeProduit(code: code, prixAchat: achat, prixVente: vente, dateEffet: date, motif: motif, valider: valider, datePassee: passee);

void main() {
  final pa = med('TST-MED', 100), pb = conso('TST-CON', 200, vente: 260);

  group('version 1 : reprise et création', () {
    test('la reprise pose la version 1 SANS date d\'effet (aucune date inventée), au prix tenu aujourd\'hui', () {
      final v = tarVersionProduit(pa, 1, 'migration');
      expect([v['version'], v['prixNonAssure'], v['statut'], v['etatAssure']], [1, 100, 'valide', 'unique']);
      expect(v.containsKey('dateEffet'), isFalse);
      expect(v['id'], 'TST-MED@origine@1');
      expect(tarVersionProduit(pb, 1, 'migration')['prixVente'], 260, reason: 'hors médicament, le prix de vente propre vit sur la version');
      expect(tarVersionProduit(pa, 1, 'migration').containsKey('prixVente'), isFalse, reason: 'un médicament n\'a pas de prix de vente propre (RG-02)');
    });

    test('un prix absent ou nul n\'est jamais un tarif : manquant ; l\'article est « à valoriser »', () {
      for (final bad in [null, 0, -3]) {
        final p = {...pa, 'code': 'TST-X', 'prixAchat': bad};
        final v = tarVersionProduit(p, 1, 'migration');
        expect(v['etatNonAssure'], 'manquant');
        expect(v.containsKey('prixNonAssure'), isFalse);
      }
      final h = ref([pa, {...pb, 'prixAchat': null}]);
      final r = tarProduitsAValoriser(h, [pa, {...pb, 'prixAchat': null}], auj);
      expect([for (final x in r) x.produit['code']], ['TST-CON']);
      final p = tarPrixProduit(h, {...pb, 'prixAchat': null}, auj, aujourdhui: auj);
      expect(p.absent, isTrue);
      expect(p.motif, contains('ne se facture jamais à zéro'));
    });

    test('la migration ignore les archivés et les produits déjà dotés ; un doublon de code n\'est repris qu\'une fois', () {
      final mg = tarMigrerProduits([pa, {...pb, 'statut': 'archive'}, conso('TST-DEJA', 5)], dejaDotes: {'TST-DEJA'});
      expect([for (final t in mg.tarifs) t['code']], ['TST-MED']);
      expect(mg.versions.single['version'], 1);
      expect(mg.tarifs.single['famille'], tarFamilleProduit);
    });

    test('la création pose la version 1 « depuis l\'origine », validée ; un article sans prix naît à valoriser', () {
      final h = ref([pa]);
      final nouveau = conso('TST-NEW', 90);
      final r = tarProposerProduit(cx(h), tarDemandeCreationProduit(nouveau), produits: [pa, nouveau]);
      expect(r.ok, isTrue, reason: '${r.refus?.motif}');
      final v = r.valeur!.version;
      expect([v['version'], v['prixNonAssure'], v['statut'], v['origine']], [1, 90, 'valide', 'creation']);
      expect(v.containsKey('dateEffet'), isFalse);
      expect(r.valeur!.identite!['famille'], tarFamilleProduit);
      final sans = {...conso('TST-VIDE', 1), 'prixAchat': null};
      final r2 = tarProposerProduit(cx(h), tarDemandeCreationProduit(sans), produits: [pa, sans]);
      expect(r2.ok, isTrue);
      expect(r2.valeur!.version['etatNonAssure'], 'manquant');
      expect(r2.valeur!.version['motif'], 'Article créé sans prix d’achat : à valoriser');
    });

    test('la création refuse un code déjà versionné et un code de prestation', () {
      final h = ReferentielTarifs([
        {'id': 'X', 'code': 'TST-MED', 'famille': tarFamilleProduit, 'statut': 'actif'},
        {'id': 'CONSULT', 'code': 'CS01', 'famille': 'CONSULTATION', 'statut': 'actif'},
      ], const []);
      expect(tarProposerProduit(cx(h), tarDemandeCreationProduit(pa), produits: [pa]).refus!.code, 'PRIX_DEJA_VERSIONNE');
      final cs = conso('CS01', 10);
      expect(tarProposerProduit(cx(h), tarDemandeCreationProduit(cs), produits: [cs]).refus!.code, 'CODE_EXISTANT');
    });
  });

  group('changer le prix d\'achat : une version AJOUTÉE', () {
    test('la version 2 est proposée, datée, motivée ; la version 1 reste en vigueur jusqu\'au Oui', () {
      final h = ref([pa]);
      final r = tarProposerProduit(cx(h), dem('TST-MED', 120), produits: [pa]);
      expect(r.ok, isTrue, reason: '${r.refus?.motif}');
      final v = r.valeur!.version;
      expect([v['version'], v['prixNonAssure'], v['statut'], v['dateEffet'], v['origine'], v['proposePar']], [2, 120, 'propose', '2026-11-20', 'ecran', 'Agent essai']);
      final h2 = ref([pa], versionsEnPlus: [v]);
      expect(tarPrixProduit(h2, pa, auj, aujourdhui: auj).achat, 100, reason: 'une proposition n\'est jamais lue');
      expect(h2.versionsDe('TST-MED').length, 2, reason: 'la version 1 n\'a pas été écrasée');
    });

    test('accesseur daté : le prix de la PIÈCE, jamais celui d\'aujourd\'hui ; le prix de vente d\'un médicament suit', () {
      final h = ref([pa], versionsEnPlus: [
        {'id': 'TST-MED@2026-11-20@2', 'code': 'TST-MED', 'version': 2, 'prixNonAssure': 130, 'etatAssure': 'unique', 'statut': 'valide', 'dateEffet': '2026-11-20', 'origine': 'ecran'}
      ]);
      final avant = tarPrixProduit(h, pa, '2026-11-19', aujourdhui: auj), apres = tarPrixProduit(h, pa, '2026-11-20', aujourdhui: auj);
      expect([avant.achat, avant.vente, avant.version], [100, 100, 1]);
      expect([apres.achat, apres.vente, apres.version, apres.dateEffet], [130, 130, 2, '2026-11-20']);
      expect(tarPrixProduit(h, pa, '2020-01-01', aujourdhui: auj).achat, 100, reason: 'la version 1 vaut depuis l\'origine');
      expect(tarPrixProduit(h, null, auj, aujourdhui: auj).absent, isTrue);
      expect(tarPrixProduit(h, med('TST-INCONNU', 1), auj, aujourdhui: auj).motif, contains('absent du référentiel'));
    });

    test('hors médicament le prix de vente propre est conservé quand il n\'est pas renseigné', () {
      final h = ref([pb]);
      final r = tarProposerProduit(cx(h), dem('TST-CON', 220), produits: [pb]);
      expect(r.ok, isTrue);
      expect(r.valeur!.version['prixVente'], 260);
    });

    test('RG-02 : un médicament ne se vend ni au-dessus ni au-dessous de son prix d\'achat ; égal est accepté ; refus NOMMÉ', () {
      final h = ref([pa]);
      for (final v in [150, 90]) {
        final r = tarProposerProduit(cx(h), dem('TST-MED', 120, vente: v), produits: [pa]);
        expect(r.refus!.code, 'RG02_MARGE');
        expect(r.refus!.motif, contains('RG-02'));
        expect(r.refus!.geste, contains('Laisser le prix de vente vide'));
      }
      expect(tarProposerProduit(cx(h), dem('TST-MED', 120, vente: 120), produits: [pa]).ok, isTrue);
    });

    test('refus nommés : prix absent, zéro, décimal, motif, date, inchangé, produit inconnu, droit', () {
      final h = ref([pa]);
      String? code(DemandeProduit d, {ContexteTarif? c}) => tarProposerProduit(c ?? cx(h), d, produits: [pa]).refus?.code;
      expect(code(dem('TST-MED', null)), 'PRIX_ABSENT');
      expect(code(dem('TST-MED', '')), 'PRIX_ABSENT');
      expect(code(dem('TST-MED', 0)), 'PRIX_ZERO');
      expect(code(dem('TST-MED', 12.5)), 'PRIX_INVALIDE');
      expect(code(dem('TST-MED', -4)), 'PRIX_INVALIDE');
      expect(code(dem('TST-MED', 130, motif: ' ')), 'MOTIF_REQUIS');
      expect(code(dem('TST-MED', 130, date: null)), 'DATE_EFFET_REQUISE');
      expect(code(dem('TST-MED', 100, date: auj)), 'PRIX_INCHANGE');
      expect(code(dem('TST-ZZZ', 130)), 'PRESTATION_INTROUVABLE');
      expect(code(dem('TST-MED', 130), c: cx(h, proposer: false)), 'PROPOSITION_RESERVEE');
    });

    test('date passée : refusée sans la case, refusée aux profils sans le geste, permise avec le geste ET la case', () {
      final h = ref([pa]);
      final d = dem('TST-MED', 130, date: '2026-11-01');
      expect(tarProposerProduit(cx(h), d, produits: [pa]).refus!.code, 'DATE_PASSEE');
      final avecCase = dem('TST-MED', 130, date: '2026-11-01', passee: true);
      final r = tarProposerProduit(cx(h), avecCase, produits: [pa]);
      expect(r.refus!.code, 'DATE_PASSEE_RESERVEE');
      expect(r.refus!.motif, contains('la DAF et la Direction'));
      final ok = tarProposerProduit(cx(h, passee: true), avecCase, produits: [pa]);
      expect(ok.ok, isTrue);
      expect(ok.valeur!.version['datePassee'], isTrue);
    });

    test('une SEULE proposition ouverte par produit', () {
      final h = ref([pa], versionsEnPlus: [
        {'id': 'TST-MED@2026-11-25@2', 'code': 'TST-MED', 'version': 2, 'prixNonAssure': 110, 'etatAssure': 'unique', 'statut': 'propose', 'dateEffet': '2026-11-25'}
      ]);
      expect(tarProposerProduit(cx(h), dem('TST-MED', 140), produits: [pa]).refus!.code, 'CHANGEMENT_EN_ATTENTE');
      expect(tarProduitsAValoriser(h, [pa], auj), isEmpty, reason: 'un prix en vigueur n\'est pas à valoriser');
    });

    test('valider en un geste : le geste « décider » ; jamais depuis un fileul', () {
      final h = ref([pa]);
      expect(tarProposerProduit(cx(h), dem('TST-MED', 130, valider: true), produits: [pa]).refus!.code, 'VALIDATION_RESERVEE');
      final ok = tarProposerProduit(cx(h, decider: true), dem('TST-MED', 130, valider: true), produits: [pa]);
      expect([ok.valeur!.version['statut'], ok.valeur!.valideeEnUnGeste], ['valide', true]);
      expect(tarProposerProduit(cx(h, decider: true, fileul: true), dem('TST-MED', 130, valider: true), produits: [pa]).refus!.code, 'CONFIGURATION_DE_LA_MERE');
    });

    test('le contrôle d\'usage lit les lignes de pièces qui portent le produit, à partir de la date d\'effet', () {
      final h = ref([pa]);
      final pieces = PiecesTarif(factures: [
        {'id': 'F1', 'numero': 'FA-1', 'date': '2026-11-22', 'statut': 'emise', 'lignes': [{'produitId': 'P-TST-MED', 'montant': 100}]}
      ]);
      final r = tarProposerProduit(cx(h, pieces: pieces), dem('TST-MED', 130, date: '2026-11-21'), produits: [pa]);
      expect(r.refus, isNotNull, reason: 'une pièce émise porte déjà le produit après cette date');
      expect(tarProposerProduit(cx(h, pieces: pieces), dem('TST-MED', 130, date: '2026-11-23'), produits: [pa]).ok, isTrue);
    });
  });

  group('correctif de la fiche, réception, garde RG-02', () {
    test('la fiche suit la version : seuls les champs de prix qui diffèrent', () {
      final h = ref([pa], versionsEnPlus: [
        {'id': 'TST-MED@o@2', 'code': 'TST-MED', 'version': 2, 'prixNonAssure': 140, 'etatAssure': 'unique', 'statut': 'valide', 'dateEffet': '2026-11-10'}
      ]);
      final s = h.instantane(h.parCode['TST-MED']!, auj)!;
      expect(tarCorrectifProduit(pa, s), {'prixAchat': 140, 'prixVente': 140});
      expect(tarCorrectifProduit({...pa, 'prixAchat': 140, 'prixVente': 140}, s), isNull);
      final sans = ref([{...pa, 'prixAchat': null}]);
      expect(tarCorrectifProduit(pa, sans.instantane(sans.parCode['TST-MED']!, auj)!), isNull, reason: 'un prix absent ne corrige rien');
    });

    test('réception : identique / ouverte / déjà ouverte / refusée / sans objet ; jamais d\'écriture directe', () {
      final h = ref([pa]);
      IssuePrixReception r(Object? prix, {ContexteTarif? c, ReferentielTarifs? hh}) =>
          tarProposerPrixReception(c ?? cx(hh ?? h), produit: pa, prixRecu: prix, date: auj, reference: 'REC-1', produits: [pa]);
      expect(r(100).etat, 'identique');
      final o = r(115);
      expect([o.etat, o.ancien, o.prix, o.dateEffet], ['ouverte', 100, 115, auj]);
      expect(o.proposition!.version['statut'], 'propose');
      expect(o.proposition!.version['motif'], 'prix constaté à la réception n° REC-1');
      expect(o.proposition!.valideeEnUnGeste, isFalse);
      final ouverte = ref([pa], versionsEnPlus: [o.proposition!.version]);
      expect(r(125, hh: ouverte).etat, 'deja_ouverte');
      expect(r(0).etat, 'refusee');
      expect(r(0).refus!.code, 'PRIX_ZERO');
      expect(r(null).refus!.code, 'PRIX_ZERO');
      expect(r(12.5).etat, 'sans_objet');
      expect(r(-1).etat, 'sans_objet');
      expect(r(130, c: cx(h, proposer: false)).etat, 'refusee');
    });

    test('la garde RG-02 du magasin : médicament avec marge refusé à l\'insertion et à la modification, nommé ; le reste passe', () {
      expect(tarGardeProduitRg02('inserer', {...pa, 'prixVente': 150}, null), contains('RG-02'));
      expect(tarGardeProduitRg02('modifier', {...pa, 'prixVente': 150}, pa), contains('TST-MED'));
      expect(tarGardeProduitRg02('modifier', {...pa, 'stock': 5}, pa), isNull);
      expect(tarGardeProduitRg02('inserer', {...pb, 'prixVente': 999}, null), isNull, reason: 'hors médicament le prix de vente propre est libre');
      expect(tarGardeProduitRg02('archiver', {...pa, 'prixVente': 150}, pa), isNull);
    });

    test('le refus d\'un article sans prix d\'achat se nomme', () {
      final r = tarRefusPrixAchatAbsent('TST-X', 'Article X');
      expect(r.code, 'PRIX_ACHAT_ABSENT');
      expect(r.motif, contains('TST-X : Article X'));
    });
  });
}
