import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show adaptateurPourMode, mecefCleMode, parametreDateIso;
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/mecef_poste.dart';
import 'package:sigh_poste/donnees/normalisation_mecef.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/m8/acheteur_normalise.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// La fenêtre « Facture normalisée » à l'émission et la NORMALISATION de la vente soldée (E2299) : toute vente est normalisée, le numéro ne naît
/// jamais à l'émission, un refus nomme son défaut et n'écrit rien. Aucun boîtier n'est branché : le numéro est celui de l'appareil de démonstration.
final donnees = DonneesNavigation.depuisDossier();
final aujourdhui = DateTime(2026, 10, 30);

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Future<void> ouvrir(WidgetTester t, Magasin m, {String role = 'admin'}) async {
  t.view.physicalSize = const Size(1600, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(SighPoste(
      key: UniqueKey(),
      donnees: donnees,
      config: ConfigPoste(mode: ModePoste.fileul, role: role),
      ecranInitial: 'm8-facturation',
      magasin: m,
      horloge: () => aujourdhui));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> toucher(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> choisir(WidgetTester t, String courant, String cible) async {
  await toucher(t, find.text(courant).first);
  await toucher(t, find.text(cible).last);
}

Future<void> saisir(WidgetTester t, String champ, String valeur) async {
  final f = find.descendant(
      of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(TextField));
  await t.ensureVisible(f);
  await t.enterText(f, valeur);
  await t.pump();
}

Future<void> ajouterLibre(WidgetTester t, String libelle, String prix) async {
  await choisir(t, 'Acte / consultation', 'Ligne libre');
  await saisir(t, 'designation', libelle);
  await saisir(t, 'prix', prix);
  await saisir(t, 'quantite', '1');
  await toucher(t, find.widgetWithText(BoutonSigh, 'Ajouter'));
}

void cas(String nom, Future<void> Function(WidgetTester) corps) =>
    testWidgets(nom, (t) async {
      await corps(t);
      // 15 s : le refus nommé de la normalisation (MECEF_NON_CONFIGURE) vit 12 s, plus que les autres messages (lot L3).
      await t.pump(const Duration(seconds: 15));
    });

void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  cas('la fenêtre « Facture normalisée » est à l\'émission : trois champs, la phrase qui dit que ce sont les seuls', (t) async {
    await ouvrir(t, magasin());
    expect(find.text('FACTURE NORMALISÉE'), findsOneWidget);
    expect(find.text('IFU de l’acheteur'), findsWidgets);
    expect(find.text('Nom de l’acheteur'), findsWidgets);
    expect(find.text('Situation de l’acheteur (AIB)'), findsWidgets);
    expect(find.textContaining('Toute vente est normalisée'), findsOneWidget);
    // Le taux affiché vient du BARÈME à la date de la facture (30/10/2026) : sans IFU, 5 % arrêté depuis le 07/09/2026, calculé sur le hors taxes.
    expect(find.textContaining('AIB au 30/10/2026 : 5 %'), findsOneWidget);
    expect(find.textContaining('arrêté, en vigueur depuis le 07/09/2026'), findsOneWidget);
    expect(find.textContaining('hors taxes'), findsWidgets);
  });

  cas('les choix de situation viennent du barème : plus de liste 0 / 1 / 5 % codée, les taux non arrêtés sont dits « à valider »', (t) async {
    await ouvrir(t, magasin());
    await toucher(t, find.text('Automatique — d’après l’IFU saisi').first);
    expect(find.textContaining('Acheteur avec IFU actif — 1 % non arrêté, à valider'), findsWidgets);
    expect(find.textContaining('Acheteur sans IFU actif — 5 % arrêté'), findsWidgets);
    expect(find.textContaining('Prestation de service retenue par le payeur — 3 % non arrêté, à valider'), findsWidgets);
    expect(find.text('1 % (taux de la facture de référence, à confirmer)'), findsNothing);
  });

  cas('IFU actif : le 1 % n\'est pas arrêté, la vente est refusée en nommant AIB_SANS_BAREME, rien n\'est écrit', (t) async {
    final m = magasin();
    final avant = m.collection('factures').actives.length;
    final ecrAvant = m.collection('ecritures').actives.length;
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await saisir(t, 'acheteurIfu', '3201642748214');
    await saisir(t, 'acheteurNom', 'Clinique X');
    expect(find.textContaining('aucun taux applicable'), findsOneWidget);
    expect(find.textContaining('1 % — non arrêté, à valider'), findsWidgets);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    expect(find.textContaining('AIB_SANS_BAREME'), findsWidgets);
    expect(m.collection('factures').actives.length, avant);
    expect(m.collection('ecritures').actives.length, ecrAvant);
  });

  cas('à une date AVANT le 07/09/2026 aucun taux n\'est arrêté : refus nommé, jamais un taux commode', (t) async {
    final m = magasin();
    final avant = m.collection('factures').actives.length;
    t.view.physicalSize = const Size(1600, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(SighPoste(
        key: UniqueKey(),
        donnees: donnees,
        config: const ConfigPoste(mode: ModePoste.fileul, role: 'admin'),
        ecranInitial: 'm8-facturation',
        magasin: m,
        horloge: () => DateTime(2026, 9, 6)));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await ajouterLibre(t, 'Carnet de santé', '500');
    expect(find.textContaining('aucun taux applicable'), findsOneWidget);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    expect(find.textContaining('AIB_SANS_BAREME'), findsWidgets);
    expect(find.textContaining('07/09/2026'), findsWidgets);
    expect(m.collection('factures').actives.length, avant);
  });

  cas('l\'agent change la situation : « sans IFU actif » (5 % arrêté) sur un acheteur qui présente un IFU ; une situation non arrêtée reste refusée', (t) async {
    final m = magasin();
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await saisir(t, 'acheteurIfu', '3201642748214');
    await saisir(t, 'acheteurNom', 'Clinique X');
    await choisir(t, 'Automatique — d’après l’IFU saisi', 'Prestation de service retenue par le payeur — 3 % non arrêté, à valider');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    expect(find.textContaining('AIB_SANS_BAREME'), findsWidgets);
    expect(m.collection('factures').actives.where((f) => f['ifuClient'] == '3201642748214'), isEmpty);
  });

  cas('MECeF fermé (bascule mecefActif) : la fenêtre est absente, la pièce ne porte aucun champ fiscal ni acheteur, le barème n\'est pas lu', (t) async {
    final m = magasin();
    m.collection('modulesActifs').inserer({'module': 'MECEF', 'actif': false, 'statut': 'actif'});
    await ouvrir(t, m);
    expect(find.text('FACTURE NORMALISÉE'), findsNothing);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final f = m.collection('factures').actives.first;
    expect(f['statutPaiement'], 'soldee');
    for (final k in ['ifuClient', 'acheteurNom', 'aibTaux', 'aibSituation', 'aibMontant', 'numeroMecef']) {
      expect(f[k], isNull, reason: k);
    }
  });

  cas('un IFU invalide est refusé en le nommant, AVANT toute écriture', (t) async {
    final m = magasin();
    final avant = m.collection('factures').actives.length;
    final ecrAvant = m.collection('ecritures').actives.length;
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await saisir(t, 'acheteurIfu', '123');
    await saisir(t, 'acheteurNom', 'Clinique X');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    expect(find.textContaining('IFU_INVALIDE'), findsWidgets);
    expect(find.textContaining('13 chiffres'), findsWidgets);
    expect(m.collection('factures').actives.length, avant);
    expect(m.collection('ecritures').actives.length, ecrAvant);
  });

  cas('un IFU sans nom est refusé en le nommant', (t) async {
    final m = magasin();
    final avant = m.collection('factures').actives.length;
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await saisir(t, 'acheteurIfu', '3201642748214');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    expect(find.textContaining('NOM_ACHETEUR_ABSENT'), findsWidgets);
    expect(m.collection('factures').actives.length, avant);
  });

  cas('vente soldée : l\'acheteur est rangé dans la pièce, la vente reste EN ATTENTE de certification et ne reçoit AUCUN numéro (lot L3)', (t) async {
    final m = magasin();
    final numeros0 = numerosPris(m).length;
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await saisir(t, 'acheteurIfu', '3201 6427 48214');
    await saisir(t, 'acheteurNom', 'Clinique X');
    await choisir(t, 'Automatique — d’après l’IFU saisi', 'Acheteur sans IFU actif — 5 % arrêté');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final f = m.collection('factures').actives.first;
    expect(f['statutPaiement'], 'soldee');
    expect(f['aibSituation'], 'ifu_inactif_ou_absent');
    expect(f['ifuClient'], '3201642748214');
    expect(f['acheteurNom'], 'Clinique X');
    expect(f['aibTaux'], 5);
    expect(f['statutMecef'], 'en_attente');
    expect(f['numeroMecef'], isNull, reason: 'aucun numéro fabriqué');
    expect(f['codeRetour'], 'MECEF_NON_CONFIGURE');
    expect(f['modeMecef'], 'boitier', reason: 'le défaut du registre');
    expect(f['mecefSimule'], isNull);
    expect(numerosPris(m).length, numeros0);
    expect(find.textContaining('MECEF_NON_CONFIGURE'), findsWidgets);
  });

  cas('règlement partiel : aucune normalisation, aucun numéro, la pièce attend le solde', (t) async {
    final m = magasin();
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '1000');
    await saisir(t, 'regle', '400');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final f = m.collection('factures').actives.first;
    expect(f['statutPaiement'], 'partielle');
    expect(f['statutMecef'], 'en_attente');
    expect(f['numeroMecef'], isNull);
  });

  group('normaliserVente', () {
    Fiche vente(Magasin m, [Map<String, Object?> sup = const {}]) =>
        m.collection('factures').inserer({
          'numero': 'FN-TEST-1',
          'montantTTC': 10000,
          'montantPaye': 10000,
          'statutPaiement': 'soldee',
          'statutMecef': 'en_attente',
          'statut': 'actif',
          'lignes': [
            {'id': 'L1', 'designation': 'Consultation', 'quantite': 1, 'prixUnitaire': 10000, 'partAssureur': 0, 'partPatient': 10000, 'statutPaiement': 'paye'}
          ],
          ...sup,
        }, prefixe: 'FAC').fiche;

    test('une vente normalisée ne se renormalise jamais, et son numéro ne change pas', () {
      final m = magasin();
      final f = vente(m, {'statutMecef': 'valide', 'numeroMecef': 'MECEF2000001'});
      final b = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(b.code, 'DEJA_NORMALISEE');
      expect(m.collection('factures').parId(f['id'])!['numeroMecef'], 'MECEF2000001');
    });

    test('sans adaptateur configuré (boîtier, mode par défaut) : refus nommé, pièce en attente, AUCUN numéro', () {
      final m = magasin();
      final f = vente(m);
      final a = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(a.ok, isFalse);
      expect(a.code, 'MECEF_NON_CONFIGURE');
      expect(a.motif, contains('Boîtier non configuré'));
      expect(a.geste, isNotEmpty);
      final apres = m.collection('factures').parId(f['id'])!;
      expect(apres['statutMecef'], 'en_attente');
      expect(apres['numeroMecef'], isNull);
      expect(apres['codeRetour'], 'MECEF_NON_CONFIGURE');
      expect(apres['modeMecef'], 'boitier');
    });

    test('en mode e-MECeF : « non configuré, dossier d\'interface DGI requis », toujours aucun numéro', () {
      final m = magasin();
      final f = vente(m);
      final a = normaliserVente(m, '${f['id']}', maintenant: aujourdhui, adaptateur: adaptateurPourMode('emecef'));
      expect(a.code, 'MECEF_NON_CONFIGURE');
      expect(a.motif, 'e-MECeF non configuré : dossier d’interface DGI requis.');
      final apres = m.collection('factures').parId(f['id'])!;
      expect(apres['statutMecef'], 'en_attente');
      expect(apres['numeroMecef'], isNull);
      expect(apres['modeMecef'], 'emecef');
    });

    test('le mode se lit au registre des paramètres : réglé sur e-MECeF, la normalisation suit', () {
      final m = magasin();
      final service = serviceParametres(m, auteur: () => 'Test', horloge: () => aujourdhui);
      expect(modeMecefDuPoste(m, aujourdhui), 'boitier');
      expect(service.regler(mecefCleMode, 'emecef', parametreDateIso(aujourdhui)).ok, isTrue);
      expect(modeMecefDuPoste(m, aujourdhui), 'emecef');
      final f = vente(m);
      normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(m.collection('factures').parId(f['id'])!['modeMecef'], 'emecef');
    });

    test('un numéro déjà porté par une pièce non normalisée est repris, jamais réécrit ni fabriqué', () {
      final m = magasin();
      final f = vente(m, {'numeroMecef': 'MECEF2000007'});
      final a = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(a.ok, isTrue);
      expect(a.numero, 'MECEF2000007');
    });

    test('annuler restitue la pièce en attente, sans numéro', () {
      final m = magasin();
      final f = vente(m);
      final a = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      a.annuler();
      final apres = m.collection('factures').parId(f['id'])!;
      expect(apres['statutMecef'], 'en_attente');
      expect(apres['numeroMecef'], isNull);
    });

    test('un total incohérent écrit la pièce « refusée » en nommant le code, sans numéro', () {
      final m = magasin();
      final f = vente(m, {'montantTTC': 10001});
      final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(r.code, 'TOTAL_INCOHERENT');
      expect(r.geste, isNotEmpty);
      final apres = m.collection('factures').parId(f['id'])!;
      expect(apres['statutMecef'], 'rejete');
      expect(apres['codeRetour'], 'TOTAL_INCOHERENT');
      expect(apres['motifRefusMecef'], contains('diffère'));
      expect(apres['numeroMecef'], isNull);
    });

    test('un refus d\'acheteur n\'écrit rien', () {
      final m = magasin();
      final f = vente(m);
      final r = normaliserVente(m, '${f['id']}',
          acheteur: {'ifu': '12', 'nom': 'X'}, maintenant: aujourdhui);
      expect(r.code, 'IFU_INVALIDE');
      final apres = m.collection('factures').parId(f['id'])!;
      expect(apres['statutMecef'], 'en_attente');
      expect(apres['ifuClient'], isNull);
    });

    test('une pro-forma ne se normalise pas', () {
      final m = magasin();
      final f = vente(m, {'proforma': true});
      expect(normaliserVente(m, '${f['id']}', maintenant: aujourdhui).code, 'PROFORMA');
    });

    // D1 (Direction, 09/11/2026) : vente sans acheteur et retransmission lisent le taux au barème daté ; sans taux arrêté en vigueur, le repli des Paramètres (0 %).
    test('D1 vente sans acheteur au 30/10/2026 : le taux ARRÊTÉ du barème (5 %), pas un 1 % écrit en dur ; la pièce porte son motif', () {
      final m = magasin();
      final f = vente(m, {'date': '2026-10-30'});
      final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(r.ok, isTrue);
      final p = m.collection('factures').parId(f['id'])!;
      expect([p['aibTaux'], p['aibSituation'], p['aibMontant'], p['aibRepli']], [5, 'ifu_inactif_ou_absent', 500, null]);
      expect(p['aibMotif'], 'Taux de 5 % arrêté, en vigueur depuis le 07/09/2026.');
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Normalisation' && '${(a['apres'] as Map)['aib']}'.contains('5 % — Taux de 5 % arrêté')), isTrue,
          reason: 'le motif du moteur est journalisé');
    });

    test('D1 vente sans acheteur AVANT l\'arrêt du 5 % : aucun taux arrêté → 0 %, repli annoncé avec le motif du moteur, journalisé', () {
      final m = magasin();
      final f = vente(m, {'date': '2026-08-01'});
      final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(r.ok, isTrue);
      final p = m.collection('factures').parId(f['id'])!;
      expect([p['aibTaux'], p['aibMontant'], p['aibRepli']], [0, 0, true]);
      expect(p['aibSituation'], isNull);
      expect(p['aibMotif'], contains('Aucun taux arrêté en vigueur au 01/08/2026 : AIB à 0 %'));
      expect(p['aibMotif'], contains('Aucun taux arrêté avant le 07/09/2026'));
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Normalisation' && '${(a['apres'] as Map)['aib']}'.contains('0 % — Aucun taux arrêté en vigueur')), isTrue);
    });

    test('D1 retransmission d\'une pièce refusée puis corrigée : le taux se lit à la date de la facture, le refus n\'écrit pas un taux périmé', () {
      final m = magasin();
      final f = vente(m, {'montantTTC': 10001, 'date': '2026-10-30'});
      expect(normaliserVente(m, '${f['id']}', maintenant: aujourdhui).code, 'TOTAL_INCOHERENT');
      final refusee = m.collection('factures').parId(f['id'])!;
      expect(refusee['statutMecef'], 'rejete');
      expect(refusee.containsKey('aibTaux'), isFalse, reason: 'un taux lu par défaut ne se porte pas sur une pièce refusée');
      // la correction, puis la retransmission : le taux arrêté est lu à la date de la facture
      m.collection('factures').mettreAJour(f['id'], {'montantTTC': 10000});
      final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(r.ok, isTrue);
      expect(m.collection('factures').parId(f['id'])!['aibTaux'], 5);
    });

    test('D1 acheteur avec IFU actif, 1 % non arrêté : la retransmission applique 0 % (jamais le 1 %), D8 : la fenêtre, elle, refuse ce même acheteur', () {
      final m = magasin();
      final f = vente(m, {'date': '2026-10-30', 'ifuClient': '3201642748214', 'acheteurNom': 'Clinique X'});
      final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(r.ok, isTrue);
      final p = m.collection('factures').parId(f['id'])!;
      expect([p['aibTaux'], p['aibRepli']], [0, true]);
      expect(p['aibMotif'], contains('0 %'));
      // D8 : la fenêtre « Facture normalisée » GARDE son refus nommé pour le même acheteur tant que le 1 % n'est pas arrêté.
      final ctl = ControleurFormulaire(champsAcheteurNormalise(m, aujourdhui), {...valeursAcheteur(null), 'acheteurIfu': '3201642748214', 'acheteurNom': 'Clinique X'});
      final refus = controlerAcheteur(ctl, m, aujourdhui);
      expect(refus!.code, 'AIB_SANS_BAREME');
    });

    test('D1 le taux de repli est celui des Paramètres : validé à 3 % pour l\'IFU actif, la retransmission applique 3 %', () {
      final m = magasin();
      m.collection('parametresAib').ajouterSansJournal({
        'id': 'PAA-IFU-2', 'statut': 'actif', 'rubrique': 'branchement_ifu', 'version': 2, 'longueurIfu': 13, 'situationIfuRenseigne': 'ifu_actif',
        'situationIfuAbsent': 'ifu_inactif_ou_absent', 'tauxRepli': 3, 'dateEffet': '2026-10-01', 'decideur': 'Direction', 'dateDecision': '2026-09-30', 'motif': 'x',
      });
      final f = vente(m, {'date': '2026-10-30', 'ifuClient': '3201642748214', 'acheteurNom': 'Clinique X'});
      expect(normaliserVente(m, '${f['id']}', maintenant: aujourdhui).ok, isTrue);
      final p = m.collection('factures').parId(f['id'])!;
      expect([p['aibTaux'], p['aibMontant']], [3, 300]);
    });

    test('une pièce qui porte déjà son taux le GARDE : la fenêtre a décidé, le défaut ne la réécrit pas', () {
      final m = magasin();
      final f = vente(m, {'date': '2026-10-30', 'aibTaux': 5, 'aibSituation': 'ifu_inactif_ou_absent'});
      expect(normaliserVente(m, '${f['id']}', maintenant: aujourdhui).ok, isTrue);
      final p = m.collection('factures').parId(f['id'])!;
      expect(p['aibTaux'], 5);
      expect(p.containsKey('aibMotif'), isFalse);
    });

    test('la longueur de l\'IFU vient des Paramètres : validée à 10 chiffres, un IFU de 13 est refusé en le disant', () {
      final m = magasin();
      m.collection('parametresAib').ajouterSansJournal({
        'id': 'PAA-IFU-2', 'statut': 'actif', 'rubrique': 'branchement_ifu', 'version': 2, 'longueurIfu': 10, 'situationIfuRenseigne': 'ifu_actif',
        'situationIfuAbsent': 'ifu_inactif_ou_absent', 'tauxRepli': 0, 'dateEffet': '2026-10-01', 'decideur': 'Direction', 'dateDecision': '2026-09-30', 'motif': 'x',
      });
      final f = vente(m, {'date': '2026-10-30'});
      final r = normaliserVente(m, '${f['id']}', acheteur: {'ifu': '3201642748214', 'nom': 'X'}, maintenant: aujourdhui);
      expect(r.code, 'IFU_INVALIDE');
      expect(r.motif, contains('10 chiffres'));
    });
  });
}
