/// ÉCHÉANCES FISCALES & PAIEMENTS (M12, `m12-echeances`) — port de `m12-comptabilite.js` (vague 22) rejoué sur `test/vecteurs/echeances.json`.
///
/// Le calendrier fiscal donne les obligations ; l'écran les déroule sur l'exercice et suit leur état : payée · en retard · à payer (sous dix jours) ·
/// déclaration attendue (sous trente jours, quand une déclaration précède le paiement) · à venir. L'état est CALCULÉ à chaque lecture, jamais stocké.
/// Une échéance dépassée et non réglée est un risque de pénalité : elle est SIGNALÉE à l'ouverture, pas seulement listée.
/// Une échéance qui tombe un samedi ou un dimanche est reportée au jour ouvrable SUIVANT, jamais avancée.
library;

import '../format/format_fr.dart';
import '../format/js.dart';
import 'cpa_referentiels.dart' show CpaFiche;

/// `ETATS_ECHEANCE` : (identifiant, libellé, ton) dans l'ordre de la maquette.
const List<(String, String, String)> cpcEtatsEcheance = [
  ('payee', 'Payée', 'succes'),
  ('en_retard', 'En retard', 'danger'),
  ('a_payer', 'À payer', 'attention'),
  ('declaration', 'Déclaration attendue', 'info'),
  ('a_venir', 'À venir', 'neutre'),
];

/// LES SEUILS de l'état d'une échéance : « à payer » sous [aPayerJours] jours, « déclaration attendue » sous [declarationJours]. Ce ne sont PAS des constantes du
/// moteur : ils se règlent aux Paramètres (`fiscal.delaiAPayerJours`, `fiscal.delaiDeclarationJours`, valeur en vigueur à la date) et le moteur les REÇOIT.
/// [defaut] (10 et 30) n'est que la graine, valeur de repli d'un poste dont le paramètre n'est pas lu. Un délai absurde (négatif, ou de déclaration inférieur à
/// celui du paiement) est ramené à une valeur cohérente plutôt que de renverser l'ordre des états.
class CpcSeuilsEcheance {
  const CpcSeuilsEcheance({this.aPayerJours = 10, this.declarationJours = 30});
  final int aPayerJours;
  final int declarationJours;

  static const CpcSeuilsEcheance defaut = CpcSeuilsEcheance();

  factory CpcSeuilsEcheance.depuis(Object? aPayer, Object? declaration) {
    int lire(Object? v, int repli) => v is num && v.isFinite && v >= 0 ? v.toInt() : repli;
    final a = lire(aPayer, defaut.aPayerJours);
    final d = lire(declaration, defaut.declarationJours);
    return CpcSeuilsEcheance(aPayerJours: a, declarationJours: d < a ? a : d);
  }
}

(String, String, String) cpcEtat(String id) =>
    cpcEtatsEcheance.firstWhere((e) => e.$1 == id, orElse: () => cpcEtatsEcheance.last);

/// `jourOuvrableSuivant(d)` : tant que la date tombe un samedi ou un dimanche, on avance d'un jour.
DateTime cpcJourOuvrableSuivant(DateTime d) {
  var x = d;
  while (x.weekday == DateTime.saturday || x.weekday == DateTime.sunday) {
    x = DateTime(x.year, x.month, x.day + 1, x.hour, x.minute, x.second);
  }
  return x;
}

/// `C.daysBetween(auj, echeance)` : `Math.round((échéance − aujourd'hui) / 86 400 000)`.
int cpcJoursAvant(DateTime auj, Object? echeance) {
  final d = DateTime.tryParse('${echeance ?? ''}');
  if (d == null) return 0;
  return arrondiJs(d.difference(auj).inMilliseconds / 86400000).toInt();
}

/// `calculerEtat(e)` : jamais stocké, toujours recalculé.
String cpcCalculerEtat(CpaFiche e, DateTime auj, {CpcSeuilsEcheance seuils = CpcSeuilsEcheance.defaut}) {
  if (e['paye'] == true) return 'payee';
  final j = cpcJoursAvant(auj, e['echeance']);
  if (j < 0) return 'en_retard';
  if (j <= seuils.aPayerJours) return 'a_payer';
  final decl = e['declaration'];
  if (decl != null && decl != '' && j <= seuils.declarationJours) return 'declaration';
  return 'a_venir';
}

/// Les lignes du tableau : la fiche, son état calculé et son délai.
List<CpaFiche> cpcLignesEcheances(Iterable<CpaFiche> actives, DateTime auj, {CpcSeuilsEcheance seuils = CpcSeuilsEcheance.defaut}) => [
      for (final e in actives) {...e, 'etat': cpcCalculerEtat(e, auj, seuils: seuils), 'jours': cpcJoursAvant(auj, e['echeance'])}
    ];

String _date(Object? d) {
  final x = DateTime.tryParse('${d ?? ''}');
  return x == null ? '' : dateFR(x);
}

/// Le délai en toutes lettres quand il vaut dix (le texte historique de la maquette), en chiffres sinon : « sous dix jours », « sous 7 jours ».
String _delai(int jours) => jours == 10 ? 'dix jours' : '$jours jours';

/// Une carte de la barre de notification : ce que la Direction demandait — être prévenu, pas devoir chercher.
class CpcAlerteEcheance {
  const CpcAlerteEcheance(this.ton, this.titre, this.detail, this.cible);
  final String ton; // danger · warning · info · success
  final String titre, detail;

  /// L'échéance que le bouton « Valider le paiement » vise (retard et paiement proche seulement).
  final CpaFiche? cible;
}

/// La barre de notification de l'écran, dans l'ordre de la maquette : retards, paiements sous dix jours, déclarations ; sinon « Aucune échéance en attente ».
List<CpcAlerteEcheance> cpcBarreEcheances(List<CpaFiche> lignes, {CpcSeuilsEcheance seuils = CpcSeuilsEcheance.defaut}) {
  final retard = [for (final e in lignes) if (e['etat'] == 'en_retard') e];
  final aPayer = [for (final e in lignes) if (e['etat'] == 'a_payer') e];
  final decl = [for (final e in lignes) if (e['etat'] == 'declaration') e];
  final out = <CpcAlerteEcheance>[];
  if (retard.isNotEmpty) {
    out.add(CpcAlerteEcheance(
        'danger',
        '${retard.length} échéance(s) dépassée(s) et non réglée(s)',
        '${retard.take(3).map((e) => '${e['code']} — ${_date(e['echeance'])} (${(e['jours'] as int).abs()} j de retard)').join(' · ')}${retard.length > 3 ? ' …' : ''}',
        retard.first));
  }
  if (aPayer.isNotEmpty) {
    out.add(CpcAlerteEcheance(
        'warning',
        '${aPayer.length} paiement(s) à effectuer sous ${_delai(seuils.aPayerJours)}',
        '${aPayer.take(3).map((e) => '${e['code']} le ${_date(e['echeance'])}').join(' · ')}${aPayer.length > 3 ? ' …' : ''}',
        aPayer.first));
  }
  if (decl.isNotEmpty) {
    out.add(CpcAlerteEcheance('info', '${decl.length} déclaration(s) à préparer',
        'Une déclaration précède le paiement : ${decl.take(2).map((e) => '${e['code']} — ${e['declaration']}').join(' · ')}', null));
  }
  if (retard.isEmpty && aPayer.isEmpty && decl.isEmpty) {
    // E804 (corrigé dans la maquette d'abord) : la date se formate comme les autres, et « tout est réglé » se dit au lieu d'écrire « undefined ».
    final prochaines = [for (final e in lignes) if ((e['jours'] as int) >= 0 && e['paye'] != true) e]
      ..sort((a, b) => (a['jours'] as int).compareTo(b['jours'] as int));
    out.add(CpcAlerteEcheance(
        'success',
        'Aucune échéance en attente immédiate',
        prochaines.isNotEmpty
            ? 'La prochaine obligation tombe le ${_date(prochaines.first['echeance'])}'
            : 'Toutes les échéances de l’exercice sont réglées.',
        null));
  }
  return out;
}

/// L'alerte SONORE de l'ouverture : le comptable ne consulte pas l'écran tous les jours, c'est l'écran qui doit l'avertir. `null` s'il n'y a ni retard ni
/// paiement sous dix jours.
({String message, String son, String type, String detail})? cpcAlerteOuverture(List<CpaFiche> lignes, {CpcSeuilsEcheance seuils = CpcSeuilsEcheance.defaut}) {
  final retard = [for (final e in lignes) if (e['etat'] == 'en_retard') e];
  final aPayer = [for (final e in lignes) if (e['etat'] == 'a_payer') e];
  if (retard.isEmpty && aPayer.isEmpty) return null;
  final premier = retard.isNotEmpty ? retard.first : aPayer.first;
  return (
    message: retard.isNotEmpty ? '${retard.length} échéance(s) en retard' : '${aPayer.length} paiement(s) sous ${_delai(seuils.aPayerJours)}',
    son: retard.isNotEmpty ? 'alerte' : 'rappel',
    type: retard.isNotEmpty ? 'error' : 'warning',
    detail: '${premier['libelle']} — ${_date(premier['echeance'])}',
  );
}

/// Le rappel d'une échéance (`rappeler(e)`).
({String message, String detail}) cpcRappel(CpaFiche e) {
  final j = e['jours'] as int;
  final decl = e['declaration'];
  return (
    message: 'Rappel — ${e['libelle']}',
    detail:
        'Échéance du ${_date(e['echeance'])}${decl != null && decl != '' ? ' · $decl' : ''}${j >= 0 ? ' · dans $j jour(s)' : ' · dépassée de ${j.abs()} jour(s)'}',
  );
}

/// Le patch d'un paiement validé : son auteur, sa date, son montant et sa référence de quittance (RG-12). La saisie vide de l'observation s'écrit `null`.
CpaFiche cpcPatchPaiement(
        {required String datePaiement, required num montant, required String moyen, required String reference, required String valideePar, String? observation}) =>
    {
      'paye': true,
      'datePaiement': datePaiement,
      'montant': montant,
      'moyen': moyen,
      'reference': reference,
      'valideePar': valideePar,
      'observation': observation == null || observation.isEmpty ? null : observation,
    };

/// Le patch d'une validation annulée : l'échéance redevient due, le motif est consigné — la trace du paiement initial reste au journal d'audit.
CpaFiche cpcPatchAnnulation(String motif) => {
      'paye': false,
      'datePaiement': null,
      'montant': null,
      'reference': null,
      'valideePar': null,
      'motifAnnulation': motif,
    };

const List<String> cpcMoyensReglement = ['Virement bancaire', 'Chèque', 'Espèces', 'Mobile Money'];
