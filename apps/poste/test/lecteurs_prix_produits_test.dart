import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// LA MESURE DES LECTEURS DE LA PROJECTION DES PRIX DE PRODUITS : la fiche `produits` porte `prixAchat` et `prixVente`, désormais DÉRIVÉS de la version du prix d'achat en vigueur
/// (la fiche suit la décision, `TarifsPoste.projeterProduits`). Qui les lit encore ? Le relevé (`fixtures/releves/lecteurs_prix_produits.json`) range, par fichier de `lib` du poste et du domaine,
/// le nombre de LECTURES (`['prixAchat']`, `['prixVente']`) et d'ÉCRITURES (`'prixAchat':`, `['prixAchat'] =`).
///
/// La règle : on ne retire QUE ce qui n'a aucun lecteur. Mesuré : tous les champs ont des lecteurs (stock, dispensation, facturation, achats, valorisation, mobile, consultation) : AUCUN champ de la
/// projection n'est retiré. Un NOUVEAU lecteur ou un nouvel écrivain est une décision, pas un détail : le test échoue en nommant le fichier, et le relevé se réécrit en connaissance de cause
/// (`RELEVE_ECRIRE=1`). Les écrivains légitimes de la fiche sont la reprise, la projection, la création et les imports ; aucun écran ne l'écrit plus depuis un formulaire de modification.
final _lecture = RegExp(r"\['prix(Achat|Vente)'\](?!\s*=[^=])");
final _ecriture = RegExp(r"'prix(Achat|Vente)'\s*:|\['prix(Achat|Vente)'\]\s*=[^=]");
const _racines = ['lib', '../../packages/domaine/lib'];
const _fichier = 'test/fixtures/releves/lecteurs_prix_produits.json';

Map<String, Object?> mesure() {
  final out = <String, Object?>{};
  for (final r in _racines) {
    for (final f in Directory(r).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final t = f.readAsStringSync();
      // Les lignes de commentaire ne comptent pas : elles disent, elles ne lisent pas.
      final code = t.split('\n').where((l) => !l.trimLeft().startsWith('///') && !l.trimLeft().startsWith('//')).join('\n');
      final l = _lecture.allMatches(code).length, e = _ecriture.allMatches(code).length;
      if (l + e > 0) out[f.path.replaceFirst('../../packages/domaine/', 'domaine/')] = {'lectures': l, 'ecritures': e};
    }
  }
  return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

void main() {
  test('les lecteurs et les écrivains du prix d\'achat et du prix de vente des produits sont ceux du relevé : un nouveau est une décision nommée', () {
    final actuel = jsonDecode(jsonEncode(mesure())) as Map;
    if (Platform.environment['RELEVE_ECRIRE'] == '1') {
      File(_fichier).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(actuel)}\n');
      return;
    }
    final avant = jsonDecode(File(_fichier).readAsStringSync()) as Map;
    final ecarts = <String>[
      for (final k in {...avant.keys, ...actuel.keys})
        if (jsonEncode(avant[k]) != jsonEncode(actuel[k])) '$k : ${jsonEncode(avant[k])} → ${jsonEncode(actuel[k])}'
    ];
    expect(ecarts, isEmpty, reason: 'un lecteur ou un écrivain a changé : décider, puis réécrire le relevé');
  });

  test('aucun écran ne reçoit le prix d\'achat d\'un formulaire de modification : la fiche n\'est écrite que par la reprise, la projection, la création et les imports', () {
    final m = mesure();
    // Les écrivains du poste : le magasin (projection), la reprise et l'écran de création du référentiel produits (le prix saisi POSE la version 1, la fiche le porte déjà).
    final ecrivains = [for (final e in m.entries.where((e) => e.key.startsWith('lib/')) ) if ((e.value as Map)['ecritures'] as int > 0) e.key];
    for (final f in ecrivains) {
      expect(['lib/modules/m6/stock_produits.dart', 'lib/modules/m7/besoins_commun.dart', 'lib/modules/cfg/cft_tarifs.dart', 'lib/modules/m6/stock_commun.dart'].contains(f) || f.contains('import') || f.contains('donnees'), isTrue, reason: '$f écrit un prix de produit');
    }
  });

  test('la mesure a des lecteurs pour CHAQUE champ : rien n\'est retiré (un champ sans lecteur serait retiré, avec le relevé avant/après)', () {
    final avant = jsonDecode(File(_fichier).readAsStringSync()) as Map;
    final lecteurs = avant.entries.where((e) => ((e.value as Map)['lectures'] as int) > 0).length;
    expect(lecteurs, greaterThan(10));
    final texte = Directory('lib').listSync(recursive: true).whereType<File>().map((f) => f.readAsStringSync()).join('\n') +
        Directory('../../packages/domaine/lib').listSync(recursive: true).whereType<File>().map((f) => f.readAsStringSync()).join('\n');
    expect(RegExp(r"\['prixAchat'\]").hasMatch(texte), isTrue);
    expect(RegExp(r"\['prixVente'\]").hasMatch(texte), isTrue);
  });
}
