/// LA PASSERELLE SMS DE LA MÈRE (ADR-0009, Direction de Baguidi, 16/11/2026).
///
/// Le poste compose le SMS depuis un modèle de message (règles pures du domaine, `smsComposer`) ; le service de la mère RECONTRÔLE le texte (`smsControler` :
/// numéro international, aucune variable restée, aucun mot interdit), le dépose au relais à `POST /mere/sms` (secret de la mère + signature du corps exact),
/// puis en SUIT le statut (`POST /mere/sms/statuts`). Le relais efface le numéro et le texte après l'envoi ; la mère ne garde, dans son journal, que le numéro
/// MASQUÉ, la longueur, le modèle, l'auteur et le statut — jamais le texte ni le numéro en clair.
///
/// L'interrupteur vit en base de la mère (table `meta`), FERMÉ par défaut (`smsActifDefaut`) : fermé, rien ne part, pas même un essai.
library;

import 'dart:convert';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'commun.dart';
import 'mere.dart';

class PasserelleSms {
  PasserelleSms(this.mere);
  final Mere mere;

  static const cleActif = 'sms:actif';
  static const cleJournal = 'sms:journal';
  static const cleSuivi = 'sms:suivi_ms';

  /// Entrées gardées au journal de la mère (les plus anciennes sortent).
  static const journalMax = 500;

  /// Cadence du suivi des statuts au relais, tant qu'un SMS est en attente.
  static const intervalleSuiviMs = 60000;

  Future<bool> actif() async => await mere.base.metaInt(cleActif, smsActifDefaut ? 1 : 0) == 1;

  Future<List<Map<String, Object?>>> journal() async {
    final brut = await mere.base.meta(cleJournal);
    if (brut == null || brut.isEmpty) return [];
    return [for (final x in jsonDecode(brut) as List) (x as Map).cast<String, Object?>()];
  }

  Future<void> _ecrireJournal(List<Map<String, Object?>> j) async {
    final garde = j.length > journalMax ? j.sublist(j.length - journalMax) : j;
    await mere.base.poserMeta(cleJournal, enJson(garde));
  }

  Future<void> _ajouter(Map<String, Object?> e) => mere.verrou.executer(() async => _ecrireJournal([...await journal(), e]));

  /// L'état du relais (plafond du jour, envoyés, attente, pilote), lu à l'instant. `null` et une erreur nommée quand il ne répond pas.
  Future<(Map<String, Object?>?, String?)> _etatRelais() async {
    if (!mere.pont.actif) return (null, null);
    try {
      return (await mere.pont.rel('GET', '/mere/sms/etat'), null);
    } catch (e) {
      return (null, e is Err ? '${e.code} — ${e.motif}' : 'Relais injoignable.');
    }
  }

  /// Ce que l'écran « Passerelle SMS » et le « Journal des envois SMS » affichent.
  Future<Map<String, Object?>> etat() async {
    final (relais, erreur) = await _etatRelais();
    final j = await journal();
    return {
      'reglages': {'actif': await actif(), 'defaut_actif': smsActifDefaut},
      'relais_configure': mere.pont.actif,
      'relais': relais,
      'erreur_relais': erreur,
      'journal': j.reversed.take(200).toList(),
      'mots_interdits_statut': smsStatutMotsInterdits,
    };
  }

  Future<Map<String, Object?>> regler(Map<String, Object?> b) async {
    if (b['actif'] is! bool) throw Err(422, 'interrupteur_invalide', 'L’interrupteur est ouvert (vrai) ou fermé (faux).');
    await mere.verrou.executer(() async {
      await mere.base.poserMeta(cleActif, b['actif'] == true ? 1 : 0);
      mere.evenementAsync('info', 'sms', 'Passerelle SMS ${b['actif'] == true ? 'ouverte' : 'fermée'}');
    });
    return etat();
  }

  /// Dépose un SMS DÉJÀ COMPOSÉ par le poste. La mère recontrôle : passerelle ouverte, relais configuré, numéro et texte conformes (aucun mot interdit).
  /// Un refus du relais (plafond, schéma) est nommé et inscrit au journal ; rien n'est réessayé en silence.
  Future<Map<String, Object?>> envoyer(Map<String, Object?> b) async {
    if (!await actif()) throw Err(409, 'SMS_PASSERELLE_FERMEE', 'La passerelle SMS est fermée : rien ne part.');
    if (!mere.pont.actif) throw Err(409, 'SMS_RELAIS_NON_CONFIGURE', 'Aucun relais n’est configuré sur cette mère : aucun SMS ne peut partir.');
    final numero = '${b['numero'] ?? ''}';
    final texte = '${b['texte'] ?? ''}';
    final refus = smsControler(numero: numero, texte: texte);
    if (refus != null) throw Err(422, refus.code, refus.motif, {'geste': refus.geste});
    final id = 'sms-${hexAlea(12)}';
    final entree = <String, Object?>{
      'id': id,
      'numero_masque': smsMasquerNumero(numero),
      'longueur': texte.runes.length,
      'modele': _court(b['modele'], 80),
      'auteur': _court(b['auteur'], 64),
      'essai': b['essai'] == true,
      'depose_le': maintenantMs(),
      'tentatives': 0,
    };
    try {
      final r = await mere.pont.rel('POST', '/mere/sms', {
        'sms': {'id': id, 'numero': numero, 'texte': texte}
      }, true);
      final s = (r['sms'] as Map?)?.cast<String, Object?>() ?? const {};
      await _ajouter({...entree, 'statut': '${s['statut'] ?? 'en_attente'}'});
      mere.evenementAsync('info', 'sms', 'SMS $id déposé au relais (${entree['longueur']} caractères)');
      return {'depose': true, 'id': id, 'statut': '${s['statut'] ?? 'en_attente'}'};
    } catch (e) {
      final code = e is Err ? e.code : 'relais_injoignable';
      final motif = e is Err ? e.motif : 'Le relais ne répond pas : le SMS n’est pas déposé.';
      await _ajouter({...entree, 'statut': 'non_depose', 'erreur': code});
      mere.evenementAsync('alerte', 'sms', 'SMS $id non déposé : $code');
      throw Err(e is Err && e.statut == 429 ? 429 : 502, code, motif);
    }
  }

  /// Relève au relais le statut des SMS encore en attente et met le journal à jour. Rend le nombre de SMS dont le statut a changé.
  Future<int> suivre() async {
    if (!mere.pont.actif) return 0;
    final attente = [for (final e in await journal()) if (e['statut'] == 'en_attente') '${e['id']}'];
    if (attente.isEmpty) return 0;
    final r = await mere.pont.rel('POST', '/mere/sms/statuts', {'ids': attente.take(200).toList()}, true);
    final parId = {for (final s in (r['statuts'] as List? ?? const [])) '${(s as Map)['id']}': s.cast<String, Object?>()};
    var changes = 0;
    await mere.verrou.executer(() async {
      final j = await journal();
      for (final e in j) {
        final s = parId['${e['id']}'];
        if (s == null || s['statut'] == null || s['statut'] == e['statut']) continue;
        e['statut'] = s['statut'];
        e['tentatives'] = s['tentatives'];
        if (s['envoye_le'] != null) e['envoye_le'] = s['envoye_le'];
        if (s['echec_le'] != null) e['echec_le'] = s['echec_le'];
        if (s['erreur'] != null) e['erreur'] = s['erreur'];
        changes++;
      }
      await _ecrireJournal(j);
      await mere.base.poserMeta(cleSuivi, maintenantMs());
    });
    return changes;
  }

  /// Un tour de boucle : relève les statuts toutes les minutes tant qu'un SMS est en attente. Erreur du relais : on réessaie au tour suivant.
  Future<void> tour() async {
    if (maintenantMs() - await mere.base.metaInt(cleSuivi) < intervalleSuiviMs) return;
    try {
      await suivre();
    } catch (_) {
      await mere.verrou.executer(() => mere.base.poserMeta(cleSuivi, maintenantMs()));
    }
  }

  static String? _court(Object? v, int n) {
    if (v == null) return null;
    final s = '$v'.replaceAll(RegExp(r'[\x00-\x1F]'), ' ').trim();
    return s.isEmpty ? null : (s.length > n ? s.substring(0, n) : s);
  }
}
