import 'dart:async';

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
  String? auteur,
  Map<String, Object?> extra = const {},
  d.DroitsGestes? gestes,
}) {
  // [gestes] : les droits EN FORCE de l'appelant (la mère qui applique une demande passe sa matrice : rôle archivé, module fermé) ; absents, ceux des fiches du magasin.
  // [auteur] : celui qui a fait le GESTE (la mère qui applique la demande d'un fileul signe sous son nom, jamais sous le sien) ; [extra] : la trace du dépôt qui l'a demandée.
  final v = d.emettreFactureTiersPayeur(
    role: role,
    gestes: gestes ?? gestesDuMagasin(m),
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
    auteur: auteur ?? m.utilisateur,
    note: note,
  );
  if (v.refus != null) return ResultatFactureTiers.refus(v.refus!);
  final col = m.collection(d.colFacturesTiers);
  final ecrite = col.inserer({...v.fiche!, ...extra, '_creePar': auteur ?? m.utilisateur, '_creeLe': maintenant.toIso8601String()}, prefixe: 'FTP');
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
    if (extra['demandePar'] != null) 'déposée par': extra['demandePar'],
    if (extra['demandeDepotId'] != null) 'dépôt': extra['demandeDepotId'],
  });
  return ResultatFactureTiers.ok(m.collection(d.colFacturesTiers).parId(ecrite.fiche['id']) ?? ecrite.fiche, annuler: ecrite.annuler, codeMecef: code, motifMecef: motif);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La ligne du relevé, rejouée par la mère pour la demande d'un fileul
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// La ligne du relevé de M9 d'une compagnie, sur une périodicité, pour un souscripteur : les factures patients non réclamées (ni par une facture à une entreprise active ni par une facture mère
/// émise), la fenêtre de dates de la périodicité arrêtée à [maintenant]. C'est ce que l'écran offre au comptable ; la mère la REJOUE avec SES factures pour appliquer la demande d'un fileul.
({d.AssFilleMere? ligne, String compagnieNom, String periodeLibelle, String depuis}) ligneReleveFactureTiers(Magasin m, {required String compagnieCode, required String periode, required String souscripteur, required DateTime maintenant}) {
  final p = d.assPeriodesMere.where((x) => x.$1 == periode).firstOrNull;
  final jours = p?.$3 ?? 30;
  final depuis = _iso(maintenant.subtract(Duration(days: jours)));
  final nom = d.assNomAssureur(compagnieCode, m.collection('assureurs').actives);
  final reclamees = d.fillesDejaReclamees(facturesTiers: m.collection(d.colFacturesTiers).actives, facturesMere: m.collection('facturesMere').actives);
  final factures = [
    for (final f in m.collection('factures').actives)
      if (!reclamees.containsKey('${f['numero'] ?? f['id']}')) f
  ];
  final lignes = d.assFillesMere(factures, compagnieCode, nom, depuis);
  return (ligne: lignes.where((l) => l.souscripteur == souscripteur).firstOrNull, compagnieNom: nom, periodeLibelle: p?.$2 ?? periode, depuis: depuis);
}

String _iso(DateTime x) => '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------------------------------------------------------------------------
// L'avoir
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce qu'a rendu l'avoir d'une facture à une entreprise : la fiche écrite et de quoi tout défaire (archivage, jamais suppression : RG-14), ou le refus nommé.
class ResultatAvoirTiers {
  const ResultatAvoirTiers.ok(this.fiche, {required this.annuler}) : refus = null;
  const ResultatAvoirTiers.refus(this.refus)
      : fiche = null,
        annuler = _rien;
  final Map<String, Object?>? fiche;
  final d.RefusTiersPayeur? refus;
  final VoidCallback annuler;
  bool get ok => fiche != null;
}

/// ÉMETTRE l'AVOIR d'une facture à une entreprise : la DÉCISION est celle du domaine (`emettreAvoirFactureTiers`, qui appelle le moteur d'avoir UNIQUE : lignes nommées, plafond cumulé, contre-passation
/// équilibrée en brouillon, RG-10) ; ici la colle : lire les fiches, écrire l'avoir dans `avoirsTiers` (collection à part, jamais vers un téléphone ; la série de numéros reste celle de `avoirs`),
/// les deux écritures en BROUILLON, le cumul que la pièce PORTE (`avoirIds`, `montantAvoirs` : elle n'est jamais réécrite), le journal (RG-12). Une écriture refusée par la garde d'un exercice clos
/// défait tout et rend un refus nommé. Un refus n'écrit RIEN.
ResultatAvoirTiers emettreAvoirTiers(
  Magasin m, {
  required String role,
  required DateTime maintenant,
  required String factureId,
  required String motif,
  num? montant,
  String? remboursement,
  String? observations,
  bool fileul = false,
  String? auteur,
  Map<String, Object?> extra = const {},
  d.DroitsGestes? gestes,
}) {
  final factures = m.collection(d.colFacturesTiers);
  final avoirs = m.collection(d.colAvoirsTiers);
  final fac = factures.parId(factureId);
  final idAvoir = 'AVT${(avoirs.toutes.length + 1).toString().padLeft(5, '0')}';
  final quand = auteur ?? m.utilisateur;
  final v = d.emettreAvoirFactureTiers(
      role: role,
      gestes: gestes ?? gestesDuMagasin(m),
      fileul: fileul,
      facture: fac,
      idAvoir: idAvoir,
      motif: motif,
      jour: _iso(maintenant),
      utilisateur: quand,
      montant: montant,
      remboursement: remboursement,
      observations: observations,
      horodatage: maintenant.toIso8601String(),
      mecefActif: d.fermeturesEnVigueur(m.collection('modulesActifs').toutes).mecefEnService,
      avoirsTiers: avoirs.actives,
      avoirsCaisse: m.collection('avoirs').actives,
      facturesMere: m.collection('facturesMere').actives);
  if (v.refus != null) return ResultatAvoirTiers.refus(v.refus!);
  final e = v.emission!;
  final annulations = <VoidCallback>[];
  void defaire() {
    for (final u in annulations.reversed) {
      u();
    }
  }

  try {
    final ins = avoirs.inserer({...e.avoir, ...extra, 'id': idAvoir, 'statut': 'actif', 'factureId': fac!['id']}, prefixe: 'AVT');
    annulations.add(ins.annuler);
    final ecr = m.collection('ecritures');
    final ids = <String>[];
    for (final x in e.ecritures) {
      final w = ecr.inserer({...x, 'statut': 'brouillon'}, prefixe: 'ECR');
      ids.add('${w.fiche['id']}');
      annulations.add(w.annuler);
    }
    avoirs.mettreAJour(idAvoir, {'ecritureIds': ids}, journaliser: false);
    annulations.add(factures.mettreAJour(fac['id'], {
      'avoirIds': [...((fac['avoirIds'] as List?) ?? const []), idAvoir],
      'montantAvoirs': e.montantAvoirs,
    }, journaliser: false));
    m.journaliser('Avoir sur une facture à une entreprise émis', 'M9', 'AvoirFactureTiers', '${e.avoir['reference']}', null, {
      'facture': fac['numero'],
      'acheteur': '${fac['acheteurNom']} (IFU ${fac['acheteurIfu']})',
      'montant': e.avoir['montant'],
      'motif': e.avoir['motif'],
      'cumul': e.montantAvoirs,
      'mecef': e.avoir['statutMecef'] ?? 'sans objet',
      if (extra['demandePar'] != null) 'déposée par': extra['demandePar'],
      if (extra['demandeDepotId'] != null) 'dépôt': extra['demandeDepotId'],
    });
    return ResultatAvoirTiers.ok(avoirs.parId(idAvoir) ?? ins.fiche, annuler: defaire);
  } on EcritureRefusee catch (x) {
    defaire();
    return ResultatAvoirTiers.refus(d.RefusTiersPayeur('ECRITURE_REFUSEE', x.motif, 'Corriger la période comptable (exercice clos) ou passer l’écriture par la clôture, puis réémettre l’avoir.'));
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La transmission au dispositif fiscal (circuit MECeF des autres ventes normalisées)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce qu'a rendu la transmission : l'état (`en_attente`, `certifiee`, `rejetee`), le refus nommé quand la pièce n'est pas certifiée, de quoi défaire.
class ResultatTransmissionFactureTiers {
  const ResultatTransmissionFactureTiers(this.etat, {this.refus, this.fiche, this.annuler = _rien, this.sansEffet = false});
  final String etat;
  final d.RefusMecef? refus;
  final Map<String, Object?>? fiche;
  final VoidCallback annuler;

  /// La pièce était déjà certifiée : rien n'a été rappelé ni écrit (rejeu d'une demande).
  final bool sansEffet;
  bool get certifiee => etat == d.transmissionTiersCertifiee;
  bool get enAttente => etat == d.transmissionTiersEnAttente;
  bool get ecrit => etat.isNotEmpty;
}

/// Le contrôle qui PRÉCÈDE une transmission faite à la main : le poste (un fileul dépose), le module MECeF en service, puis le geste réservé de la retransmission (règle des autres ventes, aucun
/// geste nouveau). `null` : permis. L'émission, elle, tente la première transmission d'office (pas de geste de retransmission).
d.RefusMecef? refusTransmissionFactureTiers(Magasin m, Fiche f, {required String role, bool fileul = false, d.DroitsGestes? gestes}) {
  if (fileul) {
    return const d.RefusMecef('FILEUL_LECTURE_SEULE', 'Ce poste est un fileul : la transmission au dispositif fiscal se fait depuis le poste mère, où le boîtier est branché.',
        'Déposer la demande de transmission : la mère l’applique sous votre rôle.');
  }
  if (!d.fermeturesEnVigueur(m.collection('modulesActifs').toutes).mecefEnService) {
    return const d.RefusMecef('MECEF_FERME', 'Le module MECeF est fermé : aucune pièce ne se transmet au dispositif fiscal.', 'Rouvrir le module dans « Activité des modules ».');
  }
  return d.refusRetransmissionFactureTiers(f, role, gestes: gestes ?? gestesDuMagasin(m));
}

/// TRANSMET une facture à une entreprise (bouton « Transmettre à la MECeF » ; demande d'un fileul appliquée par la mère). Même circuit que `normaliserVente` : mode et adaptateur du réglage ;
/// aucun appareil → la pièce reste EN ATTENTE avec le refus nommé ; numéro reçu → CERTIFIÉE (identifiant, instant de l'appareil, AIB) ; refus de l'appareil → REJETÉE. Une pièce déjà certifiée ne
/// rappelle jamais l'appareil. Chaque tentative après la première compte (`retransmissions`) ; un refus de la préparation défait ce compte. [adaptateur] : un appareil de test ; absent, celui du poste.
Future<ResultatTransmissionFactureTiers> transmettreFactureTiers(
  Magasin m,
  String factureId, {
  required String role,
  required DateTime maintenant,
  bool fileul = false,
  bool controlerDroit = true,
  d.AdaptateurMecef? adaptateur,
  String? auteur,
  d.DroitsGestes? gestes,
}) async {
  final col = m.collection(d.colFacturesTiers);
  final f = col.parId(factureId);
  if (f == null) {
    return const ResultatTransmissionFactureTiers('', refus: d.RefusMecef('FACTURE_TIERS_INTROUVABLE', 'Cette facture à une entreprise n’existe pas.', 'Choisir une pièce du registre.'));
  }
  if (d.porteBlocFiscal(f)) {
    return ResultatTransmissionFactureTiers('', sansEffet: true, refus: d.RefusMecef('DEJA_NORMALISEE', 'La facture ${f['numero']} est déjà normalisée (${f['numeroMecef']}) : elle ne se retransmet jamais.', 'La corriger par un avoir.'));
  }
  if (controlerDroit) {
    final r = refusTransmissionFactureTiers(m, f, role: role, fileul: fileul, gestes: gestes);
    if (r != null) return ResultatTransmissionFactureTiers('', refus: r);
  }
  final annulations = <VoidCallback>[];
  void defaire() {
    for (final u in annulations.reversed) {
      u();
    }
  }

  if (f['statutMecef'] != 'en_attente') {
    annulations.add(col.mettreAJour(f['id'], {'retransmissions': (f['retransmissions'] is num ? (f['retransmissions'] as num).toInt() : 0) + 1}, journaliser: false));
  }
  final ad = adaptateur ?? adaptateurDuPoste(m, maintenant);
  final modele = ad is d.AdaptateurNonConfigure ? ad.modeleBoitier : null;
  final quand = auteur ?? m.utilisateur;
  final immediat = d.transmissionImmediateFactureTiers(f, ad, modeleBoitier: modele);
  final res = immediat ?? await d.transmettreFactureTiersPayeur(f, ad, maintenant: maintenant, auteur: quand, modeleBoitier: modele);
  if (res.patch.isEmpty) {
    defaire();
    return ResultatTransmissionFactureTiers('', refus: res.refus);
  }
  annulations.add(col.mettreAJour(f['id'], res.patch, journaliser: false));
  m.journaliser('Facture à une entreprise : transmission MECeF', 'MECEF', 'FactureTiersPayeur', '${f['numero']}', {'statutMecef': f['statutMecef']},
      {'état': res.etat, 'mode': ad.mode, if (res.refus != null) 'code': res.refus!.code, if (res.certifiee) 'numéro': res.patch['numeroMecef'], 'aib': res.patch['aibMontant']});
  return ResultatTransmissionFactureTiers(res.etat, refus: res.refus, fiche: col.parId(f['id']), annuler: defaire);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La demande d'un fileul, appliquée par la mère
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le verdict qu'écrit la mère sur la fiche d'une demande : `appliquee`, `sans_effet` (déjà fait), `refusee` (code, motif, geste nommés).
class VerdictDemandeFactureTiers {
  const VerdictDemandeFactureTiers(this.etat, {this.code, this.motif, this.geste, this.reference});
  final String etat;
  final String? code, motif, geste;

  /// Le numéro de la pièce que la demande a fait naître (facture ou avoir), pour la notification de l'auteur.
  final String? reference;
}

/// La trace de la demande portée par la pièce qu'elle fait naître : qui l'a demandée, depuis quel poste, quel dépôt.
Map<String, Object?> _traceDemande(Fiche depot) => {'demandeDepotId': depot['id'], 'demandePar': depot['demandePar'], 'demandePoste': depot['demandePoste'], 'demandeLe': depot['demandeLe']};

/// APPLIQUE la demande d'un fileul sur la mère : sous le RÔLE et le NOM de son auteur, avec SA matrice ([gestes]), SES numéros, SON relevé et SES factures — tous les contrôles refaits, jamais
/// recopiés (ce sont les fonctions du geste direct). La pièce est datée de l'APPLICATION (une facture porte le jour où elle est émise et se numérote dans l'ordre), l'auteur du geste y est
/// nommé. SYNCHRONE : les trois demandes le sont tant qu'aucun appareil MECeF n'est branché ; une transmission à un appareil configuré rend `null` (l'appelant l'attend, voir
/// [appliquerTransmissionDemandeeFactureTiers]). `null` aussi pour un dépôt qui n'est pas de ce genre.
VerdictDemandeFactureTiers? appliquerDepotFactureTiers(Magasin m, Fiche depot, {required DateTime maintenant, required d.DroitsGestes gestes}) {
  if (depot['genre'] != d.valGenreFactureTiers) return null;
  final role = '${depot['demandeRole'] ?? ''}';
  final auteur = '${depot['demandePar'] ?? ''}';
  final charge = ((depot['charge'] as Map?) ?? const {}).cast<String, Object?>();
  VerdictDemandeFactureTiers refus(String code, String motif, String? geste) => VerdictDemandeFactureTiers('refusee', code: code, motif: motif, geste: geste);
  switch ('${depot['action']}') {
    case d.factureTiersActionEmettre:
      final rel = ligneReleveFactureTiers(m,
          compagnieCode: '${charge['compagnieCode']}', periode: '${charge['periode']}', souscripteur: '${charge['souscripteur']}', maintenant: maintenant);
      final r = emettreFactureTiers(m,
          role: role,
          maintenant: maintenant,
          acheteurIfu: charge['ifu'],
          acheteurNom: charge['nom'],
          situationChoisie: charge['situation'],
          compagnieCode: '${charge['compagnieCode']}',
          compagnieNom: rel.compagnieNom,
          periode: '${charge['periode']}',
          periodeLibelle: rel.periodeLibelle,
          depuis: rel.depuis,
          ligne: rel.ligne,
          note: '${charge['note'] ?? ''}',
          auteur: auteur,
          extra: _traceDemande(depot),
          gestes: gestes);
      if (!r.ok) return refus(r.refus!.code, r.refus!.motif, r.refus!.geste);
      return VerdictDemandeFactureTiers('appliquee', reference: '${r.fiche!['numero']}');
    case d.factureTiersActionAvoir:
      final montant = charge['montant'];
      final r = emettreAvoirTiers(m,
          role: role,
          maintenant: maintenant,
          factureId: '${charge['factureId']}',
          motif: '${charge['motif'] ?? ''}',
          montant: montant is num ? montant : num.tryParse('${montant ?? ''}'),
          remboursement: '${charge['remboursement'] ?? ''}',
          observations: '${charge['observations'] ?? ''}',
          auteur: auteur,
          extra: _traceDemande(depot),
          gestes: gestes);
      if (!r.ok) return refus(r.refus!.code, r.refus!.motif, r.refus!.geste);
      return VerdictDemandeFactureTiers('appliquee', reference: '${r.fiche!['reference']}');
    case d.factureTiersActionTransmettre:
      final f = m.collection(d.colFacturesTiers).parId(charge['factureId']);
      if (f == null) return refus('FACTURE_TIERS_INTROUVABLE', 'Cette facture à une entreprise n’existe pas sur la mère.', 'Rafraîchir le poste puis redéposer la demande.');
      if (d.porteBlocFiscal(f)) {
        return VerdictDemandeFactureTiers('sans_effet', code: 'DEJA_NORMALISEE', motif: 'La facture ${f['numero']} est déjà normalisée (${f['numeroMecef']}).', reference: '${f['numero']}');
      }
      final ad = adaptateurDuPoste(m, maintenant);
      if (ad.configure) return null;
      final controle = refusTransmissionFactureTiers(m, f, role: role, gestes: gestes);
      if (controle != null) return refus(controle.code, controle.motif, controle.geste);
      return _verdictTransmission(m, f, role: role, auteur: auteur, maintenant: maintenant, gestes: gestes, ad: ad);
    default:
      return refus('ACTION_INCONNUE', 'La demande « ${depot['action']} » est inconnue de la mère.', 'Refaire le geste depuis l’écran de la facture à une entreprise.');
  }
}

VerdictDemandeFactureTiers _verdictTransmission(Magasin m, Fiche f, {required String role, required String auteur, required DateTime maintenant, required d.DroitsGestes gestes, required d.AdaptateurMecef ad}) {
  // Synchrone : seul le chemin SANS appareil passe ici (le contrôle de la file l'a garanti).
  final col = m.collection(d.colFacturesTiers);
  final modele = ad is d.AdaptateurNonConfigure ? ad.modeleBoitier : null;
  final immediat = d.transmissionImmediateFactureTiers(f, ad, modeleBoitier: modele)!;
  if (f['statutMecef'] != 'en_attente') col.mettreAJour(f['id'], {'retransmissions': (f['retransmissions'] is num ? (f['retransmissions'] as num).toInt() : 0) + 1}, journaliser: false);
  if (immediat.patch.isEmpty) {
    return VerdictDemandeFactureTiers('refusee', code: immediat.refus?.code, motif: immediat.refus?.motif, geste: immediat.refus?.geste, reference: '${f['numero']}');
  }
  col.mettreAJour(f['id'], immediat.patch, journaliser: false);
  m.journaliser('Facture à une entreprise : transmission MECeF', 'MECEF', 'FactureTiersPayeur', '${f['numero']}', {'statutMecef': f['statutMecef']},
      {'état': immediat.etat, 'mode': ad.mode, if (immediat.refus != null) 'code': immediat.refus!.code, 'déposée par': auteur});
  // Une pièce REJETÉE (montants ou acheteur à corriger) : la demande est refusée en nommant le code, et la pièce porte le rejet.
  if (immediat.etat == d.transmissionTiersRejetee) {
    return VerdictDemandeFactureTiers('refusee', code: immediat.refus?.code, motif: immediat.refus?.motif, geste: immediat.refus?.geste, reference: '${f['numero']}');
  }
  // Aucun appareil : la pièce reste en attente — c'est une transmission TENTÉE et dite, pas un échec de la demande (elle reprendra quand l'appareil sera branché).
  return VerdictDemandeFactureTiers('appliquee', reference: '${f['numero']}', code: immediat.refus?.code, motif: immediat.refus?.motif, geste: immediat.refus?.geste);
}

/// La transmission DEMANDÉE vers un appareil configuré : asynchrone. Même contrôle et même écriture que le geste direct ([transmettreFactureTiers]), sous le rôle et le nom de l'auteur.
Future<VerdictDemandeFactureTiers> appliquerTransmissionDemandeeFactureTiers(Magasin m, Fiche depot, {required DateTime maintenant, required d.DroitsGestes gestes}) async {
  final charge = ((depot['charge'] as Map?) ?? const {}).cast<String, Object?>();
  final r = await transmettreFactureTiers(m, '${charge['factureId']}', role: '${depot['demandeRole'] ?? ''}', maintenant: maintenant, auteur: '${depot['demandePar'] ?? ''}', gestes: gestes);
  final numero = '${m.collection(d.colFacturesTiers).parId(charge['factureId'])?['numero'] ?? ''}';
  if (r.sansEffet) return VerdictDemandeFactureTiers('sans_effet', code: r.refus?.code, motif: r.refus?.motif, reference: numero);
  if (!r.ecrit) return VerdictDemandeFactureTiers('refusee', code: r.refus?.code, motif: r.refus?.motif, geste: r.refus?.geste, reference: numero);
  return VerdictDemandeFactureTiers('appliquee', reference: numero, code: r.refus?.code, motif: r.refus?.motif, geste: r.refus?.geste);
}
