import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigh_domaine/sigh_domaine.dart';
import 'package:sigh_poste/core/service_parametres.dart';
import 'package:sigh_poste/donnees/magasin.dart';
import 'package:sigh_poste/donnees/mecef_poste.dart';
import 'package:sigh_poste/donnees/normalisation_mecef.dart';
import 'package:sigh_poste/kit/kit.dart';

import 'aide_polices.dart';
import 'm14_aide.dart';

/// LE BOÎTIER MECeF DE BAGUIDI : un ELTRADE CC300 (décision de la Direction du 16/11/2026). Le MODÈLE est un réglage de clinique semé, affiché à la configuration,
/// porté sur la pièce et au journal MECeF là où le mode l'est ; l'adaptateur reste NON CONFIGURÉ (aucun protocole dans le dépôt) et le dit. Aucune requête réseau.
final aujourdhui = DateTime(2026, 10, 30);

Magasin magasin() => Magasin.depuisDossier(Magasin.collectionsDuJeu);

Fiche vente(Magasin m) => m.collection('factures').inserer({
      'numero': 'FN-TEST-CC300',
      'montantTTC': 10000,
      'montantPaye': 10000,
      'statutPaiement': 'soldee',
      'statutMecef': 'en_attente',
      'statut': 'actif',
      'lignes': [
        {'id': 'L1', 'designation': 'Consultation', 'quantite': 1, 'prixUnitaire': 10000, 'partAssureur': 0, 'partPatient': 10000, 'statutPaiement': 'paye'}
      ],
    }, prefixe: 'FAC').fiche;

void main() {
  setUpAll(chargerPolices);
  tearDown(ToastsSigh.viderPourTests);

  test('le modèle se LIT au registre : semé à « ELTRADE CC300 », réglable par une version datée', () {
    final m = magasin();
    expect(modeleBoitierDuPoste(m, aujourdhui), 'ELTRADE CC300');
    final s = serviceParametres(m, auteur: () => 'DAF', horloge: () => aujourdhui);
    expect(s.regler(mecefCleModeleBoitier, 'ELTRADE CC300 (série 2)', parametreDateIso(aujourdhui), motif: 'essai').ok, isTrue);
    expect(modeleBoitierDuPoste(m, aujourdhui), 'ELTRADE CC300 (série 2)');
  });

  test('une vente en mode boîtier : en attente, AUCUN numéro, la pièce et le journal MECeF portent le modèle', () {
    final m = magasin();
    final f = vente(m);
    final r = normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
    expect(r.ok, isFalse);
    expect(r.code, mecefCodeNonConfigure);
    expect(r.motif, contains('adaptateur ELTRADE CC300 : intégration à fournir par l’éditeur du boîtier'));
    final apres = m.collection('factures').parId(f['id'])!;
    expect(apres['numeroMecef'], isNull);
    expect(apres['modeMecef'], 'boitier');
    expect(apres['modeleBoitierMecef'], 'ELTRADE CC300');
    final j = m.collection('audit').toutes.lastWhere((x) => x['action'] == 'Normalisation en attente (adaptateur non configuré)');
    expect((j['apres'] as Map)['boitier'], 'ELTRADE CC300');
    expect((j['apres'] as Map)['mode'], 'boitier');
  });

  test('en mode e-MECeF, le modèle du boîtier n’est PAS porté (il ne concerne pas la tentative)', () {
    final m = magasin();
    serviceParametres(m, auteur: () => 'DAF', horloge: () => aujourdhui).regler(mecefCleMode, 'emecef', parametreDateIso(aujourdhui));
    final f = vente(m);
    normaliserVente(m, '${f['id']}', maintenant: aujourdhui);
    final apres = m.collection('factures').parId(f['id'])!;
    expect(apres['modeMecef'], 'emecef');
    expect(apres.containsKey('modeleBoitierMecef'), isFalse);
  });

  casM14('la configuration MECeF affiche le modèle et « adaptateur ELTRADE CC300 : intégration à fournir par l’éditeur du boîtier » ; le modèle se règle et se versionne', (t) async {
    final m = magasin();
    await ouvrirM14(t, m, 'mecef-config', horloge: aujourdhui);
    expect(find.textContaining('Boîtier physique : ELTRADE CC300'), findsOneWidget);
    expect(find.byKey(const Key('mecef-adaptateur-boitier')), findsOneWidget);
    expect(find.textContaining('Adaptateur ELTRADE CC300 : intégration à fournir par l’éditeur du boîtier (adaptateur non configuré)'), findsOneWidget);
    await saisir(t, 'modele', 'ELTRADE CC300 v2');
    await toucherM14(t, find.widgetWithText(BoutonSigh, 'Enregistrer le mode'));
    expect(modeleBoitierDuPoste(m, aujourdhui), 'ELTRADE CC300 v2');
    expect(m.collection('parametres').toutes.where((v) => v['cle'] == mecefCleModeleBoitier && v['valeur'] == 'ELTRADE CC300 v2').length, 1);
    expect(m.collection('parametres').toutes.where((v) => v['cle'] == mecefCleMode && v['version'] != 0), isEmpty,
        reason: 'le mode inchangé n’ajoute pas de version');
  });
}
