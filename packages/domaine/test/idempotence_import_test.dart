// L'IDEMPOTENCE DE L'IMPORT PAR LE CONTENU (lot IDEM, portage du lot de la clinique sœur, décisions du 13/11/2026) : le même inventaire est le même lot, quel que soit le fileul ou le
// moment ; la mère le confirme UNE fois et ADOPTE le second dépôt ; un verdict ou une restitution rejoués ne produisent jamais un second mouvement ni une ligne de journal de plus.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

ProfilImport profilDe(MatriceDroits m, String role) => ProfilImport(role: role, libelleRole: m.libelle(role) ?? role, droitEcran: (e) => m.droit(role, e));

/// Un port de MÈRE dont le profil et l'auteur changent à chaque demande (elle rejoue sous le rôle et le nom de l'auteur).
class PortMere extends PortImportMemoire {
  PortMere(super.jeu) : super(prefixeId: 'M-', jourFixe: '2026-11-13');
  ProfilImport? profilCourant;
  String? auteur;
  @override
  ProfilImport get profil => profilCourant ?? super.profil;
  @override
  String get utilisateur => auteur ?? super.utilisateur;
}

void main() {
  final base = MatriceDroits.depuisJson((jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>());
  final deLaMere = {...cfbEssentielles, 'utilisateurs', valCollectionValidations, parCollectionParametres}.difference({'rolesBase', 'modulesManifeste', 'reglages', 'audit'});
  final regime = RegimeDemandesImport(collectionsDeLaMere: deLaMere);
  final vecteurs = (jsonDecode(File('test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();
  final magasinInitial = (vecteurs['magasin'] as Map).cast<String, Object?>();
  List<List<Object?>> inventaire() => [
        for (final l in ((vecteurs['cas'] as List).cast<Map>().firstWhere((x) => x['id'] == 'gs-valide')['lignes'] as List)) [for (final c in (l as List)) c]
      ];
  const compteurs = {
    'produits': {'stockGros', 'stockDetail', 'stock'},
    'lots': {'quantiteRestante'},
  };

  PortImportMemoire nouveauFileul(String id) =>
      PortImportMemoire(magasinInitial, profilFixe: profilDe(base, 'stock'), utilisateurFixe: 'GESTIONNAIRE $id', prefixeId: '$id-', jourFixe: '2026-11-13');

  /// Ce que fait le FILEUL : l'écriture directe puis la demande, par le chemin du domaine.
  ({Map<String, Object?> demande, PortImportMemoire fileul, ResultatImport resultat}) fileulEcrit(String idDemande, {List<List<Object?>>? lignes, PortImportMemoire? sur}) {
    final fileul = sur ?? nouveauFileul(idDemande);
    final a = analyserFichier(jeuGrandStock, lignes ?? inventaire(), 'x.xlsx', fileul, empreinte: 'abc');
    expect(a.accepte, isTrue, reason: a.problemes.map((p) => '${p.code}:${p.motif}').join(' / '));
    final r = importerDirectEtDemander(jeu: jeuGrandStock, analyse: a, port: fileul, regime: regime, idDemande: idDemande, poste: 'F-$idDemande', compteurs: compteurs);
    expect(r.ok, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
    return (demande: r.demande!, fileul: fileul, resultat: r.resultat!);
  }

  VerdictDemandeImport lamere(Map<String, Object?> demande, PortMere mere) {
    mere
      ..profilCourant = profilDe(base, '${demande['demandeRole']}')
      ..auteur = '${demande['demandePar']}';
    return traiterDemandeImport({...demande}, mere, jeuImportParId, regime: regime, compteurs: compteurs);
  }

  int fiches(PortImportMemoire m) => ['produits', 'lots', 'mouvements', collectionLots].fold<int>(0, (t, c) => t + m.toutes(c).length);

  group('LES TROIS DÉFAUTS PROUVÉS ROUGES AVANT LE LOT (adoption, refus rejoué, restitution partielle rejouée)', () {
    test('DEUX FILEULS, MÊME INVENTAIRE : la mère confirme la première demande et NE REFUSE PAS la seconde, elle l\'adopte (un seul lot, un seul stock)', () {
      final a = fileulEcrit('DIMA1'), b = fileulEcrit('DIMB1');
      final mere = PortMere(magasinInitial);
      expect(lamere(a.demande, mere).appliquee, isTrue);
      final v2 = lamere(b.demande, mere);
      expect(v2.appliquee, isTrue, reason: 'refusée après coup (${v2.code}) : le même inventaire ne devrait compter qu\'une fois, sans refus');
      expect(mere.toutes(collectionLots).where((l) => l['etat'] == 'applique'), hasLength(1));
      expect(mere.toutes('produits').where((p) => p['code'] == 'MED1'), hasLength(1));
    });

    test('UN REFUS REJOUÉ ne consigne pas un second fichier refusé ni une seconde ligne de journal', () {
      final a = fileulEcrit('DIMA2');
      final mere = PortMere(magasinInitial)..inserer('produits', {'id': 'PRD-MERE-1', 'code': 'MED1', 'designation': 'Tenu à la mère', 'categorie': 'Médicaments', 'statut': 'actif'});
      expect(lamere(a.demande, mere).appliquee, isFalse);
      final consignes = mere.toutes(collectionLots).length, journal = mere.journal.length;
      for (var i = 0; i < 3; i++) {
        lamere(a.demande, mere);
      }
      expect(mere.toutes(collectionLots), hasLength(consignes), reason: 'un rejeu consigne un lot refusé de plus');
      expect(mere.journal, hasLength(journal));
    });

    test('UNE RESTITUTION PARTIELLE REJOUÉE reste PARTIELLE : mêmes fiches gardées, sans seconde contre-passation ni ligne de journal', () {
      final e = fileulEcrit('DIMA3');
      e.fileul.toutes('lots').firstWhere((f) => f['numeroLot'] == 'L1')['quantiteRestante'] = 90;
      final med1 = e.fileul.toutes('produits').firstWhere((f) => f['code'] == 'MED1');
      med1['stockGros'] = 140;
      med1['stock'] = 140;
      final lotId = e.resultat.lot!['id'];
      final r1 = restituerLotDirect(jeuImportParId, lotId, codeRefus: 'DOUBLON_MAGASIN', motifRefus: 'déjà tenu', port: e.fileul);
      expect(r1.etat, restitutionPartielle);
      final mouvements = e.fileul.toutes('mouvements').length, journal = e.fileul.journal.length;
      final r2 = restituerLotDirect(jeuImportParId, lotId, codeRefus: 'X', motifRefus: 'x', port: e.fileul);
      expect([r2.ok, r2.etat, r2.gardees.length], [true, restitutionPartielle, r1.gardees.length], reason: 'rejouée, la restitution partielle se disait « faite »');
      expect(e.fileul.toutes('mouvements'), hasLength(mouvements));
      expect(e.fileul.journal, hasLength(journal));
    });
  });

  group('L\'IDENTITÉ DE CONTENU', () {
    test('64 hexadécimaux, stable sous les variations de FORME du même inventaire, différente à la moindre variation de CONTENU', () {
      final ref = identiteLotImport('grand-stock', inventaire());
      expect(ref, matches(RegExp(r'^[0-9a-f]{64}$')));
      final forme = [for (final r in inventaire()) [...r]];
      forme[0] = [for (final c in forme[0]) '${c.toString().toUpperCase().replaceAll(' ', '  ')} '];
      forme[1][1] = ' ${forme[1][1]} ';
      forme[1][4] = (forme[1][4] as num).toDouble();
      forme[2] = [...forme[2], '', ''];
      forme.addAll([
        ['', '', ''],
        [null, null]
      ]);
      expect(identiteLotImport('grand-stock', forme), ref, reason: 'un classeur et un CSV du même inventaire donnent la même identité');
      final cellule = [for (final r in inventaire()) [...r]]..[1][4] = ((inventaire()[1][4] as num) + 1);
      expect(identiteLotImport('grand-stock', cellule), isNot(ref), reason: 'une seule cellule qui change : un AUTRE lot');
      expect(identiteLotImport('autre-jeu', inventaire()), isNot(ref), reason: 'le même contenu dans un autre jeu est un autre lot');
    });

    test('la SÉRIE dérive de l\'identité ; la tentative n\'ajoute que son suffixe ; une série n\'est reconnue que pour sa propre identité', () {
      final id = identiteLotImport('grand-stock', inventaire());
      final s1 = serieDuLotImport(id), s2 = serieDuLotImport(id, 2);
      expect([s1, s2], ['IMP${id.substring(0, 20)}', 'IMP${id.substring(0, 20)}T2']);
      expect([serieEstDeLIdentite(s1, id), serieEstDeLIdentite(s2, id), serieEstDeLIdentite('IMPautre', id), serieEstDeLIdentite('${s1}x', id)], [true, true, false, false]);
    });
  });

  group('DEUX FILEULS, MÊME FICHIER', () {
    test('mêmes identifiants de fiche chez les deux, chacun avec le marquage de SA demande ; la mère confirme UNE fois et adopte la seconde (rien réécrit, rien journalisé)', () {
      final a = fileulEcrit('DIMA10'), b = fileulEcrit('DIMB10');
      expect(a.demande['serieIdentifiants'], b.demande['serieIdentifiants']);
      expect(a.demande['identiteLot'], b.demande['identiteLot']);
      final med = (PortImportMemoire p) => p.toutes('produits').firstWhere((f) => f['code'] == 'MED1');
      expect([med(a.fileul)['id'], med(a.fileul)[champEnAttenteMere], med(b.fileul)[champEnAttenteMere]], ['PRO-${a.demande['serieIdentifiants']}-1', 'DIMA10', 'DIMB10']);
      final mere = PortMere(magasinInitial);
      final v1 = lamere(a.demande, mere);
      expect([v1.appliquee, v1.adoptee, v1.serie], [true, false, a.demande['serieIdentifiants']], reason: '${v1.motif}');
      final avant = fiches(mere), journal = mere.journal.length;
      final v2 = lamere(b.demande, mere);
      expect([v2.appliquee, v2.adoptee, v2.lot, v2.ecrits], [true, true, v1.lot, v1.ecrits], reason: '${v2.motif}');
      expect(fiches(mere), avant);
      expect(mere.journal, hasLength(journal), reason: 'aucune ligne de journal de plus');
      final champs = v2.versChamps(traitePar: 'Mère', traiteLe: '2026-11-13');
      expect([champs['etat'], champs['resultatAdoptee'], champs['resultatCode']], [demandeImportAppliquee, true, '']);
      expect(libelleEtatDemandeImport({...b.demande, ...champs}).libelle, 'Déjà confirmé par la mère, adopté');
      expect(libelleEtatDemandeImport({...a.demande, ...v1.versChamps(traitePar: 'Mère', traiteLe: 'x')}).libelle, 'Appliquée par la mère');
    });

    test('LE REJEU : chaque demande rejouée 1, 2, 3 fois, dans le désordre, rend le même verdict et n\'ajoute ni fiche ni ligne de journal', () {
      final a = fileulEcrit('DIMA11'), b = fileulEcrit('DIMB11');
      final mere = PortMere(magasinInitial);
      final premiers = [lamere(a.demande, mere), lamere(b.demande, mere)];
      final avant = fiches(mere), journal = mere.journal.length;
      for (final ordre in [
        [b, a],
        [a, b, b, a],
        [b, b, b]
      ]) {
        for (final x in ordre) {
          final v = lamere(x.demande, mere), attendu = premiers[identical(x, a) ? 0 : 1];
          expect([v.appliquee, v.adoptee, v.lot, v.ecrits], [attendu.appliquee, attendu.adoptee, attendu.lot, attendu.ecrits]);
        }
      }
      expect(fiches(mere), avant);
      expect(mere.journal, hasLength(journal));
    });

    test('UNE DEMANDE NE SE FAIT PAS PASSER POUR UN AUTRE LOT : identité des lignes et série de l\'identité exigées (IDENTITE_LOT_INCOHERENTE)', () {
      final a = fileulEcrit('DIMA12');
      final mere = PortMere(magasinInitial);
      expect(lamere(a.demande, mere).appliquee, isTrue);
      final avant = fiches(mere);
      final autre = [for (final r in inventaire()) [...r]]..[1][4] = 999;
      final b = fileulEcrit('DIMB12', lignes: autre);
      final forgee = {...b.demande, 'identiteLot': a.demande['identiteLot'], 'serieIdentifiants': a.demande['serieIdentifiants']};
      expect(lamere(forgee, mere).code, 'IDENTITE_LOT_INCOHERENTE');
      expect(lamere({...b.demande, 'serieIdentifiants': a.demande['serieIdentifiants']}, mere).code, 'IDENTITE_LOT_INCOHERENTE');
      expect(fiches(mere), avant, reason: 'rien n\'est écrit');
    });

    test('UNE CELLULE CHANGE : un AUTRE lot, jamais adopté ; ses articles recouvrent ceux du premier : DOUBLON_MAGASIN nommé', () {
      final a = fileulEcrit('DIMA13');
      final autre = [for (final r in inventaire()) [...r]]..[1][4] = ((inventaire()[1][4] as num) + 1);
      final b = fileulEcrit('DIMB13', lignes: autre);
      expect(b.demande['serieIdentifiants'], isNot(a.demande['serieIdentifiants']));
      final mere = PortMere(magasinInitial);
      expect(lamere(a.demande, mere).appliquee, isTrue);
      final v = lamere(b.demande, mere);
      expect([v.appliquee, v.adoptee, v.code], [false, false, 'DOUBLON_MAGASIN']);
      expect(mere.toutes('produits').where((f) => f['code'] == 'MED1'), hasLength(1));
    });

    test('LE PREMIER LOT EST REFUSÉ : le refus s\'applique au second dépôt, nommé, sans adoption ; un fichier refusé consigné UNE fois par demande', () {
      final a = fileulEcrit('DIMA14'), b = fileulEcrit('DIMB14');
      final mere = PortMere(magasinInitial)..inserer('produits', {'id': 'PRD-MERE-1', 'code': 'MED1', 'designation': 'Tenu à la mère', 'categorie': 'Médicaments', 'statut': 'actif'});
      final v1 = lamere(a.demande, mere), v2 = lamere(b.demande, mere);
      expect([v1.appliquee, v1.code, v2.appliquee, v2.adoptee, v2.code], [false, 'DOUBLON_MAGASIN', false, false, 'DOUBLON_MAGASIN']);
      expect(mere.toutes(collectionLots).where((l) => l['etat'] == 'applique'), isEmpty);
      expect(mere.toutes(collectionLots).where((l) => l['etat'] == 'refuse'), hasLength(2));
      for (var i = 0; i < 3; i++) {
        lamere(a.demande, mere);
        lamere(b.demande, mere);
      }
      expect(mere.toutes(collectionLots).where((l) => l['etat'] == 'refuse'), hasLength(2), reason: 'un rejeu ne consigne rien de plus');
      expect(mere.journal.where((l) => l.startsWith('Import refusé')), hasLength(2));
    });

    test('UN LOT ANNULÉ À LA MÈRE n\'est jamais ressuscité par une demande de la même série (LOT_ANNULE_A_LA_MERE)', () {
      final a = fileulEcrit('DIMA15'), b = fileulEcrit('DIMB15');
      final mere = PortMere(magasinInitial);
      lamere(a.demande, mere);
      final lot = mere.toutes(collectionLots).firstWhere((l) => l['etat'] == 'applique');
      mere
        ..profilCourant = profilDe(base, 'admin')
        ..auteur = '${lot['par']}';
      expect(annulerLot(jeuImportParId, lot['id'], 'erreur', mere).ok, isTrue);
      final avant = fiches(mere);
      final v = lamere(b.demande, mere);
      expect([v.appliquee, v.code], [false, 'LOT_ANNULE_A_LA_MERE']);
      expect(fiches(mere), avant);
    });
  });

  group('LE MÊME FICHIER ENCORE UNE FOIS', () {
    test('DÉJÀ TENU : lignes ignorées et nommées LOT_DEJA_IMPORTE, appliquer répond le même code, rien n\'est écrit ; une cellule qui change n\'est pas le même lot', () {
      final a = fileulEcrit('DIMA16');
      final avant = fiches(a.fileul);
      final analyse = analyserLignes(jeuGrandStock, inventaire(), 'x.xlsx', a.fileul);
      expect([analyse.accepte, analyse.aEcrire, analyse.ignorees.length, analyse.compte.refus], [true, 0, 3, 0]);
      expect({for (final p in analyse.problemes) p.code}, {'LOT_DEJA_IMPORTE'});
      expect(analyse.problemes.first.motif, allOf(contains('déjà importé'), contains('${a.demande['serieIdentifiants']}')));
      final depot = importerDirectEtDemander(jeu: jeuGrandStock, analyse: analyse, port: a.fileul, regime: regime, idDemande: 'DIMA16b', poste: 'F', compteurs: compteurs);
      expect([depot.ok, depot.refus?.code], [false, 'LOT_DEJA_IMPORTE'], reason: 'un second dépôt du même fichier ne dépose rien et le dit');
      final r = appliquer(jeuGrandStock, analyse, a.fileul);
      expect([r.ok, r.code], [false, 'LOT_DEJA_IMPORTE']);
      expect(fiches(a.fileul), avant, reason: 'ni fiche, ni lot consigné');
      final modifie = analyserLignes(jeuGrandStock, [for (final r in inventaire()) [...r]]..[1][4] = 7, 'z.xlsx', a.fileul);
      expect(modifie.accepte, isFalse);
      expect({for (final p in modifie.problemes) p.code}, allOf(contains('DOUBLON_MAGASIN'), isNot(contains('LOT_DEJA_IMPORTE'))));
    });

    test('UNE FICHE ARCHIVÉE À LA MAIN continue de compter comme déjà tenue ; seule la défaite d\'un lot libère ses fiches', () {
      final a = fileulEcrit('DIMA17');
      for (final c in ['produits', 'lots', 'mouvements']) {
        for (final f in a.fileul.toutes(c).where((f) => f[champSerieDemande] != null).toList()) {
          a.fileul.archiver(c, f['id'], 'à la main');
        }
      }
      expect(analyserLignes(jeuGrandStock, inventaire(), 'x.xlsx', a.fileul).accepte, isFalse, reason: 'sans lot défait, la fiche archivée bloque encore le même code');
    });

    test('RÉIMPORT APRÈS ANNULATION : permis, sous une série neuve (tentative 2), jamais une fiche archivée réutilisée ; troisième tentative T3', () {
      final a = fileulEcrit('DIMA18');
      final admin = PortImportMemoire(a.fileul.instantane(), profilFixe: profilDe(base, 'admin'), utilisateurFixe: 'GESTIONNAIRE DIMA18', prefixeId: 'A-', jourFixe: '2026-11-13');
      expect(annulerLot(jeuImportParId, a.resultat.lot!['id'], 'erreur de fichier', admin).ok, isTrue);
      final prep = preparerLotImport(jeuGrandStock, inventaire(), admin);
      final serie = '${a.demande['serieIdentifiants']}';
      expect(prep.serie, '${serie}T2');
      final b = fileulEcrit('DIMA19', sur: admin);
      expect(b.demande['serieIdentifiants'], '${serie}T2');
      expect(admin.actives('produits').where((f) => f['code'] == 'MED1'), hasLength(1));
      expect({for (final f in admin.toutes('produits')) f['id']}, containsAll(['PRO-$serie-1', 'PRO-${serie}T2-1']));
      expect(() => PortDemandeImport(admin, demandeId: serie, compteurs: compteurs).inserer('produits', {'id': 'PRO-$serie-1', 'code': 'X'}), throwsStateError);
      expect(annulerLot(jeuImportParId, b.resultat.lot!['id'], 'encore', admin).ok, isTrue);
      expect(preparerLotImport(jeuGrandStock, inventaire(), admin).serie, '${serie}T3');
    });

    test('L\'ADOPTION D\'UNE AUTRE SÉRIE : la mère tient la tentative 2 ; le fileul de la tentative 1 est adopté puis REBASÉ (restitution, pas un refus)', () {
      final a = fileulEcrit('DIMA20');
      final admin = PortImportMemoire(a.fileul.instantane(), profilFixe: profilDe(base, 'admin'), utilisateurFixe: 'GESTIONNAIRE DIMA20', prefixeId: 'A-', jourFixe: '2026-11-13');
      annulerLot(jeuImportParId, a.resultat.lot!['id'], 'erreur', admin);
      final a2 = fileulEcrit('DIMA21', sur: admin), b = fileulEcrit('DIMB20');
      expect(a2.demande['serieIdentifiants'], isNot(b.demande['serieIdentifiants']));
      final mere = PortMere(magasinInitial);
      final v1 = lamere(a2.demande, mere);
      final avant = fiches(mere);
      final v2 = lamere(b.demande, mere);
      expect([v2.appliquee, v2.adoptee, v2.serie, v2.lot], [true, true, a2.demande['serieIdentifiants'], v1.lot], reason: '${v2.motif}');
      expect(fiches(mere), avant);
      final demande = {...b.demande, ...v2.versChamps(traitePar: 'Mère', traiteLe: 'x')};
      expect(suiteDuVerdict(demande), SuiteDuVerdict.rebaser);
      expect(suiteDuVerdict({...demande, 'restitution': restitutionFaite}), SuiteDuVerdict.aucune);
      expect(suiteDuVerdict({...demande, 'restitution': restitutionPartielle}), SuiteDuVerdict.aucune, reason: 'jamais un second rebasage, ni après une restitution partielle');
      expect(suiteDuVerdict({...demande, 'marquageLeve': true}), SuiteDuVerdict.aucune);
    });

    test('LE RÉSULTAT DOIT ÊTRE LE MÊME : un fileul qui a écrit d\'autres lignes que le lot tenu n\'est pas adopté (RESULTAT_DIFFERENT)', () {
      final a = fileulEcrit('DIMA22'), b = fileulEcrit('DIMB22');
      final mere = PortMere(magasinInitial);
      expect(lamere(a.demande, mere).appliquee, isTrue);
      final v = lamere({...b.demande, 'rangsEcrits': [2]}, mere);
      expect([v.appliquee, v.code], [false, 'RESULTAT_DIFFERENT']);
    });
  });
}
