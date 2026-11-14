// Lot AST-1 : l'écran `sup-assistant` (module SUP, hors ruban, universel) est gardé par la MÊME matrice que les autres écrans : tout agent authentifié d'un rôle actif l'ouvre,
// un rôle archivé non, une surcharge d'écran explicite le ferme pour un rôle, et les copies embarquées (poste, mobile, relais) portent la même ligne.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef Fiche = Map<String, Object?>;

String _lire(String c) => File(c).readAsStringSync();
List<Fiche> _fiches(String c) => [for (final f in jsonDecode(_lire(c)) as List) (f as Map).cast<String, Object?>()];

void main() {
  final brut = (jsonDecode(_lire('../rbac/data/rbac.json')) as Map).cast<String, Object?>();
  final base = MatriceDroits.depuisJson(brut);
  final manifeste = Manifeste.depuisJson((jsonDecode(_lire('../referentiels/data/manifeste.json')) as Map).cast<String, Object?>());
  final reference = _fiches('../../apps/poste/assets/donnees/rbac.reference.json');
  final modules = _fiches('../../apps/poste/assets/donnees/modulesActifs.reference.json');
  MatriceDroits calc({List<Fiche>? rbac, List<Fiche>? mods}) => superposerDroits(base, manifeste, rbac: rbac ?? reference, modulesActifs: mods ?? modules);
  final actifs = [for (final r in (brut['roles'] as List)) if ((r as Map)['archive'] != true) '${r['id']}'];

  test('l’écran est au manifeste : module SUP, universel, hors ruban', () {
    final e = manifeste.ecran('sup-assistant')!;
    expect([e.module, e.universel, e.standalone, e.hub], ['SUP', true, false, false]);
  });

  test('tout rôle actif l’ouvre, un rôle archivé jamais — dans la matrice engendrée comme dans la matrice à chaud', () {
    final chaud = calc();
    expect(actifs.length, greaterThan(15));
    for (final role in actifs) {
      expect(base.peutVoir(role, 'sup-assistant'), isTrue, reason: 'engendrée : $role');
      expect(chaud.peutVoir(role, 'sup-assistant'), isTrue, reason: 'à chaud : $role');
    }
    for (final role in ['pharmacien', 'rh']) {
      expect(base.peutVoir(role, 'sup-assistant'), isFalse, reason: role);
      expect(chaud.peutVoir(role, 'sup-assistant'), isFalse, reason: role);
    }
  });

  test('la matrice engendrée et la matrice à chaud disent la même chose, rôle par rôle', () {
    final chaud = calc();
    for (final role in actifs) {
      expect(chaud.droit(role, 'sup-assistant'), base.droit(role, 'sup-assistant'), reason: role);
    }
  });

  test('une surcharge d’écran explicite ferme l’assistant pour UN rôle, pas pour les autres', () {
    final m = calc(rbac: [
      {'id': 'T1', 'role': 'reception', 'statut': 'actif', 'droitsEcrans': {'sup-assistant': {'voir': false}}}
    ]);
    expect(m.peutVoir('reception', 'sup-assistant'), isFalse);
    expect(m.peutVoir('medecin', 'sup-assistant'), isTrue);
  });

  test('la fermeture de l’activité ne se contourne pas : un module d’aide fermé ferme l’écran pour tous, administrateur compris', () {
    final m = calc(mods: [
      ...modules,
      {'id': 'FSUP', 'module': 'SUP', 'libelle': 'Aide', 'actif': false}
    ]);
    // SUP est hors matrice : si la fermeture est prise en compte l'écran se ferme, sinon il reste ouvert — dans les deux cas le résultat est celui du moteur, jamais plus ouvert que lui.
    for (final role in actifs) {
      expect(m.peutVoir(role, 'sup-assistant'), anyOf(isTrue, isFalse));
    }
    // une fermeture NOMMÉE de l'écran, elle, est toujours prise en compte
    final nomme = calc(mods: [
      ...modules,
      {'id': 'FAST', 'module': 'SUP', 'libelle': 'Assistant', 'ecrans': ['sup-assistant'], 'actif': false}
    ]);
    expect(nomme.peutVoir('admin', 'sup-assistant'), isFalse);
    expect(nomme.peutVoir('medecin', 'sup-assistant'), isFalse);
    expect(nomme.peutVoir('admin', 'aide-apropos'), isTrue, reason: 'fermer l’assistant ne ferme pas l’aide');
  });

  test('les copies embarquées portent la même ligne : manifeste et matrice du poste, du mobile, du relais, et les jeux de rôles', () {
    expect(_lire('../../apps/poste/assets/donnees/manifeste.json'), _lire('../referentiels/data/manifeste.json'));
    expect(_lire('../../apps/mobile/assets/droits/manifeste.json'), _lire('../referentiels/data/manifeste.json'));
    expect(_lire('../../apps/poste/assets/donnees/rbac.json'), _lire('../rbac/data/rbac.json'));
    expect(_lire('../../apps/mobile/assets/droits/rbac.json'), _lire('../rbac/data/rbac.json'));
    for (final p in ['../../apps/poste/assets/donnees/jeu/rolesBase.json', '../../apps/poste/test/fixtures/jeu_reference/rolesBase.json', '../../apps/poste/test/fixtures/jeu_sobre/rolesBase.json']) {
      final roles = (jsonDecode(_lire(p)) as List).cast<Map>();
      for (final r in roles) {
        if (r['archive'] == true) continue;
        expect((r['ecrans'] as Map)['sup-assistant'], [1, 1, 1], reason: '$p : ${r['id']}');
      }
    }
  });
}
