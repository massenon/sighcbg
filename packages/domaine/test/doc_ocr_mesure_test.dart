// La MESURE de l'OCR et le banc de mesure (portage OCR-prep) : fixtures SYNTHÉTIQUES créées pour le test, moteurs FACTICES. Ce qui est prouvé : la mesure est juste (un moteur parfait
// donne 100 %, un moteur qui supprime les accents le montre, un moteur qui refuse n'est pas exclu), jamais la qualité d'un moteur.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import '../tool/src/mesure_dossier.dart';

final png = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

void main() {
  test('définitions : lu à l’identique 100 % ; sans accents, les accents sont tous perdus et aucun mot n’est « perdu »', () {
    final ref = 'Hyperglycémie sévère : père déjà traité à Parakou, œuf de ç.';
    final m = ocrMesurer(ref, ref);
    expect(m.tauxMots, 1);
    expect(m.tauxAccents, 1);
    final s = ocrMesurer(ref, sansDiacritiques(ref).replaceAll('œ', 'oe'));
    expect(s.tauxMots, lessThan(1));
    expect(s.tauxAccents, 0);
    expect(s.motsPerdus, 0);
    expect(s.exemplesAccents, contains('père lu pere'));
  });
  test('un mot absent est perdu (75 % sur quatre) ; sans accent en référence, le taux d’accents est sans objet ; borné à 0', () {
    final m = ocrMesurer('un deux trois quatre', 'un deux quatre');
    expect(m.tauxMots, 0.75);
    expect(m.motsPerdus, 1);
    expect(ocrMesurer('paludisme grave', 'paludisme grave').tauxAccents, isNull);
    expect(ocrMesurer('un', 'a b c d e f g h').tauxMots, 0);
  });
  test('le banc sur un dossier synthétique : parfait 100 %, sans accents le montre, un scan refusé compte pour zéro ; rapport sans mot des documents par défaut', () async {
    final dossier = Directory.systemTemp.createTempSync('sigh-ocr-banc-');
    final sortie = Directory.systemTemp.createTempSync('sigh-ocr-rapport-');
    addTearDown(() {
      dossier.deleteSync(recursive: true);
      sortie.deleteSync(recursive: true);
    });
    final textes = {
      'certificat-1': 'Certificat de démonstration : la personne fictive est guérie et reprend ses activités.',
      'ordonnance-1': 'Ordonnance de démonstration : hyperglycémie sévère, amoxicilline 500 mg, revoir à Parakou.',
    };
    var k = 0;
    for (final e in textes.entries) {
      // deux images distinctes (un octet de fin différent) : une empreinte par scan
      File('${dossier.path}/${e.key}.png').writeAsBytesSync([...png, ++k]);
      File('${dossier.path}/${e.key}.txt').writeAsStringSync(e.value);
    }
    File('${dossier.path}/sans-reference.png').writeAsBytesSync([...png, 99]);
    final r = await mesurerDossier(
        dossier: dossier.path,
        sortie: sortie.path,
        synthetique: true,
        maintenant: DateTime(2026, 11, 14),
        moteurs: (scans) => [moteurFactice('factice-parfait', scans), moteurFactice('factice-sans-accents', scans)]);
    final parfait = r.syntheses[0], sans = r.syntheses[1];
    expect(parfait.nbScans, 2);
    expect(parfait.moyenneMots, 1);
    expect(parfait.tauxAccents, 1);
    expect(sans.moyenneMots, lessThan(1));
    expect(sans.tauxAccents, 0);
    final md = File(r.rapport).readAsStringSync();
    expect(md, contains('SYNTHÉTIQUES'));
    expect(md, contains('sans-reference.png'), reason: 'un scan sans transcription est nommé, pas ignoré en silence');
    expect(md, isNot(contains('Parakou')), reason: 'aucun mot des documents dans le rapport par défaut');
    expect(jsonDecode(File(r.rapport.replaceAll('.md', '.json')).readAsStringSync()), isA<Map>());
  });
}
