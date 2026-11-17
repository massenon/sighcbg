import 'dart:async';

import 'package:sigh_sync/sigh_sync.dart';

import 'source_pieces_fileul.dart';
import 'source_sync.dart';
import 'transcription_mobile.dart';

/// Le moteur de synchronisation d'un poste FILEUL embarqué dans l'application (même code que le banc d'essai :
/// `packages/sync_dart`). Il lit/écrit sa base locale, parle à la mère en HTTP et rattrape seul après une coupure.
/// L'interface n'en connaît que ces trois gestes : appairer, lire l'état, s'arrêter.
class MoteurFileul {
  MoteurFileul._(this._fileul);
  final Fileul _fileul;

  /// `dbChemin` = fichier SQLite du poste (`:memory:` en test). `mere` = adresse de la mère, ex. `http://192.168.1.10:9000`.
  static MoteurFileul creer(
      {required String dbChemin, required String mere, String nom = 'poste', String cleStockage = ''}) {
    final f =
        Fileul(ConfigFileul(port: 0, mere: mere, dbChemin: dbChemin, nom: nom, cleStockage: cleStockage));
    return MoteurFileul._(f);
  }

  /// Lance la boucle de synchronisation (sans serveur de commande : l'application n'expose aucun port).
  void demarrer() => unawaited(_fileul.boucle());

  String get uuid => _fileul.uuid;

  /// L'état que ce poste est seul à détenir (file des saisies non confirmées, plages, baux, étiquette) : ce qui voyage dans l'export portable d'un fileul.
  Map<String, Object?> etatPortable() => _fileul.etatPortable();

  /// Reprend l'état d'un poste exporté (poste NEUF seulement) : refus nommé sinon.
  Map<String, Object?> reprendreEtat(Map<String, Object?> etat) => _fileul.reprendreEtat(etat);

  /// Le nombre de saisies en attente de la mère, et leur liste (sans contenu : collection, fiche, type, heure) : de quoi LISTER ce qu'un import ne doit pas écraser en silence.
  List<Map<String, Object?>> fileEnAttente() => [
        for (final o in (_fileul.etatPortable()['file'] as List)) {'collection': (o as Map)['collection'], 'fiche': o['fiche'], 'type': o['type'], 'hlc': o['hlc']}
      ];

  /// Vrai quand ce poste est NEUF : rien en file, rien de synchronisé.
  bool get estNeuf => (_fileul.etatPortable()['file'] as List).isEmpty && _fileul.base.select('SELECT COUNT(*) AS n FROM confirme').first['n'] == 0;

  /// L'instant du dernier tirage de la mère (curseur > 0) : `true` si ce poste a déjà synchronisé quelque chose.
  /// L'instant du dernier cycle de synchronisation réussi (`null` : jamais).
  DateTime? get dernierSynchro => _fileul.dernierSynchro == null ? null : DateTime.fromMillisecondsSinceEpoch(_fileul.dernierSynchro!, isUtc: true);

  bool get aDejaSynchronise => _fileul.base.metaInt('curseur') > 0;

  /// Rejoue l'état de la mère depuis le début sans toucher à la file ni aux plages (après le remplacement du magasin local) : l'état CONFIRMÉ est vidé, le curseur revient à zéro.
  void resynchroniser() => _fileul.demanderResynchronisation();

  /// Le client des scans de ce poste (dépôt et lecture chez la mère, blocs scellés par la clé de clinique). `cleClinique` : la clé en hexadécimal (64 caractères) ; vide, le
  /// client refuse en le disant (`CLE_ABSENTE`).
  ClientFichiers clientFichiers(String famille, {String? cleClinique}) => _fileul.clientFichiers(famille: famille, cleClinique: cleClinique);

  /// La base de synchronisation du poste, vue par la transcription des prescriptions du mobile (E1559).
  SourcePiecesMobile get pieces => SourcePiecesFileul(_fileul);

  /// Rattache ce poste à la mère d'une clinique : redirige le moteur vers [adresse], puis consomme le code d'appairage. Refus nommé (`StateError`) si la mère
  /// refuse (code expiré, déjà utilisé…) ou ne répond pas.
  /// Rend ce que la mère rapporte d'une REPRISE d'identité (`{de, plages, baux}` : le poste remplacé, ce qu'elle a passé au nouveau), ou `null` pour un appairage ordinaire.
  Future<Map<String, Object?>?> rattacher(String adresse, String code) async {
    _fileul.rediriger(adresse);
    return appairer(code);
  }

  /// Les fiches d'une collection telles que la mère les a diffusées (état confirmé du fileul).
  Future<List<PieceSync>> liste(String collection) => pieces.liste(collection);

  /// Écrit une fiche dans le journal du poste (`creer` si la fiche est nouvelle, `modifier` sinon) ; un refus nommé de la file locale lève `StateError`.
  Map<String, Object?> ecrire(String collection, String fiche, {required bool existe, required Map<String, Object?> champs}) {
    final r = _fileul.ecrire({'collection': collection, 'fiche': fiche, 'type': existe ? 'modifier' : 'creer', 'champs': champs});
    if (r['refus'] != null) throw StateError('${r['motif'] ?? r['refus']}');
    return r;
  }

  /// Écrit une opération `restaurer` : remet en activité une fiche que la mère a archivée (RG-14).
  void restaurer(String collection, String fiche) {
    final r = _fileul.ecrire({'collection': collection, 'fiche': fiche, 'type': 'restaurer', 'champs': <String, Object?>{}});
    if (r['refus'] != null) throw StateError('${r['motif'] ?? r['refus']}');
  }

  /// Demande à la mère une PLAGE de numéros de dossier (RG-01) ; rend `(début, fin)`. Refus nommé (`StateError`) si la mère ne répond pas ou refuse. Une plage de
  /// DOSSIERS appartient à une année ([annee] : celle des dossiers à coder, séries annuelles E3830).
  Future<(int, int)> demanderPlage({int taille = 50, int minimum = 0, String nom = 'patients', int? annee}) async {
    final (statut, corps) = await _fileul.commande('POST /plage', {'nom': nom, 'taille': taille, 'minimum': minimum, if (annee != null) 'annee': annee}, const {});
    if (statut >= 400 || corps is! Map) throw StateError('la mère n’a pas alloué de plage (réponse $statut)');
    return ((corps['debut'] as num).toInt(), (corps['fin'] as num).toInt());
  }

  Future<Map<String, Object?>?> appairer(String code) async {
    final (statut, corps) =
        await _fileul.commande('POST /appairer', {'code': code}, const {});
    if (statut >= 400) {
      final c = corps is Map ? corps : const {};
      throw StateError(
          '${c['code'] ?? 'appairage_refuse'}${c['motif'] != null ? ' — ${c['motif']}' : ''}');
    }
    // Un code de REPRISE est un code d'appairage comme un autre pour le poste : c'est la mère qui sait ce qu'il désigne, et qui le rapporte.
    final r = corps is Map ? corps['reprise'] : null;
    return r is Map ? r.cast<String, Object?>() : null;
  }

  /// Les opérations que la mère a REFUSÉES (code, motif, geste), pour les dire : un refus ne se perd pas en silence.
  Future<List<Map<String, Object?>>> refusees() async {
    final (_, corps) = await _fileul.commande('GET /etat', const {}, const {});
    return [for (final r in ((corps! as Map)['a_traiter'] as List? ?? const [])) (r as Map).cast<String, Object?>()];
  }

  Future<InstantaneSync> instantane() async {
    final (_, corps) = await _fileul.commande('GET /etat', const {}, const {});
    return InstantaneSync.depuisEtat((corps! as Map).cast<String, Object?>());
  }

  SourceSyncPeriodique source(
          {Duration intervalle = const Duration(seconds: 2)}) =>
      SourceSyncPeriodique(lire: instantane, intervalle: intervalle);
}
