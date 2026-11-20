// Le référentiel de prix unique de Baguidi (lot TAR) : le moteur est celui de la clinique sœur (écart E2575), rejoué ici sur un monde SYNTHÉTIQUE de prestations (codes et prix
// de test, aucun tarif d'une autre clinique) : résolution à la date de la pièce, versions immuables, proposition qui ne change rien avant le Oui, date passée refusée ou permise
// selon le GESTE de la matrice (aucun nom de rôle dans le moteur) et le motif, ligne impayée figée à la prescription, pro-forma, migration sans changer un franc.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

const jour = '2026-11-14';

String plus(int n) => tarIso(DateTime.parse('${jour}T12:00:00').add(Duration(days: n)));

F prestation(String code, {String famille = 'ACTE'}) => {'id': code, 'code': code, 'codeActe': code, 'libelle': 'Prestation $code', 'famille': famille, 'statut': 'actif'};
F version1(String code, num prix, {String etat = 'unique'}) => {
      'id': '$code@origine@1',
      'code': code,
      'version': 1,
      'prixNonAssure': prix,
      if (etat != 'manquant') 'prixAssure': prix,
      'etatAssure': etat,
      'origine': 'migration',
      'statut': 'valide',
    };

/// Un monde : le référentiel, les pièces émises et les gestes d'une matrice SANS fiche (l'origine des gestes réservés).
class Monde {
  Monde(List<F> tarifs, List<F> versions, {List<F> fiches = const []})
      : tarifs = [for (final t in tarifs) {...t}],
        versions = [for (final v in versions) {...v}],
        gestes = DroitsGestes(fiches: fiches);
  final List<F> tarifs, versions;
  final List<F> factures = [];
  final DroitsGestes gestes;

  ReferentielTarifs get h => ReferentielTarifs(tarifs, versions);

  /// Le contexte d'un agent de [role] : proposer = éditer l'écran (donné), décider et dater dans le passé = les DEUX gestes réservés de la matrice.
  ContexteTarif cx(String role, {bool editer = true, bool fileul = false, String? nom}) => ContexteTarif(
        referentiel: h,
        aujourdhui: jour,
        role: role,
        auteur: nom ?? 'Agent $role',
        peutEditerEcran: editer,
        peutDecider: gestes.peut(role, gesteDeciderPrix),
        peutDatePassee: gestes.peut(role, gesteDaterPrixPasse),
        profilsDatePassee: [for (final r in gestes.rolesAvec(gesteDaterPrixPasse, const ['admin', 'da', 'direction'])) r],
        fileul: fileul,
        pieces: PiecesTarif(factures: factures),
      );

  ResultatTarif<PropositionTarif> proposer(String role, DemandeProposition d, {bool editer = true}) {
    final r = tarProposer(cx(role, editer: editer), d);
    if (r.ok) {
      final p = r.valeur!;
      if (p.identite != null) tarifs.add(p.identite!);
      versions.add(p.version);
    }
    return r;
  }

  ResultatTarif<DecisionTarif> decider(String role, String id, String decision, {String? motif, String? date}) {
    final r = tarDecider(cx(role), id, decision, motif: motif, dateEffet: date);
    if (r.ok) {
      final i = versions.indexWhere((v) => v['id'] == r.valeur!.versionId);
      versions[i] = {...versions[i], ...r.valeur!.patch};
    }
    return r;
  }

  void piece(String numero, String code, String date, {bool proforma = false}) => factures.add({
        'id': numero,
        'numero': numero,
        'date': date,
        'statut': 'actif',
        if (proforma) 'proforma': true,
        'lignes': [
          {'id': 'L001', 'acteCode': code, 'prixUnitaire': 1000, 'quantite': 1}
        ],
      });

  num na(String code, [String? date]) => h.aLaDate(code, date, false, aujourdhui: jour).montant!;
}

DemandeProposition prop(String code, Object? na, {String? date, bool passee = false, bool valider = false}) =>
    DemandeProposition(code: code, prixNonAssure: na, etatAssure: 'unique', dateEffet: date, motif: 'Test TAR', datePassee: passee, valider: valider);

Monde monde() => Monde([for (final c in ['MG01', 'MG02', 'MG03', 'MG04', 'SO17']) prestation(c)], [version1('MG01', 5000), version1('MG02', 8000), version1('MG03', 10000), version1('MG04', 30000), version1('SO17', 7000)]);

void main() {
  group('vigueur à la date de la PIÈCE', () {
    test('une version à venir ne change rien avant sa date : la veille l\'ancien prix, le jour dit le nouveau', () {
      final m = monde();
      final p = m.proposer('da', prop('MG01', 5500, date: plus(3), valider: true));
      expect(p.ok, isTrue, reason: '${p.refus?.motif}');
      expect(m.na('MG01'), 5000, reason: 'aujourd\'hui : l\'ancien prix');
      expect(m.na('MG01', plus(2)), 5000, reason: 'la veille de la date d\'effet');
      expect(m.na('MG01', plus(3)), 5500, reason: 'le jour dit');
      expect(m.na('MG01', '2026-11-01'), 5000, reason: 'une pièce ancienne garde son prix');
    });

    test('une proposition non décidée, refusée ou retirée n\'est JAMAIS lue', () {
      final m = monde();
      final p = m.proposer('caissier', prop('MG02', 9999, date: plus(2)));
      expect(p.ok, isTrue);
      expect(m.na('MG02', plus(5)), 8000, reason: 'proposée : jamais lue');
      expect(m.decider('da', p.valeur!.version['id'] as String, 'non', motif: 'Hors budget').ok, isTrue);
      expect(m.na('MG02', plus(5)), 8000, reason: 'refusée : jamais lue');
    });

    test('une prestation absente et un prix manquant se NOMMENT : jamais un zéro (un tiret n\'est pas un zéro)', () {
      final m = monde();
      expect(m.h.aLaDate('NEXISTE', null, false, aujourdhui: jour).absent, isTrue);
      final sans = Monde([prestation('X1')], [
        {'id': 'X1@origine@1', 'code': 'X1', 'version': 1, 'etatNonAssure': 'manquant', 'etatAssure': 'manquant', 'origine': 'migration', 'statut': 'valide'}
      ]);
      expect(sans.h.aLaDate('X1', null, false, aujourdhui: jour).montant, isNull);
    });

    test('le jour d\'une pièce : un instant se ramène au jour, une date vide vaut le jour fourni (le domaine ne lit jamais l\'horloge)', () {
      expect(tarJourDe('2026-11-14T23:59:59', jour), '2026-11-14');
      expect(tarJourDe(null, jour), jour);
      expect(tarJourDe('', jour), jour);
    });
  });

  group('immutabilité (RG-14 : le prix d\'une pièce émise doit pouvoir se relire)', () {
    test('le prix d\'une version valide ne se réécrit pas ; seule une proposition se décide', () {
      final v = version1('MG01', 5000);
      expect(tarGardeVersion('modifier', {...v, 'prixNonAssure': 1}, v), isNotNull, reason: 'le prix ne bouge pas');
      expect(tarGardeVersion('modifier', {...v, 'statut': 'retire'}, v), isNotNull, reason: 'une version valide ne se retire pas');
      expect(tarGardeVersion('archiver', {...v, 'statut': 'archive'}, v), isNotNull);
      expect(tarGardeVersion('inserer', {...v}, v), isNotNull, reason: 'une insertion ne réécrit pas une version');
      final propose = {...v, 'id': 'MG01@a-dater@2', 'version': 2, 'statut': 'propose'};
      expect(tarGardeVersion('modifier', {...propose, 'statut': 'refuse', 'motifDecision': 'x'}, propose), isNull, reason: 'une proposition se décide');
    });

    test('les listes de lecture ne s\'éditent plus pour un prix quand le référentiel est présent', () {
      final avant = {'id': 'ACT-1', 'code': 'MG01', 'prix': 5000};
      expect(tarGardeLecture('actes', 'modifier', {...avant, 'prix': 1}, avant, referentielPresent: true), isNotNull);
      expect(tarGardeLecture('actes', 'modifier', {...avant, 'libelle': 'Autre'}, avant, referentielPresent: true), isNull, reason: 'un libellé reste libre');
      expect(tarGardeLecture('actes', 'modifier', {...avant, 'prix': 1}, avant, referentielPresent: false), isNull, reason: 'sans référentiel, la liste reste la seule source');
    });
  });

  group('proposer et décider : deux droits, tous deux tenus PAR LA MATRICE', () {
    test('proposer est le droit d\'éditer l\'écran ; décider est le geste réservé : aucun nom de rôle dans le moteur', () {
      final m = monde();
      expect(m.proposer('stock', prop('MG03', 11000, date: plus(2)), editer: false).refus!.code, isNotEmpty, reason: 'sans droit d\'éditer : refusé');
      final ok = m.proposer('stock', prop('MG03', 11000, date: plus(2)));
      expect(ok.ok, isTrue, reason: 'qui édite propose');
      expect(m.decider('stock', ok.valeur!.version['id'] as String, 'oui').refus!.code, 'VALIDATION_RESERVEE', reason: 'éditer ne suffit pas à décider');
      expect(m.decider('da', ok.valeur!.version['id'] as String, 'oui').ok, isTrue);
    });

    test('une fiche de rôle ACCORDE et RETIRE le geste (la matrice, pas le code)', () {
      final fiches = [
        {'id': 'R1', 'role': 'stock', 'statut': 'actif', 'droitsGestes': {gesteDeciderPrix: true}},
        {'id': 'R2', 'role': 'da', 'statut': 'actif', 'droitsGestes': {gesteDeciderPrix: false}},
      ];
      final m = Monde([prestation('MG03')], [version1('MG03', 10000)], fiches: fiches);
      final p = m.proposer('stock', prop('MG03', 11000, date: plus(2)));
      expect(m.decider('stock', p.valeur!.version['id'] as String, 'oui').ok, isTrue, reason: 'la fiche accorde le geste au gestionnaire de stock');
      final q = m.proposer('stock', prop('MG03', 12000, date: plus(4)));
      expect(m.decider('da', q.valeur!.version['id'] as String, 'oui').refus!.code, 'VALIDATION_RESERVEE', reason: 'la fiche retire le geste à la DAF');
    });

    test('un Non exige son motif et ne crée aucune version', () {
      final m = monde();
      final p = m.proposer('da', prop('MG02', 9000, date: plus(2)));
      final id = p.valeur!.version['id'] as String;
      expect(m.decider('da', id, 'non').refus, isNotNull, reason: 'motif obligatoire');
      expect(m.decider('da', id, 'non', motif: 'Prix trop haut').ok, isTrue);
      expect(m.h.versionsDe('MG02').length, 2);
      expect(m.na('MG02', plus(9)), 8000);
    });

    test('zéro, vide, identique : refusés en nommant', () {
      final m = monde();
      expect(m.proposer('da', prop('MG02', 0, date: plus(1))).refus!.code, 'PRIX_ZERO');
      expect(m.proposer('da', prop('MG02', '', date: plus(1))).refus, isNotNull);
      expect(m.proposer('da', prop('MG02', 8000, date: plus(1))).refus, isNotNull, reason: 'ligne identique');
    });
  });

  group('date d\'effet dans le passé (T6)', () {
    test('refusée dès qu\'une pièce a utilisé la prestation depuis cette date, même pour la DAF avec la case et le motif', () {
      final m = monde();
      m.piece('FC-2026-00001', 'MG03', '${plus(-3)}T10:00:00');
      final r = m.proposer('da', prop('MG03', 11000, date: plus(-5), passee: true));
      expect(r.refus!.code, 'TARIF_DEJA_UTILISE');
      expect(r.refus!.motif, contains('FC-2026-00001'));
    });

    test('permise à la DAF et à la Direction (geste de la matrice) avec la case et le motif ; refusée sans la case, et à l\'administrateur', () {
      final m = monde();
      expect(m.proposer('da', prop('MG04', 31000, date: plus(-1))).refus!.code, 'DATE_PASSEE');
      final ok = m.proposer('da', prop('MG04', 31000, date: plus(-1), passee: true));
      expect(ok.ok, isTrue, reason: '${ok.refus?.motif}');
      expect(ok.valeur!.version['datePassee'], isTrue);
      expect(m.proposer('admin', prop('MG02', 8100, date: plus(-1), passee: true)).refus!.code, 'DATE_PASSEE_RESERVEE', reason: 'l\'administrateur décide mais ne date pas dans le passé');
      expect(m.decider('admin', ok.valeur!.version['id'] as String, 'oui').refus!.code, 'DATE_PASSEE_RESERVEE');
      expect(m.decider('direction', ok.valeur!.version['id'] as String, 'oui').ok, isTrue);
      expect(m.na('MG04', plus(-1)), 31000);
      expect(m.na('MG04', plus(-2)), 30000, reason: 'la veille : l\'ancien prix');
    });

    test('le refus nomme les profils que la matrice désigne (info-bulle), jamais une liste écrite dans le moteur', () {
      expect(tarProfilsDatePassee(['La DAF', 'La Direction']), 'La DAF et La Direction');
      expect(tarProfilsDatePassee(const []), contains('matrice'));
    });
  });

  group('ligne impayée figée à la prescription (T4) et pro-forma (T5)', () {
    test('une prestation déjà portée par une pièce du jour ferme la date d\'effet d\'aujourd\'hui : le patient informé garde son prix', () {
      final m = monde();
      m.piece('FC-2026-00010', 'MG01', '${jour}T09:00:00');
      expect(m.proposer('da', prop('MG01', 5200, date: jour)).refus!.code, 'TARIF_DEJA_UTILISE');
      final demain = m.proposer('da', prop('MG01', 5200, date: plus(1)));
      expect(demain.ok, isTrue, reason: 'le même changement à effet de demain passe');
      m.piece('FC-2026-00011', 'MG01', '${plus(1)}T10:00:00');
      expect(m.decider('da', demain.valeur!.version['id'] as String, 'oui').refus!.code, 'TARIF_DEJA_UTILISE', reason: 'rejoué au Oui : la pièce émise pendant l\'attente le refuse');
    });

    test('pro-forma : le prix de la pro-forma est tenu dans la durée de validité, le prix du jour au-delà', () {
      final m = monde();
      final P = m.na('SO17');
      F mk(int age, String n) => {
            'id': 'PF$n',
            'numero': 'PRO-2026-$n',
            'date': '${plus(-age)}T09:00:00',
            'proforma': true,
            'statut': 'actif',
            'lignes': [
              {'id': 'L001', 'categorie': 'acte', 'designation': 'Estimation', 'quantite': 1, 'prixUnitaire': P, 'montant': P, 'acteCode': 'SO17'}
            ]
          };
      expect(m.proposer('da', prop('SO17', P + 300, date: jour, valider: true)).ok, isTrue);
      Map<String, Object?> ec(F f, int validite) {
        final e = tarEcartProforma(f, referentiel: m.h, pieces: const PiecesTarif(), aujourdhui: jour, validiteJours: validite, assureA: (_) => false).valeur!;
        final l = (e['lignes'] as List).first as Map;
        return {'ancien': l['ancien'], 'nouveau': l['nouveau'], 'retenu': l['retenu'], 'ecart': e['ecartTotal']};
      }

      expect(ec(mk(10, '0001'), 30)['retenu'], P, reason: 'dans les 30 jours : le prix de la pro-forma est gardé');
      expect(ec(mk(10, '0001'), 30)['ecart'], 300, reason: 'l\'écart est affiché');
      expect(ec(mk(40, '0002'), 30)['retenu'], P + 300, reason: 'au-delà : le prix du jour');
      expect(tarValiditeProformaJours(null), tarValiditeProformaDefaut);
      expect(tarValiditeProformaDefaut, 30);
      expect(tarValiditeProformaJours('abc'), tarValiditeProformaDefaut, reason: 'une durée illisible retombe sur le défaut');
      expect(tarDefinirValiditeProforma(m.cx('caissier'), 99, reglageActuel: null).refus!.code, isNotEmpty, reason: 'réglage réservé aux profils qui décident');
      expect(tarDefinirValiditeProforma(m.cx('da'), 5, reglageActuel: null).valeur!.jours, 5);
    });
  });

  group('migration : la valeur facturée aujourd\'hui devient la version 1, sans changer un franc', () {
    final actes = <F>[
      {'code': 'MG01', 'libelle': 'Consultation', 'secteur': 'Médecine générale', 'prix': 5000, 'prixAssure': 3000, 'prixNonAssure': 5000, 'codeTarif': 'CONS-GEN', 'assurable': true},
      {'code': 'MT05', 'libelle': 'Certificat d\'aptitude', 'secteur': 'Médecine du travail', 'prix': 5000, 'prixAssure': 5000, 'prixNonAssure': 5000, 'codeTarif': 'CERT-APT', 'assurable': 'sos'},
    ];
    final grille = <F>[
      {'code': 'CONS-GEN', 'libelle': 'Consultation', 'famille': 'CONSULTATION', 'prixNonAssure': 5000, 'prixAssure': 3000, 'assurable': true},
      {'code': 'CERT-APT', 'libelle': 'Certificat médical d\'aptitude', 'famille': 'CERTIFICAT', 'prixNonAssure': 7000, 'prixAssure': 7000, 'assurable': 'sos'},
      {'code': 'CERT-APT', 'libelle': 'Certificat d\'aptitude', 'famille': 'CERTIFICAT', 'prixNonAssure': 5000, 'prixAssure': 5000, 'assurable': 'sos'},
      {'code': 'LAB-AKOP', 'libelle': 'AKOP', 'famille': 'LABO', 'prixNonAssure': 2500, 'prixAssure': 2000, 'assurable': true},
    ];
    final analyses = <F>[
      {'code': 'L01', 'designation': 'AKOP', 'prix': 2000},
    ];

    test('un code de grille porté par DEUX lignes : la première (seule lue jusqu\'ici) est retenue, la seconde est LISTÉE, l\'acte garde son prix', () {
      final mg = tarMigrer(actes: actes, grille: grille, analyses: analyses, proposerGrilleAnalyses: false);
      final h = ReferentielTarifs(mg.tarifs, mg.versions);
      expect(h.aLaDate('CERT-APT', null, false, aujourdhui: jour).montant, 7000, reason: 'la caisse lisait 7 000 : inchangé');
      expect(h.prixActe('MT05', null, false, aujourdhui: jour).montant, 5000, reason: 'l\'acte garde son propre prix');
      expect([for (final e in mg.ecarts) e['type']], containsAll(['grille-doublon', 'acte-lien-ambigu']));
    });

    test('sans grille imprimée remise : aucune proposition inventée (une seule version par analyse, l\'écart est listé)', () {
      final mg = tarMigrer(actes: actes, grille: grille, analyses: analyses, proposerGrilleAnalyses: false);
      expect(mg.versions.where((v) => v['code'] == 'L01').length, 1);
      expect(mg.versions.where((v) => v['statut'] == 'propose'), isEmpty);
      expect([for (final e in mg.ecarts) e['type']], contains('analyse-grille-non-proposee'));
      final avec = tarMigrer(actes: actes, grille: grille, analyses: analyses);
      expect(avec.versions.where((v) => v['statut'] == 'propose').length, 1, reason: 'avec une grille imprimée (clinique sœur), le prix de la grille est proposé');
    });

    test('un code canonique par prestation, l\'autre en alias ; chaque prix facturé aujourd\'hui est repris à l\'identique', () {
      final mg = tarMigrer(actes: actes, grille: grille, analyses: analyses, proposerGrilleAnalyses: false);
      final h = ReferentielTarifs(mg.tarifs, mg.versions);
      expect(h.parCode['CONS-GEN']!['code'], 'MG01');
      expect(h.aLaDate('MG01', null, true, aujourdhui: jour).montant, 3000);
      expect(h.aLaDate('MG01', null, false, aujourdhui: jour).montant, 5000);
      expect(h.prixAnalyse('L01', null, false, aujourdhui: jour).montant, 2000, reason: 'le prix facturé de l\'analyse, non celui de la ligne LABO');
    });
  });
}
