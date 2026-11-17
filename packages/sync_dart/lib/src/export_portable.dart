/// L'EXPORT COMPLET PORTABLE (Direction de Baguidi, 17/11/2026, décision 12) : un fichier, un manifeste lisible sans clé, un contenu compressé (gzip) et CHIFFRÉ par la clé de la
/// clinique. Il réutilise le chiffrement des sauvegardes ([ChiffreurSauvegarde] : AES-256-GCM, un bloc par tranche, le « genre » `export` lié à l'authentification) : un export ne
/// s'ouvre pas comme un bloc de sauvegarde et inversement. Les RÈGLES (manifeste, exclusions, refus d'import) sont dans `sigh_domaine` (`export_portable_regles.dart`).
///
/// Disposition du fichier :
///   « SGHX » ‖ format (1 octet) ‖ longueur du manifeste (4 octets, grand-boutiste) ‖ manifeste JSON (EN CLAIR) ‖ N × [ longueur (4 octets) ‖ bloc scellé ]
/// Le contenu des blocs, une fois ouvert, assemblé et décompressé, est un JSON `{manifeste, contenu}` où `contenu` est une CHAÎNE JSON : l'empreinte du manifeste est celle de cette
/// chaîne, et la copie du manifeste portée dedans doit être identique à celle du début du fichier (une altération du manifeste se voit).
///
/// VÉRIFIER n'écrit RIEN (ni disque, ni base) : tout se joue en mémoire. L'import, lui, n'écrit que dans une cible NEUVE.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sigh_domaine/sigh_domaine.dart';

import 'depot.dart';
import 'mere.dart';
import 'sauvegarde_horssite.dart' show ChiffreurSauvegarde, ErreurSauvegarde;

/// Le contenu d'un export : le magasin du poste (collections et méta) et la section du moteur de synchronisation, selon le rôle de la source.
class ContenuExport {
  ContenuExport({required this.collections, this.meta = const {}, this.sync});
  final Map<String, List<Map<String, Object?>>> collections;
  final Map<String, Object?> meta;

  /// MÈRE : `{role:'mere', tables:{…}, meta:{…}}` ; FILEUL : `{role:'fileul', uuid, etiquette, file:[…], plage:[…], baux:[…]}` ; `null` : poste sans moteur de synchronisation.
  final Map<String, Object?>? sync;
}

/// Ce qu'une vérification a lu, sans rien écrire.
class RapportVerification {
  RapportVerification(this.manifeste, {required this.contenuOk});
  final ManifesteExport manifeste;
  final bool contenuOk;
}

ErreurExport _e(String code, String motif, String geste, [Map<String, Object?> plus = const {}]) => ErreurExport(RefusSauvegarde(code, motif, geste, plus));

Uint8List _u32(int n) => Uint8List(4)..buffer.asByteData().setUint32(0, n);
int _lire32(List<int> o, int i) => ByteData.sublistView(Uint8List.fromList(o.sublist(i, i + 4))).getUint32(0);

class ExportPortable {
  const ExportPortable._();

  /// Retire du contenu ce qui ne voyage jamais (collections exclues, clés de méta secrètes, tables et méta de la mère) : l'exclusion se fait ICI, au scellement, pour qu'aucun appelant ne
  /// puisse l'oublier.
  static ({ContenuExport contenu, List<String> exclusions}) purger(ContenuExport c) {
    final exclusions = <String>[];
    final cols = <String, List<Map<String, Object?>>>{};
    for (final e in c.collections.entries) {
      if (epCollectionsExclues.containsKey(e.key)) {
        exclusions.add(e.key);
        continue;
      }
      cols[e.key] = e.value;
    }
    Map<String, Object?>? sync = c.sync;
    if (sync != null && sync['role'] == epRoleMere) {
      final tables = ((sync['tables'] ?? const {}) as Map).cast<String, Object?>();
      final t = <String, Object?>{};
      for (final e in tables.entries) {
        if (epTablesMereExclues.contains(e.key)) {
          exclusions.add('sync.${e.key}');
          continue;
        }
        if (e.key == 'meta') {
          t['meta'] = [
            for (final r in (e.value as List))
              if (!epCleMetaSecrete('${(r as Map)['k']}') && !epMetaMereExclues.contains('${r['k']}')) r
          ];
          continue;
        }
        t[e.key] = e.value;
      }
      sync = {...sync, 'tables': t};
    }
    return (contenu: ContenuExport(collections: cols, meta: epMetaExportable(c.meta), sync: sync), exclusions: exclusions);
  }

  static Map<String, int> _compteurs(ContenuExport c) {
    final out = <String, int>{for (final e in c.collections.entries) e.key: e.value.length};
    final s = c.sync;
    if (s != null && s['role'] == epRoleMere) {
      for (final e in ((s['tables'] ?? const {}) as Map).entries) {
        out['sync.${e.key}'] = (e.value as List).length;
      }
    } else if (s != null && s['role'] == epRoleFileul) {
      out['sync.file'] = ((s['file'] ?? const []) as List).length;
    }
    return out;
  }

  /// SCELLE l'export : manifeste en clair, contenu chiffré. [role] : `mere` ou `fileul` (la source). Aucun secret ni clé dans le fichier (voir [purger]).
  static Future<Uint8List> sceller(
      {required List<int> cle,
      required ContenuExport contenu,
      required String role,
      required IdentiteExport clinique,
      required String logicielVersion,
      String etiquette = '',
      String uuidSource = '',
      int schema = schemaDonneesCourant,
      DateTime? maintenant,
      int tailleBloc = shTailleBlocDefaut}) async {
    final p = purger(contenu);
    final contenuJson = jsonEncode({
      'magasin': {'meta': p.contenu.meta, 'collections': p.contenu.collections},
      if (p.contenu.sync != null) 'sync': p.contenu.sync,
    });
    final clair = utf8.encode(contenuJson);
    final fileEnAttente = p.contenu.sync?['role'] == epRoleFileul ? ((p.contenu.sync!['file'] ?? const []) as List).length : 0;
    final m = ManifesteExport(
      format: epFormat,
      logicielVersion: logicielVersion,
      schema: schema,
      cree: (maintenant ?? DateTime.now()).toUtc().toIso8601String(),
      clinique: clinique,
      roleSource: role,
      etiquette: etiquette,
      uuidSource: uuidSource,
      compteurs: _compteurs(p.contenu),
      empreinte: docSha256(clair),
      tailleClair: clair.length,
      cleEmpreinte: cleEmpreinteManifeste(cle),
      sections: ['magasin', if (p.contenu.sync != null) 'sync-$role'],
      fileEnAttente: fileEnAttente,
      exclusions: p.exclusions,
    );
    final doc = utf8.encode(jsonEncode({'manifeste': m.toJson(), 'contenu': contenuJson}));
    final compresse = gzip.encode(doc);
    final chiffreur = ChiffreurSauvegarde(cle);
    final mj = utf8.encode(m.toCanonique());
    final sortie = BytesBuilder(copy: false)
      ..add(epMagique)
      ..addByte(epFormat)
      ..add(_u32(mj.length))
      ..add(mj);
    for (final pl in shDecouper(compresse.length, tailleBloc)) {
      final bloc = await chiffreur.sceller('export', 'base', compresse.sublist(pl.debut, pl.debut + pl.longueur));
      sortie
        ..add(_u32(bloc.octets.length))
        ..add(bloc.octets);
    }
    return sortie.toBytes();
  }

  /// Lit le manifeste SANS CLÉ (en-tête et manifeste en clair) : refus nommé si ce n'est pas un export, ou si le format est plus récent.
  static (ManifesteExport, int) lireManifeste(List<int> octets) {
    if (octets.length < 9 || [for (var i = 0; i < 4; i++) octets[i]].toString() != epMagique.toString()) {
      throw _e('FICHIER_INCONNU', 'ce fichier n’est pas un export complet de la base', 'Choisir un fichier produit par « Exporter la base complète ».');
    }
    final format = octets[4];
    if (format > epFormat) {
      throw _e('FORMAT_PLUS_RECENT', 'ce fichier est au format $format, ce logiciel ne lit que jusqu’au format $epFormat', 'Installer la version du logiciel qui a produit le fichier (ou une plus récente).');
    }
    final n = _lire32(octets, 5);
    if (9 + n > octets.length) throw _e('FICHIER_ALTERE', 'le fichier est tronqué : le manifeste est incomplet', 'Reprendre le fichier depuis sa source (copie, téléchargement).');
    Object? j;
    try {
      j = jsonDecode(utf8.decode(octets.sublist(9, 9 + n)));
    } catch (_) {
      throw _e('MANIFESTE_ILLISIBLE', 'le manifeste du fichier est illisible', 'Reprendre le fichier depuis sa source.');
    }
    return (ManifesteExport.depuisJson(j), 9 + n);
  }

  /// OUVRE l'export : déchiffre, assemble, décompresse, contrôle l'empreinte et recoupe le manifeste. Refus nommés : `CLE_ABSENTE`, `CLE_INCORRECTE`, `FICHIER_ALTERE`,
  /// `MANIFESTE_ALTERE`, `EMPREINTE_DIFFERENTE`. N'écrit rien.
  static Future<({ManifesteExport manifeste, ContenuExport contenu})> ouvrir(List<int> octets, List<int>? cle) async {
    final (m, debut) = lireManifeste(octets);
    if (cle == null || cle.length != cleLongueur) {
      throw _e('CLE_ABSENTE', 'la clé de la clinique est absente : sans elle le contenu ne peut pas être ouvert', 'Restaurer la clé depuis la copie sous scellé (« Restaurer la clé de la clinique »), puis recommencer.');
    }
    if (cleEmpreinteManifeste(cle) != m.cleEmpreinte) {
      throw _e('CLE_INCORRECTE', 'cette clé n’est pas celle qui a chiffré le fichier (l’empreinte de la clé ne correspond pas)', 'Utiliser la clé de la clinique qui a produit le fichier (copie sous scellé).');
    }
    final chiffreur = ChiffreurSauvegarde(cle);
    final compresse = BytesBuilder(copy: false);
    var i = debut;
    try {
      while (i < octets.length) {
        if (i + 4 > octets.length) throw const FormatException('tronqué');
        final n = _lire32(octets, i);
        i += 4;
        if (n < 28 || i + n > octets.length) throw const FormatException('tronqué');
        final bloc = Uint8List.fromList(octets.sublist(i, i + n));
        i += n;
        compresse.add(await chiffreur.ouvrir('export', 'base', bloc, docSha256(bloc)));
      }
    } on ErreurSauvegarde {
      throw _e('FICHIER_ALTERE', 'le contenu du fichier a été altéré (un bloc ne s’authentifie pas) : rien n’a été lu', 'Reprendre le fichier depuis sa source ou choisir un autre export.');
    } on FormatException {
      throw _e('FICHIER_ALTERE', 'le fichier est tronqué ou mal formé : rien n’a été lu', 'Reprendre le fichier depuis sa source ou choisir un autre export.');
    }
    Map<String, Object?> doc;
    try {
      doc = (jsonDecode(utf8.decode(gzip.decode(compresse.toBytes()))) as Map).cast<String, Object?>();
    } catch (_) {
      throw _e('FICHIER_ALTERE', 'le contenu ne se décompresse pas : fichier altéré', 'Reprendre le fichier depuis sa source.');
    }
    final interne = ManifesteExport.depuisJson(doc['manifeste']);
    if (interne.toCanonique() != m.toCanonique()) {
      throw _e('MANIFESTE_ALTERE', 'le manifeste en clair ne correspond pas à celui du contenu chiffré : le fichier a été modifié', 'Ne pas utiliser ce fichier ; reprendre l’export d’origine.');
    }
    final contenuJson = '${doc['contenu']}';
    if (docSha256(utf8.encode(contenuJson)) != m.empreinte) {
      throw _e('EMPREINTE_DIFFERENTE', 'l’empreinte du contenu ne correspond pas à celle du manifeste', 'Ne pas utiliser ce fichier ; reprendre l’export d’origine.');
    }
    final c = (jsonDecode(contenuJson) as Map).cast<String, Object?>();
    final mag = (c['magasin'] as Map).cast<String, Object?>();
    return (
      manifeste: m,
      contenu: ContenuExport(
        collections: {
          for (final e in (mag['collections'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()]
        },
        meta: ((mag['meta'] ?? const {}) as Map).cast<String, Object?>(),
        sync: c['sync'] == null ? null : (c['sync'] as Map).cast<String, Object?>(),
      ),
    );
  }

  /// VÉRIFIE sans rien écrire : le résultat est le manifeste relu, preuve que le fichier s'ouvre avec CETTE clé.
  static Future<RapportVerification> verifier(List<int> octets, List<int>? cle) async {
    final r = await ouvrir(octets, cle);
    return RapportVerification(r.manifeste, contenuOk: true);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// La MÈRE : sa base (journal de synchronisation) se sort en lignes, se rejoue dans une base NEUVE.
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Les tables d'un dépôt, sans les tables internes du moteur.
Future<List<String>> tablesDuDepot(Depot d) async {
  final r = d.dialecte == 'pg'
      ? await d.select("SELECT table_name AS name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name")
      : await d.select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
  return [for (final x in r) '${x['name']}'];
}

/// La GARDE du schéma d'un dépôt de mère : refuse (en le nommant) un dépôt plus récent que le logiciel, pose le numéro d'un dépôt qui n'en porte pas.
Future<void> gardeSchemaDepot(Depot d) async {
  final brut = await d.meta(schemaCleMeta);
  if (brut == null) {
    await d.poserMeta(schemaCleMeta, schemaDonneesCourant);
    return;
  }
  final n = int.tryParse(brut);
  if (n == null || n < 0) throw ErreurSchemaDonnees(refusSchemaIllisible(brut, objet: 'Cette base de la mère'));
  if (n > schemaDonneesCourant) throw ErreurSchemaDonnees(refusSchemaPlusRecent(n, objet: 'Cette base de la mère'));
}

/// La base de la mère en lignes : `{role:'mere', tables:{table:[lignes]}}` (la clé de la clinique et les codes d'appairage seront retirés au scellement).
Future<Map<String, Object?>> extraireMere(Depot d) async {
  final tables = <String, Object?>{};
  for (final t in await tablesDuDepot(d)) {
    tables[t] = await d.select('SELECT * FROM $t');
  }
  return {'role': epRoleMere, 'tables': tables};
}

/// Le rapport d'un import de mère.
class RapportImportMere {
  RapportImportMere(this.lignes, this.tables);
  final int lignes;
  final int tables;
}

final RegExp _identifiantSql = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// IMPORTE une mère dans une base NEUVE : [cfg.dbChemin] ne doit pas exister (`CIBLE_EXISTE`), [cfg.cleBase64] est la clé qui a ouvert l'export (la mère restaurée garde la clé de la
/// clinique : les fileuls et le relais continuent de lui parler). La base est créée par `Mere.creer` (le même DDL que la mère en service), puis les lignes sont rejouées dans UNE transaction ;
/// la méta secrète n'a jamais voyagé et les codes d'appairage non plus. Le schéma est celui du fichier après la chaîne de migrations de la mère (aucune migration de base n'existe encore :
/// le numéro est posé). N'écrit jamais ailleurs que dans la cible.
Future<RapportImportMere> importerMereDansCibleNeuve({required ConfigMere cfg, required Map<String, Object?> sync, required List<int> cle, int schemaFichier = schemaDonneesCourant}) async {
  if (sync['role'] != epRoleMere) throw _e('FILEUL_VERS_MERE', 'ce contenu n’est pas celui d’une mère', 'Importer l’export de la MÈRE sur la mère.');
  if (schemaFichier > schemaDonneesCourant) throw ErreurSchemaDonnees(refusSchemaPlusRecent(schemaFichier, objet: 'Ce fichier'));
  if (cfg.cleBase64 != base64.encode(cle)) throw StateError('La configuration de la mère neuve doit porter la clé qui a ouvert l’export.');
  final enc = cfg.dbChemin;
  if (enc != ':memory:' && !enc.startsWith('postgres') && (File(enc).existsSync() || Directory(enc).existsSync())) {
    throw _e('CIBLE_EXISTE', 'la base de destination existe déjà : un import n’écrit jamais sur une base existante', 'Choisir un chemin neuf.');
  }
  final m = await Mere.creer(cfg);
  var lignes = 0, nbTables = 0;
  try {
    final d = m.base;
    final connues = (await tablesDuDepot(d)).toSet();
    final tables = ((sync['tables'] ?? const {}) as Map).cast<String, Object?>();
    await d.tx(() async {
      for (final e in tables.entries) {
        if (!connues.contains(e.key) || !_identifiantSql.hasMatch(e.key)) continue;
        nbTables++;
        for (final r in (e.value as List)) {
          final ligne = (r as Map).cast<String, Object?>();
          final colonnes = ligne.keys.where(_identifiantSql.hasMatch).toList();
          if (colonnes.isEmpty) continue;
          final ph = List.filled(colonnes.length, '?').join(',');
          final valeurs = [for (final c in colonnes) ligne[c]];
          if (e.key == 'meta') {
            await d.exec('INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v', valeurs);
          } else {
            await d.exec('INSERT INTO ${e.key}(${colonnes.join(',')}) VALUES($ph) ON CONFLICT DO NOTHING', valeurs);
          }
          lignes++;
        }
      }
    });
    // Les clés auto-incrémentées rejouées gardent leur numéro : la séquence repart au-dessus.
    for (final (t, c) in const [('operations', 'seq'), ('conflits', 'id'), ('evenements', 'id')]) {
      if (!connues.contains(t)) continue;
      final mx = (await d.select('SELECT COALESCE(MAX($c),0) AS m FROM $t')).first['m'];
      await d.recalerSequence(t, c, (mx as num).toInt());
    }
    await d.poserMeta('cle', base64.encode(cle));
    await d.poserMeta(schemaCleMeta, schemaDonneesCourant);
    await d.poserMeta('importee_le', DateTime.now().toUtc().toIso8601String());
  } finally {
    await m.arreter();
  }
  return RapportImportMere(lignes, nbTables);
}
