/// LES DROITS SUR LE TÉLÉPHONE (Direction, 10/11/2026) : le suivi de la matrice, évalué À CHAQUE affichage et à chaque geste.
///
/// Dart pur (aucun import Flutter hors `ChangeNotifier`) : l'évaluation est celle du poste (`MatriceMobile`, `packages/domaine`), jamais recopiée ici. Ce suivi ne tient
/// que l'ÉTAT : la graine d'origine, le rôle de l'agent (que la mère a fixé à l'appairage), les fiches reçues et la date de leur réception.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

/// Ce que l'écran lit : la matrice en force, le rôle, et QUAND la clinique a livré ses droits (`null` : droits d'origine, pas encore synchronisés).
class EtatDroits {
  const EtatDroits({required this.matrice, required this.role, this.majLe});
  final MatriceMobile matrice;
  final String? role;
  final DateTime? majLe;

  /// Vrai quand la mère a livré ses droits à ce téléphone (même sans modification : la graine est alors confirmée).
  bool get synchronises => majLe != null;
}

class SuiviDroits extends ValueNotifier<EtatDroits> {
  SuiviDroits(this.graine, {String? role}) : super(EtatDroits(matrice: MatriceMobile.graine(graine), role: role));

  final GraineDroits graine;
  String _signature = '';

  String? get role => value.role;

  /// Le rôle de l'agent appairé, tiré de SA fonction, fixée par la mère (E1600). Le changer ne vient jamais d'un réglage du téléphone.
  void definirRole(String? role) {
    if (role == value.role) return;
    value = EtatDroits(matrice: value.matrice, role: role, majLe: value.majLe);
  }

  /// Applique les fiches que la mère a livrées. Sans changement de contenu (même signature), l'écran n'est pas réveillé pour rien ; la date de réception, elle, avance.
  void appliquer({required Iterable<Map<String, Object?>> rbac, required Iterable<Map<String, Object?>> modulesActifs, DateTime? majLe}) {
    final r = [...rbac], m = [...modulesActifs];
    final signature = jsonEncode([r, m]);
    if (signature == _signature) {
      if (majLe != null && majLe != value.majLe) value = EtatDroits(matrice: value.matrice, role: value.role, majLe: majLe);
      return;
    }
    _signature = signature;
    value = EtatDroits(matrice: value.matrice.avecFiches(rbac: r, modulesActifs: m), role: value.role, majLe: majLe ?? value.majLe);
  }

  /// Voir l'écran du téléphone ? Évalué à l'instant de l'appel.
  bool peutVoir(String ecran) => value.matrice.peutVoir(value.role, ecran);

  /// Écrire dans l'écran du téléphone (commande d'écriture) ? Évalué à l'instant de l'appel.
  bool peutEditer(String ecran) => value.matrice.peutEditer(value.role, ecran);

  /// Refait le contrôle à un GESTE : refus nommé si le droit a été retiré depuis l'affichage.
  void exiger(String ecran, {bool ecriture = true}) {
    if (ecriture ? !peutEditer(ecran) : !peutVoir(ecran)) throw mobRefusDroitRetire(ecran, ecriture: ecriture);
  }
}
