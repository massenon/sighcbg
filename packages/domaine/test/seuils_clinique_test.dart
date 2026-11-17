// LE LOT « SEUILS » de l'inventaire des valeurs en dur (17/11/2026) : les seuils, délais et fenêtres qui vivaient en littéraux sont des paramètres de clinique datés.
// On prouve : (1) chaque seuil est déclaré avec des bornes qui contiennent sa valeur d'attente ; (2) la lecture retombe sur cette valeur d'attente, jamais sur zéro ;
// (3) une version datée change la valeur à partir de sa date seulement ; (4) les règles pures qui lisaient un littéral le REÇOIVENT désormais.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

Map<String, Object?> version(String cle, Object? valeur, String effet, {int v = 1}) {
  final d = definitionDeParametre(cle)!;
  return Parametre(
          cle: cle, famille: d.famille, type: d.type, valeur: valeur, defaut: d.defaut, dateEffet: effet, version: v, auteur: 'Test', motif: 'essai', creeLe: '2026-11-17T08:00:00.000')
      .toJson();
}

void main() {
  const seuils = [
    'securite.delaiVerrouOrdinaireMinutes',
    'securite.renouvellementMotDePasseJours',
    'securite.dureeVerrouCompteMinutes',
    'securite.dureeBlocageSecoursMinutes',
    'securite.validiteMotDePasseTemporaireHeures',
    'stock.delaiEcheanceUrgenteJours',
    'comptabilite.periodeBfrJours',
    'qualite.dureeLienEnqueteJours',
    'hospitalisation.joursSortiePrevue',
    'caisse.pasEcheancierReliquatJours',
    'caisse.delaiEngagementPaiementJours',
    'assurances.fenetreHistoriqueJours',
    'mere.fenetreJournalAlterationsJours',
    'mere.validiteCodeAppairageMinutes',
    'comptabilite.tailleMaxDepotFiscalKo',
    'notifications.seuilRegroupement',
    'notifications.temporisationSon',
    'achats.fenetreCircuitJours',
    'validations.delaiPieceAbsenteMinutes',
    'administration.delaiUrgentEvenementJours',
    'administration.joursVerificationRepertoireJours',
    'fiscal.echeancesProchesJours',
    'laboratoire.delaiEntreDonsSangJours',
    'rh.validiteBadgeMois',
    'rh.alerteExpirationBadgeJours',
    'specialites.preavisVisiteMedecineTravailJours',
    'assistant.horizonQuestionJours',
    'consultation.ecartRecentrageAgendaJours',
    'stock.seuilAlerteImportPourcent',
    'stock.seuilAlerteImportMinimum',
  ];

  group('déclaration', () {
    test('chaque seuil est un entier borné dont la valeur d\'attente est dans les bornes, avec une source (« à valider »)', () {
      for (final k in seuils) {
        final d = definitionDeParametre(k);
        expect(d, isNotNull, reason: k);
        expect(d!.type, TypeParametre.entier, reason: k);
        expect(d.min, isNotNull, reason: k);
        expect(d.max, isNotNull, reason: k);
        final v = d.defaut as int;
        expect(v >= d.min! && v <= d.max!, isTrue, reason: '$k : ${d.min} ≤ $v ≤ ${d.max}');
        expect(d.source, isNotNull, reason: k);
        expect(d.mobile, isFalse, reason: '$k : jamais vers un téléphone');
        expect(libellesFamillesParametres.containsKey(d.famille), isTrue, reason: '${d.famille} : famille sans libellé');
      }
    });
  });

  group('lecture', () {
    test('sans fiche : la valeur d\'attente ; hors bornes ou illisible : la valeur d\'attente, jamais zéro', () {
      for (final k in seuils) {
        final d = definitionDeParametre(k)!;
        expect(seuilEntierA(const [], k, '2026-11-17'), d.defaut, reason: k);
        expect(seuilEntierDe(k, d.max! + 1), d.defaut, reason: '$k au-dessus');
        expect(seuilEntierDe(k, d.min! - 1), d.defaut, reason: '$k en dessous');
        expect(seuilEntierDe(k, 'abc'), d.defaut, reason: '$k illisible');
        expect(seuilEntierDe(k, null), d.defaut, reason: '$k nul');
        expect(seuilEntierDe(k, 2.5), d.defaut, reason: '$k décimal');
      }
    });

    test('une version datée s\'applique à partir de sa date, pas avant', () {
      const k = 'achats.fenetreCircuitJours';
      final f = [version(k, 14, '2026-12-01')];
      expect(seuilEntierA(f, k, '2026-11-30'), seuilSeme(k));
      expect(seuilEntierA(f, k, '2026-12-01'), 14);
    });

    test('une version archivée est ignorée (RG-14)', () {
      const k = 'achats.fenetreCircuitJours';
      final f = [
        {...version(k, 14, '2026-01-01'), 'statut': 'archive'}
      ];
      expect(seuilEntierA(f, k, '2026-11-17'), seuilSeme(k));
    });

    test('une clé inconnue est une faute de programmation, pas un zéro silencieux', () {
      expect(() => seuilSeme('inconnu.cle'), throwsArgumentError);
    });
  });

  group('les règles reçoivent le seuil', () {
    test('sécurité : la durée de verrou, de blocage et de validité se passent en argument ; la valeur d\'attente s\'applique sinon', () {
      final t0 = DateTime(2026, 11, 17, 10);
      final f = <String, Object?>{'echecs': 2};
      final defaut = accApresEchec(f, t0);
      expect(defaut.verrouille, isTrue);
      expect(DateTime.parse('${defaut.patch['verrouJusqua']}'), t0.add(Duration(minutes: seuilSeme(cleDureeVerrouCompte))));
      final long = accApresEchec(f, t0, dureeVerrou: const Duration(minutes: 45));
      expect(DateTime.parse('${long.patch['verrouJusqua']}'), t0.add(const Duration(minutes: 45)));
      expect(accEcheanceTemporaire(t0, validite: const Duration(hours: 2)), t0.add(const Duration(hours: 2)));
      expect(accEcheanceTemporaire(t0), t0.add(Duration(hours: seuilSeme(cleValiditeMotDePasseTemporaire))));
      final etat = <String, Object?>{'essais': accEssaisSecoursAvantBlocage - 1};
      expect(DateTime.parse('${accSecoursApresEchec(etat, t0, dureeBlocage: const Duration(minutes: 7)).patch['bloqueJusqua']}'), t0.add(const Duration(minutes: 7)));
      expect(AccVerrou().delai, Duration(minutes: seuilSeme(cleDelaiVerrouOrdinaire)));
      expect(AccVerrou(delai: const Duration(minutes: 3)).delai, const Duration(minutes: 3));
    });

    test('verrou de poste : la politique de sécurité l\'emporte, puis le réglage, puis la valeur d\'attente', () {
      expect(delaiVerrouOrdinaireMinutes(20, reglage: 40), 20);
      expect(delaiVerrouOrdinaireMinutes(null, reglage: 40), 40);
      expect(delaiVerrouOrdinaireMinutes(null), seuilSeme(cleDelaiVerrouOrdinaire));
      expect(delaiVerrouOrdinaireMinutes(null, reglage: 9999), seuilSeme(cleDelaiVerrouOrdinaire));
    });

    test('stock : l\'échéance urgente et le préavis se passent à la teinte ; sans argument, les valeurs d\'attente', () {
      expect(teinteEcheance(25), 'danger');
      expect(teinteEcheance(25, urgent: 10), 'attention');
      expect(teinteEcheance(80, preavis: 60), 'neutre');
      expect(statutLot(80), 'alerte');
      expect(statutLot(80, preavis: 60), 'actif');
    });

    test('répertoire d\'urgence : le numéro non vérifié depuis plus de N jours est signalé, N vient du paramètre', () {
      final r = {'verifieLe': '2026-09-01'};
      final auj = DateTime(2026, 11, 17);
      expect(admPerime(r, auj), isFalse);
      expect(admPerime(r, auj, joursVerification: 30), isTrue);
      expect(admDelaiUrgent(5), isTrue);
      expect(admDelaiUrgent(5, urgentJours: 3), isFalse);
    });

    test('banque de sang : le délai entre deux dons vient du paramètre', () {
      final d = {'eligible': true, 'dernierDon': '2026-09-01'};
      final auj = DateTime(2026, 11, 17); // 77 jours
      expect(sangEligibilite(auj, d).libelle, startsWith('Délai'));
      expect(sangEligibilite(auj, d, delaiEntreDons: 60).libelle, 'Éligible');
      expect(sangDonneurDisponible(auj, d, delaiEntreDons: 60), isTrue);
    });

    test('badges : durée de validité et alerte avant expiration viennent des paramètres', () {
      expect(rhcExpirationDepuis('2026-01-15', dureeMois: 12), '2027-01-15');
      expect(rhcExpirationDepuis('2026-01-15'), '2028-01-15');
      final auj = DateTime(2026, 11, 17);
      final b = [
        {'expireLe': '2027-02-10'}
      ];
      expect(rhcBadgesExpirant(b, auj), isEmpty);
      expect(rhcBadgesExpirant(b, auj, alerteJours: 90), hasLength(1));
    });

    test('BFR : la fenêtre d\'observation par défaut vient du paramètre', () {
      final f = cpcFenetre(auj: DateTime(2026, 11, 17));
      expect(f.jours, seuilSeme('comptabilite.periodeBfrJours'));
      expect(cpcFenetre(auj: DateTime(2026, 11, 17), jours: 30).jours, 30);
    });

    test('import du stock : le lot importé est « alerte » dans le préavis EN VIGUEUR à la date de l\'import', () {
      final p = PortImportMemoire({
        'parametres': [version('stock.delaiPreavisPeremptionJours', 30, '2026-01-01')],
      }, jourFixe: '2026-11-12');
      expect(delaiPreavisPeremptionA(p.toutes('parametres'), p.jour), 30);
      expect(delaiPreavisPeremptionA(const [], p.jour), seuilSeme('stock.delaiPreavisPeremptionJours'));
    });

    test('échéances fiscales : les seuils sans argument sont les défauts des deux paramètres', () {
      final s = CpcSeuilsEcheance.defaut;
      expect(s.aPayerJours, seuilSeme('fiscal.delaiAPayerJours'));
      expect(s.declarationJours, seuilSeme('fiscal.delaiDeclarationJours'));
    });
  });
}
