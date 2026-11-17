// RG-01, lot 0 (E3830) : sur le TÉLÉPHONE, le code d'un dossier ouvert à la réception de secours porte l'année de sa CRÉATION. La plage reçue à
// l'appairage appartient à une année : elle ne code que les dossiers de cette année-là ; un dossier d'une autre année (ou toute plage reçue avant le lot 0,
// sans année) reçoit un code provisoire, que la mère remplace par un code de la série de l'année de création. Le moteur est celui de l'application
// (`Mobile` de sigh_sync, appelé par `MoteurMobileSync.creerPatient` avec la même commande `POST /ecrire`).
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show codePatient;
import 'package:sigh_sync/src/mobile.dart';

void main() {
  Mobile telephone(Map<String, Object?> plage) => Mobile(ConfigMobile(port: 0, relais: 'http://127.0.0.1:1', dbChemin: ':memory:'))
    ..recevoir({'type': 'bienvenue', 'epoch': 1, 'plage': plage, 'profil': 'reception'});

  Future<String> ouvrir(Mobile t, Map<String, Object?> champs) async {
    final (statut, corps) = await t.commande('POST /ecrire', {'type': 'creer', 'collection': 'patients', 'champs': champs}, const {});
    expect(statut, 200);
    return '${((corps! as Map)['champs'] as Map)['code']}';
  }

  test('dossier du 31/12/2026 : rang de la plage 2026, en « /26 » ; dossier du 01/01/2027 : provisoire (la plage 2026 ne le code pas)', () async {
    final t = telephone({'debut': 1003, 'fin': 1022, 'annee': 2026});
    expect(await ouvrir(t, {'nom': 'VEILLE', 'dateCreation': '2026-12-31'}), codePatient(1003, 2026));
    expect(await ouvrir(t, {'nom': 'LENDEMAIN', 'dateCreation': '2027-01-01'}), startsWith('PROV-'));
    expect(await ouvrir(t, {'nom': 'VEILLE-BIS', 'dateCreation': '2026-12-31'}), codePatient(1004, 2026), reason: 'la plage n’a pas été consommée par le dossier de 2027');
    final (_, etat) = await t.commande('GET /etat', const {}, const {});
    expect(((etat! as Map)['plage'] as Map)['annee'], 2026);
  });

  test('sans date de création écrite (la réception de secours n’en écrit pas) : l’année est celle de l’horloge du téléphone au moment du geste', () async {
    final an = DateTime.now().year;
    expect(await ouvrir(telephone({'debut': 7, 'fin': 9, 'annee': an}), {'nom': 'X'}), codePatient(7, an));
    expect(await ouvrir(telephone({'debut': 7, 'fin': 9, 'annee': an - 1}), {'nom': 'Y'}), startsWith('PROV-'));
  });

  test('une plage reçue avant le lot 0 (sans année) ne code plus rien : provisoire, jamais une année devinée', () async {
    expect(await ouvrir(telephone({'debut': 1003, 'fin': 1022}), {'nom': 'Z'}), startsWith('PROV-'));
  });
}
