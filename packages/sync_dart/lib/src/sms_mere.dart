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

import 'package:crypto/crypto.dart' as c;
import 'package:sigh_domaine/sigh_domaine.dart';

import 'commun.dart';
import 'mere.dart';
import 'reglages_mere.dart';

class PasserelleSms {
  /// [horloge] : l'heure de la mère (injectable pour les essais ; l'heure réelle sinon).
  PasserelleSms(this.mere, {DateTime Function()? horloge}) : _horloge = horloge ?? DateTime.now;
  final Mere mere;
  final DateTime Function() _horloge;

  static const cleActif = 'sms:actif';
  static const cleJournal = 'sms:journal';
  static const cleSuivi = 'sms:suivi_ms';

  /// Les envois AUTOMATIQUES (E5200) : le dernier jour où le tour a été achevé (AAAA-MM-JJ), la trace de ce qui a été déposé (clé d'envoi → jour de l'occasion), le bilan du
  /// dernier tour (des COMPTEURS : jamais un nom, un numéro ni un texte) et l'instant de la dernière tentative (pour ne pas reprendre le tour à chaque battement).
  static const cleAutoJour = 'sms:auto:jour';
  static const cleAutoTraces = 'sms:auto:traces';
  static const cleAutoBilan = 'sms:auto:bilan';
  static const cleAutoTentative = 'sms:auto:tentative_ms';

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
      'automatiques': await etatAutomatiques(),
    };
  }

  /// Les réglages en vigueur des envois automatiques et le bilan du dernier tour (compteurs seulement).
  Future<Map<String, Object?>> etatAutomatiques() async {
    final r = smsAutoReglageA(await fichesParametresMere(mere.base), iso(_horloge()));
    final bilan = await mere.base.meta(cleAutoBilan);
    return {
      'reglages': {'rappel_rdv_actif': r.rappelRdvActif, 'voeux_anniversaire_actif': r.voeuxAnniversaireActif, 'heure': r.heure, 'delai_rappel_heures': r.delaiRappelHeures},
      'dernier_jour': await mere.base.meta(cleAutoJour),
      'dernier_bilan': bilan == null || bilan.isEmpty ? null : jsonDecode(bilan),
      'traces': (await _traces()).length,
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

  /// Un dossier du magasin de la mère (collection, identifiant) ; `null` : absent ou archivé.
  Future<Map<String, Object?>?> _fiche(String collection, String id) async {
    final r = await mere.base.select('SELECT data FROM fiches WHERE collection=? AND id=? AND archive=0', [collection, id]);
    if (r.isEmpty) return null;
    try {
      return (jsonDecode(r.first['data'] as String) as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, Object?>>> _fiches(String collection) async {
    final out = <Map<String, Object?>>[];
    for (final r in await mere.base.select('SELECT data FROM fiches WHERE collection=? AND archive=0', [collection])) {
      try {
        out.add((jsonDecode(r['data'] as String) as Map).cast<String, Object?>());
      } catch (_) {/* une fiche illisible n'est pas un dossier */}
    }
    return out;
  }

  /// Dépose un SMS DÉJÀ COMPOSÉ par le poste. La mère recontrôle : passerelle ouverte, relais configuré, CONSENTEMENT du patient (E5201 : `patient_id` obligatoire, le dossier est relu ICI,
  /// et le numéro doit être le sien ; seul l'essai de la passerelle s'en passe), numéro et texte conformes (aucun mot interdit). Un refus du relais (plafond, schéma) est nommé et
  /// inscrit au journal ; rien n'est réessayé en silence.
  Future<Map<String, Object?>> envoyer(Map<String, Object?> b) async {
    if (!await actif()) throw Err(409, 'SMS_PASSERELLE_FERMEE', 'La passerelle SMS est fermée : rien ne part.');
    if (!mere.pont.actif) throw Err(409, 'SMS_RELAIS_NON_CONFIGURE', 'Aucun relais n’est configuré sur cette mère : aucun SMS ne peut partir.');
    final numero = '${b['numero'] ?? ''}';
    final texte = '${b['texte'] ?? ''}';
    final essai = b['essai'] == true;
    String? patientId;
    if (!essai) {
      patientId = '${b['patient_id'] ?? ''}'.trim();
      if (patientId.isEmpty) {
        throw Err(422, 'SMS_PATIENT_REQUIS', 'Un SMS se compose depuis un patient : son consentement est vérifié à son dossier.', {'geste': 'Choisir le patient destinataire.'});
      }
      final patient = await _fiche('patients', patientId);
      final refusConsentement = smsRefusConsentement(patient);
      if (refusConsentement != null) throw Err(422, refusConsentement.code, refusConsentement.motif, {'geste': refusConsentement.geste});
      final tel = smsNormaliserNumero('${patient!['telephone'] ?? ''}');
      if (tel == null || tel != numero) {
        throw Err(422, 'SMS_NUMERO_DIFFERENT', 'Le numéro n’est pas celui du dossier du patient : le consentement ne vaut que pour le numéro qu’il a donné.', {'geste': 'Corriger le téléphone au dossier, puis recomposer.'});
      }
    }
    final refus = smsControler(numero: numero, texte: texte);
    if (refus != null) throw Err(422, refus.code, refus.motif, {'geste': refus.geste});
    return _deposer(numero: numero, texte: texte, id: 'sms-${hexAlea(12)}', modele: b['modele'], auteur: b['auteur'], essai: essai, patientId: patientId, occasion: 'manuel');
  }

  /// Le dépôt au relais et l'inscription au journal : commun à la composition manuelle et aux envois automatiques.
  Future<Map<String, Object?>> _deposer(
      {required String numero, required String texte, required String id, Object? modele, Object? auteur, bool essai = false, String? patientId, required String occasion}) async {
    final entree = <String, Object?>{
      'id': id,
      'numero_masque': smsMasquerNumero(numero),
      'longueur': texte.runes.length,
      'modele': _court(modele, 80),
      'auteur': _court(auteur, 64),
      'essai': essai,
      'occasion': occasion,
      if (patientId != null) 'patient_id': patientId,
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

  // --- les envois automatiques (E5200) ------------------------------------------------------------------------------------------------------

  /// La trace de ce qui a été déposé : clé d'envoi → jour de l'occasion (AAAA-MM-JJ).
  Future<Map<String, String>> _traces() async {
    final brut = await mere.base.meta(cleAutoTraces);
    if (brut == null || brut.isEmpty) return {};
    return {for (final e in (jsonDecode(brut) as Map).entries) e.key as String: '${e.value}'};
  }

  /// L'identifiant tiré de la CLÉ d'envoi : un tour rejoué après une panne (dépôt fait, trace pas encore écrite) redépose le MÊME identifiant, et le relais rend la même ligne
  /// (idempotent). L'identifiant ne dit rien du patient (empreinte de la clé).
  static String identifiantAuto(String cle) => 'sms-a-${c.sha256.convert(utf8.encode(cle)).toString().substring(0, 24)}';

  /// UN TOUR D'ENVOIS AUTOMATIQUES : le rappel la veille d'un rendez-vous et les vœux d'anniversaire. Une fois par jour, à l'heure réglée (`sms.heureExecution`), jamais en dur ;
  /// rattrapé si la mère était éteinte. Rien ne part passerelle fermée, relais absent ou injoignable (le tour reste dû et sera repris), ni au-delà du plafond du relais ; un patient
  /// sans consentement, sans téléphone ou sans modèle neutre est écarté en NOMMANT le refus dans le bilan. UN envoi par patient et par occasion (trace). Le bilan ne porte que des compteurs.
  /// Rend le bilan du tour, ou `{'du': false}` quand il n'y a rien à faire.
  Future<Map<String, Object?>> executerAutomatiques() async {
    final maintenant = _horloge();
    final fiches = await fichesParametresMere(mere.base);
    final reglage = smsAutoReglageA(fiches, iso(maintenant));
    if (!smsAutoEstDu(maintenant, reglage, await mere.base.meta(cleAutoJour))) return {'du': false};
    if (!await actif()) return {'du': true, 'attente': 'SMS_PASSERELLE_FERMEE'};
    if (!mere.pont.actif) return {'du': true, 'attente': 'SMS_RELAIS_NON_CONFIGURE'};
    final (etatRelais, erreur) = await _etatRelais();
    if (etatRelais == null) {
      await mere.verrou.executer(() => mere.base.poserMeta(cleAutoTentative, maintenantMs()));
      return {'du': true, 'attente': 'relais_injoignable', if (erreur != null) 'motif': erreur};
    }
    num n(Object? v) => v is num ? v : 0;
    var reste = (n(etatRelais['plafond_jour']) - n(etatRelais['envoyes_aujourdhui']) - n(etatRelais['en_attente'])).toInt();

    final patients = await _fiches('patients');
    final candidats = smsAutoCandidats(patients: patients, rendezvous: await _fiches('rendezvous'), maintenant: maintenant, reglage: reglage);
    final modeles = await _fiches('modelesMessage');
    final traces = await _traces();
    final refus = <String, int>{};
    void ecarter(String code) => refus[code] = (refus[code] ?? 0) + 1;
    final deposes = <String, int>{smsOccasionRappelRdv: 0, smsOccasionAnniversaire: 0};
    var dejaFaits = 0;
    var injoignable = false;
    var plafond = false;
    for (final cand in candidats) {
      if (traces.containsKey(cand.cle)) {
        dejaFaits++;
        continue;
      }
      final p = smsAutoPreparer(cand, modeles: modeles, clinique: IdentiteClinique.nom, telephone: CfaIdentite.telephoneRdv);
      if (!p.ok) {
        ecarter(p.refus!.code);
        continue;
      }
      final controle = smsControler(numero: p.numero!, texte: p.texte!);
      if (controle != null) {
        ecarter(controle.code);
        continue;
      }
      if (reste <= 0) {
        plafond = true;
        ecarter('SMS_AUTO_PLAFOND_ATTEINT');
        continue;
      }
      try {
        await _deposer(
            numero: p.numero!,
            texte: p.texte!,
            id: identifiantAuto(cand.cle),
            modele: 'Envoi automatique : ${cand.occasion}',
            auteur: 'automatique',
            patientId: '${cand.patient['id']}',
            occasion: cand.occasion);
      } on Err catch (e) {
        if (e.statut == 429) {
          plafond = true;
          reste = 0;
          ecarter('SMS_AUTO_PLAFOND_ATTEINT');
          continue;
        }
        injoignable = true;
        break;
      }
      reste--;
      deposes[cand.occasion] = (deposes[cand.occasion] ?? 0) + 1;
      traces[cand.cle] = cand.jourOccasion;
      await mere.verrou.executer(() => mere.base.poserMeta(cleAutoTraces, enJson(traces)));
    }
    if (injoignable) {
      // Le relais a lâché en cours de tour : ce qui est déposé est tracé ; le tour reste dû et reprendra, sans rien redéposer.
      await mere.verrou.executer(() => mere.base.poserMeta(cleAutoTentative, maintenantMs()));
      return {'du': true, 'attente': 'relais_injoignable', 'deposes': deposes};
    }
    // Les traces des occasions passées ne servent plus : aucune ne peut redevenir candidate.
    final aujourdhui = iso(maintenant);
    traces.removeWhere((_, jour) => jour.compareTo(aujourdhui) < 0);
    final bilan = <String, Object?>{
      'jour': aujourdhui,
      'executeLe': maintenantMs(),
      'candidats': candidats.length,
      'deposes': deposes,
      'dejaFaits': dejaFaits,
      'refus': refus,
      'plafondAtteint': plafond,
    };
    await mere.verrou.executer(() async {
      await mere.base.poserMeta(cleAutoTraces, enJson(traces));
      await mere.base.poserMeta(cleAutoBilan, enJson(bilan));
      await mere.base.poserMeta(cleAutoJour, aujourdhui);
    });
    mere.evenementAsync('info', 'sms',
        'Envois automatiques du $aujourdhui : ${deposes.values.fold<int>(0, (a, b) => a + b)} déposé(s), ${refus.values.fold<int>(0, (a, b) => a + b)} écarté(s) (${refus.entries.map((e) => '${e.key} ${e.value}').join(', ')})');
    return {'du': true, ...bilan};
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
        if (s['expire_le'] != null) e['expire_le'] = s['expire_le'];
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
    await _tourAutomatique();
    if (maintenantMs() - await mere.base.metaInt(cleSuivi) < intervalleSuiviMs) return;
    try {
      await suivre();
    } catch (_) {
      await mere.verrou.executer(() => mere.base.poserMeta(cleSuivi, maintenantMs()));
    }
  }

  /// Les envois automatiques : le tour du jour s'examine au plus une fois par minute (le registre des paramètres n'est pas relu à chaque battement).
  Future<void> _tourAutomatique() async {
    if (maintenantMs() - await mere.base.metaInt(cleAutoTentative) < intervalleSuiviMs) return;
    try {
      await mere.verrou.executer(() => mere.base.poserMeta(cleAutoTentative, maintenantMs()));
      await executerAutomatiques();
    } catch (e) {
      mere.evenementAsync('alerte', 'sms', 'Envois automatiques de SMS : tour interrompu (${e is Err ? e.code : 'erreur'})');
    }
  }

  static String? _court(Object? v, int n) {
    if (v == null) return null;
    final s = '$v'.replaceAll(RegExp(r'[\x00-\x1F]'), ' ').trim();
    return s.isEmpty ? null : (s.length > n ? s.substring(0, n) : s);
  }
}
