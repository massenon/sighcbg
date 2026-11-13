import 'package:sigh_domaine/sigh_domaine.dart';

import '../kit/acteur.dart';
import '../modules/m5/res_commun.dart' show profilLabo;
import '../shell/contexte_ecran.dart';
import 'magasin.dart';

/// LES SEUILS DE VARIATION BRUTALE AU POSTE (lot A2) : le branchement des fonctions pures du domaine (`res_seuils.dart`) sur le magasin. Le domaine décide et
/// rend ce qu'il faut écrire ; c'est ICI que l'on écrit et journalise (RG-12, UNE ligne par geste).
///
/// LES DROITS SONT LUS À LA MATRICE, JAMAIS À UN NOM DE RÔLE : enregistrer = ÉDITER l'écran des valeurs de référence ; valider = le droit ANNULER de ce même
/// écran (l'arbitrage, comme l'arbitrage des lots d'import à `imp-accueil`). Par défaut seul le Biologiste médical l'a, avec l'administrateur système (qui a
/// toute la matrice). Le moteur REVÉRIFIE à chaque geste, à chaud : la commande absente de l'écran ne protège rien, un geste forcé reçoit un refus nommé. La
/// fonction du technicien de laboratoire (validation par intérim) est exclue en plus de la matrice.
///
/// Aucun seuil n'est semé : la collection `seuilsDelta` naît vide. Elle ne figure pas à `collectionsDuJeu` (aucun fichier de jeu à livrer, ni vidage ni
/// archivage du jeu de démonstration ne la touchent : un seuil validé est une décision du biologiste, pas une donnée de démonstration).
class SeuilsPoste {
  SeuilsPoste(this.c);
  final ContexteEcran c;

  /// L'écran qui porte le réglage et dont la matrice décide.
  static const ecran = 'm5-valeurs-reference';

  Magasin get m => c.magasin;
  CollectionMagasin get col => m.collection('seuilsDelta');
  List<Fiche> get actifs => col.actives;

  /// Les droits du profil de la SESSION sur l'écran des valeurs de référence, à chaud. Sur un autre écran que celui-là, la matrice est relue (jamais les
  /// droits de l'écran courant : ce serait ceux d'un autre module).
  Droit get droit {
    if (c.ecranId == ecran) return c.droit;
    final mat = c.donnees?.matrice;
    return mat == null ? const Droit(voir: false, editer: false, annuler: false) : mat.droit(c.role, ecran);
  }

  bool get peutEnregistrer => droit.editer;

  /// Valider : le droit de la matrice ET une fonction qui porte la validation biologique.
  bool get peutValider => droit.annuler && fonctionPeutValiderSeuil(profilLabo(c).session);

  String get _profil => c.donnees?.matrice.libelle(c.role) ?? c.role;

  EtatSeuil etat(Object? variableId) => etatSeuil('$variableId', actifs, aujourdhui: c.aujourdhui);

  VerdictSeuil enregistrer(String variableId, {Object? ecartAbsolu, Object? ecartRelatif, bool retrait = false, Object? dateEffet, String? note}) {
    final a = acteur(c);
    final v = m.collection('variablesLabo').parId(variableId);
    final r = enregistrerSeuil(
        variable: v,
        variableId: variableId,
        seuilsActifs: actifs,
        droitEditer: peutEnregistrer,
        profil: _profil,
        ecartAbsolu: ecartAbsolu,
        ecartRelatif: ecartRelatif,
        retrait: retrait,
        dateEffet: dateEffet,
        note: note,
        acteur: a.nom,
        role: c.role,
        maintenant: c.aujourdhui);
    return _ecrire(r);
  }

  VerdictSeuil valider(String variableId, {String? motif}) {
    final a = acteur(c);
    final r = validerSeuil(
        variableId: variableId,
        seuilsActifs: actifs,
        droitValider: droit.annuler,
        fonctionHabilitee: fonctionPeutValiderSeuil(profilLabo(c).session),
        profil: _profil,
        motif: motif,
        acteur: a.nom,
        libelleRole: c.donnees?.matrice.libelle(c.role) ?? c.role,
        maintenant: c.aujourdhui);
    return _ecrire(r);
  }

  VerdictSeuil abandonner(String variableId) {
    final r = abandonnerSeuil(variableId: variableId, seuilsActifs: actifs, droitEditer: peutEnregistrer, profil: _profil);
    return _ecrire(r);
  }

  VerdictSeuil _ecrire(VerdictSeuil r) {
    if (!r.ok) return r;
    try {
      if (r.archivage) {
        // L'archivage journalise lui-même (RG-14 : le brouillon se range à la corbeille, il ne se supprime pas).
        col.archiver(r.id);
        return r;
      }
      if (r.creation) {
        final fiche = {...r.fiche!, 'id': _prochainId()};
        col.ajouterSansJournal(fiche, enTete: true);
      } else {
        col.mettreAJour(r.id, r.patch!, journaliser: false);
      }
    } on EcritureRefusee catch (e) {
      return VerdictSeuil.refus(RefusSeuil('ECRITURE_REFUSEE', e.motif, 'Voir le journal.'));
    }
    final j = r.journal!;
    m.journaliser(j.action, 'M5', 'seuil de variation', j.reference, j.avant, j.apres);
    return r;
  }

  /// `SEU` + rang à cinq chiffres, au-delà du plus grand rang connu (archivées comprises : un identifiant ne se réattribue pas).
  String _prochainId() {
    var max = 0;
    for (final f in col.toutes) {
      final n = int.tryParse('${f['id']}'.replaceFirst('SEU', ''));
      if (n != null && n > max) max = n;
    }
    return 'SEU${(max + 1).toString().padLeft(5, '0')}';
  }
}
