import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../core/service_installation.dart';
import '../../donnees/facture_tiers_poste.dart';
import '../../donnees/magasin.dart';
import '../../impression/apercu.dart';
import '../../impression/identite_poste.dart';
import '../../impression/piece.dart';
import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../../shell/gestes_ecran.dart';
import '../../sync/service_validations_deposees.dart';
import '../m8/commun.dart' show mecefEnService;
import 'commun.dart';
import 'facture_tiers_piece.dart';

/// L'onglet « Factures à une entreprise » de `m9-facture-mere` (Direction de Baguidi, 17/11/2026, point 2) : la vente normalisée adressée à l'entreprise qui prend un patient en charge, avec
/// l'IFU et le nom de l'acheteur et la situation d'AIB CHOISIE par le comptable. La pièce naît d'une LIGNE du relevé de M9 (souscripteur, compagnie, période) : son montant est la part prise
/// en charge de cette ligne, jamais une saisie ; la facture du patient reste sans acheteur ni AIB. La commande est ABSENTE sans le geste réservé « Émettre une facture à une entreprise »
/// (jamais grisée), et le moteur refuse en nommant si on le contourne.
///
/// La SUITE de la pièce (17/11/2026) : elle s'IMPRIME (aperçu et PDF, en-tête légal unique, signataires du réglage), elle se CORRIGE par un avoir (moteur unique, jamais de réécriture) et elle se
/// TRANSMET au dispositif fiscal (circuit MECeF des autres ventes : en attente → certifiée / rejetée). Sur un FILEUL, l'émission, l'avoir et la transmission ne s'écrivent pas : la commande DÉPOSE une
/// demande que la mère applique sous le rôle de son auteur, et l'écran dit « transmise à la mère, en attente » ou donne le refus nommé.
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

  bool get _rattache => ServiceInstallation.de(c.magasin).rattache;

  /// Le geste réservé : sur un fileul aussi (la commande dépose alors une demande, la mère l'applique avec SA matrice).
  bool get _peut => gestePeutEcran(c, gesteFactureTiersEmettre);

  ServiceValidationsDeposees get _service => ServiceValidationsDeposees.de(c.magasin);

  String _libelleSituation(Fiche f) {
    final s = c.magasin.collection('situationsAib').actives.where((x) => '${x['code']}' == '${f['aibSituation']}').firstOrNull;
    return s == null ? '${f['aibSituation'] ?? ''}' : '${s['libelle'] ?? s['code']}';
  }

  /// L'APERÇU de la pièce (et son impression / PDF) : l'en-tête légal à la date de la pièce, les signataires du réglage, les avoirs portés, le bloc fiscal seulement si elle est certifiée.
  void _imprimer(BuildContext ctx, Fiche f) {
    final m = c.magasin;
    afficherApercu(
        ctx,
        pieceFactureTiers(f,
            avoirs: m.collection(colAvoirsTiers).actives,
            libelleSituation: _libelleSituation(f),
            mecefActif: mecefEnService(m),
            signatures: signatairesPieceFactureTiers(m, c.aujourdhui),
            utilisateur: acteur(c).nom,
            edite: c.aujourdhui,
            reference: PieceA4.reference_(c.aujourdhui, ImpressionPoste.prochainNumero()),
            identite: identiteImprimeeDe(m, datePiece(f, c.aujourdhui))));
  }

  void _refus(BuildContext ctx, String titre, String code, String motif, String? geste) =>
      ToastsSigh.afficher(ctx, '$titre ($code).', type: TypeToast.erreur, detail: '$motif ${geste ?? ''}'.trim(), duree: const Duration(seconds: 12));

  /// Le dépôt d'une demande depuis un fileul : refus nommé dès le poste, ou « transmise à la mère ».
  bool _deposer(BuildContext ctx, String action, Map<String, Object?> charge, {Fiche? facture}) {
    final r = _service.deposerFactureTiers(action, charge, role: c.role, acteur: acteur(c).nom, facture: facture, gestes: droitsGestesEcran(c));
    if (!r.ok) {
      _refus(ctx, 'Demande refusée', r.refus!.code, r.refus!.motif, r.refus!.geste);
      return false;
    }
    ToastsSigh.afficher(ctx, r.dejaDepose ? 'Cette demande attend déjà la mère.' : 'Demande transmise à la mère.',
        type: TypeToast.succes, detail: 'Elle l’applique sous votre rôle, avec ses numéros et son boîtier : la pièce reviendra ici par la synchronisation.');
    return true;
  }

  /// L'AVOIR : motif, montant (vide : tout ce qui reste), suite donnée (créance réduite ou remboursement en espèces). Le moteur est celui de la caisse.
  void _avoir(BuildContext ctx, Fiche f) {
    final reste = resteAvoirableFactureTiers(f);
    final form = ControleurFormulaire([
      ChampDef(nom: 'motif', libelle: 'Motif de l’avoir', type: TypeChamp.textarea, lignes: 2, col: ColChamp.plein, requis: true, aide: 'L’entreprise et la compagnie liront pourquoi la pièce est contre-passée.'),
      ChampDef(nom: 'montant', libelle: 'Montant de l’avoir (FCFA) — vide : tout le reste (${money(reste)})', type: TypeChamp.nombre, col: ColChamp.demi),
      const ChampDef(
          nom: 'remboursement',
          libelle: 'Suite donnée',
          type: TypeChamp.select,
          col: ColChamp.demi,
          options: [OptionChamp('creance', 'Créance réduite'), OptionChamp('especes', 'Remboursement en espèces')]),
    ], {'remboursement': 'creance'});
    afficherModale<void>(ctx,
        titre: 'Avoir sur ${f['numero']}',
        sousTitre: '${f['acheteurNom']} — reste avoirable ${money(reste)}',
        corps: FormulaireSigh(controleur: form),
        pied: (fermer) => [
              BoutonSigh(libelle: 'Annuler', variante: VarianteBouton.secondaire, onPressed: fermer),
              BoutonSigh(
                  key: const Key('tiers:avoir-valider'),
                  libelle: _rattache ? 'Transmettre la demande d’avoir' : 'Émettre l’avoir',
                  icone: LucideIcons.undo2,
                  onPressed: () {
                    final v = form.valider();
                    if (v == null) {
                      ToastsSigh.afficher(ctx, 'Le formulaire comporte des erreurs.', type: TypeToast.erreur);
                      return;
                    }
                    final montant = v['montant'] is num ? v['montant'] as num : num.tryParse('${v['montant'] ?? ''}');
                    if (_rattache) {
                      if (_deposer(ctx, factureTiersActionAvoir, {'factureId': f['id'], 'motif': '${v['motif']}', if (montant != null) 'montant': montant, 'remboursement': '${v['remboursement']}'}, facture: f)) fermer();
                      return;
                    }
                    final r = emettreAvoirTiers(c.magasin,
                        role: c.role, maintenant: c.aujourdhui, factureId: '${f['id']}', motif: '${v['motif']}', montant: montant, remboursement: '${v['remboursement']}');
                    if (!r.ok) {
                      _refus(ctx, 'Avoir refusé', r.refus!.code, r.refus!.motif, r.refus!.geste);
                      return;
                    }
                    fermer();
                    ToastsSigh.afficher(ctx, 'Avoir ${r.fiche!['reference']} émis sur ${f['numero']}.',
                        type: TypeToast.succes,
                        detail: '${money(r.fiche!['montant'])} contre-passés (brouillon comptable équilibré). La pièce émise n’est pas réécrite : elle porte son avoir.',
                        annuler: r.annuler,
                        messageAnnulation: 'Avoir annulé — la pièce est archivée.');
                    setState(() => _signature = '');
                  }),
            ]);
  }

  /// La TRANSMISSION au dispositif fiscal (« Transmettre à la MECeF »).
  Future<void> _transmettre(BuildContext ctx, Fiche f) async {
    if (_rattache) {
      _deposer(ctx, factureTiersActionTransmettre, {'factureId': f['id']}, facture: f);
      return;
    }
    final r = await transmettreFactureTiers(c.magasin, '${f['id']}', role: c.role, maintenant: c.aujourdhui);
    if (!ctx.mounted) return;
    if (!r.ecrit) {
      _refus(ctx, 'Transmission refusée', r.refus?.code ?? '', r.refus?.motif ?? '', r.refus?.geste);
      return;
    }
    if (r.certifiee) {
      ToastsSigh.afficher(ctx, 'Facture ${f['numero']} certifiée.', type: TypeToast.succes, detail: '${r.fiche?['numeroMecef']}', annuler: r.annuler);
    } else if (r.enAttente) {
      ToastsSigh.afficher(ctx, 'Certification en attente (${r.refus!.code}).', type: TypeToast.attention, detail: '${r.refus!.motif} ${r.refus!.geste}', duree: const Duration(seconds: 12));
    } else {
      ToastsSigh.afficher(ctx, 'Facture ${f['numero']} rejetée (${r.refus?.code}).', type: TypeToast.erreur, detail: r.refus?.motif ?? '', duree: const Duration(seconds: 12));
    }
    setState(() {});
  }

  /// Les demandes de CE poste que la mère n'a pas encore appliquées, ou qu'elle a refusées : l'attente se dit, le motif nommé revient à l'auteur.
  Widget _demandes() {
    final ouvertes = [
      for (final d in _service.depots.actives)
        if (d['genre'] == valGenreFactureTiers && (d['etat'] == valDepotDeposee || d['etat'] == valDepotRefusee)) d
    ];
    if (ouvertes.isEmpty) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final d in ouvertes)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: d['etat'] == valDepotDeposee
                    ? NoteSigh('${d['libelle']} — transmise à la mère, en attente (${d['cible']}). Elle l’applique sous le rôle de son auteur, ${d['demandePar']}.', key: Key('tiers:demande:${d['id']}'), ton: TonSigh.attention, icone: LucideIcons.clock)
                    : NoteSigh('${d['libelle']} — refusée par la mère (${d['resultatCode']}) : ${d['resultatMotif']} ${d['resultatGeste'] ?? ''}'.trim(),
                        key: Key('tiers:demande:${d['id']}'), ton: TonSigh.danger, icone: LucideIcons.fileX)),
        ]));
  }

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
    if (_rattache) {
      // Un fileul ne numérote ni ne certifie : il DÉPOSE la demande (la mère rejoue la ligne du relevé avec ses factures).
      _deposer(ctx, factureTiersActionEmettre, {
        'compagnieCode': widget.code,
        'periode': widget.periode,
        'souscripteur': '${v['souscripteur']}',
        'ifu': '${v['ifu'] ?? ''}',
        'nom': '${v['nom'] ?? ''}',
        'situation': '${v['situation'] ?? ''}',
        'note': '${v['note'] ?? ''}',
      });
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
      _demandes(),
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
              if (_rattache)
                const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: NoteSigh('Ce poste est un fileul : l’émission est tenue par la mère (numérotation et boîtier fiscal). La commande dépose votre demande, que la mère applique sous votre rôle.', icone: LucideIcons.send)),
              Align(
                  alignment: Alignment.centerLeft,
                  child: BoutonSigh(
                      key: const Key('tiers:emettre'),
                      libelle: _rattache ? 'Transmettre la demande à la mère' : 'Émettre la facture à l’entreprise',
                      icone: LucideIcons.send,
                      onPressed: () => _emettre(context))),
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
              cle: 'montantAvoirs',
              libelle: 'Avoirs',
              droite: true,
              texte: (r) => n(r['montantAvoirs']) > 0 ? '− ${money(r['montantAvoirs'])}' : '—'),
          ColonneTableau(
              cle: 'statutMecef',
              libelle: 'MECeF',
              texte: (r) => r['numeroMecef'] != null ? '${r['numeroMecef']}' : libelleTransmissionTiers(r),
              rendu: (_, r) => r['numeroMecef'] != null
                  ? BadgeSigh('${r['numeroMecef']}', ton: TonSigh.succes)
                  : (r['statutMecef'] == 'en_attente'
                      ? const BadgeSigh('En attente de certification', ton: TonSigh.attention)
                      : (r['statutMecef'] == 'rejete' ? BadgeSigh('Rejetée${r['codeRetour'] == null ? '' : ' (${r['codeRetour']})'}', ton: TonSigh.danger) : const Text('—')))),
        ],
        actionsLigne: (ctx, r) => [
          BoutonIcone(key: Key('tiers:imprimer:${r['id']}'), icone: LucideIcons.printer, libelle: 'Aperçu et impression', onPressed: () => _imprimer(ctx, r)),
          if (_peut && resteAvoirableFactureTiers(r) > 0)
            BoutonIcone(key: Key('tiers:avoir:${r['id']}'), icone: LucideIcons.undo2, libelle: 'Émettre un avoir', onPressed: () => _avoir(ctx, r)),
          if (_peut && mecefEnService(c.magasin) && ['en_attente', 'rejete', 'expiree'].contains(r['statutMecef']) && resteAvoirableFactureTiers(r) > 0)
            BoutonIcone(key: Key('tiers:transmettre:${r['id']}'), icone: LucideIcons.send, libelle: 'Transmettre à la MECeF', onPressed: () => _transmettre(ctx, r)),
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
                      ('Transmission MECeF', libelleTransmissionTiers(r)),
                      if (r['codeRetour'] != null && r['statutMecef'] != 'valide') ('Code et motif de la transmission', '${r['codeRetour']} — ${r['motifRefusMecef'] ?? ''}'),
                      if (n(r['montantAvoirs']) > 0) ('Avoirs portés', money(r['montantAvoirs'])),
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
