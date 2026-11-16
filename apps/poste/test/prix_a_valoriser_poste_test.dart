import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/parcours_caisse.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/modules/m2/cs_commun.dart';
import 'package:sigh_poste/shell/centre_notifications.dart';

/// MÉDICAMENT SANS PRIX D'ACHAT : PRESCRIRE, BLOQUER LA CAISSE (Direction de Baguidi, 16/11/2026, complément §7), au poste, sur le jeu livré :
///  (1) le médecin prescrit toujours ; la ligne porte « prix à valoriser », jamais 0 (ordonnance, facture, totaux) ;
///  (2) l'alerte « prix manquant » part vers les rôles qui peuvent MODIFIER le « Référentiel produits » (droit `editer` de la matrice), une seule ouverte par article, sans nom de patient ;
///  (3) PAR DÉFAUT, rien de la facture ne s'encaisse (FACTURE_EN_ATTENTE_DE_PRIX), la pharmacie ne délivre rien ; réglage « encaisser le reste » ouvert, seule cette ligne est refusée ;
///  (4) le prix d'achat se lit à la DATE DE LA PIÈCE : un prix daté après elle ne la débloque pas ; une version DATÉE du jour de la pièce (date passée, geste réservé) la valorise
///      EN PLACE, la facture s'encaisse en entier ; l'ordonnance suit, rien d'émis n'est réécrit.
typedef M = Map<String, Object?>;

final jour1 = DateTime(2026, 11, 16, 10);
final jour2 = DateTime(2026, 11, 18, 9);

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu')..horloge = () => jour1;

List<M> lignes(M f) => [for (final l in f['lignes'] as List) (l as Map).cast<String, Object?>()];

/// Ouvre le réglage de clinique « encaisser le reste d'une facture qui a une ligne sans prix » (une version datée en base, comme la mère l'écrirait).
void ouvrirReste(Magasin m) => m.collection(parCollectionParametres).inserer({
      'id': '$cleEncaisserResteSansPrix@2026-01-01@1',
      'statut': 'actif',
      'cle': cleEncaisserResteSansPrix,
      'famille': 'caisse',
      'type': 'booleen',
      'valeur': true,
      'defaut': false,
      'dateEffet': '2026-01-01',
      'version': 1,
      'auteur': 'Essai',
    });

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

  test('(2) l’alerte va aux rôles qui peuvent MODIFIER le « Référentiel produits » (matrice), UNE seule ouverte par article, sans nom de patient ; la matrice la reroute', () {
    final w = monde();
    prescrire(w.m, w.pt, [w.sansPrix]);
    prescrire(w.m, w.pt, [w.connu, w.sansPrix]);
    final notifs = w.m.collection('notifications').actives.where((n) => n['type'] == csTypeNotifPrixAValoriser).toList();
    expect(notifs, hasLength(1), reason: 'pas de doublon pour le même article');
    expect(notifs.single['poste'], posteEditeursEcran('m6-produits'));
    expect('${notifs.single['libelle']}', contains('Amoxicilline'));
    expect('${notifs.single['libelle']} ${notifs.single['detail']}', isNot(contains('${w.pt['nom']}')), reason: 'aucun nom de patient');
    bool recoit(String r) => CentreNotifications(magasin: w.m, donnees: () => donnees.aChaud(w.m), role: () => r, horloge: () => jour1)
        .collecter(detaille: true)
        .any((a) => a.cle == 'notif:${notifs.single['id']}');
    final roles = ['stock', 'da', 'caissier', 'medecin', 'comptable', 'admin', 'reception'];
    // La liste attendue est LUE dans la matrice (droit editer de l'écran), jamais écrite ici.
    final editeurs = [for (final r in roles) if (donnees.matrice.peutEditer(r, 'm6-produits')) r];
    expect(editeurs, isNotEmpty);
    expect([for (final r in roles) if (recoit(r)) r], editeurs);
    expect(recoit('medecin'), isFalse, reason: 'le médecin ne modifie pas le référentiel produits');
    // La Direction met le référentiel en lecture seule pour le premier éditeur : l'alerte le quitte, sans une ligne de code.
    final premier = editeurs.first;
    w.m.collection('rbac').inserer({
      'role': premier,
      'statut': 'actif',
      'droitsEcrans': {
        'm6-produits': {'voir': true, 'editer': false, 'annuler': false}
      }
    });
    expect(recoit(premier), isFalse);
    // Lue, elle n'est plus ouverte : un nouvel oubli rouvre UNE alerte.
    w.m.collection('notifications').mettreAJour(notifs.single['id'], {'lue': true});
    prescrire(w.m, w.pt, [w.sansPrix]);
    expect(w.m.collection('notifications').actives.where((n) => n['type'] == csTypeNotifPrixAValoriser && n['lue'] != true), hasLength(1));
  });

  test('(3) PAR DÉFAUT, rien de la facture ne s’encaisse ni ne se délivre ; (4) un prix daté APRÈS la pièce ne la débloque pas ; daté du jour de la pièce (date passée réservée), la ligne se valorise et la facture s’encaisse EN ENTIER', () {
    final w = monde();
    final r = prescrire(w.m, w.pt, [w.connu, w.sansPrix]);
    final fid = '${r.facture['id']}';
    final l = lignes(r.facture);
    for (final visees in [
      [for (final x in l) '${x['id']}'],
      ['${l[0]['id']}'],
      ['${l[1]['id']}'],
    ]) {
      expect(
          () => encaisserFacture(w.m, fid, lignes: visees, maintenant: jour1),
          throwsA(isA<RefusCaisse>()
              .having((e) => e.code, 'code', codeFactureEnAttenteDePrix)
              .having((e) => e.motif, 'motif', contains('Amoxicilline'))
              .having((e) => e.lignes.single['id'], 'ligne nommée', l[1]['id'])));
    }
    final f0 = w.m.collection('factures').parId(fid)!;
    expect(f0['statutPaiement'], 'impayee', reason: 'rien n’est écrit');
    expect(lignes(f0).every((x) => x['statutPaiement'] != 'paye'), isTrue);
    expect(w.m.collection('taches').actives.firstWhere((t) => t['factureId'] == fid && t['type'] == 'dispensation')['statut'], 'bloque',
        reason: 'la pharmacie ne délivre rien tant que la facture n’est pas encaissée');
    final etats0 = lignesDelivrance(w.m.collection('ordonnances').parId(r.ordonnance['id'])!, f0);
    expect(etats0.where((e) => e.delivrable), isEmpty, reason: 'aucune ligne délivrable');

    // Le gestionnaire de stock propose un prix d'achat le 18, la DAF dit Oui : la version entre en vigueur le 18, APRÈS la pièce du 16 — elle ne la débloque PAS (repli retiré).
    final stock = TarifsPoste(w.m, role: 'stock', auteur: () => 'Gestionnaire', peutProposerPrixAchat: true, horloge: () => jour2);
    final prop = stock.proposerPrixAchat(DemandeProduit(code: 'AMOX-VAL', prixAchat: 450, dateEffet: tarIso(jour2), motif: 'Premier prix d’achat'));
    expect(prop.ok, isTrue, reason: '${prop.refus?.code} ${prop.refus?.motif}');
    final da = TarifsPoste(w.m, role: 'da', auteur: () => 'DAF', peutEditerEcran: true, peutProposerPrixAchat: true, horloge: () => jour2);
    expect(da.decider('${prop.version!['id']}', 'oui', motif: 'Prix fournisseur').ok, isTrue);
    w.m.horloge = () => jour2;
    expect(() => encaisserFacture(w.m, fid, maintenant: jour2), throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', codeFactureEnAttenteDePrix)),
        reason: 'le prix du 18 ne vaut pas pour la pièce du 16');
    expect(w.m.collection('factures').parId(fid)!['lignesAValoriser'], 1, reason: 'la valorisation tentée est défaite avec le refus');

    // Le guide de l'écran de prix dit QUELLE date débloque : au plus tard le jour de la pièce, une date passée (décision réservée).
    final guide = guidePiecesEnAttenteDePrix(piecesEnAttenteDePrix(w.m.collection('factures').actives, produitId: w.sansPrix['id']), tarIso(jour2));
    expect(guide, allOf(contains('${r.facture['numero']}'), contains('16/11/2026'), contains('Dater un prix dans le passé')));

    // La DAF (geste « dater dans le passé ») pose une version datée du 16, jour de la pièce, avec motif : la ligne se valorise à ce prix et la facture s'encaisse EN ENTIER.
    expect(da.peutDaterPasse, isTrue, reason: 'la DAF détient le geste réservé d’origine');
    final passe = da.proposerPrixAchat(DemandeProduit(code: 'AMOX-VAL', prixAchat: 420, dateEffet: tarIso(jour1), motif: 'Prix à la date de la pièce', datePassee: true, valider: true));
    expect(passe.ok, isTrue, reason: '${passe.refus?.code} ${passe.refus?.motif}');
    final c2 = encaisserFacture(w.m, fid, maintenant: jour2);
    expect(c2.lignesValorisees, ['${l[1]['id']}']);
    expect(c2.lignesRefusees, isEmpty);
    expect(c2.lignesReglees, ['${l[0]['id']}', '${l[1]['id']}']);
    final f2 = w.m.collection('factures').parId(fid)!;
    final v = lignes(f2)[1];
    expect([v['prixUnitaire'], v['montant'], v['statutPaiement']], [420, 840, 'paye'], reason: 'RG-02 : 2 × 420, le prix EN VIGUEUR à la date de la pièce');
    expect((v['valorisation'] as Map)['regle'], 'a_la_date');
    expect([f2['numero'], f2['date']], [r.facture['numero'], r.facture['date']], reason: 'la pièce est COMPLÉTÉE, jamais renumérotée');
    expect(f2['statutPaiement'], 'soldee');
    expect(f2['lignesAValoriser'], 0);
    final ord = w.m.collection('ordonnances').parId(r.ordonnance['id'])!;
    expect((ord['medicaments'] as List).cast<M>()[1]['prix'], 420);
    expect(w.m.collection('taches').actives.firstWhere((t) => t['factureId'] == fid && t['type'] == 'dispensation')['statut'], 'en_attente');
    expect(w.m.collection('audit').toutes.any((a) => '${a['action']}'.contains('Valorisation d’une ligne')), isTrue, reason: 'RG-12');
    c2.annuler();
    expect(ligneAValoriser(lignes(w.m.collection('factures').parId(fid)!)[1]), isTrue, reason: 'annuler défait aussi la valorisation');
  });

  test('(3 bis) réglage « encaisser le reste » OUVERT : la caisse encaisse le reste, refuse la ligne nommée, et la pharmacie délivre ligne par ligne (comportement v21)', () {
    final w = monde();
    ouvrirReste(w.m);
    final r = prescrire(w.m, w.pt, [w.connu, w.sansPrix]);
    final fid = '${r.facture['id']}';
    final l = lignes(r.facture);
    final c1 = encaisserFacture(w.m, fid, lignes: [for (final x in l) '${x['id']}'], maintenant: jour1);
    expect(c1.lignesReglees, ['${l[0]['id']}']);
    expect(c1.lignesRefusees.single['code'], codePrixAValoriser);
    final f1 = w.m.collection('factures').parId(fid)!;
    expect(f1['statutPaiement'], 'partielle', reason: 'jamais soldée avec une ligne sans montant');
    expect(f1['numeroMecef'], isNull);
    expect(w.m.collection('taches').actives.firstWhere((t) => t['factureId'] == fid && t['type'] == 'dispensation')['statut'], 'en_attente');
    expect(c1.debloquees, ['dispensation']);
    final etats = lignesDelivrance(w.m.collection('ordonnances').parId(r.ordonnance['id'])!, f1);
    expect(etats.map((e) => e.etat), [EtatLigneDelivrance.delivrable, EtatLigneDelivrance.prixAValoriser]);
    expect(() => encaisserFacture(w.m, fid, lignes: ['${l[1]['id']}'], maintenant: jour1), throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', codePrixAValoriser)));
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
