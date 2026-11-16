import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/mere/mrb_source.dart';
import 'package:sigh_poste/sync/pont_activite.dart' show collectionsActivite;

import 'aide_polices.dart';
import 'aide_qualite.dart';

/// SATISFACTION EN LIGNE (décision du 16/11/2026, section 8), écran du poste : ouvrir un lien « sur Internet, par le relais » (toujours anonyme), voir
/// son état de publication écrit par la mère, son adresse et son QR une fois publié, imprimer l'affiche ; la carte du poste mère (état, relève) ;
/// les liens et les réponses voyagent par la synchronisation.
Magasin magasin({List<Fiche> jetons = const []}) =>
    magasinDe({'enquetes': jeuJson('enquetes'), 'reponsesEnquetes': jeuJson('reponsesEnquetes'), 'jetonsEnquete': jetons});

class _SourceFactice extends MrbSource {
  int relevees = 0;
  @override
  Future<Map<String, Object?>?> etatSatisfaction() async =>
      {'relais_configure': true, 'kid': '0123456789abcdef', 'liens_en_ligne': 1, 'derniere_releve_ms': null, 'recues': relevees, 'illisibles': 0, 'erreur': null};
  @override
  Future<Map<String, Object?>> synchroniserSatisfaction() async {
    relevees += 2;
    return {'publies': 1, 'revoques': 0, 'refuses': 0, 'recues': 2, 'illisibles': 0};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUpAll(chargerPolices);
  setUp(() {
    ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf';
    ImpressionPoste.lancer = (exe, args) async => throw ProcessException(exe, args);
  });
  tearDown(() {
    ToastsSigh.viderPourTests();
    mrbSourceInjectee = null;
  });

  test('les liens et les réponses voyagent par la synchronisation (réponses relevées par la mère comprises)', () {
    expect(collectionsActivite, containsAll(['jetonsEnquete', 'reponsesEnquetes']));
  });

  cas('ouvrir un lien EN LIGNE : toujours anonyme (un choix nominatif est refusé en le nommant), en attente du poste mère, sans QR ni adresse', (t) async {
    final m = magasin();
    await ouvrir(t, m, 'adm-enquetes');
    await toucher(t, find.byTooltip('Partager à un tiers'));
    await choisir(t, 'usage', 'Sur Internet, par le relais — depuis chez soi (anonyme, chiffré)');
    await choisir(t, 'anonyme', 'Nominatif — le répondant se nomme, et le formulaire le dit');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Ouvrir le lien'));
    expect(m.collection('jetonsEnquete').toutes, isEmpty, reason: 'un lien en ligne nominatif est refusé');
    expect(find.textContaining('Un lien en ligne est toujours anonyme'), findsOneWidget);
    await choisir(t, 'anonyme', 'Anonyme — aucun lien vers un dossier patient');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Ouvrir le lien'));
    final j = m.collection('jetonsEnquete').actives.single;
    expect(j['enLigne'], isTrue);
    expect(j['anonyme'], isTrue);
    expect(j['usage'], 'relais');
    expect(j['jeton'], matches(RegExp(r'^[a-km-z2-9]{24}$')));
    expect(find.text('Lien en ligne'), findsOneWidget);
    expect(find.text('En attente du poste mère'), findsOneWidget);
    expect(find.byKey(const Key('qual:qr')), findsNothing, reason: 'aucun QR tant que le lien ne mène nulle part');
    expect(find.byKey(const Key('qual:adresse-en-ligne')), findsNothing);
  });

  cas('un lien publié par la mère : l’adresse du relais, son QR, l’affiche imprimable ; la colonne « Canal » le dit', (t) async {
    final m = magasin(jetons: [
      {
        'id': 'JET0001', 'statut': 'actif', 'jeton': 'abcdefghijkmnpqrstuvwxyz', 'enqueteId': 'ENQ0001', 'enqueteTitre': 'Satisfaction des patients',
        'anonyme': true, 'usage': 'relais', 'enLigne': true, 'creeLe': '2026-08-10', 'expireLe': '2026-09-30', 'revoqueLe': null,
        'lienPublic': 'https://relais.exemple.bj/satisfaction/abcdefghijkmnpqrstuvwxyz', 'publieLe': '2026-08-10', 'erreurRelais': '',
      }
    ]);
    await ouvrir(t, m, 'adm-enquetes');
    await toucher(t, find.text('Liens de partage (1)'));
    expect(find.text('Publié sur le relais'), findsOneWidget);
    await toucher(t, find.byTooltip('Afficher le lien et le QR'));
    final champ = t.widget<TextField>(find.byKey(const Key('qual:adresse-en-ligne')));
    expect(champ.controller!.text, 'https://relais.exemple.bj/satisfaction/abcdefghijkmnpqrstuvwxyz');
    expect(champ.controller!.text, isNot(contains('ENQ0001')), reason: 'jamais l’identifiant de l’enquête');
    expect(find.byKey(const Key('qual:qr')), findsOneWidget);
    String? pdf;
    ImpressionPoste.enregistrer = (octets, nom) async {
      pdf = nom;
      expect(octets.length, greaterThan(500));
      return '/faux/$nom.pdf';
    };
    await toucher(t, find.widgetWithText(BoutonSigh, 'Imprimer l’affiche (QR)'));
    await t.pump(const Duration(seconds: 1));
    expect(pdf, isNotNull, reason: 'l’affiche est produite en PDF');
    expect(find.textContaining('Aucune commande d’impression'), findsOneWidget, reason: 'sans imprimante, le refus est nommé et le PDF reste');
  });

  cas('sur un fileul, la carte dit que la mère publie et relève ; sur la mère, l’état et « Publier et relever maintenant »', (t) async {
    await ouvrir(t, magasin(), 'adm-enquetes');
    await toucher(t, find.text('Liens de partage (0)'));
    expect(find.textContaining('Ce poste n’est pas le poste mère'), findsOneWidget);
  });

  cas('poste mère : état sans clé privée, relève sur demande', (t) async {
    final s = _SourceFactice();
    mrbSourceInjectee = s;
    await ouvrir(t, magasin(), 'adm-enquetes');
    await toucher(t, find.text('Liens de partage (0)'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Satisfaction en ligne (poste mère)'), findsOneWidget);
    expect(find.textContaining('Identifiant 0123456789abcdef'), findsOneWidget);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Publier et relever maintenant'));
    await t.pump(const Duration(milliseconds: 200));
    expect(s.relevees, 2);
    expect(find.textContaining('2 réponse(s) reçue(s)'), findsOneWidget);
  });

  cas('sans le droit d’écrire, ni partage ni relève', (t) async {
    final role = roleSelonDroit('adm-enquetes', editer: false);
    if (role == null) return;
    mrbSourceInjectee = _SourceFactice();
    await ouvrir(t, magasin(), 'adm-enquetes', role: role);
    expect(find.byTooltip('Partager à un tiers'), findsNothing);
    await toucher(t, find.text('Liens de partage (0)'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.widgetWithText(BoutonSigh, 'Publier et relever maintenant'), findsNothing);
  });
}
