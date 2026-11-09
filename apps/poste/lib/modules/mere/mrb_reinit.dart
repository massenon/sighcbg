import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'mrb_commun.dart';
import 'mrb_source.dart';

/// `mere-reinit` : réinitialisation de production (M-12, spec §10). Mettre l'activité de démonstration hors service en gardant les essentiels : par défaut
/// l'ARCHIVER (décision D6, 09/11/2026 : RG-14, rien n'est supprimé, la synchronisation propage l'archivage aux fileuls) ; la suppression physique, qui
/// contredit RG-14, a sa propre porte, nommée.
///
/// Garde-fous, tous testés : la commande est ABSENTE sans le droit d'annuler sur l'écran ; la fenêtre est fermée par défaut et se referme d'elle-même
/// (30 minutes) ; la saisie du nom de la clinique ET d'un second profil, différent de l'auteur, sont exigés ; une dernière confirmation nomme la
/// conséquence ; la sauvegarde préalable est faite par le service et non désactivable ; le geste est journalisé au journal du poste (RG-12).
/// Ce que le service ne tient pas seul (écarts E1350 à E1354) : l'échéance de la fenêtre, l'identité du second profil (un nom saisi n'est pas une
/// authentification), la trace détaillée au journal de la mère (auteur, second profil, empreinte de la sauvegarde).
class EcranReinitialisation extends StatefulWidget with EcranMaquette {
  const EcranReinitialisation({super.key});
  @override
  String get titre => 'Réinitialisation de production';
  @override
  String get description => 'Archiver l’activité de démonstration (mise en service) en gardant les essentiels : tarifs, secteurs, comptes, droits, catalogues.';
  @override
  String get regle =>
      'Par défaut, la mise en production ARCHIVE l’activité de démonstration (patients, factures, stocks mouvementés, écritures, brouillons compris) : rien n’est supprimé (RG-14) '
      'et les postes fileuls reçoivent l’archivage. La suppression physique, qui contredit RG-14 et change l’époque, est une porte à part. '
      'Une sauvegarde chiffrée est toujours faite avant, et ne peut pas être désactivée.';

  @override
  State<EcranReinitialisation> createState() => _EtatReinit();
}

class _Fait {
  const _Fait({required this.sauvegarde, required this.epoch, required this.trace, this.resultat});
  final String sauvegarde;
  final int? epoch;
  final MrbResultatReinit? resultat;

  /// `true` : l'évènement figure au journal technique relu APRÈS le geste ; `false` : il n'y figure pas ; `null` : le journal n'a pas pu être relu.
  final bool? trace;
}

class _EtatReinit extends MrbEtatEcran<EcranReinitialisation, MrbEtat> {
  final TextEditingController _confirmation = TextEditingController();
  final TextEditingController _second = TextEditingController();
  final TextEditingController _motif = TextEditingController();
  DateTime? _ouverteLe;
  _Fait? _fait;

  DateTime _maintenant() => context.getInheritedWidgetOfExactType<ContexteEcran>()?.aujourdhui ?? DateTime.now();

  @override
  void dispose() {
    _confirmation.dispose();
    _second.dispose();
    _motif.dispose();
    super.dispose();
  }

  @override
  Future<MrbEtat> charger(MrbSource s) async {
    var e = await s.etat();
    // La fenêtre se referme à l'échéance : le service pose un drapeau sans limite de durée.
    if (e.reinitOuverte && _ouverteLe != null) {
      final reste = mrbFenetreRestante(ouverteLe: _ouverteLe, maintenant: _maintenant());
      if (reste == Duration.zero) {
        await s.ouvrirFenetreReinit(false);
        _ouverteLe = null;
        e = await s.etat();
      }
    }
    if (!e.reinitOuverte) _ouverteLe = null;
    return e;
  }

  Future<void> _ouvrir(BuildContext contexte, bool ouvrir) async {
    final s = source;
    if (s == null) return;
    final ok = await geste(contexte, () => s.ouvrirFenetreReinit(ouvrir),
        ok: ouvrir ? 'Fenêtre ouverte pour ${mrbDureeFenetreReinit.inMinutes} minutes.' : 'Fenêtre refermée.');
    if (ok) setState(() => _ouverteLe = ouvrir ? _maintenant() : null);
  }

  Future<void> _reinitialiser(BuildContext contexte, ContexteEcran c, {bool supprimer = false}) async {
    final s = source;
    final etat = donnees;
    if (s == null || etat == null) return;
    final refus = mrbRefusReinit(
      droitAnnuler: c.peutAnnuler,
      fenetreOuverte: etat.reinitOuverte,
      confirmation: _confirmation.text,
      nomClinique: s.nomClinique,
      second: _second.text,
      auteur: acteurNom(c),
      mode: supprimer ? mrbModeSupprimer : mrbModeArchiver,
      motif: _motif.text,
      suppressionConfirmee: supprimer,
    );
    if (refus != null) {
      ToastsSigh.afficher(contexte, 'Réinitialisation refusée : ${refus.motif}', type: TypeToast.erreur);
      return;
    }
    final ok = supprimer
        ? await confirmerSigh(contexte,
            titre: 'Suppression physique : dernière confirmation',
            message: 'SUPPRIMER PHYSIQUEMENT l’activité de la clinique ${s.nomClinique} ? Les patients, factures, stocks mouvementés et écritures seront effacés du serveur, '
                'sans archivage ni retour, et la numérotation repartira du début : cela contredit RG-14. Une sauvegarde chiffrée est faite avant. '
                'Second profil confirmant : ${_second.text.trim()}.',
            libelleOk: 'Supprimer physiquement',
            libelleAnnuler: 'Renoncer',
            dangereux: true)
        : await confirmerSigh(contexte,
            titre: 'Dernière confirmation',
            message: 'Archiver le jeu de démonstration de la clinique ${s.nomClinique} ? Les patients, factures, stocks mouvementés, écritures et brouillons passent à l’état archivé '
                '(motif « $cfbMotifArchivageJeuDemo ») : rien n’est supprimé, tout se restaure, et les postes fileuls reçoivent l’archivage. '
                'Une sauvegarde chiffrée est faite avant. Second profil confirmant : ${_second.text.trim()}.',
            libelleOk: 'Archiver le jeu de démonstration',
            dangereux: true);
    if (!ok || !contexte.mounted) return;
    final second = _second.text.trim();
    try {
      final r = await s.reinitialiser(confirmation: _confirmation.text.trim(), second: second, motif: _motif.text.trim(), supprimer: supprimer);
      // RG-12 : le geste est inscrit au journal du poste avec son auteur et le second profil ; la sauvegarde préalable y est référencée.
      c.magasin.journaliser(supprimer ? 'Réinitialisation de production (suppression physique)' : 'Archivage du jeu de démonstration (mère)', 'MERE', 'Poste mère',
          'époque ${r.epoch ?? 'inconnue'}', null, {
        'secondProfil': second,
        'sauvegardePrealable': r.sauvegarde,
        if (!supprimer) ...{'motif': _motif.text.trim(), 'fiches': r.totalArchivees, 'brouillons': r.totalBrouillons, 'collections': r.archivees.length},
      });
      bool? trace;
      try {
        final j = await s.journal(limite: 50);
        trace = j.any((l) => l.message.startsWith('Réinitialisation') || l.message.startsWith('Archivage du jeu'));
      } catch (_) {
        trace = null;
      }
      setState(() {
        _fait = _Fait(sauvegarde: r.sauvegarde, epoch: r.epoch, trace: trace, resultat: r);
        _ouverteLe = null;
        _confirmation.clear();
        _second.clear();
        _motif.clear();
      });
      if (contexte.mounted) {
        ToastsSigh.afficher(
            contexte,
            supprimer
                ? 'Activité supprimée physiquement. Sauvegarde préalable : ${r.sauvegarde}'
                : 'Jeu de démonstration archivé : ${nombre(r.totalArchivees)} fiches dans ${r.archivees.length} collection(s), dont ${nombre(r.totalBrouillons)} brouillon(s). Sauvegarde préalable : ${r.sauvegarde}',
            type: TypeToast.succes);
      }
    } catch (e) {
      if (contexte.mounted) ToastsSigh.afficher(contexte, 'Réinitialisation refusée : ${mrbCause(e)}', type: TypeToast.erreur);
    }
    await actualiser();
  }

  Widget _champ(String libelle, TextEditingController ctl, Key cle) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(libelle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: JetonsShell.slate600)),
        const SizedBox(height: 4),
        TextField(key: cle, controller: ctl, style: styleSaisie, decoration: decorationChamp(indicatif: libelle)),
      ]);

  Widget _liste(String titre, List<String> items) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 4),
          for (final i in items) Padding(padding: const EdgeInsets.only(left: 8, bottom: 2), child: Text('• $i')),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final e = donnees;
    final ouverte = e?.reinitOuverte == true;
    final reste = ouverte ? mrbFenetreRestante(ouverteLe: _ouverteLe, maintenant: _maintenant()) : null;
    final s = source;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      mrbBandeauPanne(panne),
      if (e != null && !ouverte)
        const Padding(
            padding: EdgeInsets.only(bottom: 12), child: NoteSigh('La fenêtre de réinitialisation est fermée.', ton: TonSigh.neutre, icone: LucideIcons.lock)),
      if (_fait != null) ...[
        NoteSigh(
            '${_fait!.resultat?.mode == mrbModeSupprimer ? 'Activité supprimée physiquement.' : 'Jeu de démonstration archivé : ${nombre(_fait!.resultat?.totalArchivees ?? 0)} fiches dans ${_fait!.resultat?.archivees.length ?? 0} collection(s), dont ${nombre(_fait!.resultat?.totalBrouillons ?? 0)} brouillon(s). Rien n’est supprimé ; les postes fileuls reçoivent l’archivage.'} '
            'Sauvegarde préalable : ${_fait!.sauvegarde}. Époque : ${_fait!.epoch ?? mrbNonDisponible}. '
            '${_fait!.trace == true ? 'Le geste est inscrit au journal technique de la mère.' : _fait!.trace == false ? 'ATTENTION : le geste n’a pas été retrouvé au journal technique de la mère.' : 'Le journal technique n’a pas pu être relu.'}'
            '${_fait!.resultat?.mode == mrbModeSupprimer ? ' Les postes exportent leurs opérations non envoyées puis se resynchronisent à leur prochain contact.' : ''}',
            ton: _fait!.trace == false ? TonSigh.attention : TonSigh.succes,
            icone: LucideIcons.circleCheck),
        if (_fait!.resultat != null && _fait!.resultat!.archivees.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final e in (_fait!.resultat!.archivees.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: JetonsShell.success50, borderRadius: BorderRadius.circular(4)),
                  child: Text('${e.key} : ${nombre(e.value)}${(_fait!.resultat!.brouillons[e.key] ?? 0) > 0 ? ' (dont ${nombre(_fait!.resultat!.brouillons[e.key])} brouillon(s))' : ''}',
                      style: const TextStyle(fontSize: 10, height: 14 / 10, color: JetonsShell.success700))),
          ]),
        ],
        const SizedBox(height: 12),
      ],
      CarteSigh(
        titre: 'Fenêtre de réinitialisation',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            BadgeSigh(e == null ? mrbNonDisponible : (ouverte ? 'Ouverte' : 'Fermée'),
                ton: e == null ? TonSigh.neutre : (ouverte ? TonSigh.attention : TonSigh.succes)),
            const SizedBox(width: 12),
            if (ouverte)
              Flexible(
                  child: Text(reste == null
                      ? 'Ouverte à une heure inconnue (pas depuis cette console) : refermez-la après usage.'
                      : 'Se referme dans ${reste.inMinutes} min ${reste.inSeconds % 60} s.')),
          ]),
          const SizedBox(height: 8),
          const Text(
              'Le service de la mère ne limite pas lui-même la durée de la fenêtre : cette console la referme à l’échéance tant qu’elle reste ouverte.',
              style: TextStyle(fontSize: 12, color: JetonsShell.slate500)),
          if (c.peutAnnuler) ...[
            const SizedBox(height: 12),
            if (!ouverte)
              BoutonSigh(
                  libelle: 'Ouvrir la fenêtre (${mrbDureeFenetreReinit.inMinutes} min)',
                  icone: LucideIcons.lockOpen,
                  variante: VarianteBouton.attention,
                  onPressed: () => _ouvrir(context, true))
            else ...[
              const NoteSigh('Pour archiver le jeu de démonstration, saisir le nom de la clinique, le nom d’un second profil (DAF ou Direction) qui confirme, ET le motif.'),
              const SizedBox(height: 12),
              Wrap(spacing: 16, runSpacing: 12, children: [
                SizedBox(
                    width: 320,
                    child: _champ('Tapez le nom de la clinique pour confirmer${s == null ? '' : ' (${s.nomClinique})'}', _confirmation,
                        const Key('mrb:confirmation'))),
                SizedBox(width: 320, child: _champ('Second profil confirmant (DAF ou Direction)', _second, const Key('mrb:second-profil'))),
                SizedBox(width: 320, child: _champ('Motif de l’archivage (obligatoire)', _motif, const Key('mrb:motif'))),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                BoutonSigh(
                    libelle: 'Archiver le jeu de démonstration',
                    icone: LucideIcons.archive,
                    variante: VarianteBouton.danger,
                    onPressed: () => _reinitialiser(context, c)),
                BoutonSigh(
                    key: const Key('mrb:suppression-physique'),
                    libelle: 'Suppression physique',
                    icone: LucideIcons.trash2,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _reinitialiser(context, c, supprimer: true)),
                BoutonSigh(
                    libelle: 'Fermer la fenêtre',
                    icone: LucideIcons.lock,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => _ouvrir(context, false)),
              ]),
            ],
          ],
        ]),
      ),
      const SizedBox(height: 16),
      CarteSigh(
        titre: 'Ce qui est conservé',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _liste('Conservé (spécification, section 10)', mrbEssentielsSpec),
          _liste('Conservé par le moteur de synchronisation de la mère', mrbEssentielsMoteur),
          _liste('Archivé (par défaut) — vidé seulement par la suppression physique', mrbVideSpec),
          const Text(
              'La liste conservée est une donnée du dictionnaire, pas du code. L’archivage passe chaque fiche d’activité à l’état archivé par une opération du journal, '
              'propagée aux fileuls : ni purge, ni changement d’époque, ni remise à zéro de la numérotation (RG-01). La suppression physique, elle, vide le journal d’opérations, les fiches, '
              'les conflits, les plages, les baux et la portée des mobiles, incrémente l’époque et contredit RG-14.',
              style: TextStyle(fontSize: 12, color: JetonsShell.slate500)),
        ]),
      ),
    ]);
  }
}
