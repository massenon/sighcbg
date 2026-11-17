/// LES FICHES D'AIDE DE L'ASSISTANT : rédaction, validation, archivage (écran `cfg-fiches-aide`, Direction de Baguidi, 16 et 17/11/2026, DECISIONS-16-11 § 2 et § 9).
///
/// L'assistant (intentions I26 « comment faire » et I27 « c'est quoi ») ne répond JAMAIS de mémoire : il cite une fiche écrite et VALIDÉE de la collection [colFichesAide], avec son validateur
/// nommé et la date. Ce fichier porte ce qui rend une fiche citable, et rien d'autre :
///
///  * une fiche porte un titre, des mots-clés (sans eux, l'assistant ne la reconnaîtrait jamais), les rôles auxquels elle est RÉSERVÉE (liste des rôles de la MATRICE, jamais une liste écrite
///    ici ; vide = tous), des étapes (une aide) ou une définition (un glossaire), et les écrans qu'elle cite ;
///  * son statut avance de `proposee` à `validee`, puis s'ARCHIVE (RG-14 : jamais de suppression). Une fiche validée ne se réécrit pas : la réviser crée une fiche nouvelle qui la REMPLACE
///    quand elle est validée à son tour (on ne cite jamais un texte que personne n'a relu) ;
///  * la VALIDATION est un geste réservé ([gesteFichesAideValider]), distinct de la rédaction (le droit d'écrire l'écran) : l'auteur d'une fiche ne la valide pas ;
///  * une fiche qui engage un PROFESSIONNEL (la check-liste du bloc, Q94) porte un `domainePro` : sa validation exige le geste de ce professionnel ([DomaineProFicheAide.geste]) ET un champ
///    « validé par (professionnel) » non vide et daté. La Direction ne valide pas à la place d'un chirurgien ;
///  * le CONTENU des fiches n'est écrit par personne ici : la liste des fiches ATTENDUES ([fichesAideAttendues], relue du document des 100 questions) dit ce qui manque, avec son statut CALCULÉ.
///
/// Fonctions PURES : le poste y branche sa collection, son journal et la matrice ; la mère Dart et le banc Node en reprennent la règle d'écriture ([refusEcritureFicheAide]), à l'identique.
library;

import '../droits/gestes_reserves.dart';

/// La collection des fiches (famille A : une fiche, une identité commune, champ à champ ; la VALIDATION n'est écrite que par la mère).
const String colFichesAide = 'fichesAide';

const String ficheAideTypeAide = 'aide';
const String ficheAideTypeDefinition = 'definition';
const List<String> ficheAideTypes = [ficheAideTypeAide, ficheAideTypeDefinition];
const Map<String, String> ficheAideLibellesTypes = {ficheAideTypeAide: 'Aide (comment faire)', ficheAideTypeDefinition: 'Définition (c’est quoi)'};

const String ficheAideProposee = 'proposee';
const String ficheAideValidee = 'validee';

/// Le statut `archive` est celui de TOUTE fiche du magasin archivée (RG-14).
const String ficheAideArchivee = 'archive';

/// Les champs qui portent la VALIDATION : seule la mère les écrit (un poste rattaché en est refusé).
const List<String> ficheAideChampsValidation = ['validateurId', 'validePar', 'valideLe', 'professionnel', 'professionnelLe'];

/// Les champs de CONTENU : une fiche validée ne les réécrit plus.
const List<String> ficheAideChampsContenu = ['type', 'titre', 'motsCles', 'roles', 'ecrans', 'etapes', 'definition', 'domainePro', 'questionAttendue', 'remplace'];

/// Un domaine qui engage un PROFESSIONNEL nommé : la fiche qui le porte ne se valide qu'avec le geste de ce professionnel et son nom daté.
class DomaineProFicheAide {
  const DomaineProFicheAide(this.id, this.libelle, this.geste);
  final String id;
  final String libelle;

  /// Le geste réservé que détient le professionnel (le référentiel des gestes dit qui l'a d'origine ; la clinique le règle).
  final String geste;
}

/// Les domaines professionnels connus. Un seul à ce jour : le bloc opératoire (Q94). Ajouter un domaine, c'est ajouter une ligne ici (et le geste du professionnel au référentiel des gestes).
const List<DomaineProFicheAide> fichesAideDomainesPro = [
  DomaineProFicheAide('bloc', 'Bloc opératoire (check-liste, gestes d’anesthésie)', gesteValiderRefBloc),
];

DomaineProFicheAide? domaineProFicheAide(String? id) {
  for (final d in fichesAideDomainesPro) {
    if (d.id == id) return d;
  }
  return null;
}

/// Une fiche ATTENDUE : une question réelle des agents (document `docs/prd/ASSISTANT-100-questions-par-role.md`, colonne « Décision » : « fiche d'aide à rédiger » ou « fiche de définition à
/// rédiger ») dont la réponse est une fiche que PERSONNE n'a écrite. La liste est relue du document par `fiches_aide_test.dart` : elle ne peut pas diverger de lui.
class FicheAideAttendue {
  const FicheAideAttendue(this.numero, this.libelleRole, this.question, this.type, {this.domainePro});
  final int numero;

  /// Le rôle qui a posé la question, tel que le document le nomme (un libellé d'affichage : il ne décide d'aucun droit).
  final String libelleRole;

  /// La question, mot pour mot.
  final String question;
  final String type;

  /// Non nul quand la fiche engage un professionnel (validation réservée à ce professionnel).
  final String? domainePro;
}

/// Les fiches attendues, lues du document des 100 questions. Neuf : sept procédures (Q4, Q29, Q58, Q64, Q68, Q80, Q84), la check-liste du bloc (Q94, dont la fiche ne s'écrit qu'APRÈS la
/// validation de la check-liste par le professionnel nommé) et la définition d'un avoir (Q99). AUCUNE n'est écrite ici.
const List<FicheAideAttendue> fichesAideAttendues = [
  FicheAideAttendue(4, 'Administrateur système', 'Comment je crée un nouvel utilisateur et je lui donne un rôle ?', ficheAideTypeAide),
  FicheAideAttendue(29, 'Infirmier / Sage-femme', 'Comment je note la sortie d\'un patient hospitalisé ?', ficheAideTypeAide),
  FicheAideAttendue(58, 'Agent Administratif', 'Comment j\'enregistre un courrier entrant ?', ficheAideTypeAide),
  FicheAideAttendue(64, 'Ambulancier', 'Comment je remplis la fiche de transport ?', ficheAideTypeAide),
  FicheAideAttendue(68, 'Aide-soignante', 'Où je note les constantes d\'un patient ?', ficheAideTypeAide),
  FicheAideAttendue(80, 'Surveillant', 'Comment je valide une proposition de planning ?', ficheAideTypeAide),
  FicheAideAttendue(84, 'Assistant de Direction', 'Comment je fais une note de service ?', ficheAideTypeAide),
  FicheAideAttendue(94, 'Anesthésiste, Réanimateur', 'Comment on remplit la check-list du bloc ?', ficheAideTypeAide, domainePro: 'bloc'),
  FicheAideAttendue(99, 'Assistant Comptable', 'C\'est quoi un avoir ?', ficheAideTypeDefinition),
];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// CE QUI REND UNE FICHE CITABLE
// ---------------------------------------------------------------------------------------------------------------------------------------------

bool _plein(Object? v) => v != null && '$v'.trim().isNotEmpty;

/// Une fiche est CITABLE par l'assistant quand elle est `validee` ET porte son validateur nommé et la date de validation ; une fiche qui engage un professionnel porte en plus son nom et la
/// date. C'est le SEUL prédicat que le moteur de l'assistant consulte : une fiche « validée » sans validateur (saisie à la main dans la base, import) n'est jamais citée.
bool ficheAideCitable(Map<String, Object?> f) {
  if (f['statut'] != ficheAideValidee || !_plein(f['validePar']) || !_plein(f['valideLe'])) return false;
  if (_plein(f['domainePro']) && (!_plein(f['professionnel']) || !_plein(f['professionnelLe']))) return false;
  return true;
}

/// Le STATUT CALCULÉ d'une fiche attendue : `a_ecrire` (aucune fiche liée), `proposee` (une fiche liée existe, pas encore citable), `validee` (une fiche liée est citable).
const String attendueAEcrire = 'a_ecrire';
const String attendueProposee = 'proposee';
const String attendueValidee = 'validee';

String statutFicheAttendue(FicheAideAttendue a, Iterable<Map<String, Object?>> fiches) {
  var liee = false;
  for (final f in fiches) {
    if (f['statut'] == ficheAideArchivee || '${f['questionAttendue']}' != '${a.numero}') continue;
    if (ficheAideCitable(f)) return attendueValidee;
    liee = true;
  }
  return liee ? attendueProposee : attendueAEcrire;
}

const Map<String, String> attendueLibelles = {attendueAEcrire: 'Pas encore écrite', attendueProposee: 'Écrite, en attente de validation', attendueValidee: 'Validée'};

// ---------------------------------------------------------------------------------------------------------------------------------------------
// RÉDACTION
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Un refus nommé : code stable, motif, geste pour corriger.
class RefusFicheAide {
  const RefusFicheAide(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
  @override
  String toString() => '$code : $motif';
}

/// Le verdict d'un geste sur une fiche : le patch (ou la fiche entière à la création), ou un refus nommé. [archiver] : l'identifiant d'une fiche que ce geste doit archiver à son tour (la fiche
/// remplacée, quand sa remplaçante est validée).
class VerdictFicheAide {
  const VerdictFicheAide._(this.fiche, this.refus, this.archiver);
  factory VerdictFicheAide.ok(Map<String, Object?> fiche, {String? archiver}) => VerdictFicheAide._(fiche, null, archiver);
  factory VerdictFicheAide.refus(String code, String motif, String geste) => VerdictFicheAide._(null, RefusFicheAide(code, motif, geste), null);
  final Map<String, Object?>? fiche;
  final RefusFicheAide? refus;
  final String? archiver;
  bool get accepte => fiche != null;
}

List<String> _liste(Object? v) => v is List ? [for (final x in v) if (_plein(x)) '$x'.trim()] : const [];

/// Normalise le contenu saisi : textes rognés, listes sans vides ni doublons. Ne devine rien.
Map<String, Object?> contenuFicheAide(Map<String, Object?> saisie) {
  List<String> sansDoublons(List<String> l) => [...l.toSet()];
  final type = '${saisie['type'] ?? ''}'.trim();
  return {
    'type': type,
    'titre': '${saisie['titre'] ?? ''}'.trim(),
    'motsCles': sansDoublons(_liste(saisie['motsCles'])),
    'roles': sansDoublons(_liste(saisie['roles'])),
    'ecrans': sansDoublons(_liste(saisie['ecrans'])),
    if (type == ficheAideTypeAide) 'etapes': _liste(saisie['etapes']),
    if (type == ficheAideTypeDefinition) 'definition': '${saisie['definition'] ?? ''}'.trim(),
    if (_plein(saisie['domainePro'])) 'domainePro': '${saisie['domainePro']}'.trim(),
    if (_plein(saisie['questionAttendue'])) 'questionAttendue': int.tryParse('${saisie['questionAttendue']}') ?? '${saisie['questionAttendue']}',
    if (_plein(saisie['remplace'])) 'remplace': '${saisie['remplace']}'.trim(),
  };
}

/// Contrôle le contenu d'une fiche. [rolesConnus] : les rôles de la MATRICE (identifiants) ; [ecransConnus] : les écrans du manifeste (facultatif : sans lui, les écrans ne sont pas contrôlés).
/// Rend le premier refus, ou `null`.
RefusFicheAide? controlerContenuFicheAide(Map<String, Object?> contenu, {required Iterable<String> rolesConnus, Iterable<String>? ecransConnus}) {
  RefusFicheAide non(String code, String motif, String geste) => RefusFicheAide(code, motif, geste);
  final type = '${contenu['type'] ?? ''}';
  if (!ficheAideTypes.contains(type)) return non('TYPE_INVALIDE', 'Une fiche est une aide (« comment faire ») ou une définition (« c’est quoi »).', 'Choisir le type de la fiche.');
  if (!_plein(contenu['titre'])) return non('TITRE_ABSENT', 'Une fiche porte son titre : c’est lui que l’assistant affiche.', 'Saisir le titre.');
  if (_liste(contenu['motsCles']).isEmpty) {
    return non('MOTS_CLES_ABSENTS', 'Sans mot-clé, l’assistant ne reconnaîtrait jamais la question à laquelle la fiche répond.', 'Saisir au moins un mot-clé (une expression que l’agent écrirait).');
  }
  if (type == ficheAideTypeAide) {
    if (_liste(contenu['etapes']).isEmpty) return non('ETAPES_ABSENTES', 'Une aide se lit pas à pas : elle porte au moins une étape.', 'Saisir les étapes, une par ligne.');
  } else if (!_plein(contenu['definition'])) {
    return non('DEFINITION_ABSENTE', 'Une définition porte son texte.', 'Saisir la définition.');
  }
  final connus = rolesConnus.toSet();
  for (final r in _liste(contenu['roles'])) {
    if (!connus.contains(r)) return non('ROLE_INCONNU', 'Le rôle « $r » n’existe pas dans la matrice des droits : une fiche n’est réservée qu’à un rôle qui existe.', 'Choisir les rôles dans la liste de la matrice.');
  }
  if (ecransConnus != null) {
    final e = ecransConnus.toSet();
    for (final x in _liste(contenu['ecrans'])) {
      if (!e.contains(x)) return non('ECRAN_INCONNU', 'L’écran « $x » n’existe pas au manifeste.', 'Choisir les écrans dans la liste du manifeste.');
    }
  }
  if (_plein(contenu['domainePro']) && domaineProFicheAide('${contenu['domainePro']}') == null) {
    return non('DOMAINE_INCONNU', 'Le domaine professionnel « ${contenu['domainePro']} » n’est pas au référentiel.', 'Choisir un domaine de la liste, ou aucun.');
  }
  final q = contenu['questionAttendue'];
  if (q != null && !fichesAideAttendues.any((a) => '${a.numero}' == '$q')) {
    return non('QUESTION_INCONNUE', 'La question « $q » ne figure pas parmi les fiches attendues.', 'Choisir la question dans la liste, ou aucune.');
  }
  return null;
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// CRÉE une fiche : toujours `proposee`, jamais validée à la naissance, avec son auteur (nom et identifiant du compte : la comparaison « l'auteur ne valide pas » se fait sur l'identifiant).
VerdictFicheAide creerFicheAide({
  required Map<String, Object?> saisie,
  required String id,
  required String auteurId,
  required String auteurNom,
  required DateTime maintenant,
  required Iterable<String> rolesConnus,
  Iterable<String>? ecransConnus,
}) {
  if (!_plein(auteurId) || !_plein(auteurNom)) {
    return VerdictFicheAide.refus('AUTEUR_ABSENT', 'Aucune action anonyme (RG-12) : une fiche porte son auteur.', 'Ouvrir une session nominative.');
  }
  final contenu = contenuFicheAide(saisie);
  final r = controlerContenuFicheAide(contenu, rolesConnus: rolesConnus, ecransConnus: ecransConnus);
  if (r != null) return VerdictFicheAide.refus(r.code, r.motif, r.geste);
  return VerdictFicheAide.ok({
    'id': id,
    ...contenu,
    'statut': ficheAideProposee,
    'auteurId': auteurId,
    'auteurNom': auteurNom,
    'creeLe': maintenant.toUtc().toIso8601String(),
  });
}

/// MODIFIE le contenu d'une fiche NON validée. Une fiche validée ne se réécrit pas (on la révise : [reviserFicheAide]) ; une fiche archivée non plus.
VerdictFicheAide modifierFicheAide({
  required Map<String, Object?>? actuelle,
  required Map<String, Object?> saisie,
  required DateTime maintenant,
  required Iterable<String> rolesConnus,
  Iterable<String>? ecransConnus,
}) {
  if (actuelle == null) return VerdictFicheAide.refus('FICHE_INCONNUE', 'Cette fiche n’existe pas.', 'Choisir une fiche de la liste.');
  if (actuelle['statut'] == ficheAideArchivee) return VerdictFicheAide.refus('FICHE_ARCHIVEE', 'Une fiche archivée ne se modifie pas.', 'La restaurer depuis la corbeille, ou en écrire une nouvelle.');
  if (actuelle['statut'] == ficheAideValidee) {
    return VerdictFicheAide.refus('FICHE_VALIDEE', 'Une fiche validée ne se réécrit pas : ce que la Direction a relu est ce que l’assistant cite.', 'La réviser : une fiche nouvelle la remplacera quand elle sera validée à son tour.');
  }
  final contenu = contenuFicheAide({...actuelle, ...saisie});
  final r = controlerContenuFicheAide(contenu, rolesConnus: rolesConnus, ecransConnus: ecransConnus);
  if (r != null) return VerdictFicheAide.refus(r.code, r.motif, r.geste);
  return VerdictFicheAide.ok({...contenu, 'modifieLe': maintenant.toUtc().toIso8601String()});
}

/// RÉVISE une fiche validée : une fiche NOUVELLE, copie du contenu, `proposee`, qui porte `remplace`. La validée reste citée tant que sa remplaçante n'est pas validée.
VerdictFicheAide reviserFicheAide({
  required Map<String, Object?>? source,
  required String id,
  required String auteurId,
  required String auteurNom,
  required DateTime maintenant,
  required Iterable<String> rolesConnus,
  Iterable<String>? ecransConnus,
}) {
  if (source == null) return VerdictFicheAide.refus('FICHE_INCONNUE', 'Cette fiche n’existe pas.', 'Choisir une fiche de la liste.');
  if (source['statut'] != ficheAideValidee) {
    return VerdictFicheAide.refus('REVISION_SANS_OBJET', 'Seule une fiche validée se révise : une fiche non validée se modifie directement.', 'Modifier la fiche.');
  }
  return creerFicheAide(
      saisie: {...source, 'remplace': source['id']}, id: id, auteurId: auteurId, auteurNom: auteurNom, maintenant: maintenant, rolesConnus: rolesConnus, ecransConnus: ecransConnus);
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// VALIDATION
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// VALIDE une fiche. Les gardes, dans l'ordre :
///  1. un poste rattaché n'écrit pas la validation ([estFileul]) : elle est tenue par la mère ;
///  2. la fiche existe, est `proposee` ;
///  3. le rôle détient le geste réservé de validation ([gesteFichesAideValider]) ;
///  4. le validateur est nommé (compte et nom : RG-12) et n'est PAS l'auteur de la fiche (comparaison d'identifiants) ;
///  5. le contenu est encore valide (les rôles cités existent toujours dans la matrice) ;
///  6. une fiche qui engage un professionnel : le rôle détient AUSSI le geste de ce professionnel ET [professionnel] (« validé par ») est non vide ET [professionnelLe] est une date réelle, pas
///     dans le futur.
/// La date de validation est celle du jour ([maintenant]) : elle ne se saisit pas. Rend le patch à écrire sur la fiche (et l'identifiant de la fiche REMPLACÉE, à archiver).
VerdictFicheAide validerFicheAide({
  required Map<String, Object?>? fiche,
  required String role,
  required String validateurId,
  required String validateurNom,
  required DateTime maintenant,
  required DroitsGestes gestes,
  required Iterable<String> rolesConnus,
  String? professionnel,
  String? professionnelLe,
  bool estFileul = false,
}) {
  VerdictFicheAide non(String code, String motif, String geste) => VerdictFicheAide.refus(code, motif, geste);
  if (estFileul) {
    return non('REGLE_SUR_LA_MERE', 'La validation d’une fiche est tenue par la mère : un poste rattaché ne l’écrit pas (la fiche et sa validation y reviennent par la synchronisation).', 'Valider la fiche sur le poste mère.');
  }
  if (fiche == null) return non('FICHE_INCONNUE', 'Cette fiche n’existe pas.', 'Choisir une fiche de la liste.');
  if (fiche['statut'] == ficheAideArchivee) return non('FICHE_ARCHIVEE', 'Une fiche archivée ne se valide pas.', 'Écrire une fiche nouvelle.');
  if (fiche['statut'] == ficheAideValidee) return non('DEJA_VALIDEE', 'Cette fiche est déjà validée.', 'Aucun.');
  if (!gestes.peut(role, gesteFichesAideValider)) {
    return non('GESTE_RESERVE', 'Valider une fiche d’aide est le geste réservé « Valider une fiche d’aide de l’assistant » : votre rôle ne le détient pas.',
        'Demander à la Direction ou à la DAF, ou faire accorder le geste au rôle dans « Rôles et permissions › Gestes réservés ».');
  }
  if (!_plein(validateurId) || !_plein(validateurNom)) return non('VALIDATEUR_ABSENT', 'Aucune action anonyme (RG-12) : la validation porte le nom du validateur.', 'Ouvrir une session nominative.');
  if (!_plein(fiche['auteurId'])) {
    return non('AUTEUR_INCONNU', 'Cette fiche ne porte pas son auteur : on ne peut pas vérifier que le validateur n’est pas aussi l’auteur.', 'La réécrire depuis l’écran (l’auteur est alors enregistré).');
  }
  if ('${fiche['auteurId']}' == validateurId) {
    return non('AUTEUR_NE_VALIDE_PAS', 'Vous êtes l’auteur de cette fiche : on ne valide pas sa propre fiche, une autre personne la relit.', 'Demander à un autre détenteur du geste de valider la fiche.');
  }
  final r = controlerContenuFicheAide(contenuFicheAide(fiche), rolesConnus: rolesConnus);
  if (r != null) return non(r.code, r.motif, r.geste);

  final pro = domaineProFicheAide(_plein(fiche['domainePro']) ? '${fiche['domainePro']}' : null);
  if (pro != null) {
    if (!gestes.peut(role, pro.geste)) {
      return non('PROFESSIONNEL_REQUIS', 'Cette fiche engage un professionnel (${pro.libelle}) : elle ne se valide qu’avec le geste réservé de ce professionnel, que votre rôle ne détient pas.',
          'Faire valider la fiche par le professionnel concerné (ou lui faire accorder le geste dans « Rôles et permissions › Gestes réservés »).');
    }
    if (!_plein(professionnel)) {
      return non('PROFESSIONNEL_ABSENT', 'Le champ « Validé par (professionnel) » est obligatoire pour cette fiche : le nom du professionnel qui a relu la procédure.', 'Saisir le nom du professionnel.');
    }
    final jour = '${professionnelLe ?? ''}'.trim();
    final d = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(jour) ? DateTime.tryParse(jour) : null;
    if (d == null || _iso(d) != jour) return non('DATE_PROFESSIONNEL_INVALIDE', 'La date de la validation du professionnel est obligatoire, au format AAAA-MM-JJ.', 'Saisir la date à laquelle il a validé.');
    if (jour.compareTo(_iso(maintenant)) > 0) return non('DATE_PROFESSIONNEL_FUTURE', 'La date de la validation du professionnel ne peut pas être dans le futur.', 'Corriger la date.');
  }
  return VerdictFicheAide.ok({
    'statut': ficheAideValidee,
    'validateurId': validateurId,
    'validePar': validateurNom.trim(),
    'valideLe': _iso(maintenant),
    if (pro != null) ...{'professionnel': professionnel!.trim(), 'professionnelLe': professionnelLe!.trim()},
  }, archiver: _plein(fiche['remplace']) ? '${fiche['remplace']}' : null);
}

/// ARCHIVE une fiche (RG-14 : jamais une suppression) : le motif et l'auteur sont obligatoires. Rend le patch à écrire (marques d'archivage ; le statut passe à `archive`, l'ancien est gardé).
VerdictFicheAide archiverFicheAide({required Map<String, Object?>? fiche, required String motif, required String auteurNom, required DateTime maintenant}) {
  if (fiche == null) return VerdictFicheAide.refus('FICHE_INCONNUE', 'Cette fiche n’existe pas.', 'Choisir une fiche de la liste.');
  if (fiche['statut'] == ficheAideArchivee) return VerdictFicheAide.refus('DEJA_ARCHIVEE', 'Cette fiche est déjà archivée.', 'Aucun.');
  if (!_plein(motif)) return VerdictFicheAide.refus('MOTIF_ABSENT', 'Archiver une fiche se motive : on relira pourquoi elle n’est plus citée.', 'Saisir le motif.');
  if (!_plein(auteurNom)) return VerdictFicheAide.refus('AUTEUR_ABSENT', 'Aucune action anonyme (RG-12) : l’archivage porte son auteur.', 'Ouvrir une session nominative.');
  return VerdictFicheAide.ok({
    'statutAvantArchivage': fiche['statut'],
    'statut': ficheAideArchivee,
    'archiveLe': maintenant.toUtc().toIso8601String(),
    'archivePar': auteurNom.trim(),
    'motifArchivage': motif.trim(),
  });
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// LA RÈGLE D'ÉCRITURE ENTRE POSTES (mère Dart et banc Node, à l'identique)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le contrôle UNIQUE que la mère refait sur l'écriture d'un poste qui n'est pas elle (fileul, mobile) : la VALIDATION ne s'écrit que sur la mère, et une fiche validée ne se réécrit pas. Rend un
/// refus nommé, ou `null`. [type] : `creer` ou `modifier` ; [champs] : ce que l'opération écrit ; [actuelle] : la fiche telle que la mère la connaît. Miroir exact au banc Node (`mere.js`,
/// `refusFicheAideEcriture`).
({String code, String motif, String geste})? refusEcritureFicheAide(String type, Map<String, Object?> champs, {Map<String, Object?>? actuelle}) {
  bool change(String k) => champs.containsKey(k) && champs[k] != null && '${champs[k]}' != '${actuelle?[k]}';
  final validation = ficheAideChampsValidation.any(change) || (champs['statut'] == ficheAideValidee && actuelle?['statut'] != ficheAideValidee);
  if (validation) {
    return (
      code: 'validation_reservee_mere',
      motif: 'La validation d’une fiche d’aide ne s’écrit que sur le poste mère : elle seule vérifie le geste réservé et que l’auteur n’est pas le validateur.',
      geste: 'Valider la fiche sur le poste mère ; elle revient ici par la synchronisation.'
    );
  }
  if (type == 'creer' && champs['statut'] != null && champs['statut'] != ficheAideProposee) {
    return (code: 'validation_reservee_mere', motif: 'Une fiche naît « proposée » : seule la mère la valide.', geste: 'Écrire la fiche, puis la faire valider sur le poste mère.');
  }
  if (actuelle?['statut'] == ficheAideValidee && ficheAideChampsContenu.any(change)) {
    return (
      code: 'fiche_validee',
      motif: 'Une fiche validée ne se réécrit pas : ce que la Direction a relu est ce que l’assistant cite.',
      geste: 'La réviser : une fiche nouvelle la remplacera quand elle sera validée à son tour.'
    );
  }
  return null;
}
