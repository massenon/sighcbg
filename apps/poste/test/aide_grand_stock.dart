import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_demandes_import.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// OUTILS DES TESTS DU GRAND STOCK AU FILEUL (décision de la Direction du 13/11/2026) : la VRAIE mère Dart, de VRAIS moteurs de fileul, de VRAIS ponts d'activité, la vraie configuration
/// diffusée, et le câblage de `main.dart` (un fileul n'écrit jamais le catalogue `produits` par le pont : `enLectureSeule: collectionsDeLaMereSeule`).
typedef M = Map<String, Object?>;
final donnees = DonneesNavigation.depuisDossier();
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();

Magasin vide() => Magasin({
      for (final e in (vecteurs['magasin'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()],
      'audit': const [],
    });

List<List<Object?>> lignesDuCas(String id) {
  final c = (vecteurs['cas'] as List).cast<Map>().firstWhere((x) => x['id'] == id);
  return [
    for (final l in (c['lignes'] as List)) [for (final x in (l as List)) x]
  ];
}

/// Le Grand Stock du vecteur `gs-valide` : MED1 (deux lots, 100 + 50) et GANT1 (40, sans lot). Total des entrées : 190, trois mouvements.
const stockMed1 = 150, stockGant1 = 40;

/// Le jour fixe des tests.
final jourTest = DateTime(2026, 11, 13, 9);

ProfilImport profilDe(String role) => ProfilImport(role: role, libelleRole: role, droitEcran: (e) => donnees.matrice.droit(role, e));

/// Le régime de la mère SANS l'exclusion de l'activité : ce que l'on obtiendrait en levant simplement l'exclusion du Grand Stock (la mesure de l'étape 1).
RegimeDemandesImport regimeLeve() => RegimeDemandesImport(collectionsDeLaMere: collectionsConfiguration(), collectionsActivite: const {});

/// Les comptes d'un article tel qu'un poste le tient : fiches actives, compteur, lots, mouvements d'entrée de l'import.
Map<String, Object?> comptes(Magasin m, String code) {
  final ps = [for (final f in m.collection('produits').actives) if (f['code'] == code) f];
  final ids = {for (final p in ps) p['id']};
  final lots = [for (final l in m.collection('lots').actives) if (ids.contains(l['produitId'])) l];
  final mouvs = [for (final x in m.collection('mouvements').actives) if (ids.contains(x['produitId']) && x['type'] == 'entree' && '${x['justificatif']}'.startsWith('Import')) x];
  return {
    'fichesProduit': ps.length,
    'stockGros': ps.fold<num>(0, (t, p) => t + ((p['stockGros'] as num?) ?? 0)),
    'fichesLot': lots.length,
    'sommeLots': lots.fold<num>(0, (t, l) => t + ((l['quantiteRestante'] as num?) ?? 0)),
    'mouvementsEntree': mouvs.length,
    'sommeEntrees': mouvs.fold<num>(0, (t, x) => t + ((x['quantite'] as num?) ?? 0)),
  };
}

class Poste {
  Poste(this.nom, this.port, this.role, this.par) {
    moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:$port', nom: nom);
    m.horloge = () => jourTest;
    appl = ApplicateurConfiguration(m, moteur.liste);
    pont = PontActivite(m, TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs), restaurerFiche: moteur.restaurer),
        etiquette: nom, enLectureSeule: collectionsDeLaMereSeule);
    service = ServiceDemandesImport.de(m)
      ..fileulRattache = (() => true)
      ..etiquette = nom;
  }
  final String nom, role, par;
  final int port;
  final Magasin m = vide();
  late final MoteurFileul moteur;
  late final ApplicateurConfiguration appl;
  late final PontActivite pont;
  late final ServiceDemandesImport service;

  Future<void> tour() async {
    try {
      await appl.tirer();
      await pont.cycle();
    } catch (_) {/* mère injoignable : le fileul garde sa file et réessaie */}
    service.reconcilierVerdicts();
  }

  AnalyseImport analyser(String cas) {
    final a = analyserLignes(jeuImportParId('grand-stock')!, lignesDuCas(cas), '$cas.xlsx', PortMagasin(m, aujourdhui: () => jourTest, nomAgent: par, profil: profilDe(role)))..empreinte = 'e-$cas';
    expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code}:${p.motif}']}');
    return a;
  }

  Map<String, Object?> comptesDe(String code) => comptes(m, code);
  Fiche? demande(Object? id) => m.collection(demandesImportCollection).parId(id);
}

class Clinique {
  Clinique(this.port, this.dbChemin);
  final int port;
  final String dbChemin;
  late Mere mere;
  late ClientMere console;
  final Magasin mm = vide();
  late final PublicateurConfiguration pub;
  late final PontActivite pontM;
  final fileuls = <Poste>[];
  int traitees = 0;

  Future<void> demarrerMere() async {
    mere = await Mere.creer(ConfigMere(port: port, dbChemin: dbChemin, admin: 'secret-test', dossierSauvegardes: '${Directory.systemTemp.path}/sauv-grand-stock-$port'));
    await mere.demarrer();
    console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
  }

  Future<void> demarrer() async {
    await demarrerMere();
    mm.horloge = () => jourTest;
    pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero);
    pontM = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
  }

  Future<Poste> fileul(String nom, String role, String par) async {
    final p = Poste(nom, port, role, par);
    final code = await console.codeAppareil(nom).timeout(const Duration(seconds: 20));
    await p.moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
    p.moteur.demarrer();
    p.appl.demarrer(intervalle: const Duration(hours: 1)); // pose les gardes « réglé sur la mère » du fileul
    p.appl.arreter();
    fileuls.add(p);
    return p;
  }

  /// LA MÈRE REJOUE les demandes en attente (le service branché de `main.dart`, avec le régime donné par [regime]).
  void traiter(RegimeDemandesImport Function() regime) {
    final col = mm.collection(demandesImportCollection);
    for (final d in [for (final d in col.toutes) if (d['etat'] == demandeImportEnAttente && '${d['traiteLe'] ?? ''}'.isEmpty) d]) {
      final role = '${d['demandeRole']}', auteur = '${d['demandePar']}';
      final port = PortMagasin(mm, aujourdhui: () => jourTest, nomAgent: auteur, profil: profilDe(role));
      final v = traiterDemandeImport({...d}, port, jeuImportParId, regime: regime());
      col.mettreAJour(d['id'], v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-13'), journaliser: false);
      traitees++;
    }
  }

  /// Un tour de toute la clinique, MÈRE JOIGNABLE : configuration, pont de la mère, demandes, puis chaque fileul.
  Future<void> tour(RegimeDemandesImport Function() regime) async {
    await pub.pousser();
    await pontM.cycle();
    traiter(regime);
    for (final f in fileuls) {
      await f.tour();
    }
  }

  /// Des tours jusqu'à ce que [fini] soit vrai, puis [apres] tours de plus (une mesure qui s'arrête à la première convergence ne verrait jamais un compte doublé par un second passage).
  Future<void> converger(RegimeDemandesImport Function() regime, bool Function() fini, String quoi, {int apres = 3}) async {
    final fin = DateTime.now().add(const Duration(seconds: 60));
    while (!fini()) {
      await tour(regime);
      if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence (pub ${pub.erreur.value}, pontM ${pontM.erreur.value}, fileuls ${[for (final f in fileuls) '${f.nom}: ${f.appl.erreur.value}/${f.pont.erreur.value}']})');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    for (var i = 0; i < apres; i++) {
      await tour(regime);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Map<String, Object?> comptesMere(String code) => comptes(mm, code);

  Future<void> arreter() async {
    for (final f in fileuls) {
      f.appl.arreter();
    }
    pub.arreter();
    try {
      await mere.arreter();
    } catch (_) {}
  }
}
