import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> p(String id, String nom, [String? parent]) => {'id': id, 'poste': nom, 'parentId': parent};

void main() {
  final postes = [p('A', 'Direction'), p('B', 'Service B', 'A'), p('C', 'Sous B1', 'B'), p('D', 'Sous B2', 'B'), p('E', 'Sous C1', 'C')];

  test('un poste avec deux sous-postes : ils sont rattachés au parent du poste archivé, nommés dans la phrase', () {
    final plan = cfaPlanArchivagePoste(postes, 'B');
    expect(plan.nouveauParentId, 'A');
    expect(plan.reaffectations.map((r) => r.id), ['C', 'D']);
    expect(plan.reaffectations.every((r) => r.ancienParentId == 'B' && r.nouveauParentId == 'A'), isTrue);
    expect(plan.phrase, allOf(contains('2 sous-postes'), contains('« Sous B1 »'), contains('« Sous B2 »'), contains('« Direction »')));
  });

  test('un sommet archivé : ses sous-postes deviennent des sommets', () {
    final plan = cfaPlanArchivagePoste(postes, 'A');
    expect(plan.nouveauParentId, isNull);
    expect(plan.reaffectations.map((r) => r.id), ['B']);
    expect(plan.reaffectations.single.nouveauParentId, isNull);
    expect(plan.phrase, contains('sommet'));
  });

  test('un poste sans sous-poste : rien n’est réaffecté ; seuls les sous-postes directs bougent', () {
    expect(cfaPlanArchivagePoste(postes, 'E').reaffectations, isEmpty);
    expect(cfaPlanArchivagePoste(postes, 'C').reaffectations.map((r) => r.id), ['E']);
  });

  test('annulation : un sous-poste inchangé est restitué, un sous-poste modifié entre-temps ou archivé est nommé et non écrasé', () {
    final plan = cfaPlanArchivagePoste(postes, 'B');
    final apres = [p('A', 'Direction'), p('C', 'Sous B1', 'A'), p('D', 'Sous B2', 'E'), p('E', 'Sous C1', 'C')];
    final r = cfaPlanAnnulationArchivage(apres, plan.reaffectations);
    expect(r.restituables.map((x) => x.id), ['C']);
    expect(r.modifies.map((x) => x.id), ['D']);
    final sans = cfaPlanAnnulationArchivage([p('A', 'Direction'), p('C', 'Sous B1', 'A')], plan.reaffectations);
    expect(sans.modifies.map((x) => x.id), ['D'], reason: 'un sous-poste archivé n’est pas restitué');
  });

  test('restauration : la note dit que les sous-postes ne sont pas rattachés d’office ; rien à dire sans réaffectation', () {
    final plan = cfaPlanArchivagePoste(postes, 'B');
    final poste = {...p('B', 'Service B', 'A'), 'sousPostesReaffectes': [for (final r in plan.reaffectations) r.toJson()]};
    final note = cfaNoteRestaurationPoste(poste, [p('C', 'Sous B1', 'A'), p('D', 'Sous B2', 'A')]);
    expect(note, allOf(contains('« Sous B1 »'), contains('PAS rattachés')));
    expect(cfaNoteRestaurationPoste(p('B', 'Service B', 'A'), postes), isNull);
  });
}
