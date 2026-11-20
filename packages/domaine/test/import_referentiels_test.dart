// LES SEPT JEUX DE RÉFÉRENTIELS (lot « jeux supplémentaires ») : natures de facture, centres de coûts, unités du laboratoire, catalogue de l'imagerie, prestataires, immobilisations, budgets.
// Par jeu : modèle, vérification sans écriture, erreurs nommées par ligne, doublon, taille, droit (matrice en force), écriture journalisée (RG-12), historique de lot sans valeur de cellule,
// annulation par archivage (RG-14) refusée sous une pièce qui s'appuie sur la fiche. Les règles propres : exercice clos (budgets), colonnes retirées (immobilisations, prestataires),
// « ignorer les existants » jamais accordé.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import 'import_test.dart' show MagasinMemoire;
import 'aide_documents_fiscaux.dart';

extension _Instantane on MagasinMemoire {
  /// Une copie du contenu (les tests de demande ont besoin d'un magasin par poste).
  Map<String, Object?> instantaneDe() => {for (final c in _collectionsConnues) c: [for (final f in toutes(c)) {...f}]};
}

const _collectionsConnues = ['exercices', 'centresCouts', 'comptes', 'naturesFacture', 'unitesLabo', 'examensImagerie', 'prestataires', 'immobilisations', 'budgets', 'factures', 'ecritures', 'variablesLabo', 'demandesImagerie'];

typedef Fiche = Map<String, Object?>;

ProfilImport profilDe(MatriceDroits m, String role) => ProfilImport(
    role: role,
    libelleRole: m.libelle(role) ?? role,
    droitEcran: (e) => m.droit(role, e));

/// L'en-tête du modèle puis une ligne par saisie : les cellules suivent l'ordre des colonnes du jeu, une clé absente se lit vide.
List<List<Object?>> fich(JeuImport j, List<Map<String, Object?>> lignes) => [
      [for (final c in j.colonnes) c.label],
      for (final l in lignes) [for (final c in j.colonnes) l[c.cle] ?? ''],
    ];

MagasinMemoire magasin(
        {ProfilImport profil = const ProfilImport.accordeTout(),
        String jour = '2026-11-01',
        bool sansExercices = false}) =>
    MagasinMemoire({
      'exercices': sansExercices
          ? <Object?>[]
          : [
              {'id': 'EX25', 'annee': 2025, 'etat': 'clos', 'statut': 'actif'},
              {
                'id': 'EX26',
                'annee': 2026,
                'etat': 'en_cloture',
                'statut': 'actif'
              },
              {
                'id': 'EX27',
                'annee': 2027,
                'etat': 'ouvert',
                'statut': 'actif'
              },
            ],
      'centresCouts': [
        {
          'id': 'CC1',
          'code': 'laboratoire',
          'libelle': 'Laboratoire',
          'type': 'exploitation',
          'statut': 'actif'
        },
      ],
      'comptes': [
        {
          'id': 'C1',
          'num': '241000',
          'libelle': 'Matériel et outillage',
          'statut': 'actif'
        },
        {'id': 'C2', 'num': '601000', 'libelle': 'Achats', 'statut': 'actif'},
        {
          'id': 'C3',
          'num': '281000',
          'libelle': 'Amortissements',
          'statut': 'actif'
        },
      ],
      'naturesFacture': [
        {
          'id': 'N1',
          'code': 'CONS',
          'libelle': 'Consultation généraliste',
          'secteur': 'Médecine générale',
          'ordre': 1,
          'statut': 'actif'
        },
      ],
      'unitesLabo': [
        {
          'id': 'U1',
          'symbole': 'G/l',
          'libelle': 'giga par litre',
          'domaine': 'Hématologie',
          'statut': 'actif'
        },
      ],
      'examensImagerie': [
        {
          'id': 'X1',
          'code': 'IMG-ECHO-PELV',
          'label': 'Échographie pelvienne',
          'modalite': 'echographie',
          'statut': 'actif'
        },
      ],
      'prestataires': [
        {
          'id': 'P1',
          'reference': 'PE-0003',
          'nom': 'Dr EXISTANT',
          'specialite': 'Chirurgie',
          'tarifActe': 20000,
          'actesRealises': 0,
          'ifu': '3202112446712',
          'statut': 'actif'
        },
      ],
      'immobilisations': [
        {
          'id': 'I1',
          'reference': 'IM-011',
          'designation': 'Autoclave',
          'categorie': 'Matériel médical',
          'dateAcquisition': '2024-05-02',
          'valeurAcquisition': 900000,
          'statut': 'actif'
        },
      ],
      'budgets': [
        {
          'id': 'B1',
          'reference': 'BG-2027-004',
          'exercice': 2027,
          'centreCout': 'laboratoire',
          'nature': 'Investissements',
          'prevu': 1000,
          'statut': 'actif'
        },
      ],
      'factures': <Object?>[],
      'ecritures': <Object?>[],
      'variablesLabo': <Object?>[],
      'demandesImagerie': <Object?>[],
    }, profilFixe: profil, jourFixe: jour);

final sept = <JeuImport>[
  jeuNaturesFacture,
  jeuCentresCouts,
  jeuUnitesLabo,
  jeuCatalogueImagerie,
  jeuPrestataires,
  jeuImmobilisations,
  jeuBudgets
];

/// Une ligne valide par jeu (le magasin ci-dessus n'en connaît aucune).
final Map<String, Map<String, Object?>> valide = {
  'natures-facture': {
    'code': 'ORTH',
    'libelle': 'Orthopédie',
    'secteur': 'Chirurgie'
  },
  'centres-couts': {
    'code': 'orthopedie',
    'libelle': 'Orthopédie',
    'type': 'Centre d’exploitation',
    'responsable': 'Dr X'
  },
  'unites-labo': {
    'symbole': 'µmol/l',
    'libelle': 'micromole par litre',
    'domaine': 'Biochimie'
  },
  'catalogue-imagerie': {
    'code': 'IMG-RAD-THO',
    'libelle': 'Radiographie du thorax',
    'modalite': 'Radiographie'
  },
  'prestataires': {
    'nom': 'Dr EXEMPLE',
    'specialite': 'Chirurgie',
    'tarifActe': 25000,
    'ifu': '3202112446799',
    'factureNormalisee': 'Oui'
  },
  'immobilisations': {
    'designation': 'Moniteur multiparamétrique',
    'categorie': 'Matériel médical',
    'dateAcquisition': '2026-03-15',
    'valeur': 1800000,
    'duree': 5,
    'compte': '241000'
  },
  'budgets': {
    'exercice': 2027,
    'centre': 'Laboratoire',
    'nature': 'Charges de fonctionnement',
    'prevu': 4200000
  },
};

void main() {
  brancherDocumentsFiscauxDeTest();
  final base = MatriceDroits.depuisJson(
      (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map)
          .cast<String, Object?>());

  group('déclaration', () {
    test('sept jeux de plus, identifiants et écrans uniques, tous au manifeste',
        () {
      expect(jeuxImport, hasLength(26));
      expect({for (final j in jeuxImport) j.id}, hasLength(26));
      expect({for (final j in jeuxImport) j.ecran}, hasLength(26));
      final manifeste = (jsonDecode(
              File('../referentiels/data/manifeste.json').readAsStringSync())
          as Map)['ecrans'] as List;
      final ids = {for (final e in manifeste) (e as Map)['id']};
      for (final j in sept) {
        expect(ids, contains(j.ecran), reason: j.id);
        expect(jeuImportParId(j.id), same(j));
        expect(jeuImportParEcran(j.ecran), same(j));
      }
    });

    test(
        'le classement : cinq référentiels de configuration (direct et demande, prestataires compris depuis le 14/11/2026), deux jeux restreints (direct seul), aucun réservé à la mère',
        () {
      final deLaMere = {
        ...cfbEssentielles,
        'utilisateurs',
        valCollectionValidations,
        parCollectionParametres
      }.difference({'rolesBase', 'modulesManifeste', 'reglages', 'audit'});
      final regime = RegimeDemandesImport(collectionsDeLaMere: deLaMere);
      expect({
        for (final j in sept)
          if (regime.exigeLaMere(j)) j.id
      }, {
        'natures-facture',
        'centres-couts',
        'unites-labo',
        'catalogue-imagerie',
        'prestataires'
      });
      expect({
        for (final j in sept)
          if (j.restreint) j.id
      }, {
        'immobilisations',
        'budgets'
      });
      expect({
        for (final j in sept)
          if (regime.reserveALaMere(j)) j.id
      }, isEmpty);
    });

    test(
        '« ignorer les existants » n\'est accordé à aucun des sept : chacun est le support d\'une pièce émise',
        () {
      for (final j in sept) {
        expect(j.ignorable, isFalse, reason: j.id);
      }
      expect({
        for (final j in jeuxImport)
          if (j.ignorable) j.id
      }, {
        'produits',
        'fournisseurs',
        'emplacements',
        'courriers'
      });
      for (final j in sept) {
        final a = analyserLignes(
            j, fich(j, [valide[j.id]!]), 'f.xlsx', magasin(),
            options: const OptionsImport(ignorerExistants: true));
        expect(a.accepte, isFalse, reason: j.id);
        expect(a.globaux.single.code, 'IGNORER_INTERDIT', reason: j.id);
      }
    });

    test(
        'la taille maximale par défaut est la borne courte (512 Ko), réglable par jeu en base',
        () {
      for (final j in sept) {
        expect(j.octetsMaxDefaut, octetsMaxImportCourt, reason: j.id);
      }
    });

    test('la liste des secteurs d\'activité est le réglage `listes.cfg.secteursActivite` (une source, jamais deux)', () {
      expect(importSecteursActivite, ListesReference.semence('listes.cfg.secteursActivite'));
      expect(importSecteursActivite.length, 8);
    });
  });

  group('modèle téléchargeable', () {
    for (final j in sept) {
      test(j.id, () {
        final port = magasin();
        final m = modeleImport(j, port);
        expect(m.donnees.first, [for (final c in j.colonnes) c.label],
            reason: 'les en-têtes exacts des colonnes');
        expect(m.donnees, hasLength(2), reason: 'une ligne d\'exemple');
        expect(m.instructions.expand((l) => l).join(' '), contains(j.libelle));
        // La ligne d'exemple laissée telle quelle n'est jamais importée.
        final a = analyserLignes(j, m.donnees, 'modele.xlsx', port);
        expect(a.accepte, isFalse);
        expect(a.globaux.map((p) => p.code), contains('FICHIER_VIDE'));
      });
    }
  });

  group('vérification sans écriture, erreurs nommées par ligne', () {
    test(
        'un fichier valide par jeu : accepté, RIEN d\'écrit avant la confirmation',
        () {
      for (final j in sept) {
        final port = magasin();
        final avant = {for (final c in j.cibles) c: port.toutes(c).length};
        final a = analyserLignes(j, fich(j, [valide[j.id]!]), 'f.xlsx', port);
        expect(a.accepte, isTrue,
            reason: '${j.id} : ${[
              for (final p in a.problemes) '${p.code} ${p.motif}'
            ]}');
        expect({for (final c in j.cibles) c: port.toutes(c).length}, avant,
            reason: '${j.id} : la vérification n\'écrit rien');
        expect(port.toutes(collectionLots), isEmpty);
      }
    });

    ProblemeImport refus(JeuImport j, Map<String, Object?> v, String code,
        {MagasinMemoire? port, List<Map<String, Object?>> avant = const []}) {
      final a = analyserLignes(
          j, fich(j, [...avant, v]), 'f.xlsx', port ?? magasin());
      expect(a.accepte, isFalse, reason: '${j.id} $code');
      final p = a.problemes.where((p) => p.code == code).toList();
      expect(p, isNotEmpty,
          reason: '${j.id} : ${[for (final x in a.problemes) x.code]}');
      expect(p.first.n, avant.length + 2,
          reason: 'la ligne du fichier est nommée');
      expect(p.first.geste, isNotEmpty,
          reason: 'le geste de correction est nommé');
      return p.first;
    }

    test(
        'natures de facture : code invalide, secteur hors liste, code ou libellé tenu, champ obligatoire',
        () {
      expect(
          refus(
                  jeuNaturesFacture,
                  {...valide['natures-facture']!, 'code': 'A B'},
                  'FORMAT_INVALIDE')
              .colonne,
          'Code');
      expect(
          refus(
                  jeuNaturesFacture,
                  {...valide['natures-facture']!, 'secteur': 'Astronomie'},
                  'VALEUR_HORS_LISTE')
              .colonne,
          'Secteur émetteur');
      expect(
          refus(
                  jeuNaturesFacture,
                  {...valide['natures-facture']!, 'code': 'cons'},
                  'DOUBLON_MAGASIN')
              .motif,
          contains('existe déjà'));
      expect(
          refus(
                  jeuNaturesFacture,
                  {
                    ...valide['natures-facture']!,
                    'libelle': 'consultation généraliste'
                  },
                  'DOUBLON_MAGASIN')
              .motif,
          contains('code CONS'));
      expect(
          refus(
                  jeuNaturesFacture,
                  {...valide['natures-facture']!, 'libelle': ''},
                  'CHAMP_OBLIGATOIRE')
              .colonne,
          'Nature de la facture');
    });

    test(
        'centres de coûts : code tenu en majuscules comme en minuscules, type hors liste, code invalide ; un responsable absent est signalé, pas refusé',
        () {
      expect(
          refus(
                  jeuCentresCouts,
                  {...valide['centres-couts']!, 'code': 'LABORATOIRE'},
                  'DOUBLON_MAGASIN')
              .motif,
          contains('existe déjà'));
      expect(
          refus(jeuCentresCouts, {...valide['centres-couts']!, 'type': 'Autre'},
                  'VALEUR_HORS_LISTE')
              .colonne,
          'Type');
      expect(
          refus(jeuCentresCouts, {...valide['centres-couts']!, 'code': 'a'},
                  'FORMAT_INVALIDE')
              .colonne,
          'Code');
      final a = analyserLignes(
          jeuCentresCouts,
          fich(jeuCentresCouts, [
            {...valide['centres-couts']!, 'responsable': ''}
          ]),
          'f.xlsx',
          magasin());
      expect(a.accepte, isTrue);
      expect(a.problemes.map((p) => p.code), ['SANS_RESPONSABLE']);
    });

    test(
        'unités : la casse COMPTE (G/l existe, g/l est une autre unité), domaine hors liste ; chaque unité naît « à confirmer »',
        () {
      expect(
          refus(jeuUnitesLabo, {...valide['unites-labo']!, 'symbole': 'G/l'},
                  'DOUBLON_MAGASIN')
              .motif,
          contains('G/l'));
      final distincte = analyserLignes(
          jeuUnitesLabo,
          fich(jeuUnitesLabo, [
            {...valide['unites-labo']!, 'symbole': 'g/l'}
          ]),
          'f.xlsx',
          magasin());
      expect(distincte.accepte, isTrue,
          reason:
              'g/l (gramme par litre) n\'est pas G/l (giga par litre) : ne jamais normaliser');
      expect(
          refus(
                  jeuUnitesLabo,
                  {...valide['unites-labo']!, 'domaine': 'Cuisine'},
                  'VALEUR_HORS_LISTE')
              .colonne,
          'Domaine');
      expect(distincte.problemes.map((p) => p.code), contains('A_CONFIRMER'));
    });

    test(
        'catalogue de l\'imagerie : modalité hors liste, code tenu, code invalide ; l\'examen naît « à valider » et sans variables',
        () {
      expect(
          refus(
                  jeuCatalogueImagerie,
                  {...valide['catalogue-imagerie']!, 'modalite': 'Télépathie'},
                  'VALEUR_HORS_LISTE')
              .colonne,
          'Modalité');
      expect(
          refus(
                  jeuCatalogueImagerie,
                  {...valide['catalogue-imagerie']!, 'code': 'img-echo-pelv'},
                  'DOUBLON_MAGASIN')
              .motif,
          contains('existe déjà'));
      expect(
          refus(
                  jeuCatalogueImagerie,
                  {...valide['catalogue-imagerie']!, 'code': 'x y'},
                  'FORMAT_INVALIDE')
              .colonne,
          'Code examen');
      final a = analyserLignes(
          jeuCatalogueImagerie,
          fich(jeuCatalogueImagerie, [valide['catalogue-imagerie']!]),
          'f.xlsx',
          magasin());
      expect(a.problemes.map((p) => p.code),
          containsAll(['A_VALIDER', 'SANS_VARIABLES']));
    });

    test(
        'prestataires : IFU invalide, nom ou IFU tenu, tarif négatif, tiret refusé ; zéro signalé ; colonnes « N° » et « Actes réalisés » refusées',
        () {
      expect(
          refus(jeuPrestataires, {...valide['prestataires']!, 'ifu': '123'},
                  'FORMAT_INVALIDE')
              .colonne,
          'IFU du prestataire');
      expect(
          refus(
                  jeuPrestataires,
                  {...valide['prestataires']!, 'nom': 'dr existant', 'ifu': ''},
                  'DOUBLON_MAGASIN')
              .motif,
          contains('existe déjà'));
      expect(
          refus(
                  jeuPrestataires,
                  {...valide['prestataires']!, 'ifu': '3202112446712'},
                  'DOUBLON_MAGASIN')
              .motif,
          contains('IFU'));
      expect(
          refus(jeuPrestataires, {...valide['prestataires']!, 'tarifActe': -5},
                  'HORS_BORNES')
              .colonne,
          'Tarif par acte (FCFA)');
      expect(
          refus(jeuPrestataires, {...valide['prestataires']!, 'tarifActe': '-'},
                  'TYPE_INVALIDE')
              .colonne,
          'Tarif par acte (FCFA)');
      final zero = analyserLignes(
          jeuPrestataires,
          fich(jeuPrestataires, [
            {...valide['prestataires']!, 'tarifActe': 0}
          ]),
          'f.xlsx',
          magasin());
      expect(zero.accepte, isTrue);
      expect(zero.problemes.map((p) => p.code), contains('TARIF_NUL'));
      for (final retiree in ['Actes réalisés', 'N°']) {
        final f = fich(jeuPrestataires, [valide['prestataires']!]);
        f.first.add(retiree);
        f[1].add(5);
        final a = analyserLignes(jeuPrestataires, f, 'f.xlsx', magasin());
        expect(a.accepte, isFalse, reason: retiree);
        expect(a.globaux.single.code, 'COLONNE_RETIREE');
        expect(a.globaux.single.colonne, retiree);
      }
    });

    test(
        'immobilisations : date future, bien cédé, compte inconnu ou hors classes 21 à 27, valeur nulle, durée hors bornes, référence ou bien identique tenu',
        () {
      final v = valide['immobilisations']!;
      expect(
          refus(jeuImmobilisations, {...v, 'dateAcquisition': '2026-12-31'},
                  'DATE_FUTURE')
              .colonne,
          'Date d’acquisition');
      expect(
          refus(jeuImmobilisations, {...v, 'etat': 'Cédé'}, 'BIEN_CEDE')
              .colonne,
          'État');
      expect(
          refus(jeuImmobilisations, {...v, 'compte': '999999'},
                  'COMPTE_INCONNU')
              .colonne,
          'Compte d’immobilisation');
      expect(
          refus(jeuImmobilisations, {...v, 'compte': '601000'},
                  'COMPTE_NON_IMMOBILISATION')
              .motif,
          contains('classes 21 à 27'));
      expect(
          refus(jeuImmobilisations, {...v, 'compte': '281000'},
                  'COMPTE_NON_IMMOBILISATION')
              .motif,
          contains('classes 21 à 27'),
          reason:
              'la classe 28 porte les amortissements : ce n\'est pas un compte de bien');
      expect(
          refus(jeuImmobilisations, {...v, 'valeur': 0}, 'VALEUR_NULLE')
              .colonne,
          'Valeur d’acquisition (FCFA)');
      expect(
          refus(jeuImmobilisations, {...v, 'duree': 40}, 'HORS_BORNES').colonne,
          'Durée d’amortissement (années)');
      expect(
          refus(jeuImmobilisations, {...v, 'reference': 'im-011'},
                  'DOUBLON_MAGASIN')
              .motif,
          contains('IM-011'));
      expect(
          refus(
                  jeuImmobilisations,
                  {
                    'designation': 'AUTOCLAVE',
                    'categorie': 'Matériel médical',
                    'dateAcquisition': '2024-05-02',
                    'valeur': 900000,
                    'duree': 5,
                    'compte': '241000'
                  },
                  'DOUBLON_MAGASIN')
              .motif,
          contains('identique'));
    });

    test(
        'immobilisations : les colonnes de cession, d\'amortissement et de valeur nette sont REFUSÉES en les nommant, jamais ignorées',
        () {
      for (final retiree in [
        'Date de cession',
        'Prix de cession',
        'Motif de la sortie',
        'Amortissement cumulé',
        'Valeur nette comptable',
        'Dotation'
      ]) {
        final f = fich(jeuImmobilisations, [valide['immobilisations']!]);
        f.first.add(retiree);
        f[1].add('x');
        final a = analyserLignes(jeuImmobilisations, f, 'f.xlsx', magasin());
        expect(a.accepte, isFalse, reason: retiree);
        expect(a.globaux.map((p) => p.code), ['COLONNE_RETIREE'],
            reason: retiree);
        expect(a.globaux.single.colonne, retiree);
      }
    });

    test(
        'immobilisations : un bien d\'un exercice clos ou en clôture est REPRIS en le disant (aucune écriture n\'est posée) ; un exercice ouvert est muet',
        () {
      final v = valide['immobilisations']!;
      final clos = analyserLignes(
          jeuImmobilisations,
          fich(jeuImmobilisations, [
            {...v, 'dateAcquisition': '2025-06-01'}
          ]),
          'f.xlsx',
          magasin());
      expect(clos.accepte, isTrue);
      expect(clos.problemes.single.code, 'EXERCICE_NON_OUVERT');
      expect(clos.problemes.single.motif, contains('clos'));
      final cloture = analyserLignes(
          jeuImmobilisations,
          fich(jeuImmobilisations, [
            {...v, 'dateAcquisition': '2026-03-15'}
          ]),
          'f.xlsx',
          magasin());
      expect(cloture.problemes.single.motif, contains('clôture'));
      final ouvert = analyserLignes(
          jeuImmobilisations,
          fich(jeuImmobilisations, [
            {...v, 'dateAcquisition': '2027-01-01'}
          ]),
          'f.xlsx',
          magasin(jour: '2027-06-01', sansExercices: true));
      expect(ouvert.problemes, isEmpty);
    });

    test(
        'budgets : exercice clos et exercice en clôture refusés en les nommant, centre inconnu, nature hors liste, doublon exercice + centre + nature, réalisé refusé',
        () {
      final v = valide['budgets']!;
      expect(refus(jeuBudgets, {...v, 'exercice': 2025}, 'EXERCICE_CLOS').motif,
          contains('clos'));
      expect(
          refus(jeuBudgets, {...v, 'exercice': 2026}, 'EXERCICE_EN_CLOTURE')
              .motif,
          contains('clôture'));
      expect(
          refus(jeuBudgets, {...v, 'centre': 'Inconnu'}, 'VALEUR_HORS_LISTE')
              .colonne,
          'Centre de coûts');
      expect(
          refus(jeuBudgets, {...v, 'nature': 'Divers'}, 'VALEUR_HORS_LISTE')
              .colonne,
          'Nature budgétaire');
      expect(
          refus(jeuBudgets, {...v, 'nature': 'investissements'},
                  'DOUBLON_MAGASIN')
              .motif,
          contains('BG-2027-004'));
      expect(refus(jeuBudgets, {...v, 'prevu': -1}, 'HORS_BORNES').colonne,
          'Montant prévisionnel (FCFA)');
      final f = fich(jeuBudgets, [v]);
      f.first.add('Réalisé');
      f[1].add(1000);
      final a = analyserLignes(jeuBudgets, f, 'f.xlsx', magasin());
      expect(a.globaux.single.code, 'COLONNE_RETIREE');
    });

    test(
        'un doublon DANS le fichier est refusé en nommant l\'autre ligne (chaque jeu)',
        () {
      for (final j in sept) {
        final p =
            refus(j, valide[j.id]!, 'DOUBLON_FICHIER', avant: [valide[j.id]!]);
        expect(p.motif, contains('ligne 2'), reason: j.id);
      }
    });
  });

  group('taille maximale', () {
    for (final j in sept) {
      test(
          '${j.id} : au-delà de la borne le fichier n\'est pas lu, il est refusé en le nommant ; la borne réglée en base l\'emporte sur le défaut',
          () {
        final port = magasin();
        final f = fich(j, [valide[j.id]!]);
        final trop = analyserFichier(j, f, 'gros.xlsx', port,
            octets: 600 * 1024, octetsMax: j.octetsMaxDefaut);
        expect(trop.accepte, isFalse);
        expect(trop.globaux.single.code, 'FICHIER_TROP_GROS');
        expect(trop.nbLignes, 0, reason: 'le fichier n\'a pas été lu');
        final releve = analyserFichier(j, f, 'gros.xlsx', port,
            octets: 600 * 1024, octetsMax: 2 * 1024 * 1024);
        expect(releve.accepte, isTrue,
            reason: 'une borne relevée par l\'administrateur laisse passer');
      });
    }
  });

  group('le droit d\'importer, lu de la matrice en force', () {
    test('importer = voir ET éditer l\'écran du jeu : la matrice d\'origine',
        () {
      bool peut(String role, JeuImport j) =>
          profilDe(base, role).peutImporterEcran(j.ecran);
      for (final r in ['da', 'admin']) {
        for (final j in sept) {
          expect(peut(r, j), isTrue, reason: '$r ${j.id}');
        }
      }
      expect(
          peut('direction', jeuNaturesFacture) &&
              peut('direction', jeuCentresCouts) &&
              peut('direction', jeuCatalogueImagerie),
          isTrue);
      expect(
          peut('direction', jeuBudgets) ||
              peut('direction', jeuPrestataires) ||
              peut('direction', jeuImmobilisations),
          isFalse,
          reason:
              'la Direction lit, la saisie financière est à la DAF et au comptable');
      expect(peut('laborantin', jeuUnitesLabo), isTrue);
      expect(peut('laborantin', jeuBudgets), isFalse);
      expect([
        peut('comptable', jeuImmobilisations),
        peut('comptable', jeuBudgets),
        peut('comptable', jeuNaturesFacture),
        peut('comptable', jeuPrestataires)
      ], [
        true,
        true,
        false,
        false
      ]);
      for (final r in [
        'medecin',
        'caissier',
        'reception',
        'stock',
        'infirmier'
      ]) {
        for (final j in sept) {
          expect(peut(r, j), isFalse, reason: '$r ${j.id}');
        }
      }
    });

    test(
        'le moteur REFUSE sans le droit, nommé, sans rien écrire ni consigner (chaque jeu)',
        () {
      for (final j in sept) {
        final port = magasin(profil: profilDe(base, 'medecin'));
        final a = analyserFichier(j, fich(j, [valide[j.id]!]), 'f.xlsx', port);
        expect(a.refusDroit, isTrue, reason: j.id);
        expect(a.globaux.single.code, 'DROIT_IMPORT_REFUSE');
        expect(a.globaux.single.motif, contains(j.ecran));
        expect(consigner(j, a, port), isNull,
            reason: 'un refus de droit ne se consigne pas');
        final ok =
            analyserLignes(j, fich(j, [valide[j.id]!]), 'f.xlsx', magasin());
        final r = appliquer(j, ok, port);
        expect(r.ok, isFalse);
        expect(r.code, 'DROIT_IMPORT_REFUSE');
        expect(port.toutes(collectionLots), isEmpty);
      }
    });
  });

  group('écriture, journal, historique, annulation', () {
    test(
        'chaque jeu : la fiche écrite est celle de l\'écran, le lot est journalisé (RG-12) et ne garde AUCUNE valeur de cellule',
        () {
      for (final j in sept) {
        final port = magasin();
        final a =
            analyserLignes(j, fich(j, [valide[j.id]!]), 'fichier.xlsx', port);
        final r = appliquer(j, a, port);
        expect(r.ok, isTrue, reason: '${j.id} ${r.code} ${r.motif}');
        expect(r.ecrits, 1);
        expect(port.journal.where((x) => x.startsWith('Import|LotImport|')),
            hasLength(1),
            reason: j.id);
        final ecrite = port
            .toutes(j.cibles.first)
            .firstWhere((f) => f['lotImport'] == r.lot!['reference']);
        expect(ecrite['validePar'], 'ADMIN TEST');
        expect(ecrite['dateImport'], '2026-11-01');
        expect('${ecrite['source']}', contains(j.libelle));
        expect(jsonEncode(r.lot), isNot(contains('mmol')),
            reason: 'le lot ne cite pas le contenu');
      }
    });

    test(
        'le lot REFUSÉ est consigné sans valeur de cellule ni motif qui la cite (historique lu par d\'autres que l\'auteur)',
        () {
      final j = jeuPrestataires;
      final port = magasin();
      final a = analyserLignes(
          j,
          fich(j, [
            {...valide['prestataires']!, 'ifu': 'SECRET-IFU'}
          ]),
          'f.xlsx',
          port);
      final lot = consigner(j, a, port)!;
      expect(lot['etat'], 'refuse');
      for (final e in (lot['erreurs'] as List).cast<Map>()) {
        expect(e.keys.toSet(), {'n', 'colonne', 'code', 'niveau', 'geste'});
      }
      expect(jsonEncode(lot), isNot(contains('SECRET-IFU')));
    });

    test(
        'natures de facture : l\'ordre suit le rang de l\'écran, le code s\'écrit en majuscules',
        () {
      final port = magasin();
      final j = jeuNaturesFacture;
      final a = analyserLignes(
          j,
          fich(j, [
            valide[j.id]!,
            {
              'code': 'pedi',
              'libelle': 'Pédiatrie',
              'secteur': 'Médecine générale'
            }
          ]),
          'f.xlsx',
          port);
      expect(appliquer(j, a, port).ok, isTrue);
      final n = {
        for (final x in port.actives('naturesFacture')) x['code']: x['ordre']
      };
      expect(n, {'CONS': 1, 'ORTH': 2, 'PEDI': 3});
    });

    test(
        'prestataires : numéro PE attribué à la suite, actes réalisés à zéro, facture normalisée en booléen',
        () {
      final port = magasin();
      final j = jeuPrestataires;
      final a = analyserLignes(
          j,
          fich(j, [
            valide[j.id]!,
            {
              ...valide[j.id]!,
              'nom': 'Dr AUTRE',
              'ifu': '',
              'factureNormalisee': 'Non'
            }
          ]),
          'f.xlsx',
          port);
      expect(appliquer(j, a, port).ok, isTrue);
      final neufs = port
          .actives('prestataires')
          .where((x) => x['lotImport'] != null)
          .toList();
      expect({for (final x in neufs) x['nom']: x['reference']},
          {'Dr EXEMPLE': 'PE-0004', 'Dr AUTRE': 'PE-0005'});
      expect(neufs.every((x) => x['actesRealises'] == 0), isTrue);
      expect({for (final x in neufs) x['nom']: x['factureNormalisee']},
          {'Dr EXEMPLE': true, 'Dr AUTRE': false});
    });

    test(
        'immobilisations : les numéros EXPLICITES d\'abord, puis IM-NNN à la suite du registre ; la fiche porte les champs de l\'écran, sans cession',
        () {
      final port = magasin();
      final j = jeuImmobilisations;
      final v = valide[j.id]!;
      final a = analyserLignes(
          j,
          fich(j, [
            v,
            {...v, 'designation': 'Scialytique', 'reference': 'IM-012'},
            {...v, 'designation': 'Aspirateur'}
          ]),
          'f.xlsx',
          port);
      expect(a.accepte, isTrue,
          reason: '${[for (final p in a.problemes) p.code]}');
      expect(appliquer(j, a, port).ok, isTrue);
      final refs = {
        for (final x in port.actives('immobilisations'))
          x['designation']: x['reference']
      };
      expect(refs['Scialytique'], 'IM-012');
      expect(refs['Moniteur multiparamétrique'], 'IM-013',
          reason:
              'un numéro automatique ne prend jamais celui que le fichier porte plus bas');
      expect(refs['Aspirateur'], 'IM-014');
      final f = port
          .actives('immobilisations')
          .firstWhere((x) => x['designation'] == 'Aspirateur');
      expect(f['valeurAcquisition'], 1800000);
      expect(f['dureeAmortissement'], 5);
      expect(f['compte'], '241000');
      expect(f['etat'], 'En service');
      expect(f['dateCession'], '');
    });

    test(
        'budgets : BG-AAAA-NNN à la suite des budgets de l\'exercice, le centre porte son intitulé',
        () {
      final port = magasin();
      final j = jeuBudgets;
      final a = analyserLignes(
          j,
          fich(j, [
            valide[j.id]!,
            {...valide[j.id]!, 'nature': 'Charges de personnel'}
          ]),
          'f.xlsx',
          port);
      expect(appliquer(j, a, port).ok, isTrue);
      final neufs =
          port.actives('budgets').where((x) => x['lotImport'] != null).toList();
      expect({
        for (final x in neufs) x['nature']: x['reference']
      }, {
        'Charges de fonctionnement': 'BG-2027-005',
        'Charges de personnel': 'BG-2027-006'
      });
      expect(
          neufs.every((x) =>
              x['centreCout'] == 'laboratoire' &&
              x['centre'] == 'Laboratoire' &&
              x['exercice'] == 2027),
          isTrue);
    });

    test(
        'catalogue de l\'imagerie : la fiche porte la modalité, son icône, « à valider » ; l\'intitulé va au champ label de l\'écran',
        () {
      final port = magasin();
      final j = jeuCatalogueImagerie;
      final a = analyserLignes(
          j,
          fich(j, [
            {...valide[j.id]!, 'modalite': 'irm'}
          ]),
          'f.xlsx',
          port);
      expect(appliquer(j, a, port).ok, isTrue);
      final f = port
          .actives('examensImagerie')
          .firstWhere((x) => x['lotImport'] != null);
      expect(f['modalite'], 'irm');
      expect(f['icone'], 'magnet');
      expect(f['label'], 'Radiographie du thorax');
      expect(f['aValider'], true);
    });

    test(
        'le même fichier réimporté après application est un doublon (rien n\'est écrit deux fois) : refus nommé ou lot déjà importé',
        () {
      for (final j in sept) {
        final port = magasin();
        final a = analyserLignes(j, fich(j, [valide[j.id]!]), 'f.xlsx', port);
        expect(appliquer(j, a, port).ok, isTrue, reason: j.id);
        final nb = port.toutes(j.cibles.first).length;
        final b = analyserLignes(j, fich(j, [valide[j.id]!]), 'f.xlsx', port);
        final r = b.accepte ? appliquer(j, b, port) : null;
        expect(r?.ok ?? false, isFalse, reason: j.id);
        expect(port.toutes(j.cibles.first).length, nb, reason: j.id);
      }
    });

    test(
        'annulation d\'un lot : les fiches sont ARCHIVÉES (RG-14), jamais supprimées',
        () {
      for (final j in sept) {
        final port = magasin();
        final r = appliquer(j,
            analyserLignes(j, fich(j, [valide[j.id]!]), 'f.xlsx', port), port);
        final avant = port.toutes(j.cibles.first).length;
        final an =
            annulerLot(jeuImportParId, r.lot!['id'], 'erreur de fichier', port);
        expect(an.ok, isTrue, reason: '${j.id} ${an.code}');
        expect(an.archives, 1);
        expect(port.toutes(j.cibles.first), hasLength(avant),
            reason: 'rien n\'est supprimé');
        expect(
            port
                .toutes(j.cibles.first)
                .where((f) => f['lotImport'] == r.lot!['reference'])
                .single['statut'],
            'archive');
      }
    });

    ResultatImport annulerSous(JeuImport j,
        void Function(MagasinMemoire port, FicheImport ecrite) pieceEmise) {
      final port = magasin();
      final r = appliquer(
          j, analyserLignes(j, fich(j, [valide[j.id]!]), 'f.xlsx', port), port);
      expect(r.ok, isTrue);
      final ecrite = port
          .toutes(j.cibles.first)
          .firstWhere((f) => f['lotImport'] == r.lot!['reference']);
      pieceEmise(port, ecrite);
      final an = annulerLot(jeuImportParId, r.lot!['id'], null, port);
      expect(ecrite['statut'], 'actif', reason: 'refusée : la fiche reste');
      return an;
    }

    test(
        'annulation REFUSÉE en nommant la pièce qui s\'appuie sur la fiche (sept dépendances)',
        () {
      var r = annulerSous(
          jeuNaturesFacture,
          (p, e) => p.toutes('factures').add({
                'id': 'F1',
                'numero': 'FA-1',
                'type': e['libelle'],
                'statut': 'actif'
              }));
      expect([r.code, r.motif], ['NATURE_UTILISEE', contains('FA-1')]);
      r = annulerSous(
          jeuCentresCouts,
          (p, e) => p.toutes('ecritures').add({
                'id': 'E1',
                'piece': 'P-9',
                'centreCout': e['code'],
                'statut': 'actif'
              }));
      expect([r.code, r.motif], ['CENTRE_IMPUTE', contains('P-9')]);
      r = annulerSous(
          jeuCentresCouts,
          (p, e) => p.toutes('budgets').add({
                'id': 'B9',
                'reference': 'BG-2027-009',
                'centreCout': e['code'],
                'statut': 'actif'
              }));
      expect(r.code, 'CENTRE_BUDGETE');
      r = annulerSous(
          jeuUnitesLabo,
          (p, e) => p.toutes('variablesLabo').add({
                'id': 'V1',
                'libelle': 'Glycémie',
                'unite': e['symbole'],
                'statut': 'actif'
              }));
      expect([r.code, r.motif], ['UNITE_UTILISEE', contains('Glycémie')]);
      r = annulerSous(
          jeuCatalogueImagerie,
          (p, e) => p.toutes('demandesImagerie').add({
                'id': 'D1',
                'reference': 'IMG-77',
                'examenCode': e['code'],
                'statut': 'actif'
              }));
      expect([r.code, r.motif], ['EXAMEN_DEMANDE', contains('IMG-77')]);
      r = annulerSous(jeuPrestataires, (p, e) => e['actesRealises'] = 3);
      expect(r.code, 'PRESTATAIRE_EN_ACTIVITE');
      r = annulerSous(
          jeuImmobilisations, (p, e) => e['dateCession'] = '2026-10-01');
      expect(r.code, 'BIEN_CEDE_DEPUIS');
      r = annulerSous(
          jeuBudgets,
          (p, e) => p
              .toutes('exercices')
              .firstWhere((x) => x['annee'] == 2027)['etat'] = 'clos');
      expect(r.code, 'EXERCICE_CLOS');
    });
  });

  group(
      'la garde d\'exercice clos sur les budgets (au moteur, pas seulement à l\'import)',
      () {
    test(
        'cpcGardeBudgets : refus nommé sur un exercice clos, silence sur un exercice ouvert ou en clôture',
        () {
      final ex = [
        {'annee': 2025, 'etat': 'clos', 'statut': 'actif'},
        {'annee': 2026, 'etat': 'en_cloture', 'statut': 'actif'},
        {'annee': 2027, 'etat': 'ouvert', 'statut': 'actif'},
      ];
      expect(cpcGardeBudgets(ex, 2025), contains('clôturé'));
      expect(cpcGardeBudgets(ex, '2025'), isNotNull);
      expect(cpcGardeBudgets(ex, 2026), isNull,
          reason:
              'en clôture : la budgétisation de l\'écran reste ouverte, seul l\'import la refuse');
      expect(cpcGardeBudgets(ex, 2027), isNull);
      expect(cpcGardeBudgets(ex, null), isNull);
      expect(cpcGardeBudgets(const [], 2024), isNotNull,
          reason: 'un exercice de la liasse déposée est clos sans fiche');
    });

    test(
        'un exercice clôturé ENTRE l\'analyse et la confirmation : le rejeu refuse, rien n\'est écrit',
        () {
      final port = magasin();
      final a = analyserLignes(
          jeuBudgets,
          fich(jeuBudgets, [
            valide['budgets']!,
            {...valide['budgets']!, 'nature': 'Charges de personnel'}
          ]),
          'f.xlsx',
          port);
      expect(a.accepte, isTrue);
      port.toutes('exercices').firstWhere((e) => e['annee'] == 2027)['etat'] =
          'clos';
      final r = appliquer(jeuBudgets, a, port);
      expect(r.ok, isFalse);
      expect(r.code, 'MAGASIN_CHANGE',
          reason:
              'le rejeu de l\'analyse refuse l\'exercice clos avant d\'écrire');
      expect(port.actives('budgets'), hasLength(1),
          reason: 'rien n\'est écrit');
    });
  });

  group('la demande d\'import à la mère : un groupe direct et demande, un groupe direct seul', () {
    final deLaMere = {...cfbEssentielles, 'utilisateurs', valCollectionValidations, parCollectionParametres}.difference({'rolesBase', 'modulesManifeste', 'reglages', 'audit'});
    final regime = RegimeDemandesImport(collectionsDeLaMere: deLaMere);
    PortImportMemoire poste(String role, String prefixe, {Map<String, Object?>? jeu}) =>
        PortImportMemoire(jeu ?? magasin().instantaneDe(), profilFixe: profilDe(base, role), utilisateurFixe: 'AGENT $role', prefixeId: prefixe, jourFixe: '2026-11-01');

    for (final cas in [
      ('natures-facture', jeuNaturesFacture, 'da', 'naturesFacture'),
      ('centres-couts', jeuCentresCouts, 'da', 'centresCouts'),
      ('unites-labo', jeuUnitesLabo, 'laborantin', 'unitesLabo'),
      ('catalogue-imagerie', jeuCatalogueImagerie, 'da', 'examensImagerie'),
      // Décision de la Direction du 14/11/2026 (option 2) : les prestataires voyagent comme les natures de facture, tarif par acte compris.
      ('prestataires', jeuPrestataires, 'da', 'prestataires'),
    ]) {
      final (id, j, role, col) = cas;
      test('$id : le fileul écrit chez lui sous l\'identité de la demande, la mère rejoue sous le rôle de l\'auteur et écrit sous les MÊMES identifiants', () {
        final f = poste(role, 'F1-');
        final a = analyserFichier(j, fich(j, [valide[id]!]), 'f.xlsx', f);
        expect(a.accepte, isTrue);
        final d = importerDirectEtDemander(jeu: j, analyse: a, port: f, regime: regime, idDemande: 'DIM1', poste: 'F1');
        expect(d.ok, isTrue, reason: '${d.refus?.code}');
        final chezLeFileul = f.actives(col).firstWhere((x) => x[champEnAttenteMere] != null);
        expect(chezLeFileul['id'], startsWith('${col.substring(0, 3).toUpperCase()}-'), reason: 'identité de la demande, jamais préfixée du poste');
        final m = poste(role, 'M-');
        final v = traiterDemandeImport(d.demande!, m, jeuImportParId, regime: regime);
        expect(v.appliquee, isTrue, reason: '${v.code} ${v.motif}');
        final surMere = m.actives(col).firstWhere((x) => x['lotImport'] == v.lot);
        expect(surMere['id'], chezLeFileul['id'], reason: 'une fiche par code : la mère remplace celle du fileul, jamais un doublon');
        expect(surMere[champEnAttenteMere], isNull);
      });
    }

    test('un rôle sans le droit : la mère refuse en nommant (un fileul falsifié ne se prête pas le droit d\'un autre)', () {
      final j = jeuCentresCouts;
      final f = poste('da', 'F1-');
      final a = analyserFichier(j, fich(j, [valide[j.id]!]), 'f.xlsx', f);
      final d = importerDirectEtDemander(jeu: j, analyse: a, port: f, regime: regime, idDemande: 'DIM2', poste: 'F1').demande!;
      final v = traiterDemandeImport({...d, 'demandeRole': 'medecin'}, poste('medecin', 'M-'), jeuImportParId, regime: regime);
      expect(v.appliquee, isFalse);
      expect(v.code, 'DROIT_IMPORT_REFUSE');
    });

    test('une fiche créée à la mère entre-temps : refus nommé (DOUBLON_MAGASIN), rien écrit', () {
      final j = jeuNaturesFacture;
      final f = poste('da', 'F1-');
      final d = importerDirectEtDemander(jeu: j, analyse: analyserFichier(j, fich(j, [valide[j.id]!]), 'f.xlsx', f), port: f, regime: regime, idDemande: 'DIM3', poste: 'F1').demande!;
      final m = poste('da', 'M-');
      m.toutes('naturesFacture').add({'id': 'N9', 'code': 'ORTH', 'libelle': 'Ailleurs', 'secteur': 'Chirurgie', 'statut': 'actif'});
      final v = traiterDemandeImport(d, m, jeuImportParId, regime: regime);
      expect(v.appliquee, isFalse);
      expect(v.code, 'DOUBLON_MAGASIN');
      expect(m.actives('naturesFacture').where((x) => x['lotImport'] != null), isEmpty);
    });

    for (final j in [jeuImmobilisations, jeuBudgets]) {
      test('${j.id} (restreint) : ne se dépose JAMAIS, et la mère refuse une demande forgée en le nommant ; l\'import à la mère reste local et direct', () {
        final f = poste('da', 'F1-');
        final a = analyserFichier(j, fich(j, [valide[j.id]!]), 'f.xlsx', f);
        final r = importerDirectEtDemander(jeu: j, analyse: a, port: f, regime: regime, idDemande: 'DIM4', poste: 'F1');
        expect(r.ok, isFalse);
        expect(r.refus!.code, 'JEU_NON_DEMANDABLE');
        expect(f.toutes(j.cibles.first).where((x) => x['lotImport'] != null), isEmpty, reason: 'rien écrit');
        final forgee = {'id': 'DIMX', 'jeu': j.id, 'etat': demandeImportEnAttente, 'demandeRole': 'da', 'demandePar': 'X', 'lignes': fich(j, [valide[j.id]!]), 'fichier': 'f.xlsx'};
        final v = traiterDemandeImport(forgee, poste('da', 'M-'), jeuImportParId, regime: regime);
        expect(v.appliquee, isFalse);
        expect(v.code, 'JEU_RESTREINT');
        // Au poste de la mère, l'import local direct.
        final m = poste('da', 'M-');
        expect(appliquer(j, analyserLignes(j, fich(j, [valide[j.id]!]), 'f.xlsx', m), m).ok, isTrue);
      });
    }
  });
}
