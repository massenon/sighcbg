// Les décisions de droits : la plus récente l'emporte clé par clé, jamais d'écrasement silencieux, l'ordre d'arrivée ne change rien.
import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> droit(bool v, [bool e = false, bool a = false]) => {'voir': v, 'editer': e, 'annuler': a};

Map<String, Object?> dec(String id, String le, Map<String, Object?> ch,
        {Map<String, Object?> avant = const {}, String motif = 'Revue', String auteur = 'DAF', String role = 'da'}) =>
    drDecision(
        id: id,
        role: 'sage_femme',
        changements: ch,
        avant: avant,
        motif: motif,
        auteur: auteur,
        auteurRole: role,
        poste: 'P1',
        decideLe: DateTime.parse(le));

Map<String, Object?> graine() => {
      'id': 'RBAC26',
      'role': 'sage_femme',
      'statut': 'actif',
      'libelle': 'Responsable Maternité (sage-femme)',
      'droits': {'M4': droit(true, true, true), 'M1': droit(true)},
      'droitsEcrans': {'m1-pieces': {'voir': false}},
    };

void main() {
  group('aplatir et différer', () {
    test('la fiche devient des clés de droit : modules, écrans, champs du rôle', () {
      final a = drAplatir(graine());
      expect(a.keys, containsAll(['droits.M4', 'droits.M1', 'droitsEcrans.m1-pieces', 'champ.statut', 'champ.libelle']));
    });
    test('une écriture de l’écran ne produit que les clés qui changent', () {
      final d = drDiff(graine(), {
        'droits': {'M4': droit(true, true, true), 'M1': droit(true, true), 'M9': droit(true)},
        'statut': 'actif',
      });
      expect(d.keys.toSet(), {'droits.M1', 'droits.M9'});
    });
    test('un réglage d’écran retiré est une clé à null', () {
      final d = drDiff(graine(), {'droitsEcrans': <String, Object?>{}});
      expect(d, {'droitsEcrans.m1-pieces': null});
    });
  });

  group('appliquer', () {
    test('la première décision pose la clé, la version, le registre et le motif', () {
      final r = drAppliquer(graine(), dec('D1', '2026-11-10T10:00:00Z', {'droits.M1': droit(true, true)}, avant: {'droits.M1': droit(true)}));
      expect(r.issue, 'appliquee');
      final f = r.fiche!;
      expect((f['droits'] as Map)['M1'], droit(true, true));
      expect(f['version'], 1);
      expect(f['decideLe'], '2026-11-10T10:00:00.000Z');
      expect(((f['cles'] as Map)['droits.M1'] as Map)['motif'], 'Revue');
      expect(r.avantJournal, {'module M1': 'voir'});
      expect(r.apresJournal, {'module M1': 'voir, éditer'});
    });

    test('deux décisions sur le même droit : la plus récente l’emporte, la plus ancienne arrivée en retard est ÉCARTÉE et nommée', () {
      final recente = drAppliquer(graine(), dec('D2', '2026-11-10T12:00:00Z', {'droits.M1': droit(false)}, auteur: 'Directeur', motif: 'Audit'));
      final r = drAppliquer(recente.fiche, dec('D1', '2026-11-10T10:00:00Z', {'droits.M1': droit(true, true)}, auteur: 'DAF', motif: 'Besoin'));
      expect(r.issue, 'ecartee');
      expect(r.fiche, isNull, reason: 'rien n’est écrit');
      final l = r.lignes.single;
      expect(l.appliquee, isFalse);
      expect([l.remplaceeParDecision, l.remplaceeParAuteur, l.remplaceeParMotif], ['D2', 'Directeur', 'Audit']);
    });

    test('une décision plus récente qui écrase une valeur que son auteur n’avait pas vue est marquée CONCURRENTE, avec la décision remplacée', () {
      final d1 = drAppliquer(graine(), dec('D1', '2026-11-10T10:00:00Z', {'droits.M1': droit(true, true)}, avant: {'droits.M1': droit(true)}, auteur: 'DAF', motif: 'Saisie'));
      // L'auteur de D2 avait sous les yeux l'ancienne valeur (voir seul) : il n'a pas vu D1.
      final r = drAppliquer(d1.fiche, dec('D2', '2026-11-10T11:00:00Z', {'droits.M1': droit(false)}, avant: {'droits.M1': droit(true)}, auteur: 'Directeur', motif: 'Fermeture'));
      expect(r.issue, 'appliquee');
      final l = r.lignes.single;
      expect(l.concurrent, isTrue);
      expect([l.remplaceeParDecision, l.remplaceeParAuteur, l.remplaceeParMotif], ['D1', 'DAF', 'Saisie']);
      expect(l.ancien, droit(true, true), reason: 'l’ancien droit est écrit au journal');
      expect(l.nouveau, droit(false));
    });

    test('deux décisions sur des droits DIFFÉRENTS se cumulent : aucune n’efface l’autre', () {
      final a = drAppliquer(graine(), dec('D1', '2026-11-10T10:00:00Z', {'droits.M1': droit(true, true)}));
      final b = drAppliquer(a.fiche, dec('D2', '2026-11-10T09:00:00Z', {'droits.M9': droit(true)}));
      expect(b.issue, 'appliquee');
      final d = b.fiche!['droits'] as Map;
      expect(d['M1'], droit(true, true));
      expect(d['M9'], droit(true));
    });

    test('décision partielle : une clé ancienne est écartée, l’autre appliquée', () {
      final a = drAppliquer(graine(), dec('D2', '2026-11-10T12:00:00Z', {'droits.M1': droit(false)}));
      final r = drAppliquer(a.fiche, dec('D1', '2026-11-10T10:00:00Z', {'droits.M1': droit(true, true), 'droits.M9': droit(true)}));
      expect(r.issue, 'partielle');
      expect(r.appliquees.map((l) => l.cle), ['droits.M9']);
      expect(r.ecartees.map((l) => l.cle), ['droits.M1']);
    });

    test('CONVERGENCE : toutes les permutations de quatre décisions donnent la même fiche', () {
      final ds = [
        dec('D1', '2026-11-10T10:00:00Z', {'droits.M1': droit(true, true), 'droits.M9': droit(true)}),
        dec('D2', '2026-11-10T11:00:00Z', {'droits.M1': droit(false)}),
        dec('D3', '2026-11-10T11:00:00Z', {'droits.M9': droit(false), 'droitsEcrans.m4-cpn': droit(true, true)}),
        dec('D4', '2026-11-10T09:00:00Z', {'droitsEcrans.m4-cpn': droit(false), 'champ.libelleCourt': 'Resp. Maternité'}),
      ];
      String vue(Map<String, Object?>? f) => jsonEncode({'droits': f!['droits'], 'ecrans': f['droitsEcrans'], 'court': f['libelleCourt']});
      Iterable<List<T>> permutations<T>(List<T> l) sync* {
        if (l.length <= 1) {
          yield l;
          return;
        }
        for (var i = 0; i < l.length; i++) {
          final reste = [...l]..removeAt(i);
          for (final p in permutations(reste)) {
            yield [l[i], ...p];
          }
        }
      }

      final vues = <String>{};
      for (final ordre in permutations(ds)) {
        Map<String, Object?>? f = graine();
        for (final d in ordre) {
          f = drAppliquer(f, d).fiche ?? f;
        }
        vues.add(vue(f));
      }
      expect(vues.length, 1, reason: 'même fiche quel que soit l’ordre d’arrivée : $vues');
      final f = jsonDecode(vues.single) as Map;
      expect((f['droits'] as Map)['M1'], droit(false), reason: 'D2 est la plus récente sur M1');
      expect((f['droits'] as Map)['M9'], droit(false), reason: 'D3 est la plus récente sur M9');
      expect((f['ecrans'] as Map)['m4-cpn'], droit(true, true), reason: 'D3 (11 h) l’emporte sur D4 (9 h)');
    });

    test('une décision sans motif, ou sans horodatage, est refusée sans rien écrire', () {
      expect(drAppliquer(graine(), dec('D1', '2026-11-10T10:00:00Z', {'droits.M1': droit(false)}, motif: '  ')).issue, 'refusee');
      final sansDate = {...dec('D2', '2026-11-10T10:00:00Z', {'droits.M1': droit(false)}), 'decideLe': ''};
      expect(drAppliquer(graine(), sansDate).issue, 'refusee');
    });

    test('rejouer la même décision ne change rien (idempotence) : la version ne monte pas', () {
      final d = dec('D1', '2026-11-10T10:00:00Z', {'droits.M1': droit(true, true)});
      final a = drAppliquer(graine(), d);
      final b = drAppliquer(a.fiche, d);
      expect(b.issue, 'sans_effet');
      expect(b.fiche == null || b.fiche!['version'] == 1, isTrue);
    });

    test('la création d’un rôle (aucune fiche) pose tout depuis zéro', () {
      final r = drAppliquer(null, dec('D1', '2026-11-10T10:00:00Z', {'champ.libelle': 'Auditeur', 'champ.nouveau': true, 'droits.M1': droit(false)}));
      expect(r.fiche!['role'], 'sage_femme');
      expect(r.fiche!['libelle'], 'Auditeur');
      expect(r.fiche!['nouveau'], true);
    });
  });

  group('revenir au défaut d’origine', () {
    test('les clés qui ramènent à la graine : valeur remise, clé inconnue de la graine retirée', () {
      final g = graine();
      final modifiee = drAppliquer(g, dec('D1', '2026-11-10T10:00:00Z', {'droits.M1': droit(false), 'droits.M9': droit(true), 'droitsEcrans.m4-cpn': droit(true, true)})).fiche!;
      final ch = drChangementsVersGraine(modifiee, g);
      expect(ch['droits.M1'], droit(true));
      expect(ch['droits.M9'], isNull);
      expect(ch.containsKey('droits.M9'), isTrue);
      expect(ch['droitsEcrans.m4-cpn'], isNull);
    });

    test('la remise est une décision de plus : l’historique reste, la version monte, la fiche retrouve les droits de la graine', () {
      final g = graine();
      final v1 = drAppliquer(g, dec('D1', '2026-11-10T10:00:00Z', {'droits.M1': droit(false)})).fiche!;
      final remise = dec('D2', '2026-11-10T11:00:00Z', drChangementsVersGraine(v1, g), avant: drAplatir(v1));
      final v2 = drAppliquer(v1, remise).fiche!;
      expect(v2['version'], 2);
      expect(v2['droits'], g['droits']);
      expect(((v2['cles'] as Map)['droits.M1'] as Map)['id'], 'D2');
    });
  });

  group('recevabilité', () {
    final decision = dec('D1', '2026-11-10T10:00:00Z', {'droits.M1': droit(false)}, role: 'medecin');
    test('un profil qui n’édite pas l’écran des droits est refusé en le nommant', () {
      final r = drRefusDecision(decision, peutEditer: (role, ecran) => role == 'admin' && ecran == 'm14-roles');
      expect(r, contains('medecin'));
    });
    test('un profil habilité passe', () {
      expect(drRefusDecision({...decision, 'auteurRole': 'admin'}, peutEditer: (role, ecran) => role == 'admin' && ecran == 'm14-roles'), isNull);
    });
    test('un auteur sans rôle, ou un motif vide, est refusé', () {
      expect(drRefusDecision({...decision, 'auteurRole': null}, peutEditer: (_, __) => true), isNotNull);
      expect(drRefusDecision({...decision, 'motif': ''}, peutEditer: (_, __) => true), isNotNull);
    });
  });
}
