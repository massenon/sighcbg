// L'installeur Windows (Inno Setup) n'est pas exécutable ici : ce test GARDE qu'il lit le même fichier, le même en-tête, la même clé de date et les mêmes codes de refus que le domaine
// (`maj_regles.dart`). Une dérive entre le script Pascal et la règle Dart ferait bloquer l'installation à tort, ou la laisserait passer.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

void main() {
  final iss = File('installer/sigh_poste.iss').readAsStringSync();
  final texte = majTexteAutorisation(maintenant: DateTime(2026, 11, 17, 8, 5, 9), validiteHeures: 4, versionCourante: '1', schema: 1, levee: false);

  test('le script lit le fichier d’autorisation que le poste écrit, et son en-tête', () {
    expect(iss, contains(majFichierAutorisation));
    final entete = texte.split('\n').first;
    expect(entete, startsWith('SIGH-AUTORISATION-MAJ'));
    expect(iss, contains("'SIGH-AUTORISATION-MAJ'"));
    expect(iss, contains('Copy(Lignes[0], 1, ${'SIGH-AUTORISATION-MAJ'.length})'), reason: 'la longueur comparée est celle de l’en-tête');
  });

  test('il compare la date de validité au format AAAAMMJJHHMMSS (14 chiffres, heure locale) que le poste écrit', () {
    expect(iss, contains("'valable_jusqu_local'"));
    expect(iss, contains("GetDateTimeString('yyyymmddhhnnss'"));
    expect(iss, contains('Length(Jusqu) <> 14'));
    expect(RegExp(r'valable_jusqu_local=\d{14}').hasMatch(texte), isTrue);
    expect(texte, contains('valable_jusqu_local=20261117120509'));
  });

  test('il nomme les mêmes refus que le domaine et bloque une MISE À JOUR (données présentes), jamais une première installation', () {
    for (final r in [majLireAutorisation(null, DateTime(2026)), majLireAutorisation('x', DateTime(2026)), majLireAutorisation(texte, DateTime(2027))]) {
      expect(iss, contains("'${r!.code}'"), reason: r.code);
    }
    expect(iss, contains('function InitializeSetup(): Boolean;'));
    expect(iss, contains("DirExists(DossierDonnees() + '\\magasin')"));
    expect(iss, contains('if not DonneesPresentes() then'));
  });

  test('une autorisation vaut pour UNE mise à jour : l’installeur la retire une fois installé', () {
    expect(iss, contains('CurStep = ssPostInstall'));
    expect(iss, contains("DeleteFile(DossierDonnees() + '\\autorisation-mise-a-jour.txt')"));
  });

  test('le dossier des données lu par l’installeur est celui que le poste utilise (jamais le dossier du programme)', () {
    expect(iss, contains("{localappdata}\\SIGHCBG\\donnees"));
  });
}
