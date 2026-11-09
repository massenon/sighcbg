import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../donnees/magasin.dart';
import '../../donnees/parametres_aib.dart';
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
      nom: 'montant',
      libelle: 'Montant facturé (FCFA)',
      type: TypeChamp.nombre),
  // D7 (Direction, 09/11/2026) : le montant HORS TAXES est la base de la retenue d'AIB (Paramètres, « Validation de la base de l’AIB des factures
  // fournisseurs »). Facultatif — sans lui, la retenue se rabat sur le montant facturé et le dit ; la TVA, sur une ligne séparée, l'est aussi.
  _champHt(null),
  const ChampDef(
      nom: 'montantTVA',
      libelle: 'TVA (FCFA, ligne séparée)',
      type: TypeChamp.nombre,
      aide: 'Facultative : hors taxes + TVA = montant facturé.'),
  // L'AIB FACTURÉ par le fournisseur (position de la Direction du 09/11/2026) : facultatif, trois champs qui vont ensemble, en francs entiers. Le montant doit
  // être cohérent avec la base hors taxes et le taux ; « Constater l'AIB subi » (action de la ligne) le pose ensuite en créance sur l'État.
  ..._champsAib(null, null),
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

/// Le champ « Montant hors taxes » : la cohérence se contrôle au montant de la modale, sinon à [factureDeLaFiche] (le montant facturé que porte la fiche).
ChampDef _champHt(Object? factureDeLaFiche) => ChampDef(
    nom: 'montantHT',
    libelle: 'Montant hors taxes (FCFA)',
    type: TypeChamp.nombre,
    aide:
        'Facultatif. Base de la retenue d’AIB quand les Paramètres retiennent le hors-taxes ; vide, la retenue se calcule sur le montant facturé, en le disant.',
    valider: (v, vals) => cpaControlerMontantsFacture(
        ht: v,
        tva: vals['montantTVA'],
        facture: '${vals['montant'] ?? ''}'.isEmpty
            ? factureDeLaFiche
            : vals['montant']));

/// Le contrôle de l'AIB facturé, commun aux trois champs (chacun l'appelle avec SA valeur) : la COHÉRENCE se contrôle ici, le contrôle du domaine nomme son refus ;
/// un AIB subi déjà constaté FIGE les trois — la facture le porte, elle n'est pas réécrite. Un champ vide n'est pas validé par le formulaire : c'est
/// pourquoi les trois champs portent le même contrôle (un montant oublié se lit sur le taux et la base saisis).
String? _controleAib(Object? montant, Object? taux, Object? base,
    Object? factureDeLaFiche, Object? montantModale, Fiche? record) {
  final subi = record?['aibSubi'];
  final f = record?['aibFacture'];
  if (subi is Map && f is Map) {
    final change = '${montant ?? ''}'.trim() != '${f['montant']}' ||
        '${taux ?? ''}'.trim() != '${f['taux']}' ||
        '${base ?? ''}'.trim() != '${f['baseHt']}';
    if (change)
      return 'AIB_FACTURE_FIGEE : l’AIB subi est déjà constaté sur cette facture — la corriger se fait par une nouvelle pièce, jamais en la réécrivant.';
  }
  return cpdControlerAibFacture(
      montant: montant,
      taux: taux,
      base: base,
      montantFacture:
          '${montantModale ?? ''}'.isEmpty ? factureDeLaFiche : montantModale);
}

/// Les trois champs de l'AIB facturé : facultatifs, ensemble, en francs entiers.
List<ChampDef> _champsAib(Object? factureDeLaFiche, Fiche? record) => [
      ChampDef(
          nom: 'aibFactureMontant',
          libelle: 'AIB facturé — montant (FCFA)',
          type: TypeChamp.nombre,
          aide:
              'Facultatif : l’AIB que le fournisseur a facturé (francs entiers) = base hors taxes × taux. Les trois champs vont ensemble.',
          valider: (v, vals) => _controleAib(
              v,
              vals['aibFactureTaux'],
              vals['aibFactureBase'],
              factureDeLaFiche,
              vals['montant'],
              record)),
      ChampDef(
          nom: 'aibFactureTaux',
          libelle: 'AIB facturé — taux (%)',
          type: TypeChamp.nombre,
          aide:
              'Entier (1 % ou 5 % le plus souvent). Un taux hors barème arrêté est signalé, pas refusé.',
          valider: (v, vals) => _controleAib(
              vals['aibFactureMontant'],
              v,
              vals['aibFactureBase'],
              factureDeLaFiche,
              vals['montant'],
              record)),
      ChampDef(
          nom: 'aibFactureBase',
          libelle: 'AIB facturé — base hors taxes (FCFA)',
          type: TypeChamp.nombre,
          valider: (v, vals) => _controleAib(
              vals['aibFactureMontant'],
              vals['aibFactureTaux'],
              v,
              factureDeLaFiche,
              vals['montant'],
              record)),
    ];

/// Les champs de la modale pour la fiche [r] : ceux de la maquette, dont le hors-taxes se contrôle au montant facturé de la fiche, et l'AIB facturé à l'AIB
/// subi déjà constaté.
List<ChampDef> champsFactureFournisseurPour(Fiche r) {
  final aib = _champsAib(r['montantFacture'], r);
  return [
    for (final c in champsFactureFournisseur)
      if (c.nom == 'montantHT')
        _champHt(r['montantFacture'])
      else if (c.nom.startsWith('aibFacture'))
        aib.firstWhere((x) => x.nom == c.nom)
      else
        c
  ];
}

/// La fiche telle que la modale la relit : l'AIB facturé (objet `aibFacture`) est APLATI en ses trois champs de saisie.
Fiche ficheAvecAibAplati(Fiche r) {
  final a = r['aibFacture'];
  return {
    ...r,
    if (a is Map) 'aibFactureMontant': a['montant'],
    if (a is Map) 'aibFactureTaux': a['taux'],
    if (a is Map) 'aibFactureBase': a['baseHt'],
  };
}

/// Le patch de la modale « Modifier » (celui du domaine) PLUS le hors-taxes et la TVA, écrits sur la fiche sous leurs noms (`montantHT`, `montantTVA`) : un
/// champ vidé se retire de la fiche (un nul ne s'écrit pas), il n'écrit pas un zéro.
FicheFacture patchEditionAvecHt(Map<String, Object?> saisie) {
  final p = patchEditionFacture(saisie);
  num? n(Object? v) =>
      v is num ? v : num.tryParse('${v ?? ''}'.trim().replaceAll(',', '.'));
  final ht = n(saisie['montantHT']);
  final tva = n(saisie['montantTVA']);
  // L'AIB facturé incohérent n'est JAMAIS écrit à moitié : le formulaire l'a déjà refusé champ par champ, le moteur le refuse aussi.
  if (cpdControlerAibFacture(
          montant: saisie['aibFactureMontant'],
          taux: saisie['aibFactureTaux'],
          base: saisie['aibFactureBase']) !=
      null) {
    throw FormulaireInvalide(const ['aibFacture']);
  }
  // La cohérence avec le montant facturé est contrôlée au champ (`_champHt`), avant l'enregistrement.
  return {
    ...p,
    'montantHT': ht,
    'montantTVA': tva,
    // L'AIB facturé : l'objet de la facture, ou rien (trois champs vides : il se RETIRE, un nul ne s'écrit pas).
    'aibFacture': cpdAibFactureDepuisSaisie(
        montant: saisie['aibFactureMontant'],
        taux: saisie['aibFactureTaux'],
        base: saisie['aibFactureBase']),
  };
}

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
Widget detailFactureFournisseur(Fiche r, {String? signalTaux}) {
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
      if (r['montantHT'] != null) ('Montant hors taxes', money(r['montantHT'])),
      if (r['montantTVA'] != null)
        ('TVA (ligne séparée)', money(r['montantTVA'])),
      if (r['aibFacture'] is Map)
        (
          'AIB facturé',
          '${money((r['aibFacture'] as Map)['montant'])} (${(r['aibFacture'] as Map)['taux']} % de ${money((r['aibFacture'] as Map)['baseHt'])} hors taxes)'
        ),
      if (r['aibSubi'] is Map)
        (
          'AIB subi',
          'Créance de ${money((r['aibSubi'] as Map)['montant'])} sur l’État constatée au compte ${(r['aibSubi'] as Map)['compteSubi'] ?? '—'} (brouillon, journal des achats)'
        ),
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
          '${money((r['retenueAib'] as Map)['montant'])} (${(r['retenueAib'] as Map)['taux']} % de ${money((r['retenueAib'] as Map)['base'])}, situation ${(r['retenueAib'] as Map)['situation'] ?? (r['retenueAib'] as Map)['code']}) — à reverser à l’État le ${_date((r['retenueAib'] as Map)['reversement'])}${(r['retenueAib'] as Map)['baseMotif'] == null ? '' : '. ${(r['retenueAib'] as Map)['baseMotif']}'}'
        ),
    ]),
    if (signalTaux != null) ...[
      const SizedBox(height: 12),
      KeyedSubtree(
          key: const Key('aibsubi:signal-detail'),
          child: NoteSigh(signalTaux,
              ton: TonSigh.attention, icone: LucideIcons.triangleAlert)),
    ],
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
                        for (final f
                            in c.magasin.collection('fournisseurs').actives)
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
                      texte: (r) => r['retenueAib'] is Map
                          ? _m((r['retenueAib'] as Map)['montant'])
                          : '—'),
                  ColonneTableau(
                      cle: 'aibSubi',
                      libelle: 'AIB subi',
                      droite: true,
                      texte: (r) => r['aibSubi'] is Map
                          ? _m((r['aibSubi'] as Map)['montant'])
                          : (r['aibFacture'] is Map ? 'à constater' : '—')),
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
                    corps: detailFactureFournisseur(r,
                        signalTaux: _signalAib(c, r))),
                actionsLigne: (ctx, r) => [
                  if (c.droit.editer)
                    BoutonIcone(
                        icone: LucideIcons.pencil,
                        libelle: 'Modifier',
                        onPressed: () => ouvrirFormulaireFiche(ctx,
                            collection: col,
                            champs: champsFactureFournisseurPour(r),
                            versFiche: patchEditionAvecHt,
                            entite: 'facture fournisseur',
                            record: ficheAvecAibAplati(r),
                            detailMessage: false,
                            identifiant: (f) =>
                                '${f['reference'] ?? f['numero'] ?? f['code'] ?? f['id']}')),
                  if (c.droit.editer && r['retenueAib'] is! Map)
                    BoutonIcone(
                        icone: LucideIcons.percent,
                        libelle: 'Retenir l’AIB',
                        onPressed: () => _retenirAib(ctx, c, r)),
                  if (c.droit.editer &&
                      r['aibFacture'] is Map &&
                      r['aibSubi'] is! Map)
                    BoutonIcone(
                        icone: LucideIcons.landmark,
                        libelle: 'Constater l’AIB subi',
                        onPressed: () => _constaterAibSubi(ctx, c, r)),
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
    ToastsSigh.afficher(ctx, 'Retenue refusée.',
        type: TypeToast.erreur, detail: refus);
    return;
  }
  final date = DateTime.tryParse('${r['date'] ?? ''}') ?? c.aujourdhui;
  final bareme = c.magasin.collection('baremeAib').actives;
  final situations = c.magasin.collection('situationsAib').actives;
  final applicables = [
    for (final b in cpdBaremeEnVigueur(situations, bareme, date))
      if (b.reponse.taux != null) b
  ];
  if (applicables.isEmpty) {
    ToastsSigh.afficher(ctx, 'Retenue impossible.',
        type: TypeToast.erreur,
        detail:
            'Aucun taux d’AIB arrêté n’est en vigueur à la date de la facture (${dateFR(date)}). La Direction arrête le barème dans Paramètres, « Acompte sur impôt (AIB) ».');
    return;
  }
  // D7 : la BASE vient des Paramètres (version en vigueur à la date de la facture) : le hors-taxes quand il est renseigné, sinon le montant facturé — et
  // la fenêtre DIT laquelle des deux sert.
  final baseCalculee = cpaBaseRetenue(r, parametresAib(c.magasin, date));
  // Les COMPTES de la pièce se lisent aux Paramètres, à la date de la facture : la pièce déjà passée garde les siens quand une version de plus est validée.
  final comptes = comptesAib(c.magasin, date);
  final base = baseCalculee.base;
  final ctl = ControleurFormulaire([
    ChampDef(
        nom: 'situation',
        libelle: 'Situation de l’acheteur (catégorie de retenue)',
        type: TypeChamp.select,
        requis: true,
        options: [
          for (final b in applicables)
            OptionChamp(b.code, '${b.libelle} — ${b.reponse.taux} %')
        ]),
    const ChampDef(
        nom: 'base',
        libelle: 'Base de la retenue (FCFA)',
        type: TypeChamp.nombre,
        requis: true,
        aide:
            'Proposée d’après les Paramètres (voir ci-dessus). Le montant retenu = base × taux du barème à la date de la facture, arrondi au franc.'),
  ], {
    'situation': applicables.first.code,
    'base': '${base.round()}'
  });
  afficherModale<void>(ctx,
      titre: 'Retenir l’AIB — ${r['reference']}',
      sousTitre:
          '${r['fournisseurNom']} : ${money(base)} facturés le ${dateFR(date)}',
      corps: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KeyedSubtree(
                key: const Key('retenue:base'),
                child: NoteSigh(baseCalculee.motif,
                    ton: baseCalculee.repli ? TonSigh.attention : TonSigh.info,
                    icone: baseCalculee.repli
                        ? LucideIcons.triangleAlert
                        : LucideIcons.info)),
            const SizedBox(height: 12),
            FormulaireSigh(controleur: ctl),
          ]),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: fermer),
            BoutonSigh(
                libelle: 'Constater la retenue',
                icone: LucideIcons.check,
                onPressed: () {
                  final v = ctl.valider();
                  if (v == null) {
                    ToastsSigh.afficher(
                        ctx, 'Le formulaire comporte des erreurs.',
                        type: TypeToast.erreur);
                    return;
                  }
                  final CpdRetenueAib ret;
                  final List<Map<String, Object?>> lignes;
                  try {
                    final baseSaisie = num.tryParse('${v['base']}'.trim()) ?? 0;
                    final modifiee = baseSaisie != baseCalculee.base;
                    ret = cpdCalculerRetenueAib(
                        bareme, '${v['situation']}', baseSaisie, date,
                        situations: situations,
                        baseSource: modifiee ? 'manuelle' : baseCalculee.source,
                        baseMotif: modifiee
                            ? 'Base corrigée à la main à la retenue (proposée : ${money(baseCalculee.base)}). ${baseCalculee.motif}'
                            : baseCalculee.motif);
                    lignes = cpdEcrituresRetenueAib(
                        retenue: ret,
                        numero: 'AIB-${r['reference']}',
                        date: iso(date),
                        reference: '${r['reference']}',
                        fournisseur: '${r['fournisseurNom']}',
                        pieceId: '${r['id']}',
                        comptes: comptes);
                  } on RefusRetenueAib catch (e) {
                    ToastsSigh.afficher(ctx, 'Retenue refusée.',
                        type: TypeToast.erreur,
                        detail: e.motif,
                        duree: const Duration(seconds: 9));
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
                    ToastsSigh.afficher(ctx, 'Écriture refusée.',
                        type: TypeToast.erreur, detail: e.motif);
                    return;
                  }
                  c.magasin
                      .collection('facturesFournisseurs')
                      .mettreAJour(r['id'], {
                    'retenueAib': {
                      ...ret.versFiche(),
                      'date': iso(date),
                      'reversement': iso(cpdEcheanceReversementAib(date)),
                      'ecritureIds': ids,
                      'compteRetenu': comptes.retenu,
                      'compteFournisseur': comptes.fournisseur,
                      if (comptes.version != null)
                        'comptesVersion': comptes.version,
                      'retenuPar': acteur(c).nom,
                      'retenueLe': iso(c.aujourdhui),
                    }
                  });
                  c.magasin.journaliser('Retenue d’AIB sur facture fournisseur',
                      'M7', 'FactureFournisseur', '${r['reference']}', null, {
                    'taux': ret.taux,
                    'base': ret.base,
                    'montant': ret.montant,
                    'situation': ret.situation,
                    'versionId': ret.versionId,
                    'baseSource': ret.baseSource
                  });
                  fermer();
                  ToastsSigh.afficher(ctx,
                      'Retenue de ${money(ret.montant)} constatée (brouillon).',
                      type: TypeToast.succes,
                      detail:
                          '${ret.taux} % — à reverser à l’État le ${dateFR(cpdEcheanceReversementAib(date))} (compte ${comptes.retenu}).');
                }),
          ]);
}

/// Le SIGNAL « taux non arrêté au barème » d'une facture qui porte un AIB facturé, à la date de la facture : `null` quand le taux est celui d'une version arrêtée
/// du barème en vigueur (ou quand la facture ne porte pas d'AIB facturé). Il ne bloque rien : le fournisseur a facturé ce qu'il a facturé.
String? _signalAib(ContexteEcran c, Fiche r) {
  final a = r['aibFacture'];
  if (a is! Map) return null;
  final taux = a['taux'];
  if (taux is! num) return null;
  final date = DateTime.tryParse('${r['date'] ?? ''}') ?? c.aujourdhui;
  return cpdSignalTauxAibFacture(c.magasin.collection('situationsAib').actives,
      c.magasin.collection('baremeAib').actives, taux, date);
}

/// « Constater l'AIB subi » : l'AIB que le fournisseur a FACTURÉ est une créance sur l'État que l'acheteur récupère sur son impôt sur les bénéfices (position de
/// la Direction du 09/11/2026). Une pièce PLATE en brouillon, RG-10 contrôlée équilibrée AVANT écriture : débit du compte d'AIB subi, crédit du compte fournisseur
/// du même montant, journal des achats. La facture PORTE son AIB subi (elle n'est jamais réécrite) et n'en porte qu'un. Refus nommés : facture archivée, pas
/// d'AIB facturé, déjà constaté, incohérent, exercice en clôture ; un taux hors barème arrêté est SIGNALÉ, pas refusé.
void _constaterAibSubi(BuildContext ctx, ContexteEcran c, Fiche r) {
  void refuser(String detail) => ToastsSigh.afficher(ctx, 'AIB subi refusé.',
      type: TypeToast.erreur,
      detail: detail,
      duree: const Duration(seconds: 9));
  final refus = cpdControlerAibSubi(r);
  if (refus != null) return refuser(refus);
  final date = DateTime.tryParse('${r['date'] ?? ''}') ?? c.aujourdhui;
  final a = (r['aibFacture'] as Map).cast<String, Object?>();
  final comptes = comptesAib(c.magasin, date);
  final signal = _signalAib(c, r);
  afficherModale<void>(ctx,
      titre: 'Constater l’AIB subi — ${r['reference']}',
      sousTitre:
          '${r['fournisseurNom']} : ${money(a['montant'])} d’AIB facturé le ${dateFR(date)}',
      corps: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const NoteSigh(
                'L’AIB facturé par le fournisseur n’est pas une charge : c’est une CRÉANCE sur l’État, imputée en fin d’année sur l’impôt sur les bénéfices. La pièce naît en brouillon.',
                ton: TonSigh.info,
                icone: LucideIcons.info),
            const SizedBox(height: 12),
            DescListeSigh([
              ('Base hors taxes', money(a['baseHt'])),
              ('Taux', '${a['taux']} %'),
              ('AIB subi', money(a['montant'])),
              (
                'Débit',
                'compte ${comptes.subi} — AIB subi (créance sur l’État)'
              ),
              ('Crédit', 'compte ${comptes.fournisseur} — fournisseurs'),
            ]),
            if (signal != null) ...[
              const SizedBox(height: 12),
              KeyedSubtree(
                  key: const Key('aibsubi:signal'),
                  child: NoteSigh(signal,
                      ton: TonSigh.attention,
                      icone: LucideIcons.triangleAlert)),
            ],
            if (comptes.aConfirmer) ...[
              const SizedBox(height: 12),
              KeyedSubtree(
                  key: const Key('aibsubi:comptes-a-confirmer'),
                  child: NoteSigh(
                      'Comptes ${comptes.deLaGraine ? 'de la graine' : 'des Paramètres'} : ${comptes.marquage}. Ils se valident aux Paramètres, « Validations de l’AIB ».',
                      ton: TonSigh.attention,
                      icone: LucideIcons.triangleAlert)),
            ],
          ]),
      pied: (fermer) => [
            BoutonSigh(
                libelle: 'Annuler',
                variante: VarianteBouton.secondaire,
                onPressed: fermer),
            // Le contexte du bouton (dans la fenêtre) porte les refus : celui de la ligne a pu disparaître avec la facture (archivée entre-temps).
            Builder(
                builder: (bc) => BoutonSigh(
                    key: const Key('aibsubi:constater'),
                    libelle: 'Constater l’AIB subi',
                    icone: LucideIcons.check,
                    onPressed: () {
                      void refuserIci(String detail) =>
                          ToastsSigh.afficher(bc, 'AIB subi refusé.',
                              type: TypeToast.erreur,
                              detail: detail,
                              duree: const Duration(seconds: 9));
                      // La facture a pu changer depuis l'ouverture de la fenêtre : on relit la fiche vivante (archivée comprise : le contrôle la refuse en le disant).
                      final vivante = c.magasin
                              .collection('facturesFournisseurs')
                              .parId(r['id']) ??
                          {...r, 'statut': 'archive'};
                      final CpdAibSubiConstate pose;
                      try {
                        pose = cpdConstaterAibSubi(
                            facture: vivante,
                            date: date,
                            comptes: comptes,
                            numero: 'AIBS-${vivante['reference']}',
                            signalTaux: signal);
                      } on RefusAibSubi catch (e) {
                        return refuserIci(e.motif);
                      }
                      final ecr = c.magasin.collection('ecritures');
                      final ids = <Object?>[];
                      final annulations = <VoidCallback>[];
                      try {
                        for (final l in pose.ecritures) {
                          final x = ecr.inserer(l, prefixe: 'ECR');
                          ids.add(x.fiche['id']);
                          annulations.add(x.annuler);
                        }
                      } on EcritureRefusee catch (e) {
                        for (final u in annulations) {
                          u();
                        }
                        ToastsSigh.afficher(bc, 'Écriture refusée.',
                            type: TypeToast.erreur, detail: e.motif);
                        return;
                      }
                      c.magasin
                          .collection('facturesFournisseurs')
                          .mettreAJour(vivante['id'], {
                        'aibSubi': {
                          ...pose.fiche,
                          'ecritureIds': ids,
                          'constatePar': acteur(c).nom,
                          'constateLe': iso(c.aujourdhui),
                        }
                      });
                      c.magasin.journaliser(
                          'AIB subi sur facture fournisseur',
                          'M7',
                          'FactureFournisseur',
                          '${vivante['reference']}',
                          null, {
                        'montant': pose.fiche['montant'],
                        'taux': pose.fiche['taux'],
                        'base': pose.fiche['base'],
                        'compteSubi': comptes.subi,
                        'compteFournisseur': comptes.fournisseur,
                        'comptesVersion': comptes.version,
                        if (signal != null) 'signalTaux': true,
                      });
                      fermer();
                      ToastsSigh.afficher(ctx,
                          'AIB subi de ${money(pose.fiche['montant'])} constaté (brouillon).',
                          type: TypeToast.succes,
                          detail:
                              'Débit ${comptes.subi}, crédit ${comptes.fournisseur}.${signal == null ? '' : ' Taux non arrêté au barème : signalé.'}');
                    })),
          ]);
}
