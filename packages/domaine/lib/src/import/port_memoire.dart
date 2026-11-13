/// Le PORT D'ÉCRITURE EN MÉMOIRE du moteur d'import : le même contrat que le magasin du poste (insertion EN TÊTE, archivage logique RG-14, gardes d'écriture), sans aucun poste.
///
/// Il sert à ce que la règle d'une demande d'import (`demande_import.dart`) soit rejouée, telle quelle, hors du poste : par les tests du domaine et par l'outil du banc de
/// synchronisation (`packages/sync_dart/tool/import_banc.dart`), qui fait tenir le rôle d'un poste fileul et celui d'un poste mère à deux processus distincts. Le poste, lui,
/// branche le sien sur son magasin (`PortMagasin`).
library;

import 'moteur_import.dart';
import 'profil_import.dart';

class PortImportMemoire extends PortImport {
  PortImportMemoire(Map<String, Object?> jeu,
      {this.jourFixe = '2026-11-12', this.utilisateurFixe = 'ADMIN', this.profilFixe = const ProfilImport.accordeTout(), this.prefixeId = 'X'}) {
    for (final e in jeu.entries) {
      _c[e.key] = [for (final f in (e.value as List).cast<Map>()) {...f.cast<String, Object?>()}];
    }
  }
  final String jourFixe, utilisateurFixe;
  final ProfilImport profilFixe;

  /// Le préfixe des identifiants posés par ce port : deux postes ne doivent jamais attribuer le même.
  final String prefixeId;
  final Map<String, List<FicheImport>> _c = {};

  /// Les gardes d'écriture d'une collection (`op` : `inserer`, `archiver`) : un motif refuse. Le moteur défait alors ce qu'il vient de poser.
  final Map<String, String? Function(String op, FicheImport f)> gardes = {};
  int _rang = 0;
  final journal = <String>[];

  @override
  ProfilImport get profil => profilFixe;
  @override
  List<FicheImport> toutes(String collection) => _c.putIfAbsent(collection, () => []);
  @override
  String get jour => jourFixe;
  @override
  String get utilisateur => utilisateurFixe;

  /// Un instantané JSON de tout ce que le port tient.
  Map<String, Object?> instantane() => {for (final e in _c.entries) e.key: [for (final f in e.value) {...f}]};

  @override
  FicheImport inserer(String collection, FicheImport fiche) {
    final motif = gardes[collection]?.call('inserer', fiche);
    if (motif != null) throw StateError(motif);
    final f = {'statut': 'actif', ...fiche};
    f['id'] ??= '$prefixeId${++_rang}';
    toutes(collection).insert(0, f);
    return f;
  }

  @override
  void retirer(String collection, Object? id) => toutes(collection).removeWhere((f) => f['id'] == id);

  @override
  bool archiver(String collection, Object? id, String motif) {
    final f = parId(collection, id);
    if (f == null) return false;
    if (gardes[collection]?.call('archiver', f) != null) return false;
    f['statutAvantArchivage'] = f['statut'];
    f['statut'] = 'archive';
    f['_motifArchivage'] = motif;
    return true;
  }

  @override
  void restaurer(String collection, Object? id) {
    final f = parId(collection, id);
    if (f == null) return;
    f['statut'] = f.remove('statutAvantArchivage') ?? 'actif';
  }

  @override
  void mettreAJour(String collection, Object? id, FicheImport patch) => parId(collection, id)?.addAll(patch);

  @override
  void journaliser(String action, String module, String entite, String reference, Object? avant, Object? apres) => journal.add('$action|$entite|$reference');
}
