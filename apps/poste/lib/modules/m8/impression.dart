import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show IdentiteImprimee;

import '../../core/service_parametres.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/identite_poste.dart';
import '../../impression/piece.dart';
import '../../kit/acteur.dart';
import '../../shell/contexte_ecran.dart';
import 'commun.dart';

String _ref(ContexteEcran c) =>
    PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero());

/// L'EN-TÊTE D'UNE PIÈCE DE CAISSE EST CELUI DE SA DATE (`P.etat({date: f.date})`, Direction 06/11/2026) : une facture d'hier garde l'identité d'hier.
IdentiteImprimee _identite(ContexteEcran c, Fiche f) => identiteImprimeeDe(c.magasin, datePiece(f, c.aujourdhui));

/// Aperçu de la facture (ou pro-forma) : la pièce est établie à l'instant de l'impression, par l'agent connecté (RG-12).
Future<void> imprimerFacture(BuildContext ctx, Fiche f,
        {bool proforma = false, Fiche? jumelle}) =>
    afficherApercu(ctx, pieceFactureDe(ctx, f, proforma: proforma, jumelle: jumelle));

/// La pièce de la facture, telle qu'[imprimerFacture] l'imprime (extraite pour « Imprimer la sélection », une facture par page : même pièce, même en-tête de sa date).
PieceA4 pieceFactureDe(BuildContext ctx, Fiche f, {bool proforma = false, Fiche? jumelle}) {
  final c = ContexteEcran.of(ctx);
  return pieceFacture(f,
      proforma: proforma,
      // MECeF fermé (bascule P0-5) : la pièce imprimée ne porte pas le bloc fiscal ; l'en-tête légal (IFU, RCCM) reste.
      mecefActif: mecefEnService(c.magasin),
      jumelle: jumelle,
      utilisateur: acteur(c).nom,
      edite: c.aujourdhui,
      reference: _ref(c),
      identite: _identite(c, f));
}

Future<void> imprimerRecu(BuildContext ctx, Fiche f, {Fiche? versement}) => afficherApercu(ctx, pieceRecuDe(ctx, f, versement: versement));

/// Le reçu de caisse d'une facture, tel qu'[imprimerRecu] l'imprime (extrait pour « Imprimer la sélection », un reçu par page).
PieceA4 pieceRecuDe(BuildContext ctx, Fiche f, {Fiche? versement}) {
  final c = ContexteEcran.of(ctx);
  return pieceRecu(f, versement: versement, utilisateur: acteur(c).nom, edite: c.aujourdhui, reference: _ref(c), identite: _identite(c, f));
}

Future<void> imprimerEngagement(BuildContext ctx, Fiche f) {
  final c = ContexteEcran.of(ctx);
  return afficherApercu(
      ctx,
      pieceEngagement(f,
          utilisateur: acteur(c).nom,
          edite: c.aujourdhui,
          reference: _ref(c),
          joursEntreTranches: seuilClinique(c.magasin, 'caisse.pasEcheancierReliquatJours', c.aujourdhui),
          identite: _identite(c, f)));
}
