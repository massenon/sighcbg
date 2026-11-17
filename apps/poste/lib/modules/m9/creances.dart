import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/service_parametres.dart' show bornesBalanceAgeeAssureur;
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'commun.dart';

/// `m9-creances` — « Créances assureurs » : la balance âgée, en lecture seule. Les créances sont le reliquat des factures prises en charge ;
/// elles évoluent avec les règlements des compagnies, jamais par saisie directe.
///
/// Les bornes portent sur la DATE DE LA FACTURE, l'ancienneté se compte TOUJOURS par rapport à aujourd'hui (les confondre ferait vieillir une
/// créance parce qu'on a rétréci la fenêtre). Les filtres en force sont portés sur l'état imprimé.
class EcranCreances extends StatefulWidget with EcranMaquette {
  const EcranCreances({super.key});

  @override
  String get titre => 'Créances assureurs';

  @override
  String get description =>
      'Suivi des montants dus par les compagnies, par ancienneté et par compagnie.';

  @override
  String get regle =>
      'Écran en lecture seule. Les créances sont le reliquat des factures prises en charge : elles évoluent avec les règlements des compagnies, jamais par saisie directe.';

  @override
  State<EcranCreances> createState() => _EtatCreances();
}

class _EtatCreances extends State<EcranCreances> {
  ControleurFormulaire? _du, _au, _compagnie, _anciennete, _seuil;

  List<ControleurFormulaire> get _tous =>
      [_du!, _au!, _compagnie!, _anciennete!, _seuil!];

  static const _seuils = [
    ('', 'Tout montant'),
    ('50000', 'Au moins 50 000 F'),
    ('200000', 'Au moins 200 000 F'),
    ('500000', 'Au moins 500 000 F'),
    ('1000000', 'Au moins 1 000 000 F'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_du != null) return;
    final c = ContexteEcran.of(context);
    ChampDef def(String nom, String libelle, TypeChamp type,
            {List<OptionChamp> options = const []}) =>
        ChampDef(
            nom: nom,
            libelle: libelle,
            type: type,
            options: options,
            col: ColChamp.plein);
    _du = champUnique(def('du', 'Factures émises du', TypeChamp.date), '');
    _au = champUnique(def('au', 'au', TypeChamp.date), '');
    _compagnie = champUnique(
        def('compagnie', 'Compagnie', TypeChamp.select, options: [
          const OptionChamp('', 'Toutes les compagnies'),
          for (final a in actives(c, 'assureurs'))
            OptionChamp('${a['code']}', '${a['code']} — ${a['nom']}')
        ]),
        '');
    _anciennete = champUnique(
        def('anciennete', 'Ancienneté retenue', TypeChamp.select, options: [
          const OptionChamp('', 'Toutes anciennetés'),
          // Les libellés se calculent des bornes RÉGLÉES (assurances.balanceAgeeAssureurBorne1Jours et 2) : plus de « 30 » ni de « 90 » écrits ici.
          for (final t in assTranchesDef(bornesBalanceAgeeAssureur(c.magasin, c.aujourdhui))) OptionChamp(t.id, t.libelle),
        ]),
        '');
    _seuil = champUnique(
        def('seuil', 'Créance minimale', TypeChamp.select,
            options: [for (final s in _seuils) OptionChamp(s.$1, s.$2)]),
        '');
    for (final k in _tous) {
      k.addListener(_surChangement);
    }
  }

  void _surChangement() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_du != null) {
      for (final k in _tous) {
        k.removeListener(_surChangement);
        k.dispose();
      }
    }
    super.dispose();
  }

  String _txt(ControleurFormulaire k, String nom) => '${k[nom] ?? ''}';

  List<AssLigneCreance> _lignes(ContexteEcran c) => assBalanceAgee(
      assureurs: actives(c, 'assureurs'),
      facturesAssurance: assFacturesAssurance(actives(c, 'factures')),
      auj: c.aujourdhui,
      du: _txt(_du!, 'du'),
      au: _txt(_au!, 'au'),
      compagnie: _txt(_compagnie!, 'compagnie'),
      anciennete: _txt(_anciennete!, 'anciennete'),
      bornes: bornesBalanceAgeeAssureur(c.magasin, c.aujourdhui),
      seuil: num.tryParse(_txt(_seuil!, 'seuil')) ?? 0);

  /// Les filtres EN FORCE, relevés comme `P.etat` les relève sur la page.
  List<(String, String)> _filtresEnForce(ContexteEcran c) {
    String libelle(ControleurFormulaire k, String nom) => k.champs.first.options
        .firstWhere((o) => o.valeur == _txt(k, nom))
        .libelle;
    return [
      if (_txt(_du!, 'du').isNotEmpty)
        ('Factures émises du', dateFR(assDate(_txt(_du!, 'du')))),
      if (_txt(_au!, 'au').isNotEmpty) ('au', dateFR(assDate(_txt(_au!, 'au')))),
      if (_txt(_compagnie!, 'compagnie').isNotEmpty)
        ('Compagnie', libelle(_compagnie!, 'compagnie')),
      if (_txt(_anciennete!, 'anciennete').isNotEmpty)
        ('Ancienneté retenue', libelle(_anciennete!, 'anciennete')),
      if (_txt(_seuil!, 'seuil').isNotEmpty)
        ('Créance minimale', libelle(_seuil!, 'seuil')),
    ];
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, List<AssLigneCreance> rows) {
    final tri = trierPar<AssLigneCreance>(rows, (r) => r.total, descendant: true);
    final tr = assTranchesDef(bornesBalanceAgeeAssureur(c.magasin, c.aujourdhui));
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'État des créances — tiers payeurs',
            sousTitre: 'Balance âgée au ${dateFR(c.aujourdhui)}',
            cartouche: [
              (
                'Créances totales',
                money(rows.fold<num>(0, (a, r) => a + r.total))
              ),
              ('Compagnies concernées', nombre(rows.length)),
              (
                'Dont ${tr[2].libelleKpi.toLowerCase()}',
                money(rows.fold<num>(0, (a, r) => a + r.tranche3))
              ),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            filtres: _filtresEnForce(c),
            tableaux: [
              TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Code', valeur: (r) => r['code']),
                ColonneEtat(libelle: 'Compagnie', valeur: (r) => r['nom']),
                ColonneEtat(
                    libelle: 'Factures', droite: true, valeur: (r) => r['nb']),
                ColonneEtat(
                    libelle: tr[0].libelleCourt,
                    droite: true,
                    valeur: (r) => m(r['tranche1']),
                    somme: (r) => n(r['tranche1'])),
                ColonneEtat(
                    libelle: tr[1].libelleCourt,
                    droite: true,
                    valeur: (r) => m(r['tranche2']),
                    somme: (r) => n(r['tranche2'])),
                ColonneEtat(
                    libelle: tr[2].libelleCourt,
                    droite: true,
                    valeur: (r) => m(r['tranche3']),
                    somme: (r) => n(r['tranche3'])),
                ColonneEtat(
                    libelle: 'Total',
                    droite: true,
                    valeur: (r) => m(r['total']),
                    somme: (r) => n(r['total'])),
              ], lignes: [
                for (final r in tri)
                  {
                    'code': r.code,
                    'nom': r.nom,
                    'nb': r.nbFactures,
                    'tranche1': r.tranche1,
                    'tranche2': r.tranche2,
                    'tranche3': r.tranche3,
                    'total': r.total,
                  }
              ])
            ],
            signatures: const [
              Signature('Le Comptable', qualite: PaiQualite.comptable),
              signDaf
            ]));
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoute(c, ['assureurs', 'factures', 'parametres']),
      builder: (context, _) {
        final rows = _lignes(c);
        final tr = assTranchesDef(bornesBalanceAgeeAssureur(c.magasin, c.aujourdhui));
        double som(double Function(AssLigneCreance) f) =>
            rows.fold(0.0, (a, r) => a + f(r));
        final tri = trierPar<AssLigneCreance>(rows, (r) => r.total, descendant: true);
        void reinitialiser() {
          for (final k in _tous) {
            k.poser(k.champs.first.nom, '');
          }
        }

        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CarteSigh(
                  child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                    commande(_du!, largeur: 170),
                    commande(_au!, largeur: 170),
                    commande(_compagnie!, largeur: 260),
                    commande(_anciennete!, largeur: 200),
                    commande(_seuil!, largeur: 200),
                    BoutonSigh(
                        libelle: 'Réinitialiser',
                        icone: LucideIcons.rotateCcw,
                        variante: VarianteBouton.secondaire,
                        onPressed: reinitialiser),
                  ])),
              const SizedBox(height: 16),
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Créances totales',
                    valeur: money(som((r) => r.total)),
                    icone: LucideIcons.handCoins,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: tr[0].libelleKpi,
                    valeur: money(som((r) => r.tranche1)),
                    icone: LucideIcons.clock,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: tr[1].libelleKpi,
                    valeur: money(som((r) => r.tranche2)),
                    icone: LucideIcons.clockAlert,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: tr[2].libelleKpi,
                    valeur: money(som((r) => r.tranche3)),
                    indice: 'Relance impérative',
                    icone: LucideIcons.octagonAlert,
                    ton: TonSigh.danger),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Balance âgée des créances par compagnie',
                lignes: [
                  for (final r in rows)
                    {
                      'id': r.code,
                      'code': r.code,
                      'nom': r.nom,
                      'nbFactures': r.nbFactures,
                      'tranche1': r.tranche1,
                      'tranche2': r.tranche2,
                      'tranche3': r.tranche3,
                      'total': r.total,
                    }
                ],
                taillePage: 15,
                nomExport: 'creances-assureurs',
                triInitial: 'total',
                sensInitial: 'desc',
                actions: [
                  BoutonSigh(
                      libelle: 'Éditer l’état des créances',
                      icone: LucideIcons.printer,
                      taille: TailleBouton.sm,
                      onPressed: () => _imprimer(context, c, rows)),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'code',
                      libelle: 'Code',
                      sansCoupure: true,
                      texte: (r) => '${r['code']}',
                      rendu: (_, r) => monoTexte(r['code'],
                          poids: FontWeight.w600)),
                  const ColonneTableau(cle: 'nom', libelle: 'Compagnie'),
                  const ColonneTableau(
                      cle: 'nbFactures', libelle: 'Factures', droite: true),
                  ColonneTableau(
                      cle: 'tranche1',
                      libelle: tr[0].libelleColonne,
                      droite: true,
                      texte: (r) => m(r['tranche1'])),
                  ColonneTableau(
                      cle: 'tranche2',
                      libelle: tr[1].libelleColonne,
                      droite: true,
                      texte: (r) => m(r['tranche2']),
                      rendu: (_, r) => Text(m(r['tranche2']),
                          style: TextStyle(
                              color: n(r['tranche2']) > 0
                                  ? JetonsShell.warning700
                                  : JetonsShell.slate700,
                              fontSize: 14,
                              height: 20 / 14))),
                  ColonneTableau(
                      cle: 'tranche3',
                      libelle: tr[2].libelleColonne,
                      droite: true,
                      texte: (r) => m(r['tranche3']),
                      rendu: (_, r) => Text(m(r['tranche3']),
                          style: TextStyle(
                              color: n(r['tranche3']) > 0
                                  ? JetonsShell.danger600
                                  : JetonsShell.slate700,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: n(r['tranche3']) > 0
                                  ? FontWeight.w600
                                  : FontWeight.w400))),
                  ColonneTableau(
                      cle: 'total',
                      libelle: 'Total dû',
                      droite: true,
                      texte: (r) => m(r['total']),
                      rendu: (_, r) => Text(m(r['total']),
                          style: const TextStyle(
                              color: JetonsShell.navy900,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w700))),
                ],
              ),
              const SizedBox(height: 16),
              deuxCartes(
                CarteSigh(
                    titre: 'Créances par compagnie',
                    child: ClassementSigh([
                      for (final r in tri) (libelle: r.nom, valeur: r.total)
                    ], ton: JetonsShell.warning500)),
                CarteSigh(
                    titre: 'Répartition par ancienneté',
                    child: GraphiqueAnneau(
                        etiquettes: [for (final t in tr) t.libelleKpi],
                        valeurs: [
                          som((r) => r.tranche1),
                          som((r) => r.tranche2),
                          som((r) => r.tranche3)
                        ],
                        couleurs: const [
                          JetonsShell.success500,
                          JetonsShell.warning500,
                          JetonsShell.danger600
                        ])),
              ),
              if (rows.isEmpty) ...[
                const SizedBox(height: 16),
                const NoteSigh(
                    'Aucune créance ne répond à cette sélection. Les filtres portent sur la date des factures ; l’ancienneté, elle, se compte toujours par rapport à aujourd’hui.',
                    icone: LucideIcons.filter),
              ],
            ]);
      },
    );
  }
}
