/// LES RÉGLAGES DE CLINIQUE QUI NOMMENT DES RÔLES OU DES POSTES (Direction de Baguidi, 17/11/2026, Q3 et Q4).
///
/// Des valeurs qui vivaient en dur dans le code deviennent des PARAMÈTRES du registre (en base, versionnés par date, reçus des fileuls) :
///
///  * Q4 `achats.libelleValidateur` : le POSTE porté sur une pièce d'achat validée (jamais le nom d'une personne : l'agent réel est porté à part). Un LIBELLÉ, pas un droit.
///
/// QUI valide les achats n'est PLUS un réglage (Direction de Baguidi, 16/11/2026) : c'est le geste réservé `achats_valider` de la fiche RBAC (`gestes_reserves.dart`), la Directrice
/// Administrative seule d'origine. La clé `achats.rolesValidateurs` de la v20 est RETIRÉE du registre : plus semée, plus affichée, plus lue — une fiche déjà en base reste dans l'historique
/// (rien n'est effacé, RG-14) mais ne décide plus rien.
///
/// QUI passe les écritures d'inventaire d'un exercice EN CLÔTURE n'est plus un réglage non plus (Direction de Baguidi, 17/11/2026, point 7) : c'est le geste réservé `cloture_inventaire` de la fiche
/// RBAC (le Comptable et la DAF d'origine). La clé `cloture.rolesInventaire` (Q3, liste de rôles) est RETIRÉE du registre comme `achats.rolesValidateurs` : plus semée, plus affichée, plus lue — une
/// fiche déjà en base reste dans l'historique (RG-14) mais ne décide plus rien.
///
/// Une liste est écrite en TEXTE, identifiants de rôle séparés par des virgules. Une liste VIDE ou illisible retombe sur le défaut : un réglage mal saisi ne doit jamais verrouiller la clinique
/// (plus personne ne validerait une commande), il se corrige par une nouvelle version datée.
library;

/// La clé RETIRÉE du réglage Q3 « rôles d'inventaire en clôture » (remplacée par le geste `cloture_inventaire`). Nommée ici pour que les tests prouvent qu'aucun lecteur ne la consulte plus.
const String cleRolesInventaireClotureRetiree = 'cloture.rolesInventaire';

/// La clé RETIRÉE du réglage v20 « validateur des commandes » (remplacée par le geste `achats_valider`). Nommée ici pour que les tests prouvent qu'aucun lecteur ne la consulte plus.
const String cleRolesValidateursAchatsRetiree = 'achats.rolesValidateurs';
const String cleLibelleValidateurAchats = 'achats.libelleValidateur';

/// Le défaut SEMÉ du libellé du poste validateur.
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
