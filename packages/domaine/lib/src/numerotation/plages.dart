/// LES PLAGES DE NUMÉROS, PAR SÉRIE ET PAR ANNÉE (Direction de Baguidi, 17/11/2026 : « reliquats de numérotation »).
///
/// Une plage est un bloc de rangs CONSÉCUTIFS que la MÈRE attribue à un poste (la mère comprise) pour qu'il numérote hors ligne sans jamais produire le numéro d'un autre poste. Trois règles, toutes
/// pures (le poste, la mère Dart et le banc Node les rejouent à l'identique) :
///  * une plage appartient à UNE SÉRIE et à UNE ANNÉE : une série à remise annuelle repart à 1 chaque année, un rang d'une plage 2026 ne numérote donc jamais une pièce de 2027 ;
///  * deux plages d'une même série et d'une même année ne se chevauchent JAMAIS : un chevauchement est refusé EN NOMMANT la plage en cause et son poste ([refusChevauchementPlage]) ;
///  * la reprise se fait au PLUS GRAND RANG + 1 (archives comprises, un numéro ne se réutilise jamais) : [debutProchainePlage].
///
/// Les plages d'AVANT les séries annuelles n'avaient pas d'année : [rattacherPlagesAnciennes] les rattache à l'année que ce que le poste a DÉJÀ ÉCRIT désigne (les codes attribués dans la plage), jamais à
/// une année devinée, et ne réécrit aucun code attribué (RG-01).
library;

import '../referentiels/regles.dart' show anneeDeSerie, lireCodePatient;

/// Le refus nommé d'une plage (code, motif lisible, geste de correction).
class RefusPlage {
  const RefusPlage(this.code, this.motif, this.geste, [this.extra = const {}]);
  final String code, motif, geste;
  final Map<String, Object?> extra;
  Map<String, Object?> toJson() => {'ok': false, 'code': code, 'motif': motif, 'geste': geste, ...extra};
}

/// Une plage telle que la mère la détient : la série [nom] (`patients`, `besoins`…), l'année ([annee], `null` pour une plage d'avant les séries annuelles), les rangs [debut] à [fin] inclus, le poste
/// ([appareil]).
class PlageNumeros {
  const PlageNumeros({required this.nom, required this.debut, required this.fin, this.annee, this.appareil = ''});
  final String nom;
  final int debut, fin;
  final int? annee;
  final String appareil;

  int get taille => fin - debut + 1;

  /// Lit une ligne de la table des plages (colonnes `nom`, `debut`, `fin`, `annee`, `appareil`) ou une fiche locale.
  static PlageNumeros? depuis(Map<String, Object?> m) {
    final d = _entier(m['debut']), f = _entier(m['fin']);
    if (d == null || f == null) return null;
    return PlageNumeros(nom: '${m['nom'] ?? 'patients'}', debut: d, fin: f, annee: _entier(m['annee']), appareil: '${m['appareil'] ?? ''}');
  }
}

int? _entier(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.split('.').first);

/// La plage demandée [debut]–[fin] de la série [nom] pour l'année [annee] en chevauche-t-elle une déjà attribuée (même série, même année) ? Le refus NOMME la plage et le poste qui la détient.
/// Une plage d'une autre année ou d'une autre série ne chevauche jamais : les séries sont indépendantes.
RefusPlage? refusChevauchementPlage(Iterable<PlageNumeros> existantes, {required String nom, required int? annee, required int debut, required int fin}) {
  if (fin < debut) return const RefusPlage('plage_vide', 'Une plage porte au moins un numéro.', 'Demander une plage d’au moins un numéro');
  for (final p in existantes) {
    if (p.nom != nom || p.annee != annee) continue;
    if (debut <= p.fin && fin >= p.debut) {
      final de = p.appareil.isEmpty ? 'un autre poste' : 'le poste ${p.appareil}';
      return RefusPlage(
          'plage_chevauchement',
          'La plage $debut à $fin de la série « $nom »${annee == null ? '' : ' ($annee)'} chevauche la plage ${p.debut} à ${p.fin} déjà attribuée à $de : deux postes pourraient produire le même numéro.',
          'Reprendre au rang ${debutProchainePlage(existantes, nom: nom, annee: annee) } (le plus grand rang attribué + 1) ou demander une nouvelle plage',
          {'plage': {'debut': p.debut, 'fin': p.fin, 'appareil': p.appareil}});
    }
  }
  return null;
}

/// Le premier rang libre d'une série et d'une année : le plus grand rang des plages déjà attribuées + 1 (1 pour une série neuve), jamais en dessous de [minimum] (le plus grand rang que le poste
/// demandeur connaît lui-même, +1). Un numéro n'est jamais réattribué.
int debutProchainePlage(Iterable<PlageNumeros> existantes, {required String nom, required int? annee, int minimum = 0}) {
  var max = 0;
  for (final p in existantes) {
    if (p.nom == nom && p.annee == annee && p.fin > max) max = p.fin;
  }
  final debut = max + 1;
  return minimum > debut ? minimum : debut;
}

/// L'année que désignent les codes de dossier DÉJÀ ATTRIBUÉS dans la plage [debut]–[fin] : avant les séries annuelles, un compteur unique numérotait tous les dossiers, le rang identifie donc
/// l'année de son code (`CNT/1004/26` : rang 1004, année 2026). `null` : aucun code de la plage n'a été attribué (rien ne désigne l'année), ou les codes de la plage portent plusieurs années
/// (ambiguïté : on ne devine pas). [reference] (l'horloge du poste) donne le siècle des deux chiffres du code, comme `anneeDeSerie`.
int? anneeDesCodesDeLaPlage(int debut, int fin, Iterable<Object?> codes, {required DateTime reference}) {
  final annees = <int>{};
  for (final c in codes) {
    final l = lireCodePatient(c);
    if (l == null || l.rang < debut || l.rang > fin) continue;
    annees.add(anneeDeSerie(l.annee, reference));
  }
  return annees.length == 1 ? annees.single : null;
}

/// Le résultat du rattachement des plages d'avant les séries annuelles : l'année retenue par plage ([rattachees], clé : l'indice de la plage dans la liste donnée) et les plages que rien ne permet de
/// rattacher ([sansAnnee], dites : elles ne codent plus rien, un code provisoire que la mère remplace plutôt qu'une année devinée).
class RattachementPlages {
  const RattachementPlages(this.rattachees, this.sansAnnee);
  final Map<int, int> rattachees;
  final List<int> sansAnnee;
}

/// Rattache à une année les plages de dossiers qui n'en ont pas ([PlageNumeros.annee] `null`). L'année vient des codes déjà attribués dans la plage ([anneeDesCodesDeLaPlage]) ; à défaut, de
/// [anneeParDefaut] SI l'appelant en fournit une (la mère le fait pour une plage qu'elle a elle-même allouée, avant le changement d'année) ; sinon la plage reste sans année et est signalée.
/// Une plage qui a déjà une année n'est jamais touchée. Aucun code n'est réécrit.
RattachementPlages rattacherPlagesAnciennes(List<PlageNumeros> plages, Iterable<Object?> codes, {required DateTime reference, int? anneeParDefaut}) {
  final ok = <int, int>{};
  final non = <int>[];
  for (var i = 0; i < plages.length; i++) {
    final p = plages[i];
    if (p.annee != null) continue;
    final a = anneeDesCodesDeLaPlage(p.debut, p.fin, codes, reference: reference) ?? anneeParDefaut;
    if (a == null) {
      non.add(i);
    } else {
      ok[i] = a;
    }
  }
  return RattachementPlages(ok, non);
}
