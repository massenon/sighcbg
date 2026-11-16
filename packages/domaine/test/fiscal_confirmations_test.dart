// FISCAL (Direction de Baguidi, compléments du 16/11/2026, section 7) : « Confirmer » la CNSS et le barème de l'AIB (motif obligatoire, tracé, geste réservé, rien d'écrasé) ;
// DEUX barèmes de l'AIB en paramètres (retenue sur la facture d'un tiers ; barème par situation de l'acheteur), choisis par le comptable à chaque opération.
import 'dart:convert';
import 'dart:io';

import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef F = Map<String, Object?>;

List<F> _jeu(String nom) => [for (final x in jsonDecode(File('../../apps/poste/assets/donnees/jeu/$nom.json').readAsStringSync()) as List) (x as Map).cast<String, Object?>()];

void main() {
  final maintenant = DateTime.utc(2026, 11, 16, 10);

  group('confirmer la CNSS', () {
    ({FcoRefus? refus, F? fiche}) confirmer({String role = 'comptable', String? motif = 'Notification de la CNSS du 02/11/2026', Object? effet = '2026-11-16', List<F> existantes = const [], DroitsGestes? gestes, bool fileul = false}) =>
        fcoConfirmer(
            objet: fcoObjetCnss,
            cible: fcoCibleCnssTaux,
            libelle: 'CNSS',
            valeur: fcoValeursCnss(),
            dateEffet: effet,
            motif: motif,
            role: role,
            auteur: 'Agent comptable',
            maintenant: maintenant,
            existantes: existantes,
            gestes: gestes,
            fileul: fileul);

    test('ce qui existe : la part ouvrière 3,6 %, la part patronale 16,4 %, AUCUN plafond (aucun chiffre inventé)', () {
      expect(fcoValeursCnss(), {'tauxOuvrier': 3.6, 'tauxPatronal': 16.4, 'plafond': null});
      expect(fcoLibelleCnss(fcoValeursCnss()), 'part ouvrière 3,6 %, part patronale 16,4 %, aucun plafond');
    });

    test('la confirmation est TRACÉE : auteur, rôle, horodatage, motif, date d’effet et valeur recopiée', () {
      final r = confirmer();
      expect(r.refus, isNull);
      final f = r.fiche!;
      expect(f['objet'], fcoObjetCnss);
      expect(f['confirmePar'], 'Agent comptable');
      expect(f['confirmeRole'], 'comptable');
      expect(f['confirmeLe'], '2026-11-16T10:00:00.000Z');
      expect(f['motif'], 'Notification de la CNSS du 02/11/2026');
      expect(f['dateEffet'], '2026-11-16');
      expect(f['valeur'], fcoValeursCnss());
    });

    test('refus nommés : motif absent, date absente, geste non détenu, fileul', () {
      expect(confirmer(motif: '  ').refus?.code, 'MOTIF_OBLIGATOIRE');
      expect(confirmer(effet: null).refus?.code, 'DATE_EFFET_REQUISE');
      expect(confirmer(role: 'caissier').refus?.code, 'CONFIRMATION_RESERVEE');
      expect(confirmer(role: 'direction').refus?.code, 'CONFIRMATION_RESERVEE', reason: 'origine proposée : le comptable et la DAF seulement');
      expect(confirmer(role: 'da').refus, isNull);
      expect(confirmer(fileul: true).refus?.code, 'FILEUL_LECTURE_SEULE');
    });

    test('le geste est celui de la MATRICE : une fiche l’accorde à la Direction, le retire au comptable', () {
      F fiche(String role, bool v) => {'id': 'R-$role', 'role': role, 'statut': 'actif', 'droitsGestes': {gesteFiscalConfirmer: v}};
      expect(confirmer(role: 'direction', gestes: DroitsGestes(fiches: [fiche('direction', true)])).refus, isNull);
      expect(confirmer(gestes: DroitsGestes(fiches: [fiche('comptable', false)])).refus?.code, 'CONFIRMATION_RESERVEE');
    });

    test('RIEN N’EST ÉCRASÉ : même date refusée, date antérieure refusée, une date postérieure s’ajoute ; la confirmation en vigueur se lit À UNE DATE', () {
      final premiere = confirmer().fiche!;
      expect(confirmer(existantes: [premiere]).refus?.code, 'CONFIRMATION_EXISTANTE');
      expect(confirmer(existantes: [premiere], effet: '2026-10-01').refus?.code, 'DATE_EFFET_ANTERIEURE');
      final seconde = confirmer(existantes: [premiere], effet: '2027-01-01', motif: 'Revue annuelle').fiche!;
      final toutes = [premiere, seconde];
      expect(fcoHistorique(toutes, fcoObjetCnss, fcoCibleCnssTaux).map((f) => f['dateEffet']), ['2026-11-16', '2027-01-01']);
      expect(fcoConfirmationALaDate(toutes, fcoObjetCnss, fcoCibleCnssTaux, DateTime(2026, 11, 1)), isNull);
      expect(fcoConfirmationALaDate(toutes, fcoObjetCnss, fcoCibleCnssTaux, DateTime(2026, 12, 1))?['motif'], 'Notification de la CNSS du 02/11/2026');
      expect(fcoConfirmationALaDate(toutes, fcoObjetCnss, fcoCibleCnssTaux, DateTime(2027, 2, 1))?['motif'], 'Revue annuelle');
    });
  });

  group('confirmer une version du barème de l’AIB', () {
    final situations = _jeu('situationsAib');
    final versions = _jeu('baremeAib');

    test('une version NON ARRÊTÉE : la confirmation l’ARRÊTE à la date d’effet choisie (décidée par l’auteur, aujourd’hui) ; la valeur ne change pas', () {
      final v = versions.firstWhere((x) => x['id'] == 'BAI04');
      final r = fcoConfirmerVersionAib(
          version: v, versions: versions, situations: situations, dateEffet: '2026-12-01', motif: 'Texte reçu', role: 'comptable', auteur: 'Agent', maintenant: maintenant, existantes: const []);
      expect(r.refus, isNull);
      expect(r.arret, containsPair('statutArret', cpdStatutArrete));
      expect(r.arret!['dateEffet'], '2026-12-01');
      expect(r.arret!['decideurArret'], 'Agent');
      expect(r.arret!.containsKey('taux'), isFalse, reason: 'le taux n’est jamais réécrit');
      expect(r.fiche!['valeur'], containsPair('bareme', cpdBaremeRetenueTiers));
      expect(r.fiche!['valeur'], containsPair('taux', 3));
    });

    test('une version ARRÊTÉE garde SA date d’effet : la confirmation s’ajoute, rien n’est arrêté de nouveau', () {
      final v = versions.firstWhere((x) => x['id'] == 'BAI01');
      final r = fcoConfirmerVersionAib(
          version: v, versions: versions, situations: situations, dateEffet: '2027-05-05', motif: 'Revue', role: 'da', auteur: 'DAF', maintenant: maintenant, existantes: const []);
      expect(r.refus, isNull);
      expect(r.arret, isNull);
      expect(r.fiche!['dateEffet'], '2026-09-07');
    });

    test('refus nommés : motif, geste ; une confirmation ne se rejoue pas à la même date', () {
      final v = versions.firstWhere((x) => x['id'] == 'BAI01');
      expect(fcoConfirmerVersionAib(version: v, versions: versions, situations: situations, dateEffet: null, motif: '', role: 'comptable', auteur: 'A', maintenant: maintenant, existantes: const [])
          .refus
          ?.code, 'MOTIF_OBLIGATOIRE');
      expect(fcoConfirmerVersionAib(version: v, versions: versions, situations: situations, dateEffet: null, motif: 'm', role: 'caissier', auteur: 'A', maintenant: maintenant, existantes: const [])
          .refus
          ?.code, 'CONFIRMATION_RESERVEE');
      final f = fcoConfirmerVersionAib(version: v, versions: versions, situations: situations, dateEffet: null, motif: 'm', role: 'comptable', auteur: 'A', maintenant: maintenant, existantes: const []).fiche!;
      expect(fcoConfirmerVersionAib(version: v, versions: versions, situations: situations, dateEffet: null, motif: 'm', role: 'comptable', auteur: 'A', maintenant: maintenant, existantes: [f])
          .refus
          ?.code, 'CONFIRMATION_EXISTANTE');
    });
  });

  group('deux barèmes de l’AIB, choisis à chaque opération', () {
    final situations = _jeu('situationsAib');
    final versions = _jeu('baremeAib');

    test('les valeurs SEMÉES : retenue sur la facture d’un tiers 3 % (personne physique) et 5 % (personne morale), barème par situation 1 % / 5 % / 3 % ; celles qui ne viennent que de la décision sont « à valider »', () {
      String bar(String code) => cpdBaremeDeSituation(situations.firstWhere((s) => s['code'] == code));
      num taux(String sit) => versions.firstWhere((v) => v['situation'] == sit)['taux'] as num;
      expect(bar('tiers_personne_physique'), cpdBaremeRetenueTiers);
      expect(bar('tiers_personne_morale'), cpdBaremeRetenueTiers);
      expect(taux('tiers_personne_physique'), 3);
      expect(taux('tiers_personne_morale'), 5);
      for (final s in ['ifu_actif', 'ifu_inactif_ou_absent', 'prestation_service']) {
        expect(bar(s), cpdBaremeSituationAcheteur, reason: s);
      }
      expect([taux('ifu_actif'), taux('ifu_inactif_ou_absent'), taux('prestation_service')], [1, 5, 3]);
      for (final id in ['BAI04', 'BAI05']) {
        final v = versions.firstWhere((x) => x['id'] == id);
        expect(v['aValider'], isTrue, reason: id);
        expect(cpdEstArretee(v), isFalse, reason: '$id : un taux qui ne vient que de la décision ne s’applique qu’une fois confirmé');
      }
      expect(cpdBaremeDeSituation(const {'code': 'ancienne'}), cpdBaremeSituationAcheteur, reason: 'une situation sans barème garde son sens d’avant');
    });

    test('le CHOIX DU BARÈME est obligatoire et la catégorie doit lui appartenir — aucun défaut silencieux', () {
      expect(cpdRefusChoixBareme('', 'tiers_personne_morale', situations), startsWith('AIB_BAREME_REQUIS'));
      expect(cpdRefusChoixBareme(null, 'tiers_personne_morale', situations), startsWith('AIB_BAREME_REQUIS'));
      expect(cpdRefusChoixBareme('inconnu', 'tiers_personne_morale', situations), startsWith('AIB_BAREME_INCONNU'));
      expect(cpdRefusChoixBareme(cpdBaremeRetenueTiers, '', situations), startsWith('AIB_SITUATION_INCONNUE'));
      expect(cpdRefusChoixBareme(cpdBaremeRetenueTiers, 'ifu_actif', situations), startsWith('AIB_SITUATION_HORS_BAREME'));
      expect(cpdRefusChoixBareme(cpdBaremeRetenueTiers, 'tiers_personne_morale', situations), isNull);
      expect(cpdRefusChoixBareme(cpdBaremeSituationAcheteur, 'ifu_inactif_ou_absent', situations), isNull);
    });

    test('la pièce PORTE le barème choisi et le taux appliqué ; un barème incohérent est refusé au moteur', () {
      final arretees = [
        ...versions,
        {'id': 'T1', 'statut': 'actif', 'situation': 'tiers_personne_morale', 'taux': 5, 'statutArret': 'arrete', 'arrete': true, 'dateEffet': '2026-11-01', 'dateArret': '2026-11-16', 'decideurArret': 'DAF', 'source': 's', 'motif': 'm'},
      ];
      final r = cpdCalculerRetenueAib(arretees, 'tiers_personne_morale', 100000, DateTime(2026, 11, 20), situations: situations, baremeChoisi: cpdBaremeRetenueTiers);
      expect(r.montant, 5000);
      expect(r.versFiche(), containsPair('bareme', cpdBaremeRetenueTiers));
      expect(r.versFiche(), containsPair('baremeLibelle', 'Retenue sur la facture d’un tiers'));
      expect(r.versFiche(), containsPair('taux', 5));
      expect(() => cpdCalculerRetenueAib(arretees, 'tiers_personne_morale', 1000, DateTime(2026, 11, 20), situations: situations, baremeChoisi: cpdBaremeSituationAcheteur),
          throwsA(isA<RefusRetenueAib>().having((e) => e.motif, 'motif', startsWith('AIB_SITUATION_HORS_BAREME'))));
    });

    test('le barème en vigueur se filtre par barème ; le choix d’office d’après l’IFU ne présume jamais une catégorie de retenue sur un tiers', () {
      final d = DateTime(2026, 11, 20);
      expect(cpdBaremeEnVigueur(situations, versions, d, bareme: cpdBaremeRetenueTiers).map((b) => b.code), ['tiers_personne_physique', 'tiers_personne_morale']);
      expect(cpdBaremeEnVigueur(situations, versions, d, bareme: cpdBaremeSituationAcheteur).map((b) => b.code), ['ifu_actif', 'ifu_inactif_ou_absent', 'prestation_service']);
      expect(cpdBaremeEnVigueur(situations, versions, d).length, 5);
      expect(cpdSituationPourAcheteur(situations).situation?['code'], 'ifu_inactif_ou_absent');
      expect(cpdSituationPourAcheteur(situations, ifu: '1234567890123').situation?['code'], 'ifu_actif');
      final piege = [...situations, {'id': 'X', 'statut': 'actif', 'code': 'tiers_x', 'bareme': cpdBaremeRetenueTiers, 'declencheur': 'ifu_absent', 'ordre': 0}];
      expect(cpdSituationPourAcheteur(piege).situation?['code'], 'ifu_inactif_ou_absent', reason: 'une catégorie de retenue sur un tiers ne se choisit jamais d’office');
    });
  });
}
