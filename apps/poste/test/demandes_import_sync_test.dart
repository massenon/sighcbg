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
const collections = ['rbac', 'modulesActifs', 'audit', 'rolesBase', 'utilisateurs', 'fournisseurs', 'notifications'];
Magasin poste() => Magasin.depuisDossier(collections);

List<List<Object?>> fichier(List<String> codes) => [
      [for (final c in jeuFournisseurs.colonnes) c.label],
      for (final code in codes) [...ligneExemple(jeuFournisseurs)]..[0] = code..[1] = 'FOURNISSEUR $code',
    ];

AnalyseImport verifier(Magasin m, List<String> codes, ProfilImport profil) {
  final a = analyserLignes(
      jeuFournisseurs, fichier(codes), 'fournisseurs.xlsx', PortImportMemoire({'fournisseurs': m.collection('fournisseurs').toutes}, profilFixe: profil, utilisateurFixe: 'LE COMPTABLE'));
  expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code}:${p.motif}']}');
  return a;
}

void main() {
  test('BOUT EN BOUT : le fileul écrit chez lui et dépose ; la mère traite SEULE ; mêmes identifiants, une fiche par code ; refus nommé → restitution ; rôle sans droit refusé ; rien vers un mobile', () async {
    const port = 19473;
    final d = Directory.systemTemp.createTempSync('demandes-import');
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

    final profilComptable = ProfilImport(role: 'comptable', libelleRole: 'Comptable', droitEcran: (e) => donnees.matrice.droit('comptable', e));
    final code = await console.codeAppareil('F1').timeout(const Duration(seconds: 20));
    await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
    moteur.demarrer();
    await converger(() => mf.collection('rbac').toutes.length == mm.collection('rbac').toutes.length, 'configuration de départ');
    // La garde « réglé sur la mère » joue bien sur le fileul : l'écriture ORDINAIRE d'un agent y est refusée.
    expect(() => mf.collection('fournisseurs').inserer({'id': 'X', 'code': 'X', 'nom': 'X', 'statut': 'actif'}), throwsA(isA<EcritureRefusee>()));

    // 1. LE FILEUL IMPORTE : visible chez lui aussitôt, malgré la garde, sous l'identité de la demande, et la demande est déposée.
    expect(svcF.passeParUneDemande(jeuFournisseurs), isTrue);
    expect(svcF.passeParUneDemande(jeuPatients), isFalse, reason: 'un jeu restreint ne passe jamais par une demande');
    final r1 = svcF.importerEtDemander(jeuFournisseurs, verifier(mf, ['IMPA', 'IMPB'], profilComptable), profil: profilComptable, nomAgent: 'LE COMPTABLE');
    expect(r1.resultat.ok, isTrue, reason: '${r1.resultat.code} ${r1.resultat.motif}');
    final locales = mf.collection('fournisseurs').actives.where((f) => f['code'] == 'IMPA' || f['code'] == 'IMPB').toList();
    expect(locales, hasLength(2), reason: 'visible chez le fileul AVANT toute réponse de la mère');
    expect(locales.every((f) => f[champEnAttenteMere] == r1.demande && '${f['id']}'.startsWith('FOU-')), isTrue, reason: 'identité de la demande, marquage « en attente de la mère »');
    final idsFileul = {for (final f in locales) f['id']};
    expect(mf.collection(demandesImportCollection).parId(r1.demande)?['etat'], demandeImportEnAttente);

    // 2. LA MÈRE TRAITE SEULE (aucun appel manuel) : le verdict revient, ses fiches portent LES MÊMES identifiants et REMPLACENT celles du fileul (aucun doublon, rien d'archivé), notification.
    await converger(() => mf.collection(demandesImportCollection).parId(r1.demande)?['etat'] == demandeImportAppliquee, 'verdict de la mère');
    expect(svcM.traitees, greaterThanOrEqualTo(1), reason: 'c\'est le service branché de la mère qui a traité');
    final v1 = mf.collection(demandesImportCollection).parId(r1.demande)!;
    expect(v1['lignes'], isEmpty, reason: 'les lignes du fichier sont effacées au verdict');
    expect(v1['traitePar'], 'Mère');
    final surMere = mm.collection('fournisseurs').actives.where((f) => f['lotImport'] == v1['resultatLot']).toList();
    expect(surMere.map((f) => f['code']).toSet(), {'IMPA', 'IMPB'});
    expect({for (final f in surMere) f['id']}, idsFileul, reason: 'la mère écrit sous les MÊMES identifiants que le fileul');
    expect(surMere.every((f) => f['validePar'] == 'LE COMPTABLE'), isTrue, reason: 'écrit au nom de l\'auteur (RG-12)');
    expect(mm.collection('audit').toutes.any((a) => a['action'] == 'Demande d’import appliquée'), isTrue, reason: 'journal RG-12 côté mère');
    expect(mf.collection('audit').toutes.any((a) => a['action'] == 'Demande d’import déposée à la mère'), isTrue, reason: 'journal RG-12 côté fileul');
    await converger(() => mf.collection(demandesImportCollection).parId(r1.demande)?['marquageLeve'] == true, 'marquage levé');
    final chezLeFileul = mf.collection('fournisseurs').toutes.where((f) => f['code'] == 'IMPA' || f['code'] == 'IMPB').toList();
    expect(chezLeFileul, hasLength(2), reason: 'UNE fiche par code chez le fileul : jamais « provisoire + archivée »');
    expect(chezLeFileul.every((f) => f['statut'] != 'archive' && f[champEnAttenteMere] == null), isTrue);
    expect(mf.collection('notifications').toutes.any((n) => n['type'] == 'import_retenu' && n['destinataire'] == 'LE COMPTABLE'), isTrue);
    expect(libelleEtatDemandeImport(mf.collection(demandesImportCollection).parId(r1.demande)!).libelle, 'Appliquée par la mère');

    // 3. REFUS NOMMÉ : la mère crée la même fiche entre-temps ; le fileul RESTITUE son écriture (archivée, RG-14), le verdict et la restitution se lisent sur la demande.
    final a2 = verifier(mf, ['IMPC'], profilComptable);
    mm.collection('fournisseurs').inserer({'id': 'F-AILLEURS', 'code': 'IMPC', 'nom': 'créée par un autre poste', 'statut': 'actif'}, prefixe: 'F');
    final avant = mm.collection('fournisseurs').toutes.length;
    final r2 = svcF.importerEtDemander(jeuFournisseurs, a2, profil: profilComptable, nomAgent: 'LE COMPTABLE');
    expect(r2.resultat.ok, isTrue);
    await converger(() => mf.collection(demandesImportCollection).parId(r2.demande)?['restitution'] == restitutionFaite, 'refus nommé puis restitution');
    final v2 = mf.collection(demandesImportCollection).parId(r2.demande)!;
    expect(v2['etat'], demandeImportRefusee);
    expect(v2['resultatCode'], 'DOUBLON_MAGASIN');
    expect(v2['resultatMotif'], contains('rejoué à la mère'));
    expect(mm.collection('fournisseurs').toutes.length, avant, reason: 'rien n\'a été écrit à la mère');
    final idsLot = [for (final e in (r2.resultat.lot!['ecrits'] as List).cast<Map>()) e['id']];
    expect(mf.collection('fournisseurs').actives.where((f) => idsLot.contains(f['id'])), isEmpty, reason: 'l\'écriture du fileul est restituée (la fiche que la mère détient sous ce code, elle, est celle de la mère)');
    final restituee = mf.collection('fournisseurs').archivees.where((f) => idsLot.contains(f['id'])).single;
    expect('${restituee['_motifArchivage']}', contains('refusé par la mère'), reason: 'archivée avec son motif, jamais supprimée (RG-14)');
    expect(mf.collection(collectionLots).toutes.any((l) => l['id'] == r2.resultat.lot!['id'] && l['etat'] == 'restitue'), isTrue);
    expect(libelleEtatDemandeImport(v2).libelle, 'Refusée par la mère, écriture restituée');
    expect(mf.collection('notifications').toutes.any((n) => n['type'] == 'import_non_retenu' && '${n['detail']}'.contains('restituée')), isTrue);

    // 4. UN RÔLE SANS LE DROIT : la mère REJOUE sous le rôle déclaré avec SA matrice et refuse en nommant (la fiche du fileul ne prête aucun droit).
    final profilForge = ProfilImport.accordeTout(role: 'medecin');
    final a3 = verifier(mf, ['IMPD'], profilForge);
    final r3 = svcF.importerEtDemander(jeuFournisseurs, a3, profil: profilForge, nomAgent: 'FAUX COMPTABLE');
    expect(r3.resultat.ok, isTrue, reason: 'le fileul falsifié a écrit chez lui (il ne contrôle que lui-même)');
    await converger(() => mf.collection(demandesImportCollection).parId(r3.demande)?['restitution'] == restitutionFaite, 'refus du rôle sans droit puis restitution');
    expect(mf.collection(demandesImportCollection).parId(r3.demande)!['resultatCode'], 'DROIT_IMPORT_REFUSE');
    expect(mf.collection('fournisseurs').actives.any((f) => f['code'] == 'IMPD'), isFalse, reason: 'la fiche du fileul falsifié est restituée');
    expect(mm.collection('fournisseurs').toutes.any((f) => f['code'] == 'IMPD'), isFalse);

    // 5. JAMAIS VERS UN TÉLÉPHONE.
    final http0 = HttpClient();
    Future<M> appel(String methode, String chemin, {M? corps, Map<String, String> entetes = const {}}) async {
      final req = await http0.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
      req.headers.contentType = ContentType.json;
      entetes.forEach(req.headers.set);
      if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
      final rep = await req.close();
      return (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
    }

    final c = (await appel('POST', '/admin/code', corps: {'etiquette': 'mobile', 'role': 'mobile', 'profil': 'soignant', 'fonction': 'infirmier'}, entetes: {'x-admin': 'secret-test'}))['code'];
    final jetons = await appel('POST', '/appairage', corps: {'code': c, 'uuid': 'dev-mobile', 'plateforme': 'test'});
    final noms = <String>[];
    var depuis = 0;
    while (true) {
      final pull = await appel('GET', '/sync/pull?depuis=$depuis&limite=500&epoch=${jetons['epoch']}', entetes: {'authorization': 'Bearer ${jetons['jeton']}'});
      final ops = (pull['ops'] as List).cast<Map>();
      for (final o in ops) {
        noms.add('${o['collection']}');
        depuis = (o['seq'] as num).toInt();
      }
      if (pull['fin'] == true || ops.isEmpty) break;
    }
    expect(noms, isNotEmpty, reason: 'le téléphone lit bien le journal : l\'absence des demandes est une EXCLUSION, pas un journal vide');
    expect(noms, isNot(contains(demandesImportCollection)));
    http0.close(force: true);
    svcM.arreter();
    appl.arreter();
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('GARDE DE CÂBLAGE : main.dart branche réellement le traitement de la mère ET la lecture des verdicts du fileul (le défaut de Nassiera : un moteur écrit, jamais appelé)', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('ServiceDemandesImport.de(magasin)'));
    expect(RegExp(r'ServiceDemandesImport\.de\(magasin\)[\s\S]{0,200}\.demarrerMere\(').hasMatch(main), isTrue, reason: 'la mère doit traiter les demandes qui lui arrivent');
    expect(RegExp(r'ServiceDemandesImport\.de\(magasin\)[\s\S]{0,300}\.demarrerFileul\(').hasMatch(main), isTrue, reason: 'le fileul doit régler son écriture locale au verdict');
    expect(File('lib/sync/pont_activite.dart').readAsStringSync(), contains("'demandesImport'"), reason: 'la demande voyage par le pont d\'activité');
  });
}
