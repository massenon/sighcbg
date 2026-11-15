import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import '../modules/m14/commun_m14.dart' show rolesDe;

/// LA CONTINUITÉ DE SERVICE DES VALIDATIONS AU POSTE (Direction, 15/11/2026) : « une validation à faire ne doit JAMAIS empêcher le fileul de travailler ; le poste de la mère
/// n'est pas fait pour valider, c'est un poste qui porte la clinique ». Le moteur pur est `validation_deposee.dart` (domaine) ; ce service y branche le magasin, le journal et le
/// pont d'activité. UNE fabrique, pour les quinze familles de référentiels : pas un mécanisme par circuit.
///
///  * FILEUL rattaché : [deposer] écrit un DÉPÔT (collection `validationsDeposees`, famille A) au lieu de refuser « réglé sur la mère ». Le poste continue de travailler ; l'élément reste
///    « à valider » et l'écran dit « transmise à la mère, en attente » — jamais « validé » avant la confirmation. [reconcilier] donne une fois la SUITE du verdict : une notification
///    adressée à l'auteur (appliquée, sans effet, ou refusée avec son motif nommé).
///  * MÈRE : [demarrerMere] puis [traiter] — elle APPLIQUE chaque dépôt sous le rôle et le nom de son auteur, en refaisant tous les contrôles avec SES données, écrit la validation (les
///    mêmes traces que le geste direct), journalise (RG-12 : déposée par X, appliquée par la mère) et écrit le verdict sur la MÊME fiche, qui revient au fileul par le pont. Aucun humain
///    n'a à être assis devant la mère. Rejouable sans effet double (un élément déjà validé rend `sans_effet`).
class ServiceValidationsDeposees {
  ServiceValidationsDeposees._(this.magasin);
  static final Expando<ServiceValidationsDeposees> _instances = Expando('ServiceValidationsDeposees');
  static ServiceValidationsDeposees de(Magasin m) => _instances[m] ??= ServiceValidationsDeposees._(m);

  final Magasin magasin;

  /// L'étiquette de ce poste (rend unique l'identifiant d'un dépôt, reconnaît ses propres dépôts).
  String etiquette = 'P';

  /// Qui signe l'application (la mère) ; jamais anonyme (RG-12).
  String Function() auteurMere = () => 'Poste mère';

  DateTime Function()? horloge;
  DateTime get _maintenant => (horloge ?? magasin.horloge)();

  CollectionMagasin get depots => magasin.collection(valCollectionDepots);

  LectureValidation get _lire => (nom) => magasin.collection(nom).toutes;

  Map<String, String> get _libelles => {for (final r in rolesDe(magasin)) r.id: r.label};

  int _serie = 0;
  String _nouvelId() => 'VDP-$etiquette-${_maintenant.toUtc().millisecondsSinceEpoch.toRadixString(36)}-${(++_serie).toRadixString(36)}';

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // FILEUL : déposer, dire l'attente, donner la suite
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  /// DÉPOSE la validation d'un élément. Refus nommé (mêmes contrôles que le geste direct) ou le dépôt écrit ; un dépôt identique qui attend déjà la mère n'est pas doublé.
  VerdictDepot deposer(String famille, Object? id, {required String role, required String acteur, String? motif}) {
    final r = valDeposer(famille, '$id',
        role: role, acteur: acteur, poste: etiquette, maintenant: _maintenant, lire: _lire, libelles: _libelles, depots: depots.toutes, nouvelId: _nouvelId, motif: motif);
    if (!r.ok || r.dejaDepose) return r;
    try {
      depots.ajouterSansJournal(r.fiche!, enTete: true);
    } on EcritureRefusee catch (e) {
      return VerdictDepot.refus(RefusValidation('ECRITURE_REFUSEE', e.motif, null));
    }
    final f = valFamille(famille)!;
    _signaler(famille);
    magasin.journaliser('Validation transmise à la mère', f.module, f.libelle, '$id', null, {'déposée par': acteur, 'rôle': role, 'dépôt': r.fiche!['id'], if (motif != null && motif.trim().isNotEmpty) 'motif': motif.trim()});
    return r;
  }

  /// Les écrans lisent l'ÉLÉMENT (l'acte, la variable, le barème), pas le registre des dépôts : un dépôt ou un verdict doit les repeindre, faute de quoi la commande « Valider » resterait
  /// offerte après le dépôt et le badge « en attente de la mère » n'apparaîtrait qu'au prochain geste.
  void _signaler(String famille) {
    final f = valFamille(famille);
    if (f == null) return;
    for (final c in {...f.collections, valCollectionValidations}) {
      magasin.collection(c).signaler();
    }
  }

  /// L'état d'attente d'un élément (le dernier dépôt non résolu par une validation visible).
  EtatDepot? etatDepot(String famille, Object? id) => valEtatDepot(famille, '$id', depots.toutes);

  /// Donne UNE fois la suite du verdict de chaque dépôt de CE poste : une notification adressée à l'auteur. Idempotent (`notifieLe`). Rend le nombre de dépôts suivis.
  int reconcilier() {
    var n = 0;
    for (final d in [
      for (final d in depots.toutes)
        if (d['statut'] != 'archive' && '${d['demandePoste']}' == etiquette && d['etat'] != valDepotDeposee && d['notifieLe'] == null) d
    ]) {
      final etat = '${d['etat']}';
      final quoi = '« ${d['libelle'] ?? d['famille']} » (${d['cible']})';
      final (type, libelle, detail, priorite) = switch (etat) {
        valDepotAppliquee => ('validation_confirmee', 'Validation confirmée par la mère', '$quoi : votre validation est appliquée.', 'normale'),
        valDepotSansEffet => ('validation_confirmee', 'Validation déjà faite', '$quoi : ${d['resultatMotif'] ?? 'déjà validé'}', 'normale'),
        _ => ('validation_refusee', 'Validation refusée par la mère', '$quoi : ${d['resultatCode']} : ${d['resultatMotif']} ${d['resultatGeste'] ?? ''}'.trim(), 'haute'),
      };
      magasin.collection('notifications').inserer({
        'type': type,
        'poste': 'tous',
        'destinataire': d['demandePar'],
        'libelle': libelle,
        'detail': detail,
        'priorite': priorite,
        'reference': d['id'],
        'lue': false,
        'creeLe': _maintenant.toUtc().toIso8601String(),
        'statut': 'actif',
      }, prefixe: 'NOT');
      depots.mettreAJour(d['id'], {'notifieLe': _maintenant.toUtc().toIso8601String()}, journaliser: false);
      _signaler('${d['famille']}');
      n++;
    }
    return n;
  }

  Timer? _minuterieFileul;
  VoidCallback? _ecouteFileul;

  /// Démarre le suivi des verdicts (écoute de la collection et minuterie de sûreté).
  void demarrerFileul({Duration intervalle = const Duration(seconds: 4)}) {
    if (_ecouteFileul != null) return;
    _ecouteFileul = () => scheduleMicrotask(reconcilier);
    depots.addListener(_ecouteFileul!);
    _minuterieFileul = Timer.periodic(intervalle, (_) => reconcilier());
    reconcilier();
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // MÈRE : appliquer
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  bool _traitement = false;
  VoidCallback? _ecoute;
  Timer? _minuterie;

  /// Dernière erreur d'un tour (un verdict qui n'a pas pu s'écrire est repris au tour suivant).
  Object? derniereErreur;

  /// Démarre la mère : une écoute de la collection (un dépôt qui arrive par le pont est traité aussitôt) et une minuterie de sûreté.
  void demarrerMere({Duration intervalle = const Duration(seconds: 5)}) {
    if (_ecoute != null) return;
    _ecoute = () => scheduleMicrotask(traiter);
    depots.addListener(_ecoute!);
    _minuterie = Timer.periodic(intervalle, (_) => traiter());
    traiter();
  }

  void arreter() {
    if (_ecoute != null) depots.removeListener(_ecoute!);
    _ecoute = null;
    _minuterie?.cancel();
    _minuterie = null;
    if (_ecouteFileul != null) depots.removeListener(_ecouteFileul!);
    _ecouteFileul = null;
    _minuterieFileul?.cancel();
    _minuterieFileul = null;
  }

  /// Traite, dans l'ordre des gestes, chaque dépôt `deposee`. Rend le nombre de dépôts traités. Ré-entrance refusée : le verdict que l'on écrit rappelle l'écoute.
  int traiter() {
    if (_traitement) return 0;
    _traitement = true;
    var n = 0;
    try {
      final attente = [for (final d in depots.toutes) if (d['etat'] == valDepotDeposee && d['statut'] != 'archive') d]
        ..sort((a, b) => '${a['demandeLe']}${a['id']}'.compareTo('${b['demandeLe']}${b['id']}'));
      for (final d in attente) {
        final a = valAppliquerDepot(d, lire: _lire, libelles: _libelles, maintenant: _maintenant);
        if (a == null) continue;
        var etat = a.etat, code = a.code, motif = a.motif, geste = a.geste;
        final v = a.validation;
        if (v != null) {
          try {
            final col = magasin.collection(v.collection!);
            if (v.creation != null) {
              col.ajouterSansJournal(v.creation!);
            } else {
              col.mettreAJour(v.collection == valCollectionValidations ? 'VRF-${v.id}' : '${v.id}', v.patch, journaliser: false);
            }
            final j = v.journal!;
            magasin.journaliser(j.action, j.module, j.entite, j.reference, j.avant, {...j.apres, 'déposée par': d['demandePar'], 'appliquée par': auteurMere(), 'dépôt': d['id']});
          } on EcritureRefusee catch (e) {
            etat = valDepotRefusee;
            code = 'ECRITURE_REFUSEE';
            motif = e.motif;
            geste = 'Refaire la validation depuis l’écran du référentiel.';
          }
        }
        depots.mettreAJour(d['id'], {
          'etat': etat,
          'traiteLe': _maintenant.toUtc().toIso8601String(),
          'traitePar': auteurMere(),
          if (code != null) 'resultatCode': code,
          if (motif != null) 'resultatMotif': motif,
          if (geste != null) 'resultatGeste': geste,
        }, journaliser: false);
        n++;
      }
      derniereErreur = null;
    } catch (e) {
      derniereErreur = e;
    } finally {
      _traitement = false;
    }
    return n;
  }
}
