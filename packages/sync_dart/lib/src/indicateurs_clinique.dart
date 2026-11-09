/// LA PUBLICATION DES INDICATEURS AGRÉGÉS AU RELAIS (Direction, 09/11/2026, ADR-0007).
///
/// La mère calcule, avec le calculateur PUR du domaine (`ikCalculer`), un instantané de NOMBRES (aucun nom, aucun code patient, aucun libellé libre), le SIGNE
/// avec le secret de la mère existant (HMAC-SHA256 du corps exact de la requête, en-tête `x-signature` : le secret lui-même part déjà dans `x-mere`, la
/// signature protège le corps de toute altération en route) et le dépose à `POST /mere/indicateurs-clinique`.
///
/// Trois réglages vivent EN BASE (table `meta` de la mère, avec leur défaut) et se posent aux Paramètres du poste : l'interrupteur « publier les indicateurs
/// au relais » (FERMÉ par défaut tant que la Direction ne l'a pas ouvert : fermé, RIEN ne part), l'intervalle de publication, et le nombre de jours qui
/// fait qu'un lot est « proche de la péremption ». Le dernier instantané réellement envoyé est conservé tel quel : la Direction voit CE QUI PART.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as c;
import 'package:sigh_domaine/sigh_domaine.dart';

import 'commun.dart';
import 'mere.dart';

class PublicationIndicateurs {
  PublicationIndicateurs(this.mere);
  final Mere mere;

  static const cleActif = 'indicateurs_clinique:publier';
  static const cleIntervalle = 'indicateurs_clinique:intervalle_s';
  static const cleJours = 'indicateurs_clinique:jours_peremption';
  static const cleDernier = 'indicateurs_clinique:dernier';
  static const cleTentative = 'indicateurs_clinique:tentative_ms';
  static const cleErreur = 'indicateurs_clinique:erreur';

  /// Les collections lues, et rien d'autre : le calculateur n'a pas besoin du reste.
  static const collectionsLues = ['patients', 'consultations', 'visites', 'rendezvous', 'admissions', 'lits', 'factures', 'produits', 'lots', 'echeancesFiscales', 'ecritures', 'utilisateurs'];

  bool _enCours = false;

  /// HMAC-SHA256 du corps exact de la requête, en hexadécimal.
  static String signer(String secret, List<int> corps) => c.Hmac(c.sha256, utf8.encode(secret)).convert(corps).toString();

  Future<Map<String, Object?>> reglages() async => {
        'publier': await mere.base.metaInt(cleActif) == 1,
        'intervalle_s': await mere.base.metaInt(cleIntervalle, ikIntervalleDefautSecondes),
        'jours_peremption': await mere.base.metaInt(cleJours, ikJoursPeremptionDefaut),
        'defauts': {'publier': false, 'intervalle_s': ikIntervalleDefautSecondes, 'jours_peremption': ikJoursPeremptionDefaut},
        'bornes': {'intervalle_min_s': ikIntervalleMinSecondes, 'intervalle_max_s': ikIntervalleMaxSecondes},
      };

  /// Pose un ou plusieurs réglages. Une valeur hors bornes est REFUSÉE en le disant : on ne la rabote pas en silence.
  Future<Map<String, Object?>> regler(Map<String, Object?> b) async {
    final iv = b['intervalle_s'];
    final jours = b['jours_peremption'];
    if (iv != null && (iv is! int || iv < ikIntervalleMinSecondes || iv > ikIntervalleMaxSecondes)) {
      throw Err(422, 'intervalle_invalide', 'L’intervalle doit être un nombre entier de secondes entre $ikIntervalleMinSecondes et $ikIntervalleMaxSecondes.');
    }
    if (jours != null && (jours is! int || jours < 1 || jours > 730)) {
      throw Err(422, 'jours_invalides', 'Le nombre de jours de péremption doit être un entier entre 1 et 730.');
    }
    if (b['publier'] != null && b['publier'] is! bool) throw Err(422, 'interrupteur_invalide', 'L’interrupteur est ouvert (vrai) ou fermé (faux).');
    await mere.verrou.executer(() async {
      if (b['publier'] != null) await mere.base.poserMeta(cleActif, b['publier'] == true ? 1 : 0);
      if (iv != null) await mere.base.poserMeta(cleIntervalle, iv);
      if (jours != null) await mere.base.poserMeta(cleJours, jours);
      // Un interrupteur qu'on ouvre fait partir un instantané au prochain tour, sans attendre l'intervalle.
      if (b['publier'] == true) await mere.base.poserMeta(cleTentative, 0);
      mere.evenementAsync('info', 'indicateurs', 'Publication des indicateurs au relais : ${b['publier'] == null ? 'réglages modifiés' : (b['publier'] == true ? 'ouverte' : 'fermée')}');
    });
    return reglages();
  }

  /// Calcule l'instantané à partir des fiches que la mère détient. Rien n'est envoyé.
  Future<Map<String, Object?>> instantane() async {
    final jours = await mere.base.metaInt(cleJours, ikJoursPeremptionDefaut);
    final collections = <String, List<Map<String, Object?>>>{};
    List<IkAppareil> postes = [];
    await mere.verrou.executer(() async {
      final presentes = {for (final r in await mere.base.select('SELECT collection, COUNT(*) AS n FROM fiches GROUP BY collection')) '${r['collection']}'};
      for (final nom in collectionsLues) {
        if (!presentes.contains(nom)) continue; // jamais reçue : « non disponible », pas zéro
        collections[nom] = [
          for (final r in await mere.base.select('SELECT data FROM fiches WHERE collection=? AND archive=0', [nom])) (jsonDecode(r['data'] as String) as Map).cast<String, Object?>()
        ];
      }
      postes = [
        for (final r in await mere.base.select("SELECT uuid, dernier_contact FROM appareils WHERE etat <> 'revoque' ORDER BY uuid"))
          IkAppareil(identifiant: '${r['uuid']}', dernierContactMs: r['dernier_contact'] is num ? (r['dernier_contact'] as num).toInt() : 0)
      ];
    });
    return ikCalculer(IkEntree(
      collections: collections,
      maintenant: DateTime.now(),
      appareils: postes,
      versionApplication: mere.cfg.versionApplication,
      joursPeremption: jours,
    ));
  }

  /// Ce que la Direction voit aux Paramètres : réglages, dernier instantané réellement envoyé (contenu exact), dernière tentative et son erreur.
  Future<Map<String, Object?>> etat() async {
    final brut = await mere.base.meta(cleDernier);
    final erreur = await mere.base.meta(cleErreur);
    final tentative = await mere.base.metaInt(cleTentative);
    return {
      'reglages': await reglages(),
      'relais_configure': mere.pont.actif,
      'dernier': brut == null || brut.isEmpty ? null : jsonDecode(brut),
      'derniere_tentative_ms': tentative == 0 ? null : tentative,
      'erreur': erreur == null || erreur.isEmpty ? null : erreur,
    };
  }

  /// Publie maintenant. Interrupteur fermé ou relais non configuré : RIEN ne part, et la réponse le dit.
  Future<Map<String, Object?>> publier() async {
    if (await mere.base.metaInt(cleActif) != 1) return {'publie': false, 'raison': 'interrupteur_ferme'};
    if (!mere.pont.actif) return {'publie': false, 'raison': 'relais_non_configure'};
    if (_enCours) return {'publie': false, 'raison': 'deja_en_cours'};
    _enCours = true;
    try {
      final inst = await instantane();
      final defauts = ikValider(inst);
      // Garde-fou : un instantané non conforme au schéma ne part JAMAIS, même si le calculateur est fautif.
      if (defauts.isNotEmpty) {
        await mere.verrou.executer(() => mere.base.poserMeta(cleErreur, 'Instantané non conforme, rien envoyé : ${defauts.take(3).join(' ; ')}'));
        return {'publie': false, 'raison': 'instantane_non_conforme', 'defauts': defauts};
      }
      await mere.verrou.executer(() => mere.base.poserMeta(cleTentative, maintenantMs()));
      try {
        await mere.pont.rel('POST', '/mere/indicateurs-clinique', {'instantane': inst}, true);
      } catch (e) {
        await mere.verrou.executer(() => mere.base.poserMeta(cleErreur, e is Err ? '${e.code} — ${e.motif}' : 'Relais injoignable : le prochain essai suit l’intervalle.'));
        return {'publie': false, 'raison': 'echec_relais'};
      }
      await mere.verrou.executer(() async {
        await mere.base.poserMeta(cleDernier, enJson({'envoye_le': maintenantMs(), 'instantane': inst}));
        await mere.base.poserMeta(cleErreur, '');
      });
      return {'publie': true, 'envoye_le': maintenantMs()};
    } finally {
      _enCours = false;
    }
  }

  /// Un tour de boucle (toutes les quelques secondes) : publie si l'interrupteur est ouvert ET que l'intervalle est écoulé.
  Future<void> tour() async {
    if (await mere.base.metaInt(cleActif) != 1) return;
    final iv = await mere.base.metaInt(cleIntervalle, ikIntervalleDefautSecondes);
    if (maintenantMs() - await mere.base.metaInt(cleTentative) < iv * 1000) return;
    await publier();
  }
}
