import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/service_installation.dart';
import '../../donnees/facture_tiers_poste.dart';
import '../../donnees/magasin.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import 'commun.dart';

/// L'onglet « Factures à une entreprise » de `m9-facture-mere` (Direction de Baguidi, 17/11/2026, point 2) : la vente normalisée adressée à l'entreprise qui prend un patient en charge, avec
/// l'IFU et le nom de l'acheteur et la situation d'AIB CHOISIE par le comptable. La pièce naît d'une LIGNE du relevé de M9 (souscripteur, compagnie, période) : son montant est la part prise
/// en charge de cette ligne, jamais une saisie ; la facture du patient reste sans acheteur ni AIB. La commande est ABSENTE sans le geste réservé « Émettre une facture à une entreprise »
/// (jamais grisée), et le moteur refuse en nommant si on le contourne.
class OngletFacturesTiers extends StatefulWidget {
  const OngletFacturesTiers({
    super.key,
    required this.c,
    required this.code,
    required this.nom,
    required this.periode,
    required this.periodeLibelle,
    required this.depuis,
    required this.lignes,
  });
  final ContexteEcran c;
  final String code, nom, periode, periodeLibelle, depuis;

  /// Les lignes du relevé encore disponibles (factures patients non réclamées), une par souscripteur.
  final List<AssFilleMere> lignes;

  @override
  State<OngletFacturesTiers> createState() => _EtatFacturesTiers();
}

class _EtatFacturesTiers extends State<OngletFacturesTiers> {
  ControleurFormulaire? _ctl;
  String _signature = '';

  ContexteEcran get c => widget.c;

  bool get _peut => !ServiceInstallation.de(c.magasin).rattache && gestePeutEcran(c, gesteFactureTiersEmettre);

  ControleurFormulaire _formulaire() {
    final sig = widget.lignes.map((l) => l.souscripteur).join('|');
    if (_ctl != null && sig == _signature) return _ctl!;
    _ctl?.dispose();
    _signature = sig;
    final situations = c.magasin.collection('situationsAib').actives;
    return _ctl = ControleurFormulaire([
      ChampDef(
          nom: 'souscripteur',
          libelle: 'Souscripteur (ligne du relevé)',
          type: TypeChamp.select,
          requis: true,
          col: ColChamp.plein,
          options: [for (final l in widget.lignes) OptionChamp(l.souscripteur, '${l.souscripteur} — ${money(l.assureur)} sur ${nombre(l.factures.length)} facture(s)')],
          aide: 'La pièce naît d’une ligne du relevé : son montant est la part prise en charge, jamais une saisie.'),
      const ChampDef(nom: 'ifu', libelle: 'IFU de l’entreprise', col: ColChamp.demi, aide: 'Obligatoire, 13 chiffres.'),
      const ChampDef(nom: 'nom', libelle: 'Nom de l’entreprise', col: ColChamp.demi, aide: 'Obligatoire : il accompagne l’IFU sur la pièce normalisée.'),
      ChampDef(
          nom: 'situation',
          libelle: 'Situation de l’acheteur (AIB)',
          type: TypeChamp.select,
          col: ColChamp.plein,
          options: [
            const OptionChamp('', '— à choisir : jamais présumée —'),
            for (final s in situations) OptionChamp('${s['code']}', '${s['libelle'] ?? s['code']}')
          ],
          aide: 'Le comptable choisit : le taux est celui du barème ARRÊTÉ en vigueur, un taux non arrêté ne s’applique jamais.'),
      const ChampDef(nom: 'note', libelle: 'Note (facultatif)', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein),
    ], {'souscripteur': widget.lignes.isEmpty ? '' : widget.lignes.first.souscripteur, 'situation': ''});
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  void _emettre(BuildContext ctx) {
    final v = _ctl!.valider();
    if (v == null) {
      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
      return;
    }
    final ligne = widget.lignes.where((l) => l.souscripteur == '${v['souscripteur']}').firstOrNull;
    final r = emettreFactureTiers(c.magasin,
        role: c.role,
        maintenant: c.aujourdhui,
        acheteurIfu: v['ifu'],
        acheteurNom: v['nom'],
        situationChoisie: v['situation'],
        compagnieCode: widget.code,
        compagnieNom: widget.nom,
        periode: widget.periode,
        periodeLibelle: widget.periodeLibelle,
        depuis: widget.depuis,
        ligne: ligne,
        fileul: ServiceInstallation.de(c.magasin).rattache,
        note: '${v['note'] ?? ''}');
    if (!r.ok) {
      ToastsSigh.afficher(ctx, 'Émission refusée (${r.refus!.code}).', type: TypeToast.erreur, detail: '${r.refus!.motif} ${r.refus!.geste}', duree: const Duration(seconds: 12));
      return;
    }
    final f = r.fiche!;
    ToastsSigh.afficher(ctx, 'Facture ${f['numero']} émise à ${f['acheteurNom']}.',
        type: TypeToast.succes,
        detail: '${money(f['montantTTC'])} — AIB ${f['aibTaux']} % (${f['aibMontant'] == null ? '—' : money(f['aibMontant'])}). ${r.codeMecef == null ? '' : 'Certification en attente (${r.codeMecef}).'}',
        annuler: r.annuler,
        messageAnnulation: 'Émission annulée — la pièce est archivée.');
    setState(() => _signature = '');
  }

  @override
  Widget build(BuildContext context) {
    final emises = [for (final f in actives(c, colFacturesTiers)) if (f['compagnieCode'] == widget.code) f];
    final ctl = _peut && widget.lignes.isNotEmpty ? _formulaire() : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteSigh(
          'Une entreprise qui prend un patient en charge reçoit SA facture : une vente normalisée avec son IFU et son nom, distincte de la facture du patient (qui reste sans acheteur ni AIB). '
          'Le montant vient du relevé ci-dessus — la part prise en charge du souscripteur — et la pièce porte les numéros des factures patients qu’elle réclame : une facture patient ne se réclame qu’une fois.',
          icone: LucideIcons.building2),
      const SizedBox(height: 12),
      if (!_peut)
        const NoteSigh('Émettre une facture à une entreprise est le geste réservé « Émettre une facture à une entreprise » (origine proposée : le comptable et la DAF) : ce profil consulte.',
            key: Key('tiers:reserve'), icone: LucideIcons.lock)
      else if (widget.lignes.isEmpty)
        const NoteSigh('Aucune ligne du relevé n’est disponible : chaque facture patient de la période est déjà réclamée, ou la compagnie n’a rien à facturer.',
            key: Key('tiers:vide'), ton: TonSigh.attention, icone: LucideIcons.inbox)
      else
        CarteSigh(
            titre: 'Émettre une facture à une entreprise',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FormulaireSigh(key: ValueKey(_signature), controleur: ctl!),
              const SizedBox(height: 16),
              Align(
                  alignment: Alignment.centerLeft,
                  child: BoutonSigh(key: const Key('tiers:emettre'), libelle: 'Émettre la facture à l’entreprise', icone: LucideIcons.send, onPressed: () => _emettre(context))),
            ])),
      const SizedBox(height: 16),
      TableauSigh(
        key: const Key('tiers:table'),
        lignes: trierPar<Fiche>(emises, (r) => r['date'], descendant: true),
        recherche: false,
        messageVide: 'Aucune facture à une entreprise pour cette compagnie.',
        colonnes: [
          const ColonneTableau(cle: 'numero', libelle: 'Numéro'),
          ColonneTableau(cle: 'date', libelle: 'Émise le', texte: (r) => dateDe(r['date'])),
          ColonneTableau(cle: 'acheteurNom', libelle: 'Entreprise', texte: (r) => '${r['acheteurNom']} (IFU ${r['acheteurIfu']})'),
          const ColonneTableau(cle: 'souscripteur', libelle: 'Souscripteur'),
          ColonneTableau(cle: 'montantTTC', libelle: 'Montant', droite: true, texte: (r) => money(r['montantTTC'])),
          ColonneTableau(cle: 'aibTaux', libelle: 'AIB', droite: true, texte: (r) => '${r['aibTaux']} % — ${money(r['aibMontant'] ?? 0)}'),
          ColonneTableau(cle: 'netAPayer', libelle: 'Net à payer', droite: true, texte: (r) => money(r['netAPayer'])),
          ColonneTableau(
              cle: 'statutMecef',
              libelle: 'MECeF',
              texte: (r) => r['numeroMecef'] != null ? '${r['numeroMecef']}' : (r['statutMecef'] == 'en_attente' ? 'En attente de certification' : '—'),
              rendu: (_, r) => r['numeroMecef'] != null
                  ? BadgeSigh('${r['numeroMecef']}', ton: TonSigh.succes)
                  : (r['statutMecef'] == 'en_attente' ? const BadgeSigh('En attente de certification', ton: TonSigh.attention) : const Text('—'))),
        ],
        actionsLigne: (ctx, r) => [
          BoutonIcone(
              icone: LucideIcons.eye,
              libelle: 'Rattachement au relevé',
              onPressed: () => afficherTiroir<void>(ctx,
                  titre: '${r['numero']}',
                  sousTitre: '${r['acheteurNom']}',
                  corps: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    DescListeSigh([
                      ('Numéro', r['numero']),
                      ('Entreprise', '${r['acheteurNom']} — IFU ${r['acheteurIfu']}'),
                      ('Situation d’AIB choisie', r['aibSituation']),
                      ('Taux d’AIB', '${r['aibTaux']} %'),
                      ('Motif du taux', r['aibMotif']),
                      ('Montant', money(r['montantTTC'])),
                      ('Net à payer', money(r['netAPayer'])),
                      ('Émise par', r['emisePar']),
                    ]),
                    const SizedBox(height: 12),
                    NoteSigh(rattachementFactureTiers(r), icone: LucideIcons.link),
                  ]))),
        ],
      ),
    ]);
  }
}
