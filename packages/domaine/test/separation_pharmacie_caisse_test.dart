// SÉPARER LA PHARMACIE DE LA CAISSE PAR LA SEULE MATRICE (Direction de Baguidi, 16/11/2026). Aujourd'hui la Caissière-Dispensatrice tient les deux et le rôle pharmacien (fiche RBAC03,
// rouvert le 06/11/2026) reste actif : RIEN ne change le jour de la conversion. Demain, la clinique donne la dispensation au pharmacien et la caisse au caissier en cochant des cases
// (droits d'écran de la fiche, gestes réservés), sans toucher au code. Ce test le prouve sur la matrice EN FORCE (rbac.json engendré + manifeste + fiches du jeu livré).
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

List<F> _lire(String chemin) => [for (final f in jsonDecode(File(chemin).readAsStringSync()) as List) (f as Map).cast<String, Object?>()];

void main() {
  final base = MatriceDroits.depuisJson((jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>());
  final manifeste = Manifeste.depuisJson((jsonDecode(File('../referentiels/data/manifeste.json').readAsStringSync()) as Map).cast<String, Object?>());
  final jeu = _lire('../../apps/poste/assets/donnees/jeu/rbac.json');
  final modules = _lire('../../apps/poste/assets/donnees/jeu/modulesActifs.json');

  ({MatriceDroits m, DroitsGestes g}) enForce(List<F> fiches) {
    final m = superposerDroits(base, manifeste, rbac: fiches, modulesActifs: modules);
    return (m: m, g: DroitsGestes(fiches: fiches, estArchive: m.estArchive, ecranActif: m.ecranActif));
  }

  /// La décision de la Direction, telle que l'écran « Rôles & permissions » l'écrit dans les fiches : des cases, aucun code.
  List<F> separer(List<F> fiches) => [
        for (final f in fiches)
          if (f['role'] == 'pharmacien')
            {
              ...f,
              'droitsEcrans': {
                ...?(f['droitsEcrans'] as Map?)?.cast<String, Object?>(),
                'm6-dispensation': {'voir': true, 'editer': true, 'annuler': true},
                'm8-caisse': {'voir': false},
              },
              'droitsGestes': {gesteAlertesCaisse: false, gesteMecefRetransmettre: false},
            }
          else if (f['role'] == 'caissier')
            {
              ...f,
              'droitsEcrans': {
                ...?(f['droitsEcrans'] as Map?)?.cast<String, Object?>(),
                'm6-dispensation': {'voir': false},
              },
              'droitsGestes': {gesteAlertesSeuilStock: false, gesteAlertesPeremption: false},
            }
          else
            f
      ];

  test('AUJOURD’HUI (jeu livré, aucune décision) : la Caissière-Dispensatrice encaisse ET délivre ; le pharmacien reste un rôle actif ; les origines reprennent les listes d’avant', () {
    final e = enForce(jeu);
    expect(e.m.estArchive('pharmacien'), isFalse, reason: 'rôle rouvert le 06/11/2026, gardé');
    expect(e.m.peutEditer('caissier', 'm8-caisse'), isTrue);
    expect(e.m.peutEditer('caissier', 'm6-dispensation'), isTrue);
    expect(e.m.peutEditer('pharmacien', 'm6-dispensation'), isTrue);
    // Les gestes : EXACTEMENT les listes qui vivaient en dur (aucun changement de comportement).
    const tous = ['admin', 'direction', 'dm', 'da', 'medecin', 'infirmier', 'pharmacien', 'laborantin', 'stock', 'caissier', 'comptable', 'reception', 'assistant_comptable', 'aide_comptable'];
    expect(e.g.rolesAvec(gesteAlertesCaisse, tous), ['caissier']);
    expect(e.g.rolesAvec(gesteAlertesStock, tous), ['da', 'pharmacien', 'stock']);
    expect(e.g.rolesAvec(gesteAlertesSeuilStock, tous), ['da', 'pharmacien', 'stock', 'caissier']);
    expect(e.g.rolesAvec(gesteAlertesPeremption, tous), ['pharmacien', 'laborantin', 'stock', 'caissier']);
    expect(e.g.rolesAvec(gesteAlertesMecefRejet, tous), ['da', 'caissier', 'comptable', 'assistant_comptable']);
    expect(e.g.rolesAvec(gesteMecefRetransmettre, tous), ['admin', 'da', 'caissier']);
    expect(e.g.rolesAvec(gesteMecefRetransmettreSansLimite, tous), ['admin', 'da']);
  });

  test('SÉPARATION par la seule matrice : le pharmacien délivre sans la caisse, le caissier encaisse sans la dispensation', () {
    final e = enForce(separer(jeu));
    // Le pharmacien : la dispensation, pas la caisse.
    expect(e.m.peutEditer('pharmacien', 'm6-dispensation'), isTrue);
    expect(e.m.peutVoir('pharmacien', 'm8-caisse'), isFalse);
    expect(e.g.peut('pharmacien', gesteAlertesStock), isTrue);
    expect(e.g.peut('pharmacien', gesteAlertesCaisse), isFalse);
    expect(refusRetransmission({'statutMecef': 'rejete'}, 'pharmacien', gestes: e.g)?.code, 'RETRANSMISSION_INTERDITE');
    // Le caissier : la caisse, pas la dispensation.
    expect(e.m.peutEditer('caissier', 'm8-caisse'), isTrue);
    expect(e.m.peutVoir('caissier', 'm6-dispensation'), isFalse);
    expect(e.g.peut('caissier', gesteAlertesCaisse), isTrue);
    expect(e.g.peut('caissier', gesteAlertesSeuilStock), isFalse);
    expect(e.g.peut('caissier', gesteAlertesPeremption), isFalse);
    expect(refusRetransmission({'statutMecef': 'rejete'}, 'caissier', gestes: e.g), isNull);
    expect(refusRetransmission({'statutMecef': 'rejete', 'retransmissions': 1}, 'caissier', gestes: e.g)?.code, 'RETRANSMISSION_RESERVEE');
    // Rien d'autre ne bouge : les autres rôles gardent exactement leurs droits sur ces écrans.
    final avant = enForce(jeu).m;
    for (final r in ['stock', 'da', 'admin', 'comptable', 'medecin']) {
      for (final ecran in ['m8-caisse', 'm6-dispensation']) {
        expect(e.m.droit(r, ecran), avant.droit(r, ecran), reason: '$r / $ecran');
      }
    }
  });
}
