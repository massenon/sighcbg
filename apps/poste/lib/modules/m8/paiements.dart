import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/icones.dart';
import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/parcours_caisse.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import 'annonce_normalisation.dart';
import 'commun.dart';
import 'factures.dart';
import 'impression.dart';
import 'saisie_versements.dart';

/// `m8-paiements` — écran de travail de la caisse : il ne crée pas de facture, il ENCAISSE celles qui sont dues.
class EcranPaiements extends StatefulWidget with EcranMaquette {
  const EcranPaiements({super.key});

  @override
  String get description =>
      'Encaissements par espèces, terminal de paiement électronique, MTN Mobile Money et Moov Money.';

  @override
  String get regle =>
      'Écran de travail de la caisse : il ne crée pas de facture mais encaisse celles qui sont dues. Une facture se corrige depuis l’émission ou par un avoir — jamais par retouche d’un règlement déjà passé (RG-12).';

  @override
  State<EcranPaiements> createState() => _EcranPaiementsState();
}

class _EcranPaiementsState extends State<EcranPaiements> {
  CollectionMagasin? _col;
  CollectionMagasin? _versements;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final col = ContexteEcran.of(context).magasin.collection('factures');
    if (!identical(col, _col)) {
      _col?.removeListener(_maj);
      _col = col..addListener(_maj);
      _versements?.removeListener(_maj);
      _versements = ContexteEcran.of(context).magasin.collection(colVersements)..addListener(_maj);
    }
  }

  @override
  void dispose() {
    _col?.removeListener(_maj);
    _versements?.removeListener(_maj);
    super.dispose();
  }

  void _maj() => setState(() {});

  List<Fiche> get _aRegler => [
        for (final f in _col!.actives)
          if (n(f['reliquat']) > 0) f
      ];

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final actives = _col!.actives;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // LES KPI PAR MODE lisent les VERSEMENTS (Direction, 20/11/2026) : un règlement 5 000 Mobile Money + 3 000 espèces compte 5 000 d'un côté et 3 000 de l'autre.
      KpiGrilleSigh(kpis: [
        for (final t in typesParMode(c.magasin, actives))
          () {
            final vs = [for (final f in actives) ...versementsDeFacture(f, c.magasin.collection(colVersements).toutes).where((v) => v.type == t.$1)];
            return KpiSigh(
                libelle: t.$2,
                valeur: money(vs.fold<num>(0, (a, v) => a + v.montant)),
                icone: icone(iconeDeMode(t.$1)),
                indice: '${nombre(vs.length)} versement(s)');
          }(),
      ]),
      const SizedBox(height: 16),
      OngletsSigh(onglets: [
        OngletDef(
            id: 'aregler',
            libelle: 'À encaisser',
            compte: _aRegler.length,
            construire: (ctx) => TableauSigh(
                  colonnes: [
                    colNumero,
                    colDate,
                    colPatient,
                    colMontant,
                    ColonneTableau(
                        cle: 'montantPaye',
                        libelle: 'Déjà réglé',
                        droite: true,
                        texte: (f) => m(f['montantPaye']),
                        valeurExport: (f) => valeurExportNombre(f['montantPaye'])),
                    colReliquat,
                    colStatutPaiement,
                  ],
                  lignes: _aRegler,
                  triInitial: 'date',
                  sensInitial: 'desc',
                  nomExport: 'factures-a-encaisser',
                  messageVide: 'Aucune facture en attente de règlement.',
                  actionsLigne: (context, f) => [
                    // Encaisser est une ÉCRITURE : la commande est absente sans le droit d'éditer (jamais grisée).
                    if (c.droit.editer)
                      BoutonSigh(
                          libelle: 'Encaisser',
                          icone: LucideIcons.banknote,
                          taille: TailleBouton.sm,
                          onPressed: () => _encaisser(context, f)),
                  ],
                )),
        OngletDef(
            id: 'historique',
            libelle: 'Historique des règlements',
            construire: (ctx) => TableauSigh(
                  colonnes: [
                    colNumero,
                    colDate,
                    colPatient,
                    ColonneTableau(
                        cle: 'modePaiement',
                        libelle: 'Mode de règlement',
                        texte: (f) => modeDeFacture(c.magasin, f),
                        rendu: (_, f) => BadgeSigh(modeDeFacture(c.magasin, f),
                            ton: TonSigh.navy)),
                    ColonneTableau(
                        cle: 'montantPaye',
                        libelle: 'Montant réglé',
                        droite: true,
                        texte: (f) => m(f['montantPaye']),
                        valeurExport: (f) => valeurExportNombre(f['montantPaye']),
                        rendu: (_, f) => Text(m(f['montantPaye']),
                            style: const TextStyle(
                                color: JetonsShell.success700,
                                fontSize: 14,
                                height: 20 / 14,
                                fontWeight: FontWeight.w600))),
                    colReliquat,
                    colStatutPaiement,
                  ],
                  lignes: [
                    for (final f in actives)
                      if (n(f['montantPaye']) > 0) f
                  ],
                  taillePage: 15,
                  triInitial: 'date',
                  sensInitial: 'desc',
                  nomExport: 'paiements',
                  // « Imprimer la sélection » : le reçu COMPLET de chaque règlement coché, un par page (le même que « Reçu de paiement »).
                  documentLigne: (ctx, f) => pieceRecuDe(ctx, f),
                  filtres: [
                    FiltreTableau(
                        nom: 'modePaiement',
                        libelle: 'Mode',
                        options: [
                          for (final t in typesParMode(c.magasin, actives)) OptionChamp(t.$1, t.$2),
                          OptionChamp(modeMixte, modeLabel(modeMixte)),
                        ])
                  ],
                  actionsLigne: (context, f) => [
                    BoutonIcone(
                        icone: LucideIcons.printer,
                        libelle: 'Reçu de paiement',
                        onPressed: () => imprimerRecu(context, f)),
                    // ANNULER UN RÈGLEMENT : un geste RÉSERVÉ (la commande est ABSENTE sans le droit, le caissier n'annule pas) ; le moteur le revérifie.
                    if (gestesEcran(c).peut(c.role, gesteVersementAnnuler) && versementsDeFacture(f, c.magasin.collection(colVersements).toutes).any((v) => !v.implicite))
                      BoutonIcone(icone: LucideIcons.undo2, libelle: 'Annuler un règlement', onPressed: () => _annulerReglement(context, f))
                  ],
                )),
      ]),
    ]);
  }

  /// Annuler un règlement (contre-passation) : le versement choisi et ceux du même règlement reçoivent une contre-passation tracée ; le motif est obligatoire.
  void _annulerReglement(BuildContext ctx, Fiche f) {
    final c = ContexteEcran.of(ctx);
    final vs = [for (final v in versementsDeFacture(f, c.magasin.collection(colVersements).toutes)) if (!v.implicite) v];
    final types = c.magasin.collection(colTypesVersement).toutes;
    final form = ControleurFormulaire([
      ChampDef(
          nom: 'versement',
          libelle: 'Versement à annuler (avec ceux du même règlement)',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [for (final v in vs) OptionChamp('${v.id}', '${libelleDeType(types, v.type, repli: modeLabel)} — ${money(v.montant)} — ${dateDe(v.date)}${v.reference.isEmpty ? '' : ' — réf. ${v.reference}'}')]),
      const ChampDef(nom: 'motif', libelle: 'Motif de l’annulation', type: TypeChamp.textarea, requis: true, lignes: 2, col: ColChamp.plein),
    ]);
    afficherModale<void>(ctx,
        titre: 'Annuler un règlement',
        sousTitre: '${f['numero']} — ${f['patient']}',
        corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const NoteSigh(
              'Un versement ne se supprime jamais : l’annulation écrit une CONTRE-PASSATION par versement du règlement (motif obligatoire, écriture comptable inverse en brouillon) et remet les prestations en attente de règlement. Refusée si une prestation est déjà exécutée ou si la facture est normalisée.',
              ton: TonSigh.attention),
          const SizedBox(height: 12),
          FormulaireSigh(controleur: form),
        ]),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Fermer', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  libelle: 'Contre-passer le règlement',
                  icone: LucideIcons.undo2,
                  onPressed: () {
                    final v = form.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    try {
                      final r = contrepasserVersement(c.magasin, '${v['versement']}',
                          motif: '${v['motif']}', maintenant: c.aujourdhui, droit: () => gestesEcran(c).peut(c.role, gesteVersementAnnuler));
                      fermer();
                      ToastsSigh.afficher(ctx, 'Règlement annulé : ${nombre(r.contrepassations.length)} contre-passation(s).',
                          type: TypeToast.succes, detail: 'Reste dû ${money(r.facture['reliquat'])}. Écriture inverse posée en brouillon.');
                    } on RefusCaisse catch (e) {
                      ToastsSigh.afficher(ctx, 'Annulation refusée.', type: TypeToast.erreur, detail: e.motif, duree: const Duration(seconds: 10));
                    }
                  }),
            ]);
  }

  void _encaisser(BuildContext ctx, Fiche f) {
    final reste = n(f['reliquat']);
    final cx = ContexteEcran.of(ctx);
    // LES VERSEMENTS (Direction, 20/11/2026) : « Montant à encaisser » est la somme que les versements doivent totaliser ; le caissier la répartit en un ou plusieurs versements.
    final form = ControleurFormulaire(const [
      ChampDef(nom: 'montant', libelle: 'Montant à encaisser (FCFA)', type: TypeChamp.nombre, requis: true),
      ChampDef(nom: 'observation', libelle: 'Observation', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
    ], {
      'montant': '${reste.round()}',
    });
    num montantSaisi() => n(num.tryParse('${form['montant']}'.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.')) ?? 0);
    final sv = SaisieVersements(
        magasin: cx.magasin,
        aRepartir: montantSaisi,
        toast: (titre, detail) => ToastsSigh.afficher(ctx, titre, type: TypeToast.erreur, detail: detail));
    form.addListener(() => sv.version.value++);
    afficherModale<void>(ctx,
        titre: 'Encaissement',
        sousTitre: '${f['numero']} — ${f['patient']}',
        corps: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DescListeSigh([
                ('Facture', f['numero']),
                ('Patient', f['patient']),
                ('Montant total', money(f['montantTTC'])),
                ('Part patient', money(f['partPatient'])),
                ('Déjà réglé', money(f['montantPaye'])),
                ('Reste à payer', money(f['reliquat'])),
              ]),
              const SizedBox(height: 12),
              FormulaireSigh(controleur: form),
              const SizedBox(height: 12),
              sv.construire(),
              const SizedBox(height: 12),
              // Facture d'un PATIENT : normalisée sans acheteur ni AIB (Direction de Baguidi, 16/11/2026, E3770) — plus de fenêtre « Facture normalisée ».
              if (mecefEnService(cx.magasin)) const NoteSigh(mecefMentionFacturePatient, icone: LucideIcons.receipt),
            ]),
        pied: (fermer) => [
              BoutonSigh(
                  libelle: 'Annuler',
                  variante: VarianteBouton.secondaire,
                  onPressed: fermer),
              BoutonSigh(
                  libelle: 'Valider l’encaissement',
                  icone: LucideIcons.check,
                  onPressed: () {
                    final v = form.valider();
                    if (v == null) {
                      ToastsSigh.afficher(
                          ctx, 'Le formulaire comporte des erreurs.',
                          type: TypeToast.erreur);
                      return;
                    }
                    final montant = n(v['montant']);
                    if (montant <= 0) {
                      ToastsSigh.afficher(
                          ctx, 'Le montant doit être supérieur à zéro.',
                          type: TypeToast.erreur);
                      return;
                    }
                    // Refus nommé : on n'encaisse jamais plus que le reste dû.
                    if (montant > reste) {
                      ToastsSigh.afficher(ctx,
                          'Le montant dépasse le reste dû (${money(reste)}).',
                          type: TypeToast.erreur);
                      return;
                    }
                    final saisis = sv.finaliser();
                    if (saisis == null) return;
                    // L'encaissement passe par le MOTEUR (E2260) : lignes réglées, analyses et imagerie libérées, tâches d'aval, base MECeF et ÉCRITURE
                    // comptable (571, 411 de la part assureur, 706). Un encaissement ne s'annule pas : remboursement ou avoir.
                    final c = ContexteEcran.of(ctx);
                    final ResultatCaisse res;
                    try {
                      res = encaisserFacture(c.magasin, '${f['id']}',
                          montant: montant,
                          versements: saisis,
                          maintenant: c.aujourdhui);
                    } on RefusCaisse catch (e) {
                      ToastsSigh.afficher(ctx, 'Encaissement refusé.',
                          type: TypeToast.erreur,
                          detail: e.motif,
                          duree: const Duration(seconds: 9));
                      return;
                    }
                    if (!(res.montantRegle > 0)) {
                      ToastsSigh.afficher(ctx,
                          'Ce versement ne couvre entièrement aucune ligne de la pièce : régler une ou plusieurs prestations en entier.',
                          type: TypeToast.erreur);
                      return;
                    }
                    // La référence de la transaction et l'observation s'ÉCRIVENT sur la facture (même champ que m8-caisse) : elles ne
                    // vivaient que sur le reçu imprimé une fois, et la réimpression affichait un tiret.
                    final obs = '${v['observation'] ?? ''}'.trim();
                    if (obs.isNotEmpty) {
                      c.magasin.collection('factures').mettreAJour('${f['id']}', {'observationReglement': obs});
                    }
                    fermer();
                    annoncerNormalisation(ctx, res.normalisation);
                    ToastsSigh.afficher(ctx,
                        'Encaissement de ${money(res.montantRegle)} enregistré.',
                        type: TypeToast.succes,
                        detail: (res.restantDu > 0
                                ? 'Reliquat de ${money(res.restantDu)}.'
                                : 'Facture soldée.') +
                            (res.ecritures.isNotEmpty
                                ? ' Écriture comptable posée en brouillon.'
                                : ''));
                    imprimerRecu(ctx, _col!.parId(f['id'])!);
                  }),
            ]);
  }
}
