import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/service_parametres.dart';
import '../donnees/magasin.dart';

/// LES TÂCHES DU CIRCUIT D'ACHAT, NÉES DE L'ÉTAT DU BON (Direction, 16/11/2026).
///
/// Une notification de poste est LOCALE au poste qui l'écrit : celle que l'arbitrage de la DAF écrivait sur SON poste n'arrivait jamais au comptable ni au gestionnaire de stock, qui
/// travaillent ailleurs. Désormais le bon voyage (pont d'activité) et CHAQUE poste fait naître, depuis le bon accordé qu'il détient, les deux tâches que la validation promet — celle du
/// comptable (engagement et décaissement) et celle du gestionnaire de stock (achat ou distribution) —, plus la suite du verdict à l'AUTEUR du besoin (accordé, rejeté avec son motif,
/// complément demandé). Le geste n'a pas à être fait sur le poste du destinataire : c'est l'ÉTAT qui informe.
///
/// IDEMPOTENT : une tâche est reconnue par son type, son poste, sa référence et son verdict (`cle`) ; relancer le service n'en écrit aucune seconde. Fenêtre de [fenetreJours] jours
/// sur la date de l'arbitrage : un poste resté éteint plus longtemps ne rejoue pas d'anciennes décisions (le jeu de démonstration, daté de mois passés, ne bruite pas la cloche).
class ServiceCircuitAchats {
  ServiceCircuitAchats._(this.magasin);
  static final Expando<ServiceCircuitAchats> _instances = Expando('ServiceCircuitAchats');
  static ServiceCircuitAchats de(Magasin m) => _instances[m] ??= ServiceCircuitAchats._(m);

  final Magasin magasin;
  /// La fenêtre en vigueur (jours) : le paramètre `achats.fenetreCircuitJours`.
  int get fenetreJours => seuilClinique(magasin, 'achats.fenetreCircuitJours', _maintenant);

  DateTime Function()? horloge;
  DateTime get _maintenant => (horloge ?? magasin.horloge)();

  bool _enCours = false;
  VoidCallback? _ecoute;
  Timer? _minuterie;

  /// Écrit les tâches manquantes ; rend le nombre de notifications ajoutées.
  int reconcilier() {
    if (_enCours) return 0;
    _enCours = true;
    var n = 0;
    try {
      final notes = magasin.collection('notifications');
      final deja = <String>{
        for (final x in notes.toutes)
          if (x['cle'] != null) '${x['cle']}'
      };
      final limite = _maintenant.subtract(Duration(days: fenetreJours));
      for (final b in magasin.collection('besoins').actives) {
        final etat = '${b['etape']}';
        if ((rangCircuit('besoins', etat) ?? 0) < 4) continue;
        final quand = DateTime.tryParse('${b['arbitreLe'] ?? ''}');
        if (quand == null || quand.isBefore(limite)) continue;
        final ref = '${b['reference']}';
        final cle0 = cleCircuit(b);
        void ecrire(String cle, Map<String, Object?> nt) {
          if (deja.contains(cle)) return;
          deja.add(cle);
          notes.inserer({
            'type': nt['type'],
            'poste': nt['poste'] ?? 'tous',
            'destinataire': nt['destinataire'],
            'libelle': nt['libelle'],
            'detail': nt['detail'],
            'priorite': nt['priorite'] ?? 'normale',
            'reference': nt['reference'],
            'cle': cle,
            'lue': false,
            'creeLe': _maintenant.toIso8601String(),
            'statut': 'actif',
          }, prefixe: 'NOT');
          n++;
        }

        // Les deux postes informés par la validation : le comptable ET le gestionnaire de stock.
        if (!const ['rejete', 'complement'].contains(etat)) {
          for (final nt in notificationsDeBesoinAccorde(b, destinataires: destinatairesBesoinAccorde(magasin, _maintenant))) {
            ecrire('circuit:besoin_accorde:$cle0:${nt['poste']}', nt);
          }
        }
        // La suite du verdict à l'auteur : jamais perdue, motif compris.
        if (b['demandeur'] != null && '${b['demandeur']}'.isNotEmpty && const ['accorde', 'rejete', 'complement'].contains(etat)) {
          final motif = '${b['motifArbitrage'] ?? ''}'.trim();
          final (libelle, priorite) = switch (etat) {
            'accorde' => ('Votre besoin $ref est accordé', 'normale'),
            'rejete' => ('Votre besoin $ref est rejeté', 'haute'),
            _ => ('Complément demandé sur votre besoin $ref', 'haute'),
          };
          ecrire('circuit:besoin_verdict:$cle0:$etat', {
            'type': 'besoin_verdict',
            'poste': 'tous',
            'destinataire': b['demandeur'],
            'libelle': libelle,
            'detail': '${b['arbitrePar'] ?? 'La DAF'}${motif.isEmpty ? '' : ' : $motif'}',
            'priorite': priorite,
            'reference': ref,
          });
        }
      }
    } finally {
      _enCours = false;
    }
    return n;
  }

  /// Écoute les bons (un arbitrage reçu par le pont est traité aussitôt) et relit toutes les [intervalle] par sûreté.
  void demarrer({Duration intervalle = const Duration(seconds: 6)}) {
    if (_ecoute != null) return;
    _ecoute = () => scheduleMicrotask(reconcilier);
    magasin.collection('besoins').addListener(_ecoute!);
    _minuterie = Timer.periodic(intervalle, (_) => reconcilier());
    reconcilier();
  }

  void arreter() {
    if (_ecoute != null) magasin.collection('besoins').removeListener(_ecoute!);
    _ecoute = null;
    _minuterie?.cancel();
    _minuterie = null;
  }
}
