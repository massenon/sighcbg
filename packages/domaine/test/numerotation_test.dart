// LOT 2 — LE RÉFÉRENTIEL DE NUMÉROTATION UNIQUE (16/11/2026). Trois preuves :
//  1. pour CHAQUE série semée, le numéro produit par la fabrique est, au caractère près, celui que le code écrivait avant le lot (table [ancien], écrite à
//     la main d'après le code retiré : un oracle indépendant de la fabrique) — aucune pièce existante ne change de numéro (RG-01) ;
//  2. l'année vient de la DATE DE LA PIÈCE : au 1ᵉʳ janvier 2027, une série annuelle repart à 1 sous « 2027 », une série sans remise continue son rang ;
//  3. une modification est une VERSION DATÉE sous geste réservé, qui ne s'applique qu'aux pièces à venir, et qu'un fileul dépose.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'aide_rangs.dart';
import 'package:test/test.dart';

/// L'ANCIEN format de chaque série, rang 12, pièce du 04/03/2026 : la chaîne que le code construisait EN DUR avant le lot (pour une série dérivée : le
/// préfixe suivi de la base indiquée). Une série ajoutée au référentiel doit ajouter sa ligne ici.
const Map<String, (String base, String attendu)> ancien = {
  'patients.constantes': ('', 'CST-00012'),
  'patients.documents': ('', 'GED-00012'),
  'patients.fiches-reference': ('', 'REF-00012'),
  'patients.contre-references': ('', 'CRF-00012'),
  'patients.factures-certificats': ('', 'FC-2026-00012'),
  'patients.factures-externes': ('', 'FE-2026-00012'),
  'consultation.dossiers': ('', 'DOS-00012'),
  'consultation.consultations': ('', 'C00012'),
  'agenda.rendezvous': ('', 'RDV-00012'), // préfixe PROPRE depuis le 17/11/2026 (il partageait « C » avec les consultations) ; l'ancien reste lu

  'agenda.appels': ('', 'A00012'),
  'consultation.ordonnances': ('', 'ORD-2026-00012'),
  'consultation.factures': ('', 'FP-2026-00012'),
  'soins.prescriptions': ('', 'PRS-00012'),
  'soins.administrations': ('', 'ADM-00012'),
  'imagerie.demandes': ('', 'IME-00012'),
  'imagerie.comptes-rendus': ('', 'IMG-0012'),
  'imagerie.factures': ('', 'FI-2026-00012'),
  'hospitalisation.admissions': ('', 'H00012'),
  'hospitalisation.sorties-contre-avis': ('', 'SAM0012'),
  'hospitalisation.observations': ('', 'OBS-2026-0012'),
  'hospitalisation.glasgow': ('', 'GCS-0012'),
  'hospitalisation.rapports': ('', 'RAP-0012'),
  'hospitalisation.transfusions': ('', 'TRF-0012'),
  'bloc.cpa': ('', 'CPA-2026-0012'),
  'bloc.cra': ('', 'CRA-2026-0012'),
  'bloc.cro': ('', 'CRO-0012'),
  'bloc.checklists': ('', 'CKL-0012'),
  'maternite.partogrammes': ('', 'PARTO-0012'),
  'maternite.accouchements': ('', 'ACC-0012'),
  'maternite.naissances': ('', 'NAI-0012'),
  'maternite.deces': ('', 'DEC-0012'),
  'maternite.cpn': ('', 'CPN-0012'),
  'maternite.cpon': ('', 'CPO-0012'),
  'maternite.planification': ('', 'PF-0012'),
  'maternite.sonu': ('', 'SONU-0012'),
  'maternite.ptme': ('', 'PTME-0012'),
  'maternite.soins-curatifs': ('', 'SCM-0012'),
  'maternite.comptes-rendus': ('', 'CRM-0012'),
  'labo.demandes': ('', 'LAB-00012'),
  'labo.reactifs': ('', 'REA-0012'), // idem (partageait « LAB- » avec les demandes d'analyses)
  'labo.donneurs': ('', 'DON-0012'),
  'stock.produits': ('', 'PRD-0012'),
  'stock.dispensations': ('', 'DISP-00012'),
  'stock.transferts': ('', 'TR-00012'),
  'stock.mouvements': ('', 'M000012'),
  'stock.pertes': ('', 'MVT-00012'),
  'stock.inventaires': ('', 'INV-0012'),
  'achats.besoins': ('', 'BEB-2026-0012'),
  'achats.commandes': ('', 'BC-2026-0012'),
  'achats.livraisons': ('', 'BL-00012'),
  'achats.pv-consommables': ('', 'PV-CON-2026-0012'),
  'achats.pv-reactifs': ('', 'PV-REA-2026-0012'),
  'caisse.factures': ('', 'FN-2026-00012'),
  'caisse.proformas': ('', 'PRO-2026-00012'),
  'caisse.factures-tiers': ('', 'FT-2026-00012'), // série créée le 17/11/2026 : la facture à une entreprise (tiers payeur)
  'caisse.avoirs': ('', 'AV-2026-0012'),
  'caisse.pieces': ('', 'CAI-2026-00012'),
  'caisse.remboursements': ('', 'RB-00012'),
  'caisse.versements': ('', 'VRS-2026-00012'),
  'caisse.tickets': ('', 'T-00012'),
  'assurances.relances': ('', 'REL-0012'),
  'assurances.factures-meres': ('', 'FM-2026-0012'),
  'assurances.reglements': ('', 'BQ-2026-00012'),
  'rh.conges': ('', 'CG-0012'),
  'rh.contrats': ('', 'CT-0012'),
  'rh.prestataires': ('', 'PE-0012'),
  'rh.evaluations': ('', 'EV-2026-0012'),
  'rh.evenements': ('', 'EVT-0012'),
  'rh.recus-participation': ('', 'REC-PART-0012'),
  'rh.securite-entretien': ('', 'SE-012'),
  'rh.ordres-mission': ('', 'OM-2026-0012'),
  'rh.badges': ('', 'BDG-00012-2026'),
  'paie.bulletins': ('', 'BUL-00012'), // idem (partageait « BP- » avec la référence d'un bulletin d'agent)
  'paie.bulletins-agent': ('MAT-007-03', 'BP-MAT-007-03'),
  'paie.prets': ('', 'PRT-0012'),
  'paie.heures-sup': ('', 'HS-0012'),
  'paie.avances': ('', 'AVS-0012'),
  'paie.pieces': ('', 'SAL-2026-00012'),
  'paie.piece-periode': ('2026-03', 'PAIE-2026-03'),
  'compta.depenses': ('', 'DEP-2026-0012'),
  'compta.cloture': ('', 'CL-2026-00012'),
  'compta.cloture-contrepassation': ('', 'CL-2026-C00012'),
  'compta.a-nouveaux': ('', 'AN-2026-00012'),
  'compta.a-nouveaux-contrepassation': ('', 'AN-2026-C00012'),
  'compta.archives-cloture': ('', 'ARC-2026-12'),
  'compta.attestations-aib': ('FF-2026-0003', 'AIB-FF-2026-0003'),
  'compta.attestations-aib-subie': ('FF-2026-0003', 'AIBS-FF-2026-0003'),
  'compta.budgets': ('', 'BG-2026-012'),
  'compta.immobilisations': ('', 'IM-012'),
  'adm.courriers-arrivee': ('', 'ARR-2026-0012'),
  'adm.courriers-depart': ('', 'COU-2026-0012'), // idem (partageait « DEP- » avec les dépenses)
  'adm.evenements': ('', 'EVE-0012'), // idem (partageait « EVT- » avec les événements du personnel)
  'adm.reunions': ('', 'RU-2026-012'),
  'adm.ambulance': ('', 'AM-2026-0012'),
  'adm.materiel': ('', 'EQ-012'),
  'qualite.enquetes': ('', 'ENQ-012'),
  'mdt.fiches-aptitude': ('', 'FA-0012/26'),
  'acces.support': ('', 'SUP-2026-0012'),
  'cfg.rappels': ('', 'RPL-00012'),
  'cfg.actes': ('', 'ACT-012'),
  'cfg.certificats': ('', 'CERT-2026-0012'),
  'fiscal.quittances': ('ITS-2026', 'QUIT-ITS-2026'),
  'import.lots': ('', 'IMP-2026-012'),
};

typedef F = Map<String, Object?>;

DroitsGestes gestes([List<F> fiches = const []]) => DroitsGestes(fiches: fiches);

void main() {
  setUp(Numerotation.reinitialiser);
  tearDown(Numerotation.reinitialiser);

  group('les semences reprennent EXACTEMENT les formats du code (aucune pièce ne change de numéro)', () {
    test('une preuve par série, et une série par preuve', () {
      expect({for (final s in Numerotation.semences) s.code}, ancien.keys.toSet(), reason: 'toute série semée doit prouver son ancien format, et inversement');
      expect(Numerotation.semences.map((s) => s.code).toSet().length, Numerotation.semences.length, reason: 'un code par série');
    });
    for (final e in ancien.entries) {
      test('${e.key} → ${e.value.$2}', () {
        final s = Numerotation.semence(e.key);
        expect(s.aValider, isTrue, reason: 'une semence est une proposition à valider');
        final n = s.genre == genreDerive ? numeroDerive(e.key, e.value.$1, date: '2026-03-04') : numeroFormate(e.key, date: '2026-03-04', rang: 12);
        expect(n, e.value.$2);
        expect(numeroDeLaSerie(e.key, n), isTrue, reason: 'le numéro produit est reconnu par sa série');
        if (s.genre == genreSequence) {
          expect(s.rangDe(n, an: 2026), 12, reason: 'le rang se relit');
          // Le numéro SUIVANT, lu sur les pièces déjà émises (archivées comprises : un rang ne se réutilise jamais).
          expect(numeroSuivant(e.key, date: '2026-03-04', existants: [n, {s.champ: n, 'statut': 'archive'}]), numeroFormate(e.key, date: '2026-03-04', rang: 13));
        }
      });
    }
  });

  group('l’année vient de la DATE DE LA PIÈCE', () {
    for (final s in seriesNumerotationSemence.where((s) => s.genre == genreSequence && s.avecAnnee)) {
      test('${s.code} : au 1ᵉʳ janvier 2027, ${s.remiseAnnuelle ? 'la série repart à 1 sous 2027' : 'le rang continue, l’année suit la pièce'}', () {
        final n2026 = numeroFormate(s.code, date: '2026-12-31', rang: 41);
        final suivant = numeroSuivant(s.code, date: '2027-01-01', existants: [n2026]);
        expect(suivant, numeroFormate(s.code, date: '2027-01-01', rang: s.remiseAnnuelle ? 1 : 42));
        expect(suivant, contains(s.annee == anneeCourte ? '27' : '2027'));
        expect(suivant, isNot(contains('2026')));
        // Une pièce de 2026 saisie en janvier 2027 garde SON année (la date de la pièce, pas l'horloge du poste).
        expect(numeroSuivant(s.code, date: '2026-12-30', existants: [n2026]), numeroFormate(s.code, date: '2026-12-30', rang: 42));
      });
    }
    test('l’année d’une série dérivée ou sans millésime n’apparaît jamais', () {
      expect(numeroSuivant('achats.livraisons', date: '2031-01-01', existants: ['BL-00041']), 'BL-00042');
    });
    test('une année explicite l’emporte sur la date (budget d’exercice, clôture)', () {
      expect(numeroSuivant('compta.budgets', date: '2026-11-16', annee: 2027, existants: ['BG-2026-004']), 'BG-2027-001');
    });
  });

  group('la fabrique relit les numéros comme le code les relisait', () {
    test('rang sur les chiffres de tête (volets -A/-B des factures), référence provisoire sans rang', () {
      expect(rangMaximal('caisse.factures', date: '2026-05-01', existants: [{'numero': 'FN-2026-00237-A'}, {'numero': 'FN-2026-00237-B'}, {'numero': 'FN-2026-00040'}]), 237);
      expect(rangMaximal('achats.besoins', date: '2026-05-01', existants: ['BEB-2026-PROV-ABC', 'BEB-2026-0004']), 4);
      expect(numeroDeLaSerie('achats.besoins', 'BEB-2026-PROV-ABC'), isTrue);
    });
    test('la clôture et sa contre-passation ne se confondent pas, mais le journal partage son rang', () {
      final journal = [
        {'numero': 'CL-2026-00003'},
        {'numero': 'CL-2026-C00004'},
      ];
      expect(rangMaximal('compta.cloture', date: '2026-12-31', existants: journal), 3);
      expect(rangMaximal('compta.cloture-contrepassation', date: '2026-12-31', existants: journal), 4);
      expect(cpcRangPiece(journal, 'CL', 2026), 5);
    });
    test('le champ du numéro est celui de la série (badge, reçu, matricule)', () {
      expect(numeroSuivant('rh.badges', date: '2026-02-01', existants: [{'numero': 'BDG-00007-2026'}, {'numero': 'BDG-00009-2025'}]), 'BDG-00008-2026');
      expect(numeroSuivant('rh.recus-participation', existants: [{'recu': 'REC-PART-0003'}]), 'REC-PART-0004');
      expect(numeroSuivant('mdt.fiches-aptitude', date: DateTime(2026, 6, 1), existants: ['FA-0007/26', 'FA-0011/25']), 'FA-0008/26');
    });
    test('les règles du domaine rendent toujours l’ancien format', () {
      expect(referenceAvoir('2026-05-02', [{'reference': 'AV-2026-0004'}]), 'AV-2026-0005');
      expect(prefixeSerieFacture(proforma: false, dateFacture: '2026-12-31'), 'FN-2026-');
      expect(prefixeSerieFacture(proforma: true, dateFacture: '2027-01-01'), 'PRO-2027-');
      expect(cpaReferenceDepense('2026-04-10', [{'reference': 'DEP-2026-0009'}]), 'DEP-2026-0010');
      expect(cpcReferenceArchive(2026, 1), 'ARC-2026-01');
      expect(cfaNumeroCertificat(piecesAuRang('cfg.certificats', 6), date: '2026-01-05'), 'CERT-2026-0007');
      expect(admReferenceCourrier('arrivee', '2027-02-01', [{'reference': 'ARR-2026-0040'}]), 'ARR-2027-0001');
      expect(rhaReferenceMission('2026-08-01', [{'reference': 'OM-2026-0002'}]), 'OM-2026-0003');
      expect(accReferenceSupport(2026, ['SUP-2026-0001']), 'SUP-2026-0002');
      expect(paiIdentifiantPiece('2026-03'), 'PAIE-2026-03');
    });
    test('une série inconnue est une erreur de programmation, jamais un numéro inventé', () {
      expect(() => numeroSuivant('serie.inexistante', existants: const []), throwsA(isA<SerieInconnue>()));
    });
  });

  group('une modification est une VERSION DATÉE qui ne s’applique qu’aux pièces à venir', () {
    final maintenant = DateTime(2026, 11, 16, 10);
    ({RefusValidation? refus, bool sansEffet, Map<String, Object?>? version}) controler(Map<String, Object?> v,
            {String date = '2027-01-01', String role = 'da', List<F> fiches = const [], String? motif = 'Format arrêté par la Direction'}) =>
        serieControler(code: 'achats.besoins', valeurs: v, dateEffet: date, role: role, acteur: 'DAF Test', gestes: gestes(), fiches: fiches, maintenant: maintenant, motif: motif);

    test('refus NOMMÉS : geste, date passée, motif, format, version existante', () {
      expect(controler({'prefixe': 'EB'}, role: 'caissier').refus!.code, 'NUMEROTATION_RESERVEE');
      expect(controler({'prefixe': 'EB'}, role: 'admin').refus, isNull, reason: 'origine proposée : administrateur et DAF');
      expect(controler({'prefixe': 'EB'}, date: '2026-11-15').refus!.code, 'NUMEROTATION_RETROACTIVE');
      expect(controler({'prefixe': 'EB'}, motif: '  ').refus!.code, 'MOTIF_REQUIS');
      expect(controler({'prefixe': 'e b'}).refus!.code, 'FORMAT_INVALIDE');
      expect(controler({'largeur': 0}).refus!.code, 'FORMAT_INVALIDE');
      expect(controler({'annee': anneeAucune}).refus!.motif, contains('remise à 1 annuelle'));
      final v = controler({'prefixe': 'EB'}).version!;
      expect(controler({'prefixe': 'EBX'}, fiches: [v]).refus!.code, 'VERSION_EXISTANTE');
    });

    test('arrêter une semence sans la changer lève « à valider » ; refaire la même version est sans effet', () {
      final r = controler(const {}, date: '2026-11-16');
      expect(r.refus, isNull);
      expect(r.version!['aValider'], false);
      expect(r.version!['arreteeSansChangement'], true);
      expect(controler(const {}, date: '2026-12-01', fiches: [r.version!]).sansEffet, isTrue);
    });

    test('la version s’applique à partir de sa date ; les pièces déjà émises gardent leur numéro', () {
      final v = controler({'prefixe': 'EB', 'largeur': 5}).version!;
      Numerotation.appliquer([v]);
      final avant = ['BEB-2026-0041'];
      expect(numeroSuivant('achats.besoins', date: '2026-12-31', existants: avant), 'BEB-2026-0042', reason: 'avant la date d’effet : l’ancien format');
      expect(numeroSuivant('achats.besoins', date: '2027-01-02', existants: avant), 'EB-2027-00001', reason: 'nouvelle série, nouveau préfixe');
      expect(numeroDeLaSerie('achats.besoins', 'BEB-2026-0041'), isTrue, reason: 'un numéro de l’ancienne version reste reconnu');
      expect(Numerotation.serie('achats.besoins', date: '2027-03-01').aValider, isFalse);
      // Une version ARCHIVÉE ne compte plus (RG-14).
      Numerotation.appliquer([{...v, 'statut': 'archive'}]);
      expect(numeroSuivant('achats.besoins', date: '2027-01-02', existants: avant), 'BEB-2027-0001');
    });

    test('un fileul DÉPOSE ; la mère rejoue sous le rôle de l’auteur, contrôles refaits', () {
      var n = 0;
      final depot = serieDeposer(
          code: 'achats.commandes',
          valeurs: {'prefixe': 'CMD'},
          dateEffet: '2027-01-01',
          role: 'da',
          acteur: 'DAF Test',
          poste: 'F1',
          maintenant: maintenant,
          gestes: gestes(),
          fiches: const [],
          depots: const [],
          nouvelId: () => 'VDP-${++n}',
          motif: 'Lettres de la Direction');
      expect(depot.ok, isTrue);
      expect(depot.fiche!['genre'], valGenreNumerotation);
      // Déposé deux fois à l'identique : pas de doublon.
      final bis = serieDeposer(
          code: 'achats.commandes',
          valeurs: {'prefixe': 'CMD'},
          dateEffet: '2027-01-01',
          role: 'da',
          acteur: 'DAF Test',
          poste: 'F1',
          maintenant: maintenant,
          gestes: gestes(),
          fiches: const [],
          depots: [depot.fiche!],
          nouvelId: () => 'VDP-${++n}',
          motif: 'Lettres de la Direction');
      expect(bis.dejaDepose, isTrue);
      final a = serieAppliquerDepot(depot.fiche!, gestes: gestes(), fiches: const [], maintenant: maintenant)!;
      expect(a.etat, valDepotAppliquee);
      expect(a.version!['prefixe'], 'CMD');
      // La mère a retiré le geste à la DAF entre-temps : refus nommé, rien n'est écrit.
      final retire = serieAppliquerDepot(depot.fiche!,
          gestes: gestes([
            {'id': 'R', 'role': 'da', 'statut': 'actif', 'droitsGestes': {gesteNumerotationModifier: false}}
          ]),
          fiches: const [],
          maintenant: maintenant)!;
      expect(retire.etat, valDepotRefusee);
      expect(retire.code, 'NUMEROTATION_RESERVEE');
      // Arrivé APRÈS sa date d'effet : jamais appliqué en arrière.
      expect(serieAppliquerDepot(depot.fiche!, gestes: gestes(), fiches: const [], maintenant: DateTime(2027, 2, 1))!.code, 'NUMEROTATION_RETROACTIVE');
    });

    test('l’alerte d’une décision en retard va à ceux qui détiennent le geste', () {
      final d = DecisionEnAttente(genre: genreDecisionValidation, sousGenre: valGenreNumerotation, famille: 'achats.commandes', id: 'X', libelle: 'x', par: 'DAF', role: 'da', depuis: null);
      expect(destinatairesAlerteDecision(d, gesteCircuit: 'c', gestePrix: 'p'), contains('geste:$gesteNumerotationModifier'));
    });
  });
}
