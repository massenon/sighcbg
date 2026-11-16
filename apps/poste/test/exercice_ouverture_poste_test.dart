import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/modules/m12/cpc_commun.dart';

/// Q29 (Direction, 16/11/2026) : l'exercice suivant s'ouvre en décembre, réglable. Le poste porte la notion d'exercice (ouvert, en clôture, clos) : le réglage est un réglage de CLINIQUE (`reglages`),
/// semé à décembre à la première lecture, journalisé quand on le change, refusé en le disant quand il est invalide.
Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

void main() {
  test('décembre par défaut ; en novembre, pas d’exercice suivant ; en décembre, l’exercice 2027 est ouvert ; rejoué, rien ne se double', () {
    final m = jeu();
    expect(moisOuvertureSuivantDe(m), 12, reason: 'décembre tant que personne n’a réglé autre chose');
    amorcerExercices(m, DateTime(2026, 11, 16));
    expect(m.collection('reglages').parId(cpcCleMoisOuvertureSuivant), isNull, reason: 'rien n’est écrit à la lecture (pas d’insertion pendant un rendu)');
    expect(cpcExercice(m.collection('exercices').toutes, 2027), isNull, reason: 'novembre : trop tôt');
    amorcerExercices(m, DateTime(2026, 12, 1));
    expect(cpcEtatExercice(m.collection('exercices').toutes, 2027), 'ouvert');
    final n = m.collection('exercices').toutes.length;
    amorcerExercices(m, DateTime(2026, 12, 2));
    expect(m.collection('exercices').toutes.length, n, reason: 'rejoué, rien ne se double');
    expect(cpcEtatExercice(m.collection('exercices').toutes, 2026), isNot('clos'), reason: 'l’exercice en cours n’est pas touché');
  });

  test('réglable : novembre ouvre 2027 dès novembre ; un mois invalide est refusé en le disant ; le changement est journalisé', () {
    final m = jeu();
    expect(definirMoisOuvertureSuivant(m, 13, auteur: 'DAF'), isNotNull);
    expect(moisOuvertureSuivantDe(m), 12, reason: 'un refus ne change rien');
    expect(definirMoisOuvertureSuivant(m, 11, auteur: 'DAF'), isNull);
    expect(moisOuvertureSuivantDe(m), 11);
    amorcerExercices(m, DateTime(2026, 11, 16));
    expect(cpcEtatExercice(m.collection('exercices').toutes, 2027), 'ouvert');
    expect(m.collection('audit').toutes.any((x) => '${x['action']}'.contains('ouverture de l’exercice suivant')), isTrue);
  });
}
