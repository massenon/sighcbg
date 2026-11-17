import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_sync/sigh_sync.dart';

import '../sync/moteur_fileul.dart';
import 'magasin.dart';
import 'persistance.dart';

/// L'EXPORT COMPLET PORTABLE, SON RÉIMPORT ET LA PRÉPARATION D'UNE MISE À JOUR, AU POSTE (Direction de Baguidi, 17/11/2026, décision 12 et précisions du même jour sur le fileul).
/// Les RÈGLES sont dans `sigh_domaine` (`export_portable_regles.dart`, `maj_regles.dart`), le fichier et son chiffrement dans `sigh_sync` (`export_portable.dart`) ; ici, ce que seul le poste sait :
/// où est son magasin, quelle clé de clinique il détient, s'il est mère ou fileul, si son moteur de synchronisation est neuf.
///
/// DEUX GESTES RÉSERVÉS, jamais deux noms de rôle : `base_exporter` et `base_importer` (fiche de rôle, réglables). Chaque méthode REFAIT le contrôle du droit : un bouton masqué ne protège rien.
/// L'IMPORT N'ÉCRIT JAMAIS sur la base en service : il écrit dans un dossier NEUF ; la MISE EN SERVICE est un second geste explicite, tracé, qui programme un échange de dossiers appliqué au
/// prochain démarrage ([appliquerMiseEnServiceEnAttente]) : l'ancien magasin est RENOMMÉ (jamais supprimé, RG-14). Le journal d'audit ne porte que des COMPTES, jamais une fiche.

/// Un refus : le code d'un refus nommé du domaine, ou propre au poste.
ErreurExport refusPoste(String code, String motif, String geste, [Map<String, Object?> plus = const {}]) => ErreurExport(RefusSauvegarde(code, motif, geste, plus));

class RapportExportPoste {
  RapportExportPoste(this.chemin, this.manifeste, {required this.verifie});
  final String chemin;
  final ManifesteExport manifeste;

  /// Le fichier a été RELU après écriture (déchiffré, empreinte contrôlée) : c'est la preuve qui compte pour une mise à jour.
  final bool verifie;
}

class RapportImportPoste {
  RapportImportPoste({
    required this.dossierNeuf,
    required this.manifeste,
    required this.mode,
    required this.fiches,
    required this.migrations,
    this.avertissement,
    this.copiePrealable,
    this.fileReprise = 0,
    this.fileNonReprise = const [],
    this.lignesMere = 0,
  });
  final String dossierNeuf;
  final ManifesteExport manifeste;
  final ModeImport mode;
  final int fiches;
  final int lignesMere;

  /// Les migrations de la chaîne jouées sur le contenu importé (numéros).
  final List<int> migrations;
  final AvertissementAnciennete? avertissement;

  /// La copie VÉRIFIÉE du magasin remplacé (fileul rattaché).
  final String? copiePrealable;

  /// La file d'un fileul exporté reprise sur ce poste neuf (nombre d'opérations), ou ce qui n'a PAS pu l'être (listé).
  final int fileReprise;
  final List<SaisieLocale> fileNonReprise;
}

/// Les preuves de la préparation d'une mise à jour (dernier export vérifié, dernière sauvegarde vérifiée) : un petit fichier du poste, jamais une collection synchronisée (une preuve de
/// sauvegarde vaut POUR CE POSTE).
class PreuvesPoste {
  PreuvesPoste(this.dossier);
  final String dossier;
  File get _f => File('$dossier/maj-preuves.json');

  Map<String, Object?> lire() {
    try {
      return (jsonDecode(_f.readAsStringSync()) as Map).cast<String, Object?>();
    } catch (_) {
      return {};
    }
  }

  void poser(String genre, DateTime date, {required bool verifiee, String detail = ''}) {
    final m = lire();
    m[genre] = {'date': date.toUtc().toIso8601String(), 'verifiee': verifiee, 'detail': detail};
    _f.parent.createSync(recursive: true);
    _f.writeAsStringSync(jsonEncode(m));
  }

  PreuveMaj? preuve(String genre) {
    final x = lire()[genre];
    if (x is! Map) return null;
    final d = DateTime.tryParse('${x['date']}');
    return d == null ? null : PreuveMaj(date: d, verifiee: x['verifiee'] == true, detail: '${x['detail'] ?? ''}');
  }
}

class ServiceBasePortable {
  ServiceBasePortable({
    required this.magasin,
    required this.dossierDonnees,
    required this.role,
    required this.cleClinique,
    required this.peut,
    this.rattache = _toujoursVrai,
    this.moteur,
    this.mere,
    this.cleStockage,
    this.configMere,
    this.maxHeures,
    this.version = '0.1.0',
    DateTime Function()? horloge,
  }) : horloge = horloge ?? magasin.horloge;

  static bool _toujoursVrai() => true;

  final Magasin magasin;
  final String dossierDonnees;

  /// `mere` ou `fileul` : lu À CHAQUE appel (le mode d'un poste peut changer pendant que l'application tourne).
  final String Function() role;

  /// La clé de la clinique en service sur ce poste, ou `null` (refus nommé `CLE_ABSENTE`). Jamais affichée, jamais journalisée.
  final Future<List<int>?> Function() cleClinique;

  /// Le geste réservé est-il détenu par le rôle de la session ? (la décision de la fiche, jamais un nom de rôle).
  final bool Function(String geste) peut;
  final bool Function() rattache;
  final MoteurFileul? moteur;
  final Mere? Function()? mere;
  final List<int>? cleStockage;
  final ConfigMere Function(String dbChemin, String cleBase64)? configMere;
  final int Function()? maxHeures;
  final String version;
  final DateTime Function() horloge;

  static final Expando<ServiceBasePortable> _installes = Expando<ServiceBasePortable>('ServiceBasePortable');
  static ServiceBasePortable? de(Magasin m) => _installes[m];
  void installer() => _installes[magasin] = this;

  PreuvesPoste get preuves => PreuvesPoste(dossierDonnees);

  IdentiteExport get identite => IdentiteExport(sigle: IdentiteClinique.sigle, nom: IdentiteClinique.nom, ifu: IdentiteClinique.ifu);

  void _droit(String geste) {
    if (!peut(geste)) {
      final g = gesteReserve(geste);
      throw refusPoste('GESTE_RESERVE', 'ce geste est réservé : « ${g?.libelle ?? geste} » est un droit de la fiche de rôle', 'Demander à un rôle qui détient ce droit (Rôles et permissions › Gestes réservés).');
    }
  }

  Future<List<int>> _cle() async {
    final c = await cleClinique();
    if (c == null || c.length != cleLongueur) {
      throw refusPoste('CLE_ABSENTE', 'la clé de la clinique n’est pas disponible sur ce poste : sans elle un export ne se chiffre ni ne s’ouvre',
          'Restaurer la clé depuis la copie sous scellé (« Restaurer la clé de la clinique »).');
    }
    return c;
  }

  /// Lit le fichier choisi : introuvable ou illisible est un refus NOMMÉ, jamais une exception brute à l'écran.
  Future<List<int>> _lire(String chemin) async {
    try {
      return await File(chemin).readAsBytes();
    } on FileSystemException {
      throw refusPoste('FICHIER_ILLISIBLE', 'le fichier « $chemin » est introuvable ou illisible', 'Choisir un fichier .sghx produit par « Exporter la base complète ».');
    }
  }

  Future<ContenuExport> _contenu() async {
    final r = role();
    Map<String, Object?>? sync;
    if (r == epRoleMere) {
      final m = mere?.call();
      if (m == null) {
        throw refusPoste('CONTENU_INCOMPLET', 'le service de la mère n’est pas en marche : le journal de la clinique ne peut pas être exporté, l’export serait incomplet', 'Démarrer le service de la mère, puis recommencer.');
      }
      sync = await extraireMere(m.base);
    } else {
      sync = moteur?.etatPortable();
    }
    return ContenuExport(collections: magasin.exporterCollections(), meta: await magasin.metaPersistee(), sync: sync);
  }

  /// EXPORTE la base complète dans [dossierDestination] (un fichier, nom horodaté) puis le RELIT pour le vérifier. Geste réservé `base_exporter`.
  Future<RapportExportPoste> exporter({required String dossierDestination, String prefixe = 'sigh-export'}) async {
    _droit(gesteBaseExporter);
    final cle = await _cle();
    final maintenant = horloge();
    final r = role();
    final octets = await ExportPortable.sceller(
        cle: cle,
        contenu: await _contenu(),
        role: r,
        clinique: identite,
        logicielVersion: version,
        etiquette: magasin.etiquettePoste.isNotEmpty ? magasin.etiquettePoste : magasin.poste,
        uuidSource: r == epRoleFileul ? (moteur?.uuid ?? '') : '',
        schema: magasin.schemaDesDonnees ?? schemaDonneesCourant,
        maintenant: maintenant);
    final d = Directory(dossierDestination)..createSync(recursive: true);
    final fichier = File('${d.path}/$prefixe-${IdentiteClinique.sigle}-${_horodate(maintenant)}.sghx');
    final tmp = File('${fichier.path}.tmp');
    await tmp.writeAsBytes(octets, flush: true);
    await tmp.rename(fichier.path);
    // Vérifié PAR RELECTURE du fichier écrit : un export jamais relu n'est pas une garantie.
    RapportVerification? v;
    try {
      v = await ExportPortable.verifier(await fichier.readAsBytes(), cle);
    } catch (_) {
      v = null;
    }
    final (m, _) = ExportPortable.lireManifeste(octets);
    preuves.poser('export', maintenant, verifiee: v != null, detail: fichier.uri.pathSegments.last);
    magasin.journaliser('Export de la base complète', 'CFG', 'Base', m.empreinte.substring(0, 8), null,
        {'fiches': m.total, 'ensembles': m.compteurs.length, 'schema': m.schema, 'role': r, 'verifie': v != null, 'fileEnAttente': m.fileEnAttente});
    return RapportExportPoste(fichier.path, m, verifie: v != null);
  }

  /// VÉRIFIE un export sans rien écrire : refus nommé ou le manifeste relu.
  Future<ManifesteExport> verifierFichier(String chemin) async {
    _droit(gesteBaseImporter);
    final cle = await _cle();
    return (await ExportPortable.verifier(await _lire(chemin), cle)).manifeste;
  }

  /// IMPORTE un export dans un dossier NEUF ([dossierNeuf], par défaut `import-<horodate>` sous le dossier des données) : jamais sur la base en service. Geste réservé `base_importer`.
  /// Contrôles dans l'ordre : droit, format, schéma, clinique, rôle de la source, cible neuve (refus nommés, avant même la clé), puis clé, déchiffrement, empreinte. Un fileul RATTACHÉ commence
  /// par une copie préalable VÉRIFIÉE de son magasin ; il importe comme une mère de lui-même quand il n'est pas rattaché.
  Future<RapportImportPoste> importer({required String chemin, String? dossierNeuf}) async {
    _droit(gesteBaseImporter);
    final octets = await _lire(chemin);
    final (m0, _) = ExportPortable.lireManifeste(octets);
    var neuf = dossierNeuf ?? '$dossierDonnees/import-${_horodate(horloge())}';
    // Un nom par défaut est UNIQUE : deux imports dans la même seconde n'écrasent ni ne refusent l'un l'autre (un dossier choisi à la main, lui, est refusé s'il existe).
    if (dossierNeuf == null) {
      var n = 2;
      final base = neuf;
      while (Directory(neuf).existsSync()) {
        neuf = '$base-${n++}';
      }
    }
    final r = role();
    final ratt = r == epRoleFileul && rattache();
    final refus = epControlerImport(manifeste: m0, roleCible: r, identiteLocale: identite, rattache: ratt, cibleExiste: Directory(neuf).existsSync() || File(neuf).existsSync());
    if (refus != null) throw ErreurExport(refus);
    final cle = await _cle();
    final ouvert = await ExportPortable.ouvrir(octets, cle);
    final m = ouvert.manifeste;
    final mode = epModeImport(manifeste: m, roleCible: r, rattache: ratt);

    // La mère reste l'autorité : un fileul rattaché remplace son magasin APRÈS une copie préalable vérifiée.
    String? copie;
    if (ratt) {
      try {
        final c = await exporter(dossierDestination: '$dossierDonnees/avant-import-${_horodate(horloge())}', prefixe: 'sigh-magasin-remplace');
        if (!c.verifie) throw StateError('non vérifiée');
        copie = c.chemin;
      } on ErreurExport {
        rethrow;
      } catch (_) {
        throw refusPoste('COPIE_PREALABLE_ECHOUEE', 'la copie préalable du magasin actuel n’a pas pu être écrite et vérifiée : il ne sera pas remplacé', 'Libérer de l’espace ou choisir un autre emplacement, puis recommencer.');
      }
    }

    // LA CHAÎNE DE MIGRATIONS, sur le contenu importé (schéma du fichier), avec la forme d'origine rangée à part.
    final contenuMig = ContenuDonnees(ouvert.contenu.collections, {...ouvert.contenu.meta, schemaCleMeta: m.schema});
    final mig = migrerDonnees(contenuMig, horloge: horloge, objet: 'Ce fichier');
    final persistance = PersistanceFichiers('$neuf/magasin', cle: cleStockage);
    for (final e in mig.formesAvant.entries) {
      await persistance.conserverAvantMigration(e.key, e.value);
    }
    var fiches = 0;
    for (final e in ouvert.contenu.collections.entries) {
      final f = mig.modifiees[e.key] ?? e.value;
      fiches += f.length;
      await persistance.ecrire(e.key, f);
    }
    final meta = {
      ...metaMigree(contenuMig.meta, mig),
      'formeConstantes': Magasin.formeConstantes,
      'importeDe': {'cree': m.cree, 'role': m.roleSource, 'empreinte': m.empreinte.substring(0, 16), 'le': horloge().toUtc().toIso8601String(), 'mode': mode.name},
    };
    await persistance.ecrireMeta(meta);

    // La section de synchronisation.
    var lignesMere = 0;
    var fileReprise = 0;
    final nonReprise = <SaisieLocale>[];
    final sync = ouvert.contenu.sync;
    if (r == epRoleMere) {
      if (sync == null || sync['role'] != epRoleMere) {
        throw refusPoste('CONTENU_INCOMPLET', 'ce fichier ne porte pas le journal de la mère : il ne peut pas servir de base à une mère', 'Importer un export fait sur la mère.');
      }
      final cfg = configMere?.call('$neuf/mere.db', base64.encode(cle));
      if (cfg == null) throw StateError('configMere non fournie');
      lignesMere = (await importerMereDansCibleNeuve(cfg: cfg, sync: sync, cle: cle, schemaFichier: m.schema)).lignes;
    } else if (sync != null && sync['role'] == epRoleFileul) {
      // La file d'un fileul exporté : gardée AVEC la base importée, reprise à la mise en service si ce poste est neuf, sinon listée (jamais écrasée, jamais mêlée à la file en cours).
      await File('$neuf/etat-fileul.json').writeAsString(jsonEncode(sync));
      final file = ((sync['file'] ?? const []) as List).cast<Map>();
      if (moteur != null && moteur!.estNeuf) {
        fileReprise = file.length;
      } else {
        for (final o in file) {
          nonReprise.add(SaisieLocale(collection: '${o['collection']}', fiche: '${o['fiche']}', type: '${o['type']}', quand: DateTime.fromMillisecondsSinceEpoch(((o['hlc'] ?? 0) as num).toInt(), isUtc: true)));
        }
      }
    }

    // L'AVERTISSEMENT d'ancienneté (non bloquant) : ce qui est postérieur et non synchronisé est LISTÉ et gardé avec la copie.
    AvertissementAnciennete? avert;
    if (ratt && moteur != null) {
      final enFile = [
        for (final o in moteur!.fileEnAttente())
          SaisieLocale(collection: '${o['collection']}', fiche: '${o['fiche']}', type: '${o['type']}', quand: DateTime.fromMillisecondsSinceEpoch(((o['hlc'] ?? 0) as num).toInt(), isUtc: true))
      ];
      avert = epAvertirAnciennete(exportCree: DateTime.parse(m.cree), derniereSynchro: moteur!.dernierSynchro, fileEnAttente: enFile);
      if (avert != null && copie != null) {
        await File('${File(copie).parent.path}/saisies-non-synchronisees.json').writeAsString(jsonEncode([for (final s in avert.saisies) s.toJson()]));
      }
    }
    await File('$neuf/IMPORT.json').writeAsString(jsonEncode({
      'source': m.toJson(),
      'mode': mode.name,
      'roleCible': r,
      'rattache': ratt,
      'fiches': fiches,
      'migrations': [for (final j in mig.journal) j['numero']],
      'copiePrealable': copie,
    }));
    magasin.journaliser('Import d\'une base (magasin neuf)', 'CFG', 'Base', m.empreinte.substring(0, 8), null, {
      'fiches': fiches,
      'ensembles': m.compteurs.length,
      'schemaFichier': m.schema,
      'schemaApres': mig.schemaApres,
      'migrations': mig.journal.length,
      'roleSource': m.roleSource,
      'roleCible': r,
      'mode': mode.name,
      'avertissement': avert != null,
      'saisiesListees': avert?.saisies.length ?? 0,
      'fileReprise': fileReprise,
    });
    return RapportImportPoste(
        dossierNeuf: neuf,
        manifeste: m,
        mode: mode,
        fiches: fiches,
        migrations: [for (final j in mig.journal) j['numero'] as int],
        avertissement: avert,
        copiePrealable: copie,
        fileReprise: fileReprise,
        fileNonReprise: nonReprise,
        lignesMere: lignesMere);
  }

  int get _heures => maxHeures?.call() ?? majHeuresDefaut;

  /// PROGRAMME la MISE EN SERVICE d'une base importée (second geste, explicite, tracé) : au prochain démarrage, l'ancien magasin est renommé (jamais supprimé) et la base importée prend sa
  /// place. Refus nommés : droit, motif, base importée absente, et SANS export vérifié de moins de N heures (la copie préalable du magasin remplacé). Rien ne change avant le redémarrage.
  Future<void> programmerMiseEnService({required String dossierNeuf, required String motif}) async {
    _droit(gesteBaseImporter);
    if (motif.trim().length < majMotifLongueurMin) {
      throw refusPoste('MOTIF_OBLIGATOIRE', 'le motif de la mise en service doit comporter au moins $majMotifLongueurMin caractères', 'Écrire le motif ; il est journalisé avec l’auteur et la date.');
    }
    if (!Directory('$dossierNeuf/magasin').existsSync() || !File('$dossierNeuf/IMPORT.json').existsSync()) {
      throw refusPoste('BASE_IMPORTEE_ABSENTE', 'le dossier de la base importée est introuvable ou incomplet', 'Refaire l’import dans un dossier neuf.');
    }
    final p = preuves.preuve('export');
    final v = majPreparation(maintenant: horloge(), maxHeures: _heures, sauvegarde: PreuveMaj(date: horloge(), verifiee: true), export: p);
    if (!v.autorisee) {
      throw refusPoste('MISE_EN_SERVICE_SANS_COPIE', 'avant de remplacer la base en service, une copie VÉRIFIÉE de moins de $_heures heure(s) est exigée : ${v.refus.map((x) => x.code).join(', ')}', 'Exporter la base actuelle (« Exporter la base complète »), puis recommencer.');
    }
    final info = (jsonDecode(File('$dossierNeuf/IMPORT.json').readAsStringSync()) as Map).cast<String, Object?>();
    // Le fileul reprend sa file ou se resynchronise MAINTENANT (le moteur de synchronisation reste en place, seul le magasin est échangé au redémarrage).
    var fileReprise = 0;
    if (role() == epRoleFileul && moteur != null) {
      final f = File('$dossierNeuf/etat-fileul.json');
      if (f.existsSync() && moteur!.estNeuf) {
        final r = moteur!.reprendreEtat((jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>());
        if (r['refus'] != null) throw refusPoste('${r['refus']}', '${r['motif']}', 'Reprendre l’état sur un poste neuf.');
        fileReprise = (r['repris'] as num).toInt();
      }
      if (info['mode'] == ModeImport.resynchronisation.name) moteur!.resynchroniser();
    }
    File('$dossierDonnees/$fichierMiseEnService')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'neuf': dossierNeuf, 'par': magasin.utilisateur, 'le': horloge().toUtc().toIso8601String(), 'motif': motif.trim(), 'roleCible': role(), 'fileReprise': fileReprise}));
    magasin.journaliser('Mise en service programmée d\'une base importée', 'CFG', 'Base', 'import', null, {'motif': motif.trim(), 'fileReprise': fileReprise, 'mode': info['mode'], 'redemarrage': true});
  }

  static const String fichierMiseEnService = 'mise-en-service-import.json';
  static const String fichierMiseEnServiceEffectuee = 'mise-en-service-effectuee.json';

  /// APPLIQUE, AU DÉMARRAGE et AVANT toute ouverture du magasin et de la base de la mère, la mise en service programmée : l'ancien magasin (et l'ancienne base de la mère) sont RENOMMÉS
  /// `*.avant-import-<horodate>`, jamais supprimés ; la base importée prend leur place. Rend la trace de ce qui a été fait (`null` : rien de programmé).
  static Map<String, Object?>? appliquerMiseEnServiceEnAttente(String dossierDonnees, {DateTime? maintenant}) {
    final marque = File('$dossierDonnees/$fichierMiseEnService');
    if (!marque.existsSync()) return null;
    final m = (jsonDecode(marque.readAsStringSync()) as Map).cast<String, Object?>();
    final neuf = '${m['neuf']}';
    final suffixe = '.avant-import-${_horodate(maintenant ?? DateTime.now())}';
    final fait = <String>[];
    try {
      if (!Directory('$neuf/magasin').existsSync()) throw StateError('base importée introuvable');
      final actuel = Directory('$dossierDonnees/magasin');
      if (actuel.existsSync()) {
        actuel.renameSync('$dossierDonnees/magasin$suffixe');
        fait.add('magasin');
      }
      Directory('$neuf/magasin').renameSync('$dossierDonnees/magasin');
      if (File('$neuf/mere.db').existsSync()) {
        for (final ext in ['', '-wal', '-shm']) {
          final f = File('$dossierDonnees/mere.db$ext');
          if (f.existsSync()) f.renameSync('$dossierDonnees/mere.db$ext$suffixe');
        }
        for (final ext in ['', '-wal', '-shm']) {
          final f = File('$neuf/mere.db$ext');
          if (f.existsSync()) f.renameSync('$dossierDonnees/mere.db$ext');
        }
        fait.add('mere.db');
      }
      marque.deleteSync();
      final trace = {...m, 'effectueeLe': (maintenant ?? DateTime.now()).toUtc().toIso8601String(), 'renomme': fait, 'suffixe': suffixe};
      File('$dossierDonnees/$fichierMiseEnServiceEffectuee').writeAsStringSync(jsonEncode(trace));
      return trace;
    } catch (e) {
      // Un échec ne laisse pas un poste à moitié échangé : la marque est mise de côté, le poste redémarre sur sa base d'avant, l'échec est écrit.
      final cote = File('$dossierDonnees/$fichierMiseEnService.echec');
      marque.renameSync(cote.path);
      File('$dossierDonnees/$fichierMiseEnServiceEffectuee').writeAsStringSync(jsonEncode({...m, 'echec': '$e', 'renomme': fait}));
      return {...m, 'echec': '$e'};
    }
  }

  /// Écrit au journal d'audit (RG-12) la mise en service effectuée au démarrage, puis range la trace. À appeler une fois le magasin branché.
  static void journaliserMiseEnServiceEffectuee(Magasin magasin, String dossierDonnees) {
    final f = File('$dossierDonnees/$fichierMiseEnServiceEffectuee');
    if (!f.existsSync()) return;
    final t = (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
    magasin.journaliser(t['echec'] != null ? 'Mise en service d\'une base importée : ÉCHEC' : 'Mise en service d\'une base importée', 'CFG', 'Base', 'import', null,
        {'par': t['par'], 'motif': t['motif'], 'renomme': t['renomme'], if (t['echec'] != null) 'echec': t['echec']});
    f.deleteSync();
  }

  static String _horodate(DateTime d) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${p(d.month)}${p(d.day)}-${p(d.hour)}${p(d.minute)}${p(d.second)}';
  }
}
