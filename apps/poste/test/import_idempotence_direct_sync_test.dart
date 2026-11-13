import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/pont_activite.dart';

import 'aide_grand_stock.dart';

/// L'IDEMPOTENCE DE L'IMPORT PAR LE CONTENU CHEZ LES FILEULS (lot IDEM, portage du lot de la clinique sœur ; décisions de la Direction de Baguidi du 13/11/2026), contre la VRAIE mère Dart
/// et de VRAIS moteurs de fileul. Le même inventaire (même contenu normalisé) est reconnu comme le MÊME lot, quel que soit le fileul et le moment :
///  1. deux fileuls, même fichier : la mère confirme UNE fois, le second est « déjà confirmé, adopté » (jamais refusé, jamais restitué), mêmes identifiants, aucun double comptage ;
///  2. une sortie faite chez CHACUN des deux fileuls sur le lot en attente est comptée une fois, la mère étant coupée puis relancée ;
///  3. chaque étape rejouée (verdict, levée du marquage, demande à la mère, redémarrage du pont) est un NO-OP, journal compris ;
///  4. le même fichier importé plus tard : rien à écrire, nommé ; réimporté après annulation avant la réponse de la mère : permis, sous une série neuve, et l'autre fileul est rebasé ;
///  5. un fichier dont UNE cellule change est un AUTRE lot ; le premier lot REFUSÉ par la mère : le refus s'applique au second dépôt, sans écriture de la mère ni doublon ;
///  6. une restitution PARTIELLE rejouée reste PARTIELLE, sans seconde contre-passation.
const total = {'fichesProduit': 1, 'stockGros': stockMed1, 'fichesLot': 2, 'sommeLots': 150, 'mouvementsEntree': 2, 'sommeEntrees': 150};

Future<void> attendreTours(Clinique c, int n) async {
  for (var i = 0; i < n; i++) {
    await c.tour();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

int journalImport(Clinique c, [String debut = 'Import']) => [for (final l in c.mm.collection('audit').toutes) if ('${l['action']}'.startsWith(debut)) l].length;
List<Fiche> lotsApplique(Clinique c) => [for (final l in c.mm.collection(collectionLots).toutes) if (l['etat'] == 'applique') l];
int fiches(Magasin m) => ['lots', 'mouvements', 'produits'].fold(0, (t, k) => t + m.collection(k).toutes.length);
String serieDe(Poste p, String id) => '${p.demande(id)!['serieIdentifiants']}';

void main() {
  test('CAS 1, DEUX FILEULS, MÊME INVENTAIRE : la mère confirme UNE fois, le second est ADOPTÉ (ni refus ni restitution), mêmes identifiants, 150 unités partout, jamais 300', () async {
    final c = Clinique(9431, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      final r1 = f1.importer('gs-valide'), r2 = f2.importer('gs-valide');
      expect(r1.resultat.ok && r2.resultat.ok, isTrue, reason: 'chacun écrit chez lui : ${r1.resultat.motif} ${r2.resultat.motif}');
      final id1 = '${r1.demande}', id2 = '${r2.demande}';
      final serie = serieDe(f1, id1);
      expect(serieDe(f2, id2), serie, reason: 'même fichier, même série : les deux fileuls écrivent sous les MÊMES identifiants de fiche');
      expect({for (final p in f1.produits('MED1')) p['id']}, {for (final p in f2.produits('MED1')) p['id']});
      expect(f1.produits('MED1').first[champEnAttenteMere], id1, reason: 'le marquage est celui de la DEMANDE, jamais la série commune');
      expect(f2.produits('MED1').first[champEnAttenteMere], id2);
      await c.converger(
          () => f1.demande(id1)?['etat'] == demandeImportAppliquee && f2.demande(id2)?['etat'] == demandeImportAppliquee && f1.demande(id1)?['marquageLeve'] == true && f2.demande(id2)?['marquageLeve'] == true,
          'la mère tranche les deux demandes',
          apres: 6);
      final v2 = f2.demande(id2)!;
      expect([v2['resultatCode'], v2['resultatAdoptee'], v2['restitution']], ['', true, isNull], reason: 'adopté : ni refus, ni restitution');
      expect(f1.demande(id1)!['resultatAdoptee'], isNot(true), reason: 'la première demande est la confirmation, pas une adoption');
      expect(libelleEtatDemandeImport(v2).libelle, 'Déjà confirmé par la mère, adopté');
      for (final (nom, e) in [('fileul 1', f1.comptesDe('MED1')), ('mère', c.comptesMere('MED1')), ('fileul 2', f2.comptesDe('MED1'))]) {
        expect(e, total, reason: '$nom : une fiche, deux lots, deux entrées, 150 unités, jamais le double');
      }
      expect(lotsApplique(c), hasLength(1), reason: 'la mère confirme UNE fois : un seul lot appliqué');
      expect([for (final x in f2.m.collection('mouvements').toutes) if (x['restitutionDe'] != null) x], isEmpty, reason: 'aucun mouvement inverse');
      expect(f2.m.collection('produits').toutes.where((p) => p['statut'] == 'archive'), isEmpty);
      for (final m in [f1.m, c.mm, f2.m]) {
        expect({for (final f in m.collection('produits').actives) if (f['code'] == 'MED1') f['id']}, {'PRO-$serie-1'});
      }
      expect(f2.m.collection('lots').toutes.where((f) => f.containsKey(champEnAttenteMere)), isEmpty);
      // JAMAIS VERS UN TÉLÉPHONE (RG-13) : ni les demandes (lignes, identité de lot, verdict d'adoption), ni les variations de stock.
      final mobile = await collectionsRecuesParUnMobile(c.port);
      expect(mobile.where((o) => o.collection == demandesImportCollection), isEmpty);
      expect(mobile.where((o) => o.collection == 'deltasCompteurs'), isEmpty);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 2, UNE SORTIE FAITE CHEZ CHACUN DES DEUX FILEULS sur le lot en attente est comptée UNE fois (130 partout), la mère coupée puis relancée', () async {
    final c = Clinique(9432, '${Directory.systemTemp.createTempSync('sigh-idem-2-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      await c.mere.arreter();
      final id1 = '${f1.importer('gs-valide').demande}', id2 = '${f2.importer('gs-valide').demande}';
      f1.sortir('MED1', 'L1', 10);
      f2.sortir('MED1', 'L1', 10);
      for (var i = 0; i < 3; i++) {
        await f1.tour();
        await f2.tour();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(f1.demande(id1)!['etat'], demandeImportEnAttente);
      await c.demarrerMere();
      await c.converger(() => f1.demande(id1)?['etat'] == demandeImportAppliquee && f2.demande(id2)?['etat'] == demandeImportAppliquee && f1.demande(id1)?['marquageLeve'] == true && f2.demande(id2)?['marquageLeve'] == true,
          'la mère revient et tranche',
          apres: 8);
      final attendu = {...total, 'stockGros': 130, 'sommeLots': 130};
      for (final (nom, e) in [('fileul 1', f1.comptesDe('MED1')), ('mère', c.comptesMere('MED1')), ('fileul 2', f2.comptesDe('MED1'))]) {
        expect(e, attendu, reason: '$nom : 150 importées, 2 x 10 sorties, chacune UNE fois, jamais les 300 d\'un double import');
      }
      expect([for (final x in c.mm.collection('mouvements').actives) if (x['type'] == 'sortie') x], hasLength(2));
      expect(f2.demande(id2)!['resultatAdoptee'], true);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 3, LE REJEU : verdict re-reçu, demande rejouée à la mère trois fois, redémarrage des ponts : état final identique, rien d\'ajouté, aucune ligne de journal de plus', () async {
    final c = Clinique(9433, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      final id1 = '${f1.importer('gs-valide').demande}', id2 = '${f2.importer('gs-valide').demande}';
      await c.converger(() => f1.demande(id1)?['marquageLeve'] == true && f2.demande(id2)?['marquageLeve'] == true, 'la mère tranche', apres: 5);
      final etat = [fiches(f1.m), fiches(f2.m), fiches(c.mm)];
      final lotsMere = c.mm.collection(collectionLots).toutes.length, demandesMere = c.mm.collection(demandesImportCollection).toutes.length;
      final journalImport0 = journalImport(c), journalDemandes0 = journalImport(c, 'Demande d’import');
      expect(journalDemandes0, greaterThan(0), reason: 'la mère a bien journalisé ses verdicts');
      for (var i = 0; i < 3; i++) {
        // La demande revient « en attente » à la mère (verdict perdu, demande reçue deux fois) : elle la rejoue.
        for (final d in c.mm.collection(demandesImportCollection).toutes) {
          c.mm.collection(demandesImportCollection).mettreAJour(d['id'], {'etat': demandeImportEnAttente, 'traiteLe': ''});
        }
        // Le marquage de chaque fileul est relevé de nouveau : comme après une coupure entre l'écriture et son accusé.
        for (final (f, id) in [(f1, id1), (f2, id2)]) {
          f.m.collection(demandesImportCollection).mettreAJour(id, {'marquageLeve': false});
          f.service.reconcilierVerdicts();
        }
        // Redémarrage des ponts sur les mêmes magasins.
        await PontActivite(c.mm, c.pontM.transport, etiquette: 'M').cycle();
        await PontActivite(f1.m, f1.pont.transport, etiquette: 'F1', enLectureSeule: collectionsDeLaMereSeule).cycle();
        await PontActivite(f2.m, f2.pont.transport, etiquette: 'F2', enLectureSeule: collectionsDeLaMereSeule).cycle();
        await attendreTours(c, 2);
      }
      for (final e in [f1.comptesDe('MED1'), c.comptesMere('MED1'), f2.comptesDe('MED1')]) {
        expect(e, total, reason: 'rejoué trois fois : 150, une fiche, deux lots');
      }
      expect([fiches(f1.m), fiches(f2.m), fiches(c.mm)], etat, reason: 'aucune fiche de plus nulle part');
      expect(c.mm.collection(collectionLots).toutes.length, lotsMere);
      expect(c.mm.collection(demandesImportCollection).toutes.length, demandesMere);
      expect(journalImport(c), journalImport0, reason: 'aucune ligne de journal d\'import de plus');
      expect(journalImport(c, 'Demande d’import'), journalDemandes0, reason: 'un verdict rejoué n\'est pas journalisé une seconde fois');
      expect(lotsApplique(c), hasLength(1));
      expect(c.mm.collection(demandesImportCollection).toutes.every((d) => d['etat'] == demandeImportAppliquee), isTrue, reason: 'le même verdict');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 4, LE MÊME FICHIER PLUS TARD, par un autre fileul ou par le même : rien à écrire, nommé (LOT_DEJA_IMPORTE), ni demande ni fiche', () async {
    final c = Clinique(9434, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      final id1 = '${f1.importer('gs-valide').demande}';
      await c.converger(() => f1.demande(id1)?['marquageLeve'] == true && f2.produits('MED1').isNotEmpty, 'la mère confirme, le stock arrive chez le second fileul', apres: 4);
      final avant = f2.comptesDe('MED1');
      final lotsF2 = f2.m.collection(collectionLots).toutes.length, demandes = c.mm.collection(demandesImportCollection).toutes.length;
      final r = f2.importer('gs-valide');
      expect([r.resultat.ok, r.resultat.code, r.demande], [false, 'LOT_DEJA_IMPORTE', isNull]);
      expect(r.resultat.motif, contains('déjà importé'));
      expect(f1.importer('gs-valide').resultat.code, 'LOT_DEJA_IMPORTE');
      await attendreTours(c, 2);
      expect(f2.comptesDe('MED1'), avant);
      expect(f2.m.collection(collectionLots).toutes.length, lotsF2, reason: 'aucun lot consigné pour un fichier déjà importé');
      expect(c.mm.collection(demandesImportCollection).toutes.length, demandes, reason: 'aucune demande déposée');
      expect(c.comptesMere('MED1'), total);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 5, ANNULATION PUIS RÉIMPORT avant la réponse de la mère : permis, série neuve ; la mère confirme UNE fois ; le second fileul (première tentative) est adopté et REBASÉ sans doublon', () async {
    final c = Clinique(9435, '${Directory.systemTemp.createTempSync('sigh-idem-5-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      await c.mere.arreter();
      final r1 = f1.importer('gs-valide');
      expect(r1.resultat.ok, isTrue);
      final a = f1.service.annulerLotDuFileul(r1.resultat.lot!['id'], profil: profilDe('admin'), nomAgent: f1.par, motif: 'erreur de fichier');
      expect(a.ok, isTrue, reason: 'annulation permise tant que la mère n\'a pas statué : ${a.motif}');
      expect(f1.produits('MED1'), isEmpty, reason: 'archivé');
      final r1b = f1.importer('gs-valide');
      expect(r1b.resultat.ok, isTrue, reason: 'le même fichier peut être réimporté après annulation : ${r1b.resultat.motif}');
      final id1 = '${r1b.demande}';
      expect(serieDe(f1, id1), isNot(serieDe(f1, '${r1.demande}')), reason: 'une nouvelle tentative a sa série : jamais une fiche archivée réutilisée');
      expect(f1.comptesDe('MED1'), total, reason: 'chez le fileul, une fois');
      final r2 = f2.importer('gs-valide');
      final id2 = '${r2.demande}';
      await c.demarrerMere();
      await c.converger(() => f1.demande(id1)?['marquageLeve'] == true && f2.demande(id2)?['etat'] == demandeImportAppliquee && f2.demande(id2)?['restitution'] != null, 'la mère tranche', apres: 8);
      for (final (nom, e) in [('fileul 1', f1.comptesDe('MED1')), ('mère', c.comptesMere('MED1')), ('fileul 2', f2.comptesDe('MED1'))]) {
        expect(e, total, reason: '$nom : 150 une fois');
      }
      expect(lotsApplique(c), hasLength(1));
      expect(f2.demande(id2)!['resultatAdoptee'], true);
      expect(f2.demande(id2)!['restitution'], restitutionFaite, reason: 'séries différentes : l\'écriture locale du second est rebasée (archivée), jamais doublée');
      expect(f1.demande('${r1.demande}')!['etat'], demandeImportRetiree);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 6, UNE CELLULE CHANGE : un AUTRE lot ; ses articles recouvrent ceux du premier : DOUBLON_MAGASIN nommé, restitution, jamais reconnu comme le même lot', () async {
    final c = Clinique(9436, ':memory:');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      final r1 = f1.importer('gs-valide');
      final r2 = f2.importerLignes(lignesModifiees(), 'modifie.xlsx');
      expect(r2.resultat.ok, isTrue, reason: '${r2.resultat.motif}');
      final id1 = '${r1.demande}', id2 = '${r2.demande}';
      expect(serieDe(f2, id2), isNot(serieDe(f1, id1)), reason: 'une cellule change : une autre identité de lot');
      await c.converger(() => f1.demande(id1)?['etat'] == demandeImportAppliquee && f2.demande(id2)?['etat'] == demandeImportRefusee && f2.demande(id2)?['restitution'] != null, 'la mère tranche', apres: 6);
      expect(f2.demande(id2)!['resultatCode'], 'DOUBLON_MAGASIN');
      expect(f2.demande(id2)!['resultatAdoptee'], isNot(true));
      expect(c.comptesMere('MED1'), total);
      expect(f2.comptesDe('MED1'), total, reason: 'chez le second : l\'article de la mère, le sien est restitué');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 7, LE PREMIER LOT EST REFUSÉ PAR LA MÈRE puis le même fichier d\'un second fileul : le refus s\'applique aux deux, nommé, rien n\'est adopté ; un rejeu ne consigne pas un lot refusé de plus', () async {
    final c = Clinique(9437, '${Directory.systemTemp.createTempSync('sigh-idem-7-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      final f2 = await c.fileul('F2', 'stock', 'GESTIONNAIRE DEUX');
      await c.tour();
      await c.mere.arreter();
      final id1 = '${f1.importer('gs-valide').demande}', id2 = '${f2.importer('gs-valide').demande}';
      c.mm.collection('produits').inserer({'id': 'PRD-MERE-1', 'code': 'MED1', 'designation': 'Paracétamol 500 mg', 'categorie': 'Médicaments', 'unite': 'Boîte', 'stockGros': 3, 'stock': 3, 'statut': 'actif'});
      await c.demarrerMere();
      await c.converger(() => f1.demande(id1)?['etat'] == demandeImportRefusee && f1.demande(id1)?['restitution'] != null && f2.demande(id2)?['etat'] == demandeImportRefusee && f2.demande(id2)?['restitution'] != null, 'la mère refuse les deux',
          apres: 2);
      expect(f1.demande(id1)!['resultatCode'], 'DOUBLON_MAGASIN');
      expect(lotsApplique(c), isEmpty, reason: 'la mère n\'a rien écrit');
      final v2 = f2.demande(id2)!;
      expect([v2['resultatCode'], v2['resultatAdoptee']], ['DOUBLON_MAGASIN', isNot(true)], reason: 'le refus s\'applique au second dépôt, nommé ; jamais adopté : le lot n\'a jamais été confirmé');
      for (final p in [f1, f2]) {
        expect(p.m.collection('produits').toutes.where((x) => x['serieDemande'] != null && x['statut'] != 'archive'), isEmpty, reason: '${p.nom} : son écriture est restituée');
      }
      expect(c.comptesMere('MED1')['fichesProduit'], 1, reason: 'la seule fiche de la mère');
      final consignes = c.mm.collection(collectionLots).toutes.length, refusees = journalImport(c, 'Import refusé');
      for (var i = 0; i < 3; i++) {
        for (final d in c.mm.collection(demandesImportCollection).toutes) {
          c.mm.collection(demandesImportCollection).mettreAJour(d['id'], {'etat': demandeImportEnAttente, 'traiteLe': ''});
        }
        await attendreTours(c, 2);
      }
      expect(c.mm.collection(collectionLots).toutes.length, consignes, reason: 'un rejeu d\'une demande refusée ne consigne pas un second lot refusé');
      expect(journalImport(c, 'Import refusé'), refusees);
      expect(c.mm.collection(demandesImportCollection).toutes.every((d) => d['etat'] == demandeImportRefusee), isTrue);
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));

  test('CAS 8, UNE RESTITUTION PARTIELLE REJOUÉE reste PARTIELLE (jamais « faite »), sans seconde contre-passation ni seconde ligne de journal', () async {
    final c = Clinique(9438, '${Directory.systemTemp.createTempSync('sigh-idem-8-').path}/mere.sqlite');
    await c.demarrer();
    try {
      final f1 = await c.fileul('F1', 'stock', 'GESTIONNAIRE UN');
      await c.tour();
      await c.mere.arreter();
      final id1 = '${f1.importer('gs-valide').demande}';
      f1.sortir('MED1', 'L1', 10);
      await c.demarrerMere();
      c.mm.collection('produits').inserer({'id': 'PRD-MERE-1', 'code': 'MED1', 'designation': 'Paracétamol 500 mg', 'categorie': 'Médicaments', 'unite': 'Boîte', 'stockGros': 3, 'stock': 3, 'statut': 'actif'});
      await c.converger(() => f1.demande(id1)?['etat'] == demandeImportRefusee && f1.demande(id1)?['restitution'] != null, 'la mère refuse', apres: 2);
      expect(f1.demande(id1)!['restitution'], restitutionPartielle);
      int inverses() => [for (final x in f1.m.collection('mouvements').toutes) if (x['restitutionDe'] != null) x].length;
      int restitutions() => [for (final l in f1.m.collection('audit').toutes) if ('${l['action']}'.startsWith('Import restitué')) l].length;
      final n = inverses(), journal = restitutions(), gardees = (f1.demande(id1)!['restitutionGardees'] as List).length;
      // Le drapeau de restitution est PERDU (coupure entre la restitution et son accusé) : le verdict est suivi de nouveau, trois fois.
      for (var i = 0; i < 3; i++) {
        f1.m.collection(demandesImportCollection).retirerChamp(id1, 'restitution');
        f1.m.collection(demandesImportCollection).retirerChamp(id1, 'restitutionGardees');
        f1.service.reconcilierVerdicts();
        expect(f1.demande(id1)!['restitution'], restitutionPartielle, reason: 'rejeu $i : une restitution partielle ne devient jamais « faite »');
        expect((f1.demande(id1)!['restitutionGardees'] as List).length, gardees, reason: 'les fiches gardées sont rendues de nouveau');
      }
      expect(inverses(), n, reason: 'aucune seconde contre-passation');
      expect(restitutions(), journal, reason: 'aucune ligne de journal de restitution de plus');
    } finally {
      await c.arreter();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}
