/// BONS DE COMMANDE (m7-commandes) — RG-04 : toute commande de stock gros est validée par la Directrice Administrative AVANT transmission.
///
/// Rejoué sur `test/vecteurs/achats-commandes.json` (écran réel piloté dans Chrome).
///
/// Écarts de la maquette portés fidèlement et signalés (E72) : le geste « Valider (DA) » est offert à tout profil qui écrit dans M7 (le gestionnaire
/// de stock compris) et le validateur était TOUJOURS une personne écrite en dur (désormais le poste « Directrice administrative ») ; surtout, choisir le statut « Validée », « Transmise », « Livrée » ou « Soldée »
/// dans le formulaire pose d'office la validation de la DAF — RG-04 est donc contournable par qui peut modifier une commande.
library;

import 'nombres.dart';
import 'besoins.dart';

class StatutCommande {
  const StatutCommande(this.valeur, this.libelle, this.ton);
  final String valeur;
  final String libelle;
  final String ton;
}

const statutsCommande = [
  StatutCommande('brouillon', 'Brouillon', 'neutral'),
  StatutCommande('attente_validation', 'En attente de validation DA', 'warning'),
  StatutCommande('validee', 'Validée', 'info'),
  StatutCommande('transmise', 'Transmise au fournisseur', 'navy'),
  StatutCommande('livree', 'Livrée', 'success'),
  StatutCommande('soldee', 'Soldée', 'success'),
];

String libelleCommande(Object? s) => statutsCommande
    .firstWhere((x) => x.valeur == s,
        orElse: () => StatutCommande('$s', '$s', 'neutral'))
    .libelle;

String toneCommande(Object? s) => statutsCommande
    .where((x) => x.valeur == s)
    .map((x) => x.ton)
    .firstOrNull ??
    'neutral';

typedef _Commande = Map<String, Object?>;

num _n(Object? v) => nombreEntier(v);

List<_Commande> commandesEnAttente(Iterable<_Commande> actives) => [
      for (final c in actives)
        if (c['statutCommande'] == 'attente_validation') c
    ];

/// Les quatre indicateurs de l'écran.
({int enregistrees, int enAttente, num montant, int livrees}) indicateursCommandes(
        Iterable<_Commande> actives) =>
    (
      enregistrees: actives.length,
      enAttente: commandesEnAttente(actives).length,
      montant: actives.fold<num>(0, (a, c) => a + _n(c['montant'])),
      livrees: actives
          .where((c) => const ['livree', 'soldee'].contains(c['statutCommande']))
          .length,
    );

/// Le geste de la DAF (RG-04) : la commande devient « Validée » — elle peut alors être transmise.
_Commande validationCommande({required String jour, String validateur = directriceAdministrative}) => {
      'statutCommande': 'validee',
      'valideePar': validateur,
      'dateValidation': jour,
    };

/// Une ligne de commande : l'article, la quantité et le prix unitaire (la valeur est quantité × prix).
_Commande nouvelleLigneCommande(
    {required Map<String, Object?>? produit,
    required Object? quantite,
    required Object? prixUnitaire}) {
  final q = _n(quantite), pu = _n(prixUnitaire);
  if (produit == null || q <= 0) {
    throw const RefusAchat('Sélectionner un article et une quantité.');
  }
  return {
    'produitId': produit['id'],
    'produit': produit['designation'],
    'unite': produit['unite'],
    'quantite': q,
    'prixUnitaire': pu,
    'montant': q * pu,
  };
}

num montantCommande(Iterable<_Commande> lignes) =>
    lignes.fold<num>(0, (a, l) => a + _n(l['montant']));

/// Enregistre une commande (création ou modification) : ce que la modale de la maquette écrit.
/// [fournisseurs] = les fiches du référentiel (code, nom, délai) ; [commandes] = TOUTES les commandes (archivées comprises, pour la série).
/// Les statuts qui POSENT la validation (RG-04) quand la commande n'en porte pas encore : validée et tout ce qui suit.
const Set<String> statutsCommandeApresValidation = {'validee', 'transmise', 'livree', 'soldee'};

/// [peutValider] : le rôle détient-il le geste `achats_valider` ? `null` (les vecteurs de la maquette) : la règle de la maquette (E72, la validation posée d'office par le statut). `false` :
/// un statut de [statutsCommandeApresValidation] sur une commande non encore validée est REFUSÉ en le nommant (E3263) — RG-04 n'est plus contournable par le formulaire.
_Commande commandeEnregistree(
    {required _Commande saisie,
    required List<_Commande> lignes,
    _Commande? existante,
    required Iterable<_Commande> fournisseurs,
    required Iterable<_Commande> commandes,
    required String jour,
    String Function()? referenceSuivante,
    String validateur = directriceAdministrative,
    bool? peutValider}) {
  if (lignes.isEmpty) throw const RefusAchat('Ajouter au moins un article.');
  final dejaValideeAvant = existante != null && existante['valideePar'] != null && existante['valideePar'] != '';
  if (peutValider == false &&
      statutsCommandeApresValidation.contains(saisie['statutCommande']) &&
      saisie['statutCommande'] != existante?['statutCommande'] &&
      !dejaValideeAvant) {
    throw RefusAchat(
        'Le statut « ${libelleCommande(saisie['statutCommande'])} » suppose la validation de la commande (RG-04), geste réservé « Valider les achats » (d’origine : la Directrice Administrative) que ce rôle ne détient pas. Laisser la commande « En attente de validation DA ».');
  }
  final v = {...saisie};
  final four =
      fournisseurs.where((x) => x['code'] == v['fournisseur']).firstOrNull;
  v['fournisseurNom'] = four != null ? four['nom'] : v['fournisseur'];
  v['delaiLivraison'] = four?['delai'];
  v['lignes'] = lignes;
  v['montant'] = montantCommande(lignes);
  if (existante == null) {
    v['reference'] = referenceSuivante != null ? referenceSuivante() : referenceAchatSuivante('BC-2026-', 4, commandes);
  }
  // E72/E74 : le statut choisi pose la validation de la DAF d'office, sauf si un validateur est déjà connu.
  final dejaValidee = existante != null &&
      existante['valideePar'] != null &&
      existante['valideePar'] != '';
  final dejaPose = v['valideePar'];
  if (const ['validee', 'transmise', 'livree', 'soldee']
          .contains(v['statutCommande']) &&
      (dejaPose == null || dejaPose == '') &&
      !dejaValidee) {
    v['valideePar'] = validateur;
    v['dateValidation'] = jour;
  }
  return v;
}

/// Les commandes à réceptionner : validées ou transmises (jamais avant la validation de la DAF).
List<_Commande> commandesAReceptionner(Iterable<_Commande> actives) => [
      for (final c in actives)
        if (const ['validee', 'transmise'].contains(c['statutCommande'])) c
    ];

/// Les quatre indicateurs de l'écran des réceptions.
({int aReceptionner, int realisees, num valeurAttendue, int fournisseurs})
    indicateursReceptions(Iterable<_Commande> actives) {
  final a = commandesAReceptionner(actives);
  return (
    aReceptionner: a.length,
    realisees: actives
        .where((c) => const ['livree', 'soldee'].contains(c['statutCommande']))
        .length,
    valeurAttendue: a.fold<num>(0, (s, c) => s + _n(c['montant'])),
    fournisseurs: {for (final c in a) '${c['fournisseur']}'}.length,
  );
}
