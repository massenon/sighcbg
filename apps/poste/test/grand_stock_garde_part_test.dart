import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/reservation_stock.dart';
import 'package:sigh_poste/sync/service_demandes_import.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;

import 'aide_grand_stock.dart';

/// LES GARDES DU GRAND STOCK AU FILEUL :
///  * l'écriture ORDINAIRE d'un agent reste refusée « réglé sur la mère » ; seul le port du geste d'import (`gardesLevees`, limité à ses cibles) écrit chez le fileul ;
///  * le STOCK d'un produit est un compteur d'activité : une modification qui ne touche que ses compteurs passe (dispensation, perte), le reste de la fiche reste réglé sur la mère ;
///  * la PART de stock d'un poste hors ligne (RG-03) : un stock importé et non confirmé n'existe que chez ce poste, sa part est le tout ; confirmé, la part est partagée ;
///  * un compteur REÇU n'est jamais adopté.
Magasin fileulGarde() {
  final m = vide();
  ApplicateurConfiguration(m, (_) async => []).poserGardes();
  return m;
}

void main() {
  test('LA GARDE : l\'écriture ordinaire du catalogue reste refusée ; le port du geste d\'import écrit les trois cibles du Grand Stock ; une autre collection de configuration reste refusée', () {
    final m = fileulGarde();
    expect(() => m.collection('produits').inserer({'code': 'HORS', 'designation': 'Saisie directe'}), throwsA(isA<EcritureRefusee>()), reason: 'hors geste : le catalogue reste réglé sur la mère');
    final port = PortMagasin(m, aujourdhui: () => jourTest, nomAgent: 'G', profil: profilDe('stock'), gardesLevees: true, etiquette: 'F1');
    port.inserer('produits', {'code': 'DANS', 'designation': 'Dans le geste', 'statut': 'actif'});
    port.inserer('lots', {'numeroLot': 'L'});
    port.inserer('mouvements', {'reference': 'M1'});
    expect(m.collection('produits').toutes.any((f) => f['code'] == 'DANS'), isTrue);
    expect(() => m.collection('fournisseurs').inserer({'code': 'AUTRE'}), throwsA(isA<EcritureRefusee>()), reason: 'une autre collection de configuration reste refusée');
    expect(() => m.collection('actes').inserer({'code': 'A'}), throwsA(isA<EcritureRefusee>()));
    expect(() => m.collection('produits').inserer({'code': 'APRES', 'designation': 'Après le geste'}), throwsA(isA<EcritureRefusee>()), reason: 'la levée ne vaut que pour le port');
  });

  test('LE STOCK EST UN COMPTEUR : une modification qui ne touche que stock, stockGros, stockDetail passe chez un fileul (sortie, perte) ; le reste de la fiche produit reste réglé sur la mère', () {
    final m = fileulGarde();
    final col = m.collection('produits');
    final id = col.toutes.firstWhere((f) => (f['stockGros'] as num? ?? 0) > 5)['id'];
    col.mettreAJour(id, {'stockGros': 5, 'stock': 5});
    expect(col.parId(id)!['stockGros'], 5, reason: 'la sortie d\'un fileul n\'est plus refusée « réglé sur la mère » : le stock voyage par ses variations');
    expect(() => col.mettreAJour(id, {'designation': 'AUTRE NOM'}), throwsA(isA<EcritureRefusee>()));
    expect(() => col.mettreAJour(id, {'stockGros': 4, 'prixAchat': 1}), throwsA(isA<EcritureRefusee>()), reason: 'un compteur ET un autre champ : refusé');
    expect(() => col.archiver(id), throwsA(isA<EcritureRefusee>()));
    expect(col.parId(id)!['designation'], isNot('AUTRE NOM'));
    expect(() => m.collection('fournisseurs').mettreAJour(m.collection('fournisseurs').toutes.first['id'], {'stockGros': 1}), throwsA(isA<EcritureRefusee>()));
  });

  test('LA PART DE STOCK (RG-03) : un stock importé non confirmé est tout entier la part de ce poste ; confirmé ou ordinaire, la part est partagée entre les postes', () {
    final m = fileulGarde();
    final rs = ReservationStock.de(m)
      ..actif = true
      ..nbPostes = 3
      ..installer(m);
    expect(rs.horsLigne, isTrue, reason: 'jamais synchronisé : hors ligne');
    final ordinaire = m.collection('produits').toutes.firstWhere((f) => (f['stockGros'] as num? ?? 0) >= 9);
    final base = (ordinaire['stockGros'] as num).toInt(), part = base ~/ 3;
    expect(() => m.collection('produits').mettreAJour(ordinaire['id'], {'stockGros': base - part - 1, 'stock': base - part - 1}), throwsA(isA<EcritureRefusee>()), reason: 'une sortie qui dépasse la part');
    m.collection('produits').mettreAJour(ordinaire['id'], {'stockGros': base - part, 'stock': base - part});
    // Le Grand Stock importé ICI : en attente de la mère, il n'existe que chez ce poste.
    final svc = ServiceDemandesImport.de(m)
      ..fileulRattache = (() => true)
      ..etiquette = 'F1';
    final jeu = jeuImportParId('grand-stock')!;
    final a = analyserLignes(jeu, lignesDuCas('gs-valide'), 'gs.xlsx', PortMagasin(m, aujourdhui: () => jourTest, nomAgent: 'GESTIONNAIRE', profil: profilDe('stock')))..empreinte = 'e';
    final r = svc.importerEtDemander(jeu, a, profil: profilDe('stock'), nomAgent: 'GESTIONNAIRE');
    expect(r.resultat.ok, isTrue, reason: '${r.resultat.motif}');
    final med1 = m.collection('produits').toutes.firstWhere((f) => f['code'] == 'MED1');
    final l1 = m.collection('lots').toutes.firstWhere((f) => f['numeroLot'] == 'L1');
    expect(ficheLocaleAuPoste(med1), isTrue);
    // Un import n'est pas une sortie, et ce stock n'est vu d'aucun autre poste : tout peut en sortir.
    m.collection('lots').mettreAJour(l1['id'], {'quantiteRestante': 0});
    m.collection('produits').mettreAJour(med1['id'], {'stockGros': 50, 'stock': 50});
    expect(m.collection('lots').parId(l1['id'])!['quantiteRestante'], 0, reason: 'toute la quantité du lot en attente pouvait sortir');
    // Confirmé (marquage levé) : la fiche devient ordinaire, la part est partagée entre les trois postes.
    m.collection('produits').retirerChamp(med1['id'], champEnAttenteMere);
    rs.synchronise(m, {'produits', 'lots'}, postes: 3);
    final plusTard = DateTime.now().add(const Duration(hours: 1));
    rs.maintenant = () => plusTard;
    expect(rs.horsLigne, isTrue);
    expect(() => m.collection('produits').mettreAJour(med1['id'], {'stockGros': 20, 'stock': 20}), throwsA(isA<EcritureRefusee>()), reason: 'sortir 30 sur 50 dépasse la part (16) une fois confirmé');
    m.collection('produits').mettreAJour(med1['id'], {'stockGros': 40, 'stock': 40});
  });

  test('UN COMPTEUR REÇU N\'EST JAMAIS ADOPTÉ : la fiche de configuration de la mère, qui porte le stock du jour, ne donne pas son stock à une fiche que le fileul tient déjà sans compteur ; sa valeur de départ, si elle en a une, est son compteur', () async {
    final m = fileulGarde();
    // Le pont a déjà créé la fiche du fileul, sans compteur : la valeur de la mère arrivée ensuite par la configuration ne doit PAS s'y poser (les variations de la mère s'y additionneraient : 300 pour 150).
    m.collection('produits').appliquerDistante({'id': 'PRD-NEUF', 'code': 'NEUF', 'designation': 'ARTICLE NEUF', 'statut': 'actif', 'idSync': 'PRD-NEUF'});
    final recu = {'code': 'NEUF', 'designation': 'ARTICLE NEUF', 'statut': 'actif', 'stockGros': 150, 'stock': 150, 'stockDetail': 0};
    await ApplicateurConfiguration(m, (c) async => c == 'produits' ? [PieceSync('PRD-NEUF', recu)] : []).tirer();
    final f = m.collection('produits').parId('PRD-NEUF')!;
    expect([f.containsKey('stockGros'), f.containsKey('stock'), f.containsKey('stockDetail')], [false, false, false], reason: 'aucun compteur adopté : seules les variations en donneront un');
    final recuDepart = {...recu, 'departCompteurs': {'stockGros': 150, 'stock': 150, 'stockDetail': 0}};
    await ApplicateurConfiguration(m, (c) async => c == 'produits' ? [PieceSync('PRD-IMPORT', recuDepart)] : []).tirer();
    expect(m.collection('produits').parId('PRD-IMPORT')!['stockGros'], 150, reason: 'une fiche née d\'une demande porte son départ : c\'est son compteur');
    m.collection('produits').appliquerDistante({'id': 'PRD-GARDE', 'code': 'G', 'designation': 'G', 'stockGros': 90, 'statut': 'actif'});
    await ApplicateurConfiguration(m, (c) async => c == 'produits' ? [PieceSync('PRD-GARDE', {...recu, 'code': 'G'})] : []).tirer();
    expect(m.collection('produits').parId('PRD-GARDE')!['stockGros'], 90, reason: 'ses sorties n\'ont pas encore atteint la mère : la valeur de la mère les effacerait');
  });
}
