import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/identifiants.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// PLAN étape 9 : la configuration de la mère voyage jusqu'au fileul. D'abord avec des faux (règles), puis avec les TROIS pièces réelles (mère, moteur
/// fileul, magasins).
typedef M = Map<String, Object?>;
final auj = DateTime(2026, 11, 2, 9);
const secret = 'Clinique#Natitingou26';

Magasin mere() => Magasin({
      'utilisateurs': [
        {'id': 'USR001', 'statut': 'actif', 'identifiant': 'k.agbuzia', 'nomComplet': 'AGBUZIA Kiafour', 'role': 'admin', 'echecs': 0}
      ],
      'actes': [
        {'id': 'ACT1', 'code': 'CS', 'libelle': 'Consultation', 'prix': 3000},
        {'id': 'ACT2', 'code': 'PS', 'libelle': 'Pansement', 'prix': 9000},
      ],
      'personnel': [
        {'id': 'PER1', 'nom': 'AGORO', 'fonction': 'infirmier', 'salaireBase': 150000, 'cnss': '123456'}
      ],
      'patients': [
        {'id': 'P1', 'nom': 'BIO'}
      ],
    });

Magasin fileul() => Magasin({'utilisateurs': <M>[], 'actes': <M>[]});

void main() {
  setUp(() => ServiceIdentifiants.parametres = AccParametresHachage.tests);
  tearDown(() => ServiceIdentifiants.parametres = AccParametresHachage.production);

  group('publication par la mère', () {
    test('seules les collections de configuration partent ; la rémunération reste sur la mère (RG-13)', () async {
      final envoye = <String, M>{};
      final p = PublicateurConfiguration(mere(), (c, f, champs) async => envoye['$c/$f'] = champs, delai: Duration.zero);
      final n = await p.pousser();
      expect(n, greaterThanOrEqualTo(4));
      expect(envoye.keys, containsAll(['actes/ACT1', 'actes/ACT2', 'utilisateurs/USR001', 'personnel/PER1']));
      expect(envoye.keys.any((k) => k.startsWith('patients/')), isFalse, reason: 'l’activité ne part pas');
      expect(envoye['personnel/PER1']!.containsKey('salaireBase'), isFalse);
      expect(envoye['personnel/PER1']!.containsKey('cnss'), isFalse);
      expect(envoye['personnel/PER1']!['fonction'], 'infirmier');
    });

    test('une fiche inchangée n’est pas republiée ; une fiche modifiée repart seule', () async {
      final m = mere();
      var envois = 0;
      final p = PublicateurConfiguration(m, (c, f, champs) async => envois++, delai: Duration.zero);
      await p.pousser();
      final premier = envois;
      expect(await p.pousser(), 0);
      expect(envois, premier);
      m.collection('actes').mettreAJour('ACT1', {'prix': 3500});
      expect(await p.pousser(), 1);
    });

    test('un échec n’est pas perdu : il est dit, puis la fiche repart au tour suivant', () async {
      var panne = true;
      final recu = <String>[];
      final p = PublicateurConfiguration(mere(), (c, f, champs) async {
        if (panne) throw StateError('mère injoignable');
        recu.add('$c/$f');
      }, delai: const Duration(hours: 1));
      await p.pousser();
      expect(p.erreur.value, contains('mère injoignable'));
      expect(recu, isEmpty);
      panne = false;
      await p.pousser();
      expect(p.erreur.value, isNull);
      expect(recu, contains('actes/ACT1'));
    });
  });

  group('application par le fileul', () {
    Future<List<PieceSync>> depuis(Map<String, List<M>> diffuse) async => [];

    ApplicateurConfiguration appl(Magasin m, Map<String, List<M>> diffuse) =>
        ApplicateurConfiguration(m, (c) async => [for (final f in diffuse[c] ?? const <M>[]) PieceSync('${f['id']}', f)]);

    test('les fiches reçues sont appliquées sans journal local, et un second tour ne change rien', () async {
      final m = fileul();
      final a = appl(m, {
        'actes': [
          {'id': 'ACT1', 'libelle': 'Consultation', 'prix': 3000}
        ]
      });
      expect(await a.tirer(), 1);
      expect(m.collection('actes').toutes.single['libelle'], 'Consultation');
      expect(m.collection('audit').toutes, isEmpty, reason: 'la mère a déjà journalisé');
      expect(await a.tirer(), 0);
      expect(a.recues.value, 1);
    });

    test('une configuration modifiée sur la mère remplace la copie du fileul', () async {
      final m = fileul();
      final diffuse = {
        'actes': [
          {'id': 'ACT1', 'prix': 3000}
        ]
      };
      final a = appl(m, diffuse);
      await a.tirer();
      diffuse['actes'] = [
        {'id': 'ACT1', 'prix': 3500}
      ];
      expect(await a.tirer(), 1);
      expect(m.collection('actes').parId('ACT1')!['prix'], 3500);
    });

    test('le fileul REFUSE d’écrire la configuration, en disant pourquoi ; les comptes restent écrivables', () async {
      final m = fileul();
      final a = appl(m, {
        'actes': [
          {'id': 'ACT1', 'prix': 3000}
        ],
        'utilisateurs': [
          {'id': 'USR001', 'identifiant': 'k.agbuzia', 'echecs': 0}
        ]
      });
      a.demarrer(intervalle: const Duration(hours: 1));
      await Future<void>.delayed(const Duration(milliseconds: 100)); // le premier tour part avec `demarrer`
      a.arreter();
      expect(() => m.collection('actes').mettreAJour('ACT1', {'prix': 1}), throwsA(isA<EcritureRefusee>()));
      expect(() => m.collection('actes').inserer({'id': 'ACT9'}), throwsA(isA<EcritureRefusee>()));
      expect(m.collection('actes').parId('ACT1')!['prix'], 3000);
      try {
        m.collection('actes').archiver('ACT1');
      } on EcritureRefusee catch (e) {
        expect(e.motif, ApplicateurConfiguration.motifGarde);
      }
      m.collection('utilisateurs').mettreAJour('USR001', {'echecs': 1});
      expect(m.collection('utilisateurs').parId('USR001')!['echecs'], 1, reason: 'le compteur d’échecs est local au poste');
    });

    test('une fiche archivée sur la mère l’est sur le fileul (RG-14)', () async {
      final m = fileul();
      final a = appl(m, {
        'actes': [
          {'id': 'ACT1', 'prix': 3000}
        ]
      });
      await a.tirer();
      expect(depuis, isNotNull);
      final b = ApplicateurConfiguration(m, (c) async => [if (c == 'actes') const PieceSync('ACT1', {'id': 'ACT1', 'prix': 3000}, archive: true)]);
      await b.tirer();
      expect(m.collection('actes').archivees.single['id'], 'ACT1');
    });
  });

  test('BOUT EN BOUT : mère réelle, moteur fileul réel, deux magasins ; le compte créé sur la mère se connecte sur le fileul', () async {
    const port = 19432;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-cfg'));
    await mere0.demarrer();
    final mm = mere();
    await ServiceIdentifiants.de(mm).definir('USR001', secret, par: 'test', doitChanger: false, maintenant: auj);
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero);
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'Caisse');
    final mf = fileul();
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    final envoyes = <String>[];
    final pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final pontF = PontActivite(mf,
        TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) {
          envoyes.add('$c/$f existe=$existe ${champs}');
          moteur.ecrire(c, f, existe: existe, champs: champs);
        }),
        etiquette: 'F');
    try {
      expect(await pub.pousser(), greaterThanOrEqualTo(3));
      await pontM.cycle();
      expect(pontM.erreur.value, isNull);
      expect(pub.erreur.value, isNull);
      final code = await console.codeAppareil('Caisse').timeout(const Duration(seconds: 20));
      // Le fileul ne connaît pas encore la mère : l'adresse est saisie à l'écran « Rejoindre », puis le code est consommé.
      await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
      moteur.demarrer();
      final fin = DateTime.now().add(const Duration(seconds: 25));
      while (mf.collection('actes').toutes.length < 2 || mf.collection('identifiants').toutes.isEmpty) {
        await appl.tirer();
        await pontF.cycle();
        if (DateTime.now().isAfter(fin)) fail('la configuration n’est pas arrivée : ${mf.collection('actes').toutes.length} actes, ${mf.collection('identifiants').toutes.length} identifiants');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(mf.collection('actes').parId('ACT2')!['prix'], 9000);
      expect(mf.collection('utilisateurs').toutes.single['identifiant'], 'k.agbuzia');
      // Le haché voyage : le mot de passe défini sur la mère ouvre la session sur le fileul.
      final r = await ServiceIdentifiants.de(mf).verifier(identifiant: 'k.agbuzia', motDePasse: secret, rolesArchives: const {}, libelleRole: (x) => x, maintenant: auj);
      expect(r.decision.accepte, isTrue);
      // L'activité synchronisable arrive aussi (le pont) ; la rémunération, elle, ne part pas.
      await pontF.cycle();
      expect(mf.collection('patients').toutes.single['nom'], 'BIO');
      expect(mf.collection('personnel').toutes.single.containsKey('salaireBase'), isFalse);
      // MOT DE PASSE REMONTÉ : l'agent le change sur le fileul, la mère le reçoit et le vérifie.
      const nouveau = 'Nouveau-mdp-9';
      await ServiceIdentifiants.de(mf).definir('USR001', nouveau, par: 'k.agbuzia', doitChanger: false, maintenant: auj.add(const Duration(days: 1)));
      final fin2 = DateTime.now().add(const Duration(seconds: 25));
      while (true) {
        await pontF.cycle();
        await pontM.cycle();
        if (mm.collection('identifiants').parId('USR001')!['hash'] == mf.collection('identifiants').parId('USR001')!['hash']) break;
        if (DateTime.now().isAfter(fin2)) fail('le mot de passe changé sur le fileul n’est pas remonté à la mère (envoyés : $envoyes, erreurs : ${pontF.erreur.value} ${pontM.erreur.value})');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final r2 = await ServiceIdentifiants.de(mm).verifier(identifiant: 'k.agbuzia', motDePasse: nouveau, rolesArchives: const {}, libelleRole: (x) => x, maintenant: auj.add(const Duration(days: 1)));
      expect(r2.decision.accepte, isTrue, reason: 'la mère ouvre la session avec le NOUVEAU mot de passe');
    } finally {
      appl.arreter();
      pub.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('un MOBILE reçoit la configuration de la clinique mais JAMAIS les hachés des mots de passe (RG-13) ; un fileul reçoit tout', () async {
    const port = 19434;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-cfg2'));
    await mere0.demarrer();
    final http0 = HttpClient();
    Future<Map<String, Object?>> appel(String methode, String chemin, {Map<String, Object?>? corps, Map<String, String> entetes = const {}}) async {
      final req = await http0.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
      req.headers.contentType = ContentType.json;
      entetes.forEach(req.headers.set);
      if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
      final rep = await req.close();
      return (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
    }

    try {
      final mm = mere();
      await ServiceIdentifiants.de(mm).definir('USR001', secret, par: 'test', doitChanger: false, maintenant: auj);
      final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero);
      await pub.pousser();
      await PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M').cycle();
      // Une opération de la famille d'origine (produits), que le mobile a le droit de lire.
      await appel('POST', '/admin/referentiel', corps: {'collection': 'produits', 'fiche': 'PRD1', 'champs': {'libelle': 'Paracétamol'}}, entetes: {'x-admin': 'secret-test'});

      Future<List<String>> collectionsRecues(String role, Map<String, Object?> extra) async {
        final code = (await appel('POST', '/admin/code', corps: {'etiquette': role, 'role': role, ...extra}, entetes: {'x-admin': 'secret-test'}))['code'];
        final uuid = 'dev-$role';
        final jetons = await appel('POST', '/appairage', corps: {'code': code, 'uuid': uuid, 'plateforme': 'test'});
        final pull = await appel('GET', '/sync/pull?depuis=0&limite=500&epoch=${jetons['epoch']}', entetes: {'authorization': 'Bearer ${jetons['jeton']}'});
        return [for (final o in (pull['ops'] as List)) '${(o as Map)['collection']}'];
      }

      final fileul = await collectionsRecues('fileul', {});
      expect(fileul, containsAll(['utilisateurs', 'identifiants', 'actes', 'personnel', 'produits']));
      final mobile = await collectionsRecues('mobile', {'profil': 'reception'});
      expect(mobile, contains('produits'), reason: 'le référentiel que ses écrans lisent lui reste visible');
      expect(mobile, containsAll(['actes', 'utilisateurs', 'personnel']), reason: 'la configuration de la clinique arrive sur le téléphone');
      expect(mobile, isNot(contains('identifiants')), reason: 'un téléphone perdu ne doit pas emporter les empreintes des mots de passe');
    } finally {
      http0.close(force: true);
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  // LES PARAMÈTRES DE L'AIB voyagent du poste qui les valide vers un second poste (Direction, 09/11/2026) : base, branchement IFU, validations du barème.
  group('paramètres de l\'AIB : une validation faite sur un poste arrive sur un second', () {
    Map<String, Object?> version(String id, String rubrique, int n, Map<String, Object?> champs, {String? effet}) => {
          'id': id, 'statut': 'actif', 'rubrique': rubrique, 'version': n, if (effet != null) 'dateEffet': effet,
          'decideur': 'Direction', 'dateDecision': '2026-10-29', 'motif': 'Décision', ...champs,
        };

    test('la collection fait partie de la configuration diffusée, et ses libellés sont connus', () {
      expect(collectionsConfiguration(), containsAll(['parametresAib', 'baremeAib', 'situationsAib']));
      expect(cfbLibellesCollections['parametresAib'], isNotNull);
    });

    test('MÈRE → FILEUL (publication puis application) : les versions arrivent, la lecture à une date donne la même base et le même repli', () async {
      final mm = Magasin({
        'parametresAib': [
          ...cpaFichesGraine(),
          version('PAA-BASE-2', 'base_retenue', 2, {'base': 'facture'}, effet: '2026-10-20'),
          version('PAA-IFU-2', 'branchement_ifu', 2, {'longueurIfu': 13, 'situationIfuRenseigne': 'ifu_actif', 'situationIfuAbsent': 'ifu_inactif_ou_absent', 'tauxRepli': 2}, effet: '2026-10-20'),
          version('PAA-BAR-1', 'bareme', 1, {'choix': 'arreter', 'versionBaremeId': 'BAI02'}),
        ],
        'baremeAib': [
          {'id': 'BAI01', 'statut': 'actif', 'situation': 'ifu_inactif_ou_absent', 'taux': 5, 'dateEffet': '2026-09-07', 'arrete': true, 'statutArret': 'arrete', 'decideurArret': 'Direction'},
        ],
        'situationsAib': [
          {'id': 'SAI01', 'statut': 'actif', 'code': 'ifu_actif', 'libelle': 'IFU actif', 'declencheur': 'ifu_renseigne', 'ordre': 1},
        ],
      });
      final relais = <String, Map<String, Object?>>{};
      final pub = PublicateurConfiguration(mm, (c, f, champs) async => relais['$c/$f'] = champs, delai: Duration.zero);
      await pub.pousser();
      expect(relais.keys, containsAll(['parametresAib/PAA-BASE-1', 'parametresAib/PAA-BASE-2', 'parametresAib/PAA-IFU-2', 'parametresAib/PAA-BAR-1', 'baremeAib/BAI01']));
      final mf = Magasin({'parametresAib': <M>[], 'baremeAib': <M>[], 'situationsAib': <M>[]});
      final appl = ApplicateurConfiguration(mf, (c) async => [for (final e in relais.entries) if (e.key.startsWith('$c/')) PieceSync(e.key.substring(c.length + 1), e.value)]);
      expect(await appl.tirer(), 7);
      final a = cpaParametresALaDate(mm.collection('parametresAib').actives, DateTime(2026, 10, 30));
      final b = cpaParametresALaDate(mf.collection('parametresAib').actives, DateTime(2026, 10, 30));
      expect([b.base, b.tauxRepli, b.versionBase, b.versionBranchement], [a.base, a.tauxRepli, a.versionBase, a.versionBranchement]);
      expect([b.base, b.tauxRepli], ['facture', 2]);
      expect(cpaParametresALaDate(mf.collection('parametresAib').actives, DateTime(2026, 10, 1)).base, 'ht', reason: 'la version en vigueur à la date, sur le second poste aussi');
      expect(mf.collection('audit').toutes, isEmpty, reason: 'la mère a déjà journalisé');
      // le fileul REFUSE d'écrire un paramètre (réglé sur la mère)
      appl.demarrer(intervalle: const Duration(hours: 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      appl.arreter();
      expect(() => mf.collection('parametresAib').inserer({'id': 'PAA-BASE-9'}), throwsA(isA<EcritureRefusee>()));
    });

    test('une version DÉJÀ DÉCIDÉE ne s\'écrase jamais : une fiche distante qui la contredit est ignorée, seul l\'archivage passe ; une version arrêtée du barème de même', () async {
      final decidee = version('PAA-BASE-2', 'base_retenue', 2, {'base': 'facture'}, effet: '2026-10-20');
      final mf = Magasin({
        'parametresAib': [decidee],
        'baremeAib': [
          {'id': 'BAI01', 'statut': 'actif', 'situation': 'ifu_actif', 'taux': 1, 'dateEffet': '2026-12-01', 'arrete': true, 'statutArret': 'arrete', 'decideurArret': 'Direction'},
          {'id': 'BAI02', 'statut': 'actif', 'situation': 'prestation_service', 'taux': 3, 'arrete': false, 'statutArret': 'non_arrete'},
        ],
      });
      var distant = <String, Map<String, Object?>>{
        'parametresAib': {...decidee, 'base': 'ht'},
      };
      final appl = ApplicateurConfiguration(
          mf,
          (c) async => [
                if (c == 'parametresAib') PieceSync('PAA-BASE-2', distant['parametresAib']!),
                if (c == 'baremeAib') ...[
                  const PieceSync('BAI01', {'id': 'BAI01', 'statut': 'actif', 'situation': 'ifu_actif', 'taux': 9, 'dateEffet': '2026-12-01', 'arrete': true}),
                  const PieceSync('BAI02', {'id': 'BAI02', 'statut': 'actif', 'situation': 'prestation_service', 'taux': 3, 'dateEffet': '2026-12-15', 'arrete': true, 'statutArret': 'arrete', 'decideurArret': 'Direction'}),
                ],
              ]);
      await appl.tirer();
      expect(mf.collection('parametresAib').parId('PAA-BASE-2')!['base'], 'facture', reason: 'la version décidée garde son contenu');
      expect(mf.collection('baremeAib').parId('BAI01')!['taux'], 1, reason: 'une version arrêtée ne se réécrit pas');
      expect(mf.collection('baremeAib').parId('BAI02')!['arrete'], isTrue, reason: 'l\'arrêt d\'une version non arrêtée, décidé sur la mère, est repris');
      distant = {'parametresAib': {...decidee, 'statut': 'archive'}};
      final archive = ApplicateurConfiguration(mf, (c) async => [if (c == 'parametresAib') PieceSync('PAA-BASE-2', distant['parametresAib']!, archive: true)]);
      await archive.tirer();
      expect(mf.collection('parametresAib').parId('PAA-BASE-2')!['statut'], 'archive', reason: 'l\'archivage (RG-14) passe');
      expect(mf.collection('parametresAib').parId('PAA-BASE-2')!['base'], 'facture');
    });

    test('BOUT EN BOUT : mère réelle, moteur fileul réel — la validation faite sur la mère arrive sur le second poste', () async {
      const port = 19470;
      final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-aib'));
      await mere0.demarrer();
      final mm = Magasin({
        'utilisateurs': [
          {'id': 'USR001', 'statut': 'actif', 'identifiant': 'k.agbuzia', 'nomComplet': 'AGBUZIA Kiafour', 'role': 'admin', 'echecs': 0}
        ],
        'parametresAib': [
          ...cpaFichesGraine(),
          version('PAA-BASE-2', 'base_retenue', 2, {'base': 'facture'}, effet: '2026-10-20'),
        ],
      });
      final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero);
      final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
      final moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'Caisse');
      final mf = Magasin({'utilisateurs': <M>[], 'parametresAib': <M>[]});
      final appl = ApplicateurConfiguration(mf, moteur.liste);
      try {
        expect(await pub.pousser(), greaterThanOrEqualTo(3));
        expect(pub.erreur.value, isNull);
        final code = await console.codeAppareil('Caisse').timeout(const Duration(seconds: 20));
        await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
        moteur.demarrer();
        final fin = DateTime.now().add(const Duration(seconds: 25));
        while (mf.collection('parametresAib').toutes.length < 3) {
          await appl.tirer();
          if (DateTime.now().isAfter(fin)) fail('les paramètres de l\'AIB ne sont pas arrivés : ${mf.collection('parametresAib').toutes.length} fiches (${appl.erreur.value})');
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        final b = cpaParametresALaDate(mf.collection('parametresAib').actives, DateTime(2026, 10, 30));
        expect([b.base, b.versionBase], ['facture', 2]);
        // une NOUVELLE validation sur la mère arrive à son tour (une version de plus, jamais un écrasement)
        mm.collection('parametresAib').ajouterSansJournal(version('PAA-BASE-3', 'base_retenue', 3, {'base': 'ht'}, effet: '2027-01-01'));
        await pub.pousser();
        final fin2 = DateTime.now().add(const Duration(seconds: 25));
        while (mf.collection('parametresAib').parId('PAA-BASE-3') == null) {
          await appl.tirer();
          if (DateTime.now().isAfter(fin2)) fail('la seconde validation n\'est pas arrivée');
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(cpaParametresALaDate(mf.collection('parametresAib').actives, DateTime(2027, 1, 1)).base, 'ht');
        expect(cpaParametresALaDate(mf.collection('parametresAib').actives, DateTime(2026, 12, 31)).base, 'facture');
        expect(mf.collection('parametresAib').parId('PAA-BASE-2')!['base'], 'facture', reason: 'la version 2 n\'a pas été écrasée');
      } finally {
        appl.arreter();
        pub.arreter();
        try {
          await mere0.arreter();
        } catch (_) {}
      }
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
