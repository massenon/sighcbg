import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/planning_rh_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import 'rhb_circuit.dart' show rhbPlanningPoste, rhbToastRefus;
import 'rhb_commun.dart';
import 'rhb_planning.dart' show honoraireReserve;

/// PLANNING INDIVIDUEL (Direction, 16/11/2026, `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md` §8) : l'onglet « Planning individuel » de la fiche du personnel — le régime
/// EFFECTIF de l'agent (catégorie, dérogation champ par champ ou remplacement), champ par champ avec sa provenance et ses valeurs d'attente, son calendrier de la semaine
/// ou du mois (vacations, gardes, permanences, repos, congés) et l'édition de son régime individuel.
///
/// Aucune règle ici : la résolution du régime est `regimeRhALaDate` (une seule fonction, lue aussi par le planning, les primes, la paie et « Mon espace »), la pose d'une
/// version est `validerRegimeIndividuelRh` (refus nommés), le calendrier et l'honoraire du mois sont ceux du domaine. Les DROITS viennent de la MATRICE, jamais d'un nom
/// de rôle : lire l'onglet demande de voir `m10-planning` ; écrire, d'y avoir le droit d'écrire ET le geste réservé « régler le planning » ; les montants d'honoraire
/// se lisent avec le droit d'écrire le planning ou de voir `m10-primes` (la règle de `voitHonorairesPlanning`). Une commande interdite est ABSENTE.
({bool lire, bool ecrire, bool montants}) droitsPlanningIndividuel(ContexteEcran c) {
  final mat = c.donnees?.matrice;
  final lire = mat == null ? c.droit.voir : mat.peutVoir(c.role, 'm10-planning');
  final ecrireEcran = mat == null ? c.droit.editer : mat.peutEditer(c.role, 'm10-planning');
  return (
    lire: lire,
    ecrire: lire && ecrireEcran && gestePeutEcran(c, gesteRhRegler),
    montants: mat == null || ecrireEcran || mat.peutVoir(c.role, 'm10-primes'),
  );
}

const Map<String, String> _libellesProvenance = {
  provenanceCategorieRh: 'Catégorie',
  provenanceRemplacementRh: 'Régime adopté',
  provenanceIndividuelleRh: 'Individuel',
};

String _jours(List<String>? j) =>
    j == null || j.isEmpty ? 'Tous les jours (aucune restriction écrite)' : [for (final x in joursSemaineRh) if (j.contains(x.id)) x.libelle].join(', ');

/// Le texte d'un champ du régime en vigueur (`montants` faux : l'honoraire est dit réservé, jamais vidé).
String texteChampRegime(RegimeRhResolu r, String champ, {bool montants = true}) {
  switch (champ) {
    case 'vacations':
      if (r.vacations.isEmpty) return '—';
      return [
        for (final v in r.vacations)
          () {
            final h = horairesVacationRh(r, v);
            return h.debut == null ? rhbTypePlanningLabel(v) : '${rhbTypePlanningLabel(v)} (${h.debut} → ${h.fin}, ${nombre(h.duree)} h)';
          }()
      ].join(' ; ');
    case 'repos':
      return r.repos == null ? 'Aucun repos codifié' : rhbTypePlanningLabel(r.repos);
    case 'cycle':
      return r.cycle == null ? '—' : '${nombre(r.cycle)} jours';
    case 'honoraire':
      if (r.honoraire == null) return 'Aucun';
      return montants ? money(r.honoraire) : honoraireReserve;
    case 'honorairePeriodicite':
      return r.honoraire == null ? '—' : (r.honorairePeriodicite == 'occurrence' ? 'Par occurrence' : 'Mensuelle');
    case 'heureDebut':
      return r.heureDebut ?? 'Selon la vacation (référentiel)';
    case 'heureFin':
      return r.heureFin ?? 'Selon la vacation (référentiel)';
    case 'dureeHeures':
      return r.dureeHeures == null ? 'Selon la vacation (référentiel)' : '${nombre(r.dureeHeures)} h';
    case 'jours':
      return _jours(r.jours);
  }
  return '—';
}

String _mode(RegimeRhResolu r) => switch (r.mode) {
      'remplacement' => 'Remplacement du régime de la catégorie',
      'derogation' => 'Dérogation individuelle',
      _ => 'Régime de la catégorie',
    };

/// Le régime EFFECTIF d'un agent, champ par champ : valeur, provenance, et la mention « à valider » d'une valeur d'attente. Servie par la fiche du personnel et par
/// « Mon espace ».
class CarteRegimeEffectif extends StatelessWidget {
  const CarteRegimeEffectif({super.key, required this.regime, this.titre = 'Régime de travail en vigueur', this.montants = true, this.actions = const []});
  final RegimeRhResolu regime;
  final String titre;
  final bool montants;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final r = regime;
    if (r.categorie == null && !r.individuel) {
      return CarteSigh(
          titre: titre,
          actions: actions,
          child: const VideSigh('Aucun régime de travail ne couvre cette fonction : le planning propose tous les types de vacation.', icone: LucideIcons.calendarOff));
    }
    final lignes = <Fiche>[
      for (final champ in champsRegimeIndividuelRh)
        if (champ != 'honorairePeriodicite' || r.honoraire != null) {'champ': champ},
    ];
    return CarteSigh(
      key: const Key('pli:regime'),
      titre: titre,
      actions: actions,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(r.libelle ?? r.categorie ?? '—', style: const TextStyle(color: JetonsShell.slate900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
          BadgeSigh(_mode(r), ton: r.mode == 'remplacement' ? TonSigh.attention : (r.individuel ? TonSigh.info : TonSigh.neutre)),
          if (r.aValider.isNotEmpty) BadgeSigh('${r.aValider.length} valeur(s) à valider', ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
        ]),
        const SizedBox(height: 8),
        DescListeSigh([
          if (r.mode == 'remplacement') ('Catégorie de l’agent', r.categorie),
          if (r.mode == 'remplacement') ('Régime adopté', r.baseRemplacement ?? 'Composé champ par champ'),
          if (r.dateEffet != null) ('En vigueur depuis', dateFR(DateTime.parse(r.dateEffet!))),
          if (r.individuel && r.motif != null) ('Motif', r.motif),
          if (r.individuel) ('Document d’origine', r.sourceDocument ?? 'Aucun (valeurs d’attente)'),
          if (!r.individuel || r.mode == 'remplacement') ('Source du régime', r.source),
        ]),
        const SizedBox(height: 12),
        MiniTableauSigh(colonnes: [
          ColonneMini('Champ', (l) => libellesChampsRegimeRh[l['champ']] ?? '${l['champ']}'),
          ColonneMini('Valeur', (l) => texteChampRegime(r, '${l['champ']}', montants: montants),
              rendu: (l) => Text(texteChampRegime(r, '${l['champ']}', montants: montants),
                  key: Key('pli:valeur:${l['champ']}'),
                  style: TextStyle(
                      color: JetonsShell.slate700,
                      fontSize: 12,
                      height: 16 / 12,
                      fontStyle: !montants && l['champ'] == 'honoraire' && r.honoraire != null ? FontStyle.italic : FontStyle.normal))),
          ColonneMini('Provenance', (l) => _libellesProvenance[r.provenances['${l['champ']}']] ?? '—', rendu: (l) {
            final p = r.provenances['${l['champ']}'];
            if (p == null) return const Text('—', style: TextStyle(color: JetonsShell.slate300, fontSize: 12));
            return BadgeSigh(_libellesProvenance[p]!, ton: p == provenanceIndividuelleRh ? TonSigh.info : (p == provenanceRemplacementRh ? TonSigh.attention : TonSigh.neutre));
          }),
          ColonneMini('Statut', (l) => r.aValider.contains(l['champ']) ? 'À valider' : '', rendu: (l) {
            if (!r.aValider.contains(l['champ'])) return const SizedBox.shrink();
            return BadgeSigh('À valider', key: Key('pli:a-valider:${l['champ']}'), ton: TonSigh.attention);
          }),
        ], lignes: lignes),
        if (r.aValider.isNotEmpty) ...[
          const SizedBox(height: 8),
          const NoteSigh('« À valider » : valeur d’attente, posée sans document d’origine. Elle s’applique, et reste marquée jusqu’à une nouvelle version appuyée sur un document.',
              ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
        ],
      ]),
    );
  }
}

/// L'onglet « Planning individuel » de la fiche du personnel.
class OngletPlanningIndividuel extends StatefulWidget {
  const OngletPlanningIndividuel({super.key, required this.agent, required this.c, required this.ctx});
  final Fiche agent;
  final ContexteEcran c;

  /// Le contexte de l'écran (celui qui peut ouvrir une modale de saisie).
  final BuildContext ctx;

  @override
  State<OngletPlanningIndividuel> createState() => _EtatOnglet();
}

class _EtatOnglet extends State<OngletPlanningIndividuel> {
  String _vue = 'semaine';
  DateTime? _ref;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final d = droitsPlanningIndividuel(c);
    if (!d.lire) {
      return const Padding(
          padding: EdgeInsets.only(top: 16),
          child: VideSigh('Le planning de l’agent se lit avec le droit de lire le planning du personnel.',
              indice: 'Votre profil n’ouvre pas « Planning & gardes » : la matrice des droits le décide.', icone: LucideIcons.lock));
    }
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: ListenableBuilder(
            listenable: Listenable.merge([for (final n in const ['planning', 'conges', 'regimesTravail', 'regimesIndividuels']) c.magasin.collection(n)]),
            builder: (context, _) => _corps(context, c, d)));
  }

  Widget _corps(BuildContext context, ContexteEcran c, ({bool lire, bool ecrire, bool montants}) d) {
    final p = rhbPlanningPoste(c);
    final e = widget.agent;
    final aujourdhui = iso(c.aujourdhui);
    final regime = p.regimeALaDate(e, aujourdhui);
    final ref = _ref ?? c.aujourdhui;
    final cal = p.calendrier(e, _vue, ref);
    final historique = p.historique(e['id']);
    final travaillees = cal.where((j) => j.vacation != null && (rhbTypePlanning(j.vacation!['type'])?.duree ?? 0) > 0).toList();
    final hon = p.honoraireMois(e, ref.year, ref.month);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteRegimeEffectif(
        regime: regime,
        montants: d.montants,
        actions: [
          if (historique.isNotEmpty)
            BoutonSigh(
                libelle: 'Historique (${historique.length})',
                icone: LucideIcons.history,
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                onPressed: () => _historique(widget.ctx, historique, d.montants)),
          if (d.ecrire) ...[
            BoutonSigh(libelle: 'Déroger', icone: LucideIcons.userCog, taille: TailleBouton.sm, onPressed: () => ouvrirSaisieRegime(widget.ctx, c, p, e, modeDerogationRh)),
            BoutonSigh(
                libelle: 'Remplacer le régime',
                icone: LucideIcons.replace,
                taille: TailleBouton.sm,
                variante: VarianteBouton.secondaire,
                onPressed: () => ouvrirSaisieRegime(widget.ctx, c, p, e, modeRemplacementRh)),
            if (regime.individuel)
              BoutonSigh(
                  libelle: 'Revenir à la catégorie',
                  icone: LucideIcons.undo2,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: () => ouvrirSaisieRegime(widget.ctx, c, p, e, modeRetourRh)),
          ],
        ],
      ),
      const SizedBox(height: 16),
      KpiGrilleSigh(colonnes: 4, kpis: [
        KpiSigh(libelle: 'Vacations travaillées', valeur: nombre(travaillees.length), icone: LucideIcons.calendarCheck, ton: TonSigh.navy),
        KpiSigh(
            libelle: 'Gardes',
            valeur: nombre(cal.where((j) => vacationsGardeRh.contains(j.vacation?['type']) || j.vacation?['type'] == 'garde_soins').length),
            icone: LucideIcons.moon,
            ton: TonSigh.danger),
        KpiSigh(libelle: 'Repos et congés', valeur: nombre(cal.where((j) => j.conge != null || '${j.vacation?['type'] ?? ''}'.startsWith('repos') || j.vacation?['type'] == 'conge').length), icone: LucideIcons.bed, ton: TonSigh.info),
        KpiSigh(
            libelle: 'Honoraire de régime (${moisAnnee(ref)})',
            valeur: d.montants ? money(hon.montant) : honoraireReserve,
            icone: LucideIcons.wallet,
            ton: TonSigh.succes,
            indice: hon.aValider ? 'Montant d’attente, à valider' : (hon.montant == 0 ? 'Aucun honoraire du régime ce mois' : 'Planning validé seul (RG-11)')),
      ]),
      const SizedBox(height: 16),
      CarteSigh(
        titre: _vue == 'semaine'
            ? 'Semaine du ${dateFR(DateTime.parse(cal.first.date))} au ${dateFR(DateTime.parse(cal.last.date))}'
            : 'Planning de ${moisAnnee(DateTime.parse(cal.first.date))}',
        actions: [
          BoutonIcone(key: const Key('pli:precedent'), icone: LucideIcons.chevronLeft, libelle: _vue == 'semaine' ? 'Semaine précédente' : 'Mois précédent', onPressed: () => _decaler(ref, -1)),
          BoutonIcone(key: const Key('pli:suivant'), icone: LucideIcons.chevronRight, libelle: _vue == 'semaine' ? 'Semaine suivante' : 'Mois suivant', onPressed: () => _decaler(ref, 1)),
          BoutonSigh(
              key: const Key('pli:vue:semaine'),
              libelle: 'Semaine',
              taille: TailleBouton.sm,
              variante: _vue == 'semaine' ? VarianteBouton.primaire : VarianteBouton.secondaire,
              onPressed: () => setState(() => _vue = 'semaine')),
          BoutonSigh(
              key: const Key('pli:vue:mois'),
              libelle: 'Mois',
              taille: TailleBouton.sm,
              variante: _vue == 'mois' ? VarianteBouton.primaire : VarianteBouton.secondaire,
              onPressed: () => setState(() => _vue = 'mois')),
        ],
        child: _vue == 'semaine' ? _semaine(cal) : _mois(cal, c),
      ),
      const SizedBox(height: 8),
      const NoteSigh(
          'Chaque jour se lit sous le régime EN VIGUEUR À CE JOUR (une dérogation datée n’efface jamais l’historique). Les congés affichés sont les congés validés. Une vacation posée garde le régime sous lequel elle l’a été.'),
    ]);
  }

  void _decaler(DateTime ref, int sens) => setState(() => _ref = _vue == 'semaine' ? ajouterJours(ref, 7 * sens) : DateTime(ref.year, ref.month + sens, 1));

  static const _nomsJours = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];

  String _texteJour(JourPlanningRh j) {
    final v = j.vacation;
    if (v != null) return rhbTypePlanningLabel(v['type']);
    if (j.conge != null) return 'Congé';
    return j.travailleParRegime ? '' : 'Hors jours du régime';
  }

  Widget _semaine(List<JourPlanningRh> cal) => MiniTableauSigh(colonnes: [
        ColonneMini('Jour', (j) => dateJour(DateTime.parse('${j['date']}'))),
        ColonneMini('Vacation', (j) => _texteJour(j['j'] as JourPlanningRh), rendu: (l) {
          final j = l['j'] as JourPlanningRh;
          final t = _texteJour(j);
          if (t.isEmpty) return const Text('—', style: TextStyle(color: JetonsShell.slate300, fontSize: 12));
          final ton = j.vacation != null ? rhbTon(rhbTypePlanningTon(j.vacation!['type'])) : (j.conge != null ? TonSigh.succes : TonSigh.neutre);
          return BadgeSigh(t, key: Key('pli:jour:${j.date}'), ton: ton);
        }),
        ColonneMini('Horaires', (l) {
          final h = (l['j'] as JourPlanningRh).horaires;
          if (h == null || h.debut == null) return '—';
          return '${h.debut} → ${h.fin} (${nombre(h.duree)} h)${h.provenance == 'regime' ? ' · régime individuel' : ''}';
        }),
        ColonneMini('Régime du jour', (l) {
          final r = (l['j'] as JourPlanningRh).regime;
          return '${r.libelle ?? r.categorie ?? '—'}${r.individuel ? ' (individuel)' : ''}';
        }),
        ColonneMini('Validation', (l) {
          final j = l['j'] as JourPlanningRh;
          return j.vacation == null ? '' : (j.validee ? 'Validée' : 'À valider');
        }),
      ], lignes: [
        for (final j in cal) {'date': j.date, 'j': j}
      ]);

  Widget _mois(List<JourPlanningRh> cal, ContexteEcran c) {
    final premier = DateTime.parse(cal.first.date);
    final decalage = premier.weekday - 1;
    final cases = <JourPlanningRh?>[for (var i = 0; i < decalage; i++) null, ...cal];
    while (cases.length % 7 != 0) {
      cases.add(null);
    }
    const tete = TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600);
    return Table(
      border: TableBorder.all(color: JetonsShell.slate100),
      children: [
        TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50), children: [
          for (final n in _nomsJours) Padding(padding: const EdgeInsets.all(6), child: Text(n, textAlign: TextAlign.center, style: tete)),
        ]),
        for (var s = 0; s < cases.length; s += 7)
          TableRow(children: [
            for (final j in cases.sublist(s, s + 7))
              Container(
                height: 64,
                padding: const EdgeInsets.all(4),
                color: j == null
                    ? JetonsShell.slate50
                    : (j.date == iso(c.aujourdhui) ? JetonsShell.navy50 : (j.travailleParRegime ? null : JetonsShell.slate100)),
                child: j == null
                    ? const SizedBox.shrink()
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${DateTime.parse(j.date).day}', style: const TextStyle(color: JetonsShell.slate500, fontSize: 11, height: 14 / 11)),
                        const SizedBox(height: 2),
                        if (_texteJour(j).isNotEmpty)
                          Flexible(
                              child: BadgeSigh(
                                  j.vacation != null ? (rhbTypePlanning(j.vacation!['type'])?.court ?? '${j.vacation!['type']}') : (j.conge != null ? 'C' : '—'),
                                  key: Key('pli:jour:${j.date}'),
                                  ton: j.vacation != null ? rhbTon(rhbTypePlanningTon(j.vacation!['type'])) : (j.conge != null ? TonSigh.succes : TonSigh.neutre))),
                      ]),
              ),
          ]),
      ],
    );
  }

  void _historique(BuildContext ctx, List<Map<String, Object?>> h, bool montants) {
    afficherModale<void>(ctx,
        titre: 'Historique du régime de ${widget.agent['nomComplet']}',
        sousTitre: 'Chaque version est datée et ne se réécrit pas.',
        taille: TailleModale.lg,
        corps: MiniTableauSigh(vide: 'Aucune version.', colonnes: [
          ColonneMini('Version', (x) => '${x['version']}', droite: true),
          ColonneMini('Date d’effet', (x) => dateFR(DateTime.parse('${x['dateEffet']}'))),
          ColonneMini('Mode', (x) => libellesModesRegimeRh[x['mode']] ?? '${x['mode']}'),
          ColonneMini('Contenu', (x) {
            if (x['mode'] == modeRetourRh) return 'Retour au régime de la catégorie';
            final ch = (x['champs'] as Map).cast<String, Object?>();
            final av = [for (final a in (x['aValider'] as List? ?? const [])) '$a'];
            return [
              if (x['baseRemplacement'] != null) 'Régime adopté : ${x['baseRemplacement']}',
              for (final k in champsRegimeIndividuelRh)
                if (ch.containsKey(k))
                  '${libellesChampsRegimeRh[k]} : ${k == 'honoraire' && !montants ? honoraireReserve : (ch[k] is List ? (ch[k] as List).join(', ') : ch[k])}${av.contains(k) ? ' (à valider)' : ''}',
            ].join(' ; ');
          }),
          ColonneMini('Motif', (x) => '${x['motif'] == null || x['motif'] == '' ? '—' : x['motif']}'),
          ColonneMini('Document', (x) => '${x['sourceDocument'] ?? 'Aucun'}'),
          ColonneMini('Posée par', (x) => '${x['creePar'] ?? '—'}'),
        ], lignes: h),
        pied: (fermer) => [BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);
  }
}

/// La SAISIE d'une version du régime individuel d'un agent : dérogation champ par champ, remplacement, ou retour à la catégorie. La version est écrite par le domaine
/// (`PlanningRhPoste.poserRegime`), refusée EN LE NOMMANT ; les valeurs posées sans document d'origine sont marquées « à valider ».
void ouvrirSaisieRegime(BuildContext ctx, ContexteEcran c, PlanningRhPoste p, Fiche agent, String mode) {
  final options = [for (final c in champsRegimeIndividuelRh) OptionChamp(c, libellesChampsRegimeRh[c]!)];
  final champs = <ChampDef>[
    const ChampDef(nom: 'dateEffet', libelle: 'Date d’effet', type: TypeChamp.date, requis: true),
    if (mode == modeRemplacementRh) ...[
      ChampDef(nom: 'baseRemplacement', libelle: 'Régime adopté', type: TypeChamp.select, options: [
        const OptionChamp('', 'Aucun : composer le régime champ par champ'),
        for (final l in libellesRegimesRh(c.magasin.collection('regimesTravail').actives)) OptionChamp(l),
      ]),
      const ChampDef(nom: 'libelle', libelle: 'Nom du régime individuel', indicatif: 'Ex. : Horaire de jour adapté'),
    ],
    if (mode != modeRetourRh) ...[
      ChampDef.section(mode == modeRemplacementRh
          ? 'Champs du régime (complètent ou corrigent le régime adopté ; rien n’est hérité de la catégorie)'
          : 'Champs dérogés (laisser vide pour suivre la catégorie)'),
      ChampDef(nom: 'vacations', libelle: 'Vacations', type: TypeChamp.multiselect, col: ColChamp.plein, options: [
        for (final t in rhbTypesPlanning)
          if (t.duree > 0) OptionChamp(t.id, '${t.label} (${t.debut} → ${t.fin})')
      ]),
      const ChampDef(nom: 'repos', libelle: 'Repos', type: TypeChamp.select, options: [
        OptionChamp('', 'Suit la catégorie'),
        OptionChamp('repos24', 'Repos 24h'),
        OptionChamp('repos48', 'Repos 48h'),
        OptionChamp('aucun', 'Aucun repos codifié'),
      ]),
      const ChampDef(nom: 'cycle', libelle: 'Cycle (jours)', type: TypeChamp.nombre),
      const ChampDef(nom: 'heureDebut', libelle: 'Heure de début', indicatif: '08:00', col: ColChamp.tiers),
      const ChampDef(nom: 'heureFin', libelle: 'Heure de fin', indicatif: '18:00', col: ColChamp.tiers),
      const ChampDef(nom: 'dureeHeures', libelle: 'Durée (heures)', type: TypeChamp.nombre, col: ColChamp.tiers),
      ChampDef(nom: 'jours', libelle: 'Jours travaillés', type: TypeChamp.multiselect, col: ColChamp.plein, options: [for (final j in joursSemaineRh) OptionChamp(j.id, j.libelle)]),
      const ChampDef(nom: 'honoraire', libelle: 'Honoraire (FCFA)', type: TypeChamp.nombre, aide: 'Seulement si le régime porte un honoraire propre'),
      const ChampDef(nom: 'honorairePeriodicite', libelle: 'Périodicité de l’honoraire', type: TypeChamp.select, options: [
        OptionChamp('', 'Suit la catégorie'),
        OptionChamp('mensuelle', 'Mensuelle'),
        OptionChamp('occurrence', 'Par occurrence'),
      ]),
      const ChampDef.section('Origine des valeurs'),
      const ChampDef(
          nom: 'sourceDocument',
          libelle: 'Document d’origine',
          col: ColChamp.plein,
          indicatif: 'Avenant, note de service, certificat…',
          aide: 'Sans document, toutes les valeurs posées sont marquées « à valider » (valeurs d’attente).'),
      ChampDef(
          nom: 'aValider',
          libelle: 'Valeurs encore d’attente (avec un document)',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          options: options,
          aide: 'Les valeurs que le document ne fixe pas : elles restent marquées « à valider ».'),
    ],
    const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, lignes: 2, requis: true, col: ColChamp.plein),
  ];
  final ctl = ControleurFormulaire(champs, {
    'dateEffet': iso(c.aujourdhui),
    if (mode != modeRetourRh) ...{'vacations': <String>[], 'jours': <String>[], 'aValider': <String>[], 'repos': '', 'honorairePeriodicite': ''},
    if (mode == modeRemplacementRh) 'baseRemplacement': '',
  });
  final titre = libellesModesRegimeRh[mode]!;
  afficherModale<void>(ctx,
      titre: titre,
      sousTitre: '${agent['nomComplet']} — une version datée : elle ne se réécrit pas.',
      taille: TailleModale.lg,
      corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        NoteSigh(switch (mode) {
          modeRemplacementRh =>
            'Le régime de la catégorie est REMPLACÉ entièrement : par le régime adopté, s’il est choisi, complété des champs ci-dessous. La date d’effet est aujourd’hui ou à venir : les vacations passées gardent leur régime.',
          modeRetourRh => 'L’agent revient au régime de sa catégorie à la date d’effet. Les versions antérieures restent à l’historique.',
          _ => 'Seuls les champs renseignés dérogent à la catégorie. La date d’effet est aujourd’hui ou à venir : les vacations passées gardent leur régime.',
        }),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Enregistrer la version',
                icone: LucideIcons.save,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) return;
                  final doc = '${v['sourceDocument'] ?? ''}'.trim();
                  final r = p.poserRegime(
                    employeId: agent['id'],
                    dateEffet: v['dateEffet'] as String?,
                    mode: mode,
                    motif: v['motif'] as String?,
                    baseRemplacement: v['baseRemplacement'] as String?,
                    sourceDocument: doc,
                    aValider: doc.isEmpty ? null : [for (final x in (v['aValider'] as List? ?? const [])) '$x'],
                    champs: {
                      for (final k in [...champsRegimeIndividuelRh, 'libelle'])
                        if (v.containsKey(k)) k: v[k],
                    },
                  );
                  if (r['ok'] != true) {
                    rhbToastRefus(ctx, r);
                    return;
                  }
                  fermer();
                  final av = (r['aValider'] as List? ?? const []).length;
                  ToastsSigh.afficher(ctx, mode == modeRetourRh ? 'Retour au régime de la catégorie enregistré.' : 'Régime individuel enregistré.',
                      type: TypeToast.succes,
                      detail: 'Version ${r['version']} à compter du ${dateFR(DateTime.parse('${v['dateEffet']}'))}${av > 0 ? ' — $av valeur(s) à valider' : ''}');
                }),
          ]);
}
