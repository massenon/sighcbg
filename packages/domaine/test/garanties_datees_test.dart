// T13 : les garanties des assureurs sont DATÉES. Ce fichier prouve : (1) « après = avant » tant qu'aucune version datée n'est ajoutée (relevé de 56 pièces / 196 lignes écrit sur le
// moteur d'avant), y compris après la migration ; (2) la version lue est celle EN VIGUEUR à la date de la pièce, jamais la plus récente ; (3) une pièce ancienne garde son taux ;
// (4) une version est immuable (garde) ; (5) la clé d'une garantie est souscripteur + catégorie + libellé ; (6) la migration d'un poste déjà peuplé.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'outils/jeu_garanties.dart';

typedef F = Map<String, Object?>;

Object? _jsonne(Object? v) => jsonDecode(jsonEncode(v));

void main() {
  final avant = (jsonDecode(File('test/vecteurs/garanties_avant.json').readAsStringSync()) as Map).cast<String, Object?>();

  group('après = avant tant qu’aucune version datée n’est ajoutée', () {
    test('le relevé de 56 pièces et 196 lignes est identique, ligne par ligne, au relevé du moteur d’avant', () {
      expect(avant['pieces'], 56);
      expect(avant['lignes'], 196);
      final apres = _jsonne(releve());
      expect(apres, avant['releve']);
    });

    test('même résultat après la MIGRATION (chaque garantie reçoit son rang de version, aucune date n’est posée)', () {
      final g = garantiesJeu();
      final m = assMigrerGaranties(g);
      expect(m.aFait, isTrue);
      final rangs = {for (final f in m.fiches) f['id']: f['version']};
      final migrees = [for (final x in g) {...x, 'version': rangs[x['id']]}];
      expect(migrees.every((x) => x['version'] == 1), isTrue, reason: 'une seule ligne par série dans le jeu : toutes deviennent la version 1');
      expect(migrees.every((x) => x['dateEffet'] == null), isTrue, reason: 'aucune date d’effet inventée');
      expect(_jsonne(releve(garanties: migrees)), avant['releve']);
      final totalA = (avant['releve'] as List).fold<double>(0, (a, x) => a + ((x as Map)['partAssureur'] as num));
      expect(totalA, avant['partAssureurTotale']);
    });
  });

  group('lecture à la date de la pièce (RG-09)', () {
    // S1 : la consultation généraliste passe de 80 % (plafond 5 000) à 50 % (plafond 3 000) le 01/07/2026 ; S2 reste telle quelle.
    List<F> avecVersion() {
      final g = garantiesJeu();
      final v1 = g.firstWhere((x) => x['souscripteurId'] == 'S1' && x['libelle'] == 'Consultation généraliste');
      return [
        for (final x in g) x['id'] == v1['id'] ? {...x, 'version': 1} : x,
        {...v1, 'id': 'GAR-S1-G01-v2', 'taux': 50, 'plafond': 3000, 'dateEffet': '2026-07-01', 'version': 2},
      ];
    }

    F ligne(String date, {String pat = 'PA1'}) {
      final r = repartir(
          patient: patientsJeu().firstWhere((p) => p['id'] == pat),
          lignes: [
            {'libelle': 'Consultation généraliste', 'categorie': 'consultation', 'montant': 10000}
          ],
          date: date,
          couvertures: couverturesJeu(),
          souscripteurs: souscripteursJeu(),
          garanties: avecVersion());
      return r.lignes.single;
    }

    test('la pièce du 30/06 est lue à 80 % plafonné à 5 000 ; celle du 01/07 à 50 % plafonné à 3 000 : jamais la plus récente pour une pièce ancienne', () {
      expect(ligne('2026-06-30')['partAssureur'], 5000);
      expect(ligne('2026-06-30')['taux'], 80);
      expect(ligne('2026-07-01')['partAssureur'], 3000);
      expect(ligne('2026-07-01')['taux'], 50);
      expect(ligne('2026-12-31')['partAssureur'], 3000);
    });

    test('une pièce rejouée APRÈS la pose de la version garde le taux de son jour (le relevé d’avant ne bouge que pour les jours à partir du 01/07)', () {
      // Les médicaments de S1 : 80 % jusqu'au 30/06, 40 % (plafond 4 000 par acte) à partir du 01/07.
      final g = garantiesJeu();
      final v1 = g.firstWhere((x) => x['souscripteurId'] == 'S1' && x['categorie'] == 'medicament');
      final apres = releve(garanties: [
        for (final x in g) x['id'] == v1['id'] ? {...x, 'version': 1} : x,
        {...v1, 'id': 'GAR-S1-G04-v2', 'taux': 40, 'plafond': 4000, 'unitePlafond': 'acte', 'dateEffet': '2026-07-01', 'version': 2},
      ]);
      final ref = avant['releve'] as List;
      var identiques = 0, differentes = 0;
      for (var i = 0; i < ref.length; i++) {
        final a = _jsonne(apres[i]), b = ref[i] as Map;
        if ('${b['date']}'.compareTo('2026-07-01') < 0) {
          expect(a, b, reason: 'pièce du ${b['date']} (${b['patientId']}) : doit garder son taux');
          identiques++;
        } else if (a.toString() != b.toString()) {
          differentes++;
        }
      }
      expect(identiques, greaterThan(20));
      expect(differentes, greaterThan(0), reason: 'après le 01/07, la nouvelle version s’applique bien');
    });

    test('une version future ne compte pas ; une série qui ne commence que plus tard n’existe pas avant', () {
      final g = <F>[
        {'id': 'A', 'souscripteurId': 'S1', 'categorie': 'analyse', 'libelle': 'Bilan', 'taux': 70},
        {'id': 'B', 'souscripteurId': 'S1', 'categorie': 'analyse', 'libelle': 'Bilan', 'taux': 90, 'dateEffet': '2027-01-01', 'version': 2},
        {'id': 'C', 'souscripteurId': 'S1', 'categorie': 'imagerie', 'libelle': 'Écho', 'taux': 60, 'dateEffet': '2027-03-01', 'version': 1},
      ];
      expect(garantiesEnVigueur(g, '2026-12-31').map((x) => x['id']), ['A']);
      expect(garantiesEnVigueur(g, '2027-01-01').map((x) => x['id']), ['B']);
      expect(garantiesEnVigueur(g, '2027-03-01').map((x) => x['id']), ['B', 'C']);
    });

    test('la clé d’une garantie est souscripteur + catégorie + libellé (accents, casse et espaces neutralisés)', () {
      final g = <F>[
        {'id': 'A', 'souscripteurId': 'S1', 'categorie': 'consultation', 'libelle': 'Consultation spécialiste', 'taux': 70},
        {'id': 'B', 'souscripteurId': 'S1', 'categorie': 'consultation', 'libelle': 'consultation SPECIALISTE ', 'taux': 60, 'dateEffet': '2026-09-01'},
        {'id': 'C', 'souscripteurId': 'S1', 'categorie': 'consultation', 'libelle': 'Consultation généraliste', 'taux': 80},
        {'id': 'D', 'souscripteurId': 'S2', 'categorie': 'consultation', 'libelle': 'Consultation spécialiste', 'taux': 10},
      ];
      expect(cleSerieGarantie(g[0]), cleSerieGarantie(g[1]));
      expect(cleSerieGarantie(g[0]), isNot(cleSerieGarantie(g[2])), reason: 'deux libellés d’une même catégorie sont deux séries');
      expect(cleSerieGarantie(g[0]), isNot(cleSerieGarantie(g[3])), reason: 'deux souscripteurs, deux séries');
      expect(garantiesEnVigueur(g.take(3), '2026-10-01').map((x) => x['id']), ['B', 'C']);
    });

    test('un doublon d’avant le mécanisme (même garantie deux fois, sans date) : la première garde la main, comme avant', () {
      final g = <F>[
        {'id': 'A', 'souscripteurId': 'S1', 'categorie': 'analyse', 'libelle': 'Bilan', 'taux': 70},
        {'id': 'B', 'souscripteurId': 'S1', 'categorie': 'analyse', 'libelle': 'Bilan', 'taux': 99},
      ];
      expect(garantiesEnVigueur(g, '2026-01-01').map((x) => x['id']), ['A']);
    });
  });

  group('assPoserGarantie : une version, jamais un écrasement', () {
    F fac(String numero, String date, {String pat = 'PA1'}) => {'id': numero, 'numero': numero, 'date': date, 'assureur': 'ASS1', 'patientId': pat};
    AssPoseGarantie poser(Map<String, Object?> spec, {List<F>? factures, List<F>? garanties, bool essai = false}) => assPoserGarantie(
          {'souscripteurId': 'S2', 'categorie': 'analyse', 'libelle': 'Analyses et travaux de laboratoire', 'taux': 70, 'plafond': null, 'dateEffet': '2026-09-01', ...spec},
          souscripteurs: souscripteursJeu(),
          garanties: garanties ?? garantiesJeu(),
          factures: factures ?? const [],
          patients: patientsJeu(),
          couvertures: couverturesJeu(),
          essai: essai,
        );

    test('une version se pose avec son rang et sa date ; la version remplacée n’est pas touchée', () {
      final r = poser({});
      expect(r.ok, isTrue);
      expect(r.version, 2);
      expect(r.fiche!['dateEffet'], '2026-09-01');
      expect(r.fiche!['version'], 2);
      expect(r.ancienne!['id'], 'GAR-S2-C');
      expect(r.ancienne!['taux'], 60, reason: 'la version remplacée reste écrite telle quelle');
    });

    test('refus nommés : date absente, même date, version dans le passé, taux, plafond, unité, souscripteur, catégorie, libellé', () {
      expect(poser({'dateEffet': ''}).code, 'DATE_EFFET_REQUISE');
      final g1 = [...garantiesJeu(), {...garantiesJeu().firstWhere((x) => x['id'] == 'GAR-S2-C'), 'id': 'v2', 'taux': 70, 'dateEffet': '2026-09-01', 'version': 2}];
      expect(poser({'taux': 75}, garanties: g1).code, 'VERSION_MEME_DATE');
      expect(poser({'taux': 75, 'dateEffet': '2026-08-01'}, garanties: g1).code, 'VERSION_ANTERIEURE');
      expect(poser({'taux': 70}, garanties: g1).code, 'GARANTIE_INCHANGEE');
      expect(poser({'taux': 120}).code, 'TAUX_INVALIDE');
      expect(poser({'plafond': 1500.5, 'unitePlafond': 'acte'}).code, 'PLAFOND_INVALIDE');
      expect(poser({'plafond': 1500}).code, 'UNITE_PLAFOND_REQUISE');
      expect(poser({'souscripteurId': 'ZZ'}).code, 'SOUSCRIPTEUR_INCONNU');
      expect(poser({'categorie': 'inconnue'}).code, 'CATEGORIE_INCONNUE');
      expect(poser({'libelle': '  '}).code, 'GARANTIE_SANS_LIBELLE');
    });

    test('une date d’effet qu’une facture émise a déjà dépassée est refusée en nommant la pièce ; la veille de la facture passe', () {
      final f = [fac('F-2026-7', '2026-08-10', pat: 'PA2')];
      final r = poser({'dateEffet': '2026-08-01'}, factures: f);
      expect(r.code, 'FACTURE_DEJA_EMISE');
      expect(r.motif, contains('F-2026-7'));
      expect(poser({'dateEffet': '2026-08-11'}, factures: f).ok, isTrue);
      expect(poser({'dateEffet': '2026-08-10'}, factures: f).code, 'FACTURE_DEJA_EMISE', reason: 'le jour même de la pièce compte');
    });

    test('« depuis l’ouverture » : admis pour la première ligne d’une série, jamais pour une série qui existe', () {
      final neuf = poser({'libelle': 'Dentaire', 'categorie': 'dentaire', 'sansDate': true, 'dateEffet': null, 'taux': 50});
      expect(neuf.ok, isTrue);
      expect(neuf.fiche!['dateEffet'], isNull);
      expect(neuf.fiche!['version'], 1);
      expect(poser({'sansDate': true, 'dateEffet': null}).code, 'SERIE_EXISTANTE');
    });

    test('l’essai ne rend aucune fiche', () => expect(poser({}, essai: true).fiche, isNull));
  });

  group('garde du magasin (immutabilité)', () {
    String? garde(String op, F apres, F? avant, {List<F>? garanties, F? facture}) => assGardeGarantie(op, apres, avant,
        garanties: garanties ?? garantiesJeu(), souscripteur: (id) => souscripteursJeu().where((s) => s['id'] == id).firstOrNull, factureSousGrille: (s, j) => facture);
    final c = {...garantiesJeu().firstWhere((x) => x['id'] == 'GAR-S2-C'), 'version': 1};

    test('aucun champ d’une version posée ne se modifie : taux, plafond, unité, libellé, catégorie, date, rang', () {
      for (final k in assChampsImmuablesGarantie) {
        final apres = {...c, k: k == 'taux' || k == 'plafond' ? 1 : 'autre'};
        expect(garde('modifier', apres, c), contains('IMMUABLE'), reason: k);
      }
      expect(garde('modifier', {...c, 'source': 'autre pièce'}, c), isNull, reason: 'un champ de provenance reste libre');
      // Le rang d'une version qui n'en portait pas (migration) se pose une fois, jamais deux.
      final sansRang = {...c}..remove('version');
      expect(garde('modifier', {...sansRang, 'version': 1}, sansRang), isNull, reason: 'migration : le rang se pose une fois');
      expect(garde('modifier', {...sansRang, 'version': 1, 'taux': 1}, sansRang), contains('IMMUABLE'));
    });

    test('une version se pose sur la série à une date postérieure ; sans date, ou à une date déjà prise, ou dans le passé : refus', () {
      final v = {...c, 'id': 'nouvelle', 'taux': 65, 'dateEffet': '2026-09-01', 'version': 2};
      expect(garde('inserer', v, null), isNull);
      expect(garde('inserer', {...v, 'dateEffet': null}, null), contains('depuis l’ouverture'));
      final g2 = [...garantiesJeu(), {...v, 'id': 'v2'}];
      expect(garde('inserer', {...v, 'id': 'v3', 'taux': 66}, null, garanties: g2), contains('déjà effet'));
      expect(garde('inserer', {...v, 'id': 'v3', 'dateEffet': '2026-08-01'}, null, garanties: g2), contains('plus récente'));
      expect(garde('inserer', v, null, facture: {'numero': 'F9', 'date': '2026-09-05'}), contains('F9'));
    });

    test('une garantie sans doublon s’insère librement (première ligne d’une série) ; l’archivage refuse sous une version plus récente et sous une pièce émise', () {
      expect(garde('inserer', {'id': 'n', 'souscripteurId': 'S4', 'categorie': 'soin', 'libelle': 'Soins', 'taux': 50}, null), isNull);
      final g2 = [...garantiesJeu(), {...c, 'id': 'v2', 'taux': 65, 'dateEffet': '2026-09-01', 'version': 2}];
      expect(garde('archiver', c, c, garanties: g2), contains('plus récente'));
      expect(garde('archiver', g2.last, g2.last, garanties: g2), isNull);
      expect(garde('archiver', g2.last, g2.last, garanties: g2, facture: {'numero': 'F9', 'date': '2026-09-05'}), contains('F9'));
    });
  });

  group('migration d’un poste déjà peuplé', () {
    test('chaque série reçoit les rangs 1…n dans l’ordre des dates ; rien d’autre n’est écrit ; idempotente', () {
      final g = <F>[
        {'id': 'B', 'souscripteurId': 'S1', 'categorie': 'analyse', 'libelle': 'Bilan', 'taux': 90, 'dateEffet': '2027-01-01'},
        {'id': 'A', 'souscripteurId': 'S1', 'categorie': 'analyse', 'libelle': 'Bilan', 'taux': 70},
        {'id': 'C', 'souscripteurId': 'S2', 'categorie': 'analyse', 'libelle': 'Bilan', 'taux': 40},
        {'id': 'X', 'souscripteurId': 'S2', 'categorie': 'analyse', 'libelle': 'Bilan', 'taux': 41},
        {'id': 'Z', 'souscripteurId': 'S3', 'categorie': 'soin', 'libelle': 'Soin', 'taux': 10, 'version': 1, 'statut': 'archive'},
      ];
      final m = assMigrerGaranties(g);
      expect({for (final f in m.fiches) f['id']: f['version']}, {'A': 1, 'B': 2, 'C': 1, 'X': 2});
      expect(m.fiches.every((f) => f.keys.length == 2 && f.containsKey('id') && f.containsKey('version')), isTrue, reason: 'ni taux, ni plafond, ni date : seul le rang est posé');
      expect(m.series, 2);
      expect(m.doublons, 1, reason: 'le doublon sans date de S2 est compté, pas archivé');
      final ecrit = [for (final x in g) {...x, ...?m.fiches.where((f) => f['id'] == x['id']).firstOrNull}];
      expect(assMigrerGaranties(ecrit).aFait, isFalse, reason: 'rejouée, elle ne change plus rien');
    });
  });

  group('une ligne par série', () {
    test('trois séries (dont deux datées) : trois lignes, la version en vigueur et la version à venir', () {
      final g = <F>[
        {'id': 'A1', 'souscripteurId': 'S1', 'categorie': 'consultation', 'libelle': 'Consultation', 'taux': 70, 'version': 1},
        {'id': 'A2', 'souscripteurId': 'S1', 'categorie': 'consultation', 'libelle': 'Consultation', 'taux': 80, 'dateEffet': '2026-11-01', 'version': 2},
        {'id': 'A3', 'souscripteurId': 'S1', 'categorie': 'consultation', 'libelle': 'Consultation', 'taux': 90, 'dateEffet': '2026-12-01', 'version': 3},
        {'id': 'B1', 'souscripteurId': 'S1', 'categorie': 'analyse', 'libelle': 'Bilan', 'taux': 60, 'version': 1},
        {'id': 'B2', 'souscripteurId': 'S1', 'categorie': 'analyse', 'libelle': 'Bilan', 'taux': 65, 'dateEffet': '2026-10-01', 'version': 2},
        {'id': 'C1', 'souscripteurId': 'S1', 'categorie': 'soin', 'libelle': 'Soins', 'taux': 50, 'version': 1},
        {'id': 'D1', 'souscripteurId': 'S2', 'categorie': 'soin', 'libelle': 'Soins', 'taux': 10, 'version': 1},
      ];
      final s = assSeriesGarantie(g, '2026-11-14', souscripteurId: 'S1');
      expect(s.length, 3, reason: 'six lignes, trois séries');
      expect(s[0].enVigueur!['id'], 'A2');
      expect(s[0].aVenir!['id'], 'A3');
      expect(s[0].versions.map((x) => x['id']), ['A1', 'A2', 'A3']);
      expect(s[1].enVigueur!['id'], 'B2');
      expect(s[1].aVenir, isNull);
      expect(s[2].enVigueur!['id'], 'C1');
      expect(assSeriesGarantie(g, '2026-11-14').length, 4, reason: 'tous les souscripteurs : quatre séries');
      expect(assSeriesGarantie(g, '2026-10-01', souscripteurId: 'S1')[0].enVigueur!['id'], 'A1');
      expect(assRangGarantie({'id': 'A2'}, s[0].versions), 2, reason: 'un rang non écrit se lit à la place de la date');
    });
  });
}
