import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import 'identite_poste.dart';
import 'piece.dart';

/// L'ORGANIGRAMME IMPRIMÉ, construit du magasin : les postes ACTIFS (un poste archivé disparaît du graphe et de la légende), la fiche `organigramme` de
/// `fichesDocumentaires` (référence, date, version, titres, mention, grille) et l'identité de la clinique à la date d'édition. Rien n'est écrit ici :
/// ajouter un poste à l'écran l'ajoute au graphe et à la légende, sans code.
FichePaysage fichePaysageOrganigramme(Magasin m, {required String utilisateur, required DateTime edite, required String reference}) {
  final fiche = ParametresFiche.depuisFiche(m.collection(ficheDocCollection).actives.where((f) => f['id'] == ficheDocOrganigramme).firstOrNull);
  final postes = m.collection('postes').actives;
  final scene = organigrammeScene(postes, fiche.grille);
  final legende = organigrammeLegende(postes);
  return FichePaysage(
    fiche: fiche,
    pages: [PageGraphe(scene), for (final p in paginerLegende(legende, fiche.grille.legendeParPage)) PageLegende(p)],
    reference: reference,
    utilisateur: utilisateur,
    edite: edite,
    identite: identiteImprimeeDe(m, edite),
  );
}
