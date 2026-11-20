/// LES RÉGLAGES QUE LA MÈRE APPLIQUE, LUS À SON REGISTRE DATÉ (consigne du 18/11/2026 : « plus de valeur en dur »).
///
/// La mère tient la collection `parametres` (une fiche par version, famille R : elle seule l'écrit, les postes la reçoivent). Elle appliquait pourtant ses règles — fenêtre de
/// réinitialisation, délai avant la sauvegarde quotidienne, âge limite d'une copie de nuit, seuils de supervision — avec des littéraux. Ce fichier les lui fait LIRE : la version datée
/// qui s'applique AUJOURD'HUI (le poste et la mère lisent donc la même chose), sinon la valeur d'attente de la définition ; hors des bornes déclarées, la valeur d'attente — jamais zéro.
/// Les règles de lecture (bornes, cohérence des paires) sont celles du domaine (`seuilEntierA`, `mereSeuilsSupervisionA`), jamais recopiées ici.
library;

import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'depot.dart';

/// Les fiches de versions de `parametres` de la base de la mère (les archivées et les illisibles sont ignorées).
Future<List<Map<String, Object?>>> fichesParametresMere(Depot base) async {
  final out = <Map<String, Object?>>[];
  for (final r in await base.select('SELECT data FROM fiches WHERE collection=? AND archive=0', [parCollectionParametres])) {
    try {
      out.add((jsonDecode(r['data'] as String) as Map).cast<String, Object?>());
    } catch (_) {/* une fiche illisible n'est pas une version */}
  }
  return out;
}

/// Un seuil entier de la mère, EN VIGUEUR à [maintenant] (AAAA-MM-JJ de l'horloge de la mère).
Future<int> seuilMere(Depot base, String cle, DateTime maintenant) async => seuilEntierA(await fichesParametresMere(base), cle, parametreDateIso(maintenant));

/// Les seuils de supervision EN VIGUEUR.
Future<MereSeuilsSupervision> seuilsSupervisionMere(Depot base, DateTime maintenant) async =>
    mereSeuilsSupervisionA(await fichesParametresMere(base), parametreDateIso(maintenant));
