// La lecture OCR préparée (portage OCR-prep) et la CORRECTION SIGNÉE du texte lu (lot C) : règles pures. Le moteur est FACTICE ; aucune qualité de moteur réel n'est éprouvée ici.
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

const sha = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const texteMachine = 'Ordonnance : amoxicilline 500 mg, deux fois par jour. Revoir a Parakou dans une semaine.';
final t0 = DateTime.utc(2026, 11, 14, 8).toIso8601String();
final t1 = DateTime.utc(2026, 11, 14, 9).toIso8601String();
final t2 = DateTime.utc(2026, 11, 14, 10).toIso8601String();

FicheDoc lecture({String moteur = 'factice', String version = '0.1', String texte = texteMachine, String ocrLe = ''}) => ocrNouvelleLecture(
    sha: sha, texte: texte, moteur: moteur, moteurVersion: version, langue: 'fra', ocrLe: ocrLe.isEmpty ? t0 : ocrLe, ocrPar: 'Agent A', declencheur: 'automatique', pages: 1, dureeMs: 10);

FicheDoc corrige(List<FicheDoc> v, String texte, {String auteur = 'Awa Agoro', String le = '', String? motif, String? corrigeDe}) {
  final r = ocrNouvelleCorrection(sha: sha, texte: texte, versions: v, natif: false, auteur: auteur, corrigeLe: le.isEmpty ? t1 : le, motif: motif, corrigeDe: corrigeDe);
  expect(r.refus, isNull, reason: '${r.refus}');
  return r.fiche!;
}

bool Function(String) cat(List<String> ok) => (c) => ok.contains(c);

void main() {
  group('une lecture : version immuable, identifiant déterministe', () {
    test('même scan, même moteur, même texte : le même identifiant ; un autre moteur : une autre version', () {
      expect(lecture()['id'], lecture(ocrLe: t2)['id'], reason: 'la date ne change pas l’identité : deux postes qui lisent la même chose ne font qu’une version');
      expect(lecture(moteur: 'autre')['id'], isNot(lecture()['id']));
      expect(lecture()['texteSource'], 'ocr');
    });
    test('le texte indexé est normalisé : sans accent, minuscules, mots distincts', () {
      final l = lecture(texte: 'Hyperglycémie sévère, père déjà traité');
      expect(l['texte'], 'hyperglycemie severe pere deja traite');
    });
  });

  group('états d’indexation : un scan image est dit « texte non indexé » tant qu’aucune lecture n’existe', () {
    test('aucun moteur sur le poste : la raison est dite en toutes lettres', () {
      final e = ocrEtatIndexation(natif: false, versions: const [], moteurInstalle: false, actif: false, moteurActif: false);
      expect(e.etat, EtatIndexation.nonIndexe);
      expect(e.libelle, contains('aucun moteur d’OCR installé sur ce poste'));
      expect(e.disponible, isFalse);
    });
    test('réglage décidé à la mère, moteur absent de CE poste : le fileul dit lequel manque', () {
      final e = ocrEtatIndexation(natif: false, versions: const [], moteurInstalle: true, actif: true, moteurActif: false, moteurChoisi: 'tesseract-local');
      expect(e.libelle, contains('« tesseract-local », choisi au réglage de la mère, n’est pas installé sur ce poste'));
      final r = ocrDemander(registre: {'sha256': sha}, versions: const [], moteurInstalle: true, actif: true, moteurActif: false, relance: false, famille: 'courrier', type: null, maintenant: t0, par: 'A');
      expect(r.refus!.code, CodeOcr.moteurAbsent);
      expect(r.refus!.motif, contains('réglage de la mère'));
    });
    test('désactivé à la mère : OCR_DESACTIVE ; la couche texte native prime toujours', () {
      final r = ocrDemander(registre: {'sha256': sha}, versions: const [], moteurInstalle: true, actif: false, moteurActif: true, relance: false, famille: 'courrier', type: null, maintenant: t0, par: 'A');
      expect(r.refus!.code, CodeOcr.desactive);
      final n = ocrDemander(registre: {'sha256': sha, 'texteIndexe': true}, versions: const [], moteurInstalle: true, actif: true, moteurActif: true, relance: false, famille: 'courrier', type: null, maintenant: t0, par: 'A');
      expect(n.refus!.code, CodeOcr.texteNatif);
      expect(ocrEtatIndexation(natif: true, versions: [lecture()], moteurInstalle: true, actif: true, moteurActif: true).etat, EtatIndexation.indexe);
    });
    test('une lecture : « lu par machine, à vérifier » (marqué) ; une file en cours garde la version précédente lisible', () {
      final e = ocrEtatIndexation(natif: false, versions: [lecture()], moteurInstalle: true, actif: true, moteurActif: true);
      expect(e.etat, EtatIndexation.ocrIndexe);
      expect(e.marque, isTrue);
      final c = ocrEtatIndexation(natif: false, versions: [lecture()], file: {'etat': 'en_cours'}, moteurInstalle: true, actif: true, moteurActif: true);
      expect(c.etat, EtatIndexation.ocrEnCours);
      expect(c.disponible, isTrue);
    });
    test('la file est UNE par empreinte et reprend après arrêt (trois essais puis échec nommé)', () {
      final d = ocrDemander(registre: {'sha256': sha, 'ocr': {'etat': 'en_attente'}}, versions: const [], moteurInstalle: true, actif: true, moteurActif: true, relance: false, famille: 'courrier', type: null, maintenant: t0, par: 'A');
      expect(d.deja, isTrue);
      final vieux = {'etat': 'en_cours', 'debutLe': t0, 'essais': 1};
      expect(ocrReprendre(vieux, maintenant: DateTime.utc(2026, 11, 15), delaiMs: 1000)!['etat'], 'en_attente');
      expect(ocrReprendre({...vieux, 'essais': 3}, maintenant: DateTime.utc(2026, 11, 15), delaiMs: 1000)!['code'], CodeOcr.essaisEpuises);
    });
  });

  group('le réglage se décide à la mère', () {
    final moteurs = {'factice': MoteurOcrFactice()};
    ({bool ok, RefusFichier? refus, ReglageOcr? reglage}) regler({bool estMere = true, bool peutRegler = true, bool actif = true, String? moteur = 'factice', String? motif = 'mise en service'}) =>
        ocrDefinirReglage(estMere: estMere, peutRegler: peutRegler, actif: actif, moteur: moteur, langue: 'fra', motif: motif, moteurs: moteurs, avant: const ReglageOcr(), regleLe: t0, reglePar: 'Admin');
    test('un fileul ne règle pas : REGLAGE_RESERVE_A_LA_MERE, même avec le droit', () {
      expect(regler(estMere: false).refus!.code, CodeOcr.reglageReserveMere);
    });
    test('à la mère, sans le droit de l’écran des paramètres : REGLAGE_RESERVE ; sans motif : MOTIF_REQUIS', () {
      expect(regler(peutRegler: false).refus!.code, CodeOcr.reglageReserve);
      expect(regler(motif: ' ').refus!.code, CodeOcr.motifRequis);
    });
    test('activer sans moteur installé sur la mère est refusé en nommant ; avec moteur : réglage daté, signé et motivé', () {
      expect(regler(moteur: null).refus!.code, CodeOcr.moteurAbsent);
      expect(regler(moteur: 'inconnu').refus!.motif, contains('« inconnu »'));
      final r = regler();
      expect(r.ok, isTrue);
      expect(r.reglage!.toJson(), containsPair('motif', 'mise en service'));
      expect(ocrReglageLire(r.reglage!.toJson()).moteur, 'factice');
      expect(ocrReglageLire(null).actif, isFalse, reason: 'désactivé par défaut');
    });
  });

  group('versions, signature, version courante (lot C)', () {
    test('la correction est une NOUVELLE version : le texte machine est conservé, intact', () {
      final m = lecture();
      final c = corrige([m], 'Ordonnance : amoxicilline 500 mg, deux fois par jour. Revoir à Parakou dans une semaine.', motif: 'accent perdu');
      expect(c['texteSource'], 'humain');
      expect(c['corrigeDe'], m['id']);
      expect(c['corrigePar'], 'Awa Agoro');
      expect(c['corrigeLe'], t1);
      expect(c['motif'], 'accent perdu');
      expect(m['texteBrut'], texteMachine, reason: 'la version machine n’est jamais réécrite');
      expect(ocrHistorique([m, c]).map((h) => h['nature']), ['correction', 'machine']);
    });
    test('la version humaine devient la courante et c’est elle qui est INDEXÉE ; le motif est facultatif', () {
      final m = lecture();
      final c = corrige([m], 'Ordonnance : amoxicilline 250 mg, trois fois par jour.');
      expect(c['motif'], '');
      expect(ocrVersionCourante([m, c])!['id'], c['id']);
      final t = ocrTexteRecherche(natifIndexe: false, natifTexte: '', versions: [m, c], famille: 'courrier', type: null, peutCategorie: null);
      expect(t, contains('250'));
      expect(t, isNot(contains('500')));
    });
    test('une relance du moteur APRÈS la correction ajoute une version machine mais la humaine reste courante', () {
      final m = lecture();
      final c = corrige([m], 'Texte corrigé par une personne.', le: t1);
      final relance = lecture(version: '0.2', texte: 'Un autre texte lu plus tard', ocrLe: t2);
      expect(ocrVersionCourante([m, c, relance])!['id'], c['id']);
      final e = ocrEtatIndexation(natif: false, versions: [m, c, relance], moteurInstalle: true, actif: true, moteurActif: true);
      expect(e.etat, EtatIndexation.ocrCorrige);
      expect(e.libelle, 'Texte corrigé par Awa Agoro');
      expect(e.marque, isFalse);
      expect(e.source, 'humain');
    });
    test('corriger encore chaîne les versions : la plus récente humaine est courante, l’historique garde tout', () {
      final m = lecture();
      final c1 = corrige([m], 'Premier texte corrigé.', le: t1);
      final c2 = corrige([m, c1], 'Second texte corrigé, plus complet.', auteur: 'Marcel Gbaguidi', le: t2);
      expect(c2['corrigeDe'], c1['id']);
      expect(ocrVersionCourante([m, c1, c2])!['corrigePar'], 'Marcel Gbaguidi');
      final h = ocrHistorique([m, c1, c2]);
      expect(h.length, 3);
      expect(h.where((x) => x['courante'] == true).length, 1);
    });
    test('la signature se retrouve ; un texte, un auteur ou une date changés après coup la cassent et la version n’est plus courante', () {
      final m = lecture();
      final c = corrige([m], 'Texte corrigé honnête.');
      expect(ocrSignatureValide(c), isTrue);
      for (final alteree in [
        {...c, 'texteBrut': 'Texte falsifié'},
        {...c, 'corrigePar': 'Quelqu’un d’autre'},
        {...c, 'corrigeLe': t2},
        {...c, 'signature': ''},
      ]) {
        expect(ocrSignatureValide(alteree), isFalse);
        expect(ocrVersionCourante([m, alteree])!['id'], m['id'], reason: 'une signature qui ne se retrouve pas ne devient jamais la version courante');
      }
      expect(ocrHistorique([m, {...c, 'texteBrut': 'x'}]).first['signatureInvalide'], isTrue);
    });
    test('l’identifiant est déterministe (même correction rejouée = même version) et distinct d’une autre correction', () {
      final m = lecture();
      expect(corrige([m], 'Même texte.')['id'], corrige([m], 'Même texte.')['id']);
      expect(corrige([m], 'Même texte.')['id'], isNot(corrige([m], 'Autre texte.')['id']));
    });
    test('refus nommés : texte inchangé, vide, trop long, sans lecture, couche texte native, sans auteur, version inconnue', () {
      final m = lecture();
      String? code(String texte, {List<FicheDoc>? v, bool natif = false, String auteur = 'A B', String? de}) =>
          ocrNouvelleCorrection(sha: sha, texte: texte, versions: v ?? [m], natif: natif, auteur: auteur, corrigeLe: t1, corrigeDe: de).refus?.code;
      expect(code(texteMachine), CodeOcr.aucunChangement);
      expect(code('   '), CodeOcr.texteVide);
      expect(code('x' * (ocrCorrectionMax + 1)), CodeOcr.texteTropLong);
      expect(code('Nouveau', v: const []), CodeOcr.sansLecture);
      expect(code('Nouveau', natif: true), CodeOcr.texteNatif);
      expect(code('Nouveau', auteur: ' '), CodeOcr.auteurRequis);
      expect(code('Nouveau', de: 'OCR-inconnue'), CodeOcr.versionInconnue);
    });
  });

  group('le droit de corriger : la matrice, jamais un nom de rôle ; on ne corrige que ce qu’on lit', () {
    test('sans droit d’éditer l’écran du document : DROIT_REFUSE (courrier ou patient)', () {
      expect(ocrRefusCorrection(peutEditerEcran: false, famille: 'courrier', type: null, peutCategorie: null)!.code, CodeOcr.droitRefuse);
      expect(ocrRefusCorrection(peutEditerEcran: false, famille: 'patient', type: 'Ordonnance', peutCategorie: cat(['notes_consultation']))!.code, CodeOcr.droitRefuse);
    });
    test('courrier : le droit d’éditer suffit', () {
      expect(ocrRefusCorrection(peutEditerEcran: true, famille: 'courrier', type: null, peutCategorie: null), isNull);
    });
    test('document patient : éditer ne suffit pas, il faut lire les catégories du type (zone 2 : ZONE_REFUSEE, la catégorie manquante est dite)', () {
      final r = ocrRefusCorrection(peutEditerEcran: true, famille: 'patient', type: 'Compte rendu médical', peutCategorie: cat(['notes_consultation']));
      expect(r!.code, CodeOcr.zoneRefusee);
      expect(r.motif, contains('diagnostic_pathologie'));
      expect(ocrRefusCorrection(peutEditerEcran: true, famille: 'patient', type: 'Compte rendu médical', peutCategorie: cat(['notes_consultation', 'diagnostic_pathologie'])), isNull);
      expect(ocrRefusCorrection(peutEditerEcran: true, famille: 'patient', type: 'Pièce d’identité', peutCategorie: cat(['identite_detaillee'])), isNull, reason: 'zone 1 : la catégorie d’identité suffit');
    });
    test('un type inconnu se range au plus strict ; sans fonction de lecture, on refuse', () {
      expect(ocrRefusCorrection(peutEditerEcran: true, famille: 'patient', type: 'Inconnu', peutCategorie: cat(['identite_detaillee']))!.code, CodeOcr.zoneRefusee);
      expect(ocrRefusCorrection(peutEditerEcran: true, famille: 'patient', type: 'Ordonnance', peutCategorie: null)!.code, CodeOcr.zoneRefusee);
    });
    test('le texte lu d’un document de zone 2 ne se cherche pas sans le droit de lecture ; la version corrigée non plus', () {
      final m = lecture();
      final c = corrige([m], 'Diagnostic corrigé : paludisme grave.');
      String t(bool Function(String)? p) => ocrTexteRecherche(natifIndexe: false, natifTexte: '', versions: [m, c], famille: 'patient', type: 'Compte rendu médical', peutCategorie: p);
      expect(t(cat(['notes_consultation'])), '');
      expect(t(cat(['notes_consultation', 'diagnostic_pathologie'])), contains('paludisme'));
    });
  });

  group('lecture par moteur : factice, borné, refus nommé', () {
    final octets = Uint8List.fromList([1, 2, 3]);
    test('moteur factice : texte rendu ; moteur absent, texte vide, délai : refus nommés', () async {
      final m = MoteurOcrFactice(texteParDefaut: 'bonjour la clinique');
      final ok = await ocrLireFichier(moteur: m, octets: octets, formatId: 'png', mime: null, langue: 'fra', delaiMs: 1000);
      expect(ok.ok, isTrue);
      expect(ok.texte, 'bonjour la clinique');
      expect((await ocrLireFichier(moteur: null, octets: octets, formatId: 'png', mime: null, langue: 'fra', delaiMs: 1000)).refus!.code, CodeOcr.moteurAbsent);
      expect((await ocrLireFichier(moteur: MoteurOcrFactice(), octets: octets, formatId: 'png', mime: null, langue: 'fra', delaiMs: 1000)).refus!.code, CodeOcr.aucunTexte);
      final lent = MoteurOcrFactice(texteParDefaut: 'x', latence: const Duration(milliseconds: 300));
      expect((await ocrLireFichier(moteur: lent, octets: octets, formatId: 'png', mime: null, langue: 'fra', delaiMs: 20)).refus!.code, CodeOcr.delaiDepasse);
      expect((await ocrLireFichier(moteur: m, octets: octets, formatId: 'pdf', mime: null, langue: 'fra', delaiMs: 1000)).refus!.code, CodeOcr.rendu);
    });
  });
}
