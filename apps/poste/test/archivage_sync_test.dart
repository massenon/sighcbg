import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/fusion_activite.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;

/// D6 (09/11/2026) : l'archivage du jeu de démonstration est une opération NORMALE de la synchronisation. Il se propage aux postes fileuls et n'est ni refusé ni
/// écrasé par une fiche distante non archivée plus ancienne, ni par une modification concurrente d'un autre poste. Ici : la règle de fusion pure, puis le pont
/// de deux postes et de la mère (journal partagé fictif), dont la mère qui archive par son drapeau `archive` (route `POST /admin/reinitialiser`).
class Journal {
  final Map<String, Map<String, Map<String, Object?>>> fiches = {};

  /// Les fiches que la MÈRE a archivées (drapeau `archive` du journal, sans champ `statut` posé par un poste).
  final Set<String> archiveesParLaMere = {};
  final List<String> restaurations = [];
}

class TransportFictif implements TransportPont {
  TransportFictif(this.j);
  final Journal j;
  @override
  Future<List<PieceSync>> liste(String c) async => [
        for (final e in (j.fiches[c] ?? {}).entries)
          PieceSync(e.key, jsonDecode(jsonEncode(e.value)) as Map<String, Object?>, archive: j.archiveesParLaMere.contains('$c/${e.key}'))
      ];
  @override
  Future<void> ecrire(String c, String fiche, {required bool existe, required Map<String, Object?> champs}) async {
    final col = j.fiches.putIfAbsent(c, () => {});
    col[fiche] = {...?col[fiche], ...jsonDecode(jsonEncode(champs)) as Map<String, Object?>};
  }

  /// L'opération `restaurer` de la mère : le drapeau `archive` du journal retombe.
  @override
  Future<void> restaurer(String c, String fiche) async {
    j.archiveesParLaMere.remove('$c/$fiche');
    j.restaurations.add('$c/$fiche');
  }
}

Magasin poste() => Magasin({'patients': [], 'identifiants': [], 'rendezvous': []});

Future<void> tour(List<PontActivite> ponts) async {
  for (var i = 0; i < 3; i++) {
    for (final p in ponts) {
      await p.cycle();
    }
  }
}

const marques = {'_archiveLe': '2026-11-09T10:00:00.000', '_archivePar': 'Admin', '_motifArchivage': cfbMotifArchivageJeuDemo};

void main() {
  group('règle de fusion : l\'archivage l\'emporte', () {
    test('une version archivée contre une modification concurrente : la fusion est archivée, l\'ancien statut est gardé', () {
      final local = {'id': 'a', 'statut': 'planifie', 'motif': 'Contrôle'};
      final recu = {'statut': 'archive', 'statutAvantArchivage': 'honore', ...marques};
      final fusion = {'id': 'a', 'statut': 'planifie', 'motif': 'Contrôle'};
      expect(fusionnerArchivage(fusion, local, recu), isTrue);
      expect(fusion['statut'], 'archive');
      expect(fusion['statutAvantArchivage'], 'honore');
      expect(fusion['_motifArchivage'], cfbMotifArchivageJeuDemo);
      expect(fusion['motif'], 'Contrôle', reason: 'le reste de la fiche n\'est pas touché');
    });

    test('la fiche locale archivée n\'est pas ré-activée par une fiche distante plus ancienne, non archivée', () {
      final local = {'id': 'a', 'statut': 'archive', 'statutAvantArchivage': 'validee', ...marques};
      final recu = {'statut': 'validee', 'montant': 5};
      final fusion = {'id': 'a', 'statut': 'validee', 'montant': 5};
      expect(fusionnerArchivage(fusion, local, recu), isTrue);
      expect(fusion['statut'], 'archive');
      expect(fusion['statutAvantArchivage'], 'validee');
    });

    test('déjà archivée à la dernière synchronisation : ce n\'est plus une nouveauté, la restauration se propage', () {
      final base = {'statut': 'archive'};
      final local = {'id': 'a', 'statut': 'validee'};
      final recu = {'statut': 'archive'};
      final fusion = {'id': 'a', 'statut': 'validee'};
      expect(fusionnerArchivage(fusion, local, recu, base: base), isFalse);
      expect(fusion['statut'], 'validee');
    });

    test('aucune version archivée : rien ne change', () {
      final fusion = {'id': 'a', 'statut': 'validee'};
      expect(fusionnerArchivage(fusion, {'statut': 'validee'}, {'statut': 'brouillon'}), isFalse);
      expect(fusion, {'id': 'a', 'statut': 'validee'});
    });
  });

  group('le pont de deux postes et de la mère', () {
    late Journal j;
    late Magasin ma, mb, mm;
    late PontActivite pa, pb, pm;
    setUp(() {
      j = Journal();
      ma = poste();
      mb = poste();
      mm = poste();
      pa = PontActivite(ma, TransportFictif(j), etiquette: 'A');
      pb = PontActivite(mb, TransportFictif(j), etiquette: 'B');
      pm = PontActivite(mm, TransportFictif(j), etiquette: 'M');
    });

    Future<void> creerEtSynchroniser() async {
      ma.collection('patients').inserer({'nom': 'AGORO', 'code': 'CBG/1/26', 'statut': 'actif'}, prefixe: 'PAT');
      ma.collection('patients').inserer({'nom': 'BELLO', 'code': 'CBG/2/26', 'statut': 'actif'}, prefixe: 'PAT');
      await tour([pa, pb, pm]);
    }

    test('l\'archivage en bloc d\'un poste arrive aux autres : statut, ancien statut, motif, acteur et date', () async {
      await creerEtSynchroniser();
      final r = ma.collection('patients').archiverTout(marques: marques);
      expect(r.archivees, 2);
      await tour([pa, pb, pm]);
      for (final m in [mb, mm]) {
        expect(m.collection('patients').actives, isEmpty, reason: 'archivées partout');
        final f = m.collection('patients').toutes.first;
        expect([f['statut'], f['statutAvantArchivage'], f['_motifArchivage'], f['_archivePar']], ['archive', 'actif', cfbMotifArchivageJeuDemo, 'Admin']);
      }
      expect(ma.collection('patients').toutes, hasLength(2), reason: 'aucune fiche perdue, aucun doublon');
    });

    test('un poste qui MODIFIE la fiche pendant que l\'autre l\'archive ne l\'écrase pas : l\'archivage gagne partout', () async {
      await creerEtSynchroniser();
      ma.collection('patients').archiverTout(marques: marques);
      final idb = mb.collection('patients').toutes.firstWhere((f) => f['nom'] == 'AGORO')['id'];
      mb.collection('patients').mettreAJour(idb, {'statut': 'hospitalise'});
      await tour([pa, pb, pm]);
      for (final m in [ma, mb, mm]) {
        expect(m.collection('patients').actives, isEmpty, reason: 'la fiche modifiée sur B reste archivée');
      }
      final fb = mb.collection('patients').toutes.firstWhere((f) => f['nom'] == 'AGORO');
      expect(fb['statut'], 'archive');
      expect(fb['_motifArchivage'], cfbMotifArchivageJeuDemo);
    });

    test('une restauration depuis la Corbeille d\'un poste se propage aux autres', () async {
      await creerEtSynchroniser();
      ma.collection('patients').archiverTout(marques: marques);
      await tour([pa, pb, pm]);
      final idb = mb.collection('patients').toutes.firstWhere((f) => f['nom'] == 'BELLO')['id'];
      mb.collection('patients').restaurer(idb);
      await tour([pa, pb, pm]);
      for (final m in [ma, mb, mm]) {
        final actives = m.collection('patients').actives;
        expect(actives.map((f) => f['nom']), ['BELLO']);
        expect(actives.single['statut'], 'actif');
      }
    });

    test('la MÈRE archive (drapeau du journal, ses opérations `archiver`) : les postes reçoivent l\'archivage, même s\'ils avaient une fiche active plus ancienne', () async {
      await creerEtSynchroniser();
      final cleBello = j.fiches['patients']!.entries.firstWhere((e) => e.value['nom'] == 'BELLO').key;
      final cleAgoro = j.fiches['patients']!.entries.firstWhere((e) => e.value['nom'] == 'AGORO').key;
      // Ce que `Mere.reinitialiser` écrit : les marques en `modifier`, puis le drapeau `archive`.
      for (final cle in [cleBello, cleAgoro]) {
        j.fiches['patients']![cle] = {...j.fiches['patients']![cle]!, ...marques};
        j.archiveesParLaMere.add('patients/$cle');
      }
      // Un fileul modifie la fiche au même moment : l'archivage de la mère n'est pas écrasé.
      final idb = mb.collection('patients').toutes.firstWhere((f) => f['nom'] == 'AGORO')['id'];
      mb.collection('patients').mettreAJour(idb, {'statut': 'hospitalise'});
      await tour([pa, pb, pm]);
      for (final m in [ma, mb, mm]) {
        expect(m.collection('patients').actives, isEmpty, reason: 'archivées sur les trois postes');
        final f = m.collection('patients').toutes.firstWhere((x) => x['nom'] == 'BELLO');
        expect([f['statut'], f['statutAvantArchivage'], f['_motifArchivage']], ['archive', 'actif', cfbMotifArchivageJeuDemo], reason: 'restaurable avec son ancien statut');
      }
      // Restaurée depuis la Corbeille d'un poste après l'archivage de la mère : c'est une opération `restaurer` (le drapeau de la mère retombe), les marques
      // d'archivage sont effacées partout, et les autres postes la voient active.
      final idRestaure = mm.collection('patients').toutes.firstWhere((f) => f['nom'] == 'BELLO')['id'];
      mm.collection('patients').restaurer(idRestaure);
      expect(mm.collection('patients').actives.single['statut'], 'actif');
      await tour([pa, pb, pm]);
      expect(j.restaurations, ['patients/$cleBello']);
      for (final m in [ma, mb, mm]) {
        final actives = m.collection('patients').actives;
        expect(actives.map((f) => f['nom']), ['BELLO'], reason: 'restaurée partout, l\'autre reste archivée');
        expect([actives.single['statut'], actives.single['_motifArchivage'], actives.single['_archiveLe']], ['actif', null, null]);
      }
    });
  });
}
