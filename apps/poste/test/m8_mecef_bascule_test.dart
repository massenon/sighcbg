// PRD Baguidi P0-5 : la bascule MECeF coupe VRAIMENT la normalisation au poste. L'état se lit dans `modulesActifs` (fermetures en vigueur), se passe
// aux moteurs du domaine et aux pièces imprimées. Module fermé : aucune pièce nouvelle ne porte de champ fiscal, le reçu et la facture imprimés
// n'affichent pas le bloc MECeF (l'IFU et le RCCM de l'en-tête légal restent), une pièce émise pendant que MECeF était ouvert garde ses champs.
// Vérifie aussi que les pièces de caisse lisent l'identité sur IdentiteClinique (P0-2), jamais une valeur recopiée.
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/parcours_caisse.dart';
import 'package:sigh_poste/impression/piece.dart';
import 'package:sigh_poste/modules/m8/commun.dart';

typedef F = Map<String, Object?>;

/// La fiche `modulesActifs` que pose la bascule « Activité des modules » pour le module MECEF entier.
F fermetureMecef({bool actif = false, String statut = 'actif'}) => {
      'id': 'MOD90',
      'code': 'MODULE-MECEF',
      'module': 'MECEF',
      'libelle': 'Module — MECeF',
      'actif': actif,
      'statut': statut,
      'motif': 'Hors périmètre Clinique Baguidi',
    };

F factureNormalisee() => {
      'id': 'F1',
      'numero': 'FN-2026-00001',
      'patient': 'AGENT Test',
      'patientCode': 'CBG/1/26',
      'date': '2026-11-06',
      'type': 'Consultation',
      'montantTTC': 5000,
      'partAssurance': 0,
      'partPatient': 5000,
      'montantPaye': 5000,
      'reliquat': 0,
      'modePaiement': 'especes',
      'statutPaiement': 'soldee',
      'statutMecef': 'valide',
      'baseMecef': 5000,
      'numeroMecef': 'MECEF1234567',
      'lignes': [
        {
          'id': 'L1',
          'categorie': 'consultation',
          'designation': 'Consultation',
          'quantite': 1,
          'prixUnitaire': 5000,
          'partPatient': 5000,
          'statutPaiement': 'paye'
        },
      ],
    };

List<String> rubriques(PieceA4 p) => [
      for (final b in p.blocs)
        if (b is BlocTableau)
          for (final l in b.tableau.lignes) '${l['k'] ?? ''}'
    ];

List<String> textes(PieceA4 p) =>
    [for (final b in p.blocs) if (b is BlocTexte) b.texte];

void main() {
  final auj = DateTime(2026, 11, 6);

  group('l’état du module se lit dans modulesActifs', () {
    test('aucune fiche : MECeF est ouvert par défaut', () {
      expect(mecefEnService(Magasin({})), isTrue);
    });
    test('fiche module entier : fermé ; archivée (RG-14) ou réouverte : ouvert', () {
      expect(mecefEnService(Magasin({'modulesActifs': [fermetureMecef()]})), isFalse);
      expect(mecefEnService(Magasin({'modulesActifs': [fermetureMecef(statut: 'archive')]})), isTrue);
      expect(mecefEnService(Magasin({'modulesActifs': [fermetureMecef(actif: true)]})), isTrue);
    });
  });

  group('la facture imprimée suit la bascule', () {
    test('MECeF ouvert : titre « Facture normalisée », base MECeF, identifiant fiscal', () {
      final p = pieceFacture(factureNormalisee(),
          utilisateur: 'Caissier', edite: auj, reference: 'REF-1');
      expect(p.titre, 'Facture normalisée');
      expect(rubriques(p), contains('Base normalisée MECeF'));
      expect(textes(p).join(' '), contains('Identifiant fiscal MECeF'));
    });

    test('MECeF fermé : aucun bloc MECeF, mais l’en-tête légal (RCCM) reste', () {
      final p = pieceFacture(factureNormalisee(),
          mecefActif: false,
          utilisateur: 'Caissier',
          edite: auj,
          reference: 'REF-1');
      expect(p.titre, 'Facture');
      expect(p.sousTitre, 'FN-2026-00001',
          reason: 'l’identifiant fiscal ne s’imprime pas module fermé');
      final tout = [...rubriques(p), ...textes(p)].join(' ');
      expect(tout.contains('MECeF'), isFalse);
      expect(textes(p).join(' '), contains('Mode de règlement'));
      expect(p.cartouche.any((x) => x.$1 == 'RCCM' && x.$2 == IdentiteClinique.rccm), isTrue,
          reason: 'l’IFU et le RCCM relèvent de l’en-tête légal, pas du dispositif');
    });
  });

  group('l’encaissement suit la bascule (orchestration du poste)', () {
    F piecePayable({bool emiseOuverte = false}) => {
          'id': 'F2',
          'numero': 'FN-2026-00002',
          'patient': 'AGENT Test',
          'patientCode': 'CBG/1/26',
          'date': '2026-11-06',
          'type': 'Consultation',
          'montantTTC': 5000,
          'partPatient': 5000,
          'montantPaye': 0,
          'reliquat': 5000,
          'statutPaiement': 'impayee',
          if (emiseOuverte) ...{'statutMecef': 'en_attente', 'baseMecef': 0.0},
          'lignes': [
            {
              'id': 'L1',
              'categorie': 'consultation',
              'designation': 'Consultation',
              'quantite': 1,
              'prixUnitaire': 5000,
              'partPatient': 5000,
              'statutPaiement': 'du'
            },
          ],
        };

    test('module fermé, pièce émise fermée : le versement n’écrit ni statutMecef ni baseMecef', () {
      final m = Magasin({
        'factures': [piecePayable()],
        'modulesActifs': [fermetureMecef()],
      })
        ..utilisateur = 'Caissier';
      final r = encaisserFacture(m, 'F2', montant: 5000, maintenant: auj);
      expect(r.restantDu, 0);
      final f = m.collection('factures').parId('F2')!;
      expect(f['statutPaiement'], 'soldee');
      expect(f.containsKey('statutMecef'), isFalse);
      expect(f.containsKey('baseMecef'), isFalse);
      expect(r.ecritures, isNotEmpty,
          reason: 'l’écriture comptable (RG-10) ne dépend pas de MECeF');
    });

    test('module fermé, pièce émise PENDANT l’ouverture : ses champs restent tels quels', () {
      final m = Magasin({
        'factures': [piecePayable(emiseOuverte: true)],
        'modulesActifs': [fermetureMecef()],
      })
        ..utilisateur = 'Caissier';
      encaisserFacture(m, 'F2', montant: 5000, maintenant: auj);
      final f = m.collection('factures').parId('F2')!;
      expect(f['statutMecef'], 'en_attente',
          reason: 'une pièce émise MECeF ouvert garde ses champs, jamais réécrits');
      expect(f['baseMecef'], 0.0);
      expect(f['statutPaiement'], 'soldee');
    });

    test('module rouvert (fiche archivée) : le versement reprend la tenue des champs', () {
      final m = Magasin({
        'factures': [piecePayable()],
        'modulesActifs': [fermetureMecef(statut: 'archive')],
      })
        ..utilisateur = 'Caissier';
      encaisserFacture(m, 'F2', montant: 5000, maintenant: auj);
      final f = m.collection('factures').parId('F2')!;
      // Lot L3 : le module rouvert reprend la tenue des champs fiscaux ; sans adaptateur configuré, la vente attend sa certification, SANS numéro fabriqué.
      expect(f['statutMecef'], 'en_attente');
      expect(f['codeRetour'], 'MECEF_NON_CONFIGURE');
      expect(f['numeroMecef'], isNull);
      expect(f['baseMecef'], 5000);
    });
  });

  group('l’identité des pièces de caisse se lit sur IdentiteClinique (P0-2)', () {
    test('le reçu nomme la clinique en vigueur, jamais une valeur recopiée', () {
      final p = pieceRecu(factureNormalisee(),
          utilisateur: 'Caissier', edite: auj, reference: 'REF-1');
      final t = textes(p).join(' ');
      expect(t, contains(IdentiteClinique.nom));
      expect(t.toUpperCase().contains('NASSIERA'), isFalse);
    });

    test('l’engagement de paiement nomme la clinique en vigueur', () {
      final p = pieceEngagement({
        ...factureNormalisee(),
        'reliquat': 5000,
        'engagement': {'montant': 5000, 'tranches': 2, 'modalite': 'echeancier', 'date': '2026-11-06'},
      }, utilisateur: 'Comptable', edite: auj, reference: 'REF-2');
      final t = textes(p).join(' ');
      expect(t, contains(IdentiteClinique.nom));
      expect(t.toUpperCase().contains('NASSIERA'), isFalse);
    });
  });
}
