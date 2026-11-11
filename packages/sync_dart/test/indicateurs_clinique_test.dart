// Publication des indicateurs agrégés (Direction, 09/11/2026, ADR-0007) : interrupteur fermé par défaut = rien ne part ; ouvert = un instantané SIGNÉ,
// conforme au schéma, sans donnée nominative ; l'intervalle est respecté ; le dernier instantané envoyé est conservé tel quel.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/src/commun.dart';
import 'package:sigh_sync/src/indicateurs_clinique.dart';
import 'package:sigh_sync/src/mere.dart';
import 'package:test/test.dart';

class Recu {
  Recu(this.chemin, this.entetes, this.corps);
  final String chemin;
  final Map<String, String> entetes;
  final List<int> corps;
}

void main() {
  late HttpServer relais;
  late List<Recu> recus;
  late int statutRelais;
  late Mere m;
  const secret = 's3cr3t-de-la-mere';

  Future<void> fiche(String col, String id, Map<String, Object?> data) =>
      m.base.exec('INSERT INTO fiches(collection,id,data,fieldseq,archive) VALUES(?,?,?,?,0)', [col, id, jsonEncode(data), '{}']);

  setUp(() async {
    recus = [];
    statutRelais = 200;
    relais = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(relais.forEach((req) async {
      final corps = await req.fold<List<int>>([], (a, b) => [...a, ...b]);
      final h = <String, String>{};
      req.headers.forEach((k, v) => h[k] = v.join(','));
      recus.add(Recu(req.uri.path, h, corps));
      req.response.statusCode = statutRelais;
      req.response.headers.contentType = ContentType.json;
      req.response.write(statutRelais == 200 ? '{"ok":true}' : '{"code":"signature_invalide","motif":"Signature refusée."}');
      await req.response.close();
    }));
    m = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:', relais: 'http://127.0.0.1:${relais.port}', secretRelais: secret, versionApplication: '2.0.1'));
    await fiche('patients', 'P1', {'statut': 'actif', 'nom': 'ZANTCHEDE', 'prenom': 'Kadidja', 'code': 'CBG/1/26', 'telephone': '00 00 00 00 02', 'dateCreation': DateTime.now().toIso8601String().substring(0, 10), 'fictif': true});
    await fiche('consultations', 'C1', {'date': DateTime.now().toIso8601String(), 'motif': 'Paludisme grave', 'diagnostic': 'Drépanocytose', 'medecin': 'VODOUHE Fiacre'});
    await fiche('factures', 'F1', {'date': DateTime.now().toIso8601String().substring(0, 10), 'montantTTC': 12000, 'montantPaye': 5000, 'reliquat': 7000, 'patient': 'ZANTCHEDE Kadidja', 'assureur': 'Pharma Borgou SARL'});
  });
  tearDown(() async => relais.close(force: true));

  List<Recu> indic() => recus.where((r) => r.chemin == '/mere/indicateurs-clinique').toList();

  test('par défaut l\'interrupteur est OUVERT (Direction, 10/11/2026), l\'intervalle et la péremption ont leur défaut ; fermé, rien ne part', () async {
    final r = await m.pont.indicateurs.reglages();
    expect(r['publier'], true);
    await m.pont.indicateurs.regler({'publier': false});
    expect(r['intervalle_s'], ikIntervalleDefautSecondes);
    expect(r['jours_peremption'], ikJoursPeremptionDefaut);
    expect(await m.pont.indicateurs.publier(), {'publie': false, 'raison': 'interrupteur_ferme'});
    await m.pont.indicateurs.tour();
    expect(indic(), isEmpty);
    expect(recus, isEmpty, reason: 'fermé : aucune requête, pas même un essai');
    expect((await m.pont.indicateurs.etat())['dernier'], isNull);
  });

  test('ouvert : un instantané SIGNÉ part, conforme au schéma, sans aucune donnée nominative', () async {
    await m.pont.indicateurs.regler({'publier': true});
    await m.pont.indicateurs.tour();
    expect(indic(), hasLength(1));
    final r = indic().single;
    expect(r.entetes['x-mere'], secret);
    expect(r.entetes['x-signature'], 'sha256=${PublicationIndicateurs.signer(secret, r.corps)}');
    expect(r.entetes['x-signature'], isNot(PublicationIndicateurs.signer('autre-secret', r.corps)));
    final corps = jsonDecode(utf8.decode(r.corps)) as Map;
    expect(corps.keys, ['instantane']);
    final inst = corps['instantane'] as Map<String, Object?>;
    expect(ikValider(inst), isEmpty);
    expect(inst['version_application'], '2.0.1');
    expect((inst['patients'] as Map)['actifs'], 1);
    expect((inst['facturation_mois'] as Map)['montant_facture'], 12000);
    expect((inst['facturation_mois'] as Map)['reste_du'], 7000);
    expect((inst['activite_mois'] as Map)['m2_consultations'], 1);
    expect(inst['etat_jeu'], 'demonstration');
    expect((inst['stock'] as Map)['lots_perimes'], isNull, reason: 'aucun lot reçu : non disponible, pas zéro');
    final texte = utf8.decode(r.corps);
    for (final n in ['ZANTCHEDE', 'Kadidja', 'CBG/1/26', '00 00 00 00 02', 'Paludisme', 'Drépanocytose', 'VODOUHE', 'Pharma Borgou']) {
      expect(texte.contains(n), isFalse, reason: 'fuite de « $n »');
    }
  });

  test('le dernier instantané envoyé est conservé tel quel : la Direction voit CE QUI PART', () async {
    await m.pont.indicateurs.regler({'publier': true});
    await m.pont.indicateurs.tour();
    final envoye = (jsonDecode(utf8.decode(indic().single.corps)) as Map)['instantane'];
    final e = await m.pont.indicateurs.etat();
    expect((e['dernier'] as Map)['instantane'], envoye);
    expect((e['dernier'] as Map)['envoye_le'], isA<int>());
    expect(e['erreur'], isNull);
    expect(e['relais_configure'], true);
  });

  test('l\'intervalle est respecté : un second tour immédiat n\'envoie rien, un tour après l\'intervalle envoie', () async {
    await m.pont.indicateurs.regler({'publier': true, 'intervalle_s': 60});
    await m.pont.indicateurs.tour();
    await m.pont.indicateurs.tour();
    expect(indic(), hasLength(1));
    await m.base.poserMeta(PublicationIndicateurs.cleTentative, maintenantMs() - 61 * 1000);
    await m.pont.indicateurs.tour();
    expect(indic(), hasLength(2));
  });

  test('refermer l\'interrupteur arrête tout envoi', () async {
    await m.pont.indicateurs.regler({'publier': true});
    await m.pont.indicateurs.tour();
    await m.pont.indicateurs.regler({'publier': false});
    await m.base.poserMeta(PublicationIndicateurs.cleTentative, 1);
    await m.pont.indicateurs.tour();
    expect(indic(), hasLength(1));
    expect(await m.pont.indicateurs.publier(), {'publie': false, 'raison': 'interrupteur_ferme'});
  });

  test('un refus du relais est consigné avec son motif, et le dernier instantané reste le dernier ENVOYÉ', () async {
    statutRelais = 403;
    await m.pont.indicateurs.regler({'publier': true});
    final r = await m.pont.indicateurs.publier();
    expect(r['publie'], false);
    expect(r['raison'], 'echec_relais');
    final e = await m.pont.indicateurs.etat();
    expect(e['dernier'], isNull);
    expect('${e['erreur']}', contains('signature_invalide'));
  });

  test('les réglages hors bornes sont REFUSÉS en le disant, rien n\'est modifié', () async {
    for (final mauvais in [
      {'intervalle_s': 5},
      {'intervalle_s': 999999},
      {'intervalle_s': 'souvent'},
      {'jours_peremption': 0},
      {'publier': 'oui'},
    ]) {
      await expectLater(m.pont.indicateurs.regler(mauvais), throwsA(isA<Err>().having((x) => x.statut, 'statut', 422)));
    }
    expect((await m.pont.indicateurs.reglages())['intervalle_s'], ikIntervalleDefautSecondes);
    expect((await m.pont.indicateurs.reglages())['publier'], ikPublierDefaut);
  });

  test('sans relais configuré, rien ne part même interrupteur ouvert', () async {
    final seule = await Mere.creer(ConfigMere(port: 0, dbChemin: ':memory:'));
    await seule.pont.indicateurs.regler({'publier': true});
    expect(await seule.pont.indicateurs.publier(), {'publie': false, 'raison': 'relais_non_configure'});
  });

  test('l\'aperçu calcule sans rien envoyer', () async {
    final apercu = await m.pont.indicateurs.instantane();
    expect(ikValider(apercu), isEmpty);
    expect(recus, isEmpty);
  });
}
