import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/verrou_secours_poste.dart';
import 'package:sigh_poste/sync/service_circuit_achats.dart';

/// Le lot « seuils » au poste : la valeur lue est la version datée en vigueur, sinon la valeur d'attente de la définition ; les consommateurs la reçoivent.
typedef M = Map<String, Object?>;

Magasin vide() => Magasin({'utilisateurs': <M>[], 'audit': <M>[], 'politiqueSecurite': <M>[], 'besoins': <M>[], 'notifications': <M>[]});

void main() {
  final auj = DateTime(2026, 11, 17, 9);

  test('sans fiche : la valeur d\'attente ; une version datée l\'emporte à partir de sa date seulement', () {
    final m = vide();
    expect(seuilClinique(m, 'achats.fenetreCircuitJours', auj), seuilSeme('achats.fenetreCircuitJours'));
    final s = serviceParametres(m, auteur: () => 'Poste mère', horloge: () => auj);
    s.semerDefauts();
    final r = s.regler('achats.fenetreCircuitJours', 21, '2026-12-01', motif: 'Décision de la Direction');
    expect(r.ok, isTrue, reason: '${r.refus}');
    expect(seuilClinique(m, 'achats.fenetreCircuitJours', DateTime(2026, 11, 30)), seuilSeme('achats.fenetreCircuitJours'));
    expect(seuilClinique(m, 'achats.fenetreCircuitJours', DateTime(2026, 12, 1)), 21);
  });

  test('une valeur hors des bornes de la définition retombe sur la valeur d\'attente, jamais sur zéro', () {
    final m = vide();
    final s = serviceParametres(m, auteur: () => 'Poste mère', horloge: () => auj);
    s.semerDefauts();
    s.regler('achats.fenetreCircuitJours', 9999, '2026-11-01', motif: 'essai hors bornes');
    expect(seuilClinique(m, 'achats.fenetreCircuitJours', auj), seuilSeme('achats.fenetreCircuitJours'));
  });

  test('le circuit des achats lit sa fenêtre au paramètre', () {
    final m = vide();
    final svc = ServiceCircuitAchats.de(m)..horloge = () => auj;
    expect(svc.fenetreJours, seuilSeme('achats.fenetreCircuitJours'));
    serviceParametres(m, auteur: () => 'Poste mère', horloge: () => auj)
      ..semerDefauts()
      ..regler('achats.fenetreCircuitJours', 15, '2026-11-01', motif: 'essai');
    expect(svc.fenetreJours, 15);
  });

  test('le verrou d\'un poste ordinaire : la politique de sécurité, sinon le réglage, sinon la valeur d\'attente', () {
    final m = vide();
    final v = VerrouSecoursPoste(m, auteur: () => 'Test', role: 'admin', horloge: () => auj);
    expect(v.delaiOrdinaire(), seuilSeme(cleDelaiVerrouOrdinaire));
    serviceParametres(m, auteur: () => 'Poste mère', horloge: () => auj)
      ..semerDefauts()
      ..regler(cleDelaiVerrouOrdinaire, 25, '2026-11-01', motif: 'essai');
    expect(v.delaiOrdinaire(), 25);
  });
}
