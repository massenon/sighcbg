// Décision de la Direction du 16/11/2026 : deux couvertures OUVERTES pour un même patient (conflit hors ligne) ne restent plus en silence.
// Le moteur les DÉTECTE, la prise en charge (RG-09) lit la couverture dont le début est le plus récent (jamais deux), l'arbitrage CLÔT l'une des deux avec motif.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

void main() {
  F cv(String id, String debut, {String? fin, String patient = 'P1', String assureur = 'NSIA', String? police, Object? souscripteur}) => {
        'id': id, 'patientId': patient, 'debut': debut, 'fin': fin, 'assureur': assureur, 'assureurNom': assureur, 'numeroPolice': police ?? 'POL-$id', 'tauxPriseEnCharge': 80,
        'carteExpiration': '2027-12-31', 'souscripteurId': souscripteur ?? 'S-$id', 'statut': 'actif'
      };
  final patient = <String, Object?>{'id': 'P1', 'code': 'CBG/1/26', 'nom': 'A', 'prenom': 'B'};

  group('détection', () {
    test('deux couvertures ouvertes du même patient forment un conflit ; une close, une seule ou une archivée n’en forment pas', () {
      final g = assCouverturesEnConflit([cv('A', '2026-01-01'), cv('B', '2026-06-01'), cv('C', '2026-01-01', patient: 'P2'), cv('D', '2025-01-01', fin: '2025-12-31'), {...cv('E', '2026-09-01'), 'statut': 'archive'}]);
      expect(g, hasLength(1));
      expect(g.single.map((c) => c['id']), ['B', 'A'], reason: 'la plus récente (début) d’abord');
      expect(assCouverturesEnConflit([cv('A', '2026-01-01'), cv('D', '2025-01-01', fin: '2025-12-31')]), isEmpty);
    });
  });

  group('lecture en attendant l’arbitrage', () {
    test('RG-09 lit la couverture au début le plus récent, jamais deux ; avant ce début, l’autre', () {
      final l = [cv('A', '2026-01-01'), cv('B', '2026-06-01')];
      expect(couvertureALaDate(patient, l, '2026-07-01')!['id'], 'B');
      expect(couvertureALaDate(patient, l, '2026-03-01')!['id'], 'A', reason: 'avant le début de B, seule A est en force');
      expect(couvertureALaDate(patient, l.reversed.toList(), '2026-07-01')!['id'], 'B', reason: 'l’ordre des fiches ne décide pas');
    });
    test('à début égal : la dernière fiche prend la main, de façon déterministe', () {
      final l = [cv('A', '2026-06-01'), cv('B', '2026-06-01')];
      expect(couvertureALaDate(patient, l, '2026-07-01')!['id'], 'B');
      expect(couvertureALaDate(patient, l.reversed.toList(), '2026-07-01')!['id'], 'A');
    });
  });

  group('arbitrage : clore l’une des deux, avec motif', () {
    final l = [cv('A', '2026-01-01'), cv('B', '2026-06-01')];
    test('motif obligatoire, couverture inconnue, pas de conflit : refus nommés', () {
      expect(assArbitrerCouverture(patient, l, cloreId: 'A', motif: ' ', jour: '2026-11-16').code, 'MOTIF_REQUIS');
      expect(assArbitrerCouverture(patient, l, cloreId: 'Z', motif: 'x', jour: '2026-11-16').code, 'COUVERTURE_INCONNUE');
      expect(assArbitrerCouverture(patient, [cv('A', '2026-01-01')], cloreId: 'A', motif: 'x', jour: '2026-11-16').code, 'PAS_DE_CONFLIT');
    });
    test('clore la plus ancienne : fin la veille du début de l’autre ; le dossier suit la gardée', () {
      final r = assArbitrerCouverture(patient, l, cloreId: 'A', motif: 'Changement d’employeur confirmé au guichet', jour: '2026-11-16', auteur: 'LA DAF');
      expect(r.ok, isTrue);
      expect(r.fin, '2026-05-31');
      expect(r.gardeeId, 'B');
      expect(r.trace!['arbitrage'], 'Changement d’employeur confirmé au guichet');
      expect(r.majPatient!['souscripteurId'], 'S-B');
      final apres = [for (final c in l) c['id'] == 'A' ? {...c, ...r.trace!} : c];
      expect(assCouverturesEnConflit(apres), isEmpty);
      expect(couvertureALaDate(patient, apres, '2026-03-01')!['id'], 'A', reason: 'avant le 01/06, la couverture close reste celle de ses pièces');
    });
    test('clore la plus récente : elle n’aura jamais été en force (fin avant son début), la plus ancienne reste ; rien n’est supprimé', () {
      final r = assArbitrageDe(l, 'B');
      expect(r.fin, '2026-05-31');
      expect(r.majPatient!['souscripteurId'], 'S-A');
      final apres = [for (final c in l) c['id'] == 'B' ? {...c, ...r.trace!} : c];
      expect(couvertureALaDate(patient, apres, '2026-07-01')!['id'], 'A');
      expect(apres, hasLength(2));
    });
  });
}

AssArbitrageCouverture assArbitrageDe(List<F> l, String id) =>
    assArbitrerCouverture({'id': 'P1'}, l, cloreId: id, motif: 'Erreur de saisie hors ligne', jour: '2026-11-16');
