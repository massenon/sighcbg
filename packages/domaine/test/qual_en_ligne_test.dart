// SATISFACTION EN LIGNE (décision du 16/11/2026, section 8) : ce que la mère publie au relais pour un lien, et ce qu'elle retient d'une réponse déchiffrée.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  final enquete = <String, Object?>{
    'id': 'ENQ00001',
    'reference': 'ENQ-SAT',
    'titre': 'Votre avis compte',
    'description': 'Quelques questions sur votre passage.',
    'questions': [
      {'code': 'Q_ACCUEIL', 'libelle': 'Qualité de l’accueil', 'type': 'note'},
      {'code': 'Q_RECO', 'libelle': 'Recommanderiez-vous la clinique ?', 'type': 'choix', 'options': ['Oui', 'Plutôt oui', 'Non']},
      {'code': 'Q_COM', 'libelle': 'Un commentaire ?', 'type': 'texte'},
    ],
  };
  final jeton = {
    ...qualNouveauJetonEnLigne(
        enquete: enquete, jeton: 'abcdefghijkmnpqrstuvwxyz', expireLe: '2026-12-16', aujourdhui: DateTime(2026, 11, 16), ouvertPar: 'Compte d’essai'),
    'id': 'JET00001',
  };

  test('un lien en ligne est toujours anonyme, marqué en ligne, usage « relais »', () {
    expect(jeton['anonyme'], isTrue);
    expect(jeton['enLigne'], isTrue);
    expect(jeton['usage'], qualUsageRelais);
    expect(qualLienEnLigne(jeton), isTrue);
    expect(qualRefusPublication(jeton, enquete), isNull);
    expect(qualRefusPublication({...jeton, 'anonyme': false}, enquete)?.code, 'LIEN_NOMINATIF');
    expect(qualRefusPublication(jeton, null)?.code, 'ENQUETE_INCONNUE');
    expect(qualRefusPublication(jeton, {...enquete, 'questions': []})?.code, 'ENQUETE_SANS_QUESTION');
  });

  test('la publication porte les champs du GÉNÉRATEUR, jamais l’identifiant de l’enquête ; une question ajoutée y paraît', () {
    final p = qualPublicationEnLigne(
        jeton: jeton, enquete: enquete, jetonHash: 'h' * 64, clinique: 'Clinique', clePublique: 'k' * 43, kid: '0123456789abcdef');
    final champs = (p['champs'] as List).cast<Map>();
    final attendus = qualChampsDepuisModele(enquete['questions'], pleineLargeur: true);
    expect(champs.map((c) => c['nom']), attendus.map((c) => c.nom));
    expect(champs.map((c) => c['libelle']), attendus.map((c) => c.libelle));
    expect(champs.first['options'], ['1', '2', '3', '4', '5']);
    expect(p['ref'], 'JET00001');
    expect(p.toString().contains('ENQ00001'), isFalse, reason: 'l’identifiant de l’enquête ne part pas');
    expect(p.containsKey('jeton'), isFalse, reason: 'le jeton ne part que haché');
    final plus = {
      ...enquete,
      'questions': [
        ...(enquete['questions'] as List),
        {'code': 'Q_PROPRE', 'libelle': 'Propreté des locaux', 'type': 'note'}
      ]
    };
    final p2 = qualPublicationEnLigne(jeton: jeton, enquete: plus, jetonHash: 'h' * 64, clinique: 'C', clePublique: 'k' * 43, kid: '0123456789abcdef');
    expect((p2['champs'] as List).map((c) => (c as Map)['libelle']), contains('Propreté des locaux (1 à 5)'));
  });

  test('la réponse retenue : codes du modèle seulement, valeurs contrôlées, canal « Lien public », anonyme, date du relais', () {
    final r = qualReponseEnLigne(
        enquete: enquete,
        jeton: jeton,
        reponses: {'Q_ACCUEIL': '4', 'Q_RECO': 'Oui', 'Q_COM': '  Très bien.  ', 'Q_INCONNUE': 'x', 'nom': 'Quelqu’un'},
        recueLe: '2026-11-17')!;
    expect(r['canal'], qualCanalPublic);
    expect(r['date'], '2026-11-17');
    expect(r['jetonId'], 'JET00001');
    expect(r['enqueteId'], 'ENQ00001');
    expect(r['saisiPar'], qualSaisiPar(anonyme: true));
    expect(r['reponses'], {'Q_ACCUEIL': 4, 'Q_RECO': 'Oui', 'Q_COM': 'Très bien.'});
    // Une note hors bornes et un choix hors liste sont écartés ; sans rien de valable, aucune réponse.
    final r2 = qualReponseEnLigne(enquete: enquete, jeton: jeton, reponses: {'Q_ACCUEIL': '9', 'Q_RECO': 'Peut-être'}, recueLe: '2026-11-17');
    expect(r2, isNull);
    // Les statistiques la comptent comme toute réponse.
    final s = qualSatisfaction(enquete, [r]);
    expect(s.reponses, 1);
    expect(s.notes.first.moyenne, 4);
    expect(s.recommandent, 1);
  });

  test('l’état de publication se lit sur la fiche écrite par la mère', () {
    expect(qualEtatPublication(jeton).libelle, 'En attente du poste mère');
    expect(qualEtatPublication({...jeton, 'lienPublic': 'https://relais/satisfaction/x'}).ton, 'success');
    expect(qualEtatPublication({...jeton, 'erreurRelais': 'publication_invalide'}).ton, 'danger');
    expect(qualEtatPublication({...jeton, 'enLigne': null}).libelle, 'Lien interne');
  });
}
