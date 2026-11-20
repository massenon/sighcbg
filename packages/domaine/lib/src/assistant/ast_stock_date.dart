/// LE STOCK À UNE DATE PASSÉE (décision de la Direction du 16/11/2026, relecture des questions d'agents) : le magasin ne conserve que l'état d'aujourd'hui ; l'état d'une date
/// passée se RECONSTITUE depuis les mouvements — stock actuel moins l'effet des mouvements POSTÉRIEURS à la date, par magasin (gros, détail) et au total.
///
/// LE GARDE DE FIABILITÉ, qui fait toute la valeur de cette fonction : la reconstitution n'est rendue que si elle tient. Un mouvement sans date lisible, sans quantité positive,
/// de sens inconnu (une régularisation d'inventaire n'écrit que la valeur ABSOLUE de l'écart), un transfert sans magasin, un stock actuel dont gros + détail ne fait pas le total
/// (un mouvement manque quelque part), ou un résultat NÉGATIF (un mouvement antérieur manque) : la réponse est « non calculable », motif nommé — JAMAIS zéro, jamais un chiffre
/// approché. Fonction pure : aucune horloge, aucune écriture.
library;

import '../format/js.dart' show nombreOuZero;
import '../stock/mouvements_stock.dart' show typeMouvement;

/// La reconstitution d'UN article à une date.
class StockALaDate {
  const StockALaDate({required this.produitId, this.total, this.gros, this.detail, this.motifs = const [], this.mouvementsPosterieurs = 0});
  final String produitId;

  /// Le total reconstitué ; `null` : non calculable (voir [motifs]).
  final num? total;

  /// Le stock par magasin ; `null` si la répartition n'est pas reconstituable (mouvement sans magasin, fiche sans répartition), même quand le total l'est.
  final num? gros, detail;

  /// Pourquoi ce n'est pas calculable (vide : fiable).
  final List<String> motifs;
  final int mouvementsPosterieurs;

  bool get fiable => motifs.isEmpty && total != null;
}

String _jour10(Object? v) {
  final t = '${v ?? ''}';
  return t.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(t) ? t.substring(0, 10) : '';
}

num? _quantite(Object? v) {
  final n = v is num ? v : num.tryParse('${v ?? ''}'.trim());
  return n != null && n.isFinite && n > 0 ? n : null;
}

/// Le sens d'un mouvement sur le MAGASIN qu'il porte : +1 entrée, −1 sortie ; `null` : sens inconnu (le mouvement ne se rejoue pas).
int? _sens(Map<String, Object?> m) {
  final sensDit = m['sens'];
  if (sensDit == 'entree') return 1;
  if (sensDit == 'sortie') return -1;
  final type = '${m['type'] ?? ''}';
  if (type == 'transfert') {
    final st = m['stockType'];
    if (st == 'gros') return -1;
    if (st == 'detail' || st == 'labo') return 1;
    return null;
  }
  final t = typeMouvement(type);
  if (t == null || t.sens == 0) return null; // une régularisation d'inventaire sans sens écrit : la valeur absolue ne dit pas de quel côté
  return t.sens;
}

/// Reconstitue le stock de chaque produit de [produits] à la FIN de la journée [date] (AAAA-MM-JJ) : les mouvements datés APRÈS [date] sont défaits.
Map<String, StockALaDate> reconstituerStockA(Iterable<Map<String, Object?>> produits, Iterable<Map<String, Object?>> mouvements, String date) {
  final parProduit = <String, List<Map<String, Object?>>>{};
  final sansProduit = <Map<String, Object?>>[];
  for (final m in mouvements) {
    final id = m['produitId'];
    if (id == null || '$id'.isEmpty) {
      sansProduit.add(m);
      continue;
    }
    (parProduit['$id'] ??= []).add(m);
  }
  final out = <String, StockALaDate>{};
  for (final p in produits) {
    final id = '${p['id']}';
    final motifs = <String>[];
    final total0 = p['stock'] == null ? null : nombreOuZero(p['stock']);
    final g0 = p['stockGros'] == null ? null : nombreOuZero(p['stockGros']);
    final d0 = p['stockDetail'] == null ? null : nombreOuZero(p['stockDetail']);
    if (total0 == null) motifs.add('le stock actuel n’est pas renseigné');
    var repartition = g0 != null && d0 != null;
    if (repartition && total0 != null && g0 + d0 != total0) {
      motifs.add('le stock actuel est incohérent (gros ${_n(g0)} + détail ${_n(d0)} ≠ total ${_n(total0)}) : un mouvement manque au registre');
    }
    var total = total0 ?? 0, gros = g0 ?? 0, detail = d0 ?? 0;
    var n = 0;
    for (final m in parProduit[id] ?? const <Map<String, Object?>>[]) {
      final j = _jour10(m['date']);
      if (j.isEmpty) {
        motifs.add('un mouvement (${m['reference'] ?? m['id'] ?? 'sans référence'}) n’a pas de date lisible');
        continue;
      }
      if (j.compareTo(date) <= 0) continue;
      n++;
      final q = _quantite(m['quantite']);
      final s = _sens(m);
      if (q == null) {
        motifs.add('le mouvement ${m['reference'] ?? m['id'] ?? ''} du $j n’a pas de quantité lisible');
        continue;
      }
      if (s == null) {
        motifs.add('le mouvement ${m['reference'] ?? m['id'] ?? ''} du $j (${m['type'] ?? 'type inconnu'}) ne dit pas son sens');
        continue;
      }
      final st = m['stockType'];
      // Un transfert déplace du gros vers le détail : il ne change pas le total.
      if (m['type'] != 'transfert') total -= s * q;
      if (st == 'gros') {
        gros -= s * q;
      } else if (st == 'detail' || st == 'labo') {
        detail -= s * q;
      } else {
        repartition = false; // le total se rejoue, la répartition par magasin non
      }
    }
    if (motifs.isEmpty && (total < 0 || (repartition && (gros < 0 || detail < 0)))) {
      motifs.add('la reconstitution donnerait un stock négatif : un mouvement antérieur manque au registre');
    }
    out[id] = StockALaDate(
      produitId: id,
      total: motifs.isEmpty ? total : null,
      gros: motifs.isEmpty && repartition ? gros : null,
      detail: motifs.isEmpty && repartition ? detail : null,
      motifs: motifs,
      mouvementsPosterieurs: n,
    );
  }
  return out;
}

String _n(num v) => v == v.truncate() ? '${v.toInt()}' : '$v';
