/// LES TRANCHES D'ÂGE DES STATISTIQUES (lot « valeurs en dur », famille H) : une SEULE définition, paramétrable. Une tranche d'âge n'est plus un tableau écrit dans le code : c'est une
/// liste de BORNES SUPÉRIEURES (« 5; 15; 25; 45; 65 ») d'un réglage daté ; la première tranche commence à 0 an, la dernière est ouverte (« 66 ans et plus »).
///
/// Les statistiques du laboratoire et celles du pilotage portaient deux copies DIVERGENTES (0-5, 6-15… contre 0-4, 5-14…). Les deux écrans lisent désormais le MÊME code, chacun avec SON
/// réglage, dont la valeur d'attente est celle d'avant (ce sont les vecteurs de la maquette : les unifier changerait les sorties d'un des deux écrans). Aligner les deux sur un même découpage
/// (par exemple celui du DHIS2) ne demande plus de programmer : recopier les mêmes bornes dans les deux réglages.
library;

import '../parametres/listes_reference.dart' show ListesReference;

/// Une tranche d'âge : identifiant stable (« 0-5 », « 66+ »), libellé d'affichage, bornes incluses.
class TrancheAge {
  const TrancheAge(this.id, this.label, this.min, this.max);
  final String id;
  final String label;
  final int min;
  final int max;

  bool contient(int age) => age >= min && age <= max;
}

/// L'âge maximal retenu pour fermer la dernière tranche (une personne n'a pas plus de 200 ans : borne technique de la tranche ouverte, pas une valeur clinique).
const int ageMaxTrancheOuverte = 200;

/// Les bornes supérieures lues d'un réglage « 5; 15; 25 » : `null` si une valeur n'est pas un entier, si elles ne croissent pas strictement, si l'une est négative ou dépasse 150, ou s'il n'y en a aucune.
List<int>? bornesTranchesValides(List<String> brut) {
  if (brut.isEmpty) return null;
  final b = <int>[];
  for (final x in brut) {
    final n = int.tryParse(x.trim());
    if (n == null || n < 0 || n > 150) return null;
    if (b.isNotEmpty && n <= b.last) return null;
    b.add(n);
  }
  return b;
}

/// Les tranches construites sur [bornes] ; [separateur] est la typographie du libellé (« 0 – 5 ans » ou « 0–4 ans »).
List<TrancheAge> tranchesAgeDepuisBornes(List<int> bornes, {required String separateur}) {
  final out = <TrancheAge>[];
  var debut = 0;
  for (final fin in bornes) {
    out.add(TrancheAge('$debut-$fin', '$debut$separateur$fin ans', debut, fin));
    debut = fin + 1;
  }
  out.add(TrancheAge('$debut+', '$debut ans et plus', debut, ageMaxTrancheOuverte));
  return out;
}

/// Les tranches EN VIGUEUR du réglage [cle] : sa version datée, sinon sa valeur d'attente — une valeur illisible ou incohérente retombe sur la valeur d'attente, jamais sur « aucune tranche ».
List<TrancheAge> tranchesAgeDe(String cle, {required String separateur}) {
  final lues = bornesTranchesValides(ListesReference.valeurs(cle));
  final b = lues ?? bornesTranchesValides(ListesReference.semence(cle))!;
  return tranchesAgeDepuisBornes(b, separateur: separateur);
}
