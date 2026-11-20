/// LES CODES SANS PRIX, MESURÉS ET CLASSÉS PAR CAUSE (décision de la Direction du 16/11/2026, « les 199 codes d'actes à 0 »).
///
/// Un code sans prix en vigueur n'est JAMAIS une ligne à 0 : toute voie de prescription ou de facturation rend « prix à définir » et refuse la ligne en la nommant (`TARIF_A_VALIDER`). Ce fichier ne valorise
/// rien : il dit POURQUOI un code n'a pas de prix, afin que la Direction sache quoi faire (tarifer, valider, choisir une variante, trancher un doublon). Fonctions pures : le référentiel est passé en argument.
library;

import 'tarifs.dart';

/// Les causes, de la plus précise à la plus générale, avec le libellé que lit la Direction.
const Map<String, String> tarCausesSansPrix = {
  'distincte': 'Prestation distincte : code nouveau à valider',
  'variante': 'Variante de grille : la grille décline cette prestation, la clinique doit choisir',
  'non_valide': 'Tarif non validé : une proposition attend le Oui de la Direction',
  'a_venir': 'Tarif à venir : la première version prend effet plus tard',
  'refuse': 'Tarif refusé ou retiré : aucune version en vigueur',
  'prix_manquant': 'Version en vigueur sans prix non assuré (valeur manquante)',
  'jamais_tarife': 'Jamais tarifé : aucune version de prix n’a été proposée',
  'hors_referentiel': 'Code connu d’une liste mais sans prestation au référentiel de prix',
};

/// Un prix est-il en vigueur à ce jour pour cette prestation ? `null` : oui (rien à classer). Sinon la clé de [tarCausesSansPrix].
String? tarCauseSansPrix(ReferentielTarifs h, FicheTarif p, String jour) {
  final s = h.instantane(p, jour);
  if (s != null && s.na != null) return null;
  if (s != null) return 'prix_manquant';
  final code = '${p['code']}';
  final vs = h.versionsDe(code);
  if (p['distinctDe'] != null && !vs.any((v) => v['statut'] == 'valide')) return 'distincte';
  if (vs.isEmpty) {
    final variantes = p['variantesGrille'];
    return variantes is List && variantes.isNotEmpty ? 'variante' : 'jamais_tarife';
  }
  if (vs.any((v) => v['statut'] == 'propose')) return 'non_valide';
  if (vs.any((v) => v['statut'] == 'valide')) return 'a_venir';
  return 'refuse';
}

/// Le relevé : par cause, les codes concernés. [codesDeListes] : les codes que les listes de départ ou les catalogues portent (`actes`, `analyses`, `catalogueTarifs`, `examensImagerie`…) ; ceux qu'aucune
/// prestation du référentiel ne porte (code, alias, espace d'acte, de grille ou d'analyse) sont rangés sous `hors_referentiel`.
class TarReleveSansPrix {
  const TarReleveSansPrix({required this.parCause, required this.prestations, required this.sansPrix});
  final Map<String, List<String>> parCause;

  /// Le nombre de prestations (actives) du référentiel examinées.
  final int prestations;

  /// Le nombre total de codes sans prix en vigueur, toutes causes confondues.
  final int sansPrix;
  int nombre(String cause) => parCause[cause]?.length ?? 0;
}

TarReleveSansPrix tarMesurerSansPrix(ReferentielTarifs h, String jour, {Map<String, Iterable<String>> codesDeListes = const {}}) {
  final par = <String, List<String>>{};
  var n = 0;
  for (final p in h.tarifs) {
    if (p['statut'] == 'archive') continue;
    n++;
    final c = tarCauseSansPrix(h, p, jour);
    if (c != null) (par[c] ??= []).add('${p['code']}');
  }
  final connus = <String>{
    ...h.parCode.keys,
    ...h.parActe.keys,
    ...h.parGrille.keys,
    ...h.parAnalyse.keys,
  };
  for (final e in codesDeListes.entries) {
    for (final code in e.value) {
      if (code.isNotEmpty && !connus.contains(code)) (par['hors_referentiel'] ??= []).add('${e.key}:$code');
    }
  }
  return TarReleveSansPrix(parCause: par, prestations: n, sansPrix: par.values.fold(0, (a, l) => a + l.length));
}

/// Q19 (Direction, 16/11/2026) : les certificats « PRIX UNIQUE, COUVERTURE SOS SEULE » : une prestation de la famille `CERTIFICAT`, couverte par SOS seule, dont la colonne assurée vaut la colonne non assurée (le
/// même prix pour tous). Le relevé les LISTE pour relecture ; chaque ligne est marquée « à valider par la Direction » : rien n'est confirmé à sa place. Aucune écriture, aucun prix valorisé.
List<FicheTarif> tarCertificatsPrixUniqueSos(ReferentielTarifs h, String jour) => [
      for (final p in h.tarifs)
        if (p['statut'] != 'archive' && p['famille'] == 'CERTIFICAT' && p['assurable'] == 'sos')
          if (h.instantane(p, jour) case final s? when s.na != null && (s.etatAssure == 'unique' || (s.etatAssure == 'montant' && s.pa == s.na))) p
    ];
