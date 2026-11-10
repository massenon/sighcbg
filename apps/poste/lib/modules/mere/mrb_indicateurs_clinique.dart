import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mrb_commun.dart';
import 'mrb_source.dart';

/// Carte « Indicateurs agrégés pour le tableau de bord en ligne » (Direction, 09/11/2026, ADR-0007), posée sur l'écran `mere-indicateurs`.
///
/// Elle porte les TROIS réglages (interrupteur OUVERT par défaut, fermable, intervalle, jours de péremption) enregistrés en base par le service de la mère avec leur
/// défaut, et le CONTENU EXACT du dernier instantané réellement envoyé : la Direction voit CE QUI PART, ni plus ni moins. Un instantané ne porte que des
/// nombres, des dates, un code d'obligation, un numéro de version et des identifiants techniques d'appareils : jamais un nom, un code patient, un motif.
/// Les commandes d'écriture n'existent que pour qui a le droit d'écrire sur l'écran ; les autres lisent.

/// Les cadences proposées. La valeur en base, si elle n'y figure pas, s'ajoute à la liste : l'écran ne la remplace jamais en silence.
const List<int> mrbIntervallesProposes = [60, 300, 900, 1800, 3600, 21600, 86400];

String mrbLibelleIntervalle(int s) {
  if (s % 86400 == 0) return s == 86400 ? 'Une fois par jour' : 'Toutes les ${s ~/ 86400} jours';
  if (s % 3600 == 0) return s == 3600 ? 'Toutes les heures' : 'Toutes les ${s ~/ 3600} heures';
  if (s % 60 == 0) return s == 60 ? 'Toutes les minutes' : 'Toutes les ${s ~/ 60} minutes';
  return 'Toutes les $s secondes';
}

class CarteIndicateursClinique extends StatefulWidget {
  const CarteIndicateursClinique({super.key});
  @override
  State<CarteIndicateursClinique> createState() => _EtatCarte();
}

class _EtatCarte extends State<CarteIndicateursClinique> {
  MrbIndicateursClinique? etat;
  Map<String, Object?>? apercu;
  String? panne;
  bool enCours = true;
  Timer? _minuterie;

  MrbSource? get _source => mrbSourceCourante();

  @override
  void initState() {
    super.initState();
    _lire();
    _minuterie = Timer.periodic(mrbIntervalle, (_) => _lire());
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  Future<void> _lire() async {
    final s = _source;
    if (s == null) {
      if (mounted) {
        setState(() {
          panne = 'aucune liaison avec le service de la mère sur ce poste';
          enCours = false;
        });
      }
      return;
    }
    try {
      final e = await s.indicateursClinique();
      if (!mounted) return;
      setState(() {
        etat = e;
        panne = null;
        enCours = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          panne = mrbCause(e);
          enCours = false;
        });
      }
    }
  }

  Future<void> _regler(BuildContext contexte, {bool? publier, int? intervalleS, int? joursPeremption, String? ok}) async {
    final s = _source;
    if (s == null) return;
    try {
      await s.reglerIndicateursClinique(publier: publier, intervalleS: intervalleS, joursPeremption: joursPeremption);
      if (ok != null && contexte.mounted) ToastsSigh.afficher(contexte, ok, type: TypeToast.succes);
    } catch (e) {
      if (contexte.mounted) ToastsSigh.afficher(contexte, e is MrbIndisponible ? 'Non disponible : ${e.motif}' : 'Refusé : ${mrbCause(e)}', type: TypeToast.erreur);
    }
    await _lire();
  }

  Future<void> _publier(BuildContext contexte) async {
    final s = _source;
    if (s == null) return;
    try {
      final raison = await s.publierIndicateursClinique();
      if (contexte.mounted) {
        ToastsSigh.afficher(contexte, raison == null ? 'Instantané publié au relais.' : 'Rien n’est parti : ${_raison(raison)}', type: raison == null ? TypeToast.succes : TypeToast.erreur);
      }
    } catch (e) {
      if (contexte.mounted) ToastsSigh.afficher(contexte, e is MrbIndisponible ? 'Non disponible : ${e.motif}' : 'Refusé : ${mrbCause(e)}', type: TypeToast.erreur);
    }
    await _lire();
  }

  Future<void> _voirApercu() async {
    try {
      final a = await _source?.apercuIndicateursClinique();
      if (mounted) setState(() => apercu = a);
    } catch (e) {
      if (mounted) setState(() => panne = mrbCause(e));
    }
  }

  static String _raison(String r) => switch (r) {
        'interrupteur_ferme' => 'l’interrupteur est fermé.',
        'relais_non_configure' => 'aucun relais n’est configuré sur cette mère.',
        'echec_relais' => 'le relais a refusé ou ne répond pas (voir l’erreur affichée).',
        'instantane_non_conforme' => 'l’instantané n’est pas conforme au schéma ; il n’est pas envoyé.',
        'deja_en_cours' => 'un envoi est déjà en cours.',
        _ => r,
      };

  static String _json(Object? o) => const JsonEncoder.withIndent('  ').convert(o);

  Widget _bloc(String cle, String texte) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: JetonsShell.slate50, borderRadius: BorderRadius.circular(8), border: Border.all(color: JetonsShell.slate200)),
        child: SelectableText(texte, key: Key(cle), style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, height: 18 / 12)),
      );

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final e = etat;
    final peutRegler = c.peutEcrire;
    final intervalles = {...mrbIntervallesProposes, if (e != null) e.intervalleS}.toList()..sort();
    return CarteSigh(
      titre: 'Indicateurs agrégés vers le tableau de bord en ligne',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NoteSigh(
            'Le relais en ligne ne lit aucun dossier. Avec cet interrupteur ouvert, la mère lui envoie en plus, en clair, un instantané de NOMBRES agrégés '
            '(patients actifs, factures du mois, articles sous seuil, échéances en retard…) : jamais un nom, un code patient, un téléphone, une adresse, '
            'un motif, un diagnostic, un fournisseur ni un agent. L’instantané est signé avec le secret de la mère. Le contenu exact du dernier envoi est affiché ci-dessous.',
            icone: LucideIcons.shieldCheck),
        const SizedBox(height: 12),
        if (panne != null) NoteSigh('Réglages non lus : $panne.', ton: TonSigh.danger, icone: LucideIcons.triangleAlert),
        if (panne == null && !enCours && e == null)
          const NoteSigh('Le service de la mère ne propose pas la publication des indicateurs agrégés : réglages non disponibles.', ton: TonSigh.attention, icone: LucideIcons.info),
        if (e != null) ...[
          if (!e.relaisConfigure)
            const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: NoteSigh('Aucun relais n’est configuré sur cette mère : rien ne peut partir, même interrupteur ouvert.', ton: TonSigh.attention, icone: LucideIcons.triangleAlert)),
          Row(children: [
            Checkbox(
                key: const Key('mrb:interrupteur-indicateurs'),
                value: e.publier,
                onChanged: peutRegler ? (v) => _regler(context, publier: v == true, ok: v == true ? 'Publication des indicateurs ouverte.' : 'Publication des indicateurs fermée : plus rien ne part.') : null,
                activeColor: JetonsShell.navy900,
                visualDensity: VisualDensity.compact),
            Expanded(
                child: Text(e.publier ? 'Publier les indicateurs au relais : OUVERT' : 'Publier les indicateurs au relais : FERMÉ (aucun instantané ne part)',
                    key: const Key('mrb:etat-interrupteur'), style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          if (!peutRegler)
            const Padding(padding: EdgeInsets.only(left: 12, bottom: 4), child: Text('Lecture seule : vos droits ne permettent pas de régler cette publication.', style: TextStyle(fontSize: 12, color: JetonsShell.slate500))),
          const SizedBox(height: 8),
          Wrap(spacing: 24, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('Intervalle de publication', style: TextStyle(fontSize: 12, color: JetonsShell.slate500)),
              SizedBox(
                width: 260,
                child: SelecteurSigh(
                  key: const Key('mrb:intervalle-indicateurs'),
                  libelle: 'Intervalle de publication',
                  valeur: '${e.intervalleS}',
                  options: [for (final s in intervalles) OptionChamp('$s', mrbLibelleIntervalle(s) + (s == e.defautIntervalleS ? ' (défaut)' : ''))],
                  surChange: (v) {
                    final n = int.tryParse(v);
                    if (peutRegler && n != null && n != e.intervalleS) _regler(context, intervalleS: n, ok: 'Intervalle réglé : ${mrbLibelleIntervalle(n).toLowerCase()}.');
                  },
                ),
              ),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('Lot « proche de la péremption » (jours)', style: TextStyle(fontSize: 12, color: JetonsShell.slate500)),
              SizedBox(
                width: 220,
                child: SelecteurSigh(
                  key: const Key('mrb:jours-peremption'),
                  libelle: 'Jours avant péremption',
                  valeur: '${e.joursPeremption}',
                  options: [for (final j in {30, 60, 90, 120, 180, e.joursPeremption}.toList()..sort()) OptionChamp('$j', '$j jours${j == e.defautJoursPeremption ? ' (défaut)' : ''}')],
                  surChange: (v) {
                    final n = int.tryParse(v);
                    if (peutRegler && n != null && n != e.joursPeremption) _regler(context, joursPeremption: n, ok: 'Seuil de péremption réglé : $n jours.');
                  },
                ),
              ),
            ]),
            if (peutRegler)
              BoutonSigh(
                  key: const Key('mrb:publier-maintenant'),
                  libelle: 'Publier maintenant',
                  icone: LucideIcons.send,
                  variante: VarianteBouton.secondaire,
                  onPressed: e.publier ? () => _publier(context) : null),
            BoutonSigh(key: const Key('mrb:voir-apercu'), libelle: 'Voir ce qui partirait', icone: LucideIcons.eye, variante: VarianteBouton.secondaire, onPressed: _voirApercu),
          ]),
          const SizedBox(height: 16),
          Text(
              e.envoyeLe == null ? 'Dernier instantané publié' : 'Dernier instantané publié le ${mrbDateHeure(e.envoyeLe!)}',
              key: const Key('mrb:titre-dernier-instantane'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (e.dernier == null)
            Text(
                e.publier
                    ? 'Aucun instantané n’est encore parti : le premier part au prochain tour de la mère.'
                    : 'Jamais publié : l’interrupteur est fermé, rien n’est jamais parti vers le relais.',
                key: const Key('mrb:jamais-publie'),
                style: const TextStyle(color: JetonsShell.slate500))
          else
            _bloc('mrb:dernier-instantane', _json(e.dernier)),
          if (e.erreur != null) ...[
            const SizedBox(height: 8),
            NoteSigh('Dernier essai refusé : ${e.erreur}', ton: TonSigh.danger, icone: LucideIcons.triangleAlert),
          ],
          if (e.derniereTentative != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('Dernière tentative : ${mrbDateHeure(e.derniereTentative!)}', style: const TextStyle(fontSize: 12, color: JetonsShell.slate500))),
          if (apercu != null) ...[
            const SizedBox(height: 16),
            const Text('Ce qui partirait maintenant (calculé à l’instant, rien n’est envoyé)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _bloc('mrb:apercu-instantane', _json(apercu)),
            const SizedBox(height: 6),
            Text(
                ikValider(apercu).isEmpty
                    ? 'Conforme au schéma : des nombres, des dates et des identifiants techniques ; aucune donnée nominative.'
                    : 'NON CONFORME au schéma : cet instantané ne partirait pas (${ikValider(apercu).first}).',
                key: const Key('mrb:verdict-apercu'),
                style: TextStyle(fontSize: 12, color: ikValider(apercu).isEmpty ? JetonsShell.success600 : JetonsShell.slate900)),
          ],
        ],
      ]),
    );
  }
}
