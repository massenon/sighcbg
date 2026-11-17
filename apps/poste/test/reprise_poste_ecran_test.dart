// L'écran « Reprise d'un poste » de la console de la mère (mere-reprise-poste, décision 12, E4608) : la liste des fileuls avec leur identifiant d'appairage, le geste réservé,
// le code affiché UNE fois avec la durée que la mère annonce, jamais journalisé, les refus nommés lisibles.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/mere/mrd_reprise_poste.dart';
import 'package:sigh_poste/modules/mere/registre_mere.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';

final _t0 = DateTime(2026, 11, 17, 12);
const _secret = 'ZQ7K3M9P';

Appareil app(String uuid, String nom, String role, {String etat = 'actif', DateTime? contact, int seq = 0}) =>
    Appareil(uuid: uuid, etiquette: nom, role: role, etat: etat, dernierContact: contact, derniereSeq: seq, deriveMs: 0);

class SourceFausse implements SourceReprise {
  final appels = <String>[];
  Object? panne;
  ErreurMere? refus;
  int? validite = 900;
  List<Appareil> liste = [
    app('uuid-caisse-0001', 'Caisse', 'fileul', contact: _t0.subtract(const Duration(minutes: 4)), seq: 118),
    app('uuid-ancien-0002', 'Ancien labo', 'fileul', etat: 'revoque', contact: _t0.subtract(const Duration(days: 9)), seq: 3),
    app('uuid-mobile-0003', 'Dr Yoro', 'mobile'),
    app('uuid-neuf-0004', 'Neuf', 'fileul'),
  ];
  @override
  Future<List<Appareil>> appareils() async {
    if (panne != null) throw panne!;
    return liste;
  }

  @override
  Future<CodeReprise> emettre({required String uuid, required String etiquette}) async {
    appels.add('$uuid|$etiquette');
    if (refus != null) throw refus!;
    return CodeReprise(code: _secret, expireMs: _t0.add(const Duration(seconds: 900)).millisecondsSinceEpoch, validiteSecondes: validite);
  }
}

void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    ToastsSigh.viderPourTests();
    sourceRepriseInjectee = null;
  });
  final roleOrigine = gesteReserve(gesteRepriseEmettre)!.rolesDefaut.first;

  Future<Magasin> monter(WidgetTester t, SourceFausse src, {String? role, bool retirerLeGeste = false, bool accorderLeGeste = false}) async {
    t.view.physicalSize = const Size(1500, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final r = role ?? roleOrigine;
    final m = Magasin({
      if (retirerLeGeste || accorderLeGeste) 'rbac': [{'id': 'R1', 'role': r, 'statut': 'actif', 'droitsGestes': {gesteRepriseEmettre: accorderLeGeste}}],
    }, 'POSTE');
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ContexteEcran(
                    ecranId: 'mere-reprise-poste',
                    role: r,
                    droit: const Droit(voir: true, editer: true, annuler: true),
                    magasin: m,
                    utilisateur: 'U-ESSAI',
                    aller: (_) {},
                    horloge: () => _t0,
                    child: EcranReprisePoste(source: src, maintenant: () => _t0))))));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    return m;
  }

  Future<void> toucher(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  test('l’écran est branché au registre de la mère', () {
    expect(ecransMERE.keys, contains('mere-reprise-poste'));
  });

  testWidgets('la liste montre les fileuls (pas les mobiles) avec leur identifiant d’appairage, leur état et leur dernière synchronisation', (t) async {
    await monter(t, SourceFausse());
    expect(find.text('Caisse'), findsOneWidget);
    expect(find.text('uuid-caisse-0001'), findsOneWidget, reason: 'de quoi choisir QUEL ancien poste est repris');
    expect(find.text('uuid-ancien-0002'), findsOneWidget);
    expect(find.text('Dr Yoro'), findsNothing, reason: 'un mobile se ré-appaire, il ne se reprend pas');
    expect(find.text('Révoqué'), findsOneWidget);
    expect(find.textContaining('il y a 4 min'), findsOneWidget);
    expect(find.text('jamais synchronisé'), findsOneWidget);
    expect(find.byKey(const Key('rep:generer:uuid-caisse-0001')), findsOneWidget);
    expect(find.byKey(const Key('rep:sans-droit')), findsNothing);
  });

  testWidgets('générer le code : le poste choisi est celui de la mère, le code s’affiche avec la durée ANNONCÉE par la mère, se copie, ne se relit plus', (t) async {
    final src = SourceFausse();
    final m = await monter(t, src);
    final copies = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.setData') copies.add((c.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await toucher(t, find.byKey(const Key('rep:generer:uuid-caisse-0001')));
    expect(find.byKey(const Key('rep:explication')), findsOneWidget);
    expect(find.textContaining('Rejoindre une clinique'), findsWidgets);
    await toucher(t, find.byKey(const Key('rep:confirmer')));
    expect(src.appels, ['uuid-caisse-0001|Caisse'], reason: 'l’étiquette proposée est celle de l’ancien poste');
    expect(t.widget<SelectableText>(find.byKey(const Key('rep:code'))).data, _secret);
    expect(t.widget<Text>(find.byKey(const Key('rep:validite'))).data, contains('valable 15 minutes'), reason: 'durée lue de la mère');
    expect(find.byKey(const Key('rep:une-fois')), findsOneWidget);
    // journal : le geste est tracé SANS le code
    final audit = m.collection('audit').toutes;
    expect(audit.length, 1);
    expect(audit.single['action'], 'Code de reprise émis');
    expect(audit.single['reference'], 'uuid-caisse-0001');
    expect('${audit.single}'.contains(_secret), isFalse, reason: 'le code n’est JAMAIS journalisé en clair');
    await toucher(t, find.byKey(const Key('rep:copier')));
    expect(copies, [_secret]);
    await t.pump(const Duration(seconds: 5));
    await toucher(t, find.byKey(const Key('rep:fermer')));
    expect(find.text(_secret), findsNothing, reason: 'affiché UNE fois : fermé, il ne se relit plus');
    expect(find.byKey(const Key('rep:code')), findsNothing);
    expect(find.byKey(const Key('rep:emis')), findsOneWidget);
    expect('${m.collection('audit').toutes}'.contains(_secret), isFalse);
  });

  testWidgets('sans durée annoncée par la mère, l’écran ne suppose rien', (t) async {
    final src = SourceFausse()..validite = null;
    await monter(t, src);
    await toucher(t, find.byKey(const Key('rep:generer:uuid-caisse-0001')));
    await toucher(t, find.byKey(const Key('rep:confirmer')));
    final texte = t.widget<Text>(find.byKey(const Key('rep:validite'))).data!;
    expect(texte, contains('n’est pas communiquée'));
    expect(texte.contains('15'), isFalse);
  });

  testWidgets('chaque refus de la mère est nommé et lisible : poste inconnu, déjà repris, code expiré, accès administrateur', (t) async {
    final cas = {
      'appareil_inconnu': 'ne connaît pas ce poste',
      'deja_repris': 'déjà été repris',
      'code_expire': 'a expiré',
      'admin_requis': 'secret d’administration',
    };
    for (final e in cas.entries) {
      final src = SourceFausse()..refus = ErreurMere(409, e.key, 'motif de la mère');
      await monter(t, src);
      await toucher(t, find.byKey(const Key('rep:generer:uuid-caisse-0001')));
      await toucher(t, find.byKey(const Key('rep:confirmer')));
      final refus = t.widget<NoteSigh>(find.byKey(const Key('rep:refus')));
      expect(refus.texte, startsWith('${e.key} :'));
      expect(refus.texte, contains(e.value), reason: e.key);
      expect(find.byKey(const Key('rep:code')), findsNothing, reason: 'aucun code affiché sur un refus');
      expect(find.text(_secret), findsNothing);
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('service muet : « non disponible », bannière nommée, aucun faux zéro, aucune commande', (t) async {
    final src = SourceFausse()..panne = ErreurMere(503, 'indisponible', 'La base ne répond pas.');
    await monter(t, src);
    expect(find.byKey(const Key('rep:panne')), findsOneWidget);
    expect(find.text('non disponible'), findsWidgets);
    expect(find.byKey(const Key('rep:generer:uuid-caisse-0001')), findsNothing);
  });

  testWidgets('un rôle SANS le geste ne voit AUCUNE commande de génération (absente, pas grisée) et lit pourquoi', (t) async {
    await monter(t, SourceFausse(), retirerLeGeste: true);
    expect(find.byKey(const Key('rep:sans-droit')), findsOneWidget);
    expect(t.widget<NoteSigh>(find.byKey(const Key('rep:sans-droit'))).texte, contains('Émettre un code de reprise'));
    expect(find.text('Caisse'), findsOneWidget, reason: 'la liste reste lisible');
    expect(find.byKey(const Key('rep:generer:uuid-caisse-0001')), findsNothing);
    expect(find.text('Générer un code de reprise'), findsNothing);
  });

  testWidgets('un rôle créé en exploitation, sans fiche, n’a pas le geste ; une fiche le lui accorde', (t) async {
    await monter(t, SourceFausse(), role: 'role-cree-en-exploitation');
    expect(find.byKey(const Key('rep:sans-droit')), findsOneWidget);
    expect(find.byKey(const Key('rep:generer:uuid-caisse-0001')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await monter(t, SourceFausse(), role: 'role-cree-en-exploitation', accorderLeGeste: true);
    expect(find.byKey(const Key('rep:sans-droit')), findsNothing);
    expect(find.byKey(const Key('rep:generer:uuid-caisse-0001')), findsOneWidget, reason: 'la fiche de rôle accorde le geste : réglable en matrice, jamais un nom de rôle');
  });
}
