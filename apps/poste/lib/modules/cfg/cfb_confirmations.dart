import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/jetons_shell.dart';
import '../../core/service_installation.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';

/// LE BOUTON « CONFIRMER » DES TAUX FISCAUX (Direction de Baguidi, compléments du 16/11/2026, section 7) : les taux de la CNSS et les versions du barème de l'AIB.
///
/// La confirmation exige un MOTIF et une date d'effet, elle est tracée (auteur de la session, rôle, horodatage, motif, valeur confirmée recopiée) et RÉSERVÉE au geste
/// `fiscal_confirmer` de la matrice : sans lui, le bouton est ABSENT (jamais grisé). Rien n'est écrasé : une confirmation AJOUTE une fiche datée à `confirmationsFiscales`
/// (moteur `fcoConfirmer` du domaine, qui refuse en nommant), et la confirmation d'une version du barème NON ARRÊTÉE l'arrête à la date d'effet choisie. Un fileul lit :
/// la configuration fiscale est tenue par la mère.

bool _fileul(ContexteEcran c) => ServiceInstallation.de(c.magasin).rattache;

/// Le bouton s'offre-t-il ? Le geste réservé en force ET un poste qui tient sa configuration.
bool peutConfirmerFiscal(ContexteEcran c) => !_fileul(c) && gestePeutEcran(c, gesteFiscalConfirmer);

String _jourFr(Object? iso) {
  final s = '${iso ?? ''}';
  return s.length >= 10 ? '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}' : '—';
}

/// La phrase de l'état d'une confirmation à la date du jour : confirmé (par qui, quand, depuis quand, motif) ou NON confirmé.
String libelleConfirmation(Map<String, Object?>? f) => f == null
    ? 'Non confirmé : aucune confirmation (motif, auteur, date) n’est enregistrée à ce jour.'
    : 'Confirmé par ${f['confirmePar']} le ${_jourFr(f['confirmeLe'])}, avec effet au ${_jourFr(f['dateEffet'])}. Motif : ${f['motif']}';

/// La modale de confirmation : date d'effet (proposée : [effetPropose], verrouillée quand [effetFige]) et motif, tous deux obligatoires ; avec [texte], le TEXTE CITÉ
/// (référence du texte qui fonde la valeur) est demandé lui aussi, obligatoire. Rend `(dateEffet, motif, texte)` ou `null`.
Future<({String dateEffet, String motif, String texte})?> demanderConfirmation(BuildContext context,
    {required String titre, required String ce, required DateTime effetPropose, bool effetFige = false, bool texte = false}) {
  final ctl = ControleurFormulaire([
    ChampDef(
        nom: 'dateEffet',
        libelle: 'Date d’effet de la confirmation',
        type: TypeChamp.date,
        requis: true,
        valider: effetFige ? (v, _) => '$v' == iso(effetPropose) ? null : 'La date d’effet d’une version arrêtée ne change pas.' : null,
        aide: effetFige ? 'Version déjà arrêtée : sa date d’effet ne se réécrit pas.' : 'La valeur est confirmée à compter de cette date ; le passé ne se réécrit pas.'),
    const ChampDef(
        nom: 'motif',
        libelle: 'Motif de la confirmation',
        type: TypeChamp.textarea,
        lignes: 3,
        col: ColChamp.plein,
        requis: true,
        aide: 'Sur quoi repose la confirmation : texte officiel, notification de l’organisme, avis de l’expert-comptable.'),
    if (texte)
      const ChampDef(
          nom: 'texte',
          libelle: 'Texte cité',
          col: ColChamp.plein,
          requis: true,
          aide: 'La référence du texte qui fonde la valeur (loi de finances, décret, arrêté), avec sa date : sans elle, la valeur reste « à confirmer ».'),
  ], {
    'dateEffet': iso(effetPropose),
  });
  return afficherModale<({String dateEffet, String motif, String texte})>(context,
      titre: titre,
      sousTitre: ce,
      corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NoteSigh(
            'La confirmation est tracée (votre compte, la date, le motif) et s’AJOUTE à l’historique : rien n’est écrasé. Elle est réservée au geste « Confirmer un taux fiscal ».',
            ton: TonSigh.info,
            icone: LucideIcons.stamp),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            Builder(
                builder: (ctx) => BoutonSigh(
                    key: const Key('fco:confirmer:valider'),
                    libelle: 'Confirmer',
                    icone: LucideIcons.stamp,
                    onPressed: () {
                      final v = ctl.valider();
                      if (v == null) {
                        ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                        return;
                      }
                      Navigator.of(ctx, rootNavigator: true).pop((dateEffet: '${v['dateEffet']}', motif: '${v['motif']}'.trim(), texte: '${v['texte'] ?? ''}'.trim()));
                    })),
          ]);
}

/// Écrit la fiche de confirmation (ajout seul) et sa ligne de journal (RG-12).
void _ecrire(ContexteEcran c, Map<String, Object?> fiche) {
  c.magasin.collection(fcoCollection).ajouterSansJournal(fiche, enTete: true);
  c.magasin.journaliser('Confirmation fiscale : ${fiche['libelle']}', 'CFG', fcoCollection, '${fiche['id']}', null, {
    'objet': fiche['objet'],
    'cible': fiche['cible'],
    'valeur': fiche['valeur'],
    'dateEffet': fiche['dateEffet'],
    'motif': fiche['motif'],
    'confirmePar': fiche['confirmePar'],
    'confirmeRole': fiche['confirmeRole'],
  });
}

void _refuser(BuildContext ctx, FcoRefus r) =>
    ToastsSigh.afficher(ctx, 'Confirmation refusée.', type: TypeToast.erreur, detail: '${r.code} : ${r.motif} ${r.geste}', duree: const Duration(seconds: 9));

/// Les versions de la collection `parametres` (taux et barème de la paie datés, lot 1).
List<Fiche> _parametres(ContexteEcran c) => c.magasin.collection(parCollectionParametres).toutes;

/// Les taux de la paie EN VIGUEUR à [date].
PaiTauxPaie tauxPaieA(ContexteEcran c, DateTime date) => PaiTauxPaie.aLaDate(_parametres(c), date);

/// « Confirmer » les taux de la CNSS (part ouvrière, part patronale, plafond — ce qui existe) : la valeur confirmée est celle en vigueur à la date d'effet choisie.
Future<void> confirmerCnss(BuildContext context, ContexteEcran c) => confirmerTaux(context, c, fcoObjetCnss);

/// « Confirmer » la valeur d'un objet daté (CNSS, VPS, barème de l'ITS) : celle EN VIGUEUR à la date d'effet choisie. Le barème de l'ITS exige le texte cité.
Future<void> confirmerTaux(BuildContext context, ContexteEcran c, String objet) async {
  final its = objet == fcoObjetBaremeIts;
  final r = await demanderConfirmation(context,
      titre: objet == fcoObjetCnss ? 'Confirmer les taux de la CNSS' : 'Confirmer : ${_titreObjet(objet)}', ce: fcoLibelleDe(objet, fcoValeursDe(objet, tauxPaieA(c, c.aujourdhui))), effetPropose: c.aujourdhui, texte: its);
  if (r == null || !context.mounted) return;
  final res = fcoConfirmerTaux(
      objet: objet,
      parametres: _parametres(c),
      dateEffet: r.dateEffet,
      motif: r.motif,
      texte: r.texte,
      role: c.role,
      auteur: acteur(c).nom,
      maintenant: c.magasin.horloge(),
      existantes: c.magasin.collection(fcoCollection).actives,
      gestes: gestesEcran(c),
      fileul: _fileul(c));
  if (res.refus != null) return _refuser(context, res.refus!);
  _ecrire(c, res.fiche!);
  ToastsSigh.afficher(context, objet == fcoObjetCnss ? 'Taux de la CNSS confirmés.' : '${_titreObjet(objet)} confirmé.', type: TypeToast.succes, detail: libelleConfirmation(res.fiche));
}

String _titreObjet(String objet) => switch (objet) {
      fcoObjetCnss => 'Taux de la CNSS',
      fcoObjetVps => 'Taux du VPS',
      fcoObjetAnciennete => 'Prime d’ancienneté',
      fcoObjetTva => 'TVA du régime normal',
      _ => 'Barème de l’ITS',
    };

num? _nombre(Object? v) => num.tryParse('${v ?? ''}'.replaceAll(',', '.').replaceAll(RegExp(r'[\s\u00A0\u202F%]'), ''));

/// « NOUVELLE VERSION » d'un objet daté, sous le geste `fiscal_confirmer` : la valeur nouvelle, sa date d'effet, le motif (obligatoire) et le texte cité (facultatif ; pour le
/// barème de l'ITS, sans lui la version reste « à confirmer »). Le domaine ([fcoPoserVersion]) contrôle tout avant que rien ne s'écrive ; l'écran écrit les versions de
/// `parametres` (famille R) et la confirmation qui les atteste, puis journalise (RG-12).
Future<void> poserVersionTaux(BuildContext context, ContexteEcran c, String objet) async {
  final t = tauxPaieA(c, c.aujourdhui);
  final champs = <ChampDef>[
    if (objet == fcoObjetCnss) ...[
      const ChampDef(nom: 'tauxOuvrier', libelle: 'Part ouvrière (%)', type: TypeChamp.nombre, requis: true),
      const ChampDef(nom: 'tauxPatronal', libelle: 'Part patronale (%)', type: TypeChamp.nombre, requis: true),
    ],
    if (objet == fcoObjetVps) const ChampDef(nom: 'taux', libelle: 'Taux du VPS (% du brut)', type: TypeChamp.nombre, requis: true),
    if (objet == fcoObjetTva) const ChampDef(nom: 'taux', libelle: 'Taux du régime normal (%)', type: TypeChamp.nombre, requis: true),
    if (objet == fcoObjetAnciennete) ...[
      const ChampDef(nom: 'taux', libelle: 'Taux par année (% du salaire de base)', type: TypeChamp.nombre, requis: true),
      const ChampDef(nom: 'seuilAns', libelle: 'À partir de (années)', type: TypeChamp.nombre, requis: true),
    ],
    if (objet == fcoObjetBaremeIts)
      const ChampDef(
          nom: 'bareme',
          libelle: 'Tranches du barème',
          type: TypeChamp.textarea,
          lignes: 6,
          col: ColChamp.plein,
          requis: true,
          aide: 'Une tranche par ligne : plancher, plafond, taux (%). La première part de 0 ; la dernière s’écrit « et plus ».'),
    const ChampDef(
        nom: 'dateEffet',
        libelle: 'Date d’effet',
        type: TypeChamp.date,
        requis: true,
        aide: 'Un bulletin se calcule au taux en vigueur le premier jour de sa période ; un bulletin déjà généré garde le sien.'),
    const ChampDef(nom: 'motif', libelle: 'Motif', type: TypeChamp.textarea, lignes: 3, col: ColChamp.plein, requis: true,
        aide: 'Sur quoi repose le changement : texte officiel, notification de l’organisme, avis de l’expert-comptable.'),
    const ChampDef(nom: 'texte', libelle: 'Texte cité (facultatif)', col: ColChamp.plein,
        aide: 'La référence du texte qui fonde la valeur. Pour le barème de l’ITS, sans texte cité, la version reste « à confirmer ».'),
  ];
  final ctl = ControleurFormulaire(champs, {
    if (objet == fcoObjetCnss) ...{'tauxOuvrier': paiNumTexte(t.cnssOuvriere), 'tauxPatronal': paiNumTexte(t.cnssPatronale)},
    if (objet == fcoObjetVps) 'taux': paiNumTexte(t.vps),
    if (objet == fcoObjetTva) 'taux': paiNumTexte(t.tvaNormal),
    if (objet == fcoObjetAnciennete) ...{'taux': paiNumTexte(t.ancienneteTaux), 'seuilAns': '${t.ancienneteSeuilAns}'},
    if (objet == fcoObjetBaremeIts) 'bareme': paiBaremeItsVersSaisie(t.baremeIts),
    'dateEffet': iso(c.aujourdhui),
  });
  final v = await afficherModale<Map<String, Object?>>(context,
      titre: 'Nouvelle version : ${_titreObjet(objet)}',
      sousTitre: 'En vigueur aujourd’hui : ${fcoLibelleDe(objet, fcoValeursDe(objet, t))}',
      corps: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NoteSigh(
            'La version s’AJOUTE à partir de sa date d’effet : rien n’est écrasé, les bulletins déjà générés gardent leur taux. Elle est réservée au geste « Confirmer un taux fiscal » et tracée (votre compte, la date, le motif).',
            ton: TonSigh.info,
            icone: LucideIcons.history),
        const SizedBox(height: 12),
        FormulaireSigh(controleur: ctl),
      ]),
      pied: (fermer) => [
            BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
            Builder(
                builder: (ctx) => BoutonSigh(
                    key: const Key('fco:version:valider'),
                    libelle: 'Poser la version',
                    icone: LucideIcons.history,
                    onPressed: () {
                      final v = ctl.valider();
                      if (v == null) {
                        ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                        return;
                      }
                      Navigator.of(ctx, rootNavigator: true).pop(v);
                    })),
          ]);
  if (v == null || !context.mounted) return;
  final valeurs = <String, Object?>{};
  if (objet == fcoObjetCnss) {
    valeurs[paiCleCnssOuvriere] = _nombre(v['tauxOuvrier']);
    valeurs[paiCleCnssPatronale] = _nombre(v['tauxPatronal']);
  } else if (objet == fcoObjetVps) {
    valeurs[paiCleVps] = _nombre(v['taux']);
  } else if (objet == fcoObjetTva) {
    valeurs[paiCleTvaNormal] = _nombre(v['taux']);
  } else if (objet == fcoObjetAnciennete) {
    valeurs[paiCleAncienneteTaux] = _nombre(v['taux']);
    valeurs[paiCleAncienneteSeuil] = _nombre(v['seuilAns']);
  } else {
    final lu = paiBaremeItsDepuisSaisie('${v['bareme'] ?? ''}');
    if (lu.refus != null) return _refuser(context, FcoRefus('VALEUR_INVALIDE', lu.refus!, 'Corriger les tranches.'));
    valeurs[paiCleBaremeIts] = lu.bareme;
  }
  final res = fcoPoserVersion(
      objet: objet,
      valeurs: valeurs,
      dateEffet: v['dateEffet'],
      motif: '${v['motif'] ?? ''}',
      texte: '${v['texte'] ?? ''}',
      role: c.role,
      auteur: acteur(c).nom,
      maintenant: c.magasin.horloge(),
      parametres: _parametres(c),
      usages: c.magasin.collection(parCollectionUsages).toutes,
      existantes: c.magasin.collection(fcoCollection).actives,
      bulletins: c.magasin.collection('bulletins').toutes,
      gestes: gestesEcran(c),
      fileul: _fileul(c));
  if (res.refus != null) return _refuser(context, res.refus!);
  final versions = c.magasin.collection(parCollectionParametres);
  for (final f in res.versions) {
    versions.inserer(f);
  }
  _ecrire(c, res.confirmation!);
  ToastsSigh.afficher(context, 'Nouvelle version posée.', type: TypeToast.succes, detail: '${res.confirmation!['libelle']} — à compter du ${_jourFr(res.confirmation!['dateEffet'])}.');
}

/// Un taux écrit pour la saisie (« 3,6 », « 4 »).
String paiNumTexte(num v) => (v == v.truncateToDouble() ? '${v.toInt()}' : '$v').replaceAll('.', ',');

/// Les versions d'un objet daté, de la plus récente à la plus ancienne (les fiches de la collection `parametres` de ses clés, semence comprise si elle est semée).
List<Fiche> _versionsObjet(ContexteEcran c, String objet) {
  final cles = fcoClesParObjet[objet] ?? const [];
  final l = [for (final f in _parametres(c)) if (f['statut'] != 'archive' && cles.contains(f['cle']) && f['dateEffet'] != null) f];
  l.sort((a, b) => '${b['dateEffet']}'.compareTo('${a['dateEffet']}'));
  return l;
}

/// « Confirmer » une version du barème de l'AIB : la confirmation s'ajoute ; une version NON ARRÊTÉE est arrêtée à la date d'effet choisie (par l'auteur, aujourd'hui).
Future<void> confirmerVersionAib(BuildContext context, ContexteEcran c, Fiche version) async {
  final arretee = cpdEstArretee(version);
  final effet = DateTime.tryParse('${version['dateEffet'] ?? ''}');
  final r = await demanderConfirmation(context,
      titre: 'Confirmer une version du barème de l’AIB',
      ce: '${version['situation']} — ${version['taux']} %${arretee ? ' (version arrêtée)' : ' (non arrêtée : la confirmation l’arrête)'}',
      effetPropose: arretee && effet != null ? effet : c.aujourdhui,
      effetFige: arretee && effet != null);
  if (r == null || !context.mounted) return;
  final bareme = c.magasin.collection('baremeAib');
  final res = fcoConfirmerVersionAib(
      version: version,
      versions: bareme.actives,
      situations: c.magasin.collection('situationsAib').actives,
      dateEffet: r.dateEffet,
      motif: r.motif,
      role: c.role,
      auteur: acteur(c).nom,
      maintenant: c.magasin.horloge(),
      existantes: c.magasin.collection(fcoCollection).actives,
      gestes: gestesEcran(c),
      fileul: _fileul(c));
  if (res.refus != null) return _refuser(context, res.refus!);
  if (res.arret != null) bareme.mettreAJour(version['id'], res.arret!);
  _ecrire(c, res.fiche!);
  ToastsSigh.afficher(context, res.arret != null ? 'Version confirmée et arrêtée.' : 'Version confirmée.', type: TypeToast.succes, detail: libelleConfirmation(res.fiche));
}

/// La carte de la CNSS : ce qui existe (taux, plafond), l'état de la confirmation, l'historique, et « Confirmer » / « Nouvelle version » pour qui détient le geste.
class CarteConfirmationCnss extends StatelessWidget {
  const CarteConfirmationCnss({super.key, required this.c});
  final ContexteEcran c;

  @override
  Widget build(BuildContext context) => CarteTauxPaie(c: c, objet: fcoObjetCnss);
}

/// LES TAUX DE LA PAIE DATÉS (lot 1) : la CNSS, le VPS et le barème de l'ITS, chacun dans sa carte.
class CartesTauxPaie extends StatelessWidget {
  const CartesTauxPaie({super.key, required this.c, this.enteteIts = const [], this.avecTva = false});
  final ContexteEcran c;

  /// La carte de la TVA du régime normal (configuration fiscale) ; les écrans de la paie ne la montrent pas.
  final bool avecTva;

  /// Ce qui précède le barème de l'ITS dans sa carte (le bandeau de validation de la Direction, à l'écran des paramètres comptables).
  final List<Widget> enteteIts;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CarteTauxPaie(c: c, objet: fcoObjetCnss),
        const SizedBox(height: 16),
        CarteTauxPaie(c: c, objet: fcoObjetVps),
        const SizedBox(height: 16),
        CarteTauxPaie(c: c, objet: fcoObjetBaremeIts, entete: enteteIts),
        const SizedBox(height: 16),
        CarteTauxPaie(c: c, objet: fcoObjetAnciennete),
        if (avecTva) ...[
          const SizedBox(height: 16),
          CarteTauxPaie(c: c, objet: fcoObjetTva),
        ],
      ]);
}

/// La carte d'un objet daté (CNSS, VPS, barème de l'ITS) : la valeur EN VIGUEUR aujourd'hui et sa version, la prochaine version datée, l'état de la confirmation (le barème
/// de l'ITS reste « à confirmer » tant qu'aucune confirmation ne cite un texte), l'historique des versions et des confirmations ; « Confirmer » et « Nouvelle version »
/// pour qui détient le geste `fiscal_confirmer` sur un poste qui tient sa configuration (sinon ABSENTS, jamais grisés).
class CarteTauxPaie extends StatelessWidget {
  const CarteTauxPaie({super.key, required this.c, required this.objet, this.entete = const []});
  final ContexteEcran c;
  final String objet;
  final List<Widget> entete;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([c.magasin.collection(fcoCollection), c.magasin.collection(parCollectionParametres)]),
      builder: (context, _) {
        final toutes = c.magasin.collection(fcoCollection).actives;
        final t = tauxPaieA(c, c.aujourdhui);
        final valeur = fcoValeursDe(objet, t);
        final cible = fcoCibleDe(objet);
        final enVigueur = fcoConfirmationDeLaValeur(toutes, objet, cible, c.aujourdhui, valeur);
        final derniere = fcoConfirmationALaDate(toutes, objet, cible, c.aujourdhui);
        final histo = fcoHistorique(toutes, objet, cible).reversed.toList();
        final versions = _versionsObjet(c, objet);
        final aujIso = iso(c.aujourdhui);
        final futures = [for (final v in versions) if ('${v['dateEffet']}'.compareTo(aujIso) > 0) v];
        final cle = (fcoClesParObjet[objet] ?? const [paiCleBaremeIts]).first;
        final version = t.version(cle);
        final its = objet == fcoObjetBaremeIts;
        final aConfirmer = its && fcoBaremeItsAConfirmer(toutes, c.aujourdhui, t);
        final etat = enVigueur != null
            ? libelleConfirmation(enVigueur)
            : derniere != null
                ? 'Non confirmé : la valeur en vigueur a changé depuis la dernière confirmation (${_jourFr(derniere['dateEffet'])}).'
                : libelleConfirmation(null);
        return CarteSigh(
            key: Key('fco:$objet'),
            titre: _titreObjet(objet),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ...entete,
              if (entete.isNotEmpty) const SizedBox(height: 8),
              Text(objet == fcoObjetCnss ? 'En vigueur : ${fcoLibelleCnss(valeur)}.' : 'En vigueur : ${fcoLibelleDe(objet, valeur).split(' — ').last}.',
                  style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Version : ${version.libelle}.${futures.isEmpty ? '' : ' Prochaine version au ${_jourFr(futures.last['dateEffet'])}.'}',
                  key: Key('fco:$objet:version:etat'), style: const TextStyle(color: JetonsShell.slate500, fontSize: 12, height: 16 / 12)),
              if (its) ...[
                const SizedBox(height: 8),
                MiniTableauSigh(colonnes: [
                  ColonneMini('Tranche de salaire', (r) => '${r['tranche']}'),
                  ColonneMini('Taux', (r) => '${r['taux']} %', droite: true),
                ], lignes: [
                  for (final x in t.baremeIts)
                    {'tranche': '${money(x.de, avecDevise: false)}${x.a == null ? ' et plus' : ' à ${money(x.a, avecDevise: false)}'}', 'taux': paiNumTexte(x.taux)}
                ]),
              ],
              const SizedBox(height: 8),
              if (aConfirmer)
                NoteSigh(
                    'À confirmer : aucune confirmation de ce barème ne cite le texte qui le fonde. Il s’applique, mais reste marqué tant qu’un texte n’est pas cité.',
                    key: const Key('fco:bareme_its:aconfirmer'),
                    ton: TonSigh.attention,
                    icone: LucideIcons.triangleAlert),
              if (aConfirmer) const SizedBox(height: 8),
              NoteSigh(etat,
                  key: Key('fco:$objet:etat'),
                  ton: enVigueur == null ? TonSigh.attention : TonSigh.succes,
                  icone: enVigueur == null ? LucideIcons.triangleAlert : LucideIcons.circleCheck),
              if (peutConfirmerFiscal(c)) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  BoutonSigh(
                      key: Key('fco:$objet:confirmer'),
                      libelle: 'Confirmer',
                      icone: LucideIcons.stamp,
                      variante: VarianteBouton.secondaire,
                      onPressed: () => confirmerTaux(context, c, objet)),
                  BoutonSigh(
                      key: Key('fco:$objet:nouvelle'),
                      libelle: 'Nouvelle version',
                      icone: LucideIcons.history,
                      variante: VarianteBouton.secondaire,
                      onPressed: () => poserVersionTaux(context, c, objet)),
                ]),
              ],
              if (versions.isNotEmpty) ...[
                const SizedBox(height: 12),
                MiniTableauSigh(
                    key: Key('fco:$objet:versions'),
                    colonnes: [
                      ColonneMini('Version au', (f) => _jourFr(f['dateEffet'])),
                      ColonneMini('Paramètre', (f) => definitionDeParametre('${f['cle']}')?.libelle ?? '${f['cle']}'),
                      ColonneMini('Valeur', (f) => f['cle'] == paiCleBaremeIts
                          ? fcoLibelleIts({'bareme': paiBaremeItsDepuisJson(f['valeur']) == null ? null : f['valeur']})
                          : f['cle'] == paiCleAncienneteSeuil
                              ? '${nombreOuZero(f['valeur']).toInt()} ans'
                              : '${paiNumTexte(nombreOuZero(f['valeur']))} %'),
                      ColonneMini('Par', (f) => '${f['auteur'] ?? '—'}'),
                      ColonneMini('Motif', (f) => '${f['motif'] ?? '—'}'),
                    ],
                    lignes: versions),
              ],
              if (histo.isNotEmpty) ...[
                const SizedBox(height: 12),
                MiniTableauSigh(
                    colonnes: [
                      ColonneMini('Effet au', (f) => _jourFr(f['dateEffet'])),
                      ColonneMini('Valeur confirmée', (f) {
                        final v = ((f['valeur'] as Map?) ?? const {}).cast<String, Object?>();
                        return objet == fcoObjetCnss ? fcoLibelleCnss(v) : fcoLibelleDe(objet, v).split(' — ').last;
                      }),
                      ColonneMini('Par', (f) => '${f['confirmePar'] ?? '—'}'),
                      ColonneMini('Le', (f) => _jourFr(f['confirmeLe'])),
                      ColonneMini('Motif', (f) => '${f['motif'] ?? '—'}${f['texte'] == null ? '' : ' — texte : ${f['texte']}'}'),
                    ],
                    lignes: histo),
              ],
            ]));
      });
}
