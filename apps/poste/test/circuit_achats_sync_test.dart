import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/parametres_poste.dart';
import 'package:sigh_poste/core/plages_codes.dart';
import 'package:sigh_poste/core/service_installation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_poste/sync/service_circuit_achats.dart';
import 'package:sigh_poste/sync/service_validations_deposees.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// LA CONTINUITÉ DES VALIDATIONS TRAVERSE LES POSTES (Direction, 16/11/2026) : un BESOIN exprimé sur un fileul arrive à la DAF, qui arbitre depuis SON poste ; sa COMMANDE part à la DAF de la
/// même façon (RG-04). Contre la VRAIE mère Dart et DEUX vrais moteurs de fileul : numérotation sans collision, arbitrage déposé puis appliqué par la mère, verdict et tâches revenus,
/// état qui ne régresse jamais, mère coupée puis relancée, aucun prix vers un téléphone.
typedef M = Map<String, Object?>;
final auj = DateTime(2026, 11, 16, 9);

Magasin poste() => Magasin({
      'besoins': <M>[],
      'commandes': <M>[],
      'notifications': <M>[],
      'validationsDeposees': <M>[],
      'plagesCodes': <M>[],
      'fournisseurs': <M>[],
    })..horloge = () => auj;

M ligne(String produit, num q) => {'produitId': 'P', 'produit': produit, 'unite': 'boîte', 'quantiteDemandee': q, 'prixAchat': 500};

void main() {
  // Direction de Baguidi, 16/11/2026 : « Valider les achats » est un GESTE RÉSERVÉ de la fiche RBAC (la DAF seule d'origine). La mère rejoue le dépôt sous le rôle de son auteur avec SA
  // matrice : la décision en force CHEZ ELLE fait foi, jamais une liste de rôles ni ce que le fileul croyait au moment du dépôt.
  test('CIR2 — la mère refait le contrôle avec SA matrice (geste d\'origine, geste accordé chez elle, accord du fileul seul)', () {
    M bon(String id) => {'id': id, 'idSync': 'F-$id', 'reference': 'BC-$id', 'statutCommande': 'attente_validation', 'statut': 'actif'};
    final m = Magasin({
      'besoins': <M>[],
      'commandes': <M>[bon('1'), bon('2'), bon('3')],
      'notifications': <M>[],
      'validationsDeposees': <M>[],
      'rbac': <M>[],
    })
      ..horloge = () => auj;
    final svc = ServiceValidationsDeposees.de(m)
      ..etiquette = 'M'
      ..horloge = () => auj;
    // Les dépôts faits sur un fileul : la DAF (origine), l'administrateur et la Direction à qui la clinique l'avait accordé chez le fileul.
    final chezLeFileul = DroitsGestes(fiches: [
      for (final r in ['admin', 'direction'])
        {'role': r, 'droitsGestes': {gesteValiderAchats: true}}
    ]);
    M depot(String id, String role) => circuitDeposer(
            famille: circuitCommandeValidation, bon: bon(id), role: role, acteur: 'Agent $role', poste: 'F', maintenant: auj, besoins: const [], commandes: [bon(id)], depots: const [],
            nouvelId: () => 'D$id', gestes: chezLeFileul)
        .fiche!;
    for (final d in [depot('1', 'da'), depot('2', 'admin'), depot('3', 'direction')]) {
      m.collection('validationsDeposees').ajouterSansJournal(d);
    }
    // Chez la mère : la décision accorde le geste à l'administrateur seulement ; la DAF garde son origine ; la Direction n'a aucune décision.
    m.collection('rbac').inserer({'role': 'admin', 'statut': 'actif', 'droitsGestes': {gesteValiderAchats: true}});
    expect(svc.traiter(), greaterThan(0));
    String verdict(String id) => '${m.collection('validationsDeposees').toutes.firstWhere((d) => d['cible'] == 'F-$id')['etat']}';
    expect(verdict('1'), valDepotAppliquee, reason: 'la DAF : origine du geste');
    expect(verdict('2'), valDepotAppliquee, reason: 'l\'administrateur : décision de la mère');
    expect(verdict('3'), valDepotRefusee, reason: 'la Direction : aucune décision chez la mère, l\'accord du fileul ne vaut rien');
    expect(m.collection('commandes').toutes.firstWhere((c) => c['id'] == '3')['statutCommande'], 'attente_validation');
  });

  test('CIR1 — du besoin à la commande, à travers deux fileuls et la vraie mère', () async {
    const port = 19591;
    final d = Directory.systemTemp.createTempSync('cir1');
    addTearDown(() => d.deleteSync(recursive: true));
    final config = ConfigMere(port: port, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '/tmp/sigh-test-sauvegardes-cir');
    var mere0 = await Mere.creer(config);
    await mere0.demarrer();
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final moteur1 = MoteurFileul.creer(dbChemin: '${d.path}/f1.db', mere: 'http://127.0.0.1:1', nom: 'F1');
    final moteur2 = MoteurFileul.creer(dbChemin: '${d.path}/f2.db', mere: 'http://127.0.0.1:1', nom: 'F2');
    final mm = poste(), m1 = poste(), m2 = poste();
    TransportFileul tf(MoteurFileul mo) =>
        TransportFileul(lire: mo.liste, ecrireFiche: (c, f, {required existe, required champs}) => mo.ecrire(c, f, existe: existe, champs: champs));
    final pm = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M');
    final p1 = PontActivite(m1, tf(moteur1), etiquette: 'F1', enLectureSeule: collectionsDeLaMereSeule, reservesAuMere: true);
    final p2 = PontActivite(m2, tf(moteur2), etiquette: 'F2', enLectureSeule: collectionsDeLaMereSeule, reservesAuMere: true);
    final svcMere = ServiceValidationsDeposees.de(mm)
      ..etiquette = 'M'
      ..horloge = () => auj;
    final svc1 = ServiceValidationsDeposees.de(m1)
      ..etiquette = 'F1'
      ..horloge = () => auj;
    final svc2 = ServiceValidationsDeposees.de(m2)
      ..etiquette = 'F2'
      ..horloge = () => auj;
    final cir = [for (final m in [mm, m1, m2]) ServiceCircuitAchats.de(m)..horloge = () => auj];
    var mereJoignable = true;
    Future<void> tour() async {
      if (!mereJoignable) return;
      for (final p in [p1, p2, pm]) {
        await p.cycle();
      }
      for (final s in cir) {
        s.reconcilier();
      }
    }

    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 60));
      while (!fini()) {
        await tour();
        if (DateTime.now().isAfter(fin)) {
          fail('$quoi : pas de convergence. refus ${p1.motifsRefus} ${p2.motifsRefus} ${pm.motifsRefus} ; erreurs ${p1.erreur.value} ${p2.erreur.value} ${pm.erreur.value}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }

    Fiche? bon(Magasin m, String ref) => m.collection('besoins').toutes.where((b) => b['reference'] == ref).firstOrNull;
    Fiche? cmd(Magasin m, String ref) => m.collection('commandes').toutes.where((b) => b['reference'] == ref).firstOrNull;
    int notes(Magasin m, String type, {String? poste}) => m.collection('notifications').toutes.where((n) => n['type'] == type && (poste == null || n['poste'] == poste)).length;

    try {
      svcMere.demarrerMere(intervalle: const Duration(milliseconds: 150));
      svc1.demarrerFileul(intervalle: const Duration(milliseconds: 150));
      svc2.demarrerFileul(intervalle: const Duration(milliseconds: 150));
      for (final (mo, m, nom) in [(moteur1, m1, 'F1'), (moteur2, m2, 'F2')]) {
        await ServiceInstallation.de(m).attacher(StockageMemoire(), const ParametresPoste(uuidPoste: 'u', rejoint: true));
        final code = await console.codeAppareil(nom).timeout(const Duration(seconds: 20));
        await mo.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
        mo.demarrer();
        PlagesNumeros.de(m).obtenir = (n, t, mi) => mo.demanderPlage(taille: t, minimum: mi, nom: n);
      }
      PlagesNumeros.de(mm).obtenir = (n, t, mi) => TransportMereLocale(port: port, admin: 'secret-test').plage(t, mi, nom: n);

      // 1. NUMÉROTATION SANS COLLISION : chaque poste prend sa plage, puis tire trois numéros ; hors ligne les deux ne se recouvrent pas.
      for (final (m, mo) in [(m1, moteur1), (m2, moteur2)]) {
        await PlagesNumeros.de(m).recharger('besoins', 'BEB-2026-', () => m.collection('besoins').toutes);
        await PlagesNumeros.de(m).recharger('commandes', 'BC-2026-', () => m.collection('commandes').toutes);
        expect(PlagesNumeros.de(m).restants('besoins'), 50, reason: 'plage reçue de la mère');
        expect(mo, isNotNull);
      }
      String ref1(Magasin m) => PlagesNumeros.de(m).reference('besoins', 'BEB-2026-', 4, m.collection('besoins').toutes);
      final refs1 = [ref1(m1), ref1(m1), ref1(m1)], refs2 = [ref1(m2), ref1(m2), ref1(m2)];
      expect({...refs1, ...refs2}.length, 6, reason: 'jamais deux fois le même BEB entre deux postes hors ligne : $refs1 / $refs2');
      expect(refs1.first, isNot(refs2.first));
      for (final r in refs1) {
        m1.collection('besoins').inserer(
            {'reference': r, 'service': 'Laboratoire', 'demandeur': 'Agent F1', 'etape': 'soumis', 'date': '2026-11-16', 'montantEstime': 1000, 'lignes': [ligne('Gants', 2)], 'statut': 'actif'},
            prefixe: 'BES');
      }
      for (final r in refs2) {
        m2.collection('besoins').inserer(
            {'reference': r, 'service': 'Maternité', 'demandeur': 'Agent F2', 'etape': 'soumis', 'date': '2026-11-16', 'montantEstime': 1000, 'lignes': [ligne('Compresses', 3)], 'statut': 'actif'},
            prefixe: 'BES');
      }
      await converger(() => [mm, m1, m2].every((m) => m.collection('besoins').toutes.length == 6), 'les six bons arrivent partout');
      expect({for (final b in mm.collection('besoins').toutes) b['reference']}.length, 6, reason: 'six références distinctes à la mère');

      // 2. L'ARBITRAGE : F2 (la DAF) voit le besoin de F1 ; refus nommés AVANT tout dépôt ; le dépôt est idempotent.
      final r0 = refs1[0];
      final chez2 = bon(m2, r0)!;
      expect(chez2['demandeur'], 'Agent F1', reason: 'la DAF voit ce que le service de F1 a exprimé');
      expect(svc2.deposerCircuit(circuitBesoinArbitrage, chez2, role: 'caissier', acteur: 'Un caissier').refus!.code, 'VALIDATION_RESERVEE');
      // Direction de Baguidi, 16/11/2026 : « Valider les achats » est un geste réservé, la DAF SEULE d'origine — l'administrateur système ne dépose pas sans décision de la fiche RBAC.
      expect(svc2.deposerCircuit(circuitBesoinArbitrage, chez2, role: 'admin', acteur: 'L’administrateur').refus!.code, 'VALIDATION_RESERVEE');
      expect(svc2.deposerCircuit(circuitBesoinArbitrage, chez2, decision: 'rejeter', role: 'da', acteur: 'La DAF').refus!.code, 'MOTIF_OBLIGATOIRE');
      expect(svc2.depots.toutes, isEmpty, reason: 'aucun dépôt tant que le geste est refusé');
      final dep = svc2.deposerCircuit(circuitBesoinArbitrage, chez2, role: 'da', acteur: 'La DAF');
      expect(dep.ok, isTrue, reason: '${dep.refus?.code}');
      expect(svc2.deposerCircuit(circuitBesoinArbitrage, chez2, role: 'da', acteur: 'La DAF').dejaDepose, isTrue);
      expect(svc2.depots.toutes, hasLength(1));
      expect(bon(m2, r0)!['etape'], 'soumis', reason: 'rien n’est écrit chez le fileul : jamais « accordé » avant la confirmation de la mère');
      // Le poste n'est pas bloqué : il exprime un autre besoin pendant l'attente.
      m2.collection('besoins').inserer({'reference': ref1(m2), 'service': 'Maternité', 'demandeur': 'Agent F2', 'etape': 'soumis', 'lignes': [ligne('Alèses', 1)], 'statut': 'actif'}, prefixe: 'BES');

      await converger(() => svc2.depots.toutes.single['etat'] == 'appliquee' && [mm, m1, m2].every((m) => bon(m, r0)!['etape'] == 'accorde'), 'la mère applique, le bon accordé revient partout');
      final accorde = bon(mm, r0)!;
      expect([accorde['arbitrePar'], accorde['valideePar']], ['La DAF', 'La DAF'], reason: 'sous le nom de l’auteur, à la date de son geste');
      expect(accorde['arbitreLe'], valInstant(auj));
      // Tâches : le comptable ET le gestionnaire de stock, une fois chacun, sur CHAQUE poste ; le verdict revient à l'auteur (F1) avec notification.
      await converger(() => [mm, m1, m2].every((m) => notes(m, 'besoin_accorde', poste: 'comptable') == 1 && notes(m, 'besoin_accorde', poste: 'stock') == 1) && notes(m1, 'besoin_verdict') == 1, 'tâches et verdict');
      final verdict = m1.collection('notifications').toutes.firstWhere((n) => n['type'] == 'besoin_verdict');
      expect(verdict['destinataire'], 'Agent F1');
      for (var i = 0; i < 4; i++) {
        await tour();
      }
      for (final m in [mm, m1, m2]) {
        expect(notes(m, 'besoin_accorde'), 2, reason: 'idempotent : relancer le service n’écrit aucune seconde tâche');
      }
      // Idempotence de l'application : la mère rejouée n'écrit rien ; un second arbitrage contradictoire est refusé en nommant l'arbitre.
      expect(svcMere.traiter(), 0);
      final contradiction = svc2.deposerCircuit(circuitBesoinArbitrage, bon(m2, r0)!, decision: 'rejeter', motif: 'trop cher', role: 'da', acteur: 'La DAF');
      expect(contradiction.refus!.code, 'DEJA_ARBITRE');
      expect(contradiction.refus!.motif, contains('La DAF'));
      // Un dépôt falsifié (rôle caissier) est refusé PAR LA MÈRE, qui refait les contrôles.
      final autre = bon(m2, refs1[1])!;
      m2.collection('validationsDeposees').ajouterSansJournal({
        'id': 'VDP-F2-faux', 'statut': 'actif', 'genre': valGenreCircuitAchat, 'famille': circuitBesoinArbitrage, 'cible': cleCircuit(autre), 'decision': 'valider',
        'libelle': 'faux', 'etat': 'deposee', 'demandeRole': 'caissier', 'demandePar': 'Un caissier', 'demandePoste': 'F2', 'demandeLe': valInstant(auj),
      });
      await converger(() => svc2.depots.parId('VDP-F2-faux')?['etat'] == 'refusee', 'la mère refuse le dépôt falsifié');
      expect(svc2.depots.parId('VDP-F2-faux')!['resultatCode'], 'VALIDATION_RESERVEE');
      expect(bon(mm, refs1[1])!['etape'], 'soumis');

      // 3. REJET AVEC MOTIF : le motif revient à l'auteur ; le bon rejeté n'est PAS archivé.
      final rej = svc2.deposerCircuit(circuitBesoinArbitrage, bon(m2, refs1[2])!, decision: 'rejeter', motif: 'Stock suffisant au magasin', role: 'da', acteur: 'La DAF');
      expect(rej.ok, isTrue);
      await converger(() => bon(m1, refs1[2])!['etape'] == 'rejete' && notes(m1, 'besoin_verdict') == 2, 'le rejet revient à F1');
      expect(bon(m1, refs1[2])!['motifArbitrage'], 'Stock suffisant au magasin');
      expect(bon(m1, refs1[2])!['statut'], 'actif', reason: 'un bon rejeté n’est pas archivé : le service lit le motif');
      expect(m1.collection('notifications').toutes.where((n) => n['type'] == 'besoin_verdict' && '${n['detail']}'.contains('Stock suffisant')), hasLength(1));
      expect(notes(mm, 'besoin_accorde'), 2, reason: 'un rejet n’informe ni le comptable ni le stock');

      // 4. L'ÉTAT NE RÉGRESSE JAMAIS : F1 « hors ligne » fait avancer le bon accordé d'un cran en arrière (de son point de vue, soumis → contrôle stock) ; à son retour, la mère refuse en nommant.
      mereJoignable = false;
      final locale = bon(m1, refs1[1])!;
      m1.collection('besoins').mettreAJour(locale['id'], {'etape': 'controle_stock', 'motif': 'précision du service'});
      // Pendant ce temps le bon de refs1[1] est accordé chez la mère.
      mm.collection('besoins').mettreAJour(bon(mm, refs1[1])!['id'], {'etape': 'accorde', 'arbitrePar': 'La DAF', 'arbitreLe': valInstant(auj), 'valideePar': 'La DAF'});
      mereJoignable = true;
      await converger(() => bon(m1, refs1[1])!['etape'] == 'accorde' && bon(m2, refs1[1])!['etape'] == 'accorde' && bon(mm, refs1[1])!['motif'] == 'précision du service', 'l’état accordé l’emporte, la précision du service est gardée');
      expect(bon(mm, refs1[1])!['etape'], 'accorde', reason: 'un bon accordé ne repasse pas en contrôle stock par une fusion tardive');
      // Un fileul ne s'écrit pas lui-même un arbitrage : refusé en le nommant par la mère.
      m1.collection('besoins').inserer({'reference': ref1(m1), 'service': 'Laboratoire', 'demandeur': 'Agent F1', 'etape': 'soumis', 'lignes': [ligne('Tubes', 9)], 'statut': 'actif'}, prefixe: 'BES');
      await converger(() => mm.collection('besoins').toutes.length == 8, 'le quatrième bon de F1 arrive à la mère');
      final soumisF1 = m1.collection('besoins').toutes.firstWhere((b) => b['etape'] == 'soumis' && b['demandeur'] == 'Agent F1');
      m1.collection('besoins').mettreAJour(soumisF1['id'], {'etape': 'accorde', 'arbitrePar': 'Moi-même'});
      await converger(() => bon(m1, '${soumisF1['reference']}')!['etape'] == 'soumis', 'l’arbitrage que la mère n’a pas rendu ne reste pas au poste');
      expect('${await moteur1.refusees()}', contains('arbitrage_reserve'), reason: 'la mère refuse en nommant : l’arbitrage se dépose');
      expect(mm.collection('besoins').parId(cleCircuit(soumisF1)) ?? mm.collection('besoins').toutes.firstWhere((b) => b['reference'] == soumisF1['reference']), isNotNull);
      expect(bon(mm, '${soumisF1['reference']}')!['etape'], 'soumis');

      // 5. MÈRE COUPÉE PUIS RELANCÉE : le dépôt attend, le poste travaille, jamais « accordé » avant la confirmation ; au retour la mère applique.
      final cible = refs2[0];
      await converger(() => bon(m2, cible) != null && bon(mm, cible) != null, 'départ');
      final dep2 = svc2.deposerCircuit(circuitBesoinArbitrage, bon(m2, cible)!, decision: 'complement', motif: 'Préciser la marque', role: 'da', acteur: 'La DAF');
      expect(dep2.ok, isTrue);
      await mere0.arreter();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      m2.collection('besoins').inserer({'reference': ref1(m2), 'service': 'Maternité', 'demandeur': 'Agent F2', 'etape': 'soumis', 'lignes': [ligne('Seringues', 4)], 'statut': 'actif'}, prefixe: 'BES');
      for (var i = 0; i < 3; i++) {
        try {
          await p2.cycle();
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(bon(m2, cible)!['etape'], 'soumis', reason: 'jamais accordé ni complété avant la confirmation');
      expect(svc2.depotCircuitEnAttente(circuitBesoinArbitrage, bon(m2, cible)!), isNotNull, reason: 'l’état dit « transmis à la mère, en attente »');
      expect(m2.collection('besoins').toutes.length, 9, reason: 'le poste continue de travailler pendant la coupure');
      mere0 = await Mere.creer(config);
      await mere0.demarrer();
      await converger(() => bon(m2, cible)!['etape'] == 'complement' && bon(m1, cible)!['etape'] == 'complement' && m2.collection('besoins').toutes.length == 9 && mm.collection('besoins').toutes.length == 9, 'à son retour la mère applique et tout converge');
      expect(bon(mm, cible)!['motifArbitrage'], 'Préciser la marque');
      expect(await moteur2.refusees(), isEmpty);

      // 6. COMMANDES : numérotation par plage, validation DA déposée puis appliquée, jamais d'écriture directe de « validée » par un fileul.
      String refC(Magasin m) => PlagesNumeros.de(m).reference('commandes', 'BC-2026-', 4, m.collection('commandes').toutes);
      final c1 = refC(m1), c2 = refC(m2);
      expect(c1, isNot(c2));
      m1.collection('commandes').inserer({'reference': c1, 'fournisseur': 'F001', 'fournisseurNom': 'Pharma', 'statutCommande': 'attente_validation', 'montant': 5000, 'lignes': [], 'statut': 'actif'}, prefixe: 'COM');
      m2.collection('commandes').inserer({'reference': c2, 'fournisseur': 'F001', 'fournisseurNom': 'Pharma', 'statutCommande': 'attente_validation', 'montant': 7000, 'lignes': [], 'statut': 'actif'}, prefixe: 'COM');
      await converger(() => [mm, m1, m2].every((m) => cmd(m, c1) != null && cmd(m, c2) != null), 'les commandes arrivent partout');
      expect(svc2.deposerCircuit(circuitCommandeValidation, cmd(m2, c1)!, role: 'stock', acteur: 'Le magasinier').refus!.code, 'VALIDATION_RESERVEE');
      expect(svc2.deposerCircuit(circuitCommandeValidation, cmd(m2, c1)!, role: 'da', acteur: 'La DAF').ok, isTrue);
      expect(cmd(m2, c1)!['statutCommande'], 'attente_validation', reason: 'la commande ne part pas chez le fournisseur sur un dépôt seul');
      await converger(() => [mm, m1, m2].every((m) => cmd(m, c1)!['statutCommande'] == 'validee'), 'la commande est validée par la mère et revient partout');
      expect(cmd(m1, c1)!['valideeParAgent'], 'La DAF');
      expect(cmd(m1, c1)!['dateValidation'], '2026-11-16');
      // F1 écrit « validée » lui-même sur l'autre commande (sans dépôt) : refusé en le nommant, la valeur ne reste pas.
      m1.collection('commandes').mettreAJour(cmd(m1, c2)!['id'], {'statutCommande': 'validee', 'valideePar': 'Moi'});
      await converger(() => cmd(m1, c2)!['statutCommande'] == 'attente_validation', 'RG-04 : un fileul ne se valide pas lui-même');
      expect('${await moteur1.refusees()}', contains('arbitrage_reserve'));
      expect(cmd(mm, c2)!['statutCommande'], 'attente_validation');
      // L'aval suit : la commande validée est transmise depuis F1 (la mère détient la validation).
      m1.collection('commandes').mettreAJour(cmd(m1, c1)!['id'], {'statutCommande': 'transmise'});
      await converger(() => [mm, m2].every((m) => cmd(m, c1)!['statutCommande'] == 'transmise'), 'la transmission voyage');

      // 7. RG-13 : ni le besoin ni la commande (prix d'achat des lignes) ne partent vers un téléphone ; les fileuls les reçoivent.
      final http0 = HttpClient();
      Future<Map<String, Object?>> appel(String methode, String chemin, {Map<String, Object?>? corps, Map<String, String> entetes = const {}}) async {
        final req = await http0.openUrl(methode, Uri.parse('http://127.0.0.1:$port$chemin'));
        req.headers.contentType = ContentType.json;
        entetes.forEach(req.headers.set);
        if (corps != null) req.add(utf8.encode(jsonEncode(corps)));
        final rep = await req.close();
        return (jsonDecode(await utf8.decoder.bind(rep).join()) as Map).cast<String, Object?>();
      }

      Future<Set<String>> recues(String role, Map<String, Object?> extra) async {
        final c = (await appel('POST', '/admin/code', corps: {'etiquette': role, 'role': role, ...extra}, entetes: {'x-admin': 'secret-test'}))['code'];
        final jetons = await appel('POST', '/appairage', corps: {'code': c, 'uuid': 'dev-$role', 'plateforme': 'test'});
        final noms = <String>{};
        var depuis = 0;
        while (true) {
          final pull = await appel('GET', '/sync/pull?depuis=$depuis&limite=500&epoch=${jetons['epoch']}', entetes: {'authorization': 'Bearer ${jetons['jeton']}'});
          final ops = (pull['ops'] as List).cast<Map>();
          for (final o in ops) {
            noms.add('${o['collection']}');
            depuis = (o['seq'] as num).toInt();
          }
          if (pull['fin'] == true || ops.isEmpty) break;
        }
        return noms;
      }

      expect(await recues('fileul', {}), containsAll(['besoins', 'commandes', 'validationsDeposees']));
      final mobile = await recues('mobile', {'profil': 'soignant', 'fonction': 'infirmier'});
      expect(mobile, isNotEmpty);
      expect(mobile, isNot(contains('besoins')));
      expect(mobile, isNot(contains('commandes')));
      expect(mobile, isNot(contains('validationsDeposees')));
      http0.close(force: true);
    } finally {
      for (final s in cir) {
        s.arreter();
      }
      svcMere.arreter();
      svc1.arreter();
      svc2.arreter();
      p1.arreter();
      p2.arreter();
      pm.arreter();
      try {
        await mere0.arreter();
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
