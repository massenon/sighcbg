/// LES PRIX EN DOUBLON À ARBITRER (décision de la Direction du 16/11/2026).
///
/// Le catalogue de départ porte parfois le MÊME code de prestation sur deux lignes aux prix différents (Baguidi : `CERT-APT`, « Certificat médical d'aptitude » à 7 000 et « Certificat d'aptitude »
/// à 5 000, E2578). La caisse continue de lire la PREMIÈRE ligne, sans blocage, tant que la Direction n'a pas choisi. Le choix est un ARBITRAGE : « Garder celui-ci » ARCHIVE l'autre (RG-14,
/// jamais supprimé, avec motif et auteur) et, quand le prix gardé n'est pas celui que le référentiel lit, en propose la version datée par le circuit ordinaire (le geste de décider).
///
/// La détection est GÉNÉRIQUE : tout code porté deux fois par des fiches actives d'une même liste de départ (`catalogueTarifs`, `actes`) avec des prix DIFFÉRENTS est proposé à l'arbitrage ;
/// deux lignes de même code ET de même prix ne sont pas un conflit (rien à choisir). Les fiches sont passées en argument : aucune lecture d'une base, aucune horloge.
library;

typedef FicheDoublon = Map<String, Object?>;

/// Les listes de départ où un code ne devrait paraître qu'une fois : (collection, espace de code du référentiel : `grille` ou `acte`).
const Map<String, String> tarListesDeDepart = {'catalogueTarifs': 'grille', 'actes': 'acte'};

/// Le prix non assuré qu'une fiche de départ porte (`prixNonAssure`, à défaut `prix`) et son prix assuré.
num? tarPrixNADe(FicheDoublon f) => (f['prixNonAssure'] ?? f['prix']) as num?;
num? tarPrixADe(FicheDoublon f) => f['prixAssure'] as num?;

String _cle(FicheDoublon f) => '${tarPrixNADe(f)}|${tarPrixADe(f)}';

/// Un code porté par plusieurs fiches de prix différents. [candidats] : de la première (celle que la caisse lit) à la dernière.
class TarDoublonPrix {
  const TarDoublonPrix({required this.collection, required this.code, required this.candidats});
  final String collection;
  final String code;
  final List<FicheDoublon> candidats;

  /// L'identité stable d'une ligne de la file d'arbitrage.
  String get cle => '$collection/$code';
}

/// Les doublons de prix d'une liste de départ. [fiches] : les fiches de la collection (les archivées sont ignorées : un doublon arbitré cesse d'en être un).
List<TarDoublonPrix> tarDoublonsPrix(String collection, Iterable<FicheDoublon> fiches) {
  final parCode = <String, List<FicheDoublon>>{};
  for (final f in fiches) {
    if (f['statut'] == 'archive' || '${f['code'] ?? ''}'.isEmpty) continue;
    (parCode['${f['code']}'] ??= []).add(f);
  }
  return [
    for (final e in parCode.entries)
      if (e.value.length > 1 && e.value.map(_cle).toSet().length > 1) TarDoublonPrix(collection: collection, code: e.key, candidats: e.value),
  ];
}

/// Ce que l'arbitrage donne à ÉCRIRE : les fiches à archiver et, quand le prix gardé diffère de celui que le référentiel lit, le prix à proposer. Un refus se nomme.
class TarArbitrageDoublon {
  const TarArbitrageDoublon.refus(String this.code, String this.motif, String this.geste)
      : ok = false,
        garde = null,
        aArchiver = const [],
        prixAProposer = null;
  const TarArbitrageDoublon.ok({required FicheDoublon this.garde, required this.aArchiver, this.prixAProposer})
      : ok = true,
        code = null,
        motif = null,
        geste = null;
  final bool ok;
  final String? code, motif, geste;
  final FicheDoublon? garde;

  /// Les fiches des autres candidats : archivées avec le motif, jamais supprimées.
  final List<FicheDoublon> aArchiver;

  /// `{prixNonAssure, prixAssure?, etatAssure}` à proposer au référentiel (décidé en un geste par celui qui arbitre) ; `null` : le référentiel lit déjà ce prix.
  final Map<String, Object?>? prixAProposer;
}

/// ARBITRE : garder la fiche [gardeId] du doublon [doublon]. [prixEnVigueurNA] / [prixEnVigueurA] : le prix que le référentiel lit aujourd'hui pour ce code (`null` : aucun) ; [peutDecider] : le geste
/// réservé « décider un prix » (la Direction, la DAF, l'administrateur : lu de la matrice par l'appelant, jamais une liste de rôles ici).
/// Refus nommés : `ARBITRAGE_RESERVE` (le geste manque), `MOTIF_REQUIS` (RG-12), `CANDIDAT_INCONNU`.
TarArbitrageDoublon tarArbitrerDoublon(
  TarDoublonPrix doublon, {
  required Object? gardeId,
  required String motif,
  required bool peutDecider,
  num? prixEnVigueurNA,
  num? prixEnVigueurA,
  bool assureEnVigueurMontant = true,
}) {
  if (!peutDecider) {
    return const TarArbitrageDoublon.refus('ARBITRAGE_RESERVE', 'choisir le bon prix revient au profil qui décide les prix (geste réservé de la matrice) : l’arbitrage n’est pas une modification de fiche',
        'Demander l’arbitrage à la Direction ou à la Directrice Administrative.');
  }
  if (motif.trim().isEmpty) {
    return const TarArbitrageDoublon.refus('MOTIF_REQUIS', 'le motif de l’arbitrage est obligatoire (RG-12) : il explique pourquoi l’autre ligne est archivée', 'Dites pourquoi ce prix est le bon.');
  }
  final garde = doublon.candidats.where((f) => f['id'] == gardeId).firstOrNull;
  if (garde == null) {
    return const TarArbitrageDoublon.refus('CANDIDAT_INCONNU', 'cette ligne n’est pas un des candidats de ce code', 'Choisissez une des lignes proposées.');
  }
  final na = tarPrixNADe(garde), pa = tarPrixADe(garde);
  final autres = [for (final f in doublon.candidats) if (f['id'] != gardeId) f];
  final identique = prixEnVigueurNA == na && (pa == null || prixEnVigueurA == pa || !assureEnVigueurMontant);
  return TarArbitrageDoublon.ok(
    garde: garde,
    aArchiver: autres,
    prixAProposer: identique || na == null
        ? null
        : {'prixNonAssure': na, if (pa != null) 'prixAssure': pa, 'etatAssure': pa != null ? 'montant' : 'unique'},
  );
}
