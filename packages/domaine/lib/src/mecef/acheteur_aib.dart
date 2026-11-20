/// L'AIB DE LA FENÊTRE « FACTURE NORMALISÉE » LU AU BARÈME DATÉ (lot A5, 09/11/2026).
///
/// La fenêtre proposait trois taux écrits dans le code (0, 1, 5 %). Elle lit désormais le barème de M12 (`situationsAib` + `baremeAib`, moteur
/// `cpdTauxAibALaDate`) : la situation se CHOISIT à la main parmi les situations du barème ; le taux est celui EN VIGUEUR À LA DATE de la facture, avec son motif.
///
/// L'AIB N'EST JAMAIS IMPOSÉE D'OFFICE D'APRÈS L'IFU (Direction de Baguidi, 16/11/2026, §9 « rien en dur ») : ni l'IFU d'un acheteur, d'un assureur ou d'un fournisseur, ni son
/// absence ne choisissent la situation ni le taux. Sans situation choisie, [aibPourAcheteur] REFUSE en le nommant (`AIB_SITUATION_REQUISE`) — aucun défaut silencieux. L'IFU ne
/// sert qu'à vérifier son format et à dire qu'il est présumé actif quand la situation choisie le suppose.
///
/// Trois règles, dans cet ordre de gravité :
///
/// * SEULE UNE VERSION ARRÊTÉE S'APPLIQUE. Un taux non arrêté (1 % et 3 % au barème d'origine) est AFFICHÉ « non arrêté, à valider » et jamais appliqué :
///   sans version arrêtée en vigueur à la date, le résultat est le refus nommé `AIB_SANS_BAREME` du moteur du barème — jamais un taux commode, jamais zéro ;
/// * l'AIB se calcule sur le montant HORS TAXES (`mecefMontants`), en montants entiers : le taux rendu ici est un pourcentage entier ;
/// * aucune écriture comptable : l'AIB du prélèvement DGI reste affiché sur la pièce, sans écriture, jusqu'à confirmation de l'expert-comptable.
library;

import '../comptabilite/cpd_bareme_aib.dart';
import '../comptabilite/cpd_parametres_aib.dart';
import 'montants.dart';

/// Ce que la fenêtre affiche et applique : la situation, le taux arrêté en vigueur (ou le refus nommé), le motif, les taux non arrêtés offerts à la Direction.
class AibAcheteur {
  const AibAcheteur({
    this.situation,
    this.libelle,
    this.taux,
    required this.motif,
    this.choixManuel = false,
    this.presomption = false,
    this.avertissement,
    this.nonArretes = const [],
    this.refus,
  });

  /// Le code de la situation retenue (`ifu_actif`…), `null` si l'IFU est invalide.
  final String? situation;
  final String? libelle;

  /// Le taux ARRÊTÉ en vigueur à la date (pourcentage entier), `null` quand rien ne s'applique.
  final int? taux;

  /// Le motif du moteur du barème (« Taux de 5 % arrêté, en vigueur depuis le 07/09/2026. »), ou la raison du refus.
  final String motif;

  /// La situation a été choisie à la main par l'agent (et non d'office d'après l'IFU).
  final bool choixManuel;

  /// L'IFU saisi est présumé actif : le poste ne peut pas interroger la DGI.
  final bool presomption;
  final String? avertissement;

  /// Les taux de la situation qui figurent au barème sans être arrêtés (« 1 % — non arrêté, à valider ») : offerts, jamais appliqués.
  final List<String> nonArretes;

  /// Le refus nommé (`AIB_SANS_BAREME`, `IFU_INVALIDE`, `AIB_TAUX_INVALIDE`) quand aucun taux ne peut être appliqué.
  final RefusMecef? refus;

  bool get ok => taux != null && refus == null;
}

String _pct(num t) => t == t.roundToDouble() ? '${t.toInt()}' : '$t'.replaceAll('.', ',');

/// Le taux d'AIB de la situation de l'acheteur à [date]. [situationChoisie] vide ou `null` : la situation se déduit de [ifu] ; renseignée, elle
/// l'emporte (choix manuel parmi les situations ACTIVES du barème). Aucun taux n'est écrit ici : tout vient de [situations] et [versions].
///
/// [parametres] (Paramètres de l'AIB, version en vigueur à [date]) porte le BRANCHEMENT : la longueur de l'IFU et les situations présumées. Absents, la graine
/// du moteur ([CpdParametresAib.graine]) tient lieu — l'appelant du poste les lit toujours à la collection `parametresAib`.
///
/// D8 (Direction, 09/11/2026) : ici, sans taux arrêté, le refus nommé `AIB_SANS_BAREME` est GARDÉ (la fenêtre de l'acheteur) — il n'est PAS remplacé par un repli.
/// [ifu] et [parametres] ne choisissent plus rien (la situation ne se déduit plus de l'IFU) : ils restent pour les appelants, sans effet sur le choix.
AibAcheteur aibPourAcheteur({
  Object? ifu,
  Object? situationChoisie,
  required DateTime date,
  required Iterable<CpdFiche> situations,
  required Iterable<CpdFiche> versions,
  CpdParametresAib? parametres,
}) {
  final choisie = '${situationChoisie ?? ''}'.trim();
  final CpdFiche sit;
  var presomption = false;
  String? avertissement;
  if (choisie.isNotEmpty) {
    final t = [for (final s in cpdSituationsActives(situations)) if ('${s['code']}' == choisie) s];
    if (t.isEmpty) {
      return AibAcheteur(
          situation: choisie,
          motif: 'La situation « $choisie » n\'est pas une situation active du barème de l\'AIB.',
          refus: RefusMecef(cpdCodeAibSansBareme, 'La situation « $choisie » n\'est pas une situation active du barème de l\'AIB : aucun taux ne peut être rendu.',
              'Choisir une situation proposée par le barème (Paramètres, « Acompte sur impôt (AIB) »).'));
    }
    sit = t.first;
  } else {
    // AUCUNE situation n'est déduite de l'IFU : le comptable choisit, à chaque opération.
    return AibAcheteur(
        motif: 'Aucune situation d\'AIB choisie : l\'IFU ne choisit rien d\'office.',
        refus: const RefusMecef('AIB_SITUATION_REQUISE', 'Aucune situation d\'AIB n\'est choisie : l\'IFU de l\'acheteur, saisi ou absent, ne choisit ni la situation ni le taux (aucun défaut silencieux).',
            'Choisir la situation de l\'acheteur parmi celles du barème de l\'AIB (Paramètres, « Acompte sur impôt (AIB) »).'));
  }
  if (choisie.isNotEmpty && '${sit['declencheur']}' == cpdDeclencheurIfuRenseigne) {
    presomption = true;
    avertissement = 'IFU présumé actif : l\'activité de l\'IFU n\'est pas vérifiée auprès de la DGI.';
  }
  final code = '${sit['code']}';
  final libelle = '${sit['libelle'] ?? code}';
  final rep = cpdTauxAibALaDate(versions, code, date, situations: situations);
  final nonArretes = [for (final f in rep.enAttente) '${_pct(_numTaux(f['taux']) ?? 0)} % — non arrêté, à valider'];
  if (!rep.ok) {
    final attente = nonArretes.isEmpty ? '' : ' Au barème, sans être arrêté : ${nonArretes.join(' ; ')}.';
    return AibAcheteur(
        situation: code,
        libelle: libelle,
        motif: rep.motif,
        choixManuel: choisie.isNotEmpty,
        presomption: presomption,
        avertissement: avertissement,
        nonArretes: nonArretes,
        refus: RefusMecef(rep.code ?? cpdCodeAibSansBareme, '${rep.motif}$attente',
            'La Direction arrête le taux (Paramètres, « Acompte sur impôt (AIB) »), ou choisir une autre situation du barème : un taux non arrêté ne s\'applique pas.'));
  }
  final t = rep.taux!;
  if (t != t.roundToDouble() || t < 0 || t > 100) {
    return AibAcheteur(
        situation: code,
        libelle: libelle,
        motif: 'Le taux du barème (${_pct(t)} %) n\'est pas un pourcentage entier : le poste calcule en montants entiers.',
        choixManuel: choisie.isNotEmpty,
        refus: RefusMecef('AIB_TAUX_INVALIDE', 'Le taux du barème (${_pct(t)} %) n\'est pas un pourcentage entier.', 'Corriger le barème de l\'AIB.'));
  }
  return AibAcheteur(
      situation: code,
      libelle: libelle,
      taux: t.toInt(),
      motif: rep.motif,
      choixManuel: choisie.isNotEmpty,
      presomption: presomption,
      avertissement: avertissement,
      nonArretes: nonArretes);
}

num? _numTaux(Object? v) => v is num ? v : num.tryParse('$v'.replaceAll(',', '.'));

/// L'acheteur de la fenêtre résolu au barème : l'IFU et le nom sont contrôlés d'abord (`validerAcheteurMecef`), puis le taux est rendu par le barème à
/// [date]. Un refus nomme son défaut ([RefusMecef]) et n'écrit rien ; sinon l'acheteur porte son taux ET sa situation.
({AcheteurMecef? acheteur, RefusMecef? refus, AibAcheteur aib}) acheteurNormaliseAuBareme({
  Object? ifu,
  Object? nom,
  Object? situationChoisie,
  required DateTime date,
  required Iterable<CpdFiche> situations,
  required Iterable<CpdFiche> versions,
  CpdParametresAib? parametres,
}) {
  final param = parametres ?? CpdParametresAib.graine;
  final identite = validerAcheteurMecef(ifu: ifu, nom: nom, aibTaux: 0, longueurIfu: param.longueurIfu);
  if (identite.refus != null) {
    return (acheteur: null, refus: identite.refus, aib: AibAcheteur(motif: identite.refus!.motif, refus: identite.refus));
  }
  final aib = aibPourAcheteur(ifu: ifu, situationChoisie: situationChoisie, date: date, situations: situations, versions: versions, parametres: param);
  if (!aib.ok) return (acheteur: null, refus: aib.refus, aib: aib);
  final v = validerAcheteurMecef(ifu: ifu, nom: nom, aibTaux: aib.taux, aibSituation: aib.situation, longueurIfu: param.longueurIfu);
  return (acheteur: v.acheteur, refus: v.refus, aib: aib);
}

/// La date en `jj/mm/aaaa` pour les motifs.
String isoJourAib(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
