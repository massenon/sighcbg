// LE CLIQUET « VALEURS EN DUR », familles B (taux et montants) et H (barèmes figés) — lot 1 de docs/architecture/INVENTAIRE-VALEURS-EN-DUR.md (§ 4.2).
//
// Le balayage est celui de `tools/baguidi/inventaire-en-dur.mjs` (le même détecteur que le rapport à la Direction) ; la ligne de base vit dans
// `tools/baguidi/valeurs-en-dur.plafonds.json`, un plafond et un MOTIF par fichier toléré. Le cliquet échoue si une valeur en dur APPARAÎT, si un fichier passe sous
// son plafond sans que la ligne de base soit abaissée, ou si un fichier toléré n'a pas de motif. Ce test le rejoue sur le dépôt, puis sur trois lignes de base
// falsifiées pour prouver qu'il voit chacun des trois écarts.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _script = '../../tools/baguidi/inventaire-en-dur.mjs';
const _plafonds = '../../tools/baguidi/valeurs-en-dur.plafonds.json';

Future<ProcessResult> _cliquet([String? plafonds]) =>
    Process.run('node', [_script, '--cliquet', '--famille=B,H', if (plafonds != null) ...['--plafonds', plafonds]]);

void main() {
  late Map<String, Object?> base;
  late Directory tmp;
  setUpAll(() {
    base = (jsonDecode(File(_plafonds).readAsStringSync()) as Map).cast<String, Object?>();
    tmp = Directory.systemTemp.createTempSync('cliquet-en-dur');
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> familles(Map<String, Object?> b) => (b['familles'] as Map).cast<String, Object?>();
  String ecrire(String nom, Map<String, Object?> b) {
    final f = File('${tmp.path}/$nom.json')..writeAsStringSync(jsonEncode(b));
    return f.path;
  }

  Map<String, Object?> copie() => (jsonDecode(jsonEncode(base)) as Map).cast<String, Object?>();

  test('la ligne de base surveille B et H, et chaque fichier toléré dit pourquoi', () {
    expect(familles(base).keys.toSet(), {'B', 'H', 'E'}, reason: 'E (numérotation, lot 2) est sous cliquet à plafond zéro : aucun fichier toléré');
    expect((familles(base)['E'] as Map), isEmpty);
    for (final f in familles(base).entries) {
      for (final e in (f.value as Map).entries) {
        final t = (e.value as Map);
        expect(t['plafond'], isA<int>(), reason: '${f.key} ${e.key}');
        expect((t['plafond'] as int) > 0, isTrue, reason: '${f.key} ${e.key} : un plafond nul se retire de la ligne de base');
        expect('${t['motif'] ?? ''}'.trim(), isNotEmpty, reason: '${f.key} ${e.key}');
      }
    }
    // Le lot 1 a vidé la paie et le fiscal : aucun de leurs fichiers n'est toléré.
    final toleres = [for (final f in familles(base).values) ...(f as Map).keys.cast<String>()];
    for (final lot1 in ['paie/pai_moteur.dart', 'paie/pai_baremes.dart', 'configuration/confirmations_fiscales.dart', 'rh/rhc_regles.dart', 'rh/rhb_regles.dart', 'administration/adm_regles.dart']) {
      expect(toleres.where((x) => x.endsWith(lot1)), isEmpty, reason: lot1);
    }
  });

  test('le dépôt est conforme à sa ligne de base', () async {
    final r = await _cliquet();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stdout}', contains('conforme'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('une valeur en dur qui APPARAÎT fait échouer le cliquet, en nommant le fichier', () async {
    final b = copie();
    final fb = (familles(b)['B'] as Map);
    final fichier = fb.keys.first as String;
    fb.remove(fichier); // plafond implicite : zéro
    final r = await _cliquet(ecrire('apparue', b));
    expect(r.exitCode, 1);
    expect('${r.stderr}', allOf(contains(fichier), contains('APPARUE')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('un fichier sous son plafond oblige à ABAISSER la ligne de base ; un fichier toléré sans motif est refusé', () async {
    final b = copie();
    final fh = (familles(b)['H'] as Map);
    final fichier = fh.keys.first as String;
    final t = (fh[fichier] as Map);
    t['plafond'] = (t['plafond'] as int) + 1;
    final r = await _cliquet(ecrire('abaisser', b));
    expect(r.exitCode, 1);
    expect('${r.stderr}', allOf(contains(fichier), contains('ABAISSER')));

    final c = copie();
    ((familles(c)['H'] as Map)[fichier] as Map)['motif'] = ' ';
    final r2 = await _cliquet(ecrire('sansmotif', c));
    expect(r2.exitCode, 1);
    expect('${r2.stderr}', allOf(contains(fichier), contains('SANS MOTIF')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  // LES COMPLÉMENTS DU LOT 1 (relevés par l'inventaire de la clinique sœur) : le détecteur heuristique ne voit pas tout (un « 0.02 » est sous son seuil, un taux à
  // côté d'un mot qu'il ne connaît pas lui échappe). Ces gardes lisent le CODE (commentaires retirés) et interdisent que la valeur réapparaisse ailleurs que dans sa graine.
  group('les valeurs du lot 1 n’existent qu’à UN endroit : leur graine', () {
    final racines = ['lib', '../../apps/poste/lib', '../../apps/mobile/lib', '../sync_dart/lib'];
    final sources = <String, List<String>>{};
    setUpAll(() {
      for (final r in racines) {
        final d = Directory(r);
        if (!d.existsSync()) continue;
        for (final f in d.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
          sources[f.path] = [for (final l in f.readAsLinesSync()) l.replaceFirst(RegExp(r'//.*$'), '')];
        }
      }
    });
    List<(String, int, String)> occurrences(RegExp motif, {bool Function(String chemin)? dans}) => [
          for (final e in sources.entries)
            if (dans == null || dans(e.key))
              for (var i = 0; i < e.value.length; i++)
                if (motif.hasMatch(e.value[i])) (e.key, i + 1, e.value[i].trim())
        ];

    test('CNSS 3,6 % / 16,4 % : seule la graine (pai_baremes.dart) les écrit', () {
      expect(occurrences(RegExp(r'(^|[^0-9.])(3\.6|16\.4)([^0-9]|$)'), dans: (p) => !p.endsWith('paie/pai_baremes.dart')), isEmpty);
    });
    test('barème de l’ITS : aucune tranche recopiée hors de la graine', () {
      expect(occurrences(RegExp(r'\b(150001|250001|500001)\b'), dans: (p) => !p.endsWith('paie/pai_baremes.dart')), isEmpty);
    });
    test('prime d’ancienneté « 2 % dès 2 ans » : plus aucune copie en dur dans la paie ni les RH', () {
      expect(occurrences(RegExp(r'0\.02\b'), dans: (p) => RegExp(r'(src/paie|src/rh|modules/m10|modules/m11)/').hasMatch(p)), isEmpty);
      expect(occurrences(RegExp(r'ans\s*>=\s*2\b'), dans: (p) => RegExp(r'(src/paie|src/rh|modules/m10|modules/m11)/').hasMatch(p)), isEmpty);
    });
    test('CCIB 300 000 : un seul littéral, la graine du paramètre (cfb_donnees.dart)', () {
      expect(
          occurrences(RegExp(r'\b300000\b'),
              dans: (p) => !p.endsWith('configuration/cfb_donnees.dart') && !p.endsWith('comptabilite/cpc_donnees.dart') && !p.endsWith('assurances/ass_regles.dart')),
          isEmpty,
          reason: 'cpc_donnees : le classeur 2025 cité ; ass_regles : un plafond de garantie, sans rapport');
    });
    test('ORTB : le pilotage ne recalcule plus avec ses propres montants', () {
      expect(occurrences(RegExp(r'\b(1000|3000)\b'), dans: (p) => p.endsWith('pilotage/pil_stats.dart')), isEmpty);
    });
  });
}
