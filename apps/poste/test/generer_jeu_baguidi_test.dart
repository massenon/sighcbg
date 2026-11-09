// Le générateur du jeu de démonstration Baguidi : déterminisme (octet pour octet), conservation des 154 fichiers, aucun champ nul, contenu du socle et des
// personnes (J3 à J9). Lance le générateur EN MÉMOIRE ; compare aussi le jeu livré (`assets/donnees/jeu`) à ce que le générateur produit.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/generer_jeu_baguidi.dart';

List<Map<String, Object?>> lire(Map<String, String> j, String nom) =>
    [for (final f in jsonDecode(j['$nom.json']!) as List) (f as Map).cast<String, Object?>()];

void main() {
  final a = construireJeu();
  final b = construireJeu();

  test('deux exécutions donnent les mêmes octets', () {
    expect(a.keys.toList(), b.keys.toList());
    for (final k in a.keys) {
      expect(a[k], b[k], reason: k);
    }
  });

  test('le jeu livré est celui que produit le générateur, avec les 154 noms de fichier de la référence', () {
    final reference = Directory('test/fixtures/jeu_reference').listSync().map((f) => f.uri.pathSegments.last).toSet();
    expect(reference.length, 154);
    expect(a.keys.toSet(), reference);
    for (final e in a.entries) {
      expect(File('assets/donnees/jeu/${e.key}').readAsStringSync(), e.value, reason: '${e.key} : relancer flutter test tool/generer_jeu_baguidi.dart');
    }
  });

  test('aucun champ nul n\'est écrit, une collection vide s\'écrit []', () {
    for (final e in a.entries) {
      expect(RegExp(r'":null').hasMatch(e.value), isFalse, reason: e.key);
    }
    expect(a['audit.json'], '[]\n');
  });

  test('les neuf personnes réelles, leurs comptes sans secret, les vacataires fictifs', () {
    final p = lire(a, 'personnel');
    expect(p.map((x) => x['nomComplet']), [
      'BAGUIDI Rafiou', 'SANOUSSI Adamon', 'MABOUDOU Nawal', 'IDOHOU Abraham', 'AKONDE Octave', 'SOKOU Peace', 'ZIME Nadège', 'TOUNGOUH A. Zoulkifouli'
    ]);
    expect(p.every((x) => x['cnss'] == '' && x['telephone'] == '' && x['salaireProvisoire'] == true), isTrue);
    final u = lire(a, 'utilisateurs');
    expect(u.length, 9);
    expect(u.first['identifiant'], 'admin@baguidi-clinique.bj');
    expect(u.every((x) => x['statut'] == 'actif' && x['motDePasseADefinir'] == true), isTrue);
    expect(u.map((x) => x['role']).toSet(), {'admin', 'direction', 'comptable', 'rh', 'medecin', 'infirmier'});
    for (final k in ['hash', 'sel', 'motDePasse', 'empreinte']) {
      expect(u.any((x) => x.containsKey(k)), isFalse, reason: k);
    }
    expect(a.containsKey('identifiants.json'), isFalse);
    final v = lire(a, 'prestataires');
    expect(v.length, 12);
    expect(v.every((x) => x['telephone'] == '' && '${x['nom']}'.contains('fictif de démonstration')), isTrue);
  });

  test('plan comptable révisé complet et sous-comptes SIGH rattachés à leur parent', () {
    final c = lire(a, 'comptes');
    expect(c.where((x) => x['source'] == 'SYSCOHADA révisé').length, 1332);
    final caisse = c.firstWhere((x) => x['num'] == '571000');
    expect([caisse['source'], caisse['parent']], ['SIGH', '571']);
    expect(c.map((x) => x['num']).toSet().length, c.length);
  });

  test('tarifs : tous provisoires, aucun arrêté d\'origine, cinq actes de médecine du travail', () {
    final actes = lire(a, 'actes');
    expect(actes.every((x) => x['tarifProvisoire'] == true), isTrue);
    expect(a['actes.json']!.contains('arrêté par la Direction'), isFalse);
    expect(actes.where((x) => x['secteur'] == 'Médecine du travail').map((x) => x['prixNonAssure']), [10000, 8000, 8000, 5000, 5000]);
    expect(lire(a, 'catalogueTarifs').every((x) => x['tarifProvisoire'] == true || x['famille'] == null), isTrue);
  });

  test('assureurs, entreprises fictives, calendrier fiscal', () {
    final ass = lire(a, 'assureurs');
    expect(ass.length, 13);
    expect(ass.where((x) => x['convention'] == 'Signée').length, 3);
    final s = lire(a, 'souscripteurs');
    expect(s.map((x) => x['nom']), [
      'Société Cotonnière du Borgou', 'Huilerie de Parakou', 'Transports Okpara', 'Brasserie des Collines', 'BTP Alafia', 'Imprimerie Gurma'
    ]);
    expect(s.every((x) => x['fictif'] == true && x['periodiciteFacturation'] == 'mensuelle'), isTrue);
    expect(lire(a, 'obligationsFiscales').firstWhere((x) => x['code'] == 'CNSS')['jour'], 15);
    expect(lire(a, 'secteurs').length, 6);
  });
}
