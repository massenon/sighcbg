import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/modules/cfg/cfa_commun.dart';

import 'm14_aide.dart';

/// Le titre porté par l'agent (Direction de Baguidi) : un agent peut porter à l'organigramme un titre autre que son poste. Il vit sur la fiche du personnel, se lit par
/// le nom du titulaire, et ne change rien tant qu'il est vide.
void main() {
  test('le titre de l\'agent s\'ajoute au nom du titulaire ; sans titre, ou pour un titulaire inconnu, le nom seul', () {
    final m = magasinM14();
    final agent = m.collection('personnel').actives.first;
    final nom = '${agent['nomComplet']}';
    expect(cfaTitulaireAvecTitre(m, nom), nom);
    m.collection('personnel').mettreAJour(agent['id'], {'titreOrganigramme': 'SG'});
    expect(cfaTitulaireAvecTitre(m, nom), '$nom (SG)');
    m.collection('personnel').mettreAJour(agent['id'], {'titreOrganigramme': '  '});
    expect(cfaTitulaireAvecTitre(m, nom), nom, reason: 'un titre blanc n\'est pas un titre');
    expect(cfaTitulaireAvecTitre(m, 'Inconnu Aucun'), 'Inconnu Aucun');
  });
}
