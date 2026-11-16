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

  TarArbitrageDistincts arbitre({bool peut = true, String motif = 'Deux prestations différentes', Map<Object?, String> demandes = const {}, Iterable<String>? pris, Map<String, String> decides = const {}}) => tarArbitrerDistincts(doublon,
      motif: motif, peutDecider: peut, famille: 'CERTIFICAT', codesFamille: codes, libellesFamille: libelles, codesPris: pris ?? codes, codesDemandes: demandes, codesDecides: decides);

  test('la convention se LIT : préfixe commun, longueur usuelle, mot distinctif ; un code pris se différencie par un rang', () {
    expect(tarPrefixeDeCode('CERT-APT'), 'CERT-');
    expect(tarLongueurSuffixeUsuelle(codes, 'CERT-'), 3, reason: 'cinq codes à trois lettres, un à deux : la convention est trois');
    expect(tarMotsDistinctifs('Certificat d’aptitude', libelles), ['aptitude'], reason: '« certificat » est porté par la majorité de la famille : il ne distingue rien');
    final r = arbitre();
    expect(r.ok, isTrue);
    expect(r.gardeId, 'TAR147', reason: 'le code reste à la ligne que la caisse lit déjà');
    expect(r.identites.single.ficheId, 'TAR152');
    expect(r.identites.single.nouveauCode, 'CERT-APT-2');
  });

  test('un code libre se construit sans rang ; le rang suit tant que le code est pris', () {
    expect(tarCodeDistinct(codeActuel: 'CERT-APT', libelle: 'Certificat de scolarité', codesFamille: codes, libellesFamille: libelles, codesPris: codes), 'CERT-SCO');
    expect(tarCodeDistinct(codeActuel: 'CERT-APT', libelle: 'Certificat d’aptitude', codesFamille: codes, libellesFamille: libelles, codesPris: [...codes, 'CERT-APT-2']), 'CERT-APT-3');
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

  group('AJ (note de la Direction du 16/11/2026) : CERT-APT-2', () {
    test('la convention « -2 » : le rang se sépare par un tiret, pour toutes les familles', () {
      expect(tarCodeDistinct(codeActuel: 'ACT-ABC', libelle: 'Acte abc', codesFamille: const ['ACT-ABC'], libellesFamille: const ['Acte abc'], codesPris: const ['ACT-ABC']), 'ACT-ABC-2');
    });

    test('la décision : code, libellé, 5 000, SOS seule, datée et sourcée, à confirmer ; le type de pièce est relié', () {
      final d = tarPrestationsDecidees.single;
      expect([d.code, d.libelle, d.prixNonAssure, d.prixAssure, d.assurable, d.dateEffet, d.distinctDe, d.typePieceId], ['CERT-APT-2', 'Certificat d’aptitude', 5000, 5000, 'sos', '2026-11-16', 'CERT-APT', 'TPC16']);
      expect(d.source, contains('Note de la Direction du 16/11/2026'));
      expect(d.aConfirmer, isTrue);
      expect(patTypePieceCertificatAptitude2.tarifCode, d.code);
    });

    test('l’arbitrage rattache la ligne au code DÉCIDÉ (déjà pris par construction), sans création', () {
      final r = arbitre(pris: [...codes, 'CERT-APT-2'], decides: tarCodesDecides());
      expect(r.ok, isTrue);
      expect(r.identites.single.nouveauCode, 'CERT-APT-2');
      expect(r.identites.single.prestationDecidee, isTrue);
      final sans = arbitre(pris: [...codes, 'CERT-APT-2']);
      expect(sans.identites.single.nouveauCode, 'CERT-APT-3', reason: 'sans la décision, un code pris prend le rang suivant');
    });

    test('l’amorce : la prestation et sa version datée naissent, la ligne de départ correspondante est rattachée ; rejouée, rien de plus', () {
      final h = ReferentielTarifs([
        {'id': 'CERT-APT', 'code': 'CERT-APT', 'codeGrille': 'CERT-APT', 'libelle': 'Certificat médical d’aptitude', 'famille': 'CERTIFICAT', 'statut': 'actif', 'assurable': 'sos'}
      ], [
        {'id': 'CERT-APT@origine@1', 'code': 'CERT-APT', 'version': 1, 'prixNonAssure': 7000, 'prixAssure': 7000, 'etatAssure': 'montant', 'statut': 'valide'}
      ]);
      final a = tarAmorcerDecisions(h, catalogue: doublon.candidats);
      expect(a.tarifs.single['code'], 'CERT-APT-2');
      expect(a.tarifs.single['assurable'], 'sos');
      final v = a.versions.single;
      expect([v['statut'], v['prixNonAssure'], v['dateEffet'], v['provisoire'], v['origine']], ['valide', 5000, '2026-11-16', true, 'note-direction']);
      expect(a.rattachements.single.id, 'TAR152', reason: 'la ligne « Certificat d’aptitude » à 5 000, jamais celle à 7 000');
      expect(a.rattachements.single.patch['code'], 'CERT-APT-2');
      final apres = ReferentielTarifs([...h.tarifs, ...a.tarifs], [...h.versions, ...a.versions]);
      expect(apres.aLaDate('CERT-APT-2', '2026-11-16', true, aujourdhui: '2026-11-16').montant, 5000);
      expect(apres.aLaDate('CERT-APT-2', '2026-11-15', false, aujourdhui: '2026-11-16').facturable, isFalse, reason: 'jamais antidatée');
      expect(apres.aLaDate('CERT-APT', '2026-11-16', false, aujourdhui: '2026-11-16').montant, 7000, reason: 'CERT-APT n’est pas touché');
      final rejeu = tarAmorcerDecisions(apres, catalogue: [doublon.candidats.first, {...doublon.candidats.last, 'code': 'CERT-APT-2'}]);
      expect(rejeu.vide, isTrue);
    });

    test('le sigle du type de pièce est LIBRE (CMA et CMD sont doubles) ; une fiche existante ou un sigle pris n’amorcent rien', () {
      final existants = [for (final t in patTypesPiece) {'id': t.id, 'sigle': t.sigle, 'tarifCode': t.tarifCode}];
      expect(patSigleLibre('CMA', existants), isFalse);
      expect(patSigleLibre('CAP', existants), isTrue);
      final f = patFicheTypePieceAAmorcer(patTypePieceCertificatAptitude2, existants)!;
      expect([f['id'], f['sigle'], f['tarifCode'], f['aValider']], ['TPC16', 'CAP', 'CERT-APT-2', true]);
      expect(patFicheTypePieceAAmorcer(patTypePieceCertificatAptitude2, [...existants, f]), isNull);
      expect(patFicheTypePieceAAmorcer(patTypePieceCertificatAptitude2, [...existants, {'id': 'TPC99', 'sigle': 'cap'}]), isNull, reason: 'aucune collision créée');
      final n = patNumeroter(patTypePieceCertificatAptitude2, const [], 2026);
      expect(n.reference, startsWith('CAP 001/001/'));
    });
  });
}
