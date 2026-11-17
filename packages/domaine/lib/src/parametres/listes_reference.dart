/// LES LISTES DE RÉFÉRENCE (lot « listes de référence » de l'inventaire des valeurs en dur, 17/11/2026) : les listes de libellés métier qui vivaient en constantes dans le code
/// (natures de courrier, motifs d'avoir, services, catégories du parc technique…) sont des RÉGLAGES `texte` datés du registre des paramètres (`definitions.dart`, familles
/// `listes_*`) : valeurs séparées par un point-virgule, une nouvelle version datée par correction (jamais écrasée), semées au premier démarrage de la mère et reçues par les
/// fileuls (famille R). Ce fichier est le seul lecteur.
///
/// REGISTRE DE PROCESSUS, comme `Numerotation` : le poste branche la collection `parametres` au démarrage ([brancher]) ; sans branchement (domaine seul, test), la valeur lue est la
/// liste D'ATTENTE de la définition. Une liste vide ou illisible retombe elle aussi sur la liste d'attente : un formulaire ne se retrouve jamais sans aucun choix.
library;

import 'definitions.dart';
import 'parametres.dart';

class ListesReference {
  ListesReference._();

  static Iterable<Map<String, Object?>> Function()? _fiches;
  static DateTime Function() _horloge = DateTime.now;

  /// Branche le registre sur les fiches du registre des paramètres (le poste : `collection('parametres').toutes`). Idempotent : le dernier branchement l'emporte.
  static void brancher(Iterable<Map<String, Object?>> Function() fiches, {DateTime Function()? horloge}) {
    _fiches = fiches;
    _horloge = horloge ?? DateTime.now;
  }

  /// Débranche (test).
  static void debrancher() {
    _fiches = null;
    _horloge = DateTime.now;
  }

  /// La liste EN VIGUEUR aujourd'hui pour [cle] : la version datée qui s'applique, sinon la liste d'attente.
  static List<String> valeurs(String cle) => valeursA(cle, _fiches?.call() ?? const [], _date(_horloge()));

  /// La liste en vigueur à [date] (AAAA-MM-JJ) parmi [fiches] (les versions du registre) ; la liste d'attente si rien n'est lisible.
  static List<String> valeursA(String cle, Iterable<Map<String, Object?>> fiches, String date) {
    final d = definitionDeParametre(cle);
    if (d == null) throw ArgumentError('liste de référence inconnue : $cle');
    final versions = [
      for (final f in fiches)
        if (f['statut'] != 'archive' && f['cle'] == cle) Parametre.fromJson(f)
    ];
    final r = Parametres.resoudre(cle, versions, date, definition: d);
    final lue = decouper(r.ok ? r.valeur!.valeur : null);
    return lue.isNotEmpty ? lue : semence(cle);
  }

  /// Un réglage TEXTE en vigueur aujourd'hui (coordonnées, adresse…) : la version datée qui s'applique, sinon la valeur d'attente de sa définition. Un texte vide ou illisible retombe sur la
  /// valeur d'attente (une coordonnée jamais lue ne doit pas laisser un champ vide à l'écran de l'aide).
  static String texte(String cle) {
    final d = definitionDeParametre(cle);
    if (d == null || d.type != TypeParametre.texte) throw ArgumentError('réglage texte inconnu : $cle');
    final versions = [
      for (final f in _fiches?.call() ?? const <Map<String, Object?>>[])
        if (f['statut'] != 'archive' && f['cle'] == cle) Parametre.fromJson(f)
    ];
    final r = Parametres.resoudre(cle, versions, _date(_horloge()), definition: d);
    final v = r.ok ? r.valeur!.valeur : null;
    final t = v is String ? v.trim() : '';
    return t.isNotEmpty ? t : '${d.defaut}';
  }

  /// La liste d'attente de [cle] : le défaut de sa définition (un seul endroit la dit).
  static List<String> semence(String cle) {
    final d = definitionDeParametre(cle);
    if (d == null) throw ArgumentError('liste de référence inconnue : $cle');
    return decouper(d.defaut);
  }

  // --- LES ÉNUMÉRATIONS STRUCTURELLES : le CODE est dans le code, le LIBELLÉ est un réglage ---------------------------------------------------------------------------------
  // Un code que la logique lit pour décider (mode de paiement, famille de tarif, catégorie de produit…) est un INVARIANT d'algorithme : il vit dans UNE définition nommée du domaine
  // ([EnumCodes]) et nulle part ailleurs. Ce que la clinique peut vouloir changer, c'est le LIBELLÉ que l'écran affiche : il vient d'un réglage `libelles.*` (texte « code=Libellé ; … »),
  // daté, jamais écrasé. Changer un libellé ne change donc JAMAIS une décision. Un code que le réglage ne connaît pas est IGNORÉ (la logique ne sait pas qu'en faire) ; un code que le
  // réglage oublie garde le libellé d'attente ; un réglage vide ou illisible retombe sur les libellés d'attente.

  /// Les libellés EN VIGUEUR aujourd'hui pour les codes de [cle] : code → libellé, dans l'ordre du réglage (les codes oubliés suivent, dans l'ordre d'attente).
  static Map<String, String> correspondance(String cle) => correspondanceA(cle, _fiches?.call() ?? const [], _date(_horloge()));

  /// Les libellés en vigueur à [date] (AAAA-MM-JJ) parmi [fiches].
  static Map<String, String> correspondanceA(String cle, Iterable<Map<String, Object?>> fiches, String date) {
    final d = definitionDeParametre(cle);
    if (d == null) throw ArgumentError('énumération de référence inconnue : $cle');
    final attente = decouperCorrespondance(d.defaut);
    final versions = [
      for (final f in fiches)
        if (f['statut'] != 'archive' && f['cle'] == cle) Parametre.fromJson(f)
    ];
    final r = Parametres.resoudre(cle, versions, date, definition: d);
    final lue = decouperCorrespondance(r.ok ? r.valeur!.valeur : null);
    return {
      for (final e in lue.entries)
        if (attente.containsKey(e.key)) e.key: e.value,
      for (final e in attente.entries)
        if (!lue.containsKey(e.key)) e.key: e.value,
    };
  }

  /// Une ASSOCIATION OUVERTE « clé=valeur ; … » en vigueur aujourd'hui (service → secteur : les clés sont du vocabulaire de clinique, la liste n'est donc pas fermée). Un texte vide ou
  /// illisible retombe sur l'association d'attente.
  static Map<String, String> associations(String cle) {
    final d = definitionDeParametre(cle);
    if (d == null) throw ArgumentError('association de référence inconnue : $cle');
    final versions = [
      for (final f in _fiches?.call() ?? const <Map<String, Object?>>[])
        if (f['statut'] != 'archive' && f['cle'] == cle) Parametre.fromJson(f)
    ];
    final r = Parametres.resoudre(cle, versions, _date(_horloge()), definition: d);
    final lue = decouperCorrespondance(r.ok ? r.valeur!.valeur : null);
    return lue.isNotEmpty ? lue : decouperCorrespondance(d.defaut);
  }

  /// Les libellés d'attente de [cle] (le défaut de sa définition).
  static Map<String, String> correspondanceSemence(String cle) {
    final d = definitionDeParametre(cle);
    if (d == null) throw ArgumentError('énumération de référence inconnue : $cle');
    return decouperCorrespondance(d.defaut);
  }

  /// « a=Un ; b=Deux » → {a: Un, b: Deux} : points-virgules, blancs rognés, une entrée sans « = » ou sans libellé est ignorée, un code répété garde sa première entrée.
  static Map<String, String> decouperCorrespondance(Object? texte) {
    if (texte is! String) return const {};
    final r = <String, String>{};
    for (final x in texte.split(';')) {
      final i = x.indexOf('=');
      if (i <= 0) continue;
      final code = x.substring(0, i).trim(), lib = x.substring(i + 1).trim();
      if (code.isEmpty || lib.isEmpty) continue;
      r.putIfAbsent(code, () => lib);
    }
    return r;
  }

  /// « a; b ; c » → [a, b, c] : points-virgules, blancs rognés, vides et doublons retirés (l'ordre saisi est conservé).
  static List<String> decouper(Object? texte) {
    if (texte is! String) return const [];
    final vus = <String>{};
    return [
      for (final x in texte.split(';'))
        if (x.trim().isNotEmpty && vus.add(x.trim())) x.trim()
    ];
  }

  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// UNE ÉNUMÉRATION STRUCTURELLE : la clé du réglage qui porte les LIBELLÉS d'un jeu FERMÉ de codes que la logique lit. Les [codes] sont ceux de la valeur d'attente de la définition du réglage
/// (la seule liste de codes, jamais recopiée) : le libellé change, le code et donc la décision ne changent pas. `libelle` d'un code inconnu rend le code tel quel (jamais « null » à l'écran).
class EnumCodes {
  const EnumCodes(this.cle);
  final String cle;

  /// Les codes connus du logiciel, dans l'ordre d'attente.
  List<String> get codes => ListesReference.correspondanceSemence(cle).keys.toList();

  /// code → libellé en vigueur, dans l'ordre du réglage.
  Map<String, String> get libelles => ListesReference.correspondance(cle);

  /// Le libellé en vigueur de [code] ; le code lui-même s'il est inconnu.
  String libelle(Object? code) => libelles['$code'] ?? '${code ?? ''}';

  /// (code, libellé) dans l'ordre du réglage : la forme qu'attendent les listes de choix.
  List<(String, String)> get paires => [for (final e in libelles.entries) (e.key, e.value)];

  /// (code, libellé) des seuls [sousEnsemble] de codes, DANS L'ORDRE DEMANDÉ : un écran qui n'offre qu'une partie des codes (ou dans un autre ordre) la dit par ses codes, jamais par une
  /// seconde liste de libellés. Un code inconnu de l'énumération est une faute de programmation.
  List<(String, String)> paresDe(List<String> sousEnsemble) {
    final l = libelles;
    return [
      for (final c in sousEnsemble)
        if (l.containsKey(c)) (c, l[c]!) else throw ArgumentError('code inconnu de $cle : $c')
    ];
  }

  bool contient(Object? code) => codes.contains(code);
}
