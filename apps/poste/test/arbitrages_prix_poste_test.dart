import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/modules/m2/cs_commun.dart';

/// DÉCISIONS DE LA DIRECTION DU 16/11/2026, au poste :
///  (3) un prix en DOUBLON (`CERT-APT`, et tout autre code) se range à l'arbitrage ; « Garder celui-ci » archive l'autre avec motif (RG-14) ;
///  (4) une analyse ou un acte SANS PRIX EN VIGUEUR est refusé à la prescription (`TARIF_A_VALIDER`), sans bloquer le reste de l'ordonnance ;
///  (5) une analyse CRÉÉE au catalogue ouvre son identité de prix « sans prix, à valider » et prévient la DAF.
typedef M = Map<String, Object?>;

final jour = DateTime(2026, 11, 16, 10);

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu')..horloge = () => jour;

TarifsPoste poste(Magasin m, {String role = 'direction', bool fileul = false, bool peutEditer = true}) =>
    TarifsPoste(m, role: role, auteur: () => 'LA DIRECTION', fileul: fileul, peutEditerEcran: peutEditer, horloge: () => jour);

num? caisse(Magasin m, String code) => TarifsPoste.prixGrille(m, code, aujourdhui: jour).montant;

void main() {
  group('(3) prix en doublon : l’arbitrage de la Direction', () {
    test('CERT-APT est proposé à l’arbitrage avec ses deux candidats ; la caisse lit la première ligne (7 000), sans blocage', () {
      final m = jeu();
      final d = TarifsPoste.doublonsPrix(m);
      final cert = d.where((x) => x.code == 'CERT-APT').single;
      expect(cert.collection, 'catalogueTarifs');
      expect([for (final f in cert.candidats) f['id']], ['TAR147', 'TAR152']);
      expect(caisse(m, 'CERT-APT'), 7000, reason: 'tant que la Direction n’a pas choisi, la première ligne : aucun prix facturé ne change');
    });

    test('la détection est GÉNÉRIQUE : tout code en double aux prix différents, jamais deux lignes de même prix', () {
      final m = jeu();
      final avant = TarifsPoste.doublonsPrix(m).length;
      final acte = m.collection('actes').actives.first;
      m.collection('actes').inserer({...acte, 'id': 'ACT-DBL', 'prix': (acte['prix'] as num) + 100, 'prixNonAssure': ((acte['prixNonAssure'] ?? acte['prix']) as num) + 100});
      expect(TarifsPoste.doublonsPrix(m).length, avant + 1);
      expect(TarifsPoste.doublonsPrix(m).any((x) => x.collection == 'actes' && x.code == acte['code']), isTrue);
      final m2 = jeu();
      m2.collection('actes').inserer({...m2.collection('actes').actives.first, 'id': 'ACT-MEME'});
      expect(TarifsPoste.doublonsPrix(m2).length, avant, reason: 'même code, même prix : rien à choisir');
    });

    test('refus nommés : geste manquant, motif absent, candidat inconnu, fileul ; rien n’est écrit', () {
      final m = jeu();
      final d = TarifsPoste.doublonsPrix(m).firstWhere((x) => x.code == 'CERT-APT');
      expect(poste(m, role: 'caissier').arbitrerDoublon(d, 'TAR152', 'Prix du barème').refus!.code, 'ARBITRAGE_RESERVE');
      expect(poste(m).arbitrerDoublon(d, 'TAR152', '  ').refus!.code, 'MOTIF_REQUIS');
      expect(poste(m).arbitrerDoublon(d, 'ZZZ', 'x').refus!.code, 'CANDIDAT_INCONNU');
      expect(poste(m, fileul: true).arbitrerDoublon(d, 'TAR152', 'x').refus!.code, 'CONFIGURATION_DE_LA_MERE');
      expect(m.collection('catalogueTarifs').parId('TAR147')!['statut'], 'actif');
      expect(m.collection('catalogueTarifs').parId('TAR152')!['statut'], 'actif');
    });

    test('garder la ligne à 5 000 : la caisse lit 5 000 aujourd’hui, l’autre est ARCHIVÉE avec motif (jamais supprimée), journalisé', () {
      final m = jeu();
      final d = TarifsPoste.doublonsPrix(m).firstWhere((x) => x.code == 'CERT-APT');
      final versions = m.collection('versionsTarif').toutes.length;
      final r = poste(m).arbitrerDoublon(d, 'TAR152', 'Tarif de la médecine du travail confirmé');
      expect(r.ok, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
      expect(caisse(m, 'CERT-APT'), 5000);
      expect(m.collection('versionsTarif').toutes.length, versions + 1, reason: 'une version AJOUTÉE, l’ancienne reste lisible');
      final v7000 = m.collection('versionsTarif').toutes.firstWhere((v) => v['id'] == 'CERT-APT@origine@1');
      expect(v7000['prixNonAssure'], 7000, reason: 'une pièce émise à 7 000 garde son prix');
      final a = m.collection('catalogueTarifs').parId('TAR147')!;
      expect(a['statut'], 'archive');
      expect(a['motifArchivage'], 'Tarif de la médecine du travail confirmé');
      expect(a['archivePar'], 'LA DIRECTION');
      expect(m.collection('catalogueTarifs').toutes.where((x) => x['code'] == 'CERT-APT'), hasLength(2), reason: 'RG-14 : rien n’est supprimé');
      expect(TarifsPoste.doublonsPrix(m).where((x) => x.code == 'CERT-APT'), isEmpty);
      expect(m.collection('audit').toutes.any((x) => '${x['action']}'.contains('Arbitrage d’un prix en doublon')), isTrue);
      expect(TarifsPoste.parites(m, jour), isEmpty, reason: 'la projection de lecture suit le référentiel');
      expect(m.collection('catalogueTarifs').parId('TAR152')!['prixNonAssure'], 5000);
    });

    test('garder la ligne à 7 000 : aucune version ajoutée (le référentiel la lit déjà), l’autre est archivée', () {
      final m = jeu();
      final d = TarifsPoste.doublonsPrix(m).firstWhere((x) => x.code == 'CERT-APT');
      final versions = m.collection('versionsTarif').toutes.length;
      expect(poste(m).arbitrerDoublon(d, 'TAR147', 'Prix hérité confirmé').ok, isTrue);
      expect(m.collection('versionsTarif').toutes.length, versions);
      expect(caisse(m, 'CERT-APT'), 7000);
      expect(m.collection('catalogueTarifs').parId('TAR152')!['statut'], 'archive');
      expect(m.collection('catalogueTarifs').parId('TAR147')!['statut'], 'actif');
    });

    test('un refus du moteur de prix (proposition déjà en attente) ne laisse RIEN d’écrit : aucune ligne archivée', () {
      final m = jeu();
      final p = poste(m);
      expect(p.proposer(const DemandeProposition(code: 'CERT-APT', prixNonAssure: 8000, prixAssure: 8000, dateEffet: '2026-12-01', motif: 'Essai')).ok, isTrue);
      final d = TarifsPoste.doublonsPrix(m).firstWhere((x) => x.code == 'CERT-APT');
      final r = p.arbitrerDoublon(d, 'TAR152', 'Prix confirmé');
      expect(r.refus!.code, 'CHANGEMENT_EN_ATTENTE');
      expect(m.collection('catalogueTarifs').parId('TAR147')!['statut'], 'actif');
      expect(caisse(m, 'CERT-APT'), 7000);
    });
  });

  group('(Q18) la troisième issue : « ce sont deux prestations distinctes »', () {
    TarDoublonPrix cert(Magasin m) => TarifsPoste.doublonsPrix(m).firstWhere((x) => x.code == 'CERT-APT');

    test('le code reste à la ligne que la caisse lit, l’autre reçoit CERT-APT2 en PROPOSITION À VALIDER ; aucun prix, aucune pièce, aucune archive ne bouge', () {
      final m = jeu();
      final factures = [for (final f in m.collection('factures').toutes) '$f'];
      final versionsAvant = m.collection('versionsTarif').toutes.length;
      final apercu = poste(m).apercuDistincts(cert(m));
      expect(apercu.single.nouveauCode, 'CERT-APT2');
      final r = poste(m).arbitrerDistincts(cert(m), 'Médecine du travail : autre prestation');
      expect(r.ok, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
      expect(caisse(m, 'CERT-APT'), 7000, reason: 'le code reste à la prestation que la caisse lisait, au même prix');
      expect(TarifsPoste.prixGrille(m, 'CERT-APT2', aujourdhui: jour).facturable, isFalse, reason: 'proposition à valider : la caisse ne le lit pas, jamais un zéro');
      final p = TarifsPoste.lire(m).parCode['CERT-APT2']!;
      expect([p['distinctDe'], p['propositionAValider'], p['famille'], p['codeGrille']], ['CERT-APT', true, 'CERTIFICAT', 'CERT-APT2']);
      final v = TarifsPoste.lire(m).versionsDe('CERT-APT2').single;
      expect([v['statut'], v['prixNonAssure'], v['prixAssure']], ['propose', 5000, 5000], reason: 'le prix PROPRE de la ligne, proposé, jamais validé par ce geste');
      expect(m.collection('versionsTarif').toutes.length, versionsAvant + 1);
      expect(TarifsPoste.lire(m).versionsDe('CERT-APT').map((x) => x['prixNonAssure']).toSet(), {7000});
      expect(m.collection('catalogueTarifs').toutes.where((x) => x['statut'] == 'archive' && '${x['code']}'.startsWith('CERT-')), isEmpty, reason: 'rien n’est archivé');
      expect(m.collection('catalogueTarifs').parId('TAR152')!['code'], 'CERT-APT2');
      expect(m.collection('catalogueTarifs').parId('TAR152')!['codeAnterieur'], 'CERT-APT');
      expect(TarifsPoste.doublonsPrix(m).where((x) => x.code == 'CERT-APT'), isEmpty);
      expect([for (final f in m.collection('factures').toutes) '$f'], factures, reason: 'aucune facture déjà émise n’est réécrite');
      expect(m.collection('audit').toutes.any((x) => '${x['action']}'.contains('deux prestations distinctes')), isTrue);
      final a = TarifsPoste.distinctsAValider(m);
      expect([a.single.prestation['code'], a.single.etat], ['CERT-APT2', 'propose'], reason: 'visible au centre des validations');
      expect(TarifsPoste.parites(m, jour), isEmpty);
    });

    test('le Oui de la Direction (circuit ordinaire) met le nouveau code en vigueur ; la ligne quitte la liste à valider', () {
      final m = jeu();
      expect(poste(m).arbitrerDistincts(cert(m), 'Deux prestations').ok, isTrue);
      final vid = '${TarifsPoste.lire(m).versionsDe('CERT-APT2').single['id']}';
      final d = poste(m).decider(vid, 'oui');
      expect(d.ok, isTrue, reason: '${d.refus?.code} ${d.refus?.motif}');
      expect(caisse(m, 'CERT-APT2'), 5000);
      expect(caisse(m, 'CERT-APT'), 7000);
      expect(TarifsPoste.distinctsAValider(m), isEmpty);
    });

    test('refus nommés : geste réservé, motif, code déjà pris ; le doublon résolu ne se rejoue pas ; rien n’est écrit sur un refus', () {
      final m = jeu();
      expect(poste(m, role: 'caissier').arbitrerDistincts(cert(m), 'x').refus!.code, 'ARBITRAGE_RESERVE');
      expect(poste(m).arbitrerDistincts(cert(m), ' ').refus!.code, 'MOTIF_REQUIS');
      expect(poste(m).arbitrerDistincts(cert(m), 'x', codesDemandes: {'TAR152': 'CERT-DEC'}).refus!.code, 'CODE_EXISTANT');
      expect(poste(m).arbitrerDistincts(cert(m), 'x', codesDemandes: {'TAR152': 'CERT-APT'}).refus!.code, 'CODE_EXISTANT');
      expect(m.collection('catalogueTarifs').parId('TAR152')!['code'], 'CERT-APT');
      final d = cert(m);
      expect(poste(m).arbitrerDistincts(d, 'Deux prestations').ok, isTrue);
      expect(poste(m).arbitrerDistincts(d, 'Deux prestations').refus!.code, 'DOUBLON_RESOLU');
      // Un code déjà donné ne se redonne pas : une seconde clinique de la famille prend le rang suivant.
      expect(TarifsPoste.codesPris(m), contains('CERT-APT2'));
    });

    test('un FILEUL ne décide pas : il DÉPOSE ; la mère applique sous le rôle de l’auteur, avec les mêmes contrôles', () {
      final m = jeu();
      final dep = poste(m, fileul: true).arbitrerDistincts(cert(m), 'Deux prestations');
      expect(dep.depose, isTrue);
      expect(m.collection('catalogueTarifs').parId('TAR152')!['code'], 'CERT-APT', reason: 'rien n’est écrit chez le fileul');
      expect(poste(m, role: 'caissier', fileul: true).arbitrerDistincts(cert(m), 'x').refus!.code, 'ARBITRAGE_RESERVE');
      expect(m.collection('propositionsTarif').toutes.where((x) => x['genre'] == 'distincts'), hasLength(1));
      expect(poste(m).appliquerDemandes(), 1);
      final verdict = m.collection('propositionsTarif').toutes.firstWhere((x) => x['genre'] == 'distincts');
      expect(verdict['etat'], 'appliquee', reason: '${verdict['resultatCode']}');
      expect(m.collection('catalogueTarifs').parId('TAR152')!['code'], 'CERT-APT2');
      expect(TarifsPoste.distinctsAValider(m), hasLength(1));
      // Rejoué : la demande appliquée ne s'applique pas deux fois.
      expect(poste(m).appliquerDemandes(), 0);
    });
  });

  group('(5) une analyse créée au catalogue ouvre son prix « sans prix, à valider »', () {
    Map<String, Object?> nouvelle() => {'id': 'ANA-NEUVE', 'code': 'NEO-TEST', 'designation': 'Analyse de test', 'categorie': 'Biochimie', 'echantillon': 'Sang', 'delai': '2 h', 'statut': 'Actif', 'n': 99};

    test('l’identité de prix est ouverte SANS version, la DAF est prévenue une seule fois ; rejouée, rien ne change', () {
      final m = jeu();
      expect(TarifsPoste.lire(m).parAnalyse['NEO-TEST'], isNull);
      m.collection('analyses').inserer(nouvelle());
      final ouverts = TarifsPoste.assurerAnalyses(m, horloge: () => jour);
      expect(ouverts, ['NEO-TEST']);
      final p = TarifsPoste.lire(m).parAnalyse['NEO-TEST']!;
      expect(p['famille'], 'LABO');
      expect(p['codeAnalyse'], 'NEO-TEST');
      expect(TarifsPoste.lire(m).versionsDe('NEO-TEST'), isEmpty, reason: 'aucune version : « sans prix en vigueur », jamais un zéro');
      final n = m.collection('notifications').toutes.where((x) => x['type'] == 'prix_a_tarifer' && x['reference'] == 'NEO-TEST').toList();
      expect(n, hasLength(1));
      expect(n.single['poste'], 'da');
      expect(TarifsPoste.assurerAnalyses(m, horloge: () => jour), isEmpty);
      expect(m.collection('notifications').toutes.where((x) => x['type'] == 'prix_a_tarifer'), hasLength(1));
      expect(m.collection(tarCollectionTarifs).toutes.where((x) => x['code'] == 'NEO-TEST'), hasLength(1));
    });

    test('une analyse déjà dotée (les 48 du catalogue) n’est pas touchée', () {
      final m = jeu();
      expect(TarifsPoste.assurerAnalyses(m, horloge: () => jour), isEmpty);
    });

    test('non facturable jusqu’au Oui : refus nommé, le reste de l’ordonnance passe ; après le Oui elle se facture', () {
      final m = jeu();
      m.collection('analyses').inserer(nouvelle());
      TarifsPoste.assurerAnalyses(m, horloge: () => jour);
      final s = StockMagasin(m, () => jour);
      final pt = m.collection('patients').actives.firstWhere((p) => p['externe'] != true);
      final codeValide = [for (final p in TarifsPoste.lire(m).tarifs) if (p['codeAnalyse'] != null && p['codeAnalyse'] != 'NEO-TEST') '${p['codeAnalyse']}'].first;
      const session = SessionCs(role: 'admin', fonction: 'direction');
      final r = csPrescrire(s, {'patientCode': pt['code'], 'medecin': 'TEST', 'diagnostic': 'essai', 'analyses': [codeValide, 'NEO-TEST']}, session);
      expect(r.refus, hasLength(1));
      expect(r.refus.single['codeErreur'], csCodeTarifAValider);
      expect(r.refus.single['code'], 'NEO-TEST');
      expect('${r.refus.single['motif']}', startsWith('tarif à valider'));
      expect([for (final a in (r.ordonnance['analyses'] as List).cast<M>()) a['code']], [codeValide], reason: 'la ligne valide passe, aucune ligne à 0');
      expect([for (final l in (r.facture['lignes'] as List).cast<M>()) l['montant']].where((x) => x == 0), isEmpty);
      // Seule à être prescrite : refus de la prescription, nommé, rien d'écrit.
      final ord = m.collection('ordonnances').toutes.length;
      try {
        csPrescrire(s, {'patientCode': pt['code'], 'medecin': 'TEST', 'diagnostic': 'essai', 'analyses': ['NEO-TEST']}, session);
        fail('refus attendu');
      } on RefusCs catch (e) {
        expect(e.code, csCodeTarifAValider);
      }
      expect(m.collection('ordonnances').toutes.length, ord);
      // Le Oui de la DAF : proposition validée en un geste, l'analyse devient facturable.
      final i = poste(m, role: 'da').proposer(const DemandeProposition(code: 'NEO-TEST', prixNonAssure: 4500, prixAssure: 4500, etatAssure: 'montant', dateEffet: '2026-11-16', motif: 'Tarif arrêté', valider: true));
      expect(i.ok, isTrue, reason: '${i.refus?.code} ${i.refus?.motif}');
      final r2 = csPrescrire(s, {'patientCode': pt['code'], 'medecin': 'TEST', 'diagnostic': 'essai', 'analyses': ['NEO-TEST']}, session);
      expect(r2.refus, isEmpty);
      expect((r2.ordonnance['analyses'] as List).cast<M>().single['prix'], 4500);
    });
  });

  group('(4) l’acte ou l’analyse sans prix : refus nommé, jamais un zéro', () {
    test('un code d’acte inconnu du référentiel de prix est refusé « tarif à valider » ; les autres lignes passent', () {
      final m = jeu();
      final s = StockMagasin(m, () => jour);
      final pt = m.collection('patients').actives.firstWhere((p) => p['externe'] != true);
      final acte = TarifsPoste.lire(m).parActe.keys.first;
      const session = SessionCs(role: 'admin', fonction: 'direction');
      final r = csPrescrire(s, {'patientCode': pt['code'], 'medecin': 'TEST', 'diagnostic': 'essai', 'actes': [acte, 'CONS-GEN']}, session);
      expect([for (final a in (r.ordonnance['actes'] as List).cast<M>()) a['code']], [acte]);
      expect(r.refus.single['code'], 'CONS-GEN');
      expect(r.refus.single['codeErreur'], 'TARIF_A_VALIDER');
      expect(r.refus.single['categorie'], 'acte');
      expect((r.ordonnance['actes'] as List).cast<M>().single['prix'], greaterThan(0));
    });

    test('aucun prix valide ne change : un acte tarifé donne le même montant avant et après (relevé complet dans la capture des prix)', () {
      final m = jeu();
      final s = StockMagasin(m, () => jour);
      final pt = m.collection('patients').actives.firstWhere((p) => p['externe'] != true && !csVrai(p['assureur']));
      final acte = TarifsPoste.lire(m).parActe.keys.first;
      final attendu = TarifsPoste.prixActe(m, acte, aujourdhui: jour)!;
      final r = csPrescrire(s, {'patientCode': pt['code'], 'medecin': 'TEST', 'diagnostic': 'essai', 'actes': [acte]}, const SessionCs(role: 'admin', fonction: 'direction'));
      expect((r.ordonnance['actes'] as List).cast<M>().single['prix'], attendu);
      expect(r.refus, isEmpty);
    });
  });

  group('(Q18 bis) les voies : jamais une ligne à 0', () {
    // Direction de Baguidi, 16/11/2026 : revient sur le refus de la v20. Le médicament sans prix d'achat est PRESCRIT (le soin n'attend pas la pharmacie) ; sa ligne porte
    // « prix à valoriser », jamais 0, et seul son encaissement attend (voir `prix_a_valoriser_poste_test.dart`).
    test('un médicament connu mais sans prix d’achat est PRESCRIT au « prix à valoriser », jamais à 0 ; le reste de l’ordonnance passe', () {
      final m = jeu();
      final s = StockMagasin(m, () => jour);
      final pt = m.collection('patients').actives.firstWhere((p) => p['externe'] != true);
      final prods = m.collection('produits').actives.take(2).toList();
      m.collection('produits').mettreAJour(prods[1]['id'], {'prixAchat': null}, journaliser: false);
      const session = SessionCs(role: 'admin', fonction: 'direction');
      final r = csPrescrire(s, {'patientCode': pt['code'], 'medecin': 'T', 'diagnostic': 'essai', 'medicaments': [
        {'produitId': prods[0]['id'], 'quantite': 1, 'posologie': 'x', 'duree': '1 j'},
        {'produitId': prods[1]['id'], 'quantite': 1, 'posologie': 'x', 'duree': '1 j'},
      ]}, session);
      expect(r.refus, isEmpty);
      expect(r.aValoriser.single['produitId'], prods[1]['id']);
      expect((r.ordonnance['medicaments'] as List).length, 2);
      expect([for (final l in (r.facture['lignes'] as List).cast<M>()) l['montant']].where((x) => x == 0), isEmpty);
      expect([for (final l in (r.facture['lignes'] as List).cast<M>()) ligneAValoriser(l)], [false, true]);
    });

    test('le relevé du jeu : chaque code sans prix a une cause, aucun code d’un référentiel tarifé n’est à 0', () {
      final m = jeu();
      final r = tarMesurerSansPrix(TarifsPoste.lire(m), tarIso(jour), codesDeListes: {
        'actes': [for (final f in m.collection('actes').actives) '${f['code']}'],
        'analyses': [for (final f in m.collection('analyses').actives) '${f['code']}'],
        'catalogueTarifs': [for (final f in m.collection('catalogueTarifs').actives) '${f['code']}'],
        'examensImagerie': [for (final f in m.collection('examensImagerie').actives) '${f['tarifCode'] ?? f['code']}'],
      });
      // ignore: avoid_print
      print('RELEVÉ SANS PRIX : ${r.sansPrix} codes sur ${r.prestations} prestations — ${ {for (final e in r.parCause.entries) e.key: e.value.length} }');
      for (final e in r.parCause.entries) {
        expect(tarCausesSansPrix.containsKey(e.key), isTrue);
      }
      final h = TarifsPoste.lire(m);
      for (final pr in h.tarifs.where((x) => x['statut'] != 'archive')) {
        final c = tarCauseSansPrix(h, pr, tarIso(jour));
        final s = h.instantane(pr, tarIso(jour));
        expect(c == null, s != null && s.na != null && s.na! > 0, reason: '${pr['code']}');
      }
    });

    test('Q19 : les certificats à prix unique couverts par SOS seule sont listés (lecture, rien d’écrit)', () {
      final m = jeu();
      final avant = m.collection('versionsTarif').toutes.length;
      final l = tarCertificatsPrixUniqueSos(TarifsPoste.lire(m), tarIso(jour));
      expect(l, isNotEmpty);
      expect(l.every((p) => p['famille'] == 'CERTIFICAT' && p['assurable'] == 'sos'), isTrue);
      expect([for (final p in l) p['code']], contains('CERT-APT'));
      expect(m.collection('versionsTarif').toutes.length, avant);
    });
  });
}
