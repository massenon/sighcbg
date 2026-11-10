import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/mere/mrb_indicateurs.dart';
import 'package:sigh_poste/modules/mere/mrb_indicateurs_clinique.dart';
import 'package:sigh_poste/modules/mere/mrb_source.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';

/// Direction, 09/11/2026 (ADR-0007) : aux Paramètres de la mère, l'interrupteur « publier les indicateurs au relais » (fermé par défaut), l'intervalle, et le
/// contenu EXACT du dernier instantané publié — la Direction voit CE QUI PART.
class Source extends MrbSource {
  Source({this.publier = false, this.intervalleS = 900, this.dernier, this.envoyeLe, this.erreur, this.relaisConfigure = true});
  bool publier;
  int intervalleS;
  Map<String, Object?>? dernier;
  DateTime? envoyeLe;
  String? erreur;
  bool relaisConfigure;
  final appels = <String>[];

  @override
  Future<MrbEtat> etat() async => const MrbEtat(epoch: 1, seqMax: 1, repSeq: 1, reinitOuverte: false, alertes: [], bloques: [], derives: [], appareils: []);
  @override
  Future<MrbSante> supervision() async => const MrbSante(etat: 'ok', depot: 'pg', controles: []);
  @override
  Future<List<MrbLigneJournal>> journal({int limite = 500}) async => const [];
  @override
  Future<int?> patientsActifs() async => 3;
  @override
  Future<String> sauvegarderMaintenant() async => '';
  @override
  Future<void> debloquer(String uuid) async {}
  @override
  Future<void> revoquer(String uuid) async {}
  @override
  Future<void> ouvrirFenetreReinit(bool ouvrir) async {}
  @override
  Future<MrbResultatReinit> reinitialiser({required String confirmation, required String second, String motif = '', bool supprimer = false}) async => throw UnimplementedError();
  @override
  Future<MrbCodeMobile> codeMobile(String etiquette, {required String profil, String? fonction}) async => throw UnimplementedError();

  @override
  Future<MrbIndicateursClinique?> indicateursClinique() async => MrbIndicateursClinique(
      publier: publier, intervalleS: intervalleS, joursPeremption: 90, relaisConfigure: relaisConfigure, dernier: dernier, envoyeLe: envoyeLe, erreur: erreur);

  @override
  Future<Map<String, Object?>?> apercuIndicateursClinique() async => ikCalculer(IkEntree(collections: const {}, maintenant: DateTime.utc(2026, 11, 9)));

  @override
  Future<void> reglerIndicateursClinique({bool? publier, int? intervalleS, int? joursPeremption}) async {
    appels.add('regler publier=$publier intervalle=$intervalleS jours=$joursPeremption');
    if (publier != null) this.publier = publier;
    if (intervalleS != null) this.intervalleS = intervalleS;
  }

  @override
  Future<String?> publierIndicateursClinique() async {
    appels.add('publier');
    return publier ? null : 'interrupteur_ferme';
  }
}

const instantane = <String, Object?>{
  'schema': 1,
  'genere_le': 1794218400000,
  'version_application': '1.4.2',
  'etat_jeu': 'demonstration',
  'patients': {'actifs': 120, 'nouveaux_mois': 7},
  'facturation_mois': {'factures_emises': 31, 'montant_facture': 1520000, 'montant_encaisse': 980000, 'reste_du': 540000},
  'postes': [
    {'appareil': 'poste-a1', 'derniere_synchro': 1794218000000}
  ],
};

Future<Source> monter(WidgetTester t, Source s, {Droit droit = const Droit(voir: true, editer: true, annuler: true)}) async {
  mrbSourceInjectee = s;
  mrbIntervalle = const Duration(hours: 1);
  addTearDown(() => mrbSourceInjectee = null);
  t.view.physicalSize = const Size(1500, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: ContexteEcran(
                  ecranId: 'mere-indicateurs',
                  role: 'admin',
                  droit: droit,
                  magasin: Magasin(),
                  utilisateur: 'Mme TACHEDI',
                  aller: (_) {},
                  horloge: () => DateTime(2026, 11, 9, 12),
                  child: const EcranIndicateursPublies())))));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  return s;
}

String texte(WidgetTester t) => [for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? '', for (final w in t.widgetList<SelectableText>(find.byType(SelectableText))) w.data ?? ''].join('\n');

void main() {
  setUpAll(chargerPolices);

  testWidgets('par défaut : interrupteur FERMÉ, « jamais publié » en toutes lettres, intervalle par défaut', (t) async {
    await monter(t, Source());
    expect(t.widget<Checkbox>(find.byKey(const Key('mrb:interrupteur-indicateurs'))).value, isFalse);
    expect(find.textContaining('FERMÉ (aucun instantané ne part)'), findsOneWidget);
    expect(find.byKey(const Key('mrb:jamais-publie')), findsOneWidget);
    expect(find.textContaining('Jamais publié : l’interrupteur est fermé'), findsOneWidget);
    expect(find.byKey(const Key('mrb:dernier-instantane')), findsNothing);
    expect(find.text('Toutes les 15 minutes (défaut)'), findsOneWidget);
  });

  testWidgets('ouvrir l\'interrupteur appelle le service avec « publier » seul ; fermé, « Publier maintenant » est inactif', (t) async {
    final s = await monter(t, Source());
    expect(t.widget<BoutonSigh>(find.byKey(const Key('mrb:publier-maintenant'))).onPressed, isNull);
    await t.tap(find.byKey(const Key('mrb:interrupteur-indicateurs')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pump(const Duration(seconds: 10));
    expect(s.appels, ['regler publier=true intervalle=null jours=null']);
    expect(find.textContaining('OUVERT'), findsOneWidget);
    expect(t.widget<BoutonSigh>(find.byKey(const Key('mrb:publier-maintenant'))).onPressed, isNotNull);
  });

  testWidgets('l\'intervalle se règle : la valeur choisie part au service', (t) async {
    final s = await monter(t, Source());
    t.widget<SelecteurSigh>(find.byKey(const Key('mrb:intervalle-indicateurs'))).surChange('3600');
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pump(const Duration(seconds: 10));
    expect(s.appels, ['regler publier=null intervalle=3600 jours=null']);
  });

  testWidgets('une valeur en base hors de la liste proposée s\'affiche, elle n\'est pas remplacée en silence', (t) async {
    await monter(t, Source(intervalleS: 420));
    expect(find.text('Toutes les 7 minutes'), findsOneWidget);
  });

  testWidgets('le contenu EXACT du dernier instantané publié est affiché, avec sa date', (t) async {
    await monter(t, Source(publier: true, dernier: instantane, envoyeLe: DateTime(2026, 11, 9, 11, 45)));
    final affiche = t.widget<SelectableText>(find.byKey(const Key('mrb:dernier-instantane'))).data!;
    expect(jsonDecode(affiche), instantane, reason: 'ce qui est affiché est exactement ce qui est parti');
    expect(find.text('Dernier instantané publié le 09/11/2026 11:45'), findsOneWidget);
    expect(find.byKey(const Key('mrb:jamais-publie')), findsNothing);
  });

  testWidgets('interrupteur ouvert mais rien encore parti : le dit autrement que « jamais publié »', (t) async {
    await monter(t, Source(publier: true));
    expect(find.textContaining('Aucun instantané n’est encore parti'), findsOneWidget);
  });

  testWidgets('un refus du relais est affiché avec son motif', (t) async {
    await monter(t, Source(publier: true, erreur: 'signature_invalide — Signature refusée.'));
    expect(find.textContaining('signature_invalide'), findsOneWidget);
  });

  testWidgets('sans relais configuré, l\'écran prévient que rien ne peut partir', (t) async {
    await monter(t, Source(relaisConfigure: false));
    expect(find.textContaining('Aucun relais n’est configuré sur cette mère'), findsOneWidget);
  });

  testWidgets('« Voir ce qui partirait » affiche l\'aperçu calculé et le verdict de conformité, sans rien envoyer', (t) async {
    final s = await monter(t, Source());
    await t.tap(find.byKey(const Key('mrb:voir-apercu')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('mrb:apercu-instantane')), findsOneWidget);
    expect(s.appels, isEmpty);
    expect(find.textContaining('Conforme au schéma'), findsOneWidget);
  });

  testWidgets('sans droit d\'écriture : tout se lit, rien ne se règle', (t) async {
    final s = await monter(t, Source(publier: true, dernier: instantane, envoyeLe: DateTime(2026, 11, 9, 11, 45)), droit: const Droit(voir: true, editer: false, annuler: false));
    expect(t.widget<Checkbox>(find.byKey(const Key('mrb:interrupteur-indicateurs'))).onChanged, isNull);
    expect(find.byKey(const Key('mrb:publier-maintenant')), findsNothing);
    expect(find.textContaining('Lecture seule'), findsOneWidget);
    expect(find.byKey(const Key('mrb:dernier-instantane')), findsOneWidget);
    expect(s.appels, isEmpty);
  });

  testWidgets('un service sans cette publication (ancienne mère) : « non disponible », aucun réglage fantôme', (t) async {
    mrbSourceInjectee = _Ancienne();
    mrbIntervalle = const Duration(hours: 1);
    addTearDown(() => mrbSourceInjectee = null);
    t.view.physicalSize = const Size(1500, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ContexteEcran(
                    ecranId: 'mere-indicateurs',
                    role: 'admin',
                    droit: const Droit(voir: true, editer: true, annuler: true),
                    magasin: Magasin(),
                    utilisateur: 'x',
                    aller: (_) {},
                    horloge: () => DateTime(2026, 11, 9),
                    child: const CarteIndicateursClinique())))));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('ne propose pas la publication des indicateurs agrégés'), findsOneWidget);
    expect(find.byKey(const Key('mrb:interrupteur-indicateurs')), findsNothing);
  });

  test('l\'adaptateur HTTP lit les réglages et le dernier envoi, et envoie les bons corps', () async {
    final vus = <String>[];
    final client = ClientMere(
        base: Uri.parse('http://x'),
        secretAdmin: 's',
        client: MockClient((r) async {
          vus.add('${r.method} ${r.url.path} ${r.body}');
          if (r.url.path == '/admin/indicateurs-clinique') {
            return http.Response(
                jsonEncode({
                  'reglages': {'publier': true, 'intervalle_s': 300, 'jours_peremption': 60, 'defauts': {'publier': false, 'intervalle_s': 900, 'jours_peremption': 90}},
                  'relais_configure': true,
                  'dernier': {'envoye_le': 1794218400000, 'instantane': instantane},
                  'derniere_tentative_ms': 1794218400000,
                  'erreur': null,
                }),
                200);
          }
          if (r.url.path.endsWith('/publier')) return http.Response('{"publie":false,"raison":"interrupteur_ferme"}', 200);
          return http.Response('{}', 200);
        }));
    final source = MrbSourceClient(client);
    final e = (await source.indicateursClinique())!;
    expect((e.publier, e.intervalleS, e.joursPeremption, e.defautIntervalleS, e.relaisConfigure), (true, 300, 60, 900, true));
    expect(e.dernier, instantane);
    expect(e.envoyeLe, DateTime.fromMillisecondsSinceEpoch(1794218400000));
    await source.reglerIndicateursClinique(publier: false, intervalleS: 60);
    expect(await source.publierIndicateursClinique(), 'interrupteur_ferme');
    expect(vus, contains('POST /admin/indicateurs-clinique/reglages {"publier":false,"intervalle_s":60}'));
  });

  test('l\'adaptateur refuse une réponse sans réglages (ancienne mère ou autre service)', () async {
    final client = ClientMere(base: Uri.parse('http://x'), secretAdmin: 's', client: MockClient((r) async => http.Response('{"x":1}', 200)));
    await expectLater(MrbSourceClient(client).indicateursClinique(), throwsA(isA<ErreurMere>().having((x) => x.code, 'code', 'reponse_inattendue')));
  });

  test('les libellés d\'intervalle', () {
    expect(mrbLibelleIntervalle(60), 'Toutes les minutes');
    expect(mrbLibelleIntervalle(900), 'Toutes les 15 minutes');
    expect(mrbLibelleIntervalle(3600), 'Toutes les heures');
    expect(mrbLibelleIntervalle(21600), 'Toutes les 6 heures');
    expect(mrbLibelleIntervalle(86400), 'Une fois par jour');
    expect(mrbLibelleIntervalle(90), 'Toutes les 90 secondes');
  });
}

class _Ancienne extends Source {
  @override
  Future<MrbIndicateursClinique?> indicateursClinique() async => null;
}
