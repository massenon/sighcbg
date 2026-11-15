// Lot AST-1 : l'ÉCRAN de l'assistant et son service de poste. Prouve : une conversation se tient sous les droits de l'agent ; la source cliquable ne mène qu'à un écran qu'il
// voit ; un droit absent, une écriture demandée, un avis médical sont refusés EN LES NOMMANT ; rien n'est écrit au magasin ; la conversation est chiffrée sur disque, jamais
// dans le magasin (donc jamais synchronisée), purgée à 30 jours, effaçable ; un fichier illisible n'est jamais écrasé ; les états vide, chargement et erreur se disent.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/service_assistant.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 11, 14, 10);

/// Un magasin de démonstration COMPLET (le jeu livré) : l'assistant lit de vraies collections.
Magasin magasinJeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

/// Le code d'un patient du jeu livré (jamais écrit en dur : le jeu se régénère).
String codeDuJeu(Magasin m) => '${m.collection('patients').actives.firstWhere((p) => RegExp(r'^[A-Z]+/\d+/\d{2}$').hasMatch('${p['code']}'))['code']}';

Future<void> monter(WidgetTester t, Magasin m, {String role = 'reception', DateTime? maintenant}) async {
  t.view.physicalSize = const Size(1600, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.fileul, role: role), ecranInitial: 'sup-assistant', magasin: m, horloge: () => maintenant ?? auj));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Laisse finir ce que la coque fait seule à l'ouverture (elle archive, par exemple, des doublons du plan comptable) : on mesure l'assistant, pas le démarrage.
Future<void> calmer(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

Future<void> demander(WidgetTester t, String question) async {
  await t.enterText(find.byKey(const Key('assistant:champ')), question);
  await t.pump();
  await t.tap(find.byKey(const Key('assistant:envoyer')));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

String textes(WidgetTester t) => [for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? ''].join(' | ');

/// Une empreinte de TOUT le magasin : si l'assistant écrivait quelque part, elle changerait.
///
/// Deux collections sont ÉCARTÉES de la mesure : `comptes` et `garanties`. À leur toute première ouverture le magasin lui-même archive les doublons du plan comptable et
/// migre le rang des garanties (voir `Magasin.collection`) ; ce sont des écritures du magasin, qu'aucune question de l'assistant ne provoque — le test du domaine
/// vérifie que l'assistant ne lit jamais ces deux collections.
String empreinte(Magasin m) {
  final b = StringBuffer();
  for (final nom in Magasin.collectionsDuJeu.where((n) => n != 'comptes' && n != 'garanties')) {
    b.write('$nom:${m.collection(nom).toutes.length}:${jsonEncode(m.collection(nom).toutes.take(3).toList())};');
  }
  return b.toString();
}

void main() {
  setUpAll(chargerPolices);
  setUp(() => ServiceAssistant.stockageDuPoste = StockageMemoire());
  tearDown(() => ServiceAssistant.stockageDuPoste = null);

  void cas(String nom, Future<void> Function(WidgetTester) corps) => testWidgets(nom, (t) async {
        await corps(t);
        ToastsSigh.viderPourTests();
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 10));
      });

  group('la conversation sous les droits de l’agent', () {
    cas('état vide : aucune question, des exemples limités à ce que le profil lit', (t) async {
      await monter(t, magasinJeu());
      expect(find.byKey(const Key('assistant:vide')), findsOneWidget);
      expect(find.byKey(const Key('assistant:chargement')), findsNothing);
      final ex = textes(t);
      expect(ex, contains('Retrouve le patient'));
      expect(ex, isNot(contains('valeur du stock')), reason: 'la réception ne lit pas le stock : on ne lui propose pas la question');
      expect(textes(t), contains('Lecture seule'));
      expect(textes(t), contains('30 jours'));
    });

    cas('une question sur un patient : réponse, tableau ou lignes, et SOURCE cliquable vers un écran que l’agent voit', (t) async {
      final m = magasinJeu();
      final code = codeDuJeu(m);
      await monter(t, m);
      await demander(t, 'Retrouve le patient $code');
      expect(find.byKey(const Key('assistant:tour-0')), findsOneWidget);
      expect(textes(t), contains('Dossier $code'));
      expect(find.byKey(const Key('assistant:source-m1-patients')), findsOneWidget);
      expect(find.byKey(const Key('assistant:vide')), findsNothing);
    });

    cas('un droit absent est dit : la réception ne lit pas le stock, aucune source n’est offerte', (t) async {
      await monter(t, magasinJeu());
      await demander(t, 'Quelle est la valeur du stock ?');
      expect(textes(t), contains('LECTURE_NON_AUTORISEE'));
      expect(textes(t), contains('Vous n’avez pas le droit'));
      expect(find.textContaining('Source :'), findsNothing);
    });

    cas('le même texte, un autre profil : le stock répond à qui le lit', (t) async {
      await monter(t, magasinJeu(), role: 'stock');
      await demander(t, 'Quelle est la valeur du stock ?');
      expect(textes(t), contains('Valeur du stock au CUMP'));
      expect(find.byKey(const Key('assistant:source-m6-point-stock')), findsOneWidget);
    });

    cas('une écriture demandée est refusée en nommant l’écran, sans rien écrire au magasin', (t) async {
      final m = magasinJeu();
      await monter(t, m, role: 'caissier');
      await calmer(t);
      final avant = empreinte(m);
      await demander(t, 'Annule la facture FN-2026-00001');
      expect(textes(t), contains('ECRITURE_ABSENTE'));
      expect(textes(t), contains('lecture seule'));
      expect(find.byKey(const Key('assistant:ouvrir-m8-facture-avoir')), findsOneWidget);
      expect(empreinte(m), avant, reason: 'aucune écriture : ni donnée, ni journal');
    });

    cas('un avis médical et un envoi hors de la clinique sont refusés, une question hors catalogue propose', (t) async {
      await monter(t, magasinJeu(), role: 'medecin');
      await demander(t, 'Quel traitement pour le paludisme ?');
      expect(textes(t), contains('AVIS_MEDICAL_REFUSE'));
      await demander(t, 'Envoie les impayés par mail');
      expect(textes(t), contains('ENVOI_EXTERNE_REFUSE'));
      await demander(t, 'Quelle est la capitale du Bénin ?');
      expect(textes(t), contains('INTENTION_INCONNUE'));
    });

    cas('« ce patient » reprend le patient de la conversation', (t) async {
      final m = magasinJeu();
      final code = codeDuJeu(m);
      await monter(t, m, role: 'caissier');
      await demander(t, 'Combien doit encore ce patient ?');
      expect(textes(t), contains('De quel patient'));
      await demander(t, 'Retrouve le patient $code');
      await demander(t, 'Combien doit encore ce patient ?');
      expect(textes(t), contains('$code —'), reason: 'la réponse porte le patient de la conversation');
    });
  });

  group('rien n’est écrit au magasin, la conversation vit à part', () {
    cas('après une conversation, le magasin est identique ; la conversation est dans le stockage du poste, pas dans une collection', (t) async {
      final m = magasinJeu();
      final stockage = ServiceAssistant.stockageDuPoste as StockageMemoire;
      await monter(t, m, role: 'stock');
      await calmer(t);
      final avant = empreinte(m);
      await demander(t, 'Quels articles sont en rupture ?');
      await demander(t, 'Quelle est la valeur du stock ?');
      expect(empreinte(m), avant);
      expect(stockage.fichiers.length, 1);
      expect(stockage.fichiers.values.single, contains('Quels articles sont en rupture'));
      // DÉCISION DU 16/11/2026 : le FAIT d'ouvrir l'assistant est journalisé (RG-12) — une seule ligne d'ouverture, posée par le service de poste ; les questions, elles, ne laissent
      // aucune ligne (l'empreinte ci-dessus, journal compris, n'a pas bougé entre les deux questions).
      final lignes = m.collection('audit').toutes.where((a) => '${a['action']}'.toLowerCase().contains('assistant')).toList();
      expect(lignes.length, 1);
      expect(lignes.single['action'], 'Ouverture de l’assistant');
      expect(lignes.single['module'], 'SUP');
      expect(lignes.single['utilisateur'], isNotEmpty);
      expect(lignes.single['poste'], isNotNull);
      expect(lignes.single['dateHeure'], isNotNull);
    });

    cas('le journal ne contient JAMAIS un mot de la question (ni de la réponse) : une question qui porte un nom de patient', (t) async {
      final m = magasinJeu();
      await monter(t, m, role: 'caissier');
      await calmer(t);
      await demander(t, 'Combien doit encore Zoumarou Kassifa EXEMPLE/Patient ?');
      await demander(t, 'Retrouve le patient Zoumarou');
      await t.pumpWidget(const SizedBox());
      await t.pump();
      final journal = jsonEncode([for (final a in m.collection('audit').toutes) a]).toLowerCase();
      for (final mot in ['zoumarou', 'kassifa', 'exemple/patient', 'combien doit', 'retrouve le patient']) {
        expect(journal.contains(mot), isFalse, reason: mot);
      }
      final f = m.collection('audit').toutes.where((a) => a['action'] == 'Fermeture de l’assistant').toList();
      expect(f.length, 1, reason: 'la fermeture porte le nombre de questions');
      expect((f.single['apres'] as Map)['questions'], 2);
      expect((f.single['apres'] as Map).keys.toList(), ['questions'], reason: 'un compte, rien d\'autre');
    });

    cas('le service seul : l\'ouverture se trace une fois, la fermeture porte le compte, sans question aucune ligne de fermeture', (t) async {
      final lignes = <(String, Map<String, Object?>?)>[];
      ServiceAssistant s() => ServiceAssistant(stockage: StockageMemoire(), agent: 'u', retention: () => 30, maintenant: () => auj)
        ..journal = (a, r, d) => lignes.add((a, d));
      final a = s()..tracerOuverture()..tracerOuverture();
      a.tracerFermeture();
      expect(lignes.map((l) => l.$1), ['Ouverture de l’assistant'], reason: 'ouverture unique ; aucune question, aucune fermeture');
      final b = s()..tracerOuverture();
      await b.charger();
      await b.poser('une question', ContexteAst(role: 'x', lire: (_) => const [], peutVoirEcran: (_) => false, sensibles: DroitsSensibles(fiches: const [], peutVoirEcran: (_, __) => false), maintenant: auj, session: const SessionLabo(role: 'x')));
      b.tracerFermeture();
      expect(lignes.last.$1, 'Fermeture de l’assistant');
      expect(lignes.last.$2, {'questions': 1});
      expect(lignes.every((l) => !'${l.$2}'.contains('une question')), isTrue);
    });

    cas('aucune collection du magasin ne porte la conversation : le nom n’existe pas parmi celles du jeu ni de la synchronisation', (t) async {
      expect(Magasin.collectionsDuJeu.where((c) => c.toLowerCase().contains('assistant') || c.toLowerCase().contains('conversation')), isEmpty);
    });
  });

  group('purge, effacement, états', () {
    cas('la purge : à l’ouverture, ce qui a plus de 30 jours disparaît du fichier ET de l’écran', (t) async {
      final stockage = ServiceAssistant.stockageDuPoste as StockageMemoire;
      final vieux = TourAst(id: 'v', quand: DateTime.utc(2026, 10, 1).toIso8601String(), question: 'Question très ancienne', reponse: const ReponseAst(statut: 'reponse', titre: 'Réponse ancienne'));
      final recent = TourAst(id: 'r', quand: DateTime.utc(2026, 11, 13).toIso8601String(), question: 'Question de la veille', reponse: const ReponseAst(statut: 'reponse', titre: 'Réponse de la veille'));
      final m = magasinJeu();
      // l'identifiant de l'agent de démonstration de la réception : la clé du fichier
      stockage.fichiers['__à poser__'] = '';
      stockage.fichiers.clear();
      await monter(t, m);
      final cle = ServiceAssistant.stockageDuPoste as StockageMemoire;
      // la première ouverture n'a rien écrit : on pose le fichier sous la clé réellement utilisée en rouvrant avec une conversation
      await demander(t, 'Agenda du jour');
      final agent = cle.fichiers.keys.single;
      cle.fichiers[agent] = jsonEncode([vieux.toJson(), recent.toJson()]);
      await monter(t, m);
      expect(textes(t), contains('Question de la veille'));
      expect(textes(t), isNot(contains('Question très ancienne')));
      expect(cle.fichiers[agent], isNot(contains('Question très ancienne')), reason: 'purgé du disque aussi');
      expect(cle.fichiers[agent], contains('Question de la veille'));
    });

    cas('effacer la conversation : confirmation, puis le fichier disparaît', (t) async {
      final stockage = ServiceAssistant.stockageDuPoste as StockageMemoire;
      await monter(t, magasinJeu());
      await demander(t, 'Agenda du jour');
      expect(stockage.fichiers, isNotEmpty);
      await t.tap(find.byKey(const Key('assistant:effacer')));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Effacer').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(stockage.fichiers, isEmpty);
      expect(find.byKey(const Key('assistant:vide')), findsOneWidget);
    });

    cas('état d’erreur : un fichier illisible est DIT, la conversation repart vide, le fichier n’est pas écrasé', (t) async {
      final stockage = _Illisible();
      ServiceAssistant.stockageDuPoste = stockage;
      await monter(t, magasinJeu());
      expect(find.byKey(const Key('assistant:erreur')), findsOneWidget);
      expect(textes(t), contains('n’a pas pu être relue'));
      await demander(t, 'Agenda du jour');
      expect(stockage.ecritures, 0, reason: 'un fichier illisible n’est jamais écrasé');
      expect(find.byKey(const Key('assistant:tour-0')), findsOneWidget);
    });

    cas('état de chargement : le bouton ne part pas avant la lecture de la conversation', (t) async {
      final lent = _Lent();
      ServiceAssistant.stockageDuPoste = lent;
      t.view.physicalSize = const Size(1600, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(SighPoste(key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.fileul, role: 'reception'), ecranInitial: 'sup-assistant', magasin: magasinJeu(), horloge: () => auj));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('assistant:chargement')), findsOneWidget);
      lent.liberer();
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('assistant:chargement')), findsNothing);
      expect(find.byKey(const Key('assistant:vide')), findsOneWidget);
    });
  });

  group('le service de poste : chiffrement au repos, durée réglable et bornée', () {
    test('sur disque, la conversation est chiffrée : la question n’y figure pas en clair, et une autre clé ne la lit pas', () async {
      final dossier = Directory.systemTemp.createTempSync('ast');
      addTearDown(() => dossier.deleteSync(recursive: true));
      final cle = List<int>.generate(32, (i) => i + 1);
      final s = StockageFichierAssistant(dossier.path, cle: cle);
      final svc = ServiceAssistant(stockage: s, agent: 'USR-1', retention: () => 30, maintenant: () => auj);
      await svc.charger();
      final cx = ContexteAst(
          role: 'admin', lire: (n) => const [], peutVoirEcran: (_) => true, sensibles: DroitsSensibles(fiches: const []), maintenant: auj);
      await svc.poser('Question secrète EXEMPLE', cx);
      final fichiers = dossier.listSync().whereType<File>().toList();
      expect(fichiers.length, 1);
      final brut = fichiers.single.readAsStringSync();
      expect(brut, isNot(contains('secrète')));
      expect(brut, contains('chiffre'));
      expect(fichiers.single.path, isNot(contains('USR-1')), reason: 'le nom de fichier ne porte pas l’identifiant en clair');
      // relue avec la bonne clé
      final svc2 = ServiceAssistant(stockage: StockageFichierAssistant(dossier.path, cle: cle), agent: 'USR-1', retention: () => 30, maintenant: () => auj);
      await svc2.charger();
      expect(svc2.tours.single.question, 'Question secrète EXEMPLE');
      // une autre clé : erreur nommée, aucune lecture
      final svc3 = ServiceAssistant(stockage: StockageFichierAssistant(dossier.path, cle: List<int>.filled(32, 9)), agent: 'USR-1', retention: () => 30, maintenant: () => auj);
      await svc3.charger();
      expect(svc3.erreur, contains('illisible'));
      expect(svc3.tours, isEmpty);
      expect(fichiers.single.readAsStringSync(), brut, reason: 'le fichier illisible n’est pas touché');
      // un autre agent n’a pas cette conversation
      final autre = ServiceAssistant(stockage: StockageFichierAssistant(dossier.path, cle: cle), agent: 'USR-2', retention: () => 30, maintenant: () => auj);
      await autre.charger();
      expect(autre.tours, isEmpty);
    });

    test('la purge des fichiers : une conversation dont la dernière question a plus de 30 jours est supprimée, sans que son agent revienne', () async {
      final dossier = Directory.systemTemp.createTempSync('ast');
      addTearDown(() => dossier.deleteSync(recursive: true));
      final s = StockageFichierAssistant(dossier.path, cle: List<int>.filled(32, 3));
      await s.ecrire('AGENT-ANCIEN', '[]');
      await s.ecrire('AGENT-RECENT', '[]');
      final ancien = dossier.listSync().whereType<File>().firstWhere((f) => f.path.contains('assistant-'));
      // on vieillit UN des deux fichiers de 45 jours
      final fichiers = dossier.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
      fichiers.first.setLastModifiedSync(auj.subtract(const Duration(days: 45)));
      expect(ancien.existsSync(), isTrue);
      final n = await s.purgerPerimes(auj, 30);
      expect(n, 1);
      expect(dossier.listSync().whereType<File>().length, 1);
      expect(await s.purgerPerimes(auj, 30), 0);
    });

    test('la durée de conservation vient de la base : 30 par défaut, réglable, bornée', () {
      final m = magasinJeu();
      expect(ServiceAssistant.retentionDepuis(m, auj), 30);
      final s = serviceParametres(m, auteur: () => 'test', horloge: () => auj);
      s.semerDefauts();
      expect(ServiceAssistant.retentionDepuis(m, auj), 30);
      final r = s.regler(astCleRetention, 7, parametreDateIso(auj));
      expect(r.ok, isTrue, reason: '${r.refus?.motif}');
      expect(ServiceAssistant.retentionDepuis(m, auj), 7);
    });

    test('un réglage hors bornes retombe sur 30 jours (jamais infini, jamais nul)', () {
      for (final v in [0, 500, -1]) {
        expect(astRetentionJours(v), 30);
      }
    });
  });
}

class _Illisible implements StockageConversation {
  int ecritures = 0;
  @override
  Future<String?> lire(String agent) async => throw const FormatException('fichier altéré');
  @override
  Future<void> ecrire(String agent, String contenu) async => ecritures++;
  @override
  Future<void> effacer(String agent) async {}
  @override
  Future<int> purgerPerimes(DateTime maintenant, int jours) async => 0;
}

class _Lent implements StockageConversation {
  final _c = Completer<String?>();
  void liberer() => _c.complete(null);
  @override
  Future<String?> lire(String agent) => _c.future;
  @override
  Future<void> ecrire(String agent, String contenu) async {}
  @override
  Future<void> effacer(String agent) async {}
  @override
  Future<int> purgerPerimes(DateTime maintenant, int jours) async => 0;
}
