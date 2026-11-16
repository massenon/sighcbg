import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart' as d;

import 'gestes_magasin.dart';
import 'magasin.dart';
import 'mecef_poste.dart';
import 'parametres_aib.dart';

/// Ce qu'a rendu l'émission d'une facture à une entreprise : la fiche écrite (avec son éventuel refus de certification, qui n'annule pas l'émission) ou le refus nommé.
class ResultatFactureTiers {
  const ResultatFactureTiers.ok(this.fiche, {required this.annuler, this.codeMecef, this.motifMecef})
      : refus = null;
  const ResultatFactureTiers.refus(this.refus)
      : fiche = null,
        annuler = _rien,
        codeMecef = null,
        motifMecef = null;
  final Map<String, Object?>? fiche;
  final d.RefusTiersPayeur? refus;
  final VoidCallback annuler;

  /// Le code et le motif de la certification restée EN ATTENTE (aucun appareil branché : le poste ne fabrique jamais un numéro).
  final String? codeMecef, motifMecef;
  bool get ok => fiche != null;
}

void _rien() {}

/// ÉMETTRE une facture à une entreprise (point 2 du 17/11/2026). Toute la DÉCISION est celle du domaine (`emettreFactureTiersPayeur` : geste, ligne du relevé, filles déjà réclamées, IFU, nom,
/// situation d'AIB choisie, taux du barème arrêté, montants entiers) ; ici, la colle : lire les fiches du magasin, écrire la pièce, la mettre EN ATTENTE de certification comme toute
/// vente normalisée sans appareil (le mode en vigueur dit pourquoi, aucun numéro n'est fabriqué), et journaliser (RG-12). Un refus n'écrit RIEN.
ResultatFactureTiers emettreFactureTiers(
  Magasin m, {
  required String role,
  required DateTime maintenant,
  required Object? acheteurIfu,
  required Object? acheteurNom,
  required Object? situationChoisie,
  required String compagnieCode,
  required String compagnieNom,
  required String periode,
  required String periodeLibelle,
  required String depuis,
  required d.AssFilleMere? ligne,
  bool fileul = false,
  String? note,
}) {
  final v = d.emettreFactureTiersPayeur(
    role: role,
    gestes: gestesDuMagasin(m),
    fileul: fileul,
    acheteurIfu: acheteurIfu,
    acheteurNom: acheteurNom,
    situationChoisie: situationChoisie,
    compagnieCode: compagnieCode,
    compagnieNom: compagnieNom,
    periode: periode,
    periodeLibelle: periodeLibelle,
    depuis: depuis,
    ligne: ligne,
    facturesTiers: m.collection(d.colFacturesTiers).toutes,
    facturesMere: m.collection('facturesMere').actives,
    date: maintenant,
    situations: m.collection('situationsAib').actives,
    versions: m.collection('baremeAib').actives,
    parametres: parametresAib(m, maintenant),
    auteur: m.utilisateur,
    note: note,
  );
  if (v.refus != null) return ResultatFactureTiers.refus(v.refus!);
  final col = m.collection(d.colFacturesTiers);
  final ecrite = col.inserer({...v.fiche!, '_creePar': m.utilisateur, '_creeLe': maintenant.toIso8601String()}, prefixe: 'FTP');
  // MECeF fermé (bascule d'activité) : aucun champ fiscal ; sinon la pièce est EN ATTENTE de certification, avec le refus nommé de l'adaptateur du mode en vigueur.
  final mecefActif = d.fermeturesEnVigueur(m.collection('modulesActifs').toutes).mecefEnService;
  String? code, motif;
  if (!mecefActif) {
    // Aucun champ fiscal : la pièce n'a rien à certifier.
    col.mettreAJour(ecrite.fiche['id'], {'statutMecef': null, 'baseMecef': null}, journaliser: false);
  } else {
    final ad = adaptateurDuPoste(m, maintenant);
    if (!ad.configure) {
      final refus = ad.refus!;
      final modele = ad is d.AdaptateurNonConfigure ? ad.modeleBoitier : null;
      col.mettreAJour(ecrite.fiche['id'], {...d.champsEnAttenteCertification(refus, ad.mode), ...d.champsAppareilMecef(ad.mode, modele)});
      code = refus.code;
      motif = refus.motif;
    }
  }
  m.journaliser('Facture à une entreprise émise', 'M9', 'FactureTiersPayeur', '${v.fiche!['numero']}', null, {
    'acheteur': '${v.fiche!['acheteurNom']} (IFU ${v.fiche!['acheteurIfu']})',
    'situationAib': v.fiche!['aibSituation'],
    'tauxAib': v.fiche!['aibTaux'],
    'montant': v.fiche!['montantTTC'],
    'souscripteur': v.fiche!['souscripteur'],
    'filles': v.fiche!['nbFilles'],
    'mecef': code ?? 'sans objet',
  });
  return ResultatFactureTiers.ok(m.collection(d.colFacturesTiers).parId(ecrite.fiche['id']) ?? ecrite.fiche, annuler: ecrite.annuler, codeMecef: code, motifMecef: motif);
}
