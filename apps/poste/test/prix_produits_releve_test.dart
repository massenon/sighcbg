import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';

/// LE RELEVÉ « AVANT / APRÈS » DES PRIX DES PRODUITS (lot PRIX D'ACHAT VERSIONNÉ, étape 0) : pour TOUS les produits des trois jeux du dépôt (le jeu livré, le jeu de référence, le jeu
/// sobre), le prix d'achat et le prix de vente de la fiche et ce que chaque LECTEUR en tire : la valeur unitaire de stock (prix de vente et CUMP), la valorisation d'une sortie, la
/// ligne d'un bon de besoin, le catalogue du lot mobile, l'effet de la méthode de valorisation et la valeur par famille.
///
/// Le critère de réussite de la migration est que ce relevé NE BOUGE PAS : aucun prix ne change quand le prix d'achat devient une version. Le fichier versionné
/// `fixtures/releves/prix_produits.json` a été écrit AVANT toute modification du moteur ; l'écrire de nouveau (`RELEVE_ECRIRE=1`) est un geste réservé et se justifie par un écart nommé.
const _jeux = {'livre': 'assets/donnees/jeu', 'reference': 'test/fixtures/jeu_reference', 'sobre': 'test/fixtures/jeu_sobre'};
const _fichier = 'test/fixtures/releves/prix_produits.json';

final _jour = DateTime(2026, 11, 14, 9);

/// [versionnes] : le magasin est d'abord REPRIS (chaque produit reçoit sa version 1) puis la fiche suit la version en vigueur ; le relevé doit être celui d'avant.
Map<String, Object?> releve({bool versionnes = false}) {
  final out = <String, Object?>{};
  for (final e in _jeux.entries) {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, e.value);
    if (versionnes) {
      TarifsPoste.assurerProduits(m);
      TarifsPoste.projeterProduits(m, _jour);
    }
    final produits = [for (final p in m.collection('produits').toutes) p];
    final fiches = <String, Object?>{};
    for (final p in produits) {
      final id = '${p['id']}';
      final ligne = nouvelleLigneBesoin(produit: p, demandee: 1);
      final v = valoriserSortie(p, 3, 'prixVente'), c = valoriserSortie(p, 3, 'cump');
      fiches[id] = {
        'code': p['code'],
        'categorie': p['categorie'],
        'statut': p['statut'],
        'prixAchat': p['prixAchat'],
        'prixVente': p['prixVente'],
        'cump': p['cump'],
        'valeurUnitairePrixVente': valeurUnitaire(p, MethodeValorisation.prixVente),
        'valeurUnitaireCump': valeurUnitaire(p, MethodeValorisation.cump),
        'sortie3PrixVente': [v.valeur, v.valeurPrixVente, v.valeurCump],
        'sortie3Cump': [c.valeur, c.valeurPrixVente, c.valeurCump],
        'ligneBesoinPrixAchat': ligne['prixAchat'],
      };
    }
    final mob = mobProduitsPrescriptibles(produits);
    final effet = cfbEffetValorisation(produits);
    out[e.key] = {
      'nombre': produits.length,
      'fiches': fiches,
      'mobile': {for (final x in mob) x.id: x.prixAchat},
      'effetValorisation': {'ecart': effet.ecart, 'divergents': effet.divergents},
      'parFamille': [
        for (final f in cfbParFamille(produits)) {'famille': f.famille, 'articles': f.articles, 'quantite': f.quantite, 'valeur': f.valeur}
      ],
    };
  }
  return out;
}

void comparer(Map avant, Map actuel) {
  final ecarts = <String>[];
  for (final jeu in avant.keys) {
    final a = avant[jeu] as Map, b = actuel[jeu] as Map;
    if (a['nombre'] != b['nombre']) ecarts.add('$jeu : nombre ${a['nombre']} → ${b['nombre']}');
    for (final id in (a['fiches'] as Map).keys) {
      if (jsonEncode(a['fiches'][id]) != jsonEncode((b['fiches'] as Map)[id])) ecarts.add('$jeu/$id : ${jsonEncode(a['fiches'][id])} → ${jsonEncode((b['fiches'] as Map)[id])}');
    }
    for (final k in ['mobile', 'effetValorisation', 'parFamille']) {
      if (jsonEncode(a[k]) != jsonEncode(b[k])) ecarts.add('$jeu/$k');
    }
  }
  expect(ecarts, isEmpty, reason: 'aucun prix de produit ne change à la migration');
}

void main() {
  test('APRÈS la migration (chaque produit repris en version 1, la fiche suit la version) : le relevé est celui d\'avant, prix par prix', () {
    final avant = jsonDecode(File(_fichier).readAsStringSync()) as Map;
    comparer(avant, jsonDecode(jsonEncode(releve(versionnes: true))) as Map);
  });

  test('l\'accesseur daté rend, pour chaque produit des trois jeux, le prix d\'achat ET le prix de vente de la fiche d\'avant', () {
    var n = 0;
    for (final e in _jeux.entries) {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, e.value);
      final avant = ((jsonDecode(File(_fichier).readAsStringSync()) as Map)[e.key] as Map)['fiches'] as Map;
      TarifsPoste.assurerProduits(m);
      for (final p in m.collection('produits').actives) {
        final r = TarifsPoste.prixProduit(m, p, aujourdhui: _jour);
        final a = avant['${p['id']}'] as Map;
        expect(r.absent, isFalse, reason: '${e.key}/${p['code']}');
        expect([r.achat, r.vente, r.version, r.dateEffet], [a['prixAchat'], a['prixVente'], 1, null], reason: '${e.key}/${p['code']}');
        n++;
      }
    }
    expect(n, 518);
  });

  test('le relevé des prix des produits est celui d\'AVANT la migration (aucun prix ne change)', () {
    final actuel = jsonDecode(jsonEncode(releve()));
    if (Platform.environment['RELEVE_ECRIRE'] == '1') {
      File(_fichier).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(actuel)}\n');
      return;
    }
    comparer(jsonDecode(File(_fichier).readAsStringSync()) as Map, actuel as Map);
  });

  test('le relevé porte bien les trois jeux et leurs produits (garde contre un relevé vide)', () {
    final avant = jsonDecode(File(_fichier).readAsStringSync()) as Map;
    expect([for (final j in _jeux.keys) (avant[j] as Map)['nombre']], [150, 184, 184]);
    for (final j in _jeux.keys) {
      expect(((avant[j] as Map)['fiches'] as Map).length, (avant[j] as Map)['nombre']);
    }
  });
}
