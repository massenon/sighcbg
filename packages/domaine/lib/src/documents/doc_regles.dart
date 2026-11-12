/// LES DOCUMENTS NUMÉRISÉS (courriers M13, dossier patient M1) : les règles, en Dart pur, exécutées au poste, à la mère et dans les tests.
///
/// Portées de la maquette de la clinique sœur (lot DOCS-1 D0 à D4) vers l'architecture Baguidi, avec les décisions de la Direction de Baguidi :
///  * le fichier ne vit JAMAIS dans le magasin (ni en base64) ni sur le relais : il est rangé dans un DOSSIER du poste MÈRE, sous un NOM NORMALISÉ strict ;
///    la fiche ne garde que les métadonnées (empreinte SHA-256, nom d'origine, nom normalisé, type, taille, pages, version) ;
///  * RG-14 : un scan ne se supprime pas. Le remplacer garde l'ancien en version ; le retirer l'archive, annulable ;
///  * la case « Numérisé » est DÉRIVÉE de la présence d'un fichier, jamais saisie ;
///  * le droit de lire un document patient suit les CATÉGORIES SENSIBLES de la matrice (`donnees_sensibles.dart`), jamais un nom de rôle ;
///  * tout refus se nomme : un code, un motif, le geste de correction.
library;

import 'dart:convert';

import '../format/recherche.dart' show normaliser;
import 'doc_sha256.dart';

const String docFamilleCourrier = 'courrier';
const String docFamillePatient = 'patient';

/// Un refus nommé : code stable, motif lisible, geste de correction (règle 4 du projet).
class DocErreur implements Exception {
  const DocErreur(this.code, this.motif, this.geste);
  final String code;
  final String motif;
  final String geste;
  @override
  String toString() => '$code — $motif $geste';
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Formats et taille
// ---------------------------------------------------------------------------------------------------------------------------------------------

class DocFormat {
  const DocFormat(this.id, this.libelle, this.mime, this.extensions, this.familles);
  final String id;
  final String libelle;
  final String mime;

  /// La première est l'extension CANONIQUE du nom normalisé (`jpg`, jamais `jpeg`).
  final List<String> extensions;
  final List<String> familles;
  String get extension => extensions.first;
}

/// PDF, JPEG, PNG pour les deux familles. WEBP reste accepté au dossier patient seulement : le poste Baguidi le recevait déjà avant ce lot.
const List<DocFormat> docFormats = [
  DocFormat('pdf', 'PDF', 'application/pdf', ['pdf'], [docFamilleCourrier, docFamillePatient]),
  DocFormat('jpeg', 'JPEG', 'image/jpeg', ['jpg', 'jpeg'], [docFamilleCourrier, docFamillePatient]),
  DocFormat('png', 'PNG', 'image/png', ['png'], [docFamilleCourrier, docFamillePatient]),
  DocFormat('webp', 'WEBP', 'image/webp', ['webp'], [docFamillePatient]),
];

/// Taille maximale par fichier : défaut 10 Mo, « à valider » par la Direction ; réglable en base entre un plancher et un plafond dur.
const int docTailleDefaut = 10 * 1024 * 1024;
const int docTaillePlancher = 100 * 1024;
const int docTaillePlafond = 64 * 1024 * 1024;

/// La taille maximale en force : le réglage de la clinique, ramené dans les bornes, sinon le défaut.
int docTailleMax(Object? reglee) {
  final n = reglee is num ? reglee.toInt() : int.tryParse('${reglee ?? ''}');
  if (n == null || n <= 0) return docTailleDefaut;
  return n.clamp(docTaillePlancher, docTaillePlafond);
}

/// Contrôle d'un RÉGLAGE de taille maximale : borné, motif obligatoire (il se journalise). `null` = accepté.
DocErreur? docControlerReglageTaille(Object? octets, String motif) {
  final n = octets is num ? octets.toInt() : int.tryParse('${octets ?? ''}');
  if (n == null) return const DocErreur('TAILLE_ILLISIBLE', 'La taille maximale n’est pas un nombre d’octets.', 'Saisir un nombre.');
  if (n < docTaillePlancher || n > docTaillePlafond) {
    return DocErreur('TAILLE_HORS_BORNES', 'La taille maximale doit rester entre ${docPoids(docTaillePlancher)} et ${docPoids(docTaillePlafond)}.', 'Saisir une valeur dans ces bornes.');
  }
  if (motif.trim().isEmpty) return const DocErreur('MOTIF_REQUIS', 'Le motif du changement est obligatoire (journal RG-12).', 'Renseigner le motif.');
  return null;
}

/// « 2 Ko », « 3,0 Mo » : le poids lisible (virgule française).
String docPoids(int octets) {
  if (octets <= 0) return '—';
  if (octets >= 1024 * 1024) return '${(octets / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} Mo';
  return '${(octets / 1024).ceil()} Ko';
}

/// Le format lu sur les OCTETS (jamais sur le nom : un fichier renommé ne change pas de nature), ou `null`.
DocFormat? docFormatDesOctets(List<int> o) {
  bool debut(List<int> m, [int depuis = 0]) {
    if (o.length < depuis + m.length) return false;
    for (var i = 0; i < m.length; i++) {
      if (o[depuis + i] != m[i]) return false;
    }
    return true;
  }

  String id;
  if (debut([0x25, 0x50, 0x44, 0x46, 0x2d])) {
    id = 'pdf';
  } else if (debut([0xff, 0xd8, 0xff])) {
    id = 'jpeg';
  } else if (debut([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    id = 'png';
  } else if (debut([0x52, 0x49, 0x46, 0x46]) && debut([0x57, 0x45, 0x42, 0x50], 8)) {
    id = 'webp';
  } else {
    return null;
  }
  return docFormats.firstWhere((f) => f.id == id);
}

/// L'extension d'un nom de fichier, en minuscules (sans le point).
String docExtensionDe(String nom) {
  final m = RegExp(r'\.([A-Za-z0-9]+)$').firstMatch(nom.trim());
  return m == null ? '' : m.group(1)!.toLowerCase();
}

/// Contrôle d'un dépôt AVANT toute écriture : fichier non vide, format reconnu sur les octets ET admis pour la famille, extension cohérente, taille.
/// Rend le refus nommé, ou `null`.
DocErreur? docControlerDepot({required List<int> octets, required String nomOrigine, required String famille, Object? tailleMaxReglee}) {
  if (octets.isEmpty) return const DocErreur('FICHIER_VIDE', 'Le fichier est vide.', 'Numériser de nouveau, puis choisir le fichier.');
  final f = docFormatDesOctets(octets);
  final admis = docFormats.where((x) => x.familles.contains(famille)).map((x) => x.libelle).join(', ');
  if (f == null || !f.familles.contains(famille)) {
    return DocErreur('FORMAT_REFUSE', 'Format non admis : seuls $admis sont acceptés.', 'Enregistrer le scan en PDF, JPEG ou PNG.');
  }
  final ext = docExtensionDe(nomOrigine);
  if (ext.isNotEmpty && !f.extensions.contains(ext)) {
    return DocErreur('EXTENSION_INCOHERENTE', 'Le nom du fichier dit « .$ext » mais son contenu est un ${f.libelle}.', 'Renommer le fichier avec la bonne extension, ou le ré-enregistrer.');
  }
  final max = docTailleMax(tailleMaxReglee);
  if (octets.length > max) {
    return DocErreur('TAILLE_DEPASSEE', 'Le fichier pèse ${docPoids(octets.length)} ; la taille maximale réglée est ${docPoids(max)}.', 'Numériser en résolution plus basse, ou faire relever la taille maximale (Paramètres système).');
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Noms normalisés
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Une chaîne sans accent ni espace pour un nom de fichier : minuscules, chiffres et tirets.
String docSlug(Object? t) => normaliser(t).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

String _date10(Object? d) {
  final s = '${d ?? ''}';
  return RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s) ? s.substring(0, 10) : '0000-00-00';
}

String _suffixeVersion(int version) => version > 1 ? '_v$version' : '';

/// LE NOM NORMALISÉ d'une pièce (nom de rangement ET de téléchargement), RECALCULÉ de la fiche, jamais saisi : la RÉFÉRENCE de la fiche ne change pas.
///  * courrier : `AAAA-MM-JJ_ARR_0042.pdf` (date de la fiche, sens, rang de la référence `ARR-2026-0042`) ;
///  * dossier patient : `AAAA-MM-JJ_CBG-12-26_ordonnance_007.pdf` (date du document, code patient sans barre, type sans accent, rang de la référence `GED-00007`).
/// La première version porte le nom nu ; un remplacement ajoute `_v2`, `_v3`… : l'ancienne version reste sur disque sous SON nom (rien ne s'écrase).
String docNomNormalise({required String famille, required Map<String, Object?> fiche, required String ext, int version = 1}) {
  final e = ext.toLowerCase().replaceAll('.', '');
  final date = _date10(fiche['date']);
  final v = _suffixeVersion(version);
  if (famille == docFamilleCourrier) {
    final m = RegExp(r'^(ARR|DEP)-\d{4}-(\d+)$').firstMatch('${fiche['reference'] ?? ''}');
    final sens = m?.group(1) ?? (fiche['sens'] == 'depart' ? 'DEP' : 'ARR');
    final rang = (m?.group(2) ?? '0000').padLeft(4, '0');
    return '${date}_${sens}_$rang$v.$e';
  }
  final n = RegExp(r'(\d+)$').firstMatch('${fiche['reference'] ?? ''}');
  final rang = (n == null ? '0' : '${int.parse(n.group(1)!)}').padLeft(3, '0');
  final code = '${fiche['code'] ?? 'SANS-DOSSIER'}'.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  final type = docSlug(fiche['type']);
  return '${date}_${code.isEmpty ? 'SANS-DOSSIER' : code}_${type.isEmpty ? 'document' : type}_$rang$v.$e';
}

final RegExp _nomCourrier = RegExp(r'^\d{4}-\d{2}-\d{2}_(ARR|DEP)_\d{4,}(_v\d{1,3})?\.(pdf|jpg|png)$');
final RegExp _nomPatient = RegExp(r'^\d{4}-\d{2}-\d{2}_[A-Za-z0-9]+(-[A-Za-z0-9]+)*_[a-z0-9]+(-[a-z0-9]+)*_\d{3,}(_v\d{1,3})?\.(pdf|jpg|png|webp)$');

/// Le nom est-il STRICTEMENT normalisé ? La mère n'écrit jamais un fichier sous un autre nom : aucun séparateur de chemin, aucun `..`, aucun nom libre.
bool docNomNormaliseValide(String nom) => nom.length <= 120 && (_nomCourrier.hasMatch(nom) || _nomPatient.hasMatch(nom));

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Types de document du patient et droits par catégorie sensible
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les catégories sensibles (clés de `categoriesSensibles`) qu'il faut pouvoir lire pour lire UN TYPE de document. TOUTES sont exigées. Un type inconnu se
/// range au plus strict. Les résultats d'analyses et l'imagerie exigent aussi `notes_consultation` : la catégorie `resultats_analyses` seule reste ouverte par
/// défaut (ses habilitations métier s'ajoutent), ce qui laisserait lire un scan de compte rendu à tout profil qui voit l'écran. La facture, qui liste des actes,
/// est rangée au clinique par prudence (comme dans la maquette).
const Map<String, List<String>> docCategoriesDesTypes = {
  'Ordonnance': ['notes_consultation'],
  'Résultat de laboratoire': ['resultats_analyses', 'notes_consultation'],
  'Compte rendu médical': ['diagnostic_pathologie', 'notes_consultation'],
  'Consentement éclairé': ['notes_consultation'],
  'Imagerie / Échographie': ['resultats_analyses', 'notes_consultation'],
  'Bulletin d’hospitalisation': ['hospitalisation_soins'],
  'Facture': ['notes_consultation'],
  'Pièce d’identité': ['identite_detaillee'],
  'Carte d’assurance': ['couverture_assurance'],
  'Certificat médical': ['notes_consultation'],
};

const List<String> docCategoriesParDefaut = ['notes_consultation', 'diagnostic_pathologie'];

List<String> docCategoriesDuType(Object? type) => docCategoriesDesTypes['$type'] ?? docCategoriesParDefaut;

/// Zone du type : 1 = accueil (pièce d'identité, carte d'assurance), 2 = clinique (tout le reste, et tout type inconnu).
int docZoneDuType(Object? type) => docCategoriesDuType(type).every((c) => c == 'identite_detaillee' || c == 'couverture_assurance') ? 1 : 2;

/// Le profil peut-il lire un document de ce [type] ? [peutCategorie] est `AccesSensible.peut` (la matrice) : AUCUN nom de rôle ici.
bool docPeutLire(bool Function(String categorie) peutCategorie, Object? type) => docCategoriesDuType(type).every(peutCategorie);

/// Les catégories qui MANQUENT à un profil pour lire ce type (pour la mention « Information réservée — droit requis »).
List<String> docCategoriesManquantes(bool Function(String categorie) peutCategorie, Object? type) => [for (final c in docCategoriesDuType(type)) if (!peutCategorie(c)) c];

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La pièce sur la fiche : métadonnées, versions, retrait
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Le champ `scan` d'une fiche (courrier ou document patient) : UN objet, jamais un fichier. `scansAnterieurs` garde les versions remplacées ou retirées.
Map<String, Object?> docMetaScan({
  required String sha256,
  required String nomOrigine,
  required String nomNormalise,
  required String mime,
  required int taille,
  required int version,
  required String deposePar,
  required String deposeLe,
  int? pages,
  bool texteIndexe = false,
}) =>
    {
      'sha256': sha256,
      'nom': nomOrigine,
      'nomNormalise': nomNormalise,
      'mime': mime,
      'taille': taille,
      'pages': pages,
      'texteIndexe': texteIndexe,
      'version': version,
      'deposePar': deposePar,
      'deposeLe': deposeLe,
    };

Map<String, Object?>? docScan(Map<String, Object?> fiche) {
  final s = fiche['scan'];
  return s is Map && '${s['sha256'] ?? ''}'.isNotEmpty ? s.cast<String, Object?>() : null;
}

List<Map<String, Object?>> docScansAnterieurs(Map<String, Object?> fiche) {
  final l = fiche['scansAnterieurs'];
  return l is List ? [for (final x in l) if (x is Map) x.cast<String, Object?>()] : const [];
}

/// « Numérisé » : DÉRIVÉ de la présence d'un fichier. La case n'existe plus à la saisie.
bool docNumerise(Map<String, Object?> fiche) => docScan(fiche) != null;

/// La version que prendra le prochain dépôt : on compte TOUT ce qui a été posé sur la fiche, retiré compris — un numéro de version ne se réutilise pas.
int docProchaineVersion(Map<String, Object?> fiche) => docScansAnterieurs(fiche).length + (docScan(fiche) == null ? 0 : 1) + 1;

/// Le résultat du contrôle de doublon : même fiche = refus nommé ; autre fiche = avertissement nommé (rattacher quand même est un choix de l'agent).
class DocDoublon {
  const DocDoublon({this.memeFiche, this.ailleurs});
  final Map<String, Object?>? memeFiche;
  final Map<String, Object?>? ailleurs;
  bool get refus => memeFiche != null;
  bool get avertissement => ailleurs != null;
}

/// [fiches] : les fiches de la MÊME famille (la portée de « même fiche » est la fiche elle-même ; au dossier patient, le dossier du patient : [memePortee]).
DocDoublon docControlerDoublon({required String sha256, required Map<String, Object?> fiche, required Iterable<Map<String, Object?>> fiches, bool Function(Map<String, Object?> autre)? memePortee}) {
  Map<String, Object?>? meme, ailleurs;
  for (final f in fiches) {
    if (f['statut'] == 'archive') continue;
    if (docScan(f)?['sha256'] != sha256) continue;
    final dedans = f['id'] == fiche['id'] || (memePortee?.call(f) ?? false);
    if (dedans) {
      meme ??= f;
    } else {
      ailleurs ??= f;
    }
  }
  return DocDoublon(memeFiche: meme, ailleurs: ailleurs);
}

DocErreur docRefusDoublon(Map<String, Object?> existante) => DocErreur('DOUBLON_MEME_FICHE',
    'Ce fichier (empreinte ${docEmpreinteAbregee('${docScan(existante)?['sha256']}')}) est déjà rattaché à ${existante['reference'] ?? 'cette fiche'}.', 'Choisir un autre fichier, ou ouvrir la pièce existante.');

/// L'empreinte abrégée (huit caractères) imprimée sur les fiches.
String docEmpreinteAbregee(String sha) => sha.length <= 8 ? sha : sha.substring(0, 8);

/// Le patch d'un DÉPÔT sur une fiche : première pièce, ou REMPLACEMENT (l'ancienne passe aux versions antérieures, motif « Remplacée », rien n'est perdu).
Map<String, Object?> docPatchDepot(Map<String, Object?> fiche, Map<String, Object?> nouveau, {required String par, required String le}) {
  final ancien = docScan(fiche);
  if (ancien == null) return {'scan': nouveau};
  return {
    'scan': nouveau,
    'scansAnterieurs': [
      ...docScansAnterieurs(fiche),
      {...ancien, 'retireLe': le, 'retirePar': par, 'motifRetrait': 'Remplacée par la version ${nouveau['version']}'}
    ],
  };
}

/// Le patch d'un RETRAIT : motif obligatoire, la pièce passe aux versions antérieures, le fichier RESTE sur disque (RG-14). L'annulation du magasin rend l'état d'avant.
Map<String, Object?> docPatchRetrait(Map<String, Object?> fiche, {required String par, required String le, required String motif}) {
  final ancien = docScan(fiche);
  if (ancien == null) throw const DocErreur('SANS_PIECE', 'Cette fiche ne porte aucun fichier.', 'Déposer un scan d’abord.');
  if (motif.trim().isEmpty) throw const DocErreur('MOTIF_REQUIS', 'Le motif du retrait est obligatoire.', 'Renseigner le motif.');
  return {
    'scan': null,
    'scansAnterieurs': [
      ...docScansAnterieurs(fiche),
      {...ancien, 'retireLe': le, 'retirePar': par, 'motifRetrait': motif.trim()}
    ],
  };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Stockage abstrait et migration du base64
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Ce que la règle attend d'un dossier de fichiers : écrire sous un nom normalisé, relire par empreinte. L'implémentation est celle de la mère (disque) ou
/// celle d'un fileul (par le canal de synchronisation chiffré).
abstract class DocStockage {
  /// Range les octets sous [nomNormalise]. L'implémentation REFUSE si l'empreinte recalculée diffère de [sha256] ou si le nom n'est pas normalisé.
  Future<void> deposer({required List<int> octets, required String sha256, required String nomNormalise});

  /// Relit les octets rangés pour cette empreinte (vérifiés), ou `null` s'ils manquent.
  Future<List<int>?> lire(String sha256);
}

/// Décode un `data:<mime>;base64,<...>` ; `null` si ce n'en est pas un ou si le base64 est illisible.
({String mime, List<int> octets})? docDecoderDataUri(Object? donnees) {
  final s = '${donnees ?? ''}';
  final m = RegExp(r'^data:([^;,]+)?(;base64)?,').firstMatch(s);
  if (m == null || m.group(2) == null) return null;
  try {
    return (mime: m.group(1) ?? 'application/octet-stream', octets: base64Decode(s.substring(m.end)));
  } catch (_) {
    return null;
  }
}

class DocRapportMigration {
  final List<String> migrees = [];
  final List<({String fiche, String code, String motif})> refusees = [];
  int ignorees = 0;
  bool get complet => refusees.isEmpty;
}

/// MIGRATION du base64 de `documentsPatient` vers le dossier de fichiers. POUR CHAQUE fiche qui porte encore `donnees` :
///  1. décoder, calculer l'empreinte des octets d'origine ;
///  2. déposer sous le nom normalisé ;
///  3. RELIRE le fichier rangé et comparer son empreinte à celle d'origine ;
///  4. SEULEMENT ALORS retirer le base64 (patch `donnees: null` + `scan`). Une copie qui ne relit pas à l'identique laisse la fiche INTACTE et le dit au rapport.
/// Idempotente : une fiche déjà migrée (sans `donnees`) est ignorée. [appliquer] écrit le patch (le magasin, journalisé). Aucun octet n'est supprimé du disque.
Future<DocRapportMigration> docMigrerBase64({
  required Iterable<Map<String, Object?>> fiches,
  required DocStockage stockage,
  required Future<void> Function(Object? id, Map<String, Object?> patch) appliquer,
  required String par,
  required String le,
  Object? tailleMaxReglee,
  int? Function(List<int> octets, String mime)? pages,
  bool Function(List<int> octets, String mime)? texteIndexe,
}) async {
  final r = DocRapportMigration();
  for (final f in fiches) {
    final brut = f['donnees'];
    if ('${brut ?? ''}'.isEmpty) {
      r.ignorees++;
      continue;
    }
    final ref = '${f['reference'] ?? f['id']}';
    final d = docDecoderDataUri(brut);
    if (d == null) {
      r.refusees.add((fiche: ref, code: 'BASE64_ILLISIBLE', motif: 'Le contenu déposé n’est pas un base64 lisible : la fiche garde son contenu.'));
      continue;
    }
    // Une fiche ancienne peut dépasser la taille réglée aujourd'hui : la migration ne la refuse pas pour cela (elle existe déjà), mais elle refuse un format inconnu.
    final fmt = docFormatDesOctets(d.octets);
    if (fmt == null || !fmt.familles.contains(docFamillePatient)) {
      r.refusees.add((fiche: ref, code: 'FORMAT_REFUSE', motif: 'Le contenu n’est ni un PDF, ni un JPEG, ni un PNG, ni un WEBP : la fiche garde son contenu.'));
      continue;
    }
    final sha = docSha256(d.octets);
    final version = docProchaineVersion(f);
    final nom = docNomNormalise(famille: docFamillePatient, fiche: f, ext: fmt.extension, version: version);
    try {
      await stockage.deposer(octets: d.octets, sha256: sha, nomNormalise: nom);
      final relu = await stockage.lire(sha);
      if (relu == null || docSha256(relu) != sha) {
        r.refusees.add((fiche: ref, code: 'EMPREINTE_RELUE_DIFFERENTE', motif: 'La copie rangée ne se relit pas à l’identique : le base64 est conservé.'));
        continue;
      }
      final meta = docMetaScan(
          sha256: sha,
          nomOrigine: '${f['fichier'] ?? nom}',
          nomNormalise: nom,
          mime: fmt.mime,
          taille: d.octets.length,
          version: version,
          deposePar: par,
          deposeLe: le,
          pages: pages?.call(d.octets, fmt.mime),
          texteIndexe: texteIndexe?.call(d.octets, fmt.mime) ?? false);
      await appliquer(f['id'], {'scan': meta, 'donnees': null});
      r.migrees.add(ref);
    } on DocErreur catch (e) {
      r.refusees.add((fiche: ref, code: e.code, motif: '${e.motif} ${e.geste}'));
    }
  }
  return r;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Recherche avancée
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// L'état d'indexation de la pièce : `indexe` (le texte d'un PDF à couche texte est cherchable), `non_indexe` (scan image : l'OCR est une phase ultérieure),
/// `sans_fichier`. Un scan image est DIT « texte non indexé », jamais « aucun résultat ».
String docEtatIndexation(Map<String, Object?> fiche) {
  final s = docScan(fiche);
  if (s == null) return 'sans_fichier';
  return s['texteIndexe'] == true ? 'indexe' : 'non_indexe';
}

String docLibelleIndexation(Map<String, Object?> fiche) => switch (docEtatIndexation(fiche)) {
      'indexe' => 'Texte indexé',
      'non_indexe' => 'Texte non indexé',
      _ => 'Sans fichier',
    };

/// Les mots d'une requête : normalisés (accents et casse ignorés), TOUS doivent se trouver (pas de recherche par le sens).
List<String> docMotsRecherche(String requete) => normaliser(requete).split(RegExp(r'[^a-z0-9/]+')).where((m) => m.isNotEmpty).toList();

String _dateLisible(Object? d) {
  final s = '${d ?? ''}';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  return m == null ? s : '${m.group(3)}/${m.group(2)}/${m.group(1)}';
}

/// Le texte des métadonnées cherchable d'une fiche (objet, correspondant, type, patient, observations, référence, date lisible, noms du fichier).
String docTexteMetadonnees(Map<String, Object?> f) {
  final s = docScan(f);
  return [
    for (final k in ['reference', 'objet', 'correspondant', 'nature', 'affecteA', 'sens', 'type', 'patient', 'code', 'observations', 'depose', 'etat', 'traitement'])
      if (f[k] != null) '${f[k]}',
    _dateLisible(f['date']),
    if (s != null) ...['${s['nom']}', '${s['nomNormalise']}', '${s['deposePar'] ?? ''}'],
  ].join(' ');
}

/// Résultat d'une recherche : trouvé, et DANS QUOI (métadonnées ou texte du PDF).
class DocTrouve {
  const DocTrouve(this.trouve, {this.dansTexte = false});
  final bool trouve;
  final bool dansTexte;
}

/// Cherche [requete] dans les métadonnées de la fiche et dans [texteIndexe] (le texte du PDF, déjà normalisé ou non). Requête vide : tout.
DocTrouve docCorrespond(Map<String, Object?> fiche, String requete, {String? texteIndexe}) {
  final mots = docMotsRecherche(requete);
  if (mots.isEmpty) return const DocTrouve(true);
  final meta = normaliser(docTexteMetadonnees(fiche));
  final corps = normaliser(texteIndexe ?? '');
  var texte = false;
  for (final m in mots) {
    if (meta.contains(m)) continue;
    if (corps.contains(m)) {
      texte = true;
      continue;
    }
    return const DocTrouve(false);
  }
  return DocTrouve(true, dansTexte: texte);
}

/// Dans la plage [du, au] (dates ISO `AAAA-MM-JJ`, bornes incluses, vides = ouvertes).
bool docDansPlage(Object? date, {String? du, String? au}) {
  final d = '${date ?? ''}'.length >= 10 ? '$date'.substring(0, 10) : '${date ?? ''}';
  if (du != null && du.isNotEmpty && d.compareTo(du) < 0) return false;
  if (au != null && au.isNotEmpty && d.compareTo(au) > 0) return false;
  return true;
}
