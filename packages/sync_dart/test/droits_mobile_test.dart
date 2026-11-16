import 'package:sigh_sync/sigh_sync.dart';
import 'package:sigh_sync/src/mobile.dart';
import 'package:test/test.dart';

/// Le mobile REÇOIT les droits de la mère (`rbac`, `modulesActifs`) et ne les écrit pas (10/11/2026) : instantané fusionné champ par champ, opérations suivantes,
/// date de mise à jour exposée, refus nommé de l'écriture de toute configuration.
void main() {
  Mobile mobile() => Mobile(ConfigMobile(port: 0, relais: 'http://127.0.0.1:1', dbChemin: ':memory:'));
  Map<String, Object?> instantane(List<Map<String, Object?>> fiches) => {'type': 'droits', 'fiches': fiches};
  Map<String, Object?> fiche(String id, Map<String, Object?> data, Map<String, Object?> seq, {String collection = 'rbac', bool archive = false}) =>
      {'collection': collection, 'id': id, 'data': data, 'fieldseq': seq, 'archive': archive};

  test('un instantané vide pose la date de mise à jour : le téléphone est « synchronisé » sans rien à appliquer', () async {
    final m = mobile();
    expect(m.base.metaInt('droits_maj_le'), 0);
    m.recevoir(instantane(const []));
    expect(m.base.metaInt('droits_maj_le'), greaterThan(0));
    expect(m.liste('rbac'), isEmpty);
    final (_, etat) = await m.commande('GET /etat', const {}, const {});
    expect((etat! as Map)['droits_maj_le'], greaterThan(0));
  });

  test('l\'instantané range les fiches hors lot (jamais purgées à l\'expiration) ; une opération suivante les met à jour ; un instantané plus ancien ne régresse pas', () {
    final m = mobile();
    m.recevoir(instantane([
      fiche('RBAC26', {'role': 'sage_femme', 'version': 1}, {'role': 5, 'version': 5}),
      fiche('MOD01', {'module': 'M5', 'actif': false}, {'module': 6, 'actif': 6}, collection: 'modulesActifs'),
    ]));
    expect(m.liste('rbac').single['data'], containsPair('version', 1));
    expect(m.lireConfirme('rbac', 'RBAC26').dulot, isFalse);
    m.recevoir({'type': 'lot', 'expire': 1, 'fiches': const []});
    m.purgerLotExpire();
    expect(m.liste('rbac'), hasLength(1), reason: 'la fin du lot ne purge pas les droits');
    final avant = m.base.metaInt('droits_maj_le');
    m.recevoir({
      'type': 'ops',
      'ops': [
        {'collection': 'rbac', 'fiche': 'RBAC26', 'type': 'modifier', 'seq': 9, 'champs': {'version': 2}}
      ]
    });
    expect(m.liste('rbac').single['data'], containsPair('version', 2));
    expect(m.base.metaInt('droits_maj_le'), greaterThanOrEqualTo(avant));
    // Un instantané qui arrive APRÈS une opération plus récente ne la défait pas (garde par champ).
    m.recevoir(instantane([fiche('RBAC26', {'role': 'sage_femme', 'version': 1}, {'role': 5, 'version': 5})]));
    expect(m.liste('rbac').single['data'], containsPair('version', 2));
  });

  test('une fiche archivée par la mère le reste sur le téléphone (RG-14)', () {
    final m = mobile();
    m.recevoir(instantane([fiche('RBAC30', {'role': 'x'}, {'role': 1}, archive: true)]));
    expect(m.liste('rbac').single['archive'], isTrue);
  });

  test('le téléphone n\'écrit aucune configuration : refus nommé 403, rien en file, rien d\'envoyé', () async {
    final m = mobile();
    for (final c in ['rbac', 'modulesActifs', 'produits', 'tarifs']) {
      final (st, corps) = await m.commande('POST /ecrire', {'type': 'modifier', 'collection': c, 'fiche': 'X', 'champs': {'a': 1}}, const {});
      expect(st, 403, reason: c);
      expect((corps! as Map)['code'], 'regle_sur_la_mere', reason: c);
    }
    final (_, etat) = await m.commande('GET /etat', const {}, const {});
    expect((etat! as Map)['en_attente'], 0);
    // Une collection d'activité s'écrit toujours.
    final (st, _) = await m.commande('POST /ecrire', {'type': 'creer', 'collection': 'constantes', 'champs': {'temperature': 37}}, const {});
    expect(st, 200);
  });
}
