// LA VERSION DU FORMAT DES DONNÉES ET LA CHAÎNE DE MIGRATIONS (Direction de Baguidi, 17/11/2026, décision 12 : mise à jour du logiciel).
//
// Un logiciel qui change de version ne doit ni relire de travers un magasin écrit sous l'ancienne forme, ni écraser en silence un magasin écrit par une version plus
// récente. Le numéro de schéma est donc une CONSTANTE UNIQUE ([schemaDonneesCourant]), écrite dans la méta du magasin du poste et dans celle de la mère, lue à
// l'ouverture ; une chaîne ORDONNÉE de migrations ([migrationsDonnees]) amène un magasin ancien à la forme courante, et un magasin PLUS RÉCENT que le logiciel est
// REFUSÉ en le nommant (`SCHEMA_PLUS_RECENT`) : jamais d'écrasement, jamais de perte.
//
// Règles de la chaîne (tenues par [migrerDonnees], prouvées par `schema_donnees_test.dart`) :
//  * ORDONNÉE et CONTIGUË : les numéros vont de 1 à N sans trou ; une chaîne mal formée est une erreur de programmation, pas un état de données ;
//  * NON DESTRUCTIVE : avant qu'une migration ne touche une collection, la forme d'ORIGINE de cette collection est copiée dans [ResultatMigration.formesAvant] ; l'appelant
//    la range (le poste l'écrit sous `migrations/avant-<n>/`) AVANT d'écrire la forme convertie. Rien n'est jamais seulement converti ;
//  * IDEMPOTENTE : une migration n'est jouée que si le schéma du magasin est inférieur à son numéro ; relancer la chaîne sur un magasin déjà à jour ne change rien ;
//  * JOURNALISÉE : chaque migration jouée ajoute une entrée à `meta.migrations` (numéro, nom, date, détail), sans contenu médical (des COMPTES, jamais des fiches) ;
//  * le schéma n'avance qu'une fois la migration terminée : une migration qui échoue laisse le magasin au numéro d'avant, intact (la copie travaille sur des clones).
import '../hospitalisation/hos_constantes.dart';
import 'sauvegarde_horssite.dart' show RefusSauvegarde;

/// LE numéro de schéma des données que ce logiciel écrit. À incrémenter quand la FORME des données change (nouvelle migration en fin de [migrationsDonnees]) : jamais
/// recopié ailleurs (le poste, la mère, l'export portable et l'écran de mise à jour le lisent ici).
const int schemaDonneesCourant = 1;

/// La clé de la méta où le numéro de schéma est écrit (magasin du poste : `_meta` ; mère : table `meta`).
const String schemaCleMeta = 'schema';

/// LE TÉMOIN D'UNE MÉTA ILLISIBLE (E4603). Une méta qui EXISTE sur le disque mais ne se déchiffre pas ou n'est pas du JSON rend `{}` à la lecture ; sans ce témoin, un magasin PEUPLÉ
/// se lirait « schéma 0 » et la migration n°1 rejouerait la conversion de la diurèse (×1000), qui n'est pas idempotente. Le lecteur de méta pose ce témoin (une méta ABSENTE, elle,
/// reste légitime : un magasin d'avant la chaîne). Il n'est jamais écrit : [metaMigree] le retire.
const String schemaCleMetaIllisible = '_metaIllisible';

/// La clé de la méta où le journal des migrations jouées est tenu (liste d'entrées).
const String schemaCleJournal = 'migrations';

/// Le contenu d'un magasin tel que la chaîne le voit : ses collections (fiches complètes, archivées comprises, RG-14) et sa méta.
class ContenuDonnees {
  ContenuDonnees(this.collections, this.meta);
  final Map<String, List<Map<String, Object?>>> collections;
  final Map<String, Object?> meta;

  /// Un magasin sans aucune fiche : un poste neuf n'a rien à convertir et naît directement au schéma courant.
  bool get vide => collections.values.every((l) => l.isEmpty);
}

/// Ce qu'une migration voit de la situation de départ.
class ContexteMigration {
  const ContexteMigration({required this.meta, required this.peuple});

  /// La méta du magasin AVANT la chaîne (lecture seule).
  final Map<String, Object?> meta;

  /// Le magasin portait des fiches au départ (un poste neuf n'a rien à convertir).
  final bool peuple;
}

/// Ce qu'une migration rend : les collections qu'elle a MODIFIÉES (nom → fiches complètes) et un détail de COMPTES pour le journal.
class SortieMigration {
  const SortieMigration(this.modifiees, [this.detail = const {}]);
  final Map<String, List<Map<String, Object?>>> modifiees;
  final Map<String, Object?> detail;
}

typedef AppliquerMigration = SortieMigration Function(ContenuDonnees contenu, ContexteMigration contexte);

/// Une migration : son numéro (contigu, à partir de 1), son nom stable (journal) et son libellé lisible.
class MigrationDonnees {
  const MigrationDonnees({required this.numero, required this.nom, required this.libelle, required this.appliquer});
  final int numero;
  final String nom;
  final String libelle;
  final AppliquerMigration appliquer;
}

/// Migration n°1 : les CONSTANTES d'avant le lot B (13/11/2026) : tension « 12/8 » en deux nombres (relevés d'hospitalisation, feuilles d'observation) et diurèse
/// d'accueil des litres aux millilitres. C'est l'ancienne marque `formeConstantes` du poste, devenue le numéro 1 de la chaîne. La conversion de la diurèse ne se fait QUE
/// si le magasin porte des fiches ET n'a jamais reçu la marque `formeConstantes` : sans marque, 2 mL et 2 L se confondent ; avec elle, la conversion est déjà faite.
SortieMigration _migrerConstantes(ContenuDonnees c, ContexteMigration ctx) {
  if (!ctx.peuple) return const SortieMigration({});
  final r = hosMigrerConstantes(
      releves: c.collections['releves'] ?? const [],
      observations: c.collections['observations'] ?? const [],
      constantes: c.collections['constantes'] ?? const [],
      diureseAccueilEnLitres: ctx.meta['formeConstantes'] == null);
  return SortieMigration({for (final e in r.modifiees.entries) e.key: [for (final f in e.value) Map<String, Object?>.from(f)]}, {
    'tensionsScindees': r.tensionsScindees,
    'tensionsIllisibles': r.tensionsIllisibles,
    'diuresesConverties': r.diuresesConverties,
  });
}

/// LA CHAÎNE. On n'ajoute qu'EN FIN, avec le numéro suivant, et on incrémente [schemaDonneesCourant] du même geste ; on ne réécrit jamais une migration déjà livrée.
final List<MigrationDonnees> migrationsDonnees = [
  MigrationDonnees(
      numero: 1,
      nom: 'constantes-lot-b',
      libelle: 'Constantes : tension en deux nombres (cmHg), diurèse d’accueil en millilitres',
      appliquer: _migrerConstantes),
];

/// La marque de l'ancienne forme (`formeConstantes`, avant la chaîne) qui équivaut au schéma 1.
const int formeConstantesEquivalenteSchema1 = 2;

/// LE SCHÉMA D'UN MAGASIN, lu de sa méta. [peuple] : le magasin porte des fiches.
///  * `schema` posé : c'est lui ;
///  * absent, avec l'ancienne marque `formeConstantes` à la forme du lot B : un magasin d'AVANT la chaîne mais déjà converti, donc schéma 1 ;
///  * absent, peuplé, sans marque : un magasin d'avant le lot B, schéma 0 ;
///  * absent et vide : un magasin neuf, qui naît au schéma [courant].
/// `null` : la valeur posée n'est pas un entier lisible (refus [RefusSauvegarde] `SCHEMA_ILLISIBLE`, à lever par l'appelant).
int? schemaDeLaMeta(Map<String, Object?> meta, {required bool peuple, int courant = schemaDonneesCourant}) {
  final v = meta[schemaCleMeta];
  if (v != null) {
    if (v is int && v >= 0) return v;
    if (v is num && v == v.toInt() && v >= 0) return v.toInt();
    if (v is String) {
      final n = int.tryParse(v);
      if (n != null && n >= 0) return n;
    }
    return null;
  }
  final forme = meta['formeConstantes'];
  if (forme is num && forme >= formeConstantesEquivalenteSchema1) return 1;
  return peuple ? 0 : courant;
}

/// Le refus d'un schéma plus RÉCENT que le logiciel : NOMMÉ (le numéro lu, le numéro connu, le geste). Jamais d'ouverture, donc jamais d'écrasement.
RefusSauvegarde refusSchemaPlusRecent(int lu, {int courant = schemaDonneesCourant, String objet = 'Ce magasin'}) => RefusSauvegarde(
    'SCHEMA_PLUS_RECENT',
    '$objet est au schéma $lu des données, ce logiciel ne connaît que jusqu’au schéma $courant : l’ouvrir risquerait de l’écraser ou d’en perdre une partie',
    'Installer la version du logiciel qui l’a écrit (ou une plus récente). Rien n’a été modifié.',
    {'schemaLu': lu, 'schemaLogiciel': courant});

/// Le refus d'un numéro de schéma illisible dans la méta : on ne devine pas.
RefusSauvegarde refusSchemaIllisible(Object? valeur, {String objet = 'Ce magasin'}) => RefusSauvegarde(
    'SCHEMA_ILLISIBLE',
    '$objet porte un numéro de schéma illisible (« $valeur ») : on ne devine pas la forme de ses données',
    'Restaurer la méta du magasin depuis une sauvegarde, ou ouvrir un export portable plutôt que le magasin. Rien n’a été modifié.',
    {'valeur': '$valeur'});

/// Le refus d'un magasin PEUPLÉ dont la méta existe mais est illisible : on ne devine pas son schéma, on ne rejoue aucune conversion (E4603). Aucune écriture.
RefusSauvegarde refusMetaIllisible({String objet = 'Ce magasin'}) => RefusSauvegarde(
    'META_ILLISIBLE',
    '$objet porte des données, mais son fichier de méta (numéro de schéma) existe sans pouvoir être lu : on ne devine pas sa forme, et on ne rejoue aucune conversion qui pourrait l’abîmer',
    'Restaurer le fichier de méta depuis une sauvegarde, ou ouvrir un export portable (.sghx) plutôt que le magasin. Rien n’a été modifié.',
    const {});

/// Une erreur de schéma NOMMÉE (à lever par l'ouverture du magasin ; l'écran et le démarrage du poste la disent telle quelle).
class ErreurSchemaDonnees implements Exception {
  const ErreurSchemaDonnees(this.refus);
  final RefusSauvegarde refus;
  String get code => refus.code;
  @override
  String toString() => '${refus.code} : ${refus.motif}';
}

/// Ce que la chaîne a fait.
class ResultatMigration {
  ResultatMigration({required this.schemaAvant, required this.schemaApres});
  final int schemaAvant;
  final int schemaApres;

  /// La forme d'ORIGINE de chaque collection que la chaîne a modifiée, par numéro de migration (nom → fiches AVANT) : à ranger avant d'écrire la forme convertie.
  final Map<int, Map<String, List<Map<String, Object?>>>> formesAvant = {};

  /// Les collections à réécrire (nom → forme convertie).
  final Map<String, List<Map<String, Object?>>> modifiees = {};

  /// Les entrées du journal, une par migration jouée (sans contenu médical).
  final List<Map<String, Object?>> journal = [];
  bool get aFait => schemaApres != schemaAvant;
}

List<Map<String, Object?>> _clone(List<Map<String, Object?>> l) => [for (final f in l) Map<String, Object?>.from(_cloneProfond(f) as Map)];

Object? _cloneProfond(Object? v) {
  if (v is Map) return {for (final e in v.entries) '${e.key}': _cloneProfond(e.value)};
  if (v is List) return [for (final x in v) _cloneProfond(x)];
  return v;
}

/// Vérifie qu'une chaîne est ordonnée et contiguë à partir de 1 (erreur de programmation sinon).
void verifierChaine(List<MigrationDonnees> chaine) {
  for (var i = 0; i < chaine.length; i++) {
    if (chaine[i].numero != i + 1) {
      throw StateError('Chaîne de migrations mal formée : la migration en position ${i + 1} porte le numéro ${chaine[i].numero} (ordre contigu à partir de 1 exigé).');
    }
  }
}

/// LA GARDE D'OUVERTURE : lit le schéma du contenu et refuse (en le nommant) un schéma plus récent que [cible] ou illisible. Ne modifie rien.
int garderSchema(ContenuDonnees contenu, {int cible = schemaDonneesCourant, String objet = 'Ce magasin'}) {
  // Méta illisible : refusée SI le magasin est peuplé (un magasin neuf n'a rien à perdre ni à convertir).
  if (contenu.meta[schemaCleMetaIllisible] == true && !contenu.vide) throw ErreurSchemaDonnees(refusMetaIllisible(objet: objet));
  final s = schemaDeLaMeta(contenu.meta, peuple: !contenu.vide, courant: cible);
  if (s == null) throw ErreurSchemaDonnees(refusSchemaIllisible(contenu.meta[schemaCleMeta], objet: objet));
  if (s > cible) throw ErreurSchemaDonnees(refusSchemaPlusRecent(s, courant: cible, objet: objet));
  return s;
}

/// LA CHAÎNE EN MARCHE : amène [contenu] de son schéma à [cible] (par défaut le courant), migration après migration, sur des CLONES : [contenu] n'est jamais modifié
/// (l'appelant écrit [ResultatMigration.modifiees] et la méta rendue par [metaMigree]). Refuse un schéma plus récent ([ErreurSchemaDonnees]). [horloge] date le journal.
ResultatMigration migrerDonnees(ContenuDonnees contenu,
    {List<MigrationDonnees>? chaine, int? cible, required DateTime Function() horloge, String objet = 'Ce magasin'}) {
  final c = chaine ?? migrationsDonnees;
  final but = cible ?? (c.isEmpty ? 0 : c.length);
  verifierChaine(c);
  final depart = garderSchema(contenu, cible: but, objet: objet);
  final peuple = !contenu.vide;
  final r = ResultatMigration(schemaAvant: depart, schemaApres: depart);
  if (depart == but) return r;
  // Le travail se fait sur des clones : un échec en cours de route laisse l'original intact.
  final travail = ContenuDonnees({for (final e in contenu.collections.entries) e.key: _clone(e.value)}, Map<String, Object?>.from(contenu.meta));
  final ctx = ContexteMigration(meta: Map<String, Object?>.unmodifiable(contenu.meta), peuple: peuple);
  for (final m in c) {
    if (m.numero <= depart || m.numero > but) continue;
    final s = m.appliquer(travail, ctx);
    final avant = <String, List<Map<String, Object?>>>{};
    for (final e in s.modifiees.entries) {
      avant[e.key] = _clone(travail.collections[e.key] ?? const []);
      travail.collections[e.key] = _clone(e.value);
      r.modifiees[e.key] = travail.collections[e.key]!;
    }
    if (avant.isNotEmpty) r.formesAvant[m.numero] = avant;
    r.journal.add({
      'numero': m.numero,
      'nom': m.nom,
      'le': horloge().toUtc().toIso8601String(),
      'schemaAvant': m.numero - 1,
      'schemaApres': m.numero,
      'collectionsModifiees': [...s.modifiees.keys],
      ...s.detail,
    });
  }
  return ResultatMigration(schemaAvant: depart, schemaApres: but)
    ..formesAvant.addAll(r.formesAvant)
    ..modifiees.addAll(r.modifiees)
    ..journal.addAll(r.journal);
}

/// La méta d'un magasin APRÈS la chaîne : le schéma atteint et le journal complété. Les autres clés sont conservées telles quelles.
/// Un magasin déjà au schéma voulu et qui porte déjà son numéro est rendu inchangé (idempotence).
Map<String, Object?> metaMigree(Map<String, Object?> meta, ResultatMigration r) {
  final propre = Map<String, Object?>.from(meta)..remove(schemaCleMetaIllisible);
  if (!r.aFait && meta[schemaCleMeta] == r.schemaApres) return propre;
  return {
    ...propre,
    schemaCleMeta: r.schemaApres,
    if (r.journal.isNotEmpty) schemaCleJournal: [...((meta[schemaCleJournal] as List?) ?? const []), ...r.journal],
  };
}
