import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sigh_domaine/sigh_domaine.dart';

import '../../kit/kit.dart';
import '../../shell/contexte_ecran.dart';
import '../m9/commun.dart' show carteValideLe;
import 'tbb_commun.dart';

/// Tableaux de bord de poste des trois rôles créés le 10/11/2026 (décision de la Direction de Baguidi) : Responsable Radiologie, Responsable Maternité
/// (sage-femme) et Responsable Assurance. Lecture seule ; chacun annonce, comme celui de l'aide-soignante, ce que son profil ne voit pas.
/// Les règles de lecture sont au domaine (`tbb_regles.dart`).

// ---------------------------------------------------------------------------------------------------------------------------------------------
// dash-responsable-radiologie — il EXÉCUTE, il ne prescrit pas ; aucun montant.
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDashResponsableRadiologie extends StatelessWidget with EcranMaquette {
  const EcranDashResponsableRadiologie({super.key});

  @override
  String get titre => 'Tableau de bord — Responsable Radiologie';

  @override
  String get description =>
      'Demandes d’imagerie à exécuter, comptes rendus à rendre et activité par modalité — sans prescription ni accès financier.';

  @override
  Widget build(BuildContext context) => TableauTbb(
        collections: const ['demandesImagerie', 'resultatsImagerie'],
        construire: (c) => TbbDisposition(
          releve: tbbResponsableRadiologie(
              demandes: lire(c, 'demandesImagerie'), comptesRendus: lire(c, 'resultatsImagerie'), auj: c.aujourdhui),
          raccourcis: [
            raccourci('m2-dashboard-imagerie', 'scan-line', 'Poste d’imagerie médicale', 'Payés à exécuter, file d’attente'),
            raccourci('m2-imagerie-demandes', 'clipboard-list', 'Demandes d’imagerie', 'Registre des demandes'),
            raccourci('m2-echographie-galerie', 'images', 'Galerie des clichés', 'Rattachés au patient et au compte rendu'),
            raccourci('m2-stats-echographie', 'chart-column', 'Statistiques de l’imagerie', 'Activité par modalité'),
          ],
          parcours: const [
            ParcoursDef('Exécuter un examen d’imagerie', 'scan-line', action: 'Poste d’imagerie', detail: 'Une demande est payée.', [
              EtapeDef('Prendre la demande payée', ecran: 'm2-dashboard-imagerie', detail: 'Une demande encore à la caisse reste verrouillée.'),
              EtapeDef('Réaliser l’examen et saisir le compte rendu', ecran: 'm2-imagerie-demandes'),
              EtapeDef('Rédiger la conclusion', ecran: 'm2-imagerie-demandes', detail: 'Obligatoire avant de rendre : le prescripteur lit celle-là.'),
              EtapeDef('Rendre au prescripteur', ecran: 'm2-imagerie-demandes'),
              EtapeDef('Le clinicien décide', poste: 'Consultation'),
            ]),
          ],
          sections: const [
            CarteSigh(
                titre: 'Ce que votre profil ne voit pas',
                child: NoteSigh(
                    'Vous exécutez l’imagerie, vous ne prescrivez pas : ni ordonnance ni fiche de consultation ne vous sont ouvertes, et le dossier du patient se '
                    'lit sans se modifier. Aucun accès financier — ni caisse, ni assurances, ni comptabilité : un examen ne dépend pas du paiement à votre poste. '
                    'Le catalogue de l’imagerie se lit ; sa modification appartient à la Direction.',
                    icone: LucideIcons.shield)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// dash-sage-femme — le poste de la maternité : la même lecture que `dash-maternite`, avec ce que le profil ne voit pas.
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDashSageFemme extends StatelessWidget with EcranMaquette {
  const EcranDashSageFemme({super.key});

  @override
  String get titre => 'Tableau de bord — Responsable Maternité';

  @override
  String get description => 'Travail en cours, termes proches, grossesses à risque et activité de la maternité — sans finance.';

  @override
  Widget build(BuildContext context) => TableauTbb(
        collections: const ['dossiersObstetricaux', 'partogrammes', 'accouchements', 'naissances'],
        construire: (c) => TbbDisposition(
          releve: tbbMaternite(
              dossiers: lire(c, 'dossiersObstetricaux'),
              partogrammes: lire(c, 'partogrammes'),
              accouchements: lire(c, 'accouchements'),
              naissances: lire(c, 'naissances'),
              auj: c.aujourdhui),
          raccourcis: [
            raccourci('m4-partogramme', 'activity', 'Partogrammes', 'Travail en cours'),
            raccourci('m4-dossier-obstetrical', 'folder-open', 'Dossiers obstétricaux', 'Le cahier de la parturiente'),
            raccourci('m4-cpn', 'stethoscope', 'Consultations prénatales', 'Grille CPN'),
            raccourci('m4-accouchements', 'baby', 'Accouchements', 'Registre et délivrance'),
          ],
          parcours: const [
            ParcoursDef('Suivre une grossesse jusqu’à l’accouchement', 'baby', action: 'Dossiers obstétricaux', detail: 'Le cahier est ouvert à la première CPN.', [
              EtapeDef('Ouvrir le dossier obstétrical', ecran: 'm4-dossier-obstetrical'),
              EtapeDef('Tenir les consultations prénatales', ecran: 'm4-cpn'),
              EtapeDef('Suivre le travail au partogramme', ecran: 'm4-partogramme'),
              EtapeDef('Enregistrer l’accouchement et le nouveau-né', ecran: 'm4-accouchements'),
              EtapeDef('Surveiller les suites de couches', ecran: 'm4-cpon'),
            ]),
          ],
          sections: const [
            CarteSigh(
                titre: 'Ce que votre profil ne voit pas',
                child: NoteSigh(
                    'La maternité (M4) est votre module : vous y écrivez. Les dossiers patients et les consultations se lisent sans se modifier, et vous ne lisez '
                    'que les résultats d’analyses de votre secteur — pas ceux demandés par la chirurgie. Aucun accès financier : ni caisse, ni assurances, ni '
                    'comptabilité (RG-13).',
                    icone: LucideIcons.shield)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// dash-responsable-assurance — assurances et créances ; ni comptabilité ni dossier médical.
// ---------------------------------------------------------------------------------------------------------------------------------------------

class EcranDashResponsableAssurance extends StatelessWidget with EcranMaquette {
  const EcranDashResponsableAssurance({super.key});

  @override
  String get titre => 'Tableau de bord — Responsable Assurance';

  @override
  String get description =>
      'Créances des assureurs, cartes à renouveler, factures assureur et relances à faire — sans comptabilité ni dossier médical.';

  @override
  Widget build(BuildContext context) => TableauTbb(
        collections: const ['assureurs', 'patients', 'factures', 'relances', 'couverturesAssurance'],
        construire: (c) => TbbDisposition(
          releve: tbbResponsableAssurance(
              assureurs: lire(c, 'assureurs'),
              patients: lire(c, 'patients'),
              factures: lire(c, 'factures'),
              relances: lire(c, 'relances'),
              carteValide: (p) => carteValideLe(c, p),
              auj: c.aujourdhui),
          raccourcis: [
            raccourci('m9-assures', 'id-card', 'Assurés & cartes', 'Vérification de validité'),
            raccourci('m9-factures-assureur', 'file-text', 'Factures assureur', 'Relevé et facture mensuelle'),
            raccourci('m9-creances', 'hand-coins', 'Créances', 'Balance âgée par compagnie'),
            raccourci('m9-relances', 'bell-ring', 'Relances', 'À envoyer aux assureurs'),
          ],
          parcours: const [
            ParcoursDef('Recouvrer la part d’un assureur', 'hand-coins', action: 'Créances', detail: 'Une facture assurée est émise.', [
              EtapeDef('Contrôler la carte de l’assuré', ecran: 'm9-assures', detail: 'Carte non valide à la date : facturation intégrale au patient (RG-09).'),
              EtapeDef('Émettre la facture assureur', ecran: 'm9-factures-assureur'),
              EtapeDef('Suivre la créance par ancienneté', ecran: 'm9-creances'),
              EtapeDef('Relancer la compagnie', ecran: 'm9-relances'),
              EtapeDef('L’encaissement est passé en comptabilité', poste: 'Comptable'),
            ]),
          ],
          sections: const [
            CarteSigh(
                titre: 'Ce que votre profil ne voit pas',
                child: NoteSigh(
                    'Les assurances et les créances (M9) sont votre module : vous y écrivez. La facturation se lit sans se modifier ; la caisse et la comptabilité '
                    'ne vous sont pas ouvertes — l’écriture d’un règlement appartient au comptable. Le répertoire des patients se lit sans le dossier médical '
                    '(RG-13).',
                    icone: LucideIcons.shield)),
          ],
        ),
      );
}
