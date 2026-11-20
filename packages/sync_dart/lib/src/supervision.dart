/// SUPERVISION DU POSTE MÈRE (spec §13) : ce que le « PC du serveur local » doit surveiller seul — base, disque,
/// sauvegarde, retard des postes, liaison au relais, horloges, conflits. Chaque contrôle rend un état NOMMÉ
/// (`ok` · `attention` · `alerte` · `inconnu`) et une phrase lisible : jamais un voyant muet, jamais un « inconnu » qui se
/// fait passer pour « ok ». Les seuils sont des PROPOSITIONS (à valider sur le matériel réel de la clinique).
library;

import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart' show MereSeuilsSupervision, mereSeuilsSupervisionA, parametreDateIso;

import 'commun.dart';
import 'depot.dart';
import 'mere.dart';
import 'reglages_mere.dart';

/// Les seuils de la supervision : des RÉGLAGES de la mère (famille `mere`, versions datées, bornés ; propositions à valider sur le matériel réel). La classe ne porte AUCUNE valeur :
/// [Seuils.depuis] les lit au registre, [Seuils.attente] donne les valeurs d'attente des définitions (aucune fiche lue).
class Seuils {
  const Seuils._(this._s);

  final MereSeuilsSupervision _s;

  /// Les valeurs d'attente semées (aucun réglage lu) : le comportement d'avant.
  factory Seuils.attente() => Seuils._(mereSeuilsSupervisionA(const [], parametreDateIso(DateTime.now())));

  /// Les seuils EN VIGUEUR dans la base de la mère à [maintenant].
  static Future<Seuils> depuis(Depot base, DateTime maintenant) async => Seuils._(await seuilsSupervisionMere(base, maintenant));

  /// Les seuils tirés de fiches de versions déjà lues (essais, console).
  factory Seuils.desFiches(Iterable<Map<String, Object?>> fiches, String date) => Seuils._(mereSeuilsSupervisionA(fiches, date));

  int get disqueAttentionOctets => _s.disqueAttentionOctets;
  int get disqueAlerteOctets => _s.disqueAlerteOctets;
  int get sauvegardeAttentionHeures => _s.sauvegardeAttentionHeures;
  int get sauvegardeAlerteHeures => _s.sauvegardeAlerteHeures;
  int get posteSilenceAttentionMin => _s.posteSilenceAttentionMin;
  int get posteSilenceAlerteMin => _s.posteSilenceAlerteMin;
  int get posteRetardOperations => _s.posteRetardOperations;
  int get relaisRetardAttention => _s.relaisRetardAttention;
  int get relaisRetardAlerte => _s.relaisRetardAlerte;
  int get deriveHorlogeMin => _s.deriveHorlogeMin;
}

Map<String, Object?> _controle(String nom, String etat, String detail, [Object? valeur]) =>
    {'nom': nom, 'etat': etat, 'detail': detail, 'valeur': ?valeur};

/// Octets libres du disque qui porte le dossier courant, ou `null` si la plateforme ne le dit pas.
Future<int?> octetsLibres() async {
  try {
    if (Platform.isWindows) {
      final r = await Process.run('powershell', ['-NoProfile', '-Command', '[IO.DriveInfo]::new((Get-Location).Drive.Name).AvailableFreeSpace']);
      return int.tryParse('${r.stdout}'.trim());
    }
    final r = await Process.run('df', ['-Pk', '.']);
    final lignes = '${r.stdout}'.trim().split('\n');
    if (lignes.length < 2) return null;
    final disponible = int.tryParse(lignes.last.trim().split(RegExp(r'\s+'))[3]);
    return disponible == null ? null : disponible * 1024;
  } catch (_) {
    return null;
  }
}

String _taille(int o) => o >= 1 << 30 ? '${(o / (1 << 30)).toStringAsFixed(1)} Go' : '${(o / (1 << 20)).toStringAsFixed(0)} Mo';

Future<List<Map<String, Object?>>> controlesMere(Mere m, {Seuils? seuils, int? disqueLibre}) async {
  final out = <Map<String, Object?>>[];
  final base = m.base;
  final maintenant = maintenantMs();
  // Les seuils sont ceux du registre daté de la mère (réglages `mere.supervision*`), sauf si l'appelant en impose (essais).
  // Une base illisible n'empêche pas le contrôle de le dire (« Base de données : alerte ») : les seuils retombent alors sur leurs valeurs d'attente.
  Seuils seuilsEnForce;
  try {
    seuilsEnForce = seuils ?? await Seuils.depuis(base, DateTime.fromMillisecondsSinceEpoch(maintenant));
  } catch (_) {
    seuilsEnForce = Seuils.attente();
  }

  // 1. base de données
  final t0 = DateTime.now();
  try {
    await base.select('SELECT 1 AS un');
    final ms = DateTime.now().difference(t0).inMilliseconds;
    out.add(_controle('Base de données', ms > 1000 ? 'attention' : 'ok', '${base.dialecte == 'pg' ? 'PostgreSQL' : 'SQLite'} répond en $ms ms.', ms));
  } catch (e) {
    out.add(_controle('Base de données', 'alerte', 'La base ne répond pas : $e'));
  }

  // 2. espace disque
  final libre = disqueLibre ?? await octetsLibres();
  if (libre == null) {
    out.add(_controle('Espace disque', 'inconnu', 'Non mesurable sur cette plateforme.'));
  } else {
    final etat = libre < seuilsEnForce.disqueAlerteOctets ? 'alerte' : (libre < seuilsEnForce.disqueAttentionOctets ? 'attention' : 'ok');
    out.add(_controle('Espace disque', etat, '${_taille(libre)} libres.', libre));
  }

  // 3. sauvegarde quotidienne
  final derniere = await base.metaInt('derniere_sauvegarde');
  if (derniere == 0) {
    out.add(_controle('Sauvegarde', 'alerte', 'Aucune sauvegarde n\'a jamais été faite.'));
  } else {
    final h = (maintenant - derniere) / 3600000;
    final etat = h > seuilsEnForce.sauvegardeAlerteHeures ? 'alerte' : (h > seuilsEnForce.sauvegardeAttentionHeures ? 'attention' : 'ok');
    out.add(_controle('Sauvegarde', etat, 'Dernière sauvegarde il y a ${h.toStringAsFixed(1)} h.', derniere));
  }

  // 4. postes : silence et retard de synchronisation
  final seq = await m.seqMax();
  for (final a in await base.select("SELECT uuid,etiquette,role,dernier_contact,dernier_seq,derive_ms FROM appareils WHERE etat='actif' AND role<>'mobile' ORDER BY etiquette")) {
    final nom = '${a['etiquette'] ?? ''}'.isEmpty ? '${a['uuid']}' : '${a['etiquette']}';
    final contact = a['dernier_contact'] as int?;
    final retard = seq - (a['dernier_seq'] as int);
    if (contact == null) {
      out.add(_controle('Poste « $nom »', 'attention', 'Jamais vu depuis son appairage.'));
      continue;
    }
    final silence = (maintenant - contact) / 60000;
    var etat = 'ok';
    var detail = 'Vu il y a ${silence.toStringAsFixed(0)} min, retard ${retard.clamp(0, 1 << 30)} opération(s).';
    if (silence > seuilsEnForce.posteSilenceAlerteMin) {
      etat = 'alerte';
      detail = 'Silencieux depuis ${(silence / 60).toStringAsFixed(1)} h — poste éteint, hors réseau ou en panne ?';
    } else if (silence > seuilsEnForce.posteSilenceAttentionMin || retard > seuilsEnForce.posteRetardOperations) {
      etat = 'attention';
    }
    if ((a['derive_ms'] as int) > seuilsEnForce.deriveHorlogeMin * 60 * 1000) {
      etat = etat == 'alerte' ? 'alerte' : 'attention';
      detail += ' Horloge à vérifier (dérive ${((a['derive_ms'] as int) / 60000).toStringAsFixed(0)} min).';
    }
    out.add(_controle('Poste « $nom »', etat, detail));
  }

  // 5. liaison au relais en ligne
  if (!m.pont.actif) {
    out.add(_controle('Relais en ligne', 'inconnu', 'Aucun relais configuré : pas de copie hors site ni de mobiles.'));
  } else {
    final retard = seq - await base.metaInt('rep_seq');
    final dernierOk = await base.metaInt('relais_dernier_ok');
    final silence = dernierOk == 0 ? null : (maintenant - dernierOk) / 60000;
    var etat = retard > seuilsEnForce.relaisRetardAlerte ? 'alerte' : (retard > seuilsEnForce.relaisRetardAttention ? 'attention' : 'ok');
    var detail = '$retard opération(s) pas encore répliquées (chiffrées) vers le relais.';
    if (silence != null && silence > 5) {
      etat = 'alerte';
      detail += ' Aucun échange réussi depuis ${silence.toStringAsFixed(0)} min : Internet ou relais hors service.';
    }
    out.add(_controle('Relais en ligne', etat, detail, retard));
  }

  // 6. enveloppes altérées ou manquantes, appareils bloqués
  final bloques = await base.select("SELECT k FROM meta WHERE k LIKE 'bloque:%' AND v<>''");
  out.add(bloques.isEmpty
      ? _controle('Intégrité des enveloppes', 'ok', 'Aucune enveloppe altérée ni manquante.')
      : _controle('Intégrité des enveloppes', 'alerte', '${bloques.length} appareil(s) bloqué(s) : enveloppe altérée ou rang manquant — à examiner à la console.', bloques.length));

  // 7. conflits à arbitrer
  final conflits = (await base.select("SELECT COUNT(*) AS n FROM conflits WHERE etat='ouvert'")).first['n'] as int;
  out.add(_controle('Conflits à régulariser', conflits == 0 ? 'ok' : (conflits > 20 ? 'alerte' : 'attention'), conflits == 0 ? 'Aucun conflit ouvert.' : '$conflits conflit(s) attendent un arbitrage.', conflits));

  // 8. erreurs internes récentes (24 h)
  final erreurs = (await base.select("SELECT COUNT(*) AS n FROM evenements WHERE niveau='erreur' AND quand>?", [maintenant - 24 * 3600 * 1000])).first['n'] as int;
  out.add(_controle('Erreurs internes (24 h)', erreurs == 0 ? 'ok' : (erreurs > 10 ? 'alerte' : 'attention'), erreurs == 0 ? 'Aucune erreur interne.' : '$erreurs erreur(s) interne(s) — voir le journal.', erreurs));
  return out;
}

/// Le pire état rencontré : `alerte` > `attention` > `inconnu` > `ok`. Un « inconnu » ne rassure jamais.
String etatGlobal(List<Map<String, Object?>> controles) {
  const ordre = ['ok', 'inconnu', 'attention', 'alerte'];
  var pire = 0;
  for (final c in controles) {
    final i = ordre.indexOf('${c['etat']}');
    if (i > pire) pire = i;
  }
  return ordre[pire];
}
