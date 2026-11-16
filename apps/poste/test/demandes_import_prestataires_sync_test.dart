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

/// LES PRESTATAIRES EXTERNES, JEU « DIRECT ET DEMANDE » (décision de la Direction du 14/11/2026, option 2 : traités comme les natures de facture, tarif par acte compris), à travers le
/// VRAI poste : vraie mère, DEUX vrais moteurs de fileul, vrais ponts, vraie configuration diffusée.
///
///  - un fileul importe : il voit ses prestataires TOUT DE SUITE (identité de la demande, « en attente de la mère ») et la demande part ;
///  - la mère l'applique sous les MÊMES identifiants et au nom de l'auteur ; un SECOND fileul reçoit la liste par la configuration (la collection est essentielle : la mère seule écrit) ;
///  - un refus nommé de la mère (prestataire créé ailleurs entre-temps) est RESTITUÉ chez le fileul (archivage, RG-14) ;
///  - un fileul ne peut pas écrire un prestataire à la main (garde « réglé sur la mère ») : seul l'import passe ;
///  - jamais vers un téléphone.
typedef M = Map<String, Object?>;

final donnees = DonneesNavigation.depuisDossier();
const collections = ['rbac', 'modulesActifs', 'audit', 'rolesBase', 'utilisateurs', 'prestataires', 'notifications'];
Magasin poste() => Magasin.depuisDossier(collections);

List<List<Object?>> fichier(List<String> noms, {int tarif = 25000}) => [
      [for (final c in jeuPrestataires.colonnes) c.label],
      for (final n in noms) [n, 'Chirurgie', '0197000000', tarif, '', 'Non'],
    ];

AnalyseImport verifier(Magasin m, List<String> noms, ProfilImport profil, {int tarif = 25000}) {
  final a = analyserLignes(jeuPrestataires, fichier(noms, tarif: tarif), 'prestataires.xlsx',
      PortImportMemoire({'prestataires': m.collection('prestataires').toutes}, profilFixe: profil, utilisateurFixe: 'LA DAF'));
  expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code}:${p.motif}']}');
  return a;
}

void main() {
  test('BOUT EN BOUT, VRAIE MÈRE ET DEUX FILEULS : prestataires importés par F1, appliqués par la mère, reçus par F2 ; doublon refusé et restitué ; rien vers un téléphone', () async {
    const port = 19613;
    final d = Directory.systemTemp.createTempSync('demandes-import-prest');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauv'));
    await mere0.demarrer();
    addTearDown(() async {
      try {
        await mere0.arreter();
      } catch (_) {}
    });
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur1 = MoteurFileul.creer(dbChemin: '${d.path}/F1.db', mere: 'http://127.0.0.1:1', nom: 'F1');
    final moteur2 = MoteurFileul.creer(dbChemin: '${d.path}/F2.db', mere: 'http://127.0.0.1:1', nom: 'F2');
    final mm = poste(), mf1 = poste(), mf2 = poste();
    for (final m in [mm, mf1, mf2]) {
      m.horloge = () => DateTime(2026, 11, 14);
    }
    mm.utilisateur = 'Poste mère';
    final vive = MatriceVive(donnees, mm);
    final svcM = ServiceDemandesImport.de(mm)
      ..fileulRattache = (() => false)
      ..etiquette = 'M'
      ..demarrerMere(matrice: () => vive.matrice);
    final svc1 = ServiceDemandesImport.de(mf1)
      ..fileulRattache = (() => true)
      ..etiquette = 'F1';
    final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero);
    final appl1 = ApplicateurConfiguration(mf1, moteur1.liste)..demarrer(intervalle: const Duration(hours: 1));
    final appl2 = ApplicateurConfiguration(mf2, moteur2.liste)..demarrer(intervalle: const Duration(hours: 1));
    appl1.arreter();
    appl2.arreter();
    TransportFileul tf(MoteurFileul m) =>
        TransportFileul(lire: m.liste, ecrireFiche: (c, f, {required existe, required champs}) => m.ecrire(c, f, existe: existe, champs: champs), restaurerFiche: m.restaurer);
    final pm = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M', collections: {demandesImportCollection});
    final pf1 = PontActivite(mf1, tf(moteur1), etiquette: 'F1', collections: {demandesImportCollection});

    Future<void> tour() async {
      await pub.pousser();
      await appl1.tirer();
      await appl2.tirer();
      await pf1.cycle();
      await pm.cycle();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pub.pousser();
      await appl1.tirer();
      await appl2.tirer();
      await pf1.cycle();
      svc1.reconcilierVerdicts();
    }

    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 45));
      while (!fini()) {
        await tour();
        if (DateTime.now().isAfter(fin)) {
          fail('$quoi : pas de convergence. mère ${mm.collection(demandesImportCollection).toutes.map((x) => '${x['id']}:${x['etat']}')} ; F1 ${mf1.collection(demandesImportCollection).toutes.map((x) => '${x['id']}:${x['etat']}')} ; '
              'erreurs ${pm.erreur.value} ${pf1.erreur.value} ${svcM.derniereErreur} ; refus ${pm.motifsRefus} ${pf1.motifsRefus}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }

    final profilDaf = ProfilImport(role: 'da', libelleRole: 'DAF', droitEcran: (e) => donnees.matrice.droit('da', e));
    for (final (moteur, nom) in [(moteur1, 'F1'), (moteur2, 'F2')]) {
      final code = await console.codeAppareil(nom).timeout(const Duration(seconds: 20));
      await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
      moteur.demarrer();
    }
    await converger(() => mf1.collection('rbac').toutes.length == mm.collection('rbac').toutes.length && mf2.collection('rbac').toutes.length == mm.collection('rbac').toutes.length, 'configuration de départ');

    // 0. La garde joue : un agent d'un fileul n'écrit pas un prestataire à la main (seul l'import, qui lève la garde de SES cibles, passe).
    expect(() => mf1.collection('prestataires').inserer({'id': 'X', 'nom': 'Écrit à la main', 'specialite': 'Chirurgie', 'tarifActe': 1, 'statut': 'actif'}), throwsA(isA<EcritureRefusee>()),
        reason: 'réglé sur la mère : un fileul ne modifie pas un prestataire à l\'écran, il l\'importe');

    // 1. DIRECT ET DEMANDE.
    expect(svc1.passeParUneDemande(jeuPrestataires), isTrue);
    // AI (16/11/2026) : la demande porte le compte nominatif qui la signe ; la mère vérifie qu'il existe chez elle, avec ce rôle.
    signerAvec(mf1, mm, 'da', nom: 'LA DAF');
    final r1 = svc1.importerEtDemander(jeuPrestataires, verifier(mf1, ['Dr DEMANDE Alpha', 'Dr DEMANDE Bravo'], profilDaf), profil: profilDaf, nomAgent: 'LA DAF');
    expect(r1.resultat.ok, isTrue, reason: '${r1.resultat.code} ${r1.resultat.motif}');
    final locales = mf1.collection('prestataires').actives.where((f) => '${f['nom']}'.startsWith('Dr DEMANDE')).toList();
    expect(locales, hasLength(2), reason: 'visibles chez le fileul AVANT toute réponse de la mère');
    expect(locales.every((f) => f[champEnAttenteMere] == r1.demande && '${f['id']}'.startsWith('PRE-') && f['tarifActe'] == 25000), isTrue);
    final idsFileul = {for (final f in locales) f['id']};
    await converger(() => mf1.collection(demandesImportCollection).parId(r1.demande)?['etat'] == demandeImportAppliquee, 'verdict de la mère');
    final v1 = mf1.collection(demandesImportCollection).parId(r1.demande)!;
    final surMere = mm.collection('prestataires').actives.where((f) => f['lotImport'] == v1['resultatLot']).toList();
    expect({for (final f in surMere) f['nom']}, {'Dr DEMANDE Alpha', 'Dr DEMANDE Bravo'});
    expect({for (final f in surMere) f['id']}, idsFileul, reason: 'la mère écrit sous les MÊMES identifiants que le fileul');
    expect(surMere.every((f) => f['validePar'] == 'LA DAF' && f['tarifActe'] == 25000), isTrue, reason: 'au nom de l\'auteur (RG-12), tarif intact');

    // 2. LE SECOND FILEUL reçoit la liste par la configuration (la mère l'a publiée) : mêmes identifiants, même tarif, aucun marquage.
    await converger(() => mf2.collection('prestataires').toutes.where((f) => '${f['nom']}'.startsWith('Dr DEMANDE')).length == 2, 'F2 reçoit les prestataires');
    final chezF2 = mf2.collection('prestataires').toutes.where((f) => '${f['nom']}'.startsWith('Dr DEMANDE')).toList();
    expect({for (final f in chezF2) f['id']}, idsFileul);
    expect(chezF2.every((f) => f['tarifActe'] == 25000 && f[champEnAttenteMere] == null), isTrue);
    expect(() => mf2.collection('prestataires').mettreAJour('${chezF2.first['id']}', {'tarifActe': 99}), throwsA(isA<EcritureRefusee>()), reason: 'F2 reçoit, il n\'écrit pas à la main');

    // 3. REFUS NOMMÉ : la mère crée le même prestataire entre-temps ; F1 restitue (archivage, RG-14).
    final a2 = verifier(mf1, ['Dr DOUBLON'], profilDaf);
    mm.collection('prestataires').inserer({'id': 'PRE-AILLEURS', 'reference': 'PE-0900', 'nom': 'Dr DOUBLON', 'specialite': 'Chirurgie', 'tarifActe': 10000, 'actesRealises': 0, 'statut': 'actif'}, prefixe: 'PRE');
    final r2 = svc1.importerEtDemander(jeuPrestataires, a2, profil: profilDaf, nomAgent: 'LA DAF');
    expect(r2.resultat.ok, isTrue);
    await converger(() => mf1.collection(demandesImportCollection).parId(r2.demande)?['restitution'] == restitutionFaite, 'refus nommé puis restitution');
    expect(mf1.collection(demandesImportCollection).parId(r2.demande)!['resultatCode'], 'DOUBLON_MAGASIN');
    final idsLot = [for (final e in (r2.resultat.lot!['ecrits'] as List).cast<Map>()) e['id']];
    expect(mf1.collection('prestataires').actives.where((f) => idsLot.contains(f['id'])), isEmpty, reason: 'écriture du fileul restituée');
    expect(mf1.collection('prestataires').archivees.where((f) => idsLot.contains(f['id'])), hasLength(1), reason: 'archivée, jamais supprimée');

    // 4. JAMAIS vers un téléphone : la mère sert le journal à un fileul (qui le reçoit) et à un mobile (qui ne reçoit pas la rémunération).
    final http0 = HttpClient();
    addTearDown(() => http0.close(force: true));
    Future<Map<String, Object?>> appel(String methode, String chemin, {Map<String, Object?>? corps, Map<String, String> entetes = const {}}) async {
      final req = await http0.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
      req.headers.contentType = ContentType.json;
      entetes.forEach(req.headers.set);
      if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
      final rep = await req.close();
      return (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
    }

    Future<List<String>> recues(String role, Map<String, Object?> extra) async {
      final c = (await appel('POST', '/admin/code', corps: {'etiquette': role, 'role': role, ...extra}, entetes: {'x-admin': 'secret-test'}))['code'];
      final jetons = await appel('POST', '/appairage', corps: {'code': c, 'uuid': 'dev-$role', 'plateforme': 'test'});
      final noms = <String>[];
      var depuis = 0;
      while (true) {
        final pull = await appel('GET', '/sync/pull?depuis=$depuis&limite=500&epoch=${jetons['epoch']}', entetes: {'authorization': 'Bearer ${jetons['jeton']}'});
        if (pull['ops'] == null) fail('pull de $role à $depuis : $pull');
        final ops = (pull['ops'] as List).cast<Map>();
        for (final o in ops) {
          noms.add('${o['collection']}');
          depuis = (o['seq'] as num).toInt();
        }
        if (pull['fin'] == true || ops.isEmpty) break;
      }
      return noms;
    }

    expect(await recues('fileul', {}), contains('prestataires'), reason: 'un fileul reçoit les prestataires');
    final mobile = await recues('mobile', {'profil': 'soignant', 'fonction': 'infirmier'});
    expect(mobile, isNotEmpty, reason: 'le téléphone lit bien le journal : l\'absence des prestataires est une EXCLUSION, pas un journal vide');
    expect(mobile, isNot(contains('prestataires')), reason: 'la rémunération d\'un prestataire ne part jamais vers un téléphone (RG-13)');
    svcM.arreter();
  }, timeout: const Timeout(Duration(seconds: 240)));
}
