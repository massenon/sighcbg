import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../donnees/magasin.dart';
import 'service_parametres.dart';

/// LE SERVICE DE POSTE DE L'ASSISTANT (lot AST-1). Il ne décide rien : les règles (reconnaissance, droits, purge) sont dans `packages/domaine/lib/src/assistant/`.
/// Ce fichier donne à ces règles un DISQUE et une CLÉ :
///
///  * la conversation est PROPRE au poste et à l'agent : un fichier par agent, sous `assistant/` du dossier des données de CE poste, jamais dans le magasin — donc ni
///    journal d'opérations, ni synchronisation, ni sauvegarde de la mère, ni mobile : une conversation ne quitte pas le poste ;
///  * elle est CHIFFRÉE au repos (AES-256-GCM, la clé locale qui chiffre déjà le magasin ; le nom de fichier est lié au chiffré). Sans clé locale
///    (`SIGH_CHIFFREMENT=non`, développement) elle reste en clair, comme le magasin : le fichier le dit (`chiffre: false`) ;
///  * elle est PURGÉE à chaque ouverture et à chaque question : 30 jours par défaut, réglable en base (`assistant.retentionJours`), borné de 1 à 90 jours ;
///  * un fichier illisible n'est JAMAIS écrasé : l'erreur est dite, la conversation repart vide en mémoire et le fichier reste pour qu'on le regarde.
///
/// L'assistant n'écrit RIEN au magasin : ni donnée métier, ni journal d'audit (écart E2788 : une lecture n'est pas une écriture, et une trace de chaque question
/// dans un journal synchronisé annulerait la purge à 30 jours).

/// Où se range le fichier d'un agent : un contrat minimal, pour que les tests posent une mémoire et le poste un dossier.
abstract class StockageConversation {
  /// Le contenu brut du fichier de [agent], ou `null` s'il n'existe pas. Lève si illisible.
  Future<String?> lire(String agent);
  Future<void> ecrire(String agent, String contenu);
  Future<void> effacer(String agent);

  /// Supprime les conversations dont la DERNIÈRE question a plus de [jours] jours (le fichier est réécrit à chaque question : sa date est celle de la dernière). Rend le
  /// nombre de fichiers retirés. Une conversation d'un agent qui ne revient jamais ne doit pas survivre à la durée de conservation.
  Future<int> purgerPerimes(DateTime maintenant, int jours);
}

class StockageMemoire implements StockageConversation {
  final Map<String, String> fichiers = {};
  @override
  Future<String?> lire(String agent) async => fichiers[agent];
  @override
  Future<void> ecrire(String agent, String contenu) async => fichiers[agent] = contenu;
  @override
  Future<void> effacer(String agent) async => fichiers.remove(agent);
  @override
  Future<int> purgerPerimes(DateTime maintenant, int jours) async => 0;
}

/// Le dossier `assistant/` du poste. Le nom de fichier ne porte pas l'identifiant de l'agent en clair (un hachage court), et le contenu est chiffré si [cle] existe.
class StockageFichierAssistant implements StockageConversation {
  StockageFichierAssistant(this.dossier, {this.cle});
  final String dossier;
  final List<int>? cle;

  static final _aes = AesGcm.with256bits().toSync();

  File _fichier(String agent) => File('$dossier/assistant-${_nom(agent)}.json');

  /// Un nom stable et court, sans l'identifiant en clair (somme de contrôle simple : c'est un nom de fichier, pas un secret).
  static String _nom(String agent) {
    var h = 0x811c9dc5;
    for (final o in utf8.encode(agent)) {
      h = ((h ^ o) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  String _aad(String agent) => 'assistant:${_nom(agent)}';

  @override
  Future<String?> lire(String agent) async {
    final f = _fichier(agent);
    if (!f.existsSync()) return null;
    final j = jsonDecode(f.readAsStringSync());
    if (j is! Map) throw const FormatException('fichier de conversation illisible : objet attendu');
    if (j['chiffre'] is String) {
      if (cle == null) throw const FormatException('la conversation est chiffrée par la clé locale de ce poste, qui n’est pas disponible (SIGH_CHIFFREMENT=non ?)');
      try {
        final boite = SecretBox.fromConcatenation(base64.decode('${j['chiffre']}'), nonceLength: 12, macLength: 16);
        return utf8.decode(_aes.decryptSync(boite, secretKeyData: SecretKeyData(cle!), aad: utf8.encode(_aad(agent))));
      } catch (_) {
        throw const FormatException('la conversation est illisible (fichier altéré, ou chiffré par une autre session)');
      }
    }
    return jsonEncode(j['tours']);
  }

  @override
  Future<void> ecrire(String agent, String contenu) async {
    Directory(dossier).createSync(recursive: true);
    final corps = cle == null
        ? '{"v":1,"chiffre_actif":false,"tours":$contenu}'
        : jsonEncode({'v': 1, 'chiffre': base64.encode(_aes.encryptSync(utf8.encode(contenu), secretKeyData: SecretKeyData(cle!), aad: utf8.encode(_aad(agent))).concatenation())});
    final f = _fichier(agent);
    final tmp = File('${f.path}.tmp');
    tmp.writeAsStringSync(corps, flush: true);
    tmp.renameSync(f.path);
  }

  @override
  Future<void> effacer(String agent) async {
    final f = _fichier(agent);
    if (f.existsSync()) f.deleteSync();
  }

  @override
  Future<int> purgerPerimes(DateTime maintenant, int jours) async {
    final d = Directory(dossier);
    if (!d.existsSync()) return 0;
    final limite = maintenant.subtract(Duration(days: astRetentionJours(jours)));
    var n = 0;
    for (final f in d.listSync().whereType<File>()) {
      if (!RegExp(r'assistant-[0-9a-f]{8}\.json$').hasMatch(f.path)) continue;
      if (f.lastModifiedSync().isBefore(limite)) {
        f.deleteSync();
        n++;
      }
    }
    return n;
  }
}

/// La conversation d'UN agent sur CE poste.
class ServiceAssistant extends ChangeNotifier {
  ServiceAssistant({required this.stockage, required this.agent, required this.retention, DateTime Function()? maintenant, AssistantAst? moteur})
      : _maintenant = maintenant ?? DateTime.now,
        moteur = moteur ?? AssistantAst();

  /// Posé par `main` : le dossier `assistant/` des données du poste et la clé locale. Absent (test, démonstration) : une mémoire qui ne survit pas à la session.
  static StockageConversation? stockageDuPoste;

  final StockageConversation stockage;
  final String agent;

  /// La durée de conservation EN FORCE, lue à chaque purge (jamais figée à l'ouverture : un réglage qui change s'applique à la purge suivante).
  final int Function() retention;
  final DateTime Function() _maintenant;
  final AssistantAst moteur;

  final List<TourAst> _tours = [];
  bool charge = false;

  /// Non nul si le fichier n'a pas pu être lu : la conversation repart vide, le fichier n'est pas touché tant qu'on n'efface pas.
  String? erreur;
  int _n = 0;

  List<TourAst> get tours => List.unmodifiable(_tours);
  int get joursConservation => astRetentionJours(retention());

  /// La durée lue en base pour ce poste : le registre des paramètres, borné par le domaine.
  static int retentionDepuis(Magasin m, DateTime maintenant) =>
      astRetentionJours(serviceParametres(m, auteur: () => 'assistant', horloge: () => maintenant).valeur(astCleRetention, parametreDateIso(maintenant)));

  Future<void> charger() async {
    _tours.clear();
    erreur = null;
    try {
      // Les conversations des AUTRES agents de ce poste, qui n'ont pas posé de question depuis la durée de conservation, sont retirées au passage.
      await stockage.purgerPerimes(_maintenant(), joursConservation);
      final brut = await stockage.lire(agent);
      if (brut != null) {
        for (final t in (jsonDecode(brut) as List)) {
          final tour = TourAst.depuisJson(t);
          if (tour != null) _tours.add(tour);
        }
      }
      final avant = _tours.length;
      final gardes = astPurger(_tours, _maintenant(), joursConservation);
      _tours
        ..clear()
        ..addAll(gardes);
      if (_tours.length != avant) await _ecrire();
    } catch (e) {
      erreur = 'Votre conversation précédente n’a pas pu être relue (${e is FormatException ? e.message : e}). Elle reste sur le disque, intacte ; celle-ci repart vide.';
      _tours.clear();
    }
    charge = true;
    notifyListeners();
  }

  Future<void> _ecrire() => stockage.ecrire(agent, jsonEncode([for (final t in _tours) t.toJson()]));

  /// Pose une question : la réponse est calculée sous les droits de [cx] (synchrone, aucun accès réseau), gardée, puis le fichier est réécrit purgé. La conversation
  /// ne reçoit JAMAIS d'écriture du magasin : [cx] n'a aucun écrivain.
  Future<ReponseAst> poser(String question, ContexteAst cx) async {
    final q = question.trim();
    final dernierPatient = _tours.reversed.map((t) => t.reponse.patientCode).whereType<String>().firstOrNull;
    final cxAvecContexte = ContexteAst(
      role: cx.role, lire: cx.lire, peutVoirEcran: cx.peutVoirEcran, sensibles: cx.sensibles, maintenant: cx.maintenant, session: cx.session,
      patientContexte: cx.patientContexte ?? dernierPatient, libelleEcran: cx.libelleEcran, etatSynchro: cx.etatSynchro,
    );
    final r = moteur.repondre(q, cxAvecContexte);
    final now = _maintenant().toUtc();
    _tours.add(TourAst(id: '${now.microsecondsSinceEpoch}-${_n++}', quand: now.toIso8601String(), question: q, reponse: r));
    final gardes = astPurger(_tours, now, joursConservation);
    _tours
      ..clear()
      ..addAll(gardes);
    // Un fichier illisible n'est pas écrasé : la conversation vit alors en mémoire seulement, et l'erreur reste affichée.
    if (erreur == null) {
      try {
        await _ecrire();
      } catch (e) {
        erreur = 'La conversation n’a pas pu être enregistrée sur ce poste ($e).';
      }
    }
    notifyListeners();
    return r;
  }

  /// Efface la conversation de cet agent sur ce poste (le fichier lui-même).
  Future<void> effacer() async {
    _tours.clear();
    erreur = null;
    await stockage.effacer(agent);
    notifyListeners();
  }
}
