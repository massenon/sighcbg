import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_parametres.dart';
import 'magasin.dart';

/// Les RÉGLAGES DE CLINIQUE qui nomment des rôles ou un poste (Direction de Baguidi, 17/11/2026, Q3 et Q4), lus de la base à la date du jour. Aucun nom de rôle n'est écrit ici : les défauts viennent
/// du domaine (`rolesInventaireClotureDefaut`), les valeurs en vigueur des fiches de paramètres. Sur un fileul comme sur la mère : la valeur en vigueur se lit toujours, le défaut tient tant que la
/// fiche n'est pas arrivée. QUI valide les achats n'est plus un réglage : c'est le geste réservé `achats_valider` de la fiche RBAC (`droitsGestesEcran`, `shell/gestes_ecran.dart`).
class ReglagesClinique {
  const ReglagesClinique._();

  static Object? _lire(Magasin m, String cle, DateTime date) => serviceParametres(m, auteur: () => 'lecture').valeur(cle, parametreDateIso(date));

  /// Q4 : le POSTE porté sur la pièce validée (jamais une personne).
  static String libelleValidateurAchats(Magasin m, DateTime date) => reglageLibelleValidateur(_lire(m, cleLibelleValidateurAchats, date));

  /// Q3 : les rôles qui passent leurs écritures d'inventaire pendant qu'un exercice est en clôture.
  static List<String> rolesInventaire(Magasin m, DateTime date) => reglageRoles(_lire(m, cleRolesInventaireCloture, date), rolesInventaireClotureDefaut);
}
