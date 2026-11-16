/// LES PRESTATIONS DÉCIDÉES PAR UNE NOTE DE LA DIRECTION (section AJ, 16/11/2026).
///
/// Le catalogue de départ portait `CERT-APT` deux fois : « Certificat médical d'aptitude » à 7 000 et « Certificat d'aptitude » à 5 000 (E2578, E3000). La Direction a TRANCHÉ par
/// note : ce sont deux prestations ; la seconde reçoit le code **CERT-APT-2**, le libellé « Certificat d'aptitude », le prix de **5 000**, couverture SOS seule, et se délivre par le
/// générateur des pièces numérotées (type de pièce `patTypePieceCertificatAptitude2`). Ce fichier porte la décision comme une DONNÉE datée et sourcée ; le poste mère l'AMORCE
/// (rejouable, sans rien écraser) :
///  * la prestation naît au référentiel avec UNE version datée du jour de la note (origine `note-direction`), validée (la Direction a décidé le prix) mais marquée « provisoire,
///    à confirmer » : aucun document (grille) ne la porte encore ;
///  * `CERT-APT` (7 000) n'est pas touché, aucune facture n'est relue ni réécrite (une pièce émise garde son prix et son libellé) ;
///  * une ligne de départ qui portait encore `CERT-APT` avec CE libellé et CE prix est RATTACHÉE au nouveau code, exactement comme l'arbitrage « deux prestations distinctes »
///    l'aurait fait (le doublon se résout, la caisse lit chacune des deux prestations à son prix).
///
/// Fonctions PURES : le référentiel et les fiches sont passés en argument ; aucune base, aucune horloge.
library;

import 'tarifs.dart' show ReferentielTarifs, FicheTarif, tarNormaliserLibelle;
import 'tarifs_doublons.dart' show tarCleDecision, tarPrixNADe;

/// Le code fixé par la Direction pour le second certificat d'aptitude.
const String tarCodeCertificatAptitude2 = 'CERT-APT-2';

/// Une prestation décidée par une note de la Direction.
class TarPrestationDecidee {
  const TarPrestationDecidee({
    required this.code,
    required this.libelle,
    required this.famille,
    required this.prixNonAssure,
    required this.prixAssure,
    required this.assurable,
    required this.dateEffet,
    required this.origine,
    required this.source,
    required this.motif,
    required this.distinctDe,
    this.typePieceId,
    this.aConfirmer = true,
  });
  final String code;
  final String libelle;
  final String famille;
  final num prixNonAssure;
  final num prixAssure;

  /// `true`, `false` ou `'sos'` (couverture SOS seule).
  final Object assurable;

  /// La date d'effet de la version (le jour de la note), jamais une date inventée.
  final String dateEffet;
  final String origine;
  final String source;
  final String motif;

  /// Le code de la prestation dont celle-ci est distincte (la ligne de départ portait ce code).
  final String distinctDe;

  /// Le type de pièce numérotée qui la délivre (`typesPiece`), s'il existe.
  final String? typePieceId;

  /// « À confirmer » : aucun document ne porte encore ce prix (la note seule le fixe).
  final bool aConfirmer;
}

/// Les prestations décidées. Une ligne de plus = une décision de plus, avec sa source ; jamais un prix sans note.
const List<TarPrestationDecidee> tarPrestationsDecidees = [
  TarPrestationDecidee(
    code: tarCodeCertificatAptitude2,
    libelle: 'Certificat d’aptitude',
    famille: 'CERTIFICAT',
    prixNonAssure: 5000,
    prixAssure: 5000,
    assurable: 'sos',
    dateEffet: '2026-11-16',
    origine: 'note-direction',
    source: 'Note de la Direction du 16/11/2026 (section AJ)',
    motif: 'Prix fixé par la note de la Direction du 16/11/2026 (second certificat d’aptitude, couverture SOS seule) : à confirmer par un document, aucune grille Baguidi remise.',
    distinctDe: 'CERT-APT',
    typePieceId: 'TPC16',
  ),
];

/// La table « (code quitté, libellé normalisé) vers code décidé » que l'arbitrage « deux prestations distinctes » consulte ([tarArbitrerDistincts]).
Map<String, String> tarCodesDecides([List<TarPrestationDecidee> decisions = tarPrestationsDecidees]) =>
    {for (final d in decisions) tarCleDecision(d.distinctDe, d.libelle): d.code};

/// Ce que le poste mère doit écrire pour amorcer les décisions : les prestations et leurs versions absentes du référentiel, et les lignes de départ à rattacher.
class AmorceDecisions {
  const AmorceDecisions({required this.tarifs, required this.versions, required this.rattachements});
  final List<FicheTarif> tarifs;
  final List<FicheTarif> versions;

  /// (collection, identifiant de la fiche de départ, patch) : la ligne qui portait encore le code quitté avec ce libellé et ce prix prend le code décidé.
  final List<({String collection, Object? id, Map<String, Object?> patch})> rattachements;
  bool get vide => tarifs.isEmpty && versions.isEmpty && rattachements.isEmpty;
}

/// L'AMORCE des décisions (rejouable) : une prestation déjà présente au référentiel (même archivée : un code ne se réutilise jamais) n'est ni recréée ni réécrite ; une
/// ligne de départ n'est rattachée que si son code, son libellé (normalisé) et son prix non assuré sont ceux de la décision. [catalogue] : les fiches de `catalogueTarifs`.
AmorceDecisions tarAmorcerDecisions(ReferentielTarifs h, {required Iterable<FicheTarif> catalogue, List<TarPrestationDecidee> decisions = tarPrestationsDecidees}) {
  final connus = {for (final p in h.tarifs) '${p['code']}'.toUpperCase()};
  final tarifs = <FicheTarif>[];
  final versions = <FicheTarif>[];
  final rattachements = <({String collection, Object? id, Map<String, Object?> patch})>[];
  for (final d in decisions) {
    if (!connus.contains(d.code.toUpperCase()) && h.versionsDe(d.code).isEmpty) {
      tarifs.add({
        'id': d.code,
        'code': d.code,
        'codeGrille': d.code,
        'libelle': d.libelle,
        'famille': d.famille,
        'statut': 'actif',
        'assurable': d.assurable,
        'distinctDe': d.distinctDe,
        'decisionDirection': d.source,
        'source': d.source,
        if (d.typePieceId != null) 'typePieceId': d.typePieceId,
      });
      versions.add({
        'id': '${d.code}@${d.dateEffet}@1',
        'code': d.code,
        'version': 1,
        'prixNonAssure': d.prixNonAssure,
        'prixAssure': d.prixAssure,
        'etatAssure': 'montant',
        'origine': d.origine,
        'statut': 'valide',
        'dateEffet': d.dateEffet,
        'motif': d.motif,
        if (d.aConfirmer) 'provisoire': true,
        'decidePar': 'Direction (note du 16/11/2026)',
        'decideLe': d.dateEffet,
      });
    }
    final cle = tarNormaliserLibelle(d.libelle);
    for (final f in catalogue) {
      if (f['statut'] == 'archive') continue;
      if ('${f['code']}'.toUpperCase() != d.distinctDe.toUpperCase() || tarNormaliserLibelle(f['libelle']) != cle) continue;
      if (tarPrixNADe(f) != d.prixNonAssure) continue;
      rattachements.add((
        collection: 'catalogueTarifs',
        id: f['id'],
        patch: {
          'code': d.code,
          'codeAnterieur': d.distinctDe,
          'distinctDe': d.distinctDe,
          'motifDistinct': d.source,
          'distinctPar': 'Direction (note du 16/11/2026)',
          'distinctLe': d.dateEffet,
        }
      ));
    }
  }
  return AmorceDecisions(tarifs: tarifs, versions: versions, rattachements: rattachements);
}
