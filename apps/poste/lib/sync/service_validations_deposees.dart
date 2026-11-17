import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/facture_tiers_poste.dart';
import '../donnees/magasin.dart';
import '../donnees/planning_rh_poste.dart';
import '../core/service_parametres.dart';
import '../donnees/reglages_clinique_poste.dart';
import '../modules/m14/commun_m14.dart' show rolesDe;

/// LA CONTINUITÉ DE SERVICE DES VALIDATIONS AU POSTE (Direction, 15/11/2026) : « une validation à faire ne doit JAMAIS empêcher le fileul de travailler ; le poste de la mère
/// n'est pas fait pour valider, c'est un poste qui porte la clinique ». Le moteur pur est `validation_deposee.dart` (domaine) ; ce service y branche le magasin, le journal et le
/// pont d'activité. UNE fabrique, pour les quinze familles de référentiels : pas un mécanisme par circuit.
///
///  * FILEUL rattaché : [deposer] écrit un DÉPÔT (collection `validationsDeposees`, famille A) au lieu de refuser « réglé sur la mère ». Le poste continue de travailler ; l'élément reste
///    « à valider » et l'écran dit « transmise à la mère, en attente » — jamais « validé » avant la confirmation. [reconcilier] donne une fois la SUITE du verdict : une notification
///    adressée à l'auteur (appliquée, sans effet, ou refusée avec son motif nommé).
///  * MÈRE : [demarrerMere] puis [traiter] — elle APPLIQUE chaque dépôt sous le rôle et le nom de son auteur, en refaisant tous les contrôles avec SES données, écrit la validation (les
///    mêmes traces que le geste direct), journalise (RG-12 : déposée par X, appliquée par la mère) et écrit le verdict sur la MÊME fiche, qui revient au fileul par le pont. Aucun humain
///    n'a à être assis devant la mère. Rejouable sans effet double (un élément déjà validé rend `sans_effet`).
class ServiceValidationsDeposees {
  ServiceValidationsDeposees._(this.magasin);
  static final Expando<ServiceValidationsDeposees> _instances = Expando('ServiceValidationsDeposees');
  static ServiceValidationsDeposees de(Magasin m) => _instances[m] ??= ServiceValidationsDeposees._(m);

  final Magasin magasin;

  /// L'étiquette de ce poste (rend unique l'identifiant d'un dépôt, reconnaît ses propres dépôts).
  String etiquette = 'P';

  /// Qui signe l'application (la mère) ; jamais anonyme (RG-12).
  String Function() auteurMere = () => 'Poste mère';

  /// La MATRICE EN FORCE (graine et décisions superposées), relue à chaque appel : la mère rejoue un dépôt de circuit d'achat sous le rôle de son auteur en interrogeant le geste réservé
  /// `achats_valider` (rôle archivé et module fermé compris). Non branchée (test nu) : les seules fiches `rbac` décident, l'origine du référentiel pour le reste.
  MatriceDroits Function()? matrice;

  /// Les gestes réservés en force sur CE poste, lus à chaque appel (jamais une liste de rôles).
  DroitsGestes get gestes {
    final mat = matrice?.call();
    return DroitsGestes(fiches: magasin.collection('rbac').actives, estArchive: mat?.estArchive, ecranActif: mat?.ecranActif);
  }

  DateTime Function()? horloge;
  DateTime get _maintenant => (horloge ?? magasin.horloge)();

  CollectionMagasin get depots => magasin.collection(valCollectionDepots);

  LectureValidation get _lire => (nom) => magasin.collection(nom).toutes;

  Map<String, String> get _libelles => {for (final r in rolesDe(magasin)) r.id: r.label};

  int _serie = 0;
  String _nouvelId() => 'VDP-$etiquette-${_maintenant.toUtc().millisecondsSinceEpoch.toRadixString(36)}-${(++_serie).toRadixString(36)}';

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // FILEUL : déposer, dire l'attente, donner la suite
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  /// DÉPOSE la validation d'un élément. Refus nommé (mêmes contrôles que le geste direct) ou le dépôt écrit ; un dépôt identique qui attend déjà la mère n'est pas doublé.
  VerdictDepot deposer(String famille, Object? id, {required String role, required String acteur, String? motif}) {
    final r = valDeposer(famille, '$id',
        role: role, acteur: acteur, poste: etiquette, maintenant: _maintenant, lire: _lire, libelles: _libelles, depots: depots.toutes, nouvelId: _nouvelId, motif: motif);
    if (!r.ok || r.dejaDepose) return r;
    _signer(r.fiche!);
    try {
      depots.ajouterSansJournal(r.fiche!, enTete: true);
    } on EcritureRefusee catch (e) {
      return VerdictDepot.refus(RefusValidation('ECRITURE_REFUSEE', e.motif, null));
    }
    final f = valFamille(famille)!;
    _signaler(famille);
    magasin.journaliser('Validation transmise à la mère', f.module, f.libelle, '$id', null, {'déposée par': acteur, 'rôle': role, 'dépôt': r.fiche!['id'], if (motif != null && motif.trim().isNotEmpty) 'motif': motif.trim()});
    return r;
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // FACTURE À UNE ENTREPRISE (17/11/2026, point 2) : émission, avoir et transmission demandés depuis un fileul
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  /// DÉPOSE une demande sur une facture à une entreprise (`emettre`, `avoir`, `transmettre`) : l'émission reste à la mère, qui tient la numérotation et l'appareil fiscal. Même collection, même cycle de
  /// verdict, même notification de l'auteur que les autres dépôts. Refus nommé (mêmes contrôles que le geste direct) ou le dépôt écrit ; une demande identique en attente n'est pas doublée.
  /// [facture] : la pièce visée par un avoir ou une transmission, telle que ce poste la voit.
  VerdictDepot deposerFactureTiers(String action, Map<String, Object?> charge, {required String role, required String acteur, Fiche? facture, DroitsGestes? gestes}) {
    final r = factureTiersDeposer(
        action: action,
        charge: charge,
        role: role,
        acteur: acteur,
        poste: etiquette,
        maintenant: _maintenant,
        gestes: gestes ?? this.gestes,
        depots: depots.toutes,
        nouvelId: _nouvelId,
        facture: facture);
    if (!r.ok || r.dejaDepose) return r;
    _signer(r.fiche!);
    try {
      depots.ajouterSansJournal(r.fiche!, enTete: true);
    } on EcritureRefusee catch (e) {
      return VerdictDepot.refus(RefusValidation('ECRITURE_REFUSEE', e.motif, null));
    }
    _signalerFacturesTiers();
    magasin.journaliser('Demande transmise à la mère', 'M9', r.fiche!['libelle'] as String, '${r.fiche!['cible']}', null,
        {'déposée par': acteur, 'rôle': role, 'dépôt': r.fiche!['id'], 'demande': action});
    return r;
  }

  /// Le dépôt d'une demande qui attend encore la mère, ou le dernier refusé (`null` : aucun) : l'écran dit « transmise à la mère, en attente » ou donne le motif nommé.
  Fiche? depotFactureTiersAttendu(String action, String cible) => depotFactureTiersOuvert(depots.toutes, action, cible);

  void _signalerFacturesTiers() {
    for (final c in facturesTiersCollectionsSync) {
      magasin.collection(c).signaler();
    }
  }

  final Set<String> _transmissionsEnVol = {};

  /// Applique UNE demande sur une facture à une entreprise (la mère) : sous le rôle et le nom de l'auteur, avec la matrice en force, contrôles refaits. Une transmission vers un appareil CONFIGURÉ est
  /// asynchrone : elle part en tâche de fond et le verdict s'écrit à son retour (jamais deux fois : `_transmissionsEnVol`). Rend vrai quand un verdict est écrit à l'instant.
  bool _appliquerFactureTiers(Fiche d) {
    final v = appliquerDepotFactureTiers(magasin, d, maintenant: _maintenant, gestes: gestes);
    if (v == null) {
      final id = '${d['id']}';
      if (_transmissionsEnVol.add(id)) {
        appliquerTransmissionDemandeeFactureTiers(magasin, d, maintenant: _maintenant, gestes: gestes).then((r) {
          _ecrireVerdictFactureTiers(d, r);
          _signalerFacturesTiers();
        }).whenComplete(() => _transmissionsEnVol.remove(id));
      }
      return false;
    }
    _ecrireVerdictFactureTiers(d, v);
    return true;
  }

  void _ecrireVerdictFactureTiers(Fiche d, VerdictDemandeFactureTiers v) {
    depots.mettreAJour(d['id'], {
      'etat': v.etat,
      'traiteLe': _maintenant.toUtc().toIso8601String(),
      'traitePar': auteurMere(),
      'signeLe': d['demandeInstant'] ?? d['demandeLe'],
      if (v.etat == valDepotAppliquee) 'appliqueLe': _maintenant.toUtc().toIso8601String(),
      if (v.code != null) 'resultatCode': v.code,
      if (v.motif != null) 'resultatMotif': v.motif,
      if (v.geste != null) 'resultatGeste': v.geste,
      if (v.reference != null) 'resultatReference': v.reference,
    }, journaliser: false);
  }

  /// CIRCUITS D'ACHAT (16/11/2026) : DÉPOSE l'arbitrage d'un besoin (`besoin_arbitrage`) ou la validation d'une commande (`commande_validation`). Même collection, même cycle de verdict,
  /// même notification de l'auteur que la validation d'un référentiel : un seul mécanisme. Refus nommé (mêmes contrôles que l'application) ou le dépôt écrit.
  /// [gestes] : les gestes réservés de l'écran qui dépose (fiches et matrice en force) ; à défaut, ceux du service ([gestes]).
  VerdictDepot deposerCircuit(String famille, Fiche bon, {String decision = 'valider', String motif = '', required String role, required String acteur, DroitsGestes? gestes}) {
    final r = circuitDeposer(
        famille: famille,
        bon: bon,
        decision: decision,
        motif: motif,
        role: role,
        acteur: acteur,
        poste: etiquette,
        maintenant: _maintenant,
        besoins: magasin.collection('besoins').toutes,
        commandes: magasin.collection('commandes').toutes,
        depots: depots.toutes,
        gestes: gestes ?? this.gestes,
        nouvelId: _nouvelId);
    if (!r.ok || r.dejaDepose) return r;
    _signer(r.fiche!);
    try {
      depots.ajouterSansJournal(r.fiche!, enTete: true);
    } on EcritureRefusee catch (e) {
      return VerdictDepot.refus(RefusValidation('ECRITURE_REFUSEE', e.motif, null));
    }
    magasin.collection(famille == circuitBesoinArbitrage ? 'besoins' : 'commandes').signaler();
    magasin.journaliser('Validation transmise à la mère', famille == circuitBesoinArbitrage ? 'M7' : 'M7', r.fiche!['libelle'] as String, '${bon['reference']}', null,
        {'déposée par': acteur, 'rôle': role, 'dépôt': r.fiche!['id'], 'décision': decision, if (motif.trim().isNotEmpty) 'motif': motif.trim()});
    return r;
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // PLAN DE TRAVAIL ANNUEL (lot PTA, 17/11/2026) : adopter, renvoyer, clôturer depuis n'importe quel poste
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  /// Le bilan d'une clôture appliquée sur CE poste (la mère, qui rejoue un dépôt) : calculé sur SES données à l'instant de l'application — seuil de retard en vigueur pour
  /// l'exercice, états, budgets et écritures du magasin. Remplaçable par un test.
  PtaSynthese Function(int annee, int version)? syntheseBilanPta;

  PtaSynthese _syntheseBilanPta(int annee, int version) {
    final f = syntheseBilanPta;
    if (f != null) return f(annee, version);
    final exercice = ptaExercice(magasin.collection('exercices').toutes, annee);
    final seuil = ptaSeuilDe(serviceParametres(magasin, auteur: () => 'lecture').valeur(ptaCleSeuilRetard, parametreDateIso(ptaDateReglage(exercice, _maintenant))));
    return ptaSynthese(ptaActionsDuPlan(magasin.collection(ptaCollectionActions).toutes, annee, version), magasin.collection(ptaCollectionEtats).toutes,
        auj: _maintenant, seuilJours: seuil, budgets: magasin.collection('budgets').toutes, ecritures: magasin.collection('ecritures').actives);
  }

  /// DÉPOSE une décision réservée sur le plan de travail annuel (adopter, renvoyer en brouillon, clôturer). Refus nommé (mêmes contrôles que l'application) ou le dépôt écrit ;
  /// un dépôt identique qui attend déjà la mère n'est pas doublé. Le plan reste dans son état jusqu'à la confirmation : jamais « adopté » sur un dépôt seul.
  VerdictDepot deposerPta(String decision, int annee, int version, {required String role, required String acteur, required String motif, DroitsGestes? gestes}) {
    final r = ptaDeposer(
        decision: decision,
        annee: annee,
        version: version,
        role: role,
        acteur: acteur,
        poste: etiquette,
        motif: motif,
        maintenant: _maintenant,
        gestes: gestes ?? this.gestes,
        plans: magasin.collection(ptaCollectionPlans).toutes,
        actions: magasin.collection(ptaCollectionActions).toutes,
        depots: depots.toutes,
        nouvelId: _nouvelId);
    if (!r.ok || r.dejaDepose) return r;
    _signer(r.fiche!);
    try {
      depots.ajouterSansJournal(r.fiche!, enTete: true);
    } on EcritureRefusee catch (e) {
      return VerdictDepot.refus(RefusValidation('ECRITURE_REFUSEE', e.motif, null));
    }
    magasin.collection(ptaCollectionPlans).signaler();
    magasin.journaliser('Décision du plan transmise à la mère', 'M13', 'Plan de travail annuel', ptaReferencePlan(annee, version), null,
        {'décision': decision, 'déposée par': acteur, 'rôle': role, 'dépôt': r.fiche!['id'], 'motif': motif.trim()});
    return r;
  }

  /// Le dépôt d'une décision du PTA de CE plan qui attend encore la mère (`null` : aucun) : l'écran dit « transmise à la mère, en attente ».
  Fiche? depotPtaEnAttente(int annee, int version) {
    final cible = ptaClePlan(annee, version);
    for (final d in depots.toutes) {
      if (d['statut'] != 'archive' && d['genre'] == valGenrePta && d['cible'] == cible && d['etat'] == valDepotDeposee) return d;
    }
    return null;
  }

  /// Le dernier dépôt REFUSÉ par la mère pour ce plan (son motif nommé revient à l'auteur) ; `null` si aucun, ou si un dépôt plus récent l'a suivi.
  Fiche? depotPtaRefuse(int annee, int version) {
    final cible = ptaClePlan(annee, version);
    Fiche? dernier;
    for (final d in depots.toutes) {
      if (d['statut'] == 'archive' || d['genre'] != valGenrePta || d['cible'] != cible) continue;
      if (dernier == null || '${d['demandeLe']}'.compareTo('${dernier['demandeLe']}') >= 0) dernier = d;
    }
    return dernier != null && dernier['etat'] == valDepotRefusee ? dernier : null;
  }

  /// Applique les écritures d'une décision du PTA (sur la mère, ou au poste mère sous le geste) : en-têtes et suivi repris des actions, sans journal par écriture (le geste est
  /// journalisé une fois par l'appelant).
  void ecrirePta(List<PtaEcriture> ecritures) {
    for (final e in ecritures) {
      magasin.collection(e.collection).mettreAJour(e.id, e.patch, journaliser: false);
    }
  }

  /// Applique UN dépôt du PTA sur la mère : sous le rôle et le nom de l'auteur, contrôles refaits avec SA matrice et SES fiches, à la date du geste ; journal (RG-12).
  bool _appliquerPta(Fiche d) {
    final a = ptaAppliquerDepot(d,
        gestes: gestes,
        plans: magasin.collection(ptaCollectionPlans).toutes,
        actions: magasin.collection(ptaCollectionActions).toutes,
        maintenant: _maintenant,
        synthese: _syntheseBilanPta);
    if (a == null) return false;
    var etat = a.etat, code = a.code, motif = a.motif, geste = a.geste;
    if (a.ecritures.isNotEmpty) {
      try {
        ecrirePta(a.ecritures);
        magasin.journaliser('Décision du plan de travail annuel (geste réservé)', 'M13', 'Plan de travail annuel', ptaReferencePlan(int.parse('${d['exercice']}'), int.parse('${d['version']}')), null,
            {'décision': d['decision'], 'motif': d['motif'], 'déposée par': d['demandePar'], 'rôle': d['demandeRole'], 'appliquée par': auteurMere(), 'dépôt': d['id']});
      } on EcritureRefusee catch (x) {
        etat = valDepotRefusee;
        code = 'ECRITURE_REFUSEE';
        motif = x.motif;
        geste = 'Refaire la décision depuis l’écran du plan.';
      }
    }
    depots.mettreAJour(d['id'], {
      'etat': etat,
      'traiteLe': _maintenant.toUtc().toIso8601String(),
      'traitePar': auteurMere(),
      'signeLe': d['demandeInstant'] ?? d['demandeLe'],
      if (etat == valDepotAppliquee) 'appliqueLe': _maintenant.toUtc().toIso8601String(),
      if (code != null) 'resultatCode': code,
      if (motif != null) 'resultatMotif': motif,
      if (geste != null) 'resultatGeste': geste,
    }, journaliser: false);
    return true;
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // RÉGLAGE DE CLINIQUE SOUS GESTE RÉSERVÉ (16/11/2026, §7) : depuis n'importe quel poste
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  List<Parametre> get _versionsParametres => [
        for (final f in magasin.collection(parCollectionParametres).toutes)
          if (f['statut'] != 'archive') Parametre.fromJson(f)
      ];

  List<Map<String, Object?>> get _usagesParametres => magasin.collection(parCollectionUsages).toutes;

  /// Pose un réglage qui relève d'un GESTE RÉSERVÉ (`reglagesSousGeste`, par exemple « encaisser le reste d'une facture qui a une ligne sans prix »). Sur la MÈRE ([estMere]), le
  /// geste écrit la version datée (contrôles du domaine : geste en force, valeur, date, usage) ; sur un poste rattaché, il DÉPOSE une demande que la mère applique sous le rôle de
  /// l'auteur — la version revient ensuite par la synchronisation (famille R). Refus nommé dans les deux cas, rien d'écrit.
  ({RefusValidation? refus, Parametre? version, Fiche? depot, bool dejaDepose}) reglerSousGeste(String cle, Object? valeur, String dateEffet,
      {required String role, required String acteur, required bool estMere, String? motif, DroitsGestes? gestes}) {
    final g = gestes ?? this.gestes;
    if (!estMere) {
      final r = reglageDeposer(
          cle: cle,
          valeur: valeur,
          dateEffet: dateEffet,
          role: role,
          acteur: acteur,
          poste: etiquette,
          maintenant: _maintenant,
          gestes: g,
          versions: _versionsParametres,
          usages: _usagesParametres,
          depots: depots.toutes,
          nouvelId: _nouvelId,
          motif: motif);
      if (!r.ok) return (refus: r.refus, version: null, depot: null, dejaDepose: false);
      if (r.dejaDepose) return (refus: null, version: null, depot: r.fiche, dejaDepose: true);
      _signer(r.fiche!);
      try {
        depots.ajouterSansJournal(r.fiche!, enTete: true);
      } on EcritureRefusee catch (e) {
        return (refus: RefusValidation('ECRITURE_REFUSEE', e.motif, null), version: null, depot: null, dejaDepose: false);
      }
      magasin.journaliser('Réglage transmis à la mère', 'CFG', 'Paramètre', cle, null,
          {'valeur': valeur, 'à partir du': dateEffet, 'déposé par': acteur, 'rôle': role, 'dépôt': r.fiche!['id'], if (motif != null && motif.trim().isNotEmpty) 'motif': motif.trim()});
      return (refus: null, version: null, depot: r.fiche, dejaDepose: false);
    }
    final c = reglageControler(
        cle: cle, valeur: valeur, dateEffet: dateEffet, role: role, acteur: acteur, gestes: g, versions: _versionsParametres, usages: _usagesParametres, maintenant: _maintenant, motif: motif);
    if (c.refus != null) return (refus: c.refus, version: null, depot: null, dejaDepose: false);
    if (c.sansEffet) {
      return (refus: const RefusValidation('DEJA_REGLE', 'Le réglage a déjà cette valeur à cette date : aucune version n’est écrite.', 'Aucun'), version: null, depot: null, dejaDepose: false);
    }
    _ecrireVersion(c.version!);
    magasin.journaliser('Réglage d’un paramètre (geste réservé)', 'CFG', 'Paramètre', cle, null,
        {'valeur': valeur, 'à partir du': dateEffet, 'version': c.version!.version, 'par': acteur, 'rôle': role, if (motif != null && motif.trim().isNotEmpty) 'motif': motif.trim()});
    return (refus: null, version: c.version, depot: null, dejaDepose: false);
  }

  void _ecrireVersion(Parametre v) => magasin.collection(parCollectionParametres).inserer({'id': v.id, 'statut': 'actif', ...v.toJson()});

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // SÉRIES DE NUMÉROTATION (lot 2, 16/11/2026) : une version datée sous le geste `numerotation_modifier` ; la mère écrit, un poste rattaché dépose
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  List<Map<String, Object?>> get _versionsSeries => magasin.collection(colSeriesNumerotation).toutes;

  /// Modifie une série de numérotation. Sur la MÈRE ([estMere]), la version datée est écrite (contrôles du domaine : geste en force, date à venir, motif, format) ;
  /// sur un poste rattaché, une demande est DÉPOSÉE et la mère l'applique sous le rôle de l'auteur — la version revient par la synchronisation (famille R).
  ({RefusValidation? refus, Fiche? version, Fiche? depot, bool dejaDepose}) modifierSerie(String code, Map<String, Object?> valeurs, String dateEffet,
      {required String role, required String acteur, required bool estMere, String? motif, DroitsGestes? gestes}) {
    final g = gestes ?? this.gestes;
    if (!estMere) {
      final r = serieDeposer(
          code: code,
          valeurs: valeurs,
          dateEffet: dateEffet,
          role: role,
          acteur: acteur,
          poste: etiquette,
          maintenant: _maintenant,
          gestes: g,
          fiches: _versionsSeries,
          depots: depots.toutes,
          nouvelId: _nouvelId,
          motif: motif);
      if (!r.ok) return (refus: r.refus, version: null, depot: null, dejaDepose: false);
      if (r.dejaDepose) return (refus: null, version: null, depot: r.fiche, dejaDepose: true);
      _signer(r.fiche!);
      try {
        depots.ajouterSansJournal(r.fiche!, enTete: true);
      } on EcritureRefusee catch (e) {
        return (refus: RefusValidation('ECRITURE_REFUSEE', e.motif, null), version: null, depot: null, dejaDepose: false);
      }
      magasin.journaliser('Série de numérotation transmise à la mère', 'CFG', 'Série de numérotation', code, null,
          {'valeur': r.fiche!['valeur'], 'à partir du': dateEffet, 'déposé par': acteur, 'rôle': role, 'dépôt': r.fiche!['id'], 'motif': (motif ?? '').trim()});
      return (refus: null, version: null, depot: r.fiche, dejaDepose: false);
    }
    final c = serieControler(code: code, valeurs: valeurs, dateEffet: dateEffet, role: role, acteur: acteur, gestes: g, fiches: _versionsSeries, maintenant: _maintenant, motif: motif);
    if (c.refus != null) return (refus: c.refus, version: null, depot: null, dejaDepose: false);
    if (c.sansEffet) {
      return (refus: const RefusValidation('DEJA_EN_VIGUEUR', 'La série a déjà ce format à cette date : aucune version n’est écrite.', 'Aucun'), version: null, depot: null, dejaDepose: false);
    }
    final avant = serieALaDate(code, _versionsSeries, dateEffet).toJson();
    final v = magasin.collection(colSeriesNumerotation).inserer(c.version!).fiche;
    magasin.journaliser('Modification d’une série de numérotation (geste réservé)', 'CFG', 'Série de numérotation', code, avant, {...c.version!, 'par': acteur, 'rôle': role});
    return (refus: null, version: v, depot: null, dejaDepose: false);
  }

  /// Le dernier dépôt de CE poste pour la série [code] qui attend la mère (`null` : aucun).
  Fiche? depotSerieEnAttente(String code) {
    for (final d in depots.toutes) {
      if (d['statut'] != 'archive' && d['genre'] == valGenreNumerotation && d['cible'] == code && d['etat'] == valDepotDeposee) return d;
    }
    return null;
  }

  /// Applique UN dépôt de série sur la mère (sous le rôle et le nom de l'auteur, contrôles refaits avec la matrice et les versions de la mère).
  bool _appliquerSerie(Fiche d) {
    final a = serieAppliquerDepot(d, gestes: gestes, fiches: _versionsSeries, maintenant: _maintenant);
    if (a == null) return false;
    var etat = a.etat, code = a.code, motif = a.motif, geste = a.geste;
    final v = a.version;
    if (v != null) {
      try {
        magasin.collection(colSeriesNumerotation).ajouterSansJournal(v);
        magasin.journaliser('Modification d’une série de numérotation (geste réservé)', 'CFG', 'Série de numérotation', '${d['cible']}', null,
            {...v, 'déposé par': d['demandePar'], 'rôle': d['demandeRole'], 'appliqué par': auteurMere(), 'dépôt': d['id']});
      } on EcritureRefusee catch (x) {
        etat = valDepotRefusee;
        code = 'ECRITURE_REFUSEE';
        motif = x.motif;
        geste = 'Refaire la modification depuis « Numérotation des pièces ».';
      }
    }
    depots.mettreAJour(d['id'], {
      'etat': etat,
      'traiteLe': _maintenant.toUtc().toIso8601String(),
      'traitePar': auteurMere(),
      'signeLe': d['demandeInstant'] ?? d['demandeLe'],
      if (etat == valDepotAppliquee) 'appliqueLe': _maintenant.toUtc().toIso8601String(),
      if (code != null) 'resultatCode': code,
      if (motif != null) 'resultatMotif': motif,
      if (geste != null) 'resultatGeste': geste,
    }, journaliser: false);
    return true;
  }

  /// Le dernier dépôt de réglage de CE poste pour [cle] qui attend la mère (`null` : aucun) : l'écran dit « transmis à la mère, en attente ».
  Fiche? depotReglageEnAttente(String cle) {
    for (final d in depots.toutes) {
      if (d['statut'] != 'archive' && d['genre'] == valGenreReglage && d['cible'] == cle && d['etat'] == valDepotDeposee) return d;
    }
    return null;
  }

  /// Applique UN dépôt de réglage sur la mère (sous le rôle et le nom de l'auteur, contrôles refaits avec la matrice et les versions de la mère) ; la version écrite voyage aux fileuls.
  bool _appliquerReglage(Fiche d) {
    final a = reglageAppliquer(d, gestes: gestes, versions: _versionsParametres, usages: _usagesParametres, maintenant: _maintenant);
    if (a == null) return false;
    var etat = a.etat, code = a.code, motif = a.motif, geste = a.geste;
    final v = a.version;
    if (v != null) {
      try {
        _ecrireVersion(v);
        magasin.journaliser('Réglage d’un paramètre (geste réservé)', 'CFG', 'Paramètre', '${d['cible']}', null,
            {'valeur': v.valeur, 'à partir du': v.dateEffet, 'version': v.version, 'déposé par': d['demandePar'], 'rôle': d['demandeRole'], 'appliqué par': auteurMere(), 'dépôt': d['id']});
      } on EcritureRefusee catch (x) {
        etat = valDepotRefusee;
        code = 'ECRITURE_REFUSEE';
        motif = x.motif;
        geste = 'Refaire le réglage depuis les Paramètres.';
      }
    }
    depots.mettreAJour(d['id'], {
      'etat': etat,
      'traiteLe': _maintenant.toUtc().toIso8601String(),
      'traitePar': auteurMere(),
      'signeLe': d['demandeInstant'] ?? d['demandeLe'],
      if (etat == valDepotAppliquee) 'appliqueLe': _maintenant.toUtc().toIso8601String(),
      if (code != null) 'resultatCode': code,
      if (motif != null) 'resultatMotif': motif,
      if (geste != null) 'resultatGeste': geste,
    }, journaliser: false);
    return true;
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // LE PLANNING À TRAVERS LES POSTES (Direction, 17/11/2026, décision 12) : poser, remplacer, retirer, trancher une pièce, trancher une proposition
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  /// Le rappel que `PlanningRhPoste.deposer` appelle sur un poste RATTACHÉ : il écrit le dépôt (signé du compte, journalisé RG-12) ou rend le refus nommé. Les contrôles du geste ont déjà été
  /// faits à blanc par l'appelant, sur ses fiches ; la mère les REFAIT à l'application, sur les siennes.
  Map<String, Object?> Function(Map<String, Object?> demande) deposeurPlanning({required String role, required String acteur}) => (demande) {
        final r = planningRhDeposer(
            action: '${demande['action']}',
            collection: '${demande['collection']}',
            cible: '${demande['cible']}',
            libelle: '${demande['libelle'] ?? demande['cible']}',
            role: role,
            acteur: acteur,
            poste: etiquette,
            maintenant: _maintenant,
            depots: depots.toutes,
            nouvelId: _nouvelId,
            decision: demande['decision'] as String?,
            motif: demande['motif'] as String?,
            valeurs: (demande['valeurs'] as Map?)?.cast<String, Object?>());
        if (!r.ok) return {'ok': false, 'code': r.refus!.code, 'motif': r.refus!.motif, 'geste': r.refus!.geste};
        if (r.dejaDepose) return {'ok': true, 'depot': r.fiche, 'dejaDepose': true};
        _signer(r.fiche!);
        try {
          depots.ajouterSansJournal(r.fiche!, enTete: true);
        } on EcritureRefusee catch (e) {
          return {'ok': false, 'code': 'ECRITURE_REFUSEE', 'motif': e.motif, 'geste': 'Refaire le geste depuis l’écran du planning.'};
        }
        for (final c in planningCollectionsSync) {
          magasin.collection(c).signaler();
        }
        magasin.journaliser('Décision du planning transmise à la mère', 'M10', '${demande['collection']}', '${demande['cible']}', null,
            {'action': demande['action'], if (demande['decision'] != null) 'décision': demande['decision'], 'déposée par': acteur, 'rôle': role, 'dépôt': r.fiche!['id']});
        return {'ok': true, 'depot': r.fiche, 'dejaDepose': false};
      };

  /// Le dépôt du planning qui attend encore la mère pour cette pièce (`null` : aucun) : l'écran dit « transmise à la mère, en attente ».
  Fiche? depotPlanningEnAttente(String collection, Object? cible) {
    for (final d in depots.toutes) {
      if (d['statut'] != 'archive' && d['genre'] == valGenrePlanningRh && d['collection'] == collection && d['cible'] == cible && d['etat'] == valDepotDeposee) return d;
    }
    return null;
  }

  /// Applique UN dépôt du planning sur la mère : sous le rôle et le nom de l'auteur, à la date du geste, avec SA matrice et SES fiches (le planning de tous les postes) ; les contrôles sont ceux du
  /// geste direct (`PlanningRhPoste`), jamais recopiés. Une pièce qui n'est pas encore arrivée à la mère (le dépôt peut devancer la fiche) attend [delaiPieceAbsente] avant d'être refusée.
  /// Rend vrai quand le dépôt a reçu un verdict.
  bool _appliquerPlanning(Fiche d) {
    final quand = DateTime.tryParse('${d['demandeLe'] ?? ''}') ?? _maintenant;
    final p = PlanningRhPoste(magasin, auteur: () => '${d['demandePar'] ?? ''}', role: '${d['demandeRole'] ?? ''}', horloge: () => quand, appliqueDepot: true, gestesEnForce: () => gestes);
    final collection = '${d['collection']}', action = '${d['action']}';
    final fiche = p.parCle(collection, d['cible']);
    var etat = valDepotAppliquee;
    String? code, motif, geste;
    if (fiche == null) {
      if (_maintenant.difference(quand) < delaiPieceAbsente) return false;
      etat = valDepotRefusee;
      code = 'PIECE_INTROUVABLE';
      motif = 'La pièce visée n’est jamais arrivée à la mère : elle n’a pas été versée par son poste.';
      geste = 'Refaire le geste depuis l’écran du planning, une fois le poste rattaché';
    } else {
      Map<String, Object?> r;
      final plan = magasin.collection('planning');
      switch (action) {
        case planningActionTrancher:
          r = p.trancher(collection, fiche['id'], '${d['decision']}', motif: d['motif'] as String?);
        case planningActionProposition:
          r = p.trancherProposition(fiche['id'], '${d['decision']}', motif: d['motif'] as String?);
        case planningActionPoser:
          if (fiche['statut'] == 'archive') {
            r = {'ok': false, 'code': 'DEJA_FAIT', 'motif': 'La vacation a été retirée par son auteur avant l’application : rien n’est validé.', 'geste': 'Aucun'};
          } else if (planningVacationValidee(fiche)) {
            r = {'ok': false, 'code': 'DEJA_FAIT', 'motif': 'La vacation est déjà validée : rien n’est appliqué une seconde fois.', 'geste': 'Aucun'};
          } else {
            r = p.poserVacation(employeId: fiche['employeId'], date: fiche['date'] as String?, type: fiche['type'] as String?, observation: fiche['observation'] as String?, existantId: fiche['id']);
            // Une pose refusée (double affectation avec la vacation d'un autre poste, repos, droit) ne laisse pas une vacation « en attente » orpheline : elle est archivée (RG-14), le motif revient à l'auteur.
            if (r['ok'] != true) plan.archiver(fiche['id']);
          }
        case planningActionRemplacer:
          final v = (d['valeurs'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
          r = p.poserVacation(employeId: v['employeId'], date: v['date'] as String?, type: v['type'] as String?, observation: v['observation'] as String?, existantId: fiche['id']);
        case planningActionRetirer:
          r = fiche['statut'] == 'archive'
              ? {'ok': false, 'code': 'DEJA_FAIT', 'motif': 'La vacation est déjà retirée : rien n’est appliqué une seconde fois.', 'geste': 'Aucun'}
              : p.retirerVacation(fiche['id']);
        default:
          r = {'ok': false, 'code': 'ACTION_INCONNUE', 'motif': 'Action du planning inconnue de la mère : $action.', 'geste': 'Refaire le geste depuis l’écran du planning'};
      }
      if (r['ok'] != true) {
        final c = '${r['code'] ?? ''}';
        etat = c == 'DEJA_TRANCHEE' || c == 'DEJA_FAIT' ? valDepotSansEffet : valDepotRefusee;
        code = c.isEmpty ? 'REFUSE' : c;
        motif = '${r['motif'] ?? ''}';
        geste = '${r['geste'] ?? ''}';
      } else {
        magasin.journaliser('Décision du planning appliquée par la mère', 'M10', collection, '${d['cible']}',
            null, {'action': action, if (d['decision'] != null) 'décision': d['decision'], 'déposée par': d['demandePar'], 'rôle': d['demandeRole'], 'appliquée par': auteurMere(), 'dépôt': d['id']});
      }
    }
    depots.mettreAJour(d['id'], {
      'etat': etat,
      'traiteLe': _maintenant.toUtc().toIso8601String(),
      'traitePar': auteurMere(),
      'signeLe': d['demandeInstant'] ?? d['demandeLe'],
      if (etat == valDepotAppliquee) 'appliqueLe': _maintenant.toUtc().toIso8601String(),
      if (code != null) 'resultatCode': code,
      if (motif != null) 'resultatMotif': motif,
      if (geste != null) 'resultatGeste': geste,
    }, journaliser: false);
    return true;
  }

  /// Une pose de vacation refusée (compte signataire, droit, contrôle) ne laisse pas une vacation « en attente » orpheline : elle est archivée (RG-14), le motif revient à l'auteur sur le dépôt.
  void _archiverPoseOrpheline(Fiche d) {
    if (d['action'] != planningActionPoser) return;
    for (final f in magasin.collection('planning').toutes) {
      if ((f['id'] == d['cible'] || f['idSync'] == d['cible']) && f['statut'] != 'archive' && !planningVacationValidee(f)) {
        magasin.collection('planning').archiver(f['id']);
        return;
      }
    }
  }

  /// Le temps qu'un dépôt attend la pièce qu'il désigne avant d'être refusé : le dépôt peut devancer la fiche dans le journal.
  Duration delaiPieceAbsente = const Duration(minutes: 10);

  /// AI (16/11/2026) : le dépôt porte le COMPTE qui le signe (la mère le vérifie avant de rejouer) et l'instant exact du geste (l'âge de la décision en attente se mesure dessus).
  void _signer(Fiche f) {
    final compte = magasin.compteSignataire;
    if (compte != null) f[champCompteDecision] = compte;
    f['demandeInstant'] ??= _maintenant.toUtc().toIso8601String();
  }

  /// Le dépôt de circuit d'un bon qui attend encore la mère (`null` : aucun) : l'écran dit « transmis à la mère, en attente » et n'offre pas de second geste.
  Fiche? depotCircuitEnAttente(String famille, Fiche bon) {
    final cible = cleCircuit(bon);
    for (final d in depots.toutes) {
      if (d['statut'] != 'archive' && d['genre'] == valGenreCircuitAchat && d['famille'] == famille && d['cible'] == cible && d['etat'] == valDepotDeposee) return d;
    }
    return null;
  }

  /// Le dernier dépôt de circuit REFUSÉ par la mère pour ce bon (le motif nommé revient à l'auteur) ; `null` si aucun.
  Fiche? depotCircuitRefuse(String famille, Fiche bon) {
    final cible = cleCircuit(bon);
    Fiche? dernier;
    for (final d in depots.toutes) {
      if (d['statut'] == 'archive' || d['genre'] != valGenreCircuitAchat || d['famille'] != famille || d['cible'] != cible) continue;
      if (dernier == null || '${d['demandeLe']}'.compareTo('${dernier['demandeLe']}') >= 0) dernier = d;
    }
    return dernier != null && dernier['etat'] == valDepotRefusee ? dernier : null;
  }

  /// Les écrans lisent l'ÉLÉMENT (l'acte, la variable, le barème), pas le registre des dépôts : un dépôt ou un verdict doit les repeindre, faute de quoi la commande « Valider » resterait
  /// offerte après le dépôt et le badge « en attente de la mère » n'apparaîtrait qu'au prochain geste.
  void _signaler(String famille) {
    final f = valFamille(famille);
    if (f == null) return;
    for (final c in {...f.collections, valCollectionValidations}) {
      magasin.collection(c).signaler();
    }
  }

  /// L'état d'attente d'un élément (le dernier dépôt non résolu par une validation visible).
  EtatDepot? etatDepot(String famille, Object? id) => valEtatDepot(famille, '$id', depots.toutes);

  /// Donne UNE fois la suite du verdict de chaque dépôt de CE poste : une notification adressée à l'auteur. Idempotent (`notifieLe`). Rend le nombre de dépôts suivis.
  int reconcilier() {
    var n = 0;
    for (final d in [
      for (final d in depots.toutes)
        if (d['statut'] != 'archive' && '${d['demandePoste']}' == etiquette && d['etat'] != valDepotDeposee && d['notifieLe'] == null) d
    ]) {
      final etat = '${d['etat']}';
      final quoi = '« ${d['libelle'] ?? d['famille']} » (${d['cible']})';
      final ref = d['resultatReference'] == null ? '' : ' (${d['resultatReference']})';
      final (type, libelle, detail, priorite) = d['genre'] == valGenreFactureTiers
          ? switch (etat) {
              valDepotAppliquee => ('validation_confirmee', 'Demande appliquée par la mère', '$quoi : la mère a appliqué votre demande$ref.${d['resultatMotif'] == null ? '' : ' ${d['resultatMotif']}'}', 'normale'),
              valDepotSansEffet => ('validation_confirmee', 'Demande déjà satisfaite', '$quoi : ${d['resultatMotif'] ?? 'déjà fait'}', 'normale'),
              _ => ('validation_refusee', 'Demande refusée par la mère', '$quoi : ${d['resultatCode']} : ${d['resultatMotif']} ${d['resultatGeste'] ?? ''}'.trim(), 'haute'),
            }
          : switch (etat) {
        valDepotAppliquee => ('validation_confirmee', 'Validation confirmée par la mère', '$quoi : votre validation est appliquée.', 'normale'),
        valDepotSansEffet => ('validation_confirmee', 'Validation déjà faite', '$quoi : ${d['resultatMotif'] ?? 'déjà validé'}', 'normale'),
        _ => ('validation_refusee', 'Validation refusée par la mère', '$quoi : ${d['resultatCode']} : ${d['resultatMotif']} ${d['resultatGeste'] ?? ''}'.trim(), 'haute'),
      };
      magasin.collection('notifications').inserer({
        'type': type,
        'poste': 'tous',
        'destinataire': d['demandePar'],
        'libelle': libelle,
        'detail': detail,
        'priorite': priorite,
        'reference': d['id'],
        'lue': false,
        'creeLe': _maintenant.toUtc().toIso8601String(),
        'statut': 'actif',
      }, prefixe: 'NOT');
      depots.mettreAJour(d['id'], {'notifieLe': _maintenant.toUtc().toIso8601String()}, journaliser: false);
      _signaler('${d['famille']}');
      if (d['genre'] == valGenreCircuitAchat) magasin.collection(d['famille'] == circuitBesoinArbitrage ? 'besoins' : 'commandes').signaler();
      if (d['genre'] == valGenreFactureTiers) _signalerFacturesTiers();
      if (d['genre'] == valGenrePta) magasin.collection(ptaCollectionPlans).signaler();
      if (d['genre'] == valGenrePlanningRh) {
        for (final c in planningCollectionsSync) {
          magasin.collection(c).signaler();
        }
      }
      n++;
    }
    return n;
  }

  Timer? _minuterieFileul;
  VoidCallback? _ecouteFileul;

  /// Démarre le suivi des verdicts (écoute de la collection et minuterie de sûreté).
  void demarrerFileul({Duration intervalle = const Duration(seconds: 4)}) {
    if (_ecouteFileul != null) return;
    _ecouteFileul = () => scheduleMicrotask(reconcilier);
    depots.addListener(_ecouteFileul!);
    _minuterieFileul = Timer.periodic(intervalle, (_) => reconcilier());
    reconcilier();
  }

  // ---------------------------------------------------------------------------------------------------------------------------------------------
  // MÈRE : appliquer
  // ---------------------------------------------------------------------------------------------------------------------------------------------

  bool _traitement = false;
  VoidCallback? _ecoute;
  Timer? _minuterie;

  /// Dernière erreur d'un tour (un verdict qui n'a pas pu s'écrire est repris au tour suivant).
  Object? derniereErreur;

  /// Démarre la mère : une écoute de la collection (un dépôt qui arrive par le pont est traité aussitôt) et une minuterie de sûreté.
  void demarrerMere({Duration intervalle = const Duration(seconds: 5)}) {
    if (_ecoute != null) return;
    _ecoute = () => scheduleMicrotask(traiter);
    depots.addListener(_ecoute!);
    _minuterie = Timer.periodic(intervalle, (_) => traiter());
    traiter();
  }

  void arreter() {
    if (_ecoute != null) depots.removeListener(_ecoute!);
    _ecoute = null;
    _minuterie?.cancel();
    _minuterie = null;
    if (_ecouteFileul != null) depots.removeListener(_ecouteFileul!);
    _ecouteFileul = null;
    _minuterieFileul?.cancel();
    _minuterieFileul = null;
  }

  /// AI (16/11/2026) : la mère VÉRIFIE le compte inscrit sur la décision (existe dans `utilisateurs`, porte ce rôle, n'est pas archivé) AVANT de la rejouer. Désactivable pour un
  /// banc qui ne porte aucun compte ; en production toujours actif.
  bool exigerCompteInscrit = true;

  /// Les comptes de la clinique que la mère détient (relus à chaque dépôt).
  Iterable<Fiche> Function()? comptes;

  RefusCompte? _refusCompte(Fiche d) => !exigerCompteInscrit
      ? null
      : verifierCompteSignataire(
          compte: d[champCompteDecision], role: '${d['demandeRole'] ?? ''}', par: '${d['demandePar'] ?? ''}', comptes: (comptes ?? () => magasin.collection('utilisateurs').toutes)());

  /// Le verdict d'un dépôt refusé AVANT tout rejeu (compte signataire) : rien n'est appliqué, le code revient au fileul.
  void _refuserDepot(Fiche d, RefusCompte r) {
    depots.mettreAJour(d['id'], {
      'etat': valDepotRefusee,
      'traiteLe': _maintenant.toUtc().toIso8601String(),
      'traitePar': auteurMere(),
      'resultatCode': r.code,
      'resultatMotif': r.motif,
      'resultatGeste': r.geste,
      'signeLe': d['demandeInstant'] ?? d['demandeLe'],
    }, journaliser: false);
    magasin.journaliser('Validation refusée par la mère (compte signataire)', 'CFG', '${d['libelle'] ?? d['famille'] ?? ''}', '${d['cible'] ?? d['id']}', null,
        {'déposée par': d['demandePar'], 'rôle': d['demandeRole'], 'compte': d[champCompteDecision] ?? '—', 'code': r.code, 'dépôt': d['id']});
  }

  /// Applique UN dépôt de circuit sur la mère : sous le rôle et le nom de l'auteur, contrôles refaits avec les données de la mère (`circuitAppliquer`), date du geste, journal (RG-12).
  /// Le bon écrit voyage aux fileuls par le pont d'activité ; les notifications du comptable et du gestionnaire de stock naissent de l'état du bon sur chaque poste (`ServiceCircuitAchats`).
  bool _appliquerCircuit(Fiche d) {
    final a = circuitAppliquer(d, besoins: magasin.collection('besoins').toutes, commandes: magasin.collection('commandes').toutes, maintenant: _maintenant,
        gestes: gestes, libelleValidateur: ReglagesClinique.libelleValidateurAchats(magasin, _maintenant));
    if (a == null) return false;
    var etat = a.etat, code = a.code, motif = a.motif, geste = a.geste;
    final e = a.ecriture;
    if (e != null) {
      try {
        magasin.collection(e.collection).mettreAJour(e.ficheId, e.patch, journaliser: false);
        magasin.journaliser(e.action, 'M7', e.entite, e.reference, null, {...e.apres, 'déposée par': d['demandePar'], 'appliquée par': auteurMere(), 'dépôt': d['id']});
      } on EcritureRefusee catch (x) {
        etat = valDepotRefusee;
        code = 'ECRITURE_REFUSEE';
        motif = x.motif;
        geste = 'Refaire le geste depuis l’écran du circuit.';
      }
    }
    depots.mettreAJour(d['id'], {
      'etat': etat,
      'traiteLe': _maintenant.toUtc().toIso8601String(),
      'traitePar': auteurMere(),
      // AI : la date de SIGNATURE (le geste de l'auteur) et la date d'APPLICATION par la mère, côte à côte.
      'signeLe': d['demandeInstant'] ?? d['demandeLe'],
      if (etat == valDepotAppliquee) 'appliqueLe': _maintenant.toUtc().toIso8601String(),
      if (code != null) 'resultatCode': code,
      if (motif != null) 'resultatMotif': motif,
      if (geste != null) 'resultatGeste': geste,
    }, journaliser: false);
    return true;
  }

  /// Traite, dans l'ordre des gestes, chaque dépôt `deposee`. Rend le nombre de dépôts traités. Ré-entrance refusée : le verdict que l'on écrit rappelle l'écoute.
  int traiter() {
    if (_traitement) return 0;
    _traitement = true;
    var n = 0;
    try {
      final attente = [for (final d in depots.toutes) if (d['etat'] == valDepotDeposee && d['statut'] != 'archive') d]
        ..sort((a, b) => '${a['demandeLe']}${a['id']}'.compareTo('${b['demandeLe']}${b['id']}'));
      for (final d in attente) {
        final refusCompte = _refusCompte(d);
        if (refusCompte != null) {
          _refuserDepot(d, refusCompte);
          if (d['genre'] == valGenrePlanningRh) _archiverPoseOrpheline(d);
          n++;
          continue;
        }
        if (d['genre'] == valGenreCircuitAchat) {
          if (_appliquerCircuit(d)) n++;
          continue;
        }
        if (d['genre'] == valGenreReglage) {
          if (_appliquerReglage(d)) n++;
          continue;
        }
        if (d['genre'] == valGenrePta) {
          if (_appliquerPta(d)) n++;
          continue;
        }
        if (d['genre'] == valGenreNumerotation) {
          if (_appliquerSerie(d)) n++;
          continue;
        }
        if (d['genre'] == valGenrePlanningRh) {
          if (_appliquerPlanning(d)) n++;
          continue;
        }
        if (d['genre'] == valGenreFactureTiers) {
          if (_appliquerFactureTiers(d)) n++;
          continue;
        }
        final a = valAppliquerDepot(d, lire: _lire, libelles: _libelles, maintenant: _maintenant);
        if (a == null) continue;
        var etat = a.etat, code = a.code, motif = a.motif, geste = a.geste;
        final v = a.validation;
        if (v != null) {
          try {
            final col = magasin.collection(v.collection!);
            if (v.creation != null) {
              col.ajouterSansJournal(v.creation!);
            } else {
              col.mettreAJour(v.collection == valCollectionValidations ? 'VRF-${v.id}' : '${v.id}', v.patch, journaliser: false);
            }
            final j = v.journal!;
            magasin.journaliser(j.action, j.module, j.entite, j.reference, j.avant, {...j.apres, 'déposée par': d['demandePar'], 'appliquée par': auteurMere(), 'dépôt': d['id']});
          } on EcritureRefusee catch (e) {
            etat = valDepotRefusee;
            code = 'ECRITURE_REFUSEE';
            motif = e.motif;
            geste = 'Refaire la validation depuis l’écran du référentiel.';
          }
        }
        depots.mettreAJour(d['id'], {
          'etat': etat,
          'traiteLe': _maintenant.toUtc().toIso8601String(),
          'traitePar': auteurMere(),
          'signeLe': d['demandeInstant'] ?? d['demandeLe'],
          if (etat == valDepotAppliquee) 'appliqueLe': _maintenant.toUtc().toIso8601String(),
          if (code != null) 'resultatCode': code,
          if (motif != null) 'resultatMotif': motif,
          if (geste != null) 'resultatGeste': geste,
        }, journaliser: false);
        n++;
      }
      derniereErreur = null;
    } catch (e) {
      derniereErreur = e;
    } finally {
      _traitement = false;
    }
    return n;
  }
}
