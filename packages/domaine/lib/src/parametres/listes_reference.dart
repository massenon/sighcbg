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
