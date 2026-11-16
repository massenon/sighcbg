// Les motifs d'identité de la clinique sœur, pour les GARDES des tests (« aucune trace de la clinique sœur à l'écran ou sur la pièce »).
//
// La liste n'est PAS recopiée ici : elle est lue dans `tools/baguidi/neutraliser-identite.mjs` (ligne `export const MOTIFS = [...]`), seul fichier du dépôt à
// porter ces motifs en clair, et la même que celle du contrôle d'identité (`tools/baguidi/controle-identite.mjs`). Une garde qui recopierait la liste
// porterait elle-même la trace qu'elle interdit, et divergerait de la liste du contrôle au premier motif ajouté.
import 'dart:io';

List<String>? _motifs;

/// Les motifs d'origine (sous-chaînes, sensibles à la casse). Les tests du poste tournent depuis `apps/poste`.
List<String> motifsOrigine() => _motifs ??= () {
      final f = File('../../tools/baguidi/neutraliser-identite.mjs');
      final ligne = f.readAsLinesSync().firstWhere((l) => l.startsWith('export const MOTIFS = ['));
      final m = [for (final x in RegExp(r"'([^']*)'").allMatches(ligne)) x.group(1)!];
      if (m.length < 10) throw StateError('liste MOTIFS illisible dans ${f.path}');
      return List<String>.unmodifiable(m);
    }();

/// Le premier motif d'origine présent dans [texte], ou `null`.
String? traceOrigine(String texte) {
  for (final m in motifsOrigine()) {
    if (texte.contains(m)) return m;
  }
  return null;
}
