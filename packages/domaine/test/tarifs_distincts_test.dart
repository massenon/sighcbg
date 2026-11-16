import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

/// Q18 : la TROISIÈME issue de l'arbitrage d'un prix en doublon, « ce sont deux prestations distinctes ». Le code reste à la ligne que la caisse lit ; l'autre reçoit un nouvel identifiant construit sur la
/// convention des codes de la famille (lue, jamais inventée), jamais réutilisé ; aucun prix ne change.
void main() {
  final famille = <Map<String, Object?>>[
    {'code': 'CERT-DPS', 'libelle': 'Certificat médical de dispense aux activités physiques et sportives'},
    {'code': 'CERT-ATG', 'libelle': 'Attestation de grossesse'},
    {'code': 'CERT-DEC', 'libelle': 'Certificat médical de décès'},
    {'code': 'CERT-CBV', 'libelle': 'Certificat médical initial / de coups et blessures volontaires'},
    {'code': 'CERT-VC', 'libelle': 'Certificat médical de visite et de contre-visite'},
    {'code': 'CERT-APT', 'libelle': 'Certificat médical d’aptitude'},
  ];
  final codes = [for (final f in famille) '${f['code']}'];
  final libelles = [for (final f in famille) '${f['libelle']}'];
  final doublon = TarDoublonPrix(collection: 'catalogueTarifs', code: 'CERT-APT', candidats: [
    {'id': 'TAR147', 'code': 'CERT-APT', 'libelle': 'Certificat médical d’aptitude', 'prixNonAssure': 7000, 'prixAssure': 7000, 'assurable': 'sos'},
    {'id': 'TAR152', 'code': 'CERT-APT', 'libelle': 'Certificat d’aptitude', 'prixNonAssure': 5000, 'prixAssure': 5000, 'assurable': 'sos'},
  ]);

  TarArbitrageDistincts arbitre({bool peut = true, String motif = 'Deux prestations différentes', Map<Object?, String> demandes = const {}, Iterable<String>? pris}) => tarArbitrerDistincts(doublon,
      motif: motif, peutDecider: peut, famille: 'CERTIFICAT', codesFamille: codes, libellesFamille: libelles, codesPris: pris ?? codes, codesDemandes: demandes);

  test('la convention se LIT : préfixe commun, longueur usuelle, mot distinctif ; un code pris se différencie par un rang', () {
    expect(tarPrefixeDeCode('CERT-APT'), 'CERT-');
    expect(tarLongueurSuffixeUsuelle(codes, 'CERT-'), 3, reason: 'cinq codes à trois lettres, un à deux : la convention est trois');
    expect(tarMotsDistinctifs('Certificat d’aptitude', libelles), ['aptitude'], reason: '« certificat » est porté par la majorité de la famille : il ne distingue rien');
    final r = arbitre();
    expect(r.ok, isTrue);
    expect(r.gardeId, 'TAR147', reason: 'le code reste à la ligne que la caisse lit déjà');
    expect(r.identites.single.ficheId, 'TAR152');
    expect(r.identites.single.nouveauCode, 'CERT-APT2');
  });

  test('un code libre se construit sans rang ; le rang suit tant que le code est pris', () {
    expect(tarCodeDistinct(codeActuel: 'CERT-APT', libelle: 'Certificat de scolarité', codesFamille: codes, libellesFamille: libelles, codesPris: codes), 'CERT-SCO');
    expect(tarCodeDistinct(codeActuel: 'CERT-APT', libelle: 'Certificat d’aptitude', codesFamille: codes, libellesFamille: libelles, codesPris: [...codes, 'CERT-APT2']), 'CERT-APT3');
  });

  test('aucun prix ne change : la prestation nouvelle porte le prix PROPRE de sa ligne, la gardée n’est pas touchée', () {
    final i = arbitre().identites.single;
    expect([i.prixNonAssure, i.prixAssure, i.etatAssure, i.famille, i.ancienCode], [5000, 5000, 'montant', 'CERTIFICAT', 'CERT-APT']);
    expect(doublon.candidats.first['prixNonAssure'], 7000);
  });

  test('une ligne sans prix donne une prestation sans prix (« prix à définir »), jamais un zéro', () {
    final d = TarDoublonPrix(collection: 'actes', code: 'ACT-X', candidats: [
      {'id': 'A1', 'code': 'ACT-X', 'libelle': 'Acte x', 'prix': 3000},
      {'id': 'A2', 'code': 'ACT-X', 'libelle': 'Acte autre'},
    ]);
    final r = tarArbitrerDistincts(d, motif: 'm', peutDecider: true, famille: 'ACTE', codesFamille: const ['ACT-X'], libellesFamille: const ['Acte x'], codesPris: const ['ACT-X']);
    expect(r.identites.single.prixNonAssure, isNull);
    expect(r.identites.single.etatAssure, 'manquant');
  });

  test('refus nommés : geste réservé, motif, code déjà pris (référentiel, listes de départ, archivés), code vide', () {
    expect(arbitre(peut: false).refus!.code, 'ARBITRAGE_RESERVE');
    expect(arbitre(motif: '  ').refus!.code, 'MOTIF_REQUIS');
    expect(arbitre(demandes: {'TAR152': 'CERT-DEC'}).refus!.code, 'CODE_EXISTANT');
    expect(arbitre(demandes: {'TAR152': 'cert-dec'}).refus!.code, 'CODE_EXISTANT', reason: 'la casse ne contourne pas un code pris');
    expect(arbitre(demandes: {'TAR152': 'CERT-AUT'}, pris: [...codes, 'CERT-AUT']).refus!.code, 'CODE_EXISTANT');
    expect(arbitre(demandes: {'TAR152': ' '}).refus!.code, 'CODE_VIDE');
    final libre = arbitre(demandes: {'TAR152': 'CERT-MDT'});
    expect(libre.ok, isTrue);
    expect(libre.identites.single.nouveauCode, 'CERT-MDT');
  });
}
