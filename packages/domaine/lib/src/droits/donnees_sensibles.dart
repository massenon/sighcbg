/// LES DONNÉES SENSIBLES DU PATIENT : un droit PAR CATÉGORIE, porté par la matrice (Direction, 11/11/2026).
///
/// « Toutes les informations sensibles du patient ne doivent pas être visibles pour certains utilisateurs système lors de la consultation » — et « pas de
/// masquage d'interface en dur ». Deux conséquences :
///
///  * AUCUN nom de rôle ne décide de ce qu'on voit. Le droit d'un rôle sur une catégorie est UNE clé de sa fiche `rbac` (`donneesSensibles.<catégorie>`), décidée
///    comme n'importe quel droit (`decisionsDroits`, `m14-roles`) : modifiable à tout moment, diffusée aux postes appairés, jamais figée.
///  * SANS décision, le défaut SUIT LA MATRICE : une catégorie déclare l'écran dont elle dépend (`ecranRef`) et un rôle la voit s'il VOIT cet écran. Les
///    catégories de la Zone 1 (accueil) suivent le répertoire `m1-patients`, celles de la Zone 2 (consultation) le dossier de consultation, la maternité le
///    cahier obstétrical : la répartition d'aujourd'hui, sans qu'un rôle soit nommé. Une catégorie sans écran de référence reste ouverte tant que rien n'est
///    décidé (les résultats d'analyses gardent leurs propres habilitations métier, `peutVoirResultat`, qui s'appliquent EN PLUS).
///
/// Un champ masqué le DIT : [mentionReservee] (« Information réservée — droit requis : <catégorie> ») plutôt qu'un champ vide, qui se lirait comme une donnée
/// absente. Pur et sans magasin : le poste y branche ses fiches `rbac` et sa matrice EN FORCE, le téléphone les siennes.
library;

import 'a_chaud.dart' show surchargesParRole;

/// Une catégorie de données sensibles : son code (clé du droit), son libellé, ce qu'elle couvre, et l'écran dont elle suit le droit par défaut.
class CategorieSensible {
  const CategorieSensible({required this.code, required this.libelle, required this.zone, required this.champs, this.ecranRef, this.couvre = ''});

  /// La clé du droit : `donneesSensibles.<code>` dans la fiche du rôle, `sensible.<code>` dans une décision.
  final String code;
  final String libelle;

  /// 1 = accueil (Zone 1), 2 = consultation (Zone 2), 0 = transverse.
  final int zone;

  /// Les champs d'un enregistrement patient que la catégorie couvre.
  final List<String> champs;

  /// L'écran dont le droit de VOIR donne le défaut ; `null` : ouvert tant qu'aucune décision n'est prise.
  final String? ecranRef;

  /// Ce que la catégorie couvre HORS champs du patient (rubriques de la fiche, collections), pour l'écran d'administration.
  final String couvre;
}

/// Les catégories de données sensibles du patient. Le référentiel est une donnée du domaine : le code l'interroge, il ne recopie jamais ses noms.
const List<CategorieSensible> categoriesSensibles = [
  CategorieSensible(
      code: 'identite_detaillee',
      libelle: 'Identité civile détaillée',
      zone: 1,
      champs: ['dateNaissance', 'age', 'naissanceConnue', 'pieceIdentite', 'numeroPiece'],
      ecranRef: 'm1-patients',
      couvre: 'Date de naissance, âge, pièce d’identité. Le code, le nom, le prénom et le sexe restent lisibles : sans eux, on ne retrouve pas un dossier.'),
  CategorieSensible(
      code: 'coordonnees',
      libelle: 'Coordonnées (téléphone, adresse, quartier)',
      zone: 1,
      champs: ['telephone', 'quartier', 'adresse'],
      ecranRef: 'm1-patients',
      couvre: 'Téléphone, quartier, adresse.'),
  CategorieSensible(
      code: 'personne_a_prevenir',
      libelle: 'Personne à prévenir',
      zone: 1,
      champs: ['personneAPrevenir'],
      ecranRef: 'm1-patients',
      couvre: 'Nom et coordonnées de la personne à prévenir.'),
  CategorieSensible(
      code: 'couverture_assurance',
      libelle: 'Couverture d’assurance',
      zone: 1,
      champs: ['assureur', 'assureurNom', 'souscripteur', 'numeroPolice', 'tauxPriseEnCharge', 'carteExpiration'],
      ecranRef: 'm1-patients',
      couvre: 'Compagnie, souscripteur, n° de police, taux, validité de la carte (onglet Assurance, bandeau de couverture).'),
  CategorieSensible(
      code: 'allergies_traitements',
      libelle: 'Allergies et traitement en cours',
      zone: 1,
      champs: ['allergies', 'traitementEnCours'],
      ecranRef: 'm1-patients',
      couvre: 'Allergies déclarées, traitement en cours. Alerte de sécurité : par défaut ouverte à tout profil qui ouvre le répertoire.'),
  CategorieSensible(
      code: 'antecedents',
      libelle: 'Antécédents',
      zone: 2,
      champs: ['antecedents', 'antecedentsAutres'],
      ecranRef: 'm2-dossiers-consultation',
      couvre: 'Antécédents médicaux, chirurgicaux et gynéco-obstétricaux (fiche patient, dossier de consultation).'),
  CategorieSensible(
      code: 'groupe_serologies',
      libelle: 'Groupe sanguin et sérologies',
      zone: 2,
      champs: ['groupeSanguin', 'serologies', 'serologieVih', 'electrophoreseHb', 'depistage'],
      ecranRef: 'm2-dossiers-consultation',
      couvre: 'Groupe sanguin, sérologies (VIH…), électrophorèse, dépistages.'),
  CategorieSensible(
      code: 'diagnostic_pathologie',
      libelle: 'Diagnostic et pathologie',
      zone: 2,
      champs: ['diagnostic', 'pathologie', 'pathologieLibelle'],
      ecranRef: 'm2-dossiers-consultation',
      couvre: 'Diagnostic rédigé et pathologie codée des consultations.'),
  CategorieSensible(
      code: 'notes_consultation',
      libelle: 'Notes et dossier de consultation',
      zone: 2,
      champs: ['motif', 'motifVenue', 'histoire', 'examensPhysiques', 'notes', 'observations'],
      ecranRef: 'm2-dossiers-consultation',
      couvre: 'Motif, histoire de la maladie, examen IPPOA, dossier de consultation, ordonnances, soins, consultations à domicile.'),
  CategorieSensible(
      code: 'hospitalisation_soins',
      libelle: 'Hospitalisation et surveillance',
      zone: 2,
      champs: [],
      ecranRef: 'm3-admissions',
      couvre: 'Admissions, observations, feuilles de température, sorties.'),
  CategorieSensible(
      code: 'resultats_analyses',
      libelle: 'Résultats d’analyses et comptes rendus d’imagerie',
      zone: 2,
      champs: ['resultat', 'resultats'],
      couvre:
          'Résultats d’analyses et comptes rendus d’imagerie. S’ajoute aux habilitations métier (fonction, secteur, validation biologique), qui restent en force.'),
  CategorieSensible(
      code: 'donnees_obstetricales',
      libelle: 'Données obstétricales',
      zone: 2,
      champs: ['grossesse', 'dateDernieresRegles', 'termeSA'],
      ecranRef: 'm4-dossier-obstetrical',
      couvre: 'Suivi de grossesse, accouchements, naissances (onglet Maternité).'),
];

CategorieSensible? categorieSensible(String code) {
  for (final c in categoriesSensibles) {
    if (c.code == code) return c;
  }
  return null;
}

/// La catégorie qui couvre un champ de l'enregistrement patient, ou `null` (champ d'identification minimale : code, nom, prénom, sexe…).
CategorieSensible? categorieDuChamp(String champ) {
  for (final c in categoriesSensibles) {
    if (c.champs.contains(champ)) return c;
  }
  return null;
}

/// La clé de la fiche `rbac` / de la décision.
String drCleSensible(String code) => 'sensible.$code';

/// Le texte d'un champ masqué. UNE phrase pour tout le logiciel : l'écran, le papier et le téléphone disent la même chose.
String mentionReservee(String code) => 'Information réservée — droit requis : ${categorieSensible(code)?.libelle ?? code}';

/// Les droits sur les catégories sensibles, évalués À CHAQUE appel depuis les fiches et la matrice EN FORCE : rien n'est mis en cache, une décision prise à
/// l'instant s'applique à la lecture suivante.
class DroitsSensibles {
  /// [fiches] : la collection `rbac`. [peutVoirEcran] : `(rôle, écran) → bool` de la matrice en force ; `null` = matrice non branchée (tout écran réputé
  /// ouvert : un test nu, un écran hors coque).
  DroitsSensibles({required Iterable<Map<String, Object?>> fiches, bool Function(String role, String ecran)? peutVoirEcran})
      : _sur = surchargesParRole(fiches),
        _voir = peutVoirEcran;

  final Map<String, Map<String, Object?>> _sur;
  final bool Function(String role, String ecran)? _voir;

  /// La décision EXPLICITE de la clinique pour ce rôle et cette catégorie (`null` : aucune, le défaut s'applique).
  bool? decision(String role, String code) {
    final m = _sur[role]?['donneesSensibles'];
    if (m is! Map) return null;
    final v = m[code];
    return v is bool ? v : null;
  }

  /// Le défaut : le droit de voir l'écran de référence. Catégorie inconnue : refusé (ce qu'on ne connaît pas n'ouvre rien).
  bool defaut(String role, String code) {
    final c = categorieSensible(code);
    if (c == null) return false;
    final ref = c.ecranRef;
    if (ref == null) return true;
    final f = _voir;
    return f == null ? true : f(role, ref);
  }

  /// Le rôle peut-il lire cette catégorie ? Une fiche archivée ne décide rien, un rôle archivé (la matrice ne lui voit aucun écran) retombe sur son défaut.
  bool peut(String role, String code) => decision(role, code) ?? defaut(role, code);

  /// `defaut` ou `decide` : d'où vient le droit (écran d'administration).
  String origine(String role, String code) => decision(role, code) == null ? 'defaut' : 'decide';

  /// Les catégories qu'un rôle NE peut PAS lire.
  List<CategorieSensible> refusees(String role) => [
        for (final c in categoriesSensibles)
          if (!peut(role, c.code)) c
      ];

  /// Une copie de [fiche] sans les champs des catégories refusées. Les champs d'identification minimale restent. [masques] reçoit les catégories retirées.
  Map<String, Object?> masquer(String role, Map<String, Object?> fiche, {Set<String>? masques}) {
    final out = <String, Object?>{};
    fiche.forEach((k, v) {
      final c = categorieDuChamp(k);
      if (c != null && !peut(role, c.code)) {
        masques?.add(c.code);
        return;
      }
      out[k] = v;
    });
    return out;
  }
}
