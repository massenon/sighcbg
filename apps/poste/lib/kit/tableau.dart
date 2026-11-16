import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../core/jetons_shell.dart';
import '../impression/piece.dart';
import '../shell/contexte_ecran.dart';
import 'bouton.dart';
import 'carte.dart';
import 'export_tableau.dart';
import 'formulaire.dart';
import 'modale.dart';

typedef Ligne = Map<String, Object?>;

class ColonneTableau {
  const ColonneTableau(
      {required this.cle,
      required this.libelle,
      this.droite = false,
      this.triable = true,
      this.valeur,
      this.rendu,
      this.sansCoupure = false,
      this.texte,
      this.valeurExport});
  final String cle;
  final String libelle;
  final bool droite;
  final bool triable;
  final Object? Function(Ligne)? valeur;
  final Widget Function(BuildContext, Ligne)? rendu;
  final bool sansCoupure;

  /// Texte exporté / recherché quand la cellule est un widget.
  final String Function(Ligne)? texte;

  /// La VALEUR que l'export écrit (Direction, 16/11/2026, section 7) quand le texte affiché l'arrondit ou la met en forme : un montant (`num`, décimales comprises),
  /// une date (`DateTime` ou chaîne ISO `AAAA-MM-JJ`). Seuls un nombre et une date sont pris ; toute autre valeur est ignorée et la cellule part du TEXTE affiché — un texte
  /// masqué sort donc masqué. Ne JAMAIS la déclarer sur une colonne que l'écran masque (numéro, champ sensible) : le texte affiché est alors la seule sortie. Absente :
  /// la cellule part du texte affiché (un « 12 500 F » redevient le nombre 12500, un « 15/11/2026 » une date).
  final Object? Function(Ligne)? valeurExport;

  Object? lire(Ligne l) => valeur != null ? valeur!(l) : l[cle];
  String enTexte(Ligne l) => texte != null ? texte!(l) : '${lire(l) ?? ''}';
}

class FiltreTableau {
  const FiltreTableau(
      {required this.nom,
      required this.libelle,
      required this.options,
      this.correspond});
  final String nom;
  final String libelle;
  final List<OptionChamp> options;
  final bool Function(Ligne, String)? correspond;
}

/// `U.dataTable` : carte `overflow-hidden` → barre d'outils → (barre de sélection) → tableau → pied (compteur + pagination).
/// Comportements repris de la maquette : recherche sans accents sur toutes les colonnes, filtres, tri à deux états,
/// colonnes configurables, export, sélection multiple, pagination de 12, message d'état vide distinct selon qu'un filtre est actif.
///
/// CHANTIER TABLEAUX (Q38 à Q42, Direction du 15/11/2026) : sous une coque d'écran, CHAQUE tableau porte des cases à cocher (une, plusieurs, toutes les lignes de la page ou du
/// filtre), la sélection survit au changement de page jusqu'à ce que l'agent la vide, un compteur la dit, et « Exporter » écrit un classeur .xlsx ou un CSV de la sélection ou de
/// TOUT le tableau (avec ou sans le filtre). Exporter et imprimer sont DEUX gestes réservés réglables par rôle (16/11/2026), la limite de lignes un réglage de la clinique
/// réglé par son propre geste (refus nommé) ; export et impression sont journalisés (RG-12 : identifiants des fiches et nombre, jamais le contenu). « Imprimer la sélection »
/// reprend le gabarit d'impression : un seul tableau, ou une pièce complète par ligne (chacune sur sa page) quand [documentLigne] existe.
class TableauSigh extends StatefulWidget {
  const TableauSigh({
    super.key,
    required this.colonnes,
    required this.lignes,
    this.titre,
    this.taillePage = 12,
    this.recherche = true,
    this.filtres = const [],
    this.selectionnable,
    this.exportable = true,
    this.documentLigne,
    this.imprimerSelectionTableau,
    this.actionsLigne,
    this.colonnesMasquees = const [],
    this.alClicLigne,
    this.messageVide = 'Aucun enregistrement.',
    this.indiceVide,
    this.triInitial,
    this.sensInitial = 'asc',
    this.nomExport = 'export',
    this.alExporter,
    this.actions = const [],
    this.actionsGroupe,
    this.libelleRecherche = 'Rechercher…',
    this.rechercheExtra,
  });

  /// Un texte cherchable EN PLUS des colonnes, jamais affiché ni exporté (le texte extrait d'un PDF, par exemple) : la recherche le lit, rien d'autre.
  final String Function(Ligne)? rechercheExtra;

  final List<ColonneTableau> colonnes;
  final List<Ligne> lignes;
  final String? titre;
  final int taillePage;
  final bool recherche;
  final List<FiltreTableau> filtres;

  /// Les cases à cocher. `null` (défaut) : présentes sous une coque d'écran dont le profil peut exporter OU imprimer depuis un tableau (deux gestes réservés distincts ;
  /// rien à cocher pour qui n'a ni l'un ni l'autre) ; `true` : toujours (un écran qui agit en groupe) ; `false` : jamais (un petit tableau de détail où cocher n'aurait pas
  /// d'objet, une grille de saisie en cours).
  final bool? selectionnable;

  /// Faux : ni « Exporter » ni impression de la sélection (une grille de SAISIE en cours ou un tableau de DOCUMENT : Direction du 16/11/2026, section 7 ; liste avec motifs
  /// dans `docs/architecture/EXPORT-exclusions.md`). Les cases tombent avec, sauf `selectionnable: true` explicite.
  final bool exportable;

  /// La PIÈCE COMPLÈTE d'une ligne (une facture, un bon, une ordonnance, un certificat) quand elle existe déjà : « Imprimer la sélection » propose alors une pièce par ligne,
  /// chacune sur sa page, identique à celle qu'imprime la ligne seule.
  final PieceA4 Function(BuildContext, Ligne)? documentLigne;

  /// Le tableau unique PROPRE à l'écran pour « Imprimer la sélection » (sa pièce, ses colonnes) : appelé par le kit après le geste réservé et le journal. Sans lui, le
  /// tableau générique des colonnes affichées. Jamais un second bouton « Imprimer la sélection » dans [actionsGroupe].
  final void Function(BuildContext, List<Ligne>)? imprimerSelectionTableau;
  final List<Widget> Function(BuildContext, Ligne)? actionsLigne;

  /// Colonnes (par `cle`) masquées à l'ouverture, remises par le menu « Colonnes » : sur un tableau de douze colonnes, les commandes de ligne sortaient du cadre.
  final List<String> colonnesMasquees;
  final void Function(Ligne)? alClicLigne;
  final String messageVide;
  final String? indiceVide;
  final String? triInitial;
  final String sensInitial;
  final String nomExport;
  final String libelleRecherche;

  /// Reçoit `(nomDeFichier, contenuCsv)` : l'écriture du fichier appartient à la plateforme, pas au kit.
  final void Function(String nom, String csv)? alExporter;
  final List<Widget> actions;

  /// Commandes de la barre de sélection (`bulkActions`) : reçoivent les lignes sélectionnées et la fonction qui désélectionne.
  final List<Widget> Function(
      BuildContext, List<Ligne> selection, VoidCallback effacer)? actionsGroupe;

  @override
  State<TableauSigh> createState() => TableauSighState();
}

class TableauSighState extends State<TableauSigh> {
  String _q = '';
  final Map<String, String> _filtres = {};
  String? _tri;
  String _sens = 'asc';
  int _page = 1;
  late final Set<String> _caches = {...widget.colonnesMasquees};
  final SelectionLignes _selection = SelectionLignes();

  /// L'identité des lignes sans `id` : leur rang dans la liste reçue (la liste d'un écran reste la même d'un affichage à l'autre).
  final Map<Ligne, String> _sansId = Map<Ligne, String>.identity();

  String _cle(Ligne r) {
    final id = r['id'];
    return id != null ? '$id' : (_sansId[r] ?? '#');
  }

  void _indexer() {
    _sansId.clear();
    for (var i = 0; i < widget.lignes.length; i++) {
      if (widget.lignes[i]['id'] == null) _sansId[widget.lignes[i]] = '#$i';
    }
  }

  List<Ligne> _trier(List<Ligne> l) {
    if (_tri == null) return l;
    final c = widget.colonnes.where((c) => c.cle == _tri).firstOrNull;
    return c == null ? l : trierPar(l, c.lire, descendant: _sens == 'desc');
  }

  /// Les lignes cochées, TOUTES pages et tout filtre confondus (une ligne cochée puis masquée par un filtre reste cochée), dans l'ordre de tri en cours.
  List<Ligne> get lignesSelectionnees => _trier([
        for (final r in widget.lignes)
          if (_selection.contient(_cle(r))) r
      ]);

  /// Tout le tableau, sans la recherche ni les filtres, dans l'ordre de tri en cours.
  List<Ligne> get _toutesLesLignes => _trier([...widget.lignes]);

  /// Le profil peut-il exporter ? imprimer depuis le tableau ? Deux gestes réservés DISTINCTS (Direction, 16/11/2026). Hors coque (test de widget nu) : l'export reste offert
  /// comme avant, mais sans cases à cocher par défaut. Un tableau non [TableauSigh.exportable] n'offre ni l'un ni l'autre.
  bool _droitExport(BuildContext context) => widget.exportable && peutExporterTableau(ContexteEcran.maybeOf(context));
  bool _droitImpression(BuildContext context) => widget.exportable && peutImprimerTableau(ContexteEcran.maybeOf(context));
  bool _cases(BuildContext context) =>
      widget.selectionnable ?? (ContexteEcran.maybeOf(context) != null && (_droitExport(context) || _droitImpression(context)));

  @override
  void initState() {
    super.initState();
    _tri = widget.triInitial;
    _sens = widget.sensInitial;
  }

  List<ColonneTableau> get _visibles =>
      widget.colonnes.where((c) => !_caches.contains(c.cle)).toList();

  /// Lignes après recherche, filtres et tri — c'est CE que l'état imprime et que l'export écrit.
  List<Ligne> get lignesFiltrees {
    var l = [...widget.lignes];
    if (_q.isNotEmpty)
      l = l
          .where(
              (r) => widget.colonnes.any((c) => correspond(c.enTexte(r), _q)) || (widget.rechercheExtra != null && correspond(widget.rechercheExtra!(r), _q)))
          .toList();
    for (final e in _filtres.entries) {
      if (e.value.isEmpty) continue;
      final f = widget.filtres.firstWhere((x) => x.nom == e.key);
      l = l
          .where((r) => f.correspond != null
              ? f.correspond!(r, e.value)
              : '${r[e.key]}' == e.value)
          .toList();
    }
    return _trier(l);
  }

  /// Les filtres EN FORCE de la barre : (libellé, valeur lisible), pour que la pièce imprimée dise ce qui l'a bornée.
  List<(String, String)> get _filtresEnForce => [
        if (_q.isNotEmpty) ('Recherche', _q),
        for (final f in widget.filtres)
          if ((_filtres[f.nom] ?? '').isNotEmpty) (f.libelle, f.options.where((o) => o.valeur == _filtres[f.nom]).firstOrNull?.libelle ?? '${_filtres[f.nom]}'),
      ];

  SourceExport _sourceExport() {
    final selection = lignesSelectionnees;
    return SourceExport(
        nom: widget.nomExport,
        titre: widget.titre,
        colonnes: () => _visibles,
        lignes: (p) => switch (p) {
              PorteeExport.selection => selection,
              PorteeExport.toutAvecFiltre => lignesFiltrees,
              PorteeExport.toutSansFiltre => _toutesLesLignes,
            },
        nbSelection: selection.length,
        nbFiltre: lignesFiltrees.length,
        nbTout: widget.lignes.length,
        filtreActif: _filtreActif,
        alCsv: widget.alExporter);
  }

  void _exporter({PorteeExport? portee}) {
    _indexer();
    ouvrirExport(context, _sourceExport(), porteeInitiale: portee);
  }

  void _imprimerSelection() {
    _indexer();
    ouvrirImpressionSelection(
        context,
        SourceImpression(
            titre: widget.titre ?? 'Lignes sélectionnées',
            colonnes: () => _visibles,
            lignes: lignesSelectionnees,
            filtres: _filtresEnForce,
            filtreActif: _filtreActif,
            documentLigne: widget.documentLigne,
            imprimerTableau: widget.imprimerSelectionTableau));
  }

  void _colonnes() {
    afficherModale<void>(context,
        titre: 'Colonnes affichées',
        taille: TailleModale.sm,
        corps: StatefulBuilder(
            builder: (_, maj) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final c in widget.colonnes)
                    InkWell(
                      onTap: () {
                        setState(() => _caches.contains(c.cle)
                            ? _caches.remove(c.cle)
                            : _caches.add(c.cle));
                        maj(() {});
                      },
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                    color: _caches.contains(c.cle)
                                        ? Colors.white
                                        : JetonsShell.navy900,
                                    border: Border.all(
                                        color: _caches.contains(c.cle)
                                            ? JetonsShell.slate300
                                            : JetonsShell.navy900),
                                    borderRadius: BorderRadius.circular(4)),
                                child: _caches.contains(c.cle)
                                    ? null
                                    : const Icon(LucideIcons.check,
                                        size: 12, color: Colors.white)),
                            const SizedBox(width: 8),
                            Text(c.libelle,
                                style: const TextStyle(
                                    color: JetonsShell.slate700,
                                    fontSize: 14,
                                    height: 20 / 14)),
                          ])),
                    ),
                ])),
        pied: (fermer) => [BoutonSigh(libelle: 'Fermer', onPressed: fermer)]);
  }

  bool get _filtreActif =>
      _q.isNotEmpty || _filtres.values.any((v) => v.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final toutes = lignesFiltrees;
    final pages = (toutes.length / widget.taillePage).ceil().clamp(1, 1 << 30);
    if (_page > pages) _page = pages;
    final debut = (_page - 1) * widget.taillePage;
    final page = toutes.skip(debut).take(widget.taillePage).toList();
    final cols = _visibles;
    _indexer();
    final cases = _cases(context);
    // Une fiche archivée ou retirée de la liste sort de la sélection : le compteur ne compte que ce qui existe encore au tableau.
    if (!_selection.vide) _selection.retenir({for (final r in widget.lignes) _cle(r)});

    return Container(
      key: const Key('kit:tableau'),
      decoration: decorationCarte(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _barre(),
              if (!_selection.vide) _barreSelection(toutes),
              if (toutes.isEmpty)
                VideSigh(
                    _filtreActif
                        ? 'Aucun résultat pour cette recherche.'
                        : widget.messageVide,
                    indice: widget.indiceVide)
              else
                _table(cols, page, cases),
              _pied(toutes.length, debut, pages),
            ]),
      ),
    );
  }

  Widget _barre() => Container(
        key: const Key('kit:tableau-barre'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: JetonsShell.slate200))),
        child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.titre != null)
                Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(widget.titre!,
                        style: const TextStyle(
                            color: JetonsShell.slate900,
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: FontWeight.w600))),
              if (widget.recherche)
                ConstrainedBox(
                  constraints: BoxConstraints(
                      minWidth: 224,
                      maxWidth: widget.titre != null ? 320 : 480),
                  child: SizedBox(
                    width: 320,
                    child: Semantics(
                      textField: true,
                      label: 'Rechercher',
                      child: TextField(
                        key: const Key('kit:tableau-recherche'),
                        style: styleSaisie,
                        decoration: decorationChamp(
                            indicatif: widget.libelleRecherche,
                            prefixe: const Padding(
                                padding: EdgeInsets.only(left: 10, right: 6),
                                child: Icon(LucideIcons.search,
                                    size: 16, color: JetonsShell.slate400))),
                        onChanged: (v) => setState(() {
                          _q = v;
                          _page = 1;
                        }),
                      ),
                    ),
                  ),
                ),
              for (final f in widget.filtres)
                _FiltreListe(
                    f,
                    _filtres[f.nom] ?? '',
                    (v) => setState(() {
                          _filtres[f.nom] = v;
                          _page = 1;
                        })),
              BoutonSigh(
                  libelle: 'Colonnes',
                  icone: LucideIcons.columns3,
                  taille: TailleBouton.sm,
                  variante: VarianteBouton.secondaire,
                  onPressed: _colonnes),
              // Le droit d'exporter est un geste réservé : refusé, la commande est ABSENTE (un bouton grisé inviterait à chercher pourquoi).
              if (_droitExport(context))
                BoutonSigh(
                    libelle: 'Exporter',
                    icone: LucideIcons.download,
                    taille: TailleBouton.sm,
                    variante: VarianteBouton.secondaire,
                    onPressed: _exporter),
              ...widget.actions,
            ]),
      );

  Widget _barreSelection(List<Ligne> filtrees) {
    final n = _selection.taille;
    final dansFiltre = filtrees.where((r) => _selection.contient(_cle(r))).length;
    final masquees = n - dansFiltre;
    final peutExporter = _droitExport(context);
    final peutImprimer = _droitImpression(context);
    return Container(
      key: const Key('kit:tableau-selection'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(color: JetonsShell.navy50, border: Border(bottom: BorderSide(color: JetonsShell.navy200))),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(
            '$n ligne${n > 1 ? 's' : ''} sélectionnée${n > 1 ? 's' : ''}'
            '${masquees > 0 ? ' (dont $masquees hors du filtre)' : ''}',
            key: const Key('kit:tableau-compteur'),
            style: const TextStyle(color: JetonsShell.navy900, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500)),
        // Cocher TOUTES les lignes du filtre, au-delà de la page : la case de l'en-tête ne coche que la page.
        if (filtrees.length > dansFiltre)
          BoutonSigh(
              key: const Key('kit:tableau-tout-cocher'),
              libelle: 'Tout cocher (${filtrees.length})',
              variante: VarianteBouton.fantome,
              taille: TailleBouton.sm,
              onPressed: () => setState(() => _selection.definir([for (final r in filtrees) _cle(r)], true))),
        if (peutExporter)
          BoutonSigh(
              key: const Key('kit:tableau-exporter-selection'),
              libelle: 'Exporter la sélection',
              icone: LucideIcons.download,
              variante: VarianteBouton.secondaire,
              taille: TailleBouton.sm,
              onPressed: () => _exporter(portee: PorteeExport.selection)),
        if (peutImprimer)
          BoutonSigh(
              key: const Key('kit:tableau-imprimer-selection'),
              libelle: 'Imprimer la sélection',
              icone: LucideIcons.printer,
              variante: VarianteBouton.secondaire,
              taille: TailleBouton.sm,
              onPressed: _imprimerSelection),
        if (widget.actionsGroupe != null)
          for (final a in widget.actionsGroupe!(context, [for (final r in filtrees) if (_selection.contient(_cle(r))) r], () => setState(_selection.vider))) a,
        BoutonSigh(
            libelle: 'Tout désélectionner',
            variante: VarianteBouton.fantome,
            taille: TailleBouton.sm,
            onPressed: () => setState(_selection.vider)),
      ]),
    );
  }

  Widget _table(List<ColonneTableau> cols, List<Ligne> page, bool cases) {
    final colonnes = <int, TableColumnWidth>{};
    var i = 0;
    if (cases) colonnes[i++] = const FixedColumnWidth(40);
    for (var k = 0; k < cols.length; k++) {
      colonnes[i++] = const IntrinsicColumnWidth(flex: 1);
    }
    if (widget.actionsLigne != null)
      colonnes[i++] = const IntrinsicColumnWidth();
    return LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                // Largeur imposée : comme une table CSS, les colonnes se resserrent (retour à la ligne) avant que la table ne déborde.
                constraints:
                    BoxConstraints(minWidth: c.maxWidth, maxWidth: c.maxWidth),
                child: Table(
                  key: const Key('kit:tableau-table'),
                  columnWidths: colonnes,
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                        key: const ValueKey('kit:tableau-entete'),
                        decoration: const BoxDecoration(
                            color: JetonsShell.slate50,
                            border: Border(
                                bottom:
                                    BorderSide(color: JetonsShell.slate200))),
                        children: [
                          if (cases)
                            _cellule(
                                Center(
                                    child: _Cocher(
                                        page.isNotEmpty &&
                                            _selection.toutesCochees([for (final r in page) _cle(r)]),
                                        'Tout sélectionner',
                                        (v) => setState(() => _selection.definir([for (final r in page) _cle(r)], v)))),
                                tete: true),
                          for (final (i, col) in cols.indexed)
                            _tete(col,
                                cle: i == 0 && widget.selectionnable != true
                                    ? const Key('kit:tableau-entete')
                                    : null),
                          if (widget.actionsLigne != null)
                            _cellule(
                                const Align(
                                    alignment: Alignment.centerRight,
                                    child: Text('ACTIONS', style: _styleTete)),
                                tete: true),
                        ]),
                    for (final r in page)
                      TableRow(
                          decoration: BoxDecoration(
                              color: _selection.contient(_cle(r))
                                  ? JetonsShell.navy50
                                  : null,
                              border: const Border(
                                  bottom:
                                      BorderSide(color: JetonsShell.slate100))),
                          children: [
                            if (cases)
                              _cellule(Center(
                                  child: _Cocher(
                                      _selection.contient(_cle(r)),
                                      'Sélectionner la ligne',
                                      (v) => setState(() => v ? _selection.cocher(_cle(r)) : _selection.decocher(_cle(r)))))),
                            for (final (i, col) in cols.indexed)
                              _cellule(
                                  cle: i == 0 &&
                                          widget.selectionnable != true &&
                                          widget.actionsLigne == null &&
                                          identical(r, page.first)
                                      ? const Key('kit:tableau-ligne')
                                      : null,
                                  InkWell(
                                      onTap: widget.alClicLigne == null
                                          ? null
                                          : () => widget.alClicLigne!(r),
                                      child: Align(
                                          alignment: col.droite
                                              ? Alignment.centerRight
                                              : Alignment.centerLeft,
                                          child: col.rendu != null
                                              ? col.rendu!(context, r)
                                              : Text(
                                                  col.enTexte(r).isEmpty
                                                      ? '—'
                                                      : col.enTexte(r),
                                                  softWrap: !col.sansCoupure,
                                                  style: TextStyle(
                                                      color:
                                                          JetonsShell.slate700,
                                                      fontSize: 14,
                                                      height: 20 / 14,
                                                      fontFeatures: col.droite
                                                          ? const [
                                                              FontFeature
                                                                  .tabularFigures()
                                                            ]
                                                          : null))))),
                            if (widget.actionsLigne != null)
                              _cellule(
                                  cle: identical(r, page.first)
                                      ? const Key('kit:tableau-ligne')
                                      : null,
                                  // Wrap et non Row : quand la colonne des cases à cocher resserre la table, les commandes reviennent à la ligne au lieu de déborder.
                                  Wrap(
                                      alignment: WrapAlignment.end,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      runSpacing: 4,
                                      children: [
                                        for (final a
                                            in widget.actionsLigne!(context, r))
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 4),
                                              child: a),
                                      ])),
                          ]),
                  ],
                ),
              ),
            ));
  }

  static const _styleTete = TextStyle(
      color: JetonsShell.slate500,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6);

  /// Cellule : px 12, py 10 (`px-3 py-2.5`).
  Widget _cellule(Widget w, {bool tete = false, Key? cle}) => TableCell(
      child: Padding(
          key: cle,
          // py 10 + le filet de 1 px de `border-b` (CSS l'ajoute à la hauteur de la ligne, Flutter non).
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          child: w));

  Widget _tete(ColonneTableau col, {Key? cle}) {
    final actif = _tri == col.cle;
    return _cellule(
        Semantics(
          sortKey: null,
          label: col.libelle +
              (actif
                  ? (_sens == 'asc' ? ', tri croissant' : ', tri décroissant')
                  : ''),
          button: col.triable,
          excludeSemantics: true,
          child: InkWell(
            onTap: !col.triable
                ? null
                : () => setState(() {
                      if (_tri == col.cle) {
                        _sens = _sens == 'asc' ? 'desc' : 'asc';
                      } else {
                        _tri = col.cle;
                        _sens = 'asc';
                      }
                    }),
            child: Align(
              alignment:
                  col.droite ? Alignment.centerRight : Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                    child: Text(col.libelle.toUpperCase(), style: _styleTete)),
                if (actif)
                  Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                          _sens == 'asc'
                              ? LucideIcons.chevronUp
                              : LucideIcons.chevronDown,
                          size: 14,
                          color: JetonsShell.slate500)),
              ]),
            ),
          ),
        ),
        tete: true,
        cle: cle);
  }

  Widget _pied(int total, int debut, int pages) => Container(
        key: const Key('kit:tableau-pied'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: JetonsShell.slate200))),
        child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 12,
            spacing: 12,
            children: [
              Text(
                  total == 0
                      ? 'Aucun enregistrement'
                      : 'Affichage de ${debut + 1} à ${(debut + widget.taillePage).clamp(0, total)} sur $total enregistrement${total > 1 ? 's' : ''}',
                  style: const TextStyle(
                      color: JetonsShell.slate500,
                      fontSize: 12,
                      height: 16 / 12)),
              if (pages > 1) _pagination(pages),
            ]),
      );

  Widget _pagination(int pages) {
    var de = (_page - 2).clamp(1, pages);
    final a = (de + 4).clamp(1, pages);
    de = (a - 4).clamp(1, pages);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      BoutonSigh(
          icone: LucideIcons.chevronLeft,
          libelle: 'Page précédente',
          libelleVisible: false,
          taille: TailleBouton.sm,
          variante: VarianteBouton.secondaire,
          onPressed: _page == 1 ? null : () => setState(() => _page--)),
      for (var p = de; p <= a; p++)
        Padding(
            padding: const EdgeInsets.only(left: 4),
            child: BoutonSigh(
                libelle: '$p',
                taille: TailleBouton.sm,
                variante: p == _page
                    ? VarianteBouton.primaire
                    : VarianteBouton.secondaire,
                onPressed: () => setState(() => _page = p))),
      Padding(
          padding: const EdgeInsets.only(left: 4),
          child: BoutonSigh(
              icone: LucideIcons.chevronRight,
              libelle: 'Page suivante',
              libelleVisible: false,
              taille: TailleBouton.sm,
              variante: VarianteBouton.secondaire,
              onPressed:
                  _page == pages ? null : () => setState(() => _page++))),
    ]);
  }
}

class _Cocher extends StatelessWidget {
  const _Cocher(this.coche, this.libelle, this.alChangement);
  final bool coche;
  final String libelle;
  final ValueChanged<bool> alChangement;
  @override
  Widget build(BuildContext context) => Semantics(
        checked: coche,
        label: libelle,
        excludeSemantics: true,
        onTap: () => alChangement(!coche),
        child: InkWell(
          onTap: () => alChangement(!coche),
          child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                  color: coche ? JetonsShell.navy900 : Colors.white,
                  border: Border.all(
                      color:
                          coche ? JetonsShell.navy900 : JetonsShell.slate300),
                  borderRadius: BorderRadius.circular(4)),
              child: coche
                  ? const Icon(LucideIcons.check, size: 12, color: Colors.white)
                  : null),
        ),
      );
}

/// Filtre de la barre : liste déroulante de 9 rem minimum, première entrée = le libellé du filtre (« tous »).
class _FiltreListe extends StatelessWidget {
  const _FiltreListe(this.def, this.valeur, this.alChangement);
  final FiltreTableau def;
  final String valeur;
  final ValueChanged<String> alChangement;

  /// `select.w-auto.min-w-[9rem]` : largeur du contenu le plus large (libellé du filtre ou option), plus le retrait
  /// gauche (12), le chevron et la bordure (34), jamais sous 144 px. Sans largeur propre, le champ prend toute la
  /// largeur offerte par le `Wrap` de la barre et chaque filtre se retrouve seul sur sa ligne.
  double _largeur(BuildContext context) {
    var texte = 0.0;
    for (final t in [def.libelle, for (final o in def.options) o.libelle]) {
      final p = TextPainter(
          text: TextSpan(text: t, style: styleSaisie),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1)
        ..layout();
      if (p.width > texte) texte = p.width;
    }
    return (texte + 12 + 34).clamp(144.0, 320.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final courant = def.options.where((o) => o.valeur == valeur).firstOrNull;
    return Semantics(
      button: true,
      label: '${def.libelle}, ${courant?.libelle ?? 'tous'}',
      excludeSemantics: true,
      child: PopupMenuButton<String>(
        tooltip: def.libelle,
        onSelected: alChangement,
        itemBuilder: (_) => [
          PopupMenuItem(value: '', child: Text(def.libelle)),
          for (final o in def.options)
            PopupMenuItem(value: o.valeur, child: Text(o.libelle)),
        ],
        child: SizedBox(
          width: _largeur(context),
          child: InputDecorator(
            decoration: decorationChamp(
                suffixe: const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(LucideIcons.chevronDown,
                        size: 16, color: JetonsShell.slate400))),
            child: Text(courant?.libelle ?? def.libelle, style: styleSaisie),
          ),
        ),
      ),
    );
  }
}
