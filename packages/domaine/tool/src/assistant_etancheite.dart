/// Contrôle d'ÉTANCHÉITÉ des sources de l'assistant (lots AST-0 et AST-1) : une source qui importe autre chose que `dart:core`, `dart:convert` et ses voisines du domaine, qui
/// dépend d'un paquet réseau, ou qui nomme un client, un serveur, une socket ou un processus, est signalée. Ce fichier NOMME ces jetons : il n'est donc pas lui-même
/// soumis au contrôle (il ne s'exécute que dans les tests et le lanceur).
library;

/// Les violations d'étanchéité d'une SOURCE. [permis] : importations `dart:` autorisées en plus de `dart:core` (le lanceur lit des fichiers : `dart:io`, jamais de socket).
List<String> controleEtancheite(String source, {Set<String> permis = const {'dart:core', 'dart:convert'}}) {
  final v = <String>[];
  for (final m in RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''', multiLine: true).allMatches(source)) {
    final cible = m.group(1)!;
    if (cible.startsWith('dart:') && !permis.contains(cible)) v.add('importation interdite : $cible');
    if (cible.startsWith('package:') && !cible.startsWith('package:test/') && !cible.startsWith('package:sigh_domaine/')) v.add('dépendance de paquet interdite : $cible');
  }
  const jetons = [
    'Socket', 'HttpClient', 'HttpServer', 'WebSocket', 'RawDatagramSocket', 'Process.', 'Isolate.', 'InternetAddress', 'HttpOverrides.global', 'http://', 'https://', 'package:http', 'dart:io', 'dart:html',
    'dart:isolate', 'File(', 'Directory(',
  ];
  final code = source.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
  for (final j in jetons) {
    if (code.contains(j) && !permis.contains(j)) v.add('jeton réseau, fichier ou processus : $j');
  }
  return v;
}

/// Les jetons d'ÉCRITURE au magasin : une source de l'assistant qui en contient un échoue. L'assistant lit, il n'écrit pas.
List<String> controleLectureSeule(String source) {
  const jetons = ['.inserer(', '.mettreAJour(', '.archiver(', '.restaurer(', '.ajouterSansJournal(', '.remplacerContenu(', '.retirerChamp(', '.appliquerDistante(', '.sansGardes(', 'journaliser('];
  final code = source.split('\n').where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///')).join('\n');
  return [for (final j in jetons) if (code.contains(j)) 'écriture : $j'];
}
