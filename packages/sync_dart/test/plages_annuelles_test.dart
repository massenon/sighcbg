import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart' show codePatient;
import 'package:sigh_sync/src/commun.dart' show Err;
import 'package:sigh_sync/src/depot.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:test/test.dart';

/// PLAGES PAR SÉRIE ET PAR ANNÉE (Direction de Baguidi, 17/11/2026, reliquats de numérotation) : la mère alloue à chaque fileul sa plage ANNUELLE, refuse en le nommant toute plage qui en chevauche
/// une autre de la même série et de la même année, reprend au plus grand rang + 1 ; les plages de dossiers d'avant les séries annuelles sont rattachées à l'année de leurs codes DÉJÀ attribués.
void main() {
  Future<Mere> mere() => Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:'));

  test('une série nommée demande sa plage POUR UNE ANNÉE : un carnet par nom et par année, chaque fileul a la sienne, la série repart à 1 l\'année suivante', () async {
    final m = await mere();
    final a = await m.allouerPlage('F1', 'besoins', 50, 0, annee: 2026);
    final b = await m.allouerPlage('F2', 'besoins', 50, 0, annee: 2026);
    final c = await m.allouerPlage('F1', 'besoins', 50, 0, annee: 2027);
    expect(a, {'debut': 1, 'fin': 50, 'annee': 2026});
    expect(b, {'debut': 51, 'fin': 100, 'annee': 2026}, reason: 'chaque fileul reçoit la sienne, à la suite');
    expect(c, {'debut': 1, 'fin': 50, 'annee': 2027}, reason: 'la série annuelle repart à 1');
    expect((await m.base.select("SELECT annee FROM plages WHERE nom='besoins' AND appareil='F2'")).single['annee'], 2026);
    await m.base.fermer();
  });

  test('sans année demandée, la règle d\'avant reste valable pour une série qui ne se remet pas à 1 (plage sans année)', () async {
    final m = await mere();
    final a = await m.allouerPlage('F1', 'transferts', 10, 0);
    final b = await m.allouerPlage('F2', 'transferts', 10, 0);
    expect([a, b], [{'debut': 1, 'fin': 10}, {'debut': 11, 'fin': 20}]);
    await m.base.fermer();
  });

  test('la reprise se fait au plus grand rang + 1, jamais sous le minimum que le poste connaît', () async {
    final m = await mere();
    await m.allouerPlage('F1', 'commandes', 50, 0, annee: 2026);
    final reprise = await m.allouerPlage('F1', 'commandes', 50, 120, annee: 2026);
    expect(reprise['debut'], 120, reason: 'le poste connaît déjà des rangs jusqu\'à 119');
    final suite = await m.allouerPlage('F2', 'commandes', 5, 0, annee: 2026);
    expect(suite['debut'], 170);
    await m.base.fermer();
  });

  test('un chevauchement est REFUSÉ en nommant la plage et le poste (compteur remis en arrière par une restauration), rien n\'est alloué', () async {
    final m = await mere();
    await m.allouerPlage('F1', 'besoins', 50, 0, annee: 2026);
    // Une restauration de base ramène le compteur en arrière : sans le contrôle, F2 recevrait 1 à 50, déjà détenus par F1.
    await m.base.poserMeta('next_plage_besoins_2026', 1);
    final avant = (await m.base.select('SELECT COUNT(*) AS n FROM plages')).single['n'];
    Err? refus;
    try {
      await m.allouerPlage('F2', 'besoins', 50, 0, annee: 2026);
    } on Err catch (e) {
      refus = e;
    }
    expect(refus, isNotNull);
    expect(refus!.statut, 409);
    expect(refus.code, 'plage_chevauchement');
    expect(refus.motif, allOf(contains('1 à 50'), contains('F1')));
    expect(refus.corps['geste'], contains('51'), reason: 'le geste dit où reprendre : plus grand rang + 1');
    expect((await m.base.select('SELECT COUNT(*) AS n FROM plages')).single['n'], avant, reason: 'rien n\'est alloué');
    // Les dossiers : même contrôle.
    final an = DateTime.now().year; // la série de l'année en cours d'une base neuve ouvre à 1000 : F1 détient 1000 à 1049
    await m.allouerPlage('F1', 'patients', 50, 0, annee: an);
    await m.base.poserMeta(Mere.cleSeriePatients(an), 1010);
    await expectLater(() => m.allouerPlage('F2', 'patients', 5, 0, annee: an), throwsA(isA<Err>().having((e) => e.code, 'code', 'plage_chevauchement')));
    await m.base.fermer();
  });

  test('MIGRATION : une plage de dossiers sans année est rattachée à l\'année de ses codes déjà attribués ; sans code attribué, à l\'année courante comme avant ; aucun code réécrit', () async {
    final dir = await Directory.systemTemp.createTemp('sigh-plages-');
    final chemin = '${dir.path}/mere.sqlite';
    try {
      final an = DateTime.now().year;
      final d = await Depot.ouvrir(chemin, '');
      await d.initialiser('CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT); CREATE TABLE IF NOT EXISTS plages (appareil TEXT, nom TEXT, debut BIGINT, fin BIGINT);'
          ' CREATE TABLE IF NOT EXISTS fiches (collection TEXT, id TEXT, data TEXT)');
      await d.poserMeta('next_patient', 3100);
      await d.exec('INSERT INTO plages(appareil,nom,debut,fin) VALUES(?,?,?,?)', ['F1', 'patients', 1000, 1049]);
      await d.exec('INSERT INTO plages(appareil,nom,debut,fin) VALUES(?,?,?,?)', ['F2', 'patients', 3000, 3049]);
      await d.exec('INSERT INTO fiches(collection,id,data) VALUES(?,?,?)', ['patients', 'P1', '{"code":"${codePatient(1004, an - 1)}"}']);
      await d.fermer();
      final m = await Mere.creer(ConfigMere(port: 0, dbChemin: chemin));
      final lignes = await m.base.select("SELECT appareil, annee FROM plages WHERE nom='patients' ORDER BY debut");
      expect(lignes.map((r) => [r['appareil'], r['annee']]).toList(), [['F1', an - 1], ['F2', an]], reason: 'la plage dont un code est attribué prend l\'année de ce code ; l\'autre, l\'année courante');
      expect((await m.base.select("SELECT ${m.base.champJson('data', 'code')} AS c FROM fiches WHERE id='P1'")).single['c'], codePatient(1004, an - 1), reason: 'aucun code réécrit');
      await m.base.fermer();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
