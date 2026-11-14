// LOT B : les GESTES RÉSERVÉS comme droit de la fiche de rôle (`droitsGestes`). Valider un seuil de variation brutale : le Biologiste médical d'origine ; une fiche accorde
// ET retire ; « sans fiche, tous les droits » ne vaut pas pour un geste ; archivage et activité fermée retirent le geste ; la décision de droits porte la clé `geste.<id>`.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

F fiche(String role, Map<String, bool> gestes, {String id = 'R1', String statut = 'actif'}) => {'id': id, 'role': role, 'statut': statut, 'droitsGestes': gestes};

void main() {
  const g = gesteValiderSeuil;
  const interim = gesteValiderSeuilInterim;

  test('l’origine : le Biologiste médical seul valide ; l’administrateur système, la Direction et le technicien (intérim) non', () {
    final d = DroitsGestes(fiches: const []);
    expect(d.peut('laborantin', g), isTrue);
    for (final r in ['admin', 'direction', 'dm', 'da', 'medecin', 'infirmier', 'comptable', 'reception', 'echographiste', 'un_role_cree_en_exploitation']) {
      expect(d.peut(r, g), isFalse, reason: r);
    }
    for (final r in ['admin', 'laborantin', 'direction']) {
      expect(d.peut(r, interim), isFalse, reason: 'l’intérim n’est accordé à personne d’origine : $r');
    }
    expect(d.origine('laborantin', g), 'origine');
    expect(gestesReserves.map((x) => x.id), [g, interim]);
  });

  test('une fiche ACCORDE (même à l’administrateur système, sans fiche d’origine) et RETIRE (même au Biologiste médical) ; absente, l’origine suit', () {
    expect(DroitsGestes(fiches: [fiche('admin', {g: true})]).peut('admin', g), isTrue, reason: 'la Direction peut accorder le geste à l’administrateur par la matrice');
    expect(DroitsGestes(fiches: [fiche('laborantin', {g: false})]).peut('laborantin', g), isFalse, reason: 'une surcharge retire aussi');
    expect(DroitsGestes(fiches: [fiche('laborantin', {interim: true})]).peut('laborantin', g), isTrue, reason: 'une fiche qui ne nomme pas le geste suit l’origine');
    expect(DroitsGestes(fiches: [fiche('medecin', {g: true})]).peut('direction', g), isFalse, reason: 'le droit est celui du RÔLE nommé, pas d’un autre');
    final d = DroitsGestes(fiches: [fiche('admin', {g: true})]);
    expect(d.origine('admin', g), 'decide');
    expect(d.decision('admin', g), isTrue);
    expect(d.decision('direction', g), isNull);
    expect(DroitsGestes(fiches: [fiche('laborantin', {interim: true})]).peut('laborantin', interim), isTrue);
  });

  test('à chaud : le droit se relit des fiches à chaque appel, accordé puis retiré puis rendu à l’origine, rien n’est mis en cache', () {
    final fiches = <F>[];
    bool peut() => DroitsGestes(fiches: fiches).peut('direction', g);
    expect(peut(), isFalse);
    fiches.add(fiche('direction', {g: true}));
    expect(peut(), isTrue);
    fiches[0] = fiche('direction', {g: false});
    expect(peut(), isFalse);
    fiches[0] = fiche('direction', {});
    expect(peut(), isFalse, reason: 'décision retirée : l’origine (personne) s’applique de nouveau');
  });

  test('deux fiches pour un rôle se fusionnent champ par champ : la dernière gagne sur le geste qu’elle nomme, pas sur les autres', () {
    final d = DroitsGestes(fiches: [fiche('direction', {g: true, interim: true}, id: 'A'), fiche('direction', {g: false}, id: 'B')]);
    expect(d.peut('direction', g), isFalse);
    expect(d.peut('direction', interim), isTrue);
  });

  test('un rôle archivé n’a aucun geste, un écran fermé le retire à TOUS les rôles, un geste ou un rôle inconnu : refusé', () {
    final fermes = <String>{};
    final d = DroitsGestes(
        fiches: [fiche('admin', {g: true})],
        estArchive: (r) => r == 'laborantin',
        ecranActif: (e, m) => !fermes.contains(e) && !fermes.contains(m));
    expect(d.peut('laborantin', g), isFalse, reason: 'rôle archivé');
    expect(d.peut('admin', g), isTrue);
    fermes.add('m5-valeurs-reference');
    expect(d.peut('admin', g), isFalse, reason: 'écran fermé : même une décision n’y fait rien');
    fermes
      ..clear()
      ..add('M5');
    expect(d.peut('admin', g), isFalse, reason: 'module fermé');
    expect(d.peut('admin', 'geste_inconnu'), isFalse);
    expect(d.peut('', g), isFalse);
    expect(gesteReserve('geste_inconnu'), isNull);
  });

  test('la liste des porteurs est DÉRIVÉE du droit, jamais recopiée', () {
    final tous = ['admin', 'direction', 'laborantin', 'medecin'];
    expect(DroitsGestes(fiches: const []).rolesAvec(g, tous), ['laborantin']);
    expect(DroitsGestes(fiches: [fiche('direction', {g: true}), fiche('laborantin', {g: false}, id: 'R2')]).rolesAvec(g, tous), ['direction']);
  });

  test('la matrice en force : un rôle archivé par une fiche perd le geste (MatriceDroits.estArchive), même avec une décision qui l’accordait', () {
    final base = MatriceDroits.depuisJson((jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>());
    final manifeste = Manifeste.depuisJson((jsonDecode(File('../referentiels/data/manifeste.json').readAsStringSync()) as Map).cast<String, Object?>());
    final fiches = <F>[fiche('laborantin', {g: true}, id: 'RB8')];
    DroitsGestes en(List<F> f) {
      final m = superposerDroits(base, manifeste, rbac: f);
      return DroitsGestes(fiches: f, estArchive: m.estArchive, ecranActif: m.ecranActif);
    }

    expect(en(fiches).peut('laborantin', g), isTrue);
    // Une fiche créée pour l'administrateur système (qui n'en avait pas) ne porte que le geste : ses droits d'ÉCRAN ne bougent pas d'une case.
    final avant = superposerDroits(base, manifeste);
    final apres = superposerDroits(base, manifeste, rbac: [fiche('admin', {g: true}, id: 'RBADM')..['libelleOrigine'] = 'Administrateur système']);
    expect(apres.ecransVisibles('admin'), avant.ecransVisibles('admin'));
    for (final e in avant.ecransVisibles('admin')) {
      expect(apres.droit('admin', e), avant.droit('admin', e), reason: e);
    }
    expect(en([fiche('admin', {g: true}, id: 'RBADM')]).peut('admin', g), isTrue);
    expect(en([fiche('laborantin', {g: true}, id: 'RB8')..['statut'] = 'archive']).peut('laborantin', g), isFalse);
    expect(en([...fiches, {'id': 'RB9', 'role': 'laborantin', 'statut': 'archive'}]).peut('laborantin', g), isFalse);
  });

  group('décisions de droits : la clé « geste.<id> »', () {
    test('drDiff ne retient que ce qui change ; null revient à l’origine ; une clé inchangée ne se touche pas', () {
      final avant = fiche('direction', {g: true});
      expect(drDiff(avant, {'droitsGestes': {g: true}}), isEmpty);
      expect(drDiff(avant, {'droitsGestes': {g: false}}), {'geste.$g': false});
      expect(drDiff(avant, {'droitsGestes': {g: null}}), {'geste.$g': null});
      expect(drDiff(null, {'droitsGestes': {g: null}}), isEmpty, reason: 'revenir à l’origine sur un droit jamais décidé : rien');
      expect(drDiff(null, {'droitsGestes': {g: true}}), {'geste.$g': true});
      expect(drAplatir(avant)['geste.$g'], isTrue);
    });

    test('drAppliquer pose le geste dans la fiche, le retire à « revenir à l’origine », et ne casse pas les autres droits', () {
      F decision(String id, String le, Map<String, Object?> changements, {Map<String, Object?> avant = const {}}) => {
            'ident': id,
            'role': 'direction',
            'decideLe': le,
            'motif': 'Décision de la Direction',
            'auteur': 'Directrice',
            'changements': changements,
            'avant': avant,
          };
      final r1 = drAppliquer(null, decision('D1', '2026-11-14T08:00:00Z', {'geste.$g': true}));
      expect(r1.issue, 'appliquee');
      expect((r1.fiche!['droitsGestes'] as Map)[g], isTrue);
      expect(DroitsGestes(fiches: [r1.fiche!]).peut('direction', g), isTrue);
      final r2 = drAppliquer(r1.fiche, decision('D2', '2026-11-14T09:00:00Z', {'geste.$g': null}, avant: {'geste.$g': true}));
      expect((r2.fiche!['droitsGestes'] as Map).containsKey(g), isFalse);
      expect(DroitsGestes(fiches: [r2.fiche!]).peut('direction', g), isFalse);
      // Une décision plus ancienne que celle en vigueur est écartée, et le dit.
      final r3 = drAppliquer(r2.fiche, decision('D0', '2026-11-14T07:00:00Z', {'geste.$g': true}));
      expect(r3.lignes.single.appliquee, isFalse);
      expect(drLibelleCle('geste.$g'), contains('Valider un seuil'));
      expect(drLibelleValeur('geste.$g', true), 'accordé');
      expect(drLibelleValeur('geste.$g', false), 'retiré');
    });
  });
}
