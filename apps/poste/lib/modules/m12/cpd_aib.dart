import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/parametres_aib.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m14/crud_m14.dart';
import '../cfg/cfg_validations_aib.dart' show ongletValidationsAibDemande;
import 'cpc_commun.dart';

/// `m12-aib` — « Acompte sur impôt (AIB) » : le BARÈME de l'acompte sur impôt assis sur les bénéfices que la clinique retient à la source, PAR SITUATION de
/// l'acheteur (modèle de la maquette de la Direction, lot A1).
///
/// Le barème est une DONNÉE versionnée par DATE D'EFFET : deux collections, `situationsAib` (le code, le libellé et le déclencheur d'une situation :
/// IFU saisi, IFU absent, choix à la main) et `baremeAib` (une fiche par version ET par situation). Une version ARRÊTÉE ne se réécrit jamais, une
/// correction AJOUTE une version à une date d'effet postérieure, et le taux d'une date passée reste celui qui était en vigueur ce jour-là (comme la
/// grille des primes). Une version s'archive avec son motif, elle ne se supprime pas (RG-14). Le moteur (`cpd_bareme_aib.dart` du domaine) rend le taux
/// en vigueur à une date ; la retenue sur facture fournisseur le lit, la catégorie de la retenue étant une situation.
///
/// L'écran dit CE QUI EST ARRÊTÉ ET CE QUI NE L'EST PAS : le taux de 5 % (acheteur sans IFU actif) est arrêté (généralisé à compter du 07/09/2026,
/// décision de Baguidi) ; les taux de 1 % et de 3 % figurent au barème mais NE SONT PAS ARRÊTÉS, marqués à valider, et ne s'appliquent à rien tant que la
/// Direction ne les arrête pas.
///
/// La retenue sur les factures fournisseurs, comme l'AIB SUBI que le fournisseur a facturé, se constatent à l'écran « Factures fournisseurs » (M7) ; les registres
/// ci-dessous les relisent, chacun avec son total, et l'imputation sur l'impôt sur les bénéfices (total subi + retenu de l'exercice) y est INDIQUÉE en lecture.
class EcranAib extends StatelessWidget with EcranMaquette {
  const EcranAib({super.key});

  @override
  String get titre => 'Acompte sur impôt (AIB)';

  @override
  String get description => 'Barème de l’AIB retenu à la source, versionné par date d’effet : ce qui est arrêté, ce qui ne l’est pas.';

  @override
  String get regle =>
      'L’AIB est un acompte prélevé à la source : ce que la clinique RETIENT est une dette envers l’État (compte d’AIB retenu), reversée le 10 du mois suivant ; ce qu’elle SUBIT sur ses propres factures est une créance (compte d’AIB subi), imputée sur l’impôt sur les bénéfices (compte d’imputation). Les comptes se lisent aux Paramètres (« Validations de l’AIB », onglet « Comptes de l’AIB »). Seule une version ARRÊTÉE par la Direction s’applique ; une version arrêtée ne se réécrit pas : une correction ajoute une version à une date d’effet postérieure.';

  static const sourceBareme =
      'Décision de la Direction de Baguidi : taux de 5 % généralisé à compter du 07/09/2026. Les taux de 1 % et de 3 % figurent aux pièces de la clinique d’origine, sans champ d’application arrêté.';

  /// Le libellé d'une situation (son code à défaut).
  static String _libelleSituation(Iterable<Fiche> situations, Object? code) {
    for (final s in situations) {
      if ('${s['code']}' == '$code') return '${s['libelle'] ?? code}';
    }
    return '$code';
  }

  static String _pct(Object? t) {
    final x = t is num ? t : num.tryParse('$t'.replaceAll(',', '.'));
    if (x == null) return '—';
    return x == x.roundToDouble() ? '${x.toInt()} %' : '${'$x'.replaceAll('.', ',')} %';
  }

  static String _d(Object? v) => dateDe(v);

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('baremeAib');
    final colSit = c.magasin.collection('situationsAib');
    return ListenableBuilder(
      listenable: Listenable.merge([col, colSit]),
      builder: (context, _) {
        final actives = col.actives;
        final situations = colSit.actives;
        final arretees = actives.where(cpdEstArretee).toList();
        final nonArretees = actives.where((f) => !cpdEstArretee(f)).toList();
        final jour = c.aujourdhui;
        final enVigueur = cpdBaremeEnVigueur(situations, actives, jour);
        final appliques = [for (final b in enVigueur) if (b.reponse.taux != null) _pct(b.reponse.taux)];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Ce qui est arrêté, ce qui ne l'est pas : dit en toutes lettres, avec le taux, la date d'effet et le décideur.
          NoteSigh(
              arretees.isEmpty
                  ? 'Aucun taux n’est arrêté : l’AIB ne s’applique à rien tant que la Direction n’a pas arrêté une version du barème.'
                  : 'ARRÊTÉ : ${[for (final f in arretees) '${_pct(f['taux'])} (${_libelleSituation(situations, f['situation'])}, depuis le ${_d(f['dateEffet'])}, arrêté par ${f['decideurArret']} le ${_d(f['dateArret'])})'].join(' ; ')}.',
              ton: arretees.isEmpty ? TonSigh.attention : TonSigh.succes,
              icone: arretees.isEmpty ? LucideIcons.triangleAlert : LucideIcons.circleCheck),
          if (nonArretees.isNotEmpty) ...[
            const SizedBox(height: 8),
            NoteSigh(
                'NON ARRÊTÉ, À VALIDER : ${[for (final f in nonArretees) '${_pct(f['taux'])} (${_libelleSituation(situations, f['situation'])})'].join(' ; ')}. Ces taux figurent au barème mais ne s’appliquent à aucune retenue tant que la Direction ne les a pas arrêtés (date et décideur de l’arrêt à saisir).',
                ton: TonSigh.attention,
                icone: LucideIcons.triangleAlert),
          ],
          const SizedBox(height: 16),
          _RegistresAib(c),
          const SizedBox(height: 16),
          CrudM14(
            collection: col,
            entite: 'taux d’AIB',
            entiteP: 'taux d’AIB (versions)',
            prefixeId: 'BAI',
            triInitial: 'situation',
            taillePage: 15,
            provenance: sourceBareme,
            valeursCreation: const {
              'statutArret': cpdStatutNonArrete,
            },
            kpis: (rows) => [
              KpiSigh(libelle: 'Versions arrêtées', valeur: nombre(rows.where(cpdEstArretee).length), icone: LucideIcons.gavel, ton: TonSigh.succes, indice: 'décidées par la Direction'),
              KpiSigh(
                  libelle: 'Non arrêtées (à valider)',
                  valeur: nombre(rows.where((f) => !cpdEstArretee(f)).length),
                  icone: LucideIcons.triangleAlert,
                  ton: rows.any((f) => !cpdEstArretee(f)) ? TonSigh.attention : TonSigh.neutre,
                  indice: 'ne s’appliquent à rien'),
              KpiSigh(libelle: 'Situations de l’acheteur', valeur: nombre(situations.length), icone: LucideIcons.layers, ton: TonSigh.info),
              KpiSigh(
                  libelle: 'Taux appliqué aujourd’hui',
                  valeur: appliques.isEmpty ? 'Aucun' : appliques.join(' · '),
                  icone: LucideIcons.percent,
                  ton: appliques.isEmpty ? TonSigh.attention : TonSigh.navy,
                  indice: 'au ${dateFR(jour)}'),
            ],
            colonnes: [
              ColonneTableau(
                  cle: 'situation',
                  libelle: 'Situation de l’acheteur',
                  texte: (f) => _libelleSituation(situations, f['situation']),
                  rendu: (_, f) => Text(_libelleSituation(situations, f['situation']), style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14))),
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
                  cle: 'fin',
                  libelle: 'Jusqu’au',
                  sansCoupure: true,
                  texte: (f) => !cpdEstArretee(f) ? '—' : (cpdFinDeVersion(actives, f) == null ? 'en cours' : _d(cpdFinDeVersion(actives, f)))),
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
              OngletDef(id: 'adate', libelle: 'Taux à une date', construire: (_) => _TauxALaDate(c: c, col: col, colSit: colSit)),
              OngletDef(id: 'situations', libelle: 'Situations de l’acheteur', construire: (_) => _Situations(c: c, col: colSit)),
            ],
            champs: (ctx, record) => [
              ChampDef(
                  nom: 'situation',
                  libelle: 'Situation de l’acheteur',
                  type: TypeChamp.select,
                  requis: true,
                  options: [for (final x in cpdSituationsActives(situations)) OptionChamp('${x['code']}', '${x['libelle'] ?? x['code']}')],
                  aide: 'Les versions successives d’une même situation se suivent par date d’effet.'),
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
              const ChampDef(
                  nom: 'source',
                  libelle: 'Source du taux',
                  type: TypeChamp.textarea,
                  lignes: 2,
                  col: ColChamp.plein,
                  requis: true,
                  aide: 'Le texte, la décision ou la déclaration d’où vient le taux : on ne retient pas un taux dont on ne cite pas le texte.'),
              const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein, requis: true, aide: 'Pourquoi cette version : décision, correction, précision.'),
            ],
            // Le contrôle du domaine REFUSE en nommant : version arrêtée non corrigeable sur place, date d'effet en double, arrêt incomplet.
            avant: (ctx, saisie, record) => cpdControlerVersionAib(saisie, record, col.actives, c.aujourdhui, situations: colSit.actives),
            transformer: (ctx, s, record) {
              final arrete = '${s['statutArret']}' == cpdStatutArrete;
              final effet = '${s['dateEffet'] ?? ''}';
              return {
                'situation': '${s['situation']}'.trim(),
                'taux': num.parse('${s['taux']}'.replaceAll(',', '.')),
                'dateEffet': effet.isEmpty ? null : effet,
                'statutArret': '${s['statutArret']}',
                'arrete': arrete,
                'aValider': !arrete,
                'dateArret': arrete ? '${s['dateArret']}' : null,
                'decideurArret': arrete ? '${s['decideurArret']}'.trim() : null,
                'source': '${s['source']}'.trim(),
                'motif': '${s['motif']}'.trim(),
              };
            },
            titreDetail: (f) => '${_libelleSituation(situations, f['situation'])} — ${_pct(f['taux'])}',
            sousTitreDetail: (f) => 'Version du barème de l’AIB',
            detail: (ctx, f) => _detail(c, f, actives, situations),
            etat: (ctx, f) => _imprimer(ctx, c, f, situations),
          ),
        ]);
      },
    );
  }

  Widget _detail(ContexteEcran c, Fiche f, List<Fiche> actives, List<Fiche> situations) {
    final arretee = cpdEstArretee(f);
    final jour = c.aujourdhui;
    final v = cpdTauxAibALaDate(actives, '${f['situation']}', jour, situations: situations);
    final comptes = cpaComptesALaDate(c.magasin.collection(cpaCollection).actives, jour);
    final fin = arretee ? cpdFinDeVersion(actives, f) : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      NoteSigh(
          arretee
              ? 'Version ARRÊTÉE par ${f['decideurArret']} le ${_d(f['dateArret'])}. Elle ne se corrige pas sur place : une correction ajoute une version à une date d’effet postérieure.'
              : 'Version NON ARRÊTÉE, à valider par la Direction : elle ne s’applique à aucune retenue.',
          ton: arretee ? TonSigh.succes : TonSigh.attention,
          icone: arretee ? LucideIcons.gavel : LucideIcons.triangleAlert),
      const SizedBox(height: 12),
      if (comptes.aConfirmer) ...[
        NoteSigh('Comptes de l’AIB À CONFIRMER PAR L’EXPERT-COMPTABLE : ${comptes.marquage}. Ils se corrigent aux Paramètres, jamais sur la fiche du barème.',
            ton: TonSigh.attention, icone: LucideIcons.triangleAlert),
        const SizedBox(height: 12),
      ],
      DescListeSigh([
        ('Situation de l’acheteur', _libelleSituation(situations, f['situation'])),
        ('Taux', _pct(f['taux'])),
        ('Date d’effet', f['dateEffet'] == null || '${f['dateEffet']}'.isEmpty ? 'à fixer à l’arrêt' : _d(f['dateEffet'])),
        ('Jusqu’au', !arretee ? null : (fin == null ? 'en cours' : _d(fin))),
        ('Statut', arretee ? 'Arrêté' : 'Non arrêté (à valider)'),
        ('Date de l’arrêt', arretee ? _d(f['dateArret']) : null),
        ('Décideur de l’arrêt', arretee ? '${f['decideurArret']}' : null),
        ('Compte de l’AIB retenu (dette), en vigueur', comptes.retenu),
        ('Compte de l’AIB subi (créance), en vigueur', comptes.subi),
        ('Compte d’imputation, en vigueur', comptes.imputation),
        ('Provenance des comptes', comptes.provenance),
        ('Source du taux', f['source'] == null ? null : '${f['source']}'),
        ('Motif', f['motif'] == null ? null : '${f['motif']}'),
        ('Taux de la situation au ${dateFR(jour)}', v.taux == null ? 'Aucun — ${v.motif}' : '${_pct(v.taux)} — ${v.motif}'),
      ]),
      const SizedBox(height: 12),
      Text(
          'Les comptes ne sont plus portés par les fiches du barème : ils se lisent à UNE seule source, la rubrique « comptes » des Paramètres, à la date de la pièce. Une pièce déjà passée garde les comptes de son époque.',
          style: const TextStyle(fontSize: 12, height: 16 / 12, color: JetonsShell.slate500)),
      if (c.ouvre?.call('cfg-validations-aib') ?? false) ...[
        const SizedBox(height: 8),
        Wrap(children: [
          Builder(
              builder: (ctx) => BoutonSigh(
                  key: const Key('aib:vers-comptes'),
                  libelle: 'Corriger les comptes aux Paramètres',
                  icone: LucideIcons.settings,
                  variante: VarianteBouton.secondaire,
                  onPressed: () {
                    ongletValidationsAibDemande = 'comptes';
                    if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                    c.aller('cfg-validations-aib');
                  })),
        ]),
      ],
    ]);
  }

  void _imprimer(BuildContext ctx, ContexteEcran c, Fiche f, List<Fiche> situations) {
    final arretee = cpdEstArretee(f);
    final libelle = _libelleSituation(situations, f['situation']);
    final comptes = cpaComptesALaDate(c.magasin.collection(cpaCollection).actives, c.aujourdhui);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Barème de l’AIB — $libelle',
            sousTitre: 'Version du barème, par situation de l’acheteur',
            cartouche: [
              ('Situation', libelle),
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
                {'k': 'AIB retenu (dette envers l’État), compte en vigueur', 'v': 'Compte ${comptes.retenu}'},
                {'k': 'AIB subi (créance sur l’État), compte en vigueur', 'v': 'Compte ${comptes.subi}'},
                {'k': 'Imputation sur l’impôt sur les bénéfices, compte en vigueur', 'v': 'Compte ${comptes.imputation}'},
                {'k': 'Provenance des comptes (Paramètres)', 'v': comptes.provenance},
                {'k': 'Source du taux', 'v': '${f['source'] ?? '—'}'},
                {'k': 'Motif', 'v': '${f['motif'] ?? '—'}'},
                {'k': 'Application', 'v': arretee ? 'S’applique à compter de la date d’effet.' : 'Ne s’applique à aucune retenue tant que la Direction ne l’a pas arrêté.'},
              ])),
            ],
            signatures: const [Signature('Le Comptable', qualite: PaiQualite.comptable), Signature('La Direction', qualite: PaiQualite.direction)]));
  }
}

/// L'onglet « Taux à une date » : le moteur du domaine rend, pour chaque situation, le taux EN VIGUEUR à la date choisie — avec son motif quand rien ne
/// s'applique (avant la première version arrêtée, ou version non arrêtée).
class _TauxALaDate extends StatefulWidget {
  const _TauxALaDate({required this.c, required this.col, required this.colSit});
  final ContexteEcran c;
  final CollectionMagasin col;
  final CollectionMagasin colSit;

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
      for (final b in cpdBaremeEnVigueur(widget.colSit.actives, widget.col.actives, date))
        {'code': b.code, 'categorie': b.libelle, 'taux': b.reponse.taux, 'motif': b.reponse.motif, 'arrete': b.reponse.taux != null, 'rang': b.reponse.rang}
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
        messageVide: 'Aucune situation au barème.',
        colonnes: [
          ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (f) => '${f['code']}', rendu: (_, f) => monoTexte(f['code'])),
          const ColonneTableau(cle: 'categorie', libelle: 'Situation de l’acheteur'),
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


/// L'onglet « Situations de l'acheteur » : la liste des situations que le barème distingue. Le code d'une situation ne change pas (des versions du barème
/// le citent) : créer une nouvelle situation et archiver l'ancienne. Le déclencheur dit comment la situation est choisie d'office d'après l'IFU.
class _Situations extends StatelessWidget {
  const _Situations({required this.c, required this.col});
  final ContexteEcran c;
  final CollectionMagasin col;

  @override
  Widget build(BuildContext context) {
    return CrudM14(
      collection: col,
      entite: 'situation de l’acheteur',
      entiteP: 'situations de l’acheteur',
      prefixeId: 'SAI',
      triInitial: 'ordre',
      taillePage: 10,
      provenance: 'Modèle de la maquette de la Direction (lot A1) : une situation, un déclencheur, des versions du barème datées.',
      valeursCreation: const {'declencheur': cpdDeclencheurChoix},
      colonnes: [
        ColonneTableau(cle: 'ordre', libelle: 'Ordre', droite: true, valeur: (f) => f['ordre'] ?? 99, texte: (f) => '${f['ordre'] ?? '—'}'),
        ColonneTableau(cle: 'code', libelle: 'Code', sansCoupure: true, texte: (f) => '${f['code']}', rendu: (_, f) => monoTexte(f['code'])),
        const ColonneTableau(cle: 'libelle', libelle: 'Libellé'),
        ColonneTableau(
            cle: 'declencheur',
            libelle: 'Choisie d’office quand',
            texte: (f) => [for (final d in cpdDeclencheursAib) if (d.$1 == '${f['declencheur']}') d.$2].firstOrNull ?? '${f['declencheur'] ?? '—'}'),
      ],
      champs: (ctx, record) => [
        ChampDef(
            nom: 'code',
            libelle: 'Code de la situation',
            requis: true,
            aide: 'Ne change plus une fois créé : des versions du barème le citent.'),
        const ChampDef(nom: 'libelle', libelle: 'Libellé', requis: true),
        ChampDef(
            nom: 'declencheur',
            libelle: 'Choisie d’office quand',
            type: TypeChamp.select,
            requis: true,
            options: [for (final d in cpdDeclencheursAib) OptionChamp(d.$1, d.$2)]),
        const ChampDef(nom: 'ordre', libelle: 'Ordre d’affichage', type: TypeChamp.nombre),
        const ChampDef(nom: 'description', libelle: 'Description', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
      ],
      avant: (ctx, saisie, record) {
        final code = '${saisie['code'] ?? ''}'.trim();
        if (record != null && '${record['code']}' != code) {
          return 'AIB_CODE_FIGE : le code d’une situation ne change pas, des versions du barème le citent — créer une nouvelle situation et archiver celle-ci.';
        }
        if (record == null && col.actives.any((f) => '${f['code']}' == code)) return 'La situation « $code » existe déjà.';
        return null;
      },
      transformer: (ctx, s, record) => {
        'code': '${s['code']}'.trim(),
        'libelle': '${s['libelle']}'.trim(),
        'declencheur': '${s['declencheur']}',
        'ordre': num.tryParse('${s['ordre'] ?? ''}'.trim())?.toInt(),
        'description': '${s['description'] ?? ''}'.trim().isEmpty ? null : '${s['description']}'.trim(),
      },
    );
  }
}

/// Les registres de l'AIB : « Retenues » (dette envers l'État, à reverser) et « AIB subi » (créance sur l'État, facturée par les fournisseurs), un onglet chacun
/// avec son total, puis l'IMPUTATION sur l'impôt sur les bénéfices INDIQUÉE en lecture (jamais écrite).
class _RegistresAib extends StatelessWidget {
  const _RegistresAib(this.c);
  final ContexteEcran c;

  @override
  Widget build(BuildContext context) {
    final factures = c.magasin.collection('facturesFournisseurs');
    return ListenableBuilder(
      listenable: Listenable.merge([factures, c.magasin.collection(cpaCollection)]),
      builder: (context, _) {
        final comptes = comptesAib(c.magasin, c.aujourdhui);
        final imputation = cpdImputationAibExercice(factures.actives, c.aujourdhui.year, comptes);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OngletsSigh(onglets: [
            OngletDef(id: 'retenues', libelle: 'Retenues (dette)', construire: (_) => _RegistreRetenues(factures, comptes)),
            OngletDef(id: 'subi', libelle: 'AIB subi (créance)', construire: (_) => _RegistreSubi(factures, comptes)),
          ]),
          const SizedBox(height: 12),
          KeyedSubtree(
              key: const Key('aib:imputation'),
              child: NoteSigh(
                  'Imputation sur l’impôt sur les bénéfices de ${imputation.annee} (indicative, aucune écriture d’imputation n’est passée) : AIB subi ${money(imputation.subi)} + AIB retenu ${money(imputation.retenu)} = ${money(imputation.total)}, compte d’imputation ${comptes.imputation}.${comptes.aConfirmer ? ' Comptes à confirmer par l’expert-comptable.' : ''}',
                  ton: TonSigh.info,
                  icone: LucideIcons.landmark)),
        ]);
      },
    );
  }
}

/// Le registre des retenues d'AIB : une ligne par facture fournisseur retenue, le total, et la date de reversement à l'État.
class _RegistreRetenues extends StatelessWidget {
  const _RegistreRetenues(this.factures, this.comptes);
  final CollectionMagasin factures;
  final CpdComptesAib comptes;

  @override
  Widget build(BuildContext context) {
    final reg = cpdRegistreRetenuesAib(factures.actives);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'AIB retenu à reverser', valeur: money(reg.total), icone: LucideIcons.landmark, ton: reg.total > 0 ? TonSigh.attention : TonSigh.neutre, indice: 'compte ${comptes.retenu}'),
        KpiSigh(libelle: 'Factures retenues', valeur: nombre(reg.lignes.length), icone: LucideIcons.fileText),
      ]),
      const SizedBox(height: 16),
      if (reg.lignes.isEmpty)
        const NoteSigh('Aucune retenue constatée. Une retenue se constate depuis « Factures fournisseurs » (M7), au taux arrêté du barème à la date de la facture.',
            ton: TonSigh.info, icone: LucideIcons.info)
      else
        TableauSigh(
          titre: 'Registre des retenues d’AIB',
          taillePage: 8,
          nomExport: 'registre-retenues-aib',
          lignes: reg.lignes,
          colonnes: [
            const ColonneTableau(cle: 'reference', libelle: 'Facture', sansCoupure: true),
            const ColonneTableau(cle: 'fournisseur', libelle: 'Fournisseur'),
            ColonneTableau(cle: 'date', libelle: 'Retenue le', sansCoupure: true, texte: (r) => dateDe(r['date'])),
            const ColonneTableau(cle: 'situation', libelle: 'Situation', sansCoupure: true),
            ColonneTableau(cle: 'base', libelle: 'Base', droite: true, texte: (r) => money(r['base'], avecDevise: false)),
            ColonneTableau(cle: 'taux', libelle: 'Taux', droite: true, texte: (r) => '${r['taux']} %'),
            ColonneTableau(cle: 'montant', libelle: 'Retenue', droite: true, texte: (r) => money(r['montant'], avecDevise: false)),
            ColonneTableau(cle: 'reversement', libelle: 'À reverser le', sansCoupure: true, texte: (r) => dateDe(r['reversement'])),
          ],
        ),
    ]);
  }
}

/// Le registre de l'AIB SUBI : une ligne par facture fournisseur qui porte son AIB subi, le total, et le signal « taux non arrêté au barème » le cas échéant.
class _RegistreSubi extends StatelessWidget {
  const _RegistreSubi(this.factures, this.comptes);
  final CollectionMagasin factures;
  final CpdComptesAib comptes;

  @override
  Widget build(BuildContext context) {
    final reg = cpdRegistreAibSubi(factures.actives);
    final signales = reg.lignes.where((l) => l['signalTaux'] != null).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrilleSigh(kpis: [
        KpiSigh(libelle: 'AIB subi (créance sur l’État)', valeur: money(reg.total), icone: LucideIcons.landmark, ton: reg.total > 0 ? TonSigh.info : TonSigh.neutre, indice: 'compte ${comptes.subi}'),
        KpiSigh(libelle: 'Factures concernées', valeur: nombre(reg.lignes.length), icone: LucideIcons.fileText),
        KpiSigh(
            libelle: 'Taux non arrêté au barème',
            valeur: nombre(signales),
            icone: LucideIcons.triangleAlert,
            ton: signales > 0 ? TonSigh.attention : TonSigh.neutre,
            indice: 'signalé, jamais refusé'),
      ]),
      const SizedBox(height: 16),
      if (reg.lignes.isEmpty)
        const NoteSigh(
            'Aucun AIB subi constaté. Quand un fournisseur facture un AIB, il se renseigne en modifiant la facture (« Factures fournisseurs », M7), puis « Constater l’AIB subi » pose la créance sur l’État en brouillon.',
            ton: TonSigh.info,
            icone: LucideIcons.info)
      else
        TableauSigh(
          titre: 'Registre de l’AIB subi',
          taillePage: 8,
          nomExport: 'registre-aib-subi',
          lignes: reg.lignes,
          colonnes: [
            const ColonneTableau(cle: 'reference', libelle: 'Facture', sansCoupure: true),
            const ColonneTableau(cle: 'fournisseur', libelle: 'Fournisseur'),
            ColonneTableau(cle: 'date', libelle: 'Constaté le', sansCoupure: true, texte: (r) => dateDe(r['date'])),
            ColonneTableau(cle: 'base', libelle: 'Base', droite: true, texte: (r) => money(r['base'], avecDevise: false)),
            ColonneTableau(cle: 'taux', libelle: 'Taux', droite: true, texte: (r) => '${r['taux']} %'),
            ColonneTableau(cle: 'montant', libelle: 'AIB subi', droite: true, texte: (r) => money(r['montant'], avecDevise: false)),
            ColonneTableau(cle: 'compte', libelle: 'Compte', sansCoupure: true, texte: (r) => '${r['compte'] ?? comptes.subi}'),
            ColonneTableau(
                cle: 'signalTaux',
                libelle: 'Barème',
                texte: (r) => r['signalTaux'] == null ? 'Arrêté' : 'Taux non arrêté au barème',
                rendu: (_, r) => r['signalTaux'] == null
                    ? const BadgeSigh('Arrêté', ton: TonSigh.succes, icone: LucideIcons.gavel)
                    : const BadgeSigh('Taux non arrêté au barème', ton: TonSigh.attention, icone: LucideIcons.triangleAlert)),
          ],
        ),
    ]);
  }
}
