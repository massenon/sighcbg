import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/planning_rh_poste.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;

/// PLANNING INDIVIDUEL (Direction, 16/11/2026, §8) : une version de régime individuel posée sur un poste rejoint la mère et les autres postes (qui calculent primes et paie
/// sur le régime EFFECTIF de l'agent). Elle est IMMUABLE : famille B (ajout seul) à la mère Dart et au banc Node, et la garde de collection refuse toujours de la réécrire
/// chez celui qui la reçoit. Elle porte l'honoraire de l'agent : jamais vers un téléphone. Données de test fictives.
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
    // La famille B de la mère : une ligne écrite ne se modifie jamais.
    if (existe) throw StateError('journal_immuable : un journal ne se modifie pas');
    final col = j.fiches.putIfAbsent(c, () => {});
    col[fiche] = jsonDecode(jsonEncode(champs)) as Map<String, Object?>;
  }
}

void main() {
  Magasin poste() => Magasin({
        'regimesIndividuels': [],
        'regimesTravail': [],
        'planning': [],
        'personnel': [
          {'id': 'EMPS1', 'statut': 'actif', 'nomComplet': 'AGENT Synchro Fictif', 'matricule': '0', 'fonction': 'infirmier'}
        ],
      }, 'POSTE');

  test('la collection voyage : famille B à la mère Dart et au banc Node, au pont du poste ; jamais vers un téléphone', () {
    expect(collectionsActivite, contains('regimesIndividuels'));
    expect(collectionsAjoutSeul.contains('regimesIndividuels'), isFalse, reason: 'les identifiants RGI-… se suivent par poste : l’identité de synchronisation porte l’étiquette du poste');
    final dart = File('../../packages/sync_dart/lib/src/mere.dart').readAsStringSync();
    expect(dart, contains("'regimesIndividuels': 'B'"));
    expect(dart, contains("collectionsRemunerationJamaisMobile = {'prestataires', 'regimesIndividuels'}"));
    expect(dart, contains('...collectionsRemunerationJamaisMobile'), reason: 'exclue au chemin de lecture du mobile');
    final js = File('../../packages/sync/banc/mere.js').readAsStringSync();
    expect(js, contains("regimesIndividuels: 'B'"));
    final jamais = RegExp(r'const MOBILE_JAMAIS = \[([^\]]*)\]').firstMatch(js)!.group(1)!;
    expect(jamais, contains("'regimesIndividuels'"));
  });

  test('une version posée chez un fileul arrive à la mère et à l’autre fileul, sans doublon ; reçue, elle reste immuable et sert la même résolution', () async {
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

    final r = PlanningRhPoste(mf1, auteur: () => 'Administrateur', role: 'admin', horloge: () => DateTime(2026, 12, 1)).poserRegime(
        employeId: 'EMPS1', dateEffet: '2026-12-01', mode: 'derogation', champs: {'repos': 'repos24', 'jours': ['lun', 'mar']}, motif: 'Sonde de synchronisation');
    expect(r['ok'], isTrue);
    await tour();
    for (final m in [mm, mf2]) {
      final v = m.collection('regimesIndividuels').toutes.single;
      expect([v['employeId'], v['mode'], v['aValider']], ['EMPS1', 'derogation', ['repos', 'jours']]);
      final reg = PlanningRhPoste(m, auteur: () => 'X', role: 'admin', horloge: () => DateTime(2026, 12, 2))
          .regimeALaDate(m.collection('personnel').actives.single, '2026-12-02');
      expect([reg.repos, reg.jours, reg.individuel], ['repos24', ['lun', 'mar'], true]);
      expect(() => m.collection('regimesIndividuels').mettreAJour(v['id'], {'motif': 'Réécrit'}), throwsA(isA<EcritureRefusee>()), reason: 'la garde vaut chez celui qui reçoit');
    }
    expect(mf1.collection('regimesIndividuels').toutes, hasLength(1), reason: 'l’auteur ne se réimporte pas');
    expect(p1.motifsRefus, isEmpty, reason: 'aucune modification n’a été envoyée à un journal immuable');
  });
}
