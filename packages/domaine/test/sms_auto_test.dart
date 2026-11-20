// E5200 / E5201 : les envois automatiques de SMS (règles pures) et le consentement du patient. Rien n'est écrit en dur : les réglages se lisent au registre daté, les défauts
// FERMENT les envois ; un envoi par patient et par occasion ; aucune donnée de santé ; sans consentement, rien ne part et le refus est nommé.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> param(String cle, Object? valeur, {String? dateEffet, int version = 1}) =>
    {'cle': cle, 'famille': 'sms', 'type': valeur is bool ? 'booleen' : 'entier', 'valeur': valeur, 'defaut': null, 'dateEffet': dateEffet, 'version': version, 'auteur': 'U-1', 'statut': 'actif'};

const clinique = 'Clinique d’essai';

Map<String, Object?> patient(String id, {Object? consent = true, String tel = '0100000001', String? naissance, String nom = 'ESSAIA'}) =>
    {'id': id, 'nom': nom, 'prenom': 'Koffi', 'telephone': tel, 'dateNaissance': naissance, if (consent != null) 'consentementSms': consent};

Map<String, Object?> rdv(String id, String patientId, String date, {String statut = 'planifiee', bool nonPatient = false}) =>
    {'id': id, 'patientId': patientId, 'date': date, 'statut': statut, if (nonPatient) 'nonPatient': true};

const reglageOuvert = SmsAutoReglage(rappelRdvActif: true, voeuxAnniversaireActif: true, heure: 9, delaiRappelHeures: 24);

List<Map<String, Object?>> modelesNeutres() => [
      for (final m in smsModelesProposes) {'occasion': m.$1, 'libelle': m.$2, 'texte': m.$3, 'actif': true},
    ];

void main() {
  group('consentement : trois états, jamais présumé', () {
    test('un dossier sans champ est « non renseigné » : refus nommé, distinct du refus du patient', () {
      expect(smsConsentementDe({'id': 'P1'}), SmsConsentement.nonRenseigne);
      expect(smsRefusConsentement({'id': 'P1'})?.code, 'SMS_CONSENTEMENT_ABSENT');
      expect(smsRefusConsentement({'consentementSms': false})?.code, 'SMS_CONSENTEMENT_REFUSE');
      expect(smsRefusConsentement({'consentementSms': true}), isNull);
      expect(smsRefusConsentement(null)?.code, 'SMS_PATIENT_INCONNU');
      for (final r in [smsRefusConsentement({}), smsRefusConsentement({'consentementSms': false})]) {
        expect(r!.motif, isNotEmpty);
        expect(r.geste, isNotEmpty);
      }
    });

    test('cocher date et signe le changement ; décocher aussi (refus) ; le champ laissé vide ne retire rien', () {
      final t0 = DateTime.utc(2026, 11, 18, 8);
      final a = smsAppliquerConsentement({'consentementSms': smsChoixAccepte}, null, t0, 'U-ACCUEIL');
      expect(a['consentementSms'], isTrue);
      expect(a['consentementSmsPar'], 'U-ACCUEIL');
      expect(a['consentementSmsLe'], t0.toIso8601String());
      // la même réponse plus tard : date et auteur d'origine gardés
      final b = smsAppliquerConsentement({'consentementSms': smsChoixAccepte}, a, DateTime.utc(2026, 12, 1), 'U-AUTRE');
      expect(b['consentementSmsLe'], t0.toIso8601String());
      expect(b['consentementSmsPar'], 'U-ACCUEIL');
      // décocher = refuser, daté et signé
      final c = smsAppliquerConsentement({'consentementSms': smsChoixRefuse}, a, DateTime.utc(2026, 12, 1), 'U-AUTRE');
      expect(c['consentementSms'], isFalse);
      expect(c['consentementSmsPar'], 'U-AUTRE');
      expect(c['consentementSmsLe'], DateTime.utc(2026, 12, 1).toIso8601String());
      // champ vide : on garde ce qui est consigné ; sans rien consigné, rien n'est écrit
      expect(smsAppliquerConsentement({'consentementSms': ''}, a, DateTime.utc(2026, 12, 1), 'U-X')['consentementSms'], isTrue);
      expect(smsAppliquerConsentement({'consentementSms': ''}, null, DateTime.utc(2026, 12, 1), 'U-X').containsKey('consentementSms'), isFalse);
    });

    test('le transformateur du dossier : sans le champ rien ne change ; avec lui, le changement est daté et signé', () {
      final t = DateTime(2026, 11, 18, 9);
      expect(patTransformerPatient({'nom': 'A', 'naissanceConnue': 'date'}, null, t).containsKey('consentementSms'), isFalse);
      final v = patTransformerPatient({'nom': 'A', 'naissanceConnue': 'date', 'consentementSms': smsChoixAccepte}, null, t, auteur: 'U-ACCUEIL');
      expect(v['consentementSms'], isTrue);
      expect(v['consentementSmsPar'], 'U-ACCUEIL');
      expect(smsChoixDeFiche(v), smsChoixAccepte);
      expect(smsChoixDeFiche({'id': 'P'}), '');
      expect(smsLibelleConsentement({'id': 'P'}), 'Non renseigné');
      expect(smsLibelleConsentement(v), allOf(startsWith('Accepte les SMS'), contains('U-ACCUEIL')));
    });

    test('le consentement est une coordonnée : un profil sans « coordonnées » ne le voit pas', () {
      final c = categoriesSensibles.firstWhere((x) => x.code == 'coordonnees');
      expect(c.champs, containsAll(['consentementSms', 'consentementSmsLe', 'consentementSmsPar']));
    });
  });

  group('réglages : fermés par défaut, lus au registre daté', () {
    test('sans fiche : envois fermés, heure et délai d’attente', () {
      final r = smsAutoReglageA(const [], '2026-11-18');
      expect(r.rappelRdvActif, isFalse);
      expect(r.voeuxAnniversaireActif, isFalse);
      expect(r.unEnvoiActif, isFalse);
      expect(r.heure, definitionDeParametre(cleSmsHeureExecution)!.defaut);
      expect(r.delaiRappelHeures, definitionDeParametre(cleSmsDelaiRappelHeures)!.defaut);
    });

    test('une version datée s’applique à partir de sa date, jamais avant ; hors bornes : la valeur d’attente', () {
      final f = [
        param(cleSmsRappelRdvActif, true, dateEffet: '2026-11-20'),
        param(cleSmsHeureExecution, 17, dateEffet: '2026-11-20'),
        param(cleSmsDelaiRappelHeures, 500, dateEffet: '2026-11-20'),
      ];
      expect(smsAutoReglageA(f, '2026-11-19').rappelRdvActif, isFalse);
      final r = smsAutoReglageA(f, '2026-11-20');
      expect(r.rappelRdvActif, isTrue);
      expect(r.heure, 17);
      expect(r.delaiRappelHeures, definitionDeParametre(cleSmsDelaiRappelHeures)!.defaut, reason: '500 h est hors des bornes déclarées');
    });

    test('les quatre réglages sont des paramètres de la famille « sms », réglés par le geste de la passerelle', () {
      for (final k in [cleSmsRappelRdvActif, cleSmsVoeuxAnniversaireActif, cleSmsHeureExecution, cleSmsDelaiRappelHeures]) {
        final d = definitionDeParametre(k)!;
        expect(d.famille, 'sms', reason: k);
        expect(d.geste, gesteReglageSms, reason: k);
        expect(d.source, isNotNull);
      }
      expect(libellesFamillesParametres['sms'], isNotEmpty);
    });

    test('le tour du jour : une fois, à partir de l’heure, rattrapé si la mère était éteinte, jamais deux fois', () {
      final r = reglageOuvert;
      expect(smsAutoEstDu(DateTime(2026, 11, 18, 8, 59), r, null), isFalse);
      expect(smsAutoEstDu(DateTime(2026, 11, 18, 9), r, null), isTrue);
      expect(smsAutoEstDu(DateTime(2026, 11, 18, 22), r, '2026-11-17'), isTrue, reason: 'rattrapage');
      expect(smsAutoEstDu(DateTime(2026, 11, 18, 22), r, '2026-11-18'), isFalse);
      expect(smsAutoEstDu(DateTime(2026, 11, 18, 12), const SmsAutoReglage(rappelRdvActif: false, voeuxAnniversaireActif: false, heure: 9, delaiRappelHeures: 24), null), isFalse);
    });
  });

  group('candidats', () {
    final maintenant = DateTime(2026, 11, 18, 9);

    test('rappel : les rendez-vous du jour visé, un par patient et par jour ; ni passés, ni honorés, ni non enregistrés', () {
      final c = smsAutoCandidats(
        patients: [patient('P1'), patient('P2'), patient('P3')],
        rendezvous: [
          rdv('R1', 'P1', '2026-11-19T09:00'),
          rdv('R1bis', 'P1', '2026-11-19T15:30'), // même patient, même jour : un seul SMS
          rdv('R2', 'P2', '2026-11-19T10:00', statut: 'terminee'),
          rdv('R3', 'P3', '2026-11-20T10:00'), // après-demain
          rdv('R4', 'P3', '2026-11-18T10:00'), // aujourd'hui
          rdv('R5', 'PX', '2026-11-19T10:00', nonPatient: true),
          rdv('R6', 'PX', '2026-11-19T10:00'), // dossier introuvable
          rdv('R7', 'P2', '2026-11-19T11:00', statut: 'reporte'),
        ],
        maintenant: maintenant,
        reglage: reglageOuvert,
      );
      final rappels = c.where((x) => x.occasion == smsOccasionRappelRdv).toList();
      expect([for (final x in rappels) x.cle], ['rappel_rdv:P1:2026-11-19', 'rappel_rdv:P2:2026-11-19']);
      expect(rappels.first.rdv, '19/11/2026 à 09h00');
    });

    test('le délai se règle : 48 h vise après-demain', () {
      final c = smsAutoCandidats(
        patients: [patient('P3')],
        rendezvous: [rdv('R3', 'P3', '2026-11-20T10:00'), rdv('R8', 'P3', '2026-11-19T10:00')],
        maintenant: maintenant,
        reglage: const SmsAutoReglage(rappelRdvActif: true, voeuxAnniversaireActif: false, heure: 9, delaiRappelHeures: 48),
      );
      expect([for (final x in c) x.jourOccasion], ['2026-11-20']);
    });

    test('un réglage fermé ne produit aucun candidat de son occasion', () {
      final base = {
        'patients': [patient('P1', naissance: '1990-11-18')],
        'rendezvous': [rdv('R1', 'P1', '2026-11-19T09:00')],
      };
      List<SmsAutoCandidat> avec(bool rappel, bool voeux) => smsAutoCandidats(
          patients: base['patients']!,
          rendezvous: base['rendezvous']!,
          maintenant: maintenant,
          reglage: SmsAutoReglage(rappelRdvActif: rappel, voeuxAnniversaireActif: voeux, heure: 9, delaiRappelHeures: 24));
      expect(avec(false, false), isEmpty);
      expect([for (final x in avec(true, false)) x.occasion], [smsOccasionRappelRdv]);
      expect([for (final x in avec(false, true)) x.occasion], [smsOccasionAnniversaire]);
      expect(avec(true, true), hasLength(2));
    });

    test('anniversaire : le jour et le mois de naissance ; clé par année ; le 29 février est fêté le 28 hors année bissextile', () {
      final ps = [patient('P1', naissance: '1990-11-18'), patient('P2', naissance: '1990-11-19'), patient('P3', naissance: '1996-02-29'), patient('P4', naissance: null)];
      final c = smsAutoCandidats(patients: ps, rendezvous: const [], maintenant: maintenant, reglage: reglageOuvert);
      expect([for (final x in c) x.cle], ['anniversaire:P1:2026']);
      final fev = smsAutoCandidats(patients: ps, rendezvous: const [], maintenant: DateTime(2027, 2, 28, 9), reglage: reglageOuvert);
      expect([for (final x in fev) x.cle], ['anniversaire:P3:2027']);
      final bis = smsAutoCandidats(patients: ps, rendezvous: const [], maintenant: DateTime(2028, 2, 29, 9), reglage: reglageOuvert);
      expect([for (final x in bis) x.cle], ['anniversaire:P3:2028']);
    });
  });

  group('préparation : consentement, modèle neutre, aucune donnée de santé', () {
    final maintenant = DateTime(2026, 11, 18, 9);
    SmsAutoCandidat cand(Map<String, Object?> p, {String occasion = smsOccasionRappelRdv}) => SmsAutoCandidat(
        occasion: occasion, cle: '$occasion:${p['id']}', patient: p, jourOccasion: '2026-11-19', rdv: occasion == smsOccasionRappelRdv ? '19/11/2026 à 09h00' : null);
    SmsAutoPrepare prep(SmsAutoCandidat c, [List<Map<String, Object?>>? modeles]) =>
        smsAutoPreparer(c, modeles: modeles ?? modelesNeutres(), clinique: clinique, telephone: '+229 00 00 00 00');

    test('le rappel dit le jour, l’heure et la clinique : pas de nom, pas de mot interdit, numéro international', () {
      final r = prep(cand(patient('P1')));
      expect(r.ok, isTrue, reason: '${r.refus}');
      expect(r.numero, '+2290100000001');
      expect(r.texte, contains('19/11/2026 à 09h00'));
      expect(r.texte, contains(clinique));
      expect(r.texte, isNot(contains('ESSAIA')));
      expect(r.texte, isNot(contains('Koffi')));
      expect(smsMotsInterditsTrouves(r.texte!), isEmpty);
      expect(smsControler(numero: r.numero!, texte: r.texte!), isNull);
    });

    test('les vœux : modèle neutre, la date du jour ; le modèle « santé » de la maquette est sauté', () {
      final maquette = [
        for (final m in cfaModelesProposes) {'occasion': m.$1, 'libelle': m.$2, 'texte': m.$3, 'actif': true}
      ];
      final r = prep(cand(patient('P1'), occasion: smsOccasionAnniversaire), [...maquette, ...modelesNeutres()]);
      expect(r.ok, isTrue, reason: '${r.refus}');
      expect(r.texte, contains('anniversaire'));
      expect(r.texte, isNot(contains('santé')));
      // avec les seuls modèles de la maquette : aucun n'est proposable pour l'anniversaire, refus nommé
      expect(prep(cand(patient('P1'), occasion: smsOccasionAnniversaire), maquette).refus?.code, smsAutoModeleAbsent);
    });

    test('les modèles « Résultat disponible » et « Rappel de règlement » ne servent jamais, même seuls', () {
      final seuls = [
        for (final m in cfaModelesProposes)
          if (m.$1 == 'resultat' || m.$1 == 'echeance') {'occasion': m.$1, 'libelle': m.$2, 'texte': m.$3, 'actif': true}
      ];
      expect(smsAutoModele('rdv', seuls), isNull);
      expect(smsAutoModele('anniversaire', seuls), isNull);
    });

    test('sans consentement, rien ne part : non renseigné, refusé et sans dossier sont trois refus nommés', () {
      expect(prep(cand(patient('P1', consent: null))).refus?.code, 'SMS_CONSENTEMENT_ABSENT');
      expect(prep(cand(patient('P1', consent: false))).refus?.code, 'SMS_CONSENTEMENT_REFUSE');
      expect(prep(cand(patient('P1', tel: ''))).refus?.code, smsAutoSansTelephone);
      expect(prep(cand(patient('P1', tel: 'abc'))).refus?.code, 'SMS_NUMERO_INVALIDE');
      expect(prep(cand(patient('P1')), const []).refus?.code, smsAutoModeleAbsent);
    });

    test('un modèle inactif ou archivé n’est pas utilisé', () {
      final m = modelesNeutres().map((x) => {...x, 'actif': false}).toList();
      expect(smsAutoModele('rdv', m), isNull);
      final a = modelesNeutres().map((x) => {...x, 'statut': 'archive'}).toList();
      expect(smsAutoModele('rdv', a), isNull);
      expect(maintenant.year, 2026);
    });
  });
}
