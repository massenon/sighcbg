// PRD Baguidi P0-5 : la bascule MECeF coupe VRAIMENT la normalisation. L'état du module se LIT dans les fermetures en vigueur
// (`CfbFermetures.mecefEnService`) et se PASSE aux moteurs en paramètre : le domaine reste pur, sans dépendance au magasin.
// Module fermé, l'émission, l'encaissement, l'avoir et l'annulation ne posent AUCUN champ fiscal (mecef, statutMecef, baseMecef) ;
// une pièce émise pendant que MECeF était ouvert garde ses champs ; la réouverture rend les pièces suivantes normalisées.
// Le défaut (mecefActif absent) EST l'ouverture : les vecteurs d'emission_test, encaissement_test, avoir_test et remboursement_test
// continuent de vérifier le comportement d'avant, inchangé.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;

void main() {
  const patient = <String, Object?>{
    'id': 'P1',
    'nom': 'AGENT',
    'prenom': 'Test',
    'code': 'CBG/1/26',
  };

  List<M> lignesConsultation() => [
        ligneSaisie(
            nature: 'acte',
            designation: 'Consultation de médecine du travail',
            quantite: 1,
            prixUnitaire: 5000),
      ];

  ResultatEmission emettre({required bool mecefActif, num? reglement = 5000}) =>
      emettreFacture(
        patient: patient,
        lignes: lignesConsultation(),
        dateRepartition: '2026-11-06',
        dateFacture: '2026-11-06',
        type: 'Consultation',
        mode: 'especes',
        rangDebut: 0,
        reglement: reglement,
        mecefActif: mecefActif,
      );

  group('l’état du module se lit dans les fermetures en vigueur', () {
    test('aucune fiche : MECeF est OUVERT par défaut, rien ne change', () {
      expect(const CfbFermetures({}, {}).mecefEnService, isTrue);
      expect(CfbFermetures.depuis(const <M>[]).mecefEnService, isTrue);
    });

    test('la fiche module entier ferme ; archivée ou réouverte, elle ne ferme plus (RG-14)', () {
      M fiche({bool actif = false, String statut = 'actif'}) => {
            'code': 'MODULE-MECEF',
            'module': 'MECEF',
            'actif': actif,
            'statut': statut,
          };
      expect(CfbFermetures.depuis([fiche()]).mecefEnService, isFalse);
      expect(CfbFermetures.depuis([fiche(statut: 'archive')]).mecefEnService, isTrue,
          reason: 'une fiche archivée ne ferme plus rien');
      expect(CfbFermetures.depuis([fiche(actif: true)]).mecefEnService, isTrue,
          reason: 'la réouverture rend la normalisation');
    });

    test('la fermeture d’écrans NOMMÉS d’un autre module ne coupe pas la normalisation', () {
      final f = CfbFermetures.depuis([
        {'code': 'M5-BANQUE', 'module': 'M5', 'ecrans': ['m5-banque-sang'], 'actif': false, 'statut': 'actif'},
      ]);
      expect(f.mecefEnService, isTrue);
    });
  });

  group('émission (P0-5)', () {
    test('MECeF ouvert (défaut) : la pièce porte mecef, statutMecef et baseMecef', () {
      final p = emettre(mecefActif: true).pieces.single;
      expect(p['mecef'], isTrue);
      expect(p['statutMecef'], 'valide');
      expect(p['baseMecef'], 5000);
      // Le défaut du paramètre EST l'ouverture : un appelant qui ne dit rien garde le comportement d'avant.
      final defaut = emettreFacture(
          patient: patient,
          lignes: lignesConsultation(),
          dateRepartition: '2026-11-06',
          dateFacture: '2026-11-06',
          type: 'Consultation',
          mode: 'especes',
          rangDebut: 0,
          reglement: 5000).pieces.single;
      expect(defaut.containsKey('statutMecef'), isTrue);
    });

    test('MECeF fermé : AUCUN champ fiscal n’est posé ; le reste de la pièce est inchangé', () {
      final ouverte = emettre(mecefActif: true).pieces.single;
      final p = emettre(mecefActif: false).pieces.single;
      for (final k in ['mecef', 'statutMecef', 'baseMecef']) {
        expect(p.containsKey(k), isFalse, reason: '$k ne doit pas être posé');
      }
      // Même numéro, mêmes montants, même statut de paiement : seule la normalisation tombe.
      for (final k in ['numero', 'montantTTC', 'partPatient', 'montantPaye', 'reliquat', 'statutPaiement']) {
        expect(p[k], ouverte[k], reason: '$k doit rester celui de la pièce normalisée');
      }
      expect(p['statutPaiement'], 'soldee');
    });

    test('réouverture : les pièces suivantes redeviennent normalisées', () {
      final p = emettre(mecefActif: true).pieces.single;
      expect(p['mecef'], isTrue);
      expect(p['statutMecef'], 'valide');
    });
  });

  group('encaissement (P0-5)', () {
    M facturePayable({bool emiseOuverte = false}) => {
          'id': 'F1',
          'numero': 'FN-2026-00001',
          'patient': 'AGENT Test',
          'montantTTC': 5000,
          'partPatient': 5000,
          'montantPaye': 0,
          if (emiseOuverte) ...{'statutMecef': 'en_attente', 'baseMecef': 0.0},
          'lignes': [
            {'id': 'L1', 'designation': 'Consultation', 'partPatient': 5000},
          ],
        };

    test('MECeF fermé, pièce émise fermée : le versement ne pose ni statutMecef ni baseMecef', () {
      final r = encaisser(facturePayable(),
          montant: 5000,
          aujourdhui: '2026-11-06',
          maintenant: '2026-11-06T10:00:00.000Z',
          mecefActif: false);
      expect(r.facture['statutPaiement'], 'soldee');
      expect(r.facture.containsKey('statutMecef'), isFalse);
      expect(r.facture.containsKey('baseMecef'), isFalse);
      expect(r.ecritures, isNotEmpty, reason: 'l’écriture comptable (RG-10) ne dépend pas de MECeF');
    });

    test('pièce émise PENDANT que MECeF était ouvert : elle GARDE ses champs, jamais réécrits', () {
      final r = encaisser(facturePayable(emiseOuverte: true),
          montant: 5000,
          aujourdhui: '2026-11-06',
          maintenant: '2026-11-06T10:00:00.000Z',
          mecefActif: false);
      expect(r.facture['statutMecef'], 'en_attente',
          reason: 'le champ posé à l’émission reste tel quel');
      expect(r.facture['baseMecef'], 0.0,
          reason: 'la base normalisée n’est pas recalculée module fermé');
      expect(r.facture['statutPaiement'], 'soldee');
    });

    test('MECeF rouvert : le versement reprend la tenue des champs fiscaux', () {
      final r = encaisser(facturePayable(emiseOuverte: true),
          montant: 5000,
          aujourdhui: '2026-11-06',
          maintenant: '2026-11-06T10:00:00.000Z');
      expect(r.facture['statutMecef'], 'valide');
      expect(r.facture['baseMecef'], 5000);
    });
  });

  group('avoir et annulation (P0-5)', () {
    const facture = <String, Object?>{
      'id': 'F1',
      'numero': 'FN-2026-00001',
      'montantTTC': 5000,
      'statutMecef': 'valide',
      'statutPaiement': 'soldee',
      'montantPaye': 5000,
    };

    test('MECeF fermé : l’avoir ne pose pas statutMecef ; contre-passation et plafond inchangés', () {
      final r = emettreAvoir(
        facture: facture,
        idAvoir: 'AVR00001',
        lignes: const [
          {'designation': 'Consultation', 'montant': 2000}
        ],
        motif: 'Erreur de facturation',
        jour: '2026-11-06',
        utilisateur: 'Test',
        mecefActif: false,
      );
      expect(r.avoir.containsKey('statutMecef'), isFalse);
      expect(r.avoir['reference'], 'AV-2026-0001');
      expect(r.ecritures, hasLength(2));
      expect(r.ecritures[0]['debit'], r.ecritures[1]['credit'],
          reason: 'la contre-passation reste équilibrée (RG-10)');
    });

    test('MECeF ouvert (défaut) : l’avoir d’une facture normalisée validée reste « en_attente »', () {
      final r = emettreAvoir(
        facture: facture,
        idAvoir: 'AVR00001',
        lignes: const [
          {'designation': 'Consultation', 'montant': 2000}
        ],
        motif: 'Erreur de facturation',
        jour: '2026-11-06',
        utilisateur: 'Test',
      );
      expect(r.avoir['statutMecef'], 'en_attente');
    });

    test('MECeF fermé : l’annulation ne passe pas la facture en « rejeté » : aucune notification de rejet ne naît', () {
      final op = enregistrerOperation(
        saisie: const {
          'factureId': 'F1',
          'nature': 'Annulation',
          'date': '2026-11-06',
          'montant': 5000,
          'motif': 'Erreur de saisie',
          'autorisePar': 'Direction',
        },
        facture: facture,
        remboursements: const [],
        mecefActif: false,
      );
      expect(op.patchFacture, isNotNull);
      expect(op.patchFacture!['statutPaiement'], 'impayee');
      expect(op.patchFacture!['annulee'], isTrue);
      expect(op.patchFacture!.containsKey('statutMecef'), isFalse);
    });

    test('MECeF ouvert (défaut) : l’annulation passe bien la facture en « rejeté », comme avant', () {
      final op = enregistrerOperation(
        saisie: const {
          'factureId': 'F1',
          'nature': 'Annulation',
          'date': '2026-11-06',
          'montant': 5000,
          'motif': 'Erreur de saisie',
          'autorisePar': 'Direction',
        },
        facture: facture,
        remboursements: const [],
      );
      expect(op.patchFacture!['statutMecef'], 'rejete');
    });
  });
}
