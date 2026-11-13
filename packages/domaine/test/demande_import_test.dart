// LA DEMANDE D'IMPORT D'UN FILEUL À LA MÈRE (lot IMP-C, « option c » de la Direction du 12/11/2026, reprise du lot IMP-D de la clinique sœur), rejouée sur deux magasins en mémoire :
// le fileul écrit chez lui ET dépose une demande ; la mère rejoue sous le rôle de l'auteur, exige le même résultat et reste la seule autorité ; les fiches ont UNE identité commune ;
// sur refus le fileul RESTITUE (archivage RG-14), sans jamais réécrire une pièce émise.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

ProfilImport profilDe(MatriceDroits m, String role) => ProfilImport(role: role, libelleRole: m.libelle(role) ?? role, droitEcran: (e) => m.droit(role, e));

void main() {
  final base = MatriceDroits.depuisJson((jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map).cast<String, Object?>());
  // Les collections que la mère seule écrit (comme `collectionsConfiguration()` du poste).
  final deLaMere = {...cfbEssentielles, 'utilisateurs', valCollectionValidations, parCollectionParametres}.difference({'rolesBase', 'modulesManifeste', 'reglages', 'audit'});
  final regime = RegimeDemandesImport(collectionsDeLaMere: deLaMere);

  List<List<Object?>> fichier(List<String> codes) => [
        [for (final c in jeuFournisseurs.colonnes) c.label],
        for (final code in codes) [...ligneExemple(jeuFournisseurs)]..[0] = code..[1] = 'FOURNISSEUR $code',
      ];
  // Le fileul : comptable (droit d'importer les fournisseurs dans la matrice d'origine), identifiants propres au poste.
  PortImportMemoire fileul({String role = 'comptable', Map<String, Object?> jeu = const {}}) =>
      PortImportMemoire(jeu, profilFixe: profilDe(base, role), utilisateurFixe: 'COMPTABLE F1', prefixeId: 'FOURF1-', jourFixe: '2026-11-12');
  PortImportMemoire mere(ProfilImport p, {Map<String, Object?> jeu = const {}}) => PortImportMemoire(jeu, profilFixe: p, utilisateurFixe: 'COMPTABLE F1', prefixeId: 'FOUR', jourFixe: '2026-11-12');

  ImportDirectEtDemande deposer(PortImportMemoire f, List<String> codes, {String id = 'DIM1'}) {
    final a = analyserFichier(jeuFournisseurs, fichier(codes), 'fournisseurs.xlsx', f);
    expect(a.accepte, isTrue, reason: a.problemes.map((p) => p.motif).join(' / '));
    return importerDirectEtDemander(jeu: jeuFournisseurs, analyse: a, port: f, regime: regime, idDemande: id, poste: 'F1');
  }

  group('quels jeux passent par une demande', () {
    test('les jeux non restreints dont une cible est de la configuration de la mère — le Grand Stock y compris (lot IMP-E) ; jamais un jeu restreint', () {
      final demandables = {for (final j in jeuxImport) if (regime.exigeLaMere(j)) j.id};
      expect(demandables, {'actes', 'analyses', 'fournisseurs', 'assureurs', 'souscripteurs', 'plan-comptable', 'produits', 'emplacements', 'grand-stock'},
          reason: 'mesuré : les jeux non restreints dont une cible est de la configuration de la mère');
      for (final jamais in ['personnel', 'patients', 'soldes-ouverture', 'stock-detail', 'transferts', 'inventaire', 'courriers']) {
        expect(demandables.contains(jamais), isFalse, reason: '$jamais ne passe jamais par une demande');
      }
      expect({for (final j in jeuxImport) if (j.restreint) j.id}.intersection(demandables), isEmpty, reason: 'un jeu restreint ne passe JAMAIS par une demande');
      expect(regime.reserveALaMere(jeuPersonnel), isTrue, reason: 'le personnel se règle à la mère : le fileul le dit');
    });
  });

  group('le fileul : écriture directe ET demande', () {
    test('il voit son import tout de suite (identité de la demande, « en attente de la mère ») et la demande part vérifiée avec ce que la mère doit reproduire', () {
      final f = fileul();
      final r = deposer(f, ['SOBAPS', 'NSIA']);
      expect(r.ok, isTrue);
      final fiches = f.actives('fournisseurs');
      expect(fiches, hasLength(2), reason: 'visible chez le fileul immédiatement');
      expect([for (final x in fiches) x['id']].toSet(), {'FOU-DIM1-1', 'FOU-DIM1-2'}, reason: 'identité de la demande, jamais l\'étiquette du poste');
      expect(fiches.every((x) => x[champEnAttenteMere] == 'DIM1' && x[champSerieDemande] == 'DIM1' && x['provisoireMere'] == null), isTrue);
      final d = r.demande!;
      expect(d['etat'], demandeImportEnAttente);
      expect(d['demandeRole'], 'comptable');
      expect(d['demandePar'], 'COMPTABLE F1');
      expect((d['lignes'] as List), hasLength(3), reason: 'l\'en-tête et deux lignes : la mère doit pouvoir rejouer');
      expect(d['ecritureDirecte'], isTrue);
      expect(d['serieIdentifiants'], 'DIM1');
      expect(d['rangsEcrits'], [2, 3]);
      final lot = f.toutes(collectionLots).single;
      expect(d['lotLocal'], lot['reference']);
      expect(d['lotLocalId'], lot['id']);
      expect(f.journal.any((l) => l.startsWith('Demande d’import déposée à la mère')), isTrue, reason: 'RG-12 : journal côté fileul');
      expect(libelleEtatDemandeImport(d).libelle, 'Écrit chez vous, en attente de la mère', reason: 'jamais « appliquée » avant la confirmation');
    });

    test('sans le droit du rôle : refus nommé du moteur, RIEN d\'écrit, RIEN de déposé', () {
      final f = fileul(role: 'medecin');
      final a = analyserFichier(jeuFournisseurs, fichier(['X']), 'f.xlsx', fileul());
      final r = importerDirectEtDemander(jeu: jeuFournisseurs, analyse: a, port: f, regime: regime, idDemande: 'DIM9', poste: 'F1');
      expect(r.ok, isFalse);
      expect(r.refus!.code, 'DROIT_IMPORT_REFUSE');
      expect(f.toutes('fournisseurs'), isEmpty);
    });

    test('un jeu restreint ne se dépose JAMAIS (refus nommé, rien écrit)', () {
      final f = fileul(role: 'admin');
      final a = analyserFichier(jeuPersonnel, [[for (final c in jeuPersonnel.colonnes) c.label]], 'p.xlsx', f);
      final r = importerDirectEtDemander(jeu: jeuPersonnel, analyse: a, port: f, regime: regime, idDemande: 'DIM8', poste: 'F1');
      expect(r.ok, isFalse);
      expect(r.refus!.code, 'JEU_NON_DEMANDABLE');
    });
  });

  group('la mère : seule autorité', () {
    Map<String, Object?> demandeValide() => deposer(fileul(), ['SOBAPS', 'NSIA']).demande!;

    test('elle rejoue sous le rôle de l\'auteur et applique par le chemin de l\'import local, lot et journal à elle', () {
      final m = mere(profilDe(base, 'comptable'));
      final v = traiterDemandeImport(demandeValide(), m, jeuImportParId, regime: regime);
      expect(v.appliquee, isTrue, reason: '${v.code} ${v.motif}');
      expect(v.ecrits, 2);
      expect(m.actives('fournisseurs'), hasLength(2));
      expect([for (final x in m.actives('fournisseurs')) x['id']].toSet(), {'FOU-DIM1-1', 'FOU-DIM1-2'}, reason: 'MÊMES identifiants que chez le fileul : une fiche par code, jamais deux');
      expect(m.actives('fournisseurs').every((x) => x[champEnAttenteMere] == null && x['lotImport'] == v.lot), isTrue, reason: 'les fiches de la mère ne portent aucun marquage « en attente »');
      expect(m.journal.any((l) => l.startsWith('Import|')), isTrue);
      final champs = v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-12');
      expect(champs['etat'], demandeImportAppliquee);
      expect(champs['lignes'], isEmpty, reason: 'les lignes du fichier sont effacées dès le verdict');
    });

    test('REFUS : le rôle de l\'auteur n\'a plus (ou n\'a jamais eu) le droit, relu à la mère — un fileul falsifié ne se prête pas les droits d\'un autre', () {
      final d = demandeValide();
      final m = mere(profilDe(base, 'medecin'));
      final v = traiterDemandeImport({...d, 'demandeRole': 'medecin'}, m, jeuImportParId, regime: regime);
      expect(v.appliquee, isFalse);
      expect(v.code, 'DROIT_IMPORT_REFUSE');
      expect(m.toutes('fournisseurs'), isEmpty);
      expect(m.toutes(collectionLots), isEmpty, reason: 'un refus de droit ne se consigne pas');
    });

    test('REFUS NOMMÉ : une fiche équivalente créée à la mère entre-temps (DOUBLON_MAGASIN), le fichier consigné, rien écrit', () {
      final m = mere(profilDe(base, 'comptable'), jeu: {
        'fournisseurs': [
          {'id': 'F1', 'code': 'SOBAPS', 'nom': 'Existant', 'statut': 'actif'}
        ]
      });
      final v = traiterDemandeImport(demandeValide(), m, jeuImportParId, regime: regime);
      expect(v.appliquee, isFalse);
      expect(v.code, 'DOUBLON_MAGASIN');
      expect(v.motif, contains('rejoué à la mère'));
      expect(v.lot, isNotNull, reason: 'le fichier refusé est consigné à l\'historique de la mère');
      expect(m.actives('fournisseurs'), hasLength(1));
    });

    test('FORGÉE : une demande pour un jeu restreint est refusée en le nommant, même si l\'auteur a tous les droits', () {
      final m = mere(profilDe(base, 'admin'));
      final d = {...demandeValide(), 'jeu': 'patients', 'lignes': [[for (final c in jeuPatients.colonnes) c.label]]};
      final v = traiterDemandeImport(d, m, jeuImportParId, regime: regime);
      expect(v.code, 'JEU_RESTREINT');
      expect(m.toutes('patients'), isEmpty);
    });

    test('FORGÉE : un jeu que la mère n\'écrit pas seule (courriers restreints, stock vivant) ou un jeu inconnu ne passe pas', () {
      final m = mere(profilDe(base, 'admin'));
      expect(traiterDemandeImport({...demandeValide(), 'jeu': 'stock-detail'}, m, jeuImportParId, regime: regime).code, 'JEU_RESTREINT');
      expect(traiterDemandeImport({...demandeValide(), 'jeu': 'inconnu'}, m, jeuImportParId, regime: regime).code, 'JEU_INCONNU');
    });

    test('FORGÉE : des lignes démesurées (au-delà de la borne du jeu) sont refusées avant tout rejeu', () {
      final m = mere(profilDe(base, 'comptable'));
      final enorme = [
        for (var i = 0; i < 3; i++) ['X' * 400000]
      ];
      final v = traiterDemandeImport({...demandeValide(), 'lignes': enorme}, m, jeuImportParId, regime: regime, octetsMax: 50 * 1024);
      expect(v.code, 'FICHIER_TROP_GROS');
    });

    test('un verdict n\'est jamais écrit deux fois', () {
      final m = mere(profilDe(base, 'comptable'));
      final d = demandeValide();
      final v = traiterDemandeImport(d, m, jeuImportParId, regime: regime);
      final dejaTraitee = {...d, ...v.versChamps(traitePar: 'Mère', traiteLe: '2026-11-12')};
      expect(traiterDemandeImport(dejaTraitee, m, jeuImportParId, regime: regime).code, 'DEMANDE_DEJA_TRAITEE');
      expect(m.actives('fournisseurs'), hasLength(2), reason: 'pas de seconde écriture');
    });
  });

  group('la mère exige le MÊME résultat, et une demande rejouée ne compte qu\'une fois', () {
    test('une ligne que la mère n\'écrirait pas (déjà tenue chez elle) : RESULTAT_DIFFERENT ou doublon nommé, rien d\'écrit', () {
      final f = fileul();
      final d = deposer(f, ['SOBAPS', 'NSIA']).demande!;
      // la demande dit que le fileul a écrit deux lignes ; la mère n'en écrirait qu'une : elle refuse en le nommant
      final m = mere(profilDe(base, 'comptable'));
      final v = traiterDemandeImport({...d, 'rangsEcrits': [2, 3, 4]}, m, jeuImportParId, regime: regime);
      expect(v.appliquee, isFalse);
      expect(v.code, 'RESULTAT_DIFFERENT');
      expect(v.motif, contains('ligne 4'));
      expect(m.toutes('fournisseurs'), isEmpty, reason: 'rien n\'est écrit');
    });

    test('REJEU : la même demande reçue deux fois rend le MÊME verdict sans rien réécrire (ni fiche, ni lot, ni ligne de journal de plus)', () {
      final d = deposer(fileul(), ['SOBAPS', 'NSIA']).demande!;
      final m = mere(profilDe(base, 'comptable'));
      final v1 = traiterDemandeImport(d, m, jeuImportParId, regime: regime);
      final journal = m.journal.length, lots = m.toutes(collectionLots).length;
      final v2 = traiterDemandeImport(d, m, jeuImportParId, regime: regime);
      expect(v2.appliquee, isTrue, reason: 'et non un doublon refusé de ce que la mère vient d\'écrire elle-même');
      expect(v2.lot, v1.lot);
      expect(m.actives('fournisseurs'), hasLength(2));
      expect(m.toutes(collectionLots), hasLength(lots));
      expect(m.journal, hasLength(journal));
    });

    test('appliquerDemande est un NO-OP sur le lot déjà écrit par la demande (idempotence du port)', () {
      final f = fileul();
      final a = analyserFichier(jeuFournisseurs, fichier(['SOBAPS']), 'f.xlsx', f);
      final p = PortDemandeImport(f, demandeId: 'DIMX');
      final r1 = appliquerDemande(jeuFournisseurs, a, p);
      final r2 = appliquerDemande(jeuFournisseurs, a, PortDemandeImport(f, demandeId: 'DIMX'));
      expect(r1.ok && r2.ok, isTrue);
      expect(f.actives('fournisseurs'), hasLength(1));
      expect(f.toutes(collectionLots), hasLength(1));
      // et une insertion qui retombe sur une fiche de cette demande à ce rang la rend telle quelle
      final meme = PortDemandeImport(f, demandeId: 'DIMX').inserer('fournisseurs', {'code': 'ZZ', 'nom': 'ZZ'});
      expect(meme['code'], 'SOBAPS', reason: 'la fiche du rang 1 existe déjà : aucune écriture');
      expect(f.actives('fournisseurs'), hasLength(1));
    });

    test('les compteurs : la valeur d\'écriture est la valeur de DÉPART commune (jamais une variation à publier)', () {
      final f = fileul();
      final p = PortDemandeImport(f, demandeId: 'DIMC', compteurs: const {'produits': {'stockGros', 'stock'}});
      final fiche = p.inserer('produits', {'code': 'A', 'stockGros': 40, 'stock': 40, 'designation': 'A'});
      expect(fiche[champDepartCompteurs], {'stockGros': 40, 'stock': 40});
      expect(fiche['id'], 'PRO-DIMC-1');
    });
  });

  group('le fileul restitue quand la mère refuse (archivage RG-14, jamais une suppression)', () {
    Map<String, Object?> refusee(Map<String, Object?> d, String code, String motif) =>
        {...d, ...VerdictDemandeImport.refusee(code, motif, 'Corrigez.').versChamps(traitePar: 'Mère', traiteLe: '2026-11-12')};

    test('RESTITUTION : les fiches du lot sont ARCHIVÉES (motif nommé), le lot passe « restitué », le droit d\'annuler n\'est pas relu', () {
      final f = fileul();
      final d = deposer(f, ['SOBAPS', 'NSIA']).demande!;
      final r = restituerLotDirect(jeuImportParId, d['lotLocalId'], codeRefus: 'DOUBLON_MAGASIN', motifRefus: 'déjà tenue', port: f);
      expect(r.ok, isTrue);
      expect(r.archives, 2);
      expect(r.etat, restitutionFaite);
      expect(f.actives('fournisseurs'), isEmpty);
      expect(f.toutes('fournisseurs'), hasLength(2), reason: 'archivées, jamais supprimées');
      expect(f.toutes('fournisseurs').every((x) => x['statut'] == 'archive' && '${x['_motifArchivage']}'.contains('refusé par la mère')), isTrue);
      expect(f.toutes(collectionLots).single['etat'], 'restitue');
      expect(f.toutes(collectionLots).single['motifRestitution'], contains('DOUBLON_MAGASIN'));
      expect(restituerLotDirect(jeuImportParId, d['lotLocalId'], codeRefus: 'X', motifRefus: 'x', port: f).archives, 0, reason: 'idempotent : un lot restitué ne se restitue pas deux fois');
    });

    test('PIÈCE ÉMISE : une fiche sur laquelle une commande s\'appuie reste, marquée « refusée par la mère » ; le verdict dit restitution PARTIELLE', () {
      final f = fileul(jeu: {
        'commandes': [
          {'id': 'C1', 'fournisseurCode': 'SOBAPS', 'statut': 'actif'}
        ]
      });
      final d = deposer(f, ['SOBAPS', 'NSIA']).demande!;
      final r = restituerLotDirect(jeuImportParId, d['lotLocalId'], codeRefus: 'DOUBLON_MAGASIN', motifRefus: 'déjà tenue', port: f);
      expect(r.ok, isTrue);
      expect(r.etat, restitutionPartielle);
      expect(r.gardees, hasLength(1), reason: 'la dépendance du jeu est relue FICHE PAR FICHE : seul SOBAPS porte une commande');
      expect(r.archives, 1, reason: 'NSIA, que rien n\'utilise, est restituée');
      final reste = f.actives('fournisseurs').single;
      expect(reste['code'], 'SOBAPS');
      expect('${reste[champRefuseeParMere]}', contains('DOUBLON_MAGASIN'));
      expect(ficheLocaleAuPoste(reste), isTrue, reason: 'une fiche gardée reste PROPRE AU POSTE : elle ne part pas au journal');
      final libelle = libelleEtatDemandeImport({...refusee(d, 'DOUBLON_MAGASIN', 'm'), 'restitution': r.etat}).libelle;
      expect(libelle, 'Refusée par la mère, restitution partielle');
    });

    test('suite du verdict : refusée → restituer ; appliquée → lever le marquage ; une fois fait, plus rien', () {
      final d = deposer(fileul(), ['SOBAPS']).demande!;
      expect(suiteDuVerdict(d), SuiteDuVerdict.aucune, reason: 'en attente');
      expect(suiteDuVerdict(refusee(d, 'X', 'x')), SuiteDuVerdict.restituer);
      expect(suiteDuVerdict({...refusee(d, 'X', 'x'), 'restitution': restitutionFaite}), SuiteDuVerdict.aucune);
      final ok = {...d, ...const VerdictDemandeImport.appliquee(lot: 'IMP-1', ecrits: 1).versChamps(traitePar: 'Mère', traiteLe: '2026-11-12')};
      expect(suiteDuVerdict(ok), SuiteDuVerdict.leverLeMarquage);
      expect(suiteDuVerdict({...ok, 'marquageLeve': true}), SuiteDuVerdict.aucune);
    });

    test('annulation du lot : permise tant que la mère n\'a pas statué ; refusée en nommant après confirmation ou refus', () {
      final d = deposer(fileul(), ['SOBAPS']).demande!;
      expect(refusAnnulationLotDirect(d), isNull);
      expect(refusAnnulationLotDirect(null), isNull, reason: 'un lot sans demande s\'annule comme avant');
      expect(refusAnnulationLotDirect({...d, 'etat': demandeImportAppliquee, 'resultatLot': 'IMP-2026-009'})!.code, 'LOT_CONFIRME_PAR_LA_MERE');
      expect(refusAnnulationLotDirect({...d, 'etat': demandeImportRefusee})!.code, 'RESTITUTION_PAR_LA_MERE');
      expect(champsRetraitDemande(par: 'A', jour: '2026-11-12')['etat'], demandeImportRetiree);
    });

    test('les LIBELLÉS : jamais « appliquée » avant la confirmation ; chaque état se lit', () {
      final d = deposer(fileul(), ['SOBAPS']).demande!;
      expect(libelleEtatDemandeImport(d), (libelle: 'Écrit chez vous, en attente de la mère', ton: 'attention'));
      expect(libelleEtatDemandeImport({...d, 'etat': demandeImportAppliquee}).libelle, 'Appliquée par la mère');
      expect(libelleEtatDemandeImport({...d, 'etat': demandeImportRefusee}).libelle, 'Refusée par la mère, restitution en cours');
      expect(libelleEtatDemandeImport({...d, 'etat': demandeImportRefusee, 'restitution': restitutionFaite}).libelle, 'Refusée par la mère, écriture restituée');
      expect(libelleEtatDemandeImport({...d, 'etat': demandeImportRetiree}).libelle, 'Retirée par vous');
    });
  });

  group('LE GRAND STOCK chez le fileul (lot IMP-E) : identité commune, départ des compteurs, rejeu sans effet, restitution par mouvements inverses', () {
    final vecteurs = (jsonDecode(File('test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();
    final lignesGs = [
      for (final l in ((vecteurs['cas'] as List).cast<Map>().firstWhere((x) => x['id'] == 'gs-valide')['lignes'] as List)) [for (final c in (l as List)) c]
    ];
    const compteurs = {
      'produits': {'stockGros', 'stockDetail', 'stock'},
      'lots': {'quantiteRestante'},
    };
    PortImportMemoire stock({String role = 'stock', String id = 'DIMGS'}) =>
        PortImportMemoire({}, profilFixe: profilDe(base, role), utilisateurFixe: 'GESTIONNAIRE F1', prefixeId: 'F1-', jourFixe: '2026-11-13');
    ImportDirectEtDemande deposerGs(PortImportMemoire f, {String id = 'DIMGS'}) {
      final a = analyserFichier(jeuGrandStock, lignesGs, 'grand-stock.xlsx', f);
      expect(a.accepte, isTrue, reason: a.problemes.map((p) => p.motif).join(' / '));
      return importerDirectEtDemander(jeu: jeuGrandStock, analyse: a, port: f, regime: regime, idDemande: id, poste: 'F1', compteurs: compteurs);
    }

    num total(PortImportMemoire p, String code, String champ) => p.actives('produits').where((x) => x['code'] == code).fold<num>(0, (t, x) => t + ((x[champ] as num?) ?? 0));

    test('le Grand Stock passe par la demande ; chaque fiche porte sa série, son identifiant de demande et, pour un compteur, sa valeur de DÉPART', () {
      expect(regime.exigeLaMere(jeuGrandStock), isTrue);
      final f = stock();
      final r = deposerGs(f);
      expect(r.ok, isTrue, reason: '${r.refus?.code} ${r.refus?.motif}');
      final med1 = f.actives('produits').firstWhere((x) => x['code'] == 'MED1');
      expect(med1['id'], matches(RegExp(r'^PRO-DIMGS-\d$')));
      expect(med1[champSerieDemande], 'DIMGS');
      expect(med1[champEnAttenteMere], 'DIMGS');
      expect(med1[champDepartCompteurs], {'stockGros': 150, 'stockDetail': 0, 'stock': 150});
      final lot = f.actives('lots').firstWhere((x) => x['numeroLot'] == 'L1');
      expect(lot[champDepartCompteurs], {'quantiteRestante': 100});
      expect(f.actives('mouvements'), hasLength(3), reason: 'trois entrées : MED1 L1, MED1 L2, GANT1');
      expect(ficheLocaleAuPoste(med1), isTrue, reason: 'propre au poste : aucun autre poste ne voit ce stock avant la confirmation de la mère');
    });

    test('LA MÈRE applique sous les MÊMES identifiants, avec la MÊME valeur de départ : une fiche par article, 150 pour 150 importées, jamais 300', () {
      final f = stock();
      final d = deposerGs(f).demande!;
      final m = mere(profilDe(base, 'stock'));
      final v = traiterDemandeImport(d, m, jeuImportParId, regime: regime, compteurs: compteurs);
      expect(v.appliquee, isTrue, reason: '${v.code} ${v.motif}');
      expect({for (final x in m.actives('produits')) x['id']}, {for (final x in f.actives('produits')) x['id']});
      expect({for (final x in m.actives('lots')) x['id']}, {for (final x in f.actives('lots')) x['id']});
      expect({for (final x in m.actives('mouvements')) x['id']}, {for (final x in f.actives('mouvements')) x['id']});
      expect(total(m, 'MED1', 'stockGros'), 150);
      expect(total(f, 'MED1', 'stockGros'), 150);
      expect(m.actives('produits').every((x) => x[champEnAttenteMere] == null), isTrue);
      expect(m.actives('produits').firstWhere((x) => x['code'] == 'MED1')[champDepartCompteurs], {'stockGros': 150, 'stockDetail': 0, 'stock': 150}, reason: 'le départ est commun aux deux postes');
    });

    test('REJEU : appliquer la même demande une seconde fois n\'écrit rien (ni fiche, ni lot, ni ligne de journal) ; la mère qui revient rend le même verdict', () {
      final f = stock();
      final d = deposerGs(f).demande!;
      final m = mere(profilDe(base, 'stock'));
      final v1 = traiterDemandeImport(d, m, jeuImportParId, regime: regime, compteurs: compteurs);
      final journal = m.journal.length;
      final fiches = (m.toutes('produits').length, m.toutes('lots').length, m.toutes('mouvements').length, m.toutes(collectionLots).length);
      final v2 = traiterDemandeImport(d, m, jeuImportParId, regime: regime, compteurs: compteurs);
      expect(v2.appliquee, isTrue);
      expect(v2.lot, v1.lot);
      expect((m.toutes('produits').length, m.toutes('lots').length, m.toutes('mouvements').length, m.toutes(collectionLots).length), fiches);
      expect(m.journal, hasLength(journal));
      expect(total(m, 'MED1', 'stockGros'), 150, reason: 'rejoué, le stock ne double pas');
      // et chez le fileul : rejouer l'application locale est aussi sans effet
      final a = analyserFichier(jeuGrandStock, lignesGs, 'grand-stock.xlsx', f);
      expect(appliquerDemande(jeuGrandStock, a, PortDemandeImport(f, demandeId: 'DIMGS', compteurs: compteurs)).ok, isTrue);
      expect(f.actives('mouvements'), hasLength(3));
      expect(total(f, 'MED1', 'stockGros'), 150);
    });

    test('DEUX FILEULS importent le même inventaire : la mère applique la première demande, refuse la seconde en nommant ; le second restitue, il ne reste qu\'un stock', () {
      final f1 = stock(), f2 = stock();
      final d1 = deposerGs(f1, id: 'DIMGS1').demande!, d2 = deposerGs(f2, id: 'DIMGS2').demande!;
      final m = mere(profilDe(base, 'stock'));
      expect(traiterDemandeImport(d1, m, jeuImportParId, regime: regime, compteurs: compteurs).appliquee, isTrue);
      final v2 = traiterDemandeImport(d2, m, jeuImportParId, regime: regime, compteurs: compteurs);
      expect(v2.appliquee, isFalse);
      expect(v2.code, 'DOUBLON_MAGASIN');
      expect(total(m, 'MED1', 'stockGros'), 150);
      final r = restituerLotDirect(jeuImportParId, d2['lotLocalId'], codeRefus: v2.code!, motifRefus: v2.motif!, port: f2);
      expect(r.etat, restitutionFaite);
      expect(f2.actives('produits'), isEmpty);
    });

    test('RESTITUTION : rien n\'est sorti, chaque entrée est contre-passée par un mouvement inverse NOMMÉ, lots et articles sont archivés (RG-14), le stock n\'est jamais négatif', () {
      final f = stock();
      final d = deposerGs(f).demande!;
      final r = restituerLotDirect(jeuImportParId, d['lotLocalId'], codeRefus: 'DOUBLON_MAGASIN', motifRefus: 'déjà tenue', port: f);
      expect(r.ok, isTrue);
      expect(r.etat, restitutionFaite);
      expect(f.actives('produits'), isEmpty);
      expect(f.actives('lots'), isEmpty);
      expect(f.toutes('produits'), hasLength(2), reason: 'archivés, jamais supprimés');
      final inverses = f.toutes('mouvements').where((x) => x['restitutionDe'] != null).toList();
      expect(inverses, hasLength(3), reason: 'une contre-passation par entrée');
      expect(inverses.every((x) => x['type'] == 'sortie' && '${x['justificatif']}'.contains('Restitution du lot') && '${x['justificatif']}'.contains('contre-passation de')), isTrue);
      final entrees = f.toutes('mouvements').where((x) => x['type'] == 'entree');
      for (final e in entrees) {
        final somme = inverses.where((x) => x['restitutionDe'] == e['id']).fold<num>(0, (t, x) => t + (x['quantite'] as num));
        expect(somme, e['quantite'], reason: 'la quantité inverse est celle de l\'entrée, ni plus (RG-03), ni moins');
      }
      expect(ficheLocaleAuPoste(inverses.first), isTrue, reason: 'les mouvements de restitution restent propres au poste : la mère n\'a jamais tenu ce stock');
      expect(f.toutes(collectionLots).single['etat'], 'restitue');
    });

    test('UNE SORTIE DÉJÀ FAITE sur un lot importé en attente : jamais de contre-passation d\'une pièce émise ; l\'article reste « refusée par la mère » (restitution PARTIELLE) ; les autres articles sont restitués', () {
      final f = stock();
      final d = deposerGs(f).demande!;
      // une dispensation de 10 boîtes de MED1 (lot L1) : les compteurs passent sous leur valeur de départ
      final med1 = f.actives('produits').firstWhere((x) => x['code'] == 'MED1');
      final l1 = f.actives('lots').firstWhere((x) => x['produitId'] == med1['id'] && x['numeroLot'] == 'L1');
      med1['stockGros'] = 140;
      med1['stock'] = 140;
      l1['quantiteRestante'] = 90;
      final r = restituerLotDirect(jeuImportParId, d['lotLocalId'], codeRefus: 'DOUBLON_MAGASIN', motifRefus: 'déjà tenue', port: f);
      expect(r.ok, isTrue);
      expect(r.etat, restitutionPartielle);
      expect(r.gardees.map((g) => g['collection']).toSet(), {'produits', 'lots', 'mouvements'});
      expect(r.gardees.every((g) => g['code'] == 'STOCK_DEJA_SORTI'), isTrue);
      final reste = f.actives('produits').firstWhere((x) => x['code'] == 'MED1');
      expect('${reste[champRefuseeParMere]}', contains('DOUBLON_MAGASIN'), reason: 'l\'article reste marqué « refusée par la mère »');
      expect(reste['stockGros'], 140, reason: 'jamais de stock négatif ni réécrit : le stock réel reste ce qu\'il est');
      expect(f.toutes('mouvements').where((x) => x['restitutionDe'] != null && x['produitId'] == med1['id']), isEmpty, reason: 'aucune contre-passation sur l\'article déjà sorti');
      expect(f.actives('produits').where((x) => x['code'] == 'GANT1'), isEmpty, reason: 'GANT1, que rien n\'a sorti, est restitué');
      expect(r.archives, 1, reason: 'GANT1 n\'a pas de lot : seul son article est archivé (son entrée est contre-passée, non archivée)');
    });

    test('UN AUTRE MOUVEMENT sur l\'article (une perte dont le compteur n\'a pas bougé) suffit aussi à le garder', () {
      final f = stock();
      final d = deposerGs(f).demande!;
      final gant = f.actives('produits').firstWhere((x) => x['code'] == 'GANT1');
      f.inserer('mouvements', {'reference': 'M000099', 'produitId': gant['id'], 'produit': gant['designation'], 'type': 'perte', 'typeLabel': 'Perte', 'quantite': 1, 'statut': 'actif'});
      final r = restituerLotDirect(jeuImportParId, d['lotLocalId'], codeRefus: 'X', motifRefus: 'x', port: f);
      expect(r.etat, restitutionPartielle);
      expect(f.actives('produits').where((x) => x['code'] == 'GANT1'), hasLength(1));
      expect(f.actives('produits').where((x) => x['code'] == 'MED1'), isEmpty, reason: 'MED1, intact, est restitué');
    });
  });

  group('le protocole : ce qu\'un fileul falsifié n\'écrit pas', () {
    test('création : « en attente », sans verdict ; jamais d\'état traité ni de champ de verdict', () {
      expect(refusDemandeImportDuFileul('creer', {'etat': 'en_attente', 'jeu': 'assureurs', 'lignes': []}), isNull);
      expect(refusDemandeImportDuFileul('creer', {'jeu': 'assureurs'}), isNull);
      expect(refusDemandeImportDuFileul('creer', {'etat': 'appliquee'}), isNotNull);
      expect(refusDemandeImportDuFileul('creer', {'etat': 'en_attente', 'resultatCode': 'X'}), isNotNull);
      expect(refusDemandeImportDuFileul('creer', {'traitePar': 'Mère'}), isNotNull);
    });
    test('modification : ni l\'état ni le verdict ne se réécrivent ; le suivi du fileul (restitution, marquage levé) s\'écrit à côté', () {
      expect(refusDemandeImportDuFileul('modifier', {'etat': 'en_attente'}), isNotNull, reason: 'remettre en attente une demande traitée la ferait rejouer');
      expect(refusDemandeImportDuFileul('modifier', {'resultatMotif': 'ok'}), isNotNull);
      expect(refusDemandeImportDuFileul('modifier', {'fichier': 'autre.xlsx'}), isNull);
      expect(refusDemandeImportDuFileul('modifier', {'restitution': 'faite', 'restitutionArchives': 2, 'marquageLeve': true}), isNull);
    });
    test('le fileul RETIRE sa demande tant que la mère n\'a pas statué — jamais après un verdict, jamais avec un verdict', () {
      final retrait = champsRetraitDemande(par: 'A', jour: '2026-11-12');
      expect(refusDemandeImportDuFileul('modifier', retrait, etatActuel: demandeImportEnAttente), isNull);
      expect(refusDemandeImportDuFileul('modifier', retrait), isNull, reason: 'état inconnu du contrôle : le retrait reste permis, la mère ne traite plus que les demandes en attente');
      expect(refusDemandeImportDuFileul('modifier', retrait, etatActuel: demandeImportAppliquee), isNotNull, reason: 'un verdict ne se retire pas');
      expect(refusDemandeImportDuFileul('modifier', retrait, etatActuel: demandeImportRefusee), isNotNull);
      expect(refusDemandeImportDuFileul('modifier', {...retrait, 'resultatCode': 'X'}, etatActuel: demandeImportEnAttente), isNotNull);
    });
  });
}
