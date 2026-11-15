// Les SONDES D'INVARIANTS du sous-lot stock, achats, caisse et comptabilité du jeu de démonstration Baguidi : stock jamais négatif, stock égal à la somme signée
// des mouvements et à la somme des lots, chaque sortie justifiée par une pièce qui existe, FEFO rejoué mouvement par mouvement (RG-05), huit produits sous leur
// seuil, transferts qui conservent le total, chaque facture fournisseur rapprochée de sa livraison, chaque pièce comptable équilibrée (RG-10) avec une ligne à
// un seul sens, pièces validées exactement celles d'août et de septembre, créances égales aux parts assureur non réglées, une seule échéance dépassée, dépenses
// égales à la somme de leurs lignes. Les deux refus RG-03 sont REJOUÉS ici, sur les moteurs, sans rien écrire.
// Le générateur est lancé EN MÉMOIRE (aucune écriture sur le disque).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import '../tool/generer_jeu_baguidi.dart';
import '../tool/jeu_baguidi/contexte.dart';
import '../tool/jeu_baguidi/stock_base.dart' show comptableCaisse, comptableStock, direction1, direction2;

typedef F = Map<String, Object?>;

List<F> lire(Map<String, String> j, String nom) => [for (final f in jsonDecode(j['$nom.json']!) as List) (f as Map).cast<String, Object?>()];
num n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);

void main() {
  final jeu = construireJeu();
  List<F> c(String nom) => lire(jeu, nom);

  final produits = c('produits');
  final lots = c('lots');
  final mouvements = c('mouvements');
  final ecritures = c('ecritures');
  final factures = c('factures');
  final inventaires = c('inventaires');
  final aujourdhui = Contexte.maintenant;

  F produit(Object? id) => produits.firstWhere((p) => p['id'] == id);

  // --- stock ---------------------------------------------------------------------------------------------------------------------------------

  test('150 produits : 120 sur cinq familles et 30 réactifs et consommables de laboratoire, prix de vente égal au prix d\'achat (RG-02), valorisation provisoire', () {
    expect(produits.length, 150);
    final familles = <String, int>{};
    for (final p in produits) {
      familles['${p['categorie']}'] = (familles['${p['categorie']}'] ?? 0) + 1;
    }
    expect(familles.length, 7);
    expect(produits.where((p) => p['categorie'] == 'reactif' || p['categorie'] == 'conso_labo').length, 30);
    expect(produits.where((p) => p['categorie'] != 'reactif' && p['categorie'] != 'conso_labo').length, 120);
    for (final p in produits) {
      expect(p['prixVente'], p['prixAchat'], reason: '${p['designation']} : RG-02, aucune marge');
      expect(n(p['prixAchat']), greaterThan(0));
      expect(n(p['cump']), greaterThan(0));
      expect(p['valorisationProvisoire'], true);
      expect(p['fictif'], true);
    }
    expect(produits.map((p) => p['designation']).toSet().length, 150);
    expect(produits.map((p) => p['code']).toSet().length, 150);
    expect(produits.where((p) => p['urgence'] == true).length, inInclusiveRange(18, 25));
  });

  test('le stock n\'est jamais négatif, le total est toujours gros plus détail, et il n\'y a aucune rupture', () {
    for (final p in produits) {
      expect(n(p['stockGros']), greaterThanOrEqualTo(0), reason: '${p['designation']}');
      expect(n(p['stockDetail']), greaterThanOrEqualTo(0), reason: '${p['designation']}');
      expect(n(p['stock']), n(p['stockGros']) + n(p['stockDetail']), reason: '${p['designation']}');
      expect(n(p['stock']), greaterThan(0), reason: '${p['designation']} : pas de rupture');
    }
    expect(produits.where((p) => n(p['stockDetail']) > 0).length, greaterThan(40));
  });

  test('le stock de chaque produit, par magasin, est la somme SIGNÉE de ses mouvements', () {
    final ecartsInventaire = <String, num>{};
    for (final inv in inventaires.where((i) => i['statutInv'] == 'valide')) {
      for (final l in (inv['lignes'] as List).cast<Map>()) {
        ecartsInventaire['Inventaire ${inv['reference']}/${l['code']}'] = n(l['ecart']);
      }
    }
    final gros = <String, num>{};
    final detail = <String, num>{};
    void pose(String id, String magasin, num q) {
      final cible = magasin == 'gros' ? gros : detail;
      cible[id] = (cible[id] ?? 0) + q;
    }

    for (final m in mouvements) {
      final id = '${m['produitId']}';
      final q = n(m['quantite']);
      switch ('${m['type']}') {
        case 'entree':
          pose(id, '${m['stockType']}', q);
        case 'sortie' || 'perte' || 'casse' || 'peremption':
          pose(id, '${m['stockType']}', -q);
        case 'transfert':
          if ('${m['typeLabel']}'.contains('sortie magasin')) pose(id, 'gros', -q);
          if ('${m['typeLabel']}'.contains('entrée pharmacie')) pose(id, 'detail', q);
        case 'inventaire':
          final e = ecartsInventaire['${m['justificatif']}/${produit(id)['code']}'];
          expect(e, isNotNull, reason: 'écart d\'inventaire introuvable pour ${m['justificatif']}');
          expect(e!.abs(), q);
          pose(id, '${m['stockType']}', e);
        default:
          fail('type de mouvement inattendu : ${m['type']}');
      }
    }
    for (final p in produits) {
      expect(gros[p['id']] ?? 0, n(p['stockGros']), reason: 'gros de ${p['designation']}');
      expect(detail[p['id']] ?? 0, n(p['stockDetail']), reason: 'détail de ${p['designation']}');
    }
  });

  test('le stock courant ne passe JAMAIS sous zéro pendant le déroulé (rejeu des mouvements dans l\'ordre d\'écriture)', () {
    final gros = <String, num>{};
    final detail = <String, num>{};
    final ecarts = <String, num>{};
    for (final inv in inventaires.where((i) => i['statutInv'] == 'valide')) {
      for (final l in (inv['lignes'] as List).cast<Map>()) {
        ecarts['Inventaire ${inv['reference']}/${l['code']}'] = n(l['ecart']);
      }
    }
    for (final m in mouvements) {
      final id = '${m['produitId']}';
      final q = n(m['quantite']);
      void ajoute(String magasin, num v) {
        final cible = magasin == 'gros' ? gros : detail;
        cible[id] = (cible[id] ?? 0) + v;
        expect(cible[id]!, greaterThanOrEqualTo(0), reason: '${m['reference']} ${m['date']} : ${produit(id)['designation']} ($magasin) tombe sous zéro');
      }

      switch ('${m['type']}') {
        case 'entree':
          ajoute('${m['stockType']}', q);
        case 'sortie' || 'perte' || 'casse' || 'peremption':
          ajoute('${m['stockType']}', -q);
        case 'transfert':
          if ('${m['typeLabel']}'.contains('sortie magasin')) ajoute('gros', -q);
          if ('${m['typeLabel']}'.contains('entrée pharmacie')) ajoute('detail', q);
        case 'inventaire':
          ajoute('${m['stockType']}', ecarts['${m['justificatif']}/${produit(id)['code']}']!);
      }
    }
  });

  test('l\'ordre d\'écriture des mouvements est chronologique, et les références de la série M sont uniques', () {
    final dates = [for (final m in mouvements) '${m['date']}'];
    expect(dates, [...dates]..sort());
    expect(mouvements.map((m) => m['id']).toSet().length, mouvements.length);
    final series = [for (final m in mouvements) if (RegExp(r'^M\d{6}$').hasMatch('${m['reference']}')) '${m['reference']}'];
    expect(series.toSet().length, series.length);
    expect(mouvements.length, inInclusiveRange(780, 950));
    expect(mouvements.every((m) => '${m['date']}'.compareTo('2026-08-01') >= 0 && '${m['date']}'.compareTo('2026-11-07') <= 0), isTrue);
  });

  test('chaque sortie est rattachée à un justificatif qui EXISTE (facture, bon de besoins, bon de transfert, inventaire, constat)', () {
    final numerosFactures = {for (final f in factures) '${f['numero']}'};
    final references = {
      for (final b in c('besoins')) 'Bon de besoins ${b['reference']}': b,
      for (final t in c('transferts')) 'Bon de transfert ${t['reference']}': t,
      for (final i in inventaires) 'Inventaire ${i['reference']}': i,
    };
    var sorties = 0;
    for (final m in mouvements.where((m) => m['type'] != 'entree')) {
      sorties++;
      final j = '${m['justificatif'] ?? ''}';
      expect(j, isNotEmpty, reason: 'mouvement ${m['reference']} sans justificatif (RG-03)');
      if (m['type'] == 'sortie' && j.startsWith('Facture ')) {
        expect(numerosFactures.contains(j.substring('Facture '.length)), isTrue, reason: j);
      } else if (m['type'] == 'perte' || m['type'] == 'casse' || m['type'] == 'peremption') {
        expect(j, startsWith('Constat de '));
      } else {
        expect(references.containsKey(j), isTrue, reason: 'justificatif introuvable : $j');
      }
    }
    expect(sorties, greaterThan(500));
    // Une sortie de bon de besoins sert la quantité ACCORDÉE, jamais la demandée.
    for (final b in c('besoins').where((b) => b['etape'] == 'distribue')) {
      for (final l in (b['lignes'] as List).cast<Map>()) {
        final servi = mouvements
            .where((m) => m['justificatif'] == 'Bon de besoins ${b['reference']}' && m['produitId'] == l['produitId'])
            .fold<num>(0, (s, m) => s + n(m['quantite']));
        expect(servi, n(l['quantiteAccordee']), reason: '${b['reference']} ${l['produit']}');
        expect(n(l['quantiteLivree']), n(l['quantiteAccordee']));
      }
    }
  });

  test('FEFO (RG-05) rejoué : chaque sortie vide le premier lot à périmer, jamais un lot périmé ; chaque lot se réconcilie avec ses sorties', () {
    final parNumero = {for (final l in lots) '${l['numeroLot']}': l};
    expect(parNumero.length, lots.length, reason: 'numéros de lot uniques');
    final restant = <String, num>{};
    for (final m in mouvements) {
      final lot = m['lot'] == null ? null : parNumero['${m['lot']}'];
      final id = '${m['produitId']}';
      if (m['type'] == 'entree' && lot != null) {
        restant[lot['numeroLot'] as String] = (restant[lot['numeroLot']] ?? 0) + n(m['quantite']);
        continue;
      }
      if (m['type'] == 'transfert') {
        expect(m['lot'], isNull);
        continue;
      }
      expect(lot, isNotNull, reason: 'sortie ${m['reference']} sans lot');
      expect(lot!['produitId'], id);
      final date = '${m['date']}';
      final candidats = [
        for (final l in lots)
          if (l['produitId'] == id && n(restant[l['numeroLot']] ?? 0) > 0 && '${l['datePeremption']}'.compareTo(date) >= 0) l
      ]..sort((a, b) => '${a['datePeremption']}'.compareTo('${b['datePeremption']}'));
      expect(candidats, isNotEmpty);
      expect('${lot['datePeremption']}', '${candidats.first['datePeremption']}', reason: 'FEFO violé : ${m['reference']} ${produit(id)['designation']} le $date');
      expect('${lot['datePeremption']}'.compareTo(date) >= 0, isTrue, reason: 'lot périmé utilisé le $date');
      restant['${lot['numeroLot']}'] = (restant['${lot['numeroLot']}'] ?? 0) - n(m['quantite']);
      expect(restant['${lot['numeroLot']}']!, greaterThanOrEqualTo(0));
    }
    for (final l in lots) {
      expect(restant['${l['numeroLot']}'] ?? 0, n(l['quantiteRestante']), reason: 'lot ${l['numeroLot']}');
    }
    // Un lot n'entre qu'une fois : sa quantité initiale est celle de son entrée.
    for (final l in lots) {
      final entrees = mouvements.where((m) => m['type'] == 'entree' && m['lot'] == l['numeroLot']).fold<num>(0, (s, m) => s + n(m['quantite']));
      expect(entrees, n(l['quantiteInitiale']), reason: '${l['numeroLot']}');
    }
  });

  test('FEFO non trivial : au moins un produit porte deux lots dont le plus récent périme le premier', () {
    final parProduit = <String, List<F>>{};
    for (final l in lots) {
      (parProduit['${l['produitId']}'] ??= []).add(l);
    }
    final doubles = parProduit.values.where((v) => v.length > 1).toList();
    expect(doubles.length, inInclusiveRange(25, 30));
    expect(doubles.fold<int>(0, (s, v) => s + v.length - 1), 30, reason: 'trente lignes livrées, un lot chacune');
    expect(doubles.where((v) => '${v.last['datePeremption']}'.compareTo('${v.first['datePeremption']}') < 0).length, greaterThan(5));
  });

  test('180 lots, le stock de chaque produit est la somme de ses lots, la valeur du stock est la somme de la valeur de ses lots, 6 lots proches de la péremption, 2 périmés', () {
    expect(lots.length, 180);
    final parProduit = <String, num>{};
    for (final l in lots) {
      parProduit['${l['produitId']}'] = (parProduit['${l['produitId']}'] ?? 0) + n(l['quantiteRestante']);
      expect(n(l['quantiteRestante']), greaterThanOrEqualTo(0));
    }
    for (final p in produits) {
      expect(parProduit[p['id']] ?? 0, n(p['stock']), reason: '${p['designation']}');
    }
    final valeurLots = lots.fold<num>(0, (s, l) => s + n(l['quantiteRestante']) * n(produit(l['produitId'])['cump']));
    expect(valeurLots, closeTo(d.valeurStock(produits), 0.01));
    final jours = {for (final l in lots) '${l['numeroLot']}': d.joursAvantPeremption(aujourdhui, l['datePeremption'])!};
    expect(jours.values.where((j) => j < 0).length, 2);
    expect(jours.values.where((j) => j >= 0 && j <= 60).length, 6);
    expect(jours.values.where((j) => j > 60).length, 172);
    for (final l in lots) {
      final j = jours['${l['numeroLot']}']!;
      expect(l['statut'], j < 0 ? 'perime' : (j <= 90 ? 'alerte' : 'actif'), reason: '${l['numeroLot']}');
    }
  });

  test('seuils d\'alerte fixés partout, exactement 8 produits sous leur seuil, aucun en rupture', () {
    expect(produits.every((p) => d.seuilFixe(p['seuilAlerte'])), isTrue);
    final sous = produits.where((p) => d.sousSeuil(p['stock'], p['seuilAlerte'])).toList();
    expect(sous.length, 8);
    expect(sous.every((p) => d.sousSeuilHorsRupture(p['stock'], p['seuilAlerte'])), isTrue);
    expect(d.sansSeuilFixe(produits), isEmpty);
    expect(d.aReapprovisionner(produits).length, 8);
  });

  test('15 transferts multi-lignes qui CONSERVENT le total : sortie du magasin égale entrée à la pharmacie, ligne par ligne, et le total du produit ne bouge pas', () {
    final bons = c('transferts');
    expect(bons.length, 15);
    for (final b in bons) {
      final lignes = (b['lignes'] as List).cast<Map>();
      expect(lignes.length, greaterThanOrEqualTo(8));
      expect(b['nbLignes'], lignes.length);
      expect(n(b['quantiteTotale']), lignes.fold<num>(0, (s, l) => s + n(l['quantite'])));
      final mv = mouvements.where((m) => m['reference'] == b['reference']).toList();
      expect(mv.length, lignes.length * 2, reason: '${b['reference']}');
      for (final l in lignes) {
        final sortie = mv.where((m) => m['produitId'] == l['produitId'] && '${m['typeLabel']}'.contains('sortie magasin')).fold<num>(0, (s, m) => s + n(m['quantite']));
        final entree = mv.where((m) => m['produitId'] == l['produitId'] && '${m['typeLabel']}'.contains('entrée pharmacie')).fold<num>(0, (s, m) => s + n(m['quantite']));
        expect(sortie, n(l['quantite']));
        expect(entree, sortie);
      }
      expect(mv.every((m) => m['justificatif'] == 'Bon de transfert ${b['reference']}'), isTrue);
      expect(b['etat'], 'receptionne');
    }
    // Un transfert ne crée ni ne détruit : le total d'un produit n'est écrit que par les entrées, sorties, pertes et régularisations.
    final transferts = mouvements.where((m) => m['type'] == 'transfert').toList();
    expect(transferts.fold<num>(0, (s, m) => s + ('${m['typeLabel']}'.contains('sortie magasin') ? n(m['quantite']) : -n(m['quantite']))), 0);
    expect(bons.map((b) => b['reference']).toSet().length, 15);
  });

  test('inventaire : un clos fin septembre qui régularise ses écarts, une feuille EN COURS sur le détail qui n\'écrit rien', () {
    expect(inventaires.length, 2);
    final clos = inventaires.firstWhere((i) => i['statutInv'] == 'valide');
    expect(clos['date'], '2026-09-30');
    expect(clos['magasin'], 'gros');
    expect(clos['nbArticles'], 150);
    expect(clos['nbEcarts'], 9);
    final reg = mouvements.where((m) => m['type'] == 'inventaire').toList();
    expect(reg.length, 9);
    expect(reg.every((m) => m['justificatif'] == 'Inventaire ${clos['reference']}' && m['date'] == '2026-09-30'), isTrue);
    final enCours = inventaires.firstWhere((i) => i['statutInv'] == 'brouillon');
    expect(enCours['magasin'], 'detail');
    expect(enCours['date'], '2026-11-06');
    expect(mouvements.where((m) => '${m['justificatif']}'.contains('${enCours['reference']}')), isEmpty, reason: 'une feuille en cours ne régularise rien');
  });

  test('deux pertes déclarées, valorisées au CUMP, avec leur constat', () {
    final pertes = mouvements.where((m) => const ['perte', 'casse', 'peremption'].contains(m['type'])).toList();
    expect(pertes.length, 2);
    for (final m in pertes) {
      expect(n(m['valeur']), n(m['quantite']) * n(m['cump']));
      expect(m['justificatif'], startsWith('Constat de '));
      expect(m['constatePar'], isNotNull);
    }
    // RG-03 sur une perte : plus que le stock est refusé, en nommant l'article, rien n'est écrit.
    final p = produits.first;
    expect(
        () => d.declarerPerte(
            produit: p, type: 'casse', quantite: n(p['stock']) + 1, date: '2026-11-07', justificatif: 'Constat', constatePar: 'x', utilisateur: 'x', mouvements: mouvements),
        throwsA(isA<d.RefusStock>()));
  });

  test('emplacements : tous les produits sont rangés dans un casier qui existe', () {
    final codes = c('emplacements').map((e) => e['code']).toSet();
    expect(codes.length, 15);
    expect(produits.every((p) => codes.contains(p['emplacement'])), isTrue);
  });

  // --- achats --------------------------------------------------------------------------------------------------------------------------------

  test('5 fournisseurs fictifs : noms génériques, ni téléphone, ni IFU, ni compte, ni agrément', () {
    final f = c('fournisseurs');
    expect(f.length, 5);
    expect(f.map((x) => x['nom']), contains('Grossiste Pharma Borgou'));
    expect(f.map((x) => x['nom']), contains('Centrale d’achat de Parakou'));
    for (final x in f) {
      expect(x['fictif'], true);
      expect(x['tel'], '');
      for (final k in ['ifu', 'compte', 'banque', 'rccm', 'agrement']) {
        expect(x.containsKey(k), isFalse, reason: '${x['nom']} : $k');
      }
    }
    expect(produits.every((p) => f.any((x) => x['code'] == p['fournisseur'])), isTrue);
  });

  test('12 besoins : 3 soumis en attente, 1 rejeté avec motif, 8 validés dont 5 à quantité accordée différente, arbitrés par la Direction', () {
    final b = c('besoins');
    expect(b.length, 12);
    expect(b.where((x) => x['etape'] == 'soumis').length, 3);
    final rejetes = b.where((x) => x['etape'] == 'rejete').toList();
    expect(rejetes.length, 1);
    expect('${rejetes.first['motifArbitrage']}'.trim(), isNotEmpty);
    expect(rejetes.first['valideePar'], isNull, reason: 'un bon rejeté n\'est pas validé, et il n\'est pas archivé');
    final valides = b.where((x) => const ['accorde', 'prepare', 'distribue'].contains(x['etape'])).toList();
    expect(valides.length, 8);
    var differents = 0;
    for (final x in valides) {
      expect([direction1, direction2].contains(x['valideePar']), isTrue, reason: '${x['reference']} : validé par la Direction');
      expect(x['arbitrePar'], x['valideePar']);
      final lignes = (x['lignes'] as List).cast<Map>();
      for (final l in lignes) {
        expect(n(l['quantiteAccordee']), lessThanOrEqualTo(n(l['quantiteDemandee'])));
        expect(n(l['quantiteAccordee']), greaterThan(0));
      }
      if (lignes.any((l) => n(l['quantiteAccordee']) != n(l['quantiteDemandee']))) differents++;
      expect(x['montantEstime'], lignes.fold<num>(0, (s, l) => s + n(l['quantiteDemandee']) * n(l['prixAchat'])));
    }
    expect(differents, 5);
    for (final x in b.where((x) => x['etape'] == 'soumis')) {
      expect(x['valideePar'], isNull);
      expect((x['lignes'] as List).every((l) => (l as Map)['quantiteAccordee'] == null), isTrue);
    }
    expect(b.map((x) => x['reference']).toList(), [for (var i = 1; i <= 12; i++) 'BEB-2026-${i.toString().padLeft(4, '0')}']);
    expect([for (final x in b) '${x['date']}'], [for (final x in b) '${x['date']}']..sort());
    // La validation informe le comptable et le gestionnaire de stock : deux notifications par besoin accordé.
    final notifications = c('notifications').where((x) => x['type'] == 'besoin_accorde').toList();
    expect(notifications.length, 16);
    expect(notifications.map((x) => x['poste']).toSet(), {'comptable', 'stock'});
  });

  test('8 commandes toutes validées par la Direction AVANT transmission (RG-04), 6 livraisons, 6 procès-verbaux dont un avec réserves nommées', () {
    final cmd = c('commandes');
    expect(cmd.length, 8);
    for (final x in cmd) {
      expect([direction1, direction2].contains(x['valideePar']), isTrue, reason: '${x['reference']}');
      expect('${x['dateValidation']}'.compareTo('${x['date']}') >= 0, isTrue);
      expect(n(x['montant']), (x['lignes'] as List).fold<num>(0, (s, l) => s + n((l as Map)['quantite']) * n(l['prixUnitaire'])));
    }
    final livraisons = c('livraisons');
    expect(livraisons.length, 6);
    for (final l in livraisons) {
      final x = cmd.firstWhere((x) => x['reference'] == l['commandeRef']);
      expect('${l['date']}'.compareTo('${x['dateValidation']}') > 0, isTrue, reason: 'livrée après validation');
      expect(const ['livree', 'soldee'].contains(x['statutCommande']), isTrue);
      // La livraison a mis les quantités reçues en stock : une entrée par ligne reçue, justifiée par le bon de livraison.
      for (final ligne in (l['lignes'] as List).cast<Map>()) {
        final entrees = mouvements.where((m) => m['type'] == 'entree' && m['justificatif'] == 'Bon de livraison ${l['reference']}' && m['produitId'] == ligne['produitId']);
        expect(entrees.fold<num>(0, (s, m) => s + n(m['quantite'])), n(ligne['quantiteLivree']));
      }
    }
    expect(cmd.where((x) => x['statutCommande'] == 'transmise').length, 1);
    expect(cmd.where((x) => x['statutCommande'] == 'validee').length, 1);
    final pv = c('pvReceptions');
    expect(pv.length, 6);
    expect(pv.map((x) => x['livraisonRef']).toSet(), livraisons.map((l) => l['reference']).toSet());
    final reserves = pv.where((x) => x['conclusion'] != 'Conforme').toList();
    expect(reserves.length, 1);
    final liv = livraisons.firstWhere((l) => l['reference'] == reserves.first['livraisonRef']);
    expect(liv['statutReception'], 'ecart');
    final textes = '${reserves.first['reserves']}';
    for (final l in (liv['lignes'] as List).cast<Map>().where((l) => n(l['ecart']) != 0)) {
      expect(textes, contains('${l['produit']}'), reason: 'les réserves NOMMENT l\'article en écart');
    }
    expect(pv.where((x) => x['conclusion'] == 'Conforme').every((x) => '${x['reserves']}'.isEmpty), isTrue);
    expect(pv.where((x) => x['nature'] == 'reactifs').single['chaineFroid'], true);
  });

  test('6 factures fournisseurs, chacune rapprochée de SA livraison (même bon, même montant), dont 2 impayées qui nourrissent la dette du BFR', () {
    final ff = c('facturesFournisseurs');
    final livraisons = c('livraisons');
    expect(ff.length, 6);
    for (final f in ff) {
      final l = livraisons.firstWhere((l) => l['reference'] == f['blRef']);
      expect(f['commandeRef'], l['commandeRef']);
      expect(n(f['montantLivraison']), n(l['montant']));
      expect(n(f['montantFacture']), n(l['montant']));
      expect(n(f['ecart']), 0);
      expect(f['statutRappro'], 'rapproche');
      expect('${f['date']}'.compareTo('${l['date']}') >= 0, isTrue);
    }
    expect(ff.map((f) => f['blRef']).toSet().length, 6);
    final impayees = ff.where((f) => f['statutPaiement'] != 'payee').toList();
    expect(impayees.length, 2);
    expect(d.nbDettesFournisseurs(ff), 2);
    expect(d.detteFournisseurs(ff), impayees.fold<num>(0, (s, f) => s + n(f['montantFacture'])));
    expect(d.detteFournisseurs(ff), greaterThan(0));
    // La facture payée porte son règlement au journal de banque, la facture due son écriture d'achat seule.
    for (final f in ff) {
      final achat = ecritures.where((e) => e['journal'] == 'ACH' && e['pieceId'] == f['id']).toList();
      expect(achat.length, 2);
      expect(achat.fold<num>(0, (s, e) => s + n(e['debit'])), n(f['montantFacture']));
      final reglement = ecritures.where((e) => e['journal'] == 'BQ' && e['pieceId'] == f['id']).toList();
      expect(reglement.length, f['statutPaiement'] == 'payee' ? 2 : 0);
    }
    expect(ff.where((f) => f['statutPaiement'] == 'impayee' && '${f['echeance']}'.compareTo('2026-11-07') < 0).length, 1, reason: 'une dette est échue');
  });

  // --- ventes de pharmacie ---------------------------------------------------------------------------------------------------------------------

  test('40 ventes de pharmacie au comptoir SANS dossier patient, soldées, sorties du stock détail justifiées par le numéro de l\'opération', () {
    final ventes = factures.where((f) => f['venteComptoir'] == true).toList();
    expect(ventes.length, 40);
    for (final f in ventes) {
      expect(f['operationDissociee'], true);
      expect(f['patientCode'], isNull);
      expect(f['patientId'], isNull);
      expect(f['patient'], 'Client de comptoir (fictif)');
      expect(f['statutPaiement'], 'soldee');
      expect(f['partAssurance'], 0);
      expect(n(f['montantPaye']), n(f['montantTTC']));
      expect(n(f['montantTTC']), (f['lignes'] as List).fold<num>(0, (s, l) => s + n((l as Map)['montant'])));
      // Le prix vendu est le prix d'achat du produit (RG-02), sans marge.
      for (final l in (f['lignes'] as List).cast<Map>()) {
        expect(n(l['prixUnitaire']), n(produit(l['produitId'])['prixAchat']));
        expect(n(l['remiseUnitaire']), 0);
        final sorties = mouvements.where((m) => m['type'] == 'sortie' && m['justificatif'] == 'Facture ${f['numero']}' && m['produitId'] == l['produitId']);
        expect(sorties.fold<num>(0, (s, m) => s + n(m['quantite'])), n(l['quantite']), reason: '${f['numero']} ${l['designation']}');
        expect(sorties.every((m) => m['stockType'] == 'detail'), isTrue);
      }
      // L'encaissement : une pièce 571 / 706 équilibrée.
      final ecr = ecritures.where((e) => e['pieceId'] == f['id']).toList();
      expect(ecr.map((e) => e['compte']).toSet(), {'571000', '706000'});
    }
    expect(ventes.map((f) => f['numeroMecef']).toSet().length, 40);
    expect(factures.map((f) => f['numeroMecef']).whereType<String>().toSet().length, factures.where((f) => f['numeroMecef'] != null).length, reason: 'aucun numéro MECeF en double');
    expect(c('patients').length, 120, reason: 'aucune fiche patient n\'est ajoutée pour le comptoir');
    expect(factures.map((f) => f['numero']).toSet().length, factures.length);
  });

  test('2 refus RG-03 REJOUÉS sur le moteur d\'émission : quantité supérieure au stock détail refusée en le disant, rien d\'écrit', () {
    final nbFactures = factures.length;
    final nbMouvements = mouvements.length;
    final nbEcritures = ecritures.length;
    final candidats = produits.where((p) => p['categorie'] == 'medicament' && n(p['stockDetail']) > 0).take(2).toList();
    expect(candidats.length, 2);
    for (final p in candidats) {
      final detail = n(p['stockDetail']);
      expect(
          () => d.ligneSaisie(nature: 'medicament', designation: '${p['designation']}', quantite: detail + 1, prixUnitaire: n(p['prixVente']), produitId: '${p['id']}', stockDetail: detail),
          throwsA(isA<d.RefusEmission>().having((e) => e.code, 'code', 'RG03_STOCK').having((e) => e.motif, 'motif', contains('RG-03'))));
      // La même quantité, mais répartie sur deux lignes d'une même pièce, est refusée aussi.
      expect(
          () => d.ligneSaisie(
              nature: 'medicament', designation: '${p['designation']}', quantite: 2, prixUnitaire: n(p['prixVente']), produitId: '${p['id']}', stockDetail: detail, dejaSurLaFacture: detail - 1),
          throwsA(isA<d.RefusEmission>()));
      // Le contrôle d'une sortie saisie à la main refuse aussi, en nommant le disponible.
      expect(d.controleMouvement(produit: p, type: 'sortie', stockType: 'detail', quantite: detail + 1), contains('RG-03'));
    }
    expect(factures.length, nbFactures);
    expect(mouvements.length, nbMouvements);
    expect(ecritures.length, nbEcritures);
    final jeuRelance = construireJeu();
    expect(jeuRelance['factures.json'], jeu['factures.json'], reason: 'les refus n\'écrivent rien');
  });

  // --- comptabilité ----------------------------------------------------------------------------------------------------------------------------

  test('chaque pièce comptable est équilibrée (RG-10) et une ligne n\'a qu\'un sens, sur TOUT le journal (clinique, paie, achats, ventes, dépenses)', () {
    final pieces = <String, List<F>>{};
    for (final e in ecritures) {
      expect(n(e['debit']) > 0 && n(e['credit']) > 0, isFalse, reason: 'ligne à deux sens : ${e['numero']} ${e['compte']}');
      expect(n(e['debit']) > 0 || n(e['credit']) > 0, isTrue, reason: 'ligne vide : ${e['numero']}');
      (pieces['${e['numero']}'] ??= []).add(e);
    }
    for (final p in pieces.entries) {
      expect(p.value.fold<num>(0, (s, e) => s + n(e['debit'])), p.value.fold<num>(0, (s, e) => s + n(e['credit'])), reason: 'pièce ${p.key} déséquilibrée');
      expect({for (final e in p.value) e['journal']}.length, 1, reason: 'pièce ${p.key} sur deux journaux');
    }
    expect(ecritures.map((e) => e['id']).toSet().length, ecritures.length);
    expect(ecritures.any((e) => e['journal'] == 'AN'), isFalse, reason: 'aucun bilan d\'ouverture');
    expect(ecritures.every((e) => const ['brouillon', 'validee'].contains(e['statut'])), isTrue);
  });

  test('les pièces VALIDÉES sont exactement celles d\'août et de septembre ; octobre et novembre restent en brouillon ; le valideur n\'est jamais l\'auteur', () {
    final pieces = <String, List<F>>{};
    for (final e in ecritures) {
      (pieces['${e['numero']}'] ??= []).add(e);
    }
    var validees = 0;
    for (final p in pieces.entries) {
      final debut = p.value.map((e) => '${e['date']}').reduce((a, b) => a.compareTo(b) <= 0 ? a : b).substring(0, 7);
      final statuts = {for (final e in p.value) e['statut']};
      expect(statuts.length, 1, reason: 'une pièce se valide entière : ${p.key}');
      if (debut == '2026-08' || debut == '2026-09') {
        expect(statuts.single, 'validee', reason: '${p.key} ($debut)');
        validees++;
        for (final e in p.value) {
          expect([comptableStock, comptableCaisse].contains(e['validePar']), isTrue, reason: '${p.key}');
          expect(e['valideLe'], anyOf('2026-09-05', '2026-10-05'));
          expect('${e['valideLe']}'.compareTo('${e['date']}') > 0, isTrue);
          if (e['saisiPar'] != null) expect(e['validePar'], isNot(e['saisiPar']), reason: 'séparation des tâches : ${p.key}');
        }
      } else {
        expect(const ['2026-10', '2026-11'].contains(debut), isTrue);
        expect(statuts.single, 'brouillon', reason: '${p.key} ($debut)');
        expect(p.value.every((e) => e['validePar'] == null), isTrue);
      }
    }
    expect(validees, greaterThan(150));
    // Les pièces de paie d'août et de septembre, que le sous-lot RH laisse en brouillon, sont validées par la comptabilité.
    expect(ecritures.where((e) => e['journal'] == 'SAL').every((e) => e['statut'] == 'validee'), isTrue);
    // Chaque pièce validée passe le moteur de validation sans refus (RG-10).
    final actives = [for (final e in ecritures) {...e, 'statut': 'brouillon'}];
    for (final p in pieces.keys.take(40)) {
      expect(() => d.cpaValiderPiece(actives, actives.firstWhere((e) => e['numero'] == p)), returnsNormally);
    }
  });

  test('30 dépenses multi-lignes égales à la somme de leurs lignes, une écriture plate par ligne, 4 sans justificatif comptées et signalées', () {
    final dep = c('depenses');
    expect(dep.length, 30);
    expect(dep.map((x) => x['reference']).toList(), [for (var i = 1; i <= 30; i++) 'DEP-2026-${i.toString().padLeft(4, '0')}']);
    final sans = dep.where((x) => x['justificatif'] == null).toList();
    expect(sans.length, 4);
    final k = d.cpaIndicateursDepenses(dep, '2026-11-07');
    expect(k.nbSansRecu, 4);
    expect(k.nb, 30);
    for (final x in dep) {
      final lignes = d.cpaLignesDepense(x);
      expect(lignes.length, greaterThanOrEqualTo(2), reason: '${x['reference']}');
      final somme = lignes.fold<num>(0, (s, l) => s + n(l['montant']));
      expect(n(x['montant']), somme, reason: '${x['reference']}');
      expect(lignes.every((l) => n(l['montant']) > 0 && '${l['compteCharge']}'.startsWith('6')), isTrue);
      // Une écriture plate par ligne de charge au débit, un crédit de trésorerie du total, même numéro de pièce, équilibrée.
      final ecr = ecritures.where((e) => e['pieceId'] == x['id']).toList();
      expect(ecr.length, lignes.length + 1, reason: '${x['reference']}');
      expect(ecr.every((e) => e['numero'] == x['reference']), isTrue);
      final debits = ecr.where((e) => n(e['debit']) > 0).toList();
      expect(debits.length, lignes.length);
      expect(debits.fold<num>(0, (s, e) => s + n(e['debit'])), somme);
      final credit = ecr.where((e) => n(e['credit']) > 0).single;
      expect(n(credit['credit']), somme);
      expect(credit['compte'], '571000');
      expect(x['ecritureIds'], [for (final e in ecr) e['id']]);
      expect(x['categorie'], isIn([for (final cat in d.cpaCategoriesDepense) cat.$1]));
    }
    final comptes = c('comptes').map((x) => x['num']).toSet();
    for (final x in dep) {
      for (final l in d.cpaLignesDepense(x)) {
        expect(comptes.contains(l['compteCharge']), isTrue, reason: 'compte de charge inconnu du plan : ${l['compteCharge']}');
      }
    }
  });

  test('les créances d\'assureurs : chaque facture mère égale aux parts assureur de ses filles, le reste dû égal aux parts non réglées, les règlements écrits au journal de banque', () {
    final meres = c('facturesMere');
    expect(meres.length, 9);
    var totalReste = 0.0;
    var totalParts = 0.0;
    var totalRegle = 0.0;
    for (final m in meres) {
      final filles = factures.where((f) => (m['piecesFilles'] as List).contains(f['numero'])).toList();
      expect(filles.length, (m['piecesFilles'] as List).length);
      final parts = filles.fold<num>(0, (s, f) => s + n(f['partAssurance']));
      expect(n(m['montantReclame']), parts, reason: '${m['numero']}');
      final regle = d.assTotalRegle(m);
      final reste = d.assResteDuMere(m);
      expect(reste, n(m['montantReclame']) - regle);
      expect(reste, greaterThanOrEqualTo(0));
      expect(m['etat'] == 'reglee', reste == 0, reason: '${m['numero']}');
      totalReste += reste;
      totalParts += parts;
      totalRegle += regle;
      for (final r in d.assReglementsDe(m)) {
        final ecr = ecritures.where((e) => (r['ecritureIds'] as List).contains(e['id'])).toList();
        expect(ecr.map((e) => e['compte']).toSet(), {'521000', '411110'});
        expect(ecr.fold<num>(0, (s, e) => s + n(e['debit'])), n(r['montant']));
        expect(ecr.fold<num>(0, (s, e) => s + n(e['credit'])), n(r['montant']));
      }
    }
    expect(totalReste, closeTo(totalParts - totalRegle, 0.001));
    expect(meres.where((m) => m['etat'] == 'reglee').length, 2);
    expect(totalRegle, greaterThan(0));
    // Les créances en retard de plus de 60 jours (émises le 05/09 : 63 jours) ont leurs relances, au montant du reste dû.
    final auj = DateTime(2026, 11, 7);
    final enRetard = meres.where((m) => d.assResteDuMere(m) > 0 && auj.difference(DateTime.parse('${m['dateEmission']}')).inDays > 60).toList();
    expect(enRetard.length, 2);
    final relances = c('relances');
    expect(relances.length, 3);
    for (final r in relances) {
      final m = enRetard.firstWhere((m) => m['compagnieCode'] == r['assureur']);
      expect(n(r['montant']), d.assResteDuMere(m));
      expect(r['statutRelance'], 'en_attente');
    }
    expect(relances.map((r) => r['reference']).toSet().length, 3);
    // La balance âgée des factures de comptoir n'ajoute aucune créance : elles sont soldées.
    expect(factures.where((f) => f['venteComptoir'] == true).every((f) => n(f['reliquat']) == 0 && n(f['partAssurance']) == 0), isTrue);
  });

  test('échéances fiscales de l\'exercice 2026 (déclaration unique CNSS au 10, versement CNSS-VERS au 15) : payées jusqu\'à septembre, UNE seule dépassée, aucun montant inventé', () {
    final ech = c('echeancesFiscales');
    expect(ech.length, 75, reason: '63 d\'origine + douze versements CNSS (séparation de la CNSS, 09/11/2026)');
    final lignes = d.cpcLignesEcheances(ech, aujourdhui);
    final retard = lignes.where((e) => e['etat'] == 'en_retard').toList();
    expect(retard.length, 1);
    expect(retard.single['code'], 'CNSS-VERS', reason: 'le versement des cotisations de septembre, échu le 15 octobre ; la déclaration unique du 10 est réglée');
    expect(retard.single['echeance'], '2026-10-15');
    expect(lignes.where((e) => e['etat'] == 'payee').length, 63);
    expect(lignes.where((e) => e['etat'] == 'a_payer' || e['etat'] == 'a_venir' || e['etat'] == 'declaration').length, 11);
    expect(lignes.where((e) => '${e['echeance']}'.compareTo('2026-10-01') < 0).every((e) => e['paye'] == true), isTrue, reason: 'tout ce qui est échu avant octobre est payé');
    expect(ech.where((e) => e['paye'] == true).every((e) => e['montant'] == null && e['reference'] != null && e['valideePar'] != null), isTrue);
    expect(ech.firstWhere((e) => e['code'] == 'CNSS')['echeanceTheorique'], '2026-01-10');
    expect(ech.firstWhere((e) => e['code'] == 'CNSS-VERS')['echeanceTheorique'], '2026-01-15');
    final barre = d.cpcBarreEcheances(lignes);
    expect(barre.first.ton, 'danger');
    expect(d.cpcAlerteOuverture(lignes), isNotNull);
  });

  test('ce qui reste volontairement vide, avec son motif : exercice sans bilan d\'ouverture ni liasse, immobilisations, rapprochements, dispensations', () {
    for (final nom in ['exercices', 'immobilisations', 'rapprochements', 'dispensations', 'budgets', 'liasse']) {
      if (jeu.containsKey('$nom.json')) expect(jeu['$nom.json'], '[]\n', reason: nom);
    }
    expect(c('banques').map((b) => b['id']), ['BQ00'], reason: 'aucun compte bancaire inventé');
  });

  test('hygiène : aucun nom réel hors les neuf agents, aucun nom de l\'éditeur d\'origine, aucune marque, aucun numéro inventé', () {
    final texte = [for (final nom in ['produits', 'fournisseurs', 'besoins', 'commandes', 'livraisons', 'pvReceptions', 'facturesFournisseurs', 'depenses', 'relances', 'echeancesFiscales', 'lots']) jeu['$nom.json']!].join('\n');
    for (final interdit in ['SOBAPS', 'UBIPHARM', 'LABOTECH', 'MEDIPLUS', 'NATIFOURN', 'CAME ', 'Nassiera', 'NASSIERA']) {
      expect(texte.contains(interdit), isFalse, reason: interdit);
    }
    for (final f in c('fournisseurs')) {
      expect(f['fictif'], true);
    }
    final noms = {direction1, direction2, comptableStock, comptableCaisse, 'IDOHOU Abraham', 'AKONDE Octave', 'MABOUDOU Nawal'};
    for (final b in c('besoins')) {
      expect(noms.contains(b['demandeur']), isTrue, reason: '${b['demandeur']}');
      expect(noms.contains(b['valideePar']) || b['valideePar'] == null, isTrue, reason: 'un nom de validateur en dur : ${b['valideePar']}');
    }
    for (final x in c('commandes')) {
      expect(noms.contains(x['valideePar']), isTrue, reason: 'un nom de validateur en dur : ${x['valideePar']}');
    }
    for (final m in mouvements) {
      expect(noms.contains(m['utilisateur']), isTrue, reason: '${m['utilisateur']}');
    }
  });
}
