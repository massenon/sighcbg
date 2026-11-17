import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/numerotation_poste.dart';
import '../../core/service_installation.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import '../../sync/service_validations_deposees.dart';
import 'cfb_commun.dart';

/// « NUMÉROTATION DES PIÈCES » (lot 2 de l'inventaire des valeurs en dur, 16/11/2026) : la section de « Fiscalité & identité légale » qui administre le
/// référentiel de numérotation UNIQUE. Une ligne par série (bons, commandes, factures, avoirs, ordonnances, CPA, CRA, certificats, missions, écritures…) :
/// son format en vigueur aujourd'hui, l'exemple du premier numéro de l'année, la remise annuelle, l'état (semence « à valider », ou version arrêtée,
/// datée et signée) et les versions à venir.
///
/// La commande « Modifier » est ABSENTE sans le geste réservé `numerotation_modifier` (origine proposée : l'administrateur et la Directrice Administrative,
/// à valider) et sans le droit d'éditer l'écran. Une modification est une VERSION DATÉE, au plus tôt aujourd'hui : elle ne s'applique qu'aux pièces à venir,
/// les pièces déjà émises gardent leur numéro (RG-01). Sur un poste rattaché, elle est DÉPOSÉE et la mère l'applique (famille R).
class CarteNumerotation extends StatelessWidget {
  const CarteNumerotation({super.key, required this.c});
  final ContexteEcran c;

  bool get _depose => ServiceInstallation.de(c.magasin).rattache;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
        valueListenable: versionNumerotation,
        builder: (context, _, __) {
          final aujourdhui = c.aujourdhui;
          final peut = c.droit.editer && gestePeutEcran(c, gesteNumerotationModifier);
          final service = ServiceValidationsDeposees.de(c.magasin);
          final jour = _iso(aujourdhui);
          final lignes = [
            // La série FISCALE en tête (factures normalisées, pro-forma, avoirs : la MECeF les lit), puis l'ordre du référentiel, module par module.
            for (final s in [...Numerotation.semences.where((x) => _fiscales.contains(x.code)), ...Numerotation.semences.where((x) => !_fiscales.contains(x.code))])
              () {
                final v = Numerotation.serie(s.code, date: aujourdhui);
                final avenir = [for (final x in Numerotation.versions(s.code)) if (x.dateEffet!.compareTo(jour) > 0) x];
                final derniere = Numerotation.versions(s.code).where((x) => x.dateEffet!.compareTo(jour) <= 0).lastOrNull;
                final fiche = derniere == null
                    ? null
                    : c.magasin.collection(colSeriesNumerotation).toutes.where((f) => f['code'] == s.code && f['dateEffet'] == derniere.dateEffet && f['statut'] != 'archive').firstOrNull;
                return <String, Object?>{
                  'id': s.code,
                  'code': s.code,
                  'libelle': v.libelle,
                  'module': v.module,
                  'format': v.formatLisible,
                  // Les têtes d'AVANT que la série relit pour ses rangs (un préfixe propre à chaque registre, 17/11/2026) : les pièces émises gardent leur numéro.
                  'lit': v.prefixesAnterieurs.join(' '),
                  'exemple': v.genre == genreDerive ? numeroDerive(s.code, '…', date: aujourdhui) : numeroFormate(s.code, date: aujourdhui, rang: 1),
                  'remise': v.genre == genreDerive ? 'Dérivée d’une autre pièce' : (v.remiseAnnuelle ? 'Repart à 1 chaque année' : 'Continue d’une année à l’autre'),
                  'etat': v.aValider ? 'À valider' : 'Arrêtée',
                  'detailEtat': v.aValider
                      ? v.note
                      : 'Depuis le ${_jourFr(v.dateEffet)}${fiche == null ? '' : ', par ${fiche['creePar'] ?? '—'} : ${fiche['motif'] ?? ''}'}',
                  'avenir': avenir.isEmpty ? '' : avenir.map((x) => '${x.formatLisible} au ${_jourFr(x.dateEffet)}').join(' ; '),
                  'depot': service.depotSerieEnAttente(s.code) != null,
                };
              }()
          ];
          final modules = {for (final l in lignes) '${l['module']}'}.toList()..sort();
          return CarteSigh(
              titre: 'Numérotation des pièces',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                cfbNote(
                    'Une SEULE fabrique numérote toutes les pièces du logiciel, à partir de ce référentiel : aucun préfixe ni millésime n’est écrit dans le code, et l’année d’un numéro est celle de la DATE DE LA PIÈCE. '
                    'Les formats proposés reprennent exactement ceux en service au 16/11/2026 (aucune pièce existante ne change de numéro) : ils restent « à valider » tant que la Direction ne les a pas arrêtés. '
                    'Une modification est une version datée, au plus tôt aujourd’hui : elle ne s’applique qu’aux pièces à venir.'),
                if (_depose) ...[
                  const SizedBox(height: 8),
                  cfbNote('Ce poste est rattaché : une modification est transmise à la mère, qui l’applique sous votre rôle ; la nouvelle version revient ici par la synchronisation.'),
                ],
                if (!peut) ...[
                  const SizedBox(height: 8),
                  cfbNote('La modification d’une série est le geste réservé « Modifier une série de numérotation des pièces » (origine proposée : l’administrateur et la Directrice Administrative) : ce profil consulte.'),
                ],
                const SizedBox(height: 12),
                TableauSigh(
                  key: const Key('cfb:numerotation'),
                  lignes: lignes,
                  taillePage: 15,
                  nomExport: 'numerotation-pieces',
                  filtres: [
                    FiltreTableau(nom: 'module', libelle: 'Module', options: [for (final m in modules) OptionChamp(m)]),
                    const FiltreTableau(nom: 'etat', libelle: 'État', options: [OptionChamp('À valider'), OptionChamp('Arrêtée')]),
                  ],
                  colonnes: [
                    ColonneTableau(cle: 'libelle', libelle: 'Type de document'),
                    ColonneTableau(cle: 'module', libelle: 'Module', sansCoupure: true),
                    ColonneTableau(
                        cle: 'format',
                        libelle: 'Format',
                        sansCoupure: true,
                        texte: (l) => '${l['format']}${'${l['lit']}'.isEmpty ? '' : ' (lit aussi ${l['lit']})'}',
                        rendu: (_, l) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              _mono('${l['format']}'),
                              if ('${l['lit']}'.isNotEmpty) Text('Lit aussi : ${l['lit']}', style: const TextStyle(fontSize: 12, color: JetonsShell.slate500)),
                            ])),
                    ColonneTableau(cle: 'exemple', libelle: 'Premier numéro de l’année', sansCoupure: true, rendu: (_, l) => _mono('${l['exemple']}')),
                    ColonneTableau(cle: 'remise', libelle: 'Séquence'),
                    ColonneTableau(
                        cle: 'etat',
                        libelle: 'État',
                        texte: (l) => '${l['etat']} — ${l['detailEtat']}',
                        rendu: (_, l) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              BadgeSigh('${l['etat']}', ton: l['etat'] == 'Arrêtée' ? TonSigh.succes : TonSigh.attention),
                              if ('${l['avenir']}'.isNotEmpty) Text('À venir : ${l['avenir']}', style: const TextStyle(fontSize: 12, color: JetonsShell.navy700)),
                              if (l['depot'] == true) const Text('Modification transmise à la mère, en attente.', style: TextStyle(fontSize: 12, color: JetonsShell.slate500)),
                            ])),
                  ],
                  actionsLigne: peut
                      ? (ctx, l) => [
                            BoutonSigh(
                                key: Key('cfb:numerotation:modifier:${l['code']}'),
                                libelle: 'Modifier',
                                icone: LucideIcons.pencil,
                                variante: VarianteBouton.secondaire,
                                taille: TailleBouton.sm,
                                onPressed: () => _modifier(ctx, '${l['code']}')),
                          ]
                      : null,
                ),
                const SizedBox(height: 8),
                // Le code de dossier patient (RG-01) a sa propre fabrique (plages de la mère, lot 0) : il se lit ici, il ne se règle pas ici.
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Text('Dossier patient :', style: TextStyle(fontSize: 12, color: JetonsShell.slate600)),
                  _mono('${IdentiteClinique.sigle}/[n°]/[AA]'),
                  const Text('numérotation propre (RG-01), par année civile, attribuée par plages de la mère ; un code attribué ne se modifie jamais.',
                      style: TextStyle(fontSize: 12, color: JetonsShell.slate600)),
                ]),
              ]));
        });
  }

  void _modifier(BuildContext ctx, String code) {
    final s = Numerotation.serie(code, date: c.aujourdhui);
    final derive = s.genre == genreDerive;
    final champs = <ChampDef>[
      const ChampDef(nom: 'prefixe', libelle: 'Préfixe', requis: true, aide: 'Lettres majuscules, chiffres ou tiret (16 caractères au plus).'),
      const ChampDef(nom: 'separateur', libelle: 'Séparateur après le préfixe', type: TypeChamp.select, requis: true, options: _separateurs),
      if (!derive) ...[
        const ChampDef(
            nom: 'annee',
            libelle: 'Année dans le numéro',
            type: TypeChamp.select,
            requis: true,
            options: [OptionChamp(anneeAucune, 'Aucune'), OptionChamp(anneeLongue, 'Sur quatre chiffres (AAAA)'), OptionChamp(anneeCourte, 'Sur deux chiffres (AA)')]),
        const ChampDef(
            nom: 'positionAnnee', libelle: 'Place de l’année', type: TypeChamp.select, requis: true, options: [OptionChamp(anneeAvant, 'Avant le rang'), OptionChamp(anneeApres, 'Après le rang')]),
        const ChampDef(nom: 'separateurAnnee', libelle: 'Séparateur de l’année', type: TypeChamp.select, options: _separateurs, aide: 'Vide : le séparateur après le préfixe.'),
        const ChampDef(nom: 'largeur', libelle: 'Longueur du rang (chiffres)', type: TypeChamp.nombre, requis: true),
        const ChampDef(nom: 'remiseAnnuelle', libelle: 'Le rang repart à 1 chaque année', type: TypeChamp.case_),
      ],
      const ChampDef(
          nom: 'dateEffet',
          libelle: 'Effective à partir du',
          type: TypeChamp.date,
          requis: true,
          aide: 'Au plus tôt aujourd’hui : les pièces déjà émises gardent leur numéro, seules les pièces à venir suivent le nouveau format.'),
      const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, requis: true, col: ColChamp.plein),
    ];
    final ctl = ControleurFormulaire(champs, {
      'prefixe': s.prefixe,
      'separateur': s.separateur,
      'annee': s.annee,
      'positionAnnee': s.positionAnnee,
      'separateurAnnee': s.separateurAnnee ?? '',
      'largeur': '${s.largeur}',
      'remiseAnnuelle': s.remiseAnnuelle,
      'dateEffet': _iso(c.aujourdhui),
    });
    afficherModale<void>(ctx,
        titre: 'Modifier la série : ${s.libelle}',
        sousTitre: 'Format en vigueur : ${s.formatLisible}${s.aValider ? ' (proposition à valider)' : ''}',
        taille: TailleModale.md,
        corps: FormulaireSigh(controleur: ctl),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('cfb:numerotation:enregistrer'),
                  libelle: 'Enregistrer',
                  icone: LucideIcons.save,
                  onPressed: () {
                    final saisie = ctl.valider();
                    if (saisie == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final valeurs = <String, Object?>{
                      'prefixe': '${saisie['prefixe'] ?? ''}'.trim().toUpperCase(),
                      'separateur': '${saisie['separateur'] ?? ''}',
                      if (!derive) ...{
                        'annee': saisie['annee'],
                        'positionAnnee': saisie['positionAnnee'],
                        'separateurAnnee': '${saisie['separateurAnnee'] ?? ''}',
                        'largeur': int.tryParse('${saisie['largeur'] ?? ''}'.trim()) ?? -1,
                        'remiseAnnuelle': saisie['remiseAnnuelle'] == true,
                      },
                    };
                    final r = ServiceValidationsDeposees.de(c.magasin).modifierSerie(code, valeurs, '${saisie['dateEffet']}',
                        role: c.role, acteur: acteurNom(c), estMere: !_depose, motif: '${saisie['motif'] ?? ''}', gestes: droitsGestesEcran(c));
                    if (r.refus != null) {
                      ToastsSigh.afficher(ctx, r.refus!.motif, type: TypeToast.erreur, detail: r.refus!.geste, duree: const Duration(seconds: 10));
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, r.version != null ? 'Nouvelle version de la série enregistrée.' : 'Modification transmise à la mère, en attente de confirmation.',
                        type: r.version != null ? TypeToast.succes : TypeToast.info,
                        detail: r.version != null
                            ? 'Effective à partir du ${_jourFr('${saisie['dateEffet']}')} pour les pièces à venir. Elle part vers les fileuls.'
                            : 'La mère l’applique sous votre rôle, contrôles refaits ; d’ici là, le format actuel s’applique.');
                  }),
            ]);
  }
}

const _fiscales = ['caisse.factures', 'caisse.proformas', 'caisse.avoirs'];

const _separateurs = [OptionChamp('-', 'Tiret ( - )'), OptionChamp('/', 'Barre oblique ( / )'), OptionChamp('_', 'Soulignement ( _ )'), OptionChamp('.', 'Point ( . )'), OptionChamp('', 'Aucun')];

/// `AAAA-MM-JJ` → `JJ/MM/AAAA` (une date absente : « — »).
String _jourFr(String? iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso ?? '');
  return m == null ? '—' : '${m[3]}/${m[2]}/${m[1]}';
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Widget _mono(String t) => Text(t, style: const TextStyle(fontFamily: 'LiberationMono', fontSize: 12, color: JetonsShell.slate900));
