// LE CALENDRIER FISCAL CORRIGÉ À LA RACINE (Baguidi, 10/11/2026) : ce que l'audit de la maquette de la réplique d'origine avait trouvé, vérifié sur le moteur Dart.
// Aucun vecteur ici : les vecteurs de la maquette portent les défauts (jour plafonné à 28, période de janvier = « janvier »), les tests ci-dessous disent le
// comportement attendu, avec une arithmétique de date indépendante du moteur.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

CfbObligation _obl(String code, String periodicite, int jour, {int? mois}) =>
    CfbObligation(code, 'Essai $code', periodicite, jour, mois, 100, null, 'note', 'essai');

Map<String, Object?> _fiche(CfbObligation o, [String id = 'X']) => cfbFicheDepuisObligation(o, id: id);

void main() {
  final auj = DateTime(2026, 11, 10);

  group('le dernier jour réel du mois', () {
    test('février 28 ou 29, avril 30, janvier 31, décembre 31', () {
      expect(cfbDernierJour(2027, 2), 28);
      expect(cfbDernierJour(2028, 2), 29);
      expect(cfbDernierJour(2100, 2), 28, reason: 'siècle non bissextile');
      expect(cfbDernierJour(2026, 4), 30);
      expect(cfbDernierJour(2026, 1), 31);
      expect(cfbDernierJour(2026, 12), 31);
    });

    test('un jour trop grand tombe au dernier jour, il ne déborde jamais sur le mois suivant', () {
      expect(cfbDateReelle(2027, 2, 31), DateTime(2027, 2, 28));
      expect(cfbDateReelle(2028, 2, 31), DateTime(2028, 2, 29));
      expect(cfbDateReelle(2026, 4, 31), DateTime(2026, 4, 30));
      expect(cfbDateReelle(2026, 1, 31), DateTime(2026, 1, 31));
      expect(cfbDateReelle(2026, 13, 10), DateTime(2027, 1, 10), reason: 'mois 13 = janvier suivant');
      expect(DateTime(2027, 2, 31), DateTime(2027, 3, 3), reason: 'le constructeur, lui, déborde : c\'est le défaut que la fonction évite');
    });
  });

  group('l\'exercice engendré : le jour n\'est plus plafonné à 28', () {
    final l2027 = cfbGenEcheances(2027, obligationsFixes: cfbSemenceObligations(), aujourdhui: auj, sansReglement: true);
    String theorique(String code) => l2027.firstWhere((e) => e['code'] == code)['echeanceTheorique'] as String;

    test('les annuelles au 30 ou 31 tombent le 30 avril, le 31 janvier, le 30 mars, le 30 juin', () {
      expect(theorique('PATENTE-DECL'), '2027-01-31');
      for (final c in ['IS-SOLDE', 'ETATS-FIN', 'PATENTE-2', 'TVM']) {
        expect(theorique(c), '2027-04-30', reason: c);
      }
      expect(theorique('ORTB-RADIO'), '2027-03-30');
      expect(theorique('ORTB-TELE'), '2027-06-30');
    });

    test('« fin de février » : le 28 en 2027, le 29 en 2028 (CCIB-DECL au jour 31)', () {
      expect(theorique('CCIB-DECL'), '2027-02-28');
      final l2028 = cfbGenEcheances(2028, obligationsFixes: cfbSemenceObligations(), aujourdhui: auj, sansReglement: true);
      expect(l2028.firstWhere((e) => e['code'] == 'CCIB-DECL')['echeanceTheorique'], '2028-02-29');
    });

    test('le report se fait au jour ouvrable SUIVANT, jamais en arrière', () {
      final p = l2027.firstWhere((e) => e['code'] == 'PATENTE-DECL');
      expect(p['echeanceTheorique'], '2027-01-31', reason: 'un dimanche');
      expect(p['echeance'], '2027-02-01');
      expect(p['reportee'], true);
      final t = l2027.firstWhere((e) => e['code'] == 'TVM');
      expect(t['echeance'], '2027-04-30', reason: 'un vendredi : rien à reporter');
      expect(t['reportee'], false);
      for (final e in l2027) {
        expect(('${e['echeance']}').compareTo('${e['echeanceTheorique']}') >= 0, isTrue, reason: '${e['code']} ne s\'avance jamais');
        final wd = DateTime.parse('${e['echeance']}').weekday;
        expect(wd == DateTime.saturday || wd == DateTime.sunday, isFalse, reason: '${e['code']} tombe un jour ouvrable');
      }
    });

    test('une obligation MENSUELLE au jour 31 ne déborde pas : douze échéances, une par mois, février au 28', () {
      final l = cfbGenEcheances(2027, obligationsFixes: [_fiche(_obl('FIN-MOIS', 'mensuelle', 31))], aujourdhui: auj, sansReglement: true);
      expect(l.length, 12);
      expect([for (final e in l) (e['echeanceTheorique'] as String).substring(0, 7)].toSet().length, 12, reason: 'aucun mois sauté ni doublé');
      expect(l[1]['echeanceTheorique'], '2027-02-28');
      expect(l[3]['echeanceTheorique'], '2027-04-30');
      expect(l[0]['echeanceTheorique'], '2027-01-31');
    });
  });

  group('la période d\'une obligation mensuelle', () {
    test('le mois qui précède l\'échéance : janvier = décembre de l\'année d\'avant, et douze libellés DISTINCTS', () {
      final l = cfbGenEcheances(2027, obligationsFixes: [_fiche(_obl('ITS', 'mensuelle', 10))], aujourdhui: auj, sansReglement: true);
      expect(l.first['periode'], 'décembre 2026');
      expect(l[1]['periode'], 'janvier 2027');
      expect(l[2]['periode'], 'février 2027');
      expect(l.last['periode'], 'novembre 2027');
      expect({for (final e in l) e['periode']}.length, 12, reason: 'le défaut : janvier et février portaient le même libellé');
    });

    test('une annuelle porte l\'exercice', () {
      final l = cfbGenEcheances(2027, obligationsFixes: [_fiche(_obl('TVM', 'annuelle', 30, mois: 3))], aujourdhui: auj, sansReglement: true);
      expect(l.single['periode'], '2027');
    });
  });

  group('l\'exercice suivant se génère depuis les versions en vigueur', () {
    test('75 échéances pour 2027, toutes dans l\'exercice, aucune réputée payée, et la version datée à venir de l\'ITS s\'y applique', () {
      final obligations = cfbSemenceObligations();
      final its = obligations.firstWhere((o) => o['code'] == 'ITS');
      final r = cfbModifierObligation(obligations,
          id: '${its['id']}', valeurs: {'jour': 12}, dateEffet: '2027-03-01', motif: 'Essai', acteur: 'Direction', maintenant: auj, aujourdhui: auj);
      expect(r.ok, isTrue, reason: '${r.refus?.motif}');
      final apres = [for (final o in obligations) o['id'] == its['id'] ? r.fiche! : o];
      final historique = [r.historique!];
      final l = cfbGenEcheances(2027, obligations: apres, historique: historique, aujourdhui: auj, sansReglement: true);
      expect(l.length, 75);
      expect(l.every((e) => e['paye'] == false), isTrue);
      expect(l.every((e) => (e['echeanceTheorique'] as String).startsWith('2027-')), isTrue);
      final itsL = l.where((e) => e['code'] == 'ITS').toList();
      expect(itsL[1]['echeanceTheorique'], '2027-02-10', reason: 'février : version d\'origine (jour 10)');
      expect(itsL[2]['echeanceTheorique'], '2027-03-12', reason: 'mars : la version datée du 01/03 s\'applique');
    });
  });

  group('une version à venir est VISIBLE', () {
    final obligations = cfbSemenceObligations();
    final its = obligations.firstWhere((o) => o['code'] == 'ITS');
    final r = cfbModifierObligation(obligations,
        id: '${its['id']}', valeurs: {'jour': 12}, dateEffet: '2026-12-01', motif: 'Essai', acteur: 'Direction', maintenant: auj, aujourdhui: auj);
    final apres = [for (final o in obligations) o['id'] == its['id'] ? r.fiche! : o];
    final historique = [r.historique!];

    test('avant la date d\'effet : la lecture du jour montre l\'ancienne, la vue « à venir » montre la nouvelle et ce qu\'elle remplace', () {
      expect(cfbObligationsALaDate(apres, historique, auj).firstWhere((o) => o['code'] == 'ITS')['jour'], 10);
      final v = cfbVersionsAVenir(apres, historique, auj);
      expect(v.length, 1);
      expect(v.single.code, 'ITS');
      expect(v.single.dateEffet, '2026-12-01');
      expect(v.single.aVenir['jour'], 12);
      expect(v.single.enVigueur!['jour'], 10);
    });

    test('le jour dit et après : plus de version à venir, la nouvelle est en vigueur', () {
      expect(cfbVersionsAVenir(apres, historique, DateTime(2026, 12, 1)), isEmpty);
      expect(cfbVersionsAVenir(apres, historique, DateTime(2027, 1, 5)), isEmpty);
      expect(cfbObligationsALaDate(apres, historique, DateTime(2026, 12, 1)).firstWhere((o) => o['code'] == 'ITS')['jour'], 12);
    });

    test('aucune version à venir sur la semence', () {
      expect(cfbVersionsAVenir(obligations, const [], auj), isEmpty);
    });
  });

  group('les seuils d\'état et le montant de la CCIB sont des paramètres', () {
    Map<String, Object?> e(int joursAvant, {String? declaration}) => {
          'echeance': isoJour(DateTime(auj.year, auj.month, auj.day + joursAvant)),
          'paye': false,
          'declaration': declaration,
        };

    test('défaut 10 et 30 : l\'état d\'avant, à l\'identique', () {
      expect(cpcCalculerEtat(e(10), auj), 'a_payer');
      expect(cpcCalculerEtat(e(11, declaration: 'x'), auj), 'declaration');
      expect(cpcCalculerEtat(e(31, declaration: 'x'), auj), 'a_venir');
      expect(cpcCalculerEtat(e(-1), auj), 'en_retard');
    });

    test('seuils réglés à 7 et 45 : la frontière bouge', () {
      const s = CpcSeuilsEcheance(aPayerJours: 7, declarationJours: 45);
      expect(cpcCalculerEtat(e(8), auj, seuils: s), 'a_venir');
      expect(cpcCalculerEtat(e(7), auj, seuils: s), 'a_payer');
      expect(cpcCalculerEtat(e(40, declaration: 'x'), auj, seuils: s), 'declaration');
      expect(cpcCalculerEtat(e(46, declaration: 'x'), auj, seuils: s), 'a_venir');
    });

    test('la barre et l\'alerte disent le délai réglé, plus « dix jours » en dur', () {
      const s = CpcSeuilsEcheance(aPayerJours: 7);
      final lignes = cpcLignesEcheances([{...e(5), 'code': 'ITS', 'libelle': 'ITS'}], auj, seuils: s);
      expect(cpcBarreEcheances(lignes, seuils: s).single.titre, '1 paiement(s) à effectuer sous 7 jours');
      expect(cpcAlerteOuverture(lignes, seuils: s)!.message, '1 paiement(s) sous 7 jours');
      final defaut = cpcLignesEcheances([{...e(5), 'code': 'ITS', 'libelle': 'ITS'}], auj);
      expect(cpcBarreEcheances(defaut).single.titre, '1 paiement(s) à effectuer sous dix jours');
    });

    test('un délai absurde est ramené : négatif → défaut, déclaration < paiement → égale au paiement', () {
      final s = CpcSeuilsEcheance.depuis(-3, 5);
      expect(s.aPayerJours, 10);
      expect(s.declarationJours, 10);
      expect(CpcSeuilsEcheance.depuis(null, null).declarationJours, 30);
    });

    test('les trois paramètres sont déclarés, entiers, de la famille fiscale (jamais envoyés au téléphone), à leur défaut', () {
      for (final (cle, defaut) in [('fiscal.delaiAPayerJours', 10), ('fiscal.delaiDeclarationJours', 30), ('fiscal.ccibMontant', cfbCcibTotal)]) {
        final d = definitionDeParametre(cle)!;
        expect(d.type, TypeParametre.entier, reason: cle);
        expect(d.defaut, defaut, reason: cle);
        expect(d.famille, 'fiscal');
        expect(d.mobile, isFalse);
        expect(parFamillesJamaisMobile.contains(d.famille), isTrue);
        expect(libellesFamillesParametres.containsKey(d.famille), isTrue);
      }
      expect(cfbCcibTotal, 300000);
    });

    test('la CCIB réglée change l\'indicateur et ses deux tranches ; le défaut garde le texte d\'avant', () {
      final l = cfbEcheances(auj);
      final defaut = cfbKpisFiscalite(l).last;
      final regle = cfbKpisFiscalite(l, ccib: 400000).last;
      expect(defaut.valeur, isNot(regle.valeur));
      expect(defaut.indice, 'Deux tranches de 150 000 F');
      expect(regle.indice, contains('200'));
    });
  });
}
