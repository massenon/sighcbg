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

  group('création et confirmation (Direction, 16/11/2026)', () {
    final vide = <String, Object?>{'matricule': 'm-100', 'nom': 'X', 'salaireBase': 90000, 'dateEmbauche': '2026-11-02', 'categorie': '', 'cnss': ''};

    test('à la création, une catégorie ou un numéro CNSS VIDES sont marqués « à renseigner » ; renseignés, ils ne le sont pas', () {
      expect(rhaMarquerVides(vide, rhaAttentePersonnel), {'categorieProvisoire': true, 'cnssProvisoire': true});
      expect(rhaMarquerVides({...vide, 'categorie': 'E1-1', 'cnss': '123'}, rhaAttentePersonnel), isEmpty);
    });

    test('saisir la valeur remise arrête l\'attente d\'un champ marqué vide', () {
      final marque = {...vide, 'categorieProvisoire': true, 'cnssProvisoire': true};
      expect(rhaValeursArretees(marque, {...marque, 'categorie': 'E3-1'}, rhaAttentePersonnel), {'categorieProvisoire': false});
    });

    final agent = <String, Object?>{'matricule': 'm-001', 'salaireBase': 250000, 'salaireProvisoire': true, 'categorie': '', 'categorieProvisoire': true};

    test('confirmer exige le motif (refus nommé sinon), le geste réservé, une valeur non vide et une attente réelle', () {
      Map<String, Object?> c(String champ, {String motif = 'Salaire retenu par la Direction', String role = 'da', RhaFiche? a}) =>
          rhaConfirmerValeur(agent: a ?? agent, champ: champ, motif: motif, role: role, auteur: 'DAF', jour: '2026-11-16');
      expect(c('salaireBase', motif: '  ')['code'], 'MOTIF_OBLIGATOIRE');
      expect(c('salaireBase', role: 'caissier')['code'], 'GESTE_RESERVE');
      expect(c('salaireBase', role: 'caissier')['geste'], gesteRhConfirmerValeur);
      expect(c('categorie')['code'], 'VALEUR_VIDE', reason: 'une valeur absente se saisit, elle ne se confirme pas');
      expect(c('dateEmbauche')['code'], 'DEJA_ARRETEE');
      expect(c('telephone')['code'], 'CHAMP_SANS_ATTENTE');
      final ok = c('salaireBase');
      expect(ok['ok'], true);
      final patch = ok['patch'] as Map<String, Object?>;
      expect(patch['salaireProvisoire'], false);
      expect((patch['confirmationsValeurs'] as List).single, {'champ': 'salaireBase', 'motif': 'Salaire retenu par la Direction', 'par': 'DAF', 'le': '2026-11-16'});
    });

    test('le geste est réservé à la DAF, la Direction et l\'administrateur à l\'origine', () {
      final g = gesteReserve(gesteRhConfirmerValeur)!;
      expect([...g.rolesDefaut]..sort(), ['admin', 'da', 'direction']);
    });

    test('la paie nomme les agents à valeur d\'attente du lot ; le bulletin porte les libellés ; un lot sans attente ne dit rien', () {
      final b1 = <String, Object?>{'matricule': 'm-001', 'employe': 'BAGUIDI Rafiou', 'valeursAttente': ['salaire de base', 'numéro CNSS']};
      final b2 = <String, Object?>{'matricule': 'm-002', 'employe': 'ANCIEN Format', 'salaireProvisoire': true};
      final b3 = <String, Object?>{'matricule': 'm-003', 'employe': 'SANS Attente'};
      final s = paiSignalementValeursAttente([b1, b2, b3])!;
      expect(s, allOf(contains('2 agent(s)'), contains('BAGUIDI Rafiou (salaire de base, numéro CNSS)'), contains('ANCIEN Format (salaire de base)')));
      expect(s, isNot(contains('SANS Attente')));
      expect(paiSignalementValeursAttente([b3]), isNull);
      expect(rhaLibellesEnAttente(agent), ['salaire de base', 'catégorie / échelon']);
    });
  });
}
