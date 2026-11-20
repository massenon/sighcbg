// LOT 1 DE L'INVENTAIRE DES VALEURS EN DUR : les taux et barèmes de la paie (CNSS, VPS, barème de l'ITS) sont des versions de la collection `parametres`, et leurs
// confirmations des fiches de `confirmationsFiscales`. Côté synchronisation : la FAMILLE R (la mère seule écrit, un fileul ne fait que les recevoir) et JAMAIS le
// téléphone (rémunération, RG-13) — ni par la liste blanche du pont, ni par une définition qui se déclarerait `mobile`.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/src/mere.dart' show familles;
import 'package:test/test.dart';

void main() {
  test('les versions et leurs confirmations sont de famille R : la mère seule écrit', () {
    expect(familles[parCollectionParametres], 'R');
    expect(familles[fcoCollection], 'R');
  });

  test('aucune version d’un taux ou d’un barème de la paie ne part au téléphone, même déclarée « mobile »', () {
    final r = fcoPoserVersion(
        objet: fcoObjetCnss,
        valeurs: {paiCleCnssOuvriere: 4, paiCleCnssPatronale: 17},
        dateEffet: '2027-01-01',
        motif: 'Notification de la CNSS',
        role: 'comptable',
        auteur: 'COMPTABLE Test',
        maintenant: DateTime.utc(2026, 11, 16),
        parametres: const [],
        usages: const [],
        existantes: const [],
        bulletins: const []);
    expect(r.refus, isNull);
    for (final v in [...r.versions, for (final cle in paiClesBaremes) Parametres.semer(definitionDeParametre(cle)!).toJson()]) {
      expect(Parametres.autoriseMobile(v), isFalse, reason: '${v['cle']} (filtre du pont)');
      expect(Parametres.autoriseMobile({...v, 'mobile': true}), isFalse, reason: '${v['cle']} : la famille seule ferme le téléphone');
    }
  });

  test('la mère accepte les versions telles que le poste les pose, et refuse celle qui se déclarerait « mobile »', () {
    final r = fcoPoserVersion(
        objet: fcoObjetBaremeIts,
        valeurs: {paiCleBaremeIts: const [PaiTranche(0, 80000, 0), PaiTranche(80001, null, 10)]},
        dateEffet: '2027-01-01',
        motif: 'Loi de finances',
        role: 'comptable',
        auteur: 'COMPTABLE Test',
        maintenant: DateTime.utc(2026, 11, 16),
        parametres: const [],
        usages: const [],
        existantes: const [],
        bulletins: const []);
    final v = r.versions.single;
    expect(Parametres.validerChamps(v, const [], const []), isNull, reason: 'même contrôle au poste et à la mère');
    expect(Parametres.validerChamps({...v, 'mobile': true}, const [], const [])?.code, 'mobile_interdit');
  });
}
