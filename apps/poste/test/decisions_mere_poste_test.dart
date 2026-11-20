import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/shell/pastille_decisions_mere.dart';
import 'package:sigh_poste/sync/alerte_decisions_mere.dart';
import 'package:sigh_poste/sync/service_demandes_tarif.dart';
import 'package:sigh_poste/sync/service_validations_deposees.dart';

/// SECTION AI (Direction, 16/11/2026), au poste, sur le jeu livré :
///  (1) au-delà du délai réglé en base (4 h semées), une notification de poste au validateur (geste de la matrice) et à l'administrateur — une seule par décision et destinataire,
///      rien de bloqué ;
///  (2) la mère vérifie le compte inscrit sur la décision : refus nommé (code stable) rendu sur la même fiche, rien n'est appliqué ;
///  (3) le verdict porte la date de signature et, à côté, la date d'application ;
///  (4) la pastille compte les trois files avec leur âge.
final geste = DateTime.utc(2026, 11, 16, 8);

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu')..horloge = () => geste;

Agent agent(String id, String role) => Agent(utilisateurId: id, nom: 'Agent $id', role: role);

TarifsPoste fileul(Magasin m, String role) => TarifsPoste(m, role: role, auteur: () => m.utilisateur, fileul: true, peutEditerEcran: true, horloge: () => geste, etiquette: 'F1');

DemandeProposition prop(String code) => DemandeProposition(code: code, prixNonAssure: 6500, etatAssure: 'unique', dateEffet: '2026-12-01', motif: 'Essai AI');

void main() {
  group('(2) et (3) la mère vérifie le compte signataire ; le verdict porte la date de signature', () {
    test('compte existant, bon rôle : appliquée (signeLe = geste, appliqueLe = mère) ; rôle différent, compte inconnu, sans compte : refus nommés, rien n’est écrit', () {
      final m = jeu();
      final usr = m.collection('utilisateurs').actives.firstWhere((u) => u['role'] == 'direction');
      m.poserActeur(agent('${usr['id']}', 'direction'));
      final ok = fileul(m, 'direction').proposer(prop('MG01'));
      expect(ok.depose, isTrue);
      expect([ok.demande![champCompteDecision], ok.demande!['demandePoste']], [usr['id'], 'F1']);
      expect(ok.demande!['demandeInstant'], '2026-11-16T08:00:00.000Z');
      // Sous un rôle que le compte ne porte pas (le poste déclare « da ») :
      final mauvaisRole = fileul(m, 'da').proposer(prop('MG03'));
      // Sans compte (session de démonstration) :
      m.poserActeur(agentDemonstration('direction'));
      final sansCompte = fileul(m, 'direction').proposer(prop('MG02'));
      // Compte qui n'existe pas dans les comptes de la clinique :
      m.poserActeur(agent('USR-INCONNU', 'direction'));
      final inconnu = fileul(m, 'direction').proposer(prop('MG04'));

      final versions = m.collection(tarCollectionVersions).toutes.length;
      final mere = ApplicateurDemandesTarif.de(m)..horloge = () => DateTime.utc(2026, 11, 16, 14);
      expect(mere.traiter(), 4);
      final par = {for (final d in m.collection(tarCollectionDemandes).toutes) d['id']: d};
      final v = par[ok.demande!['id']]!;
      expect(v['etat'], 'appliquee', reason: '${v['resultatCode']} ${v['resultatMotif']}');
      expect([v['signeLe'], v['appliqueLe']], ['2026-11-16T08:00:00.000Z', '2026-11-16T14:00:00.000Z'], reason: 'la date de SIGNATURE, et à côté la date d’application');
      expect(par[mauvaisRole.demande!['id']]!['resultatCode'], codeCompteRoleDifferent);
      expect(par[sansCompte.demande!['id']]!['resultatCode'], codeCompteNonInscrit);
      expect(par[inconnu.demande!['id']]!['resultatCode'], codeCompteInconnu);
      expect(m.collection(tarCollectionVersions).toutes.length, versions + 1, reason: 'seule la demande signée par un compte valide a écrit sa version');
    });

    test('un compte ARCHIVÉ ne signe plus : la validation déposée est refusée COMPTE_ARCHIVE, l’élément reste à valider', () {
      final m = jeu();
      final usr = m.collection('utilisateurs').actives.firstWhere((u) => u['role'] == 'direction');
      m.poserActeur(agent('${usr['id']}', 'direction'));
      final svc = ServiceValidationsDeposees.de(m)..etiquette = 'F1';
      final famille = valFamilles.firstWhere((f) => f.roles.contains('direction') && f.collections.isNotEmpty);
      final cible = [for (final c in famille.collections) ...m.collection(c).actives.where((x) => famille.champs.any((ch) => x[ch] == true))].firstOrNull;
      if (cible == null) return; // aucun élément à valider dans le jeu pour cette famille : rien à sonder ici
      final r = svc.deposer(famille.id, cible['id'], role: 'direction', acteur: m.utilisateur);
      expect(r.ok, isTrue, reason: '${r.refus?.code}');
      expect(r.fiche![champCompteDecision], usr['id']);
      m.collection('utilisateurs').mettreAJour(usr['id'], {'statut': 'archive'}, journaliser: false);
      svc.traiter();
      final d = m.collection(valCollectionDepots).parId(r.fiche!['id'])!;
      expect([d['etat'], d['resultatCode']], [valDepotRefusee, codeCompteArchive]);
      expect(d['signeLe'], isNotNull);
    });
  });

  group('(1) et (4) la pastille et l’alerte des décisions en attente de la mère', () {
    Magasin avecAttente() {
      final m = jeu();
      final usr = m.collection('utilisateurs').actives.firstWhere((u) => u['role'] == 'direction');
      m.poserActeur(agent('${usr['id']}', 'direction'));
      fileul(m, 'direction').proposer(prop('MG01'));
      m.collection(valCollectionDepots).ajouterSansJournal({
        'id': 'VDP-X',
        'statut': 'actif',
        'genre': valGenreCircuitAchat,
        'famille': circuitCommandeValidation,
        'cible': 'BC-1',
        'libelle': 'Validation d’une commande',
        'etat': valDepotDeposee,
        'demandePar': 'DAF',
        'demandeRole': 'da',
        'demandeLe': '2026-11-16T09:00:00.000Z',
      });
      m.collection('demandesImport').ajouterSansJournal({
        'id': 'DI-X',
        'statut': 'actif',
        'jeu': 'tarifs',
        'jeuLibelle': 'Tarifs',
        'etat': 'en_attente',
        'demandePar': 'DAF',
        'demandeRole': 'da',
        'demandeLe': '2026-11-16',
        'demandeInstant': '2026-11-16T07:00:00.000Z',
      });
      return m;
    }

    test('la pastille compte les TROIS files avec l’âge de la plus ancienne ; l’alerte part au-delà de 4 h vers le validateur (geste) et l’administrateur, une seule fois', () {
      final m = avecAttente();
      final a = AlerteDecisionsMere.de(m)..horloge = () => DateTime.utc(2026, 11, 16, 12, 30);
      expect(a.delaiHeures(), 4, reason: 'le défaut semé de la décision');
      final r = a.resume();
      expect([r.validations, r.prix, r.imports, r.total], [1, 1, 1, 3]);
      expect(r.plusAncienne, const Duration(hours: 5, minutes: 30));
      expect(r.enRetard, 2, reason: 'l’import (5 h 30) et la demande de prix (4 h 30) ; la validation (3 h 30) pas encore');
      // La demande de prix : au geste « décider un prix » ET à l'administrateur ; l'import : sans matrice branchée (aucun arbitre des lots connu), à l'administrateur seul.
      expect(a.verifier(), 3, reason: 'deux décisions en retard : prix (geste + administrateur), import (administrateur)');
      final notifs = m.collection('notifications').toutes.where((n) => n['type'] == typeNotifDecisionMereEnRetard).toList();
      expect({for (final n in notifs) '${n['poste']}'}, containsAll(['geste:$gesteDeciderPrix', posteAdministrateur]));
      expect(a.verifier(), 0, reason: 'une seule alerte par décision et par destinataire');
      // Plus tard, la validation dépasse à son tour le délai : elle s'alerte au geste « valider les achats ».
      a.horloge = () => DateTime.utc(2026, 11, 16, 13, 30);
      expect(a.verifier(), 2);
      expect(m.collection('notifications').toutes.any((n) => n['type'] == typeNotifDecisionMereEnRetard && n['poste'] == 'geste:$gesteValiderAchats'), isTrue);
      // Rien n'est bloqué ni appliqué : les décisions attendent toujours.
      expect(a.resume().total, 3);
    });

    test('le délai se RÈGLE en base (version datée) : à 8 h, rien ne s’alerte encore', () {
      final m = avecAttente();
      final s = serviceParametres(m, auteur: () => 'Administrateur', horloge: () => DateTime.utc(2026, 11, 16, 12, 30))..semerDefauts();
      expect(s.regler(cleDelaiAlerteMere, 8, '2026-11-16', motif: 'essai').ok, isTrue);
      final a = AlerteDecisionsMere.de(m)..horloge = () => DateTime.utc(2026, 11, 16, 12, 30);
      expect(a.delaiHeures(), 8);
      expect(a.verifier(), 0);
    });

    testWidgets('la pastille de la barre : « 3 décisions en attente de la mère », absente à zéro', (t) async {
      final m = avecAttente();
      await t.pumpWidget(MaterialApp(home: Scaffold(body: PastilleDecisionsMere(magasin: m, horloge: () => DateTime.utc(2026, 11, 16, 12, 30)))));
      expect(find.textContaining('3 décisions en attente de la mère'), findsOneWidget);
      expect(find.textContaining('5 h 30 min'), findsOneWidget);
      final vide = jeu();
      await t.pumpWidget(MaterialApp(home: Scaffold(body: PastilleDecisionsMere(magasin: vide, horloge: () => DateTime.utc(2026, 11, 16, 12, 30)))));
      expect(find.byKey(const Key('barre-decisions-mere')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });
}
