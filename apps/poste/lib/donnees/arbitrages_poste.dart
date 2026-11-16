import 'package:sigh_domaine/sigh_domaine.dart';

import 'magasin.dart';

/// LES ARBITRAGES DU CENTRE DES VALIDATIONS (décisions de la Direction du 16/11/2026) : ce que le poste lit et écrit pour les CONFLITS DE COUVERTURE. Le domaine décide (`assArbitrerCouverture`) ;
/// ici on lit les fiches, on écrit ce qu'il rend et on journalise (RG-12). Les prix en doublon ont leur geste dans `TarifsPoste.arbitrerDoublon` (la mère seule écrit les prix).
class ArbitragesPoste {
  /// Les patients dont plusieurs couvertures sont ouvertes (sans fin) : à arbitrer. Jamais bloquant : la prise en charge lit la couverture au début le plus récent en attendant.
  static List<List<Fiche>> conflitsCouverture(Magasin m) => assCouverturesEnConflit(m.collection('couverturesAssurance').actives);

  /// CLORE la couverture [cloreId] du patient [patientId] avec un motif. Rend `null` quand c'est fait, sinon le refus nommé (rien n'est écrit). La couverture close reste écrite (RG-14) ; la fiche du dossier
  /// suit la couverture en force aujourd'hui, comme au changement de couverture.
  static ({String code, String motif, String geste})? arbitrerCouverture(Magasin m, {required Object? patientId, required Object? cloreId, required String motif, required String jour, required String auteur}) {
    final patient = m.collection('patients').parId(patientId);
    final propres = [for (final c in m.collection('couverturesAssurance').actives) if (c['patientId'] == patientId) c];
    final r = assArbitrerCouverture(patient, propres, cloreId: cloreId, motif: motif, jour: jour, auteur: auteur);
    if (!r.ok) return (code: r.code!, motif: r.motif!, geste: r.geste!);
    m.collection('couverturesAssurance').mettreAJour(r.cloreId, r.trace!, journaliser: false);
    if (patient != null) m.collection('patients').mettreAJour(patientId, r.majPatient!, journaliser: false);
    m.journaliser('Arbitrage d’un conflit de couverture', 'M9', 'Couverture', '${r.cloreId}', null, {
      'patient': '${patient?['code'] ?? patientId}',
      'close': '${r.cloreId}',
      'gardée': '${r.gardeeId}',
      'fin': r.fin,
      'par': auteur,
      'motif': motif.trim().length > 60 ? motif.trim().substring(0, 60) : motif.trim(),
    });
    return null;
  }
}
