// AUCUNE LISTE DE RÔLES EN DUR (compléments du 16/11/2026) : chaque liste qui vivait en dur est devenue un geste réservé. Ce test FIGE les listes d'AVANT (recopiées ici,
// dans un test, une fois) et prouve que la conversion n'a changé AUCUN comportement : l'origine de chaque geste est la liste d'avant, et les moteurs répondent comme avant
// sans décision. Puis il prouve que la matrice décide désormais : une fiche de rôle ACCORDE à un rôle hors liste et RETIRE à un rôle d'origine.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

F fiche(String role, Map<String, bool> gestes) => {'id': 'R-$role', 'role': role, 'statut': 'actif', 'droitsGestes': gestes};

/// Les listes d'AVANT la conversion, telles qu'elles étaient écrites dans le code (fichier : constante).
const _avant = <String, List<String>>{
  gesteAlertesComptable: ['comptable', 'assistant_comptable', 'aide_comptable', 'da'], // centre_notifications : _postesNotif['comptable']
  gesteAlertesDirection: ['direction', 'da', 'dm'],
  gesteAlertesImagerie: ['echographiste', 'responsable_radiologie'],
  gesteAlertesLaboratoire: ['laborantin'],
  gesteAlertesPrescripteur: ['medecin', 'chirurgien', 'anesthesiste', 'dm'],
  gesteAlertesSalleSoins: ['infirmier', 'aide_soignant', 'surveillant'],
  gesteAlertesHospitalisation: ['infirmier', 'aide_soignant', 'surveillant', 'medecin'],
  gesteAlertesEcheancesFiscales: ['comptable', 'da', 'assistant_comptable', 'direction'],
  gesteAlertesCreances: ['da', 'comptable', 'direction', 'assistant_comptable', 'aide_comptable', 'responsable_assurance'],
  gesteAlertesBesoinsAValider: ['da', 'direction'],
  gesteAlertesEcrituresBrouillon: ['comptable', 'da', 'aide_comptable'],
  gesteAlertesDoublonsSync: ['direction', 'da', 'comptable', 'admin'],
  gesteConflitsTrancher: ['da', 'direction', 'admin'], // pair.dart : rolesQuiTranchentPair (hors l'appareil « mere »)
  gesteSyncValiderFlux: ['da', 'admin'], // pair.dart : rolesQuiValidentPair
  gesteSystemeAdministrer: ['admin', 'da'], // mrcRolesAdmin, rolesAdminMere, rolesRubanSysteme
  gesteInstallationConduire: ['admin'], // coque : _role == 'admin'
  gesteDoubleFacteurImpose: ['dm', 'da', 'direction', 'admin'], // secRolesDoubleFacteur, cfbMfaParDefaut
  gesteComptesReinitialiser: ['admin'], // accRefusReinitialisation
  gesteReglageVerrouSecours: ['admin', 'da'], // rolesVerrouSecours
  gesteReglageHorsSite: ['admin', 'da'], // shRolesReglage
  gesteFiscalValiderConfiguration: ['direction', 'da', 'admin'], // cfbRolesValidation
  gesteAibTenir: ['comptable', 'admin', 'da'], // aibRolesEcriture
  gesteValidationsVueComplete: ['direction', 'da', 'admin'], // valVueComplete
  gesteValidationsCentreElargi: ['da', 'admin', 'direction', 'dm', 'comptable', 'surveillant', 'agentadmin'], // qual_validations : _elargis
  gesteValiderRefDirection: ['direction', 'da', 'admin'],
  gesteValiderRefLabo: ['laborantin'],
  gesteValiderRefPathologies: ['dm', 'medecin'],
  gesteValiderRefImagerie: ['echographiste', 'responsable_radiologie', 'dm'],
  gesteValiderRefBloc: ['chirurgien', 'anesthesiste'],
  gesteValiderRefRepartition: ['comptable', 'direction', 'da', 'admin'],
  gesteValiderRefBaremeAib: ['direction', 'da', 'admin', 'comptable'],
  gesteRhRegler: ['admin', 'da'], // planning_rh, pointage_badge, espace_mes : role == 'admin' || role == 'da'
  gesteRhPlanningIndividuel: ['surveillant', 'da', 'admin'], // « Planning individuel » : DA et admin l'écrivaient par rh_regler, le surveillant s'y ajoute
  gesteRhEncadrer: ['surveillant', 'da', 'admin'],
  gesteRhEtapeSurveillant: ['surveillant', 'admin'], // rolesEtapeRh['surveillant']
  gesteRhEtapeDaf: ['da', 'admin'], // rolesEtapeRh['daf']
  gesteRhPointerBadge: ['surveillant', 'da', 'admin', 'direction', 'rh'], // rolesPointageBadge
  gesteImagerieExecuter: ['echographiste', 'responsable_radiologie'], // rolesExecutantsImagerie
  gesteRubriquesChirurgicales: ['chirurgien'], // cs_dossiers : c.role == 'chirurgien'
  gesteAchatsRegistre: ['comptable', 'stock', 'da', 'direction', 'admin', 'aide_comptable'], // rolesAchat
};

const _tousLesRoles = [
  'admin', 'direction', 'dm', 'da', 'medecin', 'infirmier', 'pharmacien', 'laborantin', 'stock', 'caissier', 'comptable', 'rh', 'reception', 'agentadmin', 'ambulancier',
  'aide_soignant', 'echographiste', 'surveillant', 'assistant_comptable', 'chirurgien', 'anesthesiste', 'aide_comptable', 'responsable_radiologie', 'sage_femme',
  'responsable_assurance', 'un_role_cree_en_exploitation',
];

void main() {
  test('AUCUN changement de comportement : l’origine de chaque geste converti est EXACTEMENT la liste d’avant, rôle par rôle', () {
    final d = gestesOrigine();
    for (final e in _avant.entries) {
      final g = gesteReserve(e.key);
      expect(g, isNotNull, reason: e.key);
      expect(g!.rolesDefaut, e.value, reason: '${e.key} : origine = liste d’avant, dans le même ordre');
      expect(g.module, '*', reason: '${e.key} : transverse, ne tombe pas avec une activité (comme la liste qu’il remplace)');
      for (final r in _tousLesRoles) {
        expect(d.peut(r, e.key), e.value.contains(r), reason: '${e.key} / $r');
      }
    }
  });

  test('les moteurs du domaine répondent comme avant sans décision, puis suivent la matrice : accorder hors liste, retirer à l’origine', () {
    // Configuration fiscale.
    expect(cfbControleValidation(role: 'direction'), isNull);
    expect(cfbControleValidation(role: 'comptable')?.code, 'VALIDATION_RESERVEE');
    expect(cfbControleValidation(role: 'comptable', gestes: DroitsGestes(fiches: [fiche('comptable', {gesteFiscalValiderConfiguration: true})])), isNull);
    expect(cfbControleValidation(role: 'direction', gestes: DroitsGestes(fiches: [fiche('direction', {gesteFiscalValiderConfiguration: false})]))?.code, 'VALIDATION_RESERVEE');
    expect(cfbRolesValidation, ['direction', 'da', 'admin'], reason: 'l’origine affichée, dérivée du référentiel');
    // Barème de l'AIB.
    expect(aibMotifEcriture(role: 'comptable', libelleRole: 'Comptable'), isNull);
    expect(aibMotifEcriture(role: 'direction', libelleRole: 'Direction')?['code'], 'AIB_ECRITURE_RESERVEE');
    expect(aibMotifEcriture(role: 'comptable', libelleRole: 'Comptable', gestes: DroitsGestes(fiches: [fiche('comptable', {gesteAibTenir: false})]))?['code'], 'AIB_ECRITURE_RESERVEE');
    // Double facteur.
    expect(secDoubleFacteurExige('direction'), isTrue);
    expect(secDoubleFacteurExige('caissier'), isFalse);
    expect(secDoubleFacteurExige('caissier', gestes: DroitsGestes(fiches: [fiche('caissier', {gesteDoubleFacteurImpose: true})])), isTrue);
    expect(cfbMfaParDefaut('admin'), isTrue);
    expect(cfbMfaParDefaut('medecin'), isFalse);
    // Verrou de secours, copie hors site, réinitialisation.
    expect(controlerDesignationPosteSecours(role: 'da'), isNull);
    expect(controlerDesignationPosteSecours(role: 'comptable')?.code, 'REGLAGE_RESERVE');
    expect(shPeutRegler('admin'), isTrue);
    expect(shPeutRegler('direction'), isFalse);
    expect(shPeutRegler('direction', gestes: DroitsGestes(fiches: [fiche('direction', {gesteReglageHorsSite: true})])), isTrue);
    expect(accRefusReinitialisation(acteurRole: 'admin', acteurId: 'A', cibleId: 'B'), isNull);
    expect(accRefusReinitialisation(acteurRole: 'da', acteurId: 'A', cibleId: 'B')?.code, 'reinit_non_admin');
    // RH.
    expect(controlerReglageRh(role: 'da', genre: 'direct', valeur: true), isNull);
    expect(controlerReglageRh(role: 'surveillant', genre: 'direct', valeur: true)?.code, 'REGLAGE_RESERVE');
    expect(peutPoserPlanningRh('surveillant'), isNull);
    expect(peutPoserPlanningRh('medecin'), isNotNull);
    expect(peutPoserPlanningRh('medecin', gestes: DroitsGestes(fiches: [fiche('medecin', {gesteRhEncadrer: true})])), isNull);
    expect(rolesEtapeRh, {'surveillant': ['surveillant', 'admin'], 'daf': ['da', 'admin']});
    expect(controlerReglageCopiePaie('admin'), isNull);
    expect(controlerReglageCopiePaie('rh'), isNotNull);
    // Imagerie, achats, validations.
    expect(imgExecutantImagerie('echographiste'), isTrue);
    expect(imgExecutantImagerie('medecin'), isFalse);
    expect(estAchat('stock'), isTrue);
    expect(estAchat('caissier'), isFalse);
    expect(valPeutValider('pathologies', 'dm'), isTrue);
    expect(valPeutValider('pathologies', 'chirurgien'), isFalse);
    expect(valPeutValider('pathologies', 'chirurgien', gestes: DroitsGestes(fiches: [fiche('chirurgien', {gesteValiderRefPathologies: true})])), isTrue);
    expect(valFamille('bareme_aib')!.roles, ['direction', 'da', 'admin', 'comptable'], reason: 'l’ordre d’affichage des profils est conservé');
  });

  test('l’échange entre pairs : trancher et valider passent par les gestes ; l’appareil de la mère tranche toujours', () {
    final d = droitsDepuisMatrice(peutEditer: (_, __) => false, peutAnnuler: (_, __) => false);
    OperationPair op(String type, String role) =>
        OperationPair(id: 'o', hlc: 1, appareil: 'A', collection: 'patients', fiche: 'P1', type: type, role: role);
    expect(d(op('trancher', 'direction')), isTrue);
    expect(d(op('trancher', 'mere')), isTrue);
    expect(d(op('trancher', 'comptable')), isFalse);
    expect(d(op('valider', 'da')), isTrue);
    expect(d(op('valider', 'direction')), isFalse);
    final g = DroitsGestes(fiches: [fiche('comptable', {gesteConflitsTrancher: true}), fiche('direction', {gesteConflitsTrancher: false})]);
    final d2 = droitsDepuisMatrice(peutEditer: (_, __) => false, peutAnnuler: (_, __) => false, peutGeste: g.peut);
    expect(d2(op('trancher', 'comptable')), isTrue);
    expect(d2(op('trancher', 'direction')), isFalse);
    expect(d2(op('trancher', 'mere')), isTrue, reason: 'la mère n’est pas un rôle : aucune fiche ne la retire');
  });
}
