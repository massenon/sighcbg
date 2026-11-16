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

/// La modale de confirmation : date d'effet (proposée : [effetPropose], verrouillée quand [effetFige]) et motif, tous deux obligatoires. Rend `(dateEffet, motif)` ou `null`.
Future<({String dateEffet, String motif})?> demanderConfirmation(BuildContext context,
    {required String titre, required String ce, required DateTime effetPropose, bool effetFige = false}) {
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
  ], {
    'dateEffet': iso(effetPropose),
  });
  return afficherModale<({String dateEffet, String motif})>(context,
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
                      Navigator.of(ctx, rootNavigator: true).pop((dateEffet: '${v['dateEffet']}', motif: '${v['motif']}'.trim()));
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

/// « Confirmer » les taux de la CNSS (part ouvrière, part patronale, plafond — ce qui existe).
Future<void> confirmerCnss(BuildContext context, ContexteEcran c) async {
  final valeur = fcoValeursCnss();
  final r = await demanderConfirmation(context, titre: 'Confirmer les taux de la CNSS', ce: fcoLibelleCnss(valeur), effetPropose: c.aujourdhui);
  if (r == null || !context.mounted) return;
  final res = fcoConfirmer(
      objet: fcoObjetCnss,
      cible: fcoCibleCnssTaux,
      libelle: 'CNSS — ${fcoLibelleCnss(valeur)}',
      valeur: valeur,
      dateEffet: r.dateEffet,
      motif: r.motif,
      role: c.role,
      auteur: acteur(c).nom,
      maintenant: c.magasin.horloge(),
      existantes: c.magasin.collection(fcoCollection).actives,
      gestes: gestesEcran(c),
      fileul: _fileul(c));
  if (res.refus != null) return _refuser(context, res.refus!);
  _ecrire(c, res.fiche!);
  ToastsSigh.afficher(context, 'Taux de la CNSS confirmés.', type: TypeToast.succes, detail: libelleConfirmation(res.fiche));
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

/// La carte de la CNSS : ce qui existe (taux, plafond), l'état de la confirmation, l'historique, et « Confirmer » pour qui détient le geste.
class CarteConfirmationCnss extends StatelessWidget {
  const CarteConfirmationCnss({super.key, required this.c});
  final ContexteEcran c;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: c.magasin.collection(fcoCollection),
      builder: (context, _) {
        final toutes = c.magasin.collection(fcoCollection).actives;
        final enVigueur = fcoConfirmationALaDate(toutes, fcoObjetCnss, fcoCibleCnssTaux, c.aujourdhui);
        final histo = fcoHistorique(toutes, fcoObjetCnss, fcoCibleCnssTaux).reversed.toList();
        return CarteSigh(
            key: const Key('fco:cnss'),
            titre: 'Taux de la CNSS',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('En vigueur : ${fcoLibelleCnss(fcoValeursCnss())}.',
                  style: const TextStyle(color: JetonsShell.slate800, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              NoteSigh(libelleConfirmation(enVigueur),
                  key: const Key('fco:cnss:etat'),
                  ton: enVigueur == null ? TonSigh.attention : TonSigh.succes,
                  icone: enVigueur == null ? LucideIcons.triangleAlert : LucideIcons.circleCheck),
              if (peutConfirmerFiscal(c)) ...[
                const SizedBox(height: 8),
                Wrap(children: [
                  BoutonSigh(
                      key: const Key('fco:cnss:confirmer'),
                      libelle: 'Confirmer',
                      icone: LucideIcons.stamp,
                      variante: VarianteBouton.secondaire,
                      onPressed: () => confirmerCnss(context, c)),
                ]),
              ],
              if (histo.isNotEmpty) ...[
                const SizedBox(height: 12),
                MiniTableauSigh(
                    colonnes: [
                      ColonneMini('Effet au', (f) => _jourFr(f['dateEffet'])),
                      ColonneMini('Valeur confirmée', (f) => fcoLibelleCnss(((f['valeur'] as Map?) ?? const {}).cast<String, Object?>())),
                      ColonneMini('Par', (f) => '${f['confirmePar'] ?? '—'}'),
                      ColonneMini('Le', (f) => _jourFr(f['confirmeLe'])),
                      ColonneMini('Motif', (f) => '${f['motif'] ?? '—'}'),
                    ],
                    lignes: histo),
              ],
            ]));
      });
}
