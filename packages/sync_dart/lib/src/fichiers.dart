/// LE DOSSIER DES SCANS DE LA MÈRE (courriers M13, dossier patient M1) et le canal qui y mène.
///
/// Décision de la Direction de Baguidi : les fichiers scannés ne vont JAMAIS sur le relais et ne sont jamais en base64 dans le magasin. Ils vivent dans un
/// DOSSIER du poste mère (chemin affiché et réglable, « où sont mes scans »), sous un NOM NORMALISÉ strict (`AAAA-MM-JJ_ARR_0042.pdf`). Chaque fiche
/// porte l'empreinte SHA-256 ; la mère la RECALCULE à chaque dépôt et à chaque lecture. Un fileul va chercher le fichier chez la mère, par les routes
/// `/sync/fichier/*` : blocs d'au plus [tailleBloc] octets, chacun scellé AES-256-GCM avec la clé de clinique (le même format d'enveloppe que le reste de la
/// synchronisation). Le relais n'est pas sur ce chemin : il ne voit ni fichier, ni nom, ni empreinte.
///
/// Conservation illimitée, aucune purge, jamais de suppression physique (RG-14) : le retrait d'un scan est une affaire de fiche, le fichier reste. Un nom
/// déjà pris par un AUTRE contenu est refusé (rien ne s'écrase). Une version remplacée garde son propre nom (`_v2`…).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sigh_domaine/sigh_domaine.dart';

/// Taille d'un bloc transporté (octets en clair). 192 Ko : un bloc scellé et en base64 reste sous 300 Ko, ce qu'un relais d'hébergement mutualisé et un
/// réseau de clinique encaissent sans peine, et une coupure ne coûte qu'un bloc (reprise).
const int tailleBloc = 192 * 1024;

String _sep(String a, String b) => a.endsWith(Platform.pathSeparator) ? '$a$b' : '$a${Platform.pathSeparator}$b';

class StockFichiers implements DocStockage {
  StockFichiers(this.dossier) {
    Directory(dossier).createSync(recursive: true);
    _lireIndex();
  }

  /// Le dossier courant (visible à l'écran, réglable).
  String dossier;

  /// sha → {noms: [...], taille}
  final Map<String, Map<String, Object?>> _index = {};

  File get _fichierIndex => File(_sep(dossier, 'empreintes.json'));
  Directory get _reception => Directory(_sep(dossier, '.reception'));

  void _lireIndex() {
    _index.clear();
    if (!_fichierIndex.existsSync()) return;
    try {
      final j = jsonDecode(_fichierIndex.readAsStringSync()) as Map;
      for (final e in j.entries) {
        _index['${e.key}'] = (e.value as Map).cast<String, Object?>();
      }
    } catch (_) {
      // Un index illisible se RECONSTRUIT depuis les fichiers (leurs noms sont normalisés, leur contenu se hache) : jamais de perte.
      reconstruireIndex();
    }
  }

  void _ecrireIndex() {
    final tmp = File('${_fichierIndex.path}.tmp');
    tmp.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(_index), flush: true);
    tmp.renameSync(_fichierIndex.path);
  }

  /// Reconstruit l'index en relisant le dossier : chaque fichier au nom normalisé est haché et rangé sous son empreinte.
  int reconstruireIndex() {
    _index.clear();
    for (final f in Directory(dossier).listSync().whereType<File>()) {
      final nom = f.uri.pathSegments.last;
      if (!docNomNormaliseValide(nom)) continue;
      final octets = f.readAsBytesSync();
      final sha = docSha256(octets);
      final e = _index.putIfAbsent(sha, () => {'noms': <String>[], 'taille': octets.length});
      (e['noms'] as List).add(nom);
    }
    _ecrireIndex();
    return _index.length;
  }

  int get nombre => _index.values.fold(0, (n, e) => n + (e['noms'] as List).length);
  int get octetsTotal => _index.values.fold(0, (n, e) => n + (e['taille'] as int) * (e['noms'] as List).length);
  bool existe(String sha) => _index.containsKey(sha);
  List<String> nomsDe(String sha) => [for (final n in (_index[sha]?['noms'] as List? ?? const [])) '$n'];

  /// Le chemin LOCAL d'un fichier rangé (celui que la fiche affiche), ou `null` s'il manque.
  String? cheminDe(String sha) {
    for (final n in nomsDe(sha)) {
      final f = File(_sep(dossier, n));
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  @override
  Future<void> deposer({required List<int> octets, required String sha256, required String nomNormalise}) async {
    if (!docNomNormaliseValide(nomNormalise)) {
      throw DocErreur('NOM_NON_NORMALISE', 'Le nom « $nomNormalise » n’est pas un nom normalisé : la mère ne range que sous un nom du schéma.', 'Rejouer le dépôt depuis la fiche.');
    }
    if (docSha256(octets) != sha256) {
      throw const DocErreur('EMPREINTE_DIVERGENTE', 'L’empreinte annoncée ne correspond pas aux octets reçus : le fichier a été altéré en route.', 'Rejouer le dépôt.');
    }
    final cible = File(_sep(dossier, nomNormalise));
    if (cible.existsSync()) {
      final existant = cible.readAsBytesSync();
      if (docSha256(existant) == sha256) {
        _indexer(sha256, nomNormalise, octets.length);
        return; // même nom, même contenu : un dépôt rejoué est idempotent
      }
      throw DocErreur('NOM_PRIS', 'Le nom « $nomNormalise » est déjà pris par un AUTRE fichier : rien ne s’écrase.', 'Déposer comme remplacement (nouvelle version) depuis la fiche.');
    }
    final tmp = File('${cible.path}.part');
    tmp.writeAsBytesSync(octets, flush: true);
    tmp.renameSync(cible.path);
    _indexer(sha256, nomNormalise, octets.length);
  }

  void _indexer(String sha, String nom, int taille) {
    final e = _index.putIfAbsent(sha, () => {'noms': <String>[], 'taille': taille});
    final noms = e['noms'] as List;
    if (!noms.contains(nom)) noms.add(nom);
    _ecrireIndex();
  }

  /// Relit un fichier rangé ET le vérifie : `null` s'il manque, [DocErreur] `FICHIER_ALTERE` si son empreinte a changé (il n'est JAMAIS servi).
  @override
  Future<List<int>?> lire(String sha256) async {
    final noms = nomsDe(sha256);
    if (noms.isEmpty) return null;
    var present = false;
    for (final n in noms) {
      final f = File(_sep(dossier, n));
      if (!f.existsSync()) continue;
      present = true;
      final o = f.readAsBytesSync();
      if (docSha256(o) == sha256) return o;
    }
    if (present) {
      throw DocErreur('FICHIER_ALTERE', 'Le fichier rangé pour l’empreinte ${docEmpreinteAbregee(sha256)} ne se relit plus à l’identique : il n’est pas servi.', 'Restaurer le dossier des scans depuis la sauvegarde, ou redéposer le scan.');
    }
    return null;
  }

  // --- réception par blocs (reprise) -----------------------------------------------------------------------------
  /// Reçoit le bloc [index] d'un fichier. Les blocs arrivent DANS L'ORDRE ; un bloc déjà reçu est ignoré (rejeu), un trou est refusé en disant le bloc
  /// attendu. Au dernier bloc : empreinte et taille recalculées, contrôle du dépôt, rangement sous [nomNormalise]. Rend `{recu, attendu, complet}`.
  Future<Map<String, Object?>> recevoirBloc({
    required String sha256,
    required String nomNormalise,
    required String nomOrigine,
    required String famille,
    required int taille,
    required int index,
    required int total,
    required List<int> octets,
    int tailleMax = docTailleDefaut,
  }) async {
    if (!docNomNormaliseValide(nomNormalise)) {
      throw DocErreur('NOM_NON_NORMALISE', 'Le nom « $nomNormalise » n’est pas un nom normalisé.', 'Rejouer le dépôt depuis la fiche.');
    }
    if (taille > tailleMax) {
      throw DocErreur('TAILLE_DEPASSEE', 'Le fichier pèse ${docPoids(taille)} ; la taille maximale réglée est ${docPoids(tailleMax)}.', 'Numériser en résolution plus basse, ou faire relever la taille maximale (Paramètres système).');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) throw const DocErreur('EMPREINTE_ILLISIBLE', 'L’empreinte n’est pas un SHA-256.', 'Rejouer le dépôt.');
    if (index < 0 || total < 1 || index >= total || total > (docTaillePlafond ~/ tailleBloc) + 2) throw const DocErreur('BLOC_INVALIDE', 'Numéro de bloc hors des bornes.', 'Rejouer le dépôt.');
    _reception.createSync(recursive: true);
    final part = File(_sep(_reception.path, '$sha256.part'));
    final etat = File(_sep(_reception.path, '$sha256.json'));
    var recus = 0;
    if (etat.existsSync() && part.existsSync()) {
      recus = ((jsonDecode(etat.readAsStringSync()) as Map)['recus'] as num).toInt();
    }
    if (index < recus) return {'recu': recus, 'attendu': recus, 'complet': false, 'rejeu': true};
    if (index > recus) throw DocErreur('BLOC_HORS_ORDRE', 'Le bloc $index arrive avant le bloc $recus.', 'Reprendre à partir du bloc $recus.');
    if (index == 0 && part.existsSync()) part.deleteSync();
    final sink = part.openSync(mode: FileMode.append);
    try {
      sink.writeFromSync(octets);
      sink.flushSync();
    } finally {
      sink.closeSync();
    }
    recus++;
    etat.writeAsStringSync(jsonEncode({'recus': recus, 'total': total, 'taille': taille, 'nom': nomNormalise}));
    if (recus < total) return {'recu': recus, 'attendu': recus, 'complet': false};
    final tout = part.readAsBytesSync();
    part.deleteSync();
    etat.deleteSync();
    if (tout.length != taille) throw DocErreur('TAILLE_DIVERGENTE', 'Le fichier reçu pèse ${tout.length} octets, la fiche en annonce $taille.', 'Rejouer le dépôt.');
    final refus = docControlerDepot(octets: tout, nomOrigine: nomOrigine, famille: famille, tailleMaxReglee: tailleMax);
    if (refus != null) throw refus;
    await deposer(octets: tout, sha256: sha256, nomNormalise: nomNormalise);
    return {'recu': recus, 'attendu': recus, 'complet': true};
  }

  /// Combien de blocs la mère a déjà reçus de ce fichier (reprise après coupure).
  int blocsRecus(String sha256) {
    final etat = File(_sep(_reception.path, '$sha256.json'));
    if (!etat.existsSync()) return 0;
    try {
      return ((jsonDecode(etat.readAsStringSync()) as Map)['recus'] as num).toInt();
    } catch (_) {
      return 0;
    }
  }

  /// Le bloc [index] d'un fichier rangé (relu et vérifié). `null` si le fichier manque.
  Future<({List<int> octets, int total, int taille, String nomNormalise})?> bloc(String sha256, int index) async {
    final o = await lire(sha256);
    if (o == null) return null;
    final total = max(1, (o.length + tailleBloc - 1) ~/ tailleBloc);
    if (index < 0 || index >= total) throw const DocErreur('BLOC_INVALIDE', 'Numéro de bloc hors des bornes.', 'Relire depuis le bloc 0.');
    return (octets: o.sublist(index * tailleBloc, min(o.length, (index + 1) * tailleBloc)), total: total, taille: o.length, nomNormalise: nomsDe(sha256).first);
  }

  // --- contrôle, sauvegarde, restauration -------------------------------------------------------------------------
  /// Relit TOUS les fichiers et compare leur empreinte : `{verifies, alteres: [...], manquants: [...]}`. Rien n'est modifié.
  Map<String, Object?> controler() {
    final alteres = <String>[], manquants = <String>[];
    var ok = 0;
    for (final e in _index.entries) {
      for (final n in (e.value['noms'] as List)) {
        final f = File(_sep(dossier, '$n'));
        if (!f.existsSync()) {
          manquants.add('$n');
        } else if (docSha256(f.readAsBytesSync()) != e.key) {
          alteres.add('$n');
        } else {
          ok++;
        }
      }
    }
    return {'verifies': ok, 'alteres': alteres, 'manquants': manquants, 'complet': alteres.isEmpty && manquants.isEmpty};
  }

  /// SAUVEGARDE INCRÉMENTALE vers [destination] : chaque fichier est copié s'il manque ou diffère, RELU à destination et comparé à son empreinte, puis un
  /// `MANIFESTE.json` (nom, empreinte, taille) est écrit. Une source altérée n'est PAS copiée (une sauvegarde ne propage pas une corruption) : elle est
  /// nommée au rapport. Rien n'est supprimé, ni à la source, ni à destination (RG-14).
  Map<String, Object?> sauvegarder(String destination) {
    final d = Directory(destination)..createSync(recursive: true);
    final manifeste = <Map<String, Object?>>[];
    final copies = <String>[], inchanges = <String>[], alteres = <String>[], manquants = <String>[];
    for (final e in _index.entries) {
      for (final n in (e.value['noms'] as List)) {
        final src = File(_sep(dossier, '$n'));
        if (!src.existsSync()) {
          manquants.add('$n');
          continue;
        }
        final o = src.readAsBytesSync();
        if (docSha256(o) != e.key) {
          alteres.add('$n');
          continue;
        }
        final dst = File(_sep(d.path, '$n'));
        if (dst.existsSync() && docSha256(dst.readAsBytesSync()) == e.key) {
          inchanges.add('$n');
        } else {
          final tmp = File('${dst.path}.part');
          tmp.writeAsBytesSync(o, flush: true);
          if (docSha256(tmp.readAsBytesSync()) != e.key) {
            tmp.deleteSync();
            alteres.add('$n');
            continue;
          }
          tmp.renameSync(dst.path);
          copies.add('$n');
        }
        manifeste.add({'nom': '$n', 'sha256': e.key, 'taille': o.length});
      }
    }
    File(_sep(d.path, 'MANIFESTE.json')).writeAsStringSync(const JsonEncoder.withIndent(' ').convert({'ecritLe': DateTime.now().toUtc().toIso8601String(), 'fichiers': manifeste}));
    return {'destination': d.path, 'copies': copies.length, 'inchanges': inchanges.length, 'alteres': alteres, 'manquants': manquants, 'total': manifeste.length};
  }

  /// RESTAURATION depuis une sauvegarde : le manifeste est lu, CHAQUE fichier est vérifié contre son empreinte AVANT d'être copié, puis relu après la copie.
  /// Un fichier de la sauvegarde qui ne correspond pas à son empreinte est REFUSÉ et nommé (jamais copié). Un fichier déjà présent à l'identique est laissé ;
  /// un fichier présent mais DIFFÉRENT n'est jamais écrasé (il est signalé : `conflits`). L'index est reconstruit. Rend le rapport.
  Map<String, Object?> restaurer(String source) {
    final m = File(_sep(source, 'MANIFESTE.json'));
    if (!m.existsSync()) throw DocErreur('SAUVEGARDE_SANS_MANIFESTE', 'Le dossier « $source » ne contient pas de MANIFESTE.json : ce n’est pas une sauvegarde des scans.', 'Choisir le dossier de sauvegarde des scans.');
    final liste = ((jsonDecode(m.readAsStringSync()) as Map)['fichiers'] as List).cast<Map>();
    Directory(dossier).createSync(recursive: true);
    final restaures = <String>[], presents = <String>[], refuses = <String>[], conflits = <String>[], absents = <String>[];
    for (final e in liste) {
      final nom = '${e['nom']}', sha = '${e['sha256']}';
      if (!docNomNormaliseValide(nom)) {
        refuses.add(nom);
        continue;
      }
      final src = File(_sep(source, nom));
      if (!src.existsSync()) {
        absents.add(nom);
        continue;
      }
      final o = src.readAsBytesSync();
      if (docSha256(o) != sha) {
        refuses.add(nom);
        continue;
      }
      final dst = File(_sep(dossier, nom));
      if (dst.existsSync()) {
        (docSha256(dst.readAsBytesSync()) == sha ? presents : conflits).add(nom);
        continue;
      }
      final tmp = File('${dst.path}.part');
      tmp.writeAsBytesSync(o, flush: true);
      if (docSha256(tmp.readAsBytesSync()) != sha) {
        tmp.deleteSync();
        refuses.add(nom);
        continue;
      }
      tmp.renameSync(dst.path);
      restaures.add(nom);
    }
    reconstruireIndex();
    return {'restaures': restaures.length, 'presents': presents.length, 'refuses': refuses, 'conflits': conflits, 'absents': absents, 'total': liste.length, 'complet': refuses.isEmpty && conflits.isEmpty && absents.isEmpty};
  }

  /// Change le dossier des scans : tout est COPIÉ dans le nouveau dossier, chaque fichier relu et comparé à son empreinte, puis le stock bascule. L'ancien
  /// dossier n'est PAS vidé (RG-14) : la mère le dit, c'est à l'administrateur d'archiver ce qu'il juge. Refus nommé si une copie ne relit pas.
  Map<String, Object?> changerDossier(String nouveau) {
    if (nouveau.trim().isEmpty) throw const DocErreur('DOSSIER_VIDE', 'Le chemin du dossier des scans est vide.', 'Saisir un chemin.');
    final n = Directory(nouveau.trim());
    try {
      n.createSync(recursive: true);
      final sonde = File(_sep(n.path, '.ecriture-ok'))..writeAsStringSync('ok');
      sonde.deleteSync();
    } on FileSystemException catch (e) {
      throw DocErreur('DOSSIER_INUTILISABLE', 'Le dossier « $nouveau » est inutilisable (${e.osError?.message ?? e.message}).', 'Choisir un dossier où ce poste peut écrire.');
    }
    final ancien = dossier;
    final rapport = sauvegarder(n.path);
    if ((rapport['alteres'] as List).isNotEmpty || (rapport['manquants'] as List).isNotEmpty) {
      throw DocErreur('COPIE_IMPOSSIBLE', 'Des fichiers sont altérés ou manquants dans l’ancien dossier : ${[...rapport['alteres'] as List, ...rapport['manquants'] as List].join(', ')}.', 'Restaurer le dossier depuis la sauvegarde avant de le déplacer.');
    }
    dossier = n.path;
    reconstruireIndex();
    return {'ancien': ancien, 'nouveau': n.path, 'copies': rapport['copies'], 'total': rapport['total']};
  }
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// Le client (poste fileul ou poste mère)
// ---------------------------------------------------------------------------------------------------------------------------------------------

/// Un appel HTTP authentifié vers la mère : méthode, chemin, corps → (statut, corps JSON).
typedef AppelMere = Future<(int, Map<String, Object?>)> Function(String methode, String chemin, Object? corps);

/// Scelle / ouvre une charge : l'enveloppe AES-GCM de la clinique pour un fileul, aucune pour la mère qui parle à son propre service sur la boucle locale.
class ScelleFichiers {
  const ScelleFichiers(this.sceller, this.ouvrir);
  final Future<Map<String, Object?>> Function(Map<String, Object?> charge, int n) sceller;
  final Future<Map<String, Object?>> Function(Map<String, Object?> enveloppe) ouvrir;
}

/// Le client des fichiers : dépose un fichier chez la mère (blocs, reprise) et le relit (blocs, empreinte recalculée à l'arrivée). Implémente [DocStockage] :
/// la migration du base64 et les écrans l'emploient sans savoir où est le dossier.
class ClientFichiers implements DocStockage {
  ClientFichiers({required this.appeler, required this.prefixe, this.scelle, this.famille = docFamillePatient, this.nomOrigine = 'scan'});

  final AppelMere appeler;

  /// `/sync/fichier` pour un fileul (jeton d'appareil), `/admin/fichiers` pour la mère (secret d'administration).
  final String prefixe;
  final ScelleFichiers? scelle;
  final String famille;
  final String nomOrigine;

  DocErreur _refus(int statut, Map<String, Object?> j) =>
      DocErreur('${j['code'] ?? 'http_$statut'}', '${j['motif'] ?? 'La mère a refusé la demande ($statut).'}', '${j['geste'] ?? 'Réessayer, ou vérifier que la mère répond.'}');

  /// Dépose [octets] chez la mère sous [nomNormalise]. Reprend là où la mère s'était arrêtée. [famille] et [nomOrigine] servent au contrôle de la mère.
  @override
  Future<void> deposer({required List<int> octets, required String sha256, required String nomNormalise, String? famille, String? nomOrigine}) async {
    final fam = famille ?? this.famille;
    final total = max(1, (octets.length + tailleBloc - 1) ~/ tailleBloc);
    final (st0, etat) = await appeler('GET', '$prefixe/etat?sha=$sha256', null);
    var depuis = st0 == 200 ? ((etat['recus'] as num?)?.toInt() ?? 0) : 0;
    if (st0 == 200 && etat['present'] == true) depuis = total; // déjà rangé : rien à renvoyer, mais le nom est vérifié par un dernier bloc vide ci-dessous
    for (var i = depuis; i < total; i++) {
      final charge = <String, Object?>{
        'sha': sha256,
        'nom': nomNormalise,
        'nomOrigine': nomOrigine ?? this.nomOrigine,
        'famille': fam,
        'taille': octets.length,
        'index': i,
        'total': total,
        'b64': base64.encode(octets.sublist(i * tailleBloc, min(octets.length, (i + 1) * tailleBloc))),
      };
      final corps = scelle == null ? {'charge': charge} : {'enveloppe': await scelle!.sceller(charge, i)};
      final (st, j) = await appeler('POST', '$prefixe/bloc', corps);
      if (st != 200) throw _refus(st, j);
    }
    if (depuis >= total) {
      // Fichier déjà présent chez la mère : on l'y RATTACHE sous ce nom (un second nom normalisé pour les mêmes octets), en renvoyant un seul bloc complet.
      final charge = <String, Object?>{'sha': sha256, 'nom': nomNormalise, 'nomOrigine': nomOrigine ?? this.nomOrigine, 'famille': fam, 'taille': octets.length, 'index': 0, 'total': 1, 'b64': base64.encode(octets), 'rattacher': true};
      final corps = scelle == null ? {'charge': charge} : {'enveloppe': await scelle!.sceller(charge, 0)};
      final (st, j) = await appeler('POST', '$prefixe/bloc', corps);
      if (st != 200) throw _refus(st, j);
    }
  }

  /// Lit le fichier d'empreinte [sha256] chez la mère, bloc par bloc ; l'empreinte du fichier reconstitué est RECALCULÉE : un fichier qui ne la porte pas
  /// n'est jamais rendu (`EMPREINTE_DIVERGENTE`). `null` si la mère ne l'a pas.
  @override
  Future<List<int>?> lire(String sha256) async {
    final tout = <int>[];
    var total = 1;
    for (var i = 0; i < total; i++) {
      final (st, j) = await appeler('GET', '$prefixe/bloc?sha=$sha256&i=$i', null);
      if (st == 404) return null;
      if (st != 200) throw _refus(st, j);
      final charge = scelle == null ? (j['charge'] as Map).cast<String, Object?>() : await scelle!.ouvrir((j['enveloppe'] as Map).cast<String, Object?>());
      total = (charge['total'] as num).toInt();
      tout.addAll(base64.decode('${charge['b64']}'));
    }
    if (docSha256(tout) != sha256) {
      throw const DocErreur('EMPREINTE_DIVERGENTE', 'Le fichier reçu de la mère ne porte pas l’empreinte de la fiche : il n’est pas rendu.', 'Réessayer ; si cela persiste, signaler à l’administrateur (contrôle des scans de la mère).');
    }
    return tout;
  }

  /// Où sont les scans ? Le chemin sur la mère et ce qu'elle tient.
  Future<Map<String, Object?>> info() async {
    final (st, j) = await appeler('GET', '$prefixe/info', null);
    if (st != 200) throw _refus(st, j);
    return j;
  }
}
