/// CONFLIT HORS LIGNE SUR UNE MÊME COUVERTURE (décision de la Direction du 16/11/2026).
///
/// Deux fileuls hors ligne qui changent la couverture du MÊME assuré écrivent chacun une couverture « sans fin » : à la reprise, deux couvertures restent ouvertes pour un patient. Jusqu'ici
/// rien ne le disait. Décision : le poste DÉTECTE (à chaque application d'opérations), le dit à la DAF sans bloquer personne, et en attendant la prise en charge (RG-09) lit la couverture dont
/// le début est le plus RÉCENT — jamais deux en même temps (`couvertureALaDate`). L'arbitrage est un geste nommé : CLORE l'une des deux, avec un motif (RG-12). Aucune couverture n'est
/// supprimée ni archivée : la couverture close reste écrite, lisible, rattachée à ce qui a été facturé sous elle.
///
/// Les fiches sont passées en ARGUMENT ; aucune lecture d'une base, aucune horloge.
library;

import '../format/format_fr.dart' show dateFR, iso;
import 'ass_regles.dart' show assDate;

typedef _Fiche = Map<String, Object?>;

bool _plein(Object? v) => v != null && v != '' && v != 0 && v != false;

/// Les groupes de couvertures OUVERTES (actives, sans fin) d'un même patient quand il y en a plusieurs. Un groupe par patient en conflit, ses couvertures de la plus récente (début) à la plus
/// ancienne ; à début égal, la dernière dans l'ordre des fiches passe d'abord (même départage que la lecture).
List<List<_Fiche>> assCouverturesEnConflit(Iterable<_Fiche> couvertures) {
  final parPatient = <String, List<(int, _Fiche)>>{};
  var i = 0;
  for (final c in couvertures) {
    final rang = i++;
    if (c['statut'] == 'archive' || _plein(c['fin']) || !_plein(c['patientId'])) continue;
    (parPatient['${c['patientId']}'] ??= []).add((rang, c));
  }
  return [
    for (final l in parPatient.values)
      if (l.length > 1)
        [
          for (final x in (l..sort((a, b) {
            final c = '${b.$2['debut'] ?? '0000-00-00'}'.compareTo('${a.$2['debut'] ?? '0000-00-00'}');
            return c != 0 ? c : b.$1.compareTo(a.$1);
          })))
            x.$2
        ]
  ];
}

/// Ce que l'arbitrage rend : un refus nommé, ou la modification à écrire.
class AssArbitrageCouverture {
  const AssArbitrageCouverture.refus(String this.code, String this.motif, String this.geste)
      : ok = false,
        cloreId = null,
        gardeeId = null,
        fin = null,
        trace = null,
        majPatient = null;
  const AssArbitrageCouverture.ok({required String this.cloreId, required String this.gardeeId, required String this.fin, required Map<String, Object?> this.trace, required Map<String, Object?> this.majPatient})
      : ok = true,
        code = null,
        motif = null,
        geste = null;
  final bool ok;
  final String? code, motif, geste, cloreId, gardeeId, fin;

  /// Les champs à écrire sur la couverture close (`fin`, motif, auteur, date de l'arbitrage).
  final Map<String, Object?>? trace;

  /// La fiche du dossier suit la couverture en force aujourd'hui (même doctrine que le changement de couverture).
  final Map<String, Object?>? majPatient;
}

/// ARBITRE un conflit : clôt la couverture [cloreId] de ce patient. [couvertures] : toutes les couvertures actives du patient ; [jour] : date ISO du jour (la fiche du dossier suit la couverture
/// en force à ce jour). Refus nommés : `MOTIF_REQUIS`, `COUVERTURE_INCONNUE`, `PAS_DE_CONFLIT` (une seule couverture ouverte : rien à arbitrer, une couverture seule ne se clôt pas ici).
///
/// La fin posée : la VEILLE du début de la couverture gardée quand la close est plus ancienne (la suite normale d'un changement de couverture) ; la veille de SON propre début quand elle est plus
/// récente que la gardée (elle n'aura jamais été en force : on garde sa fiche, on ne l'efface pas).
AssArbitrageCouverture assArbitrerCouverture(_Fiche? patient, Iterable<_Fiche> couvertures, {required Object? cloreId, required String motif, required String jour, String? auteur}) {
  if (motif.trim().isEmpty) {
    return const AssArbitrageCouverture.refus('MOTIF_REQUIS', 'le motif de l’arbitrage est obligatoire (RG-12) : on le relit quand une compagnie conteste', 'Dites pourquoi cette couverture est close.');
  }
  final propres = [for (final c in couvertures) if (c['statut'] != 'archive' && patient != null && c['patientId'] == patient['id']) c];
  final groupe = assCouverturesEnConflit(propres).firstOrNull;
  final cible = propres.where((c) => c['id'] == cloreId).firstOrNull;
  if (cible == null) {
    return const AssArbitrageCouverture.refus('COUVERTURE_INCONNUE', 'cette couverture n’existe pas pour ce patient', 'Choisissez une des couvertures ouvertes du patient.');
  }
  if (groupe == null || !groupe.any((c) => c['id'] == cible['id'])) {
    return const AssArbitrageCouverture.refus('PAS_DE_CONFLIT', 'une seule couverture est ouverte pour ce patient : rien à arbitrer', 'Pour changer de couverture, utilisez « Mettre à jour la couverture » (date d’effet et motif).');
  }
  final gardee = groupe.firstWhere((c) => c['id'] != cible['id']);
  final dc = '${cible['debut'] ?? ''}', dg = '${gardee['debut'] ?? ''}';
  String veille(String d) => iso(assDate(d).subtract(const Duration(days: 1)));
  final fin = dc.compareTo(dg) < 0 ? veille(dg) : (dc.isNotEmpty ? veille(dc) : veille(jour));
  // La fiche du dossier : la couverture en force à ce jour dans l'historique APRÈS l'arbitrage.
  final apres = [for (final c in propres) c['id'] == cible['id'] ? {...c, 'fin': fin} : c];
  final tries = [...apres]..sort((a, b) => '${b['debut'] ?? '0000-00-00'}'.compareTo('${a['debut'] ?? '0000-00-00'}'));
  _Fiche e = const {};
  for (final c in tries) {
    if (_plein(c['debut']) && jour.compareTo('${c['debut']}') < 0) continue;
    if (_plein(c['fin']) && jour.compareTo('${c['fin']}') > 0) continue;
    e = c;
    break;
  }
  Object? v(String k) => _plein(e[k]) ? e[k] : null;
  return AssArbitrageCouverture.ok(
    cloreId: '${cible['id']}',
    gardeeId: '${gardee['id']}',
    fin: fin,
    trace: {
      'fin': fin,
      'arbitrage': motif.trim(),
      'arbitrePar': auteur ?? '',
      'arbitreLe': jour,
      'arbitrageGardee': '${gardee['id']}',
    },
    majPatient: {
      'assureur': v('assureur'),
      'assureurNom': v('assureurNom'),
      'numeroPolice': v('numeroPolice'),
      'categorieAssurance': v('categorieAssurance'),
      'tauxPriseEnCharge': _plein(e['tauxPriseEnCharge']) ? e['tauxPriseEnCharge'] : 0,
      'carteExpiration': v('carteExpiration'),
      'souscripteurId': v('souscripteurId'),
    },
  );
}

/// Le texte d'une ligne d'alerte pour un conflit : les couvertures nommées, la plus récente en tête (c'est celle que RG-09 lit en attendant).
String assLibelleConflitCouverture(List<_Fiche> groupe) {
  String nom(_Fiche c) => '${c['assureurNom'] ?? c['assureur'] ?? '?'}${_plein(c['numeroPolice']) ? ' (police ${c['numeroPolice']})' : ''} depuis le ${_plein(c['debut']) ? dateFR(assDate(c['debut'])) : 'l’ouverture du dossier'}';
  return groupe.map(nom).join(' ; ');
}
