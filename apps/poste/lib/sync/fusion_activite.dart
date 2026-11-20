import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart' show etatDispensation, ligneMarqueeDelivree;

import '../donnees/magasin.dart';

/// LES RÈGLES DE FUSION DE L'ACTIVITÉ QUI NE SE LAISSE PAS ÉCRASER (limites levées le 03/11/2026).
///
/// « Le dernier geste gagne » corromprait une facture (un encaissement perdu), un stock (une sortie perdue), une numérotation (deux pièces au même numéro).
/// Chaque famille de données a donc SA règle, toutes pures et testées sans réseau :
///
/// * **compteurs** (stock des produits, quantité restante des lots) : jamais remplacés, jamais écrasés : chaque poste publie ses VARIATIONS, et chaque poste
///   les additionne. Deux sorties simultanées de deux postes se retranchent toutes les deux (commutatif). Le seul risque, un stock devenu négatif par deux
///   sorties hors ligne du dernier exemplaire, est DÉTECTÉ et dit (RG-03), jamais corrigé en silence.
/// * **factures** : un règlement ne se perd pas. Une ligne réglée l'emporte sur une ligne due ; le montant payé ne recule jamais ; le statut avance, il ne
///   recule pas. Une ligne réglée par DEUX postes à la fois est signalée (`encaissementEnDoublon`).
/// * **numéros** (facture, avoir, pièce comptable, dossier) : jamais renumérotés (une pièce émise ne se réécrit jamais, RG-01), deux pièces au même numéro sont
///   MARQUÉES et comptées ; la Direction tranche.
/// * **lits** : une admission active par lit ; deux admissions actives sur le même lit sont marquées `litEnConflit`.
/// * **ordonnances** (délivrance ligne par ligne, 16/11/2026) : une ligne délivrée ne redevient jamais à délivrer. Les marques de délivrance se fusionnent LIGNE
///   PAR LIGNE ([fusionnerOrdonnance]) ; une même ligne délivrée par DEUX postes est signalée (`delivranceEnDoublon`).

/// L'ARCHIVAGE L'EMPORTE (RG-14, D6 du 09/11/2026 : la mise en production archive le jeu de démonstration d'un poste ou de la mère). La fusion à trois voies garde
/// ce que l'agent a changé ICI : un poste qui avait modifié le statut d'une fiche pendant que la mère l'archivait aurait donc ÉCRASÉ l'archivage, et la fiche
/// de démonstration serait revenue en activité. Quand l'une des deux versions ([local] ou [recu]) est archivée, [fusion] l'est aussi : `statut: 'archive'`, ancien
/// statut gardé pour la restauration, marques (date, auteur, motif) reprises de la version archivée. Une restauration, elle, est un changement de statut
/// ordinaire : si la fiche était DÉJÀ archivée à la dernière synchronisation ([base]), l'archivage n'est plus une nouveauté et la fusion à trois voies décide
/// seule, donc une restauration (de l'un ou de l'autre poste) se propage. Modifie [fusion] en place ; rend vrai si l'archivage a été imposé.
bool fusionnerArchivage(Map<String, Object?> fusion, Fiche local, Map<String, Object?> recu, {Map<String, Object?>? base}) {
  if (base != null && base['statut'] == 'archive') return false;
  final localArchive = local['statut'] == 'archive', recuArchive = recu['statut'] == 'archive';
  if (!localArchive && !recuArchive) return false;
  if (fusion['statut'] == 'archive' && fusion.containsKey('statutAvantArchivage')) return false;
  final source = recuArchive ? recu : local;
  final autre = recuArchive ? local : recu;
  // Le statut d'avant : celui que la version archivée avait gardé, sinon le statut de l'AUTRE version (la fiche active), sinon celui de la fusion.
  final avant = source['statutAvantArchivage'] ?? (autre['statut'] != 'archive' ? autre['statut'] : null) ?? (fusion['statut'] != 'archive' ? fusion['statut'] : null);
  fusion['statut'] = 'archive';
  if (avant != null) fusion['statutAvantArchivage'] = avant;
  for (final k in const ['_archiveLe', '_archivePar', '_motifArchivage']) {
    final v = source[k] ?? autre[k];
    if (v != null) fusion[k] = v;
  }
  return true;
}

/// Les champs d'une fiche qui sont des COMPTEURS (additionnés, jamais remplacés).
const Map<String, Set<String>> champsCompteurs = {
  'produits': {'stockGros', 'stockDetail', 'stock'},
  'lots': {'quantiteRestante'},
  // Les règlements d'une facture s'additionnent : deux guichets qui encaissent deux lignes en même temps ne s'effacent pas.
  'factures': {'montantPaye', 'reliquat'},
};

/// Le statut de paiement qui découle des compteurs d'une facture : soldée quand plus rien n'est dû, partielle dès qu'un règlement existe. Il ne RECULE jamais
/// (une facture soldée ne redevient pas partielle parce qu'une version plus ancienne arrive). `null` : rien à changer.
String? statutPaiementDepuis(Fiche f) {
  if (!f.containsKey('montantPaye') || !f.containsKey('reliquat')) return null;
  final paye = _n(f['montantPaye']), reste = _n(f['reliquat']);
  final voulu = reste <= 0 && paye > 0 ? 'soldee' : (paye > 0 ? 'partielle' : null);
  if (voulu == null) return null;
  final actuel = _ordreStatutPaiement['${f['statutPaiement']}'] ?? -1;
  return _ordreStatutPaiement[voulu]! > actuel ? voulu : null;
}

/// Le champ qui porte le NUMÉRO d'une pièce, par collection, et le nom du marqueur posé en cas de doublon.
const Map<String, ({String champ, String marqueur})> champsNumero = {
  'patients': (champ: 'code', marqueur: 'codeEnDoublon'),
  'factures': (champ: 'numero', marqueur: 'numeroEnDoublon'),
  'avoirs': (champ: 'reference', marqueur: 'numeroEnDoublon'),
  'ecritures': (champ: 'numero', marqueur: 'numeroEnDoublon'),
  // Un versement et sa contre-passation prennent chacun un numéro VRS dans la série du poste : deux postes hors ligne peuvent en donner le même, jamais corrigé en silence.
  'versements': (champ: 'numero', marqueur: 'numeroEnDoublon'),
  // PLANNING (17/11/2026) : la référence humaine d'un congé ou d'un ordre de mission (`CG-…`, `OM-…`) se prend dans la série du poste ; deux postes hors ligne peuvent en donner la même : jamais corrigée en silence.
  'conges': (champ: 'reference', marqueur: 'numeroEnDoublon'),
  'missions': (champ: 'reference', marqueur: 'numeroEnDoublon'),
};

String _j(Object? o) => jsonEncode(o);

const _ordreStatutPaiement = {'impayee': 0, 'partielle': 1, 'soldee': 2};

num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// Fusion d'une FACTURE : [fusion] est la fusion champ à champ déjà faite (ce que l'agent a changé ici est gardé, le reste suit le journal) ; cette fonction
/// la corrige pour qu'aucun règlement ne se perde. [local] et [recu] sont les deux versions face à face.
Map<String, Object?> fusionnerFacture(Map<String, Object?> fusion, Fiche local, Map<String, Object?> recu) {
  final r = {...fusion};
  // Les lignes : par identifiant de ligne ; la ligne RÉGLÉE l'emporte (le règlement le plus ancien est conservé, il est celui qui a libéré la prestation).
  final a = [for (final l in (local['lignes'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  final b = [for (final l in (recu['lignes'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  if (a.isNotEmpty || b.isNotEmpty) {
    final parId = <String, Map<String, Object?>>{for (final l in a) '${l['id']}': l};
    final doublons = <String>[];
    final ordre = [for (final l in a) '${l['id']}'];
    for (final l in b) {
      final id = '${l['id']}';
      final ici = parId[id];
      if (ici == null) {
        parId[id] = l;
        ordre.add(id);
        continue;
      }
      final iciPaye = ici['statutPaiement'] == 'paye', laPaye = l['statutPaiement'] == 'paye';
      if (iciPaye && laPaye && '${ici['payePar']}${ici['payeLe']}' != '${l['payePar']}${l['payeLe']}') {
        doublons.add(id);
        // Les deux ont encaissé : on garde le plus ancien et on SIGNALE.
        final dIci = DateTime.tryParse('${ici['payeLe'] ?? ''}'), dLa = DateTime.tryParse('${l['payeLe'] ?? ''}');
        if (dIci != null && dLa != null && dLa.isBefore(dIci)) parId[id] = l;
      } else if (!iciPaye && laPaye) {
        parId[id] = l;
      }
    }
    r['lignes'] = [for (final id in ordre) parId[id]!];
    if (doublons.isNotEmpty) r['encaissementEnDoublon'] = doublons;
  }
  // Le montant payé et le reliquat sont des COMPTEURS (voir `champsCompteurs`) : ils s'additionnent par leurs variations ; le statut en est DÉDUIT ensuite
  // (`statutPaiementDepuis`), il ne se choisit pas entre deux versions.
  // Le dernier règlement : le plus récent.
  final dl = local['dernierReglement'], dr = recu['dernierReglement'];
  if (dl is Map && dr is Map) {
    final tl = DateTime.tryParse('${dl['date']}'), tr = DateTime.tryParse('${dr['date']}');
    r['dernierReglement'] = (tl != null && tr != null && tr.isAfter(tl)) ? dr : dl;
  }
  return r;
}

/// Les groupes de fiches qui portent le même NUMÉRO alors qu'elles ne sont pas la même pièce. [identite] : ce qui distingue deux pièces (`pieceId` pour deux
/// lignes d'une même écriture comptable, l'identité de synchronisation sinon).
List<List<Fiche>> numerosEnDoublon(Iterable<Fiche> fiches, String champ, String Function(Fiche) identite) {
  final par = <String, Map<String, List<Fiche>>>{};
  for (final f in fiches) {
    final num = '${f[champ] ?? ''}';
    if (num.isEmpty || CollectionMagasin.estArchivee(f)) continue;
    ((par[num] ??= {})[identite(f)] ??= []).add(f);
  }
  return [
    for (final g in par.values)
      if (g.length > 1) [for (final l in g.values) ...l]
  ];
}

/// Les groupes d'admissions ACTIVES qui occupent le même lit (un lit ne porte qu'une admission active).
List<List<Fiche>> litsEnConflit(Iterable<Fiche> admissions) {
  final par = <String, List<Fiche>>{};
  for (final a in admissions) {
    if (a['statut'] != 'en_cours') continue;
    final lit = '${a['lit'] ?? ''}'.trim();
    if (lit.isEmpty) continue;
    (par[lit] ??= []).add(a);
  }
  return [
    for (final g in par.values)
      if (g.length > 1) g
  ];
}

const _champsDelivrance = ['delivreLe', 'delivrePar', 'delivreMouvement'];
const _champsValorisation = ['prix', 'total', 'prixAValoriser', 'valorisation'];
const _ordreDispensation = {'sans_objet': -1, 'en_attente': 0, 'partielle': 1, 'servie': 2};

/// Fusion d'une ORDONNANCE (délivrance ligne par ligne, Direction du 16/11/2026, E3305). La fusion champ à champ traite `medicaments` comme UN champ : quand deux
/// postes délivrent chacun une ligne différente hors ligne, la liste de l'un écrasait celle de l'autre, la ligne servie là-bas redevenait « délivrable » ici et
/// pouvait ressortir du stock. Ici les lignes se fusionnent PAR RANG : une ligne marquée délivrée l'emporte sur une ligne non marquée (ses marques sont reprises),
/// une ligne valorisée l'emporte sur une ligne « prix à valoriser » ; une ligne délivrée par les DEUX postes (marques différentes) garde la plus ancienne et est
/// SIGNALÉE (`delivranceEnDoublon`, rangs des lignes) — deux sorties de stock ont eu lieu, et les deux variations de stock restent comptées (elles sont réelles) :
/// la Direction et la pharmacie tranchent (retour de produit ou régularisation), rien n'est corrigé en silence. L'état de dispensation est RECALCULÉ depuis les
/// lignes fusionnées et ne recule jamais.
Map<String, Object?> fusionnerOrdonnance(Map<String, Object?> fusion, Fiche local, Map<String, Object?> recu) {
  final r = {...fusion};
  final a = [for (final l in (local['medicaments'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  final b = [for (final l in (recu['medicaments'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  if (a.isEmpty && b.isEmpty) return r;
  final f = [for (final l in (fusion['medicaments'] as List? ?? const [])) (l as Map).cast<String, Object?>()];
  final n = [a.length, b.length, f.length].reduce((x, y) => x > y ? x : y);
  final doublons = <int>[];
  final lignes = <Map<String, Object?>>[];
  for (var i = 0; i < n; i++) {
    final la = i < a.length ? a[i] : null, lb = i < b.length ? b[i] : null;
    final l = <String, Object?>{...(i < f.length ? f[i] : (la ?? lb ?? const {}))};
    // Valorisation : une ligne qui porte son prix l'emporte sur une ligne qui l'attend.
    bool valorisee(Map<String, Object?>? x) => x != null && x['prixAValoriser'] != true && x['total'] != null;
    if (l['prixAValoriser'] == true && l['total'] == null) {
      final v = valorisee(la) ? la : (valorisee(lb) ? lb : null);
      if (v != null) {
        for (final k in _champsValorisation) {
          if (v.containsKey(k)) {
            l[k] = v[k];
          } else {
            l.remove(k);
          }
        }
      }
    }
    final da = la != null && ligneMarqueeDelivree(la), db = lb != null && ligneMarqueeDelivree(lb);
    Map<String, Object?>? marque;
    if (da && db) {
      if ('${la['delivrePar']}${la['delivreLe']}' != '${lb['delivrePar']}${lb['delivreLe']}') {
        doublons.add(i);
        final ta = DateTime.tryParse('${la['delivreLe']}'), tb = DateTime.tryParse('${lb['delivreLe']}');
        marque = (ta != null && tb != null && tb.isBefore(ta)) ? lb : la;
      } else {
        marque = la;
      }
    } else if (da) {
      marque = la;
    } else if (db) {
      marque = lb;
    }
    if (marque != null) {
      for (final k in _champsDelivrance) {
        if (marque.containsKey(k)) l[k] = marque[k];
      }
    }
    lignes.add(l);
  }
  r['medicaments'] = lignes;
  final calcule = etatDispensation(r);
  final rangs = [local['statutDispensation'], recu['statutDispensation'], calcule]
      .map((x) => _ordreDispensation['$x'] ?? -2)
      .toList();
  // Un état « servie » écrit par l'ANCIEN moteur (sans marque de ligne) reste servi ; sinon l'état suit les lignes.
  final legacyServie = (local['statutDispensation'] == 'servie' && !a.any(ligneMarqueeDelivree)) ||
      (recu['statutDispensation'] == 'servie' && !b.any(ligneMarqueeDelivree));
  r['statutDispensation'] = legacyServie && rangs.reduce((x, y) => x > y ? x : y) == 2 ? 'servie' : calcule;
  if (r['statutDispensation'] == 'servie') {
    r['dispenseLe'] ??= local['dispenseLe'] ?? recu['dispenseLe'];
    r['dispensePar'] ??= local['dispensePar'] ?? recu['dispensePar'];
  }
  if (doublons.isNotEmpty) r['delivranceEnDoublon'] = doublons;
  return r;
}
