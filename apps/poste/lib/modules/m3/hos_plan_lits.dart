import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/tarifs_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'hos_commun.dart';

/// `m3-plan-lits` — « Plan des lits » : l'occupation par aile, chambre et lit (nomenclature A1 LIT1, chambres VIP et VVIP), tirée des admissions en
/// cours. Un lit se lit d'un coup d'œil : libre (vert), occupé (rouge), sortie à prévoir au-delà de cinq jours (orange). Le clic ouvre la fiche du lit
/// (tiroir) ; l'occupation par type de chambre et la durée moyenne de séjour sur douze mois complètent la page.
///
/// VUE RESTREINTE (décision de la Direction du 16/11/2026, plan des lits ouvert en lecture à des profils qui n'ouvrent pas les admissions) : un profil qui
/// voit l'écran sans lire la catégorie « Hospitalisation et surveillance » — refus PAR DÉFAUT, la catégorie suivant `m3-admissions` — lit le PLAN : qui
/// occupe quel lit (identification minimale : nom, code), depuis quand. Le séjour (diagnostic d'entrée, prise en charge, infirmier référent, solde) et les
/// gestes (admettre, préparer la sortie, feuille de température) ne s'affichent pas ; le tiroir le DIT. Une catégorie refusée par DÉCISION de la clinique
/// ferme l'écran entier, comme avant.
class EcranPlanLits extends StatelessWidget with EcranMaquette {
  const EcranPlanLits({super.key});

  @override
  String get titre => 'Plan des lits';

  @override
  String get description =>
      'Visualisation graphique de l’occupation par aile, chambre et lit — nomenclature A1 LIT1, chambres VIP et VVIP.';

  /// Au-delà de ce nombre de jours, un lit occupé est signalé « sortie prévue ».
  static const joursSortiePrevue = 5;

  /// Le texte que la maquette lit sur un lit : libellé, occupant (ou « Disponible »), durée — collés (`innerText` d'un bouton).
  static String texteLit(String lit, Fiche? adm, DateTime auj) =>
      '$lit${adm != null ? adm['patient'] : 'Disponible'}${adm != null ? '${hosDureeSejour(adm, auj)} j' : ''}';

  /// Durée moyenne de séjour par mois (admissions TERMINÉES, rattachées au mois d'entrée), 12 mois, un chiffre après la virgule ; 0 sans séjour.
  static List<num> dureesMoyennes(Iterable<Fiche> admissions, DateTime auj) {
    final termines = [
      for (final a in admissions)
        if (a['dateSortie'] != null && a['dateSortie'] != '') a
    ];
    return [
      for (var i = 0; i < 12; i++)
        () {
          final mois = termines.where((a) {
            final d = hosVersDate(a['dateEntree']);
            if (d == null) return false;
            final diff = (auj.year - d.year) * 12 + (auj.month - d.month);
            return 11 - diff == i;
          }).toList();
          if (mois.isEmpty) return 0;
          final somme = mois.fold<int>(0, (n, a) => n + hosDureeSejour(a, auj));
          return arrondiJs(somme / mois.length * 10) / 10;
        }()
    ];
  }

  Widget _legende(Color c, String texte) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(texte, style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate600)),
      ]);

  void _ouvrirLit(BuildContext context, HosChambre ch, String lit, Fiche? adm, {bool restreint = false}) {
    final c = ContexteEcran.of(context);
    if (adm == null) {
      final tarif = TarifsPoste.tarifsJournee(c.magasin, aujourdhui: c.aujourdhui)[ch.type];
      afficherTiroir<void>(context,
          titre: 'Lit $lit',
          sousTitre: '${ch.aile} — ${hosLibelleTypeChambre(ch.type)}',
          corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DescListeSigh([
              ('Chambre', ch.code),
              ('Lit', lit),
              ('Type', hosLibelleTypeChambre(ch.type)),
              ('Tarif journalier', tarif == null ? 'à valider' : money(tarif)),
              ('État', statutBadge('libre')),
            ]),
            const SizedBox(height: 16),
            const VideSigh('Ce lit est disponible pour une nouvelle admission.', icone: LucideIcons.bed),
          ]),
          pied: restreint
              ? null
              : (fermer) => [
                BoutonSigh(
                    libelle: 'Créer une admission',
                    icone: LucideIcons.userPlus,
                    onPressed: () {
                      fermer();
                      c.aller('m3-admissions');
                    }),
              ]);
      return;
    }
    if (restreint) {
      // Le PLAN, pas le séjour : qui, où, depuis quand. Ni diagnostic, ni prise en charge, ni soins, ni solde, ni geste.
      afficherTiroir<void>(context,
          titre: '${adm['patient']}',
          sousTitre: '${adm['patientCode']} — Lit ${adm['lit']}',
          corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DescListeSigh([
              ('Dossier', texteMono('${adm['patientCode']}', couleur: JetonsShell.slate800)),
              ('Lit', adm['lit']),
              ('Chambre', hosLibelleTypeChambre(adm['typeChambre'])),
              ('Date d’entrée', jourFR(adm['dateEntree'])),
              ('Durée de séjour', '${hosDureeSejour(adm, c.aujourdhui)} jour(s)'),
            ]),
            const SizedBox(height: 16),
            const MentionReservee('hospitalisation_soins'),
          ]));
      return;
    }
    final solde = soldePatient(c.magasin, adm['patientId']);
    afficherTiroir<void>(context,
        titre: '${adm['patient']}',
        sousTitre: '${adm['patientCode']} — Lit ${adm['lit']}',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DescListeSigh([
            ('Dossier', texteMono('${adm['patientCode']}', couleur: JetonsShell.slate800)),
            ('Lit', adm['lit']),
            ('Chambre', hosLibelleTypeChambre(adm['typeChambre'])),
            ('Date d’entrée', jourFR(adm['dateEntree'])),
            ('Durée de séjour', '${hosDureeSejour(adm, c.aujourdhui)} jour(s)'),
            ('Diagnostic d’entrée', AccesSensible.de(c).masquerSi('diagnostic_pathologie', adm['diagnosticEntree'])),
            ('Prise en charge', statutBadge(adm['priseEnCharge'])),
            ('Infirmier référent', adm['infirmier']),
          ]),
          const SizedBox(height: 16),
          solde > 0
              ? NoteSigh(
                  'RG-06 — Solde restant dû de ${money(solde)}. La sortie ne pourra être finalisée qu’après apurement, sauf dérogation motivée de la Direction.',
                  ton: TonSigh.attention,
                  icone: LucideIcons.wallet)
              : const NoteSigh('RG-06 — Solde apuré : la sortie peut être finalisée.',
                  ton: TonSigh.succes, icone: LucideIcons.circleCheck),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Feuille de température',
                  icone: LucideIcons.thermometer,
                  variante: VarianteBouton.secondaire,
                  onPressed: () {
                    fermer();
                    c.aller('m3-feuille-temperature');
                  }),
              BoutonSigh(
                  libelle: 'Préparer la sortie',
                  icone: LucideIcons.doorOpen,
                  onPressed: () {
                    fermer();
                    c.aller('m3-sorties');
                  }),
            ]);
  }

  Widget _chambre(BuildContext context, HosChambre ch, Iterable<Fiche> actives, DateTime auj, {bool restreint = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: decorationCarte(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Chambre ${ch.code}',
                  style: const TextStyle(
                      fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: JetonsShell.slate800)),
              BadgeSigh(hosLibelleTypeChambre(ch.type),
                  ton: ch.type == 'vvip' ? TonSigh.navy : (ch.type == 'vip' ? TonSigh.info : TonSigh.neutre)),
            ])),
        for (final lit in ch.lits)
          () {
            final adm = hosLitOccupePar(lit, actives);
            final sortiePrevue = adm != null && hosDureeSejour(adm, auj) > joursSortiePrevue;
            final couleur = adm == null
                ? JetonsShell.success500
                : (sortiePrevue ? JetonsShell.warning500 : JetonsShell.danger500);
            return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Tooltip(
                  message: texteLit(lit, adm, auj),
                  waitDuration: const Duration(milliseconds: 600),
                  child: Material(
                    color: Colors.white,
                    child: InkWell(
                      key: Key('plan:lit:$lit'),
                      borderRadius: BorderRadius.circular(8),
                      hoverColor: JetonsShell.navy50,
                      onTap: () => _ouvrirLit(context, ch, lit, adm, restreint: restreint),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: JetonsShell.slate200)),
                        child: Row(children: [
                          Container(
                              key: Key('plan:point:$lit'),
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(color: couleur, shape: BoxShape.circle)),
                          Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(lit,
                                style: const TextStyle(
                                    fontFamily: 'LiberationMono',
                                    fontSize: 12,
                                    height: 16 / 12,
                                    fontWeight: FontWeight.w600,
                                    color: JetonsShell.slate700)),
                            Text(adm != null ? '${adm['patient']}' : 'Disponible',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: JetonsShell.slate500)),
                          ])),
                          if (adm != null)
                            Text('${hosDureeSejour(adm, auj)} j',
                                style: const TextStyle(fontSize: 10, color: JetonsShell.slate400)),
                        ]),
                      ),
                    ),
                  ),
                ));
          }(),
      ]),
    );
  }

  // Lue la catégorie « Hospitalisation et surveillance » : l'écran entier. Refusée PAR DÉFAUT (profil qui voit le plan sans ouvrir les admissions) : la
  // vue restreinte du plan. Refusée par DÉCISION de la clinique : l'écran le dit au lieu de s'ouvrir (point unique `GardeSensible`).
  @override
  Widget build(BuildContext context) => EcouteDroitsSensibles(builder: (ctx, a) {
        if (a.peut('hospitalisation_soins')) return _corps(ctx);
        if (a.refuseeParDecision('hospitalisation_soins')) return const GardeSensible(categorie: 'hospitalisation_soins', enfant: SizedBox.shrink());
        return _corps(ctx, restreint: true);
      });

  Widget _corps(BuildContext context, {bool restreint = false}) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('admissions');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final auj = c.aujourdhui;
        final lits = hosTousLits();
        final actives = col.actives;
        final occupes = hosEnCours(actives);
        final ailes = <String, List<HosChambre>>{};
        for (final ch in hosChambres) {
          ailes.putIfAbsent(ch.aile, () => []).add(ch);
        }
        final types = [
          for (final t in hosTypesChambre)
            () {
              final l = lits.where((s) => s.chambre.type == t.id);
              final o = l.where((s) => hosLitOccupePar(s.label, actives) != null);
              return (t.label, l.length, o.length);
            }()
        ];
        final mensuel = parMois(
            [
              for (final a in actives)
                if (a['dateSortie'] != null && a['dateSortie'] != '') a
            ],
            'dateEntree',
            ref: auj);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (restreint) ...[
            NoteSigh(
                key: const Key('plan:vue-restreinte'),
                'Lecture du plan seulement : qui occupe quel lit, depuis quand. Le séjour — diagnostic, prise en charge, soins, solde — relève de la catégorie « ${categorieSensible('hospitalisation_soins')?.libelle} », que ce profil ne lit pas (RG-13).',
                icone: LucideIcons.lock),
            const SizedBox(height: 16),
          ],
          KpiGrilleSigh(kpis: [
            KpiSigh(
                libelle: 'Lits installés',
                valeur: nombre(lits.length),
                icone: LucideIcons.bed,
                ton: TonSigh.neutre),
            KpiSigh(
                libelle: 'Lits occupés',
                valeur: nombre(occupes.length),
                icone: LucideIcons.bedDouble,
                ton: TonSigh.danger),
            KpiSigh(
                libelle: 'Lits libres',
                valeur: nombre(lits.length - occupes.length),
                icone: LucideIcons.bedSingle,
                ton: TonSigh.succes),
            KpiSigh(
                libelle: 'Taux d’occupation',
                valeur: pourcent(occupes.length / lits.length * 100, 1),
                icone: LucideIcons.gauge,
                ton: TonSigh.navy),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: JetonsShell.slate200)),
            child: Wrap(spacing: 16, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Légende :',
                  style: TextStyle(
                      fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, color: JetonsShell.slate500)),
              _legende(JetonsShell.success500, 'Libre'),
              _legende(JetonsShell.danger500, 'Occupé'),
              _legende(JetonsShell.warning500, 'Sortie prévue (séjour > $joursSortiePrevue jours)'),
            ]),
          ),
          for (final e in ailes.entries) ...[
            const SizedBox(height: 16),
            CarteSigh(
                titre: e.key,
                child: LayoutBuilder(builder: (_, k) {
                  final n = k.maxWidth >= 1024 ? 4 : (k.maxWidth >= 640 ? 2 : 1);
                  final l = (k.maxWidth - 12 * (n - 1)) / n;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final ch in e.value) SizedBox(width: l, child: _chambre(context, ch, actives, auj, restreint: restreint))
                  ]);
                })),
          ],
          const SizedBox(height: 16),
          deuxColonnes(
            CarteSigh(
                titre: 'Occupation par type de chambre',
                child: GraphiqueBarres(empile: true, etiquettes: [
                  for (final t in types) t.$1
                ], series: [
                  SerieGraphique('Occupés', [for (final t in types) t.$3], couleur: JetonsShell.danger500),
                  SerieGraphique('Libres', [for (final t in types) t.$2 - t.$3], couleur: JetonsShell.success500),
                ])),
            CarteSigh(
                titre: 'Durée moyenne de séjour (12 mois)',
                child: GraphiqueLigne(etiquettes: mensuel.etiquettes, series: [
                  SerieGraphique('Jours', dureesMoyennes(actives, auj), couleur: JetonsShell.navy900),
                ])),
          ),
        ]);
      },
    );
  }
}
