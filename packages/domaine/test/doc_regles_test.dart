// Les règles des documents numérisés : empreinte, formats, taille, noms normalisés, droits par catégorie sensible, versions, retrait, doublons, migration du
// base64 (empreinte vérifiée AVANT retrait), recherche, extraction du texte d'un PDF.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;

List<int> pdf([String texte = 'Bonjour']) => latin1.encode('%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\n4 0 obj\n<< /Length 50 >>\nstream\nBT /F1 12 Tf (Ordonnance de $texte) Tj ET\nendstream\nendobj\n%%EOF');
final png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3];
final jpg = [0xff, 0xd8, 0xff, 0xe0, 1, 2, 3];

class Memoire implements DocStockage {
  final Map<String, List<int>> octets = {};
  final Map<String, String> noms = {};
  bool corrompre = false;
  @override
  Future<void> deposer({required List<int> octets, required String sha256, required String nomNormalise}) async {
    if (docSha256(octets) != sha256) throw const DocErreur('EMPREINTE_DIVERGENTE', 'divergence', 'rejouer');
    this.octets[sha256] = corrompre ? [...octets, 0] : octets;
    noms[sha256] = nomNormalise;
  }

  @override
  Future<List<int>?> lire(String sha256) async => octets[sha256];
}

void main() {
  group('empreinte SHA-256', () {
    test('vecteurs du standard', () {
      expect(docSha256([]), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(docSha256(utf8.encode('abc')), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(docSha256(utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')), '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
      expect(docSha256(List.filled(1000000, 0x61)), 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
    });
  });

  group('formats et taille', () {
    test('le format se lit sur les octets, jamais sur le nom', () {
      expect(docFormatDesOctets(pdf())?.id, 'pdf');
      expect(docFormatDesOctets(png)?.id, 'png');
      expect(docFormatDesOctets(jpg)?.id, 'jpeg');
      expect(docFormatDesOctets([1, 2, 3]), isNull);
      expect(docControlerDepot(octets: [1, 2, 3, 4], nomOrigine: 'a.pdf', famille: docFamilleCourrier)?.code, 'FORMAT_REFUSE');
      expect(docControlerDepot(octets: png, nomOrigine: 'a.pdf', famille: docFamilleCourrier)?.code, 'EXTENSION_INCOHERENTE');
      expect(docControlerDepot(octets: const [], nomOrigine: 'a.pdf', famille: docFamilleCourrier)?.code, 'FICHIER_VIDE');
      expect(docControlerDepot(octets: pdf(), nomOrigine: 'scan.PDF', famille: docFamilleCourrier), isNull);
    });
    test('WEBP admis au dossier patient seulement', () {
      final webp = [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 1];
      expect(docControlerDepot(octets: webp, nomOrigine: 'a.webp', famille: docFamillePatient), isNull);
      expect(docControlerDepot(octets: webp, nomOrigine: 'a.webp', famille: docFamilleCourrier)?.code, 'FORMAT_REFUSE');
    });
    test('taille maximale : défaut 10 Mo, réglable, bornée, refus nommé', () {
      expect(docTailleMax(null), 10 * 1024 * 1024);
      expect(docTailleMax(1), docTaillePlancher);
      expect(docTailleMax(10 * docTaillePlafond), docTaillePlafond);
      final gros = [...pdf(), ...List.filled(200 * 1024, 0)];
      final r = docControlerDepot(octets: gros, nomOrigine: 'a.pdf', famille: docFamillePatient, tailleMaxReglee: 150 * 1024);
      expect(r?.code, 'TAILLE_DEPASSEE');
      expect(r?.geste, contains('Paramètres système'));
      expect(docControlerDepot(octets: gros, nomOrigine: 'a.pdf', famille: docFamillePatient, tailleMaxReglee: 300 * 1024), isNull);
      expect(docControlerReglageTaille(50, 'x')?.code, 'TAILLE_HORS_BORNES');
      expect(docControlerReglageTaille(2 * 1024 * 1024, ' ')?.code, 'MOTIF_REQUIS');
      expect(docControlerReglageTaille(2 * 1024 * 1024, 'Scans plus lourds'), isNull);
    });
  });

  group('nom normalisé', () {
    final cour = <String, Object?>{'reference': 'ARR-2026-0042', 'date': '2026-11-11', 'sens': 'arrivee'};
    final pat = <String, Object?>{'reference': 'GED-00007', 'date': '2026-11-05', 'code': 'CBG/12/26', 'type': 'Compte rendu médical'};
    test('courrier : exemple de la Direction', () {
      expect(docNomNormalise(famille: docFamilleCourrier, fiche: cour, ext: 'pdf'), '2026-11-11_ARR_0042.pdf');
      expect(docNomNormalise(famille: docFamilleCourrier, fiche: {...cour, 'reference': 'DEP-2026-0003'}, ext: '.PDF'), '2026-11-11_DEP_0003.pdf');
      expect(docNomNormalise(famille: docFamilleCourrier, fiche: cour, ext: 'jpg', version: 2), '2026-11-11_ARR_0042_v2.jpg');
    });
    test('dossier patient : code sans barre, type sans accent', () {
      expect(docNomNormalise(famille: docFamillePatient, fiche: pat, ext: 'pdf'), '2026-11-05_CBG-12-26_compte-rendu-medical_007.pdf');
      expect(docNomNormalise(famille: docFamillePatient, fiche: {...pat, 'type': 'Pièce d’identité'}, ext: 'png', version: 3), '2026-11-05_CBG-12-26_piece-d-identite_007_v3.png');
    });
    test('validité stricte : aucun nom libre, aucune traversée de dossier', () {
      for (final bon in ['2026-11-11_ARR_0042.pdf', '2026-11-11_DEP_0042_v2.jpg', '2026-11-05_CBG-12-26_ordonnance_007.pdf', '2026-11-05_CBG-12-26_ordonnance_007_v10.png']) {
        expect(docNomNormaliseValide(bon), isTrue, reason: bon);
      }
      for (final mauvais in ['../2026-11-11_ARR_0042.pdf', 'scan.pdf', '2026-11-11_ARR_0042.exe', '2026-11-11_ARR_0042.pdf/../x', '2026-11-11_ARR_42.pdf', 'a/2026-11-11_ARR_0042.pdf', '2026-11-11_ARR_0042.PDF', '']) {
        expect(docNomNormaliseValide(mauvais), isFalse, reason: mauvais);
      }
    });
  });

  group('droits par catégorie sensible', () {
    test('la zone d’un type et ses catégories viennent du référentiel de la matrice', () {
      expect(docZoneDuType('Pièce d’identité'), 1);
      expect(docZoneDuType('Carte d’assurance'), 1);
      expect(docZoneDuType('Compte rendu médical'), 2);
      expect(docZoneDuType('Type inconnu'), 2);
      for (final c in docCategoriesDesTypes.values.expand((x) => x)) {
        expect(categorieSensible(c), isNotNull, reason: 'catégorie « $c » absente de la matrice');
      }
    });
    test('un rôle voit un type selon ses catégories, sans comparer un nom de rôle', () {
      // « accueil » : la matrice lui ouvre le répertoire (Zone 1) mais pas le dossier de consultation (Zone 2).
      final d = DroitsSensibles(fiches: const [], peutVoirEcran: (r, e) => e == 'm1-patients');
      bool peut(String c) => d.peut('un-role-quelconque', c);
      expect(docPeutLire(peut, 'Pièce d’identité'), isTrue);
      expect(docPeutLire(peut, 'Compte rendu médical'), isFalse);
      expect(docCategoriesManquantes(peut, 'Résultat de laboratoire'), contains('notes_consultation'));
      // Une décision de la clinique accorde la catégorie : le document devient lisible, sans toucher au code.
      final d2 = DroitsSensibles(fiches: [
        {'id': 'x', 'role': 'un-role-quelconque', 'donneesSensibles': {'notes_consultation': true, 'diagnostic_pathologie': true}}
      ], peutVoirEcran: (r, e) => e == 'm1-patients');
      expect(docPeutLire((c) => d2.peut('un-role-quelconque', c), 'Compte rendu médical'), isTrue);
    });
  });

  group('versions, remplacement, retrait', () {
    M meta(String sha, int v) => docMetaScan(sha256: sha, nomOrigine: 'a.pdf', nomNormalise: 'n', mime: 'application/pdf', taille: 3, version: v, deposePar: 'Awa', deposeLe: '2026-11-11T10:00');
    test('numerise est DÉRIVÉ de la présence du fichier', () {
      expect(docNumerise({'numerise': true}), isFalse);
      expect(docNumerise({'scan': meta('a' * 64, 1)}), isTrue);
      expect(docNumerise({'scan': null}), isFalse);
    });
    test('un remplacement garde l’ancienne version ; un retrait aussi, avec son motif', () {
      var f = <String, Object?>{'id': 'C1'};
      expect(docProchaineVersion(f), 1);
      f.addAll(docPatchDepot(f, meta('a' * 64, 1), par: 'Awa', le: 't1'));
      expect(docProchaineVersion(f), 2);
      f.addAll(docPatchDepot(f, meta('b' * 64, 2), par: 'Awa', le: 't2'));
      expect(docScan(f)!['sha256'], 'b' * 64);
      expect(docScansAnterieurs(f), hasLength(1));
      expect(docScansAnterieurs(f).first['sha256'], 'a' * 64);
      expect(docScansAnterieurs(f).first['motifRetrait'], contains('version 2'));
      expect(() => docPatchRetrait(f, par: 'Awa', le: 't3', motif: ' '), throwsA(isA<DocErreur>()));
      f.addAll(docPatchRetrait(f, par: 'Awa', le: 't3', motif: 'Mauvais scan'));
      expect(docNumerise(f), isFalse);
      expect(docScansAnterieurs(f), hasLength(2));
      expect(docProchaineVersion(f), 3, reason: 'un numéro de version ne se réutilise pas');
      expect(() => docPatchRetrait(f, par: 'x', le: 't', motif: 'm'), throwsA(isA<DocErreur>()));
    });
    test('doublon : même fiche = refus nommé, autre fiche = avertissement', () {
      final a = {'id': 'C1', 'reference': 'ARR-2026-0001', 'scan': meta('a' * 64, 1)};
      final b = {'id': 'C2', 'reference': 'ARR-2026-0002', 'scan': meta('a' * 64, 1)};
      final arch = {'id': 'C3', 'statut': 'archive', 'scan': meta('a' * 64, 1)};
      final r = docControlerDoublon(sha256: 'a' * 64, fiche: a, fiches: [a, b, arch]);
      expect(r.refus, isTrue);
      expect(docRefusDoublon(r.memeFiche!).motif, contains('aaaaaaaa'));
      final r2 = docControlerDoublon(sha256: 'a' * 64, fiche: {'id': 'C9'}, fiches: [a, b, arch]);
      expect(r2.refus, isFalse);
      expect(r2.avertissement, isTrue);
      expect(docControlerDoublon(sha256: 'c' * 64, fiche: a, fiches: [a]).avertissement, isFalse);
    });
  });

  group('migration du base64', () {
    String uri(List<int> o, [String mime = 'application/pdf']) => 'data:$mime;base64,${base64Encode(o)}';
    List<M> jeu() => [
          {'id': 'D1', 'reference': 'GED-00001', 'code': 'CBG/1/26', 'type': 'Ordonnance', 'date': '2026-11-01', 'fichier': 'o.pdf', 'donnees': uri(pdf('un'))},
          {'id': 'D2', 'reference': 'GED-00002', 'code': 'CBG/2/26', 'type': 'Facture', 'date': '2026-11-02', 'fichier': 'f.png', 'donnees': uri(png, 'image/png')},
          {'id': 'D3', 'reference': 'GED-00003', 'code': 'CBG/3/26', 'type': 'Facture', 'date': '2026-11-02', 'fichier': 'x.pdf', 'donnees': ''},
          {'id': 'D4', 'reference': 'GED-00004', 'code': 'CBG/4/26', 'type': 'Facture', 'date': '2026-11-02', 'donnees': 'data:application/pdf;base64,@@@'},
          {'id': 'D5', 'reference': 'GED-00005', 'code': 'CBG/5/26', 'type': 'Facture', 'date': '2026-11-02', 'donnees': uri([1, 2, 3, 4, 5], 'text/plain')},
        ];
    test('range, relit, compare l’empreinte, PUIS retire le base64 ; ignore, refuse, nomme', () async {
      final s = Memoire();
      final f = jeu();
      final r = await docMigrerBase64(
          fiches: f, stockage: s, par: 'Admin', le: '2026-11-12T08:00', appliquer: (id, p) async => f.firstWhere((x) => x['id'] == id).addAll(p), pages: (o, m) => m == 'application/pdf' ? docExtraireTextePdf(o).pages : 1);
      expect(r.migrees, ['GED-00001', 'GED-00002']);
      expect(r.ignorees, 1);
      expect(r.refusees.map((x) => x.code).toList(), ['BASE64_ILLISIBLE', 'FORMAT_REFUSE']);
      expect(f[0]['donnees'], isNull);
      final scan = docScan(f[0])!;
      expect(scan['sha256'], docSha256(pdf('un')));
      expect(scan['nomNormalise'], '2026-11-01_CBG-1-26_ordonnance_001.pdf');
      expect(scan['nom'], 'o.pdf');
      expect(docNomNormaliseValide(scan['nomNormalise'] as String), isTrue);
      expect(s.octets[scan['sha256']], pdf('un'));
      // fiche refusée : intacte
      expect(f[3]['donnees'], isNotNull);
      expect(docScan(f[3]), isNull);
      // idempotente
      final r2 = await docMigrerBase64(fiches: f, stockage: s, par: 'A', le: 't', appliquer: (id, p) async => fail('rien à migrer'));
      expect(r2.migrees, isEmpty);
    });
    test('une copie qui ne relit pas à l’identique laisse le base64 en place (la sonde rougirait si la vérification était retirée)', () async {
      final s = Memoire()..corrompre = true;
      final f = jeu().take(1).toList();
      final r = await docMigrerBase64(fiches: f, stockage: s, par: 'A', le: 't', appliquer: (id, p) async => fail('ne doit rien écrire'));
      expect(r.migrees, isEmpty);
      expect(r.refusees.single.code, 'EMPREINTE_RELUE_DIFFERENTE');
      expect(f[0]['donnees'], isNotNull);
    });
  });

  group('recherche', () {
    final f = <String, Object?>{
      'id': 'C1', 'reference': 'ARR-2026-0042', 'date': '2026-11-11', 'objet': 'Demande d’autorisation d’ouverture', 'correspondant': 'Ministère de la Santé',
      'scan': docMetaScan(sha256: 'a' * 64, nomOrigine: 'Courrier ministère.pdf', nomNormalise: '2026-11-11_ARR_0042.pdf', mime: 'application/pdf', taille: 9, version: 1, deposePar: 'Awa', deposeLe: 't', texteIndexe: true)
    };
    test('métadonnées, accents et casse ignorés, tous les mots', () {
      expect(docCorrespond(f, 'ministere SANTE').trouve, isTrue);
      expect(docCorrespond(f, '11/11/2026').trouve, isTrue);
      expect(docCorrespond(f, 'ministere douane').trouve, isFalse);
      expect(docCorrespond(f, '').trouve, isTrue);
      expect(docCorrespond(f, '0042').trouve, isTrue);
    });
    test('le texte d’un PDF se retrouve par un mot de son corps ; la trouvaille le dit', () {
      final r = docCorrespond(f, 'hémorragie', texteIndexe: 'compte rendu hemorragie du post partum');
      expect(r.trouve, isTrue);
      expect(r.dansTexte, isTrue);
      expect(docCorrespond(f, 'ministere').dansTexte, isFalse);
      expect(docCorrespond(f, 'hemorragie').trouve, isFalse);
    });
    test('un scan image est dit « texte non indexé », jamais « aucun résultat »', () {
      final img = {...f, 'scan': docMetaScan(sha256: 'b' * 64, nomOrigine: 'a.png', nomNormalise: 'n', mime: 'image/png', taille: 9, version: 1, deposePar: 'x', deposeLe: 't')};
      expect(docEtatIndexation(img), 'non_indexe');
      expect(docLibelleIndexation(img), 'Texte non indexé');
      expect(docEtatIndexation(f), 'indexe');
      expect(docEtatIndexation({'id': 'z'}), 'sans_fichier');
    });
    test('plage de dates, bornes incluses', () {
      expect(docDansPlage('2026-11-11', du: '2026-11-11', au: '2026-11-11'), isTrue);
      expect(docDansPlage('2026-11-10', du: '2026-11-11'), isFalse);
      expect(docDansPlage('2026-11-12', au: '2026-11-11'), isFalse);
      expect(docDansPlage('2026-11-12'), isTrue);
    });
  });

  group('extraction du texte d’un PDF', () {
    test('couche texte littérale', () {
      final r = docExtraireTextePdf(pdf('Éléphant'));
      expect(r.indexe, isTrue);
      expect(r.mots, containsAll(['ordonnance', 'elephant']));
      expect(r.pages, 1);
    });
    test('flux Flate', () {
      final contenu = latin1.encode('BT /F1 12 Tf [(Compte) -20 (rendu) 5 (hémorragie)] TJ ET');
      final z = ZLibCodec().encode(contenu);
      final o = <int>[...latin1.encode('%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\n2 0 obj\n<< /Filter /FlateDecode /Length ${z.length} >>\nstream\n'), ...z, ...latin1.encode('\nendstream\nendobj\n')];
      final r = docExtraireTextePdf(o);
      expect(r.indexe, isTrue);
      expect(r.mots, containsAll(['compte', 'rendu', 'hemorragie']));
    });
    test('police à codes de deux octets avec ToUnicode', () {
      final cmap = '1 beginbfchar <0001> <0053> <0002> <0041> endbfchar 1 beginbfrange <0003> <0004> <0042> endbfrange';
      final o = latin1.encode('%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\n2 0 obj\n<< /Length 1 >>\nstream\n$cmap\nendstream\nendobj\n3 0 obj\n<< /Length 1 >>\nstream\nBT <00010002000300040001> Tj ET\nendstream\nendobj');
      final r = docExtraireTextePdf(o);
      expect(r.mots, ['sabcs']);
    });
    test('un scan image n’a pas de couche texte : non indexé, raison dite ; un PDF chiffré aussi', () {
      final scan = latin1.encode('%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\n2 0 obj\n<< /Subtype /Image /Filter /DCTDecode /Length 4 >>\nstream\nÿØÿà\nendstream\nendobj');
      final r = docExtraireTextePdf(scan);
      expect(r.indexe, isFalse);
      expect(r.raison, contains('scan image'));
      expect(r.pages, 1);
      expect(docExtraireTextePdf(latin1.encode('%PDF-1.4 /Encrypt 5 0 R')).raison, contains('chiffré'));
      expect(docExtraireTextePdf([1, 2, 3]).indexe, isFalse);
    });
  });
}
