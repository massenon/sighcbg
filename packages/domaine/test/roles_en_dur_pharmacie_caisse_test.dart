// CLIQUET « AUCUN RÔLE EN DUR » DE LA PHARMACIE ET DE LA CAISSE (Direction de Baguidi, 16/11/2026). Aujourd'hui la Caissière-Dispensatrice tient les deux et le rôle pharmacien
// reste ouvert ; en production, la clinique peut séparer un pharmacien de la caisse. Rien dans ces fichiers ne doit donc décider d'un droit sur un NOM DE RÔLE : encaisser et délivrer
// sont des droits d'ÉCRAN de la matrice, le reste (routage des alertes, retransmission MECeF) des GESTES RÉSERVÉS de la fiche de rôle.
//
// Le contrôle cherche les formes d'une DÉCISION écrite sur un identifiant de rôle (lu dans `rbac.json`, un rôle ajouté demain est donc cherché aussi) : comparaison (`== 'caissier'`),
// appartenance (`.contains('pharmacien')`), liste ou ensemble littéral (`['stock', 'da']`), argument nommé (`role: 'caissier'`). Les accès à un champ (`p['stock']`) et les clés de
// table (`'poste': 'stock'`) n'en sont pas. Les lignes de commentaire sont ignorées.
//
// Les PLAFONDS ci-dessous ne peuvent que DÉCROÎTRE : un littéral de plus fait échouer le test ; un de moins aussi, pour que le plafond soit abaissé et que la place libérée ne
// serve pas à un autre. Un fichier du périmètre absent de la table a un plafond de ZÉRO.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Le périmètre : la pharmacie, la dispensation, la délivrance, le stock de détail et la caisse (domaine et poste).
const _perimetre = [
  'lib/src/caisse',
  'lib/src/stock',
  'lib/src/mecef',
  'lib/src/consultation/cs_moteur.dart',
  '../../apps/poste/lib/modules/m6',
  '../../apps/poste/lib/modules/m8',
  '../../apps/poste/lib/modules/mecef',
  '../../apps/poste/lib/donnees/parcours_caisse.dart',
  '../../apps/poste/lib/donnees/normalisation_mecef.dart',
  '../../apps/poste/lib/shell/centre_notifications.dart',
];

/// Les littéraux TOLÉRÉS, fichier par fichier, et pourquoi. Liste fermée : elle ne fait que décroître.
const _plafonds = <String, int>{
  // (1) `_tachesDef` : le champ descriptif `role` des tâches d'aval (caissier, pharmacien, laborantin, infirmier, échographiste), porté par les VECTEURS de la maquette
  // (`consultation.json`, `transcription_mobile.json`) ; AUCUN code ne le lit pour décider d'un droit (la file d'attente filtre par TYPE de tâche et par les droits de l'écran).
  // (2) `capacite == 'chirurgien' || session.role == 'chirurgien'` : les rubriques chirurgicales du dossier, hors pharmacie et caisse.
  'lib/src/consultation/cs_moteur.dart': 7,
  // Les postes de notification HORS pharmacie et caisse (comptable, direction, imagerie, laboratoire, prescripteur, salle de soins, hospitalisation) et les sources des
  // autres domaines (laboratoire, besoins, échéances fiscales, créances, synchronisation, couvertures, conflits). La caisse, le stock, le seuil d'alerte, la péremption et
  // le rejet MECeF sont des gestes réservés depuis le 16/11/2026.
  '../../apps/poste/lib/shell/centre_notifications.dart': 48,
};

List<String> _fichiers() {
  final out = <String>[];
  for (final p in _perimetre) {
    if (p.endsWith('.dart')) {
      if (File(p).existsSync()) out.add(p);
      continue;
    }
    for (final e in Directory(p).listSync(recursive: true).whereType<File>()) {
      if (e.path.endsWith('.dart')) out.add(e.path);
    }
  }
  return out..sort();
}

/// Les littéraux de rôle qui ont la forme d'une décision, ligne par ligne (`ligne:rôle`).
List<String> rolesEnDur(String source, List<String> roles) {
  final alt = roles.map(RegExp.escape).join('|');
  final index = RegExp(r"(?<=[\w\)\]\?!])\[\s*'[^']*'\s*\]");
  final formes = [
    RegExp("[=!]=\\s*'($alt)'"),
    RegExp("'($alt)'\\s*[=!]="),
    RegExp("\\.contains\\(\\s*'($alt)'\\s*\\)"),
    RegExp("(?<=[\\[{,])\\s*'($alt)'(?=\\s*[,\\]}])"),
    RegExp("\\brole\\w*\\s*:\\s*'($alt)'"),
  ];
  final out = <String>[];
  final lignes = const LineSplitter().convert(source);
  for (var i = 0; i < lignes.length; i++) {
    if (lignes[i].trimLeft().startsWith('//')) continue;
    final l = lignes[i].replaceAll(index, '');
    final vus = <int>{};
    for (final f in formes) {
      for (final m in f.allMatches(l)) {
        final debut = m.start + m.group(0)!.indexOf("'${m.group(1)}'");
        if (vus.add(debut)) out.add('${i + 1}:${m.group(1)}');
      }
    }
  }
  return out;
}

void main() {
  final rbac = (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
  final roles = [for (final r in rbac['roles'] as List) '${(r as Map)['id']}'];

  test('le détecteur reconnaît une décision écrite sur un rôle, et pas un champ ni une clé de table', () {
    expect(rolesEnDur("if (role == 'caissier') {}", roles), ['1:caissier']);
    expect(rolesEnDur("const ['stock', 'pharmacien'].contains(r)", roles), ['1:stock', '1:pharmacien']);
    expect(rolesEnDur("x.contains('pharmacien')", roles), ['1:pharmacien']);
    expect(rolesEnDur("(role: 'caissier', module: 'M8')", roles), ['1:caissier']);
    expect(rolesEnDur("final s = p['stock'] + q['da'];", roles), isEmpty);
    expect(rolesEnDur("{'poste': 'stock', 'type': 'x'}", roles), isEmpty);
    expect(rolesEnDur("// if (role == 'caissier')", roles), isEmpty);
    expect(rolesEnDur("if (role == 'un_role_qui_n_existe_pas') {}", roles), isEmpty);
  });

  test('CLIQUET : aucun nouveau nom de rôle en dur dans la pharmacie et la caisse ; les plafonds ne font que décroître', () {
    final ecarts = <String>[];
    final vus = <String>{};
    for (final f in _fichiers()) {
      final cle = f.replaceAll('\\', '/');
      vus.add(cle);
      final trouves = rolesEnDur(File(f).readAsStringSync(), roles);
      final plafond = _plafonds[cle] ?? 0;
      if (trouves.length > plafond) {
        ecarts.add('$cle : ${trouves.length} littéral(aux) de rôle pour un plafond de $plafond (${trouves.join(', ')}). '
            'Décider sur la matrice (droit d’écran) ou sur un geste réservé (`gestesReserves`), jamais sur un nom de rôle.');
      } else if (trouves.length < plafond) {
        ecarts.add('$cle : ${trouves.length} littéral(aux) pour un plafond de $plafond : ABAISSER le plafond (le cliquet ne remonte jamais).');
      }
    }
    for (final k in _plafonds.keys) {
      if (!vus.contains(k)) ecarts.add('$k : fichier du plafond introuvable dans le périmètre (retiré ou déplacé : retirer sa ligne).');
    }
    expect(ecarts, isEmpty, reason: ecarts.join('\n'));
  });
}
