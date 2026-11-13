import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/import/port_magasin.dart';

import 'aide_grand_stock.dart';

/// LA MESURE DU DOUBLE COMPTAGE DU GRAND STOCK (étape 1, décision de la Direction du 13/11/2026 : le gestionnaire de stock est un FILEUL, le Grand Stock s'écrit chez lui).
/// Un fileul écrit le Grand Stock chez lui par la voie de l'IMP-C (`importerDirectEtDemander`, exclusion de l'activité LEVÉE), la VRAIE mère Dart rejoue la demande, et l'on compte,
/// chez le fileul ET chez la mère, les fiches et les quantités de chaque article après plusieurs tours de synchronisation.
void main() {
  test('MESURE : écrit chez le fileul (identifiants propres au poste) puis rejoué par la mère, le Grand Stock se compte DEUX fois', () async {
    final c = Clinique(9431, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      await c.tour(regimeLeve);
      final port = PortMagasin(f1.m, aujourdhui: () => jourTest, nomAgent: f1.par, profil: profilDe('stock'), gardesLevees: true, etiquette: 'F1');
      final r = importerDirectEtDemander(
          jeu: jeuImportParId('grand-stock')!, analyse: f1.analyser('gs-valide'), port: port, regime: regimeLeve(), idDemande: identifiantDemandeImport('F1', jourTest, 1), poste: 'F1');
      expect(r.ok, isTrue, reason: '${r.refus?.motif}');
      final id = '${r.demande!['id']}';
      f1.m.collection(demandesImportCollection).inserer(r.demande!);
      expect(f1.comptesDe('MED1'), {'fichesProduit': 1, 'stockGros': stockMed1, 'fichesLot': 2, 'sommeLots': 150, 'mouvementsEntree': 2, 'sommeEntrees': 150}, reason: 'écrit chez le fileul : exact');
      await c.converger(regimeLeve, () => f1.demande(id)?['etat'] == demandeImportAppliquee, 'la mère rejoue la demande');
      // Le fileul a réglé l'écriture provisoire (archivée) : les fiches ACTIVES sont comptées.
      final fileul = f1.comptesDe('MED1'), mere = c.comptesMere('MED1');
      // ignore: avoid_print
      print('MESURE fileul : $fileul\nMESURE mère   : $mere');
      // CE QUI EST MESURÉ, À L'ARBRE D'AVANT : l'article existe en DEUX fiches actives chez le fileul comme chez la mère (le catalogue publié par la configuration sous son identifiant,
      // le pont d'activité le publiant sous son identité de synchronisation `M-PRD…` : défaut STRUCTUREL, constant), et le compteur de stock vaut 150 OU 300 selon l'ordre d'arrivée
      // de la configuration (valeur de la mère) et des variations (les 150 du fileul) : intermittent, d'où l'intérêt de le CORRIGER plutôt que de le surveiller. Les lots et les mouvements,
      // eux, ne sont comptés qu'une fois (l'écriture provisoire du fileul est archivée à la confirmation) : la règle IMP-C protège leurs fiches, pas leurs compteurs ni le catalogue.
      for (final (nom, e) in [('fileul', fileul), ('mère', mere)]) {
        expect(e['fichesProduit'], 2, reason: '$nom : le produit existe sous deux identités de synchronisation');
        expect(e['stockGros'], anyOf(150, 300), reason: '$nom : le compteur vaut 150 ou 300 selon la course (jamais fiable)');
      }
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('AUJOURD\'HUI le Grand Stock est REFUSÉ à un fileul (exclusion de l\'activité) : le risque n\'existe que dès qu\'on la lève', () async {
    final c = Clinique(9432, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      await c.tour(regimeLeve);
      final r = f1.service.importerEtDemander(jeuImportParId('grand-stock')!, f1.analyser('gs-valide'), profil: profilDe('stock'), nomAgent: f1.par);
      expect(r.resultat.ok, isFalse);
      expect(r.resultat.code, 'JEU_NON_DEMANDABLE');
      expect(f1.comptesDe('MED1')['fichesProduit'], 0, reason: 'rien n\'est écrit');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}
