import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_domaine/sigh_domaine.dart'
    show acheteurNormaliseAuBareme, adaptateurPourMode, aibPourAcheteur, mecefCleMode, mecefMentionFacturePatient, parametreDateIso, validerAcheteurMecef;
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/mecef_poste.dart';
import 'package:sigh_poste/donnees/normalisation_mecef.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/donnees/parametres_aib.dart';
import 'package:sigh_poste/main.dart';

import 'aide_polices.dart';

/// La NORMALISATION de la vente soldée (E2299) : toute vente est normalisée, le numéro ne naît jamais à l'émission, un refus nomme son défaut et n'écrit
/// rien. Aucun boîtier n'est branché : aucun numéro n'est fabriqué.
///
/// PORTÉ PUIS CORRIGÉ PAR DÉCISION (Direction de Baguidi, 16/11/2026, E3770 à E3779) : ce fichier éprouvait la fenêtre « Facture normalisée » de l'émission
/// (IFU de l'acheteur, Nom de l'acheteur, Situation de l'acheteur pour l'AIB) et le taux d'AIB par défaut lu au barème (D1). La facture d'un PATIENT ne porte
/// plus ni acheteur ni AIB : chaque test est GARDÉ et dit désormais la règle nouvelle (bloc absent, aucun AIB, aucun refus d'acheteur au guichet) ; ce que
/// l'ancien test prouvait du contrôle de l'acheteur est éprouvé au MOTEUR du domaine, gardé pour une vente à un tiers payeur.
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

  Future<void> blocAbsent(WidgetTester t) async {
    expect(find.text('FACTURE NORMALISÉE'), findsNothing);
    expect(find.text('IFU de l’acheteur'), findsNothing);
    expect(find.text('Nom de l’acheteur'), findsNothing);
    expect(find.text('Situation de l’acheteur (AIB)'), findsNothing);
    for (final k in ['acheteurIfu', 'acheteurNom', 'acheteurAib']) {
      expect(find.byKey(Key('kit:champ:$k')), findsNothing, reason: k);
    }
    expect(find.byKey(const Key('mecef:acheteur')), findsNothing);
    expect(find.byKey(const Key('mecef:aib-taux')), findsNothing);
  }

  cas('E3771 (porté puis corrigé) : la fenêtre « Facture normalisée » a DISPARU de l\'émission — ni IFU, ni nom de l\'acheteur, ni taux d\'AIB, ni leurs phrases', (t) async {
    await ouvrir(t, magasin());
    await blocAbsent(t);
    expect(find.textContaining('Toute vente est normalisée : l’IFU'), findsNothing);
    expect(find.textContaining('AIB au '), findsNothing);
    expect(find.textContaining('Le taux d’AIB vient du barème'), findsNothing);
    // À la place : la mention de la facture patient, normalisée sans acheteur ni AIB.
    expect(find.byKey(const Key('mecef:facture-patient')), findsOneWidget);
    expect(find.text(mecefMentionFacturePatient), findsOneWidget);
  });

  cas('E3771 : plus aucun choix de situation d\'AIB à l\'émission ; le domaine garde les situations du barème pour une vente à un tiers payeur', (t) async {
    final m = magasin();
    await ouvrir(t, m);
    expect(find.text('Automatique — d’après l’IFU saisi'), findsNothing);
    expect(find.textContaining('5 % arrêté'), findsNothing);
    // Ce que l'ancien test prouvait (les taux viennent du barème, un taux non arrêté est « à valider ») reste vrai au moteur de l'acheteur.
    final r = aibPourAcheteur(
        ifu: '3201001996110', date: aujourdhui, situations: m.collection('situationsAib').actives, versions: m.collection('baremeAib').actives);
    expect(r.refus!.code, 'AIB_SANS_BAREME');
    expect(r.nonArretes, contains('1 % — non arrêté, à valider'));
    final sans = aibPourAcheteur(date: aujourdhui, situations: m.collection('situationsAib').actives, versions: m.collection('baremeAib').actives);
    expect(sans.taux, 5);
  });

  cas('E3770 : la vente au patient (30/10/2026) est encaissée et normalisée SANS AIB : aucun refus AIB_SANS_BAREME au guichet (la règle reste au moteur de l\'acheteur tiers)', (t) async {
    final m = magasin();
    final avant = m.collection('factures').actives.length;
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    expect(find.textContaining('AIB_SANS_BAREME'), findsNothing);
    expect(m.collection('factures').actives.length, avant + 1);
    final f = m.collection('factures').actives.first;
    expect([f['ifuClient'], f['acheteurNom'], f['aibSituation'], f['aibTaux'], f['aibMontant']], [null, null, null, 0, 0]);
    // D8 tient toujours au moteur : un acheteur tiers avec IFU actif (1 % non arrêté) est refusé en le nommant.
    final tiers = acheteurNormaliseAuBareme(
        ifu: '3201001996110', nom: 'Entreprise X', date: aujourdhui, situations: m.collection('situationsAib').actives, versions: m.collection('baremeAib').actives);
    expect(tiers.refus!.code, 'AIB_SANS_BAREME');
  });

  cas('E3770 : avant le 07/09/2026 non plus, aucun taux n\'est cherché : la vente au patient passe, sans AIB ni taux de repli', (t) async {
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
    expect(find.textContaining('aucun taux applicable'), findsNothing);
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    expect(find.textContaining('AIB_SANS_BAREME'), findsNothing);
    expect(m.collection('factures').actives.length, avant + 1);
    final f = m.collection('factures').actives.first;
    expect([f['aibTaux'], f['aibRepli'], f['aibMotif']], [0, null, null]);
  });

  cas('E3771 : l\'agent n\'a plus de situation à choisir à l\'émission ; au moteur, « sans IFU actif » rend 5 % arrêté et une situation non arrêtée reste refusée', (t) async {
    final m = magasin();
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    expect(find.byKey(const Key('kit:champ:acheteurAib')), findsNothing);
    Iterable<Map<String, Object?>> s() => m.collection('situationsAib').actives;
    Iterable<Map<String, Object?>> v() => m.collection('baremeAib').actives;
    final cinq = acheteurNormaliseAuBareme(
        ifu: '3201001996110', nom: 'Entreprise X', situationChoisie: 'ifu_inactif_ou_absent', date: aujourdhui, situations: s(), versions: v());
    expect([cinq.acheteur!.aibTaux, cinq.acheteur!.aibSituation], [5, 'ifu_inactif_ou_absent']);
    final trois = acheteurNormaliseAuBareme(
        ifu: '3201001996110', nom: 'Entreprise X', situationChoisie: 'prestation_service', date: aujourdhui, situations: s(), versions: v());
    expect(trois.refus!.code, 'AIB_SANS_BAREME');
  });

  cas('MECeF fermé (bascule mecefActif) : ni bloc ni mention, la pièce ne porte aucun champ fiscal ni acheteur, le barème n\'est pas lu', (t) async {
    final m = magasin();
    m.collection('modulesActifs').inserer({'module': 'MECEF', 'actif': false, 'statut': 'actif'});
    await ouvrir(t, m);
    expect(find.text('FACTURE NORMALISÉE'), findsNothing);
    expect(find.byKey(const Key('mecef:facture-patient')), findsNothing);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final f = m.collection('factures').actives.first;
    expect(f['statutPaiement'], 'soldee');
    for (final k in ['ifuClient', 'acheteurNom', 'aibTaux', 'aibSituation', 'aibMontant', 'numeroMecef']) {
      expect(f[k], isNull, reason: k);
    }
  });

  cas('E3771 : plus de saisie d\'IFU à l\'émission, donc plus de refus IFU_INVALIDE au guichet ; le contrôle reste au moteur (vente à un tiers)', (t) async {
    final m = magasin();
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await blocAbsent(t);
    final r = validerAcheteurMecef(ifu: '123', nom: 'Entreprise X', aibTaux: 0);
    expect(r.refus!.code, 'IFU_INVALIDE');
    expect(r.refus!.motif, contains('13 chiffres'));
  });

  cas('E3771 : un IFU sans nom ne se saisit plus au guichet ; au moteur il reste refusé en le nommant', (t) async {
    final m = magasin();
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await blocAbsent(t);
    expect(validerAcheteurMecef(ifu: '3201001996110', aibTaux: 0).refus!.code, 'NOM_ACHETEUR_ABSENT');
  });

  cas('vente soldée : AUCUN acheteur dans la pièce ni AIB (E3770), la vente reste EN ATTENTE de certification et ne reçoit AUCUN numéro (lot L3)', (t) async {
    final m = magasin();
    final numeros0 = numerosPris(m).length;
    await ouvrir(t, m);
    await ajouterLibre(t, 'Carnet de santé', '500');
    await toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final f = m.collection('factures').actives.first;
    expect(f['statutPaiement'], 'soldee');
    expect(f['aibSituation'], isNull);
    expect(f['ifuClient'], isNull);
    expect(f['acheteurNom'], isNull);
    expect(f['aibTaux'], 0);
    expect(f['aibMontant'], 0);
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

    test('E3770 (porté puis corrigé) : une pièce qui porte encore un IFU invalide n\'est plus refusée — facture patient, normalisée sans acheteur, le journal dit ce qui est retiré', () {
      final m = magasin();
      final f = vente(m, {'ifuClient': '12', 'acheteurNom': 'X'});
      final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(r.code, 'MECEF_NON_CONFIGURE', reason: 'aucun refus d\'acheteur : il n\'y a pas d\'acheteur');
      final apres = m.collection('factures').parId(f['id'])!;
      expect(apres['statutMecef'], 'en_attente');
      expect(apres['ifuClient'], isNull);
      expect(apres['acheteurNom'], isNull);
      final j = m.collection('audit').toutes.lastWhere((a) => '${a['action']}'.startsWith('Normalisation'));
      expect((j['avant'] as Map)['ifuClient'], '12');
      expect('${(j['apres'] as Map)['aib']}', contains('retiré : ifuClient 12'));
    });

    test('une pro-forma ne se normalise pas', () {
      final m = magasin();
      final f = vente(m, {'proforma': true});
      expect(normaliserVente(m, '${f['id']}', maintenant: aujourdhui).code, 'PROFORMA');
    });

    // D1 (Direction, 09/11/2026) : vente sans acheteur et retransmission lisaient le taux au barème daté ; PORTÉ PUIS CORRIGÉ par la décision du 16/11/2026
    // (E3770) : la facture d'un patient ne porte aucun AIB, aucun taux n'est lu au barème ni au repli. Les tests sont gardés et disent la règle nouvelle.
    test('D1 corrigé : vente sans acheteur au 30/10/2026 — plus aucun taux lu au barème (le 5 % arrêté ne s\'applique pas), AIB 0, aucun motif ; le journal dit « facture patient »', () {
      final m = magasin();
      final f = vente(m, {'date': '2026-10-30'});
      final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(r.code, 'MECEF_NON_CONFIGURE', reason: 'lot L3 : le numéro attend l\'adaptateur');
      final p = m.collection('factures').parId(f['id'])!;
      expect([p['aibTaux'], p['aibSituation'], p['aibMontant'], p['aibRepli'], p['aibMotif']], [0, null, 0, null, null]);
      expect(m.collection('audit').toutes.any((a) => '${a['action']}'.startsWith('Normalisation') && '${(a['apres'] as Map)['aib']}'.contains('facture patient')), isTrue,
          reason: 'le journal dit pourquoi aucun AIB n\'est porté');
    });

    test('D1 corrigé : vente sans acheteur AVANT l\'arrêt du 5 % — aucun AIB, et pas davantage de « repli » annoncé', () {
      final m = magasin();
      final f = vente(m, {'date': '2026-08-01'});
      final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(r.code, 'MECEF_NON_CONFIGURE', reason: 'lot L3 : le numéro attend l\'adaptateur');
      final p = m.collection('factures').parId(f['id'])!;
      expect([p['aibTaux'], p['aibMontant'], p['aibRepli']], [0, 0, null]);
      expect(p['aibSituation'], isNull);
      expect(p['aibMotif'], isNull);
      expect(m.collection('audit').toutes.any((a) => '${(a['apres'] as Map?)?['aib'] ?? ''}'.contains('Aucun taux arrêté')), isFalse);
    });

    test('D1 corrigé : retransmission d\'une pièce refusée puis corrigée — le refus n\'écrit aucun taux, la retransmission normalise sans AIB', () {
      final m = magasin();
      final f = vente(m, {'montantTTC': 10001, 'date': '2026-10-30'});
      expect(normaliserVente(m, '${f['id']}', maintenant: aujourdhui).code, 'TOTAL_INCOHERENT');
      final refusee = m.collection('factures').parId(f['id'])!;
      expect(refusee['statutMecef'], 'rejete');
      expect(refusee.containsKey('aibTaux'), isFalse, reason: 'un refus ne porte aucun taux');
      m.collection('factures').mettreAJour(f['id'], {'montantTTC': 10000});
      final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(r.code, 'MECEF_NON_CONFIGURE', reason: 'lot L3 : le numéro attend l\'adaptateur');
      expect(m.collection('factures').parId(f['id'])!['aibTaux'], 0);
    });

    test('D1 corrigé : une pièce qui porte encore un acheteur avec IFU actif est normalisée sans acheteur ni AIB ; D8 : le moteur de l\'acheteur tiers refuse toujours ce même acheteur', () {
      final m = magasin();
      final f = vente(m, {'date': '2026-10-30', 'ifuClient': '3201001996110', 'acheteurNom': 'Clinique X'});
      final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
      expect(r.code, 'MECEF_NON_CONFIGURE', reason: 'lot L3 : le numéro attend l\'adaptateur');
      final p = m.collection('factures').parId(f['id'])!;
      expect([p['aibTaux'], p['aibRepli'], p['ifuClient'], p['acheteurNom']], [0, null, null, null]);
      // D8 : la fenêtre a disparu ; son refus nommé reste celui du moteur pour une vente à un tiers, tant que le 1 % n'est pas arrêté.
      final tiers = acheteurNormaliseAuBareme(
          ifu: '3201001996110', nom: 'Clinique X', date: aujourdhui, situations: m.collection('situationsAib').actives, versions: m.collection('baremeAib').actives);
      expect(tiers.refus!.code, 'AIB_SANS_BAREME');
    });

    test('D1 corrigé : le taux de repli des Paramètres (validé à 3 %) ne s\'applique pas à une facture patient', () {
      final m = magasin();
      m.collection('parametresAib').ajouterSansJournal({
        'id': 'PAA-IFU-2', 'statut': 'actif', 'rubrique': 'branchement_ifu', 'version': 2, 'longueurIfu': 13, 'situationIfuRenseigne': 'ifu_actif',
        'situationIfuAbsent': 'ifu_inactif_ou_absent', 'tauxRepli': 3, 'dateEffet': '2026-10-01', 'decideur': 'Direction', 'dateDecision': '2026-09-30', 'motif': 'x',
      });
      final f = vente(m, {'date': '2026-10-30', 'ifuClient': '3201001996110', 'acheteurNom': 'Clinique X'});
      expect(normaliserVente(m, '${f['id']}', maintenant: aujourdhui).code, 'MECEF_NON_CONFIGURE');
      final p = m.collection('factures').parId(f['id'])!;
      expect([p['aibTaux'], p['aibMontant']], [0, 0]);
      expect(parametresAib(m, aujourdhui).tauxRepli, 3, reason: 'le réglage existe, il ne vise pas la facture patient');
    });

    test('E3770 : une pièce qui porte encore un taux (5 %, encaissée avant la décision) est normalisée SANS AIB : le taux est retiré et le journal le dit', () {
      final m = magasin();
      final f = vente(m, {'date': '2026-10-30', 'aibTaux': 5, 'aibSituation': 'ifu_inactif_ou_absent'});
      expect(normaliserVente(m, '${f['id']}', maintenant: aujourdhui).code, 'MECEF_NON_CONFIGURE');
      final p = m.collection('factures').parId(f['id'])!;
      expect([p['aibTaux'], p['aibSituation'], p['aibMontant']], [0, null, 0]);
      final j = m.collection('audit').toutes.lastWhere((a) => '${a['action']}'.startsWith('Normalisation'));
      expect((j['avant'] as Map)['aibTaux'], 5);
    });

    test('la longueur de l\'IFU vient toujours des Paramètres (10 chiffres) pour le moteur de l\'acheteur tiers ; une facture patient n\'en contrôle aucun', () {
      final m = magasin();
      m.collection('parametresAib').ajouterSansJournal({
        'id': 'PAA-IFU-2', 'statut': 'actif', 'rubrique': 'branchement_ifu', 'version': 2, 'longueurIfu': 10, 'situationIfuRenseigne': 'ifu_actif',
        'situationIfuAbsent': 'ifu_inactif_ou_absent', 'tauxRepli': 0, 'dateEffet': '2026-10-01', 'decideur': 'Direction', 'dateDecision': '2026-09-30', 'motif': 'x',
      });
      final r = validerAcheteurMecef(ifu: '3201001996110', nom: 'X', aibTaux: 0, longueurIfu: parametresAib(m, aujourdhui).longueurIfu);
      expect(r.refus!.code, 'IFU_INVALIDE');
      expect(r.refus!.motif, contains('10 chiffres'));
      final f = vente(m, {'date': '2026-10-30', 'ifuClient': '3201001996110', 'acheteurNom': 'X'});
      expect(normaliserVente(m, '${f['id']}', maintenant: aujourdhui).code, 'MECEF_NON_CONFIGURE');
    });
  });
}
