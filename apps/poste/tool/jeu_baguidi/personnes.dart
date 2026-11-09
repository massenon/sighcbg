// LES PERSONNES DU JEU BAGUIDI (J3, J4, J5) : le personnel réel, ses comptes, les soignants qui en découlent et les vacataires fictifs des spécialités.
//
// LES NEUF PERSONNES RÉELLES portent leur nom exact (orthographe du RCCM pour BAGUIDI). Tout ce qui est PERSONNEL et que la Direction n'a pas remis
// (CNSS, téléphone, naissance, sexe, situation de famille, date d'embauche) est VIDE ou marqué provisoire : le jeu n'invente pas l'état civil de
// quelqu'un. Les salaires sont des valeurs d'attente, marquées `salaireProvisoire`.
//
// AUCUN MOT DE PASSE, AUCUNE EMPREINTE dans le dépôt. Le modèle des comptes n'en a pas besoin : un compte vit dans `utilisateurs` SANS secret, et le
// haché Argon2id d'un mot de passe vit dans la collection technique `identifiants`, que le jeu ne contient jamais (`core/identifiants.dart`). Un compte sans
// fiche `identifiants` n'ouvre pas de session (refus générique, motif « sans identifiant » au journal) : c'est l'état « mot de passe à définir ». Le drapeau
// explicite `motDePasseADefinir` le dit sur la fiche. Voir `tool/README.md` pour la marche à suivre de l'administrateur.
import 'package:sigh_poste/donnees/magasin.dart';

import 'contexte.dart';

/// Un agent réel : identifiant `m-NNN`, nom, prénom, fonction (clé des capacités du poste), service, intitulé de poste, rôle du compte, salaire d'attente.
typedef _Agent = ({String id, String nom, String prenom, String fonction, String service, String poste, String role, int salaire});

const List<_Agent> _agents = [
  (id: 'm-001', nom: 'BAGUIDI', prenom: 'Rafiou', fonction: 'direction', service: 'Direction', poste: 'Directeur Général', role: 'direction', salaire: 250000),
  (id: 'm-002', nom: 'SANOUSSI', prenom: 'Adamon', fonction: 'comptable', service: 'Comptabilité', poste: 'Comptable', role: 'comptable', salaire: 150000),
  (id: 'm-003', nom: 'MABOUDOU', prenom: 'Nawal', fonction: 'rh', service: 'Ressources humaines', poste: 'Responsable des ressources humaines', role: 'rh', salaire: 130000),
  (id: 'm-004', nom: 'IDOHOU', prenom: 'Abraham', fonction: 'medecin', service: 'Médecine générale', poste: 'Médecin', role: 'medecin', salaire: 220000),
  (id: 'm-005', nom: 'AKONDE', prenom: 'Octave', fonction: 'infirmier', service: 'Soins infirmiers', poste: 'Infirmier', role: 'infirmier', salaire: 90000),
  (id: 'm-006', nom: 'SOKOU', prenom: 'Peace', fonction: 'direction', service: 'Direction', poste: 'Direction', role: 'direction', salaire: 250000),
  (id: 'm-007', nom: 'ZIME', prenom: 'Nadège', fonction: 'comptable', service: 'Comptabilité', poste: 'Comptable', role: 'comptable', salaire: 150000),
  (id: 'm-008', nom: 'TOUNGOUH', prenom: 'A. Zoulkifouli', fonction: 'rh', service: 'Ressources humaines', poste: 'Responsable des ressources humaines', role: 'rh', salaire: 130000),
];

/// Le domaine des adresses de connexion : `m-NNN@baguidi-clinique.bj`.
const String domaineComptes = 'baguidi-clinique.bj';

/// L'identifiant de l'administrateur système.
const String identifiantAdmin = 'admin@$domaineComptes';

const String _sourcePersonnel = 'Personnel réel de la Clinique Baguidi (Direction, 08/11/2026) ; champs personnels non remis, salaire d’attente à confirmer';

/// Les douze vacataires des spécialités (J5), FICTIFS : aucun nom de personne, aucun cabinet, aucun numéro de téléphone.
const List<(String, String)> _vacataires = [
  ('Cardiologue', 'Cardiologie'),
  ('Endocrinologue', 'Endocrinologie'),
  ('Neurologue', 'Neurologie'),
  ('Pédiatre', 'Pédiatrie'),
  ('Ophtalmologue', 'Ophtalmologie'),
  ('Urologue', 'Urologie'),
  ('Rhumatologue', 'Rhumatologie'),
  ('Orthophoniste', 'Orthophonie'),
  ('Kinésithérapeute', 'Kinésithérapie'),
  ('Gynécologue', 'Gynécologie'),
  ('Chirurgien', 'Chirurgie'),
  ('Échographiste', 'Échographie'),
];

void generer(Contexte ctx) {
  _personnel(ctx);
  _comptes(ctx);
  _soignants(ctx);
  _prestataires(ctx);
  // Le rôle `stock` reste actif sans titulaire (Q33) : sa fiche RBAC est conservée du socle, aucun compte ne le porte. L'écran des rôles compte les comptes
  // par rôle : un rôle à zéro compte s'y lit tel quel.
  ctx.note('personnes : rôle « stock » actif sans titulaire (Q33), aucun compte archivé');
}

void _personnel(Contexte ctx) {
  ctx.remplacer('personnel', [
    for (final a in _agents)
      {
        'id': a.id,
        'matricule': a.id,
        'nom': a.nom,
        'prenom': a.prenom,
        'nomComplet': '${a.nom} ${a.prenom}',
        'sexe': '',
        'fonction': a.fonction,
        'poste': a.poste,
        'service': a.service,
        'categorie': '',
        'salaireBase': a.salaire,
        'salaireProvisoire': true,
        // Date d'attente : le début de la fenêtre du jeu. La vraie date d'embauche n'a pas été remise ; le moteur de paie en a besoin pour l'ancienneté.
        'dateEmbauche': Contexte.date(Contexte.debutFenetre),
        'dateEmbaucheProvisoire': true,
        'cnss': '',
        'telephone': '',
        'situation': '',
        'statut': 'actif',
        'source': _sourcePersonnel,
      }
  ]);
  ctx.note('personnes : ${_agents.length} agents réels, champs personnels vides, salaires d\'attente marqués salaireProvisoire');
}

void _comptes(Contexte ctx) {
  final creeLe = Contexte.date(Contexte.debutFenetre);
  ctx.remplacer('utilisateurs', [
    {
      'id': 'USR000',
      'statut': 'actif',
      'identifiant': identifiantAdmin,
      'nomComplet': 'Administrateur système',
      'role': 'admin',
      'service': 'Administration',
      'poste': 'Administrateur système',
      'actif': true,
      'mfa': false,
      'echecs': 0,
      'creeLe': creeLe,
      'motDePasseADefinir': true,
    },
    for (var i = 0; i < _agents.length; i++)
      {
        'id': 'USR${(i + 1).toString().padLeft(3, '0')}',
        'statut': 'actif',
        'identifiant': '${_agents[i].id}@$domaineComptes',
        'nomComplet': '${_agents[i].nom} ${_agents[i].prenom}',
        'employeId': _agents[i].id,
        'matricule': _agents[i].id,
        'role': _agents[i].role,
        'service': _agents[i].service,
        'poste': _agents[i].poste,
        'actif': true,
        'mfa': false,
        'echecs': 0,
        'creeLe': creeLe,
        'motDePasseADefinir': true,
      },
  ]);
  ctx.note('personnes : ${_agents.length + 1} comptes actifs sans mot de passe ni empreinte (collection `identifiants` absente du jeu)');
}

/// Les soignants sont DÉRIVÉS du personnel, jamais ressaisis : le médecin prescrit, l'infirmier exécute (mêmes drapeaux que le jeu d'origine).
void _soignants(Contexte ctx) {
  Fiche soignant(int rang, _Agent a, {required String qualite, required bool prescrit, required bool execute, required List<String> secteurs}) => {
        'id': 'SOI${rang.toString().padLeft(2, '0')}',
        'personnelId': a.id,
        'nomComplet': '${a.nom} ${a.prenom}',
        'poste': a.poste,
        'qualite': qualite,
        'prescrit': prescrit,
        'execute': execute,
        'supervise': false,
        'realiseImagerie': false,
        'secteurs': secteurs,
        'statut': 'actif',
        'source': 'Dérivé du personnel de la Clinique Baguidi',
      };
  final medecin = _agents.firstWhere((a) => a.role == 'medecin');
  final infirmier = _agents.firstWhere((a) => a.role == 'infirmier');
  ctx.remplacer('soignants', [
    soignant(1, medecin, qualite: 'medecin', prescrit: true, execute: false, secteurs: const ['salle_soins', 'hospitalisation', 'maternite']),
    soignant(2, infirmier, qualite: 'infirmier', prescrit: false, execute: true, secteurs: const ['salle_soins', 'hospitalisation']),
  ]);
}

void _prestataires(Contexte ctx) {
  var i = 0;
  ctx.remplacer('prestataires', [
    for (final (intitule, specialite) in _vacataires)
      {
        'id': 'PRE${(++i).toString().padLeft(4, '0')}',
        'statut': 'actif',
        'reference': 'PE-${i.toString().padLeft(4, '0')}',
        'nom': '$intitule vacataire (fictif de démonstration)',
        'specialite': specialite,
        'telephone': '',
        'tarifActe': 0,
        'tarifAFournir': true,
        'actesRealises': 0,
        'factureNormalisee': false,
        'fictif': true,
        'source': 'Vacataire fictif de démonstration : sans compte, sans numéro, sans cabinet ; à remplacer par les praticiens réels',
      }
  ]);
  ctx.note('personnes : ${_vacataires.length} vacataires fictifs (prestataires de M10), sans compte ni téléphone');
}
