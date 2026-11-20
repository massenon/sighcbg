// Les fiches d'aide de l'assistant (E4820 à E4829) : rédaction, validation par geste réservé, auteur ≠ validateur, validation d'un professionnel nommé pour la check-liste du bloc (Q94),
// archivage (jamais de suppression), statut calculé des fiches attendues, règle d'écriture entre postes. Le moteur ne cite qu'une fiche VALIDÉE avec son validateur nommé et sa date.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

import '../tool/src/assistant_mesure.dart';

Map<String, Object?> _json(String chemin) => (jsonDecode(File(chemin).readAsStringSync()) as Map).cast<String, Object?>();

final auj = DateTime(2026, 11, 17, 9, 0);

void main() {
  final rbac = _json('../rbac/data/rbac.json');
  final manifeste = Manifeste.depuisJson(_json('../referentiels/data/manifeste.json'));
  final magasin = _json('test/vecteurs/assistant_magasin_agents.json');
  // les rôles de la MATRICE (jamais une liste écrite ici)
  final roles = [for (final r in rbac['roles'] as List) '${(r as Map)['id']}'];
  final ecrans = [for (final e in manifeste.tousLesEcrans) e.id];
  final gestes = gestesOrigine();

  // Les rôles qui détiennent les gestes, LUS du référentiel (le test ne nomme aucun rôle).
  final validateur = gesteReserve(gesteFichesAideValider)!.rolesDefaut.first;
  final professionnel = gesteReserve(gesteValiderRefBloc)!.rolesDefaut.first;
  final sansGeste = roles.firstWhere((r) => !gestes.peut(r, gesteFichesAideValider) && !gestes.peut(r, gesteValiderRefBloc));

  Map<String, Object?> saisie({String type = ficheAideTypeAide, List<String> roles = const [], String? domainePro, int? question}) => {
        'type': type,
        'titre': 'Enregistrer un courrier entrant',
        'motsCles': ['courrier entrant', 'courrier arrivée'],
        'roles': roles,
        'ecrans': [ecrans.first],
        if (type == ficheAideTypeAide) 'etapes': ['Ouvrir l’écran', 'Choisir « arrivée »'] else 'definition': 'Une pièce qui annule tout ou partie d’une facture.',
        if (domainePro != null) 'domainePro': domainePro,
        if (question != null) 'questionAttendue': question,
      };

  Map<String, Object?> creer(Map<String, Object?> s, {String id = 'FA-1', String auteur = 'U-AUTEUR'}) => creerFicheAide(
          saisie: s, id: id, auteurId: auteur, auteurNom: 'Auteur Fictif', maintenant: auj, rolesConnus: roles, ecransConnus: ecrans)
      .fiche!;

  VerdictFicheAide valider(Map<String, Object?>? f, {String? role, String id = 'U-VALIDEUR', String nom = 'Valideur Fictif', String? pro, String? proLe, bool fileul = false, DroitsGestes? g}) => validerFicheAide(
      fiche: f,
      role: role ?? validateur,
      validateurId: id,
      validateurNom: nom,
      maintenant: auj,
      gestes: g ?? gestes,
      rolesConnus: roles,
      professionnel: pro,
      professionnelLe: proLe,
      estFileul: fileul);

  group('la liste des fiches ATTENDUES est celle du document des 100 questions', () {
    test('mêmes numéros, mêmes textes, même rôle d’origine, même type ; Q94 engage un professionnel', () {
      final lues = <int, ({String role, String question, String decision})>{};
      String? role;
      for (final l in File('../../docs/prd/ASSISTANT-100-questions-par-role.md').readAsLinesSync()) {
        final r = RegExp(r'^## (.*) \(`\w+`\)').firstMatch(l);
        if (r != null) role = r.group(1);
        final m = RegExp(r'^\| (\d+) \| (.*?) \| (I\d+|HC) \| (.*?) \| (.*?) \| (.*) \|$').firstMatch(l);
        if (m != null && m.group(6)!.startsWith('Validée (fiche')) lues[int.parse(m.group(1)!)] = (role: role!, question: m.group(2)!, decision: m.group(6)!);
      }
      expect(lues.keys.toList()..sort(), [for (final a in fichesAideAttendues) a.numero]);
      for (final a in fichesAideAttendues) {
        final l = lues[a.numero]!;
        expect(a.question, l.question, reason: 'Q${a.numero}');
        expect(a.libelleRole, l.role, reason: 'Q${a.numero}');
        expect(a.type, l.decision.contains('définition') ? ficheAideTypeDefinition : ficheAideTypeAide, reason: 'Q${a.numero}');
        expect(a.domainePro != null, l.decision.contains('professionnel nommé'), reason: 'Q${a.numero} : seule la check-liste du bloc exige un professionnel');
      }
      expect(fichesAideAttendues.length, 9, reason: 'sept procédures, la check-liste du bloc, la définition d’un avoir');
    });
    test('sans aucune fiche écrite, TOUTES sont « pas encore écrites » (statut calculé, rien n’est livré)', () {
      for (final a in fichesAideAttendues) {
        expect(statutFicheAttendue(a, const []), attendueAEcrire);
      }
    });
    test('le statut se calcule : écrite non validée → en attente ; validée citable → validée ; archivée → de nouveau à écrire', () {
      final a = fichesAideAttendues.first;
      final f = creer(saisie(question: a.numero));
      expect(statutFicheAttendue(a, [f]), attendueProposee);
      final v = {...f, ...valider(f).fiche!};
      expect(statutFicheAttendue(a, [v]), attendueValidee);
      expect(statutFicheAttendue(a, [{...v, 'statut': ficheAideArchivee}]), attendueAEcrire);
      // une fiche « validée » sans validateur n'est pas citable : elle ne compte pas comme validée
      expect(statutFicheAttendue(a, [{...v, 'validePar': ''}]), attendueProposee);
      // une fiche liée à une AUTRE question ne compte pas
      expect(statutFicheAttendue(fichesAideAttendues.last, [v]), attendueAEcrire);
    });
  });

  group('rédaction : une fiche naît proposée, avec son auteur ; le contenu est contrôlé', () {
    test('création : proposée, auteur nommé, jamais validée', () {
      final f = creer(saisie());
      expect(f['statut'], ficheAideProposee);
      expect(f['auteurId'], 'U-AUTEUR');
      expect(f['auteurNom'], 'Auteur Fictif');
      for (final k in ficheAideChampsValidation) {
        expect(f.containsKey(k), isFalse, reason: k);
      }
    });
    test('refus nommés : titre, mots-clés, étapes, définition, rôle hors matrice, écran inconnu, domaine inconnu, question inconnue, auteur anonyme', () {
      String? code(Map<String, Object?> s) => creerFicheAide(saisie: s, id: 'x', auteurId: 'U', auteurNom: 'N', maintenant: auj, rolesConnus: roles, ecransConnus: ecrans).refus?.code;
      expect(code({...saisie(), 'titre': ' '}), 'TITRE_ABSENT');
      expect(code({...saisie(), 'motsCles': []}), 'MOTS_CLES_ABSENTS');
      expect(code({...saisie(), 'etapes': []}), 'ETAPES_ABSENTES');
      expect(code({...saisie(type: ficheAideTypeDefinition), 'definition': ''}), 'DEFINITION_ABSENTE');
      expect(code({...saisie(), 'type': 'autre'}), 'TYPE_INVALIDE');
      expect(code(saisie(roles: ['role_fantome'])), 'ROLE_INCONNU');
      expect(code({...saisie(), 'ecrans': ['ecran-fantome']}), 'ECRAN_INCONNU');
      expect(code(saisie(domainePro: 'astrologie')), 'DOMAINE_INCONNU');
      expect(code(saisie(question: 7)), 'QUESTION_INCONNUE');
      expect(creerFicheAide(saisie: saisie(), id: 'x', auteurId: '', auteurNom: '', maintenant: auj, rolesConnus: roles).refus!.code, 'AUTEUR_ABSENT');
      expect(code(saisie(roles: [roles.first])), isNull, reason: 'un rôle de la matrice est accepté');
    });
    test('la liste des rôles autorisés vient de la matrice : un rôle de la matrice passe, un rôle inventé est refusé', () {
      expect(roles, isNotEmpty);
      for (final r in roles) {
        expect(creerFicheAide(saisie: saisie(roles: [r]), id: 'x', auteurId: 'U', auteurNom: 'N', maintenant: auj, rolesConnus: roles).accepte, isTrue, reason: r);
      }
    });
    test('mots-clés et rôles sans vides ni doublons', () {
      final f = creer({...saisie(), 'motsCles': ['a', ' a ', '', 'b'], 'roles': []});
      expect(f['motsCles'], ['a', 'b']);
    });
    test('une fiche non validée se modifie ; une fiche validée ne se réécrit pas (on la révise) ; archivée non plus', () {
      final f = creer(saisie());
      final m = modifierFicheAide(actuelle: f, saisie: {'titre': 'Nouveau titre'}, maintenant: auj, rolesConnus: roles);
      expect(m.fiche!['titre'], 'Nouveau titre');
      expect(m.fiche!['modifieLe'], isNotNull);
      final v = {...f, ...valider(f).fiche!};
      expect(modifierFicheAide(actuelle: v, saisie: {'titre': 'x'}, maintenant: auj, rolesConnus: roles).refus!.code, 'FICHE_VALIDEE');
      expect(modifierFicheAide(actuelle: {...f, 'statut': ficheAideArchivee}, saisie: {}, maintenant: auj, rolesConnus: roles).refus!.code, 'FICHE_ARCHIVEE');
      expect(modifierFicheAide(actuelle: null, saisie: {}, maintenant: auj, rolesConnus: roles).refus!.code, 'FICHE_INCONNUE');
    });
    test('réviser une fiche validée crée une fiche nouvelle, proposée, qui la remplace ; la validée reste citée jusque-là', () {
      final f = creer(saisie());
      final v = {...f, ...valider(f).fiche!};
      final r = reviserFicheAide(source: v, id: 'FA-2', auteurId: 'U-AUTEUR', auteurNom: 'Auteur Fictif', maintenant: auj, rolesConnus: roles).fiche!;
      expect(r['statut'], ficheAideProposee);
      expect(r['remplace'], 'FA-1');
      for (final k in ficheAideChampsValidation) {
        expect(r.containsKey(k), isFalse, reason: k);
      }
      expect(ficheAideCitable(v), isTrue);
      expect(reviserFicheAide(source: f, id: 'FA-3', auteurId: 'U', auteurNom: 'N', maintenant: auj, rolesConnus: roles).refus!.code, 'REVISION_SANS_OBJET');
      // valider la remplaçante désigne la fiche à archiver
      final r2 = {...r, 'auteurId': 'U-AUTEUR'};
      expect(valider(r2).archiver, 'FA-1');
    });
  });

  group('validation : geste réservé, validateur nommé, jamais l’auteur', () {
    test('le validateur détient le geste, est nommé : la fiche porte son validateur, son compte et la date du jour', () {
      final p = valider(creer(saisie())).fiche!;
      expect(p['statut'], ficheAideValidee);
      expect(p['validePar'], 'Valideur Fictif');
      expect(p['validateurId'], 'U-VALIDEUR');
      expect(p['valideLe'], '2026-11-17');
      expect(ficheAideCitable({...creer(saisie()), ...p}), isTrue);
    });
    test('sans le geste réservé : refus nommé, aucune fiche n’est validée', () {
      final v = valider(creer(saisie()), role: sansGeste);
      expect(v.accepte, isFalse);
      expect(v.refus!.code, 'GESTE_RESERVE');
    });
    test('la clinique accorde ou retire le geste par la fiche de rôle', () {
      final accorde = DroitsGestes(fiches: [
        {'id': 'RBAC-Z', 'role': sansGeste, 'statut': 'actif', 'droitsGestes': {gesteFichesAideValider: true}}
      ]);
      expect(valider(creer(saisie()), role: sansGeste, g: accorde).accepte, isTrue);
      final retire = DroitsGestes(fiches: [
        {'id': 'RBAC-Y', 'role': validateur, 'statut': 'actif', 'droitsGestes': {gesteFichesAideValider: false}}
      ]);
      expect(valider(creer(saisie()), g: retire).refus!.code, 'GESTE_RESERVE');
    });
    test('l’auteur ne valide pas sa propre fiche, même avec le geste', () {
      final v = valider(creer(saisie(), auteur: 'U-MEME'), id: 'U-MEME');
      expect(v.refus!.code, 'AUTEUR_NE_VALIDE_PAS');
    });
    test('un validateur anonyme est refusé (RG-12) ; une fiche sans auteur connu ne se valide pas', () {
      expect(valider(creer(saisie()), id: '', nom: '').refus!.code, 'VALIDATEUR_ABSENT');
      expect(valider({...creer(saisie()), 'auteurId': ''}).refus!.code, 'AUTEUR_INCONNU');
    });
    test('déjà validée, archivée, inconnue ; un poste rattaché n’écrit pas la validation', () {
      final f = creer(saisie());
      expect(valider({...f, 'statut': ficheAideValidee}).refus!.code, 'DEJA_VALIDEE');
      expect(valider({...f, 'statut': ficheAideArchivee}).refus!.code, 'FICHE_ARCHIVEE');
      expect(valider(null).refus!.code, 'FICHE_INCONNUE');
      expect(valider(f, fileul: true).refus!.code, 'REGLE_SUR_LA_MERE');
    });
    test('un rôle cité par la fiche qui a disparu de la matrice bloque la validation (nommé)', () {
      final f = {...creer(saisie()), 'roles': ['role_disparu']};
      expect(valider(f).refus!.code, 'ROLE_INCONNU');
    });
  });

  group('la check-liste du bloc (Q94) : validation réservée à un professionnel nommé, daté', () {
    final bloc = fichesAideDomainesPro.first.id;
    test('un détenteur du geste générique qui n’est pas le professionnel est refusé, nommément', () {
      final f = creer(saisie(domainePro: bloc));
      final v = valider(f, pro: 'Dr Fictif', proLe: '2026-11-16');
      expect(v.refus!.code, 'PROFESSIONNEL_REQUIS');
    });
    test('le professionnel doit AUSSI détenir le geste générique (la fiche reste une fiche d’aide) — la clinique règle les deux', () {
      final f = creer(saisie(domainePro: bloc));
      final g = DroitsGestes(fiches: [
        {'id': 'RBAC-P', 'role': professionnel, 'statut': 'actif', 'droitsGestes': {gesteFichesAideValider: true}}
      ]);
      // sans le geste générique, même le professionnel est refusé ; avec les deux, la validation passe
      expect(valider(f, role: professionnel, pro: 'Dr Fictif', proLe: '2026-11-16').refus!.code, 'GESTE_RESERVE');
      expect(valider(f, role: professionnel, pro: 'Dr Fictif', proLe: '2026-11-16', g: g).accepte, isTrue);
    });
    test('« validé par (professionnel) » non vide et daté : champ vide, date absente, mal formée ou future → refus nommés', () {
      final f = creer(saisie(domainePro: bloc));
      final g = DroitsGestes(fiches: [
        {'id': 'RBAC-P', 'role': professionnel, 'statut': 'actif', 'droitsGestes': {gesteFichesAideValider: true}}
      ]);
      String? code({String? pro, String? le}) => valider(f, role: professionnel, pro: pro, proLe: le, g: g).refus?.code;
      expect(code(pro: '', le: '2026-11-16'), 'PROFESSIONNEL_ABSENT');
      expect(code(pro: null, le: '2026-11-16'), 'PROFESSIONNEL_ABSENT');
      expect(code(pro: 'Dr Fictif', le: ''), 'DATE_PROFESSIONNEL_INVALIDE');
      expect(code(pro: 'Dr Fictif', le: '16/11/2026'), 'DATE_PROFESSIONNEL_INVALIDE');
      expect(code(pro: 'Dr Fictif', le: '2026-02-31'), 'DATE_PROFESSIONNEL_INVALIDE');
      expect(code(pro: 'Dr Fictif', le: '2026-12-01'), 'DATE_PROFESSIONNEL_FUTURE');
      final ok = valider(f, role: professionnel, pro: ' Dr Fictif ', proLe: '2026-11-16', g: g).fiche!;
      expect(ok['professionnel'], 'Dr Fictif');
      expect(ok['professionnelLe'], '2026-11-16');
      expect(ficheAideCitable({...f, ...ok}), isTrue);
    });
    test('une fiche du bloc « validée » sans le nom du professionnel n’est PAS citable', () {
      final f = creer(saisie(domainePro: bloc));
      final sans = {...f, 'statut': ficheAideValidee, 'validePar': 'Direction', 'valideLe': '2026-11-17', 'validateurId': 'U-V'};
      expect(ficheAideCitable(sans), isFalse);
      expect(ficheAideCitable({...sans, 'professionnel': 'Dr Fictif', 'professionnelLe': '2026-11-16'}), isTrue);
    });
  });

  group('archivage : jamais de suppression', () {
    test('motif et auteur obligatoires ; le statut passe à archive, l’ancien est gardé', () {
      final f = creer(saisie());
      expect(archiverFicheAide(fiche: f, motif: ' ', auteurNom: 'A', maintenant: auj).refus!.code, 'MOTIF_ABSENT');
      expect(archiverFicheAide(fiche: f, motif: 'm', auteurNom: '', maintenant: auj).refus!.code, 'AUTEUR_ABSENT');
      expect(archiverFicheAide(fiche: null, motif: 'm', auteurNom: 'A', maintenant: auj).refus!.code, 'FICHE_INCONNUE');
      expect(archiverFicheAide(fiche: {...f, 'statut': ficheAideArchivee}, motif: 'm', auteurNom: 'A', maintenant: auj).refus!.code, 'DEJA_ARCHIVEE');
      final p = archiverFicheAide(fiche: f, motif: 'Procédure changée', auteurNom: 'Archiviste', maintenant: auj).fiche!;
      expect(p['statut'], ficheAideArchivee);
      expect(p['statutAvantArchivage'], ficheAideProposee);
      expect(p['archivePar'], 'Archiviste');
      expect(p['motifArchivage'], 'Procédure changée');
    });
  });

  group('règle d’écriture entre postes : la validation ne s’écrit que sur la mère', () {
    test('un poste ne crée pas une fiche déjà validée, ne pose aucun champ de validation, ne valide pas', () {
      expect(refusEcritureFicheAide('creer', {'statut': 'validee', 'titre': 'x'})!.code, 'validation_reservee_mere');
      expect(refusEcritureFicheAide('creer', {'validePar': 'Moi'})!.code, 'validation_reservee_mere');
      expect(refusEcritureFicheAide('modifier', {'statut': 'validee'}, actuelle: {'statut': 'proposee'})!.code, 'validation_reservee_mere');
      expect(refusEcritureFicheAide('modifier', {'professionnel': 'Dr X'}, actuelle: {'statut': 'proposee'})!.code, 'validation_reservee_mere');
      expect(refusEcritureFicheAide('creer', {'titre': 'x', 'statut': 'proposee'}), isNull);
    });
    test('une fiche validée ne se réécrit pas ; l’archiver (champs d’archivage) reste permis', () {
      final v = {'statut': 'validee', 'titre': 'T', 'validePar': 'D', 'valideLe': '2026-11-17', 'etapes': ['a']};
      expect(refusEcritureFicheAide('modifier', {'titre': 'Autre'}, actuelle: v)!.code, 'fiche_validee');
      expect(refusEcritureFicheAide('modifier', {'etapes': ['b']}, actuelle: v)!.code, 'fiche_validee');
      expect(refusEcritureFicheAide('modifier', {'titre': 'T'}, actuelle: v), isNull, reason: 'même valeur : rien ne change');
      expect(refusEcritureFicheAide('modifier', {'statut': 'archive', 'archivePar': 'A', 'motifArchivage': 'm'}, actuelle: v), isNull);
    });
    test('un refus porte un motif et un geste', () {
      final r = refusEcritureFicheAide('creer', {'statut': 'validee'})!;
      expect(r.motif, isNotEmpty);
      expect(r.geste, isNotEmpty);
    });
  });

  test('la garde du moteur : le CONTENU d’une fiche validée ne se réécrit pas ; la validation, l’archivage et le reste passent', () {
    final f = creer(saisie());
    final v = {...f, ...valider(f).fiche!};
    expect(gardeFicheAide('modifier', {...v, 'titre': 'Autre'}, v), contains('ne se réécrit pas'));
    expect(gardeFicheAide('modifier', {...v, 'etapes': ['x']}, v), isNotNull);
    expect(gardeFicheAide('modifier', {...v, 'statut': ficheAideArchivee, 'motifArchivage': 'm'}, v), isNull, reason: 'archiver reste permis');
    expect(gardeFicheAide('modifier', {...f, 'statut': ficheAideValidee, 'validePar': 'D'}, f), isNull, reason: 'valider une fiche proposée');
    expect(gardeFicheAide('modifier', {...f, 'titre': 'Autre'}, f), isNull, reason: 'une fiche non validée se corrige');
    expect(gardeFicheAide('inserer', v, null), isNull);
  });

  group('le moteur de l’assistant ne cite QUE ce qui est validé avec son validateur', () {
    final questions = [for (final q in (_json('test/vecteurs/assistant_questions_agents.json')['questions'] as List)) (q as Map).cast<String, Object?>()];
    Map<String, Object?> question(int n) => questions.firstWhere((q) => q['n'] == n);
    final a = AssistantAst();
    ReponseAst pose(int n, List<Map<String, Object?>> fiches) {
      final role = '${question(n)['role']}';
      final base = contexteMesure(magasin, rbac, manifeste, role);
      final cx = ContexteAst(
          role: role,
          lire: (nom) => nom == colFichesAide ? fiches : base.lire(nom),
          peutVoirEcran: base.peutVoirEcran,
          sensibles: base.sensibles,
          maintenant: base.maintenant,
          session: base.session,
          libelleEcran: base.libelleEcran,
          matrice: base.matrice);
      return a.repondre('${question(n)['question']}', cx);
    }

    Map<String, Object?> fiche({String statut = 'validee', Object? validePar = 'Valideur Fictif', Object? valideLe = '2026-11-17', Map<String, Object?> en = const {}}) => {
          'id': 'F1',
          'type': 'aide',
          'statut': statut,
          'titre': 'Fiche d’exemple',
          'motsCles': ['courrier entrant'],
          'etapes': ['Ouvrir l’écran du courrier', 'Choisir « arrivée »'],
          'ecrans': [ecrans.first],
          'validePar': validePar,
          'valideLe': valideLe,
          ...en,
        };

    test('validée avec son validateur et sa date : citée', () {
      final r = pose(58, [fiche()]);
      expect(r.statut, 'reponse');
      expect(r.lignes.join(' | '), contains('Fiche validée par Valideur Fictif le 17/11/2026'));
    });
    test('« validée » SANS validateur ou SANS date : jamais citée (« pas de fiche »), et la réponse le dit', () {
      for (final f in [fiche(validePar: ''), fiche(validePar: null), fiche(valideLe: ''), fiche(valideLe: null)]) {
        final r = pose(58, [f]);
        expect(r.code, 'PAS_DE_FICHE', reason: '$f');
        expect(r.lignes.join(' | '), contains('ne sont pas encore validées'));
      }
    });
    test('proposée ou archivée : jamais citée', () {
      expect(pose(58, [fiche(statut: 'proposee')]).code, 'PAS_DE_FICHE');
      expect(pose(58, [fiche(statut: 'archive')]).code, 'PAS_DE_FICHE');
    });
    test('une fiche qui engage un professionnel n’est citée qu’avec son nom et sa date', () {
      final bloc = fichesAideDomainesPro.first.id;
      final sans = fiche(en: {'domainePro': bloc});
      expect(pose(94, [{...sans, 'motsCles': ['check-list', 'check list', 'bloc']}]).code, 'PAS_DE_FICHE');
      final avec = {...sans, 'motsCles': ['check-list', 'check list', 'bloc'], 'professionnel': 'Dr Fictif', 'professionnelLe': '2026-11-16'};
      final r = pose(94, [avec]);
      expect(r.statut, 'reponse');
      expect(r.lignes.join(' | '), contains('Relue par le professionnel : Dr Fictif le 16/11/2026'));
    });
    test('réservée à des rôles : ne se montre qu’à eux (liste de la matrice)', () {
      final r = pose(58, [fiche(en: {'roles': ['role_fantome']})]);
      expect(r.code, 'PAS_DE_FICHE');
    });
  });
}
