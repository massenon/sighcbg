/// M10 / M11 : UN HONORAIRE DE RÉGIME NE REPAYE PAS UNE PRIME DE LA NOTE NS 132 (Direction de Baguidi, 17/11/2026, point 3 de `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md` § 10 :
/// « jamais de double paiement »).
///
/// Le régime « Incinération des déchets » (5 000 F, mensuel) est un honoraire de RÉGIME ; la note NS 132 verse déjà, à la fonction d'aide-soignant, la prime d'incinération (5 000 F,
/// forfait mensuel). Un aide-soignant qui adopte ce régime à titre INDIVIDUEL (une version de remplacement ou de dérogation) toucherait donc deux fois le même travail : une fois
/// par la grille, une fois par le régime. La règle, SANS NOM DE RÔLE ni montant écrit ici :
///
///  * l'honoraire vient d'une version INDIVIDUELLE (le régime de la catégorie n'est jamais en cause : c'est la grille de la clinique, pas un choix posé pour un agent) ;
///  * il porte sur une vacation dont le TYPE est celui d'une prime de la grille (une vacation ouvre la prime de même identifiant : `incineration`, `garde`, `permanence`…) ;
///  * la prime est du même rythme que l'honoraire (forfait `fixe` ↔ honoraire mensuel, prime `occurrence` ↔ honoraire par occurrence) ;
///  * le MONTANT correspond : l'honoraire est égal à la prime versée à la fonction de l'agent ce jour-là (la grille se lit À LA DATE, comme la paie).
///
/// Un honoraire d'un autre montant n'est pas un doublon : c'est un complément, que la Direction a voulu. La version qui répète la prime est REFUSÉE à la pose
/// (`DOUBLE_PAIEMENT_PRIME`, refus nommé) ; une version déjà posée, ou une prime relevée après coup, est EXCLUE du bulletin avec le même message, au validateur : le bulletin
/// verse la prime de la grille et dit ce qu'il a écarté. Fonctions PURES, sans magasin.
library;

import 'planning_rh.dart';
import 'rhb_regles.dart';

/// Les primes OCCURRENCE que le bulletin et l'écran des primes versent d'après le planning (une par garde, une par permanence) ; les primes FIXES se versent chaque mois. C'est la règle
/// du moteur de paie (`paiCalculer`) et de `rhbPrimesAcquises` : une prime qu'ils ne versent pas ne peut être « répétée » par un honoraire.
const List<String> primesAuComptageDuPlanningRh = ['garde', 'permanence'];

/// Le code du refus (pose d'une version) et de l'exclusion (bulletin).
const String codeDoublePaiementPrime = 'DOUBLE_PAIEMENT_PRIME';

/// Ce qu'une répétition nomme : de quelle prime, de quelle vacation, à quel jour, pour quel montant.
class DoublePaiementPrime {
  const DoublePaiementPrime({required this.primeId, required this.primeLibelle, required this.vacation, required this.montant, required this.periodicite, required this.jour});

  /// La prime de la grille NS 132 déjà versée (son identifiant) et son libellé.
  final String primeId, primeLibelle;

  /// Le type de vacation qui ouvre à la fois l'honoraire et la prime.
  final String vacation;

  /// Le montant commun, la périodicité de l'honoraire (`mensuelle` ou `occurrence`) et le jour de la vacation (ou de la prise d'effet de la version).
  final num montant;
  final String periodicite, jour;

  Map<String, Object?> toJson() =>
      {'code': codeDoublePaiementPrime, 'prime': primeId, 'primeLibelle': primeLibelle, 'vacation': vacation, 'montant': montant, 'periodicite': periodicite, 'jour': jour};

  /// Une phrase qui NOMME la prime, la vacation, le montant et le jour (la lecture du validateur ne demande aucune autre pièce).
  String phrase() =>
      'l’honoraire de ${_montant(montant)} F ${periodicite == 'occurrence' ? '(par occurrence)' : '(mensuel)'} de la vacation « ${rhbTypePlanningLabel(vacation)} » répète la prime « $primeLibelle » de la note NS 132, '
      'de même montant, déjà versée à l’agent pour la même vacation au ${_dateFr(jour)}';
}

String _montant(num n) => n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

String _dateFr(String iso) {
  final p = iso.length >= 10 ? iso.substring(0, 10).split('-') : const <String>[];
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

/// La répétition d'UNE ligne d'honoraire (vacation de type [vacation], honoraire [honoraire] de périodicité [periodicite], le [jour]) avec une prime de la grille, ou `null`.
/// [primes] : les primes de la grille (`rhbPrimesALaDate`) ; [montantPrime] : le montant UNITAIRE que la prime de cet identifiant verse à l'agent ce jour-là (0 : aucune
/// prime versée) — la grille à la date à la pose, la ligne réellement portée au bulletin à la paie.
DoublePaiementPrime? doublePaiementPrimeRh({
  required String vacation,
  required num honoraire,
  required String periodicite,
  required String jour,
  required Iterable<RhbPrimeDef> primes,
  required num Function(String primeId) montantPrime,
}) {
  if (honoraire <= 0) return null;
  for (final p in primes) {
    if (p.id != vacation) continue;
    final memeRythme = periodicite == 'occurrence' ? p.mode == 'occurrence' : p.mode == 'fixe';
    if (!memeRythme) continue;
    if (p.mode == 'occurrence' && !primesAuComptageDuPlanningRh.contains(p.id)) continue;
    final m = montantPrime(p.id);
    if (m > 0 && m == honoraire) {
      return DoublePaiementPrime(primeId: p.id, primeLibelle: p.label, vacation: vacation, montant: m, periodicite: periodicite, jour: jour);
    }
  }
  return null;
}

/// La répétition portée par UNE ligne d'honoraire (`honoraireRegimeMoisRh` : `date`, `type`, `montant`, `periodicite`, `provenance`), ou `null`. Seul un honoraire d'une version
/// INDIVIDUELLE est en cause : le régime de la catégorie est la grille de la clinique. [montantPrime] reçoit l'identifiant de la prime et le jour de la vacation.
DoublePaiementPrime? doublePaiementLigneRh(Map<String, Object?> ligne, {required Iterable<RhbPrimeDef> primes, required num Function(String primeId, String jour) montantPrime}) {
  final p = ligne['provenance'];
  if (p != provenanceIndividuelleRh && p != provenanceRemplacementRh) return null;
  final jour = '${ligne['date']}';
  return doublePaiementPrimeRh(
      vacation: '${ligne['type']}',
      honoraire: ligne['montant'] as num,
      periodicite: '${ligne['periodicite']}',
      jour: jour,
      primes: primes,
      montantPrime: (id) => montantPrime(id, jour));
}

/// LE CONTRÔLE À LA POSE d'une version de régime individuel : [regime] est le régime EFFECTIF de l'agent à la prise d'effet, version comprise. Seul un honoraire qui vient de la
/// version (individuel ou remplacement) est en cause. Rend le refus nommé, ou `null`.
RefusRh? controlerDoublePaiementPrimeRh({
  required RegimeRhResolu regime,
  required String jour,
  required Iterable<RhbPrimeDef> primes,
  required num Function(String primeId) montantPrime,
}) {
  final h = regime.honoraire;
  if (h == null || h <= 0) return null;
  final p = regime.provenances['honoraire'];
  if (p != provenanceIndividuelleRh && p != provenanceRemplacementRh) return null;
  final per = regime.honorairePeriodicite == 'occurrence' ? 'occurrence' : 'mensuelle';
  for (final v in regime.vacations) {
    final d = doublePaiementPrimeRh(vacation: v, honoraire: h, periodicite: per, jour: jour, primes: primes, montantPrime: montantPrime);
    if (d != null) {
      return RefusRh(
          codeDoublePaiementPrime,
          'Version refusée : ${d.phrase()}. Un même travail ne se paie pas deux fois.',
          'Retirer l’honoraire de la version (la prime de la grille reste due), ou fixer un honoraire d’un autre montant s’il s’agit d’un complément voulu.',
          d.toJson());
    }
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------
// CHEVAUCHEMENT ÉCONOMIQUE : même agent, même vacation, un honoraire de régime individuel ET une prime NS 132 — de MONTANT DIFFÉRENT.
// ---------------------------------------------------------------------------------------------------------------------

/// Le code de l'avertissement (jamais un refus : la décision du 17/11/2026 ne refuse que la RÉPÉTITION exacte ; un honoraire d'un autre montant est un complément que la Direction a pu vouloir).
const String codeChevauchementPrime = 'CHEVAUCHEMENT_PRIME';

/// Un honoraire de régime individuel qui s'ajoute, pour la même vacation, à une prime de la grille NS 132 versée sur le même bulletin, sans la répéter. Le validateur le LIT avant de
/// signer ; rien n'est exclu ni refusé : [honoraire] et [prime] sont versés tous deux. Une entrée groupe les vacations de même type, de même prime et de même honoraire du mois.
class ChevauchementPrime {
  const ChevauchementPrime(
      {required this.primeId, required this.primeLibelle, required this.vacation, required this.honoraire, required this.prime, required this.periodiciteHonoraire, required this.jours});
  final String primeId, primeLibelle, vacation, periodiciteHonoraire;
  final num honoraire, prime;

  /// Les jours (ISO) des vacations concernées.
  final List<String> jours;

  Map<String, Object?> toJson() => {
        'code': codeChevauchementPrime,
        'prime': primeId,
        'primeLibelle': primeLibelle,
        'vacation': vacation,
        'honoraire': honoraire,
        'montantPrime': prime,
        'periodicite': periodiciteHonoraire,
        'jours': jours,
      };

  /// La phrase du validateur : nomme la prime, la vacation, les deux montants et le nombre de vacations ; dit que les DEUX sont versés.
  String phrase() =>
      '${jours.length} vacation(s) « ${rhbTypePlanningLabel(vacation)} » : l’honoraire du régime individuel (${_montant(honoraire)} F ${periodiciteHonoraire == 'occurrence' ? 'par occurrence' : 'mensuel'}) '
      's’ajoute à la prime « $primeLibelle » de la note NS 132 (${_montant(prime)} F), de montant différent — les deux sont versés. À confirmer comme complément voulu.';
}

/// Les chevauchements des [lignes] d'honoraire RETENUES au bulletin (`honoraireRegimeMoisRh().lignes`, celles que le doublon exact n'a pas écartées). Seul un honoraire d'une version
/// INDIVIDUELLE (ou de remplacement) est en cause, jamais le régime de la catégorie. [primes] : les primes de la grille ; [montantPrime] : le montant UNITAIRE versé ce jour-là
/// pour la prime de cet identifiant (0 : aucune prime versée, donc rien à chevaucher). Une prime d'occurrence ne compte que si le planning la verse (`primesAuComptageDuPlanningRh`).
/// Un honoraire MENSUEL est une ligne par mois : ses jours sont ceux des vacations qui l'ouvrent.
List<ChevauchementPrime> chevauchementsPrimeLignesRh(Iterable<Map<String, Object?>> lignes,
    {required Iterable<RhbPrimeDef> primes, required num Function(String primeId, String jour) montantPrime}) {
  final groupes = <String, ChevauchementPrime>{};
  for (final l in lignes) {
    final prov = l['provenance'];
    if (prov != provenanceIndividuelleRh && prov != provenanceRemplacementRh) continue;
    final type = '${l['type']}';
    final jour = '${l['date']}';
    final honoraire = l['montant'];
    if (honoraire is! num || honoraire <= 0) continue;
    for (final p in primes) {
      if (p.id != type) continue;
      if (p.mode == 'occurrence' && !primesAuComptageDuPlanningRh.contains(p.id)) continue;
      final m = montantPrime(p.id, jour);
      if (m <= 0) continue;
      final per = '${l['periodicite']}' == 'occurrence' ? 'occurrence' : 'mensuelle';
      final k = '${p.id}/$type/$per/$honoraire/$m';
      final g = groupes[k];
      groupes[k] = ChevauchementPrime(
          primeId: p.id, primeLibelle: p.label, vacation: type, honoraire: honoraire, prime: m, periodiciteHonoraire: per, jours: [...?g?.jours, jour]);
    }
  }
  return groupes.values.toList();
}
