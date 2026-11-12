import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/import/classeur_xlsx.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/import/selecteurs_import.dart';
import 'package:sigh_poste/modules/imp/imp_ecrans.dart';

/// Le classeur .xlsx du poste, éprouvé contre les classeurs ÉCRITS PAR LA MAQUETTE (`test/fixtures/import/*.xlsx`, engendrés par
/// `prototype_html/build/vecteurs-import.js`) : deux implémentations indépendantes (JavaScript, Dart) qui doivent se relire à l'identique.
/// Limite nommée : aucun de ces classeurs ne sort d'Excel lui-même ; la compatibilité avec un Excel réel n'est pas vérifiée ici.
final vecteurs = (jsonDecode(File('../../packages/domaine/test/vecteurs/import.json').readAsStringSync()) as Map).cast<String, Object?>();

Uint8List fixture(String nom) => File('test/fixtures/import/$nom.xlsx').readAsBytesSync();

String _t(Object? v) => texteDe(v);

Magasin magasinVecteurs() => Magasin({
      for (final e in (vecteurs['magasin'] as Map).entries) '${e.key}': [for (final f in (e.value as List)) (f as Map).cast<String, Object?>()],
      'audit': const [],
    });

PortMagasin portVecteurs(Magasin m) => PortMagasin(m, aujourdhui: () => DateTime(2026, 11, 1), nomAgent: 'ADMIN TEST', profil: const ProfilImport.accordeTout());

/// Décisions du 11/11/2026 : le modèle du répertoire patients ne porte plus le code (RG-01 : généré) ni le groupe sanguin ; le modèle du personnel ne porte la colonne
/// « Salaire de base » que pour le profil qui a le droit paie. Les classeurs de la maquette, écrits avant, sont relus tels quels puis ADAPTÉS avant l'analyse.
const _retiresPatients = {'Code dossier', 'Groupe sanguin'};
const _casCodeFourni = {'pa-code-existant', 'pa-code-invalide'};

List<List<Object?>> adapter(String jeu, List<List<Object?>> lignes) {
  if (jeu != 'patients' || lignes.isEmpty) return lignes;
  final garde = [for (var i = 0; i < lignes.first.length; i++) if (!_retiresPatients.contains('${lignes.first[i]}')) i];
  return [
    for (final l in lignes) [for (final i in garde) if (i < l.length) l[i] else '']
  ];
}

void main() {
  group('lecture des classeurs écrits par la maquette', () {
    for (final c in (vecteurs['cas'] as List).cast<Map>()) {
      test('${c['id']} : mêmes lignes, même verdict que la maquette', () {
        final feuilles = lireClasseur(fixture('${c['id']}'));
        expect(feuilles.map((f) => f.nom), ['Données']);
        final attendues = [
          for (final l in (c['lignes'] as List).cast<List>()) [for (final x in l) _t(x)]
        ];
        // Un classeur ne garde pas les cellules vides de queue ni les lignes vides de queue : on compare sans elles.
        List<String> sansQueue(Iterable<Object?> l) {
          final t = [for (final x in l) _t(x)];
          while (t.isNotEmpty && t.last.isEmpty) {
            t.removeLast();
          }
          return t;
        }

        final lues = [for (final l in feuilles.single.lignes) sansQueue(l)];
        final att = [for (final l in attendues) sansQueue(l)];
        while (att.isNotEmpty && att.last.isEmpty) {
          att.removeLast();
        }
        expect(lues, att);
        // Et le moteur du domaine rend le verdict de la maquette sur ces lignes lues par Dart.
        final jeu = jeuImportParId('${c['jeu']}')!;
        if (_casCodeFourni.contains(c['id'])) return; // le code fourni par le fichier n'existe plus (RG-01) : voir packages/domaine/test/import_ecarts_test.dart
        final a = analyserLignes(jeu, adapter(jeu.id, feuilles.single.lignes), '${c['id']}.xlsx', portVecteurs(magasinVecteurs()), options: OptionsImport(colonnesAccordees: jeu.colonnesReservees));
        final attendu = (c['attendu'] as Map).cast<String, Object?>();
        expect(a.accepte, attendu['accepte'], reason: '${c['id']} : accepté');
        expect(a.compte.versJson(), attendu['compte']);
        expect([for (final p in a.problemes) '${p.n}:${p.code}:${p.niveau}'],
            [for (final p in (attendu['problemes'] as List).cast<Map>()) '${p['n']}:${p['code']}:${p['niveau']}']);
      });
    }
  });

  group('modèles : celui du poste et celui de la maquette disent la même chose', () {
    final connus = (vecteurs['modeles'] as Map).cast<String, Object?>();
    for (final j in jeuxImport.where((j) => connus.containsKey(j.id))) {
      test(j.id, () {
        final m = connus[j.id] as Map;
        // Le modèle de la maquette, relu par Dart.
        final maquette = lireClasseur(fixture('modele-${j.id}'));
        expect(maquette.map((f) => f.nom), ['Données', 'Instructions', 'Listes']);
        expect([for (final x in maquette[0].lignes.first) '$x'], m['entetes']);
        // Le modèle du poste, relu par Dart : mêmes feuilles, mêmes en-têtes, mêmes lignes que celui de la maquette (au profil qui a le droit paie).
        final port = portVecteurs(magasinVecteurs());
        final poste = lireClasseur(classeurModele(j, port, colonnesAccordees: j.colonnesReservees));
        expect(poste.map((f) => f.nom), ['Données', 'Instructions', 'Listes']);
        List<String> sansQueue(Iterable<Object?> l) {
          final t = [for (final x in l) _t(x)];
          while (t.isNotEmpty && t.last.isEmpty) {
            t.removeLast();
          }
          return t;
        }

        // Patients : on retire du modèle de la maquette le code et le groupe sanguin (colonnes, lignes d'instructions, liste).
        List<List<String>> relu(int feuille) {
          var lignes = [for (final l in maquette[feuille].lignes) sansQueue(l)];
          if (j.id != 'patients') return lignes;
          if (feuille == 0) {
            final garde = [for (var i = 0; i < lignes.first.length; i++) if (!_retiresPatients.contains(lignes.first[i])) i];
            lignes = [for (final l in lignes) [for (final i in garde) if (i < l.length) l[i]]];
          } else if (feuille == 1) {
            lignes = [for (final l in lignes) if (l.isEmpty || !_retiresPatients.contains(l.first)) l];
          } else {
            final i = lignes.first.indexOf('Groupe sanguin');
            lignes = [for (final l in lignes) [for (var k = 0; k < l.length; k++) if (k != i) l[k]]];
          }
          lignes = [for (final l in lignes) sansQueue(l)];
          while (lignes.isNotEmpty && lignes.last.isEmpty && j.id == 'patients') {
            lignes.removeLast();
          }
          return lignes;
        }

        for (var i = 0; i < 3; i++) {
          // La maquette décrit le code patient sous le sigle CBG ; le poste, sous le sigle de la clinique en vigueur.
          String sigle(String x) => x.replaceAll('${IdentiteClinique.sigle}/n/AA', 'CBG/n/AA').replaceAll('Zongo II, Parakou', 'Tchirimina, Natitingou');
          final obtenu = [for (final l in poste[i].lignes) sansQueue(l).map(sigle).toList()];
          while (obtenu.isNotEmpty && obtenu.last.isEmpty && j.id == 'patients') {
            obtenu.removeLast();
          }
          expect(obtenu, relu(i), reason: 'feuille ${poste[i].nom}');
        }
      });
    }

    for (final j in jeuxImport.where((j) => !connus.containsKey(j.id))) {
      test('${j.id} (jeu du 11/11/2026) : le classeur du poste porte les en-têtes du jeu et se relit', () {
        final poste = lireClasseur(classeurModele(j, portVecteurs(magasinVecteurs())));
        expect(poste.map((f) => f.nom), ['Données', 'Instructions', 'Listes']);
        expect([for (final x in poste[0].lignes.first) '$x'], [for (final c in j.colonnes) c.label]);
        // Le modèle intact est un fichier vide : la ligne d'exemple n'est jamais importée.
        final a = analyserLignes(j, poste[0].lignes, 'modele.xlsx', portVecteurs(magasinVecteurs()));
        expect(a.accepte, isFalse);
        expect(a.globaux.single.code, 'FICHIER_VIDE');
      });
    }

    test('le modèle du personnel ne porte « Salaire de base » que pour le profil qui a le droit paie', () {
      final port = portVecteurs(magasinVecteurs());
      final sans = lireClasseur(classeurModele(jeuPersonnel, port));
      final avec = lireClasseur(classeurModele(jeuPersonnel, port, colonnesAccordees: {'salaireBase'}));
      expect([for (final x in sans[0].lignes.first) '$x'], isNot(contains('Salaire de base')));
      expect([for (final x in avec[0].lignes.first) '$x'], contains('Salaire de base'));
      expect(sans[1].lignes.expand((l) => l).map((x) => '$x').where((x) => x == 'Salaire de base'), isEmpty);
    });

    test('le modèle intact (ligne d\'exemple non modifiée) est refusé comme fichier vide, jamais importé', () {
      final lu = lireClasseur(fixture('modele-grand-stock'));
      final a = analyserLignes(jeuGrandStock, lu.first.lignes, 'modele.xlsx', portVecteurs(magasinVecteurs()));
      expect(a.accepte, isFalse);
      expect(a.globaux.single.code, 'FICHIER_VIDE');
    });
  });

  test('des classeurs compressés par un autre compresseur (zlib, niveaux 1 et 9) se relisent comme leurs originaux', () {
    for (final (comp, ref) in [('compresse-gs-valide', 'gs-valide'), ('compresse-niveau1-modele-patients', 'modele-patients')]) {
      final a = lireClasseur(fixture(comp)), b = lireClasseur(fixture(ref));
      expect([for (final x in a) x.nom], [for (final x in b) x.nom]);
      expect([for (final x in a) x.lignes], [for (final x in b) x.lignes], reason: comp);
    }
  });

  group('écrire puis relire', () {
    test('types, chaînes accentuées, booléens, cellules vides et feuille sans entête', () {
      final octets = ecrireClasseur([
        const FeuilleXlsx('Données', [
          ['Nom', 'Âge', 'Actif', 'Note'],
          ['AGBUZIA Marie', 36, true, 'a & b < c'],
          ['', 2.5, false, ''],
        ]),
        const FeuilleXlsx('Texte', [
          ['Mode d’emploi']
        ], entete: false),
      ]);
      expect(octets.sublist(0, 2), [0x50, 0x4b], reason: 'archive ZIP « PK »');
      final f = lireClasseur(octets);
      expect(f.map((x) => x.nom), ['Données', 'Texte']);
      expect(f[0].lignes[1], ['AGBUZIA Marie', 36, true, 'a & b < c']);
      expect(f[0].lignes[2], ['', 2.5, false]);
      expect(f[1].lignes.single, ['Mode d’emploi']);
    });

    test('un fichier qui n\'est pas un classeur est refusé avec un motif lisible', () {
      expect(() => lireClasseur(utf8.encode('ceci n’est pas un classeur')), throwsA(isA<FormatException>()));
      final lu = lireFichierImport(FichierChoisi('faux.xlsx', Uint8List.fromList(utf8.encode('ceci n’est pas un classeur'))));
      expect(lu.lignes, isNull);
      expect(lu.motif, contains('archive ZIP'));
      final a = analyserFichier(jeuGrandStock, lu.lignes, 'faux.xlsx', portVecteurs(magasinVecteurs()), motifIllisible: lu.motif);
      expect(a.accepte, isFalse);
      expect(a.globaux.single.code, 'FORMAT_FICHIER');
    });

    test('un .csv (BOM, point-virgule, guillemets doublés) se lit comme un classeur', () {
      const csv = 'Code fournisseur;Raison sociale;Type;Ville;Adresse;Téléphone;IFU;Délai de livraison (jours);Banque;N° de compte\r\n'
          'TST-F1;"Fournisseur ""test"" SARL";Grossiste;Parakou;;0191000000;3202112446701;4;;\r\n';
      final lu = lireFichierImport(FichierChoisi('f.csv', Uint8List.fromList(utf8.encode('\uFEFF$csv'))));
      final a = analyserLignes(jeuFournisseurs, lu.lignes!, 'f.csv', portVecteurs(magasinVecteurs()));
      expect(a.accepte, isTrue, reason: '${a.problemes.map((p) => p.code)}');
      expect(a.lignes.single.v['nom'], 'Fournisseur "test" SARL');
    });
  });

  test('le rapport d\'erreurs se relit : sept colonnes, une ligne par constat', () {
    final port = portVecteurs(magasinVecteurs());
    final c = (vecteurs['cas'] as List).cast<Map>().firstWhere((x) => x['id'] == 'gs-quantite-negative');
    final a = analyserLignes(jeuGrandStock, lireClasseur(fixture('gs-quantite-negative')).single.lignes, 'x.xlsx', port);
    final rapport = lireClasseur(classeurRapport('Importation Grand Stock', 'x.xlsx', 'IMP-2026-001', a.nbLignes, [for (final p in a.problemes) p.versJson()]));
    expect(rapport.map((f) => f.nom), ['Erreurs', 'Résumé']);
    expect(rapport[0].lignes.first, (vecteurs['rapport'] as Map)['entete']);
    expect(rapport[0].lignes[1][4], 'RG03_STOCK_NEGATIF');
    expect(c['id'], 'gs-quantite-negative');
  });
}
