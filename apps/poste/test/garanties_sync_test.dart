import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/matrice_vive.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_demandes_import.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// T13, À TRAVERS LE VRAI POSTE : vraie mère Dart, vrai moteur de fileul, vrais ponts, vraie configuration diffusée.
///  - GARANTIES (configuration de la mère, famille R) : le fileul importe (écriture chez lui ET demande), la mère rejoue les contrôles sous le rôle de l'auteur, pose la version sous les MÊMES
///    identifiants, et la version remplacée reste écrite ; un fileul ne peut pas écrire une garantie à la main ; une version datée ne se réécrit pas à la mère ;
///  - COUVERTURES (famille A des fiches patient) : un jeu RESTREINT, direct seul — jamais de demande — mais la fiche écrite au fileul VOYAGE à la mère comme le dossier du patient ;
///  - ni les garanties ni les couvertures ne partent vers un téléphone.
final donnees = DonneesNavigation.depuisDossier();
const collections = ['rbac', 'modulesActifs', 'audit', 'rolesBase', 'utilisateurs', 'souscripteurs', 'assureurs', 'garanties', 'couverturesAssurance', 'patients', 'factures', 'notifications'];
Magasin poste() => Magasin.depuisDossier(collections);

List<List<Object?>> fichierGaranties(List<Map<String, Object?>> lignes) => [
      [for (final c in jeuGaranties.colonnes) c.label],
      for (final l in lignes) [for (final c in jeuGaranties.colonnes) l[c.cle] ?? ''],
    ];

void main() {
  test('BOUT EN BOUT, VRAIE MÈRE : garanties datées (direct et demande, mêmes identifiants, version remplacée gardée) ; couvertures (direct seul) qui voyagent comme les fiches patient ; rien vers un téléphone', () async {
    const port = 19613;
    final d = Directory.systemTemp.createTempSync('garanties-sync');
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
    mm.horloge = () => DateTime(2026, 11, 14);
    mf.horloge = () => DateTime(2026, 11, 14);
    mm.utilisateur = 'Poste mère';
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
    appl.demarrer(intervalle: const Duration(hours: 1));
    appl.arreter();
    TransportFileul tf() =>
        TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs), restaurerFiche: moteur.restaurer);
    // Le pont du fileul porte les demandes ET les couvertures : c'est ce que dit `collectionsActivite`, vérifié plus bas.
    final pm = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M', collections: {demandesImportCollection, 'couverturesAssurance', 'patients'});
    final pf = PontActivite(mf, tf(), etiquette: 'F1', collections: {demandesImportCollection, 'couverturesAssurance', 'patients'});

    Future<void> tour() async {
      await pub.pousser();
      await appl.tirer();
      await pf.cycle();
      await pm.cycle();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pub.pousser();
      await appl.tirer();
      await pf.cycle();
      svcF.reconcilierVerdicts();
    }

    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 60));
      while (!fini()) {
        await tour();
        if (DateTime.now().isAfter(fin)) {
          fail('$quoi : pas de convergence. mère ${mm.collection(demandesImportCollection).toutes.map((x) => '${x['id']}:${x['etat']}:${x['resultatCode']}')} ; fileul ${mf.collection(demandesImportCollection).toutes.map((x) => '${x['id']}:${x['etat']}')} ; '
              'erreurs ${pm.erreur.value} ${pf.erreur.value} ${svcM.derniereErreur} ; refus ${pm.motifsRefus} ${pf.motifsRefus}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }

    final profilDaf = ProfilImport(role: 'da', libelleRole: 'DAF', droitEcran: (e) => donnees.matrice.droit('da', e));
    final code = await console.codeAppareil('F1').timeout(const Duration(seconds: 20));
    await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
    moteur.demarrer();
    await converger(() => mf.collection('rbac').toutes.length == mm.collection('rbac').toutes.length && mf.collection('souscripteurs').toutes.length == mm.collection('souscripteurs').toutes.length, 'configuration de départ');

    final sous = mm.collection('souscripteurs').actives.first;
    final police = '${sous['police']}';
    Map<String, Object?> ligne(String date, num taux, num plafond) =>
        {'police': police, 'categorie': 'Consultations', 'garantie': 'Consultation généraliste', 'taux': taux, 'plafond': plafond, 'unite': 'par acte', 'dateEffet': date, 'motif': 'Avenant'};

    // 0. Un fileul n'écrit pas une garantie à la main : c'est de la configuration de la mère.
    expect(() => mf.collection('garanties').inserer({'id': 'X', 'souscripteurId': sous['id'], 'libelle': 'X', 'categorie': 'consultation', 'taux': 10, 'statut': 'actif'}), throwsA(isA<EcritureRefusee>()));

    // 1. GARANTIES : direct et demande.
    expect(svcF.passeParUneDemande(jeuGaranties), isTrue);
    PortImportMemoire memoire(Magasin m) => PortImportMemoire({
          for (final c in ['souscripteurs', 'garanties', 'factures', 'patients', 'couverturesAssurance']) c: m.collection(c).toutes
        }, profilFixe: profilDaf, utilisateurFixe: 'LA DAF');
    AnalyseImport verifier(List<Map<String, Object?>> lignes) {
      final a = analyserLignes(jeuGaranties, fichierGaranties(lignes), 'garanties.xlsx', memoire(mf));
      expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code}:${p.motif}']}');
      return a;
    }

    final r1 = svcF.importerEtDemander(jeuGaranties, verifier([ligne('2027-01-01', 80, 5000)]), profil: profilDaf, nomAgent: 'LA DAF');
    expect(r1.resultat.ok, isTrue, reason: '${r1.resultat.code} ${r1.resultat.motif}');
    final locales = mf.collection('garanties').actives.where((g) => g[champEnAttenteMere] == r1.demande).toList();
    expect(locales, hasLength(1), reason: 'visible chez le fileul AVANT toute réponse de la mère');
    await converger(() => mf.collection(demandesImportCollection).parId(r1.demande)?['etat'] == demandeImportAppliquee, 'verdict de la mère (v1)');
    final surMere = mm.collection('garanties').actives.where((g) => g['souscripteurId'] == sous['id']).toList();
    expect(surMere, hasLength(1));
    expect(surMere.single['id'], locales.single['id'], reason: 'les MÊMES identifiants chez la mère et chez le fileul');
    expect(surMere.single['version'], 1);
    expect(surMere.single['dateEffet'], '2027-01-01');
    expect(surMere.single['validePar'], 'LA DAF');

    // 2. La version suivante : la mère pose la v2, la v1 reste écrite ; la lecture à la date de la pièce lit chacune.
    final r2 = svcF.importerEtDemander(jeuGaranties, verifier([ligne('2027-06-01', 60, 4000)]), profil: profilDaf, nomAgent: 'LA DAF');
    expect(r2.resultat.ok, isTrue, reason: '${r2.resultat.code} ${r2.resultat.motif}');
    await converger(() => mf.collection(demandesImportCollection).parId(r2.demande)?['etat'] == demandeImportAppliquee, 'verdict de la mère (v2)');
    final versions = assVersionsGarantie(mm.collection('garanties').actives, sous['id'], 'consultation', 'Consultation généraliste');
    expect(versions.map((g) => g['version']), [1, 2]);
    expect(versions.first['taux'], 80, reason: 'la v1 reste écrite');
    expect(garantiesEnVigueur(versions, '2027-03-01').single['taux'], 80);
    expect(garantiesEnVigueur(versions, '2027-06-01').single['taux'], 60);
    await converger(() => mf.collection('garanties').actives.where((g) => g['souscripteurId'] == sous['id'] && g['version'] == 2).isNotEmpty && mf.collection(demandesImportCollection).parId(r2.demande)?['marquageLeve'] == true, 'le fileul reçoit la v2');

    // 2b. DÉCISION DU 16/11/2026 : une seconde saisie à la MÊME date d'effet est une correction de la première. La mère la pose (v3, `corrige` = la v2), la v2 reste écrite telle quelle, et
    // la lecture à cette date — chez la mère comme chez le fileul — rend la DERNIÈRE ligne saisie. (Avant la décision : refus `VERSION_MEME_DATE`.)
    final r3 = svcF.importerEtDemander(jeuGaranties, verifier([ligne('2027-06-01', 55, 3500)]), profil: profilDaf, nomAgent: 'LA DAF');
    expect(r3.resultat.ok, isTrue, reason: '${r3.resultat.code} ${r3.resultat.motif}');
    await converger(() => mf.collection(demandesImportCollection).parId(r3.demande)?['etat'] == demandeImportAppliquee, 'verdict de la mère (correction à la même date)');
    final apresCorrection = assVersionsGarantie(mm.collection('garanties').actives, sous['id'], 'consultation', 'Consultation généraliste');
    expect(apresCorrection.map((g) => g['version']), [1, 2, 3]);
    expect(apresCorrection[1]['taux'], 60, reason: 'la version corrigée reste écrite telle quelle');
    expect(apresCorrection[2]['corrige'], apresCorrection[1]['id']);
    expect(garantiesEnVigueur(apresCorrection, '2027-06-01').single['taux'], 55, reason: 'à date égale, la dernière saisie l’emporte (mère)');
    expect(garantiesEnVigueur(apresCorrection, '2027-03-01').single['taux'], 80, reason: 'la v1 reste lue avant la date');
    await converger(() => mf.collection('garanties').actives.where((g) => g['souscripteurId'] == sous['id'] && g['version'] == 3).isNotEmpty, 'le fileul reçoit la correction');
    final cheFileul = assVersionsGarantie(mf.collection('garanties').actives, sous['id'], 'consultation', 'Consultation généraliste');
    expect(garantiesEnVigueur(cheFileul, '2027-06-01').single['taux'], 55, reason: 'à date égale, la dernière saisie l’emporte (fileul : même lecture, mêmes identifiants)');
    // Le même jour qu'une pièce émise sous la grille : le refus nommé reste (on ne réécrit jamais la garantie sous laquelle une pièce a été émise) — éprouvé au domaine (`FACTURE_DEJA_EMISE`).

    // 3. Une version datée ne se réécrit pas, même à la mère.
    expect(() => mm.collection('garanties').mettreAJour(versions.first['id'], {'taux': 10}), throwsA(isA<EcritureRefusee>()));

    // 4. COUVERTURES : jeu restreint, direct seul ; la fiche voyage avec la famille des fiches patient.
    expect(svcF.passeParUneDemande(jeuCouverturesAssurance), isFalse);
    expect(collectionsActivite, contains('couverturesAssurance'), reason: 'le pont par défaut du poste porte la couverture, comme les fiches patient');
    final pat = mm.collection('patients').actives.firstWhere((p) => p['assureur'] == null || '${p['assureur']}'.isEmpty);
    await converger(() => mf.collection('patients').parId(pat['id']) != null, 'le patient arrive au fileul');
    final ass = mm.collection('assureurs').actives.first;
    final souscrip = mm.collection('souscripteurs').actives.firstWhere((s) => s['assureur'] == ass['code']);
    final cv = [
      [for (final c in jeuCouverturesAssurance.colonnes) c.label],
      [for (final c in jeuCouverturesAssurance.colonnes) {'patient': pat['code'], 'assureur': ass['code'], 'police': souscrip['police'], 'dateEffet': '2026-12-01', 'motif': 'Changement d’employeur', 'carteExpiration': '2027-12-31', 'taux': 70}[c.cle] ?? '']
    ];
    final pFileul = PortMagasin(mf, aujourdhui: () => DateTime(2026, 11, 14), nomAgent: 'LA DAF', profil: profilDaf, gardesLevees: false, etiquette: 'F1');
    final a = analyserLignes(jeuCouverturesAssurance, cv, 'c.xlsx', pFileul);
    expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code}:${p.motif}']}');
    final ap = appliquer(jeuCouverturesAssurance, a, pFileul);
    expect(ap.ok, isTrue, reason: '${ap.code} ${ap.motif}');
    expect(mf.collection('couverturesAssurance').actives, isNotEmpty);
    await converger(() => mm.collection('couverturesAssurance').actives.where((c) => c['patientId'] == pat['id']).isNotEmpty, 'la couverture du fileul arrive à la mère');
    final cMere = mm.collection('couverturesAssurance').actives.where((c) => c['patientId'] == pat['id']).toList();
    expect(cMere.any((c) => c['debut'] == '2026-12-01' && c['souscripteurId'] == souscrip['id']), isTrue);
    expect(mm.collection(demandesImportCollection).toutes.where((x) => x['jeu'] == 'couvertures-assurance'), isEmpty, reason: 'aucune demande : les lignes du fichier ne voyagent jamais');

    // 5. Rien vers un téléphone : ni garanties ni couvertures dans le journal servi à un mobile (alors que le fileul les reçoit).
    final http0 = HttpClient();
    try {
      Future<Map<String, Object?>> appel(String methode, String chemin, {Map<String, Object?>? corps, Map<String, String> entetes = const {}}) async {
        final req = await http0.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
        req.headers.contentType = ContentType.json;
        entetes.forEach(req.headers.set);
        if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
        final rep = await req.close();
        return (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
      }

      Future<Set<String>> recues(String role, Map<String, Object?> extra) async {
        final c = (await appel('POST', '/admin/code', corps: {'etiquette': role, 'role': role, ...extra}, entetes: {'x-admin': 'secret-test'}))['code'];
        final jetons = await appel('POST', '/appairage', corps: {'code': c, 'uuid': 'dev-$role', 'plateforme': 'test'});
        final noms = <String>{};
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

      final fileulOps = await recues('fileul', {});
      expect(fileulOps, containsAll(['garanties', 'couverturesAssurance']), reason: 'un fileul reçoit les deux');
      final mobileOps = await recues('mobile', {'profil': 'soignant', 'fonction': 'infirmier'});
      expect(mobileOps, isNotEmpty, reason: 'le téléphone lit bien le journal : l\'absence est une EXCLUSION, pas un journal vide');
      expect(mobileOps, isNot(contains('garanties')), reason: 'les taux conventionnés ne partent jamais vers un téléphone');
      expect(mobileOps, isNot(contains('couverturesAssurance')), reason: 'quelle compagnie couvre quel patient : donnée nominative (RG-13)');
    } finally {
      http0.close(force: true);
      svcM.arreter();
      appl.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 300)));
}
