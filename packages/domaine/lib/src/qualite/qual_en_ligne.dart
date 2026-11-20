import 'qual_enquetes.dart';

/// SATISFACTION EN LIGNE (décision de la Direction du 16/11/2026, section 8) : un patient répond au questionnaire sur le RELAIS, depuis chez lui, par un
/// lien ou un QR ; sa réponse est chiffrée dans son navigateur avec la clé PUBLIQUE de la clinique (le relais ne la lit pas) ; la MÈRE la relève, la
/// déchiffre et l'enregistre comme une réponse d'enquête (canal « Lien public »), qui redescend aux fileuls pour les statistiques.
///
/// Ce fichier porte les règles PURES (aucun chiffrement ici : il vit dans `packages/sync_dart/lib/src/satisfaction_en_ligne.dart`) :
///  - ce que la mère PUBLIE au relais pour un lien : le modèle de questions rendu par LE générateur (`qualChampsDepuisModele`, le même que la saisie au
///    guichet et la page publique du poste : une question ajoutée au modèle paraît sur le lien), jamais l'identifiant de l'enquête ;
///  - ce que la mère RETIENT d'une réponse déchiffrée : seulement les codes des questions du modèle, chaque valeur contrôlée contre son type.
///
/// En ligne, le recueil est TOUJOURS anonyme : ni nom, ni numéro de dossier (décision du 16/11/2026). Un lien nominatif ne se publie pas.

/// Le canal de recueil d'un lien publié AU RELAIS (champ `usage` du lien), distinct des usages internes (salle, tablette, réseau local).
const qualUsageRelais = 'relais';

/// Longueur maximale d'une réponse libre retenue (le relais la borne déjà côté navigateur).
const qualLongueurTexteEnLigne = 1000;

/// Un lien est-il destiné au relais ?
bool qualLienEnLigne(Map<String, Object?>? j) => j != null && j['enLigne'] == true;

/// La fiche d'un lien EN LIGNE : celle du partage (`qualNouveauJeton`), toujours anonyme, marquée `enLigne`. La mère la publie au relais au tour suivant.
QualFiche qualNouveauJetonEnLigne(
        {required QualFiche enquete,
        required String jeton,
        required String expireLe,
        String? note,
        required DateTime aujourdhui,
        required String ouvertPar}) =>
    {
      ...qualNouveauJeton(
          enquete: enquete,
          jeton: jeton,
          anonyme: 'oui',
          usage: qualUsageRelais,
          expireLe: expireLe,
          note: note,
          aujourdhui: aujourdhui,
          ouvertPar: ouvertPar),
      'enLigne': true,
    };

/// Refus nommé d'une publication : `null` si le lien peut partir au relais.
({String code, String motif})? qualRefusPublication(QualFiche? jeton, QualFiche? enquete) {
  if (jeton == null || !qualLienEnLigne(jeton)) return (code: 'LIEN_NON_EN_LIGNE', motif: 'Ce lien n’est pas destiné au relais.');
  if (jeton['anonyme'] != true) {
    return (code: 'LIEN_NOMINATIF', motif: 'Un lien en ligne est toujours anonyme : aucun nom ni numéro de dossier n’est demandé.');
  }
  if (enquete == null || enquete['statut'] == 'archive') return (code: 'ENQUETE_INCONNUE', motif: 'L’enquête de ce lien n’existe plus.');
  final questions = enquete['questions'] as List? ?? const [];
  if (questions.isEmpty) return (code: 'ENQUETE_SANS_QUESTION', motif: 'Un questionnaire sans question ne recueille rien.');
  for (final q in questions.cast<Map>()) {
    if (q['type'] == 'choix' && (q['options'] as List? ?? const []).isEmpty) {
      return (code: 'CHOIX_SANS_OPTION', motif: 'La question « ${q['libelle']} » est à choix mais n’a pas de choix.');
    }
  }
  return null;
}

/// Ce que la mère PUBLIE au relais pour un lien. `jetonHash` : sha256 du jeton (le relais ne garde pas le jeton en clair) ; `ref` : l'identifiant de la
/// fiche du lien (rendu à la relève) ; jamais l'identifiant de l'enquête. Les champs sont ceux du GÉNÉRATEUR, en pleine largeur (on répond sur un
/// téléphone).
Map<String, Object?> qualPublicationEnLigne(
        {required QualFiche jeton,
        required QualFiche enquete,
        required String jetonHash,
        required String clinique,
        required String clePublique,
        required String kid}) =>
    {
      'jeton_hash': jetonHash,
      'ref': '${jeton['id']}',
      'expire_le': '${jeton['expireLe']}',
      'clinique': clinique,
      'titre': _borne('${enquete['titre'] ?? ''}', 120),
      'description': _borne('${enquete['description'] ?? ''}', 500),
      'champs': [
        for (final c in qualChampsDepuisModele(enquete['questions'], pleineLargeur: true))
          {'nom': c.nom, 'libelle': _borne(c.libelle, 200), 'type': c.type, 'requis': c.requis, 'options': c.options, 'lignes': c.lignes}
      ],
      'cle_publique': clePublique,
      'kid': kid,
    };

String _borne(String s, int n) => s.length <= n ? s : s.substring(0, n);

/// La réponse que la mère ENREGISTRE après déchiffrement, ou `null` si rien n'en est retenu. Seuls les codes des questions du modèle EN VIGUEUR comptent
/// (une question retirée depuis n'est pas ressuscitée) ; une note hors de 1 à 5 ou un choix hors liste est écarté ; un texte est borné. Le jour de
/// réception vient du relais (le navigateur ne date rien : son horloge n'engage personne). Anonyme : ni nom, ni lien vers un dossier.
QualFiche? qualReponseEnLigne(
    {required QualFiche enquete, required QualFiche jeton, required Map<String, Object?> reponses, required String recueLe}) {
  final jour = DateTime.tryParse(recueLe);
  if (jour == null) return null;
  final retenues = <String, Object?>{};
  for (final q in (enquete['questions'] as List? ?? const []).cast<Map>()) {
    final code = '${q['code']}';
    final brut = reponses[code];
    if (brut == null) continue;
    final v = '$brut'.trim();
    if (v.isEmpty) continue;
    switch (q['type']) {
      case 'note':
        if (const ['1', '2', '3', '4', '5'].contains(v)) retenues[code] = v;
      case 'choix':
        if ((q['options'] as List? ?? const []).map((o) => '$o').contains(v)) retenues[code] = v;
      default:
        retenues[code] = v.length <= qualLongueurTexteEnLigne ? v : v.substring(0, qualLongueurTexteEnLigne);
    }
  }
  if (retenues.isEmpty) return null;
  return qualReponse(enquete, retenues,
      aujourdhui: jour, canal: qualCanalPublic, saisiPar: qualSaisiPar(anonyme: true), jetonId: jeton['id']);
}

/// L'état de publication d'un lien en ligne, tel que la mère l'a écrit sur la fiche : (libellé, ton).
({String libelle, String ton}) qualEtatPublication(QualFiche j) {
  if (!qualLienEnLigne(j)) return (libelle: 'Lien interne', ton: 'neutral');
  final erreur = '${j['erreurRelais'] ?? ''}';
  if (erreur.isNotEmpty) return (libelle: 'Refusé par le relais : $erreur', ton: 'danger');
  if ('${j['relaisRevoqueLe'] ?? ''}'.isNotEmpty) return (libelle: 'Retiré du relais', ton: 'neutral');
  if ('${j['lienPublic'] ?? ''}'.isNotEmpty) return (libelle: 'Publié sur le relais', ton: 'success');
  return (libelle: 'En attente du poste mère', ton: 'warning');
}
