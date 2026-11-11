// Les données sensibles du patient : un droit par catégorie, porté par la matrice — jamais un nom de rôle dans le code.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// Une matrice factice : `voit[role]` = les écrans que le rôle voit. Les noms de rôle sont ceux du TEST, le code testé n'en connaît aucun.
DroitsSensibles droits(Map<String, Set<String>> voit, [List<Map<String, Object?>> fiches = const []]) =>
    DroitsSensibles(fiches: fiches, peutVoirEcran: (r, e) => voit[r]?.contains(e) ?? false);

const accueil = {'m1-patients'};
const soignant = {'m1-patients', 'm2-dossiers-consultation', 'm4-dossier-obstetrical', 'm3-admissions'};

void main() {
  final v = {'guichet': accueil, 'praticien': soignant};

  group('le défaut suit la matrice', () {
    test('Zone 1 : qui voit le répertoire lit identité, coordonnées, couverture ; Zone 2 : qui voit le dossier de consultation', () {
      final d = droits(v);
      for (final c in ['identite_detaillee', 'coordonnees', 'personne_a_prevenir', 'couverture_assurance', 'allergies_traitements']) {
        expect(d.peut('guichet', c), isTrue, reason: c);
      }
      for (final c in ['antecedents', 'groupe_serologies', 'diagnostic_pathologie', 'notes_consultation', 'donnees_obstetricales', 'hospitalisation_soins']) {
        expect(d.peut('guichet', c), isFalse, reason: c);
        expect(d.peut('praticien', c), isTrue, reason: c);
      }
    });
    test('une catégorie sans écran de référence reste ouverte (les habilitations métier des résultats s’appliquent en plus) ; une catégorie inconnue n’ouvre rien', () {
      final d = droits(v);
      expect(d.peut('guichet', 'resultats_analyses'), isTrue);
      expect(d.peut('guichet', 'inconnue'), isFalse);
      expect(d.peut('role_inconnu', 'coordonnees'), isFalse);
    });
    test('tout champ du référentiel appartient à UNE catégorie, et le code, le nom, le prénom et le sexe n’en ont aucune', () {
      final vus = <String>{};
      for (final c in categoriesSensibles) {
        for (final f in c.champs) {
          expect(vus.add(f), isTrue, reason: 'le champ « $f » est couvert deux fois');
          expect(categorieDuChamp(f)!.code, c.code);
        }
        if (c.ecranRef != null) expect(c.ecranRef, startsWith('m'), reason: 'un écran du manifeste');
      }
      for (final libre in ['code', 'nom', 'prenom', 'sexe', 'id']) {
        expect(categorieDuChamp(libre), isNull, reason: libre);
      }
    });
  });

  test('chaque écran de référence existe dans la matrice engendrée (un écran renommé ne ferme pas une catégorie en silence)', () {
    final parRole = ((jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map)['parRole'] as Map).cast<String, Object?>();
    final ecrans = {for (final r in parRole.values) ...(r as Map).keys.cast<String>()};
    for (final c in categoriesSensibles) {
      if (c.ecranRef != null) expect(ecrans, contains(c.ecranRef), reason: c.code);
    }
  });

  group('la décision de la clinique l’emporte, à chaud', () {
    test('accorder, retirer, revenir au défaut : lu à chaque appel, sans redémarrage', () {
      final fiches = <Map<String, Object?>>[];
      final d = DroitsSensibles(fiches: fiches, peutVoirEcran: (r, e) => v[r]?.contains(e) ?? false);
      expect(d.peut('guichet', 'antecedents'), isFalse);
      // Un NOUVEAU calcul sur la fiche décidée (la collection `rbac` change, le moteur est reconstruit à l'usage).
      var f = <String, Object?>{'role': 'guichet', 'donneesSensibles': {'antecedents': true}};
      var d2 = droits(v, [f]);
      expect(d2.peut('guichet', 'antecedents'), isTrue);
      expect(d2.origine('guichet', 'antecedents'), 'decide');
      expect(d2.origine('guichet', 'coordonnees'), 'defaut');
      f = {'role': 'guichet', 'donneesSensibles': {'antecedents': true, 'coordonnees': false}};
      d2 = droits(v, [f]);
      expect(d2.peut('guichet', 'coordonnees'), isFalse, reason: 'une décision retire aussi ce que le défaut donnait');
      expect(d2.peut('praticien', 'coordonnees'), isTrue, reason: 'la décision porte sur UN rôle');
      expect(d2.refusees('guichet').map((c) => c.code), contains('coordonnees'));
    });

    test('deux fiches du même rôle se fusionnent catégorie par catégorie', () {
      final d = droits(v, [
        {'role': 'guichet', 'donneesSensibles': {'antecedents': true}},
        {'role': 'guichet', 'donneesSensibles': {'coordonnees': false}},
      ]);
      expect(d.peut('guichet', 'antecedents'), isTrue);
      expect(d.peut('guichet', 'coordonnees'), isFalse);
    });

    test('la décision de droits porte les clés « sensible.* », se journalise lisiblement, et « null » revient au défaut', () {
      Map<String, Object?> dec(String id, String le, Map<String, Object?> ch) => drDecision(
          id: id, role: 'guichet', changements: ch, avant: const {}, motif: 'Revue', auteur: 'DAF', auteurRole: 'x', poste: 'P', decideLe: DateTime.parse(le));
      final diff = drDiff(null, {'donneesSensibles': {'antecedents': true}});
      expect(diff, {'sensible.antecedents': true});
      final r1 = drAppliquer(null, dec('D1', '2026-11-11T08:00:00Z', diff));
      expect(r1.issue, 'appliquee');
      expect((r1.fiche!['donneesSensibles'] as Map)['antecedents'], true);
      expect(r1.apresJournal.values.single, 'visible');
      expect(r1.avantJournal.keys.single, contains('Antécédents'));
      // Le même geste rejoué ne change rien ; une décision plus ANCIENNE n'écrase pas la plus récente.
      final r0 = drAppliquer(r1.fiche, dec('D0', '2026-11-11T07:00:00Z', {'sensible.antecedents': false}));
      expect(r0.issue, 'ecartee');
      // Revenir au défaut = la clé disparaît.
      final retour = drDiff(r1.fiche, {'donneesSensibles': {'antecedents': null}});
      expect(retour, {'sensible.antecedents': null});
      final r2 = drAppliquer(r1.fiche, dec('D2', '2026-11-11T09:00:00Z', retour));
      expect((r2.fiche!['donneesSensibles'] as Map), isEmpty);
      expect(droits(v, [r2.fiche!]).origine('guichet', 'antecedents'), 'defaut');
      // Une clé jamais décidée, remise au défaut, n'est pas une décision.
      expect(drDiff(null, {'donneesSensibles': {'antecedents': null}}), isEmpty);
    });
  });

  group('le masquage au niveau du champ', () {
    final p = {'id': 'P1', 'code': 'CNT/1/26', 'nom': 'EXEMPLE', 'prenom': 'Ruth', 'sexe': 'F', 'telephone': '97000001', 'quartier': 'Zongo', 'antecedents': ['HTA'], 'groupeSanguin': 'O+', 'diagnostic': 'Palu'};
    test('les champs des catégories refusées sont retirés, l’identification minimale reste, et les catégories masquées sont rendues', () {
      final masques = <String>{};
      final m = droits(v).masquer('guichet', p, masques: masques);
      expect(m.keys, containsAll(['id', 'code', 'nom', 'prenom', 'sexe', 'telephone', 'quartier']));
      expect(m.containsKey('antecedents'), isFalse);
      expect(m.containsKey('groupeSanguin'), isFalse);
      expect(m.containsKey('diagnostic'), isFalse);
      expect(masques, {'antecedents', 'groupe_serologies', 'diagnostic_pathologie'});
      expect(droits(v).masquer('praticien', p), p, reason: 'rien n’est retiré à qui a le droit');
    });
    test('la mention dit la catégorie — une seule phrase pour tout le logiciel', () {
      expect(mentionReservee('antecedents'), 'Information réservée — droit requis : Antécédents');
      expect(mentionReservee('groupe_serologies'), contains('Groupe sanguin et sérologies'));
    });
  });

  test('GARDE : aucun nom de rôle de la matrice n’est écrit dans le code du masquage', () {
    final roles = [for (final r in (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map)['roles'] as List) '${(r as Map)['id']}'];
    for (final f in ['lib/src/droits/donnees_sensibles.dart', '../../apps/poste/lib/kit/champ_sensible.dart']) {
      final code = File(f).readAsLinesSync().where((l) => !l.trimLeft().startsWith('///') && !l.trimLeft().startsWith('//')).join('\n');
      for (final r in roles) {
        expect(RegExp('[\'"]${RegExp.escape(r)}[\'"]').hasMatch(code), isFalse, reason: '$f nomme le rôle « $r »');
      }
    }
  });
}
