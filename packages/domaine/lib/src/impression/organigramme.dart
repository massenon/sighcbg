import '../configuration/cfa_regles.dart' show cfaNombre, cfaVrai;
import '../format/format_fr.dart';

/// L'ORGANIGRAMME IMPRIMÉ : une FICHE DOCUMENTAIRE paysage (cartouche à quatre cases, graphe, légende, pied normalisé) dessinée À PARTIR DES FICHES DE
/// POSTES, jamais d'un tracé écrit dans le moteur. Chaque poste porte de quoi se redessiner (`niveau`, centre `x`/`y`, `largeur`/`hauteur`, `lien`,
/// `barre`, coude) ; le moteur ne fait que les lire, les lier et les ajuster à la page. L'aperçu et le PDF consomment la MÊME [SceneOrganigramme] : un
/// seul modèle, deux rendus. Une constante de ce fichier n'est qu'une GRAINE — elle amorce la fiche `organigramme` de la collection
/// [ficheDocCollection], qui est la valeur en force (règle de la Direction du 09/11/2026 : tout paramétrable est en base, avec un défaut).

/// La collection des paramètres de fiches documentaires (une fiche par document : référence, date, version, titres, mention de propriété, grille).
const String ficheDocCollection = 'fichesDocumentaires';

/// L'identifiant de la fiche de l'organigramme dans cette collection.
const String ficheDocOrganigramme = 'organigramme';

/// Les types de lien d'un poste à son rattachement : voir [organigrammeScene].
const List<String> organigrammeLiens = ['hierarchique', 'accole', 'direct'];

double? _d(Object? v) => cfaNombre(v)?.toDouble();

/// La GRILLE du graphe : l'unité est celle des fiches de postes (une « unité de grille »), l'échelle réelle se calcule à la page.
class ParametresGrille {
  const ParametresGrille({
    this.largeur = 1520,
    this.hauteur = 850,
    this.xNiveaux = 350,
    this.niveauxY = const {},
    this.niveauxX = const {},
    this.police = 17,
    this.caseLargeur = 110,
    this.caseHauteur = 44,
    this.legendeParPage = 19,
  });

  /// La graine : le gabarit du document de référence FCH_GRH_006, lu sur sa première page.
  static const ParametresGrille graine = ParametresGrille(niveauxY: {1: 110, 2: 192, 3: 314, 4: 557, 5: 679, 6: 801}, niveauxX: {1: 340, 2: 340, 3: 340, 4: 345, 5: 350, 6: 354});

  /// Dimensions du cadre du graphe, en unités de grille (le cadre s'agrandit si un poste en sort).
  final double largeur, hauteur;

  /// Abscisse des numéros de niveau, en marge du graphe.
  final double xNiveaux;

  /// Ordonnée du numéro de chaque niveau (absente : moyenne des centres des cases du niveau).
  final Map<int, double> niveauxY;

  /// Abscisse propre à un niveau (absente : [xNiveaux]) : le numéro se range à côté de la case la plus proche, comme au document.
  final Map<int, double> niveauxX;

  /// Corps du texte des cases, en unités de grille.
  final double police;

  /// Taille d'une case dont la fiche ne dit pas la sienne.
  final double caseLargeur, caseHauteur;

  /// Nombre de lignes de légende par page.
  final int legendeParPage;

  factory ParametresGrille.depuisFiche(Object? brut) {
    if (brut is! Map) return graine;
    Map<int, double> table(String cle) {
      final r = <int, double>{};
      final m = brut[cle];
      if (m is Map) {
        for (final e in m.entries) {
          final k = int.tryParse('${e.key}');
          final v = _d(e.value);
          if (k != null && v != null) r[k] = v;
        }
      }
      return r;
    }

    final y = table('niveauxY'), nx = table('niveauxX');
    double pos(String k, double defaut) {
      final v = _d(brut[k]);
      return v != null && v > 0 ? v : defaut;
    }

    final par = _d(brut['legendeParPage'])?.toInt();
    return ParametresGrille(
      largeur: pos('largeur', graine.largeur),
      hauteur: pos('hauteur', graine.hauteur),
      xNiveaux: _d(brut['xNiveaux']) ?? graine.xNiveaux,
      niveauxY: y.isEmpty ? graine.niveauxY : y,
      niveauxX: nx.isEmpty && !brut.containsKey('niveauxX') ? graine.niveauxX : nx,
      police: pos('police', graine.police),
      caseLargeur: pos('caseLargeur', graine.caseLargeur),
      caseHauteur: pos('caseHauteur', graine.caseHauteur),
      legendeParPage: par != null && par > 0 ? par : graine.legendeParPage,
    );
  }

  Map<String, Object?> versFiche() => {
        'largeur': largeur,
        'hauteur': hauteur,
        'xNiveaux': xNiveaux,
        'niveauxY': {for (final e in niveauxY.entries) '${e.key}': e.value},
        'niveauxX': {for (final e in niveauxX.entries) '${e.key}': e.value},
        'police': police,
        'caseLargeur': caseLargeur,
        'caseHauteur': caseHauteur,
        'legendeParPage': legendeParPage,
      };
}

/// Les paramètres d'une fiche documentaire : cartouche (titre en deux étages, référence, date, version), mention de propriété, grille du graphe.
class ParametresFiche {
  const ParametresFiche({
    required this.reference,
    required this.date,
    required this.version,
    required this.titreHaut,
    required this.titre,
    required this.mention,
    this.grille = ParametresGrille.graine,
  });

  /// La graine de la fiche de l'organigramme : les mentions du document remis par la Direction (FCH_GRH_006, 03/05/2023, version 01).
  static const ParametresFiche graine = ParametresFiche(
    reference: 'FCH_GRH_006',
    date: '2023-05-03',
    version: '01',
    titreHaut: 'FICHE',
    titre: 'ORGANIGRAMME',
    mention: 'Ce document demeure strictement la propriété de la Clinique BAGUIDI l’AS de Cœur',
  );

  final String reference;

  /// Date ISO (AAAA-MM-JJ) ; la fiche l'imprime en JJ/MM/AAAA.
  final String date;
  final String version;
  final String titreHaut;
  final String titre;
  final String mention;
  final ParametresGrille grille;

  /// Une fiche de [ficheDocCollection] relue ; chaque champ absent ou vide retombe sur la graine.
  factory ParametresFiche.depuisFiche(Map<String, Object?>? f) {
    if (f == null) return graine;
    String t(String k, String defaut) {
      final v = f[k];
      return v == null || '$v'.trim().isEmpty ? defaut : '$v'.trim();
    }

    return ParametresFiche(
      reference: t('reference', graine.reference),
      date: t('date', graine.date),
      version: t('version', graine.version),
      titreHaut: t('titreHaut', graine.titreHaut),
      titre: t('titre', graine.titre),
      mention: t('mention', graine.mention),
      grille: ParametresGrille.depuisFiche(f['grille']),
    );
  }

  /// La fiche telle qu'elle s'écrit au magasin (semence).
  Map<String, Object?> versFiche({String id = ficheDocOrganigramme}) => {
        'id': id,
        'statut': 'actif',
        'reference': reference,
        'date': date,
        'version': version,
        'titreHaut': titreHaut,
        'titre': titre,
        'mention': mention,
        'grille': grille.versFiche(),
      };

  /// La date imprimée (JJ/MM/AAAA) ; une date illisible s'imprime telle quelle plutôt que de disparaître.
  String get dateImprimee {
    final d = DateTime.tryParse(date);
    return d == null ? date : dateFR(d);
  }

  /// Les quatre lignes de la case de droite du cartouche. [page] et [total] viennent de la pagination réelle : « Page n sur N » ne se saisit pas.
  List<String> lignesCartouche(int page, int total) => [
        'Référence : $reference',
        'Date : $dateImprimee',
        'Version $version',
        'Page $page sur $total',
      ];
}

/// Une case du graphe, en unités de grille (coin haut-gauche).
class CaseOrg {
  const CaseOrg({required this.id, required this.texte, required this.x, required this.y, required this.l, required this.h, required this.niveau, this.titre = ''});
  final String id;
  final String texte;

  /// Le titre PORTÉ par l'agent titulaire (ex. « SG »), écrit sous le code dans la boîte ; vide quand l'agent n'en porte pas.
  final String titre;
  final double x, y, l, h;
  final int niveau;
  double get cx => x + l / 2;
  double get cy => y + h / 2;
  double get bas => y + h;
}

/// Un trait fin du graphe.
class TraitOrg {
  const TraitOrg(this.x1, this.y1, this.x2, this.y2);
  final double x1, y1, x2, y2;
  @override
  bool operator ==(Object o) => o is TraitOrg && o.x1 == x1 && o.y1 == y1 && o.x2 == x2 && o.y2 == y2;
  @override
  int get hashCode => Object.hash(x1, y1, x2, y2);
}

/// Le numéro d'un niveau, en marge.
class NiveauOrg {
  const NiveauOrg(this.n, this.x, this.y);
  final int n;
  final double x, y;
}

/// La scène complète du graphe, prête à dessiner par n'importe quel moteur.
class SceneOrganigramme {
  const SceneOrganigramme({required this.largeur, required this.hauteur, required this.police, required this.cases, required this.traits, required this.niveaux});
  final double largeur, hauteur, police;
  final List<CaseOrg> cases;
  final List<TraitOrg> traits;
  final List<NiveauOrg> niveaux;
}

/// L'ajustement d'une scène à une zone : une échelle uniforme et le décalage qui centre le graphe.
class AjustementScene {
  const AjustementScene(this.echelle, this.dx, this.dy);
  final double echelle, dx, dy;
}

AjustementScene ajusterScene(SceneOrganigramme s, double zoneLargeur, double zoneHauteur) {
  final e = (zoneLargeur / s.largeur) < (zoneHauteur / s.hauteur) ? zoneLargeur / s.largeur : zoneHauteur / s.hauteur;
  return AjustementScene(e, (zoneLargeur - s.largeur * e) / 2, (zoneHauteur - s.hauteur * e) / 2);
}

/// Le texte d'une case : le code abrégé, ou à défaut l'intitulé complet (un poste sans abréviation s'écrit en toutes lettres).
String organigrammeTexteCase(Map<String, Object?> p) => cfaVrai(p['code']) ? '${p['code']}'.trim() : '${p['poste'] ?? ''}'.trim();

/// Le titre porté par le titulaire du poste, tel que la fiche le transmet (`titrePorte`, posé par l'application depuis le dossier du personnel) : « (SG) ».
String organigrammeTitreCase(Map<String, Object?> p) {
  final t = '${p['titrePorte'] ?? ''}'.trim();
  return t.isEmpty ? '' : '($t)';
}

/// Construit la scène depuis les postes ACTIFS. Règles de lecture des fiches :
///  - `niveau` (1 à 6 et au-delà), `x` / `y` (centre), `largeur` / `hauteur` : absents, le poste est PLACÉ — au niveau de son rattachement + 1, à la
///    droite de la dernière case de ce niveau, à l'ordonnée du niveau ;
///  - `lien` : `hierarchique` (défaut) descend du rattachement jusqu'à la `barre` (ordonnée de la barre horizontale ; absente : à mi-chemin), avec un
///    `coudeX` / `coudeY` facultatif pour le tronc qui se décale ; `accole` tire un trait horizontal à la hauteur de la case ; `direct` descend droit du
///    rattachement à la case. Un poste dont le rattachement est absent ou archivé n'a pas de lien.
SceneOrganigramme organigrammeScene(Iterable<Map<String, Object?>> postesActifs, ParametresGrille g) {
  final postes = postesActifs.toList();
  final parId = {for (final p in postes) '${p['id']}': p};
  int niveauDe(Map<String, Object?> p, [int garde = 0]) {
    final n = _d(p['niveau'])?.toInt();
    if (n != null && n > 0) return n;
    final par = parId['${p['parentId']}'];
    if (par == null || garde > 20) return 1;
    return niveauDe(par, garde + 1) + 1;
  }

  // 1. Les cases dont la fiche donne la place ; 2. les autres, posées à la suite.
  final placees = <String, CaseOrg>{};
  final niveaux = <String, int>{for (final p in postes) '${p['id']}': niveauDe(p)};
  CaseOrg poser(Map<String, Object?> p, double cx, double cy) {
    final l = _d(p['largeur']) ?? g.caseLargeur;
    final titre = organigrammeTitreCase(p);
    var h = _d(p['hauteur']) ?? g.caseHauteur;
    // Un titre porté s'écrit sur une seconde ligne : la boîte grandit autour de son centre, sans quoi le titre sortirait du cadre.
    if (titre.isNotEmpty && h < g.police * 2.9) h = g.police * 2.9;
    return CaseOrg(id: '${p['id']}', texte: organigrammeTexteCase(p), titre: titre, x: cx - l / 2, y: cy - h / 2, l: l, h: h, niveau: niveaux['${p['id']}']!);
  }

  for (final p in postes) {
    final x = _d(p['x']), y = _d(p['y']);
    if (x != null && y != null) placees['${p['id']}'] = poser(p, x, y);
  }
  double yNiveau(int n) {
    final connues = [for (final c in placees.values) if (c.niveau == n) c.cy];
    if (g.niveauxY.containsKey(n)) return g.niveauxY[n]!;
    if (connues.isNotEmpty) return connues.reduce((a, b) => a + b) / connues.length;
    return 70.0 + (n - 1) * 140;
  }

  for (final p in postes) {
    if (placees.containsKey('${p['id']}')) continue;
    final n = niveaux['${p['id']}']!;
    final l = _d(p['largeur']) ?? g.caseLargeur;
    final memeNiveau = [for (final c in placees.values) if (c.niveau == n) c.x + c.l];
    final cx = _d(p['x']) ?? (memeNiveau.isEmpty ? (placees['${p['parentId']}']?.cx ?? g.largeur / 2) : memeNiveau.reduce((a, b) => a > b ? a : b) + 24 + l / 2);
    placees['${p['id']}'] = poser(p, cx, _d(p['y']) ?? yNiveau(n));
  }

  final traits = <TraitOrg>[];
  void relier(List<(double, double)> pts) {
    for (var i = 0; i + 1 < pts.length; i++) {
      final t = TraitOrg(pts[i].$1, pts[i].$2, pts[i + 1].$1, pts[i + 1].$2);
      if ((t.x1 != t.x2 || t.y1 != t.y2) && !traits.contains(t)) traits.add(t);
    }
  }

  for (final p in postes) {
    final c = placees['${p['id']}']!;
    final par = placees['${p['parentId']}'];
    if (par == null || identical(par, c)) continue;
    final lien = '${p['lien'] ?? 'hierarchique'}';
    switch (lien) {
      case 'accole':
        relier([(par.cx, par.bas), (par.cx, c.cy)]);
        relier([(par.cx, c.cy), (c.cx > par.cx ? c.x : c.x + c.l, c.cy)]);
      case 'direct':
        final gauche = par.x > c.x ? par.x : c.x, droite = par.x + par.l < c.x + c.l ? par.x + par.l : c.x + c.l;
        final x = droite > gauche ? (gauche + droite) / 2 : c.cx;
        relier([(x, par.bas), (x, c.y)]);
      default:
        final barre = _d(p['barre']) ?? (par.bas + c.y) / 2;
        final cx = _d(p['coudeX']), cy = _d(p['coudeY']);
        relier([
          (par.cx, par.bas),
          if (cx != null && cy != null) ...[(par.cx, cy), (cx, cy), (cx, barre)] else (par.cx, barre),
          (c.cx, barre),
          (c.cx, c.y),
        ]);
    }
  }

  final cases = placees.values.toList();
  var largeur = g.largeur, hauteur = g.hauteur;
  for (final c in cases) {
    if (c.x + c.l + 12 > largeur) largeur = c.x + c.l + 12;
    if (c.y + c.h + 12 > hauteur) hauteur = c.y + c.h + 12;
  }
  final nums = {for (final c in cases) c.niveau}.toList()..sort();
  final marges = [
    for (final n in nums)
      NiveauOrg(n, g.niveauxX[n] ?? g.xNiveaux, g.niveauxY[n] ?? (() {
        final ys = [for (final c in cases) if (c.niveau == n) c.cy];
        return ys.reduce((a, b) => a + b) / ys.length;
      })()),
  ];
  return SceneOrganigramme(largeur: largeur, hauteur: hauteur, police: g.police, cases: cases, traits: traits, niveaux: marges);
}

/// Une ligne de légende : l'abréviation en gras, son sens.
class LigneLegende {
  const LigneLegende(this.code, this.libelle);
  final String code, libelle;
}

/// La légende, GÉNÉRÉE des mêmes fiches : un poste qui porte un code y figure (`codeLegende` si la légende l'écrit autrement que la case), dans l'ordre de
/// `ordreLegende` puis de la collection. Un poste sans code s'écrit en toutes lettres sur le graphe et n'a rien à expliquer.
List<LigneLegende> organigrammeLegende(Iterable<Map<String, Object?>> postesActifs) {
  final avec = [
    for (final (i, p) in postesActifs.indexed)
      if (cfaVrai(p['code'])) (i, p)
  ];
  avec.sort((a, b) {
    final oa = _d(a.$2['ordreLegende']), ob = _d(b.$2['ordreLegende']);
    if (oa != null && ob != null && oa != ob) return oa.compareTo(ob);
    if (oa != null && ob == null) return -1;
    if (oa == null && ob != null) return 1;
    return a.$1.compareTo(b.$1);
  });
  return [
    for (final (_, p) in avec) LigneLegende(cfaVrai(p['codeLegende']) ? '${p['codeLegende']}'.trim() : '${p['code']}'.trim(), '${p['poste'] ?? ''}'.trim())
  ];
}

/// Découpe la légende en pages de [parPage] lignes (saut de page propre : une ligne n'est jamais coupée).
List<List<LigneLegende>> paginerLegende(List<LigneLegende> lignes, int parPage) {
  final n = parPage < 1 ? 1 : parPage;
  return [for (var i = 0; i < lignes.length; i += n) lignes.sublist(i, i + n > lignes.length ? lignes.length : i + n)];
}

/// Le nombre de pages de la fiche : le graphe, puis les pages de légende (aucune si la légende est vide).
int organigrammePages(int lignesLegende, int parPage) => 1 + (lignesLegende == 0 ? 0 : ((lignesLegende + (parPage < 1 ? 1 : parPage) - 1) ~/ (parPage < 1 ? 1 : parPage)));
