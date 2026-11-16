/// LA SATISFACTION EN LIGNE, CÔTÉ MÈRE (décision de la Direction du 16/11/2026, section 8).
///
/// Un patient répond au questionnaire sur le RELAIS, depuis chez lui (lien ou QR). Sa réponse est CHIFFRÉE dans son navigateur avec la clé PUBLIQUE de
/// la clinique : le relais ne peut pas la lire. La mère seule tient la clé PRIVÉE (table `meta` de SA base, jamais dans une fiche, jamais publiée, jamais
/// diffusée aux fileuls) ; elle relève les enveloppes, les déchiffre et les enregistre comme réponses d'enquête (`reponsesEnquetes`, canal
/// « Lien public »), qui redescendent aux fileuls par le journal comme toute fiche : les statistiques (`adm-satisfaction`) les comptent partout.
///
/// Schéma « sat1 », le MÊME que `apps/web/public/js/satisfaction.js` (vecteurs croisés : `test/vecteurs/satisfaction_navigateur.json`) :
/// X25519 éphémère du navigateur × clé de la clinique → HKDF-SHA256 (sel = clé éphémère || clé de la clinique, info « sigh-satisfaction-v1 ») →
/// AES-256-GCM (nonce 12 octets, données authentifiées « sat1|kid|jeton »). Le clair est un JSON { v: 1, reponses, bourrage } bourré à 256 octets.
///
/// Le cycle, à chaque tour du pont (et sur demande, `POST /admin/satisfaction/synchroniser`) :
///  1. PUBLIER : tout lien `enLigne` d'un poste (fiche `jetonsEnquete`, arrivée par le journal) part au relais avec le modèle rendu par LE générateur du
///     domaine ; republié quand le modèle change (une question ajoutée paraît sur le lien) ; RÉVOQUÉ au relais quand le poste l'a révoqué. La mère écrit
///     l'issue sur la fiche du lien (`lienPublic`, `erreurRelais`, `relaisRevoqueLe`), qui revient aux postes ;
///  2. RELEVER : les enveloppes, déchiffrées puis retenues par la règle du domaine (`qualReponseEnLigne`), deviennent des fiches `SAT-<id>` (une relève
///     rejouée ne double rien), puis sont ACQUITTÉES (le relais les efface). Une enveloppe illisible est écartée, comptée et nommée au journal technique
///     de la mère, sans contenu.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as c;
import 'package:cryptography/cryptography.dart';
import 'package:sigh_domaine/sigh_domaine.dart' show IdentiteClinique, iso, qualPublicationEnLigne, qualRefusPublication, qualReponseEnLigne, qualLienEnLigne;

import 'commun.dart';
import 'mere.dart';

const satVersion = 'sat1';
const satInfo = 'sigh-satisfaction-v1';
const _bloc = 256;

String satB64u(List<int> o) => base64Url.encode(o).replaceAll('=', '');
List<int> satDeB64u(String t) => base64Url.decode(base64Url.normalize(t));

/// La paire de la clinique. `privee` ne sort jamais de la mère.
class CleSatisfaction {
  CleSatisfaction(this.privee, this.publique) : kid = satKid(publique);
  final List<int> privee;
  final List<int> publique;
  final String kid;

  Map<String, Object?> versJson() => {'privee': satB64u(privee), 'publique': satB64u(publique)};
  static CleSatisfaction depuisJson(Map j) => CleSatisfaction(satDeB64u('${j['privee']}'), satDeB64u('${j['publique']}'));
}

/// Identifiant de la clé : 16 premiers caractères hexadécimaux du SHA-256 de la clé publique brute.
String satKid(List<int> publique) => c.sha256.convert(publique).toString().substring(0, 16);

/// Une paire X25519 tirée au hasard (générateur sûr du système).
Future<CleSatisfaction> satNouvelleCle() async {
  final graine = List<int>.generate(32, (_) => Random.secure().nextInt(256));
  return satCleDepuisGraine(graine);
}

Future<CleSatisfaction> satCleDepuisGraine(List<int> graine) async {
  final kp = await X25519().newKeyPairFromSeed(graine);
  final pub = await kp.extractPublicKey();
  return CleSatisfaction(await kp.extractPrivateKeyBytes(), pub.bytes);
}

Future<List<int>> _cleAes(List<int> secret, List<int> epk, List<int> pk) async {
  if (secret.every((x) => x == 0)) throw const FormatException('secret partagé nul');
  final k = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(secretKey: SecretKey(secret), nonce: [...epk, ...pk], info: utf8.encode(satInfo));
  return k.extractBytes();
}

List<int> _aad(String kid, String jeton) => utf8.encode('$satVersion|$kid|$jeton');

/// Chiffre comme le NAVIGATEUR (même algorithme, même bourrage) : sert aux essais et prouve l'accord des deux implémentations.
Future<Map<String, Object?>> satChiffrer(Map<String, Object?> reponses, {required String jeton, required String kid, required String clePublique}) async {
  final pk = satDeB64u(clePublique);
  final eph = await satNouvelleCle();
  final s = await X25519().sharedSecretKey(keyPair: await X25519().newKeyPairFromSeed(eph.privee), remotePublicKey: SimplePublicKey(pk, type: KeyPairType.x25519));
  final cle = await _cleAes(await s.extractBytes(), eph.publique, pk);
  String corps(String bourrage) => jsonEncode({'v': 1, 'reponses': reponses, 'bourrage': bourrage});
  final manque = (_bloc - utf8.encode(corps('')).length % _bloc) % _bloc;
  final clair = utf8.encode(corps(' ' * manque));
  final iv = List<int>.generate(12, (_) => Random.secure().nextInt(256));
  final boite = await AesGcm.with256bits().encrypt(clair, secretKey: SecretKey(cle), nonce: iv, aad: _aad(kid, jeton));
  return {'v': satVersion, 'kid': kid, 'epk': satB64u(eph.publique), 'iv': satB64u(iv), 'ct': satB64u([...boite.cipherText, ...boite.mac.bytes])};
}

/// Déchiffre une enveloppe avec la clé de la clinique. Lève [FormatException] (nommée) si elle est illisible : version, clé, forme, authentification.
Future<Map<String, Object?>> satDechiffrer(Map env, CleSatisfaction cle, String jeton) async {
  if (env['v'] != satVersion) throw const FormatException('version inconnue');
  if (env['kid'] != cle.kid) throw const FormatException('clé inconnue');
  final List<int> epk, iv, brut;
  try {
    epk = satDeB64u('${env['epk']}');
    iv = satDeB64u('${env['iv']}');
    brut = satDeB64u('${env['ct']}');
  } catch (_) {
    throw const FormatException('enveloppe mal formée');
  }
  if (epk.length != 32 || iv.length != 12 || brut.length < 17) throw const FormatException('enveloppe mal formée');
  final s = await X25519().sharedSecretKey(keyPair: await X25519().newKeyPairFromSeed(cle.privee), remotePublicKey: SimplePublicKey(epk, type: KeyPairType.x25519));
  final k = await _cleAes(await s.extractBytes(), epk, cle.publique);
  final List<int> clair;
  try {
    clair = await AesGcm.with256bits().decrypt(SecretBox(brut.sublist(0, brut.length - 16), nonce: iv, mac: Mac(brut.sublist(brut.length - 16))),
        secretKey: SecretKey(k), aad: _aad(cle.kid, jeton));
  } on SecretBoxAuthenticationError {
    throw const FormatException('authentification refusée');
  }
  final j = jsonDecode(utf8.decode(clair));
  if (j is! Map || j['v'] != 1 || j['reponses'] is! Map) throw const FormatException('clair inattendu');
  return (j['reponses'] as Map).cast<String, Object?>();
}

/// Le moteur de la mère. Ses réglages et compteurs vivent dans la table `meta` de la mère.
class SatisfactionEnLigne {
  SatisfactionEnLigne(this.mere);
  final Mere mere;

  static const cleMeta = 'satisfaction:cle';
  static const cleDerniereReleve = 'satisfaction:derniere_releve_ms';
  static const cleRecues = 'satisfaction:recues';
  static const cleIllisibles = 'satisfaction:illisibles';
  static const cleErreur = 'satisfaction:erreur';
  static const prefixePublie = 'satisfaction:publie:';
  static const prefixeRevoque = 'satisfaction:revoque:';

  /// Intervalle minimal entre deux relèves automatiques (cadence interne : la relève sur demande passe outre).
  static const intervalleReleveMs = 60 * 1000;

  bool _enCours = false;
  CleSatisfaction? _cle;

  /// La paire de la clinique, tirée au premier besoin et gardée dans la base de la mère.
  Future<CleSatisfaction> cle() async {
    if (_cle != null) return _cle!;
    final brut = await mere.verrou.executer(() => mere.base.meta(cleMeta));
    if (brut != null && brut.isNotEmpty) return _cle = CleSatisfaction.depuisJson(jsonDecode(brut) as Map);
    final k = await satNouvelleCle();
    await mere.verrou.executer(() => mere.base.poserMeta(cleMeta, jsonEncode(k.versJson())));
    mere.evenementAsync('info', 'satisfaction', 'Clé de la satisfaction en ligne créée (identifiant ${k.kid})');
    return _cle = k;
  }

  Future<List<({String id, Map<String, Object?> data})>> _fiches(String collection) => mere.verrou.executer(() async => [
        for (final r in await mere.base.select('SELECT id, data FROM fiches WHERE collection=? AND archive=0', [collection]))
          (id: '${r['id']}', data: (jsonDecode(r['data'] as String) as Map).cast<String, Object?>())
      ]);

  /// Écrit des champs sur une fiche AU NOM DE LA MÈRE (comme `POST /admin/referentiel`) : l'opération entre au journal et revient aux postes.
  Future<Map<String, Object?>> _ecrire(String collection, String id, Map<String, Object?> champs, {bool creerSeulement = false}) =>
      mere.verrou.executer(() => mere.base.tx(() async {
            final existe = await mere.lire(collection, id);
            if (existe != null && creerSeulement) return {'statut': 'acceptee', 'rejeu': true};
            final op = <String, Object?>{
              'id': 'sat-${uuid7()}', 'collection': collection, 'fiche': id, 'type': existe != null ? 'modifier' : 'creer',
              'champs': champs, 'hlc': maintenantMs(),
              'vu': existe == null ? <String, Object?>{} : {for (final k in champs.keys) k: nb(existe.fieldseq[k])},
            };
            return mere.traiter(op, Appareil('mere', 'mere'));
          }));

  Future<void> _corriger(String id, Map<String, Object?> lien, Map<String, Object?> champs) async {
    final change = champs.entries.any((e) => '${lien[e.key] ?? ''}' != '${e.value ?? ''}');
    if (change) await _ecrire('jetonsEnquete', id, champs);
  }

  Future<void> _meta(String k, Object v) => mere.verrou.executer(() => mere.base.poserMeta(k, v));
  Future<String?> _lireMeta(String k) => mere.verrou.executer(() => mere.base.meta(k));
  Future<int> _metaInt(String k) => mere.verrou.executer(() => mere.base.metaInt(k));

  String _jour() => iso(DateTime.now());

  /// Publie les liens en ligne nouveaux ou modifiés, révoque ceux que le poste a révoqués. Rien ne part sans relais configuré.
  Future<Map<String, Object?>> publier({bool forcer = false}) async {
    if (!mere.pont.actif) return {'publies': 0, 'revoques': 0, 'raison': 'relais_non_configure'};
    final k = await cle();
    final enquetes = {for (final e in await _fiches('enquetes')) e.id: {...e.data, 'id': e.id}};
    var publies = 0, revoques = 0, refuses = 0;
    for (final f in await _fiches('jetonsEnquete')) {
      final j = {...f.data, 'id': f.id};
      if (!qualLienEnLigne(j)) continue;
      final code = '${j['jeton'] ?? ''}';
      final hash = c.sha256.convert(utf8.encode(code)).toString();
      if ('${j['revoqueLe'] ?? ''}'.isNotEmpty || j['statut'] == 'archive') {
        if (await _lireMeta('$prefixeRevoque${f.id}') != null) continue;
        if (await _lireMeta('$prefixePublie${f.id}') == null) {
          await _meta('$prefixeRevoque${f.id}', maintenantMs()); // jamais parti : rien à retirer
          continue;
        }
        try {
          await mere.pont.rel('POST', '/mere/satisfaction/revoquer', {'jeton_hash': hash}, true);
        } on Err catch (e) {
          if (e.code != 'lien_inconnu') continue;
        } catch (_) {
          continue; // relais injoignable : au tour suivant
        }
        await _meta('$prefixeRevoque${f.id}', maintenantMs());
        await _corriger(f.id, j, {'relaisRevoqueLe': _jour()});
        revoques++;
        continue;
      }
      if ('${j['expireLe'] ?? ''}'.compareTo(_jour()) < 0) continue; // échu : le relais le refuse déjà, et le purge
      final refus = qualRefusPublication(j, enquetes[j['enqueteId']]);
      if (refus != null) {
        await _corriger(f.id, j, {'erreurRelais': refus.motif});
        refuses++;
        continue;
      }
      final pub = qualPublicationEnLigne(
          jeton: j, enquete: enquetes[j['enqueteId']]!, jetonHash: hash, clinique: IdentiteClinique.nomCourt, clePublique: satB64u(k.publique), kid: k.kid);
      final empreinte = enJson(pub);
      if (!forcer && await _lireMeta('$prefixePublie${f.id}') == empreinte) continue;
      try {
        await mere.pont.rel('POST', '/mere/satisfaction/publier', pub, true);
      } on Err catch (e) {
        await _corriger(f.id, j, {'erreurRelais': '${e.code}${e.motif.isEmpty ? '' : ' : ${e.motif}'}'});
        refuses++;
        continue;
      } catch (_) {
        continue;
      }
      await _meta('$prefixePublie${f.id}', empreinte);
      await _corriger(f.id, j, {'lienPublic': '${mere.cfg.relais}/satisfaction/$code', 'erreurRelais': '', 'publieLe': _jour()});
      publies++;
    }
    return {'publies': publies, 'revoques': revoques, 'refuses': refuses};
  }

  /// Relève, déchiffre, enregistre, acquitte. Une enveloppe illisible est écartée (comptée, nommée au journal technique) : elle ne revient pas en boucle.
  Future<Map<String, Object?>> relever() async {
    if (!mere.pont.actif) return {'recues': 0, 'illisibles': 0, 'raison': 'relais_non_configure'};
    final k = await cle();
    var recues = 0, illisibles = 0;
    final liens = {for (final f in await _fiches('jetonsEnquete')) f.id: {...f.data, 'id': f.id}};
    final enquetes = {for (final e in await _fiches('enquetes')) e.id: {...e.data, 'id': e.id}};
    for (var page = 0; page < 10; page++) {
      final r = await mere.pont.rel('POST', '/mere/satisfaction/relever', {'limite': 100}, true);
      final envs = (r['enveloppes'] as List? ?? const []).cast<Map>();
      if (envs.isEmpty) break;
      final faits = <String>[];
      for (final e in envs) {
        final id = '${e['id']}';
        final lien = liens['${e['ref']}'];
        final enquete = lien == null ? null : enquetes[lien['enqueteId']];
        Map<String, Object?>? fiche;
        String? motif;
        if (lien == null || enquete == null) {
          motif = 'lien ou enquête inconnu de la mère';
        } else {
          try {
            final reps = await satDechiffrer(e['enveloppe'] as Map, k, '${lien['jeton']}');
            fiche = qualReponseEnLigne(enquete: enquete, jeton: lien, reponses: reps, recueLe: '${e['recue_le']}');
            if (fiche == null) motif = 'aucune réponse valable';
          } on FormatException catch (x) {
            motif = x.message;
          } catch (_) {
            motif = 'illisible';
          }
        }
        if (fiche != null) {
          final res = await _ecrire('reponsesEnquetes', 'SAT-$id', {...fiche, 'statut': 'actif'}, creerSeulement: true);
          if (res['statut'] == 'refusee') continue; // gardée au relais : la prochaine relève la retentera
          recues++;
        } else {
          illisibles++;
          // Ni contenu, ni jeton : la référence du lien et la cause, pour qu'un administrateur sache qu'une réponse a été écartée.
          mere.evenementAsync('alerte', 'satisfaction', 'Réponse en ligne écartée (lien ${e['ref']}) : $motif');
        }
        faits.add(id);
      }
      if (faits.isNotEmpty) await mere.pont.rel('POST', '/mere/satisfaction/acquitter', {'ids': faits}, true);
      if (r['fin'] == true) break;
    }
    await _meta(cleDerniereReleve, maintenantMs());
    await _meta(cleRecues, await _metaInt(cleRecues) + recues);
    await _meta(cleIllisibles, await _metaInt(cleIllisibles) + illisibles);
    return {'recues': recues, 'illisibles': illisibles};
  }

  /// Publier puis relever, une seule fois à la fois ; l'erreur est gardée pour l'écran.
  Future<Map<String, Object?>> synchroniser({bool forcer = false}) async {
    if (_enCours) return {'raison': 'deja_en_cours'};
    _enCours = true;
    try {
      final p = await publier(forcer: forcer);
      final r = await relever();
      await _meta(cleErreur, '');
      return {...p, ...r};
    } on Err catch (e) {
      await _meta(cleErreur, '${e.code} : ${e.motif}');
      return {'raison': 'echec_relais', 'code': e.code};
    } catch (e) {
      await _meta(cleErreur, 'Relais injoignable : le prochain essai suit l’intervalle.');
      return {'raison': 'echec_relais'};
    } finally {
      _enCours = false;
    }
  }

  /// Le tour du pont : publication à chaque tour, relève au plus toutes les [intervalleReleveMs].
  Future<void> tour() async {
    if (!mere.pont.actif) return;
    // Aucun lien en ligne (même révoqué) : rien à publier, rien à relever ; la clé n'est pas tirée, le relais n'est pas sollicité.
    if (!(await _fiches('jetonsEnquete')).any((f) => qualLienEnLigne(f.data))) return;
    if (maintenantMs() - await _metaInt(cleDerniereReleve) < intervalleReleveMs) {
      if (!_enCours) {
        _enCours = true;
        try {
          await publier();
        } finally {
          _enCours = false;
        }
      }
      return;
    }
    await synchroniser();
  }

  /// Ce que l'écran des enquêtes montre : jamais la clé privée.
  Future<Map<String, Object?>> etat() async {
    final k = await cle();
    final liens = [for (final f in await _fiches('jetonsEnquete')) if (qualLienEnLigne(f.data)) f];
    final erreur = await _lireMeta(cleErreur);
    final derniere = await _metaInt(cleDerniereReleve);
    return {
      'relais_configure': mere.pont.actif,
      'kid': k.kid,
      'liens_en_ligne': liens.length,
      'derniere_releve_ms': derniere == 0 ? null : derniere,
      'recues': await _metaInt(cleRecues),
      'illisibles': await _metaInt(cleIllisibles),
      'erreur': erreur == null || erreur.isEmpty ? null : erreur,
    };
  }

  /// `/admin/satisfaction/*` : hors du verrou de la base (réseau), comme la copie hors site.
  Future<Object?> route(String cle, HttpRequest req, Map<String, Object?> b) async {
    mere.adminOk(req);
    switch (cle) {
      case 'GET /admin/satisfaction/etat':
        return etat();
      case 'POST /admin/satisfaction/synchroniser':
        return synchroniser(forcer: b['forcer'] == true);
    }
    throw Err(404, 'route_inconnue', '');
  }
}
