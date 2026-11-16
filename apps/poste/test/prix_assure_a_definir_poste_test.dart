import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/parcours_caisse.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/modules/m2/cs_commun.dart';

/// PRIX ASSURÉ À DÉFINIR (section AJ, Direction du 16/11/2026), au poste, sur le jeu livré : un acte ASSURABLE dont la grille n'a pas de prix assuré, prescrit à un ASSURÉ (carte
/// valide, RG-09). La ligne dit « prix assuré à définir », jamais facturée au prix non assuré ; la caisse refuse SON encaissement (PRIX_ASSURE_A_DEFINIR), les autres passent ;
/// le prix assuré arrêté, la ligne se valorise en place et s'encaisse.
typedef M = Map<String, Object?>;

final jour1 = DateTime(2026, 11, 16, 10);
final jour2 = DateTime(2026, 11, 18, 9);

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu')..horloge = () => jour1;

List<M> lignes(M f) => [for (final l in f['lignes'] as List) (l as Map).cast<String, Object?>()];

void main() {
  test('assuré : ligne « prix assuré à définir » sans montant ; caisse refuse cette ligne nommée ; le prix assuré arrêté, elle se valorise et s’encaisse', () {
    final m = jeu();
    final couvertures = m.collection('couverturesAssurance').toutes;
    final pt = m.collection('patients').actives.firstWhere((p) => csVrai(p['assureur']) && !csVrai(p['personnelId']) && carteValide(p, couvertures, '2026-11-16'));
    final h = TarifsPoste.lire(m);
    // Deux actes assurables du référentiel : l'un garde son prix assuré, l'autre voit sa colonne assurée VIDÉE par une version datée (la grille ne la porte plus).
    final actes = [for (final p in h.tarifs) if (p['assurable'] == true && p['codeActe'] != null && h.instantane(p, '2026-11-16')?.etatAssure == 'montant') p];
    final vide = actes[0], plein = actes[1];
    final na = h.instantane(vide, '2026-11-16')!.na!;
    m.collection(tarCollectionVersions).ajouterSansJournal(
        {'id': '${vide['code']}@2026-11-15@90', 'code': vide['code'], 'version': 90, 'prixNonAssure': na, 'etatAssure': 'manquant', 'statut': 'valide', 'dateEffet': '2026-11-15'});
    final r = csPrescrire(StockMagasin(m, () => jour1), {
      'patientCode': pt['code'],
      'medecin': 'Dr ESSAI',
      'diagnostic': 'essai',
      'actes': [plein['codeActe'], vide['codeActe']],
    }, const SessionCs(role: 'medecin', fonction: 'medecin'));
    expect(r.refus, isEmpty, reason: 'la ligne EXISTE, elle n’est pas refusée à la prescription');
    final acteOrd = (r.ordonnance['actes'] as List).cast<M>().firstWhere((a) => a['code'] == vide['codeActe']);
    expect([acteOrd['prix'], acteOrd['prixAssureADefinir'], acteOrd['prixNonAssureInfo']], [null, true, na]);
    final l = lignes(r.facture);
    final ligne = l.firstWhere((x) => x['acteCode'] == vide['codeActe']);
    expect(ligneAssureADefinir(ligne), isTrue);
    expect(ligne['montant'], isNull, reason: 'jamais facturée au prix non assuré');
    expect(r.facture['montantTTC'], l.firstWhere((x) => x['acteCode'] == plein['codeActe'])['montant'], reason: 'le total ne porte que l’acte tarifé');
    expect(r.facture['lignesAValoriser'], 1);

    final enc = encaisserFacture(m, '${r.facture['id']}', lignes: [for (final x in l) '${x['id']}'], mode: 'especes', maintenant: jour1);
    expect(enc.lignesRefusees.single['code'], codePrixAssureADefinir);
    expect(enc.lignesRefusees.single['id'], ligne['id']);
    expect(() => encaisserFacture(m, '${r.facture['id']}', lignes: ['${ligne['id']}'], mode: 'especes', maintenant: jour1),
        throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', codePrixAssureADefinir)));

    // Le prix assuré est arrêté (version validée au 17/11) : à la caisse du 18, la ligne se valorise en place au prix assuré, parts au taux de la pièce, puis s'encaisse.
    m.collection(tarCollectionVersions).ajouterSansJournal(
        {'id': '${vide['code']}@2026-11-17@91', 'code': vide['code'], 'version': 91, 'prixNonAssure': na, 'prixAssure': 1000, 'etatAssure': 'montant', 'statut': 'valide', 'dateEffet': '2026-11-17'});
    m.horloge = () => jour2;
    final enc2 = encaisserFacture(m, '${r.facture['id']}', lignes: ['${ligne['id']}'], mode: 'especes', maintenant: jour2);
    expect(enc2.lignesValorisees, ['${ligne['id']}']);
    final apres = lignes(m.collection('factures').parId(r.facture['id'])!).firstWhere((x) => x['id'] == ligne['id']);
    expect([apres['montant'], apres['prixAssureADefinir'], apres['statutPaiement']], [1000, false, 'paye']);
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Valorisation d’une ligne au prix assuré'), isTrue);
  });

  test('non assuré : le même acte se facture à son prix non assuré, sans marque', () {
    final m = jeu();
    final pt = m.collection('patients').actives.firstWhere((p) => p['externe'] != true && !csVrai(p['assureur']) && !csVrai(p['personnelId']));
    final h = TarifsPoste.lire(m);
    final vide = [for (final p in h.tarifs) if (p['assurable'] == true && p['codeActe'] != null && h.instantane(p, '2026-11-16')?.etatAssure == 'montant') p].first;
    final na = h.instantane(vide, '2026-11-16')!.na!;
    m.collection(tarCollectionVersions).ajouterSansJournal(
        {'id': '${vide['code']}@2026-11-15@90', 'code': vide['code'], 'version': 90, 'prixNonAssure': na, 'etatAssure': 'manquant', 'statut': 'valide', 'dateEffet': '2026-11-15'});
    final r = csPrescrire(StockMagasin(m, () => jour1), {'patientCode': pt['code'], 'medecin': 'Dr ESSAI', 'actes': [vide['codeActe']]},
        const SessionCs(role: 'medecin', fonction: 'medecin'));
    final ligne = lignes(r.facture).single;
    expect([ligne['montant'], ligne['prixAssureADefinir']], [na, null]);
  });
}
