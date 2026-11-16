// Le chantier TABLEAUX (Q38 à Q42) : l'écrivain .xlsx relu par un lecteur zip INDÉPENDANT (écrit ici, ne partage rien avec l'écrivain), la limite et son refus nommé,
// la sélection, les cellules typées, le droit réservé et le journal sans contenu.
import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// Un lecteur de zip minimal, par le RÉPERTOIRE CENTRAL (comme Excel) : rend nom → contenu décompressé, et vérifie le CRC-32 de chaque entrée.
Map<String, Uint8List> lireZip(List<int> octets) {
  final d = ByteData.sublistView(Uint8List.fromList(octets));
  var fin = octets.length - 22;
  while (fin >= 0 && d.getUint32(fin, Endian.little) != 0x06054b50) {
    fin--;
  }
  expect(fin, greaterThanOrEqualTo(0), reason: 'fin de répertoire central introuvable : pas un zip');
  final n = d.getUint16(fin + 10, Endian.little);
  var p = d.getUint32(fin + 16, Endian.little);
  final sortie = <String, Uint8List>{};
  for (var i = 0; i < n; i++) {
    expect(d.getUint32(p, Endian.little), 0x02014b50);
    final methode = d.getUint16(p + 10, Endian.little);
    final crc = d.getUint32(p + 16, Endian.little);
    final taille = d.getUint32(p + 20, Endian.little);
    final origine = d.getUint32(p + 24, Endian.little);
    final ln = d.getUint16(p + 28, Endian.little), le = d.getUint16(p + 30, Endian.little), lc = d.getUint16(p + 32, Endian.little);
    final deb = d.getUint32(p + 42, Endian.little);
    final nom = utf8.decode(octets.sublist(p + 46, p + 46 + ln));
    // l'en-tête local
    expect(d.getUint32(deb, Endian.little), 0x04034b50);
    final lnLoc = d.getUint16(deb + 26, Endian.little), leLoc = d.getUint16(deb + 28, Endian.little);
    final donnees = octets.sublist(deb + 30 + lnLoc + leLoc, deb + 30 + lnLoc + leLoc + taille);
    final brut = methode == 8 ? Uint8List.fromList(ZLibCodec(raw: true).decode(donnees)) : Uint8List.fromList(donnees);
    expect(brut.length, origine, reason: nom);
    expect(crc32Reference(brut), crc, reason: 'CRC-32 de $nom');
    sortie[nom] = brut;
    p += 46 + ln + le + lc;
  }
  return sortie;
}

/// CRC-32 bit à bit, volontairement différent de la version à table de l'écrivain.
int crc32Reference(List<int> b) {
  var c = 0xFFFFFFFF;
  for (final x in b) {
    c ^= x;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
    }
  }
  return ~c & 0xFFFFFFFF;
}

String texteDe(Map<String, Uint8List> z, String nom) => utf8.decode(z[nom]!);

final instant = DateTime(2026, 11, 15, 10, 30);
const reglagesLarges = ReglagesExport(limiteLignes: 1000, seuilProgression: 100, limiteEtatsParLigne: 5);

void main() {
  group('le classeur .xlsx', () {
    late Map<String, Uint8List> z;
    late String feuille;
    setUp(() {
      final octets = ecrireXlsx(
          feuille: 'Transferts / 2026',
          entetes: ['Nom', 'Montant', 'Date', 'Heure', 'Code', 'Note'],
          lignes: [
            [const CelluleTexte('Dupont & <fils>'), const CelluleNombre(12000, FormatNombre.entierMilliers), CelluleDate(DateTime(2026, 11, 15)), CelluleDate(DateTime(2026, 11, 15, 12), avecHeure: true), const CelluleTexte('00123'), const CelluleTexte('=SOMME(A1)')],
            [const CelluleTexte('Un nom très long qui fixe la largeur de la colonne'), const CelluleNombre(3.5, FormatNombre.decimalMilliers), const CelluleVide(), const CelluleVide(), const CelluleTexte('9'), const CelluleVide()],
          ],
          maintenant: instant);
      z = lireZip(octets);
      feuille = texteDe(z, 'xl/worksheets/sheet1.xml');
    });

    test('c\'est un zip ouvrable : les parties obligatoires sont là, chaque CRC-32 est juste', () {
      expect(z.keys, containsAll(['[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml', 'xl/_rels/workbook.xml.rels', 'xl/styles.xml', 'xl/worksheets/sheet1.xml']));
      expect(texteDe(z, 'xl/workbook.xml'), contains('name="Transferts   2026"'), reason: 'le « / » interdit d\'un nom de feuille est remplacé');
    });

    test('le nombre est une cellule numérique, la date un numéro de série à format date', () {
      expect(feuille, contains('<c r="B2" s="2"><v>12000</v></c>'));
      expect(feuille, contains('<c r="B3" s="3"><v>3.5</v></c>'));
      // 15/11/2026 = 46 forme série : 2026-11-15 moins 1899-12-30
      final serie = DateTime.utc(2026, 11, 15).difference(DateTime.utc(1899, 12, 30)).inDays;
      expect(feuille, contains('<c r="C2" s="4"><v>$serie.0</v></c>'));
      expect(feuille, contains('<c r="D2" s="5"><v>$serie.5</v></c>'));
      expect(texteDe(z, 'xl/styles.xml'), contains('formatCode="dd/mm/yyyy"'));
    });

    test('un texte reste du texte, échappé, jamais évalué ; un code à zéro initial reste un texte', () {
      expect(feuille, contains('Dupont &amp; &lt;fils&gt;'));
      expect(feuille, contains('<c r="E2" t="inlineStr"><is><t xml:space="preserve">00123</t></is></c>'));
      expect(feuille, contains('<c r="F2" t="inlineStr"><is><t xml:space="preserve">=SOMME(A1)</t></is></c>'), reason: 'chaîne en ligne : aucune formule');
      expect(feuille, isNot(contains('<f>')));
    });

    test('l\'en-tête est figé, en gras, filtré ; les largeurs suivent le contenu', () {
      expect(feuille, contains('<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'));
      expect(feuille, contains('<c r="A1" s="1" t="inlineStr">'));
      expect(feuille, contains('<autoFilter ref="A1:F3"/>'));
      final largeurs = RegExp(r'<col min="(\d)" max="\d" width="([\d.]+)" customWidth="1"/>').allMatches(feuille).map((m) => double.parse(m[2]!)).toList();
      expect(largeurs.length, 6);
      expect(largeurs[0], greaterThan(40), reason: 'le nom long élargit la colonne A');
      expect(largeurs[1], lessThan(largeurs[0]));
      expect(largeurs.every((w) => w >= 8 && w <= 60), isTrue);
      expect(texteDe(z, 'xl/styles.xml'), contains('<b/>'));
    });

    test('les limites du format sont refusées en les nommant, jamais tronquées', () {
      expect(() => ecrireXlsx(feuille: 'x', entetes: const [], lignes: const [], maintenant: instant), throwsA(isA<RefusExport>().having((e) => e.code, 'code', 'EXPORT_SANS_COLONNE')));
      expect(
          () => ecrireXlsx(feuille: 'x', entetes: List.filled(xlsxColonnesMax + 1, 'c'), lignes: const [], maintenant: instant),
          throwsA(isA<RefusExport>().having((e) => e.code, 'code', 'XLSX_COLONNES_MAX')));
      expect(
          () => ecrireXlsx(feuille: 'x', entetes: ['a'], lignes: Iterable.generate(xlsxLignesMax + 1, (_) => const [CelluleVide()]), maintenant: instant),
          throwsA(isA<RefusExport>().having((e) => e.code, 'code', 'XLSX_LIGNES_MAX')));
    });

    test('lettres de colonnes et numéro de série', () {
      expect([0, 25, 26, 51, 52, 701, 702].map(lettreColonne), ['A', 'Z', 'AA', 'AZ', 'BA', 'ZZ', 'AAA']);
      expect(numeroSerieExcel(DateTime(1900, 3, 1)), 61, reason: 'Excel compte un 29/02/1900 inexistant : le 01/03/1900 vaut 61');
      expect(numeroSerieExcel(DateTime(2026, 1, 1)), 46023);
    });
  });

  group('les cellules déduites de ce que l\'écran affiche', () {
    test('montant à la française, devise retirée, milliers', () {
      final c = celluleDepuis('12 000 FCFA') as CelluleNombre;
      expect(c.valeur, 12000);
      expect(c.format, FormatNombre.entierMilliers);
      final d = celluleDepuis('1 234,50') as CelluleNombre;
      expect(d.valeur, 1234.5);
      expect(d.format, FormatNombre.decimalMilliers);
      expect((celluleDepuis('-3 500') as CelluleNombre).valeur, -3500);
      expect((celluleDepuis('42') as CelluleNombre).format, FormatNombre.general);
    });
    test('un identifiant ou un téléphone n\'est jamais un nombre', () {
      for (final t in ['00123', '0612345678', '+22997000000', '12345678901234567', 'CNT/12/26', '12 kg', '37 %']) {
        expect(celluleDepuis(t), isA<CelluleTexte>(), reason: t);
      }
    });
    test('dates : jj/mm/aaaa, avec heure, ISO ; une date impossible reste du texte', () {
      final d = celluleDepuis('15/11/2026') as CelluleDate;
      expect(d.date, DateTime(2026, 11, 15));
      expect(d.avecHeure, isFalse);
      final h = celluleDepuis('15/11/2026 14:05') as CelluleDate;
      expect(h.date, DateTime(2026, 11, 15, 14, 5));
      expect(h.avecHeure, isTrue);
      expect((celluleDepuis('2026-03-02') as CelluleDate).date, DateTime(2026, 3, 2));
      expect(celluleDepuis('31/02/2026'), isA<CelluleTexte>());
    });
    test('sans texte : le brut (date, nombre) ; sinon vide', () {
      expect(celluleDepuis('', DateTime(2026, 1, 2)), isA<CelluleDate>());
      expect((celluleDepuis('', 7) as CelluleNombre).valeur, 7);
      expect(celluleDepuis(''), isA<CelluleVide>());
    });
    test('CSV : une formule n\'est pas évaluée à l\'ouverture', () {
      expect(garderTexteCsv('=1+1'), '\'=1+1');
      expect(garderTexteCsv('@cmd'), '\'@cmd');
      expect(garderTexteCsv('-12'), '-12');
      expect(garderTexteCsv('-cmd'), '\'-cmd');
      expect(garderTexteCsv('Dupont'), 'Dupont');
    });
  });

  group('la production : limite, progression, annulation', () {
    final colonnes = [
      ColonneExport(libelle: 'Nom', texte: (r) => '${r['nom']}'),
      ColonneExport(libelle: 'Montant', texte: (r) => '${r['m']}'),
    ];
    List<Map<String, Object?>> lignes(int n) => [for (var i = 0; i < n; i++) {'id': 'r$i', 'nom': 'Patient $i', 'm': i * 1000}];

    test('au-delà de la limite : REFUS NOMMÉ, aucun fichier', () async {
      final r = await produireExport(colonnes: colonnes, lignes: lignes(1001), format: FormatExport.xlsx, feuille: 'T', maintenant: instant, reglages: reglagesLarges);
      expect(r.ok, isFalse);
      expect(r.octets, isNull);
      expect(r.refus!.code, 'EXPORT_TROP_VOLUMINEUX');
      expect(r.refus!.motif, allOf(contains('1001'), contains('1000')));
      expect(r.refus!.geste, contains('Paramètres'));
      final pile = await produireExport(colonnes: colonnes, lignes: lignes(1000), format: FormatExport.csv, feuille: 'T', maintenant: instant, reglages: reglagesLarges);
      expect(pile.ok, isTrue, reason: 'à la limite exacte, on exporte tout');
      expect(pile.lignes, 1000);
    });

    test('xlsx : toutes les lignes, jamais une de moins', () async {
      final r = await produireExport(colonnes: colonnes, lignes: lignes(250), format: FormatExport.xlsx, feuille: 'T', maintenant: instant, reglages: reglagesLarges);
      final feuille = utf8.decode(lireZip(r.octets!)['xl/worksheets/sheet1.xml']!);
      expect(RegExp('<row ').allMatches(feuille).length, 251, reason: 'en-tête + 250 lignes');
      expect(feuille, contains('Patient 249'));
    });

    test('csv : BOM, séparateur « ; », guillemets, CRLF', () async {
      final r = await produireExport(colonnes: colonnes, lignes: [{'nom': 'A "B"', 'm': 5}, {'nom': '=X', 'm': 6}], format: FormatExport.csv, feuille: 'T', maintenant: instant, reglages: reglagesLarges);
      expect(r.octets!.take(3), [0xEF, 0xBB, 0xBF], reason: 'BOM UTF-8 : Excel FR lit les accents');
      final t = utf8.decode(r.octets!);
      expect(t, startsWith('"Nom";"Montant"\r\n'));
      expect(t, contains('"A ""B""";"5"'));
      expect(t, contains('"\'=X";"6"'));
    });

    test('au-delà du seuil : le compteur avance par lots, et l\'annulation ne rend aucun fichier', () async {
      final vus = <int>[];
      final r = await produireExport(
          colonnes: colonnes, lignes: lignes(450), format: FormatExport.xlsx, feuille: 'T', maintenant: instant, reglages: reglagesLarges, progression: (f, t) => vus.add(f));
      expect(r.ok, isTrue);
      expect(vus.length, greaterThan(3), reason: 'plusieurs lots, donc plusieurs mises à jour du compteur');
      expect(vus.last, 450);
      expect(vus, orderedEquals([...vus]..sort()));
      var tours = 0;
      final a = await produireExport(
          colonnes: colonnes, lignes: lignes(450), format: FormatExport.xlsx, feuille: 'T', maintenant: instant, reglages: reglagesLarges, annule: () => ++tours > 1);
      expect(a.annule, isTrue);
      expect(a.octets, isNull);
    });

    test('en dessous du seuil : aucune progression (pas de compteur pour trois lignes)', () async {
      final vus = <int>[];
      await produireExport(colonnes: colonnes, lignes: lignes(50), format: FormatExport.csv, feuille: 'T', maintenant: instant, reglages: reglagesLarges, progression: (f, t) => vus.add(f));
      expect(vus, [50], reason: 'un seul appel final, sans lot intermédiaire');
    });
  });

  group('les réglages viennent du registre, jamais du code', () {
    test('à défaut de fiche : le défaut de la DÉFINITION, marqué « à fixer sur la plus grande table réelle »', () {
      final r = ReglagesExport.depuisParametres((_) => null);
      expect(r.limiteLignes, isNull, reason: 'AK (16/11/2026) : aucune limite de lignes par défaut');
      expect(r.seuilProgression, definitionDeParametre(cleExportSeuilProgression)!.defaut);
      expect(r.limiteEtatsParLigne, definitionDeParametre(cleExportLimiteEtats)!.defaut);
      for (final c in [cleExportSeuilProgression]) {
        expect(definitionDeParametre(c)!.source, contains('à fixer sur la plus grande table réelle'));
        expect(definitionDeParametre(c)!.mobile, isFalse, reason: 'un réglage d\'export ne part jamais au téléphone');
      }
      expect(libellesFamillesParametres['export'], isNotNull);
    });
    test('la valeur de la base l\'emporte ; une valeur invalide retombe sur le défaut', () {
      final r = ReglagesExport.depuisParametres((c) => c == cleExportLimiteLignes ? 50 : (c == cleExportSeuilProgression ? -3 : null));
      expect(r.limiteLignes, 50);
      expect(r.seuilProgression, definitionDeParametre(cleExportSeuilProgression)!.defaut);
      expect(r.verifier(51)!.code, 'EXPORT_TROP_VOLUMINEUX');
      expect(r.verifier(50), isNull);
      expect(const ReglagesExport(limiteLignes: 10, seuilProgression: 8, limiteEtatsParLigne: 3).verifierEtats(4)!.code, 'IMPRESSION_TROP_D_ETATS');
      expect(const ReglagesExport(limiteLignes: 10, seuilProgression: 8, limiteEtatsParLigne: 3).verifierEtats(3), isNull);
    });
  });

  group('AK (Direction, 16/11/2026) : aucune limite de lignes par défaut, seul le droit compte', () {
    test('le défaut de la définition est 0 = aucune limite, sourcé par la décision', () {
      final d = definitionDeParametre(cleExportLimiteLignes)!;
      expect(d.defaut, 0);
      expect(d.source, contains('16/11/2026'));
      expect(d.mobile, isFalse);
    });
    test('sans limite fixée : dix millions de lignes ne sont jamais refusées', () {
      final r = ReglagesExport.depuisParametres((_) => null);
      expect(r.verifier(10000000), isNull);
      for (final v in [0, '', null, -5, 'abc']) {
        expect(ReglagesExport.depuisParametres((c) => c == cleExportLimiteLignes ? v : null).limiteLignes, isNull, reason: '« $v » : aucune limite');
      }
    });
    test('l’ancien semis (version 0 à 200 000) ne fixe AUCUNE limite : seule une version datée de la clinique en pose une', () {
      final semis = ReglagesExport.depuisParametres((c) => c == cleExportLimiteLignes ? 200000 : null, version: (c) => c == cleExportLimiteLignes ? 0 : null);
      expect(semis.limiteLignes, isNull);
      expect(semis.verifier(250000), isNull);
      final fixee = ReglagesExport.depuisParametres((c) => c == cleExportLimiteLignes ? 500 : null, version: (c) => c == cleExportLimiteLignes ? 1 : null);
      expect(fixee.limiteLignes, 500);
      expect(fixee.verifier(501)!.code, 'EXPORT_TROP_VOLUMINEUX');
      expect(fixee.verifier(500), isNull);
    });
    test('la production sans limite écrit toutes les lignes', () async {
      const sansLimite = ReglagesExport(limiteLignes: null, seuilProgression: 100000, limiteEtatsParLigne: 5);
      final r = await produireExport(
          colonnes: [ColonneExport(libelle: 'N', texte: (r) => '${r['n']}')],
          lignes: [for (var i = 0; i < 3000; i++) {'n': i}],
          format: FormatExport.csv,
          feuille: 'T',
          maintenant: instant,
          reglages: sansLimite);
      expect(r.ok, isTrue);
      expect(r.lignes, 3000);
    });
  });

  group('la sélection', () {
    test('cocher une, plusieurs, toutes ; conservée d\'une page à l\'autre ; vidée par l\'agent', () {
      final s = SelectionLignes();
      final page1 = ['a', 'b', 'c'], page2 = ['d', 'e', 'f'];
      s.cocher('a');
      s.definir(page2, true);
      expect(s.taille, 4);
      expect(s.toutesCochees(page1), isFalse);
      expect(s.toutesCochees(page2), isTrue);
      s.basculer('b');
      s.basculer('a');
      expect(s.ids, {'b', 'd', 'e', 'f'}, reason: 'changer de page ne perd rien');
      s.definir([...page1, ...page2], true);
      expect(s.taille, 6);
      s.vider();
      expect(s.vide, isTrue);
    });
    test('une ligne archivée entre-temps sort du compteur', () {
      final s = SelectionLignes()..definir(['a', 'b', 'c'], true);
      s.retenir({'a', 'c', 'z'});
      expect(s.ids, {'a', 'c'});
    });
  });

  group('le droit d\'exporter : un geste réservé, réglable par rôle', () {
    Map<String, Object?> fiche(String role, Map<String, Object?> g) => {'id': 'F$role', 'role': role, 'statut': 'actif', 'droitsGestes': g};
    bool voit(String role, String ecran) => role == 'caissier' ? ecran == 'm8-caisse' : true;

    test('sans décision : les rôles qui LISENT l\'écran', () {
      final d = DroitsGestes(fiches: const []);
      expect(d.peutSurEcran('caissier', gesteExporter, 'm8-caisse', peutVoirEcran: voit), isTrue);
      expect(d.peutSurEcran('caissier', gesteExporter, 'm6-stock-gros', peutVoirEcran: voit), isFalse, reason: 'écran non lu = pas d\'export');
    });
    test('une décision accorde ou retire, par rôle, pour tous les écrans', () {
      final retire = DroitsGestes(fiches: [fiche('caissier', {gesteExporter: false})]);
      expect(retire.peutSurEcran('caissier', gesteExporter, 'm8-caisse', peutVoirEcran: voit), isFalse, reason: 'lit l\'écran mais le geste lui est retiré');
      final accorde = DroitsGestes(fiches: [fiche('caissier', {gesteExporter: true})]);
      expect(accorde.peutSurEcran('caissier', gesteExporter, 'm6-stock-gros', peutVoirEcran: voit), isTrue);
      expect(accorde.peutSurEcran('medecin', gesteExporter, 'm2-consultations', peutVoirEcran: voit), isTrue, reason: 'sans décision pour lui : suit la lecture');
    });
    test('rôle archivé, vide, geste d\'un autre type : non', () {
      final d = DroitsGestes(fiches: const [], estArchive: (r) => r == 'ancien');
      expect(d.peutSurEcran('ancien', gesteExporter, 'x', peutVoirEcran: voit), isFalse);
      expect(d.peutSurEcran('', gesteExporter, 'x', peutVoirEcran: voit), isFalse);
      expect(d.peutSurEcran('da', gesteDeciderPrix, 'x', peutVoirEcran: voit), isFalse);
      expect(d.peut('da', gesteExporter), isFalse, reason: '`peut` sans écran ne devine rien pour un geste transverse');
    });
    test('le geste est au référentiel, sans nom de rôle d\'origine', () {
      final g = gesteReserve(gesteExporter)!;
      expect(g.suitEcran, isTrue);
      expect(g.rolesDefaut, isEmpty);
      expect(g.ecran, isEmpty);
    });
  });

  group('le journal (RG-12)', () {
    test('qui est écrit : portée, nombre, filtre, colonnes, format — jamais un contenu', () {
      final j = detailJournalExport(portee: PorteeExport.toutAvecFiltre, lignes: 42, filtreActif: true, colonnes: 7, format: FormatExport.xlsx);
      expect(j, {'portee': 'tout_avec_filtre', 'lignes': 42, 'filtre': 'avec', 'colonnes': 7, 'format': 'xlsx'});
      final k = detailJournalExport(portee: PorteeExport.selection, lignes: 3, filtreActif: false, colonnes: 2, refus: const RefusExport('EXPORT_TROP_VOLUMINEUX', 'm', 'g'));
      expect(k['filtre'], 'sans');
      expect(k['refus'], 'EXPORT_TROP_VOLUMINEUX');
      // aucune valeur ne peut s'y glisser : les seuls types sont texte et entier, sans texte libre
      for (final v in [...j.values, ...k.values]) {
        expect(v is int || v is String, isTrue);
      }
    });
    test('le nom de fichier n\'embarque que le nom du tableau et le jour', () {
      expect(nomFichierExport('Transferts gros → détail', DateTime(2026, 11, 15), FormatExport.xlsx), 'transferts-gros-d-tail-2026-11-15.xlsx');
      expect(nomFichierExport('', DateTime(2026, 1, 2), FormatExport.csv, selection: true), 'export-2026-01-02-selection.csv');
    });
  });
}
