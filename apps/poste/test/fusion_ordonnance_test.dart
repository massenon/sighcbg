// DÉLIVRANCE LIGNE PAR LIGNE (16/11/2026, E3305) : la famille de fusion des marques de délivrance. Une ligne délivrée ne redevient jamais « à délivrer » ;
// deux postes qui servent la même ligne hors ligne sont SIGNALÉS, jamais corrigés en silence.
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/sync/fusion_activite.dart';
import 'package:sigh_poste/sync/pont_activite.dart' show collectionsActivite, marqueursLocaux;

typedef M = Map<String, Object?>;

M ligne(String p, {String? le, String? par, String? mvt, bool aValoriser = false}) => {
      'produitId': p,
      'produit': p,
      'quantite': 1,
      if (aValoriser) ...{'prix': null, 'total': null, 'prixAValoriser': true} else ...{'prix': 100, 'total': 100},
      if (le != null) ...{'delivreLe': le, 'delivrePar': par, 'delivreMouvement': mvt},
    };

M ord(List<M> meds, [String statut = 'en_attente']) => {'id': 'O1', 'numero': 'ORD-1', 'statutDispensation': statut, 'medicaments': meds};

void main() {
  test('deux postes délivrent chacun UNE ligne différente : les deux marques survivent, l’état suit les lignes (aucune ligne ne redevient délivrable)', () {
    final ici = ord([ligne('A', le: '2026-11-16T09:00:00', par: 'X', mvt: 'M000001'), ligne('B'), ligne('C')], 'partielle');
    final la = ord([ligne('A'), ligne('B', le: '2026-11-16T09:01:00', par: 'Y', mvt: 'M000002'), ligne('C')], 'partielle');
    // La fusion champ à champ a gardé la liste d'ICI (changée ici) : celle de là-bas était perdue.
    final r = fusionnerOrdonnance({...ici}, ici, la);
    final meds = (r['medicaments'] as List).cast<M>();
    expect(meds[0]['delivreMouvement'], 'M000001');
    expect(meds[1]['delivreMouvement'], 'M000002');
    expect(meds[2].containsKey('delivreLe'), isFalse);
    expect(r['statutDispensation'], 'partielle');
    expect(r.containsKey('delivranceEnDoublon'), isFalse);
    final deux = fusionnerOrdonnance({...ord([meds[0], meds[1]], 'partielle')}, ord([meds[0], ligne('B')], 'partielle'), ord([ligne('A'), meds[1]], 'partielle'));
    expect(deux['statutDispensation'], 'servie', reason: 'toutes les lignes marquées');
    expect(deux['dispensePar'], isNull, reason: 'aucune version ne portait la date de clôture : elle n’est pas inventée');
  });

  test('la MÊME ligne délivrée par deux postes : la plus ancienne est gardée et la ligne est SIGNALÉE (deux sorties ont eu lieu)', () {
    final ici = ord([ligne('A', le: '2026-11-16T09:05:00', par: 'X', mvt: 'M000003')], 'servie');
    final la = ord([ligne('A', le: '2026-11-16T09:00:00', par: 'Y', mvt: 'M000001')], 'servie');
    final r = fusionnerOrdonnance({...ici}, ici, la);
    expect(r['delivranceEnDoublon'], [0]);
    expect(((r['medicaments'] as List).single as M)['delivrePar'], 'Y');
    // Les mêmes marques des deux côtés (la même délivrance revenue par le journal) : pas un doublon.
    final meme = fusionnerOrdonnance({...ici}, ici, ici);
    expect(meme.containsKey('delivranceEnDoublon'), isFalse);
  });

  test('une ligne VALORISÉE l’emporte sur une ligne « prix à valoriser » ; l’état « servie » de l’ancien moteur ne recule pas', () {
    final ici = ord([ligne('A', aValoriser: true)]);
    final la = ord([ligne('A')]);
    final r = fusionnerOrdonnance({...ici}, ici, la);
    expect(((r['medicaments'] as List).single as M)['total'], 100);
    expect(((r['medicaments'] as List).single as M)['prixAValoriser'], isNot(true));
    final ancien = ord([ligne('A'), ligne('B')], 'servie');
    expect(fusionnerOrdonnance({...ancien}, ancien, ord([ligne('A'), ligne('B')]))['statutDispensation'], 'servie');
  });

  test('le marqueur est LOCAL (il ne voyage pas) ; les ordonnances ne voyagent pas encore : la délivrance n’a lieu que sur le poste qui tient l’ordonnance', () {
    expect(marqueursLocaux, contains('delivranceEnDoublon'));
    // Constat consigné (E3305) : si cet ensemble change, la règle ci-dessus s'applique d'office et le cas hors ligne passe de « impossible » à « détecté ».
    expect(collectionsActivite.contains('ordonnances'), isFalse);
  });
}
