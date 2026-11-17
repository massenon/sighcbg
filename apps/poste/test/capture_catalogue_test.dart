import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/controleur_poste.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/mere/activation.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/modules/auth/acc_session.dart';
import 'package:sigh_poste/modules/cfg/cfb_commun.dart' show cfbIdPlanDuSite, cfbPoserReglage;
import 'package:sigh_poste/modules/mere/mrb_source.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';
import 'package:sigh_poste/shell/coque.dart';

import 'activation_test.dart' show FauxService;
import 'aide_polices.dart';
import 'rls_test.dart' as rls;

/// CATALOGUE COMPLET DES ÉCRANS (annexe du manuel d'utilisation, docs/manuels/src/utilisateur/catalogue.html) : CHAQUE écran du manifeste est ouvert
/// dans la coque, sous un rôle qui le voit, sur le jeu de démonstration LIVRÉ dont les noms du personnel sont remplacés par « AGENTnn Démo », et donne
/// un PNG (largeur fixe, rapport de pixels modeste) et un JSON (identifiant, titre, domaine, module, rôle, mode, réussite ou motif d'échec).
/// Un écran qui ne se capture pas n'est jamais omis : son JSON porte le motif.
///
/// Sur demande seulement : `SIGH_CAPTURES=/chemin flutter test test/capture_catalogue_test.dart`.
/// Parallélisable : `SIGH_LOT=1/3` (lot 1 sur 3) — chaque processus prend un écran sur trois.
final String? _sortie = Platform.environment['SIGH_CAPTURES'];
final _lot = Platform.environment['SIGH_LOT'];
final _donnees = DonneesNavigation.depuisDossier();
final _le = DateTime(2026, 11, 16, 10);
const _taille = Size(1440, 900);
const double _ratio = 0.75;

/// Domaines servis par le poste MÈRE (la coque ne les monte qu'en mode mère, avec une source simulée).
const _domainesMere = {'Poste mère', 'Relais en ligne'};

/// Activités fermées par défaut (banque de sang, donneurs) : le magasin de capture les ROUVRE pour que l'écran se dessine.
final List<Map<String, Object?>> _activitesFermees = [
  for (final f in (jsonDecode(File('assets/donnees/modulesActifs.reference.json').readAsStringSync()) as List))
    if ((f as Map)['actif'] == false) f.cast<String, Object?>()
];

/// Le jeu livré neutralisé (noms du personnel remplacés), sérialisé UNE fois par processus ; chaque capture en reconstruit un magasin neuf.
Map<String, String>? _jeuNeutre;
Map<String, Object?>? _referentiels;

Magasin _jeu() {
  if (_jeuNeutre == null) {
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

    _jeuNeutre = {for (final nom in Magasin.collectionsDuJeu) nom: neutre(jsonEncode(m.collection(nom).toutes))};
    _referentiels = (jsonDecode(File('assets/donnees/jeu/referentiels.json').readAsStringSync()) as Map).cast<String, Object?>();
  }
  final m = Magasin({
    for (final e in _jeuNeutre!.entries) e.key: [for (final f in (jsonDecode(e.value) as List)) (f as Map).cast<String, Object?>()]
  }, 'POSTE', _referentiels!);
  // Les activités fermées par défaut sont rouvertes : leur écran se dessine au lieu de l'avis de fermeture.
  final actives = {for (final f in m.collection('modulesActifs').toutes) '${f['id']}': f};
  for (final f in _activitesFermees) {
    actives['${f['id']}'] = {...f, 'actif': true, 'motif': 'Rouverte pour le catalogue des écrans du manuel.'};
  }
  m.collection('modulesActifs').remplacerContenu(actives.values);
  return m;
}

extension on Magasin {
  void let(void Function(Magasin) f) => f(this);
}

Future<void> _pomper(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
}

/// Le service de la mère simulé pour les écrans d'exploitation (lot a) : des appareils sans nom de personne, une supervision plausible, aucun conflit.
Future<http.Response> _serviceMere(http.Request r) async {
  final ms = (Duration d) => _le.subtract(d).millisecondsSinceEpoch;
  final chemin = r.url.path;
  Object corps;
  if (chemin.endsWith('/admin/etat')) {
    corps = {
      'epoch': 3,
      'seq_max': 1240,
      'rep_seq': 1236,
      'conflits_ouverts': 0,
      'appareils': [
        {'uuid': 'u-1', 'etiquette': 'Caisse principale', 'role': 'fileul', 'etat': 'actif', 'dernier_contact': ms(const Duration(minutes: 2)), 'dernier_seq': 1238},
        {'uuid': 'u-2', 'etiquette': 'Réception', 'role': 'fileul', 'etat': 'actif', 'dernier_contact': ms(const Duration(minutes: 6)), 'dernier_seq': 1236},
        {'uuid': 'u-3', 'etiquette': 'Laboratoire', 'role': 'fileul', 'etat': 'actif', 'dernier_contact': ms(const Duration(hours: 5)), 'dernier_seq': 1190},
        {'uuid': 'u-4', 'etiquette': 'Téléphone de garde', 'role': 'mobile', 'etat': 'actif', 'dernier_contact': ms(const Duration(minutes: 40)), 'dernier_seq': 1201, 'profil': 'soignant', 'fonction': 'infirmier'},
      ],
      'alertes': [],
      'derives': [],
      'bloques': [],
      'reinit_ouverte': false,
    };
  } else if (chemin.endsWith('/admin/supervision')) {
    corps = {
      'etat': 'ok',
      'depot': 'pg',
      'controles': [
        {'nom': 'Base de données', 'etat': 'ok', 'detail': 'PostgreSQL joignable'},
        {'nom': 'Sauvegarde', 'etat': 'ok', 'detail': 'Dernière sauvegarde il y a 8,0 h.'},
        {'nom': 'Relais en ligne', 'etat': 'ok', 'detail': '4 opération(s) pas encore répliquées (chiffrées) vers le relais.'},
        {'nom': 'Postes', 'etat': 'attention', 'detail': 'Un poste sans contact depuis plus de 4 h.'},
      ],
    };
  } else if (chemin.endsWith('/admin/conflits') || chemin.endsWith('/admin/journal')) {
    corps = [];
  } else {
    corps = {};
  }
  return http.Response(jsonEncode(corps), 200, headers: {'content-type': 'application/json; charset=utf-8'});
}

void _ecrire(String id, Map<String, Object?> json) {
  Directory(_sortie!).createSync(recursive: true);
  File('$_sortie/$id.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(json));
}

void main() {
  setUpAll(chargerPolices);
  setUp(() => CoquePoste.panneauOuvertAuDemarrage = false);
  tearDown(ToastsSigh.viderPourTests);

  final ecrans = _donnees.manifeste.tousLesEcrans.toList();
  var rang = -1, n = 1, k = 0;
  if (_lot != null) {
    final p = _lot!.split('/');
    k = int.parse(p[0]) - 1;
    n = int.parse(p[1]);
  }
  for (final e in ecrans) {
    rang++;
    if (rang % n != k) continue;
    final id = e.id;
    final mere = _domainesMere.contains(e.domaine);
    final connexion = id == 'index' || id.startsWith('auth-');
    const role = 'admin';
    testWidgets('catalogue : $id', skip: _sortie == null, (t) async {
      final base = <String, Object?>{
        'id': id,
        'titre': _donnees.titreDeclare(id) ?? e.label,
        'libelle': e.label,
        'domaine': e.domaine,
        'module': e.module,
        'moduleLibelle': e.moduleLabel,
        'role': role,
        'mode': mere ? 'mère' : 'fileul',
      };
      _ecrire(id, {...base, 'capture': false, 'motif': 'Capture interrompue avant l’écriture de l’image.'});
      final debut = DateTime.now();
      t.view.physicalSize = _taille;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      if (mere) {
        mrbSourceInjectee = rls.fauxRelais();
        mrbIntervalle = const Duration(hours: 1);
      }
      addTearDown(() => mrbSourceInjectee = null);
      final client = mere ? ClientMere(base: Uri.parse('http://x'), secretAdmin: 's', client: MockClient(_serviceMere)) : null;
      // Les réglages du poste (cfg-poste) ne se montent qu'avec le contrôleur du poste : un contrôleur sur stockage en mémoire, sans réseau.
      final controleur = id == 'cfg-poste'
          ? ControleurPoste(
              activation: ActivationMere(
                  stockage: StockageMemoire(const ParametresPoste(uuidPoste: 'poste-demo')),
                  service: FauxService(),
                  relaisPour: (_, __) => throw StateError('hors ligne')),
              config: const ConfigPoste(mode: ModePoste.fileul, role: role))
          : null;
      final avertissements = <String>[];
      try {
        await t.pumpWidget(RepaintBoundary(
            key: const Key('cap-catalogue'),
            child: SighPoste(
                key: UniqueKey(),
                donnees: _donnees,
                config: ConfigPoste(mode: mere ? ModePoste.mere : ModePoste.fileul, role: role),
                client: client,
                controleur: controleur,
                ecranInitial: id,
                // Le plan du site est désactivé par défaut (réglage du système) : le magasin de capture l'active pour ce seul écran.
                magasin: id == 'plan-du-site' ? (_jeu()..let((m) => cfbPoserReglage(m, cfbIdPlanDuSite, true))) : _jeu(),
                session: connexion ? SessionPoste(exigeConnexion: true, horloge: () => _le) : null,
                horloge: () => _le)));
        await _pomper(t);
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
        await _pomper(t, 3);
        for (Object? x = t.takeException(); x != null; x = t.takeException()) {
          avertissements.add('$x'.split('\n').first);
        }
        final affiches = {for (final c in find.byType(ContexteEcran).evaluate()) (c.widget as ContexteEcran).ecranId};
        String? motif;
        if (find.byKey(const Key('ecran-a-porter')).evaluate().isNotEmpty) {
          motif = 'L’écran n’est pas encore porté sur le poste : la coque affiche l’avis « écran à porter ».';
        } else if (find.byKey(const Key('activite-fermee')).evaluate().isNotEmpty) {
          motif = 'L’activité de cet écran est fermée : la coque affiche l’avis de fermeture.';
        } else if (id != 'error-403' && affiches.contains('error-403')) {
          motif = 'Accès refusé au rôle de capture (page 403).';
        } else if (id != 'error-404' && (affiches.contains('error-404') || find.text('Page introuvable').hitTestable().evaluate().isNotEmpty)) {
          motif = 'Écran inconnu de la coque (page 404).';
        }
        await t.runAsync(() async {
          final RenderRepaintBoundary b = t.renderObject(find.byKey(const Key('cap-catalogue')));
          final ui.Image img = await b.toImage(pixelRatio: _ratio);
          final d = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$_sortie/$id.png').writeAsBytesSync(d!.buffer.asUint8List());
        });
        _ecrire(id, {
          ...base,
          'capture': true,
          if (motif != null) 'avis': motif,
          'ecransAffiches': affiches.toList()..sort(),
          if (avertissements.isNotEmpty) 'avertissements': avertissements,
          'largeur': (_taille.width * _ratio).round(),
          'hauteur': (_taille.height * _ratio).round(),
          'dureeMs': DateTime.now().difference(debut).inMilliseconds,
        });
      } catch (x) {
        _ecrire(id, {...base, 'capture': false, 'motif': 'Erreur au rendu : ${'$x'.split('\n').first}', 'dureeMs': DateTime.now().difference(debut).inMilliseconds});
      }
      // Les erreurs restantes (minuteurs, futures) ne doivent pas faire échouer le lot : elles sont déjà au JSON ou sans effet sur l'image.
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 10));
      while (t.takeException() != null) {}
    });
  }
}
