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

  /// L'écran dont le droit d'ÉDITER vaut « avoir le droit paie » : la colonne « Salaire de base » du personnel est une donnée de paie.
  static const ecranDroitPaie = 'm11-calcul';

  /// L'écran dont le droit d'ANNULER vaut « arbitrer les lots » de tout le monde.
  static const ecranLots = 'imp-accueil';

  Droit _de(String ecran) => c.donnees?.matrice.droit(c.role, ecran) ?? Droit.aucun;

  bool peutImporter(JeuImport j) {
    final d = _de(j.ecran);
    return d.voir && d.editer;
  }

  /// Le profil détient-il au moins un droit d'importer ? (la rangée « Importation » du ruban n'a de sens que pour lui).
  bool get detientUnDroit => jeuxImport.any(peutImporter);

  /// L'historique complet des lots (et l'annulation d'un lot) : DAF et administrateur dans la matrice d'origine ; les autres ne lisent que leurs lots.
  bool get arbitreLesLots {
    final d = _de(ecranLots);
    return d.voir && d.annuler;
  }

  /// Les colonnes réservées de [j] que ce profil a le droit d'importer.
  Set<String> colonnesAccordees(JeuImport j) {
    if (j.colonnesReservees.isEmpty) return const {};
    final d = _de(ecranDroitPaie);
    return d.voir && d.editer ? {...j.colonnesReservees} : const {};
  }

  /// Les lots que le profil a le droit de LIRE : tous s'il arbitre, sinon ceux dont il est l'auteur.
  List<Fiche> lotsVisibles(Iterable<Fiche> lots) => arbitreLesLots ? lots.toList() : [for (final l in lots) if (l['par'] == c.agent.nom) l];
}

/// La clé du réglage (collection `reglages`, la même que `cfbReglage` / `cfbPoserReglage`) qui fixe la borne de taille d'un fichier pour un jeu.
String cleReglageOctetsMax(String jeuId) => 'importOctetsMax.$jeuId';

/// La borne de taille d'un fichier d'import pour [j], en octets : le réglage de la clinique, sinon la valeur par défaut du jeu.
int octetsMaxDe(Magasin m, JeuImport j) {
  final f = m.collection('reglages').actives.where((x) => x['id'] == cleReglageOctetsMax(j.id)).firstOrNull;
  final v = f?['valeur'];
  return v is num && v > 0 ? v.toInt() : j.octetsMaxDefaut;
}
