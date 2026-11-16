import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import 'magasin.dart';
import 'normalisation_mecef.dart';
import 'reglages_clinique_poste.dart';
import 'tarifs_poste.dart';

/// Refus NOMMÉ d'une opération de caisse : un code, un motif lisible (jamais un échec muet).
class RefusCaisse implements Exception {
  const RefusCaisse(this.code, this.motif, {this.lignes = const []});
  final String code;
  final String motif;

  /// Les lignes en attente de prix que le refus NOMME (`{id, designation, code, motif}`) : la facture en attente de prix (`FACTURE_EN_ATTENTE_DE_PRIX`) ou la ligne seule.
  final List<Map<String, Object?>> lignes;
  @override
  String toString() => motif;
}

class ResultatCaisse {
  const ResultatCaisse({
    required this.facture,
    required this.deja,
    required this.lignesReglees,
    required this.montantRegle,
    required this.restantDu,
    required this.debloquees,
    required this.demandesLiberees,
    required this.ecritures,
    required this.annuler,
    this.normalisation,
    this.lignesRefusees = const [],
    this.lignesValorisees = const [],
    String? Function()? refusAnnulationLu,
  }) : _refusAnnulation = refusAnnulationLu;
  final Fiche facture;
  final bool deja;
  final List<String> lignesReglees;
  final num montantRegle;
  final num restantDu;

  /// Types de tâches d'aval ouvertes par le règlement (`dispensation`, `prelevement`…).
  final List<String> debloquees;

  /// Références des examens (analyses, imagerie) libérés.
  final List<String> demandesLiberees;
  final List<Fiche> ecritures;

  /// Restitue TOUT ce que l'encaissement a écrit (facture, tâches, demandes, écritures) — une annulation visible, jamais partielle. Lève [RefusCaisse]
  /// (`ANNULATION_LIGNE_DELIVREE`) sans rien défaire si une ligne qu'il avait libérée a déjà été délivrée (voir [refusAnnulation]).
  final VoidCallback annuler;

  final String? Function()? _refusAnnulation;

  /// Le motif pour lequel l'annulation serait refusée À CET INSTANT (une ligne de médicament libérée par ce versement a été délivrée depuis), ou null.
  String? refusAnnulation() => _refusAnnulation?.call();

  /// La normalisation de la vente SOLDÉE (null tant que la pièce n'est pas soldée, ou qu'il n'y a rien à normaliser). Son refus ne défait pas
  /// l'encaissement : l'argent est reçu, la pièce devient `refusee` en le disant.
  final ResultatNormalisation? normalisation;

  /// Les lignes visées NON encaissées faute de prix (« prix à valoriser » / « prix assuré à définir ») quand le réglage « encaisser le reste » est OUVERT : `{id, designation, code,
  /// motif}` ; les autres sont encaissées. Réglage fermé (défaut), une ligne en attente suspend la pièce entière : refus [RefusCaisse] `FACTURE_EN_ATTENTE_DE_PRIX`.
  final List<Map<String, Object?>> lignesRefusees;

  /// Les lignes « prix à valoriser » que ce geste a VALORISÉES (prix d'achat désormais fixé) avant de les encaisser.
  final List<String> lignesValorisees;
}

/// `PR.encaisser` côté poste : le cœur arithmétique est celui du domaine (vecteurs de la maquette) ; ici l'ORCHESTRATION — le laboratoire et
/// l'imagerie ne reçoivent que les prestations RÉGLÉES, les tâches d'aval s'ouvrent au solde, le comptable est informé par une ÉCRITURE
/// (brouillon, RG-10) posée à chaque versement.
ResultatCaisse encaisserFacture(
  Magasin m,
  String factureId, {
  List<String>? lignes,
  num? montant,
  String? mode,
  required DateTime maintenant,
}) {
  // La facture de la caisse est celle d'un PATIENT (décision de la Direction de Baguidi du 16/11/2026, E3770) : ni acheteur ni AIB ne se saisissent ni ne
  // s'appliquent ; l'ancienne fenêtre « Facture normalisée » (IFU, nom de l'acheteur, AIB) a disparu des trois portes d'encaissement.
  var fac = m.collection('factures').parId(factureId);
  if (fac == null)
    throw const RefusCaisse('FACTURE_INTROUVABLE', 'Facture introuvable.');
  final aujourdhui = d.iso(maintenant);
  final annulations = <VoidCallback>[];
  // LIGNE SANS PRIX (Direction de Baguidi, 16/11/2026, §7) : le réglage de clinique « encaisser le reste », lu au jour du geste. Non (défaut) : RIEN de la facture ne s'encaisse
  // tant qu'une ligne attend son prix ; Oui : l'encaissement ligne par ligne de la v21.
  final resteOuvert = ReglagesClinique.encaisserResteSansPrix(m, maintenant);
  // « PRIX À VALORISER » (Direction, 16/11/2026) : une ligne dont l'article a DÉSORMAIS un prix EN VIGUEUR À LA DATE DE LA PIÈCE se valorise ICI, en place (RG-02,
  // `tarPrixValorisation`) ; la pièce n'est ni soldée ni normalisée tant qu'elle attend, aucune valeur émise n'est réécrite. Réglage fermé, TOUTES les lignes en attente de la
  // facture sont tentées (une seule restée sans prix suspend la pièce entière) ; réglage ouvert, seules les lignes visées. Une ligne encore sans prix reste « prix à valoriser » :
  // le moteur refuse en le nommant.
  final valorisees = <String>[];
  final attente = [
    for (final l in d.lignesAValoriserDe(fac))
      if (!resteOuvert || lignes == null || lignes.isEmpty || lignes.contains('${l['id']}')) l
  ];
  if (attente.isNotEmpty) {
    final h = TarifsPoste.lire(m);
    final jourPiece = d.tarJourDe(fac['date'], aujourdhui);
    final ecrituresAvant = m.collection('ecritures').actives;
    final complement = <Fiche>[];
    var courante = fac;
    for (final l in attente) {
      final prod = m.collection('produits').parId(l['produitId']);
      // AJ (16/11/2026) : la cause dit quel prix valorise la ligne (prix ASSURÉ d'un acte, ou prix d'achat d'un article) ; jamais le prix non assuré.
      final prix = d.tarPrixValorisationLigne(h, l, prod, jourPiece, aujourdhui: aujourdhui);
      if (prix == null) continue;
      final r = d.valoriserLigne(courante, '${l['id']}', prix,
          utilisateur: m.utilisateur, maintenant: maintenant.toIso8601String(), aujourdhui: aujourdhui, ecritures: [...ecrituresAvant, ...complement]);
      if (!r.ok) continue;
      courante = r.facture!;
      complement.addAll(r.ecritures);
      valorisees.add('${l['id']}');
      m.journaliser(d.ligneAssureADefinir(l) ? 'Valorisation d’une ligne au prix assuré' : 'Valorisation d’une ligne au prix d’achat', 'M8', 'facture', '${fac['numero']}', {'ligne': l['designation'], 'montant': 'prix à valoriser'},
          {'ligne': l['designation'], 'prixUnitaire': prix.prixUnitaire, 'version': prix.version, 'dateEffet': prix.dateEffet, 'regle': prix.regle});
    }
    if (valorisees.isNotEmpty) {
      annulations.add(m.collection('factures').mettreAJour(factureId, {
        for (final k in ['lignes', 'montantHT', 'montantTTC', 'montantBrut', 'partAssurance', 'partPersonnel', 'partPatient', 'reliquat', 'lignesAValoriser'])
          if (courante.containsKey(k)) k: courante[k],
      }));
      for (final e in complement) {
        final ins = m.collection('ecritures').inserer(e, prefixe: 'ECR');
        annulations.add(ins.annuler);
      }
      // L'ordonnance (pièce de prescription, non fiscale) reçoit le même prix sur ses lignes en attente : la pharmacie délivre et imprime le bon de sortie au prix retenu,
      // jamais à 0. Seules les lignes encore « prix à valoriser » du même article sont complétées ; rien d'autre ne bouge.
      final ordonnances = m.collection('ordonnances');
      final ord = fac['ordonnanceId'] == null ? null : ordonnances.parId(fac['ordonnanceId']);
      if (ord != null) {
        final prixParProduit = <String, Map<String, Object?>>{
          for (final l in (courante['lignes'] as List).cast<Map>())
            if (valorisees.contains('${l['id']}') && l['produitId'] != null) '${l['produitId']}': l.cast<String, Object?>()
        };
        var change = false;
        final meds = [
          for (final x in (ord['medicaments'] as List? ?? const []).cast<Map>())
            () {
              final l = x.cast<String, Object?>();
              final v = prixParProduit['${l['produitId']}'];
              if (v == null || l['prixAValoriser'] != true || l['total'] != null) return l;
              change = true;
              final pu = v['prixUnitaire'] as num;
              return {...l, 'prix': pu, 'total': pu * d.nombreOuZero(l['quantite']), 'prixAValoriser': false, 'valorisation': v['valorisation']};
            }()
        ];
        if (change) {
          final mMed = meds.fold<num>(0, (a, l) => a + d.nombreOuZero(l['total']));
          final reste = meds.where((l) => l['prixAValoriser'] == true && l['total'] == null).length;
          annulations.add(ordonnances.mettreAJour(ord['id'], {
            'medicaments': meds,
            'montantMedicaments': mMed,
            'montant': mMed + d.nombreOuZero(ord['montantAnalyses']) + d.nombreOuZero(ord['montantActes']) + d.nombreOuZero(ord['montantImagerie']),
            'lignesAValoriser': reste,
          }));
        }
      }
      fac = m.collection('factures').parId(factureId)!;
    }
  }
  void defaire() {
    for (final u in annulations.reversed) {
      u();
    }
  }

  // L'état du module MECEF, lu dans les fermetures en vigueur et PASSÉ au moteur (P0-5) : fermé, le versement ne pose ni statutMecef ni baseMecef,
  // et une pièce émise pendant que MECeF était ouvert garde les siens.
  final mecefActif = d
      .fermeturesEnVigueur(m.collection('modulesActifs').toutes)
      .mecefEnService;
  final r = d.encaisser(
    fac,
    lignes: lignes,
    montant: montant,
    mode: mode,
    aujourdhui: aujourdhui,
    maintenant: maintenant.toIso8601String(),
    utilisateur: m.utilisateur,
    mecefActif: mecefActif,
    ecritures: m.collection('ecritures').actives,
    encaisserResteSansPrix: resteOuvert,
  );
  // E2 (corrigé le 31/10/2026) : un versement au-delà du dû d'une pièce sans lignes est REFUSÉ en nommant le défaut ; rien n'est écrit.
  if (r.refus != null) {
    // Une valorisation faite pour ce versement se défait avec lui : rien n'est écrit sur un refus (la ligne se revalorisera au geste suivant, au même prix).
    defaire();
    throw RefusCaisse(r.refusCode ?? 'VERSEMENT_REFUSE', r.refus!, lignes: r.lignesRefusees);
  }
  if (r.deja) {
    return ResultatCaisse(
        facture: fac,
        deja: true,
        lignesReglees: const [],
        montantRegle: 0,
        restantDu: 0,
        debloquees: const [],
        demandesLiberees: const [],
        ecritures: const [],
        annuler: () {});
  }
  final f = r.facture;
  annulations.add(m.collection('factures').mettreAJour(factureId, {
    for (final k in [
      'lignes',
      'montantPaye',
      'reliquat',
      'lignesAValoriser',
      'modePaiement',
      'statutPaiement',
      'statutMecef',
      'baseMecef',
      'dernierReglement'
    ])
      // MECeF fermé, le moteur ne pose pas statutMecef / baseMecef : une clé absente ne s'écrit pas (un null effacerait le champ d'une pièce
      // émise pendant que MECeF était ouvert).
      if (f.containsKey(k)) k: f[k],
  }));

  final liberees = <String>[];
  final iso = maintenant.toIso8601String();
  final reglees = [
    for (final l in (f['lignes'] as List).cast<Map>())
      if (r.lignesReglees.contains('${l['id']}')) l.cast<String, Object?>()
  ];

  // Le laboratoire : SEULES les analyses réglées passent.
  final analyses = m.collection('demandesAnalyses');
  for (final l in reglees) {
    if (l['categorie'] != 'analyse' || l['demandeId'] == null) continue;
    final dem = analyses.parId(l['demandeId']);
    if (dem == null) continue;
    annulations.add(analyses.mettreAJour(dem['id'], {
      'bloqueParPaiement': false,
      'statutPaiement': 'soldee',
      'etatAnalyse':
          dem['etatAnalyse'] == 'valide' ? 'valide' : 'attente_prelevement',
      'regleLe': iso,
    }));
    liberees.add('${dem['reference'] ?? dem['id']}');
  }
  // L'imagerie suit la même règle : la séance réglée passe.
  final imagerie = m.collection('demandesImagerie');
  for (final l in reglees) {
    if (l['categorie'] != 'imagerie' || l['demandeImagerieId'] == null)
      continue;
    final di = imagerie.parId(l['demandeImagerieId']);
    if (di == null) continue;
    annulations.add(imagerie.mettreAJour(di['id'], {
      'bloqueParPaiement': false,
      'statut': di['statut'] == 'demandee' ? 'payee' : di['statut'],
      'regleLe': iso
    }));
    liberees.add('${di['reference'] ?? di['id']}');
  }

  final debloquees = <String>[];
  // DÉLIVRANCE LIGNE PAR LIGNE (Direction de Baguidi, 16/11/2026) : la pharmacie n'attend plus le SOLDE. Dès qu'une ligne de MÉDICAMENT est réglée, la tâche de
  // dispensation de l'ordonnance s'ouvre : la pharmacie délivre les lignes réglées, les autres restent en attente, nommées (`delivrerLignes`).
  if (f['statutPaiement'] != 'soldee' && f['ordonnanceId'] != null && reglees.any((l) => l['categorie'] == 'medicament')) {
    final taches = m.collection('taches');
    for (final t in taches.actives.where((t) =>
        t['type'] == 'dispensation' && t['statut'] == 'bloque' && (t['factureId'] == factureId || t['ordonnanceId'] == f['ordonnanceId']))) {
      annulations.add(taches.mettreAJour(t['id'], {'statut': 'en_attente'}));
      if (!debloquees.contains('dispensation')) debloquees.add('dispensation');
    }
  }
  if (f['statutPaiement'] == 'soldee') {
    final taches = m.collection('taches');
    for (final t in taches.actives.where((t) => t['factureId'] == factureId)) {
      if (t['type'] == 'encaissement') {
        annulations.add(taches.mettreAJour(t['id'],
            {'statut': 'fait', 'faitLe': iso, 'faitPar': m.utilisateur}));
      } else if (t['statut'] == 'bloque') {
        annulations.add(taches.mettreAJour(t['id'], {'statut': 'en_attente'}));
        if (!debloquees.contains('${t['type']}')) debloquees.add('${t['type']}');
      }
    }
    // Pièces antérieures au modèle par lignes : ce qui resterait bloqué faute de ligne est libéré au solde.
    for (final dem
        in analyses.actives.where((x) => x['bloqueParPaiement'] == true)) {
      if (dem['factureId'] == factureId ||
          (f['ordonnanceId'] != null &&
              dem['ordonnanceId'] == f['ordonnanceId'])) {
        annulations.add(analyses.mettreAJour(dem['id'], {
          'bloqueParPaiement': false,
          'statutPaiement': 'soldee',
          'etatAnalyse':
              dem['etatAnalyse'] == 'valide' ? 'valide' : 'attente_prelevement',
          'regleLe': iso,
        }));
        liberees.add('${dem['reference'] ?? dem['id']}');
      }
    }
    for (final di in imagerie.actives.where(
        (x) => x['bloqueParPaiement'] == true && x['factureId'] == factureId)) {
      annulations.add(imagerie.mettreAJour(di['id'], {
        'bloqueParPaiement': false,
        'statut': di['statut'] == 'demandee' ? 'payee' : di['statut'],
        'regleLe': iso
      }));
      liberees.add('${di['reference'] ?? di['id']}');
    }
    if (f['ordonnanceId'] != null)
      annulations.add(m
          .collection('ordonnances')
          .mettreAJour(f['ordonnanceId'], {'statutPaiement': 'soldee'}));
  }

  // Le comptable est informé par une écriture (brouillon), à CHAQUE versement.
  final ecr = <Fiche>[];
  for (final e in r.ecritures) {
    final ins = m.collection('ecritures').inserer(e, prefixe: 'ECR');
    ecr.add(ins.fiche);
    annulations.add(ins.annuler);
  }
  m.journaliser('Encaissement', 'M8', 'facture', '${f['numero']}', {
    'statutPaiement': fac['statutPaiement']
  }, {
    'statutPaiement': f['statutPaiement'],
    'montantPaye': f['montantPaye'],
    'verse': r.montantRegle,
    'lignes': r.lignesReglees.length,
    'restantDu': r.restantDu,
    if (r.lignesRefusees.isNotEmpty) 'lignesAValoriser': [for (final x in r.lignesRefusees) x['designation']],
  });

  // TOUTE VENTE SOLDÉE EST NORMALISÉE (Direction, 07/11/2026) ; un règlement partiel attend le solde, et une pièce à la charge de l'assureur seul
  // (rien encaissé) n'a rien à normaliser. Le refus de la normalisation ne défait pas l'encaissement.
  ResultatNormalisation? normalisation;
  final apres = m.collection('factures').parId(factureId)!;
  if (apres['statutPaiement'] == 'soldee' &&
      n0(apres['montantPaye']) > 0) {
    normalisation = normaliserVente(m, factureId,
        maintenant: maintenant);
    annulations.add(normalisation.annuler);
  }

  final lignesLiberees = [...r.lignesReglees];
  String? refusAnnulation() {
    final fa = m.collection('factures').parId(factureId);
    final ordId = fa?['ordonnanceId'] ?? f['ordonnanceId'];
    return d.refusAnnulationEncaissement(
        ordId == null ? null : m.collection('ordonnances').parId(ordId), fa, lignesLiberees);
  }

  return ResultatCaisse(
    facture: m.collection('factures').parId(factureId)!,
    normalisation: normalisation,
    deja: false,
    lignesReglees: r.lignesReglees,
    montantRegle: r.montantRegle ?? 0,
    restantDu: r.restantDu ?? 0,
    debloquees: debloquees,
    demandesLiberees: liberees,
    ecritures: ecr,
    lignesRefusees: r.lignesRefusees,
    lignesValorisees: valorisees,
    // L'annulation d'un encaissement dont une ligne libérée a DÉJÀ été délivrée est REFUSÉE, nommée (E3304) : le produit est sorti du stock et remis ; défaire
    // la caisse le laisserait sorti sans pièce réglée. La voie prudente du projet : l'avoir pour la caisse, un mouvement d'entrée justifié pour le retour.
    annuler: () {
      final motif = refusAnnulation();
      if (motif != null) throw RefusCaisse('ANNULATION_LIGNE_DELIVREE', motif);
      defaire();
    },
    refusAnnulationLu: refusAnnulation,
  );
}

num n0(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
