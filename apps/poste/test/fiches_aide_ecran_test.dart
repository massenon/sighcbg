// L'écran « Fiches d'aide de l'assistant » (cfg-fiches-aide, E4820) : rédaction, validation par GESTE RÉSERVÉ (jamais par l'auteur), professionnel nommé pour la check-liste du bloc (Q94),
// archivage, fiches attendues avec leur statut calculé, gabarit vide, poste rattaché. L'assistant ne cite que ce qui est validé avec son validateur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/kit/kit.dart';
import 'package:sigh_poste/modules/cfg/registre_cfg.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

void main() {
  setUpAll(chargerPolices);

  // Les rôles se LISENT du référentiel des gestes (aucun nom écrit ici) : celui qui valide d'origine, et celui qui n'a pas le geste.
  final validateur = gesteReserve(gesteFichesAideValider)!.rolesDefaut.first;
  final professionnel = gesteReserve(gesteValiderRefBloc)!.rolesDefaut.first;

  Fiche autre({String id = 'FAI-AUTRE', String statut = 'proposee', Map<String, Object?> en = const {}}) => {
        'id': id,
        'type': 'aide',
        'statut': statut,
        'titre': 'Enregistrer un courrier entrant',
        'motsCles': ['courrier entrant'],
        'roles': <String>[],
        'ecrans': <String>[],
        'etapes': ['Ouvrir l’écran du courrier', 'Choisir « arrivée »'],
        'auteurId': 'U-AUTRE',
        'auteurNom': 'Autre Auteur',
        'creeLe': '2026-10-29T08:00:00Z',
        ...en,
      };

  Magasin magasin(List<Fiche> fiches) {
    final m = magasinM14();
    m.collection(colFichesAide).remplacerContenu(fiches);
    return m;
  }

  test('l’écran est branché au registre de CFG', () => expect(ecransCFG.keys, contains('cfg-fiches-aide')));

  casM14('sans aucune fiche : les NEUF fiches attendues sont dites « pas encore écrites » (statut calculé), le gabarit vide est là, l’assistant dit « pas de fiche validée »', (t) async {
    final m = magasin(const []);
    await ouvrirM14(t, m, 'cfg-fiches-aide', role: validateur);
    expect(find.byKey(const Key('aide:attendues')), findsOneWidget);
    expect(find.textContaining('Aucune des 9 fiches attendues n’est encore écrite'), findsOneWidget);
    expect(find.text('Pas encore écrite'), findsNWidgets(9));
    for (final a in fichesAideAttendues) {
      expect(find.text('Q${a.numero}'), findsOneWidget, reason: 'Q${a.numero}');
      expect(find.text(a.question), findsOneWidget, reason: 'la question mot pour mot');
    }
    expect(find.text('Professionnel nommé'), findsOneWidget, reason: 'la check-liste du bloc (Q94)');
    expect(find.byKey(const Key('aide:gabarit')), findsOneWidget);
    expect(find.byKey(const Key('aide:nouvelle')), findsOneWidget);
    expect(find.textContaining('Aucune fiche écrite'), findsOneWidget);
  });

  casM14('rédiger : le gabarit s’ouvre, la fiche naît PROPOSÉE avec son auteur, rien n’est validé ; le rôle sans le geste ne voit pas « Valider »', (t) async {
    // un rôle qui écrit l'écran (matrice) mais n'a pas le geste de validation d'origine
    final redacteur = ['admin', 'da', 'direction'].firstWhere((r) => !gesteReserve(gesteFichesAideValider)!.rolesDefaut.contains(r), orElse: () => '');
    expect(redacteur, isNotEmpty, reason: 'au moins un rôle de l’écran n’a pas le geste d’origine');
    final m = magasin(const []);
    await ouvrirM14(t, m, 'cfg-fiches-aide', role: redacteur);
    expect(find.byKey(const Key('aide:sans-geste')), findsOneWidget);
    await toucherM14(t, find.byKey(const Key('aide:nouvelle')));
    await saisir(t, 'titre', 'Enregistrer un courrier entrant');
    await saisir(t, 'motsCles', 'courrier entrant\ncourrier arrivée');
    await saisir(t, 'etapes', 'Ouvrir l’écran du courrier\nChoisir « arrivée »');
    await toucherM14(t, find.byKey(const Key('aide:enregistrer')));
    expect(find.byKey(const Key('aide:ok')), findsOneWidget);
    final f = m.collection(colFichesAide).toutes.single;
    expect(f['statut'], ficheAideProposee);
    expect(f['titre'], 'Enregistrer un courrier entrant');
    expect(f['motsCles'], ['courrier entrant', 'courrier arrivée']);
    expect(f['etapes'], ['Ouvrir l’écran du courrier', 'Choisir « arrivée »']);
    expect('${f['auteurId']}', isNotEmpty, reason: 'l’auteur est nommé (RG-12) : sa comparaison au validateur se fait sur l’identifiant');
    expect(f.containsKey('validePar'), isFalse);
    expect('${f['id']}', startsWith('FAI'), reason: 'identifiant attribué par la collection du poste');
    expect(find.text('Proposée'), findsOneWidget);
    expect(find.byKey(Key('aide:valider:${f['id']}')), findsNothing, reason: 'sans le geste réservé, la commande est ABSENTE');
    expect(m.collection('audit').toutes.any((x) => x['action'] == 'Création' && x['entite'] == 'Fiche d’aide'), isTrue);
    expect(ficheAideCitable(f), isFalse, reason: 'une fiche proposée n’est jamais citée');
  });

  casM14('un champ obligatoire manquant est refusé : titre, mots-clés, étapes', (t) async {
    final m = magasin(const []);
    await ouvrirM14(t, m, 'cfg-fiches-aide', role: validateur);
    await toucherM14(t, find.byKey(const Key('aide:nouvelle')));
    await toucherM14(t, find.byKey(const Key('aide:enregistrer')));
    expect(m.collection(colFichesAide).toutes, isEmpty);
    expect(find.textContaining('obligatoire'), findsWidgets);
    await saisir(t, 'titre', 'Un titre');
    await saisir(t, 'motsCles', 'un mot');
    await toucherM14(t, find.byKey(const Key('aide:enregistrer')));
    expect(find.byKey(const Key('aide:refus')), findsOneWidget);
    expect(find.textContaining('ETAPES_ABSENTES'), findsOneWidget);
    expect(m.collection(colFichesAide).toutes, isEmpty);
  });

  casM14('valider : le détenteur du geste valide la fiche d’un AUTRE ; elle porte son nom et la date ; l’assistant la cite avec son validateur', (t) async {
    final m = magasin([autre()]);
    await ouvrirM14(t, m, 'cfg-fiches-aide', role: validateur);
    await toucherM14(t, find.byKey(const Key('aide:valider:FAI-AUTRE')));
    expect(find.textContaining('Ouvrir l’écran du courrier'), findsWidgets, reason: 'le texte relu est celui que l’assistant citera');
    await toucherM14(t, find.byKey(const Key('aide:valider-ok')));
    final f = m.collection(colFichesAide).parId('FAI-AUTRE')!;
    expect(f['statut'], ficheAideValidee);
    expect('${f['validePar']}', isNotEmpty);
    expect(f['valideLe'], '2026-10-30');
    expect('${f['validateurId']}', isNotEmpty);
    expect(ficheAideCitable(f), isTrue);
    expect(find.byKey(const Key('aide:ok')), findsOneWidget);
    expect(find.text('Validée'), findsOneWidget);
    expect(m.collection('audit').toutes.any((x) => x['action'] == 'Validation' && x['reference'] == 'FAI-AUTRE'), isTrue);
    // l'assistant, lui, cite la fiche avec son validateur
    final r = AssistantAst().repondre('Comment j’enregistre un courrier entrant ?', ContexteAst(
        role: validateur,
        lire: (n) => n == colFichesAide ? m.collection(colFichesAide).actives : const [],
        peutVoirEcran: (_) => true,
        sensibles: DroitsSensibles(fiches: const []),
        maintenant: DateTime(2026, 10, 30)));
    expect(r.statut, 'reponse');
    expect(r.lignes.join(' | '), contains('Fiche validée par ${f['validePar']} le 30/10/2026'));
  });

  casM14('l’AUTEUR ne valide pas sa propre fiche : refus nommé, la fiche reste proposée', (t) async {
    final m = magasin(const []);
    await ouvrirM14(t, m, 'cfg-fiches-aide', role: validateur);
    await toucherM14(t, find.byKey(const Key('aide:nouvelle')));
    await saisir(t, 'titre', 'Ma fiche');
    await saisir(t, 'motsCles', 'ma fiche');
    await saisir(t, 'etapes', 'Une étape');
    await toucherM14(t, find.byKey(const Key('aide:enregistrer')));
    final id = m.collection(colFichesAide).toutes.single['id'];
    await toucherM14(t, find.byKey(Key('aide:valider:$id')));
    await toucherM14(t, find.byKey(const Key('aide:valider-ok')));
    expect(find.byKey(const Key('aide:refus')), findsOneWidget);
    expect(find.textContaining('AUTEUR_NE_VALIDE_PAS'), findsOneWidget);
    expect(m.collection(colFichesAide).parId(id)!['statut'], ficheAideProposee);
  });

  casM14('la check-liste du bloc (Q94) : le détenteur du geste générique ne suffit pas ; il faut le geste du professionnel, « validé par (professionnel) » non vide et daté', (t) async {
    final bloc = fichesAideDomainesPro.first.id;
    final m = magasin([autre(en: {'domainePro': bloc, 'titre': 'Check-liste du bloc', 'motsCles': ['check-list']})]);
    await ouvrirM14(t, m, 'cfg-fiches-aide', role: validateur);
    await toucherM14(t, find.byKey(const Key('aide:valider:FAI-AUTRE')));
    expect(find.byKey(const Key('aide:pro')), findsOneWidget, reason: 'le champ « Validé par (professionnel) » est demandé');
    await toucherM14(t, find.byKey(const Key('aide:valider-ok')));
    expect(find.textContaining('PROFESSIONNEL_REQUIS'), findsOneWidget, reason: 'la Direction ne valide pas à la place du chirurgien');
    expect(m.collection(colFichesAide).parId('FAI-AUTRE')!['statut'], ficheAideProposee);
    // la clinique accorde le geste du professionnel à ce rôle (fiche de rôle) : il faut alors son nom et sa date
    m.collection('rbac').inserer({'id': 'RBAC-PRO', 'role': validateur, 'statut': 'actif', 'droitsGestes': {gesteValiderRefBloc: true}}, prefixe: 'RBAC');
    await toucherM14(t, find.byKey(const Key('aide:valider-ok')));
    expect(find.textContaining('PROFESSIONNEL_ABSENT'), findsOneWidget);
    await t.enterText(find.byKey(const Key('aide:pro')), 'Dr Fictif');
    await t.pump();
    await toucherM14(t, find.byKey(const Key('aide:valider-ok')));
    expect(find.textContaining('DATE_PROFESSIONNEL_INVALIDE'), findsOneWidget);
    await t.enterText(find.byKey(const Key('aide:pro-le')), '2026-10-29');
    await t.pump();
    await toucherM14(t, find.byKey(const Key('aide:valider-ok')));
    final f = m.collection(colFichesAide).parId('FAI-AUTRE')!;
    expect([f['statut'], f['professionnel'], f['professionnelLe']], [ficheAideValidee, 'Dr Fictif', '2026-10-29']);
    expect(ficheAideCitable(f), isTrue);
    // le rôle du professionnel d'origine n'a pas le geste générique : il ne peut pas valider seul (les deux gestes sont réglables séparément)
    expect(gesteReserve(gesteFichesAideValider)!.rolesDefaut, isNot(contains(professionnel)));
  });

  casM14('archiver : le motif est obligatoire, la fiche reste lisible (jamais supprimée), l’assistant ne la cite plus', (t) async {
    final m = magasin([autre(statut: 'validee', en: {'validePar': 'Valideur Fictif', 'valideLe': '2026-10-29', 'validateurId': 'U-V'})]);
    await ouvrirM14(t, m, 'cfg-fiches-aide', role: validateur);
    await toucherM14(t, find.byKey(const Key('aide:archiver:FAI-AUTRE')));
    await toucherM14(t, find.byKey(const Key('aide:archiver-ok')));
    expect(find.textContaining('MOTIF_ABSENT'), findsOneWidget);
    await t.enterText(find.byKey(const Key('aide:motif')), 'Procédure changée');
    await t.pump();
    await toucherM14(t, find.byKey(const Key('aide:archiver-ok')));
    final f = m.collection(colFichesAide).parId('FAI-AUTRE')!;
    expect([f['statut'], f['motifArchivage'], f['statutAvantArchivage']], ['archive', 'Procédure changée', 'validee']);
    expect(m.collection(colFichesAide).toutes, hasLength(1), reason: 'rien n’est supprimé');
    expect(find.text('Archivée'), findsOneWidget);
    expect(m.collection(colFichesAide).actives, isEmpty);
  });

  casM14('réviser une fiche validée : une fiche nouvelle, proposée, la remplace ; la validée reste citée ; à la validation de la nouvelle, l’ancienne est archivée', (t) async {
    final m = magasin([autre(id: 'FAI-OLD', statut: 'validee', en: {'validePar': 'Valideur Fictif', 'valideLe': '2026-10-29', 'validateurId': 'U-V', 'auteurId': 'U-ANCIEN'})]);
    await ouvrirM14(t, m, 'cfg-fiches-aide', role: validateur);
    await toucherM14(t, find.byKey(const Key('aide:reviser:FAI-OLD')));
    final nouvelle = m.collection(colFichesAide).toutes.firstWhere((f) => f['remplace'] == 'FAI-OLD');
    expect(nouvelle['statut'], ficheAideProposee);
    expect(m.collection(colFichesAide).parId('FAI-OLD')!['statut'], ficheAideValidee, reason: 'tant que la nouvelle n’est pas validée, l’ancienne reste citée');
    // la nouvelle est écrite par le rôle courant : un autre en valide la relecture — on simule l'auteur différent
    m.collection(colFichesAide).mettreAJour(nouvelle['id'], {'auteurId': 'U-AUTRE-REVISEUR'}, journaliser: false);
    await t.pump();
    await toucherM14(t, find.byKey(Key('aide:valider:${nouvelle['id']}')));
    await toucherM14(t, find.byKey(const Key('aide:valider-ok')));
    expect(m.collection(colFichesAide).parId(nouvelle['id'])!['statut'], ficheAideValidee);
    final ancienne = m.collection(colFichesAide).parId('FAI-OLD')!;
    expect(ancienne['statut'], 'archive');
    expect('${ancienne['motifArchivage']}', contains('Remplacée par'));
  });

  casM14('« Rédiger » sur une fiche attendue relie la fiche à sa question : le statut calculé passe de « pas encore écrite » à « écrite, en attente »', (t) async {
    final m = magasin(const []);
    await ouvrirM14(t, m, 'cfg-fiches-aide', role: validateur);
    await toucherM14(t, find.byKey(const Key('aide:rediger:58')));
    await saisir(t, 'titre', 'Enregistrer un courrier entrant');
    await saisir(t, 'motsCles', 'courrier entrant');
    await saisir(t, 'etapes', 'Ouvrir l’écran du courrier');
    await toucherM14(t, find.byKey(const Key('aide:enregistrer')));
    expect(m.collection(colFichesAide).toutes.single['questionAttendue'], 58);
    expect(find.text('Pas encore écrite'), findsNWidgets(8));
    expect(find.text('Écrite, en attente de validation'), findsOneWidget);
    expect(find.textContaining('8 pas encore écrite(s), 1 écrite(s) en attente'), findsOneWidget);
  });

  casM14('un poste rattaché peut rédiger mais PAS valider : la validation se fait sur la mère, la commande est absente et le motif le dit', (t) async {
    final m = magasin([autre()]);
    await t.runAsync(() => ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true)));
    await ouvrirM14(t, m, 'cfg-fiches-aide', role: validateur);
    expect(find.byKey(const Key('aide:fileul')), findsOneWidget);
    expect(find.byKey(const Key('aide:nouvelle')), findsOneWidget, reason: 'la rédaction reste ouverte');
    expect(find.byKey(const Key('aide:valider:FAI-AUTRE')), findsNothing);
    expect(find.byKey(const Key('aide:modifier:FAI-AUTRE')), findsOneWidget);
  });

  casM14('un rôle sans le droit d’écrire l’écran le lit seulement : ni gabarit actif, ni modifier, ni archiver', (t) async {
    // l'accueil n'ouvre pas l'écran du tout ; la Direction l'ouvre (matrice) : on retire l'écriture par une surcharge d'écran
    final m = magasin([autre()]);
    await ouvrirM14(t, m, 'cfg-fiches-aide', role: 'direction', donnees: donneesLectureSeule('direction', 'cfg-fiches-aide'));
    expect(find.byKey(const Key('aide:nouvelle')), findsNothing);
    expect(find.byKey(const Key('aide:modifier:FAI-AUTRE')), findsNothing);
    expect(find.byKey(const Key('aide:archiver:FAI-AUTRE')), findsNothing);
    expect(find.text('Proposée'), findsOneWidget, reason: 'la liste se lit');
  });
}
