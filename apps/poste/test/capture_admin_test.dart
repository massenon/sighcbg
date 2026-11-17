import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/theme.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/base_portable_poste.dart';
import 'package:sigh_poste/donnees/cle_clinique_poste.dart';
import 'package:sigh_poste/donnees/maj_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/persistance.dart';
import 'package:sigh_poste/modules/cfg/cfg_base_portable.dart';
import 'package:sigh_poste/modules/mere/mrd_cle_restauration.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/mere/mra_supervision.dart';
import 'package:sigh_poste/modules/mere/mrd_reprise_poste.dart';
import 'package:sigh_poste/modules/mere/mrb_source.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show Droit, DroitsGestes, colFichesAide, smsStatutMotsInterdits;

import 'aide_polices.dart';
import 'mere_b_test.dart' as b;
import 'mra_ecrans_test.dart' as a;

/// Captures du MANUEL ADMINISTRATEUR (docs/manuels/src/admin) : les écrans d'administration dessinés pour de vrai (polices réelles, jeu LIVRÉ,
/// rôle administrateur), un PNG par écran et, à côté, un JSON des rectangles des commandes à désigner par une flèche.
/// Sur demande seulement : `SIGH_CAPTURES=/chemin flutter test test/capture_admin_test.dart`.
final String? _sortie = Platform.environment['SIGH_CAPTURES'];
const double _ratio = 1.25;
final _donnees = DonneesNavigation.depuisDossier();
final _jour = DateTime(2026, 11, 16, 10);
final Map<String, Object?> _cibles = {};

/// Le jeu LIVRÉ, mais AUCUNE personne réelle à l'image : les noms et prénoms du personnel sont remplacés partout (comptes, soignants, journal…) par des
/// noms de démonstration neutres avant le rendu. La dénomination de la clinique, elle, reste.
Magasin _jeu() {
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
  final remplacements = <String, String>{};
  var i = 0;
  for (final p in m.collection('personnel').toutes) {
    i++;
    final nom = '${p['nom'] ?? ''}', prenom = '${p['prenom'] ?? ''}';
    final n = 'AGENT${i.toString().padLeft(2, '0')}';
    if ('${p['nomComplet'] ?? ''}'.isNotEmpty) remplacements['${p['nomComplet']}'] = '$n Démo';
    if (nom.isNotEmpty && prenom.isNotEmpty) remplacements['$prenom $nom'] = 'Démo $n';
    if (prenom.length >= 3) remplacements[prenom] = 'Démo';
    if (nom.length >= 3 && nom != 'BAGUIDI') remplacements[nom] = n;
  }
  final cles = remplacements.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  String neutre(String s) {
    for (final k in cles) {
      s = s.replaceAll(k, remplacements[k]!);
    }
    return s;
  }
  for (final nom in Magasin.collectionsDuJeu) {
    final c = m.collection(nom);
    if (c.toutes.isEmpty) continue;
    final avant = jsonEncode(c.toutes);
    final apres = neutre(avant);
    if (apres != avant) c.remplacerContenu([for (final f in (jsonDecode(apres) as List)) (f as Map).cast<String, Object?>()]);
  }
  return m;
}

Future<void> _pomper(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _taille(WidgetTester t, double l, double h) async {
  t.view.physicalSize = Size(l, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _poste(WidgetTester t, String ecran, {ModePoste mode = ModePoste.fileul, Magasin? magasin, String role = 'admin'}) async {
  final client = mode == ModePoste.mere
      ? ClientMere(base: Uri.parse('http://x'), secretAdmin: 's', client: MockClient((r) async => http.Response('[]', 200)))
      : null;
  await t.pumpWidget(RepaintBoundary(
      key: const Key('cap'),
      child: SighPoste(
          key: UniqueKey(),
          donnees: _donnees,
          config: ConfigPoste(mode: mode, role: role),
          client: client,
          ecranInitial: ecran,
          magasin: magasin ?? _jeu(),
          horloge: () => _jour)));
  await _pomper(t);
  // Menu en ruban replié : la capture montre l'écran, pas le panneau des rubriques.
  if (find.byKey(const Key('panneau-ruban')).evaluate().isNotEmpty) {
    await t.tap(find.byKey(const Key('ruban-bascule')));
    await _pomper(t, 4);
  }
}

/// Écrit l'image et relève les rectangles des [cibles] (libellé → chercheur), en pixels de l'image.
Future<void> _png(WidgetTester t, String nom, Map<String, Finder> cibles) async {
  await t.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
  await t.pump();
  final boite = t.renderObject<RenderRepaintBoundary>(find.byKey(const Key('cap')));
  final origine = boite.localToGlobal(Offset.zero);
  final rects = <String, List<double>>{};
  for (final e in cibles.entries) {
    if (e.value.evaluate().isEmpty) continue;
    final r = t.getRect(e.value.first).shift(-origine);
    rects[e.key] = [for (final v in [r.left, r.top, r.width, r.height]) (v * _ratio).roundToDouble()];
  }
  await t.runAsync(() async {
    final img = await boite.toImage(pixelRatio: _ratio);
    final d = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_sortie/$nom.png').writeAsBytesSync(d!.buffer.asUint8List());
    // Une exécution partielle (--plain-name) complète le fichier au lieu de l'écraser.
    final fichier = File('$_sortie/cibles.json');
    if (_cibles.isEmpty && fichier.existsSync()) _cibles.addAll((jsonDecode(fichier.readAsStringSync()) as Map).cast<String, Object?>());
    _cibles[nom] = {'largeur': img.width, 'hauteur': img.height, 'cibles': rects};
    File('$_sortie/cibles.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_cibles));
  });
}

Finder _bouton(String libelle) => find.widgetWithText(BoutonSigh, libelle);
Finder _texte(String libelle) => find.text(libelle);
Finder _onglet(String id) => find.byKey(Key('kit:onglet:$id'));

Future<void> _toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first, warnIfMissed: false);
  await _pomper(t, 5);
}

/// La console du poste mère (lot a) se dessine sur une SOURCE : un faux qui répond comme le moteur, avec des appareils sans nom de personne.
class _SourceMra extends a.SourceFauxMra {
  _SourceMra() {
    etatMere = EtatMere(
        epoch: 3,
        seqMax: 1240,
        repSeq: 1236,
        conflitsOuverts: 1,
        alertes: const [],
        derives: const [],
        bloques: const [],
        reinitOuverte: false,
        restauration: null,
        appareils: [
          a.app('u-1', 'Caisse principale', 'fileul', contact: _jour.subtract(const Duration(minutes: 2)), seq: 1238),
          a.app('u-2', 'Réception', 'fileul', contact: _jour.subtract(const Duration(minutes: 6)), seq: 1236),
          a.app('u-3', 'Laboratoire', 'fileul', contact: _jour.subtract(const Duration(hours: 5)), seq: 1190),
          a.app('u-4', 'Téléphone de garde', 'mobile', contact: _jour.subtract(const Duration(minutes: 40)), seq: 1201, profil: 'infirmier'),
        ]);
    sante = Supervision(etat: 'ok', depot: 'pg', controles: [
      Controle(nom: 'Base de données', etat: 'ok', detail: 'PostgreSQL joignable'),
      Controle(nom: 'Sauvegarde', etat: 'ok', detail: 'Dernière sauvegarde il y a 8,0 h.'),
      Controle(nom: 'Relais en ligne', etat: 'ok', detail: '4 opération(s) pas encore répliquées (chiffrées) vers le relais.'),
      Controle(nom: 'Postes', etat: 'attention', detail: 'Un poste sans contact depuis plus de 4 h.'),
    ]);
    conflits = [];
  }
}

Future<void> _ecranMere(WidgetTester t, Widget ecran) async {
  await t.pumpWidget(RepaintBoundary(
      key: const Key('cap'),
      child: MaterialApp(
          theme: ThemeSigh.clair(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
              backgroundColor: const Color(0xFFF8FAFC),
              body: ContexteEcran(
                  ecranId: 'mere-appareils',
                  role: 'admin',
                  droit: const Droit(voir: true, editer: true, annuler: true),
                  magasin: Magasin(const {}, 'POSTE'),
                  aller: (_) {},
                  child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: ecran))))));
  await _pomper(t);
}

/// Un écran de configuration du poste, dessiné seul (la décision 12 du 17/11/2026) : un magasin vide, les trois services de la mise à jour branchés sur un dossier de données
/// d'essai, le rôle administrateur. Poste FILEUL : son export tient lieu de sauvegarde, ce qui permet de montrer « Mise à jour AUTORISÉE ».
final List<int> _cleCapture = List<int>.generate(32, (i) => (i * 17 + 3) % 256);

Future<Magasin> _magasinServices(Directory dossier) async {
  final m = Magasin(const {}, 'POSTE');
  await m.brancherPersistance(PersistanceMemoire(), delai: Duration.zero);
  bool peut(String g) => DroitsGestes(fiches: m.collection('rbac').actives).peut('admin', g);
  final base = ServiceBasePortable(magasin: m, dossierDonnees: dossier.path, role: () => 'fileul', cleClinique: () async => _cleCapture, peut: peut)..installer();
  ServiceMiseAJour(magasin: m, dossierDonnees: dossier.path, base: base, role: () => 'fileul', peut: peut, versionCourante: '0.1.0').installer();
  ServiceCleClinique(magasin: m, dossierDonnees: dossier.path, peut: peut).installer();
  return m;
}

Future<void> _ecranCfg(WidgetTester t, String ecranId, Widget ecran, Magasin magasin) async {
  await t.pumpWidget(RepaintBoundary(
      key: const Key('cap'),
      child: MaterialApp(
          theme: ThemeSigh.clair(),
          debugShowCheckedModeBanner: false,
          home: Scaffold(
              backgroundColor: const Color(0xFFF8FAFC),
              body: ContexteEcran(
                  ecranId: ecranId,
                  role: 'admin',
                  droit: const Droit(voir: true, editer: true, annuler: true),
                  magasin: magasin,
                  utilisateur: 'ADMIN',
                  aller: (_) {},
                  horloge: () => DateTime.now(),
                  child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: ecran))))));
  await _pomper(t);
}

/// Les opérations de fichier et de chiffrement rendent la main à la vraie boucle d'événements entre deux pompes.
Future<void> _attendre(WidgetTester t, Finder jusqua) async {
  for (var i = 0; i < 160; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await t.pump(const Duration(milliseconds: 20));
    if (jusqua.evaluate().isNotEmpty) return;
  }
}

/// La mère simulée porte aussi la passerelle SMS (ADR-0009) et l'état de la satisfaction en ligne : numéros MASQUÉS, aucun texte, aucun nom.
class _FauxMere extends b.Faux {
  @override
  Future<MrbSms?> sms() async => MrbSms(
      actif: true,
      relaisConfigure: true,
      relais: const {
        'plafond_jour': 100,
        'envoyes_aujourdhui': 3,
        'en_attente': 1,
        'pilote': 'vonage',
        'parametres_manquants': ['RELAIS_SMS_VONAGE_CLE', 'RELAIS_SMS_VONAGE_SECRET', 'RELAIS_SMS_EXPEDITEUR']
      },
      statutMotsInterdits: smsStatutMotsInterdits,
      journal: [
        {'id': 'sms-3', 'depose': _jour.subtract(const Duration(minutes: 4)).millisecondsSinceEpoch, 'numero': '+229 01 •• •• •• 12', 'modele': 'Rappel de rendez-vous', 'longueur': 96, 'statut': 'en_attente', 'tentatives': 0, 'erreur': ''},
        {'id': 'sms-2', 'depose': _jour.subtract(const Duration(minutes: 35)).millisecondsSinceEpoch, 'numero': '+229 01 •• •• •• 47', 'modele': 'Rappel de rendez-vous', 'longueur': 101, 'statut': 'envoye', 'tentatives': 1, 'erreur': ''},
        {'id': 'sms-1', 'depose': _jour.subtract(const Duration(hours: 2)).millisecondsSinceEpoch, 'numero': '+229 01 •• •• •• 03', 'modele': 'Essai de la passerelle', 'longueur': 58, 'statut': 'envoye', 'tentatives': 1, 'erreur': ''},
      ]);

  @override
  Future<Map<String, Object?>?> etatSatisfaction() async => {
        'relais_configure': true,
        'kid': 'sat1-01',
        'liens_en_ligne': 1,
        'derniere_releve_ms': _jour.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
        'recues': 14,
        'illisibles': 0,
      };
}

b.Faux _fauxMrb() => _FauxMere()
  ..etatV = b.unEtat(appareils: const [
    MrbAppareil(uuid: 'u-1', etiquette: 'Caisse principale', role: 'fileul', etat: 'actif'),
    MrbAppareil(uuid: 'u-2', etiquette: 'Réception', role: 'fileul', etat: 'actif'),
  ])
  ..catalogue = [
    MrbSauvegarde(date: DateTime(2026, 11, 16, 2), nature: 'Quotidienne', tailleOctets: 6 * 1024 * 1024, verification: 'Vérifiée'),
    MrbSauvegarde(date: DateTime(2026, 11, 15, 2), nature: 'Quotidienne', tailleOctets: 6 * 1024 * 1024),
    MrbSauvegarde(date: DateTime(2026, 11, 14, 2), nature: 'Quotidienne', tailleOctets: 5 * 1024 * 1024),
  ]
  ..empreinte = '3fa91c07'
  ..cree = DateTime(2026, 11, 2, 9)
  ..battement = _jour.subtract(const Duration(seconds: 40))
  ..echangesV = [
    MrbEchangeRelais(quand: _jour.subtract(const Duration(minutes: 1)), sens: 'depot', contenu: 'enveloppe de journal rang 1236, 2 048 octets chiffrés', resultat: 'Accepté'),
    MrbEchangeRelais(quand: _jour.subtract(const Duration(minutes: 3)), sens: 'depot', contenu: 'enveloppe de journal rang 1235, 1 024 octets chiffrés', resultat: 'Accepté'),
  ];

Future<void> _posteMere(WidgetTester t, String ecran, {String role = 'admin', Magasin? magasin}) async {
  mrbSourceInjectee = _fauxMrb();
  mrbIntervalle = const Duration(hours: 1);
  addTearDown(() => mrbSourceInjectee = null);
  await _poste(t, ecran, mode: ModePoste.mere, role: role, magasin: magasin);
}

/// Fait défiler jusqu'à [f] sans le toucher (la carte visée vient dans la vue de la capture).
Future<void> _voir(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) return;
  await t.ensureVisible(f.first);
  await _pomper(t, 4);
}

/// Le jeu livré avec deux décisions qui attendent la mère (une validation d'achat déposée, une demande d'import) : la pastille de la barre les compte.
Magasin _jeuAvecAttente() {
  final m = _jeu();
  m.collection('validationsDeposees').ajouterSansJournal({
    'id': 'VDP-CAP',
    'statut': 'actif',
    'genre': 'circuit_achat',
    'famille': 'commande_validation',
    'cible': 'BC-1',
    'libelle': 'Validation d’une commande',
    'etat': 'deposee',
    'demandePar': 'DAF',
    'demandeRole': 'da',
    'demandeLe': '2026-11-16T04:30:00.000Z',
  });
  m.collection('demandesImport').ajouterSansJournal({
    'id': 'DI-CAP',
    'statut': 'actif',
    'jeu': 'tarifs',
    'jeuLibelle': 'Tarifs',
    'etat': 'en_attente',
    'demandePar': 'DAF',
    'demandeRole': 'da',
    'demandeLe': '2026-11-16',
    'demandeInstant': '2026-11-16T07:00:00.000Z',
  });
  return m;
}

/// La reprise d'un poste (v31) : une source sans réseau, des postes sans nom de personne, un code FICTIF (jamais un vrai code d'appairage).
class _SourceReprise implements SourceReprise {
  @override
  Future<List<Appareil>> appareils() async => [
        Appareil(uuid: '3f7a91c0-5b2e-4d18-9a6c-0e41b7d2a5f3', etiquette: 'Caisse principale', role: 'fileul', etat: 'actif', dernierContact: _jour.subtract(const Duration(minutes: 3)), derniereSeq: 1238, deriveMs: 0),
        Appareil(uuid: '8c20d4e6-71af-4b39-8e05-2a9f6c13b7d8', etiquette: 'Réception', role: 'fileul', etat: 'actif', dernierContact: _jour.subtract(const Duration(minutes: 9)), derniereSeq: 1236, deriveMs: 0),
        Appareil(uuid: 'b5e1370a-92cd-4f60-a1b8-64d0e8f2c917', etiquette: 'Laboratoire (ancien)', role: 'fileul', etat: 'revoque', dernierContact: _jour.subtract(const Duration(days: 9)), derniereSeq: 1190, deriveMs: 0),
        Appareil(uuid: 'd90c64b2-3e8a-47f1-b256-1c7a09e5d384', etiquette: 'Téléphone de garde', role: 'mobile', etat: 'actif', dernierContact: _jour.subtract(const Duration(minutes: 40)), derniereSeq: 1201, deriveMs: 0),
      ];

  @override
  Future<CodeReprise> emettre({required String uuid, required String etiquette}) async =>
      CodeReprise(code: 'K7M4Q9XP', expireMs: _jour.add(const Duration(minutes: 15)).millisecondsSinceEpoch, validiteSecondes: 900);
}

/// Deux fiches d'aide d'EXEMPLE (aucun contenu de la clinique : l'écran n'en livre aucun), écrites par un auteur de démonstration : l'une ordinaire, l'autre qui engage un professionnel.
Magasin _jeuAvecFiches() {
  final m = _jeu();
  m.collection(colFichesAide).remplacerContenu([
    {
      'id': 'FAI-CAP-1',
      'type': 'aide',
      'statut': 'proposee',
      'titre': 'Exemple : enregistrer un courrier entrant',
      'motsCles': ['courrier entrant'],
      'roles': <String>[],
      'ecrans': <String>[],
      'etapes': ['Étape un', 'Étape deux'],
      'auteurId': 'U-DEMO-1',
      'auteurNom': 'AGENT01 Démo',
      'creeLe': '2026-11-16T08:00:00Z',
    },
    {
      'id': 'FAI-CAP-2',
      'type': 'aide',
      'statut': 'proposee',
      'titre': 'Exemple : fiche qui engage le bloc opératoire',
      'motsCles': ['check-liste'],
      'roles': <String>[],
      'ecrans': <String>[],
      'etapes': ['Étape à écrire par le professionnel'],
      'domainePro': 'bloc',
      'questionAttendue': 94,
      'auteurId': 'U-DEMO-1',
      'auteurNom': 'AGENT01 Démo',
      'creeLe': '2026-11-16T09:00:00Z',
    },
  ]);
  return m;
}

/// Les identifiants s'écrivent en `monospace` : sans police de ce nom, le moteur de test les dessine en blocs. On lui donne la police à chasse fixe du dépôt.
bool _monoChargee = false;
Future<void> _policeMono() async {
  if (_monoChargee) return;
  final mono = FontLoader('monospace');
  mono.addFont(Future.value(ByteData.view(File('assets/polices/pdf/LiberationMono-Regular.ttf').readAsBytesSync().buffer)));
  await mono.load();
  _monoChargee = true;
}

void cas(String nom, double l, double h, Future<void> Function(WidgetTester) corps) => testWidgets(nom, skip: _sortie == null, (t) async {
      await chargerPolices();
      await _policeMono();
      await _taille(t, l, h);
      await corps(t);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
    });

void main() {
  cas('Rôles et permissions : matrice', 1440, 1000, (t) async {
    await _poste(t, 'm14-roles');
    await _png(t, 'admin-01-roles-matrice', {
      'Nouveau rôle': _bouton('Nouveau rôle'),
      'Gestes réservés': _onglet('gestes'),
      'Décisions de droits': _onglet('decisions'),
      'Imprimer la matrice': _bouton('Imprimer la matrice'),
    });
  });

  cas('Rôles et permissions : gestes réservés', 1440, 1100, (t) async {
    await _poste(t, 'm14-roles');
    await _toucher(t, _onglet('gestes'));
    await _png(t, 'admin-02-roles-gestes', {
      'Accorder': _bouton('Accorder'),
      'Retirer': _bouton('Retirer'),
    });
  });

  cas('Rôles et permissions : détail par rôle', 1440, 1000, (t) async {
    await _poste(t, 'm14-roles');
    await _toucher(t, _onglet('detail'));
    await _png(t, 'admin-03-roles-detail', {
      'Modifier les droits de ce rôle': find.byTooltip('Modifier les droits de ce rôle'),
      'Régler écran par écran': find.byTooltip('Régler écran par écran'),
      'Archiver ce rôle': find.byTooltip('Archiver ce rôle'),
    });
  });

  cas('Utilisateurs : registre', 1440, 900, (t) async {
    await _poste(t, 'm14-utilisateurs');
    await _png(t, 'admin-04-utilisateurs', {'Nouveau': _bouton('Nouveau')});
  });

  cas('Utilisateurs : nouveau compte', 1440, 1000, (t) async {
    await _poste(t, 'm14-utilisateurs');
    await _toucher(t, _bouton('Nouveau'));
    await _png(t, 'admin-05-utilisateur-nouveau', {
      'Rôle (RBAC)': find.byKey(const Key('kit:champ:role')),
      'Mot de passe': find.byKey(const Key('kit:champ:motDePasse')),
      'Changement obligatoire': find.byKey(const Key('kit:champ:doitChangerMotDePasse')),
    });
  });

  cas('Paramètres système : paramètres (mère)', 1440, 1100, (t) async {
    await _posteMere(t, 'cfg-systeme');
    await _toucher(t, _onglet('parametres'));
    await _png(t, 'admin-06-parametres', {
      'Paramètres': _onglet('parametres'),
      'Régler à partir d’une date': _bouton('Régler à partir d’une date'),
      'Historique': find.textContaining('Historique ('),
    });
  });

  cas('Paramètres système : jeux de test', 1440, 1000, (t) async {
    await _poste(t, 'cfg-systeme');
    await _toucher(t, _onglet('reinitialisation'));
    await _png(t, 'admin-07-jeux-de-test', {'Jeux de test': _onglet('reinitialisation')});
  });

  cas('Paramètres système : corbeille', 1440, 900, (t) async {
    await _poste(t, 'cfg-systeme');
    await _toucher(t, _onglet('corbeille'));
    await _png(t, 'admin-08-corbeille', {'Restaurer': find.byTooltip('Restaurer')});
  });

  cas('Activité des modules', 1440, 1100, (t) async {
    await _poste(t, 'cfg-modules');
    await _png(t, 'admin-09-modules', {'Piloter une activité': _bouton('Piloter une activité'), 'Ouvert': _texte('Ouvert')});
  });

  cas('Journal d’audit', 1440, 900, (t) async {
    await _poste(t, 'm14-audit');
    await _png(t, 'admin-10-audit', {});
  });

  cas('Configuration fiscale MECeF', 1440, 1100, (t) async {
    await _posteMere(t, 'mecef-config');
    await _png(t, 'admin-11-mecef', {'Modèle': find.textContaining('ELTRADE CC300')});
  });

  cas('Paramètres fiscaux (IFU / RCCM)', 1440, 1000, (t) async {
    await _poste(t, 'cfg-fiscalite');
    await _png(t, 'admin-12-fiscalite', {
      'IFU': find.textContaining('3201001996110'),
      'RCCM': find.textContaining('RB/PKO/17 A 4240'),
    });
  });

  cas('Sauvegardes du poste (hors site)', 1440, 1000, (t) async {
    await _posteMere(t, 'm14-sauvegardes');
    await _png(t, 'admin-13-sauvegardes', {'Régler la copie hors site': _bouton('Régler la copie hors site')});
  });

  cas('Mère : appareils et appairage', 1560, 1000, (t) async {
    await _ecranMere(t, EcranMraAppareils(source: _SourceMra()));
    await _png(t, 'admin-14-mere-appareils', {
      'Appairer un poste': _bouton('Appairer un poste'),
      'Appairer un mobile': _bouton('Appairer un mobile'),
      'Révoquer': _bouton('Révoquer'),
    });
  });

  cas('Mère : code d’appairage', 1560, 900, (t) async {
    await _ecranMere(t, EcranMraAppareils(source: _SourceMra()));
    await _toucher(t, _bouton('Appairer un poste'));
    final champ = find.descendant(of: find.byKey(const Key('kit:champ:etiquette')), matching: find.byType(TextField));
    if (champ.evaluate().isNotEmpty) {
      await t.enterText(champ, 'Caisse principale');
      await t.pump();
    }
    await _png(t, 'admin-15-mere-appairer', {
      'Nom de l’appareil': find.byKey(const Key('kit:champ:etiquette')),
      'Générer le code': _bouton('Générer le code'),
    });
  });

  cas('Mère : supervision', 1560, 1000, (t) async {
    await _ecranMere(t, EcranMraSupervision(source: _SourceMra()));
    await _png(t, 'admin-16-mere-supervision', {'Sauvegarder maintenant': _bouton('Sauvegarder maintenant')});
  });

  cas('Mère : sauvegardes', 1440, 1100, (t) async {
    await _posteMere(t, 'mere-sauvegardes');
    await _png(t, 'admin-17-mere-sauvegardes', {
      'Sauvegarder maintenant': _bouton('Sauvegarder maintenant'),
      'Vérifier la dernière': _bouton('Vérifier la dernière'),
    });
  });

  cas('Mère : clé de clinique', 1440, 1000, (t) async {
    await _posteMere(t, 'mere-cle-clinique');
    await _png(t, 'admin-18-mere-cle', {'Faire tourner la clé': _bouton('Faire tourner la clé')});
  });

  cas('Mère : relais en ligne', 1440, 1000, (t) async {
    await _posteMere(t, 'mere-relais');
    await _png(t, 'admin-19-mere-relais', {});
  });

  cas('Mère : réinitialisation de production', 1440, 1100, (t) async {
    await _posteMere(t, 'mere-reinit');
    await _png(t, 'admin-20-mere-reinit', {});
  });

  cas('Mère : passerelle SMS', 1440, 1650, (t) async {
    await _posteMere(t, 'mere-sms-passerelle');
    await _png(t, 'admin-21-sms-passerelle', {
      'Interrupteur': find.byKey(const Key('sms:interrupteur')),
      'Tester l’envoi': find.byKey(const Key('sms:tester')),
      'Mots interdits': find.byKey(const Key('sms:statut-mots')),
      'Fournisseur': find.byKey(const Key('sms:fournisseurs')),
      'Paramètres manquants': find.byKey(const Key('sms:parametres-manquants')),
    });
  });

  cas('Mère : journal des envois SMS', 1440, 1000, (t) async {
    await _posteMere(t, 'mere-sms-journal');
    await _png(t, 'admin-22-sms-journal', {
      'Composer un SMS': find.byKey(const Key('sms:composer')),
      'Relever les statuts': find.byKey(const Key('sms:suivre')),
      'Numéro (masqué)': _texte('Numéro (masqué)'),
    });
  });

  cas('Mère : satisfaction en ligne', 1440, 1200, (t) async {
    await _posteMere(t, 'adm-enquetes');
    await _toucher(t, _onglet('partage'));
    await _voir(t, _texte('Satisfaction en ligne (poste mère)'));
    await _png(t, 'admin-23-satisfaction', {
      'Carte': _texte('Satisfaction en ligne (poste mère)'),
      'Publier et relever maintenant': _bouton('Publier et relever maintenant'),
    });
  });

  cas('MECeF : mode de certification', 1440, 1100, (t) async {
    await _posteMere(t, 'mecef-config');
    await _voir(t, find.byKey(const Key('mecef:etat-mode:boitier')));
    await _png(t, 'admin-24-mecef-modes', {
      'Boîtier': find.byKey(const Key('mecef:etat-mode:boitier')),
      'e-MECeF': find.byKey(const Key('mecef:etat-mode:emecef')),
      'Adaptateur': find.byKey(const Key('mecef-adaptateur-boitier')),
      'Enregistrer le mode': _bouton('Enregistrer le mode'),
    });
  });

  cas('MECeF : imprimante de caisse', 1440, 1100, (t) async {
    await _posteMere(t, 'mecef-config');
    await _voir(t, find.byKey(const Key('mecef:imprimante')));
    await _png(t, 'admin-25-mecef-imprimante', {
      'Imprimante': find.byKey(const Key('mecef:imprimante')),
      'Intégrée au boîtier': find.byKey(const Key('kit:champ:imprimanteIntegree')),
      'Enregistrer l’imprimante': _bouton('Enregistrer l’imprimante'),
    });
  });

  cas('Paramètres : caisse et encaissement', 1440, 1100, (t) async {
    await _posteMere(t, 'cfg-systeme');
    await _toucher(t, _onglet('parametres'));
    final carte = _texte('Encaisser le reste d\'une facture qui a une ligne sans prix');
    await _voir(t, carte);
    await _png(t, 'admin-26-param-caisse', {
      'Encaisser le reste': carte,
      'Régler à partir d’une date': _bouton('Régler à partir d’une date'),
    });
  });

  cas('Fiscal : confirmer la CNSS', 1440, 1100, (t) async {
    await _posteMere(t, 'cfg-comptabilite', role: 'da');
    await _voir(t, find.byKey(const Key('fco:cnss')));
    await _png(t, 'admin-27-cnss-confirmer', {
      'Taux de la CNSS': find.byKey(const Key('fco:cnss')),
      'Confirmer': find.byKey(const Key('fco:cnss:confirmer')),
    });
  });

  cas('Fiscal : barème de l’AIB', 1440, 1000, (t) async {
    await _posteMere(t, 'm12-aib', role: 'da');
    await _png(t, 'admin-28-bareme-aib', {
      'Situations de l’acheteur': _onglet('situations'),
    });
  });

  cas('RH : planning individuel', 1440, 1100, (t) async {
    await _poste(t, 'm10-employe-profil');
    await _toucher(t, _onglet('planning-individuel'));
    await _png(t, 'admin-29-planning-individuel', {
      'Déroger': _bouton('Déroger'),
      'Remplacer le régime': _bouton('Remplacer le régime'),
      'Revenir à la catégorie': _bouton('Revenir à la catégorie'),
    });
  });

  cas('Fiscalité : numérotation des pièces', 1440, 1300, (t) async {
    await _posteMere(t, 'cfg-fiscalite');
    await _voir(t, find.byKey(const Key('cfb:numerotation')));
    await _png(t, 'admin-31-numerotation', {
      'Carte': find.byKey(const Key('cfb:numerotation')),
      'Rendez-vous': _texte('Lit aussi : C'),
    });
  });

  cas('Fiscalité : série des factures à une entreprise', 1440, 800, (t) async {
    await _posteMere(t, 'cfg-fiscalite');
    await _voir(t, find.byKey(const Key('cfb:numerotation')));
    final champ = find.descendant(of: find.byKey(const Key('cfb:numerotation')), matching: find.byType(TextField));
    if (champ.evaluate().isNotEmpty) {
      await t.enterText(champ.first, 'entreprise');
      await _pomper(t, 6);
    }
    await _png(t, 'admin-36-numerotation-ft', {
      'Série FT': find.byKey(const Key('cfb:numerotation:modifier:caisse.factures-tiers')),
    });
  });

  cas('Fiscal : taux de la paie en barèmes datés', 1440, 1300, (t) async {
    await _posteMere(t, 'cfg-comptabilite', role: 'da');
    await _voir(t, find.byKey(const Key('fco:vps')));
    await _png(t, 'admin-32-taux-paie', {
      'Taux du VPS': find.byKey(const Key('fco:vps')),
      'Confirmer': find.byKey(const Key('fco:vps:confirmer')),
      'Nouvelle version': find.byKey(const Key('fco:vps:nouvelle')),
    });
  });

  cas('Paramètres : plan de travail annuel', 1440, 1300, (t) async {
    await _posteMere(t, 'cfg-systeme');
    await _toucher(t, _onglet('parametres'));
    final carte = _texte('Découpage du plan de travail annuel');
    await _voir(t, carte);
    await _png(t, 'admin-33-param-pta', {
      'Découpage': carte,
      'Seuil de retard': _texte('Seuil d’alerte de retard d’une action du plan (jours)'),
    });
  });

  cas('RH : registre du personnel vu par le Surveillant', 1440, 900, (t) async {
    await _poste(t, 'm10-personnel', role: 'surveillant');
    await _png(t, 'admin-37-personnel-surveillant', {'Réservé': _texte('réservé')});
  });

  cas('Facture à une entreprise (tiers payeur)', 1440, 1000, (t) async {
    await _posteMere(t, 'm9-facture-mere', role: 'comptable');
    await _toucher(t, _onglet('tiers'));
    await _png(t, 'admin-34-facture-tiers', {
      'Onglet': _onglet('tiers'),
      'Émettre': find.byKey(const Key('tiers:emettre')),
    });
  });

  cas('PTA : référentiels du plan', 1440, 1300, (t) async {
    await _posteMere(t, 'm13-plan-annuel');
    await _voir(t, _texte('Référentiels du plan'));
    await _png(t, 'admin-35-pta-referentiels', {'Référentiels du plan': _texte('Référentiels du plan')});
  });

  cas('Export, import et mise à jour', 1440, 1700, (t) async {
    final dossier = Directory('${Directory.systemTemp.path}/sigh-cap')..createSync(recursive: true);
    addTearDown(() {
      if (dossier.existsSync()) dossier.deleteSync(recursive: true);
    });
    final m = await _magasinServices(dossier);
    await _ecranCfg(t, 'cfg-base-portable', const EcranBasePortable(), m);
    await t.tap(find.byKey(const Key('base:exporter')));
    await _attendre(t, find.byKey(const Key('base:export-ok')));
    await t.ensureVisible(find.byKey(const Key('maj:preparer')));
    await t.tap(find.byKey(const Key('maj:preparer')));
    await _attendre(t, find.byKey(const Key('maj:autorisee')));
    await _png(t, 'admin-38-base-portable', {
      'Exporter la base complète': find.byKey(const Key('base:exporter')),
      'Fichier d’export (.sghx)': find.byKey(const Key('base:fichier')),
      'Vérifier le fichier': find.byKey(const Key('base:verifier')),
      'Importer dans un magasin neuf': find.byKey(const Key('base:importer')),
      'Préparer la mise à jour': find.byKey(const Key('maj:preparer')),
      'Mise à jour autorisée': find.byKey(const Key('maj:autorisee')),
      'Motif de la levée': find.byKey(const Key('maj:motif')),
      'Lever le blocage': find.byKey(const Key('maj:lever')),
    });
  });

  cas('Restaurer la clé de la clinique', 1440, 1000, (t) async {
    final dossier = Directory('${Directory.systemTemp.path}/sigh-cap-cle')..createSync(recursive: true);
    addTearDown(() {
      if (dossier.existsSync()) dossier.deleteSync(recursive: true);
    });
    final m = await _magasinServices(dossier);
    await _ecranCfg(t, 'mere-cle-restauration', const EcranCleRestauration(), m);
    await _png(t, 'admin-39-cle-restauration', {
      'Clé en service': find.byKey(const Key('cle:etat')),
      'Texte de la copie papier': find.byKey(const Key('cle:source-texte')),
      'Fichier de sauvegarde de clé': find.byKey(const Key('cle:source-fichier')),
      'Empreinte notée sur le scellé': find.byKey(const Key('cle:empreinte')),
      'Contrôler l’empreinte et restaurer': find.byKey(const Key('cle:restaurer')),
    });
  });

  cas('Paramètres : une liste de référence', 1440, 1000, (t) async {
    await _posteMere(t, 'cfg-systeme');
    await _toucher(t, _onglet('parametres'));
    final carte = _texte('Services de la clinique');
    await _voir(t, carte);
    await _png(t, 'admin-40-param-liste', {'Carte': carte});
  });

  cas('Paramètres : un seuil de clinique', 1440, 1000, (t) async {
    await _posteMere(t, 'cfg-systeme');
    await _toucher(t, _onglet('parametres'));
    final carte = _texte('Renouvellement du mot de passe (jours)');
    await _voir(t, carte);
    await _png(t, 'admin-41-param-seuil', {'Carte': carte});
  });

  cas('Identité : l’e-mail de la clinique', 1440, 1000, (t) async {
    await _posteMere(t, 'cfg-branding');
    await _voir(t, find.textContaining('contact@cliniquebaguidi.com'));
    await _png(t, 'admin-42-identite-email', {'E-mail': find.textContaining('contact@cliniquebaguidi.com')});
  });

  cas('Messagerie (SMTP)', 1440, 1300, (t) async {
    await _posteMere(t, 'cfg-smtp');
    await _png(t, 'admin-43-smtp', {
      'Adresse d’expéditeur': find.byKey(const Key('kit:champ:expediteur')),
      'Répondre à': find.byKey(const Key('kit:champ:repondreA')),
      'Enregistrer la messagerie': _bouton('Enregistrer la messagerie'),
      'Envoyer un message de test': _bouton('Envoyer un message de test'),
    });
  });

  cas('Mère : reprise d’un poste', 1560, 1100, (t) async {
    sourceRepriseInjectee = _SourceReprise();
    addTearDown(() => sourceRepriseInjectee = null);
    await _posteMere(t, 'mere-reprise-poste');
    await _png(t, 'admin-44-mere-reprise', {
      'Identifiant d’appairage': _texte('Identifiant d’appairage'),
      'Générer un code de reprise': _bouton('Générer un code de reprise'),
      'Ce que fait la reprise': _texte('Ce que fait la reprise'),
    });
  });

  cas('Mère : code de reprise affiché', 1560, 1000, (t) async {
    sourceRepriseInjectee = _SourceReprise();
    addTearDown(() => sourceRepriseInjectee = null);
    await _posteMere(t, 'mere-reprise-poste');
    await _toucher(t, find.byKey(const Key('rep:generer:3f7a91c0-5b2e-4d18-9a6c-0e41b7d2a5f3')));
    await _png(t, 'admin-45-reprise-nom', {
      'Nom du poste neuf': find.byKey(const Key('rep:etiquette')),
      'Générer le code': find.byKey(const Key('rep:confirmer')),
    });
    await _toucher(t, find.byKey(const Key('rep:confirmer')));
    await _pomper(t, 6);
    await _png(t, 'admin-46-reprise-code', {
      'Code': find.byKey(const Key('rep:code')),
      'Validité': find.byKey(const Key('rep:validite')),
      'Copier le code': find.byKey(const Key('rep:copier')),
    });
  });

  cas('Import de la liasse fiscale', 1440, 1500, (t) async {
    await _posteMere(t, 'm12-liasse-import', role: 'comptable');
    await _png(t, 'admin-47-liasse-import', {
      'Ce qui fait foi': _texte('Ce qui fait foi'),
      'Fichier (JSON)': find.byKey(const Key('liasse:fichier')),
      'Vérifier le fichier': find.byKey(const Key('liasse:verifier')),
      'Archiver': find.byKey(const Key('liasse:archiver:doc-fiscal-liasse-2025-2026-04-30')),
    });
  });

  cas('Import de la liasse : fichier vérifié', 1440, 1700, (t) async {
    await _posteMere(t, 'm12-liasse-import', role: 'comptable');
    await t.enterText(find.byKey(const Key('liasse:fichier')), 'tool/donnees/liasse_2025_demo.json');
    await t.pump();
    await _toucher(t, find.byKey(const Key('liasse:verifier')));
    await _pomper(t, 4);
    await _png(t, 'admin-48-liasse-verifiee', {
      'Fichier accepté': find.byKey(const Key('liasse:resume')),
      'Date de dépôt': find.byKey(const Key('liasse:date')),
      'Source': find.byKey(const Key('liasse:source')),
      'Importer ce document': find.byKey(const Key('liasse:importer')),
    });
  });

  cas('Fiches d’aide de l’assistant', 1440, 1900, (t) async {
    await _posteMere(t, 'cfg-fiches-aide', role: 'da', magasin: _jeuAvecFiches());
    await _png(t, 'admin-49-fiches-aide', {
      'Fiches attendues': find.byKey(const Key('aide:attendues')),
      'Gabarit vide': find.byKey(const Key('aide:nouvelle')),
      'Valider': find.byKey(const Key('aide:valider:FAI-CAP-1')),
    });
  });

  cas('Fiches d’aide : validation d’une fiche qui engage un professionnel', 1440, 1900, (t) async {
    await _posteMere(t, 'cfg-fiches-aide', role: 'da', magasin: _jeuAvecFiches());
    await _toucher(t, find.byKey(const Key('aide:valider:FAI-CAP-2')));
    await _voir(t, find.byKey(const Key('aide:valider-ok')));
    await _png(t, 'admin-50-fiche-validation', {
      'Validé par (professionnel)': find.byKey(const Key('aide:pro')),
      'Date de sa validation': find.byKey(const Key('aide:pro-le')),
      'Valider la fiche': find.byKey(const Key('aide:valider-ok')),
    });
  });

  cas('Barre : décisions en attente de la mère', 1440, 700, (t) async {
    await _poste(t, 'cfg-systeme', magasin: _jeuAvecAttente());
    await _png(t, 'admin-30-pastille-decisions', {'Pastille': find.byKey(const Key('barre-decisions-mere'))});
  });
}
