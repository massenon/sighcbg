// LES SEUILS DE LA MÈRE LUS AU REGISTRE DATÉ (consigne du 18/11/2026 : « plus de valeur en dur »).
//
// La mère (`packages/sync_dart`) appliquait ses règles avec des littéraux : fenêtre de réinitialisation, délai avant la sauvegarde quotidienne, âge limite d'une copie de nuit,
// seuils de la supervision. Ce sont des RÉGLAGES de la collection `parametres` (famille `mere`, versions datées, bornés) : ce fichier ne fait que les LIRE — dans n'importe
// quelle liste de fiches (la base de la mère, le magasin d'un poste, un test) — et valider la COHÉRENCE des paires (une alerte plus clémente que l'attention n'a pas de sens :
// la paire retombe alors sur ses valeurs d'attente ENSEMBLE, comme les bornes de la balance âgée).
//
// Dart pur, aucune horloge : la date est toujours fournie.
library;

import '../parametres/parametres_clinique.dart' show seuilEntierA, seuilSeme;

const String mereCleDelaiSauvegardeQuotidienne = 'mere.delaiSauvegardeQuotidienneHeures';
const String mereCleAgeLimiteCopieMagasin = 'mere.ageLimiteCopieMagasinHeures';
const String mereCleCyclesCopieFichiers = 'mere.copieFichiersCyclesTolerables';
const String mereCleToleranceCopieFichiersMin = 'mere.toleranceRetardCopieFichiersMinutes';
const String mereCleDisqueAttenteGo = 'mere.supervisionDisqueAttentionGo';
const String mereCleDisqueAlerteGo = 'mere.supervisionDisqueAlerteGo';
const String mereCleSauvegardeAttentionHeures = 'mere.supervisionSauvegardeAttentionHeures';
const String mereCleSauvegardeAlerteHeures = 'mere.supervisionSauvegardeAlerteHeures';
const String mereClePosteSilenceAttentionMin = 'mere.supervisionPosteSilenceAttentionMinutes';
const String mereClePosteSilenceAlerteMin = 'mere.supervisionPosteSilenceAlerteMinutes';
const String mereClePosteRetardOperations = 'mere.supervisionPosteRetardOperations';
const String mereCleRelaisRetardAttention = 'mere.supervisionRelaisRetardAttention';
const String mereCleRelaisRetardAlerte = 'mere.supervisionRelaisRetardAlerte';
const String mereCleDeriveHorlogeMin = 'mere.supervisionDeriveHorlogeMinutes';

/// Les seuils de la supervision du poste mère EN VIGUEUR. Les disques sont en octets (les réglages sont en Go).
class MereSeuilsSupervision {
  const MereSeuilsSupervision({
    required this.disqueAttentionOctets,
    required this.disqueAlerteOctets,
    required this.sauvegardeAttentionHeures,
    required this.sauvegardeAlerteHeures,
    required this.posteSilenceAttentionMin,
    required this.posteSilenceAlerteMin,
    required this.posteRetardOperations,
    required this.relaisRetardAttention,
    required this.relaisRetardAlerte,
    required this.deriveHorlogeMin,
  });
  final int disqueAttentionOctets, disqueAlerteOctets;
  final int sauvegardeAttentionHeures, sauvegardeAlerteHeures;
  final int posteSilenceAttentionMin, posteSilenceAlerteMin, posteRetardOperations;
  final int relaisRetardAttention, relaisRetardAlerte;
  final int deriveHorlogeMin;
}

const int _octetsParGo = 1024 * 1024 * 1024;

/// Les seuils de supervision à [date] (AAAA-MM-JJ). Chaque paire (attention, alerte) dont l'ordre est renversé ou égal retombe sur ses valeurs d'attente, ENSEMBLE.
MereSeuilsSupervision mereSeuilsSupervisionA(Iterable<Map<String, Object?>> fiches, String date) {
  int v(String cle) => seuilEntierA(fiches, cle, date);
  // La paire dont le premier terme doit être STRICTEMENT inférieur au second (ou supérieur, pour le disque : l'attention se déclenche à un espace libre plus grand).
  (int, int) paire(String c1, String c2, {required bool premierPlusPetit}) {
    final a = v(c1), b = v(c2);
    return (premierPlusPetit ? a < b : a > b) ? (a, b) : (seuilSeme(c1), seuilSeme(c2));
  }

  final disque = paire(mereCleDisqueAttenteGo, mereCleDisqueAlerteGo, premierPlusPetit: false);
  final sauv = paire(mereCleSauvegardeAttentionHeures, mereCleSauvegardeAlerteHeures, premierPlusPetit: true);
  final silence = paire(mereClePosteSilenceAttentionMin, mereClePosteSilenceAlerteMin, premierPlusPetit: true);
  final relais = paire(mereCleRelaisRetardAttention, mereCleRelaisRetardAlerte, premierPlusPetit: true);
  return MereSeuilsSupervision(
    disqueAttentionOctets: disque.$1 * _octetsParGo,
    disqueAlerteOctets: disque.$2 * _octetsParGo,
    sauvegardeAttentionHeures: sauv.$1,
    sauvegardeAlerteHeures: sauv.$2,
    posteSilenceAttentionMin: silence.$1,
    posteSilenceAlerteMin: silence.$2,
    posteRetardOperations: v(mereClePosteRetardOperations),
    relaisRetardAttention: relais.$1,
    relaisRetardAlerte: relais.$2,
    deriveHorlogeMin: v(mereCleDeriveHorlogeMin),
  );
}
