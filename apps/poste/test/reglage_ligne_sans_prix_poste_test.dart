import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/reglages_clinique_poste.dart';
import 'package:sigh_poste/sync/service_validations_deposees.dart';

/// LE RÉGLAGE « ENCAISSER LE RESTE D'UNE FACTURE QUI A UNE LIGNE SANS PRIX » (Direction de Baguidi, 16/11/2026, complément §7), au poste :
///  * Non par défaut (aucune fiche en base, ou fiche semée) ;
///  * posé sous le GESTE RÉSERVÉ `reglage_encaissement_sans_prix` (matrice, jamais un rôle en dur) : sur la mère il écrit une version datée ; un rôle sans le geste est refusé, nommé ;
///  * depuis un FILEUL, le geste se DÉPOSE ; la mère l'applique sous le rôle de l'auteur avec SA matrice ; la version revient au fileul (famille R) et s'y lit.
typedef M = Map<String, Object?>;
final auj = DateTime(2026, 11, 16, 9);

Magasin poste(String etiquette) => Magasin({
      parCollectionParametres: <M>[],
      parCollectionUsages: <M>[],
      'validationsDeposees': <M>[],
      'notifications': <M>[],
      'rbac': <M>[],
      'audit': <M>[],
      'utilisateurs': <M>[
        for (final r in ['da', 'admin', 'caissier']) {'id': 'U-$r', 'statut': 'actif', 'role': r, 'actif': true}
      ],
    })
      ..horloge = () => auj;

ServiceValidationsDeposees service(Magasin m, String etiquette) => ServiceValidationsDeposees.de(m)
  ..etiquette = etiquette
  ..horloge = () => auj;

void main() {
  test('Non par défaut ; la mère, sous le geste, écrit une version datée qui s’applique à la caisse ; le caissier sans le geste est refusé, nommé', () {
    final m = poste('M');
    expect(ReglagesClinique.encaisserResteSansPrix(m, auj), isFalse, reason: 'défaut : rien ne s’encaisse');
    final svc = service(m, 'M');
    final refus = svc.reglerSousGeste(cleEncaisserResteSansPrix, true, '2026-11-16', role: 'caissier', acteur: 'Caissière', estMere: true);
    expect(refus.refus?.code, 'REGLAGE_RESERVE');
    expect(m.collection(parCollectionParametres).toutes, isEmpty, reason: 'rien n’est écrit');
    final ok = svc.reglerSousGeste(cleEncaisserResteSansPrix, true, '2026-11-16', role: 'da', acteur: 'DAF', estMere: true, motif: 'Ruptures de prix fournisseur');
    expect(ok.refus, isNull);
    expect(ok.version!.valeur, isTrue);
    expect(ReglagesClinique.encaisserResteSansPrix(m, auj), isTrue);
    expect(ReglagesClinique.encaisserResteSansPrix(m, DateTime(2026, 11, 15)), isFalse, reason: 'versionné par date : la veille, le défaut');
    expect(m.collection('audit').toutes.any((a) => '${a['action']}'.contains('Réglage d’un paramètre')), isTrue, reason: 'RG-12');
    // Une décision de la matrice retire le geste à la DAF : refermer lui est refusé à son tour.
    m.collection('rbac').inserer({'role': 'da', 'statut': 'actif', 'droitsGestes': {gesteReglageEncaissementSansPrix: false}});
    expect(svc.reglerSousGeste(cleEncaisserResteSansPrix, false, '2026-11-17', role: 'da', acteur: 'DAF', estMere: true).refus?.code, 'REGLAGE_RESERVE');
  });

  test('depuis un FILEUL : le geste se dépose, la mère l’applique sous le rôle de l’auteur (sa matrice), la version revient et s’applique chez le fileul', () {
    final fileul = poste('F1'), mere = poste('M');
    final sf = service(fileul, 'F1');
    final d = sf.reglerSousGeste(cleEncaisserResteSansPrix, true, '2026-11-16', role: 'da', acteur: 'DAF', estMere: false, motif: 'Depuis le bureau de la DAF');
    expect(d.refus, isNull);
    expect(d.version, isNull, reason: 'le fileul n’écrit pas la version');
    expect(fileul.collection(parCollectionParametres).toutes, isEmpty);
    expect(sf.depotReglageEnAttente(cleEncaisserResteSansPrix), isNotNull, reason: 'l’écran dit « transmis à la mère, en attente »');
    expect(ReglagesClinique.encaisserResteSansPrix(fileul, auj), isFalse, reason: 'jamais « appliqué » avant la mère');
    // Rejouable : un second geste identique n'est pas doublé.
    expect(sf.reglerSousGeste(cleEncaisserResteSansPrix, true, '2026-11-16', role: 'da', acteur: 'DAF', estMere: false).dejaDepose, isTrue);
    // Le caissier, depuis le même fileul, est refusé dès le poste.
    expect(sf.reglerSousGeste(cleEncaisserResteSansPrix, true, '2026-11-16', role: 'caissier', acteur: 'Caissière', estMere: false).refus?.code, 'REGLAGE_RESERVE');

    // Le pont d'activité porte le dépôt à la mère (simulé : la copie de la fiche).
    final depot = fileul.collection('validationsDeposees').toutes.single;
    expect(depot[champCompteDecision], isNull, reason: 'aucun compte signataire dans ce banc');
    mere.collection('validationsDeposees').ajouterSansJournal({...depot});
    final sm = service(mere, 'M')..exigerCompteInscrit = false;
    expect(sm.traiter(), 1);
    final verdict = mere.collection('validationsDeposees').toutes.single;
    expect(verdict['etat'], valDepotAppliquee);
    final versions = mere.collection(parCollectionParametres).toutes;
    expect(versions, hasLength(1));
    expect([versions.single['cle'], versions.single['valeur'], versions.single['dateEffet'], versions.single['auteur']], [cleEncaisserResteSansPrix, true, '2026-11-16', 'DAF']);
    expect(ReglagesClinique.encaisserResteSansPrix(mere, auj), isTrue);
    expect(mere.collection('audit').toutes.any((a) => '${a['action']}'.contains('Réglage d’un paramètre')), isTrue, reason: 'RG-12 : déposé par la DAF, appliqué par la mère');
    // Rejoué (le pont renvoie la même fiche) : rien n'est écrit une seconde fois.
    expect(sm.traiter(), 0);

    // La synchronisation (famille R) rapporte la version et le verdict au fileul.
    fileul.collection(parCollectionParametres).ajouterSansJournal({...versions.single});
    fileul.collection('validationsDeposees').mettreAJour(depot['id'], {'etat': valDepotAppliquee}, journaliser: false);
    expect(ReglagesClinique.encaisserResteSansPrix(fileul, auj), isTrue);
    expect(sf.depotReglageEnAttente(cleEncaisserResteSansPrix), isNull);
  });

  test('la mère refait le contrôle avec SA matrice : un geste retiré chez elle refuse le dépôt, nommé, rien n’est écrit', () {
    final fileul = poste('F1'), mere = poste('M');
    service(fileul, 'F1').reglerSousGeste(cleEncaisserResteSansPrix, true, '2026-11-16', role: 'admin', acteur: 'Administrateur', estMere: false);
    mere.collection('validationsDeposees').ajouterSansJournal({...fileul.collection('validationsDeposees').toutes.single});
    mere.collection('rbac').inserer({'role': 'admin', 'statut': 'actif', 'droitsGestes': {gesteReglageEncaissementSansPrix: false}});
    service(mere, 'M')
      ..exigerCompteInscrit = false
      ..traiter();
    final v = mere.collection('validationsDeposees').toutes.single;
    expect([v['etat'], v['resultatCode']], [valDepotRefusee, 'REGLAGE_RESERVE']);
    expect(mere.collection(parCollectionParametres).toutes, isEmpty);
  });
}
