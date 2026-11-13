// LE DROIT D'IMPORT, tiré de la MATRICE EN FORCE (lot IMP-C, Direction du 11/11/2026 : « pas de masquage d'interface en dur ») : importer un jeu = voir ET éditer l'écran du jeu,
// arbitrer les lots = annuler sur `imp-accueil`. Le moteur REFUSE selon le profil (un bouton absent ne protège rien), le refus se nomme et ne se consigne pas, et un droit décidé
// depuis « Rôles et permissions » (fiche `rbac` superposée à chaud) vaut aussitôt, sans second système.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'import_test.dart' show MagasinMemoire;

typedef Fiche = Map<String, Object?>;

List<Fiche> _lire(String chemin) => [for (final f in jsonDecode(File(chemin).readAsStringSync()) as List) (f as Map).cast<String, Object?>()];

ProfilImport profilDe(MatriceDroits m, String role) => ProfilImport(role: role, libelleRole: m.libelle(role) ?? role, droitEcran: (e) => m.droit(role, e));

void main() {
  final brut = (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>();
  final base = MatriceDroits.depuisJson(brut);
  final manifeste = Manifeste.depuisJson((jsonDecode(File('../referentiels/data/manifeste.json').readAsStringSync()) as Map).cast<String, Object?>());
  final fiches = _lire('../../apps/poste/assets/donnees/jeu/rbac.json');
  final modules = _lire('../../apps/poste/assets/donnees/jeu/modulesActifs.json');
  MatriceDroits chaud(List<Fiche> rbac) => superposerDroits(base, manifeste, rbac: rbac, modulesActifs: modules);

  // Le fichier est celui du modèle du jeu : l'en-tête puis la ligne d'exemple (la ligne d'exemple elle-même n'est jamais importée : on en change le code et la raison sociale).
  final fichier = [
    [for (final c in jeuFournisseurs.colonnes) c.label],
    [...ligneExemple(jeuFournisseurs)]..[0] = 'NOUVEAU'..[1] = 'NOUVEAU FOURNISSEUR',
  ];

  test('la règle : importer = voir ET éditer l\'écran du jeu ; annuler les lots = annuler sur imp-accueil', () {
    final p = ProfilImport(role: 'x', droitEcran: (e) => e == 'imp-fournisseurs' ? const Droit(voir: true, editer: false, annuler: true) : Droit.aucun);
    expect(p.peutImporterEcran('imp-fournisseurs'), isFalse, reason: 'voir sans éditer : lecture seule');
    expect(ProfilImport(role: 'x', droitEcran: (e) => const Droit(voir: true, editer: true, annuler: false)).peutImporterEcran('imp-actes'), isTrue);
    expect(ProfilImport(role: 'x', droitEcran: (e) => e == ecranLotsImport ? const Droit(voir: true, editer: false, annuler: true) : Droit.aucun).arbitreLesLots, isTrue);
    expect(const ProfilImport.aucunDroit().peutImporterEcran('imp-actes'), isFalse);
  });

  test('la matrice engendrée : le comptable importe les fournisseurs, le médecin ne le peut pas, aucun nom de rôle n\'est lu par le moteur', () {
    expect(profilDe(base, 'comptable').peutImporterEcran(jeuFournisseurs.ecran), isTrue);
    expect(profilDe(base, 'medecin').peutImporterEcran(jeuFournisseurs.ecran), isFalse);
    expect(profilDe(base, 'caissier').peutImporterEcran(jeuProduits.ecran), isFalse);
  });

  test('le moteur REFUSE sans le droit : refus nommé, rien écrit, rien consigné (analyse, application)', () {
    final port = MagasinMemoire({}, profilFixe: profilDe(base, 'medecin'));
    final a = analyserFichier(jeuFournisseurs, fichier, 'f.xlsx', port);
    expect(a.accepte, isFalse);
    expect(a.refusDroit, isTrue);
    expect(a.globaux.single.code, 'DROIT_IMPORT_REFUSE');
    expect(a.globaux.single.motif, contains('Médecin'), reason: 'le refus nomme le profil par son libellé');
    expect(consigner(jeuFournisseurs, a, port), isNull, reason: 'un refus de droit n\'entre pas à l\'historique');
    expect(port.toutes(collectionLots), isEmpty);
    // Une analyse acceptée sous un autre profil, puis appliquée sous celui-ci : refusée au moment d'écrire (le profil est relu).
    final bonne = analyserFichier(jeuFournisseurs, fichier, 'f.xlsx', MagasinMemoire({}));
    expect(bonne.accepte, isTrue);
    final r = appliquer(jeuFournisseurs, bonne, port);
    expect(r.ok, isFalse);
    expect(r.code, 'DROIT_IMPORT_REFUSE');
    expect(port.toutes('fournisseurs'), isEmpty);
  });

  test('le moteur accepte avec le droit', () {
    final port = MagasinMemoire({}, profilFixe: profilDe(base, 'comptable'));
    final a = analyserFichier(jeuFournisseurs, fichier, 'f.xlsx', port);
    expect(a.accepte, isTrue);
    expect(appliquer(jeuFournisseurs, a, port).ok, isTrue);
    expect(port.actives('fournisseurs'), hasLength(1));
  });

  test('annuler un lot : le droit d\'annuler sur imp-accueil, relu par le moteur', () {
    final arbitre = MagasinMemoire({}, profilFixe: profilDe(base, 'admin'));
    final a = analyserFichier(jeuFournisseurs, fichier, 'f.xlsx', arbitre);
    final lot = appliquer(jeuFournisseurs, a, arbitre).lot!;
    // Le comptable a le droit d'importer, pas celui d'arbitrer : il ne peut pas annuler le lot d'un autre.
    final comptable = MagasinMemoire({'lotsImportation': arbitre.toutes(collectionLots), 'fournisseurs': arbitre.toutes('fournisseurs')}, profilFixe: profilDe(base, 'comptable'));
    final refus = annulerLot(jeuImportParId, lot['id'], 'test', comptable);
    expect(refus.ok, isFalse);
    expect(refus.code, 'DROIT_IMPORT_REFUSE');
    expect(annulerLot(jeuImportParId, lot['id'], 'test', arbitre).ok, isTrue);
  });

  test('À CHAUD : une décision de droits accorde (ou retire) l\'import sans toucher au code ni à un nom de rôle', () {
    List<Fiche> avec(String role, Map<String, Object?> ecrans) => [
          for (final f in fiches)
            f['role'] == role ? {...f, 'droitsEcrans': {...((f['droitsEcrans'] as Map?)?.cast<String, Object?>() ?? const {}), ...ecrans}} : f
        ];
    final avant = chaud(fiches);
    expect(profilDe(avant, 'medecin').peutImporterEcran('imp-fournisseurs'), isFalse);
    final accorde = chaud(avec('medecin', {
      'imp-fournisseurs': {'voir': true, 'editer': true, 'annuler': false}
    }));
    expect(profilDe(accorde, 'medecin').peutImporterEcran('imp-fournisseurs'), isTrue, reason: 'accordé par une surcharge d\'écran');
    final port = MagasinMemoire({}, profilFixe: profilDe(accorde, 'medecin'));
    expect(analyserFichier(jeuFournisseurs, fichier, 'f.xlsx', port).accepte, isTrue);
    final retire = chaud(avec('comptable', {
      'imp-fournisseurs': {'voir': true, 'editer': false, 'annuler': false}
    }));
    expect(profilDe(retire, 'comptable').peutImporterEcran('imp-fournisseurs'), isFalse, reason: 'retiré : lecture seule');
    expect(analyserFichier(jeuFournisseurs, fichier, 'f.xlsx', MagasinMemoire({}, profilFixe: profilDe(retire, 'comptable'))).refusDroit, isTrue);
  });

  test('la sensibilité est portée par le jeu : les sept jeux restreints, jamais déduits d\'un nom', () {
    expect({for (final j in jeuxImport) if (j.restreint) j.id}, {'personnel', 'patients', 'soldes-ouverture', 'stock-detail', 'transferts', 'inventaire', 'courriers'});
  });
}
