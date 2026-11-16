// Le barème de l'AIB PAR SITUATION de l'acheteur (modèle de la maquette, lot A1 de la Direction) : le taux en vigueur À UNE DATE, versionné par date
// d'effet (comme la grille des primes), jamais écrasé ; les statuts de Baguidi (arrêté / non arrêté) et le refus nommé AIB_SANS_BAREME.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

CpdFiche v(String id, String situation, num taux,
        {String? effet, bool arrete = true, String statut = 'actif', String? dateArret, String? decideur, String? fin}) =>
    {
      'id': id,
      'situation': situation,
      'taux': taux,
      'dateEffet': effet,
      if (fin != null) 'dateFin': fin,
      'statutArret': arrete ? cpdStatutArrete : cpdStatutNonArrete,
      'arrete': arrete,
      'aValider': !arrete,
      'dateArret': dateArret,
      'decideurArret': decideur,
      'source': 'Source de test',
      'motif': 'Motif de test',
      'statut': statut,
    };

CpdFiche s(String code, String libelle, String declencheur, int ordre, {String statut = 'actif'}) =>
    {'id': 'S-$code', 'code': code, 'libelle': libelle, 'declencheur': declencheur, 'ordre': ordre, 'statut': statut};

void main() {
  final situations = [
    s('ifu_actif', 'Acheteur avec IFU actif', cpdDeclencheurIfuRenseigne, 1),
    s('ifu_inactif_ou_absent', 'Acheteur sans IFU actif', cpdDeclencheurIfuAbsent, 2),
    s('prestation_service', 'Prestation de service', cpdDeclencheurChoix, 3),
  ];
  // 5 % arrêté depuis le 07/09/2026 pour l'acheteur sans IFU actif ; le 1 % (IFU actif) et le 3 % (prestation) figurent au barème mais ne sont pas
  // arrêtés ; une CORRECTION ajoute une version à 6 % au 01/01/2027.
  final bareme = [
    v('B1', 'ifu_inactif_ou_absent', 5, effet: '2026-09-07', dateArret: '2026-09-07', decideur: 'Direction'),
    v('B2', 'ifu_actif', 1, arrete: false),
    v('B3', 'prestation_service', 3, arrete: false),
    v('B4', 'ifu_inactif_ou_absent', 6, effet: '2027-01-01', dateArret: '2026-12-15', decideur: 'Direction'),
  ];
  const sans = 'ifu_inactif_ou_absent';

  group('le taux en vigueur à une date', () {
    test('avant la première version arrêtée : AUCUN taux, refus nommé AIB_SANS_BAREME, et le motif nomme la date de prise d\'effet', () {
      final r = cpdTauxAibALaDate(bareme, sans, DateTime(2026, 9, 6), situations: situations);
      expect(r.taux, isNull);
      expect(r.ok, isFalse);
      expect(r.code, cpdCodeAibSansBareme);
      expect(r.motif, contains('07/09/2026'));
    });

    test('le jour de la prise d\'effet et après : 5 %, pas 6 % tant que la version corrigée n\'a pas pris effet ; chaque réponse porte son rang', () {
      expect(cpdTauxAibALaDate(bareme, sans, DateTime(2026, 9, 7)).taux, 5);
      expect(cpdTauxAibALaDate(bareme, sans, DateTime(2026, 12, 31)).taux, 5);
      final r = cpdTauxAibALaDate(bareme, sans, DateTime(2026, 12, 31));
      expect(r.version!['id'], 'B1');
      expect(r.rang, 1);
      expect(r.code, isNull);
    });

    test('une correction AJOUTE une version : à partir de sa date d\'effet 6 %, et une date passée garde 5 % (l\'acompte déjà retenu ne se réécrit pas)', () {
      final r = cpdTauxAibALaDate(bareme, sans, DateTime(2027, 1, 1));
      expect(r.taux, 6);
      expect(r.rang, 2);
      expect(cpdTauxAibALaDate(bareme, sans, DateTime(2027, 6, 30)).version!['id'], 'B4');
      expect(cpdTauxAibALaDate(bareme, sans, DateTime(2026, 10, 1)).taux, 5);
    });

    test('la fin d\'une version est CALCULÉE : la veille de la version arrêtée suivante ; la dernière n\'a pas de fin', () {
      expect(cpdFinDeVersion(bareme, bareme[0]), '2026-12-31');
      expect(cpdFinDeVersion(bareme, bareme[3]), isNull);
      // une version non arrêtée ne ferme rien
      final avecAttente = [...bareme, v('B5', sans, 7, effet: '2027-06-01', arrete: false)];
      expect(cpdFinDeVersion(avecAttente, bareme[3]), isNull);
      expect(cpdTauxAibALaDate(avecAttente, sans, DateTime(2027, 7, 1)).taux, 6);
    });

    test('une date de fin ÉCRITE sur une version (fiche héritée) est honorée : au-delà, refus nommé', () {
      final fermee = [v('F1', sans, 5, effet: '2026-09-07', dateArret: '2026-09-07', decideur: 'Direction', fin: '2026-12-31')];
      expect(cpdTauxAibALaDate(fermee, sans, DateTime(2026, 12, 31)).taux, 5);
      final r = cpdTauxAibALaDate(fermee, sans, DateTime(2027, 1, 1));
      expect(r.taux, isNull);
      expect(r.code, cpdCodeAibSansBareme);
    });

    test('un taux NON ARRÊTÉ ne s\'applique jamais : taux nul, motif qui nomme ce qui attend la Direction', () {
      final r = cpdTauxAibALaDate(bareme, 'ifu_actif', DateTime(2026, 10, 1), situations: situations);
      expect(r.taux, isNull);
      expect(r.enAttente, hasLength(1));
      expect(r.motif, contains('1 %'));
      expect(r.motif, contains('n\'est pas arrêté'));
    });

    test('une version ARCHIVÉE est ignorée : le taux précédent reprend (RG-14, la version n\'est pas supprimée)', () {
      final archive = [for (final f in bareme) f['id'] == 'B4' ? {...f, 'statut': 'archive'} : f];
      expect(cpdTauxAibALaDate(archive, sans, DateTime(2027, 3, 1)).taux, 5);
      expect(cpdFinDeVersion(archive, archive[0]), isNull, reason: 'la précédente est « rouverte » d\'elle-même : sa fin est calculée, jamais stockée');
    });

    test('une situation inconnue ou archivée : refus nommé AIB_SANS_BAREME (jamais zéro) ; sans la liste des situations, aucune version au barème', () {
      final inconnue = cpdTauxAibALaDate(bareme, 'situation_inconnue', DateTime(2026, 10, 1), situations: situations);
      expect(inconnue.taux, isNull);
      expect(inconnue.code, cpdCodeAibSansBareme);
      expect(inconnue.motif, contains('n\'est pas active'));
      final archivee = cpdTauxAibALaDate(bareme, sans, DateTime(2026, 10, 1),
          situations: [for (final x in situations) x['code'] == sans ? {...x, 'statut': 'archive'} : x]);
      expect(archivee.taux, isNull);
      expect(archivee.code, cpdCodeAibSansBareme);
      expect(cpdTauxAibALaDate(bareme, 'AIB-9', DateTime(2026, 10, 1)).motif, contains('Aucune version'));
    });

    test('le barème du jour : une ligne par situation active (dans l\'ordre déclaré), le taux appliqué se lit en chiffres', () {
      final b = cpdBaremeEnVigueur(situations, bareme, DateTime(2026, 11, 9));
      expect([for (final x in b) x.code], ['ifu_actif', 'ifu_inactif_ou_absent', 'prestation_service']);
      expect([for (final x in b) x.reponse.taux], [null, 5, null]);
      expect(b[1].libelle, 'Acheteur sans IFU actif');
    });

    test('le montant retenu : 1 250 000 F à 5 % = 62 500 F ; 333 F à 5 % = 17 F (arrondi au franc)', () {
      expect(cpdMontantAib(1250000, 5), 62500);
      expect(cpdMontantAib(333, 5), 17);
    });
  });

  group('la situation d\'un acheteur, choisie d\'office d\'après son IFU', () {
    test('13 chiffres (espaces tolérés) : « IFU actif », PRÉSUMÉ actif et le dit ; sans IFU : « sans IFU actif », aucune présomption', () {
      final a = cpdSituationPourAcheteur(situations, ifu: '3201 6427 48214');
      expect(a.situation!['code'], 'ifu_actif');
      expect(a.presomption, isTrue);
      expect(a.avertissement, contains('présumé'));
      final b = cpdSituationPourAcheteur(situations, ifu: '');
      expect(b.situation!['code'], 'ifu_inactif_ou_absent');
      expect(b.presomption, isFalse);
      expect(b.avertissement, isNull);
    });

    test('un IFU mal formé est refusé (IFU_INVALIDE) ; sans situation au déclencheur, refus nommé AIB_SANS_BAREME', () {
      expect(cpdSituationPourAcheteur(situations, ifu: '12AB').refusCode, 'IFU_INVALIDE');
      final sansDeclencheur = cpdSituationPourAcheteur([situations[2]], ifu: '');
      expect(sansDeclencheur.ok, isFalse);
      expect(sansDeclencheur.refusCode, cpdCodeAibSansBareme);
    });
  });

  group('le contrôle d\'une saisie', () {
    final auj = DateTime(2026, 11, 9);
    Map<String, Object?> saisie(
            {String situation = sans,
            Object taux = '5',
            String effet = '2027-06-01',
            String statutArret = cpdStatutArrete,
            String dateArret = '2026-11-09',
            String decideur = 'Direction',
            String source = 'Décision de la Direction',
            String motif = 'Correction'}) =>
        {
          'situation': situation,
          'taux': taux,
          'dateEffet': effet,
          'statutArret': statutArret,
          'dateArret': dateArret,
          'decideurArret': decideur,
          'source': source,
          'motif': motif
        };
    String? controle(Map<String, Object?> x, [CpdFiche? record]) => cpdControlerVersionAib(x, record, bareme, auj, situations: situations);

    test('une saisie complète est acceptée', () => expect(controle(saisie()), isNull));

    test('un taux hors de 0 à 100 %, décimal ou illisible est refusé (AIB_TAUX_INVALIDE) : le poste calcule en montants entiers', () {
      expect(controle(saisie(taux: '120')), contains('AIB_TAUX_INVALIDE'));
      expect(controle(saisie(taux: 'x')), contains('AIB_TAUX_INVALIDE'));
      expect(controle(saisie(taux: '7.5')), contains('AIB_TAUX_INVALIDE'));
    });

    test('source absente, motif absent, situation inconnue : refus nommés', () {
      expect(controle(saisie(source: '  ')), contains('AIB_SOURCE_ABSENTE'));
      expect(controle(saisie(motif: '')), contains('AIB_MOTIF_ABSENT'));
      expect(controle(saisie(situation: 'nexiste_pas')), contains('AIB_SITUATION_INCONNUE'));
    });

    test('une version arrêtée exige date d\'effet, date d\'arrêt et décideur ; une non arrêtée n\'exige aucune des trois', () {
      expect(controle(saisie(effet: '')), contains('date d\'effet'));
      expect(controle(saisie(dateArret: '')), contains('date de l\'arrêt'));
      expect(controle(saisie(decideur: ' ')), contains('décideur'));
      expect(controle(saisie(statutArret: cpdStatutNonArrete, effet: '', dateArret: '', decideur: '')), isNull);
    });

    test('deux versions d\'une même situation ne partagent pas la même date d\'effet (AIB_DATE_EXISTANTE)', () {
      expect(controle(saisie(effet: '2026-09-07')), contains('AIB_DATE_EXISTANTE'));
      expect(controle(saisie(effet: '2026-09-07')), contains('07/09/2026'));
      // la même date sur une AUTRE situation est permise
      expect(controle(saisie(situation: 'prestation_service', taux: '3', effet: '2026-09-07')), isNull);
    });

    test('une version arrêtée ne s\'insère pas avant la plus récente arrêtée de sa situation (AIB_DATE_ANTERIEURE)', () {
      expect(controle(saisie(effet: '2026-06-01')), contains('AIB_DATE_ANTERIEURE'));
      expect(controle(saisie(situation: 'ifu_actif', taux: '1', effet: '2026-06-01')), isNull, reason: 'aucune version arrêtée pour cette situation : rien à masquer');
    });

    test('une version ARRÊTÉE ne se corrige pas sur place (AIB_VERSION_FIGEE) : on ajoute une version ; son motif seul s\'édite', () {
      final b1 = bareme.first;
      final corrige = saisie(taux: '6', effet: '2026-09-07', dateArret: '2026-09-07');
      expect(controle(corrige, b1), contains('AIB_VERSION_FIGEE'));
      expect(controle(corrige, b1), contains('ajouter une nouvelle version'));
      final memeChose = {...saisie(taux: '5', effet: '2026-09-07', dateArret: '2026-09-07'), 'motif': 'précision de rédaction'};
      expect(controle(memeChose, b1), isNull);
    });

    test('une version NON arrêtée se corrige librement, et l\'arrêt la fait entrer en vigueur', () {
      final b2 = bareme[1];
      final arretee = saisie(situation: 'ifu_actif', taux: '1', effet: '2026-11-10', dateArret: '2026-11-09');
      expect(controle(arretee, b2), isNull);
    });
  });
}
