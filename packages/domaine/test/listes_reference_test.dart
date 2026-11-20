// LES LISTES DE RÉFÉRENCE (lot « listes ») : les listes de libellés métier qui vivaient en constantes sont des réglages `texte` datés, lus par `ListesReference`.
// On prouve : (1) la liste d'attente reprend EXACTEMENT ce que le code disait ; (2) une version datée change la liste à partir de sa date, sans rien réécrire ; (3) une liste vide ou
// archivée retombe sur la liste d'attente, jamais sur « aucun choix » ; (4) les quatre copies des services sont devenues UNE liste.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> version(String cle, Object? valeur, String effet, {int v = 1, String? statut}) {
  final d = definitionDeParametre(cle)!;
  return {
    ...Parametre(cle: cle, famille: d.famille, type: d.type, valeur: valeur, defaut: d.defaut, dateEffet: effet, version: v, auteur: 'Test', motif: 'essai', creeLe: '2026-11-17T08:00:00.000').toJson(),
    if (statut != null) 'statut': statut,
  };
}

void main() {
  tearDown(ListesReference.debrancher);

  final listes = [for (final d in definitionsParametres) if (d.cle.startsWith('listes.')) d];

  test('chaque liste est un réglage texte d\'une famille « listes_* » libellée, avec une source, jamais vers un téléphone, sans doublon ni valeur vide', () {
    expect(listes.length, greaterThanOrEqualTo(40));
    for (final d in listes) {
      expect(d.type, TypeParametre.texte, reason: d.cle);
      expect(d.famille, startsWith('listes_'), reason: d.cle);
      expect(libellesFamillesParametres.containsKey(d.famille), isTrue, reason: d.famille);
      expect(d.source, isNotNull, reason: d.cle);
      expect(d.mobile, isFalse, reason: d.cle);
      final v = ListesReference.semence(d.cle);
      expect(v, isNotEmpty, reason: d.cle);
      expect(v.toSet().length, v.length, reason: '${d.cle} : doublon');
      expect(v.every((x) => x == x.trim() && x.isNotEmpty && !x.contains(';')), isTrue, reason: d.cle);
    }
  });

  test('la liste d\'attente reprend exactement ce que le code disait', () {
    expect(admNaturesCourrier, ['Lettre', 'Courriel', 'Note', 'Facture', 'Convocation', 'Rapport']);
    expect(admServicesCourrier.length, 7);
    expect(admServicesFiltreCourrier, admServicesCourrier.take(5).toList());
    expect(sangTypesDon, ['Bénévole', 'Familial', 'Compensation']);
    expect(assConventions, ['Signée', 'En cours de renouvellement', 'Suspendue']);
    expect(rhaNaturesContrat, ['CDI', 'CDD', 'Stage', 'Prestation']);
    expect(rhaPeriodesEssai, ['1 mois', '3 mois', '6 mois']);
    expect(rapFiligranes, ['Document officiel', 'Confidentiel', 'Brouillon']);
    expect(assNiveauxRelance, ['1re relance', '2e relance', 'Mise en demeure']);
  });

  test('les quatre copies de D.SERVICES sont UNE liste : RH, planning, comptes et paie lisent la même', () {
    expect(rhaServices, rhbServices);
    expect(rhaServices, secServices);
    expect(rhaServices, paiServices);
    expect(rhaServices, hasLength(10));
    expect(rhaServices.last, 'Comptabilité');
  });

  test('une version datée change la liste à partir de sa date seulement ; les fiches déjà saisies ne sont pas touchées', () {
    const cle = 'listes.m13.naturesCourrier';
    final fiches = [version(cle, 'Lettre; Courriel; Note; Facture; Convocation; Rapport; Assignation', '2026-12-01')];
    expect(ListesReference.valeursA(cle, fiches, '2026-11-30'), ListesReference.semence(cle));
    expect(ListesReference.valeursA(cle, fiches, '2026-12-01'), contains('Assignation'));
    ListesReference.brancher(() => fiches, horloge: () => DateTime(2026, 12, 15));
    expect(admNaturesCourrier, contains('Assignation'));
    ListesReference.brancher(() => fiches, horloge: () => DateTime(2026, 11, 15));
    expect(admNaturesCourrier, isNot(contains('Assignation')));
  });

  test('l\'ordre saisi est conservé ; blancs et doublons retirés', () {
    expect(ListesReference.decouper(' b ; a;; b ;c '), ['b', 'a', 'c']);
  });

  test('une liste vide, illisible ou archivée retombe sur la liste d\'attente, jamais sur aucun choix', () {
    const cle = 'listes.m13.lieuxReunion';
    expect(ListesReference.valeursA(cle, [version(cle, ' ; ', '2026-01-01')], '2026-11-17'), ListesReference.semence(cle));
    expect(ListesReference.valeursA(cle, [version(cle, 42, '2026-01-01')], '2026-11-17'), ListesReference.semence(cle));
    expect(ListesReference.valeursA(cle, [version(cle, 'Salle A', '2026-01-01', statut: 'archive')], '2026-11-17'), ListesReference.semence(cle));
    expect(ListesReference.valeursA(cle, [version(cle, 'Salle A', '2026-01-01')], '2026-11-17'), ['Salle A']);
  });

  test('une clé inconnue est une faute de programmation', () {
    expect(() => ListesReference.valeurs('listes.inconnue'), throwsArgumentError);
  });
}
