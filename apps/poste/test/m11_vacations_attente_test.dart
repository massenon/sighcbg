import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'package:sigh_poste/modules/m11/pai_commun.dart' show entreesPaie;

import 'aide_polices.dart';
import 'm11_aide.dart';

/// RG-11 / E4027 : une vacation « à valider » (posée par un fileul, pas encore appliquée par la mère) n'entre ni en prime ni en honoraire ; l'écran de paie et le bulletin
/// le DISENT (« N vacation(s) en attente de validation ne sont pas payées »). Le même jeu avec et sans champ d'état donne les mêmes montants.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  const phrase = '1 vacation(s) en attente de validation ne sont pas payées';
  Map<String, Object?> garde(String employeId, {String? etat}) =>
      {'employeId': employeId, 'date': '2026-10-12', 'type': 'garde', 'statut': 'actif', if (etat != null) 'validationEtat': etat};

  String premierAgent(Magasin m) => '${m.collection('personnel').actives.firstWhere((e) => e['salaireBase'] != null)['id']}';

  test('non-régression : le planning d\'origine (sans état) et le même planning « validee » donnent la même paie ; « a_valider » ne s\'ajoute pas', () {
    final m = magasin();
    final id = premierAgent(m);
    final agent = m.collection('personnel').actives.firstWhere((e) => e['id'] == id);
    PaiCalcul calcul() => paiCalculer(agent, 2026, 9, entreesPaie(m), aujourdhui);
    final avant = calcul();
    final posee = m.collection('planning').inserer(garde(id, etat: vacationEtatAValider), prefixe: 'PLN').fiche;
    final attente = calcul();
    expect([attente.brut, attente.net, attente.gardes], [avant.brut, avant.net, avant.gardes], reason: 'à valider : rien ne s\'ajoute');
    expect(attente.avertissementVacations, phrase);
    m.collection('planning').mettreAJour(posee['id'], {'validationEtat': vacationEtatValidee});
    final validee = calcul();
    expect(validee.gardes, avant.gardes + 1, reason: 'validée par la mère : payable au calcul suivant');
    expect(validee.avertissementVacations, isNull);
  });

  cas('l\'écran de calcul NOMME l\'agent et la phrase ; sans vacation en attente, aucun avertissement', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'm11-calcul');
    expect(textes(t).where((x) => x.contains('en attente de validation ne sont pas payées')), isEmpty);
    final id = premierAgent(m);
    final nom = '${m.collection('personnel').actives.firstWhere((e) => e['id'] == id)['nomComplet']}';
    m.collection('planning').inserer(garde(id, etat: vacationEtatAValider), prefixe: 'PLN');
    await ouvrir(t, m, 'm11-calcul');
    expect(textes(t).where((x) => x.contains(phrase) && x.contains(nom)), isNotEmpty);
  });

  cas('l\'écran de validation lit l\'instantané du bulletin ; le registre des vacations dit « À valider » et ne compte pas la ligne', (t) async {
    final m = magasin();
    poserBulletins(m);
    final b = m.collection('bulletins').actives.firstWhere((b) => b['statutBulletin'] == 'a_valider');
    m.collection('bulletins').mettreAJour(b['id'], {
      'vacationsEnAttente': [
        {'id': 'PLN-X', 'date': '2026-10-12', 'type': 'garde'}
      ]
    });
    await ouvrir(t, m, 'm11-validation');
    expect(textes(t).where((x) => x.contains(phrase) && x.contains('${b['employe']}')), isNotEmpty);
  });
}
