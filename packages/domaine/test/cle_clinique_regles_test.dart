import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

final cle = List<int>.generate(32, (i) => (i * 7 + 3) % 256);
final hex = cle.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('lecture : hexadécimal (groupé ou non) et Base64', () {
    expect(cleLireTexte(hex), cle);
    expect(cleLireTexte(RegExp('.{4}').allMatches(hex).map((m) => m[0]).join(' - ')), cle);
    expect(cleLireTexte(base64.encode(cle)), cle);
    expect(cleLireTexte('trop court'), isNull);
    expect(cleLireTexte(hex.substring(2)), isNull);
  });
  test('l’empreinte est celle du SHA-256 de la clé, et la courte n’en révèle que le début', () {
    expect(cleEmpreinte(cle).length, 64);
    expect(cleEmpreinteManifeste(cle), cleEmpreinte(cle).substring(0, 16));
    expect(cleEmpreinteAffichee(cle), cleEmpreinte(cle).substring(0, 8).toUpperCase());
    expect(cleEmpreinte(cle).contains(hex), isFalse);
  });
  test('acceptée seulement si l’empreinte attendue est reproduite', () {
    final bonne = cleEmpreinte(cle).substring(0, 8);
    expect(cleControlerRestauration(octets: cle, empreinteAttendue: bonne), isNull);
    expect(cleControlerRestauration(octets: cle, empreinteAttendue: bonne.toUpperCase()), isNull);
    expect(cleControlerRestauration(octets: cle, empreinteAttendue: 'deadbeef')?.code, 'EMPREINTE_DIFFERENTE');
    expect(cleControlerRestauration(octets: cle, empreinteAttendue: '')?.code, 'EMPREINTE_ABSENTE');
    expect(cleControlerRestauration(octets: cle, empreinteAttendue: 'zz')?.code, 'EMPREINTE_ILLISIBLE');
    expect(cleControlerRestauration(octets: null, empreinteAttendue: bonne)?.code, 'CLE_ILLISIBLE');
  });
  test('une autre clé en service n’est remplacée que sur confirmation', () {
    final bonne = cleEmpreinte(cle).substring(0, 8);
    final autre = cleEmpreinte(List.filled(32, 9));
    expect(cleControlerRestauration(octets: cle, empreinteAttendue: bonne, empreinteEnService: autre)?.code, 'CLE_EN_SERVICE_DIFFERENTE');
    expect(cleControlerRestauration(octets: cle, empreinteAttendue: bonne, empreinteEnService: autre, remplacer: true), isNull);
    expect(cleControlerRestauration(octets: cle, empreinteAttendue: bonne, empreinteEnService: cleEmpreinte(cle)), isNull);
  });
  test('un refus ne cite jamais la clé', () {
    final r = cleControlerRestauration(octets: cle, empreinteAttendue: 'deadbeef')!;
    expect('${r.motif} ${r.geste}'.contains(hex), isFalse);
    expect('${r.motif} ${r.geste}'.contains(base64.encode(cle)), isFalse);
  });
}
