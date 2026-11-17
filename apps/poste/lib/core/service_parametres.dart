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

/// Le préavis de péremption (jours) EN VIGUEUR à [date] (paramètre `stock.delaiPreavisPeremptionJours`, Q10) : lots, alertes, tableaux de bord. Poste jamais semé : 90, la valeur semée.
int preavisPeremption(Magasin m, DateTime date) =>
    delaiPreavisPeremptionDe(serviceParametres(m, auteur: () => 'lecture').valeur(cleDelaiPreavisPeremption, parametreDateIso(date)));

/// Les bornes de la balance âgée des patients EN VIGUEUR à [date] (paramètres `comptabilite.balanceAgeePatientBorne1Jours` et `…2Jours`, Q14) : 30 et 90 jours semés.
({int borne1, int borne2}) bornesBalanceAgeePatient(Magasin m, DateTime date) {
  final s = serviceParametres(m, auteur: () => 'lecture');
  final iso = parametreDateIso(date);
  return bornesBalanceAgeePatientDe(s.valeur(cleBalanceAgeePatientBorne1, iso), s.valeur(cleBalanceAgeePatientBorne2, iso));
}

/// Les bornes de la balance âgée des ASSUREURS EN VIGUEUR à [date] (paramètres `assurances.balanceAgeeAssureurBorne1Jours` et `…2Jours`) : 30 et 90 jours semés.
({int borne1, int borne2}) bornesBalanceAgeeAssureur(Magasin m, DateTime date) {
  final s = serviceParametres(m, auteur: () => 'lecture');
  final iso = parametreDateIso(date);
  return bornesBalanceAgeeAssureurDe(s.valeur(cleBalanceAgeeAssureurBorne1, iso), s.valeur(cleBalanceAgeeAssureurBorne2, iso));
}

/// Les lots actifs avec leur statut de péremption RECALCULÉ à [auj] pour le préavis en vigueur (Q10) : les tableaux de bord, le pilotage, les états et le centre de notifications lisent
/// cette vue, jamais le `statut` écrit à la saisie du lot (il date de ce jour-là et de l'ancien délai).
List<Map<String, Object?>> lotsAvecStatutAJour(Magasin m, DateTime auj) =>
    lotsAvecStatutRecalcule(m.collection('lots').actives, auj, preavisPeremption(m, auj));

/// Le routage des notifications de poste EN VIGUEUR à [date] (réglage `notifications.routagePostes`) : poste → geste réservé. Poste jamais semé : la valeur d'attente, identique
/// à la table que portait le centre de notifications.
Map<String, String> routagePostes(Magasin m, DateTime date) =>
    routagePostesDe(serviceParametres(m, auteur: () => 'lecture').valeur(cleRoutagePostes, parametreDateIso(date)));

/// Les postes informés quand un besoin est accordé EN VIGUEUR à [date] (réglage `notifications.destinatairesBesoinAccorde`).
List<DestinataireNotif> destinatairesBesoinAccorde(Magasin m, DateTime date) =>
    destinatairesBesoinAccordeDe(serviceParametres(m, auteur: () => 'lecture').valeur(cleDestinatairesBesoinAccorde, parametreDateIso(date)));
/// Un SEUIL ENTIER de clinique EN VIGUEUR à [date] (lot « seuils » de l'inventaire des valeurs en dur) : la version datée du paramètre [cle], sinon sa valeur d'attente ;
/// hors des bornes de la définition, la valeur d'attente. Poste jamais semé : la valeur d'attente, le comportement d'avant.
int seuilClinique(Magasin m, String cle, DateTime date) =>
    seuilEntierDe(cle, serviceParametres(m, auteur: () => 'lecture').valeur(cle, parametreDateIso(date)));
