/// Accord français des libellés d'entité (« une situation », « un patient »). Les tableaux écrivaient « Rechercher un situation » et « Aucun consultation
/// enregistré » : l'article se choisit sur le premier mot de l'entité.
const _feminins = {
  'situation', 'convention', 'consultation', 'facture', 'compagnie', 'demande', 'fiche', 'déclaration', 'intervention', 'immobilisation', 'grossesse',
  'naissance', 'relance', 'réunion', 'urgence', 'unité', 'analyse', 'admission', 'avance', 'pièce', 'variable', 'nature', 'identité', 'vacation',
  'écriture', 'ordonnance', 'prescription', 'commande', 'livraison', 'ligne', 'sortie', 'entrée', 'échéance', 'dépense', 'recette', 'prime', 'sanction',
  'couverture', 'ambulance', 'cpa', 'check-liste', 'contre-référence', 'catégorie', 'zone', 'famille',
  'évaluation', 'alerte', 'poche', 'transfusion', 'chambre', 'visite', 'obligation', 'garantie', 'tâche', 'opération', 'pathologie', 'spécialité',
};

bool entiteFeminine(String entite) {
  final mot = entite.trim().toLowerCase().split(RegExp(r'[\s’\x27]+')).first;
  return _feminins.contains(mot) || _feminins.contains(mot.split('-').first);
}

/// Les mots féminins connus (lecture seule) : le test de garde s'en sert pour refuser « Nouveau » devant l'un d'eux.
Set<String> get motsFeminins => Set.unmodifiable(_feminins);

bool _voyelleInitiale(String entite) {
  final premier = entite.trim().toLowerCase();
  return premier.isNotEmpty && 'aeiouyéèêàâîïôû'.contains(premier[0]);
}

/// « Nouvelle admission » / « Nouveau patient » / « Nouvel accouchement » : l'adjectif s'accorde avec le premier mot de l'entité
/// (genre) et s'élide devant une voyelle au masculin.
String nouvelleEntite(String entite) {
  if (entiteFeminine(entite)) return 'Nouvelle $entite';
  return '${_voyelleInitiale(entite) ? 'Nouvel' : 'Nouveau'} $entite';
}

/// « Nouvelle admission créée. » / « Nouveau patient créé. ».
String entiteCreee(String entite) => '${nouvelleEntite(entite)} ${entiteFeminine(entite) ? 'créée' : 'créé'}.';

/// « Toutes les admissions » / « Tous les patients » : le genre se lit sur le singulier, le texte sur le pluriel.
String tousLesEntites(String entite, String pluriel) => '${entiteFeminine(entite) ? 'Toutes' : 'Tous'} les $pluriel';

/// « Modifier la facture » / « Modifier le lot » (« l’ » devant une voyelle).
String modifierEntite(String entite) {
  final voyelle = _voyelleInitiale(entite) || entite.trim().toLowerCase().startsWith('h');
  return 'Modifier ${voyelle ? 'l’' : (entiteFeminine(entite) ? 'la ' : 'le ')}$entite';
}

String rechercherEntite(String entite) => 'Rechercher ${entiteFeminine(entite) ? 'une' : 'un'} $entite…';

String aucuneEntiteEnregistree(String entite) =>
    entiteFeminine(entite) ? 'Aucune $entite enregistrée.' : 'Aucun $entite enregistré.';
