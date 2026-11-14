import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../impression/apercu.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'res_commun.dart';

/// `m5-resultats-comparatif` — « Comparatif des résultats » : la mesure COMPARÉE face à ses antériorités (lot A1), la colonne « Antériorités » de la fiche de
/// résultats développée à l'écran. La mesure comparée se choisit (la plus récente par défaut) ; ses antériorités sont les N dernières mesures RENDUES qui la
/// précèdent (N réglé en base, défaut 3), de la plus ancienne à la plus récente, chacune jugée aux bornes de SON époque. La variation se lit à la mesure
/// précédente DE LA VARIABLE (pas forcément la colonne voisine) ; une variable qualitative se compare en texte ; un clic sur un paramètre numérique ouvre sa
/// courbe de tendance. Quand un seuil de variation brutale VALIDÉ est franchi (lot A2), l'écran le SIGNALE — il ne bloque rien.
///
/// Seuls les résultats RENDUS se comparent (comparer une saisie non validée reviendrait à lire par-dessus l'épaule du laboratoire), dans le périmètre du RBAC
/// métier : une antériorité qu'on n'a pas le droit de voir n'entre ni dans une colonne, ni dans la variation, ni dans la courbe, et l'écran le dit.
class EcranComparatifResultats extends StatefulWidget with EcranMaquette {
  const EcranComparatifResultats({super.key, this.fonction, this.secteur, this.agentId});
  final String? fonction;
  final String? secteur;
  final String? agentId;

  @override
  String get titre => 'Comparatif des résultats';

  @override
  String get description =>
      'Une mesure du même examen face à ses dernières antériorités, variable par variable, avec la variation et la courbe de tendance.';

  @override
  String get regle =>
      'La fiche de résultats de la clinique porte une colonne Antériorités : c’est elle que cet écran développe. Seuls les résultats rendus (validés biologiquement) se comparent : comparer une saisie non validée reviendrait à lire par-dessus l’épaule du laboratoire. Le périmètre est celui du RBAC métier : chacun ne compare que ce qu’il a le droit de voir, et l’écran dit ce qu’il ne montre pas.';

  @override
  State<EcranComparatifResultats> createState() => _EtatComparatif();
}

class _EtatComparatif extends State<EcranComparatifResultats> {
  ControleurFormulaire? _patient;
  ControleurFormulaire? _examen;
  ControleurFormulaire? _b;
  String _vuPatient = '', _vuExamen = '';
  String _signatureB = '';
  List<PatientComparable> _patients = const [];

  @override
  void dispose() {
    _patient?.dispose();
    _examen?.dispose();
    _b?.dispose();
    super.dispose();
  }

  /// Les patients comparables ont changé (autre agent, autre jeu) : le sélecteur est reconstruit, la comparaison repart de zéro.
  void _synchroniser(List<PatientComparable> patients) {
    final sig = [for (final p in patients) '${p.id}:${p.mesures.length}'].join('|');
    final avant = [for (final p in _patients) '${p.id}:${p.mesures.length}'].join('|');
    if (_patient != null && sig == avant) return;
    _patients = patients;
    _patient?.dispose();
    _patient = ControleurFormulaire([
      ChampDef(
          nom: 'patient',
          libelle: 'Patient',
          type: TypeChamp.select,
          col: ColChamp.plein,
          indicatif: '— Choisir un patient —',
          options: [for (final p in patients) OptionChamp(p.id, p.libelle)])
    ]);
    _patient!.addListener(_surPatient);
    _vuPatient = '';
    _vuExamen = '';
    _examen?.dispose();
    _examen = null;
    _b = null;
  }

  void _surPatient() {
    final v = '${_patient!['patient'] ?? ''}';
    if (v == _vuPatient) return;
    _vuPatient = v;
    _vuExamen = '';
    _b = null;
    _signatureB = '';
    _examen?.dispose();
    _examen = null;
    if (mounted) setState(() {});
  }

  void _surExamen() {
    final v = '${_examen!['examen'] ?? ''}';
    if (v == _vuExamen) return;
    _vuExamen = v;
    _b = null;
    _signatureB = '';
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final p = profilLabo(c, fonction: widget.fonction, secteur: widget.secteur, agentId: widget.agentId);
    return ListenableBuilder(
      listenable: ecouteLabo(c),
      builder: (context, _) {
        final actives = c.magasin.collection('demandesAnalyses').actives;
        final rows = comparables(actives, p.session);
        final patients = parPatient(rows);
        _synchroniser(patients);
        final examens = examensLabo(c);
        final masques = actives.where((r) => estRendu(r['etatAnalyse'])).length - rows.length;

        // Le sélecteur d'examen naît du patient choisi.
        PatientComparable? choisi;
        for (final x in patients) {
          if (x.id == _vuPatient) choisi = x;
        }
        List<ExamenComparable> exs = const [];
        if (choisi != null) {
          exs = examensDuPatient(choisi.mesures, examens);
          _examen ??= ControleurFormulaire([
            ChampDef(
                nom: 'examen',
                libelle: 'Examen',
                type: TypeChamp.select,
                col: ColChamp.plein,
                indicatif: '— Choisir un examen —',
                options: [for (final e in exs) OptionChamp(e.code, e.libelle)])
          ])
            ..addListener(_surExamen);
        }

        Widget zone;
        ExamenComparable? ex;
        for (final e in exs) {
          if (e.code == _vuExamen) ex = e;
        }
        if (choisi == null) {
          zone = const VideSigh('Choisir un patient pour ouvrir la comparaison.', icone: LucideIcons.gitCompareArrows);
        } else if (_vuExamen.isEmpty || ex == null) {
          zone = VideSigh(_vuExamen.isEmpty ? 'Choisir un examen : ceux qui portent plusieurs mesures se comparent.' : 'Choisir un examen.',
              icone: LucideIcons.gitCompareArrows);
        } else if (ex.mesures.length < 2) {
          zone = const VideSigh(
              'Une seule mesure de cet examen : aucune antériorité à comparer. La colonne « Antériorités » se remplira à la prochaine mesure.',
              icone: LucideIcons.history);
        } else {
          zone = _comparaison(c, p, choisi, ex);
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CarteSigh(child: LayoutBuilder(builder: (_, k) {
            final deux = k.maxWidth >= 768;
            final l = deux ? (k.maxWidth - 12) / 2 : k.maxWidth;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(width: l, child: FormulaireSigh(controleur: _patient!)),
              SizedBox(
                  width: l,
                  child: _examen == null
                      ? FormulaireSigh(
                          controleur: ControleurFormulaire(const [
                          ChampDef(nom: 'examen', libelle: 'Examen', type: TypeChamp.select, col: ColChamp.plein, indicatif: '— Choisir un examen —')
                        ]))
                      : FormulaireSigh(controleur: _examen!)),
            ]);
          })),
          const SizedBox(height: 16),
          zone,
          if (masques > 0) ...[
            const SizedBox(height: 16),
            NoteSigh('${nombre(masques)} résultat(s) rendus sont hors de votre périmètre et n’apparaissent pas ici — restriction du RBAC métier, pas donnée manquante.',
                icone: LucideIcons.shieldCheck),
          ],
        ]);
      },
    );
  }

  Widget _comparaison(ContexteEcran c, ProfilLabo p, PatientComparable pat, ExamenComparable ex) {
    final jeu = jeuLaboDe(c, p.session);
    final mr = mesuresRendues(_vuPatient, ex.code, jeu);
    final liste = mr.visibles;
    if (liste.length < 2) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (mr.cachees.isNotEmpty) _noteMasquees(mr),
        const VideSigh(
            'Une seule mesure de cet examen : aucune antériorité à comparer. La colonne « Antériorités » se remplira à la prochaine mesure.',
            icone: LucideIcons.history),
      ]);
    }
    final sig = '${ex.code}|${liste.length}|$_vuPatient';
    if (_b == null || _signatureB != sig) {
      _b?.dispose();
      _b = ControleurFormulaire([
        ChampDef(
            nom: 'b',
            libelle: 'Mesure comparée',
            type: TypeChamp.select,
            requis: true,
            options: [for (final (i, r) in liste.indexed) OptionChamp('$i', libelleMesure(r))]),
      ], {
        // La plus récente par défaut ; l'utilisateur choisit, ses antériorités s'en déduisent.
        'b': '${liste.length - 1}',
      });
      _signatureB = sig;
    }
    final b = _b!;
    return ListenableBuilder(
      listenable: b,
      builder: (context, _) {
        final mesure = liste[int.parse('${b['b']}')];
        final modele = modeleComparatif(ex.code, mesure, jeu);
        final nb = jeu.nombre;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (mr.cachees.isNotEmpty) ...[_noteMasquees(mr), const SizedBox(height: 16)],
          CarteSigh(
              child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end, children: [
            SizedBox(width: 320, child: FormulaireSigh(controleur: b)),
            ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text('Ses antériorités sont les ${nombre(nb)} mesures rendues qui la précèdent, de la plus ancienne à la plus récente.',
                    style: styleLabo(12, couleur: JetonsShell.slate500))),
            BoutonSigh(
                key: const Key('res:cmp:imprimer'),
                libelle: 'Imprimer le comparatif',
                icone: LucideIcons.printer,
                variante: VarianteBouton.secondaire,
                onPressed: () => _imprimer(context, c, pat, ex, modele)),
          ])),
          const SizedBox(height: 16),
          if (modele.anterieures.mesures.isEmpty)
            const VideSigh('Cette mesure est la plus ancienne rendue : aucune antériorité. Choisir une mesure plus récente.', icone: LucideIcons.history)
          else
            _tableau(context, c, jeu, ex, modele),
        ]);
      },
    );
  }

  Widget _noteMasquees(MesuresRendues mr) => NoteSigh(
      '${nombre(mr.cachees.length)} mesure(s) rendue(s) de cet examen sont hors de votre périmètre : ${mr.motif}. Elles n’entrent ni dans les colonnes, ni dans la variation, ni dans la courbe.',
      icone: LucideIcons.shieldCheck);

  Widget _tableau(BuildContext ctx, ContexteEcran c, JeuLabo jeu, ExamenComparable ex, ModeleComparatif modele) {
    final nb = modele.colonnes.length;
    final derniereAnt = modele.anterieures.mesures.last;
    TableRow entete() => TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50), children: [
          _cellule(Text('VARIABLE', style: styleLabo(12, couleur: JetonsShell.slate500, poids: FontWeight.w600))),
          for (final (i, m) in modele.colonnes.indexed)
            _cellule(
                Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Text(dateFrJs(m['dateHeure']), style: styleLabo(12, couleur: JetonsShell.slate500, poids: FontWeight.w600)),
                  Text(i == nb - 1 ? 'Mesure comparée' : 'Antériorité ${i + 1}', style: styleLabo(10, couleur: JetonsShell.slate400)),
                ]),
                droite: true),
          _cellule(Text('VARIATION À LA MESURE PRÉCÉDENTE', style: styleLabo(12, couleur: JetonsShell.slate500, poids: FontWeight.w600)), droite: true),
          _cellule(Text('RÉFÉRENCES (MESURE COMPARÉE)', style: styleLabo(12, couleur: JetonsShell.slate500, poids: FontWeight.w600)), droite: true),
          _cellule(Text('TENDANCE', style: styleLabo(12, couleur: JetonsShell.slate500, poids: FontWeight.w600))),
        ]);
    TableRow ligne(LigneModele l) {
      final v = l.variable;
      final code = '${v['code']}';
      final enfant = _vrai(v['parent']);
      final refB = l.cellules.last.reference;
      final sens = l.variation?.sens;
      final alerte = l.alerte;
      return TableRow(decoration: const BoxDecoration(border: Border(top: BorderSide(color: JetonsShell.slate100))), children: [
        _cellule(Padding(
            padding: EdgeInsets.only(left: enfant ? 16 : 0),
            child: Text('${enfant ? '↳ ' : ''}${v['libelle']}',
                style: styleLabo(14,
                    couleur: enfant ? JetonsShell.slate600 : JetonsShell.slate800, poids: enfant ? FontWeight.w400 : FontWeight.w500)))),
        for (final (i, cel) in l.cellules.indexed)
          _cellule(
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                Text(texteCellule(l, cel),
                    key: Key('res:cmp:cell:$code:${i == nb - 1 ? 'b' : 'a$i'}'),
                    style: styleLabo(14,
                        couleur: cel.ecart != null ? JetonsShell.danger700 : JetonsShell.slate700,
                        poids: cel.ecart != null ? FontWeight.w700 : FontWeight.w400)),
                // Chaque antériorité est jugée aux bornes de SON époque : quand elles diffèrent de celles de la mesure comparée, la cellule les nomme.
                if (i < nb - 1 && !_vide(cel.valeur) && cel.reference.isNotEmpty && cel.reference != refB)
                  Text('réf. ${cel.reference}',
                      key: Key('res:cmp:ref-epoque:$code:a$i'), style: styleLabo(10, couleur: JetonsShell.slate400)),
              ]),
              droite: true),
        _cellule(
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Text(texteVariation(l.variation, l.suffixe),
                  key: Key('res:cmp:variation:$code'),
                  textAlign: TextAlign.right,
                  style: styleLabo(12,
                      poids: FontWeight.w500,
                      couleur: l.variation == null
                          ? JetonsShell.slate400
                          : (sens == 'hausse' ? JetonsShell.danger700 : (sens == 'baisse' ? JetonsShell.info700 : JetonsShell.slate500)))),
              if (l.variation != null && l.precedente != null && !identical(l.precedente, derniereAnt))
                Text('à la mesure du ${dateFrJs(l.precedente!['dateHeure'])}', style: styleLabo(10, couleur: JetonsShell.slate400)),
              // L'ALERTE SIGNALE, ELLE NE BLOQUE RIEN (lot A2) : seuil VALIDÉ franchi, version et date d'effet nommées.
              // L'ÂGE de la mesure précédente s'affiche TOUJOURS (avec ou sans délai réglé) ; au-delà du délai réglé, le comparatif DIT que la variation n'est pas évaluée.
              if (l.variation != null && l.ageJours != null)
                Text(texteAge(l.ageJours)!, key: Key('res:cmp:age:$code'), style: styleLabo(10, couleur: JetonsShell.slate400)),
              if (alerte != null && alerte.nonEvalue == 'delai')
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(texteNonEvalue(alerte),
                        key: Key('res:cmp:non-evaluee:$code'), textAlign: TextAlign.right, style: styleLabo(10, couleur: JetonsShell.slate600, poids: FontWeight.w500))),
              if (alerte != null && alerte.alerte)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(key: Key('res:cmp:alerte:$code'), mainAxisSize: MainAxisSize.min, children: [
                      const Icon(LucideIcons.activity, size: 12, color: JetonsShell.warning700),
                      const SizedBox(width: 4),
                      Flexible(
                          child: Text(texteAlerte(alerte, l.suffixe),
                              textAlign: TextAlign.right, style: styleLabo(10, couleur: JetonsShell.warning700, poids: FontWeight.w600))),
                    ])),
              if (alerte != null && alerte.nonEvaluable)
                Text(alerte.seuil['ecartAbsolu'] != null ? 'Seuil relatif non évalué (valeur précédente nulle ou proche de zéro) : seul le seuil absolu juge.' : 'Seuil relatif non évalué : valeur précédente nulle ou proche de zéro.', style: styleLabo(10, couleur: JetonsShell.slate400)),
            ]),
            droite: true),
        _cellule(Text(refB.isEmpty ? '—' : refB, style: styleLabo(12, couleur: JetonsShell.slate500)), droite: true),
        _cellule(v['type'] == 'numerique'
            ? BoutonIcone(
                key: Key('res:tendance:$code'),
                icone: LucideIcons.chartLine,
                libelle: 'Courbe de tendance de ${v['libelle']}',
                onPressed: () => _ouvrirTendance(ctx, c, jeu, ex, v))
            : const SizedBox.shrink()),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CarteSigh(
          sansRemplissage: true,
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: 760.0 + 130 * nb),
                  child: Table(
                      key: const Key('res:comparatif'),
                      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                      columnWidths: {
                        0: const FlexColumnWidth(3),
                        for (var i = 0; i < nb; i++) 1 + i: const FlexColumnWidth(2),
                        nb + 1: const FlexColumnWidth(3.2),
                        nb + 2: const FlexColumnWidth(2.4),
                        nb + 3: const FlexColumnWidth(1.2),
                      },
                      children: [entete(), for (final l in modele.lignes) ligne(l)])))),
      const SizedBox(height: 16),
      const NoteSigh(
          'Les colonnes se lisent de gauche à droite, de la plus ancienne à la mesure comparée. Les valeurs en gras sont hors des références de leur époque : chaque colonne se compare aux bornes du lot de réactif en service à sa date. Une valeur qualitative se compare en texte, sans pourcentage ; un pourcentage n’est calculé que sur une valeur précédente non nulle. Un signalement de variation brutale n’empêche jamais de valider.',
          icone: LucideIcons.gitCompareArrows),
    ]);
  }

  // --- La courbe de tendance ----------------------------------------------------------------------------------------------------------------------

  /// TOUTES les mesures rendues et lisibles du patient pour cet examen (pas seulement les colonnes affichées).
  void _ouvrirTendance(BuildContext ctx, ContexteEcran c, JeuLabo jeu, ExamenComparable ex, Map<String, Object?> variable) {
    final mr = mesuresRendues(_vuPatient, ex.code, jeu);
    final u = symbole(c, variable['unite']);
    final suffixe = u == '—' ? '' : ' $u';
    final points = <({Map<String, Object?> demande, double valeur, num? min, num? max, String reference})>[];
    for (final r in mr.visibles) {
      final x = ((r['valeurs'] as Map?) ?? const {})[variable['code']];
      final n = x is num ? x.toDouble() : double.tryParse('${x ?? ''}'.trim());
      if (x == null || x == '' || n == null || !n.isFinite) continue;
      final borne = variableALaDate(variable, jeu.plages, r['dateHeure'], aujourdhui: jeu.aujourdhui);
      points.add((
        demande: r,
        valeur: n,
        min: borne['min'] as num?,
        max: borne['max'] as num?,
        reference: referenceALaDate(variable, jeu.plages, r['dateHeure'], aujourdhui: jeu.aujourdhui)
      ));
    }
    final Widget corps;
    if (points.length < 2) {
      corps = const VideSigh('Moins de deux mesures rendues : aucune courbe à tracer.', icone: LucideIcons.chartLine);
    } else {
      final valeurs = [for (final p in points) p.valeur];
      final borneBasse = points.every((p) => p.min != null) ? [for (final p in points) p.min!] : null;
      final borneHaute = points.every((p) => p.max != null) ? [for (final p in points) p.max!] : null;
      final tous = [...valeurs, ...?borneBasse?.map((e) => e.toDouble()), ...?borneHaute?.map((e) => e.toDouble())];
      var lo = tous.reduce((a, b) => a < b ? a : b), hi = tous.reduce((a, b) => a > b ? a : b);
      final marge = (hi - lo) == 0 ? 1.0 : (hi - lo) * 0.1;
      lo -= marge;
      hi += marge;
      corps = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CarteSigh(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LegendeGraphique(entrees: [
            ('${variable['libelle']}$suffixe', JetonsShell.navy600),
            if (borneBasse != null) ('Borne basse', JetonsShell.warning500),
            if (borneHaute != null) ('Borne haute', JetonsShell.danger500),
          ]),
          GraphiqueLigne(
              key: Key('res:tendance:courbe:${variable['code']}'),
              etiquettes: [for (final p in points) dateFrJs(p.demande['dateHeure'])],
              series: [
                SerieGraphique('${variable['libelle']}$suffixe', valeurs, couleur: JetonsShell.navy600, aire: false),
                if (borneBasse != null) SerieGraphique('Borne basse', borneBasse, couleur: JetonsShell.warning500, aire: false),
                if (borneHaute != null) SerieGraphique('Borne haute', borneHaute, couleur: JetonsShell.danger500, aire: false),
              ],
              hauteur: 280,
              min: lo,
              max: hi),
        ])),
        const SizedBox(height: 12),
        CarteSigh(
            sansRemplissage: true,
            child: Table(key: Key('res:tendance:valeurs:${variable['code']}'), columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(3)
            }, children: [
              TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50), children: [
                for (final (i, t) in ['DATE', 'CODE D’ANALYSE', 'VALEUR', 'RÉFÉRENCES DE L’ÉPOQUE'].indexed)
                  _cellule(Text(t, style: styleLabo(12, couleur: JetonsShell.slate500, poids: FontWeight.w600)), droite: i >= 2)
              ]),
              for (final p in points)
                TableRow(decoration: const BoxDecoration(border: Border(top: BorderSide(color: JetonsShell.slate100))), children: [
                  _cellule(Text(dateFrJs(p.demande['dateHeure']), style: styleLabo(14))),
                  _cellule(Text('${_vrai(p.demande['codeAnalyse']) ? p.demande['codeAnalyse'] : (p.demande['reference'] ?? '')}',
                      style: styleLabo(12, police: 'monospace'))),
                  _cellule(Text('${chaineJs(p.valeur)}$suffixe', style: styleLabo(14)), droite: true),
                  _cellule(Text(p.reference.isEmpty ? '—' : p.reference, style: styleLabo(12, couleur: JetonsShell.slate500)), droite: true),
                ])
            ])),
        if (mr.cachees.isNotEmpty) ...[
          const SizedBox(height: 12),
          NoteSigh(
              '${nombre(mr.cachees.length)} mesure(s) rendue(s) de cet examen sont hors de votre périmètre et ne figurent pas sur la courbe : ${mr.motif}.',
              icone: LucideIcons.shieldCheck),
        ],
      ]);
    }
    afficherModale<void>(ctx,
        titre: 'Tendance : ${variable['libelle']}',
        sousTitre: points.isEmpty ? null : '${nombre(points.length)} mesure(s) rendue(s)',
        taille: TailleModale.lg,
        corps: corps,
        pied: (fermer) => [BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);
  }

  // --- La pièce imprimée --------------------------------------------------------------------------------------------------------------------------

  void _imprimer(BuildContext ctx, ContexteEcran c, PatientComparable pat, ExamenComparable ex, ModeleComparatif modele) {
    final b = modele.comparee;
    final nb = modele.colonnes.length;
    final colonnes = <ColonneEtat>[
      ColonneEtat(libelle: 'Variable', valeur: (l) => l['variable']),
      for (var i = 0; i < nb; i++) ColonneEtat(libelle: dateFrJs(modele.colonnes[i]['dateHeure']), droite: true, valeur: (l) => l['c$i']),
      ColonneEtat(libelle: 'Variation à la mesure précédente', droite: true, valeur: (l) => l['variation']),
      ColonneEtat(libelle: 'Références', droite: true, valeur: (l) => l['ref']),
    ];
    final lignes = [
      for (final l in modele.lignes)
        <String, Object?>{
          'variable': '${l.variable['libelle']}',
          for (var i = 0; i < nb; i++) 'c$i': texteCellule(l, l.cellules[i]),
          'variation': '${texteVariation(l.variation, l.suffixe)}${l.alerte != null && l.alerte!.alerte ? ' — ${texteAlerte(l.alerte!, l.suffixe)}' : ''}${l.alerte != null && l.alerte!.nonEvalue == 'delai' ? ' — ${texteNonEvalue(l.alerte!)}' : ''}',
          'ref': l.cellules.last.reference.isEmpty ? '—' : l.cellules.last.reference,
        }
    ];
    afficherApercu(
        ctx,
        PieceA4(
          titre: 'Comparatif des résultats',
          sousTitre: '${b['analyse']} : ${pat.patient}',
          reference: referenceLabo(c),
          utilisateur: acteur(c).nom,
          edite: c.aujourdhui,
          cartouche: [
            ('Patient', pat.patient),
            ('Dossier', pat.code),
            ('Mesure comparée', dateFrJs(b['dateHeure'])),
            ('Antériorités', nombre(modele.anterieures.mesures.length)),
            ('Établi par', acteur(c).nom),
            ('Date d’édition', dateFR(c.aujourdhui)),
          ],
          blocs: [
            BlocTableau(TableauEtat(colonnes: colonnes, lignes: lignes)),
            BlocTexte(
                'Seules les mesures rendues (validées biologiquement) et lisibles par le profil qui édite entrent dans ce comparatif.${modele.anterieures.masquees > 0 ? ' ${nombre(modele.anterieures.masquees)} antériorité(s) hors du périmètre de ce profil ne sont pas reprises.' : ''}',
                italique: true),
          ],
          signatures: const [Signature('Le Biologiste médical')],
        ));
  }

  static bool _vide(Object? v) => v == null || v == '';
  static bool _vrai(Object? v) => v != null && v != false && v != '' && v != 0;

  Widget _cellule(Widget w, {bool droite = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Align(alignment: droite ? Alignment.centerRight : Alignment.centerLeft, child: w));
}
