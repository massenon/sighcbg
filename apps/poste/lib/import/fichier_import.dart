import 'dart:convert';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'classeur_xlsx.dart';
import 'selecteurs_import.dart';

/// Le contenu du classeur-modèle d'un jeu : Données, Instructions, Listes (les mêmes que celui de la maquette). [colonnesAccordees] : les colonnes
/// réservées que le profil a le droit d'importer — sans elles, le modèle du profil ne les porte pas.
Uint8List classeurModele(JeuImport j, PortImport port, {Set<String> colonnesAccordees = const {}}) {
  final m = modeleImport(j, port, colonnesAccordees: colonnesAccordees);
  final cols = j.colonnesPour(colonnesAccordees);
  return ecrireClasseur([
    FeuilleXlsx('Données', m.donnees,
        largeurs: [for (final c in cols) c.label.length + 4 < 14 ? 14.0 : c.label.length + 4.0], validations: m.validations, colonnesTexte: m.colonnesTexte),
    FeuilleXlsx('Instructions', m.instructions, entete: false, largeurs: const [28, 12, 28, 46, 22, 70]),
    FeuilleXlsx('Listes', m.listes, largeurs: [for (var i = 0; i < m.listes.first.length; i++) 30.0]),
  ]);
}

/// Le classeur du rapport d'erreurs d'un lot ou d'une analyse : la feuille « Erreurs » puis le « Résumé ».
Uint8List classeurRapport(String jeuLibelle, String fichier, String lot, int nbLignes, List<Map<String, Object?>> problemes) =>
    ecrireClasseur([
      FeuilleXlsx('Erreurs', rapportImport(problemes), largeurs: const [8, 26, 24, 14, 24, 70, 70]),
      FeuilleXlsx('Résumé', resumeRapportImport(jeuLibelle, fichier, lot, nbLignes, problemes.length), entete: false, largeurs: const [24, 50]),
    ]);

/// Lit un fichier choisi en lignes : .csv (UTF-8, séparateur détecté) ou classeur .xlsx (feuille « Données », à défaut la première). `null` + motif quand
/// le fichier est illisible.
({List<List<Object?>>? lignes, String? motif}) lireFichierImport(FichierChoisi f) {
  try {
    if (RegExp(r'\.(csv|txt)$', caseSensitive: false).hasMatch(f.nom)) {
      return (lignes: [for (final l in importLireCsv(utf8.decode(f.octets, allowMalformed: true))) List<Object?>.of(l)], motif: null);
    }
    final feuilles = lireClasseur(f.octets);
    if (feuilles.isEmpty) throw const FormatException('le classeur ne contient aucune feuille');
    final donnees = feuilles.where((x) => normaliser(x.nom) == normaliser('Données')).firstOrNull ?? feuilles.first;
    return (lignes: donnees.lignes, motif: null);
  } on FormatException catch (e) {
    return (lignes: null, motif: e.message);
  } catch (e) {
    return (lignes: null, motif: '$e');
  }
}
