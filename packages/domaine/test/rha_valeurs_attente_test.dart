// Les valeurs d'attente du personnel et des vacataires : le marquage « provisoire » tombe quand la valeur change, et seulement alors.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  final agent = <String, Object?>{
    'matricule': 'm-001',
    'salaireBase': 250000,
    'salaireProvisoire': true,
    'dateEmbauche': '2026-08-01',
    'dateEmbaucheProvisoire': true,
  };

  test('modifier le salaire arrête le salaire, pas la date d\'embauche', () {
    final patch = rhaValeursArretees(agent, {...agent, 'salaireBase': 310000}, rhaAttentePersonnel);
    expect(patch, {'salaireProvisoire': false});
  });

  test('le salaire saisi en texte et égal à l\'ancien n\'arrête rien (la saisie du formulaire est du texte)', () {
    expect(rhaValeursArretees(agent, {...agent, 'salaireBase': '250000', 'dateEmbauche': '2026-08-01'}, rhaAttentePersonnel), isEmpty);
  });

  test('changer la date d\'embauche arrête la date ; changer les deux arrête les deux', () {
    expect(rhaValeursArretees(agent, {...agent, 'dateEmbauche': '2024-02-15'}, rhaAttentePersonnel), {'dateEmbaucheProvisoire': false});
    expect(rhaValeursArretees(agent, {...agent, 'salaireBase': 1, 'dateEmbauche': '2020-01-01'}, rhaAttentePersonnel),
        {'salaireProvisoire': false, 'dateEmbaucheProvisoire': false});
  });

  test('une valeur déjà arrêtée n\'est pas marquée de nouveau ; une création (pas d\'ancienne fiche) n\'arrête rien', () {
    expect(rhaValeursArretees({...agent, 'salaireProvisoire': false}, {...agent, 'salaireBase': 1}, rhaAttentePersonnel), isEmpty);
    expect(rhaValeursArretees(null, agent, rhaAttentePersonnel), isEmpty);
  });

  test('le marquage est lu tant que la valeur n\'est pas arrêtée', () {
    expect(rhaValeursEnAttente(agent, rhaAttentePersonnel), ['salaireBase', 'dateEmbauche']);
    expect(rhaValeursEnAttente({...agent, 'salaireProvisoire': false}, rhaAttentePersonnel), ['dateEmbauche']);
  });

  test('un vacataire : le tarif « à fournir » tombe à la saisie du tarif remis', () {
    final v = <String, Object?>{'nom': 'Cardiologue vacataire', 'tarifActe': 0, 'tarifAFournir': true};
    expect(rhaValeursArretees(v, {...v, 'tarifActe': '15000'}, rhaAttentePrestataire), {'tarifAFournir': false});
    expect(rhaValeursArretees(v, {...v, 'tarifActe': '0'}, rhaAttentePrestataire), isEmpty);
  });
}
