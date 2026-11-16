/// L'IMPRIMANTE DE CAISSE et l'ÉTAT DES DEUX MODES MECeF (Direction de Baguidi, 16/11/2026, `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md` §8, écarts E3760 à E3769).
///
/// L'imprimante de caisse est un RÉGLAGE DE CLINIQUE du registre des paramètres (famille `mecef`, réglé sous le geste `reglage_mecef`) en trois champs : le
/// modèle, la largeur du papier et l'interface. AUCUN modèle n'est fourni pour Baguidi : le modèle et l'interface sont semés VIDES et s'affichent « à
/// renseigner », marqués à valider ; la largeur est semée à 80 mm (le gabarit du ticket de caisse de la maquette, `P.ticket`), à valider elle aussi. Le réglage
/// DÉCRIT l'appareil ; il ne branche aucun pilote : le poste n'imprime le ticket que par l'aperçu et le PDF, à la largeur réglée.
///
/// L'état des modes dit, pour le boîtier physique et pour l'e-MECeF, ce qui est PRÊT au poste et ce qui MANQUE. Aucun adaptateur n'existe (lot M3) : les deux
/// modes restent « non configurés », aucun numéro de certification n'est simulé, une vente encaissée reste en attente de certification.
library;

import 'mode.dart';

/// Les clés du réglage de l'imprimante de caisse (registre `definitionsParametres`, famille `mecef`).
const String cleImprimanteModele = 'mecef.imprimanteCaisse.modele';
const String cleImprimanteLargeurPapier = 'mecef.imprimanteCaisse.largeurPapierMm';
const String cleImprimanteInterface = 'mecef.imprimanteCaisse.interface';

/// La largeur semée (mm) : celle du rouleau de caisse de la maquette. Une valeur d'attente, à valider par la clinique.
const int imprimanteLargeurDefautMm = 80;

/// Les bornes d'une largeur de papier lisible par l'aperçu (mm). Hors bornes, la valeur réglée est signalée et le ticket garde [imprimanteLargeurDefautMm].
const int imprimanteLargeurMinMm = 40;
const int imprimanteLargeurMaxMm = 120;

/// Le texte affiché pour un champ que la clinique n'a pas renseigné (jamais un modèle supposé).
const String imprimanteARenseigner = 'à renseigner';

/// L'imprimante de caisse EN VIGUEUR, lue des trois réglages : `null` pour un champ non renseigné.
class ImprimanteCaisse {
  const ImprimanteCaisse({this.modele, required this.largeurMm, this.interface, this.largeurReglee});

  /// Le modèle réglé, `null` tant qu'il n'est pas renseigné.
  final String? modele;

  /// La largeur appliquée au ticket (mm) : la valeur réglée si elle est lisible, sinon [imprimanteLargeurDefautMm].
  final int largeurMm;

  /// L'interface réglée (texte libre : la clinique la décrit, rien n'est proposé d'office), `null` tant qu'elle n'est pas renseignée.
  final String? interface;

  /// La valeur réglée telle que lue, quand elle n'a pas pu être appliquée (hors bornes, illisible) ; `null` sinon.
  final Object? largeurReglee;

  /// Vrai tant que le modèle ou l'interface reste à renseigner : l'écran le marque « à valider ».
  bool get aRenseigner => modele == null || interface == null;

  /// La largeur réglée n'a pas pu être appliquée : l'écran le dit.
  bool get largeurIgnoree => largeurReglee != null;

  String get modeleAffiche => modele ?? imprimanteARenseigner;
  String get interfaceAffichee => interface ?? imprimanteARenseigner;

  /// La ligne courte portée par l'aperçu du ticket.
  String get resume => 'Imprimante de caisse : $modeleAffiche — papier $largeurMm mm — interface : $interfaceAffichee';
}

String? _texte(Object? v) {
  final t = v is String ? v.trim() : '';
  return t.isEmpty ? null : t;
}

/// L'imprimante en vigueur d'après les trois valeurs LUES en base (jamais un défaut supposé ici, sauf la largeur du gabarit quand la valeur est illisible).
ImprimanteCaisse imprimanteCaisseEnVigueur({Object? modele, Object? largeur, Object? interface}) {
  final l = largeur is num ? largeur : num.tryParse('${largeur ?? ''}'.replaceAll(',', '.'));
  final lisible = l != null && l == l.roundToDouble() && l >= imprimanteLargeurMinMm && l <= imprimanteLargeurMaxMm;
  return ImprimanteCaisse(
    modele: _texte(modele),
    interface: _texte(interface),
    largeurMm: lisible ? l.toInt() : imprimanteLargeurDefautMm,
    largeurReglee: lisible || largeur == null ? null : largeur,
  );
}

/// Ce qui est prêt et ce qui manque pour un mode de certification.
class EtatModeMecef {
  const EtatModeMecef({required this.mode, required this.pret, required this.manque});
  final String mode;
  final List<String> pret;
  final List<String> manque;
  String get libelle => mecefLibellesModes[mode] ?? mode;

  /// Aucun adaptateur n'est livré (lot M3) : aucun mode n'est configuré, quoi qu'on règle.
  bool get configure => false;
}

/// L'état des DEUX modes, pour l'écran : le modèle du boîtier lu en base ([modeleBoitier], `null` s'il n'est pas renseigné). Rien n'est affirmé de l'appareil
/// au-delà de son nom : les pièces à obtenir sont celles de `docs/guides/MECEF-BOITIER-ELTRADE-CC300.md`.
List<EtatModeMecef> mecefEtatsDesModes({String? modeleBoitier}) {
  const communs = [
    'Point d’extension de l’adaptateur (interface AdaptateurMecef) : l’adaptateur réel s’y branchera.',
    'Vente encaissée puis tenue « en attente de certification » (refus nommé MECEF_NON_CONFIGURE), sans aucun numéro simulé.',
    'Retransmission d’une vente en attente, sans consommer l’unique essai du caissier.',
  ];
  return [
    EtatModeMecef(mode: 'boitier', pret: [
      if (modeleBoitier != null) 'Modèle du boîtier réglé : $modeleBoitier (nommé à l’écran, sur la pièce et au journal MECeF).',
      ...communs,
    ], manque: [
      if (modeleBoitier == null) 'Modèle du boîtier : à renseigner.',
      '${mecefMentionAdaptateurBoitier(modeleBoitier)[0].toUpperCase()}${mecefMentionAdaptateurBoitier(modeleBoitier).substring(1)} : manuel d’intégration, interface et pilote, protocole, simulateur, agrément DGI.',
      'Émission asynchrone de la normalisation (lot M3), à écrire avec l’adaptateur.',
    ]),
    EtatModeMecef(mode: 'emecef', pret: communs, manque: const [
      'Dossier d’interface de la DGI (adresse, authentification, format des messages) : non remis, rien n’est supposé.',
      'Adaptateur e-MECeF (lot M3), à écrire avec ce dossier.',
    ]),
  ];
}
