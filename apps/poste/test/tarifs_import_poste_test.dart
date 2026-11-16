import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/import/port_magasin.dart';
import 'package:sigh_poste/sync/service_demandes_import.dart';

/// L'IMPORT DE PRIX AU POSTE (lot TAR, T4) : le jeu `tarifs` écrit par PROPOSITION dans le vrai magasin (gardes comprises), au même moteur que l'écran. Le geste de décider est lu de la
/// MATRICE (fiches `rbac`) par le profil : aucun nom de rôle dans le jeu. Un fileul ne dépose pas un fichier de prix : il propose à l'écran (famille R, la mère seule écrit).
final auj = DateTime(2026, 10, 30, 10);
const entete = ['Code', 'Désignation', 'Famille', 'Secteur', 'Prix non assuré', 'Prix assuré', 'Prix unique', 'Couverture', 'Date d’effet', 'Valider (Oui/Non)', 'Motif', 'Source'];

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

PortMagasin port(Magasin m, String role) => PortMagasin(m,
    aujourdhui: () => auj,
    nomAgent: 'Importateur',
    profil: ProfilImport(
        role: role,
        droitEcran: (e) => const Droit(voir: true, editer: true, annuler: false),
        gesteDroit: (g) => DroitsGestes(fiches: m.collection('rbac').actives).peut(role, g)));

List<Object?> ligne(String code, num na, num pa, {String valider = '', String date = '2027-01-15', String motif = 'Nouvelle grille'}) =>
    [code, '', '', '', na, pa, 'non', '', date, valider, motif, ''];

void main() {
  test('la mère importe : « Oui » du rôle qui détient le geste = version validée (les listes de lecture suivent à la projection) ; le prix d\'avant la date d\'effet ne bouge pas', () {
    final m = jeu();
    final p = port(m, 'da');
    final a = analyserLignes(jeuTarifs, [entete, ligne('MG01', 5500, 3300, valider: 'oui')], 'prix.xlsx', p);
    expect(a.accepte, isTrue, reason: a.problemes.map((x) => '${x.code}:${x.motif}').join(' | '));
    final r = appliquer(jeuTarifs, a, p);
    expect(r.ok, isTrue, reason: '${r.motif}');
    final v = TarifsPoste.lire(m).versionsDe('MG01').last;
    expect([v['statut'], v['prixNonAssure'], v['dateEffet']], ['valide', 5500, '2027-01-15']);
    expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj, date: '2027-01-14'), 5000);
    expect(TarifsPoste.prixActe(m, 'MG01', aujourdhui: auj, date: '2027-01-15'), 5500);
    expect(m.collection('audit').toutes.any((x) => '${x['action']}'.contains('LotImport') || '${x['entite']}' == 'LotImport'), isTrue, reason: 'le lot est journalisé (RG-12)');
  });

  test('sans le geste (rôle sans fiche d\'origine) : le Oui vaut PROPOSITION ; la fiche de rôle qui accorde le geste le rend décisionnaire, à chaud', () {
    final m = jeu();
    final a = analyserLignes(jeuTarifs, [entete, ligne('MG02', 8600, 8600, valider: 'oui')], 'prix.xlsx', port(m, 'stock'));
    expect(a.accepte, isTrue);
    expect(a.problemes.map((x) => x.code), contains('OUI_VAUT_PROPOSITION'));
    expect(appliquer(jeuTarifs, a, port(m, 'stock')).ok, isTrue);
    expect(TarifsPoste.lire(m).versionsDe('MG02').last['statut'], 'propose');
    m.collection('rbac').inserer({'id': 'RBAC-S', 'role': 'stock', 'statut': 'actif', 'droitsGestes': {gesteDeciderPrix: true}});
    final b = analyserLignes(jeuTarifs, [entete, ligne('MG03', 10600, 10600, valider: 'oui')], 'prix2.xlsx', port(m, 'stock'));
    expect(appliquer(jeuTarifs, b, port(m, 'stock')).ok, isTrue);
    expect(TarifsPoste.lire(m).versionsDe('MG03').last['statut'], 'valide', reason: 'le geste accordé par la fiche vaut à la lecture suivante');
  });

  test('un fileul rattaché ne dépose pas un fichier de prix : réservé à la mère (le moteur le dit), il propose à l\'écran', () {
    final m = jeu();
    final svc = ServiceDemandesImport.de(m)..fileulRattache = () => true;
    expect(svc.reserveALaMere(jeuTarifs), isTrue);
    expect(svc.passeParUneDemande(jeuTarifs), isFalse);
    final mere = ServiceDemandesImport.de(jeu())..fileulRattache = () => false;
    expect(mere.reserveALaMere(jeuTarifs), isFalse);
  });

  test('l\'ancien jeu « catalogue des actes » ne subsiste pas : plus aucun import n\'écrit un prix dans une liste de lecture (la garde du magasin le refuserait)', () {
    expect(jeuxImport.any((j) => j.cibles.contains('actes')), isFalse);
    final m = jeu();
    final acte = m.collection('actes').actives.first;
    expect(() => m.collection('actes').mettreAJour(acte['id'], {'prix': 1}), throwsA(isA<EcritureRefusee>()));
  });
}
