// LOT B : le DÉLAI MAXIMAL ENTRE DEUX MESURES, porté par la fiche du seuil. Vide par défaut, jamais bloquant ; au-delà, la variation n'est PAS évaluée et le verdict le dit ;
// l'âge de la mesure précédente se calcule toujours. Fonctions pures.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

final auj = DateTime(2026, 11, 13, 12);
final gb = <String, Object?>{'id': 'VAR-GB', 'code': 'GB', 'libelle': 'GB', 'type': 'numerique', 'unite': 'g_l', 'statut': 'actif', 'examen': 'NFS', 'examenLibelle': 'NFS'};

F seuil({num? abs = 1, num? rel, Object? delai, String etat = 'valide'}) => {
      'id': 'SEU1',
      'variableId': 'VAR-GB',
      'variableCode': 'GB',
      'version': 1,
      'etat': etat,
      'dateEffet': '2026-01-01',
      'ecartAbsolu': abs,
      'ecartRelatif': rel,
      'delaiMaxJours': delai,
      'retrait': false,
      'statut': 'actif',
    };

AlerteVariation? alerte(F s, {int? age, num avant = 5, num apres = 8}) =>
    alerteVariation(gb, variationEntre(gb, avant, apres), '2026-11-13', [s], aujourdhui: auj, ageJours: age);

void main() {
  group('alerteVariation et le délai', () {
    test('sans délai réglé (vide par défaut) : évalué quel que soit l’âge, aucun « non évalué »', () {
      final a = alerte(seuil(), age: 900)!;
      expect(a.alerte, isTrue);
      expect(a.nonEvalue, isNull);
      expect(a.delaiMaxJours, isNull);
      expect(a.ageInconnu, isFalse);
      expect(a.ageJours, 900, reason: 'l’âge reste porté même sans délai');
    });

    test('âge ÉGAL au délai : dans le délai, évalué ; au-delà d’un jour : NON ÉVALUÉ, et le verdict dit l’âge et le délai', () {
      final egal = alerte(seuil(delai: 30), age: 30)!;
      expect(egal.nonEvalue, isNull);
      expect(egal.alerte, isTrue);
      final dessus = alerte(seuil(delai: 30), age: 31)!;
      expect(dessus.alerte, isFalse, reason: 'non évalué n’est pas « pas d’alerte » : le drapeau le distingue');
      expect(dessus.nonEvalue, 'delai');
      expect(dessus.ageJours, 31);
      expect(dessus.delaiMaxJours, 30);
      expect(dessus.raisons, isEmpty);
      expect(texteNonEvalue(dessus), 'Variation non évaluée : mesure précédente trop ancienne (31 jours, délai réglé 30 jours)');
      expect(texteNonEvalue(alerte(seuil(delai: 1), age: 2)!), 'Variation non évaluée : mesure précédente trop ancienne (2 jours, délai réglé 1 jour)');
    });

    test('au-delà du délai, même une variation énorme ne donne PAS d’alerte ; dans le délai, la même variation alerte', () {
      expect(alerte(seuil(abs: 1, delai: 10), age: 11, avant: 5, apres: 500)!.alerte, isFalse);
      expect(alerte(seuil(abs: 1, delai: 10), age: 10, avant: 5, apres: 500)!.alerte, isTrue);
    });

    test('un âge incalculable n’est ni zéro ni dépassé : la variation s’évalue et le verdict porte « âge inconnu »', () {
      final a = alerte(seuil(delai: 30), age: null)!;
      expect(a.nonEvalue, isNull);
      expect(a.ageInconnu, isTrue);
      expect(a.alerte, isTrue);
      expect(alerte(seuil(), age: null)!.ageInconnu, isFalse, reason: 'sans délai, l’âge manquant ne veut rien dire');
    });

    test('le délai ne change pas la règle de la valeur précédente nulle : seuil relatif non évaluable, dit', () {
      final a = alerteVariation(gb, variationEntre(gb, 0, 9), '2026-11-13', [seuil(abs: null, rel: 20, delai: 30)], aujourdhui: auj, ageJours: 5)!;
      expect(a.nonEvaluable, isTrue);
      expect(a.nonEvalue, isNull);
    });
  });

  group('ageEntreMesures et son texte', () {
    F m(String d) => {'dateHeure': '${d}T09:00:00.000Z'};
    test('jours de calendrier entre deux dates, jamais négatif, null si une date manque ou est illisible', () {
      expect(ageEntreMesures(m('2026-10-01'), m('2026-11-13')), 43);
      expect(ageEntreMesures(m('2026-11-13'), m('2026-11-13')), 0);
      expect(ageEntreMesures(m('2026-11-14'), m('2026-11-13')), 0, reason: 'jamais négatif');
      expect(ageEntreMesures(null, m('2026-11-13')), isNull);
      expect(ageEntreMesures({'dateHeure': 'hier'}, m('2026-11-13')), isNull);
      expect(ageEntreMesures({'date': '2026-11-01'}, m('2026-11-13')), 12, reason: 'un relevé à `date` seule se lit aussi');
    });
    test('« mesure précédente il y a N jours » : toujours dit, au singulier et au pluriel', () {
      expect(texteAge(12), 'mesure précédente il y a 12 jours');
      expect(texteAge(1), 'mesure précédente il y a 1 jour');
      expect(texteAge(0), 'mesure précédente le même jour');
      expect(texteAge(null), isNull);
    });
  });

  group('la fiche de seuil : enregistrer, valider, versionner avec le délai', () {
    VerdictSeuil enreg({Object? abs = 1, Object? delai, bool retrait = false, List<F> base = const []}) => enregistrerSeuil(
        variable: gb,
        variableId: 'VAR-GB',
        seuilsActifs: base,
        droitEditer: true,
        profil: 'P',
        ecartAbsolu: abs,
        delaiMaxJours: delai,
        retrait: retrait,
        dateEffet: '2026-11-13',
        acteur: 'Dr B',
        role: 'laborantin',
        maintenant: auj);

    test('vide par défaut : le champ est absent de la fiche enregistrée, jamais zéro', () {
      final v = enreg();
      expect(v.ok, isTrue);
      expect(v.fiche!['delaiMaxJours'], isNull);
      expect(enreg(delai: '').fiche!['delaiMaxJours'], isNull);
    });

    test('un entier de jours d’au moins 1 s’enregistre avec le seuil ; 0, décimal, négatif, texte : DELAI_INVALIDE nommé', () {
      expect(enreg(delai: 30).fiche!['delaiMaxJours'], 30);
      expect(enreg(delai: '45').fiche!['delaiMaxJours'], 45);
      for (final mauvais in [0, 1.5, -3, 'abc']) {
        final v = enreg(delai: mauvais);
        if (mauvais == 'abc') {
          expect(v.ok, isTrue, reason: 'un texte illisible équivaut à vide (comme pour les seuils)');
        } else {
          expect(v.refus!.code, 'DELAI_INVALIDE', reason: '$mauvais');
        }
      }
    });

    test('un délai seul n’est pas un seuil (SEUIL_VIDE) ; un retrait ne porte aucun délai (RETRAIT_AVEC_VALEURS)', () {
      expect(enreg(abs: null, delai: 30).refus!.code, 'SEUIL_VIDE');
      final valide = [seuil()];
      final r = enreg(abs: null, delai: 30, retrait: true, base: valide);
      expect(r.refus!.code, 'RETRAIT_AVEC_VALEURS');
    });

    test('le délai se versionne et se valide AVEC le seuil : la version validée le porte, l’historique garde l’ancien', () {
      final enrg = enreg(delai: 30);
      final brouillon = {'id': 'SEU1', ...enrg.fiche!};
      final v = validerSeuil(
          variableId: 'VAR-GB', seuilsActifs: [brouillon], droitValider: true, fonctionHabilitee: true, profil: 'P', motif: 'Notice', acteur: 'Dr B', libelleRole: 'Biologiste médical', maintenant: auj);
      expect(v.ok, isTrue);
      final validee = {...brouillon, ...v.patch!};
      expect(validee['delaiMaxJours'], 30);
      expect(texteDelai(validee), 'délai entre deux mesures : 30 jours');
      expect(texteDelai({'delaiMaxJours': 1}), 'délai entre deux mesures : 1 jour');
      expect(texteDelai({}), '');
      // Une nouvelle version peut changer ou retirer le délai ; l'ancienne reste telle quelle.
      final v2 = enreg(delai: null, base: [validee]);
      expect(v2.creation, isTrue);
      expect(v2.fiche!['delaiMaxJours'], isNull);
      expect(validee['delaiMaxJours'], 30);
    });
  });

  test('le centre : seuilsEnAttente compte les versions Enregistrées (sans effet) seulement, jamais les validées', () {
    expect(seuilsEnAttente(const []).total, 0);
    final r = seuilsEnAttente([seuil(etat: 'enregistre'), {...seuil(etat: 'valide'), 'id': 'SEU2'}, {...seuil(etat: 'enregistre'), 'id': 'SEU3', 'variableId': 'VAR-HB'}]);
    expect(r.total, 2);
    expect(r.variables, ['VAR-GB', 'VAR-HB']);
  });
}
