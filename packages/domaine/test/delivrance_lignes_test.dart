// DÉLIVRANCE LIGNE PAR LIGNE (Direction de Baguidi, 16/11/2026, E3300 à E3306) : chaque ligne RÉGLÉE se délivre ; une ligne non réglée ou au « prix à
// valoriser » reste en attente, nommée ; RG-03 (justificatif, stock jamais négatif, refus nommé), RG-05 (lot FEFO), idempotence par ligne, état de l'ordonnance.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

const _t1 = '2026-11-16T09:00:00.000';
const _t2 = '2026-11-16T15:00:00.000';

Map<String, Object?> _prod(String id, String designation, num stock, {num? detail, num? seuil = 2, num prix = 100}) => {
      'id': id,
      'code': id,
      'designation': designation,
      'unite': 'Boîte',
      'stock': stock,
      'stockDetail': detail ?? stock,
      'prixAchat': prix,
      'prixVente': prix,
      'cump': prix,
      'seuilAlerte': seuil,
    };

Map<String, Object?> _ligneFac(String id, String produitId, String designation, {String statut = 'du', bool aValoriser = false, num montant = 200}) => {
      'id': id,
      'categorie': 'medicament',
      'designation': designation,
      'produitId': produitId,
      'quantite': 2,
      'montant': aValoriser ? null : montant,
      'partPatient': aValoriser ? null : montant,
      if (aValoriser) 'prixAValoriser': true,
      'statutPaiement': statut,
    };

void main() {
  final para = _prod('P1', 'PARACETAMOL 500 MG CP', 40);
  final amox = _prod('P2', 'AMOXICILLINE 500 MG GEL', 30);
  final nouv = _prod('P3', 'NOUVEAU SIROP', 10);
  final adre = _prod('P4', 'ADRENALINE 1 MG INJ', 5);
  final produits = [para, amox, nouv, adre];

  Map<String, Object?> ord({List<Map<String, Object?>>? meds, String statut = 'partielle'}) => {
        'id': 'O1',
        'numero': 'ORD-2026-00001',
        'patient': 'TEST Patient',
        'patientCode': 'CBG/1/26',
        'factureId': 'F1',
        'statutPaiement': statut,
        'statutDispensation': 'en_attente',
        'medicaments': meds ??
            [
              {'produitId': 'P1', 'produit': 'PARACETAMOL 500 MG CP', 'quantite': 2, 'prix': 100, 'total': 200},
              {'produitId': 'P2', 'produit': 'AMOXICILLINE 500 MG GEL', 'quantite': 2, 'prix': 100, 'total': 200},
              {'produitId': 'P3', 'produit': 'NOUVEAU SIROP', 'quantite': 2, 'prix': null, 'total': null, 'prixAValoriser': true},
            ],
      };
  Map<String, Object?> fac({String l1 = 'paye', String l2 = 'du', bool l3AValoriser = true, String l3 = 'du'}) => {
        'id': 'F1',
        'numero': 'FP-2026-00001',
        'ordonnanceId': 'O1',
        'statutPaiement': 'partielle',
        'lignes': [
          _ligneFac('L001', 'P1', 'PARACETAMOL 500 MG CP', statut: l1),
          _ligneFac('L002', 'P2', 'AMOXICILLINE 500 MG GEL', statut: l2),
          _ligneFac('L003', 'P3', 'NOUVEAU SIROP', statut: l3, aValoriser: l3AValoriser),
          {'id': 'L004', 'categorie': 'analyse', 'designation': 'NFS', 'statutPaiement': 'du', 'montant': 3000, 'partPatient': 3000},
        ],
      };
  final tache = {'id': 'T1', 'type': 'dispensation', 'ordonnanceId': 'O1', 'statut': 'en_attente'};

  DelivranceLignes delivrer(Map<String, Object?> o, Map<String, Object?>? f,
          {List<int>? lignes, String? voie, List<Map<String, Object?>> lots = const [], List<Map<String, Object?>>? prods, String instant = _t1}) =>
      delivrerLignes(
          ordonnance: o,
          facture: f,
          produits: prods ?? produits,
          taches: [tache],
          mouvementsExistants: const [],
          lots: lots,
          lignes: lignes,
          voie: voie,
          methode: 'prixVente',
          utilisateur: 'Agent de la pharmacie',
          instant: instant);

  Map<String, Object?> appliquer(Map<String, Object?> o, DelivranceLignes r) => {...o, ...r.ordonnancePatch};

  group('l’état de chaque ligne se lit sur SA ligne payable', () {
    test('réglée → délivrable ; due → en attente « non réglée à la caisse » ; sans prix → en attente « prix à valoriser »', () {
      final e = lignesDelivrance(ord(), fac());
      expect(e.map((x) => x.etat), [EtatLigneDelivrance.delivrable, EtatLigneDelivrance.nonReglee, EtatLigneDelivrance.prixAValoriser]);
      expect(e.map((x) => x.motif), [null, 'non réglée à la caisse', 'prix à valoriser']);
      expect(e[1].libelle, 'En attente — non réglée à la caisse');
      expect(e[2].libelle, 'En attente — prix à valoriser');
      expect(e.map((x) => x.ligneFacture?['id']), ['L001', 'L002', 'L003'], reason: 'rapprochement par rang, produit vérifié');
    });

    test('rapprochement : deux lignes du même produit prennent deux lignes payables distinctes', () {
      final o = ord(meds: [
        {'produitId': 'P1', 'produit': 'PARA', 'quantite': 1},
        {'produitId': 'P1', 'produit': 'PARA', 'quantite': 1},
      ]);
      final f = {
        'id': 'F1',
        'lignes': [_ligneFac('A', 'P1', 'PARA', statut: 'du'), _ligneFac('B', 'P1', 'PARA', statut: 'paye')]
      };
      final e = lignesDelivrance(o, f);
      expect(e.map((x) => x.ligneFacture!['id']), ['A', 'B']);
      expect(e.map((x) => x.delivrable), [false, true]);
    });

    test('pièce antérieure au modèle par lignes : la ligne est réglée si la pièce est soldée', () {
      final o = ord(statut: 'soldee', meds: [
        {'produitId': 'P1', 'produit': 'PARA', 'quantite': 1}
      ])
        ..remove('factureId');
      expect(lignesDelivrance(o, null).single.delivrable, isTrue);
      expect(lignesDelivrance({...o, 'statutPaiement': 'impayee'}, null).single.etat, EtatLigneDelivrance.nonReglee);
    });

    test('une ordonnance « servie » par l’ancien moteur, sans marque de ligne, est lue entièrement délivrée', () {
      final o = {...ord(), 'statutDispensation': 'servie'};
      expect(lignesDelivrance(o, fac()).every((x) => x.delivree), isTrue);
      expect(etatDispensation(o), 'servie');
    });

    test('factureDeLOrdonnance : par factureId, sinon par ordonnanceId ; une pièce archivée ne compte pas', () {
      final f = fac();
      expect(factureDeLOrdonnance(ord(), [f])?['id'], 'F1');
      expect(factureDeLOrdonnance({...ord()}..remove('factureId'), [f])?['id'], 'F1');
      expect(factureDeLOrdonnance(ord(), [{...f, 'statut': 'archive'}]), isNull);
    });
  });

  group('delivrerLignes — la ligne réglée se délivre, les autres attendent', () {
    test('règlement partiel : seule la ligne réglée sort du stock, justifiée par le n° d’ordonnance ; l’ordonnance devient partiellement délivrée', () {
      final r = delivrer(ord(), fac());
      expect(r.deja, isFalse);
      expect(r.lignesDelivrees, [0]);
      expect(r.mouvements, hasLength(1));
      final mv = r.mouvements.single;
      expect(mv['justificatif'], 'Ordonnance ORD-2026-00001', reason: 'RG-03');
      expect(mv['type'], 'sortie');
      expect(mv['sens'], 'sortie');
      expect(mv['produitId'], 'P1');
      expect(mv['ligneOrdonnance'], 0);
      expect(mv['ligneFactureId'], 'L001');
      expect(mv['circuit'], 'delivrance_externe');
      expect(mv['destination'], 'Patient');
      expect(r.produits.single.patch, {'stockDetail': 38, 'stock': 38});
      expect(r.etat, 'partielle');
      expect(r.ordonnancePatch['statutDispensation'], 'partielle');
      expect(r.ordonnancePatch.containsKey('dispenseLe'), isFalse, reason: 'l’ordonnance n’est pas servie');
      final meds = (r.ordonnancePatch['medicaments'] as List).cast<Map>();
      expect(meds[0]['delivreLe'], _t1);
      expect(meds[0]['delivrePar'], 'Agent de la pharmacie');
      expect(meds[0]['delivreMouvement'], mv['reference']);
      expect(meds[1].containsKey('delivreLe'), isFalse);
      expect(r.enAttente.map((e) => '${e.designation} : ${e.motif}'),
          ['AMOXICILLINE 500 MG GEL : non réglée à la caisse', 'NOUVEAU SIROP : prix à valoriser']);
      expect(r.journal['action'], 'Dispensation partielle');
      expect((r.journal['apres'] as Map)['enAttente'], ['AMOXICILLINE 500 MG GEL (non réglée à la caisse)', 'NOUVEAU SIROP (prix à valoriser)']);
      // Le registre des dispensations : une fiche par geste, au prix d'achat (RG-02).
      expect(r.dispensation!['reference'], 'DISP-00001');
      expect(r.dispensation!['montant'], 200);
      expect((r.dispensation!['lignes'] as List).single['produit'], 'PARACETAMOL 500 MG CP');
    });

    test('plus rien de délivrable : la tâche retourne en attente de la caisse ; il reste une ligne délivrable : elle reste ouverte', () {
      final r = delivrer(ord(), fac());
      expect(r.tachesFermees, isEmpty);
      final t = r.tachesMisesAJour.single;
      expect(t.patch['statut'], 'bloque');
      expect(t.patch['detail'], '1/3 ligne(s) délivrée(s) — en attente : AMOXICILLINE 500 MG GEL (non réglée à la caisse), NOUVEAU SIROP (prix à valoriser)');
      final r2 = delivrer(ord(), fac(l2: 'paye'), lignes: [0]);
      expect(r2.tachesMisesAJour.single.patch['statut'], 'en_attente');
    });

    test('IDEMPOTENCE PAR LIGNE : une ligne délivrée ne ressort jamais du stock', () {
      final apres = appliquer(ord(), delivrer(ord(), fac()));
      final encore = delivrer(apres, fac(), lignes: [0]);
      expect(encore.deja, isTrue);
      expect(encore.mouvements, isEmpty);
      expect(encore.produits, isEmpty);
      // Sans désignation : seules les lignes délivrables, et il n'y en a plus : refus NOMMÉ des lignes en attente, rien n'est écrit.
      expect(
          () => delivrer(apres, fac()),
          throwsA(isA<RefusDelivrance>().having((r) => r.motif, 'motif',
              'Aucune ligne délivrable sur l’ordonnance ORD-2026-00001 — « AMOXICILLINE 500 MG GEL » : non réglée à la caisse ; « NOUVEAU SIROP » : prix à valoriser. Seule une ligne réglée à la caisse se délivre.')));
    });

    test('une ligne DEMANDÉE qui attend la caisse ou son prix est refusée nommément : jamais servie « au passage »', () {
      expect(
          () => delivrer(ord(), fac(), lignes: [0, 1]),
          throwsA(isA<RefusDelivrance>().having((r) => r.motif, 'motif', contains('« AMOXICILLINE 500 MG GEL » : non réglée à la caisse'))));
      expect(() => delivrer(ord(), fac(), lignes: [2]),
          throwsA(isA<RefusDelivrance>().having((r) => r.motif, 'motif', contains('« NOUVEAU SIROP » : prix à valoriser'))));
    });

    test('la délivrance partielle laisse le reste délivrable plus tard : réglée ensuite, la ligne suivante se délivre, puis la dernière une fois valorisée et réglée',
        () {
      var o = appliquer(ord(), delivrer(ord(), fac()));
      final r2 = delivrer(o, fac(l2: 'paye'), instant: _t2);
      expect(r2.lignesDelivrees, [1]);
      expect(r2.etat, 'partielle');
      o = appliquer(o, r2);
      final r3 = delivrer(o, fac(l2: 'paye', l3AValoriser: false, l3: 'paye'), instant: _t2);
      expect(r3.lignesDelivrees, [2]);
      expect(r3.etat, 'servie');
      expect(r3.ordonnancePatch['dispenseLe'], _t2);
      expect(r3.tachesFermees.single.patch['statut'], 'fait');
      expect(r3.journal['action'], 'Dispensation');
      expect(etatDispensation(appliquer(o, r3)), 'servie');
    });

    test('RG-03 : le CUMUL des lignes d’un même produit est contrôlé, le refus NOMME l’article, rien n’est écrit', () {
      final o = ord(meds: [
        {'produitId': 'P4', 'produit': 'ADRENALINE 1 MG INJ', 'quantite': 3},
        {'produitId': 'P4', 'produit': 'ADRENALINE 1 MG INJ', 'quantite': 3},
      ]);
      final f = {
        'id': 'F1',
        'lignes': [_ligneFac('A', 'P4', 'ADRENALINE 1 MG INJ', statut: 'paye'), _ligneFac('B', 'P4', 'ADRENALINE 1 MG INJ', statut: 'paye')]
      };
      expect(
          () => delivrer(o, f),
          throwsA(isA<RefusDelivrance>()
              .having((r) => r.motif, 'motif', 'Délivrance refusée — stock insuffisant sur « ADRENALINE 1 MG INJ » : 2 en rayon pour 3 demandé(s).')
              .having((r) => r.manquants.length, 'manquants', 1)));
      // Les lignes COUVERTES se délivrent seules ; l'autre reste délivrable (rien ne ressort deux fois).
      final r = delivrer(o, f, lignes: [0]);
      expect(r.produits.single.patch, {'stockDetail': 2, 'stock': 2});
      expect(r.etat, 'partielle');
      final restants = lignesDelivrance(appliquer(o, r), f).where((x) => x.delivrable).toList();
      expect(restants.map((x) => x.index), [1], reason: 'la seconde ligne reste délivrable plus tard');
      final apresStock = [for (final p in produits) p['id'] == 'P4' ? {...p, ...r.produits.single.patch} : p];
      expect(couvertureStock(restants, apresStock).single.suffisant, isFalse, reason: '2 en rayon pour 3 : elle attend un transfert');
    });

    test('le stock ne devient jamais négatif (aucun patch sous zéro)', () {
      final r = delivrer(ord(), fac(l2: 'paye'));
      for (final p in r.produits) {
        expect((p.patch['stockDetail'] as num) >= 0 && (p.patch['stock'] as num) >= 0, isTrue);
      }
    });

    test('les deux pharmacies suivent la même règle : chacune ne sert que SA voie', () {
      final o = ord(meds: [
        {'produitId': 'P4', 'produit': 'ADRENALINE 1 MG INJ', 'quantite': 1},
        {'produitId': 'P1', 'produit': 'PARACETAMOL 500 MG CP', 'quantite': 1},
      ]);
      final f = {
        'id': 'F1',
        'lignes': [_ligneFac('A', 'P4', 'ADRENALINE 1 MG INJ', statut: 'paye'), _ligneFac('B', 'P1', 'PARACETAMOL 500 MG CP')]
      };
      final interne = delivrer(o, f, voie: 'parenterale');
      expect(interne.lignesDelivrees, [0]);
      expect(interne.mouvements.single['destination'], 'Salle de soins');
      expect(interne.mouvements.single['circuit'], 'delivrance_interne');
      expect(() => delivrer(o, f, voie: 'orale'),
          throwsA(isA<RefusDelivrance>().having((r) => r.motif, 'motif', contains('« PARACETAMOL 500 MG CP » : non réglée à la caisse'))));
    });

    test('RG-05 : le mouvement porte le lot FEFO — le premier à périmer, hors périmé et hors épuisé', () {
      final lots = [
        {'id': 'a', 'produitId': 'P1', 'numeroLot': 'L-PERIME', 'datePeremption': '2026-10-01', 'quantiteRestante': 10},
        {'id': 'b', 'produitId': 'P1', 'numeroLot': 'L-2027', 'datePeremption': '2027-05-01', 'quantiteRestante': 10},
        {'id': 'c', 'produitId': 'P1', 'numeroLot': 'L-2026-12', 'datePeremption': '2026-12-15', 'quantiteRestante': 10},
        {'id': 'd', 'produitId': 'P1', 'numeroLot': 'L-VIDE', 'datePeremption': '2026-11-20', 'quantiteRestante': 0},
      ];
      final mv = delivrer(ord(), fac(), lots: lots).mouvements.single;
      expect(mv['lot'], 'L-2026-12');
      expect(mv['peremption'], '2026-12-15');
      expect(lotFefo('P9', lots, '2026-11-16'), isNull);
    });
  });

  group('l’état de l’ordonnance et l’annulation d’un encaissement', () {
    test('non délivrée / partiellement délivrée / délivrée, déduits des lignes', () {
      expect(etatDispensation(ord()), 'en_attente');
      expect(etatDispensation(appliquer(ord(), delivrer(ord(), fac()))), 'partielle');
      expect(etatDispensation({'medicaments': const []}), 'sans_objet');
      expect([for (final c in ['en_attente', 'partielle', 'servie', 'sans_objet']) libelleDispensation(c)],
          ['Non délivrée', 'Partiellement délivrée', 'Délivrée', 'Sans médicament']);
    });

    test('un encaissement qui avait libéré une ligne DÉJÀ délivrée ne s’annule plus : refus nommé, voie de l’avoir ; une autre ligne : aucun refus', () {
      final apres = appliquer(ord(), delivrer(ord(), fac()));
      final motif = refusAnnulationEncaissement(apres, fac(), ['L001', 'L004']);
      expect(motif, startsWith('Annulation refusée : la ligne « PARACETAMOL 500 MG CP » (mouvement M000001) a déjà été délivrée au titre de l’ordonnance ORD-2026-00001'));
      expect(motif, contains('avoir'));
      expect(refusAnnulationEncaissement(apres, fac(), ['L002', 'L004']), isNull);
      expect(refusAnnulationEncaissement(ord(), fac(), ['L001']), isNull, reason: 'rien n’est encore délivré');
      expect(refusAnnulationEncaissement(null, fac(), ['L001']), isNull);
    });
  });
}
