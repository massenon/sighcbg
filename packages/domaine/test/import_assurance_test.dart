// T13 : les DEUX JEUX D'IMPORT de l'assurance (garanties datées, couvertures datées). Par jeu : classement (configuration de la mère → demande ; données de patients → restreint, jamais
// de demande), vérification sans écriture, refus nommés, écriture par la fabrique de l'écran, version remplacée intacte, annulation par archivage refusée sous une pièce émise ou sous une
// version plus récente, restitution de la fin d'une couverture et de la fiche du dossier.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef Fiche = Map<String, Object?>;

List<List<Object?>> fich(JeuImport j, List<Map<String, Object?>> lignes) => [
      [for (final c in j.colonnes) c.label],
      for (final l in lignes) [for (final c in j.colonnes) l[c.cle] ?? ''],
    ];

PortImportMemoire magasin({List<Fiche> factures = const [], String jour = '2026-11-14'}) => PortImportMemoire({
      'assureurs': [
        {'id': 'AS1', 'code': 'ASS1', 'nom': 'Compagnie un', 'statut': 'actif'},
        {'id': 'AS2', 'code': 'ASS2', 'nom': 'Compagnie deux', 'statut': 'actif'},
      ],
      'souscripteurs': [
        {'id': 'S1', 'nom': 'Employeur un', 'assureur': 'ASS1', 'police': 'POL/1', 'categorie': 'entreprise', 'statut': 'actif'},
        {'id': 'S2', 'nom': 'Employeur deux', 'assureur': 'ASS2', 'police': 'POL/2', 'categorie': 'particulier', 'statut': 'actif'},
      ],
      'garanties': [
        {'id': 'G1', 'souscripteurId': 'S1', 'assureur': 'ASS1', 'libelle': 'Consultation généraliste', 'categorie': 'consultation', 'taux': 80, 'plafond': 5000, 'unitePlafond': 'acte', 'version': 1, 'statut': 'actif'},
        {'id': 'G2', 'souscripteurId': 'S1', 'assureur': 'ASS1', 'libelle': 'Analyses', 'categorie': 'analyse', 'taux': 70, 'plafond': null, 'version': 1, 'statut': 'actif'},
      ],
      'patients': [
        {'id': 'P1', 'code': 'CBG/1/26', 'nom': 'DUPONT', 'prenom': 'Aline', 'assureur': 'ASS1', 'assureurNom': 'Compagnie un', 'numeroPolice': 'POL/1', 'souscripteurId': 'S1', 'categorieAssurance': 'entreprise', 'tauxPriseEnCharge': 80, 'carteExpiration': '2027-12-31', 'statut': 'actif'},
        {'id': 'P2', 'code': 'CBG/2/26', 'nom': 'DURAND', 'prenom': 'Paul', 'statut': 'actif'},
      ],
      'couverturesAssurance': <Object?>[],
      'factures': factures,
    }, jourFixe: jour);

const _ga = {'police': 'POL/1', 'categorie': 'Consultations', 'garantie': 'Consultation généraliste', 'taux': 60, 'plafond': 4000, 'unite': 'par acte', 'dateEffet': '2026-12-01', 'motif': 'Avenant'};
const _cv = {'patient': 'CBG/2/26', 'assureur': 'ASS2', 'police': 'POL/2', 'dateEffet': '2026-12-01', 'motif': 'Changement d’employeur', 'carteExpiration': '2027-12-31', 'taux': 70};

void main() {
  group('classement', () {
    final deLaMere = {...cfbEssentielles, 'utilisateurs', valCollectionValidations, parCollectionParametres}.difference({'rolesBase', 'modulesManifeste', 'reglages', 'audit'});
    final regime = RegimeDemandesImport(collectionsDeLaMere: deLaMere);
    test('les garanties : direct et demande (configuration de la mère) ; les couvertures : restreintes, direct seul, jamais de demande', () {
      expect(regime.exigeLaMere(jeuGaranties), isTrue);
      expect(jeuGaranties.restreint, isFalse);
      expect(jeuCouverturesAssurance.restreint, isTrue);
      expect(regime.exigeLaMere(jeuCouverturesAssurance), isFalse);
      expect(regime.reserveALaMere(jeuCouverturesAssurance), isFalse, reason: 'écrit à n’importe quel poste : la couverture suit le dossier du patient');
      expect(jeuGaranties.ignorable || jeuCouverturesAssurance.ignorable, isFalse);
      expect(jeuImportParId('garanties'), same(jeuGaranties));
      expect(jeuImportParEcran('imp-couvertures-assurance'), same(jeuCouverturesAssurance));
    });
    test('les deux écrans sont au manifeste', () {
      final ids = {for (final e in (jsonDecode(File('../referentiels/data/manifeste.json').readAsStringSync()) as Map)['ecrans'] as List) (e as Map)['id']};
      expect(ids, containsAll(['imp-garanties', 'imp-couvertures-assurance']));
    });
  });

  group('garanties', () {
    test('une version datée : vérifiée sans rien écrire, puis écrite comme version 2 ; la version remplacée reste intacte ; la pièce ancienne garde son taux', () {
      final port = magasin();
      final j = jeuGaranties;
      final a = analyserLignes(j, fich(j, [_ga]), 'g.xlsx', port);
      expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code} ${p.motif}']}');
      expect(a.problemes.map((p) => p.code), contains('VARIATION'), reason: 'la variation est dite à la vérification');
      expect(port.toutes('garanties'), hasLength(2));
      final r = appliquer(j, a, port);
      expect(r.ok, isTrue, reason: '${r.motif}');
      expect(port.toutes('garanties'), hasLength(3));
      final v2 = port.toutes('garanties').firstWhere((g) => g['dateEffet'] == '2026-12-01');
      expect(v2['version'], 2);
      expect(v2['taux'], 60);
      expect(v2['lotImport'], isNotNull);
      expect(port.parId('garanties', 'G1')!['taux'], 80, reason: 'la version remplacée n’est jamais réécrite');
      final p = port.parId('patients', 'P1')!;
      Repartition rep(String d) => repartir(
          patient: p,
          lignes: [
            {'libelle': 'Consultation généraliste', 'categorie': 'consultation', 'montant': 10000}
          ],
          date: d,
          souscripteurs: port.actives('souscripteurs'),
          garanties: port.actives('garanties'));
      expect(rep('2026-11-30').partAssureur, 5000, reason: 'la pièce de novembre garde 80 % plafonné à 5 000');
      expect(rep('2026-12-01').partAssureur, 4000, reason: '60 % de 10 000 = 6 000, plafonné à 4 000');
    });

    test('refus nommés : police inconnue, taux hors bornes, date absente, catégorie hors liste, deux versions dans un fichier, version dans le passé', () {
      final j = jeuGaranties;
      String code(Map<String, Object?> m, {List<Map<String, Object?>>? plus, PortImportMemoire? p}) {
        final a = analyserLignes(j, fich(j, [if (plus == null) {..._ga, ...m} else ...plus]), 'g.xlsx', p ?? magasin());
        return [for (final x in a.problemes) if (x.niveau == importRefus) x.code].join(',');
      }
      expect(code({'police': 'ZZZ'}), 'SOUSCRIPTEUR_INCONNU');
      expect(code({'taux': 120}), contains('HORS_BORNES'));
      expect(code({'dateEffet': ''}), 'CHAMP_OBLIGATOIRE');
      expect(code({'categorie': 'Inconnue'}), isNotEmpty);
      expect(code({}, plus: [_ga, {..._ga, 'dateEffet': '2027-01-01', 'taux': 50}]), contains('UNE_VERSION_PAR_GARANTIE'));
      final p = magasin();
      appliquer(j, analyserLignes(j, fich(j, [_ga]), 'g.xlsx', p), p);
      expect(code({'dateEffet': '2026-11-20', 'taux': 55}, p: p), 'VERSION_ANTERIEURE');
    });

    test('une garantie inchangée à la date n’écrit rien : la ligne est comptée', () {
      final j = jeuGaranties;
      final port = magasin();
      final a = analyserLignes(j, fich(j, [{..._ga, 'taux': 80, 'plafond': 5000}]), 'g.xlsx', port);
      expect(a.accepte, isTrue);
      expect(a.aEcrire, 0);
      expect(a.ignorees, [2]);
    });

    test('une date d’effet qu’une facture émise a déjà dépassée est refusée en nommant la pièce', () {
      final port = magasin(factures: [
        {'id': 'F1', 'numero': 'F-2026-9', 'date': '2026-12-05', 'assureur': 'ASS1', 'patientId': 'P1', 'statut': 'actif'}
      ]);
      final j = jeuGaranties;
      final a = analyserLignes(j, fich(j, [_ga]), 'g.xlsx', port);
      expect(a.accepte, isFalse);
      final p = a.problemes.firstWhere((x) => x.code == 'FACTURE_DEJA_EMISE');
      expect(p.motif, contains('F-2026-9'));
    });

    test('annulation du lot : la version s’archive ; refusée sous une version plus récente ou sous une facture émise depuis', () {
      final j = jeuGaranties;
      final port = magasin();
      final r = appliquer(j, analyserLignes(j, fich(j, [_ga]), 'g.xlsx', port), port);
      final lot = r.lot!;
      // 1. une version plus récente posée par un autre lot
      final r2 = appliquer(j, analyserLignes(j, fich(j, [{..._ga, 'dateEffet': '2027-03-01', 'taux': 50}]), 'g2.xlsx', port), port);
      expect(r2.ok, isTrue);
      final refus = annulerLot(jeuImportParId, lot['id'], 'test', port);
      expect(refus.ok, isFalse);
      expect(refus.code, 'VERSION_POSTERIEURE');
      // 2. on annule d'abord la plus récente, puis la première
      expect(annulerLot(jeuImportParId, r2.lot!['id'], null, port).ok, isTrue);
      // 3. une facture émise sous la version 2 : refus
      port.toutes('factures').add({'id': 'F2', 'numero': 'F-X', 'date': '2026-12-10', 'assureur': 'ASS1', 'patientId': 'P1', 'statut': 'actif'});
      final sous = annulerLot(jeuImportParId, lot['id'], null, port);
      expect(sous.code, 'GARANTIE_UTILISEE');
      port.toutes('factures').clear();
      final ok = annulerLot(jeuImportParId, lot['id'], null, port);
      expect(ok.ok, isTrue, reason: '${ok.motif}');
      expect(port.actives('garanties').map((g) => g['id']).toSet(), {'G1', 'G2'}, reason: 'la série retrouve sa seule version d’origine');
    });
  });

  group('couvertures', () {
    test('un changement de couverture : l’assuré sans historique reprend sa couverture du dossier close la veille, la neuve prend effet, le dossier suit la couverture en force aujourd’hui', () {
      final j = jeuCouverturesAssurance;
      final port = magasin();
      final a = analyserLignes(j, fich(j, [
        {..._cv, 'patient': 'CBG/1/26', 'assureur': 'ASS2', 'police': 'POL/2', 'dateEffet': '2026-11-01'}
      ]), 'c.xlsx', port);
      expect(a.accepte, isTrue, reason: '${[for (final p in a.problemes) '${p.code} ${p.motif}']}');
      expect(port.toutes('couverturesAssurance'), isEmpty);
      final r = appliquer(j, a, port);
      expect(r.ok, isTrue, reason: '${r.motif}');
      final cs = port.toutes('couverturesAssurance');
      expect(cs, hasLength(2), reason: 'la couverture reprise du dossier et la neuve');
      final reprise = cs.firstWhere((c) => c['debut'] == null);
      expect(reprise['fin'], '2026-10-31');
      expect(reprise['souscripteurId'], 'S1');
      final neuve = cs.firstWhere((c) => c['debut'] == '2026-11-01');
      expect(neuve['souscripteurId'], 'S2');
      final p = port.parId('patients', 'P1')!;
      expect(p['souscripteurId'], 'S2', reason: 'la date d’effet est passée (1er novembre) : le dossier suit');
      expect(p['souscripteur'], 'Employeur deux', reason: 'le nom du souscripteur suit son identifiant');
    });

    test('annulation : la fin de la couverture reprend sa valeur d’avant, le dossier retrouve son état, rien n’est supprimé', () {
      final j = jeuCouverturesAssurance;
      final port = magasin();
      // un assuré qui a déjà un historique ouvert
      port.toutes('couverturesAssurance').add({'id': 'C0', 'patientId': 'P2', 'assureur': 'ASS1', 'souscripteurId': 'S1', 'debut': '2026-01-01', 'fin': null, 'statut': 'actif'});
      final avant = {...port.parId('patients', 'P2')!};
      final r = appliquer(j, analyserLignes(j, fich(j, [_cv]), 'c.xlsx', port), port);
      expect(r.ok, isTrue, reason: '${r.motif}');
      expect(port.parId('couverturesAssurance', 'C0')!['fin'], '2026-11-30');
      final lot = port.toutes(collectionLots).firstWhere((l) => l['reference'] == r.lot!['reference']);
      expect(lot['restaurations'], isNotEmpty);
      final an = annulerLot(jeuImportParId, lot['id'], 'erreur de saisie', port);
      expect(an.ok, isTrue, reason: '${an.motif}');
      expect(port.parId('couverturesAssurance', 'C0')!['fin'], isNull, reason: 'la précédente reprend sa fin');
      expect(port.actives('couverturesAssurance').map((c) => c['id']), ['C0']);
      expect(port.toutes('couverturesAssurance'), hasLength(2), reason: 'la neuve est archivée, jamais supprimée');
      final apres = port.parId('patients', 'P2')!;
      for (final k in ['assureur', 'souscripteurId', 'numeroPolice', 'carteExpiration']) {
        expect(apres[k], avant[k], reason: k);
      }
    });

    test('refus nommés : patient ou police inconnus, police d’une autre compagnie, date d’effet non postérieure au début en cours ; le motif est obligatoire', () {
      final j = jeuCouverturesAssurance;
      String refus(Map<String, Object?> m, {PortImportMemoire? p}) {
        final a = analyserLignes(j, fich(j, [{..._cv, ...m}]), 'c.xlsx', p ?? magasin());
        return [for (final x in a.problemes) if (x.niveau == importRefus) x.code].join(',');
      }
      expect(refus({'patient': 'CBG/9/26'}), 'PATIENT_INCONNU');
      expect(refus({'police': 'NOPE'}), 'POLICE_INCONNUE');
      expect(refus({'assureur': 'ASS1'}), 'POLICE_AUTRE_COMPAGNIE');
      expect(refus({'motif': ''}), 'CHAMP_OBLIGATOIRE');
      final p = magasin();
      p.toutes('couverturesAssurance').add({'id': 'C0', 'patientId': 'P2', 'debut': '2026-12-01', 'fin': null, 'statut': 'actif'});
      expect(refus({}, p: p), 'DATE_EFFET_ANTERIEURE');
    });

    test('une carte sans expiration est dite (RG-09) ; une facture à partir de la date d’effet est signalée, jamais réécrite', () {
      final j = jeuCouverturesAssurance;
      final port = magasin(factures: [
        {'id': 'F1', 'numero': 'F1', 'date': '2026-12-05', 'patientId': 'P2', 'statut': 'actif'}
      ]);
      final a = analyserLignes(j, fich(j, [{..._cv, 'carteExpiration': ''}]), 'c.xlsx', port);
      expect(a.accepte, isTrue);
      expect(a.problemes.map((p) => p.code), containsAll(['CARTE_SANS_EXPIRATION', 'FACTURE_DEJA_EMISE']));
    });

    test('l’annulation est refusée sous une couverture plus récente posée depuis, et sous une facture émise sous la couverture', () {
      final j = jeuCouverturesAssurance;
      final port = magasin();
      final r = appliquer(j, analyserLignes(j, fich(j, [_cv]), 'c.xlsx', port), port);
      expect(r.ok, isTrue);
      final plusTard = appliquer(j, analyserLignes(j, fich(j, [{..._cv, 'dateEffet': '2027-06-01', 'assureur': 'ASS1', 'police': 'POL/1'}]), 'c2.xlsx', port), port);
      expect(plusTard.ok, isTrue, reason: '${plusTard.motif}');
      expect(annulerLot(jeuImportParId, r.lot!['id'], null, port).code, 'COUVERTURE_POSTERIEURE');
    });

    test('un lot dont une ligne échoue à l’écriture est défait en entier : la fin d’une couverture reprend sa valeur', () {
      final j = jeuCouverturesAssurance;
      final port = magasin();
      port.toutes('couverturesAssurance').add({'id': 'C0', 'patientId': 'P2', 'assureur': 'ASS1', 'souscripteurId': 'S1', 'debut': '2026-01-01', 'fin': null, 'statut': 'actif'});
      final a = analyserLignes(j, fich(j, [_cv]), 'c.xlsx', port);
      expect(a.accepte, isTrue);
      // le magasin refuse l'écriture du dossier du patient (garde) : tout est défait
      port.gardes['couverturesAssurance'] = (op, f) => f['debut'] == '2026-12-01' ? 'garde de test' : null;
      final r = appliquer(j, a, port);
      expect(r.ok, isFalse);
      expect(r.code, 'ECRITURE_REFUSEE');
      expect(port.parId('couverturesAssurance', 'C0')!['fin'], isNull);
    });
  });
}
