// Les indicateurs agrégés publiés au relais (Direction, 09/11/2026, ADR-0007) : calcul, schéma strict, et PREUVE qu'aucune donnée nominative n'en sort.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

// Des valeurs que RIEN ne doit laisser fuir : noms de personnes, de fournisseurs, de produits, de motifs, de diagnostics, téléphones, adresses, codes patient.
const noms = ['ZANTCHEDE', 'Kadidja', 'GOUNOUGBO Prosper', 'Pharma Borgou SARL', 'Paracétamol 500 mg', 'Paludisme grave', 'Drépanocytose', '00 00 00 00 02', 'Dépôt, Parakou', 'CBG/1/26', 'CBG/77/26', 'Chantier Alafia', 'admin@baguidi-clinique.bj', 'VODOUHE Fiacre', 'Grossiste Alpha-Pharma'];

IkEntree jeuPlein() {
  final maintenant = DateTime.utc(2026, 11, 9, 10);
  return IkEntree(
    maintenant: maintenant,
    versionApplication: '1.4.2+7',
    joursPeremption: 90,
    appareils: const [IkAppareil(identifiant: 'poste-a1', dernierContactMs: 1762680000000), IkAppareil(identifiant: 'mobile-b2', dernierContactMs: 1762670000000)],
    collections: {
      'patients': [
        {'id': 'P1', 'statut': 'actif', 'code': 'CBG/1/26', 'nom': 'ZANTCHEDE', 'prenom': 'Kadidja', 'telephone': '00 00 00 00 02', 'adresse': 'Dépôt, Parakou', 'antecedents': 'Drépanocytose', 'dateCreation': '2026-11-03', 'fictif': true},
        {'id': 'P2', 'statut': 'actif', 'code': 'CBG/77/26', 'nom': 'VODOUHE', 'prenom': 'Fiacre', 'dateCreation': '2026-09-20'},
        {'id': 'P3', 'statut': 'inactif', 'code': 'CBG/3/26', 'nom': 'GOUNOUGBO', 'dateCreation': '2026-11-01'},
      ],
      'consultations': [
        {'id': 'C1', 'date': '2026-11-05T10:30:00.000Z', 'motif': 'Paludisme grave', 'diagnostic': 'Drépanocytose', 'medecin': 'VODOUHE Fiacre', 'patient': 'ZANTCHEDE Kadidja'},
        {'id': 'C2', 'date': '2026-10-30T10:30:00.000Z', 'motif': 'Paludisme grave'},
      ],
      'visites': [
        {'id': 'V1', 'date': '2026-11-07', 'visiteurNom': 'GOUNOUGBO Prosper'},
      ],
      'rendezvous': <F>[],
      'admissions': [
        {'id': 'A1', 'statut': 'en_cours', 'dateEntree': '2026-11-02', 'patient': 'ZANTCHEDE Kadidja', 'diagnosticEntree': 'Paludisme grave'},
        {'id': 'A2', 'statut': 'sortie', 'dateEntree': '2026-10-02'},
      ],
      'lits': [
        {'id': 'L1', 'libelle': 'A1 LIT1'},
        {'id': 'L2', 'libelle': 'A1 LIT2'},
        {'id': 'L3', 'libelle': 'B1 LIT1'},
        {'id': 'L4', 'libelle': 'B1 LIT2'},
      ],
      'factures': [
        {'id': 'F1', 'numero': 'FN-2026-00001', 'date': '2026-11-04', 'montantTTC': 10000, 'montantPaye': 4000, 'reliquat': 6000, 'patient': 'ZANTCHEDE Kadidja', 'patientCode': 'CBG/1/26'},
        {'id': 'F2', 'numero': 'FN-2026-00002', 'date': '2026-11-06', 'montantTTC': 5500, 'montantPaye': 5500, 'reliquat': 0, 'assureur': 'Chantier Alafia'},
        {'id': 'F3', 'numero': 'FP-2026-00003', 'date': '2026-11-06', 'montantTTC': 999999, 'proforma': true},
        {'id': 'F4', 'numero': 'FN-2026-00000', 'date': '2026-10-31', 'montantTTC': 777, 'montantPaye': 0},
      ],
      'produits': [
        {'id': 'PRD1', 'designation': 'Paracétamol 500 mg', 'fournisseur': 'Pharma Borgou SARL', 'seuilAlerte': 100, 'stock': 40},
        {'id': 'PRD2', 'designation': 'Gants', 'seuilAlerte': 100, 'stockGros': 90, 'stockDetail': 60},
        {'id': 'PRD3', 'designation': 'Sérum', 'seuilAlerte': null, 'stock': 0},
      ],
      'lots': [
        {'id': 'LOT1', 'numeroLot': 'L1', 'datePeremption': '2026-12-15', 'quantiteRestante': 10},
        {'id': 'LOT2', 'numeroLot': 'L2', 'datePeremption': '2027-12-15', 'quantiteRestante': 10},
        {'id': 'LOT3', 'numeroLot': 'L3', 'datePeremption': '2026-10-01', 'quantiteRestante': 5},
        {'id': 'LOT4', 'numeroLot': 'L4', 'datePeremption': '2026-10-01', 'quantiteRestante': 0},
      ],
      'echeancesFiscales': [
        {'id': 'E1', 'code': 'ITS', 'libelle': 'Impôt sur les traitements salariaux', 'echeance': '2026-10-12', 'paye': false},
        {'id': 'E2', 'code': 'CNSS-VERS', 'echeance': '2026-11-16', 'paye': false},
        {'id': 'E3', 'code': 'AIB', 'echeance': '2026-11-12', 'paye': false},
        {'id': 'E4', 'code': 'TVM', 'echeance': '2026-09-10', 'paye': true},
      ],
      'ecritures': [
        {'id': 'R1', 'numero': 'CAI-2026-00001', 'statut': 'brouillon', 'libelle': 'Encaissement — ZANTCHEDE Kadidja'},
        {'id': 'R2', 'numero': 'CAI-2026-00001', 'statut': 'brouillon'},
        {'id': 'R3', 'numero': 'CAI-2026-00002', 'statut': 'validee'},
      ],
      'utilisateurs': [
        {'id': 'U1', 'identifiant': 'admin@baguidi-clinique.bj', 'nomComplet': 'GOUNOUGBO Prosper', 'actif': true, 'statut': 'actif'},
        {'id': 'U2', 'nomComplet': 'VODOUHE Fiacre', 'actif': false},
      ],
    },
  );
}

void main() {
  group('calcul', () {
    final r = ikCalculer(jeuPlein());
    Object? at(String chemin) {
      Object? v = r;
      for (final k in chemin.split('.')) {
        v = (v as Map)[k];
      }
      return v;
    }

    test('patients, activité du mois et facturation du mois', () {
      expect(at('patients.actifs'), 2);
      expect(at('patients.nouveaux_mois'), 2); // P1 et P3 créés en novembre (le statut ne retire pas la création)
      expect(at('activite_mois.m2_consultations'), 1);
      expect(at('activite_mois.m2_visites'), 1);
      expect(at('activite_mois.m2_rendezvous'), 0);
      expect(at('activite_mois.m3_admissions'), 1);
      expect(at('facturation_mois.factures_emises'), 2); // la pro forma et la facture d'octobre ne comptent pas
      expect(at('facturation_mois.montant_facture'), 15500);
      expect(at('facturation_mois.montant_encaisse'), 9500);
      expect(at('facturation_mois.reste_du'), 6000);
    });

    test('stock, péremption, échéances, brouillons, utilisateurs, lits', () {
      expect(at('stock.articles_sous_seuil'), 1); // 40 <= 100 ; 90 + 60 = 150 > 100 ; un seuil non fixé n'est pas un seuil de zéro
      expect(at('stock.lots_proches_peremption'), 1); // le 15/12/2026 est à 36 jours ; 2027 est hors fenêtre
      expect(at('stock.lots_perimes'), 1); // le lot périmé vide ne compte pas
      expect(at('comptabilite.echeances_en_retard'), 1);
      expect(at('comptabilite.prochaine_echeance_code'), 'AIB');
      expect(at('comptabilite.prochaine_echeance_date'), '2026-11-12');
      expect(at('comptabilite.brouillons_non_valides'), 1); // deux lignes, UNE pièce
      expect(at('utilisateurs_actifs'), 1);
      expect(at('taux_occupation_lits_pct'), 25); // 1 admission en cours pour 4 lits
    });

    test('version, schéma, horodatage, jeu de démonstration, postes', () {
      expect(at('schema'), ikVersionSchema);
      expect(at('version_application'), '1.4.2+7');
      expect(at('genere_le'), DateTime.utc(2026, 11, 9, 10).millisecondsSinceEpoch);
      expect(at('etat_jeu'), 'demonstration');
      expect(at('postes'), [
        {'appareil': 'mobile-b2', 'derniere_synchro': 1762670000000},
        {'appareil': 'poste-a1', 'derniere_synchro': 1762680000000},
      ]);
    });

    test('un jeu sans fiche marquée fictive est en production', () {
      final e = jeuPlein();
      final c = {for (final k in e.collections.entries) k.key: [for (final f in k.value) {...f}..remove('fictif')]};
      expect(ikCalculer(IkEntree(collections: c, maintenant: e.maintenant))['etat_jeu'], 'production');
    });

    test('une collection non reçue donne « non disponible » (null), jamais zéro', () {
      final e = ikCalculer(IkEntree(collections: const {}, maintenant: DateTime(2026, 11, 9)));
      expect((e['patients'] as Map)['actifs'], isNull);
      expect((e['facturation_mois'] as Map)['montant_facture'], isNull);
      expect((e['comptabilite'] as Map)['prochaine_echeance_code'], isNull);
      expect(e['taux_occupation_lits_pct'], isNull);
      expect(e['postes'], isEmpty);
      expect(ikValider(e), isEmpty);
    });

    test('sans lit déclaré le taux d\'occupation n\'est pas calculable', () {
      final e = jeuPlein();
      final c = {...e.collections, 'lits': <F>[]};
      expect(ikCalculer(IkEntree(collections: c, maintenant: e.maintenant))['taux_occupation_lits_pct'], isNull);
    });
  });

  group('schéma strict', () {
    test('le calcul est toujours conforme', () => expect(ikValider(ikCalculer(jeuPlein())), isEmpty));

    test('un champ inattendu, une chaîne libre ou un type faux sont des défauts nommés', () {
      F base() => jsonDecode(jsonEncode(ikCalculer(jeuPlein()))) as F;
      var b = base()..['nom_patient'] = 'ZANTCHEDE';
      expect(ikValider(b), contains('nom_patient : champ inattendu'));
      b = base();
      (b['patients'] as F)['actifs'] = 'beaucoup';
      expect(ikValider(b).single, startsWith('patients.actifs'));
      b = base();
      (b['patients'] as F)['commentaire'] = 'Kadidja est venue';
      expect(ikValider(b), contains('patients.commentaire : champ inattendu'));
      b = base();
      (b['comptabilite'] as F)['prochaine_echeance_code'] = 'Paiement du fournisseur Pharma Borgou';
      expect(ikValider(b).single, startsWith('comptabilite.prochaine_echeance_code'));
      b = base();
      (b['postes'] as List)[0] = {'appareil': 'Poste de VODOUHE Fiacre', 'derniere_synchro': 1};
      expect(ikValider(b).single, startsWith('postes[0].appareil'));
      b = base()..['etat_jeu'] = 'prod';
      expect(ikValider(b).single, startsWith('etat_jeu'));
      b = base()..['schema'] = 2;
      expect(ikValider(b).single, startsWith('schema'));
      b = base();
      (b['stock'] as F)['lots_perimes'] = 1.5;
      expect(ikValider(b).single, startsWith('stock.lots_perimes'));
      b = base();
      (b['stock'] as F)['lots_perimes'] = -1;
      expect(ikValider(b).single, startsWith('stock.lots_perimes'));
      b = base();
      (b['postes'] as List).addAll(List.generate(60, (i) => {'appareil': 'p$i', 'derniere_synchro': 1}));
      expect(ikValider(b).join(), contains('plus de $ikMaxAppareils'));
      expect(ikValider('texte'), isNotEmpty);
      expect(ikValider(base()..remove('stock')), contains('stock : champ manquant'));
    });
  });

  group('AUCUNE donnée nominative ne sort', () {
    final instantane = ikCalculer(jeuPlein());
    final json = jsonEncode(instantane);

    test('aucune valeur du jeu (nom, code patient, téléphone, adresse, motif, diagnostic, fournisseur, produit, courriel) n\'apparaît dans l\'instantané', () {
      for (final n in noms) {
        expect(json.contains(n), isFalse, reason: 'fuite de « $n »');
        for (final mot in n.split(RegExp(r'\s+')).where((m) => m.length >= 4)) {
          expect(json.toLowerCase().contains(mot.toLowerCase()), isFalse, reason: 'fuite d\'un mot de « $n » : $mot');
        }
      }
    });

    test('toute valeur de champ du jeu, de toute collection, est absente du résultat (balayage exhaustif, pas une liste choisie)', () {
      final e = jeuPlein();
      final sorties = ikChaines(instantane).toSet();
      final entrees = <String>{};
      void collecte(Object? v) {
        if (v is String && v.length >= 3) entrees.add(v);
        if (v is Map) v.values.forEach(collecte);
        if (v is List) v.forEach(collecte);
      }

      e.collections.values.forEach(collecte);
      // Seules passent des valeurs de FORME IMPOSÉE : un code d'obligation ou une date. Rien d'autre ne peut coïncider avec une valeur du jeu.
      final communes = sorties.intersection(entrees);
      for (final c in communes) {
        expect(RegExp(r'^[A-Z0-9_-]{1,24}$|^\d{4}-\d{2}-\d{2}$').hasMatch(c), isTrue, reason: '« $c » est une valeur du jeu qui sort sans être un code ou une date');
      }
      // Et ces communes sont exactement les deux champs de forme imposée de l'échéance, rien de plus.
      expect(communes, {'AIB', '2026-11-12'});
    });

    test('les seules chaînes de l\'instantané sont les clés du schéma, des énumérations et des formes imposées', () {
      final permises = <RegExp>[
        RegExp(r'^[a-z0-9_]+$'), // clés
        RegExp(r'^\d{1,3}(\.\d{1,3}){2}(\+\d{1,6})?$'), // version
        RegExp(r'^[A-Z0-9_-]{1,24}$'), // code d'obligation
        RegExp(r'^\d{4}-\d{2}-\d{2}$'), // date
        RegExp(r'^(mobile|poste)-[a-z0-9]+$'), // identifiants techniques du jeu
      ];
      for (final s in ikChaines(instantane)) {
        expect(permises.any((r) => r.hasMatch(s)), isTrue, reason: 'chaîne hors forme : « $s »');
      }
    });

    test('l\'étiquette d\'un poste (qui peut porter un nom) n\'est pas une entrée : seul l\'identifiant technique l\'est', () {
      // IkAppareil n'a pas de champ d'étiquette : la fuite est impossible par construction.
      const a = IkAppareil(identifiant: 'poste-a1', dernierContactMs: 1);
      expect(a.identifiant, 'poste-a1');
    });

    test('un identifiant qui ressemblerait à un nom est écarté, il ne part pas', () {
      final e = ikCalculer(IkEntree(
        collections: const {},
        maintenant: DateTime(2026, 11, 9),
        appareils: const [IkAppareil(identifiant: 'Poste de VODOUHE Fiacre', dernierContactMs: 1), IkAppareil(identifiant: 'poste-a1', dernierContactMs: 2)],
      ));
      expect(e['postes'], [
        {'appareil': 'poste-a1', 'derniere_synchro': 2}
      ]);
      expect(ikValider(e), isEmpty);
    });

    test('une version illisible est remplacée, jamais recopiée', () {
      final e = ikCalculer(IkEntree(collections: const {}, maintenant: DateTime(2026, 11, 9), versionApplication: 'Clinique de ZANTCHEDE'));
      expect(e['version_application'], '0.0.0');
    });

    test('le schéma ne porte aucun nom de champ nominatif', () {
      final interdits = RegExp(r'nom|prenom|patient_|code_patient|telephone|adresse|motif|diagnostic|fournisseur|agent|libelle|email|courriel', caseSensitive: false);
      for (final ch in ikChemins()) {
        expect(interdits.hasMatch(ch), isFalse, reason: 'champ suspect : $ch');
      }
    });
  });

  group('cohérence avec le relais', () {
    test('l\'exemple partagé avec les tests du relais est exactement ce que le calculateur produit sur le jeu plein', () {
      final f = File('../schema/indicateurs-clinique.exemple.json');
      final attendu = const JsonEncoder.withIndent('  ').convert(ikCalculer(jeuPlein()));
      if (Platform.environment['REGENERER_EXEMPLE'] == '1') f.writeAsStringSync('$attendu\n');
      expect(f.readAsStringSync().trim(), attendu, reason: 'regénérer avec REGENERER_EXEMPLE=1 dart test test/indicateurs_clinique_test.dart');
    });

    test('la liste des chemins est celle que le relais valide (fichier PHP lu : une dérive fait échouer ce test)', () {
      final php = File('../../apps/web/app/Relais/IndicateursClinique.php');
      if (!php.existsSync()) return; // relais absent d'une copie partielle du dépôt
      final src = php.readAsStringSync();
      for (final ch in ikChemins()) {
        final cle = ch.split('.').last.replaceAll('[]', '');
        expect(src.contains("'$cle'"), isTrue, reason: 'le relais ne connaît pas « $ch »');
      }
    });
  });
}
