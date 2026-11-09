// Les SONDES D'INVARIANTS du sous-lot RH et paie du jeu de démonstration Baguidi : 24 bulletins (août et septembre validés par la Direction, octobre en
// brouillon), séparation des tâches, net = brut moins retenues, cotisations aux taux, écritures de paie équilibrées et en brouillon (RG-10), aucune
// évaluation NS 131, primes absentes quand la grille n'en donne pas, congés dont un en cours, avance en cours de retenue.
// Le générateur est lancé EN MÉMOIRE (aucune écriture sur le disque).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import '../tool/generer_jeu_baguidi.dart';
import '../tool/jeu_baguidi/contexte.dart';

typedef F = Map<String, Object?>;

List<F> lire(Map<String, String> j, String nom) => [for (final f in jsonDecode(j['$nom.json']!) as List) (f as Map).cast<String, Object?>()];
num n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);

void main() {
  final jeu = construireJeu();
  List<F> c(String nom) => lire(jeu, nom);
  final bulletins = c('bulletins');
  final personnel = c('personnel');

  List<F> du(String periode) => [for (final b in bulletins) if (b['periode'] == periode) b];

  test('24 bulletins : trois mois pour les huit agents salariés, l\'administrateur système n\'est pas salarié', () {
    expect(bulletins.length, 24);
    expect({for (final b in bulletins) b['periode']}, {'Août 2026', 'Septembre 2026', 'Octobre 2026'});
    for (final p in ['Août 2026', 'Septembre 2026', 'Octobre 2026']) {
      expect(du(p).map((b) => b['employeId']).toSet(), {for (final a in personnel) a['id']}, reason: p);
      expect(du(p).length, 8);
    }
    expect(c('utilisateurs').any((u) => u['role'] == 'admin'), isTrue);
    expect(bulletins.any((b) => b['employeId'] == null || '${b['employe']}'.contains('Administrateur')), isFalse);
    expect(bulletins.map((b) => b['reference']).toSet().length, 24);
  });

  test('août et septembre validés par la Direction, octobre en brouillon (à valider, sans validateur)', () {
    for (final p in ['Août 2026', 'Septembre 2026']) {
      expect(du(p).every((b) => b['statutBulletin'] == 'valide' && b['validePar'] != null && b['dateValidation'] != null && b['ecritureNumero'] != null), isTrue, reason: p);
    }
    expect({for (final b in du('Août 2026')) b['validePar']}, {'BAGUIDI Rafiou'});
    expect({for (final b in du('Septembre 2026')) b['validePar']}, {'SOKOU Peace'});
    expect(du('Octobre 2026').every((b) => b['statutBulletin'] == 'a_valider' && b['validePar'] == null && b['ecritureNumero'] == null), isTrue);
  });

  test('séparation des tâches : jamais l\'auteur et le valideur confondus (par identifiant de compte et par nom), le valideur est de la Direction', () {
    final comptes = {for (final u in c('utilisateurs')) u['id']: u};
    for (final b in bulletins.where((b) => b['statutBulletin'] == 'valide')) {
      expect(b['genereeParId'], isNot(b['valideParId']));
      expect(b['genereePar'], isNot(b['validePar']));
      expect(comptes[b['genereeParId']]!['role'], 'rh');
      expect(comptes[b['valideParId']]!['role'], 'direction');
      expect(d.paiControleSeparation([b], '${b['validePar']}', validateurId: '${b['valideParId']}'), isNull);
    }
  });

  test('net = brut moins sanction moins retenues ; total des retenues = leurs composantes ; aucune sanction', () {
    for (final b in bulletins) {
      final retenues = n(b['cnssOuvriere']) + n(b['its']) + n(b['ortb']) + n(b['avances']) + n(b['participations']) + n(b['prets']);
      expect(n(b['totalRetenues']), retenues, reason: '${b['reference']}');
      expect(n(b['net']), n(b['brut']) - n(b['sanction']) - retenues, reason: '${b['reference']}');
      expect(n(b['sanction']), 0);
      expect(n(b['pctSanction']), 0);
      expect(n(b['net']), greaterThan(0));
      expect(b['salaireProvisoire'], true);
    }
  });

  test('cotisations : CNSS 3,6 % ouvrière et 16,4 % patronale, VPS 4 %, ITS du barème, ORTB nul hors mars et juin', () {
    for (final b in bulletins) {
      final base = n(b['brut']) - n(b['sanction']);
      expect((n(b['cnssOuvriere']) - base * 0.036).abs() <= 0.5, isTrue, reason: '${b['reference']}');
      expect((n(b['cnssPatronale']) - base * 0.164).abs() <= 0.5, isTrue, reason: '${b['reference']}');
      expect((n(b['vps']) - base * 0.04).abs() <= 0.5, isTrue, reason: '${b['reference']}');
      expect(n(b['its']), d.paiCalculIts(base - n(b['cnssOuvriere'])), reason: '${b['reference']}');
      expect(n(b['ortb']), 0);
    }
  });

  test('écritures de paie : une pièce par lot validé, équilibrée (RG-10), en brouillon, journal SAL ; rien pour octobre', () {
    final sal = [for (final e in c('ecritures')) if (e['journal'] == 'SAL') e];
    expect({for (final e in sal) e['pieceId']}, {'PAIE-Août 2026', 'PAIE-Septembre 2026'});
    expect(sal.every((e) => e['statut'] == 'brouillon'), isTrue);
    for (final numero in {for (final e in sal) e['numero']}) {
      final lignes = sal.where((e) => e['numero'] == numero);
      expect(lignes.fold<num>(0, (a, e) => a + n(e['debit'])), lignes.fold<num>(0, (a, e) => a + n(e['credit'])), reason: '$numero');
      expect(lignes.every((e) => (n(e['debit']) > 0) != (n(e['credit']) > 0)), isTrue);
    }
    // La pièce reprend les bulletins du lot : débit rémunérations = brut du lot.
    for (final (periode, piece) in [('Août 2026', 'PAIE-Août 2026'), ('Septembre 2026', 'PAIE-Septembre 2026')]) {
      final remu = sal.firstWhere((e) => e['pieceId'] == piece && e['compte'] == '661100');
      expect(n(remu['debit']), du(periode).fold<num>(0, (a, b) => a + n(b['brut'])));
    }
    expect(sal.any((e) => '${e['pieceId']}'.contains('Octobre')), isFalse);
  });

  test('aucune évaluation NS 131, aucune participation, aucun badge, aucun événement', () {
    for (final nom in ['evaluations', 'participations', 'badges', 'evenements']) {
      expect(c(nom), isEmpty, reason: nom);
    }
  });

  test('primes NS 132 : aucune quand la grille n\'en donne pas à la fonction ; l\'infirmier reçoit celle du barème (bloc fixe), sans garde ni permanence', () {
    final grille = c('grillePrimes');
    for (final b in bulletins) {
      final fonction = '${b['fonction']}';
      final donnees = [for (final g in grille) if (n((g['montants'] as Map)[fonction]) > 0) '${g['primeId']}'];
      final lignes = [for (final l in (b['lignesPrimes'] as List)) '${(l as Map)['id']}'];
      if (donnees.isEmpty) {
        expect(lignes, isEmpty, reason: '$fonction');
        expect(n(b['totalPrimes']), 0);
      } else {
        expect(lignes.toSet().difference(donnees.toSet()), isEmpty);
      }
    }
    final inf = bulletins.where((b) => b['fonction'] == 'infirmier');
    expect(inf.every((b) => [for (final l in (b['lignesPrimes'] as List)) (l as Map)['id']].toString() == '[bloc_fixe]'), isTrue);
  });

  test('contrats, fiches de poste, congés : CDI à la date d\'embauche d\'attente, six postes à compléter, trois congés dont un en cours au 07/11', () {
    final contrats = c('contrats');
    expect(contrats.length, 8);
    for (final k in contrats) {
      final p = personnel.firstWhere((x) => x['id'] == k['employeId']);
      expect(k['nature'], 'CDI');
      expect(k['dateDebut'], p['dateEmbauche']);
      expect(k['salaire'], p['salaireBase']);
    }
    final fiches = c('fichesPoste');
    expect([for (final f in fiches) f['intitule']],
        ['Direction Générale', 'Comptabilité', 'Ressources humaines', 'Médecine générale', 'Soins infirmiers', 'Administration système']);
    expect(fiches.every((f) => f['redigee'] == false && (f['missions'] as List).isEmpty && '${f['resume']}'.contains('à compléter par la Direction')), isTrue);
    final conges = c('conges');
    expect(conges.length, 3);
    expect(conges.where((x) => d.rhaCongeEnCours(x, Contexte.maintenant)).length, 1);
    expect(conges.every((x) => x['statutConge'] == 'valide'), isTrue);
  });

  test('planning et présences : jours ouvrés, retards signalés, un absent justifié, rien un jour de congé, heures supplémentaires et avance en cours', () {
    final pres = c('presences');
    expect(pres.where((x) => x['etat'] == 'retard').length, 6);
    final absents = pres.where((x) => x['etat'] == 'absent').toList();
    expect(absents.length, 1);
    expect(absents.single['justifie'], true);
    expect(pres.every((x) => DateTime.parse('${x['date']}').weekday <= DateTime.friday), isTrue);
    expect(pres.every((x) => '${x['date']}'.compareTo('2026-08-01') >= 0 && '${x['date']}'.compareTo('2026-11-07') <= 0), isTrue);
    expect(pres.map((x) => '${x['employeId']}|${x['date']}').toSet().length, pres.length);
    expect(c('planning').where((p) => p['type'] == 'garde').every((p) => p['fonction'] == 'medecin'), isTrue);
    final hs = c('heuresSup');
    expect(hs.length, 2);
    expect(hs.every((h) => h['valide'] == true && n(h['montant']) == n(h['heures']) * n(h['tauxHoraire'])), isTrue);
    final avances = c('avances');
    expect(avances.length, 1);
    expect(avances.single['statutAvance'], 'en_cours');
    expect(n(avances.single['rembourse']), lessThan(n(avances.single['montant'])));
    expect(n(avances.single['rembourse']), n(avances.single['mensualite']) * 1);
  });
}
