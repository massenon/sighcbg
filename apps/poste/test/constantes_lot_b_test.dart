// LOT B : les constantes à UNE SOURCE. Les champs de tension et de diurèse sont définis une fois (`champs_constantes.dart`) et servent l'accueil, la feuille de température et la
// feuille d'observation ; la tension se range en DEUX nombres (cmHg), la diurèse en millilitres ; un poste d'avant le lot est MIGRÉ une fois, sans rien inventer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m1/releves.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

typedef F = Map<String, Object?>;

ChampDef champ(List<ChampDef> l, String nom) => l.firstWhere((c) => c.nom == nom);

void main() {
  group('saisies à une source : accueil, feuille de température, feuille d’observation', () {
    late List<ChampDef> accueil;
    setUp(() {
      final m = Magasin({'patients': const <F>[], 'audit': const <F>[]}, 'POSTE');
      late List<ChampDef> l;
      // Le contexte n'est nécessaire qu'aux options de patient : `champs` ne le lit pas ailleurs.
      l = EcranConstantes.champs(
          ContexteEcran(ecranId: 'm1-constantes', role: 'reception', droit: const Droit(voir: true, editer: true, annuler: false), magasin: m, aller: (_) {}, utilisateur: 'T', child: const SizedBox()), null);
      accueil = l;
    });

    test('la même définition : mêmes noms, mêmes libellés (cmHg, mL), mêmes bornes que les champs partagés', () {
      final partages = [...champsTension(), champDiurese()];
      expect(partages.map((c) => c.nom), ['tensionSys', 'tensionDia', 'diurese']);
      for (final p in partages) {
        final a = champ(accueil, p.nom);
        expect(a.libelle, p.libelle, reason: p.nom);
        expect(a.type, TypeChamp.nombre);
        for (final v in ['0', '3', '4', '30', '31', '2', '20', '21', '5000', '5001', '6000', '1.5', '1200', 'abc']) {
          expect(a.valider!(v, const {}), p.valider!(v, const {}), reason: '${p.nom} = $v');
        }
      }
      expect(champ(accueil, 'tensionSys').libelle, 'Tension systolique (cmHg)');
      expect(champ(accueil, 'tensionDia').libelle, 'Tension diastolique (cmHg)');
      expect(champ(accueil, 'diurese').libelle, 'Diurèse (mL)');
    });

    test('bornes : systolique 4 à 30, diastolique 2 à 20 (cmHg), diurèse 0 à 5 000 mL ENTIÈRE (1,5 L se saisit 1500)', () {
      final s = champsTension();
      expect(s[0].valider!('4', const {}), isNull);
      expect(s[0].valider!('30', const {}), isNull);
      expect(s[0].valider!('3', const {}), isNotNull);
      expect(s[0].valider!('31', const {}), isNotNull);
      expect(s[1].valider!('2', const {}), isNull);
      expect(s[1].valider!('21', const {}), isNotNull);
      final d = champDiurese();
      expect(d.valider!('5000', const {}), isNull);
      expect(d.valider!('1200', const {}), isNull);
      expect(d.valider!('5001', const {}), isNotNull);
      expect(d.valider!('1.5', const {}), isNotNull, reason: 'millilitres, sans décimale : « 1.5 » est le signe d’une saisie encore en litres');
    });

    test('la feuille de température et la feuille d’observation exigent la tension (requis), l’accueil non : une seule définition, une seule option', () {
      expect(champsTension(requis: true).every((c) => c.requis), isTrue);
      expect(champsTension().every((c) => !c.requis), isTrue);
      expect(champ(accueil, 'tensionSys').requis, isFalse);
    });
  });

  group('un poste d’AVANT le lot est migré UNE fois', () {
    Map<String, List<F>> ancien() => {
          'releves': [
            {'id': 'REL1', 'statut': 'actif', 'admissionId': 'A1', 'date': '2026-10-01', 'heure': '08:00', 'tension': '12/8', 'diurese': 1200},
            {'id': 'REL2', 'statut': 'archive', 'admissionId': 'A1', 'date': '2026-10-01', 'heure': '14:00', 'tension': '11/7', 'diurese': 800},
            {'id': 'REL3', 'statut': 'actif', 'admissionId': 'A1', 'date': '2026-10-02', 'heure': '08:00', 'tension': 'à reprendre', 'diurese': 700},
          ],
          'constantes': [
            {'id': 'C1', 'statut': 'actif', 'patientId': 'P1', 'dateHeure': '2026-10-01T09:00', 'tensionSys': 13, 'tensionDia': 9, 'tension': '13/9', 'diurese': 1.5},
            {'id': 'C2', 'statut': 'actif', 'patientId': 'P1', 'dateHeure': '2026-10-02T09:00', 'tensionSys': 12, 'tensionDia': 8, 'tension': '12/8'},
          ],
          'observations': [
            {
              'id': 'OBS1',
              'statut': 'actif',
              'constantes': [
                {'heure': '2026-10-01T09:00:00Z', 'tension': '10/6', 'pouls': 70}
              ]
            }
          ],
        };

    Magasin poste() => Magasin({
          'releves': const <F>[],
          'constantes': const <F>[],
          'observations': const <F>[],
        }, 'POSTE');

    test('un poste déjà peuplé et SANS marque : tension scindée, diurèse d’accueil ×1000, texte illisible gardé et dit, marque posée, rapport disponible', () async {
      final p = PersistanceMemoire(ancien());
      final m = poste();
      await m.brancherPersistance(p, delai: Duration.zero);
      final r = m.collection('releves').toutes;
      expect(r[0]['tensionSys'], 12);
      expect(r[0]['tensionDia'], 8);
      expect(r[0].containsKey('tension'), isFalse);
      expect(r[0]['diurese'], 1200, reason: 'la diurèse du lit est déjà en mL');
      expect(r[1]['statut'], 'archive', reason: 'RG-14 : une fiche archivée est migrée et reste archivée');
      expect(r[1]['tensionSys'], 11);
      expect(r[2]['tension'], 'à reprendre', reason: 'jamais inventé');
      expect(r[2].containsKey('tensionSys'), isFalse);
      final c = m.collection('constantes').toutes;
      expect(c[0]['diurese'], 1500, reason: 'litres → millilitres');
      expect(c[0]['tension'], '13/9');
      expect(m.collection('observations').toutes.single['constantes'], [
        {'heure': '2026-10-01T09:00:00Z', 'pouls': 70, 'tensionSys': 10, 'tensionDia': 6}
      ]);
      final rap = m.migrationConstantes!;
      expect([rap.tensionsScindees, rap.tensionsIllisibles, rap.diuresesConverties], [3, 1, 1]);
      expect(p.meta['formeConstantes'], Magasin.formeConstantes);
      final trace = (p.meta['migrations'] as List).single as Map;
      expect(trace['nom'], 'constantes-lot-b');
      expect(trace['tensionsIllisibles'], 1);
      // Le disque porte la forme migrée.
      expect(p.contenu['releves']![0]['tensionSys'], 12);
      expect(p.contenu['constantes']![0]['diurese'], 1500);
    });

    test('REDÉMARRER ne reconvertit JAMAIS la diurèse : 1 500 mL ne devient pas 1 500 000 (la marque dit où en est le poste)', () async {
      final p = PersistanceMemoire(ancien());
      await poste().brancherPersistance(p, delai: Duration.zero);
      final m2 = poste();
      await m2.brancherPersistance(p, delai: Duration.zero);
      expect(m2.collection('constantes').toutes[0]['diurese'], 1500);
      expect(m2.migrationConstantes, isNull, reason: 'déjà à la bonne forme : rien à dire');
      final m3 = poste();
      await m3.brancherPersistance(p, delai: Duration.zero);
      expect(m3.collection('constantes').toutes[0]['diurese'], 1500);
      expect((p.meta['migrations'] as List).length, 1);
    });

    test('un poste NEUF (rien d’écrit) n’a rien à convertir : la marque est posée, aucune migration consignée', () async {
      final p = PersistanceMemoire();
      final m = Magasin({
        'constantes': [
          {'id': 'C1', 'statut': 'actif', 'diurese': 2}
        ],
      }, 'POSTE');
      await m.brancherPersistance(p, delai: Duration.zero);
      expect(m.collection('constantes').toutes.single['diurese'], 2, reason: '2 mL du jeu livré : jamais pris pour 2 L');
      expect(p.meta['formeConstantes'], Magasin.formeConstantes);
      expect(p.meta['migrations'], isNull);
      expect(m.migrationConstantes, isNull);
    });

    test('le jeu livré est à la bonne forme : aucun relevé d’hospitalisation ne porte plus de tension en texte', () {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
      final rel = m.collection('releves').toutes;
      expect(rel, isNotEmpty);
      for (final f in rel) {
        expect(f.containsKey('tension'), isFalse, reason: '${f['id']}');
        expect(f['tensionSys'], isA<num>());
        expect(f['tensionDia'], isA<num>());
        expect(f['tensionSys'], inInclusiveRange(hosTensionSysMin, hosTensionSysMax));
        expect(f['diurese'], inInclusiveRange(hosDiureseMin, hosDiureseMax));
      }
      for (final o in m.collection('observations').toutes) {
        for (final c in (o['constantes'] as List? ?? const []).cast<Map>()) {
          expect(c.containsKey('tension'), isFalse);
          expect(c['tensionSys'], isA<num>());
        }
      }
      final migre = hosMigrerConstantes(releves: rel, observations: m.collection('observations').toutes, diureseAccueilEnLitres: false);
      expect(migre.aFait, isFalse, reason: 'rien à migrer sur le jeu livré');
    });
  });
}
