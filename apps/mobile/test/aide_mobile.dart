// Aides communes des tests de l'application mobile : une source en mémoire (le lot) et un faux moteur qui laisse tourner le VRAI service soignant.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_mobile/moteur/moteur_mobile.dart';

final horloge = DateTime(2026, 10, 31, 10, 0);

/// La GRAINE des droits, lue sur le disque (les tests de widgets ne passent pas par le paquet d'assets) : les mêmes fichiers que l'application embarque.
GraineDroits? _graine;
GraineDroits graineDeTest() => _graine ??= GraineDroits.depuisJson(
      manifeste: File('assets/droits/manifeste.json').readAsStringSync(),
      rbac: File('assets/droits/rbac.json').readAsStringSync(),
      rbacReference: File('assets/droits/rbac.reference.json').readAsStringSync(),
      rbacLivre: File('assets/droits/rbac.livre.json').readAsStringSync(),
      modulesReference: File('assets/droits/modulesActifs.reference.json').readAsStringSync(),
      modulesLivres: File('assets/droits/modulesActifs.livre.json').readAsStringSync(),
    );

class SourceMemoire implements SourceMobile {
  SourceMemoire([Map<String, List<LigneLot>>? depart]) : donnees = depart ?? {};
  final Map<String, List<LigneLot>> donnees;
  final List<(String, Map<String, Object?>)> ecritures = [];
  int? fin;
  int _n = 0;

  @override
  Future<List<LigneLot>> liste(String collection) async => [...?donnees[collection]];

  @override
  Future<String> creer(String collection, Map<String, Object?> champs) async {
    final id = 'f${++_n}';
    donnees.putIfAbsent(collection, () => []).add(LigneLot(id, champs));
    ecritures.add((collection, champs));
    return id;
  }

  @override
  Future<int?> lotExpire() async => fin;

  List<Map<String, Object?>> de(String collection) => [for (final e in ecritures) if (e.$1 == collection) e.$2];
}

/// Le lot de la tournée du 31/10/2026 : DULOUNE (carte valide, allergique, rendez-vous 09h30), KOUZO (carte expirée, rendez-vous 10h45), TAVAPI (non assuré).
SourceMemoire lotDeDemonstration() => SourceMemoire({
      'patients': [
        const LigneLot('p1', {'code': 'CBG/12/26', 'nom': 'DULOUNE', 'prenom': 'Aline', 'quartier': 'Kouba', 'telephone': '97 11 22 33', 'ageDeclare': 67, 'assureur': 'NSIA', 'carteExpiration': '2026-12-31', 'allergies': ['Pénicilline']}),
        const LigneLot('p2', {'code': 'CBG/174/26', 'nom': 'KOUZO', 'prenom': 'Roulin', 'quartier': 'Péporiyakou', 'ageDeclare': 29, 'assureur': 'NSIA', 'carteExpiration': '2026-08-15'}),
        const LigneLot('p3', {'code': 'CBG/1109/26', 'nom': 'TAVAPI', 'prenom': 'Fikponou', 'quartier': 'Bérécingou', 'ageDeclare': 8}),
      ],
      'rendezvous': [
        const LigneLot('r1', {'patientId': 'p1', 'date': '2026-10-31T09:30', 'statut': 'planifiee', 'type': 'Domicile', 'motif': 'Suivi HTA'}),
        const LigneLot('r2', {'patientId': 'p2', 'date': '2026-10-31T10:45', 'statut': 'planifiee', 'type': 'Domicile', 'motif': 'Post-partum J5'}),
        const LigneLot('r3', {'patientId': 'p3', 'date': '2026-10-30T14:00', 'statut': 'planifiee', 'type': 'Domicile', 'motif': 'Paludisme, contrôle'}),
        const LigneLot('r4', {'patientId': 'p3', 'date': '2026-11-02T14:00', 'statut': 'planifiee', 'type': 'Domicile', 'motif': 'demain et après'}),
        const LigneLot('r5', {'patientId': 'p1', 'date': '2026-10-31T08:00', 'statut': 'planifiee', 'motif': 'archivé'}, archive: true),
      ],
      // Le catalogue des médicaments du lot (E1559) : le soignant CHOISIT, il ne tape plus un nom.
      'produits': [
        const LigneLot('PRD0001', {'designation': 'PARACETAMOL 500 MG', 'unite': 'Boîte', 'categorie': 'medicament', 'prixAchat': 500, 'stockDetail': 40}),
        const LigneLot('PRD0002', {'designation': 'AMOXICILLINE 500 MG', 'unite': 'Boîte', 'categorie': 'medicament', 'prixAchat': 1200, 'stockDetail': 2}),
      ],
      'constantes': [
        const LigneLot('c1', {'patientId': 'p1', 'patientCode': 'CBG/12/26', 'dateHeure': '2026-10-31T08:15', 'temperature': 38.6, 'pouls': 96, 'tension': '120/80'}),
      ],
    });

class FauxMoteur implements MoteurMobile {
  FauxMoteur({this.refus, SourceMemoire? source, this.fonction = 'medecin', this.agent = 'Dr YORO M’ABEKPIA Foulumi', this.refusATraiter = const [], this.profilDuCode = ProfilMobile.soignant})
      : source = source ?? lotDeDemonstration(),
        // Le rôle des droits vient de la fonction que la mère fixe à l'appairage : le faux le pose comme le moteur réel, jamais autrement.
        droits = SuiviDroits(graineDeTest(), role: mobRoleDroits(reception: profilDuCode != ProfilMobile.soignant, fonction: fonction));

  @override
  final SuiviDroits droits;

  /// Le profil que le CODE d'appairage porte (E1600) : le téléphone ne le choisit pas, il le reçoit de la mère.
  final ProfilMobile profilDuCode;
  final String? refus;
  final SourceMemoire source;
  final String fonction, agent;
  final List<RefusAffiche> refusATraiter;
  ProfilMobile? _profil;
  @override
  ProfilMobile? get profil => _profil;

  /// Le profil posé, le rôle des droits suit (réception : `reception` ; soignant : le rôle de sa fonction), comme dans le moteur réel.
  set profil(ProfilMobile? p) {
    _profil = p;
    droits.definirRole(p == null ? null : mobRoleDroits(reception: p != ProfilMobile.soignant, fonction: fonction));
  }
  @override
  final ValueNotifier<EtatMobile> etat = ValueNotifier(const EtatMobile(horsLigne: true));
  final List<FichePatient> crees = [];
  String? codeAppairage, agentAppairage;

  @override
  ServiceSoignant? get soignant => profil == ProfilMobile.soignant
      ? ServiceSoignant(source, session: SessionSoignant(agent: agent, fonction: fonction), maintenant: () => horloge, droits: droits)
      : null;

  @override
  Future<void> appairer({required String code, required String cleClinique, String agent = ''}) async {
    if (refus != null) throw StateError(refus!);
    codeAppairage = code;
    agentAppairage = agent;
    profil = profilDuCode;
  }

  @override
  Future<List<RefusAffiche>> aTraiter() async => refusATraiter;

  @override
  Future<List<FichePatient>> tournee() => soignant!.patients();
  @override
  Future<List<FichePatient>> dossiersCrees() async => crees;
  @override
  Future<String> creerPatient(Map<String, Object?> champs) async {
    crees.add(FichePatient(id: 'n${crees.length}', champs: champs));
    etat.value = EtatMobile(horsLigne: true, enAttente: crees.length);
    return 'n${crees.length - 1}';
  }
}

String refusDe(RefusMobile? r) => r == null ? '' : '${r.code}|${r.motif}|${r.geste}';
