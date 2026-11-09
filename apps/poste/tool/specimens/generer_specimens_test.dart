import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/impression/apercu.dart';

import '../../test/aide_polices.dart';
import 'directs.dart';
import 'explorateur.dart';
import 'noms.dart';

/// GÉNÉRATEUR DES SPÉCIMENS D'IMPRESSION (dossier `presentation/` à la racine du dépôt).
///
/// Ne tourne QUE sur demande : `SIGH_SPECIMENS=1 flutter test tool/specimens/generer_specimens_test.dart` (depuis `apps/poste`). Sans la variable, tous les cas
/// sont ignorés (la suite normale ne le lance pas). Variables : `SIGH_SPECIMENS_SORTIE` (dossier de sortie, défaut `../../presentation`),
/// `SIGH_SPECIMENS_ECRANS` (préfixes d'écrans séparés par des virgules : ne rejouer qu'une partie ; `-` : aucun écran) et
/// `SIGH_SPECIMENS_RECETTES` (préfixes d'identifiants de pièces produites par fabrique, voir `directs.dart`).
///
/// Deux voies, qui se complètent : (1) l'EXPLORATEUR ouvre chaque écran sous un rôle qui y a droit, sur le jeu de démonstration livré, déclenche les
/// commandes d'édition (vue, première lignes, onglets) et capture le PDF par le crochet [ImpressionPoste.enregistrer] ; (2) les pièces que ce balayage
/// n'atteint pas sont produites par leur fabrique, avec des données du jeu (`directs.dart`). Le résultat est un tableau de couverture complet.
final bool actif = Platform.environment['SIGH_SPECIMENS'] == '1';
final String sortie = Platform.environment['SIGH_SPECIMENS_SORTIE'] ?? '../../presentation';
final List<String> filtre = (Platform.environment['SIGH_SPECIMENS_ECRANS'] ?? '').split(',').where((s) => s.isNotEmpty).toList();
final List<String> filtreRecettes = (Platform.environment['SIGH_SPECIMENS_RECETTES'] ?? '').split(',').where((s) => s.isNotEmpty).toList();

void main() {
  final tous = <Capture>[];
  final notes = <String>[];
  final ecransParcourus = <String, String>{};
  late DonneesNavigation donnees;
  final horloge = DateTime(2026, 11, 7, 12);

  setUpAll(() async {
    if (!actif) return;
    await chargerPolices();
    donnees = DonneesNavigation.depuisDossier();
  });

  final ids = actif
      ? ecransAExplorer(DonneesNavigation.depuisDossier(), magasinLivre())
      : <String>[];

  testWidgets('balayage des écrans', skip: !actif, timeout: const Timeout(Duration(hours: 3)), (t) async {
    final ex = Explorateur(t, donnees, () => horloge);
    ex.brancher();
    for (final id in ids) {
      if (filtre.isNotEmpty && !filtre.any((f) => f != '-' && id.startsWith(f))) continue;
      final m = magasinLivre();
      final nav = donnees.aChaud(m);
      final role = roleDe(nav, id);
      ecransParcourus[id] = role;
      final avant = ex.captures.length;
      try {
        await ex.ouvrir(id, role, m);
        await ex.explorer();
      } catch (e) {
        ex.notes.add('$id : $e');
      }
      stdout.writeln('ECRAN $id ($role) : ${ex.captures.length - avant} PDF');
    }
    tous.addAll(ex.captures);
    notes.addAll(ex.notes);
  });

  testWidgets('pièces produites directement', skip: !actif, timeout: const Timeout(Duration(hours: 1)), (t) async {
    final m = magasinLivre();
    final d = await produireDirects(t, donnees, m, horloge, (id) => filtreRecettes.isEmpty || filtreRecettes.any(id.startsWith));
    tous.addAll(d.$1);
    notes.addAll(d.$2);
  });

  testWidgets('écriture du dossier', skip: !actif, (t) async {
    await ecrireDossier(sortie, donnees, tous, notes, ecransParcourus);
  });
}
