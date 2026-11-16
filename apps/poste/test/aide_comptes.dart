import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';

/// SECTION AI (16/11/2026) : la mère VÉRIFIE le compte inscrit sur une décision déposée (il existe dans ses `utilisateurs`, porte ce rôle, n'est pas archivé). Un test qui fait
/// déposer un fileul doit donc lui donner un agent NOMINATIF dont le compte existe à la mère : [signerAvec] prend le premier compte actif du rôle dans les comptes de [mere], ou en
/// crée un (compte de test, sans secret) quand le jeu n'en porte pas pour ce rôle, puis le pose comme acteur de [fileul].
Agent compteDuRole(Magasin mere, String role, {String? nom}) {
  final comptes = mere.collection('utilisateurs');
  var u = comptes.actives.where((x) => x['role'] == role && x['actif'] != false).firstOrNull;
  if (u == null) {
    final id = 'USR-TEST-$role';
    comptes.ajouterSansJournal({'id': id, 'statut': 'actif', 'identifiant': '$role@test.local', 'nomComplet': nom ?? 'Compte de test ($role)', 'role': role, 'actif': true});
    u = comptes.parId(id)!;
  }
  return Agent(utilisateurId: '${u['id']}', nom: nom ?? '${u['nomComplet'] ?? role}', role: role);
}

/// Pose sur [fileul] l'agent nominatif du rôle [role], dont le compte existe à [mere] (voir [compteDuRole]). Rend l'agent.
Agent signerAvec(Magasin fileul, Magasin mere, String role, {String? nom}) {
  final a = compteDuRole(mere, role, nom: nom);
  fileul.poserActeur(a);
  return a;
}
