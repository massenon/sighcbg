import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/tarifs_poste.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m7/pv_crud.dart';
import 'commun.dart';

/// Le taux de couverture n'est PAS unique par patient : il varie d'une convention à l'autre et, pour un même assuré, selon la nature de la
/// prestation. Trois niveaux, tels que les pièces réelles les montrent : compagnie → souscripteur (n° de police) → assuré, et c'est le SOUSCRIPTEUR
/// qui porte la grille. Tant qu'une convention n'est pas saisie, la facturation reste intégralement à la charge du patient — et l'écran le dit.
/// T13 : les garanties d'un souscripteur telles que l'écran les COMPTE et les liste : UNE version par série, celle EN VIGUEUR au [jour] (comme la prise en charge, RG-09). Lister toutes
/// les versions ferait dire « six garanties » pour trois séries dont deux ont changé de taux. Une série qui ne prend effet que plus tard n'y figure pas encore.
List<Fiche> garantiesEnVigueurDe(Iterable<Fiche> garanties, Object? souscripteurId, String jour) =>
    [for (final s in assSeriesGarantie(garanties, jour, souscripteurId: souscripteurId)) if (s.enVigueur != null) s.enVigueur!];

/// « depuis l'ouverture » : la version sans date d'effet est celle d'avant le mécanisme ; aucune date n'est inventée à sa place.
String depuisLe(Fiche g) {
  final d = g['dateEffet'];
  return d == null || '$d'.isEmpty ? 'l’ouverture' : dateDe(d);
}

String _plafondTexte(Fiche g) => g['plafond'] == null ? 'sans plafond' : '${m(g['plafond'])} ${assLibelleUnite(g['unitePlafond'])}';

/// Pose UNE version par le moteur du domaine (`assPoserGarantie`) avec les fiches du magasin : c'est le même chemin pour l'écran, la grille d'un bloc et l'import.
AssPoseGarantie poserGarantie(ContexteEcran c, Map<String, Object?> spec, {bool essai = false}) => assPoserGarantie(spec,
    souscripteurs: actives(c, 'souscripteurs'),
    garanties: actives(c, 'garanties'),
    factures: actives(c, 'factures'),
    patients: actives(c, 'patients'),
    couvertures: actives(c, 'couverturesAssurance'),
    essai: essai);

class EcranConventions extends StatelessWidget with EcranMaquette {
  const EcranConventions({super.key});

  @override
  String get titre => 'Conventions & garanties';

  @override
  String get description =>
      'Grille de prise en charge par souscripteur : taux et plafonds par catégorie, exclusions et accords préalables.';

  @override
  String get regle =>
      'Le taux de couverture n’est pas unique par patient : il varie d’une convention à l’autre et, pour un même assuré, selon la nature de la prestation. Tant qu’une convention n’est pas saisie, la facturation reste intégralement à la charge du patient — et l’écran le dit. RG-09 — la prise en charge ne s’applique que si la carte est valide à la date de facturation.';

  @override
  List<Widget> actionsEntete(BuildContext context) {
    final c = ContexteEcran.of(context);
    return [
      ...actionsImporter(context, 'souscripteurs'),
      BoutonSigh(
          libelle: 'Assurés & cartes',
          icone: LucideIcons.idCard,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m9-assures')),
      BoutonSigh(
          libelle: 'Compagnies',
          icone: LucideIcons.building2,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m9-compagnies')),
      BoutonSigh(
          libelle: 'Prises en charge',
          icone: LucideIcons.shieldCheck,
          variante: VarianteBouton.secondaire,
          onPressed: () => c.aller('m9-prises-en-charge')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    return ListenableBuilder(
      listenable: ecoute(c, [
        'assureurs',
        'patients',
        'souscripteurs',
        'garanties',
        'couverturesAssurance'
      ]),
      builder: (context, _) {
        final sous = actives(c, 'souscripteurs');
        final garanties = actives(c, 'garanties');
        final jour = iso(c.aujourdhui);
        final series = assSeriesGarantie(garanties, jour);
        final enVigueur = series.where((x) => x.enVigueur != null).length;
        final avecGrille = sous.where((s) => series.any((x) => x.souscripteurId == s['id'] && x.enVigueur != null)).length;
        final aCollecter = sous.length - avecGrille;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Souscripteurs',
                    valeur: nombre(sous.length),
                    indice:
                        'Contrats sous ${actives(c, 'assureurs').length} compagnies',
                    icone: LucideIcons.fileSignature),
                KpiSigh(
                    libelle: 'Conventions saisies',
                    valeur: nombre(avecGrille),
                    icone: LucideIcons.checkCircle2,
                    ton: avecGrille > 0 ? TonSigh.succes : TonSigh.attention),
                KpiSigh(
                    libelle: 'Conventions à collecter',
                    valeur: nombre(aCollecter),
                    icone: LucideIcons.circleHelp,
                    ton: TonSigh.attention),
                KpiSigh(
                    libelle: 'Garanties en vigueur',
                    valeur: nombre(enVigueur),
                    indice: garanties.length > series.length ? '${nombre(garanties.length)} versions écrites, ${nombre(series.length)} séries' : null,
                    icone: LucideIcons.percent,
                    ton: TonSigh.info),
              ]),
              if (aCollecter > 0) ...[
                const SizedBox(height: 16),
                NoteSigh(
                    '$aCollecter convention(s) non saisie(s). Un seul barème figure au dossier — celui d’un régime employeur, versé le 18/06/2026 — et il ne vaut que pour son souscripteur. Les grilles des autres compagnies restent à collecter. En attendant, leurs assurés sont facturés intégralement : mieux vaut une facture juste qu’une prise en charge supposée.',
                    ton: TonSigh.attention,
                    icone: LucideIcons.circleHelp),
              ],
              const SizedBox(height: 16),
              OngletsSigh(onglets: [
                OngletDef(
                    id: 'souscripteurs',
                    libelle: 'Souscripteurs',
                    compte: sous.length,
                    construire: (ctx) => _OngletSouscripteurs(c: c)),
                OngletDef(
                    id: 'garanties',
                    libelle: 'Grilles de garanties',
                    compte: series.length,
                    construire: (ctx) => _ongletGaranties(ctx, c, series, sous)),
                OngletDef(
                    id: 'simulateur',
                    libelle: 'Simulateur de répartition',
                    construire: (ctx) => _Simulateur(c: c)),
              ]),
            ]);
      },
    );
  }

  Widget _ongletGaranties(BuildContext ctx0, ContexteEcran c, List<AssSerieGarantie> series, List<Fiche> sous) {
    if (series.isEmpty) {
      return const VideSigh(
          'Aucune convention saisie. Ouvrir un souscripteur pour saisir sa grille.',
          icone: LucideIcons.percent);
    }
    final rows = [
      for (final x in series)
        () {
          final s = sous.where((y) => y['id'] == x.souscripteurId).firstOrNull;
          final g = x.enVigueur ?? x.aVenir!;
          return <String, Object?>{
            ...g,
            'id': x.cle,
            'souscripteur': s != null ? s['nom'] : '—',
            'compagnie': s != null ? s['assureurNom'] : g['assureur'],
            'versions': x.versions.length,
            'aVenir': x.aVenir?['dateEffet'],
            'pasEncore': x.enVigueur == null,
            '_serie': x,
          };
        }()
    ];
    final noms = ({for (final r in rows) '${r['souscripteur']}'}.toList()..sort());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Le bouton « Importer » des garanties vit dans l'onglet qu'il alimente : l'en-tête de la page porte déjà quatre commandes.
      if (actionsImporter(ctx0, 'garanties').isNotEmpty) Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(bottom: 8), child: Wrap(spacing: 8, children: actionsImporter(ctx0, 'garanties')))),
      const NoteSigh(
          'Une ligne par garantie : la version en vigueur aujourd’hui. Une garantie ne se réécrit jamais — un changement de taux ou de plafond AJOUTE une version avec sa date d’effet, et chaque pièce garde la garantie sous laquelle elle a été émise (RG-09). Cliquer une ligne pour lire son historique.',
          icone: LucideIcons.history),
      const SizedBox(height: 12),
      TableauSigh(
        lignes: rows,
        taillePage: 20,
        nomExport: 'garanties',
        triInitial: 'souscripteur',
        alClicLigne: (r) => _historique(ctx0, c, r['_serie'] as AssSerieGarantie, sous),
        filtres: [
          FiltreTableau(nom: 'souscripteur', libelle: 'Souscripteur', options: [for (final x in noms) OptionChamp(x)]),
          FiltreTableau(nom: 'categorie', libelle: 'Catégorie', options: [for (final x in assCategoriesGarantie) OptionChamp(x.$1, x.$2)]),
        ],
        colonnes: [
          const ColonneTableau(cle: 'souscripteur', libelle: 'Souscripteur'),
          ColonneTableau(
              cle: 'compagnie',
              libelle: 'Compagnie',
              texte: (g) => '${g['compagnie']}',
              rendu: (_, g) => BadgeSigh('${g['compagnie']}', ton: TonSigh.navy)),
          const ColonneTableau(cle: 'libelle', libelle: 'Garantie'),
          ColonneTableau(cle: 'categorie', libelle: 'Catégorie', texte: (g) => assLibelleCategorie(g['categorie'])),
          ColonneTableau(
              cle: 'taux',
              libelle: 'Taux',
              droite: true,
              texte: (g) => g['pasEncore'] == true ? 'pas encore' : '${g['taux']} %',
              rendu: (_, g) => g['pasEncore'] == true
                  ? const Text('pas encore', style: TextStyle(color: JetonsShell.slate300, fontSize: 12, height: 16 / 12))
                  : Text('${g['taux']} %', style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600))),
          ColonneTableau(
              cle: 'plafond',
              libelle: 'Plafond',
              droite: true,
              texte: (g) => g['plafond'] == null ? '' : '${g['plafond']}',
              rendu: (_, g) => g['plafond'] == null
                  ? const Text('sans plafond', style: TextStyle(color: JetonsShell.slate300, fontSize: 12, height: 16 / 12))
                  : Text(_plafondTexte(g), style: const TextStyle(color: JetonsShell.slate700, fontSize: 14, height: 20 / 14))),
          ColonneTableau(
              cle: 'dateEffet',
              libelle: 'En vigueur depuis',
              texte: (g) => depuisLe(g),
              rendu: (_, g) => Text(depuisLe(g), style: const TextStyle(color: JetonsShell.slate600, fontSize: 13, height: 18 / 13))),
          ColonneTableau(
              cle: 'versions',
              libelle: 'Versions',
              droite: true,
              valeur: (g) => g['versions'] as int,
              texte: (g) => '${g['versions']}',
              rendu: (_, g) => Row(mainAxisSize: MainAxisSize.min, children: [
                    BadgeSigh('${g['versions']}', ton: (g['versions'] as int) > 1 ? TonSigh.info : TonSigh.neutre),
                    if (g['aVenir'] != null) ...[const SizedBox(width: 4), BadgeSigh('à venir ${dateDe(g['aVenir'])}', ton: TonSigh.attention)],
                  ])),
        ],
      ),
    ]);
  }

  /// L'historique d'une série : toutes ses versions, la plus ancienne d'abord, celle EN VIGUEUR marquée. Une version n'a ni « Modifier » ni « Archiver » : elle s'AJOUTE.
  void _historique(BuildContext ctx, ContexteEcran c, AssSerieGarantie serie, List<Fiche> sous) {
    final s = sous.where((y) => y['id'] == serie.souscripteurId).firstOrNull;
    afficherTiroir<void>(ctx,
        titre: serie.libelle,
        sousTitre: '${s?['nom'] ?? '—'} — ${assLibelleCategorie(serie.categorie)}',
        largeurMax: 768,
        corps: ListenableBuilder(
            listenable: ecoute(c, ['garanties']),
            builder: (context, _) {
              final jour = iso(c.aujourdhui);
              final courante = assSeriesGarantie(actives(c, 'garanties'), jour, souscripteurId: serie.souscripteurId).where((x) => x.cle == serie.cle).firstOrNull ?? serie;
              final v = courante.versions;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                NoteSigh(
                    courante.enVigueur != null
                        ? 'Version en vigueur aujourd’hui : v${assRangGarantie(courante.enVigueur!, v)}, depuis ${depuisLe(courante.enVigueur!)} (${courante.enVigueur!['taux']} %, ${_plafondTexte(courante.enVigueur!)}). Une pièce datée avant une version garde la précédente.'
                        : 'Aucune version n’est encore en vigueur : la première prend effet le ${dateDe(courante.aVenir!['dateEffet'])}.',
                    icone: LucideIcons.history),
                const SizedBox(height: 12),
                CarteSigh(
                    titre: 'Versions (${v.length})',
                    child: MiniTableauSigh(colonnes: [
                      ColonneMini('Version', (x) => 'v${assRangGarantie(x, v)}'),
                      ColonneMini('Prend effet', (x) => depuisLe(x)),
                      ColonneMini('Taux', (x) => '${x['taux']} %', droite: true),
                      ColonneMini('Plafond', (x) => _plafondTexte(x), droite: true),
                      ColonneMini('État', (x) {
                        if (courante.enVigueur != null && x['id'] == courante.enVigueur!['id']) return 'En vigueur';
                        if ('${x['dateEffet'] ?? ''}'.compareTo(jour) > 0) return 'À venir';
                        return 'Remplacée';
                      }),
                      ColonneMini('Motif', (x) => '${x['motif'] ?? x['source'] ?? '—'}'),
                    ], lignes: v)),
              ]);
            }),
        pied: (fermer) => [
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Nouvelle version datée',
                    icone: LucideIcons.plus,
                    onPressed: () {
                      fermer();
                      _nouvelleVersion(ctx, c, serie);
                    }),
            ]);
  }

  /// Pose UNE version : tous les contrôles du domaine (`assPoserGarantie`) sont refaits, un refus se nomme avec son geste, rien n'est écrit en cas de refus.
  void _nouvelleVersion(BuildContext ctx, ContexteEcran c, AssSerieGarantie serie) {
    final base = serie.enVigueur ?? serie.aVenir!;
    final ctl = ControleurFormulaire([
      const ChampDef(nom: 'dateEffet', libelle: 'Date d’effet', type: TypeChamp.date, requis: true, aide: 'Le jour où les nouvelles valeurs s’appliquent. Les pièces antérieures gardent les valeurs de leur date.'),
      const ChampDef(nom: 'taux', libelle: 'Taux (%)', type: TypeChamp.nombre, requis: true),
      const ChampDef(nom: 'plafond', libelle: 'Plafond (FCFA)', type: TypeChamp.nombre, aide: 'Vide : sans plafond.'),
      ChampDef(nom: 'unitePlafond', libelle: 'Unité du plafond', type: TypeChamp.select, indicatif: '— Sans plafond —', options: [for (final u in assUnitesPlafond.entries) OptionChamp(u.key, u.value)]),
      const ChampDef(nom: 'motif', libelle: 'Motif', col: ColChamp.plein, aide: 'Par exemple : avenant du 01/12/2026.'),
    ], {
      'taux': '${base['taux']}',
      'plafond': base['plafond'] == null ? '' : '${base['plafond']}',
      'unitePlafond': base['unitePlafond'] ?? '',
      'dateEffet': '',
      'motif': '',
    });
    afficherModale<void>(ctx,
        titre: 'Nouvelle version — ${serie.libelle}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoteSigh(
              'La version actuelle (${base['taux']} %, ${_plafondTexte(base)}) reste écrite : une pièce émise garde son taux. La date d’effet doit être postérieure à la dernière version et à la dernière facture émise sous cette grille.',
              icone: LucideIcons.history),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Poser la version',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final r = poserGarantie(c, {
                      'souscripteurId': serie.souscripteurId,
                      'categorie': serie.categorie,
                      'libelle': serie.libelle,
                      'taux': v['taux'],
                      'plafond': v['plafond'],
                      'unitePlafond': v['unitePlafond'],
                      'dateEffet': v['dateEffet'],
                      'motif': '${v['motif'] ?? ''}'.trim().isEmpty ? null : '${v['motif']}'.trim(),
                      'source': 'Saisie à l’écran « Conventions & garanties »',
                    });
                    if (!r.ok) {
                      ToastsSigh.afficher(ctx, r.motif!, type: TypeToast.erreur, detail: r.geste);
                      return;
                    }
                    final f = c.magasin.collection('garanties').inserer(r.fiche!, prefixe: 'GAR').fiche;
                    fermer();
                    ToastsSigh.afficher(ctx, 'Version v${f['version']} posée.', type: TypeToast.succes, detail: '${serie.libelle} : ${f['taux']} % à partir du ${dateDe(f['dateEffet'])}.');
                  }),
            ]);
  }
}

// --- Souscripteurs ---------------------------------------------------------------------------------------------------------------

List<ChampDef> champsSouscripteur(List<Fiche> assureurs) => [
      const ChampDef(
          nom: 'nom',
          libelle: 'Souscripteur',
          requis: true,
          col: ColChamp.plein,
          aide: 'Employeur, groupe ou particulier signataire du contrat.'),
      ChampDef(
          nom: 'assureur',
          libelle: 'Compagnie',
          type: TypeChamp.select,
          requis: true,
          options: [
            for (final a in assureurs) OptionChamp('${a['code']}', '${a['nom']}')
          ]),
      const ChampDef(nom: 'police', libelle: 'N° de police', requis: true),
      const ChampDef(
          nom: 'categorie',
          libelle: 'Catégorie',
          type: TypeChamp.select,
          requis: true,
          options: [
            OptionChamp('entreprise', 'Assurance entreprise'),
            OptionChamp('particulier', 'Assurance particulier'),
            OptionChamp('personnel', 'Assurance personnel de la clinique'),
          ]),
      const ChampDef(
          nom: 'effectif', libelle: 'Bénéficiaires déclarés', type: TypeChamp.nombre),
      const ChampDef(nom: 'contact', libelle: 'Interlocuteur', col: ColChamp.plein),
      const ChampDef(
          nom: 'dateDebut', libelle: 'Début de validité', type: TypeChamp.date),
      const ChampDef(
          nom: 'dateFin',
          libelle: 'Fin de validité',
          type: TypeChamp.date,
          aide: 'Laisser vide si la convention est en cours.'),
    ];

Fiche _souscripteurSaisi(Map<String, Object?> s) => {
      'nom': s['nom'],
      'assureur': s['assureur'],
      'police': s['police'],
      'categorie': s['categorie'],
      'effectif': num.tryParse('${s['effectif'] ?? ''}'.trim()),
      'contact': s['contact'] ?? '',
      'dateDebut': s['dateDebut'] ?? '',
      'dateFin': s['dateFin'] ?? '',
    };

class _OngletSouscripteurs extends StatelessWidget {
  const _OngletSouscripteurs({required this.c});
  final ContexteEcran c;

  /// La grille LUE (une version par série, celle en vigueur aujourd'hui) : ce que l'écran compte, liste et imprime est ce que la prise en charge applique.
  List<Fiche> _garantiesDe(Object? id) => garantiesEnVigueurDe(actives(c, 'garanties'), id, iso(c.aujourdhui));
  List<Fiche> _assuresDe(Object? id) => actives(c, 'patients')
      .where((p) => p['souscripteurId'] == id)
      .toList();

  @override
  Widget build(BuildContext context) {
    final sous = actives(c, 'souscripteurs');
    final assureurs = actives(c, 'assureurs');
    final col = c.magasin.collection('souscripteurs');
    return TableauSigh(
      lignes: sous,
      taillePage: 15,
      nomExport: 'souscripteurs',
      triInitial: 'nom',
      alClicLigne: (s) => _fiche(context, s),
      filtres: [
        FiltreTableau(nom: 'categorie', libelle: 'Catégorie', options: [
          OptionChamp('entreprise', 'Entreprise'),
          OptionChamp('particulier', 'Particulier'),
          OptionChamp('personnel', 'Personnel de la clinique'),
        ]),
        FiltreTableau(
            nom: 'grille',
            libelle: 'Convention',
            options: [OptionChamp('oui', 'Saisie'), OptionChamp('non', 'À collecter')],
            correspond: (r, v) {
              final a = _garantiesDe(r['id']).isNotEmpty;
              return v == 'oui' ? a : !a;
            }),
      ],
      colonnes: [
        ColonneTableau(
            cle: 'nom',
            libelle: 'Souscripteur',
            texte: (s) => '${s['nom']} ${s['police']}',
            rendu: (_, s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${s['nom']}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: JetonsShell.slate800,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w500)),
                      Text('${s['police']}',
                          style: mono.copyWith(color: JetonsShell.slate400)),
                    ])),
        ColonneTableau(
            cle: 'assureurNom',
            libelle: 'Compagnie',
            texte: (s) => '${s['assureur']}',
            rendu: (_, s) => BadgeSigh('${s['assureur']}', ton: TonSigh.navy)),
        ColonneTableau(
            cle: 'categorie',
            libelle: 'Catégorie',
            texte: (s) => '${s['categorie']}',
            rendu: (_, s) {
              const mp = {
                'entreprise': ('Entreprise', TonSigh.info),
                'particulier': ('Particulier', TonSigh.neutre),
                'personnel': ('Personnel', TonSigh.succes)
              };
              final x = mp['${s['categorie']}'] ?? mp['particulier']!;
              return BadgeSigh(x.$1, ton: x.$2);
            }),
        ColonneTableau(
            cle: 'assures',
            libelle: 'Assurés',
            droite: true,
            valeur: (s) => _assuresDe(s['id']).length,
            texte: (s) => '${_assuresDe(s['id']).length}'),
        ColonneTableau(
            cle: 'grille',
            libelle: 'Convention',
            valeur: (s) => _garantiesDe(s['id']).length,
            texte: (s) => _garantiesDe(s['id']).isEmpty
                ? 'À collecter'
                : '${_garantiesDe(s['id']).length} garanties',
            rendu: (_, s) {
              final k = _garantiesDe(s['id']).length;
              return k > 0
                  ? BadgeSigh('$k garanties', ton: TonSigh.succes)
                  : const BadgeSigh('À collecter', ton: TonSigh.attention);
            }),
      ],
      actions: [
        if (c.droit.editer)
          BoutonSigh(
              libelle: 'Nouveau',
              icone: LucideIcons.plus,
              taille: TailleBouton.sm,
              onPressed: () => ouvrirFormulaireFiche(context,
                  collection: col,
                  champs: champsSouscripteur(assureurs),
                  entite: 'Souscripteur',
                  prefixeId: 'SOU',
                  identifiant: (x) => '${x['nom'] ?? ''}',
                  valeursCreation: {
                    'categorie': 'entreprise',
                    'assureur': assureurs.isEmpty ? '' : '${assureurs.first['code']}'
                  },
                  versFiche: (s) =>
                      assSouscripteurDepuis(_souscripteurSaisi(s), assureurs),
                  detailMessage: false)),
      ],
      actionsLigne: (ctx, s) => [
        BoutonIcone(
            icone: LucideIcons.percent,
            libelle: 'Saisir la grille',
            onPressed: () => _fiche(ctx, s)),
        if (c.droit.editer)
          BoutonIcone(
              icone: LucideIcons.pencil,
              libelle: 'Modifier',
              onPressed: () => ouvrirFormulaireFiche(ctx,
                  collection: col,
                  champs: champsSouscripteur(assureurs),
                  entite: 'Souscripteur',
                  record: s,
                  identifiant: (x) => '${x['nom'] ?? ''}',
                  // La compagnie dérivée (`assureurNom`) suit la compagnie choisie : le tiroir, l'onglet Grilles et la convention imprimée la lisent.
                  versFiche: (s) => {
                        ..._souscripteurSaisi(s),
                        'assureurNom': assNomAssureur('${s['assureur']}', assureurs),
                      },
                  detailMessage: false)),
      ],
    );
  }

  // --- La fiche d'un souscripteur : sa grille, ses exclusions, ses accords ------------------------------------------------------------

  Widget _bloc(String titre, Object? liste) {
    final l = [for (final x in (liste as List? ?? const [])) '$x'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titre.toUpperCase(),
          style: const TextStyle(
              color: JetonsShell.slate500,
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6)),
      const SizedBox(height: 4),
      if (l.isEmpty)
        const Text('Aucune — tout est couvert dans cette catégorie.',
            style: TextStyle(color: JetonsShell.slate400, fontSize: 12, height: 16 / 12))
      else
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final x in l)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: JetonsShell.slate50,
                    border: Border.all(color: JetonsShell.slate200),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(x,
                    style: const TextStyle(
                        color: JetonsShell.slate600, fontSize: 12, height: 16 / 12))),
        ]),
    ]);
  }

  void _fiche(BuildContext ctx, Fiche s0) {
    afficherTiroir<void>(ctx,
        titre: '${s0['nom']}',
        sousTitre: '${s0['assureurNom']} — ${s0['police']}',
        largeurMax: 768,
        corps: ListenableBuilder(
            listenable: ecoute(c, ['souscripteurs', 'garanties', 'patients']),
            builder: (context, _) {
              final s = c.magasin.collection('souscripteurs').parId(s0['id']) ?? s0;
              final g = _garantiesDe(s['id']);
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DescListeSigh([
                      ('Compagnie', s['assureurNom']),
                      ('N° de police', s['police']),
                      ('Catégorie', s['categorie']),
                      (
                        'Bénéficiaires déclarés',
                        s['effectif'] != null ? nombre(s['effectif']) : '—'
                      ),
                      ('Assurés rattachés', nombre(_assuresDe(s['id']).length)),
                      ('Interlocuteur', s['contact'] == null || s['contact'] == '' ? '—' : s['contact']),
                      (
                        'Validité',
                        '${dateDe(s['dateDebut'])}${s['dateFin'] != null && '${s['dateFin']}'.isNotEmpty ? ' → ${dateDe(s['dateFin'])}' : ' → en cours'}'
                      ),
                    ]),
                    const SizedBox(height: 16),
                    CarteSigh(
                        titre: 'Grille de garanties',
                        child: g.isNotEmpty
                            ? MiniTableauSigh(colonnes: [
                                ColonneMini('Garantie', (x) => '${x['libelle']}'),
                                ColonneMini('Catégorie',
                                    (x) => assLibelleCategorie(x['categorie'])),
                                ColonneMini('Taux', (x) => '${x['taux']} %', droite: true),
                                ColonneMini(
                                    'Plafond',
                                    (x) => x['plafond'] == null
                                        ? '—'
                                        : '${m(x['plafond'])} ${assLibelleUnite(x['unitePlafond'])}',
                                    droite: true),
                                ColonneMini('Depuis', (x) => depuisLe(x)),
                              ], lignes: g)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                    const VideSigh(
                                        'Convention non saisie — les assurés de ce souscripteur sont facturés intégralement.',
                                        icone: LucideIcons.fileQuestion),
                                    if (c.droit.editer)
                                      Center(
                                          child: BoutonSigh(
                                              libelle:
                                                  'Saisir la grille depuis le barème de référence',
                                              icone: LucideIcons.filePlus,
                                              onPressed: () =>
                                                  _proposerBareme(context, s))),
                                  ])),
                    const SizedBox(height: 16),
                    CarteSigh(
                        titre: 'Exclusions et accords préalables',
                        actions: [
                          if (c.droit.editer)
                            BoutonSigh(
                                libelle: 'Modifier',
                                icone: LucideIcons.pencil,
                                taille: TailleBouton.sm,
                                variante: VarianteBouton.secondaire,
                                onPressed: () => _editerExclusions(context, s)),
                        ],
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _bloc('Actes exclus', s['actesExclus']),
                              const SizedBox(height: 12),
                              _bloc('Produits exclus', s['produitsExclus']),
                              const SizedBox(height: 12),
                              _bloc('Soumis à accord préalable', s['accordPrealable']),
                            ])),
                  ]);
            }),
        pied: (fermer) => [
              if (c.droit.editer)
                BoutonSigh(
                    libelle: 'Nouvelle version de la grille',
                    icone: LucideIcons.percent,
                    variante: VarianteBouton.secondaire,
                    onPressed: () {
                      final s = c.magasin.collection('souscripteurs').parId(s0['id']) ?? s0;
                      _editerGrille(ctx, s);
                    }),
              BoutonSigh(
                  libelle: 'Imprimer la convention',
                  icone: LucideIcons.printer,
                  onPressed: () => _imprimer(ctx, s0)),
            ]);
  }

  // --- Saisie de la grille : le barème versé au dossier sert de MODÈLE (on le propose, on ne l'impose pas) -------------------------------

  List<ChampDef> _champsGrille(List<Object> libelles) => [
        for (var i = 0; i < libelles.length; i++) ...[
          ChampDef(
              nom: 'taux_$i',
              libelle: '${libelles[i]} — taux (%)',
              type: TypeChamp.nombre),
          ChampDef(
              nom: 'plafond_$i',
              libelle: 'Plafond (FCFA)',
              type: TypeChamp.nombre),
        ]
      ];

  void _proposerBareme(BuildContext ctx, Fiche s) {
    final g = AssBareme.garanties;
    final ctl = ControleurFormulaire(_champsGrille([for (final x in g) x['libelle']!]), {
      for (var i = 0; i < g.length; i++) ...{
        'taux_$i': '${g[i]['taux']}',
        'plafond_$i': g[i]['plafond'] == null ? '' : '${g[i]['plafond']}',
      }
    });
    afficherModale<void>(ctx,
        titre: 'Saisir la grille de ${s['nom']}',
        taille: TailleModale.xl,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoteSigh(
              'Barème proposé d’après ${AssBareme.reference} (${AssBareme.lieu}, ${dateDe(AssBareme.date)}). Ce document est celui d’un régime employeur : il donne la structure, pas les taux de cette convention. Ajuster avant d’enregistrer.',
              ton: TonSigh.attention,
              icone: LucideIcons.circleHelp),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer la convention',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final lignes = assGarantiesDepuisBareme(s,
                        taux: [for (var i = 0; i < g.length; i++) v['taux_$i']],
                        plafonds: [for (var i = 0; i < g.length; i++) v['plafond_$i']]);
                    final cg = c.magasin.collection('garanties');
                    // Chaque ligne est la VERSION 1 de sa série, « depuis l'ouverture » : aucune date n'est inventée (T13).
                    final posees = <Fiche>[];
                    for (final l in lignes) {
                      final r = poserGarantie(c, {...l, 'sansDate': true, 'unitePlafond': l['unitePlafond']});
                      if (!r.ok) {
                        ToastsSigh.afficher(ctx, r.motif!, type: TypeToast.erreur, detail: r.geste);
                        return;
                      }
                      // Le barème garde l'unité de chaque ligne même quand la clinique supprime le plafond : la fiche reste celle que la saisie d'un bloc écrivait avant les versions.
                      posees.add({...r.fiche!, 'unitePlafond': l['unitePlafond'], if (l['source'] != null) 'source': l['source']});
                    }
                    for (final f in posees) {
                      cg.inserer(f, prefixe: 'GAR');
                    }
                    c.magasin
                        .collection('souscripteurs')
                        .mettreAJour(s['id'], assConventionSaisie());
                    fermer();
                    ToastsSigh.afficher(ctx, 'Convention de ${s['nom']} enregistrée.',
                        type: TypeToast.succes,
                        detail:
                            '${lignes.length} garanties, exclusions et accords préalables repris.');
                  }),
            ]);
  }

  /// MODIFIER LA GRILLE = POSER UNE NOUVELLE VERSION DATÉE de chaque ligne qui change (T13) : une garantie ne se réécrit jamais, la version remplacée reste écrite et les pièces émises
  /// gardent leur taux. Toutes les lignes sont contrôlées AVANT la première écriture : un refus (date dépassée par une facture, plafond sans unité…) nomme la ligne et n'écrit rien.
  void _editerGrille(BuildContext ctx, Fiche s) {
    final g = _garantiesDe(s['id']);
    if (g.isEmpty) {
      _proposerBareme(ctx, s);
      return;
    }
    final ctl = ControleurFormulaire([
      const ChampDef(
          nom: 'dateEffet',
          libelle: 'Date d’effet de la nouvelle grille',
          type: TypeChamp.date,
          requis: true,
          col: ColChamp.plein,
          aide: 'Les pièces antérieures gardent les taux de leur date. Seules les lignes modifiées reçoivent une nouvelle version.'),
      ..._champsGrille([for (final x in g) x['libelle']!]),
    ], {
      'dateEffet': '',
      for (var i = 0; i < g.length; i++) ...{
        'taux_$i': '${g[i]['taux']}',
        'plafond_$i': g[i]['plafond'] == null ? '' : '${g[i]['plafond']}',
      }
    });
    afficherModale<void>(ctx,
        titre: 'Nouvelle version de la grille de ${s['nom']}',
        taille: TailleModale.xl,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Poser la nouvelle version',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    final aPoser = <Map<String, Object?>>[];
                    for (var i = 0; i < g.length; i++) {
                      final p = '${v['plafond_$i'] ?? ''}'.trim();
                      final taux = num.tryParse('${v['taux_$i']}'.trim()) ?? 0;
                      final plafond = p.isEmpty ? null : (num.tryParse(p) ?? 0);
                      final avant = g[i];
                      if (taux == avant['taux'] && plafond == avant['plafond']) continue;
                      aPoser.add({
                        'souscripteurId': s['id'],
                        'categorie': avant['categorie'],
                        'libelle': avant['libelle'],
                        'taux': taux,
                        'plafond': plafond,
                        'unitePlafond': avant['unitePlafond'],
                        'dateEffet': v['dateEffet'],
                        'source': 'Saisie à l’écran « Conventions & garanties »',
                      });
                    }
                    if (aPoser.isEmpty) {
                      ToastsSigh.afficher(ctx, 'Aucune ligne n’a changé : aucune version n’est posée.', type: TypeToast.info);
                      return;
                    }
                    final posees = <Fiche>[];
                    for (final spec in aPoser) {
                      final r = poserGarantie(c, spec, essai: true);
                      if (!r.ok) {
                        ToastsSigh.afficher(ctx, '« ${spec['libelle']} » : ${r.motif}', type: TypeToast.erreur, detail: '${r.geste} Rien n’a été écrit.');
                        return;
                      }
                    }
                    final cg = c.magasin.collection('garanties');
                    for (final spec in aPoser) {
                      final r = poserGarantie(c, spec);
                      posees.add(cg.inserer(r.fiche!, prefixe: 'GAR').fiche);
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Nouvelle grille posée.',
                        type: TypeToast.succes, detail: '${posees.length} version(s) à partir du ${dateDe(v['dateEffet'])} ; les versions précédentes restent écrites.');
                  }),
            ]);
  }

  void _editerExclusions(BuildContext ctx, Fiche s) {
    final actes = [
      ...AssBareme.actesExclus,
      for (final a in TarifsPoste.actes(c.magasin, aujourdhui: c.aujourdhui)) '${a['libelle']}'
    ];
    List<String> liste(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];
    final ctl = ControleurFormulaire([
      ChampDef(
          nom: 'actesExclus',
          libelle: 'Actes exclus',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          options: [for (final x in {...actes}) OptionChamp(x)]),
      ChampDef(
          nom: 'produitsExclus',
          libelle: 'Produits exclus',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          options: [for (final x in AssBareme.produitsExclus) OptionChamp(x)]),
      ChampDef(
          nom: 'accordPrealable',
          libelle: 'Soumis à accord préalable',
          type: TypeChamp.multiselect,
          col: ColChamp.plein,
          options: [for (final x in AssBareme.accordPrealable) OptionChamp(x)]),
    ], {
      'actesExclus': liste(s['actesExclus']),
      'produitsExclus': liste(s['produitsExclus']),
      'accordPrealable': liste(s['accordPrealable']),
    });
    afficherModale<void>(ctx,
        titre: 'Exclusions et accords — ${s['nom']}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh(
              'Une ligne exclue est facturée intégralement au patient, avec son motif. Un acte soumis à accord préalable l’est aussi tant que l’accord n’est pas obtenu.'),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final v = ctl.valider();
                    if (v == null) return;
                    c.magasin.collection('souscripteurs').mettreAJour(s['id'], {
                      'actesExclus': liste(v['actesExclus']),
                      'produitsExclus': liste(v['produitsExclus']),
                      'accordPrealable': liste(v['accordPrealable']),
                    });
                    fermer();
                    ToastsSigh.afficher(ctx, 'Exclusions et accords enregistrés.',
                        type: TypeToast.succes);
                  }),
            ]);
  }

  void _imprimer(BuildContext ctx, Fiche s0) {
    final s = c.magasin.collection('souscripteurs').parId(s0['id']) ?? s0;
    final g = _garantiesDe(s['id']);
    afficherApercu(
        ctx,
        pieceM9(c,
            titre: 'Convention de prise en charge',
            sousTitre: '${s['nom']} — ${s['assureurNom']}',
            cartouche: [
              ('Compagnie', '${s['assureurNom']}'),
              ('N° de police', '${s['police']}'),
              ('Catégorie', '${s['categorie']}'),
              ('Assurés rattachés', nombre(_assuresDe(s['id']).length)),
              (
                'Validité',
                '${dateDe(s['dateDebut'])}${s['dateFin'] != null && '${s['dateFin']}'.isNotEmpty ? ' → ${dateDe(s['dateFin'])}' : ' → en cours'}'
              ),
              ('Date d’édition', dateFR(c.aujourdhui)),
            ],
            tableaux: g.isEmpty
                ? const []
                : [
                    TableauEtat(colonnes: [
                      ColonneEtat(libelle: 'Garantie', valeur: (x) => x['libelle']),
                      ColonneEtat(
                          libelle: 'Catégorie',
                          valeur: (x) => assLibelleCategorie(x['categorie'])),
                      ColonneEtat(
                          libelle: 'Taux', droite: true, valeur: (x) => '${x['taux']} %'),
                      ColonneEtat(
                          libelle: 'Plafond',
                          droite: true,
                          valeur: (x) => x['plafond'] == null ? '—' : m(x['plafond'])),
                      ColonneEtat(
                          libelle: 'Unité',
                          valeur: (x) => x['plafond'] == null
                              ? '—'
                              : assLibelleUnite(x['unitePlafond'])),
                    ], lignes: g)
                  ],
            signatures: [
              const Signature('Pour la clinique', nom: 'La Directrice Administrative'),
              Signature('Pour le souscripteur', nom: '${s['contact'] ?? ''}'),
            ]));
  }
}

// --- Simulateur de répartition ---------------------------------------------------------------------------------------------------

/// Le simulateur applique la CONVENTION RÉELLE de l'assuré choisi, ligne par ligne, avec ses taux, ses plafonds, ses exclusions et la validité de
/// sa carte (`repartir`, RG-09) : c'est exactement le calcul que la facturation appliquera.
class _Simulateur extends StatefulWidget {
  const _Simulateur({required this.c});
  final ContexteEcran c;

  @override
  State<_Simulateur> createState() => _EtatSimulateur();
}

class _EtatSimulateur extends State<_Simulateur> {
  late final ControleurFormulaire _patient;
  late final ControleurFormulaire _montants;
  late final List<Fiche> _assures;

  @override
  void initState() {
    super.initState();
    final c = widget.c;
    _assures = trierPar<Fiche>(assAssures(actives(c, 'patients')), (p) => p['nom']);
    _patient = ControleurFormulaire([
      ChampDef(
          nom: 'assure',
          libelle: 'Assuré',
          type: TypeChamp.select,
          col: ColChamp.plein,
          indicatif: '— Assuré —',
          options: [
            for (final p in _assures)
              OptionChamp('${p['id']}', '${p['nom']} ${p['prenom']}')
          ]),
      const ChampDef(
          nom: 'date',
          libelle: 'Date de la pièce',
          type: TypeChamp.date,
          col: ColChamp.plein,
          aide: 'La grille et la couverture se lisent À CETTE DATE (RG-09) : une version de garantie datée après elle ne compte pas.')
    ], {
      'assure': _assures.isEmpty ? '' : '${_assures.first['id']}',
      'date': iso(c.aujourdhui),
    });
    _montants = ControleurFormulaire([
      for (var i = 0; i < assLignesSimulateur.length; i++)
        ChampDef(
            nom: 'm$i',
            libelle: '${assLignesSimulateur[i]['libelle']} (FCFA)',
            type: TypeChamp.nombre)
    ], {
      for (var i = 0; i < assLignesSimulateur.length; i++)
        'm$i': '${assLignesSimulateur[i]['montant']}'
    });
    _patient.addListener(_maj);
    _montants.addListener(_maj);
  }

  void _maj() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _patient.dispose();
    _montants.dispose();
    super.dispose();
  }

  Widget _bloc(String libelle, String valeur, Color couleur) => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(libelle,
                style: const TextStyle(
                    color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
            Text(valeur,
                style: TextStyle(
                    color: couleur,
                    fontSize: 16,
                    height: 24 / 16,
                    fontWeight: FontWeight.w600)),
          ]);

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final p = _assures.where((x) => '${x['id']}' == '${_patient['assure']}').firstOrNull;
    Widget resultat = const SizedBox();
    if (p != null) {
      final lignes = [
        for (var i = 0; i < assLignesSimulateur.length; i++)
          {
            'libelle': assLignesSimulateur[i]['libelle'],
            'categorie': assLignesSimulateur[i]['categorie'],
            'montant': num.tryParse('${_montants['m$i']}'.trim()) ?? 0,
          }
      ];
      final r = repartir(
          patient: p,
          lignes: lignes,
          date: '${_patient['date']}'.isEmpty ? iso(c.aujourdhui) : '${_patient['date']}',
          couvertures: actives(c, 'couverturesAssurance'),
          souscripteurs: actives(c, 'souscripteurs'),
          garanties: actives(c, 'garanties'));
      final sous = actives(c, 'souscripteurs')
          .where((s) => s['id'] == r.souscripteurId)
          .firstOrNull;
      resultat = CarteSigh(
          titre: 'Répartition ligne par ligne',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DescListeSigh([
              ('Assuré', '${p['nom']} ${p['prenom']} (${p['code']})'),
              ('Compagnie', p['assureurNom'] ?? '—'),
              (
                'Souscripteur',
                sous != null ? '${sous['nom']} — ${sous['police']}' : 'non rattaché'
              ),
              (
                'Carte',
                r.carteValide
                    ? 'valide jusqu’au ${dateDe(p['carteExpiration'])}'
                    : 'NON VALIDE — expirée le ${dateDe(p['carteExpiration'])}'
              ),
              ('Convention', r.grilleSaisie ? 'saisie' : 'à collecter'),
            ]),
            const SizedBox(height: 12),
            MiniTableauSigh(colonnes: [
              ColonneMini('Prestation', (l) => '${l['libelle']}'),
              ColonneMini('Montant', (l) => m(l['montant']), droite: true),
              ColonneMini('Part assureur', (l) => m(l['partAssureur']), droite: true),
              ColonneMini('Part patient', (l) => m(l['partPatient']), droite: true),
              ColonneMini('Motif', (l) => '${l['motif']}',
                  rendu: (l) => Text('${l['motif']}',
                      style: TextStyle(
                          color: n(l['partAssureur']) > 0
                              ? JetonsShell.slate500
                              : JetonsShell.warning700,
                          fontSize: 12,
                          height: 16 / 12))),
            ], lignes: r.lignes),
            const SizedBox(height: 12),
            const Divider(height: 1, color: JetonsShell.slate200),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.end, spacing: 24, children: [
              _bloc('Total', money(r.total), JetonsShell.slate800),
              _bloc('Part assureur', money(r.partAssureur), JetonsShell.info600),
              _bloc('Part patient', money(r.partPatient), JetonsShell.navy900),
            ]),
          ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh(
          'Le simulateur applique la convention réelle de l’assuré choisi, ligne par ligne, avec ses taux, ses plafonds, ses exclusions et la validité de sa carte. C’est exactement le calcul que la facturation appliquera.'),
      const SizedBox(height: 16),
      CarteSigh(titre: 'Assuré', child: FormulaireSigh(controleur: _patient)),
      const SizedBox(height: 16),
      CarteSigh(
          titre: 'Lignes à simuler', child: FormulaireSigh(controleur: _montants)),
      const SizedBox(height: 16),
      resultat,
    ]);
  }
}
