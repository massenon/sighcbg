import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/service_installation.dart';
import '../../core/service_parametres.dart';
import '../../donnees/magasin.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/choix_exercice.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import '../../sync/service_validations_deposees.dart';
import '../m12/cpc_commun.dart' show amorcerExercices;
import '../m4/mat_commun.dart';
import 'adm_commun.dart';

/// `m13-plan-annuel` — LE PLAN DE TRAVAIL ANNUEL (PTA) (lot PTA, Direction de Baguidi, 17/11/2026 : « Oui au lot PTA. RIEN NE DOIT ÊTRE EN DUR. »).
///
/// L'écran garde l'identifiant et les droits de l'ancien « plan annuel de travail » ; tout le reste est lu : l'EXERCICE du sélecteur de la barre supérieure (défaut :
/// celui qui contient la date du jour), les AXES, ÉTATS et SOURCES DE FINANCEMENT des référentiels, la PÉRIODICITÉ, le SEUIL de retard et le PRÉFIXE de numérotation
/// des paramètres de clinique (versionnés par date), le RÉALISÉ budgétaire du module Budgets. Les règles sont celles du domaine (`pta.dart`) ; cet écran ne fait que
/// les présenter et appliquer leurs écritures. Droits : écrire le plan = droit d'écran ; adopter, renvoyer, clôturer = geste `pta_adopter` ; régler les référentiels =
/// geste `pta_regler`. Une commande refusée est ABSENTE. Sur un poste rattaché, une décision réservée se DÉPOSE et la mère l'applique.
class EcranPlanAnnuel extends StatefulWidget with EcranMaquette {
  const EcranPlanAnnuel({super.key});
  @override
  String get titre => 'Plan de travail annuel (PTA)';
  @override
  String get description =>
      'Programmation des actions de la clinique pour l’exercice choisi : axes, objectifs, indicateurs et cibles, calendrier, responsables, budget, adoption par la Direction et suivi.';
  @override
  String get regle =>
      'Un plan adopté ne se réécrit pas : une révision ouvre une nouvelle version, l’ancienne reste consultable. Axes, états, sources de financement, périodicité, seuil de retard et préfixe de numérotation se règlent sous un geste réservé ; les valeurs semées sont des propositions à valider par la Direction.';

  @override
  State<EcranPlanAnnuel> createState() => _EcranPlanAnnuelState();
}

const TextStyle _petit = TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12);

/// Ce que l'écran lit, une fois par construction.
class _Contexte {
  _Contexte(this.c) : m = c.magasin {
    annee = ChoixExercice.courant(m, c.aujourdhui);
    exercice = ptaExercice(m.collection('exercices').toutes, annee);
    etatExercice = cpcEtatExercice(m.collection('exercices').toutes, annee);
    final dateReglage = parametreDateIso(ptaDateReglage(exercice, c.aujourdhui));
    final p = serviceParametres(m, auteur: () => 'lecture');
    decoupage = ptaDecoupageDe(p.valeur(ptaCleDecoupage, dateReglage));
    seuil = ptaSeuilDe(p.valeur(ptaCleSeuilRetard, dateReglage));
    prefixe = ptaPrefixeDe(p.valeur(ptaClePrefixe, dateReglage));
    // RIEN EN DUR : les signataires du plan et du bilan se lisent à l'organigramme (réglage « signataires du plan », sinon le poste qui coiffe l'organigramme).
    signataires = [for (final s in ptaSignataires(postes: m.collection('postes').actives, reglage: p.valeur(ptaCleSignataires, dateReglage))) Signature(s.intitule, nom: s.titulaire)];
    periodes = ptaPeriodes(exercice, decoupage);
    axes = m.collection(ptaCollectionAxes).toutes;
    etats = m.collection(ptaCollectionEtats).toutes;
    financements = m.collection(ptaCollectionFinancements).toutes;
    plans = m.collection(ptaCollectionPlans).toutes;
    toutesActions = m.collection(ptaCollectionActions).toutes;
    budgets = m.collection('budgets').toutes;
    ecritures = m.collection('ecritures').actives;
  }
  final ContexteEcran c;
  final Magasin m;
  late final int annee;
  late final PtaExercice exercice;
  late final String etatExercice;
  late final String decoupage;
  late final int seuil;
  late final String prefixe;
  late final List<Signature> signataires;
  late final List<PtaPeriode> periodes;
  late final List<Fiche> axes, etats, financements, plans, toutesActions, budgets, ecritures;

  PtaSynthese synthese(List<Fiche> actions) => ptaSynthese(actions, etats, auj: c.aujourdhui, seuilJours: seuil, budgets: budgets, ecritures: ecritures);
}

class _EcranPlanAnnuelState extends State<EcranPlanAnnuel> {
  bool _amorce = false;
  int? _version;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_amorce) return;
    _amorce = true;
    // Même mécanique que les écrans de M12 : les fiches d'exercice existent (sinon le sélecteur ne s'affiche pas), l'exercice du jour est le défaut.
    amorcerExercices(ContexteEcran.of(context).magasin, ContexteEcran.of(context).aujourdhui);
  }

  bool _rattache(ContexteEcran c) => ServiceInstallation.de(c.magasin).rattache;

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final m = c.magasin;
    return ListenableBuilder(
        listenable: Listenable.merge([
          for (final n in [...ptaCollections, 'budgets', 'ecritures', 'exercices', 'postes', parCollectionParametres, valCollectionDepots, 'rbac']) m.collection(n)
        ]),
        builder: (context, _) {
          final x = _Contexte(c);
          final versions = ptaPlansExercice(x.plans, x.annee);
          final plan = _version == null ? (versions.isEmpty ? null : versions.last) : ptaPlanVersion(x.plans, x.annee, _version!) ?? (versions.isEmpty ? null : versions.last);
          final v = plan == null ? 0 : ptaVersionDe(plan);
          final actions = plan == null ? <Fiche>[] : admTrierPlanPta(ptaActionsDuPlan(x.toutesActions, x.annee, v));
          final s = x.synthese(actions);
          final horsPlan = ptaActionsHorsPlan(x.toutesActions);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            admLectureSeule(c),
            if (!x.exercice.amorce)
              Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: NoteSigh('L’exercice ${x.annee} n’a pas de fiche d’exercice : ses périodes sont lues sur l’année civile.', ton: TonSigh.attention)),
            _bandeauPlan(context, x, versions, plan, actions, s),
            const SizedBox(height: 16),
            admKpis(ptaKpis(s)),
            if (s.enRetard > 0) ...[
              const SizedBox(height: 12),
              NoteSigh(
                  key: const Key('pta:retard'),
                  '${nombre(s.enRetard)} action${s.enRetard > 1 ? 's' : ''} en retard : période échue depuis plus de ${nombre(x.seuil)} jour${x.seuil > 1 ? 's' : ''} (seuil réglé aux paramètres) sans être terminée. Les détenteurs du geste « alerte de retard du plan » en sont avertis.',
                  ton: TonSigh.danger,
                  icone: LucideIcons.clockAlert),
            ],
            if (horsPlan.isNotEmpty) ...[
              const SizedBox(height: 12),
              NoteSigh(
                  '${nombre(horsPlan.length)} action${horsPlan.length > 1 ? 's' : ''} saisie${horsPlan.length > 1 ? 's' : ''} avant le PTA, sans exercice ni version : rattachée${horsPlan.length > 1 ? 's' : ''} à aucun plan, ni affichée${horsPlan.length > 1 ? 's' : ''} ni comptée${horsPlan.length > 1 ? 's' : ''} ici (RG-14 : rien n’est effacé).',
                  ton: TonSigh.neutre),
            ],
            const SizedBox(height: 16),
            CarteSigh(
                titre: 'Calendrier par ${x.decoupage == 'mois' ? 'mois' : (x.decoupage == 'semestre' ? 'semestre' : 'trimestre')} — exercice ${x.annee}',
                sansRemplissage: true,
                child: _frise(x, actions)),
            const SizedBox(height: 16),
            _tableau(context, x, plan, actions),
            const SizedBox(height: 16),
            _carteVersions(context, x, versions),
            const SizedBox(height: 16),
            _carteReferentiels(context, x),
          ]);
        });
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // Bandeau du plan : état, version, commandes du cycle
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  Widget _bandeauPlan(BuildContext context, _Contexte x, List<Fiche> versions, Fiche? plan, List<Fiche> actions, PtaSynthese s) {
    final c = x.c;
    final peutAdopter = gestePeutEcran(c, gestePtaAdopter);
    final service = ServiceValidationsDeposees.de(c.magasin);
    final commandes = <Widget>[];
    final notes = <Widget>[];
    if (plan == null) {
      if (c.droit.editer && x.etatExercice != 'clos') {
        commandes.add(BoutonSigh(libelle: 'Ouvrir le plan de l’exercice ${x.annee}', icone: LucideIcons.plus, onPressed: () => _creerPlan(context, x)));
      }
      notes.add(Text(
          x.etatExercice == 'clos'
              ? 'L’exercice ${x.annee} est clos : aucun plan n’y a été ouvert.'
              : 'Aucun plan pour l’exercice ${x.annee}. La clinique saisit le sien : ouvrir le plan, y ajouter les actions, puis le soumettre à l’adoption.',
          style: _petit));
    } else {
      final v = ptaVersionDe(plan);
      final etat = '${plan['etat']}';
      final dernier = versions.isNotEmpty && ptaVersionDe(versions.last) == v;
      final depot = service.depotPtaEnAttente(x.annee, v);
      final refuse = service.depotPtaRefuse(x.annee, v);
      if (depot != null) {
        notes.add(NoteSigh('Décision « ${depot['decision']} » transmise à la mère, en attente de confirmation : le plan reste « ${ptaLibelleEtatPlan(etat).toLowerCase()} » jusque-là.',
            ton: TonSigh.info, icone: LucideIcons.hourglass));
      } else if (refuse != null) {
        notes.add(NoteSigh('La mère a refusé la décision « ${refuse['decision']} » : ${refuse['resultatMotif'] ?? ''} ${refuse['resultatGeste'] ?? ''}'.trim(), ton: TonSigh.danger));
      }
      if (dernier && depot == null) {
        if (etat == ptaPlanBrouillon && c.droit.editer) {
          commandes.add(BoutonSigh(libelle: 'Nouvelle action', icone: LucideIcons.plus, onPressed: () => _saisirAction(context, x, plan, null)));
          commandes.add(BoutonSigh(libelle: 'Soumettre à l’adoption', icone: LucideIcons.send, variante: VarianteBouton.secondaire, onPressed: () => _soumettre(context, x, plan)));
        }
        if (etat == ptaPlanSoumis) {
          if (c.droit.editer) {
            commandes.add(BoutonSigh(libelle: 'Retirer la soumission', icone: LucideIcons.undo2, variante: VarianteBouton.secondaire, onPressed: () => _retirer(context, x, plan)));
          }
          if (peutAdopter) {
            commandes.add(BoutonSigh(libelle: 'Adopter le plan', icone: LucideIcons.stamp, variante: VarianteBouton.succes, onPressed: () => _decider(context, x, plan, ptaDecisionAdopter)));
            commandes.add(BoutonSigh(libelle: 'Renvoyer en brouillon', icone: LucideIcons.cornerUpLeft, variante: VarianteBouton.secondaire, onPressed: () => _decider(context, x, plan, ptaDecisionRenvoyer)));
          }
        }
        if (etat == ptaPlanAdopte && c.droit.editer) {
          commandes.add(BoutonSigh(libelle: 'Mettre en exécution', icone: LucideIcons.play, onPressed: () => _executer(context, x, plan)));
        }
        if (ptaEtatsPlanEnVigueur.contains(etat)) {
          if (c.droit.editer) {
            commandes.add(BoutonSigh(libelle: 'Réviser le plan', icone: LucideIcons.gitBranch, variante: VarianteBouton.secondaire, onPressed: () => _reviser(context, x)));
          }
          if (peutAdopter) {
            commandes.add(BoutonSigh(libelle: 'Clôturer le plan', icone: LucideIcons.lock, variante: VarianteBouton.secondaire, onPressed: () => _decider(context, x, plan, ptaDecisionCloturer)));
          }
        }
      }
      // RECONDUCTION : de l'exercice affiché vers le suivant, jamais l'inverse ; sous le droit d'écrire le plan.
      if (c.droit.editer) {
        commandes.add(BoutonSigh(
            key: const Key('pta:reconduire'),
            libelle: 'Reconduire les actions non réalisées vers l’exercice ${x.annee + 1}',
            icone: LucideIcons.copyPlus,
            variante: VarianteBouton.secondaire,
            onPressed: () => _reconduire(context, x)));
      }
      final infos = <String>[
        if (plan['reviseDe'] != null) 'Révision de la version ${plan['reviseDe']} : ${plan['motifRevision'] ?? ''}',
        if (plan['soumisPar'] != null && etat == ptaPlanSoumis) 'Soumis par ${plan['soumisPar']} le ${_date(plan['soumisLe'])}',
        if (plan['motifRenvoi'] != null && etat == ptaPlanBrouillon) 'Renvoyé en brouillon par ${plan['renvoyePar']} le ${_date(plan['renvoyeLe'])} : ${plan['motifRenvoi']}',
        if (plan['adoptePar'] != null) 'Adopté par ${plan['adoptePar']} le ${_date(plan['adopteLe'])} — ${plan['motifAdoption'] ?? ''}',
        if (plan['remplaceParVersion'] != null) 'Remplacé par la version ${plan['remplaceParVersion']} le ${_date(plan['remplaceLe'])}',
        if (plan['bilan'] is Map) 'Clôturé par ${plan['cloturePar']} le ${_date(plan['clotureLe'])} — bilan : ${(plan['bilan'] as Map)['texte'] ?? ''}',
      ];
      notes.insertAll(0, [for (final i in infos) Text(i, style: _petit)]);
    }
    final imprimer = [
      if (plan != null) BoutonSigh(libelle: 'Imprimer le plan', icone: LucideIcons.printer, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _imprimerPlan(context, x, plan, actions, s)),
      if (plan != null) BoutonSigh(libelle: 'Imprimer le bilan', icone: LucideIcons.fileChartColumn, taille: TailleBouton.sm, variante: VarianteBouton.secondaire, onPressed: () => _imprimerBilan(context, x, plan, actions, s)),
    ];
    return CarteSigh(
        titre: plan == null ? 'Plan de travail annuel — exercice ${x.annee}' : 'Plan ${ptaReferencePlan(x.annee, ptaVersionDe(plan))} — exercice ${x.annee}',
        actions: imprimer,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (plan != null)
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              BadgeSigh(ptaLibelleEtatPlan(plan['etat']), key: const Key('pta:etat-plan'), ton: matTon(ptaTonsEtatPlan['${plan['etat']}'] ?? 'neutre')),
              Text('Version ${ptaVersionDe(plan)} sur ${versions.length}', style: _petit),
              Text('Périodicité : ${x.decoupage} · seuil de retard : ${nombre(x.seuil)} j · numérotation ${x.prefixe}-${x.annee}-NNN', style: _petit),
            ]),
          if (notes.isNotEmpty) ...[const SizedBox(height: 8), ...notes.map((n) => Padding(padding: const EdgeInsets.only(bottom: 4), child: n))],
          if (commandes.isNotEmpty) ...[const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: commandes)],
        ]));
  }

  String _date(Object? v) {
    final d = DateTime.tryParse('${v ?? ''}');
    return d == null ? '—' : dateFR(d.toLocal());
  }

  void _toast(BuildContext ctx, RefusValidation r) => ToastsSigh.afficher(ctx, r.motif, type: TypeToast.erreur, detail: r.geste, duree: const Duration(seconds: 8));

  void _ecrire(BuildContext ctx, ContexteEcran c, List<PtaEcriture> ecritures, String action, String reference, Map<String, Object?> journal) {
    try {
      for (final e in ecritures) {
        c.magasin.collection(e.collection).mettreAJour(e.id, e.patch, journaliser: false);
      }
      c.magasin.journaliser(action, 'M13', 'Plan de travail annuel', reference, null, {...journal, 'par': acteurNom(c), 'rôle': c.role});
    } on EcritureRefusee catch (e) {
      ToastsSigh.afficher(ctx, 'Écriture refusée.', type: TypeToast.erreur, detail: e.motif);
    }
  }

  void _creerPlan(BuildContext ctx, _Contexte x) {
    final c = x.c;
    final r = ptaCreerPlan(annee: x.annee, plans: x.plans, acteur: acteurNom(c), maintenant: c.aujourdhui, etatExercice: x.etatExercice);
    if (!r.ok) return _toast(ctx, r.refus!);
    c.magasin.collection(ptaCollectionPlans).inserer(r.creation!);
    setState(() => _version = null);
    ToastsSigh.afficher(ctx, 'Plan ${r.creation!['reference']} ouvert en brouillon.', type: TypeToast.succes, detail: 'Ajouter les actions, puis soumettre le plan à l’adoption.');
  }

  void _soumettre(BuildContext ctx, _Contexte x, Fiche plan) {
    final r = ptaSoumettre(plan, x.toutesActions, acteur: acteurNom(x.c), maintenant: x.c.aujourdhui);
    if (!r.ok) return _toast(ctx, r.refus!);
    _ecrire(ctx, x.c, r.ecritures, 'Soumission du plan de travail annuel', '${plan['reference']}', const {});
    ToastsSigh.afficher(ctx, 'Plan soumis à l’adoption.', type: TypeToast.succes, detail: 'Un détenteur du geste « adopter » (autre que vous) l’adopte ou le renvoie, motif à l’appui.');
  }

  void _retirer(BuildContext ctx, _Contexte x, Fiche plan) {
    final r = ptaRetirerSoumission(plan, acteur: acteurNom(x.c), maintenant: x.c.aujourdhui);
    if (!r.ok) return _toast(ctx, r.refus!);
    _ecrire(ctx, x.c, r.ecritures, 'Retrait de la soumission du plan', '${plan['reference']}', const {});
  }

  void _executer(BuildContext ctx, _Contexte x, Fiche plan) {
    final r = ptaMettreEnExecution(plan, acteur: acteurNom(x.c), maintenant: x.c.aujourdhui);
    if (!r.ok) return _toast(ctx, r.refus!);
    _ecrire(ctx, x.c, r.ecritures, 'Mise en exécution du plan de travail annuel', '${plan['reference']}', const {});
    ToastsSigh.afficher(ctx, 'Plan en exécution.', type: TypeToast.succes);
  }

  /// Reconduit vers l'exercice suivant les actions ni réalisées ni abandonnées (règle du domaine : `ptaReconduire`). Le plan suivant naît en brouillon s'il n'existe pas ; relancer ne
  /// double rien ; chaque copie porte son lien d'origine ; le geste est journalisé (RG-12) et annulable d'un bloc.
  Future<void> _reconduire(BuildContext ctx, _Contexte x) async {
    final c = x.c;
    final cible = x.annee + 1;
    final apercu = ptaReconduire(
        annee: x.annee,
        plans: x.plans,
        actions: x.toutesActions,
        etats: x.etats,
        acteur: acteurNom(c),
        maintenant: c.aujourdhui,
        prefixe: x.prefixe,
        etatExerciceSuivant: cpcEtatExercice(c.magasin.collection('exercices').toutes, cible));
    if (!apercu.ok) return _toast(ctx, apercu.refus!);
    final ok = await confirmerSigh(ctx,
        titre: 'Reconduire vers l’exercice $cible ?',
        message:
            '${apercu.actions.length} action(s) non réalisée(s) et non abandonnée(s) du plan ${x.annee} seront recopiées dans le plan $cible (${apercu.planACreer != null ? 'créé en brouillon' : 'brouillon existant'}), avec leur lien d’origine. Les dates, le réalisé et la ligne de budget repartent de zéro ; les actions d’origine ne sont pas modifiées.${apercu.dejaReconduites.isEmpty ? '' : ' ${apercu.dejaReconduites.length} déjà reconduite(s) : ignorée(s).'}',
        libelleOk: 'Reconduire');
    if (!ok || !ctx.mounted) return;
    // Les données ont pu changer pendant la confirmation : le verdict est REFAIT sur le magasin courant.
    final y = _Contexte(c);
    final r = ptaReconduire(
        annee: y.annee,
        plans: y.plans,
        actions: y.toutesActions,
        etats: y.etats,
        acteur: acteurNom(c),
        maintenant: c.aujourdhui,
        prefixe: y.prefixe,
        etatExerciceSuivant: cpcEtatExercice(c.magasin.collection('exercices').toutes, cible));
    if (!r.ok) return _toast(ctx, r.refus!);
    final annulations = <VoidCallback>[];
    try {
      if (r.planACreer != null) annulations.add(c.magasin.collection(ptaCollectionPlans).inserer(r.planACreer!).annuler);
      for (final a in r.actions) {
        annulations.add(c.magasin.collection(ptaCollectionActions).inserer({...a, '_creePar': acteurNom(c), '_creeLe': c.aujourdhui.toIso8601String()}, prefixe: 'PTA').annuler);
      }
    } on EcritureRefusee catch (e) {
      for (final u in annulations.reversed) {
        u();
      }
      ToastsSigh.afficher(ctx, 'Reconduction refusée.', type: TypeToast.erreur, detail: e.motif);
      return;
    }
    c.magasin.journaliser('Reconduction du plan de travail annuel', 'M13', 'Plan de travail annuel', ptaReferencePlan(cible, r.version), null, {
      'de': ptaReferencePlan(y.annee, ptaVersionDe(ptaPlanCourant(y.plans, y.annee)!)),
      'actions recopiées': r.actions.length,
      'déjà reconduites': r.dejaReconduites.length,
      'par': acteurNom(c),
      'rôle': c.role
    });
    ToastsSigh.afficher(ctx, '${r.actions.length} action(s) reconduite(s) vers l’exercice $cible.',
        type: TypeToast.succes,
        detail: 'Dans le plan ${ptaReferencePlan(cible, r.version)} (brouillon) : les dates sont à replanifier.',
        annuler: () {
          for (final u in annulations.reversed) {
            u();
          }
        });
  }

  Future<void> _reviser(BuildContext ctx, _Contexte x) async {
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Réviser le plan ?',
        message: 'Une nouvelle version, en brouillon, recopie les actions. La version en vigueur le reste jusqu’à l’adoption de la révision ; elle sera alors « remplacée », jamais effacée.',
        libelleOk: 'Ouvrir la révision');
    if (motif == null || !ctx.mounted) return;
    final c = x.c;
    final r = ptaReviser(annee: x.annee, plans: x.plans, actions: x.toutesActions, acteur: acteurNom(c), motif: motif, maintenant: c.aujourdhui);
    if (r.refus != null) return _toast(ctx, r.refus!);
    c.magasin.collection(ptaCollectionPlans).inserer(r.plan!);
    for (final a in r.actions) {
      c.magasin.collection(ptaCollectionActions).inserer(a, prefixe: 'PTA');
    }
    c.magasin.journaliser('Révision du plan de travail annuel', 'M13', 'Plan de travail annuel', '${r.plan!['reference']}', null, {'motif': motif, 'par': acteurNom(c), 'actions recopiées': r.actions.length});
    setState(() => _version = null);
    ToastsSigh.afficher(ctx, 'Révision ${r.plan!['reference']} ouverte en brouillon.', type: TypeToast.succes);
  }

  /// Une décision RÉSERVÉE : sur la mère (ou un poste seul), le geste s'écrit ; sur un poste rattaché, il se DÉPOSE et la mère l'applique.
  Future<void> _decider(BuildContext ctx, _Contexte x, Fiche plan, String decision) async {
    final c = x.c;
    final v = ptaVersionDe(plan);
    final (titre, message, ok) = switch (decision) {
      ptaDecisionAdopter => (
          'Adopter le plan ${ptaReferencePlan(x.annee, v)} ?',
          'L’adoption fige le programme : il ne se réécrit plus, une révision ouvrira une nouvelle version. Motif obligatoire (instance, date de la décision).',
          'Adopter'
        ),
      ptaDecisionRenvoyer => ('Renvoyer le plan en brouillon ?', 'Le plan revient à son rédacteur. Dire ce qu’il faut reprendre.', 'Renvoyer'),
      _ => ('Clôturer le plan ${ptaReferencePlan(x.annee, v)} ?', 'La clôture arrête le bilan (indicateurs du jour) : plus rien ne s’écrit ensuite. Saisir le bilan.', 'Clôturer'),
    };
    final motif = await confirmerAvecMotif(ctx, titre: titre, message: message, libelleOk: ok);
    if (motif == null || !ctx.mounted) return;
    if (_rattache(c)) {
      final d = ServiceValidationsDeposees.de(c.magasin).deposerPta(decision, x.annee, v, role: c.role, acteur: acteurNom(c), motif: motif, gestes: droitsGestesEcran(c));
      if (!d.ok) return _toast(ctx, d.refus!);
      ToastsSigh.afficher(ctx, 'Décision transmise à la mère, en attente.', type: TypeToast.info, detail: 'La mère l’applique sous votre rôle, contrôles refaits ; le plan change d’état à la confirmation.');
      return;
    }
    final r = ptaDecider(
        decision: decision,
        annee: x.annee,
        version: v,
        role: c.role,
        acteur: acteurNom(c),
        motif: motif,
        gestes: droitsGestesEcran(c),
        plans: x.plans,
        actions: x.toutesActions,
        maintenant: c.aujourdhui,
        synthese: decision == ptaDecisionCloturer ? x.synthese(ptaActionsDuPlan(x.toutesActions, x.annee, v)) : null);
    if (!r.ok) return _toast(ctx, r.refus!);
    _ecrire(ctx, c, r.ecritures, 'Décision du plan de travail annuel (geste réservé)', ptaReferencePlan(x.annee, v), {'décision': decision, 'motif': motif});
    setState(() => _version = null);
    ToastsSigh.afficher(
        ctx,
        switch (decision) {
          ptaDecisionAdopter => 'Plan adopté.',
          ptaDecisionRenvoyer => 'Plan renvoyé en brouillon.',
          _ => 'Plan clôturé, bilan arrêté.',
        },
        type: TypeToast.succes);
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // Frise par période
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  Widget _frise(_Contexte x, List<Fiche> actions) {
    const entete = TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600);
    Widget h(String t, {bool centre = false}) =>
        Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: Align(alignment: centre ? Alignment.center : Alignment.centerLeft, child: Text(t, style: entete)));
    if (actions.isEmpty) {
      return const Padding(padding: EdgeInsets.all(16), child: Text('Aucune action dans ce plan.', style: _petit));
    }
    final largeur = 520.0 + 56.0 * x.periodes.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: largeur,
        child: Table(
          columnWidths: {
            0: const FixedColumnWidth(240),
            1: const FixedColumnWidth(150),
            for (var i = 0; i < x.periodes.length; i++) 2 + i: const FixedColumnWidth(56),
            2 + x.periodes.length: const FixedColumnWidth(130),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: const TableBorder(horizontalInside: BorderSide(color: JetonsShell.slate100)),
          children: [
            TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50), children: [
              h('Activité'),
              h('Axe'),
              for (final p in x.periodes) Tooltip(message: p.libelleLong, child: h(p.libelle, centre: true)),
              h('État'),
            ]),
            for (final a in actions)
              TableRow(children: [
                Padding(padding: const EdgeInsets.all(10), child: Text('${a['action'] ?? ''}', style: const TextStyle(color: JetonsShell.slate800, fontSize: 13, height: 18 / 13))),
                Padding(padding: const EdgeInsets.all(10), child: Text(ptaLibelleAxe(a['axe'], x.axes), style: _petit)),
                for (final p in x.periodes)
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                      child: Container(
                          key: Key('pta:barre:${a['reference']}:${p.code}'),
                          height: 12,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9999),
                              color: ptaCouvre(a, p)
                                  ? switch (ptaTonEtat(a['etat'], x.etats)) {
                                      'success' => JetonsShell.success400,
                                      'info' => JetonsShell.info400,
                                      'danger' => JetonsShell.danger400,
                                      'navy' => JetonsShell.navy400,
                                      'neutre' => JetonsShell.slate400,
                                      _ => JetonsShell.warning400,
                                    }
                                  : JetonsShell.slate100))),
                Padding(
                    padding: const EdgeInsets.all(10),
                    child: Align(alignment: Alignment.centerLeft, child: BadgeSigh(ptaLibelleEtat(a['etat'], x.etats), ton: matTon(ptaTonEtat(a['etat'], x.etats))))),
              ]),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // Tableau des actions
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  Widget _tableau(BuildContext context, _Contexte x, Fiche? plan, List<Fiche> actions) {
    final c = x.c;
    final etatPlan = '${plan?['etat'] ?? ''}';
    final arrete = etatPlan == ptaPlanCloture || etatPlan == ptaPlanRemplace;
    int? retard(Fiche a) => ptaJoursRetard(a, x.etats, c.aujourdhui, x.seuil);
    return TableauSigh(
      titre: 'Actions du plan',
      lignes: actions,
      taillePage: 15,
      nomExport: 'plan-de-travail-annuel-${x.annee}',
      messageVide: plan == null ? 'Aucun plan pour cet exercice.' : 'Aucune action dans ce plan.',
      filtres: [
        FiltreTableau(nom: 'axe', libelle: 'Axe', options: [for (final a in ptaAxesEnForce(x.axes)) OptionChamp('${a['code']}', '${a['libelle']}')]),
        FiltreTableau(nom: 'etat', libelle: 'État', options: [for (final e in ptaEtatsEnForce(x.etats)) OptionChamp('${e['code']}', '${e['libelle']}')]),
        FiltreTableau(nom: 'responsable', libelle: 'Responsable', options: admOptions(({for (final a in actions) '${a['responsable'] ?? ''}'}..remove('')).toList()..sort())),
        FiltreTableau(
            nom: 'retard',
            libelle: 'Retard',
            options: const [OptionChamp('oui', 'En retard'), OptionChamp('non', 'Dans les temps')],
            correspond: (l, v) => (retard(l) != null) == (v == 'oui')),
      ],
      alClicLigne: (f) => _consulter(context, x, f),
      actionsLigne: (ctx, f) => [
        BoutonIcone(icone: LucideIcons.eye, libelle: 'Consulter', onPressed: () => _consulter(ctx, x, f)),
        if (c.droit.editer && plan != null && !arrete) BoutonIcone(icone: LucideIcons.pencil, libelle: 'Modifier', onPressed: () => _saisirAction(ctx, x, plan, f)),
        if (c.droit.annuler && etatPlan == ptaPlanBrouillon) BoutonIcone(icone: LucideIcons.archive, libelle: 'Archiver', onPressed: () => admArchiver(ctx, c.magasin.collection(ptaCollectionActions), f)),
      ],
      colonnes: [
        ColonneTableau(cle: 'reference', libelle: 'N°', sansCoupure: true, rendu: (_, r) => matRef(r['reference'])),
        const ColonneTableau(cle: 'action', libelle: 'Activité'),
        ColonneTableau(cle: 'axe', libelle: 'Axe', texte: (r) => ptaLibelleAxe(r['axe'], x.axes)),
        ColonneTableau(cle: 'calendrier', libelle: 'Période', texte: (r) => ptaLibellePeriode(r, x.periodes)),
        const ColonneTableau(cle: 'responsable', libelle: 'Responsable'),
        ColonneTableau(cle: 'cibleValeur', libelle: 'Cible', droite: true, texte: (r) => _valeur(r['cibleValeur'], r['cibleUnite'])),
        ColonneTableau(cle: 'realiseValeur', libelle: 'Réalisé', droite: true, texte: (r) => _valeur(r['realiseValeur'], r['cibleUnite'])),
        ColonneTableau(
            cle: 'tauxAvancement',
            libelle: 'Avancement',
            droite: true,
            valeur: (r) => ptaTaux(r).valeur ?? -1,
            texte: (r) => '${ptaTaux(r).texte} (${ptaTaux(r).mode == 'saisi' ? 'saisi' : 'calculé'})'),
        ColonneTableau(cle: 'etat', libelle: 'État', texte: (r) => ptaLibelleEtat(r['etat'], x.etats), rendu: (_, r) => BadgeSigh(ptaLibelleEtat(r['etat'], x.etats), ton: matTon(ptaTonEtat(r['etat'], x.etats)))),
        ColonneTableau(
            cle: 'retard',
            libelle: 'Retard',
            droite: true,
            valeur: (r) => retard(r) ?? 0,
            texte: (r) => retard(r) == null ? '—' : '${retard(r)} j',
            rendu: (_, r) => retard(r) == null ? const Text('—', style: _petit) : BadgeSigh('${retard(r)} j', ton: TonSigh.danger)),
      ],
    );
  }

  String _valeur(Object? v, Object? unite) {
    final n = num.tryParse('${v ?? ''}');
    if (n == null) return '—';
    final u = '${unite ?? ''}'.trim();
    return u.isEmpty ? nombre(n) : '${nombre(n)} $u';
  }

  void _consulter(BuildContext ctx, _Contexte x, Fiche a) {
    final t = ptaTaux(a);
    final b = ptaBudgetLie(a, x.budgets);
    final r = ptaRealiseBudget(b, x.ecritures);
    final j = ptaJoursRetard(a, x.etats, x.c.aujourdhui, x.seuil);
    afficherTiroir<void>(ctx,
        titre: '${a['reference'] ?? ''} — ${a['action'] ?? ''}',
        sousTitre: ptaLibelleAxe(a['axe'], x.axes),
        largeurMax: 640,
        corps: DescListeSigh([
          ('Objectif spécifique', a['objectif']),
          ('Activité', a['action']),
          ('Résultat attendu', a['resultatAttendu']),
          ('Indicateur', a['indicateur']),
          ('Valeur de départ', _valeur(a['valeurDepart'], a['cibleUnite'])),
          ('Cible', _valeur(a['cibleValeur'], a['cibleUnite'])),
          ('Valeur réalisée', _valeur(a['realiseValeur'], a['cibleUnite'])),
          ('Écart (réalisé − cible)', ptaEcart(a) == null ? 'Non calculable' : _valeur(ptaEcart(a), a['cibleUnite'])),
          ('Avancement', '${t.texte} — ${t.explication}'),
          ('Calendrier', [for (final p in x.periodes) if (ptaCouvre(a, p)) p.libelleLong].join(', ')),
          ('Retard', j == null ? 'Aucun' : '$j jours (seuil : ${x.seuil} jours après la fin de la période)'),
          ('Responsable', a['responsable']),
          ('Service porteur', a['service']),
          ('Partenaires', a['partenaires']),
          ('Budget prévu', a['budgetPrevu'] == null ? null : money(a['budgetPrevu'])),
          ('Source de financement', ptaLibelleFinancement(a['sourceFinancement'], x.financements)),
          ('Ligne de budget liée', '${a['budgetReference'] ?? ''}'.isEmpty ? 'Aucune' : (b == null ? '${a['budgetReference']} — introuvable ou archivée au module Budgets' : '${b['reference']} (${b['centre'] ?? b['centreCout'] ?? ''})')),
          ('Budget réalisé', r == null ? 'Non calculable (aucune ligne liée)' : '${money(r)} — lu au module Budgets (débits de classe 6 du centre, exercice ${b?['exercice']})'),
          ('État', BadgeSigh(ptaLibelleEtat(a['etat'], x.etats), ton: matTon(ptaTonEtat(a['etat'], x.etats)))),
          ('Observations', a['observations']),
        ]));
  }

  /// Les responsables proposés : le PERSONNEL, puis les FONCTIONS et les SERVICES de l'organigramme (jamais une liste écrite ici).
  List<OptionChamp> _responsables(Magasin m) => [
        for (final e in trierPar(m.collection('personnel').actives, (e) => e['nomComplet'])) OptionChamp('personnel|${e['id']}|${e['nomComplet']}', '${e['nomComplet']} — ${e['poste'] ?? ''}'),
        for (final p in {for (final p in m.collection('postes').actives) '${p['poste'] ?? ''}'.trim()}..remove('')) OptionChamp('fonction||$p', 'Fonction : $p'),
        for (final s in _services(m)) OptionChamp('service||$s', 'Service : $s'),
      ];

  List<String> _services(Magasin m) => ({
        for (final s in m.collection('secteurs').actives) '${s['libelle'] ?? ''}'.trim(),
        for (final e in m.collection('personnel').actives) '${e['service'] ?? ''}'.trim(),
      }..remove(''))
          .toList()
        ..sort();

  void _saisirAction(BuildContext ctx, _Contexte x, Fiche plan, Fiche? existante) {
    final c = x.c;
    final fige = ptaEtatsPlanFiges.contains(plan['etat']);
    final etats = ptaEtatsEnForce(x.etats);
    final optionsEtat = [for (final e in etats) OptionChamp('${e['code']}', '${e['libelle']}')];
    final suivi = <ChampDef>[
      const ChampDef.section('Suivi'),
      ChampDef(nom: 'etat', libelle: 'État', type: TypeChamp.select, requis: true, options: optionsEtat),
      const ChampDef(nom: 'realiseValeur', libelle: 'Valeur réalisée', type: TypeChamp.nombre),
      const ChampDef(nom: 'tauxAvancement', libelle: 'Avancement saisi (%)', type: TypeChamp.nombre, condition: (controle: 'avancementMode', quand: ['saisi'])),
      const ChampDef(nom: 'observations', libelle: 'Observations', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
    ];
    final budgets = [for (final b in x.budgets) if (b['statut'] != 'archive' && '${b['exercice']}' == '${x.annee}') b];
    final programme = <ChampDef>[
      const ChampDef.section('Programme'),
      ChampDef(nom: 'axe', libelle: 'Axe', type: TypeChamp.select, requis: true, options: [for (final a in ptaAxesEnForce(x.axes)) OptionChamp('${a['code']}', '${a['libelle']}')]),
      const ChampDef(nom: 'objectif', libelle: 'Objectif spécifique', col: ColChamp.plein),
      const ChampDef(nom: 'action', libelle: 'Activité', requis: true, col: ColChamp.plein),
      const ChampDef(nom: 'resultatAttendu', libelle: 'Résultat attendu', col: ColChamp.plein),
      const ChampDef(nom: 'indicateur', libelle: 'Indicateur', col: ColChamp.plein),
      const ChampDef(nom: 'valeurDepart', libelle: 'Valeur de départ', type: TypeChamp.nombre, col: ColChamp.tiers),
      const ChampDef(nom: 'cibleValeur', libelle: 'Cible (valeur)', type: TypeChamp.nombre, col: ColChamp.tiers),
      const ChampDef(nom: 'cibleUnite', libelle: 'Unité', col: ColChamp.tiers),
      ChampDef(
          nom: 'calendrier',
          libelle: 'Calendrier (périodes)',
          type: TypeChamp.multiselect,
          requis: true,
          col: ColChamp.plein,
          aide: 'Cocher les périodes de l’exercice ${x.annee} (périodicité réglée : ${x.decoupage}).',
          options: [for (final p in x.periodes) OptionChamp('${p.debutIso}/${p.finIso}', p.libelleLong)]),
      ChampDef(nom: 'responsableChoix', libelle: 'Responsable', type: TypeChamp.select, requis: true, options: _responsables(c.magasin)),
      ChampDef(nom: 'service', libelle: 'Service porteur', type: TypeChamp.select, options: admOptions(_services(c.magasin))),
      const ChampDef(nom: 'partenaires', libelle: 'Partenaires', col: ColChamp.plein),
      const ChampDef(nom: 'budgetPrevu', libelle: 'Budget prévu (FCFA)', type: TypeChamp.nombre),
      ChampDef(nom: 'sourceFinancement', libelle: 'Source de financement', type: TypeChamp.select, options: [
        for (final f in ptaFinancementsEnForce(x.financements)) OptionChamp('${f['code']}', '${f['libelle']}')
      ]),
      ChampDef(
          nom: 'budgetReference',
          libelle: 'Ligne du module Budgets (facultatif)',
          type: TypeChamp.select,
          aide: 'Le budget réalisé est LU au module Budgets pour la ligne liée, jamais ressaisi.',
          options: [for (final b in budgets) OptionChamp('${b['reference']}', '${b['reference']} — ${b['centre'] ?? b['centreCout'] ?? ''} (${money(b['prevu'])})')]),
      const ChampDef(nom: 'avancementMode', libelle: 'Avancement', type: TypeChamp.select, requis: true, options: [
        OptionChamp('calcule', 'Calculé (réalisé ÷ cible)'),
        OptionChamp('saisi', 'Saisi'),
      ]),
    ];
    // Plan adopté : le MODE d'avancement fait partie du programme ; il s'affiche (il commande le champ du pourcentage) mais ne se change pas.
    final modeFige = existante == null ? 'calcule' : ptaModeAvancement(existante);
    final champs = fige
        ? [
            ChampDef(nom: 'avancementMode', libelle: 'Avancement', type: TypeChamp.select, requis: true, options: [
              OptionChamp(modeFige, modeFige == 'saisi' ? 'Saisi' : 'Calculé (réalisé ÷ cible)'),
            ]),
            ...suivi
          ]
        : [...programme, ...suivi];
    final initial = <String, Object?>{
      if (existante != null) ...{for (final e in existante.entries) e.key: e.value is num ? '${e.value}' : e.value},
      if (existante == null) ...{'etat': ptaEtatParDefaut(x.etats), 'avancementMode': 'calcule'},
      if (existante != null) 'avancementMode': ptaModeAvancement(existante),
      if (existante != null && existante['responsableType'] != null)
        'responsableChoix': '${existante['responsableType']}|${existante['responsableId'] ?? ''}|${existante['responsable'] ?? ''}',
      if (existante != null && existante['calendrier'] is List) 'calendrier': [for (final s in existante['calendrier'] as List) '$s'],
    };
    final ctl = ControleurFormulaire(champs, initial);
    afficherModale<void>(ctx,
        titre: existante == null ? 'Nouvelle action du plan' : (fige ? 'Suivi de l’action' : 'Modifier l’action'),
        sousTitre: existante == null
            ? 'Numérotation ${x.prefixe}-${x.annee}-NNN. Les champs marqués d’un astérisque sont obligatoires.'
            : '${existante['reference']}${fige ? ' — plan adopté : seul le suivi reste ouvert, le programme se change par une révision' : ''}',
        taille: TailleModale.lg,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: existante == null ? 'Créer' : 'Enregistrer',
                  icone: existante == null ? LucideIcons.plus : LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final f = <String, Object?>{
                      'etat': v['etat'],
                      'realiseValeur': admNombre(v['realiseValeur']),
                      'tauxAvancement': v['avancementMode'] == 'saisi' ? admNombre(v['tauxAvancement']) : null,
                      'observations': v['observations'],
                      'avancementMode': v['avancementMode'],
                    };
                    if (!fige) {
                      final cal = [for (final s in (v['calendrier'] as List? ?? const [])) '$s']..sort();
                      final bornes = ptaBornesCalendrier(cal);
                      final resp = '${v['responsableChoix'] ?? ''}'.split('|');
                      f.addAll({
                        'axe': v['axe'],
                        'objectif': v['objectif'],
                        'action': v['action'],
                        'resultatAttendu': v['resultatAttendu'],
                        'indicateur': v['indicateur'],
                        'valeurDepart': admNombre(v['valeurDepart']),
                        'cibleValeur': admNombre(v['cibleValeur']),
                        'cibleUnite': v['cibleUnite'],
                        'calendrier': cal,
                        'debut': bornes?.$1,
                        'fin': bornes?.$2,
                        'responsableType': resp.isNotEmpty ? resp[0] : null,
                        'responsableId': resp.length > 1 && resp[1].isNotEmpty ? resp[1] : null,
                        'responsable': resp.length > 2 ? resp.sublist(2).join('|') : null,
                        'service': v['service'],
                        'partenaires': v['partenaires'],
                        'budgetPrevu': admNombre(v['budgetPrevu']),
                        'sourceFinancement': v['sourceFinancement'],
                        'budgetReference': v['budgetReference'],
                      });
                    }
                    final propre = {for (final e in f.entries) if (e.value != null && e.value != '') e.key: e.value};
                    final col = c.magasin.collection(ptaCollectionActions);
                    fermer();
                    try {
                      if (existante == null) {
                        final r = col.inserer({
                          'statut': 'actif',
                          ...propre,
                          'exercice': x.annee,
                          'planVersion': ptaVersionDe(plan),
                          'reference': ptaReferenceSuivante(x.annee, x.toutesActions, prefixe: x.prefixe),
                          '_creePar': acteurNom(c),
                          '_creeLe': c.aujourdhui.toIso8601String(),
                        }, prefixe: 'PTA');
                        ToastsSigh.afficher(ctx, 'Action ${r.fiche['reference']} ajoutée au plan.', type: TypeToast.succes, annuler: r.annuler);
                      } else {
                        // Un champ vidé est retiré (`null`), jamais écrit vide : la garde compare ce qui CHANGE.
                        final patch = <String, Object?>{for (final k in f.keys) k: propre[k]};
                        final annuler = col.mettreAJour(existante['id'], patch);
                        ToastsSigh.afficher(ctx, 'Modifications enregistrées.', type: TypeToast.succes, annuler: annuler);
                      }
                    } on EcritureRefusee catch (e) {
                      ToastsSigh.afficher(ctx, 'Écriture refusée.', type: TypeToast.erreur, detail: e.motif);
                    }
                  }),
            ]);
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // Versions et référentiels
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  Widget _carteVersions(BuildContext context, _Contexte x, List<Fiche> versions) => CarteSigh(
        titre: 'Versions du plan — exercice ${x.annee}',
        child: versions.isEmpty
            ? const Text('Aucune version : le plan n’est pas encore ouvert.', style: _petit)
            : Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in versions)
                  ChoiceChip(
                    key: Key('pta:version:${ptaVersionDe(p)}'),
                    label: Text('V${ptaVersionDe(p)} · ${ptaLibelleEtatPlan(p['etat'])}'),
                    selected: (_version ?? ptaVersionDe(versions.last)) == ptaVersionDe(p),
                    onSelected: (_) => setState(() => _version = ptaVersionDe(p)),
                  ),
              ]),
      );

  Widget _carteReferentiels(BuildContext context, _Contexte x) {
    final c = x.c;
    final peutRegler = gestePeutEcran(c, gestePtaRegler);
    Widget bloc(String collection, String titre, List<Fiche> fiches) {
      final enForce = ptaReferentiel(fiches, () => ptaSemenceDe(collection));
      final archives = [for (final f in fiches) if (f['statut'] == 'archive') f];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(titre, style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, fontWeight: FontWeight.w600))),
          if (peutRegler)
            BoutonSigh(
                libelle: 'Ajouter',
                icone: LucideIcons.plus,
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                onPressed: () => _saisirReferentiel(context, x, collection, null)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in enForce)
            InputChip(
              key: Key('pta:ref:$collection:${f['code']}'),
              label: Text('${f['libelle']}${f['aValider'] == true ? ' · à valider' : ''}'),
              onPressed: peutRegler && fiches.isNotEmpty ? () => _saisirReferentiel(context, x, collection, f) : null,
              onDeleted: peutRegler && fiches.isNotEmpty
                  ? () {
                      final annuler = c.magasin.collection(collection).archiver(f['id']);
                      ToastsSigh.afficher(context, '« ${f['libelle']} » archivé.', type: TypeToast.succes, annuler: annuler, messageAnnulation: 'Archivage annulé.');
                    }
                  : null,
              deleteButtonTooltipMessage: 'Archiver',
            ),
          if (peutRegler)
            for (final f in archives)
              ActionChip(
                  label: Text('${f['libelle']} (archivé) — restaurer', style: _petit),
                  onPressed: () {
                    c.magasin.collection(collection).restaurer(f['id']);
                    ToastsSigh.afficher(context, '« ${f['libelle']} » restauré.', type: TypeToast.succes);
                  }),
        ]),
      ]);
    }

    return CarteSigh(
        titre: 'Référentiels du plan',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              'Modèle proposé par la Direction (16/11/2026) : chaque élément semé est une proposition à valider. ${peutRegler ? 'Vous les réglez (geste « ${gesteReserve(gestePtaRegler)!.libelle} »).' : 'Ils se règlent sous le geste « ${gesteReserve(gestePtaRegler)!.libelle} », que votre profil ne détient pas.'} Périodicité, seuil de retard et préfixe de numérotation se règlent aux Paramètres (famille « Plan de travail annuel »).',
              style: _petit),
          const SizedBox(height: 12),
          bloc(ptaCollectionAxes, 'Axes', x.axes),
          const SizedBox(height: 12),
          bloc(ptaCollectionEtats, 'États d’avancement', x.etats),
          const SizedBox(height: 12),
          bloc(ptaCollectionFinancements, 'Sources de financement', x.financements),
        ]));
  }

  void _saisirReferentiel(BuildContext ctx, _Contexte x, String collection, Fiche? existante) {
    final c = x.c;
    final etat = collection == ptaCollectionEtats;
    final champs = <ChampDef>[
      const ChampDef(nom: 'code', libelle: 'Code (immuable)', requis: true, indicatif: 'minuscules_et_soulignes'),
      const ChampDef(nom: 'libelle', libelle: 'Libellé', requis: true, col: ColChamp.plein),
      const ChampDef(nom: 'ordre', libelle: 'Ordre', type: TypeChamp.nombre),
      if (etat) ChampDef(nom: 'ton', libelle: 'Ton', type: TypeChamp.select, requis: true, options: admOptions(ptaTons)),
      if (etat) const ChampDef(nom: 'realise', libelle: 'Compte comme réalisée', type: TypeChamp.case_),
      if (etat) const ChampDef(nom: 'termine', libelle: 'Terminée (plus suivie, jamais en retard)', type: TypeChamp.case_),
      if (etat) const ChampDef(nom: 'exclutTaux', libelle: 'Exclue du taux d’exécution', type: TypeChamp.case_),
      if (etat) const ChampDef(nom: 'parDefaut', libelle: 'État d’une action nouvelle', type: TypeChamp.case_),
    ];
    final ctl = ControleurFormulaire(champs, existante == null ? {'ton': 'info'} : {for (final e in existante.entries) e.key: e.value is num ? '${e.value}' : e.value});
    afficherModale<void>(ctx,
        titre: existante == null ? 'Ajouter au référentiel' : 'Modifier « ${existante['libelle']} »',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final f = <String, Object?>{
                      'code': '${v['code'] ?? ''}'.trim(),
                      'libelle': '${v['libelle'] ?? ''}'.trim(),
                      if (admNombre(v['ordre']) != null) 'ordre': admNombre(v['ordre']),
                      if (etat) ...{'ton': v['ton'], 'realise': v['realise'] == true, 'termine': v['termine'] == true, 'exclutTaux': v['exclutTaux'] == true, 'parDefaut': v['parDefaut'] == true},
                      // Régler une fiche l'ARRÊTE : la mention « à valider » tombe, l'auteur et la date sont portés.
                      'aValider': false,
                      'arreteLe': c.aujourdhui.toIso8601String(),
                      'arretePar': acteurNom(c),
                    };
                    final col = c.magasin.collection(collection);
                    final r = ptaControlerReferentiel(collection, f, col.toutes, avant: existante, role: c.role, gestes: droitsGestesEcran(c));
                    if (r != null) return _toast(ctx, r);
                    fermer();
                    if (existante == null) {
                      final ins = col.inserer({'statut': 'actif', ...f}, prefixe: collection == ptaCollectionAxes ? 'PTAX' : (etat ? 'PTAE' : 'PTAF'));
                      ToastsSigh.afficher(ctx, '« ${f['libelle']} » ajouté.', type: TypeToast.succes, annuler: ins.annuler);
                    } else {
                      final annuler = col.mettreAJour(existante['id'], {...f, 'mention': null});
                      ToastsSigh.afficher(ctx, '« ${f['libelle']} » enregistré.', type: TypeToast.succes, annuler: annuler);
                    }
                  }),
            ]);
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // Impression : le plan et le bilan (gabarit A4 en paysage, en-tête légal unique)
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  List<(String, String)> _cartouche(_Contexte x, Fiche plan, PtaSynthese s) => [
        ('Exercice', '${x.annee}'),
        ('Version', 'V${ptaVersionDe(plan)} — ${ptaLibelleEtatPlan(plan['etat'])}'),
        ('Actions programmées', nombre(s.programmees)),
        ('Réalisées', nombre(s.realisees)),
        ('En retard', nombre(s.enRetard)),
        ('Taux d’exécution', s.taux == null ? 'Non calculable' : '${s.taux} %'),
        if (plan['adoptePar'] != null) ('Adopté par', '${plan['adoptePar']} le ${_date(plan['adopteLe'])}'),
        ('Date d’édition', dateFR(x.c.aujourdhui)),
      ];

  void _imprimerPlan(BuildContext ctx, _Contexte x, Fiche plan, List<Fiche> actions, PtaSynthese s) {
    matImprimer(ctx,
        titre: 'Plan de travail annuel',
        sousTitre: 'Exercice ${x.annee} — ${ptaReferencePlan(x.annee, ptaVersionDe(plan))}',
        filigrane: ptaEtatsPlanFiges.contains(plan['etat']) ? null : 'Projet',
        paysage: true,
        cartouche: _cartouche(x, plan, s),
        blocs: [
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'N°', valeur: (r) => r['reference']),
            ColonneEtat(libelle: 'Axe', valeur: (r) => ptaLibelleAxe(r['axe'], x.axes)),
            ColonneEtat(libelle: 'Objectif spécifique', valeur: (r) => r['objectif']),
            ColonneEtat(libelle: 'Activité', valeur: (r) => r['action']),
            ColonneEtat(libelle: 'Résultat attendu', valeur: (r) => r['resultatAttendu']),
            ColonneEtat(libelle: 'Indicateur', valeur: (r) => r['indicateur']),
            ColonneEtat(libelle: 'Départ', droite: true, valeur: (r) => _valeur(r['valeurDepart'], null)),
            ColonneEtat(libelle: 'Cible', droite: true, valeur: (r) => _valeur(r['cibleValeur'], r['cibleUnite'])),
            ColonneEtat(libelle: 'Calendrier', valeur: (r) => ptaLibellePeriode(r, x.periodes)),
            ColonneEtat(libelle: 'Responsable', valeur: (r) => r['responsable']),
            ColonneEtat(libelle: 'Service porteur', valeur: (r) => r['service']),
            ColonneEtat(libelle: 'Partenaires', valeur: (r) => r['partenaires']),
            ColonneEtat(libelle: 'Budget prévu', droite: true, valeur: (r) => r['budgetPrevu'] == null ? '—' : money(r['budgetPrevu']), somme: (r) => num.tryParse('${r['budgetPrevu'] ?? ''}') ?? 0),
            ColonneEtat(libelle: 'Financement', valeur: (r) => ptaLibelleFinancement(r['sourceFinancement'], x.financements)),
          ], lignes: actions), titre: 'Programme'),
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'N°', valeur: (r) => r['reference']),
            ColonneEtat(libelle: 'Activité', valeur: (r) => r['action']),
            ColonneEtat(libelle: 'Réalisé', droite: true, valeur: (r) => _valeur(r['realiseValeur'], r['cibleUnite'])),
            ColonneEtat(libelle: 'Avancement', droite: true, valeur: (r) => '${ptaTaux(r).texte} (${ptaTaux(r).mode == 'saisi' ? 'saisi' : 'calculé'})'),
            ColonneEtat(libelle: 'Budget réalisé (module Budgets)', droite: true, valeur: (r) {
              final b = ptaRealiseBudget(ptaBudgetLie(r, x.budgets), x.ecritures);
              return b == null ? '—' : money(b);
            }),
            ColonneEtat(libelle: 'État', valeur: (r) => ptaLibelleEtat(r['etat'], x.etats)),
            ColonneEtat(libelle: 'Observations', valeur: (r) => r['observations']),
          ], lignes: actions), titre: 'Suivi'),
          if (ptaSemenceAxes().isNotEmpty && [...x.axes, ...x.etats, ...x.financements].any((f) => f['aValider'] == true))
            const BlocTexte('Référentiels du plan : certains éléments sont des propositions à valider par la Direction (modèle proposé le 16/11/2026).', italique: true),
        ],
        signatures: x.signataires);
  }

  void _imprimerBilan(BuildContext ctx, _Contexte x, Fiche plan, List<Fiche> actions, PtaSynthese s) {
    final bilan = plan['bilan'] is Map ? (plan['bilan'] as Map).cast<String, Object?>() : null;
    matImprimer(ctx,
        titre: 'Bilan du plan de travail annuel',
        sousTitre: 'Exercice ${x.annee} — ${ptaReferencePlan(x.annee, ptaVersionDe(plan))}${bilan == null ? ' — bilan provisoire (plan non clôturé)' : ''}',
        filigrane: bilan == null ? 'Provisoire' : null,
        paysage: true,
        cartouche: [
          ..._cartouche(x, plan, s),
          ('Budget prévu', money(s.budgetPrevu)),
          ('Budget réalisé (module Budgets)', s.budgetRealise == null ? 'Aucune ligne liée' : money(s.budgetRealise)),
          if (bilan != null) ('Arrêté le', '${_date(bilan['arreteLe'])} par ${bilan['arretePar'] ?? ''}'),
        ],
        blocs: [
          if (bilan != null) BlocTexte('Bilan : ${bilan['texte'] ?? ''}'),
          BlocTableau(TableauEtat(colonnes: [
            ColonneEtat(libelle: 'N°', valeur: (r) => r['reference']),
            ColonneEtat(libelle: 'Axe', valeur: (r) => ptaLibelleAxe(r['axe'], x.axes)),
            ColonneEtat(libelle: 'Activité', valeur: (r) => r['action']),
            ColonneEtat(libelle: 'Indicateur', valeur: (r) => r['indicateur']),
            ColonneEtat(libelle: 'Cible', droite: true, valeur: (r) => _valeur(r['cibleValeur'], r['cibleUnite'])),
            ColonneEtat(libelle: 'Réalisé', droite: true, valeur: (r) => _valeur(r['realiseValeur'], r['cibleUnite'])),
            ColonneEtat(libelle: 'Écart', droite: true, valeur: (r) => ptaEcart(r) == null ? 'Non calculable' : _valeur(ptaEcart(r), r['cibleUnite'])),
            ColonneEtat(libelle: 'Avancement', droite: true, valeur: (r) => '${ptaTaux(r).texte} (${ptaTaux(r).mode == 'saisi' ? 'saisi' : 'calculé'})'),
            ColonneEtat(libelle: 'Budget prévu', droite: true, valeur: (r) => r['budgetPrevu'] == null ? '—' : money(r['budgetPrevu']), somme: (r) => num.tryParse('${r['budgetPrevu'] ?? ''}') ?? 0),
            ColonneEtat(libelle: 'Budget réalisé', droite: true, valeur: (r) {
              final b = ptaRealiseBudget(ptaBudgetLie(r, x.budgets), x.ecritures);
              return b == null ? '—' : money(b);
            }),
            ColonneEtat(libelle: 'État', valeur: (r) => ptaLibelleEtat(r['etat'], x.etats)),
            ColonneEtat(libelle: 'Retard', droite: true, valeur: (r) {
              final j = ptaJoursRetard(r, x.etats, x.c.aujourdhui, x.seuil);
              return j == null ? '—' : '$j j';
            }),
          ], lignes: actions)),
          const BlocTexte('Le budget réalisé est lu au module Budgets (une ligne liée comptée une fois au total du cartouche) ; « Non calculable » n’est pas zéro.', italique: true),
        ],
        signatures: x.signataires);
  }
}

/// Les actions dans l'ordre du plan : par date de début, puis par référence.
List<Fiche> admTrierPlanPta(List<Fiche> actions) => [...actions]..sort((a, b) {
    final d = '${a['debut'] ?? ''}'.compareTo('${b['debut'] ?? ''}');
    return d != 0 ? d : comparerNaturel('${a['reference'] ?? ''}', '${b['reference'] ?? ''}');
  });
