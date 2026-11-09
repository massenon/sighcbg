import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import 'pv_crud.dart';

String _m(Object? v) => money(v, avecDevise: false);
String _date(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : dateFR(d);
}

/// Les champs de la modale « Modifier ». Leurs NOMS ne sont pas ceux de la fiche (`numero`, `montant` au lieu de `numeroFournisseur`,
/// `montantFacture`) : le formulaire s'ouvre avec ces deux champs vides et ce qu'il écrit n'est lu par aucune colonne (écart E21, porté
/// fidèlement). « payée » et non « soldée » : le registre, son filtre et la dette du BFR comptent sur `payee`.
final champsFactureFournisseur = <ChampDef>[
  const ChampDef(nom: 'numero', libelle: 'N° de facture', requis: true),
  const ChampDef(
      nom: 'date',
      libelle: 'Date de facture',
      type: TypeChamp.date,
      requis: true),
  const ChampDef(nom: 'fournisseur', libelle: 'Fournisseur', requis: true),
  const ChampDef(
      nom: 'montant', libelle: 'Montant (FCFA)', type: TypeChamp.nombre),
  const ChampDef(nom: 'echeance', libelle: 'Échéance', type: TypeChamp.date),
  ChampDef(
      nom: 'statutPaiement',
      libelle: 'Règlement',
      type: TypeChamp.select,
      options: [
        for (final e in reglementsFournisseur.entries)
          OptionChamp(e.key, e.value.$1)
      ].reversed.toList()),
];

TonSigh _ton(String t) => switch (t) {
      'succes' => TonSigh.succes,
      'attention' => TonSigh.attention,
      'danger' => TonSigh.danger,
      _ => TonSigh.neutre,
    };

Widget _badgeReglement(Object? s) {
  final x = reglementsFournisseur['$s'];
  return x == null
      ? BadgeSigh('${s ?? '—'}')
      : BadgeSigh(x.$1, ton: _ton(x.$2));
}

Widget _ecart(Fiche r) => ecartConforme(r)
    ? const BadgeSigh('Conforme', ton: TonSigh.succes)
    : Text('${(r['ecart'] as num) > 0 ? '+' : ''}${_m(r['ecart'])}',
        style: const TextStyle(
            color: JetonsShell.danger600,
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w600));

/// Le tiroir d'une facture : la fiche, puis le verdict du rapprochement.
Widget detailFactureFournisseur(Fiche r) {
  final anomalie = r['statutRappro'] == 'anomalie';
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    DescListeSigh([
      ('Référence interne', r['reference']),
      ('N° fournisseur', r['numeroFournisseur']),
      ('Fournisseur', r['fournisseurNom']),
      ('Date', _date(r['date'])),
      ('Commande', r['commandeRef']),
      ('Bordereau de livraison', r['blRef']),
      ('Montant livré', money(r['montantLivraison'])),
      ('Montant facturé', money(r['montantFacture'])),
      (
        'Écart',
        ecartConforme(r)
            ? const BadgeSigh('Conforme', ton: TonSigh.succes)
            : BadgeSigh(money(r['ecart']), ton: TonSigh.danger)
      ),
      ('Échéance', _date(r['echeance'])),
      if (r['retenueAib'] is Map)
        (
          'Retenue AIB',
          '${money((r['retenueAib'] as Map)['montant'])} (${(r['retenueAib'] as Map)['taux']} % de ${money((r['retenueAib'] as Map)['base'])}, catégorie ${(r['retenueAib'] as Map)['code']}) — à reverser à l’État le ${_date((r['retenueAib'] as Map)['reversement'])}'
        ),
    ]),
    const SizedBox(height: 16),
    if (anomalie)
      const NoteSigh(
          'Anomalie de rapprochement. Le montant facturé ne correspond pas au montant effectivement livré. Le règlement doit être suspendu jusqu’à régularisation avec le fournisseur.',
          ton: TonSigh.danger,
          icone: LucideIcons.triangleAlert)
    else
      const NoteSigh(
          'Rapprochement conforme : commande, livraison et facture concordent.',
          ton: TonSigh.succes,
          icone: LucideIcons.circleCheck),
  ]);
}

/// `m7-factures-fournisseurs` — « Factures fournisseurs » : rapprochement pro-forma → validation → facture normalisée → bordereau de livraison.
/// La facture « payée » sort des impayées ; une pièce non payée pèse sur le BFR par son montant facturé.
class EcranFacturesFournisseurs extends StatelessWidget with EcranMaquette {
  const EcranFacturesFournisseurs({super.key});

  @override
  String get titre => 'Factures fournisseurs';

  @override
  String get description =>
      'Rapprochement facture pro-forma → validation → facture normalisée → bordereau de livraison.';

  @override
  String get regle =>
      'Le système détecte les incohérences commande ≠ livraison et livraison ≠ facture et génère une anomalie.';

  @override
  Widget build(BuildContext context) {
    final c = ContexteEcran.of(context);
    final col = c.magasin.collection('facturesFournisseurs');
    return ListenableBuilder(
      listenable: col,
      builder: (context, _) {
        final rows = col.actives;
        final k = kpisFacturesFournisseurs(rows);
        final note = noteAnomalies(rows);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (note != null) ...[
                NoteSigh(note,
                    ton: TonSigh.danger, icone: LucideIcons.triangleAlert),
                const SizedBox(height: 16),
              ],
              KpiGrilleSigh(kpis: [
                KpiSigh(
                    libelle: 'Factures fournisseurs',
                    valeur: nombre(k.total),
                    icone: LucideIcons.fileText),
                KpiSigh(
                    libelle: 'Rapprochées',
                    valeur: nombre(k.rapprochees),
                    icone: LucideIcons.circleCheck,
                    ton: TonSigh.succes),
                KpiSigh(
                    libelle: 'Anomalies',
                    valeur: nombre(k.anomalies),
                    icone: LucideIcons.triangleAlert,
                    ton: TonSigh.danger),
                KpiSigh(
                    libelle: 'Impayées',
                    valeur: money(k.impayees),
                    icone: LucideIcons.wallet,
                    ton: TonSigh.attention),
              ]),
              const SizedBox(height: 16),
              TableauSigh(
                titre: 'Factures fournisseurs',
                taillePage: 12,
                triInitial: 'date',
                sensInitial: 'desc',
                nomExport: 'factures-fournisseurs',
                lignes: rows,
                filtres: [
                  const FiltreTableau(
                      nom: 'statutRappro',
                      libelle: 'Rapprochement',
                      options: [
                        OptionChamp('rapproche', 'Rapprochée'),
                        OptionChamp('anomalie', 'Anomalie')
                      ]),
                  FiltreTableau(
                      nom: 'statutPaiement',
                      libelle: 'Règlement',
                      options: [
                        for (final e in reglementsFournisseur.entries)
                          OptionChamp(e.key, e.value.$1)
                      ]),
                  FiltreTableau(
                      nom: 'fournisseur',
                      libelle: 'Fournisseur',
                      options: [
                        for (final f in c.magasin.collection('fournisseurs').actives)
                          OptionChamp('${f['code']}', '${f['nom']}')
                      ]),
                ],
                colonnes: [
                  ColonneTableau(
                      cle: 'reference',
                      libelle: 'N° interne',
                      sansCoupure: true,
                      texte: (r) => '${r['reference'] ?? ''}',
                      rendu: (_, r) => Text('${r['reference'] ?? ''}',
                          style: const TextStyle(
                              fontFamily: 'LiberationMono',
                              fontSize: 12,
                              height: 16 / 12,
                              color: JetonsShell.slate800))),
                  const ColonneTableau(
                      cle: 'numeroFournisseur',
                      libelle: 'N° fournisseur',
                      sansCoupure: true),
                  ColonneTableau(
                      cle: 'date',
                      libelle: 'Date',
                      sansCoupure: true,
                      texte: (r) => _date(r['date'])),
                  const ColonneTableau(
                      cle: 'fournisseurNom', libelle: 'Fournisseur'),
                  ColonneTableau(
                      cle: 'blRef',
                      libelle: 'BL rattaché',
                      sansCoupure: true,
                      texte: (r) => '${r['blRef'] ?? ''}',
                      rendu: (_, r) => Text('${r['blRef'] ?? ''}',
                          style: const TextStyle(
                              fontFamily: 'LiberationMono',
                              fontSize: 12,
                              height: 16 / 12,
                              color: JetonsShell.slate500))),
                  ColonneTableau(
                      cle: 'montantLivraison',
                      libelle: 'Montant livré',
                      droite: true,
                      texte: (r) => _m(r['montantLivraison'])),
                  ColonneTableau(
                      cle: 'montantFacture',
                      libelle: 'Montant facturé',
                      droite: true,
                      texte: (r) => _m(r['montantFacture']),
                      rendu: (_, r) => Text(_m(r['montantFacture']),
                          style: const TextStyle(
                              color: JetonsShell.slate700,
                              fontSize: 14,
                              height: 20 / 14,
                              fontWeight: FontWeight.w600))),
                  ColonneTableau(
                      cle: 'ecart',
                      libelle: 'Écart',
                      droite: true,
                      texte: (r) => _m(r['ecart']),
                      rendu: (_, r) => _ecart(r)),
                  ColonneTableau(
                      cle: 'retenueAib',
                      libelle: 'Retenue AIB',
                      droite: true,
                      texte: (r) => r['retenueAib'] is Map ? _m((r['retenueAib'] as Map)['montant']) : '—'),
                  ColonneTableau(
                      cle: 'echeance',
                      libelle: 'Échéance',
                      sansCoupure: true,
                      texte: (r) => _date(r['echeance'])),
                  ColonneTableau(
                      cle: 'statutPaiement',
                      libelle: 'Règlement',
                      texte: (r) =>
                          reglementsFournisseur['${r['statutPaiement']}']?.$1 ??
                          '${r['statutPaiement'] ?? ''}',
                      rendu: (_, r) => _badgeReglement(r['statutPaiement'])),
                ],
                alClicLigne: (r) => afficherTiroir<void>(context,
                    titre: 'Facture ${r['reference']}',
                    sousTitre: '${r['fournisseurNom']} — ${_date(r['date'])}',
                    corps: detailFactureFournisseur(r)),
                actionsLigne: (ctx, r) => [
                  if (c.droit.editer)
                    BoutonIcone(
                        icone: LucideIcons.pencil,
                        libelle: 'Modifier',
                        onPressed: () => ouvrirFormulaireFiche(ctx,
                            collection: col,
                            champs: champsFactureFournisseur,
                            versFiche: patchEditionFacture,
                            entite: 'facture fournisseur',
                            record: r,
                            detailMessage: false,
                            identifiant: (f) =>
                                '${f['reference'] ?? f['numero'] ?? f['code'] ?? f['id']}')),
                  if (c.droit.editer && r['retenueAib'] is! Map)
                    BoutonIcone(
                        icone: LucideIcons.percent,
                        libelle: 'Retenir l’AIB',
                        onPressed: () => _retenirAib(ctx, c, r)),
                  if (c.droit.annuler)
                    BoutonIcone(
                        icone: LucideIcons.archive,
                        libelle: 'Archiver',
                        onPressed: () => archiverAvecMotif(ctx, col, r)),
                ],
              ),
            ]);
      },
    );
  }
}

/// « Retenir l'AIB » : la retenue se CALCULE au barème daté (jamais saisie), se constate par une pièce plate en brouillon (RG-10), et la facture la PORTE.
/// Refus nommés : aucun taux arrêté en vigueur, facture déjà retenue, exercice en clôture.
void _retenirAib(BuildContext ctx, ContexteEcran c, Fiche r) {
  final refus = cpdControlerRetenueFacture(r);
  if (refus != null) {
    ToastsSigh.afficher(ctx, 'Retenue refusée.', type: TypeToast.erreur, detail: refus);
    return;
  }
  final date = DateTime.tryParse('${r['date'] ?? ''}') ?? c.aujourdhui;
  final bareme = c.magasin.collection('baremeAIB').actives;
  final applicables = [
    for (final b in cpdBaremeEnVigueur(bareme, date))
      if (b.reponse.taux != null) b
  ];
  if (applicables.isEmpty) {
    ToastsSigh.afficher(ctx, 'Retenue impossible.',
        type: TypeToast.erreur,
        detail:
            'Aucun taux d’AIB arrêté n’est en vigueur à la date de la facture (${dateFR(date)}). La Direction arrête le barème dans Paramètres, « Acompte sur impôt (AIB) ».');
    return;
  }
  final base = (r['montantFacture'] as num?) ?? 0;
  final ctl = ControleurFormulaire([
    ChampDef(
        nom: 'code',
        libelle: 'Catégorie de retenue',
        type: TypeChamp.select,
        requis: true,
        options: [for (final b in applicables) OptionChamp(b.code, '${b.libelle} — ${b.reponse.taux} %')]),
    const ChampDef(
        nom: 'base',
        libelle: 'Base de la retenue (FCFA)',
        type: TypeChamp.nombre,
        requis: true,
        aide: 'Par défaut le montant facturé. Le montant retenu = base × taux du barème à la date de la facture, arrondi au franc.'),
  ], {'code': applicables.first.code, 'base': '${base.round()}'});
  afficherModale<void>(ctx,
      titre: 'Retenir l’AIB — ${r['reference']}',
      sousTitre: '${r['fournisseurNom']} : ${money(base)} facturés le ${dateFR(date)}',
      corps: FormulaireSigh(controleur: ctl),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            BoutonSigh(
                libelle: 'Constater la retenue',
                icone: LucideIcons.check,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) {
                    ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                    return;
                  }
                  final CpdRetenueAib ret;
                  final List<Map<String, Object?>> lignes;
                  try {
                    ret = cpdCalculerRetenueAib(bareme, '${v['code']}', num.tryParse('${v['base']}'.trim()) ?? 0, date);
                    lignes = cpdEcrituresRetenueAib(
                        retenue: ret,
                        numero: 'AIB-${r['reference']}',
                        date: iso(date),
                        reference: '${r['reference']}',
                        fournisseur: '${r['fournisseurNom']}',
                        pieceId: '${r['id']}');
                  } on RefusRetenueAib catch (e) {
                    ToastsSigh.afficher(ctx, 'Retenue refusée.', type: TypeToast.erreur, detail: e.motif, duree: const Duration(seconds: 9));
                    return;
                  }
                  final ecr = c.magasin.collection('ecritures');
                  final ids = <Object?>[];
                  final annulations = <VoidCallback>[];
                  try {
                    for (final l in lignes) {
                      final x = ecr.inserer(l, prefixe: 'ECR');
                      ids.add(x.fiche['id']);
                      annulations.add(x.annuler);
                    }
                  } on EcritureRefusee catch (e) {
                    for (final a in annulations) {
                      a();
                    }
                    ToastsSigh.afficher(ctx, 'Écriture refusée.', type: TypeToast.erreur, detail: e.motif);
                    return;
                  }
                  c.magasin.collection('facturesFournisseurs').mettreAJour(r['id'], {
                    'retenueAib': {
                      ...ret.versFiche(),
                      'date': iso(date),
                      'reversement': iso(cpdEcheanceReversementAib(date)),
                      'ecritureIds': ids,
                      'retenuPar': acteur(c).nom,
                      'retenueLe': iso(c.aujourdhui),
                    }
                  });
                  c.magasin.journaliser('Retenue d’AIB sur facture fournisseur', 'M7', 'FactureFournisseur', '${r['reference']}', null,
                      {'taux': ret.taux, 'base': ret.base, 'montant': ret.montant, 'code': ret.code});
                  fermer();
                  ToastsSigh.afficher(ctx, 'Retenue de ${money(ret.montant)} constatée (brouillon).',
                      type: TypeToast.succes,
                      detail: '${ret.taux} % — à reverser à l’État le ${dateFR(cpdEcheanceReversementAib(date))} (compte $cpdCompteAibRetenu).');
                }),
          ]);
}
