// Décisions Q1 à Q7 de la Direction de Baguidi (17/11/2026) : circuit de clôture (geste réservé), inventaire en clôture et validateur des achats (réglages),
// un droit par réglage, aucun rôle semé, proposition de prix (admin et DAF, pas le caissier), pièce d'un fileul mise de côté.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

void main() {
  final exo = <F>[
    {'id': 'E1', 'annee': 2030, 'statut': 'actif', 'etat': 'ouvert', 'source': 'journal'}
  ];
  final auj = DateTime(2030, 12, 31, 9);

  test('Q1/Q5 : le circuit et les trois réglages sont des gestes réservés, administrateur et DAF d\'origine, jamais le caissier ni le comptable', () {
    final d = DroitsGestes(fiches: const []);
    for (final g in [gesteCircuitCloture, gesteReglageFichiers, gesteReglageOcr, gesteReglageMecef]) {
      expect(d.rolesAvec(g, const ['admin', 'da', 'direction', 'comptable', 'caissier']), ['admin', 'da'], reason: g);
    }
    // un droit PAR réglage : en retirer un ne touche pas les autres
    final f = DroitsGestes(fiches: [
      {'role': 'da', 'droitsGestes': {gesteReglageOcr: false}}
    ]);
    expect(f.peut('da', gesteReglageOcr), isFalse);
    expect(f.peut('da', gesteReglageFichiers), isTrue);
    expect(f.peut('da', gesteReglageMecef), isTrue);
  });

  test('Q2 : un comptable seul ne démarre pas ; avec le droit il démarre mais ne clôture jamais ce qu\'il a démarré', () {
    expect(cpcDemarrerCloture(exo, const [], 2030, acteur: 'C', acteurId: 'U1', role: 'comptable', maintenant: auj).ok, isFalse);
    final r = cpcDemarrerCloture(exo, const [], 2030, acteur: 'C', acteurId: 'U1', role: 'comptable', maintenant: auj, autorise: true);
    expect(r.ok, isTrue);
    final enC = [
      {...exo.first, ...r.patch!}
    ];
    final v = cpcValiderCloture(enC, const [], 2030, motif: 'Conforme', acteur: 'C', acteurId: 'U1', role: 'comptable', maintenant: auj, autorise: true);
    expect(v.motif, contains('Signer n’est pas saisir'));
  });

  test('Q1 : l\'avertissement avant démarrage informe sans bloquer', () {
    final brouillon = <F>[
      {'numero': 'P1', 'date': '2030-03-01', 'compte': '706000', 'debit': 0, 'credit': 5, 'statut': 'brouillon'}
    ];
    final pre = cpcPreCloture(brouillon, 2030, exercices: exo);
    expect(pre.bloquants, isNotEmpty);
    final a = cpcAvertissementsDemarrage(pre);
    expect(a.any((x) => x.contains('brouillon')), isTrue);
    expect(a.last, contains('MISE DE CÔTÉ'));
    expect(cpcDemarrerCloture(exo, brouillon, 2030, acteur: 'D', role: 'da', maintenant: auj).ok, isTrue, reason: 'jamais bloquant');
  });

  test('Q1 : la mère met de côté la pièce d\'un fileul datée d\'un exercice clos (exercice_clos) ou en clôture (exercice_en_cloture)', () {
    final clos = [
      {...exo.first, 'etat': 'clos'}
    ];
    final enC = [
      {...exo.first, 'etat': 'en_cloture'}
    ];
    final p = {'numero': 'EC-1', 'date': '2030-05-01', 'origine': 'Saisie manuelle'};
    expect(cpcRefusPieceFileul(exo, p), isNull);
    expect(cpcRefusPieceFileul(clos, p)!.code, 'exercice_clos');
    expect(cpcRefusPieceFileul(enC, p)!.code, 'exercice_en_cloture');
    expect(cpcRefusPieceFileul(enC, p, roleAuteur: 'comptable'), isNull, reason: 'inventaire d\'un rôle réglé');
    expect(cpcRefusPieceFileul(enC, p, roleAuteur: 'comptable', rolesInventaire: const ['stock'])!.code, 'exercice_en_cloture');
    expect(cpcRefusPieceFileul(clos, {...p, 'origineCloture': 'cl'}), isNull);
    expect(cpcRefusPieceFileul(clos, {'numero': 'X'}), isNull);
  });

  test('Q3 : les rôles d\'inventaire en clôture sont un réglage', () {
    final enC = [
      {...exo.first, 'etat': 'en_cloture'}
    ];
    String? g(String role, [Iterable<String>? r]) => cpcGardeEcritures(enC, '2030-05-01', origine: 'Saisie manuelle', role: role, rolesInventaire: r);
    expect(g('comptable'), isNull);
    expect(g('stock'), isNotNull);
    expect(g('stock', const ['stock']), isNull);
    expect(g('comptable', const ['stock']), isNotNull);
    expect(definitionDeParametre(cleRolesInventaireCloture)!.defaut, reglageRolesTexte(rolesInventaireClotureDefaut));
  });

  test('Q4 : le validateur des achats est un réglage (DAF semée), lu par vues, dépôt et application', () {
    expect(definitionDeParametre(cleRolesValidateursAchats)!.defaut, reglageRolesTexte(rolesValidateursAchatsDefaut));
    expect(definitionDeParametre(cleLibelleValidateurAchats)!.defaut, libelleValidateurAchatsDefaut);
    expect(estArbitre('da'), isTrue);
    expect(estArbitre('admin'), isFalse);
    expect(estArbitre('admin', validateurs: reglageRoles('da, admin', const [])), isTrue);
    expect(reglageRoles('  ', rolesValidateursAchatsDefaut), rolesValidateursAchatsDefaut, reason: 'jamais de verrouillage');
    expect(vuesOffertes(role: 'comptable', droitVoir: true), isNot(contains('arbitrage')));
    final cmd = <F>[
      {'id': 'C1', 'reference': 'BC-1', 'statutCommande': 'attente_validation'}
    ];
    VerdictDepot dep(String role, Iterable<String>? v) => circuitDeposer(
        famille: circuitCommandeValidation, bon: cmd.first, role: role, acteur: 'A', poste: 'P', maintenant: auj, besoins: const [], commandes: cmd, depots: [], nouvelId: () => 'D1', validateurs: v);
    expect(dep('comptable', null).refus!.code, 'VALIDATION_RESERVEE');
    final ok = dep('comptable', const ['comptable']);
    expect(ok.ok, isTrue);
    final a = circuitAppliquer(ok.fiche!, besoins: const [], commandes: cmd, maintenant: auj, validateurs: const ['comptable'], libelleValidateur: 'Poste réglé');
    expect(a!.ecriture!.patch['valideePar'], 'Poste réglé');
    expect(circuitAppliquer(ok.fiche!, besoins: const [], commandes: cmd, maintenant: auj)!.code, 'VALIDATION_RESERVEE', reason: 'la mère refait le contrôle avec SON réglage');
  });

  test('Q6/Q7 : un rôle créé part de zéro et se coche ; admin et DAF proposent un prix, le caissier non', () {
    expect(DroitsGestes(fiches: const []).peut('role_cree', gesteValiderSeuil), isFalse);
    expect(DroitsGestes(fiches: [
      {'role': 'role_cree', 'droitsGestes': {gesteValiderSeuil: true}}
    ]).peut('role_cree', gesteValiderSeuil), isTrue);
    final rbac = (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
    final m = MatriceDroits.depuisJson(rbac);
    for (final r in ['admin', 'da']) {
      expect(m.peutEditer(r, 'cfg-tarifs'), isTrue, reason: r);
      expect(DroitsGestes(fiches: const []).peut(r, gesteProposerPrixAchat), isTrue, reason: r);
    }
    expect(m.peutEditer('caissier', 'cfg-tarifs'), isFalse);
    expect(DroitsGestes(fiches: const []).peut('caissier', gesteProposerPrixAchat), isFalse);
  });
}
