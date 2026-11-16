import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef P = Map<String, Object?>;

/// L'organigramme imprimé : le placement, les liens, la légende et la pagination se LISENT sur les fiches de postes — aucune coordonnée dans le moteur.
void main() {
  final g = ParametresGrille.graine;
  P poste(String id, {String? code, String? parent, int? niveau, double? x, double? y, double? l, double? h, String? lien, double? barre, String? libelle}) => {
        'id': id,
        'statut': 'actif',
        'poste': libelle ?? 'Poste $id',
        if (code != null) 'code': code,
        if (parent != null) 'parentId': parent,
        if (niveau != null) 'niveau': niveau,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (l != null) 'largeur': l,
        if (h != null) 'hauteur': h,
        if (lien != null) 'lien': lien,
        if (barre != null) 'barre': barre,
      };

  group('modifiable : le graphe suit les fiches', () {
    final racine = poste('A', code: 'DG', niveau: 1, x: 800, y: 40, l: 200, h: 40);
    final mg = poste('B', code: 'MG', parent: 'A', niveau: 2, x: 600, y: 160, l: 100, h: 40, barre: 120);
    final rl = poste('C', code: 'RL', parent: 'A', niveau: 2, x: 1000, y: 160, l: 100, h: 40, barre: 120);

    test('un poste réaffecté à un autre rattachement : son trait part désormais de ce rattachement', () {
      final avant = organigrammeScene([racine, mg, rl], g);
      expect(avant.traits.any((t) => t.x1 == 800 && t.y1 == 60), isTrue, reason: 'MG et RL descendent de DG');
      // MG passe sous RL : le tronc part du bas de RL (centre 1000), plus de DG.
      final apres = organigrammeScene([racine, {...mg, 'parentId': 'C', 'barre': 200, 'y': 260}, rl], g);
      final c = apres.cases.firstWhere((k) => k.id == 'B');
      expect(apres.traits.any((t) => t.x1 == 1000 && t.y1 == 180 && t.x2 == 1000), isTrue, reason: 'le tronc part du bas de RL');
      expect(apres.traits.any((t) => t.x2 == c.cx && t.y2 == c.y), isTrue, reason: 'et rejoint le haut de MG');
      expect(apres.traits.where((t) => t.x2 == 600 && t.y2 == 140).isEmpty, isTrue, reason: 'plus de descente depuis la barre de DG');
    });

    test('le titre porté s’écrit dans la boîte : « (SG) » ; la boîte grandit pour le contenir ; sans titre rien ne change', () {
      final sans = organigrammeScene([racine, mg], g);
      expect(sans.cases.every((k) => k.titre.isEmpty), isTrue);
      final avec = organigrammeScene([racine, {...mg, 'titrePorte': 'SG'}], g);
      final k = avec.cases.firstWhere((c) => c.id == 'B');
      expect(k.titre, '(SG)');
      expect(k.texte, 'MG', reason: 'le code reste');
      expect(k.h, greaterThanOrEqualTo(g.police * 2.9));
      expect(k.cy, 160, reason: 'la boîte grandit autour de son centre');
      expect('${avec.cases.firstWhere((c) => c.id == 'A').h}', '40.0');
      expect(organigrammeScene([racine, {...mg, 'titrePorte': '   '}], g).cases.last.titre, '');
    });

    test('les descendants d’un poste : un poste ne peut pas être rattaché à l’un d’eux', () {
      final postes = [racine, mg, rl, poste('D', parent: 'C'), poste('E', parent: 'D')];
      expect(cfaDescendantsDe(postes, 'C'), {'D', 'E'});
      expect(cfaDescendantsDe(postes, 'A'), {'B', 'C', 'D', 'E'});
      expect(cfaDescendantsDe(postes, 'E'), isEmpty);
    });
  });

  group('scène', () {
    final racine = poste('A', code: 'DG', niveau: 1, x: 800, y: 40, l: 200, h: 40);
    test('une case prend la place de sa fiche : centre, largeur, hauteur', () {
      final s = organigrammeScene([racine], g);
      final c = s.cases.single;
      expect((c.x, c.y, c.l, c.h), (700.0, 20.0, 200.0, 40.0));
      expect((c.cx, c.cy, c.bas), (800.0, 40.0, 60.0));
      expect(c.texte, 'DG');
    });

    test('un poste sans code s’écrit en toutes lettres sur sa case', () {
      final s = organigrammeScene([poste('B', libelle: 'Responsable Comptable', niveau: 3, x: 100, y: 200)], g);
      expect(s.cases.single.texte, 'Responsable Comptable');
    });

    test('lien hiérarchique : tronc, barre à l’ordonnée de la fiche, descente jusqu’au haut de la case', () {
      final s = organigrammeScene([racine, poste('B', code: 'MG', parent: 'A', niveau: 2, x: 600, y: 160, l: 100, h: 40, barre: 120)], g);
      expect(s.traits, containsAll([const TraitOrg(800, 60, 800, 120), const TraitOrg(800, 120, 600, 120), const TraitOrg(600, 120, 600, 140)]));
    });

    test('une barre commune n’est pas dessinée deux fois (traits dédoublonnés)', () {
      final s = organigrammeScene([
        racine,
        poste('B', code: 'MG', parent: 'A', niveau: 2, x: 600, y: 160, l: 100, h: 40, barre: 120),
        poste('C', code: 'MP', parent: 'A', niveau: 2, x: 1000, y: 160, l: 100, h: 40, barre: 120),
      ], g);
      expect(s.traits.where((t) => t == const TraitOrg(800, 60, 800, 120)).length, 1);
    });

    test('sans barre déclarée : à mi-chemin entre le bas du rattachement et le haut de la case', () {
      final s = organigrammeScene([racine, poste('B', code: 'MG', parent: 'A', niveau: 2, x: 800, y: 200, l: 100, h: 40)], g);
      expect(s.traits, contains(const TraitOrg(800, 60, 800, 120)));
      expect(s.traits, contains(const TraitOrg(800, 120, 800, 180)));
    });

    test('lien accolé : trait horizontal à la hauteur de la case, du tronc au bord de la case', () {
      final s = organigrammeScene([racine, poste('B', code: 'SM', parent: 'A', niveau: 1, x: 1000, y: 100, l: 100, h: 40, lien: 'accole')], g);
      expect(s.traits, contains(const TraitOrg(800, 100, 950, 100)));
    });

    test('lien direct : descente droite au milieu du recouvrement des deux cases', () {
      final s = organigrammeScene([
        poste('A', code: 'RL', niveau: 3, x: 500, y: 100, l: 100, h: 40),
        poste('B', code: 'RSI', parent: 'A', niveau: 4, x: 480, y: 300, l: 100, h: 40, lien: 'direct'),
      ], g);
      expect(s.traits, contains(const TraitOrg(490, 120, 490, 280)));
    });

    test('un coude décale le tronc : trait vers la droite à la hauteur du coude, puis descente jusqu’à la barre', () {
      final s = organigrammeScene([
        poste('A', code: 'CARH', niveau: 3, x: 400, y: 100, l: 100, h: 40),
        {...poste('B', code: 'ADS', parent: 'A', niveau: 6, x: 300, y: 500, l: 100, h: 40, barre: 450), 'coudeX': 500, 'coudeY': 300},
      ], g);
      expect(s.traits, containsAll([const TraitOrg(400, 120, 400, 300), const TraitOrg(400, 300, 500, 300), const TraitOrg(500, 300, 500, 450), const TraitOrg(500, 450, 300, 450)]));
    });

    test('un rattachement archivé (absent des postes actifs) ne laisse aucun lien', () {
      final s = organigrammeScene([poste('B', code: 'MG', parent: 'ABSENT', niveau: 2, x: 600, y: 160)], g);
      expect(s.traits, isEmpty);
    });

    test('un poste sans coordonnées est PLACÉ : niveau du rattachement + 1, à droite de la dernière case du niveau', () {
      final s = organigrammeScene([
        racine,
        poste('B', code: 'MG', parent: 'A', niveau: 2, x: 600, y: 160, l: 100, h: 40),
        poste('C', code: 'NEUF', parent: 'A'),
      ], g);
      final c = s.cases.firstWhere((c) => c.id == 'C');
      final b = s.cases.firstWhere((c) => c.id == 'B');
      expect(c.niveau, 2);
      expect(c.x, greaterThan(b.x + b.l), reason: 'à droite de la dernière case du niveau');
      expect(c.cy, g.niveauxY[2]);
      expect(s.traits.any((t) => t.x2 == c.cx), isTrue, reason: 'et relié à son rattachement');
    });

    test('le cadre s’agrandit si un poste en sort ; les numéros de niveau suivent les niveaux présents', () {
      final s = organigrammeScene([poste('A', code: 'X', niveau: 2, x: 2000, y: 100, l: 100), poste('B', code: 'Y', niveau: 5, x: 100, y: 100)], g);
      expect(s.largeur, 2000 + 50 + 12);
      expect(s.niveaux.map((n) => n.n), [2, 5]);
      expect(s.niveaux.first.x, g.niveauxX[2]);
      expect(s.niveaux.first.y, g.niveauxY[2]);
    });

    test('sans ordonnée déclarée pour un niveau : moyenne des centres de ses cases', () {
      final s = organigrammeScene([poste('A', code: 'X', niveau: 8, x: 100, y: 100), poste('B', code: 'Y', niveau: 8, x: 300, y: 200)], g);
      expect(s.niveaux.single.y, 150);
    });
  });

  group('ajustement', () {
    test('échelle uniforme limitée par la dimension la plus serrée, graphe centré', () {
      const s = SceneOrganigramme(largeur: 1000, hauteur: 500, police: 17, cases: [], traits: [], niveaux: []);
      final a = ajusterScene(s, 500, 400);
      expect(a.echelle, 0.5);
      expect((a.dx, a.dy), (0.0, 75.0));
    });
  });

  group('légende', () {
    test('générée des fiches : seuls les postes à code, dans l’ordre de la légende puis de la collection', () {
      final l = organigrammeLegende([
        poste('A', code: 'RL', libelle: 'Responsable Laboratoire'),
        poste('B', libelle: 'Responsable Comptable'),
        {...poste('C', code: 'AE', libelle: 'Agent d’Entretien et de Service'), 'codeLegende': 'AES', 'ordreLegende': 1},
        {...poste('D', code: 'DG/ MC', libelle: 'Directeur Général'), 'ordreLegende': 0, 'codeLegende': 'DG/MC'},
      ]);
      expect(l.map((x) => x.code), ['DG/MC', 'AES', 'RL']);
      expect(l[1].libelle, 'Agent d’Entretien et de Service');
    });

    test('pagination : saut de page propre, une ligne n’est jamais coupée', () {
      final lignes = [for (var i = 0; i < 45; i++) LigneLegende('C$i', 'L$i')];
      final pages = paginerLegende(lignes, 19);
      expect(pages.map((p) => p.length), [19, 19, 7]);
      expect(organigrammePages(45, 19), 4);
      expect(organigrammePages(18, 19), 2);
      expect(organigrammePages(0, 19), 1);
      expect(organigrammePages(19, 19), 2);
      expect(organigrammePages(20, 19), 3);
    });
  });

  group('paramètres de la fiche', () {
    test('la graine porte les mentions du document remis', () {
      final f = ParametresFiche.graine;
      expect(f.lignesCartouche(1, 2), ['Référence : FCH_GRH_006', 'Date : 03/05/2023', 'Version 01', 'Page 1 sur 2']);
      expect((f.titreHaut, f.titre), ('FICHE', 'ORGANIGRAMME'));
      expect(f.mention, 'Ce document demeure strictement la propriété de la Clinique BAGUIDI l’AS de Cœur');
    });

    test('aller-retour par la fiche du magasin ; un champ vide ou absent retombe sur la graine', () {
      final f = ParametresFiche.depuisFiche({...ParametresFiche.graine.versFiche(), 'reference': 'FCH_GRH_007', 'version': '', 'date': '2024-01-09'});
      expect(f.reference, 'FCH_GRH_007');
      expect(f.version, '01');
      expect(f.dateImprimee, '09/01/2024');
      expect(ParametresFiche.depuisFiche(null).reference, 'FCH_GRH_006');
      expect(ParametresFiche.depuisFiche(ParametresFiche.graine.versFiche()).grille.niveauxY, ParametresGrille.graine.niveauxY);
    });

    test('la grille se relit telle qu’elle a été écrite (clés de niveau en texte, comme en JSON)', () {
      final relue = ParametresGrille.depuisFiche(const ParametresGrille(largeur: 1800, niveauxY: {1: 10.0, 2: 99.0}, legendeParPage: 12).versFiche());
      expect(relue.largeur, 1800.0);
      expect(relue.niveauxY, {1: 10.0, 2: 99.0});
      expect(relue.legendeParPage, 12);
    });
  });

  test('la saisie d’un poste : champs numériques convertis, champ vidé retiré (le poste sera placé automatiquement)', () {
    final v = cfaFichePoste({'poste': 'X', 'niveau': '3', 'x': '120,5', 'y': '', 'code': '', 'lien': 'direct'});
    expect(v['niveau'], 3);
    expect(v['x'], 120.5);
    expect(v.containsKey('y'), isFalse);
    expect(v.containsKey('code'), isFalse);
    expect(v['lien'], 'direct');
  });
}
