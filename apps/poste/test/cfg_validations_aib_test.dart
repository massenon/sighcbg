import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// `cfg-validations-aib` — les TROIS FORMULAIRES DE VALIDATION de l'AIB aux Paramètres, AU GESTE (Direction, 09/11/2026, D4, D7, D8) : le barème par
/// situation, la base de la retenue des factures fournisseurs, le branchement de l'IFU. Chacun : des choix, un décideur et une date de décision OBLIGATOIRES,
/// une version DATÉE ajoutée (jamais d'écrasement), le journal (RG-12), et la lecture seule sans le droit d'écrire.
Magasin magasinAib() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Future<void> choisirDate(WidgetTester t, String champ, String jour) async {
  await toucherM14(t, find.descendant(of: find.byKey(Key('kit:champ:$champ')), matching: find.byType(InkWell)).first);
  await t.pump(const Duration(milliseconds: 400));
  await t.tap(find.byIcon(Icons.edit_outlined));
  await t.pump(const Duration(milliseconds: 300));
  await t.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).first, jour);
  await t.pump();
  await t.tap(find.text('OK'));
  await t.pump(const Duration(milliseconds: 400));
  // la fermeture du sélecteur dure plus longtemps que le premier battement : sans ce second, le champ suivant se trouve sous le fond du dialogue
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> ongletAib(WidgetTester t, String libelle) => toucherM14(t, find.text(libelle));

Fiche? derniere(Magasin m, String rubrique) {
  final l = cpaVersionsDe(m.collection(cpaCollection).actives, rubrique);
  return l.isEmpty ? null : l.last;
}

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('droits : écriture DAF, comptable, administrateur ; lecture Direction, aide-comptable et assistant de direction ; rien ailleurs', () {
    test('la matrice du poste', () {
      for (final r in ['admin', 'da', 'comptable']) {
        expect(donneesNav.matrice.peutEditer(r, 'cfg-validations-aib'), isTrue, reason: r);
      }
      for (final r in ['direction', 'aide_comptable', 'assistant_comptable']) {
        expect(donneesNav.matrice.peutVoir(r, 'cfg-validations-aib'), isTrue, reason: r);
        expect(donneesNav.matrice.peutEditer(r, 'cfg-validations-aib'), isFalse, reason: r);
      }
      // Le directeur médical n'a PAS accès (liste arrêtée par la Direction le 09/11/2026 : comptable, DAF, administrateur, aide-comptable, assistant de direction, et la Direction elle-même en lecture).
      for (final r in ['dm', 'caissier', 'medecin', 'reception', 'stock', 'laborantin', 'infirmier']) {
        expect(donneesNav.matrice.peutVoir(r, 'cfg-validations-aib'), isFalse, reason: r);
      }
      expect(donneesNav.manifeste.ecran('cfg-validations-aib')!.module, 'CFG');
    });

    casM14('lecture seule : l\'aide-comptable lit les quatre onglets, aucune commande de validation n\'est offerte', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib', role: 'aide_comptable');
      expect(find.textContaining('Lecture seule'), findsOneWidget);
      expect(find.byKey(const Key('aib:valider:bareme')), findsNothing);
      expect(find.text('Validation du barème AIB'), findsNothing, reason: 'le formulaire est ABSENT, jamais grisé');
      await ongletAib(t, 'Base des factures fournisseurs');
      expect(find.byKey(const Key('aib:valider:base')), findsNothing);
      await ongletAib(t, 'Branchement IFU');
      expect(find.byKey(const Key('aib:valider:ifu')), findsNothing);
      expect(find.byKey(const Key('aib:table-branchement')), findsOneWidget, reason: 'la table se lit');
      await ongletAib(t, 'Comptes de l’AIB');
      expect(find.byKey(const Key('aib:valider:comptes')), findsNothing);
      expect(find.textContaining('Comptes en vigueur'), findsOneWidget, reason: 'les comptes se lisent');
      expect(m.collection(cpaCollection).actives.length, 3, reason: 'rien n\'a été écrit');
    });

    casM14('lecture seule : l\'assistant de direction lit, ne valide rien', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib', role: 'assistant_comptable');
      expect(find.textContaining('Lecture seule'), findsOneWidget);
      expect(find.byKey(const Key('aib:valider:bareme')), findsNothing);
      await ongletAib(t, 'Comptes de l’AIB');
      expect(find.byKey(const Key('aib:valider:comptes')), findsNothing);
    });

    casM14('le directeur médical n\'a plus l\'écran : l\'adresse renvoie à l\'accès refusé, aucune ligne dans la matrice', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib', role: 'dm');
      expect(find.text('Validations de l’AIB'), findsNothing);
      expect(find.byKey(const Key('aib:valider:bareme')), findsNothing);
    });

    casM14('le comptable écrit : les formulaires sont offerts', (t) async {
      await ouvrirM14(t, magasinAib(), 'cfg-validations-aib', role: 'comptable');
      expect(find.textContaining('Lecture seule'), findsNothing);
      expect(find.text('Validation du barème AIB'), findsOneWidget);
      expect(find.byKey(const Key('aib:valider:bareme')), findsOneWidget);
    });
  });

  group('1. Validation du barème AIB — pilote la mécanique d\'arrêt de m12-aib', () {
    casM14('arrêter le 1 % de l\'IFU actif au 01/12/2026 : le barème est arrêté, la décision est une version datée, journalisée', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib');
      expect(find.textContaining('À REVOIR : 1 % (Acheteur avec IFU actif)'), findsOneWidget);
      await choisirM14(t, 'version', 'Acheteur avec IFU actif — 1 % — non arrêtée');
      await choisirDate(t, 'dateEffet', '12/01/2026');
      await saisir(t, 'decideur', 'Direction');
      await choisirDate(t, 'dateDecision', '10/30/2026');
      await saisir(t, 'motif', 'Texte de la DGI reçu : 1 % arrêté pour un acheteur avec IFU actif');
      await toucherM14(t, find.byKey(const Key('aib:valider:bareme')));
      final bai = m.collection('baremeAib').parId('BAI02')!;
      expect([bai['arrete'], bai['statutArret'], bai['dateEffet'], bai['decideurArret'], bai['dateArret'], bai['aValider']],
          [true, 'arrete', '2026-12-01', 'Direction', '2026-10-30', false]);
      final v = derniere(m, cpaRubriqueBareme)!;
      expect([v['id'], v['version'], v['choix'], v['versionBaremeId'], v['decideur'], v['dateDecision']], ['PAA-BAR-1', 1, 'arreter', 'BAI02', 'Direction', '2026-10-30']);
      expect(m.collection('audit').toutes.any((a) => '${a['action']}'.startsWith('Validation du barème AIB') && a['reference'] == 'PAA-BAR-1'), isTrue, reason: 'RG-12');
      expect(find.text('Version du barème arrêtée.'), findsOneWidget);
      final fiches = m.collection('baremeAib').actives;
      expect(cpdTauxAibALaDate(fiches, 'ifu_actif', DateTime(2026, 11, 30)).taux, isNull, reason: 'pas avant la date d\'effet');
      expect(cpdTauxAibALaDate(fiches, 'ifu_actif', DateTime(2026, 12, 1)).taux, 1);
    });

    casM14('maintenir non arrêtée : la décision est consignée, le barème ne bouge pas, le motif est obligatoire', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await choisirM14(t, 'choix', 'Maintenir non arrêtée');
      await saisir(t, 'decideur', 'Direction');
      await choisirDate(t, 'dateDecision', '10/30/2026');
      await toucherM14(t, find.byKey(const Key('aib:valider:bareme')));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget, reason: 'le motif manque');
      expect(m.collection(cpaCollection).actives.length, 3);
      ToastsSigh.viderPourTests();
      await saisir(t, 'motif', 'En attente du texte de la DGI');
      await toucherM14(t, find.byKey(const Key('aib:valider:bareme')));
      expect(m.collection('baremeAib').parId('BAI02')!['arrete'], isFalse);
      final v = derniere(m, cpaRubriqueBareme)!;
      expect([v['choix'], v['decideur']], ['maintenir', 'Direction']);
      expect(find.text('Version maintenue non arrêtée.'), findsOneWidget);
    });

    casM14('décideur et date de la décision OBLIGATOIRES : sans eux, rien n\'est écrit', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await choisirDate(t, 'dateEffet', '12/01/2026');
      await saisir(t, 'motif', 'Test');
      await toucherM14(t, find.byKey(const Key('aib:valider:bareme')));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection('baremeAib').parId('BAI02')!['arrete'], isFalse);
      expect(m.collection(cpaCollection).actives.length, 3);
    });

    casM14('une date de décision future est refusée en le nommant', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await choisirDate(t, 'dateEffet', '12/01/2026');
      await saisir(t, 'decideur', 'Direction');
      await choisirDate(t, 'dateDecision', '12/31/2026');
      await saisir(t, 'motif', 'Test');
      await toucherM14(t, find.byKey(const Key('aib:valider:bareme')));
      expect(find.textContaining('PARAM_DATE_FUTURE'), findsOneWidget);
      expect(m.collection('baremeAib').parId('BAI02')!['arrete'], isFalse);
    });
  });

  group('2. Validation de la base de l\'AIB des factures fournisseurs', () {
    casM14('choisir « montant facturé » à compter du 01/12/2026 : une version v2 est AJOUTÉE, la v1 reste, la base de la date est lue par le moteur', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await ongletAib(t, 'Base des factures fournisseurs');
      expect(find.textContaining('Base en vigueur au 30/10/2026'), findsOneWidget);
      await choisirM14(t, 'base', 'Montant facturé (toujours)');
      await choisirDate(t, 'dateEffet', '12/01/2026');
      await saisir(t, 'decideur', 'Direction');
      await choisirDate(t, 'dateDecision', '10/30/2026');
      await saisir(t, 'motif', 'Avis de l\'expert-comptable : la base est le montant facturé');
      await toucherM14(t, find.byKey(const Key('aib:valider:base')));
      final fiches = m.collection(cpaCollection).actives;
      final v = derniere(m, cpaRubriqueBase)!;
      expect([v['id'], v['version'], v['base'], v['dateEffet'], v['decideur'], v['dateDecision']], ['PAA-BASE-2', 2, 'facture', '2026-12-01', 'Direction', '2026-10-30']);
      expect(fiches.any((f) => f['id'] == 'PAA-BASE-1'), isTrue, reason: 'jamais d\'écrasement : la version 1 reste');
      expect(cpaParametresALaDate(fiches, DateTime(2026, 11, 30)).base, 'ht');
      expect(cpaParametresALaDate(fiches, DateTime(2026, 12, 1)).base, 'facture');
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Validation de la base de l’AIB des factures fournisseurs' && a['reference'] == 'PAA-BASE-2'), isTrue);
      expect(find.text('Base de l’AIB validée.'), findsOneWidget);
    });

    casM14('une date d\'effet qui ne dépasse pas la version la plus récente est refusée : une version ne se réécrit pas', (t) async {
      final m = magasinAib();
      m.collection(cpaCollection).ajouterSansJournal({
        'id': 'PAA-BASE-2', 'statut': 'actif', 'rubrique': cpaRubriqueBase, 'version': 2, 'base': 'facture', 'dateEffet': '2026-10-15',
        'decideur': 'Direction', 'dateDecision': '2026-10-10', 'motif': 'x',
      });
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await ongletAib(t, 'Base des factures fournisseurs');
      await choisirDate(t, 'dateEffet', '10/15/2026');
      await saisir(t, 'decideur', 'Direction');
      await choisirDate(t, 'dateDecision', '10/30/2026');
      await saisir(t, 'motif', 'Test');
      await toucherM14(t, find.byKey(const Key('aib:valider:base')));
      expect(find.textContaining('PARAM_DATE_ANTERIEURE'), findsOneWidget);
      expect(derniere(m, cpaRubriqueBase)!['version'], 2);
    });

    casM14('décideur obligatoire', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await ongletAib(t, 'Base des factures fournisseurs');
      await choisirDate(t, 'dateEffet', '12/01/2026');
      await choisirDate(t, 'dateDecision', '10/30/2026');
      await saisir(t, 'motif', 'Test');
      await toucherM14(t, find.byKey(const Key('aib:valider:base')));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(m.collection(cpaCollection).actives.length, 3);
    });
  });

  group('3. Validation du branchement IFU', () {
    casM14('la table lit le taux au barème : 5 % arrêté sans IFU actif, « aucun taux arrêté : repli à 0 % » pour l\'IFU actif', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await ongletAib(t, 'Branchement IFU');
      expect(find.textContaining('5 % — Taux de 5 % arrêté, en vigueur depuis le 07/09/2026.'), findsOneWidget);
      expect(find.textContaining('aucun taux arrêté : repli à 0 %'), findsWidgets);
      expect(find.textContaining('IFU de 13 chiffres renseigné (présumé actif)'), findsOneWidget);
    });

    casM14('valider un repli à 2 % et un IFU de 10 chiffres : version v2 datée, le moteur la lit à partir de sa date d\'effet', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await ongletAib(t, 'Branchement IFU');
      await saisir(t, 'longueurIfu', '10');
      await saisir(t, 'tauxRepli', '2');
      await choisirDate(t, 'dateEffet', '12/01/2026');
      await saisir(t, 'decideur', 'Direction');
      await choisirDate(t, 'dateDecision', '10/30/2026');
      await saisir(t, 'motif', 'Décision de la Direction : repli à 2 %');
      await toucherM14(t, find.byKey(const Key('aib:valider:ifu')));
      final v = derniere(m, cpaRubriqueBranchement)!;
      expect([v['id'], v['version'], v['longueurIfu'], v['tauxRepli'], v['situationIfuRenseigne'], v['dateEffet'], v['decideur']],
          ['PAA-IFU-2', 2, 10, 2, 'ifu_actif', '2026-12-01', 'Direction']);
      final fiches = m.collection(cpaCollection).actives;
      expect(fiches.any((f) => f['id'] == 'PAA-IFU-1'), isTrue);
      expect(cpaParametresALaDate(fiches, DateTime(2026, 11, 30)).tauxRepli, 0);
      expect(cpaParametresALaDate(fiches, DateTime(2026, 12, 1)).tauxRepli, 2);
      expect(cpaParametresALaDate(fiches, DateTime(2026, 12, 1)).longueurIfu, 10);
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Validation du branchement IFU' && a['reference'] == 'PAA-IFU-2'), isTrue);
    });

    casM14('un taux de repli hors 0 à 100 est refusé en le nommant', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await ongletAib(t, 'Branchement IFU');
      await saisir(t, 'tauxRepli', '150');
      await choisirDate(t, 'dateEffet', '12/01/2026');
      await saisir(t, 'decideur', 'Direction');
      await choisirDate(t, 'dateDecision', '10/30/2026');
      await saisir(t, 'motif', 'Test');
      await toucherM14(t, find.byKey(const Key('aib:valider:ifu')));
      expect(find.textContaining('PARAM_TAUX_REPLI'), findsOneWidget);
      expect(derniere(m, cpaRubriqueBranchement)!['version'], 1);
    });
  });

  group('4. Comptes de l\'AIB — lus par les moteurs à la date de la pièce, marqués à confirmer tant qu\'aucun décideur n\'a validé', () {
    casM14('la graine semée : 4492 / 4478 / 891 / 401000, le marquage « à confirmer par l\'expert-comptable » est visible', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await ongletAib(t, 'Comptes de l’AIB');
      expect(find.textContaining('AIB subi 4492, AIB retenu 4478, imputation 891, fournisseur 401000'), findsOneWidget);
      expect(find.byKey(const Key('aib:comptes-a-confirmer')), findsOneWidget);
      expect(find.textContaining('À CONFIRMER PAR L’EXPERT-COMPTABLE'), findsWidgets);
      expect(find.byKey(const Key('aib:valider:comptes')), findsOneWidget);
    });

    casM14('collection vide : la graine du code répond, et l\'écran DIT que c\'est un repli', (t) async {
      final m = magasinAib();
      for (final f in m.collection(cpaCollection).actives) {
        m.collection(cpaCollection).archiver(f['id']);
      }
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await ongletAib(t, 'Comptes de l’AIB');
      expect(find.textContaining('la graine du code répond (repli)'), findsOneWidget);
    });

    casM14('valider un compte d\'AIB subi à 4491 à compter du 01/12/2026 : v2 AJOUTÉE, v1 intacte, marquage levé, journalisée, lue à la date', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await ongletAib(t, 'Comptes de l’AIB');
      await choisirDate(t, 'dateEffet', '12/01/2026');
      await choisirDate(t, 'dateDecision', '10/30/2026');
      await saisir(t, 'compteAibSubi', '4491');
      await saisir(t, 'decideur', 'Expert-comptable');
      await saisir(t, 'motif', 'Confirmation écrite de l\'expert-comptable');
      await toucherM14(t, find.byKey(const Key('aib:valider:comptes')));
      final v = derniere(m, cpaRubriqueComptes)!;
      expect([v['id'], v['version'], v['compteAibSubi'], v['compteAibRetenu'], v['compteImputation'], v['compteFournisseur'], v['dateEffet'], v['decideur']],
          ['PAA-COMPTES-2', 2, '4491', '4478', '891', '401000', '2026-12-01', 'Expert-comptable']);
      final fiches = m.collection(cpaCollection).actives;
      expect(fiches.any((f) => f['id'] == 'PAA-COMPTES-1'), isTrue, reason: 'jamais d\'écrasement : la version 1 reste');
      expect(cpaComptesALaDate(fiches, DateTime(2026, 11, 30)).subi, '4492', reason: 'les pièces antérieures gardent leurs comptes');
      final apres = cpaComptesALaDate(fiches, DateTime(2026, 12, 1));
      expect([apres.subi, apres.aConfirmer], ['4491', false]);
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Validation des comptes de l’AIB' && a['reference'] == 'PAA-COMPTES-2'), isTrue);
      expect(find.text('Comptes de l’AIB validés.'), findsOneWidget);
    });

    casM14('refus nommés : compte invalide, comptes confondus, date d\'effet non postérieure ; décideur obligatoire', (t) async {
      final m = magasinAib();
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await ongletAib(t, 'Comptes de l’AIB');
      await choisirDate(t, 'dateEffet', '12/01/2026');
      await choisirDate(t, 'dateDecision', '10/30/2026');
      await saisir(t, 'compteAibSubi', '44X2');
      await saisir(t, 'decideur', 'Direction');
      await saisir(t, 'motif', 'Test');
      await toucherM14(t, find.byKey(const Key('aib:valider:comptes')));
      expect(find.textContaining('PARAM_COMPTE_INVALIDE'), findsOneWidget);
      await saisir(t, 'compteAibSubi', '4478');
      await toucherM14(t, find.byKey(const Key('aib:valider:comptes')));
      expect(find.textContaining('PARAM_COMPTES_CONFONDUS'), findsOneWidget);
      await saisir(t, 'compteAibSubi', '4491');
      await saisir(t, 'decideur', '');
      await toucherM14(t, find.byKey(const Key('aib:valider:comptes')));
      expect(find.text('Le formulaire comporte des erreurs.'), findsOneWidget);
      expect(derniere(m, cpaRubriqueComptes)!['version'], 1, reason: 'rien n\'a été écrit');
    });

    casM14('une version déjà posée au 15/10/2026 : une date d\'effet qui ne la dépasse pas est refusée (le passé ne se réécrit pas)', (t) async {
      final m = magasinAib();
      m.collection(cpaCollection).ajouterSansJournal({
        'id': 'PAA-COMPTES-2', 'statut': 'actif', 'rubrique': cpaRubriqueComptes, 'version': 2, 'dateEffet': '2026-10-15', 'compteAibSubi': '4491',
        'compteAibRetenu': '4478', 'compteImputation': '891', 'compteFournisseur': '401000', 'decideur': 'Expert-comptable', 'dateDecision': '2026-10-10', 'motif': 'x',
      });
      await ouvrirM14(t, m, 'cfg-validations-aib');
      await ongletAib(t, 'Comptes de l’AIB');
      expect(find.byKey(const Key('aib:comptes-a-confirmer')), findsNothing, reason: 'une version validée lève le marquage');
      await choisirDate(t, 'dateEffet', '10/15/2026');
      await choisirDate(t, 'dateDecision', '10/30/2026');
      await saisir(t, 'decideur', 'Direction');
      await saisir(t, 'motif', 'Test');
      await toucherM14(t, find.byKey(const Key('aib:valider:comptes')));
      expect(find.textContaining('PARAM_DATE_ANTERIEURE'), findsOneWidget);
      expect(derniere(m, cpaRubriqueComptes)!['version'], 2);
    });
  });
}
