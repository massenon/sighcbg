/// LES GESTES RÉSERVÉS : un droit PAR GESTE, porté par la fiche de rôle (lot B, Direction du 13/11/2026).
///
/// Un geste qui engage un professionnel nommé n'est pas une liste de rôles écrite dans un écran : c'est un droit de la fiche `rbac` du rôle
/// (`droitsGestes.<geste>`, vrai ou faux), accordé PAR RÔLE (jamais par agent), que le référentiel ci-dessous ne donne d'origine qu'à la liste `rolesDefaut`.
/// Même mécanisme que les catégories de données sensibles ([DroitsSensibles]) : évalué À CHAQUE appel depuis les fiches, rien n'est mis en cache, une décision
/// prise à l'instant vaut à la lecture suivante, sans redémarrage.
///
///  * UNE SURCHARGE ACCORDE AUTANT QU'ELLE RETIRE : `true` accorde (même à un rôle absent de `rolesDefaut`, l'administrateur système compris), `false` retire
///    (même au rôle d'origine), absent suit l'origine ;
///  * « un rôle sans fiche a tous les droits » vaut pour les ÉCRANS, jamais pour un geste réservé : l'administrateur système, qui n'a pas de fiche, n'a donc PAS
///    ce droit d'origine, et aucune exception de nom de rôle n'est écrite nulle part ;
///  * un rôle archivé n'a aucun geste, un écran ou un module fermé retire le geste à TOUS les rôles ;
///  * le droit n'ouvre PAS l'écran du geste : l'écran se règle à part (« Régler écran par écran »).
library;

import 'a_chaud.dart' show surchargesParRole;

/// Un geste réservé : son identifiant (clé du droit), ce qu'il autorise, l'écran qui le porte et les rôles qui le détiennent d'origine.
class GesteReserve {
  const GesteReserve(
      {required this.id, required this.libelle, required this.module, required this.ecran, required this.rolesDefaut, this.aide = '', this.suitEcran = false});
  final String id;
  final String libelle;
  final String module;

  /// L'écran qui porte le geste ; vide quand il s'exerce sur plusieurs écrans du module (le geste suit alors l'activité du MODULE) ou sur tous ([suitEcran]).
  final String ecran;

  /// Les rôles qui détiennent le geste sans aucune décision. Un rôle créé en exploitation n'y figure pas : il part de zéro.
  final List<String> rolesDefaut;
  final String aide;

  /// Un geste TRANSVERSE, sans écran propre (`ecran` vide) : sans décision, il suit la LECTURE de l'écran où il s'exerce (`DroitsGestes.peutSurEcran`). Une décision de la
  /// clinique l'accorde ou le retire au rôle pour TOUS les écrans.
  final bool suitEcran;
}

/// Valider un seuil de variation brutale du laboratoire : au Biologiste médical d'origine (réponse de la Direction du 13/11/2026).
const String gesteValiderSeuil = 'valider_seuil_labo';

/// Valider un seuil de variation PAR INTÉRIM, avec la fonction de technicien de laboratoire : la fonction est portée par le rôle du Biologiste médical, et non
/// par un rôle propre. Personne ne le détient d'origine (le technicien est exclu par défaut) ; l'accorder au rôle sous lequel le technicien se connecte l'ouvre
/// à ses techniciens. Il s'ajoute à [gesteValiderSeuil] : il ne le remplace pas.
const String gesteValiderSeuilInterim = 'valider_seuil_labo_interim';

/// Décider un changement de prix (Oui ou Non) à « Tarifs et prix » : un geste de la matrice (lot TAR, PRD-TARIFS). Origine : l'administrateur, la DAF et la Direction ;
/// une fiche de rôle accorde ou retire. Proposer reste le droit d'ÉDITER l'écran.
const String gesteDeciderPrix = 'tarif_decider';

/// Dater un prix dans le PASSÉ (T6, Direction) : la DAF et la Direction seulement d'origine, avec motif ; refusé dès qu'une pièce a utilisé la prestation depuis la date.
const String gesteDaterPrixPasse = 'tarif_dater_passe';

/// Proposer un changement de PRIX D'ACHAT d'un produit à « Référentiel produits » (bouton « Changer le prix d'achat », Direction du 16/11/2026) : ce n'est plus le simple droit
/// d'éditer l'écran. Le caissier modifie la fiche d'un produit (stock détail) mais n'a aucune raison métier de proposer un prix d'achat. Origine : le gestionnaire de stock, la DAF et
/// l'administrateur. S'ajoute au droit d'éditer l'écran (il ne l'ouvre pas) ; ne touche ni la réception d'achat ni l'importation des prix d'achat, qui ont leur propre droit.
const String gesteProposerPrixAchat = 'tarif_proposer_achat';

/// EXPORTER les lignes d'un tableau en fichier (.xlsx, CSV) (Q39, Direction du 15/11/2026 ; séparé de l'impression le 16/11/2026, section 7) : un droit réglable PAR RÔLE.
/// Sans décision, il suit la lecture de l'écran (les rôles qui LISENT l'écran exportent) ; une décision l'accorde ou le retire au rôle pour tous les écrans. Il s'applique à
/// la SORTIE : le fichier ne porte que ce que l'écran montre.
const String gesteExporter = 'export_tableau';

/// IMPRIMER depuis un tableau (la sélection cochée ou tout le filtre, en un tableau unique ou en pièces complètes, une par page) : un droit DISTINCT de l'export (Direction,
/// 16/11/2026, section 7 : « deux droits séparés »). Même mécanique que [gesteExporter] : sans décision, il suit la lecture de l'écran ; une décision de fiche l'accorde ou le
/// retire au rôle pour tous les écrans. Retirer l'un ne retire pas l'autre.
const String gesteImprimerTableau = 'imprimer_tableau';

/// RÉGLER LA LIMITE de lignes par export (`export.limiteLignes`, Direction, 16/11/2026, section 7) : un geste réservé réglable, et non le seul droit d'éditer l'écran des
/// paramètres. Origine PROPOSÉE (à valider par la Direction) : l'administrateur et la Directrice Administrative ; une fiche de rôle l'accorde ou le retire.
const String gesteReglerLimiteExport = 'export_regler_limite';
/// LE CIRCUIT DE CLÔTURE (Q1 et Q2 de la Direction de Baguidi, 17/11/2026) : démarrer la clôture, clôturer définitivement, reprendre la saisie et rouvrir un exercice sont UN geste réservé de
/// la fiche de rôle, accordé par rôle et réglable. Origine : l'administrateur et la Directrice Administrative. Le droit ne dispense JAMAIS de la séparation des personnes : celui qui a démarré la
/// clôture ne la clôture pas (le moteur compare l'identifiant de l'agent), et un comptable seul, sans ce droit, ne démarre ni ne clôture.
const String gesteCircuitCloture = 'cloture_circuit';

/// Régler la gestion des FICHIERS NUMÉRISÉS (taille maximale d'un scan, contrôle d'intégrité, sauvegarde du dossier des scans) : un droit PAR RÉGLAGE (Q5), réservé d'origine à l'administrateur
/// et à la Directrice Administrative. Se règle sur la poste mère.
const String gesteReglageFichiers = 'reglage_fichiers';

/// Régler la LECTURE DES SCANS (OCR : activation, moteur, langue, délai) : un droit par réglage (Q5), administrateur et Directrice Administrative d'origine. Se règle sur la poste mère.
const String gesteReglageOcr = 'reglage_ocr';

/// Régler la CONFIGURATION MECeF (mode de certification, boîtier ou e-MECeF) : un droit par réglage (Q5), administrateur et Directrice Administrative d'origine. Se règle sur la poste mère.
const String gesteReglageMecef = 'reglage_mecef';

/// VALIDER LES ACHATS (RG-04, Direction de Baguidi du 16/11/2026, qui remplace le réglage de clinique `achats.rolesValidateurs` de la v20) : arbitrer un bon d'expression de besoins (accorder,
/// rejeter, demander un complément) et valider une commande de stock avant sa transmission au fournisseur. Origine : la Directrice Administrative SEULE (RG-04) ; la Direction l'étend à un autre
/// rôle dans « Rôles et permissions › Gestes réservés », décision tracée. L'administrateur système ne l'a PAS d'origine. Depuis un poste rattaché, le geste se DÉPOSE et la mère le rejoue sous
/// le rôle de son auteur, avec SA matrice. Le POSTE écrit sur la pièce reste le réglage `achats.libelleValidateur` (un libellé, pas un droit).
const String gesteValiderAchats = 'achats_valider';

/// RÉGLER L'ENCAISSEMENT D'UNE FACTURE QUI A UNE LIGNE SANS PRIX (Direction de Baguidi, 16/11/2026, complément §7) : par défaut RIEN d'une facture ne s'encaisse tant qu'une de ses
/// lignes attend son prix ; le réglage de clinique `caisse.encaisserResteLigneSansPrix` rouvre l'encaissement ligne par ligne. Il se pose sous ce geste, depuis N'IMPORTE QUEL poste : sur un
/// poste rattaché, le geste se DÉPOSE et la mère l'applique sous le rôle de son auteur, avec SA matrice (le réglage revient par la synchronisation, famille R). Origine : l'administrateur et la
/// Directrice Administrative (à confirmer par la Direction) ; une fiche de rôle accorde ou retire.
const String gesteReglageEncaissementSansPrix = 'reglage_encaissement_sans_prix';

/// LA PHARMACIE ET LA CAISSE NE SONT PAS UN RÔLE (Direction de Baguidi, 16/11/2026) : aujourd'hui la Caissière-Dispensatrice tient les deux et le rôle pharmacien reste ouvert, mais une
/// clinique peut séparer un pharmacien de la caisse. Aucune décision de droit n'y suppose donc « pharmacie = caissier » : encaisser et délivrer sont des droits d'ÉCRAN de la matrice
/// (`m8-caisse`, `m6-dispensation`), et ce qui n'était pas un droit d'écran (le routage des alertes, la retransmission MECeF) est un geste réservé ci-dessous, dont l'origine
/// reprend À L'IDENTIQUE les listes qui vivaient en dur (aucun changement de comportement le jour de la conversion). Séparer, c'est cocher des cases, jamais toucher au code.

/// Recevoir les notifications du POSTE de caisse (tâche ou notification adressée à la « caisse »). Origine : le Caissier (liste reprise de `_postesNotif['caisse']`).
const String gesteAlertesCaisse = 'alertes_caisse';

/// Recevoir les notifications du POSTE stock (besoins accordés, réapprovisionnement, notifications adressées au « stock »). Origine : le gestionnaire de stock, le pharmacien et la DAF.
const String gesteAlertesStock = 'alertes_stock';

/// Recevoir l'alerte « article sous son seuil d'alerte ». Origine : le gestionnaire de stock, le pharmacien, le Caissier-Dispensateur et la DAF.
const String gesteAlertesSeuilStock = 'alertes_seuil_stock';

/// Recevoir l'alerte « lot périmé ou proche de la péremption ». Origine : le gestionnaire de stock, le pharmacien, le Caissier-Dispensateur et le Biologiste médical.
const String gesteAlertesPeremption = 'alertes_peremption';

/// Recevoir l'alerte « facture rejetée par la MECeF ». Origine : le Caissier, le Comptable, la DAF et l'Assistant de Direction.
const String gesteAlertesMecefRejet = 'alertes_mecef_rejet';

/// Retransmettre une pièce à la MECeF UNE fois (PRD section 7, Q7). Origine : le Caissier, la DAF et l'administrateur.
const String gesteMecefRetransmettre = 'mecef_retransmettre';

/// Retransmettre une pièce à la MECeF SANS limite de nombre (après la première retransmission). Origine : la DAF et l'administrateur.
const String gesteMecefRetransmettreSansLimite = 'mecef_retransmettre_sans_limite';

// ---------------------------------------------------------------------------------------------------------------------------------------------
// AUCUNE LISTE DE RÔLES EN DUR (Direction de Baguidi, compléments du 16/11/2026, section 7) : chaque décision de droit qui vivait en dur dans un écran ou un moteur devient
// un geste réservé ci-dessous, UN par décision métier, dont l'origine reprend À L'IDENTIQUE la liste d'avant (aucun changement de comportement le jour de la conversion). Ces
// gestes sont TRANSVERSES de module (`module: '*'`, `ecran: ''`) : ils ne tombent pas avec une activité fermée (les écrans qui les portent tombent, eux) — comme les listes
// qu'ils remplacent. Le cliquet global `roles_en_dur_global_test.dart` garde qu'aucune liste ne revienne.
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Recevoir les notifications du POSTE comptable. Origine : le Comptable, l'Assistant de Direction, l'Assistant Comptable et la DAF (liste reprise de `_postesNotif['comptable']`).
const String gesteAlertesComptable = 'alertes_comptable';

/// Recevoir les notifications du POSTE de la Direction. Origine : la Direction, la DAF et le Directeur Médical.
const String gesteAlertesDirection = 'alertes_direction';

/// Recevoir les notifications du POSTE d'imagerie (demandes d'imagerie). Origine : le technicien d'échographie et le Responsable Radiologie.
const String gesteAlertesImagerie = 'alertes_imagerie';

/// Recevoir les notifications du POSTE de laboratoire et ses alertes (prélèvement à faire, résultat à saisir). Origine : le Biologiste médical.
const String gesteAlertesLaboratoire = 'alertes_laboratoire';

/// Recevoir les notifications du POSTE prescripteur (résultat disponible, rectifié). Origine : le médecin, le chirurgien, l'anesthésiste et le Directeur Médical.
const String gesteAlertesPrescripteur = 'alertes_prescripteur';

/// Recevoir les notifications de la SALLE DE SOINS (prescriptions de soins). Origine : l'infirmier, l'aide-soignante et le surveillant.
const String gesteAlertesSalleSoins = 'alertes_salle_soins';

/// Recevoir les notifications de l'HOSPITALISATION. Origine : l'infirmier, l'aide-soignante, le surveillant et le médecin.
const String gesteAlertesHospitalisation = 'alertes_hospitalisation';

/// Recevoir l'alerte « échéance fiscale dépassée ». Origine : le Comptable, la DAF, l'Assistant de Direction et la Direction.
const String gesteAlertesEcheancesFiscales = 'alertes_echeances_fiscales';

/// Recevoir l'alerte « créance assureur en souffrance ». Origine : la DAF, le Comptable, la Direction, l'Assistant de Direction, l'Assistant Comptable et le Responsable Assurance.
const String gesteAlertesCreances = 'alertes_creances';

/// Recevoir l'alerte « bon de besoins à valider ». Origine : la DAF et la Direction.
const String gesteAlertesBesoinsAValider = 'alertes_besoins_a_valider';

/// Recevoir l'alerte « pièce comptable en brouillon ». Origine : le Comptable, la DAF et l'Assistant Comptable.
const String gesteAlertesEcrituresBrouillon = 'alertes_ecritures_brouillon';

/// Recevoir l'alerte « doublon détecté par la synchronisation » (dossier, facture, encaissement, délivrance, avoir, écriture, lit, stock). Origine : la Direction, la DAF, le
/// Comptable et l'administrateur.
const String gesteAlertesDoublonsSync = 'alertes_doublons_sync';

/// TRANCHER un conflit (champ écrit sur deux postes, couverture en double) et en recevoir l'alerte. Origine : la DAF, la Direction et l'administrateur (`rolesQuiTranchentPair`).
/// L'appareil de la mère (`mere`, qui n'est pas un rôle) tranche toujours à son retour.
const String gesteConflitsTrancher = 'conflits_trancher';

/// VALIDER ou REJETER un flux échangé entre postes (règle de fusion pair). Origine : la DAF et l'administrateur (`rolesQuiValidentPair`).
const String gesteSyncValiderFlux = 'sync_valider_flux';

/// ADMINISTRER LE SYSTÈME : les écrans du groupe « Poste mère » (exploitation, cycle, plateforme) et l'onglet « Système » du ruban. Origine : l'administrateur et la DAF
/// (`mrcRolesAdmin`, `rolesAdminMere`, `rolesRubanSysteme`).
const String gesteSystemeAdministrer = 'systeme_administrer';

/// Conduire l'ASSISTANT D'INSTALLATION tant qu'il est en cours sur le poste. Origine : l'administrateur.
const String gesteInstallationConduire = 'installation_conduire';

/// Le DOUBLE FACTEUR est IMPOSÉ au rôle (case cochée d'office et non décochable). Origine : le Directeur Médical, la DAF, la Direction et l'administrateur.
const String gesteDoubleFacteurImpose = 'securite_double_facteur';

/// Réinitialiser le mot de passe d'un autre compte. Origine : l'administrateur.
const String gesteComptesReinitialiser = 'comptes_reinitialiser';

/// Régler le VERROU DE SECOURS (délai, poste de secours). Origine : l'administrateur et la DAF.
const String gesteReglageVerrouSecours = 'reglage_verrou_secours';

/// Régler la COPIE HORS SITE des sauvegardes. Origine : l'administrateur et la DAF.
const String gesteReglageHorsSite = 'reglage_horssite';

/// RÉGLER LA PASSERELLE SMS et TESTER L'ENVOI (ADR-0009, Direction de Baguidi, 16/11/2026) : ouvrir ou fermer la passerelle, envoyer un SMS d'essai, composer et
/// déposer un SMS au relais. Origine PROPOSÉE, à valider par la Direction : l'administrateur et la DAF. Se règle sur la poste mère.
const String gesteReglageSms = 'reglage_sms';

/// VALIDER LA CONFIGURATION FISCALE (identité légale, obligations, paramètres ORTB datés). Origine : la Direction, la DAF et l'administrateur (`cfbRolesValidation`).
const String gesteFiscalValiderConfiguration = 'fiscal_valider_configuration';

/// TENIR LE BARÈME DE L'AIB et ses réglages (écrire une version, un réglage). Origine : le Comptable, l'administrateur et la DAF (`aibRolesEcriture`) ; la Direction lit.
const String gesteAibTenir = 'aib_tenir';

/// CONFIRMER un taux fiscal (taux de la CNSS, version du barème de l'AIB) : motif obligatoire, auteur et date tracés, la valeur reste versionnée par date (compléments du
/// 16/11/2026). Origine PROPOSÉE (à valider par la Direction) : le Comptable et la DAF.
const String gesteFiscalConfirmer = 'fiscal_confirmer';

/// Voir TOUTES les familles au centre des validations (les autres profils voient leur ressort). Origine : la Direction, la DAF et l'administrateur (`valVueComplete`).
const String gesteValidationsVueComplete = 'validations_vue_complete';

/// Le centre des validations ÉLARGI (les profils qui l'ouvraient avant voient tout ce qu'ils y voyaient). Origine : la DAF, l'administrateur, la Direction, le Directeur Médical,
/// le Comptable, le surveillant et l'agent administratif.
const String gesteValidationsCentreElargi = 'validations_centre_elargi';

/// Valider les référentiels du ressort de la DIRECTION (enquêtes, tarifs des actes et des analyses, valorisation SAGE, objectifs, badges, jeux d'import, modèles de messages,
/// barème de l'ITS). Origine : la Direction, la DAF et l'administrateur.
const String gesteValiderRefDirection = 'valider_ref_direction';

/// Valider les variables et unités du laboratoire (bornes suppléées). Origine : le Biologiste médical.
const String gesteValiderRefLabo = 'valider_ref_labo';

/// Valider les pathologies (tableau de morbidité). Origine : le Directeur Médical et le médecin.
const String gesteValiderRefPathologies = 'valider_ref_pathologies';

/// Valider le catalogue de l'imagerie (examens et variables). Origine : le technicien d'échographie, le Responsable Radiologie et le Directeur Médical.
const String gesteValiderRefImagerie = 'valider_ref_imagerie';

/// Valider les check-listes du bloc et les échelles ASA et Mallampati. Origine : le chirurgien et l'anesthésiste.
const String gesteValiderRefBloc = 'valider_ref_bloc';

/// Valider la répartition fixe et variable des charges. Origine : le Comptable, la Direction, la DAF et l'administrateur.
const String gesteValiderRefRepartition = 'valider_ref_repartition';

/// Valider le barème de l'AIB (marquage « à valider » d'une version). Origine : la Direction, la DAF, l'administrateur et le Comptable.
const String gesteValiderRefBaremeAib = 'valider_ref_bareme_aib';

/// RÉGLER LE PERSONNEL : circuit de validation des présences et « l'agent modifie directement », dérogation de régime individuel, délai du pointage par badge, copie de la
/// fiche de paie sur le téléphone. Origine : l'administrateur et la DAF.
const String gesteRhRegler = 'rh_regler';

/// ENCADRER LE PLANNING DU PERSONNEL : poser et retirer le planning, voir et valider les propositions, régulariser un pointage, consigner l'avis du chef de service sur un
/// ordre de mission. Origine : le surveillant, la DAF et l'administrateur.
const String gesteRhEncadrer = 'rh_encadrer';

/// Valider l'étape « surveillant » du circuit RH (présences, absences, missions). Origine : le surveillant et l'administrateur.
const String gesteRhEtapeSurveillant = 'rh_etape_surveillant';

/// Valider l'étape « directrice administrative » du circuit RH. Origine : la DAF et l'administrateur.
const String gesteRhEtapeDaf = 'rh_etape_daf';

/// POINTER UN BADGE à l'écran de vérification. Origine : le surveillant, la DAF, l'administrateur, la Direction et le compte RH.
const String gesteRhPointerBadge = 'rh_pointer_badge';

/// EXÉCUTER L'IMAGERIE sans la prescrire : lire tous les comptes rendus, ouvrir celui d'un examen payé, ne jamais créer de demande. Origine : le technicien d'échographie et le
/// Responsable Radiologie (`rolesExecutantsImagerie`).
const String gesteImagerieExecuter = 'imagerie_executer';

/// ÉCRIRE LES RUBRIQUES CHIRURGICALES du dossier de consultation (elles se lisent par tous). Origine : le chirurgien. La fonction de chirurgien portée par l'agent ouvre aussi
/// ces rubriques (axe Fonction, `csPeutEcrireRubrique`).
const String gesteRubriquesChirurgicales = 'rubriques_chirurgicales';

/// Voir les besoins validés et le registre complet des achats (achat et logistique). Origine : le Comptable, le gestionnaire de stock, la DAF, la Direction, l'administrateur et
/// l'Assistant Comptable (`rolesAchat`).
const String gesteAchatsRegistre = 'achats_registre';

/// LE PLAN DE TRAVAIL ANNUEL (lot PTA, Direction de Baguidi, 17/11/2026 : « RIEN NE DOIT ÊTRE EN DUR ») : ADOPTER le plan (et le renvoyer en brouillon, et le CLÔTURER
/// avec son bilan) est un geste de la fiche de rôle, pas le droit d'écrire l'écran. Origine PROPOSÉE (à valider par la Direction) : la Direction et la DAF. Depuis un poste
/// rattaché, le geste se DÉPOSE et la mère l'applique sous le rôle de son auteur, avec SA matrice. Celui qui a soumis le plan ne l'adopte pas.
const String gestePtaAdopter = 'pta_adopter';

/// Régler les RÉFÉRENTIELS du plan de travail annuel : axes, états d'avancement (collections), découpage en périodes et seuil d'alerte de retard (paramètres de clinique
/// versionnés par date). Origine PROPOSÉE (à valider par la Direction) : l'administrateur et la DAF.
const String gestePtaRegler = 'pta_regler';

/// Recevoir l'alerte « action du plan de travail annuel en retard » (une ligne par action, routée vers les responsables du suivi). Origine PROPOSÉE (à valider par la
/// Direction) : la Direction et la DAF.
const String gesteAlertesPtaRetard = 'alertes_pta_retard';

/// Le référentiel des gestes réservés. Une donnée du domaine : le code l'interroge, il ne recopie jamais ses identifiants ni ses rôles d'origine.
const List<GesteReserve> gestesReserves = [
  GesteReserve(
      id: gesteValiderSeuil,
      libelle: 'Valider un seuil de variation brutale du laboratoire',
      module: 'M5',
      ecran: 'm5-valeurs-reference',
      rolesDefaut: ['laborantin'],
      aide: 'Rend un seuil opposable : sans lui, un seuil enregistré reste sans effet. Origine : le Biologiste médical.'),
  GesteReserve(
      id: gesteValiderSeuilInterim,
      libelle: 'Valider un seuil de variation brutale avec la fonction de technicien de laboratoire',
      module: 'M5',
      ecran: 'm5-valeurs-reference',
      rolesDefaut: [],
      aide: 'Le technicien de laboratoire est exclu par défaut. Accordé à un rôle, ses agents de fonction technicien peuvent valider un seuil (en plus du droit précédent).'),
  GesteReserve(
      id: gesteDeciderPrix,
      libelle: 'Décider un changement de prix (Oui ou Non)',
      module: 'CFG',
      ecran: 'cfg-tarifs',
      rolesDefaut: ['admin', 'da', 'direction'],
      aide: 'Une proposition de prix ne change rien avant le Oui. Proposer est le droit d’éditer l’écran « Tarifs et prix » ; décider est celui-ci. Origine : l’administrateur, la DAF, la Direction.'),
  GesteReserve(
      id: gesteDaterPrixPasse,
      libelle: 'Dater un prix dans le passé',
      module: 'CFG',
      ecran: 'cfg-tarifs',
      rolesDefaut: ['da', 'direction'],
      aide: 'Une date d’effet antérieure à aujourd’hui, avec motif, tant qu’aucune pièce n’a utilisé la prestation depuis cette date. Origine : la DAF et la Direction.'),
  GesteReserve(
      id: gesteProposerPrixAchat,
      libelle: 'Proposer un changement de prix d’achat d’un produit',
      module: 'M6',
      ecran: 'm6-produits',
      rolesDefaut: ['admin', 'da', 'stock'],
      aide: 'La commande « Changer le prix d’achat » du Référentiel produits. Modifier la fiche d’un produit ne suffit plus. Origine : le gestionnaire de stock, la DAF, l’administrateur.'),
  GesteReserve(
      id: gesteExporter,
      libelle: 'Exporter les lignes d’un tableau (Excel, CSV)',
      module: '*',
      ecran: '',
      rolesDefaut: [],
      suitEcran: true,
      aide: 'Excel (.xlsx) et CSV. Sans décision, le droit suit la lecture de l’écran : qui lit le tableau peut l’exporter. Accordé ou retiré à un rôle, il vaut pour tous les écrans. Le fichier ne porte que les colonnes et les lignes que l’écran montre, champs sensibles masqués comme à l’écran. L’impression depuis un tableau est un droit distinct.'),
  GesteReserve(
      id: gesteImprimerTableau,
      libelle: 'Imprimer depuis un tableau',
      module: '*',
      ecran: '',
      rolesDefaut: [],
      suitEcran: true,
      aide: 'La sélection cochée ou tout le filtre, en un tableau unique ou en pièces complètes (une par page). Sans décision, le droit suit la lecture de l’écran. Accordé ou retiré à un rôle, il vaut pour tous les écrans ; il est distinct du droit d’exporter.'),
  GesteReserve(
      id: gesteReglerLimiteExport,
      libelle: 'Régler la limite de lignes par export',
      module: 'CFG',
      ecran: 'cfg-systeme',
      rolesDefaut: ['admin', 'da'],
      aide: 'Le réglage « Nombre maximal de lignes par export » (Paramètres système › Paramètres). Le droit d’éditer l’écran ne suffit pas. Origine proposée, à valider : l’administrateur et la Directrice Administrative.'),
  GesteReserve(
      id: gesteCircuitCloture,
      libelle: 'Circuit de clôture : démarrer, clôturer, rouvrir un exercice',
      module: 'M12',
      ecran: 'm12-cloture',
      rolesDefaut: ['admin', 'da'],
      aide: 'Démarrer la clôture, la prononcer, reprendre la saisie et rouvrir un exercice clos. Ne dispense pas de la séparation des personnes : celui qui a démarré ne clôture jamais. Origine : l’administrateur et la Directrice Administrative.'),
  GesteReserve(
      id: gesteValiderAchats,
      libelle: 'Valider les achats : arbitrer un besoin, valider une commande de stock (RG-04)',
      module: 'M7',
      ecran: '',
      rolesDefaut: ['da'],
      aide: 'Écrans « Expression des besoins » (vue d’arbitrage) et « Commandes ». Accorder, rejeter ou renvoyer en complément un bon d’expression de besoins, et valider une commande de stock avant sa transmission au fournisseur (RG-04). Origine : la Directrice Administrative seule ; l’administrateur système ne l’a pas d’origine. Depuis un poste rattaché, le geste est transmis à la mère, qui le rejoue sous le rôle de son auteur.'),
  GesteReserve(
      id: gesteReglageFichiers,
      libelle: 'Régler la gestion des fichiers numérisés',
      module: 'CFG',
      ecran: 'cfg-systeme',
      rolesDefaut: ['admin', 'da'],
      aide: 'Taille maximale d’un scan, contrôle d’intégrité du dossier des scans. Se règle sur le poste mère. Origine : l’administrateur et la Directrice Administrative.'),
  GesteReserve(
      id: gesteReglageOcr,
      libelle: 'Régler la lecture des scans (OCR)',
      module: 'CFG',
      ecran: 'cfg-systeme',
      rolesDefaut: ['admin', 'da'],
      aide: 'Activer ou désactiver la lecture des scans, choisir le moteur, la langue et le délai. Se règle sur le poste mère. Origine : l’administrateur et la Directrice Administrative.'),
  GesteReserve(
      id: gesteReglageMecef,
      libelle: 'Régler la configuration MECeF',
      module: 'MECEF',
      ecran: 'mecef-config',
      rolesDefaut: ['admin', 'da'],
      aide: 'Le mode de certification des factures (boîtier ou e-MECeF), le modèle du boîtier et l’imprimante de caisse (modèle, largeur du papier, interface). Se règle sur le poste mère. Origine : l’administrateur et la Directrice Administrative.'),
  GesteReserve(
      id: gesteReglageEncaissementSansPrix,
      libelle: 'Régler l’encaissement d’une facture qui a une ligne sans prix',
      module: 'CFG',
      ecran: 'cfg-systeme',
      rolesDefaut: ['admin', 'da'],
      aide: 'Le réglage « Encaisser le reste d’une facture qui a une ligne sans prix » (Non par défaut : rien de la facture ne s’encaisse tant qu’une ligne attend son prix). Se règle depuis n’importe quel poste : sur un poste rattaché, la demande est transmise à la mère, qui l’applique. Origine : l’administrateur et la Directrice Administrative (à confirmer par la Direction).'),
  GesteReserve(
      id: gesteAlertesCaisse,
      libelle: 'Recevoir les notifications du poste de caisse',
      module: 'M8',
      ecran: '',
      rolesDefaut: ['caissier'],
      aide: 'Les notifications adressées à la caisse. Séparer la caisse de la pharmacie : accorder ce droit au rôle qui encaisse, le retirer à celui qui délivre. Origine : le Caissier.'),
  GesteReserve(
      id: gesteAlertesStock,
      libelle: 'Recevoir les notifications du poste stock',
      module: 'M6',
      ecran: '',
      rolesDefaut: ['stock', 'pharmacien', 'da'],
      aide: 'Besoins accordés, réapprovisionnement et notifications adressées au stock. Origine : le gestionnaire de stock, le pharmacien et la DAF.'),
  GesteReserve(
      id: gesteAlertesSeuilStock,
      libelle: 'Recevoir l’alerte « article sous son seuil »',
      module: 'M6',
      ecran: '',
      rolesDefaut: ['stock', 'pharmacien', 'caissier', 'da'],
      aide: 'L’alerte d’un article sous son seuil d’alerte (encore filtrée par la lecture de l’écran des alertes). Origine : le gestionnaire de stock, le pharmacien, le Caissier-Dispensateur et la DAF.'),
  GesteReserve(
      id: gesteAlertesPeremption,
      libelle: 'Recevoir l’alerte « lot périmé ou proche de la péremption »',
      module: 'M6',
      ecran: '',
      rolesDefaut: ['stock', 'pharmacien', 'caissier', 'laborantin'],
      aide: 'L’alerte de péremption d’un lot (encore filtrée par la lecture de l’écran des lots). Origine : le gestionnaire de stock, le pharmacien, le Caissier-Dispensateur et le Biologiste médical.'),
  GesteReserve(
      id: gesteAlertesMecefRejet,
      libelle: 'Recevoir l’alerte « facture rejetée par la MECeF »',
      module: 'MECEF',
      ecran: '',
      rolesDefaut: ['caissier', 'comptable', 'da', 'assistant_comptable'],
      aide: 'Une facture rejetée par l’administration fiscale, à corriger puis retransmettre. Origine : le Caissier, le Comptable, la DAF et l’Assistant de Direction.'),
  GesteReserve(
      id: gesteMecefRetransmettre,
      libelle: 'Retransmettre une pièce à la MECeF (une fois)',
      module: 'MECEF',
      ecran: 'mecef-transmission',
      rolesDefaut: ['caissier', 'da', 'admin'],
      aide: 'Corriger et retransmettre une pièce refusée, expirée ou en attente : une seule fois sans le droit suivant. Jamais une vente normalisée. Origine : le Caissier, la DAF et l’administrateur.'),
  GesteReserve(
      id: gesteMecefRetransmettreSansLimite,
      libelle: 'Retransmettre une pièce à la MECeF sans limite',
      module: 'MECEF',
      ecran: 'mecef-transmission',
      rolesDefaut: ['da', 'admin'],
      aide: 'Retransmettre une pièce déjà retransmise une fois (s’ajoute au droit précédent). Origine : la DAF et l’administrateur.'),
  // --- Aucune liste de rôles en dur (compléments du 16/11/2026) : gestes transverses, origine = la liste d'avant. ---
  GesteReserve(
      id: gesteAlertesComptable,
      libelle: 'Recevoir les notifications du poste comptable',
      module: '*',
      ecran: '',
      rolesDefaut: ['comptable', 'assistant_comptable', 'aide_comptable', 'da'],
      aide: 'Les notifications adressées au poste comptable (besoin accordé, engagement). Origine : le Comptable, l’Assistant de Direction, l’Assistant Comptable et la DAF.'),
  GesteReserve(
      id: gesteAlertesDirection,
      libelle: 'Recevoir les notifications du poste de la Direction',
      module: '*',
      ecran: '',
      rolesDefaut: ['direction', 'da', 'dm'],
      aide: 'Les notifications adressées à la Direction. Origine : la Direction, la DAF et le Directeur Médical.'),
  GesteReserve(
      id: gesteAlertesImagerie,
      libelle: 'Recevoir les notifications du poste d’imagerie',
      module: '*',
      ecran: '',
      rolesDefaut: ['echographiste', 'responsable_radiologie'],
      aide: 'Les demandes d’imagerie adressées au poste d’imagerie. Origine : le technicien d’échographie et le Responsable Radiologie.'),
  GesteReserve(
      id: gesteAlertesLaboratoire,
      libelle: 'Recevoir les notifications et alertes du laboratoire',
      module: '*',
      ecran: '',
      rolesDefaut: ['laborantin'],
      aide: 'Notifications adressées au laboratoire, analyses réglées à prélever, échantillons reçus à saisir. Origine : le Biologiste médical.'),
  GesteReserve(
      id: gesteAlertesPrescripteur,
      libelle: 'Recevoir les notifications du prescripteur',
      module: '*',
      ecran: '',
      rolesDefaut: ['medecin', 'chirurgien', 'anesthesiste', 'dm'],
      aide: 'Résultat disponible ou rectifié. Origine : le médecin, le chirurgien, l’anesthésiste et le Directeur Médical.'),
  GesteReserve(
      id: gesteAlertesSalleSoins,
      libelle: 'Recevoir les notifications de la salle de soins',
      module: '*',
      ecran: '',
      rolesDefaut: ['infirmier', 'aide_soignant', 'surveillant'],
      aide: 'Prescriptions de soins adressées à la salle de soins. Origine : l’infirmier, l’aide-soignante et le surveillant.'),
  GesteReserve(
      id: gesteAlertesHospitalisation,
      libelle: 'Recevoir les notifications de l’hospitalisation',
      module: '*',
      ecran: '',
      rolesDefaut: ['infirmier', 'aide_soignant', 'surveillant', 'medecin'],
      aide: 'Notifications adressées à l’hospitalisation. Origine : l’infirmier, l’aide-soignante, le surveillant et le médecin.'),
  GesteReserve(
      id: gesteAlertesEcheancesFiscales,
      libelle: 'Recevoir l’alerte « échéance fiscale dépassée »',
      module: '*',
      ecran: '',
      rolesDefaut: ['comptable', 'da', 'assistant_comptable', 'direction'],
      aide: 'Une échéance du calendrier fiscal dépassée et non payée. Origine : le Comptable, la DAF, l’Assistant de Direction et la Direction.'),
  GesteReserve(
      id: gesteAlertesCreances,
      libelle: 'Recevoir l’alerte « créance assureur en souffrance »',
      module: '*',
      ecran: '',
      rolesDefaut: ['da', 'comptable', 'direction', 'assistant_comptable', 'aide_comptable', 'responsable_assurance'],
      aide: 'Les créances assureur au-delà du seuil des objectifs de pilotage. Origine : la DAF, le Comptable, la Direction, l’Assistant de Direction, l’Assistant Comptable et le Responsable Assurance.'),
  GesteReserve(
      id: gesteAlertesBesoinsAValider,
      libelle: 'Recevoir l’alerte « bon de besoins à valider »',
      module: '*',
      ecran: '',
      rolesDefaut: ['da', 'direction'],
      aide: 'Un bon d’expression de besoins soumis. Origine : la DAF et la Direction. Arbitrer reste le geste « Valider les achats ».'),
  GesteReserve(
      id: gesteAlertesEcrituresBrouillon,
      libelle: 'Recevoir l’alerte « pièce comptable en brouillon »',
      module: '*',
      ecran: '',
      rolesDefaut: ['comptable', 'da', 'aide_comptable'],
      aide: 'Une pièce comptable en brouillon à contrôler (RG-10). Origine : le Comptable, la DAF et l’Assistant Comptable.'),
  GesteReserve(
      id: gesteAlertesDoublonsSync,
      libelle: 'Recevoir l’alerte « doublon détecté par la synchronisation »',
      module: '*',
      ecran: '',
      rolesDefaut: ['direction', 'da', 'comptable', 'admin'],
      aide: 'Dossier, facture, encaissement, délivrance, avoir ou écriture en double, lit en conflit, stock négatif. Origine : la Direction, la DAF, le Comptable et l’administrateur.'),
  GesteReserve(
      id: gesteConflitsTrancher,
      libelle: 'Trancher un conflit entre postes',
      module: '*',
      ecran: '',
      rolesDefaut: ['da', 'direction', 'admin'],
      aide: 'Trancher un champ écrit sur deux postes, arbitrer deux couvertures ouvertes, et en recevoir l’alerte. Origine : la DAF, la Direction et l’administrateur. L’appareil de la mère tranche toujours à son retour.'),
  GesteReserve(
      id: gesteSyncValiderFlux,
      libelle: 'Valider ou rejeter un flux échangé entre postes',
      module: '*',
      ecran: '',
      rolesDefaut: ['da', 'admin'],
      aide: 'La validation institutionnelle d’un flux de la règle de fusion pair. Origine : la DAF et l’administrateur.'),
  GesteReserve(
      id: gesteSystemeAdministrer,
      libelle: 'Administrer le système : poste mère et onglet « Système »',
      module: '*',
      ecran: '',
      rolesDefaut: ['admin', 'da'],
      aide: 'Les écrans du groupe « Poste mère » (exploitation, cycle, plateforme) et l’onglet « Système » du ruban. Il n’ouvre pas les écrans : la matrice les règle à part. Origine : l’administrateur et la DAF.'),
  GesteReserve(
      id: gesteInstallationConduire,
      libelle: 'Conduire l’assistant d’installation',
      module: '*',
      ecran: '',
      rolesDefaut: ['admin'],
      aide: 'L’assistant d’installation proposé tant qu’il est en cours sur ce poste. Origine : l’administrateur.'),
  GesteReserve(
      id: gesteDoubleFacteurImpose,
      libelle: 'Double facteur imposé au rôle',
      module: '*',
      ecran: '',
      rolesDefaut: ['dm', 'da', 'direction', 'admin'],
      aide: 'Le double facteur est coché d’office et imposé aux comptes du rôle, que la case soit cochée ou non. Origine : le Directeur Médical, la DAF, la Direction et l’administrateur.'),
  GesteReserve(
      id: gesteComptesReinitialiser,
      libelle: 'Réinitialiser le mot de passe d’un autre compte',
      module: '*',
      ecran: '',
      rolesDefaut: ['admin'],
      aide: 'Jamais son propre compte. Origine : l’administrateur.'),
  GesteReserve(
      id: gesteReglageVerrouSecours,
      libelle: 'Régler le verrou de secours',
      module: '*',
      ecran: '',
      rolesDefaut: ['admin', 'da'],
      aide: 'Le délai du verrou d’un poste de secours et la désignation de ce poste. Origine : l’administrateur et la DAF.'),
  GesteReserve(
      id: gesteReglageHorsSite,
      libelle: 'Régler la copie hors site des sauvegardes',
      module: '*',
      ecran: '',
      rolesDefaut: ['admin', 'da'],
      aide: 'Destination, chiffrement et contrôle de la copie hors site. Origine : l’administrateur et la DAF.'),
  GesteReserve(
      id: gesteReglageSms,
      libelle: 'Régler la passerelle SMS et tester l’envoi',
      module: 'MERE',
      ecran: 'mere-sms-passerelle',
      rolesDefaut: ['admin', 'da'],
      aide: 'Ouvrir ou fermer la passerelle SMS (fermée par défaut), envoyer un SMS d’essai, composer et déposer un SMS au relais depuis un modèle de message. Le journal des envois se lit avec le seul droit de l’écran. Origine PROPOSÉE, à valider par la Direction : l’administrateur et la DAF.'),
  GesteReserve(
      id: gesteFiscalValiderConfiguration,
      libelle: 'Valider la configuration fiscale',
      module: '*',
      ecran: '',
      rolesDefaut: ['direction', 'da', 'admin'],
      aide: 'Identité légale, obligations fiscales et paramètres ORTB datés. Origine : la Direction, la DAF et l’administrateur.'),
  GesteReserve(
      id: gesteAibTenir,
      libelle: 'Tenir le barème de l’AIB et ses réglages',
      module: '*',
      ecran: '',
      rolesDefaut: ['comptable', 'admin', 'da'],
      aide: 'Écrire une version du barème ou d’un réglage de l’AIB. La Direction lit sans écrire. Origine : le Comptable, l’administrateur et la DAF.'),
  GesteReserve(
      id: gesteFiscalConfirmer,
      libelle: 'Confirmer un taux fiscal (CNSS, barème de l’AIB)',
      module: '*',
      ecran: '',
      rolesDefaut: ['comptable', 'da'],
      aide: 'Le bouton « Confirmer » des taux de la CNSS et des versions du barème de l’AIB : motif obligatoire, auteur et date tracés ; rien n’est écrasé, la confirmation s’ajoute à une date d’effet. Origine PROPOSÉE, à valider par la Direction : le Comptable et la DAF.'),
  GesteReserve(
      id: gesteValidationsVueComplete,
      libelle: 'Voir toutes les familles au centre des validations',
      module: '*',
      ecran: '',
      rolesDefaut: ['direction', 'da', 'admin'],
      aide: 'Sans ce droit, un profil ne voit que les familles qu’il valide. Origine : la Direction, la DAF et l’administrateur.'),
  GesteReserve(
      id: gesteValidationsCentreElargi,
      libelle: 'Centre des validations élargi',
      module: '*',
      ecran: '',
      rolesDefaut: ['da', 'admin', 'direction', 'dm', 'comptable', 'surveillant', 'agentadmin'],
      aide: 'Les profils qui ouvraient le centre des validations y gardent toutes les rubriques ; les autres n’y voient que les familles de leur rôle. Origine : la DAF, l’administrateur, la Direction, le Directeur Médical, le Comptable, le surveillant et l’agent administratif.'),
  GesteReserve(
      id: gesteValiderRefDirection,
      libelle: 'Valider les référentiels du ressort de la Direction',
      module: '*',
      ecran: '',
      rolesDefaut: ['direction', 'da', 'admin'],
      aide: 'Modèles d’enquête, tarifs des actes et des analyses, valorisation SAGE, objectifs de pilotage, modèles de badge, jeux d’import, modèles de messages, barème de l’ITS. Origine : la Direction, la DAF et l’administrateur.'),
  GesteReserve(
      id: gesteValiderRefLabo,
      libelle: 'Valider les variables et unités du laboratoire',
      module: '*',
      ecran: '',
      rolesDefaut: ['laborantin'],
      aide: 'Les bornes suppléées du laboratoire. Origine : le Biologiste médical.'),
  GesteReserve(
      id: gesteValiderRefPathologies,
      libelle: 'Valider les pathologies',
      module: '*',
      ecran: '',
      rolesDefaut: ['dm', 'medecin'],
      aide: 'Le tableau de morbidité. Origine : le Directeur Médical et le médecin.'),
  GesteReserve(
      id: gesteValiderRefImagerie,
      libelle: 'Valider le catalogue de l’imagerie',
      module: '*',
      ecran: '',
      rolesDefaut: ['echographiste', 'responsable_radiologie', 'dm'],
      aide: 'Examens et variables de l’imagerie. Origine : le technicien d’échographie, le Responsable Radiologie et le Directeur Médical.'),
  GesteReserve(
      id: gesteValiderRefBloc,
      libelle: 'Valider les check-listes du bloc',
      module: '*',
      ecran: '',
      rolesDefaut: ['chirurgien', 'anesthesiste'],
      aide: 'Check-listes d’entrée et de sortie, échelles ASA et Mallampati. Origine : le chirurgien et l’anesthésiste.'),
  GesteReserve(
      id: gesteValiderRefRepartition,
      libelle: 'Valider la répartition fixe et variable des charges',
      module: '*',
      ecran: '',
      rolesDefaut: ['comptable', 'direction', 'da', 'admin'],
      aide: 'La répartition proposée des comptes de charge (seuil de rentabilité). Origine : le Comptable, la Direction, la DAF et l’administrateur.'),
  GesteReserve(
      id: gesteValiderRefBaremeAib,
      libelle: 'Valider le barème de l’AIB (marquage « à valider »)',
      module: '*',
      ecran: '',
      rolesDefaut: ['direction', 'da', 'admin', 'comptable'],
      aide: 'Le marquage « à valider » d’une version du barème au centre des validations. Origine : la Direction, la DAF, l’administrateur et le Comptable.'),
  GesteReserve(
      id: gesteRhRegler,
      libelle: 'Régler le personnel',
      module: '*',
      ecran: '',
      rolesDefaut: ['admin', 'da'],
      aide: 'Circuit de validation des présences, « l’agent modifie directement », dérogation de régime individuel, délai du pointage par badge, copie de la fiche de paie sur le téléphone. Origine : l’administrateur et la DAF.'),
  GesteReserve(
      id: gesteRhEncadrer,
      libelle: 'Encadrer le planning du personnel',
      module: '*',
      ecran: '',
      rolesDefaut: ['surveillant', 'da', 'admin'],
      aide: 'Poser et retirer le planning, voir et valider les propositions des agents, régulariser un pointage, consigner l’avis du chef de service sur un ordre de mission. Origine : le surveillant, la DAF et l’administrateur.'),
  GesteReserve(
      id: gesteRhEtapeSurveillant,
      libelle: 'Valider l’étape « surveillant » du circuit RH',
      module: '*',
      ecran: '',
      rolesDefaut: ['surveillant', 'admin'],
      aide: 'Présences, absences et missions à l’étape du surveillant. Origine : le surveillant et l’administrateur.'),
  GesteReserve(
      id: gesteRhEtapeDaf,
      libelle: 'Valider l’étape « directrice administrative » du circuit RH',
      module: '*',
      ecran: '',
      rolesDefaut: ['da', 'admin'],
      aide: 'Présences, absences et missions à l’étape de la directrice administrative. Origine : la DAF et l’administrateur.'),
  GesteReserve(
      id: gesteRhPointerBadge,
      libelle: 'Pointer un badge',
      module: '*',
      ecran: '',
      rolesDefaut: ['surveillant', 'da', 'admin', 'direction', 'rh'],
      aide: 'Le pointage par badge à l’écran de vérification, quand le réglage est actif. Origine : le surveillant, la DAF, l’administrateur, la Direction et le compte RH.'),
  GesteReserve(
      id: gesteImagerieExecuter,
      libelle: 'Exécuter l’imagerie sans la prescrire',
      module: '*',
      ecran: '',
      rolesDefaut: ['echographiste', 'responsable_radiologie'],
      aide: 'Lire tous les comptes rendus d’imagerie, ouvrir celui d’un examen payé, ne jamais créer de demande (prescrire n’est pas exécuter). Origine : le technicien d’échographie et le Responsable Radiologie.'),
  GesteReserve(
      id: gesteRubriquesChirurgicales,
      libelle: 'Écrire les rubriques chirurgicales du dossier de consultation',
      module: '*',
      ecran: '',
      rolesDefaut: ['chirurgien'],
      aide: 'Les rubriques chirurgicales s’écrivent par le chirurgien et se lisent par tous. Origine : le chirurgien (la fonction de chirurgien de l’agent les ouvre aussi).'),
  GesteReserve(
      id: gesteAchatsRegistre,
      libelle: 'Voir les besoins validés et le registre complet des achats',
      module: '*',
      ecran: '',
      rolesDefaut: ['comptable', 'stock', 'da', 'direction', 'admin', 'aide_comptable'],
      aide: 'Les vues « Besoins validés » et « Tous les bons » de l’expression des besoins. Origine : le Comptable, le gestionnaire de stock, la DAF, la Direction, l’administrateur et l’Assistant Comptable.'),
  GesteReserve(
      id: gestePtaAdopter,
      libelle: 'Adopter, renvoyer ou clôturer le plan de travail annuel',
      module: 'M13',
      ecran: 'm13-plan-annuel',
      rolesDefaut: ['direction', 'da'],
      aide: 'Adopter un plan soumis (motif et date, jamais par celui qui l’a soumis), le renvoyer en brouillon, le clôturer avec son bilan. Depuis un poste rattaché, le geste est transmis à la mère, qui l’applique. Origine : Modèle proposé le 16/11/2026, à valider (la Direction et la DAF).'),
  GesteReserve(
      id: gestePtaRegler,
      libelle: 'Régler les référentiels du plan de travail annuel',
      module: 'M13',
      ecran: 'm13-plan-annuel',
      rolesDefaut: ['admin', 'da'],
      aide: 'Axes, états d’avancement et sources de financement du plan (écran du plan, onglet « Référentiels »), périodicité, seuil d’alerte de retard et préfixe de numérotation (Paramètres, famille « Plan de travail annuel »). Origine proposée, à valider : l’administrateur et la DAF.'),
  GesteReserve(
      id: gesteAlertesPtaRetard,
      libelle: 'Recevoir l’alerte « action du plan de travail annuel en retard »',
      module: '*',
      ecran: '',
      rolesDefaut: ['direction', 'da'],
      aide: 'Une ligne par action non terminée dont la période est échue depuis plus que le seuil réglé. Origine proposée, à valider : la Direction et la DAF.'),
];

GesteReserve? gesteReserve(String id) {
  for (final g in gestesReserves) {
    if (g.id == id) return g;
  }
  return null;
}

/// La clé du droit dans une décision (`geste.<id>`) ; dans la fiche : `droitsGestes.<id>`.
String drCleGeste(String id) => 'geste.$id';

/// Les droits sur les gestes réservés, évalués À CHAQUE appel depuis les fiches `rbac` et la matrice EN FORCE.
class DroitsGestes {
  /// [fiches] : la collection `rbac`. [estArchive] : le rôle est-il archivé (matrice en force) ? [ecranActif] : `(écran, module) → bool`, l'activité est-elle
  /// ouverte ? `null` = non branché (réputé ouvert : un test nu).
  DroitsGestes({required Iterable<Map<String, Object?>> fiches, bool Function(String role)? estArchive, bool Function(String ecran, String module)? ecranActif})
      : _sur = surchargesParRole(fiches),
        _archive = estArchive,
        _actif = ecranActif;

  final Map<String, Map<String, Object?>> _sur;
  final bool Function(String role)? _archive;
  final bool Function(String ecran, String module)? _actif;

  /// La décision EXPLICITE de la clinique pour ce rôle et ce geste (`null` : aucune, l'origine s'applique).
  bool? decision(String role, String geste) {
    final m = _sur[role]?['droitsGestes'];
    if (m is! Map) return null;
    final v = m[geste];
    return v is bool ? v : null;
  }

  /// L'origine : le rôle est-il dans la liste d'origine du geste ? Geste inconnu : refusé.
  bool defaut(String role, String geste) => gesteReserve(geste)?.rolesDefaut.contains(role) ?? false;

  /// Le rôle détient-il ce geste ? Rôle vide, geste inconnu, rôle archivé, écran ou module fermé : non.
  bool peut(String role, String geste) {
    final g = gesteReserve(geste);
    if (g == null || role.isEmpty) return false;
    if (_archive?.call(role) ?? false) return false;
    // Un geste porté par PLUSIEURS écrans d'un module (`ecran` vide, module nommé : valider les achats) tombe avec son MODULE fermé.
    if ((g.ecran.isNotEmpty || g.module != '*') && !(_actif?.call(g.ecran, g.module) ?? true)) return false;
    // Un geste transverse sans décision ne se juge pas sans écran : voir [peutSurEcran].
    if (g.suitEcran) return decision(role, geste) ?? false;
    return decision(role, geste) ?? defaut(role, geste);
  }

  /// Le rôle détient-il le geste TRANSVERSE [geste] sur l'écran [ecran] ? La décision de la clinique l'emporte dans les deux sens ; sans décision, le rôle doit LIRE
  /// l'écran ([peutVoirEcran], la matrice en force ; `null` = matrice non branchée, un test nu : écran réputé ouvert). Rôle vide, geste inconnu ou non transverse,
  /// rôle archivé : non.
  bool peutSurEcran(String role, String geste, String ecran, {bool Function(String role, String ecran)? peutVoirEcran}) {
    final g = gesteReserve(geste);
    if (g == null || !g.suitEcran || role.isEmpty) return false;
    if (_archive?.call(role) ?? false) return false;
    return decision(role, geste) ?? (peutVoirEcran?.call(role, ecran) ?? true);
  }

  /// `origine` ou `decide` : d'où vient le droit (écran d'administration).
  String origine(String role, String geste) => decision(role, geste) == null ? 'origine' : 'decide';

  /// Les rôles de [roles] qui détiennent le geste (liste DÉRIVÉE du droit, jamais recopiée).
  List<String> rolesAvec(String geste, Iterable<String> roles) => [
        for (final r in roles)
          if (peut(r, geste)) r
      ];
}

/// Les droits d'ORIGINE, sans aucune fiche : ce que valaient les listes de rôles écrites en dur avant leur conversion en gestes. Le repli des moteurs quand l'appelant ne
/// passe pas la matrice en force (un test nu, un vecteur) — jamais une décision de la clinique.
DroitsGestes gestesOrigine() => DroitsGestes(fiches: const []);
