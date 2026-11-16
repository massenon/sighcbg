import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// CONTINUITÉ DES VALIDATIONS, À L'ÉCRAN (Direction, 15/11/2026) : la Direction est un FILEUL (seuls l'administrateur et la DAF portent la mère). Sur « Tarifs et prix » d'un fileul
/// rattaché, la commande « Valider » d'un tarif d'attente est OFFERTE (avant : absente, « réglé sur la mère »), le geste est DÉPOSÉ, l'écran dit « Transmise à la mère, en attente »
/// et la commande disparaît (pas de second dépôt). Rien n'est validé chez le fileul avant la confirmation de la mère.
void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('sur un fileul rattaché, la Direction DÉPOSE la validation d\'un tarif d\'attente : badge « en attente de la mère », pas de second bouton, rien d\'écrit chez le fileul', (t) async {
    final m = magasinM14();
    await t.runAsync(() => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true)));
    // Un tarif d'attente à valider (le jeu de l'aide en porte arrêtés).
    m.collection('actes').mettreAJour(m.collection('actes').actives.firstWhere((f) => f['code'] == 'MG01')['id'], {'tarifProvisoire': true, 'valideLe': null}, journaliser: false);
    await ouvrirM14(t, m, 'cfg-tarifs', role: 'direction');
    await t.enterText(find.byKey(const Key('kit:tableau-recherche')).first, 'MG01');
    await t.pump(const Duration(milliseconds: 500));
    final acte = m.collection('actes').actives.firstWhere((f) => f['code'] == 'MG01');
    final bouton = find.byKey(Key('val:valider:actes:${acte['id']}'));
    expect(bouton, findsOneWidget, reason: 'le validateur d\'un fileul voit la commande : le geste se dépose, il n\'est pas refusé');
    await toucherM14(t, bouton);
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Valider').last);
    expect(m.collection('validationsDeposees').toutes.length, 1);
    expect(m.collection('validationsDeposees').toutes.single['etat'], 'deposee');
    expect(m.collection('actes').parId(acte['id'])!['tarifProvisoire'], isTrue, reason: 'jamais validé avant la confirmation de la mère');
    expect(find.byKey(Key('val:valider:actes:${acte['id']}')), findsNothing, reason: 'le geste est déposé : pas de second bouton');
  });
}
