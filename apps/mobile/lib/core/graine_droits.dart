import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:sigh_domaine/sigh_domaine.dart' show GraineDroits;

/// La GRAINE des droits : les droits d'origine du logiciel, embarqués avec l'application (`assets/droits`, copie des fichiers que le poste livre : un test les rapproche de
/// leurs sources). Hors ligne, avant la première synchronisation, c'est la seule matrice que le téléphone connaisse ; dès que la mère livre ses fiches, elles font foi.
Future<GraineDroits> chargerGraineDroits([AssetBundle? bundle]) async {
  final b = bundle ?? rootBundle;
  return GraineDroits.depuisJson(
    manifeste: await b.loadString('assets/droits/manifeste.json'),
    rbac: await b.loadString('assets/droits/rbac.json'),
    rbacReference: await b.loadString('assets/droits/rbac.reference.json'),
    rbacLivre: await b.loadString('assets/droits/rbac.livre.json'),
    modulesReference: await b.loadString('assets/droits/modulesActifs.reference.json'),
    modulesLivres: await b.loadString('assets/droits/modulesActifs.livre.json'),
  );
}
