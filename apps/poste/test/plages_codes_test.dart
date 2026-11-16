import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/plages_codes.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// RG-01 : deux postes ne tirent jamais le même numéro de dossier (limite levée le 03/11/2026).
final auj = DateTime(2026, 11, 3, 9);

Magasin poste() => Magasin({'patients': <Map<String, Object?>>[]});

void main() {
  test('sans service de plage, la règle historique (plus grand rang + 1) ; plage détenue : le numéro suivant, qui avance dès la réservation', () async {
    final m = poste();
    m.collection('patients').inserer({'code': 'CBG/7/26', 'nom': 'A'}, prefixe: 'PAT');
    final s = PlagesCodes.de(m);
    expect(s.actif, isFalse);
    expect(s.prochainCode(m.collection('patients').toutes, auj), 'CBG/8/26');
    s.obtenir = (taille, minimum, annee) async => (minimum, minimum + taille - 1);
    await s.recharger(maintenant: auj);
    expect(s.plages.single['debut'], 8, reason: 'la plage commence au-dessus des dossiers que le poste connaît');
    expect(s.prochainCode(m.collection('patients').toutes, auj), 'CBG/8/26');
    expect(s.prochainCode(m.collection('patients').toutes, auj), 'CBG/9/26', reason: 'un second guichet ne reçoit pas le même numéro');
    expect(s.restants, 48);
  });

  test('plage épuisée hors ligne : jamais de numéro inventé, un code PROVISOIRE ; la plage est conservée au magasin', () async {
    final m = poste();
    final s = PlagesCodes.de(m);
    var enligne = true;
    var suivant = 100;
    s.obtenir = (taille, minimum, annee) async {
      if (!enligne) throw StateError('hors ligne');
      final r = (suivant, suivant + 1);
      suivant += 2;
      return r;
    };
    await s.recharger(maintenant: auj);
    expect(s.prochainCode(const [], auj), 'CBG/100/26');
    expect(s.prochainCode(const [], auj), 'CBG/101/26');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // La recharge en ligne a donné une seconde plage (102-103) ; on la consomme, puis la mère devient injoignable.
    enligne = false;
    expect(s.prochainCode(const [], auj), 'CBG/102/26');
    expect(s.prochainCode(const [], auj), 'CBG/103/26');
    final c = s.prochainCode(const [], auj);
    expect(c, startsWith('PROV-'));
    expect(m.collection(PlagesCodes.collection).toutes, isNotEmpty);
  });

  test('SÉRIES ANNUELLES (E3830) : le dossier du 31/12/2026 prend la plage 2026, celui du 01/01/2027 demande une plage 2027 ; jamais une plage d\'une autre année', () async {
    final m = poste();
    m.collection('patients').inserer({'code': 'CBG/1180/26', 'nom': 'ANCIEN'}, prefixe: 'PAT');
    final s = PlagesCodes.de(m);
    final demandes = <(int, int, int)>[];
    var enligne = true;
    s.obtenir = (taille, minimum, annee) async {
      if (!enligne) throw StateError('hors ligne');
      demandes.add((taille, minimum, annee));
      // La mère : une série par année ; 2027 repart à 1.
      final debut = annee == 2026 ? (minimum > 1200 ? minimum : 1200) : (minimum > 1 ? minimum : 1);
      return (debut, debut + taille - 1);
    };
    final veille = DateTime(2026, 12, 31, 23, 50);
    final lendemain = DateTime(2027, 1, 1, 0, 10);
    await s.recharger(maintenant: veille);
    expect(demandes.single.$3, 2026);
    expect(s.prochainCode(m.collection('patients').toutes, veille), 'CBG/1200/26');
    // Hors ligne au passage de l'année : les plages 2026 restent, mais ne codent pas un dossier du 1er janvier.
    enligne = false;
    expect(s.prochainCode(m.collection('patients').toutes, lendemain), startsWith('PROV-'), reason: 'aucun code 2027 tiré d\'une plage 2026');
    expect(s.prochainCode(m.collection('patients').toutes, veille), 'CBG/1201/26', reason: 'la plage 2026 sert encore les dossiers datés de 2026');
    await Future<void>.delayed(const Duration(milliseconds: 10)); // la recharge tentée hors ligne s'achève
    enligne = true;
    await s.recharger(maintenant: lendemain);
    expect(demandes.last, (PlagesCodes.taillePlage, 1, 2027), reason: 'une plage de la série 2027, au-dessus des seuls dossiers de 2027 (aucun)');
    expect(s.prochainCode(m.collection('patients').toutes, lendemain), 'CBG/1/27', reason: 'la série repart à 1');
    expect(s.restantsDe(2026), 48);
    expect(s.restantsDe(2027), 49);
    expect({for (final p in s.plages) p['id']}.length, 2, reason: 'deux plages de deux années ne s\'écrasent pas');
  });

  test('BOUT EN BOUT : la mère et deux fileuls créent des dossiers en même temps, sans lien : aucun code en double, tout converge', () async {
    const port = 19441;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-plg'));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteurA = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'A');
    final moteurB = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'B');
    final mm = poste(), ma = poste(), mb = poste();
    // Des dossiers déjà là sur la mère : les plages doivent commencer au-dessus.
    mm.collection('patients').inserer({'code': 'CBG/1109/26', 'nom': 'ANCIEN'}, prefixe: 'PAT');
    final transportMere = TransportMereLocale(port: port, admin: 'secret-test');
    PlagesCodes.de(mm).obtenir = (t, mi, a) => transportMere.plage(t, mi, annee: a);
    PlagesCodes.de(ma).obtenir = (t, mi, a) => moteurA.demanderPlage(taille: t, minimum: mi, annee: a);
    PlagesCodes.de(mb).obtenir = (t, mi, a) => moteurB.demanderPlage(taille: t, minimum: mi, annee: a);
    PontActivite pont(Magasin m, TransportPont t, String e) => PontActivite(m, t, etiquette: e);
    TransportFileul tf(MoteurFileul mo) =>
        TransportFileul(lire: mo.liste, ecrireFiche: (c, f, {required existe, required champs}) => mo.ecrire(c, f, existe: existe, champs: champs));
    final pm = pont(mm, transportMere, 'M'), pa = pont(ma, tf(moteurA), 'A'), pb = pont(mb, tf(moteurB), 'B');
    try {
      for (final mo in [moteurA, moteurB]) {
        final code = await console.codeAppareil(mo == moteurA ? 'A' : 'B').timeout(const Duration(seconds: 20));
        await mo.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
        mo.demarrer();
      }
      await PlagesCodes.de(mm).recharger(maintenant: auj);
      await PlagesCodes.de(ma).recharger(maintenant: auj);
      await PlagesCodes.de(mb).recharger(maintenant: auj);
      for (final m in [mm, ma, mb]) {
        expect(PlagesCodes.de(m).restants, 50, reason: 'chaque poste détient sa plage');
      }
      // Trois postes, hors lien, créent trois dossiers chacun.
      for (final (m, nom) in [(mm, 'M'), (ma, 'A'), (mb, 'B')]) {
        for (var i = 0; i < 3; i++) {
          final code = PlagesCodes.de(m).prochainCode(m.collection('patients').toutes, auj);
          m.collection('patients').inserer({'code': code, 'nom': '$nom$i'}, prefixe: 'PAT');
        }
      }
      final fin = DateTime.now().add(const Duration(seconds: 40));
      bool fini() => [mm, ma, mb].every((m) => m.collection('patients').toutes.length == 10);
      while (!fini()) {
        for (final p in [pa, pb, pm]) {
          await p.cycle();
        }
        if (DateTime.now().isAfter(fin)) fail('pas de convergence : ${[mm, ma, mb].map((m) => m.collection('patients').toutes.length)} ; ${pm.erreur.value} ${pa.erreur.value} ${pb.erreur.value}');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      for (final m in [mm, ma, mb]) {
        final codes = [for (final f in m.collection('patients').toutes) f['code']];
        expect(codes.toSet().length, codes.length, reason: 'aucun code en double : $codes');
        expect(m.collection('patients').toutes.any((f) => f['codeEnDoublon'] == true), isFalse);
        expect(codes.where((c) => '$c'.startsWith('PROV-')), isEmpty);
      }
      final rangs = [for (final f in mm.collection('patients').toutes) int.parse('${f['code']}'.split('/')[1])]..sort();
      expect(rangs.where((r) => r != 1109).every((r) => r > 1109), isTrue, reason: 'les plages commencent au-dessus des dossiers existants');
    } finally {
      pa.arreter();
      pb.arreter();
      pm.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('BOUT EN BOUT, CHANGEMENT D\'ANNÉE (E3830) : un fileul ouvre un dossier le 31/12/2026 et un le 01/01/2027 ; synchronisés ensuite, chacun garde la série de SON année', () async {
    const port = 19447;
    final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: ':memory:', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-plg2'));
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur = MoteurFileul.creer(dbChemin: ':memory:', mere: 'http://127.0.0.1:1', nom: 'F');
    final mf = poste();
    PlagesCodes.de(mf).obtenir = (t, mi, a) => moteur.demanderPlage(taille: t, minimum: mi, annee: a);
    final pf = PontActivite(mf, TransportFileul(lire: moteur.liste, ecrireFiche: (c, f, {required existe, required champs}) => moteur.ecrire(c, f, existe: existe, champs: champs)), etiquette: 'F');
    try {
      final code = await console.codeAppareil('F').timeout(const Duration(seconds: 20));
      await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
      moteur.demarrer();
      final veille = DateTime(2026, 12, 31, 23, 50), lendemain = DateTime(2027, 1, 1, 0, 10);
      await PlagesCodes.de(mf).recharger(maintenant: veille);
      // Le guichet ouvre les deux dossiers avant que le pont ne parte : le premier dans la plage 2026, le second sans plage 2027 (provisoire).
      final c1 = PlagesCodes.de(mf).prochainCode(mf.collection('patients').toutes, veille);
      mf.collection('patients').inserer({'code': c1, 'nom': 'VEILLE', 'dateCreation': '2026-12-31'}, prefixe: 'PAT');
      PlagesCodes.de(mf).obtenir = (t, mi, a) async => throw StateError('hors ligne');
      final c2 = PlagesCodes.de(mf).prochainCode(mf.collection('patients').toutes, lendemain);
      mf.collection('patients').inserer({'code': c2, 'nom': 'LENDEMAIN', 'dateCreation': '2027-01-01'}, prefixe: 'PAT');
      expect(c1, endsWith('/26'));
      expect(c2, startsWith('PROV-'));
      final fin = DateTime.now().add(const Duration(seconds: 40));
      String codeDe(String nom) => '${mf.collection('patients').toutes.firstWhere((f) => f['nom'] == nom)['code']}';
      while (codeDe('LENDEMAIN').startsWith('PROV-')) {
        await pf.cycle();
        if (DateTime.now().isAfter(fin)) fail('pas de code attribué : ${pf.erreur.value}');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(codeDe('VEILLE'), c1, reason: 'un code attribué ne change pas (RG-01)');
      expect(codeDe('LENDEMAIN'), endsWith('/27'), reason: 'la mère code à l\'année de création, pas à celle de la synchronisation');
      if (DateTime.now().year != 2027) expect(codeDe('LENDEMAIN').split('/')[1], '1', reason: 'la série 2027 repart à 1');
    } finally {
      pf.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}
