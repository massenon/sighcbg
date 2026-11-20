// LE RÈGLEMENT EN PLUSIEURS VERSEMENTS (Direction de Baguidi, 20/11/2026, §13) au poste : deux versements de deux types sur la même facture, prestations libérées une à une,
// une écriture par versement sur le compte de SON type, états par mode lus dans les versements, reçu détaillé, MECeF muet sur les modes, contre-passation sous geste réservé.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/config_poste.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/parcours_caisse.dart';
import 'package:sigh_poste/impression/piece.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/main.dart';
import 'package:sigh_poste/modules/m8/commun.dart';
import 'package:sigh_poste/modules/m8/saisie_versements.dart';

import 'aide_polices.dart';

typedef F = Map<String, Object?>;

final donnees = DonneesNavigation.depuisDossier();
final auj = DateTime(2026, 11, 20, 10);

Magasin jeu() => Magasin({
      'factures': [
        {
          'id': 'F1',
          'numero': 'FN-2026-00001',
          'patient': 'DOSSOU K.',
          'patientCode': 'CBG/1/26',
          'patientId': 'P1',
          'date': '2026-11-20',
          'type': 'Pharmacie',
          'montantTTC': 6000,
          'partAssurance': 0,
          'partPatient': 6000,
          'montantPaye': 0,
          'reliquat': 6000,
          'statutPaiement': 'impayee',
          'ordonnanceId': 'O1',
          'lignes': [
            {'id': 'L1', 'categorie': 'analyse', 'designation': 'NFS', 'quantite': 1, 'prixUnitaire': 2000, 'partPatient': 2000, 'demandeId': 'D1', 'statutPaiement': 'du'},
            {'id': 'L2', 'categorie': 'analyse', 'designation': 'Glycémie', 'quantite': 1, 'prixUnitaire': 1000, 'partPatient': 1000, 'demandeId': 'D2', 'statutPaiement': 'du'},
            {'id': 'L3', 'categorie': 'medicament', 'designation': 'Paracétamol', 'quantite': 2, 'prixUnitaire': 1500, 'partPatient': 3000, 'statutPaiement': 'du'},
          ],
        },
        // Une facture d'AVANT les versements : réglée en un mode unique, sans aucun versement écrit.
        {
          'id': 'F0',
          'numero': 'FN-2026-00000',
          'patient': 'ANCIEN P.',
          'date': '2026-11-20',
          'type': 'Consultation',
          'montantTTC': 4000,
          'partPatient': 4000,
          'montantPaye': 4000,
          'reliquat': 0,
          'statutPaiement': 'soldee',
          'modePaiement': 'tpe',
          'lignes': [
            {'id': 'A1', 'categorie': 'consultation', 'designation': 'Consultation', 'quantite': 1, 'prixUnitaire': 4000, 'partPatient': 4000, 'statutPaiement': 'paye', 'montantRegle': 4000, 'payeLe': '2026-11-20T08:00:00.000'},
          ],
        },
      ],
      'taches': [
        {'id': 'T1', 'type': 'encaissement', 'statut': 'en_attente', 'factureId': 'F1', 'reference': 'ORD-0001', 'patient': 'DOSSOU K.', 'detail': 'Encaisser', 'montant': 6000, 'date': '2026-11-20'},
        {'id': 'T2', 'type': 'dispensation', 'statut': 'bloque', 'factureId': 'F1', 'ordonnanceId': 'O1', 'reference': 'ORD-0001', 'patient': 'DOSSOU K.', 'date': '2026-11-20'},
      ],
      'demandesAnalyses': [
        {'id': 'D1', 'reference': 'LAB-00001', 'bloqueParPaiement': true, 'etatAnalyse': 'en_attente', 'factureId': 'F1', 'ordonnanceId': 'O1'},
        {'id': 'D2', 'reference': 'LAB-00002', 'bloqueParPaiement': true, 'etatAnalyse': 'en_attente', 'factureId': 'F1', 'ordonnanceId': 'O1'},
      ],
      'ordonnances': [
        {'id': 'O1', 'statutPaiement': 'du'}
      ],
    });

const momo = VersementSaisi(montant: 2000, type: 'mobile_money', modalite: 'MV01', reference: 'MP2611.0042');
const cash = VersementSaisi(montant: 1000, type: 'especes');

double som(Iterable<Fiche> e, String compte, String sens) => e.where((x) => '${x['compte']}' == compte).fold(0.0, (a, x) => a + (x[sens]! as num));

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  test('deux versements (Mobile Money puis espèces) : lignes réglées une à une, aval libéré, une écriture par versement sur le compte de SON type', () {
    final m = jeu();
    final r = encaisserFacture(m, 'F1', lignes: ['L1', 'L2'], versements: [momo, cash], maintenant: auj);
    expect(r.versements.length, 2);
    expect(r.lignesReglees, ['L1', 'L2']);
    expect(r.montantRegle, 3000);
    expect(r.restantDu, 3000, reason: 'le médicament reste dû : sa ligne n’est pas payée');
    expect(r.demandesLiberees, ['LAB-00001', 'LAB-00002']);
    final f = m.collection('factures').parId('F1')!;
    expect(f['montantPaye'], 3000);
    expect(f['reliquat'], 3000);
    expect(f['statutPaiement'], 'partielle');
    expect(f['modePaiement'], modeMixte);
    // La prestation non payée reste bloquée : la dispensation n'est pas ouverte.
    expect(m.collection('taches').parId('T2')!['statut'], 'bloque');
    // Le journal : deux lignes de famille B, identités distinctes, étiquette du poste dans l'identifiant.
    final vs = m.collection(colVersements).toutes;
    expect(vs.map((v) => v['type']).toSet(), {'mobile_money', 'especes'});
    expect(vs.firstWhere((v) => v['type'] == 'mobile_money')['modaliteLibelle'], 'MTN');
    expect(vs.firstWhere((v) => v['type'] == 'mobile_money')['reference'], 'MP2611.0042');
    expect({for (final v in vs) v['id']}.length, 2);
    // Les écritures : débit 521 (type Mobile Money) 2 000, débit 571 (espèces) 1 000, crédit 706 3 000, brouillon, équilibrées.
    final e = m.collection('ecritures').actives;
    expect(som(e, '521000', 'debit'), 2000);
    expect(som(e, '571000', 'debit'), 1000);
    expect(som(e, '706000', 'credit'), 3000);
    expect(e.every((x) => x['statut'] == 'brouillon'), isTrue);
    // Le reste, plus tard, par l'ancienne voie (un mode) : un versement de plus, le règlement s'achève.
    final r2 = encaisserFacture(m, 'F1', lignes: ['L3'], mode: 'especes', maintenant: auj);
    expect(r2.versements.length, 1);
    expect(m.collection('factures').parId('F1')!['statutPaiement'], 'soldee');
    expect(m.collection('taches').parId('T2')!['statut'], 'en_attente', reason: 'la dispensation s’ouvre quand la ligne du médicament est payée');
  });

  test('refus nommés : un versement qui dépasse les prestations cochées, une référence exigée absente — rien n’est écrit', () {
    final m = jeu();
    expect(
        () => encaisserFacture(m, 'F1', lignes: ['L1'], versements: [momo, cash], maintenant: auj),
        throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', codeVersementsEcartLignes)));
    expect(
        () => encaisserFacture(m, 'F1', lignes: ['L1'], versements: [const VersementSaisi(montant: 2000, type: 'mobile_money', modalite: 'MV01')], maintenant: auj),
        throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', codeVersementReferenceExigee)));
    expect(m.collection(colVersements).toutes, isEmpty);
    expect(m.collection('ecritures').actives, isEmpty);
    expect(m.collection('factures').parId('F1')!['montantPaye'], 0);
  });

  test('un versement ne se modifie ni ne s’archive (garde du journal) ; l’« Annuler » du toast retire la ligne posée à l’instant', () {
    final m = jeu();
    final r = encaisserFacture(m, 'F1', lignes: ['L1', 'L2'], versements: [momo, cash], maintenant: auj);
    final id = '${r.versements.first['id']}';
    expect(() => m.collection(colVersements).mettreAJour(id, {'montant': 1}), throwsA(anything));
    expect(() => m.collection(colVersements).archiver(id), throwsA(anything));
    r.annuler();
    expect(m.collection(colVersements).actives, isEmpty, reason: 'l’annulation immédiate du geste retire les lignes');
    expect(m.collection('factures').parId('F1')!['montantPaye'], 0);
  });

  test('états par mode : 2 000 Mobile Money + 1 000 espèces compte 2 000 d’un côté et 1 000 de l’autre ; l’ancienne facture compte pour son mode unique', () {
    final m = jeu();
    encaisserFacture(m, 'F1', lignes: ['L1', 'L2'], versements: [momo, cash], maintenant: auj);
    final par = repartitionParType(m.collection('factures').actives, m.collection(colVersements).toutes);
    expect(par['mobile_money'], 2000);
    expect(par['especes'], 1000);
    expect(par['tpe'], 4000);
    expect(modeDeFacture(m, m.collection('factures').parId('F1')!), 'Mobile Money + Espèces');
    expect(modeDeFacture(m, m.collection('factures').parId('F0')!), 'TPE (carte bancaire)');
    // Le tableau de bord du caissier (domaine) lit les mêmes versements.
    final d = tbaCaissier(taches: const [], factures: m.collection('factures').actives, auj: auj, versements: m.collection(colVersements).toutes, typesVersement: m.collection(colTypesVersement).toutes);
    final lecture = {for (final (i, l) in d.parMode.etiquettes.indexed) l: d.parMode.series.first.donnees[i]};
    expect(lecture['Mobile Money'], 2000);
    expect(lecture['Espèces'], 1000);
    expect(lecture['TPE (carte bancaire)'], 4000);
  });

  test('reçu détaillé : chaque versement (mode, modalité, référence, montant) et le reste dû ; la facture et le ticket ne mentionnent NI versement NI mode', () {
    final m = jeu();
    encaisserFacture(m, 'F1', lignes: ['L1', 'L2'], versements: [momo, cash], maintenant: auj);
    final f = m.collection('factures').parId('F1')!;
    final vs = versementsDeFacture(f, m.collection(colVersements).toutes);
    final recu = pieceRecu(f, versements: vs, libelleType: (c) => libelleDeType(m.collection(colTypesVersement).toutes, c), utilisateur: 'Caissier', edite: auj, reference: 'R1');
    final tableau = recu.blocs.whereType<BlocTableau>().firstWhere((b) => b.titre == 'Versements').tableau;
    expect(tableau.lignes.length, 2);
    final cellules = [for (final l in tableau.lignes) for (final c in tableau.colonnes) '${c.valeur(l)}'].join('|');
    expect(cellules, contains('Mobile Money'));
    expect(cellules, contains('MTN'));
    expect(cellules, contains('MP2611.0042'));
    expect(cellules, contains('Espèces'));
    expect([for (final b in recu.blocs.whereType<BlocTableau>()) for (final l in b.tableau.lignes) '${l['k'] ?? ''}'].join('|'), contains('RESTE À PAYER'));
    // DÉCISION DE LA DIRECTION : la pièce normalisée n'a que le montant total, le libellé d'arrêté et le montant en lettres.
    final fac = pieceFacture(f, mecefActif: true, utilisateur: 'Caissier', edite: auj, reference: 'F-1');
    final tout = [
      for (final b in fac.blocs) ...[
        if (b is BlocTexte) b.texte,
        if (b is BlocTableau) for (final l in b.tableau.lignes) '${l['k'] ?? ''} ${l['v'] ?? ''}',
      ],
      ...fac.cartouche.map((x) => '${x.$1} ${x.$2}'),
    ].join(' | ').toLowerCase();
    for (final interdit in ['mobile money', 'espèces', 'especes', 'mtn', 'mp2611', 'mode de règlement', 'versement', 'plusieurs modes', 'vrs-']) {
      expect(tout.contains(interdit), isFalse, reason: 'la facture normalisée ne mentionne pas « $interdit »');
    }
    expect(tout, contains(IdentiteImprimee.semence.formuleArrete.toLowerCase()), reason: 'le libellé d’arrêté reste');
    // Le ticket 80 mm ne reçoit ni versements ni modes : sa structure n'en porte pas (mêmes lignes, pour la même facture).
    final lignes = lignesTicket(EntreeTicket(operateur: 'Caissier', numero: 'T-1', date: auj, total: 6000, partPatient: 6000, regle: 3000, lignes: const [LigneArticle(designation: 'NFS', quantite: 1, prixUnitaire: 2000, montant: 2000)])).map((l) => l.brut).join('|').toLowerCase();
    for (final interdit in ['mobile money', 'espèces', 'mtn', 'versement', 'mode']) {
      expect(lignes.contains(interdit), isFalse, reason: 'le ticket ne mentionne pas « $interdit »');
    }
    expect(lignes, contains(IdentiteImprimee.semence.formuleArrete.toLowerCase()));
    expect(lignes, contains('montant total'));
  });

  test('la saisie : ajouter, retirer, reste à répartir recalculé, plafond et référence exigée refusés en nommant', () {
    final m = jeu();
    num aRepartir = 3000;
    final refus = <String>[];
    final sv = SaisieVersements(magasin: m, aRepartir: () => aRepartir, toast: (t, d) => refus.add(d));
    expect(sv.reste, 3000);
    sv.form.poser('versement_type', 'mobile_money');
    sv.form.poser('versement_modalite_mobile_money', 'MV02');
    sv.form.poser('versement_montant', '2000');
    expect(sv.ajouter(), isFalse, reason: 'référence exigée');
    expect(refus.last, contains('exige la référence'));
    sv.form.poser('versement_reference', 'MV-77');
    expect(sv.ajouter(), isTrue);
    expect(sv.reste, 1000);
    sv.form.poser('versement_type', 'especes');
    sv.form.poser('versement_montant', '5000');
    expect(sv.ajouter(), isFalse, reason: 'plafond');
    expect(refus.last, contains('dépasse le reste à répartir'));
    sv.form.poser('versement_montant', '');
    final fin = sv.finaliser()!;
    expect(fin.map((v) => (v.type, v.montant)), [('mobile_money', 2000), ('especes', 1000)]);
    expect(fin.first.modalite, 'MV02');
    sv.retirer(0);
    expect(sv.reste, 2000);
  });

  testWidgets('écran d’encaissement : « Ajouter un versement », reste à répartir, validation — la facture est réglée par UN versement ou plusieurs', (t) async {
    final m = jeu();
    t.view.physicalSize = const Size(1600, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(SighPoste(key: UniqueKey(), donnees: donnees, config: ConfigPoste(mode: ModePoste.fileul, role: 'admin'), ecranInitial: 'm8-caisse', magasin: m, horloge: () => auj));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.byTooltip('Encaisser').first);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Ajouter un versement'), findsOneWidget);
    expect(find.text(money(6000)), findsWidgets);
    expect(find.byKey(const Key('versements:reste')), findsOneWidget);
    // Un premier versement (type par défaut, montant = le reste), ajouté à la liste : le reste tombe à zéro.
    await t.ensureVisible(find.text('Ajouter un versement'));
    await t.tap(find.text('Ajouter un versement'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('versements:ligne:0')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('versements:reste'))).data, money(0));
    await t.ensureVisible(find.text('Valider l’encaissement'));
    await t.tap(find.text('Valider l’encaissement'));
    await t.pump(const Duration(milliseconds: 500));
    expect(m.collection(colVersements).toutes.length, 1);
    expect(m.collection('factures').parId('F1')!['statutPaiement'], 'soldee');
    await t.pump(const Duration(seconds: 15));
  });

  group('annuler un règlement : un geste réservé (contre-passation), jamais une suppression', () {
    test('le droit : comptable et DAF d’origine, ni le caissier ni l’administrateur ; une fiche de rôle l’accorde ou le retire', () {
      final g = DroitsGestes(fiches: const []);
      expect(g.peut('comptable', gesteVersementAnnuler), isTrue);
      expect(g.peut('da', gesteVersementAnnuler), isTrue);
      expect(g.peut('caissier', gesteVersementAnnuler), isFalse);
      expect(g.peut('admin', gesteVersementAnnuler), isFalse);
      final accorde = DroitsGestes(fiches: [
        {'id': 'RBAC1', 'role': 'caissier', 'droitsGestes': {gesteVersementAnnuler: true}}
      ]);
      expect(accorde.peut('caissier', gesteVersementAnnuler), isTrue);
      final retire = DroitsGestes(fiches: [
        {'id': 'RBAC2', 'role': 'comptable', 'droitsGestes': {gesteVersementAnnuler: false}}
      ]);
      expect(retire.peut('comptable', gesteVersementAnnuler), isFalse);
      expect(g.peut('admin', gesteVersementRegler), isTrue);
      expect(g.peut('caissier', gesteVersementRegler), isFalse);
    });

    test('contre-passation : refusée sans le droit ; accordée, elle écrit une ligne par versement, l’écriture inverse, rouvre les lignes et REBLOQUE le laboratoire', () {
      final m = jeu();
      final r = encaisserFacture(m, 'F1', lignes: ['L1', 'L2'], versements: [momo, cash], maintenant: auj);
      final premier = '${r.versements.first['id']}';
      expect(() => contrepasserVersement(m, premier, motif: 'Erreur', maintenant: auj, droit: () => false), throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', 'DROIT_REFUSE')));
      expect(() => contrepasserVersement(m, premier, motif: ' ', maintenant: auj, droit: () => true), throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', codeVersementMotifObligatoire)));
      final c = contrepasserVersement(m, premier, motif: 'Montant saisi par erreur', maintenant: auj, droit: () => true);
      expect(c.contrepassations.length, 2);
      expect(c.lignesRouvertes, ['L1', 'L2']);
      final f = m.collection('factures').parId('F1')!;
      expect(f['montantPaye'], 0);
      expect(f['reliquat'], 6000);
      expect(f['statutPaiement'], 'impayee');
      expect(m.collection('demandesAnalyses').parId('D1')!['bloqueParPaiement'], isTrue);
      expect(m.collection('demandesAnalyses').parId('D1')!['etatAnalyse'], 'en_attente');
      // Rien n'a été supprimé : 2 versements + 2 contre-passations ; la lecture ne voit plus de versement en vigueur.
      expect(m.collection(colVersements).toutes.length, 4);
      expect(versementsDeFacture(f, m.collection(colVersements).toutes), isEmpty);
      // Les écritures : les deux d'origine et leurs deux inverses (équilibre global nul sur chaque compte de trésorerie).
      final e = m.collection('ecritures').actives;
      expect(som(e, '521000', 'debit') - som(e, '521000', 'credit'), 0);
      expect(som(e, '571000', 'debit') - som(e, '571000', 'credit'), 0);
      // Une seconde annulation du même règlement : refusée.
      expect(() => contrepasserVersement(m, premier, motif: 'Encore', maintenant: auj, droit: () => true), throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', codeVersementDejaAnnule)));
    });

    test('une prestation déjà exécutée (examen prélevé) : l’annulation est REFUSÉE en nommant, rien n’est écrit', () {
      final m = jeu();
      final r = encaisserFacture(m, 'F1', lignes: ['L1', 'L2'], versements: [momo, cash], maintenant: auj);
      m.collection('demandesAnalyses').mettreAJour('D1', {'etatAnalyse': 'en_cours'});
      expect(() => contrepasserVersement(m, '${r.versements.first['id']}', motif: 'Erreur', maintenant: auj, droit: () => true),
          throwsA(isA<RefusCaisse>().having((e) => e.code, 'code', 'PRESTATION_DEJA_EXECUTEE')));
      expect(m.collection(colVersements).toutes.length, 2);
      expect(m.collection('factures').parId('F1')!['montantPaye'], 3000);
    });
  });
}
