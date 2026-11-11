/// LES DROITS DU MOBILE (Direction de Baguidi, 10/11/2026) : « L'application mobile doit évaluer la matrice des droits pour suivre ces modifications. »
///
/// Le téléphone n'a PAS son propre moteur de droits : il rejoue celui du poste. Les fiches de la collection `rbac` (une par rôle) et de `modulesActifs`
/// (activités fermées) que la mère lui diffuse par le relais sont superposées à la graine par [superposerDroits] — le MÊME calcul que `aChaud` du poste, le
/// même manifeste, la même matrice engendrée. Rien de la logique des droits n'est recopié ici : ce fichier ne fait que (1) NOMMER le rôle de la matrice que
/// porte l'agent appairé, (2) RELIER chaque écran du téléphone à un écran du manifeste, (3) tenir la graine de départ.
///
/// Trois règles, toutes tenues par les tests :
///  * la matrice engendrée n'est que la GRAINE (hors ligne, avant la première synchronisation) : dès que la mère a livré ses fiches, elles font foi ;
///  * le droit de la matrice RESTREINT ce que le profil du téléphone offre déjà (`mob_suite.dart`, `D.CAPACITES`) : il ne peut pas ouvrir sur le mobile
///    un écran que le profil ne porte pas ;
///  * le rôle (donc la fonction) vient du code d'appairage de la mère (E1600), jamais d'un réglage du téléphone.
library;

import 'dart:convert' show JsonCodec;

import '../droits/a_chaud.dart';
import '../droits/matrice.dart';
import '../navigation/manifeste.dart';
import 'mob_regles.dart' show RefusMobile, mobLibelleEcran;

typedef MobFicheDroits = Map<String, Object?>;

/// Les écrans du téléphone gouvernés par la matrice, et l'écran du manifeste dont ils portent le droit. Le choix est celui de l'écran qui tient la même
/// donnée au poste : le dossier est le répertoire des patients, la saisie de constantes l'écran des constantes de l'accueil, etc.
const mobEcransManifeste = <String, String>{
  'dossier': 'm1-patients',
  'constantes': 'm1-constantes',
  'consultation': 'm2-consultation-fiche',
  'prescription': 'm2-ordonnances',
  'demande-analyse': 'm5-demandes',
  'cpn': 'm4-cpn',
  'cpon': 'm4-cpon',
  'surveillance': 'm4-accouchements',
  'nouveau-dossier': 'm1-patient-nouveau',
  'dossiers-crees': 'm1-patient-nouveau',
  'orientation': 'm2-file-attente',
  // L'agenda du jour de la tournée : l'agenda de l'accueil.
  'agenda': 'm2-agenda',
};

/// Les écrans du téléphone que la matrice NE gouverne pas : l'appairage, le verrou, la synchronisation, les refus à traiter, le lot et les réglages sont
/// l'appareil lui-même (sans eux, le téléphone ne peut ni se verrouiller ni dire ce qui lui arrive). Leur ouverture reste celle du profil.
const mobEcransHorsMatrice = {'appairage', 'verrou', 'sync', 'a-traiter', 'lot', 'parametres', 'accueil-soignant', 'accueil-medecin', 'accueil-sagefemme', 'accueil-reception'};

/// Le rôle de la matrice que porte l'agent du téléphone. La réception de secours est `reception` ; un soignant porte le rôle de SA fonction (fixée par la
/// mère à l'appairage). Une fonction inconnue ne porte AUCUN rôle : ce qu'on ne sait pas n'ouvre rien.
String? mobRoleDroits({required bool reception, String fonction = ''}) {
  if (reception) return 'reception';
  return switch (fonction) {
    'medecin' => 'medecin',
    'sage_femme' => 'sage_femme',
    'infirmier' => 'infirmier',
    'aide_soignant' => 'aide_soignant',
    _ => null,
  };
}

/// La graine : ce que le téléphone sait des droits AVANT d'avoir reçu les fiches de la mère. Ce sont les fichiers que le poste livre (`manifeste.json`,
/// `rbac.json` et les fiches du jeu livré, avec la référence de l'extraction) : le téléphone démarre donc sur les droits d'origine du logiciel.
class GraineDroits {
  GraineDroits(
      {required this.manifeste,
      required this.base,
      required this.referenceRbac,
      required this.referenceModules,
      required this.rbacLivre,
      this.modulesLivres = const []});

  /// Les chaînes JSON des cinq fichiers engendrés (`manifeste`, `rbac`, `rbac.reference`, `jeu/rbac`, `modulesActifs.reference`).
  factory GraineDroits.depuisJson(
      {required String manifeste,
      required String rbac,
      required String rbacReference,
      required String rbacLivre,
      required String modulesReference,
      String? modulesLivres}) {
    List<MobFicheDroits> fiches(String t) => [for (final f in (_decoder(t) as List)) (f as Map).cast<String, Object?>()];
    return GraineDroits(
      manifeste: Manifeste.depuisJson((_decoder(manifeste) as Map).cast<String, Object?>()),
      base: MatriceDroits.depuisJson((_decoder(rbac) as Map).cast<String, Object?>()),
      referenceRbac: fiches(rbacReference),
      referenceModules: fiches(modulesReference),
      rbacLivre: fiches(rbacLivre),
      modulesLivres: modulesLivres == null ? const [] : fiches(modulesLivres),
    );
  }

  final Manifeste manifeste;

  /// La matrice engendrée (`rbac.json`).
  final MatriceDroits base;

  /// Les fiches avec lesquelles la matrice engendrée l'a été (extraction), et les activités de l'extraction : la RÉFÉRENCE de la superposition.
  final List<MobFicheDroits> referenceRbac, referenceModules;

  /// Les fiches `rbac` / `modulesActifs` du jeu livré avec le logiciel : ce que le magasin du poste porte à son premier lancement.
  final List<MobFicheDroits> rbacLivre, modulesLivres;
}

/// La matrice EN FORCE sur le téléphone : la graine, ou la superposition des fiches reçues de la mère.
class MatriceMobile {
  MatriceMobile._(this.graine, this.matrice, this.recue);

  /// Les droits d'origine : aucune fiche reçue de la mère.
  factory MatriceMobile.graine(GraineDroits g) => MatriceMobile._(
      g,
      superposerDroits(g.base, g.manifeste,
          rbac: g.rbacLivre, modulesActifs: g.modulesLivres, referenceRbac: g.referenceRbac, referenceModules: g.referenceModules),
      false);

  final GraineDroits graine;
  final MatriceDroits matrice;

  /// Vrai quand la matrice vient des fiches de la mère ; faux : droits d'origine, pas encore synchronisés.
  final bool recue;

  /// La même graine sous les fiches que la mère vient de livrer. Aucune fiche reçue (la mère n'en a pas diffusé) : les droits d'origine restent en force.
  MatriceMobile avecFiches({required Iterable<MobFicheDroits> rbac, required Iterable<MobFicheDroits> modulesActifs}) {
    if (rbac.isEmpty && modulesActifs.isEmpty) return MatriceMobile.graine(graine);
    final m = superposerDroits(graine.base, graine.manifeste,
        rbac: rbac, modulesActifs: modulesActifs, referenceRbac: graine.referenceRbac, referenceModules: graine.referenceModules);
    return MatriceMobile._(graine, m, true);
  }

  /// Le droit du rôle sur un écran du TÉLÉPHONE. Un écran hors matrice (appareil) est ouvert ; un écran inconnu ou un rôle inconnu : rien.
  Droit droit(String? role, String ecranMobile) {
    if (mobEcransHorsMatrice.contains(ecranMobile)) return const Droit(voir: true, editer: true, annuler: false);
    final cible = mobEcransManifeste[ecranMobile];
    if (role == null || cible == null) return Droit.aucun;
    return matrice.droit(role, cible);
  }

  bool peutVoir(String? role, String ecranMobile) => droit(role, ecranMobile).voir;

  /// Écrire (créer une constante, une note, une prescription…) : le droit d'éditer, qui suppose celui de voir.
  bool peutEditer(String? role, String ecranMobile) {
    final d = droit(role, ecranMobile);
    return d.voir && d.editer;
  }

  /// Les écrans du téléphone que le rôle voit (ceux que la matrice gouverne).
  Set<String> ecransVisibles(String? role) => {
        for (final e in mobEcransManifeste.keys)
          if (peutVoir(role, e)) e
      };
}

// `dart:convert` seul : le domaine reste du Dart pur.
dynamic _decoder(String t) => _json.decode(t);
const _json = JsonCodec();

/// Le refus d'un geste ou d'un écran dont le droit a été retiré par la clinique : il se NOMME (code, motif, geste), il ne s'ouvre pas à moitié. Refait à CHAQUE
/// geste : une commande absente de l'écran ne protège rien, et un droit retiré pendant que l'écran était ouvert doit refuser le geste suivant.
RefusMobile mobRefusDroitRetire(String ecranMobile, {required bool ecriture}) {
  final nom = ecranMobile == 'agenda' ? 'Agenda du jour' : mobLibelleEcran(ecranMobile);
  return RefusMobile(
      'DROIT_RETIRE',
      ecriture ? 'Les droits de votre profil ne permettent plus d’écrire dans « $nom » : la clinique les a modifiés.' : 'Les droits de votre profil ne permettent plus de voir « $nom » : la clinique les a modifiés.',
      'Revenir à l’accueil ; demander la modification à l’administrateur de la clinique');
}
