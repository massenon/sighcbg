// LES LISTES DE VALEURS MÉTIER (famille D de l'inventaire, 18/11/2026) : « PLUS DE VALEUR EN DUR ». On prouve : (1) une ÉNUMÉRATION STRUCTURELLE n'a qu'UNE liste de codes (celle de la définition de son
// réglage) et ne porte au réglage que ses LIBELLÉS ; (2) changer un libellé change ce que l'écran affiche SANS changer la décision (les codes lus par la logique ne bougent pas, un code inconnu du
// logiciel est ignoré, un code oublié garde son libellé d'attente, un texte vide retombe sur l'attente) ; (3) les listes de vocabulaire (actes de soins, check-listes du bloc, issues d'une variable
// de laboratoire, secteurs d'activité, secteur d'un service) suivent leur réglage ; (4) le barème de référence du régime employeur est un RÉFÉRENTIEL daté, plus une constante.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> version(String cle, String valeur, {String effet = '2026-11-01', int v = 1, String? statut}) {
  final d = definitionDeParametre(cle)!;
  return {
    ...Parametre(cle: cle, famille: d.famille, type: d.type, valeur: valeur, defaut: d.defaut, dateEffet: effet, version: v, auteur: 'Test', motif: 'essai', creeLe: '2026-11-18T08:00:00.000').toJson(),
    if (statut != null) 'statut': statut,
  };
}

void brancher(List<Map<String, Object?>> fiches) => ListesReference.brancher(() => fiches, horloge: () => DateTime(2026, 11, 18));

void main() {
  tearDown(ListesReference.debrancher);

  group('énumérations structurelles : des codes dans une seule liste, des libellés au réglage', () {
    test('chacune est un réglage texte « code=Libellé » d\'une famille libellée, jamais vers un téléphone, sans code ni libellé vide ni doublon', () {
      expect(enumerationsStructurelles.length, 18);
      final vues = <String>{};
      for (final e in enumerationsStructurelles) {
        final d = definitionDeParametre(e.cle)!;
        expect(vues.add(e.cle), isTrue, reason: '${e.cle} déclarée deux fois');
        expect(d.type, TypeParametre.texte, reason: e.cle);
        expect(d.famille, startsWith('listes_'), reason: e.cle);
        expect(libellesFamillesParametres.containsKey(d.famille), isTrue, reason: d.famille);
        expect(d.source, isNotNull, reason: e.cle);
        expect(d.mobile, isFalse, reason: e.cle);
        final brut = '${d.defaut}'.split(';').where((x) => x.trim().isNotEmpty).toList();
        final lues = ListesReference.correspondanceSemence(e.cle);
        expect(lues.length, brut.length, reason: '${e.cle} : une entrée sans « = », sans libellé ou en doublon');
        expect(e.codes, lues.keys.toList(), reason: e.cle);
        expect(lues.values.every((x) => x == x.trim() && x.isNotEmpty), isTrue, reason: e.cle);
      }
    });

    test('changer un LIBELLÉ change l\'affichage, jamais les codes ni la décision', () {
      final avant = [for (final c in categoriesProduit) c.id];
      final rhaAvant = rhaTypePlanningTon('garde');
      brancher([
        version('libelles.m8.modesPaiement', 'especes=Comptant; mtn=Mobile Money MTN'),
        version('libelles.m6.categoriesProduit', 'medicament=Produits pharmaceutiques'),
        version('libelles.m10.typesPlanning', 'garde=Garde de nuit'),
      ]);
      // Le libellé suit le réglage, dans tous les sites qui le lisent (une seule source) :
      expect(enumModesPaiement.libelle('especes'), 'Comptant');
      expect(tbaModesPaiement['especes'], 'Comptant');
      expect(tbaModesPaiement['mtn'], 'Mobile Money MTN');
      expect(categorieLabel('medicament'), 'Produits pharmaceutiques');
      expect(rhaTypePlanningLabel('garde'), 'Garde de nuit');
      // …les codes oubliés par le réglage gardent leur libellé d'attente ; l'ordre du réglage passe d'abord :
      expect(tbaModesPaiement['moov'], 'Moov Money');
      expect(tbaModesPaiement.keys.toList().take(2), ['especes', 'mtn']);
      // …et la décision ne bouge pas : les codes que la logique lit sont les mêmes, le ton d'un type de planning aussi.
      expect([for (final c in categoriesProduit) c.id].toSet(), avant.toSet());
      expect(enumModesPaiement.codes, ['especes', 'tpe', 'mtn', 'moov', 'mobile_money', 'mixte', 'assurance']);
      expect(rhaTypePlanningTon('garde'), rhaAvant);
    });

    test('un code inconnu du logiciel est ignoré ; un texte vide, illisible ou archivé retombe sur les libellés d\'attente ; un code inconnu s\'affiche tel quel', () {
      brancher([version('libelles.m6.typesStock', 'gros=Magasin central; nouveau=Inventé; detail=Pharmacie')]);
      expect(enumTypesStock.libelles.keys.toSet(), {'gros', 'detail', 'labo'});
      expect(enumTypesStock.libelle('gros'), 'Magasin central');
      expect(enumTypesStock.libelle('labo'), 'Stock laboratoire');
      expect(enumTypesStock.libelle('inconnu'), 'inconnu');
      for (final vide in ['', '   ', 'pas de signe égal', 'gros=']) {
        brancher([version('libelles.m6.typesStock', vide)]);
        expect(enumTypesStock.libelles, ListesReference.correspondanceSemence('libelles.m6.typesStock'), reason: vide);
      }
      brancher([version('libelles.m6.typesStock', 'gros=Archivé', statut: 'archive')]);
      expect(enumTypesStock.libelle('gros'), 'Stock gros (magasin central)');
    });

    test('une version datée ne change l\'affichage qu\'à partir de sa date ; les pièces d\'avant gardent leur libellé', () {
      final fiches = [version('libelles.m9.categoriesAssurance', 'entreprise=Employeur', effet: '2026-12-01')];
      expect(ListesReference.correspondanceA('libelles.m9.categoriesAssurance', fiches, '2026-11-30')['entreprise'], 'Assurance entreprise');
      expect(ListesReference.correspondanceA('libelles.m9.categoriesAssurance', fiches, '2026-12-01')['entreprise'], 'Employeur');
    });

    test('une clé inconnue est une faute de programmation ; un sous-ensemble de codes inconnu aussi', () {
      expect(() => ListesReference.correspondance('libelles.nexiste.pas'), throwsArgumentError);
      expect(() => enumFamillesTarif.paresDe(['CONSULTATION', 'INCONNU']), throwsArgumentError);
      expect(enumFamillesTarif.paresDe(['LABO', 'CONSULTATION']).map((x) => x.$1), ['LABO', 'CONSULTATION']);
    });

    test('les trois copies des modes de paiement et des familles de tarif sont UNE liste : mêmes codes, mêmes libellés partout', () {
      expect(tbaModesPaiement, enumModesPaiement.libelles);
      final cfa = {for (final (c, l, _) in cfaFamillesTarif) c: l};
      final import = {for (final (c, l) in enumFamillesTarif.paresDe(['CONSULTATION', 'ACTE', 'HOSPITALISATION', 'AMI', 'GYNECO', 'CERTIFICAT', 'LABO', 'IMAGERIE'])) c: l};
      for (final e in cfa.entries) {
        expect(import[e.key], e.value, reason: e.key);
      }
      brancher([version('libelles.cfg.famillesTarif', 'LABO=Biologie')]);
      expect({for (final (c, l, _) in cfaFamillesTarif) c: l}['LABO'], 'Biologie');
    });
  });

  group('listes de vocabulaire : le réglage commande', () {
    test('actes de soins, check-listes du bloc, issues d\'une variable de laboratoire', () {
      expect(hosActesSoins.first, 'Injection intraveineuse');
      expect(blocChecklistEntree.length, 12);
      expect(blocChecklistSortie.length, 9);
      expect(valeursTypeVariable['ternaire'], ['Positif', 'Négatif', 'Indéterminé']);
      brancher([
        version('listes.m3.actesSoins', 'Aérosol; Pansement'),
        version('listes.m3.checklistBlocEntree', 'Identité vérifiée; Site marqué'),
        version('listes.m5.valeursTernaire', 'Oui; Non; Douteux'),
      ]);
      expect(hosActesSoins, ['Aérosol', 'Pansement']);
      expect(blocChecklistEntree, ['Identité vérifiée', 'Site marqué']);
      expect(valeursTypeVariable['ternaire'], ['Oui', 'Non', 'Douteux']);
      expect(valeursTypeVariable['binaire'], ['Positif', 'Négatif']);
      expect(valeursTypeVariable.containsKey('titre'), isTrue);
    });

    test('les secteurs d\'activité et les motifs de couverture de l\'import sont ceux des écrans (une source)', () {
      brancher([version('listes.cfg.secteursActivite', 'Chirurgie; Maternité')]);
      expect(importSecteursActivite, ['Chirurgie', 'Maternité']);
    });

    test('le secteur d\'un service est une association « service=SECTEUR » réglable, qui retombe sur l\'attente', () {
      expect(agentSecteurDeService['Maternité'], 'MAT');
      expect(agentSecteurDeService.length, 11);
      brancher([version('listes.socle.secteurParService', 'Maternité=OBS')]);
      expect(agentSecteurDeService, {'Maternité': 'OBS'});
      brancher([version('listes.socle.secteurParService', '???')]);
      expect(agentSecteurDeService.length, 11);
    });
  });

  group('le nom d\'une compagnie se lit au référentiel des assureurs', () {
    test('sans référentiel, aucun nom n\'est inventé ; avec lui, le nom suit la fiche', () {
      final saisie = {'assureur': 'NSIA', 'naissanceConnue': 'date', 'dateNaissance': '1990-01-01'};
      expect(patTransformerPatient(saisie, null, DateTime(2026, 11, 18))['assureurNom'], isNull);
      final v = patTransformerPatient(saisie, null, DateTime(2026, 11, 18), assureurs: [
        {'code': 'NSIA', 'nom': 'NSIA ASSURANCE', 'statut': 'actif'},
        {'code': 'NSIA', 'nom': 'ARCHIVÉ', 'statut': 'archive'},
      ]);
      expect(v['assureurNom'], 'NSIA ASSURANCE');
    });
  });

  group('le barème de référence du régime employeur est un référentiel daté du jeu', () {
    final ref = (jsonDecode(File('../../apps/poste/assets/donnees/jeu/referentiels.json').readAsStringSync()) as Map)['garanties'];

    test('sans référentiel, le barème est vide (on n\'invente pas une grille)', () {
      expect(AssBareme.depuis(null).vide, isTrue);
      expect(AssBareme.depuis('illisible').vide, isTrue);
      expect(AssBareme.depuis(const {}).garanties, isEmpty);
    });

    test('le jeu porte les vingt garanties, les exclusions et les accords du document du 18/06/2026, avec sa date et sa source', () {
      final b = AssBareme.depuis(ref);
      expect(b.version, '2026-06-18');
      expect(b.date, '2026-06-18');
      expect(b.source, contains('18/06/2026'));
      expect(b.garanties.length, 20);
      expect(b.garanties.first['code'], 'G01');
      expect(b.garanties.first['plafond'], 5000);
      expect(b.actesExclus.length, 14);
      expect(b.produitsExclus.length, 23);
      expect(b.accordPrealable.length, 15);
      // chaque catégorie du barème est une catégorie de garantie connue
      final connues = enumCategoriesGarantie.codes.toSet();
      for (final g in b.garanties) {
        expect(connues, contains(g['categorie']), reason: '${g['code']}');
      }
    });

    test('une convention se construit sur le barème PASSÉ, et un autre barème donne une autre grille', () {
      final b = AssBareme.depuis(ref);
      final g = assGarantiesDepuisBareme({'id': 'S1', 'assureur': 'AFR'}, bareme: b, taux: List.filled(20, null), plafonds: [for (final x in b.garanties) x['plafond']]);
      expect(g.length, 20);
      expect(g.first['libelle'], b.garanties.first['libelle']);
      final petit = AssBareme(reference: 'Autre', garanties: [b.garanties.first], actesExclus: const ['Massages']);
      expect(assGarantiesDepuisBareme({'id': 'S1'}, bareme: petit, taux: const [], plafonds: const []).length, 1);
      expect(assConventionSaisie(petit)['actesExclus'], ['Massages']);
      expect(assConventionSaisie(AssBareme.depuis(null))['accordPrealable'], isEmpty);
    });
  });
}
