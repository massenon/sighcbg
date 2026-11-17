import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/numerotation_poste.dart';
import 'package:sigh_poste/core/plages_codes.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/sync/service_validations_deposees.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

typedef M = Map<String, Object?>;

/// LOT 2 — le RÉFÉRENTIEL DE NUMÉROTATION au poste : la collection `seriesNumerotation` alimente la fabrique du domaine (au démarrage et à chaque écriture),
/// la mère écrit une version datée, un fileul la DÉPOSE et la mère la rejoue, les plages des bons suivent la série, et la section « Numérotation des pièces »
/// de « Fiscalité & identité légale » offre « Modifier » au seul profil qui détient le geste et le droit d'éditer.
void main() {
  setUpAll(chargerPolices);
  tearDown(() {
    Numerotation.reinitialiser();
    ToastsSigh.viderPourTests();
  });

  Magasin vide(DateTime auj) => Magasin({
        colSeriesNumerotation: <M>[],
        'validationsDeposees': <M>[],
        'rbac': <M>[],
        'besoins': <M>[],
        'utilisateurs': <M>[
          {'id': 'U-da', 'statut': 'actif', 'role': 'da', 'actif': true}
        ],
      }, 'POSTE', {})
        ..horloge = () => auj;

  test('une version écrite à la mère s’applique aux pièces À VENIR dès l’écriture ; les numéros déjà émis ne bougent pas', () {
    final auj = DateTime(2026, 11, 16, 9);
    final m = vide(auj);
    brancherNumerotation(m);
    final svc = ServiceValidationsDeposees.de(m)..horloge = () => auj;
    expect(numeroSuivant('achats.besoins', date: '2027-01-05', existants: ['BEB-2026-0040']), 'BEB-2027-0001', reason: 'semence : l’année de la pièce, remise annuelle');
    final r = svc.modifierSerie('achats.besoins', {'prefixe': 'EB'}, '2027-01-01', role: 'da', acteur: 'DAF', estMere: true, motif: 'Format arrêté');
    expect(r.refus, isNull);
    expect(r.version!['aValider'], false);
    expect(m.collection(colSeriesNumerotation).toutes, hasLength(1));
    expect(numeroSuivant('achats.besoins', date: '2027-01-05', existants: ['BEB-2026-0040']), 'EB-2027-0001', reason: 'la fabrique a suivi l’écriture, sans redémarrage');
    expect(numeroSuivant('achats.besoins', date: '2026-12-31', existants: ['BEB-2026-0040']), 'BEB-2026-0041', reason: 'avant la date d’effet, rien ne change');
    expect(m.collection('audit').toutes.any((a) => '${a['action']}'.contains('série de numérotation')), isTrue, reason: 'RG-12');
    // Le caissier n'a pas le geste : refus nommé, rien d'écrit.
    final refus = svc.modifierSerie('achats.besoins', {'prefixe': 'XX'}, '2027-02-01', role: 'caissier', acteur: 'Caisse', estMere: true, motif: 'essai');
    expect(refus.refus!.code, 'NUMEROTATION_RESERVEE');
    expect(m.collection(colSeriesNumerotation).toutes, hasLength(1));
  });

  test('un fileul DÉPOSE la modification ; la mère l’applique sous le rôle de l’auteur ; la version revient (famille R)', () {
    final auj = DateTime(2026, 11, 16, 9);
    final fileul = vide(auj), mere = vide(auj);
    final svcF = ServiceValidationsDeposees.de(fileul)
      ..etiquette = 'F1'
      ..horloge = () => auj;
    final d = svcF.modifierSerie('achats.commandes', {'prefixe': 'CMD', 'largeur': 5}, '2026-12-01', role: 'da', acteur: 'DAF', estMere: false, motif: 'Lettres de la Direction');
    expect(d.refus, isNull);
    expect(d.version, isNull, reason: 'un fileul n’écrit pas le référentiel');
    expect(fileul.collection(colSeriesNumerotation).toutes, isEmpty);
    expect(svcF.depotSerieEnAttente('achats.commandes'), isNotNull);
    // Le dépôt voyage (famille A) : la mère le traite.
    // Le compte signataire (AI, 16/11/2026) : celui de l'agent connecté au fileul, que la mère vérifie.
    mere.collection('validationsDeposees').ajouterSansJournal({...d.depot!, champCompteDecision: 'U-da'});
    final svcM = ServiceValidationsDeposees.de(mere)
      ..etiquette = 'M'
      ..horloge = () => auj;
    expect(svcM.traiter(), 1);
    final verdict = mere.collection('validationsDeposees').toutes.single;
    expect(verdict['etat'], valDepotAppliquee, reason: '${verdict['resultatCode']} : ${verdict['resultatMotif']}');
    final v = mere.collection(colSeriesNumerotation).toutes.single;
    expect(v['prefixe'], 'CMD');
    expect(v['creePar'], 'DAF', reason: 'appliquée sous le nom de son auteur');
    // Reçue par le fileul (la synchronisation pose la fiche) : sa fabrique suit.
    brancherNumerotation(fileul);
    fileul.collection(colSeriesNumerotation).appliquerDistante(v);
    expect(numeroSuivant('achats.commandes', date: '2026-12-02', existants: const []), 'CMD-2026-00001');
  });

  test('les plages des bons suivent la série : numéro de la plage, puis référence PROVISOIRE de la série une fois la plage épuisée', () {
    final auj = DateTime(2026, 11, 16, 9);
    final m = vide(auj);
    final p = PlagesNumeros.de(m)..obtenir = (nom, taille, minimum, {annee}) async => throw StateError('hors ligne');
    expect(PlagesNumeros.de(m).actif, isTrue);
    expect(p.reference('besoins', 'achats.besoins', const [], date: DateTime(2026, 11, 16)), startsWith('BEB-2026-PROV-'), reason: 'aucune plage : provisoire, jamais un numéro inventé');
    m.collection(PlagesCodes.collection).ajouterSansJournal({'id': 'PLG-besoins-101', 'nom': 'besoins', 'debut': 101, 'fin': 102, 'prochain': 101});
    expect(p.reference('besoins', 'achats.besoins', const [], date: DateTime(2026, 11, 16)), 'BEB-2026-0101');
    expect(p.reference('besoins', 'achats.besoins', const [], date: DateTime(2027, 1, 3)), 'BEB-2027-0102', reason: 'l’année est celle de la pièce');
    expect(p.reference('besoins', 'achats.besoins', const [], date: DateTime(2027, 1, 3)), startsWith('BEB-2027-PROV-'));
    p.obtenir = null;
    expect(p.reference('besoins', 'achats.besoins', [{'reference': 'BEB-2026-0007'}], date: DateTime(2026, 11, 16)), 'BEB-2026-0008', reason: 'sans service de plage : la règle historique');
  });

  test('une série à remise annuelle demande sa plage POUR L\u2019ANNÉE de la pièce ; une plage d\u2019une autre année ne sert jamais ; un refus de la mère ne crée aucune plage', () async {
    final m = vide(DateTime(2026, 11, 17, 9));
    final demandes = <(String, int?)>[];
    final p = PlagesNumeros.de(m)
      ..obtenir = (nom, taille, minimum, {annee}) async {
        demandes.add((nom, annee));
        if (annee == 2028) throw StateError('plage_chevauchement');
        return (1, 50);
      };
    expect(PlagesNumeros.anneeDemandee('achats.besoins', DateTime(2026, 11, 17)), 2026, reason: 'la série repart à 1 chaque année : l\u2019année est celle de la pièce');
    await p.recharger('besoins', 'achats.besoins', () => const [], date: DateTime(2026, 11, 17));
    expect(demandes, [('besoins', 2026)]);
    expect(m.collection(PlagesCodes.collection).toutes.single['annee'], 2026, reason: 'la plage porte son année');
    expect(p.reference('besoins', 'achats.besoins', const [], date: DateTime(2026, 11, 17)), 'BEB-2026-0001');
    // Une pièce de 2027 ne tire jamais dans la plage 2026 : provisoire, puis une plage de 2027 est demandée.
    expect(p.reference('besoins', 'achats.besoins', const [], date: DateTime(2027, 1, 4)), startsWith('BEB-2027-PROV-'));
    await p.recharger('besoins', 'achats.besoins', () => const [], date: DateTime(2027, 1, 4));
    expect(demandes.last, ('besoins', 2027));
    expect(p.reference('besoins', 'achats.besoins', const [], date: DateTime(2027, 1, 4)), 'BEB-2027-0001', reason: 'la série 2027 repart à 1');
    // La mère refuse (chevauchement, nommé chez elle) : le poste n\u2019invente rien et ne crée aucune plage.
    final avant = m.collection(PlagesCodes.collection).toutes.length;
    await p.recharger('besoins', 'achats.besoins', () => const [], date: DateTime(2028, 2, 1));
    expect(m.collection(PlagesCodes.collection).toutes.length, avant);
  });

  test('les plages de dossiers d\u2019avant les séries annuelles sont rattachées à l\u2019année de leurs codes déjà attribués ; sans code, elles restent sans année (dites) ; aucun code réécrit', () {
    final m = Magasin({
      PlagesCodes.collection: <M>[
        {'id': 'PLG-1000', 'debut': 1000, 'fin': 1049, 'prochain': 1011, 'statut': 'actif'},
        {'id': 'PLG-3000', 'debut': 3000, 'fin': 3049, 'prochain': 3000, 'statut': 'actif'},
        {'id': 'PLG2025-500', 'debut': 500, 'fin': 549, 'prochain': 510, 'annee': 2025, 'statut': 'actif'},
      ],
      'patients': <M>[
        {'id': 'P1', 'code': codePatient(1004, 2026), 'statut': 'actif'},
        {'id': 'P2', 'code': codePatient(1010, 2026), 'statut': 'actif'},
      ],
    });
    final p = PlagesCodes.de(m);
    expect(p.plagesDe(2026), isEmpty, reason: 'avant : la plage sans année n\u2019appartient à aucune série');
    final r = p.rattacherAnciennes(maintenant: DateTime(2026, 11, 17));
    expect((r.rattachees, r.sansAnnee), (1, 1));
    expect(p.plagesDe(2026).single['id'], 'PLG-1000');
    expect(p.plagesDe(2026).single['prochain'], 1011, reason: 'la plage garde son état : seule l\u2019année est posée');
    expect(m.collection(PlagesCodes.collection).parId('PLG-3000')!['annee'], isNull, reason: 'aucun code attribué : aucune année devinée');
    expect(m.collection(PlagesCodes.collection).parId('PLG2025-500')!['annee'], 2025, reason: 'une plage qui a une année n\u2019est jamais touchée');
    expect(m.collection('patients').toutes.map((x) => x['code']), [codePatient(1004, 2026), codePatient(1010, 2026)], reason: 'RG-01 : aucun code réécrit');
    final r2 = p.rattacherAnciennes(maintenant: DateTime(2026, 11, 17));
    expect((r2.rattachees, r2.sansAnnee), (0, 1), reason: 'idempotent');
  });

  casM14('« Numérotation des pièces » : chaque série, son format, son premier numéro de l’année ; « Modifier » ouvre une version datée', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-fiscalite');
    expect(find.text('Numérotation des pièces'), findsOneWidget);
    expect(find.text('FN-AAAA-NNNNN'), findsOneWidget, reason: 'la série fiscale des factures en tête, au format semé');
    expect(find.text('FN-2026-00001'), findsOneWidget, reason: 'le premier numéro de l’année de la date du poste');
    expect(find.text('À valider'), findsWidgets);
    final modifier = find.byKey(const Key('cfb:numerotation:modifier:caisse.avoirs'));
    expect(modifier, findsOneWidget, reason: 'l’administrateur détient le geste d’origine et édite l’écran');
    await toucherM14(t, modifier);
    await saisir(t, 'prefixe', 'AVR');
    await saisir(t, 'motif', 'Préfixe arrêté par la Direction');
    await toucherM14(t, find.byKey(const Key('cfb:numerotation:enregistrer')));
    final v = m.collection(colSeriesNumerotation).toutes.single;
    expect(v['prefixe'], 'AVR');
    expect(v['dateEffet'], '2026-10-30');
    expect(numeroFormate('caisse.avoirs', date: '2026-10-30', rang: 1), 'AVR-2026-0001');
    expect(numeroFormate('caisse.avoirs', date: '2026-10-29', rang: 1), 'AV-2026-0001', reason: 'les pièces antérieures gardent leur format');
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('AVR-AAAA-NNNN'), findsOneWidget, reason: 'l’écran suit la nouvelle version');
  });

  casM14('sans le droit d’éditer l’écran, la commande « Modifier » est ABSENTE (jamais grisée)', (t) async {
    final m = magasinM14();
    await ouvrirM14(t, m, 'cfg-fiscalite', role: 'da', donnees: donneesLectureSeule('da', 'cfg-fiscalite'));
    expect(find.text('Numérotation des pièces'), findsOneWidget);
    expect(find.byKey(const Key('cfb:numerotation:modifier:caisse.avoirs')), findsNothing);
    expect(find.textContaining('ce profil consulte'), findsOneWidget);
  });
}
