import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import 'magasin.dart';
import 'parametres_aib.dart';
import 'mecef_poste.dart';

/// Ce que la normalisation d'une vente a rendu : un numéro, un refus nommé (code, motif, geste) ou rien à faire.
class ResultatNormalisation {
  const ResultatNormalisation.ok(this.numero, {required this.annuler})
      : code = null,
        motif = null,
        geste = null,
        ignore = false;
  const ResultatNormalisation.refus(this.code, this.motif, this.geste,
      {required this.annuler})
      : numero = null,
        ignore = false;
  const ResultatNormalisation.ignoree()
      : numero = null,
        code = null,
        motif = null,
        geste = null,
        ignore = true,
        annuler = _rien;
  final String? numero;
  final String? code;
  final String? motif;
  final String? geste;
  final bool ignore;

  /// Restitue ce que la normalisation a écrit (la pièce revient en attente).
  final VoidCallback annuler;
  bool get ok => numero != null;
}

void _rien() {}

/// Les numéros déjà portés par une facture ou un avoir : un numéro de pièce ne se reprend jamais.
Set<String> numerosPris(Magasin m) => {
      for (final c in ['factures', 'avoirs'])
        for (final f in m.collection(c).toutes)
          if ('${f['numeroMecef'] ?? ''}'.isNotEmpty) '${f['numeroMecef']}'
    };

/// NORMALISER UNE VENTE (E2299, lot L3). La décision (refus nommés, acheteur, montants entiers) est celle du domaine. L'ÉMISSION du numéro est celle de
/// l'ADAPTATEUR du mode en vigueur (`mecef.mode`) : tant qu'aucun adaptateur n'est configuré (boîtier ou e-MECeF, lot M3), le poste ne fabrique AUCUN
/// numéro : la vente reste EN ATTENTE de certification, avec le code, le motif et le geste du refus nommé `MECEF_NON_CONFIGURE`. L'encaissement reste acquis.
/// Une vente déjà normalisée ne se renormalise jamais ; un numéro déjà porté n'est jamais réécrit ; l'état `en_attente` est écrit AVANT l'émission ; un refus
/// des montants écrit la pièce `refusee` (identifiant stocké `rejete`) en nommant le code.
ResultatNormalisation normaliserVente(
  Magasin m,
  String factureId, {
  Map<String, Object?>? acheteur,
  required DateTime maintenant,
  num tauxTvaCourant = 0,
  d.AdaptateurMecef? adaptateur,
}) {
  final col = m.collection('factures');
  final fac = col.parId(factureId);
  if (fac == null) {
    return ResultatNormalisation.refus(
        'FACTURE_INTROUVABLE',
        'La facture $factureId n’existe pas.',
        'Rouvrir la caisse et choisir une pièce du registre.',
        annuler: _rien);
  }
  // MECeF fermé (bascule P0-5 de Baguidi) : rien à normaliser, la pièce ne porte aucun champ fiscal.
  final mecefActif = d.fermeturesEnVigueur(m.collection('modulesActifs').toutes).mecefEnService;
  // LE TAUX PAR DÉFAUT SE LIT AU BARÈME (D1, Direction, 09/11/2026) : une pièce qui ne porte aucun taux (retransmission d'une pièce restée sans taux, vente
  // sans acheteur) reçoit le taux ARRÊTÉ en vigueur à la date de la facture pour la situation que le branchement IFU donne à son IFU ; sans taux arrêté, le
  // taux de REPLI des Paramètres (0 % à la graine), jamais un taux inventé. Le motif du moteur est journalisé et porté par la pièce. Une pièce ou une
  // fenêtre qui porte déjà son taux le GARDE.
  Map<String, Object?>? acheteurEffectif = acheteur;
  d.AibParDefaut? defaut;
  final porteTaux = '${acheteur?['aibTaux'] ?? fac['aibTaux'] ?? ''}'.isNotEmpty;
  if (mecefActif && !porteTaux) {
    final dateAib = DateTime.tryParse('${fac['date'] ?? ''}') ?? maintenant;
    final ifu = acheteur != null && acheteur.containsKey('ifu') ? acheteur['ifu'] : fac['ifuClient'];
    defaut = aibParDefaut(m, dateAib, ifu: ifu);
    acheteurEffectif = {
      ...?acheteur,
      'aibTaux': defaut.taux,
      'aibSituation': defaut.situation,
      'aibRepli': defaut.repli,
    };
  }
  final params = parametresAib(m, maintenant);
  final prep = d.preparerNormalisation(fac,
      acheteurSaisi: acheteurEffectif,
      modeDesactive: !mecefActif,
      longueurIfu: params.longueurIfu,
      tauxTvaCourant: tauxTvaCourant);
  if (prep.ignore) return const ResultatNormalisation.ignoree();
  final annulations = <VoidCallback>[];
  void undo() {
    for (final u in annulations.reversed) {
      u();
    }
  }

  if (!prep.ok) {
    final r = prep.refus!;
    // Un refus des MONTANTS écrit la pièce refusée en nommant le code ; les autres refus (pro-forma, règlement absent, déjà normalisée, acheteur)
    // n'écrivent rien.
    const deMontants = {
      'AUCUNE_LIGNE',
      'QUANTITE_INVALIDE',
      'PRIX_DECIMAL',
      'MONTANT_DECIMAL',
      'REMISE_INVALIDE',
      'TOTAL_INCOHERENT',
      'AIB_TAUX_INVALIDE'
    };
    if (deMontants.contains(r.code)) {
      final ach = d.acheteurDePiece(fac, saisi: acheteurEffectif, longueurIfu: params.longueurIfu).acheteur;
      annulations.add(col.mettreAJour(factureId, {
        'statutMecef': 'rejete',
        'codeRetour': r.code,
        'motifRefusMecef': r.motif,
        if (ach != null) ...{
          'ifuClient': ach.ifu,
          'acheteurNom': ach.nom,
          // Un taux LU au barème par défaut n'est PAS porté par une pièce refusée : la retransmission le relira à sa date, jamais un taux périmé.
          if (defaut == null) ...{
            'aibTaux': ach.aibTaux,
            if (ach.aibSituation != null) 'aibSituation': ach.aibSituation,
            if (ach.aibRepli) 'aibRepli': true,
          },
        },
      }));
      m.journaliser('Normalisation refusée', 'MECEF', 'facture',
          '${fac['numero']}', {'statutMecef': fac['statutMecef']}, {'code': r.code});
    }
    return ResultatNormalisation.refus(r.code, r.motif, r.geste, annuler: undo);
  }
  final a = prep.acheteur!;
  final bascule = {
    'ifuClient': a.ifu,
    'acheteurNom': a.nom,
    'aibTaux': a.aibTaux,
    if (a.aibSituation != null) 'aibSituation': a.aibSituation,
    if (a.aibRepli) 'aibRepli': true,
    if (defaut != null) 'aibMotif': defaut.motif,
  };
  // L'état est écrit AVANT l'émission (un redémarrage reprend au bon endroit).
  annulations.add(col.mettreAJour(factureId,
      {'statutMecef': 'en_attente', 'codeRetour': null, 'motifRefusMecef': null, ...bascule}));
  final porte = '${fac['numeroMecef'] ?? ''}';
  if (porte.isEmpty) {
    // Aucun numéro à poser sans l'appareil : l'adaptateur configuré émettra (asynchrone, lot M3) ; sinon la vente RESTE en attente de certification.
    final ad = adaptateur ?? adaptateurDuPoste(m, maintenant);
    if (ad.configure) {
      throw StateError('Adaptateur MECeF configuré : l’émission est asynchrone (lot M3), normaliserVente doit le devenir.');
    }
    final refus = ad.refus!;
    annulations.add(col.mettreAJour(factureId, d.champsEnAttenteCertification(refus, ad.mode)));
    m.journaliser('Normalisation en attente (adaptateur non configuré)', 'MECEF', 'facture', '${fac['numero']}',
        {'statutMecef': fac['statutMecef']},
        {'statutMecef': 'en_attente', 'code': refus.code, 'mode': ad.mode, if (defaut != null) 'aib': '${a.aibTaux} % — ${defaut.motif}'});
    return ResultatNormalisation.refus(refus.code, refus.motif, refus.geste, annuler: undo);
  }
  // Un numéro déjà porté (pièce ancienne, ou réponse réconciliée) n'est JAMAIS réécrit : on ne rappelle pas l'appareil.
  annulations.add(col.mettreAJour(factureId, {
    'statutMecef': 'valide',
    'numeroMecef': porte,
    'codeRetour': 'OK-200',
    'dateTransmission': maintenant.toIso8601String(),
    'aibMontant': prep.montants!.aib,
    'normalisePar': m.utilisateur,
  }));
  m.journaliser('Normalisation', 'MECEF', 'facture', '${fac['numero']}',
      {'statutMecef': 'en_attente'}, {'statutMecef': 'valide', 'numero': porte, if (defaut != null) 'aib': '${a.aibTaux} % — ${defaut.motif}'});
  return ResultatNormalisation.ok(porte, annuler: undo);
}
