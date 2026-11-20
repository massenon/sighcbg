/// L'IMPORT DATÉ DE LA LIASSE FISCALE ET DU CLASSEUR DE BASELINE (écran `m12-liasse-import`, Direction de Baguidi, 16/11/2026, section 9 : « les chiffres déposés quittent le code pour la base,
/// sous forme d'IMPORT DATÉ — source, date de dépôt, auteur »). Fonctions PURES : le poste y branche sa collection et son journal, un test les rejoue sans magasin.
///
/// Ce que cet import fait, et ne fait pas :
///  * il accepte EXACTEMENT le schéma des documents d'import de démonstration (`apps/poste/tool/donnees/*_demo.json`) : même clés, mêmes types, aucune clé inconnue tolérée, aucune clé
///    manquante complétée. Un refus est NOMMÉ (code, chemin de la valeur fautive dans le document, motif, geste pour corriger) ;
///  * il ne recalcule rien et n'invente aucun chiffre : une liasse déposée porte ses propres écarts internes (le document de la clinique est CITÉ, jamais corrigé), donc aucune arithmétique n'est
///    imposée à la liasse. Le classeur, lui, est un tableau de la clinique dont les totaux se recoupent : un classeur dont les lignes ne somment pas à ses totaux est refusé ;
///  * il ne supprime rien (RG-14) : une version nouvelle s'AJOUTE, la plus récente fait foi ([DocumentsFiscaux.fiche]), une version se retire par ARCHIVAGE motivé, jamais par suppression ;
///  * la date de dépôt ne peut pas être dans le futur ni précéder la fin de l'exercice déposé ; une liasse qui porte sa propre date de dépôt ne peut pas la contredire.
///
/// Le journal d'audit (RG-12) ne reçoit JAMAIS le contenu comptable : [docFiscalResumeJournal] ne porte que le genre, l'exercice, la date, la source et des NOMBRES DE LIGNES.
library;

import 'dart:convert';

import 'documents_fiscaux.dart';

/// Un refus d'import : code stable, motif, geste pour corriger. [chemin] dit où, dans le document, la valeur fautive se trouve (vide pour un refus qui ne vise pas une valeur).
class RefusImportFiscal {
  const RefusImportFiscal(this.code, this.motif, this.geste, {this.chemin = ''});
  final String code;
  final String motif;
  final String geste;
  final String chemin;

  @override
  String toString() => '$code : $motif${chemin.isEmpty ? '' : ' [$chemin]'}';

  /// LA PHRASE que l'écran affiche : « code : motif (chemin). geste. » Le motif et le geste sont des phrases ÉCRITES AVEC leur point final (ou une parenthèse, un guillemet) : les coller par
  /// `'$motif. $geste'` donnait « …(Unexpected character).. Importer… ». La jonction est faite ICI, une fois, pour TOUS les refus : le point final de chaque morceau est retiré puis
  /// reposé une seule fois, jamais deux.
  String get message => refusFiscalPhrase(code, motif, geste, chemin: chemin);
}

/// Retire les points, points de suspension, virgules, points-virgules, deux-points et espaces de fin d'un morceau de phrase.
String refusFiscalSansPonctuationFinale(String t) => t.replaceFirst(RegExp(r'[\s.,;:…]+$'), '');

/// Assemble « code : motif (chemin). geste. » sans jamais doubler un signe de fin de phrase, quelle que soit la ponctuation finale du motif ou du geste.
String refusFiscalPhrase(String code, String motif, String geste, {String chemin = ''}) {
  final m = refusFiscalSansPonctuationFinale(motif);
  final g = refusFiscalSansPonctuationFinale(geste);
  final debut = '$code : $m${chemin.isEmpty ? '' : ' ($chemin)'}';
  return g.isEmpty ? '$debut.' : '$debut. $g.';
}

/// Les clés de premier niveau d'une liasse, dans l'ordre du document : toutes obligatoires, aucune autre admise.
const List<String> docFiscalClesLiasse = ['DEPOT', 'BILAN_ACTIF', 'BILAN_PASSIF', 'RESULTAT', 'FLUX', 'DISPONIBILITES', 'SYNTHESE', 'NOTES_SYNTHESE', 'ECARTS'];

/// Les clés d'un classeur de baseline : toutes obligatoires, aucune autre admise.
const List<String> docFiscalClesClasseur = [
  'annee', 'mois', 'chiffreAffaires', 'totalChiffreAffaires', 'depenses', 'totalDepenses', 'horsExploitation', 'totalHorsExploitation', 'totalCharges', 'resultat', 'controle'
];

/// L'IFU est un identifiant de 13 chiffres (même longueur que celle contrôlée à la facture normalisée).
const int docFiscalLongueurIfu = 13;

/// La tolérance des recoupements arithmétiques du classeur (un centime).
const double docFiscalTolerance = 0.01;

/// Un document lu : son genre (déduit de sa forme), son exercice, la date de dépôt qu'il porte lui-même (liasse seulement) et son contenu, tel que lu.
class DocumentFiscalLu {
  const DocumentFiscalLu({required this.genre, required this.exercice, required this.contenu, this.dateDepotPortee, this.sourcePortee, this.demonstration = ''});
  final String genre;
  final int exercice;
  final Map<String, Object?> contenu;

  /// La date de dépôt écrite DANS la liasse (`DEPOT.dateDepot`) ; `null` pour un classeur (il n'en porte pas).
  final String? dateDepotPortee;

  /// La source écrite dans la liasse (`DEPOT.source`), proposée à l'agent comme valeur de départ ; `null` pour un classeur.
  final String? sourcePortee;

  /// La mention de démonstration de la liasse (`DEPOT.demonstration`), vide pour un document réel.
  final String demonstration;
  bool get estDemonstration => demonstration.trim().isNotEmpty;
}

/// Le verdict d'une lecture : un document, ou un refus nommé.
class VerdictLectureFiscale {
  const VerdictLectureFiscale._(this.document, this.refus);
  factory VerdictLectureFiscale.ok(DocumentFiscalLu d) => VerdictLectureFiscale._(d, null);
  factory VerdictLectureFiscale.refus(RefusImportFiscal r) => VerdictLectureFiscale._(null, r);
  final DocumentFiscalLu? document;
  final RefusImportFiscal? refus;
  bool get accepte => document != null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// LECTURE ET VALIDATION STRICTE
// ---------------------------------------------------------------------------------------------------------------------------------------------

RefusImportFiscal _r(String code, String motif, String geste, [String chemin = '']) => RefusImportFiscal(code, motif, geste, chemin: chemin);

const String _gesteCorriger = 'Corriger le document source et le réimporter : l’import ne complète ni ne corrige rien.';

/// Lit le TEXTE d'un fichier (JSON) et le valide. Le genre est déduit de la forme : une racine qui porte `DEPOT` est une liasse, une racine qui porte `annee` est un classeur ; tout
/// autre fichier est refusé (`GENRE_INDETERMINE`). Aucune valeur n'est corrigée en route.
VerdictLectureFiscale lireDocumentFiscal(String texte) {
  if (texte.trim().isEmpty) return VerdictLectureFiscale.refus(_r('FICHIER_VIDE', 'Le fichier est vide.', 'Choisir le document de liasse ou de classeur à importer.'));
  Object? racine;
  try {
    racine = jsonDecode(texte);
  } on FormatException catch (e) {
    return VerdictLectureFiscale.refus(_r('JSON_ILLISIBLE', 'Le fichier n’est pas un JSON lisible (${e.message}).', 'Importer le document tel que remis, au format JSON.'));
  }
  if (racine is! Map) {
    return VerdictLectureFiscale.refus(_r('RACINE_NON_OBJET', 'Le document doit être un objet (une liasse ou un classeur), pas ${racine is List ? 'une liste' : 'une valeur isolée'}.', _gesteCorriger));
  }
  final doc = racine.cast<String, Object?>();
  if (doc.containsKey('DEPOT')) return _validerLiasse(doc);
  if (doc.containsKey('annee')) return _validerClasseur(doc);
  return VerdictLectureFiscale.refus(_r('GENRE_INDETERMINE',
      'Le document n’est ni une liasse (clé « DEPOT » attendue) ni un classeur de baseline (clé « annee » attendue) : sa forme n’est pas reconnue.', 'Choisir un document de liasse ou de classeur au schéma des documents d’import.'));
}

bool _estNombre(Object? v) => v is num && v.isFinite;
bool _estEntier(Object? v) => v is int || (v is double && v.isFinite && v == v.roundToDouble());
bool _estTexte(Object? v) => v is String;
bool _texteNonVide(Object? v) => v is String && v.trim().isNotEmpty;

/// Une date AAAA-MM-JJ réelle (le 31 février est refusé).
bool docFiscalDateValide(Object? v) {
  if (v is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return false;
  final d = DateTime.tryParse(v);
  return d != null && '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}' == v;
}

/// Contrôle les clés d'un objet : toutes les [requises] présentes, aucune hors [admises]. Rend le premier refus, ou `null`.
RefusImportFiscal? _cles(Map m, String chemin, {required Iterable<String> requises, Iterable<String> facultatives = const []}) {
  for (final k in requises) {
    if (!m.containsKey(k)) return _r('CLE_MANQUANTE', 'La clé « $k » manque${chemin.isEmpty ? '' : ' à « $chemin »'}.', _gesteCorriger, chemin.isEmpty ? k : '$chemin.$k');
  }
  final admises = {...requises, ...facultatives};
  for (final k in m.keys) {
    if (!admises.contains('$k')) return _r('CLE_INCONNUE', 'La clé « $k » n’existe pas dans le schéma${chemin.isEmpty ? '' : ' de « $chemin »'} : rien n’est ignoré en silence.', _gesteCorriger, chemin.isEmpty ? '$k' : '$chemin.$k');
  }
  return null;
}

RefusImportFiscal _type(String chemin, String attendu) => _r('TYPE_INVALIDE', 'La valeur attendue est $attendu.', _gesteCorriger, chemin);

/// Une liste d'objets, ligne par ligne : chaque ligne passe par [ligne] (qui rend un refus ou `null`).
RefusImportFiscal? _lignes(Object? v, String chemin, {required bool nonVide, required RefusImportFiscal? Function(Map<String, Object?> l, String c) ligne}) {
  if (v is! List) return _type(chemin, 'une liste');
  if (nonVide && v.isEmpty) return _r('LISTE_VIDE', 'La liste « $chemin » ne peut pas être vide : un formulaire déposé porte ses lignes.', _gesteCorriger, chemin);
  for (var i = 0; i < v.length; i++) {
    final c = '$chemin[$i]';
    final l = v[i];
    if (l is! Map) return _type(c, 'un objet');
    final r = ligne(l.cast<String, Object?>(), c);
    if (r != null) return r;
  }
  return null;
}

RefusImportFiscal? _comptes(Object? v, String chemin) {
  if (v is! List) return _type(chemin, 'une liste de numéros de compte');
  for (var i = 0; i < v.length; i++) {
    if (v[i] is! String || !RegExp(r'^\d{1,8}$').hasMatch(v[i] as String)) return _r('COMPTE_INVALIDE', 'Un numéro de compte est une suite de chiffres (« ${v[i]} » n’en est pas une).', _gesteCorriger, '$chemin[$i]');
  }
  return null;
}

RefusImportFiscal? _montant(Map<String, Object?> l, String c, String cle, {bool nul = false}) {
  final v = l[cle];
  if (v == null && nul) return null;
  if (!_estNombre(v)) return _type('$c.$cle', nul ? 'un nombre (ou null quand la case du formulaire est vide)' : 'un nombre');
  return null;
}

/// Les références d'un formulaire sont UNIQUES (une référence nomme une case : AD, XB, ZA…).
RefusImportFiscal? _refsUniques(List lignes, String chemin) {
  final vues = <String>{};
  for (var i = 0; i < lignes.length; i++) {
    final l = lignes[i];
    if (l is Map && l['ref'] is String && (l['ref'] as String).isNotEmpty && !vues.add('${l['ref']}')) return _r('REFERENCE_EN_DOUBLE', 'La référence « ${l['ref']} » figure deux fois : une référence nomme une case du formulaire.', _gesteCorriger, '$chemin[$i].ref');
  }
  return null;
}

VerdictLectureFiscale _validerLiasse(Map<String, Object?> d) {
  VerdictLectureFiscale refus(RefusImportFiscal r) => VerdictLectureFiscale.refus(r);
  var r = _cles(d, '', requises: docFiscalClesLiasse);
  if (r != null) return refus(r);

  // --- DEPOT
  final depot = d['DEPOT'];
  if (depot is! Map) return refus(_type('DEPOT', 'un objet'));
  final dep = depot.cast<String, Object?>();
  r = _cles(dep, 'DEPOT', requises: ['denomination', 'ifu', 'dateDepot', 'code', 'exerciceN', 'exerciceN1', 'administration', 'source'], facultatives: ['demonstration']);
  if (r != null) return refus(r);
  for (final k in ['denomination', 'code', 'administration', 'source']) {
    if (!_texteNonVide(dep[k])) return refus(_r('DEPOT_INCOMPLET', 'L’en-tête du dépôt doit porter « $k », non vide.', _gesteCorriger, 'DEPOT.$k'));
  }
  if (dep['demonstration'] != null && !_estTexte(dep['demonstration'])) return refus(_type('DEPOT.demonstration', 'un texte'));
  final ifu = '${dep['ifu']}';
  if (dep['ifu'] is! String || !RegExp('^\\d{$docFiscalLongueurIfu}\$').hasMatch(ifu)) {
    return refus(_r('IFU_INVALIDE', 'L’IFU du dépôt doit comporter exactement $docFiscalLongueurIfu chiffres.', _gesteCorriger, 'DEPOT.ifu'));
  }
  if (!docFiscalDateValide(dep['dateDepot'])) return refus(_r('DATE_DEPOT_INVALIDE', 'La date de dépôt du document doit être une date réelle au format AAAA-MM-JJ.', _gesteCorriger, 'DEPOT.dateDepot'));
  if (!_estEntier(dep['exerciceN']) || !_estEntier(dep['exerciceN1'])) return refus(_type('DEPOT.exerciceN', 'une année entière (exerciceN et exerciceN1)'));
  final n = (dep['exerciceN'] as num).toInt();
  final n1 = (dep['exerciceN1'] as num).toInt();
  if (n < 2000 || n > 2100) return refus(_r('EXERCICE_INVALIDE', 'L’exercice N doit être une année plausible (2000 à 2100).', _gesteCorriger, 'DEPOT.exerciceN'));
  if (n1 != n - 1) return refus(_r('EXERCICE_INCOHERENT', 'L’exercice N-1 ($n1) doit être l’année qui précède l’exercice N ($n).', _gesteCorriger, 'DEPOT.exerciceN1'));

  // --- BILAN ACTIF : brut, amortissements, net, net N-1
  r = _lignes(d['BILAN_ACTIF'], 'BILAN_ACTIF', nonVide: true, ligne: (l, c) {
    final k = _cles(l, c, requises: ['ref', 'libelle', 'brut', 'amort', 'net', 'netN1'], facultatives: ['note', 't', 'comptes']);
    if (k != null) return k;
    return _ligneCommune(l, c) ?? _montant(l, c, 'brut') ?? _montant(l, c, 'amort') ?? _montant(l, c, 'net') ?? _montant(l, c, 'netN1');
  });
  if (r != null) return refus(r);
  r = _refsUniques(d['BILAN_ACTIF'] as List, 'BILAN_ACTIF');
  if (r != null) return refus(r);

  // --- BILAN PASSIF
  r = _lignes(d['BILAN_PASSIF'], 'BILAN_PASSIF', nonVide: true, ligne: (l, c) {
    final k = _cles(l, c, requises: ['ref', 'libelle', 'net', 'netN1'], facultatives: ['note', 't', 'comptes']);
    if (k != null) return k;
    return _ligneCommune(l, c) ?? _montant(l, c, 'net') ?? _montant(l, c, 'netN1');
  });
  if (r != null) return refus(r);
  r = _refsUniques(d['BILAN_PASSIF'] as List, 'BILAN_PASSIF');
  if (r != null) return refus(r);

  // --- COMPTE DE RÉSULTAT
  r = _lignes(d['RESULTAT'], 'RESULTAT', nonVide: true, ligne: (l, c) {
    final k = _cles(l, c, requises: ['ref', 'libelle', 'n', 'n1'], facultatives: ['signe', 'repere', 'note', 't', 'comptes']);
    if (k != null) return k;
    if (l['signe'] != null && !const {'+', '-', '-/+'}.contains(l['signe'])) return _r('SIGNE_INVALIDE', 'Le signe d’une ligne du compte de résultat est « + », « - » ou « -/+ ».', _gesteCorriger, '$c.signe');
    if (l['repere'] != null && !_texteNonVide(l['repere'])) return _type('$c.repere', 'un repère (lettre) non vide');
    return _ligneCommune(l, c) ?? _montant(l, c, 'n') ?? _montant(l, c, 'n1');
  });
  if (r != null) return refus(r);
  r = _refsUniques(d['RESULTAT'] as List, 'RESULTAT');
  if (r != null) return refus(r);

  // --- TABLEAU DES FLUX : une ligne est soit un intitulé de section seul, soit une case chiffrée
  final ecartsDeclares = <String>{};
  final ecarts = d['ECARTS'];
  if (ecarts is! List) return refus(_type('ECARTS', 'une liste'));
  for (var i = 0; i < ecarts.length; i++) {
    final e = ecarts[i];
    if (e is! Map) return refus(_type('ECARTS[$i]', 'un objet'));
    final em = e.cast<String, Object?>();
    final k = _cles(em, 'ECARTS[$i]', requises: ['cle', 'titre', 'constat', 'lecture']);
    if (k != null) return refus(k);
    for (final c in ['cle', 'titre', 'constat', 'lecture']) {
      if (!_texteNonVide(em[c])) return refus(_r('TEXTE_VIDE', 'Un écart signalé porte « $c », non vide.', _gesteCorriger, 'ECARTS[$i].$c'));
    }
    if (!ecartsDeclares.add('${em['cle']}')) return refus(_r('ECART_EN_DOUBLE', 'L’écart « ${em['cle']} » est déclaré deux fois.', _gesteCorriger, 'ECARTS[$i].cle'));
  }
  RefusImportFiscal? ecartConnu(Map<String, Object?> l, String c) {
    if (l['ecart'] == null) return null;
    if (!ecartsDeclares.contains('${l['ecart']}')) {
      return _r('ECART_INCONNU', 'La ligne renvoie à l’écart « ${l['ecart']} », qu’aucune entrée de « ECARTS » ne déclare.', _gesteCorriger, '$c.ecart');
    }
    return null;
  }

  r = _lignes(d['FLUX'], 'FLUX', nonVide: true, ligne: (l, c) {
    if (l.containsKey('section')) {
      final k = _cles(l, c, requises: ['section']);
      if (k != null) return k;
      return _texteNonVide(l['section']) ? null : _r('TEXTE_VIDE', 'Un intitulé de section ne peut pas être vide.', _gesteCorriger, '$c.section');
    }
    final k = _cles(l, c, requises: ['ref', 'libelle', 'n', 'n1'], facultatives: ['t', 'repere', 'ecart']);
    if (k != null) return k;
    return _ligneCommune(l, c) ?? _montant(l, c, 'n') ?? _montant(l, c, 'n1') ?? ecartConnu(l, c);
  });
  if (r != null) return refus(r);
  r = _refsUniques(d['FLUX'] as List, 'FLUX');
  if (r != null) return refus(r);

  // --- NOTE 11 : DISPONIBILITÉS
  final disp = d['DISPONIBILITES'];
  if (disp is! Map) return refus(_type('DISPONIBILITES', 'un objet'));
  final dm = disp.cast<String, Object?>();
  r = _cles(dm, 'DISPONIBILITES', requises: ['note', 'lignes', 'commentaires', 'nb']);
  if (r != null) return refus(r);
  if (!_texteNonVide(dm['note'])) return refus(_r('TEXTE_VIDE', 'La note porte son intitulé.', _gesteCorriger, 'DISPONIBILITES.note'));
  if (!_estTexte(dm['nb'])) return refus(_type('DISPONIBILITES.nb', 'un texte'));
  final com = dm['commentaires'];
  if (com is! List || com.any((x) => x is! String)) return refus(_type('DISPONIBILITES.commentaires', 'une liste de textes'));
  r = _lignes(dm['lignes'], 'DISPONIBILITES.lignes', nonVide: true, ligne: (l, c) {
    final k = _cles(l, c, requises: ['libelle', 'n', 'n1'], facultatives: ['t', 'comptes']);
    if (k != null) return k;
    return _ligneCommune(l, c, avecRef: false) ?? _montant(l, c, 'n', nul: true) ?? _montant(l, c, 'n1', nul: true);
  });
  if (r != null) return refus(r);

  // --- NOTE 34 : FICHE DE SYNTHÈSE (intitulés de section, lignes chiffrées, ligne de contrôle)
  r = _lignes(d['SYNTHESE'], 'SYNTHESE', nonVide: true, ligne: (l, c) {
    if (l.containsKey('section') || l.containsKey('section2')) {
      final cle = l.containsKey('section') ? 'section' : 'section2';
      final k = _cles(l, c, requises: [cle]);
      if (k != null) return k;
      return _texteNonVide(l[cle]) ? null : _r('TEXTE_VIDE', 'Un intitulé de section ne peut pas être vide.', _gesteCorriger, '$c.$cle');
    }
    if (l.containsKey('controle')) {
      final k = _cles(l, c, requises: ['controle', 'libelle']);
      if (k != null) return k;
      if (l['controle'] is! bool) return _type('$c.controle', 'un booléen');
      return _texteNonVide(l['libelle']) ? null : _r('TEXTE_VIDE', 'Un libellé ne peut pas être vide.', _gesteCorriger, '$c.libelle');
    }
    final k = _cles(l, c, requises: ['libelle', 'n', 'n1'], facultatives: ['t', 'variation', 'unite', 'ecart']);
    if (k != null) return k;
    if (l['variation'] != null && !_estNombre(l['variation'])) return _type('$c.variation', 'un nombre');
    if (l['unite'] != null && !_texteNonVide(l['unite'])) return _type('$c.unite', 'un texte non vide');
    return _ligneCommune(l, c, avecRef: false) ?? _montant(l, c, 'n', nul: true) ?? _montant(l, c, 'n1', nul: true) ?? ecartConnu(l, c);
  });
  if (r != null) return refus(r);

  // --- NOTES DE BAS DE FORMULAIRE
  final notes = d['NOTES_SYNTHESE'];
  if (notes is! List || notes.any((x) => x is! String)) return refus(_type('NOTES_SYNTHESE', 'une liste de textes'));

  return VerdictLectureFiscale.ok(DocumentFiscalLu(
      genre: docFiscalLiasse,
      exercice: n,
      contenu: d,
      dateDepotPortee: dep['dateDepot'] as String,
      sourcePortee: dep['source'] as String,
      demonstration: '${dep['demonstration'] ?? ''}'));
}

/// Les propriétés communes à une ligne de formulaire : `ref` et `libelle` (textes non vides), `t` (`total` ou `grand`), `note` (texte), `comptes` (numéros de compte).
RefusImportFiscal? _ligneCommune(Map<String, Object?> l, String c, {bool avecRef = true}) {
  // La référence est un texte : elle peut être VIDE (le formulaire déposé a une ligne de total sans case nommée, « Variation du BF »), mais elle est toujours écrite.
  if (avecRef && !_estTexte(l['ref'])) return _type('$c.ref', 'un texte (la référence de la case, vide si le formulaire n’en nomme pas)');
  if (!_texteNonVide(l['libelle'])) return _r('TEXTE_VIDE', 'Une ligne du formulaire porte son libellé, non vide.', _gesteCorriger, '$c.libelle');
  if (l['t'] != null && l['t'] != 'total' && l['t'] != 'grand') return _r('NIVEAU_INVALIDE', 'Le niveau d’une ligne (« t ») est « total » ou « grand ».', _gesteCorriger, '$c.t');
  if (l['note'] != null && !_estTexte(l['note'])) return _type('$c.note', 'un texte');
  if (l['comptes'] != null) return _comptes(l['comptes'], '$c.comptes');
  return null;
}

VerdictLectureFiscale _validerClasseur(Map<String, Object?> d) {
  VerdictLectureFiscale refus(RefusImportFiscal r) => VerdictLectureFiscale.refus(r);
  var r = _cles(d, '', requises: docFiscalClesClasseur);
  if (r != null) return refus(r);
  if (!_estEntier(d['annee'])) return refus(_type('annee', 'une année entière'));
  final annee = (d['annee'] as num).toInt();
  if (annee < 2000 || annee > 2100) return refus(_r('EXERCICE_INVALIDE', 'L’année du classeur doit être plausible (2000 à 2100).', _gesteCorriger, 'annee'));

  final mois = d['mois'];
  if (mois is! List || mois.length != 12 || mois.any((x) => !_texteNonVide(x))) return refus(_r('MOIS_INVALIDES', 'Le classeur porte douze mois nommés.', _gesteCorriger, 'mois'));
  final ca = d['chiffreAffaires'];
  if (ca is! List || ca.length != 12 || ca.any((x) => !_estNombre(x))) return refus(_r('SERIE_INVALIDE', 'Le chiffre d’affaires porte douze montants (un par mois).', _gesteCorriger, 'chiffreAffaires'));
  for (final k in ['totalChiffreAffaires', 'totalDepenses', 'totalHorsExploitation', 'totalCharges', 'resultat']) {
    if (!_estNombre(d[k])) return refus(_type(k, 'un nombre'));
  }
  final hors = d['horsExploitation'];
  if (hors is! Map || hors.entries.any((e) => e.key is! String || !_texteNonVide(e.value))) {
    return refus(_r('HORS_EXPLOITATION_INVALIDE', 'Les postes hors exploitation sont un dictionnaire « numéro de compte → libellé ».', _gesteCorriger, 'horsExploitation'));
  }
  final controle = d['controle'];
  if (controle is! Map) return refus(_type('controle', 'un objet'));
  final cm = controle.cast<String, Object?>();
  r = _cles(cm, 'controle', requises: ['totalDetail', 'totalClasseur', 'ecart', 'postesSansCompte', 'montantSansCompte']);
  if (r != null) return refus(r);
  for (final k in ['totalDetail', 'totalClasseur', 'ecart', 'montantSansCompte']) {
    if (!_estNombre(cm[k])) return refus(_type('controle.$k', 'un nombre'));
  }
  if (!_estEntier(cm['postesSansCompte'])) return refus(_type('controle.postesSansCompte', 'un nombre entier'));

  var totalPostes = 0.0, totalHors = 0.0, totalSansCompte = 0.0;
  var nbSansCompte = 0;
  r = _lignes(d['depenses'], 'depenses', nonVide: true, ligne: (l, c) {
    final k = _cles(l, c, requises: ['num', 'libelle', 'mois', 'total', 'aRattacher']);
    if (k != null) return k;
    if (l['num'] != null && (l['num'] is! String || !RegExp(r'^\d{1,8}$').hasMatch(l['num'] as String))) return _r('COMPTE_INVALIDE', 'Le numéro de compte d’un poste est une suite de chiffres, ou null s’il reste à rattacher.', _gesteCorriger, '$c.num');
    if (!_texteNonVide(l['libelle'])) return _r('TEXTE_VIDE', 'Un poste de dépense porte son libellé.', _gesteCorriger, '$c.libelle');
    if (l['aRattacher'] is! bool) return _type('$c.aRattacher', 'un booléen');
    if (l['aRattacher'] == true && l['num'] != null) return _r('RATTACHEMENT_INCOHERENT', 'Un poste « à rattacher » ne porte pas encore de numéro de compte.', _gesteCorriger, '$c.aRattacher');
    if (l['aRattacher'] == false && l['num'] == null) return _r('RATTACHEMENT_INCOHERENT', 'Un poste sans numéro de compte est « à rattacher ».', _gesteCorriger, '$c.aRattacher');
    final m = l['mois'];
    if (m is! List || m.length != 12 || m.any((x) => !_estNombre(x))) return _r('SERIE_INVALIDE', 'Un poste de dépense porte douze montants (un par mois).', _gesteCorriger, '$c.mois');
    if (!_estNombre(l['total'])) return _type('$c.total', 'un nombre');
    final somme = m.fold<double>(0, (a, x) => a + (x as num));
    if ((somme - (l['total'] as num)).abs() > docFiscalTolerance) {
      return _r('TOTAL_POSTE_INCOHERENT', 'Les douze mois du poste somment ${_f(somme)} alors que son total est ${_f(l['total'] as num)} : le classeur ne se recoupe pas.', _gesteCorriger, '$c.total');
    }
    totalPostes += (l['total'] as num);
    if (l['num'] != null && hors.containsKey(l['num'])) totalHors += (l['total'] as num);
    if (l['aRattacher'] == true) {
      nbSansCompte++;
      totalSansCompte += (l['total'] as num);
    }
    return null;
  });
  if (r != null) return refus(r);

  RefusImportFiscal? recoupe(String nom, num attendu, double calcule, String chemin) => (calcule - attendu).abs() > docFiscalTolerance
      ? _r('TOTAL_INCOHERENT', '$nom : le document annonce ${_f(attendu)}, les lignes donnent ${_f(calcule)} : le classeur ne se recoupe pas, rien n’est recalculé à la place du document.', _gesteCorriger, chemin)
      : null;
  final somCa = ca.fold<double>(0, (a, x) => a + (x as num));
  r = recoupe('Chiffre d’affaires', d['totalChiffreAffaires'] as num, somCa, 'totalChiffreAffaires') ??
      recoupe('Total des dépenses', d['totalDepenses'] as num, totalPostes, 'totalDepenses') ??
      recoupe('Dépenses hors exploitation', d['totalHorsExploitation'] as num, totalHors, 'totalHorsExploitation') ??
      recoupe('Charges d’exploitation', d['totalCharges'] as num, totalPostes - totalHors, 'totalCharges') ??
      recoupe('Résultat', d['resultat'] as num, somCa - (totalPostes - totalHors), 'resultat') ??
      recoupe('Contrôle : total du détail', cm['totalDetail'] as num, totalPostes, 'controle.totalDetail') ??
      recoupe('Contrôle : montant des postes sans compte', cm['montantSansCompte'] as num, totalSansCompte, 'controle.montantSansCompte');
  if (r != null) return refus(r);
  if ((cm['postesSansCompte'] as num).toInt() != nbSansCompte) {
    return refus(_r('TOTAL_INCOHERENT', 'Contrôle : le document compte ${cm['postesSansCompte']} poste(s) sans compte, les lignes en portent $nbSansCompte.', _gesteCorriger, 'controle.postesSansCompte'));
  }
  return VerdictLectureFiscale.ok(DocumentFiscalLu(genre: docFiscalClasseur, exercice: annee, contenu: d));
}

String _f(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

// ---------------------------------------------------------------------------------------------------------------------------------------------
// L'IMPORT : une version NOUVELLE, jamais un écrasement
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le verdict d'un import : la fiche à écrire, ou un refus nommé.
class VerdictImportFiscal {
  const VerdictImportFiscal._(this.fiche, this.refus);
  factory VerdictImportFiscal.ok(Map<String, Object?> f) => VerdictImportFiscal._(f, null);
  factory VerdictImportFiscal.refus(RefusImportFiscal r) => VerdictImportFiscal._(null, r);
  final Map<String, Object?>? fiche;
  final RefusImportFiscal? refus;
  bool get accepte => fiche != null;
}

/// Prépare la fiche d'un import daté. Les gardes, dans l'ordre : le droit ([peutImporter], le geste réservé), un poste qui n'est pas rattaché ([estFileul] : la collection est tenue par la
/// mère), la source (obligatoire), l'auteur (RG-12), la date de dépôt (réelle, pas future, pas antérieure à la fin de l'exercice déposé, identique à celle que la liasse porte), puis
/// l'unicité de la fiche. [existantes] : TOUTES les fiches de la collection, archivées comprises (une version archivée garde son identité, elle ne se recycle pas).
///
/// [dateDepot] : la date AAAA-MM-JJ du dépôt ; pour une liasse, `null` reprend celle du document. [importeLe] : l'instant du geste, au format ISO.
VerdictImportFiscal preparerImportFiscal({
  required DocumentFiscalLu document,
  required String? dateDepot,
  required String source,
  required String auteur,
  required DateTime maintenant,
  required Iterable<Map<String, Object?>> existantes,
  required bool peutImporter,
  bool estFileul = false,
}) {
  VerdictImportFiscal refus(String code, String motif, String geste, [String chemin = '']) => VerdictImportFiscal.refus(_r(code, motif, geste, chemin));
  if (!peutImporter) {
    return refus('GESTE_RESERVE', 'Importer une liasse ou un classeur est le geste réservé « Importer ou archiver la liasse fiscale déposée et le classeur de baseline » : votre rôle ne le détient pas.',
        'Demander au comptable ou à la DAF, ou faire accorder le geste au rôle dans « Rôles et permissions › Gestes réservés ».');
  }
  if (estFileul) {
    return refus('REGLE_SUR_LA_MERE', 'La liasse et le classeur sont écrits par la mère (référentiel diffusé aux postes) : un poste rattaché ne les écrit pas lui-même, il dépose une demande d’import.', 'Déposer la demande d’import depuis l’écran « Import de la liasse fiscale » : la mère la rejoue et la version revient par la synchronisation.');
  }
  if (source.trim().isEmpty) return refus('SOURCE_ABSENTE', 'Un document importé porte sa source (d’où il vient) : un chiffre sans origine ne se cite pas.', 'Indiquer la source (ex. « Liasse remise à la DGI le … », « Classeur de l’expert-comptable »).');
  if (auteur.trim().isEmpty) return refus('AUTEUR_ABSENT', 'Aucune action anonyme (RG-12) : l’import porte son auteur.', 'Ouvrir une session nominative.');
  final jour = (dateDepot ?? document.dateDepotPortee ?? '').trim();
  if (jour.isEmpty) return refus('DATE_DEPOT_ABSENTE', 'La date de dépôt est obligatoire : c’est elle qui décide de la version qui fait foi.', 'Saisir la date de dépôt (AAAA-MM-JJ).');
  if (!docFiscalDateValide(jour)) return refus('DATE_DEPOT_INVALIDE', 'La date de dépôt doit être une date réelle au format AAAA-MM-JJ.', 'Corriger la date de dépôt.');
  if (document.dateDepotPortee != null && document.dateDepotPortee != jour) {
    return refus('DATE_DEPOT_DIVERGENTE', 'La liasse porte elle-même la date de dépôt ${document.dateDepotPortee} : elle ne peut pas être importée à une autre date (${jour}).',
        'Reprendre la date du document, ou corriger le document si la date qu’il porte est fausse.');
  }
  final auj = _iso(maintenant);
  if (jour.compareTo(auj) > 0) return refus('DATE_DEPOT_FUTURE', 'La date de dépôt ($jour) est postérieure à aujourd’hui ($auj) : un dépôt qui n’a pas eu lieu ne s’importe pas.', 'Corriger la date de dépôt.');
  if (jour.compareTo('${document.exercice}-12-31') <= 0) {
    return refus('DATE_DEPOT_AVANT_EXERCICE', 'Le dépôt du $jour précède la fin de l’exercice ${document.exercice} : un document ne se dépose pas avant la clôture de l’exercice qu’il décrit.', 'Corriger la date de dépôt ou l’exercice du document.');
  }
  final base = 'doc-fiscal-${document.genre}-${document.exercice}-$jour';
  final ids = {for (final f in existantes) '${f['id']}'};
  var id = base;
  var rang = 1;
  // Un dépôt rectifié le même jour est une version de plus : l'identité d'une version archivée ne se recycle pas.
  while (ids.contains(id)) {
    rang++;
    id = '$base-r${rang.toString().padLeft(2, '0')}';
  }
  final fiche = docFiscalFiche(
      genre: document.genre, exercice: document.exercice, dateDepot: jour, source: source.trim(), auteur: auteur.trim(), importeLe: maintenant.toUtc().toIso8601String(), contenu: document.contenu);
  fiche['id'] = id;
  if (document.estDemonstration) fiche['demonstration'] = true;
  return VerdictImportFiscal.ok(fiche);
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Prépare l'archivage d'une version (RG-14 : jamais une suppression) : le patch à écrire sur la fiche, ou un refus nommé. Le motif est obligatoire ; l'auteur aussi.
({Map<String, Object?>? patch, RefusImportFiscal? refus}) preparerArchivageFiscal({
  required Map<String, Object?>? fiche,
  required String motif,
  required String auteur,
  required DateTime maintenant,
  required bool peutImporter,
  bool estFileul = false,
}) {
  ({Map<String, Object?>? patch, RefusImportFiscal? refus}) non(String code, String motif, String geste) => (patch: null, refus: _r(code, motif, geste));
  if (!peutImporter) return non('GESTE_RESERVE', 'Archiver une version est le geste réservé « Importer ou archiver la liasse fiscale déposée et le classeur de baseline » : votre rôle ne le détient pas.', 'Demander au comptable ou à la DAF.');
  if (estFileul) return non('REGLE_SUR_LA_MERE', 'Les versions sont tenues par la mère : un poste rattaché ne les archive pas.', 'Archiver la version sur le poste mère.');
  if (fiche == null) return non('VERSION_INCONNUE', 'Cette version n’existe pas.', 'Choisir une version de la liste.');
  if (fiche['statut'] == 'archive') return non('DEJA_ARCHIVEE', 'Cette version est déjà archivée.', 'Aucun.');
  if (motif.trim().isEmpty) return non('MOTIF_ABSENT', 'Archiver une version se motive : on relira pourquoi elle ne fait plus foi.', 'Saisir le motif de l’archivage.');
  if (auteur.trim().isEmpty) return non('AUTEUR_ABSENT', 'Aucune action anonyme (RG-12) : l’archivage porte son auteur.', 'Ouvrir une session nominative.');
  return (
    patch: {
      'statutAvantArchivage': fiche['statut'],
      'statut': 'archive',
      'archiveLe': maintenant.toUtc().toIso8601String(),
      'archivePar': auteur.trim(),
      'motifArchivage': motif.trim(),
    },
    refus: null
  );
}

/// Une version de la liste : la fiche, et le rôle qu'elle joue (en force, antérieure, archivée).
class VersionFiscale {
  const VersionFiscale(this.fiche, this.etat);
  final Map<String, Object?> fiche;

  /// `en_force` : la version que lisent les écrans pour son genre ; `anterieure` : active mais supplantée par une version plus récente ; `archivee` : retirée par archivage.
  final String etat;
  String get id => '${fiche['id']}';
}

const String versionFiscaleEnForce = 'en_force';
const String versionFiscaleAnterieure = 'anterieure';
const String versionFiscaleArchivee = 'archivee';

/// Les versions importées d'un genre, de la plus récente à la plus ancienne (même clé que le registre : date d'effet, instant d'import, identifiant), archivées comprises : une version
/// retirée reste LISIBLE. [enForce] est la fiche que [DocumentsFiscaux] fait valoir (calculée ici, par la même règle).
List<VersionFiscale> versionsFiscales(Iterable<Map<String, Object?>> fiches, String genre) {
  String cle(Map<String, Object?> f) => '${f['dateEffet'] ?? ''}|${f['importeLe'] ?? ''}|${f['id'] ?? ''}';
  final du = [for (final f in fiches) if (f['genre'] == genre && f['contenu'] is Map) f]..sort((a, b) => cle(b).compareTo(cle(a)));
  String? idEnForce;
  for (final f in du) {
    if (f['statut'] != 'archive') {
      idEnForce = '${f['id']}';
      break;
    }
  }
  return [
    for (final f in du) VersionFiscale(f, f['statut'] == 'archive' ? versionFiscaleArchivee : ('${f['id']}' == idEnForce ? versionFiscaleEnForce : versionFiscaleAnterieure))
  ];
}

/// Le NOMBRE de lignes de chaque formulaire d'un contenu : la seule chose qu'un résumé (écran, journal) dit du contenu.
Map<String, int> docFiscalNombresDeLignes(Map<String, Object?> contenu) {
  final r = <String, int>{};
  for (final e in contenu.entries) {
    final v = e.value;
    if (v is List) r[e.key] = v.length;
  }
  final disp = contenu['DISPONIBILITES'];
  if (disp is Map && disp['lignes'] is List) r['DISPONIBILITES'] = (disp['lignes'] as List).length;
  return r;
}

/// Ce que le journal d'audit reçoit d'un import : l'identité de la version, sa source et des NOMBRES DE LIGNES — jamais un montant, un compte ni un libellé du document.
Map<String, Object?> docFiscalResumeJournal(Map<String, Object?> fiche) => {
      'genre': fiche['genre'],
      'exercice': fiche['exercice'],
      'dateDepot': fiche['dateEffet'],
      'source': fiche['source'],
      'lignes': docFiscalNombresDeLignes((fiche['contenu'] as Map).cast<String, Object?>()),
    };
