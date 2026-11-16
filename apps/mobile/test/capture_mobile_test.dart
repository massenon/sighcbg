// CAPTURES DU MANUEL D'UTILISATION — APPLICATION MOBILE (docs/manuels/src/utilisateur, chapitre « L'application mobile »).
//
// Ouvre les écrans du téléphone sur les lots de démonstration des tests (noms FICTIFS, faux moteur, VRAI service soignant) et écrit, pour chacun, un PNG
// et un JSON des repères (rectangles des clés, des infobulles et des onglets) qui placent les flèches du manuel. Couvre l'appairage, le code PIN, l'accueil
// de chaque profil et chaque écran du manifeste mobile (`mobEcransManifeste`) : dossier, constantes, consultation, prescription, demande d'analyse, CPN,
// CPoN, surveillance, nouveau dossier et dossiers créés, orientation, agenda — plus le lot, les réglages et « À traiter ».
//
// Sur demande seulement : `SIGH_CAPTURES=/chemin flutter test test/capture_mobile_test.dart`.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_mobile/main.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';

import 'aide_mobile.dart';
import 'aide_suite.dart';

final String? _sortie = Platform.environment['SIGH_CAPTURES'];
const _taille = Size(412, 900);

/// Les vraies polices (Inter de la charte, icônes Material du SDK) : sans elles, Flutter dessine des carrés.
Future<void> _polices() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(Future.value(ByteData.view(File('../poste/assets/polices/Inter-$f.otf').readAsBytesSync().buffer)));
  }
  await inter.load();
  final sdk = File(Platform.resolvedExecutable).parent.parent.parent.parent.path; // …/flutter/bin/cache/dart-sdk/bin/dart → …/flutter
  for (final chemin in ['$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf', '/opt/sdk/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']) {
    final f = File(chemin);
    if (!f.existsSync()) continue;
    final icones = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    await icones.load();
    break;
  }
}

typedef Geste = Future<void> Function(WidgetTester t);

Future<void> _pomper(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

Geste cle(String k) => (t) async {
      final f = find.byKey(Key(k));
      if (f.evaluate().isEmpty) return;
      await t.ensureVisible(f.first);
      await t.pump();
      await t.tap(f.first, warnIfMissed: false);
      await _pomper(t);
    };

Geste ecrire(String k, String texte) => (t) async {
      final f = find.byKey(Key(k));
      if (f.evaluate().isEmpty) return;
      await t.enterText(f.first, texte);
      await _pomper(t, 2);
    };

Geste frapper(String code) => (t) async {
      for (final k in code.split('')) {
        await t.tap(find.byKey(Key('touche-$k')));
        await t.pump();
      }
      await _pomper(t);
    };

/// Le dernier segment de la nature de prescription : la demande d'analyses.
Geste natureAnalyse() => (t) async {
      final f = find.descendant(of: find.byKey(const Key('nature')), matching: find.byType(Text));
      if (f.evaluate().isEmpty) return;
      await t.tap(f.last, warnIfMissed: false);
      await _pomper(t);
    };

class _Cap {
  const _Cap(this.nom, this.moteur, {this.gestes = const [], this.coffre, this.hauteur = 900});
  final String nom;
  final FauxMoteur Function() moteur;
  final List<Geste> gestes;
  final CoffrePin Function()? coffre;
  final double hauteur;
}

FauxMoteurSuite _soignant(String fonction, {SourceMemoire? source, String agent = 'Agent de démonstration'}) =>
    FauxMoteurSuite(fonction: fonction, agent: agent, source: source ?? lotDeDemonstration())..profil = ProfilMobile.soignant;

FauxMoteurSuite _reception() => FauxMoteurSuite(source: accueilDeSecours(), agentReception: 'Accueil de démonstration')..profil = ProfilMobile.receptionSecours;

final _dossierP1 = <Geste>[cle('onglet-dossiers'), cle('patient-p1')];
final _dossierP4 = <Geste>[cle('onglet-dossiers'), cle('patient-p4')];

final _captures = <_Cap>[
  // L'appairage : le téléphone n'a encore aucun profil.
  _Cap('m01-appairage', () => FauxMoteurSuite(fonction: 'medecin')),
  _Cap('m01b-appairage-saisi', () => FauxMoteurSuite(fonction: 'medecin'),
      gestes: [ecrire('code', 'ABCD2345'), ecrire('cle', 'Y2xlLWRlLWNsaW5pcXVl'), ecrire('agent', 'Agent de démonstration')]),
  // Le code PIN : premier choix, puis déverrouillage.
  _Cap('m02-pin-choix', () => _soignant('medecin'), coffre: () => CoffrePinMemoire()),
  _Cap('m03-pin', () => _soignant('medecin'), coffre: () => CoffrePinMemoire('1234')),
  // L'accueil du médecin (soignant) : l'agenda du jour, puis les dossiers du lot.
  _Cap('m04-accueil-agenda', () => _soignant('medecin')),
  _Cap('m05-dossiers-lot', () => _soignant('medecin'), gestes: [cle('onglet-dossiers')]),
  _Cap('m06-dossier', () => _soignant('medecin'), gestes: _dossierP1, hauteur: 1500),
  _Cap('m07-constantes', () => _soignant('medecin'), gestes: [..._dossierP1, cle('saisir-constantes')], hauteur: 1100),
  _Cap('m08-consultation', () => _soignant('medecin'), gestes: [..._dossierP1, cle('nouvelle-note')], hauteur: 1150),
  _Cap('m09-prescription', () => _soignant('medecin'), gestes: [..._dossierP1, cle('prescrire')]),
  _Cap('m10-demande-analyse', () => _soignant('medecin'), gestes: [..._dossierP1, cle('prescrire'), natureAnalyse()], hauteur: 1100),
  // La sage-femme : ses trois écrans partent du dossier.
  _Cap('m11-accueil-sagefemme', () => _soignant('sage_femme', source: lotSageFemme(), agent: 'Sage-femme de garde')),
  _Cap('m12-dossier-sagefemme', () => _soignant('sage_femme', source: lotSageFemme(), agent: 'Sage-femme de garde'), gestes: _dossierP4, hauteur: 1600),
  _Cap('m13-cpn', () => _soignant('sage_femme', source: lotSageFemme(), agent: 'Sage-femme de garde'), gestes: [..._dossierP4, cle('ouvrir-cpn')], hauteur: 1300),
  _Cap('m14-cpon', () => _soignant('sage_femme', source: lotSageFemme(), agent: 'Sage-femme de garde'), gestes: [..._dossierP4, cle('ouvrir-cpon')], hauteur: 1300),
  _Cap('m15-surveillance', () => _soignant('sage_femme', source: lotSageFemme(), agent: 'Sage-femme de garde'), gestes: [..._dossierP4, cle('ouvrir-surveillance')], hauteur: 1300),
  // La réception de secours : nouveau dossier, dossiers créés, orientation.
  _Cap('m16-reception', _reception, hauteur: 1200),
  _Cap('m16b-reception-cree', _reception, gestes: [ecrire('nom', 'NOUVEAU'), ecrire('prenom', 'Patient'), ecrire('age', '34'), cle('creer')], hauteur: 1200),
  _Cap('m17-orientation', _reception, gestes: [cle('orienter')]),
  // L'appareil : lot de tournée, réglages, refus à traiter.
  _Cap('m18-lot', () => _soignant('sage_femme', source: lotSageFemme(), agent: 'Sage-femme de garde'), gestes: [cle('ouvrir-lot')]),
  _Cap('m19-reglages', () => _soignant('medecin'), gestes: [cle('ouvrir-reglages')], hauteur: 1100),
  _Cap('m20-a-traiter', () {
    final m = FauxMoteur(refusATraiter: const [
      RefusAffiche(operation: 'op1', code: 'droit_refuse', motif: 'Infirmier(ère) n’est pas habilité à prescrire « Médicaments ».', geste: 'Demander la prescription à un médecin')
    ], fonction: 'infirmier', agent: 'Agent de démonstration')
      ..profil = ProfilMobile.soignant;
    m.etat.value = const EtatMobile(horsLigne: false, aTraiter: 1);
    return m;
  }),
  _Cap('m20b-bandeau', () {
    final m = FauxMoteur(refusATraiter: const [
      RefusAffiche(operation: 'op1', code: 'droit_refuse', motif: 'Infirmier(ère) n’est pas habilité à prescrire « Médicaments ».', geste: 'Demander la prescription à un médecin')
    ], fonction: 'infirmier', agent: 'Agent de démonstration')
      ..profil = ProfilMobile.soignant;
    m.etat.value = const EtatMobile(horsLigne: false, aTraiter: 1);
    return m;
  }, gestes: [cle('bandeau')]),
];

List<double> _rect(Rect r) => [r.left, r.top, r.width, r.height].map((v) => (v * 10).roundToDouble() / 10).toList();

Map<String, Object?> _reperes(WidgetTester t, Size taille) {
  bool visible(Rect r) => r.width > 0 && r.height > 0 && r.right > 0 && r.bottom > 0 && r.left < taille.width && r.top < taille.height;
  Rect? rectDe(Element e) {
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    return visible(r) ? r : null;
  }

  final cles = <String, Object?>{};
  for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String>).evaluate()) {
    final k = (e.widget.key as ValueKey<String>).value;
    if (k.startsWith('[') || cles.containsKey(k)) continue;
    final r = rectDe(e);
    if (r != null) cles[k] = _rect(r);
  }
  // Les boutons Material (libellé du texte qu'ils portent) : « Saisir les constantes », « Enregistrer »…
  final boutons = <Map<String, Object?>>[];
  for (final e in find.byWidgetPredicate((w) => w is ButtonStyleButton).evaluate()) {
    final textes = find.descendant(of: find.byWidget(e.widget), matching: find.byType(Text)).evaluate().map((x) => (x.widget as Text).data ?? '').where((s) => s.isNotEmpty).toList();
    final r = rectDe(e);
    if (r != null && textes.isNotEmpty) boutons.add({'libelle': textes.first, 'rect': _rect(r)});
  }
  final infos = <Map<String, Object?>>[];
  for (final e in find.byType(Tooltip).evaluate()) {
    final w = e.widget as Tooltip;
    final r = rectDe(e);
    if (r != null && (w.message ?? '').isNotEmpty) infos.add({'message': w.message, 'rect': _rect(r)});
  }
  final onglets = <Map<String, Object?>>[];
  for (final e in find.byType(Tab).evaluate()) {
    final r = rectDe(e);
    if (r != null) onglets.add({'libelle': (e.widget as Tab).text ?? '', 'rect': _rect(r)});
  }
  return {'boutons': boutons, 'cles': cles, 'infobulles': infos, 'onglets': onglets};
}

void main() {
  setUpAll(_polices);

  for (final c in _captures) {
    testWidgets('capture mobile : ${c.nom}', skip: _sortie == null, (t) async {
      final taille = Size(_taille.width, c.hauteur);
      t.view.physicalSize = taille;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final m = c.moteur();
      await t.pumpWidget(RepaintBoundary(key: const Key('cap-mobile'), child: SighMobile(moteur: m, coffre: c.coffre?.call())));
      await _pomper(t, 8);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await _pomper(t, 4);
      for (final g in c.gestes) {
        await g(t);
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await _pomper(t, 3);
      }
      // Le défilement d'un `ensureVisible` est remis en haut : la capture montre l'écran tel qu'il s'ouvre.
      for (final s in find.byType(Scrollable).evaluate()) {
        final st = (s as StatefulElement).state as ScrollableState;
        if (st.position.pixels != 0) st.position.jumpTo(0);
      }
      await _pomper(t, 3);
      final reperes = _reperes(t, taille);
      await t.runAsync(() async {
        final RenderRepaintBoundary b = t.renderObject(find.byKey(const Key('cap-mobile')));
        final ui.Image img = await b.toImage(pixelRatio: 2);
        final d = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory(_sortie!).createSync(recursive: true);
        File('$_sortie/${c.nom}.png').writeAsBytesSync(d!.buffer.asUint8List());
        File('$_sortie/${c.nom}.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
          'nom': c.nom,
          'taille': [taille.width, taille.height],
          'echelle': 2,
          // Largeur de référence des flèches : un écran de téléphone se lit à part, ses flèches gardent une épaisseur lisible.
          'largeurReference': 520,
          ...reperes,
        }));
      });
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });
  }
}
