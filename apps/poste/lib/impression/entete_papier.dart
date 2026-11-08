import 'package:flutter/material.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../shell/logo_clinique.dart';

/// L'en-tête légal en TROIS ZONES (P0-13) rendu en widgets : feuille A4 de l'écran ET aperçu de `cfg-branding`. La composition (quelles lignes, dans quel
/// ordre, lesquelles se taisent) vient d'[EnteteTroisZones] dans le domaine, que le PDF lit aussi : un seul modèle, trois rendus qui ne divergent pas.
///
/// Rouge cœur et bleu santé, anthracite : les jetons de la charte, aucune couleur en dur. Un champ vide n'imprime rien.
/// 2,4 cm en pixels logiques (1 mm = 96/25,4 px).
const double _logo = EnteteTroisZones.logoCm * 10 * 96 / 25.4;

class EnteteLegal extends StatelessWidget {
  const EnteteLegal({super.key, required this.identite, this.echelle = 1});
  final IdentiteImprimee identite;

  /// 1 pour la feuille ; moins pour l'aperçu en carte (les proportions sont celles de la pièce).
  final double echelle;

  @override
  Widget build(BuildContext context) {
    final e = EnteteTroisZones.depuis(identite);
    final k = echelle;
    final gauche = 100 * EnteteTroisZones.partGauche, droite = 100 * EnteteTroisZones.partDroite;
    return Column(key: const Key('impression:entete'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.only(bottom: 4 * k),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
              flex: gauche.round(),
              child: Padding(
                  padding: EdgeInsets.only(right: 8 * k),
                  child: Column(key: const Key('entete:gauche'), mainAxisSize: MainAxisSize.min, children: [
                    LogoClinique(largeur: _logo * k, hauteur: _logo * k),
                    if (e.devise.isNotEmpty)
                      Padding(
                          padding: EdgeInsets.only(top: 4 * k),
                          child: Text(e.devise,
                              key: const Key('entete:devise'),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontFamily: 'Dancing Script', fontSize: EnteteTroisZones.corpsDevise * k, height: 1.15, color: JetonsShell.coeur500))),
                  ]))),
          Expanded(
              flex: (100 - gauche - droite).round(),
              child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8 * k),
                  child: Column(key: const Key('entete:centre'), mainAxisSize: MainAxisSize.min, children: [
                    Text(e.denomination,
                        key: const Key('impression:entete:nom'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w700,
                            fontSize: EnteteTroisZones.corpsDenomination * k,
                            height: 1.2,
                            letterSpacing: -0.3,
                            color: JetonsShell.coeur500)),
                    if (e.sousTitre.isNotEmpty)
                      Padding(
                          padding: EdgeInsets.only(top: 2 * k),
                          child: Text(e.sousTitre,
                              key: const Key('entete:sous-titre'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: EnteteTroisZones.corpsSousTitre * k,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                  letterSpacing: 0.4,
                                  color: JetonsShell.anthracite900))),
                  ]))),
          Expanded(
              flex: droite.round(),
              child: Padding(
                  padding: EdgeInsets.only(left: 8 * k),
                  child: Column(key: const Key('entete:droite'), crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    for (final l in e.lignesDroite)
                      Text(l,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: EnteteTroisZones.corpsDroite * k,
                              height: 1.3,
                              fontWeight: l.startsWith('IFU') ? FontWeight.w600 : FontWeight.w400,
                              color: JetonsShell.slate700)),
                  ]))),
        ]),
      ),
      // Double filet fin : rouge cœur, puis 2 px plus bas bleu santé, pleine largeur.
      SizedBox(height: 4 * k),
      Container(key: const Key('entete:filet-coeur'), height: EnteteTroisZones.filetPx, color: JetonsShell.coeur500),
      const SizedBox(height: EnteteTroisZones.interFiletPx),
      Container(key: const Key('entete:filet-sante'), height: EnteteTroisZones.filetPx, color: JetonsShell.sante600),
    ]);
  }
}
