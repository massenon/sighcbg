// LES DROITS DU MOBILE (Direction, 10/11/2026) : le téléphone rejoue le moteur du poste sur les fiches que la mère lui diffuse.
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef Fiche = Map<String, Object?>;

String _lire(String chemin) => File(chemin).readAsStringSync();

void main() {
  // La graine du téléphone : les fichiers copiés dans apps/mobile/assets/droits. Le premier test les rapproche de leurs sources.
  const assets = '../../apps/mobile/assets/droits';
  const poste = '../../apps/poste/assets/donnees';
  final graine = GraineDroits.depuisJson(
    manifeste: _lire('$assets/manifeste.json'),
    rbac: _lire('$assets/rbac.json'),
    rbacReference: _lire('$assets/rbac.reference.json'),
    rbacLivre: _lire('$assets/rbac.livre.json'),
    modulesReference: _lire('$assets/modulesActifs.reference.json'),
    modulesLivres: _lire('$assets/modulesActifs.livre.json'),
  );
  final graineMatrice = MatriceMobile.graine(graine);
  List<Fiche> livre() => [for (final f in graine.rbacLivre) {...f}];
  Fiche surcharge(String role, {Map<String, Object?> ecrans = const {}, Map<String, Object?> modules = const {}, String id = 'RBACX'}) =>
      {'id': id, 'role': role, 'statut': 'actif', if (ecrans.isNotEmpty) 'droitsEcrans': ecrans, if (modules.isNotEmpty) 'droits': modules, 'definiLe': '2026-11-10'};
  // Les fiches de la mère : celles du jeu livré, plus une décision (la fiche d'un rôle est UNE, la décision la remplace champ par champ).
  MatriceMobile apres(List<Fiche> decisions, {List<Fiche> modules = const []}) => graineMatrice.avecFiches(rbac: [...livre(), ...decisions], modulesActifs: modules);

  group('la graine : les copies embarquées sont celles du poste', () {
    test('chaque fichier de la graine est identique à sa source (sinon : recopier depuis apps/poste/assets/donnees)', () {
      final paires = {
        'manifeste.json': '$poste/manifeste.json',
        'rbac.json': '$poste/rbac.json',
        'rbac.reference.json': '$poste/rbac.reference.json',
        'rbac.livre.json': '$poste/jeu/rbac.json',
        'modulesActifs.reference.json': '$poste/modulesActifs.reference.json',
        'modulesActifs.livre.json': '$poste/jeu/modulesActifs.json',
      };
      paires.forEach((copie, source) => expect(_lire('$assets/$copie'), _lire(source), reason: 'cp $source $assets/$copie'));
    });

    test('le rôle du téléphone vient de la fonction fixée par la mère : une fonction inconnue ne porte aucun rôle', () {
      expect(mobRoleDroits(reception: true), 'reception');
      expect(mobRoleDroits(reception: false, fonction: 'medecin'), 'medecin');
      expect(mobRoleDroits(reception: false, fonction: 'sage_femme'), 'sage_femme');
      expect(mobRoleDroits(reception: false, fonction: 'infirmier'), 'infirmier');
      expect(mobRoleDroits(reception: false, fonction: 'aide_soignant'), 'aide_soignant');
      expect(mobRoleDroits(reception: false, fonction: 'chauffeur'), isNull);
      expect(mobRoleDroits(reception: false), isNull);
      expect(graineMatrice.peutVoir(null, 'dossier'), isFalse);
    });

    test('les droits d\'origine sont ceux de la matrice du poste, écran par écran, pour les cinq rôles du téléphone', () {
      expect(graineMatrice.recue, isFalse);
      // La matrice du poste à son premier lancement : la graine engendrée superposée aux fiches du jeu livré (même appel que `aChaud`).
      final poste = superposerDroits(graine.base, graine.manifeste,
          rbac: graine.rbacLivre, modulesActifs: graine.modulesLivres, referenceRbac: graine.referenceRbac, referenceModules: graine.referenceModules);
      for (final role in ['medecin', 'sage_femme', 'infirmier', 'aide_soignant', 'reception']) {
        for (final e in mobEcransManifeste.entries) {
          expect(graineMatrice.droit(role, e.key), poste.droit(role, e.value), reason: '$role / ${e.key} -> ${e.value}');
        }
      }
    });

    test('les droits d\'origine : le médecin voit et écrit sa consultation, la sage-femme sa CPN, la réception ne voit aucun écran clinique', () {
      expect(graineMatrice.peutEditer('medecin', 'consultation'), isTrue);
      expect(graineMatrice.peutEditer('medecin', 'prescription'), isTrue);
      expect(graineMatrice.peutEditer('medecin', 'demande-analyse'), isTrue);
      expect(graineMatrice.peutEditer('sage_femme', 'cpn'), isTrue);
      expect(graineMatrice.peutEditer('sage_femme', 'surveillance'), isTrue);
      expect(graineMatrice.peutEditer('sage_femme', 'prescription'), isFalse, reason: 'la sage-femme lit les ordonnances, elle n\'en écrit pas');
      expect(graineMatrice.peutEditer('infirmier', 'constantes'), isTrue);
      expect(graineMatrice.peutVoir('reception', 'consultation'), isFalse);
      expect(graineMatrice.peutVoir('reception', 'cpn'), isFalse);
      expect(graineMatrice.peutEditer('reception', 'nouveau-dossier'), isTrue);
      expect(graineMatrice.peutEditer('reception', 'orientation'), isTrue);
    });

    test('un écran de l\'appareil (réglages, synchronisation, refus à traiter) n\'est gouverné par aucune matrice', () {
      for (final e in ['sync', 'a-traiter', 'parametres', 'verrou', 'appairage']) {
        expect(graineMatrice.peutVoir('aide_soignant', e), isTrue, reason: e);
        expect(graineMatrice.peutVoir(null, e), isTrue, reason: e);
      }
      // Un écran inconnu n'ouvre rien.
      expect(graineMatrice.peutVoir('medecin', 'inconnu'), isFalse);
    });
  });

  group('les fiches reçues de la mère font foi', () {
    test('un droit de voir retiré : l\'écran disparaît ; la graine, elle, ne bouge pas', () {
      final m = apres([surcharge('sage_femme', ecrans: {'m4-cpn': {'voir': false}})]);
      expect(m.recue, isTrue);
      expect(m.peutVoir('sage_femme', 'cpn'), isFalse);
      expect(m.peutEditer('sage_femme', 'cpn'), isFalse, reason: 'écrire suppose voir');
      expect(m.peutVoir('sage_femme', 'cpon'), isTrue, reason: 'un seul écran retiré');
      expect(graineMatrice.peutVoir('sage_femme', 'cpn'), isTrue);
    });

    test('un droit d\'écrire retiré : l\'écran reste visible, la commande disparaît (lecture seule)', () {
      final m = apres([surcharge('medecin', ecrans: {'m2-ordonnances': {'voir': true, 'editer': false, 'annuler': false}})]);
      expect(m.peutVoir('medecin', 'prescription'), isTrue);
      expect(m.peutEditer('medecin', 'prescription'), isFalse);
      expect(m.droit('medecin', 'prescription').lectureSeule, isTrue);
      expect(m.peutEditer('medecin', 'consultation'), isTrue, reason: 'les autres écrans ne bougent pas');
    });

    test('un droit rendu : la décision la plus récente de la mère ouvre ce que la graine fermait', () {
      final m = apres([surcharge('aide_soignant', ecrans: {'m1-patients': {'voir': true, 'editer': false, 'annuler': false}})]);
      expect(graineMatrice.peutVoir('aide_soignant', 'dossier'), isFalse, reason: 'droits d\'origine : l\'aide-soignante n\'a pas le répertoire');
      expect(m.peutVoir('aide_soignant', 'dossier'), isTrue);
    });

    test('un module fermé par la direction (activité fermée) retire ses écrans à tous les rôles', () {
      final m = apres([], modules: [
        ...graine.referenceModules,
        {'id': 'MOD10', 'code': 'M4', 'module': 'M4', 'actif': false, 'motif': 'Hors périmètre', 'fermeLe': '2026-11-10', 'fermePar': 'Direction'},
      ]);
      expect(m.peutVoir('sage_femme', 'cpn'), isFalse);
      expect(m.peutVoir('medecin', 'cpon'), isFalse);
      expect(m.peutVoir('medecin', 'consultation'), isTrue);
      // La fiche de fermeture ARCHIVÉE ne ferme plus rien (RG-14).
      final rouvert = apres([], modules: [
        ...graine.referenceModules,
        {'id': 'MOD10', 'code': 'M4', 'module': 'M4', 'actif': false, 'statut': 'archive'},
      ]);
      expect(rouvert.peutVoir('sage_femme', 'cpn'), isTrue);
    });

    test('un rôle archivé n\'ouvre plus rien', () {
      final m = apres([surcharge('infirmier', id: 'RBACA')..['statut'] = 'archive']);
      expect(m.ecransVisibles('infirmier').where((e) => !mobEcransHorsMatrice.contains(e)), isEmpty);
      expect(m.peutVoir('infirmier', 'constantes'), isFalse);
      expect(m.peutVoir('infirmier', 'sync'), isTrue, reason: 'l\'appareil se dit toujours');
    });

    test('aucune fiche reçue : les droits d\'origine restent en force (pas de matrice vide)', () {
      final m = graineMatrice.avecFiches(rbac: const [], modulesActifs: const []);
      expect(m.recue, isFalse);
      expect(m.peutEditer('medecin', 'consultation'), isTrue);
    });

    test('la fiche livrée sans changement donne la matrice d\'origine, case pour case', () {
      final m = apres([]);
      expect(m.recue, isTrue);
      for (final role in ['medecin', 'sage_femme', 'infirmier', 'aide_soignant', 'reception']) {
        expect(m.ecransVisibles(role), graineMatrice.ecransVisibles(role), reason: role);
      }
    });
  });
}
