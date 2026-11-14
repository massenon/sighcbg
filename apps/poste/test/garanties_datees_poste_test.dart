import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm9_aide.dart' as m9;

/// T13 : les garanties des assureurs sont DATÉES, au poste. Migration d'un magasin déjà peuplé (rang 1, aucune date inventée, rien ne change à la prise en charge), garde AU MOTEUR du magasin
/// (version immuable, version à la fin de sa série, archivage refusé sous la suivante), écran à UNE LIGNE PAR SÉRIE avec historique, et les deux jeux d'import écrits par le port du poste
/// (journal, identifiants, annulation qui restitue la fin d'une couverture et la fiche du dossier).
typedef F = Map<String, Object?>;

F gar(String id, String sous, String libelle, String cat, num taux, {num? plafond, String? dateEffet, int? version, String? unite}) => {
      'id': id,
      'souscripteurId': sous,
      'assureur': 'AFR',
      'libelle': libelle,
      'categorie': cat,
      'taux': taux,
      'plafond': plafond,
      'unitePlafond': unite,
      'statut': 'actif',
      if (dateEffet != null) 'dateEffet': dateEffet,
      if (version != null) 'version': version,
    };

final Map<String, List<F>> petit = {
  'souscripteurs': [
    {'id': 'S1', 'nom': 'Employeur un', 'assureur': 'AFR', 'assureurNom': 'Compagnie un', 'police': 'P/1', 'categorie': 'entreprise', 'statut': 'actif'},
  ],
  'patients': [
    {'id': 'P1', 'code': 'CBG/1/26', 'nom': 'DUPONT', 'prenom': 'Aline', 'assureur': 'AFR', 'souscripteurId': 'S1', 'carteExpiration': '2027-12-31', 'statut': 'actif'},
  ],
  'factures': [],
  'couverturesAssurance': [],
};

Magasin avec(List<F> garanties, {Map<String, List<F>>? plus}) => Magasin({...petit, ...?plus, 'garanties': garanties}, 'POSTE')..utilisateur = 'Agent test';

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  group('migration d’un magasin déjà peuplé', () {
    test('chaque garantie sans rang devient la version 1 : taux, plafond et libellé ne bougent pas, AUCUNE date d’effet n’est posée, une trace est écrite au journal', () {
      final m = avec([
        gar('G1', 'S1', 'Consultation', 'consultation', 80, plafond: 5000, unite: 'acte'),
        gar('G2', 'S1', 'Analyses', 'analyse', 70),
        gar('G3', 'S1', 'Analyses', 'analyse', 40, dateEffet: '2026-09-01'),
      ]);
      final avant = {for (final g in m.collection('garanties').toutes) g['id']: {...g}};
      final col = m.collection('garanties');
      expect(m.migrationGaranties, isNotNull);
      expect(m.migrationGaranties!.versionsPosees, 3);
      expect(col.parId('G1')!['version'], 1);
      expect(col.parId('G2')!['version'], 1);
      expect(col.parId('G3')!['version'], 2, reason: 'la version datée passe après celle d’origine');
      for (final g in col.toutes) {
        final a = avant[g['id']]!;
        for (final k in ['taux', 'plafond', 'libelle', 'unitePlafond', 'dateEffet']) {
          expect(g[k], a[k], reason: '${g['id']}.$k : seul le rang est posé');
        }
      }
      expect(col.parId('G1')!.containsKey('dateEffet'), isFalse, reason: 'aucune date d’effet inventée');
      expect(m.collection('audit').toutes.any((e) => e['action'] == 'Migration' && e['entite'] == 'Garantie'), isTrue);
    });

    test('une collection déjà migrée n’est pas retouchée ; la prise en charge lit la même chose avant et après', () {
      final brut = [gar('G1', 'S1', 'Consultation', 'consultation', 80, plafond: 5000, unite: 'acte')];
      final lignes = [
        {'libelle': 'Consultation', 'categorie': 'consultation', 'montant': 10000}
      ];
      Repartition lire(Magasin m) => repartir(
          patient: m.collection('patients').parId('P1'),
          lignes: lignes,
          date: '2026-08-16',
          couvertures: const [],
          souscripteurs: m.collection('souscripteurs').actives,
          garanties: m.collection('garanties').actives);
      final avantMigration = repartir(
          patient: petit['patients']!.first,
          lignes: lignes,
          date: '2026-08-16',
          souscripteurs: petit['souscripteurs']!,
          garanties: brut);
      final m = avec(brut);
      final apres = lire(m);
      expect(apres.partAssureur, avantMigration.partAssureur);
      expect(apres.partPatient, avantMigration.partPatient);
      expect(m.migrationGaranties!.aFait, isTrue);
      final m2 = avec([for (final g in m.collection('garanties').toutes) {...g}]);
      m2.collection('garanties');
      expect(m2.migrationGaranties, isNull, reason: 'rien à refaire : idempotente');
    });
  });

  group('la garde du magasin', () {
    final base = [
      gar('G1', 'S1', 'Consultation', 'consultation', 80, plafond: 5000, unite: 'acte', version: 1),
      gar('G2', 'S1', 'Consultation', 'consultation', 60, plafond: 4000, unite: 'acte', dateEffet: '2026-09-01', version: 2),
    ];
    test('une version est immuable ; la série ne se redéfinit pas « depuis l’ouverture » ; une version ne s’insère pas dans le passé de sa série ni à une date prise', () {
      final col = avec(base).collection('garanties');
      expect(() => col.mettreAJour('G1', {'taux': 10}), throwsA(isA<EcritureRefusee>()));
      expect(() => col.mettreAJour('G2', {'dateEffet': '2026-10-01'}), throwsA(isA<EcritureRefusee>()));
      expect(() => col.inserer({...base[0], 'id': 'G9', 'taux': 1}, prefixe: 'GAR'), throwsA(isA<EcritureRefusee>()), reason: 'depuis l’ouverture : la série existe');
      expect(() => col.inserer({...base[1], 'id': 'G9', 'taux': 1, 'dateEffet': '2026-09-01'}, prefixe: 'GAR'), throwsA(isA<EcritureRefusee>()), reason: 'date déjà prise');
      expect(() => col.inserer({...base[1], 'id': 'G9', 'taux': 1, 'dateEffet': '2026-08-01'}, prefixe: 'GAR'), throwsA(isA<EcritureRefusee>()), reason: 'dans le passé de la série');
      expect(col.parId('G1')!['taux'], 80);
      final ok = col.inserer({...base[1], 'id': 'G9', 'taux': 50, 'dateEffet': '2026-12-01', 'version': 3}, prefixe: 'GAR');
      expect(ok.fiche['id'], 'G9');
    });

    test('une version ne s’archive pas sous la suivante, ni sous une facture émise ; la dernière s’archive (RG-14) tant qu’aucune pièce ne s’appuie dessus', () {
      final col = avec(base).collection('garanties');
      expect(() => col.archiver('G1'), throwsA(isA<EcritureRefusee>()));
      col.archiver('G2');
      expect(col.parId('G2')!['statut'], 'archive');
      final m2 = avec(base, plus: {
        'factures': [
          {'id': 'F1', 'numero': 'F-1', 'date': '2026-09-15', 'assureur': 'AFR', 'patientId': 'P1', 'statut': 'actif'}
        ]
      });
      expect(() => m2.collection('garanties').archiver('G2'), throwsA(isA<EcritureRefusee>()), reason: 'la facture F-1 a été émise sous cette version');
    });

    test('la pièce émise avant la version garde son taux ; la pièce du jour de la version prend le nouveau', () {
      final m = avec(base);
      Repartition lire(String d) => repartir(
          patient: m.collection('patients').parId('P1'),
          lignes: [
            {'libelle': 'Consultation', 'categorie': 'consultation', 'montant': 10000}
          ],
          date: d,
          souscripteurs: m.collection('souscripteurs').actives,
          garanties: m.collection('garanties').actives);
      expect(lire('2026-08-31').partAssureur, 5000, reason: '80 % plafonné à 5 000');
      expect(lire('2026-09-01').partAssureur, 4000, reason: '60 % plafonné à 4 000');
    });
  });

  group('écran « Conventions & garanties » : une ligne par série', () {
    Magasin jeu() {
      final m = m9.magasin();
      final col = m.collection('garanties');
      for (final g in [
        gar('GA1', 'SOU001', 'Consultation', 'consultation', 70, version: 1),
        gar('GA2', 'SOU001', 'Consultation', 'consultation', 80, dateEffet: '2026-07-01', version: 2),
        gar('GA3', 'SOU001', 'Consultation', 'consultation', 90, dateEffet: '2026-12-01', version: 3),
        gar('GB1', 'SOU001', 'Analyses', 'analyse', 60, version: 1),
        gar('GB2', 'SOU001', 'Analyses', 'analyse', 65, dateEffet: '2026-06-01', version: 2),
      ]) {
        // Le jeu est posé comme le ferait une mère qui a reçu ces versions : les gardes ne jouent pas (le jeu de démonstration porte des factures de l'été sous cette grille).
        col.sansGardes(() => col.inserer({...g, 'assureur': 'AFR'}, prefixe: 'GAR'));
      }
      return m;
    }

    m9.cas('cinq versions écrites, deux séries : l’écran compte et liste DEUX garanties, la version en vigueur au 16/08, et dit la version à venir', (t) async {
      await m9.ouvrir(t, jeu(), 'm9-conventions');
      expect(find.text('Lignes de garantie'), findsOneWidget, reason: 'le libellé de la maquette ; la valeur compte les séries en vigueur');
      expect(m9.kpis(t), ['9', '1', '8', '2']);
      expect(find.textContaining('5 versions écrites, 2 séries'), findsOneWidget);
      expect(find.text('2 garanties'), findsOneWidget, reason: 'l’onglet des souscripteurs compte les séries en vigueur : deux, pas cinq lignes');
      await m9.toucher(t, find.text('Grilles de garanties').first);
      await t.pumpAndSettle();
      expect(find.text('80 %'), findsOneWidget, reason: 'la consultation : v2 (01/07), pas la v3 de décembre');
      expect(find.text('65 %'), findsOneWidget);
      expect(find.text('90 %'), findsNothing);
      expect(find.textContaining('à venir 01/12/2026'), findsOneWidget);
      await m9.toucher(t, find.text('Consultation').first);
      await t.pumpAndSettle();
      expect(find.text('Versions (3)'), findsOneWidget);
      expect(find.textContaining('Version en vigueur aujourd’hui : v2'), findsOneWidget);
      expect(find.text('Nouvelle version datée'), findsOneWidget);
    });

    m9.cas('sans le droit d’écrire (direction), l’historique se lit mais « Nouvelle version datée » est ABSENT', (t) async {
      await m9.ouvrir(t, jeu(), 'm9-conventions', role: 'direction');
      await m9.toucher(t, find.text('Grilles de garanties').first);
      await t.pumpAndSettle();
      await m9.toucher(t, find.text('Consultation').first);
      await t.pumpAndSettle();
      expect(find.text('Versions (3)'), findsOneWidget);
      expect(find.text('Nouvelle version datée'), findsNothing);
    });
  });

  group('les deux jeux d’import au poste', () {
    PortMagasin port(Magasin m) => PortMagasin(m, aujourdhui: () => DateTime(2026, 11, 14, 10), nomAgent: 'Agent test', profil: const ProfilImport.accordeTout());
    List<List<Object?>> fich(JeuImport j, List<Map<String, Object?>> lignes) => [
          [for (final c in j.colonnes) c.label],
          for (final l in lignes) [for (final c in j.colonnes) l[c.cle] ?? ''],
        ];

    test('garanties : une version datée s’écrit par le port du poste (identifiant GAR, journal), la version remplacée reste ; l’annulation archive', () {
      final m = avec([gar('G1', 'S1', 'Consultation', 'consultation', 80, plafond: 5000, unite: 'acte')]);
      final p = port(m);
      final j = jeuGaranties;
      final ligne = {'police': 'P/1', 'categorie': 'Consultations', 'garantie': 'Consultation', 'taux': 60, 'plafond': 4000, 'unite': 'par acte', 'dateEffet': '2026-12-01', 'motif': 'Avenant'};
      final a = analyserLignes(j, fich(j, [ligne]), 'g.xlsx', p);
      expect(a.accepte, isTrue, reason: '${[for (final x in a.problemes) '${x.code} ${x.motif}']}');
      final r = appliquer(j, a, p);
      expect(r.ok, isTrue, reason: '${r.motif}');
      final col = m.collection('garanties');
      expect(col.toutes.length, 2);
      expect(col.parId('G1')!['taux'], 80);
      final v2 = col.toutes.firstWhere((g) => g['id'] != 'G1');
      expect((v2['id'] as String), startsWith('GAR'));
      expect(v2['version'], 2);
      expect(v2['lotImport'], isNotNull);
      expect(m.collection('audit').toutes.any((e) => '${e['entite']}' == 'garanties' || '${e['reference']}'.contains('GAR')), isTrue);
      final an = annulerLot(jeuImportParId, r.lot!['id'], 'test', p);
      expect(an.ok, isTrue, reason: '${an.motif}');
      expect(col.actives.map((g) => g['id']), ['G1']);
    });

    test('couvertures : la fin de la couverture précédente et la fiche du dossier reprennent leur valeur à l’annulation, le lot garde ses restaurations', () {
      final m = avec([], plus: {
        'assureurs': [
          {'id': 'A1', 'code': 'AFR', 'nom': 'Compagnie un', 'statut': 'actif'},
          {'id': 'A2', 'code': 'NSIA', 'nom': 'Compagnie deux', 'statut': 'actif'},
        ],
        'souscripteurs': [
          ...petit['souscripteurs']!,
          {'id': 'S2', 'nom': 'Employeur deux', 'assureur': 'NSIA', 'assureurNom': 'Compagnie deux', 'police': 'P/2', 'categorie': 'entreprise', 'statut': 'actif'},
        ],
        'couverturesAssurance': [
          {'id': 'C0', 'patientId': 'P1', 'assureur': 'AFR', 'souscripteurId': 'S1', 'debut': '2026-01-01', 'fin': null, 'statut': 'actif'}
        ],
      });
      final p = port(m);
      final j = jeuCouverturesAssurance;
      final ligne = {'patient': 'CBG/1/26', 'assureur': 'NSIA', 'police': 'P/2', 'dateEffet': '2026-11-01', 'motif': 'Changement d’employeur', 'carteExpiration': '2027-12-31', 'taux': 70};
      final a = analyserLignes(j, fich(j, [ligne]), 'c.xlsx', p);
      expect(a.accepte, isTrue, reason: '${[for (final x in a.problemes) '${x.code} ${x.motif}']}');
      final r = appliquer(j, a, p);
      expect(r.ok, isTrue, reason: '${r.motif}');
      expect(m.collection('couverturesAssurance').parId('C0')!['fin'], '2026-10-31');
      expect(m.collection('patients').parId('P1')!['souscripteurId'], 'S2');
      expect(m.collection('patients').parId('P1')!['assureur'], 'NSIA');
      final lot = m.collection(collectionLots).parId(r.lot!['id'])!;
      expect((lot['restaurations'] as List).length, 2, reason: 'la fin de C0 et la fiche du dossier');
      expect(annulerLot(jeuImportParId, lot['id'], 'erreur', p).ok, isTrue);
      expect(m.collection('couverturesAssurance').parId('C0')!['fin'], isNull);
      expect(m.collection('patients').parId('P1')!['souscripteurId'], 'S1');
      expect(m.collection('patients').parId('P1')!['assureur'], 'AFR');
    });
  });
}
