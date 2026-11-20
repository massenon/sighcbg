// LE COMPTE QUI SIGNE UNE DÉCISION DÉPOSÉE (section AI, Direction du 16/11/2026).
//
// Une décision prise sur un fileul (validation d'un référentiel ou d'un circuit d'achat, demande de prix, demande d'import) voyage jusqu'à la mère, qui la REJOUE sous le rôle et le
// nom de son auteur. Jusqu'ici la mère croyait le rôle que le poste déclarait. Désormais elle VÉRIFIE, avant de rejouer, que le COMPTE inscrit sur la décision existe dans les comptes
// de la clinique (collection `utilisateurs`, que la mère seule écrit), qu'il porte CE rôle et qu'il n'est pas archivé. Sinon : refus NOMMÉ, code stable, rendu au fileul sur la même
// fiche (rien n'est appliqué). Une décision qui ne porte AUCUN compte (session non nominative, poste d'avant la règle) est refusée elle aussi : omettre le champ ne doit pas
// suffire à passer.
//
// Fonction PURE : les comptes sont passés en argument.

/// Le champ qui porte le compte (identifiant `utilisateurs.id`) sur une décision déposée.
const String champCompteDecision = 'demandeCompte';

/// Les codes STABLES des refus (écrans, tests, journal et banc les lisent).
const String codeCompteNonInscrit = 'COMPTE_NON_INSCRIT';
const String codeCompteInconnu = 'COMPTE_INCONNU';
const String codeCompteRoleDifferent = 'COMPTE_ROLE_DIFFERENT';
const String codeCompteArchive = 'COMPTE_ARCHIVE';

/// Le refus nommé d'un compte signataire.
class RefusCompte {
  const RefusCompte(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
}

bool _archive(Map<String, Object?> u) => u['statut'] == 'archive' || u['actif'] == false;

/// Les rôles d'un compte : `role`, et la liste `roles` quand un compte en porte plusieurs.
Set<String> rolesDuCompte(Map<String, Object?> u) => {
      if ('${u['role'] ?? ''}'.isNotEmpty) '${u['role']}',
      for (final r in (u['roles'] is List ? u['roles'] as List : const [])) '$r',
    };

/// VÉRIFIE le compte inscrit sur une décision : `null` s'il existe dans [comptes] (par son identifiant de compte, ou son identifiant de connexion), porte [role] et n'est pas archivé ;
/// sinon le refus nommé. [par] : le nom porté par la décision (pour le message seulement : un nom ne prouve rien).
RefusCompte? verifierCompteSignataire({required Object? compte, required String role, required String par, required Iterable<Map<String, Object?>> comptes}) {
  final id = '${compte ?? ''}'.trim();
  if (id.isEmpty) {
    return RefusCompte(codeCompteNonInscrit, 'la décision de « $par » ne porte aucun compte de la clinique : une décision ne s’applique que signée par un compte nominatif',
        'Refaire le geste depuis une session nominative (connexion avec son compte).');
  }
  Map<String, Object?>? trouve;
  for (final u in comptes) {
    if ('${u['id']}' == id || ('${u['identifiant'] ?? ''}'.isNotEmpty && '${u['identifiant']}' == id)) {
      trouve = u;
      break;
    }
  }
  if (trouve == null) {
    return RefusCompte(codeCompteInconnu, 'le compte « $id » inscrit sur la décision de « $par » n’existe pas dans les comptes de la clinique',
        'Vérifier le compte à « Utilisateurs » (poste mère), puis refaire le geste.');
  }
  if (_archive(trouve)) {
    return RefusCompte(codeCompteArchive, 'le compte « ${trouve['identifiant'] ?? id} » de « $par » est archivé ou désactivé : sa décision ne s’applique pas',
        'Faire refaire le geste par un compte actif qui détient ce droit.');
  }
  if (!rolesDuCompte(trouve).contains(role)) {
    return RefusCompte(codeCompteRoleDifferent,
        'le compte « ${trouve['identifiant'] ?? id} » de « $par » ne porte pas le rôle « $role » inscrit sur la décision (rôle du compte : ${rolesDuCompte(trouve).join(', ')})',
        'Refaire le geste sous le rôle que le compte porte, ou corriger le rôle du compte à « Utilisateurs » (poste mère).');
  }
  return null;
}
