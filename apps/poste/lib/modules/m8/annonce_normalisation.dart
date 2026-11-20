import 'package:flutter/material.dart';

import '../../donnees/normalisation_mecef.dart';
import '../../kit/kit.dart';

/// CE QUE LA NORMALISATION A RENDU, DIT AU GUICHET (E2299), pour les trois portes d'encaissement (émission, registre des paiements, file de caisse).
///
/// TOUTE VENTE EST NORMALISÉE à la clinique (Direction, 07/11/2026). LA FACTURE D'UN PATIENT NE PORTE NI ACHETEUR NI AIB (Direction de Baguidi, 16/11/2026,
/// E3770) : la fenêtre « Facture normalisée » (IFU de l'acheteur, Nom de l'acheteur, Situation de l'acheteur pour l'AIB) qui vivait dans ce fichier a disparu
/// des trois portes ; le patient paie le total et la pièce est normalisée sans acheteur. Le moteur de l'acheteur au barème reste au domaine
/// (`acheteurNormaliseAuBareme`) pour une vente à un tiers payeur, qu'aucune porte n'émet aujourd'hui ; la retenue d'AIB d'un fournisseur vit en M7.
///
/// Une pièce refusée se DIT, avec son code, son motif et son geste. Rien à dire en mode désactivé.
void annoncerNormalisation(BuildContext ctx, ResultatNormalisation? n) {
  if (n == null || n.ignore) return;
  if (n.ok) {
    ToastsSigh.afficher(ctx, 'Vente normalisée : ${n.numero}.',
        type: TypeToast.succes,
        detail: 'Numéro déjà porté par la pièce : il n’est jamais réécrit (lot L3 : le poste ne fabrique aucun numéro).');
    return;
  }
  ToastsSigh.afficher(ctx,
      'Normalisation non aboutie (${n.code}) : la vente est encaissée mais pas normalisée.',
      type: TypeToast.attention,
      detail: '${n.motif} ${n.geste}',
      duree: const Duration(seconds: 12));
}
