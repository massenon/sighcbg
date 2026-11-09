import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/normalisation_mecef.dart';
import '../../kit/kit.dart';

/// LA FENÊTRE « FACTURE NORMALISÉE » (E2299), une fabrique pour les trois portes d'encaissement (émission, registre des paiements, file de caisse).
///
/// TOUTE VENTE EST NORMALISÉE à la clinique (Direction, 07/11/2026) : il n'y a pas de « facture simple » à choisir. La fenêtre ne sert qu'à saisir
/// l'IFU et le nom de l'acheteur et à situer l'acheteur pour l'AIB. L'IFU est facultatif pour un particulier (13 chiffres quand il est renseigné) ; un
/// IFU exige un nom. Le contrôle est celui du domaine, refait AVANT toute écriture : un refus nommé n'écrit rien.
///
/// LE TAUX D'AIB N'EST PLUS UNE LISTE CODÉE (lot A5) : il se LIT au barème daté de M12 (`situationsAib` + `baremeAib`). La situation se déduit d'office de
/// l'IFU (« Automatique », par défaut) ou se choisit à la main parmi les situations du barème ; le taux affiché est celui EN VIGUEUR À LA DATE de la
/// facture, avec son motif. Seul un taux ARRÊTÉ s'applique : un taux non arrêté s'affiche « non arrêté, à valider » et la vente est refusée en le nommant
/// (`AIB_SANS_BAREME`) — jamais un taux commode. Aucune écriture comptable d'AIB n'est posée ici (décision de la Direction).
const _automatique = '';

/// Les champs de la fenêtre : les choix de situation viennent du barème à [date], plus d'une liste écrite dans le code.
List<ChampDef> champsAcheteurNormalise(Magasin m, DateTime date) {
  final situations = m.collection('situationsAib').actives;
  final versions = m.collection('baremeAib').actives;
  String etat(String code, d.CpdTauxAib r) {
    if (r.ok) return '${r.taux} % arrêté';
    final attente = [for (final f in r.enAttente) '${f['taux']} % non arrêté, à valider'];
    return attente.isEmpty ? 'aucun taux arrêté' : attente.join(' ; ');
  }

  return [
    const ChampDef(
        nom: 'acheteurIfu',
        libelle: 'IFU de l’acheteur',
        type: TypeChamp.texte,
        col: ColChamp.tiers,
        indicatif: '13 chiffres (facultatif pour un particulier)'),
    const ChampDef(
        nom: 'acheteurNom',
        libelle: 'Nom de l’acheteur',
        type: TypeChamp.texte,
        col: ColChamp.tiers,
        indicatif: 'Le patient, par défaut'),
    ChampDef(
        nom: 'acheteurAib',
        libelle: 'Situation de l’acheteur (AIB)',
        type: TypeChamp.select,
        col: ColChamp.tiers,
        options: [
          const OptionChamp(_automatique, 'Automatique — d’après l’IFU saisi'),
          for (final b in d.cpdBaremeEnVigueur(situations, versions, date))
            OptionChamp(b.code, '${b.libelle} — ${etat(b.code, b.reponse)}'),
        ]),
  ];
}

/// Les valeurs initiales de la fenêtre pour une pièce (ce qu'elle porte déjà) : la situation est « Automatique », le barème décide.
Map<String, Object?> valeursAcheteur(Map<String, Object?>? piece) => {
      'acheteurIfu': '${piece?['ifuClient'] ?? ''}',
      'acheteurNom': '${piece?['acheteurNom'] ?? ''}',
      'acheteurAib': _automatique,
    };

/// L'acheteur de la fenêtre résolu au barème à [date] (date de la facture) : acheteur validé portant son taux ET sa situation, ou refus nommé.
({d.AcheteurMecef? acheteur, d.RefusMecef? refus, d.AibAcheteur aib}) resoudreAcheteur(ControleurFormulaire f, Magasin m, DateTime date) =>
    d.acheteurNormaliseAuBareme(
        ifu: f['acheteurIfu'],
        nom: f['acheteurNom'],
        situationChoisie: f['acheteurAib'],
        date: date,
        situations: m.collection('situationsAib').actives,
        versions: m.collection('baremeAib').actives);

/// Ce que la fenêtre a saisi, dans la forme de `encaisser` et de `normaliserVente` : le taux et la situation viennent du BARÈME à la date de la facture.
Map<String, Object?> lireAcheteur(ControleurFormulaire f, Magasin m, DateTime date) {
  final r = resoudreAcheteur(f, m, date);
  return {
    'ifu': f['acheteurIfu'],
    'nom': f['acheteurNom'],
    'aibTaux': r.acheteur?.aibTaux,
    'aibSituation': r.acheteur?.aibSituation,
  };
}

/// La carte « Facture normalisée » : l'IFU, le nom, la situation de l'acheteur — et, en dessous, le taux d'AIB que le barème rend à la date de la facture,
/// avec son motif (ou le refus nommé), recalculé à chaque saisie.
class SectionAcheteur extends StatelessWidget {
  const SectionAcheteur({super.key, required this.controleur, required this.magasin, required this.date});
  final ControleurFormulaire controleur;
  final Magasin magasin;
  final DateTime date;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('mecef:acheteur'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            border: Border.all(color: JetonsShell.slate200),
            borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('FACTURE NORMALISÉE',
              style: TextStyle(
                  color: JetonsShell.navy900,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),
          FormulaireSigh(controleur: controleur),
          ListenableBuilder(
              listenable: controleur,
              builder: (context, _) {
                final r = d.aibPourAcheteur(
                    ifu: controleur['acheteurIfu'],
                    situationChoisie: controleur['acheteurAib'],
                    date: date,
                    situations: magasin.collection('situationsAib').actives,
                    versions: magasin.collection('baremeAib').actives);
                final quand = d.dateFR(date);
                final texte = r.ok
                    ? 'AIB au $quand : ${r.taux} % (${r.libelle}${r.choixManuel ? ', choisie à la main' : ''}). ${r.motif}${r.avertissement == null ? '' : ' ${r.avertissement}'} Calculé sur le montant hors taxes.'
                    : 'AIB au $quand : aucun taux applicable. ${r.refus?.motif ?? r.motif}';
                return Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: KeyedSubtree(
                        key: const Key('mecef:aib-taux'),
                        child: NoteSigh(texte,
                            ton: r.ok ? TonSigh.info : TonSigh.attention,
                            icone: r.ok ? LucideIcons.percent : LucideIcons.triangleAlert)));
              }),
          const Text(
              'Toute vente est normalisée : l’IFU, s’il est renseigné, compte 13 chiffres. Le taux d’AIB vient du barème de M12 : seul un taux arrêté s’applique.',
              style: TextStyle(color: JetonsShell.slate500, fontSize: 12)),
        ]),
      );
}

/// Le contrôle de la fenêtre AVANT toute écriture : `null` quand elle est valide, sinon le refus nommé (code, motif, geste).
d.RefusMecef? controlerAcheteur(ControleurFormulaire f, Magasin m, DateTime date) =>
    resoudreAcheteur(f, m, date).refus;

/// Ce que la normalisation a rendu, dit au guichet : une pièce refusée se DIT, avec son code, son motif et son geste. Rien à dire en mode désactivé.
void annoncerNormalisation(BuildContext ctx, ResultatNormalisation? n) {
  if (n == null || n.ignore) return;
  if (n.ok) {
    ToastsSigh.afficher(ctx, 'Vente normalisée : ${n.numero}.',
        type: TypeToast.succes,
        detail: 'Numéro de démonstration, non fiscal (aucun boîtier branché).');
    return;
  }
  ToastsSigh.afficher(ctx,
      'Normalisation non aboutie (${n.code}) : la vente est encaissée mais pas normalisée.',
      type: TypeToast.attention,
      detail: '${n.motif} ${n.geste}',
      duree: const Duration(seconds: 12));
}
