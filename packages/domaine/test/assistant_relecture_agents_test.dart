// La relecture des 100 questions d'agents (Direction, 16/11/2026, DECISIONS-16-11-ASSISTANT-AI-AK.md §2), sondée au geste sur le MOTEUR COMPLET : refus gardés, reformulation en
// suivi lue dans la matrice des gestes, deux chiffres (recettes, dette fournisseur) et l'écart, stock reconstitué à une date passée avec son garde, intentions ajoutées sous le
// droit de LEUR écran, petits lots. Aucun rôle n'est nommé pour décider d'un droit : les attentes se calculent depuis rbac.json. Données : EXEMPLES neutres.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_domaine/src/assistant/ast_stock_date.dart';
import 'package:test/test.dart';

import '../tool/src/assistant_mesure.dart';

Map<String, Object?> _json(String chemin) => (jsonDecode(File(chemin).readAsStringSync()) as Map).cast<String, Object?>();

void main() {
  final rbac = _json('../rbac/data/rbac.json');
  final manifeste = Manifeste.depuisJson(_json('../referentiels/data/manifeste.json'));
  final magasin = _json('test/vecteurs/assistant_magasin_agents.json');
  final matrice = MatriceDroits.depuisJson(rbac);
  final a = AssistantAst();

  /// Le contexte de mesure, avec au besoin des collections remplacées, des lectures relevées, une autre matrice des gestes, d'autres décisions de catégories sensibles.
  ContexteAst cx(String role, {Map<String, List<Map<String, Object?>>> en = const {}, List<String>? lectures, DroitsGestes? gestes, List<Map<String, Object?>> fichesSensibles = const [], String? agent}) {
    final base = contexteMesure(magasin, rbac, manifeste, role);
    final g = gestes ?? DroitsGestes(fiches: const [], estArchive: matrice.estArchive);
    return ContexteAst(
      role: role,
      lire: (n) {
        lectures?.add(n);
        return en[n] ?? base.lire(n);
      },
      peutVoirEcran: base.peutVoirEcran,
      sensibles: DroitsSensibles(fiches: fichesSensibles, peutVoirEcran: matrice.peutVoir),
      maintenant: base.maintenant,
      session: SessionLabo(role: role, nom: agent ?? base.session?.nom),
      libelleEcran: base.libelleEcran,
      matrice: MatriceAst(
        roles: base.matrice!.roles,
        libelleRole: base.matrice!.libelleRole,
        roleVoit: base.matrice!.roleVoit,
        roleDetient: g.peut,
        ecransDuModule: base.matrice!.ecransDuModule,
      ),
    );
  }

  String tout(ReponseAst r) => [r.titre, ...r.lignes, if (r.tableau != null) ...[...r.tableau!.colonnes, for (final l in r.tableau!.lignes) ...l]].join(' | ');
  String sansEspaces(String t) => t.replaceAll(RegExp('[   ]'), '');
  final roles = [for (final r in matrice.rolesBruts) if (!matrice.estArchive('${r['id']}')) '${r['id']}'];

  group('(a) refus gardés', () {
    test('la dose d’un médicament : AVIS_MEDICAL_REFUSE pour tout rôle, sans lire une seule donnée', () {
      for (final role in roles) {
        final lectures = <String>[];
        final r = a.repondre('Quelle dose de paracétamol pour un enfant de 5 ans ?', cx(role, lectures: lectures));
        expect([r.statut, r.code], ['refus', 'AVIS_MEDICAL_REFUSE'], reason: role);
        expect(lectures, isEmpty, reason: role);
      }
    });
    test('les résultats d’un patient : refusés (RG-13) à tout rôle qui n’ouvre aucun écran du laboratoire — calculé dans la matrice, aucune valeur, aucun état', () {
      // Q69 (décision du 16/11/2026) : l'accueil lit le STATUT d'un résultat (Oui, En attente), jamais son contenu — par l'écran des patients adressés de l'extérieur (`m1-externe`). Les rôles qui l'ouvrent
      // ne sont plus REFUSÉS : ils reçoivent le statut seul (sondé dans assistant_decisions_reelles_test.dart) ; tous les autres, l'aide-soignante comprise, restent refusés.
      final sansLabo = [for (final role in roles) if (!matrice.peutVoir(role, 'm5-demandes') && !matrice.peutVoir(role, 'm5-resultats') && !matrice.peutVoir(role, 'm1-externe') && !matrice.peutVoir(role, 'm2-imagerie-demandes')) role];
      expect(sansLabo, contains('aide_soignant'), reason: 'la décision du 16/11/2026 garde ce refus pour l’aide-soignante');
      for (final role in sansLabo) {
        final r = a.repondre('resultat labo de CBG/101/26 stp', cx(role));
        expect([r.statut, r.code], ['refus', 'LECTURE_NON_AUTORISEE'], reason: role);
        expect(tout(r), isNot(contains('NFS')), reason: role);
        expect(tout(r), isNot(contains('Validé')), reason: role);
      }
    });
  });

  group('(b) « en attente de ma validation » : un SUIVI quand le rôle n’a pas le geste, lu dans la matrice', () {
    final titulaires = [for (final role in roles) if (DroitsGestes(fiches: const [], estArchive: matrice.estArchive).peut(role, gesteValiderAchats)) matrice.libelle(role)!];
    test('un rôle sans le geste reçoit « en attente de la validation de <poste> », jamais « à valider par vous »', () {
      final sans = [for (final role in roles) if (matrice.peutVoir(role, 'm7-commandes') && !DroitsGestes(fiches: const []).peut(role, gesteValiderAchats)) role];
      expect(sans, contains('direction'));
      for (final role in sans) {
        final r = a.repondre('les commandes qui attendent ma validation', cx(role));
        expect(r.intention, 'I13', reason: role);
        expect(r.titre, contains('(suivi)'), reason: role);
        expect(tout(r), contains('SUIVI'), reason: role);
        expect(tout(r), isNot(contains('votre validation')), reason: role);
        for (final t in titulaires) {
          expect(tout(r), contains(t), reason: '$role : le poste qui valide est NOMMÉ depuis la matrice');
        }
      }
    });
    test('le titulaire du geste reçoit « attendent votre validation »', () {
      for (final role in roles) {
        if (!matrice.peutVoir(role, 'm7-commandes') || !DroitsGestes(fiches: const []).peut(role, gesteValiderAchats)) continue;
        final r = a.repondre('les commandes en attente de ma validation', cx(role));
        expect(r.titre, contains('attendent votre validation'), reason: role);
      }
    });
    test('une décision de la clinique qui donne le geste à la Direction change la réponse : rien n’est écrit en dur', () {
      final decision = DroitsGestes(fiches: const [
        {'id': 'D1', 'role': 'direction', 'droitsGestes': {gesteValiderAchats: true}},
        {'id': 'D2', 'role': 'da', 'droitsGestes': {gesteValiderAchats: false}},
      ], estArchive: matrice.estArchive);
      final dir = a.repondre('les commandes qui attendent ma validation', cx('direction', gestes: decision));
      expect(dir.titre, contains('attendent votre validation'));
      final daf = a.repondre('les commandes qui attendent ma validation', cx('da', gestes: decision));
      expect(daf.titre, contains('(suivi)'));
      expect(tout(daf), contains(matrice.libelle('direction')!));
    });
    test('sans matrice des gestes branchée, la réponse ne prétend jamais « à valider par vous »', () {
      final base = cx('da');
      final nu = ContexteAst(role: 'da', lire: base.lire, peutVoirEcran: base.peutVoirEcran, sensibles: base.sensibles, maintenant: base.maintenant);
      final r = a.repondre('les commandes qui attendent ma validation', nu);
      expect(tout(r), contains('titulaire du geste'));
      expect(tout(r), isNot(contains('votre validation')));
    });
  });

  group('(c) deux chiffres, nommés, et l’écart', () {
    test('« recettes » : l’encaissé ET le facturé dans la même réponse', () {
      final r = a.repondre('on a fait combien de recettes ce mois', cx('direction'));
      final t = sansEspaces(r.titre);
      expect(t, contains('Recettes(encaissé)'));
      expect(t, contains('16500'), reason: 'le jeu de mesure porte un règlement du jour (14/11) en plus de ceux du 4 et du 13');
      expect(t, contains('Chiffred’affaires(facturé)'));
      expect(t, contains('18000'));
    });
    test('dette fournisseur globale : factures non payées (40 000), solde comptable 401 (30 000), écart (10 000), chacun nommé', () {
      final r = a.repondre('combien on doit aux fournisseurs au total', cx('comptable'));
      final t = sansEspaces(tout(r));
      expect(t, contains('1.Facturesfournisseursnonpayées:40000'));
      expect(t, contains('2.Soldecomptableducomptefournisseur(classe401):30000'));
      expect(t, contains('Écart(facturesnonpayées−soldecomptable):10000'));
      expect(t, isNot(contains('brouillon')), reason: 'aucun brouillon sur les 401 du jeu');
    });
    test('par fournisseur, le sous-compte 401 se lit au plan comptable par le NOM ; un écart nul se dit', () {
      final r = a.repondre('on doit combien au fournisseur OMEGA', cx('da', en: {
        'fournisseurs': [
          {'id': 'F9', 'code': 'OMG', 'nom': 'OMEGA', 'tel': ''}
        ],
        'facturesFournisseurs': [
          {'id': 'X', 'fournisseur': 'OMG', 'montantFacture': 25000, 'statutPaiement': 'impayee'}
        ],
        'ecritures': [
          {'id': 'E1', 'compte': '401120', 'date': '2026-11-02', 'credit': 25000, 'debit': 0, 'statut': 'validee'},
          {'id': 'E2', 'compte': '401000', 'date': '2026-11-02', 'credit': 99000, 'debit': 0, 'statut': 'validee'},
        ],
      }));
      final t = sansEspaces(tout(r));
      expect(t, contains('compte fournisseur 401120'.replaceAll(' ', '')));
      expect(t, contains(':25000'));
      expect(t, contains('nul,lesdeuxchiffresconcordent'));
    });
    test('un chiffre hors du périmètre de l’agent n’est pas lu, et l’écart ne se calcule pas sans lui', () {
      expect(matrice.peutVoir('stock', 'm7-factures-fournisseurs'), isTrue);
      expect(matrice.peutVoir('stock', 'm12-grand-livre') || matrice.peutVoir('stock', 'm12-balance'), isFalse);
      final r = a.repondre('notre dette fournisseurs', cx('stock'));
      expect(tout(r), contains('non lu'));
      expect(tout(r), contains('Écart : non calculable'));
      expect(r.sources.map((s) => s.ecran), isNot(contains('m12-grand-livre')));
    });
  });

  group('(d) le stock à une date passée : reconstitué, avec son garde', () {
    test('stock actuel moins mouvements postérieurs, par magasin (entrée, transfert, sortie)', () {
      final p = {'id': 'A', 'stock': 40, 'stockGros': 30, 'stockDetail': 10};
      final m = [
        {'produitId': 'A', 'type': 'entree', 'stockType': 'gros', 'date': '2026-10-20', 'quantite': 20},
        {'produitId': 'A', 'type': 'transfert', 'stockType': 'gros', 'date': '2026-11-01', 'quantite': 10},
        {'produitId': 'A', 'type': 'transfert', 'stockType': 'detail', 'date': '2026-11-01', 'quantite': 10},
        {'produitId': 'A', 'type': 'sortie', 'stockType': 'detail', 'date': '2026-11-05', 'quantite': 5},
        {'produitId': 'A', 'type': 'sortie', 'stockType': 'detail', 'date': '2026-10-01', 'quantite': 99},
      ];
      final r = reconstituerStockA([p], m, '2026-10-12')['A']!;
      expect([r.fiable, r.total, r.gros, r.detail, r.mouvementsPosterieurs], [true, 25, 20, 5, 4]);
      final veille = reconstituerStockA([p], m, '2026-11-01')['A']!;
      expect([veille.total, veille.gros, veille.detail], [45, 30, 15], reason: 'le jour même est compris dans l’état du soir');
    });
    test('le garde : sens inconnu, sans date, sans quantité, stock incohérent, négatif — « non calculable », motif nommé, jamais zéro', () {
      final p = {'id': 'A', 'stock': 10, 'stockGros': 10, 'stockDetail': 0};
      StockALaDate f(List<Map<String, Object?>> m, [Map<String, Object?>? prod]) => reconstituerStockA([prod ?? p], m, '2026-10-01')['A']!;
      expect(f([{'produitId': 'A', 'type': 'inventaire', 'stockType': 'gros', 'date': '2026-10-10', 'quantite': 4}]).motifs.single, contains('ne dit pas son sens'));
      expect(f([{'produitId': 'A', 'type': 'inventaire', 'sens': 'sortie', 'stockType': 'gros', 'date': '2026-10-10', 'quantite': 4}]).total, 14, reason: 'un sens ÉCRIT se rejoue');
      expect(f([{'produitId': 'A', 'type': 'sortie', 'stockType': 'gros', 'date': '', 'quantite': 4}]).motifs.single, contains('pas de date'));
      expect(f([{'produitId': 'A', 'type': 'sortie', 'stockType': 'gros', 'date': '2026-10-10', 'quantite': 'x'}]).motifs.single, contains('quantité'));
      expect(f([], {'id': 'A', 'stock': 10, 'stockGros': 3, 'stockDetail': 3}).motifs.single, contains('incohérent'));
      final neg = f([{'produitId': 'A', 'type': 'entree', 'stockType': 'gros', 'date': '2026-10-10', 'quantite': 15}]);
      expect([neg.fiable, neg.total], [false, null]);
      expect(neg.motifs.single, contains('négatif'));
      expect(f([{'produitId': 'A', 'type': 'transfert', 'date': '2026-10-10', 'quantite': 4}]).motifs.single, contains('sens'), reason: 'un transfert sans magasin ne se rejoue pas');
      final sansMagasin = f([{'produitId': 'A', 'type': 'delivrance_externe', 'sens': 'sortie', 'date': '2026-10-10', 'quantite': 4}]);
      expect([sansMagasin.fiable, sansMagasin.total, sansMagasin.gros], [true, 14, null], reason: 'le total se rejoue, la répartition non');
    });
    test('au moteur : le gestionnaire lit 25 (20 au gros, 5 au détail) ; l’article à mouvement douteux est « non calculable » ; sans l’écran des mouvements, refus nommé', () {
      final ok = a.repondre('le stock de EXEMPLE/Article le 12 octobre', cx('stock'));
      expect(ok.titre, contains('25 en stock au 12/10/2026 (reconstitué)'));
      expect(tout(ok), contains('Magasin (gros) : 20 ; détail : 5'));
      final douteux = a.repondre('il y avait combien de EXEMPLE/Incertain le 1er novembre', cx('stock'));
      expect([douteux.statut, douteux.code], ['non_calculable', 'NON_CALCULABLE']);
      expect(douteux.titre, isNot(contains('0 en stock')));
      // Q45 (décision du 16/11/2026) : le droit est celui de l'ARTICLE (m6-produits), pas celui du registre des mouvements : le caissier, qui lit les produits sans lire les mouvements, lit la quantité
      // reconstituée — et la réponse ne cite aucun mouvement. (L'ancien garde « refus nommé sans m6-mouvements » est levé, et dit.)
      final sansMvt = [for (final role in roles) if (matrice.peutVoir(role, 'm6-produits') && !matrice.peutVoir(role, 'm6-mouvements')) role];
      expect(sansMvt, isNotEmpty);
      for (final role in sansMvt) {
        final r = a.repondre('le stock de EXEMPLE/Article le 12 octobre', cx(role));
        expect(r.statut, 'reponse', reason: role);
        expect(r.titre, contains('25 en stock au 12/10/2026 (reconstitué)'), reason: role);
        expect(r.sources.map((s) => s.ecran), isNot(contains('m6-mouvements')), reason: role);
      }
      // un rôle qui ne lit AUCUN écran du stock reste refusé
      final sansStock = [for (final role in roles) if (!['m6-produits', 'm6-stock-gros', 'm6-stock-detail', 'm6-lots', 'm5-reactifs'].any((e) => matrice.peutVoir(role, e))) role];
      for (final role in sansStock) {
        final r = a.repondre('le stock de EXEMPLE/Article le 12 octobre', cx(role));
        expect([r.statut, r.code], ['refus', 'LECTURE_NON_AUTORISEE'], reason: role);
      }
    });
    test('la valeur à une date passée est « non calculable » (CUMP non conservé) ; les quantités, elles, se reconstituent quand elles tiennent', () {
      final r = a.repondre('la valeur du stock le 12 octobre', cx('stock', en: {
        'produits': [
          {'id': 'A1', 'designation': 'EXEMPLE/Article', 'categorie': 'medicament', 'stock': 40, 'stockGros': 30, 'stockDetail': 10, 'cump': 100}
        ]
      }));
      expect([r.statut, r.code], ['non_calculable', 'NON_CALCULABLE']);
      expect(tout(r), contains('CUMP n’est conservé qu’à aujourd’hui'));
      expect(r.tableau!.lignes.single.last, '25');
    });
  });

  group('(e) les intentions ajoutées : chacune sous le droit de SON écran', () {
    final cas = <(String, String, String)>[
      ('I28', 'quels roles ouvrent les ecrans de la paie', 'm14-roles'),
      ('I29', 'la masse salariale du mois', 'm11-calcul'),
      ('I30', 'balance des comptes du mois', 'm12-balance'),
      ('I31', 'les reunions de la semaine', 'm13-reunions'),
      ('I32', 'ambulance disponible ?', 'm13-repertoire-ambulances'),
      ('I33', 'ma prochaine garde', 'm10-mes'),
      ('I34', 'combien d echographies aujourd hui', 'm2-imagerie'),
      ('I35', 'qui est en conge cette semaine', 'm10-conges'),
    ];
    for (final (id, question, ecran) in cas) {
      test('$id : répond à qui voit un de ses écrans, refuse nommément aux autres (lu dans rbac.json)', () {
        final ecrans = a.catalogue[id]!.ecransLecture;
        expect(ecrans, contains(ecran));
        for (final role in roles) {
          final r = a.repondre(question, cx(role));
          final droit = ecrans.any((e) => matrice.peutVoir(role, e));
          if (droit) {
            expect(r.intention, id, reason: '$role : $question');
            expect(['reponse', 'pas_de_donnees', 'non_calculable'], contains(r.statut), reason: '$role : ${r.code}');
          } else {
            expect([r.statut, r.code], ['refus', 'LECTURE_NON_AUTORISEE'], reason: role);
          }
        }
      });
    }
    test('I28 : les rôles listés sont exactement ceux que la matrice ouvre sur un écran du module de la paie', () {
      final paie = [for (final e in manifeste.tousLesEcrans) if (e.module == 'M11') e.id];
      final attendus = [for (final role in roles) if (paie.any((e) => matrice.peutVoir(role, e))) matrice.libelle(role)];
      final r = a.repondre('quels roles ouvrent les ecrans de la paie', cx('admin'));
      expect([for (final l in r.tableau!.lignes) l.first], attendus);
    });
    test('I29 : un chiffre agrégé, aucun nom, aucun salaire individuel ; toute autre question de paie reste refusée', () {
      final r = a.repondre('la masse salariale du mois', cx('direction'));
      expect(r.statut, 'reponse');
      expect(tout(r), contains('2 agent(s)'));
      for (final p in ((magasin['collections'] as Map)['personnel'] as List)) {
        expect(tout(r), isNot(contains('${(p as Map)['nomComplet']}')));
      }
      for (final q in ['le salaire de Mme EXEMPLE', 'les bulletins de paie du mois', 'la masse salariale par agent', 'les primes de garde du mois']) {
        expect(a.repondre(q, cx('direction')).code, 'PAIE_HORS_ASSISTANT', reason: q);
      }
    });
    test('I30 : balance équilibrée sur les écritures VALIDÉES, brouillons écartés et dits ; la collection `comptes` n’est jamais lue', () {
      final lectures = <String>[];
      final r = a.repondre('balance des comptes du mois', cx('comptable', lectures: lectures));
      expect(tout(r), contains('balance équilibrée (RG-10)'));
      expect(tout(r), contains('2 brouillon(s) écarté(s)'));
      expect(lectures, isNot(contains('comptes')));
      final dese = a.repondre('balance des comptes du mois', cx('comptable', en: {
        'ecritures': [
          {'id': 'E', 'compte': '571000', 'date': '2026-11-03', 'debit': 100, 'credit': 0, 'statut': 'validee'}
        ]
      }));
      expect(tout(dese), contains('DÉSÉQUILIBRÉE'));
    });
    test('I33 : seules les lignes de l’agent CONNECTÉ ; une ligne non validée est dite à part ; un compte non nominatif est refusé', () {
      final r = a.repondre('ma prochaine garde', cx('infirmier'));
      expect(r.titre, contains('20/11/2026'));
      expect(tout(r), contains('non encore validée'));
      expect(tout(r), isNot(contains('15/11/2026')), reason: 'la garde d’un autre agent n’est pas « ma » garde');
      final inconnu = a.repondre('ma prochaine garde', cx('infirmier', agent: 'Poste partagé'));
      expect([inconnu.statut, inconnu.code], ['refus', 'COMPTE_NON_NOMINATIF']);
    });
    test('I34 : les échographies comptées par état, aucun patient nommé', () {
      final r = a.repondre('combien d echographies aujourd hui', cx('echographiste'));
      expect(r.titre, contains('2 échographie(s)'));
      expect(tout(r), isNot(contains('EXEMPLE')));
    });
    test('I35 : les congés accordés ; une demande en attente n’est pas une absence', () {
      final r = a.repondre('qui est en conge cette semaine', cx('da'));
      expect(r.titre, contains('1 congé(s) accordé(s)'));
      expect(tout(r), contains('1 demande(s) en attente'));
    });
  });

  group('(f) petits lots', () {
    test('recherche par NOM : les homonymes sont listés par code, jamais le premier ; par CODE : le dossier', () {
      final h = a.repondre('cherche le patient EXEMPLE', cx('reception'));
      expect([h.statut, h.code], ['ambigue', 'HOMONYMES']);
      expect(h.propositions.length, greaterThanOrEqualTo(2));
      expect(a.repondre('retrouve CBG/101/26', cx('reception')).titre, 'Dossier CBG/101/26');
    });
    test('articles immobiles : la durée sans période dite est le RÉGLAGE de clinique (version datée), pas un littéral', () {
      final defaut = a.repondre('articles immobiles', cx('stock'));
      expect(defaut.titre, contains('les 30 derniers jours'));
      final regle = a.repondre('articles immobiles', cx('stock', en: {
        'parametres': [
          {'id': 'p1', 'cle': cleJoursArticlesImmobiles, 'famille': 'stock', 'type': 'entier', 'valeur': 7, 'defaut': 30, 'version': 0, 'dateEffet': null}
        ]
      }));
      expect(regle.titre, contains('les 7 derniers jours'));
      expect(tout(regle), contains('réglage « Articles immobiles »'));
      final d = definitionDeParametre(cleJoursArticlesImmobiles)!;
      expect([d.famille, d.mobile, d.defaut], ['stock', false, 30]);
    });
    test('impayés : nombre de jours LIBRE ; balance des patients', () {
      expect(a.repondre('les impayés de plus de 45 jours', cx('caissier')).titre, contains('1 facture(s) impayée(s)'));
      final b = a.repondre('balance des patients', cx('comptable'));
      expect(b.intention, 'I16');
      expect(b.tableau!.colonnes.first, 'Ancienneté');
    });
    test('vue du dossier élargie : ordonnances, courriers, compte rendu opératoire, anesthésie — sous le droit de chaque écran et de la catégorie sensible', () {
      final r = a.repondre('tout le dossier de CBG/101/26', cx('medecin'));
      final natures = [for (final l in r.tableau!.lignes) l.first];
      for (final n in ['Ordonnance', 'Courrier — fiche de référence', 'Compte rendu opératoire', 'Fiche d’anesthésie (compte rendu)']) {
        expect(natures, contains(n));
      }
      final reserve = a.repondre('tout le dossier de CBG/101/26', cx('chirurgien', fichesSensibles: const [
        {'id': 'S', 'role': 'chirurgien', 'donneesSensibles': {'hospitalisation_soins': false}}
      ]));
      expect(tout(reserve), contains('Information réservée'));
      expect([for (final l in reserve.tableau?.lignes ?? const <List<String>>[]) l.first], isNot(contains('Compte rendu opératoire')));
    });
    test('aide (I26) et définitions (I27) : « pas de fiche » tant qu’aucune fiche n’est validée — jamais une réponse de mémoire', () {
      for (final q in ['comment faire une sortie contre avis medical', 'que veut dire FEFO', 'c koi une sortie contre avis medical']) {
        final r = a.repondre(q, cx('reception'));
        expect([r.statut, r.code], ['non_calculable', 'PAS_DE_FICHE'], reason: q);
        expect(r.sources, isEmpty, reason: q);
      }
    });
  });
}
