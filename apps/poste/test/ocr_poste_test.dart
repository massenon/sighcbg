// La lecture OCR au poste (OCR-prep porté) et la CORRECTION SIGNÉE du texte lu (lot C) : service, droits, réglage décidé à la mère. Le moteur est FACTICE : ce qui est éprouvé, c'est tout ce
// qui l'entoure — jamais la qualité d'un moteur réel.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/documents/ocr_poste.dart';
import 'package:sigh_poste/documents/service_fichiers.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_sync/sigh_sync.dart';

import 'documents_scans_test.dart' show courrier, docu, magasin, png;

final auj = DateTime.utc(2026, 11, 14, 10);
const texteLu = 'Ordonnance : amoxicilline 500 mg, deux fois par jour. Revoir a Parakou.';
final pngB = [...png, 7]; // une autre empreinte

bool Function(String) cat(List<String> ok) => (c) => ok.contains(c);

void main() {
  late Directory tmp;
  late StockFichiers stock;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sigh-poste-ocr-');
    stock = StockFichiers('${tmp.path}/scans');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Un poste : magasin, dossier de scans, service OCR (file coupée : menée à la main), moteur factice enregistré si demandé.
  ({Magasin m, ServiceFichiers s, OcrPoste o, MoteurOcrFactice? moteur}) poste(Map<String, List<Fiche>> jeux, {bool mere = true, bool avecMoteur = true, String texte = texteLu}) {
    final m = magasin(jeux);
    m.horloge = () => auj;
    m.utilisateur = 'Awa Agoro';
    final s = ServiceFichiers.de(m);
    s.stockagePour = (_) => stock;
    s.lireInfo = () async => {'dossier': stock.dossier, 'fichiers': stock.nombre};
    final moteur = avecMoteur ? MoteurOcrFactice(texteParDefaut: texte) : null;
    final o = OcrPoste(m, estMere: () => mere)
      ..automatique = false
      ..installer();
    if (moteur != null) o.enregistrer(moteur);
    return (m: m, s: s, o: o, moteur: moteur);
  }

  ResultatFileOcr activer(OcrPoste o, {bool peutRegler = true}) => o.definirReglage(peutRegler: peutRegler, actif: true, moteur: 'factice', langue: 'fra', motif: 'mise en service');

  Map<String, Object?> scanDe(Magasin m, String id) => docScan(m.collection('courriers').parId(id)!)!;

  group('sans moteur : un scan image est « texte non indexé », rien ne se met en file, la raison est dite', () {
    test('aucun moteur installé : l’état dit « aucun moteur d’OCR installé sur ce poste » ; un PDF à couche texte reste « indexé »', () async {
      final p = poste({'courriers': [courrier('C1', 'ARR-2026-0001'), courrier('C2', 'ARR-2026-0002')]}, avecMoteur: false);
      await p.s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.png', octets: png);
      final e = p.o.etatDe(scanDe(p.m, 'C1'));
      expect(e.etat, EtatIndexation.nonIndexe);
      expect(e.libelle, contains('aucun moteur d’OCR installé sur ce poste'));
      expect(p.m.collection(ocrFile).toutes, isEmpty);
      expect(p.s.libelleIndexation(p.m.collection('courriers').parId('C1')!), 'Texte non indexé');
      expect(p.s.sansTexte(p.m.collection('courriers').parId('C1')!), isTrue);
      expect(p.o.demander(docSha256(png)).refus!.code, CodeOcr.moteurAbsent);
      expect(p.o.reglage.actif, isFalse, reason: 'désactivé par défaut');
    });
  });

  group('le réglage se décide à la mère et se lit partout', () {
    test('un fileul ne le règle pas (même avec le droit) ; la mère sans le droit des paramètres non plus ; sans motif non plus', () {
      final f = poste({}, mere: false);
      expect(activer(f.o).refus!.code, CodeOcr.reglageReserveMere);
      expect(f.m.collection(ocrReglages).toutes, isEmpty);
      final m = poste({});
      expect(activer(m.o, peutRegler: false).refus!.code, CodeOcr.reglageReserve);
      expect(m.o.definirReglage(peutRegler: true, actif: true, moteur: 'factice', langue: 'fra', motif: ' ').refus!.code, CodeOcr.motifRequis);
      expect(m.m.collection(ocrReglages).toutes, isEmpty);
    });
    test('à la mère avec le droit : réglage écrit (moteur, langue, délai, motif, auteur, date), journalisé ; activer sans moteur est refusé en nommant', () {
      final sans = poste({}, avecMoteur: false);
      expect(activer(sans.o).refus!.code, CodeOcr.moteurAbsent);
      final p = poste({});
      final r = p.o.definirReglage(peutRegler: true, actif: true, moteur: 'factice', langue: 'fra', motif: 'mise en service', delaiMs: 45000);
      expect(r.ok, isTrue);
      final fiche = p.m.collection(ocrReglages).parId('ocr')!;
      expect(fiche['moteur'], 'factice');
      expect(fiche['delaiMs'], 45000);
      expect(fiche['reglePar'], 'Awa Agoro');
      expect(fiche['motif'], 'mise en service');
      expect(p.o.pret, isTrue);
      expect(p.m.collection('audit').toutes.where((a) => a['action'] == 'Réglage de la lecture OCR des scans'), hasLength(1));
    });
    test('REÇU de la mère (fiche appliquée à distance) : le fileul lit le moteur choisi ; si ce moteur n’est pas installé chez lui, il le DIT', () async {
      final f = poste({}, mere: false, avecMoteur: false);
      f.m.collection(ocrReglages).appliquerDistante({'id': 'ocr', 'actif': true, 'moteur': 'tesseract-local', 'langue': 'fra', 'delaiMs': 60000, 'reglePar': 'Administrateur', 'regleLe': '2026-11-14T08:00:00.000Z', 'motif': 'essai'});
      expect(f.o.reglage.moteur, 'tesseract-local');
      expect(f.o.pret, isFalse);
      f.o.enregistrer(MoteurOcrFactice(id: 'autre'));
      final cadre = poste({}, mere: false, avecMoteur: false);
      cadre.o.enregistrer(MoteurOcrFactice(id: 'autre'));
      cadre.m.collection(ocrReglages).appliquerDistante({'id': 'ocr', 'actif': true, 'moteur': 'tesseract-local', 'langue': 'fra', 'delaiMs': 60000});
      cadre.m.collection('courriers').appliquerDistante(courrier('C1', 'ARR-2026-0001'));
      await cadre.s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.png', octets: png);
      final e = cadre.o.etatDe(scanDe(cadre.m, 'C1'));
      expect(e.etat, EtatIndexation.nonIndexe);
      expect(e.libelle, contains('« tesseract-local », choisi au réglage de la mère, n’est pas installé sur ce poste'));
      expect(cadre.o.relancePossible(scanDe(cadre.m, 'C1'), peutDeposer: true), isFalse);
      expect(cadre.o.demander(docSha256(png)).refus!.code, CodeOcr.moteurAbsent);
    });
    test('le réglage reçu qui ACTIVE la lecture rattrape les scans déjà déposés chez le fileul (il lit chez lui, avec son moteur)', () async {
      final f = poste({'courriers': [courrier('C1', 'ARR-2026-0001')]}, mere: false);
      await f.s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.png', octets: png);
      expect(f.m.collection(ocrFile).toutes, isEmpty);
      f.m.collection(ocrReglages).appliquerDistante({'id': 'ocr', 'actif': true, 'moteur': 'factice', 'langue': 'fra', 'delaiMs': 60000});
      expect(f.m.collection(ocrFile).toutes, hasLength(1), reason: 'le scan est entré dans la file locale');
      expect(await f.o.vider(), 1);
      expect(f.o.etatDe(scanDe(f.m, 'C1')).etat, EtatIndexation.ocrIndexe);
    });
  });

  group('la lecture : file locale, une version par lecture, marquée « à vérifier »', () {
    test('activé : le dépôt met le scan en file, la file le lit, la lecture est une version immuable marquée, et la recherche la trouve', () async {
      final p = poste({'courriers': [courrier('C1', 'ARR-2026-0001')]});
      activer(p.o);
      await p.s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.png', octets: png);
      expect(p.m.collection(ocrFile).toutes, hasLength(1));
      expect(await p.o.vider(), 1);
      final e = p.o.etatDe(scanDe(p.m, 'C1'));
      expect(e.etat, EtatIndexation.ocrIndexe);
      expect(e.marque, isTrue);
      expect(p.s.libelleIndexation(p.m.collection('courriers').parId('C1')!), 'Texte lu par machine, à vérifier');
      expect(p.s.texteDe(p.m.collection('courriers').parId('C1')!, famille: docFamilleCourrier), contains('amoxicilline'));
      expect(p.s.texteDe(p.m.collection('courriers').parId('C1')!), '', reason: 'sans famille, seule la couche texte native est lue');
      expect(p.s.sansTexte(p.m.collection('courriers').parId('C1')!), isFalse);
      final v = p.o.versionsDe(docSha256(png)).single;
      expect(v['texteSource'], 'ocr');
      expect(() => p.m.collection(ocrLectures).mettreAJour(v['id'], {'texteBrut': 'réécrit'}), throwsA(anything), reason: 'une lecture est immuable (garde du magasin)');
      expect(() => p.m.collection(ocrLectures).inserer({...v}), throwsA(anything));
    });
    test('un seul moteur à la fois, jamais deux files pour la même empreinte, reprise après arrêt', () async {
      final p = poste({'courriers': [courrier('C1', 'ARR-2026-0001'), courrier('C2', 'ARR-2026-0002')]});
      activer(p.o);
      await p.s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.png', octets: png);
      await p.s.deposer(famille: docFamilleCourrier, ficheId: 'C2', nomOrigine: 'b.png', octets: pngB);
      expect(p.o.demander(docSha256(png)).deja, isTrue);
      expect(await p.o.vider(), 2);
      expect(p.moteur!.maxParallele, 1);
      // reprise : un « en cours » vieux de plus de deux délais est remis en attente
      final f = p.m.collection(ocrFile).toutes.first;
      p.m.collection(ocrFile).mettreAJour(f['id'], {'etat': 'en_cours', 'debutLe': '2026-11-14T00:00:00.000Z', 'essais': 1}, journaliser: false);
      expect(p.o.reprendre(), 1);
      expect(p.m.collection(ocrFile).parId(f['id'])!['etat'], 'en_attente');
    });
    test('la file ne sort pas du poste : `fileOcr` n’est ni dans l’activité synchronisée ni dans la configuration ; `lecturesOcr` voyage en ajout seul ; `reglagesOcr` descend', () {
      expect(collectionsActivite, isNot(contains(ocrFile)));
      expect(collectionsConfiguration(), isNot(contains(ocrFile)));
      expect(collectionsActivite, contains(ocrLectures));
      expect(collectionsAjoutSeul, contains(ocrLectures));
      expect(collectionsConfiguration(), contains(ocrReglages));
      expect(collectionsActivite, isNot(contains(ocrReglages)), reason: 'le réglage ne remonte pas : la mère seule l’écrit');
    });
    test('un fileul qui tente d’écrire le réglage localement est refusé par la garde « réglé sur la mère »', () {
      final f = poste({}, mere: false);
      ApplicateurConfiguration(f.m, (_) async => const []).poserGardes();
      expect(() => f.m.collection(ocrReglages).inserer({'id': 'ocr', 'actif': true, 'moteur': 'factice'}), throwsA(anything));
      expect(f.m.collection(ocrReglages).toutes, isEmpty);
    });
  });

  group('la CORRECTION SIGNÉE du texte lu (lot C)', () {
    const corrige = 'Ordonnance : amoxicilline 250 mg, trois fois par jour. Revoir à Parakou.';
    Future<({Magasin m, ServiceFichiers s, OcrPoste o, MoteurOcrFactice? moteur})> lu({bool patient = false, String type = 'Ordonnance'}) async {
      final p = poste({
        'courriers': [courrier('C1', 'ARR-2026-0001')],
        'documentsPatient': [docu('D1', 'GED-00001', type)],
      });
      activer(p.o);
      p.o.accesCourant = () => cat(['notes_consultation', 'diagnostic_pathologie', 'resultats_analyses']);
      if (patient) {
        await p.s.deposer(famille: docFamillePatient, ficheId: 'D1', nomOrigine: 'a.png', octets: png);
      } else {
        await p.s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.png', octets: png);
      }
      await p.o.vider();
      p.m.horloge = () => auj.add(const Duration(hours: 1)); // la correction vient après la lecture
      return p;
    }

    test('avec le droit d’éditer : NOUVELLE version signée, texte machine conservé, version humaine courante, indexée, « corrigé par »', () async {
      final p = await lu();
      final scan = scanDe(p.m, 'C1');
      expect(p.o.correctionPossible(scan, famille: docFamilleCourrier, peutEditer: true), isTrue);
      final r = p.o.corriger(scan: scan, texte: corrige, famille: docFamilleCourrier, peutEditer: true, motif: 'dosage rétabli');
      expect(r.ok, isTrue, reason: '${r.refus}');
      final versions = p.o.versionsDe(docSha256(png));
      expect(versions, hasLength(2));
      final machine = versions.firstWhere((v) => v['texteSource'] == 'ocr');
      final humaine = versions.firstWhere((v) => v['texteSource'] == 'humain');
      expect(machine['texteBrut'], texteLu, reason: 'le texte machine est conservé, intact');
      expect(humaine['corrigePar'], 'Awa Agoro');
      expect(humaine['corrigeLe'], auj.add(const Duration(hours: 1)).toIso8601String());
      expect(humaine['motif'], 'dosage rétabli');
      expect(humaine['corrigeDe'], machine['id']);
      expect(ocrSignatureValide(humaine), isTrue);
      expect(p.o.versionCourante(docSha256(png))!['id'], humaine['id']);
      final e = p.o.etatDe(scan);
      expect(e.etat, EtatIndexation.ocrCorrige);
      expect(e.libelle, 'Texte corrigé par Awa Agoro');
      expect(p.s.libelleIndexation(p.m.collection('courriers').parId('C1')!), 'Texte corrigé par Awa Agoro');
      final fiche = p.m.collection('courriers').parId('C1')!;
      expect(p.s.texteDe(fiche, famille: docFamilleCourrier), contains('250'));
      expect(p.s.texteDe(fiche, famille: docFamilleCourrier), isNot(contains('500')), reason: 'la version humaine est celle qui est indexée');
      expect(p.m.collection('audit').toutes.where((a) => a['action'] == 'Correction du texte lu d’un scan'), hasLength(1));
      // la même correction rejouée ne fait pas une seconde version ; une relance du moteur n'efface pas le travail humain
      expect(p.o.corriger(scan: scan, texte: corrige, famille: docFamilleCourrier, peutEditer: true).refus!.code, CodeOcr.aucunChangement);
      final h = p.o.historique(docSha256(png), famille: docFamilleCourrier);
      expect(h.map((x) => x['nature']), ['correction', 'machine']);
      expect(h.first['courante'], isTrue);
    });
    test('sans le droit d’éditer l’écran du document : la commande est ABSENTE et le moteur refuse aussi (DROIT_REFUSE) ; rien n’est écrit', () async {
      final p = await lu();
      final scan = scanDe(p.m, 'C1');
      expect(p.o.correctionPossible(scan, famille: docFamilleCourrier, peutEditer: false), isFalse);
      final r = p.o.corriger(scan: scan, texte: corrige, famille: docFamilleCourrier, peutEditer: false);
      expect(r.refus!.code, CodeOcr.droitRefuse);
      expect(p.o.versionsDe(docSha256(png)), hasLength(1));
    });
    test('document patient de zone 2 : éditer ne suffit pas, on ne corrige que ce qu’on lit (ZONE_REFUSEE) ; le droit de lecture ouvre ; l’historique n’est pas montré au profil qui ne lit pas', () async {
      final p = await lu(patient: true, type: 'Compte rendu médical');
      final scan = docScan(p.m.collection('documentsPatient').parId('D1')!)!;
      final accueil = cat(['identite_detaillee']);
      expect(p.o.correctionPossible(scan, famille: docFamillePatient, type: 'Compte rendu médical', peutEditer: true, peutCategorie: accueil), isFalse);
      expect(p.o.corriger(scan: scan, texte: corrige, famille: docFamillePatient, type: 'Compte rendu médical', peutEditer: true, peutCategorie: accueil).refus!.code, CodeOcr.zoneRefusee);
      expect(p.o.historique(docSha256(png), famille: docFamillePatient, type: 'Compte rendu médical', peutCategorie: accueil), isEmpty);
      expect(p.o.texteOcr(docSha256(png), famille: docFamillePatient, type: 'Compte rendu médical', peutCategorie: accueil), '');
      final medecin = cat(['notes_consultation', 'diagnostic_pathologie']);
      final r = p.o.corriger(scan: scan, texte: corrige, famille: docFamillePatient, type: 'Compte rendu médical', peutEditer: true, peutCategorie: medecin);
      expect(r.ok, isTrue, reason: '${r.refus}');
      expect(p.o.texteOcr(docSha256(png), famille: docFamillePatient, type: 'Compte rendu médical', peutCategorie: medecin), contains('250'));
      expect(p.o.texteOcr(docSha256(png), famille: docFamillePatient, type: 'Compte rendu médical', peutCategorie: accueil), '', reason: 'la version corrigée reste de zone 2');
      expect(p.m.collection('audit').toutes.firstWhere((a) => a['action'] == 'Correction du texte lu d’un scan')['module'], 'M1');
    });
    test('refus nommés : sans lecture à corriger, couche texte native, texte vide ou inchangé', () async {
      final p = poste({'courriers': [courrier('C1', 'ARR-2026-0001')]});
      activer(p.o);
      await p.s.deposer(famille: docFamilleCourrier, ficheId: 'C1', nomOrigine: 'a.png', octets: png);
      final scan = scanDe(p.m, 'C1');
      expect(p.o.correctionPossible(scan, famille: docFamilleCourrier, peutEditer: true), isFalse, reason: 'rien à corriger avant la lecture');
      expect(p.o.corriger(scan: scan, texte: 'x', famille: docFamilleCourrier, peutEditer: true).refus!.code, CodeOcr.sansLecture);
      await p.o.vider();
      expect(p.o.corriger(scan: scan, texte: '  ', famille: docFamilleCourrier, peutEditer: true).refus!.code, CodeOcr.texteVide);
      expect(p.o.corriger(scan: scan, texte: texteLu, famille: docFamilleCourrier, peutEditer: true).refus!.code, CodeOcr.aucunChangement);
      // une couche texte native prime : rien à corriger
      p.m.collection('fichiers').inserer({'id': docSha256(png), 'texte': 'texte natif', 'taille': 1}, prefixe: 'FIC');
      expect(p.o.corriger(scan: scan, texte: 'autre', famille: docFamilleCourrier, peutEditer: true).refus!.code, CodeOcr.texteNatif);
    });
    test('une correction dont la signature ne se retrouve pas (fiche altérée à la source) n’est jamais la version courante', () async {
      final p = await lu();
      final scan = scanDe(p.m, 'C1');
      final r = p.o.corriger(scan: scan, texte: corrige, famille: docFamilleCourrier, peutEditer: true);
      // une fiche reçue d'ailleurs, falsifiée : l'auteur a changé, la signature ne suit pas
      final saine = p.m.collection(ocrLectures).parId(r.version)!;
      p.m.collection(ocrLectures).appliquerDistante({...saine, 'texteBrut': 'Texte falsifié', 'texte': 'texte falsifie', 'corrigePar': 'Quelqu’un d’autre'});
      expect(p.o.versionCourante(docSha256(png))!['texteSource'], 'ocr');
      expect(p.o.historique(docSha256(png), famille: docFamilleCourrier).first['signatureInvalide'], isTrue);
    });
  });
}
