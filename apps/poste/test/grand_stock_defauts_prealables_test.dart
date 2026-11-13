import 'package:flutter_test/flutter_test.dart';

import 'aide_grand_stock.dart';

/// LES DEUX DÉFAUTS PRÉEXISTANTS que la clinique sœur a trouvés en mesurant le Grand Stock chez un fileul (étape 2), cherchés ICI sans aucun import : la vraie mère Dart, un vrai fileul,
/// de vrais ponts, la vraie configuration. Un article créé par la mère (comme le ferait l'écran « Produits » ou un import fait au poste de la mère) et un fileul qui dispense.
void main() {
  Map<String, Object?> article(String id, int stock) => {'id': id, 'code': 'ART$id', 'designation': 'ARTICLE $id', 'statut': 'actif', 'stockGros': stock, 'stockDetail': 0, 'stock': stock, 'prixAchat': 100, 'seuilAlerte': 5};

  test('DÉFAUT 1 : un fileul qui a SORTI du stock ne le voit pas remplacé par la valeur que la mère publie (ses sorties ne sont pas encore parties)', () async {
    final c = Clinique(9433, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      c.mm.collection('produits').inserer(article('ZZ1', 100));
      await c.converger(regimeLeve, () => f1.m.collection('produits').parId('ZZ1') != null, 'l\'article de la mère arrive au fileul');
      expect(f1.m.collection('produits').parId('ZZ1')!['stockGros'], 100);
      // Le fileul DISPENSE 10 : sa sortie n'est pas encore partie (le pont n'a pas tourné), la mère publie la fiche de nouveau (elle change le seuil d'alerte).
      f1.m.collection('produits').mettreAJour('ZZ1', {'stockGros': 90, 'stock': 90});
      c.mm.collection('produits').mettreAJour('ZZ1', {'seuilAlerte': 8});
      // Le fileul n'exécute PAS le pont d'activité (sa sortie ne part pas) : seule la configuration de la mère est tirée, jusqu'à la reprise du nouveau seuil.
      final fin = DateTime.now().add(const Duration(seconds: 30));
      while (f1.m.collection('produits').parId('ZZ1')!['seuilAlerte'] != 8 && DateTime.now().isBefore(fin)) {
        await c.pub.pousser();
        await f1.appl.tirer();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final fiche = f1.m.collection('produits').parId('ZZ1')!;
      expect(fiche['seuilAlerte'], 8, reason: 'la configuration de la mère est bien reprise');
      expect(fiche['stockGros'], 90, reason: 'mais la sortie du fileul, qui n\'a pas encore atteint la mère, ne doit pas être effacée par la valeur du stock que la mère publie');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('DÉFAUT 2 : un article créé par la mère arrive en UNE fiche chez un fileul (jamais deux : l\'identifiant de configuration et l\'identité de synchronisation du pont)', () async {
    final c = Clinique(9434, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      c.mm.collection('produits').inserer(article('ZZ2', 100));
      await c.converger(regimeLeve, () => f1.m.collection('produits').parId('ZZ2') != null, 'l\'article de la mère arrive au fileul');
      await c.tour(regimeLeve);
      final fiches = [for (final p in f1.m.collection('produits').actives) if (p['code'] == 'ARTZZ2') '${p['id']}'];
      expect(fiches, ['ZZ2'], reason: 'une seule fiche chez le fileul');
      final surMere = [for (final p in c.mm.collection('produits').actives) if (p['code'] == 'ARTZZ2') '${p['id']}'];
      expect(surMere, ['ZZ2'], reason: 'une seule fiche chez la mère');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('DÉFAUT 3 (garde) : un fileul peut SORTIR du stock (dispensation, perte, transfert) malgré la garde « réglé sur la mère » du catalogue', () async {
    final c = Clinique(9435, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      c.mm.collection('produits').inserer(article('ZZ3', 100));
      await c.converger(regimeLeve, () => f1.m.collection('produits').parId('ZZ3') != null, 'l\'article de la mère arrive au fileul');
      expect(() => f1.m.collection('produits').mettreAJour('ZZ3', {'stockGros': 95, 'stock': 95}), returnsNormally, reason: 'un compteur est de l\'activité, pas de la configuration');
      expect(() => f1.m.collection('produits').mettreAJour('ZZ3', {'designation': 'AUTRE NOM'}), throwsA(isA<Object>()), reason: 'le reste de la fiche reste réglé sur la mère');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}
