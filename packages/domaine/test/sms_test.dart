// ADR-0009 : les SMS par le relais. La composition retire le nom, remplace les variables permises, ramène le numéro au format international et refuse en le
// nommant un texte porteur d'un mot interdit (liste proposée, à valider par un médecin), une variable restée, un texte trop long. Le contrôle seul est refait
// par le service de la mère avant l'envoi au relais.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  const clinique = 'Clinique d’essai';

  group('numéro', () {
    test('un numéro local reçoit l’indicatif du Bénin ; « 00 » vaut « + » ; espaces, points et tirets sont ignorés', () {
      expect(smsNormaliserNumero('01 00 00 00 01'), '+2290100000001');
      expect(smsNormaliserNumero('+229 01.00.00.00.01'), '+2290100000001');
      expect(smsNormaliserNumero('00229-0100000001'), '+2290100000001');
      expect(smsNormaliserNumero('+33 6 00 00 00 00'), '+33600000000');
    });
    test('ce qui n’est pas un numéro est refusé', () {
      for (final b in ['', 'abc', '+0123456789', '12', '+229 01 00 00 00 01 99 99 99']) {
        expect(smsNormaliserNumero(b), isNull, reason: b);
      }
    });
    test('le numéro masqué du journal ne garde que l’indicatif et les deux derniers chiffres', () {
      expect(smsMasquerNumero('+2290100000001'), '+229 •••••••• 01');
      expect(smsMasquerNumero('+2290100000001'), isNot(contains('0100000')));
    });
  });

  group('composition', () {
    test('le rappel de rendez-vous : le nom est RETIRÉ, jamais remplacé, et la ponctuation se resserre', () {
      final r = smsComposer(
          modele: 'Bonjour {{nom}}, nous vous rappelons votre rendez-vous à {{clinique}} le {{rdv}}. Pour toute modification, appelez le {{telephone}}.',
          numero: '0100000001',
          clinique: clinique,
          telephone: '+229 00 00 00 00',
          rdv: '18/11/2026 à 09h00');
      expect(r.ok, isTrue, reason: '${r.refus}');
      expect(r.nomRetire, isTrue);
      expect(r.numero, '+2290100000001');
      expect(r.texte, 'Bonjour, nous vous rappelons votre rendez-vous à Clinique d’essai le 18/11/2026 à 09h00. Pour toute modification, appelez le +229 00 00 00 00.');
      expect(r.texte, isNot(contains('{{')));
    });

    test('les six modèles proposés : seul « Résultat disponible » est refusé (il révèle un examen)', () {
      for (final m in cfaModelesProposes) {
        final r = smsComposer(modele: m.$3, numero: '0100000001', clinique: clinique, telephone: '+229 00 00 00 00', rdv: '18/11/2026 à 09h00', date: '18/11/2026');
        if (m.$1 == 'resultat') {
          expect(r.refus?.code, 'SMS_CONTENU_MEDICAL', reason: m.$2);
          expect(r.refus!.motif, contains('resultat'));
        } else {
          expect(r.ok, isTrue, reason: '${m.$2} : ${r.refus}');
          expect(r.texte!.length, lessThanOrEqualTo(smsLongueurMax));
        }
      }
    });

    test('une variable sans valeur ou inconnue est un refus nommé : un patient ne reçoit jamais « {{rdv}} »', () {
      expect(smsComposer(modele: 'Rendez-vous le {{rdv}}.', numero: '0100000001', clinique: clinique).refus?.code, 'SMS_VARIABLE_MANQUANTE');
      expect(smsComposer(modele: 'Bonjour {{prenom}}.', numero: '0100000001', clinique: clinique).refus?.code, 'SMS_VARIABLE_INCONNUE');
    });

    test('un numéro invalide, un texte vide ou trop long sont refusés, chacun avec son geste', () {
      final a = smsComposer(modele: 'Bonjour.', numero: 'abc', clinique: clinique);
      expect(a.refus?.code, 'SMS_NUMERO_INVALIDE');
      expect(a.refus!.geste, isNotEmpty);
      expect(smsComposer(modele: '{{nom}}', numero: '0100000001', clinique: clinique).refus?.code, 'SMS_TEXTE_VIDE');
      expect(smsComposer(modele: 'a' * 321, numero: '0100000001', clinique: clinique).refus?.code, 'SMS_TROP_LONG');
    });

    test('le message d’essai passe les mêmes contrôles et ne dit rien de médical', () {
      final r = smsComposer(modele: smsModeleEssai, numero: '0100000001', clinique: clinique);
      expect(r.ok, isTrue, reason: '${r.refus}');
      expect(r.texte, contains(clinique));
    });
  });

  group('mots interdits (proposition à valider par un médecin)', () {
    test('la liste est marquée à valider par un médecin', () {
      expect(smsStatutMotsInterdits, contains('à valider par un médecin'));
      expect(smsMotsInterdits, containsAll(['diagnostic', 'vih', 'grossesse', 'resultat', 'analyse', 'ordonnance']));
    });

    test('accents, majuscules, pluriels et féminins sont reconnus en début de mot', () {
      expect(smsMotsInterditsTrouves('Vos ANALYSES sont prêtes'), ['analyse']);
      expect(smsMotsInterditsTrouves('Résultat disponible'), ['resultat']);
      expect(smsMotsInterditsTrouves('elle est séropositive'), ['seropositi']);
      expect(smsMotsInterditsTrouves('Suivi de grossesse et échographie'), ['grossesse', 'echographie']);
      expect(smsMotsInterditsTrouves('test VIH'), ['vih']);
    });

    test('un mot interdit À L’INTÉRIEUR d’un autre mot ne déclenche rien (liste, distinct, artiste)', () {
      expect(smsMotsInterditsTrouves('Voici la liste, un geste distinct, un artiste.'), isEmpty);
      expect(smsMotsInterditsTrouves('Bonjour, votre rendez-vous est fixé au 18/11/2026 à 09h00 à la clinique.'), isEmpty);
    });

    test('le contrôle de la mère refuse un texte composé hors du poste qui porte un mot interdit, en le nommant', () {
      final r = smsControler(numero: '+2290100000001', texte: 'Votre test de dépistage est prêt.');
      expect(r?.code, 'SMS_CONTENU_MEDICAL');
      expect(r!.motif, contains('depistage'));
      expect(smsControler(numero: '+2290100000001', texte: 'Rendez-vous le 18/11/2026 à 09h00.'), isNull);
      expect(smsControler(numero: '0100000001', texte: 'Bonjour.')?.code, 'SMS_NUMERO_INVALIDE');
    });
  });

  test('le geste réservé « régler la passerelle SMS » : origine proposée l’administrateur et la DAF, porté par l’écran de la passerelle', () {
    final g = gesteReserve(gesteReglageSms)!;
    expect(g.rolesDefaut, ['admin', 'da']);
    expect(g.ecran, 'mere-sms-passerelle');
    expect(g.aide, contains('à valider'));
    final d = DroitsGestes(fiches: const []);
    expect(d.peut('admin', gesteReglageSms), isTrue);
    expect(d.peut('da', gesteReglageSms), isTrue);
    for (final r in ['direction', 'dm', 'medecin', 'reception', 'caissier', 'comptable']) {
      expect(d.peut(r, gesteReglageSms), isFalse, reason: r);
    }
  });

  test('les fournisseurs du relais : Vonage, Twilio, HTTP générique et journal ; chacun nomme ses variables, aucun identifiant n’est porté', () {
    expect([for (final f in smsFournisseurs) f.cle], ['vonage', 'twilio', 'http', 'journal']);
    expect(smsFournisseurDe('twilio')!.parametres, containsAll(['RELAIS_SMS_TWILIO_SID', 'RELAIS_SMS_TWILIO_TOKEN']));
    expect(smsFournisseurDe('vonage')!.parametres, containsAll(['RELAIS_SMS_VONAGE_CLE', 'RELAIS_SMS_VONAGE_SECRET']));
    expect(smsFournisseurDe('journal')!.envoie, isFalse);
    expect(smsFournisseurDe('journal')!.parametres, isEmpty);
    expect(smsFournisseurDe('inconnu'), isNull);
    expect(smsFournisseurDe(null), isNull);
    for (final f in smsFournisseurs) {
      for (final p in f.parametres) {
        expect(p, startsWith('RELAIS_SMS_'), reason: 'un NOM de variable, jamais une valeur');
      }
    }
  });
}
