import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/matrice_vive.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_demandes_import.dart';
import 'package:sigh_sync/sigh_sync.dart';

import 'aide_comptes.dart';

/// LA DEMANDE D'IMPORT ENTRE UN FILEUL ET LA MÈRE (lot IMP-C, « option c » de la Direction du 12/11/2026), à travers le VRAI poste : vraie mère (service de synchronisation), vrai moteur de
/// fileul, vrais ponts d'activité, vraie configuration diffusée. RIEN n'est traité à la main : c'est `ServiceDemandesImport.demarrerMere` — le même appel que `main.dart` — qui écoute
/// les demandes arrivées par le pont et rend le verdict. (Le défaut de Nassiera, `appliquerDemandes()` jamais branchée, n'est pas reproduit : le dernier test garde le câblage.)
///
///  - le fileul écrit chez lui TOUT DE SUITE malgré la garde « réglé sur la mère » (identité de la demande, « en attente de la mère »), et dépose la demande ;
///  - la mère la TRAITE seule, applique au nom de l'auteur sous les MÊMES identifiants, journalise ; sa copie remplace celle du fileul (une fiche par code) et le fileul est notifié ;
///  - une fiche créée à la mère entre-temps : refus NOMMÉ, le fileul RESTITUE son écriture (archivée), avec notification ;
///  - un rôle sans le droit : refus de la mère, nommé ;
///  - jamais vers un téléphone.
typedef M = Map<String, Object?>;

final donnees = DonneesNavigation.depuisDossier();
const collections = ['rbac', 'modulesActifs', 'audit', 'rolesBase', 'utilisateurs', 'naturesFacture', 'budgets', 'exercices', 'centresCouts', 'notifications'];
Magasin poste() => Magasin.depuisDossier(collections);

List<List<Object?>> fichier(List<String> codes) => [
      [for (final c in jeuNaturesFacture.colonnes) c.label],
      for (final code in codes) ['$code', 'NATURE $code', 'Chirurgie', 'Décision test'],
    ];

AnalyseImport verifier(Magasin m, List<String> codes, ProfilImport profil) {
  final a = analyserLignes(
      jeuNaturesFacture, fichier(codes), 'natures.xlsx', PortImportMemoire({'naturesFacture': m.collection('naturesFacture').toutes}, profilFixe: profil, utilisateurFixe: 'LA DAF'));
  expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code}:${p.motif}']}');
  return a;
}

void main() {
  test('BOUT EN BOUT, VRAIE MÈRE : natures de facture (direct et demande) appliquées sous les mêmes identifiants, doublon refusé et restitué ; budgets (restreint) ne passe jamais par une demande, une demande forgée est refusée', () async {
    const port = 19611;
    final d = Directory.systemTemp.createTempSync('demandes-import-ref');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauv'));
    await mere0.demarrer();
    addTearDown(() async {
      try {
        await mere0.arreter();
      } catch (_) {}
    });
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: '${d.path}/F1.db', mere: 'http://127.0.0.1:1', nom: 'F1');
    final mm = poste(), mf = poste();
    mm.horloge = () => DateTime(2026, 11, 12);
    mf.horloge = () => DateTime(2026, 11, 12);
    mm.utilisateur = 'Poste mère';
    // LA MÈRE : exactement l'appel de main.dart — la matrice EN FORCE de la mère, relue à chaque demande.
    final vive = MatriceVive(donnees, mm);
    final svcM = ServiceDemandesImport.de(mm)
      ..fileulRattache = (() => false)
      ..etiquette = 'M'
      ..demarrerMere(matrice: () => vive.matrice);
    final svcF = ServiceDemandesImport.de(mf)
      ..fileulRattache = (() => true)
      ..etiquette = 'F1';
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero);
    final appl = ApplicateurConfiguration(mf, moteur.liste);
    appl.demarrer(intervalle: const Duration(hours: 1)); // pose les gardes « réglé sur la mère » du fileul
    appl.arreter();
    TransportFileul tf() =>
        TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs), restaurerFiche: moteur.restaurer);
    final pm = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M', collections: {demandesImportCollection});
    final pf = PontActivite(mf, tf(), etiquette: 'F1', collections: {demandesImportCollection});

    Future<void> tour() async {
      await pub.pousser();
      await appl.tirer();
      await pf.cycle();
      await pm.cycle();
      await Future<void>.delayed(const Duration(milliseconds: 20)); // la mère traite en microtâche, à la réception
      await pub.pousser();
      await appl.tirer();
      await pf.cycle();
      svcF.reconcilierVerdicts();
    }

    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 45));
      while (!fini()) {
        await tour();
        if (DateTime.now().isAfter(fin)) {
          fail('$quoi : pas de convergence. mère ${mm.collection(demandesImportCollection).toutes.map((x) => '${x['id']}:${x['etat']}')} ; fileul ${mf.collection(demandesImportCollection).toutes.map((x) => '${x['id']}:${x['etat']}')} ; '
              'erreurs ${pm.erreur.value} ${pf.erreur.value} ${svcM.derniereErreur} ; refus ${pm.motifsRefus} ${pf.motifsRefus}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }

    final profilDaf = ProfilImport(role: 'da', libelleRole: 'DAF', droitEcran: (e) => donnees.matrice.droit('da', e));
    final code = await console.codeAppareil('F1').timeout(const Duration(seconds: 20));
    await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
    moteur.demarrer();
    await converger(() => mf.collection('rbac').toutes.length == mm.collection('rbac').toutes.length, 'configuration de départ');
    expect(() => mf.collection('naturesFacture').inserer({'id': 'X', 'code': 'X', 'libelle': 'X', 'secteur': 'Chirurgie', 'statut': 'actif'}), throwsA(isA<EcritureRefusee>()),
        reason: 'la garde « réglé sur la mère » joue : l\'écriture ordinaire d\'un agent du fileul est refusée');

    // 1. GROUPE DIRECT ET DEMANDE : natures de facture.
    expect(svcF.passeParUneDemande(jeuNaturesFacture), isTrue);
    // AI (16/11/2026) : la demande porte le compte nominatif qui la signe ; la mère vérifie qu'il existe chez elle, avec ce rôle.
    signerAvec(mf, mm, 'da', nom: 'LA DAF');
    final r1 = svcF.importerEtDemander(jeuNaturesFacture, verifier(mf, ['IMPA', 'IMPB'], profilDaf), profil: profilDaf, nomAgent: 'LA DAF');
    expect(r1.resultat.ok, isTrue, reason: '${r1.resultat.code} ${r1.resultat.motif}');
    final locales = mf.collection('naturesFacture').actives.where((f) => f['code'] == 'IMPA' || f['code'] == 'IMPB').toList();
    expect(locales, hasLength(2), reason: 'visible chez le fileul AVANT toute réponse de la mère');
    expect(locales.every((f) => f[champEnAttenteMere] == r1.demande && '${f['id']}'.startsWith('NAT-')), isTrue);
    final idsFileul = {for (final f in locales) f['id']};
    await converger(() => mf.collection(demandesImportCollection).parId(r1.demande)?['etat'] == demandeImportAppliquee, 'verdict de la mère');
    final v1 = mf.collection(demandesImportCollection).parId(r1.demande)!;
    final surMere = mm.collection('naturesFacture').actives.where((f) => f['lotImport'] == v1['resultatLot']).toList();
    expect({for (final f in surMere) f['code']}, {'IMPA', 'IMPB'});
    expect({for (final f in surMere) f['id']}, idsFileul, reason: 'la mère écrit sous les MÊMES identifiants que le fileul');
    expect(surMere.every((f) => f['validePar'] == 'LA DAF'), isTrue, reason: 'écrit au nom de l\'auteur (RG-12)');
    await converger(() => mf.collection(demandesImportCollection).parId(r1.demande)?['marquageLeve'] == true, 'marquage levé');
    expect(mf.collection('naturesFacture').toutes.where((f) => f['code'] == 'IMPA' || f['code'] == 'IMPB'), hasLength(2), reason: 'UNE fiche par code chez le fileul');

    // 2. REFUS NOMMÉ : la mère crée le même code entre-temps ; le fileul restitue (archivage, RG-14).
    final a2 = verifier(mf, ['IMPC'], profilDaf);
    mm.collection('naturesFacture').inserer({'id': 'N-AILLEURS', 'code': 'IMPC', 'libelle': 'créée ailleurs', 'secteur': 'Chirurgie', 'statut': 'actif'}, prefixe: 'NAT');
    final r2 = svcF.importerEtDemander(jeuNaturesFacture, a2, profil: profilDaf, nomAgent: 'LA DAF');
    expect(r2.resultat.ok, isTrue);
    await converger(() => mf.collection(demandesImportCollection).parId(r2.demande)?['restitution'] == restitutionFaite, 'refus nommé puis restitution');
    expect(mf.collection(demandesImportCollection).parId(r2.demande)!['resultatCode'], 'DOUBLON_MAGASIN');
    final idsLot = [for (final e in (r2.resultat.lot!['ecrits'] as List).cast<Map>()) e['id']];
    expect(mf.collection('naturesFacture').actives.where((f) => idsLot.contains(f['id'])), isEmpty, reason: 'écriture du fileul restituée');
    expect(mf.collection('naturesFacture').archivees.where((f) => idsLot.contains(f['id'])), hasLength(1), reason: 'archivée, jamais supprimée');

    // 3. GROUPE DIRECT SEUL (RESTREINT) : les budgets ne passent JAMAIS par une demande.
    expect(svcF.passeParUneDemande(jeuBudgets), isFalse);
    expect(svcF.reserveALaMere(jeuBudgets), isFalse, reason: 'aucune cible de configuration : ni demande, ni réservé à la mère, l\'import est local comme la saisie de l\'écran');
    // Une demande FORGÉE par un fileul falsifié (un jeu restreint déposé quand même) est refusée par la mère, en le nommant.
    final lignes = [
      [for (final c in jeuBudgets.colonnes) c.label],
      [2027, 'laboratoire', 'Investissements', 1000]
    ];
    // (`composerDemandeImport` refuse un jeu restreint par une assertion : la demande forgée est écrite à la main, comme le ferait un fileul falsifié.)
    final fausse = {
      'id': 'DIMFORGEE1',
      'statut': 'actif',
      'jeu': jeuBudgets.id,
      'jeuLibelle': jeuBudgets.libelle,
      'fichier': 'b.xlsx',
      'lignes': lignes,
      'ignorerExistants': false,
      'nbLignes': 1,
      'aEcrire': 1,
      'nbAvertissements': 0,
      'etat': demandeImportEnAttente,
      'demandePar': 'LA DAF',
      'demandeRole': 'da',
      'demandePoste': 'F1',
      'demandeLe': '2026-11-12',
      // Forgée sous un compte VALIDE (le contrôle du compte passe) : c'est la nature du jeu qui la fait refuser.
      champCompteDecision: compteDuRole(mm, 'da').utilisateurId,
    };
    mf.collection(demandesImportCollection).inserer({...fausse, 'id': 'DIMFORGEE1'}, prefixe: 'DIM');
    await converger(() => mf.collection(demandesImportCollection).parId('DIMFORGEE1')?['etat'] == demandeImportRefusee, 'refus de la demande forgée');
    expect(mf.collection(demandesImportCollection).parId('DIMFORGEE1')!['resultatCode'], 'JEU_RESTREINT');
    expect(mm.collection('budgets').toutes.where((b) => b['lotImport'] != null), isEmpty, reason: 'rien n\'est écrit à la mère');
    svcM.arreter();
    appl.arreter();
  }, timeout: const Timeout(Duration(seconds: 240)));
}
