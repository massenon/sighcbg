// L'EXPORT COMPLET PORTABLE ET SON RÉIMPORT : les RÈGLES PURES (Direction de Baguidi, 17/11/2026, décision 12, puis précisions du même jour sur le fileul).
//
// Un fichier, un manifeste LISIBLE SANS CLÉ (version du logiciel, schéma des données, date, identité de la clinique, compteurs par collection, empreinte du contenu),
// un contenu compressé et CHIFFRÉ par la clé de la clinique (le chiffrement vit dans `sigh_sync`, qui réutilise celui des sauvegardes). Ici : le manifeste, ce qui est
// EXCLU du fichier, et les contrôles d'import, qui REFUSENT EN NOMMANT (code, motif, geste) — jamais de refus muet, jamais d'import à moitié.
//
// CE QUI VOYAGE : toutes les collections du magasin du poste (archivées comprises, RG-14), sa méta (schéma, journal des migrations), et, selon le rôle de la source :
//  * MÈRE : les tables du journal de synchronisation (opérations, fiches confirmées, plages, appareils…) ;
//  * FILEUL : sa FILE d'opérations NON confirmées (aucune saisie en attente ne se perd au déménagement), ses plages et son étiquette.
// CE QUI NE VOYAGE JAMAIS (aucun secret, aucune clé dans le fichier) : la clé de la clinique ; les hachés des comptes (`identifiants`) ; les jetons des liens publics
// d'enquête (`jetonsEnquete`) ; les codes d'appairage non utilisés ; toute clé de méta qui nomme une clé, un secret, un jeton ou un mot de passe.
library;

import 'dart:convert';

import '../droits/gestes_reserves.dart';
import 'sauvegarde_horssite.dart' show RefusSauvegarde, shOctets;
import 'schema_donnees.dart';

/// Le format du fichier d'export (versionné : un logiciel plus ancien refuse un format qu'il ne connaît pas).
const int epFormat = 1;

/// Le genre inscrit au manifeste.
const String epGenre = 'export-complet';

/// L'en-tête du fichier : « SGHX » puis l'octet de format.
const List<int> epMagique = [0x53, 0x47, 0x48, 0x58];

/// Les deux rôles d'une source ou d'une cible.
const String epRoleMere = 'mere';
const String epRoleFileul = 'fileul';

/// Les collections du magasin qui ne voyagent PAS, avec la raison (affichée à l'écran et au manifeste).
const Map<String, String> epCollectionsExclues = {
  'identifiants': 'hachés des mots de passe : un secret ne voyage pas ; les mots de passe se redéfinissent sur le poste d’arrivée (réinitialisation de compte)',
  'jetonsEnquete': 'jetons des liens publics d’enquête : un lien à diffuser se recrée sur le poste d’arrivée',
};

/// Les tables de la mère qui ne voyagent pas (codes d'appairage à usage unique : un secret).
const List<String> epTablesMereExclues = ['codes'];

/// Les clés de méta de la mère qui ne voyagent pas : la clé de la clinique elle-même.
const List<String> epMetaMereExclues = ['cle'];

final RegExp _cleSecrete = RegExp(r'(^|[_.:\- ])(cle|secret|jeton|mdp|password|token|motdepasse)', caseSensitive: false);

/// Une clé de méta nomme-t-elle un secret ? (jamais exportée).
bool epCleMetaSecrete(String cle) => _cleSecrete.hasMatch(cle);

/// La méta exportable d'un magasin ou d'une base : sans clé secrète.
Map<String, Object?> epMetaExportable(Map<String, Object?> meta, {List<String> exclues = const []}) => {
      for (final e in meta.entries)
        if (!epCleMetaSecrete(e.key) && !exclues.contains(e.key)) e.key: e.value,
    };

/// Un refus d'export ou d'import, levé tel quel (le code se teste, le motif se lit au guichet).
class ErreurExport implements Exception {
  const ErreurExport(this.refus);
  final RefusSauvegarde refus;
  String get code => refus.code;
  @override
  String toString() => '${refus.code} : ${refus.motif}';
}

RefusSauvegarde _r(String code, String motif, String geste, [Map<String, Object?> plus = const {}]) => RefusSauvegarde(code, motif, geste, plus);

/// L'identité de la clinique portée au manifeste : de quoi refuser le fichier d'une AUTRE clinique, jamais un secret.
class IdentiteExport {
  const IdentiteExport({required this.sigle, required this.nom, required this.ifu});
  final String sigle;
  final String nom;
  final String ifu;
  Map<String, Object?> toJson() => {'sigle': sigle, 'nom': nom, 'ifu': ifu};
  factory IdentiteExport.depuisJson(Map<String, Object?> j) => IdentiteExport(sigle: '${j['sigle'] ?? ''}', nom: '${j['nom'] ?? ''}', ifu: '${j['ifu'] ?? ''}');
  bool memeClinique(IdentiteExport autre) => ifu.trim().isNotEmpty && autre.ifu.trim().isNotEmpty ? ifu.trim() == autre.ifu.trim() : nom.trim().toLowerCase() == autre.nom.trim().toLowerCase();
}

/// Le manifeste d'un export : lisible sans clé, recoupé avec la copie portée DANS le contenu chiffré (une altération du manifeste se voit).
class ManifesteExport {
  const ManifesteExport({
    required this.format,
    required this.logicielVersion,
    required this.schema,
    required this.cree,
    required this.clinique,
    required this.roleSource,
    required this.etiquette,
    required this.compteurs,
    required this.empreinte,
    required this.tailleClair,
    required this.cleEmpreinte,
    this.sections = const [],
    this.fileEnAttente = 0,
    this.exclusions = const [],
    this.uuidSource = '',
  });
  final int format;
  final String logicielVersion;
  final int schema;

  /// Date de création, ISO 8601 UTC.
  final String cree;
  final IdentiteExport clinique;
  final String roleSource;

  /// L'étiquette du poste d'origine (identité d'étiquette, jamais un nom d'agent).
  final String etiquette;
  final String uuidSource;

  /// Nombre de fiches par collection du magasin (et `sync.<table>` par table de la mère) : des COMPTES, jamais du contenu.
  final Map<String, int> compteurs;

  /// SHA-256 du contenu en clair (avant compression et chiffrement).
  final String empreinte;
  final int tailleClair;

  /// L'empreinte COURTE de la clé qui a chiffré (16 premiers hexadécimaux du SHA-256 de la clé) : elle permet de dire « mauvaise clé » plutôt que « fichier altéré ». Elle ne
  /// permet pas de retrouver la clé.
  final String cleEmpreinte;
  final List<String> sections;
  final int fileEnAttente;
  final List<String> exclusions;

  int get total => compteurs.values.fold(0, (a, b) => a + b);

  Map<String, Object?> toJson() => {
        'format': format,
        'genre': epGenre,
        'logiciel': {'version': logicielVersion},
        'schema': schema,
        'cree': cree,
        'clinique': clinique.toJson(),
        'source': {'role': roleSource, 'etiquette': etiquette, if (uuidSource.isNotEmpty) 'uuid': uuidSource},
        'compteurs': compteurs,
        'total': total,
        'empreinte': empreinte,
        'tailleClair': tailleClair,
        'cleEmpreinte': cleEmpreinte,
        'sections': sections,
        'fileEnAttente': fileEnAttente,
        'exclusions': exclusions,
      };

  String toCanonique() => jsonEncode(toJson());

  /// Lecture STRICTE : un manifeste qui n'a pas la forme attendue est refusé (`MANIFESTE_ILLISIBLE`).
  static ManifesteExport depuisJson(Object? brut) {
    if (brut is! Map) throw ErreurExport(_r('MANIFESTE_ILLISIBLE', 'le manifeste du fichier n’a pas la forme attendue', 'Choisir un fichier produit par « Exporter la base complète ».'));
    final j = brut.cast<String, Object?>();
    ErreurExport mal(String c) => ErreurExport(_r('MANIFESTE_ILLISIBLE', 'le manifeste ne porte pas « $c »', 'Choisir un fichier produit par « Exporter la base complète ».'));
    final format = j['format'];
    if (format is! int) throw mal('format');
    if (j['genre'] != epGenre) throw ErreurExport(_r('FICHIER_INCONNU', 'ce fichier n’est pas un export complet de la base', 'Choisir un fichier produit par « Exporter la base complète ».'));
    final schema = j['schema'];
    if (schema is! int) throw mal('schema');
    final src = j['source'];
    final cli = j['clinique'];
    final cpt = j['compteurs'];
    if (src is! Map || cli is! Map || cpt is! Map) throw mal('source, clinique ou compteurs');
    final role = '${src['role']}';
    if (role != epRoleMere && role != epRoleFileul) throw mal('source.role');
    for (final c in ['empreinte', 'cree', 'cleEmpreinte']) {
      if (j[c] is! String || (j[c] as String).isEmpty) throw mal(c);
    }
    return ManifesteExport(
      format: format,
      logicielVersion: '${(j['logiciel'] is Map ? (j['logiciel'] as Map)['version'] : '') ?? ''}',
      schema: schema,
      cree: j['cree'] as String,
      clinique: IdentiteExport.depuisJson(cli.cast<String, Object?>()),
      roleSource: role,
      etiquette: '${src['etiquette'] ?? ''}',
      uuidSource: '${src['uuid'] ?? ''}',
      compteurs: {for (final e in cpt.entries) '${e.key}': (e.value as num).toInt()},
      empreinte: j['empreinte'] as String,
      tailleClair: (j['tailleClair'] as num?)?.toInt() ?? 0,
      cleEmpreinte: j['cleEmpreinte'] as String,
      sections: [for (final s in (j['sections'] as List? ?? const [])) '$s'],
      fileEnAttente: (j['fileEnAttente'] as num?)?.toInt() ?? 0,
      exclusions: [for (final s in (j['exclusions'] as List? ?? const [])) '$s'],
    );
  }
}

/// CE QUE L'IMPORT FERA du fichier, selon la source et la cible.
enum ModeImport {
  /// Un magasin complet sert de base : la mère reprend sa vie (ou le fileul reprend sa file) sur le magasin neuf.
  complet,

  /// Un export de MÈRE importé sur un fileul : point de départ de RESYNCHRONISATION : la mère reste l'autorité, le fileul se rattache et rejoue ce qu'il a en file.
  resynchronisation,
}

/// LES CONTRÔLES D'IMPORT, dans l'ordre où ils se posent. Rend le premier refus NOMMÉ, ou `null`. [roleCible] : `mere` ou `fileul`. [identiteLocale] : la clinique de CE poste.
/// [rattache] : le poste cible est un fileul rattaché à une mère ; un fileul non rattaché (autonome) importe comme une mère de lui-même (Direction, 17/11/2026).
/// [cibleExiste] : le dossier du magasin neuf existe déjà (jamais écrasé).
RefusSauvegarde? epControlerImport(
    {required ManifesteExport manifeste,
    required String roleCible,
    IdentiteExport? identiteLocale,
    bool rattache = true,
    bool cibleExiste = false,
    int schemaLogiciel = schemaDonneesCourant,
    int formatLogiciel = epFormat}) {
  if (manifeste.format > formatLogiciel) {
    return _r('FORMAT_PLUS_RECENT', 'ce fichier est au format ${manifeste.format}, ce logiciel ne lit que jusqu’au format $formatLogiciel', 'Installer la version du logiciel qui a produit le fichier (ou une plus récente).');
  }
  if (manifeste.schema > schemaLogiciel) return refusSchemaPlusRecent(manifeste.schema, courant: schemaLogiciel, objet: 'Ce fichier');
  if (identiteLocale != null && !manifeste.clinique.memeClinique(identiteLocale)) {
    return _r('AUTRE_CLINIQUE', 'ce fichier vient d’une autre clinique (« ${manifeste.clinique.nom} »), ce poste est celui de « ${identiteLocale.nom} »',
        'Importer le fichier de CETTE clinique. Un fichier d’une autre clinique n’est jamais lu.');
  }
  final commeFileul = roleCible == epRoleFileul && rattache;
  if (manifeste.roleSource == epRoleFileul && !commeFileul) {
    return _r('FILEUL_VERS_MERE', 'ce fichier est l’export d’un poste FILEUL : il ne peut pas servir de base à une mère (il ne porte pas le journal de la clinique, seulement la file de ce poste)',
        'Importer l’export de la MÈRE sur la mère, ou celui du fileul sur un fileul.');
  }
  if (cibleExiste) {
    return _r('CIBLE_EXISTE', 'le dossier de destination existe déjà : un import n’écrit jamais sur un magasin existant', 'Choisir un dossier neuf (l’écran en propose un), puis décider de la mise en service.');
  }
  return null;
}

/// Le mode d'un import accepté.
ModeImport epModeImport({required ManifesteExport manifeste, required String roleCible, bool rattache = true}) =>
    roleCible == epRoleFileul && rattache && manifeste.roleSource == epRoleMere ? ModeImport.resynchronisation : ModeImport.complet;

/// Une saisie du fileul que l'import risque de ne pas retrouver : listée, jamais écrasée en silence.
class SaisieLocale {
  const SaisieLocale({required this.collection, required this.fiche, required this.type, required this.quand});
  final String collection;
  final String fiche;
  final String type;
  final DateTime quand;
  Map<String, Object?> toJson() => {'collection': collection, 'fiche': fiche, 'type': type, 'quand': quand.toUtc().toIso8601String()};
}

/// L'avertissement NON BLOQUANT d'un import plus ANCIEN que la dernière synchronisation du poste (Direction, 17/11/2026, point 4) : le magasin importé ne contient pas ce qui
/// s'est écrit depuis. Les saisies locales postérieures et non synchronisées sont LISTÉES (elles restent dans la file du poste ; la liste est aussi gardée avec la copie du magasin
/// remplacé). Rend `null` quand l'import n'est pas plus ancien.
class AvertissementAnciennete {
  const AvertissementAnciennete({required this.message, required this.saisies, required this.ecartHeures});
  final String message;
  final List<SaisieLocale> saisies;
  final int ecartHeures;
}

AvertissementAnciennete? epAvertirAnciennete({required DateTime exportCree, DateTime? derniereSynchro, List<SaisieLocale> fileEnAttente = const []}) {
  final posterieures = [for (final s in fileEnAttente) if (s.quand.isAfter(exportCree)) s];
  final plusAncien = derniereSynchro != null && derniereSynchro.isAfter(exportCree);
  if (!plusAncien && posterieures.isEmpty) return null;
  final ecart = plusAncien ? derniereSynchro.difference(exportCree).inHours : 0;
  final morceaux = <String>[
    if (plusAncien) 'ce fichier date de $ecart heure(s) avant la dernière synchronisation de ce poste : ce qui s’est écrit depuis n’y figure pas',
    if (posterieures.isNotEmpty) '${posterieures.length} saisie(s) de ce poste, postérieure(s) au fichier et pas encore synchronisée(s), sont listée(s) et conservée(s) dans la file du poste',
  ];
  return AvertissementAnciennete(
      message: 'Avertissement (non bloquant) : ${morceaux.join(' ; ')}. La mère reste l’autorité : elle renverra ce qu’elle a validé.', saisies: posterieures, ecartHeures: ecart);
}

/// Le COMPTE RENDU d'un export, pour l'écran : sans contenu médical.
String epResume(ManifesteExport m) =>
    '${m.total} fiche(s) dans ${m.compteurs.length} ensemble(s), schéma ${m.schema}, ${m.roleSource == epRoleMere ? 'mère' : 'fileul'}${m.etiquette.isEmpty ? '' : ' « ${m.etiquette} »'}, créé le ${m.cree} (${shOctets(m.tailleClair)} en clair)';

/// Les GESTES de l'export et de l'import (fiche de rôle, réglables) : jamais une liste de rôles écrite ici.
List<String> get epRolesExport => gesteReserve(gesteBaseExporter)?.rolesDefaut ?? const [];
List<String> get epRolesImport => gesteReserve(gesteBaseImporter)?.rolesDefaut ?? const [];
