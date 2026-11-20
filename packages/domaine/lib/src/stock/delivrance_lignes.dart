/// DÉLIVRANCE LIGNE PAR LIGNE (Direction de Baguidi, 16/11/2026 — `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md`, §1).
///
/// Jusqu'ici une ordonnance n'était délivrable qu'une fois SOLDÉE : un règlement partiel, ou une seule ligne « prix à valoriser » (qui ne s'encaisse pas tant que
/// l'article n'a pas de prix d'achat), bloquait toute la dispensation, médicaments déjà payés compris. La règle devient :
///
/// * chaque ligne de médicament RÉGLÉE à la caisse se délivre — le règlement se lit sur la LIGNE PAYABLE de la facture (encaissement ligne par ligne, la ligne
///   payable porte le `produitId`), jamais sur l'état global de la pièce ;
/// * une ligne non réglée, ou au « prix à valoriser », reste EN ATTENTE : affichée, NOMMÉE (« non réglée à la caisse » / « prix à valoriser »), jamais délivrable ;
/// * RG-03 inchangé : le justificatif est le numéro d'ordonnance, le stock ne devient jamais négatif (le refus NOMME chaque article), le CUMUL des lignes d'un même
///   produit est contrôlé ; RG-05 : le lot FEFO (le premier à périmer, hors périmé et hors épuisé) est porté par le mouvement ;
/// * une délivrance partielle laisse le reste délivrable plus tard, SANS double sortie : chaque ligne délivrée porte sa marque (`delivreLe`, `delivrePar`,
///   `delivreMouvement`), et une ligne marquée ne se délivre plus jamais (idempotence PAR LIGNE) ;
/// * l'ordonnance porte un état clair, DÉDUIT de ses lignes : `en_attente` (non délivrée), `partielle` (partiellement délivrée), `servie` (délivrée).
///
/// Les deux pharmacies (interne vers la salle de soins, externe vers le patient) et la file de la dispensation passent par CE moteur : une seule règle.
///
/// Pièces ANTÉRIEURES au modèle par lignes (facture sans ligne payable, ordonnance sans facture liée) : la ligne est réglée si la pièce est soldée — c'est la doctrine
/// de l'encaissement pour ces pièces. Une ordonnance déjà « servie » par l'ancien moteur, sans aucune marque de ligne, est lue entièrement délivrée.
///
/// Comme `delivrance.dart` : les fiches arrivent EN ARGUMENT, le moteur RENVOIE ce qu'il faut écrire ; il n'écrit rien lui-même.
library;

import '../caisse/valorisation.dart' show ligneAValoriser;
import '../format/format_fr.dart';
import '../format/js.dart';
import 'delivrance.dart';
import '../numerotation/numerotation.dart';

/// Le motif d'attente d'une ligne non réglée (affiché tel quel).
const String attenteNonReglee = 'non réglée à la caisse';

/// Le motif d'attente d'une ligne dont l'article n'a pas encore de prix d'achat (affiché tel quel).
const String attentePrixAValoriser = 'prix à valoriser';

/// Les quatre états d'une ligne de médicament devant la pharmacie.
enum EtatLigneDelivrance { delivree, delivrable, nonReglee, prixAValoriser }

/// Une ligne de médicament d'une ordonnance, mise en regard de la caisse.
class LigneOrdonnanceDelivrance {
  const LigneOrdonnanceDelivrance(
      {required this.index, required this.ligne, required this.ligneFacture, required this.etat});

  /// Le rang de la ligne dans `ordonnance.medicaments`.
  final int index;
  final Map<String, Object?> ligne;

  /// La ligne payable de la facture qui la couvre (null : pièce antérieure au modèle par lignes).
  final Map<String, Object?>? ligneFacture;
  final EtatLigneDelivrance etat;

  bool get delivree => etat == EtatLigneDelivrance.delivree;
  bool get delivrable => etat == EtatLigneDelivrance.delivrable;
  bool get enAttente => etat == EtatLigneDelivrance.nonReglee || etat == EtatLigneDelivrance.prixAValoriser;

  /// « non réglée à la caisse » / « prix à valoriser » ; null hors attente.
  String? get motif => switch (etat) {
        EtatLigneDelivrance.nonReglee => attenteNonReglee,
        EtatLigneDelivrance.prixAValoriser => attentePrixAValoriser,
        _ => null,
      };

  /// Le libellé d'état affiché par les écrans.
  String get libelle => switch (etat) {
        EtatLigneDelivrance.delivree => 'Délivrée',
        EtatLigneDelivrance.delivrable => 'Délivrable',
        _ => 'En attente — $motif',
      };

  Object? get produitId => ligne['produitId'];
  Object? get designation => ligne['produit'];
  Object? get quantite => ligne['quantite'];
}

bool _vrai(Object? v) => v != null && v != '' && v != false && v != 0;
double _n(Object? v) => nombreOuZero(v);
num _dispo(Map<String, Object?> p) => (p['stockDetail'] != null ? _n(p['stockDetail']) : _n(p['stock']));
String _js(num v) => v == v.truncate() && v.abs() < 1e15 ? '${v.truncate()}' : '$v';

List<Map<String, Object?>> _meds(Map<String, Object?> o) =>
    [for (final x in (o['medicaments'] as List? ?? const [])) (x as Map).cast<String, Object?>()];

/// La ligne porte-t-elle la marque d'une délivrance ?
bool ligneMarqueeDelivree(Map<String, Object?> l) => _vrai(l['delivreLe']);

/// L'ordonnance a-t-elle été servie par l'ANCIEN moteur (servie entière, sans marque de ligne) ?
bool _servieSansMarques(Map<String, Object?> o) => o['statutDispensation'] == 'servie' && !_meds(o).any(ligneMarqueeDelivree);

/// La facture de l'ordonnance : celle qu'elle désigne (`factureId`), sinon la pièce active qui la désigne (`ordonnanceId`).
Map<String, Object?>? factureDeLOrdonnance(Map<String, Object?> ordonnance, Iterable<Map<String, Object?>> factures) {
  Map<String, Object?>? parOrd;
  for (final f in factures) {
    if (f['statut'] == 'archive') continue;
    if (ordonnance['factureId'] != null && f['id'] == ordonnance['factureId']) return f;
    if (parOrd == null && f['ordonnanceId'] != null && f['ordonnanceId'] == ordonnance['id']) parOrd = f;
  }
  return parOrd;
}

/// Les lignes payables `medicament` de la facture, rapprochées des lignes de l'ordonnance : par RANG (le moteur de prescription les construit dans l'ordre des
/// médicaments), le `produitId` vérifié ; à défaut, la première ligne libre du même produit.
List<Map<String, Object?>?> _rapprocher(List<Map<String, Object?>> meds, Map<String, Object?>? facture) {
  final fl = [
    for (final x in (facture?['lignes'] as List? ?? const []))
      if (x is Map && x['categorie'] == 'medicament') x.cast<String, Object?>()
  ];
  final prises = <int>{};
  final out = <Map<String, Object?>?>[];
  for (var i = 0; i < meds.length; i++) {
    final pid = meds[i]['produitId'];
    var k = -1;
    if (i < fl.length && !prises.contains(i) && fl[i]['produitId'] == pid) {
      k = i;
    } else {
      for (var j = 0; j < fl.length; j++) {
        if (!prises.contains(j) && fl[j]['produitId'] == pid) {
          k = j;
          break;
        }
      }
    }
    if (k >= 0) prises.add(k);
    out.add(k >= 0 ? fl[k] : null);
  }
  return out;
}

/// L'état de chaque ligne de médicament de [ordonnance] devant la pharmacie. [facture] : la pièce de prescription (voir [factureDeLOrdonnance]).
List<LigneOrdonnanceDelivrance> lignesDelivrance(Map<String, Object?> ordonnance, Map<String, Object?>? facture) {
  final meds = _meds(ordonnance);
  final legacyServie = _servieSansMarques(ordonnance);
  final soldee = ordonnance['statutPaiement'] == 'soldee' || facture?['statutPaiement'] == 'soldee';
  final rapproches = _rapprocher(meds, facture);
  return [
    for (var i = 0; i < meds.length; i++)
      () {
        final l = meds[i];
        final lf = rapproches[i];
        EtatLigneDelivrance etat;
        if (ligneMarqueeDelivree(l) || legacyServie) {
          etat = EtatLigneDelivrance.delivree;
        } else if (lf != null) {
          etat = lf['statutPaiement'] == 'paye'
              ? EtatLigneDelivrance.delivrable
              : (ligneAValoriser(lf) ? EtatLigneDelivrance.prixAValoriser : EtatLigneDelivrance.nonReglee);
        } else if (l['prixAValoriser'] == true && l['total'] == null) {
          etat = EtatLigneDelivrance.prixAValoriser;
        } else {
          // Pièce antérieure au modèle par lignes (ou ligne payable introuvable) : la pièce soldée règle la ligne.
          etat = soldee ? EtatLigneDelivrance.delivrable : EtatLigneDelivrance.nonReglee;
        }
        return LigneOrdonnanceDelivrance(index: i, ligne: l, ligneFacture: lf, etat: etat);
      }(),
  ];
}

/// L'état de dispensation DÉDUIT des lignes : `sans_objet`, `en_attente` (non délivrée), `partielle` (partiellement délivrée), `servie` (délivrée).
String etatDispensation(Map<String, Object?> ordonnance) {
  final meds = _meds(ordonnance);
  if (meds.isEmpty) return ordonnance['statutDispensation'] == 'servie' ? 'servie' : 'sans_objet';
  if (_servieSansMarques(ordonnance)) return 'servie';
  final n = meds.where(ligneMarqueeDelivree).length;
  if (n == 0) return 'en_attente';
  return n == meds.length ? 'servie' : 'partielle';
}

/// Le libellé d'un état de dispensation.
String libelleDispensation(Object? code) => switch ('$code') {
      'en_attente' => 'Non délivrée',
      'partielle' => 'Partiellement délivrée',
      'servie' => 'Délivrée',
      'sans_objet' => 'Sans médicament',
      _ => '—',
    };

/// Les lignes DÉLIVRÉES de [ordonnance] que couvrent les lignes payables [ligneFactureIds] de [facture] : ce qu'une annulation d'encaissement ne peut plus défaire
/// (le produit est sorti du stock et remis).
List<LigneOrdonnanceDelivrance> lignesDelivreesCouvertesPar(
    Map<String, Object?> ordonnance, Map<String, Object?>? facture, Iterable<String> ligneFactureIds) {
  final ids = ligneFactureIds.toSet();
  return [
    for (final l in lignesDelivrance(ordonnance, facture))
      if (l.delivree && ligneMarqueeDelivree(l.ligne) && l.ligneFacture != null && ids.contains('${l.ligneFacture!['id']}')) l
  ];
}

/// Le motif du refus d'annuler un encaissement dont une ligne libérée a DÉJÀ été délivrée, ou null. La voie prudente du projet : une pièce dont l'effet a eu lieu ne
/// se défait pas en silence — la correction passe par un AVOIR (`m8-facture-avoir`) et le retour du produit par un mouvement d'entrée justifié (`m6-mouvements`).
String? refusAnnulationEncaissement(
    Map<String, Object?>? ordonnance, Map<String, Object?>? facture, Iterable<String> ligneFactureIds) {
  if (ordonnance == null) return null;
  final d = lignesDelivreesCouvertesPar(ordonnance, facture, ligneFactureIds);
  if (d.isEmpty) return null;
  final noms = d.map((l) => '« ${l.designation} »${_vrai(l.ligne['delivreMouvement']) ? ' (mouvement ${l.ligne['delivreMouvement']})' : ''}').join(', ');
  return 'Annulation refusée : ${d.length == 1 ? 'la ligne' : 'les lignes'} $noms ${d.length == 1 ? 'a' : 'ont'} déjà été délivrée${d.length == 1 ? '' : 's'} '
      'au titre de l’ordonnance ${ordonnance['numero']} — le produit est sorti du stock (RG-03). L’encaissement ne s’annule plus : la correction passe par un avoir '
      '(« Factures d’avoir »), et le retour du produit par un mouvement d’entrée justifié (« Mouvements de stock »).';
}

/// La couverture de stock des lignes [aServir] (dans leur ordre) : RG-03, le CUMUL des lignes d'un même produit est contrôlé.
List<LigneStock> couvertureStock(List<LigneOrdonnanceDelivrance> aServir, Iterable<Map<String, Object?>> produits) {
  final liste = produits.toList();
  final prises = <Object?, num>{};
  return [
    for (final x in aServir)
      () {
        final prod = liste.where((p) => p['id'] == x.produitId).firstOrNull;
        final total = prod == null ? 0 : _dispo(prod);
        final dispo = total - (prises[x.produitId] ?? 0);
        if (prod != null) prises[x.produitId] = (prises[x.produitId] ?? 0) + _n(x.quantite);
        return LigneStock(ligne: x.ligne, produit: prod, disponible: dispo, suffisant: prod != null && dispo >= _n(x.quantite));
      }(),
  ];
}

/// Le refus nommé d'une ligne non couverte (même phrase que la pharmacie).
String motifStockInsuffisant(LigneStock m) =>
    'Délivrance refusée — stock insuffisant sur « ${m.ligne['produit']} » : ${nombre(m.disponible)} en rayon pour ${nombre(m.ligne['quantite'])} demandé(s).';

/// Le lot FEFO (RG-05) d'un produit : le premier à périmer, hors périmé (statut ou date passée) et hors épuisé ; null sans lot.
Map<String, Object?>? lotFefo(Object? produitId, Iterable<Map<String, Object?>> lots, String jour) {
  final candidats = [
    for (final x in lots)
      if (x['produitId'] == produitId &&
          x['statut'] != 'perime' &&
          x['statut'] != 'archive' &&
          _n(x['quantiteRestante']) > 0 &&
          !(_vrai(x['datePeremption']) && '${x['datePeremption']}'.compareTo(jour) < 0))
        x
  ]..sort((a, b) => '${a['datePeremption'] ?? '9999'}'.compareTo('${b['datePeremption'] ?? '9999'}'));
  return candidats.isEmpty ? null : candidats.first;
}

/// Ce qu'écrit une délivrance ligne par ligne.
class DelivranceLignes {
  const DelivranceLignes({
    required this.deja,
    required this.etat,
    this.ordonnancePatch = const {},
    this.produits = const [],
    this.mouvements = const [],
    this.dispensation,
    this.tachesFermees = const [],
    this.tachesMisesAJour = const [],
    this.tachesCreees = const [],
    this.alertes = const [],
    this.journal = const {},
    this.lignesDelivrees = const [],
    this.enAttente = const [],
  });

  /// Toutes les lignes demandées étaient DÉJÀ délivrées : rien n'est refait (idempotence par ligne).
  final bool deja;

  /// L'état de dispensation de l'ordonnance APRÈS le geste.
  final String etat;

  /// `{medicaments, statutDispensation, [dispenseLe, dispensePar]}`.
  final Map<String, Object?> ordonnancePatch;
  final List<({Object? id, Map<String, Object?> patch})> produits;
  final List<Map<String, Object?>> mouvements;

  /// La fiche du registre `dispensations` (une par geste), sans identifiant.
  final Map<String, Object?>? dispensation;
  final List<({Object? id, Map<String, Object?> patch})> tachesFermees;

  /// La tâche de dispensation de l'ordonnance, quand il reste des lignes : `en_attente` s'il en reste une délivrable, `bloque` sinon (elle attend la caisse).
  final List<({Object? id, Map<String, Object?> patch})> tachesMisesAJour;
  final List<Map<String, Object?>> tachesCreees;
  final List<AlerteStock> alertes;
  final Map<String, Object?> journal;

  /// Les rangs des lignes délivrées par CE geste.
  final List<int> lignesDelivrees;

  /// Les lignes restées en attente (nommées), pour le message.
  final List<LigneOrdonnanceDelivrance> enAttente;
}

/// Délivre les lignes RÉGLÉES de [ordonnance]. [lignes] : les rangs à servir (null : toutes les lignes délivrables) ; [voie] : `orale` ou `parenterale` pour ne servir
/// que la pharmacie concernée (null : toutes). Une ligne déjà délivrée est IGNORÉE (jamais deux sorties) ; une ligne demandée en attente ou non couverte par le stock
/// lève [RefusDelivrance] en la nommant — rien n'est écrit. [lots] : pour le lot FEFO ; [dispensationsExistantes] : pour la série `DISP-NNNNN` ;
/// [mouvementsExistants] : pour la série `M000000`.
DelivranceLignes delivrerLignes({
  required Map<String, Object?>? ordonnance,
  required Map<String, Object?>? facture,
  required Iterable<Map<String, Object?>> produits,
  required Iterable<Map<String, Object?>> taches,
  required Iterable<Map<String, Object?>> mouvementsExistants,
  Iterable<Map<String, Object?>> lots = const [],
  Iterable<Map<String, Object?>> dispensationsExistantes = const [],
  List<int>? lignes,
  String? voie,
  required String methode,
  required String utilisateur,
  required String instant,
}) {
  if (ordonnance == null) throw const RefusDelivrance('Ordonnance introuvable.');
  final liste = produits.toList();
  Map<String, Object?>? produitDe(Object? id) => liste.where((p) => p['id'] == id).firstOrNull;
  bool dansVoie(LigneOrdonnanceDelivrance l) => voie == null || voieDe(l.ligne, produitDe(l.produitId)) == voie;

  final etats = lignesDelivrance(ordonnance, facture);
  final visees = [
    for (final l in etats)
      if (dansVoie(l) && (lignes == null || lignes.contains(l.index))) l
  ];
  final aServir = visees.where((l) => !l.delivree).toList();
  final enAttente = [for (final l in etats) if (dansVoie(l) && l.enAttente) l];
  if (visees.isNotEmpty && aServir.isEmpty) {
    return DelivranceLignes(deja: true, etat: etatDispensation(ordonnance), enAttente: enAttente);
  }
  if (lignes != null) {
    // Une ligne DEMANDÉE qui attend la caisse ou son prix est refusée nommément : on ne la sert jamais « au passage ».
    final bloquees = aServir.where((l) => l.enAttente).toList();
    if (bloquees.isNotEmpty) {
      throw RefusDelivrance('Délivrance en attente — ${bloquees.map((l) => '« ${l.designation} » : ${l.motif}').join(' ; ')} '
          '(ordonnance ${ordonnance['numero']}). Seule une ligne réglée à la caisse se délivre.');
    }
  }
  final servies = aServir.where((l) => l.delivrable).toList();
  if (servies.isEmpty) {
    if (enAttente.isEmpty) {
      throw RefusDelivrance('Aucune ligne à délivrer sur l’ordonnance ${ordonnance['numero']}.');
    }
    throw RefusDelivrance('Aucune ligne délivrable sur l’ordonnance ${ordonnance['numero']} — '
        '${enAttente.map((l) => '« ${l.designation} » : ${l.motif}').join(' ; ')}. Seule une ligne réglée à la caisse se délivre.');
  }

  final etatStock = couvertureStock(servies, liste);
  final manquants = etatStock.where((e) => !e.suffisant).toList();
  if (manquants.isNotEmpty) {
    // RG-03 — jamais de stock négatif : on refuse, et on dit lesquels.
    throw RefusDelivrance(manquants.map(motifStockInsuffisant).join(' ; '), manquants: manquants);
  }

  final jour = instant.length >= 10 ? instant.substring(0, 10) : instant;
  final vivants = <Object?, Map<String, Object?>>{for (final p in liste) p['id']: {...p}};
  final patchs = <({Object? id, Map<String, Object?> patch})>[];
  final mouvements = <Map<String, Object?>>[];
  final refs = [...mouvementsExistants];
  final medsApres = [for (final m in _meds(ordonnance)) {...m}];
  final lignesRegistre = <Map<String, Object?>>[];
  num montant = 0;
  for (final x in servies) {
    final prod = vivants[x.produitId]!;
    final q = _n(x.quantite);
    final reste = _dispo(prod) - q;
    final patch = <String, Object?>{
      'stockDetail': prod['stockDetail'] != null ? reste : prod['stockDetail'],
      'stock': (_n(prod['stock']) - q) < 0 ? 0 : _n(prod['stock']) - q,
    };
    prod.addAll(patch);
    patchs.add((id: prod['id'], patch: patch));
    final val = valoriserSortie(prod, q, methode);
    final circuit = voieDe(x.ligne, prod) == 'parenterale' ? 'delivrance_interne' : 'delivrance_externe';
    final lot = lotFefo(prod['id'], lots, jour);
    final mv = <String, Object?>{
      'reference': numeroSuivant('stock.mouvements', date: instant, existants: refs),
      'date': instant,
      'produitId': prod['id'],
      'produit': prod['designation'],
      'type': 'sortie',
      'typeLabel': 'Sortie',
      'sens': 'sortie',
      'circuit': circuit,
      'destination': circuit == 'delivrance_interne' ? 'Salle de soins' : 'Patient',
      'quantite': x.quantite,
      'stockType': 'detail',
      // RG-03 : le justificatif est le numéro d'ordonnance.
      'justificatif': 'Ordonnance ${ordonnance['numero']}',
      'ordonnanceId': ordonnance['id'],
      'ligneOrdonnance': x.index,
      if (x.ligneFacture != null) 'ligneFactureId': x.ligneFacture!['id'],
      // RG-05 : le lot qui sort en premier.
      if (lot != null) 'lot': lot['numeroLot'],
      if (lot != null) 'peremption': lot['datePeremption'],
      'valorisation': val.methode,
      'valeur': val.valeur,
      'valeurPrixVente': val.valeurPrixVente,
      'valeurCump': val.valeurCump,
      'utilisateur': utilisateur,
    };
    mouvements.add(mv);
    refs.add(mv);
    medsApres[x.index] = {
      ...medsApres[x.index],
      'delivreLe': instant,
      'delivrePar': utilisateur,
      'delivreMouvement': mv['reference'],
    };
    // RG-02 : le prix d'achat (celui de l'ordonnance, sinon celui de la fiche).
    final pu = x.ligne['prix'] is num ? x.ligne['prix'] as num : _n(prod['prixAchat']);
    montant += pu * q;
    lignesRegistre.add({
      'produitId': prod['id'],
      'produit': prod['designation'],
      'quantite': x.quantite,
      'unite': x.ligne['unite'] ?? prod['unite'] ?? '',
      'prix': pu,
      'ligneOrdonnance': x.index,
      if (lot != null) 'lot': lot['numeroLot'],
    });
  }

  final ordApres = {...ordonnance, 'medicaments': medsApres};
  final etat = etatDispensation(ordApres);
  final restantes = [for (final l in lignesDelivrance(ordApres, facture)) if (!l.delivree) l];
  final attenteApres = restantes.where((l) => l.enAttente).toList();
  final avant = ordonnance['statutDispensation'] ?? 'en_attente';

  final fermees = <({Object? id, Map<String, Object?> patch})>[];
  final majs = <({Object? id, Map<String, Object?> patch})>[];
  for (final t in taches) {
    if (t['ordonnanceId'] != ordonnance['id'] || t['type'] != 'dispensation') continue;
    if (etat == 'servie') {
      fermees.add((id: t['id'], patch: <String, Object?>{'statut': 'fait', 'faitLe': instant, 'faitPar': utilisateur}));
    } else {
      final delivrees = medsApres.where(ligneMarqueeDelivree).length;
      final resteDelivrable = restantes.any((l) => l.delivrable);
      majs.add((
        id: t['id'],
        patch: <String, Object?>{
          // Plus rien de délivrable : la tâche attend de nouveau la caisse (l'encaissement de la ligne suivante la rouvre).
          'statut': resteDelivrable ? 'en_attente' : 'bloque',
          'detail': '$delivrees/${medsApres.length} ligne(s) délivrée(s)'
              '${attenteApres.isEmpty ? '' : ' — en attente : ${attenteApres.map((l) => '${l.designation} (${l.motif})').join(', ')}'}',
        }
      ));
    }
  }

  final alertes = alerterStock([for (final x in servies) x.produitId], vivants, taches, '${ordonnance['numero']}', instant);

  return DelivranceLignes(
    deja: false,
    etat: etat,
    ordonnancePatch: {
      'medicaments': medsApres,
      'statutDispensation': etat,
      if (etat == 'servie') 'dispenseLe': instant,
      if (etat == 'servie') 'dispensePar': utilisateur,
    },
    produits: patchs,
    mouvements: mouvements,
    dispensation: {
      'reference': numeroSuivant('stock.dispensations', date: instant, existants: dispensationsExistantes),
      'date': instant,
      'ordonnanceId': ordonnance['id'],
      'ordonnanceNumero': ordonnance['numero'],
      'patientId': ordonnance['patientId'],
      'patient': ordonnance['patient'],
      'patientCode': ordonnance['patientCode'],
      'lignes': lignesRegistre,
      'montant': arrondiJs(montant.toDouble()),
      'dispensePar': utilisateur,
      'etatOrdonnance': etat,
    },
    tachesFermees: fermees,
    tachesMisesAJour: [...majs, ...alertes.miseAJour],
    tachesCreees: alertes.creees,
    alertes: alertes.alertes,
    lignesDelivrees: [for (final x in servies) x.index],
    enAttente: attenteApres,
    journal: {
      'action': etat == 'servie' ? 'Dispensation' : 'Dispensation partielle',
      'module': 'M6',
      'entite': 'ordonnance',
      'reference': ordonnance['numero'],
      'avant': {'statutDispensation': avant},
      'apres': {
        'statutDispensation': etat,
        'lignes': mouvements.length,
        'produits': [for (final x in servies) '${x.designation} × ${_js(_n(x.quantite))}'],
        if (attenteApres.isNotEmpty) 'enAttente': [for (final l in attenteApres) '${l.designation} (${l.motif})'],
      },
    },
  );
}
