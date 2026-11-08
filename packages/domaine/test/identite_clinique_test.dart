// L'IDENTITÉ LÉGALE IMPRIMÉE (réplique Baguidi, PRD §4) : valeurs initiales, surcharge enregistrée (écart E841 levé) et mention vide jamais imprimée.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  tearDown(IdentiteClinique.reinitialiser);

  group('valeurs initiales : la fiche d’identité de la Clinique Baguidi (06/11/2026)', () {
    test('dénomination, sigle, devise, coordonnées, IFU, RCCM', () {
      expect(IdentiteClinique.sigle, 'CBG');
      expect(IdentiteClinique.nom, 'CLINIQUE BAGUIDI « L’AS DU CŒUR »');
      expect(IdentiteClinique.nomCourt, 'CLINIQUE BAGUIDI');
      expect(IdentiteClinique.slogan, 'Votre bien-être est notre raison d’être.');
      expect(IdentiteClinique.adresse, 'Quartier Zongo II, Parakou');
      expect(IdentiteClinique.ville, 'Parakou');
      expect(IdentiteClinique.localisation, 'Parakou, République du Bénin');
      expect(IdentiteClinique.activite, 'CENTRE DE MÉDECINE DU TRAVAIL, MÉDECINE GÉNÉRALE');
      expect(IdentiteClinique.bp, '02 BP : 105 PARAKOU (Rép. du Bénin)');
      expect(IdentiteClinique.telephones, ['95 74 69 56', '95 95 99 14', '97 09 34 99']);
      expect(IdentiteClinique.email, 'cliniquebaguidi@yahoo.fr');
      expect(IdentiteClinique.ifu, '3201001996110');
      expect(IdentiteClinique.rccm, 'RB/PKO/17 A 4240');
      expect(IdentiteClinique.formuleArrete, 'Arrêtée la présente facture à la somme de');
      expect(IdentiteClinique.logiciel, 'SIGH-CBG');
      expect(IdentiteClinique.editeDepuis, 'Édité depuis le SIGH-CBG');
      expect(IdentiteClinique.prefixeFichier, 'sigh-cbg');
    });

    test('forme juridique, autorisation d’ouverture et formule de politesse : VIDES (non renseignées par la Direction)', () {
      expect(IdentiteClinique.forme, '');
      expect(IdentiteClinique.autorisation, '');
      expect(IdentiteClinique.formulePolitesse, 'Votre bien-être est notre raison d’être.');
      expect(IdentiteClinique.rccmDate, '19/03/2009');
      expect(IdentiteClinique.ifuDate, '26 novembre 2010');
      expect(IdentiteImprimee.semence.fiche['ifuDate'], '26 novembre 2010');
      expect(IdentiteClinique.enregistrement, '0416/ONMB/ATL/2002');
      expect(IdentiteClinique.ligneEnregistrement, 'N° D’ENREGISTREMENT 0416/ONMB/ATL/2002');
    });

    test('la mention légale est DÉRIVÉE de la dénomination, de l’IFU et du RCCM', () {
      expect(IdentiteClinique.mentionLegale,
          'CLINIQUE BAGUIDI « L’AS DU CŒUR » — IFU 3201001996110 — RCCM RB/PKO/17 A 4240.');
    });

    test('aucune trace de l’identité de Nassiera Too', () {
      final tout = [
        for (final k in IdentiteClinique.champs) k == 'telephones' ? IdentiteClinique.telephones.join(' ') : '${IdentiteClinique.defauts[k]}',
        IdentiteClinique.mentionLegale,
        ...IdentiteClinique.lignesEnTete,
      ].join(' ');
      for (final interdit in ['NASSIERA', 'Natitingou', 'NATITINGOU', '3201642748214', 'RB/NAT', 'raison de vivre', 'cliniquenassiera', 'DIEU', 'CN' 'T']) {
        expect(tout.contains(interdit), isFalse, reason: interdit);
      }
    });
  });

  group('surcharge : l’identité ENREGISTRÉE l’emporte sur l’identité initiale', () {
    test('une valeur saisie est reprise ; une clé absente garde la valeur initiale', () {
      IdentiteClinique.appliquer({'forme': 'SARL', 'autorisation': 'N° 012/MS/DNSP/2009', 'formulePolitesse': 'MERCI DE VOTRE CONFIANCE'});
      expect(IdentiteClinique.forme, 'SARL');
      expect(IdentiteClinique.autorisation, 'N° 012/MS/DNSP/2009');
      expect(IdentiteClinique.formulePolitesse, 'MERCI DE VOTRE CONFIANCE');
      expect(IdentiteClinique.ifu, '3201001996110', reason: 'non surchargé');
      expect(IdentiteClinique.ligneAutorisation, 'AUTORISATION D’OUVERTURE N° 012/MS/DNSP/2009');
      expect(IdentiteClinique.lignesEnTete, contains('AUTORISATION D’OUVERTURE N° 012/MS/DNSP/2009'));
    });

    test('les téléphones saisis en une ligne deviennent une liste ; les espaces de bord tombent', () {
      IdentiteClinique.appliquer({'telephones': ' 95 74 69 56 / 97 09 34 99 /', 'nom': '  CLINIQUE TEST  '});
      expect(IdentiteClinique.telephones, ['95 74 69 56', '97 09 34 99']);
      expect(IdentiteClinique.nom, 'CLINIQUE TEST');
      expect(IdentiteClinique.mentionLegale, startsWith('CLINIQUE TEST — IFU '));
    });

    test('le sigle surchargé préfixe les codes, les pièces et le nom du logiciel', () {
      IdentiteClinique.appliquer({'sigle': 'XYZ'});
      expect(codePatient(12, 2026), 'XYZ/12/26');
      expect(IdentiteClinique.logiciel, 'SIGH-XYZ');
      expect(IdentiteClinique.prefixeFichier, 'sigh-xyz');
    });

    test('réinitialiser (ou appliquer une fiche vide) rend l’identité initiale', () {
      IdentiteClinique.appliquer({'ifu': '1'});
      expect(IdentiteClinique.ifu, '1');
      IdentiteClinique.appliquer(null);
      expect(IdentiteClinique.ifu, '3201001996110');
      IdentiteClinique.appliquer({'ifu': '1'});
      IdentiteClinique.reinitialiser();
      expect(IdentiteClinique.surcharge, isEmpty);
    });
  });

  group('une mention VIDE n’est pas imprimée : ni ligne, ni libellé orphelin', () {
    test('en-tête : pas de ligne « AUTORISATION D’OUVERTURE » sans numéro', () {
      expect(IdentiteClinique.ligneAutorisation, '');
      expect(IdentiteClinique.lignesEnTete.any((l) => l.contains('AUTORISATION')), isFalse);
      expect(IdentiteClinique.lignesEnTete.any((l) => l.trim().isEmpty), isFalse);
    });

    test('IFU, RCCM, courriel, BP et téléphones vidés : ni « IFU : », ni « RCCM », ni « E-mail : », ni « TÉL. : »', () {
      IdentiteClinique.appliquer({'ifu': '', 'rccm': '', 'email': '', 'bp': '', 'telephones': '', 'enregistrement': ''});
      expect(IdentiteClinique.ligneFiscale, '');
      expect(IdentiteClinique.ligneEmail, '');
      expect(IdentiteClinique.ligneCoordonnees, '');
      expect(IdentiteClinique.lignesEnTete, [IdentiteClinique.slogan]);
      expect(IdentiteClinique.mentionLegale, '${IdentiteClinique.nom}.');
      expect(IdentiteClinique.piedLegal, IdentiteClinique.nom);
    });

    test('une seule des deux mentions fiscales : l’autre n’a pas de libellé', () {
      IdentiteClinique.appliquer({'rccm': ''});
      expect(IdentiteClinique.ligneFiscale, 'IFU : 3201001996110');
      expect(IdentiteClinique.piedLegal, '${IdentiteClinique.nom} — IFU 3201001996110');
    });

    test('« Fait à » : la ville de l’adresse ; sans ville, « Fait le »', () {
      expect(IdentiteClinique.faitA('6 novembre 2026'), 'Fait à Parakou, le 6 novembre 2026');
      IdentiteClinique.appliquer({'adresse': ''});
      expect(IdentiteClinique.faitA('6 novembre 2026'), 'Fait le 6 novembre 2026');
    });

    test('rouleau de caisse : sans formule de politesse, ni ligne ni séparateur final ; avec, les deux', () {
      final entree = EntreeTicket(
          operateur: 'Caisse',
          typeVente: 'COMPTANT',
          numero: 'F-1',
          date: DateTime(2026, 11, 6, 10),
          lignes: const [],
          total: 1000,
          partPatient: 1000);
      final sans = lignesTicket(entree).map((l) => l.gauche).toList();
      expect(sans.last, isNot(contains('---')));
      expect(sans.any((t) => t.contains('DIEU')), isFalse);
      expect(sans.first, 'CLINIQUE BAGUIDI');
      IdentiteClinique.appliquer({'formulePolitesse': 'MERCI DE VOTRE CONFIANCE', 'rccm': ''});
      final avec = lignesTicket(entree).map((l) => l.gauche).toList();
      expect(avec.last, 'MERCI DE VOTRE CONFIANCE');
      expect(avec[avec.length - 2], startsWith('---'));
      expect(avec.any((t) => t.startsWith('RCCM')), isFalse, reason: 'RCCM vidé : pas de libellé orphelin');
    });
  });

  group('codes patient : le sigle EN VIGUEUR, et tous les sigles se relisent', () {
    test('codePatient lit le sigle', () {
      expect(codePatient(530, 2025), 'CBG/530/25');
    });
    test('lireCodePatient : nouveau format, ancien format, autre sigle ; un texte quelconque ne se lit pas', () {
      expect(lireCodePatient('CBG/12/26'), (rang: 12, annee: '26'));
      expect(lireCodePatient('CBG530/25'), (rang: 530, annee: '25'));
      expect(lireCodePatient('CBG/7/26'), (rang: 7, annee: '26'));
      expect(lireCodePatient('PROV-ab12'), isNull);
      expect(lireCodePatient(null), isNull);
    });
    test('le prochain code compte les codes déjà attribués sous un AUTRE sigle (RG-01 : jamais réutilisé)', () {
      final p = [
        {'code': 'CBG/40/26', 'statut': 'actif'},
        {'code': 'CBG/3/26', 'statut': 'actif'},
      ];
      expect(patProchainCode(p, DateTime(2026, 11, 6)), 'CBG/41/26');
    });
  });
}
