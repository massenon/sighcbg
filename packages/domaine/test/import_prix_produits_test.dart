// Le jeu « Prix d'achat des produits » (`tarifs-produits`) et le référentiel produits (`produits`) : l'import par PROPOSITION, au même moteur que l'écran « Changer le prix d'achat ».
// Oui + geste de décider = version validée ; Oui sans ce geste ou vide = proposition ; Non = consigné, aucune version ; prix identique = inchangée ; erreurs = tout ou rien.
// Les articles sont ceux de l'essai (codes `TST-…`) : aucune donnée d'une autre clinique.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

class Port extends PortImport {
  Port(this.profilFixe, {Map<String, List<F>> init = const {}}) {
    init.forEach((k, v) => _c[k] = [for (final f in v) {...f}]);
  }
  final ProfilImport profilFixe;
  final Map<String, List<F>> _c = {};
  int _n = 0;
  @override
  ProfilImport get profil => profilFixe;
  @override
  List<F> toutes(String c) => _c.putIfAbsent(c, () => []);
  @override
  String get jour => '2026-11-14';
  @override
  String get utilisateur => 'IMPORTATEUR';
  @override
  F inserer(String c, F f) {
    final x = {'statut': 'actif', ...f};
    x['id'] ??= 'X${++_n}';
    toutes(c).insert(0, x);
    return x;
  }

  @override
  void retirer(String c, Object? id) => toutes(c).removeWhere((f) => f['id'] == id);
  @override
  bool archiver(String c, Object? id, String motif) {
    final f = parId(c, id);
    if (f == null) return false;
    f['statut'] = 'archive';
    return true;
  }

  @override
  void restaurer(String c, Object? id) => parId(c, id)?['statut'] = 'actif';
  @override
  void mettreAJour(String c, Object? id, F patch) => parId(c, id)?.addAll(patch);
  @override
  void journaliser(String a, String m, String e, String r, Object? av, Object? ap) {}
}

const entete = ['Code article', 'Prix d’achat', 'Date d’effet', 'Valider (Oui/Non)', 'Motif', 'Source'];
List<Object?> ligne(String code, Object? prix, {String date = '2026-12-01', String valider = '', String motif = 'Nouveau tarif fournisseur'}) => [code, prix, date, valider, motif, ''];

F med(String code, num achat) => {'id': 'P-$code', 'code': code, 'designation': 'Article $code', 'categorie': 'medicament', 'prixAchat': achat, 'prixVente': achat, 'statut': 'actif'};

Port monde(ProfilImport p, {bool versionne = true}) {
  final produits = [med('TST-A', 100), med('TST-B', 250)];
  final m = tarMigrerProduits(produits, origine: 'reprise');
  return Port(p, init: {'produits': produits, if (versionne) 'tarifs': m.tarifs, if (versionne) 'versionsTarif': m.versions});
}

AnalyseImport analyser(Port port, List<List<Object?>> lignes) => analyserLignes(jeuTarifsProduits, [entete, ...lignes], 'p.xlsx', port, options: const OptionsImport());

// Un profil qui peut importer ce jeu (VOIR et ÉDITER son écran) et dont les gestes sont lus de la matrice (aucun nom de rôle dans le jeu).
ProfilImport profil(String role, DroitsGestes g, {bool importe = true}) => ProfilImport(
    role: role,
    droitEcran: (e) => Droit(voir: importe, editer: importe, annuler: false),
    gesteDroit: (id) => g.peut(role, id));

void main() {
  final decideur = profil('da', DroitsGestes(fiches: const []));
  final simple = profil('stock', DroitsGestes(fiches: const []));

  test('le jeu est déclaré : restreint (la mère seule écrit les versions), écran dédié, cibles = les deux collections de prix, droit d\'importer porté par la matrice', () {
    expect(jeuTarifsProduits.restreint, isTrue);
    expect(jeuImportParId('tarifs-produits'), same(jeuTarifsProduits));
    expect(jeuImportParEcran('imp-tarifs-produits')!.id, 'tarifs-produits');
    expect(jeuTarifsProduits.cibles, [tarCollectionTarifs, tarCollectionVersions]);
  });

  test('Oui avec le geste de décider : version 2 VALIDÉE d\'emblée, effective à sa date ; la fiche et le prix en vigueur ne bougent pas avant', () {
    final p = monde(decideur);
    final a = analyser(p, [ligne('TST-A', 120, valider: 'oui')]);
    expect(a.accepte, isTrue, reason: a.problemes.map((x) => '${x.code}:${x.motif}').join(' / '));
    final r = appliquer(jeuTarifsProduits, a, p);
    expect(r.ok, isTrue, reason: '${r.motif}');
    final vs = p.toutes('versionsTarif').where((x) => x['code'] == 'TST-A').toList();
    expect(vs.length, 2, reason: 'une version AJOUTÉE, la version 1 est conservée');
    final v = vs.firstWhere((x) => x['version'] == 2);
    expect([v['statut'], v['origine'], v['prixNonAssure'], v['dateEffet']], ['valide', 'import', 120, '2026-12-01']);
    final h = ReferentielTarifs(p.toutes('tarifs'), p.toutes('versionsTarif'));
    expect(tarPrixProduit(h, med('TST-A', 100), '2026-11-30', aujourdhui: '2026-11-14').achat, 100);
    expect(tarPrixProduit(h, med('TST-A', 100), '2026-12-01', aujourdhui: '2026-11-14').achat, 120);
    expect(p.parId('produits', 'P-TST-A')!['prixAchat'], 100, reason: 'l\'import n\'écrit jamais la fiche');
  });

  test('Oui SANS le geste, ou vide : PROPOSITION (le Oui vaut proposition et le dit) ; rien ne change', () {
    for (final valider in ['oui', '']) {
      final p = monde(simple);
      final a = analyser(p, [ligne('TST-B', 300, valider: valider)]);
      expect(a.accepte, isTrue, reason: a.problemes.map((x) => x.code).join(','));
      if (valider == 'oui') expect(a.problemes.map((x) => x.code), contains('OUI_VAUT_PROPOSITION'));
      expect(appliquer(jeuTarifsProduits, a, p).ok, isTrue);
      final v = p.toutes('versionsTarif').firstWhere((x) => x['code'] == 'TST-B' && x['version'] == 2);
      expect(v['statut'], 'propose');
      final h = ReferentielTarifs(p.toutes('tarifs'), p.toutes('versionsTarif'));
      expect(tarPrixProduit(h, med('TST-B', 250), '2026-12-31', aujourdhui: '2026-11-14').achat, 250, reason: 'une proposition ne change rien');
    }
  });

  test('Non : consigné avec son motif, AUCUNE version ; sans motif, refusé ; prix identique : inchangée, comptée', () {
    final p = monde(decideur);
    final a = analyser(p, [ligne('TST-A', 120, valider: 'non', motif: 'Tarif pas encore signé'), ligne('TST-B', 250)]);
    expect(a.accepte, isTrue, reason: a.problemes.map((x) => x.code).join(','));
    expect(a.problemes.map((x) => x.code), containsAll(['LIGNE_NON_APPLIQUEE', 'PRIX_INCHANGE']));
    expect(a.ignorees, [2, 3]);
    expect(appliquer(jeuTarifsProduits, a, p).ok, isTrue);
    expect(p.toutes('versionsTarif').length, 2, reason: 'aucune version créée');
    expect(analyser(p, [ligne('TST-A', 120, valider: 'non', motif: '')]).problemes.map((x) => x.code), contains('MOTIF_REQUIS'));
  });

  test('refus NOMMÉS, tout ou rien : tiret, zéro, NC, décimal, date passée, article inconnu, sans motif ; doublon dans le fichier', () {
    final p = monde(decideur);
    Set<String> codes(List<Object?> l) => {for (final x in analyser(p, [l]).problemes) x.code};
    expect(codes(ligne('TST-A', '-')), contains('PRIX_ABSENT'));
    expect(codes(ligne('TST-A', 0)), contains('PRIX_ZERO'));
    expect(codes(ligne('TST-A', 'NC')), contains('NC_INTERDIT'));
    expect(codes(ligne('TST-A', 12.5)), isNotEmpty);
    expect(codes(ligne('TST-A', 130, date: '2026-11-01')), contains('DATE_PASSEE'));
    expect(codes(ligne('TST-INCONNU', 130)), contains('ARTICLE_INCONNU'));
    expect(codes(ligne('TST-A', 130, motif: '')), contains('MOTIF_REQUIS'));
    final a = analyser(p, [ligne('TST-A', 130), ligne('TST-B', 0)]);
    expect(a.accepte, isFalse, reason: 'une erreur refuse le fichier entier');
    expect(p.toutes('versionsTarif').length, 2, reason: 'rien n\'est écrit par une analyse');
    final d = analyser(p, [ligne('TST-A', 130), ligne('TST-A', 140)]);
    expect(d.accepte, isFalse, reason: 'un code deux fois dans le fichier est refusé');
  });

  test('RG-02 : les médicaments n\'ont pas de colonne prix de vente (il se dérive) ; la proposition d\'un article NON médicament garde son prix de vente propre', () {
    expect(jeuTarifsProduits.colonnes.map((c) => c.cle), isNot(contains('prixVente')));
    final autre = {'id': 'P-TST-C', 'code': 'TST-C', 'designation': 'Article C', 'categorie': 'fourniture', 'prixAchat': 50, 'prixVente': 80, 'statut': 'actif'};
    final m = tarMigrerProduits([autre], origine: 'reprise');
    final p = Port(decideur, init: {'produits': [autre], 'tarifs': m.tarifs, 'versionsTarif': m.versions});
    expect(appliquer(jeuTarifsProduits, analyser(p, [ligne('TST-C', 60, valider: 'oui')]), p).ok, isTrue);
    expect(p.toutes('versionsTarif').firstWhere((x) => x['version'] == 2)['prixVente'], 80);
  });

  test('un article sans version 1 reçoit sa reprise AVANT la proposition (réparation de donnée, jamais une date inventée)', () {
    final p = monde(decideur, versionne: false);
    final a = analyser(p, [ligne('TST-A', 120, valider: 'oui')]);
    expect(a.accepte, isTrue, reason: a.problemes.map((x) => '${x.code}:${x.motif}').join(' / '));
    expect(p.toutes('tarifs'), isEmpty, reason: 'l\'analyse n\'écrit rien');
    expect(appliquer(jeuTarifsProduits, a, p).ok, isTrue);
    final vs = p.toutes('versionsTarif').where((x) => x['code'] == 'TST-A').toList()..sort((x, y) => (x['version'] as num).compareTo(y['version'] as num));
    expect([for (final v in vs) v['version']], [1, 2]);
    expect(vs.first['origine'], 'reprise');
    expect(vs.first.containsKey('dateEffet'), isFalse);
  });

  test('sans le droit d\'importer ce jeu, le moteur REFUSE en nommant ; un lot dont une version est validée ne s\'annule plus', () {
    final p = monde(profil('x', DroitsGestes(fiches: const []), importe: false));
    final a = analyser(p, [ligne('TST-A', 120)]);
    expect(a.accepte, isFalse);
    final q = monde(decideur);
    final b = analyser(q, [ligne('TST-A', 120, valider: 'oui')]);
    expect(appliquer(jeuTarifsProduits, b, q).ok, isTrue);
    final lot = q.toutes(collectionLots).first;
    final dep = jeuTarifsProduits.dependances(lot, q);
    expect(dep?.code, 'VERSION_DEJA_VALIDEE');
  });

  group('le référentiel produits (jeu `produits`) : prix d\'achat obligatoire et RG-02 sans marge', () {
    const ent = ['Code article', 'Désignation', 'Catégorie', 'Unité', 'Prix d’achat unitaire', 'Prix de vente unitaire', 'Seuil d’alerte', 'Emplacement', 'Code fournisseur'];
    Set<String> codes(List<Object?> l) {
      final p = Port(ProfilImport.accordeTout());
      return {for (final x in analyserLignes(jeuProduits, [ent, l], 'r.xlsx', p, options: const OptionsImport()).problemes) x.code};
    }

    test('un prix d\'achat absent, tiret ou nul REFUSE la ligne en nommant (PRIX_ACHAT_ABSENT) ; le Grand Stock garde « à valoriser »', () {
      for (final prix in [null, '', 0]) {
        expect(codes(['TST-N', 'Article N', 'Médicaments', 'Boîte', prix, null, null, null, null]), contains('PRIX_ACHAT_ABSENT'), reason: 'prix : $prix');
      }
      // Un tiret dans une colonne d'entiers est refusé par le moteur de lecture lui-même (type de cellule), avant la règle : le fichier est refusé de toute façon.
      expect(codes(['TST-N', 'Article N', 'Médicaments', 'Boîte', '-', null, null, null, null]), isNotEmpty);
      expect(codes(['TST-N', 'Article N', 'Médicaments', 'Boîte', 100, null, null, null, null]), isNot(contains('PRIX_ACHAT_ABSENT')));
      expect(jeuGrandStock.colonnes.firstWhere((c) => c.cle == 'prixRevient').obligatoire, isFalse);
    });

    test('RG-02 : un médicament à prix de vente différent est refusé, au-dessus comme au-dessous ; égal ou vide passe ; hors médicament libre', () {
      expect(codes(['TST-N', 'Article N', 'Médicaments', 'Boîte', 100, 150, null, null, null]), contains('RG02_MARGE'));
      expect(codes(['TST-N', 'Article N', 'Médicaments', 'Boîte', 100, 80, null, null, null]), contains('RG02_MARGE'));
      expect(codes(['TST-N', 'Article N', 'Médicaments', 'Boîte', 100, 100, null, null, null]), isNot(contains('RG02_MARGE')));
      expect(codes(['TST-N', 'Article N', 'Fournitures', 'Boîte', 100, 150, null, null, null]), isNot(contains('RG02_MARGE')));
    });
  });
}
