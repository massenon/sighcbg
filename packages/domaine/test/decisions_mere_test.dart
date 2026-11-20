// SECTION AI (Direction, 16/11/2026) : les décisions prises sur un fileul et que la mère applique.
//  (1) au-delà du délai réglé en base (4 h semées), une alerte vers le validateur concerné et l'administrateur, sans blocage ;
//  (2) la mère vérifie le compte inscrit sur la décision (existe, porte ce rôle, non archivé), sinon refus nommé à code stable ;
//  (3) la validation porte la date de SIGNATURE, la date d'application à côté ;
//  (4) la pastille compte les TROIS files avec leur âge.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  final comptes = <Map<String, Object?>>[
    {'id': 'USR001', 'identifiant': 'm-001@clinique.bj', 'role': 'direction', 'statut': 'actif', 'actif': true},
    {'id': 'USR002', 'identifiant': 'm-002@clinique.bj', 'role': 'comptable', 'statut': 'archive'},
    {'id': 'USR003', 'identifiant': 'm-003@clinique.bj', 'role': 'rh', 'actif': false},
    {'id': 'USR004', 'identifiant': 'm-004@clinique.bj', 'role': 'medecin', 'roles': ['medecin', 'dm']},
  ];

  group('(2) le compte signataire', () {
    test('existe, porte ce rôle, actif : accepté (par identifiant de compte ou de connexion, rôle principal ou secondaire)', () {
      expect(verifierCompteSignataire(compte: 'USR001', role: 'direction', par: 'X', comptes: comptes), isNull);
      expect(verifierCompteSignataire(compte: 'm-001@clinique.bj', role: 'direction', par: 'X', comptes: comptes), isNull);
      expect(verifierCompteSignataire(compte: 'USR004', role: 'dm', par: 'X', comptes: comptes), isNull);
    });
    test('refus nommés, codes stables : aucun compte, compte inconnu, rôle différent, archivé ou désactivé', () {
      expect(verifierCompteSignataire(compte: null, role: 'direction', par: 'X', comptes: comptes)!.code, codeCompteNonInscrit);
      expect(verifierCompteSignataire(compte: '  ', role: 'direction', par: 'X', comptes: comptes)!.code, codeCompteNonInscrit);
      expect(verifierCompteSignataire(compte: 'USR999', role: 'direction', par: 'X', comptes: comptes)!.code, codeCompteInconnu);
      expect(verifierCompteSignataire(compte: 'USR001', role: 'da', par: 'X', comptes: comptes)!.code, codeCompteRoleDifferent);
      expect(verifierCompteSignataire(compte: 'USR002', role: 'comptable', par: 'X', comptes: comptes)!.code, codeCompteArchive);
      expect(verifierCompteSignataire(compte: 'USR003', role: 'rh', par: 'X', comptes: comptes)!.code, codeCompteArchive);
      expect(verifierCompteSignataire(compte: 'USR001', role: 'da', par: 'Agent Y', comptes: comptes)!.motif, contains('Agent Y'));
      expect([codeCompteNonInscrit, codeCompteInconnu, codeCompteRoleDifferent, codeCompteArchive], ['COMPTE_NON_INSCRIT', 'COMPTE_INCONNU', 'COMPTE_ROLE_DIFFERENT', 'COMPTE_ARCHIVE']);
    });
  });

  group('(1) et (4) les décisions en attente de la mère', () {
    final maintenant = DateTime.utc(2026, 11, 16, 15);
    final validations = [
      {'id': 'VDP1', 'genre': valGenreReferentiel, 'famille': 'actes', 'cible': 'A1', 'libelle': 'Tarifs des actes', 'etat': valDepotDeposee, 'demandePar': 'DAF', 'demandeRole': 'da', 'demandeLe': '2026-11-16T09:00:00.000Z'},
      {'id': 'VDP2', 'genre': valGenreCircuitAchat, 'famille': circuitCommandeValidation, 'cible': 'BC1', 'etat': valDepotDeposee, 'demandeLe': '2026-11-16T14:00:00.000Z'},
      {'id': 'VDP3', 'genre': valGenreReferentiel, 'famille': 'actes', 'cible': 'A2', 'etat': valDepotAppliquee, 'demandeLe': '2026-11-15T09:00:00.000Z'},
    ];
    final prix = [
      {'id': 'DT1', 'genre': 'proposition', 'code': 'MG01', 'etat': 'deposee', 'demandeLe': '2026-11-16', 'demandeInstant': '2026-11-16T12:30:00.000Z'},
      {'id': 'DT2', 'genre': 'decision', 'etat': 'appliquee', 'demandeLe': '2026-11-16'},
    ];
    final imports = [
      {'id': 'DI1', 'jeu': 'tarifs', 'jeuLibelle': 'Tarifs', 'etat': 'en_attente', 'demandeLe': '2026-11-16', 'demandeInstant': '2026-11-16T10:00:00.000Z'},
      {'id': 'DI2', 'jeu': 'tarifs', 'etat': 'en_attente', 'traiteLe': '2026-11-16', 'demandeLe': '2026-11-16'},
    ];
    final liste = decisionsEnAttenteMere(validations: validations, demandesPrix: prix, demandesImport: imports);

    test('la pastille compte les TROIS files (en attente seulement) et dit l’âge de la plus ancienne', () {
      expect([for (final d in liste) d.id], ['VDP1', 'DI1', 'DT1', 'VDP2'], reason: 'de la plus ancienne à la plus récente');
      final r = resumerDecisionsMere(liste, maintenant, delaiHeures: 4);
      expect([r.validations, r.prix, r.imports, r.total, r.enRetard], [2, 1, 1, 4, 2]);
      expect(r.plusAncienne, const Duration(hours: 6));
      expect(r.libelle, '4 décisions en attente de la mère');
      expect(r.detail, allOf(contains('2 validations'), contains('1 demande de prix'), contains('1 demande d’import'), contains('6 h 0 min')));
      expect(resumerDecisionsMere(const [], maintenant).libelle, '', reason: 'à zéro, rien à dire');
    });

    test('au-delà du délai : seules les décisions qui l’atteignent ; le délai vient du registre (4 h semées), une valeur invalide retombe sur le défaut', () {
      expect([for (final d in decisionsEnRetard(liste, maintenant, 4)) d.id], ['VDP1', 'DI1']);
      final def = definitionDeParametre(cleDelaiAlerteMere)!;
      expect([def.defaut, def.famille, def.type, def.mobile], [4, 'validations', TypeParametre.entier, false]);
      expect(def.source, contains('16/11/2026'));
      expect(delaiAlerteMereDepuis(2, defaut: 4), 2);
      expect(delaiAlerteMereDepuis(0, defaut: 4), 4);
      expect(delaiAlerteMereDepuis(null, defaut: 4), 4);
    });

    test('les destinataires : le validateur lu de ce qui décide déjà (registre, geste de la matrice, arbitres des lots), puis l’administrateur — jamais deux fois', () {
      final parId = {for (final d in liste) d.id: d};
      expect(destinatairesAlerteDecision(parId['VDP1']!, gesteCircuit: 'g-achats', gestePrix: 'g-prix'), [...valFamille('actes')!.roles.where((r) => r != posteAdministrateur), posteAdministrateur]);
      expect(destinatairesAlerteDecision(parId['VDP2']!, gesteCircuit: 'g-achats', gestePrix: 'g-prix'), ['geste:g-achats', posteAdministrateur]);
      expect(destinatairesAlerteDecision(parId['DT1']!, gesteCircuit: 'g-achats', gestePrix: 'g-prix'), ['geste:g-prix', posteAdministrateur]);
      expect(destinatairesAlerteDecision(parId['DI1']!, gesteCircuit: 'g-achats', gestePrix: 'g-prix', rolesArbitreImport: ['da', 'admin']), ['da', 'admin']);
    });
  });

  group('(3) date de signature et date d’application', () {
    test('le dépôt appliqué par la mère : la validation porte signeLe (le geste) et appliqueLe (la mère) ; le geste direct n’en porte aucune', () {
      final fiches = <String, List<Map<String, Object?>>>{
        'actes': [
          {'id': 'A1', 'code': 'A1', 'libelle': 'Acte', 'prix': 5000, 'tarifProvisoire': true, 'statut': 'actif'}
        ],
      };
      List<Map<String, Object?>> lire(String n) => fiches[n] ?? const [];
      final role = valFamille('actes')!.roles.first;
      final depot = {
        'id': 'VDP1',
        'statut': 'actif',
        'genre': valGenreReferentiel,
        'famille': 'actes',
        'cible': 'A1',
        'etat': valDepotDeposee,
        'demandeRole': role,
        'demandePar': 'Agent',
        'demandeLe': '2026-11-16T09:00:00.000Z',
      };
      final a = valAppliquerDepot(depot, lire: lire, libelles: const {}, maintenant: DateTime.utc(2026, 11, 16, 17))!;
      expect(a.etat, valDepotAppliquee);
      final traces = a.validation!.patch!;
      expect(traces['signeLe'], '2026-11-16T09:00:00.000Z');
      expect(traces['valideLe'], traces['signeLe'], reason: 'la validation porte la date de SIGNATURE');
      expect(traces['appliqueLe'], '2026-11-16T17:00:00.000Z');
      final direct = valValiderReferentiel('actes', 'A1', role: role, acteur: 'Agent', maintenant: DateTime.utc(2026, 11, 16, 9), lire: lire, libelles: const {});
      expect(direct.patch!.containsKey('appliqueLe'), isFalse);
    });
  });
}
