import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_validations_deposees.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;
import 'package:sigh_sync/sigh_sync.dart';
// ignore: implementation_imports
import 'package:sigh_sync/src/mere.dart' show Appareil, familles, collectionsFacturesTiersJamaisMobile;

import 'm9_aide.dart' show magasin;

/// LA FACTURE À UNE ENTREPRISE À TRAVERS LES POSTES (Direction de Baguidi, 17/11/2026, point 2) : `facturesTiers` et `avoirsTiers` voyagent (famille A), l'ÉMISSION reste à la mère, un fileul DÉPOSE une
/// demande (émission, avoir, transmission) que la mère applique sous le rôle de son auteur avec sa matrice, ses numéros et son avecReleve ; jamais vers un téléphone. Contre la VRAIE mère Dart : le
/// transport des ponts est son `traiter`, donc chaque refus est réel. Données fictives.
typedef M = Map<String, Object?>;

class _Liaison {
  _Liaison(this.mere);
  final Mere mere;
  bool coupee = false;
  int n = 0;
}

class _Transport implements TransportPont {
  _Transport(this.l, this.app);
  final _Liaison l;
  final Appareil app;
  @override
  Future<List<PieceSync>> liste(String c) async {
    if (l.coupee) throw StateError('mère injoignable');
    final rows = await l.mere.base.select('SELECT id,data,archive FROM fiches WHERE collection=?', [c]);
    return [for (final r in rows) PieceSync('${r['id']}', (jsonDecode(r['data'] as String) as Map).cast<String, Object?>(), archive: (r['archive'] as int) != 0)];
  }

  @override
  Future<void> ecrire(String c, String fiche, {required bool existe, required Map<String, Object?> champs}) async {
    if (l.coupee) throw StateError('mère injoignable');
    final f = await l.mere.lire(c, fiche);
    final vu = <String, Object?>{for (final k in champs.keys) if (f != null && f.fieldseq[k] != null) k: f.fieldseq[k]};
    final r = await l.mere.traiter({'id': 'op${l.n++}', 'type': existe ? 'modifier' : 'creer', 'collection': c, 'fiche': fiche, 'champs': jsonDecode(jsonEncode(champs)), 'hlc': 1000 + l.n, 'vu': vu}, app);
    if (r['statut'] == 'refusee') throw StateError('${r['code']} : ${r['motif']}');
  }

  @override
  Future<void> restaurer(String collection, String fiche) async => throw StateError('non porté');
}

void main() {
  final auj = DateTime(2031, 3, 10, 9);
  const ifu = '1201555000123';
  late List<M> situations, bareme;
  setUpAll(() {
    final jeu = magasin();
    situations = [for (final s in jeu.collection('situationsAib').toutes) {...s}];
    bareme = [
      for (final b in jeu.collection('baremeAib').toutes) {...b},
      {'id': 'BAI-T', 'statut': 'actif', 'situation': 'prestation_service', 'taux': 5, 'statutArret': 'arrete', 'arrete': true, 'aValider': false, 'dateEffet': '2026-01-01', 'dateArret': '2026-01-01', 'decideurArret': 'Direction', 'source': 'Test', 'motif': 'Test'},
    ];
  });

  Magasin poste({bool avecReleve = false}) {
    final m = Magasin({
      'assureurs': <M>[
        if (avecReleve) {'id': 'A1', 'statut': 'actif', 'code': 'AFR', 'nom': 'ASSUREUR FICTIF'}
      ],
      'factures': <M>[
        if (avecReleve)
          for (final (i, sous) in [('1', 'Employeur Alpha'), ('2', 'Employeur Alpha'), ('3', 'Employeur Beta')])
            {
              'id': 'F$i',
              'numero': 'FN-2031-0000$i',
              'statut': 'actif',
              'assureur': 'AFR',
              'souscripteur': sous,
              'montantTTC': 10000,
              'partAssurance': 8000,
              'partPatient': 2000,
              'date': '2031-03-0$i',
              'lignes': [{'id': 'L1'}]
            }
      ],
      'situationsAib': [for (final s in situations) {...s}],
      'baremeAib': [for (final b in bareme) {...b}],
      for (final n in ['facturesMere', colFacturesTiers, colAvoirsTiers, 'avoirs', 'ecritures', 'modulesActifs', 'rbac', 'utilisateurs', 'postes', 'notifications', valCollectionDepots, 'audit']) n: <M>[],
    }, 'POSTE')
      ..horloge = () => auj;
    serviceParametres(m, auteur: () => 'Poste mère').semerDefauts();
    return m;
  }

  // Le pont d'un fileul préfixe l'identifiant d'une fiche par son poste (`F1-…`) : la mère et les autres postes la lisent sous cet identifiant.
  Fiche? deposee(Magasin m, Object? id) => m.collection(valCollectionDepots).toutes.where((x) => '${x['id']}'.endsWith('$id')).firstOrNull;

  M emission({String souscripteur = 'Employeur Alpha', String ifuAcheteur = ifu}) => {
        'compagnieCode': 'AFR',
        'periode': 'mois',
        'souscripteur': souscripteur,
        'ifu': ifuAcheteur,
        'nom': 'Entreprise fictive SARL',
        'situation': 'prestation_service',
      };

  test('famille A à la mère Dart et au banc Node, pont du poste (le fileul n\'envoie rien), jamais vers un téléphone, ni dans la configuration conservée à la mise en production', () {
    for (final c in facturesTiersCollectionsSync) {
      expect(familles[c], 'A', reason: '$c : fiche d\'identité commune, la mère complète certification et cumul');
    }
    expect(collectionsActivite, containsAll(facturesTiersCollectionsSync));
    expect(collectionsDeLaMereSeule, containsAll(facturesTiersCollectionsSync), reason: 'le pont d\'un fileul ne les envoie pas : seule la mère écrit');
    expect(collectionsFacturesTiersJamaisMobile, containsAll(facturesTiersCollectionsSync));
    final dart = File('../../packages/sync_dart/lib/src/mere.dart').readAsStringSync();
    expect(dart, contains('...collectionsFacturesTiersJamaisMobile'));
    expect(dart, contains('refusEcritureFactureTiers('), reason: 'la mère refait le contrôle');
    final js = File('../../packages/sync/banc/mere.js').readAsStringSync();
    expect(js, contains("facturesTiers: 'A', avoirsTiers: 'A'"));
    final jamais = RegExp(r'const MOBILE_JAMAIS = \[([^\]]*)\]').firstMatch(js)!.group(1)!;
    for (final c in facturesTiersCollectionsSync) {
      expect(jamais, contains("'$c'"));
    }
    expect(js, contains('emission_reservee_mere'), reason: 'miroir du refus dans le banc Node');
  });

  test('la VRAIE mère Dart refuse l\'écriture d\'un fileul ou d\'un téléphone en nommant le geste ; elle accepte la sienne', () async {
    final d = Directory.systemTemp.createTempSync('ft-mere');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere = await Mere.creer(ConfigMere(port: 19596, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes'));
    var n = 0;
    Future<Map<String, Object?>> op(Appareil a, String type, String c, String fiche, Map<String, Object?> champs) =>
        mere.traiter({'id': 'op${n++}', 'type': type, 'collection': c, 'fiche': fiche, 'champs': champs, 'hlc': 1000 + n, 'vu': <String, Object?>{}}, a);
    String? code(Map<String, Object?> r) => r['statut'] == 'refusee' ? '${r['code']}' : null;
    final fileul = Appareil('F1', 'fileul'), laMere = Appareil('mere', 'mere'), mobile = Appareil('T1', 'mobile', 'soignant', 'infirmier');
    final piece = {'numero': 'FT-2031-00001', 'type': 'tiers_payeur', 'montantTTC': 12000, 'statutMecef': 'en_attente'};
    expect(code(await op(fileul, 'creer', colFacturesTiers, 'FTP1', piece)), 'emission_reservee_mere');
    expect(code(await op(mobile, 'creer', colFacturesTiers, 'FTP1', piece)), 'emission_reservee_mere');
    expect(code(await op(fileul, 'creer', colAvoirsTiers, 'AVT1', {'reference': 'AV-2031-0001', 'montant': 1})), 'emission_reservee_mere');
    expect(code(await op(laMere, 'creer', colFacturesTiers, 'FTP1', piece)), isNull);
    expect(code(await op(fileul, 'modifier', colFacturesTiers, 'FTP1', {'statutMecef': 'valide', 'numeroMecef': 'FAUX'})), 'emission_reservee_mere');
    expect(code(await op(fileul, 'modifier', colFacturesTiers, 'FTP1', {'montantAvoirs': 12000})), 'emission_reservee_mere');
    expect(code(await op(laMere, 'modifier', colFacturesTiers, 'FTP1', {'statutMecef': 'valide', 'numeroMecef': 'CC300-1'})), isNull, reason: 'la certification est écrite par la mère');
    expect((await mere.lire(colFacturesTiers, 'FTP1'))!.data['numeroMecef'], 'CC300-1');
    // La demande, elle, est une fiche ordinaire de `validationsDeposees` : acceptée d'un fileul.
    expect(code(await op(fileul, 'creer', valCollectionDepots, 'VDP-1', {'genre': valGenreFactureTiers, 'action': 'emettre', 'etat': 'deposee'})), isNull);
  });

  test('deux fileuls et la mère : émission, avoir et transmission DEMANDÉS depuis un fileul, appliqués par la mère sous le rôle de l\'auteur ; verdicts nommés ; mère coupée ; aucun doublon', () async {
    final d = Directory.systemTemp.createTempSync('ft-pont');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere = await Mere.creer(ConfigMere(port: 19597, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauvegardes'));
    final liaison = _Liaison(mere);
    final f1 = poste(), f2 = poste(), mm = poste(avecReleve: true);
    final p1 = PontActivite(f1, _Transport(liaison, Appareil('F1', 'fileul')), etiquette: 'F1', enLectureSeule: collectionsDeLaMereSeule, reservesAuMere: true);
    final p2 = PontActivite(f2, _Transport(liaison, Appareil('F2', 'fileul')), etiquette: 'F2', enLectureSeule: collectionsDeLaMereSeule, reservesAuMere: true);
    final pm = PontActivite(mm, _Transport(liaison, Appareil('mere', 'mere')), etiquette: 'M');
    Future<void> tour() async {
      for (var i = 0; i < 3; i++) {
        for (final p in [p1, p2, pm]) {
          await p.cycle();
        }
      }
    }

    final s1 = ServiceValidationsDeposees.de(f1)..etiquette = 'F1';
    final s2 = ServiceValidationsDeposees.de(f2)..etiquette = 'F2';
    final sm = ServiceValidationsDeposees.de(mm)
      ..etiquette = 'M'
      ..exigerCompteInscrit = false;

    // 1. Refus nommés DÈS LE POSTE, rien de déposé : geste, IFU, avecReleve.
    expect(s1.deposerFactureTiers(factureTiersActionEmettre, emission(), role: 'caissier', acteur: 'Agent Fileul').refus!.code, 'TIERS_PAYEUR_RESERVE');
    expect(s1.deposerFactureTiers(factureTiersActionEmettre, emission(ifuAcheteur: ''), role: 'comptable', acteur: 'Agent Fileul').refus!.code, 'IFU_ACHETEUR_REQUIS');
    expect(f1.collection(valCollectionDepots).toutes, isEmpty);

    // 2. F1 : la demande d'ÉMISSION (avecReleve : Employeur Alpha, 16 000 F sur deux factures patients). La mère l'applique sous le rôle ET le nom de l'auteur.
    final dep = s1.deposerFactureTiers(factureTiersActionEmettre, emission(), role: 'comptable', acteur: 'Agent Fileul');
    expect(dep.ok, isTrue, reason: '${dep.refus?.code} ${dep.refus?.motif}');
    expect(s1.deposerFactureTiers(factureTiersActionEmettre, emission(), role: 'comptable', acteur: 'Agent Fileul').dejaDepose, isTrue, reason: 'une demande identique en attente n\'est pas doublée');
    expect(s1.depotFactureTiersAttendu(factureTiersActionEmettre, 'AFR|mois|Employeur Alpha'), isNotNull, reason: '« transmise à la mère, en attente »');
    expect(f1.collection(colFacturesTiers).toutes, isEmpty, reason: 'rien n\'est écrit sur le fileul : l\'émission est à la mère');
    await tour();
    expect(mm.collection(valCollectionDepots).toutes.single['genre'], valGenreFactureTiers);
    expect(sm.traiter(), 1);
    final piece = mm.collection(colFacturesTiers).toutes.single;
    expect(piece['numero'], 'FT-2031-00001');
    expect([piece['acheteurIfu'], piece['acheteurNom'], piece['aibSituation'], piece['aibTaux']], [ifu, 'Entreprise fictive SARL', 'prestation_service', 5]);
    expect(piece['montantTTC'], 16000, reason: 'la part prise en charge de la ligne du avecReleve, rejouée par la mère avec SES factures');
    expect(piece['emisePar'], 'Agent Fileul', reason: 'la mère signe sous le nom de l\'auteur du geste');
    expect(piece['demandeDepotId'], deposee(mm, dep.fiche!['id'])!['id'], reason: 'la pièce porte la trace de la demande qui l\'a fait naître');
    expect(piece['statutMecef'], 'en_attente', reason: 'aucun appareil : le circuit MECeF le dit, aucun numéro fabriqué');
    expect(mm.collection(valCollectionDepots).toutes.single['etat'], valDepotAppliquee);
    expect(mm.collection(valCollectionDepots).toutes.single['resultatReference'], 'FT-2031-00001');
    expect(mm.collection('audit').toutes.any((x) => x['action'] == 'Facture à une entreprise émise'), isTrue, reason: 'RG-12');
    await tour();
    for (final m in [f1, f2]) {
      final v = m.collection(colFacturesTiers).toutes.single;
      expect([v['numero'], v['montantTTC'], v['acheteurNom']], ['FT-2031-00001', 16000, 'Entreprise fictive SARL'], reason: 'la pièce de la mère est LUE par les deux fileuls');
    }
    expect(f1.collection(valCollectionDepots).toutes.single['etat'], valDepotAppliquee);
    expect(s1.depotFactureTiersAttendu(factureTiersActionEmettre, 'AFR|mois|Employeur Alpha'), isNull, reason: 'appliquée : plus rien à dire, la pièce parle');
    expect(s1.reconcilier(), 1);
    final notif = f1.collection('notifications').toutes.single;
    expect(notif['libelle'], 'Demande appliquée par la mère');
    expect(notif['detail'], contains('FT-2031-00001'));
    expect(sm.traiter(), 0, reason: 'un dépôt traité n\'est jamais rejoué');

    // F2 travaille un peu plus tard : le dernier dépôt d'une cible se lit à la date du geste.
    f2.horloge = () => auj.add(const Duration(minutes: 5));
    // 3. F2 : la MÊME ligne ne se réclame pas deux fois : refus NOMMÉ de la mère, qui revient au fileul avec son motif.
    final bis = s2.deposerFactureTiers(factureTiersActionEmettre, emission(), role: 'comptable', acteur: 'Autre Agent');
    expect(bis.ok, isTrue, reason: 'le fileul ne voit pas encore le avecReleve de la mère : le refus est celui de la mère');
    await tour();
    expect(sm.traiter(), 1);
    await tour();
    final refuse = deposee(f2, bis.fiche!['id'])!;
    expect([refuse['etat'], refuse['resultatCode']], [valDepotRefusee, anyOf('RELEVE_VIDE', 'FILLE_DEJA_FACTUREE')]);
    expect('${refuse['resultatMotif']}', isNotEmpty);
    expect(mm.collection(colFacturesTiers).toutes, hasLength(1), reason: 'un refus n\'écrit rien');
    expect(s2.depotFactureTiersAttendu(factureTiersActionEmettre, 'AFR|mois|Employeur Alpha')!['etat'], valDepotRefusee, reason: 'le motif nommé revient à l\'auteur');
    expect(s2.reconcilier(), 1);
    expect(f2.collection('notifications').toutes.single['libelle'], 'Demande refusée par la mère');

    // 4. Un rôle sans le geste qui contournerait le poste (fiche écrite à la main) : la mère REFAIT le contrôle avec SA matrice.
    f2.collection(valCollectionDepots).ajouterSansJournal({
      'id': 'VDP-FRAUDE',
      'statut': 'actif',
      'genre': valGenreFactureTiers,
      'famille': valGenreFactureTiers,
      'action': factureTiersActionEmettre,
      'cible': 'AFR|mois|Employeur Beta',
      'libelle': 'Émission',
      'etat': valDepotDeposee,
      'demandeRole': 'caissier',
      'demandePar': 'Caissier Fictif',
      'demandePoste': 'F2',
      'demandeLe': '2031-03-10T09:00:00.000Z',
      'charge': emission(souscripteur: 'Employeur Beta'),
    });
    await tour();
    expect(sm.traiter(), 1);
    expect(deposee(mm, 'VDP-FRAUDE')!['resultatCode'], 'TIERS_PAYEUR_RESERVE');
    expect(mm.collection(colFacturesTiers).toutes, hasLength(1));

    // 5. F2 : l'AVOIR d'une pièce émise ailleurs : ligne nommée, plafond cumulé, contre-passation équilibrée à la mère, cumul porté par la pièce, avoir lu partout.
    await tour();
    final id = f2.collection(colFacturesTiers).toutes.single['id'];
    final av = s2.deposerFactureTiers(factureTiersActionAvoir, {'factureId': id, 'motif': 'Erreur de période', 'montant': 6000}, role: 'da', acteur: 'Autre Agent', facture: f2.collection(colFacturesTiers).parId(id));
    expect(av.ok, isTrue, reason: '${av.refus?.code}');
    expect(s2.deposerFactureTiers(factureTiersActionAvoir, {'factureId': id, 'motif': ''}, role: 'da', acteur: 'Autre Agent', facture: f2.collection(colFacturesTiers).parId(id)).refus!.code, 'MOTIF_AVOIR_REQUIS');
    await tour();
    expect(sm.traiter(), 1);
    final avoir = mm.collection(colAvoirsTiers).toutes.single;
    expect([avoir['montant'], avoir['factureNumero'], avoir['emisPar']], [6000, 'FT-2031-00001', 'Autre Agent']);
    expect(avoir['reference'], matches(RegExp(r'^AV-2031-\d{4}$')));
    expect(mm.collection(colFacturesTiers).toutes.single['montantAvoirs'], 6000);
    final ecr = [for (final e in mm.collection('ecritures').toutes) if (e['pieceNumero'] == avoir['reference']) e];
    expect(ecr, hasLength(2));
    expect(ecr.fold<num>(0, (s, e) => s + (e['debit'] as num)), ecr.fold<num>(0, (s, e) => s + (e['credit'] as num)), reason: 'RG-10');
    await tour();
    for (final m in [f1, f2]) {
      expect(m.collection(colAvoirsTiers).toutes.single['montant'], 6000, reason: 'l\'avoir de la mère arrive aux deux fileuls');
      expect(m.collection(colFacturesTiers).toutes.single['montantAvoirs'], 6000);
    }
    // Un second avoir qui dépasserait le plafond cumulé : refus NOMMÉ de la mère, rien d'écrit.
    final trop = s1.deposerFactureTiers(factureTiersActionAvoir, {'factureId': id, 'motif': 'Excès', 'montant': 11000}, role: 'comptable', acteur: 'Agent Fileul', facture: f1.collection(colFacturesTiers).parId(id));
    expect(trop.ok, isTrue);
    await tour();
    expect(sm.traiter(), 1);
    expect(deposee(mm, trop.fiche!['id'])!['resultatCode'], 'AVOIR_REFUSE');
    expect(mm.collection(colAvoirsTiers).toutes, hasLength(1));

    // 6. La TRANSMISSION demandée : le détenteur du geste d'émission transmet sa pièce ; sans appareil, elle reste en attente, l'attente est NOMMÉE.
    final tr = s1.deposerFactureTiers(factureTiersActionTransmettre, {'factureId': id}, role: 'comptable', acteur: 'Agent Fileul', facture: f1.collection(colFacturesTiers).parId(id));
    expect(tr.ok, isTrue, reason: '${tr.refus?.code}');
    await tour();
    expect(sm.traiter(), 1);
    final apresTr = mm.collection(colFacturesTiers).toutes.single;
    expect([apresTr['statutMecef'], apresTr['codeRetour']], ['en_attente', mecefCodeNonConfigure]);
    expect(apresTr['numeroMecef'], isNull);
    expect(deposee(mm, tr.fiche!['id'])!['resultatCode'], mecefCodeNonConfigure);

    // 7. Mère COUPÉE : F2 dépose pendant la coupure ; rétablie, la demande arrive, sans doublon.
    liaison.coupee = true;
    final pendant = s2.deposerFactureTiers(factureTiersActionTransmettre, {'factureId': id}, role: 'da', acteur: 'Autre Agent', facture: f2.collection(colFacturesTiers).parId(id));
    expect(pendant.ok, isTrue);
    await tour();
    expect(p2.erreur.value, isNotNull, reason: 'mère coupée : le poste le dit, il continue de travailler');
    liaison.coupee = false;
    await tour();
    await tour();
    expect(mm.collection(valCollectionDepots).toutes.where((x) => '${x['id']}'.endsWith('${pendant.fiche!['id']}')), hasLength(1));
    expect(sm.traiter(), 1);

    // 8. Rejeu : tourner encore ne change rien ; la mère n'a refusé aucune écriture légitime.
    await tour();
    final avant = [f1, f2, mm].map((m) => [m.collection(colFacturesTiers).toutes.length, m.collection(colAvoirsTiers).toutes.length, m.collection(valCollectionDepots).toutes.length]).toList();
    await tour();
    await tour();
    expect([f1, f2, mm].map((m) => [m.collection(colFacturesTiers).toutes.length, m.collection(colAvoirsTiers).toutes.length, m.collection(valCollectionDepots).toutes.length]).toList(), avant);
    for (final p in [p1, p2, pm]) {
      expect(p.motifsRefus, isEmpty, reason: 'aucune écriture refusée par la mère : ${p.motifsRefus}');
    }
    // Les deux collections n'ont jamais voyagé d'un fileul vers la mère : tout vient de la mère.
    expect(f1.collection(colFacturesTiers).toutes.single['numero'], 'FT-2031-00001');
  });
}
