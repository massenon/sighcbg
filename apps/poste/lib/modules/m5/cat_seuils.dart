import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/seuils_poste.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m6/points_commun.dart' show champUnique, commande;
import 'cat_commun.dart';
import 'res_commun.dart' show symbole, styleLabo;

/// LES SEUILS DE VARIATION BRUTALE (lot A2), à l'écran « Valeurs de référence » : un seuil par variable NUMÉRIQUE, VIDE par défaut. Aucun document n'en donne, aucun
/// n'est proposé : un seuil vide veut dire « pas d'alerte configurée », jamais zéro. ENREGISTRER garde l'état « Enregistré » (sans effet), même pour le biologiste ;
/// VALIDER est un second geste, motivé, qui le fait passer à « Validé » (en vigueur) — il est réservé par la MATRICE (droit annuler de l'écran) et le moteur
/// REVÉRIFIE : la commande interdite est ABSENTE de l'écran, un geste forcé reçoit un refus nommé. Modifier un seuil validé AJOUTE une version datée.
class SectionSeuils extends StatefulWidget {
  const SectionSeuils({super.key, required this.variables});

  /// Les variables de l'écran, déjà filtrées par section et par examen : le tableau n'en garde que les numériques.
  final List<Fiche> variables;

  @override
  State<SectionSeuils> createState() => _EtatSeuils();
}

class _EtatSeuils extends State<SectionSeuils> {
  late final ControleurFormulaire _filtre = champUnique(
      const ChampDef(nom: 'seuil', libelle: 'Seuils de variation', type: TypeChamp.select, options: [
        OptionChamp('', 'Tous les seuils'),
        OptionChamp('aucun', 'Sans seuil configuré'),
        OptionChamp('enregistre', 'Enregistrés (sans effet)'),
        OptionChamp('valide', 'Validés (en vigueur)'),
      ]),
      '')
    ..addListener(() {
      if (mounted) setState(() {});
    });

  @override
  void dispose() {
    _filtre.dispose();
    super.dispose();
  }

  static bool _numerique(Fiche v) => v['type'] == 'numerique' && v['accompagnement'] != true && v['actif'] != false;

  String _suffixe(ContexteEcran c, Fiche v) {
    final u = symbole(c, v['unite']);
    return u == '—' ? '' : ' $u';
  }

  Widget _badge(EtatSeuil e) => switch (e.etat) {
        'enregistre' => const BadgeSigh('Enregistré (sans effet)', ton: TonSigh.attention),
        'enregistre_sur_valide' => const BadgeSigh('Enregistré, la version validée reste en force', ton: TonSigh.attention),
        'valide' => const BadgeSigh('Validé', ton: TonSigh.succes),
        _ => BadgeSigh(e.retire ? 'Alerte retirée' : 'Aucun seuil'),
      };

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final sp = SeuilsPoste(c);
    return ListenableBuilder(
      listenable: Listenable.merge([c.magasin.collection('seuilsDelta'), c.magasin.collection('variablesLabo')]),
      builder: (context, _) {
        final tous = [for (final v in c.magasin.collection('variablesLabo').actives) if (_numerique(v)) v];
        final etats = [for (final v in tous) sp.etat(v['id']).etat];
        int n(bool Function(String) f) => etats.where(f).length;
        final filtre = '${_filtre['seuil']}';
        final lignes = [
          for (final v in widget.variables)
            if (_numerique(v) && v['statut'] != 'archive')
              if (switch (filtre) {
                'aucun' => sp.etat(v['id']).etat == 'aucun',
                'enregistre' => const ['enregistre', 'enregistre_sur_valide'].contains(sp.etat(v['id']).etat),
                'valide' => const ['valide', 'enregistre_sur_valide'].contains(sp.etat(v['id']).etat),
                _ => true,
              })
                v
        ];
        return Column(key: const Key('seuils:section'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KpiGrilleSigh(kpis: [
            KpiSigh(libelle: 'Variables numériques', valeur: nombre(tous.length), icone: LucideIcons.hash, ton: TonSigh.navy),
            KpiSigh(
                libelle: 'Seuils validés',
                valeur: nombre(n((e) => e == 'valide' || e == 'enregistre_sur_valide')),
                icone: LucideIcons.shieldCheck,
                ton: TonSigh.succes,
                indice: 'En vigueur'),
            KpiSigh(
                libelle: 'Seuils enregistrés',
                valeur: nombre(n((e) => e == 'enregistre' || e == 'enregistre_sur_valide')),
                icone: LucideIcons.save,
                ton: TonSigh.attention,
                indice: 'Sans effet tant qu’ils ne sont pas validés'),
            KpiSigh(libelle: 'Sans seuil', valeur: nombre(n((e) => e == 'aucun')), icone: LucideIcons.bellOff, ton: TonSigh.neutre, indice: 'Pas d’alerte configurée'),
          ]),
          const SizedBox(height: 16),
          const NoteSigh(
              'Seuils de variation brutale. Aucun seuil n’est proposé : un seuil vide veut dire « pas d’alerte configurée », jamais zéro. Un seuil Enregistré est sans effet ; seul un seuil Validé par un rôle auquel la fiche de rôle accorde le geste « Valider un seuil » (par défaut le Biologiste médical ; l’administrateur système n’en fait pas partie par défaut, la Direction peut le lui accorder) alerte, au comparatif et à l’écran de validation biologique, jamais sur le résultat que lit le prescripteur. Modifier un seuil validé ajoute une version datée : l’ancienne reste lisible et les alertes déjà levées gardent leur seuil. Délai maximal entre deux mesures (facultatif, vide par défaut, jamais bloquant) : au-delà, la variation n’est pas évaluée et le comparatif le dit. Forme du seuil (décidée par la Direction le 13/11/2026) : une variation absolue et/ou relative, l’alerte part dès que l’UNE des deux est atteinte ; sur une valeur précédente nulle ou proche de zéro, le pourcentage n’est pas calculé et seul le seuil absolu juge.',
              icone: LucideIcons.activity),
          const SizedBox(height: 16),
          CarteSigh(child: commande(_filtre, largeur: 260)),
          const SizedBox(height: 16),
          TableauSigh(
            titre: 'Seuils de variation brutale',
            colonnes: [
              ColonneTableau(
                  cle: 'libelle',
                  libelle: 'Variable',
                  texte: (v) => '${v['libelle']} ${v['examenLibelle'] ?? ''}',
                  rendu: (_, v) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('${v['libelle']}', overflow: TextOverflow.ellipsis, style: styleCat(couleur: JetonsShell.slate800, poids: FontWeight.w500)),
                        Text('${v['examenLibelle'] ?? ''}', style: styleCat(taille: 12, couleur: JetonsShell.slate400)),
                      ])),
              ColonneTableau(cle: 'unite', libelle: 'Unité', droite: true, texte: (v) => symbole(c, v['unite']), valeur: (v) => symbole(c, v['unite'])),
              ColonneTableau(
                  cle: 'enVigueur',
                  libelle: 'Seuil en vigueur',
                  texte: (v) {
                    final e = sp.etat(v['id']);
                    return e.enVigueur == null ? '' : texteSeuil(e.enVigueur!, _suffixe(c, v));
                  },
                  rendu: (_, v) {
                    final e = sp.etat(v['id']);
                    if (e.enVigueur == null) {
                      return Text(e.retire ? 'Alerte retirée' : 'Aucun seuil configuré', style: styleCat(taille: 12, couleur: JetonsShell.slate400));
                    }
                    return Column(
                        key: Key('seuils:vigueur:${v['code']}'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(texteSeuil(e.enVigueur!, _suffixe(c, v)), style: styleCat()),
                          if (e.enVigueur!['delaiMaxJours'] != null)
                            Text(texteDelai(e.enVigueur!),
                                key: Key('seuils:delai:${v['code']}'), style: styleCat(taille: 10, couleur: JetonsShell.slate500)),
                          Text('version ${e.enVigueur!['version']}, depuis le ${dateFrJs(e.enVigueur!['dateEffet'])}', style: styleCat(taille: 10, couleur: JetonsShell.slate400)),
                        ]);
                  }),
              ColonneTableau(
                  cle: 'etat',
                  libelle: 'État',
                  texte: (v) => sp.etat(v['id']).etat,
                  rendu: (_, v) => KeyedSubtree(key: Key('seuils:etat:${v['code']}'), child: _badge(sp.etat(v['id'])))),
              ColonneTableau(
                  cle: 'brouillon',
                  libelle: 'Enregistré en attente',
                  texte: (v) {
                    final b = sp.etat(v['id']).brouillon;
                    return b == null ? '' : texteSeuil(b, _suffixe(c, v));
                  },
                  rendu: (_, v) {
                    final b = sp.etat(v['id']).brouillon;
                    if (b == null) return Text('—', style: styleCat(taille: 12, couleur: JetonsShell.slate300));
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(b['retrait'] == true ? 'Retrait de l’alerte' : texteSeuil(b, _suffixe(c, v)), style: styleCat()),
                      Text('à partir du ${dateFrJs(b['dateEffet'])}', style: styleCat(taille: 10, couleur: JetonsShell.slate400)),
                    ]);
                  }),
            ],
            lignes: lignes,
            taillePage: 12,
            nomExport: 'seuils-variation',
            messageVide: 'Aucune variable numérique ne correspond à ce filtre.',
            actionsLigne: (ctx, v) {
              final e = sp.etat(v['id']);
              return [
                if (sp.peutEnregistrer)
                  BoutonIcone(
                      key: Key('seuils:regler:${v['code']}'),
                      icone: LucideIcons.slidersHorizontal,
                      libelle: 'Régler le seuil de ${v['libelle']}',
                      onPressed: () => _regler(ctx, v)),
                // Valider : ABSENT pour tout profil auquel la matrice ne l'accorde pas ; le moteur refuse aussi.
                if (e.brouillon != null && sp.peutValider)
                  BoutonSigh(
                      key: Key('seuils:valider:${v['code']}'),
                      libelle: 'Valider',
                      icone: LucideIcons.shieldCheck,
                      taille: TailleBouton.sm,
                      onPressed: () => _valider(ctx, v)),
                if (e.brouillon != null && sp.peutEnregistrer)
                  BoutonIcone(
                      key: Key('seuils:abandonner:${v['code']}'),
                      icone: LucideIcons.x,
                      libelle: 'Abandonner le seuil enregistré',
                      onPressed: () => _abandonner(ctx, v)),
                if (e.versions.isNotEmpty)
                  BoutonIcone(
                      key: Key('seuils:historique:${v['code']}'),
                      icone: LucideIcons.history,
                      libelle: 'Historique des versions du seuil',
                      onPressed: () => _historique(ctx, v)),
              ];
            },
          ),
        ]);
      },
    );
  }

  void _refus(BuildContext ctx, RefusSeuil r) => ToastsSigh.afficher(ctx, r.motif, type: TypeToast.erreur, detail: r.geste);

  void _regler(BuildContext ctx, Fiche v) {
    final c = ContexteEcran.of(ctx);
    final sp = SeuilsPoste(c);
    final e = sp.etat(v['id']);
    final base = e.brouillon ?? e.enVigueur;
    final u = symbole(c, v['unite']);
    String t(Object? x) => x == null ? '' : (x is num && x == x.truncate() ? '${x.toInt()}' : '$x');
    final ctl = ControleurFormulaire([
      ChampDef(
          nom: 'ecartAbsolu',
          libelle: 'Variation absolue d’au moins${u == '—' ? '' : ' ($u)'}',
          type: TypeChamp.nombre,
          aide: 'Vide : pas d’alerte sur l’écart absolu'),
      const ChampDef(nom: 'ecartRelatif', libelle: 'Variation relative d’au moins (%)', type: TypeChamp.nombre, aide: 'Vide : pas d’alerte sur le pourcentage'),
      const ChampDef(
          nom: 'delaiMaxJours',
          libelle: 'Délai maximal entre deux mesures (jours)',
          type: TypeChamp.nombre,
          aide: 'Vide : aucun délai. Au-delà, la variation n’est pas évaluée et le comparatif le dit ; rien n’est bloqué.'),
      const ChampDef(
          nom: 'dateEffet',
          libelle: 'Date d’effet',
          type: TypeChamp.date,
          requis: true,
          aide: 'Aujourd’hui ou plus tard : un seuil ne s’applique jamais en arrière'),
      const ChampDef(nom: 'retrait', libelle: 'Retirer l’alerte de cette variable', type: TypeChamp.case_, col: ColChamp.plein, aide: 'Une version aussi : enregistrée, puis validée'),
      const ChampDef(nom: 'note', libelle: 'Note', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
    ], {
      'ecartAbsolu': t(base?['ecartAbsolu']),
      'ecartRelatif': t(base?['ecartRelatif']),
      'delaiMaxJours': base?['retrait'] == true ? '' : t(base?['delaiMaxJours']),
      'dateEffet': iso(DateTime(c.aujourdhui.year, c.aujourdhui.month, c.aujourdhui.day)),
      'note': base?['note'] ?? '',
    });
    afficherModale<void>(ctx,
        titre: 'Seuil de variation : ${v['libelle']}',
        sousTitre: '${v['examenLibelle'] ?? ''}',
        taille: TailleModale.md,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoteSigh(
              e.enVigueur != null
                  ? 'Seuil validé en force : ${texteSeuil(e.enVigueur!, u == '—' ? '' : ' $u')} (version ${e.enVigueur!['version']}). Enregistrer ajoute une version ; la version validée reste en force jusqu’à la validation de la nouvelle.'
                  : 'Aucun seuil validé. Enregistrer ne produit aucune alerte : le seuil reste sans effet tant qu’il n’est pas validé.',
              icone: LucideIcons.activity),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: ctl),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('seuils:enregistrer'),
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) return;
                    final r = SeuilsPoste(c).enregistrer('${v['id']}',
                        ecartAbsolu: saisie['ecartAbsolu'],
                        ecartRelatif: saisie['ecartRelatif'],
                        delaiMaxJours: saisie['delaiMaxJours'],
                        retrait: saisie['retrait'] == true,
                        dateEffet: saisie['dateEffet'],
                        note: '${saisie['note'] ?? ''}');
                    if (!r.ok) {
                      _refus(ctx, r.refus!);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Seuil enregistré (sans effet).',
                        type: TypeToast.succes, detail: '${v['libelle']} : il n’alertera qu’une fois validé.');
                  }),
            ]);
  }

  Future<void> _valider(BuildContext ctx, Fiche v) async {
    final c = ContexteEcran.of(ctx);
    final sp = SeuilsPoste(c);
    final b = sp.etat(v['id']).brouillon;
    if (b == null) return;
    final motif = await confirmerAvecMotif(ctx,
        titre: 'Valider le seuil de « ${v['libelle']} » ?',
        message:
            'Le seuil ${b['retrait'] == true ? 'retire l’alerte' : texteSeuil(b, _suffixe(c, v))} entrera en vigueur le ${dateFrJs(b['dateEffet'])}. À partir de là, une variation au moins égale à ce seuil est signalée au comparatif et à l’écran de validation biologique ; elle n’empêche jamais de valider. La version validée ne se réécrit plus : la modifier ajoutera une version.\n\nLe motif dit sur quoi le seuil s’appuie.',
        libelleOk: 'Valider le seuil',
        // Un motif vide n'est pas ignoré en silence : le moteur le refuse en le nommant (MOTIF_OBLIGATOIRE).
        motifObligatoire: false);
    if (motif == null || !ctx.mounted) return;
    final r = sp.valider('${v['id']}', motif: motif);
    if (!r.ok) {
      _refus(ctx, r.refus!);
      return;
    }
    ToastsSigh.afficher(ctx, 'Seuil validé.',
        type: TypeToast.succes, detail: '${v['libelle']} : en vigueur le ${dateFrJs(b['dateEffet'])}, validé par ${acteur(c).nom}.');
  }

  Future<void> _abandonner(BuildContext ctx, Fiche v) async {
    final ok = await confirmerSigh(ctx,
        titre: 'Abandonner le seuil enregistré de « ${v['libelle']} » ?',
        message: 'Le seuil enregistré (sans effet) est archivé. La version validée, s’il y en a une, reste en force.',
        libelleOk: 'Abandonner',
        dangereux: true);
    if (!ok || !ctx.mounted) return;
    final r = SeuilsPoste(ContexteEcran.of(ctx)).abandonner('${v['id']}');
    if (!r.ok) {
      _refus(ctx, r.refus!);
      return;
    }
    ToastsSigh.afficher(ctx, 'Seuil abandonné.', type: TypeToast.succes);
  }

  void _historique(BuildContext ctx, Fiche v) {
    final c = ContexteEcran.of(ctx);
    final e = SeuilsPoste(c).etat(v['id']);
    final suffixe = _suffixe(c, v);
    afficherModale<void>(ctx,
        titre: 'Versions du seuil : ${v['libelle']}',
        sousTitre: '${v['examenLibelle'] ?? ''}',
        taille: TailleModale.lg,
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const NoteSigh('Une version validée ne se réécrit jamais : une alerte déjà levée garde le seuil sous lequel elle l’a été.', icone: LucideIcons.history),
          const SizedBox(height: 12),
          CarteSigh(
              sansRemplissage: true,
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 760),
                      child: Table(key: Key('seuils:versions:${v['code']}'), columnWidths: const {
                        0: FlexColumnWidth(1),
                        1: FlexColumnWidth(2.2),
                        2: FlexColumnWidth(2),
                        3: FlexColumnWidth(1.6),
                        4: FlexColumnWidth(2),
                        5: FlexColumnWidth(2.4),
                        6: FlexColumnWidth(2.4),
                      }, children: [
                        TableRow(decoration: const BoxDecoration(color: JetonsShell.slate50), children: [
                          for (final t in ['VERSION', 'ÉTAT', 'SEUIL', 'DATE D’EFFET', 'ENREGISTRÉ PAR', 'VALIDÉ PAR', 'MOTIF'])
                            _c(Text(t, style: styleLabo(12, couleur: JetonsShell.slate500, poids: FontWeight.w600)))
                        ]),
                        for (final x in e.versions.reversed)
                          TableRow(decoration: const BoxDecoration(border: Border(top: BorderSide(color: JetonsShell.slate100))), children: [
                            _c(Text('v${x['version']}', style: styleLabo(14))),
                            _c(Text(x['etat'] == 'valide' ? 'Validé' : 'Enregistré (sans effet)', style: styleLabo(14))),
                            _c(Text(x['retrait'] == true ? 'Retrait de l’alerte' : texteSeuil(x, suffixe) + (x['delaiMaxJours'] != null ? ' (${texteDelai(x)})' : ''), style: styleLabo(14))),
                            _c(Text(dateFrJs(x['dateEffet']), style: styleLabo(14))),
                            _c(Text('${x['enregistrePar'] ?? ''}${x['enregistreLe'] != null ? ', le ${dateFrJs(x['enregistreLe'])}' : ''}', style: styleLabo(12))),
                            _c(Text(x['etat'] == 'valide' ? '${x['validePar']} (${x['valideRole']}), le ${dateFrJs(x['valideLe'])}' : '', style: styleLabo(12))),
                            _c(Text('${x['motifValidation'] ?? ''}', style: styleLabo(12))),
                          ])
                      ]))))
        ]),
        pied: (fermer) => [BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer)]);
  }

  Widget _c(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Align(alignment: Alignment.centerLeft, child: w));
}
