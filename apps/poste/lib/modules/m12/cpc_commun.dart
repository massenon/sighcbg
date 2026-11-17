import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../donnees/exercices_poste.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m7/besoins_commun.dart' show notifierPoste;
export 'cpa_commun.dart';
export '../../donnees/exercices_poste.dart' show amorcerExercices, moisOuvertureSuivantDe;

/// Briques communes à la tranche M12 « synthèse, exercices, pilotage » (états financiers, baseline 2025, échéances, clôture, ouverture, BFR, coût à
/// l'activité). Les règles chiffrées vivent dans `packages/domaine/lib/src/comptabilite/cpc_*.dart`.

List<Fiche> exercicesActifs(Magasin m) => cpcListeExercices(m.collection('exercices').toutes);

/// Le nom de l'agent porté par chaque geste (RG-12) : celui de l'agent de la session (A1, E800 levé). L'IDENTIFIANT ([acteurIdDe]) sert aux contrôles
/// de séparation des tâches ; le nom, à l'affichage et aux pièces.
String acteurDe(ContexteEcran c) => acteurNom(c);

/// L'identifiant du compte de l'agent : la clé de « demandeur différent du validateur », jamais le libellé du rôle.
String acteurIdDe(ContexteEcran c) => acteur(c).utilisateurId;

/// L'écran d'un contrôle de pré-clôture, nommé comme au manifeste (« → Écritures comptables »).
const Map<String, String> libellesEcransM12 = {
  'm12-ecritures': 'Écritures comptables',
  'm12-balance': 'Balance générale & âgée',
  'm12-ouverture': 'Bilan d’ouverture & à-nouveaux',
  'm12-grand-livre': 'Grand livre',
};

/// Un refus d'écriture par la garde de la collection : toast nommé (le journal est déjà écrit par la collection).
bool refuseSiClos(BuildContext ctx, void Function() ecriture) {
  try {
    ecriture();
    return false;
  } on EcritureRefusee catch (e) {
    ToastsSigh.afficher(ctx, 'Écriture refusée.', type: TypeToast.erreur, detail: e.motif);
    return true;
  }
}

/// `PR.notifier` : une notification de POSTE.
void notifier(ContexteEcran c, {required String type, required String poste, required String libelle, String? detail, String priorite = 'normale', String? reference}) =>
    notifierPoste(c.magasin, {'type': type, 'poste': poste, 'libelle': libelle, 'detail': detail, 'priorite': priorite, 'reference': reference}, c.aujourdhui);


/// Règle le mois d'ouverture de l'exercice suivant. Rend le refus nommé, ou `null`. Journalisé (RG-12) avec l'ancien et le nouveau mois ; l'exercice suivant déjà ouvert le reste (rien n'est fermé ici).
String? definirMoisOuvertureSuivant(Magasin m, Object? valeur, {required String auteur}) {
  final refus = cpcRefusMoisOuvertureSuivant(valeur);
  if (refus != null) return refus;
  final mois = cpcMoisOuvertureSuivant(valeur);
  final avant = moisOuvertureSuivantDe(m);
  m.journaliser('Réglage : mois d’ouverture de l’exercice suivant', 'M12', 'reglage', cpcCleMoisOuvertureSuivant, {'mois': avant}, {'mois': mois, 'par': auteur});
  final col = m.collection('reglages');
  if (col.parId(cpcCleMoisOuvertureSuivant) == null) {
    col.ajouterSansJournal({
      'id': cpcCleMoisOuvertureSuivant,
      'statut': 'actif',
      'valeur': mois,
      'source': 'Décision de la Direction du 16/11/2026 (Q29) : l\u2019exercice suivant s\u2019ouvre en décembre par défaut, réglable.',
    });
  } else {
    col.mettreAJour(cpcCleMoisOuvertureSuivant, {'valeur': mois}, journaliser: false);
  }
  return null;
}
