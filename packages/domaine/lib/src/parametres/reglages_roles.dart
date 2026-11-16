/// LES RÉGLAGES DE CLINIQUE QUI NOMMENT DES RÔLES (Direction de Baguidi, 17/11/2026, Q3 et Q4).
///
/// Deux listes de rôles qui vivaient en dur dans le code deviennent des PARAMÈTRES du registre (en base, versionnés par date, reçus des fileuls) :
///
///  * Q3 `cloture.rolesInventaire` : qui passe les écritures d'inventaire d'un exercice EN CLÔTURE (comptable et administrateur semés) ;
///  * Q4 `achats.rolesValidateurs` : qui arbitre un bon de besoins et valide une commande de stock (RG-04) — la Directrice Administrative semée — et `achats.libelleValidateur`, le POSTE
///    porté sur la pièce validée (jamais le nom d'une personne : l'agent réel est porté à part).
///
/// Une liste est écrite en TEXTE, identifiants de rôle séparés par des virgules. Une liste VIDE ou illisible retombe sur le défaut : un réglage mal saisi ne doit jamais verrouiller la clinique
/// (plus personne ne validerait une commande), il se corrige par une nouvelle version datée.
library;

const String cleRolesInventaireCloture = 'cloture.rolesInventaire';
const String cleRolesValidateursAchats = 'achats.rolesValidateurs';
const String cleLibelleValidateurAchats = 'achats.libelleValidateur';

/// Les défauts SEMÉS : ce sont ceux que le code portait avant le réglage (Q3 : comptable et administrateur ; Q4 : la Directrice Administrative).
const List<String> rolesInventaireClotureDefaut = ['comptable', 'admin'];
const List<String> rolesValidateursAchatsDefaut = ['da'];
const String libelleValidateurAchatsDefaut = 'Directrice administrative';

/// Les identifiants de rôle d'un réglage « liste de rôles » : séparés par des virgules ou des points-virgules, espaces ôtés, doublons retirés, ordre conservé. [defaut] quand la valeur
/// n'est pas un texte ou ne contient aucun identifiant.
List<String> reglageRoles(Object? valeur, List<String> defaut) {
  if (valeur is! String) return defaut;
  final vus = <String>[];
  for (final m in valeur.split(RegExp(r'[,;]'))) {
    final r = m.trim();
    if (r.isNotEmpty && !vus.contains(r)) vus.add(r);
  }
  return vus.isEmpty ? defaut : vus;
}

/// Le texte d'un réglage « liste de rôles » (l'inverse de [reglageRoles]).
String reglageRolesTexte(Iterable<String> roles) => roles.join(',');

/// Le poste validateur porté sur une pièce : le libellé réglé, ou le défaut quand il est vide.
String reglageLibelleValidateur(Object? valeur) => valeur is String && valeur.trim().isNotEmpty ? valeur.trim() : libelleValidateurAchatsDefaut;
