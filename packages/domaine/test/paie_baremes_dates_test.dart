// LOT 1 DE L'INVENTAIRE DES VALEURS EN DUR (docs/architecture/INVENTAIRE-VALEURS-EN-DUR.md, défauts graves 4, 5 et 9) : la paie et le fiscal en BARÈMES DATÉS.
//
// Pour CHAQUE barème, trois preuves :
//  (a) la valeur SEMÉE est l'ancienne constante (recopiée ici en littéral : c'est le seul endroit où elle peut encore s'écrire) — aucun bulletin ne change ;
//  (b) une version nouvelle, datée, ne s'applique qu'À PARTIR de sa date ;
//  (c) un bulletin passé garde le taux de sa date (il le PORTE, et son mois recalculé reste identique).
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;

void main() {
  final maintenant = DateTime.utc(2026, 11, 16, 9);
  final auj = DateTime(2026, 11, 16, 10);
  final agent = <String, Object?>{
    'id': 'E1',
    'matricule': '001',
    'nomComplet': 'AGENT Test',
    'fonction': 'medecin', // aucune prime NS 132 : brut = salaire de base
    'salaireBase': 200000,
    'dateEmbauche': '2025-09-01',
    'statut': 'actif'
  };

  /// La version datée d'une clé, posée comme le poste la pose (règle commune des paramètres).
  M version(String cle, Object? valeur, String dateEffet, List<M> deja) {
    final r = Parametres.proposer(
        definition: definitionDeParametre(cle),
        versions: [for (final f in deja) if (f['cle'] == cle) Parametre.fromJson(f)],
        usages: const [],
        valeur: valeur,
        dateEffet: dateEffet,
        auteur: 'COMPTABLE Test',
        motif: 'Essai');
    expect(r.ok, isTrue, reason: '${r.refus}');
    return {'id': r.valeur!.id, 'statut': 'actif', ...r.valeur!.toJson()};
  }

  PaiCalcul calc(int annee, int mois, List<M> parametres) => paiCalculer(agent, annee, mois, PaiEntrees(parametres: parametres), auj);

  group('les définitions : quatre paramètres datés, famille réservée, réglage dédié, jamais au téléphone', () {
    test('déclarés avec pour défaut la semence, sous le geste fiscal_confirmer', () {
      for (final cle in paiClesBaremes) {
        final d = definitionDeParametre(cle)!;
        expect(d.famille, paiFamilleBaremes, reason: cle);
        expect(d.geste, gesteFiscalConfirmer, reason: cle);
        expect(d.mobile, isFalse, reason: cle);
        expect(Parametres.autoriseMobile(Parametres.semer(d).toJson()), isFalse, reason: cle);
        expect(Parametres.autoriseMobile({...Parametres.semer(d).toJson(), 'mobile': true}), isFalse, reason: '$cle : la famille seule ferme le téléphone');
        expect(d.source, isNotNull, reason: cle);
      }
      expect(parFamillesJamaisMobile, contains(paiFamilleBaremes));
      expect(parFamillesReglageDedie, contains(paiFamilleBaremes), reason: 'le panneau générique contournerait le motif et le geste');
      expect(libellesFamillesParametres[paiFamilleBaremes], isNotEmpty);
    });
  });

  group('CNSS part ouvrière (3,6 %)', () {
    test('(a) la semence est l’ancienne constante', () {
      expect(paiCnssOuvriereSemence, 3.6);
      expect(definitionDeParametre(paiCleCnssOuvriere)!.defaut, 3.6);
      expect(PaiTauxPaie.aLaDate(const [], '2026-10-01').cnssOuvriere, 3.6);
      expect(calc(2026, 9, const []).cnssOuvriere, arrondiJs(200000 * 3.6 / 100));
    });
    test('(b) une version au 01/01/2027 ne s’applique qu’à partir de janvier', () {
      final p = [version(paiCleCnssOuvriere, 4.0, '2027-01-01', const [])];
      expect(PaiTauxPaie.aLaDate(p, '2026-12-31').cnssOuvriere, 3.6);
      expect(PaiTauxPaie.aLaDate(p, '2027-01-01').cnssOuvriere, 4.0);
      expect(calc(2026, 11, p).cnssOuvriere, 7200, reason: 'décembre 2026 : 3,6 %');
      expect(calc(2027, 0, p).cnssOuvriere, 8000, reason: 'janvier 2027 : 4 %');
      expect(calc(2027, 0, p).taux.version(paiCleCnssOuvriere).dateEffet, '2027-01-01');
    });
    test('(c) un bulletin passé PORTE son taux et son mois recalculé est identique', () {
      final b = paiBulletinDe(calc(2026, 11, const []), 'BP-00001');
      final p = [version(paiCleCnssOuvriere, 4.0, '2027-01-01', const [])];
      expect(paiTauxDuBulletin(b, p).cnssOuvriere, 3.6);
      expect((b['tauxPaie'] as Map)['cnssOuvriere'], 3.6);
      expect(calc(2026, 11, p).cnssOuvriere, b['cnssOuvriere']);
      // Un bulletin d'avant le lot (sans `tauxPaie`) relit le taux de SA date, pas celui du jour.
      final ancien = {...b}..remove('tauxPaie');
      final p2 = [version(paiCleCnssOuvriere, 4.0, '2026-12-15', const [])];
      expect(paiTauxDuBulletin(ancien, p2).cnssOuvriere, 3.6, reason: 'décembre se lit au 01/12');
    });
  });

  group('CNSS part patronale (16,4 %)', () {
    test('(a) la semence est l’ancienne constante', () {
      expect(paiCnssPatronaleSemence, 16.4);
      expect(definitionDeParametre(paiCleCnssPatronale)!.defaut, 16.4);
      expect(calc(2026, 9, const []).cnssPatronale, arrondiJs(200000 * 16.4 / 100));
    });
    test('(b) datée, elle ne touche que les mois qui suivent', () {
      final p = [version(paiCleCnssPatronale, 17.0, '2027-03-01', const [])];
      expect(calc(2027, 1, p).cnssPatronale, 32800);
      expect(calc(2027, 2, p).cnssPatronale, 34000);
      expect(calc(2027, 2, p).coutEmployeur, 200000 + 34000 + 8000);
    });
    test('(c) le bulletin de février garde 16,4 %', () {
      final b = paiBulletinDe(calc(2027, 1, const []), 'BP-00002');
      final p = [version(paiCleCnssPatronale, 17.0, '2027-03-01', const [])];
      expect(paiTauxDuBulletin(b, p).cnssPatronale, 16.4);
      expect(calc(2027, 1, p).cnssPatronale, b['cnssPatronale']);
    });
  });

  group('VPS (4 %)', () {
    test('(a) la semence est l’ancienne constante', () {
      expect(paiVpsTauxSemence, 4);
      expect(definitionDeParametre(paiCleVps)!.defaut, 4);
      expect(calc(2026, 9, const []).vps, 8000);
    });
    test('(b) datée, elle ne s’applique qu’après sa date', () {
      final p = [version(paiCleVps, 5.0, '2027-01-01', const [])];
      expect(calc(2026, 11, p).vps, 8000);
      expect(calc(2027, 0, p).vps, 10000);
    });
    test('(c) un bulletin passé garde le sien', () {
      final b = paiBulletinDe(calc(2026, 11, const []), 'BP-00003');
      final p = [version(paiCleVps, 5.0, '2027-01-01', const [])];
      expect(paiTauxDuBulletin(b, p).vps, 4);
      expect(calc(2026, 11, p).vps, b['vps']);
    });
  });

  group('barème de l’ITS', () {
    const ancien = [PaiTranche(0, 60000, 0), PaiTranche(60001, 150000, 10), PaiTranche(150001, 250000, 15), PaiTranche(250001, 500000, 19), PaiTranche(500001, null, 30)];
    test('(a) la semence est l’ancien barème, tranche par tranche', () {
      expect(PaiTauxPaie.semence.baremeIts, ancien);
      expect(paiBaremeItsDepuisJson(definitionDeParametre(paiCleBaremeIts)!.defaut), ancien);
      expect(paiCalculIts(600000), 9000 + 15000 + 47500 + 30000);
      expect(paiControlerBaremeIts(ancien), isNull);
    });
    test('(b) un barème daté du 01/01/2027 ne s’applique qu’à partir de janvier', () {
      final nouveau = [const PaiTranche(0, 80000, 0), const PaiTranche(80001, null, 10)];
      final p = [version(paiCleBaremeIts, paiBaremeItsVersJson(nouveau), '2027-01-01', const [])];
      expect(PaiTauxPaie.aLaDate(p, '2026-12-01').baremeIts, ancien);
      expect(PaiTauxPaie.aLaDate(p, '2027-01-01').baremeIts, nouveau);
      final dec = calc(2026, 11, p), jan = calc(2027, 0, p);
      expect(dec.its, paiCalculIts(dec.brutApresSanction - dec.cnssOuvriere, ancien));
      expect(jan.its, paiCalculItsSur(jan.brutApresSanction - jan.cnssOuvriere, nouveau));
      expect(jan.its, isNot(dec.its));
    });
    test('(c) un bulletin passé porte SON barème', () {
      final b = paiBulletinDe(calc(2026, 11, const []), 'BP-00004');
      final p = [version(paiCleBaremeIts, paiBaremeItsVersJson([const PaiTranche(0, null, 5)]), '2027-01-01', const [])];
      expect(paiTauxDuBulletin(b, p).baremeIts, ancien);
      expect(calc(2026, 11, p).its, b['its']);
    });
    test('la saisie d’un barème : relue, contrôlée, refusée en nommant la tranche', () {
      final lu = paiBaremeItsDepuisSaisie(paiBaremeItsVersSaisie(ancien));
      expect(lu.bareme, ancien);
      expect(paiBaremeItsDepuisSaisie('0 60 000 0\n60 001 et plus 10 %').bareme, [const PaiTranche(0, 60000, 0), const PaiTranche(60001, null, 10)]);
      expect(paiBaremeItsDepuisSaisie('0 60000 0\n60002 et plus 10').refus, contains('Tranche 2'));
      expect(paiBaremeItsDepuisSaisie('0 60000 0\n60001 70000 10').refus, contains('dernière tranche est sans plafond'));
      expect(paiBaremeItsDepuisSaisie('10 et plus 10').refus, contains('commence à 0'));
      expect(paiBaremeItsDepuisSaisie('0 et plus 120').refus, contains('entre 0 et 100'));
    });
  });

  group('la confirmation fiscale agit sur ces valeurs (geste fiscal_confirmer)', () {
    List<M> bulletins(int annee, int mois) => [paiBulletinDe(calc(annee, mois, const []), 'BP-1')];
    ({FcoRefus? refus, List<M> versions, M? confirmation}) poser(String objet, Map<String, Object?> v, String effet,
            {String role = 'comptable', String? motif = 'Notification de la CNSS', List<M> parametres = const [], List<M> existantes = const [], List<M> bull = const [], String? texte, bool fileul = false}) =>
        fcoPoserVersion(
            objet: objet,
            valeurs: v,
            dateEffet: effet,
            motif: motif,
            texte: texte,
            role: role,
            auteur: 'COMPTABLE Test',
            maintenant: maintenant,
            parametres: parametres,
            usages: const [],
            existantes: existantes,
            bulletins: bull,
            fileul: fileul);

    test('une nouvelle version de la CNSS pose ses DEUX parts et la confirmation qui les atteste', () {
      final r = poser(fcoObjetCnss, {paiCleCnssOuvriere: 4, paiCleCnssPatronale: 16.4}, '2027-01-01');
      expect(r.refus, isNull);
      expect([for (final v in r.versions) v['cle']], [paiCleCnssOuvriere, paiCleCnssPatronale]);
      expect([for (final v in r.versions) v['dateEffet']], ['2027-01-01', '2027-01-01']);
      expect(r.confirmation!['valeur'], {'tauxOuvrier': 4.0, 'tauxPatronal': 16.4, 'plafond': null});
      expect(r.confirmation!['motif'], 'Notification de la CNSS');
      final t = PaiTauxPaie.aLaDate(r.versions, '2027-01-01');
      expect([t.cnssOuvriere, t.cnssPatronale], [4.0, 16.4]);
      expect(fcoConfirmationDeLaValeur([r.confirmation!], fcoObjetCnss, fcoCibleCnssTaux, DateTime(2027, 2, 1), fcoValeursCnss(t)), isNotNull);
    });

    test('refus nommés : geste non détenu, fileul, motif, date, valeur identique, taux hors bornes, mois déjà généré', () {
      expect(poser(fcoObjetVps, {paiCleVps: 5}, '2027-01-01', role: 'direction').refus!.code, 'CONFIRMATION_RESERVEE');
      expect(poser(fcoObjetVps, {paiCleVps: 5}, '2027-01-01', fileul: true).refus!.code, 'FILEUL_LECTURE_SEULE');
      expect(poser(fcoObjetVps, {paiCleVps: 5}, '2027-01-01', motif: ' ').refus!.code, 'MOTIF_OBLIGATOIRE');
      expect(poser(fcoObjetVps, {paiCleVps: 5}, '').refus!.code, 'DATE_EFFET_REQUISE');
      expect(poser(fcoObjetVps, {paiCleVps: 4}, '2027-01-01').refus!.code, 'VALEUR_IDENTIQUE');
      expect(poser(fcoObjetVps, {paiCleVps: 0}, '2027-01-01').refus!.code, 'VALEUR_INVALIDE');
      expect(poser(fcoObjetBaremeIts, {paiCleBaremeIts: [const PaiTranche(5, null, 10)]}, '2027-01-01').refus!.code, 'VALEUR_INVALIDE');
      // Décembre 2026 est généré : une version au 01/12 le contredirait, au 02/12 elle ne vaut qu'à partir de janvier.
      final r = poser(fcoObjetVps, {paiCleVps: 5}, '2026-12-01', bull: bulletins(2026, 11));
      expect(r.refus!.code, 'PAIE_DEJA_GENEREE');
      expect(r.versions, isEmpty, reason: 'rien n’est écrit à moitié');
      expect(poser(fcoObjetVps, {paiCleVps: 5}, '2026-12-02', bull: bulletins(2026, 11)).refus, isNull);
    });

    test('« Confirmer » atteste la valeur EN VIGUEUR à la date d’effet ; une valeur changée depuis n’est plus confirmée', () {
      final c = fcoConfirmerTaux(
          objet: fcoObjetVps, parametres: const [], dateEffet: '2026-11-01', motif: 'Avis de l’expert-comptable', role: 'comptable', auteur: 'X', maintenant: maintenant, existantes: const []);
      expect(c.refus, isNull);
      expect(c.fiche!['valeur'], {'taux': 4.0});
      final p = [version(paiCleVps, 5.0, '2027-01-01', const [])];
      expect(fcoConfirmationDeLaValeur([c.fiche!], fcoObjetVps, fcoCibleVpsTaux, DateTime(2026, 12, 1), fcoValeursVps(PaiTauxPaie.aLaDate(p, '2026-12-01'))), isNotNull);
      expect(fcoConfirmationDeLaValeur([c.fiche!], fcoObjetVps, fcoCibleVpsTaux, DateTime(2027, 1, 1), fcoValeursVps(PaiTauxPaie.aLaDate(p, '2027-01-01'))), isNull,
          reason: 'la version du 01/01/2027 n’a pas été confirmée');
    });

    test('le barème de l’ITS reste « à confirmer » tant qu’aucune confirmation ne cite un texte', () {
      final t = PaiTauxPaie.semence;
      expect(fcoBaremeItsAConfirmer(const [], auj, t), isTrue);
      final sans = fcoConfirmerTaux(
          objet: fcoObjetBaremeIts, parametres: const [], dateEffet: '2026-11-01', motif: 'Vu', role: 'comptable', auteur: 'X', maintenant: maintenant, existantes: const []);
      expect(sans.refus!.code, 'TEXTE_REQUIS');
      final avec = fcoConfirmerTaux(
          objet: fcoObjetBaremeIts,
          parametres: const [],
          dateEffet: '2026-11-01',
          motif: 'Vérifié avec le cabinet',
          texte: 'Code général des impôts, art. 179',
          role: 'comptable',
          auteur: 'X',
          maintenant: maintenant,
          existantes: const []);
      expect(avec.refus, isNull);
      expect(avec.fiche!['texte'], 'Code général des impôts, art. 179');
      expect(fcoBaremeItsAConfirmer([avec.fiche!], auj, t), isFalse);
      // Une version nouvelle posée sans texte reste à confirmer à sa date.
      final r = poser(fcoObjetBaremeIts, {paiCleBaremeIts: [const PaiTranche(0, null, 10)]}, '2027-01-01', existantes: [avec.fiche!]);
      expect(r.refus, isNull);
      expect(fcoBaremeItsAConfirmer([avec.fiche!, r.confirmation!], DateTime(2027, 1, 2), PaiTauxPaie.aLaDate(r.versions, '2027-01-02')), isTrue);
    });
  });

  group('ORTB : une seule source, la fiche ORTB-PARAMETRES, lue par la paie ET le pilotage à la même date', () {
    M fiche(num seuil, num radio, num tele, String effet) => {
          'id': 'OBL-ORTB',
          'type': 'parametres',
          'code': paiCodeParametresOrtb,
          'statut': 'actif',
          'dateEffet': effet,
          'seuilTele': seuil,
          'redevances': [
            {...paiRedevances[0].fiche, 'montant': radio},
            {...paiRedevances[1].fiche, 'montant': tele, 'seuilMin': seuil + 1},
          ],
        };
    test('(a) la semence du pilotage est celle de la paie : 1 000 F pour tous, 4 000 F au-delà de 60 000 F', () {
      expect(pilCoutAgent({'salaireBase': 60000}, const [], '', '').ortbAnnuel, 1000);
      expect(pilCoutAgent({'salaireBase': 60001}, const [], '', '').ortbAnnuel, 4000);
      expect(paiCalculOrtb(60001, 0).montantAnnuel, 4000);
    });
    test('(b) une fiche datée relevée : le pilotage la lit comme la paie, à partir de sa date seulement', () {
      final obligations = [fiche(80000, 1500, 3000, '2027-01-01')];
      final avant = PaiParametresOrtb.aLaDate(DateTime(2026, 12, 1), obligations: obligations, historique: const []);
      final apres = PaiParametresOrtb.aLaDate(DateTime(2027, 1, 1), obligations: obligations, historique: const []);
      final a = {'salaireBase': 70000};
      expect(pilCoutAgent(a, const [], '', '', ortb: avant).ortbAnnuel, 4000);
      expect(pilCoutAgent(a, const [], '', '', ortb: apres).ortbAnnuel, 1500, reason: '70 000 F sous le nouveau seuil : radio seule, au nouveau montant');
      expect(pilCoutAgent(a, const [], '', '', ortb: apres).ortbAnnuel, paiCalculOrtb(70000, 0, parametres: apres).montantAnnuel, reason: 'même source, même montant');
      expect(pilCoutAgent(a, const [], '', '', ortb: apres).vue.kpis.last.indice, contains('Radio seule'));
    });
    test('(c) le taux de CNSS du pilotage suit la même version datée que la paie', () {
      final p = [version(paiCleCnssPatronale, 17.0, '2027-01-01', const [])];
      final r = pilCoutAgent({'salaireBase': 100000}, const [], '', '', taux: PaiTauxPaie.aLaDate(p, '2027-01-01'));
      expect(r.patronale, 17000);
      expect(pilCoutAgent({'salaireBase': 100000}, const [], '', '', taux: PaiTauxPaie.aLaDate(p, '2026-12-01')).patronale, 16400);
    });
  });

  group('la grille NS 132 : UNE seule graine', () {
    test('la paie lit la graine de grillePrimes (rhbPrimesOrigine) : mêmes primes, même ordre, mêmes montants', () {
      expect([for (final p in paiPrimesNs132) p.id], [for (final p in rhbPrimesOrigine) p.id]);
      for (final p in rhbPrimesOrigine) {
        for (final f in p.montants.keys) {
          expect(paiMontantOrigine(p.id, f), rhbMontantOrigine(p.id, f), reason: '${p.id}/$f');
        }
      }
      expect(paiMontantOrigine('garde', 'infirmier'), 1500, reason: '(a) la graine garde ses montants');
    });
  });

  group('participation standard aux événements (1 000 F)', () {
    test('(a) la semence est l’ancienne constante', () {
      expect(rhcMontantStandardSemence, 1000);
      expect(definitionDeParametre(rhcCleMontantStandard)!.defaut, 1000);
      expect(participationStandardA(const [], '2026-11-16'), 1000);
      expect(rhcMontantParAgent(''), 1000);
    });
    test('(b) une version datée ne vaut qu’à partir de sa date', () {
      final p = [version(rhcCleMontantStandard, 1500, '2027-01-01', const [])];
      expect(participationStandardA(p, '2026-12-31'), 1000);
      expect(participationStandardA(p, '2027-01-01'), 1500);
      expect(rhcMontantParAgent('', null, participationStandardA(p, '2027-01-01')), 1500);
    });
    test('(c) un événement déjà créé garde le montant qu’il porte', () {
      expect(rhcMontantParAgent('0', 1000, 1500), 1000);
    });
  });

  group('tarif d’une course d’ambulance sans montant (proposition à valider)', () {
    test('(a) les semences sont les anciennes constantes : 5 000 F + 500 F/km', () {
      expect([admForfaitAmbulanceSemence, admPrixKmAmbulanceSemence], [5000, 500]);
      expect(tarifAmbulanceA(const [], '2026-11-16'), (forfait: 5000, parKm: 500));
      expect(admTarifAmbulance('', 20), 15000);
      expect(definitionDeParametre(admCleForfaitAmbulance)!.source, contains('à valider'));
    });
    test('(b) une version datée ne vaut qu’à partir de sa date', () {
      final p = [version(admClePrixKmAmbulance, 600, '2027-01-01', const [])];
      final t = tarifAmbulanceA(p, '2027-01-01');
      expect(tarifAmbulanceA(p, '2026-12-31').parKm, 500);
      expect(admTarifAmbulance('', 20, forfait: t.forfait, parKm: t.parKm), 17000);
    });
    test('(c) une course saisie avec son montant le garde', () {
      expect(admTarifAmbulance('9000', 5, forfait: 7000, parKm: 600), 9000);
    });
  });

  group('prime d’ancienneté (2 % par année, dès 2 ans) : UNE règle pour la paie et la fiche d’évaluation', () {
    final ancien = {...agent, 'dateEmbauche': '2020-01-01'}; // 6 ans pleins au 16/11/2026
    PaiCalcul c(int annee, int mois, List<M> p) => paiCalculer(ancien, annee, mois, PaiEntrees(parametres: p), auj);
    test('(a) les semences sont les anciennes constantes : le bulletin et la fiche NS 131 donnent le même montant', () {
      expect([paiAncienneteTauxSemence, paiAncienneteSeuilAnsSemence], [2, 2]);
      expect(definitionDeParametre(paiCleAncienneteTaux)!.defaut, 2);
      expect(definitionDeParametre(paiCleAncienneteSeuil)!.defaut, 2);
      expect(c(2026, 9, const []).primeAnciennete, arrondiJs(200000 * 0.02 * 6));
      expect(paiPrimeAnciennete(200000, 1), 0, reason: 'sous 2 ans, pas de prime');
      final s = rhbSolde(salaireBrut: 200000, prelevementPct: 0, gardes: 0, permanences: 0, montantGarde: 0, montantPermanence: 0, montantAccueil: 0, ans: 6);
      expect(s.primeAnciennete, c(2026, 9, const []).primeAnciennete);
    });
    test('(b) un taux et un seuil datés du 01/01/2027 ne valent qu’à partir de janvier', () {
      final p = [version(paiCleAncienneteTaux, 3.0, '2027-01-01', const []), version(paiCleAncienneteSeuil, 7, '2027-01-01', const [])];
      expect(c(2026, 11, p).primeAnciennete, 24000);
      expect(c(2027, 0, p).primeAnciennete, 0, reason: '6 ans d’ancienneté, sous le nouveau seuil de 7 ans');
      final p2 = [version(paiCleAncienneteTaux, 3.0, '2027-01-01', const [])];
      expect(c(2027, 0, p2).primeAnciennete, 36000);
      final s = rhbSolde(
          salaireBrut: 200000, prelevementPct: 0, gardes: 0, permanences: 0, montantGarde: 0, montantPermanence: 0, montantAccueil: 0, ans: 6, taux: PaiTauxPaie.aLaDate(p2, '2027-01-01'));
      expect(s.primeAnciennete, 36000, reason: 'la fiche d’évaluation lit la même règle, à sa date');
    });
    test('(c) un bulletin passé garde son taux', () {
      final b = paiBulletinDe(c(2026, 11, const []), 'BP-00005');
      final p = [version(paiCleAncienneteTaux, 3.0, '2027-01-01', const [])];
      expect(paiTauxDuBulletin(b, p).ancienneteTaux, 2);
      expect(c(2026, 11, p).primeAnciennete, b['primeAnciennete']);
    });
    test('une nouvelle version passe par la confirmation fiscale (seuil entier contrôlé)', () {
      final r = fcoPoserVersion(
          objet: fcoObjetAnciennete,
          valeurs: {paiCleAncienneteTaux: 2.5, paiCleAncienneteSeuil: 3},
          dateEffet: '2027-01-01',
          motif: 'Convention collective',
          role: 'comptable',
          auteur: 'X',
          maintenant: maintenant,
          parametres: const [],
          usages: const [],
          existantes: const [],
          bulletins: const []);
      expect(r.refus, isNull);
      expect(r.confirmation!['valeur'], {'taux': 2.5, 'seuilAns': 3});
      final t = PaiTauxPaie.aLaDate(r.versions, '2027-01-01');
      expect([t.ancienneteTaux, t.ancienneteSeuilAns], [2.5, 3]);
      final k = fcoPoserVersion(
          objet: fcoObjetAnciennete,
          valeurs: {paiCleAncienneteTaux: 2.5, paiCleAncienneteSeuil: 2.5},
          dateEffet: '2027-01-01',
          motif: 'x',
          role: 'comptable',
          auteur: 'X',
          maintenant: maintenant,
          parametres: const [],
          usages: const [],
          existantes: const [],
          bulletins: const []);
      expect(k.refus!.code, 'VALEUR_INVALIDE');
    });
  });

  group('TVA du régime normal (18 %) : le régime se choisit à la configuration fiscale, son taux est daté', () {
    test('(a) la semence est l’ancienne valeur ; le régime exonéré reste à 0', () {
      expect(paiTvaNormalSemence, 18);
      expect(definitionDeParametre(paiCleTvaNormal)!.defaut, 18);
      final n = const ParamFiscal(regimeTva: 'normal').aLaDate(const [], '2026-11-16');
      expect([n.tauxTva, n.libelleTva, n.regime.libelle], [18, 'TVA 18 %', 'Taux normal 18 %']);
      expect(const ParamFiscal().aLaDate(const [], '2026-11-16').tauxTva, 0);
    });
    test('(b) une version au 01/01/2027 ne vaut qu’à partir de sa date', () {
      final p = [version(paiCleTvaNormal, 19.0, '2027-01-01', const [])];
      const n = ParamFiscal(regimeTva: 'normal');
      expect(n.aLaDate(p, '2026-12-31').tauxTva, 18);
      expect(n.aLaDate(p, '2027-01-01').tauxTva, 19);
      expect(n.aLaDate(p, '2027-01-01').libelleTva, 'TVA 19 %');
      expect(const ParamFiscal().aLaDate(p, '2027-01-01').tauxTva, 0, reason: 'le régime exonéré choisi ne bouge pas');
    });
    test('(c) une pièce se décompose au taux de SA date', () {
      final p = [version(paiCleTvaNormal, 19.0, '2027-01-01', const [])];
      const n = ParamFiscal(regimeTva: 'normal');
      expect(decomposer(1180, n.aLaDate(p, '2026-12-31')).ht, 1000);
      expect(decomposer(1190, n.aLaDate(p, '2027-01-02')).ht, 1000);
    });
  });
}
