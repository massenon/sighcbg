import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show AccParametresHachage;
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/identifiants.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/auth/acc_session.dart';
import 'package:sigh_poste/shell/coque.dart';

import 'aide_polices.dart';

/// CAPTURES DU MANUEL D'UTILISATION (docs/manuels/src/utilisateur) : ouvre les écrans clés du poste sur le jeu de démonstration et écrit, pour chacun,
/// un PNG et un JSON des repères (rectangles des boutons, des clés et des onglets) qui servent à placer les flèches automatiquement.
/// Sur demande seulement : `SIGH_CAPTURES=/chemin flutter test test/capture_manuel_test.dart`.
final String? _sortie = Platform.environment['SIGH_CAPTURES'];
final _donnees = DonneesNavigation.depuisDossier();
final _le = DateTime(2026, 11, 16, 10);
const _taille = Size(1440, 900);

typedef Geste = Future<void> Function(WidgetTester t);

class _Cap {
  const _Cap(this.nom, this.ecran,
      {this.role = 'admin', this.gestes = const [], this.session, this.jeuDeTest = false, this.taille = _taille, this.mode = ModePoste.fileul, this.posteNeuf = false});

  /// Taille logique de la fenêtre (les écrans longs — configuration fiscale, planning individuel — se photographient en hauteur).
  final Size taille;
  final ModePoste mode;

  /// Un poste NEUF (aucun compte) dont l'assistant d'installation est attaché : premier lancement, première installation, rejoindre une clinique.
  final bool posteNeuf;

  /// Quelques files (dispensation, file d'attente, comptes rendus en cours) sont vides dans le jeu livré : ces captures lisent le jeu de test.
  final bool jeuDeTest;
  final String nom;
  final String? ecran;
  final String role;
  final List<Geste> gestes;
  final SessionPoste Function()? session;
}

Future<void> _pomper(WidgetTester t, [int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

Geste toucherCle(String cle) => (t) async {
      final f = find.byKey(Key(cle));
      if (f.evaluate().isEmpty) return;
      await t.tap(f.first, warnIfMissed: false);
      await _pomper(t);
    };

Geste toucherBouton(String libelle) => (t) async {
      final f = find.widgetWithText(BoutonSigh, libelle);
      if (f.evaluate().isEmpty) return;
      await t.ensureVisible(f.first);
      await t.pump();
      await t.tap(f.first, warnIfMissed: false);
      await _pomper(t, 6);
    };

Geste toucherTexte(String texte) => (t) async {
      final f = find.text(texte);
      if (f.evaluate().isEmpty) return;
      await t.tap(f.first, warnIfMissed: false);
      await _pomper(t, 6);
    };

Geste toucherIcone(String libelle) => (t) async {
      final f = find.byWidgetPredicate((w) => w is BoutonIcone && w.libelle == libelle);
      if (f.evaluate().isEmpty) return;
      await t.ensureVisible(f.first);
      await t.pump();
      await t.tap(f.first, warnIfMissed: false);
      await _pomper(t, 6);
    };

/// Laisse tourner les calculs asynchrones (hachage du mot de passe à la création du premier compte).
Geste attendre([int n = 8]) => (t) async {
      for (var i = 0; i < n; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await t.pump(const Duration(milliseconds: 50));
      }
      await _pomper(t, 4);
    };

/// Un bouton du kit OU une icône d'action, désigné par son libellé.
Geste toucherLibelle(String libelle) => (t) async {
      if (find.widgetWithText(BoutonSigh, libelle).evaluate().isNotEmpty) return toucherBouton(libelle)(t);
      return toucherIcone(libelle)(t);
    };

/// Remplit un champ du kit (`kit:champ:<nom>`).
Geste champ(String nom, String texte) => (t) async {
      final f = find.descendant(of: find.byKey(Key('kit:champ:$nom')), matching: find.byType(TextField));
      if (f.evaluate().isEmpty) return;
      await t.enterText(f.first, texte);
      await _pomper(t, 2);
    };

/// Choisit une option d'une liste du kit (`kit:champ:<nom>`) : ouvre la liste puis touche le libellé.
Geste choisir(String nom, String libelle) => (t) async {
      final f = find.byKey(Key('kit:champ:$nom'));
      if (f.evaluate().isEmpty) return;
      final cible = find.descendant(of: f, matching: find.byWidgetPredicate((w) => w is DropdownButton || w is InkWell || w is GestureDetector));
      await t.tap(cible.evaluate().isEmpty ? f.first : cible.first, warnIfMissed: false);
      await _pomper(t, 6);
      final o = find.text(libelle);
      if (o.evaluate().isEmpty) return;
      await t.tap(o.last, warnIfMissed: false);
      await _pomper(t, 6);
    };

/// Ferme les modales ouvertes (touche Échap).
Geste fermerModales() => (t) async {
      for (var i = 0; i < 2; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await _pomper(t, 4);
      }
    };

const _secretDemo = 'Demonstration#Parakou26';

/// La création du premier administrateur sur un poste neuf (nom fictif), jusqu'à l'affichage du code de secours.
final _premierCompte = <Geste>[
  toucherCle('ins:premiere'),
  saisir('ins:nom', 'ADMINISTRATEUR Démonstration'),
  saisir('ins:identifiant', 'admin.demo'),
  saisir('ins:motdepasse', _secretDemo),
  saisir('ins:confirmation', _secretDemo),
  toucherCle('ins:creer'),
  attendre(),
];

/// Coche les [n] premières lignes d'un tableau du kit (case « Sélectionner la ligne »).
Geste cocherLignes(int n) => (t) async {
      final f = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Sélectionner la ligne');
      for (var i = 0; i < n && i < f.evaluate().length; i++) {
        await t.tap(f.at(i), warnIfMissed: false);
        await _pomper(t, 2);
      }
    };

Geste saisir(String cle, String texte) => (t) async {
      final f = find.byKey(Key(cle));
      if (f.evaluate().isEmpty) return;
      await t.enterText(f.first, texte);
      await _pomper(t, 2);
    };

final _captures = <_Cap>[
  _Cap('01-connexion', 'index', session: () => SessionPoste(exigeConnexion: true, horloge: () => _le)),
  _Cap('02-verrou', 'auth-lock', session: () => SessionPoste(exigeConnexion: true, horloge: () => _le)),
  _Cap('03-accueil-tableau', 'dash-receptionniste', role: 'reception'),
  _Cap('04-ruban-accueil', 'dash-receptionniste', role: 'reception', gestes: [toucherCle('domaine-Accueil')]),
  _Cap('05-recherche', 'dash-receptionniste', role: 'reception', gestes: [toucherCle('recherche-globale'), saisir('recherche-champ', 'para')]),
  _Cap('06-notifications', 'dash-receptionniste', role: 'reception', gestes: [toucherCle('barre-cloche')]),
  _Cap('07-profil', 'dash-receptionniste', role: 'reception', gestes: [toucherCle('barre-profil')]),
  _Cap('09-assistant', 'sup-assistant', role: 'reception'),
  _Cap('10-patients', 'm1-patients', role: 'reception'),
  _Cap('17-tableau-selection', 'm6-stock-detail', gestes: [cocherLignes(3)]),
  _Cap('18-export', 'm6-stock-detail', gestes: [cocherLignes(3), toucherBouton('Exporter la sélection')]),
  _Cap('19-patient-profil', 'm1-patient-profil', role: 'medecin'),
  _Cap('12b-rdv-nouveau', 'm2-rendezvous', role: 'reception', gestes: [toucherBouton('Nouveau')]),
  _Cap('35-delivrer', 'm6-dispensation', gestes: [toucherIcone('Délivrer')], jeuDeTest: true),
  _Cap('36-inventaire-feuille', 'm6-inventaire-feuille'),
  _Cap('40b-besoin-nouveau', 'm7-besoins', gestes: [toucherBouton('Nouveau bon')]),
  _Cap('57-encaisser', 'm8-caisse', gestes: [toucherIcone('Encaisser')]),
  _Cap('85-ecriture-nouvelle', 'm12-ecritures', gestes: [toucherBouton('Nouvelle écriture')]),
  _Cap('11-patient-nouveau', 'm1-patient-nouveau', role: 'reception'),
  _Cap('13-file-attente', 'm2-file-attente', role: 'reception', jeuDeTest: true),
  _Cap('14-externe', 'm1-externe', role: 'reception'),
  _Cap('15-certificats', 'm1-pieces', role: 'reception'),
  _Cap('16-constantes', 'm1-constantes', role: 'reception'),
  _Cap('20-dossiers-consultation', 'm2-dossiers-consultation', role: 'medecin'),
  _Cap('21-fiche-consultation', 'm2-consultation-fiche', role: 'medecin'),
  _Cap('22-ordonnances', 'm2-ordonnances', role: 'medecin'),
  _Cap('23-imagerie-demandes', 'm2-imagerie-demandes', role: 'medecin', jeuDeTest: true),
  _Cap('24-admissions', 'm3-admissions', role: 'medecin'),
  _Cap('25-bloc-cro', 'm3-bloc-cro', role: 'medecin'),
  _Cap('26-dossier-obstetrical', 'm4-dossier-obstetrical'),
  _Cap('28-prelevement', 'm5-prelevement'),
  _Cap('29-resultats', 'm5-resultats'),
  _Cap('30-dispensation', 'm6-dispensation', jeuDeTest: true),
  _Cap('31-stock-detail', 'm6-stock-detail'),
  _Cap('32-lots', 'm6-lots'),
  _Cap('34-transferts', 'm6-transferts'),
  _Cap('41-commandes', 'm7-commandes'),
  _Cap('42-livraisons', 'm7-livraisons'),
  _Cap('43-factures-fournisseurs', 'm7-factures-fournisseurs'),
  _Cap('50-facturation', 'm8-facturation'),
  _Cap('52-paiements', 'm8-paiements'),
  _Cap('53-avoirs', 'm8-facture-avoir'),
  _Cap('56-mecef-config', 'mecef-config', taille: Size(1440, 2600)),
  _Cap('60-assures', 'm9-assures'),
  _Cap('62-factures-assureur', 'm9-factures-assureur'),
  _Cap('70-personnel', 'm10-personnel'),
  _Cap('72-conges', 'm10-conges'),
  _Cap('73-mon-espace', 'm10-mes'),
  _Cap('74-paie-calcul', 'm11-calcul'),
  _Cap('82-grand-livre', 'm12-grand-livre'),
  _Cap('83-cloture', 'm12-cloture'),
  _Cap('90-direction', 'dash-direction'),
  _Cap('91-dash-caissier', 'dash-caissier', role: 'caissier'),
  // ---- Assistant d'installation du poste (poste neuf, aucun compte).
  _Cap('100-ins-accueil', 'index', posteNeuf: true, session: () => SessionPoste(exigeConnexion: true, horloge: () => _le)),
  _Cap('101-ins-premiere', 'index', posteNeuf: true, session: () => SessionPoste(exigeConnexion: true, horloge: () => _le), gestes: [toucherCle('ins:premiere')]),
  _Cap('102-ins-secours', 'index', posteNeuf: true, session: () => SessionPoste(exigeConnexion: true, horloge: () => _le), gestes: _premierCompte),
  _Cap('103-ins-configurations', 'index',
      posteNeuf: true,
      session: () => SessionPoste(exigeConnexion: true, horloge: () => _le),
      gestes: [..._premierCompte, toucherCle('ins:range'), toucherCle('ins:suite'), attendre(4)]),
  _Cap('104-ins-rejoindre', 'index', posteNeuf: true, session: () => SessionPoste(exigeConnexion: true, horloge: () => _le), gestes: [toucherCle('ins:rejoindre')]),
  // ---- Sauvegarde.
  _Cap('110-sauvegardes', 'm14-sauvegardes', taille: Size(1440, 1700)),
  _Cap('111-hors-site', 'm14-sauvegardes', taille: Size(1440, 2800)),
  // ---- Caisse : reçu, ticket, impression de la sélection.
  _Cap('58-recu', 'm8-caisse', gestes: [toucherIcone('Réimprimer le reçu détaillé')]),
  _Cap('59-ticket', 'm8-facturation', gestes: [toucherBouton('Ticket de caisse')]),
  _Cap('19b-imprimer-selection', 'm8-paiements', gestes: [cocherLignes(2), toucherBouton('Imprimer la sélection')]),
  // ---- Satisfaction en ligne.
  _Cap('120-enquetes', 'adm-enquetes'),
  _Cap('121-enquete-partager', 'adm-enquetes', gestes: [toucherLibelle('Partager à un tiers'), choisir('usage', 'Sur Internet, par le relais — depuis chez soi (anonyme, chiffré)')]),
  _Cap('122-enquete-liens', 'adm-enquetes', gestes: [toucherTexte('Liens de partage')]),
  _Cap('123-enquete-qr', 'adm-enquetes', taille: Size(1440, 1100), gestes: [
    toucherLibelle('Partager à un tiers'),
    choisir('usage', 'Sur Internet, par le relais — depuis chez soi (anonyme, chiffré)'),
    toucherBouton('Ouvrir le lien'),
    attendre(4),
  ]),
  _Cap('123b-enquete-liens', 'adm-enquetes', gestes: [
    toucherLibelle('Partager à un tiers'),
    choisir('usage', 'Sur Internet, par le relais — depuis chez soi (anonyme, chiffré)'),
    toucherBouton('Ouvrir le lien'),
    attendre(4),
    fermerModales(),
    toucherTexte('Liens de partage (1)'),
  ]),
  _Cap('124-satisfaction', 'adm-satisfaction'),
  // ---- Planning individuel (fiche du personnel).
  // Jeu de TEST : le personnel du jeu livré porte les vrais agents de la clinique, le jeu de test des noms fictifs.
  _Cap('130-planning-individuel', 'm10-employe-profil', jeuDeTest: true, taille: Size(1440, 1500), gestes: [toucherTexte('Planning individuel')]),
  _Cap('131-planning-deroger', 'm10-employe-profil', jeuDeTest: true, taille: Size(1440, 1500), gestes: [toucherTexte('Planning individuel'), toucherBouton('Déroger')]),
  // ---- SMS (poste mère).
  _Cap('140-sms-passerelle', 'mere-sms-passerelle', mode: ModePoste.mere, taille: Size(1440, 1200)),
  _Cap('141-sms-journal', 'mere-sms-journal', mode: ModePoste.mere),
];

List<double> _rect(Rect r) => [r.left, r.top, r.width, r.height].map((v) => (v * 10).roundToDouble() / 10).toList();

Size _tailleCourante = _taille;

bool _visible(Rect r) => r.width > 0 && r.height > 0 && r.right > 0 && r.bottom > 0 && r.left < _tailleCourante.width && r.top < _tailleCourante.height;

/// Les repères de l'écran : boutons du kit (libellé), clés textuelles, infobulles, onglets.
Map<String, Object?> _reperes(WidgetTester t) {
  final boutons = <Map<String, Object?>>[];
  for (final e in find.byType(BoutonSigh).evaluate()) {
    final w = e.widget as BoutonSigh;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (_visible(r)) boutons.add({'libelle': w.libelle, 'rect': _rect(r)});
  }
  for (final e in find.byType(BoutonIcone).evaluate()) {
    final w = e.widget as BoutonIcone;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (_visible(r)) boutons.add({'libelle': w.libelle, 'icone': true, 'rect': _rect(r)});
  }
  for (final e in find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith('Sélectionner')).evaluate()) {
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (_visible(r)) boutons.add({'libelle': (e.widget as Semantics).properties.label, 'case': true, 'rect': _rect(r)});
  }
  final cles = <String, Object?>{};
  for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String>).evaluate()) {
    final k = (e.widget.key as ValueKey<String>).value;
    if (k.startsWith('[') || cles.containsKey(k)) continue;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (_visible(r)) cles[k] = _rect(r);
  }
  final infos = <Map<String, Object?>>[];
  for (final e in find.byType(Tooltip).evaluate()) {
    final w = e.widget as Tooltip;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached || (w.message ?? '').isEmpty) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (_visible(r)) infos.add({'message': w.message, 'rect': _rect(r)});
  }
  final onglets = <Map<String, Object?>>[];
  for (final e in find.byType(Tab).evaluate()) {
    final w = e.widget as Tab;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (_visible(r)) onglets.add({'libelle': w.text ?? '', 'rect': _rect(r)});
  }
  // Aucun texte de l'écran n'est écrit (noms de patients) : seuls les repères géométriques servent aux flèches.
  return {'boutons': boutons, 'cles': cles, 'infobulles': infos, 'onglets': onglets};
}

void main() {
  setUpAll(() async {
    await chargerPolices();
    // Le hachage d'essai (rapide) : la création du premier compte de l'assistant d'installation ne prend pas de longues secondes.
    ServiceIdentifiants.parametres = AccParametresHachage.tests;
  });
  setUp(() => CoquePoste.panneauOuvertAuDemarrage = false);
  tearDown(ToastsSigh.viderPourTests);

  for (final c in _captures) {
    testWidgets('capture manuel : ${c.nom}', skip: _sortie == null, (t) async {
      _tailleCourante = c.taille;
      t.view.physicalSize = c.taille;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      Magasin? neuf;
      if (c.posteNeuf) {
        neuf = Magasin.depuisDossier(const ['audit', 'utilisateurs', 'rbac', 'tentativesConnexion', 'personnel', 'soignants', 'rolesBase', 'support'], 'assets/donnees/jeu');
        await t.runAsync(() => ServiceInstallation.de(neuf!).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'poste-demo')));
      }
      await t.pumpWidget(RepaintBoundary(
          key: const Key('cap-manuel'),
          child: SighPoste(
              key: UniqueKey(),
              donnees: _donnees,
              config: ConfigPoste(mode: c.mode, role: c.role),
              ecranInitial: c.ecran,
              // Le jeu de démonstration LIVRÉ avec le poste (assets/donnees/jeu) : noms fictifs de Baguidi, jamais le jeu de test.
              magasin: neuf ?? Magasin.depuisDossier(Magasin.collectionsDuJeu, c.jeuDeTest ? null : 'assets/donnees/jeu'),
              session: c.session?.call(),
              horloge: () => _le)));
      await _pomper(t, 6);
      for (final g in c.gestes) {
        await g(t);
      }
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await _pomper(t, 2);
      final reperes = _reperes(t);
      await t.runAsync(() async {
        final RenderRepaintBoundary b = t.renderObject(find.byKey(const Key('cap-manuel')));
        final ui.Image img = await b.toImage(pixelRatio: 1.25);
        final d = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory(_sortie!).createSync(recursive: true);
        File('$_sortie/${c.nom}.png').writeAsBytesSync(d!.buffer.asUint8List());
        File('$_sortie/${c.nom}.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
          'nom': c.nom,
          'ecran': c.ecran,
          'role': c.role,
          'taille': [c.taille.width, c.taille.height],
          'echelle': 1.25,
          ...reperes,
        }));
      });
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });
  }
}
