import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/impression/feuilles.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

/// Le magasin du jeu de démonstration LIVRÉ avec le poste (`assets/donnees/jeu`, celui que charge l'application) — et non la copie de test des bancs de parité,
/// qui est le défaut de `Magasin.depuisDossier`.
Magasin magasinLivre() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

/// Un PDF capturé par le crochet [ImpressionPoste.enregistrer].
class Capture {
  Capture(this.ecran, this.role, this.titre, this.reference, this.octets, this.geste, {this.module});

  /// Module de classement quand il diffère de celui de l'écran de montage (pièce produite par sa fabrique).
  final String? module;
  final String ecran;
  final String role;
  final String titre;
  final String reference;
  final List<int> octets;

  /// Le geste d'écran qui l'a produit (libellé du bouton, onglet, ligne ouverte).
  final String geste;
}

/// Ce que l'on tape pour déclencher une édition : libellés de boutons et d'icônes.
final RegExp declencheur = RegExp(
    r'(mprim|ditions? |^Éditer|dition de|perçu|Prévisualiser|^PDF|Ticket|^Reçu|Réimprimer|Rééditer|Bon de|Bordereau|Planche|Badge|Étiquette|Quittance|Certificat|Attestation|Bulletin|Ordonnance|Relevé|Compte rendu|Fiche d|^État |^Point (détaillé|global)|Notification de sanction|^Procès-verbal)',
    caseSensitive: false);

/// Commandes qui OUVRENT une modale ou un tiroir de consultation (sans écrire) : on les ouvre pour y chercher l'édition (bon de sortie, fiche, détail).
final RegExp ouvreur = RegExp(r'^(Préparer|Consulter|Voir|Détail|Ouvrir|Visualiser|Afficher|Composer|Rédiger|Fiche|Aperçu)', caseSensitive: false);

/// Libellés qu'il ne faut jamais taper, même s'ils ressemblent à un déclencheur (écritures, suppressions, envois).
final RegExp interdit = RegExp(r'(Relevé & facture|Générer|Lancer|Créer|Nouve|Ajouter|Annuler|Supprimer|Archiver|Restaurer|Valider|Clôturer|Envoyer|Transmettre|Réinitialiser|Régulariser|Encaisser|Enregistrer et|Éditions enregistrées|Importer|Sauvegarder|Restaurer)', caseSensitive: false);

bool bavard = Platform.environment['SIGH_BAVARD'] == '1';

class Explorateur {
  Explorateur(this.t, this.donnees, this.horloge);
  final WidgetTester t;
  final DonneesNavigation donnees;
  final DateTime Function() horloge;
  final List<Capture> captures = [];
  final List<String> notes = [];
  String _ecran = '', _role = '', _geste = '';
  Magasin? _magasin;
  final Set<String> _vus = {};

  Future<void> _laisser([int ms = 200]) async {
    await t.pump(Duration(milliseconds: ms));
    final e = t.takeException();
    if (e != null) {
      final txt = '$_ecran/$_geste : exception d’écran — ${'$e'.split('\n').first}';
      if (notes.length < 400 && !notes.contains(txt)) notes.add(txt);
    }
  }

  Future<void> ouvrir(String ecran, String role, Magasin m) async {
    _ecran = ecran;
    _role = role;
    _magasin = m;
    t.view.physicalSize = const Size(1600, 1100);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(SighPoste(
        key: UniqueKey(),
        donnees: donnees,
        config: ConfigPoste(mode: ModePoste.fileul, role: role),
        ecranInitial: ecran,
        magasin: m,
        horloge: horloge));
    for (var i = 0; i < 5; i++) {
      await _laisser(150);
    }
  }

  /// Chaîne lisible d'un widget cliquable : libellé d'un BoutonSigh ou d'un BoutonIcone.
  /// Libellés des raccourcis de navigation (écrans et rangées du ruban) : les taper changerait d'écran sous nos pieds, et ce n'est pas une édition.
  late final Set<String> _libellesNav = {
    for (final e in donnees.manifeste.tousLesEcrans) ...[e.label, if (donnees.titreDeclare(e.id) != null) donnees.titreDeclare(e.id)!],
    for (final r in donnees.manifeste.rangees) r.label,
  };

  List<(Finder, String)> _cibles() {
    final out = <(Finder, String)>[];
    // Quand une modale ou un tiroir est ouvert, seules ses commandes comptent : celles de la page, dessous, sont recouvertes par le voile et ne recevraient pas le clic.
    final tiroir = find.byKey(const Key('kit:tiroir-panneau'));
    final modale = find.byKey(const Key('kit:modale-panneau'));
    final racine = tiroir.evaluate().isNotEmpty ? tiroir.last : (modale.evaluate().isNotEmpty ? modale.last : null);
    Finder dans(Type type) => racine == null ? find.byType(type) : find.descendant(of: racine, matching: find.byType(type));
    for (final w in t.widgetList<BoutonSigh>(dans(BoutonSigh))) {
      if (w.onPressed == null || _libellesNav.contains(w.libelle)) continue;
      out.add((find.byWidget(w), w.libelle));
    }
    for (final w in t.widgetList<BoutonIcone>(dans(BoutonIcone))) {
      if (w.onPressed == null) continue;
      out.add((find.byWidget(w), w.libelle));
    }
    return out;
  }

  bool get _apercuOuvert => find.text('Enregistrer en PDF').evaluate().isNotEmpty;

  Future<void> _fermerTout() async {
    for (var i = 0; i < 4; i++) {
      final f = find.widgetWithText(BoutonSigh, 'Fermer');
      final a = find.widgetWithText(BoutonSigh, 'Annuler');
      if (f.evaluate().isNotEmpty) {
        await t.tap(f.last, warnIfMissed: false);
      } else if (a.evaluate().isNotEmpty) {
        await t.tap(a.last, warnIfMissed: false);
      } else {
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await _laisser(150);
      if (find.byKey(const Key('kit:modale-panneau')).evaluate().isEmpty &&
          find.byKey(const Key('kit:tiroir-panneau')).evaluate().isEmpty) {
        break;
      }
    }
    // Les messages (« PDF enregistré ») s'empilent en haut à droite et recouvrent les commandes de ligne : on les retire. Le voile d'une modale qui se ferme avale
    // aussi le clic suivant : on laisse l'animation de sortie s'achever.
    ToastsSigh.viderPourTests();
    await _laisser(500);
    await _laisser(500);
  }

  Future<void> _enregistrerApercu() async {
    var titre = _titreForce ?? '';
    final a4 = find.byType(FeuilleA4);
    final tk = find.byType(FeuilleTicket);
    if (titre.isNotEmpty) {
    } else if (a4.evaluate().isNotEmpty) {
      titre = t.widget<FeuilleA4>(a4.first).piece.titre;
    } else if (tk.evaluate().isNotEmpty) {
      titre = 'Ticket de caisse';
    } else {
      final mt = find.byKey(const Key('kit:modale-titre'));
      if (mt.evaluate().isNotEmpty) {
        final tx = find.descendant(of: mt, matching: find.byType(Text));
        if (tx.evaluate().isNotEmpty) titre = t.widget<Text>(tx.first).data ?? '';
      }
    }
    final avant = _appels;
    _titreCourant = titre;
    final cleCourante = '${titre.replaceAll(RegExp(r'[0-9]+'), '#')}|$_ecran';
    final bouton = find.widgetWithText(BoutonSigh, 'Enregistrer en PDF');
    var erreur = false;
    await t.runAsync(() async {
      // Les erreurs ASYNCHRONES de la fabrication du PDF (état de plus de 20 pages : refusé par le moteur) sont recueillies, jamais jetées au banc.
      await runZonedGuarded(() async {
        await t.tap(bouton.first, warnIfMissed: false);
        // Un grand livre de plusieurs dizaines de pages demande son temps : on attend l'écriture du PDF (ou l'erreur) jusqu'à 40 s.
        final debut = DateTime.now();
        while (_appels == avant && !erreur && DateTime.now().difference(debut) < const Duration(seconds: 40)) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }, (e, st) {
        erreur = true;
        notes.add('$_ecran/$_geste : PDF non produit — ${'$e'.split('\n').first}');
      });
    });
    await _laisser(100);
    if (_appels == avant && !erreur && !_vus.contains(cleCourante)) notes.add('$_ecran/$_geste : aperçu ouvert mais aucun PDF capturé');
  }

  String _titreCourant = '';
  String? _moduleCourant;
  int _appels = 0;
  String? _titreForce;

  /// Branche le crochet d'écriture sur cet explorateur.
  void brancher() {
    ImpressionPoste.enregistrer = (pdf, nom) async {
      _appels++;
      final cle = '${_titreCourant.replaceAll(RegExp(r'[0-9]+'), '#')}|$_ecran';
      if (_vus.add(cle)) {
        captures.add(Capture(_ecran, _role, _titreCourant, nom, pdf, _geste, module: _moduleCourant));
      }
      return '/specimen/$nom.pdf';
    };
  }

  /// Ouvre la première occurrence de chaque commande d'ouverture (voir [ouvreur]) et y cherche l'édition, un niveau seulement.
  Future<void> ouvrirOuvreurs(String contexte) async {
    final deja = <String>{};
    for (var tour = 0; tour < 4; tour++) {
      (Finder, String)? choix;
      for (final c in _cibles()) {
        if (!ouvreur.hasMatch(c.$2) || interdit.hasMatch(c.$2) || deja.contains(c.$2)) continue;
        choix = c;
        break;
      }
      if (choix == null) return;
      deja.add(choix.$2);
      _geste = '$contexte › ${choix.$2}';
      try {
        await t.ensureVisible(choix.$1);
        await t.tap(choix.$1, warnIfMissed: false);
        for (var i = 0; i < 4; i++) {
          await _laisser(250);
        }
        await balayer('$contexte › ${choix.$2}', profondeur: 1);
      } catch (e) {
        notes.add('$_ecran/$_geste : $e');
      }
      await _fermerTout();
    }
  }

  /// Tape chaque déclencheur de la vue courante ; recueille ce qui s'imprime.
  Future<void> balayer(String contexte, {int profondeur = 0}) async {
    final deja = <String>{};
    for (var tour = 0; tour < 12; tour++) {
      (Finder, String)? choix;
      for (final c in _cibles()) {
        if (!declencheur.hasMatch(c.$2) || interdit.hasMatch(c.$2)) continue;
        if (deja.contains(c.$2)) continue;
        choix = c;
        break;
      }
      if (choix == null) return;
      deja.add(choix.$2);
      if (bavard) stdout.writeln('  tap « ${choix.$2} »');
      _geste = '$contexte › ${choix.$2}';
      try {
        await t.ensureVisible(choix.$1);
        if (bavard) stdout.writeln('    rect ${t.getRect(choix.$1.first)} matches ${choix.$1.evaluate().length}');
        await t.tap(choix.$1, warnIfMissed: false);
        for (var i = 0; i < 8 && !_apercuOuvert; i++) {
          await _laisser(250);
        }
        if (bavard) stdout.writeln('    aperçu ouvert: $_apercuOuvert, modales: ${find.byKey(const Key('kit:modale-panneau')).evaluate().length}');
        if (_apercuOuvert) await _enregistrerApercu();
      } catch (e) {
        notes.add('$_ecran/$_geste : $e');
      }
      await _fermerTout();
      await _revenirSiNavigue();
    }
  }

  /// Un bouton qui est en réalité un raccourci a changé d'écran sous nos pieds : on rouvre l'écran d'origine (même magasin) pour poursuivre l'exploration.
  Future<void> _revenirSiNavigue() async {
    final c = find.byType(ContexteEcran);
    if (c.evaluate().isEmpty) return;
    if (t.widget<ContexteEcran>(c.first).ecranId == _ecran) return;
    if (bavard) stdout.writeln('    navigation détectée : retour à $_ecran');
    final m = _magasin;
    if (m != null) await ouvrir(_ecran, _role, m);
  }

  /// Ouvre la n-ième ligne de données du premier tableau visible (clic sur une cellule, jamais sur une commande de ligne). Les lignes se repèrent à la GÉOMÉTRIE :
  /// les cellules cliquables situées sous l'en-tête, groupées par ordonnée — le nombre de colonnes n'a donc pas à être connu.
  Future<bool> ouvrirLigne(int rang) async {
    final table = find.byKey(const Key('kit:tableau-table'));
    if (table.evaluate().isEmpty) return false;
    final entete = find.byKey(const Key('kit:tableau-entete'));
    final basEntete = entete.evaluate().isEmpty ? 0.0 : t.getRect(entete.first).bottom;
    final parLigne = <int, Element>{};
    for (final e in find.descendant(of: table, matching: find.byType(InkWell)).evaluate()) {
      final w = e.widget as InkWell;
      if (w.onTap == null) continue;
      var dansBouton = false;
      e.visitAncestorElements((a) {
        if (a.widget is BoutonIcone || a.widget is BoutonSigh) {
          dansBouton = true;
          return false;
        }
        return true;
      });
      if (dansBouton) continue;
      final r = t.getRect(find.byElementPredicate((x) => identical(x, e)));
      if (r.top < basEntete - 1) continue;
      parLigne.putIfAbsent(r.top.round(), () => e);
    }
    final hauteurs = parLigne.keys.toList()..sort();
    if (bavard) stdout.writeln('    lignes détectées : ${hauteurs.length} (bas de l’en-tête $basEntete)');
    if (rang >= hauteurs.length) return false;
    final cible = parLigne[hauteurs[rang]]!;
    try {
      final f = find.byElementPredicate((x) => identical(x, cible));
      await t.ensureVisible(f);
      await t.tap(f, warnIfMissed: false);
      // Le tiroir glisse depuis la droite : tant qu'il n'est pas en place, ses boutons sont hors de l'écran et le clic tombe à côté.
      for (var i = 0; i < 4; i++) {
        await _laisser(250);
      }
      return true;
    } catch (e) {
      notes.add('$_ecran : ligne $rang : $e');
      return false;
    }
  }

  /// Écrans dont les lignes donnent des pièces DIFFÉRENTES (une par type de pièce certifiante) : on y ouvre davantage de lignes.
  static const Map<String, int> lignesParEcran = {'m1-pieces': 24, 'm4-deces': 2};

  Future<void> _vueEtLignes(String contexte, {int lignes = 2}) async {
    final tableauDeBord = _ecran.startsWith('dash-');
    if (lignesParEcran.containsKey(_ecran) && lignes == 2) lignes = lignesParEcran[_ecran]!;
    await balayer(contexte);
    // Un tableau de bord n'offre que des RACCOURCIS vers d'autres écrans : y suivre un lien changerait d'écran sous nos pieds (leurs pièces sont prises à leur écran).
    if (!tableauDeBord) await ouvrirOuvreurs(contexte);
    if (tableauDeBord) return;
    for (var r = 0; r < lignes; r++) {
      final ouverte = await ouvrirLigne(r);
      if (bavard) stdout.writeln('    ligne $r ouverte : $ouverte');
      if (!ouverte) break;
      await balayer('$contexte › ligne ${r + 1}');
      await _fermerTout();
      await balayerIcones('$contexte › ligne ${r + 1}', r);
    }
  }

  /// Exploration complète d'un écran déjà ouvert : la vue, les lignes ouvertes, puis chaque onglet.
  Future<void> explorer() async {
    await _vueEtLignes('vue');
    final barres = find.byType(OngletsSigh);
    if (barres.evaluate().isEmpty) return;
    final onglets = t.widget<OngletsSigh>(barres.first).onglets;
    for (final o in onglets.skip(1).take(10)) {
      final f = find.descendant(of: find.byKey(const Key('kit:onglets-barre')), matching: find.text(o.libelle));
      if (f.evaluate().isEmpty) continue;
      try {
        await t.tap(f.first, warnIfMissed: false);
        await _laisser(400);
        await _vueEtLignes('onglet « ${o.libelle} »', lignes: 1);
      } catch (e) {
        notes.add('$_ecran : onglet ${o.libelle} : $e');
      }
    }
  }

  /// Produit UN document par sa fabrique : monte [ecran] sous [role] (pour disposer du contexte réel — magasin, agent, horloge, droits), fait lancer l'aperçu par
  /// [lancer] et enregistre le PDF comme le ferait le bouton « Enregistrer en PDF ». [titre] force le nom du spécimen (ticket, badge).
  Future<bool> recette(
      {required String id,
      required String module,
      required String ecran,
      required String role,
      required Magasin magasin,
      required Future<void> Function(BuildContext ctx) lancer,
      String? titre}) async {
    _geste = 'fabrique : $id';
    _moduleCourant = module;
    _titreForce = titre;
    final avant = _appels;
    try {
      await ouvrir(ecran, role, magasin);
      _geste = 'fabrique : $id';
      final texte = find.descendant(of: find.byType(ContexteEcran), matching: find.byType(Text));
      final ctx = t.element(texte.first);
      runZonedGuarded(() => lancer(ctx), (e, st) => notes.add('$id : $e'));
      for (var i = 0; i < 12 && !_apercuOuvert; i++) {
        await _laisser(250);
      }
      if (_apercuOuvert) {
        await _enregistrerApercu();
      } else {
        notes.add('$id : aucun aperçu ouvert par la fabrique');
      }
    } catch (e) {
      notes.add('$id : $e');
    }
    await _fermerTout();
    _moduleCourant = null;
    _titreForce = null;
    return _appels > avant;
  }

  /// Exécute [action] avec le contexte réel de l'écran ouvert (magasin, agent, horloge) : sert à préparer une donnée par le moteur de l'écran avant de l'explorer.
  Future<void> preparer(Future<void> Function(BuildContext ctx) action) async {
    final texte = find.descendant(of: find.byType(ContexteEcran), matching: find.byType(Text));
    final ctx = t.element(texte.first);
    await action(ctx);
    await _laisser(200);
  }

  /// Choisit [cible] dans la liste dont le résumé affiche [courant] (liste à recherche : on tape pour filtrer quand l'entrée n'est pas encore visible).
  Future<void> choisirCombo(String courant, String cible) async {
    final f = find.text(courant).first;
    await t.ensureVisible(f);
    await t.tap(f, warnIfMissed: false);
    for (var i = 0; i < 3; i++) {
      await _laisser(200);
    }
    if (find.text(cible).evaluate().isEmpty) {
      await t.enterText(find.byType(TextField).last, cible);
      await _laisser(300);
    }
    await t.tap(find.text(cible).last, warnIfMissed: false);
    for (var i = 0; i < 3; i++) {
      await _laisser(200);
    }
  }

  /// Les commandes d'icône d'une LIGNE (une par ligne du tableau, même libellé) : on tape celle de la ligne [rang], pas toujours la première — c'est ainsi que
  /// chaque ligne d'un registre de pièces donne sa propre pièce.
  Future<void> balayerIcones(String contexte, int rang) async {
    final labels = <String>{};
    for (final c in _cibles()) {
      if (declencheur.hasMatch(c.$2) && !interdit.hasMatch(c.$2)) labels.add(c.$2);
    }
    for (final l in labels) {
      final f = find.byWidgetPredicate((w) => w is BoutonIcone && w.libelle == l && w.onPressed != null);
      if (f.evaluate().length <= rang) continue;
      _geste = '$contexte › $l (ligne ${rang + 1})';
      try {
        await t.ensureVisible(f.at(rang));
        await t.tap(f.at(rang), warnIfMissed: false);
        for (var i = 0; i < 8 && !_apercuOuvert; i++) {
          await _laisser(250);
        }
        if (_apercuOuvert) await _enregistrerApercu();
      } catch (e) {
        notes.add('$_ecran/$_geste : $e');
      }
      await _fermerTout();
      await _revenirSiNavigue();
    }
  }
}
