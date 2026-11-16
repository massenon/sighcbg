// Décisions Q1 à Q7 de la Direction de Baguidi (17/11/2026) : circuit de clôture (geste réservé), inventaire en clôture (réglage), validateur des achats (geste réservé depuis le 16/11/2026),
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

  // Direction de Baguidi, 16/11/2026 : Q4 REMPLACÉE. Le validateur des commandes n'est plus un réglage de clinique (`achats.rolesValidateurs`, v20, DAF + Direction + administrateur semés)
  // mais le GESTE RÉSERVÉ `achats_valider` de la fiche RBAC : la Directrice Administrative SEULE d'origine (RG-04), étendu par décision tracée. Le POSTE porté sur la pièce reste un réglage.
  test('Q4 (remplacée le 16/11/2026) : valider les achats est un geste réservé, la DAF seule d\'origine ; la mère refait le contrôle avec SA matrice', () {
    final g = gesteReserve(gesteValiderAchats)!;
    expect(g.rolesDefaut, ['da'], reason: 'RG-04 : la Directrice Administrative seule');
    expect(g.module, 'M7');
    final origine = DroitsGestes(fiches: const []);
    expect(origine.rolesAvec(gesteValiderAchats, const ['admin', 'da', 'direction', 'comptable', 'stock', 'caissier']), ['da'],
        reason: 'l\'administrateur système et la Direction ne l\'ont PAS d\'origine');
    expect(definitionDeParametre(cleRolesValidateursAchatsRetiree), isNull, reason: 'le réglage v20 est retiré du registre : plus semé, plus affiché');
    expect(definitionDeParametre(cleLibelleValidateurAchats)!.defaut, libelleValidateurAchatsDefaut, reason: 'le POSTE porté sur la pièce reste un réglage (un libellé, pas un droit)');
    expect(estArbitre('da', origine), isTrue);
    expect(estArbitre('admin', origine), isFalse);
    expect(estArbitre('direction', origine), isFalse);
    expect(vuesOffertes(role: 'admin', droitVoir: true, gestes: origine), isNot(contains('arbitrage')));
    expect(vuesOffertes(role: 'da', droitVoir: true, gestes: origine), contains('arbitrage'));
    // La Direction étend le geste à un rôle : décision de la fiche RBAC.
    final etendu = DroitsGestes(fiches: [
      {'role': 'direction', 'droitsGestes': {gesteValiderAchats: true}}
    ]);
    expect(estArbitre('direction', etendu), isTrue);
    expect(vuesOffertes(role: 'direction', droitVoir: true, gestes: etendu), contains('arbitrage'));
    // Retiré à la DAF : plus personne ne valide (aucun repli silencieux sur une liste en dur).
    expect(estArbitre('da', DroitsGestes(fiches: [{'role': 'da', 'droitsGestes': {gesteValiderAchats: false}}])), isFalse);
    // Module M7 fermé : le geste tombe pour tous ; rôle archivé : aucun geste.
    expect(DroitsGestes(fiches: const [], ecranActif: (e, m) => m != 'M7').peut('da', gesteValiderAchats), isFalse);
    expect(DroitsGestes(fiches: const [], estArchive: (r) => r == 'da').peut('da', gesteValiderAchats), isFalse);
    final cmd = <F>[
      {'id': 'C1', 'reference': 'BC-1', 'statutCommande': 'attente_validation'}
    ];
    VerdictDepot dep(String role, DroitsGestes gestes) => circuitDeposer(
        famille: circuitCommandeValidation, bon: cmd.first, role: role, acteur: 'A', poste: 'P', maintenant: auj, besoins: const [], commandes: cmd, depots: [], nouvelId: () => 'D1', gestes: gestes);
    expect(dep('admin', origine).refus!.code, 'VALIDATION_RESERVEE', reason: 'l\'administrateur ne dépose pas sans le geste');
    expect(dep('admin', origine).refus!.motif, contains('Valider les achats'));
    final accordeComptable = DroitsGestes(fiches: [
      {'role': 'comptable', 'droitsGestes': {gesteValiderAchats: true}}
    ]);
    final ok = dep('comptable', accordeComptable);
    expect(ok.ok, isTrue);
    final a = circuitAppliquer(ok.fiche!, besoins: const [], commandes: cmd, maintenant: auj, gestes: accordeComptable, libelleValidateur: 'Poste réglé');
    expect(a!.ecriture!.patch['valideePar'], 'Poste réglé');
    expect(circuitAppliquer(ok.fiche!, besoins: const [], commandes: cmd, maintenant: auj, gestes: origine)!.code, 'VALIDATION_RESERVEE',
        reason: 'la mère refait le contrôle avec SA matrice : la décision retirée entre le dépôt et l\'application fait foi');
  });

  test('Q4 : une ancienne fiche du réglage `achats.rolesValidateurs` en base ne décide plus rien', () {
    final versions = <F>[
      {'id': '$cleRolesValidateursAchatsRetiree@1', 'statut': 'actif', 'cle': cleRolesValidateursAchatsRetiree, 'valeur': 'comptable,admin,direction', 'version': 1, 'dateEffet': '2026-01-01'}
    ];
    final s = ServiceParametres(
        definitions: definitionsParametres,
        lireVersions: () => versions,
        lireUsages: () => const [],
        ecrireVersion: (id, c) => versions.add({'id': id, ...c}),
        ecrireUsage: (_, __) {},
        auteur: () => 'T',
        maintenant: () => auj);
    expect(s.parFamille('2030-12-31').values.expand((l) => l).map((p) => p.definition.cle), isNot(contains(cleRolesValidateursAchatsRetiree)),
        reason: 'l\'écran des paramètres ne l\'affiche plus');
    expect(s.semerDefauts(), definitionsParametres.length, reason: 'rien n\'est semé pour la clé retirée');
    // Le droit ne lit que la matrice : la fiche ancienne qui nommait le comptable, l'administrateur et la Direction n'y change rien.
    final d = DroitsGestes(fiches: const []);
    for (final r in ['comptable', 'admin', 'direction']) {
      expect(estArbitre(r, d), isFalse, reason: r);
    }
  });

  test('E3263 : sans le geste, le formulaire ne pose plus la validation d\'office (besoin accordé, commande validée)', () {
    final ligne = <F>[
      {'designation': 'Gants', 'quantite': 2, 'prix': 100}
    ];
    expect(() => bonEnregistre(saisie: {'etape': 'accorde'}, lignes: ligne, bons: const [], peutValider: false), throwsA(isA<RefusAchat>()));
    final enDa = bonEnregistre(saisie: {'etape': 'validation_da'}, lignes: ligne, bons: const [], peutValider: false);
    expect(enDa['valideePar'], isNull, reason: 'la DAF n\'est plus portée validatrice d\'un bon qu\'elle n\'a pas arbitré');
    expect(bonEnregistre(saisie: {'etape': 'accorde'}, lignes: ligne, bons: const [], peutValider: true)['valideePar'], directriceAdministrative);
    expect(bonEnregistre(saisie: {'etape': 'livre'}, lignes: ligne, bons: const [], existant: {'etape': 'accorde', 'valideePar': 'X'}, peutValider: false)['valideePar'], isNull,
        reason: 'un bon déjà validé avance sans le geste (le validateur connu n\'est pas réécrit ici)');
    expect(bonEnregistre(saisie: {'etape': 'accorde'}, lignes: ligne, bons: const [])['valideePar'], directriceAdministrative, reason: 'sans information (vecteurs) : la règle de la maquette');
    expect(() => commandeEnregistree(saisie: {'statutCommande': 'validee'}, lignes: ligne, fournisseurs: const [], commandes: const [], jour: '2030-12-31', peutValider: false),
        throwsA(isA<RefusAchat>()));
    expect(commandeEnregistree(saisie: {'statutCommande': 'attente_validation'}, lignes: ligne, fournisseurs: const [], commandes: const [], jour: '2030-12-31', peutValider: false)['valideePar'],
        isNull);
    expect(
        commandeEnregistree(
            saisie: {'statutCommande': 'transmise'},
            lignes: ligne,
            existante: {'statutCommande': 'validee', 'valideePar': 'Directrice administrative'},
            fournisseurs: const [],
            commandes: const [],
            jour: '2030-12-31',
            peutValider: false)['statutCommande'],
        'transmise',
        reason: 'une commande déjà validée se transmet sans le geste');
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
