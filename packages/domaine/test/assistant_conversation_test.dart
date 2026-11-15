// Lot AST-1 : la conversation de l'assistant — purge à 30 jours (réglable, borné), plafond de tours, forme gardée. Le chiffrement et le disque sont l'affaire du poste.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

TourAst tour(String id, String quand) => TourAst(
    id: id, quand: quand, question: 'Question $id', reponse: const ReponseAst(statut: 'reponse', titre: 'T', sources: [SourceAst('m1-patients', 'patients')], lignes: ['L'], intention: 'I01'));

void main() {
  final maintenant = DateTime.utc(2026, 11, 14, 12);
  test('la durée par défaut est de 30 jours, bornée de 1 à 90', () {
    expect([astRetentionDefaut, astRetentionMin, astRetentionMax], [30, 1, 90]);
    expect(astRetentionJours(null), 30);
    expect(astRetentionJours(0), 30);
    expect(astRetentionJours(91), 30);
    expect(astRetentionJours(90), 90);
    expect(astRetentionJours('12'), 12);
  });
  test('la purge retire ce qui a plus de 30 jours, garde le reste, et la limite exacte reste', () {
    final tours = [tour('vieux', '2026-10-01T00:00:00Z'), tour('limite', '2026-10-15T12:00:00Z'), tour('recent', '2026-11-13T12:00:00Z'), tour('illisible', 'hier')];
    final gardes = astPurger(tours, maintenant, 30);
    expect(gardes.map((t) => t.id), ['limite', 'recent']);
  });
  test('un réglage de 7 jours purge plus court ; hors bornes, 30', () {
    final tours = [tour('a', '2026-11-01T00:00:00Z'), tour('b', '2026-11-12T00:00:00Z')];
    expect(astPurger(tours, maintenant, 7).map((t) => t.id), ['b']);
    expect(astPurger(tours, maintenant, 0).map((t) => t.id), ['a', 'b']);
  });
  test('au plus $astToursMax tours gardés, les plus récents', () {
    final tours = [for (var i = 0; i < astToursMax + 20; i++) tour('t$i', DateTime.utc(2026, 11, 14, 0, 0, 0).add(Duration(seconds: i)).toIso8601String())];
    final g = astPurger(tours, maintenant, 30);
    expect(g.length, astToursMax);
    expect(g.last.id, 't${astToursMax + 19}');
  });
  test('un tour se relit tel qu’il a été donné : question, réponse, source, motif de refus', () {
    final t = TourAst(
        id: 'x', quand: '2026-11-14T10:00:00Z', question: 'Annule la facture', reponse: const ReponseAst(statut: 'refus', code: 'ECRITURE_ABSENTE', titre: 'Refus', lignes: ['a'], geste: 'g', ecranRenvoi: 'm8-caisse', tableau: TableauAst(['c'], [['v']])));
    final r = TourAst.depuisJson(t.toJson())!;
    expect([r.question, r.reponse.code, r.reponse.ecranRenvoi, r.reponse.tableau!.lignes.single.single], ['Annule la facture', 'ECRITURE_ABSENTE', 'm8-caisse', 'v']);
    expect(TourAst.depuisJson({'id': 1}), isNull);
    expect(TourAst.depuisJson('x'), isNull);
  });
}
