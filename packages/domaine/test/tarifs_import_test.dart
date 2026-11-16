// Le jeu « Tarifs et prix » (lot TAR, PRD-TARIFS T4) : l'import par PROPOSITION, jamais par réécriture, au même moteur que l'écran. Oui + geste de décider (matrice) = version validée ;
// Oui sans ce geste ou vide = proposition ; Non = consigné avec son motif, aucune version ; prix identique = inchangée ; erreurs = tout ou rien.
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

const entete = ['Code', 'Désignation', 'Famille', 'Secteur', 'Prix non assuré', 'Prix assuré', 'Prix unique', 'Couverture', 'Date d’effet', 'Valider (Oui/Non)', 'Motif', 'Source'];

List<Object?> ligne(String code, Object? na, Object? pa, {String date = '2026-12-01', String valider = '', String motif = 'Nouvelle grille', String designation = '', String famille = '', String unique = 'non'}) =>
    [code, designation, famille, '', na, pa, unique, '', date, valider, motif, ''];

Port monde(ProfilImport p) => Port(p, init: {
      'tarifs': [
        {'id': 'MG01', 'code': 'MG01', 'codeActe': 'MG01', 'libelle': 'Consultation', 'famille': 'CONSULTATION', 'statut': 'actif', 'assurable': true},
        {'id': 'MG02', 'code': 'MG02', 'codeActe': 'MG02', 'libelle': 'Suivi', 'famille': 'CONSULTATION', 'statut': 'actif'},
      ],
      'versionsTarif': [
        {'id': 'MG01@origine@1', 'code': 'MG01', 'version': 1, 'prixNonAssure': 5000, 'prixAssure': 3000, 'etatAssure': 'montant', 'origine': 'migration', 'statut': 'valide', 'provisoire': true},
        {'id': 'MG02@origine@1', 'code': 'MG02', 'version': 1, 'prixNonAssure': 8000, 'prixAssure': 8000, 'etatAssure': 'unique', 'origine': 'migration', 'statut': 'valide'},
      ],
    });

AnalyseImport analyser(Port port, List<List<Object?>> lignes) => analyserLignes(jeuTarifs, [entete, ...lignes], 't.xlsx', port, options: const OptionsImport());

// Un profil dont les gestes sont lus de la MATRICE (fiches `rbac`) : aucun nom de rôle dans le jeu.
ProfilImport profilAvecGestes(String role, DroitsGestes g) => ProfilImport(role: role, droitEcran: (e) => const Droit(voir: true, editer: true, annuler: false), gesteDroit: (id) => g.peut(role, id));

void main() {
  final decideur = profilAvecGestes('da', DroitsGestes(fiches: const []));
  final simple = profilAvecGestes('stock', DroitsGestes(fiches: const []));

  test('le jeu est restreint (la mère seule écrit le référentiel) et remplace l\'ancien catalogue des actes ; l\'ancien identifiant renvoie au nouveau', () {
    expect(jeuTarifs.restreint, isTrue);
    expect(jeuImportParId('actes')!.id, 'tarifs');
    expect(jeuxImport.where((j) => j.cibles.contains('actes')), isEmpty, reason: 'plus aucun jeu n\'écrit une liste de prix de lecture');
  });

  test('Oui avec le geste de décider : version VALIDÉE d\'emblée, effective à sa date ; le prix en vigueur ne bouge pas avant', () {
    final p = monde(decideur);
    final a = analyser(p, [ligne('MG01', 5500, 3300, valider: 'oui')]);
    expect(a.accepte, isTrue, reason: a.problemes.map((x) => '${x.code}:${x.motif}').join(' / '));
    final r = appliquer(jeuTarifs, a, p);
    expect(r.ok, isTrue, reason: '${r.motif}');
    final v = p.toutes('versionsTarif').firstWhere((x) => x['code'] == 'MG01' && x['version'] == 2);
    expect(v['statut'], 'valide');
    expect(v['decidePar'], isNotNull);
    final h = ReferentielTarifs(p.toutes('tarifs'), p.toutes('versionsTarif'));
    expect(h.aLaDate('MG01', '2026-11-30', false, aujourdhui: '2026-11-14').montant, 5000);
    expect(h.aLaDate('MG01', '2026-12-01', false, aujourdhui: '2026-11-14').montant, 5500);
    expect(p.toutes('versionsTarif').firstWhere((x) => x['id'] == 'MG01@origine@1')['provisoire'], isNot(true), reason: 'une version validée arrête le marquage d\'attente');
  });

  test('Oui SANS le geste, ou vide : PROPOSITION (le Oui vaut proposition et le dit) ; rien ne change', () {
    for (final valider in ['oui', '']) {
      final p = monde(simple);
      final a = analyser(p, [ligne('MG02', 8500, 8500, unique: 'oui', valider: valider)]);
      expect(a.accepte, isTrue, reason: a.problemes.map((x) => x.code).join(','));
      if (valider == 'oui') expect(a.problemes.map((x) => x.code), contains('OUI_VAUT_PROPOSITION'));
      expect(appliquer(jeuTarifs, a, p).ok, isTrue);
      final v = p.toutes('versionsTarif').firstWhere((x) => x['code'] == 'MG02' && x['version'] == 2);
      expect(v['statut'], 'propose');
      final h = ReferentielTarifs(p.toutes('tarifs'), p.toutes('versionsTarif'));
      expect(h.aLaDate('MG02', '2026-12-31', false, aujourdhui: '2026-11-14').montant, 8000, reason: 'une proposition ne change rien');
    }
  });

  test('Non : consigné avec son motif, AUCUNE version, ni erreur ni refus ; sans motif, refusé', () {
    final p = monde(decideur);
    final a = analyser(p, [ligne('MG01', 5500, 3300, valider: 'non', motif: 'Grille pas encore signée')]);
    expect(a.accepte, isTrue);
    expect(a.problemes.map((x) => x.code), contains('LIGNE_NON_APPLIQUEE'));
    expect(a.ignorees, [2]);
    expect(appliquer(jeuTarifs, a, p).ok, isTrue);
    expect(p.toutes('versionsTarif').where((x) => x['code'] == 'MG01').length, 1, reason: 'aucune version créée par un Non');
    final b = analyser(p, [ligne('MG01', 5500, 3300, valider: 'non', motif: '')]);
    expect(b.accepte, isFalse);
    expect(b.problemes.map((x) => x.code), contains('MOTIF_REQUIS'));
  });

  test('ligne inchangée : comptée, jamais une version', () {
    final p = monde(decideur);
    final a = analyser(p, [ligne('MG01', 5000, 3000)]);
    expect(a.accepte, isTrue);
    expect(a.problemes.map((x) => x.code), contains('PRIX_INCHANGE'));
    expect(appliquer(jeuTarifs, a, p).ok, isTrue);
    expect(p.toutes('versionsTarif').length, 2);
  });

  test('un tiret n\'est pas un zéro : prix non assuré absent refusé ; zéro refusé ; NC interdit en colonne non assurée ; date passée refusée ; sans motif refusé', () {
    final p = monde(decideur);
    final codes = <String>[
      for (final l in [
        ligne('MG01', '-', 3000),
        ligne('MG01', 0, 3000),
        ligne('MG01', 'NC', 3000),
        ligne('MG01', 5500, 3300, date: '2026-11-01'),
        ligne('MG01', 5500, 3300, motif: ''),
        ligne('NEXISTEPAS', 5500, 3300),
      ])
        ...analyser(p, [l]).problemes.where((x) => x.estRefus).map((x) => x.code)
    ];
    expect(codes, ['PRIX_ABSENT', 'PRIX_ZERO', 'NC_INTERDIT', 'DATE_PASSEE', 'MOTIF_REQUIS', 'IDENTITE_INCOMPLETE']);
  });

  test('un refus d\'une ligne refuse le fichier entier (tout ou rien) : rien n\'est écrit', () {
    final p = monde(decideur);
    final a = analyser(p, [ligne('MG01', 5500, 3300), ligne('MG02', 0, 0)]);
    expect(a.accepte, isFalse);
    final r = appliquer(jeuTarifs, a, p);
    expect(r.ok, isFalse);
    expect(p.toutes('versionsTarif').length, 2);
  });

  test('création d\'une prestation : identité et version 1 écrites, née sans prix en vigueur avant sa date d\'effet', () {
    final p = monde(decideur);
    final a = analyser(p, [ligne('NV01', 12000, 9000, designation: 'Acte nouveau', famille: 'ACTE', valider: 'oui', motif: 'Création')]);
    expect(a.accepte, isTrue, reason: a.problemes.map((x) => '${x.code}:${x.motif}').join(' / '));
    expect(appliquer(jeuTarifs, a, p).ok, isTrue);
    expect(p.toutes('tarifs').any((x) => x['code'] == 'NV01'), isTrue);
    final h = ReferentielTarifs(p.toutes('tarifs'), p.toutes('versionsTarif'));
    expect(h.aLaDate('NV01', '2026-11-20', false, aujourdhui: '2026-11-14').montant, isNull, reason: 'avant la date d\'effet : aucun prix en vigueur, jamais un zéro');
    expect(h.aLaDate('NV01', '2026-12-01', false, aujourdhui: '2026-11-14').montant, 12000);
  });

  test('une pièce qui porte déjà la prestation à cette date refuse la ligne (le prix d\'une ligne payée ou impayée n\'est jamais changé après coup)', () {
    final p = monde(decideur);
    p.toutes('factures').add({
      'id': 'F1',
      'numero': 'FC-1',
      'date': '2026-12-02T09:00:00',
      'statut': 'actif',
      'lignes': [
        {'acteCode': 'MG01', 'prixUnitaire': 5000, 'quantite': 1}
      ]
    });
    final a = analyser(p, [ligne('MG01', 5500, 3300)]);
    expect(a.problemes.where((x) => x.estRefus).map((x) => x.code), ['TARIF_DEJA_UTILISE']);
  });
}
