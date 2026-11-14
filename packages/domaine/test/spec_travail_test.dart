import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

void main() {
  test('trois visites, trois actes, trois codes de grille', () {
    expect(mdtNatures.map((n) => (n.code, n.acte, n.codeTarif)).toList(),
        [('embauche', 'MT01', 'MT-EMB'), ('periodique', 'MT02', 'MT-PER'), ('reprise', 'MT03', 'MT-REP')]);
    expect(mdtNature('Visite médicale de reprise')!.code, 'reprise');
    expect(mdtNature('inconnue'), isNull);
  });

  test('la fiche d\'aptitude est une pièce tarifée par la caisse sur MT-FAP, sans collision de sigle', () {
    expect(mdtTypePiece.tarifCode, 'MT-FAP');
    expect(mdtTypePiece.sigle, 'FAP');
    expect(mdtTypePiece.collision, isNull);
    expect(patTypesPiece.any((t) => t.sigle == 'FAP'), isFalse);
  });

  test('validité : douze mois, aucune pour une inaptitude définitive', () {
    expect(mdtValiditeFiche(DateTime(2026, 8, 5), 'Apte'), '2027-08-05');
    expect(mdtValiditeFiche(DateTime(2026, 8, 5), 'Inapte temporaire'), '2027-08-05');
    expect(mdtValiditeFiche(DateTime(2026, 8, 5), 'Inapte définitif'), isNull);
  });

  test('la référence suit la série annuelle, archivées comprises', () {
    final c = [
      {'ficheAptitude': {'reference': 'FA-0001/26'}},
      {'ficheAptitude': {'reference': 'FA-0007/26'}, 'statut': 'archive'},
      {'ficheAptitude': {'reference': 'FA-0099/25'}},
      {'diagnostic': 'sans fiche'},
    ];
    expect(mdtReferenceFiche(c, DateTime(2026, 11, 9)), 'FA-0008/26');
    expect(mdtReferenceFiche(c, DateTime(2027, 1, 4)), 'FA-0001/27');
    expect(mdtReferenceFiche(const [], DateTime(2026, 1, 1)), 'FA-0001/26');
  });

  test('l\'état d\'un salarié : jamais vu, à jour, à planifier, en retard', () {
    final auj = DateTime(2026, 11, 9);
    expect(mdtEtatSalarie(null, auj).etat, MdtEtat.jamaisVu);
    final ajour = mdtEtatSalarie(DateTime(2026, 8, 5), auj);
    expect(ajour.etat, MdtEtat.aJour);
    expect(ajour.echeance, '2027-08-05');
    expect(mdtEtatSalarie(DateTime(2025, 11, 30), auj).etat, MdtEtat.aPlanifier);
    final retard = mdtEtatSalarie(DateTime(2025, 10, 1), auj);
    expect(retard.etat, MdtEtat.enRetard);
    expect(retard.jours!, lessThan(0));
    expect(mdtEtatSalarie(DateTime(2026, 5, 20), auj, periodiciteMois: 6).etat, MdtEtat.aPlanifier);
  });

  test('une convention est en vigueur entre son début et sa fin ; sans fin, elle se reconduit ; archivée, jamais', () {
    final c = {'dateDebut': '2026-08-01', 'dateFin': '2027-07-31'};
    expect(mdtConventionEnVigueur(c, '2026-07-31'), isFalse);
    expect(mdtConventionEnVigueur(c, '2026-08-01'), isTrue);
    expect(mdtConventionEnVigueur(c, '2027-07-31'), isTrue);
    expect(mdtConventionEnVigueur(c, '2027-08-01'), isFalse);
    expect(mdtConventionEnVigueur({'dateDebut': '2026-08-01'}, '2040-01-01'), isTrue);
    expect(mdtConventionEnVigueur({...c, 'statut': 'archive'}, '2026-09-01'), isFalse);
  });

  test('le décompte oppose les visites prévues aux visites réalisées de l\'année pour l\'entreprise', () {
    final conv = {'entrepriseId': 'SOU001', 'visitesAnnuellesPrevues': 3};
    final v = (String e, String d, [String statut = 'terminee', String type = 'Médecine du travail']) =>
        {'entrepriseId': e, 'date': d, 'statut': statut, 'type': type};
    final r = mdtDecompteConvention(conv, [
      v('SOU001', '2026-08-05T10:00:00Z'),
      v('SOU001', '2026-09-05T10:00:00Z'),
      v('SOU002', '2026-09-05T10:00:00Z'),
      v('SOU001', '2025-09-05T10:00:00Z'),
      v('SOU001', '2026-10-05T10:00:00Z', 'planifiee'),
      v('SOU001', '2026-10-06T10:00:00Z', 'terminee', 'Consultation'),
    ], 2026);
    expect((r.prevues, r.realisees, r.reste), (3, 2, 1));
    expect(mdtDecompteConvention({'entrepriseId': 'X', 'visitesAnnuellesPrevues': 1}, const [], 2026).reste, 1);
  });
}
