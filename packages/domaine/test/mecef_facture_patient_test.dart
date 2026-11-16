// LA FACTURE D'UN PATIENT NE PORTE NI ACHETEUR NI AIB (Direction de Baguidi, 16/11/2026, E3770 à E3779) : la normalisation et la pièce imprimée d'une facture
// patient n'appliquent aucun AIB, quoi que la pièce ou un appelant fournisse ; la règle de la maquette (vecteurs) reste celle d'une vente à un tiers payeur.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  final vente = <String, Object?>{
    'numero': 'FN-TEST-1',
    'montantTTC': 10000,
    'montantPaye': 10000,
    'statutPaiement': 'soldee',
    'lignes': [
      {'id': 'L1', 'designation': 'Consultation', 'quantite': 1, 'prixUnitaire': 10000, 'partAssureur': 0, 'partPatient': 10000}
    ],
  };

  group('normalisation d’une facture patient', () {
    test('sans acheteur ni AIB : le patient paie le total, net = base', () {
      final p = preparerNormalisation(vente, facturePatient: true);
      expect(p.ok, isTrue);
      expect(p.acheteur!.ifu, isNull);
      expect(p.acheteur!.nom, isNull);
      expect(p.acheteur!.aibTaux, 0);
      expect(p.montants!.aib, 0);
      expect(p.montants!.net, p.montants!.base);
    });

    test('l’acheteur saisi, le taux par défaut et l’acheteur porté par la pièce ne sont PAS lus : aucun AIB, aucun refus d’acheteur', () {
      final ancienne = {...vente, 'ifuClient': '12', 'acheteurNom': 'X', 'aibTaux': 5};
      final p = preparerNormalisation(ancienne,
          facturePatient: true, acheteurSaisi: {'ifu': '12', 'nom': '', 'aibTaux': 5}, aibParDefaut: 5);
      expect(p.ok, isTrue, reason: 'un IFU invalide n’est plus contrôlé : il n’y a pas d’acheteur');
      expect(p.montants!.aib, 0);
    });

    test('porté puis corrigé : la règle d’avant (acheteur et AIB lus) reste celle d’une vente à un tiers payeur', () {
      final tiers = preparerNormalisation(vente, acheteurSaisi: {'ifu': '3201642748214', 'nom': 'Entreprise X', 'aibTaux': 5});
      expect(tiers.montants!.aib, 500);
      expect(preparerNormalisation(vente, acheteurSaisi: {'ifu': '12', 'nom': 'X'}).refus!.code, 'IFU_INVALIDE');
    });

    test('les refus qui ne tiennent pas à l’acheteur demeurent (pro-forma, règlement absent, montants)', () {
      expect(preparerNormalisation({...vente, 'proforma': true}, facturePatient: true).refus!.code, 'PROFORMA');
      expect(preparerNormalisation({...vente, 'montantPaye': 0}, facturePatient: true).refus!.code, 'VENTE_NON_ENCAISSEE');
      expect(preparerNormalisation({...vente, 'montantTTC': 10001}, facturePatient: true).refus!.code, 'TOTAL_INCOHERENT');
    });

    test('les champs d’une facture patient normalisée : ni IFU, ni nom, ni situation, ni repli, AIB nul', () {
      expect(champsFacturePatientSansAib, {
        'ifuClient': null,
        'acheteurNom': null,
        'aibTaux': 0,
        'aibSituation': null,
        'aibRepli': null,
        'aibMotif': null,
      });
      expect(acheteurFacturePatient.toJson()['aibTaux'], 0);
      expect(mecefMentionFacturePatient, contains('sans acheteur ni AIB'));
    });
  });

  group('pièce imprimée d’une facture patient', () {
    final f = {...vente, 'statutMecef': 'valide', 'numeroMecef': 'MECEF1234567'};
    List<String> taxes(FactureNormalisee fn) => [for (final r in fn.taxes.lignes) '${r['k']}'];

    test('aucune ligne d’AIB, net à payer = TTC, même si la pièce porte encore un taux', () {
      for (final t in [null, 0, 1, 5]) {
        final fn = factureNormalisee({...f, if (t != null) 'aibTaux': t}, const ParamFiscal(), facturePatient: true);
        expect(fn.netAPayer, 10000, reason: 'taux porté : $t');
        expect(taxes(fn).any((k) => k.contains('AIB')), isFalse, reason: 'taux porté : $t');
        expect(fn.enLettres, montantEnLettres(10000));
      }
    });

    test('porté puis corrigé : la pièce de la maquette (vente à un tiers) garde l’AIB du régime', () {
      final fn = factureNormalisee(f, const ParamFiscal());
      expect(fn.netAPayer, 10100);
      expect(taxes(fn).last, 'AIB 1 % (AIB2)');
    });
  });

  test('où l’acheteur et l’AIB gardent un sens : la facture d’un fournisseur et la vente à un tiers payeur, pas la caisse', () {
    final lieux = [for (final e in mecefSaisieAcheteurAibConservee) e.$1];
    expect(lieux, hasLength(2));
    expect(lieux.first, contains('fournisseur'));
    expect(lieux.last, contains('tiers payeur'));
    expect(lieux.any((l) => l.toLowerCase().contains('patient')), isFalse);
  });
}
