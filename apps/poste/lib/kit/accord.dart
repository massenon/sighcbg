/// Accord français des libellés d'entité (« une situation », « un patient »). Les tableaux écrivaient « Rechercher un situation » et « Aucun consultation
/// enregistré » : l'article se choisit sur le premier mot de l'entité.
const _feminins = {
  'situation', 'convention', 'consultation', 'facture', 'compagnie', 'demande', 'fiche', 'déclaration', 'intervention', 'immobilisation', 'grossesse',
  'naissance', 'relance', 'réunion', 'urgence', 'unité', 'analyse', 'admission', 'avance', 'pièce', 'variable', 'nature', 'identité', 'vacation',
  'écriture', 'ordonnance', 'prescription', 'commande', 'livraison', 'ligne', 'sortie', 'entrée', 'échéance', 'dépense', 'recette', 'prime', 'sanction',
  'évaluation', 'alerte', 'poche', 'transfusion', 'chambre', 'visite', 'obligation', 'garantie', 'tâche', 'opération', 'pathologie', 'spécialité',
};

bool entiteFeminine(String entite) {
  final mot = entite.trim().toLowerCase().split(RegExp(r'[\s’\x27-]+')).first;
  return _feminins.contains(mot);
}

String rechercherEntite(String entite) => 'Rechercher ${entiteFeminine(entite) ? 'une' : 'un'} $entite…';

String aucuneEntiteEnregistree(String entite) =>
    entiteFeminine(entite) ? 'Aucune $entite enregistrée.' : 'Aucun $entite enregistré.';
