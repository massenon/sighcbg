// L'OUTILLAGE COMMUN DU SOUS-LOT « STOCK, ACHATS, CAISSE ET COMPTABILITÉ » : le déroulé chronologique des événements (une file triée par instant : les numéros de
// pièce, de bon et de mouvement suivent les jours) et les écritures de collection. Rien d'autre : toute règle métier est dans `packages/domaine`.
//
// Les acteurs : le rôle « stock » n'a pas de titulaire (Q33), c'est donc un comptable qui tient le magasin ; l'autre comptable tient la caisse. Les arbitrages
// (besoins, commandes : RG-04) sont rendus par la Direction, jamais par un nom écrit en dur dans un moteur du domaine.
import 'package:sigh_poste/donnees/magasin.dart';

import 'contexte.dart';

/// Le comptable qui tient le magasin (le rôle « stock » n'a pas de titulaire) et signe les mouvements, les inventaires, les procès-verbaux.
const String comptableStock = 'SANOUSSI Adamon';

/// Le comptable qui tient la caisse (comme dans le sous-lot clinique).
const String comptableCaisse = 'ZIME Nadège';

/// Les deux membres de la Direction : l'un ou l'autre arbitre un besoin ou valide une commande (RG-04).
const String direction1 = 'BAGUIDI Rafiou';
const String direction2 = 'SOKOU Peace';

/// Mention des fiches fictives du sous-lot.
const String sourceDemo = 'Jeu de démonstration Baguidi : donnée fictive, à remplacer par la clinique';

String pad(int n, int l) => n.toString().padLeft(l, '0');

/// Un instant UTC (le jeu ne dépend jamais du fuseau du poste qui le génère).
DateTime instant(DateTime jour, int h, [int mn = 0]) => DateTime.utc(jour.year, jour.month, jour.day, h, mn);

/// `aaaa-mm-jj` d'une date écrite telle quelle.
DateTime jourIso(String iso) => DateTime.utc(int.parse(iso.substring(0, 4)), int.parse(iso.substring(5, 7)), int.parse(iso.substring(8, 10)));

String iso8601(DateTime t) => t.toUtc().toIso8601String();
String jourDe(DateTime t) => Contexte.date(t);

/// Les montants d'un jeu sont des entiers de francs : un `double` entier s'écrit sans décimale (le poste lit `2000`, pas `2000.0`).
Object? entier(Object? v) {
  if (v is double && v == v.truncateToDouble()) return v.toInt();
  return v;
}

Object? normaliser(Object? v) {
  if (v is Map) return {for (final e in v.entries) '${e.key}': normaliser(e.value)};
  if (v is List) return [for (final x in v) normaliser(x)];
  return entier(v);
}

Fiche normalisee(Fiche f) => (normaliser(f) as Map).cast<String, Object?>();

class _Evt {
  _Evt(this.quand, this.rang, this.geste);
  final DateTime quand;
  final int rang;
  final void Function() geste;
}

/// L'atelier du sous-lot : le tirage de l'étape, l'horloge de la file et les écritures.
class Atelier {
  Atelier(this.ctx) : t = ctx.tirageDe('stock_finance');

  final Contexte ctx;
  final Tirage t;

  /// L'instant « courant » de la file : mis à jour avant chaque geste.
  DateTime horloge = DateTime.utc(2026, 8, 1, 8);

  final Map<String, int> _compteurs = {};
  final List<_Evt> _file = [];
  int _rang = 0;

  /// Planifie un geste à un instant : inséré à sa place dans la file (stable à égalité).
  void planifier(DateTime quand, void Function() geste) {
    final e = _Evt(quand, _rang++, geste);
    var i = _file.length;
    while (i > 0 && _file[i - 1].quand.isAfter(quand)) {
      i--;
    }
    _file.insert(i, e);
  }

  /// Déroule la file du plus ancien au plus récent. Un geste peut planifier à son tour.
  void derouler() {
    while (_file.isNotEmpty) {
      final e = _file.removeAt(0);
      horloge = e.quand;
      e.geste();
    }
  }

  /// Un identifiant `PREFIXE` + rang sur [largeur] chiffres (un identifiant ne se réutilise jamais).
  String nouvelId(String collection, String prefixe, {int largeur = 5}) {
    final n = (_compteurs[collection] ?? ctx.collection(collection).toutes.length) + 1;
    _compteurs[collection] = n;
    return '$prefixe${pad(n, largeur)}';
  }

  /// Ajoute une fiche À LA FIN d'une collection (ordre déterministe) et rend la fiche telle qu'écrite (sa copie vivante).
  Fiche ajouter(String collection, Fiche fiche, String prefixe, {int largeur = 5}) {
    final f = {...fiche};
    f['id'] ??= nouvelId(collection, prefixe, largeur: largeur);
    f['statut'] ??= 'actif';
    ctx.ajouter(collection, normalisee(f));
    return ctx.collection(collection).parId(f['id'])!;
  }

  Fiche? parId(String collection, Object? id) => ctx.collection(collection).parId(id);

  void maj(String collection, Object? id, Fiche patch) {
    ctx.collection(collection).mettreAJour(id, normalisee(patch), journaliser: false);
  }

  List<Fiche> fiches(String collection) => ctx.fiches(collection);
  List<Fiche> toutes(String collection) => ctx.collection(collection).toutes;
}
