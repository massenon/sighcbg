// La validation d'une fiche d'aide DEPUIS UN POSTE RATTACHÉ (Direction de Baguidi, 18/11/2026, point 3) : le fileul DÉPOSE la demande (genre `fiche_aide_valider`), la mère l'applique en refaisant
// tous les contrôles de la validation directe sous le rôle et le nom du déposant ; le verdict est nommé ; rien n'est validé avant la confirmation. Aucun nom de rôle écrit ici : les rôles viennent
// du référentiel des gestes réservés et de la matrice.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> _json(String chemin) => (jsonDecode(File(chemin).readAsStringSync()) as Map).cast<String, Object?>();

final auj = DateTime(2026, 11, 18, 9, 0);

void main() {
  final rbac = _json('../rbac/data/rbac.json');
  final manifeste = Manifeste.depuisJson(_json('../referentiels/data/manifeste.json'));
  final roles = [for (final r in rbac['roles'] as List) '${(r as Map)['id']}'];
  final ecrans = [for (final e in manifeste.tousLesEcrans) e.id];
  final gestes = gestesOrigine();
  final validateur = gesteReserve(gesteFichesAideValider)!.rolesDefaut.first;
  final professionnelRole = gesteReserve(gesteValiderRefBloc)!.rolesDefaut.first;
  final sansGeste = roles.firstWhere((r) => !gestes.peut(r, gesteFichesAideValider) && !gestes.peut(r, gesteValiderRefBloc));

  Map<String, Object?> fiche({String id = 'FAI-F1-1', String auteur = 'U-AUTEUR', String? domainePro, String? remplace}) => creerFicheAide(
          saisie: {
            'type': ficheAideTypeAide,
            'titre': 'Enregistrer un courrier entrant',
            'motsCles': ['courrier entrant'],
            'roles': <String>[],
            'ecrans': [ecrans.first],
            'etapes': ['Ouvrir l’écran', 'Choisir « arrivée »'],
            if (domainePro != null) 'domainePro': domainePro,
            if (remplace != null) 'remplace': remplace,
          },
          id: id,
          auteurId: auteur,
          auteurNom: 'Auteur Fictif',
          maintenant: auj,
          rolesConnus: roles,
          ecransConnus: ecrans)
      .fiche!;

  // La matrice d'un poste où le validateur détient AUSSI le geste du professionnel du bloc (accordé par une fiche de rôle, jamais un nom écrit ici).
  final gBloc = DroitsGestes(fiches: [
    {'id': 'RBAC-BLOC', 'role': validateur, 'statut': 'actif', 'droitsGestes': {gesteValiderRefBloc: true}}
  ]);

  var n = 0;
  String nouvelId() => 'VDP-F1-${++n}';

  VerdictDepot deposer(Map<String, Object?>? f, {String? role, String valideur = 'U-VALIDEUR', List<Map<String, Object?>> depots = const [], DroitsGestes? g, String? pro, String? proLe}) => ficheAideValiderDeposer(
      ficheId: '${f?['id'] ?? 'FAI-F1-1'}',
      fiche: f,
      role: role ?? validateur,
      validateurId: valideur,
      validateurNom: 'Valideur Fictif',
      poste: 'F1',
      maintenant: auj,
      gestes: g ?? gestes,
      rolesConnus: roles,
      depots: depots,
      nouvelId: nouvelId,
      professionnel: pro,
      professionnelLe: pro == null ? null : (proLe ?? '2026-11-17'));

  ApplicationFicheAideValider? appliquer(Map<String, Object?> dep, Map<String, Object?>? f, {Map<String, Object?>? remplacee, DroitsGestes? g, DateTime? maintenant}) =>
      ficheAideValiderAppliquer(dep, fiche: f, remplacee: remplacee, gestes: g ?? gestes, rolesConnus: roles, maintenant: maintenant ?? auj.add(const Duration(hours: 2)));

  group('le dépôt du fileul', () {
    test('contrôle à blanc : les refus de la validation directe se nomment DÈS LE POSTE, rien n’est déposé', () {
      expect(deposer(fiche(), role: sansGeste).refus!.code, 'GESTE_RESERVE');
      expect(deposer(fiche(auteur: 'U-VALIDEUR')).refus!.code, 'AUTEUR_NE_VALIDE_PAS');
      expect(deposer(null).refus!.code, 'FICHE_INCONNUE');
      expect(deposer({...fiche(), 'statut': ficheAideValidee}).refus!.code, 'DEJA_VALIDEE');
      expect(deposer({...fiche(), 'statut': ficheAideArchivee}).refus!.code, 'FICHE_ARCHIVEE');
      expect(deposer(fiche(), valideur: '').refus!.code, 'VALIDATEUR_ABSENT');
    });

    test('le dépôt porte le validateur (l’agent connecté), son rôle, son poste, l’instant du geste ; il désigne la fiche et rien d’autre', () {
      final v = deposer(fiche());
      expect(v.ok, isTrue, reason: '${v.refus?.code}');
      final d = v.fiche!;
      expect([d['genre'], d['cible'], d['etat'], d['demandeRole'], d['demandePar'], d['validateurId'], d['demandePoste']],
          [valGenreFicheAideValider, 'FAI-F1-1', valDepotDeposee, validateur, 'Valideur Fictif', 'U-VALIDEUR', 'F1']);
      expect(d['libelle'], contains('Enregistrer un courrier entrant'));
      expect(DateTime.parse('${d['demandeLe']}').isAtSameMomentAs(auj), isTrue);
      expect(d.containsKey('professionnel'), isFalse);
    });

    test('rejouable : un dépôt identique qui attend la mère n’est pas doublé ; un autre validateur dépose le sien', () {
      final premier = deposer(fiche()).fiche!;
      final second = deposer(fiche(), depots: [premier]);
      expect(second.dejaDepose, isTrue);
      expect(second.fiche!['id'], premier['id']);
      expect(deposer(fiche(), valideur: 'U-AUTRE', depots: [premier]).dejaDepose, isFalse);
      expect(deposer(fiche(), depots: [{...premier, 'etat': valDepotRefusee}]).dejaDepose, isFalse, reason: 'un dépôt déjà jugé ne bloque pas un nouveau geste');
    });

    test('la check-liste du bloc : le geste du professionnel, son nom et la date sont contrôlés dès le poste, puis portés par le dépôt', () {
      final f = fiche(domainePro: 'bloc');
      expect(deposer(f, pro: 'Dr Fictif').refus!.code, 'PROFESSIONNEL_REQUIS', reason: 'le validateur de fiches seul ne détient pas le geste du professionnel');
      expect(deposer(f, g: gBloc).refus!.code, 'PROFESSIONNEL_ABSENT');
      expect(deposer(f, g: gBloc, pro: 'Dr Fictif', proLe: '2999-01-01').refus!.code, 'DATE_PROFESSIONNEL_FUTURE');
      expect(deposer(f, g: gBloc, pro: 'Dr Fictif', proLe: '17/11/2026').refus!.code, 'DATE_PROFESSIONNEL_INVALIDE');
      final ok = deposer(f, g: gBloc, pro: 'Dr Fictif');
      expect(ok.ok, isTrue, reason: '${ok.refus?.code}');
      expect([ok.fiche!['professionnel'], ok.fiche!['professionnelLe']], ['Dr Fictif', '2026-11-17']);
    });
  });

  group('l’application par la mère', () {
    test('elle refait les contrôles sous le rôle et le nom du déposant, à la date de SON geste : patch de validation, jamais la date de l’application', () {
      final dep = deposer(fiche()).fiche!;
      final a = appliquer(dep, fiche())!;
      expect(a.etat, valDepotAppliquee);
      expect([a.patch!['statut'], a.patch!['validateurId'], a.patch!['validePar'], a.patch!['valideLe']], [ficheAideValidee, 'U-VALIDEUR', 'Valideur Fictif', '2026-11-18']);
      final tard = appliquer(dep, fiche(), maintenant: auj.add(const Duration(days: 3)))!;
      expect(tard.patch!['valideLe'], '2026-11-18', reason: 'la validation n’est pas postdatée par la date d’application');
    });

    test('verdicts NOMMÉS : le geste retiré depuis le dépôt, l’auteur identique côté mère, la fiche archivée entre-temps, la fiche inconnue de la mère', () {
      final dep = deposer(fiche()).fiche!;
      final retire = DroitsGestes(fiches: [
        {'id': 'RBAC-X', 'role': validateur, 'statut': 'actif', 'droitsGestes': {gesteFichesAideValider: false}}
      ]);
      expect(appliquer(dep, fiche(), g: retire)!.code, 'GESTE_RESERVE', reason: 'la mère relit SA matrice, pas celle du fileul au moment du dépôt');
      expect(appliquer(dep, fiche(auteur: 'U-VALIDEUR'))!.code, 'AUTEUR_NE_VALIDE_PAS', reason: 'l’auteur que la MÈRE connaît');
      expect(appliquer(dep, {...fiche(), 'statut': ficheAideArchivee})!.code, 'FICHE_ARCHIVEE');
      final inconnue = appliquer(dep, null)!;
      expect([inconnue.etat, inconnue.code], [valDepotRefusee, 'FICHE_INCONNUE']);
      for (final r in [appliquer(dep, fiche(auteur: 'U-VALIDEUR'))!, inconnue]) {
        expect(r.motif, isNotEmpty);
        expect(r.geste, isNotEmpty);
        expect(r.patch, isNull, reason: 'un refus n’écrit rien');
      }
    });

    test('la validation porte sur ce que le validateur a LU : une fiche réécrite entre-temps est refusée (FICHE_MODIFIEE), la fiche inchangée passe', () {
      final dep = deposer(fiche()).fiche!;
      expect(dep['contenuVu'], isNotNull);
      final reecrite = {...fiche(), 'etapes': ['Autre étape']};
      final a = appliquer(dep, reecrite)!;
      expect([a.etat, a.code], [valDepotRefusee, 'FICHE_MODIFIEE']);
      expect(a.patch, isNull);
      expect(a.geste, isNotEmpty);
      expect(appliquer(dep, {...fiche(), 'creeLe': 'autre date', 'auteurNom': 'Autre'})!.etat, valDepotAppliquee, reason: 'seul le CONTENU relu compte, pas les marques de la fiche');
    });

    test('une fiche déjà validée rend « sans effet », nommé : jamais une seconde trace', () {
      final dep = deposer(fiche()).fiche!;
      final a = appliquer(dep, {...fiche(), 'statut': ficheAideValidee, 'validePar': 'Autre'})!;
      expect([a.etat, a.code], [valDepotSansEffet, 'DEJA_VALIDEE']);
      expect(a.patch, isNull);
    });

    test('un dépôt déjà traité, archivé ou d’un autre genre n’est pas rejoué (null)', () {
      final dep = deposer(fiche()).fiche!;
      expect(appliquer({...dep, 'etat': valDepotAppliquee}, fiche()), isNull);
      expect(appliquer({...dep, 'statut': 'archive'}, fiche()), isNull);
      expect(appliquer({...dep, 'genre': valGenreReferentiel}, fiche()), isNull);
    });

    test('une fiche qui en remplace une autre : la remplacée est archivée avec un motif (RG-14), jamais supprimée', () {
      final nouvelle = fiche(id: 'FAI-F1-2', remplace: 'FAI-F1-1');
      final dep = deposer(nouvelle).fiche!;
      final a = appliquer(dep, nouvelle, remplacee: fiche())!;
      expect(a.etat, valDepotAppliquee);
      expect(a.archiver, 'FAI-F1-1');
      expect(a.archivage!['statut'], ficheAideArchivee);
      expect(a.archivage!['motifArchivage'], contains('FAI-F1-2'));
      expect(appliquer(dep, nouvelle, remplacee: {...fiche(), 'statut': ficheAideArchivee})!.archivage, isNull, reason: 'déjà archivée : rien à archiver deux fois');
    });

    test('la check-liste du bloc : la mère exige AUSSI le geste du professionnel, son nom et sa date, relus de sa matrice', () {
      final f = fiche(domainePro: 'bloc');
      final dep = deposer(f, g: gBloc, pro: 'Dr Fictif').fiche!;
      expect(appliquer(dep, f, g: gBloc)!.etat, valDepotAppliquee);
      final patch = appliquer(dep, f, g: gBloc)!.patch!;
      expect([patch['professionnel'], patch['professionnelLe']], ['Dr Fictif', '2026-11-17']);
      expect(appliquer(dep, f)!.code, 'PROFESSIONNEL_REQUIS', reason: 'la matrice de la MÈRE ne donne pas le geste du professionnel à ce rôle : refus nommé');
      expect(appliquer({...dep}..remove('professionnel'), f, g: gBloc)!.code, 'PROFESSIONNEL_ABSENT');
      expect(appliquer({...dep, 'professionnelLe': '2999-01-01'}, f, g: gBloc)!.code, 'DATE_PROFESSIONNEL_FUTURE');
    });
  });

  group('lecture de l’état d’une fiche', () {
    test('en attente, ou refusée avec son motif nommé ; un dépôt plus récent efface le refus', () {
      final d1 = {...deposer(fiche()).fiche!, 'demandeLe': '2026-11-18T07:00:00.000Z'};
      expect(ficheAideDepotEnAttente([d1], 'FAI-F1-1'), isNotNull);
      expect(ficheAideDepotEnAttente([d1], 'FAI-F1-9'), isNull);
      final refuse = {...d1, 'etat': valDepotRefusee, 'resultatCode': 'GESTE_RESERVE'};
      expect(ficheAideDepotEnAttente([refuse], 'FAI-F1-1'), isNull);
      expect(ficheAideDepotRefuse([refuse], 'FAI-F1-1')!['resultatCode'], 'GESTE_RESERVE');
      final plusRecent = {...d1, 'id': 'VDP-2', 'demandeLe': '2026-11-18T08:00:00.000Z'};
      expect(ficheAideDepotRefuse([refuse, plusRecent], 'FAI-F1-1'), isNull);
    });

    test('l’alerte après le délai de la mère part vers ceux qui détiennent le geste de validation (lu dans la matrice), plus l’administrateur', () {
      final d = DecisionEnAttente(genre: genreDecisionValidation, id: 'V1', libelle: 'x', par: 'A', role: 'r', depuis: auj, sousGenre: valGenreFicheAideValider, famille: colFichesAide);
      final dest = destinatairesAlerteDecision(d, gesteCircuit: 'g', gestePrix: 'p');
      expect(dest, contains('geste:$gesteFichesAideValider'));
      expect(dest, contains(posteAdministrateur));
      final enRetard = decisionsEnRetard([d], auj.add(const Duration(hours: 5)), 4);
      expect(enRetard.length, 1, reason: 'au-delà de 4 heures (le défaut du réglage), la décision est signalée');
      expect(decisionsEnAttenteMere(validations: [
        {...deposer(fiche()).fiche!}
      ], demandesPrix: const [], demandesImport: const []).single.sousGenre, valGenreFicheAideValider);
    });
  });
}
