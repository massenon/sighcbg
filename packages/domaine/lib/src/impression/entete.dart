import 'identite.dart';

/// Le papier à en-tête en TROIS ZONES (exigence P0-13, maquette Baguidi `print.js` `entete()` / `pied()`), composé UNE seule fois ici : l'aperçu de
/// `cfg-branding`, la feuille A4 de l'écran et le PDF lisent tous le même modèle, si bien que l'écran et la pièce ne peuvent pas diverger.
///
/// - zone GAUCHE (≈ 24 %) : le logo circulaire (≈ 2,4 cm) et, dessous, la devise ;
/// - zone CENTRALE : la dénomination, puis l'activité (« CENTRE DE MÉDECINE DU TRAVAIL, MÉDECINE GÉNÉRALE ») ;
/// - zone DROITE (≈ 30 %, alignée à droite, petits caractères) : [lignesDroite].
///
/// Sous l'en-tête, un DOUBLE FILET fin (rouge cœur puis, 2 px plus bas, bleu santé). Un champ vide n'imprime rien : ni ligne, ni libellé orphelin.
/// Rouleau 80 mm et badge CR80 n'en relèvent pas : ils gardent leur gabarit.
class EnteteTroisZones {
  const EnteteTroisZones._({required this.devise, required this.denomination, required this.sousTitre, required this.lignesDroite, required this.piedLegal, required this.editeDepuis});

  /// Part de la largeur de la zone gauche et de la zone droite (la centrale prend le reste).
  static const double partGauche = 0.24, partDroite = 0.30;

  /// Diamètre du logo, en centimètres.
  static const double logoCm = 2.4;

  /// Épaisseur de chaque filet et écart entre les deux, en pixels logiques (points PDF).
  static const double filetPx = 2, interFiletPx = 2;

  /// Corps de la dénomination (≈ 19 px de la maquette) et des petits caractères de la zone droite.
  static const double corpsDenomination = 19, corpsDroite = 9, corpsSousTitre = 10, corpsDevise = 11;

  factory EnteteTroisZones.depuis(IdentiteImprimee i) {
    final ifu = i.ifu.isEmpty ? '' : (i.ifuDate.isEmpty ? 'IFU : ${i.ifu}' : 'IFU : ${i.ifu} du ${i.ifuDate}');
    final lieu = [i.adresse, i.pays].where((p) => p.isNotEmpty).join(' — ');
    final lignes = [
      i.bp,
      if (i.telephones.isNotEmpty) 'Téléphones : ${i.telephones.join(' / ')}',
      ifu,
      i.email.isEmpty ? '' : 'E-mail : ${i.email}',
      lieu,
      i.rccm.isEmpty ? '' : 'RCCM : ${i.rccm}',
      // Tant qu'elle est vide, l'autorisation d'ouverture n'est pas imprimée (aucun « Autorisation : » sans numéro).
      i.autorisation.isEmpty ? '' : 'Autorisation d’ouverture : ${i.autorisation}',
      i.enregistrement.isEmpty ? '' : 'N° d’enregistrement ONMB : ${i.enregistrement}',
    ];
    return EnteteTroisZones._(
      devise: i.slogan,
      denomination: i.nom,
      sousTitre: i.activite.toUpperCase(),
      lignesDroite: [for (final l in lignes) if (l.trim().isNotEmpty) l],
      piedLegal: [i.nom, if (i.ifu.isNotEmpty) 'IFU ${i.ifu}', if (i.rccm.isNotEmpty) 'RCCM ${i.rccm}'].where((p) => p.isNotEmpty).join(' — '),
      editeDepuis: 'Édité depuis le SIGH${i.sigle.isEmpty ? '' : '-${i.sigle}'}',
    );
  }

  final String devise, denomination, sousTitre;

  /// Les lignes de la zone droite, dans l'ordre de la maquette, SANS ligne vide.
  final List<String> lignesDroite;

  /// Pied : « dénomination — IFU — RCCM », sans mention vide.
  final String piedLegal;

  /// « Édité depuis le SIGH-CBG » (sigle lu de l'identité).
  final String editeDepuis;
}
