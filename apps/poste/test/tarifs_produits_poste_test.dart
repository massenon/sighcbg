import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';

/// LE PRIX D'ACHAT DES PRODUITS AU POSTE : la reprise d'un poste déjà peuplé (version 1 sans date inventée), la version AJOUTÉE (jamais écrasée), le Oui qui met la fiche au prix en vigueur
/// et fait SUIVRE le prix de vente d'un médicament (RG-02), les gardes du magasin (une version ne se modifie pas, un médicament ne naît pas avec une marge), le dépôt d'un fileul que la mère applique.
final auj = DateTime(2026, 11, 14, 10);
String plus(int n) => tarIso(auj.add(Duration(days: n)));

Magasin jeu() {
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
  TarifsPoste.assurerProduits(m);
  return m;
}

TarifsPoste poste(Magasin m, String role, {String nom = 'Agent', bool fileul = false, bool proposer = true, String etiquette = 'P'}) => TarifsPoste(m,
    role: role,
    auteur: () => nom,
    fileul: fileul,
    peutEditerEcran: false,
    peutProposerPrixAchat: proposer,
    libelles: const {'da': 'DAF', 'direction': 'Direction', 'admin': 'Administrateur', 'stock': 'Gestionnaire de stock'},
    horloge: () => auj,
    etiquette: etiquette);

Map<String, Object?> article(Magasin m, String categorie) => m.collection('produits').actives.firstWhere((p) => p['categorie'] == categorie);
// Loin dans le futur : aucune pièce du jeu ne porte l'article à cette date.
const loin = '2027-03-01';

void main() {
  group('la reprise d\'un poste déjà peuplé', () {
    test('chaque produit actif reçoit sa version 1 « reprise », SANS date d\'effet, au prix qu\'il tient ; idempotente ; une seule ligne de journal', () {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
      final avant = m.collection('audit').toutes.length;
      final n = m.collection('produits').actives.length;
      expect(TarifsPoste.assurerProduits(m), n);
      expect(m.collection('audit').toutes.length, avant + 1, reason: 'un geste de reprise, une ligne : pas une par produit');
      final vs = [for (final v in m.collection('versionsTarif').toutes) if (v['origine'] == 'reprise') v];
      expect(vs.length, n);
      expect(vs.every((v) => v['version'] == 1 && v['statut'] == 'valide' && !v.containsKey('dateEffet')), isTrue, reason: 'aucune date inventée');
      final p = article(m, 'medicament');
      expect(vs.firstWhere((v) => v['code'] == p['code'])['prixNonAssure'], p['prixAchat']);
      expect(TarifsPoste.assurerProduits(m), 0, reason: 'rejouée : rien');
      expect(TarifsPoste.lire(m).tarifs.where((t) => t['famille'] == tarFamilleProduit).length, n);
    });

    test('un produit sans prix d\'achat est repris « manquant » (à valoriser), jamais à zéro', () {
      final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
      final p = article(m, 'conso_medical');
      m.collection('produits').appliquerDistante({...p}..remove('prixAchat'));
      TarifsPoste.assurerProduits(m);
      final r = TarifsPoste.prixProduit(m, m.collection('produits').parId(p['id'])!, aujourdhui: auj);
      expect(r.absent, isTrue);
      expect(TarifsPoste.produitsAValoriser(m, aujourdhui: auj).map((x) => x.produit['code']), [p['code']]);
    });
  });

  group('changer le prix d\'achat', () {
    test('une version AJOUTÉE ; la fiche ne bouge pas à la proposition ; au Oui elle suit, et le prix de vente d\'un médicament suit (RG-02)', () {
      final m = jeu();
      final p = article(m, 'medicament');
      final achat = p['prixAchat'] as num;
      final stock = poste(m, 'stock');
      final r = stock.proposerPrixAchat(DemandeProduit(code: '${p['code']}', prixAchat: achat + 10, dateEffet: plus(0), motif: 'Nouveau tarif fournisseur'));
      expect(r.ok, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
      expect(TarifsPoste.lire(m).versionsDe('${p['code']}').length, 2, reason: 'la version 1 est conservée');
      expect(m.collection('produits').parId(p['id'])!['prixAchat'], achat);
      final id = '${r.version!['id']}';
      // Le gestionnaire de stock ne décide pas : le Oui est un geste réservé.
      expect(stock.decider(id, 'oui').refus, isNotNull);
      final da = poste(m, 'da', nom: 'DAF');
      expect(da.decider(id, 'oui').ok, isTrue);
      final apres = m.collection('produits').parId(p['id'])!;
      expect([apres['prixAchat'], apres['prixVente']], [achat + 10, achat + 10], reason: 'RG-02 : le prix de vente SUIT le prix d\'achat, il ne se saisit pas');
      expect(TarifsPoste.prixProduit(m, apres, aujourdhui: auj, date: '2020-01-01').achat, achat, reason: 'la pièce d\'hier garde son prix');
      expect(TarifsPoste.prixProduit(m, apres, aujourdhui: auj).achat, achat + 10);
    });

    test('une version datée de demain ne change la fiche QU\'À sa date (projection au démarrage)', () {
      final m = jeu();
      final p = article(m, 'reactif');
      final achat = p['prixAchat'] as num;
      final da = poste(m, 'da', nom: 'DAF');
      expect(da.proposerPrixAchat(DemandeProduit(code: '${p['code']}', prixAchat: achat + 5, dateEffet: loin, motif: 'Avenant', valider: true)).ok, isTrue);
      expect(m.collection('produits').parId(p['id'])!['prixAchat'], achat);
      expect(TarifsPoste.projeterProduits(m, DateTime(2027, 3, 1, 8)), 1);
      expect(m.collection('produits').parId(p['id'])!['prixAchat'], achat + 5);
      expect(TarifsPoste.projeterProduits(m, DateTime(2027, 3, 1, 8)), 0, reason: 'idempotente');
    });

    test('hors médicament, le prix de vente propre est conservé quand le prix d\'achat change', () {
      final m = jeu();
      final p = {...article(m, 'fourniture'), 'prixVente': 999};
      m.collection('produits').appliquerDistante(p);
      m.collection('versionsTarif').remplacerContenu([for (final v in m.collection('versionsTarif').toutes) if (v['code'] != p['code']) v]);
      m.collection('tarifs').remplacerContenu([for (final v in m.collection('tarifs').toutes) if (v['code'] != p['code']) v]);
      TarifsPoste.assurerProduits(m);
      expect(TarifsPoste.prixProduit(m, p, aujourdhui: auj).vente, 999);
      final da = poste(m, 'da', nom: 'DAF');
      expect(da.proposerPrixAchat(DemandeProduit(code: '${p['code']}', prixAchat: (p['prixAchat'] as num) + 1, dateEffet: plus(0), motif: 'Hausse', valider: true)).ok, isTrue);
      expect(m.collection('produits').parId(p['id'])!['prixVente'], 999);
    });

    test('refus nommés : RG-02, droit, zéro, motif', () {
      final m = jeu();
      final p = article(m, 'medicament');
      final achat = p['prixAchat'] as num;
      final stock = poste(m, 'stock');
      DemandeProduit d({Object? prix, Object? vente, String? motif = 'x'}) => DemandeProduit(code: '${p['code']}', prixAchat: prix ?? achat + 1, prixVente: vente, dateEffet: plus(0), motif: motif);
      expect(stock.proposerPrixAchat(d(vente: achat + 50)).refus!.code, 'RG02_MARGE');
      expect(stock.proposerPrixAchat(d(prix: 0)).refus!.code, 'PRIX_ZERO');
      expect(stock.proposerPrixAchat(d(motif: '')).refus!.code, 'MOTIF_REQUIS');
      expect(poste(m, 'caissier', proposer: false).proposerPrixAchat(d()).refus!.code, 'PROPOSITION_RESERVEE');
      expect(TarifsPoste.lire(m).versionsDe('${p['code']}').length, 1, reason: 'aucun refus n\'écrit quoi que ce soit');
    });
  });

  group('le geste réservé « proposer un prix d\'achat » (Direction, 16/11/2026)', () {
    DemandeProduit d(Magasin m) {
      final p = article(m, 'medicament');
      return DemandeProduit(code: '${p['code']}', prixAchat: (p['prixAchat'] as num) + 3, dateEffet: plus(0), motif: 'Hausse');
    }

    test('origine : gestionnaire de stock, DAF, administrateur ; le caissier a le droit d\'éditer l\'écran mais pas le geste : refus NOMMÉ, rien n\'est écrit', () {
      final m = jeu();
      expect(gesteReserve(gesteProposerPrixAchat)!.rolesDefaut, ['admin', 'da', 'stock']);
      // Le caissier garde le droit d'ÉDITER l'écran (peutProposerPrixAchat: true) : c'est le geste qui lui manque.
      final r = poste(m, 'caissier').proposerPrixAchat(d(m));
      expect(r.refus!.code, 'PROPOSITION_RESERVEE');
      expect(TarifsPoste.lire(m).versionsDe('${article(m, 'medicament')['code']}').length, 1);
      expect(poste(m, 'caissier').peutProposerPrixAchatEcran, isFalse);
      for (final role in ['stock', 'da', 'admin']) {
        expect(poste(jeu(), role).peutProposerPrixAchatEcran, isTrue, reason: role);
      }
      expect(poste(m, 'stock').proposerPrixAchat(d(m)).ok, isTrue);
    });

    test('c\'est la FICHE du rôle qui décide, à chaud : accordé au caissier il propose, retiré au gestionnaire de stock il est refusé', () {
      final m = jeu();
      DroitsGestes avec(String role, bool v) => DroitsGestes(fiches: [
            {'role': role, 'droitsGestes': {gesteProposerPrixAchat: v}}
          ]);
      expect(TarifsPoste(m, role: 'caissier', auteur: () => 'C', peutProposerPrixAchat: true, gestes: () => avec('caissier', true), horloge: () => auj, etiquette: 'P').proposerPrixAchat(d(m)).ok, isTrue);
      final m2 = jeu();
      expect(TarifsPoste(m2, role: 'stock', auteur: () => 'S', peutProposerPrixAchat: true, gestes: () => avec('stock', false), horloge: () => auj, etiquette: 'P').proposerPrixAchat(d(m2)).refus!.code,
          'PROPOSITION_RESERVEE');
    });
  });

  group('les gardes du magasin', () {
    test('une version posée ne se modifie plus (elle se corrige par une version AJOUTÉE)', () {
      final m = jeu();
      final v = m.collection('versionsTarif').toutes.firstWhere((x) => x['origine'] == 'reprise');
      expect(() => m.collection('versionsTarif').mettreAJour(v['id'], {'prixNonAssure': 1}), throwsA(isA<EcritureRefusee>()));
    });

    test('RG-02 au moteur : un médicament ne naît ni ne devient avec une marge ; un autre produit le peut', () {
      final m = jeu();
      final p = article(m, 'medicament');
      expect(() => m.collection('produits').mettreAJour(p['id'], {'prixVente': (p['prixAchat'] as num) + 10}), throwsA(isA<EcritureRefusee>()));
      expect(() => m.collection('produits').inserer({'code': 'TST-MARGE', 'designation': 'Essai', 'categorie': 'medicament', 'prixAchat': 10, 'prixVente': 15}), throwsA(isA<EcritureRefusee>()));
      final q = article(m, 'fourniture');
      m.collection('produits').mettreAJour(q['id'], {'prixVente': (q['prixAchat'] as num) + 10});
      m.collection('produits').mettreAJour(p['id'], {'stock': 7});
    });
  });

  group('un fileul DÉPOSE, la mère applique', () {
    test('le fileul n\'écrit aucune version ; la mère refait les contrôles sous le rôle de l\'auteur et écrit UNE version proposée ; un refus revient nommé', () {
      final mere = jeu();
      final fil = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
      for (final c in ['tarifs', 'versionsTarif']) {
        fil.collection(c).remplacerContenu([for (final f in mere.collection(c).toutes) {...f}]);
      }
      final p = article(mere, 'medicament');
      final achat = p['prixAchat'] as num;
      final f = poste(fil, 'stock', nom: 'Gestionnaire fileul', fileul: true, etiquette: 'F');
      final r = f.proposerPrixAchat(DemandeProduit(code: '${p['code']}', prixAchat: achat + 20, dateEffet: plus(0), motif: 'Dépôt du fileul'));
      expect(r.ok && r.depose, isTrue, reason: '${r.refus?.code}');
      expect(fil.collection('versionsTarif').toutes.length, mere.collection('versionsTarif').toutes.length, reason: 'un fileul n\'écrit pas une version');
      // La demande voyage à la mère (par le pont) ; la mère l'applique.
      mere.collection('propositionsTarif').appliquerDistante({...fil.collection('propositionsTarif').toutes.single});
      expect(TarifsPoste(mere, role: 'mere', auteur: () => 'Poste mère', peutProposerPrixAchatPour: (r) => r == 'stock', horloge: () => auj, etiquette: 'M').appliquerDemandes(), 1);
      final v = mere.collection('versionsTarif').toutes.firstWhere((x) => x['code'] == p['code'] && x['statut'] == 'propose');
      expect([v['proposePar'], v['proposeRole'], v['prixNonAssure'], v['version']], ['Gestionnaire fileul', 'stock', achat + 20, 2]);
      expect(mere.collection('propositionsTarif').toutes.single['etat'], 'appliquee');
      expect(mere.collection('produits').parId(p['id'])!['prixAchat'], achat, reason: 'une proposition ne change rien');
      // La version arrive au fileul (journal de configuration) : un second dépôt pendant l'attente est refusé NOMMÉ, avant même d'être déposé.
      fil.collection('versionsTarif').appliquerDistante({...v});
      final r2 = f.proposerPrixAchat(DemandeProduit(code: '${p['code']}', prixAchat: achat + 30, dateEffet: plus(1), motif: 'Second'));
      expect(r2.refus?.code, 'CHANGEMENT_EN_ATTENTE');
    });
  });
}
