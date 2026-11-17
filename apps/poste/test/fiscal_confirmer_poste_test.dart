import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m11/pai_commun.dart' show entreesPaie;

import 'aide_polices.dart';
import 'm14_aide.dart';

/// FISCAL (Direction de Baguidi, compléments du 16/11/2026, section 7) : « Confirmer » les taux de la CNSS (écran « Paramètres comptables & obligations ») et une version
/// du barème de l'AIB (détail d'une version, écran « Acompte sur impôt »). Le bouton est ABSENT sans le geste réservé `fiscal_confirmer` (origine proposée : le Comptable et
/// la DAF) ; la confirmation exige un motif, elle est tracée et ajoutée, jamais écrasée ; une version non arrêtée confirmée est arrêtée à la date d'effet choisie.
Magasin _magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Future<void> _motifEtConfirmer(WidgetTester t, String motif) async {
  await saisir(t, 'motif', motif);
  await toucherM14(t, find.byKey(const Key('fco:confirmer:valider')));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  casM14('CNSS : « Confirmer » offert au comptable, ABSENT pour la Direction (geste non détenu) ; le motif est obligatoire ; la confirmation est tracée et s’ajoute', (t) async {
    final m = _magasin();
    await ouvrirM14(t, m, 'cfg-comptabilite', role: 'direction');
    expect(find.byKey(const Key('fco:cnss')), findsOneWidget, reason: 'la carte de la CNSS se lit par tous ceux qui ouvrent l’écran');
    expect(find.byKey(const Key('fco:cnss:confirmer')), findsNothing, reason: 'une commande refusée est absente, pas grisée');
    // Lot 1 : les taux datés de la paie et la TVA du régime normal ont chacun leur carte à la configuration fiscale.
    for (final o in [fcoObjetVps, fcoObjetBaremeIts, fcoObjetAnciennete, fcoObjetTva]) {
      expect(find.byKey(Key('fco:$o')), findsOneWidget, reason: o);
    }
    // Le comptable n'ouvre pas « Paramètres comptables » : la même carte est à « Cotisations CNSS / ITS / VPS ».
    await ouvrirM14(t, m, 'm11-cotisations', role: 'comptable');
    expect(find.textContaining('Non confirmé'), findsWidgets);
    await toucherM14(t, find.byKey(const Key('fco:cnss:confirmer')));
    await toucherM14(t, find.byKey(const Key('fco:confirmer:valider')));
    expect(m.collection(fcoCollection).actives, isEmpty, reason: 'sans motif, rien n’est écrit');
    await _motifEtConfirmer(t, 'Notification de la CNSS reçue');
    final f = m.collection(fcoCollection).actives.single;
    expect([f['objet'], f['cible'], f['confirmeRole'], f['motif']], [fcoObjetCnss, fcoCibleCnssTaux, 'comptable', 'Notification de la CNSS reçue']);
    expect(f['valeur'], {'tauxOuvrier': 3.6, 'tauxPatronal': 16.4, 'plafond': null});
    expect(m.collection('audit').toutes.first['action'], startsWith('Confirmation fiscale'), reason: 'RG-12 : la confirmation est journalisée');
    expect(find.textContaining('Confirmé par'), findsWidgets);
  });

  casM14('AIB : confirmer une version NON ARRÊTÉE (3 %) l’arrête à la date d’effet choisie ; le taux n’est pas réécrit ; la Direction ne voit pas le bouton', (t) async {
    final m = _magasin();
    final v0 = m.collection('baremeAib').actives.firstWhere((f) => f['taux'] == 3);
    expect(cpdEstArretee(v0), isFalse);
    await ouvrirM14(t, m, 'm12-aib', role: 'direction');
    await toucherM14(t, find.text('3 %').first);
    await t.pump(const Duration(milliseconds: 600)); // le tiroir du détail glisse avant d'être touchable
    expect(find.byKey(const Key('fco:aib:etat')), findsOneWidget);
    expect(find.byKey(const Key('fco:aib:confirmer')), findsNothing);
    await ouvrirM14(t, m, 'm12-aib', role: 'comptable');
    await toucherM14(t, find.text('3 %').first);
    await t.pump(const Duration(milliseconds: 600)); // le tiroir du détail glisse avant d'être touchable
    await toucherM14(t, find.byKey(const Key('fco:aib:confirmer')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Confirmer une version du barème de l’AIB'), findsOneWidget);
    await _motifEtConfirmer(t, 'Texte réglementaire produit');
    final v = m.collection('baremeAib').parId(v0['id'])!;
    expect(cpdEstArretee(v), isTrue);
    expect(v['taux'], 3, reason: 'la valeur n’est jamais réécrite');
    expect(v['decideurArret'], isNotEmpty);
    final c = m.collection(fcoCollection).actives.single;
    expect([c['objet'], c['cible'], c['confirmeRole']], [fcoObjetBaremeAib, '${v0['id']}', 'comptable']);
    expect(v['confirmationId'], c['id']);
  });

  // LOT 1 DE L'INVENTAIRE DES VALEURS EN DUR : la CNSS, le VPS et le barème de l'ITS sont des PARAMÈTRES DATÉS ; la confirmation fiscale agit sur eux.
  casM14('VPS : « Nouvelle version » sous le geste — la version datée s’ajoute à `parametres`, la confirmation l’atteste ; novembre la lit, octobre garde 4 %', (t) async {
    final m = _magasin();
    await ouvrirM14(t, m, 'm11-cotisations', role: 'direction');
    expect(find.byKey(const Key('fco:vps')), findsOneWidget, reason: 'la carte du VPS se lit par tous ceux qui ouvrent l’écran');
    expect(find.byKey(const Key('fco:vps:nouvelle')), findsNothing, reason: 'sans le geste, la commande est absente');
    await ouvrirM14(t, m, 'm11-cotisations', role: 'comptable');
    await toucherM14(t, find.byKey(const Key('fco:vps:nouvelle')));
    await saisir(t, 'taux', '5');
    await toucherM14(t, find.byKey(const Key('fco:version:valider')));
    expect(m.collection(parCollectionParametres).toutes.where((f) => f['cle'] == paiCleVps), isEmpty, reason: 'sans motif, rien n’est écrit');
    await saisir(t, 'motif', 'Loi de finances 2027');
    await toucherM14(t, find.byKey(const Key('fco:version:valider')));
    await t.pump(const Duration(milliseconds: 300));
    final v = m.collection(parCollectionParametres).toutes.singleWhere((f) => f['cle'] == paiCleVps);
    expect([v['valeur'], v['dateEffet'], v['motif'], v['famille']], [5.0, '2026-10-30', 'Loi de finances 2027', paiFamilleBaremes]);
    final c = m.collection(fcoCollection).actives.single;
    expect([c['objet'], c['valeur'], c['confirmeRole']], [fcoObjetVps, {'taux': 5.0}, 'comptable']);
    // Le moteur lit le taux à la DATE DU BULLETIN : octobre (01/10) garde 4 %, novembre (01/11) prend 5 %.
    final oct = paiCalculerTous(m.collection('personnel').actives, 2026, 9, entreesPaie(m), aujourdhui);
    final nov = paiCalculerTous(m.collection('personnel').actives, 2026, 10, entreesPaie(m), aujourdhui);
    expect(oct, isNotEmpty);
    expect(oct.first.taux.vps, 4);
    expect(nov.first.taux.vps, 5);
    expect(oct.first.vps, arrondiJs(oct.first.brutApresSanction * 4 / 100));
    expect(m.collection('audit').toutes.first['action'], startsWith('Confirmation fiscale'), reason: 'RG-12');
  });

  casM14('barème de l’ITS : marqué « à confirmer » tant qu’aucun texte n’est cité ; la confirmation exige le texte cité', (t) async {
    final m = _magasin();
    await ouvrirM14(t, m, 'm11-cotisations', role: 'comptable');
    expect(find.byKey(const Key('fco:bareme_its:aconfirmer')), findsOneWidget);
    await toucherM14(t, find.byKey(const Key('fco:bareme_its:confirmer')));
    await saisir(t, 'motif', 'Vérifié avec le cabinet comptable');
    await toucherM14(t, find.byKey(const Key('fco:confirmer:valider')));
    expect(m.collection(fcoCollection).actives, isEmpty, reason: 'sans texte cité, rien n’est écrit');
    await saisir(t, 'texte', 'Code général des impôts, article 179');
    await toucherM14(t, find.byKey(const Key('fco:confirmer:valider')));
    await t.pump(const Duration(milliseconds: 300));
    final f = m.collection(fcoCollection).actives.single;
    expect([f['objet'], f['texte']], [fcoObjetBaremeIts, 'Code général des impôts, article 179']);
    expect(find.byKey(const Key('fco:bareme_its:aconfirmer')), findsNothing);
  });
}
