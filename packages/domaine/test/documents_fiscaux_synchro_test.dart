// L'import de la liasse DEPUIS UN POSTE RATTACHÉ (Direction de Baguidi, 18/11/2026, point 4) : le fileul dépose la demande (genre `liasse_importer`, contenu = le document validé localement) ; la mère
// REJOUE la validation stricte, applique sous le geste `documents_fiscaux_importer` du compte signataire, renvoie un verdict nommé ; la taille est bornée par un RÉGLAGE. Aucun nom de rôle écrit ici.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

String _texte(String nom) => File('../../apps/poste/tool/donnees/$nom').readAsStringSync();

String _modifie(String nom, void Function(Map<String, Object?> d) modifier) {
  final d = (jsonDecode(_texte(nom)) as Map).cast<String, Object?>();
  modifier(d);
  return jsonEncode(d);
}

final auj = DateTime(2026, 11, 18, 10, 30);

void main() {
  final gestes = gestesOrigine();
  final importeur = gesteReserve(gesteDocumentsFiscauxImporter)!.rolesDefaut.first;
  // Les rôles de la MATRICE (jamais une liste écrite ici) : un rôle qui ne détient pas le geste d'import.
  final roles = [for (final r in (jsonDecode(File('../rbac/data/rbac.json').readAsStringSync()) as Map)['roles'] as List) '${(r as Map)['id']}'];
  final sansGeste = roles.firstWhere((r) => !gestes.peut(r, gesteDocumentsFiscauxImporter));
  final tailleMax = seuilSeme(cleTailleMaxDepotFiscalKo);
  final liasse = lireDocumentFiscal(_texte('liasse_2025_demo.json')).document!;
  final classeur = lireDocumentFiscal(_texte('classeur_2025_demo.json')).document!;

  var n = 0;
  String nouvelId() => 'VDP-F1-${++n}';

  VerdictDepot deposer(DocumentFiscalLu d, {String? date, String source = 'Remise à la DGI', String auteur = 'Comptable Fictif', String? role, DroitsGestes? g, int? max, List<Map<String, Object?>> depots = const [], List<Map<String, Object?>> existantes = const []}) =>
      liasseImporterDeposer(
          document: d,
          dateDepot: date,
          source: source,
          auteur: auteur,
          role: role ?? importeur,
          poste: 'F1',
          maintenant: auj,
          existantes: existantes,
          gestes: g ?? gestes,
          tailleMaxKo: max ?? tailleMax,
          depots: depots,
          nouvelId: nouvelId);

  ApplicationLiasseImporter? appliquer(Map<String, Object?> dep, {DroitsGestes? g, int? max, List<Map<String, Object?>> existantes = const [], DateTime? maintenant}) =>
      liasseImporterAppliquer(dep, existantes: existantes, gestes: g ?? gestes, tailleMaxKo: max ?? tailleMax, maintenant: maintenant ?? auj.add(const Duration(hours: 3)));

  test('la taille maximale est un RÉGLAGE borné de la clinique (jamais un nombre écrit), valeur d’attente semée', () {
    final d = definitionDeParametre(cleTailleMaxDepotFiscalKo)!;
    expect(d.type, TypeParametre.entier);
    expect(d.min, isNotNull);
    expect(d.max, isNotNull);
    expect(tailleMax >= d.min! && tailleMax <= d.max!, isTrue);
    expect(d.mobile, isFalse, reason: 'donnée financière : jamais vers un téléphone');
    expect(docFiscalOctets(liasse.contenu), lessThan(tailleMax * 1024), reason: 'la liasse de démonstration tient sous la valeur d’attente');
    expect(seuilEntierDe(cleTailleMaxDepotFiscalKo, d.max! + 1), tailleMax, reason: 'hors bornes : la valeur d’attente');
  });

  group('le dépôt du fileul', () {
    test('le contrôle est celui de l’import direct, à blanc : geste réservé, source, auteur, date — refus nommés, rien n’est déposé', () {
      expect(deposer(liasse, role: sansGeste).refus!.code, 'GESTE_RESERVE');
      expect(deposer(liasse, source: ' ').refus!.code, 'SOURCE_ABSENTE');
      expect(deposer(liasse, auteur: '').refus!.code, 'AUTEUR_ABSENT');
      expect(deposer(classeur).refus!.code, 'DATE_DEPOT_ABSENTE');
      expect(deposer(classeur, date: '2026-12-25').refus!.code, 'DATE_DEPOT_FUTURE');
      expect(deposer(liasse, date: '2026-05-02').refus!.code, 'DATE_DEPOT_DIVERGENTE');
    });

    test('un refus qui vise une valeur dit où, sans point doublé', () {
      final r = deposer(liasse, date: '2026-05-02').refus!;
      expect(r.motif, isNot(contains('..')));
      expect(r.geste, isNotEmpty);
    });

    test('la taille est bornée par le réglage : refus nommé au dépôt, avec la taille et la limite', () {
      final r = deposer(liasse, max: 1).refus!;
      expect(r.code, 'DOCUMENT_TROP_VOLUMINEUX');
      expect(r.motif, contains('1 Ko'));
      expect(r.motif, contains('Ko'));
      expect(r.geste, isNotEmpty);
    });

    test('le dépôt porte le document validé, son genre, son exercice, la date, la source, l’auteur, le rôle, le poste et des NOMBRES de lignes', () {
      final v = deposer(liasse);
      expect(v.ok, isTrue, reason: '${v.refus?.code} ${v.refus?.motif}');
      final d = v.fiche!;
      expect([d['genre'], d['documentGenre'], d['exercice'], d['dateDepot'], d['source'], d['demandePar'], d['demandeRole'], d['demandePoste'], d['etat']],
          [valGenreLiasseImporter, docFiscalLiasse, 2025, '2026-04-30', 'Remise à la DGI', 'Comptable Fictif', importeur, 'F1', valDepotDeposee]);
      expect(d['contenu'], same(liasse.contenu));
      expect(d['octets'], docFiscalOctets(liasse.contenu));
      expect((d['resume'] as Map)['BILAN_ACTIF'], 29);
      expect(d['libelle'], contains('2025'));
      expect(d['cible'], 'liasse|2025|2026-04-30');
    });

    test('rejouable : une demande identique en attente n’est pas doublée ; un contenu ou une date différents est une autre demande', () {
      final premier = deposer(liasse).fiche!;
      final encore = deposer(liasse, depots: [premier]);
      expect(encore.dejaDepose, isTrue);
      expect(encore.fiche!['id'], premier['id']);
      expect(deposer(classeur, date: '2026-04-30', depots: [premier]).dejaDepose, isFalse);
      expect(deposer(liasse, source: 'Autre source', depots: [premier]).dejaDepose, isFalse);
      expect(deposer(liasse, depots: [{...premier, 'etat': valDepotRefusee}]).dejaDepose, isFalse);
    });
  });

  group('l’application par la mère', () {
    test('elle REJOUE la validation stricte et écrit la version sous le nom et à la date du geste du déposant, avec sa référence', () {
      final dep = deposer(liasse).fiche!;
      final a = appliquer(dep)!;
      expect(a.etat, valDepotAppliquee, reason: '${a.code} ${a.motif}');
      final f = a.fiche!;
      expect([f['genre'], f['exercice'], f['dateEffet'], f['source'], f['importePar'], f['statut']], [docFiscalLiasse, 2025, '2026-04-30', 'Remise à la DGI', 'Comptable Fictif', 'actif']);
      expect(f['importeLe'], startsWith('2026-11-18'), reason: 'la date du GESTE, pas celle de l’application (3 jours plus tard)');
      expect(appliquer(dep, maintenant: auj.add(const Duration(days: 3)))!.fiche!['importeLe'], startsWith('2026-11-18'));
      expect(a.reference, f['id']);
      expect(f['contenu'], isA<Map>());
    });

    test('un contenu qui ne passe PAS le validateur strict de la mère est refusé en nommant l’endroit fautif — la mère ne fait confiance à aucune lecture d’un autre poste', () {
      final dep = deposer(liasse).fiche!;
      final falsifie = {...dep, 'contenu': (jsonDecode(_modifie('liasse_2025_demo.json', (d) => d.remove('FLUX'))) as Map).cast<String, Object?>()};
      final a = appliquer(falsifie)!;
      expect([a.etat, a.code], [valDepotRefusee, 'CLE_MANQUANTE']);
      expect(a.motif, contains('FLUX'));
      expect(a.motif, isNot(contains('..')));
      expect(appliquer({...dep, 'contenu': <String, Object?>{}})!.code, 'CONTENU_ABSENT');
      expect(appliquer({...dep}..remove('contenu'))!.code, 'CONTENU_ABSENT');
    });

    test('une demande qui annonce autre chose que ce qu’elle porte est refusée (genre, exercice)', () {
      final dep = deposer(liasse).fiche!;
      expect(appliquer({...dep, 'documentGenre': docFiscalClasseur})!.code, 'DEPOT_INCOHERENT');
      expect(appliquer({...dep, 'exercice': 2024})!.code, 'DEPOT_INCOHERENT');
    });

    test('la taille est rebornée à la valeur DE LA MÈRE : un fileul au réglage plus large ne la contourne pas', () {
      final dep = deposer(liasse).fiche!;
      expect(appliquer(dep, max: 1)!.code, 'DOCUMENT_TROP_VOLUMINEUX');
    });

    test('le geste réservé est relu dans la matrice de la MÈRE, au nom du rôle du déposant : retiré depuis le dépôt, la demande est refusée', () {
      final dep = deposer(liasse).fiche!;
      final retire = DroitsGestes(fiches: [
        {'id': 'RBAC-X', 'role': importeur, 'statut': 'actif', 'droitsGestes': {gesteDocumentsFiscauxImporter: false}}
      ]);
      final a = appliquer(dep, g: retire)!;
      expect([a.etat, a.code], [valDepotRefusee, 'GESTE_RESERVE']);
      expect(a.fiche, isNull, reason: 'un refus n’écrit rien');
      expect(a.geste, isNotEmpty);
    });

    test('un dépôt rectifié le même jour est une version de plus ; une date de dépôt rejugée à l’heure du geste', () {
      final dep = deposer(liasse).fiche!;
      final une = appliquer(dep)!.fiche!;
      final deux = appliquer(dep, existantes: [une])!;
      expect(deux.etat, valDepotAppliquee);
      expect(deux.fiche!['id'], '${une['id']}-r02');
    });

    test('un dépôt déjà traité, archivé ou d’un autre genre n’est pas rejoué (null)', () {
      final dep = deposer(liasse).fiche!;
      expect(appliquer({...dep, 'etat': valDepotAppliquee}), isNull);
      expect(appliquer({...dep, 'statut': 'archive'}), isNull);
      expect(appliquer({...dep, 'genre': valGenreReferentiel}), isNull);
    });
  });

  test('lecture : les demandes d’import, la plus récente d’abord ; l’alerte après le délai va vers ceux qui détiennent le geste d’import', () {
    final a = {...deposer(liasse).fiche!, 'demandeLe': '2026-11-18T07:00:00.000Z'};
    final b = {...deposer(classeur, date: '2026-04-30').fiche!, 'id': 'VDP-F1-9', 'demandeLe': '2026-11-18T08:00:00.000Z'};
    final recents = liasseDepotsRecents([a, b, {...a, 'statut': 'archive'}, {'genre': valGenreReferentiel, 'demandeLe': '2999'}]);
    expect([for (final d in recents) d['id']], [b['id'], a['id']]);
    final d = DecisionEnAttente(genre: genreDecisionValidation, id: 'V1', libelle: 'x', par: 'A', role: 'r', depuis: auj, sousGenre: valGenreLiasseImporter, famille: colDocumentsFiscaux);
    final dest = destinatairesAlerteDecision(d, gesteCircuit: 'g', gestePrix: 'p');
    expect(dest, contains('geste:$gesteDocumentsFiscauxImporter'));
    expect(dest, contains(posteAdministrateur));
    expect(decisionsEnRetard([d], auj.add(const Duration(hours: 5)), 4).length, 1);
  });
}
