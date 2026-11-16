import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> ecran(String id, String module, {List<String>? roles}) => {
        'id': id, 'label': id, 'icone': 'circle', 'module': module, 'moduleLabel': 'Module $module', 'domaine': 'Soins',
        'hub': false, 'standalone': false, 'universel': false, 'servant': null, if (roles != null) 'roles': roles,
      };
  final manifeste = Manifeste.depuisJson({
    'domaines': [{'nom': 'Soins', 'icone': 'stethoscope'}],
    'raccourcis': <Object>[],
    'modules': [
      {'domaine': 'Soins', 'code': 'M2', 'label': 'Spécialités', 'icone': 'stethoscope', 'alias': false, 'secondaire': true, 'ecrans': ['m2-specialites']},
    ],
    'ecrans': [ecran('m2-specialites', 'M2'), ecran('m2-file-attente', 'M2'), ecran('m2-dossiers-consultation', 'M2'), ecran('m2-stats-consultations', 'PIL')],
  });
  final matrice = MatriceDroits.depuisJson({
    'roles': [
      {'id': 'medecin', 'label': 'Médecin'},
      {'id': 'reception', 'label': 'Réception'},
      {'id': 'caissier', 'label': 'Caissier'},
      {'id': 'rh', 'label': 'RH', 'archive': true},
    ],
    'parRole': {
      'medecin': {'m2-specialites': [1, 1, 1], 'm2-file-attente': [1, 1, 1], 'm2-dossiers-consultation': [1, 1, 1], 'm2-stats-consultations': [1, 0, 0]},
      'reception': {'m2-specialites': [1, 0, 0], 'm2-file-attente': [1, 1, 0]},
      'caissier': <String, Object>{},
      'rh': <String, Object>{},
    },
  });

  EcranNav nav(String id, String module) => EcranNav(
      id: id, label: id, icone: 'circle', module: module, moduleLabel: 'Spécialités', domaine: 'Soins', hub: false, standalone: false);

  final dyn = manifeste.avecEcrans(
      ecrans: [for (final v in SpecVue.values) nav(specIdEcran('cardiologie', v), specModule)],
      domaine: 'Soins',
      code: 'M2',
      libelleRangee: 'Spécialités',
      idsRangee: [specIdEcran('cardiologie')]);
  final droits = matrice.avecDroitsDerives({
    for (final v in SpecVue.values) specIdEcran('cardiologie', v): specModelesDroits[v]!,
  });

  test('le manifeste augmenté garde l\'original intact et étend la rangée existante', () {
    expect(manifeste.ecran('spec-cardiologie'), isNull);
    expect(dyn.ecran('spec-cardiologie'), isNotNull);
    expect(dyn.ecran('spec-cardiologie-agenda')!.module, 'M2');
    expect(dyn.rangees.where((r) => r.label == 'Spécialités').length, 1);
    expect(dyn.rangees.single.ecrans, ['m2-specialites', 'spec-cardiologie']);
    expect(manifeste.rangees.single.ecrans, ['m2-specialites']);
  });

  test('la rangée est créée quand elle n\'existait pas, et un identifiant connu n\'est jamais écrasé', () {
    final vide = Manifeste.depuisJson({'domaines': [{'nom': 'Soins'}], 'modules': <Object>[], 'ecrans': <Object>[]});
    final m = vide.avecEcrans(ecrans: [nav('spec-x', 'M2')], domaine: 'Soins', code: 'M2', libelleRangee: 'Spécialités', idsRangee: ['spec-x']);
    expect(m.rangees.single.secondaire, isTrue);
    final deux = m.avecEcrans(
        ecrans: [EcranNav(id: 'spec-x', label: 'AUTRE', icone: null, module: 'M2', moduleLabel: 'x', domaine: 'Soins', hub: false, standalone: false)],
        domaine: 'Soins', code: 'M2', libelleRangee: 'Spécialités', idsRangee: ['spec-x']);
    expect(deux.ecran('spec-x')!.label, 'spec-x');
    expect(deux.rangees.single.ecrans, ['spec-x']);
  });

  test('les droits d\'un écran dérivé sont EXACTEMENT ceux de son modèle, rôle par rôle', () {
    expect(droits.droit('medecin', 'spec-cardiologie'), const Droit(voir: true, editer: true, annuler: true));
    expect(droits.droit('medecin', 'spec-cardiologie-stats'), const Droit(voir: true, editer: false, annuler: false));
    expect(droits.droit('reception', 'spec-cardiologie-agenda'), const Droit(voir: true, editer: true, annuler: false));
    expect(droits.droit('reception', 'spec-cardiologie-consultation'), Droit.aucun, reason: 'clinique : l\'accueil n\'y entre pas (RG-13)');
    expect(droits.droit('reception', 'spec-cardiologie-stats'), Droit.aucun);
  });

  test('un rôle sans le module, un rôle archivé : aucun écran de spécialité', () {
    for (final v in SpecVue.values) {
      expect(droits.peutVoir('caissier', specIdEcran('cardiologie', v)), isFalse);
      expect(droits.peutVoir('rh', specIdEcran('cardiologie', v)), isFalse);
    }
    expect(droits.ecransVisibles('caissier'), isEmpty);
  });

  test('le ruban d\'un rôle ne montre que les spécialités que ses droits ouvrent ; la matrice d\'origine n\'est pas modifiée', () {
    final med = dyn.ruban(droits, 'medecin', estMere: false);
    expect(med.single.rangees.single.ecrans.map((e) => e.id), ['m2-specialites', 'spec-cardiologie']);
    final rec = dyn.ruban(droits, 'reception', estMere: false);
    expect(rec.single.rangees.single.ecrans.map((e) => e.id), ['m2-specialites', 'spec-cardiologie']);
    expect(dyn.ruban(droits, 'caissier', estMere: false), isEmpty);
    expect(matrice.peutVoir('medecin', 'spec-cardiologie'), isFalse);
  });
}
