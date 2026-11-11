import '../format/format_fr.dart';
import '../format/recherche.dart' show trierPar;
import '../impression/identite.dart';

/// RÈGLES DE CFG — dix écrans de configuration : organisation, identité, référentiel tarifaire, catalogue à deux prix, en-têtes, types de pièces, rappels,
/// certificats, natures de facture, catalogue de l'imagerie. Portées de `prototype_html/assets/js/modules/configuration.js` et rejouées sur les vecteurs
/// de la maquette (`test/vecteurs/cfg.json`, engendré par `prototype_html/build/vecteurs-cfg.js`). Symboles préfixés `cfa` / `Cfa`.

typedef CfaFiche = Map<String, Object?>;

/// Un indicateur de tableau : libellé, valeur affichée, icône Lucide (par son nom), ton, indice.
class CfaKpi {
  const CfaKpi(this.libelle, this.valeur, this.icone, this.ton, [this.indice]);
  final String libelle;
  final String valeur;
  final String icone;
  final String ton;
  final String? indice;
}

bool cfaVrai(Object? v) => v != null && v != false && v != 0 && v != '';

/// `String(v)` de JavaScript pour un nombre : 3.0 s'écrit « 3 ».
String cfaTexte(Object? v) {
  if (v is double && v == v.roundToDouble() && v.isFinite) return v.toInt().toString();
  return '${v ?? ''}';
}

/// `Number(v)` d'une saisie : vide → absent.
num? cfaNombre(Object? v) {
  if (v is num) return v;
  final t = '${v ?? ''}'.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final n = num.tryParse(t);
  if (n == null) return null;
  return n == n.roundToDouble() ? n.toInt() : n;
}

String cfaMajuscules(String s) => s.toUpperCase();

// =============================================================================================================================================
// Référentiels statiques lus par ces écrans — tirés de la maquette (`cfg.json › constantes`), GARDÉS par `test/cfg_test.dart`.
// =============================================================================================================================================

/// `D.NS145` (sans la liste des secteurs, qui vit dans la collection `secteurs`).
class CfaNs145 {
  const CfaNs145._();
  static const reference = 'NS 145/08/DA/CBG/2026';
  static const objet = 'Répartition des secteurs de la clinique et désignation des responsables';
  static const dateSignature = '2026-08-06';
  static const dateEffet = '2026-08-07';
  /// La QUALITÉ du signataire : son nom se lit au dossier du personnel (`paiSignataire`), jamais dans le code.
  static const signataire = 'Directrice Administrative';
  static const source = 'DOC — Note de service NS 145/08/DA/CBG/2026';
}

/// `C.BRAND` : ce que l'écran d'identité affiche en plus de `IdentiteClinique` (UNE identité légale). Forme juridique et adresse VIVENT dans
/// `IdentiteClinique` (surchargeables depuis cfg-branding) : les relire ici évite une seconde vérité.
class CfaIdentite {
  const CfaIdentite._();
  // Ces champs vivent sur l'identité courante ([IdentiteClinique], surchargeable depuis cfg-branding) : lus là, jamais recopiés ici.
  static String get forme => IdentiteClinique.forme;
  static String get adresse => IdentiteClinique.adresse;
  static String get telephoneRdv => IdentiteClinique.telephoneRdv;
  static const autorisationExerciceMotif = IdentiteClinique.autorisationExerciceMotif;
  static String get logo => IdentiteClinique.logo;
}

/// `D.FAMILLES_TARIF` : (code, libellé, icône).
const cfaFamillesTarif = <(String, String, String)>[
  ('CONSULTATION', 'Consultations', 'stethoscope'),
  ('IMAGERIE', 'Imagerie médicale', 'scan-line'),
  ('LABO', 'Analyses de laboratoire', 'flask-conical'),
  ('AMI', 'Actes médico-infirmiers', 'syringe'),
  ('GYNECO', 'Actes gynéco-obstétricaux et kits', 'baby'),
  ('CERTIFICAT', 'Certificats et attestations', 'file-badge'),
];

/// `D.IMAGERIE.TYPES` : (code, libellé) des types de variable d'un compte rendu d'imagerie.
const cfaTypesVariableImagerie = <(String, String)>[
  ('liste', 'Liste de choix'),
  ('binaire', 'Deux valeurs'),
  ('mesure', 'Mesure chiffrée'),
  ('dimensions', 'Trois dimensions (mm)'),
  ('gestationnel', 'Âge gestationnel (SA + jours)'),
  ('texte', 'Texte libre'),
  ('zone', 'Texte libre — plusieurs lignes'),
  ('multiple', 'Choix multiples'),
];

// =============================================================================================================================================
// cfg-organisation
// =============================================================================================================================================

/// Un poste de l'organigramme avec ses enfants (`arbreDepuisCollection`).
class CfaNoeud {
  CfaNoeud(this.fiche);
  final CfaFiche fiche;
  final List<CfaNoeud> enfants = [];
  String get poste => '${fiche['poste'] ?? ''}';
  num get effectif => cfaNombre(fiche['effectif']) ?? 0;
}

/// `arbreDepuisCollection` : les postes ACTIFS, chacun rattaché à son parent s'il existe (sinon sommet).
List<CfaNoeud> cfaArbre(Iterable<CfaFiche> postesActifs) {
  final parId = {for (final p in postesActifs) '${p['id']}': CfaNoeud(p)};
  final racines = <CfaNoeud>[];
  for (final p in postesActifs) {
    final n = parId['${p['id']}']!;
    final parent = p['parentId'];
    if (cfaVrai(parent) && parId.containsKey('$parent')) {
      parId['$parent']!.enfants.add(n);
    } else {
      racines.add(n);
    }
  }
  return racines;
}

/// Les identifiants de TOUS les postes portés, de près ou de loin, par le poste [id] : un poste ne peut pas être rattaché à l'un d'eux (le graphe ferait un cercle).
Set<String> cfaDescendantsDe(Iterable<CfaFiche> postesActifs, String id) {
  final r = <String>{};
  var frontiere = {id};
  while (frontiere.isNotEmpty) {
    final suite = <String>{};
    for (final p in postesActifs) {
      final pid = '${p['id']}';
      if (frontiere.contains('${p['parentId'] ?? ''}') && r.add(pid)) suite.add(pid);
    }
    frontiere = suite;
  }
  return r;
}

/// Un sous-poste réaffecté par l'archivage de son poste porteur : son rattachement d'avant et celui d'après (`null` : sommet).
class CfaReaffectation {
  const CfaReaffectation({required this.id, required this.poste, required this.ancienParentId, required this.nouveauParentId});
  final String id;
  final String poste;
  final String ancienParentId;
  final String? nouveauParentId;

  Map<String, Object?> toJson() => {'id': id, 'poste': poste, 'ancienParentId': ancienParentId, 'nouveauParentId': nouveauParentId};
  static CfaReaffectation depuisJson(Map<String, Object?> j) => CfaReaffectation(
      id: '${j['id']}', poste: '${j['poste'] ?? ''}', ancienParentId: '${j['ancienParentId']}', nouveauParentId: cfaVrai(j['nouveauParentId']) ? '${j['nouveauParentId']}' : null);
}

/// Ce qu'archiver un poste fait de ses sous-postes (décision de la Direction) : les sous-postes ACTIFS sont réaffectés au rattachement du poste archivé
/// (son parent ; un sommet laisse des sommets), pour qu'aucune boîte ne reste sans trait.
class CfaPlanArchivagePoste {
  const CfaPlanArchivagePoste({required this.posteId, required this.poste, required this.nouveauParentId, required this.nouveauParent, required this.reaffectations});
  final String posteId;
  final String poste;

  /// Le rattachement d'accueil (`null` : les sous-postes deviennent des sommets) et son intitulé.
  final String? nouveauParentId;
  final String? nouveauParent;
  final List<CfaReaffectation> reaffectations;

  /// La phrase de la confirmation : combien de sous-postes, lesquels, vers quel poste.
  String get phrase {
    if (reaffectations.isEmpty) return 'Ce poste ne porte aucun sous-poste actif : rien n’est réaffecté.';
    final n = reaffectations.length;
    final noms = reaffectations.map((r) => '« ${r.poste} »').join(', ');
    final tete = '$n sous-poste${n > 1 ? 's seront réaffectés' : ' sera réaffecté'} automatiquement : $noms';
    return nouveauParentId == null
        ? '$tete — ${n > 1 ? 'ils deviendront des sommets' : 'il deviendra un sommet'} de l’organigramme (le poste archivé en était un).'
        : '$tete — ${n > 1 ? 'rattachés' : 'rattaché'} à « $nouveauParent » (le rattachement du poste archivé).';
  }
}

/// Le plan d'archivage du poste [id] sur les postes ACTIFS. Fonction pure : seuls les sous-postes DIRECTS bougent (ils emportent les leurs).
CfaPlanArchivagePoste cfaPlanArchivagePoste(Iterable<CfaFiche> postesActifs, String id) {
  final actifs = postesActifs.toList();
  final poste = actifs.firstWhere((p) => '${p['id']}' == id);
  final pid = cfaVrai(poste['parentId']) ? '${poste['parentId']}' : null;
  final parent = pid == null ? null : actifs.where((p) => '${p['id']}' == pid && '${p['id']}' != id).firstOrNull;
  final nouveauId = parent == null ? null : '${parent['id']}';
  return CfaPlanArchivagePoste(
    posteId: id,
    poste: '${poste['poste'] ?? ''}',
    nouveauParentId: nouveauId,
    nouveauParent: parent == null ? null : '${parent['poste'] ?? ''}',
    reaffectations: [
      for (final p in actifs)
        if (cfaVrai(p['parentId']) && '${p['parentId']}' == id)
          CfaReaffectation(id: '${p['id']}', poste: '${p['poste'] ?? ''}', ancienParentId: id, nouveauParentId: nouveauId)
    ],
  );
}

/// L'annulation de l'archivage : parmi les sous-postes réaffectés, ceux dont le rattachement est TOUJOURS celui que la réaffectation a posé (et qui
/// sont actifs) retrouvent leur rattachement d'origine ; les autres ont été modifiés entre-temps — on ne les écrase pas, on les nomme.
({List<CfaReaffectation> restituables, List<CfaReaffectation> modifies}) cfaPlanAnnulationArchivage(Iterable<CfaFiche> postesActifs, List<CfaReaffectation> reaffectations) {
  final actifs = {for (final p in postesActifs) '${p['id']}': p};
  final restituables = <CfaReaffectation>[];
  final modifies = <CfaReaffectation>[];
  for (final r in reaffectations) {
    final p = actifs[r.id];
    final courant = p != null && cfaVrai(p['parentId']) ? '${p['parentId']}' : null;
    (p != null && courant == r.nouveauParentId ? restituables : modifies).add(r);
  }
  return (restituables: restituables, modifies: modifies);
}

/// La note de la RESTAURATION d'un poste archivé depuis la Corbeille : ses anciens sous-postes ne lui sont pas rattachés d'office. `null` : rien à dire.
String? cfaNoteRestaurationPoste(CfaFiche poste, Iterable<CfaFiche> postesActifs) {
  final liste = [for (final j in (poste['sousPostesReaffectes'] as List? ?? const [])) if (j is Map) CfaReaffectation.depuisJson({for (final e in j.entries) '${e.key}': e.value})];
  if (liste.isEmpty) return null;
  final actifs = {for (final p in postesActifs) '${p['id']}': p};
  final noms = [for (final r in liste) if (actifs.containsKey(r.id)) '« ${r.poste} »'];
  if (noms.isEmpty) return null;
  return 'À son archivage, ${noms.length > 1 ? 'ses sous-postes ont été réaffectés' : 'son sous-poste a été réaffecté'} (${noms.join(', ')}) : ils ne sont PAS rattachés de nouveau d’office. Pour les replacer sous ce poste, modifier leur rattachement.';
}

num cfaEffectifTotal(Iterable<CfaNoeud> noeuds) =>
    noeuds.fold<num>(0, (s, n) => s + n.effectif + cfaEffectifTotal(n.enfants));

List<CfaKpi> cfaKpisOrganisation({required int secteurs, required int postes, required num effectif, required int roles}) => [
      CfaKpi('Secteurs de la clinique', nombre(secteurs), 'layers', 'navy', 'NS 145 du 06/08/2026'),
      CfaKpi('Postes de l’organigramme', nombre(postes), 'network', 'info'),
      CfaKpi('Effectif porté', nombre(effectif), 'users-round', 'success'),
      CfaKpi('Rôles RBAC', nombre(roles), 'shield', 'neutral'),
    ];

/// `transform` du bouton « Nouveau » des secteurs : code par défaut = trois premières lettres du libellé en majuscules, rang = nombre de fiches + 1
/// (archivées comprises).
CfaFiche cfaFicheSecteur(Map<String, Object?> saisie, int nbToutes) {
  final v = {...saisie};
  if (!cfaVrai(v['code'])) {
    final l = cfaVrai(v['libelle']) ? '${v['libelle']}' : 'SEC';
    v['code'] = (l.length > 3 ? l.substring(0, 3) : l).toUpperCase();
  }
  v['ordre'] = nbToutes + 1;
  return v;
}

/// `transform` du bouton « Nouveau » des postes : sans rattachement, le poste est un sommet (`parentId` nul), l'effectif est un nombre.
CfaFiche cfaFichePoste(Map<String, Object?> saisie) {
  final v = {...saisie};
  if (!cfaVrai(v['parentId'])) v['parentId'] = null;
  if (v.containsKey('effectif')) v['effectif'] = cfaNombre(v['effectif']);
  // Le GRAPHE de l'organigramme imprimé : les champs numériques d'une saisie sont des nombres, un champ vidé disparaît (le poste est alors placé
  // automatiquement par `organigrammeScene`).
  for (final k in const ['niveau', 'x', 'y', 'largeur', 'hauteur', 'barre', 'coudeX', 'coudeY', 'ordreLegende']) {
    if (!v.containsKey(k)) continue;
    final n = cfaNombre(v[k]);
    if (n == null) {
      v.remove(k);
    } else {
      v[k] = n;
    }
  }
  for (final k in const ['code', 'codeLegende', 'lien']) {
    if (v.containsKey(k) && !cfaVrai(v[k])) v.remove(k);
  }
  return v;
}

/// `modulesRole` : un code par RANGÉE du manifeste (les codes se répètent quand un module a des rangées secondaires ou des alias) dont au moins un écran
/// est visible du rôle.
///
/// Une rangée CANONIQUE se juge sur les droits de ses écrans (la matrice engendrée) ; une rangée d'ALIAS ne déclare aucun rôle : la maquette l'interroge
/// avec « tous les rôles » et seuls comptent les droits du module et les réglages d'écran — c'est ce que [voit] reçoit dans `alias`.
List<String> cfaModulesRole(Iterable<(String code, List<String> ecrans, bool alias)> rangees, bool Function(String code, String ecran, bool alias) voit) =>
    [for (final r in rangees) if (r.$2.any((e) => voit(r.$1, e, r.$3))) r.$1];

// =============================================================================================================================================
// cfg-branding
// =============================================================================================================================================

/// `RESSOURCES_ATTENDUES` : (type, intitulé, usage).
const cfaRessourcesAttendues = <(String, String, String)>[
  ('logo', 'Logo principal', 'Utilisé sur tous les états et dans l’application'),
  ('logo_mono', 'Logo monochrome', 'Pour les impressions en noir et blanc'),
  ('cachet', 'Cachet de l’établissement', 'Apposé sur les documents officiels'),
  ('signature_dm', 'Signature numérisée du Directeur', 'Documents médicaux et administratifs'),
  ('photos', 'Photographies du site', 'Supports de communication'),
];

/// Poids d'un fichier : « 2 ko », « 1.2 Mo » (`poids(o)` de la maquette).
String cfaPoids(num? o) {
  if (o == null || o == 0) return '—';
  if (o > 1024 * 1024) return '${(o / 1024 / 1024).toStringAsFixed(1)} Mo';
  return '${(o / 1024).round()} ko';
}

/// Au-delà d'un mégaoctet, la maquette avertit (stockage local qui sature) — le poste garde l'avertissement.
bool cfaFichierTropLourd(num taille) => taille > 1024 * 1024;

// =============================================================================================================================================
// cfg-tarifs
// =============================================================================================================================================

List<CfaKpi> cfaKpisTarifs({required int produits, required int analyses, required int actes, required int secteurs, required int aConfirmer}) => [
      CfaKpi('Produits tarifés', nombre(produits), 'pill', 'navy'),
      CfaKpi('Analyses tarifées', nombre(analyses), 'flask-conical', 'info'),
      CfaKpi('Actes et prestations', nombre(actes), 'stethoscope', 'success', '$secteurs secteurs'),
      CfaKpi('Tarifs à confirmer', nombre(aConfirmer), 'help-circle', 'warning', 'Colonnes de prix vierges aux sources'),
    ];

/// « Tarifs à confirmer » : les analyses à tarif provisoire plus les actes sans prix.
int cfaTarifsAConfirmer(Iterable<CfaFiche> analyses, Iterable<CfaFiche> actes) =>
    analyses.where((a) => cfaVrai(a['tarifProvisoire'])).length + actes.where((a) => a['prix'] == null).length;

/// RG-02 à la création d'un produit : pour un médicament le prix de vente SUIT le prix d'achat ; code `PRD-NNNN` ; trois stocks à zéro.
CfaFiche cfaFicheProduit(Map<String, Object?> saisie, int nbToutes) {
  final v = {...saisie};
  v['prixAchat'] = cfaNombre(v['prixAchat']);
  v['prixVente'] = cfaNombre(v['prixVente']);
  v['seuilAlerte'] = cfaNombre(v['seuilAlerte']);
  if (v['categorie'] == 'medicament') v['prixVente'] = v['prixAchat'];
  if (!cfaVrai(v['code'])) v['code'] = 'PRD-${(nbToutes + 1).toString().padLeft(4, '0')}';
  v['stock'] = cfaVrai(v['stock']) ? v['stock'] : 0;
  v['stockGros'] = cfaVrai(v['stockGros']) ? v['stockGros'] : 0;
  v['stockDetail'] = cfaVrai(v['stockDetail']) ? v['stockDetail'] : 0;
  return v;
}

/// Création d'une analyse : rang et code `LNN`, tarif TOUJOURS provisoire (le document source ne renseigne pas les prix).
CfaFiche cfaFicheAnalyse(Map<String, Object?> saisie, int nbToutes) {
  final v = {...saisie};
  v['prix'] = cfaNombre(v['prix']);
  final n = nbToutes + 1;
  v['n'] = n;
  if (!cfaVrai(v['code'])) v['code'] = 'L${n.toString().padLeft(2, '0')}';
  v['tarifProvisoire'] = true;
  return v;
}

/// Création d'un acte : code `ACT-NNN`, prix vide = absent (à valider), jamais zéro.
CfaFiche cfaFicheActe(Map<String, Object?> saisie, int nbToutes) {
  final v = {...saisie};
  if (!cfaVrai(v['code'])) v['code'] = 'ACT-${(nbToutes + 1).toString().padLeft(3, '0')}';
  v['prix'] = cfaNombre(v['prix']);
  return v;
}

/// Les cinq lectures du filtre « Tarif » du catalogue des actes.
const cfaFiltresTarifActe = <(String, String)>[
  ('grille', 'Repris d’une grille'),
  ('valide', 'Validé sur pièce'),
  ('attente', 'Valeur d’attente'),
  ('decline', 'Décliné par la grille'),
  ('absent', 'Sans tarif'),
];

bool cfaCorrespondTarifActe(CfaFiche r, String v) {
  if (v == 'grille') return cfaVrai(r['codeTarif']);
  if (v == 'valide') return r['prix'] != null && !cfaVrai(r['tarifProvisoire']);
  if (v == 'attente') return cfaVrai(r['tarifProvisoire']);
  if (v == 'decline') {
    final l = r['variantesGrille'];
    return l is List && l.isNotEmpty;
  }
  return r['prix'] == null;
}

/// Les notes de l'onglet « Actes & hospitalisation » : tarifs repris des grilles, valeurs d'attente, actes déclinés par la grille — trois populations
/// qu'il faut distinguer. Une population vide n'a pas de note.
List<({String texte, String ton})> cfaNotesActes(Iterable<CfaFiche> actes) {
  final repris = actes.where((a) => cfaVrai(a['codeTarif'])).length;
  final aValider = actes.where((a) => a['prix'] == null || cfaVrai(a['tarifProvisoire'])).length;
  final declines = actes.where((a) {
    final l = a['variantesGrille'];
    return l is List && l.isNotEmpty;
  }).length;
  return [
    if (repris > 0)
      (
        texte:
            '$repris prestation(s) reprennent leur tarif des grilles imprimées de la clinique, avec leurs deux colonnes — assuré et non assuré. Le rapprochement est fait sur libellé identique ou par une correspondance nommée, jamais par approximation : apparier « Consultation généraliste à domicile » avec « Consultation généraliste » ferait perdre le déplacement.',
        ton: 'succes'
      ),
    if (aValider > 0)
      (
        texte:
            '$aValider prestation(s) portent encore un tarif d’attente. Elles ne figurent sur aucune des six grilles : la valeur permet d’exercer la facturation, elle reste signalée tant que la Direction ne l’a pas validée.',
        ton: 'attention'
      ),
    if (declines > 0)
      (
        texte:
            '$declines prestation(s) sont déclinées par la grille en plusieurs variantes — sept accouchements, quatre paliers d’oxygénothérapie, trois épisiotomies, deux ponctions lombaires. Ce n’est pas un prix manquant : c’est à la clinique de dire quelle variante son acte désigne. Choisir à sa place facturerait le mauvais tarif.',
        ton: 'info'
      ),
  ];
}

/// L'onglet « Certificats et Attestations » : les types de pièce sans tarif au catalogue (une pièce non tarifée se délivre, elle ne se facture pas).
String? cfaNoteSansTarif(Iterable<CfaFiche> typesActifs) {
  final sans = typesActifs.where((t) => !cfaVrai(t['tarifCode'])).toList();
  if (sans.isEmpty) return null;
  return '${nombre(sans.length)} type(s) de pièce sans tarif au catalogue : ${sans.map((t) => t['libelle']).join(', ')}. Une pièce non tarifée se délivre, elle ne se facture pas — rattacher son acte depuis « Types de pièces certifiantes ».';
}

/// Tri par défaut du catalogue des actes : secteur, ordre naturel français.
List<CfaFiche> cfaTrierParSecteur(List<CfaFiche> l) => trierPar(l, (x) => x['secteur']);

// =============================================================================================================================================
// cfg-catalogue
// =============================================================================================================================================

List<CfaKpi> cfaKpisCatalogue(Iterable<CfaFiche> rows) {
  final sansPrix = rows.where((r) => cfaVrai(r['prixAValider'])).length;
  final nonCouverts = rows.where((r) => cfaVrai(r['nonCouvert'])).length;
  final sos = rows.where((r) => r['assurable'] == 'sos').length;
  return [
    CfaKpi('Actes au catalogue', nombre(rows.length), 'list-ordered', 'navy', '${nombre(cfaFamillesTarif.length)} familles'),
    CfaKpi('Non couverts par les assurances', nombre(nonCouverts), 'shield-off', 'warning', 'planification familiale et hydrotubation'),
    CfaKpi('Couverts par SOS seule', nombre(sos), 'shield-alert', 'info', 'les certificats'),
    CfaKpi('Prix non renseigné', nombre(sansPrix), 'triangle-alert', sansPrix > 0 ? 'danger' : 'success', 'ligne non facturable'),
  ];
}

/// Les notes de tête du catalogue : prix absents (bloquent la facturation), divergences à arbitrer, arbitrages tranchés. Jamais de note pour une
/// population vide.
List<({String texte, String ton})> cfaNotesCatalogue(Iterable<CfaFiche> rows) {
  final sansPrix = rows.where((r) => cfaVrai(r['prixAValider'])).toList();
  final aArbitrer = rows.where((r) => cfaVrai(r['aArbitrer'])).toList();
  final arbitres = rows.where((r) => cfaVrai(r['arbitrage'])).toList();
  return [
    if (sansPrix.isNotEmpty)
      (
        texte:
            '${sansPrix.length} acte(s) sans prix au document : ${sansPrix.map((r) => r['libelle']).join(' · ')}. Un tiret sur la grille n’est ni un zéro ni une exclusion — c’est une valeur manquante. Ces lignes ne peuvent pas être facturées tant que la Direction ne les a pas arrêtées.',
        ton: 'danger'
      ),
    if (aArbitrer.isNotEmpty)
      (
        texte:
            'Divergence à arbitrer — ${aArbitrer.map((r) => '${r['libelle']} : ${r['aArbitrer']}').join(' ; ')} Le prototype retient le document ; écraser une pièce écrite par une phrase, ou l’inverse, serait décider à la place de la clinique.',
        ton: 'attention'
      ),
    if (arbitres.isNotEmpty)
      (
        texte:
            '${arbitres.length} acte(s) arbitré(s) par la Direction, dont le tarif ne suit pas la grille relevée : ${arbitres.map((r) => '${r['code']} — ${r['libelle']}').join(' · ')}. Un arbitrage tranché n’est pas une divergence en attente : il est appliqué et daté. Ne pas le « corriger » sans nouvelle décision écrite.',
        ton: 'info'
      ),
  ];
}

/// Création d'un acte du catalogue à deux prix : NON COUVERT = non assurable ; un prix absent (ou un assuré absent sans exclusion) est « à valider ».
CfaFiche cfaFicheTarif(Map<String, Object?> saisie) {
  final v = {...saisie};
  v['prixNonAssure'] = cfaNombre(v['prixNonAssure']);
  v['prixAssure'] = cfaNombre(v['prixAssure']);
  final nc = cfaVrai(v['nonCouvert']);
  v['nonCouvert'] = nc;
  v['assurable'] = !nc;
  v['prixAValider'] = v['prixNonAssure'] == null || (v['prixAssure'] == null && !nc);
  v['source'] = cfaVrai(v['source']) ? v['source'] : 'Saisi par l’administrateur';
  v['statut'] = 'actif';
  return v;
}

/// La cellule « Écart » (assuré − non assuré) : « — » si un des deux prix manque ou si l'acte n'est pas couvert ; « + » seulement quand l'assuré paie PLUS.
String cfaEcartTarif(CfaFiche r) {
  final a = cfaNombre(r['prixNonAssure']), b = cfaNombre(r['prixAssure']);
  if (a == null || b == null || cfaVrai(r['nonCouvert'])) return '—';
  final e = b - a;
  return '${e > 0 ? '+' : ''}${money(e)}';
}

/// « Couverture » de la fiche détaillée d'un acte.
String cfaCouverture(CfaFiche r) {
  if (r['assurable'] == 'sos') return 'SOS seule';
  if (r['assurable'] == false || cfaVrai(r['nonCouvert'])) return 'Aucune';
  return 'Toutes compagnies';
}

// =============================================================================================================================================
// cfg-entetes, cfg-types-piece
// =============================================================================================================================================

/// Numérotation d'une pièce certifiante : « <SIGLE> n°/n°/CBG/<direction>/<année> » (le sigle de la clinique, lu de l'identité).
String cfaNumerotationPiece(CfaFiche t, int annee) => '${t['sigle']} n°/n°/${IdentiteClinique.sigle}/${t['direction']}/$annee';

List<CfaKpi> cfaKpisTypesPiece({required int types, required int tarifes, required int collisions, required int delivrees}) => [
      CfaKpi('Types de pièces', nombre(types), 'stamp', 'navy'),
      CfaKpi('Tarifés au catalogue', nombre(tarifes), 'tag', 'info'),
      CfaKpi('Sigles en collision', nombre(collisions), 'triangle-alert', collisions > 0 ? 'warning' : 'success'),
      CfaKpi('Pièces délivrées', nombre(delivrees), 'file-check', 'neutral'),
    ];

// =============================================================================================================================================
// cfg-rappels
// =============================================================================================================================================

/// `OCCASIONS` : (code, libellé, icône).
const cfaOccasions = <(String, String, String)>[
  ('anniversaire', 'Anniversaire du patient', 'cake'),
  ('nouvel_an', 'Nouvel an', 'party-popper'),
  ('fete', 'Fête ou jour férié', 'calendar-heart'),
  ('rdv', 'Rappel de rendez-vous', 'calendar-clock'),
  ('resultat', 'Résultat disponible', 'file-check-2'),
  ('echeance', 'Échéance de règlement', 'wallet'),
];

/// `VARIABLES` : (jeton, description). Un jeton inconnu reste tel quel dans le texte — visible, donc corrigeable.
const cfaVariablesMessage = <(String, String)>[
  ('{{nom}}', 'Nom et prénoms du patient'),
  ('{{clinique}}', 'Dénomination de la clinique'),
  ('{{date}}', 'Date de l’occasion'),
  ('{{telephone}}', 'Ligne téléphonique de la clinique'),
  ('{{rdv}}', 'Date et heure du rendez-vous'),
];

/// Les modèles proposés à l'amorçage, à valider par la Direction : (occasion, intitulé, texte).
const cfaModelesProposes = <(String, String, String)>[
  ('anniversaire', 'Anniversaire', 'Bonjour {{nom}}, toute l’équipe de {{clinique}} vous souhaite un très joyeux anniversaire et une excellente santé. Votre bien-être est notre raison d’être.'),
  ('nouvel_an', 'Vœux de nouvel an', 'Bonjour {{nom}}, {{clinique}} vous présente ses meilleurs vœux pour la nouvelle année : santé, paix et prospérité à vous et à toute votre famille.'),
  ('fete', 'Vœux de fête', 'Bonjour {{nom}}, {{clinique}} vous souhaite une excellente fête, entouré des vôtres.'),
  ('rdv', 'Rappel de rendez-vous', 'Bonjour {{nom}}, nous vous rappelons votre rendez-vous à {{clinique}} le {{rdv}}. Pour toute modification, appelez le {{telephone}}.'),
  ('resultat', 'Résultat disponible', 'Bonjour {{nom}}, votre résultat est disponible à {{clinique}}. Vous pouvez le retirer aux heures d’ouverture.'),
  ('echeance', 'Rappel de règlement', 'Bonjour {{nom}}, un reliquat reste dû sur votre dossier à {{clinique}}. Nous vous remercions de bien vouloir passer à la caisse.'),
];

const cfaNomExemple = 'ODJIPIAR YUDJOUVOU Mibu';

/// `apercu(texte)` : les variables remplacées par des valeurs d'exemple. [jour] = « AAAA-MM-JJ ». Un jeton inconnu reste tel quel.
String cfaApercuMessage(String texte, {required String clinique, required String telephone, required String jour}) {
  final d = DateTime.parse(jour);
  return texte
      .replaceAll('{{nom}}', cfaNomExemple)
      .replaceAll('{{clinique}}', clinique)
      .replaceAll('{{date}}', dateFR(d))
      .replaceAll('{{telephone}}', telephone)
      .replaceAll('{{rdv}}', '${dateFR(d)} à 09h00');
}

String cfaLibelleOccasion(Object? code) {
  for (final o in cfaOccasions) {
    if (o.$1 == code) return o.$2;
  }
  return '$code';
}

/// Texte d'un modèle dans le tableau : 90 caractères, puis « … ».
String cfaCoupeTexte(String t) => t.length > 90 ? '${t.substring(0, 90)}…' : t;

/// Résultat de « Préparer les anniversaires du jour ».
class CfaPreparation {
  CfaPreparation(this.rappels, this.concernes, this.erreur);
  final List<CfaFiche> rappels;
  final int concernes;

  /// Refus nommé (aucun modèle actif) ; `null` sinon.
  final String? erreur;
  int get faits => rappels.length;
  String get message => erreur ?? (concernes == 0 ? 'Aucun patient ne fête son anniversaire aujourd’hui.' : '$faits rappel(s) préparé(s) — $concernes anniversaire(s) aujourd’hui.');
}

/// `preparerAnniversaires` : un rappel par patient dont le jour et le mois de naissance sont ceux de [jour] — jamais deux fois le même (patient, date,
/// occasion). [prochaineRef] fournit les références `RPL-NNNNN` ; ce sont les patients ACTIFS qui comptent.
CfaPreparation cfaPreparerAnniversaires({
  required Iterable<CfaFiche> modeles,
  required Iterable<CfaFiche> patients,
  required Iterable<CfaFiche> rappelsExistants,
  required String jour,
  required String clinique,
  required String telephone,
  required String Function() prochaineRef,
}) {
  CfaFiche? modele;
  for (final m in modeles) {
    if (m['occasion'] == 'anniversaire' && cfaVrai(m['actif'])) {
      modele = m;
      break;
    }
  }
  if (modele == null) return CfaPreparation([], 0, 'Aucun modèle d’anniversaire actif.');
  final mmjj = jour.substring(5, 10);
  final concernes = patients.where((p) {
    final d = '${p['dateNaissance'] ?? ''}';
    return cfaVrai(p['dateNaissance']) && d.length >= 10 && d.substring(5, 10) == mmjj;
  }).toList();
  final faits = <CfaFiche>[];
  for (final p in concernes) {
    final nom = '${p['nom']} ${p['prenom']}';
    final deja = [...rappelsExistants, ...faits].any((r) => r['patientId'] == p['id'] && r['dateEcheance'] == jour && r['occasion'] == 'Anniversaire');
    if (deja) continue;
    faits.add({
      'reference': prochaineRef(),
      'occasion': 'Anniversaire',
      'patientId': p['id'],
      'destinataire': nom,
      'telephone': p['telephone'],
      'dateEcheance': jour,
      'etat': 'en_file',
      'message': cfaApercuMessage('${modele['texte']}', clinique: clinique, telephone: telephone, jour: jour).replaceAll(cfaNomExemple, nom),
    });
  }
  return CfaPreparation(faits, concernes.length, null);
}

// =============================================================================================================================================
// cfg-certificats
// =============================================================================================================================================

class CfaTypeCertificat {
  const CfaTypeCertificat(this.id, this.libelle, this.champs, this.trame);
  final String id;
  final String libelle;
  final List<String> champs;
  final String trame;
}

/// `TYPES_CERTIFICAT` : huit gabarits, la trame porte des {jetons} que le praticien complète.
const cfaTypesCertificat = <CfaTypeCertificat>[
  CfaTypeCertificat('repos', 'Certificat médical de repos', ['duree', 'dateDebut'],
      'Je soussigné(e), {praticien}, certifie avoir examiné ce jour {patient}, et atteste que son état de santé nécessite un repos de {duree} jour(s) à compter du {dateDebut}.'),
  CfaTypeCertificat('grossesse', 'Certificat médical de grossesse', ['termeSemaines', 'datePresumee'],
      'Je soussigné(e), {praticien}, certifie avoir examiné ce jour {patient}, et atteste qu’elle présente une grossesse évolutive de {termeSemaines} semaines d’aménorrhée, dont le terme est présumé au {datePresumee}.'),
  CfaTypeCertificat('accouchement', 'Attestation d’accouchement', ['dateAccouchement', 'sexeEnfant'],
      'Je soussigné(e), {praticien}, atteste que {patient} a accouché dans notre établissement le {dateAccouchement} d’un enfant de sexe {sexeEnfant}.'),
  CfaTypeCertificat('coups', 'Certificat médical de coups et blessures involontaires', ['constatations', 'itt'],
      'Je soussigné(e), {praticien}, certifie avoir examiné ce jour {patient} et avoir constaté : {constatations}. Ces lésions entraînent une incapacité totale de travail de {itt} jour(s), sauf complications.'),
  CfaTypeCertificat('initial', 'Certificat médical initial', ['constatations', 'itt'],
      'Je soussigné(e), {praticien}, certifie avoir examiné ce jour {patient} et avoir constaté : {constatations}. Incapacité totale de travail estimée à {itt} jour(s), sous réserve de complications ultérieures.'),
  CfaTypeCertificat('guerison', 'Certificat médical de guérison', ['affection', 'dateGuerison'],
      'Je soussigné(e), {praticien}, certifie que {patient}, traité(e) pour {affection}, est déclaré(e) guéri(e) depuis le {dateGuerison} et peut reprendre ses activités.'),
  CfaTypeCertificat('prenuptial', 'Certificat prénuptial', ['examens'],
      'Je soussigné(e), {praticien}, certifie avoir examiné ce jour {patient} dans le cadre d’un examen prénuptial. Examens pratiqués : {examens}. Aucune contre-indication médicale au mariage n’a été relevée.'),
  CfaTypeCertificat('aptitude', 'Certificat d’aptitude physique', ['activite'],
      'Je soussigné(e), {praticien}, certifie avoir examiné ce jour {patient} et n’avoir constaté aucune contre-indication à la pratique de : {activite}.'),
];

CfaTypeCertificat? cfaTypeCertificat(Object? id) {
  for (final t in cfaTypesCertificat) {
    if (t.id == id) return t;
  }
  return null;
}

/// `composer(trame, valeurs)` : remplace les {jetons}. Une valeur absente ou vide devient « …………… » ; une date ISO s'écrit JJ/MM/AAAA.
String cfaComposerCertificat(String trame, Map<String, Object?> valeurs) {
  final iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  return trame.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    final v = valeurs[m.group(1)];
    if (v == null || v == '') return '……………';
    final s = cfaTexte(v);
    if (iso.hasMatch(s)) return dateFR(DateTime.parse(s));
    return s;
  });
}

/// Définition d'un champ de saisie d'un certificat : (libellé, type, min, max, lignes, plein, options).
class CfaChampCertificat {
  const CfaChampCertificat(this.libelle, {this.type = 'texte', this.min, this.max, this.lignes, this.plein = false, this.options = const []});
  final String libelle;
  final String type;
  final num? min;
  final num? max;
  final int? lignes;
  final bool plein;
  final List<String> options;
}

const cfaChampsCertificat = <String, CfaChampCertificat>{
  'duree': CfaChampCertificat('Durée du repos (jours)', type: 'nombre', min: 1),
  'dateDebut': CfaChampCertificat('À compter du', type: 'date'),
  'termeSemaines': CfaChampCertificat('Terme (semaines d’aménorrhée)', type: 'nombre', min: 1, max: 45),
  'datePresumee': CfaChampCertificat('Terme présumé', type: 'date'),
  'dateAccouchement': CfaChampCertificat('Date d’accouchement', type: 'date'),
  'sexeEnfant': CfaChampCertificat('Sexe de l’enfant', type: 'select', options: ['masculin', 'féminin']),
  'constatations': CfaChampCertificat('Constatations médicales', type: 'zone', lignes: 3, plein: true),
  'itt': CfaChampCertificat('Incapacité totale de travail (jours)', type: 'nombre', min: 0),
  'affection': CfaChampCertificat('Affection traitée', plein: true),
  'dateGuerison': CfaChampCertificat('Date de guérison', type: 'date'),
  'examens': CfaChampCertificat('Examens pratiqués', type: 'zone', lignes: 2, plein: true),
  'activite': CfaChampCertificat('Activité concernée', plein: true),
};

/// Numéro d'un certificat : « CERT-2026-NNNN » — l'année est ÉCRITE EN DUR par la maquette (écart E842), le rang compte les fiches (archivées comprises).
String cfaNumeroCertificat(int nbToutes) => 'CERT-2026-${(nbToutes + 1).toString().padLeft(4, '0')}';

/// « Délivrés ce mois » : la maquette ne compare que le NUMÉRO DU MOIS (écart E843 : le mois d'octobre d'une autre année compte aussi).
int cfaDelivresCeMois(Iterable<CfaFiche> rows, DateTime auj) =>
    rows.where((r) {
      final d = DateTime.tryParse('${r['date'] ?? ''}');
      return d != null && d.month == auj.month;
    }).length;

List<CfaKpi> cfaKpisCertificats({required int delivres, required int types, required int ceMois, required int praticiens}) => [
      CfaKpi('Certificats délivrés', nombre(delivres), 'file-badge', 'navy'),
      CfaKpi('Types au catalogue', nombre(types), 'list', 'info'),
      CfaKpi('Délivrés ce mois', nombre(ceMois), 'calendar-check', 'success'),
      CfaKpi('Praticiens signataires', nombre(praticiens), 'stethoscope', 'neutral'),
    ];

// =============================================================================================================================================
// cfg-natures-facture
// =============================================================================================================================================

/// Création d'une nature : code par défaut = quatre premières lettres du libellé en majuscules, rang = nombre de fiches + 1.
CfaFiche cfaFicheNature(Map<String, Object?> saisie, int nbToutes) {
  final v = {...saisie};
  if (!cfaVrai(v['code'])) {
    final l = cfaVrai(v['libelle']) ? '${v['libelle']}' : 'NAT';
    v['code'] = (l.length > 4 ? l.substring(0, 4) : l).toUpperCase();
  }
  v['ordre'] = nbToutes + 1;
  return v;
}

List<CfaKpi> cfaKpisNatures({required int natures, required int secteurs, required int archivees}) => [
      CfaKpi('Natures disponibles', nombre(natures), 'receipt-text', 'navy'),
      CfaKpi('Secteurs couverts', nombre(secteurs), 'layers', 'info'),
      CfaKpi('Natures archivées', nombre(archivees), 'archive', 'neutral', 'Restaurables depuis la corbeille'),
    ];

// =============================================================================================================================================
// cfg-imagerie-catalogue
// =============================================================================================================================================

/// `transformVariable` : les choix saisis « a|b|c » deviennent une liste (vides retirés), `null` s'il n'y en a pas ; le rang est un nombre.
CfaFiche cfaTransformVariableImagerie(Map<String, Object?> saisie) {
  final v = {...saisie};
  final t = v.remove('optionsTexte');
  v['options'] = cfaVrai(t) ? ('$t'.split('|').map((x) => x.trim()).where((x) => x.isNotEmpty).toList()) : null;
  if (v['ordre'] != null) v['ordre'] = cfaNombre(v['ordre']);
  return v;
}

/// Le champ « choix » d'une variable à l'édition : relu depuis la liste, séparée par « | ».
String cfaOptionsTexte(CfaFiche v) {
  final o = v['options'];
  return o is List ? o.join('|') : '';
}

List<CfaKpi> cfaKpisImagerie({required int examens, required int variables, required int fermees, required int listes}) => [
      CfaKpi('Examens au catalogue', nombre(examens), 'scan-line', 'navy'),
      CfaKpi('Variables de compte rendu', nombre(variables), 'list-checks', 'info'),
      CfaKpi('Variables fermées', nombre(fermees), 'eye-off', 'neutral'),
      CfaKpi('Listes de choix', nombre(listes), 'chevrons-up-down', 'neutral', 'La demande du brouillon manuscrit'),
    ];

// =============================================================================================================================================
// cfg-entetes, cfg-branding : l'identité légale UNIQUE (arbitrage du 31/08/2026)
// =============================================================================================================================================

/// Ce que l'écran affiche à la place d'une mention que la Direction n'a pas encore renseignée (l'écran le DIT ; la pièce imprimée, elle, n'imprime rien).
const cfaMentionARenseigner = 'À renseigner par la Direction (non imprimée tant qu’elle est vide)';

String _ouARenseigner(String v) => v.isEmpty ? cfaMentionARenseigner : v;

/// Les quatre indicateurs de l'écran des en-têtes : UN IFU, UN RCCM, UNE autorisation imprimés, sur tous les états. Une mention vide se compte 0.
List<CfaKpi> cfaKpisEntetes() => [
      CfaKpi('IFU imprimé', IdentiteClinique.ifu.isEmpty ? '0' : '1', 'hash', IdentiteClinique.ifu.isEmpty ? 'warning' : 'success',
          IdentiteClinique.ifu.isEmpty ? null : IdentiteClinique.ifu),
      CfaKpi('RCCM imprimé', IdentiteClinique.rccm.isEmpty ? '0' : '1', 'scale', IdentiteClinique.rccm.isEmpty ? 'warning' : 'success',
          IdentiteClinique.rccm.isEmpty ? null : IdentiteClinique.rccm),
      IdentiteClinique.autorisation.isEmpty
          ? const CfaKpi('Autorisation d’ouverture', '0', 'stamp', 'warning', 'À renseigner')
          : const CfaKpi('Autorisation d’ouverture', '1', 'stamp', 'success'),
      const CfaKpi('États alimentés', 'Tous', 'printer', 'navy'),
    ];

/// La grille « Identité légale imprimée sur chaque état ». Une mention vide le dit plutôt que de laisser une case muette.
List<(String, String)> cfaGrilleIdentite() => [
      ('Dénomination', [IdentiteClinique.nom, if (CfaIdentite.forme.isNotEmpty) CfaIdentite.forme].join(' — ')),
      ('Forme juridique', _ouARenseigner(CfaIdentite.forme)),
      ('Devise de l’établissement', IdentiteClinique.slogan),
      ('Adresse', [CfaIdentite.adresse, IdentiteClinique.bp].where((x) => x.isNotEmpty).join(' · ')),
      ('Téléphones', IdentiteClinique.telephones.join(' / ')),
      ('Ligne rendez-vous', CfaIdentite.telephoneRdv),
      ('Courriel', IdentiteClinique.email),
      ('IFU', IdentiteClinique.ifu),
      ('RCCM', IdentiteClinique.rccm),
      ('Autorisation d’ouverture', _ouARenseigner(IdentiteClinique.autorisation)),
      ('Formule de politesse des factures', _ouARenseigner(IdentiteClinique.formulePolitesse)),
      ('Autorisation d’exercice', 'Non imprimée — ${CfaIdentite.autorisationExerciceMotif}'),
    ];

const cfaNoteAnciennesPieces =
    'Les pièces émises AVANT l’unification portent d’autres identités — trois IFU, trois RCCM et deux autorisations relevés sur les 37 documents collectés (certificats médico-légaux, rapport médical, comptes rendus de laboratoire et d’imagerie). Ces pièces restent valables et documentées par leurs scans dans docs/ ; elles ne sont simplement plus reproduites. Un document ancien qui diverge du présent en-tête n’est donc pas un faux.';

/// Les valeurs du formulaire d'identité : l'identité EN VIGUEUR (initiale, ou celle que la Direction a enregistrée). Les mentions inconnues restent
/// VIDES (forme juridique, autorisation d'ouverture, formule de politesse) : la Direction les remplit, et la pièce les reprend.
Map<String, Object?> cfaValeursIdentite({Map<String, Object?>? options}) => {
      'nom': IdentiteClinique.nom,
      'nomCourt': IdentiteClinique.nomCourt,
      'sigle': IdentiteClinique.sigle,
      'forme': IdentiteClinique.forme,
      'slogan': IdentiteClinique.slogan,
      'adresse': IdentiteClinique.adresse,
      'bp': IdentiteClinique.bp,
      'telephones': IdentiteClinique.telephones.join(' / '),
      'email': IdentiteClinique.email,
      'ifu': IdentiteClinique.ifu,
      'rccm': IdentiteClinique.rccm,
      'autorisation': IdentiteClinique.autorisation,
      'formulePolitesse': IdentiteClinique.formulePolitesse,
      'doubleLogo': options?['doubleLogo'] ?? true,
      'piedPage': options?['piedPage'] ?? true,
      'filigrane': options?['filigrane'] ?? '',
    };

/// Le pied du papier à en-tête, tel que l'aperçu le montre.
String cfaPiedApercu(String utilisateur, DateTime quand) =>
    '${IdentiteClinique.piedLegal} · Document généré par $utilisateur le ${dateHeure(quand)} · Réf. ${IdentiteClinique.sigle}-XXXXXXXX-0001';

/// Le message de la bascule d'une variable : l'état se lit AVANT l'écriture (écart E845, corrigé dans la maquette).
({String message, String? detail}) cfaMessageBascule({required bool etaitFermee}) => etaitFermee
    ? (message: 'Variable rouverte.', detail: null)
    : (message: 'Variable fermée.', detail: 'Les comptes rendus déjà rendus la conservent.');
