// La liasse déposée et le classeur 2025 sont des DONNÉES importées en base (`documents_fiscaux.dart`). Un test du domaine, sans magasin, les branche ici depuis les documents
// d'import de démonstration (la MÊME source que le jeu livré avec le poste : `apps/poste/tool/donnees/*_demo.json`).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

Map<String, Object?> _lire(String nom) => (jsonDecode(File('../../apps/poste/tool/donnees/$nom').readAsStringSync()) as Map).cast<String, Object?>();

/// Branche le registre sur la liasse et le classeur de démonstration (à appeler dans `setUpAll`).
void brancherDocumentsFiscauxDeTest() {
  final liasse = _lire('liasse_2025_demo.json');
  final classeur = _lire('classeur_2025_demo.json');
  final depot = (liasse['DEPOT'] as Map).cast<String, Object?>();
  final fiches = [
    docFiscalFiche(
        genre: docFiscalLiasse,
        exercice: depot['exerciceN'] as int,
        dateDepot: '${depot['dateDepot']}',
        source: '${depot['source']}',
        auteur: 'Test',
        importeLe: '2026-11-17',
        contenu: liasse),
    docFiscalFiche(
        genre: docFiscalClasseur,
        exercice: classeur['annee'] as int,
        dateDepot: '${depot['dateDepot']}',
        source: 'Classeur 2025 de démonstration',
        auteur: 'Test',
        importeLe: '2026-11-17',
        contenu: classeur),
  ];
  DocumentsFiscaux.brancher(() => fiches);
}

/// Le texte JSON du classeur de démonstration (pour un test qui le déforme avant de le relire).
String classeurDemoJson() => File('../../apps/poste/tool/donnees/classeur_2025_demo.json').readAsStringSync();
