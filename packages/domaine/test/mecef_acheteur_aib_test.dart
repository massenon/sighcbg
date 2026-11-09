// L'AIB de la fenêtre « Facture normalisée » lu au barème daté (lot A5) : situation d'office d'après l'IFU ou choisie à la main, taux arrêté en vigueur
// à la date de la facture, refus nommé AIB_SANS_BAREME sans version arrêtée, montants entiers sur le HORS TAXES, MECeF fermé = rien.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

CpdFiche v(String id, String situation, num taux, {String? effet, bool arrete = true, String statut = 'actif'}) => {
      'id': id,
      'situation': situation,
      'taux': taux,
      'dateEffet': effet,
      'statutArret': arrete ? cpdStatutArrete : cpdStatutNonArrete,
      'arrete': arrete,
      'aValider': !arrete,
      'statut': statut,
    };

CpdFiche s(String code, String libelle, String declencheur, int ordre) =>
    {'id': 'S-$code', 'code': code, 'libelle': libelle, 'declencheur': declencheur, 'ordre': ordre, 'statut': 'actif'};

void main() {
  final situations = [
    s('ifu_actif', 'Acheteur avec IFU actif', cpdDeclencheurIfuRenseigne, 1),
    s('ifu_inactif_ou_absent', 'Acheteur sans IFU actif', cpdDeclencheurIfuAbsent, 2),
    s('prestation_service', 'Prestation de service', cpdDeclencheurChoix, 3),
  ];
  // Le barème d'origine : 5 % arrêté au 07/09/2026 ; 1 % et 3 % non arrêtés.
  final bareme = [
    v('B1', 'ifu_inactif_ou_absent', 5, effet: '2026-09-07'),
    v('B2', 'ifu_actif', 1, arrete: false),
    v('B3', 'prestation_service', 3, arrete: false),
  ];
  final jour = DateTime(2026, 11, 9);
  const ifu = '3201642748214';

  AibAcheteur aib({Object? i, Object? choix, DateTime? date, List<CpdFiche>? versions}) =>
      aibPourAcheteur(ifu: i, situationChoisie: choix, date: date ?? jour, situations: situations, versions: versions ?? bareme);

  group('la situation se choisit d\'office d\'après l\'IFU', () {
    test('aucun IFU : « IFU absent », 5 % arrêté appliqué, motif du moteur', () {
      final r = aib();
      expect(r.ok, isTrue);
      expect(r.situation, 'ifu_inactif_ou_absent');
      expect(r.taux, 5);
      expect(r.choixManuel, isFalse);
      expect(r.motif, 'Taux de 5 % arrêté, en vigueur depuis le 07/09/2026.');
    });

    test('IFU de 13 chiffres (espaces tolérés) : « IFU actif » présumé ; son 1 % n\'est PAS arrêté : refus nommé, jamais appliqué', () {
      final r = aib(i: '3201 6427 48214');
      expect(r.situation, 'ifu_actif');
      expect(r.presomption, isTrue);
      expect(r.avertissement, contains('présumé actif'));
      expect(r.taux, isNull);
      expect(r.ok, isFalse);
      expect(r.refus!.code, cpdCodeAibSansBareme);
      expect(r.nonArretes, ['1 % — non arrêté, à valider']);
      expect(r.refus!.motif, contains('1 % — non arrêté, à valider'));
    });

    test('IFU invalide : IFU_INVALIDE', () {
      expect(aib(i: '123').refus!.code, 'IFU_INVALIDE');
    });
  });

  group('choix manuel parmi les situations du barème', () {
    test('« prestation de service » : 3 % non arrêté, donc refus nommé ; le choix manuel est dit', () {
      final r = aib(choix: 'prestation_service');
      expect(r.choixManuel, isTrue);
      expect(r.refus!.code, cpdCodeAibSansBareme);
      expect(r.nonArretes, ['3 % — non arrêté, à valider']);
    });

    test('l\'agent change la situation : un IFU présent peut être ramené à « sans IFU actif » (5 % arrêté)', () {
      final r = aib(i: ifu, choix: 'ifu_inactif_ou_absent');
      expect(r.ok, isTrue);
      expect(r.taux, 5);
      expect(r.choixManuel, isTrue);
    });

    test('une situation qui n\'est pas au barème (ou archivée) est refusée en le disant', () {
      expect(aib(choix: 'inventee').refus!.code, cpdCodeAibSansBareme);
      final archivee = [for (final x in situations) x['code'] == 'prestation_service' ? {...x, 'statut': 'archive'} : x];
      final r = aibPourAcheteur(situationChoisie: 'prestation_service', date: jour, situations: archivee, versions: bareme);
      expect(r.refus!.code, cpdCodeAibSansBareme);
    });
  });

  group('le taux est celui EN VIGUEUR À LA DATE', () {
    test('avant le 07/09/2026 : aucun taux arrêté, refus nommé qui cite la date de prise d\'effet', () {
      final r = aib(date: DateTime(2026, 9, 6));
      expect(r.taux, isNull);
      expect(r.refus!.code, cpdCodeAibSansBareme);
      expect(r.refus!.motif, contains('07/09/2026'));
      expect(aib(date: DateTime(2026, 9, 7)).taux, 5);
    });

    test('une version arrêtée datée dans le FUTUR ne s\'applique pas : le taux d\'aujourd\'hui reste celui d\'hier', () {
      final avecFutur = [...bareme, v('B4', 'ifu_inactif_ou_absent', 6, effet: '2027-01-01')];
      expect(aib(versions: avecFutur).taux, 5);
      expect(aib(versions: avecFutur, date: DateTime(2027, 1, 1)).taux, 6);
      expect(aib(versions: avecFutur, date: DateTime(2026, 12, 31)).taux, 5);
    });

    test('quand la Direction arrête le 1 % (IFU actif), il s\'applique à partir de sa date d\'effet', () {
      final arrete = [...bareme.where((f) => f['id'] != 'B2'), v('B2b', 'ifu_actif', 1, effet: '2026-11-01')];
      expect(aib(i: ifu, versions: arrete).taux, 1);
      expect(aib(i: ifu, versions: arrete, date: DateTime(2026, 10, 31)).refus!.code, cpdCodeAibSansBareme);
    });

    test('une version archivée ne s\'applique pas', () {
      final r = aib(versions: [v('B1', 'ifu_inactif_ou_absent', 5, effet: '2026-09-07', statut: 'archive')]);
      expect(r.refus!.code, cpdCodeAibSansBareme);
    });
  });

  group('l\'acheteur résolu au barème', () {
    ({AcheteurMecef? acheteur, RefusMecef? refus, AibAcheteur aib}) r(
            {Object? i, Object? nom = 'Clinique X', Object? choix, DateTime? date, List<CpdFiche>? versions}) =>
        acheteurNormaliseAuBareme(ifu: i, nom: nom, situationChoisie: choix, date: date ?? jour, situations: situations, versions: versions ?? bareme);

    test('sans IFU : l\'acheteur porte 5 % et sa situation', () {
      final x = r(i: '', nom: '');
      expect(x.refus, isNull);
      expect(x.acheteur!.aibTaux, 5);
      expect(x.acheteur!.aibSituation, 'ifu_inactif_ou_absent');
      expect(x.acheteur!.toJson()['aibSituation'], 'ifu_inactif_ou_absent');
    });

    test('IFU actif : refus AIB_SANS_BAREME (1 % non arrêté), aucun acheteur', () {
      final x = r(i: ifu);
      expect(x.acheteur, isNull);
      expect(x.refus!.code, cpdCodeAibSansBareme);
    });

    test('l\'identité se contrôle d\'abord : IFU invalide, IFU sans nom', () {
      expect(r(i: '12').refus!.code, 'IFU_INVALIDE');
      expect(r(i: ifu, nom: '').refus!.code, 'NOM_ACHETEUR_ABSENT');
    });

    test('l\'ancienne voie (sans situation) reste bornée à 0, 1, 5 ; la voie du barème accepte un taux entier arrêté (3) mais jamais un taux absent', () {
      expect(validerAcheteurMecef(aibTaux: 3).refus!.code, 'AIB_TAUX_INVALIDE');
      expect(validerAcheteurMecef(aibTaux: 3, aibSituation: 'prestation_service').acheteur!.aibTaux, 3);
      expect(validerAcheteurMecef(aibSituation: 'prestation_service').refus!.code, 'AIB_TAUX_INVALIDE');
      expect(validerAcheteurMecef(aibTaux: 120, aibSituation: 'x').refus!.code, 'AIB_TAUX_INVALIDE');
      expect(validerAcheteurMecef().acheteur!.aibTaux, aibTauxParDefaut);
      expect(validerAcheteurMecef().acheteur!.toJson().containsKey('aibSituation'), isFalse);
    });

    test('un taux du barème décimal est refusé : le poste calcule en montants entiers', () {
      final x = r(versions: [v('B1', 'ifu_inactif_ou_absent', 2.5, effet: '2026-09-07')]);
      expect(x.refus!.code, 'AIB_TAUX_INVALIDE');
    });
  });

  group('le geste d\'encaissement', () {
    Map<String, Object?> piece() => {
          'id': 'FAC1',
          'numero': 'FN-1',
          'montantTTC': 10000,
          'partPatient': 10000,
          'statutPaiement': 'impayee',
          'lignes': [
            {'id': 'L1', 'designation': 'Consultation', 'quantite': 1, 'prixUnitaire': 10000, 'partAssureur': 0, 'partPatient': 10000, 'statutPaiement': 'impaye'}
          ],
        };
    final acheteur5 = acheteurNormaliseAuBareme(ifu: '', nom: '', date: jour, situations: situations, versions: bareme).acheteur!;

    test('l\'acheteur du barème est rangé dans la pièce avec sa situation ; l\'AIB se calcule sur le HORS TAXES en montants entiers', () {
      final e = encaisser(piece(),
          aujourdhui: '2026-11-09', maintenant: 'x', acheteur: {'ifu': acheteur5.ifu, 'nom': acheteur5.nom, 'aibTaux': acheteur5.aibTaux, 'aibSituation': acheteur5.aibSituation});
      expect(e.refus, isNull);
      expect(e.facture['aibTaux'], 5);
      expect(e.facture['aibSituation'], 'ifu_inactif_ou_absent');
      // 10 000 TTC à TVA 18 % : HT 8 475, AIB 424 (5 % de 8 475 = 423,75, arrondi au franc) — jamais sur le TTC (500).
      final prep = preparerNormalisation({...e.facture, 'montantPaye': 10000},
          acheteurSaisi: {'ifu': '', 'nom': '', 'aibTaux': 5, 'aibSituation': 'ifu_inactif_ou_absent'}, tauxTvaCourant: 18);
      expect(prep.ok, isTrue);
      expect(prep.montants!.ht, 8475);
      expect(prep.montants!.aib, 424);
      expect(prep.montants!.aib, isA<int>());
      expect(prep.montants!.net, 10000 + 424);
    });

    test('MECeF fermé : la fenêtre n\'existe pas, aucun acheteur ni champ fiscal n\'est posé, même si un acheteur du barème est présenté', () {
      final e = encaisser(piece(),
          aujourdhui: '2026-11-09',
          maintenant: 'x',
          mecefActif: false,
          acheteur: {'ifu': ifu, 'nom': 'X', 'aibTaux': 5, 'aibSituation': 'ifu_inactif_ou_absent'});
      expect(e.refus, isNull);
      for (final k in ['ifuClient', 'acheteurNom', 'aibTaux', 'aibSituation', 'statutMecef', 'baseMecef']) {
        expect(e.facture.containsKey(k), isFalse, reason: k);
      }
    });

    test('un taux du barème sans situation nommée reste soumis à la liste 0, 1, 5 (ancienne voie intacte)', () {
      final e = encaisser(piece(), aujourdhui: '2026-11-09', maintenant: 'x', acheteur: {'aibTaux': 3});
      expect(e.refusCode, 'AIB_TAUX_INVALIDE');
    });
  });
}
