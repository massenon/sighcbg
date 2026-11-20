// PLAGES DE NUMÉROS PAR SÉRIE ET PAR ANNÉE (17/11/2026) : chevauchement refusé en nommant la plage, reprise au plus grand rang + 1, plages d'avant les séries annuelles rattachées à l'année que
// désignent les codes déjà attribués (jamais devinée), aucun code réécrit.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  final ref = DateTime(2026, 11, 17);
  const a = PlageNumeros(nom: 'besoins', annee: 2026, debut: 1, fin: 50, appareil: 'F1');
  const b = PlageNumeros(nom: 'besoins', annee: 2026, debut: 51, fin: 100, appareil: 'F2');

  group('chevauchement', () {
    test('une plage qui en recoupe une autre de la MÊME série et de la MÊME année est refusée en nommant la plage et son poste', () {
      final r = refusChevauchementPlage([a, b], nom: 'besoins', annee: 2026, debut: 40, fin: 89);
      expect(r, isNotNull);
      expect(r!.code, 'plage_chevauchement');
      expect(r.motif, allOf(contains('1 à 50'), contains('F1')));
      expect(r.geste, contains('101'), reason: 'le geste dit où reprendre : plus grand rang + 1');
      expect((r.extra['plage'] as Map)['appareil'], 'F1');
    });
    test('les bords comptent (une plage qui commence au dernier rang d\'une autre chevauche) ; la plage contiguë passe', () {
      expect(refusChevauchementPlage([a], nom: 'besoins', annee: 2026, debut: 50, fin: 99)?.code, 'plage_chevauchement');
      expect(refusChevauchementPlage([a], nom: 'besoins', annee: 2026, debut: 51, fin: 100), isNull);
    });
    test('une autre année ou une autre série ne chevauche jamais : les séries sont indépendantes', () {
      expect(refusChevauchementPlage([a], nom: 'besoins', annee: 2027, debut: 1, fin: 50), isNull, reason: 'la série annuelle repart à 1');
      expect(refusChevauchementPlage([a], nom: 'commandes', annee: 2026, debut: 1, fin: 50), isNull);
    });
    test('une plage vide est refusée', () {
      expect(refusChevauchementPlage(const [], nom: 'x', annee: 2026, debut: 5, fin: 4)?.code, 'plage_vide');
    });
  });

  group('reprise au plus grand rang + 1', () {
    test('série neuve : 1 ; sinon la fin de la plus haute plage + 1 ; jamais sous le minimum du demandeur', () {
      expect(debutProchainePlage(const [], nom: 'besoins', annee: 2026), 1);
      expect(debutProchainePlage([a, b], nom: 'besoins', annee: 2026), 101);
      expect(debutProchainePlage([a, b], nom: 'besoins', annee: 2027), 1);
      expect(debutProchainePlage([a, b], nom: 'besoins', annee: 2026, minimum: 140), 140);
      expect(debutProchainePlage([a, b], nom: 'besoins', annee: 2026, minimum: 3), 101);
    });
  });

  group('plages d\'avant les séries annuelles', () {
    const codes = ['CNT/1004/26', 'CNT/1010/26', 'CNT/12/25', 'CNT/2002/25', 'NON-CODE', null];
    test('l\'année est celle des codes déjà attribués dans la plage', () {
      expect(anneeDesCodesDeLaPlage(1000, 1049, codes, reference: ref), 2026);
      expect(anneeDesCodesDeLaPlage(2000, 2049, codes, reference: ref), 2025);
    });
    test('aucun code attribué, ou des codes de plusieurs années : aucune année devinée', () {
      expect(anneeDesCodesDeLaPlage(3000, 3049, codes, reference: ref), isNull);
      expect(anneeDesCodesDeLaPlage(1, 3000, codes, reference: ref), isNull, reason: 'ambigu');
    });
    test('rattachement : les plages sans année reçoivent celle de leurs codes ; une plage qui a une année n\'est jamais touchée ; le reste est dit', () {
      const plages = [
        PlageNumeros(nom: 'patients', debut: 1000, fin: 1049),
        PlageNumeros(nom: 'patients', debut: 3000, fin: 3049),
        PlageNumeros(nom: 'patients', debut: 2000, fin: 2049, annee: 2024),
      ];
      final r = rattacherPlagesAnciennes(plages, codes, reference: ref);
      expect(r.rattachees, {0: 2026});
      expect(r.sansAnnee, [1]);
      final avecDefaut = rattacherPlagesAnciennes(plages, codes, reference: ref, anneeParDefaut: 2026);
      expect(avecDefaut.rattachees, {0: 2026, 1: 2026});
      expect(avecDefaut.sansAnnee, isEmpty);
      expect(avecDefaut.rattachees.containsKey(2), isFalse);
    });
    test('lecture d\'une ligne de la table des plages', () {
      final p = PlageNumeros.depuis({'nom': 'besoins', 'debut': 1, 'fin': 50, 'annee': null, 'appareil': 'F1'})!;
      expect([p.nom, p.taille, p.annee, p.appareil], ['besoins', 50, null, 'F1']);
      expect(PlageNumeros.depuis({'debut': 'x'}), isNull);
    });
  });
}
