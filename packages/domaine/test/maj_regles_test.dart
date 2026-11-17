import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

final now = DateTime(2026, 11, 17, 12);
PreuveMaj p(int h, {bool ok = true}) => PreuveMaj(date: now.subtract(Duration(hours: h)), verifiee: ok);

void main() {
  test('sauvegarde ET export récents et vérifiés : autorisée', () {
    expect(majPreparation(maintenant: now, maxHeures: 24, sauvegarde: p(3), export: p(1)).autorisee, isTrue);
  });
  test('chaque manque est nommé', () {
    List<String> codes(PreuveMaj? s, PreuveMaj? e) => [for (final r in majPreparation(maintenant: now, maxHeures: 24, sauvegarde: s, export: e).refus) r.code];
    expect(codes(null, null), ['SAUVEGARDE_ABSENTE', 'EXPORT_ABSENT']);
    expect(codes(p(30), p(30)), ['SAUVEGARDE_TROP_ANCIENNE', 'EXPORT_TROP_ANCIEN']);
    expect(codes(p(1, ok: false), p(1, ok: false)), ['SAUVEGARDE_NON_VERIFIEE', 'EXPORT_NON_VERIFIE']);
    expect(codes(p(1), null), ['EXPORT_ABSENT']);
  });
  test('N est un paramètre : 48 h accepte ce que 24 h refuse', () {
    expect(majPreparation(maintenant: now, maxHeures: 24, sauvegarde: p(30), export: p(30)).autorisee, isFalse);
    expect(majPreparation(maintenant: now, maxHeures: 48, sauvegarde: p(30), export: p(30)).autorisee, isTrue);
  });
  test('le message de blocage nomme les codes et dit comment lever', () {
    final v = majPreparation(maintenant: now, maxHeures: 24);
    final m = majMessageBlocage(v);
    expect(m, contains('SAUVEGARDE_ABSENTE'));
    expect(m, contains('BLOQUÉE'));
    expect(m, contains('24 heure'));
  });
  test('le réglage est borné, jamais rogné', () {
    expect(majVerifierReglage(24), isNull);
    expect(majVerifierReglage(0)?.code, 'MAJ_DELAI_HORS_BORNES');
    expect(majVerifierReglage(169)?.code, 'MAJ_DELAI_HORS_BORNES');
    expect(majVerifierReglage('24')?.code, 'MAJ_DELAI_HORS_BORNES');
  });
  test('le défaut est semé au registre des paramètres, pas écrit dans le code appelant', () {
    final d = definitionsParametres.where((x) => x.cle == cleMajSauvegardeMaxHeures).single;
    expect(d.defaut, majHeuresDefaut);
    expect(libellesFamillesParametres[d.famille], isNotNull);
  });
  group('levée du blocage : geste réservé tracé', () {
    test('sans le droit : refus nommé', () => expect(majControlerLevee(aLeDroit: false, motif: 'incendie du local serveur')?.code, 'GESTE_RESERVE'));
    test('sans motif : refus nommé', () => expect(majControlerLevee(aLeDroit: true, motif: 'court')?.code, 'MOTIF_OBLIGATOIRE'));
    test('avec le droit et le motif : accordée', () => expect(majControlerLevee(aLeDroit: true, motif: 'panne du disque de sauvegarde, mise à jour de sécurité'), isNull));
    test('le droit se lit à la fiche (gestes d’origine), jamais à un nom de rôle', () {
      final roles = gesteReserve(gesteMajLeverBlocage)!.rolesDefaut;
      expect(roles, isNotEmpty);
      expect(gestesOrigine().peut(roles.first, gesteMajLeverBlocage), isTrue);
    });
  });
  group('fichier d’autorisation lu par l’installeur', () {
    final texte = majTexteAutorisation(maintenant: now, validiteHeures: 4, versionCourante: '0.1.0', schema: schemaDonneesCourant, levee: false, sauvegarde: now, export: now);
    test('valide pendant sa durée', () {
      expect(majLireAutorisation(texte, now.add(const Duration(hours: 3))), isNull);
      expect(texte, contains('valable_jusqu_local=20261117160000'));
    });
    test('expirée, absente, illisible : refus nommés', () {
      expect(majLireAutorisation(texte, now.add(const Duration(hours: 5)))?.code, 'AUTORISATION_EXPIREE');
      expect(majLireAutorisation(null, now)?.code, 'AUTORISATION_ABSENTE');
      expect(majLireAutorisation('n importe quoi', now)?.code, 'AUTORISATION_ILLISIBLE');
      expect(majLireAutorisation('SIGH-AUTORISATION-MAJ 1\nvalable_jusqu_local=hier', now)?.code, 'AUTORISATION_ILLISIBLE');
    });
    test('la levée est consignée dans le fichier', () {
      expect(majTexteAutorisation(maintenant: now, validiteHeures: 4, versionCourante: '1', schema: 1, levee: true), contains('levee=oui'));
    });
  });
}
