// L'IMPRIMANTE DE CAISSE (réglage de clinique, aucun modèle fourni pour Baguidi : « à renseigner ») et L'ÉTAT DES DEUX MODES MECeF (ce qui est prêt, ce qui
// manque), décision de la Direction de Baguidi du 16/11/2026 (E3760 à E3769). Aucun pilote, aucun adaptateur, aucun numéro simulé.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  group('imprimante de caisse : trois réglages de clinique', () {
    test('famille mecef (geste reglage_mecef), jamais vers un téléphone, sourcés : modèle = le boîtier MECeF, interface VIDE, largeur 80 mm', () {
      final defs = {for (final c in [cleImprimanteModele, cleImprimanteLargeurPapier, cleImprimanteInterface]) c: definitionDeParametre(c)!};
      for (final d in defs.values) {
        expect(d.famille, 'mecef', reason: d.cle);
        expect(d.mobile, isFalse, reason: d.cle);
        expect(d.source, contains('16/11/2026'), reason: d.cle);
        expect(d.source, contains('à valider'), reason: d.cle);
        expect(Parametres.validerFiche(Parametres.semer(d), const [], const []), isNull, reason: d.cle);
      }
      expect(defs[cleImprimanteModele]!.defaut, mecefModeleBoitierDefaut, reason: 'le boîtier MECeF ELTRADE CC300 est aussi l\'imprimante de caisse (décision du 17/11/2026) : une seule machine, un seul libellé');
      expect(defs[cleImprimanteInterface]!.defaut, '');
      expect(defs[cleImprimanteLargeurPapier]!.type, TypeParametre.entier);
      expect(defs[cleImprimanteLargeurPapier]!.defaut, 80);
    });

    test('une machine, deux fonctions : intégrée, l’imprimante prend le modèle du boîtier et son interface ; le réglage est semé à « oui »', () {
      final def = definitionDeParametre(cleImprimanteIntegree)!;
      expect([def.famille, def.type, def.defaut, def.mobile], ['mecef', TypeParametre.booleen, true, false]);
      expect(def.source, contains('17/11/2026'));
      expect(Parametres.validerFiche(Parametres.semer(def), const [], const []), isNull);
      final i = imprimanteCaisseEnVigueur(integree: true, modeleBoitier: ' Boîtier X ', modele: 'Autre', interface: 'USB', largeur: 80);
      expect([i.integree, i.modele, i.interface, i.aRenseigner], [true, 'Boîtier X', imprimanteInterfaceIntegree, false]);
      expect(i.mentionIntegree, 'Le boîtier Boîtier X est à la fois le MECeF et l’imprimante de caisse (ticket 80 mm) : une machine, deux fonctions.');
      expect(i.resume, 'Imprimante de caisse : Boîtier X — papier 80 mm — interface : $imprimanteInterfaceIntegree');
      // le modèle du boîtier n'est pas renseigné : l'imprimante intégrée le dit « à renseigner »
      final sans = imprimanteCaisseEnVigueur(integree: true, modeleBoitier: '');
      expect([sans.modele, sans.aRenseigner, sans.modeleAffiche], [null, true, 'à renseigner']);
      // décochée : les champs propres reprennent la main
      final propre = imprimanteCaisseEnVigueur(integree: false, modeleBoitier: 'Boîtier X', modele: 'Autre', interface: 'USB');
      expect([propre.modele, propre.interface, propre.integree], ['Autre', 'USB', false]);
    });

    test('valeurs semées : « à renseigner », à valider, 80 mm', () {
      final i = imprimanteCaisseEnVigueur(modele: '', largeur: 80, interface: '  ');
      expect(i.modele, isNull);
      expect(i.interface, isNull);
      expect(i.aRenseigner, isTrue);
      expect(i.modeleAffiche, 'à renseigner');
      expect(i.interfaceAffichee, 'à renseigner');
      expect(i.largeurMm, 80);
      expect(i.largeurIgnoree, isFalse);
      expect(i.resume, 'Imprimante de caisse : à renseigner — papier 80 mm — interface : à renseigner');
    });

    test('valeurs réglées : la largeur est appliquée ; hors bornes ou illisible, 80 mm et c’est dit', () {
      final i = imprimanteCaisseEnVigueur(modele: ' Modèle Y ', largeur: 58, interface: 'USB');
      expect([i.modele, i.interface, i.largeurMm, i.aRenseigner], ['Modèle Y', 'USB', 58, false]);
      for (final v in [10, 300, 72.5, 'large']) {
        final h = imprimanteCaisseEnVigueur(largeur: v);
        expect(h.largeurMm, 80, reason: '$v');
        expect(h.largeurIgnoree, isTrue, reason: '$v');
      }
      expect(imprimanteCaisseEnVigueur(largeur: '76').largeurMm, 76);
    });
  });

  group('état des deux modes', () {
    test('boîtier (modèle réglé) et e-MECeF : aucun n’est configuré, chacun dit ce qui manque', () {
      final e = {for (final x in mecefEtatsDesModes(modeleBoitier: 'ELTRADE CC300')) x.mode: x};
      expect(e.keys, ['boitier', 'emecef']);
      expect(e.values.every((x) => !x.configure), isTrue, reason: 'aucun adaptateur livré (lot M3)');
      expect(e['boitier']!.libelle, 'Boîtier physique');
      expect(e['boitier']!.pret.first, contains('ELTRADE CC300'));
      expect(e['boitier']!.manque.join(' '), contains('Adaptateur ELTRADE CC300 : intégration à fournir par l’éditeur du boîtier'));
      expect(e['emecef']!.manque.join(' '), contains('Dossier d’interface de la DGI'));
      for (final x in e.values) {
        expect(x.pret.join(' '), contains('sans aucun numéro simulé'), reason: x.mode);
      }
    });

    test('modèle non renseigné : il passe dans ce qui manque', () {
      final b = mecefEtatsDesModes().first;
      expect(b.manque.first, 'Modèle du boîtier : à renseigner.');
      expect(b.pret.any((l) => l.contains('Modèle du boîtier réglé')), isFalse);
    });
  });
}
