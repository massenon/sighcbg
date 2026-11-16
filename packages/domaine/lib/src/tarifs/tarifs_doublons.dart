/// LES PRIX EN DOUBLON À ARBITRER (décision de la Direction du 16/11/2026).
///
/// Le catalogue de départ porte parfois le MÊME code de prestation sur deux lignes aux prix différents (Baguidi : `CERT-APT`, « Certificat médical d'aptitude » à 7 000 et « Certificat d'aptitude »
/// à 5 000, E2578). La caisse continue de lire la PREMIÈRE ligne, sans blocage, tant que la Direction n'a pas choisi. Le choix est un ARBITRAGE : « Garder celui-ci » ARCHIVE l'autre (RG-14,
/// jamais supprimé, avec motif et auteur) et, quand le prix gardé n'est pas celui que le référentiel lit, en propose la version datée par le circuit ordinaire (le geste de décider).
///
/// La détection est GÉNÉRIQUE : tout code porté deux fois par des fiches actives d'une même liste de départ (`catalogueTarifs`, `actes`) avec des prix DIFFÉRENTS est proposé à l'arbitrage ;
/// deux lignes de même code ET de même prix ne sont pas un conflit (rien à choisir). Les fiches sont passées en argument : aucune lecture d'une base, aucune horloge.
library;

import 'tarifs.dart' show RefusTarif, tarNormaliserLibelle;

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

// ---------------------------------------------------------------------------------------------------------------------------------------------
// LA TROISIÈME ISSUE (décision Q18 de la Direction) : « ce sont deux prestations DISTINCTES »
// ---------------------------------------------------------------------------------------------------------------------------------------------
//
// Deux lignes de même code aux prix différents sont parfois DEUX prestations (« Certificat médical d'aptitude » 7 000 et « Certificat d'aptitude » 5 000). Ni « garder celui-ci » (qui archive l'autre,
// donc efface une prestation réelle) ni un prix à corriger : le code RESTE à la ligne que la caisse lit déjà (la première) ; chaque AUTRE ligne reçoit un NOUVEL identifiant, construit sur la convention
// des codes de la même famille et jamais réutilisé. Aucun prix ne change, aucune pièce émise n'est réécrite (elle garde son prix et son libellé). Le nouveau code naît « proposition à valider » :
// sa prestation est ouverte au référentiel avec le prix PROPRE de la ligne comme version PROPOSÉE (jamais validée ici), que la Direction décide par le circuit ordinaire.

/// Les mots de liaison qu'une désignation porte sans qu'ils distinguent une prestation d'une autre.
const Set<String> _motsVides = {'de', 'du', 'des', 'd', 'la', 'le', 'les', 'l', 'a', 'au', 'aux', 'et', 'ou', 'en', 'pour', 'un', 'une'};

/// Le préfixe de famille d'un code : tout ce qui précède le premier tiret, tiret compris (`CERT-APT` : `CERT-`) ; vide quand le code n'en porte pas.
String tarPrefixeDeCode(String code) {
  final i = code.indexOf('-');
  return i <= 0 ? '' : code.substring(0, i + 1);
}

/// La longueur de suffixe la plus FRÉQUENTE parmi les codes de la famille qui portent ce préfixe (la convention LUE, jamais supposée) ; [parDefaut] quand aucun ne le porte.
int tarLongueurSuffixeUsuelle(Iterable<String> codesFamille, String prefixe, {int parDefaut = 3}) {
  final nb = <int, int>{};
  for (final c in codesFamille) {
    if (prefixe.isEmpty || !c.startsWith(prefixe) || c.length == prefixe.length) continue;
    final n = c.length - prefixe.length;
    nb[n] = (nb[n] ?? 0) + 1;
  }
  if (nb.isEmpty) return parDefaut;
  final tri = nb.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : b.key.compareTo(a.key));
  return tri.first.key;
}

/// Les mots distinctifs d'une désignation : normalisés, sans mot vide, sans mot que la majorité des désignations de la famille porte déjà (« certificat », « médical »).
List<String> tarMotsDistinctifs(String libelle, Iterable<String> libellesFamille) {
  List<String> mots(String x) => [for (final w in tarNormaliserLibelle(x).split(RegExp(r"[ ']+"))) if (w.isNotEmpty && !_motsVides.contains(w)) w];
  final famille = [for (final l in libellesFamille) mots(l).toSet()];
  final seuil = famille.length / 2;
  final communs = <String>{
    for (final w in famille.expand((s) => s)) if (famille.where((s) => s.contains(w)).length > seuil) w
  };
  final propres = [for (final w in mots(libelle)) if (!communs.contains(w)) w];
  return propres.isEmpty ? mots(libelle) : propres;
}

/// Le NOUVEL identifiant d'une prestation distincte : préfixe de la famille (lu du code qu'elle quitte), puis les premières lettres de son mot distinctif, à la longueur usuelle des codes de la famille.
/// Quand le code obtenu est déjà pris (par un code, un alias ou une ligne de départ, archivés compris), il se DIFFÉRENCIE par un rang SÉPARÉ PAR UN TIRET (`CERT-APT-2`, `CERT-APT-3`…) :
/// c'est la seule règle ajoutée à la convention. Le tiret est celui que la Direction a fixé le 16/11/2026 pour le second certificat d'aptitude (« CERT-APT-2 ») : la règle de
/// construction suit la décision, pour toutes les familles (un rang se lit comme tel, il ne se confond pas avec le suffixe de la famille).
String tarCodeDistinct({
  required String codeActuel,
  required String libelle,
  required Iterable<String> codesFamille,
  required Iterable<String> libellesFamille,
  required Iterable<String> codesPris,
}) {
  final pris = {for (final c in codesPris) c.toUpperCase()};
  final prefixe = tarPrefixeDeCode(codeActuel);
  final n = tarLongueurSuffixeUsuelle(codesFamille, prefixe);
  final mots = tarMotsDistinctifs(libelle, libellesFamille);
  final mot = (mots.isEmpty ? 'x' : mots.last).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final base = mot.length >= n ? mot.substring(0, n) : mot.padRight(n, 'X');
  var candidat = '$prefixe$base';
  var rang = 1;
  while (pris.contains(candidat.toUpperCase())) {
    rang++;
    candidat = '$prefixe$base-$rang';
  }
  return candidat;
}

/// Une ligne qui reçoit un nouveau code : ce que le poste doit écrire (la prestation proposée, le code porté par la fiche de départ). Jamais une archive, jamais un prix modifié.
class TarNouvelleIdentite {
  const TarNouvelleIdentite({
    required this.ficheId,
    required this.ancienCode,
    required this.nouveauCode,
    required this.libelle,
    required this.famille,
    required this.prixNonAssure,
    required this.prixAssure,
    required this.etatAssure,
    this.secteur,
    this.assurable,
    this.prestationDecidee = false,
  });
  final Object? ficheId;
  final String ancienCode;
  final String nouveauCode;
  final String libelle;
  final String famille;
  final num? prixNonAssure;
  final num? prixAssure;

  /// `montant` ou `unique` quand la ligne porte un prix ; `manquant` quand elle n'en porte pas (la prestation naît sans prix : « prix à définir », jamais un zéro).
  final String etatAssure;
  final String? secteur;
  final Object? assurable;

  /// Le nouveau code est celui d'une prestation DÉJÀ DÉCIDÉE par la Direction ([tarPrestationsDecidees], par exemple `CERT-APT-2`) : la ligne de départ s'y RATTACHE, aucune
  /// prestation ni proposition de prix n'est créée (le prix décidé est déjà en vigueur).
  final bool prestationDecidee;
}

class TarArbitrageDistincts {
  const TarArbitrageDistincts.refus(RefusTarif this.refus)
      : ok = false,
        gardeId = null,
        identites = const [];
  const TarArbitrageDistincts.ok({required this.gardeId, required this.identites})
      : ok = true,
        refus = null;
  final bool ok;
  final RefusTarif? refus;

  /// La ligne qui GARDE le code (celle que la caisse lisait).
  final Object? gardeId;
  final List<TarNouvelleIdentite> identites;
}

/// ARBITRE « deux prestations distinctes » : le code reste à la première ligne ([doublon] : de celle que la caisse lit à la dernière) ; chacune des autres reçoit un nouveau code. [famille] : la famille de
/// la prestation de départ (`CERTIFICAT`…). [codesFamille] / [libellesFamille] : les codes et désignations de la MÊME famille au référentiel (la convention se lit là). [codesPris] : TOUS les codes
/// existants (référentiel, alias, listes de départ, archivés compris). [codesDemandes] : un code que l'appelant propose pour une ligne (`ficheId` vers code) ; le moteur le REFUSE s'il est déjà pris.
/// [codesDecides] : les prestations que la Direction a déjà décidées, clé [tarCleDecision] (code quitté et libellé normalisé) vers le code décidé : une ligne qui y correspond reçoit CE code
/// (déjà pris, par construction), rattachée à la prestation décidée, sans création.
/// Refus nommés : `ARBITRAGE_RESERVE` (le geste manque), `MOTIF_REQUIS` (RG-12), `CODE_EXISTANT` (un code ne se réutilise pas), `CODE_VIDE`.
TarArbitrageDistincts tarArbitrerDistincts(
  TarDoublonPrix doublon, {
  required String motif,
  required bool peutDecider,
  required String famille,
  required Iterable<String> codesFamille,
  required Iterable<String> libellesFamille,
  required Iterable<String> codesPris,
  Map<Object?, String> codesDemandes = const {},
  Map<String, String> codesDecides = const {},
}) {
  if (!peutDecider) {
    return const TarArbitrageDistincts.refus(RefusTarif('ARBITRAGE_RESERVE',
        'dire que deux lignes sont deux prestations distinctes revient au profil qui décide les prix (geste réservé de la matrice) : ce n’est pas une modification de fiche',
        'Demander l’arbitrage à la Direction ou à la Directrice Administrative.'));
  }
  if (motif.trim().isEmpty) {
    return const TarArbitrageDistincts.refus(RefusTarif('MOTIF_REQUIS', 'le motif de l’arbitrage est obligatoire (RG-12) : il explique pourquoi ce sont deux prestations', 'Dites en quoi les deux lignes diffèrent.'));
  }
  final pris = {for (final c in codesPris) c.toUpperCase()};
  final garde = doublon.candidats.first;
  final autres = doublon.candidats.skip(1).toList();
  final nouveaux = <String>{};
  final identites = <TarNouvelleIdentite>[];
  for (final f in autres) {
    final demande = codesDemandes[f['id']]?.trim();
    final decide = codesDecides[tarCleDecision(doublon.code, f['libelle'])];
    String code;
    if (demande == null && decide != null) {
      code = decide;
    } else if (demande != null) {
      if (demande.isEmpty) return const TarArbitrageDistincts.refus(RefusTarif('CODE_VIDE', 'le nouveau code est vide', 'Saisir un code.'));
      if (pris.contains(demande.toUpperCase()) || nouveaux.contains(demande.toUpperCase())) {
        return TarArbitrageDistincts.refus(RefusTarif('CODE_EXISTANT', 'le code « $demande » existe déjà (code, alias ou ligne de départ) : un code ne se réutilise jamais',
            'Choisir un autre code, ou laisser le logiciel le construire sur la convention de la famille.'));
      }
      code = demande;
    } else {
      code = tarCodeDistinct(
          codeActuel: doublon.code,
          libelle: '${f['libelle'] ?? doublon.code}',
          codesFamille: codesFamille,
          libellesFamille: libellesFamille,
          codesPris: [...pris, ...nouveaux]);
    }
    nouveaux.add(code.toUpperCase());
    final na = tarPrixNADe(f), pa = tarPrixADe(f);
    identites.add(TarNouvelleIdentite(
        ficheId: f['id'],
        ancienCode: doublon.code,
        nouveauCode: code,
        libelle: '${f['libelle'] ?? doublon.code}',
        famille: famille,
        prixNonAssure: na,
        prixAssure: pa,
        etatAssure: na == null ? 'manquant' : (pa != null ? 'montant' : 'unique'),
        secteur: f['secteur'] as String?,
        assurable: f['assurable'],
        prestationDecidee: demande == null && decide != null));
  }
  return TarArbitrageDistincts.ok(gardeId: garde['id'], identites: identites);
}

/// La clé d'une prestation décidée par la Direction pour l'arbitrage « deux prestations distinctes » : le code quitté et la désignation normalisée de la ligne.
String tarCleDecision(Object? ancienCode, Object? libelle) => '${'$ancienCode'.toUpperCase()}|${tarNormaliserLibelle(libelle)}';
