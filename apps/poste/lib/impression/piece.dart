import 'package:sigh_domaine/sigh_domaine.dart';

/// Une ligne de signature d'une pièce. Le NOM n'est jamais écrit dans le code : une signature qui porte une [qualite] (`PaiQualite`) et pas de nom reçoit,
/// à l'aperçu et au PDF (`afficherApercu`), le nom de l'agent qui porte cette qualité au dossier du personnel ; sans titulaire, la pièce imprime une
/// ligne de signature sans nom, que l'on signe à la main.
class Signature {
  const Signature(this.role, {this.nom, this.mention = 'Signature', this.qualite});
  final String role;
  final String? nom;
  final String mention;
  final PaiQualite? qualite;

  /// La même signature, avec le nom lu au personnel.
  Signature avecNom(String? n) => Signature(role, nom: n, mention: mention, qualite: qualite);

  /// Reste-t-il à lire le nom de cette signature au personnel ?
  bool get aResoudre => qualite != null && (nom == null || nom!.isEmpty);
}

/// Pièce A4 (`P.etat`) : en-tête légal UNIQUE (jamais passé par l'appelant), titre, filtres en force, contenu tabulaire dont le total est
/// calculé, lieu et date, signatures, pied normalisé (utilisateur, date/heure, identifiant). Une seule description pour l'aperçu ET le PDF.
/// Un bloc de contenu d'une pièce, dans l'ordre d'impression : le même ordre sert l'aperçu et le PDF.
sealed class BlocPiece {
  const BlocPiece();
}

class BlocTableau extends BlocPiece {
  const BlocTableau(this.tableau, {this.titre, this.alerte = false});
  final TableauEtat tableau;

  /// Intertitre (« Prestations réglées », « Reste à régler ») ; `alerte` le met en rouge.
  final String? titre;
  final bool alerte;
}

class BlocTexte extends BlocPiece {
  const BlocTexte(this.texte, {this.gras = false, this.italique = false});
  final String texte;
  final bool gras;
  final bool italique;
}

class PieceA4 {
  PieceA4({
    required this.titre,
    required this.reference,
    required this.utilisateur,
    required this.edite,
    this.sousTitre,
    List<TableauEtat> tableaux = const [],
    List<BlocPiece> blocs = const [],
    this.cartouche = const [],
    this.filtres = const [],
    this.signatures = const [],
    this.lieuDate = true,
    this.filigrane,
    this.identite,
  }) : blocs = [...blocs, for (final t in tableaux) BlocTableau(t)];

  /// L'IDENTITÉ LÉGALE que la pièce imprime (en-tête et pied) : la version en force À LA DATE DE LA PIÈCE (`P.etat({date})`, Direction 06/11/2026). Une
  /// facture, un avoir ou un reçu la fixent à leur date ; `null` : l'aperçu la résout à la date d'édition depuis le magasin (sans magasin, la semence).
  final IdentiteImprimee? identite;

  /// La même pièce, avec son identité fixée.
  PieceA4 avecIdentite(IdentiteImprimee i) => PieceA4(
      titre: titre,
      reference: reference,
      utilisateur: utilisateur,
      edite: edite,
      sousTitre: sousTitre,
      blocs: blocs,
      cartouche: cartouche,
      filtres: filtres,
      signatures: signatures,
      lieuDate: lieuDate,
      filigrane: filigrane,
      identite: i);

  /// La même pièce, avec ses signatures lues au personnel (voir [Signature.qualite]) : le nom d'un signataire vient du dossier du personnel, jamais du code.
  PieceA4 avecSignatures(Iterable<Map<String, Object?>> personnel) => !signatures.any((s) => s.aResoudre)
      ? this
      : PieceA4(
          titre: titre,
          reference: reference,
          utilisateur: utilisateur,
          edite: edite,
          sousTitre: sousTitre,
          blocs: blocs,
          cartouche: cartouche,
          filtres: filtres,
          signatures: [for (final s in signatures) s.aResoudre ? s.avecNom(paiSignataire(personnel, s.qualite!)) : s],
          lieuDate: lieuDate,
          filigrane: filigrane,
          identite: identite);

  /// L'identité effectivement imprimée : celle fixée, sinon la semence.
  IdentiteImprimee get identiteImprimee => identite ?? IdentiteImprimee.semence;

  final String titre;
  final String? sousTitre;
  final List<BlocPiece> blocs;

  /// Cartouche d'en-tête de pièce : (libellé, valeur), sur deux colonnes.
  final List<(String, String)> cartouche;

  /// Filtres appliqués à l'état, (libellé, valeur) : un état tiré d'un écran filtré ne montre qu'une PARTIE des données, et doit le dire.
  final List<(String, String)> filtres;
  final List<Signature> signatures;
  final bool lieuDate;
  final String? filigrane;
  final String reference;
  final String utilisateur;
  final DateTime edite;

  /// Référence `CBG-AAAAMMJJ-NNNN`, préfixée du sigle de la clinique (`compteur` s'incrémente à chaque édition, comme la maquette).
  static String reference_(DateTime d, int compteur) =>
      '${IdentiteClinique.sigle}-${iso(d).replaceAll('-', '')}-${compteur.toString().padLeft(4, '0')}';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// FICHE DOCUMENTAIRE PAYSAGE : le gabarit des fiches de la clinique qui ne sont pas des états tabulaires (organigramme, procédures, fiches de poste…).
// Cartouche à quatre cases (logo · titre en deux étages · référence/date/version/page), contenu libre, pied normalisé. Une seule description pour l'aperçu
// (`FeuilleFichePaysage`) ET le PDF (`pdfFichePaysage`) : ni l'un ni l'autre ne porte une cote, elles sont toutes ici.
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Une page de fiche paysage.
sealed class PageFiche {
  const PageFiche();
}

/// Le graphe de l'organigramme, dessiné depuis la scène que le domaine a bâtie sur les fiches de postes.
class PageGraphe extends PageFiche {
  const PageGraphe(this.scene);
  final SceneOrganigramme scene;
}

/// Une page de légende : une ligne par abréviation, le code en gras suivi de son sens.
class PageLegende extends PageFiche {
  const PageLegende(this.lignes);
  final List<LigneLegende> lignes;
}

/// Les cotes du gabarit paysage (A4 297 × 210 mm), en millimètres. UN seul jeu pour les deux rendus.
class GabaritFichePaysage {
  const GabaritFichePaysage();
  double get largeur => 297;
  double get hauteur => 210;
  double get margeHaut => 8;
  double get margeCote => 6;
  double get margeBas => 7;

  /// Cartouche : largeur centrée, hauteur, part des trois colonnes (logo, titre, références) et parts des deux étages du titre / des quatre lignes de droite.
  double get cartoucheLargeur => 213;
  double get cartoucheHauteur => 21;
  List<int> get colonnes => const [12, 69, 19];
  List<int> get etagesTitre => const [55, 45];
  List<int> get lignesDroite => const [34, 26, 23, 24];

  /// Écart entre le cartouche et le contenu ; hauteur réservée au pied (deux lignes d'adresse, la mention, la ligne de traçabilité).
  double get ecartContenu => 3;
  double get hauteurPied => 17;

  /// La zone du graphe : sous le cartouche, au-dessus du pied.
  double get zoneLargeur => largeur - 2 * margeCote;
  double get zoneHauteur => hauteur - margeHaut - cartoucheHauteur - ecartContenu - hauteurPied - margeBas;

  /// Habillage des cases : marges du libellé clair dans la case foncée, en unités de grille, épaisseur du bord ; trait fin du graphe en millimètres.
  double get insetX => 12;
  double get insetY => 6;
  double get bordUnites => 4;
  double get traitMm => 0.22;

  /// Légende : retrait gauche (aligné sur le cartouche), haut, hauteur de ligne, corps (points).
  double get legendeGauche => (largeur - cartoucheLargeur) / 2;
  double get legendeHaut => 9;
  double get legendeLigne => 7.4;
  double get legendeCorps => 11;
}

class FichePaysage {
  FichePaysage({
    required this.fiche,
    required this.pages,
    required this.reference,
    required this.utilisateur,
    required this.edite,
    required this.identite,
  });

  /// Les paramètres de la fiche, lus en base (référence, date, version, titres, mention).
  final ParametresFiche fiche;
  final List<PageFiche> pages;

  /// Identifiant unique de l'édition (`CBG-AAAAMMJJ-NNNN`).
  final String reference;
  final String utilisateur;
  final DateTime edite;
  final IdentiteImprimee identite;

  String get titre => '${fiche.titreHaut} — ${fiche.titre}';

  /// Les quatre lignes du cartouche pour la page [i] (0 = première) : « Page n sur N » vient du nombre RÉEL de pages.
  List<String> cartouche(int i) => fiche.lignesCartouche(i + 1, pages.length);

  /// Les deux lignes d'identité du pied, lues de l'IDENTITÉ de la clinique, jamais recopiées : dénomination, boîte postale, téléphones / IFU, e-mail.
  List<String> get pied {
    final tel = identite.telephones.isEmpty ? '' : 'TEL : ${identite.telephones.join(' / ')}';
    return [
      [identite.nom, identite.bp, tel].where((p) => p.trim().isNotEmpty).join(' - '),
      [if (identite.ifu.isNotEmpty) 'IFU : ${identite.ifu}', if (identite.email.isNotEmpty) 'Email : ${identite.email}'].join(' - '),
    ];
  }

  /// La ligne de traçabilité (utilisateur, date et heure, identifiant) : la mention normalisée de toute pièce éditée.
  String get tracabilite => 'Document généré par $utilisateur le ${dateHeure(edite)} — Réf. document : $reference — ${EnteteTroisZones.depuis(identite).editeDepuis}';
}
