import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

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
}
