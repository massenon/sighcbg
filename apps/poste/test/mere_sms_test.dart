import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/mere/mrb_sms.dart';
import 'package:sigh_poste/modules/mere/mrb_source.dart';
import 'package:sigh_poste/modules/mere/registre_mere.dart';
import 'package:sigh_poste/shell/contexte_ecran.dart';

import 'aide_polices.dart';

/// ADR-0009 (Direction de Baguidi, 16/11/2026) : les deux écrans SMS de la poste mère. La passerelle est FERMÉE par défaut, le plafond est LU au relais,
/// la liste des mots interdits est affichée « à valider par un médecin » ; régler, tester et composer sont le geste réservé `reglage_sms` (absent sans lui, jamais
/// grisé) ; la composition montre le texte EXACT qui partira, sans le nom, et refuse un modèle porteur d'un mot interdit avant tout dépôt.
class Source extends MrbSource {
  Source({this.actif = false, this.journalSms = const []});
  bool actif;
  List<Map<String, Object?>> journalSms;
  final appels = <String>[];
  final deposes = <Map<String, Object?>>[];

  @override
  Future<MrbEtat> etat() async => const MrbEtat(epoch: 1, seqMax: 1, repSeq: 1, reinitOuverte: false, alertes: [], bloques: [], derives: [], appareils: []);
  @override
  Future<MrbSante> supervision() async => const MrbSante(etat: 'ok', depot: 'pg', controles: []);
  @override
  Future<List<MrbLigneJournal>> journal({int limite = 500}) async => const [];
  @override
  Future<int?> patientsActifs() async => 0;
  @override
  Future<String> sauvegarderMaintenant() async => '';
  @override
  Future<void> debloquer(String uuid) async {}
  @override
  Future<void> revoquer(String uuid) async {}
  @override
  Future<void> ouvrirFenetreReinit(bool ouvrir) async {}
  @override
  Future<MrbResultatReinit> reinitialiser({required String confirmation, required String second, String motif = '', bool supprimer = false}) async => throw UnimplementedError();
  @override
  Future<MrbCodeMobile> codeMobile(String etiquette, {required String profil, String? fonction}) async => throw UnimplementedError();

  Map<String, Object?>? automatiques;
  Map<String, Object?> relais = const {'plafond_jour': 100, 'envoyes_aujourdhui': 3, 'en_attente': 1, 'pilote': 'journal'};

  @override
  Future<MrbSms?> sms() async => MrbSms(
      actif: actif,
      relaisConfigure: true,
      relais: relais,
      journal: journalSms,
      statutMotsInterdits: smsStatutMotsInterdits,
      automatiques: automatiques);

  @override
  Future<void> reglerSms({required bool actif}) async {
    appels.add('regler $actif');
    this.actif = actif;
  }

  @override
  Future<String> envoyerSms({required String numero, required String texte, String? modele, String? auteur, bool essai = false, String? patientId}) async {
    deposes.add({'numero': numero, 'texte': texte, 'modele': modele, 'essai': essai, 'patientId': patientId});
    return 'sms-essai';
  }

  @override
  Future<int> suivreSms() async {
    appels.add('suivre');
    return 0;
  }
}

Future<void> pomper(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<Source> monter(WidgetTester t, Source s, Widget ecran, String id,
    {String role = 'admin', Droit droit = const Droit(voir: true, editer: true, annuler: true), Magasin? magasin}) async {
  mrbSourceInjectee = s;
  mrbIntervalle = const Duration(hours: 1);
  addTearDown(() => mrbSourceInjectee = null);
  t.view.physicalSize = const Size(1500, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: ContexteEcran(
                  ecranId: id,
                  role: role,
                  droit: droit,
                  magasin: magasin ?? Magasin(),
                  utilisateur: 'U-ESSAI',
                  aller: (_) {},
                  horloge: () => DateTime(2026, 11, 16, 12),
                  child: ecran)))));
  await pomper(t);
  return s;
}

/// Les six modèles de la maquette, les quatre modèles neutres du canal SMS (E5200) et trois patients : un qui a accepté les SMS, un qui a refusé, un jamais interrogé.
Magasin avecModeles() {
  final m = Magasin();
  for (final x in [...cfaModelesProposes, ...smsModelesProposes]) {
    m.collection('modelesMessage').inserer({'statut': 'actif', 'occasion': x.$1, 'libelle': x.$2, 'texte': x.$3, 'actif': true}, prefixe: 'MSG');
  }
  final p = m.collection('patients');
  p.inserer({'statut': 'actif', 'id': 'P-OUI', 'code': 'CBG/1/26', 'nom': 'ESSAIA', 'prenom': 'Koffi', 'telephone': '0100000001', 'consentementSms': true}, prefixe: 'PAT');
  p.inserer({'statut': 'actif', 'id': 'P-NON', 'code': 'CBG/2/26', 'nom': 'ESSAIB', 'prenom': 'Ama', 'telephone': '0100000002', 'consentementSms': false}, prefixe: 'PAT');
  p.inserer({'statut': 'actif', 'id': 'P-ANC', 'code': 'CBG/3/26', 'nom': 'ESSAIC', 'prenom': 'Eric', 'telephone': '0100000003'}, prefixe: 'PAT');
  return m;
}

void main() {
  setUpAll(chargerPolices);

  test('les deux écrans sont branchés au registre de la mère', () {
    expect(ecransMERE.keys, containsAll(['mere-sms-passerelle', 'mere-sms-journal']));
  });

  testWidgets('passerelle : FERMÉE par défaut, plafond lu au relais, pilote d’essai dit, mots interdits « à valider par un médecin »', (t) async {
    await monter(t, Source(), const EcranSmsPasserelle(), 'mere-sms-passerelle');
    expect(t.widget<Checkbox>(find.byKey(const Key('sms:interrupteur'))).value, isFalse);
    expect(find.textContaining('FERMÉE (aucun SMS ne part)'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('Journal (essai, n’envoie rien)'), findsWidgets);
    expect(find.byKey(const Key('sms:parametres-manquants')), findsNothing);
    expect(find.textContaining('à valider par un médecin'), findsWidgets);
    expect(find.text('diagnostic'), findsOneWidget);
    // fermée : « Tester l'envoi » existe (le droit est là) mais n'envoie rien tant que la passerelle est fermée
    expect(t.widget<BoutonSigh>(find.byKey(const Key('sms:tester'))).onPressed, isNull);
  });

  testWidgets('passerelle : le fournisseur est lu au relais ; ses paramètres manquants sont nommés, et les quatre fournisseurs disent ce qu’ils attendent', (t) async {
    final src = Source()..relais = const {'plafond_jour': 100, 'envoyes_aujourdhui': 0, 'en_attente': 0, 'pilote': 'vonage', 'parametres_manquants': ['RELAIS_SMS_VONAGE_SECRET']};
    await monter(t, src, const EcranSmsPasserelle(), 'mere-sms-passerelle');
    expect(find.text('Vonage'), findsWidgets);
    expect(find.text('En service au relais'), findsOneWidget);
    expect(find.textContaining('Le relais attend encore, dans son fichier de réglages : RELAIS_SMS_VONAGE_SECRET'), findsOneWidget);
    for (final f in smsFournisseurs) {
      expect(find.text('RELAIS_SMS_PILOTE=${f.cle}'), findsOneWidget, reason: f.cle);
    }
    expect(find.textContaining('RELAIS_SMS_TWILIO_SID'), findsOneWidget);
  });

  testWidgets('passerelle : ouvrir appelle le service ; « Tester l’envoi » compose un SMS d’essai contrôlé et le dépose', (t) async {
    final s = await monter(t, Source(), const EcranSmsPasserelle(), 'mere-sms-passerelle');
    await t.tap(find.byKey(const Key('sms:interrupteur')));
    await pomper(t);
    await t.pump(const Duration(seconds: 10));
    expect(s.appels, ['regler true']);
    expect(find.textContaining('OUVERTE'), findsOneWidget);
    await t.tap(find.byKey(const Key('sms:tester')));
    await pomper(t);
    await t.enterText(find.byKey(const Key('sms:numero')), '01 00 00 00 01');
    await pomper(t);
    expect(t.widget<SelectableText>(find.byKey(const Key('sms:apercu'))).data, contains('Message d’essai de la passerelle SMS'));
    await t.tap(find.byKey(const Key('sms:deposer')));
    await pomper(t);
    await t.pump(const Duration(seconds: 10));
    expect(s.deposes, hasLength(1));
    expect(s.deposes.single['numero'], '+2290100000001');
    expect(s.deposes.single['essai'], isTrue);
  });

  testWidgets('sans le geste réservé (fiche qui le retire à la DAF) : interrupteur inactif, « Tester l’envoi » ABSENT, lecture seule dite', (t) async {
    final m = Magasin();
    m.collection('rbac').inserer({'role': 'da', 'statut': 'actif', 'droitsGestes': {gesteReglageSms: false}}, prefixe: 'RBAC');
    await monter(t, Source(), const EcranSmsPasserelle(), 'mere-sms-passerelle', role: 'da', magasin: m);
    expect(t.widget<Checkbox>(find.byKey(const Key('sms:interrupteur'))).onChanged, isNull);
    expect(find.byKey(const Key('sms:tester')), findsNothing);
    expect(find.byKey(const Key('sms:lecture-seule')), findsOneWidget);
  });

  testWidgets('sans le droit d’écrire sur l’écran : aucune commande, même avec le geste', (t) async {
    await monter(t, Source(actif: true), const EcranSmsPasserelle(), 'mere-sms-passerelle', droit: const Droit(voir: true, editer: false, annuler: false));
    expect(find.byKey(const Key('sms:tester')), findsNothing);
    expect(t.widget<Checkbox>(find.byKey(const Key('sms:interrupteur'))).onChanged, isNull);
  });

  testWidgets('journal : numéro MASQUÉ, statuts lisibles (dont « expiré »), compteurs d’échecs qui comptent les expirés', (t) async {
    await monter(
        t,
        Source(actif: true, journalSms: const [
          {'id': 'sms-1', 'numero_masque': '+229 •••••••• 01', 'longueur': 88, 'modele': 'Rappel de rendez-vous', 'statut': 'envoye', 'tentatives': 1, 'depose_le': 1794822000000},
          {'id': 'sms-2', 'numero_masque': '+229 •••••••• 02', 'longueur': 60, 'modele': 'Vœux de fête', 'statut': 'non_depose', 'erreur': 'plafond_atteint', 'tentatives': 0, 'depose_le': 1794822000000},
          {'id': 'sms-3', 'numero_masque': '+229 •••••••• 03', 'longueur': 60, 'modele': 'Vœux de fête', 'statut': 'expire', 'tentatives': 0, 'depose_le': 1794822000000},
        ]),
        const EcranSmsJournal(),
        'mere-sms-journal',
        magasin: avecModeles());
    expect(find.text('+229 •••••••• 01'), findsOneWidget);
    expect(find.textContaining('Envoyé (numéro et texte effacés au relais)'), findsOneWidget);
    expect(find.textContaining('Expiré avant l’envoi'), findsOneWidget);
    expect(find.text('plafond_atteint'), findsOneWidget);
    expect(find.text('Échecs, refus ou expirés'), findsOneWidget);
  });

  testWidgets('composer un SMS : depuis un PATIENT ; pas de consentement = refus nommé ; « Résultat disponible » et « Rappel de règlement » ne sont pas proposés', (t) async {
    final s = await monter(t, Source(actif: true), const EcranSmsJournal(), 'mere-sms-journal', magasin: avecModeles());
    await t.tap(find.byKey(const Key('sms:composer')));
    await pomper(t);
    // les modèles proposés : ceux du SMS (neutres, fête, rendez-vous) — jamais ceux qui révèlent un examen, une dette ou la santé
    final libelles = [for (final o in t.widget<SelecteurSigh>(find.byKey(const Key('sms:modele'))).options) o.libelle];
    expect(libelles, isNot(contains('Résultat disponible')));
    expect(libelles, isNot(contains('Rappel de règlement')));
    expect(libelles, isNot(contains('Anniversaire')), reason: 'le modèle de la maquette dit « santé »');
    expect(libelles, containsAll(['Rappel de rendez-vous (SMS)', 'Anniversaire (SMS)', 'Vœux de fête']));
    String option(String libelle) => t.widget<SelecteurSigh>(find.byKey(const Key('sms:modele'))).options.firstWhere((o) => o.libelle == libelle).valeur;
    void patient(String id) => t.widget<SelecteurSigh>(find.byKey(const Key('sms:patient'))).surChange(id);
    // aucun champ de numéro libre : le numéro vient du dossier
    expect(find.byKey(const Key('sms:numero')), findsNothing);
    // jamais interrogé : refus nommé, rien à déposer
    patient('P-ANC');
    await pomper(t);
    expect(find.byKey(const Key('sms:refus-consentement')), findsOneWidget);
    expect(find.textContaining('n’est pas renseigné'), findsWidgets);
    expect(t.widget<BoutonSigh>(find.byKey(const Key('sms:deposer'))).onPressed, isNull);
    // refusé : autre refus nommé
    patient('P-NON');
    await pomper(t);
    expect(find.textContaining('a refusé de recevoir des SMS'), findsWidgets);
    expect(t.widget<BoutonSigh>(find.byKey(const Key('sms:deposer'))).onPressed, isNull);
    // accepté : le rappel de rendez-vous, nom retiré, date du rendez-vous demandée, texte exact montré
    patient('P-OUI');
    await pomper(t);
    expect(find.byKey(const Key('sms:refus-consentement')), findsNothing);
    t.widget<SelecteurSigh>(find.byKey(const Key('sms:modele'))).surChange(option('Rappel de rendez-vous (SMS)'));
    await pomper(t);
    expect(t.widget<BoutonSigh>(find.byKey(const Key('sms:deposer'))).onPressed, isNull, reason: 'la date du rendez-vous manque');
    await t.enterText(find.byKey(const Key('sms:rdv')), '18/11/2026 à 09h00');
    await pomper(t);
    final apercu = t.widget<SelectableText>(find.byKey(const Key('sms:apercu'))).data!;
    expect(apercu, startsWith('Bonjour, nous vous rappelons votre rendez-vous'));
    expect(apercu, contains('18/11/2026 à 09h00'));
    expect(apercu, isNot(contains('{{')));
    expect(apercu, isNot(contains('ESSAIA')));
    expect(find.textContaining('Le nom du patient n’est jamais envoyé'), findsOneWidget);
    await t.tap(find.byKey(const Key('sms:deposer')));
    await pomper(t);
    await t.pump(const Duration(seconds: 10));
    expect(s.deposes.single['texte'], apercu);
    expect(s.deposes.single['modele'], 'Rappel de rendez-vous (SMS)');
    expect(s.deposes.single['numero'], '+2290100000001');
    expect(s.deposes.single['patientId'], 'P-OUI');
    expect(s.deposes.single['essai'], isFalse);
  });

  testWidgets('passerelle : les envois automatiques sont montrés (réglages en vigueur, dernier tour en compteurs, jamais un nom ni un numéro)', (t) async {
    final src = Source()
      ..automatiques = {
        'reglages': {'rappel_rdv_actif': true, 'voeux_anniversaire_actif': false, 'heure': 9, 'delai_rappel_heures': 24},
        'dernier_jour': '2026-11-16',
        'dernier_bilan': {
          'jour': '2026-11-16',
          'candidats': 5,
          'deposes': {'rappel_rdv': 2, 'anniversaire': 1},
          'refus': {'SMS_CONSENTEMENT_ABSENT': 2},
          'plafondAtteint': false
        },
      };
    await monter(t, src, const EcranSmsPasserelle(), 'mere-sms-passerelle');
    expect(find.byKey(const Key('sms:automatiques')), findsOneWidget);
    expect(find.text('Rappel de rendez-vous : OUVERT'), findsOneWidget);
    expect(find.text('Vœux d’anniversaire : FERMÉ'), findsOneWidget);
    expect(find.text('Heure : 9 h'), findsOneWidget);
    expect(find.text('Délai de rappel : 24 h'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('sms:dernier-tour'))).data, allOf(contains('3 SMS déposé(s) sur 5'), contains('2 consentement non renseigné')));
  });

  testWidgets('journal sans le geste : « Composer un SMS » ABSENT, « Relever les statuts » reste au droit d’écrire', (t) async {
    final m = avecModeles();
    m.collection('rbac').inserer({'role': 'admin', 'statut': 'actif', 'droitsGestes': {gesteReglageSms: false}}, prefixe: 'RBAC');
    final s = await monter(t, Source(actif: true), const EcranSmsJournal(), 'mere-sms-journal', magasin: m);
    expect(find.byKey(const Key('sms:composer')), findsNothing);
    await t.tap(find.byKey(const Key('sms:suivre')));
    await pomper(t);
    await t.pump(const Duration(seconds: 10));
    expect(s.appels, contains('suivre'));
  });
}
