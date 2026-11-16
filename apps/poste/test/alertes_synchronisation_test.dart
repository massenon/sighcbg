// E2143 (arbitrage du 04/11/2026) : un doublon détecté par la synchronisation n'est jamais corrigé en silence ; il est signalé à ceux qui tranchent.
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/core/donnees_navigation.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/shell/centre_notifications.dart';

void main() {
  final donnees = DonneesNavigation.depuisDossier();
  final horloge = DateTime(2026, 11, 4, 9);

  Magasin avecMarqueurs() {
    final m = Magasin({}, 'POSTE', {});
    m.collection('patients').inserer({'statut': 'actif', 'code': 'CBG/12/26', 'codeEnDoublon': true});
    m.collection('factures').inserer({'statut': 'actif', 'numero': 'FAC-0042', 'numeroEnDoublon': true});
    m.collection('admissions').inserer({'statut': 'actif', 'lit': 'Ch2-L1', 'litEnConflit': true});
    m.collection('produits').inserer({'statut': 'actif', 'designation': 'Paracétamol 500 mg', 'stockNegatifDetecte': true});
    return m;
  }

  List<AlerteNotif> pour(Magasin m, String role) =>
      CentreNotifications(magasin: m, donnees: () => donnees, role: () => role, horloge: () => horloge).collecter().where((n) => n.source == 'sync_a_arbitrer').toList();

  test('la Direction voit chaque doublon, nommé, avec l’écran où le traiter', () {
    final a = pour(avecMarqueurs(), 'direction');
    expect(a.map((n) => n.titre), containsAll(['Dossier en doublon : CBG/12/26', 'Facture au numéro en double : FAC-0042', 'Lit en conflit : Ch2-L1', 'Stock négatif détecté : Paracétamol 500 mg']));
    expect(a.every((n) => n.lien == null || donnees.matrice.peutVoir('direction', n.lien!)), isTrue);
  });

  test('16/11/2026 : deux couvertures ouvertes pour un même patient sont annoncées à la DAF, à la Direction et à l’administrateur — pas au caissier ; une seule ou une close : rien', () {
    Magasin avec(List<Map<String, Object?>> couvertures) {
      final m = Magasin({}, 'POSTE', {});
      for (final c in couvertures) {
        m.collection('couverturesAssurance').inserer({'statut': 'actif', 'patientId': 'P1', 'patientCode': 'CBG/7/26', 'assureurNom': 'NSIA', ...c});
      }
      return m;
    }

    List<AlerteNotif> lues(Magasin m, String role) => pour(m, role).where((n) => n.titre.startsWith('Conflit de couverture')).toList();
    // Le marqueur est DÉDUIT par le pont d'activité à chaque application d'opérations ; la source ne lit que le marqueur ET revérifie le conflit.
    final conflit = avec([
      {'debut': '2026-10-01', 'couvertureEnConflit': true},
      {'debut': '2026-11-01', 'couvertureEnConflit': true},
    ]);
    for (final r in ['da', 'direction', 'admin']) {
      expect(lues(conflit, r).single.titre, 'Conflit de couverture à arbitrer : CBG/7/26', reason: r);
      expect(lues(conflit, r).single.lien, 'adm-validations');
    }
    expect(lues(conflit, 'caissier'), isEmpty);
    expect(lues(avec([{'debut': '2026-10-01', 'couvertureEnConflit': true}]), 'da'), isEmpty, reason: 'une seule couverture ouverte : pas de conflit');
    expect(lues(avec([{'debut': '2026-10-01', 'fin': '2026-10-31', 'couvertureEnConflit': true}, {'debut': '2026-11-01', 'couvertureEnConflit': true}]), 'da'), isEmpty, reason: 'une couverture close n’est pas un conflit');
  });

  test('16/11/2026 : une ligne d’ordonnance délivrée par deux postes, une ligne encaissée par deux guichets (marqueurs en LISTE) sont annoncées', () {
    final m = Magasin({}, 'POSTE', {});
    m.collection('ordonnances').inserer({'statut': 'actif', 'numero': 'ORD-2026-00007', 'delivranceEnDoublon': [0]});
    m.collection('factures').inserer({'statut': 'actif', 'numero': 'FP-2026-00007', 'encaissementEnDoublon': ['L001']});
    m.collection('ordonnances').inserer({'statut': 'actif', 'numero': 'ORD-2026-00008', 'delivranceEnDoublon': <Object?>[]});
    final a = pour(m, 'direction').map((n) => n.titre).toList();
    expect(a, containsAll(['Délivrance en double : ORD-2026-00007', 'Encaissement en double : FP-2026-00007']));
    expect(a.where((t) => t.contains('ORD-2026-00008')), isEmpty, reason: 'une liste vide n’alerte pas');
    expect(pour(m, 'caissier'), isEmpty);
  });

  test('le caissier ne reçoit rien : il ne tranche pas', () => expect(pour(avecMarqueurs(), 'caissier'), isEmpty));

  test('sans marqueur, aucune alerte (jamais un doublon inventé)', () => expect(pour(Magasin({}, 'POSTE', {}), 'direction'), isEmpty));

  test('ADR-0006 : un conflit entre pairs est annoncé à ceux qui tranchent, pas aux autres', () {
    final m = Magasin({}, 'POSTE', {});
    m.collection('conflitsPair').inserer({'statut': 'actif', 'collection': 'patients', 'fiche': 'p1', 'champ': 'telephone', 'libelle': 'téléphone du patient CBG/12/26', 'valeurs': '90 / 91', 'ecran': 'm1-patients'});
    List<AlerteNotif> de(String r) => CentreNotifications(magasin: m, donnees: () => donnees, role: () => r, horloge: () => horloge).collecter().where((n) => n.source == 'pair_conflits').toList();
    expect(de('da').single.titre, 'Conflit à trancher : téléphone du patient CBG/12/26');
    expect(de('da').single.lien, 'm1-patients');
    expect(de('direction'), hasLength(1));
    expect(de('caissier'), isEmpty);
    expect(de('medecin'), isEmpty);
  });

  test('sans écran désigné, la ligne ouvre la modale « Conflits à trancher »', () {
    final m = Magasin({}, 'POSTE', {});
    m.collection('conflitsPair').inserer({'statut': 'actif', 'collection': 'rendezvous', 'fiche': 'r1', 'champ': 'heure', 'valeurs': '9 h / 10 h'});
    final a = CentreNotifications(magasin: m, donnees: () => donnees, role: () => 'direction', horloge: () => horloge).collecter().where((n) => n.source == 'pair_conflits').single;
    expect(a.lien, 'pair-trancher');
  });
}
