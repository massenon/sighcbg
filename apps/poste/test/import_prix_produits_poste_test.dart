import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/sync/service_demandes_import.dart';

/// L'IMPORT DU PRIX D'ACHAT DES PRODUITS AU POSTE : le jeu `tarifs-produits` écrit par PROPOSITION dans le vrai magasin (gardes comprises), le droit d'importer est lu de la MATRICE EN FORCE
/// (le gestionnaire de stock y a droit : décision de la Direction), le geste de décider aussi ; un fileul ne dépose pas un fichier de prix. Le référentiel produits importé reçoit sa version 1 par la mère.
final auj = DateTime(2026, 11, 14, 10);
final donnees = DonneesNavigation.depuisDossier();
const entete = ['Code article', 'Prix d’achat', 'Date d’effet', 'Valider (Oui/Non)', 'Motif', 'Source'];

Magasin jeu() {
  final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
  TarifsPoste.assurerProduits(m);
  return m;
}

PortMagasin port(Magasin m, String role) => PortMagasin(m,
    aujourdhui: () => auj,
    nomAgent: 'Importateur',
    profil: ProfilImport(
        role: role,
        droitEcran: (e) => donnees.matrice.droit(role, e),
        gesteDroit: (g) => DroitsGestes(fiches: m.collection('rbac').actives).peut(role, g)));

List<Object?> ligne(String code, num prix, {String valider = '', String date = '2027-01-15', String motif = 'Nouveau tarif fournisseur'}) => [code, prix, date, valider, motif, ''];

void main() {
  Map<String, Object?> article(Magasin m, String cat) => m.collection('produits').actives.firstWhere((p) => p['categorie'] == cat);

  test('le droit d\'importer le jeu est celui de la matrice : le gestionnaire de stock, la DAF et l\'administrateur l\'ont ; le caissier non (le moteur refuse en nommant)', () {
    for (final r in ['stock', 'da', 'admin']) {
      expect(ProfilImport(role: r, droitEcran: (e) => donnees.matrice.droit(r, e)).peutImporterEcran('imp-tarifs-produits'), isTrue, reason: r);
    }
    final m = jeu();
    final p = article(m, 'medicament');
    final a = analyserLignes(jeuTarifsProduits, [entete, ligne('${p['code']}', (p['prixAchat'] as num) + 5)], 'prix.xlsx', port(m, 'caissier'));
    expect(a.accepte, isFalse);
    expect(TarifsPoste.lire(m).versionsDe('${p['code']}').length, 1);
  });

  test('le gestionnaire de stock importe : PROPOSITION (le Oui vaut proposition) ; la DAF décide : version validée, la fiche suit au jour d\'effet', () {
    final m = jeu();
    final p = article(m, 'medicament');
    final achat = p['prixAchat'] as num;
    final a = analyserLignes(jeuTarifsProduits, [entete, ligne('${p['code']}', achat + 5, valider: 'oui')], 'prix.xlsx', port(m, 'stock'));
    expect(a.accepte, isTrue, reason: a.problemes.map((x) => '${x.code}:${x.motif}').join(' | '));
    expect(a.problemes.map((x) => x.code), contains('OUI_VAUT_PROPOSITION'));
    expect(appliquer(jeuTarifsProduits, a, port(m, 'stock')).ok, isTrue);
    final v = TarifsPoste.lire(m).versionsDe('${p['code']}').last;
    expect([v['statut'], v['origine'], v['version'], v['prixNonAssure']], ['propose', 'import', 2, achat + 5]);
    expect(m.collection('produits').parId(p['id'])!['prixAchat'], achat, reason: 'l\'import n\'écrit jamais la fiche');
    // La DAF décide Oui à l'écran des prix : la version est validée.
    final da = TarifsPoste(m, role: 'da', auteur: () => 'DAF', horloge: () => DateTime(2027, 1, 15, 8));
    expect(da.decider('${v['id']}', 'oui').ok, isTrue);
    expect(m.collection('produits').parId(p['id'])!['prixAchat'], achat + 5, reason: 'à sa date d\'effet la fiche suit la version');
    expect(m.collection('produits').parId(p['id'])!['prixVente'], achat + 5, reason: 'RG-02');
  });

  test('un fileul rattaché ne dépose pas un fichier de prix d\'achat : réservé à la mère', () {
    final svc = ServiceDemandesImport.de(jeu())..fileulRattache = () => true;
    expect(svc.reserveALaMere(jeuTarifsProduits), isTrue);
    expect(svc.passeParUneDemande(jeuTarifsProduits), isFalse);
  });

  test('le référentiel produits importé : un prix d\'achat absent est refusé en nommant ; un article valide reçoit sa version 1 de la mère, sans date inventée', () {
    final m = Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');
    TarifsPoste.assurerProduits(m);
    const ent = ['Code article', 'Désignation', 'Catégorie', 'Unité', 'Prix d’achat unitaire', 'Prix de vente unitaire', 'Seuil d’alerte', 'Emplacement', 'Code fournisseur'];
    final p = port(m, 'stock');
    final sans = analyserLignes(jeuProduits, [ent, ['TST-SANS', 'Sans prix', 'Médicaments', 'Boîte', null, null, null, null, null]], 'a.xlsx', p);
    expect(sans.accepte, isFalse);
    expect(sans.problemes.map((x) => x.code), contains('PRIX_ACHAT_ABSENT'));
    final ok = analyserLignes(jeuProduits, [ent, ['TST-OK', 'Article valide', 'Médicaments', 'Boîte', 310, null, null, null, null]], 'b.xlsx', p);
    expect(ok.accepte, isTrue, reason: ok.problemes.map((x) => x.code).join(','));
    expect(appliquer(jeuProduits, ok, p).ok, isTrue);
    expect(TarifsPoste.lire(m).parCode['TST-OK'], isNull, reason: 'la fiche est écrite par l\'import ; la version 1 est posée par la mère aussitôt après (reprise)');
    expect(TarifsPoste.assurerProduits(m), 1);
    final v = TarifsPoste.lire(m).versionsDe('TST-OK').single;
    expect([v['version'], v['prixNonAssure'], v['origine'], v['statut'], v.containsKey('dateEffet')], [1, 310, 'reprise', 'valide', false]);
  });
}
