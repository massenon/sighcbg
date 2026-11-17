import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/parcours_caisse.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/modules/m2/cs_commun.dart';
import 'package:sigh_poste/shell/centre_notifications.dart';

/// PRIX ASSURÉ À DÉFINIR (section AJ, Direction du 16/11/2026, complément §7), au poste, sur le jeu livré : un acte ASSURABLE dont la grille n'a pas de prix assuré, prescrit à un
/// ASSURÉ (carte valide, RG-09). La ligne dit « prix assuré à définir », jamais facturée au prix non assuré ; l'alerte « prix manquant » (une par code, sans nom de patient) va aux
/// rôles qui peuvent MODIFIER « Tarifs et prix » ; par défaut RIEN de la facture ne s'encaisse (FACTURE_EN_ATTENTE_DE_PRIX), réglage ouvert seule la ligne est refusée
/// (PRIX_ASSURE_A_DEFINIR) ; un prix assuré daté APRÈS la pièce ne la débloque pas, daté du jour de la pièce il la valorise en place et la facture s'encaisse.
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

    // L'ALERTE « prix manquant » : UNE par code, sans nom de patient, vers les rôles qui peuvent MODIFIER « Tarifs et prix » (matrice).
    final alertes = m.collection('notifications').actives.where((n) => n['type'] == csTypeNotifPrixManquant && n['prestationCode'] == vide['codeActe']).toList();
    expect(alertes, hasLength(1));
    expect(alertes.single['poste'], posteEditeursEcran('cfg-tarifs'));
    expect('${alertes.single['libelle']} ${alertes.single['detail']}', isNot(contains('${pt['nom']}')), reason: 'aucun nom de patient');
    csPrescrire(StockMagasin(m, () => jour1), {'patientCode': pt['code'], 'medecin': 'Dr ESSAI', 'actes': [vide['codeActe']]}, const SessionCs(role: 'medecin', fonction: 'medecin'));
    expect(m.collection('notifications').actives.where((n) => n['type'] == csTypeNotifPrixManquant && n['prestationCode'] == vide['codeActe']), hasLength(1), reason: 'pas de doublon');
    final donnees = DonneesNavigation.depuisDossier();
    final roles = ['admin', 'da', 'direction', 'caissier', 'medecin', 'comptable', 'stock'];
    final editeurs = [for (final r in roles) if (donnees.matrice.peutEditer(r, 'cfg-tarifs')) r];
    expect(editeurs, isNotEmpty);
    bool recoit(String r) =>
        CentreNotifications(magasin: m, donnees: () => donnees.aChaud(m), role: () => r, horloge: () => jour1).collecter(detaille: true).any((a) => a.cle == 'notif:${alertes.single['id']}');
    expect([for (final r in roles) if (recoit(r)) r], editeurs, reason: 'lue dans la matrice (droit editer de « Tarifs et prix »), jamais écrite');

    // PAR DÉFAUT : rien de la facture ne s'encaisse, la ligne nommée avec sa cause.
    expect(
        () => encaisserFacture(m, '${r.facture['id']}', lignes: [for (final x in l) '${x['id']}'], mode: 'especes', maintenant: jour1),
        throwsA(isA<RefusCaisse>()
            .having((e) => e.code, 'code', codeFactureEnAttenteDePrix)
            .having((e) => e.lignes.single['code'], 'cause', codePrixAssureADefinir)));

    // Un prix assuré validé au 17/11 (APRÈS la pièce du 16) ne la débloque pas : le prix se lit à la date de la pièce.
    m.collection(tarCollectionVersions).ajouterSansJournal(
        {'id': '${vide['code']}@2026-11-17@91', 'code': vide['code'], 'version': 91, 'prixNonAssure': na, 'prixAssure': 1000, 'etatAssure': 'montant', 'statut': 'valide', 'dateEffet': '2026-11-17'});
    m.horloge = () => jour2;
    expect(() => encaisserFacture(m, '${r.facture['id']}', mode: 'especes', maintenant: jour2), throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', codeFactureEnAttenteDePrix)));

    // Une version datée du 16 (jour de la pièce : la date passée, décision réservée) : la ligne se valorise en place au prix assuré, parts au taux de la pièce, et la facture s'encaisse.
    m.collection(tarCollectionVersions).ajouterSansJournal({
      'id': '${vide['code']}@2026-11-16@92',
      'code': vide['code'],
      'version': 92,
      'prixNonAssure': na,
      'prixAssure': 900,
      'etatAssure': 'montant',
      'statut': 'valide',
      'dateEffet': '2026-11-16',
      'datePassee': true
    });
    final enc2 = encaisserFacture(m, '${r.facture['id']}', mode: 'especes', maintenant: jour2);
    expect(enc2.lignesValorisees, ['${ligne['id']}']);
    final apres = lignes(m.collection('factures').parId(r.facture['id'])!).firstWhere((x) => x['id'] == ligne['id']);
    expect([apres['montant'], apres['prixAssureADefinir'], apres['statutPaiement']], [900, false, 'paye']);
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Valorisation d’une ligne au prix assuré'), isTrue);
  });

  test('réglage « encaisser le reste » OUVERT : la consultation passe, la ligne au prix assuré à définir est refusée nommée', () {
    final m = jeu();
    m.collection(parCollectionParametres).inserer({
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
    final couvertures = m.collection('couverturesAssurance').toutes;
    final pt = m.collection('patients').actives.firstWhere((p) => csVrai(p['assureur']) && !csVrai(p['personnelId']) && carteValide(p, couvertures, '2026-11-16'));
    final h = TarifsPoste.lire(m);
    final actes = [for (final p in h.tarifs) if (p['assurable'] == true && p['codeActe'] != null && h.instantane(p, '2026-11-16')?.etatAssure == 'montant') p];
    final vide = actes[0], plein = actes[1];
    final na = h.instantane(vide, '2026-11-16')!.na!;
    m.collection(tarCollectionVersions).ajouterSansJournal(
        {'id': '${vide['code']}@2026-11-15@90', 'code': vide['code'], 'version': 90, 'prixNonAssure': na, 'etatAssure': 'manquant', 'statut': 'valide', 'dateEffet': '2026-11-15'});
    final r = csPrescrire(StockMagasin(m, () => jour1), {'patientCode': pt['code'], 'medecin': 'Dr ESSAI', 'actes': [plein['codeActe'], vide['codeActe']]},
        const SessionCs(role: 'medecin', fonction: 'medecin'));
    final l = lignes(r.facture);
    final ligne = l.firstWhere((x) => x['acteCode'] == vide['codeActe']);
    final enc = encaisserFacture(m, '${r.facture['id']}', lignes: [for (final x in l) '${x['id']}'], mode: 'especes', maintenant: jour1);
    expect(enc.lignesRefusees.single['code'], codePrixAssureADefinir);
    expect(enc.lignesRefusees.single['id'], ligne['id']);
    expect(() => encaisserFacture(m, '${r.facture['id']}', lignes: ['${ligne['id']}'], mode: 'especes', maintenant: jour1),
        throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', codePrixAssureADefinir)));
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
