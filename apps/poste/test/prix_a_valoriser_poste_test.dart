import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/parcours_caisse.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/modules/m2/cs_commun.dart';
import 'package:sigh_poste/shell/centre_notifications.dart';

/// MÉDICAMENT SANS PRIX D'ACHAT : PRESCRIRE, BLOQUER LA CAISSE (Direction de Baguidi, 16/11/2026), au poste, sur le jeu livré :
///  (1) le médecin prescrit toujours ; la ligne porte « prix à valoriser », jamais 0 (ordonnance, facture, totaux) ;
///  (2) l'alerte part vers qui fixe le prix d'achat (le geste `tarif_proposer_achat`, lu dans la matrice), une seule ouverte par article ;
///  (3) à la caisse, seule cette ligne est refusée (PRIX_A_VALORISER), les autres s'encaissent ; la pièce reste ouverte ;
///  (4) le prix fixé, la ligne se valorise EN PLACE au prix retenu à la date de la pièce et s'encaisse ; l'ordonnance suit, rien d'émis n'est réécrit.
typedef M = Map<String, Object?>;

final jour1 = DateTime(2026, 11, 16, 10);
final jour2 = DateTime(2026, 11, 18, 9);

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu')..horloge = () => jour1;

List<M> lignes(M f) => [for (final l in f['lignes'] as List) (l as Map).cast<String, Object?>()];

void main() {
  final donnees = DonneesNavigation.depuisDossier();

  ({Magasin m, M pt, M connu, M sansPrix}) monde() {
    final m = jeu();
    final pt = m.collection('patients').actives.firstWhere((p) => p['externe'] != true && !csVrai(p['assureur']) && !csVrai(p['personnelId']));
    final connu = m.collection('produits').actives.firstWhere((p) => p['categorie'] == 'medicament' && (p['prixAchat'] as num? ?? 0) > 0);
    // Un article CONNU mais « à valoriser » : sa version 1 de prix d'achat est `manquant` (reprise sans prix), comme un article repris du Grand Stock.
    final sansPrix = m.collection('produits').inserer({
      'code': 'AMOX-VAL',
      'designation': 'Amoxicilline 1 g (à valoriser)',
      'categorie': 'medicament',
      'unite': 'boîte',
      'stock': 40,
      'stockDetail': 40,
      'statut': 'actif',
    }, prefixe: 'PRD').fiche;
    TarifsPoste.assurerProduits(m);
    expect(TarifsPoste.produitsAValoriser(m, aujourdhui: jour1).map((x) => x.produit['code']), contains('AMOX-VAL'));
    return (m: m, pt: pt, connu: connu, sansPrix: sansPrix);
  }

  ResultatPrescription prescrire(Magasin m, M pt, List<M> produits) => csPrescrire(
      StockMagasin(m, () => jour1),
      {
        'patientCode': pt['code'],
        'medecin': 'Dr ESSAI',
        'diagnostic': 'essai',
        'medicaments': [for (final p in produits) {'produitId': p['id'], 'quantite': 2, 'posologie': '1 x 2', 'duree': '5 j'}],
      },
      const SessionCs(role: 'medecin', fonction: 'medecin'));

  test('(1) le médecin PRESCRIT ; la ligne porte « prix à valoriser », jamais 0 ; aucun refus TARIF_A_VALIDER', () {
    final w = monde();
    final r = prescrire(w.m, w.pt, [w.connu, w.sansPrix]);
    expect(r.refus, isEmpty, reason: 'le refus de la v20 est retiré pour les médicaments');
    expect(r.aValoriser.single['produitId'], w.sansPrix['id']);
    final meds = (r.ordonnance['medicaments'] as List).cast<M>();
    expect(meds, hasLength(2));
    expect(meds[1]['prixAValoriser'], isTrue);
    expect([meds[1]['prix'], meds[1]['total']], [null, null]);
    final l = lignes(r.facture);
    expect(l, hasLength(2));
    expect(ligneAValoriser(l[1]), isTrue);
    expect([for (final x in l) x['montant']].where((x) => x == 0), isEmpty, reason: 'aucune ligne à 0');
    expect(r.facture['montantTTC'], l[0]['montant'], reason: 'le total ne porte que la ligne valorisée');
    expect(r.facture['lignesAValoriser'], 1);
    expect(r.ordonnance['lignesAValoriser'], 1);
  });

  test('(2) l’alerte va aux rôles qui détiennent « proposer un prix d’achat » (matrice), UNE seule ouverte par article ; une décision la reroute', () {
    final w = monde();
    prescrire(w.m, w.pt, [w.sansPrix]);
    prescrire(w.m, w.pt, [w.connu, w.sansPrix]);
    final notifs = w.m.collection('notifications').actives.where((n) => n['type'] == csTypeNotifPrixAValoriser).toList();
    expect(notifs, hasLength(1), reason: 'pas de doublon pour le même article');
    expect(notifs.single['poste'], 'geste:$gesteProposerPrixAchat');
    expect('${notifs.single['libelle']}', contains('Amoxicilline'));
    bool recoit(String r) => CentreNotifications(magasin: w.m, donnees: () => donnees, role: () => r, horloge: () => jour1)
        .collecter(detaille: true)
        .any((a) => a.cle == 'notif:${notifs.single['id']}');
    expect([for (final r in ['stock', 'da', 'caissier', 'medecin', 'comptable']) if (recoit(r)) r], ['stock', 'da']);
    // La Direction retire le geste au gestionnaire de stock et l'accorde au comptable : l'alerte suit la matrice, sans une ligne de code.
    w.m.collection('rbac').inserer({'role': 'comptable', 'statut': 'actif', 'droitsGestes': {gesteProposerPrixAchat: true}});
    w.m.collection('rbac').inserer({'role': 'stock', 'statut': 'actif', 'droitsGestes': {gesteProposerPrixAchat: false}});
    expect(recoit('stock'), isFalse);
    expect(recoit('comptable'), donnees.matrice.peutVoir('comptable', 'm6-produits'), reason: 'reçue si le comptable lit l’écran du geste');
    // Lue, elle n'est plus ouverte : un nouvel oubli rouvre UNE alerte.
    w.m.collection('notifications').mettreAJour(notifs.single['id'], {'lue': true});
    prescrire(w.m, w.pt, [w.sansPrix]);
    expect(w.m.collection('notifications').actives.where((n) => n['type'] == csTypeNotifPrixAValoriser && n['lue'] != true), hasLength(1));
  });

  test('(3) puis (4) : la caisse encaisse le reste et REFUSE la ligne nommée ; le prix fixé, la ligne se valorise EN PLACE et s’encaisse', () {
    final w = monde();
    final r = prescrire(w.m, w.pt, [w.connu, w.sansPrix]);
    final fid = '${r.facture['id']}';
    final l = lignes(r.facture);
    final c1 = encaisserFacture(w.m, fid, lignes: [for (final x in l) '${x['id']}'], maintenant: jour1);
    expect(c1.lignesReglees, ['${l[0]['id']}']);
    expect(c1.lignesRefusees.single['code'], codePrixAValoriser);
    final f1 = w.m.collection('factures').parId(fid)!;
    expect(f1['statutPaiement'], 'partielle', reason: 'jamais soldée avec une ligne sans montant');
    expect(f1['numeroMecef'], isNull);
    // DÉLIVRANCE LIGNE PAR LIGNE (Direction de Baguidi, 16/11/2026, E3300) : la ligne RÉGLÉE ouvre la pharmacie ; la ligne au prix à valoriser reste en attente, nommée.
    expect(w.m.collection('taches').actives.firstWhere((t) => t['factureId'] == fid && t['type'] == 'dispensation')['statut'], 'en_attente',
        reason: 'la ligne réglée se délivre sans attendre la ligne au prix à valoriser');
    expect(c1.debloquees, ['dispensation']);
    final etats = lignesDelivrance(w.m.collection('ordonnances').parId(r.ordonnance['id'])!, f1);
    expect(etats.map((e) => e.etat), [EtatLigneDelivrance.delivrable, EtatLigneDelivrance.prixAValoriser]);
    // Seule la ligne sans prix : refus nommé, rien n'est écrit.
    expect(() => encaisserFacture(w.m, fid, lignes: ['${l[1]['id']}'], maintenant: jour1), throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', codePrixAValoriser)));
    final avant = w.m.collection('factures').parId(fid)!;
    expect(lignes(avant)[0], lignes(f1)[0]);

    // Le gestionnaire de stock propose un prix d'achat le 18, la DAF dit Oui : la version entre en vigueur le 18, APRÈS la pièce du 16.
    final stock = TarifsPoste(w.m, role: 'stock', auteur: () => 'Gestionnaire', peutProposerPrixAchat: true, horloge: () => jour2);
    final prop = stock.proposerPrixAchat(DemandeProduit(code: 'AMOX-VAL', prixAchat: 450, dateEffet: tarIso(jour2), motif: 'Premier prix d’achat'));
    expect(prop.ok, isTrue, reason: '${prop.refus?.code} ${prop.refus?.motif}');
    final da = TarifsPoste(w.m, role: 'da', auteur: () => 'DAF', peutEditerEcran: true, horloge: () => jour2);
    expect(da.decider('${prop.version!['id']}', 'oui', motif: 'Prix fournisseur').ok, isTrue);

    final c2 = encaisserFacture(w.m, fid, lignes: ['${l[1]['id']}'], maintenant: jour2);
    expect(c2.lignesValorisees, ['${l[1]['id']}']);
    expect(c2.lignesRefusees, isEmpty);
    expect(c2.montantRegle, 900, reason: 'RG-02 : 2 × 450, le prix d’achat sans marge');
    final f2 = w.m.collection('factures').parId(fid)!;
    final v = lignes(f2)[1];
    expect([v['prixUnitaire'], v['montant'], v['statutPaiement']], [450, 900, 'paye']);
    expect((v['valorisation'] as Map)['regle'], 'premiere_valorisation');
    expect(lignes(f2)[0], lignes(f1)[0], reason: 'la ligne déjà réglée ne bouge pas');
    expect([f2['numero'], f2['date']], [f1['numero'], f1['date']]);
    expect(f2['statutPaiement'], 'soldee');
    expect(f2['lignesAValoriser'], 0);
    // L'ordonnance suit (la pharmacie imprime le bon de sortie au prix retenu, jamais à 0) ; la délivrance est débloquée au solde.
    final ord = w.m.collection('ordonnances').parId(r.ordonnance['id'])!;
    expect((ord['medicaments'] as List).cast<M>()[1]['prix'], 450);
    expect(w.m.collection('taches').actives.firstWhere((t) => t['factureId'] == fid && t['type'] == 'dispensation')['statut'], 'en_attente');
    expect(w.m.collection('audit').toutes.any((a) => '${a['action']}'.contains('Valorisation d’une ligne')), isTrue, reason: 'RG-12');
    // Annuler l'encaissement défait AUSSI la valorisation : la ligne redevient « prix à valoriser ».
    c2.annuler();
    expect(ligneAValoriser(lignes(w.m.collection('factures').parId(fid)!)[1]), isTrue);
  });
  test('SÉPARATION : les notifications de la « caisse » et du « stock » suivent les gestes de la fiche, jamais un nom de rôle', () {
    final m = jeu();
    m.collection('notifications').inserer({'type': 'encaissement', 'poste': 'caisse', 'libelle': 'À encaisser', 'lue': false, 'statut': 'actif'});
    m.collection('notifications').inserer({'type': 'besoin_accorde', 'poste': 'stock', 'libelle': 'Besoin accordé', 'lue': false, 'statut': 'actif'});
    Set<String> recues(String r) => {
          for (final a in CentreNotifications(magasin: m, donnees: () => donnees.aChaud(m), role: () => r, horloge: () => jour1).collecter(detaille: true))
            if (a.source == 'poste' && const {'À encaisser', 'Besoin accordé'}.contains(a.titre)) a.titre
        };
    // Aujourd'hui (aucune décision) : la caisse va au Caissier, le stock au gestionnaire, au pharmacien et à la DAF (les listes d'avant).
    expect(recues('caissier'), {'À encaisser'});
    expect(recues('stock'), {'Besoin accordé'});
    expect(recues('pharmacien'), {'Besoin accordé'});
    expect(recues('da'), {'Besoin accordé'});
    // La Direction sépare : le pharmacien perd le stock et prend… rien de la caisse ; le caissier prend aussi le stock. Des cases, aucun code.
    m.collection('rbac').inserer({'role': 'caissier', 'statut': 'actif', 'droitsGestes': {gesteAlertesStock: true}});
    m.collection('rbac').inserer({'role': 'pharmacien', 'statut': 'actif', 'droitsGestes': {gesteAlertesStock: false}});
    expect(recues('caissier'), {'À encaisser', 'Besoin accordé'});
    expect(recues('pharmacien'), isEmpty);
  });
}
