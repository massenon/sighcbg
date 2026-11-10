import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_poste/impression/apercu.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm8_facturation_test.dart' as f;

/// Le CLIENT LIBRE : une vente au comptoir sans dossier patient. Ni code CBG consommé, ni patient créé, ni couverture ; la pièce porte le nom et le
/// téléphone s'ils sont donnés ; une hospitalisation exige un dossier.
void main() {
  setUpAll(chargerPolices);
  setUp(() => ImpressionPoste.enregistrer = (pdf, nom) async => '/faux/$nom.pdf');
  tearDown(ToastsSigh.viderPourTests);

  f.cas('client libre nommé : la pièce est soldée, sans patientId ni code, aucun dossier ouvert', (t) async {
    final m = f.magasin();
    final patients = m.collection('patients').toutes.length;
    final avant = {for (final x in m.collection('factures').toutes) x['id']};
    await f.ouvrir(t, m);
    await f.choisir(t, 'TIAMOU Bodje', 'Client libre (vente sans dossier patient)');
    await f.ajouterLibre(t, 'Carnet de santé', '500', quantite: '2');
    await f.saisir(t, 'clientNom', 'Mme Azemidia');
    await f.saisir(t, 'clientTelephone', '97000000');
    await f.toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final neuves = [for (final x in m.collection('factures').toutes) if (!avant.contains(x['id'])) x];
    expect(neuves.length, 1);
    final p = neuves.first;
    expect(p['clientLibre'], true);
    expect(p['patientId'], isNull);
    expect(p['patientCode'], isNull);
    expect(p['patient'].toString().trim(), 'Mme Azemidia');
    expect(p['clientTelephone'], '97000000');
    expect(p['operationDissociee'], true);
    expect(p['statutPaiement'], 'soldee');
    expect(p['montantTTC'], 1000);
    expect(m.collection('patients').toutes.length, patients, reason: 'aucun dossier ouvert');
  });

  f.cas('client libre sans nom : la pièce dit « Client libre »', (t) async {
    final m = f.magasin();
    final avant = {for (final x in m.collection('factures').toutes) x['id']};
    await f.ouvrir(t, m);
    await f.choisir(t, 'TIAMOU Bodje', 'Client libre (vente sans dossier patient)');
    await f.ajouterLibre(t, 'Pansement', '300');
    await f.toucher(t, find.widgetWithText(BoutonSigh, 'Enregistrer et encaisser'));
    final p = [for (final x in m.collection('factures').toutes) if (!avant.contains(x['id'])) x].single;
    expect(p['patient'].toString().trim(), 'Client libre');
    expect(p['clientLibre'], true);
  });
}
