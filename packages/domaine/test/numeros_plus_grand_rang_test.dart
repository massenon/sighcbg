import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// LES NUMÉROS SUIVENT LE PLUS GRAND RANG PORTÉ, JAMAIS LE NOMBRE DE FICHES (Direction de Baguidi, 17/11/2026, point 4 ; `docs/prd/DECISIONS-16-11-ASSISTANT-AI-AK.md` § 10).
///
/// Treize séries tiraient leur rang du NOMBRE de fiches (E3866) : une fiche supprimée du registre, archivée au milieu, ou d'une autre série du même registre (les factures)
/// faisait RÉUTILISER un numéro déjà émis, ou en sauter. Elles passent à `rangMaximal + 1`, archives comprises ; les numéros déjà émis ne changent pas.

typedef M = Map<String, Object?>;

/// Un registre où le rang 1 est actif, le rang 2 archivé, puis un trou jusqu'au rang 7 archivé : trois fiches, mais le plus grand rang est 7 (le NOMBRE donnerait 4).
List<M> registre(String serie, {String? champ, Object? date, Map<String, Object?> extra = const {}}) {
  final s = Numerotation.semence(serie);
  final c = champ ?? s.champ;
  M f(int rang, String statut) => {c: numeroFormate(serie, date: date ?? '2026-06-01', rang: rang), 'statut': statut, ...extra};
  return [f(1, 'actif'), f(2, 'archive'), f(7, 'archive')];
}

String rangDu(String serie, String numero) => '${Numerotation.semence(serie).rangDe(numero)}';

void main() {
  group('une fiche archivée au milieu ne fait jamais réutiliser un numéro (une épreuve par série)', () {
    const series = {
      'assurances.factures-meres': 'FM',
      'imagerie.factures': 'FI',
      'patients.factures-externes': 'FE',
      'patients.factures-certificats': 'FC',
      'consultation.ordonnances': 'ORD',
      'cfg.certificats': 'CERT',
      'hospitalisation.observations': 'OBS',
      'patients.documents': 'GED',
      'adm.evenements': 'EVT',
      'stock.produits': 'PRD',
      'cfg.actes': 'ACT',
    };
    for (final e in series.entries) {
      test('${e.value} (${e.key}) : le suivant est le rang 8, pas le rang 4', () {
        final suivant = numeroSuivant(e.key, date: '2026-06-01', existants: registre(e.key));
        expect(rangDu(e.key, suivant), '8', reason: suivant);
        expect(suivant, numeroFormate(e.key, date: '2026-06-01', rang: 8));
        // Les numéros déjà émis ne changent pas : le format est celui de la semence, caractère pour caractère.
        expect(numeroFormate(e.key, date: '2026-06-01', rang: 7), startsWith(Numerotation.serie(e.key, date: '2026-06-01').formater(an: 2026, rang: 7).substring(0, 3)));
      });
    }

    test('chaque série lit le champ que son registre ÉCRIT réellement (un champ mal nommé ferait toujours repartir au rang 1)', () {
      // Relevé sur les écrans qui posent le numéro : factures et certificats portent `numero`, observations, documents et événements `reference`, produits et actes `code`.
      const champs = {
        'assurances.factures-meres': 'numero',
        'imagerie.factures': 'numero',
        'patients.factures-externes': 'numero',
        'patients.factures-certificats': 'numero',
        'consultation.ordonnances': 'numero',
        'cfg.certificats': 'numero',
        'hospitalisation.observations': 'reference',
        'patients.documents': 'reference',
        'adm.evenements': 'reference',
        'stock.produits': 'code',
        'cfg.actes': 'code',
      };
      for (final e in champs.entries) {
        expect(Numerotation.semence(e.key).champ, e.value, reason: e.key);
      }
    });

    test('les séries de la liste existent toutes au référentiel (une série renommée ferait échouer ce test, pas passer en silence)', () {
      for (final code in series.keys) {
        expect(Numerotation.connue(code), isTrue, reason: code);
      }
    });

    test('un registre vide reste au rang 1 ; une pièce d\'une autre série du même registre ne compte pas', () {
      for (final code in series.keys) {
        expect(rangDu(code, numeroSuivant(code, date: '2026-06-01', existants: const [])), '1', reason: code);
      }
      // Les factures vivent dans UN registre : une facture normalisée (FN-) au rang 400 ne fait pas démarrer la série FE au rang 401.
      final factures = [
        {'numero': 'FN-2026-00400'},
        {'numero': 'FE-2026-00003', 'statut': 'archive'},
      ];
      expect(numeroSuivant('patients.factures-externes', date: '2026-06-01', existants: factures), 'FE-2026-00004');
      expect(numeroSuivant('patients.factures-certificats', date: '2026-06-01', existants: factures), 'FC-2026-00001');
      expect(numeroSuivant('imagerie.factures', date: '2026-06-01', existants: factures), 'FI-2026-00001');
    });
  });

  group('les fonctions du domaine qui comptaient les fiches lisent désormais le plus grand rang', () {
    test('certificat, document du dossier, événement de l\'établissement', () {
      expect(cfaNumeroCertificat(registre('cfg.certificats'), date: '2026-06-01'), 'CERT-2026-0008');
      expect(patReferenceDocument(registre('patients.documents'), date: '2026-06-01'), 'GED-00008');
      expect(admReferenceEvenement(registre('adm.evenements'), date: '2026-06-01'), 'EVE-0008');
    });

    test('code d\'un produit et d\'un acte (saisie sans code)', () {
      expect(cfaFicheProduit({'designation': 'X', 'categorie': 'conso_medical', 'prixAchat': '1', 'prixVente': '1'}, registre('stock.produits'))['code'], 'PRD-0008');
      expect(cfaFicheActe({'libelle': 'X', 'secteur': 'Médecine générale', 'prix': ''}, registre('cfg.actes'))['code'], 'ACT-008');
    });

    test('facture mère : le rang suit la plus grande pièce, archivées comprises', () {
      final filles = <AssFilleMere>[];
      final fiche = assEmettreMere(
          code: 'SOS',
          nom: 'SOS',
          periode: assPeriodesMere.first.$1,
          filles: filles,
          rap: assRapprocher(filles),
          depuis: '2026-06-01',
          auj: DateTime(2026, 6, 30),
          existantes: registre('assurances.factures-meres'),
          emisePar: 'Test');
      expect(fiche['numero'], 'FM-2026-0008');
    });

    test('à-nouveaux importés : le plus grand rang de pièce, jamais le nombre de LIGNES du journal AN', () {
      // Une pièce d'à-nouveau porte plusieurs lignes d'un même numéro : trois lignes archivées de la pièce 1 donnaient « 4 » à l'ancien calcul.
      final port = PortImportMemoire({
        'ecritures': [
          for (var i = 0; i < 3; i++) {'journal': 'AN', 'numero': 'AN-2027-00001', 'date': '2027-01-01', 'statut': 'archive'},
        ],
        'comptes': [
          {'num': '571000', 'libelle': 'Caisse'}
        ],
      });
      jeuSoldesOuverture.ecrire(
          [LigneImport(1, {'date': '2027-01-01', 'compte': '571000', 'debit': 100, 'credit': 0}, const [])],
          (collection, fiche) => port.inserer(collection, {'statut': 'actif', ...fiche}),
          <String, Object?>{},
          <String, Object?>{},
          port);
      final nouvelles = port.toutes('ecritures').where((e) => e['statut'] == 'brouillon').toList();
      expect(nouvelles.single['numero'], 'AN-2027-00002');
    });
  });

  test('CLIQUET : aucun appelant ne tire plus un rang du NOMBRE de fiches (numeroFormate(..., rang: n + 1) est interdit)', () {
    final racines = ['lib', '../../apps/poste/lib', '../../apps/mobile/lib'];
    // Les appels légitimes : un rang déjà calculé par un moteur qui lit le plus grand rang (série de factures, plages de la mère, versions de clôture).
    const tolerees = {'caisse/emission.dart': 'rangDebut = plus grand rang de la série (rangSerieFactures)'};
    final motif = RegExp(r'numeroFormate\([^;]*?rang:\s*[^,;]*?(\.length|\+\s*1)');
    final fautifs = <String>[];
    for (final r in racines) {
      final d = Directory(r);
      if (!d.existsSync()) continue;
      for (final f in d.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('numerotation/numerotation.dart')) continue;
        if (tolerees.keys.any(f.path.endsWith)) continue;
        final s = f.readAsStringSync();
        for (final m in motif.allMatches(s)) {
          fautifs.add('${f.path} : ${m.group(0)!.split('\n').first}');
        }
      }
    }
    expect(fautifs, isEmpty, reason: 'un rang compté se dédouble à la première fiche archivée : utiliser numeroSuivant / rangMaximal');
  });
}
