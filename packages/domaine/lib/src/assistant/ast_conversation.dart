/// LA CONVERSATION de l'assistant : propre au POSTE et à l'AGENT, jamais synchronisée, chiffrée au repos (par le service du poste), conservée 30 jours par défaut puis
/// purgée. La durée est un réglage en base, BORNÉ : une valeur absurde ne peut pas désactiver la purge ni la rendre infinie.
///
/// Ce module est pur : il ne sait ni chiffrer ni écrire — il décide de ce qui reste (la purge) et de la forme de ce qui se garde.
library;

import 'ast_contexte.dart';

/// La clé du réglage dans le registre des paramètres (`definitionsParametres`).
const String astCleRetention = 'assistant.retentionJours';

const int astRetentionDefaut = 30;
const int astRetentionMin = 1;
const int astRetentionMax = 90;

/// Au plus ce nombre de tours gardés par conversation : la purge par l'âge ne suffit pas si un poste pose mille questions par jour.
const int astToursMax = 300;

/// La durée de conservation EN FORCE : le réglage lu, borné à 1–90 jours ; illisible ou hors bornes, la valeur de repli est celle de 30 jours (jamais l'infini).
int astRetentionJours(Object? reglage) {
  final n = reglage is num ? reglage.toInt() : int.tryParse('${reglage ?? ''}'.trim());
  if (n == null || n < astRetentionMin || n > astRetentionMax) return astRetentionDefaut;
  return n;
}

/// Un tour : la question de l'agent et la réponse rendue (qui porte sa source, son motif de refus). Les réponses se rejouent à l'écran telles qu'elles ont été
/// données : on ne les recalcule pas, car la donnée a pu changer depuis (et un historique non conservé reste « non calculable »).
class TourAst {
  const TourAst({required this.id, required this.quand, required this.question, required this.reponse});
  final String id;

  /// Instant ISO 8601 UTC.
  final String quand;
  final String question;
  final ReponseAst reponse;

  Map<String, Object?> toJson() => {'id': id, 'quand': quand, 'question': question, 'reponse': reponse.toJson()};

  static TourAst? depuisJson(Object? j) {
    if (j is! Map) return null;
    try {
      return TourAst(id: '${j['id']}', quand: '${j['quand']}', question: '${j['question']}', reponse: ReponseAst.depuisJson((j['reponse'] as Map).cast<String, Object?>()));
    } catch (_) {
      return null;
    }
  }
}

/// Les tours encore conservés à [maintenant] : ni plus vieux que [jours], ni au-delà des [astToursMax] derniers. Un tour dont la date est illisible est PURGÉ
/// (on ne garde pas ce qu'on ne sait pas dater).
List<TourAst> astPurger(Iterable<TourAst> tours, DateTime maintenant, int jours) {
  final limite = maintenant.toUtc().subtract(Duration(days: astRetentionJours(jours)));
  final gardes = [
    for (final t in tours)
      if (DateTime.tryParse(t.quand) case final d? when !d.toUtc().isBefore(limite)) t
  ]..sort((a, b) => a.quand.compareTo(b.quand));
  return gardes.length > astToursMax ? gardes.sublist(gardes.length - astToursMax) : gardes;
}
