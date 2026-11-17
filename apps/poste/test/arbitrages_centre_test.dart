import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'aide_qualite.dart';

/// DÉCISIONS DU 16/11/2026, À L'ÉCRAN : le centre des validations porte une ligne « Prix en doublon à arbitrer : CERT-APT » (deux candidats, « Garder celui-ci ») et une ligne « Conflit de couverture
/// à arbitrer » (« Clore celle-ci »), jamais bloquantes ; les commandes sont ABSENTES sans le droit ; et « Tarifs et prix » porte l'onglet « Sans prix ».
// Le jeu LIVRÉ du poste (celui qui porte le doublon CERT-APT), non le jeu de référence d'une autre clinique.
List<Fiche> jeuReel(String nom) => liste(jsonDecode(File('assets/donnees/jeu/$nom.json').readAsStringSync()));

Magasin magasin({List<Fiche> couvertures = const []}) => magasinDe({
      'tarifs': jeuReel('tarifs'),
      'versionsTarif': jeuReel('versionsTarif'),
      'catalogueTarifs': jeuReel('catalogueTarifs'),
      'actes': jeuReel('actes'),
      'analyses': jeuReel('analyses'),
      'patients': jeuReel('patients'),
      'couverturesAssurance': couvertures,
    });

Fiche couv(String id, String patient, String debut, String police) => {
      'id': id, 'statut': 'actif', 'patientId': patient, 'patientCode': 'CBG/9/26', 'assureur': 'NSIA', 'assureurNom': 'NSIA', 'numeroPolice': police, 'debut': debut, 'fin': null, 'tauxPriseEnCharge': 80, 'motif': 'Changement d’employeur'
    };

Future<void> motifEtConfirmer(WidgetTester t, String motif, String libelleOk) async {
  await t.enterText(find.byType(TextField).last, motif);
  await t.pump();
  await toucher(t, find.widgetWithText(BoutonSigh, libelleOk).last);
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  cas('prix en doublon : la ligne nomme CERT-APT et ses deux candidats ; « Garder celui-ci » archive l’autre avec motif ; la ligne disparaît', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'adm-validations');
    expect(find.text('Prix en doublon à arbitrer : CERT-APT'), findsOneWidget);
    expect(find.byKey(const Key('arb:doublon:garder:TAR147')), findsOneWidget);
    expect(find.byKey(const Key('arb:doublon:garder:TAR152')), findsOneWidget);
    await toucher(t, find.byKey(const Key('arb:doublon:garder:TAR152')));
    await motifEtConfirmer(t, 'Tarif de la médecine du travail confirmé', 'Garder celui-ci');
    expect(m.collection('catalogueTarifs').parId('TAR147')!['statut'], 'archive');
    expect(m.collection('catalogueTarifs').parId('TAR147')!['motifArchivage'], 'Tarif de la médecine du travail confirmé');
    expect(TarifsPoste.prixGrille(m, 'CERT-APT', aujourdhui: aujourdhui).montant, 5000);
    expect(find.text('Prix en doublon à arbitrer : CERT-APT'), findsNothing);
  });

  cas('sans le geste « décider un prix », la ligne se lit : AUCUN bouton « Garder celui-ci » (absent, jamais grisé)', (t) async {
    await ouvrir(t, magasin(), 'adm-validations', role: 'comptable');
    expect(find.text('Prix en doublon à arbitrer : CERT-APT'), findsOneWidget);
    expect(find.byKey(const Key('arb:doublon:garder:TAR147')), findsNothing);
  });

  cas('conflit de couverture : la ligne nomme le patient ; « Clore celle-ci » exige un motif et retombe', (t) async {
    final pat = jeuReel('patients').firstWhere((p) => p['externe'] != true);
    final m = magasin(couvertures: [couv('CV1', '${pat['id']}', '2026-05-01', 'POL-A'), couv('CV2', '${pat['id']}', '2026-07-01', 'POL-B')]);
    await ouvrir(t, m, 'adm-validations');
    expect(find.byKey(Key('arb:couv:${pat['id']}')), findsOneWidget);
    expect(find.textContaining('appliquée en attendant'), findsOneWidget);
    await toucher(t, find.byKey(const Key('arb:couv:clore:CV1')));
    await t.pump();
    // Sans motif : la confirmation reste refusée, rien n'est écrit.
    await toucher(t, find.widgetWithText(BoutonSigh, 'Clore celle-ci').last);
    expect(m.collection('couverturesAssurance').parId('CV1')!['fin'], isNull);
    await motifEtConfirmer(t, 'Une seule police depuis le 01/07', 'Clore celle-ci');
    expect(m.collection('couverturesAssurance').parId('CV1')!['fin'], '2026-06-30');
    expect(m.collection('couverturesAssurance').parId('CV1')!['statut'], 'actif');
    expect(find.byKey(Key('arb:couv:${pat['id']}')), findsNothing);
  });

  cas('« Tarifs et prix » : l’onglet « Sans prix » liste une prestation créée sans prix, avec la DAF prévenue', (t) async {
    final m = magasin();
    m.collection('analyses').inserer({'id': 'ANA-N', 'code': 'NEO-TEST', 'designation': 'Analyse de test', 'categorie': 'Biochimie', 'statut': 'Actif', 'n': 99});
    TarifsPoste.assurerAnalyses(m, horloge: () => aujourdhui);
    await ouvrir(t, m, 'cfg-tarifs');
    expect(find.textContaining('Sans prix'), findsWidgets);
    await toucher(t, find.text('Sans prix').first);
    expect(find.text('NEO-TEST'), findsOneWidget);
    expect(find.text('Sans prix en vigueur'), findsWidgets);
  });
}
