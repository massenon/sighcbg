import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/core/matrice_vive.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/service_droits.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LES DÉCISIONS DE DROITS (10/11/2026) : la matrice n'est jamais figée. Un droit décidé sur un poste habilité (ou la mère) est jugé par la mère, appliqué, journalisé,
/// diffusé à tous les fileuls ; le moteur le lit à chaque évaluation. Ici : le service seul (mère), puis la VRAIE mère et DEUX VRAIS moteurs de fileul.
typedef M = Map<String, Object?>;

final donnees = DonneesNavigation.depuisDossier();

Magasin poste() => Magasin.depuisDossier(['rbac', 'modulesActifs', 'audit', 'rolesBase', 'utilisateurs']);

M droit(bool v, [bool e = false, bool a = false]) => {'voir': v, 'editer': e, 'annuler': a};

Fiche ficheDe(Magasin m, String role) => m.collection('rbac').toutes.firstWhere((f) => f['role'] == role);

bool peut(Magasin m, String role, String ecran) => donnees.aChaud(m).matrice.peutVoir(role, ecran);

ServiceDroits mere(Magasin m, {String auteur = 'DAF'}) {
  m.utilisateur = auteur;
  final vive = MatriceVive(donnees, m);
  return ServiceDroits.de(m)
    ..fileulRattache = (() => false)
    ..demarrerMere(peutEditerEnForce: vive.peutEditer);
}

void main() {
  group('sur la mère (ou un poste isolé)', () {
    test('une décision s’applique aussitôt, porte son motif, sa version et son horodatage, et se journalise avec l’ancien et le nouveau droit (RG-12)', () {
      final m = poste();
      final s = mere(m);
      expect(peut(m, 'sage_femme', 'm9-assures'), isFalse);
      final r = s.decider(role: 'sage_femme', valeurs: {'droits': {'M9': droit(true)}}, journal: 'Modification des droits RBAC', motif: 'Suivi des cartes de la maternité', auteurRole: 'admin');
      expect(r.issue, 'appliquee');
      expect(r.transmise, isFalse);
      final f = ficheDe(m, 'sage_femme');
      expect((f['droits'] as Map)['M9'], droit(true));
      expect(f['version'], 1);
      expect(f['decideLe'], isNotNull);
      expect(peut(m, 'sage_femme', 'm9-assures'), isTrue, reason: 'effective à chaud, sans redémarrage');
      final ligne = m.collection('audit').toutes.firstWhere((a) => a['action'] == 'Modification des droits RBAC');
      expect(ligne['utilisateur'], 'DAF');
      expect((ligne['avant'] as Map)['module M9'], 'fermé');
      expect((ligne['apres'] as Map)['module M9'], 'voir');
      expect((ligne['apres'] as Map)['motif'], 'Suivi des cartes de la maternité');
      final d = s.decisions.toutes.single;
      expect([d['statutDemande'], d['auteur'], d['motif'], d['role']], ['appliquee', 'DAF', 'Suivi des cartes de la maternité', 'sage_femme']);
    });

    test('une écriture qui ne change rien ne crée aucune décision', () {
      final m = poste();
      final s = mere(m);
      final r = s.decider(role: 'sage_femme', valeurs: {'statut': 'actif'}, journal: 'x', motif: 'x', auteurRole: 'admin');
      expect(r.issue, 'sans_effet');
      expect(s.decisions.toutes, isEmpty);
    });

    test('l’annulation est une DÉCISION de plus : datée, journalisée, et l’historique garde les deux', () {
      final m = poste();
      final s = mere(m);
      final r = s.decider(role: 'sage_femme', valeurs: {'droits': {'M9': droit(true)}}, journal: 'Modification des droits RBAC', motif: 'Essai', auteurRole: 'admin');
      expect(peut(m, 'sage_femme', 'm9-assures'), isTrue);
      m.horloge = () => DateTime.now().add(const Duration(seconds: 5));
      r.annuler();
      expect(peut(m, 'sage_femme', 'm9-assures'), isFalse);
      expect(s.decisions.toutes, hasLength(2));
      expect(s.decisions.toutes.map((d) => d['genre']), containsAll(['modification', 'annulation']));
    });

    test('REVENIR AU DÉFAUT D’ORIGINE : la graine est réappliquée en nouvelle version, jamais en supprimant l’historique', () {
      final m = poste();
      final s = mere(m);
      final graine = Map<String, Object?>.from(s.graineDuRole('sage_femme')!);
      s.decider(role: 'sage_femme', valeurs: {'droits': {'M9': droit(true, true), 'M4': droit(false)}}, journal: 'Modification des droits RBAC', motif: 'Essai', auteurRole: 'admin');
      expect(ficheDe(m, 'sage_femme')['version'], 1);
      m.horloge = () => DateTime.now().add(const Duration(minutes: 1));
      final r = s.revenirAuDefaut(role: 'sage_femme', motif: 'Retour au réglage de la Direction', auteurRole: 'admin')!;
      expect(r.issue, 'appliquee');
      final f = ficheDe(m, 'sage_femme');
      expect(f['droits'], graine['droits']);
      expect(f['droitsEcrans'], graine['droitsEcrans']);
      expect(f['version'], 2, reason: 'une version de plus : ni retour en arrière silencieux ni remise à zéro');
      expect(s.decisions.toutes, hasLength(2), reason: 'rien n’est supprimé (RG-14)');
      expect(peut(m, 'sage_femme', 'm4-cpn'), isTrue);
      // Le jeu d'origine n'a pas bougé.
      expect(s.graineDuRole('sage_femme')!['droits'], graine['droits']);
      // Déjà au défaut : sans effet, et dit.
      expect(s.revenirAuDefaut(role: 'sage_femme', motif: 'encore', auteurRole: 'admin')!.issue, 'sans_effet');
    });

    test('un rôle créé en exploitation n’a pas de défaut d’origine : la remise le dit au lieu de deviner', () {
      final m = poste();
      final s = mere(m);
      s.decider(role: 'auditeur', valeurs: {'libelle': 'Auditeur', 'nouveau': true, 'droits': {'M1': droit(false)}}, journal: 'Création d’un rôle', motif: 'Revue', auteurRole: 'admin');
      expect(s.graineDuRole('auditeur'), isNull);
      expect(s.revenirAuDefaut(role: 'auditeur', motif: 'x', auteurRole: 'admin'), isNull);
    });
  });

  group('la mère juge les décisions reçues des postes', () {
    M recue(String ident, String role, String decideLe, Map<String, Object?> ch, {String auteur = 'Directeur', String auteurRole = 'admin', String motif = 'Revue', Map<String, Object?> vu = const {}}) =>
        drDecision(id: ident, role: role, changements: ch, avant: vu, motif: motif, auteur: auteur, auteurRole: auteurRole, poste: 'P2', decideLe: DateTime.parse(decideLe));

    test('un profil sans droit sur « Rôles et permissions » est REFUSÉ en le nommant, et rien ne change', () {
      final m = poste();
      final s = mere(m);
      final avant = ficheDe(m, 'sage_femme')['version'];
      s.decisions.ajouterSansJournal({...recue('D1', 'sage_femme', '2026-11-10T10:00:00Z', {'droits.M9': droit(true)}, auteurRole: 'caissier', auteur: 'Caissière'), 'id': 'F-D1'});
      s.traiterEnAttente();
      final d = s.decisions.parId('F-D1')!;
      expect(d['statutDemande'], 'refusee');
      expect(d['motifRefus'], contains('caissier'));
      expect(ficheDe(m, 'sage_femme')['version'], avant);
      expect(peut(m, 'sage_femme', 'm9-assures'), isFalse);
      expect(m.collection('audit').toutes.any((a) => a['action'] == 'Décision de droits refusée' && (a['apres'] as Map)['auteur'] == 'Caissière'), isTrue);
    });

    test('deux décisions sur le MÊME droit arrivées dans le désordre : la plus récente par horodatage l’emporte, l’autre est écartée, nommée, journalisée', () {
      final m = poste();
      final s = mere(m);
      // La plus récente (11 h) arrive d'abord, la plus ancienne (10 h) ensuite : l'ordre d'arrivée ne décide pas.
      s.decisions.ajouterSansJournal({...recue('D-recente', 'sage_femme', '2026-11-10T11:00:00Z', {'droits.M9': droit(true)}, auteur: 'Directeur', motif: 'Lecture seule pendant l’audit'), 'id': 'F-R'});
      s.traiterEnAttente();
      s.decisions.ajouterSansJournal({...recue('D-ancienne', 'sage_femme', '2026-11-10T10:00:00Z', {'droits.M9': droit(true, true)}, auteur: 'DAF', motif: 'Besoin du service'), 'id': 'F-A'});
      s.traiterEnAttente();
      expect(s.decisions.parId('F-R')!['statutDemande'], 'appliquee');
      final ancienne = s.decisions.parId('F-A')!;
      expect(ancienne['statutDemande'], 'ecartee');
      final ligne = (ancienne['lignes'] as List).single as Map;
      expect([ligne['autreAuteur'], ligne['autreMotif']], ['Directeur', 'Lecture seule pendant l’audit']);
      expect((ficheDe(m, 'sage_femme')['droits'] as Map)['M9'], droit(true), reason: 'la décision de 11 h tient');
      final j = m.collection('audit').toutes.firstWhere((a) => (a['apres'] as Map?)?['décision'] == 'D-ancienne');
      expect((j['apres'] as Map)['issue'], 'ecartee');
      expect((j['apres'] as Map).keys, contains('écartées (décision plus récente en vigueur)'));
    });

    test('dans l’ordre inverse (l’ancienne d’abord, la récente ensuite) la récente écrase, marquée CONCURRENTE, avec ancien droit, auteur et motif de ce qu’elle remplace', () {
      final m = poste();
      final s = mere(m);
      s.decisions.ajouterSansJournal({...recue('D-ancienne', 'sage_femme', '2026-11-10T10:00:00Z', {'droits.M9': droit(true, true)}, auteur: 'DAF', motif: 'Besoin du service', vu: {'droits.M9': null}), 'id': 'F-A'});
      s.traiterEnAttente();
      s.decisions.ajouterSansJournal({...recue('D-recente', 'sage_femme', '2026-11-10T11:00:00Z', {'droits.M9': droit(false)}, auteur: 'Directeur', motif: 'Fermeture audit', vu: {'droits.M9': null}), 'id': 'F-R'});
      s.traiterEnAttente();
      final r = s.decisions.parId('F-R')!;
      expect(r['statutDemande'], 'appliquee');
      final ligne = (r['lignes'] as List).single as Map;
      expect(ligne['concurrent'], isTrue);
      expect([ligne['autreAuteur'], ligne['autreMotif']], ['DAF', 'Besoin du service']);
      expect(ligne['ancien'], droit(true, true), reason: 'l’ancien droit est conservé au journal des décisions');
      final j = m.collection('audit').toutes.firstWhere((a) => (a['apres'] as Map?)?['décision'] == 'D-recente');
      expect(((j['apres'] as Map)['concurrentes'] as List).single, contains('DAF'));
      expect((j['avant'] as Map)['module M9'], 'voir, éditer');
      expect((j['apres'] as Map)['module M9'], 'fermé');
    });

    test('deux décisions sur des droits DIFFÉRENTS du même rôle se cumulent', () {
      final m = poste();
      final s = mere(m);
      s.decisions.ajouterSansJournal({...recue('D1', 'sage_femme', '2026-11-10T10:00:00Z', {'droits.M9': droit(true)}), 'id': 'F-1'});
      s.decisions.ajouterSansJournal({...recue('D2', 'sage_femme', '2026-11-10T09:00:00Z', {'droits.M8': droit(true)}), 'id': 'F-2'});
      s.traiterEnAttente();
      final d = ficheDe(m, 'sage_femme')['droits'] as Map;
      expect([d['M9'], d['M8']], [droit(true), droit(true)]);
      expect(s.decisions.toutes.map((x) => x['statutDemande']), everyElement('appliquee'));
    });
  });

  group('aucune matrice figée : le moteur lit la fiche en base à chaque évaluation', () {
    test('MatriceVive : une décision invalide la mémoïsation, l’évaluation suivante repart de la fiche', () {
      final m = poste();
      final vive = MatriceVive(donnees, m);
      expect(vive.peutVoir('sage_femme', 'm9-assures'), isFalse);
      final n = vive.calculs;
      vive.peutVoir('sage_femme', 'm9-assures');
      expect(vive.calculs, n, reason: 'mémoïsée tant que rien n’est écrit');
      ServiceDroits.de(m).fileulRattache = () => false;
      ServiceDroits.de(m).decider(role: 'sage_femme', valeurs: {'droits': {'M9': droit(true)}}, journal: 'j', motif: 'm', auteurRole: 'admin');
      expect(vive.peutVoir('sage_femme', 'm9-assures'), isTrue);
      expect(vive.calculs, n + 1, reason: 'recalculée depuis la fiche en base');
      expect(donnees.matrice.peutVoir('sage_femme', 'm9-assures'), isFalse, reason: 'la graine engendrée n’a pas bougé : elle n’est que la graine');
    });

    test('la graine engendrée ne porte aucun droit que la base ne puisse corriger : fermer un écran ouvert d’origine prend effet', () {
      final m = poste();
      final s = mere(m);
      expect(peut(m, 'sage_femme', 'm4-cpn'), isTrue);
      s.decider(role: 'sage_femme', valeurs: {'droitsEcrans': {'m4-cpn': {'voir': false}}}, journal: 'j', motif: 'Fermeture', auteurRole: 'admin');
      expect(peut(m, 'sage_femme', 'm4-cpn'), isFalse);
    });
  });

  group('MÈRE RÉELLE + DEUX FILEULS RÉELS', () {
    test('un droit décidé sur un fileul habilité se propage à la mère et à l’autre fileul, sans redémarrage ; refus nommé d’un profil non habilité ; concurrence jugée par horodatage', () async {
      const port = 19471;
      final d = Directory.systemTemp.createTempSync('droits');
      addTearDown(() => d.deleteSync(recursive: true));
      final mere0 = await Mere.creer(ConfigMere(port: port, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauv'));
      await mere0.demarrer();
      addTearDown(() async {
        try {
          await mere0.arreter();
        } catch (_) {}
      });
      final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
      final moteurs = [
        for (final n in ['F1', 'F2']) MoteurFileul.creer(dbChemin: '${d.path}/$n.db', mere: 'http://127.0.0.1:1', nom: n),
      ];
      final mm = poste(), m1 = poste(), m2 = poste();
      mere(mm, auteur: 'Poste mère');
      m1.utilisateur = 'Dr Fileul Un';
      m2.utilisateur = 'Dr Fileul Deux';
      final s1 = ServiceDroits.de(m1)..fileulRattache = (() => true);
      final s2 = ServiceDroits.de(m2)..fileulRattache = (() => true);
      final pub = PublicateurConfiguration(mm, publierVersMereLocale(port: port, admin: 'secret-test'), delai: Duration.zero);
      final appl = [ApplicateurConfiguration(m1, moteurs[0].liste), ApplicateurConfiguration(m2, moteurs[1].liste)];
      for (final a in appl) {
        a.demarrer(intervalle: const Duration(hours: 1));
        a.arreter();
      }
      TransportFileul tf(MoteurFileul mo) =>
          TransportFileul(lire: mo.liste, ecrireFiche: (c, f, {required existe, required champs}) => mo.ecrire(c, f, existe: existe, champs: champs), restaurerFiche: mo.restaurer);
      PontActivite pont(Magasin m, TransportPont t, String e) => PontActivite(m, t, etiquette: e, collections: {drCollectionDecisions});
      final pm = pont(mm, TransportMereLocale(port: port, admin: 'secret-test'), 'M');
      final p1 = pont(m1, tf(moteurs[0]), 'F1');
      final p2 = pont(m2, tf(moteurs[1]), 'F2');

      Future<void> tour() async {
        await pub.pousser();
        for (final a in appl) {
          await a.tirer();
        }
        await p1.cycle();
        await p2.cycle();
        await pm.cycle();
        await Future<void>.delayed(const Duration(milliseconds: 20)); // la mère traite en microtâche, à la réception
        await pub.pousser();
        for (final a in appl) {
          await a.tirer();
        }
        await p1.cycle();
        await p2.cycle();
      }

      Future<void> converger(bool Function() fini, String quoi) async {
        final fin = DateTime.now().add(const Duration(seconds: 45));
        while (!fini()) {
          await tour();
          if (DateTime.now().isAfter(fin)) {
            fail('$quoi : pas de convergence. mère ${mm.collection('decisionsDroits').toutes.map((x) => '${x['ident']}:${x['statutDemande']}')} ; F1 ${m1.collection('decisionsDroits').toutes.map((x) => '${x['ident']}:${x['statutDemande']}')} ; erreurs ${pm.erreur.value} ${p1.erreur.value} ${p2.erreur.value} ; refus ${pm.motifsRefus} ${p1.motifsRefus}');
          }
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }

      for (final (i, mo) in moteurs.indexed) {
        final code = await console.codeAppareil('F${i + 1}').timeout(const Duration(seconds: 20));
        await mo.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
        mo.demarrer();
      }
      final nbFiches = mm.collection('rbac').toutes.length;
      await converger(() => m1.collection('rbac').toutes.length == nbFiches && m2.collection('rbac').toutes.length == nbFiches, 'configuration de départ');
      // Les fileuls ne peuvent pas écrire la fiche de droits eux-mêmes : famille R, garde « réglé sur la mère ».
      expect(() => m1.collection('rbac').mettreAJour(ficheDe(m1, 'sage_femme')['id'], {'statut': 'actif'}), throwsA(isA<EcritureRefusee>()));
      expect(peut(m2, 'sage_femme', 'm9-assures'), isFalse);

      // 1. UN FILEUL HABILITÉ décide : la décision part à la mère, qui la juge, l'applique, la journalise ; l'autre fileul reçoit la fiche ; personne ne redémarre.
      m1.horloge = () => DateTime.utc(2026, 11, 10, 11);
      final r = s1.decider(role: 'sage_femme', valeurs: {'droits': {'M9': droit(true)}}, journal: 'Modification des droits RBAC', motif: 'La maternité suit les cartes d’assurance', auteurRole: 'admin');
      expect(r.transmise, isTrue);
      expect((ficheDe(m1, 'sage_femme')['droits'] as Map)['M9'], droit(false), reason: 'le fileul n’applique pas lui-même : la mère décide');
      await converger(() => peut(m2, 'sage_femme', 'm9-assures') && peut(m1, 'sage_femme', 'm9-assures') && peut(mm, 'sage_femme', 'm9-assures'), 'diffusion d’une décision de fileul');
      await converger(() => m1.collection('decisionsDroits').toutes.single['statutDemande'] == 'appliquee', 'issue renvoyée au poste qui a décidé');
      expect(m1.collection('decisionsDroits').toutes.single['statutDemande'], 'appliquee', reason: 'l’issue revient au poste qui a décidé');
      final audit = mm.collection('audit').toutes.firstWhere((a) => a['action'] == 'Modification des droits RBAC');
      expect((audit['apres'] as Map)['motif'], 'La maternité suit les cartes d’assurance');
      expect((audit['apres'] as Map)['auteur'], 'Dr Fileul Un');
      expect((audit['avant'] as Map)['module M9'], 'fermé');

      // 2. UN PROFIL NON HABILITÉ (caissier) : refus nommé par la mère, aucun droit ne change.
      s2.decider(role: 'sage_femme', valeurs: {'droits': {'M12': droit(true, true, true)}}, journal: 'Modification des droits RBAC', motif: 'Tentative', auteurRole: 'caissier');
      await converger(() => m2.collection('decisionsDroits').toutes.any((x) => x['statutDemande'] == 'refusee'), 'refus d’un profil non habilité');
      expect(m2.collection('decisionsDroits').toutes.firstWhere((x) => x['statutDemande'] == 'refusee')['motifRefus'], contains('caissier'));
      expect(peut(mm, 'sage_femme', 'm12-ecritures'), isFalse);

      // 3. DEUX POSTES, MÊME DROIT : F2 décide à 12 h ; F1 (poste hors ligne, ou horloge en retard) décide à 10 h une autre valeur, et sa décision est reçue APRÈS. L'horodatage de
      // décision tranche, pas l'ordre d'arrivée : celle de 10 h est écartée, nommée, journalisée.
      m2.horloge = () => DateTime.utc(2026, 11, 10, 12);
      s2.decider(role: 'sage_femme', valeurs: {'droits': {'M8': droit(true)}}, journal: 'Modification des droits RBAC', motif: 'Lecture de la facturation', auteurRole: 'admin');
      await converger(() => peut(mm, 'sage_femme', 'm8-facturation') && peut(m1, 'sage_femme', 'm8-facturation') && peut(m2, 'sage_femme', 'm8-facturation'), 'décision de 12 h');
      m1.horloge = () => DateTime.utc(2026, 11, 10, 10);
      s1.decider(role: 'sage_femme', valeurs: {'droits': {'M8': droit(true, true)}}, journal: 'Modification des droits RBAC', motif: 'Facturation en écriture', auteurRole: 'admin');
      await converger(() => m1.collection('decisionsDroits').toutes.any((x) => x['motif'] == 'Facturation en écriture' && x['statutDemande'] == 'ecartee'), 'décision de 10 h reçue après');
      final ecartee = m1.collection('decisionsDroits').toutes.firstWhere((x) => x['motif'] == 'Facturation en écriture');
      expect(((ecartee['lignes'] as List).single as Map)['autreAuteur'], 'Dr Fileul Deux', reason: 'la décision qui tient est nommée');
      expect(peut(mm, 'sage_femme', 'm8-facturation'), isTrue, reason: 'la décision de 12 h tient sur la mère');
      expect(((ficheDe(m1, 'sage_femme')['droits'] as Map)['M8']), droit(true), reason: 'et sur le fileul dont la décision, plus ancienne, a été écartée');
      expect(peut(m2, 'sage_femme', 'm8-facturation'), isTrue);
      expect(mm.collection('decisionsDroits').toutes, hasLength(4), reason: 'rien ne se supprime : les quatre décisions restent au journal');
      final j = mm.collection('audit').toutes.firstWhere((a) => (a['apres'] as Map?)?['issue'] == 'ecartee');
      expect(((j['apres'] as Map)['motif']), 'Facturation en écriture');
    }, timeout: const Timeout(Duration(seconds: 180)));
  });
}
