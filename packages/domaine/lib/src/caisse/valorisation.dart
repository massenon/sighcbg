/// MÉDICAMENT SANS PRIX D'ACHAT : PRESCRIRE, BLOQUER LA CAISSE (Direction de Baguidi, 16/11/2026, revient sur le refus `TARIF_A_VALIDER` des médicaments, E3002).
///
/// Le médecin prescrit TOUJOURS : le soin n'attend pas la pharmacie. La ligne d'un article connu sans prix d'achat en vigueur porte « prix à valoriser » et AUCUN montant —
/// jamais 0, ni dans la facture, ni dans les totaux, ni dans les estimations, ni sur la pièce imprimée. Seul son ENCAISSEMENT est refusé, nommé ([codePrixAValoriser]) ; les
/// autres lignes de la même facture s'encaissent normalement (encaissement ligne par ligne).
///
/// LA VOIE CHOISIE POUR VALORISER, ET POURQUOI ELLE NE RÉÉCRIT JAMAIS UNE PIÈCE VALIDÉE. Une facture de prescription n'est normalisée (MECeF) qu'une fois SOLDÉE, et une
/// facture qui porte une ligne « à valoriser » ne peut pas l'être : la ligne n'a pas de montant. Tant qu'elle attend, la pièce n'est donc ni normalisée ni soldée. La ligne
/// se valorise À L'ENCAISSEMENT, EN PLACE : on COMPLÈTE un montant qui n'a jamais existé, on n'en réécrit aucun. Les lignes déjà valorisées, les montants déjà réglés, le numéro
/// et la date de la pièce ne bougent pas ; la ligne garde la trace de sa valorisation (`valorisation` : prix, version, date d'effet, règle, auteur, instant). Une pièce
/// normalisée, ou archivée, refuse la valorisation en le nommant (`PIECE_NORMALISEE`, `PIECE_ARCHIVEE`) : sa correction passe par un avoir.
///
/// LE PRIX RETENU (RG-02 : le prix d'achat, sans marge) : celui EN VIGUEUR À LA DATE DE LA PIÈCE. Si l'article était encore « à valoriser » à cette date — le cas ordinaire,
/// puisque c'est ce qui a fait la ligne —, le PREMIER prix d'achat validé entré en vigueur après elle, c'est-à-dire celui qui l'a valorisé, jamais un prix plus récent : la ligne
/// ne suit pas les hausses qui viendraient ensuite, et deux caisses qui la valorisent trouvent le même prix. Une date d'effet future ne valorise rien avant d'être en vigueur.
library;

import '../format/js.dart';
import '../tarifs/tarifs.dart';
import 'encaissement.dart' show compteClientsAssurance, comptePrestations, creanceAssureurConstatee, numeroPieceCaisse;

/// Le code nommé du refus d'encaissement d'une ligne sans prix (stable : les écrans, les tests et le journal le lisent).
const String codePrixAValoriser = 'PRIX_A_VALORISER';

/// Le libellé affiché à la place d'un montant absent : jamais « 0 ».
const String libellePrixAValoriser = 'Prix à valoriser';

/// La ligne attend-elle son prix ? (marquée à la prescription, aucun montant posé).
bool ligneAValoriser(Map<String, Object?> l) => l['prixAValoriser'] == true && l['montant'] == null;

/// Les lignes d'une facture qui attendent leur prix.
List<Map<String, Object?>> lignesAValoriserDe(Map<String, Object?> facture) => [
      for (final l in (facture['lignes'] as List? ?? const []))
        if (l is Map && ligneAValoriser(l.cast<String, Object?>())) l.cast<String, Object?>()
    ];

/// Le motif nommé du refus d'encaissement d'une ligne (sans montant inventé).
String motifPrixAValoriser(Object? designation) =>
    '« ${designation ?? 'Article'} » n’a pas de prix d’achat en vigueur : la ligne porte « prix à valoriser » et ne s’encaisse pas encore. '
    'Le prix d’achat se fixe au « Référentiel produits » (« Changer le prix d’achat », puis Oui à « Tarifs et prix ») ; la ligne s’encaisse ensuite au prix d’achat retenu (RG-02). '
    'Les autres prestations de la facture s’encaissent normalement.';

// ---------------------------------------------------------------------------------------------------------------------------------------------
// PRIX ASSURÉ À DÉFINIR (section AJ, Direction du 16/11/2026) : MÊME mécanique que « prix à valoriser ».
// ---------------------------------------------------------------------------------------------------------------------------------------------
//
// Un acte ASSURABLE dont la colonne « prix assuré » de la grille est VIDE, prescrit à un ASSURÉ (carte valide à la date, RG-09) : la ligne existe, porte « prix assuré à définir »
// et AUCUN montant ; le prix NON ASSURÉ est affiché pour information, il n'est JAMAIS facturé à sa place. La ligne porte les deux marques (`prixAValoriser` : la mécanique commune
// des lignes sans montant — hors totaux, encaissement et normalisation refusés en le nommant ; `prixAssureADefinir` : la cause). Elle se valorise à l'encaissement, en place, dès
// qu'un prix assuré validé est en vigueur ([tarPrixValorisationLigne]).

/// Le code nommé du refus d'encaissement d'une ligne dont le prix assuré manque (stable : écrans, tests, journal).
const String codePrixAssureADefinir = 'PRIX_ASSURE_A_DEFINIR';

/// Le libellé affiché à la place du montant : jamais « 0 », jamais le prix non assuré.
const String libellePrixAssureADefinir = 'Prix assuré à définir';

/// La ligne attend-elle son PRIX ASSURÉ (cause particulière d'une ligne sans montant) ?
bool ligneAssureADefinir(Map<String, Object?> l) => l['prixAssureADefinir'] == true && ligneAValoriser(l);

/// Le libellé d'une ligne sans montant, selon sa cause. Le prix non assuré, quand la ligne le porte (`prixNonAssureInfo`), est dit POUR INFORMATION.
String libelleLigneSansMontant(Map<String, Object?> l, {String Function(Object?)? montant}) {
  if (!ligneAssureADefinir(l)) return libellePrixAValoriser;
  final info = l['prixNonAssureInfo'];
  if (info is! num) return libellePrixAssureADefinir;
  return '$libellePrixAssureADefinir (non assuré : ${montant == null ? '$info' : montant(info)}, pour information)';
}

/// Le code nommé du refus d'encaissement d'une ligne sans montant.
String codeLigneSansMontant(Map<String, Object?> l) => ligneAssureADefinir(l) ? codePrixAssureADefinir : codePrixAValoriser;

/// Le motif nommé du refus d'encaissement d'une ligne sans montant.
String motifLigneSansMontant(Map<String, Object?> l) => ligneAssureADefinir(l)
    ? '« ${l['designation'] ?? 'Acte'} » est un acte assurable dont la grille ne porte pas de prix ASSURÉ : la ligne de l’assuré porte « prix assuré à définir » et ne s’encaisse pas. '
        'Elle n’est jamais facturée au prix non assuré (${l['prixNonAssureInfo'] ?? '—'}, pour information). Le prix assuré se propose à « Tarifs et prix », puis Oui ; la ligne s’encaisse ensuite. '
        'Les autres prestations de la facture s’encaissent normalement.'
    : motifPrixAValoriser(l['designation']);

/// Le prix retenu pour valoriser une ligne.
class PrixValorisation {
  const PrixValorisation({required this.prixUnitaire, this.version, this.dateEffet, required this.regle});
  final num prixUnitaire;
  final int? version;
  final String? dateEffet;

  /// `a_la_date` : en vigueur à la date de la pièce ; `premiere_valorisation` : le premier prix validé entré en vigueur après elle.
  final String regle;

  Map<String, Object?> versJson() => {'prixUnitaire': prixUnitaire, 'version': version, 'dateEffet': dateEffet, 'regle': regle};
}

/// Le prix de valorisation d'une ligne d'article (voir l'en-tête) : `null` tant qu'aucun prix d'achat n'est en vigueur. [produit] : la fiche `produits` (son code est celui
/// de sa prestation de prix) ; [jourPiece] : le jour de la PIÈCE ; [aujourdhui] : le jour du geste (une date d'effet postérieure ne vaut pas encore).
PrixValorisation? tarPrixValorisation(ReferentielTarifs h, Map<String, Object?>? produit, String jourPiece, {required String aujourdhui}) {
  if (produit == null) return null;
  final aLaDate = tarPrixProduit(h, produit, jourPiece, aujourdhui: aujourdhui);
  if (!aLaDate.absent && aLaDate.vente != null) {
    return PrixValorisation(prixUnitaire: aLaDate.vente!, version: aLaDate.version, dateEffet: aLaDate.dateEffet, regle: 'a_la_date');
  }
  final code = '${produit['code'] ?? ''}';
  if (code.isEmpty) return null;
  Map<String, Object?>? premiere;
  for (final v in h.versionsDe(code)) {
    if (v['statut'] != 'valide' || tarPrixAchatDe(v) == null) continue;
    final de = v['dateEffet'];
    if (de == null) continue; // « depuis l'origine » : elle aurait été en vigueur à la date de la pièce
    final d = '$de';
    if (d.compareTo(jourPiece) <= 0 || d.compareTo(aujourdhui) > 0) continue;
    if (premiere == null) {
      premiere = v;
      continue;
    }
    final c = d.compareTo('${premiere['dateEffet']}');
    if (c < 0 || (c == 0 && ((v['version'] as num?) ?? 0) < ((premiere['version'] as num?) ?? 0))) premiere = v;
  }
  if (premiere == null) return null;
  final vente = tarPrixVenteProduit(produit['categorie'], premiere);
  if (vente == null) return null;
  return PrixValorisation(
      prixUnitaire: vente, version: ((premiere['version'] as num?) ?? 0).toInt(), dateEffet: premiere['dateEffet'] as String?, regle: 'premiere_valorisation');
}

/// Le prix ASSURÉ de valorisation d'une ligne d'acte (même règle que [tarPrixValorisation]) : le prix assuré EN VIGUEUR à la date de la pièce, sinon le PREMIER prix assuré validé entré
/// en vigueur après elle (et déjà en vigueur aujourd'hui). `null` tant qu'aucun prix assuré n'est validé : jamais le prix non assuré.
PrixValorisation? tarPrixValorisationAssure(ReferentielTarifs h, Object? acteCode, String jourPiece, {required String aujourdhui}) {
  final p = h.parActe['$acteCode'] ?? h.parCode['$acteCode'];
  if (p == null) return null;
  final code = '${p['code']}';
  final aLaDate = h.enVigueur(code, jourPiece);
  if (aLaDate != null && aLaDate['etatAssure'] == 'montant' && aLaDate['prixAssure'] is num && (aLaDate['prixAssure'] as num) > 0) {
    return PrixValorisation(
        prixUnitaire: aLaDate['prixAssure'] as num, version: ((aLaDate['version'] as num?) ?? 0).toInt(), dateEffet: aLaDate['dateEffet'] as String?, regle: 'a_la_date');
  }
  Map<String, Object?>? premiere;
  for (final v in h.versionsDe(code)) {
    if (v['statut'] != 'valide' || v['etatAssure'] != 'montant' || v['prixAssure'] is! num || (v['prixAssure'] as num) <= 0) continue;
    final de = v['dateEffet'];
    if (de == null) continue;
    final d = '$de';
    if (d.compareTo(jourPiece) <= 0 || d.compareTo(aujourdhui) > 0) continue;
    if (premiere == null || d.compareTo('${premiere['dateEffet']}') < 0) premiere = v;
  }
  if (premiere == null) return null;
  return PrixValorisation(
      prixUnitaire: premiere['prixAssure'] as num, version: ((premiere['version'] as num?) ?? 0).toInt(), dateEffet: premiere['dateEffet'] as String?, regle: 'premiere_valorisation');
}

/// Le prix de valorisation d'une ligne SANS MONTANT, selon sa cause : prix assuré d'un acte ([tarPrixValorisationAssure]) ou prix d'achat d'un article ([tarPrixValorisation]).
PrixValorisation? tarPrixValorisationLigne(ReferentielTarifs h, Map<String, Object?> ligne, Map<String, Object?>? produit, String jourPiece, {required String aujourdhui}) =>
    ligneAssureADefinir(ligne) ? tarPrixValorisationAssure(h, ligne['acteCode'], jourPiece, aujourdhui: aujourdhui) : tarPrixValorisation(h, produit, jourPiece, aujourdhui: aujourdhui);

/// Le résultat d'une valorisation : la facture APRÈS (copie), l'écriture complémentaire éventuelle, ou le refus nommé (rien n'est écrit).
class ResultatValorisation {
  const ResultatValorisation({this.facture, this.ecritures = const [], this.refusCode, this.refus});
  final Map<String, Object?>? facture;

  /// La part de l'assureur ajoutée par la ligne, quand la créance de la pièce est DÉJÀ constatée (411 / 706, brouillon, RG-10) : sans elle, la part assurée de la ligne
  /// valorisée n'entrerait jamais au journal (l'encaissement ne constate la créance qu'au premier versement).
  final List<Map<String, Object?>> ecritures;
  final String? refusCode;
  final String? refus;
  bool get ok => refusCode == null;
}

double _n(Object? v) => nombreOuZero(v);

/// Valoriser EN PLACE la ligne [ligneId] de [facture] au [prix] retenu. Pure : rend la facture après, ne l'écrit pas. Les parts suivent la règle de la pièce (taux de prise en
/// charge et prise en charge du personnel ARRÊTÉS à sa date, RG-09) ; jamais de remise sur un médicament (RG-02).
ResultatValorisation valoriserLigne(Map<String, Object?> facture, String ligneId, PrixValorisation prix,
    {required String utilisateur, required String maintenant, String? aujourdhui, List<Map<String, Object?>> ecritures = const []}) {
  final numero = facture['numero'] ?? facture['id'];
  if (facture['statut'] == 'archive') {
    return ResultatValorisation(refusCode: 'PIECE_ARCHIVEE', refus: 'La facture $numero est archivée : aucune ligne ne s’y valorise.');
  }
  if ('${facture['numeroMecef'] ?? ''}'.isNotEmpty || facture['statutMecef'] == 'valide' || facture['statutMecef'] == 'normalisee') {
    return ResultatValorisation(
        refusCode: 'PIECE_NORMALISEE', refus: 'La facture $numero est normalisée : elle ne se réécrit jamais. La corriger par un avoir et une nouvelle pièce.');
  }
  final lignes = [for (final l in (facture['lignes'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  final i = lignes.indexWhere((l) => '${l['id']}' == ligneId);
  if (i < 0) return ResultatValorisation(refusCode: 'LIGNE_INTROUVABLE', refus: 'La ligne $ligneId n’existe pas sur la facture $numero.');
  final l = lignes[i];
  if (!ligneAValoriser(l)) return ResultatValorisation(refusCode: 'DEJA_VALORISEE', refus: 'La ligne « ${l['designation']} » porte déjà son montant.');
  if (!(prix.prixUnitaire > 0)) {
    return ResultatValorisation(refusCode: codeLigneSansMontant(l), refus: motifLigneSansMontant(l));
  }
  final q = _n(l['quantite'] ?? 1);
  final brut = arrondiJs(prix.prixUnitaire * q).toInt();
  final agent = facture['priseEnChargePersonnel'] == true;
  final taux = _n(facture['tauxPriseEnCharge']);
  final pa = agent ? 0 : arrondiJs(brut * taux / 100).toInt();
  final pp = agent ? brut : 0;
  final pat = brut - pa - pp;
  final ligne = <String, Object?>{
    ...l,
    'prixUnitaire': prix.prixUnitaire,
    'prixUnitaireNet': q != 0 ? arrondiJs(brut / q).toInt() : brut,
    'montantBrut': brut,
    'remise': 0,
    'montant': brut,
    'partAssureur': pa,
    'partPersonnel': pp,
    'partPatient': pat,
    'prixAValoriser': false,
    if (l['prixAssureADefinir'] == true) 'prixAssureADefinir': false,
    'valorisation': {...prix.versJson(), 'valoriseLe': maintenant, 'valorisePar': utilisateur},
  };
  final apresLignes = [...lignes]..[i] = ligne;
  final restantes = apresLignes.where(ligneAValoriser).length;
  final apres = <String, Object?>{
    ...facture,
    'lignes': apresLignes,
    'montantHT': _n(facture['montantHT']) + brut,
    'montantTTC': _n(facture['montantTTC']) + brut,
    'montantBrut': _n(facture['montantBrut']) + brut,
    'partAssurance': _n(facture['partAssurance']) + pa,
    'partPersonnel': _n(facture['partPersonnel']) + pp,
    'partPatient': _n(facture['partPatient']) + pat,
    'reliquat': _n(facture['reliquat']) + pat,
    'lignesAValoriser': restantes,
  };
  final complement = <Map<String, Object?>>[];
  if (pa > 0 && creanceAssureurConstatee(facture, ecritures)) {
    final jour = aujourdhui ?? maintenant.substring(0, 10);
    final base = <String, Object?>{
      'numero': numeroPieceCaisse(facture, jour, ecritures),
      'date': jour,
      'journal': 'CAI',
      'journalLibelle': 'Journal de caisse-dépenses',
      'libelle': 'Valorisation « ${l['designation']} » — facture $numero — part ${facture['assureur'] ?? 'assureur'}',
      'pieceId': facture['id'],
      'pieceNumero': facture['numero'],
      'origine': 'Automatique — Caisse (valorisation)',
      'statut': 'brouillon',
    };
    complement
      ..add({...base, 'compte': compteClientsAssurance, 'debit': pa.toDouble(), 'credit': 0.0})
      ..add({...base, 'compte': comptePrestations, 'debit': 0.0, 'credit': pa.toDouble()});
  }
  return ResultatValorisation(facture: apres, ecritures: complement);
}
