import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import 'magasin.dart';
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

/// NORMALISER UNE VENTE (E2299, lot L3). La décision (refus nommés, montants entiers) est celle du domaine. L'ÉMISSION du numéro est celle de l'ADAPTATEUR du
/// mode en vigueur (`mecef.mode`) : tant qu'aucun adaptateur n'est configuré (boîtier ou e-MECeF, lot M3), le poste ne fabrique AUCUN numéro : la vente reste
/// EN ATTENTE de certification, avec le code, le motif et le geste du refus nommé `MECEF_NON_CONFIGURE`. L'encaissement reste acquis. Une vente déjà normalisée
/// ne se renormalise jamais ; un numéro déjà porté n'est jamais réécrit ; l'état `en_attente` est écrit AVANT l'émission ; un refus des montants écrit la pièce
/// `refusee` (identifiant stocké `rejete`) en nommant le code.
///
/// UNE FACTURE DE LA CAISSE EST CELLE D'UN PATIENT (décision de la Direction de Baguidi du 16/11/2026, E3770) : elle se normalise SANS acheteur ni AIB — le
/// patient paie le total. Aucun acheteur n'est saisi ni lu, le barème de l'AIB n'est pas consulté, aucun refus d'acheteur n'est possible. L'ancienne règle (la
/// fenêtre « Facture normalisée » et le taux par défaut lu au barème, D1) a été portée puis corrigée par cette décision ; le moteur de l'acheteur reste au
/// domaine pour une vente à un tiers payeur, qu'aucune porte du poste n'émet aujourd'hui.
ResultatNormalisation normaliserVente(
  Magasin m,
  String factureId, {
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
  final prep = d.preparerNormalisation(fac,
      modeDesactive: !mecefActif,
      tauxTvaCourant: tauxTvaCourant,
      facturePatient: true);
  if (prep.ignore) return const ResultatNormalisation.ignoree();
  final annulations = <VoidCallback>[];
  void undo() {
    for (final u in annulations.reversed) {
      u();
    }
  }

  if (!prep.ok) {
    final r = prep.refus!;
    // Un refus des MONTANTS écrit la pièce refusée en nommant le code ; les autres refus (pro-forma, règlement absent, déjà normalisée, prix à valoriser)
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
      // Facture patient (E3770) : aucun acheteur ni taux n'est porté, la retransmission se fera sous la même règle.
      annulations.add(col.mettreAJour(factureId, {
        'statutMecef': 'rejete',
        'codeRetour': r.code,
        'motifRefusMecef': r.motif,
      }));
      m.journaliser('Normalisation refusée', 'MECEF', 'facture',
          '${fac['numero']}', {'statutMecef': fac['statutMecef']}, {'code': r.code});
    }
    return ResultatNormalisation.refus(r.code, r.motif, r.geste, annuler: undo);
  }
  // Ce que la pièce portait encore d'un acheteur ou d'un taux (pièce encaissée avant la décision du 16/11/2026) : retiré, et dit au journal (RG-12).
  final ancienAcheteur = {
    for (final k in ['ifuClient', 'acheteurNom', 'aibTaux', 'aibSituation'])
      if ('${fac[k] ?? ''}'.isNotEmpty && !(k == 'aibTaux' && '${fac[k]}' == '${d.mecefAibFacturePatient}')) k: fac[k]
  };
  final bascule = {...d.champsFacturePatientSansAib};
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
    // Le MODÈLE du boîtier (réglage de clinique) est porté là où le mode l'est : sur la pièce et au journal MECeF (mode boîtier seulement).
    final modele = ad is d.AdaptateurNonConfigure ? ad.modeleBoitier : null;
    final appareil = d.champsAppareilMecef(ad.mode, modele);
    annulations.add(col.mettreAJour(factureId, {...d.champsEnAttenteCertification(refus, ad.mode), ...appareil, 'aibMontant': prep.montants!.aib}));
    m.journaliser('Normalisation en attente (adaptateur non configuré)', 'MECEF', 'facture', '${fac['numero']}',
        {'statutMecef': fac['statutMecef'], ...ancienAcheteur},
        {'statutMecef': 'en_attente', 'code': refus.code, 'mode': ad.mode, if (appareil.isNotEmpty) 'boitier': modele, 'aib': _aibJournal(ancienAcheteur)});
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
      {'statutMecef': 'en_attente'}, {'statutMecef': 'valide', 'numero': porte, 'aib': _aibJournal(ancienAcheteur)});
  return ResultatNormalisation.ok(porte, annuler: undo);
}

/// La mention de l'AIB au journal MECeF : la facture d'un patient n'en porte pas ; une pièce qui portait encore un acheteur ou un taux le dit.
String _aibJournal(Map<String, Object?> ancien) => ancien.isEmpty
    ? 'aucun — facture patient, normalisée sans acheteur ni AIB'
    : 'aucun — facture patient, normalisée sans acheteur ni AIB (retiré : ${ancien.entries.map((e) => '${e.key} ${e.value}').join(', ')})';
