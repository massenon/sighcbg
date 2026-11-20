import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/tarifs_poste.dart';
import 'package:sigh_poste/sync/configuration_sync.dart';
import 'package:sigh_poste/sync/transcription_mobile.dart' show PieceSync;

/// AJ (Direction, 16/11/2026) : au changement de jour, les listes de prix affichées (actes, analyses, catalogue) sont PROJETÉES au prix du jour sur le FILEUL aussi, pas seulement sur la
/// mère — utile mère coupée. Le fileul reçoit encore de la mère les listes de la veille : elles ne doivent pas effacer sa projection (ni la faire aller et venir à chaque tour).
/// Les prix des PIÈCES restent lus à la date de la pièce.
final auj = DateTime(2026, 10, 30, 10);
String plus(int n) => tarIso(auj.add(Duration(days: n)));

Magasin jeu() => Magasin.depuisDossier(Magasin.collectionsDuJeu, 'assets/donnees/jeu');

void main() {
  test('mère coupée la veille, fileul au jour : le fileul projette ses listes au prix du jour et les garde ; la pièce d’hier garde son prix', () async {
    final mere = jeu()..horloge = () => auj;
    final t = TarifsPoste(mere, role: 'da', auteur: () => 'DAF', fileul: false, peutEditerEcran: true, horloge: () => auj);
    expect(t.proposer(DemandeProposition(code: 'MG01', prixNonAssure: 5500, etatAssure: 'unique', dateEffet: plus(2), motif: 'Test AJ', valider: true)).ok, isTrue);
    expect(mere.collection('actes').actives.firstWhere((a) => a['code'] == 'MG01')['prix'], 5000, reason: 'la mère, coupée, n’a pas changé de jour');

    // Le fileul a reçu le référentiel (versions comprises) ; deux jours plus tard, la mère est toujours sur la veille.
    final fileul = jeu()..horloge = () => auj.add(const Duration(days: 2));
    for (final c in const ['tarifs', 'versionsTarif']) {
      fileul.collection(c).remplacerContenu([for (final f in mere.collection(c).toutes) {...f}]);
    }
    final app = ApplicateurConfiguration(fileul, (nom) async => [for (final f in mere.collection(nom).toutes) PieceSync('${f['id']}', {...f})],
        collections: const {'tarifs', 'versionsTarif', 'actes'});
    await app.tirer();
    expect(fileul.collection('actes').actives.firstWhere((a) => a['code'] == 'MG01')['prix'], 5500, reason: 'la liste affichée au fileul suit le jour');
    expect(await app.tirer(), 0, reason: 'la liste de la veille, renvoyée par la mère, n’efface pas la projection du jour : aucun va-et-vient');
    expect(fileul.collection('actes').actives.firstWhere((a) => a['code'] == 'MG01')['prix'], 5500);
    expect(TarifsPoste.prixActe(fileul, 'MG01', aujourdhui: auj.add(const Duration(days: 2)), date: plus(1)), 5000, reason: 'une pièce datée de la veille garde le prix de sa date');
  });

  test('une seconde ligne active du même code (doublon non arbitré) garde ce qu’elle porte', () {
    final m = jeu()..horloge = () => auj;
    final cert = m.collection('catalogueTarifs').actives.where((f) => f['code'] == 'CERT-APT').toList();
    expect(cert, hasLength(2));
    final second = cert.last;
    expect(TarifsPoste.auPrixDuJour(m, 'catalogueTarifs', {...second}, auj), {...second});
  });
}
