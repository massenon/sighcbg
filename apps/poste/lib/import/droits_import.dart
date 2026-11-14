import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import '../shell/contexte_ecran.dart';

/// LE DROIT D'IMPORTER, lu dans la MATRICE et nulle part ailleurs (décision de la Direction du 11/11/2026, doctrine « pas de masquage d'interface en dur ») :
/// aucun nom de rôle n'est écrit ici. Importer un jeu de données est un droit DISTINCT d'écrire dans l'écran métier : il se porte par l'écran du JEU
/// (`imp-produits`, `imp-courriers`…), que la matrice administrable (m14-roles, fiches `rbac`) accorde ou retire rôle par rôle, comme tout écran. Un agent
/// qui peut écrire au référentiel produits n'importe donc pas pour autant ; l'administrateur peut accorder l'import au Rôle X sans lui donner l'écriture.
///
///  * importer le jeu = VOIR et ÉDITER l'écran du jeu ;
///  * arbitrer les lots (voir TOUS les lots de l'historique, annuler un lot) = le droit d'ANNULER sur `imp-accueil` ;
///  * importer une colonne réservée (le salaire de base) = ÉDITER l'écran de calcul de la paie ([ecranDroitPaie]).
class DroitsImport {
  const DroitsImport(this.c);
  final ContexteEcran c;

  /// Les écrans dont la matrice décide (définis au domaine, avec la règle : `ProfilImport`).
  static const ecranDroitPaie = ecranDroitPaieImport;
  static const ecranLots = ecranLotsImport;

  /// Le profil que le MOTEUR du domaine lit : la même règle des deux côtés (`ProfilImport`, `packages/domaine`), pour que le bouton et le refus ne divergent jamais.
  ProfilImport get profil => profilImportDe(c);

  bool peutImporter(JeuImport j) => profil.peutImporterEcran(j.ecran);

  /// Le profil détient-il au moins un droit d'importer ? (la rangée « Importation » du ruban n'a de sens que pour lui).
  bool get detientUnDroit => jeuxImport.any(peutImporter);

  /// L'historique complet des lots (et l'annulation d'un lot) : DAF et administrateur dans la matrice d'origine ; les autres ne lisent que leurs lots.
  bool get arbitreLesLots => profil.arbitreLesLots;

  /// Les colonnes réservées de [j] que ce profil a le droit d'importer.
  Set<String> colonnesAccordees(JeuImport j) {
    if (j.colonnesReservees.isEmpty) return const {};
    return profil.aLeDroitPaie ? {...j.colonnesReservees} : const {};
  }

  /// Les lots que le profil a le droit de LIRE : tous s'il arbitre, sinon ceux dont il est l'auteur.
  List<Fiche> lotsVisibles(Iterable<Fiche> lots) => arbitreLesLots ? lots.toList() : [for (final l in lots) if (l['par'] == c.agent.nom) l];
}

/// Le profil de l'agent connecté : son rôle et ses droits sur chaque écran, lus de la matrice EN FORCE de la coque (graine engendrée + décisions de droits superposées à chaud).
/// Sans matrice branchée (un écran monté sans coque), le profil n'a AUCUN droit : le moteur refuse.
ProfilImport profilImportDe(ContexteEcran c) {
  final m = c.donnees?.matrice;
  if (m == null) return const ProfilImport.aucunDroit();
  final role = c.role;
  return ProfilImport(role: role, libelleRole: m.libelle(role) ?? role, droitEcran: (e) => m.droit(role, e));
}

/// La clé du réglage (collection `reglages`, la même que `cfbReglage` / `cfbPoserReglage`) qui fixe la borne de taille d'un fichier pour un jeu.
String cleReglageOctetsMax(String jeuId) => 'importOctetsMax.$jeuId';

/// La borne de taille d'un fichier d'import pour [j], en octets : le réglage de la clinique, sinon la valeur par défaut du jeu.
int octetsMaxDe(Magasin m, JeuImport j) {
  final f = m.collection('reglages').actives.where((x) => x['id'] == cleReglageOctetsMax(j.id)).firstOrNull;
  final v = f?['valeur'];
  return v is num && v > 0 ? v.toInt() : j.octetsMaxDefaut;
}
