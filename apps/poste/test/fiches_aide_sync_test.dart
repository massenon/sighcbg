import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;
import 'package:sigh_sync/sigh_sync.dart';
// ignore: implementation_imports
import 'package:sigh_sync/src/mere.dart' show Appareil, familles, collectionsDocumentsJamaisMobile;

/// LES FICHES D'AIDE ET LA LIASSE FISCALE À TRAVERS LES POSTES (Direction de Baguidi, 17/11/2026) :
///  * `fichesAide` voyage (famille A, mère Dart et banc Node), écrite depuis n'importe quel poste ; la VALIDATION ne s'écrit que sur la mère et une fiche validée ne se réécrit pas ;
///  * `documentsFiscaux` est un référentiel de la mère (famille R) : elle le publie, un fileul le reçoit et ne l'écrit pas ;
///  * ni l'une ni l'autre ne part vers un téléphone.
/// Contre la VRAIE mère Dart : chaque refus est réel. Données fictives.
typedef M = Map<String, Object?>;

class _Liaison {
  _Liaison(this.mere);
  final Mere mere;
  int n = 0;
}

class _Transport implements TransportPont {
  _Transport(this.l, this.app);
  final _Liaison l;
  final Appareil app;
  final refus = <String>[];
  @override
  Future<List<PieceSync>> liste(String c) async {
    final rows = await l.mere.base.select('SELECT id,data,archive FROM fiches WHERE collection=?', [c]);
    return [for (final r in rows) PieceSync('${r['id']}', (jsonDecode(r['data'] as String) as Map).cast<String, Object?>(), archive: (r['archive'] as int) != 0)];
  }

  @override
  Future<void> ecrire(String c, String fiche, {required bool existe, required Map<String, Object?> champs}) async {
    final f = await l.mere.lire(c, fiche);
    final vu = <String, Object?>{for (final k in champs.keys) if (f != null && f.fieldseq[k] != null) k: f.fieldseq[k]};
    final r = await l.mere.traiter({'id': 'op${l.n++}', 'type': existe ? 'modifier' : 'creer', 'collection': c, 'fiche': fiche, 'champs': jsonDecode(jsonEncode(champs)), 'hlc': 1000 + l.n, 'vu': vu}, app);
    if (r['statut'] == 'refusee') {
      refus.add('${r['code']}');
      throw StateError('${r['code']} : ${r['motif']}');
    }
  }

  @override
  Future<void> restaurer(String collection, String fiche) async => throw StateError('non porté');
}

void main() {
  final auj = DateTime(2026, 11, 17, 9);
  const fiche = {
    'type': 'aide',
    'statut': 'proposee',
    'titre': 'Enregistrer un courrier entrant',
    'motsCles': ['courrier entrant'],
    'roles': <String>[],
    'ecrans': <String>[],
    'etapes': ['Ouvrir l’écran', 'Choisir « arrivée »'],
    'auteurId': 'U-F1',
    'auteurNom': 'Auteur Fictif',
  };

  test('déclarations : famille A (fiches d’aide) et R (liasse) à la mère Dart et au banc Node, pont du poste, jamais vers un téléphone', () {
    expect(familles[colFichesAide], 'A');
    expect(familles[colDocumentsFiscaux], 'R');
    expect(collectionsActivite, contains(colFichesAide));
    expect(collectionsConfiguration(), contains(colDocumentsFiscaux), reason: 'la mère publie la liasse, les fileuls la reçoivent');
    expect(collectionsConfiguration(), isNot(contains(colFichesAide)), reason: 'les fiches d’aide ne sont pas de la configuration conservée : elles voyagent comme des fiches descriptives');
    expect(collectionsDocumentsJamaisMobile, containsAll([colFichesAide, colDocumentsFiscaux]));
    final dart = File('../../packages/sync_dart/lib/src/mere.dart').readAsStringSync();
    expect(dart, contains('...collectionsDocumentsJamaisMobile'));
    expect(dart, contains('refusEcritureFicheAide('), reason: 'la mère refait le contrôle');
    final js = File('../../packages/sync/banc/mere.js').readAsStringSync();
    expect(js, contains("fichesAide: 'A'"));
    expect(js, contains("documentsFiscaux: 'R'"));
    final jamais = RegExp(r'const MOBILE_JAMAIS = \[([^\]]*)\]').firstMatch(js)!.group(1)!;
    for (final c in [colFichesAide, colDocumentsFiscaux]) {
      expect(jamais, contains("'$c'"));
    }
    for (final code in ['validation_reservee_mere', 'fiche_validee']) {
      expect(js, contains(code), reason: 'miroir du refus dans le banc Node');
    }
  });

  test('la VRAIE mère Dart : un fileul écrit une fiche proposée mais ne la valide pas ni ne réécrit une fiche validée ; la mère valide ; l’archivage reste permis ; la liasse est à la mère seule', () async {
    final d = Directory.systemTemp.createTempSync('fai-mere');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere = await Mere.creer(ConfigMere(port: 19598, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes'));
    var n = 0;
    // `vu` : ce que l'appareil sait de la fiche (comme le transport d'un pont) ; un `vu` vide ferait de chaque correction un conflit de champ, non un refus.
    Future<Map<String, Object?>> op(Appareil a, String type, String c, String id, Map<String, Object?> champs) async {
      final f = await mere.lire(c, id);
      final vu = <String, Object?>{for (final k in champs.keys) if (f != null && f.fieldseq[k] != null) k: f.fieldseq[k]};
      return mere.traiter({'id': 'op${n++}', 'type': type, 'collection': c, 'fiche': id, 'champs': champs, 'hlc': 1000 + n, 'vu': vu}, a);
    }
    String? code(Map<String, Object?> r) => r['statut'] == 'refusee' ? '${r['code']}' : null;
    final fileul = Appareil('F1', 'fileul'), laMere = Appareil('mere', 'mere'), mobile = Appareil('T1', 'mobile', 'soignant', 'infirmier');

    expect(code(await op(fileul, 'creer', colFichesAide, 'FA1', fiche)), isNull, reason: 'une fiche proposée s’écrit depuis un fileul');
    expect((await mere.lire(colFichesAide, 'FA1'))!.data['titre'], fiche['titre']);
    expect(code(await op(fileul, 'creer', colFichesAide, 'FA2', {...fiche, 'statut': 'validee', 'validePar': 'Moi'})), 'validation_reservee_mere');
    expect(await mere.lire(colFichesAide, 'FA2'), isNull, reason: 'rien n’est écrit');
    expect(code(await op(fileul, 'modifier', colFichesAide, 'FA1', {'statut': 'validee', 'valideLe': '2026-11-17', 'validePar': 'Moi'})), 'validation_reservee_mere');
    expect(code(await op(fileul, 'modifier', colFichesAide, 'FA1', {'professionnel': 'Dr X', 'professionnelLe': '2026-11-16'})), 'validation_reservee_mere');
    expect((await mere.lire(colFichesAide, 'FA1'))!.data['statut'], 'proposee');
    expect(code(await op(fileul, 'modifier', colFichesAide, 'FA1', {'titre': 'Titre corrigé'})), isNull, reason: 'une fiche non validée se corrige depuis un fileul');

    expect(code(await op(laMere, 'modifier', colFichesAide, 'FA1', {'statut': 'validee', 'validateurId': 'U-M', 'validePar': 'Valideur Fictif', 'valideLe': '2026-11-17'})), isNull, reason: 'la validation est écrite par la mère');
    expect(code(await op(fileul, 'modifier', colFichesAide, 'FA1', {'etapes': ['Autre']})), 'fiche_validee');
    expect(code(await op(fileul, 'modifier', colFichesAide, 'FA1', {'titre': 'Encore'})), 'fiche_validee');
    expect((await mere.lire(colFichesAide, 'FA1'))!.data['etapes'], fiche['etapes']);
    expect(code(await op(fileul, 'modifier', colFichesAide, 'FA1', {'statut': 'archive', 'archivePar': 'Archiviste', 'motifArchivage': 'Procédure changée'})), isNull, reason: 'archiver reste permis (RG-14)');
    expect((await mere.lire(colFichesAide, 'FA1'))!.data['statut'], 'archive');
    // Un téléphone n'écrit déjà pas cette collection (sa liste d'écriture est celle de son profil) ; si l'écriture arrivait jusqu'ici, la validation lui serait refusée comme à un fileul.
    expect(code(await op(mobile, 'creer', colFichesAide, 'FA3', {...fiche, 'statut': 'validee', 'validePar': 'Moi'})), 'validation_reservee_mere');

    // La liasse : référentiel de la mère seule.
    final liasse = {'genre': 'liasse', 'exercice': 2025, 'dateEffet': '2026-04-30', 'source': 'Remise à la DGI', 'importePar': 'Comptable Fictif', 'contenu': {'DEPOT': {}}};
    expect(code(await op(fileul, 'creer', colDocumentsFiscaux, 'doc1', liasse)), 'droit_refuse');
    expect(code(await op(laMere, 'creer', colDocumentsFiscaux, 'doc1', liasse)), isNull);
    expect(code(await op(fileul, 'modifier', colDocumentsFiscaux, 'doc1', {'source': 'Autre'})), 'droit_refuse');
  });

  test('deux fileuls et la mère : la fiche écrite sur un fileul arrive à tous ; la validation de la mère revient aux fileuls ; le fileul ne la réécrit pas ; aucune fiche ne se perd', () async {
    final d = Directory.systemTemp.createTempSync('fai-pont');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere = await Mere.creer(ConfigMere(port: 19599, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes'));
    final liaison = _Liaison(mere);
    Magasin poste() => Magasin({colFichesAide: <M>[], 'audit': <M>[]}, 'POSTE')..horloge = () => auj;
    final f1 = poste(), f2 = poste(), mm = poste();
    final t1 = _Transport(liaison, Appareil('F1', 'fileul')), t2 = _Transport(liaison, Appareil('F2', 'fileul')), tm = _Transport(liaison, Appareil('mere', 'mere'));
    final p1 = PontActivite(f1, t1, etiquette: 'F1', enLectureSeule: collectionsDeLaMereSeule, reservesAuMere: true);
    final p2 = PontActivite(f2, t2, etiquette: 'F2', enLectureSeule: collectionsDeLaMereSeule, reservesAuMere: true);
    final pm = PontActivite(mm, tm, etiquette: 'M');
    Future<void> tour() async {
      for (var i = 0; i < 3; i++) {
        for (final p in [p1, p2, pm]) {
          await p.cycle();
        }
      }
    }

    // L'identifiant est attribué par la collection du poste, préfixé de son étiquette.
    f1.etiquettePoste = 'F1';
    final id = '${f1.collection(colFichesAide).inserer({...fiche}, prefixe: 'FAI').fiche['id']}';
    expect(id, startsWith('F1-FAI'));
    await tour();
    expect(mm.collection(colFichesAide).parId(id)!['titre'], fiche['titre']);
    expect(f2.collection(colFichesAide).parId(id)!['titre'], fiche['titre']);

    // La mère valide : la validation revient aux deux fileuls.
    mm.collection(colFichesAide).mettreAJour(id, {'statut': 'validee', 'validateurId': 'U-M', 'validePar': 'Valideur Fictif', 'valideLe': '2026-11-17'}, journaliser: false);
    await tour();
    for (final m in [f1, f2]) {
      final v = m.collection(colFichesAide).parId(id)!;
      expect([v['statut'], v['validePar'], v['valideLe']], ['validee', 'Valideur Fictif', '2026-11-17']);
      expect(ficheAideCitable(v), isTrue);
    }

    // Un fileul qui réécrit la fiche validée est refusé par la mère : son texte reste celui que la Direction a relu.
    f2.collection(colFichesAide).mettreAJour(id, {'titre': 'Titre réécrit'}, journaliser: false);
    await tour();
    expect(t2.refus, contains('fiche_validee'));
    expect(mm.collection(colFichesAide).parId(id)!['titre'], fiche['titre']);
  });

  test('la liasse importée sur la mère est PUBLIÉE (un tour) et REÇUE par le fileul, qui la lit comme la mère et ne peut pas l’écrire', () async {
    final liasse = {
      'id': 'doc-fiscal-liasse-2025-2026-04-30',
      'statut': 'actif',
      'genre': docFiscalLiasse,
      'exercice': 2025,
      'dateEffet': '2026-04-30',
      'source': 'Remise à la DGI',
      'importeLe': '2026-11-17T09:00:00Z',
      'importePar': 'Comptable Fictif',
      'contenu': {'DEPOT': {'exerciceN': 2025}, 'BILAN_ACTIF': []},
    };
    final mm = Magasin({colDocumentsFiscaux: [liasse], 'audit': <M>[]});
    final envoye = <String, M>{};
    final pub = PublicateurConfiguration(mm, (c, f, champs) async => envoye['$c/$f'] = champs, delai: Duration.zero);
    expect(await pub.pousser(), 1);
    expect(envoye.keys, contains('$colDocumentsFiscaux/${liasse['id']}'), reason: 'la mère publie la liasse');

    // Le fileul : un autre magasin, qui reçoit ce que la mère a publié.
    final mf = Magasin({colDocumentsFiscaux: <M>[], 'audit': <M>[]});
    final appl = ApplicateurConfiguration(mf, (c) async => [for (final e in envoye.entries) if (e.key.startsWith('$c/')) PieceSync(e.key.substring(c.length + 1), e.value)])..poserGardes();
    expect(await appl.tirer(), greaterThanOrEqualTo(1));
    // La même lecture que la mère : le registre branché sur le magasin du fileul rend la liasse, avec sa provenance.
    final f = versionsFiscales(mf.collection(colDocumentsFiscaux).toutes, docFiscalLiasse).single;
    expect(f.etat, versionFiscaleEnForce);
    expect(f.fiche['source'], 'Remise à la DGI');
    expect(f.fiche['importePar'], 'Comptable Fictif');
    DocumentsFiscaux.brancher(() => mf.collection(colDocumentsFiscaux).toutes);
    addTearDown(DocumentsFiscaux.debrancher);
    expect(DocumentsFiscaux.provenanceLiasse!['dateDepot'], '2026-04-30');
    // Un fileul n'écrit pas la liasse : la garde « réglé sur la mère » refuse, en disant pourquoi.
    expect(() => mf.collection(colDocumentsFiscaux).inserer({'id': 'doc-x', 'genre': docFiscalLiasse}), throwsA(isA<EcritureRefusee>()));
  });
}
