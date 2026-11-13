/// LE PROFIL QUI IMPORTE, tel que le moteur le lit (lot IMP-C, porté de la clinique sœur et ADAPTÉ à l'architecture de Baguidi).
///
/// Le droit d'importer n'est PAS un axe de plus : à Baguidi il est tiré de la MATRICE (décision de la Direction du 11/11/2026, « pas de masquage d'interface en dur »).
/// Importer un jeu = VOIR et ÉDITER l'écran du jeu (`imp-produits`, `imp-courriers`…) ; arbitrer les lots = le droit d'ANNULER sur `imp-accueil`. La matrice est celle EN FORCE
/// (graine engendrée + décisions de droits superposées à chaud, `MatriceVive` du poste) : un droit accordé ou retiré depuis « Rôles et permissions » vaut aussitôt, sur la mère comme
/// sur les fileuls, sans second système. Aucun nom de rôle n'est écrit ici.
///
/// Le profil ne porte que le NOM du rôle (pour nommer un refus) et une fonction `ecran → droits` : il ne connaît pas la matrice, il l'interroge. Le moteur refuse selon lui
/// (`refusDroitImport` dans `moteur_import.dart`) : masquer un bouton ne protège rien.
library;

import '../droits/matrice.dart' show Droit;

/// L'écran dont le droit d'ANNULER vaut « arbitrer les lots » de tout le monde (DAF, administrateur dans la matrice d'origine).
const String ecranLotsImport = 'imp-accueil';

/// L'écran dont le droit d'ÉDITER vaut « avoir le droit paie » : la colonne « Salaire de base » du personnel est une donnée de paie.
const String ecranDroitPaieImport = 'm11-calcul';

class ProfilImport {
  const ProfilImport({required this.role, required this.droitEcran, this.libelleRole = ''});

  /// Le profil des TESTS et des traitements déjà contrôlés : accorde tout. Jamais construit par un écran ni par la mère (qui prend toujours le rôle de l'auteur de la demande).
  const ProfilImport.accordeTout({this.role = 'test', this.libelleRole = 'test'}) : droitEcran = _tout;

  /// Aucun droit : un écran monté sans coque, un rôle inconnu. Le moteur refuse.
  const ProfilImport.aucunDroit({this.role = '', this.libelleRole = ''}) : droitEcran = _rien;

  final String role, libelleRole;

  /// Les droits du rôle sur un écran, lus de la matrice en force.
  final Droit Function(String ecran) droitEcran;

  static Droit _tout(String ecran) => const Droit(voir: true, editer: true, annuler: true);
  static Droit _rien(String ecran) => Droit.aucun;

  /// Importer le jeu dont l'écran est [ecran] : VOIR et ÉDITER cet écran.
  bool peutImporterEcran(String ecran) {
    final d = droitEcran(ecran);
    return d.voir && d.editer;
  }

  /// Arbitrer les lots de tout le monde (les voir tous, annuler celui d'un autre).
  bool get arbitreLesLots {
    final d = droitEcran(ecranLotsImport);
    return d.voir && d.annuler;
  }

  /// La colonne « Salaire de base » (et toute colonne réservée) : le droit paie.
  bool get aLeDroitPaie {
    final d = droitEcran(ecranDroitPaieImport);
    return d.voir && d.editer;
  }

  /// Le libellé qui nomme le rôle dans un refus.
  String get nom => libelleRole.isEmpty ? (role.isEmpty ? 'inconnu' : role) : libelleRole;
}
