// La validation DÉPOSÉE par un fileul et APPLIQUÉE par la mère (continuité de service, Direction, 15/11/2026) : le moteur pur, sans magasin.
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:test/test.dart';

typedef M = Map<String, Object?>;

const libelles = {'direction': 'Direction / Gérance', 'da': 'Directrice Administrative', 'caissier': 'Caissier'};

M acte() => {'id': 'A1', 'code': 'MG01', 'designation': 'Consultation', 'prix': 5000, 'tarifProvisoire': true, 'statut': 'actif'};

void main() {
  late Map<String, List<M>> base;
  LectureValidation lire() => (n) => base[n] ?? const [];
  var n = 0;
  String nouvelId() => 'VDP-${++n}';
  final t0 = DateTime.utc(2026, 11, 15, 9);

  setUp(() => base = {'actes': [acte()], valCollectionValidations: [], valCollectionDepots: []});

  VerdictDepot deposer({String role = 'direction', List<M>? depots}) => valDeposer('actes', 'A1',
      role: role, acteur: 'La Direction', poste: 'F1', maintenant: t0, lire: lire(), libelles: libelles, depots: depots ?? base[valCollectionDepots]!, nouvelId: nouvelId);

  test('un dépôt refait les contrôles du geste : un rôle hors famille est refusé en le nommant, rien n’est déposé', () {
    final r = deposer(role: 'caissier');
    expect(r.ok, isFalse);
    expect(r.refus!.code, 'VALIDATION_RESERVEE');
  });

  test('le dépôt porte famille, cible, rôle, auteur, poste et instant du geste ; il est « deposee », pas « validé »', () {
    final r = deposer();
    expect(r.ok, isTrue);
    final f = r.fiche!;
    expect([f['genre'], f['famille'], f['cible'], f['etat'], f['demandeRole'], f['demandePar'], f['demandePoste']], ['referentiel', 'actes', 'A1', 'deposee', 'direction', 'La Direction', 'F1']);
    expect(f['demandeLe'], valInstant(t0));
    expect(valEtatDepot('actes', 'A1', [f])!.enAttente, isTrue);
  });

  test('IDEMPOTENCE du dépôt : un second geste identique n’ajoute rien', () {
    final a = deposer().fiche!;
    base[valCollectionDepots]!.add(a);
    final b = deposer();
    expect(b.dejaDepose, isTrue);
    expect(b.fiche!['id'], a['id']);
  });

  test('la mère applique sous le rôle de l’AUTEUR, à la date du geste ; l’élément est validé, avec les mêmes traces que le geste direct', () {
    final dep = deposer().fiche!;
    final a = valAppliquerDepot(dep, lire: lire(), libelles: libelles, maintenant: t0.add(const Duration(hours: 5)))!;
    expect(a.etat, valDepotAppliquee);
    final v = a.validation!;
    expect([v.collection, v.id, v.validePar, v.valideRole, v.valideLe], ['actes', 'A1', 'La Direction', 'Direction / Gérance', valInstant(t0)], reason: 'date du geste, pas de l’application');
    expect(v.patch['tarifProvisoire'], isFalse);
  });

  test('IDEMPOTENCE de l’application : rejouée sur un élément déjà validé, la mère rend sans_effet (nommé), aucune seconde trace', () {
    final dep = deposer().fiche!;
    final a = valAppliquerDepot(dep, lire: lire(), libelles: libelles, maintenant: t0)!;
    base['actes']![0].addAll(a.validation!.patch);
    final b = valAppliquerDepot(dep, lire: lire(), libelles: libelles, maintenant: t0)!;
    expect(b.etat, valDepotSansEffet);
    expect(b.code, 'DEJA_VALIDE');
    expect(b.validation, isNull);
    // Un dépôt traité n’est plus rejoué du tout.
    expect(valAppliquerDepot({...dep, 'etat': 'appliquee'}, lire: lire(), libelles: libelles, maintenant: t0), isNull);
  });

  test('la mère REFAIT les contrôles avec SES données : un élément qui a disparu est refusé, le verdict se nomme', () {
    final dep = deposer().fiche!;
    base['actes']!.clear();
    final a = valAppliquerDepot(dep, lire: lire(), libelles: libelles, maintenant: t0)!;
    expect(a.etat, valDepotRefusee);
    expect(a.code, 'INTROUVABLE');
    expect(a.geste, isNotEmpty);
    expect(valEtatDepot('actes', 'A1', [{...dep, 'etat': 'refusee', 'resultatCode': a.code, 'resultatMotif': a.motif}])!.refuse, isTrue);
  });

  test('une validation appliquée ou sans effet ne dit plus rien : l’élément porte SA validation (état lu, jamais stocké)', () {
    final dep = deposer().fiche!;
    expect(valEtatDepot('actes', 'A1', [{...dep, 'etat': 'appliquee'}]), isNull);
    expect(valEtatDepot('actes', 'A1', [{...dep, 'etat': 'sans_effet'}]), isNull);
  });

  test('un genre inconnu est refusé par la mère en nommant, jamais appliqué', () {
    final a = valAppliquerDepot({...deposer().fiche!, 'genre': 'autre'}, lire: lire(), libelles: libelles, maintenant: t0)!;
    expect([a.etat, a.code], [valDepotRefusee, 'GENRE_INCONNU']);
  });
}
