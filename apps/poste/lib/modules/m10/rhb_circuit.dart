import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/service_installation.dart';
import '../../donnees/magasin.dart';
import '../../donnees/planning_rh_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import '../../sync/service_validations_deposees.dart';

/// Les briques communes des cinq écrans du planning individuel, du circuit de validation et des propositions (lots L4 à L6, Direction, 09/11/2026) : la
/// carte des réglages, le badge et les commandes de validation, les refus nommés. Les RÈGLES sont celles du domaine (`planning_rh.dart`), assemblées au
/// magasin du poste par [PlanningRhPoste] ; le circuit et « l'agent modifie directement » se LISENT au registre des paramètres (lot L0), jamais en constante.

/// Le moteur du planning RH pour l'agent de la session (nom nominatif, rôle, horloge du poste).
///
/// Sur un poste RATTACHÉ (fileul), une validation du planning se DÉPOSE (décision 12 du 17/11/2026) : la mère l'applique sous le rôle de l'auteur ; le résultat porte alors `enAttenteMere`.
PlanningRhPoste rhbPlanningPoste(ContexteEcran c) => PlanningRhPoste(c.magasin,
    auteur: () => acteur(c).nom,
    role: c.role,
    horloge: () => c.aujourdhui,
    deposer: ServiceInstallation.de(c.magasin).rattache ? ServiceValidationsDeposees.de(c.magasin).deposeurPlanning(role: c.role, acteur: acteur(c).nom) : null);

/// Le message d'un geste du planning qui a réussi : le succès, ou « transmis à la mère, en attente » quand la validation s'est DÉPOSÉE (jamais « validé » avant la confirmation de la mère).
void rhbToastSuite(BuildContext ctx, Map<String, Object?> res, String succes, {String? detail, VoidCallback? annuler}) {
  if (res['enAttenteMere'] == true) {
    ToastsSigh.afficher(ctx, 'Décision transmise à la mère, en attente.',
        type: TypeToast.info, detail: 'La mère l’applique sous votre rôle, contrôles refaits ; la pièce change d’état à la confirmation.', annuler: annuler);
    return;
  }
  ToastsSigh.afficher(ctx, succes, type: TypeToast.succes, detail: detail, annuler: annuler);
}

/// Les états de validation d'une pièce (libellés de la maquette).
const Map<String, (String, TonSigh)> rhbEtatsValidation = {
  'a_valider': ('À valider', TonSigh.attention),
  'valide_surveillant': ('Validé par le surveillant, DAF attendue', TonSigh.info),
  'valide': ('Validé', TonSigh.succes),
  'refuse': ('Refusé', TonSigh.danger),
};

/// Le badge d'état de validation d'une pièce (`badgeValidation`).
Widget rhbBadgeValidation(String nom, Fiche r) {
  final x = rhbEtatsValidation[etatValidationRh(nom, r)] ?? ('—', TonSigh.neutre);
  return BadgeSigh(x.$1, ton: x.$2);
}

/// Le libellé « ce pointage », « cette demande de congé », « cet ordre de mission ».
String rhbDefPiece(String nom) => switch (nom) {
      'presences' => 'ce pointage',
      'conges' => 'cette demande de congé',
      _ => 'cet ordre de mission',
    };

/// Toast d'un refus nommé : le motif, et le geste de correction en détail.
void rhbToastRefus(BuildContext ctx, Map<String, Object?> r) =>
    ToastsSigh.afficher(ctx, '${r['motif']}', type: TypeToast.erreur, detail: '${r['geste']}');

/// Celui qui signe l'étape [etape] du circuit (`daf` ou `surveillant`), dit par le POSTE de l'organigramme (« le poste X ») quand celui-ci en nomme un ; à défaut, l'intitulé d'attente
/// (`nomEtapeRh` du domaine). L'étape reste un identifiant stocké sur la pièce ; son intitulé, lui, n'est écrit nulle part au-delà de ce repli.
String rhbLibelleEtape(ContexteEcran c, Object? etape) {
  // Quelle étape ? Celle dont le geste réservé est « valider pour la DAF » : l'identifiant de l'étape n'est comparé à aucun littéral.
  final daf = gesteEtapeRh['$etape'] == gesteRhEtapeDaf;
  final poste = paiIntituleSignataire(c.magasin.collection('postes').actives, daf ? PaiQualite.daf : PaiQualite.surveillant);
  return poste == null ? nomEtapeRh['$etape'] ?? '$etape' : 'le poste « $poste »';
}

/// Les commandes de validation d'une pièce : ABSENTES si le rôle courant n'est pas l'étape attendue du circuit (jamais grisées). [apres] : rafraîchissement
/// de l'écran après le geste (les écrans écoutent déjà leurs collections : il sert surtout aux écrans qui ne le font pas).
List<Widget> rhbCommandesValidation(BuildContext ctx, ContexteEcran c, String nom, Fiche r, {VoidCallback? apres}) {
  final p = rhbPlanningPoste(c);
  final peut = p.peutTrancher(nom, r);
  if (peut.refus != null) return const [];
  final def = rhbDefPiece(nom);
  final etape = rhbLibelleEtape(c, peut.etape);
  return [
    BoutonIcone(
        icone: LucideIcons.check,
        libelle: 'Valider $def',
        onPressed: () async {
          final ok = await confirmerSigh(ctx,
              titre: 'Valider $def ?',
              message: 'La validation est celle de $etape, consignée au journal (RG-12). Circuit en vigueur : ${libellesCircuitsRh[p.circuit()]}.',
              libelleOk: 'Valider');
          if (!ok || !ctx.mounted) return;
          final res = p.trancher(nom, r['id'], 'valider');
          if (res['ok'] != true) {
            rhbToastRefus(ctx, res);
            return;
          }
          apres?.call();
          rhbToastSuite(ctx, res, res['complet'] == true ? 'Pièce validée.' : 'Étape validée : la pièce attend ${rhbLibelleEtape(c, gesteEtapeRh.entries.firstWhere((e) => e.value == gesteRhEtapeDaf).key)}.', annuler: res['enAttenteMere'] == true
              ? null
              : () {
                  (res['annuler'] as VoidCallback)();
                  apres?.call();
                });
        }),
    BoutonIcone(
        icone: LucideIcons.x,
        libelle: 'Refuser $def',
        onPressed: () async {
          final motif = await confirmerAvecMotif(ctx,
              titre: 'Refuser $def ?', message: 'Le refus exige son motif : l’agent le lira.', libelleOk: 'Refuser', dangereux: true, motifObligatoire: false);
          if (motif == null || !ctx.mounted) return;
          final res = p.trancher(nom, r['id'], 'refuser', motif: motif);
          if (res['ok'] != true) {
            rhbToastRefus(ctx, res);
            return;
          }
          apres?.call();
          rhbToastSuite(ctx, res, 'Pièce refusée.', detail: 'Le motif est visible de l’agent.', annuler: res['enAttenteMere'] == true
              ? null
              : () {
                  (res['annuler'] as VoidCallback)();
                  apres?.call();
                });
        }),
  ];
}

/// `carteReglagesRh` : « Réglages du planning et des présences ». Partagée par les écrans qui s'y réfèrent ; la commande « Régler » est ABSENTE hors
/// administrateur et Directrice Administrative (le moteur refuse de toute façon : REGLAGE_RESERVE).
class RhbCarteReglages extends StatelessWidget {
  const RhbCarteReglages({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
        listenable: c.magasin.collection(parCollectionParametres),
        builder: (ctx, _) {
          final p = rhbPlanningPoste(c);
          final peut = gestePeutEcran(c, gesteRhRegler);
          return CarteSigh(
              titre: 'Réglages du planning et des présences',
              actions: [
                if (peut) BoutonSigh(libelle: 'Régler', icone: LucideIcons.settings2, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _regler(context, c, p)),
              ],
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                DescListeSigh([
                  ('Circuit de validation', libellesCircuitsRh[p.circuit()] ?? '—'),
                  ('L’agent modifie directement son planning', p.agentModifieDirectement() ? 'Oui' : 'Non : il propose, le surveillant valide'),
                ]),
                const SizedBox(height: 8),
                const Text(
                    'Une présence, une absence, un congé ou un ordre de mission non validé est visible mais ne compte pas. Un planning proposé ne change rien tant qu’il n’est pas validé.',
                    style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
              ]));
        });
  }

  void _regler(BuildContext ctx, ContexteEcran c, PlanningRhPoste p) {
    final ctl = ControleurFormulaire([
      ChampDef(nom: 'circuit', libelle: 'Circuit de validation des présences, absences, congés et ordres de mission', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: [
        for (final e in libellesCircuitsRh.entries) OptionChamp(e.key, e.value)
      ]),
      const ChampDef(nom: 'direct', libelle: 'L’agent modifie directement son planning (sans validation du surveillant)', type: TypeChamp.case_, col: ColChamp.plein),
    ], {'circuit': p.circuit(), 'direct': p.agentModifieDirectement()});
    afficherModale<void>(ctx,
        titre: 'Réglages du planning et des présences',
        taille: TailleModale.md,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const NoteSigh('Ces réglages se règlent au poste et se synchronisent. Une pièce déjà tranchée garde le circuit sous lequel elle l’a été.'),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final r1 = p.definirCircuit(v['circuit']);
                    if (r1['ok'] != true) {
                      rhbToastRefus(ctx, r1);
                      return;
                    }
                    final r2 = p.definirAgentDirect(v['direct'] == true);
                    if (r2['ok'] != true) {
                      rhbToastRefus(ctx, r2);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Réglages enregistrés.', type: TypeToast.succes);
                  }),
            ]);
  }
}
