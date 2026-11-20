import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

RepPoste poste(String uuid, String etiquette, {String role = 'fileul', bool revoque = false}) =>
    (uuid: uuid, etiquette: etiquette, role: role, revoque: revoque, dernierContact: null, derniereSeq: 0);

Map<String, Object?> fiche(String role, Map<String, bool> gestes) => {'id': 'R1', 'role': role, 'statut': 'actif', 'droitsGestes': gestes};

void main() {
  test('seuls les fileuls se reprennent ; les actifs d’abord, puis les révoqués, par étiquette', () {
    final l = repPostesReprenables([
      poste('u3', 'Zeta'),
      poste('u1', 'Beta', revoque: true),
      poste('m1', 'Téléphone', role: 'mobile'),
      poste('u2', 'alpha'),
      poste('u4', ''),
      poste('mere', 'Mère', role: 'mere'),
    ]);
    expect(l.map((p) => p.uuid), ['u2', 'u4', 'u3', 'u1'], reason: 'un mobile et la mère ne se reprennent pas ; sans étiquette, l’identifiant sert de nom');
    expect(repNomPoste(l[1]), 'u4');
  });

  test('l’étiquette proposée est celle de l’ancien poste, nettoyée', () {
    expect(repEtiquetteProposee(poste('u1', '  Réception  ')), 'Réception');
  });

  test('la durée de validité vient de la mère, jamais supposée', () {
    expect(repDureeLisible(900), '15 minutes');
    expect(repDureeLisible(60), '1 minute');
    expect(repDureeLisible(3600), '1 heure');
    expect(repDureeLisible(7200), '2 heures');
    expect(repDureeLisible(90), '90 secondes');
    expect(repDureeLisible(150), '3 minutes', reason: 'arrondie à la minute supérieure : on ne promet jamais plus que ce que la mère accorde');
    expect(repDureeLisible(null), isNull);
    expect(repDureeLisible(0), isNull);
    expect(repDureeLisible(-5), isNull);
  });

  test('compte à rebours : jamais négatif', () {
    expect(repTempsRestant(10000, 4000), const Duration(milliseconds: 6000));
    expect(repTempsRestant(10000, 12000), Duration.zero);
    expect(repCompteARebours(const Duration(seconds: 725)), '12 min 05 s');
    expect(repCompteARebours(const Duration(seconds: -3)), '0 min 00 s');
    expect(repCompteARebours(const Duration(seconds: 3720)), '1 h 02 min');
  });

  test('chaque refus nommé de la reprise a un motif lisible ET un geste ; le code de la mère est repris tel quel', () {
    for (final c in ['appareil_inconnu', 'deja_repris', 'code_expire', 'code_utilise', 'code_invalide', 'admin_requis', 'acces_refuse', 'mere_injoignable']) {
      final r = repRefus(c);
      expect(r.code, c);
      expect(r.motif, isNotEmpty);
      expect(r.geste, isNotEmpty, reason: 'un refus dit ce qu’on fait ensuite : $c');
    }
    expect(repRefus('code_expire').motif, contains('expiré'));
    expect(repRefus('deja_repris').motif, contains('déjà été repris'));
    expect(repRefus('appareil_inconnu').motif, contains('ne connaît pas'));
    expect(repRefus('acces_refuse').motif, contains('droit'));
  });

  test('un refus inconnu garde le motif de la mère (jamais masqué) ; sans motif, un libellé neutre', () {
    expect(repRefus('autre_chose', motifMere: 'Le disque est plein.').motif, 'Le disque est plein.');
    expect(repRefus('autre_chose').motif, 'Refus de la mère.');
    expect(repRefus('autre_chose').code, 'autre_chose');
  });

  test('aucun refus ne laisse supposer un code de reprise', () {
    for (final c in ['appareil_inconnu', 'deja_repris', 'code_expire', 'code_utilise', 'code_invalide', 'admin_requis', 'acces_refuse']) {
      final r = repRefus(c);
      expect('${r.motif} ${r.geste}'.contains(RegExp(r'\b[A-HJKMNP-Z2-9]{8}\b')), isFalse, reason: c);
    }
  });

  test('ce que la mère rapporte d’une reprise se lit, et une forme inattendue n’en fait pas une reprise', () {
    final r = repLireRepriseFaite({'de': 'u1', 'plages': 2, 'baux': 1});
    expect(r, isNotNull);
    expect(r!.de, 'u1');
    expect(r.plages, 2);
    expect(r.baux, 1);
    expect(repLireRepriseFaite(null), isNull);
    expect(repLireRepriseFaite('x'), isNull);
    expect(repLireRepriseFaite({'plages': 2}), isNull);
    expect(repLireRepriseFaite({'de': ''}), isNull);
    expect(repLireRepriseFaite({'de': 'u1'})!.plages, 0);
    final t = repPhraseRepriseFaite(r);
    expect(t, contains('u1'));
    expect(t, contains('2 plages de numéros'));
    expect(t, contains('1 bail de stock'));
    expect(t, contains('révoqué'));
  });

  test('le journal de l’émission porte QUI est repris et jusqu’à quand, jamais le code', () {
    final j = repJournalEmission(uuidAncien: 'u1', etiquetteAncien: 'Réception', expireMs: 1000, validiteSecondes: 900);
    expect(j.keys.toSet(), {'poste', 'etiquette', 'expire', 'validite_s'});
    expect(j.containsKey('code'), isFalse);
    expect(repJournalEmission(uuidAncien: 'u1', etiquetteAncien: 'R').keys.toSet(), {'poste', 'etiquette'});
  });

  test('le geste réservé : origine à l’administrateur et à la DAF, réglable en fiche de rôle', () {
    final g = gesteReserve(gesteRepriseEmettre);
    expect(g, isNotNull);
    expect(g!.ecran, 'mere-reprise-poste');
    expect(g.rolesDefaut, isNotEmpty);
    expect(DroitsGestes(fiches: const []).peut(g.rolesDefaut.first, gesteRepriseEmettre), isTrue);
    expect(DroitsGestes(fiches: const []).peut('inconnu', gesteRepriseEmettre), isFalse);
    expect(DroitsGestes(fiches: [fiche(g.rolesDefaut.first, {gesteRepriseEmettre: false})]).peut(g.rolesDefaut.first, gesteRepriseEmettre), isFalse, reason: 'une fiche le retire');
    expect(DroitsGestes(fiches: [fiche('role-cree', {gesteRepriseEmettre: true})]).peut('role-cree', gesteRepriseEmettre), isTrue, reason: 'une fiche l’accorde');
  });
}
