import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/arbitrages_poste.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/mere/client_mere.dart';
import 'package:sigh_poste/shell/centre_notifications.dart';
import 'package:sigh_poste/sync/moteur_fileul.dart';
import 'package:sigh_poste/sync/pont_activite.dart';
import 'package:sigh_sync/sigh_sync.dart';

/// DÉCISION DU 16/11/2026, À TRAVERS LA VRAIE MÈRE DART ET DEUX FILEULS HORS LIGNE : deux postes changent la couverture du MÊME assuré sans se parler ; à la reprise, deux couvertures restent
/// ouvertes. La mère les DÉTECTE à l'application des opérations (marqueur local, jamais synchronisé), l'alerte part à la DAF sans bloquer personne, la prise en charge (RG-09) lit la couverture au
/// début le plus récent (jamais deux), et l'arbitrage — clore l'une des deux avec motif — se propage aux deux fileuls ; l'alerte retombe partout.
final donnees = DonneesNavigation.depuisDossier();
const collections = ['rbac', 'modulesActifs', 'audit', 'rolesBase', 'utilisateurs', 'patients', 'couverturesAssurance', 'notifications'];
Magasin poste() => Magasin.depuisDossier(collections);

void main() {
  test('DEUX FILEULS HORS LIGNE, VRAIE MÈRE : conflit de couverture détecté, alerté, lu sans ambiguïté, arbitré, propagé', () async {
    const port = 19791;
    final d = Directory.systemTemp.createTempSync('conflit-couverture');
    addTearDown(() => d.deleteSync(recursive: true));
    final mere = await Mere.creer(ConfigMere(port: port, dbChemin: '${d.path}/mere.db', admin: 'secret-test', dossierSauvegardes: '${d.path}/sauv'));
    await mere.demarrer();
    addTearDown(() async {
      try {
        await mere.arreter();
      } catch (_) {}
    });
    final console = ClientMere(base: Uri.parse('http://127.0.0.1:$port'), secretAdmin: 'secret-test');
    final jour = DateTime(2026, 11, 16);
    final mm = poste(), mf1 = poste(), mf2 = poste();
    for (final m in [mm, mf1, mf2]) {
      m.horloge = () => jour;
    }
    mm.utilisateur = 'Poste mère';
    final moteur1 = MoteurFileul.creer(dbChemin: '${d.path}/F1.db', mere: 'http://127.0.0.1:1', nom: 'F1');
    final moteur2 = MoteurFileul.creer(dbChemin: '${d.path}/F2.db', mere: 'http://127.0.0.1:1', nom: 'F2');
    TransportFileul tf(MoteurFileul m) => TransportFileul(lire: m.liste, ecrireFiche: (c, f, {required existe, required champs}) => m.ecrire(c, f, existe: existe, champs: champs), restaurerFiche: m.restaurer);
    const cols = {'couverturesAssurance', 'patients'};
    final pm = PontActivite(mm, TransportMereLocale(port: port, admin: 'secret-test'), etiquette: 'M', collections: cols);
    final pf1 = PontActivite(mf1, tf(moteur1), etiquette: 'F1', collections: cols);
    final pf2 = PontActivite(mf2, tf(moteur2), etiquette: 'F2', collections: cols);

    Future<void> tour() async {
      await pf1.cycle();
      await pf2.cycle();
      await pm.cycle();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pf1.cycle();
      await pf2.cycle();
    }

    Future<void> converger(bool Function() fini, String quoi) async {
      final fin = DateTime.now().add(const Duration(seconds: 60));
      while (!fini()) {
        await tour();
        if (DateTime.now().isAfter(fin)) fail('$quoi : pas de convergence. erreurs ${pm.erreur.value} ${pf1.erreur.value} ${pf2.erreur.value} ; refus ${pm.motifsRefus} ${pf1.motifsRefus} ${pf2.motifsRefus}');
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }

    for (final (nom, moteur) in [('F1', moteur1), ('F2', moteur2)]) {
      final code = await console.codeAppareil(nom).timeout(const Duration(seconds: 20));
      await moteur.rattacher('http://127.0.0.1:$port', code).timeout(const Duration(seconds: 20));
      moteur.demarrer();
    }

    final pat = mm.collection('patients').actives.firstWhere((p) => p['externe'] != true && (p['assureur'] == null || '${p['assureur']}'.isEmpty));
    Map<String, Object?> couverture(String debut, String police, String souscripteur) => {
          'statut': 'actif', 'patientId': pat['id'], 'patientCode': pat['code'], 'patient': '${pat['nom']} ${pat['prenom']}', 'assureur': 'NSIA', 'assureurNom': 'NSIA', 'numeroPolice': police,
          'souscripteurId': souscripteur, 'tauxPriseEnCharge': 80, 'carteExpiration': '2027-12-31', 'debut': debut, 'fin': null, 'motif': 'Changement d’employeur'
        };

    // HORS LIGNE : chaque fileul change la couverture du même assuré, sans cycle entre les deux écritures.
    final c1 = mf1.collection('couverturesAssurance').inserer(couverture('2026-10-01', 'POL-F1', 'S-F1'), prefixe: 'COV').fiche;
    final c2 = mf2.collection('couverturesAssurance').inserer(couverture('2026-11-01', 'POL-F2', 'S-F2'), prefixe: 'COV').fiche;
    await converger(() => mm.collection('couverturesAssurance').actives.where((c) => c['patientId'] == pat['id'] && c['debut'] != null && ('${c['numeroPolice']}' == 'POL-F1' || '${c['numeroPolice']}' == 'POL-F2')).length == 2 && pm.couverturesEnConflitCompte.value >= 2, 'les deux couvertures arrivent à la mère');

    // 1. LA MÈRE DÉTECTE : un marqueur local sur chacune, un conflit, jamais corrigé en silence.
    final chezMere = mm.collection('couverturesAssurance').actives.where((c) => c['patientId'] == pat['id'] && c['fin'] == null).toList();
    expect(chezMere, hasLength(2));
    expect(chezMere.every((c) => c['couvertureEnConflit'] == true), isTrue);
    expect(assCouverturesEnConflit(mm.collection('couverturesAssurance').actives), hasLength(1));
    expect(marqueursLocaux, contains('couvertureEnConflit'), reason: 'le marqueur est déduit par chaque poste, il ne voyage jamais');

    // 2. L'ALERTE part à la DAF (sans bloquer personne) ; le caissier ne tranche pas.
    List<AlerteNotif> alertes(Magasin m, String role) =>
        CentreNotifications(magasin: m, donnees: () => donnees, role: () => role, horloge: () => jour).collecter().where((n) => n.titre.startsWith('Conflit de couverture')).toList();
    expect(alertes(mm, 'da').single.titre, contains('${pat['code']}'));
    expect(alertes(mm, 'caissier'), isEmpty);

    // 3. EN ATTENTE, RG-09 lit UNE couverture, celle dont le début est le plus récent — la même chez la mère et chez les deux fileuls, quel que soit l'ordre de réception.
    String? lue(Magasin m) => couvertureALaDate(pat, m.collection('couverturesAssurance').actives, '2026-11-16')?['numeroPolice'] as String?;
    await converger(() => mf1.collection('couverturesAssurance').actives.length == mm.collection('couverturesAssurance').actives.length && mf2.collection('couverturesAssurance').actives.length == mm.collection('couverturesAssurance').actives.length, 'les fileuls reçoivent les deux');
    expect([lue(mm), lue(mf1), lue(mf2)], ['POL-F2', 'POL-F2', 'POL-F2']);
    expect(couvertureALaDate(pat, mm.collection('couverturesAssurance').actives, '2026-10-15')!['numeroPolice'], 'POL-F1', reason: 'avant le début de la seconde, la première est la seule en force');

    // 4. L'ARBITRAGE : clore l'une des deux, avec motif. Refus nommé sans motif ; rien n'est écrit. L'identifiant est celui de la fiche CHEZ LA MÈRE (une fiche née chez un fileul y porte le sien).
    final aClore = chezMere.firstWhere((c) => c['numeroPolice'] == 'POL-F1');
    final refus = ArbitragesPoste.arbitrerCouverture(mm, patientId: pat['id'], cloreId: aClore['id'], motif: ' ', jour: '2026-11-16', auteur: 'LA DAF');
    expect(refus!.code, 'MOTIF_REQUIS');
    expect(mm.collection('couverturesAssurance').parId(aClore['id'])!['fin'], isNull);
    final fait = ArbitragesPoste.arbitrerCouverture(mm, patientId: pat['id'], cloreId: aClore['id'], motif: 'Le patient a bien changé d’employeur le 01/11 : une seule police', jour: '2026-11-16', auteur: 'LA DAF');
    expect(fait, isNull);
    final close = mm.collection('couverturesAssurance').parId(aClore['id'])!;
    expect(close['fin'], '2026-10-31');
    expect(close['arbitrePar'], 'LA DAF');
    expect(close['statut'], 'actif', reason: 'RG-14 : la couverture close reste écrite, jamais supprimée ni archivée');
    expect(mm.collection('audit').toutes.any((x) => '${x['action']}'.contains('Arbitrage d’un conflit de couverture')), isTrue);

    // 5. L'arbitrage SE PROPAGE : les deux fileuls reçoivent la fin, l'alerte retombe partout, la lecture ne change pas pour le jour même.
    bool finRecue(Magasin m) => m.collection('couverturesAssurance').actives.any((c) => c['patientId'] == pat['id'] && c['numeroPolice'] == 'POL-F1' && c['fin'] == '2026-10-31');
    await converger(() => finRecue(mf1) && finRecue(mf2), 'l’arbitrage arrive aux deux fileuls');
    await converger(() => pm.couverturesEnConflitCompte.value == 0 && pf1.couverturesEnConflitCompte.value == 0 && pf2.couverturesEnConflitCompte.value == 0, 'le marqueur retombe partout');
    for (final m in [mm, mf1, mf2]) {
      expect(alertes(m, 'da'), isEmpty);
      expect(assCouverturesEnConflit(m.collection('couverturesAssurance').actives), isEmpty);
      expect(lue(m), 'POL-F2');
      expect(m.collection('couverturesAssurance').toutes.where((c) => c['patientId'] == pat['id']).any((c) => c['couvertureEnConflit'] == true), isFalse);
    }
    expect([c1['id'], c2['id']], everyElement(isNotNull));
  }, timeout: const Timeout(Duration(seconds: 300)));
}
