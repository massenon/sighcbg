/// LES VERSEMENTS — le règlement d'UNE facture en plusieurs versements de modes différents (Direction de Baguidi, 20/11/2026,
/// docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md §13).
///
/// Un VERSEMENT est une ligne de journal (famille B : ajout seul, jamais réécrite) : montant, TYPE de versement (espèces, carte, Mobile Money, chèque…), modalité éventuelle
/// (l'opérateur Mobile Money, la banque), référence de transaction SAISIE À LA MAIN (jamais lue d'une API), date et heure, caissier, facture, prestations couvertes.
/// Les TYPES et les MODALITÉS sont des PARAMÈTRES de la clinique (collections `typesVersement`, `modalitesVersement`, administrables, archivage annulable RG-14) : AUCUN
/// type n'est écrit dans une règle. Le type porte son compte de trésorerie comptable et dit si la référence est exigée.
///
/// Règles (Direction, §13) :
///  * un règlement mixte se fait LE MÊME JOUR, en UN geste : la somme des versements saisis égale ce que les prestations cochées valent (une ligne n'est réglée que si elle l'est
///    ENTIÈREMENT, donc rien n'est jamais versé « à moitié » sur une ligne) et ne dépasse jamais le dû ; la règle des restes dus d'un autre jour est celle d'avant, inchangée ;
///  * les prestations bloquées ne se débloquent que lorsque SA ligne est entièrement payée : l'allocation aux lignes est celle de [encaisser] (ordre de la pièce) ;
///  * le règlement ne concerne que la part du PATIENT (assuré ou non) : la part de l'assureur reste une créance (411), constatée au premier versement seulement ;
///  * CHAQUE versement pose SON écriture plate sur le compte de trésorerie de son type (RG-10 contrôlé avant écriture, brouillon) ;
///  * un versement ne se supprime jamais : l'annulation est une CONTRE-PASSATION tracée, sous le geste réservé `versement_annuler` ([contrepasserReglement]).
///
/// COMPATIBILITÉ : une facture d'avant les versements n'en porte aucun ; sa lecture passe quand même par eux ([versementsDeFacture]) : un versement IMPLICITE du mode unique de
/// la pièce, jamais écrit (aucune réécriture de l'existant).
///
/// MECeF (Direction) : la facture normalisée et le ticket ne mentionnent NI versements NI modes — le montant total, le libellé d'arrêté et le montant en lettres seulement.
/// Rien de ce fichier ne produit une pièce normalisée : les versements n'existent que sur le reçu détaillé et dans les états.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import '../mecef/montants.dart';
import '../numerotation/numerotation.dart';
import '../parametres/enumerations.dart';
import 'encaissement.dart';

const String colVersements = 'versements';
const String colTypesVersement = 'typesVersement';
const String colModalitesVersement = 'modalitesVersement';

/// Le sens d'une ligne de versement : un versement reçu, ou la contre-passation d'un versement (annulation tracée).
const String sensVersement = 'versement';
const String sensContrepassation = 'contrepassation';

/// Le code de mode que porte la facture quand ses versements sont de plusieurs types (lecture : `libelles.m8.modesPaiement`).
const String modeMixte = 'mixte';

// Refus nommés.
const String codeVersementsVides = 'VERSEMENTS_VIDES';
const String codeVersementMontant = 'VERSEMENT_MONTANT_INVALIDE';
const String codeVersementTypeInconnu = 'VERSEMENT_TYPE_INCONNU';
const String codeVersementModaliteInconnue = 'VERSEMENT_MODALITE_INCONNUE';
const String codeVersementReferenceExigee = 'VERSEMENT_REFERENCE_EXIGEE';
const String codeVersementReferenceUtilisee = 'VERSEMENT_REFERENCE_DEJA_UTILISEE';
const String codeVersementsDepassentDu = 'VERSEMENTS_DEPASSENT_DU';
const String codeVersementsEcartLignes = 'VERSEMENTS_ECART_LIGNES';
const String codeVersementsMontantNonAlloue = 'VERSEMENTS_MONTANT_NON_ALLOUE';
const String codeVersementDejaAnnule = 'VERSEMENT_DEJA_ANNULE';
const String codeVersementMotifObligatoire = 'VERSEMENT_MOTIF_OBLIGATOIRE';
const String codeVersementFactureNormalisee = 'VERSEMENT_FACTURE_NORMALISEE';
const String codeVersementIntrouvable = 'VERSEMENT_INTROUVABLE';

bool _faux(Object? v) => v == null || v == '' || v == 0 || v == false;
double _n(Object? v) => nombreOuZero(v);

/// Un type de versement, tel que la clinique le règle.
class TypeVersement {
  const TypeVersement({required this.code, required this.libelle, required this.compte, required this.referenceExigee, this.aConfirmer = false});
  final String code;
  final String libelle;

  /// Le compte de TRÉSORERIE (classe 5) débité par un versement de ce type.
  final String compte;
  final bool referenceExigee;
  final bool aConfirmer;
}

/// Une modalité (opérateur Mobile Money, banque…) rattachée à un type.
class ModaliteVersement {
  const ModaliteVersement({required this.id, required this.type, required this.libelle, this.aConfirmer = false});
  final String id;
  final String type;
  final String libelle;
  final bool aConfirmer;
}

/// Le compte de trésorerie d'attente des types qui ne sont pas la caisse : « Banque » du plan comptable. Le compte RÉEL (banque de la clinique, compte Mobile Money) est à confirmer
/// par la Direction : il se règle sur la fiche du type, jamais ici.
const String compteTresorerieAttente = '521000';

/// Les types d'attente : les codes de `libelles.m8.modesPaiement` que le PATIENT règle (la prise en charge de l'assurance n'est pas un règlement du patient), plus « Mobile Money »
/// avec ses opérateurs. Marqués « à confirmer par la Direction » : aucun document ne fixe ni la liste ni les comptes. Un code absent du réglage garde son code comme libellé.
List<Map<String, Object?>> typesVersementSemence() => [
      for (final (i, c) in const [('especes', compteCaisse), ('tpe', compteTresorerieAttente), ('mtn', compteTresorerieAttente), ('moov', compteTresorerieAttente), ('mobile_money', compteTresorerieAttente)].indexed)
        {
          'id': 'TV${(i + 1).toString().padLeft(2, '0')}',
          'code': c.$1,
          'libelle': enumModesPaiement.libelle(c.$1),
          'compteTresorerie': c.$2,
          'referenceExigee': c.$1 == 'mobile_money',
          'actif': true,
          'ordre': i + 1,
          'aConfirmer': true,
          'source': 'Valeur d’attente (libellés des modes de paiement) — à confirmer par la Direction : libellé, compte de trésorerie réel, référence exigée.',
        }
    ];

/// Les modalités d'attente : MTN, Moov et Celtiis sous « Mobile Money » — des valeurs d'attente, pas une liste officielle des opérateurs (« à confirmer par la Direction »).
List<Map<String, Object?>> modalitesVersementSemence() => [
      for (final (i, l) in const ['MTN', 'Moov', 'Celtiis'].indexed)
        {
          'id': 'MV${(i + 1).toString().padLeft(2, '0')}',
          'type': 'mobile_money',
          'libelle': l,
          'actif': true,
          'ordre': i + 1,
          'aConfirmer': true,
          'source': 'Valeur d’attente — la liste des opérateurs n’est pas une liste officielle ; à confirmer par la Direction.',
        }
    ];

bool _actif(Map<String, Object?> f) => f['statut'] != 'archive' && f['actif'] != false;

/// Les types EN SERVICE : les fiches actives de la collection ; la collection vide (poste neuf, jeu d'un test) retombe sur les valeurs d'attente — un caissier ne se retrouve jamais sans
/// aucun type. Une collection dont tous les types sont archivés, elle, n'offre rien : c'est un choix de la clinique.
List<TypeVersement> typesVersementEnService(Iterable<Map<String, Object?>> fiches) {
  final f = fiches.toList();
  final src = f.isEmpty ? typesVersementSemence() : f;
  final l = [
    for (final x in src)
      if (_actif(x))
        TypeVersement(
            code: '${x['code']}',
            libelle: '${x['libelle'] ?? x['code']}',
            compte: '${x['compteTresorerie'] ?? compteCaisse}',
            referenceExigee: x['referenceExigee'] == true,
            aConfirmer: x['aConfirmer'] == true)
  ];
  return l;
}

/// Le libellé affiché d'un type : celui de sa fiche (archivée comprise), sinon le libellé du mode du réglage `libelles.m8.modesPaiement` (les pièces d'avant les versements), sinon
/// [repli], sinon le code. Le code « mixte » (facture réglée de plusieurs types) se lit au même réglage.
String libelleDeType(Iterable<Map<String, Object?>> typesFiches, Object? code, {String Function(String)? repli}) {
  final t = typeVersementDe(typesFiches, code);
  if (t != null) return t.libelle;
  final c = '${code ?? ''}';
  if (c.isEmpty) return 'Mode non renseigné';
  final enum_ = enumModesPaiement.libelles[c];
  if (enum_ != null) return enum_;
  return repli != null ? repli(c) : c;
}

/// Tous les types, archivés compris (la lecture d'une pièce ancienne retrouve le libellé d'un type archivé depuis).
TypeVersement? typeVersementDe(Iterable<Map<String, Object?>> fiches, Object? code) {
  final f = fiches.toList();
  for (final x in (f.isEmpty ? typesVersementSemence() : f)) {
    if ('${x['code']}' == '$code') {
      return TypeVersement(
          code: '${x['code']}',
          libelle: '${x['libelle'] ?? x['code']}',
          compte: '${x['compteTresorerie'] ?? compteCaisse}',
          referenceExigee: x['referenceExigee'] == true,
          aConfirmer: x['aConfirmer'] == true);
    }
  }
  return null;
}

List<ModaliteVersement> modalitesVersementEnService(Iterable<Map<String, Object?>> fiches, {String? type}) {
  final f = fiches.toList();
  return [
    for (final x in (f.isEmpty ? modalitesVersementSemence() : f))
      if (_actif(x) && (type == null || '${x['type']}' == type)) ModaliteVersement(id: '${x['id']}', type: '${x['type']}', libelle: '${x['libelle'] ?? x['id']}', aConfirmer: x['aConfirmer'] == true)
  ];
}

String? libelleModalite(Iterable<Map<String, Object?>> fiches, Object? id) {
  if (_faux(id)) return null;
  final f = fiches.toList();
  for (final x in (f.isEmpty ? modalitesVersementSemence() : f)) {
    if ('${x['id']}' == '$id') return '${x['libelle'] ?? id}';
  }
  return null;
}

/// Un versement tel que le caissier le saisit.
class VersementSaisi {
  const VersementSaisi({required this.montant, required this.type, this.modalite, this.reference = ''});
  final num montant;
  final String type;
  final String? modalite;
  final String reference;
}

/// Un versement en vigueur d'une facture, tel que les ÉTATS le lisent (écrit ou implicite).
class VersementLu {
  const VersementLu({required this.montant, required this.type, required this.date, this.libelleType, this.modalite, this.reference = '', this.implicite = false, this.id});
  final num montant;
  final String type;
  final String date;
  final String? libelleType;
  final String? modalite;
  final String reference;
  final bool implicite;
  final String? id;
}

/// LA LECTURE D'UNE FACTURE PAR SES VERSEMENTS. Les versements écrits de la pièce (déduction faite de ceux qu'une contre-passation annule) ; à défaut, et seulement si la pièce a
/// été réglée, UN versement implicite du mode unique de la pièce (`modePaiement`) pour le montant payé : une facture d'avant les versements se lit comme avant, sans réécriture.
List<VersementLu> versementsDeFacture(Map<String, Object?> facture, Iterable<Map<String, Object?>> versements) {
  final id = facture['id'];
  final siens = [for (final v in versements) if (v['factureId'] == id && v['statut'] != 'archive') v];
  if (siens.isNotEmpty) {
    final annules = {for (final v in siens) if (v['sens'] == sensContrepassation) '${v['annule']}'};
    // Dans l'ordre où ils ont été reçus (date et heure, puis rang dans le règlement), quel que soit l'ordre de rangement de la collection.
    final vivants = [for (final v in siens) if (v['sens'] != sensContrepassation && !annules.contains('${v['id']}')) v]
      ..sort((a, b) {
        final c = '${a['dateHeure'] ?? a['date'] ?? ''}'.compareTo('${b['dateHeure'] ?? b['date'] ?? ''}');
        return c != 0 ? c : _n(a['rang']).compareTo(_n(b['rang']));
      });
    return [
      for (final v in vivants)
        VersementLu(
            montant: _n(v['montant']),
            type: '${v['type']}',
            libelleType: v['typeLibelle'] as String?,
            modalite: v['modaliteLibelle'] as String?,
            reference: '${v['reference'] ?? ''}',
            date: '${v['date'] ?? ''}',
            id: '${v['id']}')
    ];
  }
  final mode = _faux(facture['modePaiement']) ? 'especes' : '${facture['modePaiement']}';
  final refTransaction = '${facture['referenceTransaction'] ?? ''}';
  String jour(Object? v) {
    final t = '${v ?? ''}';
    return t.length >= 10 ? t.substring(0, 10) : t;
  }

  // La date : celle des règlements portés par les LIGNES payées (un versement implicite par jour de règlement), sinon celle du dernier règlement, sinon celle de la facture.
  final parJour = <String, double>{};
  for (final l in (facture['lignes'] as List? ?? const [])) {
    if (l is Map && !_faux(l['payeLe']) && _n(l['montantRegle'] ?? l['partPatient']) > 0 && l['statutPaiement'] != 'du') {
      final j = jour(l['payeLe']);
      parJour[j] = (parJour[j] ?? 0) + _n(l['montantRegle'] ?? l['partPatient']);
    }
  }
  // Le montant payé de la pièce ; une pièce qui ne le porte pas se lit par ses lignes réglées.
  final somme0 = parJour.values.fold<double>(0, (a, b) => a + b);
  final paye = _n(facture['montantPaye']) > 0 ? _n(facture['montantPaye']) : somme0;
  if (paye <= 0) return const [];
  final dr = facture['dernierReglement'];
  if (parJour.isEmpty) parJour[jour((dr is Map ? dr['date'] : null) ?? facture['date'])] = paye;
  // Ce que les lignes ne portent pas (règlement d'une pièce sans lignes, arrondi) va au dernier jour : la somme des versements implicites est TOUJOURS le montant payé.
  final somme = parJour.values.fold<double>(0, (a, b) => a + b);
  final dernierJour = (parJour.keys.toList()..sort()).last;
  if ((paye - somme).abs() > 0.5) parJour[dernierJour] = (parJour[dernierJour] ?? 0) + (paye - somme);
  return [
    for (final j in (parJour.keys.toList()..sort()))
      VersementLu(montant: parJour[j]!, type: mode, reference: refTransaction, date: j, implicite: true)
  ];
}

/// Ce que les états « par mode » additionnent : le montant par TYPE de versement sur [factures], d'après les versements (écrits ou implicites). [dans] filtre par la date du versement
/// (un état de période compte les versements de la période, non la date de la facture) ; sans filtre, tous. Un règlement 5 000 Mobile Money + 3 000 espèces compte 5 000 d'un côté
/// et 3 000 de l'autre.
Map<String, num> repartitionParType(Iterable<Map<String, Object?>> factures, Iterable<Map<String, Object?>> versements, {bool Function(VersementLu)? dans}) {
  final out = <String, num>{};
  final liste = versements.toList();
  for (final f in factures) {
    for (final v in versementsDeFacture(f, liste)) {
      if (dans != null && !dans(v)) continue;
      out[v.type] = (out[v.type] ?? 0) + v.montant;
    }
  }
  return out;
}

class ResultatVersements {
  const ResultatVersements({required this.encaissement, required this.versements, required this.ecritures, this.refus, this.refusCode});

  /// Le résultat arithmétique de l'encaissement (facture APRÈS règlement, lignes réglées, reste dû). Sur un refus : l'encaissement refusé ou celui d'avant, rien d'écrit.
  final ResultatEncaissement? encaissement;

  /// Les fiches de versement à écrire (sans `id`, que le magasin attribue).
  final List<Map<String, Object?>> versements;
  final List<Map<String, Object?>> ecritures;
  final String? refus;
  final String? refusCode;
  bool get ok => refus == null;
}

ResultatVersements _refus(String code, String motif, [ResultatEncaissement? r]) => ResultatVersements(encaissement: r, versements: const [], ecritures: const [], refus: '$code : $motif', refusCode: code);

/// Règle UNE facture par un ou plusieurs versements, en un geste (le même jour). [lignes] : les prestations cochées (leur total EST la somme à répartir) ; sans lignes, la somme des
/// versements est allouée aux lignes dues dans l'ordre de la pièce, et doit les couvrir ENTIÈREMENT. Rien n'est jamais écrit sur un refus (refus nommé).
///
/// [versementsExistants] : le journal des versements (références déjà utilisées, rang de numéro). [typesFiches] / [modalitesFiches] : les collections de paramètres.
ResultatVersements reglerParVersements(
  Map<String, Object?> facture,
  List<VersementSaisi> saisis, {
  List<String>? lignes,
  required String aujourdhui,
  required String maintenant,
  String utilisateur = '',
  bool mecefActif = true,
  bool encaisserResteSansPrix = false,
  List<Map<String, Object?>> ecritures = const [],
  List<Map<String, Object?>> versementsExistants = const [],
  Iterable<Map<String, Object?>> typesFiches = const [],
  Iterable<Map<String, Object?>> modalitesFiches = const [],
  String? lotId,
}) {
  if (saisis.isEmpty) return _refus(codeVersementsVides, 'Aucun versement saisi : ajouter au moins un versement (montant et type).');
  final types = {for (final t in typesVersementEnService(typesFiches)) t.code: t};
  final toutesModalites = modalitesVersementEnService(modalitesFiches);
  final vus = <String>{};
  for (final (i, s) in saisis.indexed) {
    final rang = 'Versement ${i + 1}';
    if (!(s.montant > 0)) return _refus(codeVersementMontant, '$rang : le montant doit être supérieur à zéro.');
    final t = types[s.type];
    if (t == null) return _refus(codeVersementTypeInconnu, '$rang : le type « ${s.type} » n’est pas un type de versement en service (Paramètres de la caisse › Types de versement).');
    if (!_faux(s.modalite)) {
      final m = toutesModalites.where((x) => x.id == s.modalite).toList();
      if (m.isEmpty || m.first.type != s.type) {
        return _refus(codeVersementModaliteInconnue, '$rang : la modalité choisie n’existe pas pour le type « ${t.libelle} » (Paramètres de la caisse › Modalités de versement).');
      }
    }
    final ref = s.reference.trim();
    if (t.referenceExigee && ref.isEmpty) {
      return _refus(codeVersementReferenceExigee, '$rang : le type « ${t.libelle} » exige la référence de la transaction (saisie à la main).');
    }
    if (ref.isNotEmpty) {
      final cle = '${s.type}|${ref.toLowerCase()}';
      final annules = {for (final v in versementsExistants) if (v['sens'] == sensContrepassation) '${v['annule']}'};
      final deja = vus.contains(cle) ||
          versementsExistants.any((v) => v['sens'] != sensContrepassation && v['statut'] != 'archive' && !annules.contains('${v['id']}') && '${v['type']}' == s.type && '${v['reference'] ?? ''}'.trim().toLowerCase() == ref.toLowerCase());
      if (deja) return _refus(codeVersementReferenceUtilisee, '$rang : la référence « $ref » a déjà servi pour un versement « ${t.libelle} » — une transaction ne règle qu’une fois.');
      vus.add(cle);
    }
  }
  final total = saisis.fold<double>(0, (a, s) => a + s.montant.toDouble());
  final toutes = [for (final l in (facture['lignes'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  final avecLignes = lignes != null && lignes.isNotEmpty && toutes.isNotEmpty;
  if (avecLignes) {
    final vises = lignes.toSet();
    final du = toutes.where((l) => l['statutPaiement'] != 'paye' && vises.contains(l['id'])).fold<double>(0, (a, l) => a + _n(l['partPatient']));
    if ((total - du).abs() > 0.5) {
      return _refus(
          codeVersementsEcartLignes,
          total > du
              ? 'Les versements totalisent ${money(total)} : les prestations cochées ne valent que ${money(du)}. Un versement ne dépasse jamais le dû.'
              : 'Les versements totalisent ${money(total)} : les prestations cochées valent ${money(du)}. Une prestation n’est réglée que si elle l’est entièrement — ajouter un versement de ${money(du - total)} ou décocher une prestation.');
    }
  }
  final codes = {for (final s in saisis) s.type};
  final modeFacture = codes.length == 1 ? codes.first : modeMixte;
  final r = encaisser(facture,
      lignes: avecLignes ? lignes : null,
      montant: avecLignes ? null : total,
      mode: modeFacture,
      aujourdhui: aujourdhui,
      maintenant: maintenant,
      utilisateur: utilisateur,
      mecefActif: mecefActif,
      ecritures: ecritures,
      encaisserResteSansPrix: encaisserResteSansPrix);
  if (r.refus != null) return ResultatVersements(encaissement: r, versements: const [], ecritures: const [], refus: r.refus, refusCode: r.refusCode ?? 'VERSEMENT_REFUSE');
  if (r.deja) return _refus('FACTURE_DEJA_SOLDEE', 'La facture est déjà soldée : aucun versement à enregistrer.', r);
  final regle = r.montantRegle ?? 0;
  if ((regle - total).abs() > 0.5) {
    // Sans prestation cochée : la somme n'a couvert entièrement aucune ligne, ou en a laissé une partie sans ligne (jamais d'argent encaissé sans ligne pour le porter).
    return _refus(
        codeVersementsMontantNonAlloue,
        regle <= 0
            ? 'Les versements (${money(total)}) ne couvrent entièrement aucune prestation : régler une ou plusieurs prestations en entier.'
            : 'Les versements (${money(total)}) couvrent entièrement ${money(regle)} de prestations ; ${money(total - regle)} ne règle aucune prestation en entier. Ajuster les versements ou cocher les prestations.',
        r);
  }
  final dr = r.facture['dernierReglement'];
  final apres = {
    ...r.facture,
    'modePaiement': modeFacture,
    if (dr is Map) 'dernierReglement': {...dr.cast<String, Object?>(), 'mode': modeFacture, 'versements': saisis.length},
  };
  final ref = '${_faux(facture['numero']) ? facture['id'] : facture['numero']}';
  final lot = lotId ?? 'LOT-${facture['id']}-${maintenant.replaceAll(RegExp(r'[^0-9]'), '')}';
  final fiches = <Map<String, Object?>>[];
  final posees = <Map<String, Object?>>[];
  for (final (i, s) in saisis.indexed) {
    final t = types[s.type]!;
    final numero = numeroSuivant('caisse.versements', date: aujourdhui, existants: [...versementsExistants, ...fiches]);
    final mod = _faux(s.modalite) ? null : toutesModalites.firstWhere((x) => x.id == s.modalite);
    fiches.add({
      'numero': numero,
      'factureId': facture['id'],
      'factureNumero': ref,
      'patientId': facture['patientId'],
      'patient': facture['patient'],
      'patientCode': facture['patientCode'],
      'sens': sensVersement,
      'montant': s.montant,
      'type': s.type,
      'typeLibelle': t.libelle,
      'compteTresorerie': t.compte,
      if (mod != null) 'modalite': mod.id,
      if (mod != null) 'modaliteLibelle': mod.libelle,
      if (s.reference.trim().isNotEmpty) 'reference': s.reference.trim(),
      'date': aujourdhui,
      'dateHeure': maintenant,
      'caissier': utilisateur,
      'lot': lot,
      'rang': i + 1,
      'lignes': r.lignesReglees,
      'statut': 'actif',
    });
    // L'écriture de CE versement : débit du compte du type, crédit des produits ; la créance de l'assureur n'entre qu'au premier versement de la facture (les écritures déjà
    // posées, y compris celles de ce geste, la portent).
    posees.addAll(ecritureEncaissementSur(apres, s.montant.toDouble(), aujourdhui, [...ecritures, ...posees],
        compteTresorerie: t.compte, complementLibelle: '${t.libelle}${mod == null ? '' : ' ${mod.libelle}'}'));
  }
  if (posees.length < saisis.length) return _refus('ECRITURE_DESEQUILIBREE', 'Une écriture de versement n’est pas équilibrée (RG-10) : rien n’est écrit.', r);
  return ResultatVersements(encaissement: ResultatEncaissement(facture: apres, deja: false, lignesReglees: r.lignesReglees, montantRegle: r.montantRegle, restantDu: r.restantDu, ecritures: posees, lignesRefusees: r.lignesRefusees), versements: fiches, ecritures: posees);
}

class ResultatContrepassation {
  const ResultatContrepassation({required this.contrepassations, required this.ecritures, required this.facture, required this.lignesRouvertes, this.refus, this.refusCode});
  final List<Map<String, Object?>> contrepassations;
  final List<Map<String, Object?>> ecritures;

  /// Les champs de la facture à réécrire (montant payé, reste dû, statut, lignes rouvertes, base MECeF).
  final Map<String, Object?> facture;
  final List<String> lignesRouvertes;
  final String? refus;
  final String? refusCode;
  bool get ok => refus == null;
}

ResultatContrepassation _refusC(String code, String motif) => ResultatContrepassation(contrepassations: const [], ecritures: const [], facture: const {}, lignesRouvertes: const [], refus: '$code : $motif', refusCode: code);

/// ANNULE UN RÈGLEMENT (le geste réservé `versement_annuler`, vérifié par l'appelant) : le versement désigné et tous ceux du MÊME règlement (même lot — un règlement couvre des
/// prestations entières, l'annuler à moitié laisserait des prestations payées sans l'argent qui les porte) reçoivent chacun une CONTRE-PASSATION tracée (nouvelle ligne de journal,
/// motif obligatoire, jamais une modification ni une suppression), l'écriture comptable inverse naît en brouillon (RG-10), et les prestations du règlement redeviennent dues.
/// Refusé en nommant : motif absent, versement déjà annulé, facture NORMALISÉE (une pièce émise ne se réécrit pas : passer par la facture d'avoir).
ResultatContrepassation contrepasserReglement(
  Map<String, Object?> facture,
  String versementId,
  List<Map<String, Object?>> versements, {
  required String motif,
  required String aujourdhui,
  required String maintenant,
  String utilisateur = '',
  List<Map<String, Object?>> ecritures = const [],
  bool mecefActif = true,
}) {
  if (motif.trim().isEmpty) return _refusC(codeVersementMotifObligatoire, 'Le motif de l’annulation est obligatoire (il voyage avec la contre-passation).');
  final siens = [for (final v in versements) if (v['factureId'] == facture['id'] && v['statut'] != 'archive') v];
  final cible = siens.where((v) => '${v['id']}' == versementId && v['sens'] != sensContrepassation).toList();
  if (cible.isEmpty) return _refusC(codeVersementIntrouvable, 'Versement introuvable sur cette facture.');
  final annules = {for (final v in siens) if (v['sens'] == sensContrepassation) '${v['annule']}'};
  if (annules.contains(versementId)) return _refusC(codeVersementDejaAnnule, 'Ce versement est déjà annulé : une contre-passation ne se rejoue pas.');
  if ('${facture['numeroMecef'] ?? ''}'.isNotEmpty || facture['statutMecef'] == 'valide' || facture['statutMecef'] == 'normalisee') {
    return _refusC(codeVersementFactureNormalisee, 'La facture est normalisée : une pièce émise ne se réécrit pas. Passer par une facture d’avoir (Factures d’avoir).');
  }
  final lot = cible.first['lot'];
  final groupe = [for (final v in siens) if (v['sens'] != sensContrepassation && !annules.contains('${v['id']}') && (lot == null ? v['id'] == cible.first['id'] : v['lot'] == lot)) v];
  final total = groupe.fold<double>(0, (a, v) => a + _n(v['montant']));
  final ref = '${_faux(facture['numero']) ? facture['id'] : facture['numero']}';
  final fiches = <Map<String, Object?>>[];
  final posees = <Map<String, Object?>>[];
  final lignesIds = {for (final v in groupe) ...((v['lignes'] as List?) ?? const []).map((x) => '$x')};
  for (final v in groupe) {
    final numero = numeroSuivant('caisse.versements', date: aujourdhui, existants: [...versements, ...fiches]);
    fiches.add({
      'numero': numero,
      'factureId': facture['id'],
      'factureNumero': ref,
      'patient': facture['patient'],
      'sens': sensContrepassation,
      'annule': v['id'],
      'montant': v['montant'],
      'type': v['type'],
      'typeLibelle': v['typeLibelle'],
      'compteTresorerie': v['compteTresorerie'],
      if (v['modaliteLibelle'] != null) 'modaliteLibelle': v['modaliteLibelle'],
      'date': aujourdhui,
      'dateHeure': maintenant,
      'caissier': utilisateur,
      'motif': motif.trim(),
      'lot': v['lot'],
      'lignes': v['lignes'],
      'statut': 'actif',
    });
    // L'écriture inverse : débit des produits (706), crédit du compte de trésorerie du versement. Brouillon ; la créance de l'assureur n'est pas touchée (elle ne dépend pas du
    // règlement du patient).
    final base = {
      'numero': numeroPieceCaisse(facture, aujourdhui, [...ecritures, ...posees]),
      'date': aujourdhui,
      'journal': 'CAI',
      'journalLibelle': 'Journal de caisse-dépenses',
      'libelle': 'Annulation de versement $ref — ${v['typeLibelle'] ?? v['type']} — ${motif.trim()}',
      'pieceId': facture['id'],
      'pieceNumero': facture['numero'],
      'origine': 'Automatique — Caisse (contre-passation)',
      'statut': 'brouillon',
    };
    final m = _n(v['montant']);
    posees.addAll([
      {...base, 'compte': comptePrestations, 'debit': m, 'credit': 0.0},
      {...base, 'compte': '${v['compteTresorerie'] ?? compteCaisse}', 'debit': 0.0, 'credit': m},
    ]);
  }
  final lignesAvant = [for (final l in (facture['lignes'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  final lignesMaj = [
    for (final l in lignesAvant)
      if (lignesIds.contains('${l['id']}') && l['statutPaiement'] == 'paye')
        {for (final e in l.entries) if (!const {'montantRegle', 'payeLe', 'payePar'}.contains(e.key)) e.key: e.value, 'statutPaiement': 'du'}
      else
        l
  ];
  final paye = (_n(facture['montantPaye']) - total) > 0 ? _n(facture['montantPaye']) - total : 0.0;
  final reste = lignesMaj.isNotEmpty
      ? lignesMaj.where((l) => l['statutPaiement'] != 'paye').fold(0.0, (n, l) => n + _n(l['partPatient']))
      : ((facture['partPatient'] != null ? _n(facture['partPatient']) : _n(facture['montantTTC'])) - paye).clamp(0.0, double.infinity);
  double? base;
  final reglees = [for (final l in lignesMaj) if (l['statutPaiement'] == 'paye') l];
  if (reglees.isNotEmpty) {
    final mv = mecefMontants(lignes: [for (final l in reglees) ligneVersMecef(l)]);
    if (mv.ok) base = mv.montants!.base.toDouble();
  }
  return ResultatContrepassation(
      contrepassations: fiches,
      ecritures: posees,
      lignesRouvertes: [for (final l in lignesAvant) if (lignesIds.contains('${l['id']}') && l['statutPaiement'] == 'paye') '${l['id']}'],
      facture: {
        'lignes': lignesMaj,
        'montantPaye': paye,
        'reliquat': reste,
        'statutPaiement': paye > 0 ? 'partielle' : 'impayee',
        if (mecefActif && facture.containsKey('baseMecef')) 'baseMecef': base ?? paye,
      });
}

/// LA GARDE DU JOURNAL (RG-12, RG-14) : un versement ne se modifie ni ne s'archive — l'erreur se corrige par une CONTRE-PASSATION tracée ([contrepasserReglement]). Posée AU MOTEUR sur la
/// collection `versements` : masquer un bouton ne protège rien. `null` : l'opération est permise (l'insertion d'une nouvelle ligne).
String? gardeVersement(String operation, Map<String, Object?> fiche) => operation == 'inserer'
    ? null
    : 'VERSEMENT_NON_MODIFIABLE : un versement est une ligne de journal, elle ne se modifie ni ne s’archive. Pour corriger une erreur, annuler le règlement : une contre-passation est écrite avec son motif (geste réservé).';
