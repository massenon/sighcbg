// LE MAGASIN, LES ACHATS ET LES VENTES DE PHARMACIE (sous-lot stock) : un DÉROULÉ CHRONOLOGIQUE du 01/08 au 07/11/2026. Chaque geste appelle le moteur de
// `packages/domaine` qui le porte au poste (réception, transfert, inventaire, perte, besoin, commande, procès-verbal, émission de facture) ; ce fichier ne
// décide que du CALENDRIER et des QUANTITÉS, jamais d'une règle.
//
// L'ÉTAT DU STOCK EST UNE CONSÉQUENCE, JAMAIS UNE DONNÉE : le stock initial entre au 01/08 par des mouvements d'entrée (« reprise du stock initial »), et le
// stock de chaque produit à la fin est la somme signée de ses mouvements (sondé). Un lot est un registre à part : le stock d'un produit est la somme de ses lots,
// les sorties consomment les lots en FEFO (RG-05, le premier à périmer d'abord, jamais un lot périmé), et chaque mouvement de sortie dit quel lot il a vidé.
//
// RG-03 tient par construction : une sortie n'est jamais plus grande que le stock concerné (le moteur refuse, ou le calendrier ne la propose pas), et chaque
// sortie porte son justificatif (numéro de facture, de bon de besoins, de constat, d'inventaire).
//
// Seuils d'alerte : fixés EN FIN de déroulé, pour que le jeu montre exactement huit produits sous leur seuil et aucun en rupture. Ce sont des valeurs
// d'attente (`seuilAValider`), pas des seuils confirmés par la clinique.
import 'package:sigh_domaine/sigh_domaine.dart' as d;
import 'package:sigh_poste/donnees/magasin.dart';

import 'contexte.dart';
import 'finance_caisse.dart';
import 'finance_compta.dart';
import 'stock_base.dart';
import 'stock_catalogue.dart';

num _n(Object? v) => d.nombreOuZero(v);

// --- les référentiels propres au magasin -----------------------------------------------------------------------------------------------------------

/// Les cinq fournisseurs FICTIFS : noms génériques inventés, aucun nom de société réelle, aucun téléphone, IFU, compte bancaire ni agrément.
/// (code, nom, type, délai de livraison en jours, habilité).
const List<(String, String, String, int, bool)> _fournisseurs = [
  ('GPB', 'Grossiste Pharma Borgou', 'Grossiste pharmaceutique', 5, true),
  ('CAP', 'Centrale d’achat de Parakou', 'Centrale d’achat', 7, true),
  ('REA', 'Comptoir des Réactifs du Nord', 'Réactifs & consommables labo', 10, false),
  ('MMN', 'Matériel Médical du Nord', 'Matériel médical', 14, false),
  ('FEB', 'Fournitures et Entretien du Borgou', 'Fournitures & entretien', 3, false),
];

/// Le plan de rangement : (code, zone, température).
const List<(String, String, String)> _emplacements = [
  ('Rayon A, casier 1', 'Rayonnage sec', 'Ambiante'),
  ('Rayon A, casier 2', 'Rayonnage sec', 'Ambiante'),
  ('Rayon A, casier 3', 'Rayonnage sec', 'Ambiante'),
  ('Rayon A, casier 4', 'Rayonnage sec', 'Ambiante'),
  ('Rayon B, casier 1', 'Rayonnage sec', 'Ambiante'),
  ('Rayon B, casier 2', 'Rayonnage sec', 'Ambiante'),
  ('Rayon B, casier 3', 'Rayonnage sec', 'Ambiante'),
  ('Rayon B, casier 4', 'Rayonnage sec', 'Ambiante'),
  ('Rayon C, casier 1', 'Rayonnage sec', 'Ambiante'),
  ('Rayon C, casier 2', 'Rayonnage sec', 'Ambiante'),
  ('Rayon D, casier 1', 'Rayonnage sec', 'Ambiante'),
  ('Rayon D, casier 2', 'Rayonnage sec', 'Ambiante'),
  ('Chariot d’urgence', 'Salle de soins', 'Ambiante'),
  ('Armoire sécurisée 1', 'Armoire sécurisée', 'Sous clé, ambiante'),
  ('Réfrigérateur 1', 'Chaîne du froid', '2 à 8 °C'),
];

/// Un besoin : (date, service, demandeur, motif, famille(s) des lignes, nombre de lignes, issue, quantités accordées différentes, arbitre, date d'arbitrage,
/// date de service). Les besoins se lisent dans l'ordre de leur date : leur numéro suit.
typedef _PlanBesoin = ({
  String date,
  String service,
  String demandeur,
  String motif,
  List<String> familles,
  int lignes,
  String issue,
  bool differente,
  String? arbitre,
  String? arbitrage,
  String? service_,
  String? motifRejet,
});

const List<_PlanBesoin> _besoins = [
  (date: '2026-08-06', service: 'Laboratoire', demandeur: 'IDOHOU Abraham', motif: 'Dotation de service', familles: ['reactif', 'conso_labo'], lignes: 4, issue: 'distribue', differente: true, arbitre: direction1, arbitrage: '2026-08-07', service_: '2026-08-13', motifRejet: null),
  (date: '2026-08-20', service: 'Hospitalisation', demandeur: 'AKONDE Octave', motif: 'Réapprovisionnement mensuel', familles: ['medicament', 'conso_medical'], lignes: 5, issue: 'distribue', differente: true, arbitre: direction2, arbitrage: '2026-08-21', service_: '2026-08-28', motifRejet: null),
  (date: '2026-09-03', service: 'Maternité', demandeur: 'IDOHOU Abraham', motif: 'Dotation de service', familles: ['medicament', 'conso_medical'], lignes: 4, issue: 'distribue', differente: true, arbitre: direction1, arbitrage: '2026-09-04', service_: '2026-09-10', motifRejet: null),
  (date: '2026-09-17', service: 'Accueil', demandeur: 'ZIME Nadège', motif: 'Rupture constatée', familles: ['fourniture'], lignes: 3, issue: 'distribue', differente: false, arbitre: direction2, arbitrage: '2026-09-18', service_: '2026-09-24', motifRejet: null),
  (date: '2026-10-01', service: 'Entretien', demandeur: 'MABOUDOU Nawal', motif: 'Réapprovisionnement mensuel', familles: ['entretien'], lignes: 4, issue: 'distribue', differente: false, arbitre: direction1, arbitrage: '2026-10-02', service_: '2026-10-09', motifRejet: null),
  (date: '2026-10-14', service: 'Bloc opératoire', demandeur: 'IDOHOU Abraham', motif: 'Besoin exceptionnel', familles: ['conso_medical'], lignes: 4, issue: 'accorde', differente: true, arbitre: direction2, arbitrage: '2026-10-16', service_: null, motifRejet: null),
  (date: '2026-10-20', service: 'Accueil', demandeur: 'ZIME Nadège', motif: 'Dotation de service', familles: ['fourniture'], lignes: 3, issue: 'rejete', differente: false, arbitre: direction2, arbitrage: '2026-10-22', service_: null, motifRejet: 'Quantités demandées sans rapport avec la consommation du trimestre : redéposer une demande chiffrée sur la base du relevé de consommation.'),
  (date: '2026-10-27', service: 'Pharmacie d’urgence', demandeur: 'AKONDE Octave', motif: 'Seuil d’alerte atteint', familles: ['medicament'], lignes: 4, issue: 'accorde', differente: false, arbitre: direction1, arbitrage: '2026-10-29', service_: null, motifRejet: null),
  (date: '2026-10-30', service: 'Laboratoire', demandeur: 'IDOHOU Abraham', motif: 'Réapprovisionnement mensuel', familles: ['reactif', 'conso_labo'], lignes: 3, issue: 'soumis', differente: false, arbitre: null, arbitrage: null, service_: null, motifRejet: null),
  (date: '2026-11-02', service: 'Administration', demandeur: 'MABOUDOU Nawal', motif: 'Dotation de service', familles: ['fourniture'], lignes: 3, issue: 'prepare', differente: true, arbitre: direction2, arbitrage: '2026-11-03', service_: null, motifRejet: null),
  (date: '2026-11-03', service: 'Maternité', demandeur: 'IDOHOU Abraham', motif: 'Rupture constatée', familles: ['medicament'], lignes: 3, issue: 'soumis', differente: false, arbitre: null, arbitrage: null, service_: null, motifRejet: null),
  (date: '2026-11-05', service: 'Hospitalisation', demandeur: 'AKONDE Octave', motif: 'Réapprovisionnement mensuel', familles: ['conso_medical'], lignes: 3, issue: 'soumis', differente: false, arbitre: null, arbitrage: null, service_: null, motifRejet: null),
];

/// Une commande : (fournisseur, date, validation, livraison, facture, règlement) ; `ecart` : la livraison est incomplète ; `lignes` : nombre d'articles.
typedef _PlanCommande = ({
  String fournisseur,
  String date,
  String validation,
  String? livraison,
  String? facture,
  String? reglement,
  String statut,
  int lignes,
  bool ecart,
});

const List<_PlanCommande> _commandes = [
  (fournisseur: 'GPB', date: '2026-08-03', validation: '2026-08-04', livraison: '2026-08-11', facture: '2026-08-12', reglement: '2026-09-10', statut: 'soldee', lignes: 5, ecart: false),
  (fournisseur: 'CAP', date: '2026-08-18', validation: '2026-08-19', livraison: '2026-08-27', facture: '2026-08-28', reglement: '2026-09-25', statut: 'soldee', lignes: 5, ecart: false),
  (fournisseur: 'REA', date: '2026-09-01', validation: '2026-09-02', livraison: '2026-09-14', facture: '2026-09-15', reglement: '2026-10-14', statut: 'soldee', lignes: 5, ecart: false),
  (fournisseur: 'GPB', date: '2026-09-10', validation: '2026-09-11', livraison: '2026-09-18', facture: '2026-09-19', reglement: '2026-10-16', statut: 'soldee', lignes: 5, ecart: true),
  (fournisseur: 'MMN', date: '2026-09-22', validation: '2026-09-23', livraison: '2026-10-02', facture: '2026-10-03', reglement: null, statut: 'livree', lignes: 5, ecart: false),
  (fournisseur: 'FEB', date: '2026-10-14', validation: '2026-10-15', livraison: '2026-10-26', facture: '2026-10-28', reglement: null, statut: 'livree', lignes: 5, ecart: false),
  (fournisseur: 'GPB', date: '2026-10-28', validation: '2026-10-29', livraison: null, facture: null, reglement: null, statut: 'transmise', lignes: 6, ecart: false),
  (fournisseur: 'CAP', date: '2026-11-04', validation: '2026-11-05', livraison: null, facture: null, reglement: null, statut: 'validee', lignes: 6, ecart: false),
];

/// Les services demandeurs des transferts gros vers détail, dans l'ordre (quinze bons). Le laboratoire ne reçoit que des réactifs et des consommables de labo.
const List<String> _servicesTransfert = [
  'Pharmacie d’urgence', 'Laboratoire', 'Pharmacie d’urgence', 'Hospitalisation', 'Maternité', 'Pharmacie d’urgence', 'Laboratoire', 'Pharmacie d’urgence',
  'Hospitalisation', 'Maternité', 'Pharmacie d’urgence', 'Laboratoire', 'Pharmacie d’urgence', 'Hospitalisation', 'Pharmacie d’urgence',
];

const Map<String, String> _prefixesCode = {
  'medicament': 'MED',
  'conso_medical': 'CMD',
  'fourniture': 'FOU',
  'entretien': 'ENT',
  'petit_materiel': 'PMT',
  'reactif': 'REA',
  'conso_labo': 'CLB',
};

class Stock {
  Stock(this.a, this.caisse, this.compta);
  final Atelier a;
  final CaisseComptoir caisse;
  final Comptabilite compta;

  Tirage get t => a.t;

  /// Les produits réservés : leur lot périmé ou proche de la péremption ne bouge pas (aucune sortie, aucune livraison).
  final Set<String> reserves = {};

  /// Les huit produits qui finiront sous leur seuil.
  final Set<String> bas = {};

  /// Les quantités du stock gros promises à un bon de besoins accordé et pas encore servi : ni transfert ni perte ne les entame.
  final Map<String, num> reservation = {};

  /// Les mouvements écrits avec leur lot, pour le compte rendu.
  int refus = 0;

  // --- aides ---------------------------------------------------------------------------------------------------------------------------------

  Fiche _produit(Object? id) => a.parId('produits', id)!;
  List<Fiche> _produits() => a.fiches('produits');

  /// Met à jour le stock d'un produit : le total est TOUJOURS gros + détail.
  void _stock(Object? id, {num? gros, num? detail}) {
    final p = _produit(id);
    final g = gros ?? _n(p['stockGros']);
    final dt = detail ?? _n(p['stockDetail']);
    a.maj('produits', id, {'stockGros': g, 'stockDetail': dt, 'stock': g + dt});
  }

  /// Écrit un mouvement : référence de la série `M000001` (le plus grand rang + 1), identifiant `MOU00001`. [lot] : le numéro du lot touché.
  Fiche _mouvement({
    required String date,
    required Fiche produit,
    required String type,
    required String typeLabel,
    required num quantite,
    required String stockType,
    required String justificatif,
    required String utilisateur,
    String? lot,
    String? reference,
  }) =>
      a.ajouter(
          'mouvements',
          {
            'reference': reference ?? d.referenceSuivante('M', 6, a.toutes('mouvements')),
            'date': date,
            'produitId': produit['id'],
            'produit': produit['designation'],
            'type': type,
            'typeLabel': typeLabel,
            'quantite': quantite,
            'stockType': stockType,
            'justificatif': justificatif,
            'utilisateur': utilisateur,
            if (lot != null) 'lot': lot,
          },
          'MOU');

  /// FEFO (RG-05) : consomme [q] unités des lots du produit, le premier à périmer d'abord, JAMAIS un lot périmé à [jour]. Rend les (lot, quantité) prélevés.
  List<(Fiche, num)> _consommer(Object? produitId, num q, String jour) {
    final lots = [
      for (final l in a.fiches('lots'))
        if (l['produitId'] == produitId && '${l['datePeremption']}'.compareTo(jour) >= 0) l
    ];
    var reste = q;
    final pris = <(Fiche, num)>[];
    for (final l in d.ordreFefo(lots)) {
      if (reste <= 0) break;
      final prend = _n(l['quantiteRestante']) < reste ? _n(l['quantiteRestante']) : reste;
      a.maj('lots', l['id'], {'quantiteRestante': _n(l['quantiteRestante']) - prend});
      pris.add((l, prend));
      reste -= prend;
    }
    if (reste > 0) throw StateError('Lots insuffisants pour ${_produit(produitId)['designation']} : il manque $reste.');
    return pris;
  }

  /// Le stock de ce que le premier lot FEFO peut encore fournir à [jour].
  num _premierLot(Object? produitId, String jour) {
    final lots = [
      for (final l in a.fiches('lots'))
        if (l['produitId'] == produitId && '${l['datePeremption']}'.compareTo(jour) >= 0) l
    ];
    final o = d.ordreFefo(lots);
    return o.isEmpty ? 0 : _n(o.first['quantiteRestante']);
  }

  num _plancher(Fiche p) => bas.contains(p['id']) ? 1 : 4;

  // --- référentiels, produits, stock initial ---------------------------------------------------------------------------------------------------------

  void referentiels() {
    for (final (code, zone, temperature) in _emplacements) {
      a.ajouter('emplacements', {'code': code, 'libelle': code, 'zone': zone, 'temperature': temperature, 'source': 'Plan de rangement de démonstration, à adapter à la clinique'}, 'EMP', largeur: 3);
    }
    for (final (code, nom, type, delai, habilite) in _fournisseurs) {
      final f = d.valeursFournisseur({'code': code, 'nom': nom, 'type': type, 'ville': 'Parakou', 'tel': '', 'delai': delai, 'habilite': habilite});
      a.ajouter('fournisseurs', {...f, 'fictif': true, 'source': 'Fournisseur fictif de démonstration : nom générique, sans téléphone, IFU, compte ni agrément'}, 'F', largeur: 3);
    }
  }

  String _emplacement(EntreeCatalogue e, int rang) {
    final (famille, designation, unite, _, urgent) = e;
    switch (famille) {
      case 'medicament':
        if (designation.startsWith('Morphine') || designation.startsWith('Diazépam')) return 'Armoire sécurisée 1';
        if (designation.startsWith('Insuline') || designation.startsWith('Oxytocine')) return 'Réfrigérateur 1';
        if (urgent) return 'Chariot d’urgence';
        return 'Rayon A, casier ${1 + rang % 4}';
      case 'conso_medical':
        return urgent ? 'Chariot d’urgence' : 'Rayon B, casier ${1 + rang % 3}';
      case 'fourniture':
        return 'Rayon C, casier 1';
      case 'entretien':
        return 'Rayon C, casier 2';
      case 'petit_materiel':
        return 'Rayon B, casier 4';
      case 'reactif':
        return const ['Kit', 'Flacon', 'Test'].contains(unite) ? 'Réfrigérateur 1' : 'Rayon D, casier 1';
      default:
        return 'Rayon D, casier 2';
    }
  }

  String _fournisseurDe(String famille, int rang) => switch (famille) {
        'medicament' => rang.isEven ? 'GPB' : 'CAP',
        'conso_medical' => rang.isEven ? 'CAP' : 'MMN',
        'petit_materiel' => 'MMN',
        'fourniture' || 'entretien' => 'FEB',
        _ => 'REA',
      };

  /// Les 150 produits, leur stock initial (gros et détail), leurs lots et les mouvements d'entrée du 01/08. Les tirages se font dans un ordre FIXE.
  void produitsEtOuverture() {
    final nonUrgentsMed = [for (var i = 0; i < catalogue.length; i++) if (catalogue[i].$1 == 'medicament' && !catalogue[i].$5) i];
    final reservesIdx = t.melanger(nonUrgentsMed).take(8).toSet();
    final pool = [for (var i = 0; i < catalogue.length; i++) if ((catalogue[i].$1 == 'medicament' || catalogue[i].$1 == 'conso_medical') && !catalogue[i].$5 && !reservesIdx.contains(i)) i];
    final basIdx = t.melanger(pool).take(8).toSet();

    final rangParFamille = <String, int>{};
    final lotsPrevus = <(String, String)>[]; // (produitId, date de péremption)
    final quantites = <String, num>{};
    for (var i = 0; i < catalogue.length; i++) {
      final e = catalogue[i];
      final (famille, designation, unite, prix, urgent) = e;
      final rang = rangParFamille[famille] = (rangParFamille[famille] ?? -1) + 1;
      final int total = basIdx.contains(i) ? t.entre(10, 22) : (t.entre(30000, 90000) / prix).round().clamp(12, 900).toInt();
      final part = famille == 'medicament' ? (urgent ? 0.4 : 0.25) : (famille == 'conso_medical' ? 0.2 : 0.0);
      var detail = (total * part).round();
      if (total - detail < 1) detail = total - 1;
      final Map<String, Object?> saisie = {
        'code': '${_prefixesCode[famille]}-${pad(rang + 1, 3)}',
        'designation': designation,
        'unite': unite,
        'categorie': famille,
        'prixAchat': prix,
        'seuilAlerte': 1,
        'stockGros': total - detail,
        'stockDetail': detail,
        'emplacement': _emplacement(e, rang),
        'fournisseur': _fournisseurDe(famille, rang),
      };
      final p = a.ajouter(
          'produits',
          {
            ...d.transformerProduit(saisie),
            if (urgent) 'urgence': true,
            'valorisationProvisoire': true,
            'sourceValorisation': 'Prix d’attente fictif de démonstration, à remplacer par la Direction à la première facture',
            'seuilAValider': true,
            'fictif': true,
            'source': sourceDemo,
          },
          'PRD',
          largeur: 4);
      if (reservesIdx.contains(i)) reserves.add('${p['id']}');
      if (basIdx.contains(i)) bas.add('${p['id']}');
      quantites['${p['id']}'] = total;
    }

    // Les péremptions : huit lots à dates imposées (deux périmés, six sous les soixante jours), les autres au-delà de mars 2027.
    const speciales = ['2026-09-18', '2026-10-22', '2026-11-18', '2026-11-30', '2026-12-05', '2026-12-14', '2026-12-28', '2027-01-04'];
    final reservesListe = reserves.toList();
    for (final p in _produits()) {
      final id = '${p['id']}';
      final k = reservesListe.indexOf(id);
      final peremption = k >= 0 ? speciales[k] : Contexte.date(DateTime.utc(2027, 3, 1).add(Duration(days: t.entre(0, 670))));
      lotsPrevus.add((id, peremption));
    }
    for (final (id, peremption) in lotsPrevus) {
      final p = _produit(id);
      final q = quantites[id]!;
      final lot = a.ajouter(
          'lots',
          {
            'produitId': id,
            'produit': p['designation'],
            'numeroLot': 'L2026-${pad(a.toutes('lots').length + 1, 4)}',
            'datePeremption': peremption,
            'quantiteRestante': q,
            'quantiteInitiale': q,
            'emplacement': p['emplacement'],
            'dateEntree': '2026-08-01',
            'origine': 'Stock initial au 01/08/2026',
            'statut': 'actif',
            'fictif': true,
            'source': sourceDemo,
          },
          'LOT',
          largeur: 4);
      for (final (magasin, qte) in [('gros', _n(p['stockGros'])), ('detail', _n(p['stockDetail']))]) {
        if (qte <= 0) continue;
        _mouvement(
            date: '2026-08-01',
            produit: p,
            type: 'entree',
            typeLabel: 'Entrée',
            quantite: qte,
            stockType: magasin,
            justificatif: 'Reprise du stock initial au 01/08/2026',
            utilisateur: comptableStock,
            lot: '${lot['numeroLot']}');
      }
    }
  }

  // --- le déroulé ----------------------------------------------------------------------------------------------------------------------------

  /// Inscrit TOUS les gestes à leur date, puis déroule la file.
  void derouler() {
    final jours = a.ctx.joursOuvres();
    _planifierBesoins();
    _planifierCommandes();
    _planifierTransferts(jours);
    _planifierVentes(jours);
    _planifierPertes();
    _planifierInventaires();
    a.derouler();
  }

  DateTime _a(String jour, int h, [int mn = 0]) => instant(jourIso(jour), h, mn);

  // --- besoins ----------------------------------------------------------------------------------------------------------------------------------

  void _planifierBesoins() {
    final ids = <int, String>{};
    for (var k = 0; k < _besoins.length; k++) {
      final b = _besoins[k];
      a.planifier(_a(b.date, 9), () => ids[k] = _creerBesoin(b));
      if (b.arbitrage != null) a.planifier(_a(b.arbitrage!, 11), () => _arbitrer(b, ids[k]!));
      if (b.issue == 'prepare') a.planifier(_a(b.arbitrage!, 15), () => _preparer(ids[k]!));
      if (b.service_ != null) a.planifier(_a(b.service_!, 14), () => _servir(ids[k]!));
    }
  }

  /// Un bon d'expression de besoins saisi par un agent : `bonEnregistre` pose la référence, le montant estimé, et le bon part SOUMIS (ou au contrôle du stock quand
  /// les quantités accordées sont déjà arrêtées). Les quantités des bons SERVIS sont fixées ici, sur le stock gros disponible, et réservées jusqu'au service.
  String _creerBesoin(_PlanBesoin b) {
    final valide = b.issue != 'soumis' && b.issue != 'rejete';
    final servi = b.service_ != null;
    final candidats = t.melanger([
      for (final p in _produits())
        if (b.familles.contains(p['categorie']) && !reserves.contains(p['id']) && !bas.contains(p['id'])) p
    ]);
    final lignes = <Fiche>[];
    for (final p in candidats) {
      if (lignes.length >= b.lignes) break;
      final prix = _n(p['prixAchat']);
      final demande = prix >= 5000 ? t.entre(2, 4) : (prix >= 1000 ? t.entre(3, 12) : t.entre(10, 60));
      var accorde = demande;
      if (valide && b.differente && lignes.isEmpty) accorde = (demande * 0.7).floor().clamp(1, demande - 1).toInt();
      if (servi && _n(p['stockGros']) - (reservation['${p['id']}'] ?? 0) < accorde + 4) continue;
      lignes.add(d.nouvelleLigneBesoin(produit: p, demandee: demande, accordee: valide ? accorde : null));
      if (servi) reservation['${p['id']}'] = (reservation['${p['id']}'] ?? 0) + accorde;
    }
    if (lignes.length < b.lignes) throw StateError('Besoin du ${b.date} : trop peu de produits disponibles.');
    final saisie = {
      'date': b.date,
      'service': b.service,
      'demandeur': b.demandeur,
      'motif': b.motif,
      'etape': valide ? 'controle_stock' : 'soumis',
    };
    final bon = d.bonEnregistre(saisie: saisie, lignes: lignes, bons: a.toutes('besoins'));
    final ins = a.ajouter('besoins', {...bon, 'fictif': true, 'source': sourceDemo}, 'BEB', largeur: 4);
    return '${ins['id']}';
  }

  /// L'arbitrage de la Direction : trois réponses, et le motif exigé quand on rejette. La validation informe le comptable et le gestionnaire de stock par une
  /// notification de poste, née du geste.
  void _arbitrer(_PlanBesoin b, String id) {
    final bon = a.parId('besoins', id)!;
    final rejet = b.issue == 'rejete';
    final r = d.arbitrerBon(
        bon: bon,
        quoi: rejet ? d.Arbitrage.rejeter : d.Arbitrage.valider,
        motif: rejet ? (b.motifRejet ?? '') : '',
        utilisateur: b.arbitre!,
        maintenant: iso8601(a.horloge));
    a.maj('besoins', id, r.patch);
    for (final nt in r.notifications) {
      a.ajouter(
          'notifications',
          {
            'type': nt['type'],
            'poste': nt['poste'],
            'libelle': nt['libelle'],
            'detail': nt['detail'],
            'priorite': nt['priorite'],
            'reference': nt['reference'],
            'lue': a.horloge.isBefore(DateTime.utc(2026, 10, 15)),
            'creeLe': iso8601(a.horloge),
            'statut': 'actif',
          },
          'NOT');
    }
  }

  void _preparer(String id) {
    a.maj('besoins', id, d.versCommandeBesoin(utilisateur: comptableStock, maintenant: iso8601(a.horloge)));
  }

  /// Le service d'un bon accordé : une sortie du stock gros par ligne, de la QUANTITÉ ACCORDÉE (jamais de la demandée), justifiée par le numéro du bon (RG-03),
  /// les lots vidés en FEFO.
  void _servir(String id) {
    final bon = a.parId('besoins', id)!;
    final jour = jourDe(a.horloge);
    final lignes = <Fiche>[];
    for (final l in (bon['lignes'] as List).cast<Map<String, Object?>>()) {
      final q = _n(l['quantiteAccordee']);
      final p = _produit(l['produitId']);
      if (q > _n(p['stockGros'])) throw StateError('RG-03 : ${p['designation']} : ${p['stockGros']} au magasin, $q accordé(s).');
      for (final (lot, qte) in _consommer(p['id'], q, jour)) {
        _mouvement(
            date: jour,
            produit: p,
            type: 'sortie',
            typeLabel: 'Sortie',
            quantite: qte,
            stockType: 'gros',
            justificatif: 'Bon de besoins ${bon['reference']}',
            utilisateur: comptableStock,
            lot: '${lot['numeroLot']}');
      }
      _stock(p['id'], gros: _n(p['stockGros']) - q);
      reservation['${p['id']}'] = (reservation['${p['id']}'] ?? 0) - q;
      lignes.add({...l, 'quantiteLivree': q});
    }
    a.maj('besoins', id, {...d.distribuerBesoin(utilisateur: comptableStock, maintenant: iso8601(a.horloge)), 'lignes': lignes});
  }

  // --- commandes, livraisons, procès-verbaux, factures fournisseurs --------------------------------------------------------------------------------

  void _planifierCommandes() {
    for (var k = 0; k < _commandes.length; k++) {
      final c = _commandes[k];
      var refCommande = '';
      a.planifier(_a(c.date, 9, 30), () => refCommande = _creerCommande(c, k));
      a.planifier(_a(c.validation, 10), () => _validerCommande(refCommande, c));
      if (c.statut != 'validee') a.planifier(_a(c.validation, 10, 30), () => a.maj('commandes', _commande(refCommande)['id'], {'statutCommande': 'transmise'}));
      if (c.livraison != null) {
        a.planifier(_a(c.livraison!, 11), () => _receptionner(refCommande, c, k));
        a.planifier(_a(c.livraison!, 12), () => _pv(refCommande, c));
        a.planifier(_a(c.facture!, 15), () => _facturer(refCommande, c, k));
        if (c.reglement != null) a.planifier(_a(c.reglement!, 11, 30), () => _regler(refCommande, c));
      }
    }
  }

  Fiche _commande(String reference) => a.fiches('commandes').firstWhere((x) => x['reference'] == reference);

  String _creerCommande(_PlanCommande c, int k) {
    final jour = c.date;
    var candidats = [
      for (final p in _produits())
        if (p['fournisseur'] == c.fournisseur && !reserves.contains(p['id']) && !bas.contains(p['id'])) p
    ];
    candidats = t.melanger(candidats);
    final lignes = <Fiche>[];
    for (final p in candidats.take(c.lignes)) {
      final prix = _n(p['prixAchat']);
      // Une ligne par commande livrée voit son prix bouger de 5 % (arrondi à 5 F) : le CUMP du moteur de réception n'est plus le prix d'achat.
      final hausse = lignes.length == 1 && prix >= 250 && c.livraison != null;
      final pu = hausse ? ((prix * 1.05) / 5).ceil() * 5 : prix;
      final q = (t.entre(40000, 120000) / prix).round().clamp(20, 600);
      lignes.add(d.nouvelleLigneCommande(produit: p, quantite: q, prixUnitaire: pu));
    }
    final fiche = d.commandeEnregistree(
      saisie: {'date': jour, 'fournisseur': c.fournisseur, 'statutCommande': 'attente_validation'},
      lignes: lignes,
      fournisseurs: a.fiches('fournisseurs'),
      commandes: a.toutes('commandes'),
      jour: jour,
    );
    final ins = a.ajouter('commandes', {...fiche, 'fictif': true, 'source': sourceDemo}, 'BC', largeur: 4);
    return '${ins['reference']}';
  }

  /// RG-04 : la commande est validée PAR LA DIRECTION avant toute transmission (jamais par un nom écrit en dur dans le moteur).
  void _validerCommande(String reference, _PlanCommande c) {
    final com = _commande(reference);
    final patch = d.validationCommande(jour: c.validation);
    a.maj('commandes', com['id'], {...patch, 'valideePar': _commandes.indexOf(c).isEven ? direction1 : direction2});
  }

  void _receptionner(String reference, _PlanCommande c, int k) {
    final com = _commande(reference);
    final lignes = (com['lignes'] as List).cast<Map<String, Object?>>();
    final recus = <String, num>{};
    if (c.ecart) {
      // Deux lignes arrivent incomplètes : le moteur écrit l'écart, le procès-verbal le nomme.
      for (final i in [1, 3]) {
        final q = _n(lignes[i]['quantite']);
        recus['${lignes[i]['produitId']}'] = q - (q * 0.15).ceil().clamp(1, q.toInt());
      }
    }
    final blRef = 'BL-${c.fournisseur}-26-${pad(412 + k * 37, 4)}';
    final r = d.calculerReception(
      commande: com,
      recus: recus,
      entete: {'referenceBL': blRef, 'date': c.livraison, 'controleur1': comptableStock, 'controleur2': comptableCaisse, 'observations': ''},
      produits: _produits(),
      mouvements: a.toutes('mouvements'),
    );
    for (final m in r.majProduits) {
      a.maj('produits', m.id, m.patch);
    }
    final liv = a.ajouter('livraisons', {...r.livraison, 'fictif': true, 'source': sourceDemo}, 'BL', largeur: 4);
    // Le mouvement d'entrée et le LOT de chaque ligne reçue.
    for (final m in r.mouvements) {
      final p = _produit(m['produitId']);
      final lot = a.ajouter(
          'lots',
          {
            'produitId': p['id'],
            'produit': p['designation'],
            'numeroLot': 'L2026-${pad(a.toutes('lots').length + 1, 4)}',
            'datePeremption': Contexte.date(DateTime.utc(2027, 3, 1).add(Duration(days: t.entre(0, 670)))),
            'quantiteRestante': m['quantite'],
            'quantiteInitiale': m['quantite'],
            'emplacement': p['emplacement'],
            'dateEntree': c.livraison,
            'origine': 'Bon de livraison $blRef',
            'statut': 'actif',
            'fictif': true,
            'source': sourceDemo,
          },
          'LOT',
          largeur: 4);
      a.ajouter('mouvements', {...m, 'lot': lot['numeroLot']}, 'MOU');
    }
    a.maj('commandes', com['id'], {...r.patchCommande, 'statutCommande': c.statut == 'soldee' ? 'livree' : c.statut});
    a.maj('livraisons', liv['id'], {'commandeId': com['id']});
  }

  Fiche _livraisonDe(String reference) => a.fiches('livraisons').firstWhere((l) => l['commandeRef'] == reference);

  /// Le procès-verbal de réception : un par livraison, de la nature de ses lignes. Une conclusion autre que « Conforme » EXIGE ses réserves, nommées.
  void _pv(String reference, _PlanCommande c) {
    final liv = _livraisonDe(reference);
    final lignes = (liv['lignes'] as List).cast<Map<String, Object?>>();
    final nature = d.estReactif(lignes.first['produitId'], _produits()) ? d.natureReactifs : d.natureConsommables;
    final manquants = [for (final l in lignes) if (_n(l['ecart']) != 0) l];
    final texteReserves = manquants.isEmpty
        ? ''
        : 'Livraison incomplète : ${[for (final l in manquants) '${l['produit']} : ${_n(l['ecart']).abs().toInt()} ${l['unite']} manquant(s) sur ${_n(l['quantite']).toInt()} commandé(s)'].join(' ; ')}. Le fournisseur est informé, le complément est attendu.';
    final pv = d.etablirPv(
      nature: nature,
      saisie: {
        'livraisonRef': liv['reference'],
        'date': liv['date'],
        'conclusion': manquants.isEmpty ? d.conclusionConforme : d.conclusionAvecReserves,
        'reserves': texteReserves,
        'representantFournisseur': 'Livreur du fournisseur (nom non relevé)',
        if (nature == d.natureReactifs) 'chaineFroid': true,
      },
      livraisons: a.fiches('livraisons'),
      produits: _produits(),
      references: [for (final p in a.fiches('pvReceptions')) '${p['reference']}'],
      nomSession: comptableStock,
    );
    a.ajouter('pvReceptions', {...pv, 'fictif': true, 'source': sourceDemo}, 'PVR', largeur: 4);
  }

  /// La facture du fournisseur, rapprochée de SA livraison (même montant, écart nul) ; payée ou non selon l'histoire. Sa pièce d'achat naît en brouillon.
  void _facturer(String reference, _PlanCommande c, int k) {
    final liv = _livraisonDe(reference);
    final com = _commande(reference);
    final montant = _n(liv['montant']);
    final echeance = Contexte.date(jourIso(c.facture!).add(const Duration(days: 30)));
    final ff = a.ajouter(
        'facturesFournisseurs',
        {
          'reference': d.referenceAchatSuivante('FF-2026-', 4, a.toutes('facturesFournisseurs')),
          'numeroFournisseur': 'FA-${c.fournisseur}-26-${pad(118 + k * 41, 4)}',
          'date': c.facture,
          'blRef': liv['reference'],
          'commandeRef': reference,
          'fournisseur': c.fournisseur,
          'fournisseurNom': com['fournisseurNom'],
          'montantLivraison': montant,
          'montantFacture': montant,
          'ecart': 0,
          'statutRappro': 'rapproche',
          'statutPaiement': 'impayee',
          'echeance': echeance,
          'fictif': true,
          'source': sourceDemo,
        },
        'FF',
        largeur: 4);
    final centre = switch (c.fournisseur) { 'REA' => 'laboratoire', 'FEB' => 'direction', _ => 'pharmacie' };
    final ids = compta.poserFactureAchat(ff, centre);
    a.maj('facturesFournisseurs', ff['id'], {'ecritureIds': ids});
  }

  void _regler(String reference, _PlanCommande c) {
    final ff = a.fiches('facturesFournisseurs').firstWhere((f) => f['commandeRef'] == reference);
    final jour = jourDe(a.horloge);
    final ids = compta.poserReglementFournisseur(ff, jour);
    a.maj('facturesFournisseurs', ff['id'], {'statutPaiement': 'payee', 'datePaiement': jour, 'ecritureReglementIds': ids});
    final com = _commande(reference);
    a.maj('commandes', com['id'], {'statutCommande': 'soldee'});
  }

  // --- transferts gros vers détail -------------------------------------------------------------------------------------------------------------

  void _planifierTransferts(List<DateTime> jours) {
    for (var k = 0; k < _servicesTransfert.length; k++) {
      final i = 2 + (k * (jours.length - 9) / (_servicesTransfert.length - 1)).round();
      a.planifier(instant(jours[i], 10, 30), () => _transfert(k, jourDe(jours[i])));
    }
  }

  /// Un bon de transfert multi-lignes : chaque ligne contrôlée RG-03 contre le disponible du magasin (hors ce qui est promis à un bon de besoins), le lot FEFO
  /// porté par la ligne ; deux mouvements symétriques par ligne (sortie du magasin, entrée à la pharmacie), justifiés par le numéro du bon.
  void _transfert(int k, String jour) {
    final service = _servicesTransfert[k];
    final labo = service == 'Laboratoire';
    final familles = labo ? const ['reactif', 'conso_labo'] : const ['medicament', 'conso_medical'];
    final n = labo ? t.entre(8, 14) : t.entre(12, 20);
    final candidats = t.melanger([
      for (final p in _produits())
        if (familles.contains(p['categorie']) && !reserves.contains(p['id']) && _n(p['stockGros']) - (reservation['${p['id']}'] ?? 0) >= 2) p
    ]);
    var lignes = <Fiche>[];
    for (final p in candidats.take(n)) {
      final dispo = _n(p['stockGros']) - (reservation['${p['id']}'] ?? 0);
      final q = (dispo * t.entre(20, 45) / 100).round().clamp(1, dispo.toInt());
      lignes = d.ajouterLigneTransfert(lignes: lignes, produitId: '${p['id']}', quantite: q, produits: _produits(), lots: a.fiches('lots'));
    }
    d.controlerBonAvantEcriture(lignes, _produits());
    final r = d.emettreTransfert(
      date: jour,
      demandeur: service,
      motif: t.pondere({'Réapprovisionnement hebdomadaire': 3, 'Seuil d’alerte atteint': 1}),
      lignes: lignes,
      produits: _produits(),
      bons: a.toutes('transferts'),
      utilisateur: comptableStock,
    );
    a.ajouter('transferts', {...r.bon, 'fictif': true, 'source': sourceDemo}, 'TRA', largeur: 4);
    for (final m in r.produits) {
      a.maj('produits', m.id, m.patch);
    }
    for (final m in r.mouvements) {
      a.ajouter('mouvements', m, 'MOU');
    }
  }

  // --- ventes de pharmacie au comptoir -----------------------------------------------------------------------------------------------------------

  void _planifierVentes(List<DateTime> jours) {
    final choisis = t.melanger(jours).take(40).toList()..sort((x, y) => x.compareTo(y));
    final tentatives = {12, 31};
    for (var k = 0; k < choisis.length; k++) {
      final j = choisis[k];
      final h = t.entre(8, 16);
      final mn = t.entre(0, 59);
      final quand = (j.month == 11 && j.day == 7) ? instant(j, 8, mn) : instant(j, h, mn);
      final mode = t.pondere({'especes': 7, 'tpe': 1, 'mtn': 1, 'moov': 1});
      a.planifier(quand, () {
        _vente(quand, mode);
        if (tentatives.contains(k)) _refusRg03(quand);
      });
    }
  }

  num _quantiteVente(Fiche p) {
    final multiple = const ['Comprimé', 'Gélule', 'Sachet'].contains(p['unite']);
    final q = multiple ? t.entre(4, 24) : t.entre(1, 3);
    final plafond = _n(p['stockDetail']) < _n(p['stock']) - _plancher(p) ? _n(p['stockDetail']) : _n(p['stock']) - _plancher(p);
    if (plafond < 1) return 0;
    return q < plafond ? q : plafond;
  }

  void _vente(DateTime quand, String mode) {
    final jour = jourDe(quand);
    final candidats = t.melanger([
      for (final p in _produits())
        if ((p['categorie'] == 'medicament' || (p['categorie'] == 'conso_medical' && t.chance(0.25))) && !reserves.contains(p['id']) && _n(p['stockDetail']) >= 1) p
    ]);
    final nb = t.pondere({1: 25, 2: 35, 3: 25, 4: 10, 5: 5});
    final lignes = <LigneVente>[];
    for (final p in candidats) {
      if (lignes.length >= nb) break;
      final q = _quantiteVente(p);
      if (q < 1) continue;
      lignes.add((produitId: '${p['id']}', designation: '${p['designation']}', nature: p['categorie'] == 'medicament' ? 'medicament' : 'libre', prixVente: _n(p['prixVente']), quantite: q, stockDetail: _n(p['stockDetail'])));
    }
    if (lignes.isEmpty) throw StateError('Aucun produit vendable au comptoir le $jour.');
    final r = caisse.vendre(quand: quand, lignes: lignes, mode: mode);
    // Les sorties : une par ligne (et par lot vidé), justifiées par le numéro de la facture (RG-03), prélevées sur le STOCK DÉTAIL.
    for (final s in r.sorties) {
      final p = _produit(s.produitId);
      for (final (lot, qte) in _consommer(p['id'], s.quantite, jour)) {
        _mouvement(
            date: jour,
            produit: p,
            type: 'sortie',
            typeLabel: 'Sortie',
            quantite: qte,
            stockType: 'detail',
            justificatif: s.justificatif,
            utilisateur: comptableCaisse,
            lot: '${lot['numeroLot']}');
      }
      _stock(p['id'], detail: _n(p['stockDetail']) - s.quantite);
    }
  }

  /// Une quantité supérieure au stock détail est REFUSÉE par le moteur, en le disant : rien n'est écrit (ni pièce, ni écriture, ni mouvement).
  void _refusRg03(DateTime quand) {
    final p = _produits().firstWhere((x) => x['categorie'] == 'medicament' && _n(x['stockDetail']) >= 1 && !reserves.contains(x['id']));
    final detail = _n(p['stockDetail']);
    try {
      caisse.ligne((produitId: '${p['id']}', designation: '${p['designation']}', nature: 'medicament', prixVente: _n(p['prixVente']), quantite: detail + 1, stockDetail: detail));
      throw StateError('Le moteur aurait dû refuser (RG-03) : ${p['designation']}.');
    } on d.RefusEmission catch (e) {
      if (e.code != 'RG03_STOCK') rethrow;
      refus++;
    }
  }

  // --- pertes ----------------------------------------------------------------------------------------------------------------------------------

  void _planifierPertes() {
    a.planifier(_a('2026-09-11', 15, 30), () => _perte('conso_medical', 2, 'casse', 'Constat de casse n° 01/2026 du 11/09/2026', comptableCaisse, 'Flacons brisés lors du rangement.', 12));
    a.planifier(_a('2026-10-06', 15, 30), () => _perte('medicament', 4, 'perte', 'Constat de disparition n° 02/2026 du 06/10/2026', comptableStock, 'Boîtes introuvables à l’inventaire de rayon.', 6));
  }

  /// Une perte déclarée : un MOUVEMENT de sortie valorisé au CUMP (`declarerPerte`), refusée si elle dépasse le stock (RG-03), le lot vidé en FEFO.
  void _perte(String famille, int rang, String type, String justificatif, String constatePar, String observation, num voulu) {
    final jour = jourDe(a.horloge);
    final p = _produits().where((x) => x['categorie'] == famille && !reserves.contains(x['id']) && !bas.contains(x['id']) && catalogue.firstWhere((e) => e.$2 == x['designation']).$5 == false).toList()[rang];
    final gros = _n(p['stockGros']) - (reservation['${p['id']}'] ?? 0);
    final detail = _n(p['stockDetail']);
    final magasin = detail >= gros ? 'detail' : 'gros';
    final stockMagasin = magasin == 'detail' ? detail : gros;
    var q = voulu;
    for (final borne in [stockMagasin, _n(p['stock']) - _plancher(p), _premierLot(p['id'], jour)]) {
      if (q > borne) q = borne;
    }
    if (q < 1) throw StateError('Perte impossible sur ${p['designation']}.');
    final r = d.declarerPerte(
        produit: p,
        type: type,
        quantite: q,
        date: jour,
        justificatif: justificatif,
        constatePar: constatePar,
        observation: observation,
        utilisateur: constatePar,
        mouvements: a.toutes('mouvements'));
    final pris = _consommer(p['id'], q, jour);
    a.ajouter('mouvements', {...r.mouvement, 'stockType': magasin, 'lot': pris.first.$1['numeroLot']}, 'MOU');
    _stock(p['id'], gros: magasin == 'gros' ? _n(p['stockGros']) - q : null, detail: magasin == 'detail' ? _n(p['stockDetail']) - q : null);
  }

  // --- inventaires -----------------------------------------------------------------------------------------------------------------------------

  void _planifierInventaires() {
    a.planifier(_a('2026-09-30', 17, 30), _inventaireClos);
    a.planifier(_a('2026-11-06', 16), _feuilleEnCours);
  }

  /// L'inventaire CLOS de fin septembre : tout le magasin gros, neuf écarts en moins (casse, perte) régularisés par `validerInventaire` : un mouvement par écart,
  /// justifié par le numéro de l'inventaire, jamais sous zéro. Les lots sont vidés en FEFO de la même quantité.
  void _inventaireClos() {
    final jour = jourDe(a.horloge);
    final candidats = t.melanger([
      for (final p in _produits())
        if (!reserves.contains(p['id']) && _n(p['stockGros']) - (reservation['${p['id']}'] ?? 0) >= 6 && _n(p['stock']) - _plancher(p) >= 4 && _premierLot(p['id'], jour) >= 3) p
    ]).take(9);
    final physiques = <String, Object?>{for (final p in candidats) '${p['id']}': _n(p['stockGros']) - t.entre(1, 3)};
    final r = d.validerInventaire(
      entete: {'magasin': 'gros', 'type': 'Mensuel', 'date': jour, 'perimetre': 'Tous les articles', 'operateur': comptableStock},
      cible: d.ciblesInventaire(_produits(), 'Tous les articles'),
      physiques: physiques,
      inventaires: a.toutes('inventaires'),
      mouvements: a.toutes('mouvements'),
    );
    a.ajouter('inventaires', {...r.inventaire, 'fictif': true, 'source': sourceDemo}, 'INV', largeur: 4);
    for (var i = 0; i < r.produits.length; i++) {
      final m = r.mouvements[i];
      final pris = _consommer(r.produits[i].id, _n(m['quantite']), jour);
      a.maj('produits', r.produits[i].id, r.produits[i].patch);
      a.ajouter('mouvements', {...m, 'lot': pris.first.$1['numeroLot']}, 'MOU');
    }
  }

  /// La feuille d'inventaire EN COURS sur le magasin détail (médicaments) : comptage entamé, écarts relevés mais NON régularisés. Le poste ne persiste pas
  /// une feuille ouverte (elle vit dans l'écran) : la fiche écrite ici est un BROUILLON du registre des inventaires, sans mouvement ni correction de stock.
  void _feuilleEnCours() {
    final jour = jourDe(a.horloge);
    final cible = d.ciblesInventaire(_produits(), 'Médicaments');
    final comptes = t.melanger([for (final p in cible) if (_n(p['stockDetail']) >= 3) p]).take(5);
    final physiques = <String, Object?>{for (final p in comptes) '${p['id']}': _n(p['stockDetail']) - t.entre(1, 2)};
    final r = d.validerInventaire(
      entete: {'magasin': 'detail', 'type': 'Ponctuel', 'date': jour, 'perimetre': 'Médicaments', 'operateur': comptableStock},
      cible: cible,
      physiques: physiques,
      inventaires: a.toutes('inventaires'),
      mouvements: a.toutes('mouvements'),
    );
    a.ajouter('inventaires', {...r.inventaire, 'statutInv': 'brouillon', 'fictif': true, 'source': 'Feuille d’inventaire en cours (brouillon) : comptage non validé, aucune régularisation'}, 'INV', largeur: 4);
  }

  // --- seuils ----------------------------------------------------------------------------------------------------------------------------------

  /// Les seuils d'alerte, fixés EN FIN de déroulé : huit produits sont sous leur seuil (jamais en rupture), tous les autres au-dessus. Valeurs d'attente.
  void fixerLesSeuils() {
    for (final p in _produits()) {
      final fin = _n(p['stock']);
      final seuil = bas.contains(p['id']) ? fin + t.entre(1, 3) : (fin * 0.4).floor().clamp(1, 1000000);
      a.maj('produits', p['id'], {'seuilAlerte': seuil});
    }
    // Le statut d'un lot se déduit de son échéance, à la date du jeu.
    for (final l in a.fiches('lots')) {
      final f = d.transformerLot({...l}, Contexte.maintenant, _produits());
      a.maj('lots', l['id'], {'produit': f['produit'], 'statut': f['statut']});
    }
  }
}
