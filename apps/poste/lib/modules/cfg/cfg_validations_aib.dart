import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/service_installation.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m8/commun.dart' show dateDe;
import 'cfa_commun.dart';

/// `cfg-validations-aib` — « Validations de l’AIB » : TROIS FORMULAIRES DE VALIDATION aux Paramètres (Direction, 09/11/2026, décisions D4, D7 et D8).
///
/// 1. « Validation du barème AIB » : la revue des versions du barème par situation, arrêt ou maintien non arrêté. Elle PILOTE la mécanique d'arrêt de
///    `m12-aib` (`cpdControlerVersionAib`, la même, jamais dupliquée) : arrêter une version écrit son arrêt dans `baremeAib` ; la décision est consignée ;
/// 2. « Validation de la base de l’AIB des factures fournisseurs » : le choix de la base (hors taxes, montant facturé), appliqué par le moteur de retenue à
///    partir de la version en vigueur à la date de la facture ;
/// 4. « Comptes de l’AIB » : les quatre comptes (AIB subi, AIB retenu ou collecté, imputation, fournisseur) lus par la retenue et par l'AIB subi à la date de la pièce ;
///    marqués « à confirmer par l'expert-comptable » tant qu'aucun décideur n'a validé ; une version de plus ne réécrit pas les pièces déjà passées.
/// 3. « Validation du branchement IFU » : la table « situation de l'acheteur → taux du barème arrêté qu'elle utilise » (le branchement LIT le taux au barème,
///    il n'en porte aucun), la situation présumée quand l'IFU est renseigné, la longueur de l'IFU et le taux de repli sans taux arrêté.
///
/// Chaque validation est une VERSION DATÉE de la collection `parametresAib` : décideur, date de la décision, date d'effet et motif obligatoires, journalisée
/// (RG-12), jamais d'écrasement (une version de plus). Les commandes d'écriture sont ABSENTES sans le droit (DAF, comptable, administrateur — la Direction n'écrit plus, décision du 09/11/2026) et sur un
/// poste fileul (la configuration est tenue par la mère, puis reprise ici par la synchronisation).
class EcranValidationsAib extends StatelessWidget with EcranMaquette {
  const EcranValidationsAib({super.key});

  @override
  String get titre => 'Validations de l’AIB';

  @override
  String get description =>
      'Quatre formulaires de validation : le barème de l’AIB, la base de la retenue sur les factures fournisseurs, le branchement de l’IFU de l’acheteur, les comptes de l’AIB.';

  @override
  String get regle =>
      'Rien n’est écrasé : chaque validation ajoute une version datée (décideur, date de la décision, date d’effet, motif), journalisée. Le branchement lit le taux au barème arrêté et n’en porte aucun ; sans taux arrêté en vigueur, le taux de repli s’applique. Les comptes se lisent à la date de la pièce : les pièces déjà passées gardent les leurs.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection(cpaCollection);
    final ancre = ongletValidationsAibDemande;
    ongletValidationsAibDemande = null;
    return ListenableBuilder(
      listenable: Listenable.merge([col, c.magasin.collection('baremeAib'), c.magasin.collection('situationsAib')]),
      builder: (context, _) => cfaPile([
        if (!_peutEcrire(c))
          NoteSigh(
              _fileul(c)
                  ? 'Réglé sur la mère : ces validations se font sur le poste principal, puis elles sont reprises ici.'
                  : 'Lecture seule : les validations sont réservées à la DAF, au comptable et à l’administrateur.',
              ton: TonSigh.info,
              icone: LucideIcons.lock),
        OngletsSigh(ancre: ancre, onglets: [
          OngletDef(id: 'bareme', libelle: 'Barème AIB', construire: (_) => _OngletBareme(c: c)),
          OngletDef(id: 'base', libelle: 'Base des factures fournisseurs', construire: (_) => _OngletBase(c: c)),
          OngletDef(id: 'ifu', libelle: 'Branchement IFU', construire: (_) => _OngletIfu(c: c)),
          OngletDef(id: 'comptes', libelle: 'Comptes de l’AIB', construire: (_) => _OngletComptes(c: c)),
        ]),
      ]),
    );
  }
}

/// L'onglet demandé à l'ouverture de l'écran par un LIEN PROFOND venu d'un autre écran (le détail du barème de `m12-aib` demande « comptes ») : lu une fois,
/// à l'ouverture, puis vidé — un lien qui resterait collé rouvrirait le mauvais onglet à l'ouverture suivante.
String? ongletValidationsAibDemande;

bool _fileul(ContexteEcran c) => ServiceInstallation.de(c.magasin).rattache;

/// Le droit d'écrire : celui de l'écran (matrice : DAF, comptable, administrateur ; lecture : aide-comptable, assistant de direction) ET un poste qui tient sa configuration.
bool _peutEcrire(ContexteEcran c) => c.droit.editer && !_fileul(c);

String _d(Object? v) => v == null || '$v'.isEmpty ? '—' : dateDe(v);

/// Les deux champs de la décision, communs aux quatre formulaires : le décideur et la date de la décision sont OBLIGATOIRES.
List<ChampDef> _champsDecision() => const [
      ChampDef.section('La décision'),
      ChampDef(nom: 'decideur', libelle: 'Décideur', requis: true, col: ColChamp.tiers, aide: 'La personne ou l’instance qui décide (la Direction).'),
      ChampDef(nom: 'dateDecision', libelle: 'Date de la décision', type: TypeChamp.date, requis: true, col: ColChamp.tiers),
    ];

const ChampDef _champMotif = ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein, requis: true, aide: 'Pourquoi cette décision : texte, communiqué, avis de l’expert-comptable.');

/// Le numéro et l'identifiant de la prochaine version d'une rubrique : `PAA-BASE-2`.
String _idVersion(String rubrique, int n) =>
    'PAA-${switch (rubrique) { cpaRubriqueBase => 'BASE', cpaRubriqueBranchement => 'IFU', cpaRubriqueComptes => 'COMPTES', _ => 'BAR' }}-$n';

/// Écrit UNE version datée (jamais d'écrasement), puis UNE ligne de journal nommée (RG-12). Rend la fiche écrite.
Fiche _ecrireVersion(ContexteEcran c, String rubrique, String actionJournal, Map<String, Object?> contenu, Map<String, Object?> v) {
  final col = c.magasin.collection(cpaCollection);
  final n = cpaVersionSuivante(col.toutes, rubrique);
  final fiche = <String, Object?>{
    'id': _idVersion(rubrique, n),
    'statut': 'actif',
    'rubrique': rubrique,
    'version': n,
    ...contenu,
    'decideur': '${v['decideur']}'.trim(),
    'dateDecision': isoJour(v['dateDecision']),
    if ('${v['dateEffet'] ?? ''}'.isNotEmpty) 'dateEffet': isoJour(v['dateEffet']),
    'motif': '${v['motif']}'.trim(),
    'saisiPar': acteur(c).nom,
    'saisiLe': isoJour(c.aujourdhui),
  };
  col.ajouterSansJournal(fiche, enTete: true);
  c.magasin.journaliser(actionJournal, 'CFG', cpaCollection, '${fiche['id']}', null, {
    'rubrique': rubrique,
    'version': n,
    ...contenu,
    'decideur': fiche['decideur'],
    'dateDecision': fiche['dateDecision'],
    if (fiche['dateEffet'] != null) 'dateEffet': fiche['dateEffet'],
  });
  return fiche;
}

/// Le tableau des versions d'une rubrique, la plus récente en tête ; la version EN VIGUEUR à la date du jour porte son badge.
Widget _tableVersions(ContexteEcran c, String rubrique, List<ColonneMini> colonnesPropres) {
  final fiches = c.magasin.collection(cpaCollection).actives;
  final versions = cpaVersionsDe(fiches, rubrique).reversed.toList();
  final enVigueur = cpaFicheALaDate(fiches, rubrique, c.aujourdhui);
  return MiniTableauSigh(
      vide: 'Aucune version enregistrée : la graine du moteur s’applique tant qu’une validation n’est pas écrite.',
      colonnes: [
        ColonneMini('Version', (f) => 'v${f['version']}', rendu: (f) => cfaCode('v${f['version']}')),
        ColonneMini('Statut', (f) => '', rendu: (f) {
          if (f['graine'] == true && '${f['decideur'] ?? ''}'.isEmpty) return const BadgeSigh('Graine, à valider', ton: TonSigh.attention, icone: LucideIcons.triangleAlert);
          if (enVigueur != null && f['id'] == enVigueur['id']) return const BadgeSigh('En vigueur', ton: TonSigh.succes, icone: LucideIcons.circleCheck);
          final effet = '${f['dateEffet'] ?? ''}';
          return effet.isNotEmpty && isoJour(effet).compareTo(isoJour(c.aujourdhui)) > 0
              ? const BadgeSigh('À venir', ton: TonSigh.info)
              : const BadgeSigh('Remplacée');
        }),
        ColonneMini('Depuis le', (f) => f['dateEffet'] == null ? 'l’ouverture' : _d(f['dateEffet'])),
        ...colonnesPropres,
        ColonneMini('Décideur', (f) => '${f['decideur'] ?? '—'}'),
        ColonneMini('Décision du', (f) => _d(f['dateDecision'])),
        ColonneMini('Motif', (f) => '${f['motif'] ?? '—'}'),
      ],
      lignes: versions);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// 1. Validation du barème AIB
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _OngletBareme extends StatefulWidget {
  const _OngletBareme({required this.c});
  final ContexteEcran c;
  @override
  State<_OngletBareme> createState() => _EtatBareme();
}

class _EtatBareme extends State<_OngletBareme> {
  ControleurFormulaire? _ctl;
  String _signature = '';

  ContexteEcran get c => widget.c;

  String _libelle(Iterable<Fiche> situations, Object? code) {
    for (final s in situations) {
      if ('${s['code']}' == '$code') return '${s['libelle'] ?? code}';
    }
    return '$code';
  }

  String _pct(Object? t) {
    final x = t is num ? t : num.tryParse('$t');
    return x == null ? '—' : (x == x.roundToDouble() ? '${x.toInt()} %' : '$x %'.replaceAll('.', ','));
  }

  ControleurFormulaire _formulaire(List<Fiche> versions, List<Fiche> situations) {
    final sig = versions.map((f) => '${f['id']}:${f['statutArret']}').join('|');
    if (_ctl != null && sig == _signature) return _ctl!;
    _ctl?.dispose();
    _signature = sig;
    return _ctl = ControleurFormulaire([
      const ChampDef.section('La version du barème'),
      ChampDef(
          nom: 'version',
          libelle: 'Version du barème à revoir',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [
            for (final f in versions)
              OptionChamp('${f['id']}', '${_libelle(situations, f['situation'])} — ${_pct(f['taux'])} — ${cpdEstArretee(f) ? 'arrêtée' : 'non arrêtée'}')
          ]),
      ChampDef(nom: 'choix', libelle: 'Décision', type: TypeChamp.select, requis: true, options: [for (final x in cpaChoixBareme) OptionChamp(x.$1, x.$2)]),
      const ChampDef(
          nom: 'dateEffet',
          libelle: 'Date d’effet du taux arrêté',
          type: TypeChamp.date,
          requis: true,
          condition: (controle: 'choix', quand: [cpaChoixArreter]),
          aide: 'Le taux s’applique à compter de cette date ; le passé ne se réécrit pas.'),
      ..._champsDecision(),
      _champMotif,
    ]);
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  void _enregistrer(List<Fiche> versions, List<Fiche> situations) {
    final ctl = _ctl!;
    final v = ctl.valider();
    if (v == null) {
      ToastsSigh.afficher(context, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final col = c.magasin.collection(cpaCollection);
    final bareme = c.magasin.collection('baremeAib');
    final choix = '${v['choix']}';
    final record = bareme.parId(v['version']);
    void refuser(String detail) => ToastsSigh.afficher(context, 'Validation refusée.', type: TypeToast.erreur, detail: detail, duree: const Duration(seconds: 9));
    if (record == null) return refuser('AIB_VERSION_INCONNUE : la version du barème n’existe plus.');
    final refusDecision = cpaControlerVersion(cpaRubriqueBareme, v, col.toutes, c.aujourdhui);
    if (refusDecision != null) return refuser(refusDecision);
    if (cpdEstArretee(record)) {
      return refuser(
          'AIB_VERSION_FIGEE : cette version est déjà arrêtée et ne se revoit pas sur place — ajouter une version à une date d’effet postérieure à l’écran « Acompte sur impôt (AIB) ».');
    }
    final contenu = <String, Object?>{
      'choix': choix,
      'versionBaremeId': '${record['id']}',
      'situation': '${record['situation']}',
      'taux': record['taux'],
    };
    if (choix == cpaChoixArreter) {
      // LA MÉCANIQUE D'ARRÊT DE m12-aib, la même : le contrôle du domaine refuse en nommant (date d'effet, arrêt incomplet, date d'effet en double).
      final saisie = <String, Object?>{
        'situation': record['situation'],
        'taux': record['taux'],
        'source': record['source'],
        'motif': record['motif'] ?? v['motif'],
        'statutArret': cpdStatutArrete,
        'dateEffet': isoJour(v['dateEffet']),
        'dateArret': isoJour(v['dateDecision']),
        'decideurArret': '${v['decideur']}'.trim(),
      };
      final refus = cpdControlerVersionAib(saisie, record, bareme.actives, c.aujourdhui, situations: situations);
      if (refus != null) return refuser(refus);
      bareme.mettreAJour(record['id'], {
        'dateEffet': isoJour(v['dateEffet']),
        'statutArret': cpdStatutArrete,
        'arrete': true,
        'aValider': false,
        'dateArret': isoJour(v['dateDecision']),
        'decideurArret': '${v['decideur']}'.trim(),
      });
      contenu['dateEffetArretee'] = isoJour(v['dateEffet']);
    }
    final fiche = _ecrireVersion(c, cpaRubriqueBareme, choix == cpaChoixArreter ? 'Validation du barème AIB : version arrêtée' : 'Validation du barème AIB : version maintenue non arrêtée',
        contenu, {...v, 'dateEffet': null});
    ToastsSigh.afficher(context, choix == cpaChoixArreter ? 'Version du barème arrêtée.' : 'Version maintenue non arrêtée.',
        type: TypeToast.succes, detail: 'Validation v${fiche['version']} consignée par ${fiche['decideur']} le ${_d(fiche['dateDecision'])}.');
    setState(() => _signature = '');
  }

  @override
  Widget build(BuildContext context) {
    final versions = c.magasin.collection('baremeAib').actives.toList()
      ..sort((a, b) {
        final s = '${a['situation']}'.compareTo('${b['situation']}');
        return s != 0 ? s : '${a['dateEffet'] ?? ''}'.compareTo('${b['dateEffet'] ?? ''}');
      });
    final situations = c.magasin.collection('situationsAib').actives;
    final nonArretees = versions.where((f) => !cpdEstArretee(f)).toList();
    final aRevoir = [for (final f in versions) if (!cpdEstArretee(f)) f];
    final f = _formulaire(aRevoir, situations);
    return cfaPile([
      NoteSigh(
          nonArretees.isEmpty
              ? 'Toutes les versions du barème sont arrêtées : il n’y a rien à revoir. Une correction ajoute une version à l’écran « Acompte sur impôt (AIB) ».'
              : 'À REVOIR : ${[for (final x in nonArretees) '${_pct(x['taux'])} (${_libelle(situations, x['situation'])})'].join(' ; ')} — non arrêté${nonArretees.length > 1 ? 's' : ''}, sans effet tant que la Direction ne l’arrête pas.',
          ton: nonArretees.isEmpty ? TonSigh.succes : TonSigh.attention,
          icone: nonArretees.isEmpty ? LucideIcons.circleCheck : LucideIcons.triangleAlert),
      CarteSigh(
          titre: 'Versions du barème par situation',
          child: MiniTableauSigh(
              colonnes: [
                ColonneMini('Situation', (x) => _libelle(situations, x['situation'])),
                ColonneMini('Taux', (x) => _pct(x['taux']), droite: true),
                ColonneMini('Depuis le', (x) => x['dateEffet'] == null || '${x['dateEffet']}'.isEmpty ? 'à fixer à l’arrêt' : _d(x['dateEffet'])),
                ColonneMini('Statut', (x) => cpdEstArretee(x) ? 'Arrêté' : 'Non arrêté', rendu: (x) {
                  return cpdEstArretee(x)
                      ? const BadgeSigh('Arrêté', ton: TonSigh.succes, icone: LucideIcons.gavel)
                      : const BadgeSigh('Non arrêté, à valider', ton: TonSigh.attention, icone: LucideIcons.triangleAlert);
                }),
                ColonneMini('Arrêt', (x) => cpdEstArretee(x) ? '${x['decideurArret'] ?? ''} le ${_d(x['dateArret'])}' : '—'),
              ],
              lignes: versions)),
      if (_peutEcrire(c) && aRevoir.isNotEmpty)
        CarteSigh(
            titre: 'Validation du barème AIB',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FormulaireSigh(key: ValueKey(_signature), controleur: f),
              const SizedBox(height: 16),
              Wrap(spacing: 8, children: [
                BoutonSigh(
                    key: const Key('aib:valider:bareme'),
                    libelle: 'Enregistrer la validation',
                    icone: LucideIcons.gavel,
                    onPressed: () => _enregistrer(aRevoir, situations)),
                BoutonSigh(
                    libelle: 'Ouvrir le barème',
                    icone: LucideIcons.percent,
                    variante: VarianteBouton.secondaire,
                    onPressed: () => c.aller('m12-aib')),
              ]),
            ])),
      CarteSigh(
          titre: 'Décisions consignées (versions datées)',
          child: _tableVersions(c, cpaRubriqueBareme, [
            ColonneMini('Décision', (x) => [for (final o in cpaChoixBareme) if (o.$1 == '${x['choix']}') o.$2].firstOrNull ?? '—'),
            ColonneMini('Version du barème', (x) => '${_libelle(situations, x['situation'])} — ${_pct(x['taux'])}'),
          ])),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// 2. Validation de la base de l'AIB des factures fournisseurs
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _OngletBase extends StatefulWidget {
  const _OngletBase({required this.c});
  final ContexteEcran c;
  @override
  State<_OngletBase> createState() => _EtatBase();
}

class _EtatBase extends State<_OngletBase> {
  ControleurFormulaire? _ctl;
  ContexteEcran get c => widget.c;

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  ControleurFormulaire _formulaire() => _ctl ??= ControleurFormulaire([
        const ChampDef.section('La base de la retenue'),
        ChampDef(
            nom: 'base',
            libelle: 'Base de l’AIB retenu sur une facture fournisseur',
            type: TypeChamp.select,
            requis: true,
            col: ColChamp.plein,
            options: [for (final b in cpaBases) OptionChamp(b.$1, b.$2)],
            aide: 'Hors taxes : la base est le montant hors taxes de la facture quand il est renseigné ; sinon le montant facturé, et la fenêtre de retenue le dit.'),
        const ChampDef(
            nom: 'dateEffet',
            libelle: 'Date d’effet',
            type: TypeChamp.date,
            requis: true,
            aide: 'Le moteur applique à chaque facture la version en vigueur à SA date : une version de plus ne change pas une retenue déjà constatée.'),
        ..._champsDecision(),
        _champMotif,
      ], {
        'base': cpaParametresALaDate(c.magasin.collection(cpaCollection).actives, c.aujourdhui).base,
      });

  void _enregistrer() {
    final ctl = _ctl!;
    final v = ctl.valider();
    if (v == null) {
      ToastsSigh.afficher(context, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final col = c.magasin.collection(cpaCollection);
    final refus = cpaControlerVersion(cpaRubriqueBase, v, col.toutes, c.aujourdhui);
    if (refus != null) {
      ToastsSigh.afficher(context, 'Validation refusée.', type: TypeToast.erreur, detail: refus, duree: const Duration(seconds: 9));
      return;
    }
    final f = _ecrireVersion(c, cpaRubriqueBase, 'Validation de la base de l’AIB des factures fournisseurs', {'base': '${v['base']}'}, v);
    ToastsSigh.afficher(context, 'Base de l’AIB validée.',
        type: TypeToast.succes, detail: 'Version ${f['version']} : ${[for (final b in cpaBases) if (b.$1 == f['base']) b.$2].first}, à compter du ${_d(f['dateEffet'])}.');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = cpaParametresALaDate(c.magasin.collection(cpaCollection).actives, c.aujourdhui);
    final libelleBase = [for (final b in cpaBases) if (b.$1 == p.base) b.$2].first;
    return cfaPile([
      NoteSigh(
          'Base en vigueur au ${dateFR(c.aujourdhui)} : $libelleBase — ${p.provenance}. Sur une facture dont le hors-taxes n’est pas renseigné, la retenue se calcule sur le montant facturé et la fenêtre de retenue le dit.',
          ton: p.deLaGraine ? TonSigh.attention : TonSigh.info,
          icone: LucideIcons.info),
      if (_peutEcrire(c))
        CarteSigh(
            titre: 'Validation de la base de l’AIB des factures fournisseurs',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FormulaireSigh(controleur: _formulaire()),
              const SizedBox(height: 16),
              BoutonSigh(key: const Key('aib:valider:base'), libelle: 'Enregistrer la validation', icone: LucideIcons.gavel, onPressed: _enregistrer),
            ])),
      CarteSigh(
          titre: 'Versions de la base (la plus récente en tête)',
          child: _tableVersions(c, cpaRubriqueBase, [
            ColonneMini('Base', (x) => [for (final b in cpaBases) if (b.$1 == '${x['base']}') b.$2].firstOrNull ?? '—'),
          ])),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// 3. Validation du branchement IFU
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _OngletIfu extends StatefulWidget {
  const _OngletIfu({required this.c});
  final ContexteEcran c;
  @override
  State<_OngletIfu> createState() => _EtatIfu();
}

class _EtatIfu extends State<_OngletIfu> {
  ControleurFormulaire? _ctl;
  ContexteEcran get c => widget.c;

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  ControleurFormulaire _formulaire(List<Fiche> situations) {
    final p = cpaParametresALaDate(c.magasin.collection(cpaCollection).actives, c.aujourdhui);
    final options = [for (final s in cpdSituationsActives(situations)) OptionChamp('${s['code']}', '${s['libelle'] ?? s['code']}')];
    return _ctl ??= ControleurFormulaire([
      const ChampDef.section('Le branchement de l’IFU de l’acheteur'),
      const ChampDef(nom: 'longueurIfu', libelle: 'Nombre de chiffres d’un IFU', type: TypeChamp.nombre, requis: true, col: ColChamp.tiers),
      ChampDef(
          nom: 'situationIfuRenseigne',
          libelle: 'Situation présumée quand l’IFU est renseigné',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: options,
          aide: 'Aujourd’hui : un IFU de 13 chiffres est présumé actif (l’activité n’est pas vérifiée auprès de la DGI).'),
      ChampDef(nom: 'situationIfuAbsent', libelle: 'Situation quand aucun IFU n’est renseigné', type: TypeChamp.select, requis: true, col: ColChamp.plein, options: options),
      const ChampDef(
          nom: 'tauxRepli',
          libelle: 'Taux de repli sans taux arrêté (%)',
          type: TypeChamp.nombre,
          requis: true,
          col: ColChamp.tiers,
          aide: 'Appliqué en retransmission, en vente sans acheteur et à l’affichage de la configuration MECeF quand le barème n’a aucun taux arrêté : jamais un taux inventé.'),
      const ChampDef(nom: 'dateEffet', libelle: 'Date d’effet', type: TypeChamp.date, requis: true, col: ColChamp.tiers),
      ..._champsDecision(),
      _champMotif,
    ], {
      'longueurIfu': '${p.longueurIfu}',
      'situationIfuRenseigne': p.situationIfuRenseigne,
      'situationIfuAbsent': p.situationIfuAbsent,
      'tauxRepli': '${p.tauxRepli}',
    });
  }

  void _enregistrer(List<Fiche> situations) {
    final ctl = _ctl!;
    final v = ctl.valider();
    if (v == null) {
      ToastsSigh.afficher(context, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final col = c.magasin.collection(cpaCollection);
    final refus = cpaControlerVersion(cpaRubriqueBranchement, v, col.toutes, c.aujourdhui, situations: situations);
    if (refus != null) {
      ToastsSigh.afficher(context, 'Validation refusée.', type: TypeToast.erreur, detail: refus, duree: const Duration(seconds: 9));
      return;
    }
    final f = _ecrireVersion(c, cpaRubriqueBranchement, 'Validation du branchement IFU', {
      'longueurIfu': int.parse('${v['longueurIfu']}'.trim()),
      'situationIfuRenseigne': '${v['situationIfuRenseigne']}',
      'situationIfuAbsent': '${v['situationIfuAbsent']}',
      'tauxRepli': int.parse('${v['tauxRepli']}'.trim()),
    }, v);
    ToastsSigh.afficher(context, 'Branchement IFU validé.', type: TypeToast.succes, detail: 'Version ${f['version']} à compter du ${_d(f['dateEffet'])}.');
    setState(() {});
  }

  String _tauxLu(CpdTauxAib r, int repli) => r.ok
      ? '${r.taux} % — ${r.motif}'
      : 'aucun taux arrêté : repli à $repli %${r.enAttente.isEmpty ? '' : ' (au barème, non arrêté : ${r.enAttente.map((f) => '${f['taux']} %').join(', ')})'}';

  @override
  Widget build(BuildContext context) {
    final situations = c.magasin.collection('situationsAib').actives;
    final versions = c.magasin.collection('baremeAib').actives;
    final p = cpaParametresALaDate(c.magasin.collection(cpaCollection).actives, c.aujourdhui);
    final lignes = <Fiche>[
      for (final s in cpdSituationsActives(situations))
        {
          'code': '${s['code']}',
          'libelle': '${s['libelle'] ?? s['code']}',
          'quand': [
            if ('${s['code']}' == p.situationIfuRenseigne) 'IFU de ${p.longueurIfu} chiffres renseigné (présumé actif)',
            if ('${s['code']}' == p.situationIfuAbsent) 'aucun IFU renseigné',
            if ('${s['code']}' != p.situationIfuRenseigne && '${s['code']}' != p.situationIfuAbsent) 'choisie à la main',
          ].join(' ; '),
          'taux': _tauxLu(cpdTauxAibALaDate(versions, '${s['code']}', c.aujourdhui, situations: situations), p.tauxRepli),
          'arrete': cpdTauxAibALaDate(versions, '${s['code']}', c.aujourdhui, situations: situations).ok,
        }
    ];
    return cfaPile([
      NoteSigh(
          'Le branchement LIT le taux au barème arrêté : la table ci-dessous donne, pour chaque situation de l’acheteur, le taux que le barème fournit au ${dateFR(c.aujourdhui)}. Aucun taux n’est porté ici ; sans taux arrêté, le taux de repli (${p.tauxRepli} %) s’applique, ${p.provenance}.',
          ton: p.deLaGraine ? TonSigh.attention : TonSigh.info,
          icone: LucideIcons.info),
      CarteSigh(
          titre: 'Situation de l’acheteur → taux du barème arrêté utilisé',
          child: KeyedSubtree(
              key: const Key('aib:table-branchement'),
              child: MiniTableauSigh(colonnes: [
                ColonneMini('Situation de l’acheteur', (x) => '${x['libelle']}'),
                ColonneMini('Choisie quand', (x) => '${x['quand']}'),
                ColonneMini('Taux fourni par le barème', (x) => '${x['taux']}',
                    rendu: (x) => x['arrete'] == true ? BadgeSigh('${x['taux']}', ton: TonSigh.succes, icone: LucideIcons.gavel) : BadgeSigh('${x['taux']}', ton: TonSigh.attention, icone: LucideIcons.triangleAlert)),
              ], lignes: lignes))),
      if (_peutEcrire(c))
        CarteSigh(
            titre: 'Validation du branchement IFU',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FormulaireSigh(controleur: _formulaire(situations)),
              const SizedBox(height: 16),
              BoutonSigh(key: const Key('aib:valider:ifu'), libelle: 'Enregistrer la validation', icone: LucideIcons.gavel, onPressed: () => _enregistrer(situations)),
            ])),
      CarteSigh(
          titre: 'Versions du branchement (la plus récente en tête)',
          child: _tableVersions(c, cpaRubriqueBranchement, [
            ColonneMini('IFU renseigné', (x) => '${x['situationIfuRenseigne'] ?? '—'}'),
            ColonneMini('IFU absent', (x) => '${x['situationIfuAbsent'] ?? '—'}'),
            ColonneMini('Chiffres', (x) => '${x['longueurIfu'] ?? '—'}', droite: true),
            ColonneMini('Repli', (x) => '${x['tauxRepli'] ?? '—'} %', droite: true),
          ])),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// 4. Comptes de l'AIB
// ---------------------------------------------------------------------------------------------------------------------------------------------

class _OngletComptes extends StatefulWidget {
  const _OngletComptes({required this.c});
  final ContexteEcran c;
  @override
  State<_OngletComptes> createState() => _EtatComptes();
}

class _EtatComptes extends State<_OngletComptes> {
  ControleurFormulaire? _ctl;
  ContexteEcran get c => widget.c;

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  ControleurFormulaire _formulaire() {
    final p = cpaComptesALaDate(c.magasin.collection(cpaCollection).actives, c.aujourdhui);
    return _ctl ??= ControleurFormulaire([
      const ChampDef.section('Les comptes de l’AIB'),
      const ChampDef(nom: 'compteAibSubi', libelle: 'Compte de l’AIB subi (créance sur l’État)', requis: true, col: ColChamp.tiers, aide: 'Débité quand un fournisseur facture un AIB à la clinique.'),
      const ChampDef(nom: 'compteAibRetenu', libelle: 'Compte de l’AIB retenu ou collecté (dette)', requis: true, col: ColChamp.tiers, aide: 'Crédité par la retenue d’AIB sur une facture fournisseur.'),
      const ChampDef(nom: 'compteImputation', libelle: 'Compte d’imputation', requis: true, col: ColChamp.tiers, aide: 'Impôt sur les bénéfices : indiqué en lecture au registre de l’AIB, jamais écrit.'),
      const ChampDef(nom: 'compteFournisseur', libelle: 'Compte fournisseur', requis: true, col: ColChamp.tiers, aide: 'Débité par la retenue, crédité par l’AIB subi.'),
      const ChampDef(
          nom: 'dateEffet',
          libelle: 'Date d’effet',
          type: TypeChamp.date,
          requis: true,
          col: ColChamp.tiers,
          aide: 'Le moteur lit, pour chaque pièce, la version en vigueur à SA date : une version de plus ne réécrit pas les pièces déjà passées.'),
      ..._champsDecision(),
      _champMotif,
    ], {
      'compteAibSubi': p.subi,
      'compteAibRetenu': p.retenu,
      'compteImputation': p.imputation,
      'compteFournisseur': p.fournisseur,
    });
  }

  void _enregistrer() {
    final ctl = _ctl!;
    final v = ctl.valider();
    if (v == null) {
      ToastsSigh.afficher(context, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final col = c.magasin.collection(cpaCollection);
    final refus = cpaControlerVersion(cpaRubriqueComptes, v, col.toutes, c.aujourdhui);
    if (refus != null) {
      ToastsSigh.afficher(context, 'Validation refusée.', type: TypeToast.erreur, detail: refus, duree: const Duration(seconds: 9));
      return;
    }
    final f = _ecrireVersion(c, cpaRubriqueComptes, 'Validation des comptes de l’AIB', {
      'compteAibSubi': '${v['compteAibSubi']}'.trim(),
      'compteAibRetenu': '${v['compteAibRetenu']}'.trim(),
      'compteImputation': '${v['compteImputation']}'.trim(),
      'compteFournisseur': '${v['compteFournisseur']}'.trim(),
    }, v);
    ToastsSigh.afficher(context, 'Comptes de l’AIB validés.',
        type: TypeToast.succes, detail: 'Version ${f['version']} à compter du ${_d(f['dateEffet'])} : les pièces antérieures gardent leurs comptes.');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = cpaComptesALaDate(c.magasin.collection(cpaCollection).actives, c.aujourdhui);
    return cfaPile([
      NoteSigh(
          'Comptes en vigueur au ${dateFR(c.aujourdhui)} : AIB subi ${p.subi}, AIB retenu ${p.retenu}, imputation ${p.imputation}, fournisseur ${p.fournisseur} — ${p.provenance}. '
          '${p.deLaGraine ? 'Aucune version n’est enregistrée : la graine du code répond (repli) jusqu’à la première validation. ' : ''}'
          'La retenue et l’AIB subi lisent la version en vigueur à la date de la pièce ; une pièce déjà passée garde ses comptes d’origine.',
          ton: p.aConfirmer ? TonSigh.attention : TonSigh.info,
          icone: p.aConfirmer ? LucideIcons.triangleAlert : LucideIcons.info),
      if (p.aConfirmer)
        KeyedSubtree(
            key: const Key('aib:comptes-a-confirmer'),
            child: const NoteSigh(
                'À CONFIRMER PAR L’EXPERT-COMPTABLE : aucune source consultée ne confirme 4492 pour l’AIB subi (ni 441) ; le plan SYSCOHADA place 4478 sous 447 et l’impôt sur les bénéfices en 891. Le marquage tombe à la validation (décideur et date de la décision).',
                ton: TonSigh.attention,
                icone: LucideIcons.triangleAlert)),
      if (_peutEcrire(c))
        CarteSigh(
            titre: 'Validation des comptes de l’AIB',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FormulaireSigh(controleur: _formulaire()),
              const SizedBox(height: 16),
              BoutonSigh(key: const Key('aib:valider:comptes'), libelle: 'Enregistrer la validation', icone: LucideIcons.gavel, onPressed: _enregistrer),
            ])),
      CarteSigh(
          titre: 'Versions des comptes (la plus récente en tête)',
          child: _tableVersions(c, cpaRubriqueComptes, [
            ColonneMini('AIB subi', (x) => '${x['compteAibSubi'] ?? '—'}'),
            ColonneMini('AIB retenu', (x) => '${x['compteAibRetenu'] ?? '—'}'),
            ColonneMini('Imputation', (x) => '${x['compteImputation'] ?? '—'}'),
            ColonneMini('Fournisseur', (x) => '${x['compteFournisseur'] ?? '—'}'),
            ColonneMini('Confirmation', (x) => '${x['decideur'] ?? ''}'.isEmpty ? 'À confirmer par l’expert-comptable' : 'Validée'),
          ])),
    ]);
  }
}
