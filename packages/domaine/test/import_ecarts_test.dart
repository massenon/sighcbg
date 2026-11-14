// Les décisions de la Direction du 11/11/2026 sur le module d'importation, rejouées sur un magasin en mémoire : « ignorer les existants » limité à quatre
// jeux, stock détail initial UNE seule fois, transfert contrôlé ligne par ligne (RG-03), comptage sans régularisation, colonne de salaire réservée,
// historique des lots sans les valeurs des cellules, borne de taille, code patient jamais fourni par le fichier (RG-01).
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'import_test.dart' show MagasinMemoire;

MagasinMemoire magasin() => MagasinMemoire({
      'produits': [
        {'id': 'P1', 'code': 'PARA500', 'designation': 'PARACETAMOL 500 MG', 'unite': 'Boîte', 'categorie': 'medicament', 'cump': 100, 'stockGros': 50, 'stockDetail': 0, 'stock': 50, 'statut': 'actif'},
        {'id': 'P2', 'code': 'GANT', 'designation': 'GANTS M', 'unite': 'Boîte', 'categorie': 'conso_medical', 'cump': 2000, 'stockGros': 10, 'stockDetail': 0, 'stock': 10, 'statut': 'actif'},
        {'id': 'P3', 'code': 'AMOX', 'designation': 'AMOXICILLINE', 'unite': 'Boîte', 'categorie': 'medicament', 'cump': 300, 'stockGros': 20, 'stockDetail': 5, 'stock': 25, 'statut': 'actif'},
      ],
      'mouvements': [
        {'id': 'M1', 'reference': 'M000001', 'produitId': 'P3', 'produit': 'AMOXICILLINE', 'type': 'entree', 'typeLabel': 'Entrée', 'quantite': 5, 'stockType': 'detail', 'statut': 'actif'},
      ],
      'emplacements': [
        {'id': 'E1', 'code': 'A1', 'libelle': 'Rayon A1', 'zone': 'Rayonnage sec', 'statut': 'actif'}
      ],
      'courriers': [
        {'id': 'C1', 'reference': 'ARR-2026-0001', 'sens': 'arrivee', 'date': '2026-11-03', 'correspondant': 'DDS', 'objet': 'Convocation', 'statut': 'actif'}
      ],
      'fournisseurs': [
        {'id': 'F1', 'code': 'SOBAPS', 'nom': 'SoBAPS', 'statut': 'actif'}
      ],
      'patients': [
        {'id': 'PAT1', 'code': 'CNT/7/26', 'nom': 'ALI', 'prenom': 'Sika', 'dateNaissance': '1990-01-01', 'statut': 'actif'}
      ],
    });

/// Le fichier est celui du modèle du jeu : l'en-tête puis les lignes (une ligne = les cellules dans l'ordre des colonnes).
List<List<Object?>> fichier(JeuImport j, List<List<Object?>> lignes, {Set<String> accordees = const {}}) => [
      [for (final c in j.colonnesPour(accordees)) c.label],
      ...lignes
    ];

void main() {
  group('ignorer les existants : quatre jeux seulement', () {
    test('produits : la ligne existante est IGNORÉE, listée, jamais modifiée ; la nouvelle est écrite', () {
      final port = magasin();
      final f = fichier(jeuProduits, [
        ['PARA500', 'AUTRE NOM', 'Médicaments', '', 100, 100, '', '', ''],
        ['NEWMED', 'NOUVEAU MEDICAMENT', 'Médicaments', 'Boîte', 400, 400, '', '', ''],
      ]);
      final sans = analyserLignes(jeuProduits, f, 'p.xlsx', port);
      expect(sans.accepte, isFalse, reason: 'sans l’option, l’existant est un refus nommé');
      expect(sans.problemes.where((p) => p.code == 'DOUBLON_MAGASIN'), hasLength(1));

      final a = analyserLignes(jeuProduits, f, 'p.xlsx', port, options: const OptionsImport(ignorerExistants: true));
      expect(a.accepte, isTrue);
      expect(a.ignorees, [2]);
      expect(a.compte.refus, 0);
      final r = appliquer(jeuProduits, a, port);
      expect(r.ok, isTrue);
      expect(r.ecrits, 1, reason: 'une seule fiche écrite : la nouvelle');
      expect(r.lot!['ignores'], [2]);
      expect(r.lot!['nbIgnorees'], 1);
      expect(port.toutes('produits').firstWhere((p) => p['code'] == 'PARA500')['designation'], 'PARACETAMOL 500 MG', reason: 'l’existant n’est pas modifié');
      final neuf = port.toutes('produits').firstWhere((p) => p['code'] == 'NEWMED');
      expect(neuf['stock'], 0);
      expect(neuf['prixVente'], 400);
    });

    test('fournisseurs, emplacements, courriers : permis', () {
      final port = magasin();
      for (final j in [jeuFournisseurs, jeuEmplacements, jeuCourriers]) {
        expect(j.ignorable, isTrue, reason: j.id);
      }
      final a = analyserLignes(jeuEmplacements, fichier(jeuEmplacements, [['A1', 'Autre', 'Réserve', '', ''], ['B1', 'Rayon B1', 'Réserve', '', 12]]), 'e.xlsx', port,
          options: const OptionsImport(ignorerExistants: true));
      expect(a.accepte, isTrue);
      expect(a.ignorees, [2]);
      final c = analyserLignes(jeuCourriers,
          fichier(jeuCourriers, [['Arrivée', '2026-11-03', 'DDS', 'Convocation', '', 'Direction Administrative', ''], ['Départ', '2026-11-04', 'DDS', 'Réponse', 'Lettre', 'Direction Administrative', '']]), 'c.xlsx', port,
          options: const OptionsImport(ignorerExistants: true));
      expect(c.accepte, isTrue);
      expect(c.ignorees, [2]);
      final r = appliquer(jeuCourriers, c, port);
      expect(r.ok, isTrue);
      expect(port.toutes('courriers').firstWhere((x) => x['sens'] == 'depart')['reference'], 'DEP-2026-0001');
    });

    test('JAMAIS sur les patients, les comptes, les pièces : le fichier est refusé en le disant', () {
      final port = magasin();
      for (final j in jeuxImport.where((j) => !j.ignorable)) {
        final a = analyserLignes(j, fichier(j, const [], accordees: j.colonnesReservees), 'x.xlsx', port, options: const OptionsImport(ignorerExistants: true));
        expect(a.accepte, isFalse, reason: j.id);
        expect(a.globaux.map((p) => p.code), contains('IGNORER_INTERDIT'), reason: j.id);
      }
      expect(jeuxImport.where((j) => j.ignorable).map((j) => j.id).toSet(), {'fournisseurs', 'produits', 'emplacements', 'courriers'});
      for (final id in ['patients', 'plan-comptable', 'soldes-ouverture']) {
        expect(jeuImportParId(id)!.ignorable, isFalse, reason: id);
      }
    });
  });

  group('patients : modèle d’accueil (RG-01)', () {
    test('ni code dossier ni groupe sanguin dans le modèle ; le code est GÉNÉRÉ, même si le fichier en propose un', () {
      final labels = [for (final c in jeuPatients.colonnes) c.label];
      expect(labels, isNot(contains('Code dossier')));
      expect(labels, isNot(contains('Groupe sanguin')));
      final port = magasin();
      final f = [
        [...labels, 'Code dossier'],
        ['EXEMPLE', 'Rose', 'F', '1992-02-02', '', '', '', '', '', '', '', '', 'CNT/999/26'],
      ];
      final a = analyserLignes(jeuPatients, f, 'p.xlsx', port);
      expect(a.accepte, isTrue);
      expect(a.globaux.map((p) => p.code), contains('COLONNE_IGNOREE'));
      final r = appliquer(jeuPatients, a, port);
      expect(r.ok, isTrue);
      final fiche = port.toutes('patients').firstWhere((p) => p['nom'] == 'EXEMPLE');
      expect(fiche['code'], isNot('CNT/999/26'));
      expect(fiche['code'], matches(reCodePatient));
      expect(fiche.containsKey('groupeSanguin'), isFalse);
    });
  });

  group('stock détail initial : UNE seule fois', () {
    test('un article sans mouvement au détail est initialisé ; un second import est refusé en le nommant', () {
      final port = magasin();
      final a = analyserLignes(jeuStockDetail, fichier(jeuStockDetail, [['PARA500', 30]]), 'sd.xlsx', port);
      expect(a.accepte, isTrue);
      final r = appliquer(jeuStockDetail, a, port);
      expect(r.ok, isTrue);
      final p = port.toutes('produits').firstWhere((x) => x['code'] == 'PARA500');
      expect(p['stockDetail'], 30);
      expect(p['stock'], 80);
      expect(port.toutes('mouvements').where((m) => m['stockType'] == 'detail' && m['produitId'] == 'P1'), hasLength(1));
      final b = analyserLignes(jeuStockDetail, fichier(jeuStockDetail, [['PARA500', 10]]), 'sd2.xlsx', port);
      expect(b.accepte, isFalse);
      final refus = b.problemes.firstWhere((x) => x.estRefus);
      expect(refus.code, 'STOCK_DETAIL_DEJA_ALIMENTE');
      expect(refus.motif, contains('PARACETAMOL 500 MG'));
    });

    test('un article qui a déjà un mouvement au détail est refusé d’emblée ; un article inconnu aussi', () {
      final port = magasin();
      final a = analyserLignes(jeuStockDetail, fichier(jeuStockDetail, [['AMOX', 10], ['ZZZ', 1]]), 'sd.xlsx', port);
      expect(a.problemes.where((p) => p.estRefus).map((p) => p.code), ['STOCK_DETAIL_DEJA_ALIMENTE', 'PRODUIT_INCONNU']);
    });

    test('le lot ne s’annule pas : il a posé du stock', () {
      final port = magasin();
      final r = appliquer(jeuStockDetail, analyserLignes(jeuStockDetail, fichier(jeuStockDetail, [['GANT', 4]]), 'sd.xlsx', port), port);
      final annul = annulerLot(jeuImportParId, r.lot!['id'], 'test', port);
      expect(annul.ok, isFalse);
      expect(annul.code, 'STOCK_POSE');
    });
  });

  group('transfert gros → détail : RG-03 ligne par ligne, un justificatif', () {
    test('une ligne qui dépasse le stock du magasin est refusée en NOMMANT l’article ; rien n’est écrit', () {
      final port = magasin();
      final a = analyserLignes(jeuTransferts, fichier(jeuTransferts, [['PARA500', 20, 'Bon 12'], ['GANT', 11, 'Bon 12']]), 't.xlsx', port);
      expect(a.accepte, isFalse);
      final refus = a.problemes.firstWhere((p) => p.estRefus);
      expect(refus.code, 'RG03_STOCK_INSUFFISANT');
      expect(refus.n, 3);
      expect(refus.motif, contains('GANTS M'));
      final avant = port.toutes('transferts').length;
      expect(appliquer(jeuTransferts, a, port).ok, isFalse);
      expect(port.toutes('transferts').length, avant);
      expect(port.toutes('produits').firstWhere((x) => x['code'] == 'GANT')['stockGros'], 10);
    });

    test('deux justificatifs dans le même fichier : refus', () {
      final a = analyserLignes(jeuTransferts, fichier(jeuTransferts, [['PARA500', 5, 'Bon 12'], ['GANT', 2, 'Bon 13']]), 't.xlsx', magasin());
      expect(a.accepte, isFalse);
      expect(a.globaux.single.code, 'JUSTIFICATIF_UNIQUE');
    });

    test('un transfert valide écrit UN bon, deux mouvements par ligne, déplace le stock, et ne s’annule pas', () {
      final port = magasin();
      final a = analyserLignes(jeuTransferts, fichier(jeuTransferts, [['PARA500', 20, 'Bon 12'], ['GANT', 10, 'Bon 12']]), 't.xlsx', port);
      expect(a.accepte, isTrue);
      final r = appliquer(jeuTransferts, a, port);
      expect(r.ok, isTrue, reason: '${r.motif}');
      expect(port.toutes('transferts'), hasLength(1));
      expect(port.toutes('transferts').single['justificatifImport'], 'Bon 12');
      final nouveaux = port.toutes('mouvements').where((m) => m['type'] == 'transfert');
      expect(nouveaux, hasLength(4));
      expect(nouveaux.every((m) => '${m['justificatif']}'.contains('Bon 12')), isTrue);
      final gant = port.toutes('produits').firstWhere((x) => x['code'] == 'GANT');
      expect(gant['stockGros'], 0, reason: 'RG-03 : zéro, jamais négatif');
      expect(gant['stockDetail'], 10);
      expect(annulerLot(jeuImportParId, r.lot!['id'], 'x', port).code, 'TRANSFERT_EMIS');
    });
  });

  group('comptage d’inventaire : une saisie, jamais une régularisation', () {
    test('le comptage s’écrit à part ; le stock ne bouge pas ; deux magasins dans un fichier sont refusés', () {
      final port = magasin();
      final a = analyserLignes(jeuInventaire, fichier(jeuInventaire, [['gros', 'PARA500', 47, ''], ['gros', 'GANT', 10, '2026-10-30']]), 'i.xlsx', port);
      expect(a.accepte, isTrue);
      final r = appliquer(jeuInventaire, a, port);
      expect(r.ok, isTrue);
      expect(port.toutes('comptagesInventaire'), hasLength(2));
      expect(port.toutes('produits').firstWhere((x) => x['code'] == 'PARA500')['stockGros'], 50, reason: 'aucune régularisation automatique');
      expect(port.toutes('mouvements').where((m) => m['type'] == 'inventaire'), isEmpty);
      final b = analyserLignes(jeuInventaire, fichier(jeuInventaire, [['gros', 'PARA500', 47, ''], ['detail', 'GANT', 3, '']]), 'i.xlsx', port);
      expect(b.accepte, isFalse);
      expect(b.globaux.single.code, 'MAGASIN_UNIQUE');
    });

    test('une feuille de 200 articles tient', () {
      final port = MagasinMemoire({
        'produits': [for (var i = 0; i < 200; i++) {'id': 'P$i', 'code': 'A$i', 'designation': 'Article $i', 'stockGros': 5, 'stockDetail': 0, 'statut': 'actif'}],
      });
      final a = analyserLignes(jeuInventaire, fichier(jeuInventaire, [for (var i = 0; i < 200; i++) ['gros', 'A$i', i, '']]), 'i.xlsx', port);
      expect(a.accepte, isTrue);
      expect(a.nbLignes, 200);
    });
  });

  group('salaire de base : colonne réservée au droit paie', () {
    final entete = ['Matricule', 'Nom', 'Prénom', 'Sexe', 'Fonction', 'Poste', 'Service'];
    List<List<Object?>> f(bool avecSalaire) => [
          [...entete, if (avecSalaire) 'Salaire de base'],
          ['901', 'EXEMPLE', 'Jean', 'M', 'infirmier', 'Infirmier', 'Soins infirmiers', if (avecSalaire) 150000],
        ];

    test('sans le droit : la colonne est rejetée en la NOMMANT, et absente du modèle', () {
      final port = magasin();
      final a = analyserLignes(jeuPersonnel, f(true), 'pe.xlsx', port);
      expect(a.accepte, isFalse);
      final refus = a.globaux.single;
      expect(refus.code, 'COLONNE_RESERVEE');
      expect(refus.colonne, 'Salaire de base');
      expect([for (final x in modeleImport(jeuPersonnel, port).donnees.first) '$x'], isNot(contains('Salaire de base')));
      expect(analyserLignes(jeuPersonnel, f(false), 'pe.xlsx', port).accepte, isTrue);
    });

    test('avec le droit paie : la colonne est dans le modèle et importée', () {
      final port = magasin();
      const droit = OptionsImport(colonnesAccordees: {'salaireBase'});
      expect([for (final x in modeleImport(jeuPersonnel, port, colonnesAccordees: {'salaireBase'}).donnees.first) '$x'], contains('Salaire de base'));
      final r = appliquer(jeuPersonnel, analyserLignes(jeuPersonnel, f(true), 'pe.xlsx', port, options: droit), port);
      expect(r.ok, isTrue);
      expect(port.toutes('personnel').single['salaireBase'], 150000);
    });
  });

  group('historique des lots : jamais les valeurs des cellules', () {
    test('un lot refusé conserve le rang, la colonne et le code, jamais la valeur lue ni le motif qui la cite', () {
      final port = magasin();
      final a = analyserLignes(jeuProduits, fichier(jeuProduits, [['SECRET-ZZ', 'Désignation secrète', 'pas une catégorie', '', 'abc', '', '', '', '']]), 'p.xlsx', port);
      expect(a.accepte, isFalse);
      final lot = consigner(jeuProduits, a, port)!;
      final erreurs = (lot['erreurs'] as List).cast<Map>();
      expect(erreurs, isNotEmpty);
      for (final e in erreurs) {
        expect(e.keys.toSet(), {'n', 'colonne', 'code', 'niveau', 'geste'});
        expect(e['n'], 2);
      }
      expect('$lot', isNot(contains('pas une catégorie')));
      expect('$lot', isNot(contains('abc')));
    });
  });

  group('borne de taille d’un fichier', () {
    test('un fichier au-dessus de la borne du jeu est refusé AVANT toute lecture, en disant la borne', () {
      final port = magasin();
      final a = analyserFichier(jeuProduits, fichier(jeuProduits, const []), 'gros.xlsx', port, octets: 3000, octetsMax: 2048);
      expect(a.accepte, isFalse);
      expect(a.globaux.single.code, 'FICHIER_TROP_GROS');
      expect(a.globaux.single.motif, contains('2,0 Ko'));
      expect(a.lignes, isEmpty);
    });

    test('à la borne ou en dessous : analysé normalement ; chaque jeu porte une borne par défaut', () {
      final port = magasin();
      final f = fichier(jeuProduits, [['NEW', 'Nouveau', 'Médicaments', '', 10, 10, '', '', '']]);
      expect(analyserFichier(jeuProduits, f, 'p.xlsx', port, octets: 2048, octetsMax: 2048).accepte, isTrue);
      for (final j in jeuxImport) {
        expect(j.octetsMaxDefaut, greaterThan(0), reason: j.id);
      }
    });
  });
}
