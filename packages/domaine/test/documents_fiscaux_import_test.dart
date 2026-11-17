// L'import daté de la liasse fiscale et du classeur de baseline (E4800) : lecture STRICTE au schéma des documents d'import de démonstration, refus nommés, version nouvelle jamais un écrasement,
// la plus récente fait foi, archivage motivé, journal sans contenu comptable.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

String _texte(String nom) => File('../../apps/poste/tool/donnees/$nom').readAsStringSync();
Map<String, Object?> _json(String nom) => (jsonDecode(_texte(nom)) as Map).cast<String, Object?>();

/// Une copie profonde modifiable d'un document, passée à [modifier], puis rendue en texte.
String _modifie(String nom, void Function(Map<String, Object?> d) modifier) {
  final d = (jsonDecode(_texte(nom)) as Map).cast<String, Object?>();
  modifier(d);
  return jsonEncode(d);
}

final auj = DateTime(2026, 11, 17, 10, 30);

void main() {
  tearDown(DocumentsFiscaux.debrancher);

  group('lecture stricte : les deux documents de démonstration sont acceptés tels quels', () {
    test('la liasse', () {
      final v = lireDocumentFiscal(_texte('liasse_2025_demo.json'));
      expect(v.refus, isNull, reason: '${v.refus}');
      expect(v.document!.genre, docFiscalLiasse);
      expect(v.document!.exercice, 2025);
      expect(v.document!.dateDepotPortee, '2026-04-30');
      expect(v.document!.estDemonstration, isTrue);
    });
    test('le classeur', () {
      final v = lireDocumentFiscal(_texte('classeur_2025_demo.json'));
      expect(v.refus, isNull, reason: '${v.refus}');
      expect(v.document!.genre, docFiscalClasseur);
      expect(v.document!.exercice, 2025);
      expect(v.document!.dateDepotPortee, isNull);
    });
  });

  group('refus NOMMÉS, avec le chemin de la valeur fautive', () {
    RefusImportFiscal? refus(String texte) => lireDocumentFiscal(texte).refus;

    test('fichier vide, JSON illisible, racine qui n’est pas un objet, forme inconnue', () {
      expect(refus('  ')!.code, 'FICHIER_VIDE');
      expect(refus('{pas du json')!.code, 'JSON_ILLISIBLE');
      expect(refus('[1,2]')!.code, 'RACINE_NON_OBJET');
      expect(refus('{"x":1}')!.code, 'GENRE_INDETERMINE');
    });
    test('liasse : une clé de premier niveau manque, une clé inconnue est refusée (rien n’est ignoré en silence)', () {
      var r = refus(_modifie('liasse_2025_demo.json', (d) => d.remove('FLUX')));
      expect(r!.code, 'CLE_MANQUANTE');
      expect(r.chemin, 'FLUX');
      r = refus(_modifie('liasse_2025_demo.json', (d) => d['EXTRA'] = []));
      expect(r!.code, 'CLE_INCONNUE');
      expect(r.chemin, 'EXTRA');
    });
    test('liasse : en-tête du dépôt (IFU, date, exercices, source)', () {
      String? code(void Function(Map<String, Object?> depot) f) => refus(_modifie('liasse_2025_demo.json', (d) => f((d['DEPOT'] as Map).cast<String, Object?>())))?.code;
      expect(code((x) => x['ifu'] = '12AB'), 'IFU_INVALIDE');
      expect(code((x) => x['dateDepot'] = '2026-02-31'), 'DATE_DEPOT_INVALIDE');
      expect(code((x) => x['exerciceN1'] = 2020), 'EXERCICE_INCOHERENT');
      expect(code((x) => x['exerciceN'] = '2025'), 'TYPE_INVALIDE');
      expect(code((x) => x['source'] = '  '), 'DEPOT_INCOMPLET');
      expect(code((x) => x.remove('denomination')), 'CLE_MANQUANTE');
    });
    test('liasse : une ligne de formulaire (type, clé inconnue, niveau, référence en double, écart inconnu)', () {
      var r = refus(_modifie('liasse_2025_demo.json', (d) => ((d['BILAN_ACTIF'] as List)[2] as Map)['brut'] = '12'));
      expect(r!.code, 'TYPE_INVALIDE');
      expect(r.chemin, 'BILAN_ACTIF[2].brut');
      r = refus(_modifie('liasse_2025_demo.json', (d) => ((d['BILAN_PASSIF'] as List)[0] as Map)['inconnue'] = 1));
      expect(r!.code, 'CLE_INCONNUE');
      r = refus(_modifie('liasse_2025_demo.json', (d) => ((d['RESULTAT'] as List)[0] as Map)['t'] = 'enorme'));
      expect(r!.code, 'NIVEAU_INVALIDE');
      r = refus(_modifie('liasse_2025_demo.json', (d) => ((d['BILAN_ACTIF'] as List)[1] as Map)['ref'] = ((d['BILAN_ACTIF'] as List)[0] as Map)['ref']));
      expect(r!.code, 'REFERENCE_EN_DOUBLE');
      r = refus(_modifie('liasse_2025_demo.json', (d) {
        for (final l in d['FLUX'] as List) {
          if ((l as Map).containsKey('ecart')) l['ecart'] = 'fantome';
        }
      }));
      expect(r!.code, 'ECART_INCONNU');
      r = refus(_modifie('liasse_2025_demo.json', (d) => d['BILAN_ACTIF'] = []));
      expect(r!.code, 'LISTE_VIDE');
      r = refus(_modifie('liasse_2025_demo.json', (d) => ((d['BILAN_ACTIF'] as List)[1] as Map)['comptes'] = ['21x']));
      expect(r!.code, 'COMPTE_INVALIDE');
    });
    test('liasse : une case vide (null) n’est admise qu’aux notes 11 et 34, pas au bilan', () {
      final r = refus(_modifie('liasse_2025_demo.json', (d) => ((d['BILAN_PASSIF'] as List)[0] as Map)['net'] = null));
      expect(r!.code, 'TYPE_INVALIDE');
    });
    test('la liasse n’est PAS recalculée : ses écarts internes sont CITÉS, jamais refusés', () {
      // le document de démonstration porte six écarts internes déclarés : il est accepté (premier groupe) ; changer un montant de sous-total ne le refuse pas non plus
      final texte = _modifie('liasse_2025_demo.json', (d) => ((d['RESULTAT'] as List)[0] as Map)['n'] = 123456789);
      expect(lireDocumentFiscal(texte).refus, isNull);
    });
    test('classeur : totaux qui ne se recoupent pas, structure, rattachement', () {
      var r = refus(_modifie('classeur_2025_demo.json', (d) => d['totalChiffreAffaires'] = 1));
      expect(r!.code, 'TOTAL_INCOHERENT');
      r = refus(_modifie('classeur_2025_demo.json', (d) => ((d['depenses'] as List)[0] as Map)['total'] = 5));
      expect(r!.code, 'TOTAL_POSTE_INCOHERENT');
      expect(r.chemin, 'depenses[0].total');
      r = refus(_modifie('classeur_2025_demo.json', (d) => (d['chiffreAffaires'] as List).removeLast()));
      expect(r!.code, 'SERIE_INVALIDE');
      r = refus(_modifie('classeur_2025_demo.json', (d) => d.remove('controle')));
      expect(r!.code, 'CLE_MANQUANTE');
      r = refus(_modifie('classeur_2025_demo.json', (d) => d['surprise'] = 1));
      expect(r!.code, 'CLE_INCONNUE');
      r = refus(_modifie('classeur_2025_demo.json', (d) {
        for (final l in d['depenses'] as List) {
          if ((l as Map)['aRattacher'] == true) {
            l['num'] = '123456';
            break;
          }
        }
      }));
      expect(r!.code, 'RATTACHEMENT_INCOHERENT');
      r = refus(_modifie('classeur_2025_demo.json', (d) => (d['controle'] as Map)['postesSansCompte'] = 9));
      expect(r!.code, 'TOTAL_INCOHERENT');
    });
    test('chaque refus porte un motif et un geste', () {
      for (final texte in ['', '{', '[]', '{"x":1}', _modifie('liasse_2025_demo.json', (d) => d.remove('DEPOT'))]) {
        final r = refus(texte)!;
        expect(r.motif, isNotEmpty);
        expect(r.geste, isNotEmpty);
      }
    });
  });

  group('préparer un import : les gardes, dans l’ordre', () {
    final liasse = lireDocumentFiscal(_texte('liasse_2025_demo.json')).document!;
    final classeur = lireDocumentFiscal(_texte('classeur_2025_demo.json')).document!;

    VerdictImportFiscal importer(DocumentFiscalLu d,
            {String? date, String source = 'Remise à la DGI', String auteur = 'Comptable', bool droit = true, bool fileul = false, List<Map<String, Object?>> existantes = const []}) =>
        preparerImportFiscal(document: d, dateDepot: date, source: source, auteur: auteur, maintenant: auj, existantes: existantes, peutImporter: droit, estFileul: fileul);

    test('sans le geste réservé : refus nommé, rien n’est écrit', () {
      final v = importer(liasse, droit: false);
      expect(v.accepte, isFalse);
      expect(v.refus!.code, 'GESTE_RESERVE');
    });
    test('un poste rattaché n’écrit pas (référentiel de la mère)', () => expect(importer(liasse, fileul: true).refus!.code, 'REGLE_SUR_LA_MERE'));
    test('source et auteur obligatoires (un chiffre sans origine ne se cite pas, aucune action anonyme)', () {
      expect(importer(liasse, source: ' ').refus!.code, 'SOURCE_ABSENTE');
      expect(importer(liasse, auteur: '').refus!.code, 'AUTEUR_ABSENT');
    });
    test('la date de dépôt : obligatoire pour un classeur, réelle, pas future, pas avant la fin de l’exercice, jamais contraire à celle que la liasse porte', () {
      expect(importer(classeur).refus!.code, 'DATE_DEPOT_ABSENTE');
      expect(importer(classeur, date: '2026-13-01').refus!.code, 'DATE_DEPOT_INVALIDE');
      expect(importer(classeur, date: '2026-12-25').refus!.code, 'DATE_DEPOT_FUTURE');
      expect(importer(classeur, date: '2025-06-01').refus!.code, 'DATE_DEPOT_AVANT_EXERCICE');
      expect(importer(liasse, date: '2026-05-02').refus!.code, 'DATE_DEPOT_DIVERGENTE');
      expect(importer(liasse).accepte, isTrue, reason: 'la liasse reprend sa propre date de dépôt');
    });
    test('la fiche porte genre, exercice, date d’effet, source, auteur, instant et contenu ; la liasse de démonstration est marquée', () {
      final f = importer(liasse).fiche!;
      expect(f['id'], 'doc-fiscal-liasse-2025-2026-04-30');
      expect(f['genre'], docFiscalLiasse);
      expect(f['exercice'], 2025);
      expect(f['dateEffet'], '2026-04-30');
      expect(f['source'], 'Remise à la DGI');
      expect(f['importePar'], 'Comptable');
      expect(f['importeLe'], startsWith('2026-11-17'));
      expect(f['statut'], 'actif');
      expect(f['demonstration'], isTrue);
      expect(f['contenu'], same(liasse.contenu));
      expect(importer(classeur, date: '2026-04-30').fiche!.containsKey('demonstration'), isFalse);
    });
    test('un dépôt rectifié le MÊME jour est une version de plus ; l’identité d’une version archivée ne se recycle pas', () {
      final premiere = importer(liasse).fiche!;
      final seconde = importer(liasse, existantes: [premiere]).fiche!;
      expect(seconde['id'], 'doc-fiscal-liasse-2025-2026-04-30-r02');
      final archivee = {...seconde, 'statut': 'archive'};
      expect(importer(liasse, existantes: [premiere, archivee]).fiche!['id'], 'doc-fiscal-liasse-2025-2026-04-30-r03');
    });
  });

  group('la plus récente fait foi, une version se retire par archivage, rien ne se supprime', () {
    final liasse = lireDocumentFiscal(_texte('liasse_2025_demo.json')).document!;

    Map<String, Object?> version(String jour, {String? importeLe, String statut = 'actif'}) => {
          ...docFiscalFiche(genre: docFiscalLiasse, exercice: 2025, dateDepot: jour, source: 'S $jour', auteur: 'A', importeLe: importeLe ?? '2026-11-17T08:00:00Z', contenu: liasse.contenu),
          'statut': statut,
        };

    test('versionsFiscales : la plus récente en force, les autres antérieures, les archivées lisibles', () {
      final a = version('2026-04-30'), b = version('2026-06-10'), c = version('2026-08-01', statut: 'archive');
      final v = versionsFiscales([a, b, c], docFiscalLiasse);
      expect([for (final x in v) x.id], [c['id'], b['id'], a['id']]);
      expect([for (final x in v) x.etat], [versionFiscaleArchivee, versionFiscaleEnForce, versionFiscaleAnterieure]);
      DocumentsFiscaux.brancher(() => [a, b, c]);
      expect(DocumentsFiscaux.fiche(docFiscalLiasse)!['id'], b['id'], reason: 'le registre et la liste disent la même chose');
      expect(versionsFiscales([a, b, c], docFiscalClasseur), isEmpty);
    });
    test('archiver la version en force rend la précédente : le registre suit', () {
      final a = version('2026-04-30'), b = version('2026-06-10');
      final p = preparerArchivageFiscal(fiche: b, motif: 'Import fait par erreur', auteur: 'Comptable', maintenant: auj, peutImporter: true);
      expect(p.refus, isNull);
      expect(p.patch!['statut'], 'archive');
      expect(p.patch!['archivePar'], 'Comptable');
      expect(p.patch!['motifArchivage'], 'Import fait par erreur');
      final archivee = {...b, ...p.patch!};
      DocumentsFiscaux.brancher(() => [a, archivee]);
      expect(DocumentsFiscaux.fiche(docFiscalLiasse)!['id'], a['id']);
    });
    test('l’archivage se motive, se nomme, exige le geste, ne se fait pas sur un fileul', () {
      final b = version('2026-06-10');
      String? code({String motif = 'm', String auteur = 'A', bool droit = true, bool fileul = false, Map<String, Object?>? f}) =>
          preparerArchivageFiscal(fiche: f ?? b, motif: motif, auteur: auteur, maintenant: auj, peutImporter: droit, estFileul: fileul).refus?.code;
      expect(code(motif: ' '), 'MOTIF_ABSENT');
      expect(code(auteur: ''), 'AUTEUR_ABSENT');
      expect(code(droit: false), 'GESTE_RESERVE');
      expect(code(fileul: true), 'REGLE_SUR_LA_MERE');
      expect(preparerArchivageFiscal(fiche: null, motif: 'm', auteur: 'A', maintenant: auj, peutImporter: true).refus!.code, 'VERSION_INCONNUE');
      expect(code(f: {...b, 'statut': 'archive'}), 'DEJA_ARCHIVEE');
    });
    test('sans aucune fiche : rien n’est inventé (le registre dit « aucune liasse importée »)', () {
      DocumentsFiscaux.brancher(() => const []);
      expect(DocumentsFiscaux.importee(docFiscalLiasse), isFalse);
      expect(versionsFiscales(const [], docFiscalLiasse), isEmpty);
      expect((DocumentsFiscaux.liasse['DEPOT'] as Map)['exerciceN'], 0);
    });
  });

  test('le journal ne reçoit JAMAIS de contenu comptable : seulement l’identité, la source et des nombres de lignes', () {
    final liasse = lireDocumentFiscal(_texte('liasse_2025_demo.json')).document!;
    final fiche = preparerImportFiscal(
            document: liasse, dateDepot: null, source: 'Remise à la DGI', auteur: 'Comptable', maintenant: auj, existantes: const [], peutImporter: true)
        .fiche!;
    final r = docFiscalResumeJournal(fiche);
    final json = jsonEncode(r);
    expect(r['genre'], docFiscalLiasse);
    expect((r['lignes'] as Map)['BILAN_ACTIF'], 29);
    for (final interdit in ['"brut"', '"netN1"', '"comptes"', 'IMMOBILISATIONS', '"ifu"', '3201001996110']) {
      expect(json, isNot(contains(interdit)), reason: interdit);
    }
    // les nombres de lignes ne portent aucun montant : chaque valeur est un entier de petite taille
    for (final n in (r['lignes'] as Map).values) {
      expect(n, isA<int>());
    }
  });

  test('le geste réservé est au référentiel : comptable et DAF d’origine, rattaché à l’écran de la comptabilité', () {
    final g = gesteReserve(gesteDocumentsFiscauxImporter)!;
    expect(g.rolesDefaut, containsAll(['comptable', 'da']));
    expect(g.module, 'M12');
    expect(g.ecran, 'm12-liasse-import');
    final droits = DroitsGestes(fiches: const []);
    expect(droits.peut('comptable', gesteDocumentsFiscauxImporter), isTrue);
    expect(droits.peut('caissier', gesteDocumentsFiscauxImporter), isFalse);
    // la clinique le retire ou l'accorde par la fiche de rôle
    final accorde = DroitsGestes(fiches: [
      {'id': 'RBAC-X', 'role': 'caissier', 'statut': 'actif', 'droitsGestes': {gesteDocumentsFiscauxImporter: true}}
    ]);
    expect(accorde.peut('caissier', gesteDocumentsFiscauxImporter), isTrue);
  });
}
