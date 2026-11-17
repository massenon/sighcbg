// La PHRASE d'un refus d'import de liasse (Direction de Baguidi, 18/11/2026) : « …(Unexpected character).. Importer… » — le motif porte déjà son point final, l'écran en ajoutait un second.
// La jonction se fait à la racine (`RefusImportFiscal.message`), pour TOUS les refus : jamais « .. », jamais de ponctuation doublée.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

String _texte(String nom) => File('../../apps/poste/tool/donnees/$nom').readAsStringSync();

String _modifie(String nom, void Function(Map<String, Object?> d) modifier) {
  final d = (jsonDecode(_texte(nom)) as Map).cast<String, Object?>();
  modifier(d);
  return jsonEncode(d);
}

Map<String, Object?> _m(Object? o) => (o as Map).cast<String, Object?>();

/// Une ponctuation doublée ou mal posée dans la phrase affichée.
void _proprete(String phrase, String contexte) {
  expect(phrase, isNot(contains('..')), reason: contexte);
  expect(phrase, isNot(contains('. .')), reason: contexte);
  expect(phrase, isNot(contains(' .')), reason: contexte);
  expect(phrase, isNot(contains(',.')), reason: contexte);
  expect(phrase, isNot(contains(':.')), reason: contexte);
  expect(phrase.endsWith('.'), isTrue, reason: '$contexte : la phrase se termine par UN point');
  expect(phrase.endsWith('..'), isFalse, reason: contexte);
  expect(phrase, isNot(contains(RegExp(r'\s{2,}'))), reason: contexte);
}

void main() {
  final auj = DateTime(2026, 11, 17, 10, 30);
  final liasse = lireDocumentFiscal(_texte('liasse_2025_demo.json')).document!;
  final classeur = lireDocumentFiscal(_texte('classeur_2025_demo.json')).document!;

  /// Tous les refus que les gardes et la lecture savent produire, chacun obtenu par le geste qui le déclenche (jamais fabriqué à la main).
  final refus = <RefusImportFiscal>[];
  void lire(String texte) {
    final r = lireDocumentFiscal(texte).refus;
    if (r != null) refus.add(r);
  }

  void depot(void Function(Map<String, Object?> x) f) => lire(_modifie('liasse_2025_demo.json', (d) => f(_m(d['DEPOT']))));
  void liasseMod(void Function(Map<String, Object?> d) f) => lire(_modifie('liasse_2025_demo.json', f));
  void classeurMod(void Function(Map<String, Object?> d) f) => lire(_modifie('classeur_2025_demo.json', f));
  void preparer(DocumentFiscalLu d, {String? date, String source = 'Remise à la DGI', String auteur = 'Comptable', bool droit = true, bool fileul = false}) {
    final r = preparerImportFiscal(document: d, dateDepot: date, source: source, auteur: auteur, maintenant: auj, existantes: const [], peutImporter: droit, estFileul: fileul).refus;
    if (r != null) refus.add(r);
  }

  setUpAll(() {
    // lecture
    lire('  ');
    lire('{pas du json');
    lire('{"a":');
    lire('[1,2]');
    lire('{"x":1}');
    liasseMod((d) => d.remove('FLUX'));
    liasseMod((d) => d['EXTRA'] = []);
    depot((x) => x['ifu'] = '12AB');
    depot((x) => x['dateDepot'] = '2026-02-31');
    depot((x) => x['exerciceN1'] = 2020);
    depot((x) => x['exerciceN'] = '2025');
    depot((x) => x['exerciceN'] = 1999);
    depot((x) => x['source'] = '  ');
    depot((x) => x.remove('denomination'));
    liasseMod((d) => d['BILAN_ACTIF'] = []);
    liasseMod((d) => d['BILAN_ACTIF'] = 'texte');
    liasseMod((d) => (d['BILAN_ACTIF'] as List).add({'ref': 'ZZ'}));
    liasseMod((d) => _m((d['BILAN_ACTIF'] as List).first)['t'] = 'sous-total');
    liasseMod((d) => _m((d['BILAN_ACTIF'] as List).first)['libelle'] = '');
    liasseMod((d) => (d['BILAN_ACTIF'] as List).add(Map<String, Object?>.from(_m((d['BILAN_ACTIF'] as List).first))));
    liasseMod((d) => _m((d['BILAN_ACTIF'] as List).first)['comptes'] = ['12AB']);
    liasseMod((d) => _m((d['RESULTAT'] as List).first)['signe'] = '*');
    liasseMod((d) => _m((d['ECARTS'] as List).first)['texte'] = '');
    liasseMod((d) => (d['ECARTS'] as List).add(Map<String, Object?>.from(_m((d['ECARTS'] as List).first))));
    liasseMod((d) => _m((d['BILAN_ACTIF'] as List).first)['ecart'] = 'inconnu');
    liasseMod((d) => _m(d['DISPONIBILITES'])['note'] = '');
    classeurMod((d) => d.remove('mois'));
    classeurMod((d) => d['annee'] = 1500);
    classeurMod((d) => d['mois'] = ['x']);
    classeurMod((d) => d['chiffreAffaires'] = [1]);
    classeurMod((d) => d['horsExploitation'] = [1]);
    classeurMod((d) => _m((d['depenses'] as List).first)['num'] = '12AB');
    classeurMod((d) => _m((d['depenses'] as List).first)['libelle'] = '');
    classeurMod((d) => _m((d['depenses'] as List).first)['aRattacher'] = !(_m((d['depenses'] as List).first)['aRattacher'] == true));
    classeurMod((d) => _m((d['depenses'] as List).first)['mois'] = [1]);
    classeurMod((d) => _m((d['depenses'] as List).first)['total'] = 1);
    classeurMod((d) => d['totalDepenses'] = 1);
    classeurMod((d) => _m(d['controle'])['postesSansCompte'] = 99);
    // gardes de la fiche
    preparer(liasse, droit: false);
    preparer(liasse, fileul: true);
    preparer(liasse, source: ' ');
    preparer(liasse, auteur: '');
    preparer(classeur);
    preparer(classeur, date: '2026-13-01');
    preparer(classeur, date: '2026-12-25');
    preparer(classeur, date: '2025-06-01');
    preparer(liasse, date: '2026-05-02');
  });

  group('la phrase d’un refus : un seul point, jamais « .. »', () {
    test('chaque refus réellement produit par la lecture et les gardes', () {
      expect(refus.length, greaterThan(30), reason: 'la batterie doit réellement produire des refus');
      for (final r in refus) {
        _proprete(r.message, r.code);
        expect(r.message, startsWith('${r.code} : '), reason: r.code);
        expect(r.message, contains(refusFiscalSansPonctuationFinale(r.geste)), reason: r.code);
        if (r.chemin.isNotEmpty) expect(r.message, contains('(${r.chemin})'), reason: r.code);
      }
    });

    test('le cas de la Direction : JSON illisible, le message de l’analyseur ne porte plus de double point', () {
      final r = lireDocumentFiscal('{pas du json').refus!;
      expect(r.code, 'JSON_ILLISIBLE');
      expect(r.message, isNot(contains('..')));
      expect(r.message, matches(RegExp(r'\)\. Importer le document tel que remis, au format JSON\.$')));
    });

    test('tous les codes que le fichier source sait produire sont couverts par la batterie ou par la jonction elle-même', () {
      final source = File('lib/src/comptabilite/documents_fiscaux_import.dart').readAsStringSync();
      final codes = {for (final m in RegExp(r"(?:_r|refus|non)\('([A-Z_]+)'").allMatches(source)) m.group(1)!};
      expect(codes.length, greaterThan(30));
      final produits = {for (final r in refus) r.code};
      // Un code que la batterie ne produit pas passe quand même par la même jonction : on la vérifie sur le gabarit de son motif/geste le plus défavorable.
      for (final c in codes.difference(produits)) {
        for (final fin in ['.', '..', '…', ')', ' ', '.)', '. ', '']) {
          _proprete(RefusImportFiscal(c, 'Un motif$fin', 'Un geste$fin', chemin: 'a.b[0]').message, '$c / fin « $fin »');
          _proprete(RefusImportFiscal(c, 'Un motif$fin', 'Un geste$fin').message, '$c sans chemin / fin « $fin »');
        }
      }
      expect(produits.length, greaterThan(codes.length ~/ 2), reason: 'au moins la moitié des codes est exercée par un vrai geste');
    });

    test('la jonction, pour toute ponctuation finale du motif ou du geste', () {
      for (final fin in ['', '.', '..', '...', '…', ' .', '. ', ';', ',', ':', ' ']) {
        final r = RefusImportFiscal('X_Y', 'Le motif$fin', 'Corriger le document$fin');
        expect(r.message, 'X_Y : Le motif. Corriger le document.', reason: 'fin « $fin »');
        final c = RefusImportFiscal('X_Y', 'Le motif$fin', 'Corriger le document$fin', chemin: 'DEPOT.ifu');
        expect(c.message, 'X_Y : Le motif (DEPOT.ifu). Corriger le document.', reason: 'fin « $fin » avec chemin');
      }
      // la parenthèse finale d'un motif est conservée : c'est elle que l'analyseur ferme
      expect(RefusImportFiscal('J', 'illisible (Unexpected character).', 'Importer.').message, 'J : illisible (Unexpected character). Importer.');
      // un geste absent ne laisse ni espace ni point orphelin
      expect(RefusImportFiscal('J', 'Motif.', '').message, 'J : Motif.');
    });
  });
}
