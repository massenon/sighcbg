import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m14/crud_m14.dart';
import 'cpc_commun.dart';

/// `m12-aib` — « Acompte sur impôt (AIB) » : le BARÈME de l'acompte sur impôt assis sur les bénéfices que la clinique retient à la source.
///
/// Le barème est une DONNÉE versionnée par DATE D'EFFET (collection `baremeAIB`, une fiche par version) : une version ARRÊTÉE ne se réécrit jamais, une
/// correction AJOUTE une version à une date d'effet postérieure, et le taux d'une date passée reste celui qui était en vigueur ce jour-là (comme la
/// grille des primes). Une version s'archive avec son motif, elle ne se supprime pas (RG-14). Le moteur (`cpd_bareme_aib.dart` du domaine) rend le taux
/// en vigueur à une date.
///
/// L'écran dit CE QUI EST ARRÊTÉ ET CE QUI NE L'EST PAS : le taux de 5 % est arrêté (généralisé à compter du 07/09/2026, décision de Baguidi) ; les
/// taux de 1 % et de 3 % figurent au barème mais NE SONT PAS ARRÊTÉS, marqués à valider, et ne s'appliquent à rien tant que la Direction ne les arrête pas.
///
/// Hors périmètre de cet écran : la retenue sur les factures fournisseurs et les écritures qu'elle engendre (voir le « reste » du chantier).
class EcranAib extends StatelessWidget with EcranMaquette {
  const EcranAib({super.key});

  @override
  String get titre => 'Acompte sur impôt (AIB)';

  @override
  String get description => 'Barème de l’AIB retenu à la source, versionné par date d’effet : ce qui est arrêté, ce qui ne l’est pas.';

  @override
  String get regle =>
      'L’AIB est un acompte prélevé à la source : ce que la clinique RETIENT est une dette envers l’État (compte $cpdCompteAibRetenu), reversée le 10 du mois suivant ; ce qu’elle SUBIT sur ses propres factures est une créance (compte $cpdCompteAibSubi), imputée sur l’impôt sur les bénéfices (compte $cpdCompteAibImputation). Seule une version ARRÊTÉE par la Direction s’applique ; une version arrêtée ne se réécrit pas : une correction ajoute une version à une date d’effet postérieure.';

  static const sourceBareme =
      'Décision de la Direction de Baguidi : taux de 5 % généralisé à compter du 07/09/2026. Les taux de 1 % et de 3 % figurent aux pièces de la clinique d’origine, sans champ d’application arrêté.';

  static String _pct(Object? t) {
    final x = t is num ? t : num.tryParse('$t'.replaceAll(',', '.'));
    if (x == null) return '—';
    return x == x.roundToDouble() ? '${x.toInt()} %' : '${'$x'.replaceAll('.', ',')} %';
  }

  static String _d(Object? v) => dateDe(v);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('baremeAIB');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final actives = col.actives;
        final arretees = actives.where(cpdEstArretee).toList();
        final nonArretees = actives.where((f) => !cpdEstArretee(f)).toList();
        final jour = c.aujourdhui;
        final enVigueur = cpdBaremeEnVigueur(actives, jour);
        final appliques = [for (final b in enVigueur) if (b.reponse.taux != null) _pct(b.reponse.taux)];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Ce qui est arrêté, ce qui ne l'est pas : dit en toutes lettres, avec le taux, la date d'effet et le décideur.
          NoteSigh(
              arretees.isEmpty
                  ? 'Aucun taux n’est arrêté : l’AIB ne s’applique à rien tant que la Direction n’a pas arrêté une version du barème.'
                  : 'ARRÊTÉ : ${[for (final f in arretees) '${_pct(f['taux'])} (${f['categorie']}, depuis le ${_d(f['dateEffet'])}, arrêté par ${f['decideurArret']} le ${_d(f['dateArret'])})'].join(' ; ')}.',
              ton: arretees.isEmpty ? TonSigh.attention : TonSigh.succes,
              icone: arretees.isEmpty ? LucideIcons.triangleAlert : LucideIcons.circleCheck),
          if (nonArretees.isNotEmpty) ...[
            const SizedBox(height: 8),
            NoteSigh(
                'NON ARRÊTÉ, À VALIDER : ${[for (final f in nonArretees) '${_pct(f['taux'])} (${f['categorie']})'].join(' ; ')}. Ces taux figurent au barème mais ne s’appliquent à aucune retenue tant que la Direction ne les a pas arrêtés (date et décideur de l’arrêt à saisir).',
                ton: TonSigh.attention,
                icone: LucideIcons.triangleAlert),
          ],
          const SizedBox(height: 16),
          CrudM14(
            collection: col,
            entite: 'taux d’AIB',
            entiteP: 'taux d’AIB (versions)',
            prefixeId: 'BAIB',
            triInitial: 'code',
            taillePage: 15,
            provenance: sourceBareme,
            valeursCreation: const {
              'statutArret': cpdStatutNonArrete,
              'compteRetenu': cpdCompteAibRetenu,
              'compteSubi': cpdCompteAibSubi,
              'compteImputation': cpdCompteAibImputation,
            },
            kpis: (rows) => [
              KpiSigh(libelle: 'Versions arrêtées', valeur: nombre(rows.where(cpdEstArretee).length), icone: LucideIcons.gavel, ton: TonSigh.succes, indice: 'décidées par la Direction'),
              KpiSigh(
                  libelle: 'Non arrêtées (à valider)',
                  valeur: nombre(rows.where((f) => !cpdEstArretee(f)).length),
                  icone: LucideIcons.triangleAlert,
                  ton: rows.any((f) => !cpdEstArretee(f)) ? TonSigh.attention : TonSigh.neutre,
                  indice: 'ne s’appliquent à rien'),
              KpiSigh(libelle: 'Catégories du barème', valeur: nombre(cpdCodesAib(rows).length), icone: LucideIcons.layers, ton: TonSigh.info),
              KpiSigh(
                  libelle: 'Taux appliqué aujourd’hui',
                  valeur: appliques.isEmpty ? 'Aucun' : appliques.join(' · '),
                  icone: LucideIcons.percent,
                  ton: appliques.isEmpty ? TonSigh.attention : TonSigh.navy,
                  indice: 'au ${dateFR(jour)}'),
            ],
            colonnes: [
              ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (f) => '${f['code']}', rendu: (_, f) => monoTexte(f['code'])),
              const ColonneTableau(cle: 'categorie', libelle: 'Catégorie'),
              ColonneTableau(
                  cle: 'taux',
                  libelle: 'Taux',
                  droite: true,
                  valeur: (f) => f['taux'],
                  texte: (f) => _pct(f['taux']),
                  rendu: (_, f) => Text(_pct(f['taux']), style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
              ColonneTableau(
                  cle: 'dateEffet',
                  libelle: 'Date d’effet',
                  sansCoupure: true,
                  valeur: (f) => f['dateEffet'] ?? '',
                  texte: (f) => f['dateEffet'] == null || '${f['dateEffet']}'.isEmpty ? 'à fixer à l’arrêt' : _d(f['dateEffet'])),
              ColonneTableau(
                  cle: 'statutArret',
                  libelle: 'Statut',
                  texte: (f) => cpdEstArretee(f) ? 'Arrêté' : 'Non arrêté (à valider)',
                  rendu: (_, f) => cpdEstArretee(f)
                      ? const BadgeSigh('Arrêté', ton: TonSigh.succes, icone: LucideIcons.gavel)
                      : const BadgeSigh('Non arrêté, à valider', ton: TonSigh.attention, icone: LucideIcons.triangleAlert)),
              ColonneTableau(
                  cle: 'arret',
                  libelle: 'Arrêt',
                  texte: (f) => cpdEstArretee(f) ? '${f['decideurArret'] ?? ''} ${_d(f['dateArret'])}' : '—'),
            ],
            filtres: [
              FiltreTableau(
                  nom: 'statutArret',
                  libelle: 'Statut',
                  options: [for (final s in cpdStatutsAib) OptionChamp(s.$1, s.$2)],
                  correspond: (l, v) => (cpdEstArretee(l) ? cpdStatutArrete : cpdStatutNonArrete) == v),
            ],
            ongletsApres: (ctx) => [
              OngletDef(id: 'adate', libelle: 'Taux à une date', construire: (_) => _TauxALaDate(c: c, col: col)),
            ],
            champs: (ctx, record) => [
              const ChampDef(nom: 'code', libelle: 'Code de la catégorie', requis: true, aide: 'Les versions successives d’une même catégorie portent le même code.'),
              const ChampDef(nom: 'categorie', libelle: 'Libellé de la catégorie', requis: true),
              ChampDef(
                  nom: 'taux',
                  libelle: 'Taux (%)',
                  type: TypeChamp.nombre,
                  requis: true,
                  valider: (v, _) {
                    final t = num.tryParse('$v'.replaceAll(',', '.'));
                    return t == null || t < 0 || t > 100 ? 'Le taux doit être compris entre 0 et 100 %.' : null;
                  }),
              const ChampDef(
                  nom: 'dateEffet',
                  libelle: 'Date d’effet',
                  type: TypeChamp.date,
                  aide: 'Obligatoire pour une version arrêtée. Une correction prend une date d’effet postérieure : le passé ne se réécrit pas.'),
              ChampDef(
                  nom: 'statutArret',
                  libelle: 'Statut',
                  type: TypeChamp.select,
                  requis: true,
                  options: [for (final s in cpdStatutsAib) OptionChamp(s.$1, s.$2)]),
              const ChampDef(
                  nom: 'dateArret',
                  libelle: 'Date de l’arrêt',
                  type: TypeChamp.date,
                  condition: (controle: 'statutArret', quand: [cpdStatutArrete])),
              const ChampDef(
                  nom: 'decideurArret',
                  libelle: 'Décideur de l’arrêt',
                  aide: 'La personne ou l’instance qui a arrêté ce taux (la Direction).',
                  condition: (controle: 'statutArret', quand: [cpdStatutArrete])),
              const ChampDef(nom: 'compteRetenu', libelle: 'Compte de l’AIB retenu', requis: true, aide: 'Dette envers l’État (4478).'),
              const ChampDef(nom: 'compteSubi', libelle: 'Compte de l’AIB subi', requis: true, aide: 'Créance sur l’État (4492).'),
              const ChampDef(nom: 'compteImputation', libelle: 'Compte d’imputation', requis: true, aide: 'Impôt sur les bénéfices (891).'),
              const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein, aide: 'Pourquoi cette version : décision, correction, précision.'),
            ],
            // Le contrôle du domaine REFUSE en nommant : version arrêtée non corrigeable sur place, date d'effet en double, arrêt incomplet.
            avant: (ctx, saisie, record) => cpdControlerVersionAib(saisie, record, col.actives, c.aujourdhui),
            transformer: (ctx, s, record) {
              final arrete = '${s['statutArret']}' == cpdStatutArrete;
              final effet = '${s['dateEffet'] ?? ''}';
              return {
                'code': '${s['code']}'.trim(),
                'categorie': '${s['categorie']}'.trim(),
                'taux': num.parse('${s['taux']}'.replaceAll(',', '.')),
                'dateEffet': effet.isEmpty ? null : effet,
                'statutArret': '${s['statutArret']}',
                'arrete': arrete,
                'aValider': !arrete,
                'dateArret': arrete ? '${s['dateArret']}' : null,
                'decideurArret': arrete ? '${s['decideurArret']}'.trim() : null,
                'compteRetenu': '${s['compteRetenu']}'.trim(),
                'compteSubi': '${s['compteSubi']}'.trim(),
                'compteImputation': '${s['compteImputation']}'.trim(),
                'motif': '${s['motif'] ?? ''}'.trim().isEmpty ? null : '${s['motif']}'.trim(),
              };
            },
            titreDetail: (f) => '${f['code']} — ${_pct(f['taux'])}',
            sousTitreDetail: (f) => '${f['categorie']}',
            detail: (ctx, f) => _detail(c, f, actives),
            etat: (ctx, f) => _imprimer(ctx, c, f),
          ),
        ]);
      },
    );
  }

  Widget _detail(ContexteEcran c, Fiche f, List<Fiche> actives) {
    final arretee = cpdEstArretee(f);
    final jour = c.aujourdhui;
    final v = cpdTauxAibALaDate(actives, '${f['code']}', jour);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NoteSigh(
          arretee
              ? 'Version ARRÊTÉE par ${f['decideurArret']} le ${_d(f['dateArret'])}. Elle ne se corrige pas sur place : une correction ajoute une version à une date d’effet postérieure.'
              : 'Version NON ARRÊTÉE, à valider par la Direction : elle ne s’applique à aucune retenue.',
          ton: arretee ? TonSigh.succes : TonSigh.attention,
          icone: arretee ? LucideIcons.gavel : LucideIcons.triangleAlert),
      const SizedBox(height: 12),
      DescListeSigh([
        ('Code', '${f['code']}'),
        ('Catégorie', '${f['categorie']}'),
        ('Taux', _pct(f['taux'])),
        ('Date d’effet', f['dateEffet'] == null || '${f['dateEffet']}'.isEmpty ? 'à fixer à l’arrêt' : _d(f['dateEffet'])),
        ('Statut', arretee ? 'Arrêté' : 'Non arrêté (à valider)'),
        ('Date de l’arrêt', arretee ? _d(f['dateArret']) : null),
        ('Décideur de l’arrêt', arretee ? '${f['decideurArret']}' : null),
        ('Compte de l’AIB retenu (dette)', '${f['compteRetenu'] ?? cpdCompteAibRetenu}'),
        ('Compte de l’AIB subi (créance)', '${f['compteSubi'] ?? cpdCompteAibSubi}'),
        ('Compte d’imputation', '${f['compteImputation'] ?? cpdCompteAibImputation}'),
        ('Motif', f['motif'] == null ? null : '${f['motif']}'),
        ('Taux de la catégorie au ${dateFR(jour)}', v.taux == null ? 'Aucun — ${v.motif}' : '${_pct(v.taux)} — ${v.motif}'),
      ]),
    ]);
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, Fiche f) {
    final arretee = cpdEstArretee(f);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Barème de l’AIB — version ${f['code']}',
            sousTitre: '${f['categorie']}',
            cartouche: [
              ('Code', '${f['code']}'),
              ('Catégorie', '${f['categorie']}'),
              ('Taux', _pct(f['taux'])),
              ('Date d’effet', f['dateEffet'] == null || '${f['dateEffet']}'.isEmpty ? 'à fixer à l’arrêt' : _d(f['dateEffet'])),
              ('Statut', arretee ? 'ARRÊTÉ' : 'NON ARRÊTÉ — à valider'),
              if (arretee) ('Arrêté le', _d(f['dateArret'])),
              if (arretee) ('Décideur', '${f['decideurArret']}'),
            ],
            blocs: [
              BlocTableau(TableauEtat(colonnes: [
                ColonneEtat(libelle: 'Rubrique', valeur: (l) => l['k']),
                ColonneEtat(libelle: 'Information', valeur: (l) => l['v']),
              ], lignes: [
                {'k': 'AIB retenu (dette envers l’État)', 'v': 'Compte ${f['compteRetenu'] ?? cpdCompteAibRetenu}'},
                {'k': 'AIB subi (créance sur l’État)', 'v': 'Compte ${f['compteSubi'] ?? cpdCompteAibSubi}'},
                {'k': 'Imputation sur l’impôt sur les bénéfices', 'v': 'Compte ${f['compteImputation'] ?? cpdCompteAibImputation}'},
                {'k': 'Motif', 'v': '${f['motif'] ?? '—'}'},
                {'k': 'Application', 'v': arretee ? 'S’applique à compter de la date d’effet.' : 'Ne s’applique à aucune retenue tant que la Direction ne l’a pas arrêté.'},
              ])),
            ],
            signatures: const [Signature('Le Comptable', qualite: PaiQualite.comptable), Signature('La Direction', qualite: PaiQualite.direction)]));
  }
}

/// L'onglet « Taux à une date » : le moteur du domaine rend, pour chaque catégorie, le taux EN VIGUEUR à la date choisie — avec son motif quand rien ne
/// s'applique (avant la première version arrêtée, ou version non arrêtée).
class _TauxALaDate extends StatefulWidget {
  const _TauxALaDate({required this.c, required this.col});
  final ContexteEcran c;
  final CollectionMagasin col;

  @override
  State<_TauxALaDate> createState() => _EtatTauxALaDate();
}

class _EtatTauxALaDate extends State<_TauxALaDate> {
  // La date se choisit au champ date du kit (le sélecteur natif n'est jamais ouvert hors du kit).
  late final ControleurFormulaire _ctl = ControleurFormulaire(
      [const ChampDef(nom: 'date', libelle: 'Date de lecture du barème', type: TypeChamp.date)], {'date': isoJour(widget.c.aujourdhui)});

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_maj);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _maj() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse('${_ctl['date']}') ?? widget.c.aujourdhui;
    final lignes = [
      for (final b in cpdBaremeEnVigueur(widget.col.actives, date))
        {'code': b.code, 'categorie': b.libelle, 'taux': b.reponse.taux, 'motif': b.reponse.motif, 'arrete': b.reponse.taux != null}
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
          titre: 'Taux en vigueur au ${dateFR(date)}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormulaireSigh(controleur: _ctl),
            const SizedBox(height: 8),
            const Text('Le taux d’une date passée est celui de la version qui était en vigueur ce jour-là : une correction ultérieure ne le change pas.',
                style: TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
          ])),
      const SizedBox(height: 12),
      TableauSigh(
        titre: 'Barème à cette date',
        lignes: lignes,
        taillePage: 20,
        messageVide: 'Aucune catégorie au barème.',
        colonnes: [
          ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (f) => '${f['code']}', rendu: (_, f) => monoTexte(f['code'])),
          const ColonneTableau(cle: 'categorie', libelle: 'Catégorie'),
          ColonneTableau(
              cle: 'taux',
              libelle: 'Taux en vigueur',
              droite: true,
              texte: (f) => EcranAib._pct(f['taux']),
              rendu: (_, f) => f['taux'] == null
                  ? const BadgeSigh('Aucun taux', ton: TonSigh.attention, icone: LucideIcons.triangleAlert)
                  : BadgeSigh(EcranAib._pct(f['taux']), ton: TonSigh.succes, icone: LucideIcons.gavel)),
          const ColonneTableau(cle: 'motif', libelle: 'Motif'),
        ],
      ),
    ]);
  }
}
