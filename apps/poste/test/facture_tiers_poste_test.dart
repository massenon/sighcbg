import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/facture_tiers_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/service_droits.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm9_aide.dart';

/// LA FACTURE À UNE ENTREPRISE, AU POSTE (Direction de Baguidi, 17/11/2026, point 2) : l'onglet « Factures à une entreprise » de `m9-facture-mere`, né d'une ligne du relevé de M9 ; la commande
/// est ABSENTE sans le geste réservé ; l'IFU, le nom et la situation d'AIB sont saisis (la situation n'est jamais présumée) ; la pièce est numérotée par la série `caisse.factures-tiers`,
/// mise EN ATTENTE de certification (aucun numéro fabriqué), journalisée ; les factures patients qu'elle réclame ne figurent plus à la facture mère ; la facture du patient n'est pas touchée.
const ifu = '1201555000123';

Magasin monde() {
  final m = magasin();
  ServiceDroits.de(m).fileulRattache = () => false;
  // Le barème d'origine n'arrête que le 5 % de « sans IFU actif » au 07/09/2026 : pour une pièce du 16/08, une version arrêtée antérieure (choix du comptable, test).
  m.collection('baremeAib').inserer({
    'id': 'BAI-TEST',
    'statut': 'actif',
    'situation': 'prestation_service',
    'taux': 5,
    'statutArret': 'arrete',
    'arrete': true,
    'aValider': false,
    'dateEffet': '2026-01-01',
    'dateArret': '2026-01-01',
    'decideurArret': 'Direction',
    'source': 'Texte de test',
    'motif': 'Version de test'
  });
  return m;
}

/// Un écran assez haut pour que le formulaire et son bouton soient dans la fenêtre : le test ne mesure pas le défilement de la page.
void grandEcran(WidgetTester t) {
  t.view.physicalSize = const Size(1600, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
}

Future<void> ouvrirOnglet(WidgetTester t, Magasin m, {String role = 'comptable'}) async {
  await ouvrir(t, m, 'm9-facture-mere', role: role);
  grandEcran(t);
  await toucher(t, find.text('Factures à une entreprise').first);
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  cas('sans le geste réservé, la commande est ABSENTE et la note nomme le geste (l\'administrateur n\'a pas le geste d\'origine)', (t) async {
    final m = monde();
    await ouvrirOnglet(t, m, role: 'admin');
    expect(find.byKey(const Key('tiers:reserve')), findsOneWidget);
    expect(find.byKey(const Key('tiers:emettre')), findsNothing, reason: 'absente, jamais grisée');
    expect(m.collection(colFacturesTiers).toutes, isEmpty);
  });

  cas('le comptable émet : refus nommé sans situation (rien d\'écrit), puis la pièce, numérotée, en attente de certification, journalisée ; la facture mère ne réclame plus ses filles', (t) async {
    final m = monde();
    await ouvrir(t, m, 'm9-facture-mere', role: 'comptable');
    grandEcran(t);
    await t.pump(const Duration(milliseconds: 300));
    expect(kpis(t), ['2', '4', '30 140 FCFA', 'Concordant']);
    await toucher(t, find.text('Factures à une entreprise').first);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('tiers:emettre')), findsOneWidget);
    await saisir(t, 'ifu', ifu);
    await saisir(t, 'nom', 'Université de Parakou');
    // La situation n'est JAMAIS présumée : sans choix, refus nommé et rien n'est écrit.
    await toucher(t, find.byKey(const Key('tiers:emettre')));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('AIB_SITUATION_A_CHOISIR'), findsOneWidget);
    expect(m.collection(colFacturesTiers).toutes, isEmpty);
    ToastsSigh.viderPourTests();
    await choisir(t, 'situation', 'Prestation de service retenue par le payeur');
    await toucher(t, find.byKey(const Key('tiers:emettre')));
    await t.pump(const Duration(milliseconds: 500));
    final f = m.collection(colFacturesTiers).toutes.single;
    expect(f['numero'], 'FT-2026-00001');
    expect([f['acheteurIfu'], f['acheteurNom'], f['aibSituation'], f['aibTaux']], [ifu, 'Université de Parakou', 'prestation_service', 5]);
    expect(f['statutMecef'], 'en_attente', reason: 'aucun appareil : le poste ne fabrique aucun numéro');
    expect(f['codeRetour'], isNotNull, reason: 'le refus nommé de l\'adaptateur est porté');
    expect(f['numeroMecef'], isNull);
    expect((f['piecesFilles'] as List), isNotEmpty);
    expect(m.collection('audit').toutes.any((a) => a['action'] == 'Facture à une entreprise émise' && a['reference'] == 'FT-2026-00001'), isTrue, reason: 'RG-12');
    // Les factures patients réclamées ne figurent plus à la facture mère : un souscripteur de moins.
    await toucher(t, find.text('Consolidation').first);
    expect(kpis(t).sublist(1, 3), ['${4 - (f['piecesFilles'] as List).length}', '${sp(money(30140 - (f['montantReleve'] as num)))}'],
        reason: 'la facture mère ne réclame plus les filles de la facture à l\'entreprise : une facture patient ne se réclame qu\'une fois');
    expect(kpis(t).last, 'Concordant', reason: 'le rapprochement de la mère se refait sur ce qui reste');
    // Le tableau des pièces émises le dit, avec son rattachement.
    await toucher(t, find.text('Factures à une entreprise').first);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('FT-2026-00001'), findsWidgets);
    expect(find.text('En attente de certification'), findsWidgets);
  });

  test('l\'engine : refus nommés sans écriture, numéro suivant le plus grand rang, une facture patient ne se réclame qu\'une fois', () {
    final m = monde();
    // Une ligne du relevé dont les factures patients ne sont réclamées par aucune facture mère du jeu (le jeu livre des mères émises : leurs filles sont réclamées).
    final ligne = AssFilleMere('Employeur de test')
      ..factures.addAll([
        {'id': 'F-T1', 'numero': 'FN-2026-09001', 'montantTTC': 10000, 'partAssurance': 8000, 'partPatient': 2000, 'date': '2026-08-10', 'lignes': [{}]},
        {'id': 'F-T2', 'numero': 'FN-2026-09002', 'montantTTC': 5000, 'partAssurance': 4000, 'partPatient': 1000, 'date': '2026-08-11', 'lignes': [{}]},
      ])
      ..assureur = 12000
      ..montant = 15000
      ..patient = 3000;
    final lignes = [ligne];
    ResultatFactureTiers emettre(String role, AssFilleMere l, {Object? situation = 'prestation_service'}) => emettreFactureTiers(m,
        role: role,
        maintenant: DateTime(2026, 8, 16, 12),
        acheteurIfu: ifu,
        acheteurNom: 'Entreprise',
        situationChoisie: situation,
        compagnieCode: 'AFR',
        compagnieNom: 'AFRICAINE DES ASSURANCES',
        periode: 'mois',
        periodeLibelle: 'Mensuelle',
        depuis: '2026-07-17',
        ligne: l);
    expect(emettre('caissier', lignes.first).refus!.code, 'TIERS_PAYEUR_RESERVE');
    expect(m.collection(colFacturesTiers).toutes, isEmpty, reason: 'un refus n\'écrit rien');
    final ok = emettre('comptable', lignes.first);
    expect(ok.ok, isTrue, reason: '${ok.refus?.code} ${ok.refus?.motif}');
    // La même ligne ne se réclame pas deux fois.
    final bis = emettre('da', lignes.first);
    expect(bis.refus!.code, 'FILLE_DEJA_FACTUREE');
    expect(bis.refus!.motif, contains(ok.fiche!['numero'] as String));
    // « Annuler » archive la pièce (RG-14) : la ligne redevient réclamable.
    ok.annuler();
    expect(m.collection(colFacturesTiers).actives, isEmpty);
    expect(m.collection(colFacturesTiers).toutes, hasLength(1), reason: 'archivée, jamais supprimée');
    expect(emettre('comptable', lignes.first).fiche!['numero'], 'FT-2026-00002', reason: 'le numéro de la pièce archivée n\'est jamais redonné');
  });
}
