import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/documents/ocr_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';

import 'aide_grand_stock.dart';

/// LE TEXTE LU ET SA CORRECTION SIGNÉE, LE RÉGLAGE DE LA LECTURE, PAR LA SYNCHRONISATION, CONTRE LA VRAIE MÈRE DART (lots OCR-prep et OCR-C) : de vrais moteurs de fileul, de vrais ponts d'activité,
/// la vraie configuration diffusée. Le moteur de lecture est FACTICE : ce qui est éprouvé, c'est tout ce qui l'entoure.
///  1. une lecture écrite par un poste ARRIVE chez l'autre par le journal : lue « par machine, à vérifier », sans relecture ;
///  2. deux postes qui lisent le MÊME scan avec le même moteur avant de se parler ne font qu'UNE version à la mère, sans refus ;
///  3. une CORRECTION signée arrive partout en version de plus ; le texte machine reste intact ; la version courante est la même sur tous les postes ;
///  4. une version ne se MODIFIE jamais : modifier la correction à la mère est refusé (journal_immuable) et le pont n'y renvoie rien ;
///  5. le RÉGLAGE décidé à la mère descend aux fileuls ; un fileul qui tente de l'écrire est refusé (à son poste et par la mère) ;
///  6. la FILE reste locale ; JAMAIS vers un téléphone (ni lecture, ni correction, ni réglage).
const texteA = 'Hyperglycémie sévère : père déjà traité à Parakou';
final sha = docSha256([1, 2, 3, 4, 5, 6, 7, 8]);
final t0 = DateTime.utc(2026, 11, 14, 8);

OcrPoste lecteur(Magasin m, {bool mere = false, String moteur = 'factice', String texte = texteA}) {
  final o = OcrPoste(m, estMere: () => mere)
    ..automatique = false
    ..installer();
  o.enregistrer(MoteurOcrFactice(id: moteur, texteParDefaut: texte));
  return o;
}

FicheDoc uneLecture({String moteur = 'factice', String texte = texteA, DateTime? le}) => ocrNouvelleLecture(
    sha: sha, texte: texte, moteur: moteur, moteurVersion: '0.1', langue: 'fra', ocrLe: (le ?? t0).toIso8601String(), ocrPar: 'Agent', declencheur: 'automatique', pages: 1, dureeMs: 5);

Future<Map<String, Object?>> admin(Clinique c, String chemin) async {
  final r = await http.get(Uri.parse('http://127.0.0.1:${c.port}$chemin'), headers: {'x-admin': 'secret-test'});
  final j = jsonDecode(r.body);
  return j is Map ? j.cast<String, Object?>() : {'liste': j};
}

Future<int> compteMere(Clinique c, String collection) async => ((await admin(c, '/admin/compte?collection=$collection'))['n'] as num).toInt();

Future<void> tours(Clinique c, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await c.tour();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  test('1 et 3. une lecture écrite par F1 arrive chez F2 ; la correction signée de F2 arrive chez F1 et à la mère : le texte machine reste, la version courante est la même partout', () async {
    final c = Clinique(9771, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'AGENT UN');
      final f2 = await c.fileul('F2', 'stock', 'AGENT DEUX');
      final o1 = lecteur(f1.m), o2 = lecteur(f2.m);
      f1.m.collection(ocrLectures).inserer(uneLecture(), prefixe: 'OCR');
      final idMachine = uneLecture()['id'];
      await c.converger(() => f2.m.collection(ocrLectures).toutes.isNotEmpty, 'la lecture arrive chez F2');
      final e = o2.etatDe({'sha256': sha});
      expect(e.etat, EtatIndexation.ocrIndexe, reason: 'F2 lit « lu par machine, à vérifier » sans relire');
      expect(e.marque, isTrue);
      expect(o2.balayer(), 0);
      expect(o2.texteOcr(sha, famille: docFamilleCourrier, peutCategorie: null), contains('hyperglycemie'));
      // la correction de F2
      f2.m.utilisateur = 'Awa Agoro';
      f2.m.horloge = () => t0.add(const Duration(hours: 1));
      final r = o2.corriger(scan: {'sha256': sha}, texte: 'Hyperglycémie sévère : père déjà traité à Parakou (dossier relu)', famille: docFamilleCourrier, peutEditer: true, motif: 'relu avec le dossier papier');
      expect(r.ok, isTrue, reason: '${r.refus}');
      await c.converger(() => f1.m.collection(ocrLectures).toutes.length == 2 && c.mm.collection(ocrLectures).toutes.length == 2, 'la correction arrive chez F1 et à la mère');
      for (final (nom, m) in [('F1', f1.m), ('mère', c.mm), ('F2', f2.m)]) {
        final versions = ocrVersionsOrdonnees(m.collection(ocrLectures).toutes);
        expect(versions, hasLength(2), reason: nom);
        expect(versions.firstWhere((v) => v['id'] == idMachine)['texteBrut'], texteA, reason: '$nom : le texte machine est intact');
        final courante = ocrVersionCourante(versions)!;
        expect(courante['texteSource'], 'humain', reason: nom);
        expect(courante['corrigePar'], 'Awa Agoro', reason: nom);
        expect(ocrSignatureValide(courante), isTrue, reason: '$nom : la signature survit au voyage');
        expect(courante['id'], r.version, reason: '$nom : la même version courante partout');
      }
      expect(o1.etatDe({'sha256': sha}).libelle, 'Texte corrigé par Awa Agoro');
      expect(f1.pont.motifsRefus, isEmpty);
      expect(f2.pont.motifsRefus, isEmpty);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('2. deux postes qui lisent le MÊME scan avec le même moteur avant de se parler ne font qu’UNE version à la mère, sans refus', () async {
    final c = Clinique(9772, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'AGENT UN');
      final f2 = await c.fileul('F2', 'stock', 'AGENT DEUX');
      f1.m.collection(ocrLectures).inserer(uneLecture(le: t0), prefixe: 'OCR');
      f2.m.collection(ocrLectures).inserer(uneLecture(le: t0.add(const Duration(seconds: 5))), prefixe: 'OCR');
      expect(f1.m.collection(ocrLectures).toutes.single['id'], f2.m.collection(ocrLectures).toutes.single['id'], reason: 'identifiant déterministe');
      await tours(c);
      expect(await compteMere(c, ocrLectures), 1, reason: 'la seconde création est acceptée SANS EFFET : une fiche à la mère');
      expect(f1.m.collection(ocrLectures).toutes, hasLength(1));
      expect(f2.m.collection(ocrLectures).toutes, hasLength(1));
      expect(f1.pont.motifsRefus, isEmpty);
      expect(f2.pont.motifsRefus, isEmpty);
      expect(f1.pont.erreur.value, isNull);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('4. une version ne se modifie jamais : la mère refuse (journal_immuable) et la fiche reste celle de la correction', () async {
    final c = Clinique(9773, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'AGENT UN');
      final o1 = lecteur(f1.m);
      f1.m.collection(ocrLectures).inserer(uneLecture(), prefixe: 'OCR');
      f1.m.utilisateur = 'Awa Agoro';
      f1.m.horloge = () => t0.add(const Duration(hours: 1));
      final id = o1.corriger(scan: {'sha256': sha}, texte: 'Texte corrigé, honnête.', famille: docFamilleCourrier, peutEditer: true).version!;
      await tours(c);
      expect(await compteMere(c, ocrLectures), 2);
      final r = await http.post(Uri.parse('http://127.0.0.1:${c.port}/admin/referentiel'),
          headers: {'content-type': 'application/json', 'x-admin': 'secret-test'}, body: jsonEncode({'collection': ocrLectures, 'fiche': id, 'champs': {'texteBrut': 'falsifié', 'corrigePar': 'Un autre'}}));
      expect((jsonDecode(r.body) as Map)['code'], 'journal_immuable');
      final liste = (await admin(c, '/admin/liste?collection=$ocrLectures'))['liste'] as List;
      final cor = liste.cast<Map>().firstWhere((x) => x['id'] == id)['data'] as Map;
      expect(cor['texteBrut'], 'Texte corrigé, honnête.');
      expect(cor['corrigePar'], 'Awa Agoro');
      // une fiche distante falsifiée chez un poste (signature qui ne suit pas) n'est jamais la version courante
      final falsifiee = {...f1.m.collection(ocrLectures).parId(id)!, 'texteBrut': 'falsifié', 'corrigePar': 'Un autre'};
      f1.m.collection(ocrLectures).appliquerDistante(falsifiee);
      expect(ocrVersionCourante(f1.m.collection(ocrLectures).toutes)!['texteSource'], 'ocr');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('5. le réglage décidé à la mère descend aux fileuls ; un fileul qui tente de l’écrire est refusé, à son poste et par la mère', () async {
    final c = Clinique(9774, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'AGENT UN');
      final f2 = await c.fileul('F2', 'stock', 'AGENT DEUX');
      final m = lecteur(c.mm, mere: true);
      c.mm.utilisateur = 'Administrateur';
      final reglage = m.definirReglage(peutRegler: true, actif: true, moteur: 'factice', langue: 'fra', motif: 'mise en service', delaiMs: 90000);
      expect(reglage.ok, isTrue, reason: '${reglage.refus}');
      final o1 = OcrPoste(f1.m, estMere: () => false)
        ..automatique = false
        ..installer();
      final o2 = OcrPoste(f2.m, estMere: () => false)
        ..automatique = false
        ..installer();
      await c.converger(() => f1.m.collection(ocrReglages).toutes.isNotEmpty && f2.m.collection(ocrReglages).toutes.isNotEmpty, 'le réglage descend');
      expect(o1.etatDe({'sha256': sha}).libelle, contains('aucun moteur d’OCR installé sur ce poste'), reason: 'un fileul sans moteur le dit');
      for (final o in [o1, o2]) {
        o.enregistrer(MoteurOcrFactice(id: 'autre'));
        expect(o.reglage.actif, isTrue);
        expect(o.reglage.moteur, 'factice');
        expect(o.reglage.delaiMs, 90000);
        expect(o.reglage.reglePar, 'Administrateur');
        expect(o.pret, isFalse, reason: 'le moteur choisi à la mère n’est pas installé sur ce poste : il le dit');
        expect(o.etatDe({'sha256': sha}).libelle, contains('« factice », choisi au réglage de la mère, n’est pas installé sur ce poste'));
      }
      // un fileul ne l'écrit pas : refus à son poste (famille R + garde « réglé sur la mère »)…
      final r = o1.definirReglage(peutRegler: true, actif: false, moteur: null, langue: 'fra', motif: 'je veux couper');
      expect(r.refus!.code, CodeOcr.reglageReserveMere);
      expect(() => f1.m.collection(ocrReglages).mettreAJour('ocr', {'actif': false}), throwsA(anything), reason: 'garde « réglé sur la mère »');
      // … et par la mère, même si un poste falsifié l'écrivait quand même par son moteur de synchronisation
      f1.moteur.ecrire(ocrReglages, 'ocr', existe: true, champs: {'actif': false, 'moteur': 'pirate'});
      f1.moteur.ecrire(ocrReglages, 'ocr-f1', existe: false, champs: {'actif': true, 'moteur': 'pirate'});
      await tours(c);
      final liste = ((await admin(c, '/admin/liste?collection=$ocrReglages'))['liste'] as List).cast<Map>();
      expect(liste, hasLength(1), reason: 'aucune fiche de réglage de plus à la mère');
      expect((liste.single['data'] as Map)['moteur'], 'factice');
      expect((liste.single['data'] as Map)['actif'], true);
      expect(f2.m.collection(ocrReglages).parId('ocr')!['moteur'], 'factice');
      // la mère change le réglage : il redescend
      c.mm.horloge = () => t0.add(const Duration(hours: 2));
      expect(m.definirReglage(peutRegler: true, actif: false, moteur: 'factice', langue: 'fra', motif: 'arrêt de la lecture').ok, isTrue);
      await c.converger(() => f1.m.collection(ocrReglages).parId('ocr')?['actif'] == false && f2.m.collection(ocrReglages).parId('ocr')?['actif'] == false, 'le nouveau réglage descend');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('6. la FILE reste locale ; JAMAIS vers un téléphone : ni lecture, ni correction, ni réglage', () async {
    final c = Clinique(9775, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'AGENT UN');
      final f2 = await c.fileul('F2', 'stock', 'AGENT DEUX');
      final o1 = lecteur(f1.m);
      lecteur(c.mm, mere: true).definirReglage(peutRegler: true, actif: true, moteur: 'factice', langue: 'fra', motif: 'essai');
      f1.m.collection(ocrFile).inserer({'id': 'OCQ-${sha.substring(0, 16)}', 'sha256': sha, 'etat': 'en_attente', 'famille': 'courrier'}, prefixe: 'OCQ');
      f1.m.collection(ocrLectures).inserer(uneLecture(), prefixe: 'OCR');
      f1.m.utilisateur = 'Awa Agoro';
      f1.m.horloge = () => t0.add(const Duration(hours: 1));
      o1.corriger(scan: {'sha256': sha}, texte: 'Texte corrigé pour le téléphone.', famille: docFamilleCourrier, peutEditer: true);
      await c.converger(() => f2.m.collection(ocrLectures).toutes.length == 2 && f2.m.collection(ocrReglages).toutes.isNotEmpty, 'tout est arrivé chez F2');
      expect(f2.m.collection(ocrFile).toutes, isEmpty, reason: 'la file est locale à F1');
      expect(c.mm.collection(ocrFile).toutes, isEmpty);
      expect(await compteMere(c, ocrFile), 0, reason: 'la mère ne détient aucune file');
      final recues = await collectionsRecuesParUnMobile(c.port);
      final noms = {for (final x in recues) x.collection};
      expect(await compteMere(c, ocrLectures), 2);
      expect(noms, isNot(contains(ocrLectures)), reason: 'un téléphone ne reçoit AUCUN texte lu ni corrigé : $noms');
      expect(noms, isNot(contains(ocrReglages)), reason: 'ni le réglage');
      expect(noms, isNot(contains(ocrFile)));
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
