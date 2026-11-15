/// MESURE de la compréhension de l'assistant (lot AST-0), pour la Clinique Baguidi. Un outil de mesure : aucun réseau, aucun modèle, aucune dépendance nouvelle. Il mesure
/// le MÊME moteur que le poste (`ReconnaisseurAst`).
///
///   dart run tool/mesure_assistant.dart                       rapport complet (Markdown et JSON) dans ./rapport-assistant
///   dart run tool/mesure_assistant.dart --sortie <dossier>    où écrire le rapport
///   dart run tool/mesure_assistant.dart --tableau             le bloc engendré du tableau de couverture, sur la sortie standard
///   dart run tool/mesure_assistant.dart --matrice             le bloc engendré de la matrice de droits, sur la sortie standard
///   dart run tool/mesure_assistant.dart --droits <fichier>    (re)engendre les vecteurs de droits depuis rbac.json
///   dart run tool/mesure_assistant.dart --reglage             n'affiche que les échecs du jeu de RÉGLAGE (le contrôle reste caché pendant le réglage)
library;

import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'src/assistant_mesure.dart';

Map<String, Object?> _json(String chemin) => (jsonDecode(File(chemin).readAsStringSync()) as Map).cast<String, Object?>();

void main(List<String> args) {
  String? valeur(String nom) {
    final i = args.indexWhere((a) => a == '--$nom');
    if (i >= 0 && i + 1 < args.length) return args[i + 1];
    final p = args.where((a) => a.startsWith('--$nom=')).firstOrNull;
    return p?.substring(nom.length + 3);
  }

  final rbac = _json(valeur('rbac') ?? '../rbac/data/rbac.json');
  final questions = [for (final q in (_json(valeur('questions') ?? 'test/vecteurs/assistant_questions.json')['questions'] as List)) (q as Map).cast<String, Object?>()];
  final profils = {for (final e in ((_json('test/vecteurs/assistant_profils.json')['profils']) as Map).entries) '${e.key}': '${e.value}'};
  final cat = CatalogueAst();

  if (args.contains('--tableau')) {
    stdout.write(tableauCouverture(cat));
    return;
  }
  if (args.contains('--matrice')) {
    stdout.write(tableauDroits(matriceDroits(rbac, cat, profils), profils.keys.toList()));
    return;
  }
  if (valeur('droits') != null) {
    File(valeur('droits')!).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
      '_doc': 'ENGENDRÉ par `dart run tool/mesure_assistant.dart --droits` depuis packages/rbac/data/rbac.json et le catalogue de l\'assistant : ne pas éditer. Pour chaque intention, les écrans de lecture (un parmi) et, par profil type, le droit de lecture.',
      'profils': profils,
      'matrice': matriceDroits(rbac, cat, profils),
    }));
    stdout.writeln('Vecteurs de droits écrits : ${valeur('droits')}');
    return;
  }

  final moteur = ReconnaisseurAst(cat);
  final m = mesurer(questions, moteur);
  if (args.contains('--reglage')) {
    stdout.writeln('RÉGLAGE : ${pct(m.reglage)} (${m.compte((q) => jeuDe(q['n'] as int) == 'reglage', seulementOk: true)}/${m.compte((q) => jeuDe(q['n'] as int) == 'reglage')})');
    for (final (q, j) in m.echecs) {
      if (jeuDe(q['n'] as int) == 'reglage') stdout.writeln('  ${q['n']} « ${q['question']} » : ${j.raison}');
    }
    for (final (q, j) in m.echecsParametres) {
      if (jeuDe(q['n'] as int) == 'reglage') stdout.writeln('  [paramètre] ${q['n']} « ${q['question']} » : ${j.raisonParams}');
    }
    return;
  }
  final temps = mesurerTemps(questions, moteur, repetitions: int.tryParse(valeur('repetitions') ?? '') ?? 50);
  final matrice = matriceDroits(rbac, cat, profils);
  final rapport = rapportMarkdown(m, temps, cat, rbac, matrice, questions, profils);
  final sortie = Directory(valeur('sortie') ?? 'rapport-assistant')..createSync(recursive: true);
  File('${sortie.path}/rapport-assistant.md').writeAsStringSync(rapport);
  File('${sortie.path}/rapport-assistant.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
    'global': m.global, 'reglage': m.reglage, 'controle': m.controle, 'inventees': m.inventees,
    'tempsMoyenUs': temps.moyenneUs, 'tempsPireUs': temps.pireUs,
    'echecs': [for (final e in m.echecs) {'n': e.$1['n'], 'question': e.$1['question'], 'raison': e.$2.raison}],
  }));
  stdout.writeln(rapport);
}

String rapportMarkdown(ResultatMesure m, ({double moyenneUs, int pireUs, String pireQuestion}) temps, CatalogueAst cat, Map<String, Object?> rbac, List<Map<String, Object?>> matrice,
    List<Map<String, Object?>> questions, Map<String, String> profils) {
  final b = StringBuffer();
  final ids = cat.intentions.keys.toList()..sort();
  b.writeln('# Mesure de la reconnaissance de l\'assistant (lot AST-0, Clinique Baguidi)');
  b.writeln();
  b.writeln('Date de référence : 2026-11-14. Questions : ${questions.length} (écrites pour Baguidi, NON collectées sur le terrain). Aucun modèle, aucun réseau.');
  b.writeln();
  b.writeln('## Taux de bonne intention');
  b.writeln();
  b.writeln('| Jeu | Questions | Réussies | Taux |');
  b.writeln('|---|---|---|---|');
  for (final (nom, f) in <(String, bool Function(Map<String, Object?>))>[
    ('Global', (q) => true),
    ('Réglage (n impair)', (q) => jeuDe(q['n'] as int) == 'reglage'),
    ('Contrôle (n pair)', (q) => jeuDe(q['n'] as int) == 'controle'),
    ('Lecture (75)', (q) => q['limite'] != true),
    ('Cas limites (25)', (q) => q['limite'] == true),
  ]) {
    b.writeln('| $nom | ${m.compte(f)} | ${m.compte(f, seulementOk: true)} | ${pct(m.taux(f))} |');
  }
  b.writeln();
  b.writeln('Réponses inventées (valeur de réponse produite, paramètre non lu dans la question, intention hors catalogue) : **${m.inventees}**.');
  b.writeln();
  b.writeln('## Par intention');
  b.writeln();
  b.writeln('| Intention | Réussies | Questions | Taux |');
  b.writeln('|---|---|---|---|');
  final pi = m.parIntention(ids);
  for (final id in ids) {
    final (ok, tot) = pi[id]!;
    b.writeln('| $id ${cat[id]!.libelle} | $ok | $tot | ${tot == 0 ? 'sans question' : pct(ok / tot)} |');
  }
  b.writeln();
  b.writeln('## Échecs (${m.echecs.length})');
  b.writeln();
  if (m.echecs.isEmpty) {
    b.writeln('Aucun.');
  } else {
    b.writeln('| N° | Jeu | Question | Cause | Raison |');
    b.writeln('|---|---|---|---|---|');
    for (final (q, j) in m.echecs) {
      final i = questions.indexOf(q);
      b.writeln('| ${q['n']} | ${jeuDe(q['n'] as int)} | ${q['question']} | ${causeEchec(q, m.reconnaissances[i])} | ${j.raison} |');
    }
  }
  b.writeln();
  final avecParams = m.questions.where((q) => q['parametres'] != null).length;
  b.writeln('## Paramètres typés');
  b.writeln();
  b.writeln('Vecteurs qui déclarent des paramètres : $avecParams ; exacts : ${avecParams - m.echecsParametres.length}.');
  for (final (q, j) in m.echecsParametres) {
    b.writeln('- ${q['n']} « ${q['question']} » : ${j.raisonParams}');
  }
  b.writeln();
  b.writeln('## Temps de reconnaissance');
  b.writeln();
  b.writeln('Moyenne : ${temps.moyenneUs.toStringAsFixed(1)} µs par question ; pire cas : ${temps.pireUs} µs (« ${temps.pireQuestion} »). Machine virtuelle Dart (JIT) du conteneur, pas un vieux poste.');
  b.writeln();
  b.writeln('## Robustesse (la même question abîmée)');
  b.writeln();
  b.writeln('| Variante | Réaction inchangée | Questions | Taux |');
  b.writeln('|---|---|---|---|');
  for (final e in mesurerRobustesse(questions, ReconnaisseurAst(cat)).entries) {
    b.writeln('| ${e.key} | ${e.value.$1} | ${e.value.$2} | ${pct(e.value.$1 / e.value.$2)} |');
  }
  b.writeln();
  b.writeln('## Droits');
  b.writeln();
  final sans = [for (final l in matrice) if ((l['profils'] as Map).values.any((v) => v == false)) l['intention']];
  b.writeln('Intentions où au moins un profil type n\'a pas le droit : ${sans.length} sur ${ids.length}.');
  b.writeln();
  final inco = incoherencesProfils(questions, rbac, cat, profils);
  b.writeln('Questions dont le profil type n\'a PAS le droit de lecture d\'après rbac.json (${inco.length}) :');
  for (final i in inco) {
    b.writeln('- ${i['n']} « ${i['question']} » (profil ${i['profil']}, rôle ${i['role']}, ${i['intention']}, écrans ${i['ecrans']})');
  }
  b.writeln();
  b.writeln('Droits manquants :');
  for (final d in droitsManquants(rbac, cat)) {
    b.writeln('- ${d['code']} (${d['intentions']}) : ${d['libelle']}');
  }
  return b.toString();
}
