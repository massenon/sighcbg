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

/// Exporter ou imprimer les lignes d'un tableau (Q39, Direction du 15/11/2026) : un droit réglable PAR RÔLE. Sans décision, il suit la lecture de l'écran (les rôles qui
/// LISENT l'écran exportent) ; une décision l'accorde ou le retire au rôle pour tous les écrans. Il s'applique à la SORTIE : le fichier ne porte que ce que l'écran montre.
const String gesteExporter = 'export_tableau';
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
      libelle: 'Exporter et imprimer les lignes d’un tableau',
      module: '*',
      ecran: '',
      rolesDefaut: [],
      suitEcran: true,
      aide: 'Excel, CSV et impression de la sélection. Sans décision, le droit suit la lecture de l’écran : qui lit le tableau peut l’exporter. Accordé ou retiré à un rôle, il vaut pour tous les écrans. Le fichier ne porte que les colonnes et les lignes que l’écran montre, champs sensibles masqués comme à l’écran.'),
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
      aide: 'Le mode de certification des factures (boîtier ou e-MECeF). Se règle sur le poste mère. Origine : l’administrateur et la Directrice Administrative.'),
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
