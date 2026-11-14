import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/pont_activite.dart';

import 'aide_grand_stock.dart';

/// L'AUDIT DE LA CONTINUITÉ DES VALIDATIONS (Direction, 15/11/2026) : ce que chaque circuit de validation PEUT faire depuis un autre poste se lit à la CLASSE de la collection que son geste écrit,
/// et cette classe se calcule sur les constantes de la production — jamais recopiée dans un tableau qu'on oublierait de tenir (`docs/architecture/CONTINUITE-VALIDATIONS.md`).
///  * R (configuration) : la mère seule écrit, un fileul reçoit ; un fileul DÉPOSE (`validationsDeposees`) et la mère applique ;
///  * A (activité synchronisée) : le geste s'écrit à N'IMPORTE QUEL poste et voyage par le pont (fusion champ à champ) ;
///  * L (locale au poste) : l'enregistrement n'existe que sur le poste qui l'a créé — le circuit ne traverse pas les postes.
String classe(String c) => collectionsConfiguration().contains(c) ? 'R' : (collectionsActivite.contains(c) ? 'A' : 'L');

void main() {
  test('les quinze familles de référentiels à valider sont TOUTES de classe R : toutes passent par le dépôt (aucune ne reste « réglée sur la mère »)', () {
    for (final f in valFamilles) {
      final cols = f.mode == 'fiche' ? [valCollectionValidations] : f.collections;
      for (final c in cols) {
        expect(classe(c), 'R', reason: '${f.id} écrit $c');
      }
      expect(valVoyageDeLaMere(f), isTrue, reason: f.id);
    }
    expect(valFamilles.length, 15);
    expect(classe(valCollectionDepots), 'A', reason: 'le dépôt voyage du fileul à la mère par le pont d\'activité');
  });

  test('la classe de la collection de chaque autre circuit : ce que le tableau du document affirme', () {
    const attendu = {
      // tarifs, droits, lots d'import : déjà portés par un dépôt appliqué par la mère (lots T6, droits, IMP-C)
      'versionsTarif': 'R', 'propositionsTarif': 'A', 'rbac': 'R', 'decisionsDroits': 'A', 'demandesImport': 'A',
      // configuration fiscale et décisions de l'AIB : écrites par la mère seule, aucun dépôt (reste à décider)
      'identiteLegale': 'R', 'obligationsFiscales': 'R', 'parametresAib': 'R',
      // activité synchronisée : le validateur écrit depuis n'importe quel poste
      'ecritures': 'A', 'presences': 'A', 'avoirs': 'A', 'factures': 'A', 'lecturesOcr': 'A',
      // locale au poste : la validation ne traverse pas les postes tant que la collection ne rejoint pas le pont
      'besoins': 'L', 'commandes': 'L', 'facturesFournisseurs': 'L', 'bulletins': 'L', 'depenses': 'L', 'clotures': 'L', 'planning': 'L',
      'demandesAnalyses': 'L', 'resultatsImagerie': 'L', 'demandesImagerie': 'L', 'pieces': 'L', 'documents': 'L', 'badges': 'L', 'seuilsDelta': 'L', 'cpa': 'L', 'crAnesthesie': 'L',
    };
    for (final e in attendu.entries) {
      expect(classe(e.key), e.value, reason: e.key);
    }
  });

  test('UN CIRCUIT D\'ACTIVITÉ SYNCHRONISÉ, contre la vraie mère : le brouillon d\'un caissier (fileul) est validé par le comptable depuis un AUTRE fileul ; le caissier n\'est jamais bloqué ; la validation revient à la mère et à l\'auteur', () async {
    final c = Clinique(19581, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'caissier', 'CAISSIER');
      final f2 = await c.fileul('F2', 'comptable', 'COMPTABLE');
      Map<String, Object?> ligne(String piece, String compte, num debit, num credit) =>
          {'numero': piece, 'pieceId': piece, 'date': '2026-11-15', 'libelle': 'Encaissement $piece', 'compte': compte, 'debit': debit, 'credit': credit, 'statut': 'brouillon'};
      f1.m.collection('ecritures').inserer(ligne('PC-T1', '571000', 1000, 0), prefixe: 'ECR');
      f1.m.collection('ecritures').inserer(ligne('PC-T1', '706000', 0, 1000), prefixe: 'ECR');
      int piece(Magasin m, String p) => m.collection('ecritures').toutes.where((x) => x['pieceId'] == p).length;
      await c.converger(() => piece(f2.m, 'PC-T1') == 2 && piece(c.mm, 'PC-T1') == 2, 'la pièce du caissier arrive au comptable et à la mère');
      // Le caissier n'est PAS bloqué par un brouillon qui attend : il encaisse la pièce suivante.
      f1.m.collection('ecritures').inserer(ligne('PC-T2', '571000', 500, 0), prefixe: 'ECR');
      f1.m.collection('ecritures').inserer(ligne('PC-T2', '706000', 0, 500), prefixe: 'ECR');
      expect([piece(f1.m, 'PC-T1'), piece(f1.m, 'PC-T2')], [2, 2]);
      // Le comptable valide la première pièce depuis SON poste (un fileul).
      for (final x in f2.m.collection('ecritures').toutes.where((x) => x['pieceId'] == 'PC-T1')) {
        f2.m.collection('ecritures').mettreAJour(x['id'], {'statut': 'validee'});
      }
      bool validee(Magasin m) => m.collection('ecritures').toutes.where((x) => x['pieceId'] == 'PC-T1').every((x) => x['statut'] == 'validee');
      await c.converger(() => validee(c.mm) && validee(f1.m), 'la validation du comptable arrive à la mère et au caissier');
      expect(c.mm.collection('ecritures').toutes.where((x) => x['pieceId'] == 'PC-T2').every((x) => x['statut'] == 'brouillon'), isTrue, reason: 'la seconde pièce attend toujours : rien n\'est validé à sa place');
      expect(f1.pont.motifsRefus, isEmpty);
      expect(f2.pont.motifsRefus, isEmpty);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
