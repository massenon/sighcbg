import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;

/// Q26 (Direction, 16/11/2026) : budgets et immobilisations rejoignent la synchronisation. Un import fait chez un fileul (écrit directement, jeux restreints) ne reste plus local au poste : la fiche arrive à
/// la mère et aux autres postes, champ à champ. Ces deux collections ne partent JAMAIS vers un téléphone (donnée financière, RG-13) ; la mère Dart et le banc Node les déclarent à l'identique.
class _Journal {
  final Map<String, Map<String, Map<String, Object?>>> fiches = {};
}

class _Transport implements TransportPont {
  _Transport(this.j);
  final _Journal j;
  @override
  Future<void> restaurer(String collection, String fiche) async => throw StateError('non porté');
  @override
  Future<List<PieceSync>> liste(String c) async => [for (final e in (j.fiches[c] ?? {}).entries) PieceSync(e.key, jsonDecode(jsonEncode(e.value)) as Map<String, Object?>)];
  @override
  Future<void> ecrire(String c, String fiche, {required bool existe, required Map<String, Object?> champs}) async {
    final col = j.fiches.putIfAbsent(c, () => {});
    col[fiche] = {...?col[fiche], ...jsonDecode(jsonEncode(champs)) as Map<String, Object?>};
  }
}

void main() {
  Magasin poste() => Magasin({'budgets': [], 'immobilisations': [], 'exercices': []});

  test('la collection voyage : famille A à la mère Dart, au banc Node, au pont du poste ; jamais vers un téléphone', () {
    expect(collectionsActivite, containsAll(['budgets', 'immobilisations']));
    final dart = File('../../packages/sync_dart/lib/src/mere.dart').readAsStringSync();
    expect(dart, contains("'budgets': 'A', 'immobilisations': 'A'"), reason: 'la mère Dart déclare la famille A');
    expect(dart, contains("collectionsFinanceJamaisMobile = {'budgets', 'immobilisations'}"));
    expect(dart, contains('...collectionsFinanceJamaisMobile'), reason: 'exclue au chemin de lecture du mobile');
    final js = File('../../packages/sync/banc/mere.js').readAsStringSync();
    expect(RegExp(r"budgets: 'A', immobilisations: 'A'").hasMatch(js), isTrue, reason: 'le banc Node déclare la même famille');
    final jamais = RegExp(r'const MOBILE_JAMAIS = \[([^\]]*)\]').firstMatch(js)!.group(1)!;
    expect(jamais, allOf(contains("'budgets'"), contains("'immobilisations'")));
  });

  test('un budget et une immobilisation écrits chez un fileul arrivent à la mère et à l’autre fileul, champ à champ, sans doublon', () async {
    final j = _Journal();
    final mf1 = poste(), mf2 = poste(), mm = poste();
    final p1 = PontActivite(mf1, _Transport(j), etiquette: 'F1');
    final p2 = PontActivite(mf2, _Transport(j), etiquette: 'F2');
    final pm = PontActivite(mm, _Transport(j), etiquette: 'M');
    Future<void> tour() async {
      for (var i = 0; i < 3; i++) {
        for (final p in [p1, p2, pm]) {
          await p.cycle();
        }
      }
    }

    mf1.collection('budgets').inserer({'reference': 'BG-2026-001', 'exercice': 2026, 'centreCout': 'CONSULTATION', 'montant': 1500000}, prefixe: 'BUD');
    mf1.collection('immobilisations').inserer({'designation': 'Échographe', 'dateAcquisition': '2026-02-01', 'valeur': 4200000}, prefixe: 'IMM');
    await tour();
    for (final m in [mm, mf2]) {
      expect(m.collection('budgets').toutes.single['reference'], 'BG-2026-001');
      expect(m.collection('immobilisations').toutes.single['valeur'], 4200000);
    }
    expect(mf1.collection('budgets').toutes, hasLength(1), reason: 'l’auteur ne se réimporte pas');
    // Deux postes modifient des champs différents : les deux changements survivent.
    final id = mf2.collection('budgets').toutes.single['id'];
    mf2.collection('budgets').mettreAJour(id, {'montant': 1600000});
    mm.collection('budgets').mettreAJour(mm.collection('budgets').toutes.single['id'], {'observation': 'Révisé par la DAF'});
    await tour();
    for (final m in [mf1, mf2, mm]) {
      final b = m.collection('budgets').toutes.single;
      expect([b['montant'], b['observation']], [1600000, 'Révisé par la DAF']);
    }
  });
}
