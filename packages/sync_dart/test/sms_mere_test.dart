// ADR-0009 : la passerelle SMS de la mère. Fermée par défaut (rien ne part, pas même un essai) ; ouverte, la mère RECONTRÔLE le texte composé par le poste
// (mot interdit, numéro, variable restée : refus nommé, rien n'est déposé), dépose un SMS SIGNÉ au relais, garde au journal le numéro MASQUÉ sans le texte,
// nomme le refus du relais (plafond) et suit le statut jusqu'à « envoyé ».
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/src/commun.dart';
import 'package:sigh_sync/src/sms_mere.dart';
import 'package:sigh_sync/src/indicateurs_clinique.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:test/test.dart';

class Recu {
  Recu(this.chemin, this.entetes, this.corps);
  final String chemin;
  final Map<String, String> entetes;
  final List<int> corps;
}

void main() {
  late HttpServer relais;
  late List<Recu> recus;
  late int statutDepot;
  late String statutSuivi;
  late Mere m;
  const secret = 's3cr3t-de-la-mere';
  const texte = 'Bonjour, nous vous rappelons votre rendez-vous a la clinique le 18/11/2026 a 09h00.';

  setUp(() async {
    recus = [];
    statutDepot = 200;
    statutSuivi = 'en_attente';
    relais = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(relais.forEach((req) async {
      final corps = await req.fold<List<int>>([], (a, b) => [...a, ...b]);
      final h = <String, String>{};
      req.headers.forEach((k, v) => h[k] = v.join(','));
      recus.add(Recu(req.uri.path, h, corps));
      req.response.headers.contentType = ContentType.json;
      switch (req.uri.path) {
        case '/mere/sms':
          req.response.statusCode = statutDepot;
          final id = statutDepot == 200 ? ((jsonDecode(utf8.decode(corps)) as Map)['sms'] as Map)['id'] : null;
          req.response.write(statutDepot == 200
              ? jsonEncode({'ok': true, 'rejeu': false, 'sms': {'id': id, 'statut': 'en_attente', 'tentatives': 0}})
              : '{"code":"plafond_atteint","motif":"Le plafond quotidien de SMS (100) est atteint."}');
        case '/mere/sms/statuts':
          final ids = (jsonDecode(utf8.decode(corps)) as Map)['ids'] as List;
          req.response.write(jsonEncode({'statuts': [for (final i in ids) {'id': i, 'statut': statutSuivi, 'tentatives': 1, 'envoye_le': statutSuivi == 'envoye' ? 1 : null}]}));
        case '/mere/sms/etat':
          req.response.write('{"plafond_jour":100,"envoyes_aujourdhui":3,"en_attente":0,"tentatives_max":5,"longueur_max":320,"pilote":"journal"}');
        default:
          req.response.write('{"ok":true}');
      }
      await req.response.close();
    }));
    m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:', relais: 'http://127.0.0.1:${relais.port}', secretRelais: secret, versionApplication: '2.0.1'));
  });
  tearDown(() async => relais.close(force: true));

  Future<void> fiche(String col, String id, Map<String, Object?> data) =>
      m.base.exec('INSERT INTO fiches(collection,id,data,fieldseq,archive) VALUES(?,?,?,?,0) ON CONFLICT(collection,id) DO UPDATE SET data=excluded.data', [col, id, jsonEncode(data), '{}']);

  /// Un patient qui a accepté les SMS, un qui a refusé, un jamais interrogé.
  Future<void> patients() async {
    await fiche('patients', 'P-OUI', {'id': 'P-OUI', 'nom': 'ESSAIA', 'prenom': 'Koffi', 'telephone': '0100000001', 'consentementSms': true});
    await fiche('patients', 'P-NON', {'id': 'P-NON', 'nom': 'ESSAIB', 'prenom': 'Ama', 'telephone': '0100000002', 'consentementSms': false});
    await fiche('patients', 'P-ANC', {'id': 'P-ANC', 'nom': 'ESSAIC', 'prenom': 'Eric', 'telephone': '0100000003'});
  }

  List<Recu> depots() => recus.where((r) => r.chemin == '/mere/sms').toList();

  test('par défaut la passerelle est FERMÉE : rien ne part, pas même un essai, et le refus est nommé', () async {
    final e = await m.pont.sms.etat();
    expect((e['reglages'] as Map)['actif'], isFalse);
    expect(e['mots_interdits_statut'], contains('à valider par un médecin'));
    await expectLater(m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte, 'essai': true}), throwsA(isA<Err>().having((x) => x.code, 'code', 'SMS_PASSERELLE_FERMEE')));
    expect(depots(), isEmpty);
  });

  test('l’état affiche le plafond lu au relais (il ne se règle pas depuis le poste)', () async {
    final e = await m.pont.sms.etat();
    expect((e['relais'] as Map)['plafond_jour'], 100);
    expect((e['relais'] as Map)['envoyes_aujourdhui'], 3);
    expect(e['relais_configure'], isTrue);
  });

  test('ouverte : la mère RECONTRÔLE ; un mot interdit, un numéro local ou une variable restée sont refusés et rien n’est déposé', () async {
    await m.pont.sms.regler({'actif': true});
    for (final (corps, code) in [
      ({'numero': '+2290100000001', 'texte': 'Votre résultat d’analyse est prêt.', 'essai': true}, 'SMS_CONTENU_MEDICAL'),
      ({'numero': '0100000001', 'texte': texte, 'essai': true}, 'SMS_NUMERO_INVALIDE'),
      ({'numero': '+2290100000001', 'texte': 'Bonjour {{nom}}.', 'essai': true}, 'SMS_VARIABLE_INCONNUE'),
    ]) {
      await expectLater(m.pont.sms.envoyer(corps), throwsA(isA<Err>().having((x) => x.code, 'code', code)));
    }
    expect(depots(), isEmpty);
    expect(await m.pont.sms.journal(), isEmpty);
  });

  test('un SMS conforme part SIGNÉ, schéma fermé ; le journal de la mère garde le numéro MASQUÉ, jamais le texte ni le numéro', () async {
    await m.pont.sms.regler({'actif': true});
    await patients();
    final r = await m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte, 'modele': 'Rappel de rendez-vous', 'auteur': 'U-1', 'patient_id': 'P-OUI'});
    expect(r['depose'], isTrue);
    final d = depots().single;
    expect(d.entetes['x-mere'], secret);
    expect(d.entetes['x-signature'], 'sha256=${PublicationIndicateurs.signer(secret, d.corps)}');
    final corps = jsonDecode(utf8.decode(d.corps)) as Map;
    expect(corps.keys, ['sms']);
    expect((corps['sms'] as Map).keys.toSet(), {'id', 'numero', 'texte'});
    final j = await m.pont.sms.journal();
    expect(j, hasLength(1));
    expect(j.single['statut'], 'en_attente');
    expect(j.single['numero_masque'], '+229 •••••••• 01');
    final brut = jsonEncode(j);
    expect(brut, isNot(contains('0100000001')));
    expect(brut, isNot(contains('rendez-vous a la clinique')));
  });

  test('un refus du relais (plafond) est NOMMÉ et inscrit au journal ; rien n’est réessayé en silence', () async {
    await m.pont.sms.regler({'actif': true});
    statutDepot = 429;
    await expectLater(m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte, 'essai': true}), throwsA(isA<Err>().having((x) => x.code, 'code', 'plafond_atteint').having((x) => x.statut, 'statut', 429)));
    final j = await m.pont.sms.journal();
    expect(j.single['statut'], 'non_depose');
    expect(j.single['erreur'], 'plafond_atteint');
    expect(depots(), hasLength(1));
  });

  test('le suivi relève le statut au relais jusqu’à « envoyé »', () async {
    await m.pont.sms.regler({'actif': true});
    await m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte, 'essai': true});
    expect(await m.pont.sms.suivre(), 0);
    statutSuivi = 'envoye';
    expect(await m.pont.sms.suivre(), 1);
    final e = (await m.pont.sms.journal()).single;
    expect(e['statut'], 'envoye');
    expect(e['envoye_le'], 1);
    final suivi = recus.where((r) => r.chemin == '/mere/sms/statuts').last;
    expect(suivi.entetes['x-signature'], 'sha256=${PublicationIndicateurs.signer(secret, suivi.corps)}');
    expect(await m.pont.sms.suivre(), 0, reason: 'plus rien en attente : aucune requête');
  });

  test('un SMS que le relais a abandonné (périmé) est suivi jusqu’à « expire », sans plus rien en attente (E5204)', () async {
    await m.pont.sms.regler({'actif': true});
    await m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte, 'essai': true});
    statutSuivi = 'expire';
    expect(await m.pont.sms.suivre(), 1);
    final e = (await m.pont.sms.journal()).single;
    expect(e['statut'], 'expire');
    expect(await m.pont.sms.suivre(), 0, reason: 'un SMS expiré n’est plus suivi');
  });

  test('refermer la passerelle arrête tout dépôt', () async {
    await m.pont.sms.regler({'actif': true});
    await m.pont.sms.regler({'actif': false});
    await expectLater(m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte, 'essai': true}), throwsA(isA<Err>()));
    await expectLater(m.pont.sms.regler({'actif': 'oui'}), throwsA(isA<Err>().having((x) => x.code, 'code', 'interrupteur_invalide')));
    expect(depots(), isEmpty);
  });

  group('consentement du patient (E5201) : la mère relit le dossier', () {
    test('un patient qui n’a pas été interrogé, qui a refusé ou qui n’existe pas : refus nommé, rien n’est déposé', () async {
      await m.pont.sms.regler({'actif': true});
      await patients();
      for (final (id, code) in [('P-ANC', 'SMS_CONSENTEMENT_ABSENT'), ('P-NON', 'SMS_CONSENTEMENT_REFUSE'), ('P-FANTOME', 'SMS_PATIENT_INCONNU')]) {
        await expectLater(m.pont.sms.envoyer({'numero': '+2290100000003', 'texte': texte, 'patient_id': id}),
            throwsA(isA<Err>().having((x) => x.code, 'code', code).having((x) => x.corps['geste'], 'geste', isNotEmpty)));
      }
      expect(depots(), isEmpty);
      expect(await m.pont.sms.journal(), isEmpty);
    });

    test('sans patient, un SMS n’est possible que pour l’essai de la passerelle', () async {
      await m.pont.sms.regler({'actif': true});
      await expectLater(m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte}), throwsA(isA<Err>().having((x) => x.code, 'code', 'SMS_PATIENT_REQUIS')));
      expect(depots(), isEmpty);
      await m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte, 'essai': true});
      expect(depots(), hasLength(1));
    });

    test('le consentement vaut pour le numéro du dossier : un autre numéro est refusé', () async {
      await m.pont.sms.regler({'actif': true});
      await patients();
      await expectLater(m.pont.sms.envoyer({'numero': '+2290199999999', 'texte': texte, 'patient_id': 'P-OUI'}), throwsA(isA<Err>().having((x) => x.code, 'code', 'SMS_NUMERO_DIFFERENT')));
      expect(depots(), isEmpty);
    });

    test('le consentement est relu À CHAQUE envoi : retiré, le SMS suivant est refusé', () async {
      await m.pont.sms.regler({'actif': true});
      await patients();
      await m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte, 'patient_id': 'P-OUI'});
      await fiche('patients', 'P-OUI', {'id': 'P-OUI', 'telephone': '0100000001', 'consentementSms': false});
      await expectLater(m.pont.sms.envoyer({'numero': '+2290100000001', 'texte': texte, 'patient_id': 'P-OUI'}), throwsA(isA<Err>().having((x) => x.code, 'code', 'SMS_CONSENTEMENT_REFUSE')));
      expect(depots(), hasLength(1));
    });
  });

  group('envois automatiques (E5200)', () {
    // Le 18/11/2026 à 10 h, heure locale de la mère.
    final jour = DateTime(2026, 11, 18, 10);
    late PasserelleSms auto;
    late DateTime horloge;

    Future<void> reglage(String cle, Object? valeur, {String famille = 'sms'}) => fiche('parametres', 'v-$cle', {
          'cle': cle, 'famille': famille, 'type': valeur is bool ? 'booleen' : 'entier', 'valeur': valeur, 'defaut': null, 'dateEffet': null, 'version': 1, 'auteur': 'U-1', 'statut': 'actif',
        });

    Future<void> modeles() async {
      for (final x in smsModelesProposes) {
        await fiche('modelesMessage', 'M-${x.$1}', {'id': 'M-${x.$1}', 'occasion': x.$1, 'libelle': x.$2, 'texte': x.$3, 'actif': true});
      }
    }

    setUp(() {
      horloge = jour;
      auto = PasserelleSms(m, horloge: () => horloge);
    });

    List<Map<String, Object?>> corpsDeposes() => [for (final d in depots()) ((jsonDecode(utf8.decode(d.corps)) as Map)['sms'] as Map).cast<String, Object?>()];

    test('par défaut RIEN n’est dû : les envois sont fermés, aucun dépôt', () async {
      await patients();
      await fiche('rendezvous', 'R1', {'id': 'R1', 'patientId': 'P-OUI', 'date': '2026-11-19T09:00', 'statut': 'planifiee'});
      await m.pont.sms.regler({'actif': true});
      expect(await auto.executerAutomatiques(), {'du': false});
      expect(depots(), isEmpty);
      final e = (await auto.etatAutomatiques())['reglages'] as Map;
      expect(e['rappel_rdv_actif'], isFalse);
      expect(e['voeux_anniversaire_actif'], isFalse);
    });

    test('le rappel de la veille : un SMS neutre, sans nom, au patient consentant ; le bilan nomme les refus et ne porte que des compteurs', () async {
      await reglage(cleSmsRappelRdvActif, true);
      await patients();
      await modeles();
      await m.pont.sms.regler({'actif': true});
      await fiche('rendezvous', 'R1', {'id': 'R1', 'patientId': 'P-OUI', 'date': '2026-11-19T09:00', 'statut': 'planifiee'});
      await fiche('rendezvous', 'R2', {'id': 'R2', 'patientId': 'P-NON', 'date': '2026-11-19T10:00', 'statut': 'planifiee'});
      await fiche('rendezvous', 'R3', {'id': 'R3', 'patientId': 'P-ANC', 'date': '2026-11-19T11:00', 'statut': 'planifiee'});
      await fiche('rendezvous', 'R4', {'id': 'R4', 'patientId': 'P-OUI', 'date': '2026-11-21T11:00', 'statut': 'planifiee'});
      final b = await auto.executerAutomatiques();
      expect((b['deposes'] as Map)[smsOccasionRappelRdv], 1);
      expect(b['candidats'], 3);
      expect(b['refus'], {'SMS_CONSENTEMENT_REFUSE': 1, 'SMS_CONSENTEMENT_ABSENT': 1});
      final sms = corpsDeposes().single;
      expect(sms['numero'], '+2290100000001');
      expect(sms['texte'], allOf(contains('19/11/2026 à 09h00'), isNot(contains('ESSAIA')), isNot(contains('Koffi'))));
      expect(smsMotsInterditsTrouves('${sms['texte']}'), isEmpty);
      final brut = jsonEncode(b) + jsonEncode(await m.pont.sms.journal()) + jsonEncode(await auto.etatAutomatiques());
      expect(brut, isNot(contains('0100000001')));
      expect(brut, isNot(contains('ESSAIA')));
      expect(brut, isNot(contains('19/11/2026 à 09h00')));
      final j = (await m.pont.sms.journal()).single;
      expect(j['occasion'], smsOccasionRappelRdv);
      expect(j['patient_id'], 'P-OUI');
    });

    test('UN envoi par patient et par occasion : le tour rejoué, ou repris après une panne, ne redépose rien', () async {
      await reglage(cleSmsRappelRdvActif, true);
      await patients();
      await modeles();
      await m.pont.sms.regler({'actif': true});
      await fiche('rendezvous', 'R1', {'id': 'R1', 'patientId': 'P-OUI', 'date': '2026-11-19T09:00', 'statut': 'planifiee'});
      await fiche('rendezvous', 'R1b', {'id': 'R1b', 'patientId': 'P-OUI', 'date': '2026-11-19T14:00', 'statut': 'planifiee'});
      await auto.executerAutomatiques();
      expect(depots(), hasLength(1), reason: 'deux rendez-vous le même jour : un seul SMS');
      // même jour : le tour n'est plus dû
      expect(await auto.executerAutomatiques(), {'du': false});
      // le « dernier jour » est effacé (panne, restauration) : la trace retient l'envoi
      await m.base.poserMeta(PasserelleSms.cleAutoJour, '');
      final b = await auto.executerAutomatiques();
      expect(depots(), hasLength(1));
      expect(b['dejaFaits'], 1);
      // la trace manque mais le tour est rejoué : l'identifiant, tiré de la clé, est le même — le relais rend la même ligne
      await m.base.poserMeta(PasserelleSms.cleAutoJour, '');
      await m.base.poserMeta(PasserelleSms.cleAutoTraces, '{}');
      await auto.executerAutomatiques();
      final ids = {for (final s in corpsDeposes()) s['id']};
      expect(ids, hasLength(1));
    });

    test('l’heure d’exécution se règle : avant l’heure rien ne part, passé l’heure oui', () async {
      await reglage(cleSmsRappelRdvActif, true);
      await reglage(cleSmsHeureExecution, 17);
      await patients();
      await modeles();
      await m.pont.sms.regler({'actif': true});
      await fiche('rendezvous', 'R1', {'id': 'R1', 'patientId': 'P-OUI', 'date': '2026-11-19T09:00', 'statut': 'planifiee'});
      expect(await auto.executerAutomatiques(), {'du': false});
      horloge = DateTime(2026, 11, 18, 17, 1);
      await auto.executerAutomatiques();
      expect(depots(), hasLength(1));
    });

    test('le délai de rappel se règle : 48 h vise les rendez-vous d’après-demain', () async {
      await reglage(cleSmsRappelRdvActif, true);
      await reglage(cleSmsDelaiRappelHeures, 48);
      await patients();
      await modeles();
      await m.pont.sms.regler({'actif': true});
      await fiche('rendezvous', 'R1', {'id': 'R1', 'patientId': 'P-OUI', 'date': '2026-11-19T09:00', 'statut': 'planifiee'});
      await fiche('rendezvous', 'R2', {'id': 'R2', 'patientId': 'P-ANC', 'date': '2026-11-20T09:00', 'statut': 'planifiee'});
      final b = await auto.executerAutomatiques();
      expect(b['candidats'], 1);
      expect(b['refus'], {'SMS_CONSENTEMENT_ABSENT': 1});
    });

    test('les vœux d’anniversaire : modèle neutre, patient consentant seulement', () async {
      await reglage(cleSmsVoeuxAnniversaireActif, true);
      await modeles();
      await m.pont.sms.regler({'actif': true});
      await fiche('patients', 'P-OUI', {'id': 'P-OUI', 'nom': 'ESSAIA', 'prenom': 'Koffi', 'telephone': '0100000001', 'consentementSms': true, 'dateNaissance': '1985-11-18'});
      await fiche('patients', 'P-NON', {'id': 'P-NON', 'nom': 'ESSAIB', 'telephone': '0100000002', 'consentementSms': false, 'dateNaissance': '1990-11-18'});
      await fiche('patients', 'P-ANC', {'id': 'P-ANC', 'nom': 'ESSAIC', 'telephone': '0100000003', 'dateNaissance': '1970-11-18'});
      final b = await auto.executerAutomatiques();
      expect((b['deposes'] as Map)[smsOccasionAnniversaire], 1);
      expect(b['refus'], {'SMS_CONSENTEMENT_REFUSE': 1, 'SMS_CONSENTEMENT_ABSENT': 1});
      expect(corpsDeposes().single['texte'], allOf(contains('anniversaire'), isNot(contains('santé'))));
    });

    test('sans modèle neutre, le refus est nommé (jamais le texte de la maquette qui dit « santé »)', () async {
      await reglage(cleSmsVoeuxAnniversaireActif, true);
      await m.pont.sms.regler({'actif': true});
      await fiche('patients', 'P-OUI', {'id': 'P-OUI', 'telephone': '0100000001', 'consentementSms': true, 'dateNaissance': '1985-11-18'});
      for (final x in cfaModelesProposes) {
        await fiche('modelesMessage', 'M-${x.$1}', {'id': 'M-${x.$1}', 'occasion': x.$1, 'texte': x.$3, 'actif': true});
      }
      final b = await auto.executerAutomatiques();
      expect(b['refus'], {smsAutoModeleAbsent: 1});
      expect(depots(), isEmpty);
    });

    test('passerelle fermée : rien ne part et le tour RESTE DÛ, repris dès l’ouverture', () async {
      await reglage(cleSmsRappelRdvActif, true);
      await patients();
      await modeles();
      await fiche('rendezvous', 'R1', {'id': 'R1', 'patientId': 'P-OUI', 'date': '2026-11-19T09:00', 'statut': 'planifiee'});
      expect((await auto.executerAutomatiques())['attente'], 'SMS_PASSERELLE_FERMEE');
      expect(depots(), isEmpty);
      await m.pont.sms.regler({'actif': true});
      await auto.executerAutomatiques();
      expect(depots(), hasLength(1));
    });

    test('plafond du relais atteint : on s’arrête, le reste est nommé « plafond atteint », rien n’est tracé comme envoyé', () async {
      await reglage(cleSmsRappelRdvActif, true);
      await patients();
      await fiche('patients', 'P-DEUX', {'id': 'P-DEUX', 'telephone': '0100000004', 'consentementSms': true});
      await modeles();
      await m.pont.sms.regler({'actif': true});
      await fiche('rendezvous', 'R1', {'id': 'R1', 'patientId': 'P-OUI', 'date': '2026-11-19T09:00', 'statut': 'planifiee'});
      await fiche('rendezvous', 'R2', {'id': 'R2', 'patientId': 'P-DEUX', 'date': '2026-11-19T10:00', 'statut': 'planifiee'});
      statutDepot = 429;
      final b = await auto.executerAutomatiques();
      expect(b['plafondAtteint'], isTrue);
      expect((b['refus'] as Map)['SMS_AUTO_PLAFOND_ATTEINT'], greaterThanOrEqualTo(1));
      expect((b['deposes'] as Map)[smsOccasionRappelRdv], 0);
      expect(await auto.etatAutomatiques().then((e) => e['traces']), 0);
    });

    test('relais injoignable : rien n’est marqué fait, le tour reprendra', () async {
      await reglage(cleSmsRappelRdvActif, true);
      await patients();
      await modeles();
      await m.pont.sms.regler({'actif': true});
      await fiche('rendezvous', 'R1', {'id': 'R1', 'patientId': 'P-OUI', 'date': '2026-11-19T09:00', 'statut': 'planifiee'});
      await relais.close(force: true);
      final b = await auto.executerAutomatiques();
      expect(b['attente'], 'relais_injoignable');
      expect(await m.base.meta(PasserelleSms.cleAutoJour), isNull);
    });

    test('les traces des occasions passées sont purgées', () async {
      await reglage(cleSmsRappelRdvActif, true);
      await patients();
      await modeles();
      await m.pont.sms.regler({'actif': true});
      await m.base.poserMeta(PasserelleSms.cleAutoTraces, jsonEncode({'rappel_rdv:P-OUI:2026-11-01': '2026-11-01'}));
      await auto.executerAutomatiques();
      expect(await auto.etatAutomatiques().then((e) => e['traces']), 0);
    });
  });
}
