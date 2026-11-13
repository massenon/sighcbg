/// MODULE D'IMPORTATION (IMP) : le moteur générique, port de `SIGH.importer` (prototype_html/assets/js/modules/import.js).
///
/// UN MOTEUR, DES JEUX DÉCLARATIFS (`jeux_import.dart`). Chaque jeu dit ses colonnes (type, obligatoire, référentiel de contrôle), sa clé de
/// dédoublonnage et ses règles métier ; le moteur fait le reste, toujours dans le même ordre : contrôler les colonnes, contrôler chaque cellule,
/// dédoublonner (dans le fichier, puis contre le magasin), appliquer les règles métier, contrôler le lot entier (RG-10 pour les soldes).
/// RIEN n'est écrit avant la confirmation. Un refus se NOMME : ligne, colonne, valeur, motif et geste de correction. Un fichier refusé est
/// CONSIGNÉ (lot « refusé ») et n'écrit rien. Un lot accepté s'écrit d'un seul geste : toutes les fiches ou aucune, chacune portant `source`,
/// `lotImport`, `validePar` et `dateImport`. Un lot s'ANNULE en archivant ses fiches (RG-14), jamais en les supprimant.
///
/// Le moteur ne lit ni ne parle à aucun fichier : il reçoit des LIGNES (tableaux de cellules) que la couche d'entrée-sortie du poste tire d'un
/// classeur .xlsx (paquet `excel`) ou d'un .csv. Il écrit par un PORT ([PortImport]) que le magasin du poste, la mère et les tests implémentent.
/// Les vecteurs viennent de la maquette (`prototype_html/build/vecteurs-import.js`).
library;

import '../format/recherche.dart' show normaliser;
import 'identite_lot.dart';
import 'profil_import.dart';

typedef FicheImport = Map<String, Object?>;

/// Les bornes par défaut de la taille d'un fichier d'import, MESURÉES sur le classeur du poste (`ecrireClasseur`, textes aléatoires donc peu compressibles :
/// une valeur réelle pèse moins) : 200 lignes d'inventaire = 7 Ko, 184 articles du Grand Stock = 18 Ko, 1 000 produits ou patients = 70 Ko, 2 000 courriers =
/// 120 Ko, et les 18 000 dossiers du registre papier = 1,25 Mo. Trois bornes en découlent : 512 Ko pour les jeux courts (plus de sept mille lignes : un
/// fichier plus gros n'est pas ce jeu), 1 Mo pour les référentiels, 2 Mo pour le répertoire patients (le seul qui monte à ce volume). Chaque borne se règle
/// PAR JEU dans la collection `reglages` (clé `importOctetsMax.<jeu>`).
const octetsMaxImportDefaut = 1024 * 1024;
const octetsMaxImportCourt = 512 * 1024;
const octetsMaxImportPatients = 2 * 1024 * 1024;

/// Niveaux d'un constat.
const importRefus = 'refus';
const importAvertissement = 'avertissement';

/// Un constat nommé : ligne (0 = le fichier entier), colonne, valeur lue, code stable, motif et geste de correction.
class ProblemeImport {
  const ProblemeImport({
    required this.n,
    required this.colonne,
    required this.valeur,
    required this.code,
    required this.motif,
    required this.geste,
    required this.niveau,
  });
  final int n;
  final String colonne;
  final Object? valeur;
  final String code, motif, geste, niveau;

  Map<String, Object?> versJson() => {'n': n, 'colonne': colonne, 'valeur': valeur, 'code': code, 'motif': motif, 'geste': geste, 'niveau': niveau};
  bool get estRefus => niveau == importRefus;
  ProblemeImport avecLigne(int ligne) =>
      ProblemeImport(n: ligne, colonne: colonne, valeur: valeur, code: code, motif: motif, geste: geste, niveau: niveau);
}

/// Un choix d'une colonne « liste » : [valeur] est ce qui s'écrit, [label] ce que l'agent saisit ou lit.
class ValeurListe {
  const ValeurListe(this.valeur, [String? label]) : label = label ?? valeur;
  final String valeur, label;
}

/// Ce qu'on répond quand une valeur est sous le minimum (RG-03 pour la quantité) : code, motif et geste propres à la colonne.
class SousMinImport {
  const SousMinImport(this.code, this.motif, this.geste);
  final String code, motif, geste;
}

class ColonneImport {
  const ColonneImport(
    this.cle,
    this.label,
    this.type, {
    this.obligatoire = false,
    this.liste,
    this.min,
    this.max,
    this.longueurMax,
    this.motif,
    this.motifTexte,
    this.exemple,
    this.aide,
    this.sousMin,
  });

  /// Types : `texte`, `entier`, `decimal`, `date`, `liste`, `tarif` (montant, NC ou tiret).
  final String cle, label, type;
  final bool obligatoire;
  final List<ValeurListe> Function(dynamic ctx)? liste;
  final num? min, max;
  final int? longueurMax;
  final RegExp? motif;
  final String? motifTexte, aide;
  final Object? exemple;
  final SousMinImport? sousMin;
}

/// Une ligne du fichier une fois lue : [n] est son rang dans la feuille (l'en-tête est la ligne 1).
class LigneImport {
  LigneImport(this.n, this.v, this.brut);
  final int n;
  final Map<String, Object?> v;
  final List<String> brut;
  final List<ProblemeImport> problemes = [];
  String etat = 'valide';

  /// La fiche existe déjà et l'agent a choisi « ignorer les existants » : la ligne n'écrit RIEN (elle est comptée et listée, jamais modifiée).
  bool ignoree = false;
}

/// Les choix de l'agent pour UNE analyse (le même jeu de choix est rejoué à la confirmation).
class OptionsImport {
  const OptionsImport({this.ignorerExistants = false, this.colonnesAccordees = const {}});

  /// « Ignorer les existants » : une ligne dont la fiche existe est ignorée au lieu d'être refusée. Permis SEULEMENT sur les jeux qui le déclarent
  /// ([JeuImport.ignorable]) ; demandé sur un autre jeu, le fichier est refusé en le disant.
  final bool ignorerExistants;

  /// Les clés des colonnes RÉSERVÉES ([JeuImport.colonnesReservees]) que l'agent a le droit d'importer (le droit vient de la matrice, jamais du rôle).
  final Set<String> colonnesAccordees;
}

class CompteImport {
  CompteImport({this.valides = 0, this.avertissements = 0, this.refus = 0});
  int valides, avertissements, refus;
  Map<String, Object?> versJson() => {'valides': valides, 'avertissements': avertissements, 'refus': refus};
}

/// Le résultat de l'analyse d'un fichier : rien n'est écrit.
class AnalyseImport {
  AnalyseImport(this.jeu, this.fichier, this.lignesBrutes);
  final String jeu, fichier;
  final List<List<Object?>> lignesBrutes;
  int nbLignes = 0;
  final List<LigneImport> lignes = [];
  final List<ProblemeImport> globaux = [];
  bool accepte = false;
  final CompteImport compte = CompteImport();
  String? empreinte;
  OptionsImport options = const OptionsImport();

  /// Le profil n'a pas le droit d'importer ce jeu : le moteur REFUSE (masquer un bouton ne protège rien) et le refus ne se consigne PAS (ce n'est pas un fichier qu'on ait lu).
  bool refusDroit = false;

  /// Le nombre de lignes que l'application écrirait : les lignes valides qui ne sont pas ignorées.
  int get aEcrire => lignes.where((l) => !l.ignoree).length;

  /// Les rangs des lignes ignorées (la fiche existait déjà) : jamais leurs valeurs.
  List<int> get ignorees => [for (final l in lignes) if (l.ignoree) l.n];

  /// Tous les constats à plat : ceux du fichier, puis ceux de chaque ligne.
  List<ProblemeImport> get problemes => [...globaux, for (final l in lignes) ...l.problemes];
}

/// Le PORT d'écriture du moteur : le magasin du poste, la mère ou la mémoire d'un test. Une écriture refusée par le moteur (garde d'exercice clos)
/// lève une exception ; le moteur défait alors ce qu'il vient de poser.
abstract class PortImport {
  /// Le profil qui importe : droits lus de la matrice en force (jamais un nom de rôle en dur). La mère prend celui de l'AUTEUR de la demande qu'elle traite.
  ProfilImport get profil;

  List<FicheImport> toutes(String collection);
  List<FicheImport> actives(String collection) => [
        for (final f in toutes(collection))
          if (f['statut'] != 'archive') f
      ];
  FicheImport? parId(String collection, Object? id) => toutes(collection).where((f) => f['id'] == id).firstOrNull;

  /// Date du jour, `AAAA-MM-JJ`.
  String get jour;

  /// Nom de l'agent connecté (jamais d'action anonyme, RG-12).
  String get utilisateur;

  /// Insère une fiche et rend celle qui est stockée (avec son `id`). Lève si le moteur la refuse.
  FicheImport inserer(String collection, FicheImport fiche);

  /// Retire une fiche posée dans le geste en cours (annulation d'une création, avant tout autre usage). Jamais pour une fiche déjà publiée.
  void retirer(String collection, Object? id);

  /// Archive (RG-14). Rend `false` si le moteur refuse.
  bool archiver(String collection, Object? id, String motif);
  void restaurer(String collection, Object? id);
  void mettreAJour(String collection, Object? id, FicheImport patch);
  void journaliser(String action, String module, String entite, String reference, Object? avant, Object? apres);
}

/// LOT IDEM : ce que le moteur LIT pour dire « cette fiche est déjà tenue » : les fiches nées d'une demande, archivées parce que leur lot a été DÉFAIT (annulé, ou restitué après le refus de
/// la mère), ne comptent plus. Sans cela le même fichier ne se réimporterait jamais après une annulation légitime (l'article archivé existerait encore). Une fiche archivée à la main, ou celle
/// d'un lot que personne n'a défait, continue de compter : seule la défaite d'un lot libère ses fiches. Lecture seule : toute écriture va au port d'origine.
class _VueSansLotsDefaits extends PortImport {
  _VueSansLotsDefaits(this.base) : _defaits = {for (final l in base.toutes(collectionLots)) if (l['etat'] == 'annule' || l['etat'] == 'restitue') l['reference']};
  final PortImport base;
  final Set<Object?> _defaits;
  @override
  ProfilImport get profil => base.profil;
  @override
  String get jour => base.jour;
  @override
  String get utilisateur => base.utilisateur;
  @override
  List<FicheImport> toutes(String collection) => collection == collectionLots
      ? base.toutes(collection)
      : [
          for (final f in base.toutes(collection))
            if (!(f['statut'] == 'archive' && f[champSerieDemande] != null && _defaits.contains(f['lotImport']))) f
        ];
  @override
  FicheImport inserer(String collection, FicheImport fiche) => base.inserer(collection, fiche);
  @override
  void retirer(String collection, Object? id) => base.retirer(collection, id);
  @override
  bool archiver(String collection, Object? id, String motif) => base.archiver(collection, id, motif);
  @override
  void restaurer(String collection, Object? id) => base.restaurer(collection, id);
  @override
  void mettreAJour(String collection, Object? id, FicheImport patch) => base.mettreAJour(collection, id, patch);
  @override
  void journaliser(String action, String module, String entite, String reference, Object? avant, Object? apres) => base.journaliser(action, module, entite, reference, avant, apres);
}

/// Refus nommé d'une annulation ou d'une application : code stable, motif et geste.
class ResultatImport {
  const ResultatImport.ok({this.lot, this.ecrits = 0, this.archives = 0, this.analyse})
      : ok = true,
        code = null,
        motif = null,
        geste = null;
  const ResultatImport.refus(this.code, this.motif, this.geste, {this.lot, this.analyse})
      : ok = false,
        ecrits = 0,
        archives = 0;
  final bool ok;
  final String? code, motif, geste;
  final FicheImport? lot;
  final int ecrits, archives;
  final AnalyseImport? analyse;
}

/// LOT IMP-E : ce que la restitution propre à un jeu a fait : les fiches archivées et celles qu'il a GARDÉES (`{collection, id, code, motif}`, une pièce émise ne se réécrit jamais).
typedef RestitutionJeu = ({int archives, List<Map<String, Object?>> gardees});

/// Une dépendance qui interdit l'annulation d'un lot (un acte s'appuie déjà sur ses fiches).
class DependanceImport {
  const DependanceImport(this.code, this.motif, this.geste);
  final String code, motif, geste;
}

typedef EcrireFiche = FicheImport Function(String collection, FicheImport fiche);

/// Un jeu d'import, déclaratif. Les fonctions reçoivent le contexte (ce que le magasin sait déjà) lu UNE fois par analyse.
class JeuImport {
  const JeuImport({
    required this.id,
    required this.ecran,
    required this.libelle,
    required this.module,
    required this.statut,
    required this.description,
    required this.source,
    required this.cibles,
    required this.fichierModele,
    required this.colonnes,
    required this.contexte,
    required this.cle,
    required this.existe,
    required this.regles,
    required this.ecrire,
    required this.dependances,
    this.limite,
    this.gesteExiste,
    this.reglesLot,
    this.ignorable = false,
    this.restreint = false,
    this.colonnesReservees = const {},
    this.octetsMaxDefaut = octetsMaxImportDefaut,
    this.restituer,
  });
  final String id, ecran, libelle, module, statut, description, source, fichierModele;
  final String? limite, gesteExiste;
  final List<String> cibles;

  /// « Ignorer les existants » est-il permis ? Seulement produits, fournisseurs, emplacements, courriers : jamais sur les patients, les comptes ni les
  /// pièces, où une ligne existante est un doublon à corriger, pas à taire.
  final bool ignorable;

  /// La SENSIBILITÉ du jeu (lot IMP-C) : un jeu RESTREINT porte des données nominatives, de rémunération, de comptabilité ou de stock vivant (patients, personnel, soldes d'ouverture,
  /// stock initial, transferts, comptage d'inventaire, courriers). Il ne passe JAMAIS par une demande d'import à la mère (les lignes du fichier ne voyagent pas dans une fiche partagée,
  /// RG-13) et ses refus ne citent jamais une valeur de cellule hors du poste qui l'importe.
  final bool restreint;

  /// Les colonnes qu'un seul profil peut importer (le salaire de base : droit paie). Le droit se lit dans la matrice ; sans lui la colonne est absente du
  /// modèle et, présente dans le fichier, REJETÉE en la nommant.
  final Set<String> colonnesReservees;

  /// La borne de taille d'un fichier de CE jeu, en octets, quand aucun réglage ne la fixe (`reglages`, par jeu).
  final int octetsMaxDefaut;

  /// Les colonnes que ce profil peut voir et remplir : les colonnes réservées en sont retirées sans le droit correspondant.
  List<ColonneImport> colonnesPour(Set<String> accordees) => [for (final c in colonnes) if (!colonnesReservees.contains(c.cle) || accordees.contains(c.cle)) c];
  final List<ColonneImport> colonnes;
  final dynamic Function(PortImport port) contexte;
  final List<String> Function(Map<String, Object?> v) cle;
  final String? Function(Map<String, Object?> v, dynamic ctx) existe;
  final List<ProblemeImport> Function(Map<String, Object?> v, dynamic ctx, Map<String, Object?> sc, int n) regles;
  final List<ProblemeImport> Function(List<LigneImport> lignes, dynamic ctx)? reglesLot;
  final void Function(List<LigneImport> lignes, EcrireFiche ecrire, FicheImport lot, dynamic ctx, PortImport port) ecrire;
  final DependanceImport? Function(FicheImport lot, PortImport port) dependances;

  /// LOT IMP-E : une écriture de fileul que la mère REFUSE se restitue par l'archivage de ses fiches (RG-14) ; un jeu qui porte des QUANTITÉS (le Grand Stock) ne peut pas s'en tenir là :
  /// un mouvement écrit ne se réécrit pas (il se contre-passe par un mouvement inverse nommé), un stock ne devient jamais négatif (RG-03) et un article déjà sorti ne se restitue pas.
  /// [libelleMotif] : le motif d'archivage ; [motifMarque] : le motif de la mère, posé sur les fiches gardées.
  final RestitutionJeu Function(FicheImport lot, String libelleMotif, String motifMarque, PortImport port)? restituer;

  bool get supporte => statut == 'supporte';
}

/// Le constat d'un champ dans une règle de ligne (la ligne est posée par le moteur).
ProblemeImport constat(String colonne, Object? valeur, String code, String niveau, String motif, String geste) =>
    ProblemeImport(n: 0, colonne: colonne, valeur: valeur, code: code, motif: motif, geste: geste, niveau: niveau);

// --- Outils -----------------------------------------------------------------------------------------------------------------------

/// Une cellule en texte, comme `String(v)` de la maquette : un nombre entier s'écrit sans décimale.
String texteDe(Object? v) {
  if (v == null) return '';
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt().toString();
  return '$v';
}

Object? _nettoyer(Object? v) => v is String ? v.replaceAll(RegExp('[\u00A0\u202F]'), ' ').trim() : v;
bool _vide(Object? v) => v == null || (v is String && v.trim().isEmpty);

bool _dateValide(int a, int m, int j) {
  final d = DateTime.utc(a, m, j);
  return d.year == a && d.month == m && d.day == j;
}

String _deux(int n) => n.toString().padLeft(2, '0');

/// `X.versDate` : un numéro de série Excel (système 1900) en `AAAA-MM-JJ`. Le jour 60 d'Excel (29/02/1900) n'a jamais existé.
String? importVersDate(num n) {
  final s = n.floor();
  if (s < 1) return null;
  final d = DateTime.utc(1899, 12, 30).add(Duration(days: s > 59 ? s : s + 1));
  return '${d.year.toString().padLeft(4, '0')}-${_deux(d.month)}-${_deux(d.day)}';
}

/// Jours entiers entre deux dates ISO, sans heure.
int importJoursEntre(String a, String b) {
  DateTime u(String x) => DateTime.utc(int.parse(x.substring(0, 4)), int.parse(x.substring(5, 7)), int.parse(x.substring(8, 10)));
  return (u(b).difference(u(a)).inHours / 24).round();
}

int importAgeAu(String naissance, String jour) {
  final a = (importJoursEntre(naissance, jour) / 365.25).floor();
  return a < 0 ? 0 : a;
}

num _entierSiPossible(num n) => n == n.truncate() ? n.toInt() : n;

List<ValeurListe> valeursListe(ColonneImport c, dynamic ctx) => c.liste == null ? const [] : c.liste!(ctx);

/// Le résultat du typage d'une cellule : vide, une valeur, ou une erreur nommée.
class _Cellule {
  _Cellule.vide()
      : vide = true,
        valeur = null,
        erreur = null;
  _Cellule.valeur(this.valeur)
      : vide = false,
        erreur = null;
  _Cellule.erreur(this.erreur)
      : vide = false,
        valeur = null;
  final bool vide;
  final Object? valeur;
  final ProblemeImport? erreur;
}

ProblemeImport _err(String code, String motif, String geste) =>
    ProblemeImport(n: 0, colonne: '', valeur: '', code: code, motif: motif, geste: geste, niveau: importRefus);

_Cellule _lireCellule(ColonneImport col, Object? brut, dynamic ctx) {
  final v = _nettoyer(brut);
  if (_vide(v)) return _Cellule.vide();
  switch (col.type) {
    case 'texte':
      final t = texteDe(v);
      if (col.motif != null && !col.motif!.hasMatch(t)) {
        return _Cellule.erreur(_err('FORMAT_INVALIDE', col.motifTexte ?? 'format non conforme', 'Corrigez la valeur selon le format indiqué dans l’onglet Instructions.'));
      }
      if (col.longueurMax != null && t.length > col.longueurMax!) {
        return _Cellule.erreur(_err('TROP_LONG', 'texte de ${t.length} caractères (maximum ${col.longueurMax})', 'Raccourcissez la valeur à ${col.longueurMax} caractères au plus.'));
      }
      return _Cellule.valeur(t);
    case 'entier':
    case 'decimal':
      num? n;
      if (v is num) {
        n = v;
      } else {
        final s = texteDe(v).replaceAll(RegExp(r'\s'), '').replaceFirst(',', '.');
        n = RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s) ? num.parse(s) : null;
      }
      if (n == null || (n is double && !n.isFinite)) {
        return _Cellule.erreur(_err('TYPE_INVALIDE', 'nombre attendu, « ${texteDe(v)} » n’en est pas un', 'Saisissez un nombre sans lettre ni symbole monétaire.'));
      }
      if (col.type == 'entier' && n != n.truncate()) {
        return _Cellule.erreur(_err('TYPE_INVALIDE', 'nombre entier attendu, « ${texteDe(v)} » porte une décimale', 'Arrondissez à l’unité (le franc CFA n’a pas de décimale).'));
      }
      if (col.min != null && n < col.min!) {
        if (col.sousMin != null) return _Cellule.erreur(_err(col.sousMin!.code, col.sousMin!.motif, col.sousMin!.geste));
        return _Cellule.erreur(_err('HORS_BORNES', 'valeur ${_entierSiPossible(n)} inférieure au minimum ${col.min}', 'Saisissez une valeur d’au moins ${col.min}.'));
      }
      if (col.max != null && n > col.max!) {
        return _Cellule.erreur(_err('HORS_BORNES', 'valeur ${_entierSiPossible(n)} supérieure au maximum ${col.max}', 'Saisissez une valeur d’au plus ${col.max}.'));
      }
      return _Cellule.valeur(_entierSiPossible(n));
    case 'date':
      String? iso;
      if (v is num) {
        iso = importVersDate(v);
      } else {
        final t = texteDe(v);
        final m1 = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
        final m2 = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(t);
        if (m1 != null && _dateValide(int.parse(m1[1]!), int.parse(m1[2]!), int.parse(m1[3]!))) {
          iso = '${m1[1]}-${m1[2]}-${m1[3]}';
        } else if (m2 != null && _dateValide(int.parse(m2[3]!), int.parse(m2[2]!), int.parse(m2[1]!))) {
          iso = '${m2[3]}-${_deux(int.parse(m2[2]!))}-${_deux(int.parse(m2[1]!))}';
        }
      }
      if (iso == null) {
        return _Cellule.erreur(_err('TYPE_INVALIDE', 'date attendue, « ${texteDe(v)} » n’en est pas une', 'Saisissez la date au format AAAA-MM-JJ ou JJ/MM/AAAA.'));
      }
      return _Cellule.valeur(iso);
    case 'liste':
      final choix = valeursListe(col, ctx);
      final cle = normaliser(texteDe(v)).trim();
      final trouve = choix.where((c) => normaliser(c.valeur) == cle || normaliser(c.label) == cle).firstOrNull;
      if (trouve == null) {
        return _Cellule.erreur(_err('VALEUR_HORS_LISTE', '« ${texteDe(v)} » n’est pas une valeur permise',
            'Choisissez parmi : ${choix.take(8).map((c) => c.label).join(', ')}${choix.length > 8 ? ', …' : ''}.'));
      }
      return _Cellule.valeur(trouve.valeur);
    case 'tarif':
      final tv = texteDe(v).trim();
      if (RegExp('^(-|\u2013|\u2014)\$').hasMatch(tv)) return _Cellule.valeur({'etat': 'manquant'});
      if (RegExp(r'^(nc|non couvert)$', caseSensitive: false).hasMatch(tv)) return _Cellule.valeur({'etat': 'nc'});
      final nn = v is num ? v : num.tryParse(tv.replaceAll(RegExp(r'\s'), '').replaceFirst(',', '.'));
      if (nn == null || !nn.isFinite || nn != nn.truncate() || nn < 0) {
        return _Cellule.erreur(_err('TYPE_INVALIDE', '« ${texteDe(v)} » n’est ni un montant entier, ni NC, ni un tiret', 'Saisissez un montant en francs, NC (non couvert) ou un tiret (valeur manquante).'));
      }
      return _Cellule.valeur({'etat': 'montant', 'montant': nn.toInt()});
  }
  return _Cellule.valeur(v);
}

String _clefEntete(Object? s) => normaliser(texteDe(s).replaceAll('*', '')).replaceAll(RegExp(r'\s+'), ' ').trim();

List<Object?> ligneExemple(JeuImport j, [List<ColonneImport>? colonnes]) => [for (final c in colonnes ?? j.colonnes) c.exemple ?? ''];

// --- Analyse ---------------------------------------------------------------------------------------------------------------------

// --- Le droit ---------------------------------------------------------------------------------------------------------------------

/// Un refus de droit se NOMME : le profil, le jeu, le geste. [geste] : `importer` (voir ET éditer l'écran du jeu) ou `annuler` (arbitrer les lots : le droit d'annuler sur `imp-accueil`, comme le bouton de l'historique).
/// Rend `null` quand le droit est détenu. Le droit est celui de la MATRICE EN FORCE, lu du profil : jamais un nom de rôle, jamais déduit d'une présentation.
ResultatImport? refusDroitImport(JeuImport j, String geste, PortImport port) {
  final p = port.profil;
  final ok = geste == 'annuler' ? p.arbitreLesLots : p.peutImporterEcran(j.ecran);
  if (ok) return null;
    return ResultatImport.refus(
      'DROIT_IMPORT_REFUSE',
      geste == 'annuler'
          ? 'le profil « ${p.nom} » ne détient pas le droit d’annuler un lot (droit d’annuler sur l’écran « $ecranLotsImport » dans la matrice)'
          : 'le profil « ${p.nom} » ne détient pas le droit d’importer le jeu « ${j.libelle} » (voir et éditer l’écran « ${j.ecran} » dans la matrice)',
      'Demandez à un administrateur d’accorder ce droit au profil dans « Rôles et permissions », ou confiez l’import à un profil qui le détient.');
}

/// Analyse des lignes (la première est l'en-tête) contre un jeu. [port] fournit le contexte ; RIEN n'est écrit.
AnalyseImport analyserLignes(JeuImport j, List<List<Object?>> lignes, String fichier, PortImport port, {OptionsImport options = const OptionsImport()}) {
  final res = AnalyseImport(j.id, fichier, lignes)..options = options;
  void globalement(String code, String colonne, String motif, String geste, [String niveau = importRefus, Object? valeur = '']) {
    res.globaux.add(ProblemeImport(n: 0, colonne: colonne, valeur: valeur, code: code, motif: motif, geste: geste, niveau: niveau));
  }

  final rd = refusDroitImport(j, 'importer', port);
  if (rd != null) {
    res.refusDroit = true;
    globalement(rd.code!, '', rd.motif!, rd.geste!);
    return res;
  }
  if (options.ignorerExistants && !j.ignorable) {
    globalement('IGNORER_INTERDIT', '', '« Ignorer les existants » n’est pas permis sur le jeu « ${j.libelle} » : une ligne dont la fiche existe y est un doublon à corriger, pas à taire',
        'Décochez « Ignorer les existants », retirez du fichier les lignes déjà enregistrées, puis recommencez.');
    return res;
  }
  if (lignes.isEmpty) {
    globalement('FICHIER_VIDE', '', 'le fichier ne contient aucune ligne', 'Téléchargez le modèle, remplissez l’onglet Données et téléversez-le de nouveau.');
    return res;
  }
  final entete = [for (final h in lignes.first) _clefEntete(h)];
  final idx = <String, int>{};
  final manquantes = <ColonneImport>[];
  // Les colonnes RÉSERVÉES sans le droit correspondant : elles ne font pas partie du modèle de ce profil ; présentes dans le fichier, elles sont REJETÉES en les nommant.
  final cols = j.colonnesPour(options.colonnesAccordees);
  final reservees = [for (final c in j.colonnes) if (!cols.contains(c)) c];
  for (final c in reservees) {
    if (entete.contains(_clefEntete(c.label))) {
      globalement('COLONNE_RESERVEE', c.label, 'la colonne « ${c.label} » est réservée à un profil qui en a le droit : elle est rejetée',
          'Retirez la colonne « ${c.label} » du fichier (le modèle de votre profil ne la porte pas), puis recommencez.');
    }
  }
  if (res.globaux.isNotEmpty) return res;
  for (final c in cols) {
    final i = entete.indexOf(_clefEntete(c.label));
    if (i < 0) {
      if (c.obligatoire) {
        manquantes.add(c);
      } else {
        globalement('COLONNE_ABSENTE', c.label, 'colonne facultative « ${c.label} » absente du fichier', 'Ses valeurs resteront vides ; ajoutez-la au besoin.', importAvertissement);
      }
    } else {
      idx[c.cle] = i;
    }
  }
  if (manquantes.isNotEmpty) {
    for (final c in manquantes) {
      globalement('COLONNE_MANQUANTE', c.label, 'colonne obligatoire « ${c.label} » absente de la première ligne du fichier',
          'Ajoutez la colonne « ${c.label} » en respectant l’orthographe exacte du modèle, ou téléchargez le modèle de nouveau.');
    }
    return res;
  }
  final connus = {for (final c in cols) _clefEntete(c.label)};
  for (final h in lignes.first) {
    if (!_vide(h) && !connus.contains(_clefEntete(h))) {
      globalement('COLONNE_IGNOREE', texteDe(h), 'colonne « ${texteDe(h)} » inconnue : elle est ignorée', 'Retirez-la du fichier si elle est inutile.', importAvertissement);
    }
  }
  final ctx = j.contexte(_VueSansLotsDefaits(port));
  final sc = <String, Object?>{'articles': <String, Map<String, Object?>>{}};
  final exemple = [for (final x in ligneExemple(j, cols)) texteDe(x).trim()];
  final vus = <String, int>{};
  // LOT IDEM : ce fichier est-il DÉJÀ tenu ? Une fiche active écrite par une demande porte l'identité de CONTENU de son lot : le même inventaire (peu importe le fileul, le moment ou le
  // format) est reconnu comme le même lot. Ses lignes ne sont alors ni refusées ni réécrites : elles sont IGNORÉES et NOMMÉES, jamais comptées deux fois.
  final identiteDuFichier = identiteLotImport(j.id, lignes);
  String? lotTenu;
  for (final c in j.cibles) {
    for (final f in port.toutes(c)) {
      if (f[champIdentiteLot] == identiteDuFichier && f['statut'] != 'archive') {
        lotTenu = '${f[champSerieDemande] ?? ''}';
        break;
      }
    }
    if (lotTenu != null) break;
  }
  for (var r = 1; r < lignes.length; r++) {
    final brute = lignes[r];
    if (brute.every(_vide)) continue;
    Object? cellule(ColonneImport c) {
      final i = idx[c.cle];
      // Une colonne facultative absente du fichier (avertie plus haut) se lit vide.
      return i != null && i < brute.length ? brute[i] : '';
    }

    final lecture = [for (final c in cols) texteDe(_nettoyer(cellule(c) ?? '')).trim()];
    if (r == 1 && lecture.join('|') == exemple.join('|')) continue; // la ligne d'exemple du modèle, restée telle quelle
    final n = r + 1;
    final ligne = LigneImport(n, {}, lecture);
    var ok = true;
    for (final c in cols) {
      final b = cellule(c);
      final lc = _lireCellule(c, b, ctx);
      if (lc.erreur != null) {
        ok = false;
        final e = lc.erreur!;
        ligne.problemes.add(ProblemeImport(n: n, colonne: c.label, valeur: texteDe(b), code: e.code, motif: e.motif, geste: e.geste, niveau: importRefus));
        ligne.v[c.cle] = null;
      } else if (lc.vide) {
        ligne.v[c.cle] = null;
        if (c.obligatoire) {
          ok = false;
          ligne.problemes.add(ProblemeImport(
              n: n, colonne: c.label, valeur: '', code: 'CHAMP_OBLIGATOIRE', motif: 'valeur obligatoire absente', geste: 'Renseignez la colonne « ${c.label} » de la ligne $n.', niveau: importRefus));
        }
      } else {
        ligne.v[c.cle] = lc.valeur;
      }
    }
    if (ok) {
      final cles = j.cle(ligne.v);
      int? doublon;
      for (final k in cles) {
        if (doublon == null && vus.containsKey(k)) doublon = vus[k];
      }
      if (doublon != null) {
        ligne.problemes.add(ProblemeImport(
            n: n, colonne: cols.first.label, valeur: lecture.first, code: 'DOUBLON_FICHIER', niveau: importRefus, motif: 'identique à la ligne $doublon du même fichier', geste: 'Retirez l’une des deux lignes.'));
      } else {
        for (final k in cles) {
          vus[k] = n;
        }
      }
      final existe = j.existe(ligne.v, ctx);
      if (existe != null && lotTenu != null && doublon == null) {
        ligne.ignoree = true;
        ligne.problemes.add(ProblemeImport(
            n: n,
            colonne: cols.first.label,
            valeur: lecture.first,
            code: 'LOT_DEJA_IMPORTE',
            niveau: importAvertissement,
            motif: 'ce fichier est déjà importé : la fiche existe par le lot de série $lotTenu (même contenu)',
            geste: 'Rien à faire : le fichier est déjà dans le magasin, il n’est ni réécrit ni compté deux fois.'));
      } else if (existe != null && options.ignorerExistants) {
        // « Ignorer les existants » : la ligne est listée, comptée, et n'écrit rien. La fiche existante n'est JAMAIS modifiée.
        ligne.ignoree = true;
        ligne.problemes.add(ProblemeImport(
            n: n, colonne: cols.first.label, valeur: lecture.first, code: 'IGNORE_EXISTANT', niveau: importAvertissement, motif: existe, geste: 'Ligne ignorée : la fiche existante n’est pas modifiée.'));
      } else {
        if (existe != null) {
          ligne.problemes.add(ProblemeImport(
              n: n, colonne: cols.first.label, valeur: lecture.first, code: 'DOUBLON_MAGASIN', niveau: importRefus, motif: existe, geste: j.gesteExiste ?? 'Retirez la ligne.'));
        }
        for (final p in j.regles(ligne.v, ctx, sc, n)) {
          ligne.problemes.add(p.avecLigne(n));
        }
      }
    }
    ligne.etat = ligne.problemes.any((p) => p.estRefus) ? 'refus' : (ligne.problemes.isNotEmpty ? 'avertissement' : 'valide');
    res.lignes.add(ligne);
  }
  res.nbLignes = res.lignes.length;
  if (res.nbLignes == 0) {
    globalement('FICHIER_VIDE', '', 'aucune ligne de données (la ligne d’exemple du modèle n’est pas importée)', 'Remplacez la ligne d’exemple par vos données, ou ajoutez des lignes.');
    return res;
  }
  if (j.reglesLot != null && !res.lignes.any((l) => l.etat == 'refus')) {
    res.globaux.addAll(j.reglesLot!([for (final l in res.lignes) if (!l.ignoree) l], ctx));
  }
  for (final l in res.lignes) {
    if (l.etat == 'refus') {
      res.compte.refus++;
    } else if (l.etat == 'avertissement') {
      res.compte.avertissements++;
    } else {
      res.compte.valides++;
    }
  }
  res.accepte = !res.globaux.any((p) => p.estRefus) && res.compte.refus == 0 && res.nbLignes > 0;
  return res;
}

/// L'analyse d'un fichier déjà lu en lignes, ou d'un fichier illisible (le lecteur du poste rend alors [motifIllisible]).
AnalyseImport analyserFichier(JeuImport j, List<List<Object?>>? lignes, String fichier, PortImport port,
    {String? motifIllisible, String? empreinte, OptionsImport options = const OptionsImport(), int? octets, int? octetsMax}) {
  AnalyseImport a;
  final rd = refusDroitImport(j, 'importer', port);
  if (rd != null) {
    // Le droit se vérifie AVANT toute lecture du fichier (taille, format) : un profil sans droit n'apprend rien de ce qu'il a déposé.
    a = AnalyseImport(j.id, fichier, const [])
      ..options = options
      ..refusDroit = true;
    a.globaux.add(ProblemeImport(n: 0, colonne: '', valeur: '', code: rd.code!, niveau: importRefus, motif: rd.motif!, geste: rd.geste!));
    return a;
  }
  String ko(int n) => (n / 1024).toStringAsFixed(n < 10 * 1024 ? 1 : 0).replaceFirst('.', ',');
  if (octets != null && octetsMax != null && octets > octetsMax) {
    // La borne se vérifie AVANT toute lecture : un fichier qui dépasse n'est pas analysé, il est refusé et consigné.
    a = AnalyseImport(j.id, fichier, const [])..options = options;
    a.globaux.add(ProblemeImport(
        n: 0,
        colonne: '',
        valeur: '',
        code: 'FICHIER_TROP_GROS',
        niveau: importRefus,
        motif: 'fichier de ${ko(octets)} Ko : au-delà de la borne de ${ko(octetsMax)} Ko fixée pour le jeu « ${j.libelle} »',
        geste: 'Scindez le fichier en plusieurs lots, ou demandez à l’administrateur de relever la borne de ce jeu (réglage « Taille maximale d’un fichier d’import »).'));
  } else if (lignes == null) {
    a = AnalyseImport(j.id, fichier, const [])..options = options;
    a.globaux.add(ProblemeImport(
        n: 0,
        colonne: '',
        valeur: fichier,
        code: 'FORMAT_FICHIER',
        niveau: importRefus,
        motif: 'fichier illisible : ${motifIllisible ?? 'format inconnu'}',
        geste: 'Déposez un classeur .xlsx (modèle téléchargé) ou un fichier .csv encodé en UTF-8.'));
  } else {
    a = analyserLignes(j, lignes, fichier, port, options: options);
  }
  a.empreinte = empreinte;
  return a;
}

// --- Lots -----------------------------------------------------------------------------------------------------------------------

const collectionLots = 'lotsImportation';

String referenceLot(PortImport port) {
  final an = port.jour.substring(0, 4);
  var max = 0;
  for (final l in port.toutes(collectionLots)) {
    final m = RegExp(r'^IMP-(\d{4})-(\d+)$').firstMatch('${l['reference'] ?? ''}');
    if (m != null && m[1] == an) {
      final k = int.parse(m[2]!);
      if (k > max) max = k;
    }
  }
  return 'IMP-$an-${(max + 1).toString().padLeft(3, '0')}';
}

/// Les constats que le LOT conserve : le rang de la ligne, la colonne, le code et le niveau, JAMAIS la valeur lue ni le motif (qui la cite). L'historique
/// des lots est lu par d'autres que l'auteur du fichier (la DAF, l'administrateur) : il dit OÙ ça a coincé, pas CE que contenait la cellule.
List<Map<String, Object?>> _erreursPlafonnees(List<ProblemeImport> ps) =>
    [for (final p in ps.take(100)) {'n': p.n, 'colonne': p.colonne, 'code': p.code, 'niveau': p.niveau, 'geste': p.geste}];

/// Consigne un fichier REFUSÉ : une fiche de lot « refusé » ; aucune donnée métier n'est écrite. Rend `null` pour un refus de droit (rien à consigner).
FicheImport? consigner(JeuImport j, AnalyseImport a, PortImport port) {
  // Un refus de DROIT ne se consigne pas : aucun fichier n'a été lu, et l'historique ne doit pas se remplir des essais d'un profil sans droit.
  if (a.refusDroit) return null;
  final ps = a.problemes;
  final lot = port.inserer(collectionLots, {
    'reference': referenceLot(port),
    'jeu': j.id,
    'jeuLibelle': j.libelle,
    'fichier': a.fichier,
    'empreinte': a.empreinte,
    'date': port.jour,
    'par': port.utilisateur,
    'etat': 'refuse',
    'nbLignes': a.nbLignes,
    'nbAvertissements': a.compte.avertissements,
    'nbRefus': a.compte.refus + a.globaux.where((p) => p.estRefus).length,
    'ecrits': <Object?>[],
    'erreurs': _erreursPlafonnees(ps),
    'erreursTotal': ps.length,
    'ignores': a.ignorees,
  });
  port.journaliser('Import refusé', 'IMP', 'LotImport', '${lot['reference']}', null, {'jeu': j.id, 'fichier': a.fichier, 'refus': lot['nbRefus']});
  return lot;
}

/// Applique un lot ACCEPTÉ d'un seul geste : toutes les fiches ou aucune. L'analyse est REJOUÉE sur les lignes d'origine (le magasin a pu changer
/// entre l'analyse et la confirmation) ; en cas d'échec d'écriture, ce qui vient d'être posé est retiré et le fichier est consigné.
ResultatImport appliquer(JeuImport j, AnalyseImport analyse, PortImport port) {
  if (!analyse.accepte) {
    return const ResultatImport.refus('ANALYSE_REFUSEE', 'le fichier n’a pas passé l’analyse', 'Corrigez les refus listés, puis téléversez de nouveau.');
  }
  final rd = refusDroitImport(j, 'importer', port);
  if (rd != null) return rd;
  final rejeu = analyserLignes(j, analyse.lignesBrutes, analyse.fichier, port, options: analyse.options)..empreinte = analyse.empreinte;
  if (!rejeu.accepte) {
    final c = consigner(j, rejeu, port)!;
    return ResultatImport.refus('MAGASIN_CHANGE', 'le magasin a changé depuis l’analyse ; le fichier est refusé et consigné (${c['reference']})',
        'Relisez le rapport du lot ${c['reference']} et téléversez de nouveau.',
        lot: c, analyse: rejeu);
  }
  if (rejeu.aEcrire == 0 && rejeu.lignes.isNotEmpty && rejeu.lignes.every((l) => l.ignoree) && rejeu.problemes.any((p) => p.code == 'LOT_DEJA_IMPORTE')) {
    final p = rejeu.problemes.firstWhere((p) => p.code == 'LOT_DEJA_IMPORTE');
    return ResultatImport.refus('LOT_DEJA_IMPORTE', p.motif, p.geste);
  }
  final ctx = j.contexte(_VueSansLotsDefaits(port));
  final reference = referenceLot(port);
  final lot = <String, Object?>{'reference': reference};
  final ecrits = <Map<String, Object?>>[];
  final par = port.utilisateur, jour = port.jour;
  FicheImport ecrireFiche(String collection, FicheImport fiche) {
    final stockee = port.inserer(collection, {
      'statut': 'actif',
      'source': 'Import ${j.libelle} (${analyse.fichier.isEmpty ? 'fichier' : analyse.fichier})',
      'lotImport': reference,
      'validePar': par,
      'dateImport': jour,
      ...fiche,
    });
    ecrits.add({'collection': collection, 'id': stockee['id']});
    return stockee;
  }

  try {
    j.ecrire([for (final l in rejeu.lignes) if (!l.ignoree) l], ecrireFiche, lot, ctx, port);
  } catch (e) {
    for (final x in ecrits.reversed) {
      port.retirer('${x['collection']}', x['id']);
    }
    final motif = e.toString();
    rejeu.globaux.add(ProblemeImport(
        n: 0, colonne: '', valeur: '', code: 'ECRITURE_REFUSEE', niveau: importRefus, motif: motif, geste: 'Rien n’a été écrit. Corrigez la cause puis téléversez de nouveau.'));
    final consigne = consigner(j, rejeu, port)!;
    return ResultatImport.refus('ECRITURE_REFUSEE', motif, 'Rien n’a été écrit ; le fichier est consigné (${consigne['reference']}).', lot: consigne);
  }
  final ps = rejeu.problemes;
  final rec = port.inserer(collectionLots, {
    'reference': reference,
    'jeu': j.id,
    'jeuLibelle': j.libelle,
    'fichier': analyse.fichier,
    'empreinte': analyse.empreinte,
    'date': jour,
    'par': par,
    'validePar': par,
    'etat': 'applique',
    'nbLignes': rejeu.nbLignes,
    'nbAvertissements': rejeu.compte.avertissements,
    'nbRefus': 0,
    'ecrits': ecrits,
    'erreurs': _erreursPlafonnees(ps),
    'erreursTotal': ps.length,
    'ignores': rejeu.ignorees,
    'nbIgnorees': rejeu.ignorees.length,
  });
  port.journaliser('Import', 'IMP', 'LotImport', reference,
      null, {'jeu': j.id, 'fichier': analyse.fichier, 'lignes': rejeu.nbLignes, 'fiches': ecrits.length, if (rejeu.ignorees.isNotEmpty) 'ignorees': rejeu.ignorees.length});
  return ResultatImport.ok(lot: rec, ecrits: ecrits.length);
}

/// Annule un lot appliqué : ses fiches sont ARCHIVÉES (RG-14), jamais supprimées. Refusé en nommant la dépendance si un acte s'appuie dessus.
ResultatImport annulerLot(JeuImport? Function(String id) jeu, Object? lotId, String? motif, PortImport port) {
  final lot = port.parId(collectionLots, lotId);
  if (lot == null) return const ResultatImport.refus('LOT_INCONNU', 'lot introuvable', 'Actualisez l’historique.');
  if (lot['etat'] != 'applique') {
    return ResultatImport.refus('LOT_NON_APPLIQUE', 'seul un lot appliqué s’annule (état actuel : ${lot['etat']})', 'Aucune action : ce lot n’a rien écrit ou est déjà annulé.');
  }
  final j = jeu('${lot['jeu']}');
  if (j != null) {
    final rd = refusDroitImport(j, 'annuler', port);
    if (rd != null) return rd;
  }
  final dep = j?.dependances(lot, port);
  if (dep != null) return ResultatImport.refus(dep.code, dep.motif, dep.geste);
  final faits = <Map<String, Object?>>[];
  Map<String, Object?>? echec;
  final ecrits = (lot['ecrits'] as List).cast<Map>().map((e) => e.cast<String, Object?>()).toList();
  for (final e in ecrits) {
    if (echec != null) break;
    final f = port.parId('${e['collection']}', e['id']);
    if (f == null || f['statut'] == 'archive') continue;
    if (!port.archiver('${e['collection']}', e['id'], 'Annulation du lot ${lot['reference']}${motif != null && motif.isNotEmpty ? ' : $motif' : ''}')) {
      echec = e;
    } else {
      faits.add(e);
    }
  }
  if (echec != null) {
    for (final e in faits) {
      port.restaurer('${e['collection']}', e['id']);
    }
    return ResultatImport.refus('ARCHIVAGE_REFUSE', 'le moteur a refusé d’archiver une fiche de « ${echec['collection']} » (exercice clos ou fiche verrouillée)',
        'Rien n’a été annulé. Rouvrez l’exercice ou traitez la fiche à la main.');
  }
  port.mettreAJour(collectionLots, lot['id'], {'etat': 'annule', 'annulePar': port.utilisateur, 'annuleLe': port.jour, 'motifAnnulation': motif});
  port.journaliser('Import annulé', 'IMP', 'LotImport', '${lot['reference']}', {'etat': 'applique'}, {'etat': 'annule', 'fiches': faits.length});
  return ResultatImport.ok(lot: port.parId(collectionLots, lot['id']), archives: faits.length);
}

// --- Modèles et rapports (le contenu des feuilles ; l'écriture du classeur est l'affaire du poste) -------------------------------------

String _typeLisible(ColonneImport c) =>
    const {
      'texte': 'Texte',
      'entier': 'Nombre entier',
      'decimal': 'Nombre',
      'date': 'Date (AAAA-MM-JJ ou JJ/MM/AAAA)',
      'liste': 'Liste de valeurs',
      'tarif': 'Montant, NC ou tiret'
    }[c.type] ??
    c.type;

String _valeursPermises(ColonneImport c, dynamic ctx) {
  if (c.type == 'liste') return valeursListe(c, ctx).map((x) => x.label).join(' ; ');
  if (c.type == 'entier') return 'entier${c.min != null ? ' ≥ ${c.min}' : ''}${c.max != null ? ' et ≤ ${c.max}' : ''}';
  if (c.type == 'tarif') return 'montant entier en FCFA ; NC ; tiret (-)';
  if (c.motifTexte != null) return c.motifTexte!;
  if (c.longueurMax != null) return 'jusqu’à ${c.longueurMax} caractères';
  return '';
}

/// Le contenu des trois feuilles du modèle : « Données » (en-têtes exacts et une ligne d'exemple), « Instructions » (colonnes, formats, valeurs
/// permises) et « Listes » (les référentiels de contrôle). [validations] : pour chaque colonne « liste », la formule de sa liste déroulante.
class ModeleImport {
  ModeleImport(this.donnees, this.instructions, this.listes, this.validations, this.colonnesTexte);
  final List<List<Object?>> donnees, instructions, listes;
  final List<({int colonne, String formule})> validations;
  final List<int> colonnesTexte;
}

ModeleImport modeleImport(JeuImport j, PortImport port, {Set<String> colonnesAccordees = const {}}) {
  final ctx = j.contexte(port);
  final cols = j.colonnesPour(colonnesAccordees);
  final donnees = <List<Object?>>[
    [for (final c in cols) c.label],
    ligneExemple(j, cols),
  ];
  final instructions = <List<Object?>>[
    ['Modèle d’importation : ${j.libelle}'],
    ['Source : ${j.source}'],
    [j.statut == 'proposition' ? 'Statut du jeu : PROPOSITION À VALIDER. ${j.limite ?? ''}' : 'Statut du jeu : supporté.'],
    [''],
    ['Mode d’emploi'],
    ['1. Remplissez l’onglet « Données » à partir de la ligne 2 : une ligne par enregistrement. La ligne 2 est un exemple, remplacez-la ou supprimez-la (elle est ignorée tant qu’elle reste identique à l’exemple).'],
    ['2. Ne changez ni l’ordre ni l’orthographe des en-têtes de la ligne 1 : ils sont reconnus à l’identique. Les colonnes obligatoires doivent toutes figurer.'],
    ['3. Téléversez le fichier : l’analyse complète s’exécute avant toute écriture, ligne par ligne. Un refus nomme la ligne, la colonne, la valeur, le motif et le geste de correction.'],
    ['4. Si une seule ligne est refusée, le fichier entier est refusé et rien n’est écrit. Corrigez et téléversez de nouveau.'],
    ['5. Un lot confirmé s’annule (les fiches sont archivées, jamais supprimées) tant qu’aucun acte ne s’appuie dessus.'],
    [''],
    ['Colonne', 'Obligatoire', 'Type', 'Valeurs permises', 'Exemple', 'Explication'],
    for (final c in cols) [c.label, c.obligatoire ? 'oui' : 'non', _typeLisible(c), _valeursPermises(c, ctx), c.exemple ?? '', c.aide ?? ''],
  ];
  final colsListes = <({String titre, List<String> valeurs})>[];
  for (final c in cols) {
    if (c.type != 'liste') continue;
    colsListes.add((titre: c.label, valeurs: [for (final x in valeursListe(c, ctx)) x.label]));
  }
  final hauteur = colsListes.fold<int>(0, (m, l) => l.valeurs.length > m ? l.valeurs.length : m);
  final listes = <List<Object?>>[
    [for (final l in colsListes) l.titre],
    for (var i = 0; i < hauteur; i++) [for (final l in colsListes) i < l.valeurs.length ? l.valeurs[i] : ''],
  ];
  final validations = <({int colonne, String formule})>[];
  var k = 0;
  for (var ci = 0; ci < cols.length; ci++) {
    if (cols[ci].type != 'liste') continue;
    final lettre = String.fromCharCode(65 + k);
    final fin = colsListes[k].valeurs.length + 1;
    validations.add((colonne: ci, formule: 'Listes!\$$lettre\$2:\$$lettre\$${fin < 2 ? 2 : fin}'));
    k++;
  }
  return ModeleImport(
    donnees,
    instructions,
    colsListes.isEmpty ? [['Aucune liste pour ce jeu']] : listes,
    validations,
    [for (var ci = 0; ci < cols.length; ci++) if (cols[ci].type == 'texte') ci],
  );
}

/// Le modèle CSV : BOM, point-virgule, guillemets doublés.
String modeleCsvImport(JeuImport j, {Set<String> colonnesAccordees = const {}}) {
  final cols = j.colonnesPour(colonnesAccordees);
  String ligne(List<Object?> a) => a.map((x) => '"${texteDe(x).replaceAll('"', '""')}"').join(';');
  return '\uFEFF${ligne([for (final c in cols) c.label])}\r\n${ligne(ligneExemple(j, cols))}\r\n';
}

/// Le contenu de la feuille « Erreurs » du rapport téléchargeable.
List<List<Object?>> rapportImport(List<Map<String, Object?>> problemes) => [
      ['Ligne', 'Colonne', 'Valeur', 'Niveau', 'Code', 'Motif', 'Geste de correction'],
      for (final p in problemes) [p['n'] ?? '', p['colonne'] ?? '', texteDe(p['valeur']), p['niveau'], p['code'], p['motif'], p['geste']],
    ];

/// Le contenu de la feuille « Résumé » du rapport.
List<List<Object?>> resumeRapportImport(String jeuLibelle, String fichier, String lot, int nbLignes, int nbProblemes) => [
      ['Rapport d’importation'],
      ['Jeu', jeuLibelle],
      ['Fichier', fichier],
      ['Lot', lot],
      ['Lignes lues', nbLignes],
      ['Problèmes', nbProblemes],
    ];

// --- Lecture CSV et empreinte ----------------------------------------------------------------------------------------------------

/// Lit un CSV : séparateur `;`, `,` ou tabulation détecté sur la première ligne, guillemets doublés, BOM, lignes finales vides retirées.
List<List<String>> importLireCsv(String texte) {
  var t = texte;
  if (t.isNotEmpty && t.codeUnitAt(0) == 0xFEFF) t = t.substring(1);
  final premiere = t.split(RegExp(r'\r?\n')).first;
  var sep = ';';
  var meilleur = -1;
  for (final s in [';', ',', '\t']) {
    final n = premiere.split(s).length;
    if (n > meilleur) {
      meilleur = n;
      sep = s;
    }
  }
  final lignes = <List<String>>[];
  var ligne = <String>[];
  var champ = StringBuffer();
  var guillemets = false;
  for (var i = 0; i < t.length; i++) {
    final ch = t[i];
    if (guillemets) {
      if (ch == '"') {
        if (i + 1 < t.length && t[i + 1] == '"') {
          champ.write('"');
          i++;
        } else {
          guillemets = false;
        }
      } else {
        champ.write(ch);
      }
    } else if (ch == '"') {
      guillemets = true;
    } else if (ch == sep) {
      ligne.add(champ.toString());
      champ = StringBuffer();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < t.length && t[i + 1] == '\n') i++;
      ligne.add(champ.toString());
      champ = StringBuffer();
      lignes.add(ligne);
      ligne = <String>[];
    } else {
      champ.write(ch);
    }
  }
  if (champ.isNotEmpty || ligne.isNotEmpty) {
    ligne.add(champ.toString());
    lignes.add(ligne);
  }
  while (lignes.isNotEmpty && lignes.last.every((v) => v.trim().isEmpty)) {
    lignes.removeLast();
  }
  return lignes;
}

/// CRC-32 (empreinte du fichier consignée au lot), en hexadécimal sans zéros de tête, comme la maquette.
String importCrc32(List<int> octets) {
  var c = 0xFFFFFFFF;
  for (final b in octets) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
  }
  return ((c ^ 0xFFFFFFFF) & 0xFFFFFFFF).toRadixString(16);
}
