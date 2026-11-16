import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// « Les codes à 0 » (Direction, 16/11/2026) : le relevé classe par cause ; aucune voie ne valorise un prix à la place de la Direction.
void main() {
  Map<String, Object?> p(String code, {Object? variantes, Object? distinctDe}) =>
      {'id': code, 'code': code, 'libelle': code, 'famille': 'ACTE', 'statut': 'actif', 'codeActe': code, if (variantes != null) 'variantesGrille': variantes, if (distinctDe != null) 'distinctDe': distinctDe};
  Map<String, Object?> v(String code, String statut, {String? date = '2026-01-01', Object? na = 1000, int rang = 1}) =>
      {'id': '$code@$rang', 'code': code, 'version': rang, 'dateEffet': date, 'prixNonAssure': na, 'etatAssure': 'unique', 'statut': statut};

  test('le relevé classe chaque code sans prix par sa cause', () {
    final h = ReferentielTarifs([
      p('OK'),
      p('JAMAIS'),
      p('VAR', variantes: ['A', 'B']),
      p('PROP'),
      p('FUTUR'),
      p('REFUSE'),
      p('NOUVEAU', distinctDe: 'OK'),
    ], [
      v('OK', 'valide'),
      v('PROP', 'propose'),
      v('FUTUR', 'valide', date: '2027-01-01'),
      v('REFUSE', 'refuse'),
      v('NOUVEAU', 'propose'),
    ]);
    final r = tarMesurerSansPrix(h, '2026-11-16', codesDeListes: {'actes': ['OK', 'ORPHELIN']});
    expect(r.parCause['jamais_tarife'], ['JAMAIS']);
    expect(r.parCause['variante'], ['VAR']);
    expect(r.parCause['non_valide'], ['PROP']);
    expect(r.parCause['a_venir'], ['FUTUR']);
    expect(r.parCause['refuse'], ['REFUSE']);
    expect(r.parCause['distincte'], ['NOUVEAU']);
    expect(r.parCause['hors_referentiel'], ['actes:ORPHELIN']);
    expect(r.prestations, 7);
    expect(r.sansPrix, 7, reason: 'six prestations sans prix et un code orphelin ; OK est tarifé');
    expect(tarCauseSansPrix(h, h.parCode['OK']!, '2026-11-16'), isNull);
  });

  test('la caisse manuelle refuse un prix nul ou absent en disant « prix à définir »', () {
    expect(refusPrixADefinir('Pansement', 0)!.code, 'PRIX_A_DEFINIR');
    expect(refusPrixADefinir('Pansement', null)!.code, 'PRIX_A_DEFINIR');
    expect(refusPrixADefinir('Pansement', '')!.code, 'PRIX_A_DEFINIR');
    expect(refusPrixADefinir('Pansement', '9000'), isNull);
    expect(refusPrixADefinir('Pansement', 9000), isNull);
  });

  test('un examen sans prix refuse la demande du patient externe en le nommant, sans rien écrire', () {
    expect(
        () => patOuvrirDemandeExterne(
            saisie: {'nom': 'A', 'prenom': 'B'},
            codesAnalyses: ['X1'],
            catalogue: [
              {'code': 'X1', 'designation': 'Examen sans prix', 'prix': null}
            ],
            patients: [],
            demandesExistantes: [],
            nbFactures: 0,
            nouvelId: (q) => q,
            date: DateTime(2026, 11, 16)),
        throwsA(isA<PatRefus>().having((e) => e.message, 'message', allOf(contains('prix à définir'), contains('Examen sans prix')))));
  });
}
