import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';

/// Le service des paramètres branché sur le magasin du poste (lot L0). Les règles sont dans `packages/domaine/lib/src/parametres/` (rejouées sur les vecteurs du
/// banc de synchronisation) ; ce fichier ne fait que lui donner les deux collections :
///
/// - `parametres` : une fiche par VERSION (immuable, famille R : la mère seule écrit, les fileuls la reçoivent par le journal et ne l'écrivent jamais) ;
/// - `usagesParametres` : une ligne par pièce qui a utilisé une valeur (ajout seul, remonte à la mère par le pont : c'est elle qui refuse de réécrire ce que la
///   pièce d'un fileul a utilisé).
///
/// [auteur] est le nom de l'agent de la session (RG-12 : aucune action anonyme) ; [horloge] vaut l'horloge réelle sauf dans un test.
ServiceParametres serviceParametres(Magasin m, {required String Function() auteur, DateTime Function()? horloge}) {
  final versions = m.collection(parCollectionParametres);
  final usages = m.collection(parCollectionUsages);
  return ServiceParametres(
    definitions: definitionsParametres,
    lireVersions: () => versions.toutes,
    lireUsages: () => usages.toutes,
    ecrireVersion: (id, champs) => versions.inserer({'id': id, 'statut': 'actif', ...champs}),
    ecrireUsage: (id, champs) => usages.inserer({'id': id, 'statut': 'actif', ...champs}),
    auteur: auteur,
    maintenant: horloge ?? DateTime.now,
  );
}

/// Les SEUILS d'état des échéances fiscales EN VIGUEUR à [date] (paramètres `fiscal.delaiAPayerJours` et `fiscal.delaiDeclarationJours`). Sans fiche en base (poste
/// jamais semé) la valeur retombe sur le défaut de la définition, identique à la graine du moteur : un poste neuf se comporte comme avant.
CpcSeuilsEcheance seuilsEcheance(Magasin m, DateTime date) {
  final s = serviceParametres(m, auteur: () => 'lecture');
  final iso = parametreDateIso(date);
  return CpcSeuilsEcheance.depuis(s.valeur('fiscal.delaiAPayerJours', iso), s.valeur('fiscal.delaiDeclarationJours', iso));
}

/// La contribution annuelle de la CCIB EN VIGUEUR à [date] (paramètre `fiscal.ccibMontant`).
int ccibMontant(Magasin m, DateTime date) {
  final v = serviceParametres(m, auteur: () => 'lecture').valeur('fiscal.ccibMontant', parametreDateIso(date));
  return v is num && v.isFinite && v >= 0 ? v.toInt() : cfbCcibTotal;
}
