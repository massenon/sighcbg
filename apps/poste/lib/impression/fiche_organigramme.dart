import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import 'identite_poste.dart';
import 'piece.dart';

/// L'AGENT qui tient un poste : par son identifiant (`personnelId`, le lien posé quand le titulaire se choisit au personnel), à défaut par le nom écrit sur
/// la fiche (les postes du jeu d'origine, et un nom gardé tel quel — « épse X » comprise). Aucun agent trouvé : `null` (le nom reste affiché tel quel).
Map<String, Object?>? agentDuPoste(Magasin m, Map<String, Object?> poste) {
  final id = '${poste['personnelId'] ?? ''}';
  final nom = '${poste['titulaire'] ?? ''}';
  for (final a in m.collection('personnel').actives) {
    if (id.isNotEmpty ? '${a['id']}' == id : (nom.isNotEmpty && '${a['nomComplet']}' == nom)) return a;
  }
  return null;
}

/// Le titre que l'agent titulaire porte à l'organigramme (« SG »), vide s'il n'en porte pas ou si le poste est vacant.
String titrePorteDuPoste(Magasin m, Map<String, Object?> poste) => '${agentDuPoste(m, poste)?['titreOrganigramme'] ?? ''}'.trim();

/// L'ORGANIGRAMME IMPRIMÉ, construit du magasin : les postes ACTIFS (un poste archivé disparaît du graphe et de la légende), la fiche `organigramme` de
/// `fichesDocumentaires` (référence, date, version, titres, mention, grille) et l'identité de la clinique à la date d'édition. Rien n'est écrit ici :
/// ajouter un poste à l'écran l'ajoute au graphe et à la légende, sans code.
FichePaysage fichePaysageOrganigramme(Magasin m, {required String utilisateur, required DateTime edite, required String reference}) {
  final fiche = ParametresFiche.depuisFiche(m.collection(ficheDocCollection).actives.where((f) => f['id'] == ficheDocOrganigramme).firstOrNull);
  // Le titre porté par chaque titulaire est lu au PERSONNEL à l'édition : le changer au dossier de l'agent change la boîte, sans toucher au poste.
  final postes = [
    for (final p in m.collection('postes').actives) {...p, 'titrePorte': titrePorteDuPoste(m, p)}
  ];
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
