import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/matrice_vive.dart';
import '../donnees/magasin.dart';
import '../donnees/tarifs_poste.dart';
import '../modules/m14/commun_m14.dart' show rolesDe;

/// L'APPLICATION DES DEMANDES DE PRIX SUR LA MÈRE, BRANCHÉE (lot TAR, PRD-TARIFS). La clinique sœur avait écrit `TarifsPoste.appliquerDemandes()` sans jamais l'appeler en
/// production : un fileul déposait sa proposition, la mère ne la lisait jamais. Ici le traitement est démarré par `main.dart` au démarrage de la mère, comme celui des demandes
/// d'import et des décisions de droits, et un test le prouve à travers la vraie mère Dart (`tarifs_sync_test.dart`).
///
/// Un fileul DÉPOSE (famille B, `propositionsTarif`) ; la mère, seule autorité (famille R), refait les mêmes contrôles sous le RÔLE et le NOM de l'auteur de la demande, avec
/// SA matrice en force (gestes réservés compris : aucun nom de rôle n'est écrit ici), écrit la version ou la décision, puis le verdict (`appliquee` ou `refusee`, code, motif,
/// geste) sur la même fiche, qui revient au fileul par le pont d'activité. Un seul applicateur par magasin.
class ApplicateurDemandesTarif {
  ApplicateurDemandesTarif._(this.magasin);
  static final Expando<ApplicateurDemandesTarif> _instances = Expando('ApplicateurDemandesTarif');
  static ApplicateurDemandesTarif de(Magasin m) => _instances[m] ??= ApplicateurDemandesTarif._(m);

  final Magasin magasin;

  /// L'étiquette du poste mère, qui rend unique l'identifiant d'une demande.
  String etiquette = 'M';

  /// Qui signe le traitement (la mère) ; jamais anonyme (RG-12).
  String Function() auteur = () => 'Poste mère';

  /// La matrice EN FORCE chez la mère (graine engendrée et décisions de droits superposées, relue à chaque appel).
  MatriceVive? matrice;

  DateTime Function()? horloge;

  VoidCallback? _ecoute;
  Timer? _minuterie;
  bool _traitement = false;

  CollectionMagasin get demandes => magasin.collection(tarCollectionDemandes);

  /// Les droits de la mère, relus à chaque tour : `TarifsPoste` ne garde rien en mémoire.
  TarifsPoste _poste() {
    final mv = matrice;
    final mat = mv?.matrice;
    return TarifsPoste(magasin,
        role: 'mere',
        auteur: auteur,
        fileul: false,
        libelles: {for (final r in rolesDe(magasin)) r.id: r.label},
        peutEditerEcran: false,
        peutEditerPour: mat == null ? null : (r) => mat.peutEditer(r, 'cfg-tarifs'),
        peutProposerPrixAchatPour: mat == null ? null : (r) => mat.peutEditer(r, 'm6-produits'),
        peutProposerReceptionPour: mat == null ? null : (r) => mat.peutEditer(r, 'm7-receptions'),
        gestes: () => DroitsGestes(fiches: magasin.collection('rbac').actives, estArchive: mat?.estArchive, ecranActif: mat?.ecranActif),
        horloge: horloge,
        etiquette: etiquette);
  }

  /// Démarre : une écoute de la collection (une demande qui arrive par le pont est traitée aussitôt) et une minuterie de sûreté (un verdict qui n'a pas pu être écrit est repris).
  void demarrer({Duration intervalle = const Duration(seconds: 5)}) {
    if (_ecoute != null) return;
    _ecoute = () => scheduleMicrotask(traiter);
    demandes.addListener(_ecoute!);
    _minuterie = Timer.periodic(intervalle, (_) => traiter());
    traiter();
  }

  void arreter() {
    if (_ecoute != null) demandes.removeListener(_ecoute!);
    _ecoute = null;
    _minuterie?.cancel();
    _minuterie = null;
  }

  /// Traite, dans l'ordre du dépôt, chaque demande `deposee`. Rend le nombre de demandes traitées dans ce tour. Ré-entrance refusée : le verdict que l'on écrit rappelle l'écoute.
  int traiter() {
    if (_traitement) return 0;
    _traitement = true;
    try {
      return _poste().appliquerDemandes();
    } finally {
      _traitement = false;
    }
  }
}
