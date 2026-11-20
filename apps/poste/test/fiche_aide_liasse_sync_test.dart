import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_validations_deposees.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;
import 'package:sigh_sync/sigh_sync.dart';
// ignore: implementation_imports
import 'package:sigh_sync/src/mere.dart' show Appareil, familles, collectionsDocumentsJamaisMobile;

import 'aide_comptes.dart';

/// LA VALIDATION D'UNE FICHE D'AIDE ET L'IMPORT DE LA LIASSE DEPUIS UN POSTE RATTACHÉ (Direction de Baguidi, 18/11/2026, points 3 et 4) : le fileul DÉPOSE (genres `fiche_aide_valider` et
/// `liasse_importer`), la mère applique en refaisant tous ses contrôles sous le rôle du compte signataire, le verdict nommé revient, mère coupée = demande en attente. Contre la VRAIE mère Dart :
/// le transport des ponts est son `traiter`, donc chaque refus est réel. Aucun nom de rôle écrit ici : les rôles viennent du référentiel des gestes réservés. Données fictives.
typedef M = Map<String, Object?>;

class _Liaison {
  _Liaison(this.mere);
  final Mere mere;
  bool coupee = false;
  int n = 0;
}

class _Transport implements TransportPont {
  _Transport(this.l, this.app);
  final _Liaison l;
  final Appareil app;
  @override
  Future<List<PieceSync>> liste(String c) async {
    if (l.coupee) throw StateError('mère injoignable');
    final rows = await l.mere.base.select('SELECT id,data,archive FROM fiches WHERE collection=?', [c]);
    return [for (final r in rows) PieceSync('${r['id']}', (jsonDecode(r['data'] as String) as Map).cast<String, Object?>(), archive: (r['archive'] as int) != 0)];
  }

  @override
  Future<void> ecrire(String c, String fiche, {required bool existe, required Map<String, Object?> champs}) async {
    if (l.coupee) throw StateError('mère injoignable');
    final f = await l.mere.lire(c, fiche);
    final vu = <String, Object?>{for (final k in champs.keys) if (f != null && f.fieldseq[k] != null) k: f.fieldseq[k]};
    final r = await l.mere.traiter({'id': 'op${l.n++}', 'type': existe ? 'modifier' : 'creer', 'collection': c, 'fiche': fiche, 'champs': jsonDecode(jsonEncode(champs)), 'hlc': 1000 + l.n, 'vu': vu}, app);
    if (r['statut'] == 'refusee') throw StateError('${r['code']} : ${r['motif']}');
  }

  @override
  Future<void> restaurer(String collection, String fiche) async => throw StateError('non porté');
}

void main() {
  final auj = DateTime(2026, 11, 18, 9);
  final roles = [for (final r in (jsonDecode(File('../../packages/rbac/data/rbac.json').readAsStringSync()) as Map)['roles'] as List) '${(r as Map)['id']}'];
  final gestes = gestesOrigine();
  final validateur = gesteReserve(gesteFichesAideValider)!.rolesDefaut.first;
  final importeur = gesteReserve(gesteDocumentsFiscauxImporter)!.rolesDefaut.first;
  final sansGeste = roles.firstWhere((r) => !gestes.peut(r, gesteFichesAideValider) && !gestes.peut(r, gesteDocumentsFiscauxImporter));

  Magasin poste(String etiquette) {
    final m = Magasin({
      for (final n in ['fichesAide', colDocumentsFiscaux, 'rbac', 'utilisateurs', 'rolesBase', 'notifications', valCollectionDepots, 'audit']) n: <M>[],
    }, 'POSTE')
      ..etiquettePoste = etiquette
      ..horloge = () => auj;
    serviceParametres(m, auteur: () => 'Poste mère').semerDefauts();
    return m;
  }

  Fiche? deposee(Magasin m, Object? id) => m.collection(valCollectionDepots).toutes.where((x) => '${x['id']}'.endsWith('$id')).firstOrNull;

  M saisieFiche({String titre = 'Enregistrer un courrier entrant', List<String> etapes = const ['Ouvrir l’écran', 'Choisir « arrivée »']}) => {
        'type': ficheAideTypeAide,
        'titre': titre,
        'motsCles': ['courrier entrant'],
        'roles': <String>[],
        'ecrans': <String>[],
        'etapes': etapes,
      };

  Fiche ficheAide(String id, {String auteur = 'U-AUTEUR', String titre = 'Enregistrer un courrier entrant'}) =>
      creerFicheAide(saisie: saisieFiche(titre: titre), id: id, auteurId: auteur, auteurNom: 'Auteur Fictif', maintenant: auj, rolesConnus: const []).fiche!;

  test('les deux genres sont de la famille A (dépôt), la liasse reste de la famille R, jamais vers un téléphone, taille bornée par un réglage', () {
    expect(familles[valCollectionDepots], 'A');
    expect(familles[colDocumentsFiscaux], 'R', reason: 'la mère seule écrit la liasse : le fileul DÉPOSE une demande, il n\'écrit pas la collection');
    expect(collectionsDocumentsJamaisMobile, containsAll([colDocumentsFiscaux, colFichesAide]));
    expect(collectionsActivite, isNot(contains(colDocumentsFiscaux)), reason: 'le pont d\'activité ne la porte pas : elle voyage par la configuration (R)');
    final js = File('../../packages/sync/banc/mere.js').readAsStringSync();
    expect(js, contains("documentsFiscaux: 'R'"));
    expect(RegExp(r'const MOBILE_JAMAIS = \[([^\]]*)\]').firstMatch(js)!.group(1)!, allOf(contains("'validationsDeposees'"), contains("'documentsFiscaux'")), reason: 'les demandes (et le document qu\'elles portent) ne vont pas au mobile');
    final d = definitionDeParametre(cleTailleMaxDepotFiscalKo)!;
    expect(d.min, isNotNull);
    expect(d.mobile, isFalse);
  });

  test('FICHE D\'AIDE : le fileul DÉPOSE la validation (compte signé), la mère coupée la garde en attente, la mère la rejoue sous le rôle de l\'auteur du geste, le verdict nommé revient et notifie', () async {
    final d = Directory.systemTemp.createTempSync('fa-mere');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere = await Mere.creer(ConfigMere(port: 19611, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes'));
    final liaison = _Liaison(mere);
    final f1 = poste('F1'), f2 = poste('F2'), mm = poste('M');
    final p1 = PontActivite(f1, _Transport(liaison, Appareil('F1', 'fileul')), etiquette: 'F1', enLectureSeule: collectionsDeLaMereSeule, reservesAuMere: true);
    final p2 = PontActivite(f2, _Transport(liaison, Appareil('F2', 'fileul')), etiquette: 'F2', enLectureSeule: collectionsDeLaMereSeule, reservesAuMere: true);
    final pm = PontActivite(mm, _Transport(liaison, Appareil('mere', 'mere')), etiquette: 'M');
    Future<void> tour() async {
      for (var i = 0; i < 3; i++) {
        for (final p in [p1, p2, pm]) {
          await p.cycle();
        }
      }
    }

    final s1 = ServiceValidationsDeposees.de(f1)..etiquette = 'F1';
    final s2 = ServiceValidationsDeposees.de(f2)..etiquette = 'F2';
    final sm = ServiceValidationsDeposees.de(mm)..etiquette = 'M'; // le compte signataire EST vérifié : exigerCompteInscrit reste vrai
    final valideur = signerAvec(f2, mm, validateur, nom: 'Valideur Fictif');
    Fiche? chez(Magasin m, String id) => m.collection('fichesAide').toutes.where((x) => x['id'] == id || x['idSync'] == id).firstOrNull;
    Future<Fiche> ecrireFiche(String id, {String auteur = 'U-AUTEUR'}) async {
      f1.collection('fichesAide').ajouterSansJournal(ficheAide(id, auteur: auteur));
      await tour();
      expect(chez(mm, id), isNotNull, reason: 'la fiche rédigée sur un fileul arrive à la mère');
      expect(chez(f2, id), isNotNull, reason: 'et à l\'autre fileul');
      return chez(f2, id)!;
    }

    // 1. Les refus se nomment DÈS LE POSTE (le contrôle de la validation directe, à blanc) : rien n'est déposé.
    final fa = await ecrireFiche('F1-FAI-1');
    expect(s2.deposerFicheAideValider(fa, role: sansGeste, validateurId: valideur.utilisateurId, validateurNom: valideur.nom).refus!.code, 'GESTE_RESERVE');
    expect(s2.deposerFicheAideValider(fa, role: validateur, validateurId: 'U-AUTEUR', validateurNom: 'Auteur Fictif').refus!.code, 'AUTEUR_NE_VALIDE_PAS');
    expect(f2.collection(valCollectionDepots).toutes, isEmpty);

    // 2. Mère COUPÉE : le fileul dépose quand même ; la demande attend, la fiche reste « proposée », le poste continue de travailler.
    liaison.coupee = true;
    final dep = s2.deposerFicheAideValider(fa, role: validateur, validateurId: valideur.utilisateurId, validateurNom: valideur.nom);
    expect(dep.ok, isTrue, reason: '${dep.refus?.code} ${dep.refus?.motif}');
    expect(s2.deposerFicheAideValider(fa, role: validateur, validateurId: valideur.utilisateurId, validateurNom: valideur.nom).dejaDepose, isTrue, reason: 'rejouable : une demande identique en attente n\'est pas doublée');
    expect(s2.depotFicheAideEnAttente(chez(f2, 'F1-FAI-1')!), isNotNull, reason: '« transmise à la mère, en attente »');
    expect(chez(f2, 'F1-FAI-1')!['statut'], ficheAideProposee, reason: 'jamais « validée » sur un dépôt seul');
    expect(f2.collection(valCollectionDepots).toutes.single['demandeCompte'], valideur.utilisateurId, reason: 'le dépôt est signé du compte de l\'agent connecté');
    await tour();
    expect(p2.erreur.value, isNotNull, reason: 'mère injoignable : le poste le dit, rien n\'est perdu');
    expect(mm.collection(valCollectionDepots).toutes, isEmpty);
    expect(sm.traiter(), 0);
    liaison.coupee = false;
    await tour();
    expect(mm.collection(valCollectionDepots).toutes.single['genre'], valGenreFicheAideValider);
    expect(mm.collection(valCollectionDepots).toutes, hasLength(1), reason: 'aucun doublon après la reprise');

    // 3. La mère REJOUE : sous le rôle et le nom de l'auteur du geste, à la date du geste.
    expect(sm.traiter(), 1);
    final validee = chez(mm, 'F1-FAI-1')!;
    expect([validee['statut'], validee['validePar'], validee['validateurId'], validee['valideLe']], [ficheAideValidee, 'Valideur Fictif', valideur.utilisateurId, '2026-11-18']);
    expect(ficheAideCitable(validee), isTrue);
    expect(mm.collection(valCollectionDepots).toutes.single['etat'], valDepotAppliquee);
    expect(mm.collection(valCollectionDepots).toutes.single['signeLe'], isNotNull);
    expect(mm.collection('audit').toutes.any((x) => x['action'] == 'Validation de fiche d’aide (geste réservé)' && (x['apres'] as Map)['appliquée par'] != null), isTrue, reason: 'RG-12 : déposée par X, appliquée par la mère');
    expect(sm.traiter(), 0, reason: 'un dépôt traité n\'est jamais rejoué');
    await tour();
    for (final m in [f1, f2]) {
      expect([chez(m, 'F1-FAI-1')!['statut'], chez(m, 'F1-FAI-1')!['validePar']], [ficheAideValidee, 'Valideur Fictif'], reason: 'la validation de la mère arrive aux deux fileuls');
    }
    expect(s2.depotFicheAideEnAttente(chez(f2, 'F1-FAI-1')!), isNull, reason: 'appliquée : la fiche parle');
    expect(f2.collection(valCollectionDepots).toutes.single['etat'], valDepotAppliquee, reason: 'le verdict revient au fileul sur la même fiche de dépôt');
    expect(s2.reconcilier(), 1);
    final notif = f2.collection('notifications').toutes.single;
    expect(notif['libelle'], 'Fiche d’aide validée par la mère');
    expect(notif['destinataire'], 'Valideur Fictif');

    // 4. Refus NOMMÉ de la mère : son geste retiré à SA matrice entre le dépôt et l'application ; la fiche reste proposée, le motif revient à la fiche.
    final fb = await ecrireFiche('F1-FAI-2');
    expect(s2.deposerFicheAideValider(fb, role: validateur, validateurId: valideur.utilisateurId, validateurNom: valideur.nom).ok, isTrue);
    await tour();
    mm.collection('rbac').inserer({'id': 'RBAC-RETRAIT', 'role': validateur, 'statut': 'actif', 'droitsGestes': {gesteFichesAideValider: false}}, prefixe: 'RBAC');
    expect(sm.traiter(), 1);
    expect(chez(mm, 'F1-FAI-2')!['statut'], ficheAideProposee, reason: 'un refus n\'écrit rien sur la fiche');
    await tour();
    final refuse = s2.depotFicheAideRefuse(chez(f2, 'F1-FAI-2')!);
    expect([refuse!['etat'], refuse['resultatCode']], [valDepotRefusee, 'GESTE_RESERVE']);
    expect('${refuse['resultatMotif']}', isNotEmpty);
    expect(s2.reconcilier(), 1);
    expect(f2.collection('notifications').toutes.map((n) => n['libelle']), contains('Validation de la fiche d’aide refusée par la mère'));
    mm.collection('rbac').archiver(mm.collection('rbac').toutes.firstWhere((x) => x['id'] != null && x['role'] == validateur)['id']);

    // 5. On valide ce qu'on a lu : la fiche réécrite entre le dépôt et l'application est refusée (FICHE_MODIFIEE).
    final fc = await ecrireFiche('F1-FAI-3');
    expect(s2.deposerFicheAideValider(fc, role: validateur, validateurId: valideur.utilisateurId, validateurNom: valideur.nom).ok, isTrue);
    await tour();
    f1.collection('fichesAide').mettreAJour('F1-FAI-3', {'etapes': ['Une tout autre étape']}, journaliser: false);
    await tour();
    expect(chez(mm, 'F1-FAI-3')!['etapes'], ['Une tout autre étape']);
    expect(sm.traiter(), 1);
    expect(deposee(mm, f2.collection(valCollectionDepots).toutes.first['id'])!['resultatCode'], 'FICHE_MODIFIEE');
    expect(chez(mm, 'F1-FAI-3')!['statut'], ficheAideProposee);

    // 6. Le compte signataire est VÉRIFIÉ par la mère : un compte inconnu (poste d'un intrus, dépôt écrit à la main) est refusé AVANT tout rejeu.
    final fd = await ecrireFiche('F1-FAI-4');
    final intrus = Agent(utilisateurId: 'USR-INCONNU', nom: 'Intrus Fictif', role: validateur);
    f2.poserActeur(intrus);
    final di = s2.deposerFicheAideValider(fd, role: validateur, validateurId: intrus.utilisateurId, validateurNom: intrus.nom);
    expect(di.ok, isTrue, reason: 'le poste ne connaît pas les comptes de la mère : c\'est elle qui refuse');
    await tour();
    expect(sm.traiter(), 1);
    expect(deposee(mm, di.fiche!['id'])!['resultatCode'], codeCompteInconnu);
    expect(chez(mm, 'F1-FAI-4')!['statut'], ficheAideProposee);
    for (final p in [p1, p2, pm]) {
      expect(p.motifsRefus, isEmpty, reason: 'aucune écriture légitime refusée par la mère : ${p.motifsRefus}');
    }
  });

  test('LIASSE : le fileul DÉPOSE la demande (contenu validé localement), la mère coupée la garde, la mère REJOUE la validation stricte et écrit sous le geste du compte signataire ; la collection reste R et ne part pas au fileul', () async {
    final d = Directory.systemTemp.createTempSync('li-mere');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere = await Mere.creer(ConfigMere(port: 19612, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes'));
    final liaison = _Liaison(mere);
    final f1 = poste('F1'), f2 = poste('F2'), mm = poste('M');
    final p1 = PontActivite(f1, _Transport(liaison, Appareil('F1', 'fileul')), etiquette: 'F1', enLectureSeule: collectionsDeLaMereSeule, reservesAuMere: true);
    final pm = PontActivite(mm, _Transport(liaison, Appareil('mere', 'mere')), etiquette: 'M');
    Future<void> tour() async {
      for (var i = 0; i < 3; i++) {
        for (final p in [p1, pm]) {
          await p.cycle();
        }
      }
    }

    final s1 = ServiceValidationsDeposees.de(f1)..etiquette = 'F1';
    final sm = ServiceValidationsDeposees.de(mm)..etiquette = 'M';
    final comptable = signerAvec(f1, mm, importeur, nom: 'Comptable Fictif');
    final liasse = lireDocumentFiscal(File('tool/donnees/liasse_2025_demo.json').readAsStringSync()).document!;
    VerdictDepot deposer({String role = '', String? date, String source = 'Remise à la DGI'}) =>
        s1.deposerLiasse(document: liasse, dateDepot: date, source: source, auteur: comptable.nom, role: role.isEmpty ? importeur : role);

    // 1. Refus à blanc, nommés, rien de déposé.
    expect(deposer(role: sansGeste).refus!.code, 'GESTE_RESERVE');
    expect(deposer(source: ' ').refus!.code, 'SOURCE_ABSENTE');
    expect(deposer(date: '2026-05-02').refus!.code, 'DATE_DEPOT_DIVERGENTE');
    expect(f1.collection(valCollectionDepots).toutes, isEmpty);

    // 2. Mère coupée : la demande attend ; rien n'est écrit à la mère ; le fileul n'écrit pas la collection.
    liaison.coupee = true;
    final dep = deposer();
    expect(dep.ok, isTrue, reason: '${dep.refus?.code} ${dep.refus?.motif}');
    expect(deposer().dejaDepose, isTrue);
    expect(f1.collection(colDocumentsFiscaux).toutes, isEmpty, reason: 'le fileul n\'écrit pas la liasse');
    await tour();
    expect(p1.erreur.value, isNotNull);
    expect(mm.collection(valCollectionDepots).toutes, isEmpty);
    liaison.coupee = false;
    await tour();
    expect(mm.collection(valCollectionDepots).toutes, hasLength(1));
    expect(mm.collection(valCollectionDepots).toutes.single['contenu'], isA<Map>(), reason: 'le document arrive à la mère dans la demande');

    // 3. La mère REJOUE la validation stricte et applique.
    expect(sm.traiter(), 1);
    final v = mm.collection(colDocumentsFiscaux).toutes.single;
    expect([v['genre'], v['exercice'], v['dateEffet'], v['source'], v['importePar'], v['statut']], [docFiscalLiasse, 2025, '2026-04-30', 'Remise à la DGI', 'Comptable Fictif', 'actif']);
    final depot = mm.collection(valCollectionDepots).toutes.single;
    expect([depot['etat'], depot['resultatReference']], [valDepotAppliquee, v['id']]);
    expect(depot['contenu'], isEmpty, reason: 'le document n\'est pas dupliqué dans le registre des demandes : la version importée vit dans documentsFiscaux');
    expect((depot['resume'] as Map)['BILAN_ACTIF'], 29, reason: 'l\'identité et des nombres de lignes restent');
    final ligne = mm.collection('audit').toutes.firstWhere((x) => x['action'] == 'Import' && x['entite'] == 'Document fiscal');
    expect((ligne['apres'] as Map)['appliquée par'], isNotNull);
    for (final interdit in ['"brut"', '"netN1"', 'IMMOBILISATIONS', '3201001996110']) {
      expect(jsonEncode(mm.collection('audit').toutes), isNot(contains(interdit)), reason: 'le journal ne porte aucun contenu comptable : $interdit');
    }
    expect(sm.traiter(), 0);
    await tour();
    expect(f1.collection(valCollectionDepots).toutes.single['etat'], valDepotAppliquee, reason: 'le verdict nommé revient au fileul');
    expect(f1.collection(valCollectionDepots).toutes.single['contenu'], isEmpty);
    expect(s1.reconcilier(), 1);
    expect(f1.collection('notifications').toutes.single['libelle'], 'Import fiscal appliqué par la mère');
    expect(f1.collection('notifications').toutes.single['detail'], contains('${v['id']}'));

    // 4. La collection reste R : la mère la publie, le fileul la REÇOIT ; un fileul qui l'écrirait quand même est refusé (droit_refuse) par la vraie mère.
    final publi = PublicateurConfiguration(mm, (c, id, champs) => _Transport(liaison, Appareil('mere', 'mere')).ecrire(c, id, existe: false, champs: champs), collections: {colDocumentsFiscaux});
    expect(await publi.pousser(), 1);
    final appl = ApplicateurConfiguration(f2, _Transport(liaison, Appareil('F2', 'fileul')).liste, collections: {colDocumentsFiscaux});
    expect(await appl.tirer(), 1);
    expect(f2.collection(colDocumentsFiscaux).toutes.single['importePar'], 'Comptable Fictif', reason: 'la version écrite par la mère arrive au fileul par la configuration');
    await expectLater(
        _Transport(liaison, Appareil('F1', 'fileul')).ecrire(colDocumentsFiscaux, 'doc-fraude', existe: false, champs: {'genre': docFiscalLiasse, 'exercice': 2025, 'statut': 'actif'}), throwsA(predicate((e) => '$e'.contains('droit_refuse'))));
    expect((await mere.base.select("SELECT COUNT(*) AS n FROM fiches WHERE collection=?", [colDocumentsFiscaux])).first['n'], 1);

    // 5. Refus nommés de la mère : le geste retiré à SA matrice, un contenu falsifié (la mère ne croit aucune lecture d'un autre poste), un compte inconnu.
    mm.collection('rbac').inserer({'id': 'RBAC-RETRAIT', 'role': importeur, 'statut': 'actif', 'droitsGestes': {gesteDocumentsFiscauxImporter: false}}, prefixe: 'RBAC');
    final classeur = lireDocumentFiscal(File('tool/donnees/classeur_2025_demo.json').readAsStringSync()).document!;
    final d2 = s1.deposerLiasse(document: classeur, dateDepot: '2026-04-30', source: 'Classeur de l’expert-comptable', auteur: comptable.nom, role: importeur);
    expect(d2.ok, isTrue);
    await tour();
    expect(sm.traiter(), 1);
    expect(deposee(mm, d2.fiche!['id'])!['resultatCode'], 'GESTE_RESERVE', reason: 'la mère relit SA matrice');
    expect(mm.collection(colDocumentsFiscaux).toutes, hasLength(1));
    expect(deposee(mm, d2.fiche!['id'])!['contenu'], isEmpty, reason: 'même refusé, le document ne reste pas dupliqué');
    mm.collection('rbac').archiver(mm.collection('rbac').toutes.firstWhere((x) => x['role'] == importeur)['id']);

    final falsifie = {...jsonDecode(jsonEncode(liasse.contenu)) as Map<String, Object?>}..remove('FLUX');
    f1.collection(valCollectionDepots).ajouterSansJournal({
      'id': 'VDP-FALSIFIE',
      'statut': 'actif',
      'genre': valGenreLiasseImporter,
      'famille': colDocumentsFiscaux,
      'cible': 'liasse|2025|2026-04-30',
      'libelle': 'Import falsifié',
      'etat': valDepotDeposee,
      'documentGenre': docFiscalLiasse,
      'exercice': 2025,
      'dateDepot': '2026-04-30',
      'source': 'Remise à la DGI',
      'contenu': falsifie,
      'demandeRole': importeur,
      'demandePar': comptable.nom,
      'demandePoste': 'F1',
      'demandeCompte': comptable.utilisateurId,
      'demandeLe': '2026-11-18T09:00:00.000Z',
    });
    await tour();
    expect(sm.traiter(), 1);
    final fa = deposee(mm, 'VDP-FALSIFIE')!;
    expect([fa['etat'], fa['resultatCode']], [valDepotRefusee, 'CLE_MANQUANTE'], reason: 'la validation stricte est rejouée par la mère');
    expect(mm.collection(colDocumentsFiscaux).toutes, hasLength(1));
    await tour();
    expect(s1.reconcilier(), 2, reason: 'les deux refus de la mère reviennent au fileul avec leur notification');
    expect(f1.collection('notifications').toutes.map((n) => n['libelle']), contains('Import fiscal refusé par la mère'));
    for (final p in [p1, pm]) {
      expect(p.motifsRefus, isEmpty, reason: 'aucune écriture légitime refusée : ${p.motifsRefus}');
    }
  });
}
